import Foundation

/// A single outstanding read, completed exactly once by data, EOF or close.
/// The lock also prevents a readability callback from reading a closed handle.
final class PipeReadWaiter: @unchecked Sendable {
    let handle: FileHandle
    let lock = NSLock()
    var waiter: CheckedContinuation<Data, Error>?
    var closed = false
    init(_ handle: FileHandle) { self.handle = handle }
    func read() async throws -> Data {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if closed { lock.unlock(); continuation.resume(returning: Data()); return }
            guard waiter == nil else { lock.unlock(); continuation.resume(throwing: CocoaError(.fileReadUnknown)); return }
            waiter = continuation
            handle.readabilityHandler = { [weak self] handle in
                guard let self else { return }
                self.lock.lock()
                guard !self.closed, let waiter = self.waiter else { self.lock.unlock(); return }
                self.waiter = nil
                handle.readabilityHandler = nil
                let data = handle.availableData
                self.lock.unlock()
                waiter.resume(returning: data)
            }
            lock.unlock()
        }
    }
    func close() {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        closed = true
        let pending = waiter; waiter = nil
        handle.readabilityHandler = nil
        try? handle.close()
        lock.unlock()
        pending?.resume(returning: Data())
    }
}
