import Foundation
import SwiftUI

struct CodexAgentSource: HookConfigAgentSource {
    let id = "codex"
    let displayName = "Codex"
    let symbolName = "chevron.left.forwardslash.chevron.right"
    let accentColor = Color(red: 0.55, green: 0.62, blue: 1.0)
    let executableName = "codex"
    let hooksFileURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/hooks.json")

    // Codex has no `Notification` event; an approval it is waiting on arrives
    // as `PermissionRequest`, which Atoll only reports and never answers.
    var extendedLifecycle = false
    var hookEvents: [String: AgentEventPhase] {
        var events: [String: AgentEventPhase] = [
        "SessionStart": .sessionStarted,
        "UserPromptSubmit": .promptSubmitted,
        "PreToolUse": .toolStarted,
        "PermissionRequest": .needsAttention,
        "Stop": .turnFinished,
        "SessionEnd": .sessionEnded,
        ]
        if extendedLifecycle { events.merge(["PostToolUse": .thinking, "Interrupt": .turnCancelled]) { _, new in new } }
        return events
    }

    func phase(forEvent event: String, payload: [String: Any]) -> AgentEventPhase? {
        if event == "PostToolUse" { return .thinking }
        if event == "Interrupt" { return .turnCancelled }
        return hookEvents[event]
    }

    let toolKinds: [String: AgentToolKind] = [
        "view_image": .read,
        "update_plan": .other,
    ]

    /// A terminal on Codex's shared service takes messages directly.
    var replyDelivery: AgentReplyDelivery? { .sharedService }

    var installNote: String? {
        String(localized: "Codex runs a new hook only after you trust it: open Codex and approve Atoll's hooks when asked.")
    }
}
