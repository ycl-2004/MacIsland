import AppKit

/// Resolve just before a handoff, never in a mouse event's synchronous path.
@MainActor
struct ShelfPreparedDrag {
    let items: [ShelfItem]
    let writers: [NSPasteboardWriting]
    let fileURLs: [URL]
    let lease: ShelfFileLease
}

@MainActor
enum ShelfDragPreparation {
    static func prepare(_ requested: [ShelfItem], shelf: ShelfStateViewModel? = nil) async -> ShelfPreparedDrag? {
        guard !requested.isEmpty else { return nil }
        let shelf = shelf ?? .shared
        // Protect owned copies during preparation, including a concurrent Clear.
        let lease = ShelfFileLifetime.shared.acquire(requested.compactMap { $0.cachedPath.map { URL(fileURLWithPath: $0) } })
        defer { lease.finish() }
        var writers: [NSPasteboardWriting] = []
        var urls: [URL] = []
        var paths: [UUID: String] = [:]
        var sources: [UUID: Data] = [:]
        for item in requested {
            guard !Task.isCancelled else { return nil }
            switch item.kind {
            case .file(let bookmark):
                // No mount or permission dialogs may start from a drag gesture.
                // https://developer.apple.com/documentation/foundation/nsurl/bookmarkresolutionoptions
                let url = await Task.detached(priority: .userInitiated) {
                    guard let resolved = Bookmark(data: bookmark).resolveWithoutMounting(),
                          FileManager.default.fileExists(atPath: resolved.path) else { return URL?.none }
                    return resolved
                }.value
                guard !Task.isCancelled else { return nil }
                guard let url else {
                    shelf.report(String(localized: "This file is unavailable. Check its location or reconnect the drive."))
                    return nil
                }
                writers.append(url as NSURL)
                urls.append(url)
                paths[item.id] = url.standardizedFileURL.path
                sources[item.id] = bookmark
            case .text(let text): writers.append(text as NSString)
            case .link(let url): writers.append(url as NSURL)
            }
        }
        // A removed/renamed item must not start a late drag with an old snapshot.
        guard !Task.isCancelled, requested.allSatisfy({ candidate in
            shelf.items.contains { $0.id == candidate.id && $0.kind == candidate.kind }
        }) else { return nil }
        shelf.applyCachedPaths(paths, resolvedFrom: sources)
        let handoffLease = ShelfFileLifetime.shared.acquire(urls)
        return ShelfPreparedDrag(items: requested, writers: writers, fileURLs: urls, lease: handoffLease)
    }
}
