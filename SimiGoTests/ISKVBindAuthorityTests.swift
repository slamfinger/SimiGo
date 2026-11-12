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
            ManagedPaths.databaseURL.path.hasPrefix(isolationRoot.path),
            "authoritative store resolves outside the isolation root: \(ManagedPaths.databaseURL.path)")
        XCTAssertTrue(
            ExecutionStateGraphStore.defaultStoreURL().path.hasPrefix(
                (graphStore as NSString).standardizingPath),
            "reference graph resolves outside the isolated state-graph root")

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimiGoA2ModelFree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"model_type":"a2-kv-binding-stand-in"}"#.utf8).write(
            to: dir.appendingPathComponent("tokenizer.adapter.json"))
        // Post-#171: a directory the hub layout cannot name derives its model
        // identity from its weight bytes. The old stand-in carried a tokenizer
        // and nothing else, so it now resolves `.absent` — which every identity
        // gate refuses, exactly as intended. Give it weight bytes so it resolves
        // a real identity the way a local model directory does; the physical
        // gate tests then compare two real identities instead of two absences.
        try Data("a2-stand-in-weights".utf8).write(
            to: dir.appendingPathComponent("model.safetensors"))
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
        -> SettlementKVBinding.Representation {
        SettlementKVBinding.Representation(
            modelID: namespace.modelID, kvFingerprint: namespace.kvFingerprint,
            tokenCount: 12, boundaryHash: boundaryHash)
    }

    /// Stage a settled parent: the continuation-parent dependency edge is
    /// validated against a real, valid parent settlement in the same commit.
    @MainActor
    private func stageSettledAnchor(value: String) throws -> (stateID: String, settlementID: String) {
        let store = ExecutionStateGraphStore()
        let root = try store.create()
        let state = try store.continueState(root, input: value)
        try store.settleProducerResult(
            generatedText: "RESULT=\(value)",
            boundToState: state,
            producerIdentity: ProducerIdentity.identity(fromPath: modelPath!))
        let settlementID = try XCTUnwrap(store.esis?.latestSettlementID(forStateID: state.id))
        return (state.id, settlementID)
    }

    @MainActor
    private func store() -> ExecutionStateGraphStore { ExecutionStateGraphStore() }

    /// The engine identity the model-free stand-in resolves to. Both halves are
    /// non-empty content digests, so a settle -> admit round-trip on the same
    /// stand-in matches the producer rows the settlement recorded.
    private var engineIdentity: SettlementIdentityBinding.Identity {
        ProducerIdentity.identity(fromPath: modelPath!)
    }

    /// The recorded dictionary the bind site sees in production: the settled
    /// kv.* rows merged with the producer.* identity rows (HTTPServerResponses
    /// registers exactly this merge). The two namespaces are disjoint, so the
    /// KV evaluator ignores the producer rows and vice versa.
    private func recordedBindings(_ admitted: ISAdmission.Admitted) -> [String: String] {
        admitted.kvBindings.merging(admitted.producerBindings) { kv, _ in kv }
    }

    /// A specified identity for the fabricated-recorded gate tests (no settlement,
    /// no engine): both halves non-empty so the gate reaches the digest comparison.
    private let gateIdentity = SettlementIdentityBinding.Identity(
        model: "a2-gate-model", tokenizer: "a2-gate-tokenizer")

    /// Settle one continuation over the REAL adapter path with a KV
    /// representation, then admit it back through the real IS admission.
    @MainActor
    private func settleAndAdmit(
        tag: String, kvRepresentation: SettlementKVBinding.Representation?
    ) throws -> (outcome: ContinuationSettlementOutcome, admitted: ISAdmission.Admitted) {
        let anchor = try stageSettledAnchor(value: tag)
        let child = "es-child-\(UUID().uuidString.lowercased())"
        let outcome = try settleForNativeMLXContinuation(
            store: store(),
            request: ContinuationSettlementRequest(
                generatedText: "RESULT=\(tag)",
                parentESStateID: anchor.stateID,
                parentSettlementID: anchor.settlementID,
                childESStateID: child,
                verifiedBindings: ["next_input": .string(tag)]),
            modelPath: modelPath!,
            kvRepresentation: kvRepresentation)
        let admitted = try store().admitContinuation(
            stateID: outcome.childESStateID,
            consumer: ProducerIdentity.identity(fromPath: modelPath!))
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
        let expected = SettlementKVBinding.bindings(for: settledRepresentation)
        XCTAssertEqual(rows[SettlementKVBinding.poolKey], expected[SettlementKVBinding.poolKey],
                       "the settlement must name the exact pool boundary it exported")
        XCTAssertEqual(
            rows[SettlementKVBinding.cacheFingerprint],
            expected[SettlementKVBinding.cacheFingerprint])
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
                       [SettlementKVBinding.poolKey, SettlementKVBinding.cacheFingerprint])
        // T9 read half: admission also carries the producer identity rows the
        // physical KV bind site gates on (model + tokenizer content digests).
        XCTAssertEqual(
            admitted.producerBindings,
            SettlementIdentityBinding.bindings(for: engineIdentity),
            "admission must carry the producer identity rows for the physical KV gate")
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
        let recorded = recordedBindings(admitted)

        // The boundary the settlement actually exported: authorized.
        XCTAssertEqual(
            NativeMLXPrefixPool.bindVerdict(
                .verdict(.authorized(recorded)), namespace: ns,
                tokenCount: settledRepresentation.tokenCount,
                boundaryHash: settledRepresentation.boundaryHash,
                engineIdentity: engineIdentity),
            .allowed)

        // Same artifact, one more token covered: the content claim differs.
        let longer = NativeMLXPrefixPool.bindVerdict(
            .verdict(.authorized(recorded)), namespace: ns,
            tokenCount: settledRepresentation.tokenCount + 1,
            boundaryHash: settledRepresentation.boundaryHash,
            engineIdentity: engineIdentity)
        XCTAssertEqual(longer, .rejected(reason: SettlementKVBinding.Refusal.poolKeyMismatch.rawValue))
        XCTAssertFalse(longer.permitsBind, "a longer reuse than settled must not bind")

        // Tampered content claim at the right length.
        XCTAssertEqual(
            NativeMLXPrefixPool.bindVerdict(
                .verdict(.authorized(recorded)), namespace: ns,
                tokenCount: settledRepresentation.tokenCount,
                boundaryHash: settledRepresentation.boundaryHash &+ 1,
                engineIdentity: engineIdentity),
            .rejected(reason: SettlementKVBinding.Refusal.poolKeyMismatch.rawValue))

        // Different KV namespace (different kvSettings / thinking flag) — the same
        // boundary hash is a different representation.
        let otherNamespace = namespace(kvFingerprint: "fp-other")
        let otherFingerprint = NativeMLXPrefixPool.bindVerdict(
            .verdict(.authorized(recorded)), namespace: otherNamespace,
            tokenCount: settledRepresentation.tokenCount,
            boundaryHash: settledRepresentation.boundaryHash,
            engineIdentity: engineIdentity)
        XCTAssertEqual(
            otherFingerprint,
            .rejected(reason: SettlementKVBinding.Refusal.fingerprintMismatch.rawValue))

        // Missing rows fail closed (a settlement from before this wiring).
        XCTAssertEqual(
            NativeMLXPrefixPool.bindVerdict(.verdict(.authorized([:])), namespace: ns,
                                            tokenCount: 12, boundaryHash: 1,
                                            engineIdentity: engineIdentity),
            .rejected(reason: SettlementKVBinding.Refusal.fingerprintAbsent.rawValue))
        var halfOnly = recorded
        halfOnly[SettlementKVBinding.poolKey] = nil
        XCTAssertEqual(
            NativeMLXPrefixPool.bindVerdict(.verdict(.authorized(halfOnly)), namespace: ns,
                                            tokenCount: settledRepresentation.tokenCount,
                                            boundaryHash: settledRepresentation.boundaryHash,
                                            engineIdentity: engineIdentity),
            .rejected(reason: SettlementKVBinding.Refusal.poolKeyAbsent.rawValue))
    }

    // MARK: - Physical identity gate: model + tokenizer must match exactly

    /// Post-#169: identity is provenance for semantic reuse, but a PHYSICAL KV
    /// restore is gated on an exact model + tokenizer match against the producer
    /// rows the settlement recorded. The KV boundary is checked first; only a
    /// matching boundary reaches the identity gate, and a different model or
    /// tokenizer falls back to cold prefill (fail-closed). An unnamed engine is
    /// never a wildcard, and a settlement with no producer rows grants no restore.
    @MainActor
    func testPhysicalKVBindRequiresExactProducerIdentity() async throws {
        let ns = namespace()
        let settledRepresentation = representation(in: ns, boundaryHash: 0xfeed_face)
        let (_, admitted) = try settleAndAdmit(
            tag: "A2-KV-IDENTITY-7104", kvRepresentation: settledRepresentation)
        let recorded = recordedBindings(admitted)
        let producer = engineIdentity
        XCTAssertTrue(producer.isSpecified, "the stand-in must resolve a specified identity")

        func verdict(_ identity: SettlementIdentityBinding.Identity) -> NativeMLXPrefixPool.BindAuthority {
            NativeMLXPrefixPool.bindVerdict(
                .verdict(.authorized(recorded)), namespace: ns,
                tokenCount: settledRepresentation.tokenCount,
                boundaryHash: settledRepresentation.boundaryHash,
                engineIdentity: identity)
        }

        // Same model + tokenizer: the physical representation is restorable.
        XCTAssertEqual(verdict(producer), .allowed)

        // A different model cannot restore this KV artifact even at the right boundary.
        XCTAssertEqual(
            verdict(SettlementIdentityBinding.Identity(
                model: producer.model + "-other", tokenizer: producer.tokenizer)),
            .rejected(reason: SettlementIdentityBinding.Refusal.modelMismatch.rawValue))

        // A different tokenizer is a different physical layout: refused.
        XCTAssertEqual(
            verdict(SettlementIdentityBinding.Identity(
                model: producer.model, tokenizer: producer.tokenizer + "-other")),
            .rejected(reason: SettlementIdentityBinding.Refusal.tokenizerMismatch.rawValue))

        // An unnamed engine is not a wildcard: fail closed.
        XCTAssertEqual(
            verdict(.absent),
            .rejected(reason: SettlementIdentityBinding.Refusal.consumerAbsent.rawValue))

        // KV rows without producer identity rows (a pre-T9 settlement) grant no
        // physical restore: the identity gate fails closed on the absent model row.
        XCTAssertEqual(
            NativeMLXPrefixPool.bindVerdict(
                .verdict(.authorized(admitted.kvBindings)), namespace: ns,
                tokenCount: settledRepresentation.tokenCount,
                boundaryHash: settledRepresentation.boundaryHash,
                engineIdentity: producer),
            .rejected(reason: SettlementIdentityBinding.Refusal.modelAbsent.rawValue))
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
            namespace: namespace(), tokenCount: 12, boundaryHash: 1,
            engineIdentity: engineIdentity)
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
        let recorded = SettlementKVBinding.bindings(for: settledRepresentation)
            .merging(SettlementIdentityBinding.bindings(for: gateIdentity)) { kv, _ in kv }

        // Unmanaged = the pool edge as it was before A-2.
        let ungoverned = NativeMLXPrefixPool.bindVerdict(
            ISKVBindAuthority.shared.consume(esStateID: "es-never-registered-\(UUID().uuidString)"),
            namespace: ns, tokenCount: settledRepresentation.tokenCount,
            boundaryHash: settledRepresentation.boundaryHash,
            engineIdentity: gateIdentity)
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
                boundaryHash: settledRepresentation.boundaryHash,
                engineIdentity: gateIdentity),
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

    /// Lifetime is the request, not a table size: nothing is evicted while a
    /// request is in flight, and `release` is what empties the table when the
    /// request ends. This is the property the old bounded-tombstone design could
    /// not hold — its ring could be walked past by unrelated registrations.
    @MainActor
    func testGrantsLiveUntilTheirRequestReleases() {
        ISKVBindAuthority.shared.reset()
        let ids = (0..<80).map { _ in "es-" + UUID().uuidString.lowercased() }
        for id in ids {
            ISKVBindAuthority.shared.register(esStateID: id, verdict: .unauthorized(reason: "x"))
        }
        XCTAssertEqual(ISKVBindAuthority.shared.count, ids.count,
                       "no registration may evict another in-flight grant")
        XCTAssertEqual(ISKVBindAuthority.shared.peek(esStateID: ids.first!).isGoverned, true)
        XCTAssertEqual(ISKVBindAuthority.shared.peek(esStateID: ids.last!).isGoverned, true)

        for id in ids {
            ISKVBindAuthority.shared.release(esStateID: id)
        }
        XCTAssertEqual(ISKVBindAuthority.shared.count, 0,
                       "every grant leaves the table when its request ends")
        XCTAssertEqual(ISKVBindAuthority.shared.peek(esStateID: ids.first!), .notGoverned)

        // Releasing an id that was never registered, or releasing twice, is a
        // no-op — completions and failures both funnel through it.
        ISKVBindAuthority.shared.release(esStateID: "es-never-\(UUID().uuidString)")
        XCTAssertEqual(ISKVBindAuthority.shared.count, 0)
        ISKVBindAuthority.shared.reset()
    }

    /// A grant survives arbitrary unrelated churn and still gates its own bind;
    /// the never-registered everyday turn keeps the pre-A-2 behaviour; and a
    /// released grant is not governed any more. Together these are the whole
    /// contract: governed-and-paid, governed-and-refused, ungoverned, finished.
    @MainActor
    func testGrantSurvivesChurnThenEndsWithItsRequest() {
        ISKVBindAuthority.shared.reset()
        let ns = namespace()
        let settledRepresentation = representation(in: ns)
        let recorded = SettlementKVBinding.bindings(for: settledRepresentation)
            .merging(SettlementIdentityBinding.bindings(for: gateIdentity)) { kv, _ in kv }

        let inFlight = "es-" + UUID().uuidString.lowercased()
        ISKVBindAuthority.shared.register(esStateID: inFlight, verdict: .authorized(recorded))
        // Churn well past the old 64-entry window before the in-flight request
        // reaches its bind site.
        let churn = (0..<200).map { _ in "es-" + UUID().uuidString.lowercased() }
        for id in churn {
            ISKVBindAuthority.shared.register(esStateID: id, verdict: .unauthorized(reason: "churn"))
        }
        let decision = NativeMLXPrefixPool.bindVerdict(
            ISKVBindAuthority.shared.consume(esStateID: inFlight),
            namespace: ns, tokenCount: settledRepresentation.tokenCount,
            boundaryHash: settledRepresentation.boundaryHash,
            engineIdentity: gateIdentity)
        XCTAssertEqual(decision, .allowed,
                       "unrelated traffic must not downgrade an in-flight governed grant")
        for id in churn { ISKVBindAuthority.shared.release(esStateID: id) }

        // The everyday path is unchanged: never registered = not governed.
        let everyday = NativeMLXPrefixPool.bindVerdict(
            ISKVBindAuthority.shared.consume(esStateID: "es-never-\(UUID().uuidString)"),
            namespace: ns, tokenCount: settledRepresentation.tokenCount,
            boundaryHash: settledRepresentation.boundaryHash,
            engineIdentity: gateIdentity)
        XCTAssertEqual(everyday, .notGoverned)
        XCTAssertTrue(everyday.permitsBind)

        // A request that ends without ever binding leaves nothing behind, and
        // its id is an ordinary turn afterwards — the request is over.
        let unbound = "es-" + UUID().uuidString.lowercased()
        ISKVBindAuthority.shared.register(esStateID: unbound, verdict: .authorized(recorded))
        ISKVBindAuthority.shared.release(esStateID: unbound)
        XCTAssertEqual(ISKVBindAuthority.shared.peek(esStateID: unbound), .notGoverned)
        XCTAssertEqual(ISKVBindAuthority.shared.count, 0)
        ISKVBindAuthority.shared.reset()
    }
}
