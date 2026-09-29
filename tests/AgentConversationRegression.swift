import Foundation
import CryptoKit

// Build: swiftc DynamicIsland/managers/Agents/*.swift DynamicIsland/managers/Agents/Sources/*.swift DynamicIsland/managers/Agents/Terminals/*.swift DynamicIsland/utils/AtollTemporaryFiles.swift
//   tests/AgentConversationRegression.swift -o agent-regress && ./agent-regress tests/agent-rpc-fixture
// Tests inject their own Codex client and never run or read installed agents.

// App-wide pieces the agent files use, stood in for outside the app.
enum Logger {
    enum Category { case agents }
    static func log(_ message: String, category: Category) {}
}

/// Stands in for Codex's shared service (or, with `isSharedDaemon` false, a private reader).
@MainActor
final class FakeCodexClient: CodexConversationClient {
    var onEvent: ((String, [String: Any]) -> Void)?
    var onRequest: ((Any, String, [String: Any]) -> Void)?
    var onDisconnect: (() -> Void)?
    var isReady = false
    var isSharedDaemon = true
    var sharedServiceAvailable = true
    var loaded: [String] = []
    var threads: [String: [String: Any]] = [:]
    /// Loaded threads with nothing saved yet, which cannot be subscribed to.
    var unmaterialized = Set<String>()
    var turns: [[String: Any]] = []
    var methods: [String] = []
    var resumed: [String] = []
    var unsubscribed: [String] = []
    var starts: [[String: Any]] = []
    var replies: [[String: Any]] = []
    var rejectStart = false
    var loseTurnAck = false

    func start(executable: String) async throws { isReady = true }
    func close() { isReady = false; onDisconnect?() }
    func reply(id: Any, result: [String: Any]) throws { replies.append(result) }
    func request(_ method: String, _ params: [String: Any], timeout: Double) async throws -> [String: Any] {
        methods.append(method)
        let threadID = params["threadId"] as? String ?? ""
        switch method {
        case "thread/loaded/list": return ["data": loaded]
        case "thread/read":
            guard let thread = threads[threadID] else { throw AgentConnectionError.rejected("thread not found") }
            return ["thread": thread]
        case "thread/resume":
            precondition(isSharedDaemon && loaded.contains(threadID), "only a thread the shared service holds may be followed")
            if unmaterialized.contains(threadID) { throw AgentConnectionError.rejected("no rollout found for thread id") }
            resumed.append(threadID)
            return ["thread": threads[threadID]!]
        case "thread/unsubscribe": unsubscribed.append(threadID); return [:]
        case "thread/turns/list": return ["data": turns]
        case "turn/start":
            if rejectStart { throw AgentConnectionError.rejected("Terminal no longer accepts input") }
            starts.append(params)
            if loseTurnAck { throw AgentConnectionError.unavailable("socket closed") }
            return ["turn": ["id": "turn-one", "status": "inProgress"]]
        default: return [:]
        }
    }
}

/// Stands in for the system in every test: records what Atoll would run and
/// never touches a real terminal, whichever terminal the suite itself runs in.
final class FakeTerminals {
    var commands: [TerminalCommand] = []
    var running: Set<String> = [CmuxTerminalHost().bundleIdentifier, GhosttyTerminalHost.id, AppleTerminalHost.id]
    var devices: [Int32: String] = [:]
    var agentInForeground = true
    /// What Ghostty's focused-pane query prints.
    var focused = ""
    var refuse = false
    var activated: [String] = []

    @MainActor
    func make() -> AgentTerminals {
        AgentTerminals(system: TerminalSystem(
            run: { command, _ in try self.record(command) },
            isRunning: { self.running.contains($0) },
            activate: { self.activated.append($0); return self.running.contains($0) },
            device: { self.devices[$0] },
            agentHoldsForeground: { _ in self.agentInForeground }
        ))
    }

    private func record(_ command: TerminalCommand) throws -> String {
        if refuse { throw TerminalCommandFailure(errorDescription: "not authorized") }
        commands.append(command)
        // Ghostty's focused-pane query is the one command without arguments.
        return command.arguments.isEmpty ? focused : "OK\n"
    }
}

@main
struct AgentConversationRegression {
    static let threadID = "12345678-1234-4123-8123-123456789abc"
    static let otherThreadID = "22345678-1234-4123-8123-123456789abc"
    static let sessionID = AgentSession.key(sourceID: "codex", sessionKey: threadID)

    /// A terminal's thread as the shared service reports it: TUI threads there say `vscode`.
    static func terminalThread(_ id: String = threadID, status: String = "idle") -> [String: Any] {
        ["id": id, "name": "Original task", "cwd": "/tmp/project", "source": "vscode", "originator": "codex-tui",
         "canAcceptDirectInput": true, "status": ["type": status], "updatedAt": Date().timeIntervalSince1970]
    }

    static func hook(_ phase: AgentEventPhase, source: String = "codex", key: String = threadID, prompt: String? = nil,
                     reply: String? = nil, tool: String? = nil, host: String? = "com.mitchellh.ghostty",
                     at date: Date = Date()) -> AgentHookEvent {
        AgentHookEvent(sourceID: source, phase: phase, sessionKey: key, cwd: "/tmp/project", prompt: prompt,
                       toolName: tool, toolKind: tool == nil ? nil : .command, toolDetail: tool,
                       message: nil, lastReply: reply, hostBundleID: host, receivedAt: date)
    }

    @MainActor
    static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
        precondition(condition(), "timed out")
    }

    @MainActor
    static func main() async throws {
        defer { discardDefaults() }
        verifyModel()
        verifyProjection()
        try verifyStore()
        try await verifyLiveTerminal()
        try await verifySending()
        try await verifyReadOnlyTerminal()
        try verifyTranscripts()
        try verifyHookInstall()
        try await verifyHookReplies()
        try await verifyHookScript()
        verifyTerminalCommands()
        try await verifyTerminals()
        try verifyTemporaryFileCleanup()
        try verifyWebSocket()
        if CommandLine.arguments.count > 1 { try await verifyProcessTransport(CommandLine.arguments[1]) }
    }

    @MainActor
    static func verifyModel() {
        let started = AgentSession.starting(with: hook(.promptSubmitted, prompt: "First question"))
        let working = started.applying(hook(.toolStarted, tool: "git status"))
        precondition(working.messages.map(\.role) == [.user, .activity] && working.messages[1].text == "git status")
        let done = working.applying(hook(.turnFinished, reply: "First answer"))
        precondition(done.messages.map(\.text) == ["First question", "git status", "First answer"] && done.state == .finished)
        let ended = done.applying(hook(.sessionEnded))
        precondition(ended.isDisconnected && ended.messages.count == 3)
        let quiet = done.applying(hook(.promptSubmitted, prompt: "Next"), recordingMessages: false)
        precondition(quiet.messages.count == 3 && quiet.state == .thinking && quiet.lastReply == nil,
                     "a session with a live feed takes lifecycle, not messages, from hooks")

        var bounded = started
        for index in 0..<(AgentSession.messageLimit + 5) { bounded.upsertMessage(.activity(id: "\(index)", kind: .read, detail: "f")) }
        precondition(bounded.messages.count == AgentSession.messageLimit)

        // Terminal or desktop: a hook names the host; a Codex thread names who started it.
        precondition(started.isTerminalSession)
        precondition(!AgentSession.starting(with: hook(.sessionStarted, host: "com.openai.codex")).isTerminalSession)
        precondition(AgentSession.starting(with: hook(.sessionStarted, source: "claude", host: nil)).isTerminalSession)
        print("PASS: hook lifecycle, activity lines, live-feed hooks, bounded history, terminal detection")
    }

    static func verifyProjection() {
        let live = CodexSessionProjection.session(terminalThread(), existing: nil, live: true)!
        precondition(live.isTerminalSession && live.canAcceptDirectInput == true)
        var desktop = terminalThread()
        desktop["originator"] = "Codex Desktop"
        precondition(!CodexSessionProjection.session(desktop, existing: nil, live: true)!.isTerminalSession)
        var saved = terminalThread(status: "notLoaded")
        saved["source"] = "cli"
        let reader = CodexSessionProjection.session(saved, existing: nil, live: false)!
        precondition(reader.isTerminalSession && reader.canAcceptDirectInput == false && !reader.isDisconnected,
                     "a private reader's notLoaded says nothing about the terminal")
        precondition(!CodexSessionProjection.isFollowable(["id": threadID, "source": ["subAgent": [:]]]))
        precondition(!CodexSessionProjection.isFollowable(["id": threadID, "source": "vscode", "ephemeral": true]))

        var session = live
        session.state = .thinking
        CodexSessionProjection.applyStatus(["type": "active", "activeFlags": ["waitingOnApproval"]], to: &session)
        precondition(session.state.needsAttention)
        CodexSessionProjection.applyStatus(["type": "idle"], to: &session)
        precondition(session.state == .finished && session.finishedAt != nil)
        CodexSessionProjection.applyStatus(["type": "notLoaded"], to: &session)
        precondition(session.isDisconnected && session.canAcceptDirectInput == false)

        let turns: [[String: Any]] = [["items": [
            ["id": "u", "type": "userMessage", "content": [["type": "text", "text": "Visible question"], ["type": "image", "url": "x"]]],
            ["id": "r", "type": "reasoning", "summary": ["HIDDEN"], "content": ["HIDDEN"]],
            ["id": "c", "type": "agentMessage", "phase": "commentary", "text": "Checking the repo"],
            ["id": "x", "type": "commandExecution", "command": "/bin/zsh -lc 'git status'", "aggregatedOutput": "HIDDEN",
             "commandActions": [["type": "unknown", "command": "git status"]]],
            ["id": "y", "type": "commandExecution", "command": "/bin/zsh -lc 'cat README.md'", "aggregatedOutput": "HIDDEN",
             "commandActions": [["type": "read", "command": "cat README.md", "name": "README.md", "path": "/tmp/README.md"]]],
            ["id": "f", "type": "fileChange", "changes": [["path": "/tmp/a.swift", "diff": "HIDDEN"], ["path": "/tmp/b.swift", "diff": "HIDDEN"]]],
            ["id": "p", "type": "plan", "text": "HIDDEN"],
            ["id": "a", "type": "agentMessage", "phase": "final_answer", "text": "Visible answer"],
        ]]]
        let lines = CodexSessionProjection.messages(turns: turns)
        precondition(lines.map(\.text) == ["Visible question\n\n[Image]", "Checking the repo", "git status", "README.md", "a.swift, b.swift", "Visible answer"])
        precondition(lines.map(\.role) == [.user, .assistant, .activity, .activity, .activity, .assistant])
        precondition(lines.compactMap(\.toolKind) == [.command, .read, .edit])
        precondition(!lines.contains { $0.text.contains("HIDDEN") }, "tool output, reasoning and plans stay out")
        precondition(CodexSessionProjection.unwrappedShellCommand("bash -lc 'echo '\\''hi'\\'''") == "echo 'hi'")
        print("PASS: terminal/desktop threads, statuses, conversation lines without output or reasoning")
    }

    @MainActor
    static func verifyStore() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-agents-\(UUID())")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let cache = temp.appendingPathComponent("sessions.json")
        let saved = AgentSessionStore(persistenceURL: cache)
        saved.apply(hook(.promptSubmitted, prompt: "Recent"))
        saved.apply(hook(.promptSubmitted, key: otherThreadID, prompt: "Old", at: Date(timeIntervalSinceNow: -2 * AgentSessionStore.staleSessionInterval)))
        saved.save()
        let restored = AgentSessionStore(persistenceURL: cache)
        precondition(restored.sessions.map(\.sessionKey) == [threadID], "only sessions active recently come back")
        precondition(restored.sessions[0].isDisconnected && restored.closedNotchHighlight() == nil)
        restored.remove(restored.sessions[0]); restored.save()
        let hidden = AgentSessionStore(persistenceURL: cache)
        hidden.upsert(CodexSessionProjection.session(terminalThread(), existing: nil, live: true)!)
        precondition(hidden.sessions.isEmpty && hidden.isHidden(sessionID))

        let store = AgentSessionStore(persistenceURL: nil)
        store.apply(hook(.promptSubmitted, prompt: "Hi"))
        store.setLiveFeed(sessionID, true)
        store.apply(hook(.turnFinished, reply: "Hook reply"))
        precondition(store.session(id: sessionID)!.messages.count == 1 && store.session(id: sessionID)!.state == .finished)
        store.pruneStaleSessions(now: Date(timeIntervalSinceNow: AgentSessionStore.staleSessionInterval + 1))
        precondition(store.sessions.isEmpty && !store.hasLiveFeed(sessionID), "quiet sessions leave the notch")

        // Removing every ended card is one change, and the removed ids are
        // forgotten once nothing but a new turn could bring the cards back.
        let ended = AgentSessionStore(persistenceURL: nil)
        for key in ["a", "b", "c"] {
            ended.apply(hook(.promptSubmitted, key: key, prompt: key))
            ended.apply(hook(.sessionEnded, key: key))
        }
        ended.apply(hook(.promptSubmitted, key: "live", prompt: "still working"))
        var changes = 0
        let watcher = ended.objectWillChange.sink { changes += 1 }
        ended.remove(ended.sessions.filter(\.isDisconnected))
        watcher.cancel()
        precondition(changes == 1 && ended.sessions.map(\.sessionKey) == ["live"])
        let removedAt = Date()
        precondition(["a", "b", "c"].allSatisfy { ended.isHidden(AgentSession.key(sourceID: "codex", sessionKey: $0)) })
        ended.pruneStaleSessions(now: removedAt.addingTimeInterval(AgentSessionStore.staleSessionInterval - 60))
        precondition(ended.isHidden(AgentSession.key(sourceID: "codex", sessionKey: "a")), "kept while the card could come back")
        ended.pruneStaleSessions(now: removedAt.addingTimeInterval(AgentSessionStore.staleSessionInterval + 1))
        precondition(!ended.isHidden(AgentSession.key(sourceID: "codex", sessionKey: "a")), "forgotten afterwards")

        // A cache written before removal times were kept still loads.
        try Data(#"{"sessions":[],"hiddenIDs":["\#(sessionID)"]}"#.utf8).write(to: cache)
        precondition(AgentSessionStore(persistenceURL: cache).isHidden(sessionID))
        print("PASS: persistence, recent-only restore, hidden cards, live-feed hooks, quiet sessions leave, remove ended in one change, removed ids expire, old cache format")
    }

    /// A suite named by a path keeps its plist in the temporary folder. A named
    /// suite would leave an empty plist in ~/Library/Preferences even once
    /// emptied, which the preferences daemon writes back if it is deleted.
    static let defaultsFolder = FileManager.default.temporaryDirectory
        .appending(path: "atoll-agent-regression-\(ProcessInfo.processInfo.processIdentifier)")
    static let defaultsSuite: String = {
        try! FileManager.default.createDirectory(at: defaultsFolder, withIntermediateDirectories: true)
        return defaultsFolder.appending(path: "defaults").path
    }()

    static func discardDefaults() {
        UserDefaults(suiteName: defaultsSuite)!.removePersistentDomain(forName: defaultsSuite)
        try? FileManager.default.removeItem(at: defaultsFolder)
    }

    /// Each service starts from empty delivery receipts in a throwaway defaults suite.
    @MainActor
    static func makeService(_ client: FakeCodexClient, store: AgentSessionStore,
                            terminals: FakeTerminals = FakeTerminals()) -> (AgentConversationService, UserDefaults) {
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defaults.removePersistentDomain(forName: defaultsSuite)
        return (AgentConversationService(store: store, defaults: defaults, client: client, terminals: terminals.make(),
                                         executablePath: { "/fake/codex" }), defaults)
    }

    @MainActor
    static func verifyLiveTerminal() async throws {
        let client = FakeCodexClient()
        client.threads = [threadID: terminalThread(), otherThreadID: terminalThread(otherThreadID)]
        client.loaded = [threadID, otherThreadID]
        client.unmaterialized = [otherThreadID]
        var desktop = terminalThread("32345678-1234-4123-8123-123456789abc")
        desktop["originator"] = "Codex Desktop"
        client.threads[desktop["id"] as! String] = desktop
        client.loaded.append(desktop["id"] as! String)
        let store = AgentSessionStore(persistenceURL: nil)
        let (service, _) = makeService(client, store: store)
        service.start()
        defer { service.stop() }
        try await waitUntil { store.hasLiveFeed(sessionID) }
        precondition(client.resumed == [threadID], "only a saved terminal thread the service holds is followed")
        precondition(store.sessions.count == 1 && service.isLive && service.canSend(store.session(id: sessionID)!))

        client.unmaterialized.removeAll()
        await service.refresh()
        precondition(client.resumed == [threadID, otherThreadID], "a new thread is followed once its first message is saved")
        precondition(client.methods.filter { $0 == "thread/read" }.count == 4, "desktop threads are not reread every pass")

        // The stream the terminal renders, in order.
        client.onEvent?("turn/started", ["threadId": threadID, "turn": ["id": "t1"]])
        precondition(store.session(id: sessionID)!.state == .thinking)
        client.onEvent?("item/started", ["threadId": threadID, "item": ["id": "u1", "type": "userMessage", "content": [["type": "text", "text": "Typed in terminal"]]]])
        client.onEvent?("item/started", ["threadId": threadID, "item": ["id": "x1", "type": "commandExecution", "command": "/bin/zsh -lc 'ls'"]])
        precondition(store.session(id: sessionID)!.state == .tool(.command, name: "", detail: "ls"))
        client.onEvent?("item/completed", ["threadId": threadID, "item": ["id": "x1", "type": "commandExecution", "command": "/bin/zsh -lc 'ls'", "aggregatedOutput": "a\nb"]])
        client.onEvent?("item/started", ["threadId": threadID, "item": ["id": "a1", "type": "agentMessage", "text": ""]])
        client.onEvent?("item/agentMessage/delta", ["threadId": threadID, "delta": "Live "])
        client.onEvent?("item/agentMessage/delta", ["threadId": threadID, "delta": "answer"])
        precondition(service.streaming[sessionID] == "Live answer")
        // The terminal's own hooks arrive too; they must not duplicate the feed.
        store.apply(hook(.promptSubmitted, prompt: "Typed in terminal"))
        client.onEvent?("item/completed", ["threadId": threadID, "item": ["id": "a1", "type": "agentMessage", "phase": "final_answer", "text": "Live answer"]])
        client.onEvent?("turn/completed", ["threadId": threadID, "turn": ["id": "t1", "status": "completed"]])
        var session = store.session(id: sessionID)!
        precondition(session.messages.map(\.text) == ["Typed in terminal", "ls", "Live answer"])
        precondition(session.state == .finished && service.streaming[sessionID] == nil && session.lastReply == "Live answer")

        // Opening the conversation loads saved turns; lines the feed added after them stay.
        client.turns = [["items": [["id": "u0", "type": "userMessage", "content": [["type": "text", "text": "Earlier"]]],
                                   ["id": "u1", "type": "userMessage", "content": [["type": "text", "text": "Typed in terminal"]]]]]]
        await service.loadHistory(id: sessionID, force: true)
        session = store.session(id: sessionID)!
        precondition(session.messages.map(\.text) == ["Earlier", "Typed in terminal", "ls", "Live answer"])

        client.onEvent?("thread/status/changed", ["threadId": threadID, "status": ["type": "active", "activeFlags": ["waitingOnUserInput"]]])
        precondition(!service.canSend(store.session(id: sessionID)!), "a terminal waiting on its own question is answered there")
        client.onEvent?("thread/closed", ["threadId": threadID])
        try await waitUntil { client.unsubscribed.contains(threadID) }
        precondition(!store.hasLiveFeed(sessionID) && store.session(id: sessionID)!.isDisconnected)

        client.close()
        precondition(!service.isLive && !store.hasLiveFeed(AgentSession.key(sourceID: "codex", sessionKey: otherThreadID)))
        precondition(store.sessions.count == 2, "losing Atoll's connection does not end terminal sessions")
        print("PASS: follows only loaded terminal threads, live items and streaming, hook de-duplication, history merge, close and reconnect")
    }

    @MainActor
    static func verifySending() async throws {
        for scenario in ["accepted", "uncertain", "rejected", "hook-ended"] {
            let client = FakeCodexClient()
            client.threads = [threadID: terminalThread()]
            client.loaded = [threadID]
            client.rejectStart = scenario == "rejected"
            client.loseTurnAck = scenario == "uncertain"
            let store = AgentSessionStore(persistenceURL: nil)
            let (service, defaults) = makeService(client, store: store)
            service.start()
            try await waitUntil { store.hasLiveFeed(sessionID) }
            if scenario == "hook-ended" {
                store.apply(hook(.sessionEnded))
                precondition(!service.canSend(store.session(id: sessionID)!))
                store.apply(hook(.sessionStarted))
                precondition(service.canSend(store.session(id: sessionID)!), "resuming the terminal restores sending")
                service.stop()
                continue
            }
            service.drafts[sessionID] = "Continue this exact thread"
            service.send(id: sessionID); service.send(id: sessionID)
            try await waitUntil { !service.sending.contains(sessionID) }
            precondition(client.starts.count <= 1, "one click sends once")
            switch scenario {
            case "accepted":
                precondition(client.starts.count == 1 && client.starts[0]["threadId"] as? String == threadID)
                let commandID = client.starts[0]["clientUserMessageId"] as! String
                precondition(service.drafts[sessionID] == "" && !service.uncertainIDs.contains(sessionID))
                precondition(store.session(id: sessionID)!.messages.map(\.id) == [commandID])
                // Codex echoes the message as an item; it replaces the optimistic line.
                client.onEvent?("item/started", ["threadId": threadID, "item": ["id": "item-1", "type": "userMessage", "clientId": commandID,
                                                                                "content": [["type": "text", "text": "Continue this exact thread"]]]])
                precondition(store.session(id: sessionID)!.messages.map(\.id) == ["item-1"])
                precondition(service.canInterrupt(store.session(id: sessionID)!))
                client.onRequest?(9, "item/commandExecution/requestApproval", ["threadId": threadID, "command": "pwd"])
                precondition(service.approvals.count == 1 && client.replies.isEmpty)
                service.answerApproval(service.approvals[0], allow: false)
                precondition(client.replies.last?["decision"] as? String == "decline")
            case "uncertain":
                precondition(service.uncertainIDs.contains(sessionID) && service.drafts[sessionID] != "")
                let relaunched = AgentConversationService(store: store, defaults: defaults, client: FakeCodexClient(),
                                                          terminals: FakeTerminals().make())
                precondition(relaunched.uncertainIDs.contains(sessionID), "an unconfirmed send survives a relaunch")
                service.send(id: sessionID)
                precondition(client.starts.count == 1, "never retried automatically")
            default:
                precondition(service.errors[sessionID] != nil && service.drafts[sessionID] != "" && !service.uncertainIDs.contains(sessionID))
            }
            service.stop()
        }
        // Another client's approval is never answered or rejected by Atoll.
        let client = FakeCodexClient()
        client.threads = [threadID: terminalThread()]
        client.loaded = [threadID]
        let store = AgentSessionStore(persistenceURL: nil)
        let (service, _) = makeService(client, store: store)
        service.start()
        try await waitUntil { store.hasLiveFeed(sessionID) }
        client.onRequest?(3, "item/commandExecution/requestApproval", ["threadId": threadID, "command": "rm -rf /tmp/x"])
        precondition(service.approvals.isEmpty && client.replies.isEmpty)
        service.stop()
        print("PASS: exact-thread delivery, duplicate suppression, echo replaces optimistic line, uncertain and rejected sends, terminal-ended guard, approvals")
    }

    @MainActor
    static func verifyReadOnlyTerminal() async throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-rollout-\(UUID()).jsonl")
        try Data("{}\n".utf8).write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }
        let client = FakeCodexClient()
        client.isSharedDaemon = false
        client.sharedServiceAvailable = false
        client.turns = [["items": [["id": "u", "type": "userMessage", "content": [["type": "text", "text": "Question"]]]]]]
        let store = AgentSessionStore(persistenceURL: nil)
        let (service, _) = makeService(client, store: store)
        service.start()
        defer { service.stop() }
        await service.refresh()
        precondition(!client.isReady, "no reader runs until a Codex conversation is open")

        var event = hook(.promptSubmitted, prompt: "Question")
        event.transcriptPath = temp.path
        store.apply(event)
        service.selectedID = sessionID
        await service.refresh()
        precondition(client.isReady && store.session(id: sessionID)!.messages.map(\.id) == ["u"])
        precondition(!service.canSend(store.session(id: sessionID)!) && !client.methods.contains("thread/resume"),
                     "a terminal without the shared service is only read, never resumed")
        let reads = client.methods.filter { $0 == "thread/turns/list" }.count
        await service.refresh()
        precondition(client.methods.filter { $0 == "thread/turns/list" }.count == reads, "unchanged file, no reread")
        client.turns[0]["items"] = (client.turns[0]["items"] as! [[String: Any]]) + [["id": "a", "type": "agentMessage", "text": "Answer"]]
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 5)], ofItemAtPath: temp.path)
        await service.refresh()
        precondition(store.session(id: sessionID)!.messages.map(\.text) == ["Question", "Answer"], "a changed file is reread")
        print("PASS: no-daemon terminals are read-only, read on open and whenever their file changes")
    }

    static func verifyTranscripts() throws {
        let envelope = AtollMessageEnvelope.wrap(id: "cmd-1", text: "Ship it")
        let echoed = "<task-notification>\n<summary>Stop hook feedback</summary>\n<system-reminder>\(envelope)\n</system-reminder>"
        precondition(AtollMessageEnvelope.unwrap(echoed)?.id == "cmd-1" && AtollMessageEnvelope.visibleUserText(echoed) == "Ship it")
        precondition(AtollMessageEnvelope.visibleUserText("<task-notification>build done</task-notification>") == nil)
        precondition(AtollMessageEnvelope.visibleUserText("  Fix it ") == "Fix it")

        let claude = ClaudeCodeAgentSource()
        let rows: [[String: Any]] = [
            ["type": "user", "uuid": "1", "message": ["role": "user", "content": "Fix the build"]],
            ["type": "user", "uuid": "2", "isMeta": true, "message": ["role": "user", "content": "HIDDEN meta"]],
            ["type": "assistant", "uuid": "3", "message": ["role": "assistant", "content": [
                ["type": "thinking", "thinking": "HIDDEN"],
                ["type": "text", "text": "Looking."],
                ["type": "tool_use", "id": "tu1", "name": "Bash", "input": ["command": "swift build"]],
            ]]],
            ["type": "user", "uuid": "4", "message": ["role": "user", "content": [["type": "tool_result", "content": "HIDDEN output"]]]],
            ["type": "user", "uuid": "5", "message": ["role": "user", "content": "<command-name>/clear</command-name>"]],
            ["type": "assistant", "uuid": "6", "isSidechain": true, "message": ["role": "assistant", "content": [["type": "text", "text": "HIDDEN subagent"]]]],
            ["type": "ai-title", "aiTitle": "Fix the build"],
            ["type": "user", "uuid": "8", "origin": ["kind": "task-notification"], "message": ["role": "user", "content": echoed]],
            ["type": "assistant", "uuid": "7", "message": ["role": "assistant", "content": [["type": "text", "text": "Done."]]]],
        ]
        let transcript = claude.transcript(from: rows)!
        precondition(transcript.messages.map(\.text) == ["Fix the build", "Looking.", "swift build", "Ship it", "Done."])
        precondition(transcript.messages[2].role == .activity && transcript.messages[2].toolKind == .command)
        precondition(transcript.title == "Fix the build")

        let agy = AntigravityAgentSource()
        let steps: [[String: Any]] = [
            ["step_index": 0, "type": "USER_INPUT", "content": "<USER_REQUEST>\nRun the tests\n</USER_REQUEST>\n<ADDITIONAL_METADATA>\nHIDDEN\n</ADDITIONAL_METADATA>"],
            ["step_index": 1, "type": "PLANNER_RESPONSE", "thinking": "HIDDEN", "tool_calls": [["name": "run_command", "args": ["CommandLine": "\"npm test\"", "Cwd": "\"/tmp\""]]]],
            ["step_index": 2, "type": "GENERIC", "content": "HIDDEN output"],
            ["step_index": 3, "type": "PLANNER_RESPONSE", "content": "All tests pass."],
        ]
        let agyLines = agy.transcript(from: steps)!.messages
        precondition(agyLines.map(\.text) == ["Run the tests", "npm test", "All tests pass."])
        precondition(agyLines[1].toolKind == .command)
        let inject = try JSONSerialization.jsonObject(with: agy.replyOutput("Also lint", atEvent: "PreInvocation")!) as! [String: Any]
        precondition(((inject["injectSteps"] as! [[String: Any]])[0]["userMessage"] as! String) == "Also lint")
        let keepGoing = try JSONSerialization.jsonObject(with: agy.replyOutput("Also lint", atEvent: "Stop")!) as! [String: Any]
        precondition(keepGoing["decision"] as? String == "continue" && (keepGoing["reason"] as! String).contains("Also lint"))
        precondition(agy.replyOutput("x", atEvent: "PostToolUse") == nil && claude.replyOutput("x", atEvent: "Stop") == nil)

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-claude-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let lines = try rows.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }
        try Data((String(repeating: "x", count: Int(AgentTranscriptFile.tailBytes)) + "\n" + lines.joined(separator: "\n") + "\n").utf8).write(to: file)
        let tail = AgentTranscriptFile.rows(AgentTranscriptFile.tail(path: file.path)!)
        precondition(claude.transcript(from: tail)!.messages.count == 5, "a long file is read from its end")
        print("PASS: Atoll envelope, Claude and Antigravity transcripts without hidden rows, Antigravity reply outputs, tail read")
    }

    static func verifyHookInstall() throws {
        let script = "/tmp/Atoll/AgentBridge/agent-hook.sh"
        let claude = ClaudeCodeAgentSource()
        let handlers = claude.hookHandlers(scriptPath: script)
        let stop = handlers["Stop"]!
        precondition(stop.count == 2 && stop[1]["asyncRewake"] as? Bool == true && (stop[1]["command"] as! String).hasSuffix("claude wait"))
        precondition(handlers["PreToolUse"]!.count == 1 && CodexAgentSource().hookHandlers(scriptPath: script)["Stop"]!.count == 1)
        // Antigravity takes any PreToolUse reply as a permission decision, for every session on the machine.
        precondition(AntigravityAgentSource().hookHandlers(scriptPath: script)["PreToolUse"] == nil)

        // Last release's hooks: one Stop handler. They read as outdated, and an update keeps the user's own hooks.
        let format = GroupedHookFormat()
        let user: [String: Any] = ["type": "command", "command": "say done"]
        var root: [String: Any] = ["hooks": ["Stop": [["hooks": [user]], ["hooks": [stop[0]]]]]]
        precondition(!format.containsAll(handlers, in: root) && format.containsAtoll(in: root))
        format.install(handlers, into: &root)
        precondition(format.containsAll(handlers, in: root))
        let groups = (root["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
        precondition(groups.count == 2 && NSDictionary(dictionary: (groups[0]["hooks"] as! [[String: Any]])[0]).isEqual(to: user))
        let before = try JSONSerialization.data(withJSONObject: root, options: .sortedKeys)
        format.install(handlers, into: &root)
        let after = try JSONSerialization.data(withJSONObject: root, options: .sortedKeys)
        precondition(after == before, "installing twice changes nothing")
        format.remove(from: &root)
        precondition(!format.containsAtoll(in: root))
        print("PASS: Claude's parked Stop hook installs beside the user's, upgrades old installs, idempotent and removable")
    }

    @MainActor
    static func verifyHookReplies() async throws {
        let store = AgentSessionStore(persistenceURL: nil)
        let (service, _) = makeService(FakeCodexClient(), store: store)
        service.start()
        defer { service.stop() }
        let claudeID = AgentSession.key(sourceID: "claude", sessionKey: threadID)
        let stopped = hook(.turnFinished, source: "claude", reply: "Done")
        _ = service.receive(hook(.promptSubmitted, source: "claude", prompt: "Build it"))
        _ = service.receive(stopped)
        precondition(!service.canSend(store.session(id: claudeID)!), "no parked hook yet")
        var replies: [Data?] = []
        service.park(stopped, reply: { replies.append($0) }, onClose: { _ in })
        precondition(service.canSend(store.session(id: claudeID)!))

        // The user answers in the terminal: the parked hook stands down.
        _ = service.receive(hook(.promptSubmitted, source: "claude", prompt: "Typed in terminal"))
        precondition(replies.count == 1 && replies[0] == nil && !service.canSend(store.session(id: claudeID)!))
        _ = service.receive(stopped)
        service.park(stopped, reply: { replies.append($0) }, onClose: { _ in })

        service.drafts[claudeID] = "From Atoll"
        service.send(id: claudeID); service.send(id: claudeID)
        precondition(replies.count == 2, "one click wakes once")
        let wake = String(decoding: replies[1]!, as: UTF8.self)
        let echo = AtollMessageEnvelope.unwrap(wake)!
        precondition(echo.prompt == "From Atoll" && service.sending.contains(claudeID))
        // Claude echoes the wake as its next prompt: delivered, shown unwrapped, draft cleared.
        _ = service.receive(hook(.promptSubmitted, source: "claude", prompt: "<task-notification>\n\(wake)\n</task-notification>"))
        precondition(!service.sending.contains(claudeID) && service.drafts[claudeID] == "")
        precondition(store.session(id: claudeID)!.messages.last?.text == "From Atoll" && store.session(id: claudeID)!.state == .thinking)

        // Antigravity: only while it works, handed over at its next step.
        let agyID = AgentSession.key(sourceID: "agy", sessionKey: threadID)
        var step = hook(.thinking, source: "agy")
        step.eventName = "PreInvocation"
        precondition(service.receive(step) == nil)
        precondition(service.canSend(store.session(id: agyID)!))
        service.drafts[agyID] = "Also lint"
        service.send(id: agyID)
        precondition(!service.canSend(store.session(id: agyID)!), "one message waits at a time")
        var toolDone = hook(.thinking, source: "agy")
        toolDone.eventName = "PostToolUse"
        precondition(service.receive(toolDone) == nil, "PostToolUse cannot carry a message")
        let output = service.receive(step)!
        precondition(String(decoding: output, as: UTF8.self).contains("Also lint") && service.receive(step) == nil)
        precondition(!service.sending.contains(agyID) && store.session(id: agyID)!.messages.last?.text == "Also lint")
        var done = hook(.turnFinished, source: "agy")
        done.eventName = "Stop"
        _ = service.receive(done)
        precondition(!service.canSend(store.session(id: agyID)!), "an idle Antigravity cannot be reached")
        print("PASS: Claude wakes once from a parked hook, terminal input releases it, echo confirms; Antigravity takes messages at its next step while working")
    }

    /// The real hook script against the real event server: a parked Claude hook
    /// exits 2 with the message on stderr, and an Antigravity step prints its injection.
    @MainActor
    static func verifyHookScript() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("atoll-bridge-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AgentSessionStore(persistenceURL: nil)
        let terminals = FakeTerminals()
        let (service, _) = makeService(FakeCodexClient(), store: store, terminals: terminals)
        service.start()
        let bridge = AgentBridge(directory: directory, receiver: service)
        bridge.start()
        defer { bridge.stop(); service.stop() }
        try await waitUntil { FileManager.default.fileExists(atPath: directory.appendingPathComponent("port").path) }
        let script = directory.appendingPathComponent("agent-hook.sh").path

        func run(_ arguments: [String], payload: [String: Any], environment: [String: String] = [:]) throws -> Process {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [script] + arguments
            // Only what each case sets: not the terminal the suite runs in.
            let inherited = ProcessInfo.processInfo.environment.filter { key, _ in
                !["ATOLL_SUPPRESS_HOOKS", "CLAUDE_CODE_SESSION_KIND", "__CFBundleIdentifier"].contains(key)
                    && !key.hasPrefix("CMUX_") && !key.hasPrefix("GHOSTTY_")
            }
            process.environment = inherited.merging(environment) { $1 }
            let input = Pipe()
            process.standardInput = input
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            input.fileHandleForWriting.write(try JSONSerialization.data(withJSONObject: payload))
            try input.fileHandleForWriting.close()
            return process
        }
        // Atoll answers hooks on the main actor, so never block it while one runs.
        func finished(_ process: Process) async throws -> Process {
            while process.isRunning { try await Task.sleep(for: .milliseconds(10)) }
            return process
        }
        func output(_ process: Process, _ keyPath: KeyPath<Process, Any?>) -> String {
            String(decoding: ((process[keyPath: keyPath] as! Pipe).fileHandleForReading.readDataToEndOfFile()), as: UTF8.self)
        }

        let claudeID = AgentSession.key(sourceID: "claude", sessionKey: threadID)
        let payload: [String: Any] = ["session_id": threadID, "cwd": "/tmp/project", "last_assistant_message": "Done"]
        let stop = try await finished(try run(["claude", "Stop"], payload: payload))
        precondition(stop.terminationStatus == 0 && output(stop, \.standardOutput).isEmpty, "Claude's hooks print nothing")
        try await waitUntil { store.session(id: claudeID)?.state == .finished }

        let notInteractive = try await finished(try run(["claude", "wait"], payload: payload, environment: ["CLAUDE_CODE_ENTRYPOINT": "sdk-cli"]))
        precondition(notInteractive.terminationStatus == 0, "`claude -p` never waits")

        let wait = try run(["claude", "wait"], payload: payload, environment: ["CLAUDE_CODE_ENTRYPOINT": "cli"])
        try await waitUntil { service.canSend(store.session(id: claudeID)!) }
        service.drafts[claudeID] = "Hello from the notch"
        service.send(id: claudeID)
        _ = try await finished(wait)
        precondition(wait.terminationStatus == 2 && AtollMessageEnvelope.unwrap(output(wait, \.standardError))?.prompt == "Hello from the notch")

        // A parked hook the agent gives up on leaves nothing behind.
        let abandoned = try run(["claude", "wait"], payload: payload, environment: ["CLAUDE_CODE_ENTRYPOINT": "cli"])
        try await waitUntil { service.parkedSessions.contains(claudeID) }
        abandoned.terminate()
        try await waitUntil { !service.parkedSessions.contains(claudeID) }

        let agyPayload: [String: Any] = ["conversationId": threadID, "workspacePaths": ["/tmp/project"], "invocationNum": 1]
        let agyID = AgentSession.key(sourceID: "agy", sessionKey: threadID)
        let first = try await finished(try run(["agy", "PreInvocation", "{}"], payload: agyPayload))
        precondition(output(first, \.standardOutput) == "{}", "the neutral reply when nothing waits")
        try await waitUntil { store.session(id: agyID) != nil }
        service.drafts[agyID] = "Also run lint"
        service.send(id: agyID)
        let next = try await finished(try run(["agy", "PreInvocation", "{}"], payload: agyPayload))
        let injected = try JSONSerialization.jsonObject(with: Data(output(next, \.standardOutput).utf8)) as! [String: Any]
        precondition(((injected["injectSteps"] as! [[String: Any]])[0]["userMessage"] as! String) == "Also run lint")

        // Where the agent runs: the hosting app's own pane variable, and the
        // hook's parent (this process) for the terminal device.
        terminals.devices[getpid()] = "/dev/ttys990"
        let cmuxPane = "11111111-2222-4333-8444-555555555555"
        let panePayload: [String: Any] = ["session_id": "pane-session", "cwd": "/tmp/project"]
        let paneID = AgentSession.key(sourceID: "claude", sessionKey: "pane-session")
        _ = try await finished(try run(["claude", "SessionStart"], payload: panePayload,
                                       environment: ["__CFBundleIdentifier": "com.cmuxterm.app", "CMUX_SURFACE_ID": cmuxPane]))
        try await waitUntil { store.session(id: paneID)?.terminalPane == cmuxPane }
        precondition(store.session(id: paneID)?.terminalDevice == "/dev/ttys990")
        // A Terminal started from cmux inherits CMUX_SURFACE_ID; its pane is its tty.
        _ = try await finished(try run(["claude", "SessionStart"], payload: panePayload,
                                       environment: ["__CFBundleIdentifier": "com.apple.Terminal", "CMUX_SURFACE_ID": cmuxPane]))
        try await waitUntil { store.session(id: paneID)?.hostBundleID == "com.apple.Terminal" }
        precondition(store.session(id: paneID)?.terminalPane == "/dev/ttys990")
        // Anything but a plain id never leaves the hook.
        _ = try await finished(try run(["claude", "SessionStart"], payload: panePayload,
                                       environment: ["__CFBundleIdentifier": "com.cmuxterm.app", "CMUX_SURFACE_ID": "x&pid=1"]))
        try await waitUntil { store.session(id: paneID)?.hostBundleID == "com.cmuxterm.app" }
        precondition(store.session(id: paneID)?.terminalPane == nil && terminals.commands.isEmpty)
        print("PASS: hook script parks and exits 2 with the message, skips non-interactive Claude, cleans up abandoned waits, injects Antigravity steps, reports its pane and process")
    }

    /// What each terminal is asked to run: a multi-line message stays one
    /// message (a new-line key between lines, Return once), and control characters never go through.
    static func verifyTerminalCommands() {
        let message = "one\r\n-two \u{1b}[201~\u{3}\n\nfour ä"
        precondition(TerminalText.lines(message) == ["one", "-two [201~", "", "four ä"])

        // cmux: typed text travels beside the arguments, never as one of them.
        let send = ["send", "--surface", "P", "--"]
        func key(_ name: String) -> [String] { ["send-key", "--surface", "P", "--", name] }
        let cmux = CmuxTerminalHost().typeCommands(text: message, pane: "P")
        precondition(cmux.map(\.arguments) == [send, key("shift+enter"), send, key("shift+enter"), key("shift+enter"), send, key("enter")])
        precondition(cmux.map(\.text) == ["one", nil, "-two [201~", nil, nil, "four ä", nil])
        precondition(CmuxTerminalHost().focusCommands(pane: "P").map(\.arguments) == [["focus-panel", "--panel", "P"]])
        // `send` would read "\n" as Return: the pair is split across two sends.
        precondition(CmuxTerminalHost.literalPieces(#"print("a\n")"#) == [#"print("a\"#, #"n")"#])
        precondition(CmuxTerminalHost.literalPieces(#"c:\\new \f \"#) == [#"c:\\"#, #"new \f \"#])
        precondition(CmuxTerminalHost.literalPieces(#"\t"#) == [#"\"#, "t"] && CmuxTerminalHost.literalPieces("plain") == ["plain"])

        // AppleScript gets the pane as an argument and the text from a file, never inside its source.
        for host in [GhosttyTerminalHost() as TerminalHost, AppleTerminalHost()] {
            let typing = host.typeCommands(text: message, pane: "P\" & quit")
            precondition(typing.count == 1 && typing[0].arguments == ["P\" & quit"] && typing[0].text == "one\n-two [201~\n\nfour ä")
            guard case .appleScript(let source) = typing[0].program else { preconditionFailure() }
            precondition(!source.contains("quit") && !source.contains("four"))
            precondition(host.focusCommands(pane: "P").map(\.arguments) == [["P"]])
        }
        precondition(TerminalHostRegistry.host(bundleIdentifier: "COM.CMUXTERM.APP") is CmuxTerminalHost)
        precondition(TerminalHostRegistry.host(bundleIdentifier: "com.googlecode.iterm2") == nil)
        print("PASS: cmux types line by line with Shift+Return and splits its escapes, AppleScript reads text from a file, control characters dropped, registry lookup")
    }

    /// Finding each session's pane, and typing into it only while the agent still holds it.
    @MainActor
    static func verifyTerminals() async throws {
        let store = AgentSessionStore(persistenceURL: nil)
        let fake = FakeTerminals()
        let (service, _) = makeService(FakeCodexClient(), store: store, terminals: fake)
        service.start()
        defer { service.stop() }
        func event(_ phase: AgentEventPhase, key: String, host: String, pane: String? = nil, pid: Int32? = 7,
                   prompt: String? = nil) -> AgentHookEvent {
            var event = hook(phase, source: "claude", key: key, prompt: prompt, host: host)
            event.hostPane = pane
            event.hostProcessID = pid
            return event
        }
        fake.devices = [7: "/dev/ttys007", 8: "/dev/ttys008"]

        // cmux: the pane its environment named, once the hook runs inside a terminal.
        let cmuxID = AgentSession.key(sourceID: "claude", sessionKey: "cmux")
        _ = service.receive(event(.sessionStarted, key: "cmux", host: "com.cmuxterm.app", pane: "S1", pid: 99))
        precondition(store.session(id: cmuxID)!.terminalPane == nil, "a hook outside any terminal (a background service) says nothing")
        _ = service.receive(event(.promptSubmitted, key: "cmux", host: "com.cmuxterm.app", pane: "S1", prompt: "Build it"))
        precondition(store.session(id: cmuxID)!.terminalPane == "S1" && store.session(id: cmuxID)!.terminalDevice == "/dev/ttys007")
        // Working: a message still goes in, as it would from the keyboard.
        precondition(service.route(for: store.session(id: cmuxID)!) == .terminal("cmux"))
        service.drafts[cmuxID] = "Also add tests\nplease"
        service.send(id: cmuxID)
        try await waitUntil { !service.sending.contains(cmuxID) }
        precondition(fake.commands.map { $0.text ?? $0.arguments.last! } == ["Also add tests", "shift+enter", "please", "enter"])
        precondition(service.drafts[cmuxID] == "" && service.notices[cmuxID] != nil && service.errors[cmuxID] == nil)
        _ = service.receive(event(.promptSubmitted, key: "cmux", host: "com.cmuxterm.app", pane: "S1", prompt: "Also add tests\nplease"))
        precondition(service.notices[cmuxID] == nil, "the agent took it; the conversation shows it now")

        // Never type where the agent is gone (a shell would run it), into a
        // pending approval, or into a terminal that is not running.
        fake.commands.removeAll()
        fake.agentInForeground = false
        service.drafts[cmuxID] = "rm -rf build"
        service.send(id: cmuxID)
        try await waitUntil { service.errors[cmuxID] != nil }
        precondition(fake.commands.isEmpty && service.drafts[cmuxID] == "rm -rf build")
        fake.agentInForeground = true
        _ = service.receive(event(.needsAttention, key: "cmux", host: "com.cmuxterm.app", pane: "S1"))
        precondition(!service.canSend(store.session(id: cmuxID)!), "typed text would answer the approval")
        _ = service.receive(event(.thinking, key: "cmux", host: "com.cmuxterm.app", pane: "S1"))
        fake.running.remove("com.cmuxterm.app")
        precondition(!service.canSend(store.session(id: cmuxID)!))
        fake.running.insert("com.cmuxterm.app")
        fake.refuse = true
        service.send(id: cmuxID)
        try await waitUntil { !service.sending.contains(cmuxID) }
        precondition(service.errors[cmuxID]!.contains("Automation"), "a refused command says what to allow")
        fake.refuse = false

        // A new process in another terminal: the old pane no longer applies.
        _ = service.receive(event(.sessionStarted, key: "cmux", host: "com.cmuxterm.app", pid: 8))
        precondition(store.session(id: cmuxID)!.terminalDevice == "/dev/ttys008" && store.session(id: cmuxID)!.terminalPane == nil)

        // Terminal: the pane is the tty.
        let terminalID = AgentSession.key(sourceID: "claude", sessionKey: "terminal")
        _ = service.receive(event(.sessionStarted, key: "terminal", host: "com.apple.Terminal"))
        precondition(store.session(id: terminalID)!.terminalPane == "/dev/ttys007")

        // Ghostty: the focused pane when the user acts, if it is in the session's folder.
        let ghosttyID = AgentSession.key(sourceID: "claude", sessionKey: "ghostty")
        fake.commands.removeAll()
        fake.focused = "G1\n/tmp/project\n"
        _ = service.receive(event(.sessionStarted, key: "ghostty", host: GhosttyTerminalHost.id))
        try await waitUntil { store.session(id: ghosttyID)?.terminalPane == "G1" }
        fake.focused = "G2\n/somewhere/else\n"
        _ = service.receive(event(.promptSubmitted, key: "ghostty", host: GhosttyTerminalHost.id, prompt: "From the keyboard"))
        try await waitUntil { fake.commands.count == 2 }
        precondition(store.session(id: ghosttyID)?.terminalPane == "G1", "another folder is another session's pane")
        _ = service.receive(event(.turnFinished, key: "ghostty", host: GhosttyTerminalHost.id))
        service.drafts[ghosttyID] = "Typed by Atoll"
        service.send(id: ghosttyID)
        try await waitUntil { !service.sending.contains(ghosttyID) }
        precondition(fake.commands.last!.arguments == ["G1"] && fake.commands.last!.text == "Typed by Atoll")
        let queries = fake.commands.count
        fake.focused = "G3\n/tmp/project\n"
        _ = service.receive(event(.promptSubmitted, key: "ghostty", host: GhosttyTerminalHost.id, prompt: "Typed by Atoll"))
        try await Task.sleep(for: .milliseconds(50))
        precondition(fake.commands.count == queries && store.session(id: ghosttyID)?.terminalPane == "G1",
                     "Atoll's own message says nothing about which pane is focused")

        // Open Terminal: the pane when known, else the app; never an app that is not running.
        fake.commands.removeAll()
        let atPane = await service.openTerminal(store.session(id: ghosttyID)!)
        precondition(atPane == .pane && fake.activated.last == GhosttyTerminalHost.id)
        let appOnly = await service.openTerminal(store.session(id: cmuxID)!)
        precondition(appOnly == .app(nil) && fake.commands.count == 1)
        fake.running.remove(AppleTerminalHost.id)
        let closed = await service.openTerminal(store.session(id: terminalID)!)
        precondition(closed == .unavailable)
        print("PASS: panes from cmux, Terminal and Ghostty, typing while working, refusals (agent gone, approval, not running, not allowed), moved sessions, focus")
    }

    /// Leftover cleanup keeps what saved items still use, whichever spelling of
    /// the temporary folder their path has, and removes everything else. It runs
    /// on a folder of its own, never on Atoll's.
    static func verifyTemporaryFileCleanup() throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("atoll-cleanup-\(UUID())", isDirectory: true)
        defer { try? fm.removeItem(at: folder) }
        func make(_ relative: String) throws -> URL {
            let url = folder.appendingPathComponent(relative)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
            return url
        }
        let kept = try make("A1B2/dropped image.png")
        let orphan = try make("C3D4/old note.txt")
        let zipWork = try make("zip_E5F6/part.txt")
        let loose = try make("loose.png")
        // A saved item's path may name the temporary folder through /private or not.
        let otherSpelling = kept.path.hasPrefix("/private/") ? String(kept.path.dropFirst("/private".count)) : "/private" + kept.path
        let keptAsBookmarkResolves = URL(fileURLWithPath: otherSpelling)
        precondition(fm.fileExists(atPath: otherSpelling), "both spellings name the same file")

        AtollTemporaryFiles.removeEntries(of: folder, notIn: [keptAsBookmarkResolves, loose])
        precondition(fm.fileExists(atPath: kept.path) && fm.fileExists(atPath: loose.path))
        precondition(!fm.fileExists(atPath: orphan.deletingLastPathComponent().path))
        precondition(!fm.fileExists(atPath: zipWork.deletingLastPathComponent().path))

        AtollTemporaryFiles.removeEntries(of: folder, notIn: [])
        let remaining = try fm.contentsOfDirectory(atPath: folder.path)
        precondition(remaining.isEmpty)
        print("PASS: leftover cleanup keeps files saved items use (either temp-folder spelling) and removes the rest")
    }

    static func verifyWebSocket() throws {
        var parser = CodexWebSocketFraming()
        let handshake = String(decoding: parser.handshake, as: UTF8.self)
        let key = handshake.components(separatedBy: "\r\n").first { $0.hasPrefix("Sec-WebSocket-Key:") }!
            .split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)
        let accept = Data(Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))).base64EncodedString()
        let header = Data("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n".utf8)
        var ready = false
        for byte in header {
            for event in try parser.receive(Data([byte])) { if case .ready = event { ready = true } }
        }
        precondition(ready)
        let events = try parser.receive(Data([0x01, 2, 65, 66, 0x89, 1, 88, 0x80, 2, 67, 68]))
        precondition(events.contains { if case .text(let data) = $0 { return data == Data("ABCD".utf8) }; return false })
        precondition(events.contains { if case .ping(let data) = $0 { return data == Data("X".utf8) }; return false })
        for count in [0, 125, 126, 65_536] {
            let payload = Data(repeating: 65, count: count)
            let frame = try CodexWebSocketFraming.frame(payload)
            let offset = count < 126 ? 2 : (count <= 65_535 ? 4 : 10)
            precondition(frame[1] & 0x80 != 0)
            let mask = Array(frame[offset..<(offset + 4)])
            let decoded = Data(frame.dropFirst(offset + 4).enumerated().map { $0.element ^ mask[$0.offset % 4] })
            precondition(decoded == payload)
        }
        do { _ = try parser.receive(Data([0x82, 0])); preconditionFailure("binary frame must be rejected") }
        catch AgentConnectionError.unavailable { }
        print("PASS: fragmented WebSocket upgrade, continuation frames, ping, masking and extended lengths")
    }

    @MainActor
    static func verifyProcessTransport(_ fixture: String) async throws {
        let rpc = CodexRPCClient(preferSharedDaemon: false)
        try await rpc.start(executable: fixture)
        let result = try await rpc.request("echo", ["text": "中文\nquotes: \" and $()"])
        precondition(result["text"] as? String == "中文\nquotes: \" and $()")
        do { _ = try await rpc.request("fail", [:]); preconditionFailure("expected rejection") }
        catch AgentConnectionError.rejected { }
        do { _ = try await rpc.request("silent", [:], timeout: 0.05); preconditionFailure("expected timeout") }
        catch AgentConnectionError.unavailable { }
        rpc.close()
        print("PASS: real JSONL process transport, Unicode, fragmented frames, rejection and bounded timeout")
    }
}
