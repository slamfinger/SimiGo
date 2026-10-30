import Foundation
import Network
import XCTest
import LOCALBCore
import SimiGoRuntimeContract

@testable import SimiGo

/// 「可以复用就不调用模型」 at the REAL product HTTP entry: an exact repeat of a
/// question already answered in this information scope is served from the
/// settled result with ZERO generation calls — on both Responses wire paths,
/// because most Agents stream by default.
///
/// Every assertion goes through the real dispatch:
///
///   signed HTTPS POST /v1/responses
///     -> HTTPServer.route -> handleResponses(Non)Streaming
///     -> prepareInformationTurn (real ES demand + IS resolve)
///     -> reusableAnswer gate (settlement validity + producer identity)
///     -> completed response carrying `simigo.model_calls = 0`
///
/// The only substituted component is generation (a counter, never a model).
///
/// Runs only with the three isolated roots injected (`SIMIGO_HOME`,
/// `SIMIGO_CACHE_ROOT`, `SIMIGO_STATE_GRAPH_STORE`); otherwise XCTSkip.
final class ResponsesAnswerReuseHTTPTests: XCTestCase {

    private let port = 59_372

    private var isolationRoot: URL!
    private var modelPath: String!
    private var otherModelPath: String!
    private var host: LOCALBAuthorizedE2E.Host!
    private var stub: Stub!

    private final class Stub: @unchecked Sendable {
        private let lock = NSLock()
        private var _generate = 0
        nonisolated(unsafe) var text = ""
        func bump() { lock.withLock { _generate += 1 } }
        var generate: Int { lock.withLock { _generate } }
    }

    private struct Outcome {
        let status: Int
        let body: [String: Any]
        let raw: Data
        let generate: Int

        var simigo: [String: Any]? { body["simigo"] as? [String: Any] }

        var outputText: String? {
            guard let output = body["output"] as? [[String: Any]],
                  let content = output.first?["content"] as? [[String: Any]]
            else { return nil }
            return content.first?["text"] as? String
        }
    }

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let home = env["SIMIGO_HOME"], !home.isEmpty,
              let graphStore = env["SIMIGO_STATE_GRAPH_STORE"], !graphStore.isEmpty,
              let cache = env["SIMIGO_CACHE_ROOT"], !cache.isEmpty,
              home.hasPrefix("/"), graphStore.hasPrefix("/"), cache.hasPrefix("/") else {
            throw XCTSkip(
                "isolated roots not injected: run through tools/make_isolated_xctestrun.py "
                + "so no real model or user state is touched")
        }
        isolationRoot = URL(fileURLWithPath: (home as NSString).standardizingPath, isDirectory: true)
        XCTAssertTrue(
            SimiGoPaths.databaseURL.path.hasPrefix(isolationRoot.path),
            "authoritative store resolves outside the isolation root")

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimiGoAnswerReuse-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"model_type":"answer-reuse-http-model-free-stand-in"}"#.utf8)
            .write(to: dir.appendingPathComponent("tokenizer.adapter.json"))
        modelPath = dir.path

        // A second engine whose tokenizer artifacts differ: its identity is
        // distinct, which is what a swapped local model looks like to ES/IS.
        let other = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimiGoAnswerReuse-other-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try Data(#"{"model_type":"cross-model-stand-in-B"}"#.utf8)
            .write(to: other.appendingPathComponent("tokenizer.adapter.json"))
        otherModelPath = other.path

        host = try LOCALBAuthorizedE2E.makeHost()
        let stub = Stub()
        stub.text = "SETTLED-ANSWER-7F3"
        self.stub = stub
    }

    override func tearDown() {
        if let modelPath { try? FileManager.default.removeItem(atPath: modelPath) }
        if let otherModelPath { try? FileManager.default.removeItem(atPath: otherModelPath) }
        stub = nil
        host = nil
        super.tearDown()
    }

    // MARK: - Server + real authorized requests

    /// One server per test: the listener is started once and every request in
    /// the test goes through the real signed HTTP entry. `identityPath` and
    /// `stub` let a test stand up a SECOND engine (a swapped local model), so
    /// identity is exercised through the same real dispatch.
    @MainActor
    private func withServer(
        identityPath: String? = nil,
        stub activeStub: Stub? = nil,
        _ run: () async throws -> Void
    ) async throws {
        let stub = activeStub ?? self.stub!
        self.stub = stub
        let identity = SimiGoProducerIdentity.identity(fromPath: identityPath ?? modelPath)
        let server = HTTPServer(
            port: port,
            modelId: "answer-reuse-http-test",
            generateHandler: { _, _, _, _, _, _, _, onChunk, _ in
                stub.bump()
                onChunk(stub.text)
                return GenerationResult(text: stub.text, usage: nil, completion: .complete)
            },
            forkBranchHandler: { _, _, _, target in
                SessionCacheMetadata(
                    storageKey: "t/\(target)", modelId: "answer-reuse-http-test",
                    savedAt: Date(), history: [])
            },
            deleteBranchHandler: { _, _, _ in },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { true },
            informationTurnProducer: {
                InformationTurnProducer(
                    modelIdentity: identity.model, identity: identity)
            }
        )
        server.configureLOCALBTransport(identity: host.identity)
        server.configureLOCALBRequestAuthorization(
            coordinator: host.coordinator,
            trustedCheckpoint: host.checkpointProvider)
        try server.start()
        try? await Task.sleep(nanoseconds: 200_000_000)
        defer { server.stop() }
        try await run()
    }

    @MainActor
    private func dispatch(_ body: [String: Any]) async throws -> Outcome {
        let stub = stub!
        let payload = try JSONSerialization.data(withJSONObject: body)
        var lastError: Error?
        var responseData: Data?
        var httpResponse: HTTPURLResponse?
        for _ in 0..<3 {
            do {
                let result = try await LOCALBAuthorizedE2E.send(
                    host: host, port: port, method: "POST",
                    path: "/v1/responses",
                    contentType: "application/json", body: payload)
                responseData = result.0
                httpResponse = result.1
                break
            } catch let error as URLError
            where error.code == .cannotConnectToHost || error.code == .networkConnectionLost {
                lastError = error
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        let sent = try XCTUnwrap(
            httpResponse,
            "authorized request never reached the server: \(String(describing: lastError))")
        let data = responseData ?? Data()
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return Outcome(status: sent.statusCode, body: json, raw: data, generate: stub.generate)
    }

    private func requestBody(session: String, input: String, stream: Bool = false) -> [String: Any] {
        [
            "model": "answer-reuse-http-test",
            "input": input,
            "session_id": session,
            "stream": stream,
        ]
    }

    // MARK: - 1) Non-streaming: exact repeat is served with zero model calls

    @MainActor
    func testExactRepeatIsServedWithoutModelCall() async throws {
        let session = "reuse-session-\(UUID().uuidString)"

        try await withServer {
            let first = try await dispatch(requestBody(session: session, input: "what is alpha"))
            XCTAssertEqual(first.status, 200, String(decoding: first.raw, as: UTF8.self))
            XCTAssertEqual(first.generate, 1, "the first turn generates")
            XCTAssertEqual(first.outputText, "SETTLED-ANSWER-7F3")
            XCTAssertNil(first.body["simigo"], "a generated turn is not a reuse")

            let store = ExecutionStateGraphStore()
            let db = try XCTUnwrap(store.esis)
            let stateAfterFirst = try db.currentChatStateID(sessionID: session)
            let settlementsAfterFirst = try db.readSettlementReceipts().count

            let second = try await dispatch(requestBody(session: session, input: "what is alpha"))
            XCTAssertEqual(second.status, 200, String(decoding: second.raw, as: UTF8.self))
            XCTAssertEqual(second.generate, 1, "an exact repeat must not call the model")
            XCTAssertEqual(second.outputText, "SETTLED-ANSWER-7F3",
                           "the served text is the settled result")

            let block = try XCTUnwrap(second.simigo, "reuse is reported on the wire")
            XCTAssertEqual(block["answer_reuse"] as? Bool, true)
            XCTAssertEqual(block["model_calls"] as? Int, 0)
            let demandID = try XCTUnwrap(block["demand_id"] as? String)
            let settlementID = try XCTUnwrap(block["settlement_id"] as? String)
            XCTAssertEqual(block["source_state_id"] as? String, stateAfterFirst,
                           "the source is the state that produced the answer")

            XCTAssertEqual(try db.currentChatStateID(sessionID: session), stateAfterFirst,
                           "serving a reused answer is a read: it creates no ES state")
            XCTAssertEqual(try db.readSettlementReceipts().count, settlementsAfterFirst,
                           "serving a reused answer writes no new settlement")

            let event = try XCTUnwrap(db.informationReuseEvent(demandID: demandID))
            XCTAssertEqual(event.sourceSettlementID, settlementID)
            XCTAssertEqual(event.modelCalls, 0)

            // A different question is not an exact repeat and still generates.
            let third = try await dispatch(requestBody(session: session, input: "what is beta"))
            XCTAssertEqual(third.status, 200, String(decoding: third.raw, as: UTF8.self))
            XCTAssertEqual(third.generate, 2, "a different question runs the ordinary path")
            XCTAssertNil(third.body["simigo"])
        }
    }

    // MARK: - 2) Streaming: same zero-call contract on the event wire

    @MainActor
    func testStreamingRepeatIsServedWithoutModelCall() async throws {
        let session = "reuse-stream-\(UUID().uuidString)"

        try await withServer {
            let first = try await dispatch(
                requestBody(session: session, input: "where is the exit"))
            XCTAssertEqual(first.status, 200, String(decoding: first.raw, as: UTF8.self))
            XCTAssertEqual(first.generate, 1)

            let second = try await dispatch(
                requestBody(session: session, input: "where is the exit", stream: true))
            XCTAssertEqual(second.status, 200, String(decoding: second.raw, as: UTF8.self))
            XCTAssertEqual(second.generate, 1, "a streaming exact repeat must not call the model")

            let sse = String(decoding: second.raw, as: UTF8.self)
            XCTAssertTrue(sse.contains("response.created"),
                          "the client still sees a full event chain")
            XCTAssertTrue(sse.contains("answer_reuse"), "reuse is reported on the stream")
            XCTAssertTrue(sse.contains("SETTLED-ANSWER-7F3"), "the settled text is streamed")
            XCTAssertTrue(sse.contains("response.completed"),
                          "a reuse terminates with response.completed")
            XCTAssertFalse(sse.contains("response.failed"), "a reuse is not a failure")
        }
    }

    // MARK: - 3) A swapped engine never inherits another engine's answer

    /// Replace the local model and ask the SAME question in the SAME session:
    /// the previous engine's settled result must not be served. The gate checks
    /// producer identity, so this is the product-level form of 「不同模型的结果
    /// 不能直接假定可互换」.
    @MainActor
    func testDifferentProducerIdentityIsNotReused() async throws {
        let session = "reuse-identity-\(UUID().uuidString)"
        let stubA = Stub()
        stubA.text = "MODEL-A-ANSWER"
        let stubB = Stub()
        stubB.text = "MODEL-B-ANSWER"

        try await withServer(stub: stubA) {
            let first = try await dispatch(
                requestBody(session: session, input: "what is gamma"))
            XCTAssertEqual(first.status, 200, String(decoding: first.raw, as: UTF8.self))
            XCTAssertEqual(first.generate, 1)
            XCTAssertEqual(first.outputText, "MODEL-A-ANSWER")
            XCTAssertNil(first.body["simigo"], "the first turn is a generation")
        }

        // The first listener must be gone before the second binds the port.
        try? await Task.sleep(nanoseconds: 300_000_000)

        try await withServer(identityPath: otherModelPath, stub: stubB) {
            let second = try await dispatch(
                requestBody(session: session, input: "what is gamma"))
            XCTAssertEqual(second.status, 200, String(decoding: second.raw, as: UTF8.self))
            XCTAssertEqual(second.generate, 1,
                           "a different engine must not inherit the settled answer")
            XCTAssertEqual(second.outputText, "MODEL-B-ANSWER",
                           "the turn is answered by the engine now in use")
            XCTAssertNil(second.body["simigo"],
                         "a cross-engine turn is a generation, not a reuse")
        }
    }

    // MARK: - 4) A tool continuation is never served from the settled answer

    /// D-1: after a settled answer, the follow-up that appends the tool output
    /// must reach generation. Before the fix the unchanged user text made the
    /// reuse gate serve the old text, and the tool loop ended without a call.
    ///
    /// The precondition is proven before the continuation is sent: the store
    /// holds an ADVANCED demand for this exact session and question backed by a
    /// valid settlement, and an ordinary repeat is actually served from it with
    /// zero model calls. Only then does the same question in tool-continuation
    /// form have to generate, so a pass can only come from the guard — a gate
    /// that missed fails the repeat assertions instead of passing silently.
    ///
    /// Both Responses wires carry the guard, so both are exercised: each wire
    /// first proves the same question is reusable there, then requires that the
    /// tool-continuation form of it generates.
    @MainActor
    func testToolContinuationIsNotServedFromSettledAnswer() async throws {
        let session = "reuse-tool-\(UUID().uuidString)"
        let question = "what is epsilon"

        try await withServer {
            let first = try await dispatch(requestBody(session: session, input: question))
            XCTAssertEqual(first.status, 200, String(decoding: first.raw, as: UTF8.self))
            XCTAssertEqual(first.generate, 1, "the first turn generates")
            XCTAssertNil(first.simigo, "the first turn is a generation")

            // Precondition 1 — the authoritative store: this exact question is
            // answered in this session by a still-valid settlement.
            let db = try XCTUnwrap(ExecutionStateGraphStore().esis)
            let answered = try XCTUnwrap(
                db.answeredDemand(sessionID: session, query: question),
                "no reusable answer was published for this session and question")
            let receipt = try XCTUnwrap(
                db.settlementReceipt(answered.answerSettlementID))
            XCTAssertEqual(receipt.validity, "valid")

            // Precondition 2 — the gate, through the real dispatch: an ordinary
            // repeat of the same question is served from that settlement with
            // no model call. This is the turn the continuation differs from.
            let repeatTurn = try await dispatch(
                requestBody(session: session, input: question))
            XCTAssertEqual(
                repeatTurn.status, 200,
                String(decoding: repeatTurn.raw, as: UTF8.self))
            XCTAssertEqual(
                repeatTurn.generate, 1,
                "the exact repeat must be served from the settled answer")
            XCTAssertEqual(repeatTurn.simigo?["answer_reuse"] as? Bool, true)
            XCTAssertEqual(repeatTurn.simigo?["model_calls"] as? Int, 0)
            XCTAssertEqual(
                repeatTurn.simigo?["settlement_id"] as? String,
                answered.answerSettlementID,
                "the repeat was served from the settlement checked above")

            // Same session, same question, plus the tool output: that is the
            // only difference from the reused turn above.
            var body = requestBody(session: session, input: question)
            body["input"] = [
                ["role": "user", "content": question],
                ["type": "function_call_output", "call_id": "call-1", "output": "42"],
            ]
            let continuation = try await dispatch(body)
            XCTAssertEqual(
                continuation.status, 200,
                String(decoding: continuation.raw, as: UTF8.self))
            XCTAssertEqual(
                continuation.generate, 2,
                "a tool continuation must reach the model, not the settled text")
            XCTAssertNil(
                continuation.body["simigo"],
                "a tool continuation is not an answer reuse")
            XCTAssertEqual(
                continuation.outputText, "SETTLED-ANSWER-7F3",
                "the turn is generated by the engine in use")

            // The streaming wire, same pair. The stream gate must first be
            // shown to hit this same question, otherwise the streaming
            // continuation below would prove nothing.
            let streamRepeat = try await dispatch(
                requestBody(session: session, input: question, stream: true))
            XCTAssertEqual(
                streamRepeat.status, 200,
                String(decoding: streamRepeat.raw, as: UTF8.self))
            XCTAssertEqual(
                streamRepeat.generate, 2,
                "a streaming exact repeat must not call the model")
            let streamRepeatSSE = String(decoding: streamRepeat.raw, as: UTF8.self)
            XCTAssertTrue(
                streamRepeatSSE.contains("answer_reuse"),
                "the streaming repeat is served from the settled answer: \(streamRepeatSSE)")
            XCTAssertTrue(streamRepeatSSE.contains("response.completed"))

            var streamBody = requestBody(session: session, input: question, stream: true)
            streamBody["input"] = [
                ["role": "user", "content": question],
                ["type": "function_call_output", "call_id": "call-2", "output": "42"],
            ]
            let streamContinuation = try await dispatch(streamBody)
            XCTAssertEqual(
                streamContinuation.status, 200,
                String(decoding: streamContinuation.raw, as: UTF8.self))
            XCTAssertEqual(
                streamContinuation.generate, 3,
                "a streaming tool continuation must reach the model")
            let streamContinuationSSE = String(
                decoding: streamContinuation.raw, as: UTF8.self)
            XCTAssertFalse(
                streamContinuationSSE.contains("answer_reuse"),
                "a streaming tool continuation is not an answer reuse")
            XCTAssertTrue(streamContinuationSSE.contains("response.completed"))
        }
    }
}
