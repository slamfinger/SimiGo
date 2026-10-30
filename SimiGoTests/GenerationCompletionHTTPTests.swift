import Foundation
import Network
import XCTest
import LOCALBCore
import SimiGoRuntimeContract

@testable import SimiGo

/// T-1 acceptance: an answer that never finished is never presented — and never
/// registered — as one that did.
///
/// The defect was that `GenerationResult` carried text but no verdict. When the
/// generation budget ran out, the engine returned a half sentence, the wire said
/// `status: completed` / `finish_reason: stop`, and the same half sentence was
/// settled into the Information Space, so every later repeat of that question
/// was served the truncated text with zero model calls.
///
/// The fix is one channel, asserted here end to end through the real dispatch:
///
///   engine termination reason
///     -> GenerationResult.completion          (no default value: a producer
///        that cannot say how generation ended has to say so)
///     -> wire status / finish_reason          (Responses: incomplete +
///        incomplete_details.reason; Chat & Completions have no incomplete
///        status, so `length` plus a `simigo` block naming the exact cause)
///     -> settlement gate                      (only `.complete` may settle)
///     -> Information Space reuse gate         (nothing unsettled can be served)
///
/// Every request goes through the signed product entry
/// (`HTTPServer.route -> handleResponses/handleChat/handleTextCompletions`);
/// the only substituted component is generation, a counter plus a declared
/// termination reason — never a model.
///
/// Runs only with the three isolated roots injected (`SIMIGO_HOME`,
/// `SIMIGO_CACHE_ROOT`, `SIMIGO_STATE_GRAPH_STORE`); otherwise XCTSkip.
final class GenerationCompletionHTTPTests: XCTestCase {

    private let port = 59_375

    private var isolationRoot: URL!
    private var modelPath: String!
    private var host: LOCALBAuthorizedE2E.Host!
    private var stub: Stub!

    /// The stand-in engine: what it answers and WHY it stopped answering.
    private final class Stub: @unchecked Sendable {
        private let lock = NSLock()
        private var _generate = 0
        nonisolated(unsafe) var text = ""
        nonisolated(unsafe) var completion: GenerationCompletion = .complete
        func bump() { lock.withLock { _generate += 1 } }
        var generate: Int { lock.withLock { _generate } }
    }

    private struct Outcome {
        let status: Int
        let body: [String: Any]
        let raw: Data
        let generate: Int

        var sse: String { String(decoding: raw, as: UTF8.self) }
        var simigo: [String: Any]? { body["simigo"] as? [String: Any] }

        /// The Responses wire's own completeness field.
        var responseStatus: String? { body["status"] as? String }

        var incompleteReason: String? {
            (body["incomplete_details"] as? [String: Any])?["reason"] as? String
        }

        var outputText: String? {
            guard let output = body["output"] as? [[String: Any]],
                  let content = output.first?["content"] as? [[String: Any]]
            else { return nil }
            return content.first?["text"] as? String
        }

        var finishReason: String? {
            ((body["choices"] as? [[String: Any]])?.first)?["finish_reason"] as? String
        }

        var choiceText: String? {
            ((body["choices"] as? [[String: Any]])?.first)?["text"] as? String
        }

        var messageContent: String? {
            guard let choice = (body["choices"] as? [[String: Any]])?.first,
                  let message = choice["message"] as? [String: Any]
            else { return nil }
            return message["content"] as? String
        }
    }

    private struct Ledger: Equatable {
        let states: Int
        /// UUID-keyed settlement receipts — the class of row a later turn can
        /// reuse as an answer. See `ledger()`.
        let answers: Int
    }

    /// An absent or JSON-null `incomplete_details` — the shape of a finished turn.
    private func assertNoIncompleteDetails(
        _ outcome: Outcome, _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let value = outcome.body["incomplete_details"]
        XCTAssertTrue(
            value == nil || value is NSNull, message,
            file: file, line: line)
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

        // An engine stand-in whose identity is stable across the server restarts
        // a test performs, so producer identity can never be what blocks a reuse.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimiGoCompletion-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"model_type":"generation-completion-http-stand-in"}"#.utf8)
            .write(to: dir.appendingPathComponent("tokenizer.adapter.json"))
        modelPath = dir.path

        host = try LOCALBAuthorizedE2E.makeHost()
        let stub = Stub()
        stub.text = "ANSWER-7C2"
        self.stub = stub
    }

    override func tearDown() {
        if let modelPath { try? FileManager.default.removeItem(atPath: modelPath) }
        stub = nil
        host = nil
        super.tearDown()
    }

    // MARK: - Server + real authorized requests

    /// One server per test. `completion` is re-read on every call, so a test can
    /// flip the engine's verdict between turns — the only knob T-1 needs.
    @MainActor
    private func withServer(_ run: () async throws -> Void) async throws {
        let stub = stub!
        let identity = SimiGoProducerIdentity.identity(fromPath: modelPath)
        let server = HTTPServer(
            port: port,
            modelId: "generation-completion-http-test",
            generateHandler: { _, _, _, _, _, _, _, onChunk, _ in
                stub.bump()
                onChunk(stub.text)
                return GenerationResult(
                    text: stub.text, usage: nil, completion: stub.completion)
            },
            forkBranchHandler: { _, _, _, target in
                SessionCacheMetadata(
                    storageKey: "t/\(target)", modelId: "generation-completion-http-test",
                    savedAt: Date(), history: [])
            },
            deleteBranchHandler: { _, _, _ in },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { true },
            informationTurnProducer: {
                InformationTurnProducer(modelIdentity: identity.model, identity: identity)
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
    private func dispatch(
        _ body: [String: Any],
        path: String = "/v1/responses"
    ) async throws -> Outcome {
        let stub = stub!
        let payload = try JSONSerialization.data(withJSONObject: body)
        var lastError: Error?
        var responseData: Data?
        var httpResponse: HTTPURLResponse?
        for _ in 0..<3 {
            do {
                let result = try await LOCALBAuthorizedE2E.send(
                    host: host, port: port, method: "POST",
                    path: path,
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

    private func responsesBody(
        session: String, input: String, stream: Bool = false
    ) -> [String: Any] {
        [
            "model": "generation-completion-http-test",
            "input": input,
            "session_id": session,
            "stream": stream,
        ]
    }

    private func chatBody(
        session: String, input: String, stream: Bool = false
    ) -> [String: Any] {
        [
            "model": "generation-completion-http-test",
            "messages": [["role": "user", "content": input]],
            "session_id": session,
            "stream": stream,
        ]
    }

    private func completionsBody(prompt: String) -> [String: Any] {
        [
            "model": "generation-completion-http-test",
            "prompt": prompt,
            "max_tokens": 32,
        ]
    }

    /// The authoritative store, read on the row classes that carry a verdict:
    /// `states` (an ES state was settled) and `answers` (a settlement a later
    /// turn may reuse). `count("settlements")` is deliberately not used — that
    /// table also carries one state-less `is-retrieval:<demand>` row per
    /// resolved demand, and a reuse turn re-resolves its demand against the
    /// citable answers the previous turn just settled, so a new fingerprint
    /// means a new IS row without settling anything. `answers` is the same
    /// basis `ResponsesAnswerReuseHTTPTests` uses.
    @MainActor
    private func ledger() throws -> Ledger {
        let db = try XCTUnwrap(ExecutionStateGraphStore().esis)
        return Ledger(
            states: try db.count("execution_states"),
            answers: try db.readSettlementReceipts().count)
    }

    // MARK: - 1) Budget cap: incomplete on the wire, absent from the store

    /// The T-1 case itself. A capped answer is told to the client as unfinished
    /// and registers nothing, so the very next turn of the same question runs the
    /// model again instead of serving the truncated text.
    @MainActor
    func testBudgetCappedResponsesIsIncompleteAndNeverReusable() async throws {
        let session = "completion-capped-\(UUID().uuidString)"
        let warm = "what is warm"
        let question = "what is capped"

        try await withServer {
            // A settled turn first: the session demonstrably can produce reusable
            // answers, so the reuse failure below cannot be blamed on the gate
            // being off or on an unwired store.
            stub.completion = .complete
            stub.text = "WARM-ANSWER-1"
            let primer = try await dispatch(responsesBody(session: session, input: warm))
            XCTAssertEqual(primer.status, 200, primer.sse)
            XCTAssertEqual(primer.responseStatus, "completed")
            assertNoIncompleteDetails(primer, "a finished turn claims no incompleteness")

            let before = try ledger()

            // Same engine, same entry, but generation ran out of budget.
            stub.completion = .capped
            stub.text = "TRUNCATED-MID-SENTENCE"
            let capped = try await dispatch(responsesBody(session: session, input: question))
            XCTAssertEqual(capped.status, 200, capped.sse)
            XCTAssertEqual(capped.generate, 2)
            XCTAssertEqual(
                capped.responseStatus, "incomplete",
                "a budget-capped answer is not a completed one: \(capped.body)")
            XCTAssertEqual(capped.incompleteReason, "max_output_tokens")
            XCTAssertEqual(capped.outputText, "TRUNCATED-MID-SENTENCE",
                           "the partial text is still served")
            XCTAssertNil(capped.simigo, "incomplete is the Responses' own channel")

            let db = try XCTUnwrap(ExecutionStateGraphStore().esis)
            XCTAssertNil(
                try db.answeredDemand(sessionID: session, query: question),
                "a capped turn registered no answered demand")
            let afterCapped = try ledger()
            XCTAssertEqual(afterCapped.states, before.states,
                           "a capped turn settles no ES state")
            XCTAssertEqual(afterCapped.answers, before.answers,
                           "a capped turn settles no reusable answer")

            // The engine finishes this time. The turn must be generated, not
            // served from the capped text settled above — which is the exact
            // behaviour the defect produced.
            stub.completion = .complete
            stub.text = "FULL-ANSWER-2"
            let finished = try await dispatch(responsesBody(session: session, input: question))
            XCTAssertEqual(finished.status, 200, finished.sse)
            XCTAssertEqual(finished.responseStatus, "completed")
            XCTAssertEqual(
                finished.generate, 3,
                "the question after a capped turn runs the model again")
            XCTAssertEqual(finished.outputText, "FULL-ANSWER-2")

            let answered = try XCTUnwrap(
                db.answeredDemand(sessionID: session, query: question),
                "the completed turn is the first one to answer this demand")
            XCTAssertEqual(
                try ledger().states - afterCapped.states, 1,
                "exactly the completed turn settled a state")

            // And reuse works in this very scope: the third ask is served by the
            // settlement from the second, proving turn 2 above was blocked by the
            // completeness gate and not by reuse being unavailable.
            let repeatTurn = try await dispatch(responsesBody(session: session, input: question))
            XCTAssertEqual(repeatTurn.status, 200, repeatTurn.sse)
            XCTAssertEqual(repeatTurn.generate, 3, "a settled answer is served without the model")
            XCTAssertEqual(repeatTurn.simigo?["answer_reuse"] as? Bool, true)
            XCTAssertEqual(repeatTurn.simigo?["model_calls"] as? Int, 0)
            XCTAssertEqual(repeatTurn.simigo?["settlement_id"] as? String,
                           answered.answerSettlementID)
            XCTAssertEqual(repeatTurn.outputText, "FULL-ANSWER-2")
        }
    }

    // MARK: - 2) Natural end keeps the ordinary contract

    /// The other half of the same gate: `.complete` still settles and still
    /// serves a repeat with zero model calls, so T-1 cannot be fixed by turning
    /// reuse off.
    @MainActor
    func testNaturallyEndedTurnCompletesAndIsReusable() async throws {
        let session = "completion-natural-\(UUID().uuidString)"
        let question = "what is natural"

        try await withServer {
            stub.completion = .complete
            stub.text = "NATURAL-ANSWER"
            let first = try await dispatch(responsesBody(session: session, input: question))
            XCTAssertEqual(first.status, 200, first.sse)
            XCTAssertEqual(first.responseStatus, "completed")
            XCTAssertNil(first.incompleteReason)

            let db = try XCTUnwrap(ExecutionStateGraphStore().esis)
            let answered = try XCTUnwrap(
                db.answeredDemand(sessionID: session, query: question),
                "a finished answer is registered as settled")
            XCTAssertEqual(try db.settlementReceipt(answered.answerSettlementID)?.validity, "valid")

            let stateID = try db.currentChatStateID(sessionID: session)
            let before = try ledger()

            let second = try await dispatch(responsesBody(session: session, input: question))
            XCTAssertEqual(second.status, 200, second.sse)
            XCTAssertEqual(second.responseStatus, "completed")
            XCTAssertEqual(second.generate, 1, "the exact repeat must not call the model")
            XCTAssertEqual(second.simigo?["model_calls"] as? Int, 0)
            XCTAssertEqual(second.simigo?["source_state_id"] as? String, stateID)
            XCTAssertEqual(
                second.simigo?["settlement_id"] as? String, answered.answerSettlementID,
                "the repeat is served by the answer the first turn settled")
            XCTAssertEqual(try ledger(), before, "serving a reuse settles no new answer")
        }
    }

    // MARK: - 3) Cancelled and unconfirmed are incomplete too

    /// Both remaining non-complete verdicts. A real cancellation returns before
    /// this point; here the stand-in reports the reason the engine reports, so
    /// the gate — not the transport — is what is under test. Absence of a
    /// termination signal is the more dangerous case: it used to be indistinguishable
    /// from success.
    @MainActor
    func testUnfinishedVerdictsAreIncompleteAndUnsettled() async throws {
        let cases: [(GenerationCompletion, String)] = [
            (.cancelled, "generation_cancelled"),
            (.unconfirmed, "generation_unconfirmed"),
        ]
        let session = "completion-unfinished-\(UUID().uuidString)"

        try await withServer {
            for (completion, expectedReason) in cases {
                let question = "what is \(completion.wireName)"
                let before = try ledger()
                let callsBefore = stub.generate

                stub.completion = completion
                stub.text = "PARTIAL-\(completion.wireName)"
                let turn = try await dispatch(responsesBody(session: session, input: question))
                XCTAssertEqual(turn.status, 200, turn.sse)
                XCTAssertEqual(turn.generate, callsBefore + 1)
                XCTAssertEqual(
                    turn.responseStatus, "incomplete",
                    "\(completion.wireName) must not claim completion")
                XCTAssertEqual(turn.incompleteReason, expectedReason)

                let db = try XCTUnwrap(ExecutionStateGraphStore().esis)
                XCTAssertNil(
                    try db.answeredDemand(sessionID: session, query: question),
                    "\(completion.wireName) registered no reusable answer")
                let after = try ledger()
                XCTAssertEqual(
                    after.states, before.states,
                    "\(completion.wireName) settled no ES state")
                XCTAssertEqual(
                    after.answers, before.answers,
                    "\(completion.wireName) settled no reusable answer")

                // Asking again runs the engine once more: there is nothing to
                // serve, and the product never reports a reuse it did not perform.
                let repeatTurn = try await dispatch(responsesBody(session: session, input: question))
                XCTAssertEqual(repeatTurn.responseStatus, "incomplete")
                XCTAssertEqual(
                    repeatTurn.generate, callsBefore + 2,
                    "\(completion.wireName) is never served as a settled answer")
                XCTAssertNil(repeatTurn.simigo)
            }
        }
    }

    // MARK: - 4) Chat has no incomplete status: length + cause, never stop

    @MainActor
    func testCappedChatNonStreamingSaysLengthAndDoesNotSettle() async throws {
        let session = "completion-chat-\(UUID().uuidString)"
        let question = "what is chat capped"

        try await withServer {
            stub.completion = .complete
            stub.text = "CHAT-COMPLETE"
            let primer = try await dispatch(
                chatBody(session: session, input: "what is chat warm"),
                path: "/v1/chat/completions")
            XCTAssertEqual(primer.status, 200, primer.sse)
            XCTAssertEqual(primer.finishReason, "stop", "a finished turn still claims stop")
            XCTAssertNil(primer.simigo, "the cause block appears only when the turn is unfinished")

            let before = try ledger()

            stub.completion = .capped
            stub.text = "CHAT-TRUNCATED"
            let capped = try await dispatch(
                chatBody(session: session, input: question),
                path: "/v1/chat/completions")
            XCTAssertEqual(capped.status, 200, capped.sse)
            XCTAssertEqual(
                capped.finishReason, "length",
                "a capped chat turn must not be reported as `stop`: \(capped.body)")
            XCTAssertEqual(capped.messageContent, "CHAT-TRUNCATED")
            let block = try XCTUnwrap(capped.simigo, "the wire cannot say why, so simigo does")
            XCTAssertEqual(block["completion"] as? String, "capped")
            XCTAssertEqual(block["settlement_written"] as? Bool, false)

            let db = try XCTUnwrap(ExecutionStateGraphStore().esis)
            XCTAssertNil(try db.answeredDemand(sessionID: session, query: question))
            let after = try ledger()
            XCTAssertEqual(after.states, before.states, "a capped chat turn settles no ES state")
            XCTAssertEqual(
                after.answers, before.answers,
                "a capped chat turn settles no reusable answer")

            // History continuity survives: the truncated text stays in the
            // conversation, it is simply never a settled answer.
            let transcript = try db.listChatMessages(sessionID: session)
            XCTAssertTrue(
                transcript.contains { $0.role == "assistant" && $0.content.contains("CHAT-TRUNCATED") },
                "the served text remains part of the transcript")

            stub.completion = .complete
            stub.text = "CHAT-FULL"
            let finished = try await dispatch(
                chatBody(session: session, input: question),
                path: "/v1/chat/completions")
            XCTAssertEqual(finished.finishReason, "stop")
            XCTAssertEqual(finished.generate, 3, "the capped turn left nothing to reuse")
            XCTAssertNotNil(try db.answeredDemand(sessionID: session, query: question))
        }
    }

    // MARK: - 5) The streaming chat wire carries the same verdict

    @MainActor
    func testCappedChatStreamTerminatesWithLength() async throws {
        let session = "completion-chat-stream-\(UUID().uuidString)"

        try await withServer {
            stub.completion = .capped
            stub.text = "STREAM-TRUNCATED"
            let turn = try await dispatch(
                chatBody(session: session, input: "what is stream capped", stream: true),
                path: "/v1/chat/completions")
            XCTAssertEqual(turn.status, 200, turn.sse)
            XCTAssertTrue(
                turn.sse.contains("\"finish_reason\":\"length\""),
                "the terminal chunk says not-finished: \(turn.sse)")
            XCTAssertFalse(turn.sse.contains("\"finish_reason\":\"stop\""))
            XCTAssertTrue(turn.sse.contains("\"completion\":\"capped\""))
            XCTAssertTrue(turn.sse.contains("\"settlement_written\":false"))
            XCTAssertTrue(turn.sse.contains("data: [DONE]"), "and still terminates the stream")

            let db = try XCTUnwrap(ExecutionStateGraphStore().esis)
            XCTAssertNil(
                try db.answeredDemand(sessionID: session, query: "what is stream capped"))
        }
    }

    // MARK: - 6) Completions keeps its boundary and stops claiming stop

    @MainActor
    func testCappedTextCompletionReportsLength() async throws {
        try await withServer {
            stub.completion = .complete
            let done = try await dispatch(completionsBody(prompt: "a finished prompt"),
                                         path: "/v1/completions")
            XCTAssertEqual(done.status, 200, done.sse)
            XCTAssertEqual(done.finishReason, "stop")
            let marker = try XCTUnwrap(done.simigo, "the passthrough always declares itself")
            XCTAssertEqual(marker["managed"] as? Bool, false)
            XCTAssertEqual(marker["reason"] as? String, "legacy_text_completions")
            XCTAssertEqual(
                marker.keys.count, 2,
                "a finished passthrough carries exactly the declared marker: \(marker)")

            stub.completion = .capped
            stub.text = "COMPLETION-TRUNCATED"
            let capped = try await dispatch(completionsBody(prompt: "a capped prompt"),
                                            path: "/v1/completions")
            XCTAssertEqual(capped.status, 200, capped.sse)
            XCTAssertEqual(
                capped.finishReason, "length",
                "a capped passthrough must not claim a normal stop either")
            XCTAssertEqual(capped.choiceText, "COMPLETION-TRUNCATED")
            let block = try XCTUnwrap(capped.simigo)
            XCTAssertEqual(block["managed"] as? Bool, false, "still an unmanaged entry")
            XCTAssertEqual(block["completion"] as? String, "capped")
            XCTAssertEqual(block["incomplete_reason"] as? String, "max_output_tokens")
        }
    }

    // MARK: - 7) The streaming Responses chain ends with response.incomplete

    @MainActor
    func testCappedResponsesStreamEndsWithIncompleteEvent() async throws {
        let session = "completion-stream-\(UUID().uuidString)"

        try await withServer {
            stub.completion = .capped
            stub.text = "STREAM-TRUNCATED"
            let turn = try await dispatch(
                responsesBody(session: session, input: "what is stream capped", stream: true))
            XCTAssertEqual(turn.status, 200, turn.sse)
            let sse = turn.sse
            XCTAssertTrue(sse.contains("response.created"), "the chain still opens: \(sse)")
            XCTAssertTrue(sse.contains("STREAM-TRUNCATED"), "the partial text is streamed")
            XCTAssertTrue(
                sse.contains("\"type\":\"response.incomplete\""),
                "the terminal event is the incomplete one")
            XCTAssertTrue(sse.contains("\"status\":\"incomplete\""))
            XCTAssertTrue(sse.contains("\"reason\":\"max_output_tokens\""))
            XCTAssertFalse(sse.contains("response.completed"), "a capped stream never completes")

            let db = try XCTUnwrap(ExecutionStateGraphStore().esis)
            XCTAssertNil(
                try db.answeredDemand(sessionID: session, query: "what is stream capped"))
        }
    }
}
