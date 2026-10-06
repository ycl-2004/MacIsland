import Foundation
import SwiftUI

struct ClaudeCodeAgentSource: HookConfigAgentSource {
    let id = "claude"
    let displayName = "Claude Code"
    let symbolName = "asterisk"
    let accentColor = Color(red: 0.85, green: 0.47, blue: 0.34)
    let executableName = "claude"
    let hooksFileURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")

    // Only long-standing events: Claude Code rejects a settings file that
    // names an event it does not know.
    let hookEvents: [String: AgentEventPhase] = [
        "SessionStart": .sessionStarted,
        "UserPromptSubmit": .promptSubmitted,
        "PreToolUse": .toolStarted,
        "PostToolUse": .thinking,
        "Notification": .needsAttention,
        "Stop": .turnFinished,
        "SessionEnd": .sessionEnded,
    ]

    let toolKinds: [String: AgentToolKind] = [
        "Task": .delegate,
        "Agent": .delegate,
        "TodoWrite": .other,
        "ToolSearch": .other,
        "Skill": .other,
    ]

    var installNote: String? {
        String(localized: "Sessions that are already open pick this up after a restart.")
    }

    /// Claude Code has no input channel of its own. An async Stop hook waits
    /// while Claude waits for the user; exiting with code 2 hands its stderr to
    /// the same session as the next turn. It never blocks Claude or the terminal.
    var replyDelivery: AgentReplyDelivery? {
        .wakeWhenIdle(hookEvent: "Stop", options: ["asyncRewake": true, "timeout": 8 * 60 * 60])
    }

    func phase(forEvent event: String, payload: [String: Any]) -> AgentEventPhase? {
        // `Notification` also fires when a finished turn has sat unanswered for
        // a minute; that is not something to flag in the notch.
        if event == "Notification", (payload["notification_type"] as? String) == "idle_prompt" {
            return nil
        }
        return hookEvents[event]
    }

    /// User turns, Claude's text and one line per tool call. Thinking, tool
    /// results, subagent (sidechain) rows and Claude's own markup are skipped.
    func transcript(from rows: [[String: Any]]) -> AgentTranscript? {
        var messages: [AgentMessage] = []
        var title: String?
        for row in rows {
            if row["type"] as? String == "ai-title" { title = (row["aiTitle"] as? String)?.nonBlank ?? title }
            guard row["isSidechain"] as? Bool != true, row["isMeta"] as? Bool != true,
                  let uuid = row["uuid"] as? String,
                  let content = (row["message"] as? [String: Any])?["content"] else { continue }
            let blocks = content as? [[String: Any]] ?? (content as? String).map { [["type": "text", "text": $0]] } ?? []
            switch row["type"] as? String {
            case "user":
                // Tool results come back as user rows; they are not something the user typed.
                let text = blocks.compactMap { block -> String? in
                    switch block["type"] as? String {
                    case "text": return block["text"] as? String
                    case "image": return String(localized: "[Image]")
                    default: return nil
                    }
                }.joined(separator: "\n\n")
                guard let visible = AtollMessageEnvelope.visibleUserText(text) else { continue }
                messages.append(AgentMessage(id: uuid, role: .user, text: visible))
            case "assistant":
                for (index, block) in blocks.enumerated() {
                    switch block["type"] as? String {
                    case "text":
                        if let text = (block["text"] as? String)?.nonBlank {
                            messages.append(AgentMessage(id: "\(uuid)-\(index)", role: .assistant, text: text))
                        }
                    case "tool_use":
                        guard let name = block["name"] as? String else { continue }
                        let detail = (block["input"] as? [String: Any]).flatMap(Self.toolDetail(from:)) ?? name
                        messages.append(.activity(id: block["id"] as? String ?? "\(uuid)-\(index)", kind: toolKind(for: name), detail: detail))
                    default: continue
                    }
                }
            default: continue
            }
        }
        return AgentTranscript(messages: Array(messages.suffix(AgentSession.messageLimit)), title: title)
    }
}
