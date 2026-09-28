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

        func send(_ body: Data?) {
            queue.async { [self] in
                guard !answered else { return }
                answered = true
                onClose = nil
                finish()
                AgentEventServer.respond(on: connection, status: body == nil ? "204 No Content" : "200 OK", body: body ?? Data())
            }
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

    private let queue = DispatchQueue(label: "Atoll.AgentEventServer")
    private let expectedAuthorization: Data
    private let onRequest: (Request, Reply) -> Void
    private var listener: NWListener?
    /// Requests not answered yet, on `queue`.
    private var waiting: [ObjectIdentifier: Reply] = [:]

    init(token: String, onRequest: @escaping (Request, Reply) -> Void) {
        self.expectedAuthorization = Data("Bearer \(token)".utf8)
        self.onRequest = onRequest
    }

    func start(onReady: @escaping (UInt16) -> Void, onFailure: @escaping (Error) -> Void) {
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
            onFailure(error)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        // Waiting hooks let their agents carry on without a message.
        queue.async { [self] in
            for reply in waiting.values { reply.send(nil) }
        }
    }

    private func accept(_ connection: NWConnection) {
        guard Self.isLoopback(connection.endpoint) else {
            connection.cancel()
            return
        }
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] chunk, _, isComplete, error in
            guard let self else { return connection.cancel() }
            var buffer = buffer
            if let chunk { buffer.append(chunk) }

            guard buffer.count <= Self.maxRequestBytes else {
                return self.respond(on: connection, status: "413 Payload Too Large")
            }
            switch Self.parse(buffer) {
            case .incomplete where error == nil && !isComplete:
                self.receive(on: connection, buffer: buffer)
            case .incomplete, .malformed:
                self.respond(on: connection, status: "400 Bad Request")
            case .complete(let request, let authorization):
                guard Self.constantTimeEquals(authorization, self.expectedAuthorization) else {
                    return self.respond(on: connection, status: "401 Unauthorized")
                }
                let reply = Reply(connection: connection, queue: self.queue)
                let key = ObjectIdentifier(reply)
                self.waiting[key] = reply
                reply.onFinish = { [weak self] in self?.waiting[key] = nil }
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
        guard length >= 0 else { return .malformed }
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
