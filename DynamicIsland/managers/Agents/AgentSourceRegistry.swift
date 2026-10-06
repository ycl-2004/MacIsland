import Foundation

/// Every agent Atoll knows. Adding one is a new `AgentSource` type plus a line here.
enum AgentSourceRegistry {
    static let all: [AgentSource] = [
        ClaudeCodeAgentSource(),
        CodexAgentSource(),
        AntigravityAgentSource(),
        PiAgentSource(),
        OpenCodeAgentSource(),
        GrokAgentSource(),
    ]

    static func source(id: String) -> AgentSource? {
        all.first { $0.id == id }
    }
}

extension AgentSession {
    var source: AgentSource? { AgentSourceRegistry.source(id: sourceID) }
}
