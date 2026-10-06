import Foundation
import Darwin

/// Owns only the child it launches. Cancellation and deadlines first ask the
/// child to exit, then kill that same child after a short grace period.
enum ProcessRunner {
    enum Outcome: Equatable { case exited(Int32), timedOut }
    struct Captured {
        let outcome: Outcome
        let output: Data
        let errors: Data
        let truncated: Bool
    }

    static func run(_ process: Process, timeout: TimeInterval? = nil) async throws -> Outcome {
        let execution = Execution(process)
        let outcome = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { execution.start($0, timeout: timeout) }
        } onCancel: { execution.cancel() }
        try Task.checkCancellation()
        return outcome
    }

    /// Drain both streams while the child runs, even after the capture budget
    /// is reached. Waiting for exit before reading can fill a pipe and deadlock.
    static func capture(_ process: Process, timeout: TimeInterval = 10, limit: Int = 4 * 1024 * 1024) async throws -> Captured {
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let outReader = PipeReadWaiter(output.fileHandleForReading), errReader = PipeReadWaiter(errors.fileHandleForReading)
        let stdout = Task.detached(priority: .utility) { await drain(outReader, limit: limit) }
        let stderr = Task.detached(priority: .utility) { await drain(errReader, limit: limit) }
        let outcome: Outcome
        do {
            outcome = try await run(process, timeout: timeout)
        } catch {
            try? output.fileHandleForWriting.close()
            try? errors.fileHandleForWriting.close()
            outReader.close(); errReader.close()
            _ = await stdout.value; _ = await stderr.value
            throw error
        }
        try? output.fileHandleForWriting.close()
        try? errors.fileHandleForWriting.close()
        // A descendant may retain an inherited pipe after the direct child
        // exits. Its output cannot keep the caller or file descriptors alive.
        let drainDeadline = DispatchWorkItem { outReader.close(); errReader.close() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1, execute: drainDeadline)
        let out = await stdout.value, err = await stderr.value
        drainDeadline.cancel()
        return Captured(outcome: outcome, output: out.0, errors: err.0, truncated: out.1 || err.1)
    }

    /// Legacy synchronous collectors call this only on their utility queues.
    /// The child and both pipe drains still have the same hard deadline.
    static func captureBlocking(_ process: Process, timeout: TimeInterval = 5, limit: Int = 2 * 1024 * 1024) -> Captured? {
        precondition(!Thread.isMainThread, "Move process collection off the UI thread")
        let result = BlockingResult()
        let done = DispatchSemaphore(value: 0)
        Task.detached(priority: .utility) {
            result.value = try? await capture(process, timeout: timeout, limit: limit)
            done.signal()
        }
        done.wait()
        return result.value
    }
    private final class BlockingResult: @unchecked Sendable { var value: Captured? }

    private static func drain(_ reader: PipeReadWaiter, limit: Int) async -> (Data, Bool) {
        defer { reader.close() }
        var result = Data(), truncated = false
        while let chunk = try? await reader.read(), !chunk.isEmpty {
            let remaining = max(0, limit - result.count)
            result.append(chunk.prefix(remaining))
            if chunk.count > remaining { truncated = true }
        }
        return (result, truncated)
    }

    private final class Execution: @unchecked Sendable {
        let process: Process
        let queue = DispatchQueue(label: "app.atoll.process", qos: .utility)
        var continuation: CheckedContinuation<Outcome, Error>?
        var deadline: DispatchWorkItem?
        var hardStop: DispatchWorkItem?
        var cancelled = false
        var timedOut = false
        var childPID: pid_t?
        init(_ process: Process) { self.process = process }

        func start(_ continuation: CheckedContinuation<Outcome, Error>, timeout: TimeInterval?) {
            queue.async {
                guard !self.cancelled else { continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                self.process.terminationHandler = { [weak self] process in
                    let status = process.terminationStatus
                    guard let self else { return }
                    self.queue.async { self.finish(.success(self.timedOut ? .timedOut : .exited(status))) }
                }
                do {
                    try self.process.run()
                    self.childPID = self.process.processIdentifier
                    if let timeout {
                        let work = DispatchWorkItem { [weak self] in
                            guard let self, self.continuation != nil, self.process.isRunning else { return }
                            self.timedOut = true
                            self.stop()
                        }
                        self.deadline = work
                        self.queue.asyncAfter(deadline: .now() + max(0, timeout), execute: work)
                    }
                } catch { self.finish(.failure(error)) }
            }
        }
        func cancel() {
            queue.async {
                self.cancelled = true
                if self.continuation != nil { self.stop() }
            }
        }
        private func stop() {
            guard process.isRunning, hardStop == nil else { return }
            process.terminate()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.continuation != nil, self.process.isRunning,
                      let pid = self.childPID, pid == self.process.processIdentifier else { return }
                Darwin.kill(pid, SIGKILL)
            }
            hardStop = work
            queue.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
        private func finish(_ result: Result<Outcome, Error>) {
            guard let continuation else { return }
            self.continuation = nil
            deadline?.cancel(); deadline = nil
            hardStop?.cancel(); hardStop = nil
            process.terminationHandler = nil
            continuation.resume(with: result)
        }
    }
}
