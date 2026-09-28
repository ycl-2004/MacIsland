import Foundation

/// Answers one question about a screenshot by running an agent's CLI headless
/// (`claude -p`, `codex exec`, `agy -p`), so it uses the account the CLI is
/// already signed in to instead of an API key.
///
/// A backend only says how to call its CLI and where the answer comes back.
/// Starting the process, the working folder, the timeout and cancellation are
/// shared in the extension below.
protocol AssistantBackend {
    /// The `AgentSource` this backend runs; its name, icon and executable are reused.
    var sourceID: String { get }
    /// Arguments for one question. The screenshot is `imageURL`, inside `workingDirectory`.
    func arguments(prompt: String, imageURL: URL, workingDirectory: URL, answerFile: URL, model: String?) -> [String]
    /// The answer, read from stdout or from `answerFile`.
    func answer(stdout: Data, answerFile: URL) throws -> String
}

enum AssistantError: LocalizedError {
    case cliNotFound(String)
    case failed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .cliNotFound(let name): return String(localized: "\(name) is not installed on this Mac.")
        case .failed(let message): return message
        case .timedOut: return String(localized: "No answer after three minutes.")
        }
    }
}

extension AssistantBackend {
    var source: AgentSource? { AgentSourceRegistry.source(id: sourceID) }

    static var timeout: TimeInterval { 180 }

    /// The instruction every backend receives, so answers read the same whichever one is used.
    static func prompt(for question: String, imagePath: String) -> String {
        """
        The user took a screenshot of part of their screen; it is the image file \(imagePath). \
        Look at it and answer their question about it. Be concise, and answer in the language \
        the question is written in. Do not modify any files.

        Question: \(question)
        """
    }

    func ask(_ question: String, about screenshot: URL, model: String?) async throws -> String {
        guard let source, let executable = AgentExecutableLocator.path(for: source.executableName) else {
            throw AssistantError.cliNotFound(source?.displayName ?? sourceID)
        }
        let workingDirectory = AtollTemporaryFiles.directory(.screenQuestion)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let imageURL = workingDirectory.appendingPathComponent("capture.png")
        try FileManager.default.copyItem(at: screenshot, to: imageURL)
        let answerFile = workingDirectory.appendingPathComponent("answer.txt")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments(
            prompt: Self.prompt(for: question, imagePath: imageURL.path),
            imageURL: imageURL,
            workingDirectory: workingDirectory,
            answerFile: answerFile,
            model: model?.isEmpty == false ? model : nil
        )
        process.currentDirectoryURL = workingDirectory
        process.environment = Self.environment(addingToPathOf: executable)
        process.standardInput = FileHandle.nullDevice
        // Files rather than pipes: a CLI can leave a helper running that holds
        // on to its stdout, and a pipe read would then never finish.
        let stdoutURL = workingDirectory.appendingPathComponent("stdout.txt")
        let stderrURL = workingDirectory.appendingPathComponent("stderr.txt")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        process.standardOutput = try FileHandle(forWritingTo: stdoutURL)
        process.standardError = try FileHandle(forWritingTo: stderrURL)

        guard case .exited(let status) = try await ProcessRunner.run(process, timeout: Self.timeout) else {
            throw AssistantError.timedOut
        }
        let output = (try? Data(contentsOf: stdoutURL)) ?? Data()
        let errors = (try? Data(contentsOf: stderrURL)) ?? Data()
        guard status == 0 else {
            let message = String(decoding: errors.suffix(600), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw AssistantError.failed(message.isEmpty ? String(localized: "\(source.displayName) exited with status \(status).") : message)
        }
        let text = try answer(stdout: output, answerFile: answerFile).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AssistantError.failed(String(localized: "\(source.displayName) returned an empty answer.")) }
        return text
    }

    /// A GUI app's `PATH` is minimal; the CLIs are often Node scripts that need
    /// `node` next to them. `ATOLL_SUPPRESS_HOOKS` keeps this run out of the Agents tab
    /// for agents whose hooks cannot be switched off per run (Antigravity).
    private static func environment(addingToPathOf executable: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let extra = [URL(fileURLWithPath: executable).deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin"]
        environment["PATH"] = (extra + [environment["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        environment["ATOLL_SUPPRESS_HOOKS"] = "1"
        return environment
    }
}
