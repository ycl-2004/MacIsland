import AppKit

enum TerminalError: LocalizedError {
    case paneUnknown(String)
    case notRunning(String)
    case agentGone(String)
    case refused(String, hint: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .paneUnknown(let terminal):
            return String(localized: "Atoll has not found this session's \(terminal) tab yet.")
        case .notRunning(let terminal):
            return String(localized: "\(terminal) is not running, so nothing was typed.")
        case .agentGone(let terminal):
            return String(localized: "The agent no longer runs in its \(terminal) tab, so nothing was typed there.")
        case .refused(let terminal, let hint, let detail):
            return String(localized: "\(terminal) did not accept Atoll's command (\(detail)). \(hint)")
        }
    }
}

/// What Atoll needs from the system to act on terminals. Tests supply their own.
struct TerminalSystem {
    /// Runs one command against the app with this bundle identifier and returns what it printed.
    var run: (TerminalCommand, _ bundleIdentifier: String) async throws -> String
    var isRunning: (_ bundleIdentifier: String) -> Bool
    var activate: (_ bundleIdentifier: String) -> Bool
    var device: (_ processID: Int32) -> String?
    var agentHoldsForeground: (_ device: String) -> Bool

    static let live = TerminalSystem(
        run: TerminalCommandRunner.run,
        isRunning: { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty },
        activate: { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first?.activate() ?? false },
        device: ControllingTerminal.device(ofProcess:),
        agentHoldsForeground: ControllingTerminal.agentHoldsForeground(device:)
    )
}

struct TerminalCommandFailure: LocalizedError {
    let errorDescription: String?
}

enum TerminalCommandRunner {
    static let timeout: TimeInterval = 10

    static func run(_ command: TerminalCommand, in bundleIdentifier: String) async throws -> String {
        let textFile = try command.text.map(writeTextFile)
        defer { if let textFile { try? FileManager.default.removeItem(at: textFile) } }
        let process = Process()
        switch command.program {
        case .appleScript(let source):
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            // `--` ends osascript's options, so every argument reaches the script as text.
            process.arguments = ["-e", source, "--"] + command.arguments + (textFile.map { [$0.path] } ?? [])
        case .bundledTool(let path):
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                throw TerminalCommandFailure(errorDescription: String(localized: "the app is not installed"))
            }
            let tool = app.appendingPathComponent(path).path
            if let textFile {
                // The shell reads the text and hands its bytes to the tool unchanged.
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", #"f=$1; shift; exec "$@" "$(cat "$f")""#, "sh", textFile.path, tool] + command.arguments
            } else {
                process.executableURL = URL(fileURLWithPath: tool)
                process.arguments = command.arguments
            }
        }
        let output = Pipe(), errors = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors
        // Both commands print a line or two, well within a pipe's buffer.
        guard case .exited(let status) = try await ProcessRunner.run(process, timeout: timeout) else {
            throw TerminalCommandFailure(errorDescription: String(localized: "no answer in \(Int(timeout)) seconds"))
        }
        guard status == 0 else {
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw TerminalCommandFailure(errorDescription: message.nonBlank.map { String($0.suffix(300)) } ?? String(localized: "exit status \(status)"))
        }
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    /// A file only this user can read, removed once the command ran.
    private static func writeTextFile(_ text: String) throws -> URL {
        let file = AtollTemporaryFiles.directory(.terminalText).appendingPathComponent(UUID().uuidString)
        guard FileManager.default.createFile(atPath: file.path, contents: Data(text.utf8), attributes: [.posixPermissions: 0o600]) else {
            throw TerminalCommandFailure(errorDescription: String(localized: "could not stage the message"))
        }
        return file
    }
}

/// Finds the terminal pane each agent session runs in, brings it back to the
/// front, and types into it: the same keystrokes as the user typing there.
@MainActor
final class AgentTerminals {
    static let shared = AgentTerminals()

    enum FocusResult: Equatable {
        /// The session's own pane is in front.
        case pane
        /// Only the terminal app came forward; the pane was unknown or refused (the reason).
        case app(String?)
        /// The terminal is unknown or not running.
        case unavailable
    }

    private let system: TerminalSystem
    /// What Atoll typed into each session, until the agent reports it as a
    /// prompt. That report came from Atoll, not from the user acting in the
    /// pane, so it says nothing about which pane is focused.
    private var typedPrompts: [String: String] = [:]

    init(system: TerminalSystem = .live) {
        self.system = system
    }

    func host(for session: AgentSession) -> TerminalHost? {
        TerminalHostRegistry.host(bundleIdentifier: session.hostBundleID)
    }

    /// Notes where the event's session runs, once the store has applied it.
    func track(_ event: AgentHookEvent, in store: AgentSessionStore) {
        let id = AgentSession.key(sourceID: event.sourceID, sessionKey: event.sessionKey)
        // Only a hook run inside a terminal tells where the session is. One run
        // by a background service (Codex's shared service) has no terminal, and
        // its environment belongs to whichever terminal started that service.
        guard var session = store.session(id: id), let host = host(for: session),
              let device = event.hostProcessID.flatMap(system.device) else { return }
        let before = session
        let typedByAtoll = event.phase == .promptSubmitted && consumeTypedPrompt(id, reported: event.prompt)
        if session.terminalDevice != device {
            // A new process, so whatever pane was known belongs to the old one.
            session.terminalDevice = device
            session.terminalPane = nil
        }
        switch host.paneDiscovery {
        case .environment:
            if let pane = event.hostPane { session.terminalPane = pane }
        case .controllingTerminal:
            session.terminalPane = device
        case .focusedPane(let query):
            // The user just typed here, or started the session here.
            let userActedHere = event.phase == .promptSubmitted
                ? !typedByAtoll
                : event.phase == .sessionStarted && session.terminalPane == nil
            if userActedHere, let cwd = event.cwd {
                Task { await bindFocusedPane(id, query: query, host: host, cwd: cwd, device: device, store: store) }
            }
        }
        if session != before { store.upsert(session) }
    }

    func canType(into session: AgentSession) -> Bool {
        guard !session.isDisconnected, let host = host(for: session),
              session.terminalPane != nil, session.terminalDevice != nil else { return false }
        return system.isRunning(host.bundleIdentifier)
    }

    /// Types `text` into the session's pane and submits it. Refuses when the
    /// agent no longer holds the terminal, where the text would run as a command.
    func type(_ text: String, into session: AgentSession) async throws {
        guard let host = host(for: session) else { throw TerminalError.paneUnknown(String(localized: "terminal")) }
        guard let pane = session.terminalPane, let device = session.terminalDevice else { throw TerminalError.paneUnknown(host.displayName) }
        guard system.isRunning(host.bundleIdentifier) else { throw TerminalError.notRunning(host.displayName) }
        guard system.agentHoldsForeground(device) else { throw TerminalError.agentGone(host.displayName) }
        guard TerminalText.printable(text).nonBlank != nil else { return }
        typedPrompts[session.id] = text
        do {
            for command in host.typeCommands(text: text, pane: pane) {
                _ = try await system.run(command, host.bundleIdentifier)
            }
        } catch {
            typedPrompts[session.id] = nil
            throw TerminalError.refused(host.displayName, hint: host.permissionHint, detail: error.localizedDescription)
        }
    }

    /// Brings the session's terminal to the front, at its own pane when known.
    func focus(_ session: AgentSession) async -> FocusResult {
        guard let bundleIdentifier = session.hostBundleID, system.isRunning(bundleIdentifier) else { return .unavailable }
        // The app first: in the background a terminal may defer reordering its windows.
        let activated = system.activate(bundleIdentifier)
        guard let host = host(for: session), let pane = session.terminalPane else {
            return activated ? .app(nil) : .unavailable
        }
        do {
            for command in host.focusCommands(pane: pane) {
                _ = try await system.run(command, bundleIdentifier)
            }
            return .pane
        } catch {
            let problem = TerminalError.refused(host.displayName, hint: host.permissionHint, detail: error.localizedDescription)
            return activated ? .app(problem.localizedDescription) : .unavailable
        }
    }

    private func consumeTypedPrompt(_ id: String, reported prompt: String?) -> Bool {
        guard let typed = typedPrompts[id], typed.nonBlank == prompt?.nonBlank else { return false }
        typedPrompts[id] = nil
        return true
    }

    /// Asks the terminal for its focused pane and takes it when its working
    /// directory is the session's; otherwise the user is somewhere else.
    private func bindFocusedPane(_ id: String, query: TerminalCommand, host: TerminalHost,
                                 cwd: String, device: String, store: AgentSessionStore) async {
        guard let output = try? await system.run(query, host.bundleIdentifier) else { return }
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 2, let pane = lines[0].nonBlank, let directory = lines[1].nonBlank,
              Self.sameDirectory(directory, cwd),
              var session = store.session(id: id), session.terminalDevice == device,
              session.terminalPane != pane else { return }
        session.terminalPane = pane
        store.upsert(session)
    }

    static func sameDirectory(_ first: String, _ second: String) -> Bool {
        func canonical(_ path: String) -> String {
            URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        }
        return canonical(first) == canonical(second)
    }
}
