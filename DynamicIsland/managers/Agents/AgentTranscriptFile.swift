import Foundation

/// Reads the end of an agent's JSONL transcript. Each source turns the rows
/// into conversation lines (`AgentSource.transcript(from:)`).
enum AgentTranscriptFile {
    /// Only the end of a long transcript is read; it holds the recent turns.
    static let tailBytes: UInt64 = 1 << 20

    /// The raw end of the file, read off the main thread by callers.
    static func tail(path: String, bytes tailBytes: UInt64 = tailBytes) -> Data? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > tailBytes ? size - tailBytes : 0
        guard (try? handle.seek(toOffset: start)) != nil, var data = try? handle.readToEnd() else { return nil }
        // A read that starts mid-file starts mid-line.
        if start > 0, let newline = data.firstIndex(of: 0x0A) { data = data.suffix(from: data.index(after: newline)) }
        return data
    }

    static func rows(_ data: Data) -> [[String: Any]] {
        data.split(separator: 0x0A).compactMap { try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any] }
    }
}
