import Foundation
import SQLite3
import XCTest
@testable import SimiGoRuntimeContract

/// P6: a refusal is a typed conclusion, not a command.
///
/// Every refusal path — managed continuation (P1 and P2) and settlement
/// consumption — must leave the four execution tables (`settlements`,
/// `execution_states`, `information_advancements`, `settlement_consumptions`)
/// untouched. The failure audit is the only permitted write: appended after
/// rollback, best-effort, terminal-result-neutral, and it records the
/// attempt's side-effect counts faithfully — `settlementsWritten` is always 0
/// on a refusal; `modelCalls` is 0 for a pre-model refusal and the honest
/// count for a post-model one (the model did run; nothing it produced may
/// settle).
final class RefusalSideEffectTests: XCTestCase {

    private typealias Snapshot = SnapshotContract
    private typealias Managed = ManagedContinuation
    private typealias Refusal = ManagedRefusal

    private enum TestError: Error { case notCommitted, notRefused }

    /// The four execution tables a refusal must never touch.
    private let executionTables = [
        "settlements", "execution_states",
        "information_advancements", "settlement_consumptions"
    ]

    private func rowCounts(_ db: ESISDatabase) throws -> [String: Int] {
        var counts: [String: Int] = [:]
        for table in executionTables {
            counts[table] = try db.count(table)
        }
        return counts
    }

    // MARK: - Managed-path fixtures (mirror ManagedContinuationTests)

    private func makeDatabase(_ name: String) throws -> (ESISDatabase, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-refusal-\(UUID().uuidString)-\(name).sqlite3")
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        addTeardownBlock {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: URL(fileURLWithPath: url.path + suffix))
            }
        }
        return (db, url)
    }

    private func settled(_ text: String) throws -> SettlementAuthority.SettledResult {
        let contract = #"{"schema_version":"simigo.result-contract/v1","fields":{"secret":{"pattern":"^SECRET=(.+)$","type":"string"}},"constraints":[{"kind":"digest_equals_binding","field":"secret","binding":"secret_commitment"}]}"#
        return try SettlementAuthority.authorize(
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

    private func managedRequest(_ policy: RecomputePolicy) -> Snapshot.Request {
        Snapshot.Request(
            kind: "chat", rootIDs: ["root-1"],
            contractJSON: Data(#"{"schema_version":"simigo.result-contract/v1","fields":{}}"#.utf8),
            recomputePolicy: policy.rawValue, idempotencyKey: "idem-1")
    }

    private func seedParent(_ db: ESISDatabase) throws {
        try db.recordExecutionState(
            id: "state-parent", parentID: nil, modelIdentity: "mlx:m",
            position: 1, continuationID: "C-parent", anchor: "a",
            lifecycle: "saved", createdAt: Date(timeIntervalSince1970: 1_790_000_000))
        _ = try db.recordNativeSettlementWithIdentity(
            try settled("SECRET=NORTH>EAST"), stateID: "state-parent",
            identity: .init(model: "mlx:m", tokenizer: "tok:t"))
    }

    private func config(
        anchor: String, policy: RecomputePolicy, child: String, position: Int,
        key: String? = nil
    ) -> Managed.Config {
        Managed.Config(
            executionID: "exec-\(child)", attempt: 1, anchorStateID: anchor,
            policy: policy, snapshotRequest: managedRequest(policy),
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

    private func committed(_ outcome: Managed.Outcome) throws -> Managed.Committed {
        guard case .committed(let value) = outcome else { throw TestError.notCommitted }
        return value
    }

    private func refused(_ outcome: Managed.Outcome) throws -> (Refusal.Refusal, Bool) {
        guard case .refused(let refusal, let persisted) = outcome else {
            throw TestError.notRefused
        }
        return (refusal, persisted)
    }

    // MARK: - A1: P1 refusal, before the model

    func testManagedP1RefusalLeavesExecutionTablesUntouchedAndAuditsZeroSideEffects() async throws {
        let (db, _) = try makeDatabase("p1")
        try seedParent(db)
        _ = try committed(try await Managed.run(
            db: db, config: config(anchor: "state-parent", policy: .never, child: "child-1", position: 2),
            capture: capture("let a = 1\n"), generate: generate("let a = 1\n", calls: Counter())))

        let before = try rowCounts(db)
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

        XCTAssertEqual(try rowCounts(db), before,
                       "a P1 refusal must not touch any execution table")
        XCTAssertEqual(try db.count("is_objects"), objectsBefore + 1,
                       "the audit object is the only permitted write")
        XCTAssertNil(try db.executionStatePosition("child-2"))

        let audit = try XCTUnwrap(db.failureAudit(executionID: "exec-child-2"))
        XCTAssertEqual(audit.phase, .p1)
        XCTAssertEqual(audit.modelCalls, 0)
        XCTAssertEqual(audit.settlementsWritten, 0)
    }

    // MARK: - A2: P2 refusal after the model ran (used-undeclared)

    func testManagedPostModelRefusalLeavesExecutionTablesUntouchedAndAuditsFaithfully() async throws {
        let (db, _) = try makeDatabase("p2-used")
        try seedParent(db)
        let before = try rowCounts(db)
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

        XCTAssertEqual(try rowCounts(db), before,
                       "a post-generation violation must not touch any execution table")
        XCTAssertEqual(try db.count("is_objects"), objectsBefore + 2,
                       "the S-phase declared snapshot is retained plus one audit object")
        XCTAssertNil(try db.executionStatePosition("child-1"))

        let audit = try XCTUnwrap(db.failureAudit(executionID: "exec-child-1"))
        XCTAssertEqual(audit.modelCalls, 1, "the model ran; the audit records it faithfully")
        XCTAssertEqual(audit.settlementsWritten, 0, "but nothing it produced may settle")
    }

    // MARK: - A3: idempotency conflict (caller key reused with new inputs)

    func testManagedIdempotencyConflictLeavesExecutionTablesUntouched() async throws {
        let (db, _) = try makeDatabase("conflict")
        try seedParent(db)
        let calls = Counter()
        let first = try committed(try await Managed.run(
            db: db,
            config: config(anchor: "state-parent", policy: .never, child: "child-1",
                           position: 2, key: "caller-key-1"),
            capture: capture("let a = 1\n"), generate: generate("let a = 1\n", calls: calls)))
        let before = try rowCounts(db)
        let objectsBefore = try db.count("is_objects")

        let outcome = try await Managed.run(
            db: db,
            config: config(anchor: "state-parent", policy: .never, child: "child-2",
                           position: 2, key: "caller-key-1"),
            capture: capture("let a = 2\n"), generate: generate("let a = 2\n", calls: calls))

        let (refusal, persisted) = try refused(outcome)
        XCTAssertEqual(refusal.cause, .idempotencyConflict)
        XCTAssertEqual(refusal.phase, .p2)
        XCTAssertTrue(persisted)

        XCTAssertEqual(try rowCounts(db), before)
        XCTAssertEqual(try db.executionStateIdempotencyKey("child-1"), "caller-key-1")
        XCTAssertEqual(try db.latestSettlementID(forStateID: "child-1"), first.settlementID)
        XCTAssertNil(try db.executionStatePosition("child-2"))
        XCTAssertEqual(try db.count("is_objects"), objectsBefore + 2,
                       "the declared snapshot was written in S, then one audit object")

        let audit = try XCTUnwrap(db.failureAudit(executionID: "exec-child-2"))
        XCTAssertEqual(audit.modelCalls, 1)
        XCTAssertEqual(audit.settlementsWritten, 0)
    }

    // MARK: - B: consumption refusals (no audit object; pure rollback)

    private let identity = SettlementIdentityBinding.Identity(
        model: "model-a", tokenizer: "tokenizer-a")

    private struct ConsumFixture {
        let directory: URL
        let dbURL: URL
        let rootURL: URL
        let db: ESISDatabase
    }

    private func makeFixture(
        _ name: String, files: [String: String] = ["notes.md": "alpha beta gamma"]
    ) throws -> ConsumFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-refusal-consume-\(UUID().uuidString)-\(name)")
        let rootURL = directory.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        for (path, content) in files {
            try Data(content.utf8).write(to: rootURL.appendingPathComponent(path))
        }
        let dbURL = directory.appendingPathComponent("esis.sqlite3")
        let db = try ESISDatabase(url: dbURL)
        try db.runMigrations()
        try db.settleWorkRootContents(rootID: "work", rootURL: rootURL)
        return ConsumFixture(directory: directory, dbURL: dbURL, rootURL: rootURL, db: db)
    }

    private func cleanup(_ fixture: ConsumFixture) {
        fixture.db.close()
        try? FileManager.default.removeItem(at: fixture.directory)
    }

    @discardableResult
    private func makeSource(
        _ fixture: ConsumFixture,
        query: String = "alpha facts",
        stateID: String = UUID().uuidString
    ) throws -> String {
        let now = Date()
        try fixture.db.recordExecutionState(
            id: stateID, parentID: nil, modelIdentity: identity.model,
            position: 0, continuationID: UUID().uuidString,
            anchor: "source-anchor", lifecycle: "active", createdAt: now)
        let settled = try SettlementAuthority.authorize(
            generatedText: "alpha beta gamma",
            contractJSON: InformationLoop.chatResultContractJSON,
            verifiedBindings: [:], settledAt: now)
        let settlementID = try fixture.db.recordNativeSettlementWithIdentity(
            settled, stateID: stateID, identity: identity).uuidString
        try fixture.db.declareSettlementReuseContract(
            settlementID: settlementID,
            contractID: SettlementConsumption.Contract.contractID,
            demandClass: SettlementConsumption.Contract.demandClass,
            contractVersion: SettlementConsumption.Contract.version,
            query: query,
            rootIDs: ["work"],
            extractField: SettlementConsumption.Contract.defaultExtractField,
            requiredConsumerIdentity: nil)
        return settlementID
    }

    private func consumptionRequest(
        source: String,
        consumer: String,
        query: String = "alpha facts",
        roots: [String] = ["work"],
        contractVersion: String = SettlementConsumption.Contract.version
    ) -> SettlementConsumption.Request {
        .init(
            sourceSettlementID: source,
            consumerStateID: consumer,
            consumerModelIdentity: identity.model,
            consumerIdentity: identity,
            contractID: SettlementConsumption.Contract.contractID,
            demandClass: SettlementConsumption.Contract.demandClass,
            contractVersion: contractVersion,
            query: query,
            rootIDs: roots,
            allowRecompute: false)
    }

    private func rawExec(_ url: URL, _ sql: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            sqlite3_close(handle)
            throw ESISDatabase.DatabaseError.cannotOpen(url.path)
        }
        defer { sqlite3_close(handle) }
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &message) == SQLITE_OK else {
            let detail = message.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(message)
            throw ESISDatabase.DatabaseError.sql(detail)
        }
    }

    func testConsumptionRefusalsLeaveExecutionTablesUntouched() throws {
        let fixture = try makeFixture("consume-refusals")
        defer { cleanup(fixture) }

        // Sources are created first; the snapshots start after the last
        // creation, so the refusals below are the only candidate writers.
        let tampered = try makeSource(fixture, stateID: "src-tampered")
        let invalidated = try makeSource(fixture, stateID: "src-invalidated")
        let upstream = try makeSource(fixture, stateID: "src-upstream")
        let downstream = try makeSource(fixture, stateID: "src-downstream")
        try fixture.db.addDependency(
            fromSettlement: downstream, toSettlement: upstream, kind: "depends")
        let orphan = try makeSource(fixture, stateID: "src-orphan")
        let missing = UUID().uuidString
        try fixture.db.addDependency(
            fromSettlement: orphan, toSettlement: missing, kind: "depends")
        let declared = try makeSource(fixture, stateID: "src-declared")

        let before = try rowCounts(fixture.db)
        let objectsBefore = try fixture.db.count("is_objects")

        // 1. Tampered recorded digest: the admission seal check refuses before
        //    anything is written.
        try rawExec(fixture.dbURL,
            "UPDATE settlements SET payload_digest='deadbeef' WHERE settlement_id='\(tampered)';")
        XCTAssertThrowsError(try SettlementConsumption.consume(
            db: fixture.db, request: consumptionRequest(source: tampered, consumer: "c-tampered")))

        // 2. Invalidated source.
        _ = try fixture.db.invalidateSettlement(invalidated)
        XCTAssertThrowsError(try SettlementConsumption.consume(
            db: fixture.db, request: consumptionRequest(source: invalidated, consumer: "c-invalidated")))

        // 3. The closure catches a locally-valid source over an invalidated
        //    upstream.
        try rawExec(fixture.dbURL,
            "INSERT INTO settlement_validity_events(settlement_id, validity, cause, recorded_at) VALUES('\(upstream)','invalid','test',datetime('now'));")
        XCTAssertEqual(try fixture.db.settlementValidity(downstream), "valid")
        XCTAssertThrowsError(try SettlementConsumption.consume(
            db: fixture.db, request: consumptionRequest(source: downstream, consumer: "c-downstream")))

        // 4. A dependency edge to a settlement that does not exist.
        XCTAssertThrowsError(try SettlementConsumption.consume(
            db: fixture.db, request: consumptionRequest(source: orphan, consumer: "c-orphan")))

        // 5. No declaration at all.
        XCTAssertThrowsError(try SettlementConsumption.consume(
            db: fixture.db, request: consumptionRequest(source: missing, consumer: "c-undeclared")))

        // 6. Unsupported contract version.
        XCTAssertThrowsError(try SettlementConsumption.consume(
            db: fixture.db,
            request: consumptionRequest(source: declared, consumer: "c-version",
                                        contractVersion: "v99")))

        XCTAssertEqual(try rowCounts(fixture.db), before,
                       "consumption refusals must not touch any execution table")
        XCTAssertEqual(try fixture.db.count("is_objects"), objectsBefore,
                       "the consume path writes no audit object: it has no execution attempt to audit")
    }
}
