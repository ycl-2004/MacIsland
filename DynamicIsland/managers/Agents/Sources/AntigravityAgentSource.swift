import Foundation
import SwiftUI

struct AntigravityAgentSource: HookConfigAgentSource {
    let id = "agy"
    let displayName = "Antigravity"
    let symbolName = "atom"
    let accentColor = Color(red: 0.26, green: 0.52, blue: 0.96)
    let executableName = "agy"
    /// Shared by the `agy` CLI and the Antigravity apps.
    let hooksFileURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/config/hooks.json")
    let hookFormat: AgentHookConfigFormat = NamedHookFormat(name: "atoll", toolEvents: ["PostToolUse"])
    /// Antigravity parses every hook's stdout as JSON; `{}` means "no opinion"
    /// on each event installed here.
    let hookReply: String? = "{}"

    // Antigravity has no prompt, session or notification events: a new model
    // invocation marks the start of work, and quiet sessions age out.
    // No `PreToolUse`: Antigravity requires a permission decision there and
    // denies the call on `{}`, and the hooks file is global, so any reply would
    // gate every Antigravity session. Tool calls show in the transcript instead.
    let hookEvents: [String: AgentEventPhase] = [
        "PreInvocation": .thinking,
        "PostToolUse": .thinking,
        "Stop": .turnFinished,
    ]

    let toolKinds: [String: AgentToolKind] = [
        "run_command": .command,
        "view_file": .read,
        "list_dir": .read,
        "find_by_name": .search,
        "grep_search": .search,
        "write_to_file": .edit,
        "replace_file_content": .edit,
        "multi_replace_file_content": .edit,
        "read_url_content": .web,
        "search_web": .web,
        "browser_subagent": .web,
        "manage_subagents": .delegate,
    ]

    func phase(forEvent event: String, payload: [String: Any]) -> AgentEventPhase? {
        if event == "Stop", (payload["terminationReason"] as? String) == "error" {
            return .turnFailed
        }
        return hookEvents[event]
    }

    /// Antigravity's hooks all run in line with its loop and it has no prompt
    /// hook, so nothing can wait for the user without freezing it. While it
    /// works, the next step takes the message instead.
    var replyDelivery: AgentReplyDelivery? { .injectWhileWorking }

    /// `PreInvocation` injects a real user step before the next model call.
    /// A turn that ends first keeps going with the message (`Stop`'s
    /// `continue`, where it arrives as a system message).
    func replyOutput(_ message: String, atEvent event: String) -> Data? {
        let reply: [String: Any]
        switch event {
        case "PreInvocation": reply = ["injectSteps": [["userMessage": message]]]
        case "Stop": reply = ["decision": "continue", "reason": AtollMessageEnvelope.wrap(id: UUID().uuidString, text: message)]
        default: return nil
        }
        return try? JSONSerialization.data(withJSONObject: reply)
    }

    /// Steps of `transcript.jsonl`: user requests, planner text and tool calls.
    /// Tool results (`GENERIC`) and thinking are skipped.
    func transcript(from rows: [[String: Any]]) -> AgentTranscript? {
        var messages: [AgentMessage] = []
        for row in rows {
            let id = "\(row["step_index"] ?? messages.count)"
            switch row["type"] as? String {
            case "USER_INPUT":
                guard let text = (row["content"] as? String).map(Self.userRequest)?.nonBlank else { continue }
                messages.append(AgentMessage(id: id, role: .user, text: text))
            case "PLANNER_RESPONSE":
                if let text = (row["content"] as? String)?.nonBlank {
                    messages.append(AgentMessage(id: id, role: .assistant, text: text))
                }
                for (index, call) in (row["tool_calls"] as? [[String: Any]] ?? []).enumerated() {
                    guard let name = call["name"] as? String else { continue }
                    // Argument values arrive JSON-encoded ("\"npm test\"").
                    let args = (call["args"] as? [String: Any] ?? [:]).mapValues { value -> Any in
                        guard let text = value as? String, let data = text.data(using: .utf8),
                              let decoded = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else { return value }
                        return decoded
                    }
                    messages.append(.activity(id: "\(id)-\(index)", kind: toolKind(for: name), detail: Self.toolDetail(from: args) ?? name))
                }
            default: continue
            }
        }
        return AgentTranscript(messages: Array(messages.suffix(AgentSession.messageLimit)))
    }

    /// The text inside `<USER_REQUEST>`, without the metadata Antigravity appends.
    private static func userRequest(_ content: String) -> String {
        guard let start = content.range(of: "<USER_REQUEST>"),
              let end = content.range(of: "</USER_REQUEST>", range: start.upperBound..<content.endIndex) else { return content }
        return String(content[start.upperBound..<end.lowerBound])
    }
}
