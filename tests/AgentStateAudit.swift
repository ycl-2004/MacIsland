import Foundation

/// Acceptance replay against the real reducers and regression fake clients.
/// A policy mismatch records evidence and fails the executable.
/// Compile with AgentConversationRegression.swift's @main removed in a temporary
/// copy. No installed agent, real transcript or production preference is used.
@main
struct AgentStateAudit {
    struct Observation: Codable {
        let id: String
        let policy: String
        let met: Bool
        let observed: String
    }

    @MainActor
    static func main() async throws {
        setbuf(stdout, nil)
        defer { AgentConversationRegression.discardDefaults() }
        var results: [Observation] = []
        func check(_ id: String, _ policy: String, _ met: Bool, _ observed: String) {
            results.append(Observation(id: id, policy: policy, met: met, observed: observed))
            print("\(met ? "MET" : "GAP"): \(id) — \(observed)")
        }
        let claude = ClaudeCodeAgentSource(), codex = CodexAgentSource(), grok = GrokAgentSource()
        for source in [claude as AgentSource, codex, grok] {
            let phase = source.phase(forEvent: "PreToolUse", payload: ["tool_name": "Bash"])
            check("\(source.id)-plain-tool", "A normal tool call is work, not a request for user action", phase == .toolStarted, "\(String(describing: phase))")
        }
        for type in ["idle_prompt", "auth_success", "agent_completed", "elicitation_complete", "unknown_future_type"] {
            let phase = claude.phase(forEvent: "Notification", payload: ["notification_type": type])
            check("claude-notification-\(type)", "Informational or unrecognised notifications must not become urgent user requests", phase != .needsAttention, "\(String(describing: phase))")
        }
        let permission = claude.phase(forEvent: "Notification", payload: ["notification_type": "permission_prompt"])
        check("claude-permission", "An explicit permission prompt needs user action", permission == .needsAttention, "\(String(describing: permission))")
        let failure = claude.phase(forEvent: "PostToolUseFailure", payload: ["tool_name": "Bash", "error": "Exit code 1", "is_interrupt": false])
        check("claude-tool-failure", "A finished failing tool must stop being presented as currently running", failure != nil, "\(String(describing: failure))")
        let stopFailure = claude.phase(forEvent: "StopFailure", payload: ["error": "rate_limit"])
        check("claude-turn-failure", "An explicit API failure must settle the working state", stopFailure == .turnFailed, "\(String(describing: stopFailure))")
        let post = codex.phase(forEvent: "PostToolUse", payload: ["tool_name": "Bash"])
        check("codex-tool-return", "Hook-only sessions need a state update when a tool finishes", post != nil, "\(String(describing: post))")
        let unknown = grok.phase(forEvent: "Notification", payload: ["notificationType": "unknown_future_type"])
        check("grok-unknown-notification", "Unknown notification types should not manufacture a user request", unknown != .needsAttention, "\(String(describing: unknown))")
        let cancelled = grok.phase(forEvent: "StopCancelled", payload: [:])
        check("grok-cancel", "Cancellation must not produce a successful completion flash", cancelled != .turnFinished, "\(String(describing: cancelled))")

        let baseTime = Date()
        let base = AgentSession.starting(with: AgentConversationRegression.hook(.promptSubmitted, at: baseTime))
        let waiting = base.applying(AgentConversationRegression.hook(.needsAttention, at: baseTime.addingTimeInterval(1)))
        let resumed = waiting.applying(AgentConversationRegression.hook(.thinking, at: baseTime.addingTimeInterval(2)))
        check("resume-clears-wait", "An explicit resumption clears an old wait", !resumed.isWaitingOnUser && resumed.state.isWorking, "\(resumed.state)")
        let ended = waiting.applying(AgentConversationRegression.hook(.sessionEnded, at: baseTime.addingTimeInterval(2)))
        check("end-clears-wait", "Ending a session removes urgent attention", !ended.isWaitingOnUser && ended.isDisconnected, "\(ended.state), disconnected=\(ended.isDisconnected)")
        let delayed = resumed.applying(AgentConversationRegression.hook(.needsAttention, at: baseTime))
        check("late-hook", "An older event must not replace a newer lifecycle state", !delayed.isWaitingOnUser, "\(delayed.state)")
        let done = base.applying(AgentConversationRegression.hook(.turnFinished, at: baseTime.addingTimeInterval(3)))
        let duplicate = done.applying(AgentConversationRegression.hook(.turnFinished, at: baseTime.addingTimeInterval(5)))
        check("duplicate-finish", "A duplicate completion must not restart the completion flash", duplicate.finishedAt == done.finishedAt, "finishedAt moved=\(duplicate.finishedAt != done.finishedAt)")
        let store = AgentSessionStore(persistenceURL: nil)
        store.upsert(waiting)
        store.setLiveFeed(waiting.id, true)
        store.dropLiveFeeds()
        check("lost-live-feed", "A lost authoritative feed must expose uncertainty rather than a confirmed live wait", store.session(id: waiting.id)?.isWaitingOnUser != true, "waiting=\(store.session(id: waiting.id)?.isWaitingOnUser == true)")
        let highlights = AgentSessionStore(persistenceURL: nil)
        highlights.upsert(done)
        check("finish-expiry", "Completion highlights expire after six seconds", highlights.closedNotchHighlight(now: baseTime.addingTimeInterval(10)) == nil, "highlight expired=\(highlights.closedNotchHighlight(now: baseTime.addingTimeInterval(10)) == nil)")
        highlights.upsert(waiting)
        highlights.apply(AgentConversationRegression.hook(.promptSubmitted, key: "other", at: baseTime.addingTimeInterval(4)))
        check("wait-priority", "A confirmed wait is shown ahead of ordinary work", highlights.closedNotchHighlight(now: baseTime.addingTimeInterval(5))?.id == waiting.id, "\(highlights.closedNotchHighlight(now: baseTime.addingTimeInterval(4))?.id ?? "none")")
        var updates = 0
        let watcher = highlights.objectWillChange.sink { updates += 1 }
        highlights.remove([waiting])
        watcher.cancel()
        check("single-removal-publication", "Removing cards should publish one collection update", updates == 1, "updates=\(updates)")

        let client = FakeCodexClient()
        let thread = AgentConversationRegression.threadID
        let id = AgentConversationRegression.sessionID
        client.threads = [thread: AgentConversationRegression.terminalThread()]
        client.loaded = [thread]
        let liveStore = AgentSessionStore(persistenceURL: nil)
        let (service, _) = AgentConversationRegression.makeService(client, store: liveStore)
        service.start()
        defer { service.stop() }
        try await AgentConversationRegression.waitUntil { liveStore.hasLiveFeed(id) }
        func event(_ name: String, _ extra: [String: Any]) {
            client.onEvent?(name, ["threadId": thread].merging(extra) { _, rhs in rhs })
        }
        event("turn/started", ["turn": ["id": "current"]])
        event("thread/status/changed", ["status": ["type": "active", "activeFlags": ["waitingOnApproval"]]])
        event("item/completed", ["turnId": "current", "item": ["id": "other-tool", "type": "commandExecution", "command": "true"]])
        check("parallel-tool-vs-wait", "Finishing another tool must not erase an explicit pending approval", liveStore.session(id: id)?.isWaitingOnUser == true, "\(liveStore.session(id: id)!.state)")
        event("turn/started", ["turn": ["id": "newer"]])
        event("turn/completed", ["turn": ["id": "current", "status": "completed"]])
        check("old-turn-completion", "A previous turn's completion must not finish the newer turn", liveStore.session(id: id)?.state.isWorking == true, "\(liveStore.session(id: id)!.state)")
        event("turn/started", ["turn": ["id": "interrupted"]])
        event("turn/completed", ["turn": ["id": "interrupted", "status": "interrupted"]])
        check("cancel-highlight", "An interrupted turn must not interrupt music with a completion highlight", liveStore.closedNotchHighlight() == nil, "highlight=\(liveStore.closedNotchHighlight() != nil)")
        event("turn/started", ["turn": ["id": "failed"]])
        event("turn/completed", ["turn": ["id": "failed", "status": "failed", "error": ["message": "fixture error"]]])
        check("live-turn-failure", "Explicit failure has an error state", liveStore.session(id: id)?.state == .failed(message: "fixture error"), "\(liveStore.session(id: id)!.state)")

        // An approval Atoll owns is tested via the fake client, never by answering
        // a real terminal's approval prompt.
        event("turn/completed", ["turn": ["id": "failed", "status": "completed"]])
        service.setDraft("fixture prompt", for: id)
        service.send(id: id)
        try await AgentConversationRegression.waitUntil { !service.sending.contains(id) }
        for request in [1, 2] {
            client.onRequest?(request, "item/commandExecution/requestApproval", ["threadId": thread, "turnId": "turn-one", "command": "true"])
        }
        check("owned-approval-visible", "Requests for an Atoll-owned turn are visible", service.approvals.count == 2 && liveStore.session(id: id)?.isWaitingOnUser == true, "requests=\(service.approvals.count)")
        if let first = service.approvals.first { service.answerApproval(first, allow: false) }
        check("multiple-approvals", "Answering one request must retain the wait for another", service.approvals.count == 1 && liveStore.session(id: id)?.isWaitingOnUser == true, "requests=\(service.approvals.count), state=\(liveStore.session(id: id)!.state)")

        check("approval-send-guard", "Outstanding approvals keep ordinary input blocked", !service.canSend(liveStore.session(id: id)!), "canSend=\(service.canSend(liveStore.session(id: id)!))")
        event("serverRequest/resolved", ["requestId": 2])
        check("approval-resolution", "The matching server request resolves without clearing other IDs", service.approvals.isEmpty && !liveStore.session(id: id)!.hasPendingRequests, "requests=\(service.approvals.count)")
        event("turn/completed", ["turn": ["id": "turn-one", "status": "completed"]])
        let firstFinish = liveStore.session(id: id)!.finishedAt
        event("turn/completed", ["turn": ["id": "turn-one", "status": "completed"]])
        check("live-finish-dedup", "A repeated completion retains the original flash deadline", liveStore.session(id: id)!.finishedAt == firstFinish, "deadline unchanged")
        event("item/completed", ["turnId": "turn-one", "item": ["id": "late-item", "type": "commandExecution", "command": "true"]])
        check("settled-turn-late-item", "Late items cannot reopen a settled turn", liveStore.session(id: id)!.state == .finished, "\(liveStore.session(id: id)!.state)")
        client.onRequest?(9, "item/commandExecution/requestApproval", ["threadId": thread, "turnId": "turn-one"])
        check("settled-turn-late-request", "Late approval requests cannot reopen a settled turn", liveStore.session(id: id)!.state == .finished && !liveStore.session(id: id)!.hasPendingRequests && service.approvals.isEmpty, "settled turn remains finished")
        event("turn/started", ["turn": ["id": "external"]])
        for _ in 0..<2 { client.onRequest?(3, "item/commandExecution/requestApproval", ["threadId": thread, "turnId": "external", "command": "true"]) }
        check("foreign-approval-observation", "Foreign requests are tracked once without becoming answerable", service.approvals.isEmpty && liveStore.session(id: id)!.pendingRequests?.count == 1, "answerable=\(service.approvals.count)")
        let beforeHook = liveStore.session(id: id)!.state
        liveStore.apply(AgentConversationRegression.hook(.thinking))
        check("owner-feed-precedence", "A hook cannot erase an owner feed's pending approval", liveStore.session(id: id)!.state == beforeHook && !service.canSend(liveStore.session(id: id)!), "pending wait retained")
        liveStore.dropLiveFeeds()
        check("uncertain-input-guard", "Lost feed blocks terminal fallback without claiming the session ended", !service.canSend(liveStore.session(id: id)!) && !liveStore.session(id: id)!.isDisconnected, "input blocked, terminal not declared ended")

        let source = OpenCodeAgentSource()
        func oc(_ name: String, _ payload: [String: Any], _ offset: Double) -> AgentHookEvent {
            source.makeEvent(eventName: name, payload: ["session_id": "oc"].merging(payload) { _, rhs in rhs }, hostBundleID: nil, now: baseTime.addingTimeInterval(offset))!
        }
        var concurrent = AgentSession.starting(with: oc("chat.message", ["turn_id": "a"], 0))
        concurrent = concurrent.applying(oc("permission.asked", ["turn_id": "a", "request_id": "p1"], 1))
        concurrent = concurrent.applying(oc("question.asked", ["turn_id": "a", "request_id": "q2"], 2))
        concurrent = concurrent.applying(oc("tool.completed", ["turn_id": "a", "tool_use_id": "unrelated"], 3))
        check("hook-parallel-requests", "An unrelated tool does not resolve identified hook requests", concurrent.pendingRequests?.count == 2 && concurrent.isWaitingOnUser, "requests=\(concurrent.pendingRequests?.count ?? 0)")
        concurrent = concurrent.applying(oc("permission.replied", ["turn_id": "a", "request_id": "p1"], 4))
        check("hook-matching-resolution", "A reply resolves only its own permission ID", concurrent.pendingRequests?.count == 1 && concurrent.isWaitingOnUser, "one question remains")
        concurrent = concurrent.applying(oc("question.replied", ["turn_id": "a", "request_id": "q2"], 5))
        check("hook-all-resolved", "After the last identified reply normal work resumes", !concurrent.blocksInput && concurrent.state.isWorking, "\(concurrent.state)")
        concurrent = concurrent.applying(oc("chat.message", ["turn_id": "b"], 6))
        concurrent = concurrent.applying(oc("session.idle", ["turn_id": "a"], 7))
        check("hook-old-turn-id", "IDs reject an older turn even if it arrives later", concurrent.currentTurnID == "b" && concurrent.state.isWorking, "current turn=\(concurrent.currentTurnID ?? "none")")
        concurrent = concurrent.applying(oc("session.cancelled", ["turn_id": "b"], 8))
        concurrent = concurrent.applying(oc("session.idle", ["turn_id": "b"], 9))
        check("hook-cancel-then-idle", "Idle after cancellation is not a success", concurrent.state == .idle && concurrent.finishedAt == nil && concurrent.wasCancelled == true, "cancelled without success flash")
        concurrent = concurrent.applying(oc("atoll.transport.uncertain", [:], 10))
        check("hook-overflow-uncertainty", "Transport overflow exposes uncertainty and keeps input guarded", concurrent.statusUncertain == true && concurrent.blocksInput, "uncertain=\(concurrent.statusUncertain == true)")
        let legacy = ClaudeCodeAgentSource(), extended = ClaudeCodeAgentSource(extendedLifecycle: true)
        check("legacy-hook-profile", "Legacy settings omit new hooks; extended profile adds them explicitly", legacy.hookEvents["StopFailure"] == nil && extended.hookEvents["StopFailure"] == .turnFailed, "profiles are separate")
        let guarded = AgentSession.starting(with: AgentConversationRegression.hook(.needsAttention, at: baseTime))
        let settlingStore = AgentSessionStore(persistenceURL: nil)
        settlingStore.upsert(guarded)
        check("attention-settling-window", "Input remains guarded while a transient reminder waits 250 ms", guarded.blocksInput && settlingStore.closedNotchHighlight(now: baseTime.addingTimeInterval(0.1)) == nil && settlingStore.closedNotchHighlight(now: baseTime.addingTimeInterval(1))?.id == guarded.id, "immediate guard, delayed reminder")

        // Status timestamps from a new server protect flags that have no turn ID.
        event("turn/started", ["turn": ["id": "emission-current"]])
        event("thread/status/changed", ["_atollEmittedAtMs": 200.0, "status": ["type": "active", "activeFlags": []]])
        event("thread/status/changed", ["_atollEmittedAtMs": 100.0, "status": ["type": "active", "activeFlags": ["waitingOnApproval"]]])
        check("owner-emission-order", "An identifiable old status cannot overwrite newer flags", !liveStore.session(id: id)!.state.needsAttention, "older status rejected")
        let resumeClient = FakeCodexClient()
        resumeClient.threads = [thread: AgentConversationRegression.terminalThread()]
        resumeClient.loaded = [thread]
        resumeClient.onResume = { resumeClient.onRequest?(17, "item/commandExecution/requestApproval", ["threadId": thread, "command": "true"]) }
        let resumeStore = AgentSessionStore(persistenceURL: nil)
        let (resumeService, _) = AgentConversationRegression.makeService(resumeClient, store: resumeStore)
        resumeService.start()
        try await AgentConversationRegression.waitUntil { resumeStore.hasLiveFeed(id) }
        check("subscribe-approval-race", "A request emitted before resume response is not lost", resumeStore.session(id: id)!.isWaitingOnUser && !resumeService.canSend(resumeStore.session(id: id)!) && resumeService.approvals.isEmpty, "foreign approval retained during subscription")
        resumeService.stop()

        let ownershipClient = FakeCodexClient()
        ownershipClient.threads = [thread: AgentConversationRegression.terminalThread()]
        ownershipClient.loaded = [thread]
        let ownershipStore = AgentSessionStore(persistenceURL: nil)
        let (ownershipService, _) = AgentConversationRegression.makeService(ownershipClient, store: ownershipStore)
        ownershipService.start()
        try await AgentConversationRegression.waitUntil { ownershipStore.hasLiveFeed(id) }
        ownershipService.setDraft("owned fixture", for: id)
        ownershipService.send(id: id)
        try await AgentConversationRegression.waitUntil { !ownershipService.sending.contains(id) }
        ownershipClient.onRequest?(1, "item/commandExecution/requestApproval", ["threadId": thread, "turnId": "turn-one"])
        let oldApproval = ownershipService.approvals.first!
        ownershipClient.onEvent?("turn/started", ["threadId": thread, "turn": ["id": "external-next"]])
        ownershipClient.onRequest?(2, "item/commandExecution/requestApproval", ["threadId": thread, "turnId": "external-next"])
        check("ownership-is-turn-specific", "A new terminal turn does not inherit Atoll's previous approval authority", ownershipService.approvals.isEmpty && ownershipStore.session(id: id)!.hasPendingRequests, "foreign next turn remains read-only")
        ownershipClient.close()
        await ownershipService.refresh()
        ownershipClient.nextTurnID = "new-connection-turn"
        ownershipService.setDraft("new connection fixture", for: id)
        ownershipService.send(id: id)
        try await AgentConversationRegression.waitUntil { !ownershipService.sending.contains(id) }
        ownershipClient.onRequest?(1, "item/commandExecution/requestApproval", ["threadId": thread, "turnId": "new-connection-turn"])
        let repliesBefore = ownershipClient.replies.count
        ownershipService.answerApproval(oldApproval, allow: false)
        check("approval-generation-guard", "An old approval UI cannot answer a reused RPC ID on a new connection", ownershipService.approvals.count == 1 && ownershipClient.replies.count == repliesBefore, "current requests=\(ownershipService.approvals.count), stale replies=\(ownershipClient.replies.count - repliesBefore)")
        ownershipService.stop()

        let hookStore = AgentSessionStore(persistenceURL: nil)
        let (hookService, _) = AgentConversationRegression.makeService(FakeCodexClient(), store: hookStore)
        hookService.start()
        let hookID = AgentSession.key(sourceID: "claude", sessionKey: thread)
        let oldPrompt = AgentConversationRegression.hook(.promptSubmitted, source: "claude", at: baseTime)
        _ = hookService.receive(oldPrompt)
        let currentStop = AgentConversationRegression.hook(.turnFinished, source: "claude", at: baseTime.addingTimeInterval(1))
        _ = hookService.receive(currentStop)
        var parkedReleases = 0
        hookService.park(currentStop, reply: { _ in parkedReleases += 1 }, onClose: { _ in })
        _ = hookService.receive(oldPrompt)
        check("stale-hook-delivery-guard", "An old prompt cannot release the current parked reply route", parkedReleases == 0 && hookService.canSend(hookStore.session(id: hookID)!), "current route retained")
        var staleParkRejected = false
        hookService.park(oldPrompt, reply: { _ in staleParkRejected = true }, onClose: { _ in })
        check("stale-park-guard", "An old parked hook cannot replace a newer route", staleParkRejected && parkedReleases == 0, "old hook released, current route retained")
        hookService.stop()

        var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as! [String: Any]
        for key in ["attentionSince", "currentTurnID", "retiredTurnIDs", "pendingRequests", "activityState", "statusUncertain", "wasCancelled"] { legacyJSON[key] = nil }
        let restoredLegacy = try JSONDecoder().decode(AgentSession.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
        check("legacy-session-decode", "Existing snapshots load without new optional state fields", restoredLegacy.id == base.id && restoredLegacy.currentTurnID == nil && restoredLegacy.pendingRequests == nil, "legacy snapshot retained")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let path = CommandLine.arguments.dropFirst().first {
            try encoder.encode(results).write(to: URL(fileURLWithPath: path), options: .atomic)
        }
        print("Policy met: \(results.filter(\.met).count)/\(results.count); gaps: \(results.filter { !$0.met }.count)")
        guard results.allSatisfy(\.met) else { throw NSError(domain: "AgentStateAcceptance", code: 1) }
    }
}
