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

    private var identityRoot: URL!

    override func setUpWithError() throws {
        identityRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "GGUFIdentityLedger-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: identityRoot, withIntermediateDirectories: true)
        GGUFModelIdentity.blobLedgerURLOverride =
            identityRoot.appendingPathComponent("model-content-digests.json")
    }

    override func tearDown() {
        GGUFModelIdentity.blobLedgerURLOverride = nil
        if let identityRoot { try? FileManager.default.removeItem(at: identityRoot) }
        super.tearDown()
    }

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
            onToolCall: { _ in },
            onReasoning: { _ in })

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

    func testClientKeepsReasoningOffTheAnswerChannel() async throws {
        let stub = try GGUFEngineStub.start(
            port: try GGUFRestFixture.freePort(),
            .sse([
                #"{"choices":[{"delta":{"reasoning_content":"先核对约束。"},"finish_reason":null}]}"#,
                #"{"choices":[{"delta":{"reasoning_content":"再给出结论。"},"finish_reason":null}]}"#,
                #"{"choices":[{"delta":{"content":"答案。"},"finish_reason":"stop"}]}"#,
                #"{"choices":[],"usage":{"prompt_tokens":5,"completion_tokens":6}}"#,
            ]))
        defer { stub.stop() }
        let client = makeClient(port: stub.port)

        let lock = NSLock()
        var content: [String] = []
        var reasoning: [String] = []
        let result = try await client.generate(
            requestId: "reasoning-\(UUID().uuidString)",
            messages: hostMessage("解释一下"),
            tools: nil,
            config: ModelConfig(),
            onChunk: { chunk in
                lock.lock()
                content.append(chunk)
                lock.unlock()
            },
            onToolCall: { _ in },
            onReasoning: { text in
                lock.lock()
                reasoning.append(text)
                lock.unlock()
            })

        lock.lock()
        let receivedContent = content
        let receivedReasoning = reasoning
        lock.unlock()
        XCTAssertEqual(receivedContent, ["答案。"], "reasoning must never ride content")
        XCTAssertEqual(
            receivedReasoning, ["先核对约束。", "再给出结论。"],
            "the engine's own reasoning is forwarded in order on its own channel")
        XCTAssertEqual(result.text, "答案。")
        XCTAssertEqual(result.completion, .complete)
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
            },
            onReasoning: { _ in })

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
            onToolCall: { _ in },
            onReasoning: { _ in })
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
                onToolCall: { _ in },
            onReasoning: { _ in })
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
                onToolCall: { _ in },
            onReasoning: { _ in })
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

    /// A checkpoint's tokenizer identity is the digest of its bytes. The HF hub
    /// names blobs by their own SHA-256, and that name is accepted only inside
    /// the hub layout it describes — a bare 64-hex filename proves nothing.
    func testGGUFTokenizerIdentityIsTheContentDigestNotTheFilename() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GGUFIdentity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let hub = root.appendingPathComponent("hub", isDirectory: true)
        let blobs = hub.appendingPathComponent(
            "models--org--demo/blobs", isDirectory: true)
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        let bytes = Data("gguf-blob-through-the-hub".utf8)
        let blobName = SettlementAuthority.payloadDigest(bytes)
        try bytes.write(to: blobs.appendingPathComponent(blobName))
        let addressed = ProducerIdentity.tokenizerIdentity(
            fromPath: blobs.appendingPathComponent(blobName).path)
        XCTAssertEqual(addressed.count, 1)
        XCTAssertEqual(addressed.first?["file"] as? String, blobName)
        XCTAssertEqual(
            addressed.first?["sha256"] as? String, blobName,
            "inside models--*/blobs/, the filename IS the SHA-256")
        XCTAssertEqual(addressed.first?["size"] as? Int64, Int64(bytes.count))

        // A local checkpoint: the digest comes from the bytes, not from the name.
        let plain = root.appendingPathComponent("model.gguf")
        let localBytes = Data(repeating: 0xCD, count: 7)
        try localBytes.write(to: plain)
        let local = ProducerIdentity.tokenizerIdentity(fromPath: plain.path)
        XCTAssertEqual(local.count, 1)
        XCTAssertEqual(local.first?["file"] as? String, "model.gguf")
        XCTAssertEqual(local.first?["size"] as? Int64, 7)
        XCTAssertEqual(
            local.first?["sha256"] as? String,
            SettlementAuthority.payloadDigest(localBytes),
            "the digest is the checkpoint's content, never the filename")

        // A 64-hex name outside the hub layout is not a content address.
        let fakeName = String(repeating: "a", count: 64)
        let fake = root.appendingPathComponent(fakeName)
        try localBytes.write(to: fake)
        let notTrusted = ProducerIdentity.tokenizerIdentity(fromPath: fake.path)
        XCTAssertEqual(
            notTrusted.first?["sha256"] as? String,
            SettlementAuthority.payloadDigest(localBytes),
            "an ordinary file cannot claim a digest by naming itself like one")
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
            ManagedPaths.databaseURL.path.hasPrefix(isolationRoot.path),
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
        let identity = ProducerIdentity.identity(fromPath: modelPath)
        let port = Int(try GGUFRestFixture.freePort())
        let server = HTTPServer(
            port: port,
            modelId: "gguf-managed-entry-test",
            bonjourEnabled: false,
            generateHandler: { requestId, _, _, _, messages, tools, config, onChunk, onToolCall, onReasoning in
                try await client.generate(
                    requestId: requestId,
                    messages: messages,
                    tools: tools,
                    config: config,
                    onChunk: onChunk,
                    onToolCall: onToolCall,
                    onReasoning: onReasoning)
            },
            forkBranchHandler: { _, _, _, _ in
                throw RuntError.generationFailed("GGUF 后端不提供分支快照")
            },
            deleteBranchHandler: { _, _, _, _ in
                BranchDeletionOutcome(
                    deletedBranch: "", hadLiveSession: false,
                    hadCheckpointFile: false, generation: 1,
                    remainingLiveBranches: [],
                    remainingCheckpointBranches: [])
            },
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

    private func sendChatRaw(
        to port: Int,
        session: String,
        query: String,
        stream: Bool = false,
        maxTokens: Int? = nil
    ) async throws -> (status: Int, data: Data) {
        var request = URLRequest(
            url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        var payload: [String: Any] = [
            "model": "gguf-managed-entry-test",
            "session_id": session,
            "messages": [["role": "user", "content": query]],
        ]
        if stream { payload["stream"] = true }
        if let maxTokens { payload["max_tokens"] = maxTokens }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? -1, data)
    }

    private func sendChat(
        to port: Int, session: String, query: String
    ) async throws -> (status: Int, body: [String: Any]) {
        let (status, data) = try await sendChatRaw(
            to: port, session: session, query: query)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return (status, json)
    }

    private func assistantMessage(_ body: [String: Any]) -> [String: Any]? {
        (body["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]
    }

    private func assistantContent(_ body: [String: Any]) -> String? {
        assistantMessage(body)?["content"] as? String
    }

    /// Parsed `delta` objects of a chat SSE body, in wire order.
    private func streamDeltas(_ data: Data) -> [[String: Any]] {
        String(decoding: data, as: UTF8.self)
            .components(separatedBy: "\n")
            .compactMap { line -> [String: Any]? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("data:") else { return nil }
                let payload = trimmed.dropFirst("data:".count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard payload != "[DONE]" else { return nil }
                guard let json = try? JSONSerialization.jsonObject(
                    with: Data(payload.utf8)) as? [String: Any]
                else { return nil }
                return ((json["choices"] as? [[String: Any]])?.first?["delta"])
                    as? [String: Any]
            }
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
            XCTAssertNil(
                assistantMessage(outcome.body)?["reasoning_content"],
                "a turn the engine did not reason through carries no reasoning field")
            XCTAssertNil(outcome.body["simigo"], "a finished turn carries no incomplete block")

            XCTAssertNotNil(stub.requestBody)
        }

        let db = try ESISDatabase(url: ManagedPaths.databaseURL)
        let messages = try db.listChatMessages(sessionID: session)
        XCTAssertEqual(messages.map(\.role), ["user", "assistant"])
        XCTAssertEqual(messages.last?.content, answer)

        let answered = try XCTUnwrap(
            db.answeredDemand(sessionID: session, query: query),
            "a complete GGUF turn settles its demand")
        XCTAssertEqual(
            try db.settlementReceipt(answered.answerSettlementID)?.validity, "valid")
        XCTAssertNotNil(try db.currentChatStateID(sessionID: session))

        let loop = InformationLoop(database: db)
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

        let db = try ESISDatabase(url: ManagedPaths.databaseURL)
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

    // MARK: - #148 reasoning exposure

    /// Reasoning is served on its own field, and only there: the answer keeps
    /// its previous shape, and nothing derived from reasoning reaches the
    /// conversation ledger, the settlement or the retrieval index.
    @MainActor
    func testGGUFReasoningRidesItsOwnFieldAndIsNeverSettled() async throws {
        let session = "gguf-managed-reasoning-\(UUID().uuidString)"
        let query = "为什么 reasoning 不进入结算"
        let reasoningText = "先核对隔离边界，再决定字段归属。"
        let answer = "因为结算只承认答案内容。"
        let stream: [String] = [
            #"{"choices":[{"delta":{"reasoning_content":"先核对隔离边界，"}}]}"#,
            #"{"choices":[{"delta":{"reasoning_content":"再决定字段归属。"}}]}"#,
            #"{"choices":[{"delta":{"content":"因为结算只承认答案内容。"},"finish_reason":"stop"}]}"#,
            #"{"choices":[],"usage":{"prompt_tokens":8,"completion_tokens":9}}"#,
        ]
        try await withManagedEntry(.sse(stream)) { port, _, _ in
            let outcome = try await sendChat(to: port, session: session, query: query)
            XCTAssertEqual(outcome.status, 200)
            let message = try XCTUnwrap(assistantMessage(outcome.body))
            XCTAssertEqual(message["content"] as? String, answer)
            XCTAssertEqual(
                message["reasoning_content"] as? String, reasoningText,
                "the engine's reasoning is exposed verbatim on its own field")
            XCTAssertNil(
                outcome.body["simigo"],
                "reasoning exposure alone does not change a finished turn's verdict")
        }

        let db = try ESISDatabase(url: ManagedPaths.databaseURL)
        let messages = try db.listChatMessages(sessionID: session)
        XCTAssertEqual(messages.map(\.role), ["user", "assistant"])
        XCTAssertEqual(
            messages.last?.content, answer,
            "the ledger stores the answer, never the reasoning")
        XCTAssertFalse(
            messages.contains { $0.content.contains(reasoningText) },
            "reasoning text must not reach the conversation ledger")

        let answered = try XCTUnwrap(
            db.answeredDemand(sessionID: session, query: query),
            "a complete answer still settles; only the reasoning is withheld")
        XCTAssertEqual(
            try db.settlementReceipt(answered.answerSettlementID)?.validity, "valid")

        let loop = InformationLoop(database: db)
        let resolution = try loop.resolve(
            .init(
                sessionID: session, query: query, includeChat: true,
                chatSessionIDs: [session]))
        let retrieved = resolution.hits.map(\.lineText).joined(separator: "\n")
        XCTAssertTrue(retrieved.contains(answer), "the answer stays retrievable")
        XCTAssertFalse(
            retrieved.contains(reasoningText),
            "reasoning must not enter the retrieval index")
    }

    /// Streaming carries reasoning as its own delta field, interleaved in wire
    /// order and disjoint from every `content` delta.
    @MainActor
    func testGGUFStreamingReasoningIsAnIndependentDeltaField() async throws {
        let session = "gguf-managed-reasoning-stream-\(UUID().uuidString)"
        let query = "流式下 reasoning 走哪里"
        let reasoningText = "先想一步。再想一步。"
        let answer = "走独立的 delta 字段。"
        let stream: [String] = [
            #"{"choices":[{"delta":{"reasoning_content":"先想一步。"},"finish_reason":null}]}"#,
            #"{"choices":[{"delta":{"reasoning_content":"再想一步。"},"finish_reason":null}]}"#,
            #"{"choices":[{"delta":{"content":"走独立的 delta 字段。"},"finish_reason":"stop"}]}"#,
            #"{"choices":[],"usage":{"prompt_tokens":6,"completion_tokens":8}}"#,
        ]
        try await withManagedEntry(.sse(stream)) { port, _, _ in
            let (status, data) = try await sendChatRaw(
                to: port, session: session, query: query, stream: true)
            XCTAssertEqual(status, 200)
            let deltas = streamDeltas(data)
            let reasoning = deltas.compactMap { $0["reasoning_content"] as? String }
                .joined()
            let content = deltas.compactMap { $0["content"] as? String }.joined()
            XCTAssertEqual(reasoning, reasoningText)
            XCTAssertEqual(content, answer)
            for delta in deltas where delta["reasoning_content"] != nil {
                XCTAssertNil(
                    delta["content"],
                    "a reasoning delta must not also carry answer text")
            }
            XCTAssertTrue(
                String(decoding: data, as: UTF8.self).contains("data: [DONE]"))
        }
    }

    /// The retention bound is independent of the answer: past 64K characters
    /// the stream keeps a prefix, marks the field truncated, and leaves the
    /// answer and its termination verdict untouched.
    @MainActor
    func testGGUFReasoningOverflowIsTruncatedAndMarked() async throws {
        let session = "gguf-managed-reasoning-cap-\(UUID().uuidString)"
        let query = "很长的思考"
        let reasoning = String(repeating: "想", count: 70_000)
        let answer = "简短答案。"
        let reasoningLine = try XCTUnwrap(String(
            data: JSONSerialization.data(withJSONObject: [
                "choices": [["delta": ["reasoning_content": reasoning]]],
            ]),
            encoding: .utf8))
        let answerLine = #"{"choices":[{"delta":{"content":"简短答案。"},"finish_reason":"stop"}]}"#
        try await withManagedEntry(.sse([reasoningLine, answerLine])) { port, _, _ in
            let outcome = try await sendChat(to: port, session: session, query: query)
            XCTAssertEqual(outcome.status, 200)
            let message = try XCTUnwrap(assistantMessage(outcome.body))
            XCTAssertEqual(message["content"] as? String, answer)
            XCTAssertEqual(
                (message["reasoning_content"] as? String)?.count,
                HTTPServer.maxReasoningChars,
                "only the declared bound is retained")
            let simigo = try XCTUnwrap(outcome.body["simigo"] as? [String: Any])
            let marker = try XCTUnwrap(simigo["reasoning"] as? [String: Any])
            XCTAssertEqual(marker["truncated"] as? Bool, true)
            XCTAssertEqual(
                marker["limit_chars"] as? Int, HTTPServer.maxReasoningChars)
            XCTAssertEqual(
                ((outcome.body["choices"] as? [[String: Any]])?.first)?["finish_reason"]
                    as? String,
                "stop",
                "the answer's own verdict is not rewritten by reasoning retention")
        }
    }

    /// A reused answer is stored without its reasoning, so the replay must not
    /// invent a field for it.
    @MainActor
    func testReusedAnswerDoesNotFabricateReasoning() async throws {
        let session = "gguf-managed-reasoning-reuse-\(UUID().uuidString)"
        let query = "复用的时候还带 reasoning 吗"
        let stream: [String] = [
            #"{"choices":[{"delta":{"reasoning_content":"这是一次性的推理。"}}]}"#,
            #"{"choices":[{"delta":{"content":"不带。"},"finish_reason":"stop"}]}"#,
            #"{"choices":[],"usage":{"prompt_tokens":5,"completion_tokens":3}}"#,
        ]
        try await withManagedEntry(.sse(stream)) { port, _, _ in
            let first = try await sendChat(to: port, session: session, query: query)
            XCTAssertEqual(first.status, 200)
            XCTAssertEqual(
                assistantMessage(first.body)?["reasoning_content"] as? String,
                "这是一次性的推理。")

            let second = try await sendChat(to: port, session: session, query: query)
            XCTAssertEqual(second.status, 200)
            XCTAssertEqual(assistantContent(second.body), "不带。")
            let simigo = try XCTUnwrap(second.body["simigo"] as? [String: Any])
            XCTAssertEqual(simigo["answer_reuse"] as? Bool, true)
            XCTAssertNil(
                assistantMessage(second.body)?["reasoning_content"],
                "the replay has no engine reasoning and must not fabricate one")
        }
    }
}
