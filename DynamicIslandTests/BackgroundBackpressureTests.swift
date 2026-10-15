import Foundation
import XCTest
@testable import Atoll

final class BackgroundBackpressureTests: XCTestCase {
    private final class LifetimeCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var live: Int { lock.withLock { count } }
        func change(_ delta: Int) { lock.withLock { count += delta } }
    }

    private final class Snapshot {
        let revision: Int
        let counter: LifetimeCounter
        init(_ revision: Int, counter: LifetimeCounter) {
            self.revision = revision; self.counter = counter; counter.change(1)
        }
        deinit { counter.change(-1) }
    }

    func testBlockedWriterRetainsOnlyActiveAndLatestSnapshot() async {
        let queue = DispatchQueue(label: "test.latest-snapshot")
        let started = expectation(description: "first write blocked")
        let release = DispatchSemaphore(value: 0)
        let counter = LifetimeCounter()
        let lock = NSLock()
        var writes: [Int] = []
        let writer = LatestSnapshotWriter<Snapshot, Int>(queue: queue, write: { snapshot in
            if snapshot.revision == 0 {
                started.fulfill()
                _ = release.wait(timeout: .now() + 10)
            }
            lock.withLock { writes.append(snapshot.revision) }
            return snapshot.revision
        }, didWrite: { _ in })
        writer.submit(Snapshot(0, counter: counter))
        await fulfillment(of: [started], timeout: 2)
        for revision in 1...1_000 { writer.submit(Snapshot(revision, counter: counter)) }
        XCTAssertEqual(counter.live, 2, "Cancelled/replaced snapshots must be released while disk is still blocked")
        release.signal()
        let result = await writer.flush()
        XCTAssertEqual(result, 1_000)
        XCTAssertEqual(lock.withLock { writes }, [0, 1_000])
        XCTAssertEqual(counter.live, 0)
    }

    func testRecoveryCanDiscardPendingWithoutDiscardingActiveWrite() async {
        let queue = DispatchQueue(label: "test.latest-snapshot.recovery")
        let started = expectation(description: "first write blocked")
        let release = DispatchSemaphore(value: 0)
        let writer = LatestSnapshotWriter<Int, Int>(queue: queue, write: { revision in
            if revision == 0 { started.fulfill(); _ = release.wait(timeout: .now() + 10) }
            return revision
        }, didWrite: { _ in })
        writer.submit(0)
        await fulfillment(of: [started], timeout: 2)
        writer.submit(1)
        writer.discardPending()
        release.signal()
        let result = await writer.flush()
        XCTAssertEqual(result, 0)
        writer.submit(2)
        XCTAssertEqual(writer.flushSynchronously(), 2)
    }

    @MainActor
    func testPipeWriterRejectsOversizedAndBackloggedFramesWithoutWaiting() throws {
        let pipe = Pipe()
        let writer = try CodexPipeWriter(handle: pipe.fileHandleForWriting) { error in
            XCTFail("Explicitly stopped writes should not fail: \(error)")
        }
        defer { writer.stop() }
        XCTAssertThrowsError(try writer.enqueue(Data(repeating: 65, count: CodexPipeWriter.maximumMessageBytes + 1)))
        try writer.enqueue(Data(repeating: 65, count: CodexPipeWriter.maximumMessageBytes))
        try writer.enqueue(Data(repeating: 66, count: CodexPipeWriter.maximumMessageBytes))
        XCTAssertThrowsError(try writer.enqueue(Data([67])))
    }

    @MainActor
    func testPipeWriterLimitsQueuedFrameCountAndCanRemoveAnUnstartedFrame() throws {
        let pipe = Pipe()
        let writer = try CodexPipeWriter(handle: pipe.fileHandleForWriting) { _ in XCTFail("Unexpected failure") }
        defer { writer.stop() }
        try writer.enqueue(Data(repeating: 65, count: CodexPipeWriter.maximumMessageBytes))
        let cancelled = UUID()
        try writer.enqueue(Data([66]), token: cancelled)
        for _ in 2..<CodexPipeWriter.maximumQueuedMessages { try writer.enqueue(Data([67])) }
        XCTAssertThrowsError(try writer.enqueue(Data([68])))
        XCTAssertFalse(writer.cancel(cancelled), "Unstarted frame cancellation must preserve the stream")
        XCTAssertNoThrow(try writer.enqueue(Data([69])))
    }

    @MainActor
    func testPipeWriterDeadlineWorksWhenReaderNeverDrains() async throws {
        let pipe = Pipe()
        let timedOut = expectation(description: "write deadline")
        let writer = try CodexPipeWriter(handle: pipe.fileHandleForWriting) { _ in timedOut.fulfill() }
        defer { writer.stop() }
        try writer.enqueue(Data(repeating: 65, count: CodexPipeWriter.maximumMessageBytes), timeout: 0.05)
        await fulfillment(of: [timedOut], timeout: 1)
        XCTAssertThrowsError(try writer.enqueue(Data([66])))
    }

    @MainActor
    func testClosedPipeReportsFailureWithoutSIGPIPE() async throws {
        let pipe = Pipe()
        try pipe.fileHandleForReading.close()
        let failed = expectation(description: "closed reader")
        let writer = try CodexPipeWriter(handle: pipe.fileHandleForWriting) { _ in failed.fulfill() }
        defer { writer.stop() }
        try writer.enqueue(Data([65]))
        await fulfillment(of: [failed], timeout: 1)
    }
}
