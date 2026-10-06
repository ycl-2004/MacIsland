import Foundation
import XCTest
@testable import Atoll

final class ResourceReliabilityTests: XCTestCase {
    @MainActor
    func testNativeHostDisablesProductionStartup() {
        XCTAssertTrue(AppDelegate.isHostingUnitTests)
    }

    func testBothProcessPipesDrainBeyondTheirBufferCapacity() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", "print STDOUT 'x' x 2097152; print STDERR 'y' x 2097152;"]
        let result = try await ProcessRunner.capture(process, timeout: 3, limit: 1024)
        XCTAssertEqual(result.outcome, .exited(0))
        XCTAssertEqual(result.output.count, 1024)
        XCTAssertEqual(result.errors.count, 1024)
        XCTAssertTrue(result.truncated)
    }

    func testDeadlineKillsAnOwnedChildThatIgnoresTermination() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", "$SIG{TERM}=sub{}; while (1) { sleep 20; }"]
        let start = Date()
        let outcome = try await ProcessRunner.run(process, timeout: 0.15)
        XCTAssertEqual(outcome, .timedOut)
        XCTAssertFalse(process.isRunning)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testProcessCancellationTerminatesTheChild() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["20"]
        let task = Task { try await ProcessRunner.run(process, timeout: 10) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { }
        XCTAssertFalse(process.isRunning)
    }

    func testUnicodeSurvivesEverySplitBoundary() async throws {
        struct Row: Decodable { let text: String }
        actor Rows { var values: [String] = []; func add(_ text: String) { values.append(text) } }
        let bytes = Data("{\"text\":\"中文🙂\"}\n".utf8)
        for split in 1..<bytes.count {
            let handler = JSONLinesPipeHandler(), rows = Rows()
            let pipe = await handler.getPipe()
            let reading = Task { await handler.readJSONLines(as: Row.self) { await rows.add($0.text) } }
            try pipe.fileHandleForWriting.write(contentsOf: bytes.prefix(split))
            try await Task.sleep(for: .milliseconds(5))
            try pipe.fileHandleForWriting.write(contentsOf: bytes.suffix(bytes.count - split))
            try pipe.fileHandleForWriting.close()
            await reading.value
            let values = await rows.values
            XCTAssertEqual(values, ["中文🙂"], "Split \(split)")
            await handler.close()
        }
    }

    func testConcurrentDataAndCancellationFinishExactlyOnce() async throws {
        for _ in 0..<200 {
            let handler = JSONLinesPipeHandler()
            let pipe = await handler.getPipe()
            let reading = Task { await handler.readJSONLines(as: String.self) { _ in } }
            try pipe.fileHandleForWriting.write(contentsOf: Data("\"fixture\"\n".utf8))
            reading.cancel()
            await handler.close()
            await reading.value
        }
    }

    func testCancellingAnEmptyStreamCompletesWithoutAContinuationLeak() async throws {
        let handler = JSONLinesPipeHandler()
        let done = expectation(description: "Cancelled reader finished")
        let reading = Task {
            await handler.readJSONLines(as: String.self) { _ in }
            done.fulfill()
        }
        try await Task.sleep(for: .milliseconds(20))
        reading.cancel()
        await fulfillment(of: [done], timeout: 1)
        await handler.close()
    }
}
