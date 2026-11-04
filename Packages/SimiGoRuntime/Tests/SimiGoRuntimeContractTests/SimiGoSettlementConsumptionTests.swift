import Foundation
import SQLite3
import XCTest
@testable import SimiGoRuntimeContract

/// Stage B matrix: a settled unit is consumed into a NEW execution state with
/// zero model calls, or it is refused. Every case runs on a real SQLite store so
/// the transactional boundary, provenance rows and directory isolation are
/// exercised rather than simulated.
final class SimiGoSettlementConsumptionTests: XCTestCase {

    private let identity = SimiGoSettlementIdentityBinding.Identity(
        model: "model-a", tokenizer: "tokenizer-a")
    private let otherIdentity = SimiGoSettlementIdentityBinding.Identity(
        model: "model-b", tokenizer: "tokenizer-b")

    private struct Fixture {
        let directory: URL
        let dbURL: URL
        let rootURL: URL
        let db: SimiGoESISDatabase
    }

    private func makeFixture(_ name: String, files: [String: String] = ["notes.md": "alpha beta gamma"]) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-consumption-\(UUID().uuidString)-\(name)")
        let rootURL = directory.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        for (path, content) in files {
            try Data(content.utf8).write(to: rootURL.appendingPathComponent(path))
        }
        let dbURL = directory.appendingPathComponent("esis.sqlite3")
        let db = try SimiGoESISDatabase(url: dbURL)
        try db.runMigrations()
        try db.settleWorkRootContents(rootID: "work", rootURL: rootURL)
        return Fixture(directory: directory, dbURL: dbURL, rootURL: rootURL, db: db)
    }

    private func cleanup(_ fixture: Fixture) {
        fixture.db.close()
        try? FileManager.default.removeItem(at: fixture.directory)
    }

    /// A model-produced settlement that declares the exact-repeat reuse contract
    /// for `query` over the current root contents.
    @discardableResult
    private func makeSource(
        _ fixture: Fixture,
        value: String = "alpha beta gamma",
        query: String = "alpha facts",
        linkFile: Bool = false,
        stateID: String = UUID().uuidString
    ) throws -> String {
        let now = Date()
        try fixture.db.recordExecutionState(
            id: stateID, parentID: nil, modelIdentity: identity.model,
            position: 0, continuationID: UUID().uuidString,
            anchor: "source-anchor", lifecycle: "active", createdAt: now)
        let settled = try SimiGoSettlementAuthority.authorize(
            generatedText: value,
            contractJSON: SimiGoInformationLoop.chatResultContractJSON,
            verifiedBindings: [:], settledAt: now)
        let settlementID = try fixture.db.recordNativeSettlementWithIdentity(
            settled, stateID: stateID, identity: identity).uuidString
        if linkFile {
            try fixture.db.linkSettlementToExternalFile(
                settlementID: settlementID, binding: "content",
                rootID: "work", relativePath: "notes.md")
        }
        try fixture.db.declareSettlementReuseContract(
            settlementID: settlementID,
            contractID: SimiGoSettlementConsumption.Contract.contractID,
            demandClass: SimiGoSettlementConsumption.Contract.demandClass,
            contractVersion: SimiGoSettlementConsumption.Contract.version,
            query: query,
            rootIDs: ["work"],
            extractField: SimiGoSettlementConsumption.Contract.defaultExtractField)
        return settlementID
    }

    private func request(
        source: String,
        consumer: String = UUID().uuidString,
        query: String = "alpha facts",
        roots: [String] = ["work"],
        contractVersion: String = SimiGoSettlementConsumption.Contract.version,
        contractID: String = SimiGoSettlementConsumption.Contract.contractID,
        demandClass: String = SimiGoSettlementConsumption.Contract.demandClass,
        allowRecompute: Bool = false,
        identity: SimiGoSettlementIdentityBinding.Identity? = nil
    ) -> SimiGoSettlementConsumption.Request {
        let consumerIdentity = identity ?? self.identity
        return .init(
            sourceSettlementID: source,
            consumerStateID: consumer,
            consumerModelIdentity: consumerIdentity.model,
            consumerIdentity: consumerIdentity,
            contractID: contractID,
            demandClass: demandClass,
            contractVersion: contractVersion,
            query: query,
            rootIDs: roots,
            allowRecompute: allowRecompute)
    }

    private func rawExec(_ url: URL, _ sql: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            sqlite3_close(handle)
            throw SimiGoESISDatabase.DatabaseError.cannotOpen(url.path)
        }
        defer { sqlite3_close(handle) }
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &message) == SQLITE_OK else {
            let detail = message.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(message)
            throw SimiGoESISDatabase.DatabaseError.sql(detail)
        }
    }

    /// Attempt a write from a separate connection with no busy wait. While the
    /// consumption transaction holds `BEGIN IMMEDIATE`, this must fail BUSY.
    private func attemptImmediateWrite(_ url: URL, _ sql: String) -> Int32 {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK
        else { sqlite3_close(handle); return -1 }
        defer { sqlite3_close(handle) }
        sqlite3_exec(handle, "PRAGMA busy_timeout=0;", nil, nil, nil)
        return sqlite3_exec(handle, sql, nil, nil, nil)
    }

    private func consumed(_ outcome: SimiGoSettlementConsumption.Outcome) throws -> SimiGoSettlementConsumption.Consumed {
        guard case .consumed(let value) = outcome else {
            XCTFail("expected a consumption, got \(outcome)")
            throw SimiGoSettlementConsumption.Refusal.missingField("outcome")
        }
        return value
    }

    // MARK: - 1. exact match, zero model calls

    func testExactMatchConsumesWithZeroModelCalls() throws {
        let fixture = try makeFixture("match")
        defer { cleanup(fixture) }
        let source = try makeSource(fixture)

        let consumer = "consumer-1"
        let result = try consumed(SimiGoSettlementConsumption.consume(
            db: fixture.db, request: request(source: source, consumer: consumer)))

        XCTAssertFalse(result.reusedExisting)
        XCTAssertEqual(result.modelCalls, 0)
        XCTAssertEqual(result.sourceSettlementID, source)

        // The consumer ES carries the consumed value as its next input.
        let row = try XCTUnwrap(
            fixture.db.settlementAdmissionRow(settlementID: result.consumerSettlementID))
        XCTAssertEqual(row.stateID, consumer)
        XCTAssertEqual(row.validationStatus, "DERIVED_CONSUMPTION")
        XCTAssertEqual(row.validity, "valid")

        let receipt = try XCTUnwrap(
            fixture.db.settlementReceipt(result.consumerSettlementID))
        XCTAssertEqual(receipt.validationStatus, "DERIVED_CONSUMPTION")
        XCTAssertEqual(
            receipt.bindings[SimiGoSettlementIdentityBinding.consumerModelKey],
            SimiGoSettlementIdentityBinding.digest(identity.model))
        XCTAssertNil(receipt.bindings[SimiGoSettlementIdentityBinding.modelKey])
        XCTAssertNil(receipt.bindings[SimiGoKVBindingKey.poolKey])
        XCTAssertNil(receipt.bindings[SimiGoKVBindingKey.fingerprintKey])

        // Consumption is data, not log text.
        let stored = try XCTUnwrap(fixture.db.settlementConsumption(
            sourceSettlementID: source, consumerStateID: consumer,
            demandID: result.demandID))
        XCTAssertEqual(stored.modelCalls, 0)
        XCTAssertEqual(stored.consumerSettlementID, result.consumerSettlementID)
        XCTAssertEqual(try fixture.db.count("settlement_consumptions"), 1)

        // Dependency edge: the derived row's upstream closure contains the source.
        XCTAssertTrue(try fixture.db
            .upstreamDependencyClosure(ofSettlement: result.consumerSettlementID)
            .contains(source))
        XCTAssertEqual(try fixture.db.count("information_advancements"), 1)

        // Derived rows are valid but are excluded from model-output statistics.
        XCTAssertEqual(try fixture.db.validSettlementCount(), 1)
        XCTAssertEqual(try fixture.db.count("settlements"), 2)
    }

    // MARK: - 2. idempotent repeat

    func testRepeatedConsumptionIsIdempotent() throws {
        let fixture = try makeFixture("idempotent")
        defer { cleanup(fixture) }
        let source = try makeSource(fixture)
        let consumer = "consumer-repeat"
        let req = request(source: source, consumer: consumer)

        let first = try consumed(SimiGoSettlementConsumption.consume(db: fixture.db, request: req))
        let second = try consumed(SimiGoSettlementConsumption.consume(db: fixture.db, request: req))

        XCTAssertEqual(first.consumptionID, second.consumptionID)
        XCTAssertEqual(first.consumerSettlementID, second.consumerSettlementID)
        XCTAssertFalse(first.reusedExisting)
        XCTAssertTrue(second.reusedExisting)
        XCTAssertEqual(try fixture.db.count("settlement_consumptions"), 1)
        XCTAssertEqual(try fixture.db.count("settlements"), 2)
        XCTAssertEqual(try fixture.db.count("execution_states"), 2)
    }

    // MARK: - 3. query / roots / content change

    func testChangedQueryOrRootsOrContentDoesNotReuse() throws {
        let fixture = try makeFixture("changed")
        defer { cleanup(fixture) }
        let source = try makeSource(fixture)

        // Query change: the canonical basis changes with it.
        XCTAssertThrowsError(try SimiGoSettlementConsumption.consume(
            db: fixture.db,
            request: request(source: source, query: "different question")))
        // Explicit recompute is allowed to proceed without writing a consumption.
        let queryOutcome = try SimiGoSettlementConsumption.consume(
            db: fixture.db,
            request: request(source: source, query: "different question", allowRecompute: true))
        guard case .recompute = queryOutcome else {
            return XCTFail("expected recompute for changed query, got \(queryOutcome)")
        }

        // An extra (empty) root is a different demand even though it carries no files.
        XCTAssertThrowsError(try SimiGoSettlementConsumption.consume(
            db: fixture.db, request: request(source: source, roots: ["work", "other"])))

        // Content change: same query and root, different real digest.
        try Data("alpha beta gamma delta".utf8)
            .write(to: fixture.rootURL.appendingPathComponent("notes.md"))
        try fixture.db.settleWorkRootContents(rootID: "work", rootURL: fixture.rootURL)
        XCTAssertThrowsError(try SimiGoSettlementConsumption.consume(
            db: fixture.db, request: request(source: source)))
        let contentOutcome = try SimiGoSettlementConsumption.consume(
            db: fixture.db, request: request(source: source, allowRecompute: true))
        guard case .recompute = contentOutcome else {
            return XCTFail("expected recompute for changed content, got \(contentOutcome)")
        }

        XCTAssertEqual(try fixture.db.count("settlement_consumptions"), 0)
        XCTAssertEqual(try fixture.db.count("execution_states"), 1)
    }

    // MARK: - 4. missing / tampered / invalid source

    func testMissingTamperedOrInvalidSourceIsRefused() throws {
        let fixture = try makeFixture("refuse-source")
        defer { cleanup(fixture) }

        // No declaration at all is not consumable.
        let unknown = UUID().uuidString
        XCTAssertThrowsError(try SimiGoSettlementConsumption.consume(
            db: fixture.db, request: request(source: unknown))) { error in
            XCTAssertEqual(
                error as? SimiGoSettlementConsumption.Refusal,
                .contractUndeclared(settlementID: unknown))
        }
        XCTAssertThrowsError(try fixture.db.declareSettlementReuseContract(
            settlementID: unknown,
            contractID: SimiGoSettlementConsumption.Contract.contractID,
            demandClass: SimiGoSettlementConsumption.Contract.demandClass,
            contractVersion: SimiGoSettlementConsumption.Contract.version,
            query: "alpha facts", rootIDs: ["work"]))

        // Tampered recorded digest: admission's seal check runs before anything is written.
        let tampered = try makeSource(fixture)
        try rawExec(fixture.dbURL,
            "UPDATE settlements SET payload_digest='deadbeef' WHERE settlement_id='\(tampered)';")
        XCTAssertThrowsError(try SimiGoSettlementConsumption.consume(
            db: fixture.db, request: request(source: tampered))) { error in
            XCTAssertEqual(
                error as? SimiGoISAdmission.Refusal,
                .digestMismatch(settlementID: tampered))
        }

        // Invalidated source.
        let invalidated = try makeSource(fixture)
        _ = try fixture.db.invalidateSettlement(invalidated)
        XCTAssertThrowsError(try SimiGoSettlementConsumption.consume(
            db: fixture.db, request: request(source: invalidated))) { error in
            XCTAssertEqual(
                error as? SimiGoISAdmission.Refusal,
                .invalidated(settlementID: invalidated))
        }

        XCTAssertEqual(try fixture.db.count("settlement_consumptions"), 0)
    }

    // MARK: - 5. invalid upstream dependency

    func testInvalidUpstreamDependencyIsRefused() throws {
        let fixture = try makeFixture("refuse-dependency")
        defer { cleanup(fixture) }
        let upstream = try makeSource(fixture)
        let downstream = try makeSource(fixture)
        try fixture.db.addDependency(
            fromSettlement: downstream, toSettlement: upstream, kind: "depends")

        // Invalidate the dependency WITHOUT cascading, so the downstream row is
        // still locally valid: only the closure re-check can catch this.
        try rawExec(fixture.dbURL,
            "UPDATE settlements SET validity='invalid' WHERE settlement_id='\(upstream)';")
        XCTAssertEqual(try fixture.db.settlementValidity(downstream), "valid")

        XCTAssertThrowsError(try SimiGoSettlementConsumption.consume(
            db: fixture.db, request: request(source: downstream))) { error in
            XCTAssertEqual(
                error as? SimiGoISAdmission.Refusal,
                .dependencyInvalid(settlementID: downstream, dependency: upstream))
        }

        // A dependency edge to a settlement that does not exist is also refused.
        let orphan = try makeSource(fixture)
        let missing = UUID().uuidString
        try fixture.db.addDependency(
            fromSettlement: orphan, toSettlement: missing, kind: "depends")
        XCTAssertThrowsError(try SimiGoSettlementConsumption.consume(
            db: fixture.db, request: request(source: orphan))) { error in
            XCTAssertEqual(
                error as? SimiGoISAdmission.Refusal,
                .dependencyMissing(settlementID: orphan, dependency: missing))
        }

        XCTAssertEqual(try fixture.db.count("settlement_consumptions"), 0)
    }

    // MARK: - 6. identity / contract mismatch

    func testIdentityAndContractMismatchAreRefused() throws {
        let fixture = try makeFixture("refuse-contract")
        defer { cleanup(fixture) }
        let source = try makeSource(fixture)

        // A different engine may not inherit this settled value.
        XCTAssertThrowsError(try SimiGoSettlementConsumption.consume(
            db: fixture.db,
            request: request(source: source, identity: otherIdentity))) { error in
            guard case .producerBinding(let verdict)? =
                error as? SimiGoISAdmission.Refusal
            else { return XCTFail("expected producer binding refusal, got \(error)") }
            XCTAssertEqual(verdict.code, "SETTLEMENT_BINDING_MODEL_MISMATCH")
        }

        // Unsupported contract version is a refusal, not a recompute.
        XCTAssertThrowsError(try SimiGoSettlementConsumption.consume(
            db: fixture.db,
            request: request(source: source, contractVersion: "v99"))) { error in
            XCTAssertEqual(
                error as? SimiGoSettlementConsumption.Refusal,
                .contractMismatch(
                    field: "contract_version", expected: "v1", actual: "v99"))
        }

        // A demand class outside the contract is refused unless recompute is allowed.
        XCTAssertThrowsError(try SimiGoSettlementConsumption.consume(
            db: fixture.db,
            request: request(source: source, demandClass: "similar-text"))) { error in
            XCTAssertEqual(
                error as? SimiGoSettlementConsumption.Refusal,
                .contractNotCovered(demandClass: "similar-text", allowed: "exact-repeat"))
        }
        let recompute = try SimiGoSettlementConsumption.consume(
            db: fixture.db,
            request: request(source: source, demandClass: "similar-text", allowRecompute: true))
        guard case .recompute = recompute else {
            return XCTFail("expected recompute for uncovered demand class")
        }

        // Missing typed field.
        XCTAssertThrowsError(try SimiGoSettlementConsumption.consume(
            db: fixture.db, request: request(source: source, query: "  "))) { error in
            XCTAssertEqual(
                error as? SimiGoSettlementConsumption.Refusal,
                .missingField("query"))
        }

        XCTAssertEqual(try fixture.db.count("settlement_consumptions"), 0)
    }

    // MARK: - 7. race: invalidation cannot interleave; failure rolls back

    func testInvalidationCannotInterleaveAndRollbackLeavesNoRows() throws {
        let fixture = try makeFixture("race")
        defer { cleanup(fixture) }
        let source = try makeSource(fixture)

        var writeRC: Int32 = -1
        let consumer = "consumer-race"
        let result = try consumed(SimiGoSettlementConsumption.consume(
            db: fixture.db,
            request: request(source: source, consumer: consumer),
            afterAdmission: {
                // The consumption transaction already holds BEGIN IMMEDIATE. An
                // external invalidator must not be able to land between the
                // re-admission and the commit.
                writeRC = self.attemptImmediateWrite(
                    fixture.dbURL,
                    "UPDATE settlements SET validity='invalid' WHERE settlement_id='\(source)';")
            }))

        XCTAssertEqual(writeRC, SQLITE_BUSY)
        XCTAssertEqual(try fixture.db.settlementValidity(source), "valid")
        XCTAssertEqual(result.modelCalls, 0)
        XCTAssertEqual(try fixture.db.count("settlement_consumptions"), 1)

        // After commit the same external write succeeds — the lock, not a
        // permission rule, is what blocked it above.
        try rawExec(fixture.dbURL,
            "UPDATE settlements SET validity='invalid' WHERE settlement_id='\(source)';")
        XCTAssertEqual(try fixture.db.settlementValidity(source), "invalid")

        // A failure after admission rolls back every write.
        let secondSource = try makeSource(fixture)
        let failingConsumer = "consumer-rollback"
        struct InjectedFailure: Error {}
        XCTAssertThrowsError(try SimiGoSettlementConsumption.consume(
            db: fixture.db,
            request: request(source: secondSource, consumer: failingConsumer),
            afterAdmission: { throw InjectedFailure() }))
        XCTAssertEqual(try fixture.db.count("settlement_consumptions"), 1)
        XCTAssertNil(try fixture.db.latestSettlementID(forStateID: failingConsumer))
        XCTAssertEqual(
            try fixture.db.count("execution_states")
                - (try fixture.db.readGraph().states.count), 0)
    }

    // MARK: - 8. two directories stay isolated and create no KV files

    func testTwoDirectoriesStayIsolatedAndCreateNoKVFiles() throws {
        let first = try makeFixture("dir-a")
        let second = try makeFixture("dir-b")
        defer { cleanup(first); cleanup(second) }

        let filesBefore = directoryFiles(first.directory)
            .union(directoryFiles(second.directory))

        let sourceA = try makeSource(first)
        let sourceB = try makeSource(second)
        let consumerA = "consumer-a"
        let consumerB = "consumer-b"
        let resultA = try consumed(SimiGoSettlementConsumption.consume(
            db: first.db, request: request(source: sourceA, consumer: consumerA)))
        let resultB = try consumed(SimiGoSettlementConsumption.consume(
            db: second.db, request: request(source: sourceB, consumer: consumerB)))

        XCTAssertNotEqual(resultA.consumptionID, resultB.consumptionID)
        XCTAssertEqual(try first.db.count("settlement_consumptions"), 1)
        XCTAssertEqual(try second.db.count("settlement_consumptions"), 1)
        XCTAssertEqual(try first.db.settlementConsumptions(consumerStateID: consumerB).count, 0)
        XCTAssertEqual(try second.db.settlementConsumptions(consumerStateID: consumerA).count, 0)
        XCTAssertNil(try first.db.latestSettlementID(forStateID: consumerB))
        XCTAssertNil(try second.db.latestSettlementID(forStateID: consumerA))
        XCTAssertEqual(try first.db.upstreamDependencyClosure(
            ofSettlement: resultA.consumerSettlementID), [sourceA])
        XCTAssertEqual(try second.db.upstreamDependencyClosure(
            ofSettlement: resultB.consumerSettlementID), [sourceB])

        // Consumption writes rows only: neither directory gained a file, let
        // alone a prefix-pool or branch-checkpoint artifact.
        let filesAfter = directoryFiles(first.directory)
            .union(directoryFiles(second.directory))
        XCTAssertEqual(filesAfter, filesBefore)
        XCTAssertFalse(filesAfter.contains { $0.hasSuffix(".safetensors") })
    }

    private func directoryFiles(_ directory: URL) -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(
            atPath: directory.path)) ?? []
        return Set(names.filter {
            !$0.hasSuffix(".sqlite3") && !$0.hasSuffix("-wal") && !$0.hasSuffix("-shm")
        })
    }

    // MARK: - 9. file-driven demand uses the real content digest

    func testFileDrivenDemandUsesRealContentDigest() throws {
        let fixture = try makeFixture("digest")
        defer { cleanup(fixture) }
        let content = "alpha beta gamma"
        let expected = "alpha facts|work/notes.md="
            + NativeSHA256.hexDigest(Data(content.utf8))
        let expectedDigest = NativeSHA256.hexDigest(Data(expected.utf8))

        let canonical = try fixture.db.canonicalDemandInput(
            query: "alpha facts", rootIDs: ["work"])
        XCTAssertEqual(canonical.canonical, expected)
        XCTAssertEqual(canonical.digest, expectedDigest)
        XCTAssertNotEqual(
            canonical.digest,
            NativeSHA256.hexDigest(Data("alpha facts".utf8)))

        let source = try makeSource(fixture)
        _ = try consumed(SimiGoSettlementConsumption.consume(
            db: fixture.db, request: request(source: source)))

        // Same path and query, different bytes: a path-only or fixed-id key
        // would still match; the real content digest does not.
        try Data("alpha beta gamma epsilon".utf8)
            .write(to: fixture.rootURL.appendingPathComponent("notes.md"))
        try fixture.db.settleWorkRootContents(rootID: "work", rootURL: fixture.rootURL)
        let changed = try fixture.db.canonicalDemandInput(
            query: "alpha facts", rootIDs: ["work"])
        XCTAssertNotEqual(changed.digest, expectedDigest)

        XCTAssertThrowsError(try SimiGoSettlementConsumption.consume(
            db: fixture.db,
            request: request(source: source, consumer: "consumer-changed"))) { error in
            XCTAssertEqual(
                error as? SimiGoSettlementConsumption.Refusal,
                .canonicalInputMismatch(
                    expected: expectedDigest, actual: changed.digest))
        }
    }

    // MARK: - 10. derived rows are chainable, not generation

    func testDerivedSettlementIsChainableWithoutMasqueradingAsGeneration() throws {
        let fixture = try makeFixture("chain")
        defer { cleanup(fixture) }
        let source = try makeSource(fixture)

        let first = try consumed(SimiGoSettlementConsumption.consume(
            db: fixture.db, request: request(source: source, consumer: "consumer-2")))
        // Chain: the derived row itself declares exact-repeat for the same basis.
        try fixture.db.declareSettlementReuseContract(
            settlementID: first.consumerSettlementID,
            contractID: SimiGoSettlementConsumption.Contract.contractID,
            demandClass: SimiGoSettlementConsumption.Contract.demandClass,
            contractVersion: SimiGoSettlementConsumption.Contract.version,
            query: "alpha facts",
            rootIDs: ["work"])
        let second = try consumed(SimiGoSettlementConsumption.consume(
            db: fixture.db,
            request: request(source: first.consumerSettlementID, consumer: "consumer-3")))

        XCTAssertEqual(second.modelCalls, 0)
        let derived = try XCTUnwrap(
            fixture.db.settlementReceipt(second.consumerSettlementID))
        XCTAssertEqual(derived.validationStatus, "DERIVED_CONSUMPTION")
        XCTAssertFalse(derived.bindings.keys.contains(SimiGoSettlementIdentityBinding.modelKey))
        XCTAssertEqual(
            derived.bindings[SimiGoSettlementIdentityBinding.consumerModelKey],
            SimiGoSettlementIdentityBinding.digest(identity.model))

        // One model generation, two consumptions.
        XCTAssertEqual(try fixture.db.validSettlementCount(), 1)
        XCTAssertEqual(try fixture.db.count("settlement_consumptions"), 2)

        // The derived summaries keep their provenance chain.
        let summaries = try fixture.db.citableSettlementSummaries(sessionID: nil)
        let firstSummary = try XCTUnwrap(
            summaries.first { $0.settlementID == first.consumerSettlementID })
        XCTAssertEqual(firstSummary.derivationType, "DERIVED_CONSUMPTION")
        XCTAssertEqual(firstSummary.sourceSettlementID, source)
        let secondSummary = try XCTUnwrap(
            summaries.first { $0.settlementID == second.consumerSettlementID })
        XCTAssertEqual(secondSummary.sourceSettlementID, first.consumerSettlementID)

        // A derived summary is still citable, but marked derived in the context
        // a later turn would see.
        let loop = SimiGoInformationLoop(database: fixture.db)
        let resolution = try loop.resolve(.init(query: "alpha facts"))
        let derivedItems = resolution.hits.filter { $0.derivationType == "DERIVED_CONSUMPTION" }
        XCTAssertFalse(derivedItems.isEmpty)
        XCTAssertTrue(derivedItems.allSatisfy { $0.sourceSettlementID != nil })
        XCTAssertTrue(loop.contextBlock(resolution).contains("[derived:settlement:"))
    }
}

/// Mirrors `SimiGoSettlementKVBinding` key names without depending on its
/// internals: a derived consumption must carry no representation binding at all.
private enum SimiGoKVBindingKey {
    static let poolKey = "kv.pool_key"
    static let fingerprintKey = "kv.cache_fingerprint"
}
