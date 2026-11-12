import Foundation
import XCTest
import SQLite3
import SimiGoRuntimeContract
@testable import SimiGo

/// Directed, model-free proof for the PRODUCTION continuation settlement
/// adapter (the closure wired into the NativeMLX HTTPServer construction
/// site). It is deliberately not another HTTP-stub test: every assertion here
/// drives the real store adapter over an isolated temporary authoritative
/// SQLite store, so what is proven is the code a real request will run —
///
/// * the settlement is written by the existing native gate + IS authority
///   (`settleProducerResult(...producerIdentity:)`), with a settlement id read
///   back from the authoritative store rather than invented;
/// * the producer identity binding is genuinely published (read back from
///   `settlement_bindings`) and makes the settlement admissible by a LATER
///   continuation — the settlement -> admission seam is exercised;
/// * the identity is the one re-derived from the runtime's OWN model snapshot:
///   no caller can supply or borrow another execution's identity, because a
///   different identity is refused at admission;
/// * failure boundaries stay distinct: a native result-contract refusal is
///   `NATIVE_RESULT_CONTRACT_REJECTED` and leaves NO half-settled record, an
///   unknown anchor / missing authority is `SETTLEMENT_ENGINE_ERROR`, never 422.
///
/// NO REAL MODEL IS STARTED: the "generation stand-in" is a text value handed
/// to the same entry the production adapter receives from the dispatch, and the
/// producer identity is re-derived from an existing snapshot DIRECTORY with no
/// weight load at all. The real-model closed loop stays NOT RUN and requires a
/// separately authorized model round.
///
/// Isolation: this class only runs against the three redirected roots the
/// isolated xctestrun injects (`SIMIGO_HOME`, `SIMIGO_STATE_GRAPH_STORE`);
/// without them it throws XCTSkip instead of writing the operator's real
/// reference graph / authoritative database.
private enum ConcurrentCommitResult: Sendable {
    case success(String)
    case failure(String)
}

private final class ConcurrentCommitResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int: ConcurrentCommitResult] = [:]

    func set(_ value: ConcurrentCommitResult, for index: Int) {
        lock.lock()
        defer { lock.unlock() }
        values[index] = value
    }

    func snapshot() -> [Int: ConcurrentCommitResult] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

final class NativeMLXContinuationSettlementAdapterTests: XCTestCase {

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
        // Guard the claim itself: the authority this test opens must be inside
        // the isolation root, not the real ~/.simigo.
        XCTAssertTrue(
            ManagedPaths.databaseURL.path.hasPrefix(isolationRoot.path),
            "authoritative store resolves outside the isolation root: \(ManagedPaths.databaseURL.path)")
        XCTAssertTrue(
            ExecutionStateGraphStore.defaultStoreURL().path.hasPrefix(
                (graphStore as NSString).standardizingPath),
            "reference graph resolves outside the isolated state-graph root")

        // An existing snapshot DIRECTORY (never a weight load): the identity
        // re-derivation is pure disk re-derivation, so a minimal deterministic
        // directory is a legitimate model-free stand-in for the runtime's own
        // model path.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimiGoAdapterModelFree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"model_type":"adapter-model-free-stand-in"}"#.utf8).write(
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

    /// Stage a live, SETTLED ES state in the product's authoritative store.
    /// A continuation settles against the parent settlement its admission
    /// verified, so the anchor must carry a valid settlement of its own.
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
    private func receipts(for store: ExecutionStateGraphStore, stateID: String) -> [SettlementReceipt] {
        (store.document.settlements ?? []).filter { $0.stateID == stateID }
    }

    @MainActor
    private func authoritativeReceiptCount(stateID: String) throws -> Int {
        let db = try XCTUnwrap(store().esis)
        return try db.readSettlementReceipts().filter { $0.stateID == stateID }.count
    }

    @MainActor
    private func authoritativeReceiptCountTotal() throws -> Int {
        let db = try XCTUnwrap(store().esis)
        return try db.readSettlementReceipts().count
    }

    @MainActor
    private func authoritativeBindingCountTotal() throws -> Int {
        let db = try XCTUnwrap(store().esis)
        return try db.count("settlement_bindings")
    }

    /// Execute narrowly scoped SQL against the isolated test database, used only
    /// to inject a failure exactly when a producer identity binding is inserted.
    private func executeIsolatedSQLite(_ sql: String) throws {
        var handle: OpaquePointer?
        let openRC = sqlite3_open(ManagedPaths.databaseURL.path, &handle)
        guard openRC == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw NSError(
                domain: "NativeMLXContinuationSettlementAdapterTests.SQLite",
                code: Int(openRC),
                userInfo: [NSLocalizedDescriptionKey: "could not open isolated test database"])
        }
        defer { sqlite3_close(handle) }

        var message: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &message)
        if rc != SQLITE_OK {
            let detail = message.map { String(cString: $0) } ?? "SQLite error \(rc)"
            if let message { sqlite3_free(message) }
            throw NSError(
                domain: "NativeMLXContinuationSettlementAdapterTests.SQLite",
                code: Int(rc),
                userInfo: [NSLocalizedDescriptionKey: detail])
        }
        if let message { sqlite3_free(message) }
    }

    @MainActor
    private func store() -> ExecutionStateGraphStore { ExecutionStateGraphStore() }

    /// Read back the v36 result-contract identity columns for one settlement.
    /// Test-only: the production read path (`readSettlementReceipts`) does not
    /// surface these columns, so the directed proof reads them straight from the
    /// isolated authoritative store to verify they were recorded at settle time.
    private func readResultContractIdentity(
        settlementID: String
    ) throws -> (id: String?, digest: String?) {
        var handle: OpaquePointer?
        let openRC = sqlite3_open(ManagedPaths.databaseURL.path, &handle)
        guard openRC == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw NSError(
                domain: "NativeMLXContinuationSettlementAdapterTests.SQLite",
                code: Int(openRC),
                userInfo: [NSLocalizedDescriptionKey: "could not open isolated test database"])
        }
        defer { sqlite3_close(handle) }
        var stmt: OpaquePointer?
        let sql = """
        SELECT result_contract_id, result_contract_digest
        FROM settlements WHERE settlement_id = ? LIMIT 1;
        """
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw NSError(
                domain: "NativeMLXContinuationSettlementAdapterTests.SQLite",
                code: Int(sqlite3_errcode(handle)),
                userInfo: [NSLocalizedDescriptionKey: "prepare failed for result-contract read"])
        }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, settlementID, -1, transient)
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw NSError(
                domain: "NativeMLXContinuationSettlementAdapterTests.SQLite",
                code: Int(sqlite3_errcode(handle)),
                userInfo: [NSLocalizedDescriptionKey: "no settlement row for \(settlementID)"])
        }
        func col(_ i: Int32) -> String? {
            sqlite3_column_text(stmt, i).map { String(cString: $0) }
        }
        return (col(0), col(1))
    }

    // MARK: - Tests

    /// Positive: the production adapter settles the ACTUAL generated text over
    /// the real native gate, the id it reports is the authoritative one, the
    /// identity binding is readable, and a later continuation admits the
    /// settlement through the same store.
    @MainActor
    func testProductionAdapterSettlesAndStaysAdmissible() async throws {
        let value = "ADAPTER-SETTLE-6311"
        let anchor = try stageSettledAnchor(value: value)

        let handler = makeNativeMLXContinuationSettlementHandler(modelPath: modelPath!)
        // Model-free generation stand-in: the text a real generation would have
        // produced, handed to the same entry the dispatch uses, together with the
        // bindings the pre-generation admission verified and the child ES.
        let child = "es-child-\(UUID().uuidString.lowercased())"
        let outcome = try await handler(ContinuationSettlementRequest(
            generatedText: "RESULT=\(value)",
            parentESStateID: anchor.stateID,
            parentSettlementID: anchor.settlementID,
            childESStateID: child,
            verifiedBindings: ["next_input": .string(value)]))

        XCTAssertFalse(outcome.settlementID.isEmpty)
        XCTAssertTrue(outcome.identityBindingPublished)
        XCTAssertEqual(outcome.childESStateID, child)

        // The reported id is the authoritative store's own settlement id, and the
        // settlement belongs to the CHILD execution state, not the anchor.
        let fresh = store()
        let recorded = try XCTUnwrap(
            fresh.esis?.latestSettlementID(forStateID: outcome.childESStateID))
        XCTAssertEqual(recorded, outcome.settlementID,
                       "the adapter must report the id the authoritative store issued")
        XCTAssertEqual(receipts(for: fresh, stateID: child).count, 1)
        XCTAssertEqual(try authoritativeReceiptCount(stateID: child), 1)
        XCTAssertNotEqual(child, anchor.stateID)
        XCTAssertEqual(fresh.state(child)?.parentID, anchor.stateID,
                       "the settled state must be a child of the continuation anchor")
        XCTAssertEqual(fresh.state(child)?.nextInput, value,
                       "the child ES projection must carry the settled value")
        let childRow = try XCTUnwrap(
            fresh.esis?.readGraph().states.first { $0.id == child })
        XCTAssertEqual(childRow.nextInput, value,
                       "the child ES row must persist the settled value as next_input")
        XCTAssertTrue(
            try XCTUnwrap(fresh.esis).upstreamDependencyClosure(
                ofSettlement: outcome.settlementID).contains(anchor.settlementID),
            "the child settlement must depend on the admission-verified parent settlement")

        // Identity binding really landed in settlement_bindings (read back).
        // The store persists `digest(identity.model|tokenizer)`, the same form
        // `ISAdmission` compares a consumer against, so the read-back must
        // match the digest of the identity re-derived from THIS snapshot.
        let own = ProducerIdentity.identity(fromPath: modelPath!)
        let bindings = try XCTUnwrap(fresh.esis).settlementBindings(settlementID: outcome.settlementID)
        XCTAssertEqual(
            bindings[SettlementIdentityBinding.modelKey],
            SettlementIdentityBinding.digest(own.model),
            "the published binding must be the identity re-derived from THIS runtime's snapshot")
        XCTAssertEqual(
            bindings[SettlementIdentityBinding.tokenizerKey],
            SettlementIdentityBinding.digest(own.tokenizer))

        // Admission seam: the settlement this adapter published is admissible by
        // the continuation path that follows, THROUGH THE CHILD id it returned.
        let admitted = try fresh.admitContinuation(
            stateID: outcome.childESStateID, consumer: own)
        XCTAssertEqual(admitted.recoveredValue, value)
    }

    /// A violating generated output is refused by the existing native contract
    /// INSIDE the adapter: the terminal is the contract class and nothing is
    /// written — neither the graph receipt nor the authoritative row.
    @MainActor
    func testContractRefusalLeavesNoHalfSettledRecord() async throws {
        let anchor = try stageSettledAnchor(value: "ADAPTER-REFUSE-6312")

        let handler = makeNativeMLXContinuationSettlementHandler(modelPath: modelPath!)
        let child = "es-child-\(UUID().uuidString.lowercased())"
        let error = await catchAsyncError {
            _ = try await handler(ContinuationSettlementRequest(
                generatedText: "NOISE-OFF-CONTRACT",
                parentESStateID: anchor.stateID,
                parentSettlementID: anchor.settlementID,
                childESStateID: child,
                verifiedBindings: ["next_input": .string("ADAPTER-REFUSE-6312")]))
        }
        let unwrapped = try XCTUnwrap(error, "a violating output must be refused")
        let terminal = continuationSettlementTerminal(for: unwrapped)
        XCTAssertEqual(terminal.status, 422)
        XCTAssertEqual(terminal.errorKind, "NATIVE_RESULT_CONTRACT_REJECTED")

        let fresh = store()
        XCTAssertTrue(receipts(for: fresh, stateID: child).isEmpty,
                      "a refused settlement must leave no partial record")
        XCTAssertEqual(try authoritativeReceiptCount(stateID: child), 0)
        XCTAssertNil(try fresh.esis?.latestSettlementID(forStateID: child))
        XCTAssertNil(fresh.state(child),
                     "a refused settlement must not leave a child execution state")
    }

    /// #6 confirmed result-contract (IS codex-2026-11-11-ben#t8): continuation is
    /// restatement-after-recovery, NOT derivation. Pin both arms at the product
    /// adapter so the confirmed boundary is enforceable and auditable:
    ///  * restating the admission-verified value settles, and the authoritative
    ///    settlement row records the contract identity (`schema_version`);
    ///  * a well-formed `RESULT=` that DERIVES a different value is refused by the
    ///    `equals_binding` constraint (not the pattern) with ZERO writes.
    /// This locks the confirmed boundary; it does not open derivation.
    @MainActor
    func testContinuationContractIsConfirmedRestatementNotDerivation() async throws {
        let value = "ADAPTER-RESTATE-6316"
        let derived = "ADAPTER-DERIVE-6316-NEW"
        let anchor = try stageSettledAnchor(value: value)
        let handler = makeNativeMLXContinuationSettlementHandler(modelPath: modelPath!)
        let own = ProducerIdentity.identity(fromPath: modelPath!)

        // Restatement arm: RESULT=<verified value> settles under the confirmed
        // contract, and the row carries the contract identity for later audit.
        let restatedChild = "es-child-\(UUID().uuidString.lowercased())"
        let outcome = try await handler(ContinuationSettlementRequest(
            generatedText: "RESULT=\(value)",
            parentESStateID: anchor.stateID,
            parentSettlementID: anchor.settlementID,
            childESStateID: restatedChild,
            verifiedBindings: ["next_input": .string(value)]))
        let fresh = store()
        let row = try XCTUnwrap(
            fresh.esis?.readSettlementReceipts().first { $0.id.uuidString == outcome.settlementID })
        XCTAssertEqual(row.schemaVersion, "simigo.result-contract/v1",
                       "the settled row must record which result-contract it was settled under")
        XCTAssertEqual(fresh.state(restatedChild)?.nextInput, value)
        XCTAssertEqual(
            try fresh.admitContinuation(stateID: restatedChild, consumer: own).recoveredValue,
            value, "a restated child stays admissible — the restatement chain continues")

        // Derivation arm: a well-formed RESULT= carrying a NEW value passes the
        // pattern but violates equals_binding(next_input). It must be refused as
        // a contract rejection (not an engine fault) and write nothing.
        let before = try authoritativeReceiptCountTotal()
        let derivedChild = "es-child-\(UUID().uuidString.lowercased())"
        let error = await catchAsyncError {
            _ = try await handler(ContinuationSettlementRequest(
                generatedText: "RESULT=\(derived)",
                parentESStateID: anchor.stateID,
                parentSettlementID: anchor.settlementID,
                childESStateID: derivedChild,
                verifiedBindings: ["next_input": .string(value)]))
        }
        let unwrapped = try XCTUnwrap(error, "a derived (non-restated) value must be refused")
        let terminal = continuationSettlementTerminal(for: unwrapped)
        XCTAssertEqual(terminal.status, 422)
        XCTAssertEqual(terminal.errorKind, "NATIVE_RESULT_CONTRACT_REJECTED")
        // It is the equals_binding constraint that refuses, not the RESULT=
        // pattern: the output was well-formed, it simply derived a new value.
        let contractError = try XCTUnwrap(unwrapped as? NativeResultContractError)
        XCTAssertEqual(contractError.code, "PRODUCER_RESULT_BINDING_MISMATCH")

        let after = store()
        XCTAssertNil(try after.esis?.latestSettlementID(forStateID: derivedChild))
        XCTAssertNil(after.state(derivedChild),
                     "a refused derivation must not leave a child execution state")
        XCTAssertTrue(receipts(for: after, stateID: derivedChild).isEmpty)
        XCTAssertEqual(try authoritativeReceiptCountTotal(), before,
                       "a refused derivation must add no settlement row")
    }

    /// T7 (#6 opened): derivation is authorized by a TASK-LEVEL contract, never by
    /// silently swapping the default. Supplying a versioned deriving contract (its
    /// own `contract_id`, no `equals_binding` pin) to `settleContinuationResult`
    /// settles a NEW value computed from the verified input; the settlement row
    /// records that contract's id / schema version / digest, and the child still
    /// depends on the admission-verified parent through the continuation-parent
    /// edge. The default restatement contract is unchanged (the prior test pins it).
    @MainActor
    func testTaskLevelContractOpensDerivationAndRecordsContractIdentity() async throws {
        let value = "ADAPTER-DERIVE-OPEN-6317"
        let derived = "ADAPTER-DERIVE-OPEN-6317-NEW"
        let anchor = try stageSettledAnchor(value: value)
        let own = ProducerIdentity.identity(fromPath: modelPath!)

        // A versioned deriving contract: same RESULT= field shape, its own
        // contract_id, and NO equals_binding pin — so a new value is admissible.
        let derivingContractJSON = Data(#"{"schema_version":"simigo.result-contract/v1","contract_id":"simigo.continuation.derivation.test","fields":{"content":{"pattern":"^RESULT=(.+)$","capture_group":1,"type":"string","normalize":"trim","nonempty":true}},"constraints":[]}"#.utf8)

        let child = "es-child-\(UUID().uuidString.lowercased())"
        let commit = try store().settleContinuationResult(
            generatedText: "RESULT=\(derived)",
            parentStateID: anchor.stateID,
            parentSettlementID: anchor.settlementID,
            childStateID: child,
            verifiedBindings: ["next_input": .string(value)],
            contractJSON: derivingContractJSON,
            producerIdentity: own)

        let fresh = store()
        // A NEW value settled — not a restatement of the verified input.
        XCTAssertEqual(commit.childStateID, child)
        XCTAssertNotEqual(derived, value)
        XCTAssertEqual(fresh.state(child)?.nextInput, derived)
        let childRow = try XCTUnwrap(fresh.esis?.readGraph().states.first { $0.id == child })
        XCTAssertEqual(childRow.nextInput, derived)

        // The row records WHICH versioned contract authorized the derivation.
        let row = try XCTUnwrap(
            fresh.esis?.readSettlementReceipts().first { $0.id.uuidString == commit.settlementID })
        XCTAssertEqual(row.schemaVersion, "simigo.result-contract/v1")
        let identity = try readResultContractIdentity(settlementID: commit.settlementID)
        XCTAssertEqual(identity.id, "simigo.continuation.derivation.test",
                       "the settlement must name the task-level contract that authorized it")
        XCTAssertEqual(identity.digest, SettlementAuthority.payloadDigest(derivingContractJSON),
                       "the settlement must pin the exact contract bytes (version digest)")
        // The default restatement contract is a DIFFERENT version: same input,
        // different task contract => different recorded digest (no key collision).
        XCTAssertNotEqual(
            identity.digest,
            SettlementAuthority.payloadDigest(ExecutionStateGraphStore.referenceResultContractJSON))

        // Derivation still explicitly depends on the admission-verified parent.
        XCTAssertTrue(
            try XCTUnwrap(fresh.esis).upstreamDependencyClosure(
                ofSettlement: commit.settlementID).contains(anchor.settlementID),
            "a derived child must depend on the verified parent settlement")

        // The derived child stays admissible — the chain continues under provenance.
        XCTAssertEqual(
            try fresh.admitContinuation(stateID: child, consumer: own).recoveredValue,
            derived)
    }

    /// §III of the third review, opened: the TASK contract travels through the
    /// production adapter, not just through a store call a test made up.
    ///
    /// `ContinuationSettlementRequest.contractJSON` is the only channel a
    /// transport has; this drives it through `settleForNativeMLXContinuation`
    /// (the exact body the HTTPServer closure calls) and reads the recorded
    /// v36 columns back from SQLite. A nil contract must still settle under the
    /// restatement default, byte-identically to before the field existed.
    @MainActor
    func testTaskContractReachesTheStoreThroughTheProductionAdapter() async throws {
        let value = "ADAPTER-PLUMB-6411"
        let derived = "ADAPTER-PLUMB-6411-DERIVED"
        let anchor = try stageSettledAnchor(value: value)
        let derivingContractJSON = Data(#"{"schema_version":"simigo.result-contract/v1","contract_id":"simigo.continuation.derivation.plumbing-test","fields":{"content":{"pattern":"^RESULT=(.+)$","capture_group":1,"type":"string","normalize":"trim","nonempty":true}},"constraints":[]}"#.utf8)

        let child = "es-child-\(UUID().uuidString.lowercased())"
        let outcome = try settleForNativeMLXContinuation(
            store: store(),
            request: ContinuationSettlementRequest(
                generatedText: "RESULT=\(derived)",
                parentESStateID: anchor.stateID,
                parentSettlementID: anchor.settlementID,
                childESStateID: child,
                verifiedBindings: ["next_input": .string(value)],
                contractJSON: derivingContractJSON),
            modelPath: modelPath!)

        XCTAssertEqual(outcome.childESStateID, child)
        let fresh = store()
        XCTAssertEqual(fresh.state(child)?.nextInput, derived,
                       "the adapter must settle the derived value it was contracted for")
        let identity = try readResultContractIdentity(settlementID: outcome.settlementID)
        XCTAssertEqual(identity.id, "simigo.continuation.derivation.plumbing-test",
                       "the settlement must name the contract the request supplied")
        XCTAssertEqual(identity.digest, SettlementAuthority.payloadDigest(derivingContractJSON))

        // No contract supplied -> restatement default, same as before §III.
        let restatedChild = "es-child-\(UUID().uuidString.lowercased())"
        let restated = try settleForNativeMLXContinuation(
            store: store(),
            request: ContinuationSettlementRequest(
                generatedText: "RESULT=\(value)",
                parentESStateID: anchor.stateID,
                parentSettlementID: anchor.settlementID,
                childESStateID: restatedChild,
                verifiedBindings: ["next_input": .string(value)]),
            modelPath: modelPath!)
        let restatedIdentity = try readResultContractIdentity(
            settlementID: restated.settlementID)
        XCTAssertEqual(restatedIdentity.id, "simigo.continuation.restatement",
                       "nil contractJSON must keep the restatement default, never a derivation")
        XCTAssertEqual(
            restatedIdentity.digest,
            SettlementAuthority.payloadDigest(
                ExecutionStateGraphStore.referenceResultContractJSON))
    }

    /// An anchor that names no state in the authoritative graph is an engine
    /// fault (500), never a business 422, and writes nothing. Receipt counts are
    /// asserted delta-wise because the isolated store is shared across the
    /// class' tests (each stages its own new state).
    @MainActor
    func testUnknownAnchorIsEngineFaultNotBusinessRefusal() async throws {
        let ghostAnchor = "es-state-no-such-anchor-\(UUID().uuidString)"
        let before = try authoritativeReceiptCountTotal()

        let handler = makeNativeMLXContinuationSettlementHandler(modelPath: modelPath!)
        let error = await catchAsyncError {
            _ = try await handler(ContinuationSettlementRequest(
                generatedText: "RESULT=anything",
                parentESStateID: ghostAnchor,
                parentSettlementID: "settlement-ghost",
                childESStateID: "es-child-\(UUID().uuidString.lowercased())",
                verifiedBindings: ["next_input": .string("anything")]))
        }
        let terminal = continuationSettlementTerminal(for: try XCTUnwrap(error))
        XCTAssertEqual(terminal.status, 500)
        XCTAssertEqual(terminal.errorKind, "SETTLEMENT_ENGINE_ERROR")
        XCTAssertNotEqual(terminal.errorKind, "NATIVE_RESULT_CONTRACT_REJECTED")

        // Nothing written for the phantom anchor, and the store is unchanged.
        let fresh = store()
        XCTAssertNil(try fresh.esis?.latestSettlementID(forStateID: ghostAnchor))
        XCTAssertEqual(try authoritativeReceiptCountTotal(), before,
                       "an engine fault must not add any settlement row")
    }

    /// The identity is not a caller-supplied label: it comes from the runtime's
    /// own snapshot, so a settlement published by this adapter is refused to a
    /// DIFFERENT identity while remaining admissible to the adapter's own.
    @MainActor
    func testIdentityIsNotBorrowableAcrossExecutions() async throws {
        let anchor = try stageSettledAnchor(value: "ADAPTER-IDENTITY-6313")
        let handler = makeNativeMLXContinuationSettlementHandler(modelPath: modelPath!)
        let outcome = try await handler(ContinuationSettlementRequest(
            generatedText: "RESULT=ADAPTER-IDENTITY-6313",
            parentESStateID: anchor.stateID,
            parentSettlementID: anchor.settlementID,
            childESStateID: "es-child-\(UUID().uuidString.lowercased())",
            verifiedBindings: ["next_input": .string("ADAPTER-IDENTITY-6313")]))
        XCTAssertTrue(outcome.identityBindingPublished)

        let fresh = store()
        let own = ProducerIdentity.identity(fromPath: modelPath!)
        let admitted = try fresh.admitContinuation(
            stateID: outcome.childESStateID, consumer: own)
        XCTAssertEqual(admitted.recoveredValue, "ADAPTER-IDENTITY-6313")

        let borrowed = SettlementIdentityBinding.Identity(
            model: "borrowed-model-digest", tokenizer: "borrowed-tokenizer-digest")
        XCTAssertThrowsError(
            try fresh.admitContinuation(stateID: outcome.childESStateID, consumer: borrowed),
            "a borrowed identity must not admit this settlement"
        )
    }

    /// Inject a failure after the settlement and native constraint rows have
    /// been attempted but while the producer identity rows are being inserted.
    /// SQLite must roll EVERYTHING back; the graph projection changes only after
    /// the authoritative transaction has returned successfully.
    @MainActor
    func testIdentityBindingWriteFailureRollsBackWholeSettlement() async throws {
        let anchor = try stageSettledAnchor(value: "ADAPTER-ATOMIC-6314")
        let settlementsBefore = try authoritativeReceiptCountTotal()
        let bindingsBefore = try authoritativeBindingCountTotal()
        let trigger = "fail_identity_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        try executeIsolatedSQLite("""
        CREATE TRIGGER \(trigger)
        BEFORE INSERT ON settlement_bindings
        WHEN NEW.name = 'producer.model_identity'
        BEGIN
            SELECT RAISE(ABORT, 'injected producer identity write failure');
        END;
        """)
        defer { try? executeIsolatedSQLite("DROP TRIGGER IF EXISTS \(trigger)") }

        let handler = makeNativeMLXContinuationSettlementHandler(modelPath: modelPath!)
        let child = "es-child-\(UUID().uuidString.lowercased())"
        let error = await catchAsyncError {
            _ = try await handler(ContinuationSettlementRequest(
                generatedText: "RESULT=ADAPTER-ATOMIC-6314",
                parentESStateID: anchor.stateID,
                parentSettlementID: anchor.settlementID,
                childESStateID: child,
                verifiedBindings: ["next_input": .string("ADAPTER-ATOMIC-6314")]))
        }
        let terminal = continuationSettlementTerminal(for: try XCTUnwrap(
            error, "injected identity binding failure must fail the request"))
        XCTAssertEqual(terminal.status, 500)
        XCTAssertEqual(terminal.errorKind, "SETTLEMENT_ENGINE_ERROR")

        let fresh = store()
        XCTAssertNil(try fresh.esis?.latestSettlementID(forStateID: child))
        XCTAssertTrue(receipts(for: fresh, stateID: child).isEmpty,
                      "the graph projection must not gain a receipt before commit")
        XCTAssertNil(fresh.state(child),
                     "the child ES insert must roll back with its settlement")
        XCTAssertEqual(try authoritativeReceiptCountTotal(), settlementsBefore,
                       "settlement insert must roll back when identity insert fails")
        XCTAssertEqual(try authoritativeBindingCountTotal(), bindingsBefore,
                       "native constraint and identity bindings must all roll back")
    }

    /// Two independent SQLite connections settle the SAME ES anchor concurrently
    /// with the same fixed settledAt. Each call must return the UUID it inserted,
    /// and identity rows under that UUID must belong to that caller—not to
    /// whichever latest-settlement query might otherwise win after commit.
    @MainActor
    func testConcurrentSameAnchorSettlementsReturnTheirOwnIDs() async throws {
        let value = "ADAPTER-CONCURRENT-6315"
        let anchor = try stageSettledAnchor(value: value)
        let fixedDate = Date(timeIntervalSince1970: 1_798_000_000)
        let settled = try SettlementAuthority.authorize(
            generatedText: "RESULT=\(value)",
            contractJSON: ExecutionStateGraphStore.referenceResultContractJSON,
            verifiedBindings: ["next_input": .string(value)],
            settledAt: fixedDate
        )
        let identities = [
            SettlementIdentityBinding.Identity(
                model: "concurrent-model-A", tokenizer: "concurrent-tokenizer-A"),
            SettlementIdentityBinding.Identity(
                model: "concurrent-model-B", tokenizer: "concurrent-tokenizer-B")
        ]
        let databaseURL = ManagedPaths.databaseURL
        let results = ConcurrentCommitResultBox()

        // Each worker opens its own SQLite connection. BEGIN IMMEDIATE serializes
        // writes; returned IDs remain transaction-local regardless of commit order.
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            do {
                let db = try ESISDatabase(url: databaseURL, createIfNeeded: false)
                let id = try db.recordNativeSettlementWithIdentity(
                    settled,
                    stateID: anchor.stateID,
                    identity: identities[index]
                )
                results.set(.success(id.uuidString), for: index)
            } catch {
                results.set(.failure(String(describing: error)), for: index)
            }
        }

        let snapshots = results.snapshot()
        let id0: String
        let id1: String
        guard let result0 = snapshots[0], let result1 = snapshots[1] else {
            XCTFail("both concurrent SQLite writers must return a result")
            return
        }
        switch result0 {
        case .success(let value): id0 = value
        case .failure(let detail):
            XCTFail("writer A failed: \(detail)")
            return
        }
        switch result1 {
        case .success(let value): id1 = value
        case .failure(let detail):
            XCTFail("writer B failed: \(detail)")
            return
        }
        XCTAssertNotEqual(id0, id1, "each committed settlement has its own UUID")

        let verifier = try ESISDatabase(url: databaseURL, createIfNeeded: false)
        let bindings0 = try verifier.settlementBindings(settlementID: id0)
        let bindings1 = try verifier.settlementBindings(settlementID: id1)
        XCTAssertEqual(
            bindings0[SettlementIdentityBinding.modelKey],
            SettlementIdentityBinding.digest(identities[0].model))
        XCTAssertEqual(
            bindings0[SettlementIdentityBinding.tokenizerKey],
            SettlementIdentityBinding.digest(identities[0].tokenizer))
        XCTAssertEqual(
            bindings1[SettlementIdentityBinding.modelKey],
            SettlementIdentityBinding.digest(identities[1].model))
        XCTAssertEqual(
            bindings1[SettlementIdentityBinding.tokenizerKey],
            SettlementIdentityBinding.digest(identities[1].tokenizer))

        let latest = try XCTUnwrap(verifier.latestSettlementID(forStateID: anchor.stateID))
        XCTAssertTrue(latest == id0 || latest == id1)
        XCTAssertTrue(id0 != latest || id1 != latest,
                      "same settledAt yields one latest ID, but both calls retain their own IDs")
    }

    // MARK: - Async throwing helpers

    private func catchAsyncError(
        _ body: () async throws -> Void
    ) async -> Error? {
        do { try await body(); return nil } catch { return error }
    }
}
