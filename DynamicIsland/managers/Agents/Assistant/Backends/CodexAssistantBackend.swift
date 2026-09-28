import Foundation

/// `codex exec`: the screenshot is attached with `-i`, the final message is
/// written to a file, and the run leaves no session behind. Hooks and plugins
/// stay off, so the run cannot start or notify other apps hooked into Codex.
struct CodexAssistantBackend: AssistantBackend {
    let sourceID = "codex"

    func arguments(prompt: String, imageURL: URL, workingDirectory: URL, answerFile: URL, model: String?) -> [String] {
        var arguments = [
            "exec", "-c", "features.hooks=false", "-c", "features.plugins=false",
            "--skip-git-repo-check", "--ephemeral", "--sandbox", "read-only",
            "--cd", workingDirectory.path, "--image", imageURL.path,
            "--output-last-message", answerFile.path,
        ]
        if let model { arguments += ["--model", model] }
        return arguments + [prompt]
    }

    func answer(stdout: Data, answerFile: URL) throws -> String {
        try String(contentsOf: answerFile, encoding: .utf8)
    }
}
