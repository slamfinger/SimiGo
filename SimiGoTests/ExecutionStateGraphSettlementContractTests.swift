import XCTest
import SQLite3
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
    private let identity = SettlementIdentityBinding.Identity(
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
    // The reference UI overload has no producer-identity argument, but its
    // receipt is still authoritative: a failed SQLite settlement insert must
    // leave both the in-memory projection and the durable IS settlement set
    // unchanged.
    @MainActor
    func testReferenceSettlementSQLiteFailureDoesNotPublishReceipt() throws {
        let store = ExecutionStateGraphStore(storeURL: storeURL, dbURL: dbURL)
        let root = try store.create()
        try store.continueState(root, input: "atomic-reference")
        let state = try XCTUnwrap(store.state(root.id))
        let before = store.document

        var rawDatabase: OpaquePointer?
        let openResult = sqlite3_open_v2(dbURL.path, &rawDatabase, SQLITE_OPEN_READWRITE, nil)
        guard openResult == SQLITE_OK, let rawDatabase else {
            XCTFail("could not open test database for trigger setup (SQLite code \(openResult))")
            if let rawDatabase { _ = sqlite3_close_v2(rawDatabase) }
            return
        }
        let triggerSQL = """
        CREATE TRIGGER reject_reference_settlement_insert
        BEFORE INSERT ON settlements
        BEGIN
            SELECT RAISE(ABORT, 'forced reference settlement failure');
        END;
        """
        let triggerResult = sqlite3_exec(rawDatabase, triggerSQL, nil, nil, nil)
        let triggerError = String(cString: sqlite3_errmsg(rawDatabase))
        let closeResult = sqlite3_close_v2(rawDatabase)
        XCTAssertEqual(triggerResult, SQLITE_OK, triggerError)
        XCTAssertEqual(closeResult, SQLITE_OK)
        guard triggerResult == SQLITE_OK else { return }

        XCTAssertThrowsError(
            try store.settleProducerResult(
                generatedText: "RESULT=atomic-reference", boundToState: state)
        )
        XCTAssertEqual(store.document, before, "failed settlement must not publish a UI receipt")
        XCTAssertTrue(receipts(store, stateID: state.id).isEmpty)

        let database = try XCTUnwrap(store.esis)
        XCTAssertTrue(try database.readSettlementReceipts().isEmpty)
        let graph = try database.readGraph()
        XCTAssertEqual(
            graph.states.first(where: { $0.id == state.id })?.nextInput,
            "atomic-reference",
            "the current ES snapshot remains intact after the settlement transaction rolls back")

        let reopened = ExecutionStateGraphStore(storeURL: storeURL, dbURL: dbURL)
        XCTAssertTrue((reopened.document.settlements ?? []).isEmpty)
        XCTAssertEqual(reopened.state(state.id)?.nextInput, "atomic-reference")
    }

    // A stale value captured before another continuation update must not
    // authorize the old next_input. The same stale selector can still settle
    // the current value once the producer returns the current binding.
    @MainActor
    func testReferenceSettlementUsesCurrentStateInsteadOfStaleSnapshot() throws {
        let store = ExecutionStateGraphStore(storeURL: storeURL, dbURL: dbURL)
        let root = try store.create()
        let stale = try store.continueState(root, input: "older-input")
        let current = try store.continueState(stale, input: "current-input")

        XCTAssertEqual(stale.nextInput, "older-input")
        XCTAssertEqual(current.nextInput, "current-input")

        XCTAssertThrowsError(
            try store.settleProducerResult(
                generatedText: "RESULT=older-input", boundToState: stale)
        ) { error in
            XCTAssertEqual(
                (error as? NativeResultContractError)?.code,
                "PRODUCER_RESULT_BINDING_MISMATCH")
        }
        XCTAssertTrue(receipts(store, stateID: current.id).isEmpty)

        let settled = try store.settleProducerResult(
            generatedText: "RESULT=current-input", boundToState: stale)
        XCTAssertEqual(settled.trace.validationStatus, "VALID")
        XCTAssertEqual(receipts(store, stateID: current.id).count, 1)

        let reopened = ExecutionStateGraphStore(storeURL: storeURL, dbURL: dbURL)
        XCTAssertEqual(
            reopened.document.settlements?.filter { $0.stateID == current.id }.count,
            1,
            "the successful receipt must survive restart")
    }

}
