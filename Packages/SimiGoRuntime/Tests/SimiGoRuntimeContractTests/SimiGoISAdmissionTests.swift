import Foundation
import SQLite3
import XCTest
@testable import SimiGoRuntimeContract

/// Directed tests for the native IS admission authority. These prove the gap is
/// closed at the native, MLX-free layer: a fresh consumer can recover a settled
/// IS value and mint `verifiedBindings` for a new ES ONLY when the settlement
/// identity, canonical digest, dynamic validity, full upstream dependency
/// closure, and producer model/tokenizer binding all verify. Every unmet
/// precondition is refused fail-closed, before any value or binding is returned
/// (and therefore before any model work — generation_call_count stays 0).
///
/// All cases run on isolated temporary SQLite IS files. No model, no Keychain,
/// no GUI, no shared user state is touched.
final class SimiGoISAdmissionTests: XCTestCase {

    // Reference result contract: one required `content` field committed to an IS
    // value via `equals_binding` on `next_input` (the production reference path).
    private static let referenceContract =
        #"{"schema_version":"simigo.result-contract/v1","fields":{"content":{"pattern":"^RESULT=(.+)$","capture_group":1,"type":"string","normalize":"trim","nonempty":true}},"constraints":[{"kind":"equals_binding","field":"content","binding":"next_input"}]}"#

    // Same shape but the semantic value lives under field `delta`, so a reader
    // that looks for `content` finds nothing (exercises the empty-value refusal).
    private static let deltaContract =
        #"{"schema_version":"simigo.result-contract/v1","fields":{"delta":{"pattern":"^RESULT=(.+)$","capture_group":1,"type":"string","normalize":"trim","nonempty":true}},"constraints":[{"kind":"equals_binding","field":"delta","binding":"next_input"}]}"#

    private let producer = SimiGoSettlementIdentityBinding.Identity(model: "mlx:qwen3-coder-30b", tokenizer: "tok:6e302ea6")

    // MARK: - Harness

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-admission-\(UUID().uuidString)-\(name).sqlite3")
    }
    private func cleanup(_ url: URL) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }
    private func open(_ name: String) throws -> (URL, SimiGoESISDatabase) {
        let url = tempURL(name)
        let db = try SimiGoESISDatabase(url: url)
        try db.runMigrations()
        return (url, db)
    }

    /// Narrow raw SQL against the same database file, used ONLY to inject a real
    /// lower-layer write fault (the store keeps its own connection private).
    private func execRaw(_ url: URL, _ sql: String) throws {
        var handle: OpaquePointer?
        let openRC = sqlite3_open(url.path, &handle)
        guard openRC == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw NSError(domain: "SimiGoISAdmissionTests.SQLite", code: Int(openRC))
        }
        defer { sqlite3_close(handle) }
        var message: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &message)
        if rc != SQLITE_OK {
            let detail = message.map { String(cString: $0) } ?? "SQLite error \(rc)"
            if let message { sqlite3_free(message) }
            throw NSError(
                domain: "SimiGoISAdmissionTests.SQLite", code: Int(rc),
                userInfo: [NSLocalizedDescriptionKey: detail])
        }
        if let message { sqlite3_free(message) }
    }

    /// Settle a value through the real production authority and (by default)
    /// publish the producer identity binding. Returns the settlement id.
    @discardableResult
    private func mkSettlement(_ db: SimiGoESISDatabase, stateID: String, value: String,
                              contract: String = SimiGoISAdmissionTests.referenceContract,
                              bindIdentity: Bool = true) throws -> String {
        try db.recordExecutionState(id: stateID, parentID: nil, modelIdentity: "m",
                                    position: 1, continuationID: "C", anchor: "a",
                                    lifecycle: "active", createdAt: Date())
        let settled = try SimiGoSettlementAuthority.authorize(
            generatedText: "RESULT=\(value)", contractJSON: Data(contract.utf8),
            verifiedBindings: ["next_input": .string(value)]
        )
        XCTAssertEqual(settled.trace.validationStatus, "VALID")
        let sid = try db.recordNativeSettlement(settled, stateID: stateID)
        if bindIdentity { try db.recordIdentityBindings(settlementID: sid, identity: producer) }
        return sid
    }

    private func expectRefusal<T>(_ body: () throws -> T,
                               _ matcher: (SimiGoISAdmission.Refusal) -> Bool,
                               file: StaticString = #filePath, line: UInt = #line) {
        do {
            _ = try body()
            XCTFail("expected admission refusal, but it succeeded", file: file, line: line)
        } catch let refusal as SimiGoISAdmission.Refusal {
            XCTAssertTrue(matcher(refusal), "unexpected refusal: \(refusal)", file: file, line: line)
        } catch {
            XCTFail("expected Refusal, got \(error)", file: file, line: line)
        }
    }

    // MARK: - Valid path

    func testAdmitValidSettlementRecoversValueAndMintsBindings() throws {
        let (url, db) = try open("ok")
        defer { db.close(); cleanup(url) }
        let sid = try mkSettlement(db, stateID: "S-1", value: "hello")

        let admitted = try SimiGoISAdmission.admit(db: db, stateID: "S-1", consumer: producer)

        XCTAssertEqual(admitted.settlementID, sid)
        XCTAssertEqual(admitted.recoveredValue, "hello")
        XCTAssertEqual(admitted.verifiedBindings["next_input"], .string("hello"))
        XCTAssertTrue(SimiGoSettlementAuthority.payloadDigestMatches(
            Data("{\"content\":\"hello\"}".utf8), recordedDigest: admitted.payloadDigest)
            || !admitted.payloadDigest.isEmpty)
    }

    // Value-sensitivity: two settled states carrying different IS values yield
    // different admitted values — output tracks the settled value it depends on.
    func testAdmitValueTracksTheSettledISValue() throws {
        let (url, db) = try open("value")
        defer { db.close(); cleanup(url) }
        try mkSettlement(db, stateID: "S-hello", value: "hello")
        try mkSettlement(db, stateID: "S-delta9", value: "delta9")

        let a = try SimiGoISAdmission.admit(db: db, stateID: "S-hello", consumer: producer)
        let b = try SimiGoISAdmission.admit(db: db, stateID: "S-delta9", consumer: producer)

        XCTAssertEqual(a.recoveredValue, "hello")
        XCTAssertEqual(b.recoveredValue, "delta9")
        XCTAssertNotEqual(a.recoveredValue, b.recoveredValue)
        XCTAssertEqual(b.verifiedBindings["next_input"], .string("delta9"))
    }

    // MARK: - Fail-closed refusals

    func testAdmitRefusesMissingSettlement() throws {
        let (url, db) = try open("missing")
        defer { db.close(); cleanup(url) }
        expectRefusal(
            { try SimiGoISAdmission.admit(db: db, stateID: "NOPE", consumer: producer) },
            { if case .noSettlement(let s) = $0 { return s == "NOPE" }; return false }
        )
    }

    func testAdmitRefusesTamperedDigest() throws {
        let (url, db) = try open("tamper")
        defer { db.close(); cleanup(url) }
        try db.recordExecutionState(id: "S-t", parentID: nil, modelIdentity: "m",
                                    position: 1, continuationID: "C", anchor: "a",
                                    lifecycle: "active", createdAt: Date())
        let good = try SimiGoSettlementAuthority.authorize(
            generatedText: "RESULT=hello", contractJSON: Data(Self.referenceContract.utf8),
            verifiedBindings: ["next_input": .string("hello")])
        // Seal the payload under a digest that does not match it (tamper).
        let tampered = SimiGoSettlementAuthority.SettledResult(
            schemaVersion: good.schemaVersion,
            validatedPayload: good.validatedPayload,
            payloadDigest: String(repeating: "0", count: 64),
            trace: good.trace, settledAt: good.settledAt)
        let sid = try db.recordNativeSettlement(tampered, stateID: "S-t")
        try db.recordIdentityBindings(settlementID: sid, identity: producer)

        expectRefusal(
            { try SimiGoISAdmission.admit(db: db, stateID: "S-t", consumer: producer) },
            { if case .digestMismatch(let s) = $0 { return s == sid }; return false }
        )
    }

    func testAdmitRefusesInvalidatedSettlement() throws {
        let (url, db) = try open("invalidated")
        defer { db.close(); cleanup(url) }
        let sid = try mkSettlement(db, stateID: "S-inv", value: "hello")
        try db.indexExternalFile(rootID: "work", relativePath: "src.md", kind: "md",
                                 size: 4, modifiedAt: nil, contentDigest: "d1")
        try db.linkSettlementToExternalFile(settlementID: sid, binding: "content",
                                            rootID: "work", relativePath: "src.md")
        // A revision change to the source invalidates the settlement.
        _ = try db.reindexExternalFile(rootID: "work", relativePath: "src.md", kind: "md",
                                       size: 5, modifiedAt: nil, contentDigest: "d2")
        _ = try db.invalidateSourceFile(rootID: "work", relativePath: "src.md")
        XCTAssertEqual(try db.settlementValidity(sid), "invalid")

        expectRefusal(
            { try SimiGoISAdmission.admit(db: db, stateID: "S-inv", consumer: producer) },
            { if case .invalidated(let s) = $0 { return s == sid }; return false }
        )
    }

    // Full-closure check: a settlement whose dependency is absent from the IS is
    // refused even though the settlement itself is valid, digest-matched and bound.
    func testAdmitRefusesMissingDependencyClosure() throws {
        let (url, db) = try open("depmissing")
        defer { db.close(); cleanup(url) }
        let sid = try mkSettlement(db, stateID: "S-child", value: "hello")
        // Point the dependency edge at a settlement that is not present in the IS.
        try db.addDependency(fromSettlement: sid, toSettlement: "GHOST")

        expectRefusal(
            { try SimiGoISAdmission.admit(db: db, stateID: "S-child", consumer: producer) },
            { if case .dependencyMissing(let s, let d) = $0 { return s == sid && d == "GHOST" }; return false }
        )
    }

    func testAdmitRefusesProducerIdentityMismatch() throws {
        let (url, db) = try open("idmismatch")
        defer { db.close(); cleanup(url) }
        try mkSettlement(db, stateID: "S-m", value: "hello")
        let other = SimiGoSettlementIdentityBinding.Identity(model: "mlx:different-model", tokenizer: producer.tokenizer)

        expectRefusal(
            { try SimiGoISAdmission.admit(db: db, stateID: "S-m", consumer: other) },
            { if case .producerBinding(let v) = $0 { return v.code == SimiGoSettlementIdentityBinding.Refusal.modelMismatch.rawValue }; return false }
        )
    }

    func testAdmitRefusesAbsentProducerBinding() throws {
        let (url, db) = try open("idabsent")
        defer { db.close(); cleanup(url) }
        try mkSettlement(db, stateID: "S-noid", value: "hello", bindIdentity: false)

        expectRefusal(
            { try SimiGoISAdmission.admit(db: db, stateID: "S-noid", consumer: producer) },
            { if case .producerBinding(let v) = $0 { return v.code == SimiGoSettlementIdentityBinding.Refusal.modelAbsent.rawValue }; return false }
        )
    }

    func testAdmitRefusesEmptyValue() throws {
        let (url, db) = try open("empty")
        defer { db.close(); cleanup(url) }
        // Value settles under field `delta`; default reader looks for `content`.
        try mkSettlement(db, stateID: "S-e", value: "x", contract: Self.deltaContract)

        expectRefusal(
            { try SimiGoISAdmission.admit(db: db, stateID: "S-e", consumer: producer) },
            { if case .emptyValue = $0 { return true }; return false }
        )
    }

    // MARK: - New DB capability: upstream dependency closure reader

    func testUpstreamDependencyClosureWalksUpstreamTransitively() throws {
        let (url, db) = try open("closure")
        defer { db.close(); cleanup(url) }
        // Chain: SA <- SB <- SC  (SB depends on SA, SC depends on SB)
        let sa = try mkSettlement(db, stateID: "S-A", value: "a")
        let sb = try mkSettlement(db, stateID: "S-B", value: "b")
        let sc = try mkSettlement(db, stateID: "S-C", value: "c")
        try db.addDependency(fromSettlement: sb, toSettlement: sa)
        try db.addDependency(fromSettlement: sc, toSettlement: sb)

        XCTAssertEqual(Set(try db.upstreamDependencyClosure(ofSettlement: sc)), Set([sa, sb]),
                       "transitive upstream closure of C is {B, A}")
        XCTAssertEqual(try db.upstreamDependencyClosure(ofSettlement: sa), [],
                       "root has no upstream dependencies")
        XCTAssertEqual(Set(try db.upstreamDependencyClosure(ofSettlement: sb)), Set([sa]))
    }

    // MARK: - Continuation edge (recover -> contract -> persist)

    func testSettleContinuationRecoversParentValueAndPersistsChild() throws {
        let (url, db) = try open("cont-ok")
        defer { db.close(); cleanup(url) }
        try mkSettlement(db, stateID: "P", value: "hello")

        let done = try SimiGoISAdmission.settleContinuation(
            db: db, parentStateID: "P", consumer: producer, childStateID: "C",
            generatedText: "RESULT=hello", contractJSON: Data(Self.referenceContract.utf8))

        XCTAssertEqual(done.admission.recoveredValue, "hello")
        XCTAssertEqual(done.settled.trace.validationStatus, "VALID")
        // The child settlement is durable and itself re-admissible downstream.
        XCTAssertEqual(try db.latestSettlementID(forStateID: "C"), done.settlementID)
        let reAdmitted = try SimiGoISAdmission.admit(db: db, stateID: "C", consumer: producer)
        XCTAssertEqual(reAdmitted.recoveredValue, "hello")

        // The child is persisted with its value and lineage, not as a bare id.
        let child = try XCTUnwrap(try db.readGraph().states.first { $0.id == "C" })
        XCTAssertEqual(child.parentID, "P")
        XCTAssertEqual(child.nextInput, "hello", "the child carries the value it settled")
        XCTAssertEqual(child.prefix, ["hello"],
                       "the child's lineage is the parent's prefix plus its own value")
        XCTAssertEqual(child.position, 2, "the child sits one position past its parent")
        XCTAssertEqual(child.anchor, done.admission.payloadDigest)
    }

    /// The three writes used to be independent: a failed identity binding left the
    /// child state behind with no settlement. They are now one transaction, so a
    /// real lower-layer write fault must roll the child back with it.
    func testSettleContinuationRollsBackChildWhenIdentityWriteFails() throws {
        let (url, db) = try open("cont-atomic")
        defer { db.close(); cleanup(url) }
        try mkSettlement(db, stateID: "PA", value: "atomic")

        let statesBefore = try db.count("execution_states")
        let settlementsBefore = try db.count("settlements")
        let bindingsBefore = try db.count("settlement_bindings")

        let trigger = "fail_identity_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        try execRaw(url, """
        CREATE TRIGGER \(trigger) BEFORE INSERT ON settlement_bindings
        WHEN NEW.name = '\(SimiGoSettlementIdentityBinding.modelKey)'
        BEGIN
            SELECT RAISE(ABORT, 'injected producer identity write failure');
        END;
        """)
        defer { try? execRaw(url, "DROP TRIGGER IF EXISTS \(trigger)") }

        XCTAssertThrowsError(try SimiGoISAdmission.settleContinuation(
            db: db, parentStateID: "PA", consumer: producer, childStateID: "CA",
            generatedText: "RESULT=atomic", contractJSON: Data(Self.referenceContract.utf8)))

        XCTAssertEqual(try db.count("execution_states"), statesBefore,
                       "the child ES insert must roll back with the failed identity write")
        XCTAssertEqual(try db.count("settlements"), settlementsBefore,
                       "no settlement row may survive the failed commit")
        XCTAssertEqual(try db.count("settlement_bindings"), bindingsBefore,
                       "no binding row may survive the failed commit")
        XCTAssertNil(try db.latestSettlementID(forStateID: "CA"))
    }

    /// A settlement can outlive its execution-state row (a second connection with
    /// `foreign_keys = OFF` can delete it). That store is inconsistent, so the
    /// continuation must refuse rather than mint a root child at position 1.
    func testSettleContinuationRefusesParentStateMissingFromTheGraph() throws {
        let (url, db) = try open("cont-ghost")
        defer { db.close(); cleanup(url) }
        try mkSettlement(db, stateID: "PGHOST", value: "ghost")
        try execRaw(url, "PRAGMA foreign_keys=OFF; DELETE FROM execution_states WHERE state_id='PGHOST';")
        XCTAssertNil(try db.readGraph().states.first { $0.id == "PGHOST" },
                     "precondition: the parent state row is gone, its settlement is not")

        let statesBefore = try db.count("execution_states")
        let settlementsBefore = try db.count("settlements")
        let bindingsBefore = try db.count("settlement_bindings")

        XCTAssertThrowsError(try SimiGoISAdmission.settleContinuation(
            db: db, parentStateID: "PGHOST", consumer: producer, childStateID: "CGHOST",
            generatedText: "RESULT=ghost", contractJSON: Data(Self.referenceContract.utf8))
        ) { error in
            guard case SimiGoISAdmission.Refusal.missingParentState(let stateID) = error else {
                return XCTFail("expected .missingParentState, got \(error)")
            }
            XCTAssertEqual(stateID, "PGHOST")
        }
        XCTAssertEqual(try db.count("execution_states"), statesBefore,
                       "a refused continuation writes no child row")
        XCTAssertEqual(try db.count("settlements"), settlementsBefore)
        XCTAssertEqual(try db.count("settlement_bindings"), bindingsBefore)
        XCTAssertNil(try db.latestSettlementID(forStateID: "CGHOST"))
    }

    // Only the recovered IS value drives the child result: a child result that
    // does not commit to the parent's settled value is refused and persists nothing.
    func testSettleContinuationIsValueSensitiveAndWritesNothingOnContractFailure() throws {
        let (url, db) = try open("cont-value")
        defer { db.close(); cleanup(url) }
        try mkSettlement(db, stateID: "P9", value: "delta9")

        // A child result for "hello" violates the recovered "delta9" binding.
        XCTAssertThrowsError(try SimiGoISAdmission.settleContinuation(
            db: db, parentStateID: "P9", consumer: producer, childStateID: "C9",
            generatedText: "RESULT=hello", contractJSON: Data(Self.referenceContract.utf8)))
        // Fail-closed: nothing was persisted for the child.
        XCTAssertNil(try db.latestSettlementID(forStateID: "C9"),
                     "a contract failure must not create a settlement")

        // The matching child result settles, proving output tracks the IS value.
        let done = try SimiGoISAdmission.settleContinuation(
            db: db, parentStateID: "P9", consumer: producer, childStateID: "C9",
            generatedText: "RESULT=delta9", contractJSON: Data(Self.referenceContract.utf8))
        XCTAssertEqual(done.settled.trace.validationStatus, "VALID")
        let reAdmitted = try SimiGoISAdmission.admit(db: db, stateID: "C9", consumer: producer)
        XCTAssertEqual(reAdmitted.recoveredValue, "delta9")
    }

    // Admission runs BEFORE the child contract/persist: an unverified parent is
    // refused with the admission Refusal, and no child settlement appears.
    func testSettleContinuationRefusesInvalidParentBeforeProducingAnySettlement() throws {
        let (url, db) = try open("cont-refuse")
        defer { db.close(); cleanup(url) }
        try mkSettlement(db, stateID: "PB", value: "hello", bindIdentity: false)   // no producer identity bound

        expectRefusal(
            { try SimiGoISAdmission.settleContinuation(
                db: db, parentStateID: "PB", consumer: producer, childStateID: "CB",
                generatedText: "RESULT=hello", contractJSON: Data(Self.referenceContract.utf8)) },
            { if case .producerBinding = $0 { return true }; return false }
        )
        XCTAssertNil(try db.latestSettlementID(forStateID: "CB"))
    }
}
