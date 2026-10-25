import Foundation
import XCTest
@testable import SimiGoRuntimeContract

/// G2 — SQLite Information-Space BEHAVIORAL experiments (not just structural
/// integrity). Per the revised plan, passing `integrity_check=ok` is NOT enough:
/// the IS must carry TWO sources (external work files + agent sessions), link
/// settled information objects to their sources and to each other, and support
/// LOCAL dynamic invalidation — a source change flips only the affected
/// dependency closure to invalid while unrelated valid results survive. It must
/// also prove: repeat-scan idempotency, reconciliation of lost watcher events,
/// transaction atomicity, and data ownership (no external file bytes copied in).
///
/// These are the PRODUCT G2 acceptance experiments; they are distinct from any
/// same-named narrow experiment inside SimiGo-Lab.
final class SimiGoESISDatabaseG2Tests: XCTestCase {

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-g2-\(UUID().uuidString)-\(name).sqlite3")
    }
    private func cleanup(_ url: URL) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private static let contract =
        #"{"schema_version":"simigo.result-contract/v1","fields":{"content":{"pattern":"^RESULT=(.+)$","capture_group":1,"type":"string","normalize":"trim","nonempty":true}},"constraints":[{"kind":"equals_binding","field":"content","binding":"next_input"}]}"#

    /// Create a real gate-authorized settlement through the production authority
    /// path and record it as the write authority. Returns its settlement id.
    @discardableResult
    private func mkSettlement(_ db: SimiGoESISDatabase, stateID: String, value: String) throws -> String {
        try db.recordExecutionState(id: stateID, parentID: nil, modelIdentity: "m",
                                    position: 1, continuationID: "C", anchor: "a",
                                    lifecycle: "active", createdAt: Date())
        let settled = try SimiGoSettlementAuthority.authorize(
            generatedText: "RESULT=\(value)", contractJSON: Data(Self.contract.utf8),
            verifiedBindings: ["next_input": .string(value)]
        )
        XCTAssertEqual(settled.trace.validationStatus, "VALID")
        return try db.recordNativeSettlement(settled, stateID: stateID)
    }

    private func open(_ name: String) throws -> (URL, SimiGoESISDatabase) {
        let url = tempURL(name)
        let db = try SimiGoESISDatabase(url: url)
        try db.runMigrations()
        return (url, db)
    }

    // MARK: - Local invalidation preserves unrelated valid results

    func testG2LocalInvalidationOnlyAffectsClosurePreservesUnrelated() throws {
        let (url, db) = try open("local")
        defer { db.close(); cleanup(url) }

        try db.indexExternalFile(rootID: "work", relativePath: "report.md", kind: "md",
                                 size: 10, modifiedAt: nil, contentDigest: "d1")
        try db.indexExternalFile(rootID: "work", relativePath: "other.md", kind: "md",
                                 size: 10, modifiedAt: nil, contentDigest: "o1")
        let sa = try mkSettlement(db, stateID: "S-A", value: "alpha")
        let sb = try mkSettlement(db, stateID: "S-B", value: "beta")
        try db.linkSettlementToExternalFile(settlementID: sa, binding: "content",
                                            rootID: "work", relativePath: "report.md")
        try db.linkSettlementToExternalFile(settlementID: sb, binding: "content",
                                            rootID: "work", relativePath: "other.md")

        XCTAssertEqual(try db.validSettlementCount(), 2)

        // report.md changes; only SA's closure must go invalid, SB stays valid.
        let changed = try db.reindexExternalFile(rootID: "work", relativePath: "report.md",
                                                 kind: "md", size: 12, modifiedAt: nil,
                                                 contentDigest: "d2")
        XCTAssertTrue(changed)
        let invalidated = try db.invalidateSourceFile(rootID: "work", relativePath: "report.md")
        XCTAssertEqual(Set(invalidated), [sa])
        XCTAssertEqual(try db.settlementValidity(sa), "invalid")
        XCTAssertEqual(try db.settlementValidity(sb), "valid")
        XCTAssertEqual(try db.validSettlementCount(), 1, "unrelated valid result preserved")
    }

    // MARK: - Transitive dependency closure

    func testG2TransitiveDependencyClosureInvalidatesDownstream() throws {
        let (url, db) = try open("closure")
        defer { db.close(); cleanup(url) }

        try db.indexExternalFile(rootID: "work", relativePath: "src", kind: "txt",
                                 size: 1, modifiedAt: nil, contentDigest: "s1")
        let sa = try mkSettlement(db, stateID: "S-A", value: "a")   // bound to src
        let sb = try mkSettlement(db, stateID: "S-B", value: "b")   // depends on SA
        let sc = try mkSettlement(db, stateID: "S-C", value: "c")   // depends on SB
        let sd = try mkSettlement(db, stateID: "S-D", value: "d")   // unrelated
        try db.linkSettlementToExternalFile(settlementID: sa, binding: "content",
                                            rootID: "work", relativePath: "src")
        try db.addDependency(fromSettlement: sb, toSettlement: sa)
        try db.addDependency(fromSettlement: sc, toSettlement: sb)

        let invalidated = try db.invalidateSourceFile(rootID: "work", relativePath: "src")
        XCTAssertEqual(Set(invalidated), Set([sa, sb, sc]), "transitive closure A→B→C")
        XCTAssertEqual(try db.settlementValidity(sd), "valid", "unrelated D survives")
        XCTAssertEqual(try db.validSettlementCount(), 1)
    }

    // MARK: - Repeat-scan idempotency

    func testG2RepeatScanIdempotentNoInvalidationWhenUnchanged() throws {
        let (url, db) = try open("idempotent")
        defer { db.close(); cleanup(url) }

        try db.indexExternalFile(rootID: "work", relativePath: "f", kind: "txt",
                                 size: 5, modifiedAt: nil, contentDigest: "x")
        let s = try mkSettlement(db, stateID: "S", value: "v")
        try db.linkSettlementToExternalFile(settlementID: s, binding: "content",
                                            rootID: "work", relativePath: "f")

        // Re-scan the SAME digest: not a change → caller triggers no invalidation.
        let changedAgain = try db.reindexExternalFile(rootID: "work", relativePath: "f",
                                                      kind: "txt", size: 5, modifiedAt: nil,
                                                      contentDigest: "x")
        XCTAssertFalse(changedAgain, "unchanged digest must report no change")
        XCTAssertEqual(try db.settlementValidity(s), "valid", "no spurious invalidation")
        XCTAssertEqual(try db.count("external_files"), 1, "repeat scan does not duplicate rows")
        XCTAssertEqual(try db.count("settlements"), 1)
    }

    // MARK: - Reconciliation of lost watcher events

    func testG2ReconcileMissingWatcherEventInvalidatesRemovedFile() throws {
        let (url, db) = try open("reconcile")
        defer { db.close(); cleanup(url) }

        try db.indexExternalFile(rootID: "work", relativePath: "gone.md", kind: "md",
                                 size: 1, modifiedAt: nil, contentDigest: "g1")
        try db.indexExternalFile(rootID: "work", relativePath: "keep.md", kind: "md",
                                 size: 1, modifiedAt: nil, contentDigest: "k1")
        let sa = try mkSettlement(db, stateID: "S-A", value: "a")
        let sb = try mkSettlement(db, stateID: "S-B", value: "b")
        try db.linkSettlementToExternalFile(settlementID: sa, binding: "content",
                                            rootID: "work", relativePath: "gone.md")
        try db.linkSettlementToExternalFile(settlementID: sb, binding: "content",
                                            rootID: "work", relativePath: "keep.md")

        // A watcher event for gone.md was lost; a rescan sees only keep.md.
        let invalidated = try db.reconcileRoot(rootID: "work", seenRelativePaths: ["keep.md"])
        XCTAssertEqual(Set(invalidated), [sa])
        XCTAssertEqual(try db.settlementValidity(sa), "invalid")
        XCTAssertEqual(try db.settlementValidity(sb), "valid")
        XCTAssertTrue(try db.listExternalFiles(rootID: "work")
                        .contains(where: { $0.relativePath == "gone.md" && $0.status == "missing" }))
    }

    // MARK: - Transaction atomicity for local-update writes

    func testG2LocalUpdateWritesAreAtomicUnderFailure() throws {
        let (url, db) = try open("atomic")
        defer { db.close(); cleanup(url) }

        let before = try db.count("settlements")
        XCTAssertThrowsError(try db.transaction {
            try db.recordExecutionState(id: "S-X", parentID: nil, modelIdentity: "m",
                                        position: 1, continuationID: "C", anchor: "a",
                                        lifecycle: "active", createdAt: Date())
            struct Boom: Error {}
            throw Boom()
        })
        XCTAssertEqual(try db.count("execution_states"), 0,
                       "aborted transaction must leave no half-written authority")
        XCTAssertEqual(try db.count("settlements"), before)
    }

    // MARK: - Dual-source coexistence (work files + agent sessions)

    func testG2DualSourceCoexistenceWorkAndSession() throws {
        let (url, db) = try open("dualsource")
        defer { db.close(); cleanup(url) }

        // Source 1: an external work file.
        try db.indexExternalFile(rootID: "work", relativePath: "spec.md", kind: "md",
                                 size: 3, modifiedAt: nil, contentDigest: "w1")
        let sWork = try mkSettlement(db, stateID: "S-W", value: "w")
        try db.linkSettlementToExternalFile(settlementID: sWork, binding: "content",
                                            rootID: "work", relativePath: "spec.md")

        // Source 2: an agent session (no external file row), linked by root only.
        try db.upsertRoot(rootID: "sessroot", category: "session", displayName: nil,
                          locatorType: "path", status: "present")
        try db.indexAgentSession(sessionID: "sess-1", adapterID: "adapter-a",
                                 sourceRootID: "sessroot", metadataDigest: "m1")
        let sSess = try mkSettlement(db, stateID: "S-S", value: "s")
        let sDerived = try mkSettlement(db, stateID: "S-D", value: "d") // depends on the session-sourced one
        try db.addDependency(fromSettlement: sDerived, toSettlement: sSess)

        // Both sources coexist and are individually queryable.
        XCTAssertEqual(try db.listExternalFiles(rootID: "work").count, 1)
        XCTAssertEqual(try db.validSettlementCount(), 3)

        // Session version change → invalidate the session-sourced settlement;
        // its dependent cascades; the work-file settlement is untouched.
        let invalidated = try db.invalidateSettlement(sSess)
        XCTAssertEqual(Set(invalidated), Set([sSess, sDerived]))
        XCTAssertEqual(try db.settlementValidity(sWork), "valid", "other source preserved")
    }

    // MARK: - Data ownership: no external file bytes copied into the DB

    func testG2ExternalFileIndexStoresNoBytes() throws {
        let (url, db) = try open("ownership")
        defer { db.close(); cleanup(url) }

        try db.indexExternalFile(rootID: "work", relativePath: "a.md", kind: "md",
                                 size: 42, modifiedAt: nil, contentDigest: "digest-abc")
        XCTAssertFalse(try db.tableHasBlobColumn("external_files"),
                       "external file index must never hold file bytes")
        XCTAssertEqual(try db.externalFileDigest(rootID: "work", relativePath: "a.md"), "digest-abc")
    }
}
