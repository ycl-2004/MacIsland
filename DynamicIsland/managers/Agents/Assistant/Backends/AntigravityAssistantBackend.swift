import Foundation

/// `agy -p`: the working folder is added to its workspace so it may open the screenshot.
struct AntigravityAssistantBackend: AssistantBackend {
    let sourceID = "agy"

    func arguments(prompt: String, imageURL: URL, workingDirectory: URL, answerFile: URL, model: String?) -> [String] {
        // `-p` takes the next argument as the prompt, so every flag comes before it.
        var arguments = ["--add-dir", workingDirectory.path, "--output-format", "json", "--print-timeout", "170s"]
        if let model { arguments += ["--model", model] }
        return arguments + ["-p", prompt]
    }

    func answer(stdout: Data, answerFile: URL) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: stdout) as? [String: Any],
              let response = json["response"] as? String else {
            throw AssistantError.failed(String(decoding: stdout.prefix(600), as: UTF8.self))
        }
        return response
    }
}
