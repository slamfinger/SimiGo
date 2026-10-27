import Foundation
import XCTest
@testable import SimiGoRuntimeContract

/// C-3 proof: the managed continuation pins the anchor, writes one declared
/// snapshot before the model call, and commits the final snapshot + settlement
/// + idempotency key in a single P2 transaction. Refusals never masquerade as
/// successes and never rewrite history.
final class SimiGoManagedContinuationTests: XCTestCase {
    private typealias Snapshot = SimiGoSnapshotContract
    private typealias Managed = SimiGoManagedContinuation
    private typealias Refusal = SimiGoManagedRefusal

    private enum TestError: Error { case notCommitted, notRefused }

    // MARK: - Fixtures

    private func makeDatabase(_ name: String) throws -> (SimiGoESISDatabase, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-managed-\(UUID().uuidString)-\(name).sqlite3")
        let db = try SimiGoESISDatabase(url: url)
        try db.runMigrations()
        addTeardownBlock {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        return (db, url)
    }

    private func settled(_ text: String) throws -> SimiGoSettlementAuthority.SettledResult {
        let contract = #"{"schema_version":"simigo.result-contract/v1","fields":{"secret":{"pattern":"^SECRET=(.+)$","type":"string"}},"constraints":[{"kind":"digest_equals_binding","field":"secret","binding":"secret_commitment"}]}"#
        return try SimiGoSettlementAuthority.authorize(
            generatedText: text,
            contractJSON: Data(contract.utf8),
            verifiedBindings: ["secret_commitment": .string("2b1a5d9f0a1183c966ce8325a252424579a625c1b2314654dd6aaebaf9c334a8")])
    }

    private func entry(_ content: String, path: String = "Sources/A.swift") throws -> Snapshot.DeclaredEntry {
        let data = Data(content.utf8)
        return try Snapshot.DeclaredEntry(
            fileRootID: "root-1", relativePath: path,
            sha256: Snapshot.sha256Hex(data), byteSource: .embedded(data),
            size: data.count, modified: "2026-10-27T00:00:00.000Z",
            statIdentity: .init(device: "1", inode: "2", modificationNanoseconds: "3"))
    }

    private func request(_ policy: SimiGoRecomputePolicy) -> Snapshot.Request {
        Snapshot.Request(
            kind: "chat", rootIDs: ["root-1"],
            contractJSON: Data(#"{"schema_version":"simigo.result-contract/v1","fields":{}}"#.utf8),
            recomputePolicy: policy.rawValue, idempotencyKey: "idem-1")
    }

    private func seedParent(_ db: SimiGoESISDatabase) throws {
        try db.recordExecutionState(
            id: "state-parent", parentID: nil, modelIdentity: "mlx:m",
            position: 1, continuationID: "C-parent", anchor: "a",
            lifecycle: "saved", createdAt: Date(timeIntervalSince1970: 1_790_000_000))
        _ = try db.recordNativeSettlementWithIdentity(
            try settled("SECRET=NORTH>EAST"), stateID: "state-parent",
            identity: .init(model: "mlx:m", tokenizer: "tok:t"))
    }

    private func config(
        anchor: String, policy: SimiGoRecomputePolicy, child: String, position: Int,
        key: String? = nil
    ) -> Managed.Config {
        Managed.Config(
            executionID: "exec-\(child)", attempt: 1, anchorStateID: anchor,
            policy: policy, snapshotRequest: request(policy),
            childStateID: child, childModelIdentity: "mlx:m", childPosition: position,
            identity: .init(model: "mlx:m", tokenizer: "tok:t"),
            capturedAt: Date(timeIntervalSince1970: 1_790_000_050),
            idempotencyKey: key)
    }

    private func capture(_ content: String) -> Managed.Capture {
        { _ in Managed.Captured(entries: [try self.entry(content)],
                                asOf: Date(timeIntervalSince1970: 1_790_000_050)) }
    }

    private func generate(_ content: String, calls: Counter) -> Managed.Generate {
        { declared in
            calls.value += 1
            return Managed.Generated(
                used: [Snapshot.UsedItem.from(declared: declared.entries[0], injectedAs: "context[0]")],
                settled: try self.settled("SECRET=NORTH>EAST"),
                nextInput: content)
        }
    }

    final class Counter: @unchecked Sendable { var value = 0 }

    private func committed(
        _ outcome: Managed.Outcome, file: StaticString = #filePath, line: UInt = #line
    ) throws -> Managed.Committed {
        guard case .committed(let value) = outcome else {
            XCTFail("expected committed, got \(outcome)", file: file, line: line)
            throw TestError.notCommitted
        }
        return value
    }

    private func refused(
        _ outcome: Managed.Outcome, file: StaticString = #filePath, line: UInt = #line
    ) throws -> (Refusal.Refusal, Bool) {
        guard case .refused(let refusal, let persisted) = outcome else {
            XCTFail("expected refused, got \(outcome)", file: file, line: line)
            throw TestError.notRefused
        }
        return (refusal, persisted)
    }

    // MARK: - Policy typing

    func testPolicyResolutionRejectsConflictAndUnsupportedValues() {
        XCTAssertEqual(
            try SimiGoRecomputePolicy.resolve(
                managedAnchorPresent: true, settlementConsumptionPresent: false, raw: nil),
            .never)
        XCTAssertEqual(
            try SimiGoRecomputePolicy.resolve(
                managedAnchorPresent: true, settlementConsumptionPresent: false,
                raw: "allow_safe_recompute"),
            .allowSafeRecompute)
        XCTAssertThrowsError(try SimiGoRecomputePolicy.resolve(
            managedAnchorPresent: true, settlementConsumptionPresent: true, raw: "never")
        ) { error in
            XCTAssertEqual((error as? Refusal.Refusal)?.cause, .recomputePolicyConflict)
            XCTAssertEqual(
                Refusal.external(error as! Refusal.Refusal, entry: .managedContinuation).status, 400)
        }
        XCTAssertThrowsError(try SimiGoRecomputePolicy.resolve(
            managedAnchorPresent: true, settlementConsumptionPresent: false, raw: "always")
        ) { error in
            XCTAssertEqual((error as? Refusal.Refusal)?.cause, .recomputePolicyInvalid)
        }
        // An unsupported value is reported before the two-entry conflict (§D3).
        XCTAssertThrowsError(try SimiGoRecomputePolicy.resolve(
            managedAnchorPresent: true, settlementConsumptionPresent: true, raw: "sometimes")
        ) { error in
            XCTAssertEqual((error as? Refusal.Refusal)?.cause, .recomputePolicyInvalid)
        }
        XCTAssertThrowsError(try SimiGoRecomputePolicy.resolve(
            managedAnchorPresent: false, settlementConsumptionPresent: false, raw: "never")
        ) { error in
            XCTAssertEqual((error as? Refusal.Refusal)?.cause, .recomputePolicyInvalid)
        }
        // Absence is not an entry: an anchor plus settlement_consumption request
        // without the policy field keeps its pre-C behavior instead of becoming
        // a 400 conflict.
        XCTAssertEqual(
            try SimiGoRecomputePolicy.resolve(
                managedAnchorPresent: true, settlementConsumptionPresent: true, raw: nil),
            .never)
    }

    func testFingerprintCoversSixDimensionsAndChangesWithPolicy() {
        let base = SimiGoIdempotencyFingerprint.make(
            anchorStateID: "s", anchorSettlementID: "t", declaredInputDigest: "d",
            contractJSON: Data("{}".utf8), rootIDs: ["b", "a"], policy: .never)
        XCTAssertEqual(base.components.count, 6)
        XCTAssertEqual(Set(base.components.keys), Set(SimiGoIdempotencyFingerprint.dimensions))

        let reordered = SimiGoIdempotencyFingerprint.make(
            anchorStateID: "s", anchorSettlementID: "t", declaredInputDigest: "d",
            contractJSON: Data("{}".utf8), rootIDs: ["a", "b"], policy: .never)
        XCTAssertEqual(base.digest, reordered.digest, "root order must not change the fingerprint")

        let allowed = SimiGoIdempotencyFingerprint.make(
            anchorStateID: "s", anchorSettlementID: "t", declaredInputDigest: "d",
            contractJSON: Data("{}".utf8), rootIDs: ["a", "b"], policy: .allowSafeRecompute)
        XCTAssertNotEqual(base.digest, allowed.digest)
    }

    // MARK: - Happy path

    func testCommitWritesDeclaredFinalAndSettlementTogether() async throws {
        let (db, _) = try makeDatabase("commit")
        try seedParent(db)
        let calls = Counter()

        let outcome = try await Managed.run(
            db: db,
            config: config(anchor: "state-parent", policy: .never, child: "child-1", position: 2),
            capture: capture("let a = 1\n"),
            generate: generate("let a = 1\n", calls: calls))

        let commit = try committed(outcome)
        XCTAssertEqual(calls.value, 1)
        XCTAssertEqual(commit.modelCalls, 1)
        XCTAssertEqual(commit.settlementsWritten, 1)
        XCTAssertEqual(commit.replayable, true)
        XCTAssertFalse(commit.reusedExecution)
        XCTAssertFalse(commit.recomputed)

        // The settlement points at the final snapshot, and the final snapshot
        // points back at the declared one.
        XCTAssertEqual(
            try db.settlementInputSnapshotObjectID(settlementID: commit.settlementID),
            commit.finalSnapshotID)
        let final = try Snapshot.Final.decode(try db.readObject(commit.finalSnapshotID))
        XCTAssertEqual(final.declaredSnapshotID, commit.declaredSnapshotID)
        XCTAssertTrue(final.replayable)
        XCTAssertNoThrow(try final.verify(
            against: Snapshot.Declared.decode(try db.readObject(commit.declaredSnapshotID))))

        // The idempotency key lives on the child state, not on a side table.
        XCTAssertEqual(try db.executionStateIdempotencyKey("child-1"), commit.fingerprint)
        XCTAssertNil(db.failureAudit(executionID: "exec-child-1"))
    }

    // MARK: - Policy `never`

    func testPolicyNeverRefusesWhenInputsChangedWithoutCallingTheModel() async throws {
        let (db, _) = try makeDatabase("never")
        try seedParent(db)

        let first = try committed(try await Managed.run(
            db: db, config: config(anchor: "state-parent", policy: .never, child: "child-1", position: 2),
            capture: capture("let a = 1\n"), generate: generate("let a = 1\n", calls: Counter())))

        let settlementsBefore = try db.count("settlements")
        let objectsBefore = try db.count("is_objects")
        let calls = Counter()

        let outcome = try await Managed.run(
            db: db, config: config(anchor: "child-1", policy: .never, child: "child-2", position: 3),
            capture: capture("let a = 2\n"), generate: generate("let a = 2\n", calls: calls))

        let (refusal, persisted) = try refused(outcome)
        XCTAssertEqual(refusal.cause, .snapshotInconsistent)
        XCTAssertEqual(refusal.phase, .p1)
        XCTAssertTrue(persisted)
        XCTAssertEqual(calls.value, 0, "a refusal before G must not run the model")
        XCTAssertEqual(try db.count("settlements"), settlementsBefore)
        XCTAssertEqual(try db.count("is_objects"), objectsBefore + 1,
                       "P1 refuses before S: only the audit object is written")
        XCTAssertNil(try db.executionStatePosition("child-2"))

        let audit = try XCTUnwrap(db.failureAudit(executionID: "exec-child-2"))
        XCTAssertEqual(audit.phase, .p1)
        XCTAssertEqual(audit.modelCalls, 0)
        XCTAssertEqual(audit.settlementsWritten, 0)
        XCTAssertNotNil(first.settlementID)

        // The external mapping keeps this out of the request-format bucket.
        XCTAssertNil(Refusal.external(refusal, entry: .managedContinuation).reasonCode)
        XCTAssertEqual(Refusal.external(refusal, entry: .managedContinuation).status, 422)
    }

    func testAllowSafeRecomputeProceedsOnChangedInputs() async throws {
        let (db, _) = try makeDatabase("recompute")
        try seedParent(db)
        _ = try await Managed.run(
            db: db, config: config(anchor: "state-parent", policy: .allowSafeRecompute,
                                   child: "child-1", position: 2),
            capture: capture("let a = 1\n"),
            generate: generate("let a = 1\n", calls: Counter()))

        let calls = Counter()
        let commit = try committed(try await Managed.run(
            db: db, config: config(anchor: "child-1", policy: .allowSafeRecompute,
                                   child: "child-2", position: 3),
            capture: capture("let a = 2\n"),
            generate: generate("let a = 2\n", calls: calls)))

        XCTAssertTrue(commit.recomputed)
        XCTAssertEqual(calls.value, 1)
        XCTAssertEqual(commit.settlementsWritten, 1)
        let final = try Snapshot.Final.decode(try db.readObject(commit.finalSnapshotID))
        XCTAssertEqual(final.declaredInputDigest.count, 64)
        XCTAssertEqual(final.recheck["policy"], "allow_safe_recompute")
    }

    // MARK: - Post-generation violations

    func testUsedItemOutsideDeclaredIsRefusedAfterTheModelCall() async throws {
        let (db, _) = try makeDatabase("used")
        try seedParent(db)
        let settlementsBefore = try db.count("settlements")
        let objectsBefore = try db.count("is_objects")

        let stranger = try entry("not captured\n", path: "Sources/B.swift")
        let outcome = try await Managed.run(
            db: db, config: config(anchor: "state-parent", policy: .never, child: "child-1", position: 2),
            capture: capture("let a = 1\n"),
            generate: { _ in
                Managed.Generated(
                    used: [Snapshot.UsedItem.from(declared: stranger, injectedAs: "context[1]")],
                    settled: try self.settled("SECRET=NORTH>EAST"),
                    nextInput: "out")
            })

        let (refusal, persisted) = try refused(outcome)
        XCTAssertEqual(refusal.cause, .snapshotUsedUndeclared)
        XCTAssertEqual(refusal.phase, .p2)
        XCTAssertTrue(persisted)
        XCTAssertEqual(try db.count("settlements"), settlementsBefore,
                       "a post-generation violation must not settle")
        XCTAssertNil(try db.executionStatePosition("child-1"))
        XCTAssertEqual(try db.count("is_objects"), objectsBefore + 2,
                       "the S-phase declared snapshot is retained plus one audit object")

        let audit = try XCTUnwrap(db.failureAudit(executionID: "exec-child-1"))
        XCTAssertEqual(audit.modelCalls, 1)
        XCTAssertEqual(audit.settlementsWritten, 0)
        let external = Refusal.external(refusal, entry: .managedContinuation)
        XCTAssertEqual(external.status, 422)
        XCTAssertNil(external.reasonCode)
        XCTAssertNotEqual(external.errorKind, Refusal.invalidRequestEntryKind)
    }

    func testAnchorAdvancingDuringGenerationIsRefusedAtCommit() async throws {
        let (db, _) = try makeDatabase("advanced")
        try seedParent(db)
        let settlementsBefore = try db.count("settlements")
        let calls = Counter()

        let outcome = try await Managed.run(
            db: db, config: config(anchor: "state-parent", policy: .never, child: "child-1", position: 2),
            capture: capture("let a = 1\n"),
            generate: { declared in
                calls.value += 1
                _ = try db.recordNativeSettlement(
                    try self.settled("SECRET=NORTH>EAST"), stateID: "state-parent")
                return Managed.Generated(
                    used: [Snapshot.UsedItem.from(declared: declared.entries[0], injectedAs: "context[0]")],
                    settled: try self.settled("SECRET=NORTH>EAST"),
                    nextInput: "out")
            })

        let (refusal, persisted) = try refused(outcome)
        XCTAssertEqual(refusal.cause, .invalidAnchor)
        XCTAssertEqual(refusal.phase, .p2)
        XCTAssertTrue(persisted)
        XCTAssertEqual(calls.value, 1)
        XCTAssertEqual(try db.count("settlements"), settlementsBefore + 1,
                       "only the externally written settlement exists")
        XCTAssertNil(try db.executionStatePosition("child-1"))
    }

    // MARK: - Idempotency

    func testSecondRunReusesTheExistingExecutionWithoutCallingTheModel() async throws {
        let (db, _) = try makeDatabase("idempotent")
        try seedParent(db)
        let calls = Counter()

        let first = try committed(try await Managed.run(
            db: db, config: config(anchor: "state-parent", policy: .never, child: "child-1", position: 2),
            capture: capture("let a = 1\n"), generate: generate("let a = 1\n", calls: calls)))

        let settlementsAfterFirst = try db.count("settlements")
        let second = try committed(try await Managed.run(
            db: db, config: config(anchor: "state-parent", policy: .never, child: "child-1", position: 2),
            capture: capture("let a = 1\n"), generate: generate("let a = 1\n", calls: calls)))

        XCTAssertTrue(second.reusedExecution)
        XCTAssertEqual(second.modelCalls, 0)
        XCTAssertEqual(second.settlementID, first.settlementID)
        XCTAssertEqual(calls.value, 1, "the model runs exactly once per fingerprint")
        XCTAssertEqual(try db.count("settlements"), settlementsAfterFirst)
        XCTAssertEqual(try db.failureAuditHistory(executionID: "exec-child-1").count, 0)
    }

    func testCallerKeyReplaysOnlyWhenTheFingerprintMatches() async throws {
        let (db, _) = try makeDatabase("caller-key")
        try seedParent(db)
        let calls = Counter()

        let first = try committed(try await Managed.run(
            db: db,
            config: config(anchor: "state-parent", policy: .never, child: "child-1",
                           position: 2, key: "caller-key-1"),
            capture: capture("let a = 1\n"), generate: generate("let a = 1\n", calls: calls)))

        let second = try committed(try await Managed.run(
            db: db,
            config: config(anchor: "state-parent", policy: .never, child: "child-2",
                           position: 2, key: "caller-key-1"),
            capture: capture("let a = 1\n"), generate: generate("let a = 1\n", calls: calls)))

        XCTAssertTrue(second.reusedExecution, "same key + same fingerprint is a replay")
        XCTAssertEqual(second.childStateID, first.childStateID)
        XCTAssertEqual(second.settlementID, first.settlementID)
        XCTAssertEqual(calls.value, 1)
        XCTAssertNil(try db.executionStatePosition("child-2"))
    }

    func testCallerKeyWithDifferentInputsConflictsInsteadOfReplaying() async throws {
        let (db, _) = try makeDatabase("caller-key-conflict")
        try seedParent(db)
        let calls = Counter()

        let first = try committed(try await Managed.run(
            db: db,
            config: config(anchor: "state-parent", policy: .never, child: "child-1",
                           position: 2, key: "caller-key-1"),
            capture: capture("let a = 1\n"), generate: generate("let a = 1\n", calls: calls)))
        let settlementsAfterFirst = try db.count("settlements")

        let outcome = try await Managed.run(
            db: db,
            config: config(anchor: "state-parent", policy: .never, child: "child-2",
                           position: 2, key: "caller-key-1"),
            capture: capture("let a = 2\n"), generate: generate("let a = 2\n", calls: calls))

        let (refusal, persisted) = try refused(outcome)
        XCTAssertEqual(refusal.cause, .idempotencyConflict)
        XCTAssertEqual(refusal.phase, .p2)
        XCTAssertTrue(persisted)
        XCTAssertEqual(calls.value, 2, "a reused key with new inputs still ran the model")
        XCTAssertEqual(try db.count("settlements"), settlementsAfterFirst,
                       "the losing attempt wrote no settlement")
        XCTAssertNil(try db.executionStatePosition("child-2"))
        XCTAssertEqual(try db.executionStateIdempotencyKey("child-1"), "caller-key-1")
        XCTAssertEqual(try db.latestSettlementID(forStateID: "child-1"), first.settlementID)

        let audit = try XCTUnwrap(db.failureAudit(executionID: "exec-child-2"))
        XCTAssertEqual(audit.modelCalls, 1)
        XCTAssertEqual(audit.settlementsWritten, 0)
    }
}
