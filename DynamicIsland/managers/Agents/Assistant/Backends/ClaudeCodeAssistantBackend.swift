import Foundation

/// `claude -p`: reads the screenshot with its Read tool, the only tool it is allowed.
/// Every hook stays off, including plugins' hooks, so the run cannot start or
/// notify other apps hooked into Claude Code.
struct ClaudeCodeAssistantBackend: AssistantBackend {
    let sourceID = "claude"

    func arguments(prompt: String, imageURL: URL, workingDirectory: URL, answerFile: URL, model: String?) -> [String] {
        var arguments = ["-p", prompt, "--output-format", "json", "--allowedTools", "Read",
                         "--settings", #"{"disableAllHooks":true}"#]
        if let model { arguments += ["--model", model] }
        return arguments
    }

    func answer(stdout: Data, answerFile: URL) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: stdout) as? [String: Any],
              let result = json["result"] as? String else {
            throw AssistantError.failed(String(decoding: stdout.prefix(600), as: UTF8.self))
        }
        if json["is_error"] as? Bool == true { throw AssistantError.failed(result) }
        return result
    }
}
