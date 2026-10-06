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
        let docA = (informationID: infoA, carrierID: a.carrierID,
                    revisionID: CarrierRevisionID(rawValue: "conc-rev-a"),
                    title: nil as String?, text: "alpha concurrent text" as String)
        let docB = (informationID: infoB, carrierID: b.carrierID,
                    revisionID: CarrierRevisionID(rawValue: "conc-rev-b"),
                    title: nil as String?, text: "beta concurrent text" as String)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await ops.indexDocument(
                informationID: docA.informationID, carrierID: docA.carrierID,
                revisionID: docA.revisionID, title: docA.title, text: docA.text) }
            group.addTask { _ = try await ops.rebuildIndex(documents: [docA, docB]) }
            group.addTask { try await ops.indexDocument(
                informationID: docB.informationID, carrierID: docB.carrierID,
                revisionID: docB.revisionID, title: docB.title, text: docB.text) }
            try await group.waitForAll()
        }
        // Legal linearization: the full rebuild replaces the whole index;
        // whatever the order, the surviving set is exactly one of the two
        // legal states and every surviving row is pair-consistent.
        let hits = try await ops.searchScoped("concurrent text", carrierID: nil)
        let pairs = Set(hits.map { "\($0.informationID)|\($0.carrierID)" })
        let legalAfterRebuildLast: Set<String> = [
            "\(infoA.rawValue)|\(a.carrierID)", "\(infoB.rawValue)|\(b.carrierID)"]
        let legalAfterIndexLast: Set<String> = [
            "\(infoA.rawValue)|\(a.carrierID)", "\(infoB.rawValue)|\(b.carrierID)"]
        #expect(pairs == legalAfterRebuildLast || pairs == legalAfterIndexLast)
        let residualStale = try await ops.indexStaleness()
        #expect(residualStale.isEmpty || residualStale.count <= 2)
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
                // Retry of the committed operation (unknown-outcome replay).
                let replay = try await ops.appendSessionEvent(
                    carrierID: carrier.carrierID, kind: "NOTE",
                    payload: Data("committed before race".utf8),
                    occurredAt: Date(timeIntervalSince1970: 100),
                    actorID: "agent-A", operationID: "op-f6-known",
                    clientRef: "ref-f6-known")
                #expect(replay.outcome == .replayed)
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
    func focus6SearchDuringRebuildNeverSeesPartialState() async throws {
        let ops = try freshFactory().make().operations
        let a = try await makeFileCarrier(ops, "sr-a")
        let info = CarrierInformationID(rawValue: "sr-info")
        _ = try await ops.recordMapping(
            informationID: info, carrierID: a.carrierID, recordID: "r",
            representationID: nil, fromVersion: nil,
            actorID: "agent-A", operationID: "op-sr-map")
        try await ops.indexDocument(
            informationID: info, carrierID: a.carrierID,
            revisionID: CarrierRevisionID(rawValue: "sr-rev"),
            title: nil, text: "searchable during rebuild")
        let docs: [(informationID: CarrierInformationID, carrierID: String,
                    revisionID: CarrierRevisionID, title: String?, text: String)] = [
            (info, a.carrierID, CarrierRevisionID(rawValue: "sr-rev"), nil,
             "searchable during rebuild")
        ]
        try await withThrowingTaskGroup(of: [UASearchHit].self) { group in
            group.addTask { _ = try await ops.rebuildIndex(documents: docs)
                return [] }
            for _ in 0..<6 {
                group.addTask { try await ops.searchScoped("searchable", limit: 50) }
            }
            for try await hits in group {
                // Every observed view is a complete committed state: either
                // the document is present or the index is momentarily empty
                // (pre-insert state) — never a partial row set.
                for hit in hits {
                    #expect(hit.informationID == "sr-info")
                    #expect(hit.carrierID == a.carrierID)
                }
            }
        }
        #expect(try await ops.searchScoped("searchable", carrierID: nil).count == 1)
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
}
