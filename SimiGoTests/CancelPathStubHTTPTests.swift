import XCTest
import Foundation
import LOCALBCore
import SimiGoRuntimeContract

@testable import SimiGo

/// 二.5 T-A（owner 2026-10-29 授权；2026-10-30 ADR 后语义更新）：四类桩层
/// 缺口 + 普通结算对照。
///
/// Every test first proves the target branch was actually entered — the stub's
/// generate closure ran (`generateCount == 1` / `started`), and for the
/// streaming disconnect cases the client has already read the first delta —
/// and only then checks the callback count, the generation-task exit, the
/// post-cancel chunk count and the per-table ES/IS deltas.
///
/// 2026-10-30 ADR: a client disconnect now **detaches** the turn — no cancel
/// callback, no generation cancel, the turn runs to completion and stops at the
/// fail-closed guard before settlement. A2/A4/A5 assert that shape; A3 keeps
/// the server-internal cancel shape.
///
/// Evidence level of this file: control flow and ES/IS rows under a stub engine.
/// It does NOT prove that a real model execution stopped or completed; that is
/// the real-model window's measurement object.
///
/// Answer settlements (`settlements` ids without the `is-retrieval:` prefix)
/// and retrieval rows (`is-retrieval:<demand>` plus their content bindings) are
/// reported as two disjoint classes. A single global count is never used.
final class CancelPathStubHTTPTests: XCTestCase {

    private let port = 59_381

    /// Deleted rows are never acceptable in any window of this file.
    private static let anchorTables = ["roots", "external_files"]

    private var host: LOCALBAuthorizedE2E.Host!
    private var modelPath: String!

    override func setUpWithError() throws {
        _ = try CancelPathHarness.requireIsolatedRoots()
        host = try LOCALBAuthorizedE2E.makeHost()
        modelPath = try CancelPathHarness.makeModelStandIn("ta")
    }

    override func tearDown() {
        if let modelPath {
            try? FileManager.default.removeItem(atPath: modelPath)
        }
        modelPath = nil
        host = nil
        super.tearDown()
    }

    // MARK: - Harness

    @MainActor
    private func startServer(
        _ engine: BlockingStubEngine,
        _ cancel: RecordingCancelHandler
    ) async throws -> HTTPServer {
        let server = try CancelPathHarness.startServer(
            port: port, modelPath: modelPath, host: host,
            engine: engine, cancel: cancel)
        let ready = await CancelPathHarness.waitUntilReady(
            host: host, port: port)
        XCTAssertTrue(ready, "the stub server never became ready on :\(port)")
        return server
    }

    private func responsesBody(
        session: String, input: String, stream: Bool
    ) -> [String: Any] {
        [
            "model": "cancel-path-http-test",
            "input": input,
            "session_id": session,
            "stream": stream,
        ]
    }

    private func chatBody(
        session: String, input: String, stream: Bool
    ) -> [String: Any] {
        [
            "model": "cancel-path-http-test",
            "messages": [["role": "user", "content": input]],
            "session_id": session,
            "stream": stream,
        ]
    }

    private func completionsBody(prompt: String) -> [String: Any] {
        [
            "model": "cancel-path-http-test",
            "prompt": prompt,
            "stream": true,
        ]
    }

    /// Prints the per-table delta plus the two settlement classes kept apart.
    private func reportDelta(
        _ label: String,
        before: ESISSweep.Snapshot,
        after: ESISSweep.Snapshot
    ) {
        let tables = [
            "execution_states", "settlements", "settlement_bindings",
            "information_advancements", "settlement_summaries",
            "settlement_reuse_contracts", "settlement_consumptions",
            "information_reuse_events", "information_demands",
            "chat_execution_links", "chat_messages", "retrieval_settlements",
            "roots", "external_files", "information_items",
        ]
        let row = tables.map { table in
            "+\(ESISSweep.added(table, before: before, after: after).count)"
                + "/-\(ESISSweep.removed(table, before: before, after: after).count)"
                + " \(table)"
        }.joined(separator: ", ")
        print("[TA-delta] \(label): \(row)")
        print(
            "[TA-delta] \(label): answerSettlements="
                + "\(ESISSweep.newAnswerSettlementIDs(before: before, after: after))"
                + " retrievalSettlements="
                + "\(ESISSweep.newRetrievalSettlementIDs(before: before, after: after))"
                + " answerBindings="
                + "\(ESISSweep.newAnswerBindingIDs(before: before, after: after))"
                + " retrievalBindings="
                + "\(ESISSweep.newRetrievalBindingIDs(before: before, after: after))")
    }

    /// Shared post-cancel/absence judgement for A2/A4/A5: no ES state at all
    /// (an admission-only row is a semantic finding, not "harmless"), no
    /// settlement/binding/advancement/summary/reuse row, no answered demand,
    /// no chat link for the session, and unchanged anchors.
    ///
    /// `information_items` is the IS content table: a cancelled turn still
    /// admits its own user text as `chat:<session>/<n>`. Those admission rows
    /// are reported as their own class and must all belong to the session under
    /// test — they are never counted as an answer and never used as an anchor.
    @MainActor
    private func assertNoAnswerLifecycle(
        before: ESISSweep.Snapshot,
        after: ESISSweep.Snapshot,
        session: String?,
        query: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(
            ESISSweep.added("execution_states", before: before, after: after), [],
            "a cancelled turn created an ES state (admission-only row is a finding)",
            file: file, line: line)
        XCTAssertEqual(
            ESISSweep.newAnswerSettlementIDs(before: before, after: after), [],
            "a cancelled turn settled an answer", file: file, line: line)
        XCTAssertEqual(
            ESISSweep.newAnswerBindingIDs(before: before, after: after), [],
            "a cancelled turn bound an answer settlement",
            file: file, line: line)
        XCTAssertEqual(
            ESISSweep.added(
                "information_advancements", before: before, after: after), [],
            "a cancelled turn advanced a demand", file: file, line: line)
        XCTAssertEqual(
            ESISSweep.added(
                "settlement_summaries", before: before, after: after), [],
            "a cancelled turn wrote a settlement summary", file: file, line: line)
        XCTAssertEqual(
            ESISSweep.added(
                "settlement_reuse_contracts", before: before, after: after), [],
            file: file, line: line)
        XCTAssertEqual(
            ESISSweep.added(
                "settlement_consumptions", before: before, after: after), [],
            file: file, line: line)
        XCTAssertEqual(
            ESISSweep.added(
                "information_reuse_events", before: before, after: after), [],
            file: file, line: line)
        if let session {
            XCTAssertNil(
                ESISSweep.chatStateID(sessionID: session),
                "a cancelled turn linked the session to a state",
                file: file, line: line)
            let links = ESISSweep.added(
                "chat_execution_links", before: before, after: after)
                .filter { $0.hasPrefix("\(session)|") }
            XCTAssertEqual(
                links, [], "a cancelled turn wrote a chat execution link",
                file: file, line: line)
        }
        if let session, let query {
            XCTAssertNil(
                try ESISSweep.answeredDemand(sessionID: session, query: query),
                "a cancelled turn registered an answered demand",
                file: file, line: line)
        }
        let admittedItems = ESISSweep.added(
            "information_items", before: before, after: after)
        XCTAssertEqual(
            ESISSweep.removed(
                "information_items", before: before, after: after), [],
            "a cancelled window deleted an IS content row",
            file: file, line: line)
        if let session {
            let foreign = admittedItems.filter { !$0.hasPrefix("chat:\(session)/") }
            XCTAssertEqual(
                foreign, [],
                "IS content rows added in this window do not belong to the "
                    + "cancelled turn's own admission: \(foreign)",
                file: file, line: line)
        } else {
            let foreign = admittedItems.filter {
                !$0.hasPrefix("chat:") && !$0.hasPrefix("openai-request:")
            }
            XCTAssertEqual(
                foreign, [],
                "unmanaged wire admitted IS rows under an unexpected scope: \(foreign)",
                file: file, line: line)
        }
        for table in Self.anchorTables {
            XCTAssertEqual(
                ESISSweep.added(table, before: before, after: after), [],
                "\(table) gained rows in a cancelled window", file: file, line: line)
            XCTAssertEqual(
                ESISSweep.removed(table, before: before, after: after), [],
                "\(table) lost rows in a cancelled window", file: file, line: line)
        }
    }

    /// A client disconnect must leave the turn running under the orphan budget:
    /// the stub leaves its closure on its own, no cancel callback fires, and the
    /// engine never observes `Task.isCancelled`.
    private func assertGenerationDetached(
        _ engine: BlockingStubEngine,
        _ cancel: RecordingCancelHandler,
        traceSince: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let exited = await engine.waitForExit(timeout: 15)
        XCTAssertTrue(
            exited, "the detached generation never left its closure",
            file: file, line: line)
        XCTAssertFalse(
            engine.cancelObserved,
            "the engine observed Task.isCancelled after the client left",
            file: file, line: line)
        XCTAssertEqual(
            engine.chunksAfterCancel, 0,
            "the engine emitted chunks after it observed the cancellation",
            file: file, line: line)
        XCTAssertEqual(
            cancel.count, 0,
            "a client disconnect must not call the cancel handler: "
                + "\(cancel.requestIds)",
            file: file, line: line)
        let detach = await CancelTrace.waitForLine(
            containing: ["[DETACH]", "slots=1"], since: traceSince, timeout: 10)
        XCTAssertNotNil(
            detach,
            "[DETACH] missing from the window:\n"
                + CancelTrace.window(since: traceSince),
            file: file, line: line)
    }

    // MARK: - A1) Streaming Responses plain turn: completes, settles, reuses

    @MainActor
    func testStreamingResponsesPlainTurnCompletesAndSettles() async throws {
        let session = "ta1-\(UUID().uuidString)"
        let question = "what does the plain streaming turn answer"

        let engine = BlockingStubEngine(
            .complete(chunks: ["STREAM-", "ANSWER-1"], text: "STREAM-ANSWER-1",
                      silenceAfterFirst: 0))
        let cancel = RecordingCancelHandler()
        let server = try await startServer(engine, cancel)
        defer { server.stop() }

        let before = await ESISSweep.stable()

        let client = StreamingClient(host: host, port: port)
        try await client.start(
            path: "/v1/responses",
            body: responsesBody(session: session, input: question, stream: true))
        XCTAssertEqual(client.status, 200, client.sse)
        let completed = await client.waitForLine(
            containing: ["\"type\":\"response.completed\""], timeout: 20)
        XCTAssertNotNil(completed, "no response.completed: \(client.sse)")
        let cancelAtCompletion = cancel.count
        let finished = await client.waitForFinished(timeout: 10)
        XCTAssertTrue(finished, client.sse)
        // The close transition runs after the terminal send; record the count on
        // both sides of it so a post-completion callback is distinguishable
        // from a callback that interrupted the finished turn.
        try? await Task.sleep(nanoseconds: 300_000_000)
        let cancelAfterClose = cancel.count

        XCTAssertEqual(engine.generateCount, 1, "the plain turn must generate once")
        XCTAssertTrue(engine.exitObserved, "the generation closure must have returned")
        XCTAssertEqual(
            cancel.count, 0,
            "a finished turn must not call the cancel handler; "
                + "atCompletion=\(cancelAtCompletion) afterClose=\(cancelAfterClose) "
                + "ids=\(cancel.requestIds) times=\(cancel.times)")

        let finalEvent = try XCTUnwrap(
            StreamingClient.lastEvent(ofType: "response.completed", in: client.lines),
            client.sse)
        let response = try XCTUnwrap(finalEvent["response"] as? [String: Any])
        XCTAssertEqual(response["status"] as? String, "completed", client.sse)
        let output = try XCTUnwrap(response["output"] as? [[String: Any]])
        let content = try XCTUnwrap(output.first?["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["text"] as? String, "STREAM-ANSWER-1")
        XCTAssertTrue(client.sse.contains("STREAM-"), "the delta text reached the wire")
        XCTAssertTrue(client.sse.contains("ANSWER-1"), "the delta text reached the wire")

        let after = await ESISSweep.stable()
        reportDelta("A1", before: before, after: after)

        let newStates = ESISSweep.newChatStateIDs(before: before, after: after)
        XCTAssertEqual(newStates.count, 1, "a settled turn creates exactly one chat-* state")
        XCTAssertEqual(
            ESISSweep.chatStateID(sessionID: session), newStates.first,
            "the session is linked to the state the turn settled")

        let answerSettlements = ESISSweep.newAnswerSettlementIDs(
            before: before, after: after)
        XCTAssertEqual(answerSettlements.count, 1, "exactly one answer settlement")
        let settlementID = try XCTUnwrap(answerSettlements.first)
        XCTAssertFalse(
            try ESISSweep.bindings(settlementID: settlementID).isEmpty,
            "the settled answer carries its bindings")
        XCTAssertNotNil(
            try ESISSweep.summary(settlementID: settlementID),
            "the settled answer carries its summary")
        let answerBindings = ESISSweep.newAnswerBindingIDs(before: before, after: after)
        XCTAssertFalse(answerBindings.isEmpty, "the binding row set must grow")
        XCTAssertTrue(
            answerBindings.allSatisfy { $0.hasPrefix("\(settlementID)|") },
            "every non-retrieval binding belongs to the settled answer: \(answerBindings)")
        XCTAssertEqual(
            ESISSweep.added(
                "information_advancements", before: before, after: after).count, 1,
            "exactly the settled turn advances one demand")

        let answered = try XCTUnwrap(
            try ESISSweep.answeredDemand(sessionID: session, query: question),
            "the completed turn is registered as an answered demand")
        XCTAssertEqual(answered.answerSettlementID, settlementID)

        // Same question again: served from the settlement, zero model calls.
        let callsBeforeReuse = engine.generateCount
        let reuseClient = StreamingClient(host: host, port: port)
        try await reuseClient.start(
            path: "/v1/responses",
            body: responsesBody(session: session, input: question, stream: true))
        XCTAssertEqual(reuseClient.status, 200, reuseClient.sse)
        let reuseCompleted = await reuseClient.waitForLine(
            containing: ["\"type\":\"response.completed\""], timeout: 20)
        XCTAssertNotNil(
            reuseCompleted,
            "no response.completed on the reuse turn: \(reuseClient.sse)")
        let reuseFinished = await reuseClient.waitForFinished(timeout: 10)
        XCTAssertTrue(reuseFinished)

        XCTAssertEqual(
            engine.generateCount, callsBeforeReuse,
            "the exact repeat must not enter generation")
        let reuseEvent = try XCTUnwrap(
            StreamingClient.lastEvent(ofType: "response.completed", in: reuseClient.lines),
            reuseClient.sse)
        let reuseResponse = try XCTUnwrap(reuseEvent["response"] as? [String: Any])
        let block = try XCTUnwrap(
            reuseResponse["simigo"] as? [String: Any],
            "reuse is reported on the stream: \(reuseClient.sse)")
        XCTAssertEqual(block["answer_reuse"] as? Bool, true)
        XCTAssertEqual(block["model_calls"] as? Int, 0)
        XCTAssertEqual(block["settlement_id"] as? String, settlementID)
        XCTAssertEqual(reuseResponse["status"] as? String, "completed")

        let afterReuse = await ESISSweep.stable()
        reportDelta("A1-reuse", before: after, after: afterReuse)
        XCTAssertEqual(
            ESISSweep.newAnswerSettlementIDs(before: after, after: afterReuse), [],
            "serving a reuse settles nothing")
        XCTAssertEqual(
            ESISSweep.newChatStateIDs(before: after, after: afterReuse), [],
            "serving a reuse creates no ES state")
    }

    // MARK: - A2) Streaming Responses: client disconnect detaches generation

    @MainActor
    func testStreamingResponsesClientDisconnectDetachesGenerationWithoutSettlement() async throws {
        let session = "ta2-\(UUID().uuidString)"
        let question = "what happens to the streaming turn that is abandoned"

        // Outlives the close: first delta, silent gap, second delta, return.
        let engine = BlockingStubEngine(
            .complete(chunks: ["FIRST-DELTA", "SECOND-DELTA"],
                      text: "ABANDONED-ANSWER", silenceAfterFirst: 2))
        let cancel = RecordingCancelHandler()
        let server = try await startServer(engine, cancel)
        defer { server.stop() }

        let before = await ESISSweep.stable()
        let traceSince = CancelTrace.size()

        let client = StreamingClient(host: host, port: port)
        try await client.start(
            path: "/v1/responses",
            body: responsesBody(session: session, input: question, stream: true))
        XCTAssertEqual(client.status, 200, client.sse)
        let firstDelta = await client.waitForLine(
            containing: ["output_text.delta", "FIRST-DELTA"], timeout: 15)
        XCTAssertNotNil(
            firstDelta,
            "the disconnect must happen after the stream is live: \(client.sse)")
        XCTAssertEqual(engine.generateCount, 1)
        XCTAssertTrue(engine.started)

        let disconnectAt = client.cancelReading()
        await assertGenerationDetached(
            engine, cancel, traceSince: traceSince)

        XCTAssertEqual(engine.generateCount, 1, "the detached turn must not restart")
        XCTAssertTrue(engine.exitObserved, "the detached turn must run to completion")
        print(
            "[TA-A2] disconnectAt=\(disconnectAt.timeIntervalSince1970) "
                + "callbacks=\(cancel.requestIds) "
                + "chunksAfterCancel=\(engine.chunksAfterCancel)")

        // Allow any trailing async write to land, then take a stable snapshot.
        let after = await ESISSweep.stable()
        reportDelta("A2", before: before, after: after)
        try assertNoAnswerLifecycle(
            before: before, after: after, session: session, query: question)

        // The only rows a detached turn may add on the ES/IS side: the user
        // message and the resolve-stage retrieval demand/settlement. They are
        // reported as their own class and are NOT counted as an answer.
        print(
            "[TA-A2] allowed rows: chat_messages+="
                + "\(ESISSweep.added("chat_messages", before: before, after: after).count)"
                + " information_demands+="
                + "\(ESISSweep.added("information_demands", before: before, after: after).count)"
                + " retrieval_settlements+="
                + "\(ESISSweep.added("retrieval_settlements", before: before, after: after).count)"
                + " information_items+="
                + "\(ESISSweep.added("information_items", before: before, after: after))")
    }

    // MARK: - A3) Streaming Responses: server-internal cancel keeps the client connected

    @MainActor
    func testStreamingResponsesInternalCancelKeepsClientConnectedAndFailsResponse() async throws {
        let session = "ta3-\(UUID().uuidString)"
        let question = "what happens when the engine cancels internally"

        let engine = BlockingStubEngine(
            .throwCancellationAfterChunk(first: "FIRST-CHUNK", delay: 0.2))
        let cancel = RecordingCancelHandler()
        let server = try await startServer(engine, cancel)
        defer { server.stop() }

        let before = await ESISSweep.stable()

        let client = StreamingClient(host: host, port: port)
        try await client.start(
            path: "/v1/responses",
            body: responsesBody(session: session, input: question, stream: true))
        XCTAssertEqual(client.status, 200, client.sse)
        let failedLine = await client.waitForLine(
            containing: ["\"type\":\"response.failed\""], timeout: 15)
        let failed = try XCTUnwrap(
            failedLine, "the connected client must receive a terminal failure: \(client.sse)")
        let failedFinished = await client.waitForFinished(timeout: 10)
        XCTAssertTrue(failedFinished, client.sse)

        XCTAssertEqual(engine.generateCount, 1, "the engine ran exactly once")
        XCTAssertTrue(engine.exitObserved)
        XCTAssertEqual(
            cancel.count, 0,
            "a server-internal cancel must not masquerade as a peer-close generation cancel")

        let event = try XCTUnwrap(
            StreamingClient.jsonObject(from: failed),
            "the failed terminal must be parseable: \(failed)")
        let response = try XCTUnwrap(event["response"] as? [String: Any])
        XCTAssertEqual(response["status"] as? String, "failed")
        let error = try XCTUnwrap(response["error"] as? [String: Any])
        XCTAssertEqual(error["type"] as? String, "cancelled")

        let after = await ESISSweep.stable()
        reportDelta("A3", before: before, after: after)
        try assertNoAnswerLifecycle(
            before: before, after: after, session: session, query: question)
    }

    // MARK: - A4) Chat non-streaming: client disconnect detaches generation

    @MainActor
    func testChatNonStreamingClientDisconnectDetachesGenerationWithoutSettlement() async throws {
        let session = "ta4-\(UUID().uuidString)"
        let question = "what happens to the non streaming chat that is abandoned"

        let engine = BlockingStubEngine(
            .complete(chunks: ["A4-FIRST", "A4-SECOND"], text: "A4-ANSWER",
                      silenceAfterFirst: 2))
        let cancel = RecordingCancelHandler()
        let server = try await startServer(engine, cancel)
        defer { server.stop() }

        let before = await ESISSweep.stable()
        let traceSince = CancelTrace.size()

        let request = try await StreamingClient.makeRequest(
            host: host, port: port, path: "/v1/chat/completions",
            body: chatBody(session: session, input: question, stream: false))
        let dataTask = host.session.dataTask(with: request)
        dataTask.resume()

        let started = await engine.waitForStarted(timeout: 10)
        XCTAssertTrue(
            started,
            "the request must reach generation before it is disconnected")
        let disconnectAt = Date()
        dataTask.cancel()

        await assertGenerationDetached(
            engine, cancel, traceSince: traceSince)
        XCTAssertEqual(engine.generateCount, 1, "the detached turn must not restart")
        XCTAssertTrue(engine.exitObserved, "the detached turn must run to completion")
        print(
            "[TA-A4] disconnectAt=\(disconnectAt.timeIntervalSince1970) "
                + "callbacks=\(cancel.requestIds)")

        let after = await ESISSweep.stable()
        reportDelta("A4", before: before, after: after)
        try assertNoAnswerLifecycle(
            before: before, after: after, session: session, query: question)
    }

    // MARK: - A5) Completions streaming: client disconnect detaches generation

    @MainActor
    func testCompletionsStreamingClientDisconnectDetachesGenerationWithoutSettlement() async throws {
        let prompt = "what happens to the legacy completion that is abandoned"

        let engine = BlockingStubEngine(
            .complete(chunks: ["FIRST-CHUNK", "SECOND-CHUNK"],
                      text: "A5-ANSWER", silenceAfterFirst: 2))
        let cancel = RecordingCancelHandler()
        let server = try await startServer(engine, cancel)
        defer { server.stop() }

        let before = await ESISSweep.stable()
        let traceSince = CancelTrace.size()

        let client = StreamingClient(host: host, port: port)
        try await client.start(
            path: "/v1/completions", body: completionsBody(prompt: prompt))
        XCTAssertEqual(client.status, 200, client.sse)
        let firstChunk = await client.waitForLine(
            containing: ["FIRST-CHUNK"], timeout: 15)
        XCTAssertNotNil(
            firstChunk,
            "the disconnect must happen after the stream is live: \(client.sse)")
        XCTAssertEqual(engine.generateCount, 1)
        XCTAssertTrue(engine.started)

        client.cancelReading()
        await assertGenerationDetached(
            engine, cancel, traceSince: traceSince)
        XCTAssertEqual(engine.generateCount, 1, "the detached turn must not restart")
        XCTAssertTrue(engine.exitObserved, "the detached turn must run to completion")
        print("[TA-A5] callbacks=\(cancel.requestIds) detached=1")

        // The legacy text-completions wire is unmanaged: no session is named,
        // so the demand/link checks are limited to their presence as rows.
        let after = await ESISSweep.stable()
        reportDelta("A5", before: before, after: after)
        try assertNoAnswerLifecycle(
            before: before, after: after, session: nil, query: nil)
        XCTAssertEqual(
            ESISSweep.added("chat_execution_links", before: before, after: after), [],
            "the unmanaged completions wire must not link a session")
    }

    // MARK: - A6) Detached orphan yields the engine to a queued retry

    /// Owner authorization (2026-10-30): reduce the wasted decoding of orphan
    /// turns — "stop generating, keep the prefix". The orphan still runs when
    /// nobody is waiting (A2/A4/A5); the moment another generation is in the
    /// engine window, the orphan stops at a token boundary through the standard
    /// cancel wiring (so #134/#136 prefix retention applies), and stays
    /// fail-closed: no settlement, no commit.
    @MainActor
    func testDetachedOrphanYieldsEngineToQueuedRetry() async throws {
        let orphanSession = "ta6a-\(UUID().uuidString)"
        let orphanQuestion = "which abandoned turn yields to the queued retry"
        let retrySession = "ta6b-\(UUID().uuidString)"
        let retryQuestion = "which queued retry takes the engine from the orphan"

        let engine = BlockingStubEngine(
            .firstStreamsThenCompletes(
                first: "ORPHAN-FIRST", interval: 0.05, laterHold: 1.0,
                laterChunks: ["RETRY-", "ANSWER-6"], laterText: "RETRY-ANSWER-6"))
        let cancel = RecordingCancelHandler()
        let server = try await startServer(engine, cancel)
        defer { server.stop() }

        let before = await ESISSweep.stable()
        let traceSince = CancelTrace.size()

        let orphan = StreamingClient(host: host, port: port)
        try await orphan.start(
            path: "/v1/responses",
            body: responsesBody(
                session: orphanSession, input: orphanQuestion, stream: true))
        XCTAssertEqual(orphan.status, 200, orphan.sse)
        let firstDelta = await orphan.waitForLine(
            containing: ["ORPHAN-FIRST"], timeout: 15)
        XCTAssertNotNil(
            firstDelta,
            "the orphan must be live before its client leaves: \(orphan.sse)")
        XCTAssertEqual(engine.generateCount, 1)
        XCTAssertTrue(engine.started)

        orphan.cancelReading()
        let detach = await CancelTrace.waitForLine(
            containing: ["[DETACH]", "slots=1"], since: traceSince, timeout: 10)
        XCTAssertNotNil(
            detach,
            "[DETACH] missing from the window:\n"
                + CancelTrace.window(since: traceSince))

        // The retry is a different session: it enters the generation window
        // while the orphan is still decoding.
        let retry = StreamingClient(host: host, port: port)
        try await retry.start(
            path: "/v1/responses",
            body: responsesBody(
                session: retrySession, input: retryQuestion, stream: true))
        XCTAssertEqual(retry.status, 200, retry.sse)
        let retryCompleted = await retry.waitForLine(
            containing: ["\"type\":\"response.completed\""], timeout: 20)
        XCTAssertNotNil(
            retryCompleted, "the retry must complete on its own: \(retry.sse)")
        let retryFinished = await retry.waitForFinished(timeout: 10)
        XCTAssertTrue(retryFinished, retry.sse)

        let stopped = await CancelTrace.waitForLine(
            containing: ["[DETACH]", "stop=1"], since: traceSince, timeout: 10)
        XCTAssertNotNil(
            stopped,
            "the orphan never yielded the engine:\n"
                + CancelTrace.window(since: traceSince))
        let orphanCancelled = await engine.waitForCancelObserved(timeout: 10)
        XCTAssertTrue(
            orphanCancelled,
            "the orphan's generation must observe the yield as a cancellation")
        // `cancelObserved` is set only after the first call's emit loop exits,
        // so it already proves that closure left its loop. `chunksAfterCancel`
        // is global across calls and the retry emits two chunks of its own, so
        // it is not evidence about the orphan here.
        XCTAssertEqual(
            engine.generateCount, 2,
            "the retry must be the second — and only other — generate call")
        XCTAssertEqual(
            cancel.count, 0,
            "the yield is not a client cancellation: \(cancel.requestIds)")

        let finalEvent = try XCTUnwrap(
            StreamingClient.lastEvent(
                ofType: "response.completed", in: retry.lines),
            retry.sse)
        let response = try XCTUnwrap(finalEvent["response"] as? [String: Any])
        let output = try XCTUnwrap(response["output"] as? [[String: Any]])
        let content = try XCTUnwrap(output.first?["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["text"] as? String, "RETRY-ANSWER-6")
        XCTAssertEqual(response["status"] as? String, "completed")

        // Both turns are in one window: the retry settles, the orphan does not.
        let after = await ESISSweep.stable()
        reportDelta("A6", before: before, after: after)

        let answerSettlements = ESISSweep.newAnswerSettlementIDs(
            before: before, after: after)
        XCTAssertEqual(
            answerSettlements.count, 1,
            "only the retry may settle; the yielded orphan must not: "
                + "\(answerSettlements)")
        let retryAnswered = try XCTUnwrap(
            try ESISSweep.answeredDemand(
                sessionID: retrySession, query: retryQuestion),
            "the completed retry is registered as an answered demand")
        XCTAssertEqual(answerSettlements, [retryAnswered.answerSettlementID])
        XCTAssertEqual(
            ESISSweep.added(
                "information_advancements", before: before, after: after).count, 1,
            "exactly the retry advances one demand")

        XCTAssertNil(
            ESISSweep.chatStateID(sessionID: orphanSession),
            "the yielded orphan linked its session to a state")
        XCTAssertNil(
            try ESISSweep.answeredDemand(
                sessionID: orphanSession, query: orphanQuestion),
            "the yielded orphan registered an answered demand")
        let orphanLinks = ESISSweep.added(
            "chat_execution_links", before: before, after: after)
            .filter { $0.hasPrefix("\(orphanSession)|") }
        XCTAssertEqual(
            orphanLinks, [], "the yielded orphan wrote a chat execution link")
        XCTAssertEqual(
            ESISSweep.removed("information_items", before: before, after: after), [],
            "the yield deleted an IS content row")
        for table in Self.anchorTables {
            XCTAssertEqual(
                ESISSweep.added(table, before: before, after: after), [],
                "\(table) gained rows in this window")
            XCTAssertEqual(
                ESISSweep.removed(table, before: before, after: after), [],
                "\(table) lost rows in this window")
        }
    }
}
