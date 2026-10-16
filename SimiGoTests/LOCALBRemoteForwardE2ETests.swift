import Foundation
import Network
import XCTest

@testable import SimiGo

/// PR #14 review gap closure (2026-10-16, route ① step 2): proves the
/// FULL forwarding chain for a LOCALB-authorized remote route —
/// challenge (binding the exact requestTarget) → V2 proof → B3 gate →
/// dispatch → a REAL loopback mock upstream — delivers the signed target
/// byte-for-byte on the upstream request line.
///
/// The signed target intentionally carries the two fragile cases from
/// d802237: a percent-encoded slash (`%2F` must survive un-reencoded) and
/// a trailing empty-value parameter (the `?…&flag=` delimiter must
/// survive). The loopback HTTP upstream itself exercises the 75d1eb3
/// exemption that makes local mock development legal.
final class LOCALBRemoteForwardE2ETests: XCTestCase {

    private let serverPort = 18_441
    private let upstreamPort = 18_442

    /// One-shot capture upstream: accepts a single connection, records the
    /// request line + Authorization header, replies with a canned chat
    /// completion over plain HTTP.
    private final class MockUpstream {

        private let listener: NWListener
        private let lock = NSLock()
        private var requestLine: String?
        private var authorization: String?

        init(port: Int) throws {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(
                using: params,
                on: NWEndpoint.Port(rawValue: UInt16(port))
                    ?? NWEndpoint.Port(rawValue: 0)!)
        }

        var capturedRequestLine: String? {
            lock.lock()
            defer { lock.unlock() }
            return requestLine
        }

        var capturedAuthorization: String? {
            lock.lock()
            defer { lock.unlock() }
            return authorization
        }

        func start() {
            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .global())
                self?.serve(connection)
            }
            listener.start(queue: .global())
        }

        func stop() {
            listener.cancel()
        }

        private func serve(_ connection: NWConnection) {
            var buffer = Data()
            receive(connection, into: &buffer)
        }

        private func receive(
            _ connection: NWConnection, into buffer: inout Data
        ) {
            // Local var copy is impossible with `inout` across escapes —
            // use a box instead.
            boxReceive(connection, buffer: buffer)
        }

        private func boxReceive(
            _ connection: NWConnection, buffer: Data
        ) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
                [weak self] data, _, isComplete, error in
                guard error == nil else {
                    connection.cancel()
                    return
                }
                var buffer = buffer
                if let data {
                    buffer.append(data)
                }
                guard let self else { return }

                if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                    let head = String(
                        decoding: buffer.subdata(in: 0..<range.lowerBound),
                        as: UTF8.self)
                    self.lock.lock()
                    self.requestLine = head
                        .split(separator: "\r\n").first.map(String.init)
                    for line in head.split(separator: "\r\n").dropFirst() {
                        let parts = line.split(
                            separator: ":", maxSplits: 1)
                        if parts.count == 2,
                           parts[0].lowercased() == "authorization" {
                            self.authorization =
                                parts[1].trimmingCharacters(in: .whitespaces)
                        }
                    }
                    self.lock.unlock()
                    self.respond(with: Self.cannedCompletion, on: connection)
                } else if isComplete {
                    connection.cancel()
                } else {
                    self.boxReceive(connection, buffer: buffer)
                }
            }
        }

        private static let cannedCompletion: Data = {
            let json: [String: Any] = [
                "id": "chatcmpl-mock",
                "object": "chat.completion",
                "created": 0,
                "model": "mock-model",
                "choices": [[
                    "index": 0,
                    "message": ["role": "assistant", "content": "ok"],
                    "finish_reason": "stop"
                ]]
            ]
            let body = try! JSONSerialization.data(withJSONObject: json)
            return Data(
                ("HTTP/1.1 200 OK\r\n"
                    + "Content-Type: application/json\r\n"
                    + "Content-Length: \(body.count)\r\n"
                    + "Connection: close\r\n\r\n").utf8
            ) + body
        }()

        private func respond(with payload: Data, on connection: NWConnection) {
            connection.send(
                content: payload,
                completion: .contentProcessed { _ in
                    connection.cancel()
                }
            )
        }
    }

    func testUpstreamReceivesSignedTargetByteForByte() async throws {
        let upstream = try MockUpstream(port: upstreamPort)
        upstream.start()
        defer { upstream.stop() }

        let host = try LOCALBAuthorizedE2E.makeHost()
        let backend = RemoteOpenAIBackend(
            configuration: CloudBackendConfiguration(
                baseURLString: "http://127.0.0.1:\(upstreamPort)/v1",
                model: "mock-model"
            ),
            apiKey: "test-key"
        )

        let server = HTTPServer(
            port: serverPort,
            modelId: "mock-model",
            bonjourEnabled: false,
            generateHandler: { _, _, _, _, _, _, _, _, _ in
                GenerationResult(text: "", usage: nil)
            },
            forkBranchHandler: { _, _, _, _ in
                SessionCacheMetadata(
                    storageKey: "", modelId: "", savedAt: Date(),
                    history: [], kvFingerprint: nil,
                    checkpointGeneration: nil, cacheSHA256: nil)
            },
            deleteBranchHandler: { _, _, _ in },
            listBranchesHandler: { _, _ in ([], []) },
            checkHealthHandler: { true },
            remoteBackend: backend
        )
        server.configureLOCALBTransport(identity: host.identity)
        server.configureLOCALBRequestAuthorization(
            coordinator: host.coordinator,
            trustedCheckpoint: host.checkpointProvider
        )
        try server.start()
        defer { server.stop() }

        // Fragile cases on purpose: encoded slash + trailing empty value.
        let target = "/v1/chat/completions?team=core%2Flocalb&flag="
        let body = try JSONSerialization.data(
            withJSONObject: [
                "model": "mock-model",
                "messages": [["role": "user", "content": "hi"]],
                "stream": false,
            ]
        )

        let (data, response) = try await LOCALBAuthorizedE2E.send(
            host: host,
            port: serverPort,
            method: "POST",
            path: target,
            contentType: "application/json",
            body: body
        )
        XCTAssertEqual(
            response.statusCode, 200,
            String(decoding: data, as: UTF8.self))

        // The upstream must have seen the SIGNED target, byte for byte.
        let deadline = Date().addingTimeInterval(5)
        var line: String?
        while Date() < deadline {
            line = upstream.capturedRequestLine
            if line != nil { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let captured = try XCTUnwrap(line, "upstream captured no request")
        XCTAssertTrue(
            captured.hasPrefix("POST /v1/chat/completions?"),
            "unexpected request line: \(captured)")
        let upstreamTarget = captured.dropFirst("POST ".count).prefix(
            while: { $0 != " " })
        XCTAssertEqual(
            String(upstreamTarget), target,
            "upstream target diverges from the signed request-target")

        // Secondary: credentials crossed the boundary server-side only.
        XCTAssertEqual(upstream.capturedAuthorization, "Bearer test-key")
    }
}
