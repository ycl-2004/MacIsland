import Foundation
import CryptoKit
import Combine

/// The way a message typed in Atoll reaches a session right now.
enum AgentSendRoute: Equatable {
    /// Codex's shared service takes it into the thread.
    case sharedService
    /// Typed into the session's pane in this terminal app, as the user would.
    case terminal(String)
    /// A parked hook wakes the idle agent with it.
    case wakeWhenIdle
    /// The working agent's next step picks it up.
    case injectWhileWorking
}

struct AgentApproval: Identifiable {
    let id: String
    let requestID: Any
    let sessionID: String
    let title: String
    let detail: String
}

/// Keeps terminal conversations current and carries messages back to them.
///
/// A Codex terminal attached to Codex's shared service (the app-server daemon)
/// is followed live: Atoll subscribes to every thread the service has loaded
/// and receives the same item stream the terminal renders, and a message typed
/// here starts, or joins, a turn in that same thread. The service is the
/// thread's only writer, so Atoll never competes with the terminal. Other
/// sessions (Claude Code, Antigravity, Codex started without the service) are
/// followed by rereading their saved conversation whenever its file changes,
/// and a message reaches them by being typed into their terminal pane when
/// Atoll knows it (`AgentTerminals`), or else through their hooks.
@MainActor
final class AgentConversationService: ObservableObject {
    static let shared = AgentConversationService()
    private static let pollInterval: Duration = .seconds(3)
    /// An open conversation rereads its file this often, so it tracks the terminal.
    private static let openPollInterval: Duration = .seconds(1)
    /// Turns of saved history loaded when a conversation opens.
    private static let historyTurns = 3
    private static let receiptKey = "atoll.agent.unconfirmedDeliveries"

    @Published private(set) var connectionMessage: String?
    /// Connected to Codex's shared service, so live terminals can be reached.
    @Published private(set) var isLive = false
    @Published private(set) var sending: Set<String> = []
    @Published private(set) var errors: [String: String] = [:]
    /// What happened to the last message typed into a terminal, until the agent takes it.
    @Published private(set) var notices: [String: String] = [:]
    /// Text the agent is writing right now, before its message completes.
    @Published private(set) var streaming: [String: String] = [:]
    @Published private(set) var approvals: [AgentApproval] = []
    @Published private(set) var uncertainIDs: Set<String>
    @Published var drafts: [String: String] = [:]
    @Published var requestedSessionID: String?
    @Published var selectedID: String? { didSet { store.viewedSessionID = selectedID } }

    private let client: CodexConversationClient
    private let executablePath: () -> String?
    private let store: AgentSessionStore
    private let terminals: AgentTerminals
    private let defaults: UserDefaults
    var refreshIntervalProvider: (() -> Duration)?
    private var polling: Task<Void, Never>?
    private var refreshing = false
    private var enabled = false
    /// Changes whenever the connection does, so late replies from an old one are dropped.
    private var connectionEpoch = UUID()
    /// Codex threads Atoll is subscribed to.
    private var subscribed = Set<String>()
    /// Loaded threads that are not a terminal's own session (helpers, subagents).
    private var ignoredThreads = Set<String>()
    private var activeTurns: [String: String] = [:]
    private var ownerEmissionTimes: [String: Double] = [:]
    /// Threads whose current turn Atoll started; only those approvals are Atoll's to answer.
    private var ownedTurns: [String: String] = [:]
    /// Messages sent from Atoll that Codex has not yet echoed back as items.
    private var awaitingEcho = Set<String>()
    /// Modification date of each session's conversation file when last read.
    private var transcriptStamps: [String: Date] = [:]
    private var loadingHistory = Set<String>()
    private var sendingTasks: [String: Task<Void, Never>] = [:]
    private var storeSubscription: AnyCancellable?

    init(store: AgentSessionStore? = nil, defaults: UserDefaults = .standard,
         client: CodexConversationClient? = nil, terminals: AgentTerminals? = nil,
         executablePath: @escaping () -> String? = { AgentExecutableLocator.path(for: "codex") }) {
        self.store = store ?? .shared
        self.terminals = terminals ?? .shared
        self.defaults = defaults
        self.client = client ?? CodexRPCClient()
        self.executablePath = executablePath
        uncertainIDs = Set(defaults.stringArray(forKey: Self.receiptKey) ?? [])
        self.client.onEvent = { [weak self] in self?.handleEvent($0, $1) }
        self.client.onRequest = { [weak self] in self?.handleRequest($0, $1, $2) }
        self.client.onDisconnect = { [weak self] in self?.connectionLost() }
        storeSubscription = self.store.$sessions.sink { [weak self] sessions in
            self?.pruneSidecarState(retaining: Set(sessions.map(\.id)))
        }
    }

    func setDraft(_ text: String, for id: String) {
        let others = drafts.filter { $0.key != id }
        guard text.utf8.count <= 64 * 1024, others.count < 64,
              others.values.reduce(0, { $0 + $1.utf8.count }) + text.utf8.count <= 1024 * 1024 else {
            errors[id] = "Draft storage is full. Keep each draft under 64 KB and clear old drafts before adding more."
            return
        }
        drafts[id] = text
    }

    private func pruneSidecarState(retaining ids: Set<String>) {
        let retained = ids.union(selectedID.map { [$0] } ?? [])
        errors = errors.filter { retained.contains($0.key) }
        notices = notices.filter { retained.contains($0.key) }
        streaming = streaming.filter { retained.contains($0.key) }
        transcriptStamps = transcriptStamps.filter { retained.contains($0.key) }
        loadingHistory.formIntersection(retained)
        for (id, task) in sendingTasks where !retained.contains(id) { task.cancel(); sendingTasks[id] = nil }
        sending.formIntersection(retained)
        // Unsent drafts stay available; their editor enforces a separate budget.
    }

    // MARK: Lifecycle

    func start() {
        guard polling == nil else { return }
        enabled = true
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: self?.refreshIntervalProvider?() ?? (self?.selectedID == nil ? Self.pollInterval : Self.openPollInterval))
            }
        }
    }

    func stop() {
        enabled = false
        polling?.cancel(); polling = nil
        for task in sendingTasks.values { task.cancel() }
        sendingTasks.removeAll()
        sending.removeAll()
        for id in Array(parkedHooks.keys) { releaseParkedHook(id) }
        queuedReplies.removeAll()
        handedOff.removeAll()
        client.close()
        resetConnectionState()
    }

    func refresh() async {
        guard enabled, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        await syncCodex()
        if let selectedID { await loadHistory(id: selectedID) }
    }

    func select(_ id: String) {
        selectedID = id
        Task { await loadHistory(id: id, force: true) }
    }

    private func connectionLost() {
        let wasLive = isLive
        resetConnectionState()
        if wasLive { connectionMessage = String(localized: "Lost the connection to Codex. Reconnecting…") }
    }

    private func resetConnectionState() {
        connectionEpoch = UUID()
        isLive = false
        store.dropLiveFeeds()
        subscribed.removeAll()
        ignoredThreads.removeAll()
        activeTurns.removeAll()
        ownerEmissionTimes.removeAll()
        ownedTurns.removeAll()
        approvals.removeAll()
        streaming.removeAll()
    }

    // MARK: Codex service

    /// Attaches to the shared service when it runs, or keeps a private reader
    /// for saved history while a Codex conversation is open.
    private func syncCodex() async {
        let codexOpen = selectedID.flatMap { store.session(id: $0) }?.sourceID == "codex"
        guard client.sharedServiceAvailable || codexOpen || client.isReady else { return }
        do {
            guard let executable = executablePath() else {
                throw AgentConnectionError.unavailable(String(localized: "Install Codex to follow its terminal sessions."))
            }
            try await client.start(executable: executable)
            guard enabled else { return }
            if client.isSharedDaemon { try await syncLoadedThreads(epoch: connectionEpoch) }
            isLive = client.isSharedDaemon
            connectionMessage = nil
        } catch {
            isLive = false
            connectionMessage = error.localizedDescription
        }
    }

    /// Every thread the service has loaded belongs to an open terminal (or one
    /// that just closed). Subscribing is how a second client follows it; a
    /// stored thread the service has not loaded is never resumed from here.
    private func syncLoadedThreads(epoch: UUID) async throws {
        let loaded = Set(try await client.request("thread/loaded/list", [:])["data"] as? [String] ?? [])
        guard enabled, epoch == connectionEpoch else { return }
        for threadID in subscribed.subtracting(loaded) { endLiveFeed(threadID) }
        let cutoff = Date().addingTimeInterval(-AgentSessionStore.staleSessionInterval)
        for threadID in loaded.subtracting(subscribed).subtracting(ignoredThreads) {
            let id = Self.sessionID(threadID)
            guard !store.isHidden(id),
                  let thread = try? await client.request("thread/read", ["threadId": threadID, "includeTurns": false])["thread"] as? [String: Any],
                  enabled, epoch == connectionEpoch,
                  var session = CodexSessionProjection.session(thread, existing: reconciledSnapshotBase(store.session(id: id)), live: true) else { continue }
            guard CodexSessionProjection.isFollowable(thread), session.isTerminalSession else { ignoredThreads.insert(threadID); continue }
            guard (session.lastSeenAt ?? session.updatedAt) > cutoff else { continue }
            // Register before awaiting resume: the service can emit an approval
            // before its response. Keep input guarded until following succeeds.
            let wasExisting = store.session(id: id) != nil
            let acceptsInput = session.canAcceptDirectInput
            session.canAcceptDirectInput = false
            session.statusUncertain = true
            subscribed.insert(threadID)
            store.upsert(session)
            guard (try? await client.request("thread/resume", ["threadId": threadID, "excludeTurns": true])) != nil,
                  enabled, epoch == connectionEpoch, subscribed.contains(threadID) else {
                if epoch == connectionEpoch { endLiveFeed(threadID) }
                if !wasExisting { store.discardUnconfirmed(session) }
                continue
            }
            store.setLiveFeed(id, true)
            if var current = store.session(id: id) {
                current.canAcceptDirectInput = acceptsInput
                current.isDisconnected = false
                current.statusUncertain = false
                store.upsert(current)
            }
            if selectedID == id { await loadHistory(id: id, force: true) }
        }
        // A quiet session leaves the notch; stop holding its thread open.
        for threadID in subscribed {
            guard let session = store.session(id: Self.sessionID(threadID)) else { endLiveFeed(threadID); continue }
            if !session.state.isWorking, !session.state.needsAttention, (session.lastSeenAt ?? session.updatedAt) <= cutoff {
                endLiveFeed(threadID)
            }
        }
    }

    private func reconciledSnapshotBase(_ existing: AgentSession?) -> AgentSession? {
        guard var existing else { return nil }
        if existing.statusUncertain == true {
            existing.pendingRequests = nil
            existing.attentionSince = nil
        }
        return existing
    }

    private func endLiveFeed(_ threadID: String) {
        guard subscribed.remove(threadID) != nil else { return }
        let id = Self.sessionID(threadID)
        store.setLiveFeed(id, false)
        activeTurns[threadID] = nil
        ownedTurns[threadID] = nil
        ownerEmissionTimes[threadID] = nil
        streaming[id] = nil
        if var session = store.session(id: id) {
            session.canAcceptDirectInput = false
            if !session.isDisconnected { session.statusUncertain = true; session.finishedAt = nil }
            store.upsert(session)
        }
        Task { _ = try? await client.request("thread/unsubscribe", ["threadId": threadID]) }
    }

    private static func sessionID(_ threadID: String) -> String {
        AgentSession.key(sourceID: "codex", sessionKey: threadID)
    }

    // MARK: History

    /// Rereads a session's saved conversation. Without a live feed that happens
    /// whenever the agent's file changes; with one, only when it opens, since
    /// the feed carries everything after.
    func loadHistory(id: String, force: Bool = false) async {
        guard enabled, let session = store.session(id: id), !loadingHistory.contains(id) else { return }
        let live = store.hasLiveFeed(id)
        let stamp = session.transcriptPath.flatMap(Self.modificationDate(path:))
        if !force {
            guard !live, let stamp, stamp != transcriptStamps[id] else { return }
        }
        loadingHistory.insert(id)
        defer { loadingHistory.remove(id) }
        let epoch = connectionEpoch
        var history: [AgentMessage]
        var title: String?
        var path = session.transcriptPath
        switch session.sourceID {
        case "codex":
            guard client.isReady else { return }
            do {
                let result = try await client.request("thread/turns/list", [
                    "threadId": session.sessionKey, "limit": Self.historyTurns, "sortDirection": "desc", "itemsView": "full",
                ])
                guard epoch == connectionEpoch else { return }
                history = CodexSessionProjection.messages(turns: (result["data"] as? [[String: Any]] ?? []).reversed())
                if session.transcriptPath == nil,
                   let thread = try? await client.request("thread/read", ["threadId": session.sessionKey, "includeTurns": false])["thread"] as? [String: Any] {
                    path = thread["path"] as? String
                }
            } catch {
                errors[id] = String(localized: "Could not load the conversation: \(error.localizedDescription)")
                return
            }
        default:
            // Other agents keep their own transcript file, which their source reads.
            // Reading and parsing up to a megabyte of JSON happens off the main
            // thread; an open conversation rereads it whenever the agent writes.
            guard let source = session.source, let path = session.transcriptPath,
                  let transcript = await Task.detached(operation: {
                      AgentTranscriptFile.tail(path: path).flatMap { source.transcript(from: AgentTranscriptFile.rows($0)) }
                  }).value else { return }
            history = transcript.messages
            title = transcript.title
        }
        guard enabled, var current = store.session(id: id) else { return }
        // The stamp from before the read, so a change made during it is read next time.
        transcriptStamps[id] = stamp ?? path.flatMap(Self.modificationDate(path:))
        current.transcriptPath = path
        errors[id] = nil
        if store.hasLiveFeed(id) {
            // Items the feed delivered after the saved page stay at the end.
            let known = Set(history.map(\.id))
            history += current.messages.reversed().prefix { !known.contains($0.id) }.reversed()
        }
        guard !history.isEmpty else { return }
        current.messages = Array(history.suffix(AgentSession.messageLimit))
        current.title = title ?? current.title
        current.lastPrompt = history.last(where: { $0.role == .user })?.text ?? current.lastPrompt
        current.lastReply = history.last(where: { $0.role == .assistant })?.text ?? current.lastReply
        store.upsert(current)
    }

    private nonisolated static func modificationDate(path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    // MARK: Sending

    /// A message typed here can reach the session now.
    func canSend(_ session: AgentSession) -> Bool { route(for: session) != nil }

    /// How a message typed here reaches the session now. Codex's shared
    /// service comes first, since it confirms delivery. Otherwise the terminal
    /// pane, which takes a message whether the agent works or waits, just as
    /// its keyboard does; then the agent's own hook route.
    func route(for session: AgentSession) -> AgentSendRoute? {
        // An agent asking for approval would take typed text as its answer.
        guard enabled, !session.isDisconnected, !session.blocksInput else { return nil }
        let delivery = session.source?.replyDelivery
        if case .sharedService = delivery, client.isSharedDaemon, store.hasLiveFeed(session.id),
           session.canAcceptDirectInput == true {
            return .sharedService
        }
        if terminals.canType(into: session), let terminal = terminals.host(for: session) {
            return .terminal(terminal.displayName)
        }
        switch delivery {
        case .wakeWhenIdle:
            return parkedSessions.contains(session.id) && !session.state.isWorking ? .wakeWhenIdle : nil
        case .injectWhileWorking:
            return session.state.isWorking && queuedReplies[session.id] == nil ? .injectWhileWorking : nil
        case .sharedService, nil:
            return nil
        }
    }

    /// The terminal app hosting the session, when Atoll can type into that app.
    func terminalName(for session: AgentSession) -> String? {
        terminals.host(for: session)?.displayName
    }

    func send(id: String) {
        guard let session = store.session(id: id), let route = route(for: session),
              !sending.contains(id), !uncertainIDs.contains(id) else { return }
        let prompt = (drafts[id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, prompt.count <= AgentSession.messageCharacterLimit else { return }
        errors[id] = nil
        notices[id] = nil
        switch route {
        case .sharedService: sendThroughService(session, prompt: prompt)
        case .terminal(let terminal): typeIntoTerminal(session, terminal: terminal, prompt: prompt)
        case .wakeWhenIdle: wake(session, prompt: prompt)
        case .injectWhileWorking: queueForNextStep(session, prompt: prompt)
        }
    }

    /// Types the message into the session's pane and submits it. The agent
    /// records it as the user's prompt once it takes it, as with the keyboard.
    private func typeIntoTerminal(_ session: AgentSession, terminal: String, prompt: String) {
        let id = session.id
        sending.insert(id)
        sendingTasks[id] = Task { [weak self] in
            guard let self else { return }
            defer { sending.remove(id); sendingTasks[id] = nil }
            do {
                try await terminals.type(prompt, into: session)
                if drafts[id]?.trimmingCharacters(in: .whitespacesAndNewlines) == prompt { drafts[id] = "" }
                let agent = session.source?.displayName ?? String(localized: "The agent")
                notices[id] = String(localized: "Typed into \(terminal). It appears here once \(agent) takes it.")
            } catch {
                errors[id] = error.localizedDescription
            }
        }
    }

    /// Brings back the session's terminal, at its own pane when Atoll knows it.
    func openTerminal(_ session: AgentSession) async -> AgentTerminals.FocusResult {
        await terminals.focus(session)
    }

    private func sendThroughService(_ session: AgentSession, prompt: String) {
        let id = session.id
        let threadID = session.sessionKey
        let commandID = UUID().uuidString
        sending.insert(id)
        // Persist a receipt before dispatch, never the prompt. A crash cannot
        // turn an uncertain dispatch into a retry on the next launch.
        uncertainIDs.insert(id)
        persistReceipts()
        awaitingEcho.insert(commandID)
        sendingTasks[id] = Task { [weak self] in
            guard let self else { return }
            defer { sending.remove(id); sendingTasks[id] = nil }
            do {
                // Codex joins a message sent mid-turn to the running turn, as
                // the terminal does, so idle and busy sessions take the same call.
                let result: [String: Any]
                do {
                    result = try await client.request("turn/start", [
                        "threadId": threadID, "clientUserMessageId": commandID,
                        "input": [["type": "text", "text": prompt, "text_elements": []]],
                    ])
                } catch AgentConnectionError.rejected(let message) {
                    throw AgentConnectionError.rejected(message)
                } catch {
                    throw AgentConnectionError.uncertain
                }
                guard let turnID = (result["turn"] as? [String: Any])?["id"] as? String else { throw AgentConnectionError.uncertain }
                uncertainIDs.remove(id)
                persistReceipts()
                let canOwnTurn = !(store.session(id: id)?.retiredTurnIDs ?? []).contains(turnID)
                    && (activeTurns[threadID] == nil || activeTurns[threadID] == turnID)
                if canOwnTurn {
                    ownedTurns[threadID] = turnID
                    if activeTurns[threadID] == nil { activeTurns[threadID] = turnID }
                }
                // Only acknowledgement clears the draft; keep edits made while it was in flight.
                if drafts[id]?.trimmingCharacters(in: .whitespacesAndNewlines) == prompt { drafts[id] = "" }
                // Show the message until Codex echoes it as an item, which replaces it.
                if canOwnTurn, var current = store.session(id: id), current.currentTurnID != turnID {
                    current.beginTurn(turnID)
                    current.state = .thinking
                    store.upsert(current)
                }
                if awaitingEcho.contains(commandID), var current = store.session(id: id) {
                    current.upsertMessage(AgentMessage(id: commandID, role: .user, text: prompt))
                    current.lastPrompt = prompt
                    if canOwnTurn {
                        if !current.state.isWorking { current.state = .thinking }
                        current.finishedAt = nil
                    }
                    store.upsert(current)
                }
            } catch {
                awaitingEcho.remove(commandID)
                if case AgentConnectionError.uncertain = error {
                    errors[id] = AgentConnectionError.uncertain.localizedDescription
                } else {
                    uncertainIDs.remove(id)
                    persistReceipts()
                    errors[id] = error.localizedDescription
                }
            }
        }
    }

    func acknowledgeUncertainDelivery(id: String) {
        uncertainIDs.remove(id)
        persistReceipts()
        errors[id] = nil
    }

    private func persistReceipts() {
        defaults.set(Array(uncertainIDs), forKey: Self.receiptKey)
    }

    func canInterrupt(_ session: AgentSession) -> Bool {
        store.hasLiveFeed(session.id) && activeTurns[session.sessionKey] != nil
    }

    /// Stops the running turn, like Esc in the terminal.
    func interrupt(id: String) {
        guard let session = store.session(id: id), canInterrupt(session),
              let turnID = activeTurns[session.sessionKey] else { return }
        Task {
            do { _ = try await client.request("turn/interrupt", ["threadId": session.sessionKey, "turnId": turnID]) }
            catch { errors[id] = error.localizedDescription }
        }
    }

    func answerApproval(_ approval: AgentApproval, allow: Bool) {
        guard approvals.contains(where: { $0.id == approval.id }) else { return }
        do {
            try client.reply(id: approval.requestID, result: ["decision": allow ? "accept" : "decline"])
            approvals.removeAll { $0.id == approval.id }
            if var session = store.session(id: approval.sessionID) {
                session.pendingRequests?[Self.requestKey(approval.requestID)] = nil
                session.state = session.activityState ?? .thinking
                session.restorePendingAttention()
                store.upsert(session)
            }
        } catch { errors[approval.sessionID] = error.localizedDescription }
    }

    // MARK: Replies through hooks

    private struct ParkedHook {
        let token: UUID
        let reply: (Data?) -> Void
    }

    private struct PendingReply {
        let commandID: String
        let text: String
    }

    /// Sessions whose agent is waiting for the user with a hook parked in Atoll.
    @Published private(set) var parkedSessions: Set<String> = []
    private var parkedHooks: [String: ParkedHook] = [:]
    /// Messages for an agent's next step, until a hook takes them.
    private var queuedReplies: [String: PendingReply] = [:]
    /// Messages handed to a woken agent, until it shows it took them.
    private var handedOff: [String: PendingReply] = [:]
    private static let wakeConfirmationTimeout: Duration = .seconds(30)
    private static let nextStepTimeout: Duration = .seconds(300)

    /// Wakes a waiting agent with the message. It confirms by echoing the
    /// prompt in its next `UserPromptSubmit`, or by saving it to its transcript.
    private func wake(_ session: AgentSession, prompt: String) {
        let id = session.id
        guard let hook = parkedHooks.removeValue(forKey: id) else { return }
        parkedSessions.remove(id)
        let pending = PendingReply(commandID: UUID().uuidString, text: prompt)
        handedOff[id] = pending
        sending.insert(id)
        hook.reply(Data(AtollMessageEnvelope.wrap(id: pending.commandID, text: prompt).utf8))
        sendingTasks[id] = Task { [weak self] in
            let deadline = ContinuousClock.now + Self.wakeConfirmationTimeout
            while ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, handedOff[id]?.commandID == pending.commandID else { return }
                if let path = store.session(id: id)?.transcriptPath,
                   let tail = await Task.detached(operation: { AgentTranscriptFile.tail(path: path, bytes: 64 * 1024) }).value,
                   tail.range(of: Data(pending.commandID.utf8)) != nil {
                    return delivered(id, pending, showMessage: true)
                }
            }
            guard let self, handedOff[id]?.commandID == pending.commandID else { return }
            handedOff[id] = nil
            sending.remove(id)
            sendingTasks[id] = nil
            uncertainIDs.insert(id)
            persistReceipts()
            errors[id] = AgentConnectionError.uncertain.localizedDescription
        }
    }

    /// Leaves the message for the agent's next step to pick up.
    private func queueForNextStep(_ session: AgentSession, prompt: String) {
        let id = session.id
        let pending = PendingReply(commandID: UUID().uuidString, text: prompt)
        queuedReplies[id] = pending
        sending.insert(id)
        sendingTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: Self.nextStepTimeout)
            guard let self, queuedReplies[id]?.commandID == pending.commandID else { return }
            queuedReplies[id] = nil
            sending.remove(id)
            sendingTasks[id] = nil
            errors[id] = String(localized: "The agent did not reach its next step in time, so nothing was sent. Type it in the terminal instead.")
        }
    }

    private func delivered(_ id: String, _ pending: PendingReply, showMessage: Bool) {
        handedOff[id] = nil
        sending.remove(id)
        sendingTasks.removeValue(forKey: id)?.cancel()
        if drafts[id]?.trimmingCharacters(in: .whitespacesAndNewlines) == pending.text { drafts[id] = "" }
        guard showMessage, var session = store.session(id: id) else { return }
        session.upsertMessage(AgentMessage(id: pending.commandID, role: .user, text: pending.text))
        session.lastPrompt = pending.text
        store.upsert(session)
    }

    /// The parked hook stands down and the agent carries on without a message.
    private func releaseParkedHook(_ id: String) {
        guard let hook = parkedHooks.removeValue(forKey: id) else { return }
        parkedSessions.remove(id)
        hook.reply(nil)
    }

    private func hookStoppedWaiting(_ id: String, token: UUID) {
        guard parkedHooks[id]?.token == token else { return }
        parkedHooks[id] = nil
        parkedSessions.remove(id)
    }

    // MARK: Live feed

    private func handleEvent(_ method: String, _ params: [String: Any]) {
        guard enabled, client.isSharedDaemon else { return }
        if method == "thread/started" {
            // A terminal just opened a session; pick it up without waiting for the next poll.
            Task { await refresh() }
            return
        }
        guard let threadID = params["threadId"] as? String else { return }
        let id = Self.sessionID(threadID)
        guard subscribed.contains(threadID), var session = store.session(id: id) else {
            // A terminal's thread became active before Atoll followed it.
            if method == "thread/status/changed", (params["status"] as? [String: Any])?["type"] as? String == "active",
               !ignoredThreads.contains(threadID) { Task { await refresh() } }
            return
        }
        if let emitted = params["_atollEmittedAtMs"] as? Double, emitted.isFinite {
            if let previous = ownerEmissionTimes[threadID], emitted < previous { return }
            ownerEmissionTimes[threadID] = emitted
        }
        let now = Date()
        let turnID = (params["turn"] as? [String: Any])?["id"] as? String ?? params["turnId"] as? String
        if let turnID {
            guard !(session.retiredTurnIDs ?? []).contains(turnID) else { return }
            if method != "turn/started", let current = session.currentTurnID, current != turnID { return }
        }
        switch method {
        case "thread/status/changed":
            guard let status = params["status"] as? [String: Any] else { return }
            CodexSessionProjection.applyStatus(status, to: &session, now: now)
            if status["type"] as? String == "notLoaded" { store.upsert(session); endLiveFeed(threadID); return }
        case "thread/closed":
            session.isDisconnected = true
            store.upsert(session)
            endLiveFeed(threadID)
            return
        case "thread/name/updated":
            session.title = (params["threadName"] as? String)?.nonBlank ?? session.title
        case "turn/started":
            if ownedTurns[threadID] != turnID { ownedTurns[threadID] = nil }
            activeTurns[threadID] = turnID
            if session.currentTurnID != turnID {
                session.beginTurn(turnID)
                approvals.removeAll { $0.sessionID == id }
            }
            session.state = .thinking
            session.statusUncertain = false
            session.finishedAt = nil
        case "serverRequest/resolved":
            guard let requestID = params["requestId"] else { return }
            let key = Self.requestKey(requestID)
            session.pendingRequests?[key] = nil
            approvals.removeAll { $0.sessionID == id && Self.requestKey($0.requestID) == key }
            session.state = session.activityState ?? .thinking
            session.restorePendingAttention()
        case "item/started", "item/completed":
            guard let item = params["item"] as? [String: Any] else { return }
            apply(item: item, completed: method == "item/completed", to: &session, id: id)
        case "item/agentMessage/delta":
            guard let delta = params["delta"] as? String else { return }
            streaming[id] = String(((streaming[id] ?? "") + delta).suffix(AgentSession.messageCharacterLimit))
        case "turn/completed":
            let turn = params["turn"] as? [String: Any] ?? [:]
            // An unidentified completion cannot safely settle an identified turn.
            if session.currentTurnID != nil && turnID == nil { session.statusUncertain = true; store.upsert(session); return }
            if activeTurns[threadID] == nil, session.state == .finished || session.wasCancelled == true { return }
            switch turn["status"] as? String {
            case "failed":
                session.state = .failed(message: (turn["error"] as? [String: Any])?["message"] as? String)
                session.finishedAt = nil
            case "interrupted":
                session.state = .idle
                session.wasCancelled = true
                session.finishedAt = nil
            case "completed":
                if session.state != .finished { session.finishedAt = now }
                session.state = .finished
            default:
                session.statusUncertain = true
                session.finishedAt = nil
                store.upsert(session)
                return
            }
            if let turnID { session.retiredTurnIDs = Array(((session.retiredTurnIDs ?? []).filter { $0 != turnID } + [turnID]).suffix(16)) }
            session.pendingRequests = nil
            session.activityState = nil
            session.statusUncertain = false
            streaming[id] = nil
            activeTurns[threadID] = nil
            ownedTurns[threadID] = nil
            approvals.removeAll { $0.sessionID == id }
        default:
            return
        }
        session.updatedAt = now
        session.lastSeenAt = now
        store.upsert(session)
    }

    private func apply(item: [String: Any], completed: Bool, to session: inout AgentSession, id: String) {
        let type = item["type"] as? String
        if type == "agentMessage" {
            // The streamed text becomes the message once it completes.
            if completed { streaming[id] = nil } else { streaming[id] = ""; return }
        }
        if type == "userMessage", let clientID = item["clientId"] as? String {
            awaitingEcho.remove(clientID)
            session.messages.removeAll { $0.id == clientID }
        }
        guard let message = CodexSessionProjection.message(for: item) else { return }
        session.upsertMessage(message)
        switch message.role {
        case .user:
            session.lastPrompt = message.text
            session.lastReply = nil
        case .assistant:
            session.lastReply = message.text
        case .activity:
            session.activityState = completed ? .thinking : .tool(message.toolKind ?? .other, name: "", detail: message.text)
            if !session.state.needsAttention { session.state = session.activityState! }
            session.restorePendingAttention()
        }
    }

    private static func requestKey(_ id: Any) -> String {
        // Preserve JSON-RPC's distinct integer and string namespaces.
        if let string = id as? String {
            return "rpc:s:" + SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        return "rpc:n:" + String(String(describing: id).prefix(240))
    }

    private func handleRequest(_ requestID: Any, _ method: String, _ params: [String: Any]) {
        if method == "currentTime/read" {
            try? client.reply(id: requestID, result: ["currentTimeAt": Int(Date().timeIntervalSince1970)])
            return
        }
        // Observe foreign requests without answering them. Only Atoll-owned
        // command/file approvals are actionable in this UI.
        guard enabled, let threadID = params["threadId"] as? String, subscribed.contains(threadID),
              var session = store.session(id: Self.sessionID(threadID)) else { return }
        if let turn = params["turnId"] as? String {
            guard !(session.retiredTurnIDs ?? []).contains(turn) else { return }
            if let current = session.currentTurnID, turn != current { return }
        }
        let interactive = ["item/commandExecution/requestApproval", "item/fileChange/requestApproval", "item/tool/requestUserInput", "mcpServer/elicitation/request", "item/permissions/requestApproval"]
        guard interactive.contains(method) else { return }
        let id = session.id
        let key = Self.requestKey(requestID)
        var requests = session.pendingRequests ?? [:]
        guard requests.count < 64 || requests[key] != nil else {
            session.statusUncertain = true
            store.upsert(session)
            return
        }
        let isApproval = method.hasSuffix("requestApproval")
        requests[key] = String(localized: isApproval ? "Approval required" : "Waiting for your answer")
        session.pendingRequests = requests
        if session.state.isWorking { session.activityState = session.state }
        session.restorePendingAttention()
        store.upsert(session)
        guard let ownedTurn = ownedTurns[threadID], ownedTurn == session.currentTurnID, method == "item/commandExecution/requestApproval" || method == "item/fileChange/requestApproval",
              !approvals.contains(where: { $0.sessionID == id && Self.requestKey($0.requestID) == key }) else { return }
        let isCommand = method == "item/commandExecution/requestApproval"
        let details = [params["reason"] as? String, params["command"] as? String, params["grantRoot"] as? String].compactMap { $0 }.joined(separator: "\n\n")
        approvals.append(AgentApproval(id: connectionEpoch.uuidString + ":" + key, requestID: requestID, sessionID: id,
                                       title: isCommand ? String(localized: "Allow this command?") : String(localized: "Allow these file changes?"),
                                       detail: String(details.prefix(8_000))))
    }
}

extension AgentConversationService: AgentHookReceiver {
    func receive(_ event: AgentHookEvent) -> Data? {
        let id = AgentSession.key(sourceID: event.sourceID, sessionKey: event.sessionKey)
        if let current = store.session(id: id), !current.accepts(event) { return nil }
        switch event.phase {
        case .promptSubmitted:
            notices[id] = nil  // The agent took what was typed; the conversation shows it now.
            if let pending = handedOff[id], event.prompt.flatMap(AtollMessageEnvelope.unwrap)?.id == pending.commandID {
                // The event itself records the message in the conversation.
                delivered(id, pending, showMessage: false)
            } else {
                releaseParkedHook(id)  // The user answered in the terminal.
            }
        case .sessionEnded:
            releaseParkedHook(id)
            if queuedReplies.removeValue(forKey: id) != nil {
                sending.remove(id)
                sendingTasks.removeValue(forKey: id)?.cancel()
                errors[id] = String(localized: "The session ended before it took the message, so nothing was sent.")
            }
        default:
            break
        }
        store.apply(event)
        terminals.track(event, in: store)
        guard let name = event.eventName, let pending = queuedReplies[id],
              let output = AgentSourceRegistry.source(id: event.sourceID)?.replyOutput(pending.text, atEvent: name) else { return nil }
        queuedReplies[id] = nil
        delivered(id, pending, showMessage: true)
        return output
    }

    func park(_ event: AgentHookEvent, reply: @escaping (Data?) -> Void, onClose: (@escaping @Sendable () -> Void) -> Void) {
        let id = AgentSession.key(sourceID: event.sourceID, sessionKey: event.sessionKey)
        guard enabled else { return reply(nil) }
        if let current = store.session(id: id) {
            guard event.receivedAt >= current.updatedAt,
                  event.turnID == nil || event.turnID == current.currentTurnID else { return reply(nil) }
        }
        // A newer turn's hook takes over from an older one still waiting.
        releaseParkedHook(id)
        let token = UUID()
        parkedHooks[id] = ParkedHook(token: token, reply: reply)
        parkedSessions.insert(id)
        onClose { [weak self] in Task { @MainActor in self?.hookStoppedWaiting(id, token: token) } }
    }
}
