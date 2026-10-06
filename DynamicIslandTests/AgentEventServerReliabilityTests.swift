import Foundation
import Network
import XCTest
@testable import Atoll

final class AgentEventServerReliabilityTests: XCTestCase {
    private func start(_ server: AgentEventServer) async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            server.start(onReady: { continuation.resume(returning: $0) }, onFailure: { continuation.resume(throwing: $0) })
        }
    }
    func testAuthenticatedRequestAndStopReleaseAllConnectionState() async throws {
        let server = AgentEventServer(token: "fixture") { _, reply in reply.send(Data("ok".utf8)) }
        let port = try await start(server)
        defer { server.stop() }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/test")!)
        request.httpMethod = "POST"
        request.setValue("Bearer fixture", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("payload".utf8)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(data, Data("ok".utf8))
        server.stop()
        let counts = await server.resourceCounts()
        XCTAssertEqual(counts.connections, 0)
        XCTAssertEqual(counts.bufferedBytes, 0)
        XCTAssertEqual(counts.waiting, 0)
    }

    func testShutdownAnswersAnAuthenticatedParkedRequest() async throws {
        let received = expectation(description: "Authenticated reply is parked")
        let server = AgentEventServer(token: "fixture") { _, _ in received.fulfill() }
        let port = try await start(server)
        defer { server.stop() }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/wait")!)
        request.httpMethod = "POST"
        request.setValue("Bearer fixture", forHTTPHeaderField: "Authorization")
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let waiting = Task { try await session.data(for: request) }
        await fulfillment(of: [received], timeout: 2)
        server.stop()
        let (data, response) = try await waiting.value
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 204)
        XCTAssertTrue(data.isEmpty)
    }

    func testIncompleteUnauthenticatedConnectionHasADeadline() async throws {
        let server = AgentEventServer(token: "fixture", requestTimeout: 0.2) { _, reply in reply.send(nil) }
        let port = try await start(server)
        defer { server.stop() }
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let ready = expectation(description: "Local fixture connected")
        connection.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        connection.start(queue: DispatchQueue(label: "fixture.connection"))
        defer { connection.cancel() }
        await fulfillment(of: [ready], timeout: 2)
        connection.send(content: Data("POST /test HTTP/1.1\r\n".utf8), completion: .contentProcessed { _ in })
        try await Task.sleep(for: .milliseconds(400))
        let counts = await server.resourceCounts()
        XCTAssertEqual(counts.connections, 0)
        XCTAssertEqual(counts.bufferedBytes, 0)
    }

    func testStopCancelsPreAuthenticationConnections() async throws {
        let server = AgentEventServer(token: "fixture") { _, _ in XCTFail("Not authenticated") }
        let port = try await start(server)
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let ready = expectation(description: "Local fixture connected")
        connection.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        connection.start(queue: DispatchQueue(label: "fixture.stop"))
        defer { connection.cancel(); server.stop() }
        await fulfillment(of: [ready], timeout: 2)
        server.stop()
        let counts = await server.resourceCounts()
        XCTAssertEqual(counts.connections, 0)
        XCTAssertEqual(counts.waiting, 0)
    }
}
