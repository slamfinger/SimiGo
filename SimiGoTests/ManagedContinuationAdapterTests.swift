import Foundation
import XCTest
import SimiGoRuntimeContract

@testable import SimiGo

/// C-4b acceptance at the production adapter boundary: real work-root capture,
/// real P1 → S → G → P2 through `SimiGoManagedContinuation.run`, real settlement
/// gate, and a stub model call (a counter plus a fixed answer).
///
/// The adapter is exercised exactly as the runtime wires it, so these tests also
/// cover what the HTTP suite cannot see: the declared snapshot bytes, the `used`
/// evidence, and the row-level effects of each refusal.
///
/// Runs only with the three isolated roots injected (`SIMIGO_HOME`,
/// `SIMIGO_CACHE_ROOT`, `SIMIGO_STATE_GRAPH_STORE`); otherwise XCTSkip.
final class ManagedContinuationAdapterTests: XCTestCase {

    private let rootID = "work-adapter-c4b"
    private var isolationRoot: URL!
    private var modelPath: String!
    private var workRoot: URL!

    private final class Stub: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private var messages: [[JSONValue]] = []
        private var text = ""

        func configure(text: String) { lock.withLock { self.text = text } }

        func record(_ sent: [JSONValue]) -> String {
            lock.withLock {
                count += 1
                messages.append(sent)
                return text
            }
        }

        var calls: Int { lock.withLock { count } }
        var lastMessages: [JSONValue] { lock.withLock { messages.last ?? [] } }
    }

    private struct Ledger: Equatable {
        let states: Int
        let settlements: Int
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
        isolationRoot = URL(
            fileURLWithPath: (home as NSString).standardizingPath, isDirectory: true)
        XCTAssertTrue(
            SimiGoPaths.databaseURL.path.hasPrefix(isolationRoot.path),
            "authoritative store resolves outside the isolation root")

        let model = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimiGoManagedAdapterModel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        try Data(#"{"model_type":"managed-adapter-stand-in"}"#.utf8)
            .write(to: model.appendingPathComponent("tokenizer.adapter.json"))
        modelPath = model.path

        workRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimiGoManagedAdapterRoot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workRoot, withIntermediateDirectories: true)
        try Data("alpha beta gamma".utf8)
            .write(to: workRoot.appendingPathComponent("notes.md"))

        let db = try openDatabase()
        try db.upsertRoot(
            rootID: rootID, category: "work", displayName: workRoot.path,
            locatorType: "path", status: "registered")
    }

    override func tearDown() {
        if let modelPath { try? FileManager.default.removeItem(atPath: modelPath) }
        if let workRoot { try? FileManager.default.removeItem(atPath: workRoot.path) }
        super.tearDown()
    }

    // MARK: - Helpers

    private func openDatabase() throws -> SimiGoESISDatabase {
        let db = try SimiGoESISDatabase(
            url: SimiGoPaths.databaseURL, createIfNeeded: true)
        try db.runMigrations()
        return db
    }

    private func ledger(_ db: SimiGoESISDatabase) throws -> Ledger {
        Ledger(
            states: try db.count("execution_states"),
            settlements: try db.count("settlements"))
    }

    private func stageAnchor(_ db: SimiGoESISDatabase) throws -> String {
        let settled = try SimiGoSettlementAuthority.authorize(
            generatedText: "ANCHOR-STATE",
            contractJSON: SimiGoInformationLoop.chatResultContractJSON,
            verifiedBindings: [:])
        let stateID = "es-anchor-" + UUID().uuidString.lowercased()
        try db.recordExecutionState(
            id: stateID, parentID: nil,
            modelIdentity: SimiGoProducerIdentity.identity(fromPath: modelPath).model,
            position: 1, continuationID: UUID().uuidString,
            anchor: settled.payloadDigest, lifecycle: "active", createdAt: Date())
        _ = try db.recordNativeSettlement(settled, stateID: stateID)
        return stateID
    }

    private func makeRequest(
        anchor: String,
        policy: SimiGoRecomputePolicy = .never,
        key: String?,
        roots: [String]? = nil
    ) -> ManagedContinuationRequest {
        ManagedContinuationRequest(
            requestId: "req-" + UUID().uuidString.lowercased(),
            agentId: nil,
            sessionId: "sess-managed-adapter",
            logicalBranchId: "main",
            anchorESStateID: anchor,
            policy: policy,
            idempotencyKey: key,
            consumerESStateID: nil,
            rootIDs: roots ?? [rootID],
            messages: [
                .object(["role": .string("system"), "content": .string("sys")]),
                .object([
                    "role": .string("user"),
                    "content": .string("summarize the notes"),
                ]),
            ],
            tools: nil,
            config: ModelConfig())
    }

    private func generator(_ stub: Stub) -> ManagedContinuationGenerate {
        { _, messages in
            GenerationResult(text: stub.record(messages), usage: nil, completion: .complete)
        }
    }

    /// The same stand-in with a declared verdict, which is how a budget-capped or
    /// cancelled managed generation is reproduced without a model.
    private func generator(
        _ stub: Stub, completion: GenerationCompletion
    ) -> ManagedContinuationGenerate {
        { _, messages in
            GenerationResult(text: stub.record(messages), usage: nil, completion: completion)
        }
    }

    private func rewriteNotes(_ text: String) throws {
        try Data(text.utf8).write(to: workRoot.appendingPathComponent("notes.md"))
    }

    private func refusal(
        from request: ManagedContinuationRequest,
        stub: Stub,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> SimiGoManagedRefusal.Refusal? {
        await refusal(from: request, generate: generator(stub), file: file, line: line)
    }

    private func refusal(
        from request: ManagedContinuationRequest,
        generate: @escaping ManagedContinuationGenerate,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> SimiGoManagedRefusal.Refusal? {
        do {
            _ = try await runNativeManagedContinuation(
                request: request, modelPath: modelPath, generate: generate)
            XCTFail("expected a typed refusal", file: file, line: line)
            return nil
        } catch let failure as ManagedContinuationFailure {
            guard case .refused(let refusal) = failure else {
                XCTFail("unexpected failure \(failure)", file: file, line: line)
                return nil
            }
            return refusal
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
            return nil
        }
    }

    // MARK: - 1) Fresh run: declared sources, injection evidence, one commit

    func testFreshRunCapturesSourcesInjectsThemAndCommits() async throws {
        let db = try openDatabase()
        let anchor = try stageAnchor(db)
        let stub = Stub()
        stub.configure(text: "MANAGED-ANSWER-9001")

        let result = try await runNativeManagedContinuation(
            request: makeRequest(anchor: anchor, key: "fresh-9001"),
            modelPath: modelPath, generate: generator(stub))

        XCTAssertEqual(result.modelCalls, 1)
        XCTAssertEqual(result.settlementsWritten, 1)
        XCTAssertEqual(result.replayable, true, "embedded bytes make the run replayable")
        XCTAssertEqual(result.content, "MANAGED-ANSWER-9001")
        XCTAssertFalse(result.reusedExecution)
        XCTAssertFalse(result.recomputed)
        XCTAssertEqual(stub.calls, 1)

        // Injection: appended to the trailing user turn, leading prefix stable.
        let sent = stub.lastMessages
        XCTAssertEqual(sent.first?.object?["role"]?.string, "system")
        let user = try XCTUnwrap(sent.last?.object?["content"]?.string)
        XCTAssertTrue(user.hasPrefix("summarize the notes"))
        XCTAssertTrue(user.contains("<source root_id=\"\(rootID)\" path=\"notes.md\""))
        XCTAssertTrue(user.contains("alpha beta gamma"))

        // Child state sits under the anchor.
        XCTAssertEqual(try db.executionStatePosition(result.childESStateID), 2)

        let finalID = try XCTUnwrap(
            db.settlementInputSnapshotObjectID(settlementID: result.settlementID))
        let final = try SimiGoSnapshotContract.Final.decode(try db.readObject(finalID))
        XCTAssertTrue(final.replayable)
        XCTAssertEqual(final.used.count, 1)
        XCTAssertEqual(final.used.first?.identity.identifier, "file:\(rootID)/notes.md")
        XCTAssertEqual(final.used.first?.injectedAs, "context[0]")

        let declared = try SimiGoSnapshotContract.Declared.decode(
            try db.readObject(final.declaredSnapshotID))
        XCTAssertEqual(declared.entries.count, 1)
        XCTAssertEqual(declared.request.rootIDs, [rootID])
        XCTAssertEqual(
            declared.entries.first?.digest,
            SimiGoSnapshotContract.sha256Hex(Data("alpha beta gamma".utf8)))
        XCTAssertNoThrow(try final.verify(against: declared))
    }

    // MARK: - 2) Replay: settled value, zero model calls

    func testReplayServesSettledValueWithoutModelCall() async throws {
        let db = try openDatabase()
        let anchor = try stageAnchor(db)
        let stub = Stub()
        stub.configure(text: "REPLAY-VALUE-9002")

        _ = try await runNativeManagedContinuation(
            request: makeRequest(anchor: anchor, key: "replay-9002"),
            modelPath: modelPath, generate: generator(stub))
        XCTAssertEqual(stub.calls, 1)

        let replay = try await runNativeManagedContinuation(
            request: makeRequest(anchor: anchor, key: "replay-9002"),
            modelPath: modelPath, generate: generator(stub))

        XCTAssertTrue(replay.reusedExecution)
        XCTAssertEqual(replay.modelCalls, 0)
        XCTAssertEqual(replay.settlementsWritten, 0)
        XCTAssertEqual(replay.content, "REPLAY-VALUE-9002")
        XCTAssertEqual(stub.calls, 1, "a replay never calls the model")
    }

    // MARK: - 3) Changed source under `never`: refused before generation

    func testChangedSourceRefusesUnderNeverPolicy() async throws {
        let db = try openDatabase()
        let anchor = try stageAnchor(db)
        let stub = Stub()
        stub.configure(text: "FIRST-9003")

        let first = try await runNativeManagedContinuation(
            request: makeRequest(anchor: anchor, key: "never-9003"),
            modelPath: modelPath, generate: generator(stub))
        try rewriteNotes("alpha beta gamma delta")

        let before = try ledger(db)
        let attempt = await refusal(
            from: makeRequest(anchor: first.childESStateID, key: nil), stub: stub)
        let refused = try XCTUnwrap(attempt)
        XCTAssertEqual(refused.cause, .snapshotInconsistent)
        XCTAssertEqual(refused.phase, .p1)
        XCTAssertEqual(stub.calls, 1, "refusal happens before any model call")
        XCTAssertEqual(try ledger(db), before, "a refusal writes no state or settlement")
    }

    // MARK: - 4) Changed source under `allow_safe_recompute`: one new commit

    func testChangedSourceRecomputesUnderAllowSafeRecompute() async throws {
        let db = try openDatabase()
        let anchor = try stageAnchor(db)
        let stub = Stub()
        stub.configure(text: "FIRST-9004")

        let first = try await runNativeManagedContinuation(
            request: makeRequest(anchor: anchor, key: "recompute-9004"),
            modelPath: modelPath, generate: generator(stub))
        try rewriteNotes("alpha beta gamma delta")
        stub.configure(text: "SECOND-9004")

        let second = try await runNativeManagedContinuation(
            request: makeRequest(
                anchor: first.childESStateID, policy: .allowSafeRecompute,
                key: "recompute-9004b"),
            modelPath: modelPath, generate: generator(stub))

        XCTAssertTrue(second.recomputed, "a permitted recompute is reported as such")
        XCTAssertFalse(second.reusedExecution)
        XCTAssertEqual(second.modelCalls, 1)
        XCTAssertEqual(second.settlementsWritten, 1)
        XCTAssertEqual(second.content, "SECOND-9004")
        XCTAssertEqual(stub.calls, 2)
        XCTAssertNotEqual(second.declaredSnapshotID, first.declaredSnapshotID)

        let finalID = try XCTUnwrap(
            db.settlementInputSnapshotObjectID(settlementID: second.settlementID))
        let final = try SimiGoSnapshotContract.Final.decode(try db.readObject(finalID))
        XCTAssertTrue(final.replayable)
    }

    // MARK: - 5) Same key, different inputs: conflict inside P2

    func testSameKeyWithChangedInputsConflictsInsideP2() async throws {
        let db = try openDatabase()
        let anchor = try stageAnchor(db)
        let stub = Stub()
        stub.configure(text: "KEYED-9005")

        _ = try await runNativeManagedContinuation(
            request: makeRequest(anchor: anchor, key: "conflict-9005"),
            modelPath: modelPath, generate: generator(stub))
        try rewriteNotes("alpha beta gamma epsilon")

        let before = try ledger(db)
        let attempt = await refusal(
            from: makeRequest(anchor: anchor, key: "conflict-9005"), stub: stub)
        let refused = try XCTUnwrap(attempt)

        XCTAssertEqual(refused.cause, .idempotencyConflict)
        XCTAssertEqual(refused.phase, .p2)
        XCTAssertEqual(stub.calls, 2, "the model ran before the conflict was detected")
        XCTAssertEqual(
            try ledger(db), before,
            "a P2 refusal writes no second state or settlement")
    }

    // MARK: - 6) Race: two lanes, one key -> exactly one commit

    /// Holds both lanes inside G so neither P2 can run before the other has read
    /// P1's (empty) idempotency lookup. Without the pair arriving the test would
    /// hang until xcodebuild's per-test timeout, which is the intended signal:
    /// a lane that refuses before G would make this assertion meaningless.
    private actor Rendezvous {
        private let expected: Int
        private var arrivals = 0
        private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []
        private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
        private var released = false

        init(_ expected: Int) { self.expected = expected }

        func arrive() {
            arrivals += 1
            guard arrivals >= expected else { return }
            let waiters = arrivalWaiters
            arrivalWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }

        func waitForAll() async {
            if arrivals >= expected { return }
            await withCheckedContinuation { arrivalWaiters.append($0) }
        }

        func release() {
            released = true
            let waiters = releaseWaiters
            releaseWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }

        func waitForRelease() async {
            if released { return }
            await withCheckedContinuation { releaseWaiters.append($0) }
        }
    }

    private struct RaceOutcome: Sendable {
        var committed = false
        var modelCalls = 0
        var settlementsWritten = 0
        var cause: SimiGoManagedRefusal.Cause?
        var phase: SimiGoManagedRefusal.Phase?
        var error: String?
    }

    private struct RaceLane: Sendable {
        let modelPath: String
        let generate: ManagedContinuationGenerate

        func run(_ request: ManagedContinuationRequest) async -> RaceOutcome {
            do {
                let result = try await runNativeManagedContinuation(
                    request: request, modelPath: modelPath, generate: generate)
                return RaceOutcome(
                    committed: true, modelCalls: result.modelCalls,
                    settlementsWritten: result.settlementsWritten)
            } catch let failure as ManagedContinuationFailure {
                if case .refused(let refusal) = failure {
                    return RaceOutcome(cause: refusal.cause, phase: refusal.phase)
                }
                return RaceOutcome(error: "\(failure)")
            } catch {
                return RaceOutcome(error: "\(error)")
            }
        }
    }

    func testConcurrentSameKeyCommitsExactlyOnce() async throws {
        let db = try openDatabase()
        let anchor = try stageAnchor(db)
        let stub = Stub()
        stub.configure(text: "RACE-9007")
        let rendezvous = Rendezvous(2)

        let lane = RaceLane(modelPath: modelPath, generate: { _, messages in
            let text = stub.record(messages)
            await rendezvous.arrive()
            await rendezvous.waitForRelease()
            return GenerationResult(text: text, usage: nil, completion: .complete)
        })

        let before = try ledger(db)
        let key = "race-9007"
        let requestA = makeRequest(anchor: anchor, key: key)
        let requestB = makeRequest(anchor: anchor, key: key)
        async let first = lane.run(requestA)
        async let second = lane.run(requestB)
        await rendezvous.waitForAll()
        await rendezvous.release()
        let outcomes = await [first, second]

        XCTAssertNil(outcomes.compactMap(\.error).first)
        XCTAssertEqual(stub.calls, 2, "both lanes reached the model before either committed")

        let committed = outcomes.filter(\.committed)
        let refused = outcomes.filter { !$0.committed && $0.error == nil }
        XCTAssertEqual(committed.count, 1, "one key owns exactly one execution")
        XCTAssertEqual(refused.count, 1)
        XCTAssertEqual(committed.first?.modelCalls, 1)
        XCTAssertEqual(committed.first?.settlementsWritten, 1)
        XCTAssertEqual(refused.first?.cause, .idempotencyConflict)
        XCTAssertEqual(refused.first?.phase, .p2)

        let after = try ledger(db)
        XCTAssertEqual(after.states, before.states + 1)
        XCTAssertEqual(after.settlements, before.settlements + 1)

        let replay = try await runNativeManagedContinuation(
            request: makeRequest(anchor: anchor, key: key),
            modelPath: modelPath, generate: generator(stub))
        XCTAssertTrue(replay.reusedExecution, "the committed lane is now the replay owner")
        XCTAssertEqual(replay.modelCalls, 0)
        XCTAssertEqual(stub.calls, 2)
    }

    // MARK: - 7) Unknown root: refused before generation

    func testUnknownRootIsRefusedBeforeGeneration() async throws {
        let db = try openDatabase()
        let anchor = try stageAnchor(db)
        let stub = Stub()
        stub.configure(text: "UNREACHABLE")

        let before = try ledger(db)
        let attempt = await refusal(
            from: makeRequest(anchor: anchor, key: nil, roots: ["work-missing"]),
            stub: stub)
        let refused = try XCTUnwrap(attempt)

        XCTAssertEqual(refused.cause, .snapshotSourceUnreadable)
        XCTAssertEqual(refused.phase, .p1)
        XCTAssertEqual(stub.calls, 0)
        XCTAssertEqual(try ledger(db), before)
    }

    // MARK: - 8) T-1: an unfinished generation cannot become a settlement

    /// The managed entry owns the only model call the pipeline makes, and it runs
    /// inside G — after the snapshot was declared, before P2 writes. So a capped,
    /// cancelled or unattested output has to be refused exactly there: the model
    /// cost is real and already spent, while the settlement that would have made
    /// it reusable never exists.
    func testUnfinishedGenerationIsRefusedBeforeAnyWrite() async throws {
        for verdict in [
            GenerationCompletion.capped, .cancelled, .unconfirmed,
        ] {
            let db = try openDatabase()
            let anchor = try stageAnchor(db)
            let stub = Stub()
            stub.configure(text: "MANAGED-PARTIAL")
            let before = try ledger(db)

            let attempt = await refusal(
                from: makeRequest(anchor: anchor, key: "t1-\(verdict.wireName)"),
                generate: generator(stub, completion: verdict))
            let refused = try XCTUnwrap(attempt, "\(verdict) produced no typed refusal")

            XCTAssertEqual(refused.cause, .generationIncomplete)
            XCTAssertEqual(refused.phase, .g, "the verdict is only knowable after the model ran")
            XCTAssertEqual(refused.evidence["completion"], verdict.wireName)
            XCTAssertEqual(stub.calls, 1)
            XCTAssertEqual(
                try ledger(db), before,
                "\(verdict) commits no state and no settlement, so it cannot be reused")

            // The refusal is not a cacheable terminal either: a second attempt with
            // a finished generation is an ordinary fresh run, not a replay of the
            // unfinished one.
            let fresh = try await runNativeManagedContinuation(
                request: makeRequest(anchor: anchor, key: "t1-\(verdict.wireName)-retry"),
                modelPath: modelPath, generate: generator(stub))
            XCTAssertFalse(fresh.reusedExecution)
            XCTAssertEqual(fresh.settlementsWritten, 1)
        }
    }
}
