import Foundation

/// One disk operation in flight and one replaceable snapshot. The drain itself
/// is the only work item queued; edits never enqueue closures holding old data.
/// The supplied queue must be serial. Write results and barriers use that queue.
final class LatestSnapshotWriter<Snapshot, Output>: @unchecked Sendable {
    private let queue: DispatchQueue
    private let write: (Snapshot) -> Output
    private let didWrite: (Output) -> Void
    private let lock = NSLock()
    private var pending: Snapshot?
    private var draining = false
    private var lastOutput: Output?

    init(queue: DispatchQueue, write: @escaping (Snapshot) -> Output, didWrite: @escaping (Output) -> Void) {
        self.queue = queue
        self.write = write
        self.didWrite = didWrite
    }

    func submit(_ snapshot: Snapshot) {
        lock.withLock {
            pending = snapshot
            guard !draining else { return }
            draining = true
            // Enqueue while locked so a flush cannot overtake this submission.
            queue.async { self.drain() }
        }
    }

    func discardPending() { lock.withLock { pending = nil } }

    /// Call after submit. The barrier waits for the drain, including its latest
    /// replacement; it does not capture another full snapshot.
    func flush() async -> Output? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.lastOutput) }
        }
    }

    /// Legacy explicit/test callers only; never called from the writer queue.
    func flushSynchronously() -> Output? { queue.sync { lastOutput } }

    private func drain() {
        while let snapshot = takePending() {
            let output = write(snapshot)
            lastOutput = output
            didWrite(output)
        }
    }

    private func takePending() -> Snapshot? {
        lock.withLock {
            guard let snapshot = pending else { draining = false; return nil }
            pending = nil
            return snapshot
        }
    }
}
