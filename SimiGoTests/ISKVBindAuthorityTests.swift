import Foundation
import XCTest
import SimiGo2Experimental
import SimiGoRuntimeContract
@testable import SimiGo

/// A-2 directed proof: the IS settlement is the PRE-AUTHORITY for KV reuse on
/// the continuation edge. Model-free by construction (no engine, no weights, no
/// pool artifact on disk) — what is proven is the product code a real request
/// runs between the native gate, the authoritative store, IS admission and the
/// prefix-pool bind site:
///
/// * a settled turn's prefix representation is recorded as derived binding rows
///   in the SAME transaction as the settlement (digests only, never a path);
/// * IS admission carries those rows out, so a continuation knows exactly which
///   boundary its parent settlement authorized;
/// * the pool bind site accepts ONLY that boundary: a different covered length,
///   a different content claim or a different KV namespace is refused;
/// * a settlement with no KV row grants nothing — the governed continuation is
///   refused and falls back to cold prefill, while an ungoverned (everyday)
///   request stays byte-identical to before A-2;
/// * a grant is consumed once and is keyed to its own child ES: it never leaks
///   to another execution.
///
/// NOT PROVEN HERE, and deliberately not claimed: that a real model actually
/// avoided the forward pass. On this machine the installed model cannot export
/// a v1 prefix snapshot at all, so the KV-level cross-ES reuse stays NO-GO and
/// is owned by task A-3. This file proves the authority decision, not the saving.
///
/// Isolation: runs only against the redirected roots the isolated xctestrun
/// injects (`SIMIGO_HOME`, `SIMIGO_STATE_GRAPH_STORE`); otherwise XCTSkip.
final class ISKVBindAuthorityTests: XCTestCase {

    private var isolationRoot: URL!
    private var modelPath: String!

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let home = env["SIMIGO_HOME"], !home.isEmpty,
              let graphStore = env["SIMIGO_STATE_GRAPH_STORE"], !graphStore.isEmpty,
              home.hasPrefix("/"), graphStore.hasPrefix("/") else {
            throw XCTSkip(
                "isolated roots not injected: run through tools/run_isolated_tests.sh "
                + "(SIMIGO_HOME / SIMIGO_STATE_GRAPH_STORE) so no real state is written")
        }
        isolationRoot = URL(fileURLWithPath: (home as NSString).standardizingPath, isDirectory: true)
        XCTAssertTrue(
            SimiGoPaths.databaseURL.path.hasPrefix(isolationRoot.path),
            "authoritative store resolves outside the isolation root: \(SimiGoPaths.databaseURL.path)")
        XCTAssertTrue(
            ExecutionStateGraphStore.defaultStoreURL().path.hasPrefix(
                (graphStore as NSString).standardizingPath),
            "reference graph resolves outside the isolated state-graph root")

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimiGoA2ModelFree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"model_type":"a2-kv-binding-stand-in"}"#.utf8).write(
            to: dir.appendingPathComponent("tokenizer.adapter.json"))
        modelPath = dir.path
    }

    override func tearDown() {
        if let modelPath {
            try? FileManager.default.removeItem(atPath: modelPath)
        }
        super.tearDown()
    }

    // MARK: - Helpers

    /// The namespace the pool derives for a real model/KV pair — the fingerprint
    /// carries the thinking flag, so the test uses the production derivation
    /// instead of inventing a second key format.
    private func namespace(
        modelID: String = "a2-test-model", kvFingerprint: String = "fp-42",
        thinkingDisabled: Bool = false
    ) -> PrefixPoolNamespace {
        NativeMLXPrefixPool.namespace(
            modelID: modelID, kvFingerprint: kvFingerprint,
            thinkingDisabled: thinkingDisabled)
    }

    private func representation(in namespace: PrefixPoolNamespace, boundaryHash: UInt64 = 0xdead_beef)
        -> SimiGoSettlementKVBinding.Representation {
        SimiGoSettlementKVBinding.Representation(
            modelID: namespace.modelID, kvFingerprint: namespace.kvFingerprint,
            tokenCount: 12, boundaryHash: boundaryHash)
    }

    @MainActor
    private func stageUnsettledAnchor(value: String) throws -> String {
        let store = ExecutionStateGraphStore()
        let root = try store.create()
        try store.continueState(root, input: value)
        return root.id
    }

    @MainActor
    private func store() -> ExecutionStateGraphStore { ExecutionStateGraphStore() }

    /// Settle one continuation over the REAL adapter path with a KV
    /// representation, then admit it back through the real IS admission.
    @MainActor
    private func settleAndAdmit(
        tag: String, kvRepresentation: SimiGoSettlementKVBinding.Representation?
    ) throws -> (outcome: ContinuationSettlementOutcome, admitted: SimiGoISAdmission.Admitted) {
        let anchor = try stageUnsettledAnchor(value: tag)
        let child = "es-child-\(UUID().uuidString.lowercased())"
        let outcome = try settleForNativeMLXContinuation(
            store: store(),
            request: ContinuationSettlementRequest(
                generatedText: "RESULT=\(tag)",
                parentESStateID: anchor,
                childESStateID: child,
                verifiedBindings: ["next_input": .string(tag)]),
            modelPath: modelPath!,
            kvRepresentation: kvRepresentation)
        let admitted = try store().admitContinuation(
            stateID: outcome.childESStateID,
            consumer: SimiGoProducerIdentity.identity(fromPath: modelPath!))
        return (outcome, admitted)
    }

    // MARK: - Write side: the settlement names its own prefix representation

    /// The settled turn's representation lands in `settlement_bindings` as
    /// digests, in the same commit as the settlement, and IS admission hands it
    /// back to the next execution.
    @MainActor
    func testSettlementRecordsKVBindingAndAdmissionCarriesItOut() async throws {
        let ns = namespace()
        let settledRepresentation = representation(in: ns, boundaryHash: 0x1122_3344_5566_7788)

        let (outcome, admitted) = try settleAndAdmit(
            tag: "A2-KV-RECORD-7101", kvRepresentation: settledRepresentation)

        let rows = try XCTUnwrap(store().esis).settlementBindings(settlementID: outcome.settlementID)
        let expected = SimiGoSettlementKVBinding.bindings(for: settledRepresentation)
        XCTAssertEqual(rows[SimiGoSettlementKVBinding.poolKey], expected[SimiGoSettlementKVBinding.poolKey],
                       "the settlement must name the exact pool boundary it exported")
        XCTAssertEqual(
            rows[SimiGoSettlementKVBinding.cacheFingerprint],
            expected[SimiGoSettlementKVBinding.cacheFingerprint])
        // Digests only — no model path, no token array, no weight material. The
        // recorded form is exactly what `bindings(for:)` produces, so a raw pool
        // key or namespace can never appear in the table.
        for (name, value) in rows.filter({ $0.key.hasPrefix("kv.") }) {
            XCTAssertEqual(value.count, 64, "\(name) must be a digest")
            XCTAssertFalse(value.contains("|"), "\(name) must not carry the raw pool key")
        }

        // Admission read-back: the governed continuation receives exactly the
        // two kv.* rows (constraint and producer rows stay out).
        XCTAssertEqual(admitted.kvBindings, expected,
                       "IS admission must carry the settled KV rows to the next ES")
        XCTAssertEqual(Set(admitted.kvBindings.keys),
                       [SimiGoSettlementKVBinding.poolKey, SimiGoSettlementKVBinding.cacheFingerprint])
    }

    // MARK: - Read side: the bind site authorizes one boundary only

    /// Matching, mismatched-length, mismatched-namespace and missing bindings,
    /// all decided by the same code the pool bind site runs.
    @MainActor
    func testBindSiteAcceptsOnlyTheSettledBoundary() async throws {
        let ns = namespace()
        let settledRepresentation = representation(in: ns, boundaryHash: 0x0a0b_0c0d_0e0f_1011)
        let (_, admitted) = try settleAndAdmit(
            tag: "A2-KV-EVALUATE-7102", kvRepresentation: settledRepresentation)
        let recorded = admitted.kvBindings

        // The boundary the settlement actually exported: authorized.
        XCTAssertEqual(
            NativeMLXPrefixPool.bindVerdict(
                .verdict(.authorized(recorded)), namespace: ns,
                tokenCount: settledRepresentation.tokenCount,
                boundaryHash: settledRepresentation.boundaryHash),
            .allowed)

        // Same artifact, one more token covered: the content claim differs.
        let longer = NativeMLXPrefixPool.bindVerdict(
            .verdict(.authorized(recorded)), namespace: ns,
            tokenCount: settledRepresentation.tokenCount + 1,
            boundaryHash: settledRepresentation.boundaryHash)
        XCTAssertEqual(longer, .rejected(reason: SimiGoSettlementKVBinding.Refusal.poolKeyMismatch.rawValue))
        XCTAssertFalse(longer.permitsBind, "a longer reuse than settled must not bind")

        // Tampered content claim at the right length.
        XCTAssertEqual(
            NativeMLXPrefixPool.bindVerdict(
                .verdict(.authorized(recorded)), namespace: ns,
                tokenCount: settledRepresentation.tokenCount,
                boundaryHash: settledRepresentation.boundaryHash &+ 1),
            .rejected(reason: SimiGoSettlementKVBinding.Refusal.poolKeyMismatch.rawValue))

        // Different KV namespace (different kvSettings / thinking flag) — the same
        // boundary hash is a different representation.
        let otherNamespace = namespace(kvFingerprint: "fp-other")
        let otherFingerprint = NativeMLXPrefixPool.bindVerdict(
            .verdict(.authorized(recorded)), namespace: otherNamespace,
            tokenCount: settledRepresentation.tokenCount,
            boundaryHash: settledRepresentation.boundaryHash)
        XCTAssertEqual(
            otherFingerprint,
            .rejected(reason: SimiGoSettlementKVBinding.Refusal.fingerprintMismatch.rawValue))

        // Missing rows fail closed (a settlement from before this wiring).
        XCTAssertEqual(
            NativeMLXPrefixPool.bindVerdict(.verdict(.authorized([:])), namespace: ns,
                                            tokenCount: 12, boundaryHash: 1),
            .rejected(reason: SimiGoSettlementKVBinding.Refusal.fingerprintAbsent.rawValue))
        var halfOnly = recorded
        halfOnly[SimiGoSettlementKVBinding.poolKey] = nil
        XCTAssertEqual(
            NativeMLXPrefixPool.bindVerdict(.verdict(.authorized(halfOnly)), namespace: ns,
                                            tokenCount: settledRepresentation.tokenCount,
                                            boundaryHash: settledRepresentation.boundaryHash),
            .rejected(reason: SimiGoSettlementKVBinding.Refusal.poolKeyAbsent.rawValue))
    }

    // MARK: - No KV row => no authority

    /// A settlement that recorded no prefix representation grants no KV reuse:
    /// the governed continuation is refused at the bind site and prefills cold.
    @MainActor
    func testSettlementWithoutKVRepresentationGrantsNothing() async throws {
        let (_, admitted) = try settleAndAdmit(
            tag: "A2-KV-ABSENT-7103", kvRepresentation: nil)
        XCTAssertTrue(admitted.kvBindings.isEmpty,
                      "a settlement with no KV row must not carry authority out")
        XCTAssertEqual(
            admitted.recoveredValue, "A2-KV-ABSENT-7103",
            "the semantic result still settles and stays admissible — only KV reuse is refused")

        let esID = "es-" + UUID().uuidString.lowercased()
        ISKVBindAuthority.shared.register(
            esStateID: esID,
            verdict: admitted.kvBindings.isEmpty
                ? .unauthorized(reason: "no_settled_kv_binding")
                : .authorized(admitted.kvBindings))
        let decision = NativeMLXPrefixPool.bindVerdict(
            ISKVBindAuthority.shared.consume(esStateID: esID),
            namespace: namespace(), tokenCount: 12, boundaryHash: 1)
        XCTAssertEqual(decision, .rejected(reason: "no_settled_kv_binding"))
        XCTAssertFalse(decision.permitsBind)
    }

    // MARK: - Gate lifecycle: unmanaged path, consume-once, no leakage

    /// Everyday requests register nothing and keep A-2's pre-existing behaviour
    /// (`.notGoverned` permits the bind); a registered verdict is consumed once;
    /// and a grant never applies to another execution's ES id.
    @MainActor
    func testGateLifecycleIsConsumeOnceAndNeverLeaks() {
        let ns = namespace()
        let settledRepresentation = representation(in: ns, boundaryHash: 0x9999_8888)
        let recorded = SimiGoSettlementKVBinding.bindings(for: settledRepresentation)

        // Unmanaged = the pool edge as it was before A-2.
        let ungoverned = NativeMLXPrefixPool.bindVerdict(
            ISKVBindAuthority.shared.consume(esStateID: "es-never-registered-\(UUID().uuidString)"),
            namespace: ns, tokenCount: settledRepresentation.tokenCount,
            boundaryHash: settledRepresentation.boundaryHash)
        XCTAssertEqual(ungoverned, .notGoverned)
        XCTAssertTrue(ungoverned.permitsBind, "an ungoverned turn must not be blocked by A-2")

        // Register once, use once.
        let esID = "es-" + UUID().uuidString.lowercased()
        ISKVBindAuthority.shared.register(
            esStateID: esID, verdict: .authorized(recorded))
        XCTAssertEqual(
            NativeMLXPrefixPool.bindVerdict(
                ISKVBindAuthority.shared.consume(esStateID: esID),
                namespace: ns, tokenCount: settledRepresentation.tokenCount,
                boundaryHash: settledRepresentation.boundaryHash),
            .allowed)
        XCTAssertEqual(
            ISKVBindAuthority.shared.consume(esStateID: esID), .notGoverned,
            "a grant must not survive the turn it was issued for")

        // A sibling ES must not inherit another execution's grant.
        let sibling = "es-" + UUID().uuidString.lowercased()
        ISKVBindAuthority.shared.register(esStateID: esID, verdict: .authorized(recorded))
        XCTAssertEqual(
            ISKVBindAuthority.shared.consume(esStateID: sibling), .notGoverned,
            "grants are keyed to the child ES that was admitted")
        XCTAssertEqual(ISKVBindAuthority.shared.consume(esStateID: esID).isGoverned, true)

        // Re-registering the same ES replaces the verdict instead of stacking.
        ISKVBindAuthority.shared.register(esStateID: esID, verdict: .unauthorized(reason: "revoked"))
        XCTAssertEqual(
            ISKVBindAuthority.shared.consume(esStateID: esID),
            .verdict(.unauthorized(reason: "revoked")))
    }

    /// The bound table is bounded: an old unconsumed grant is evicted rather than
    /// growing forever (the everyday path never registers, so evictions here only
    /// drop grants whose request is already gone).
    @MainActor
    func testGateTableStaysBoundedUnderChurn() {
        ISKVBindAuthority.shared.reset()
        let ids = (0..<80).map { _ in "es-" + UUID().uuidString.lowercased() }
        for id in ids {
            ISKVBindAuthority.shared.register(esStateID: id, verdict: .unauthorized(reason: "x"))
        }
        XCTAssertLessThanOrEqual(ISKVBindAuthority.shared.count, 64,
                                "the grant table must stay bounded")
        // The oldest entries were dropped; the newest is still governed.
        XCTAssertEqual(ISKVBindAuthority.shared.peek(esStateID: ids.first!).isGoverned, false)
        XCTAssertEqual(ISKVBindAuthority.shared.peek(esStateID: ids.last!).isGoverned, true)
        ISKVBindAuthority.shared.reset()
    }
}
