import Foundation
import SQLite3
import XCTest
import SimiGoRuntimeContract
@testable import SimiGo

/// Directed regression for slice 8 (ES/IS core call chain), model-free.
///
/// Two invariants are asserted against the REAL product store, not stubs:
///
/// 1. `settlement` binds the value the PRE-GENERATION admission verified, never
///    a value re-read from mutable ES state. The documented product hazard is
///    staged literally: the parent settles `A`, admission verifies `A`, then the
///    same ES `nextInput` is moved to `B` by `continueState`. `RESULT=A` must
///    still settle; `RESULT=B` must be refused and write nothing.
/// 2. A successful continuation creates a CHILD Execution State distinct from
///    the parent, the new settlement belongs to that child, and the returned
///    child id is admissible by the next continuation.
///
/// No weights are loaded and no generation runs: the "generation" is a text
/// stand-in handed to the same store entry the production adapter uses.
/// Isolation: requires the injected isolated roots, otherwise XCTSkip.
final class ContinuationAdmissionSettlementBindingTests: XCTestCase {

    private var isolationRoot: URL!
    private var modelPath: String!
    private var consumer: SimiGoSettlementIdentityBinding.Identity!

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let home = env["SIMIGO_HOME"], !home.isEmpty,
              let graphStore = env["SIMIGO_STATE_GRAPH_STORE"], !graphStore.isEmpty,
              home.hasPrefix("/"), graphStore.hasPrefix("/") else {
            throw XCTSkip(
                "isolated roots not injected: run through the isolated xctestrun "
                + "(SIMIGO_HOME / SIMIGO_STATE_GRAPH_STORE) so no real state is written")
        }
        isolationRoot = URL(fileURLWithPath: (home as NSString).standardizingPath, isDirectory: true)
        XCTAssertTrue(
            SimiGoPaths.databaseURL.path.hasPrefix(isolationRoot.path),
            "authoritative store resolves outside the isolation root")

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimiGoBindingModelFree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"model_type":"binding-model-free-stand-in"}"#.utf8)
            .write(to: dir.appendingPathComponent("tokenizer.binding.json"))
        modelPath = dir.path
        consumer = SimiGoProducerIdentity.identity(fromPath: modelPath)
    }

    override func tearDown() {
        if let modelPath { try? FileManager.default.removeItem(atPath: modelPath) }
        super.tearDown()
    }

    /// Narrow raw SQL against the isolated database, used ONLY to inject a real
    /// lower-layer fault (a second connection can bypass this process's FKs).
    private func executeSQLite(_ sql: String) throws {
        var handle: OpaquePointer?
        let openRC = sqlite3_open(SimiGoPaths.databaseURL.path, &handle)
        guard openRC == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw NSError(
                domain: "ContinuationAdmissionSettlementBindingTests.SQLite",
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
                domain: "ContinuationAdmissionSettlementBindingTests.SQLite",
                code: Int(rc),
                userInfo: [NSLocalizedDescriptionKey: detail])
        }
        if let message { sqlite3_free(message) }
    }

    /// Stage a parent whose settled IS value is `value`.
    @MainActor
    private func stagedParent(
        store: ExecutionStateGraphStore,
        value: String
    ) throws -> ExecutionStateRecord {
        let parent = try store.continueState(try store.create(), input: value)
        try store.settleProducerResult(
            generatedText: "RESULT=\(value)",
            boundToState: parent,
            producerIdentity: consumer)
        return parent
    }

    // MARK: - 1. Admission value, not mutable ES state

    @MainActor
    func testSettlementBindsAdmittedValueNotMutatedNextInput() throws {
        let store = ExecutionStateGraphStore()
        let parent = try stagedParent(store: store, value: "A")

        let admitted = try store.admitContinuation(stateID: parent.id, consumer: consumer)
        XCTAssertEqual(admitted.recoveredValue, "A")
        XCTAssertEqual(admitted.verifiedBindings["next_input"], .string("A"))

        // The exact hazard: the SAME ES nextInput moves to B after the settled
        // value that admission verified was A.
        _ = try store.continueState(parent, input: "B")
        XCTAssertEqual(store.state(parent.id)?.nextInput, "B",
                       "precondition: the mutable ES field now disagrees with the IS")

        // The correct output settles against the ADMITTED value.
        let child = "es-child-a-\(UUID().uuidString.lowercased())"
        let commit = try store.settleContinuationResult(
            generatedText: "RESULT=A",
            parentStateID: parent.id,
            childStateID: child,
            verifiedBindings: admitted.verifiedBindings,
            producerIdentity: consumer)
        XCTAssertEqual(commit.childStateID, child)
        XCTAssertEqual(try store.esis?.latestSettlementID(forStateID: child), commit.settlementID)

        // The output matching the MUTATED ES field is refused, and leaves no
        // child ES and no settlement behind.
        let refusedChild = "es-child-b-\(UUID().uuidString.lowercased())"
        XCTAssertThrowsError(try store.settleContinuationResult(
            generatedText: "RESULT=B",
            parentStateID: parent.id,
            childStateID: refusedChild,
            verifiedBindings: admitted.verifiedBindings,
            producerIdentity: consumer)) { error in
            XCTAssertEqual(
                continuationSettlementTerminal(for: error).errorKind,
                "NATIVE_RESULT_CONTRACT_REJECTED",
                "a value that only matches mutable ES state must not settle")
        }
        XCTAssertNil(store.state(refusedChild), "no child ES may be created on refusal")
        XCTAssertNil(try store.esis?.latestSettlementID(forStateID: refusedChild))
    }

    // MARK: - 2. Child ES identity + chainability

    @MainActor
    func testSuccessCreatesChainableChildExecutionState() throws {
        let store = ExecutionStateGraphStore()
        let parent = try stagedParent(store: store, value: "CHAIN-A")
        let parentPosition = try XCTUnwrap(store.state(parent.id)).position
        let admitted = try store.admitContinuation(stateID: parent.id, consumer: consumer)

        let child = "es-child-chain-\(UUID().uuidString.lowercased())"
        let commit = try store.settleContinuationResult(
            generatedText: "RESULT=CHAIN-A",
            parentStateID: parent.id,
            childStateID: child,
            verifiedBindings: admitted.verifiedBindings,
            producerIdentity: consumer)

        let childState = try XCTUnwrap(store.state(child))
        XCTAssertNotEqual(childState.id, parent.id, "the child ES is a distinct state")
        XCTAssertEqual(childState.parentID, parent.id)
        XCTAssertEqual(childState.position, parentPosition + 1)
        XCTAssertEqual(childState.lifecycle, .active)
        XCTAssertEqual(childState.nextInput, "CHAIN-A",
                       "the child's IS projection is the value it settled")

        // The settlement belongs to the CHILD, not the parent anchor.
        let receipts = store.document.settlements ?? []
        XCTAssertEqual(receipts.filter { $0.stateID == child }.count, 1)
        let childReceipt = try XCTUnwrap(receipts.first { $0.stateID == child })
        XCTAssertEqual(childState.anchor, childReceipt.payloadDigest,
                       "the child anchors on the digest of its own settlement")
        XCTAssertEqual(receipts.filter { $0.id.uuidString == commit.settlementID }.first?.stateID, child)

        // Chainability: the returned child id admits on its own.
        let next = try store.admitContinuation(stateID: child, consumer: consumer)
        XCTAssertEqual(next.recoveredValue, "CHAIN-A")
        XCTAssertEqual(next.settlementID, commit.settlementID)
    }

    // MARK: - 2b. The persisted child IS the projected child (durable lineage)

    /// A child created by a continuation must survive a reload with the SAME
    /// representation the graph projected. Otherwise a restarted product reads the
    /// child back with an empty prefix and the next `continueState` silently drops
    /// every ancestor — the settlement would be durable while its lineage is not.
    @MainActor
    func testChildStateSurvivesReloadWithFullLineage() throws {
        let store = ExecutionStateGraphStore()
        let parent = try stagedParent(store: store, value: "LINEAGE-A")
        let parentPrefix = try XCTUnwrap(store.state(parent.id)).prefix
        let admitted = try store.admitContinuation(stateID: parent.id, consumer: consumer)

        let child = "es-child-lineage-\(UUID().uuidString.lowercased())"
        try store.settleContinuationResult(
            generatedText: "RESULT=LINEAGE-A",
            parentStateID: parent.id,
            childStateID: child,
            verifiedBindings: admitted.verifiedBindings,
            producerIdentity: consumer)

        let projected = try XCTUnwrap(store.state(child))

        // A fresh store = what a restarted product reads back from SQLite.
        let reloaded = ExecutionStateGraphStore()
        let durable = try XCTUnwrap(reloaded.state(child))
        XCTAssertEqual(durable.nextInput, projected.nextInput,
                       "the durable child must carry the value the projection carries")
        XCTAssertEqual(durable.nextInput, "LINEAGE-A")
        XCTAssertEqual(durable.prefix, projected.prefix,
                       "the durable child must carry the same lineage as the projection")
        XCTAssertEqual(durable.prefix, parentPrefix + ["LINEAGE-A"],
                       "the child's lineage is the parent's prefix plus its own value")
        XCTAssertEqual(durable.parentID, parent.id)
        XCTAssertEqual(durable.anchor, projected.anchor)

        // Continuing the durable child APPENDS to that lineage.
        let next = try reloaded.continueState(durable, input: "LINEAGE-B")
        XCTAssertEqual(next.prefix, parentPrefix + ["LINEAGE-A", "LINEAGE-B"],
                       "continuing the child must not reset its ancestry")
        XCTAssertEqual(next.nextInput, "LINEAGE-B")
    }

    // MARK: - 3. No orphan child, no double create

    @MainActor
    func testChildIdentityIsExclusiveAndRequiresALiveParent() throws {
        let store = ExecutionStateGraphStore()
        let parent = try stagedParent(store: store, value: "EXCL-A")
        let admitted = try store.admitContinuation(stateID: parent.id, consumer: consumer)
        let child = "es-child-exclusive-\(UUID().uuidString.lowercased())"

        try store.settleContinuationResult(
            generatedText: "RESULT=EXCL-A",
            parentStateID: parent.id,
            childStateID: child,
            verifiedBindings: admitted.verifiedBindings,
            producerIdentity: consumer)

        // The same child id can never be re-created (no second settlement).
        XCTAssertThrowsError(try store.settleContinuationResult(
            generatedText: "RESULT=EXCL-A",
            parentStateID: parent.id,
            childStateID: child,
            verifiedBindings: admitted.verifiedBindings,
            producerIdentity: consumer))

        // A discarded parent cannot be continued, and nothing is written.
        try store.discard(parent)
        let afterDiscard = "es-child-after-discard-\(UUID().uuidString.lowercased())"
        XCTAssertThrowsError(try store.settleContinuationResult(
            generatedText: "RESULT=EXCL-A",
            parentStateID: parent.id,
            childStateID: afterDiscard,
            verifiedBindings: admitted.verifiedBindings,
            producerIdentity: consumer))
        XCTAssertNil(store.state(afterDiscard))
        XCTAssertNil(try store.esis?.latestSettlementID(forStateID: afterDiscard))
    }

    // MARK: - 4. The authoritative row, not the projection, defines the lineage

    /// The in-memory graph can outlive its parent ROW: a second connection with
    /// `foreign_keys = OFF` can drop the row while this process still projects the
    /// state. The product write must refuse, because the projection is not a second
    /// source of truth. Before this was fixed the call wrote a child whose
    /// `parent_id` pointed at nothing and reported success.
    @MainActor
    func testContinuationRefusesParentRowMissingFromAuthoritativeStore() throws {
        let store = ExecutionStateGraphStore()
        let parent = try stagedParent(store: store, value: "GHOST-A")
        let admitted = try store.admitContinuation(stateID: parent.id, consumer: consumer)
        let child = "es-child-ghost-\(UUID().uuidString.lowercased())"

        try executeSQLite(
            "PRAGMA foreign_keys=OFF; DELETE FROM execution_states WHERE state_id='\(parent.id)';")
        let db = try XCTUnwrap(store.esis)
        XCTAssertNil(try db.readGraph().states.first { $0.id == parent.id },
                     "precondition: the authoritative parent row is gone")
        XCTAssertNotNil(store.state(parent.id),
                        "precondition: the in-memory projection still holds the parent")

        let statesBefore = try db.count("execution_states")
        let settlementsBefore = try db.count("settlements")
        let bindingsBefore = try db.count("settlement_bindings")

        XCTAssertThrowsError(try store.settleContinuationResult(
            generatedText: "RESULT=GHOST-A",
            parentStateID: parent.id,
            childStateID: child,
            verifiedBindings: admitted.verifiedBindings,
            producerIdentity: consumer)
        ) { error in
            guard case SimiGoESISDatabase.DatabaseError.missingParentState(let missing) = error else {
                return XCTFail("expected .missingParentState from the authoritative write, got \(error)")
            }
            XCTAssertEqual(missing, parent.id)
        }

        XCTAssertEqual(try db.count("execution_states"), statesBefore,
                       "a refused continuation writes no child row")
        XCTAssertEqual(try db.count("settlements"), settlementsBefore,
                       "no settlement may survive the refused commit")
        XCTAssertEqual(try db.count("settlement_bindings"), bindingsBefore)
        XCTAssertNil(try db.latestSettlementID(forStateID: child))
        XCTAssertNil(store.state(child), "the projection must not gain a child either")
    }
}
