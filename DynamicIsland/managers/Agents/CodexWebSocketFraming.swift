import Foundation
import CryptoKit

/// The CLI's `app-server proxy` is a byte tunnel to a user-private Unix socket.
/// That socket carries RFC 6455, not JSONL. Bound frames before allocating and
/// mask every client frame; this adapter never opens a TCP listening port.
struct CodexWebSocketFraming {
    enum Event { case ready, text(Data), ping(Data), closed }
    private let key = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) }).base64EncodedString()
    private var buffer = Data()
    private var fragments = Data()
    private var fragmented = false
    private var upgraded = false
    static let maximumBytes = 8 * 1024 * 1024

    var handshake: Data {
        Data("GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: \(key)\r\nSec-WebSocket-Version: 13\r\n\r\n".utf8)
    }

    mutating func receive(_ data: Data) throws -> [Event] {
        buffer.append(data)
        var events: [Event] = []
        if !upgraded {
            guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                guard buffer.count <= 16_384 else { throw invalid() }; return []
            }
            let header = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
            let lines = header.components(separatedBy: "\r\n")
            let expected = Data(Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))).base64EncodedString()
            let accept = lines.dropFirst().first { $0.lowercased().hasPrefix("sec-websocket-accept:") }?
                .split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces)
            guard lines.first?.hasPrefix("HTTP/1.1 101 ") == true, accept == expected else { throw invalid() }
            buffer = Data(buffer[end.upperBound...])
            upgraded = true
            events.append(.ready)
        }
        while buffer.count >= 2 {
            let bytes = [UInt8](buffer.prefix(10))
            let final = bytes[0] & 0x80 != 0
            let opcode = bytes[0] & 0x0F
            guard bytes[0] & 0x70 == 0, bytes[1] & 0x80 == 0 else { throw invalid() }
            var size = UInt64(bytes[1] & 0x7F)
            var offset = 2
            if size == 126 {
                guard bytes.count >= 4 else { break }
                size = UInt64(bytes[2]) << 8 | UInt64(bytes[3]); offset = 4
            } else if size == 127 {
                guard bytes.count >= 10 else { break }
                size = bytes[2..<10].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }; offset = 10
            }
            guard size <= Self.maximumBytes else { throw invalid() }
            if opcode >= 8, (!final || size > 125) { throw invalid() }
            guard buffer.count >= offset + Int(size) else { break }
            let payload = buffer.subdata(in: offset..<(offset + Int(size)))
            buffer = Data(buffer.dropFirst(offset + Int(size)))
            switch opcode {
            case 1:
                guard !fragmented else { throw invalid() }
                if final { events.append(.text(payload)) }
                else { fragments = payload; fragmented = true }
            case 0:
                guard fragmented, fragments.count + payload.count <= Self.maximumBytes else { throw invalid() }
                fragments.append(payload)
                if final { events.append(.text(fragments)); fragments = Data(); fragmented = false }
            case 8: events.append(.closed)
            case 9: events.append(.ping(payload))
            case 10: break
            default: throw invalid()
            }
        }
        guard buffer.count <= Self.maximumBytes + 10 else { throw invalid() }
        return events
    }

    static func frame(_ body: Data, opcode: UInt8 = 1) throws -> Data {
        guard body.count <= maximumBytes else { throw AgentConnectionError.unavailable("Codex message is too large.") }
        var data = Data([0x80 | opcode])
        if body.count < 126 { data.append(0x80 | UInt8(body.count)) }
        else if body.count <= 65535 {
            data.append(0x80 | 126)
            var size = UInt16(body.count).bigEndian
            withUnsafeBytes(of: &size) { data.append(contentsOf: $0) }
        } else {
            data.append(0x80 | 127)
            var size = UInt64(body.count).bigEndian
            withUnsafeBytes(of: &size) { data.append(contentsOf: $0) }
        }
        let mask = (0..<4).map { _ in UInt8.random(in: .min ... .max) }
        data.append(contentsOf: mask)
        data.append(contentsOf: body.enumerated().map { $0.element ^ mask[$0.offset % 4] })
        return data
    }

    private func invalid() -> AgentConnectionError { .unavailable("The Codex terminal connection returned an invalid WebSocket frame.") }
}
