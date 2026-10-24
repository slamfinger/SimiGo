import Foundation
import XCTest
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
            SimiGoPaths.databaseURL.path.hasPrefix(isolationRoot.path),
            "authoritative store resolves outside the isolation root: \(SimiGoPaths.databaseURL.path)")
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

    /// Stage a live, NOT-yet-settled ES state in the product's authoritative
    /// store, mirroring how a continuation anchor exists before the hot path
    /// settles it. Returns the state id used as `previous_es_state_id`.
    @MainActor
    private func stageUnsettledAnchor(value: String) throws -> String {
        let store = ExecutionStateGraphStore()
        let root = try store.create()
        try store.continueState(root, input: value)
        let state = try XCTUnwrap(store.state(root.id))
        XCTAssertNil(try store.esis?.latestSettlementID(forStateID: state.id),
                     "the staged anchor must start unsettled")
        return state.id
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
    private func store() -> ExecutionStateGraphStore { ExecutionStateGraphStore() }

    // MARK: - Tests

    /// Positive: the production adapter settles the ACTUAL generated text over
    /// the real native gate, the id it reports is the authoritative one, the
    /// identity binding is readable, and a later continuation admits the
    /// settlement through the same store.
    @MainActor
    func testProductionAdapterSettlesAndStaysAdmissible() async throws {
        let value = "ADAPTER-SETTLE-6311"
        let anchor = try stageUnsettledAnchor(value: value)

        let handler = makeNativeMLXContinuationSettlementHandler(modelPath: modelPath!)
        // Model-free generation stand-in: the text a real generation would have
        // produced, handed to the same entry the dispatch uses.
        let outcome = try await handler("RESULT=\(value)", anchor)

        XCTAssertFalse(outcome.settlementID.isEmpty)
        XCTAssertTrue(outcome.identityBindingPublished)

        // The reported id is the authoritative store's own settlement id.
        let fresh = store()
        let recorded = try XCTUnwrap(fresh.esis?.latestSettlementID(forStateID: anchor))
        XCTAssertEqual(recorded, outcome.settlementID,
                       "the adapter must report the id the authoritative store issued")
        XCTAssertEqual(receipts(for: fresh, stateID: anchor).count, 1)
        XCTAssertEqual(try authoritativeReceiptCount(stateID: anchor), 1)

        // Identity binding really landed in settlement_bindings (read back).
        // The store persists `digest(identity.model|tokenizer)`, the same form
        // `SimiGoISAdmission` compares a consumer against, so the read-back must
        // match the digest of the identity re-derived from THIS snapshot.
        let own = SimiGoProducerIdentity.identity(fromPath: modelPath!)
        let bindings = try XCTUnwrap(fresh.esis).settlementBindings(settlementID: outcome.settlementID)
        XCTAssertEqual(
            bindings[SimiGoSettlementIdentityBinding.modelKey],
            SimiGoSettlementIdentityBinding.digest(own.model),
            "the published binding must be the identity re-derived from THIS runtime's snapshot")
        XCTAssertEqual(
            bindings[SimiGoSettlementIdentityBinding.tokenizerKey],
            SimiGoSettlementIdentityBinding.digest(own.tokenizer))

        // Admission seam: the settlement this adapter published is admissible by
        // the continuation path that follows.
        let admitted = try fresh.admitContinuation(stateID: anchor, consumer: own)
        XCTAssertEqual(admitted.recoveredValue, value)
    }

    /// A violating generated output is refused by the existing native contract
    /// INSIDE the adapter: the terminal is the contract class and nothing is
    /// written — neither the graph receipt nor the authoritative row.
    @MainActor
    func testContractRefusalLeavesNoHalfSettledRecord() async throws {
        let anchor = try stageUnsettledAnchor(value: "ADAPTER-REFUSE-6312")

        let handler = makeNativeMLXContinuationSettlementHandler(modelPath: modelPath!)
        let error = await catchAsyncError { _ = try await handler("NOISE-OFF-CONTRACT", anchor) }
        let unwrapped = try XCTUnwrap(error, "a violating output must be refused")
        let terminal = continuationSettlementTerminal(for: unwrapped)
        XCTAssertEqual(terminal.status, 422)
        XCTAssertEqual(terminal.errorKind, "NATIVE_RESULT_CONTRACT_REJECTED")

        let fresh = store()
        XCTAssertTrue(receipts(for: fresh, stateID: anchor).isEmpty,
                      "a refused settlement must leave no partial record")
        XCTAssertEqual(try authoritativeReceiptCount(stateID: anchor), 0)
        XCTAssertNil(try fresh.esis?.latestSettlementID(forStateID: anchor))
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
            _ = try await handler("RESULT=anything", ghostAnchor)
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
        let anchor = try stageUnsettledAnchor(value: "ADAPTER-IDENTITY-6313")
        let handler = makeNativeMLXContinuationSettlementHandler(modelPath: modelPath!)
        let outcome = try await handler("RESULT=ADAPTER-IDENTITY-6313", anchor)
        XCTAssertTrue(outcome.identityBindingPublished)

        let fresh = store()
        let own = SimiGoProducerIdentity.identity(fromPath: modelPath!)
        let admitted = try fresh.admitContinuation(stateID: anchor, consumer: own)
        XCTAssertEqual(admitted.recoveredValue, "ADAPTER-IDENTITY-6313")

        let borrowed = SimiGoSettlementIdentityBinding.Identity(
            model: "borrowed-model-digest", tokenizer: "borrowed-tokenizer-digest")
        XCTAssertThrowsError(
            try fresh.admitContinuation(stateID: anchor, consumer: borrowed),
            "a borrowed identity must not admit this settlement"
        )
    }

    // MARK: - Async throwing helpers

    private func catchAsyncError(
        _ body: () async throws -> Void
    ) async -> Error? {
        do { try await body(); return nil } catch { return error }
    }
}
