import Foundation

/// A lifecycle step, normalised across agents. Each `AgentSource` maps its own
/// hook event names onto these, so nothing past the source layer knows that
/// Claude calls it `Stop` and Antigravity calls it something else.
enum AgentEventPhase: Equatable {
    case sessionStarted
    case promptSubmitted
    /// The model is between tool calls (a new model invocation, or a tool just returned).
    case thinking
    case toolStarted
    case needsAttention
    case attentionResolved
    case turnCancelled
    case statusUncertain
    case turnFinished
    case turnFailed
    case sessionEnded
}

/// What a tool call is doing, coarse enough to read at a glance in the notch.
enum AgentToolKind: String, Equatable, Codable {
    case command
    case edit
    case read
    case search
    case web
    case delegate
    case other
}

enum AgentState: Equatable, Codable {
    /// Session is open and waiting for the user's next prompt.
    case idle
    case thinking
    case tool(AgentToolKind, name: String, detail: String?)
    case needsAttention(message: String?)
    case finished
    case failed(message: String?)

    /// The agent is busy and the user does not need to do anything.
    var isWorking: Bool {
        switch self {
        case .thinking, .tool: return true
        default: return false
        }
    }

    var needsAttention: Bool {
        if case .needsAttention = self { return true }
        return false
    }
}

/// One normalised hook event, already routed to its source.
struct AgentHookEvent {
    let sourceID: String
    let phase: AgentEventPhase
    /// The session key the agent reported, or a fallback derived from `cwd`.
    let sessionKey: String
    let cwd: String?
    let prompt: String?
    let toolName: String?
    let toolKind: AgentToolKind?
    let toolDetail: String?
    let message: String?
    /// The agent's final reply, when the event that ends a turn carries it.
    let lastReply: String?
    /// Bundle identifier of the app hosting the agent (the terminal, or the
    /// agent's own desktop app), so a card can bring it back to the front.
    let hostBundleID: String?
    /// The pane the hook's environment named, for terminals that name panes there.
    var hostPane: String? = nil
    /// The process that ran the hook, which leads to the agent's terminal device.
    var hostProcessID: Int32? = nil
    /// The agent's own record of the conversation, when the hook names it.
    var transcriptPath: String? = nil
    /// The agent's own name for the hook, where one phase covers several.
    var eventName: String? = nil
    var turnID: String? = nil
    var toolUseID: String? = nil
    var requestID: String? = nil
    let receivedAt: Date
}

/// One line of a conversation as the terminal shows it: what the user typed,
/// what the agent said, or a one-line summary of a tool call. Tool output and
/// reasoning never become messages.
struct AgentMessage: Identifiable, Equatable, Codable {
    enum Role: String, Codable { case user, assistant, activity }
    let id: String
    let role: Role
    /// For `.activity`, the command, file or query the tool call worked on.
    let text: String
    var toolKind: AgentToolKind? = nil

    static func activity(id: String, kind: AgentToolKind, detail: String) -> AgentMessage {
        AgentMessage(id: id, role: .activity, text: detail, toolKind: kind)
    }
}

struct AgentSession: Identifiable, Equatable, Codable {
    /// How much of a conversation a card keeps: enough to read the last few turns.
    static let messageLimit = 40
    static let messageCharacterLimit = 16_000

    let id: String
    let sourceID: String
    var cwd: String?
    var hostBundleID: String?
    var lastPrompt: String?
    var lastReply: String?
    var state: AgentState
    let startedAt: Date
    var updatedAt: Date
    /// When the current turn ended, so the closed notch can flash "finished"
    /// briefly instead of for as long as the session stays open.
    var finishedAt: Date?
    var title: String? = nil
    var model: String? = nil
    var messages: [AgentMessage] = []
    var isDisconnected = false
    /// Codex's own record of who started the thread (`codex-tui`, `Codex Desktop`).
    var originator: String? = nil
    var sourceKind: String? = nil
    /// Codex accepts messages for this thread from Atoll (it is loaded in the
    /// shared service). `nil` or `false` means read-only.
    var canAcceptDirectInput: Bool? = nil
    /// Last sign of life from the agent, separate from content age.
    var lastSeenAt: Date? = nil
    /// The agent's conversation file, read to follow sessions without a live feed.
    var transcriptPath: String? = nil
    /// The terminal device the agent runs on ("/dev/ttys003").
    var terminalDevice: String? = nil
    /// The agent's pane in its terminal app, in that app's own terms (a cmux
    /// surface, a Ghostty terminal id, a Terminal tty), once Atoll found it.
    var terminalPane: String? = nil

    // Optional fields keep snapshots from earlier versions decodable. These are
    // bounded current-turn facts, not a second conversation history.
    var attentionSince: Date? = nil
    var currentTurnID: String? = nil
    var retiredTurnIDs: [String]? = nil
    var pendingRequests: [String: String]? = nil
    var activityState: AgentState? = nil
    var statusUncertain: Bool? = nil
    var wasCancelled: Bool? = nil

    var hasPendingRequests: Bool { !(pendingRequests ?? [:]).isEmpty }
    /// Aggregate waiting flags establish attention, but do not identify extra requests.
    var identifiedPendingRequestCount: Int {
        (pendingRequests ?? [:]).keys.filter { !$0.hasPrefix("status:") }.count
    }
    var pendingRequestSummary: String {
        let count = identifiedPendingRequestCount
        return count > 0 ? String(localized: "\(count) pending") : String(localized: "Waiting reported")
    }
    var blocksInput: Bool { state.needsAttention || hasPendingRequests || statusUncertain == true }
    var isWorking: Bool { state.isWorking || activityState?.isWorking == true }

    mutating func restorePendingAttention() {
        if hasPendingRequests {
            state = .needsAttention(message: pendingRequests?.sorted { $0.key < $1.key }.first?.value)
        }
    }

    mutating func beginTurn(_ turnID: String?) {
        if let currentTurnID, currentTurnID != turnID {
            retiredTurnIDs = Array(((retiredTurnIDs ?? []) + [currentTurnID]).suffix(16))
        }
        currentTurnID = turnID
        pendingRequests = nil
        attentionSince = nil
        activityState = nil
        wasCancelled = false
        statusUncertain = false
        finishedAt = nil
    }

    /// Stopped on something only the user can answer, in a session still running.
    var isWaitingOnUser: Bool {
        state.needsAttention && !isDisconnected && statusUncertain != true
    }

    /// Desktop apps have their own conversation UI; the notch follows terminals.
    /// A hook names the hosting app; a Codex thread without one says who started it.
    var isTerminalSession: Bool {
        if let host = hostBundleID?.lowercased() {
            return !["com.openai.codex", "com.openai.chat", "com.google.antigravity"].contains(host)
        }
        guard sourceID == "codex" else { return true }
        return originator == "codex-tui" || sourceKind == "cli"
    }

    var sessionKey: String { String(id.dropFirst(sourceID.count + 1)) }

    mutating func appendMessage(role: AgentMessage.Role, text: String?) {
        guard let text = text?.nonBlank else { return }
        if messages.last?.role == role && messages.last?.text == text { return }
        upsertMessage(AgentMessage(id: UUID().uuidString, role: role, text: text))
    }

    /// Replaces the message with the same id, or appends it.
    mutating func upsertMessage(_ message: AgentMessage) {
        let bounded = AgentMessage(id: message.id, role: message.role,
                                   text: String(message.text.prefix(Self.messageCharacterLimit)), toolKind: message.toolKind)
        if let index = messages.firstIndex(where: { $0.id == bounded.id }) {
            messages[index] = bounded
        } else {
            messages.append(bounded)
            messages = Array(messages.suffix(Self.messageLimit))
        }
    }

    /// The project folder's name, when the agent reported one.
    var projectName: String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    static func key(sourceID: String, sessionKey: String) -> String {
        "\(sourceID):\(sessionKey)"
    }

    /// Identified old events cannot change state or hook delivery routes.
    func accepts(_ event: AgentHookEvent) -> Bool {
        guard event.receivedAt >= updatedAt else { return false }
        if let turn = event.turnID {
            guard !(retiredTurnIDs ?? []).contains(turn) else { return false }
            if let currentTurnID, currentTurnID != turn,
               event.phase != .promptSubmitted && event.phase != .sessionStarted { return false }
        }
        return true
    }

    /// Healthy owner feeds provide conversation and lifecycle. Their hooks
    /// can update terminal metadata without overwriting that authoritative state.
    func applying(_ event: AgentHookEvent, recordingMessages: Bool = true, applyingLifecycle: Bool = true) -> AgentSession {
        guard accepts(event) else { return self }
        var next = self
        if let cwd = event.cwd { next.cwd = cwd }
        if let host = event.hostBundleID {
            if host != next.hostBundleID { next.terminalPane = nil }
            next.hostBundleID = host
        }
        if let path = event.transcriptPath { next.transcriptPath = path }
        // Healthy owner feeds are authoritative. Hooks can still identify the
        // terminal, but cannot overwrite a live approval or turn state.
        guard applyingLifecycle else { return next }
        next.updatedAt = event.receivedAt
        if event.phase != .statusUncertain { next.lastSeenAt = event.receivedAt }
        if event.phase != .statusUncertain { next.isDisconnected = false }
        if next.currentTurnID == nil { next.currentTurnID = event.turnID }
        let requestKey = event.requestID ?? event.toolUseID.map { "tool:\($0)" }

        switch event.phase {
        case .sessionStarted:
            next.beginTurn(event.turnID)
            next.state = .idle
        case .promptSubmitted:
            next.beginTurn(event.turnID)
            let prompt = event.prompt.flatMap(AtollMessageEnvelope.visibleUserText)
            if let prompt { next.lastPrompt = prompt }
            if recordingMessages { next.appendMessage(role: .user, text: prompt) }
            next.lastReply = nil
            next.state = .thinking
        case .thinking, .attentionResolved:
            if let requestKey { next.pendingRequests?[requestKey] = nil }
            // Anonymous legacy waits can only follow explicit continuation.
            // An identified request survives unrelated tool completion.
            next.activityState = .thinking
            next.state = .thinking
            next.restorePendingAttention()
            next.finishedAt = nil
        case .toolStarted:
            let kind = event.toolKind ?? .other
            next.activityState = .tool(kind, name: event.toolName ?? "", detail: event.toolDetail)
            if !next.state.needsAttention { next.state = next.activityState! }
            next.restorePendingAttention()
            next.finishedAt = nil
            if recordingMessages, let detail = event.toolDetail ?? event.toolName {
                next.upsertMessage(.activity(id: event.toolUseID ?? UUID().uuidString, kind: kind, detail: detail))
            }
        case .needsAttention:
            if let requestKey, requestKey.utf8.count <= 256 {
                var requests = next.pendingRequests ?? [:]
                if requests.count < 64 || requests[requestKey] != nil {
                    requests[requestKey] = String((event.message ?? String(localized: "Approval required")).prefix(1024))
                    next.pendingRequests = requests
                } else { next.statusUncertain = true }
            }
            if next.state.isWorking { next.activityState = next.state }
            next.state = .needsAttention(message: event.message)
        case .turnFinished:
            // Cancellation/failure followed by idle is not a successful turn.
            guard next.wasCancelled != true, !next.hasPendingRequests else { return next }
            if case .failed = next.state { return next }
            if next.state != .finished { next.finishedAt = event.receivedAt }
            next.state = .finished
            next.activityState = nil
            if let reply = event.lastReply { next.lastReply = reply }
            if recordingMessages { next.appendMessage(role: .assistant, text: event.lastReply) }
        case .turnFailed:
            next.state = .failed(message: event.message)
            next.finishedAt = nil
            next.activityState = nil
            next.pendingRequests = nil
        case .turnCancelled:
            next.state = .idle
            next.wasCancelled = true
            next.activityState = nil
            next.pendingRequests = nil
            next.finishedAt = nil
        case .statusUncertain:
            next.statusUncertain = true
            next.finishedAt = nil
        case .sessionEnded:
            next.isDisconnected = true
            next.pendingRequests = nil
            next.activityState = nil
            next.finishedAt = nil
            if next.state.isWorking || next.state.needsAttention { next.state = .idle }
        }
        if next.isWaitingOnUser { next.attentionSince = attentionSince ?? event.receivedAt }
        else { next.attentionSince = nil }
        if [.turnFinished, .turnCancelled, .turnFailed].contains(event.phase), let turn = event.turnID {
            next.retiredTurnIDs = Array(((next.retiredTurnIDs ?? []).filter { $0 != turn } + [turn]).suffix(16))
        }
        return next
    }

    static func starting(with event: AgentHookEvent) -> AgentSession {
        let blank = AgentSession(
            id: key(sourceID: event.sourceID, sessionKey: event.sessionKey),
            sourceID: event.sourceID,
            cwd: event.cwd,
            hostBundleID: event.hostBundleID,
            lastPrompt: nil,
            lastReply: nil,
            state: .idle,
            startedAt: event.receivedAt,
            updatedAt: event.receivedAt,
            finishedAt: nil
        )
        return blank.applying(event)
    }
}

/// A message typed in Atoll, framed for an agent that takes it from a hook
/// rather than as typed input. The marker line lets Atoll recognise its own
/// message when the agent echoes it back.
enum AtollMessageEnvelope {
    static let marker = "ATOLL_USER_MESSAGE_V1 "

    static func wrap(id: String, text: String) -> String {
        let payload = (try? JSONSerialization.data(withJSONObject: ["id": id, "prompt": text])).map { String(decoding: $0, as: UTF8.self) } ?? ""
        return "The user typed this follow-up in Atoll (the notch app) instead of the terminal. "
            + "Treat it as their next message in this conversation. It does not approve any tool or change any permission.\n"
            + marker + payload
    }

    /// Atoll's message inside `text`, which the agent may have wrapped in its own markup.
    static func unwrap(_ text: String) -> (id: String, prompt: String)? {
        guard let line = text.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix(marker) }),
              let object = try? JSONSerialization.jsonObject(with: Data(line.dropFirst(marker.count).utf8)) as? [String: Any],
              let id = object["id"] as? String, let prompt = (object["prompt"] as? String)?.nonBlank else { return nil }
        return (id, prompt)
    }

    /// What the user actually said in a prompt the agent reports: Atoll's
    /// message unwrapped, and nil for markup the agent adds on its own
    /// (background-task notices, reminders, slash-command echoes).
    static func visibleUserText(_ text: String) -> String? {
        if let message = unwrap(text) { return message.prompt }
        let injected = ["<task-notification>", "<command-name>", "<command-message>", "<local-command", "<system-reminder>"]
        return injected.contains(where: text.hasPrefix) ? nil : text.nonBlank
    }
}

extension String {
    /// The text without surrounding whitespace, or nil when nothing is left.
    var nonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
