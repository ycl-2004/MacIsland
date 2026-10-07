import SwiftUI

/// How a tool call reads, shared by the live state and the conversation's
/// one-line activity rows.
extension AgentToolKind {
    var symbolName: String {
        switch self {
        case .command: return "terminal"
        case .edit: return "pencil"
        case .read: return "doc.text"
        case .search: return "magnifyingglass"
        case .web: return "globe"
        case .delegate: return "person.2"
        case .other: return "wrench.and.screwdriver"
        }
    }

    /// The verb for a tool call in the conversation: "Ran git status".
    var activityVerb: String {
        switch self {
        case .command: return String(localized: "Ran")
        case .edit: return String(localized: "Edited")
        case .read: return String(localized: "Read")
        case .search: return String(localized: "Searched")
        case .web: return String(localized: "Browsed")
        case .delegate: return String(localized: "Delegated")
        case .other: return String(localized: "Used")
        }
    }
}

/// How each agent state reads in the notch, defined once for the tab and the
/// closed-notch activity alike.
extension AgentState {
    var title: String {
        switch self {
        case .idle: return String(localized: "Waiting for you")
        case .thinking: return String(localized: "Thinking…")
        case .tool(let kind, let name, _):
            switch kind {
            case .command: return String(localized: "Processing a command")
            case .edit: return String(localized: "Editing files")
            case .read: return String(localized: "Reading files")
            case .search: return String(localized: "Searching the code")
            case .web: return String(localized: "Browsing the web")
            case .delegate: return String(localized: "Working with a subagent")
            case .other: return name.isEmpty ? String(localized: "Using a tool") : String(localized: "Using \(name)")
            }
        case .needsAttention: return String(localized: "Needs you")
        case .finished: return String(localized: "This turn finished")
        case .failed: return String(localized: "Stopped with an error")
        }
    }

    var symbolName: String {
        switch self {
        case .idle: return "pause.circle"
        case .thinking: return "ellipsis.circle"
        case .tool(let kind, _, _): return kind.symbolName
        case .needsAttention: return "exclamationmark.circle.fill"
        case .finished: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .needsAttention: return .statusAttention
        case .finished: return .statusSuccess
        case .failed: return .statusDanger
        // Not `.secondary`: the closed notch is not dark-schemed, where that
        // resolves near-black.
        case .idle: return .inkTertiary
        case .thinking, .tool: return .inkPrimary
        }
    }

    /// A second line under the title: the command or file for a tool call, or
    /// the message the agent is waiting on.
    var detail: String? {
        switch self {
        case .tool(_, _, let detail): return detail
        case .needsAttention(let message), .failed(let message): return message
        default: return nil
        }
    }
}

extension AgentSession {
    var statusTitle: String {
        if isDisconnected { return String(localized: "Session ended") }
        if statusUncertain == true { return String(localized: "Status cannot be confirmed") }
        if wasCancelled == true { return String(localized: "Stopped") }
        return state.title
    }
    var statusSymbol: String {
        isDisconnected ? "bolt.slash" : statusUncertain == true ? "questionmark.circle" : wasCancelled == true ? "stop.circle" : state.symbolName
    }
    var statusTint: Color {
        isDisconnected || statusUncertain == true || wasCancelled == true ? .inkTertiary : state.tint
    }

    /// The project folder, or the agent's name when it did not report one.
    var displayTitle: String {
        title ?? projectName ?? source?.displayName ?? sourceID
    }
}
