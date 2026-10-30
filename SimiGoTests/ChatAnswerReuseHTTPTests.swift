import Foundation
import Network
import XCTest
import LOCALBCore
import SimiGoRuntimeContract

@testable import SimiGo

/// 「可以复用就不调用模型」 at the OpenAI-compatible CHAT wire, streaming form.
/// Most agents stream by default, so the short-circuit only being proven on the
/// non-streaming chat path would leave the zero-model-call behaviour unverified
/// for the shape those agents actually use.
///
/// Every assertion goes through the real dispatch:
///
///   signed HTTPS POST /v1/chat/completions (stream: true)
///     -> HTTPServer.route -> handleChatCompletionsStreaming
///     -> prepareInformationTurn (real ES demand + IS resolve)
///     -> reusableAnswer gate (settlement validity + producer identity)
///     -> serveReusedAnswerStream (one content chunk + stop + [DONE])
///
/// The only substituted component is generation (a counter, never a model).
///
/// Runs only with the three isolated roots injected (`SIMIGO_HOME`,
/// `SIMIGO_CACHE_ROOT`, `SIMIGO_STATE_GRAPH_STORE`); otherwise XCTSkip.
final class ChatAnswerReuseHTTPTests: XCTestCase {

    private let port = 59_374

    private var isolationRoot: URL!
    private var modelPath: String!
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
        let raw: Data
        let generate: Int

        var sse: String { String(decoding: raw, as: UTF8.self) }

        /// The `simigo` block that marks a reused answer, if the stream carried one.
        var reuse: [String: Any]? {
            for line in sse.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("data:") else { continue }
                let payload = String(trimmed.dropFirst("data:".count))
                    .trimmingCharacters(in: .whitespaces)
                guard payload.hasPrefix("{"),
                      let data = payload.data(using: .utf8),
                      let object = (try? JSONSerialization.jsonObject(with: data))
                        as? [String: Any],
                      let block = object["simigo"] as? [String: Any]
                else { continue }
                return block
            }
            return nil
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
            .appendingPathComponent("SimiGoChatAnswerReuse-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"model_type":"chat-answer-reuse-http-model-free-stand-in"}"#.utf8)
            .write(to: dir.appendingPathComponent("tokenizer.adapter.json"))
        modelPath = dir.path

        host = try LOCALBAuthorizedE2E.makeHost()

        let stub = Stub()
        stub.text = "CHAT-SETTLED-ANSWER-91C"
        self.stub = stub
    }

    override func tearDown() {
        if let modelPath { try? FileManager.default.removeItem(atPath: modelPath) }
        stub = nil
        host = nil
        super.tearDown()
    }

    // MARK: - Server + real authorized request

    @MainActor
    private func withServer(_ run: () async throws -> Void) async throws {
        let stub = self.stub!
        let identity = SimiGoProducerIdentity.identity(fromPath: modelPath)
        let server = HTTPServer(
            port: port,
            modelId: "chat-answer-reuse-http-test",
            generateHandler: { _, _, _, _, _, _, _, onChunk, _ in
                stub.bump()
                onChunk(stub.text)
                return GenerationResult(text: stub.text, usage: nil, completion: .complete)
            },
            forkBranchHandler: { _, _, _, target in
                SessionCacheMetadata(
                    storageKey: "t/\(target)", modelId: "chat-answer-reuse-http-test",
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
    private func dispatch(session: String, input: String) async throws -> Outcome {
        let stub = self.stub!
        let body: [String: Any] = [
            "model": "chat-answer-reuse-http-test",
            "messages": [["role": "user", "content": input]],
            "session_id": session,
            "stream": true,
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        var lastError: Error?
        var responseData: Data?
        var httpResponse: HTTPURLResponse?
        for _ in 0..<3 {
            do {
                let result = try await LOCALBAuthorizedE2E.send(
                    host: host, port: port, method: "POST",
                    path: "/v1/chat/completions",
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
        return Outcome(
            status: sent.statusCode, raw: responseData ?? Data(), generate: stub.generate)
    }

    // MARK: - Exact repeat is served with zero model calls on the event wire

    @MainActor
    func testStreamingExactRepeatIsServedWithoutModelCall() async throws {
        let session = "chat-reuse-stream-\(UUID().uuidString)"

        try await withServer {
            let first = try await dispatch(session: session, input: "where is the vault")
            XCTAssertEqual(first.status, 200, first.sse)
            XCTAssertEqual(first.generate, 1, "the first turn generates")
            XCTAssertTrue(first.sse.contains("CHAT-SETTLED-ANSWER-91C"),
                          "the generated text reaches the client as a delta")
            XCTAssertTrue(first.sse.contains("data: [DONE]"), "the stream terminates")
            XCTAssertNil(first.reuse, "a generated turn is not a reuse")

            let store = ExecutionStateGraphStore()
            let db = try XCTUnwrap(store.esis)
            let stateAfterFirst = try db.currentChatStateID(sessionID: session)
            let settlementsAfterFirst = try db.readSettlementReceipts().count

            let second = try await dispatch(session: session, input: "where is the vault")
            XCTAssertEqual(second.status, 200, second.sse)
            XCTAssertEqual(second.generate, 1, "a streaming exact repeat must not call the model")

            let block = try XCTUnwrap(second.reuse, "reuse is reported on the stream")
            XCTAssertEqual(block["answer_reuse"] as? Bool, true)
            XCTAssertEqual(block["model_calls"] as? Int, 0)
            let demandID = try XCTUnwrap(block["demand_id"] as? String)
            let settlementID = try XCTUnwrap(block["settlement_id"] as? String)
            XCTAssertEqual(block["source_state_id"] as? String, stateAfterFirst,
                           "the source is the state that produced the answer")
            XCTAssertTrue(second.sse.contains("CHAT-SETTLED-ANSWER-91C"),
                          "the settled text is streamed to the client")
            XCTAssertTrue(second.sse.contains("\"finish_reason\":\"stop\""),
                          "a reuse terminates with a stop chunk")
            XCTAssertTrue(second.sse.contains("data: [DONE]"), "the reuse stream closes")

            XCTAssertEqual(try db.currentChatStateID(sessionID: session), stateAfterFirst,
                           "serving a reused answer is a read: it creates no ES state")
            XCTAssertEqual(try db.readSettlementReceipts().count, settlementsAfterFirst,
                           "serving a reused answer writes no new settlement")

            let event = try XCTUnwrap(db.informationReuseEvent(demandID: demandID))
            XCTAssertEqual(event.sourceSettlementID, settlementID)
            XCTAssertEqual(event.modelCalls, 0)

            // A different question is not an exact repeat and still generates.
            let third = try await dispatch(session: session, input: "where is the anvil")
            XCTAssertEqual(third.status, 200, third.sse)
            XCTAssertEqual(third.generate, 2, "a different question runs the ordinary path")
            XCTAssertNil(third.reuse)
        }
    }
}
