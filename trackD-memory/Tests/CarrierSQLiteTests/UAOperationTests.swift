import Foundation
import CryptoKit
import Testing
import CarrierInterface
@testable import CarrierSQLite

// U-A mechanism-level conformance (Unified Minimal Composition Manifest §4).
// Each test derives mechanically from a manifest chain's pass/fail criterion
// and is named for the MA clause and correctness bound it exercises. These
// are composition-level mechanism checks; no Frozen Contract vocabulary is
// asserted here beyond what UA v1.0 already froze.

@Suite
struct UAOperationTests {
    private func freshFactory() -> SQLiteCarrierFactory {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ccvs01-ua-\(UUID().uuidString)", isDirectory: true)
        return SQLiteCarrierFactory(rootURL: root)
    }

    private func makeFileCarrier(
        _ ops: SQLiteUnifiedCarrierOperations, _ name: String
    ) async throws -> UACarrier {
        let (carrier, outcome) = try await ops.createCarrier(
            kind: .file, locatorScheme: "file", locatorValue: "\(name)/1",
            actorID: "agent-A", operationID: "op-create-\(name)"
        )
        #expect(outcome == .applied)
        return carrier
    }

    // MARK: MA-3 / I19 — lost-update prevention

    @Test
    func ma3StaleReviseDetectedWithNoOverwrite() async throws {
        let ops = try freshFactory().make().operations
        let carrier = try await makeFileCarrier(ops, "ma3")
        // First revise from base 0 -> 1.
        let (revised, outcome) = try await ops.reviseCarrier(
            carrierID: carrier.carrierID, expectedRevision: 0,
            newLocatorScheme: "file", newLocatorValue: "ma3/2",
            fromVersion: "base-0", actorID: "agent-A", operationID: "op-rev-1"
        )
        #expect(outcome == .applied)
        #expect(revised.revision == 1)
        // Agent A commits from the stale base 0 — must be rejected.
        await #expect(throws: UAOperationError.staleRevision(expected: 0, observed: 1)) {
            try await ops.reviseCarrier(
                carrierID: carrier.carrierID, expectedRevision: 0,
                newLocatorScheme: "file", newLocatorValue: "ma3/stale",
                fromVersion: "base-0", actorID: "agent-A", operationID: "op-rev-stale"
            )
        }
        // No silent overwrite: revision and locator unchanged.
        let afterStale = try await ops.carrier(carrierID: carrier.carrierID)
        #expect(afterStale?.revision == 1)
        #expect(afterStale?.locatorValue == "ma3/2")
        // The CONFLICT attempt is recorded as ledger evidence.
        let ledger = try await ops.operationLedger()
        #expect(ledger.contains {
            $0.operationID == "op-rev-stale" && $0.outcome == .conflict
                && $0.baseRevision == 0 && $0.observedRevision == 1
        })
        // Rebase: re-read, then commit from the fresh base.
        let (rebased, rebaseOutcome) = try await ops.reviseCarrier(
            carrierID: carrier.carrierID, expectedRevision: 1,
            newLocatorScheme: "file", newLocatorValue: "ma3/3",
            fromVersion: "rebase-from-1", actorID: "agent-A", operationID: "op-rev-2"
        )
        #expect(rebaseOutcome == .applied)
        #expect(rebased.revision == 2)
        #expect(try await ops.operationLedger().contains {
            $0.operationID == "op-rev-2" && $0.fromVersion == "rebase-from-1"
        })
    }

    // MARK: MA-7 / I24 — idempotent retry

    @Test
    func ma7SameOperationIDReplaysWithZeroStateDelta() async throws {
        let ops = try freshFactory().make().operations
        let carrier = try await ops.createCarrier(
            kind: .session, locatorScheme: nil, locatorValue: nil,
            actorID: "agent-A", operationID: "op-create-s1"
        ).carrier
        let first = try await ops.appendSessionEvent(
            carrierID: carrier.carrierID, kind: "JUDGMENT",
            payload: Data("r1".utf8), occurredAt: Date(timeIntervalSince1970: 100),
            actorID: "agent-A", operationID: "op-append-1", clientRef: "client-ref-1"
        )
        #expect(first.outcome == .applied)
        let fingerprintBefore = try await ops.authorityFingerprint()
        // Retry with the SAME operation id after "unknown outcome".
        let retry = try await ops.appendSessionEvent(
            carrierID: carrier.carrierID, kind: "JUDGMENT",
            payload: Data("r1".utf8), occurredAt: Date(timeIntervalSince1970: 100),
            actorID: "agent-A", operationID: "op-append-1", clientRef: "client-ref-1"
        )
        #expect(retry.outcome == .replayed)
        #expect(retry.event.eventID == first.event.eventID)
        #expect(retry.event.sequence == first.event.sequence)
        // Zero state delta: the authority fingerprint is byte-identical
        // (the ledger's replay path performs no writes).
        #expect(try await ops.authorityFingerprint() == fingerprintBefore)
    }

    // MARK: MA-6 — client-ref dedupe + carrier-side ordering

    @Test
    func ma6SameClientRefAcrossOperationsYieldsOneEvent() async throws {
        let ops = try freshFactory().make().operations
        let carrier = try await ops.createCarrier(
            kind: .session, locatorScheme: nil, locatorValue: nil,
            actorID: "agent-A", operationID: "op-create-s2"
        ).carrier
        let first = try await ops.appendSessionEvent(
            carrierID: carrier.carrierID, kind: "RESULT", payload: Data("x".utf8),
            occurredAt: Date(), actorID: "agent-A",
            operationID: "op-a", clientRef: "shared-ref"
        )
        #expect(first.outcome == .applied)
        // A different operation (different id) retries the same logical
        // append — the client ref resolves to the ONE allocated event.
        let duplicate = try await ops.appendSessionEvent(
            carrierID: carrier.carrierID, kind: "RESULT", payload: Data("x".utf8),
            occurredAt: Date(), actorID: "agent-B",
            operationID: "op-b", clientRef: "shared-ref"
        )
        #expect(duplicate.outcome == .replayed)
        #expect(duplicate.event.eventID == first.event.eventID)
        let snapshot = try await ops.consistentSnapshot(carrierID: carrier.carrierID)
        #expect(snapshot.events.count == 1)
    }

    @Test
    func ma6ConcurrentAppendsProduceGaplessTotalOrder() async throws {
        let ops = try freshFactory().make().operations
        let carrier = try await ops.createCarrier(
            kind: .session, locatorScheme: nil, locatorValue: nil,
            actorID: "agent-A", operationID: "op-create-s3"
        ).carrier
        // Clock skew injected on purpose: allocation order must be the
        // carrier's, never the client timestamps' order.
        let appends = try await withThrowingTaskGroup(
            of: UASessionAppendResult.self
        ) { group -> [UASessionAppendResult] in
            for index in 0..<12 {
                group.addTask {
                    try await ops.appendSessionEvent(
                        carrierID: carrier.carrierID, kind: "NOTE",
                        payload: Data("event-\(index)".utf8),
                        occurredAt: Date(timeIntervalSince1970: Double(100 - index)),
                        actorID: index.isMultiple(of: 2) ? "agent-A" : "agent-B",
                        operationID: "op-append-\(index)",
                        clientRef: "ref-\(index)"
                    )
                }
            }
            var results: [UASessionAppendResult] = []
            for try await result in group { results.append(result) }
            return results
        }
        #expect(appends.count == 12)
        #expect(appends.allSatisfy { $0.outcome == .applied })
        let snapshot = try await ops.consistentSnapshot(carrierID: carrier.carrierID)
        let sequences = snapshot.events.map(\.sequence)
        #expect(sequences == Array(0..<12))
        // Timestamps were injected in reverse; allocation order (payload
        // content order is irrelevant, but occurredAt order must NOT be
        // the stored order — the carrier allocated the sequence).
        let occurredAts = snapshot.events.map { $0.occurredAt.timeIntervalSince1970 }
        #expect(occurredAts != occurredAts.sorted())
        #expect(snapshot.readVersion == 12)
    }

    // MARK: MA-4 / I21 — atomic boundary + complete provenance

    @Test
    func ma4CompoundReviseCommitsAllPartsAtomically() async throws {
        let bundle = try freshFactory().make()
        let ops = bundle.operations
        let carrier = try await makeFileCarrier(ops, "ma4")
        let payload = Data("revision-2 bytes".utf8)
        let (revised, outcome) = try await ops.reviseCarrierWithRepresentation(
            carrierID: carrier.carrierID,
            informationID: CarrierInformationID(rawValue: "ma4-info"),
            revisionID: CarrierRevisionID(rawValue: "ma4-rev-2"),
            representationID: CarrierRepresentationID(rawValue: "ma4-rep-2"),
            payload: payload, mediaType: "text/plain",
            expectedRevision: carrier.revision, fromVersion: "from-rev-1",
            actorID: "agent-A", operationID: "op-compound-1"
        )
        #expect(outcome == .applied)
        #expect(revised.revision == carrier.revision + 1)
        // All three parts committed together: representation row,
        // carrier bump, ledger provenance.
        let content = try await bundle.representations.content(
            CarrierRepresentationID(rawValue: "ma4-rep-2")
        )
        #expect(content?.payload.bytes == payload)
        let ledger = try await ops.operationLedger()
        #expect(ledger.contains {
            $0.operationID == "op-compound-1" && $0.outcome == .applied
                && $0.observedRevision == carrier.revision + 1
                && $0.fromVersion == "from-rev-1"
        })
        // I21: no committed operation lacks provenance.
        #expect(try await ops.danglingProvenanceCount() == 0)
    }

    @Test
    func ma4ConflictInsideCompoundWritesEvidenceOnly() async throws {
        let bundle = try freshFactory().make()
        let ops = bundle.operations
        let carrier = try await makeFileCarrier(ops, "ma4c")
        // Stale base for the compound operation.
        await #expect(throws: UAOperationError.staleRevision(expected: 7, observed: carrier.revision)) {
            try await ops.reviseCarrierWithRepresentation(
                carrierID: carrier.carrierID,
                informationID: CarrierInformationID(rawValue: "ma4c-info"),
                revisionID: CarrierRevisionID(rawValue: "ma4c-rev-x"),
                representationID: CarrierRepresentationID(rawValue: "ma4c-rep-x"),
                payload: Data("never committed".utf8), mediaType: nil,
                expectedRevision: 7, fromVersion: nil,
                actorID: "agent-A", operationID: "op-compound-stale"
            )
        }
        // Carrier state unchanged; no representation row leaked.
        let after = try await ops.carrier(carrierID: carrier.carrierID)
        #expect(after?.revision == carrier.revision)
        let content = try await bundle.representations.content(
            CarrierRepresentationID(rawValue: "ma4c-rep-x")
        )
        #expect(content == nil)
        // But the CONFLICT attempt is visible as evidence.
        let ledger = try await ops.operationLedger()
        #expect(ledger.contains {
            $0.operationID == "op-compound-stale" && $0.outcome == .conflict
        })
        #expect(try await ops.danglingProvenanceCount() == 0)
    }

    // MARK: I20 — conflicting duplicate carrier registration

    @Test
    func i20DuplicateCarrierIdentityRejected() async throws {
        let ops = try freshFactory().make().operations
        _ = try await ops.createCarrier(
            kind: .file, locatorScheme: "file", locatorValue: "dup/1",
            actorID: "agent-A", operationID: "op-dup-1", explicitCarrierID: "C-DUP-1"
        )
        await #expect(throws: UAOperationError.conflictingDuplicateCarrierIdentity("C-DUP-1")) {
            try await ops.createCarrier(
                kind: .file, locatorScheme: "file", locatorValue: "dup/1",
                actorID: "agent-B", operationID: "op-dup-2", explicitCarrierID: "C-DUP-1"
            )
        }
        // Exactly one carriers row for the logical instance.
        let ledger = try await ops.operationLedger()
        #expect(ledger.filter { $0.kind == "CARRIER_CREATE" && $0.outcome == .applied }.count == 1)
    }

    // MARK: §2 / §3 — identity namespaces + mapping closed loop

    @Test
    func identityNamespacesAndMappingClosedLoop() async throws {
        let bundle = try freshFactory().make()
        let ops = bundle.operations
        let carrier = try await makeFileCarrier(ops, "ident")
        // Carrier identity is a registry-minted UUID, never the
        // information id, never derived from the locator.
        #expect(carrier.carrierID != "ident-info")
        #expect(UUID(uuidString: carrier.carrierID) != nil)
        let infoID = CarrierInformationID(rawValue: "ident-info")
        let payload = Data("closed loop bytes".utf8)
        _ = try await ops.reviseCarrierWithRepresentation(
            carrierID: carrier.carrierID,
            informationID: infoID,
            revisionID: CarrierRevisionID(rawValue: "ident-rev-2"),
            representationID: CarrierRepresentationID(rawValue: "ident-rep"),
            payload: payload, mediaType: nil,
            expectedRevision: carrier.revision, fromVersion: nil,
            actorID: "agent-A", operationID: "op-ident-rev"
        )
        _ = try await ops.recordMapping(
            informationID: infoID, carrierID: carrier.carrierID,
            recordID: "record-1", representationID: "ident-rep",
            fromVersion: "from-rev-2", actorID: "agent-A",
            operationID: "op-ident-map"
        )
        // Forward walk: information -> mapping -> carrier -> representation
        // -> bytes (digest re-verified).
        let mappings = try await ops.mappings()
        let mapping = try #require(mappings.first { $0.informationID == "ident-info" })
        #expect(mapping.carrierID == carrier.carrierID)
        #expect(mapping.representationID == "ident-rep")
        let content = try await bundle.representations.content(
            CarrierRepresentationID(rawValue: "ident-rep")
        )
        #expect(content?.payload.bytes == payload)
        // Backward walk: bytes -> digest -> representation -> mapping.
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        #expect(content?.representation.digest == digest)
        let byDigest = mappings.first { $0.representationID == "ident-rep" }
        #expect(byDigest != nil)
        // Append-only semantics: a correction is a NEW mapping entry.
        _ = try await ops.recordMapping(
            informationID: infoID, carrierID: carrier.carrierID,
            recordID: "record-1-corrected", representationID: "ident-rep",
            fromVersion: nil, actorID: "agent-A", operationID: "op-ident-map-fix"
        )
        #expect(try await ops.mappings().count == 2)
    }

    // MARK: MA-9 / I25 — index isolation + rebuild completeness

    @Test
    func ma9StalenessDetectableAndRebuildRestoresCoverage() async throws {
        let ops = try freshFactory().make().operations
        let fileCarrier = try await makeFileCarrier(ops, "ma9")
        let sessionCarrier = try await ops.createCarrier(
            kind: .session, locatorScheme: nil, locatorValue: nil,
            actorID: "agent-B", operationID: "op-create-ma9-s"
        ).carrier
        let infoA = CarrierInformationID(rawValue: "ma9-info-a")
        let infoB = CarrierInformationID(rawValue: "ma9-info-b")
        _ = try await ops.recordMapping(
            informationID: infoA, carrierID: fileCarrier.carrierID,
            recordID: "r-a", representationID: nil, fromVersion: nil,
            actorID: "agent-A", operationID: "op-map-a"
        )
        _ = try await ops.recordMapping(
            informationID: infoB, carrierID: sessionCarrier.carrierID,
            recordID: "r-b", representationID: nil, fromVersion: nil,
            actorID: "agent-B", operationID: "op-map-b"
        )
        try await ops.indexDocument(
            informationID: infoA, carrierID: fileCarrier.carrierID,
            revisionID: CarrierRevisionID(rawValue: "ma9-rev-a"),
            title: "alpha", text: "quantum flux capacitor notes"
        )
        try await ops.indexDocument(
            informationID: infoB, carrierID: sessionCarrier.carrierID,
            revisionID: CarrierRevisionID(rawValue: "ma9-rev-b"),
            title: "beta", text: "session timeline of research day"
        )
        // Fresh builds are not stale.
        #expect(try await ops.indexStaleness().isEmpty)
        // A carrier write advances the revision — the index becomes
        // stale-DETECTABLE (never silently outdated).
        _ = try await ops.recordMapping(
            informationID: infoA, carrierID: fileCarrier.carrierID,
            recordID: "r-a2", representationID: nil, fromVersion: nil,
            actorID: "agent-A", operationID: "op-map-a2"
        )
        let stale = try await ops.indexStaleness()
        #expect(stale.contains { $0.carrierID == fileCarrier.carrierID })
        // Coverage before rebuild: both documents searchable.
        let hitsA = try await ops.search("quantum", limit: 10).map(\.informationID.rawValue)
        let hitsB = try await ops.search("timeline", limit: 10).map(\.informationID.rawValue)
        let hitsBefore = Set(hitsA + hitsB)
        #expect(hitsBefore == Set(["ma9-info-a", "ma9-info-b"]))
        // Rebuild from authority-derived documents: authority fingerprint
        // must be byte-identical before and after (index never touches
        // authority), and coverage must be restored exactly.
        let fingerprintBefore = try await ops.authorityFingerprint()
        let report = try await ops.rebuildIndex(documents: [
            (informationID: infoA, carrierID: fileCarrier.carrierID,
             revisionID: CarrierRevisionID(rawValue: "ma9-rev-a"),
             title: "alpha", text: "quantum flux capacitor notes"),
            (informationID: infoB, carrierID: sessionCarrier.carrierID,
             revisionID: CarrierRevisionID(rawValue: "ma9-rev-b"),
             title: "beta", text: "session timeline of research day"),
        ])
        #expect(report.documentsIndexed == 2)
        #expect(try await ops.authorityFingerprint() == fingerprintBefore)
        let hitsA2 = try await ops.search("quantum", limit: 10).map(\.informationID.rawValue)
        let hitsB2 = try await ops.search("timeline", limit: 10).map(\.informationID.rawValue)
        #expect(Set(hitsA2 + hitsB2) == hitsBefore)
        // Post-rebuild, the index is fresh again (build versions match).
        #expect(try await ops.indexStaleness().isEmpty)
    }

    // MARK: MA-10 / I22 — snapshot / read version

    @Test
    func ma10SnapshotIsOneCommittedVersionView() async throws {
        let ops = try freshFactory().make().operations
        let carrier = try await ops.createCarrier(
            kind: .session, locatorScheme: nil, locatorValue: nil,
            actorID: "agent-A", operationID: "op-create-ma10"
        ).carrier
        for index in 0..<3 {
            _ = try await ops.appendSessionEvent(
                carrierID: carrier.carrierID, kind: "NOTE",
                payload: Data("n\(index)".utf8), occurredAt: Date(),
                actorID: "agent-A", operationID: "op-ma10-\(index)",
                clientRef: "ma10-ref-\(index)"
            )
        }
        let snapshot = try await ops.consistentSnapshot(carrierID: carrier.carrierID)
        #expect(snapshot.readVersion == 3)
        #expect(snapshot.events.map(\.sequence) == [0, 1, 2])
        #expect(snapshot.carrier?.revision == snapshot.readVersion)
        // Two further commits advance the version; the next snapshot
        // observes the new committed state coherently (no mixed view of
        // pre-commit event counts with post-commit versions).
        for index in 3..<5 {
            _ = try await ops.appendSessionEvent(
                carrierID: carrier.carrierID, kind: "NOTE",
                payload: Data("n\(index)".utf8), occurredAt: Date(),
                actorID: "agent-B", operationID: "op-ma10-\(index)",
                clientRef: "ma10-ref-\(index)"
            )
        }
        let later = try await ops.consistentSnapshot(carrierID: carrier.carrierID)
        #expect(later.readVersion == 5)
        #expect(later.events.count == 5)
        #expect(later.events.map(\.sequence) == Array(0..<5))
    }

    // MARK: MA-2 — concurrent writes across carriers interleave

    @Test
    func ma2ConcurrentWritesAcrossCarriersAllSucceed() async throws {
        let ops = try freshFactory().make().operations
        let fileCarrierA = try await makeFileCarrier(ops, "ma2a")
        let fileCarrierB = try await makeFileCarrier(ops, "ma2b")
        let sessionCarrier = try await ops.createCarrier(
            kind: .session, locatorScheme: nil, locatorValue: nil,
            actorID: "agent-B", operationID: "op-create-ma2-s"
        ).carrier
        // CAS revise with the MA-3 outcome set: conflict -> re-read ->
        // REBASE. A CONFLICT is a terminal outcome recorded under that
        // operation's id (MA-7 replay returns it verbatim), so a rebase
        // attempt is a NEW operation with a new operation_id (manifest
        // §4.1: "rebase = new operation with new expected_revision").
        func reviseWithRetry(_ carrierID: String, _ value: String, _ op: String) async throws {
            for attempt in 0..<10 {
                do {
                    let current = try await ops.carrier(carrierID: carrierID)
                    _ = try await ops.reviseCarrier(
                        carrierID: carrierID,
                        expectedRevision: current?.revision ?? 0,
                        newLocatorScheme: "file", newLocatorValue: value,
                        fromVersion: nil, actorID: "agent-A",
                        operationID: "\(op)-attempt-\(attempt)"
                    )
                    return
                } catch UAOperationError.staleRevision {
                    continue
                }
            }
            Issue.record("revise never settled: \(op)")
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<3 {
                group.addTask {
                    try await ops.appendSessionEvent(
                        carrierID: sessionCarrier.carrierID, kind: "NOTE",
                        payload: Data("s\(index)".utf8), occurredAt: Date(),
                        actorID: "agent-B", operationID: "op-ma2-s-\(index)",
                        clientRef: "ma2-s-ref-\(index)"
                    )
                }
                group.addTask {
                    try await reviseWithRetry(
                        fileCarrierA.carrierID, "ma2a/rev-\(index)", "op-ma2-a-\(index)"
                    )
                }
                group.addTask {
                    try await reviseWithRetry(
                        fileCarrierB.carrierID, "ma2b/rev-\(index)", "op-ma2-b-\(index)"
                    )
                }
            }
            try await group.waitForAll()
        }
        let afterA = try await ops.carrier(carrierID: fileCarrierA.carrierID)
        let afterB = try await ops.carrier(carrierID: fileCarrierB.carrierID)
        let afterS = try await ops.carrier(carrierID: sessionCarrier.carrierID)
        // Independent revision streams, all settled: 3 appends on the
        // session carrier (conflict-free by carrier-side allocation), 3
        // CAS revises on each file carrier (conflicts retried per MA-3).
        #expect(afterS?.revision == 3, "session actual: \(afterS?.revision ?? -1)")
        #expect(afterA?.revision == 3, "fileA actual: \(afterA?.revision ?? -1)")
        #expect(afterB?.revision == 3, "fileB actual: \(afterB?.revision ?? -1)")
        #expect(try await ops.danglingProvenanceCount() == 0)
        // Every recorded outcome is in the allowed set, and any CONFLICT
        // rows that occurred during racing retried to APPLIED.
        let ledger = try await ops.operationLedger()
        #expect(ledger.allSatisfy {
            $0.outcome == .applied || $0.outcome == .conflict || $0.outcome == .replayed
        })
    }
}
