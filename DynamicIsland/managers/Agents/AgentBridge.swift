import Foundation

/// Where hook events go, and who answers a hook that waits for a message.
@MainActor
protocol AgentHookReceiver: AnyObject {
    /// Handles one event. Returned data is what the hook prints for its agent.
    func receive(_ event: AgentHookEvent) -> Data?
    /// A hook waiting for a message typed in Atoll. `reply` answers it once:
    /// with the message, or nil to let the agent carry on. `onClose` registers
    /// what to do if the hook stops waiting first.
    func park(_ event: AgentHookEvent, reply: @escaping (Data?) -> Void, onClose: (@escaping @Sendable () -> Void) -> Void)
}

/// Connects agent hooks to Atoll: writes the hook script and its credentials,
/// runs `AgentEventServer`, and turns each request into an `AgentHookEvent`.
///
/// Everything lives in one private folder. The script reads the current port
/// and auth header from it on every call, so hooks installed once keep working
/// across relaunches, and exit at once when Atoll is not running.
@MainActor
final class AgentBridge {
    static let shared = AgentBridge(receiver: AgentConversationService.shared)

    nonisolated static let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Atoll/AgentBridge", isDirectory: true)

    let directory: URL
    private weak var receiver: AgentHookReceiver?
    private var server: AgentEventServer?

    private var scriptPath: String { directory.appendingPathComponent("agent-hook.sh").path }
    private var portFile: URL { directory.appendingPathComponent("port") }
    private var authHeaderFile: URL { directory.appendingPathComponent("auth-header") }

    init(directory: URL = AgentBridge.defaultDirectory, receiver: AgentHookReceiver) {
        self.directory = directory
        self.receiver = receiver
    }

    var isRunning: Bool { server != nil }

    // MARK: Hooks

    /// Adds Atoll's hooks to the agent's config. The script they call is
    /// written first, so a hook never points at a file that is not there.
    func installHooks(for source: AgentSource) throws {
        try prepareDirectory()
        try source.installHooks(scriptPath: scriptPath)
    }

    func removeHooks(for source: AgentSource) throws {
        try source.removeHooks()
    }

    func hooksInstalled(for source: AgentSource) -> Bool {
        source.hooksInstalled(scriptPath: scriptPath)
    }

    func hooksOutdated(for source: AgentSource) -> Bool {
        source.hooksOutdated(scriptPath: scriptPath)
    }

    // MARK: Server

    func start() {
        guard server == nil else { return }
        do {
            try prepareDirectory()
            let token = Self.makeToken()
            // The token goes to curl as a header file so it never shows up in `ps`.
            try write("Authorization: Bearer \(token)\n", to: authHeaderFile)

            let server = AgentEventServer(token: token) { [weak self] request, reply in
                Task { @MainActor in
                    guard let self else { return reply.send(nil) }
                    self.route(request, reply: reply)
                }
            }
            server.start(
                onReady: { [weak self] port in
                    Task { @MainActor in
                        guard let self else { return }
                        try? self.write("\(port)", to: self.portFile)
                    }
                },
                onFailure: { error in
                    Task { @MainActor in Logger.log("Agent bridge failed: \(error.localizedDescription)", category: .agents) }
                }
            )
            self.server = server
        } catch {
            Logger.log("Agent bridge could not start: \(error.localizedDescription)", category: .agents)
        }
    }

    func stop() {
        server?.stop()
        server = nil
        // With no port file the hook script exits without trying to connect.
        try? FileManager.default.removeItem(at: portFile)
    }

    private func route(_ request: AgentEventServer.Request, reply: AgentEventServer.Reply) {
        guard let sourceID = request.query["source"], let source = AgentSourceRegistry.source(id: sourceID),
              let receiver else { return reply.send(nil) }
        let payload = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
        let host = request.query["host"].flatMap { $0.isEmpty ? nil : $0 }
        switch request.path {
        case "/v1/agent/event":
            guard let eventName = request.query["event"],
                  var event = source.makeEvent(eventName: eventName, payload: payload, hostBundleID: host) else { return reply.send(nil) }
            event.hostPane = request.query["pane"].flatMap(Self.pane)
            event.hostProcessID = request.query["pid"].flatMap { Int32($0) }
            reply.send(receiver.receive(event))
        case "/v1/agent/wait":
            // The waiting hook fires with the turn that just ended; only its
            // session matters here, the ending itself arrived as an event.
            guard case .wakeWhenIdle(let hookEvent, _) = source.replyDelivery,
                  let event = source.makeEvent(eventName: hookEvent, payload: payload, hostBundleID: host) else { return reply.send(nil) }
            receiver.park(event, reply: reply.send, onClose: reply.whenClosed)
        default:
            reply.send(nil)
        }
    }

    /// A pane id as terminals write them (UUIDs, refs); anything else is dropped.
    private static func pane(_ value: String) -> String? {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-")
        guard !value.isEmpty, value.count <= 128, value.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return value
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try writeScript()
    }

    private func writeScript() throws {
        // Terminals that name each pane in an environment variable, keyed by
        // their bundle identifier.
        let paneVariables = TerminalHostRegistry.hosts.compactMap { host -> String? in
            guard case .environment(let variable) = host.paneDiscovery else { return nil }
            return "  \(host.bundleIdentifier)) pane=\"${\(variable):-}\" ;;"
        }.joined(separator: "\n")
        let script = """
        #!/bin/sh
        # Installed by Atoll. Forwards agent hook events to Atoll's notch.
        # usage: agent-hook.sh <source> <event> [reply]   (hook payload JSON on stdin)
        #        agent-hook.sh <source> wait
        # An event never blocks or changes the agent: exit 0 within a second,
        # printing Atoll's answer when it has one (a message typed in Atoll for
        # the agent's next step), or else the neutral reply some agents require.
        # `wait` runs as an async hook while the agent waits for the user. It
        # exits 2 with a message typed in Atoll on stderr, which the agent takes
        # as its next turn, or 0 once the user answers in the terminal.
        dir='\(directory.path)'
        reply="${3:-}"
        finish() { [ -n "$reply" ] && printf '%s' "$reply"; exit 0; }
        # Atoll's own headless runs (screen questions) are not sessions to show.
        [ -n "${ATOLL_SUPPRESS_HOOKS:-}" ] && { cat >/dev/null; finish; }
        port=$(cat "$dir/port" 2>/dev/null) || { cat >/dev/null; finish; }
        url="http://127.0.0.1:$port/v1/agent"
        # Where the agent runs: the app hosting it, the pane when that app names
        # it in the environment, and this hook's parent, which leads to the
        # terminal device. Only the hosting app's own variable counts, since an
        # app started from a terminal inherits that terminal's variables.
        pane=
        case "${__CFBundleIdentifier:-}" in
        \(paneVariables)
        esac
        case "$pane" in *[!A-Za-z0-9._:-]*) pane= ;; esac
        origin="host=${__CFBundleIdentifier:-}&pane=$pane&pid=$PPID"
        if [ "$2" = wait ]; then
          # Only Claude Code's interactive terminal (not `claude -p`) has a user to wait for.
          { [ "${CLAUDE_CODE_ENTRYPOINT:-}" = cli ] && [ -z "${CLAUDE_CODE_SESSION_KIND:-}" ]; } || { cat >/dev/null; exit 0; }
          message=$(/usr/bin/curl -sf --connect-timeout 0.5 -m 28800 \\
            -H @"$dir/auth-header" -H 'Content-Type: application/json' --data-binary @- \\
            "$url/wait?source=$1&$origin" 2>/dev/null) || exit 0
          [ -n "$message" ] || exit 0
          printf '%s\\n' "$message" >&2
          exit 2
        fi
        answer=$(/usr/bin/curl -sf --connect-timeout 0.5 -m 1 \\
          -H @"$dir/auth-header" -H 'Content-Type: application/json' --data-binary @- \\
          "$url/event?source=$1&event=$2&$origin" 2>/dev/null)
        [ -n "$answer" ] && { printf '%s' "$answer"; exit 0; }
        finish

        """
        try write(script, to: URL(fileURLWithPath: scriptPath))
    }

    private func write(_ contents: String, to url: URL) throws {
        try Data(contents.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func makeToken() -> String {
        // `SystemRandomNumberGenerator` is a CSPRNG on Apple platforms.
        (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
    }
}
