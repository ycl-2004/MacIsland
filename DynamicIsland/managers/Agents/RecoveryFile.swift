import Foundation

/// Serial, bounded snapshots. A damaged file is never silently replaced by an
/// empty in-memory state. The caller surfaces the error and keeps editing open.
/// Saving stays refused until `load()` succeeds again, so the owner merges a
/// repaired file before writing over it.
actor RecoveryFile<Value: Codable & Sendable> {
    let url: URL
    let limit: Int
    private var loadFailure: Error?
    private var didLoad = false
    private let validate: @Sendable (Value) -> Bool

    init(url: URL, limit: Int, validate: @escaping @Sendable (Value) -> Bool = { _ in true }) {
        self.url = url; self.limit = limit; self.validate = validate
    }

    /// The last read failed, so `save` refuses until a new read succeeds.
    var readFailed: Bool { loadFailure != nil }

    func load() throws -> Value? {
        do {
            let value: Value?
            if FileManager.default.fileExists(atPath: url.path) {
                value = try JSONDecoder().decode(Value.self, from: PrivateContentFile.read(url, limit: limit))
            } else { value = nil }
            if let value, !validate(value) { throw CocoaError(.fileReadCorruptFile) }
            didLoad = true
            loadFailure = nil
            return value
        } catch { didLoad = true; loadFailure = error; throw error }
    }

    func save(_ value: Value) throws {
        if !didLoad { _ = try load() }
        if let loadFailure { throw loadFailure }
        guard validate(value) else { throw CocoaError(.fileWriteInvalidFileName) }
        let data = try JSONEncoder().encode(value)
        guard data.count <= limit else { throw PrivateContentFile.Failure.tooLarge(limit) }
        try PrivateContentFile.write(data, to: url)
    }
}
