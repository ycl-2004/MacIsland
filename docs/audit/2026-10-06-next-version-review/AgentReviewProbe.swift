import Foundation

@main struct AgentReviewProbe {
    @MainActor static func main() async throws {
        defer { AgentConversationRegression.discardDefaults() }
        let ordinary = try await probe(longIDs: false)
        let collision = try await probe(longIDs: true)
        let result: [String: Any] = ["kind": "isolated_defect_reproduction", "realAgentAccess": false,
                                    "ordinaryApproval": ordinary, "longStringIDs": collision]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    }

    @MainActor static func probe(longIDs: Bool) async throws -> [String: Any] {
        let thread = AgentConversationRegression.threadID
        let id = AgentConversationRegression.sessionID
        let client = FakeCodexClient()
        client.threads = [thread: AgentConversationRegression.terminalThread()]
        client.loaded = [thread]
        let store = AgentSessionStore(persistenceURL: nil)
        let (service, _) = AgentConversationRegression.makeService(client, store: store)
        service.start()
        defer { service.stop() }
        try await AgentConversationRegression.waitUntil { store.hasLiveFeed(id) && service.isLive }
        service.setDraft("Review fixture", for: id)
        service.send(id: id)
        try await AgentConversationRegression.waitUntil { !service.sending.contains(id) && !client.starts.isEmpty }
        let params: [String: Any] = ["threadId": thread, "turnId": "turn-one", "command": "fixture command"]
        if !longIDs {
            client.onRequest?(1, "item/commandExecution/requestApproval", params)
            client.onEvent?("thread/status/changed", ["threadId": thread, "status": ["type": "active", "activeFlags": ["waitingOnApproval"]]])
            let session = store.session(id: id)!
            precondition(service.approvals.count == 1 && session.pendingRequests?.count == 2)
            return ["requestCountSent": 1, "actionableApprovals": service.approvals.count,
                    "cardPendingCount": session.pendingRequests?.count ?? 0,
                    "keys": (session.pendingRequests ?? [:]).keys.sorted(),
                    "ordinaryInputBlocked": !service.canSend(session)]
        }
        let prefix = String(repeating: "x", count: 240)
        client.onRequest?(prefix + "A", "item/commandExecution/requestApproval", params)
        client.onRequest?(prefix + "B", "item/commandExecution/requestApproval", params)
        let countBefore = service.approvals.count
        let pendingBefore = store.session(id: id)!.pendingRequests?.count ?? 0
        precondition(countBefore == 1 && pendingBefore == 1)
        service.answerApproval(service.approvals[0], allow: false)
        let session = store.session(id: id)!
        precondition(client.replies.count == 1 && !session.hasPendingRequests && service.canSend(session))
        return ["requestCountSent": 2, "idLength": 241, "samePrefixLength": 240,
                "actionableApprovalsBeforeReply": countBefore, "pendingBeforeReply": pendingBefore,
                "repliesSent": client.replies.count, "pendingAfterFirstReply": session.pendingRequests?.count ?? 0,
                "ordinaryInputAllowedAfterFirstReply": service.canSend(session),
                "scope": "protocol edge case; installed client occurrence not measured"]
    }
}
