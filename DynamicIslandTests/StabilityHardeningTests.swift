import XCTest
@testable import Atoll

@MainActor
final class StabilityHardeningTests: XCTestCase {
    private func temporaryURL(_ name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AtollStability-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent(name)
    }

    func testSaveGateKeepsOpenOnFailureAndCanRetry() async {
        var fail = true
        let gate = TerminationSaveGate { fail ? "disk unavailable" : nil }
        let first = expectation(description: "failed save")
        gate.prepare { XCTAssertEqual($0, "disk unavailable"); first.fulfill() }
        await fulfillment(of: [first], timeout: 1)
        XCTAssertFalse(gate.isSaving)
        fail = false
        let second = expectation(description: "retry")
        gate.prepare { XCTAssertNil($0); second.fulfill() }
        await fulfillment(of: [second], timeout: 1)
    }

    func testFirstQuitAwaitsLazyRestorationBeforeDetectingEdits() async throws {
        let textURL = try temporaryURL("content.txt")
        let original = Data("saved before the text tab was opened 你好".utf8)
        try original.write(to: textURL)
        let draftURL = try temporaryURL("drafts.json")
        try JSONEncoder().encode(["one": "unsent saved draft"]).write(to: draftURL)
        let shelfDirectory = try temporaryURL("shelf")
        let persistence = ShelfPersistenceService(directory: shelfDirectory)
        let item = ShelfItem(kind: .text(string: "saved shelf text"))
        XCTAssertTrue(persistence.save([item]))
        let shelf = ShelfStateViewModel(persistence: persistence,
                                       lifetime: ShelfFileLifetime(directory: try temporaryURL("owned")))
        let sessions = AgentSessionStore(persistenceURL: nil)
        let conversation = AgentConversationService(store: sessions, draftURL: draftURL, executablePath: { nil })
        let text = ExtraSpaceStore(fileURL: textURL)
        text.isRelaunching = true
        XCTAssertFalse(text.isLoaded)

        let error = await AppTerminationCoordinator.saveContent(extraSpace: text, shelf: shelf,
                                                                sessions: sessions, conversation: conversation,
                                                                timer: .shared)
        XCTAssertNil(error)
        XCTAssertEqual(text.text, String(decoding: original, as: UTF8.self))
        XCTAssertEqual(try Data(contentsOf: textURL), original)
        XCTAssertEqual(shelf.items, [item])
        XCTAssertEqual(conversation.drafts["one"], "unsent saved draft")
        conversation.stop()
    }

    func testRepairedDraftFileIsMergedOnTheNextQuit() async throws {
        let draftURL = try temporaryURL("drafts.json")
        let damaged = Data("{damaged".utf8)
        try damaged.write(to: draftURL)
        let sessions = AgentSessionStore(persistenceURL: nil)
        let conversation = AgentConversationService(store: sessions, draftURL: draftURL, executablePath: { nil })
        let shelf = ShelfStateViewModel(persistence: ShelfPersistenceService(directory: try temporaryURL("shelf")),
                                        lifetime: ShelfFileLifetime(directory: try temporaryURL("owned")))
        let text = ExtraSpaceStore(fileURL: try temporaryURL("content.txt"))
        func quit() async -> String? {
            await AppTerminationCoordinator.saveContent(extraSpace: text, shelf: shelf, sessions: sessions,
                                                        conversation: conversation, timer: .shared)
        }
        await conversation.awaitInitialLoad()
        conversation.setDraft("typed after the failure", for: "one")
        let blocked = await quit()
        XCTAssertNotNil(blocked)
        XCTAssertEqual(try Data(contentsOf: draftURL), damaged, "an unreadable file is never written over")

        try JSONEncoder().encode(["one": "older saved", "two": "saved elsewhere"]).write(to: draftURL)
        let retried = await quit()
        XCTAssertNil(retried)
        XCTAssertNil(conversation.draftPersistenceError)
        XCTAssertEqual(conversation.drafts, ["one": "typed after the failure", "two": "saved elsewhere"])
        let saved = try await RecoveryFile<[String: String]>(url: draftURL, limit: 1024).load()
        XCTAssertEqual(saved, conversation.drafts)
        conversation.stop()
    }

    func testTimedOutSaveCannotAccumulateOrReplyTwice() async {
        var release: CheckedContinuation<Void, Never>?
        var writes = 0
        var replies = 0
        let gate = TerminationSaveGate(timeout: 0.03) {
            writes += 1
            await withCheckedContinuation { release = $0 }
            return nil
        }
        let timedOut = expectation(description: "deadline")
        gate.prepare { XCTAssertNotNil($0); replies += 1; timedOut.fulfill() }
        await fulfillment(of: [timedOut], timeout: 1)
        XCTAssertTrue(gate.isSaving)
        gate.prepare { XCTAssertNotNil($0) }
        XCTAssertEqual(writes, 1)
        release?.resume()
        for _ in 0..<100 where gate.isSaving { await Task.yield() }
        XCTAssertFalse(gate.isSaving)
        XCTAssertEqual(replies, 1)
    }

    func testOldBridgeCannotRemoveReplacementDiscovery() throws {
        let directory = try temporaryURL("bridge")
        let old = BridgeDiscoveryLease(directory: directory, owner: "old")
        let replacement = BridgeDiscoveryLease(directory: directory, owner: "new")
        try old.publish(port: 10001, token: "old-token")
        try replacement.publish(port: 10002, token: "new-token")
        try old.release()
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("port"), encoding: .utf8), "10002")
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("auth-header"), encoding: .utf8), "Authorization: Bearer new-token\n")
        let mode = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("auth-header").path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
        try replacement.release()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("port").path))
    }

    func testTemporaryCleanupLeavesOtherLiveInstanceAndShelfUntouched() throws {
        let own = AtollTemporaryFiles.directory(.terminalText).appendingPathComponent("own.txt")
        let other = AtollTemporaryFiles.root.appendingPathComponent("Runs/\(ProcessInfo.processInfo.processIdentifier)-other/TerminalText/other.txt")
        let shelf = AtollTemporaryFiles.directory(.shelf).appendingPathComponent("saved-\(UUID()).txt")
        try FileManager.default.createDirectory(at: other.deletingLastPathComponent(), withIntermediateDirectories: true)
        for file in [own, other, shelf] { try Data("fixture".utf8).write(to: file) }
        defer {
            try? FileManager.default.removeItem(at: other.deletingLastPathComponent().deletingLastPathComponent())
            try? FileManager.default.removeItem(at: shelf)
        }
        AtollTemporaryFiles.removeAll(except: [.shelf])
        XCTAssertFalse(FileManager.default.fileExists(atPath: own.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: shelf.path))
    }

    func testRecoveryBackoffIsBoundedAndResetsOnlyAfterStableConnection() {
        var retry = ServiceRetryPolicy()
        XCTAssertEqual((0..<6).compactMap { _ in retry.nextDelay(now: 0) }, [1, 2, 4, 8, 16, 30])
        XCTAssertNil(retry.nextDelay(now: 0))
        retry.ready(now: 10)
        XCTAssertNil(retry.nextDelay(now: 11))
        retry.ready(now: 20)
        XCTAssertEqual(retry.nextDelay(now: 81), 1)
        _ = retry.nextDelay(now: 81)
        retry.reset()
        XCTAssertEqual(retry.nextDelay(now: 82), 1, "an explicit restart opens a new bounded round")
    }

    func testNowPlayingAdapterReconnectsAfterRetriesRunOut() async throws {
        var healthy = false
        var policy = ServiceRetryPolicy()
        policy.maximumRetries = 1
        policy.baseDelay = 0.01
        // Stand-in adapters: one that exits at once, one that stays up until stopped.
        let controller = try XCTUnwrap(NowPlayingController(adapterCommand: {
            healthy ? .init(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"])
                    : .init(executable: URL(fileURLWithPath: "/usr/bin/false"), arguments: [])
        }, retryPolicy: policy))
        defer { controller.stop() }
        for _ in 0..<300 where controller.connectionStatus != "unavailable" { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(controller.connectionStatus, "unavailable", "the bounded round ends")
        healthy = true
        controller.reconnectIfUnavailable()
        for _ in 0..<300 where controller.connectionStatus != "ready" { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(controller.connectionStatus, "ready", "a wake or playback command brings the adapter back")
        controller.reconnectIfUnavailable()
        XCTAssertEqual(controller.connectionStatus, "ready", "a working adapter is left alone")
    }

    func testBridgeStopCancelsFailedStartRetryAndLateReady() async throws {
        let receiver = StabilityHookReceiver()
        let blocked = try temporaryURL("not-a-directory")
        try Data("fixture".utf8).write(to: blocked)
        let failing = AgentBridge(directory: blocked, receiver: receiver)
        failing.start()
        XCTAssertEqual(failing.status, "retrying")
        XCTAssertFalse(failing.isRunning)
        failing.stop()
        try await Task.sleep(for: .seconds(1.1))
        XCTAssertEqual(failing.status, "stopped")
        let directory = try temporaryURL("bridge")
        let bridge = AgentBridge(directory: directory, receiver: receiver)
        bridge.start()
        bridge.stop()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("port").path))
        bridge.start()
        for _ in 0..<100 where !bridge.isRunning { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(bridge.isRunning)
        bridge.stop()
        XCTAssertFalse(bridge.isRunning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("port").path))
    }

    func testInvalidDraftSnapshotCannotBeOverwrittenByEmptyState() async throws {
        let url = try temporaryURL("invalid-drafts.json")
        let original = try JSONEncoder().encode(["one": String(repeating: "x", count: 65 * 1024)])
        try original.write(to: url)
        let service = AgentConversationService(store: AgentSessionStore(persistenceURL: nil), draftURL: url, executablePath: { nil })
        let error = await service.saveForTermination()
        XCTAssertNotNil(error)
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertTrue(service.drafts.isEmpty)
        service.stop()
    }

    func testCrashReportExportRejectsLinksOldReportsAndBoundsCount() throws {
        let directory = try temporaryURL("reports")
        let output = try temporaryURL("export")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for index in 0..<12 { try Data("crash".utf8).write(to: directory.appendingPathComponent("Atoll-\(index).ips")) }
        let old = directory.appendingPathComponent("Atoll-old.crash")
        try Data("old".utf8).write(to: old)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-8 * 86400)], ofItemAtPath: old.path)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("Atoll-link.ips"), withDestinationURL: old)
        try AtollDiagnostics.copyRecentCrashReports(from: [directory], to: output)
        let names = try FileManager.default.contentsOfDirectory(atPath: output.path)
        XCTAssertEqual(names.count, 8)
        XCTAssertFalse(names.contains("Atoll-old.crash"))
        XCTAssertFalse(names.contains("Atoll-link.ips"))
    }

    func testBundleCarriesSourceAndDependencyIdentity() {
        let identity = AtollDiagnostics.buildInfo
        XCTAssertEqual(identity["sourceSHA256"]?.count, 64)
        XCTAssertEqual(identity["packagesSHA256"]?.count, 64)
        XCTAssertNotEqual(identity["xcode"], "unknown")
        XCTAssertNotNil(Bundle.main.url(forResource: "AtollProcessSupervisor", withExtension: nil))
    }

    func testRecoveryFilePreservesCorruptionAndEnforcesLimit() async throws {
        let url = try temporaryURL("snapshot.json")
        let original = Data("damaged content".utf8)
        try original.write(to: url)
        let file = RecoveryFile<[String: String]>(url: url, limit: 256)
        do { _ = try await file.load(); XCTFail("Expected corrupt snapshot") } catch {}
        do { try await file.save([:]); XCTFail("Must preserve unreadable predecessor") } catch {}
        XCTAssertEqual(try Data(contentsOf: url), original)
        let readFailed = await file.readFailed
        XCTAssertTrue(readFailed)
        try JSONEncoder().encode(["repaired": "yes"]).write(to: url)
        do { try await file.save([:]); XCTFail("A repaired file is read before it is written over") } catch {}
        let repaired = try await file.load()
        XCTAssertEqual(repaired, ["repaired": "yes"])
        try await file.save(["repaired": "saved"])
        let bounded = RecoveryFile<[String: String]>(url: try temporaryURL("bounded.json"), limit: 32)
        do { try await bounded.save(["draft": String(repeating: "x", count: 64)]); XCTFail("Expected limit") } catch {}
    }

    func testDraftsRecoverAndNewEditsWinOverDelayedLoad() async throws {
        let url = try temporaryURL("drafts.json")
        let file = RecoveryFile<[String: String]>(url: url, limit: 1024)
        try await file.save(["one": "saved", "two": "untouched"])
        let service = AgentConversationService(store: AgentSessionStore(persistenceURL: nil), draftURL: url, executablePath: { nil })
        service.setDraft("newer edit", for: "one")
        let error = await service.saveForTermination()
        XCTAssertNil(error)
        XCTAssertEqual(service.drafts, ["one": "newer edit", "two": "untouched"])
        let recovered = try await RecoveryFile<[String: String]>(url: url, limit: 1024).load()
        XCTAssertEqual(recovered, service.drafts)
        service.stop()
    }

    func testTimerRecoveryPreservesDeadlineAndPauseAcrossEncoding() throws {
        let start = Date(timeIntervalSince1970: 1000)
        var countdown = TimerCountdown(duration: 120, startingAt: start)
        let running = TimerRecovery.Active(countdown: countdown, duration: 120, name: "Timer", paused: false, presetID: nil)
        let decoded = try JSONDecoder().decode(TimerRecovery.Active.self, from: JSONEncoder().encode(running))
        XCTAssertEqual(decoded.countdown.timeLeft(at: start.addingTimeInterval(35)), 85)
        XCTAssertFalse(decoded.isRestorable(at: start.addingTimeInterval(121)))
        countdown.pause(at: start.addingTimeInterval(35))
        let paused = TimerRecovery.Active(countdown: countdown, duration: 120, name: "Timer", paused: true, presetID: nil)
        XCTAssertTrue(paused.isRestorable(at: start.addingTimeInterval(999)))
        XCTAssertEqual(paused.countdown.timeLeft(at: start.addingTimeInterval(999)), 85)
    }

    func testDiagnosticsMatchAllHistoricalSubsystemsAndStayBounded() throws {
        let predicate = NSPredicate(format: AtollDiagnostics.exportPredicate)
        for subsystem in AtollDiagnostics.legacySubsystems {
            XCTAssertTrue(predicate.evaluate(with: ["subsystem": subsystem]))
        }
        XCTAssertFalse(predicate.evaluate(with: ["subsystem": "unrelated"]))
        let events = DiagnosticEvents()
        XCTAssertTrue(events.record(site: "fixed-site", now: 0))
        XCTAssertFalse(events.record(site: "fixed-site", now: 1))
        XCTAssertTrue(events.record(site: "fixed-site", now: 60))
        XCTAssertEqual(events.snapshot().first?["count"] as? Int, 3)
        for index in 0..<256 { _ = events.record(site: "site-\(index)", now: 61) }
        XCTAssertEqual(events.snapshot().count, 128)
        XCTAssertEqual(Set(events.snapshot().first!.keys), ["site", "count", "lastUptime"])
        XCTAssertEqual(SystemOSDManager.policy, "native coexistence")
    }

    func testInheritedPipeDoesNotKeepCaptureWaitingForDescendant() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        child.arguments = ["-c", "(sleep 2) & printf ok"]
        let start = Date()
        let result = try await ProcessRunner.capture(child, timeout: 0.5, limit: 1024)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.8)
        XCTAssertEqual(String(data: result.output, encoding: .utf8), "ok")
    }

    func testHTTPLimitsChunkedBodyAndCancelsStalledResponse() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StabilityHTTPProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (data, _) = try await BoundedHTTP.data(from: URL(string: "https://fixture.invalid/small")!, session: session, limit: 64)
        XCTAssertEqual(data.count, 8)
        do {
            _ = try await BoundedHTTP.data(from: URL(string: "https://fixture.invalid/large")!, session: session, limit: 64)
            XCTFail("Oversized chunked response must fail")
        } catch { XCTAssertEqual((error as? URLError)?.code, .dataLengthExceedsMaximum) }
        let start = Date()
        do {
            _ = try await BoundedHTTP.data(from: URL(string: "https://fixture.invalid/stall")!, session: session, timeout: 0.05)
            XCTFail("Stalled body must fail")
        } catch { XCTAssertLessThan(Date().timeIntervalSince(start), 1) }
    }
}

@MainActor
private final class StabilityHookReceiver: AgentHookReceiver {
    func receive(_ event: AgentHookEvent) -> Data? { nil }
    func park(_ event: AgentHookEvent, reply: @escaping (Data?) -> Void, onClose: (@escaping @Sendable () -> Void) -> Void) { reply(nil) }
}

private final class StabilityHTTPProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if request.url?.path == "/stall" { return }
        client?.urlProtocol(self, didLoad: Data(repeating: 1, count: request.url?.path == "/large" ? 128 : 8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
