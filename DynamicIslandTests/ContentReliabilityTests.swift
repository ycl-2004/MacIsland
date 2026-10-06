import AppKit
import Foundation
import XCTest
@testable import Atoll

@MainActor
final class ContentReliabilityTests: XCTestCase {
    private func fixture() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }
    private func loaded(_ predicate: () -> Bool) async throws {
        let end = Date().addingTimeInterval(3)
        while !predicate(), Date() < end { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(predicate())
    }

    func testSharedContentUsesIsolatedTestPaths() {
        XCTAssertTrue(ExtraSpaceStore.shared.fileURL.path.hasPrefix(AppRuntimeEnvironment.testDirectory.path))
        XCTAssertTrue(ShelfPersistenceService.defaultDirectory.path.hasPrefix(AppRuntimeEnvironment.testDirectory.path))
        XCTAssertTrue(AtollTemporaryFiles.root.path.hasPrefix(AppRuntimeEnvironment.testDirectory.path))
    }

    func testExtraSpaceRejectsOversizedChangesWithoutReplacingContent() async throws {
        let url = try fixture().appendingPathComponent("content.txt")
        let store = ExtraSpaceStore(fileURL: url, saveDelay: 60)
        try await loaded { store.isLoaded }
        store.updateText("keep me"); store.flushPendingSave()
        store.updateText(String(repeating: "x", count: ExtraSpaceStore.maximumBytes + 1))
        store.flushPendingSave()
        XCTAssertEqual(store.text, "keep me")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "keep me")
        XCTAssertNotNil(store.errorMessage)
    }

    func testOversizedExtraSpaceFileIsKeptAndNotLoadedOrOverwritten() async throws {
        let url = try fixture().appendingPathComponent("content.txt")
        let data = Data(repeating: 120, count: ExtraSpaceStore.maximumBytes + 1)
        try data.write(to: url)
        let store = ExtraSpaceStore(fileURL: url)
        try await loaded { store.errorMessage != nil }
        store.updateText("replacement"); store.flushPendingSave()
        XCTAssertFalse(store.isLoaded)
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testRepeatedSaveKeepsPreviousVersionAndPrivatePermissions() async throws {
        let url = try fixture().appendingPathComponent("content.txt")
        let store = ExtraSpaceStore(fileURL: url, saveDelay: 60)
        try await loaded { store.isLoaded }
        store.updateText("first"); store.flushPendingSave()
        XCTAssertFalse(store.hasPreviousVersion)
        store.updateText("second"); store.saveNow(); store.saveNow(); store.flushPendingSave()
        XCTAssertEqual(try String(contentsOf: PrivateContentFile.backupURL(url), encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "second")
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
        let directoryMode = try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)[.posixPermissions] as? Int
        XCTAssertEqual(directoryMode, 0o700)
    }

    func testExplicitRecoveryKeepsTheCurrentVersion() async throws {
        let url = try fixture().appendingPathComponent("content.txt")
        let store = ExtraSpaceStore(fileURL: url, saveDelay: 60)
        try await loaded { store.isLoaded }
        store.updateText("first"); store.flushPendingSave()
        store.updateText("second"); store.flushPendingSave()
        store.recoverPrevious()
        try await loaded { store.text == "first" }
        store.flushPendingSave()
        XCTAssertEqual(try String(contentsOf: url.appendingPathExtension("recovery"), encoding: .utf8), "second")
    }

    func testRecoveryWritesEvenWhenThePreviousTextMatchesTheCurrentDraft() async throws {
        let url = try fixture().appendingPathComponent("content.txt")
        let store = ExtraSpaceStore(fileURL: url, saveDelay: 60)
        try await loaded { store.isLoaded }
        store.updateText("first"); store.flushPendingSave()
        store.updateText("second"); store.updateText("first"); store.flushPendingSave()
        XCTAssertTrue(store.hasPreviousVersion)
        store.recoverPrevious()
        try await loaded { FileManager.default.fileExists(atPath: url.appendingPathExtension("recovery").path) }
        try await Task.sleep(for: .milliseconds(30))
        store.flushPendingSave()
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "first")
    }

    func testAgentSnapshotBudgetReloadsLargeMultiSessionHistory() async throws {
        let url = try fixture().appendingPathComponent("sessions.json")
        let store = AgentSessionStore(persistenceURL: url)
        try await loaded { store.isLoaded }
        for i in 0..<14 {
            var session = AgentSession(id: "test:\(i)", sourceID: "test", cwd: nil, hostBundleID: nil,
                lastPrompt: nil, lastReply: nil, state: .idle, startedAt: Date(), updatedAt: Date())
            session.messages = (0..<40).map { AgentMessage(id: "\($0)", role: .assistant, text: String(repeating: "🙂", count: 16_000)) }
            store.upsert(session)
        }
        store.flushPendingSave()
        let data = try Data(contentsOf: url)
        XCTAssertLessThanOrEqual(data.count, AgentSessionStore.maximumSnapshotBytes)
        let reloaded = AgentSessionStore(persistenceURL: url)
        try await loaded { reloaded.isLoaded }
        XCTAssertEqual(reloaded.sessions.count, 14)
        XCTAssertTrue(reloaded.sessions.allSatisfy { !$0.messages.isEmpty })
        XCTAssertNil(reloaded.persistenceError)
    }

    func testAgentMemoryKeepsOnlyRecentBoundedCards() {
        let store = AgentSessionStore(persistenceURL: nil)
        for i in 0..<100 {
            store.upsert(AgentSession(id: "test:\(i)", sourceID: "test", cwd: nil, hostBundleID: nil,
                lastPrompt: nil, lastReply: nil, state: .idle, startedAt: Date(), updatedAt: Date()))
        }
        XCTAssertEqual(store.sessions.count, AgentSessionStore.maximumSessions)
    }

    func testShelfOwnedCopyHasAByteBudgetAndPrivatePermissions() throws {
        let root = try fixture()
        let source = root.appendingPathComponent("source.txt")
        let target = root.appendingPathComponent("owned/file.txt")
        try Data("content".utf8).write(to: source)
        try ShelfStorageBudget.copy(source, to: target)
        XCTAssertEqual(try Data(contentsOf: target), Data("content".utf8))
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? Int, 0o600)
        XCTAssertThrowsError(try ShelfStorageBudget.size(source, limit: 1))
    }

    func testZipSnapshotsInputsAndPreservesSingleFileName() async throws {
        let root = try fixture()
        let source = root.appendingPathComponent("example.txt")
        try Data("content".utf8).write(to: source)
        let created = await TemporaryFileStorageService.shared.createZip(from: [source])
        let archive = try XCTUnwrap(created)
        XCTAssertEqual(archive.lastPathComponent, "example.txt.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", archive.path, "example.txt"]
        let result = try await ProcessRunner.capture(process, timeout: 3)
        XCTAssertEqual(result.outcome, .exited(0))
        XCTAssertEqual(result.output, Data("content".utf8))
        try? FileManager.default.removeItem(at: archive.deletingLastPathComponent())
    }

    func testFailedTimerSoundImportLeavesPreviousSound() throws {
        let root = try fixture()
        let store = TimerSoundStore(directory: root.appendingPathComponent("sounds"))
        let source = root.appendingPathComponent("sound.mp3")
        try Data("old".utf8).write(to: source)
        let saved = try store.importSound(from: source)
        XCTAssertThrowsError(try store.importSound(from: root.appendingPathComponent("missing.mp3")))
        XCTAssertEqual(try Data(contentsOf: saved), Data("old".utf8))
        try Data("new".utf8).write(to: source)
        let replacement = try store.importSound(from: source)
        XCTAssertEqual(try Data(contentsOf: replacement), Data("new".utf8))
    }
}
