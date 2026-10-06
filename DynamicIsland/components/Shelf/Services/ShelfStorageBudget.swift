import Foundation

/// Only copied provider data consumes this quota; ordinary Finder drops keep
/// references and do not copy the user's files into Atoll storage.
enum ShelfStorageBudget {
    static let maximumItemBytes = 100 * 1024 * 1024
    static let maximumOwnedBytes = 250 * 1024 * 1024
    static let lock = NSRecursiveLock()
    private static var reservedBytes = 0

    static func size(_ url: URL, limit: Int) throws -> Int {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
        if values.isSymbolicLink == true { return 0 }
        if values.isDirectory != true {
            guard values.isRegularFile == true else { throw CocoaError(.fileReadUnknown) }
            let size = values.fileSize ?? 0
            guard size <= limit else { throw PrivateContentFile.Failure.tooLarge(limit) }
            return size
        }
        guard let iterator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: []) else { throw CocoaError(.fileReadUnknown) }
        var total = 0, entries = 0
        for case let child as URL in iterator {
            entries += 1
            guard entries <= 10_000 else { throw CocoaError(.fileReadTooLarge) }
            let values = try child.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values.isRegularFile == true { total += values.fileSize ?? 0 }
            guard total <= limit else { throw PrivateContentFile.Failure.tooLarge(limit) }
        }
        return total
    }
    static func reserve(_ bytes: Int, root: URL) -> Bool {
        lock.withLock {
            guard let stored = try? size(root, limit: maximumOwnedBytes), stored + reservedBytes + bytes <= maximumOwnedBytes else { return false }
            reservedBytes += bytes
            return true
        }
    }
    static func release(_ bytes: Int) { lock.withLock { reservedBytes -= bytes } }

    /// Snapshot regular files with a bounded read loop. A source that grows
    /// during import cannot turn a 100 MB preflight into an unbounded copy.
    static func copy(_ source: URL, to destination: URL) throws {
        let source = source.standardizedFileURL
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw CocoaError(.fileReadUnsupportedScheme) }
        var copied = 0
        func file(_ source: URL, _ destination: URL) throws {
            let input = try FileHandle(forReadingFrom: source)
            defer { try? input.close() }
            try PrivateContentFile.prepareDirectory(destination.deletingLastPathComponent())
            guard FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
            let output = try FileHandle(forWritingTo: destination)
            defer { try? output.close() }
            while let data = try input.read(upToCount: 64 * 1024), !data.isEmpty {
                try Task.checkCancellation()
                copied += data.count
                guard copied <= maximumItemBytes else { throw PrivateContentFile.Failure.tooLarge(maximumItemBytes) }
                try output.write(contentsOf: data)
            }
        }
        if values.isDirectory != true {
            guard values.isRegularFile == true else { throw CocoaError(.fileReadUnknown) }
            try file(source, destination); return
        }
        try PrivateContentFile.prepareDirectory(destination)
        guard let iterator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { throw CocoaError(.fileReadUnknown) }
        var count = 0
        for case let child as URL in iterator {
            count += 1
            guard count <= 10_000 else { throw CocoaError(.fileReadTooLarge) }
            let relative = String(child.path.dropFirst(source.path.count + 1))
            let target = destination.appendingPathComponent(relative)
            let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw CocoaError(.fileReadUnsupportedScheme) }
            if values.isDirectory == true { try PrivateContentFile.prepareDirectory(target) }
            else {
                guard values.isRegularFile == true else { throw CocoaError(.fileReadUnknown) }
                try file(child, target)
            }
        }
    }

    static func permits(_ incomingBytes: Int, root: URL) -> Bool {
        guard incomingBytes <= maximumItemBytes else { return false }
        return (try? size(root, limit: maximumOwnedBytes)).map { $0 + reservedBytes + incomingBytes <= maximumOwnedBytes } ?? false
    }
}
