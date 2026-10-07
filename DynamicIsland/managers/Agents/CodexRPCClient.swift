import Foundation
import Darwin

enum AgentConnectionError: LocalizedError {
    case unavailable(String)
    case rejected(String)
    case uncertain

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .rejected(let message): return message
        case .uncertain:
            return String(localized: "Delivery could not be confirmed. Check the conversation in the terminal before sending another message.")
        }
    }
}

/// JSONL transport for the installed Codex app-server protocol. No shell, no
/// model invocation during discovery, and no retries of prompt-bearing requests.
/// Protocol: `codex app-server generate-json-schema --experimental` (0.157.0).
@MainActor
protocol CodexConversationClient: AnyObject {
    var onEvent: ((String, [String: Any]) -> Void)? { get set }
    var onRequest: ((Any, String, [String: Any]) -> Void)? { get set }
    var onDisconnect: (() -> Void)? { get set }
    var isReady: Bool { get }
    /// Connected to Codex's shared service rather than a private reader.
    var isSharedDaemon: Bool { get }
    /// The shared service is running and can be connected to.
    var sharedServiceAvailable: Bool { get }
    func start(executable: String) async throws
    func request(_ method: String, _ params: [String: Any], timeout: Double) async throws -> [String: Any]
    func reply(id: Any, result: [String: Any]) throws
    func close()
}

extension CodexConversationClient {
    func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        try await request(method, params, timeout: 12)
    }
}

@MainActor
final class CodexRPCClient: CodexConversationClient {
    var onEvent: ((String, [String: Any]) -> Void)?
    var onRequest: ((Any, String, [String: Any]) -> Void)?
    var onDisconnect: (() -> Void)?
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var timers: [Int: Task<Void, Never>] = [:]
    private var startup: Task<Void, Error>?
    private var generation = UUID()
    private(set) var isReady = false
    private(set) var isSharedDaemon = false
    private let preferSharedDaemon: Bool
    private var websocket = CodexWebSocketFraming()
    private var upgradeWaiter: CheckedContinuation<Void, Error>?

    init(preferSharedDaemon: Bool = true) { self.preferSharedDaemon = preferSharedDaemon }

    var sharedServiceAvailable: Bool { preferSharedDaemon && Self.sharedSocketPath() != nil }

    func start(executable: String) async throws {
        if isReady {
            if !isSharedDaemon && sharedServiceAvailable {
                // The terminal may have opened since our history-only reader.
                close()
            } else { return }
        }
        if let startup { return try await startup.value }
        let task = Task { @MainActor [self] in
            try launch(executable: executable)
            if isSharedDaemon {
                try await withCheckedThrowingContinuation { (waiter: CheckedContinuation<Void, Error>) in
                    upgradeWaiter = waiter
                    do { try input?.write(contentsOf: websocket.handshake) }
                    catch { upgradeWaiter = nil; waiter.resume(throwing: error) }
                    let epoch = generation
                    Task { [weak self] in
                        try? await Task.sleep(for: .seconds(3))
                        guard let self, self.generation == epoch, let waiter = self.upgradeWaiter else { return }
                        self.upgradeWaiter = nil
                        waiter.resume(throwing: AgentConnectionError.unavailable("Codex terminal connection timed out. Reopen Codex in your terminal."))
                    }
                }
            }
            _ = try await request("initialize", [
                "clientInfo": ["name": "atoll", "version": "1.0"],
                "capabilities": ["experimentalApi": true],
            ])
            try write(["method": "initialized", "params": [:]])
            isReady = true
        }
        startup = task
        do { try await task.value; startup = nil }
        catch { close(); throw error }
    }

    private func launch(executable: String) throws {
        let process = Process()
        let stdin = Pipe(), stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        let socketPath = preferSharedDaemon ? Self.sharedSocketPath() : nil
        isSharedDaemon = socketPath != nil
        websocket = CodexWebSocketFraming()
        process.arguments = socketPath.map { ["app-server", "proxy", "--sock", $0] } ?? ["app-server"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = [URL(fileURLWithPath: executable).deletingLastPathComponent().path,
                               "/opt/homebrew/bin", "/usr/local/bin", environment["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
        // Atoll projects lifecycle directly from the server that owns these turns.
        environment["ATOLL_SUPPRESS_HOOKS"] = "1"
        process.environment = environment
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        let epoch = UUID()
        generation = epoch
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async {
                guard let self, self.generation == epoch else { return }
                if data.isEmpty { self.close() } else { self.receive(data) }
            }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == epoch else { return }
                self.close()
            }
        }
        self.process = process
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        try process.run()
    }

    private static func sharedSocketPath() -> String? {
        let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        // Codex publishes a symlink to its per-daemon socket. Validate the
        // resolved target's type, ownership and permissions before connecting.
        let path = URL(fileURLWithPath: codexHome).appendingPathComponent("app-server-control/app-server-control.sock").resolvingSymlinksInPath().path
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFSOCK,
              info.st_uid == getuid(), (info.st_mode & 0o077) == 0 else { return nil }
        // The service records its first client as the originator of every
        // thread it creates. Give the terminal that started it time to connect
        // first, so its sessions stay attributed to the terminal.
        guard Date().timeIntervalSince1970 - TimeInterval(info.st_birthtimespec.tv_sec) >= 3 else { return nil }
        return path
    }

    func request(_ method: String, _ params: [String: Any], timeout: Double = 12) async throws -> [String: Any] {
        nextID += 1
        let id = nextID
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            timers[id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard !Task.isCancelled else { return }
                self?.finish(id, result: .failure(AgentConnectionError.unavailable(String(localized: "Codex did not respond in time."))))
            }
            do { try write(["id": id, "method": method, "params": params]) }
            catch { finish(id, result: .failure(error)) }
        }
    }

    func reply(id: Any, result: [String: Any]) throws { try write(["id": id, "result": result]) }

    private func write(_ value: [String: Any]) throws {
        guard let input, process?.isRunning == true else {
            throw AgentConnectionError.unavailable(String(localized: "Codex is disconnected."))
        }
        var data = try JSONSerialization.data(withJSONObject: value)
        if isSharedDaemon { data = try CodexWebSocketFraming.frame(data) }
        else { data.append(0x0A) }
        try input.write(contentsOf: data)
    }

    private func receive(_ data: Data) {
        if isSharedDaemon {
            do {
                for event in try websocket.receive(data) {
                    switch event {
                    case .ready:
                        let waiter = upgradeWaiter; upgradeWaiter = nil; waiter?.resume()
                    case .text(let data): receiveMessage(data)
                    case .ping(let data): try input?.write(contentsOf: CodexWebSocketFraming.frame(data, opcode: 10))
                    case .closed: close(); return
                    }
                }
            } catch { close() }
            return
        }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            guard buffer.distance(from: buffer.startIndex, to: newline) <= 8 * 1024 * 1024 else { close(); return }
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            receiveMessage(line)
        }
        if buffer.count > 8 * 1024 * 1024 { close() }
    }

    private func receiveMessage(_ data: Data) {
            guard let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
            if let method = message["method"] as? String {
                var params = message["params"] as? [String: Any] ?? [:]
                // Newer owners emit this before fan-out. Older servers omit it.
                // Source: app-server-protocol/src/protocol/common.rs, ServerNotificationEnvelope.
                if let emitted = message["emittedAtMs"] as? Double { params["_atollEmittedAtMs"] = emitted }
                if let id = message["id"] { onRequest?(id, method, params) }
                else { onEvent?(method, params) }
            } else if let id = message["id"] as? Int {
                if let error = message["error"] as? [String: Any] {
                    finish(id, result: .failure(AgentConnectionError.rejected(error["message"] as? String ?? "Codex rejected the request.")))
                } else if let result = message["result"] as? [String: Any] {
                    finish(id, result: .success(result))
                } else {
                    finish(id, result: .failure(AgentConnectionError.unavailable("Invalid Codex response.")))
                }
            }
    }

    private func finish(_ id: Int, result: Result<[String: Any], Error>) {
        timers.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(with: result)
    }

    func close() {
        let wasConnected = process != nil
        generation = UUID()
        isReady = false
        isSharedDaemon = false
        let waiter = upgradeWaiter; upgradeWaiter = nil
        waiter?.resume(throwing: AgentConnectionError.unavailable("Codex terminal connection closed."))
        startup?.cancel()
        startup = nil
        output?.readabilityHandler = nil
        try? input?.close()
        try? output?.close()
        input = nil; output = nil
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil
        buffer.removeAll()
        for id in Array(pending.keys) {
            finish(id, result: .failure(AgentConnectionError.unavailable("Codex disconnected.")))
        }
        if wasConnected { onDisconnect?() }
    }
}
