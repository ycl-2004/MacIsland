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
import Combine
import Defaults

@MainActor
final class ShelfStateViewModel: ObservableObject {
    static let shared = ShelfStateViewModel()

    @Published private(set) var items: [ShelfItem] = [] {
        didSet {
            if isLoaded { scheduleSave() }
            ShelfSelectionModel.shared.reconcileSelection(with: items)
            removeUnusedTemporaryFiles()
            if items.isEmpty { Task { await thumbnails.clear() } }
        }
    }

    @Published private(set) var isLoaded = false
    static let maximumItems = 200
    private let persistenceQueue = DispatchQueue(label: "app.atoll.shelf.persistence", qos: .utility)
    private var pendingSave: DispatchWorkItem?
    var isEmpty: Bool { items.isEmpty }

    @Published private(set) var feedback: String?
    private var feedbackTask: Task<Void, Never>?
    static let maximumConcurrentImports = 3
    private var importTasks: [UUID: Task<Void, Never>] = [:]
    private var importFlushTask: Task<Void, Never>?
    private var pendingImports: [ShelfItem] = []
    private var importTotal = 0
    private var importCompleted = 0
    private var importAdded = 0
    private var importFailures = 0
    private var importLimitReached = false
    private var importGeneration = UUID()
    private var contentGeneration = UUID()
    private var importWasLimited = false
    private var importQueue: [NSItemProvider] = []
    var isImporting: Bool { !importTasks.isEmpty || !importQueue.isEmpty }
    var generation: UUID { importGeneration }

    func report(_ message: String, persistent: Bool = false) {
        feedbackTask?.cancel()
        // A successful drop notice must not hide a failed save or recovery warning.
        if let issue = persistence.lastError ?? persistence.recoveryWarning {
            feedback = issue
            return
        }
        if fileLifetime.needsRecovery {
            feedback = String(localized: "Temporary file records could not be read. Files have been kept for recovery.")
            return
        }
        feedback = message
        guard !persistent else { return }
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.feedback = nil
        }
    }

    // Queue for deferred bookmark updates to avoid publishing during view updates
    private var pendingBookmarkUpdates: [ShelfItem.ID: (bookmark: Data, path: String?, source: Data)] = [:]
    private var updateTask: Task<Void, Never>?
    private var shelfSwitch: AnyCancellable?

    private let persistence: ShelfPersistenceService
    private let fileLifetime: ShelfFileLifetime
    private let enabledKey: Defaults.Key<Bool>
    private let thumbnails: ThumbnailService

    init(persistence: ShelfPersistenceService = .shared, lifetime: ShelfFileLifetime = .shared,
         enabledKey: Defaults.Key<Bool> = .dynamicShelf, thumbnails: ThumbnailService = .shared) {
        self.persistence = persistence
        self.fileLifetime = lifetime
        self.enabledKey = enabledKey
        self.thumbnails = thumbnails
        let generation = contentGeneration
        persistenceQueue.async { [weak self] in
            let loaded = persistence.load()
            DispatchQueue.main.async {
                guard let self else { return }
                if self.contentGeneration == generation { self.items = loaded }
                self.isLoaded = true
                if let issue = self.persistence.lastError ?? self.persistence.recoveryWarning {
                    self.report(issue, persistent: true)
                }
                self.backfillCachedPaths()
            }
        }
        // Hiding the shelf preserves its persisted references. Only explicit
        // Clear removes entries; active handoffs retain their existing leases.
        shelfSwitch = Defaults.publisher(enabledKey).sink { [weak self] change in
            Task { @MainActor in
                guard let self else { return }
                let enabled = Defaults[self.enabledKey]
                if !enabled { self.pauseImports() }
                await self.thumbnails.setEnabled(enabled)
            }
        }
    }

    /// Removes shelf temporary files no item uses: left by a crash, by items
    /// removed while Atoll was not running, or handed to another app and past
    /// their grace period.
    private func removeUnusedTemporaryFiles() {
        let unresolved = items.contains { $0.isTemporary && $0.cachedPath == nil }
        fileLifetime.setReferences(items.compactMap { $0.cachedPath.map { URL(fileURLWithPath: $0) } },
            allowCleanup: !unresolved && persistence.permitsCleanup)
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let snapshot = items
        let persistence = self.persistence
        let work = DispatchWorkItem { [weak self] in
            let success = persistence.save(snapshot)
            if !success {
                DispatchQueue.main.async { self?.report(persistence.lastError ?? "Shelf changes could not be saved.", persistent: true) }
            }
        }
        pendingSave = work
        persistenceQueue.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func flushPendingSave() {
        guard isLoaded else { return }
        pendingSave?.cancel(); pendingSave = nil
        let snapshot = items
        if !persistenceQueue.sync(execute: { persistence.save(snapshot) }) {
            report(persistence.lastError ?? "Shelf changes could not be saved.", persistent: true)
        }
    }

    func awaitInitialLoad() async {
        await withCheckedContinuation { continuation in
            persistenceQueue.async {
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    func saveForTermination() async -> String? {
        await awaitInitialLoad()
        guard isLoaded else { return nil }
        pendingSave?.cancel(); pendingSave = nil
        let snapshot = items, persistence = persistence
        let success: Bool = await withCheckedContinuation { continuation in
            persistenceQueue.async { continuation.resume(returning: persistence.save(snapshot)) }
        }
        if !success {
            let error = persistence.lastError ?? "Shelf changes could not be saved."
            report(error, persistent: true)
            return error
        }
        return items == snapshot ? nil : "Shelf changed while saving. Please try again."
    }

    /// Resolves `cachedPath` for items persisted before the path cache existed,
    /// off the main actor. Once this lands, `identityKey` and `resolvedFileURL`
    /// never touch the disk on the main actor — which is what keeps an
    /// unreachable network mount from stalling the UI.
    ///
    /// The temporary-file sweep waits for it: until every item has a path, no
    /// file can be ruled out.
    private func backfillCachedPaths() {
        let pending: [(ShelfItem.ID, Data)] = items.compactMap { item in
            guard item.cachedPath == nil, case .file(let data) = item.kind else { return nil }
            return (item.id, data)
        }
        guard !pending.isEmpty else {
            removeUnusedTemporaryFiles()
            return
        }

        Task.detached(priority: .utility) {
            var resolved: [ShelfItem.ID: String] = [:]
            var sources: [ShelfItem.ID: Data] = [:]
            for (itemID, data) in pending {
                if let url = Bookmark(data: data).resolve().url {
                    resolved[itemID] = url.standardizedFileURL.path
                    sources[itemID] = data
                }
            }
            // Hand the closure immutable copies: capturing the `var`s directly is
            // already a warning and becomes an error in the Swift 6 language mode.
            let paths = resolved
            let bookmarks = sources
            await MainActor.run {
                let shelf = ShelfStateViewModel.shared
                shelf.applyCachedPaths(paths, resolvedFrom: bookmarks)
                shelf.removeUnusedTemporaryFiles()
            }
        }
    }

    /// Applies resolved paths in a single mutation — writing `items[idx]` inside
    /// a loop would fire `didSet` (and a full JSON save) once per item.
    ///
    /// `sources` carries the bookmark each path was resolved from, and an entry
    /// only lands while the item still holds that bookmark. Every caller resolves
    /// off the main actor, so a resolve that started before a rename can finish
    /// *after* `updateBookmark` recorded the new bookmark and path; without the
    /// check it would put the pre-rename path back, and `resolvedFileURL` prefers
    /// `cachedPath` — so drag-out and the context menu would target the old
    /// location.
    func applyCachedPaths(_ paths: [ShelfItem.ID: String], resolvedFrom sources: [ShelfItem.ID: Data]) {
        guard !paths.isEmpty else { return }
        var updated = items
        var changed = false
        for idx in updated.indices {
            let id = updated[idx].id
            guard let path = paths[id], updated[idx].cachedPath != path else { continue }
            guard case .file(let current) = updated[idx].kind, current == sources[id] else { continue }
            updated[idx].cachedPath = path
            changed = true
        }
        if changed {
            items = updated
        }
    }

    func applyCachedPath(_ path: String, for itemID: ShelfItem.ID, resolvedFrom source: Data) {
        applyCachedPaths([itemID: path], resolvedFrom: [itemID: source])
    }

    func add(_ newItems: [ShelfItem], ifUnchanged generation: UUID? = nil) {
        importWasLimited = false
        guard !newItems.isEmpty else { return }
        guard (generation == nil || generation == importGeneration), Defaults[enabledKey] else {
            fileLifetime.requestCleanup()
            return
        }
        var merged = items
        // Deduplicate by identityKey while preserving order (existing first)
        var seen: Set<String> = Set(merged.map { $0.identityKey })
        var textBytes = merged.reduce(0) { $0 + $1.storageTextBytes }
        var added = false
        for it in newItems where seen.insert(it.identityKey).inserted {
            guard merged.count < Self.maximumItems, it.storageTextBytes <= 1024 * 1024,
                  textBytes + it.storageTextBytes <= 4 * 1024 * 1024 else {
                importWasLimited = true
                report("Shelf holds up to 200 items and 4 MB of text (1 MB per item). Remove some items before adding more.")
                fileLifetime.requestCleanup()
                break
            }
            merged.append(it)
            textBytes += it.storageTextBytes
            added = true
        }
        // Every duplicate-only drop would otherwise trigger a save and a publish.
        guard added else { return }
        items = merged
    }

    /// Removes the reference; the lifetime service reclaims unused owned data.
    func remove(_ item: ShelfItem) {
        remove([item])
    }

    func remove(_ removed: [ShelfItem]) {
        let ids = Set(removed.map(\.id))
        guard items.contains(where: { ids.contains($0.id) }) else { return }
        items.removeAll { ids.contains($0.id) }
    }

    /// Takes items just dragged into another app off the shelf. Their temporary
    /// files remain protected by the drag session's lease and handoff grace.
    func removeAfterHandOff(_ handedOff: [ShelfItem]) {
        remove(handedOff)
    }

    func pauseImports() {
        importGeneration = UUID()
        importTasks.values.forEach { $0.cancel() }
        importTasks.removeAll()
        importFlushTask?.cancel()
        importFlushTask = nil
        pendingImports.removeAll()
        importQueue.removeAll()
        if importTotal > importCompleted {
            feedbackTask?.cancel()
            feedback = persistence.lastError ?? persistence.recoveryWarning
            if fileLifetime.needsRecovery {
                report(String(localized: "Temporary file records could not be read. Files have been kept for recovery."), persistent: true)
            }
        }
        importTotal = 0
        importCompleted = 0
        fileLifetime.requestCleanup()
        Task { await thumbnails.clear() }
    }

    /// Active drags, shares and clipboard ownership retain their own file leases.
    func removeAll() {
        contentGeneration = UUID()
        pauseImports()
        updateTask?.cancel()
        pendingBookmarkUpdates.removeAll()
        if !items.isEmpty { items.removeAll() }
        else { removeUnusedTemporaryFiles() }
        Task { await thumbnails.clear() }
    }

    /// Pass `path` whenever the caller already resolved the new bookmark —
    /// leaving `cachedPath` pointing at the old location would make dedup treat
    /// a renamed file as a new one.
    ///
    /// Pass `resolvedFrom` when `bookmark` is the *refreshed form of an older
    /// bookmark* obtained off the main actor: the write is then skipped unless the
    /// item still holds that older bookmark, so a resolve that began before a
    /// rename cannot put the pre-rename bookmark and path back. Omit it for
    /// authoritative writes — the rename flow has already moved the file on disk,
    /// and its data is by definition the freshest, so discarding that write
    /// because something else refreshed the bookmark while the rename was being
    /// typed would lose the rename instead of protecting it.
    func updateBookmark(for item: ShelfItem, bookmark: Data, path: String? = nil, resolvedFrom source: Data? = nil) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard case .file(let current) = items[idx].kind else { return }
        if let source, current != source { return }
        let newPath = path ?? Bookmark(data: bookmark).resolveWithoutMounting()?.standardizedFileURL.path
        // `items.didSet` writes the whole shelf JSON, so mutating `kind` and
        // `cachedPath` as two statements saves twice and — in between — persists
        // the new bookmark paired with the old path.
        var updated = items
        updated[idx].kind = .file(bookmark: bookmark)
        updated[idx].cachedPath = newPath
        if let newPath { updated[idx].cachedDisplayName = URL(fileURLWithPath: newPath).lastPathComponent }
        updated[idx].cachedIconData = nil
        let oldPath = items[idx].cachedPath
        Task {
            if let oldPath { await ThumbnailService.shared.invalidate(URL(fileURLWithPath: oldPath)) }
            if let newPath, newPath != oldPath { await ThumbnailService.shared.invalidate(URL(fileURLWithPath: newPath)) }
        }
        items = updated
    }

    private func scheduleDeferredBookmarkUpdate(for item: ShelfItem, bookmark: Data, path: String?, resolvedFrom source: Data) {
        pendingBookmarkUpdates[item.id] = (bookmark, path, source)

        // Cancel existing task and schedule a new one
        updateTask?.cancel()
        updateTask = Task { @MainActor [weak self] in
            await Task.yield()

            guard let self = self else { return }

            let updates = self.pendingBookmarkUpdates
            self.pendingBookmarkUpdates.removeAll()
            guard !updates.isEmpty else { return }

            // Same reason as `updateBookmark`: one assignment, so the coalesced
            // batch costs a single save instead of two per item.
            var updated = self.items
            var changed = false
            for (itemID, update) in updates {
                guard let idx = updated.firstIndex(where: { $0.id == itemID }),
                      case .file(let current) = updated[idx].kind else { continue }
                // Revalidated after the suspension above, not just at schedule
                // time: the item may have been renamed while this was queued, in
                // which case the refresh is a resolve of the pre-rename bookmark.
                guard current == update.source else { continue }
                updated[idx].kind = .file(bookmark: update.bookmark)
                if let path = update.path { updated[idx].cachedPath = path }
                changed = true
            }

            guard changed else { return }
            self.items = updated
        }
    }

    @discardableResult
    func load(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty, Defaults[enabledKey] else { return false }
        guard providers.count <= 50, importQueue.count + importTasks.count + providers.count <= 100 else {
            report("Drop up to 50 items at a time. Wait for the current import to finish before adding more.")
            return false
        }
        if !isImporting {
            importTotal = 0; importCompleted = 0; importAdded = 0; importFailures = 0
            importLimitReached = false
        }
        importTotal += providers.count
        importQueue.append(contentsOf: providers)
        reportImportProgress()
        startImports()
        return true
    }

    private func reportImportProgress() {
        guard !importLimitReached else { return }
        report(String(localized: "Importing \(importCompleted) of \(importTotal) items…"), persistent: true)
    }

    private func startImports() {
        let generation = importGeneration
        while importTasks.count < Self.maximumConcurrentImports, !importQueue.isEmpty {
            let id = UUID(), provider = importQueue.removeFirst()
            importTasks[id] = Task { [weak self] in
                guard let self else { return }
                await self.awaitInitialLoad()
                guard !Task.isCancelled, self.importGeneration == generation else { return }
                let item = await ShelfDropService.item(from: provider)
                guard !Task.isCancelled, self.importGeneration == generation, Defaults[self.enabledKey] else {
                    // Disabled before the switch observer paused: this task still
                    // owns a slot, and a quick re-enable would otherwise leak it.
                    if self.importGeneration == generation { self.pauseImports() }
                    else { self.fileLifetime.requestCleanup() }
                    return
                }
                self.importTasks[id] = nil
                self.importCompleted += 1
                if let item { self.pendingImports.append(item) } else { self.importFailures += 1 }
                self.startImports()
                if !self.isImporting {
                    self.flushImports()
                } else if self.importFlushTask == nil {
                    // Coalesce fast completions into one view/persistence update per frame.
                    self.importFlushTask = Task { [weak self] in
                        try? await Task.sleep(for: .milliseconds(16))
                        guard !Task.isCancelled, let self, self.importGeneration == generation else { return }
                        self.flushImports()
                    }
                }
            }
        }
    }

    private func flushImports() {
        importFlushTask?.cancel(); importFlushTask = nil
        let completed = pendingImports
        pendingImports.removeAll()
        let before = items.count
        add(completed, ifUnchanged: importGeneration)
        importAdded += items.count - before
        importLimitReached = importLimitReached || importWasLimited
        guard !importLimitReached else { return }
        if isImporting { reportImportProgress() }
        else if importFailures > 0 {
            report(String(localized: "Added \(importAdded) items. \(importFailures) items could not be read; try dropping them from Finder."))
        } else if importAdded == 0 {
            report(String(localized: "These items are already on the Shelf."))
        } else {
            report(String(localized: "Added \(importAdded) items to Shelf."))
        }
    }

    // Unavailable volumes or revoked permissions must not erase saved items.
    // File access is retried when the user opens, previews or shares an item.

    // Async version that resolves bookmark on background thread
    func resolveFileURLAsync(for item: ShelfItem) async -> URL? {
        guard case .file(let bookmarkData) = item.kind else { return nil }
        let bookmark = Bookmark(data: bookmarkData)
        let result = await bookmark.resolveAsync()
        let path = result.url?.standardizedFileURL.path
        if let refreshed = result.refreshedData, refreshed != bookmarkData {
            NSLog("Bookmark for \(item) stale; refreshing")
            scheduleDeferredBookmarkUpdate(for: item, bookmark: refreshed, path: path, resolvedFrom: bookmarkData)
        } else if let path {
            // Self-healing: the file may have moved since the path was cached.
            applyCachedPath(path, for: item.id, resolvedFrom: bookmarkData)
        }
        return result.url
    }

    // Async version for user-initiated actions
    func resolveAndUpdateBookmarkAsync(for item: ShelfItem) async -> URL? {
        guard case .file(let bookmarkData) = item.kind else { return nil }
        let bookmark = Bookmark(data: bookmarkData)
        let result = await bookmark.resolveAsync()
        let path = result.url?.standardizedFileURL.path
        if let refreshed = result.refreshedData, refreshed != bookmarkData {
            NSLog("Bookmark for \(item) stale; refreshing")
            updateBookmark(for: item, bookmark: refreshed, path: path, resolvedFrom: bookmarkData)
        } else if let path {
            applyCachedPath(path, for: item.id, resolvedFrom: bookmarkData)
        }
        return result.url
    }
}
