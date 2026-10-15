import Foundation
import Darwin

/// Serializes cross-process discovery updates. An old app may only remove the
/// record it owns, even when a replacement has published before it exits.
struct BridgeDiscoveryLease {
    let directory: URL
    let owner: String

    func publish(port: UInt16, token: String) throws {
        try locked {
            try write(owner, name: "owner")
            // Remove old discovery first: readers can fail closed during handoff,
            // but can never trust a half-published new port as a ready service.
            try remove("port")
            try write("Authorization: Bearer \(token)\n", name: "auth-header")
            try write(String(port), name: "port")
        }
    }

    func release() throws {
        try locked {
            let current = try? String(contentsOf: directory.appendingPathComponent("owner"), encoding: .utf8)
            guard current == owner else { return }
            try remove("port")
            try remove("auth-header")
            try remove("owner")
        }
    }

    private func remove(_ name: String) throws {
        let url = directory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    private func write(_ text: String, name: String) throws {
        try PrivateContentFile.write(Data(text.utf8), to: directory.appendingPathComponent(name), keepingPrevious: false)
    }
    private func locked(_ operation: () throws -> Void) throws {
        try PrivateContentFile.prepareDirectory(directory)
        let fd = open(directory.appendingPathComponent("discovery.lock").path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        // No UI-thread wait behind another process's stalled storage operation.
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw POSIXError(.EBUSY) }
        defer { flock(fd, LOCK_UN) }
        try operation()
    }
}
