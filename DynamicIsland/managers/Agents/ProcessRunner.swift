import Foundation

/// Runs a `Process` to completion without blocking a thread. Cancelling the
/// calling task terminates the process, and so does the optional timeout.
enum ProcessRunner {
    enum Outcome: Equatable {
        case exited(Int32)
        case timedOut
    }

    static func run(_ process: Process, timeout: TimeInterval? = nil) async throws -> Outcome {
        let timedOut = Flag()
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                    return
                }
                guard let timeout else { return }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    guard process.isRunning else { return }
                    timedOut.set()
                    process.terminate()
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        try Task.checkCancellation()
        return timedOut.isSet ? .timedOut : .exited(status)
    }

    /// Set from the timeout's queue, read once the process has exited.
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool { lock.withLock { value } }
        func set() { lock.withLock { value = true } }
    }
}
