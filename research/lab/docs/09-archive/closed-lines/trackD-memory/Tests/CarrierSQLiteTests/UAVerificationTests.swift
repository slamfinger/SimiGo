import Foundation
import CryptoKit
import Testing
import CarrierInterface
@testable import CarrierSQLite

// U-A code-level VERIFICATION suite (Human audit round 2, six focus
// areas). These are verification instruments over the EXISTING mechanisms
// — no new mechanisms. Each test names the audit focus it verifies.

@Suite
struct UAVerificationTests {
    private func freshFactory() -> SQLiteCarrierFactory {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccvs01-uaverify-\(UUID().uuidString)", isDirectory: true)
        return SQLiteCarrierFactory(rootURL: root)
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func makeFileCarrier(
        _ ops: SQLiteUnifiedCarrierOperations, _ name: String
    ) async throws -> UACarrier {
        let (carrier, outcome) = try await ops.createCarrier(
            kind: .file, locatorScheme: "file", locatorValue: "\(name)/1",
            actorID: "agent-A", operationID: "op-verify-create-\(name)")
        #expect(outcome == .applied)
        return carrier
    }

    // MARK: Focus 1 — carrier_id through the full chain (no information-scoped residue)

    @Test
    func focus1LegacyWritesCannotEraseCarrierScopedRows() async throws {
        let b = try freshFactory().make()
        let ops = b.operations
        let carrier = try await makeFileCarrier(ops, "f1legacy")
        let info = CarrierInformationID(rawValue: "f1legacy-info")
        // UA carrier-scoped row.
        try await ops.indexDocument(
            informationID: info, carrierID: carrier.carrierID,
            revisionID: CarrierRevisionID(rawValue: "f1legacy-rev"),
            title: "ua", text: "carrier scoped searchable text")
        // Legacy runtime-path upsert of the SAME information (NULL scope).
        try await b.runtime.composition.search.upsert(CarrierSearchDocument(
            informationID: info,
            revisionID: CarrierRevisionID(rawValue: "f1legacy-rev"),
            title: "legacy", text: "legacy searchable text"))
        // UA scoped row must survive the legacy upsert (UA-IF-3b).
        let uaHits = try await ops.searchScoped(
            "carrier scoped", carrierID: carrier.carrierID)
        #expect(uaHits.count == 1)
        // Legacy scoped-by-construction reads see the legacy row only via
        // the unscoped neutral surface; U-A scoped queries NEVER see
        // NULL-carrier rows (focus 5).
        let legacyHits = try await ops.searchScoped("legacy searchable", carrierID: carrier.carrierID)
        #expect(legacyHits.isEmpty)
        // Unscoped (carrierID: nil) reads see legacy rows with an EMPTY
        // carrier scope — the explicit legacy boundary (focus 5); they are
        // never attributed to a carrier.
        let allScoped = try await ops.searchScoped("searchable", carrierID: nil)
        #expect(allScoped.contains { $0.carrierID == carrier.carrierID })
        #expect(allScoped.contains { $0.carrierID.isEmpty })
        // Legacy delete of the information must also not touch UA rows.
        try await b.runtime.composition.search.delete(informationID: info)
        #expect(try await ops.searchScoped(
            "carrier scoped", carrierID: carrier.carrierID).count == 1)
        // And the legacy row is gone (its own scope was respected).
        let legacyAfterDelete = try await ops.searchScoped("legacy searchable", carrierID: nil)
        #expect(legacyAfterDelete.isEmpty)
    }

    @Test
    func focus1RebuildAndStalenessArePairScoped() async throws {
        let ops = try freshFactory().make().operations
        let a = try await makeFileCarrier(ops, "pair-a")
        let b = try await ops.createCarrier(
            kind: .session, locatorScheme: nil, locatorValue: nil,
            actorID: "agent-B", operationID: "op-pair-b").carrier
        let info = CarrierInformationID(rawValue: "pair-info")
        _ = try await ops.recordMapping(
            informationID: info, carrierID: a.carrierID, recordID: "r-a",
            representationID: nil, fromVersion: nil,
            actorID: "agent-A", operationID: "op-pair-map-a")
        _ = try await ops.recordMapping(
            informationID: info, carrierID: b.carrierID, recordID: "r-b",
            representationID: nil, fromVersion: nil,
            actorID: "agent-B", operationID: "op-pair-map-b")
        try await ops.indexDocument(
            informationID: info, carrierID: a.carrierID,
            revisionID: CarrierRevisionID(rawValue: "pair-rev-a"),
            title: nil, text: "pair coverage text alpha")
        try await ops.indexDocument(
            informationID: info, carrierID: b.carrierID,
            revisionID: CarrierRevisionID(rawValue: "pair-rev-b"),
            title: nil, text: "pair coverage text beta")
        // Advance ONLY carrier A: staleness must flag exactly the (A, info)
        // pair, never the (B, info) pair.
        _ = try await ops.recordMapping(
            informationID: info, carrierID: a.carrierID, recordID: "r-a2",
            representationID: nil, fromVersion: nil,
            actorID: "agent-A", operationID: "op-pair-advance-a")
        let stale = try await ops.indexStaleness()
        #expect(stale.contains { $0.carrierID == a.carrierID && $0.informationID == "pair-info" })
        #expect(!stale.contains { $0.carrierID == b.carrierID })
        // Full rebuild restores both pairs (build rows keyed per pair).
        _ = try await ops.rebuildIndex(documents: [
            (info, a.carrierID, CarrierRevisionID(rawValue: "pair-rev-a"), nil,
             "pair coverage text alpha"),
            (info, b.carrierID, CarrierRevisionID(rawValue: "pair-rev-b"), nil,
             "pair coverage text beta")
        ])
        #expect(try await ops.indexStaleness().isEmpty)
        let aHits = try await ops.searchScoped("alpha", carrierID: a.carrierID)
        let bHits = try await ops.searchScoped("beta", carrierID: b.carrierID)
        #expect(aHits.count == 1 && bHits.count == 1)
    }

    // MARK: Focus 2 — FTS v2 migration satisfies CC-7 (no free clean PASS)

    @Test
    func focus2MigrationDiscardsDerivedStateWithoutTouchingAuthority() async throws {
        let factory = freshFactory()
        let b = try factory.make()
        let ops = b.operations
        let carrier = try await makeFileCarrier(ops, "mig")
        let info = CarrierInformationID(rawValue: "mig-info")
        _ = try await ops.recordMapping(
            informationID: info, carrierID: carrier.carrierID, recordID: "r-mig",
            representationID: nil, fromVersion: nil,
            actorID: "agent-A", operationID: "op-mig-map")
        try await ops.indexDocument(
            informationID: info, carrierID: carrier.carrierID,
            revisionID: CarrierRevisionID(rawValue: "mig-rev"),
            title: nil, text: "migration coverage text")
        let fingerprintBefore = try await ops.authorityFingerprint()
        // Manually degrade the FTS to the OLD (pre-UA-IF-3) schema, as a
        // database created before the correction would look.
        try await b.core.runOutsideTransaction("DROP TABLE search_fts")
        try await b.core.runOutsideTransaction(
            "CREATE VIRTUAL TABLE search_fts USING fts5(information_id UNINDEXED, revision_id UNINDEXED, title, text)")
        try await b.core.run(
            "INSERT INTO search_fts(information_id, revision_id, title, text) VALUES (?,?,?,?)",
            bind: {
                $0.bindText(1, "mig-info")
                $0.bindText(2, "mig-rev")
                $0.bindTextOpt(3, nil)
                $0.bindText(4, "old schema searchable text")
            })
        // Reopen: the migration must detect the stale schema, drop it, and
        // recreate the v2 table EMPTY.
        let reopened = try factory.make()
        let fingerprintAfter = try await reopened.operations.authorityFingerprint()
        // (a) authority unchanged by the migration.
        #expect(fingerprintAfter == fingerprintBefore)
        // (b) old derived state fully discarded — no ghost rows.
        let ghost = try await reopened.operations.searchScoped("old schema", carrierID: nil)
        #expect(ghost.isEmpty)
        // (c) an EMPTY index must NOT pass a rebuild-compare against the
        // promised coverage — migration grants no free clean PASS.
        let promised: Set<String> = ["mig-info|\(carrier.carrierID)"]
        let actualBeforeRebuild = Set(try await reopened.operations.searchScoped(
            "migration coverage", carrierID: nil).map { "\($0.informationID)|\($0.carrierID)" })
        #expect(actualBeforeRebuild != promised)
        // (d) rebuild from the authority-derived document restores exactly
        // the promised coverage.
        _ = try await reopened.operations.rebuildIndex(documents: [
            (info, carrier.carrierID, CarrierRevisionID(rawValue: "mig-rev"), nil,
             "migration coverage text")
        ])
        let actualAfterRebuild = Set(try await reopened.operations.searchScoped(
            "migration coverage", carrierID: nil).map { "\($0.informationID)|\($0.carrierID)" })
        #expect(actualAfterRebuild == promised)
        #expect(try await reopened.operations.indexStaleness().isEmpty)
    }

    // MARK: Focus 1/A — legacy DESTRUCTIVE operations (clear/rebuild) ownership

    @Test
    func focus1ALegacyClearAndRebuildNeverEraseCarrierScopedRows() async throws {
        let b = try freshFactory().make()
        let ops = b.operations
        let a = try await makeFileCarrier(ops, "own-a")
        let c = try await ops.createCarrier(
            kind: .session, locatorScheme: nil, locatorValue: nil,
            actorID: "agent-B", operationID: "op-own-b").carrier
        let infoA = CarrierInformationID(rawValue: "own-info-a")
        let infoB = CarrierInformationID(rawValue: "own-info-b")
        try await ops.indexDocument(
            informationID: infoA, carrierID: a.carrierID,
            revisionID: CarrierRevisionID(rawValue: "own-rev-a"),
            title: nil, text: "ua scoped text alpha")
        try await ops.indexDocument(
            informationID: infoB, carrierID: c.carrierID,
            revisionID: CarrierRevisionID(rawValue: "own-rev-b"),
            title: nil, text: "ua scoped text beta")
        func uaRowsAlive(_ label: String) async throws {
            #expect(try await ops.searchScoped(
                "ua scoped text alpha", carrierID: a.carrierID).count == 1, "\(label): alpha row")
            #expect(try await ops.searchScoped(
                "ua scoped text beta", carrierID: c.carrierID).count == 1, "\(label): beta row")
        }
        // Legacy upsert + delete (already NULL-scoped) — A/B remain.
        let infoL = CarrierInformationID(rawValue: "own-info-legacy")
        try await b.runtime.composition.search.upsert(CarrierSearchDocument(
            informationID: infoL,
            revisionID: CarrierRevisionID(rawValue: "own-rev-l"),
            title: nil, text: "legacy text one"))
        try await uaRowsAlive("after legacy upsert")
        try await b.runtime.composition.search.delete(informationID: infoL)
        try await uaRowsAlive("after legacy delete")
        // Legacy CLEAR — must not erase U-A rows (the audited blocker).
        try await b.runtime.composition.search.clear()
        try await uaRowsAlive("after legacy clear")
        // Legacy REBUILD — replaces only the legacy portion; A/B remain and
        // the legacy portion becomes exactly the rebuilt result.
        try await b.runtime.composition.search.rebuild(with: [
            CarrierSearchDocument(
                informationID: infoL,
                revisionID: CarrierRevisionID(rawValue: "own-rev-l2"),
                title: nil, text: "legacy text rebuilt")
        ])
        try await uaRowsAlive("after legacy rebuild")
        let legacyPortion = try await ops.searchScoped("legacy text", carrierID: nil)
            .filter { $0.carrierID.isEmpty }
        #expect(legacyPortion.count == 1
                && legacyPortion.first?.informationID == "own-info-legacy")
        // UA rebuild (mirror symmetry): owns only carrier-scoped rows —
        // the legacy portion survives a U-A rebuild.
        _ = try await ops.rebuildIndex(documents: [
            (infoA, a.carrierID, CarrierRevisionID(rawValue: "own-rev-a"), nil,
             "ua scoped text alpha"),
            (infoB, c.carrierID, CarrierRevisionID(rawValue: "own-rev-b"), nil,
             "ua scoped text beta")
        ])
        try await uaRowsAlive("after UA rebuild")
        let legacyAfterUARebuild = try await ops.searchScoped("legacy text rebuilt", carrierID: nil)
            .filter { $0.carrierID.isEmpty }
        #expect(legacyAfterUARebuild.count == 1)
    }

    // MARK: Focus 3 — replay boundary (six fields; effects exactly bounded)

    @Test
    func focus3IdempotentReplayChangesNothingButItsOwnAttemptRecord() async throws {
        let b = try freshFactory().make()
        let ops = b.operations
        let carrier = try await makeFileCarrier(ops, "replay")
        let payload = Data("immutable replay bytes".utf8)
        _ = try await ops.reviseCarrierWithRepresentation(
            carrierID: carrier.carrierID,
            informationID: CarrierInformationID(rawValue: "replay-info"),
            revisionID: CarrierRevisionID(rawValue: "replay-rev"),
            representationID: CarrierRepresentationID(rawValue: "R-replay"),
            payload: payload, mediaType: "text/plain",
            expectedRevision: carrier.revision, fromVersion: nil,
            actorID: "agent-A", operationID: "op-replay-first")
        // Snapshot of every object the replay must leave untouched.
        let repsBefore = try await b.representations.representations(
            for: CarrierInformationID(rawValue: "replay-info"), revisionID: nil)
        let contentBefore = try await b.representations.content(
            CarrierRepresentationID(rawValue: "R-replay"))
        let carrierBefore = try await ops.carrier(carrierID: carrier.carrierID)
        let mappingsBefore = try await ops.mappings()
        let fingerprintBefore = try await ops.authorityFingerprint()
        // Idempotent duplicate registration: ALL SIX immutable properties
        // identical (representation_id is the lookup key; information_id,
        // revision_id, digest, byte_count, media_type are compared).
        let (after, outcome) = try await ops.reviseCarrierWithRepresentation(
            carrierID: carrier.carrierID,
            informationID: CarrierInformationID(rawValue: "replay-info"),
            revisionID: CarrierRevisionID(rawValue: "replay-rev"),
            representationID: CarrierRepresentationID(rawValue: "R-replay"),
            payload: payload, mediaType: "text/plain",
            expectedRevision: carrierBefore?.revision ?? 0, fromVersion: nil,
            actorID: "agent-A", operationID: "op-replay-second")
        #expect(outcome == .replayed)
        #expect(after.revision == carrierBefore?.revision)
        // No new representation row; stored object unchanged.
        let repsAfter = try await b.representations.representations(
            for: CarrierInformationID(rawValue: "replay-info"), revisionID: nil)
        #expect(repsAfter.count == repsBefore.count)
        let contentAfter = try await b.representations.content(
            CarrierRepresentationID(rawValue: "R-replay"))
        #expect(contentAfter?.payload.bytes == contentBefore?.payload.bytes)
        #expect(contentAfter?.representation.digest == contentBefore?.representation.digest)
        #expect(contentAfter?.representation.createdAt == contentBefore?.representation.createdAt)
        // Authority bytes unchanged (entity file identical).
        #expect(contentAfter?.payload.bytes == payload)
        // Mapping rows unchanged.
        #expect(try await ops.mappings() == mappingsBefore)
        // The ONLY delta is the appended attempt record (operation ledger
        // is append-only: the no-op attempt's own provenance). Object
        // provenance (the original APPLIED registration row) is singular.
        let ledger = try await ops.operationLedger()
        let replayRows = ledger.filter { $0.operationID == "op-replay-second" }
        #expect(replayRows.count == 1 && replayRows.first?.outcome == .replayed)
        let appliedRowsForR = ledger.filter {
            $0.subjectID == "R-replay" && $0.outcome == .applied
                && $0.kind == "CARRIER_REPRESENTATION_REVISE"
        }
        #expect(appliedRowsForR.count == 1)
        // Fingerprint delta = the appended ledger row only; verified via
        // the ledger row count (fingerprint covers ledger by design).
        #expect(try await ops.authorityFingerprint() != fingerprintBefore)
        // Strictness: same R + same digest but a DIFFERENT media_type is a
        // typed conflict — the check is six-field, not digest-only.
        await #expect(throws: UAOperationError.conflictingDuplicateRepresentation("R-replay")) {
            try await ops.reviseCarrierWithRepresentation(
                carrierID: carrier.carrierID,
                informationID: CarrierInformationID(rawValue: "replay-info"),
                revisionID: CarrierRevisionID(rawValue: "replay-rev"),
                representationID: CarrierRepresentationID(rawValue: "R-replay"),
                payload: payload, mediaType: "application/json",
                expectedRevision: carrierBefore?.revision ?? 0, fromVersion: nil,
                actorID: "agent-A", operationID: "op-replay-mediatype")
        }
    }

    // MARK: Focus 4 — CONFLICT evidence is committed OUTSIDE the rolled-back work

    @Test
    func focus4ConflictEvidenceSurvivesAndStateContinues() async throws {
        let ops = try freshFactory().make().operations
        let carrier = try await makeFileCarrier(ops, "atomconf")
        let payload1 = Data("atomic conflict bytes 1".utf8)
        _ = try await ops.reviseCarrierWithRepresentation(
            carrierID: carrier.carrierID,
            informationID: CarrierInformationID(rawValue: "atomconf-info"),
            revisionID: CarrierRevisionID(rawValue: "atomconf-rev-1"),
            representationID: CarrierRepresentationID(rawValue: "R-atom"),
            payload: payload1, mediaType: nil,
            expectedRevision: carrier.revision, fromVersion: nil,
            actorID: "agent-A", operationID: "op-atom-1")
        // Typed conflict: R-atom with different bytes.
        await #expect(throws: UAOperationError.conflictingDuplicateRepresentation("R-atom")) {
            try await ops.reviseCarrierWithRepresentation(
                carrierID: carrier.carrierID,
                informationID: CarrierInformationID(rawValue: "atomconf-info"),
                revisionID: CarrierRevisionID(rawValue: "atomconf-rev-x"),
                representationID: CarrierRepresentationID(rawValue: "R-atom"),
                payload: Data("different".utf8), mediaType: nil,
                expectedRevision: 1, fromVersion: nil,
                actorID: "agent-A", operationID: "op-atom-conflict")
        }
        // The CONFLICT evidence row was committed in its OWN transaction —
        // it exists AFTER the throw (first-round bug pattern: evidence
        // written inside the transaction that then rolled back).
        let ledger = try await ops.operationLedger()
        #expect(ledger.contains { $0.operationID == "op-atom-conflict" && $0.outcome == .conflict })
        // Carrier state unchanged by the conflict; a NEW valid revise still
        // proceeds (the state machine continues).
        let payload2 = Data("atomic conflict bytes 2".utf8)
        let (revised, outcome) = try await ops.reviseCarrierWithRepresentation(
            carrierID: carrier.carrierID,
            informationID: CarrierInformationID(rawValue: "atomconf-info"),
            revisionID: CarrierRevisionID(rawValue: "atomconf-rev-2"),
            representationID: CarrierRepresentationID(rawValue: "R-atom-2"),
            payload: payload2, mediaType: nil,
            expectedRevision: 1, fromVersion: nil,
            actorID: "agent-A", operationID: "op-atom-2")
        #expect(outcome == .applied && revised.revision == 2)
        #expect(try await ops.danglingProvenanceCount() == 0)
    }

    // MARK: Focus 6 — concurrency battery (composition: actor-owned single connection)

    @Test
    func focus6RebuildAndScopedIndexInterleaveLegally() async throws {
        let ops = try freshFactory().make().operations
        let a = try await makeFileCarrier(ops, "conc-a")
        let b = try await ops.createCarrier(
            kind: .session, locatorScheme: nil, locatorValue: nil,
            actorID: "agent-B", operationID: "op-conc-b").carrier
        let infoA = CarrierInformationID(rawValue: "conc-info-a")
        let infoB = CarrierInformationID(rawValue: "conc-info-b")
        _ = try await ops.recordMapping(
            informationID: infoA, carrierID: a.carrierID, recordID: "r",
            representationID: nil, fromVersion: nil,
            actorID: "agent-A", operationID: "op-conc-map-a")
        _ = try await ops.recordMapping(
            informationID: infoB, carrierID: b.carrierID, recordID: "r",
            representationID: nil, fromVersion: nil,
            actorID: "agent-B", operationID: "op-conc-map-b")
        // The rebuild writes v1 for pair (A, infoA); the racing
        // indexDocument writes v2 for the SAME pair — the final content
        // must be EXACTLY ONE of them, decided by the linearization.
        let docA_v1 = (informationID: infoA, carrierID: a.carrierID,
                       revisionID: CarrierRevisionID(rawValue: "conc-rev-a"),
                       title: nil as String?, text: "alpha v1 concurrent" as String)
        let docA_v2 = (informationID: infoA, carrierID: a.carrierID,
                       revisionID: CarrierRevisionID(rawValue: "conc-rev-a-v2"),
                       title: nil as String?, text: "alpha v2 concurrent" as String)
        let docB = (informationID: infoB, carrierID: b.carrierID,
                    revisionID: CarrierRevisionID(rawValue: "conc-rev-b"),
                    title: nil as String?, text: "beta concurrent text" as String)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await ops.indexDocument(
                informationID: docA_v2.informationID, carrierID: docA_v2.carrierID,
                revisionID: docA_v2.revisionID, title: docA_v2.title, text: docA_v2.text) }
            group.addTask { _ = try await ops.rebuildIndex(documents: [docA_v1, docB]) }
            group.addTask { try await ops.indexDocument(
                informationID: docB.informationID, carrierID: docB.carrierID,
                revisionID: docB.revisionID, title: docB.title, text: docB.text) }
            try await group.waitForAll()
        }
        let aHits = try await ops.searchScoped("alpha", carrierID: a.carrierID)
        #expect(aHits.count == 1)
        #expect(aHits.first?.informationID == "conc-info-a")
        // The surviving revision distinguishes the linearization: rebuild-
        // last -> "conc-rev-a"; index-last -> "conc-rev-a-v2". Exactly one
        // row survives either way.
        let alphaVariants = try await ops.searchScoped("concurrent", carrierID: a.carrierID)
        #expect(alphaVariants.count == 1)
        #expect(["conc-rev-a", "conc-rev-a-v2"].contains(alphaVariants.first?.revisionID ?? ""))
        let bHits = try await ops.searchScoped("beta", carrierID: b.carrierID)
        #expect(bHits.count == 1)
        // Strict staleness close-out: a final full rebuild over the current
        // pairs MUST clear staleness completely (decidable invariant, no
        // weak "count <= 2" allowance).
        _ = try await ops.rebuildIndex(documents: [
            (infoA, a.carrierID, CarrierRevisionID(rawValue: "conc-rev-a"), nil,
             "alpha v1 concurrent"),
            (infoB, b.carrierID, CarrierRevisionID(rawValue: "conc-rev-b"), nil,
             "beta concurrent text")
        ])
        #expect(try await ops.indexStaleness().isEmpty)
    }

    @Test
    func focus6ConcurrentSameInformationDifferentCarriers() async throws {
        let ops = try freshFactory().make().operations
        let a = try await makeFileCarrier(ops, "sameinfo-a")
        let b = try await ops.createCarrier(
            kind: .session, locatorScheme: nil, locatorValue: nil,
            actorID: "agent-B", operationID: "op-sameinfo-b").carrier
        let info = CarrierInformationID(rawValue: "sameinfo-info")
        _ = try await ops.recordMapping(
            informationID: info, carrierID: a.carrierID, recordID: "r-a",
            representationID: nil, fromVersion: nil,
            actorID: "agent-A", operationID: "op-sameinfo-map-a")
        _ = try await ops.recordMapping(
            informationID: info, carrierID: b.carrierID, recordID: "r-b",
            representationID: nil, fromVersion: nil,
            actorID: "agent-B", operationID: "op-sameinfo-map-b")
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await ops.indexDocument(
                    informationID: info, carrierID: a.carrierID,
                    revisionID: CarrierRevisionID(rawValue: "sameinfo-rev-a"),
                    title: nil, text: "from carrier a")
            }
            group.addTask {
                try await ops.indexDocument(
                    informationID: info, carrierID: b.carrierID,
                    revisionID: CarrierRevisionID(rawValue: "sameinfo-rev-b"),
                    title: nil, text: "from carrier b")
            }
            try await group.waitForAll()
        }
        // BOTH carrier-scoped representations coexist (no cross-erase).
        #expect(try await ops.searchScoped("from carrier a", carrierID: a.carrierID).count == 1)
        #expect(try await ops.searchScoped("from carrier b", carrierID: b.carrierID).count == 1)
    }

    @Test
    func focus6ConflictRacingNormalRevisionSettlesCleanly() async throws {
        let ops = try freshFactory().make().operations
        let carrier = try await makeFileCarrier(ops, "race-conf")
        let payload1 = Data("race bytes one".utf8)
        _ = try await ops.reviseCarrierWithRepresentation(
            carrierID: carrier.carrierID,
            informationID: CarrierInformationID(rawValue: "race-info"),
            revisionID: CarrierRevisionID(rawValue: "race-rev-1"),
            representationID: CarrierRepresentationID(rawValue: "R-race"),
            payload: payload1, mediaType: nil,
            expectedRevision: carrier.revision, fromVersion: nil,
            actorID: "agent-A", operationID: "op-race-1")
        var conflictThrown = false
        var reviseApplied = false
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                // Conflicting duplicate registration of R-race.
                do {
                    _ = try await ops.reviseCarrierWithRepresentation(
                        carrierID: carrier.carrierID,
                        informationID: CarrierInformationID(rawValue: "race-info"),
                        revisionID: CarrierRevisionID(rawValue: "race-rev-1"),
                        representationID: CarrierRepresentationID(rawValue: "R-race"),
                        payload: Data("race bytes two".utf8), mediaType: nil,
                        expectedRevision: 1, fromVersion: nil,
                        actorID: "agent-A", operationID: "op-race-conflict")
                } catch is UAOperationError {
                    conflictThrown = true
                }
            }
            group.addTask {
                // Normal revision by a different representation.
                let current = try await ops.carrier(carrierID: carrier.carrierID)
                _ = try await ops.reviseCarrierWithRepresentation(
                    carrierID: carrier.carrierID,
                    informationID: CarrierInformationID(rawValue: "race-info"),
                    revisionID: CarrierRevisionID(rawValue: "race-rev-2"),
                    representationID: CarrierRepresentationID(rawValue: "R-race-2"),
                    payload: Data("race bytes normal".utf8), mediaType: nil,
                    expectedRevision: current?.revision ?? 0, fromVersion: nil,
                    actorID: "agent-B", operationID: "op-race-normal")
                reviseApplied = true
            }
            try await group.waitForAll()
        }
        #expect(conflictThrown && reviseApplied)
        // Exactly one bump landed (the normal revision); the conflict left
        // no state change; provenance complete.
        let after = try await ops.carrier(carrierID: carrier.carrierID)
        #expect(after?.revision == 2)
        let ledger = try await ops.operationLedger()
        #expect(ledger.contains { $0.operationID == "op-race-conflict" && $0.outcome == .conflict })
        #expect(ledger.contains { $0.operationID == "op-race-normal" && $0.outcome == .applied })
        #expect(try await ops.danglingProvenanceCount() == 0)
    }

    @Test
    func focus6ReplayRacingNewOperation() async throws {
        let ops = try freshFactory().make().operations
        let carrier = try await ops.createCarrier(
            kind: .session, locatorScheme: nil, locatorValue: nil,
            actorID: "agent-A", operationID: "op-f6-create").carrier
        let committed = try await appendEvent(
            ops, carrier.carrierID, kind: "NOTE", payload: "committed before race",
            occurredAt: 100, actor: "agent-A", op: "op-f6-known", ref: "ref-f6-known")
        #expect(committed.outcome == .applied)
        let before = try await ops.consistentSnapshot(carrierID: carrier.carrierID)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                // Retry of the committed operation: returns the RECORDED
                // terminal outcome (round-4 ruling).
                let replay = try await ops.appendSessionEvent(
                    carrierID: carrier.carrierID, kind: "NOTE",
                    payload: Data("committed before race".utf8),
                    occurredAt: Date(timeIntervalSince1970: 100),
                    actorID: "agent-A", operationID: "op-f6-known",
                    clientRef: "ref-f6-known")
                #expect(replay.outcome == .applied)
            }
            group.addTask {
                _ = try await appendEvent(
                    ops, carrier.carrierID, kind: "NOTE", payload: "fresh during race",
                    occurredAt: 101, actor: "agent-B", op: "op-f6-new", ref: "ref-f6-new")
            }
            try await group.waitForAll()
        }
        let after = try await ops.consistentSnapshot(carrierID: carrier.carrierID)
        #expect(after.events.count == before.events.count + 1)
        #expect(after.events.map(\.sequence) == Array(0..<after.events.count))
        #expect(try await ops.danglingProvenanceCount() == 0)
    }

    @Test
    func focus6SearchDuringRebuildSeesOnlyOldCompleteOrNewComplete() async throws {
        let ops = try freshFactory().make().operations
        let a = try await makeFileCarrier(ops, "sr-a")
        let c = try await ops.createCarrier(
            kind: .session, locatorScheme: nil, locatorValue: nil,
            actorID: "agent-B", operationID: "op-sr-b").carrier
        let info1 = CarrierInformationID(rawValue: "sr-info-1")
        let info2 = CarrierInformationID(rawValue: "sr-info-2")
        let info3 = CarrierInformationID(rawValue: "sr-info-3")
        _ = try await ops.recordMapping(
            informationID: info1, carrierID: a.carrierID, recordID: "r1",
            representationID: nil, fromVersion: nil,
            actorID: "agent-A", operationID: "op-sr-map-1")
        _ = try await ops.recordMapping(
            informationID: info2, carrierID: c.carrierID, recordID: "r2",
            representationID: nil, fromVersion: nil,
            actorID: "agent-B", operationID: "op-sr-map-2")
        _ = try await ops.recordMapping(
            informationID: info3, carrierID: c.carrierID, recordID: "r3",
            representationID: nil, fromVersion: nil,
            actorID: "agent-B", operationID: "op-sr-map-3")
        // BEFORE state: {I1 x A, I2 x C}. AFTER state: {I1 x A, I3 x C}.
        // The two sets are distinguishable (I2 swapped for I3) and BOTH
        // documents share the probe term so one MATCH query observes the
        // whole snapshot.
        try await ops.indexDocument(
            informationID: info1, carrierID: a.carrierID,
            revisionID: CarrierRevisionID(rawValue: "sr-rev-1"),
            title: nil, text: "oracle shared old one")
        try await ops.indexDocument(
            informationID: info2, carrierID: c.carrierID,
            revisionID: CarrierRevisionID(rawValue: "sr-rev-2"),
            title: nil, text: "oracle shared old two")
        let before: Set<String> = ["sr-info-1|\(a.carrierID)", "sr-info-2|\(c.carrierID)"]
        let after: Set<String> = ["sr-info-1|\(a.carrierID)", "sr-info-3|\(c.carrierID)"]
        let rebuildDocs: [(informationID: CarrierInformationID, carrierID: String,
                           revisionID: CarrierRevisionID, title: String?, text: String)] = [
            (info1, a.carrierID, CarrierRevisionID(rawValue: "sr-rev-1"), nil,
             "oracle shared new one"),
            (info3, c.carrierID, CarrierRevisionID(rawValue: "sr-rev-3"), nil,
             "oracle shared new two")
        ]
        try await withThrowingTaskGroup(of: Set<String>.self) { group in
            group.addTask { _ = try await ops.rebuildIndex(documents: rebuildDocs)
                // The rebuild task's own post-condition is the AFTER set —
                // returned so the homogeneous group can collect it without
                // polluting the observation oracle with a placeholder
                // empty set.
                return after }
            for _ in 0..<8 {
                group.addTask {
                    let hits = try await ops.searchScoped("oracle shared", limit: 50)
                    return Set(hits.map { "\($0.informationID)|\($0.carrierID)" })
                }
            }
            for try await observed in group {
                // STRICT atomic-visibility oracle: every concurrent reader
                // sees OLD COMPLETE or NEW COMPLETE — never empty, never
                // partial (one pair), never mixed (three pairs).
                #expect(observed == before || observed == after,
                        "observed \(observed) — expected before \(before) or after \(after)")
            }
        }
        let final = Set(try await ops.searchScoped("oracle shared", limit: 50)
            .map { "\($0.informationID)|\($0.carrierID)" })
        #expect(final == after)
    }

    private func appendEvent(
        _ ops: SQLiteUnifiedCarrierOperations, _ carrierID: String,
        kind: String, payload: String, occurredAt: TimeInterval,
        actor: String, op: String, ref: String
    ) async throws -> UASessionAppendResult {
        try await ops.appendSessionEvent(
            carrierID: carrierID, kind: kind, payload: Data(payload.utf8),
            occurredAt: Date(timeIntervalSince1970: occurredAt),
            actorID: actor, operationID: op, clientRef: ref)
    }

    // MARK: Focus C — MA-7 zero-effect boundary includes the entity layer
    // (round-4 ruling, corrected from the round-3 probe into verification)

    @Test
    func focusC1ReplayPreflightLeavesZeroExternalEffect() async throws {
        let b = try freshFactory().make()
        let ops = b.operations
        let carrier = try await makeFileCarrier(ops, "c1")
        let p1 = Data("c1 payload one".utf8)
        _ = try await ops.reviseCarrierWithRepresentation(
            carrierID: carrier.carrierID,
            informationID: CarrierInformationID(rawValue: "c1-info"),
            revisionID: CarrierRevisionID(rawValue: "c1-rev"),
            representationID: CarrierRepresentationID(rawValue: "R-c1"),
            payload: p1, mediaType: nil,
            expectedRevision: carrier.revision, fromVersion: nil,
            actorID: "agent-A", operationID: "OP1")
        // State hash H1 — INCLUDES the entity store (authority fingerprint
        // hashes authority tables + entity files).
        let h1 = try await ops.authorityFingerprint()
        let p2 = Data("c1 payload two (must never be written)".utf8)
        // Same operation_id, different payload: the recorded outcome is
        // returned and NO external effect occurs.
        let (after, outcome) = try await ops.reviseCarrierWithRepresentation(
            carrierID: carrier.carrierID,
            informationID: CarrierInformationID(rawValue: "c1-info"),
            revisionID: CarrierRevisionID(rawValue: "c1-rev"),
            representationID: CarrierRepresentationID(rawValue: "R-c1"),
            payload: p2, mediaType: nil,
            expectedRevision: carrier.revision, fromVersion: nil,
            actorID: "agent-A", operationID: "OP1")
        let h2 = try await ops.authorityFingerprint()
        #expect(outcome == .applied)
        #expect(after.revision == 1)
        #expect(h2 == h1)
        // P2 entity does NOT exist (round-3 probe showed it did — the
        // replay preflight now precedes any durable external effect).
        #expect(!FileManager.default.fileExists(
            atPath: b.representations.fileURL(for: digest(p2)).path))
        // Exactly one OP1 ledger row.
        #expect(try await ops.operationLedger()
            .filter { $0.operationID == "OP1" }.count == 1)
    }

    @Test
    func focusC2StaleRejectionLeavesNoEntity() async throws {
        let b = try freshFactory().make()
        let ops = b.operations
        let carrier = try await makeFileCarrier(ops, "c2")
        let p3 = Data("c2 payload three (stale attempt)".utf8)
        let fingerprintBefore = try await ops.authorityFingerprint()
        await #expect(throws: UAOperationError.staleRevision(expected: 99, observed: carrier.revision)) {
            try await ops.reviseCarrierWithRepresentation(
                carrierID: carrier.carrierID,
                informationID: CarrierInformationID(rawValue: "c2-info"),
                revisionID: CarrierRevisionID(rawValue: "c2-rev-stale"),
                representationID: CarrierRepresentationID(rawValue: "R-c2-stale"),
                payload: p3, mediaType: nil,
                expectedRevision: 99, fromVersion: nil,
                actorID: "agent-A", operationID: "OP-stale")
        }
        // No P3 entity; carrier/mapping/provenance unchanged; exactly one
        // terminal conflict record for the rejected attempt.
        #expect(!FileManager.default.fileExists(
            atPath: b.representations.fileURL(for: digest(p3)).path))
        #expect((try await ops.carrier(carrierID: carrier.carrierID))?.revision == carrier.revision)
        #expect(try await ops.mappings().isEmpty)
        #expect(try await ops.danglingProvenanceCount() == 0)
        let ledger = try await ops.operationLedger()
        #expect(ledger.filter { $0.operationID == "OP-stale" }.count == 1)
        #expect(ledger.first { $0.operationID == "OP-stale" }?.outcome == .conflict)
        // The conflict evidence row is the ONLY delta beyond the baseline
        // carrier setup — the ledger is append-only by design, so the
        // fingerprint delta is exactly that row.
        #expect(try await ops.authorityFingerprint() != fingerprintBefore)
    }

    @Test
    func focusC3IdentityConflictLeavesNoEntity() async throws {
        let b = try freshFactory().make()
        let ops = b.operations
        let carrier = try await makeFileCarrier(ops, "c3")
        let p1 = Data("c3 payload one".utf8)
        _ = try await ops.reviseCarrierWithRepresentation(
            carrierID: carrier.carrierID,
            informationID: CarrierInformationID(rawValue: "c3-info"),
            revisionID: CarrierRevisionID(rawValue: "c3-rev"),
            representationID: CarrierRepresentationID(rawValue: "R-c3"),
            payload: p1, mediaType: nil,
            expectedRevision: carrier.revision, fromVersion: nil,
            actorID: "agent-A", operationID: "OP-c3-1")
        let p4 = Data("c3 payload four (identity conflict)".utf8)
        let fingerprintBefore = try await ops.authorityFingerprint()
        await #expect(throws: UAOperationError.conflictingDuplicateRepresentation("R-c3")) {
            try await ops.reviseCarrierWithRepresentation(
                carrierID: carrier.carrierID,
                informationID: CarrierInformationID(rawValue: "c3-info"),
                revisionID: CarrierRevisionID(rawValue: "c3-rev"),
                representationID: CarrierRepresentationID(rawValue: "R-c3"),
                payload: p4, mediaType: nil,
                expectedRevision: 1, fromVersion: nil,
                actorID: "agent-A", operationID: "OP-c3-conflict")
        }
        #expect(!FileManager.default.fileExists(
            atPath: b.representations.fileURL(for: digest(p4)).path))
        #expect((try await ops.carrier(carrierID: carrier.carrierID))?.revision == 1)
        #expect(try await ops.mappings().isEmpty)
        #expect(try await ops.danglingProvenanceCount() == 0)
        let ledger = try await ops.operationLedger()
        #expect(ledger.first { $0.operationID == "OP-c3-conflict" }?.outcome == .conflict)
        // Fingerprint delta = the conflict evidence row only (append-only
        // ledger); no representation row, no entity file, no mapping.
        let conflicts = ledger.filter { $0.outcome == .conflict }
        #expect(conflicts.count == 1 && conflicts.first?.operationID == "OP-c3-conflict")
    }

    // MARK: Focus B — deterministic interleave instrumentation
    // (round-4 ruling: readers must be FORCED into the rebuild critical
    // section. A second connection holds the exact rebuild transaction
    // open; readers on the main connection run inside the critical
    // window and must observe ONLY BEFORE or AFTER — WAL snapshot
    // isolation, the same guarantee uaRebuildIndex relies on when
    // concurrent readers exist on other connections. Single-connection
    // self-observation is impossible without a mechanism seam, which is
    // out of scope.)

    @Test
    func focusBDeterministicInterleaveReaderInsideRebuildCriticalSection() async throws {
        let factory = freshFactory()
        let b = try factory.make()
        let ops = b.operations
        let a = try await makeFileCarrier(ops, "il-a")
        let c = try await ops.createCarrier(
            kind: .session, locatorScheme: nil, locatorValue: nil,
            actorID: "agent-B", operationID: "op-il-b").carrier
        let info1 = CarrierInformationID(rawValue: "il-info-1")
        let info2 = CarrierInformationID(rawValue: "il-info-2")
        let info3 = CarrierInformationID(rawValue: "il-info-3")
        _ = try await ops.recordMapping(
            informationID: info1, carrierID: a.carrierID, recordID: "r1",
            representationID: nil, fromVersion: nil,
            actorID: "agent-A", operationID: "op-il-map-1")
        _ = try await ops.recordMapping(
            informationID: info2, carrierID: c.carrierID, recordID: "r2",
            representationID: nil, fromVersion: nil,
            actorID: "agent-B", operationID: "op-il-map-2")
        _ = try await ops.recordMapping(
            informationID: info3, carrierID: c.carrierID, recordID: "r3",
            representationID: nil, fromVersion: nil,
            actorID: "agent-B", operationID: "op-il-map-3")
        // BEFORE = {I1×A, I2×C}; AFTER = {I1×A, I3×C}; both documents in
        // either state share the probe term.
        try await ops.indexDocument(
            informationID: info1, carrierID: a.carrierID,
            revisionID: CarrierRevisionID(rawValue: "il-rev-1"),
            title: nil, text: "interleave oracle old one")
        try await ops.indexDocument(
            informationID: info2, carrierID: c.carrierID,
            revisionID: CarrierRevisionID(rawValue: "il-rev-2"),
            title: nil, text: "interleave oracle old two")
        let before: Set<String> = ["il-info-1|\(a.carrierID)", "il-info-2|\(c.carrierID)"]
        let after: Set<String> = ["il-info-1|\(a.carrierID)", "il-info-3|\(c.carrierID)"]
        // Second connection holds the EXACT rebuild transaction open
        // (same statements uaRebuildIndex executes).
        let registryPath = factory.rootURL.appendingPathComponent("registry.sqlite").path
        let writer = try SQLiteCore(path: registryPath)
        try await writer.runOutsideTransaction("BEGIN IMMEDIATE")
        try await writer.runOutsideTransaction("DELETE FROM search_fts WHERE carrier_id IS NOT NULL")
        try await writer.runOutsideTransaction("DELETE FROM ua_index_builds")
        try await writer.runOutsideTransaction(
            "INSERT INTO search_fts(information_id, carrier_id, revision_id, title, text) VALUES (?,?,?,?,?)",
            bind: {
                $0.bindText(1, "il-info-1")
                $0.bindText(2, a.carrierID)
                $0.bindText(3, "il-rev-1")
                $0.bindTextOpt(4, nil)
                $0.bindText(5, "interleave oracle new one")
            })
        try await writer.runOutsideTransaction(
            "INSERT INTO search_fts(information_id, carrier_id, revision_id, title, text) VALUES (?,?,?,?,?)",
            bind: {
                $0.bindText(1, "il-info-3")
                $0.bindText(2, c.carrierID)
                $0.bindText(3, "il-rev-3")
                $0.bindTextOpt(4, nil)
                $0.bindText(5, "interleave oracle new two")
            })
        // Readers INSIDE the open critical section (WAL readers proceed).
        for _ in 0..<4 {
            let observed = Set(try await ops.searchScoped("interleave oracle", limit: 50)
                .map { "\($0.informationID)|\($0.carrierID)" })
            #expect(observed == before,
                    "inside critical section the reader must see the BEFORE snapshot; got \(observed)")
        }
        // Commit → AFTER.
        try await writer.runOutsideTransaction("COMMIT")
        let final = Set(try await ops.searchScoped("interleave oracle", limit: 50)
            .map { "\($0.informationID)|\($0.carrierID)" })
        #expect(final == after)
    }
}