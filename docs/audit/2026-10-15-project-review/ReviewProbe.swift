import Foundation
import Darwin

@main struct ReviewProbe {
    @MainActor static func waitUntil(_ check: () -> Bool) async throws {
        for _ in 0..<300 where !check() { try await Task.sleep(for: .milliseconds(5)) }
        precondition(check(), "probe timed out")
    }
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let url = root.appendingPathComponent("damaged.json")
        try Data("invalid json".utf8).write(to: url)
        let recovery = RecoveryFile<[String: String]>(url: url, limit: 1024)
        do { _ = try await recovery.load(); preconditionFailure("must reject invalid data") } catch {}
        // Repair on disk without replacing the live store, as the Quit dialog suggests.
        try JSONEncoder().encode([String: String]()).write(to: url)
        let freshlyLoaded = try await RecoveryFile<[String: String]>(url: url, limit: 1024).load()
        precondition(freshlyLoaded != nil, "repair must be readable")
        var retryRejected = false
        do { try await recovery.save(["new": "unsaved text"]) } catch { retryRejected = true }
        print("recovery_file_repaired_on_disk=true live_store_retry_rejected=\(retryRejected)")
        precondition(retryRejected)

        let damagedDraftURL = root.appendingPathComponent("damaged-service-drafts.json")
        try Data("invalid json".utf8).write(to: damagedDraftURL)
        let repairDefaults = UserDefaults(suiteName: root.appendingPathComponent("repair-defaults").path)!
        let damagedService = AgentConversationService(store: AgentSessionStore(persistenceURL: nil),
            defaults: repairDefaults, client: FakeCodexClient(), terminals: FakeTerminals().make(),
            draftURL: damagedDraftURL, executablePath: { nil })
        await damagedService.awaitInitialLoad()
        try JSONEncoder().encode([String: String]()).write(to: damagedDraftURL)
        let quitError = await damagedService.saveForTermination()
        print("draft_file_repaired_on_disk=true termination_save_still_rejected=\(quitError != nil)")
        precondition(quitError != nil)
        damagedService.stop()

        let store = AgentSessionStore(persistenceURL: nil)
        let client = FakeCodexClient()
        let suite = root.appendingPathComponent("defaults").path
        let defaults = UserDefaults(suiteName: suite)!
        let service = AgentConversationService(store: store, defaults: defaults, client: client,
            terminals: FakeTerminals().make(), draftURL: root.appendingPathComponent("drafts.json"),
            executablePath: { "/fake/codex" })
        service.start()
        defer { service.stop(); defaults.removePersistentDomain(forName: suite) }
        await service.awaitInitialLoad()
        try await waitUntil { service.isLive }
        for index in 0..<64 {
            let threadID = UUID().uuidString.lowercased()
            let thread: [String: Any] = ["id": threadID, "name": "Synthetic session \(index)", "cwd": "/tmp/fixture",
                "source": "vscode", "originator": "codex-tui", "canAcceptDirectInput": true,
                "status": ["type": "idle"], "updatedAt": Date().timeIntervalSince1970]
            let session = CodexSessionProjection.session(thread, existing: nil, live: true)!
            store.upsert(session)
            store.setLiveFeed(session.id, true)
            service.setDraft("synthetic prompt \(index)", for: session.id)
            service.send(id: session.id)
            try await waitUntil { !service.sending.contains(session.id) }
            precondition(client.starts.count == index + 1)
        }
        let emptyDrafts = service.drafts.values.filter(\.isEmpty).count
        service.setDraft("new unsent text", for: "codex:new-session")
        let newDraftBlocked = service.drafts["codex:new-session"] == nil
        print("successful_sends=\(client.starts.count) empty_draft_entries=\(emptyDrafts) new_session_input_blocked=\(newDraftBlocked)")
        precondition(emptyDrafts == 64 && newDraftBlocked)

        let error = await service.saveForTermination()
        precondition(error == nil)
        let savedDrafts = try await RecoveryFile<[String: String]>(url: root.appendingPathComponent("drafts.json"), limit: 2 * 1024 * 1024).load()
        print("persisted_empty_drafts=\(savedDrafts?.count ?? -1) in_memory_slots_still_used=\(service.drafts.count)")
        precondition(savedDrafts?.isEmpty == true)
    }
}
