import Foundation
import SwiftUI

struct GrokAgentSource: HookConfigAgentSource {
    let id = "grok"
    let displayName = "Grok Build"
    let symbolName = "circle.slash"
    let accentColor = Color(white: 0.82)
    let executableName = "grok"
    /// Grok merges every file in `~/.grok/hooks/`, so Atoll keeps its hooks in
    /// a file of its own and never touches the user's.
    let hooksFileURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/hooks/atoll.json")
    /// Grok also runs the hooks in `~/.claude/settings.json`, Atoll's Claude
    /// Code hooks among them, with this set.
    let hookEnvironmentVariable: String? = "GROK_HOOK_EVENT"

    // Grok fails open on every hook and blocks only on an explicit decision, so
    // the empty reply Atoll's hooks give lets every prompt, tool call and stop
    // through unchanged.
    let hookEvents: [String: AgentEventPhase] = [
        "SessionStart": .sessionStarted,
        "UserPromptSubmit": .promptSubmitted,
        "PreToolUse": .toolStarted,
        "PostToolUse": .thinking,
        "Notification": .needsAttention,
        "Stop": .turnFinished,
        "StopFailure": .turnFailed,
        // Runs instead of `Stop` after Ctrl+C or a declined permission.
        "StopCancelled": .turnFinished,
        "SessionEnd": .sessionEnded,
    ]

    let toolKinds: [String: AgentToolKind] = [
        "monitor": .command,
        "todo_write": .other,
        "use_tool": .other,
        "search_tool": .other,
        "ask_user_question": .other,
        "kill_command_or_subagent": .other,
        "get_command_or_subagent_output": .other,
    ]

    var installNote: String? {
        String(localized: "Sessions that are already open pick this up after a restart.")
    }

    func phase(forEvent event: String, payload: [String: Any]) -> AgentEventPhase? {
        // A subagent's own events are part of its parent's card.
        if payload["subagentType"] != nil { return nil }
        switch event {
        case "Notification":
            // `idle_prompt` and `task_complete` report a turn that already ended.
            let type = (payload["notificationType"] ?? payload["notification_type"]) as? String
            if type == "idle_prompt" || type == "task_complete" { return nil }
        case "Stop":
            // Grok also fires `Stop` as the session closes; `SessionEnd` follows.
            if let reason = payload["reason"] as? String, reason != "end_turn" { return nil }
        default:
            break
        }
        return hookEvents[event]
    }
}
