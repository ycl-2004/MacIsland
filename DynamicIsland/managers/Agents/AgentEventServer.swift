import Foundation
import Network

/// The loopback HTTP endpoint the hook script posts to.
///
/// Hand-rolled because neither Foundation nor Network.framework ships an HTTP
/// server, and all it has to understand is one POST with a `Content-Length`
/// body per connection. It binds `127.0.0.1` on a port the system picks, and
/// every request must carry the bearer token only the hook script can read.
/// A request stays open until it is answered, which lets a hook wait for a
/// message typed in Atoll.
final class AgentEventServer {
    struct Request {
        let path: String
        let query: [String: String]
        let body: Data
    }

    /// Answers one request, once. `nil` means "nothing to say" (204); data is
    /// what the hook prints. All state lives on the server's queue.
    final class Reply: @unchecked Sendable {
        fileprivate let connection: NWConnection
        fileprivate let queue: DispatchQueue
        private var answered = false
        private var onClose: (@Sendable () -> Void)?
        fileprivate var onFinish: (() -> Void)?

        fileprivate init(connection: NWConnection, queue: DispatchQueue) {
            self.connection = connection
            self.queue = queue
        }

        func send(_ body: Data?) { queue.async { [self] in sendNow(body) } }

        fileprivate func sendNow(_ body: Data?) {
            guard !answered else { return }
            answered = true
            onClose = nil
            finish()
            AgentEventServer.respond(on: connection, status: body == nil ? "204 No Content" : "200 OK", body: body ?? Data())
        }

        private func finish() {
            onFinish?()
            onFinish = nil
        }

        /// Runs once if the hook hangs up before it was answered.
        func whenClosed(_ handler: @escaping @Sendable () -> Void) {
            queue.async { [self] in
                if answered { return }
                onClose = handler
            }
        }

        fileprivate func peerClosed() {
            guard !answered else { return }
            answered = true
            finish()
            connection.cancel()
            let handler = onClose
            onClose = nil
            handler?()
        }
    }

    /// Hook payloads can quote whole files (a `Write` tool call), but nothing
    /// Atoll reads is anywhere near this.
    private static let maxRequestBytes = 2 * 1024 * 1024
    private static let maxHeaderBytes = 16 * 1024
    private static let maxConnections = 32
    private static let maxBufferedBytes = 16 * 1024 * 1024
    private final class Incoming {
        let connection: NWConnection
        var buffer = Data()
        var chargedBytes = 0
        var deadline: DispatchWorkItem?
        init(_ connection: NWConnection) { self.connection = connection }
    }
    private var incoming: [ObjectIdentifier: Incoming] = [:]
    private var bufferedBytes = 0
    private var running = false

    private let queue = DispatchQueue(label: "Atoll.AgentEventServer")
    private let requestTimeout: TimeInterval
    private let expectedAuthorization: Data
    private let onRequest: (Request, Reply) -> Void
    private var listener: NWListener?
    /// Requests not answered yet, on `queue`.
    private var waiting: [ObjectIdentifier: Reply] = [:]

    init(token: String, requestTimeout: TimeInterval = 5, onRequest: @escaping (Request, Reply) -> Void) {
        self.requestTimeout = requestTimeout
        self.expectedAuthorization = Data("Bearer \(token)".utf8)
        self.onRequest = onRequest
    }

    func start(onReady: @escaping (UInt16) -> Void, onFailure: @escaping (Error) -> Void) {
        queue.async { [self] in startListener(onReady: onReady, onFailure: onFailure) }
    }

    private func startListener(onReady: @escaping (UInt16) -> Void, onFailure: @escaping (Error) -> Void) {
        guard !running else { return }
        running = true
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        do {
            let listener = try NWListener(using: params)
            listener.stateUpdateHandler = { [weak listener] state in
                switch state {
                case .ready:
                    if let port = listener?.port?.rawValue { onReady(port) }
                case .failed(let error):
                    onFailure(error)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            running = false
            onFailure(error)
        }
    }

    func stop() {
        queue.async { [self] in
            running = false
            listener?.cancel(); listener = nil
            for reply in Array(waiting.values) { reply.sendNow(nil) }
            for state in Array(incoming.values) { release(state.connection, cancel: true) }
        }
    }

    private func accept(_ connection: NWConnection) {
        guard running, Self.isLoopback(connection.endpoint), incoming.count < Self.maxConnections else {
            connection.cancel(); return
        }
        let state = Incoming(connection)
        incoming[ObjectIdentifier(connection)] = state
        connection.start(queue: queue)
        setDeadline(state, seconds: requestTimeout)
        receive(on: connection)
    }

    private func setDeadline(_ state: Incoming, seconds: TimeInterval, reply: Reply? = nil) {
        state.deadline?.cancel()
        let work = DispatchWorkItem { [weak self, weak state, weak reply] in
            guard let self, let state else { return }
            if let reply { reply.peerClosed() }
            self.release(state.connection, cancel: true)
        }
        state.deadline = work
        queue.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func release(_ connection: NWConnection, cancel: Bool) {
        if let state = incoming.removeValue(forKey: ObjectIdentifier(connection)) {
            state.deadline?.cancel()
            bufferedBytes -= state.chargedBytes
        }
        if cancel { connection.cancel() }
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] chunk, _, isComplete, error in
            guard let self, self.running, let state = self.incoming[ObjectIdentifier(connection)] else { return connection.cancel() }
            if let chunk {
                guard state.chargedBytes + chunk.count <= Self.maxRequestBytes,
                      self.bufferedBytes + chunk.count <= Self.maxBufferedBytes else {
                    return self.respond(on: connection, status: "413 Payload Too Large")
                }
                state.buffer.append(chunk)
                state.chargedBytes += chunk.count
                self.bufferedBytes += chunk.count
            }
            let delimiter = state.buffer.range(of: Data("\r\n\r\n".utf8))
            if (delimiter?.lowerBound ?? state.buffer.count) > Self.maxHeaderBytes {
                return self.respond(on: connection, status: "431 Request Header Fields Too Large")
            }
            switch Self.parse(state.buffer) {
            case .incomplete where error == nil && !isComplete:
                self.receive(on: connection)
            case .incomplete, .malformed:
                self.respond(on: connection, status: "400 Bad Request")
            case .complete(let request, let authorization):
                guard Self.constantTimeEquals(authorization, self.expectedAuthorization) else {
                    return self.respond(on: connection, status: "401 Unauthorized")
                }
                state.buffer.removeAll(keepingCapacity: false)
                let reply = Reply(connection: connection, queue: self.queue)
                let key = ObjectIdentifier(reply)
                self.waiting[key] = reply
                reply.onFinish = { [weak self] in
                    self?.waiting[key] = nil
                    self?.release(connection, cancel: false)
                }
                self.setDeadline(state, seconds: 8 * 60 * 60, reply: reply)
                self.watchForHangUp(connection, reply: reply)
                self.onRequest(request, reply)
            }
        }
    }

    /// A hook that stops waiting (its agent moved on, or it timed out) closes
    /// its end; the only thing left to read is that end-of-stream.
    private func watchForHangUp(_ connection: NWConnection, reply: Reply) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, isComplete, error in
            if isComplete || error != nil { reply.peerClosed() }
        }
    }

    private func respond(on connection: NWConnection, status: String) {
        release(connection, cancel: false)
        Self.respond(on: connection, status: status, body: Data())
    }

    fileprivate static func respond(on connection: NWConnection, status: String, body: Data) {
        var message = Data("HTTP/1.1 \(status)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        message.append(body)
        connection.send(content: message, completion: .contentProcessed { _ in connection.cancel() })
    }

    private enum ParseResult {
        case incomplete
        case malformed
        case complete(Request, authorization: Data)
    }

    private static func parse(_ buffer: Data) -> ParseResult {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return .incomplete }
        guard let head = String(data: buffer[..<headerEnd.lowerBound], encoding: .utf8) else { return .malformed }
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ")
        guard requestLine.count == 3, requestLine[0] == "POST",
              let components = URLComponents(string: "http://127.0.0.1" + requestLine[1]) else { return .malformed }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0, length <= Self.maxRequestBytes - headerEnd.upperBound else { return .malformed }
        let bodyStart = headerEnd.upperBound
        guard buffer.count - bodyStart >= length else { return .incomplete }

        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value ?? "" }
        let request = Request(
            path: components.path,
            query: query,
            body: buffer.subdata(in: bodyStart..<(bodyStart + length))
        )
        return .complete(request, authorization: Data((headers["authorization"] ?? "").utf8))
    }

    func resourceCounts() async -> (connections: Int, bufferedBytes: Int, waiting: Int) {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: (self.incoming.count, self.bufferedBytes, self.waiting.count)) }
        }
    }

    /// Only this Mac may post: the listener binds loopback, and this checks the peer too.
    static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address): return address.isLoopback
        // `::ffff:127.0.0.1` arrives on a dual-stack socket and is loopback.
        case .ipv6(let address): return address.asIPv4?.isLoopback ?? address.isLoopback
        case .name(let name, _): return name == "localhost" || name == "localhost."
        @unknown default: return false
        }
    }

    private static func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
