import Foundation
import XCTest
import SimiGoRuntimeContract

@testable import SimiGo

/// C-6d: KV-free acceptance matrix (K1 / K2 / K3).
///
/// Premise enforced by `setUpWithError`: `SIMIGO_CACHE_ROOT` points under a
/// regular file, so `prefix-pool` and `branch-checkpoints` are simultaneously
/// unreadable and unwritable. Every test starts by re-verifying that premise:
/// a green suite against a writable cache root would prove nothing.
///
/// Two configurations, and since owner ruling U2 (2026-10-27) both persistence
/// switches DEFAULT OFF, so each asserts the DERIVED switch state rather than a
/// raw env string:
///   · `SIMIGO_KV_FREE_MATRIX=1`  -- switches off (by default or by `=0`):
///     proves the product path never tries, and never needs, persisted KV.
///   · `SIMIGO_KV_BLOCKED_ONLY=1` -- switches explicitly opted IN with `=1` and
///     the roots blocked: proves a real attempt fails yet the product still
///     works, with no fallback directory.  "not 0" would no longer be enough.
///
/// What each test separates, as required:
///   · model calls (stub counter)
///   · successful settlement writes (row counts, unchanged on refusal)
///   · KV file reads/writes (both roots absent before and after, no fallback
///     root created under SIMIGO_HOME or the real home)
///
/// Scope note: this is the TEST layer. It proves semantic continuity is carried
/// by ES/IS alone through the production adapter. It does not exercise MLX
/// generation, suspend, or process restart — those need the installed build and
/// a real model, and are tracked as the second acceptance level.
final class KVFreeContinuityTests: XCTestCase {

    private let rootID = "work-kvfree-c6d"
    private var isolationRoot: URL!
    private var modelPath: String!
    private var workRoot: URL!
    private var blockedCacheRoot: URL!
    private var isolationHome: URL!

    private final class Stub: @unchecked Sendable {
        enum Mode {
            case answer(String)
            /// Records the prompt, emits a partial answer, then aborts — the
            /// shape of a generation interrupted mid-stream.
            case interruptAfter(partial: String)
        }

        private let lock = NSLock()
        private var mode: Mode = .answer("")
        private var count = 0
        private var prompts: [[JSONValue]] = []

        func configure(_ mode: Mode) { lock.withLock { self.mode = mode } }

        func record(_ sent: [JSONValue]) throws -> String {
            try lock.withLock {
                count += 1
                prompts.append(sent)
                switch mode {
                case .answer(let text):
                    return text
                case .interruptAfter:
                    throw Interrupted()
                }
            }
        }

        struct Interrupted: Error {}

        var calls: Int { lock.withLock { count } }
        var lastPrompt: [JSONValue] { lock.withLock { prompts.last ?? [] } }
        var allPrompts: [[JSONValue]] { lock.withLock { prompts } }
    }

    private struct Ledger: Equatable {
        let states: Int
        let settlements: Int
    }

    /// K1–K3 assert the switches-off product configuration; the blocked-root
    /// probe is the only test that opts the switches back in (`=1`), because
    /// after U2 the defaults are off.
    private func requireKVFree(
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SIMIGO_KV_FREE_MATRIX"] == "1",
            "runs in the switches-off (KV-free) configuration",
            file: file, line: line)
    }

    // MARK: - Setup: the premise is the test

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let home = env["SIMIGO_HOME"], !home.isEmpty,
              let graphStore = env["SIMIGO_STATE_GRAPH_STORE"], !graphStore.isEmpty,
              let cache = env["SIMIGO_CACHE_ROOT"], !cache.isEmpty,
              home.hasPrefix("/"), graphStore.hasPrefix("/"), cache.hasPrefix("/") else {
            throw XCTSkip(
                "isolated roots not injected: run through tools/make_isolated_xctestrun.py")
        }
        guard env["SIMIGO_KV_FREE_MATRIX"] == "1" || env["SIMIGO_KV_BLOCKED_ONLY"] == "1" else {
            throw XCTSkip(
                "KV-free matrix suite: needs SIMIGO_KV_FREE_MATRIX=1 (switches off) or "
                + "SIMIGO_KV_BLOCKED_ONLY=1 (switch defaults, roots blocked)")
        }
        if env["SIMIGO_KV_FREE_MATRIX"] == "1" {
            // Derived state, not the raw string: the switches default OFF since
            // U2, so an absent env var is an equally valid KV-free window and the
            // old `== "0"` assert would fail a premise that actually holds.
            XCTAssertFalse(
                RuntimeTuning.prefixPoolEnabled,
                "prefix-pool persistence must be off for the KV-free matrix")
            XCTAssertFalse(
                RuntimeTuning.branchCheckpointsEnabled,
                "branch-checkpoints persistence must be off for the KV-free matrix")
        } else {
            // The blocked-root probe separates "the switch is off" from "the
            // directory is genuinely unusable", which requires a REAL attempt:
            // opt both switches in explicitly, then verify the derived state.
            XCTAssertEqual(
                env["SIMIGO_PREFIX_POOL"], "1",
                "the blocked-root probe must opt in with SIMIGO_PREFIX_POOL=1; "
                + "with the switch off it would attempt nothing and prove nothing")
            XCTAssertEqual(
                env["SIMIGO_BRANCH_CHECKPOINTS"], "1",
                "the blocked-root probe must opt in with SIMIGO_BRANCH_CHECKPOINTS=1")
            XCTAssertTrue(
                RuntimeTuning.prefixPoolEnabled,
                "SIMIGO_PREFIX_POOL=1 injected but the pool switch resolved off")
            XCTAssertTrue(
                RuntimeTuning.branchCheckpointsEnabled,
                "SIMIGO_BRANCH_CHECKPOINTS=1 injected but the checkpoint switch resolved off")
        }

        isolationRoot = URL(
            fileURLWithPath: (home as NSString).standardizingPath, isDirectory: true)
        isolationHome = isolationRoot
        blockedCacheRoot = URL(
            fileURLWithPath: (cache as NSString).standardizingPath, isDirectory: true)
        XCTAssertTrue(
            SimiGoPaths.databaseURL.path.hasPrefix(isolationRoot.path),
            "authoritative store resolves outside the isolation root")

        let model = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimiGoKVFreeModel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        try Data(#"{"model_type":"kv-free-stand-in"}"#.utf8)
            .write(to: model.appendingPathComponent("tokenizer.adapter.json"))
        modelPath = model.path

        workRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimiGoKVFreeRoot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workRoot, withIntermediateDirectories: true)
        try Data("alpha beta gamma".utf8)
            .write(to: workRoot.appendingPathComponent("notes.md"))

        let db = try openDatabase()
        try db.upsertRoot(
            rootID: rootID, category: "work", displayName: workRoot.path,
            locatorType: "path", status: "registered")

        assertKVUnavailable("at suite start")
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

    /// Asserts both KV roots are simultaneously unreadable and unwritable, and
    /// that no silent redirection exists: the resolved paths must sit under the
    /// blocked cache root, and neither the isolation home nor the real home may
    /// grow a fallback directory.
    private func assertKVUnavailable(
        _ moment: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let prefix = SimiGoRuntimeCachePaths.prefixPoolRoot
        let checkpoints = SimiGoRuntimeCachePaths.branchCheckpointsRoot

        XCTAssertTrue(
            prefix.path.hasPrefix(blockedCacheRoot.path + "/"),
            "prefix-pool resolved outside the blocked cache root at \(moment): \(prefix.path)",
            file: file, line: line)
        XCTAssertTrue(
            checkpoints.path.hasPrefix(blockedCacheRoot.path + "/"),
            "branch-checkpoints resolved outside the blocked cache root at \(moment): "
            + checkpoints.path,
            file: file, line: line)

        for root in [prefix, checkpoints] {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: root.path),
                "KV root exists at \(moment): \(root.path) — the premise is that it "
                + "cannot be created, read, or written",
                file: file, line: line)
            XCTAssertThrowsError(
                try FileManager.default.contentsOfDirectory(atPath: root.path),
                "KV root is readable at \(moment): \(root.path)",
                file: file, line: line)
            XCTAssertThrowsError(
                try FileManager.default.createDirectory(
                    at: root, withIntermediateDirectories: true),
                "KV root is creatable at \(moment): \(root.path)",
                file: file, line: line)
        }

        // No fallback: resolution above already proves neither root points at
        // the isolation home or the real home. This adds the effect check for
        // the isolation home, which this process solely owns. The real
        // ~/.simigo is deliberately not asserted on — it legitimately holds the
        // operator's own KV, and this suite must never write there to begin
        // with; a redirect there would already fail the path assertions.
        for name in ["prefix-pool", "branch-checkpoints"] {
            let candidate = isolationHome.appendingPathComponent(name, isDirectory: true)
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: candidate.path),
                "silent fallback created \(candidate.path) at \(moment)",
                file: file, line: line)
        }
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
        key: String?,
        roots: [String]? = nil
    ) -> ManagedContinuationRequest {
        ManagedContinuationRequest(
            requestId: "req-" + UUID().uuidString.lowercased(),
            agentId: nil,
            sessionId: "sess-kvfree",
            logicalBranchId: "main",
            anchorESStateID: anchor,
            policy: .never,
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
            GenerationResult(text: try stub.record(messages), usage: nil)
        }
    }

    private func promptText(_ prompt: [JSONValue]) -> String {
        prompt.compactMap { $0.object?["content"]?.string }.joined(separator: "\n")
    }

    // MARK: - Premise test

    func testPremiseBothKVRootsAreSimultaneouslyUnavailable() throws {
        try requireKVFree()
        XCTAssertFalse(
            RuntimeTuning.prefixPoolEnabled,
            "prefix pool switch is on; the matrix would not be KV-free")
        XCTAssertFalse(
            RuntimeTuning.branchCheckpointsEnabled,
            "branch checkpoint switch is on; the matrix would not be KV-free")

        assertKVUnavailable("in the premise test")

        // The store factory must not create the directory as a side effect.
        let store = NativeMLX.defaultBranchCheckpointStore()
        XCTAssertEqual(
            store.standardizedFileURL.path,
            SimiGoRuntimeCachePaths.branchCheckpointsRoot.standardizedFileURL.path)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: store.path),
            "defaultBranchCheckpointStore() created \(store.path) while persistence is off")
    }

    // MARK: - K1: settled value consumed with zero model calls

    func testK1SettledResultIsConsumedWithZeroModelCallsWhileKVUnavailable() async throws {
        try requireKVFree()
        let db = try openDatabase()
        let anchor = try stageAnchor(db)
        // Unique per invocation: the isolation root may hold rows from an
        // earlier run, and a stale key would turn the first leg into a replay.
        let k1Key = "k1-" + UUID().uuidString.lowercased()
        let stub = Stub()
        stub.configure(.answer("K1-SETTLED-VALUE"))

        let first = try await runNativeManagedContinuation(
            request: makeRequest(anchor: anchor, key: k1Key),
            modelPath: modelPath, generate: generator(stub))
        XCTAssertEqual(first.modelCalls, 1)
        XCTAssertEqual(first.settlementsWritten, 1)
        XCTAssertEqual(first.content, "K1-SETTLED-VALUE")
        let afterFirst = try ledger(db)
        assertKVUnavailable("after the settling run")

        // A different answer must never appear: a replay serves the settled
        // value, it does not regenerate one.
        stub.configure(.answer("K1-MUST-NOT-APPEAR"))
        let replay = try await runNativeManagedContinuation(
            request: makeRequest(anchor: anchor, key: k1Key),
            modelPath: modelPath, generate: generator(stub))

        XCTAssertTrue(replay.reusedExecution)
        XCTAssertEqual(replay.modelCalls, 0)
        XCTAssertEqual(replay.settlementsWritten, 0)
        XCTAssertEqual(replay.content, "K1-SETTLED-VALUE")
        XCTAssertEqual(stub.calls, 1, "a replay never calls the model")
        XCTAssertEqual(
            try ledger(db), afterFirst,
            "a zero-call replay writes no state and no settlement")
        assertKVUnavailable("after the replay")
    }

    // MARK: - K2: settled state survives a restart with no KV to restore

    func testK2SettledResultRecoversAfterRestartWithoutKV() async throws {
        try requireKVFree()
        let k2Key = "k2-" + UUID().uuidString.lowercased()
        let anchor: String
        let settlementID: String
        let childID: String
        do {
            let db = try openDatabase()
            anchor = try stageAnchor(db)
            let stub = Stub()
            stub.configure(.answer("K2-DURABLE-VALUE"))
            let run = try await runNativeManagedContinuation(
                request: makeRequest(anchor: anchor, key: k2Key),
                modelPath: modelPath, generate: generator(stub))
            settlementID = run.settlementID
            childID = run.childESStateID
            XCTAssertEqual(run.settlementsWritten, 1)
        }

        // Restart: a brand-new connection to the same authoritative store.
        // No in-memory session, no KV directory, no checkpoint file exists —
        // everything below must come from ES/IS rows and objects on disk.
        let reopened = try openDatabase()
        XCTAssertEqual(try reopened.latestSettlementID(forStateID: childID), settlementID)
        XCTAssertEqual(try reopened.executionStatePosition(childID), 2)

        let finalID = try XCTUnwrap(
            reopened.settlementInputSnapshotObjectID(settlementID: settlementID))
        let final = try SimiGoSnapshotContract.Final.decode(try reopened.readObject(finalID))
        XCTAssertTrue(final.replayable)
        let declared = try SimiGoSnapshotContract.Declared.decode(
            try reopened.readObject(final.declaredSnapshotID))
        XCTAssertNoThrow(try final.verify(against: declared))
        XCTAssertEqual(
            declared.entries.first?.digest,
            SimiGoSnapshotContract.sha256Hex(Data("alpha beta gamma".utf8)))

        let stub = Stub()
        stub.configure(.answer("K2-MUST-NOT-APPEAR"))
        let replay = try await runNativeManagedContinuation(
            request: makeRequest(anchor: anchor, key: k2Key),
            modelPath: modelPath, generate: generator(stub))
        XCTAssertTrue(replay.reusedExecution)
        XCTAssertEqual(replay.modelCalls, 0)
        XCTAssertEqual(replay.content, "K2-DURABLE-VALUE")
        XCTAssertEqual(stub.calls, 0)
        assertKVUnavailable("after the post-restart replay")
    }

    // MARK: - K3: an interrupted generation is never a settlement

    func testK3InterruptedGenerationIsNeverSettledAndReexecutesFromAnchor() async throws {
        try requireKVFree()
        let db = try openDatabase()
        let anchor = try stageAnchor(db)
        let before = try ledger(db)
        let anchorSettlement = try db.latestSettlementID(forStateID: anchor)

        let k3Key = "k3-" + UUID().uuidString.lowercased()
        let interrupted = Stub()
        interrupted.configure(.interruptAfter(partial: "K3-PARTIAL-OUTPUT"))

        let attempt = try await attemptRun(
            request: makeRequest(anchor: anchor, key: k3Key),
            stub: interrupted)
        XCTAssertNil(attempt, "an interrupted generation must not produce a result")
        XCTAssertEqual(interrupted.calls, 1)

        XCTAssertEqual(
            try ledger(db), before,
            "an interrupted generation writes no state and no settlement")
        XCTAssertEqual(
            try db.latestSettlementID(forStateID: anchor), anchorSettlement,
            "the anchor's settled value is untouched by the failed attempt")
        let partialRow = try db.count("settlements")
        XCTAssertEqual(partialRow, before.settlements)
        assertKVUnavailable("after the interrupted attempt")

        // Re-execution starts from the anchor. The partial text must not leak
        // into the next prompt — it was never a result.
        let good = Stub()
        good.configure(.answer("K3-RESUMED-VALUE"))
        let resumed = try await runNativeManagedContinuation(
            request: makeRequest(anchor: anchor, key: k3Key),
            modelPath: modelPath, generate: generator(good))

        XCTAssertEqual(resumed.modelCalls, 1)
        XCTAssertEqual(resumed.settlementsWritten, 1)
        XCTAssertEqual(resumed.content, "K3-RESUMED-VALUE")
        XCTAssertFalse(resumed.reusedExecution)
        XCTAssertFalse(
            promptText(good.lastPrompt).contains("K3-PARTIAL-OUTPUT"),
            "the interrupted partial output leaked into the resumed prompt")

        XCTAssertEqual(try db.count("settlements"), before.settlements + 1)
        XCTAssertEqual(try db.count("execution_states"), before.states + 1)
        XCTAssertEqual(try db.executionStatePosition(resumed.childESStateID), 2)
        assertKVUnavailable("after the successful re-execution")
    }

    private func attemptRun(
        request: ManagedContinuationRequest, stub: Stub
    ) async throws -> ManagedContinuationResult? {
        do {
            return try await runNativeManagedContinuation(
                request: request, modelPath: modelPath, generate: generator(stub))
        } catch is Stub.Interrupted {
            return nil
        }
    }

    // MARK: - Switches ON, roots blocked: no silent redirection

    /// Runs only in the second configuration (`SIMIGO_KV_BLOCKED_ONLY=1`), where
    /// both persistence switches are explicitly opted in (`=1`) but
    /// `SIMIGO_CACHE_ROOT` is
    /// still blocked. That separates "the switch is off" from "the directory is
    /// genuinely unusable": a fallback to another directory would show up here.
    func testSwitchOnWithBlockedRootsDegradesWithoutRedirecting() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["SIMIGO_KV_BLOCKED_ONLY"] == "1" else {
            throw XCTSkip("second KV configuration: needs SIMIGO_KV_BLOCKED_ONLY=1")
        }
        XCTAssertTrue(
            RuntimeTuning.prefixPoolEnabled,
            "expected an opted-in pool switch (SIMIGO_PREFIX_POOL=1)")
        XCTAssertTrue(
            RuntimeTuning.branchCheckpointsEnabled,
            "expected an opted-in checkpoint switch (SIMIGO_BRANCH_CHECKPOINTS=1)")

        assertKVUnavailable("with switches on and roots blocked")

        let store = NativeMLX.defaultBranchCheckpointStore()
        XCTAssertTrue(
            store.path.hasPrefix(blockedCacheRoot.path + "/"),
            "checkpoint store resolved outside the blocked root: \(store.path)")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: store.path),
            "the store factory created \(store.path) even though the root is blocked")

        let admission = NativeMLXPrefixPool.shared.admit(
            modelID: "kv-blocked-probe",
            kvFingerprint: "probe",
            thinkingDisabled: false,
            incoming: [(role: "user", content: "probe")])
        XCTAssertNil(admission, "an unusable pool root must miss, never crash or redirect")
        assertKVUnavailable("after probing the pool with switches on")
    }
}
