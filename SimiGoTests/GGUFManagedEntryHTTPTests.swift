import Foundation
import Network
import XCTest
import SimiGoRuntimeContract

@testable import SimiGo

// MARK: - Stub engine

/// A loopback HTTP server that answers one request with a llama.cpp shaped
/// body. Only the engine is a stand-in; every other link is production code.
final class GGUFEngineStub: @unchecked Sendable {
    enum Behavior {
        /// SSE payload lines, then `[DONE]`, then end of body.
        case sse([String])
        /// One SSE payload line, then the connection stays open (for cancel).
        case sseStall(first: String)
        /// HTTP error status with a JSON body.
        case status(Int, String)
    }

    private let listener: NWListener
    private let behavior: Behavior
    private(set) var port: UInt16 = 0

    private let lock = NSLock()
    private var _requestBody: String?
    private var _sentFirstChunk = false

    var requestBody: String? {
        lock.lock()
        defer { lock.unlock() }
        return _requestBody
    }

    var sentFirstChunk: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _sentFirstChunk
    }

    private init(listener: NWListener, behavior: Behavior) {
        self.listener = listener
        self.behavior = behavior
    }

    static func start(port: UInt16, _ behavior: Behavior) throws -> GGUFEngineStub {
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        let stub = GGUFEngineStub(listener: listener, behavior: behavior)
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
                domain: "GGUFEngineStub", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "stub engine did not become ready"])
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
            let head = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
            // CRLF is one grapheme in Swift, so `split(separator: "\n")` would
            // not split these lines at all.
            let contentLength = head
                .components(separatedBy: "\r\n")
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
            lock.lock()
            let body = String(decoding: buffer[headerEnd.upperBound...], as: UTF8.self)
            if !body.isEmpty { _requestBody = body }
            lock.unlock()
            respond(on: connection)
        }

        func receiveMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
                data, _, isComplete, error in
                if let data { buffer.append(data) }
                respondIfComplete()
                if isComplete || error != nil { return }
                receiveMore()
            }
        }
        receiveMore()
    }

    private func respond(on connection: NWConnection) {
        switch behavior {
        case let .status(code, body):
            let bytes = Data(body.utf8)
            var head = "HTTP/1.1 \(code) Error\r\nContent-Type: application/json\r\n"
            head += "Content-Length: \(bytes.count)\r\nConnection: close\r\n\r\n"
            connection.send(
                content: Data(head.utf8) + bytes,
                completion: .contentProcessed { _ in connection.cancel() })

        case let .sse(payloads):
            let lines = payloads.map { "data: \($0)\n\n" }.joined()
                + "data: [DONE]\n\n"
            var head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n"
            head += "Transfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
            connection.send(
                content: Self.chunked(head: head, body: lines, endOfBody: true),
                completion: .contentProcessed { _ in connection.cancel() })

        case let .sseStall(first):
            var head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n"
            head += "Transfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
            let body = "data: \(first)\n\n"
            connection.send(
                content: Self.chunked(head: head, body: body),
                completion: .contentProcessed { _ in
                    self.lock.lock()
                    self._sentFirstChunk = true
                    self.lock.unlock()
                })
            // The body never terminates, mirroring a long cold prefill.
        }
    }

    private static func chunked(head: String, body: String, endOfBody: Bool = false) -> Data {
        var data = Data(head.utf8)
        let payload = Data(body.utf8)
        data.append(Data("\(String(payload.count, radix: 16))\r\n".utf8))
        data.append(payload)
        data.append(Data("\r\n".utf8))
        if endOfBody {
            data.append(Data("0\r\n\r\n".utf8))
        }
        return data
    }
}

// MARK: - Helpers shared by both suites

enum GGUFRestFixture {
    /// Matches the production `ManagedGGUFRuntime.freeLoopbackPort()` contract:
    /// the kernel confirms the port is bindable before the listener takes it.
    static func freePort() throws -> UInt16 {
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
            domain: "GGUFRestFixture", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "could not reserve a local port"])
    }

    static func waitUntilListening(port: Int, timeout: TimeInterval = 5) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if probeOnce(port: port) { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw NSError(
            domain: "GGUFRestFixture", code: 2,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "HTTPServer never accepted on 127.0.0.1:\(port)"
            ])
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
}

// MARK: - 1) The engine client on its own

/// The single translation point between llama.cpp's SSE wire and the protocol
/// contract. These tests pin the mapping the settlement gate depends on:
/// text assembly, usage, tool-call fragments, termination reason and cancel.
final class GGUFEngineClientTests: XCTestCase {

    private func makeClient(port: UInt16, model: String = "stub-gguf-model") -> GGUFEngineClient {
        GGUFEngineClient(
            endpoint: .init(
                baseURL: URL(string: "http://127.0.0.1:\(port)")!, model: model))
    }

    private func hostMessage(_ text: String) -> [JSONValue] {
        [JSONValue.any(["role": "user", "content": text])]
    }

    func testClientAssemblesSSEUsageAndCompletion() async throws {
        let stub = try GGUFEngineStub.start(
            port: try GGUFRestFixture.freePort(),
            .sse([
                #"{"choices":[{"delta":{"content":"节点"},"finish_reason":null}]}"#,
                #"{"choices":[{"delta":{"content":"工期 42 天"},"finish_reason":"stop"}]}"#,
                #"{"choices":[],"usage":{"prompt_tokens":21,"completion_tokens":7,"prompt_tokens_details":{"cached_tokens":5}}}"#,
            ]))
        defer { stub.stop() }
        let client = makeClient(port: stub.port)

        let lock = NSLock()
        var chunks: [String] = []
        let result = try await client.generate(
            requestId: "assemble-\(UUID().uuidString)",
            messages: hostMessage("关键线路 节点工期"),
            tools: nil,
            config: ModelConfig(),
            onChunk: { chunk in
                lock.lock()
                chunks.append(chunk)
                lock.unlock()
            },
            onToolCall: { _ in })

        XCTAssertEqual(result.text, "节点工期 42 天")
        XCTAssertEqual(result.completion, .complete)
        lock.lock()
        let received = chunks
        lock.unlock()
        XCTAssertEqual(received, ["节点", "工期 42 天"])
        let usage = try XCTUnwrap(result.usage, "usage must survive the SSE mapping")
        XCTAssertEqual(usage.promptTokens, 21)
        XCTAssertEqual(usage.generationTokens, 7)
        XCTAssertEqual(usage.cachedPromptTokens, 5)
        XCTAssertEqual(try XCTUnwrap(usage.cacheEfficiency), 5.0 / 21.0, accuracy: 1e-9)
        XCTAssertNotNil(usage.ttftSeconds)
        XCTAssertGreaterThan(try XCTUnwrap(usage.tokensPerSecond), 0)

        // The engine must be asked for the part of the wire this mapping reads.
        let body = try XCTUnwrap(stub.requestBody)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "stub-gguf-model")
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertEqual(json["cache_prompt"] as? Bool, true)
        XCTAssertEqual(
            (json["stream_options"] as? [String: Any])?["include_usage"] as? Bool, true)
    }

    func testClientAccumulatesFragmentedToolCalls() async throws {
        let stub = try GGUFEngineStub.start(
            port: try GGUFRestFixture.freePort(),
            .sse([
                #"{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_abc","type":"function","function":{"name":"get_weather","arguments":""}}]},"finish_reason":null}]}"#,
                #"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"city\":"}}]},"finish_reason":null}]}"#,
                #"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"Paris\"}"}}]},"finish_reason":null}]}"#,
                #"{"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
                #"{"choices":[],"usage":{"prompt_tokens":9,"completion_tokens":5}}"#,
            ]))
        defer { stub.stop() }
        let client = makeClient(port: stub.port)

        let lock = NSLock()
        var calls: [ParsedToolCall] = []
        let result = try await client.generate(
            requestId: "tools-\(UUID().uuidString)",
            messages: hostMessage("what is the weather"),
            tools: [JSONValue.any([
                "type": "function",
                "function": [
                    "name": "get_weather",
                    "parameters": ["type": "object", "properties": [String: Any]()],
                ],
            ])],
            config: ModelConfig(),
            onChunk: { _ in },
            onToolCall: { call in
                lock.lock()
                calls.append(call)
                lock.unlock()
            })

        XCTAssertEqual(result.text, "")
        XCTAssertEqual(
            result.completion, .complete,
            "a tool_calls ending is a normal ending; settlement is blocked on the tool-call ground")
        lock.lock()
        let received = calls
        lock.unlock()
        let call = try XCTUnwrap(received.first)
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(call.id, "call_abc")
        XCTAssertEqual(call.name, "get_weather")
        XCTAssertEqual(call.arguments["city"]?.string, "Paris")
    }

    func testClientMapsLengthToCapped() async throws {
        let stub = try GGUFEngineStub.start(
            port: try GGUFRestFixture.freePort(),
            .sse([
                #"{"choices":[{"delta":{"content":"TRUNC"},"finish_reason":"length"}]}"#,
                #"{"choices":[],"usage":{"prompt_tokens":3,"completion_tokens":1}}"#,
            ]))
        defer { stub.stop() }
        let client = makeClient(port: stub.port)
        let result = try await client.generate(
            requestId: "capped-\(UUID().uuidString)",
            messages: hostMessage("long answer"),
            tools: nil,
            config: ModelConfig(),
            onChunk: { _ in },
            onToolCall: { _ in })
        XCTAssertEqual(result.completion, .capped)
        XCTAssertEqual(result.text, "TRUNC")
    }

    func testClientSurfacesEngineHTTPErrorAsTypedFailure() async throws {
        let stub = try GGUFEngineStub.start(
            port: try GGUFRestFixture.freePort(),
            .status(503, #"{"error":"model loading"}"#))
        defer { stub.stop() }
        let client = makeClient(port: stub.port)

        do {
            _ = try await client.generate(
                requestId: "error-\(UUID().uuidString)",
                messages: hostMessage("hello"),
                tools: nil,
                config: ModelConfig(),
                onChunk: { _ in },
                onToolCall: { _ in })
            XCTFail("an engine HTTP failure must not become a generation result")
        } catch let failure as GGUFEngineClient.Failure {
            guard case let .upstream(status, body) = failure else {
                return XCTFail("unexpected failure shape: \(failure)")
            }
            XCTAssertEqual(status, 503)
            XCTAssertTrue(body.contains("model loading"))
        }
    }

    func testClientCancellationStopsTheStream() async throws {
        let stub = try GGUFEngineStub.start(
            port: try GGUFRestFixture.freePort(),
            .sseStall(first: #"{"choices":[{"delta":{"content":"partial"},"finish_reason":null}]}"#))
        defer { stub.stop() }
        let client = makeClient(port: stub.port)
        let requestID = "cancel-\(UUID().uuidString)"

        let task = Task {
            try await client.generate(
                requestId: requestID,
                messages: hostMessage("cancel me"),
                tools: nil,
                config: ModelConfig(),
                onChunk: { _ in },
                onToolCall: { _ in })
        }

        let deadline = Date().addingTimeInterval(5)
        while !stub.sentFirstChunk, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(stub.sentFirstChunk, "the engine never started streaming")

        client.cancel(requestId: requestID)
        let cancelledAt = Date()
        do {
            _ = try await task.value
            XCTFail("a cancelled generation must not return a result")
        } catch is CancellationError {
            // expected
        }
        XCTAssertLessThan(
            Date().timeIntervalSince(cancelledAt), 3,
            "cancellation must not wait for the engine to finish")
    }

    func testGGUFSnapshotIdentityUsesHFBlobNameAsContentAddress() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GGUFIdentity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let blobName = String((0..<64).map { _ in "0123456789abcdef".randomElement()! })
        let blob = root.appendingPathComponent(blobName)
        try Data(repeating: 0xAB, count: 33).write(to: blob)
        let addressed = SimiGoProducerIdentity.tokenizerIdentity(fromPath: blob.path)
        XCTAssertEqual(addressed.count, 1)
        XCTAssertEqual(addressed.first?["file"] as? String, blobName)
        XCTAssertEqual(
            addressed.first?["sha256"] as? String, blobName,
            "an HF cache blob's filename IS its SHA-256")
        XCTAssertEqual(addressed.first?["size"] as? Int64, 33)

        let plain = root.appendingPathComponent("model.gguf")
        try Data(repeating: 0xCD, count: 7).write(to: plain)
        let fallback = SimiGoProducerIdentity.tokenizerIdentity(fromPath: plain.path)
        XCTAssertEqual(fallback.count, 1)
        XCTAssertEqual(fallback.first?["file"] as? String, "model.gguf")
        XCTAssertEqual(fallback.first?["size"] as? Int64, 7)
        XCTAssertNil(
            fallback.first?["sha256"],
            "a non-content-addressed name must not claim a digest")
    }

    func testManagedLaunchArgsPinTheEngineToLoopback() {
        let args = ManagedGGUFRuntime.pinningLoopbackHost([
            "--model", "/tmp/model.gguf", "--port", "43210",
            "--host", "0.0.0.0", "--parallel", "2",
        ])
        let hostIndex = args.firstIndex(of: "--host")!
        XCTAssertEqual(
            args[hostIndex + 1], "127.0.0.1",
            "LAN mode publishes through the product listener; the internal engine has no auth")
        XCTAssertEqual(args[args.firstIndex(of: "--port")! + 1], "43210")
    }
}

// MARK: - 2) The managed entry end to end

/// GGUF turns through the product entry: the same HTTPServer, the same
/// HTTPServerChat preparation/settlement path and the same store as an MLX
/// turn. Runs only with the three isolated roots injected; otherwise XCTSkip.
final class GGUFManagedEntryHTTPTests: XCTestCase {

    private var isolationRoot: URL!
    private var modelPath: String!

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

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GGUFManagedEntry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"model_type":"gguf-managed-entry-stand-in"}"#.utf8)
            .write(to: dir.appendingPathComponent("tokenizer.adapter.json"))
        modelPath = dir.path
    }

    override func tearDown() {
        if let modelPath { try? FileManager.default.removeItem(atPath: modelPath) }
        super.tearDown()
    }

    // MARK: Fixture

    /// The production wiring of `ManagedGGUFRuntime.start`, with the engine
    /// process replaced by the SSE stub. Everything above the client is real.
    @MainActor
    private func withManagedEntry(
        _ behavior: GGUFEngineStub.Behavior,
        run: (Int, GGUFEngineStub, GGUFEngineClient) async throws -> Void
    ) async throws {
        let stub = try GGUFEngineStub.start(
            port: try GGUFRestFixture.freePort(), behavior)
        let client = GGUFEngineClient(
            endpoint: .init(
                baseURL: URL(string: "http://127.0.0.1:\(stub.port)")!,
                model: "stub-gguf-model"))
        let identity = SimiGoProducerIdentity.identity(fromPath: modelPath)
        let port = Int(try GGUFRestFixture.freePort())
        let server = HTTPServer(
            port: port,
            modelId: "gguf-managed-entry-test",
            bonjourEnabled: false,
            generateHandler: { requestId, _, _, _, messages, tools, config, onChunk, onToolCall in
                try await client.generate(
                    requestId: requestId,
                    messages: messages,
                    tools: tools,
                    config: config,
                    onChunk: onChunk,
                    onToolCall: onToolCall)
            },
            forkBranchHandler: { _, _, _, _ in
                throw RuntError.generationFailed("GGUF 后端不提供分支快照")
            },
            deleteBranchHandler: { _, _, _ in },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { true },
            cancelGenerationHandler: { requestId in
                client.cancel(requestId: requestId)
            },
            informationTurnProducer: {
                InformationTurnProducer(modelIdentity: identity.model, identity: identity)
            },
            requestAdmission: RequestAdmissionScheduler(limit: 4)
        )
        server.configureLOCALBSecurityMode(.legacyPlaintextCompat)
        try server.start()
        defer {
            server.stop()
            stub.stop()
        }
        try GGUFRestFixture.waitUntilListening(port: port)
        try await run(port, stub, client)
    }

    private func sendChat(
        to port: Int, session: String, query: String
    ) async throws -> (status: Int, body: [String: Any]) {
        var request = URLRequest(
            url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "gguf-managed-entry-test",
            "session_id": session,
            "messages": [["role": "user", "content": query]],
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return ((response as? HTTPURLResponse)?.statusCode ?? -1, json)
    }

    private func assistantContent(_ body: [String: Any]) -> String? {
        let choices = body["choices"] as? [[String: Any]]
        return (choices?.first?["message"] as? [String: Any])?["content"] as? String
    }

    // MARK: Tests

    /// A complete GGUF turn is recorded, settled and retrievable — the same
    /// three states an in-process turn reaches. This is the whole point of
    /// fronting the engine with the product entry.
    @MainActor
    func testGGUFTurnIsRecordedSettledAndRetrievable() async throws {
        let session = "gguf-managed-\(UUID().uuidString)"
        let query = "关键线路 节点工期"
        let answer = "节点工期 42 天"
        let stream: [String] = [
            #"{"choices":[{"delta":{"content":"节点"},"finish_reason":null}]}"#,
            #"{"choices":[{"delta":{"content":"工期 42 天"},"finish_reason":"stop"}]}"#,
            #"{"choices":[],"usage":{"prompt_tokens":21,"completion_tokens":7,"prompt_tokens_details":{"cached_tokens":5}}}"#,
        ]
        try await withManagedEntry(.sse(stream)) { port, stub, _ in
            let outcome = try await sendChat(to: port, session: session, query: query)
            XCTAssertEqual(outcome.status, 200)
            let choices = outcome.body["choices"] as? [[String: Any]]
            XCTAssertEqual(choices?.first?["finish_reason"] as? String, "stop")
            XCTAssertEqual(assistantContent(outcome.body), answer)
            XCTAssertNil(outcome.body["simigo"], "a finished turn carries no incomplete block")

            XCTAssertNotNil(stub.requestBody)
        }

        let db = try SimiGoESISDatabase(url: SimiGoPaths.databaseURL)
        let messages = try db.listChatMessages(sessionID: session)
        XCTAssertEqual(messages.map(\.role), ["user", "assistant"])
        XCTAssertEqual(messages.last?.content, answer)

        let answered = try XCTUnwrap(
            db.answeredDemand(sessionID: session, query: query),
            "a complete GGUF turn settles its demand")
        XCTAssertEqual(
            try db.settlementReceipt(answered.answerSettlementID)?.validity, "valid")
        XCTAssertNotNil(try db.currentChatStateID(sessionID: session))

        let loop = SimiGoInformationLoop(database: db)
        let resolution = try loop.resolve(
            .init(
                sessionID: session, query: query, includeChat: true,
                chatSessionIDs: [session]))
        XCTAssertTrue(
            resolution.hits.contains { $0.itemID.hasPrefix("chat:\(session)/") },
            "the settled GGUF answer becomes retrievable history")
    }

    /// A truncated GGUF answer is served and recorded but never settled: the
    /// termination signal travels engine → client → protocol layer.
    @MainActor
    func testTruncatedGGUFTurnIsRecordedButNotSettled() async throws {
        let session = "gguf-managed-capped-\(UUID().uuidString)"
        let query = "需要很长的回答"
        let stream: [String] = [
            #"{"choices":[{"delta":{"content":"TRUNCATED-MID-SENTENCE"},"finish_reason":"length"}]}"#,
            #"{"choices":[],"usage":{"prompt_tokens":3,"completion_tokens":2}}"#,
        ]
        try await withManagedEntry(.sse(stream)) { port, _, _ in
            let outcome = try await sendChat(to: port, session: session, query: query)
            XCTAssertEqual(outcome.status, 200)
            let choices = outcome.body["choices"] as? [[String: Any]]
            XCTAssertEqual(choices?.first?["finish_reason"] as? String, "length")
            XCTAssertEqual(assistantContent(outcome.body), "TRUNCATED-MID-SENTENCE")
            let simigo = outcome.body["simigo"] as? [String: Any]
            XCTAssertEqual(simigo?["completion"] as? String, "capped")
            XCTAssertEqual(simigo?["settlement_written"] as? Bool, false)
        }

        let db = try SimiGoESISDatabase(url: SimiGoPaths.databaseURL)
        let messages = try db.listChatMessages(sessionID: session)
        XCTAssertEqual(
            messages.last?.content, "TRUNCATED-MID-SENTENCE",
            "the partial text is kept for audit")
        XCTAssertNil(
            try db.answeredDemand(sessionID: session, query: query),
            "a capped GGUF turn must not become knowledge")
        XCTAssertNil(try db.currentChatStateID(sessionID: session))
    }

    /// A second identical question is served by the settlement, with zero
    /// engine calls — the reuse contract also holds for GGUF.
    @MainActor
    func testSettledGGUFTurnIsReusedWithoutEngineCall() async throws {
        let session = "gguf-managed-reuse-\(UUID().uuidString)"
        let query = "关键线路 节点工期"
        let stream: [String] = [
            #"{"choices":[{"delta":{"content":"节点工期 42 天"},"finish_reason":"stop"}]}"#,
            #"{"choices":[],"usage":{"prompt_tokens":21,"completion_tokens":7}}"#,
        ]
        try await withManagedEntry(.sse(stream)) { port, stub, _ in
            let first = try await sendChat(to: port, session: session, query: query)
            XCTAssertEqual(first.status, 200)
            XCTAssertEqual(assistantContent(first.body), "节点工期 42 天")
            XCTAssertNotNil(stub.requestBody, "the first turn must reach the engine")

            let second = try await sendChat(to: port, session: session, query: query)
            XCTAssertEqual(second.status, 200)
            XCTAssertEqual(assistantContent(second.body), "节点工期 42 天")
            let simigo = second.body["simigo"] as? [String: Any]
            XCTAssertEqual(simigo?["answer_reuse"] as? Bool, true)
            XCTAssertEqual(simigo?["model_calls"] as? Int, 0)
        }
    }
}
