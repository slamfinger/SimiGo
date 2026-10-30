import Foundation
import Network
import XCTest
import SimiGoRuntimeContract

@testable import SimiGo

/// External-API turns end to end through the real forwarding path.
///
/// The chain under test is the production one, with only the upstream provider
/// replaced by a loopback stub:
///
///   client POST /v1/chat/completions
///     -> HTTPServer route -> forwardToRemote
///     -> recordExternalTurn (recorded, not retrievable)
///     -> stub upstream answers
///     -> recordExternalResponse + verifyExternalTurn (complete answers only)
///     -> chatIndexRows / SimiGoInformationLoop (retrievable history)
///
/// Runs only with the three isolated roots injected (`SIMIGO_HOME`,
/// `SIMIGO_CACHE_ROOT`, `SIMIGO_STATE_GRAPH_STORE`); otherwise XCTSkip. That
/// guard is what keeps a plain `xcodebuild test` from writing the real
/// `~/.simigo`.
final class RemoteISForwardingTests: XCTestCase {

    private var isolationRoot: URL!

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let home = env["SIMIGO_HOME"], !home.isEmpty, home.hasPrefix("/"),
            let graphStore = env["SIMIGO_STATE_GRAPH_STORE"], !graphStore.isEmpty,
            let cache = env["SIMIGO_CACHE_ROOT"], !cache.isEmpty
        else {
            throw XCTSkip(
                "isolated roots not injected: run through tools/make_isolated_xctestrun.py "
                + "so no real user state is touched")
        }
        isolationRoot = URL(
            fileURLWithPath: (home as NSString).standardizingPath, isDirectory: true)
        XCTAssertTrue(
            SimiGoPaths.databaseURL.path.hasPrefix(isolationRoot.path),
            "authoritative store resolves outside the isolation root")
    }

    // MARK: - Loopback upstream stub

    private final class StubUpstream: @unchecked Sendable {
        enum Reply {
            case json(String)
            case stream(String)
        }

        private let listener: NWListener
        private let reply: Reply
        private(set) var port: UInt16 = 0

        private init(listener: NWListener, reply: Reply) {
            self.listener = listener
            self.reply = reply
        }

        static func start(port: UInt16, _ reply: Reply) throws -> StubUpstream {
            let listener = try NWListener(
                using: .tcp,
                on: NWEndpoint.Port(rawValue: port)!)
            let stub = StubUpstream(listener: listener, reply: reply)
            let ready = DispatchSemaphore(value: 0)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready, .failed, .cancelled: ready.signal()
                default: break
                }
            }
            listener.newConnectionHandler = { connection in
                connection.start(queue: .global())
                stub.serve(connection)
            }
            listener.start(queue: .global())
            guard ready.wait(timeout: .now() + 5) == .success,
                case .ready = listener.state
            else {
                listener.cancel()
                throw NSError(
                    domain: "StubUpstream", code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "stub upstream did not become ready"
                    ])
            }
            stub.port = port
            return stub
        }

        func stop() { listener.cancel() }

        private func serve(_ connection: NWConnection) {
            var buffer = Data()
            var responded = false

            func respondIfComplete() {
                guard !responded,
                    let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8))
                else { return }
                let head = String(
                    decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
                let contentLength = head
                    .split(separator: "\n")
                    .compactMap { line -> Int? in
                        let trimmed = line
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .lowercased()
                        guard trimmed.hasPrefix("content-length:") else { return nil }
                        return Int(
                            trimmed.dropFirst("content-length:".count)
                                .trimmingCharacters(in: .whitespaces))
                    }
                    .first ?? 0
                guard buffer.count - headerEnd.upperBound >= contentLength else { return }
                responded = true
                let response = responseBytes()
                connection.send(
                    content: response,
                    completion: .contentProcessed { _ in connection.cancel() })
            }

            func receiveMore() {
                connection.receive(
                    minimumIncompleteLength: 1, maximumLength: 65_536
                ) { data, _, isComplete, error in
                    if let data { buffer.append(data) }
                    respondIfComplete()
                    if isComplete || error != nil { return }
                    receiveMore()
                }
            }
            receiveMore()
        }

        private func responseBytes() -> Data {
            switch reply {
            case .json(let body):
                let bytes = Data(body.utf8)
                var head = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
                head += "Content-Length: \(bytes.count)\r\nConnection: close\r\n\r\n"
                return Data(head.utf8) + bytes
            case .stream(let body):
                let bytes = Data(body.utf8)
                var head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n"
                head += "Content-Length: \(bytes.count)\r\nConnection: close\r\n\r\n"
                return Data(head.utf8) + bytes
            }
        }
    }

    // MARK: - Fixture

    /// A port the kernel confirms is bindable on loopback. `NWListener` does
    /// not report its assigned ephemeral port here (it stays 0), so the port
    /// is chosen first and handed to the listener explicitly.
    private static func freePort() throws -> UInt16 {
        for _ in 0..<20 {
            let candidate = UInt16.random(in: 42000...58000)
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else { break }
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = candidate.bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")
            let bound = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            close(fd)
            if bound == 0 { return candidate }
        }
        throw NSError(
            domain: "RemoteISForwardingTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "could not reserve a local port"])
    }

    private static func waitUntilListening(port: Int, timeout: TimeInterval = 5) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if probeOnce(port: port) { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw NSError(
            domain: "RemoteISForwardingTests", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "HTTPServer never accepted on 127.0.0.1:\(port)"])
    }

    private static func probeOnce(port: Int) -> Bool {
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return false }
        let connection = NWConnection(host: "127.0.0.1", port: endpointPort, using: .tcp)
        let reached = DispatchSemaphore(value: 0)
        let answered = NSLock()
        var isReady = false
        connection.stateUpdateHandler = { state in
            answered.lock()
            defer { answered.unlock() }
            guard !isReady else { return }
            switch state {
            case .ready:
                isReady = true
                reached.signal()
            case .failed:
                reached.signal()
            default:
                break
            }
        }
        connection.start(queue: .global())
        let connected = reached.wait(timeout: .now() + 1) == .success
        connection.cancel()
        answered.lock()
        defer { answered.unlock() }
        return connected && isReady
    }

    @MainActor
    private func withServer(
        _ reply: StubUpstream.Reply,
        run: (Int, StubUpstream) async throws -> Void
    ) async throws {
        let stub = try StubUpstream.start(port: try Self.freePort(), reply)
        let backend = RemoteOpenAIBackend(
            configuration: CloudBackendConfiguration(
                baseURLString: "http://127.0.0.1:\(stub.port)",
                model: "stub-model",
                provider: .openai),
            apiKey: "")
        let port = Int(try Self.freePort())
        let server = HTTPServer(
            port: port,
            modelId: "remote-is-forwarding-test",
            bonjourEnabled: false,
            generateHandler: { _, _, _, _, _, _, _, _, _ in
                GenerationResult(text: "", usage: nil, completion: .complete)
            },
            forkBranchHandler: { _, _, _, _ in
                throw RuntError.generationFailed("no live session in forwarding test")
            },
            deleteBranchHandler: { _, _, _ in },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { true },
            remoteBackend: backend
        )
        server.configureLOCALBSecurityMode(.legacyPlaintextCompat)
        try server.start()
        defer {
            server.stop()
            stub.stop()
        }
        try Self.waitUntilListening(port: port)
        try await run(port, stub)
    }

    private func sendChat(
        to port: Int, path: String = "/v1/chat/completions",
        body: [String: Any], headers: [String: String] = [:]
    ) async throws -> (status: Int, raw: Data) {
        var request = URLRequest(
            url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? -1, data)
    }

    private func openDatabase() throws -> SimiGoESISDatabase {
        try SimiGoESISDatabase(url: SimiGoPaths.databaseURL)
    }

    // MARK: - Tests

    /// The complete answer of a forwarded request is recorded with provenance
    /// and becomes retrievable history.
    func testForwardedTurnIsRecordedThenVerifiedAndRetrievable() async throws {
        let sessionID = "remote-is-e2e-\(UUID().uuidString)"
        let answer = "外部回答：关键线路 节点工期 42 天"
        try await withServer(
            .json(
                #"{"choices":[{"message":{"role":"assistant","content":"\#(answer)"},"finish_reason":"stop"}]}"#
            )
        ) { port, _ in
            let outcome = try await sendChat(
                to: port,
                body: [
                    "model": "client-model",
                    "session_id": sessionID,
                    "messages": [
                        ["role": "user", "content": "外部请求：关键线路 节点工期"],
                    ],
                ])
            XCTAssertEqual(outcome.status, 200)
            XCTAssertTrue(String(decoding: outcome.raw, as: UTF8.self).contains(answer))
        }

        let db = try openDatabase()
        let provenance = try db.chatTurnProvenance(sessionID: sessionID)
        XCTAssertEqual(provenance.map(\.role), ["user", "assistant"])
        XCTAssertEqual(provenance.map(\.turnState), ["committed", "committed"])
        XCTAssertEqual(provenance.map(\.sourceKind), ["external", "external"])
        XCTAssertEqual(provenance.compactMap(\.sourceProvider), ["openai", "openai"])
        XCTAssertEqual(
            Set(provenance.compactMap(\.requestID)).count, 1,
            "both sides of one forwarded turn share its request identity")
        XCTAssertTrue(provenance.allSatisfy { $0.verifiedAt != nil && $0.isEligible })

        let messages = try db.listChatMessages(sessionID: sessionID)
        XCTAssertEqual(messages.map(\.role), ["user", "assistant"])
        XCTAssertEqual(messages.last?.content, answer)

        let loop = SimiGoInformationLoop(database: db)
        let resolution = try loop.resolve(
            .init(
                sessionID: sessionID, query: "节点工期", includeChat: true,
                chatSessionIDs: [sessionID]))
        XCTAssertEqual(
            Set(resolution.hits.map(\.itemID)),
            Set(provenance.map { "chat:\(sessionID)/\($0.messageID)" }))
    }

    /// Streaming forwarded turns are verified from the SSE stream, not from a
    /// JSON body.
    func testStreamingForwardedTurnIsVerifiedOnCompleteStream() async throws {
        let sessionID = "remote-is-e2e-stream-\(UUID().uuidString)"
        let answer = "外部流式回答：节点工期 42 天"
        let stream = """
            data: {"choices":[{"delta":{"content":"外部流式回答："},"finish_reason":null}]}

            data: {"choices":[{"delta":{"content":"节点工期 42 天"},"finish_reason":"stop"}]}

            data: [DONE]

            """
        try await withServer(.stream(stream)) { port, _ in
            let outcome = try await sendChat(
                to: port,
                body: [
                    "model": "client-model",
                    "stream": true,
                    "session_id": sessionID,
                    "messages": [
                        ["role": "user", "content": "外部请求：关键线路 节点工期"],
                    ],
                ])
            XCTAssertEqual(outcome.status, 200)
            let text = String(decoding: outcome.raw, as: UTF8.self)
            XCTAssertTrue(text.contains("节点工期 42 天"))
        }

        let db = try openDatabase()
        let provenance = try db.chatTurnProvenance(sessionID: sessionID)
        XCTAssertEqual(provenance.map(\.turnState), ["committed", "committed"])
        XCTAssertTrue(provenance.allSatisfy { $0.verifiedAt != nil })
        let loop = SimiGoInformationLoop(database: db)
        let resolution = try loop.resolve(
            .init(
                sessionID: sessionID, query: "节点工期", includeChat: true,
                chatSessionIDs: [sessionID]))
        XCTAssertEqual(
            Set(resolution.hits.map(\.itemID)),
            Set(provenance.map { "chat:\(sessionID)/\($0.messageID)" }))
    }

    /// A truncated upstream answer is kept — with provenance — but it never
    /// becomes knowledge another request may consume.
    func testTruncatedUpstreamAnswerStaysRecordedAndUnretrievable() async throws {
        let sessionID = "remote-is-e2e-truncated-\(UUID().uuidString)"
        try await withServer(
            .json(
                #"{"choices":[{"message":{"content":"被截断的外部回答"},"finish_reason":"length"}]}"#
            )
        ) { port, _ in
            let outcome = try await sendChat(
                to: port,
                body: [
                    "model": "client-model",
                    "session_id": sessionID,
                    "messages": [
                        ["role": "user", "content": "外部请求：需要完整回答的问题"],
                    ],
                ])
            XCTAssertEqual(outcome.status, 200)
        }

        let db = try openDatabase()
        let provenance = try db.chatTurnProvenance(sessionID: sessionID)
        XCTAssertEqual(provenance.map(\.role), ["user", "assistant"])
        XCTAssertEqual(provenance.map(\.turnState), ["recorded", "recorded"])
        XCTAssertTrue(provenance.allSatisfy { $0.verifiedAt == nil && !$0.isEligible })
        XCTAssertEqual(
            try db.listChatMessages(sessionID: sessionID).last?.content,
            "被截断的外部回答")

        let loop = SimiGoInformationLoop(database: db)
        let resolution = try loop.resolve(
            .init(
                sessionID: sessionID, query: "完整回答", includeChat: true,
                chatSessionIDs: [sessionID]))
        XCTAssertTrue(resolution.hits.isEmpty)
    }

    /// A client-declared internal operation keeps that standing through the
    /// forwarding path: the turn is recorded for audit, but verification never
    /// promotes it and no later request can retrieve it.
    func testInternalDeclaredForwardedTurnIsKeptButNeverPromoted() async throws {
        let sessionID = "remote-is-e2e-internal-\(UUID().uuidString)"
        let answer = "内部记账：rollout 摘要 17 条"
        try await withServer(
            .json(
                #"{"choices":[{"message":{"content":"\#(answer)"},"finish_reason":"stop"}]}"#
            )
        ) { port, _ in
            let outcome = try await sendChat(
                to: port,
                body: [
                    "model": "client-model",
                    "session_id": sessionID,
                    "messages": [
                        ["role": "user", "content": "内部请求：后台 rollout 分析"],
                    ],
                ],
                headers: ["X-SimiGo-Request-Scope": "internal"])
            XCTAssertEqual(outcome.status, 200)
            XCTAssertTrue(String(decoding: outcome.raw, as: UTF8.self).contains(answer))
        }

        let db = try openDatabase()
        let provenance = try db.chatTurnProvenance(sessionID: sessionID)
        XCTAssertEqual(provenance.map(\.role), ["user", "assistant"])
        XCTAssertEqual(
            provenance.map(\.turnState), ["internal", "internal"],
            "an internal declaration must survive the external write path")
        XCTAssertTrue(
            provenance.allSatisfy { $0.verifiedAt == nil && !$0.isEligible },
            "internal bookkeeping is kept, but never settled or retrievable")
        XCTAssertEqual(
            try db.listChatMessages(sessionID: sessionID).last?.content, answer,
            "keeping it means the text is still readable for audit")

        let loop = SimiGoInformationLoop(database: db)
        let resolution = try loop.resolve(
            .init(
                sessionID: sessionID, query: "rollout 摘要", includeChat: true,
                chatSessionIDs: [sessionID]))
        XCTAssertTrue(resolution.hits.isEmpty)
    }

    /// `/v1/responses` is the wire Codex Desktop's local provider is configured
    /// for, so it goes through the same recording rule as chat.
    func testResponsesWireForwardedTurnIsVerifiedAndRetrievable() async throws {
        let sessionID = "remote-is-e2e-responses-\(UUID().uuidString)"
        let answer = "外部 responses 回答：节点工期 42 天"
        let reply = """
            {"status":"completed","output":[{"type":"message","role":"assistant",
             "content":[{"type":"output_text","text":"\(answer)"}]}]}
            """
        try await withServer(.json(reply.replacingOccurrences(of: "\n", with: ""))) { port, _ in
            let outcome = try await sendChat(
                to: port,
                path: "/v1/responses",
                body: [
                    "model": "client-model",
                    "session_id": sessionID,
                    "input": [
                        [
                            "role": "user",
                            "content": [
                                ["type": "input_text", "text": "外部请求：关键线路 节点工期"],
                            ],
                        ],
                    ],
                ])
            XCTAssertEqual(outcome.status, 200)
            XCTAssertTrue(String(decoding: outcome.raw, as: UTF8.self).contains(answer))
        }

        let db = try openDatabase()
        let provenance = try db.chatTurnProvenance(sessionID: sessionID)
        XCTAssertEqual(provenance.map(\.role), ["user", "assistant"])
        XCTAssertEqual(provenance.map(\.turnState), ["committed", "committed"])
        XCTAssertEqual(provenance.map(\.sourceKind), ["external", "external"])
        XCTAssertTrue(provenance.allSatisfy { $0.verifiedAt != nil && $0.isEligible })
        XCTAssertEqual(
            try db.listChatMessages(sessionID: sessionID).last?.content, answer)

        let loop = SimiGoInformationLoop(database: db)
        let resolution = try loop.resolve(
            .init(
                sessionID: sessionID, query: "节点工期", includeChat: true,
                chatSessionIDs: [sessionID]))
        XCTAssertEqual(
            Set(resolution.hits.map(\.itemID)),
            Set(provenance.map { "chat:\(sessionID)/\($0.messageID)" }))
    }
}
