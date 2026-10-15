import Foundation
import Darwin

/// Bounded FIFO above DispatchIO: only one frame is handed to the I/O channel.
/// DispatchIO performs the pipe writes asynchronously and .stop interrupts I/O.
/// Source: https://developer.apple.com/documentation/dispatch/dispatch_io_close
@MainActor
final class CodexPipeWriter {
    static let maximumMessageBytes = 512 * 1024
    static let maximumQueuedBytes = 1024 * 1024
    static let maximumQueuedMessages = 64

    private struct Entry {
        let token: UUID
        let data: Data
        let deadline: TimeInterval
    }

    private let channel: DispatchIO
    private let onFailure: (Error) -> Void
    private var active: Entry?
    private var waiting: [Entry] = []
    private var queuedBytes = 0
    private var deadlineTask: Task<Void, Never>?
    private var stopped = false

    init(handle: FileHandle, onFailure: @escaping (Error) -> Void) throws {
        let fd = fcntl(handle.fileDescriptor, F_DUPFD_CLOEXEC, 0)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        // Local to this pipe; do not change the app's SIGPIPE disposition.
        // Source: https://github.com/apple-oss-distributions/xnu/blob/main/bsd/man/man2/fcntl.2
        guard fcntl(fd, F_SETNOSIGPIPE, 1) != -1 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            Darwin.close(fd)
            throw error
        }
        channel = DispatchIO(type: .stream, fileDescriptor: fd, queue: .global(qos: .utility)) { _ in
            Darwin.close(fd)
        }
        self.onFailure = onFailure
    }

    deinit { channel.close(flags: .stop) }

    func enqueue(_ data: Data, token: UUID = UUID(), timeout: TimeInterval = 12) throws {
        guard !stopped else { throw AgentConnectionError.unavailable("Codex is disconnected.") }
        guard data.count <= Self.maximumMessageBytes else {
            throw AgentConnectionError.unavailable("The Codex message is too large to send.")
        }
        guard waiting.count + (active == nil ? 0 : 1) < Self.maximumQueuedMessages,
              data.count <= Self.maximumQueuedBytes - queuedBytes else {
            throw AgentConnectionError.unavailable("Codex is not reading messages fast enough. Please try again later.")
        }
        waiting.append(Entry(token: token, data: data, deadline: ProcessInfo.processInfo.systemUptime + timeout))
        queuedBytes += data.count
        startNext()
    }

    /// An unstarted frame can be removed. An active frame may already be
    /// partially written, so its cancellation requires closing the transport.
    func cancel(_ token: UUID) -> Bool {
        if active?.token == token { stop(); return true }
        if let index = waiting.firstIndex(where: { $0.token == token }) {
            queuedBytes -= waiting.remove(at: index).data.count
        }
        return false
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        deadlineTask?.cancel(); deadlineTask = nil
        active = nil
        waiting.removeAll()
        queuedBytes = 0
        channel.close(flags: .stop)
    }

    private func startNext() {
        guard !stopped, active == nil, !waiting.isEmpty else { return }
        let entry = waiting.removeFirst()
        active = entry
        let remaining = entry.deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else { fail(AgentConnectionError.unavailable("Codex pipe write timed out.")); return }
        deadlineTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
            guard let self, self.active?.token == entry.token else { return }
            self.fail(AgentConnectionError.unavailable("Codex pipe write timed out."))
        }
        let data = entry.data.withUnsafeBytes { DispatchData(bytes: $0) }
        channel.write(offset: 0, data: data, queue: .main) { [weak self] done, _, error in
            guard let self, !self.stopped, self.active?.token == entry.token else { return }
            if error != 0 { self.fail(POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO)); return }
            guard done else { return }
            self.deadlineTask?.cancel(); self.deadlineTask = nil
            self.queuedBytes -= entry.data.count
            self.active = nil
            self.startNext()
        }
    }

    private func fail(_ error: Error) { stop(); onFailure(error) }
}
