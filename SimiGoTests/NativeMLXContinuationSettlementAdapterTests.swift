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
    private func authoritativeBindingCountTotal() throws -> Int {
        let db = try XCTUnwrap(store().esis)
        return try db.count("settlement_bindings")
    }

    /// Execute narrowly scoped SQL against the isolated test database, used only
    /// to inject a failure exactly when a producer identity binding is inserted.
    private func executeIsolatedSQLite(_ sql: String) throws {
        var handle: OpaquePointer?
        let openRC = sqlite3_open(SimiGoPaths.databaseURL.path, &handle)
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
        // produced, handed to the same entry the dispatch uses, together with the
        // bindings the pre-generation admission verified and the child ES.
        let child = "es-child-\(UUID().uuidString.lowercased())"
        let outcome = try await handler(ContinuationSettlementRequest(
            generatedText: "RESULT=\(value)",
            parentESStateID: anchor,
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
        XCTAssertNotEqual(child, anchor)
        XCTAssertEqual(fresh.state(child)?.parentID, anchor,
                       "the settled state must be a child of the continuation anchor")

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
        let anchor = try stageUnsettledAnchor(value: "ADAPTER-REFUSE-6312")

        let handler = makeNativeMLXContinuationSettlementHandler(modelPath: modelPath!)
        let child = "es-child-\(UUID().uuidString.lowercased())"
        let error = await catchAsyncError {
            _ = try await handler(ContinuationSettlementRequest(
                generatedText: "NOISE-OFF-CONTRACT",
                parentESStateID: anchor,
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
        let anchor = try stageUnsettledAnchor(value: "ADAPTER-IDENTITY-6313")
        let handler = makeNativeMLXContinuationSettlementHandler(modelPath: modelPath!)
        let outcome = try await handler(ContinuationSettlementRequest(
            generatedText: "RESULT=ADAPTER-IDENTITY-6313",
            parentESStateID: anchor,
            childESStateID: "es-child-\(UUID().uuidString.lowercased())",
            verifiedBindings: ["next_input": .string("ADAPTER-IDENTITY-6313")]))
        XCTAssertTrue(outcome.identityBindingPublished)

        let fresh = store()
        let own = SimiGoProducerIdentity.identity(fromPath: modelPath!)
        let admitted = try fresh.admitContinuation(
            stateID: outcome.childESStateID, consumer: own)
        XCTAssertEqual(admitted.recoveredValue, "ADAPTER-IDENTITY-6313")

        let borrowed = SimiGoSettlementIdentityBinding.Identity(
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
        let anchor = try stageUnsettledAnchor(value: "ADAPTER-ATOMIC-6314")
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
                parentESStateID: anchor,
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
        let anchor = try stageUnsettledAnchor(value: value)
        let fixedDate = Date(timeIntervalSince1970: 1_798_000_000)
        let settled = try SimiGoSettlementAuthority.authorize(
            generatedText: "RESULT=\(value)",
            contractJSON: ExecutionStateGraphStore.referenceResultContractJSON,
            verifiedBindings: ["next_input": .string(value)],
            settledAt: fixedDate
        )
        let identities = [
            SimiGoSettlementIdentityBinding.Identity(
                model: "concurrent-model-A", tokenizer: "concurrent-tokenizer-A"),
            SimiGoSettlementIdentityBinding.Identity(
                model: "concurrent-model-B", tokenizer: "concurrent-tokenizer-B")
        ]
        let databaseURL = SimiGoPaths.databaseURL
        let results = ConcurrentCommitResultBox()

        // Each worker opens its own SQLite connection. BEGIN IMMEDIATE serializes
        // writes; returned IDs remain transaction-local regardless of commit order.
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            do {
                let db = try SimiGoESISDatabase(url: databaseURL, createIfNeeded: false)
                let id = try db.recordNativeSettlementWithIdentity(
                    settled,
                    stateID: anchor,
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

        let verifier = try SimiGoESISDatabase(url: databaseURL, createIfNeeded: false)
        let bindings0 = try verifier.settlementBindings(settlementID: id0)
        let bindings1 = try verifier.settlementBindings(settlementID: id1)
        XCTAssertEqual(
            bindings0[SimiGoSettlementIdentityBinding.modelKey],
            SimiGoSettlementIdentityBinding.digest(identities[0].model))
        XCTAssertEqual(
            bindings0[SimiGoSettlementIdentityBinding.tokenizerKey],
            SimiGoSettlementIdentityBinding.digest(identities[0].tokenizer))
        XCTAssertEqual(
            bindings1[SimiGoSettlementIdentityBinding.modelKey],
            SimiGoSettlementIdentityBinding.digest(identities[1].model))
        XCTAssertEqual(
            bindings1[SimiGoSettlementIdentityBinding.tokenizerKey],
            SimiGoSettlementIdentityBinding.digest(identities[1].tokenizer))

        let latest = try XCTUnwrap(verifier.latestSettlementID(forStateID: anchor))
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
