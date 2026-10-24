import XCTest
import SimiGoRuntimeContract
@testable import SimiGo

/// Directed tests through the product's authoritative ES/IS store — the same
/// entry the UI Settle action and the headless driver use. They prove the
/// continuation READ/recover edge now actually invokes the native IS admission
/// authority: a settled value is recovered with `verifiedBindings` only when it
/// verifies, and is refused fail-closed (before any binding can feed a
/// generation) otherwise.
///
/// Hermetic and model-free: each test drives a fresh per-run SQLite IS under a
/// temp directory, so no model, Keychain, GUI, or real user state is involved.
final class ExecutionStateGraphAdmissionTests: XCTestCase {

    private var storeURL: URL!
    private var dbURL: URL!
    private let identity = SimiGoSettlementIdentityBinding.Identity(
        model: "mlx:qwen3-coder-30b", tokenizer: "tok:6e302ea6")

    override func setUp() {
        super.setUp()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimiGoAdmissionStoreTests-\(UUID().uuidString)")
        storeURL = base.appendingPathComponent("graph.json")
        dbURL = base.appendingPathComponent("estates.sqlite3")
    }

    override func tearDown() {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(at: URL(fileURLWithPath: dbURL.path + suffix))
        }
        try? fm.removeItem(at: storeURL)
        super.tearDown()
    }

    /// Create + continue + settle a state through the real store, publishing the
    /// producer identity so the settlement is admissible.
    @MainActor
    private func settledState(_ store: ExecutionStateGraphStore, value: String) throws -> ExecutionStateRecord {
        let root = try store.create()
        try store.continueState(root, input: value)
        let state = try XCTUnwrap(store.state(root.id))
        _ = try store.settleProducerResult(
            generatedText: "RESULT=\(value)", boundToState: state, producerIdentity: identity)
        return state
    }

    // Valid path: the store recovers the settled IS value and mints bindings for
    // a fresh ES — the product store driving the native admission authority.
    @MainActor
    func testStoreAdmitsSettledContinuationAndMintsBindings() throws {
        let store = ExecutionStateGraphStore(storeURL: storeURL, dbURL: dbURL)
        let state = try settledState(store, value: "hello")

        let admitted = try store.admitContinuation(stateID: state.id, consumer: identity)

        XCTAssertEqual(admitted.recoveredValue, "hello")
        XCTAssertEqual(admitted.verifiedBindings["next_input"], .string("hello"))
    }

    // A settlement produced by a different model is refused before any binding
    // is produced (identity binding is fail-closed).
    @MainActor
    func testStoreRefusesValueProducedByDifferentModel() throws {
        let store = ExecutionStateGraphStore(storeURL: storeURL, dbURL: dbURL)
        let state = try settledState(store, value: "hello")
        let other = SimiGoSettlementIdentityBinding.Identity(model: "mlx:different", tokenizer: identity.tokenizer)

        XCTAssertThrowsError(try store.admitContinuation(stateID: state.id, consumer: other)) { error in
            guard case SimiGoISAdmission.Refusal.producerBinding(let verdict) = error else {
                return XCTFail("expected producerBinding refusal, got \(error)")
            }
            XCTAssertEqual(verdict.code, SimiGoSettlementIdentityBinding.Refusal.modelMismatch.rawValue)
        }
    }

    // A state that was continued but never settled has no verified IS value to
    // recover: admission refuses with noSettlement, before any generation input
    // could be assembled.
    @MainActor
    func testStoreRefusesUnsettledStateBeforeProducingBindings() throws {
        let store = ExecutionStateGraphStore(storeURL: storeURL, dbURL: dbURL)
        let root = try store.create()
        try store.continueState(root, input: "hello")   // continued but NOT settled

        XCTAssertThrowsError(try store.admitContinuation(stateID: root.id, consumer: identity)) { error in
            guard case SimiGoISAdmission.Refusal.noSettlement = error else {
                return XCTFail("expected noSettlement refusal, got \(error)")
            }
        }
    }
}
