import Foundation

/// Every backend screen questions can go to. Adding one is a new `AssistantBackend` plus a line here.
enum AssistantBackendRegistry {
    static let all: [AssistantBackend] = [
        ClaudeCodeAssistantBackend(),
        CodexAssistantBackend(),
        AntigravityAssistantBackend(),
    ]

    static func backend(id: String) -> AssistantBackend? {
        all.first { $0.sourceID == id }
    }
}
