import XCTest
import SimiGoRuntimeContract
@testable import SimiGo

/// Store-level, model-free proof for the settlement side of the continuation
/// contract v0.1: the generated output must pass the EXISTING native gate
/// before the authoritative store writes anything. A violating output throws
/// and leaves no half-settled record; a compliant output produces a readable
/// settlement whose published identity binding makes it admissible.
final class ExecutionStateGraphSettlementContractTests: XCTestCase {

    private var storeURL: URL!
    private var dbURL: URL!
    private let identity = SimiGoSettlementIdentityBinding.Identity(
        model: "mlx:qwen3-coder-30b", tokenizer: "tok:6e302ea6")

    override func setUp() {
        super.setUp()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimiGoSettleContract-\(UUID().uuidString)")
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

    @MainActor
    private func receipts(_ store: ExecutionStateGraphStore, stateID: String) -> [SettlementReceipt] {
        (store.document.settlements ?? []).filter { $0.stateID == stateID }
    }

    // A violating output is refused by the native gate BEFORE any write:
    // the state has no settlement receipt, and the refusal maps to the
    // contract-rejected class — never admission refusal, never engine noise.
    @MainActor
    func testViolatingOutputRefusedWithNoHalfSettledRecord() throws {
        let store = ExecutionStateGraphStore(storeURL: storeURL, dbURL: dbURL)
        let root = try store.create()
        try store.continueState(root, input: "hello")
        let state = try XCTUnwrap(store.state(root.id))

        XCTAssertThrowsError(
            try store.settleProducerResult(
                generatedText: "NOISE", boundToState: state, producerIdentity: identity)
        ) { error in
            XCTAssertTrue(
                error is NativeResultContractError,
                "expected native contract rejection, got \(error)")
            guard case ContinuationSettlementFailure.contractRejected =
                ContinuationSettlementFailure(storeError: error) else {
                return XCTFail("store rejection must map to contractRejected")
            }
        }
        XCTAssertTrue(
            receipts(store, stateID: state.id).isEmpty,
            "a refused settlement must leave no partial record")
    }

    // The compliant path writes a readable settlement and publishes the
    // producer identity so a fresh continuation admits it through the store.
    @MainActor
    func testValidSettlementIsReadableAndIdentityAdmissible() throws {
        let store = ExecutionStateGraphStore(storeURL: storeURL, dbURL: dbURL)
        let root = try store.create()
        try store.continueState(root, input: "hello")
        let state = try XCTUnwrap(store.state(root.id))

        let settled = try store.settleProducerResult(
            generatedText: "RESULT=hello", boundToState: state, producerIdentity: identity)
        XCTAssertFalse(settled.payloadDigest.isEmpty)
        XCTAssertEqual(receipts(store, stateID: state.id).count, 1)

        let admitted = try store.admitContinuation(stateID: state.id, consumer: identity)
        XCTAssertEqual(admitted.recoveredValue, "hello")
    }

    // Infrastructure errors map to the engine class, never contract refusal.
    func testInfrastructureErrorMapsToEngine() {
        let mapped = ContinuationSettlementFailure(
            storeError: NSError(domain: "SQLite", code: 14))
        guard case .engine = mapped else {
            return XCTFail("infrastructure error must not map to contractRejected")
        }
    }
}
