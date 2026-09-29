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

import AppKit
import Foundation
import UniformTypeIdentifiers

extension NSItemProvider {
    func extractItem() async -> URL? {
        await loadFileURL(typeIdentifier: UTType.item.identifier)
    }

    /// Detects if this is a file dragged from the filesystem
    func extractFileURL() async -> URL? {
        if hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return await loadFileURL(typeIdentifier: UTType.fileURL.identifier)
        }
        return nil
    }

    /// Copy within the completion; the provider owns and removes its source.
    /// Loading a file representation avoids buffering a whole attachment in RAM.
    func copyFileRepresentation() async -> URL? {
        guard let type = registeredTypeIdentifiers.first(where: {
            guard let type = UTType($0) else { return false }
            return type.conforms(to: .data) && !type.conforms(to: .url)
        }) else { return nil }
        let name = suggestedName
        return await providerValue { operation in
            let progress = self.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                guard !operation.isFinished, let url else { operation.finish(nil); return }
                let copy = TemporaryFileStorageService.shared.copyProviderFile(url, suggestedName: name)
                operation.finish(copy)
            }
            operation.track(progress)
        }
    }

    /// Attempts to extract a URL (web link) from the provider
    func extractURL() async -> URL? {
        if hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = await loadURL(typeIdentifier: UTType.url.identifier) {
                guard url.scheme != nil else { return nil }
                return url
            }
        }
        return nil
    }

    func extractText() async -> String? {
        let textTypes = [UTType.utf8PlainText.identifier, UTType.plainText.identifier]
        for typeIdentifier in textTypes where hasItemConformingToTypeIdentifier(typeIdentifier) {
            if let text = await loadText(typeIdentifier: typeIdentifier) {
                return text
            }
        }
        return nil
    }

    /// Loads a file URL from the provider for the given type identifier.
    func loadFileURL(typeIdentifier: String) async -> URL? {
        await providerValue { (cont: ProviderLoad<URL>) in
            loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    print("❌ Error loading item for type \(typeIdentifier): \(error.localizedDescription)")
                    cont.finish(nil)
                    return
                }
                var resolvedURL: URL?
                if let url = item as? URL {
                    resolvedURL = url
                } else if let data = item as? Data {
                    if let string = String(data: data, encoding: .utf8) {
                        if string.hasPrefix("/") { resolvedURL = URL(fileURLWithPath: string) }
                        else { resolvedURL = URL(string: string) }
                    }
                    if resolvedURL == nil {
                        let bookmark = Bookmark(data: data)
                        resolvedURL = bookmark.resolveWithoutMounting()
                    }
                } else if let string = item as? String {
                    resolvedURL = string.hasPrefix("/") ? URL(fileURLWithPath: string) : URL(string: string)
                }
                cont.finish(resolvedURL)
            }
        }
    }

    /// Loads a URL from the provider for the given type identifier.
    func loadURL(typeIdentifier: String) async -> URL? {
        await providerValue { (cont: ProviderLoad<URL>) in
            loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if error != nil {
                    cont.finish(nil)
                    return
                }
                if let url = item as? URL {
                    cont.finish(url)
                } else if let data = item as? Data {
                    if let string = String(data: data, encoding: .utf8) {
                        if let url = URL(string: string) {
                            cont.finish(url)
                            return
                        } else if string.hasPrefix("/") {
                            cont.finish(URL(fileURLWithPath: string))
                            return
                        }
                    }
                    cont.finish(nil)
                } else if let string = item as? String {
                    if let url = URL(string: string) {
                        cont.finish(url)
                    } else if string.hasPrefix("/") {
                        cont.finish(URL(fileURLWithPath: string))
                    } else {
                        cont.finish(nil)
                    }
                } else {
                    cont.finish(nil)
                }
            }
        }
    }

    /// Loads text from the provider for the given type identifier.
    func loadText(typeIdentifier: String) async -> String? {
        await providerValue { (cont: ProviderLoad<String>) in
            loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if error != nil {
                    cont.finish(nil)
                    return
                }
                if let string = item as? String {
                    cont.finish(string)
                } else if let data = item as? Data,
                          let string = String(data: data, encoding: .utf8) {
                    cont.finish(string)
                } else {
                    cont.finish(nil)
                }
            }
        }
    }
}

/// Exactly-once completion, even when a provider hangs, cancels or replies late.
/// Timers exist only while a provider is loading; cancellation releases the waiter.
private final class ProviderLoad<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value?, Never>?
    private var finished = false
    private var progress: Progress?
    private var timeout: DispatchWorkItem?

    var isFinished: Bool { lock.lock(); defer { lock.unlock() }; return finished }

    func install(_ continuation: CheckedContinuation<Value?, Never>) -> Bool {
        lock.lock()
        guard !finished else { lock.unlock(); continuation.resume(returning: nil); return false }
        self.continuation = continuation
        let timeout = DispatchWorkItem { [weak self] in self?.finish(nil) }
        self.timeout = timeout
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30, execute: timeout)
        return true
    }

    func track(_ progress: Progress) {
        lock.lock()
        let cancelled = finished
        if !cancelled { self.progress = progress }
        lock.unlock()
        if cancelled { progress.cancel() }
    }

    func finish(_ value: Value?) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        let progress = self.progress
        self.progress = nil
        timeout?.cancel(); timeout = nil
        lock.unlock()
        if value == nil { progress?.cancel() }
        continuation?.resume(returning: value)
    }
}

private func providerValue<Value>(_ start: (ProviderLoad<Value>) -> Void) async -> Value? {
    let operation = ProviderLoad<Value>()
    return await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
            if operation.install(continuation) {
                if Task.isCancelled { operation.finish(nil) }
                else { start(operation) }
            }
        }
    } onCancel: { operation.finish(nil) }
}
