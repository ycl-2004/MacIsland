import Foundation

/// Turns Codex app-server threads and items into Atoll sessions and
/// conversation lines. Tool output and reasoning never cross into the UI: a
/// tool call becomes one line naming its command, file or query, as the
/// terminal shows it.
enum CodexSessionProjection {
    /// A user's own top-level thread, not a subagent or an ephemeral helper.
    static func isFollowable(_ thread: [String: Any]) -> Bool {
        thread["ephemeral"] as? Bool != true && thread["parentThreadId"] as? String == nil
            && thread["source"] is String
    }

    /// `live` means the thread comes from the shared service that owns it, so
    /// its runtime status and input capability are real. A private reader only
    /// sees saved history and reports every thread as `notLoaded`.
    static func session(_ thread: [String: Any], existing: AgentSession?, live: Bool, now: Date = Date()) -> AgentSession? {
        guard let key = thread["id"] as? String, UUID(uuidString: key) != nil else { return nil }
        let updated = Date(timeIntervalSince1970: thread["updatedAt"] as? Double ?? 0)
        var session = existing ?? AgentSession(
            id: AgentSession.key(sourceID: "codex", sessionKey: key), sourceID: "codex",
            cwd: thread["cwd"] as? String, hostBundleID: nil, lastPrompt: nil, lastReply: nil,
            state: .idle, startedAt: Date(timeIntervalSince1970: thread["createdAt"] as? Double ?? 0),
            updatedAt: updated, finishedAt: nil)
        session.title = (thread["name"] as? String)?.nonBlank ?? session.title
        session.cwd = thread["cwd"] as? String ?? session.cwd
        session.model = thread["model"] as? String ?? session.model
        session.originator = thread["originator"] as? String ?? session.originator
        session.sourceKind = thread["source"] as? String ?? session.sourceKind
        session.transcriptPath = thread["path"] as? String ?? session.transcriptPath
        session.canAcceptDirectInput = live && thread["canAcceptDirectInput"] as? Bool == true
        if session.lastPrompt == nil { session.lastPrompt = (thread["preview"] as? String)?.nonBlank }
        session.updatedAt = max(session.updatedAt, updated)
        // Activity, not polling, keeps a card alive.
        session.lastSeenAt = max(session.lastSeenAt ?? updated, updated)
        if live, let status = thread["status"] as? [String: Any] {
            applyStatus(status, to: &session, now: now)
        }
        return session
    }

    /// Applies a status reported by the service that owns the thread.
    static func applyStatus(_ status: [String: Any], to session: inout AgentSession, now: Date = Date()) {
        switch status["type"] as? String {
        case "active":
            let flags = status["activeFlags"] as? [String] ?? []
            if flags.contains("waitingOnApproval") { session.state = .needsAttention(message: String(localized: "Approval required")) }
            else if flags.contains("waitingOnUserInput") { session.state = .needsAttention(message: String(localized: "Waiting for your answer")) }
            else if !session.state.isWorking { session.state = .thinking }
            // Only an attached terminal makes a loaded thread active.
            session.isDisconnected = false
            session.finishedAt = nil
        case "idle":
            if session.state.isWorking || session.state.needsAttention {
                session.state = .finished
                session.finishedAt = now
            }
        case "systemError":
            session.state = .failed(message: String(localized: "Codex reported an error. Check the terminal."))
        case "notLoaded":
            // The service let go of the thread: no terminal is attached any more.
            session.isDisconnected = true
            session.canAcceptDirectInput = false
            if session.state.isWorking || session.state.needsAttention { session.state = .idle }
            session.finishedAt = nil
        default: break
        }
    }

    /// The conversation lines in a page of turns, oldest first.
    static func messages(turns: [[String: Any]]) -> [AgentMessage] {
        var seen = Set<String>()
        let lines = turns.flatMap { $0["items"] as? [[String: Any]] ?? [] }
            .compactMap(message(for:))
            .filter { seen.insert($0.id).inserted }
        return Array(lines.suffix(AgentSession.messageLimit))
    }

    /// One thread item as the terminal shows it, or nil for items it keeps to
    /// itself (reasoning, plans, hook prompts, raw tool output).
    static func message(for item: [String: Any]) -> AgentMessage? {
        guard let id = item["id"] as? String else { return nil }
        switch item["type"] as? String {
        case "userMessage":
            let text = (item["content"] as? [[String: Any]] ?? []).compactMap { part -> String? in
                switch part["type"] as? String {
                case "text": return part["text"] as? String
                case "image", "localImage": return String(localized: "[Image]")
                default: return nil
                }
            }.joined(separator: "\n\n")
            return text.nonBlank.map { AgentMessage(id: id, role: .user, text: $0) }
        case "agentMessage":
            return (item["text"] as? String)?.nonBlank.map { AgentMessage(id: id, role: .assistant, text: $0) }
        case "commandExecution":
            let (kind, detail) = commandActivity(item)
            return .activity(id: id, kind: kind, detail: detail)
        case "fileChange":
            let files = (item["changes"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }
                .map { URL(fileURLWithPath: $0).lastPathComponent }
            return files.isEmpty ? nil : .activity(id: id, kind: .edit, detail: files.joined(separator: ", "))
        case "webSearch":
            let action = item["action"] as? [String: Any]
            let detail = (item["query"] as? String)?.nonBlank ?? (action?["url"] as? String) ?? (action?["query"] as? String)
            return .activity(id: id, kind: .web, detail: detail ?? String(localized: "the web"))
        case "mcpToolCall":
            let name = [item["server"] as? String, item["tool"] as? String].compactMap { $0 }.joined(separator: ".")
            return name.nonBlank.map { .activity(id: id, kind: .other, detail: $0) }
        case "dynamicToolCall":
            return (item["tool"] as? String)?.nonBlank.map { .activity(id: id, kind: .other, detail: $0) }
        case "collabAgentToolCall":
            let prompt = (item["prompt"] as? String)?.nonBlank.map(firstLine)
            return .activity(id: id, kind: .delegate, detail: prompt ?? String(localized: "a subagent"))
        case "imageView":
            return (item["path"] as? String).map { .activity(id: id, kind: .read, detail: URL(fileURLWithPath: $0).lastPathComponent) }
        default:
            return nil
        }
    }

    /// Codex parses most shell calls into reads, searches and listings, as its
    /// terminal shows them; anything else is the command itself.
    private static func commandActivity(_ item: [String: Any]) -> (AgentToolKind, String) {
        let actions = item["commandActions"] as? [[String: Any]] ?? []
        let types = Set(actions.compactMap { $0["type"] as? String })
        if !actions.isEmpty, !types.contains("unknown") {
            if types == ["search"], let query = actions.compactMap({ $0["query"] as? String }).first {
                return (.search, query)
            }
            let names = actions.compactMap { ($0["name"] as? String) ?? ($0["path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } }
            if !names.isEmpty, types.isSubset(of: ["read", "listFiles"]) { return (.read, names.joined(separator: ", ")) }
        }
        return (.command, firstLine(unwrappedShellCommand(item["command"] as? String ?? "")))
    }

    /// `/bin/zsh -lc 'git status'` → `git status`, the way the terminal prints it.
    static func unwrappedShellCommand(_ command: String) -> String {
        let pattern = #"^(?:/[\w/]*/)?(?:ba|z)?sh -l?c '(.*)'$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)),
              let range = Range(match.range(at: 1), in: command) else { return command }
        return command[range].replacingOccurrences(of: #"'\''"#, with: "'")
    }

    private static func firstLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.count > 120 ? String(line.prefix(119)) + "…" : line
    }
}
