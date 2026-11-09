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
///     -> reusableAnswer gate (current demand + settlement validity; identity is provenance)
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
            generateHandler: { _, _, _, _, _, _, _, onChunk, _, _ in
                stub.bump()
                onChunk(stub.text)
                return GenerationResult(text: stub.text, usage: nil, completion: .complete)
            },
            forkBranchHandler: { _, _, _, target in
                SessionCacheMetadata(
                    storageKey: "t/\(target)", modelId: "chat-answer-reuse-http-test",
                    savedAt: Date(), history: [])
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
        let previousFreeze = ProcessInfo.processInfo.environment["SIMIGO_IS_CONTEXT_FREEZE"]
        let previousReuse = ProcessInfo.processInfo.environment["SIMIGO_IS_ANSWER_REUSE"]
        setenv("SIMIGO_IS_CONTEXT_FREEZE", "1", 1)
        setenv("SIMIGO_IS_ANSWER_REUSE", "1", 1)
        defer {
            if let previousFreeze {
                setenv("SIMIGO_IS_CONTEXT_FREEZE", previousFreeze, 1)
            } else {
                unsetenv("SIMIGO_IS_CONTEXT_FREEZE")
            }
            if let previousReuse {
                setenv("SIMIGO_IS_ANSWER_REUSE", previousReuse, 1)
            } else {
                unsetenv("SIMIGO_IS_ANSWER_REUSE")
            }
        }

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
            let answeredBeforeRepeat = try XCTUnwrap(
                db.answeredDemand(sessionID: session, query: "where is the vault"))
            let demandsBeforeRepeat = try db.count("information_demands")

            let second = try await dispatch(session: session, input: "where is the vault")
            XCTAssertEqual(second.status, 200, second.sse)
            XCTAssertEqual(second.generate, 1, "a streaming exact repeat must not call the model")
            XCTAssertEqual(
                try db.count("information_demands"), demandsBeforeRepeat,
                "the exact repeat resolves the already answered demand, so it mints no new demand row")

            let block = try XCTUnwrap(second.reuse, "reuse is reported on the stream")
            XCTAssertEqual(block["answer_reuse"] as? Bool, true)
            XCTAssertEqual(block["model_calls"] as? Int, 0)
            let demandID = try XCTUnwrap(block["demand_id"] as? String)
            XCTAssertEqual(
                demandID, answeredBeforeRepeat.demandID,
                "reuse is authorized by the frozen demand actually rendered, not the newer retrieval candidate")
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
            let answeredAfterRepeat = try XCTUnwrap(
                db.answeredDemand(sessionID: session, query: "where is the vault"))
            XCTAssertEqual(
                answeredAfterRepeat.demandID, answeredBeforeRepeat.demandID,
                "the answer remains published against the rendered demand")

            // A different question is not an exact repeat and still generates.
            let third = try await dispatch(session: session, input: "where is the anvil")
            XCTAssertEqual(third.status, 200, third.sse)
            XCTAssertEqual(third.generate, 2, "a different question runs the ordinary path")
            XCTAssertNil(third.reuse)
        }
    }

    /// Disconnect after generation start may detach only when an orphan slot
    /// is granted; manual cancellation and Runtime shutdown still win. Once a
    /// completed turn claims finalization, later disconnects cannot orphan-yield it.
    @MainActor
    func testCompletedTurnClaimAllowsGrantedDetachButRejectsCancellation() throws {
        func makeContext(_ label: String) -> (HTTPServer.ConnectionContext, NWConnection) {
            let connection = NWConnection(
                to: .hostPort(
                    host: NWEndpoint.Host("127.0.0.1"),
                    port: NWEndpoint.Port(rawValue: 9)!),
                using: .tcp)
            connection.start(queue: DispatchQueue(label: "detach-policy-" + label + "-" + UUID().uuidString))
            return (HTTPServer.ConnectionContext(connection: connection), connection)
        }

        // An acquired orphan slot preserves a naturally completed generation.
        let (detached, detachedConnection) = makeContext("detached")
        defer { detachedConnection.cancel() }
        XCTAssertTrue(detached.markGenerationStarted())
        let detachedClose = detached.closeAndTakeRequestTask(
            cancelGeneration: true, detach: true, claimDetachSlot: { true })
        XCTAssertTrue(detachedClose.detached)
        XCTAssertFalse(detachedClose.shouldCancelGeneration)
        XCTAssertTrue(detached.claimCompletedTurnSettlement())

        // A normal cancellation sets the cancellation latch and cannot claim.
        let (cancelled, cancelledConnection) = makeContext("cancelled")
        defer { cancelledConnection.cancel() }
        XCTAssertTrue(cancelled.markGenerationStarted())
        let cancelledClose = cancelled.closeAndTakeRequestTask(
            cancelGeneration: true, detach: false)
        XCTAssertTrue(cancelledClose.shouldCancelGeneration)
        XCTAssertFalse(cancelled.claimCompletedTurnSettlement())

        // A later client close cannot cancel a generation already finalizing.
        let (claimed, claimedConnection) = makeContext("claimed")
        defer { claimedConnection.cancel() }
        XCTAssertTrue(claimed.markGenerationStarted())
        XCTAssertTrue(claimed.claimCompletedTurnSettlement())
        var lateSlotClaimed = false
        let lateClose = claimed.closeAndTakeRequestTask(
            cancelGeneration: true, detach: true, claimDetachSlot: {
                lateSlotClaimed = true
                return true
            })
        XCTAssertFalse(lateClose.shouldCancelGeneration)
        XCTAssertFalse(lateClose.detached)
        XCTAssertFalse(lateSlotClaimed,
                       "completed finalization is no longer an inference orphan")
        
        // Runtime shutdown still overrides a previously claimed finalization.
        let (runtimeCancelled, runtimeConnection) = makeContext("runtime-cancelled")
        defer { runtimeConnection.cancel() }
        XCTAssertTrue(runtimeCancelled.markGenerationStarted())
        XCTAssertTrue(runtimeCancelled.claimCompletedTurnSettlement())
        runtimeCancelled.markCancelledByRuntime()
        let runtimeClose = runtimeCancelled.closeAndTakeRequestTask(
            cancelGeneration: true, detach: false)
        XCTAssertTrue(runtimeClose.shouldCancelGeneration)
    }

    /// An orphan-yield pass that already took the detached task wins over a
    /// later completion claim, and a claimed finalization can no longer be
    /// taken for yield. Both decisions share one lock, so the loser must
    /// observe the winner's result instead of both proceeding.
    @MainActor
    func testOrphanYieldAndSettlementClaimAreMutuallyExclusive() throws {
        func makeContext(_ label: String) -> (HTTPServer.ConnectionContext, NWConnection) {
            let connection = NWConnection(
                to: .hostPort(
                    host: NWEndpoint.Host("127.0.0.1"),
                    port: NWEndpoint.Port(rawValue: 9)!),
                using: .tcp)
            connection.start(queue: DispatchQueue(label: "detach-race-" + label + "-" + UUID().uuidString))
            return (HTTPServer.ConnectionContext(connection: connection), connection)
        }
        func sleepingTask() -> Task<Void, Never> {
            Task {
                do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch {}
            }
        }

        // Yield wins: its task was taken, so the completed turn must not settle.
        let (yielded, yieldedConnection) = makeContext("yielded")
        defer { yieldedConnection.cancel() }
        let yieldedTask = sleepingTask()
        XCTAssertTrue(yielded.setRequestTask(yieldedTask))
        XCTAssertTrue(yielded.markGenerationStarted())
        let yieldedClose = yielded.closeAndTakeRequestTask(
            cancelGeneration: true, detach: true, claimDetachSlot: { true })
        XCTAssertTrue(yieldedClose.detached)
        XCTAssertNotNil(yielded.takeDetachedRequestTask())
        yieldedTask.cancel()
        XCTAssertFalse(
            yielded.claimCompletedTurnSettlement(),
            "a yielded orphan must not settle after its task was taken")

        // Claim wins over yield: the finalization is no longer a candidate.
        let (claimed, claimedConnection) = makeContext("claimed-before-yield")
        defer { claimedConnection.cancel() }
        let claimedTask = sleepingTask()
        XCTAssertTrue(claimed.setRequestTask(claimedTask))
        XCTAssertTrue(claimed.markGenerationStarted())
        let claimedClose = claimed.closeAndTakeRequestTask(
            cancelGeneration: true, detach: true, claimDetachSlot: { true })
        XCTAssertTrue(claimedClose.detached)
        XCTAssertTrue(claimed.claimCompletedTurnSettlement())
        XCTAssertNil(
            claimed.takeDetachedRequestTask(),
            "a claimed finalization is no longer an orphan candidate")
        XCTAssertFalse(
            claimed.claimCompletedTurnSettlement(),
            "the finalization claim is one-shot")
        claimedTask.cancel()

        // A close that arrives after the claim (client was still connected when
        // the claim was taken) must neither cancel the generation nor hand its
        // task back for cancellation; only Runtime shutdown may override.
        let (late, lateConnection) = makeContext("late-close-after-claim")
        defer { lateConnection.cancel() }
        let lateTask = sleepingTask()
        XCTAssertTrue(late.setRequestTask(lateTask))
        XCTAssertTrue(late.markGenerationStarted())
        XCTAssertTrue(late.claimCompletedTurnSettlement())
        var lateSlotClaimed = false
        let lateClose = late.closeAndTakeRequestTask(
            cancelGeneration: true, detach: true, claimDetachSlot: {
                lateSlotClaimed = true
                return true
            })
        XCTAssertFalse(lateClose.shouldCancelGeneration)
        XCTAssertFalse(lateClose.detached)
        XCTAssertFalse(lateSlotClaimed)
        XCTAssertNil(
            lateClose.requestTask,
            "a late close must not hand a claimed finalization to cancellation")
        lateTask.cancel()

        // A claimed detached finalization retains its task for Runtime shutdown.
        let (claimedDetached, claimedDetachedConnection) = makeContext("claimed-detached")
        defer { claimedDetachedConnection.cancel() }
        let detachedTask = sleepingTask()
        XCTAssertTrue(claimedDetached.setRequestTask(detachedTask))
        XCTAssertTrue(claimedDetached.markGenerationStarted())
        let detachedClose = claimedDetached.closeAndTakeRequestTask(
            cancelGeneration: true, detach: true, claimDetachSlot: { true })
        XCTAssertTrue(detachedClose.detached)
        XCTAssertTrue(claimedDetached.claimCompletedTurnSettlement())
        let ordinaryLateClose = claimedDetached.closeAndTakeRequestTask(
            cancelGeneration: true, detach: true, claimDetachSlot: { true })
        XCTAssertNil(
            ordinaryLateClose.requestTask,
            "an ordinary late close must not receive a claimed finalization task")
        claimedDetached.markCancelledByRuntime()
        let runtimeClose = claimedDetached.closeAndTakeRequestTask(
            cancelGeneration: true, detach: false)
        XCTAssertNotNil(
            runtimeClose.requestTask,
            "Runtime shutdown must still receive the retained detached task")
        runtimeClose.requestTask?.cancel()
        detachedTask.cancel()
    }

    func testHTTPFailureAuditPersistsSafeAppendOnlyTerminalFact() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-http-failure-audit-\(UUID().uuidString).sqlite3")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
        }

        let executionID = "http-failure-audit-test-\(UUID().uuidString)"
        let first = try XCTUnwrap(HTTPServer.recordHTTPFailureAudit(
            executionID: executionID,
            requestID: "req-test-1234",
            wire: "chat.completions.stream",
            terminal: "cancelled_by_client",
            modelCalls: 1,
            settlementsWritten: 0,
            evidence: ["safe_marker": "test-only"],
            databaseURL: url))
        XCTAssertTrue(first.auditPersisted)

        let db = try SimiGoESISDatabase(url: url, createIfNeeded: false)
        defer { db.close() }
        try db.runMigrations()
        let event = try XCTUnwrap(db.failureAudit(executionID: executionID))
        XCTAssertEqual(event.executionID, executionID)
        XCTAssertEqual(event.phase, .g)
        XCTAssertNil(event.cause)
        XCTAssertEqual(event.origin, .request)
        XCTAssertEqual(event.modelCalls, 1)
        XCTAssertEqual(event.settlementsWritten, 0)
        XCTAssertEqual(event.evidence["request_id"], "req-test-1234")
        XCTAssertEqual(event.evidence["wire"], "chat.completions.stream")
        XCTAssertEqual(event.evidence["terminal"], "cancelled_by_client")
        XCTAssertEqual(event.evidence["safe_marker"], "test-only")
        XCTAssertEqual(event.detail, "wire=chat.completions.stream terminal=cancelled_by_client")
        XCTAssertEqual(try db.failureAuditHistory(executionID: executionID).count, 1)

        let duplicate = try XCTUnwrap(HTTPServer.recordHTTPFailureAudit(
            executionID: executionID,
            requestID: "req-test-1234",
            wire: "chat.completions.stream",
            terminal: "model_execution_error",
            modelCalls: 1,
            settlementsWritten: 0,
            databaseURL: url))
        XCTAssertFalse(duplicate.auditPersisted)
        XCTAssertEqual(duplicate.failureClass, "duplicate_execution_id")
        XCTAssertEqual(try XCTUnwrap(db.failureAudit(executionID: executionID)), event)
        XCTAssertEqual(try db.failureAuditHistory(executionID: executionID).count, 1)
    }

    /// Exact wording is not enough: reuse is bound to the demand resolved for
    /// THIS turn. An answer's own question and answer rows are excluded from
    /// that basis, so only information the turn did not itself publish moves it.
    /// Committing a turn in another session does, and the settled answer must
    /// then not be served for the same words.
    @MainActor
    func testChangedCurrentDemandIsNotServedByReuse() async throws {
        let session = "chat-demand-change-\(UUID().uuidString)"
        let previous = ProcessInfo.processInfo.environment["SIMIGO_IS_CONTEXT_FREEZE"]
        setenv("SIMIGO_IS_CONTEXT_FREEZE", "0", 1)
        defer {
            if let previous {
                setenv("SIMIGO_IS_CONTEXT_FREEZE", previous, 1)
            } else {
                unsetenv("SIMIGO_IS_CONTEXT_FREEZE")
            }
        }

        try await withServer {
            let first = try await dispatch(session: session, input: "where is the vault")
            XCTAssertEqual(first.status, 200, first.sse)
            XCTAssertEqual(first.generate, 1, "the first turn generates")
            XCTAssertNil(first.reuse)

            let store = ExecutionStateGraphStore()
            let db = try XCTUnwrap(store.esis)
            let demandsAfterFirst = try db.count("information_demands")

            // New information this answer did not produce: a committed turn in a
            // different session, inside the same shared personal space.
            let external = "chat-demand-change-external-\(UUID().uuidString)"
            let externalUser = try db.appendChatMessage(
                sessionID: external, role: "user",
                content: "the vault moved to the north shelf",
                model: nil, createdAt: Date())
            try db.commitChatTurn(
                sessionID: external, userMessageID: externalUser,
                assistantText: "CHAT-EXTERNAL-DEMAND-SOURCE-73B",
                model: nil, createdAt: Date())
            XCTAssertEqual(
                try db.count("information_demands"), demandsAfterFirst,
                "committing chat rows resolves no demand of its own")

            let second = try await dispatch(session: session, input: "where is the vault")
            XCTAssertEqual(second.status, 200, second.sse)
            XCTAssertEqual(
                second.generate, 2,
                "the same words are a different demand once the scope moved")
            XCTAssertNil(second.reuse, "a changed current demand must not inherit the old answer")
            XCTAssertEqual(
                try db.count("information_demands"), demandsAfterFirst + 1,
                "the second turn resolved a NEW demand, so the old answer was out of scope")
        }
    }
    
    func testDetachedCancellationKeepsDetachedTerminalStandingUnlessRuntimeShutdownWins() {
        func makeContext(_ label: String) -> (HTTPServer.ConnectionContext, NWConnection) {
            let connection = NWConnection(
                to: .hostPort(
                    host: NWEndpoint.Host("127.0.0.1"),
                    port: NWEndpoint.Port(rawValue: 9)!),
                using: .tcp)
            connection.start(queue: DispatchQueue(label: "terminal-standing-" + label + "-" + UUID().uuidString))
            return (HTTPServer.ConnectionContext(connection: connection), connection)
        }

        let (detached, detachedConnection) = makeContext("detached-yield")
        defer { detachedConnection.cancel() }
        XCTAssertTrue(detached.markGenerationStarted())
        let detachedClose = detached.closeAndTakeRequestTask(
            cancelGeneration: true, detach: true, claimDetachSlot: { true })
        XCTAssertTrue(detachedClose.detached)
        XCTAssertEqual(
            HTTPServer.chatTurnTerminalForCancellation(detached).rawValue,
            "detached",
            "an orphan-yield cancellation retains the client-detached standing")

        let (runtime, runtimeConnection) = makeContext("runtime-shutdown")
        defer { runtimeConnection.cancel() }
        XCTAssertTrue(runtime.markGenerationStarted())
        let runtimeClose = runtime.closeAndTakeRequestTask(
            cancelGeneration: true, detach: true, claimDetachSlot: { true })
        XCTAssertTrue(runtimeClose.detached)
        runtime.markCancelledByRuntime()
        XCTAssertEqual(
            HTTPServer.chatTurnTerminalForCancellation(runtime).rawValue,
            "cancelled",
            "Runtime shutdown overrides the earlier client detach")

        let (manual, manualConnection) = makeContext("manual-cancel")
        defer { manualConnection.cancel() }
        XCTAssertTrue(manual.markGenerationStarted())
        _ = manual.closeAndTakeRequestTask(cancelGeneration: true, detach: false)
        XCTAssertEqual(
            HTTPServer.chatTurnTerminalForCancellation(manual).rawValue,
            "cancelled",
            "ordinary cancellation remains cancelled")
    }
}
