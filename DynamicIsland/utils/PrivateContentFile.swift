import Foundation

/// App-owned content only. Check file size before allocating its contents;
/// preserve a damaged predecessor and keep one last known-good revision.
enum PrivateContentFile {
    enum Failure: LocalizedError {
        case tooLarge(Int)
        var errorDescription: String? {
            switch self { case .tooLarge(let limit): return "This content exceeds the \(limit / 1024 / 1024) MB limit. The original file has been kept. Export it or reduce its size before loading it." }
        }
    }
    static func read(_ url: URL, limit: Int) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= limit else { throw Failure.tooLarge(limit) }
        let data = try Data(contentsOf: url)
        guard data.count <= limit else { throw Failure.tooLarge(limit) }
        return data
    }
    static func prepareDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
    static func write(_ data: Data, to url: URL, keepingPrevious: Bool = true) throws {
        try prepareDirectory(url.deletingLastPathComponent())
        // Never replace a backup until a complete new snapshot is available.
        if keepingPrevious, FileManager.default.fileExists(atPath: url.path) {
            let previous = try Data(contentsOf: url, options: .mappedIfSafe)
            try previous.write(to: backupURL(url), options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL(url).path)
        }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func backupURL(_ url: URL) -> URL { url.appendingPathExtension("previous") }
}
