import AppKit
import Foundation

/// Serializes ownership and cleanup. No periodic sweep: one work item wakes at
/// the next expiry. Only files inside the app's Shelf directory can be deleted.
final class ShelfFileLifetime: @unchecked Sendable {
    static let shared = ShelfFileLifetime()
    static let handoffInterval: TimeInterval = 600

    private let queue = DispatchQueue(label: "Atoll.ShelfFiles", qos: .utility)
    let directory: URL
    private var ledgerURL: URL { directory.appendingPathComponent(".handoffs.json") }
    private var references: Set<URL> = []
    private var active: [UUID: Set<URL>] = [:]
    private var expirations: [String: Date] = [:]
    private var cleanupAllowed = false
    private var wake: DispatchWorkItem?
    private let now: @Sendable () -> Date
    let needsRecovery: Bool

    init(directory: URL = AtollTemporaryFiles.root.appendingPathComponent("Shelf"), now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory.resolvingSymlinksInPath().standardizedFileURL
        self.now = now
        let ledger = self.directory.appendingPathComponent(".handoffs.json")
        if FileManager.default.fileExists(atPath: ledger.path) {
            do {
                expirations = try JSONDecoder().decode([String: Date].self, from: Data(contentsOf: ledger))
                needsRecovery = false
            } catch { needsRecovery = true }
        } else { needsRecovery = false }
    }

    deinit { wake?.cancel() }

    func resourceCounts() async -> (active: Int, handoffs: Int, scheduled: Bool) {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: (self.active.count, self.expirations.count, self.wake != nil)) }
        }
    }

    func owns(_ url: URL) -> Bool {
        url.isFileURL && normalized(url).path.hasPrefix(directory.path + "/")
    }

    private func normalized(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    func setReferences(_ urls: [URL], allowCleanup: Bool) {
        queue.async {
            self.references = Set(urls.filter(self.owns).map(self.normalized))
            self.cleanupAllowed = allowCleanup && !self.needsRecovery
            self.sweep()
        }
    }

    func acquire(_ urls: [URL]) -> ShelfFileLease {
        let id = UUID()
        queue.async {
            let owned = Set(urls.filter(self.owns).map(self.normalized))
            guard !owned.isEmpty else { return }
            self.active[id] = owned
            // A crash must not turn an active handoff into immediate deletion.
            self.persist()
        }
        return ShelfFileLease(urls: urls, release: { [weak self] grace in
            self?.queue.async { [weak self] in
                guard let self, let owned = self.active.removeValue(forKey: id) else { return }
                for url in owned {
                    let expiry = self.now().addingTimeInterval(grace)
                    // Do not shorten an earlier successful handoff's grace.
                    if grace > 0 { self.expirations[url.path] = max(self.expirations[url.path] ?? .distantPast, expiry) }

                }
                self.sweep()
            }
        })
    }

    func requestCleanup() { queue.async { self.sweep() } }

    private func persist() {
        guard !needsRecovery else { return }
        var recorded = expirations
        for url in active.values.flatMap({ $0 }) {
            recorded[url.path] = max(recorded[url.path] ?? .distantPast, now().addingTimeInterval(Self.handoffInterval))
        }
        guard !recorded.isEmpty else {
            try? FileManager.default.removeItem(at: ledgerURL)
            return
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(recorded).write(to: ledgerURL, options: .atomic)
        } catch {
            // If protection cannot be recorded, retain files for this process.
            cleanupAllowed = false
            NSLog("Shelf handoff record could not be saved: %@", error.localizedDescription)
        }
    }

    private func sweep() {
        wake?.cancel()
        wake = nil
        let now = self.now()
        expirations = expirations.filter { $0.value > now }
        persist()
        guard cleanupAllowed else { return }
        var keep = references.union(active.values.reduce(into: Set<URL>()) { $0.formUnion($1) })
        keep.formUnion(expirations.keys.map { URL(fileURLWithPath: $0) })
        keep.insert(ledgerURL)
        AtollTemporaryFiles.removeEntries(of: directory, notIn: keep,
            createdBefore: now.addingTimeInterval(-AtollTemporaryFiles.unusedEntryMinimumAge))
        var next = expirations.values.filter { $0 > now }.min()
        // Also revisit newly created, abandoned imports once their creation grace ends.
        let entries = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        for entry in entries where entry != ledgerURL {
            let path = normalized(entry).path
            guard !keep.contains(where: { $0.path == path || $0.path.hasPrefix(path + "/") }) else { continue }
            let created = (try? entry.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let expiry = created.addingTimeInterval(AtollTemporaryFiles.unusedEntryMinimumAge + 1)
            if expiry > now { next = min(next ?? expiry, expiry) }
        }
        rmdir(directory.path)
        if let next {
            let work = DispatchWorkItem { [weak self] in self?.sweep() }
            wake = work
            queue.asyncAfter(deadline: .now() + max(1, next.timeIntervalSince(now)), execute: work)
        }
    }
}

/// Holds only successful security-scope starts, independently of file ownership.
/// Non-sandbox file URLs remain usable when startAccessing returns false.
final class ShelfFileLease: @unchecked Sendable {
    private let lock = NSLock()
    private var release: ((TimeInterval) -> Void)?
    private var scopedURLs: [URL]

    init(urls: [URL], release: @escaping (TimeInterval) -> Void) {
        scopedURLs = urls.filter { $0.isFileURL && $0.startAccessingSecurityScopedResource() }
        self.release = release
    }

    func finish(handoff: Bool = false) {
        lock.lock()
        let callback = release
        release = nil
        let urls = scopedURLs
        scopedURLs = []
        lock.unlock()
        urls.forEach { $0.stopAccessingSecurityScopedResource() }
        callback?(handoff ? ShelfFileLifetime.handoffInterval : 0)
    }

    deinit { finish() }
}

/// Pasteboard ownership callbacks release copied files without an idle poller.
@MainActor
final class ShelfClipboard: NSObject {
    static let shared = ShelfClipboard()
    private final class Ownership: NSObject {
        let lease: ShelfFileLease
        var active = true
        init(lease: ShelfFileLease) { self.lease = lease }
        func finish(handoff: Bool) {
            guard active else { return }
            active = false
            lease.finish(handoff: handoff)
        }
        @objc func pasteboardChangedOwner(_ sender: NSPasteboard) { finish(handoff: true) }
    }

    private var owner: Ownership?
    private let pasteboard: NSPasteboard
    private let lifetime: ShelfFileLifetime

    init(pasteboard: NSPasteboard = .general, lifetime: ShelfFileLifetime = .shared) {
        self.pasteboard = pasteboard
        self.lifetime = lifetime
        super.init()
    }

    var holdsFiles: Bool { owner?.active == true }

    func write(_ objects: [NSPasteboardWriting], fileURLs: [URL]) -> Bool {
        let next = Ownership(lease: lifetime.acquire(fileURLs))
        pasteboard.clearContents()
        owner?.finish(handoff: true)
        owner = next
        let types = Array(Set(objects.flatMap { $0.writableTypes(for: pasteboard) }))
        pasteboard.declareTypes(types, owner: next)
        let written = pasteboard.writeObjects(objects)
        if !written { next.finish(handoff: false) }
        return written
    }
}
