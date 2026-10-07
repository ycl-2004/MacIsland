/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// A small, explicitly bounded LRU with at most two Quick Look requests running.
/// Each visible card is a cancellable consumer; queued work with no consumers dies.
actor ThumbnailService {
    static let shared = ThumbnailService()
    static let maximumEntries = 48
    static let maximumBytes = 8 * 1024 * 1024
    static let maximumConcurrent = 2
    static let maximumPending = 256
    static let maximumConsumersPerRequest = 32

    private struct Cached {
        let image: NSImage
        let bytes: Int
    }
    private struct Pending {
        let id = UUID()
        let request: QLThumbnailGenerator.Request
        let url: URL
        var consumers: [UUID: CheckedContinuation<NSImage?, Never>]
        var lease: ShelfFileLease?
        var timeout: Task<Void, Never>?
    }
    private var cache: [String: Cached] = [:]
    private var lru: [String] = []
    private var bytes = 0
    private var pending: [String: Pending] = [:]
    private var waiting: [String] = []
    private var running: Set<String> = []
    private var isEnabled = true
    private let generator = QLThumbnailGenerator.shared
    private let lifetime: ShelfFileLifetime
    private let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))

    init(lifetime: ShelfFileLifetime = .shared) {
        self.lifetime = lifetime
        pressure.setEventHandler { [weak self] in Task { await self?.clear() } }
        pressure.resume()
    }

    deinit { pressure.cancel() }

    func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        guard isEnabled, !Task.isCancelled else { return nil }
        let version = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .fileResourceIdentifierKey])
        let key = "\(url.standardizedFileURL.path)_\(size.width)x\(size.height)_\(version?.contentModificationDate?.timeIntervalSince1970 ?? 0)_\(version?.fileSize ?? 0)_\(String(describing: version?.fileResourceIdentifier))"
        if let hit = cache[key] {
            lru.removeAll { $0 == key }; lru.append(key)
            return hit.image
        }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled { continuation.resume(returning: nil); return }
                if let work = pending[key] {
                    guard work.consumers.count < Self.maximumConsumersPerRequest else { continuation.resume(returning: nil); return }
                    pending[key]?.consumers[id] = continuation
                } else {
                    guard pending.count < Self.maximumPending else { continuation.resume(returning: nil); return }
                    let bounded = CGSize(width: min(128, size.width), height: min(128, size.height))
                    let request = QLThumbnailGenerator.Request(fileAt: url, size: bounded, scale: 2, representationTypes: .all)
                    request.iconMode = true
                    pending[key] = Pending(request: request, url: url, consumers: [id: continuation])
                    waiting.append(key)
                }
                startNext()
            }
        } onCancel: {
            Task { await self.cancel(key: key, consumer: id) }
        }
    }

    private func startNext() {
        while running.count < Self.maximumConcurrent, !waiting.isEmpty {
            let key = waiting.removeFirst()
            guard var work = pending[key] else { continue }
            running.insert(key)
            work.lease = lifetime.acquire([work.url])
            let request = work.request
            let id = work.id
            work.timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                await self?.complete(key: key, id: id, image: nil)
            }
            pending[key] = work
            generator.generateBestRepresentation(for: request) { [weak self] representation, _ in
                let image = representation.map { NSImage(cgImage: $0.cgImage, size: sizeForImage($0.cgImage)) }
                Task { await self?.complete(key: key, id: id, image: image) }
            }
        }
    }

    private func complete(key: String, id: UUID, image: NSImage?) {
        // Ignore callbacks from cancelled requests replaced under the same key.
        guard let work = pending[key], work.id == id else { return }
        pending[key] = nil
        running.remove(key)
        waiting.removeAll { $0 == key }
        work.timeout?.cancel()
        if image == nil { generator.cancel(work.request) }
        work.lease?.finish()
        if let image {
            let cost = image.representations.reduce(0) { total, rep in
                total + ((rep as? NSBitmapImageRep).map { $0.bytesPerRow * $0.pixelsHigh } ?? 0)
            }
            // CG-backed images can have non-bitmap representations; reserve RGBA bytes.
            let reserved = max(cost, Int(image.size.width * image.size.height) * 4)
            if reserved <= Self.maximumBytes {
                while cache.count >= Self.maximumEntries || bytes + reserved > Self.maximumBytes {
                    guard let oldest = lru.first else { break }
                    lru.removeFirst()
                    bytes -= cache.removeValue(forKey: oldest)?.bytes ?? 0
                }
                cache[key] = Cached(image: image, bytes: reserved)
                lru.append(key)
                bytes += reserved
            }
        }
        work.consumers.values.forEach { $0.resume(returning: image) }
        startNext()
    }

    private func cancel(key: String, consumer: UUID) {
        pending[key]?.consumers.removeValue(forKey: consumer)?.resume(returning: nil)
        if let work = pending[key], work.consumers.isEmpty { complete(key: key, id: work.id, image: nil) }
    }

    func invalidate(_ url: URL) {
        let prefix = url.standardizedFileURL.path + "_"
        let keys = cache.keys.filter { $0.hasPrefix(prefix) }
        for key in keys {
            bytes -= cache.removeValue(forKey: key)?.bytes ?? 0
            lru.removeAll { $0 == key }
        }
        for (key, work) in pending.filter({ $0.key.hasPrefix(prefix) }) {
            complete(key: key, id: work.id, image: nil)
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled { clear() }
    }

    func clear() {
        cache.removeAll(); lru.removeAll(); bytes = 0
        waiting.removeAll()
        let work = pending
        pending.removeAll(); running.removeAll()
        for value in work.values {
            value.timeout?.cancel()
            generator.cancel(value.request)
            value.lease?.finish()
            value.consumers.values.forEach { $0.resume(returning: nil) }
        }
    }

    func resourceCounts() -> (cached: Int, bytes: Int, running: Int, queued: Int) {
        (cache.count, bytes, running.count, waiting.count)
    }
}

private func sizeForImage(_ image: CGImage) -> NSSize {
    NSSize(width: image.width, height: image.height)
}
