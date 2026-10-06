import Foundation
import SQLite3
import CryptoKit
import CarrierInterface

// U-A composition mechanisms (Unified Minimal Composition Manifest §2-§4).
// These are layer ②③④ implementation and evidence handles for the SQLite +
// POSIX composition ONLY: they never enter Information or Relation objects,
// never become Frozen Contract vocabulary, and impose no obligation on any
// other candidate (manifest §4 scope bounding, self-audit A2).

/// Logical Carrier kinds (CC-1: extensible only by explicit SimiGo-side
/// decision, never by carrier interpretation).
public enum UACarrierKind: String, Sendable, Equatable {
    case file = "FILE"
    case session = "SESSION"
}

/// Operation ledger outcome (manifest §4.1 evidence: outcome ∈
/// {APPLIED, CONFLICT, REPLAYED}).
public enum UAOperationOutcome: String, Sendable, Equatable {
    case applied = "APPLIED"
    case conflict = "CONFLICT"
    case replayed = "REPLAYED"
}

/// The logical Carrier object (CC-1): opaque carrier-side identity minted
/// by the registry, independent of Information identity and of locator.
public struct UACarrier: Sendable, Equatable {
    public let carrierID: String
    public let kind: UACarrierKind
    public let locatorScheme: String?
    public let locatorValue: String?
    public let revision: Int
    public let createdAt: Date
    public let createdBy: String
}

/// One operation-ledger row = complete carrier_provenance (MA-8 / I21):
/// who / when / from which version / resulting version / operation_id.
public struct UAOperationRecord: Sendable, Equatable {
    public let operationID: String
    public let actorID: String
    public let carrierID: String?
    public let subjectID: String?
    public let kind: String
    public let baseRevision: Int?
    public let observedRevision: Int?
    public let outcome: UAOperationOutcome
    public let fromVersion: String?
    public let resultingVersion: String?
    public let recordedAt: Date
}

/// CC-5 mapping row (append-only; corrections are new entries).
public struct UAMappingRecord: Sendable, Equatable {
    public let mappingID: String
    public let informationID: String
    public let carrierID: String
    public let recordID: String
    public let representationID: String?
    public let actorID: String
    public let operationID: String
    public let fromVersion: String?
    public let mappedAt: Date
}

public struct UASessionAppendResult: Sendable, Equatable {
    public let event: CarrierSessionEvent
    public let outcome: UAOperationOutcome
    public let carrierRevision: Int
}

public struct UACarrierSnapshot: Sendable {
    public let carrier: UACarrier?
    public let events: [CarrierSessionEvent]
    public let mappings: [UAMappingRecord]
    /// Carrier revision at snapshot time — the read_version all objects in
    /// this snapshot observe (MA-10).
    public let readVersion: Int
}

public struct UAStaleIndexEntry: Sendable, Equatable {
    public let carrierID: String
    public let informationID: String
    public let carrierRevision: Int
    public let indexedBuildVersion: Int?
}

public struct UARebuildReport: Sendable {
    public let documentsIndexed: Int
    public let completedAt: Date
}

public enum UAOperationError: Error, Equatable, Sendable {
    /// I20 (narrowed form): a second registration claiming an existing
    /// logical Carrier instance.
    case conflictingDuplicateCarrierIdentity(String)
    case carrierNotFound(String)
    case entityStoreUnavailable
    /// MA-3 CONFLICT: current revision differs from the base the actor
    /// read. Carrier state is unchanged; the CONFLICT attempt is recorded
    /// in the operation ledger as evidence.
    case staleRevision(expected: Int, observed: Int)
}

/// U-A unified operation facade over the A1 SQLite registry. All mutating
/// operations run in one SQLite transaction (MA-4) and record complete
/// provenance (MA-8 / I21); the actor-isolated implementations live in the
/// `SQLiteCore` extension below.
public struct SQLiteUnifiedCarrierOperations: Sendable {
    let core: SQLiteCore
    let entities: POSIXEntityStore?

    public init(core: SQLiteCore, entities: POSIXEntityStore? = nil) {
        self.core = core
        self.entities = entities
    }

    public func createCarrier(
        kind: UACarrierKind,
        locatorScheme: String?,
        locatorValue: String?,
        actorID: String,
        operationID: String,
        explicitCarrierID: String? = nil
    ) async throws -> (carrier: UACarrier, outcome: UAOperationOutcome) {
        try await core.uaCreateCarrier(
            kind: kind, locatorScheme: locatorScheme, locatorValue: locatorValue,
            actorID: actorID, operationID: operationID, explicitCarrierID: explicitCarrierID
        )
    }

    public func reviseCarrier(
        carrierID: String,
        expectedRevision: Int,
        newLocatorScheme: String?,
        newLocatorValue: String?,
        fromVersion: String?,
        actorID: String,
        operationID: String
    ) async throws -> (carrier: UACarrier, outcome: UAOperationOutcome) {
        try await core.uaReviseCarrier(
            carrierID: carrierID, expectedRevision: expectedRevision,
            newLocatorScheme: newLocatorScheme, newLocatorValue: newLocatorValue,
            fromVersion: fromVersion, actorID: actorID, operationID: operationID
        )
    }

    public func reviseCarrierWithRepresentation(
        carrierID: String,
        informationID: CarrierInformationID,
        revisionID: CarrierRevisionID,
        representationID: CarrierRepresentationID,
        payload: Data,
        mediaType: String?,
        expectedRevision: Int,
        fromVersion: String?,
        actorID: String,
        operationID: String
    ) async throws -> (carrier: UACarrier, outcome: UAOperationOutcome) {
        try await core.uaReviseCarrierWithRepresentation(
            entities: entities, carrierID: carrierID, informationID: informationID,
            revisionID: revisionID, representationID: representationID, payload: payload,
            mediaType: mediaType, expectedRevision: expectedRevision, fromVersion: fromVersion,
            actorID: actorID, operationID: operationID
        )
    }

    public func appendSessionEvent(
        carrierID: String,
        kind: String,
        payload: Data,
        occurredAt: Date,
        actorID: String,
        operationID: String,
        clientRef: String
    ) async throws -> UASessionAppendResult {
        try await core.uaAppendSessionEvent(
            carrierID: carrierID, kind: kind, payload: payload, occurredAt: occurredAt,
            actorID: actorID, operationID: operationID, clientRef: clientRef
        )
    }

    public func recordMapping(
        informationID: CarrierInformationID,
        carrierID: String,
        recordID: String,
        representationID: String?,
        fromVersion: String?,
        actorID: String,
        operationID: String
    ) async throws -> UAMappingRecord {
        try await core.uaRecordMapping(
            informationID: informationID, carrierID: carrierID, recordID: recordID,
            representationID: representationID, fromVersion: fromVersion,
            actorID: actorID, operationID: operationID
        )
    }

    public func consistentSnapshot(carrierID: String) async throws -> UACarrierSnapshot {
        try await core.uaConsistentSnapshot(carrierID: carrierID)
    }

    public func indexDocument(
        informationID: CarrierInformationID,
        carrierID: String,
        revisionID: CarrierRevisionID,
        title: String?,
        text: String
    ) async throws {
        try await core.uaIndexDocument(
            informationID: informationID, carrierID: carrierID,
            revisionID: revisionID, title: title, text: text
        )
    }

    public func indexStaleness() async throws -> [UAStaleIndexEntry] {
        try await core.uaIndexStaleness()
    }

    public func rebuildIndex(
        documents: [(informationID: CarrierInformationID, carrierID: String,
                     revisionID: CarrierRevisionID, title: String?, text: String)]
    ) async throws -> UARebuildReport {
        try await core.uaRebuildIndex(documents: documents)
    }

    public func search(_ query: String, limit: Int = 20) async throws -> [CarrierSearchResult] {
        try await core.uaSearch(query, limit: limit)
    }

    public func operationLedger() async throws -> [UAOperationRecord] {
        try await core.uaOperationLedger()
    }

    public func mappings() async throws -> [UAMappingRecord] {
        try await core.uaMappings()
    }

    public func carrier(carrierID: String) async throws -> UACarrier? {
        try await core.uaCarrier(carrierID: carrierID)
    }

    /// I21 evidence: APPLIED ledger rows missing any provenance component.
    public func danglingProvenanceCount() async throws -> Int {
        try await core.uaDanglingProvenanceCount()
    }

    /// Authority fingerprint for the MA-9 audit: hash of all authority
    /// table contents + entity files. Rebuild must never change this.
    public func authorityFingerprint() async throws -> String {
        try await core.uaAuthorityFingerprint(entities: entities)
    }
}

// MARK: - Actor-isolated implementations

extension SQLiteCore {
    // MARK: Carrier creation (§2 identity minting, I20)

    /// Mint a new logical Carrier. `carrierID` is minted by the registry
    /// (UUIDv4) unless `explicitCarrierID` is supplied — an explicit id
    /// that already exists is a CONFLICTING DUPLICATE REGISTRATION (I20),
    /// rejected, never silently re-registered.
    func uaCreateCarrier(
        kind: UACarrierKind,
        locatorScheme: String?,
        locatorValue: String?,
        actorID: String,
        operationID: String,
        explicitCarrierID: String?
    ) async throws -> (carrier: UACarrier, outcome: UAOperationOutcome) {
        try withTransaction {
            if let prior = try uaLedgerRow(operationID: operationID) {
                // MA-7 replay: the recorded ledger row IS the evidence; no
                // new effects, no duplicate ledger row.
                guard let carrierID = prior.carrierID,
                      let carrier = try uaCarrierRow(carrierID: carrierID) else {
                    throw UAOperationError.carrierNotFound(operationID)
                }
                return (carrier, prior.outcome)
            }
            let carrierID = try explicitCarrierID ?? uaMintCarrierID()
            if try uaCarrierRow(carrierID: carrierID) != nil {
                throw UAOperationError.conflictingDuplicateCarrierIdentity(carrierID)
            }
            let now = Date()
            try statement("""
              INSERT INTO carriers(carrier_id, kind, locator_scheme, locator_value,
                revision, created_at, created_by) VALUES (?,?,?,?,0,?,?)
            """, bind: {
                $0.bindText(1, carrierID)
                $0.bindText(2, kind.rawValue)
                $0.bindTextOpt(3, locatorScheme)
                $0.bindTextOpt(4, locatorValue)
                $0.bindDouble(5, now.timeIntervalSince1970)
                $0.bindText(6, actorID)
            })
            try uaLedgerInsert(
                operationID: operationID, actorID: actorID, carrierID: carrierID,
                subjectID: nil, kind: "CARRIER_CREATE", baseRevision: nil,
                observedRevision: 0, outcome: .applied,
                fromVersion: nil, resultingVersion: "0"
            )
            guard let carrier = try uaCarrierRow(carrierID: carrierID) else {
                throw UAOperationError.carrierNotFound(carrierID)
            }
            return (carrier, .applied)
        }
    }

    // MARK: MA-3 lost-update prevention (CAS)

    /// Carrier revision CAS: commits only when the current revision equals
    /// `expectedRevision` (the base the actor read). A mismatch records a
    /// CONFLICT ledger row in its own committed transaction (evidence only —
    /// carrier state is untouched) and throws. `newLocatorScheme`/
    /// `newLocatorValue` model a locator transition (MOVE) on the same
    /// logical carrier: identity unchanged.
    func uaReviseCarrier(
        carrierID: String,
        expectedRevision: Int,
        newLocatorScheme: String?,
        newLocatorValue: String?,
        fromVersion: String?,
        actorID: String,
        operationID: String
    ) async throws -> (carrier: UACarrier, outcome: UAOperationOutcome) {
        enum CASResult {
            case applied(UACarrier)
            case replayed(UACarrier, UAOperationOutcome)
            case conflict(observed: Int)
        }
        let casResult: CASResult = try withTransaction {
            if let prior = try uaLedgerRow(operationID: operationID) {
                guard let id = prior.carrierID,
                      let carrier = try uaCarrierRow(carrierID: id) else {
                    throw UAOperationError.carrierNotFound(carrierID)
                }
                return .replayed(carrier, prior.outcome)
            }
            guard let current = try uaCarrierRow(carrierID: carrierID) else {
                throw UAOperationError.carrierNotFound(carrierID)
            }
            guard current.revision == expectedRevision else {
                return .conflict(observed: current.revision)
            }
            try statement("""
              UPDATE carriers SET revision=revision+1, locator_scheme=?, locator_value=?
              WHERE carrier_id=? AND revision=?
            """, bind: {
                $0.bindTextOpt(1, newLocatorScheme ?? current.locatorScheme)
                $0.bindTextOpt(2, newLocatorValue ?? current.locatorValue)
                $0.bindText(3, carrierID)
                $0.bindInt(4, expectedRevision)
            })
            guard changes() == 1 else {
                return .conflict(observed: current.revision)
            }
            let resulting = expectedRevision + 1
            try uaLedgerInsert(
                operationID: operationID, actorID: actorID, carrierID: carrierID,
                subjectID: nil, kind: "CARRIER_REVISE", baseRevision: expectedRevision,
                observedRevision: resulting, outcome: .applied,
                fromVersion: fromVersion, resultingVersion: String(resulting)
            )
            guard let updated = try uaCarrierRow(carrierID: carrierID) else {
                throw UAOperationError.carrierNotFound(carrierID)
            }
            return .applied(updated)
        }
        switch casResult {
        case .applied(let carrier):
            return (carrier, .applied)
        case .replayed(let carrier, let outcome):
            return (carrier, outcome)
        case .conflict(let observed):
            try withTransaction {
                try uaLedgerInsert(
                    operationID: operationID, actorID: actorID, carrierID: carrierID,
                    subjectID: nil, kind: "CARRIER_REVISE", baseRevision: expectedRevision,
                    observedRevision: observed, outcome: .conflict,
                    fromVersion: fromVersion, resultingVersion: nil
                )
            }
            throw UAOperationError.staleRevision(expected: expectedRevision, observed: observed)
        }
    }

    // MARK: MA-4 compound revise — entity + registry in one boundary

    /// Compound FILE-carrier revise: entity bytes are durably written
    /// FIRST (temp+fsync+rename+dir-fsync+digest re-read), then ONE
    /// transaction commits representation row + carrier CAS bump + ledger.
    /// Crash between the two steps leaves a typed orphan entity (detected
    /// by the integrity reporter), never a half-committed registry.
    func uaReviseCarrierWithRepresentation(
        entities: POSIXEntityStore?,
        carrierID: String,
        informationID: CarrierInformationID,
        revisionID: CarrierRevisionID,
        representationID: CarrierRepresentationID,
        payload: Data,
        mediaType: String?,
        expectedRevision: Int,
        fromVersion: String?,
        actorID: String,
        operationID: String
    ) async throws -> (carrier: UACarrier, outcome: UAOperationOutcome) {
        guard let entities else {
            throw UAOperationError.entityStoreUnavailable
        }
        let digest = sha256Hex(payload)
        // 1) durable entity write with digest re-read verification.
        try entities.durableWrite(digest: digest, bytes: payload)
        if let written = FileManager.default.contents(atPath: entities.fileURL(for: digest).path),
           sha256Hex(written) != digest {
            throw CarrierInterfaceError.integrityIssue("post-write digest reread mismatch for \(digest)")
        }
        // Durable-acknowledgement boundary (P8 F1 exposure point, U-A).
        CrashGate.trap("UA-C2")
        // 2) one transaction: representation + CAS + provenance.
        enum CASResult {
            case applied(UACarrier)
            case replayed(UACarrier, UAOperationOutcome)
            case conflict(observed: Int)
        }
        let casResult: CASResult = try withTransaction {
            if let prior = try uaLedgerRow(operationID: operationID) {
                guard let id = prior.carrierID,
                      let carrier = try uaCarrierRow(carrierID: id) else {
                    throw UAOperationError.carrierNotFound(carrierID)
                }
                return .replayed(carrier, prior.outcome)
            }
            guard let current = try uaCarrierRow(carrierID: carrierID) else {
                throw UAOperationError.carrierNotFound(carrierID)
            }
            guard current.revision == expectedRevision else {
                return .conflict(observed: current.revision)
            }
            try statement("""
              INSERT OR IGNORE INTO representations(representation_id, information_id,
                revision_id, digest, byte_count, media_type, created_at) VALUES (?,?,?,?,?,?,?)
            """, bind: {
                $0.bindText(1, representationID.rawValue)
                $0.bindText(2, informationID.rawValue)
                $0.bindText(3, revisionID.rawValue)
                $0.bindText(4, digest)
                $0.bindInt(5, payload.count)
                $0.bindTextOpt(6, mediaType)
                $0.bindDouble(7, Date().timeIntervalSince1970)
            })
            try statement(
                "UPDATE carriers SET revision=revision+1 WHERE carrier_id=? AND revision=?",
                bind: {
                    $0.bindText(1, carrierID)
                    $0.bindInt(2, expectedRevision)
                }
            )
            guard changes() == 1 else {
                return .conflict(observed: current.revision)
            }
            let resulting = expectedRevision + 1
            try uaLedgerInsert(
                operationID: operationID, actorID: actorID, carrierID: carrierID,
                subjectID: representationID.rawValue, kind: "CARRIER_REPRESENTATION_REVISE",
                baseRevision: expectedRevision, observedRevision: resulting,
                outcome: .applied, fromVersion: fromVersion, resultingVersion: String(resulting)
            )
            guard let updated = try uaCarrierRow(carrierID: carrierID) else {
                throw UAOperationError.carrierNotFound(carrierID)
            }
            return .applied(updated)
        }
        switch casResult {
        case .applied(let carrier):
            return (carrier, .applied)
        case .replayed(let carrier, let outcome):
            return (carrier, outcome)
        case .conflict(let observed):
            try withTransaction {
                try uaLedgerInsert(
                    operationID: operationID, actorID: actorID, carrierID: carrierID,
                    subjectID: representationID.rawValue, kind: "CARRIER_REPRESENTATION_REVISE",
                    baseRevision: expectedRevision, observedRevision: observed,
                    outcome: .conflict, fromVersion: fromVersion, resultingVersion: nil
                )
            }
            throw UAOperationError.staleRevision(expected: expectedRevision, observed: observed)
        }
    }

    // MARK: MA-6 / MA-7 session append (carrier-side allocation)

    /// Concurrent-safe session append: the CARRIER allocates the sequence
    /// inside the append transaction (serialized by the SQLite write lock);
    /// client timestamps are never the ordering source. `clientRef` is the
    /// idempotency key: the same (session, clientRef) always resolves to
    /// the one allocated event; the same `operationID` replays the recorded
    /// outcome with zero new effects (MA-7 / I24).
    func uaAppendSessionEvent(
        carrierID: String,
        kind: String,
        payload: Data,
        occurredAt: Date,
        actorID: String,
        operationID: String,
        clientRef: String
    ) async throws -> UASessionAppendResult {
        let eventID = UUID().uuidString
        let result: UASessionAppendResult = try withTransaction {
            // 1) operation-id replay (MA-7): return the recorded outcome.
            if let prior = try uaLedgerRow(operationID: operationID) {
                if let subject = prior.subjectID,
                   let event = try uaSessionEvent(sessionID: subject, operationID: operationID) {
                    let carrier = try uaCarrierRow(carrierID: carrierID)
                    return UASessionAppendResult(
                        event: event, outcome: .replayed, carrierRevision: carrier?.revision ?? 0
                    )
                }
            }
            guard let carrier = try uaCarrierRow(carrierID: carrierID) else {
                throw UAOperationError.carrierNotFound(carrierID)
            }
            // 2) client-ref dedupe (MA-6): same (session, clientRef) = one
            // event regardless of which operation retries it.
            let existing: (eventID: String, sequence: Int)? = try query(
                "SELECT event_id, sequence FROM ua_session_client_refs WHERE session_id=? AND client_ref=?",
                bind: {
                    $0.bindText(1, carrierID)
                    $0.bindText(2, clientRef)
                },
                read: { ($0.text(0), $0.int(1)) }
            ).first
            if let existing,
               let event = try uaSessionEventByID(eventID: existing.eventID) {
                try uaLedgerInsert(
                    operationID: operationID, actorID: actorID, carrierID: carrierID,
                    subjectID: carrierID, kind: "SESSION_APPEND", baseRevision: carrier.revision,
                    observedRevision: carrier.revision, outcome: .replayed,
                    fromVersion: nil, resultingVersion: "seq:\(existing.sequence)"
                )
                return UASessionAppendResult(
                    event: event, outcome: .replayed, carrierRevision: carrier.revision
                )
            }
            // 3) carrier-side sequence allocation (serialized in this
            // IMMEDIATE transaction) — gapless, never renumbered.
            let sequence = try query(
                "SELECT COALESCE(MAX(sequence), -1) + 1 FROM session_events WHERE session_id=?",
                bind: { $0.bindText(1, carrierID) },
                read: { $0.int(0) }
            ).first ?? 0
            let now = Date()
            try statement("""
              INSERT INTO session_events(session_id, sequence, event_id, kind, payload,
                occurred_at, produced_at, produced_by, source) VALUES (?,?,?,?,?,?,?,?,?)
            """, bind: {
                $0.bindText(1, carrierID)
                $0.bindInt(2, sequence)
                $0.bindText(3, eventID)
                $0.bindText(4, kind)
                $0.bindBlob(5, payload)
                $0.bindDouble(6, occurredAt.timeIntervalSince1970)
                $0.bindDouble(7, now.timeIntervalSince1970)
                $0.bindText(8, actorID)
                $0.bindTextOpt(9, nil)
            })
            try statement("""
              INSERT INTO ua_session_client_refs(session_id, client_ref, event_id, sequence)
              VALUES (?,?,?,?)
            """, bind: {
                $0.bindText(1, carrierID)
                $0.bindText(2, clientRef)
                $0.bindText(3, eventID)
                $0.bindInt(4, sequence)
            })
            try statement(
                "UPDATE carriers SET revision=revision+1 WHERE carrier_id=?",
                bind: { $0.bindText(1, carrierID) }
            )
            let newRevision = carrier.revision + 1
            try uaLedgerInsert(
                operationID: operationID, actorID: actorID, carrierID: carrierID,
                subjectID: carrierID, kind: "SESSION_APPEND", baseRevision: carrier.revision,
                observedRevision: newRevision, outcome: .applied,
                fromVersion: nil, resultingVersion: "seq:\(sequence)"
            )
            let event = CarrierSessionEvent(
                eventID: CarrierSessionEventID(rawValue: eventID),
                sessionID: CarrierSessionID(rawValue: carrierID),
                sequence: sequence,
                kind: kind,
                payload: payload,
                occurredAt: occurredAt,
                provenance: CarrierProvenance(producedAt: now, producedBy: actorID, source: nil)
            )
            return UASessionAppendResult(
                event: event, outcome: .applied, carrierRevision: newRevision
            )
        }
        // Unknown-outcome boundary (MA-DS-1 step 8 / crash window UA-C1):
        // committed but the actor may never have seen the acknowledgement.
        CrashGate.trap("UA-C1")
        return result
    }

    // MARK: CC-5 mapping (§3 closed loop)

    /// Append a CC-5 mapping entry (append-only; corrections are new
    /// entries). Bumps the carrier revision so derived-index staleness is
    /// observable (MA-9).
    func uaRecordMapping(
        informationID: CarrierInformationID,
        carrierID: String,
        recordID: String,
        representationID: String?,
        fromVersion: String?,
        actorID: String,
        operationID: String
    ) async throws -> UAMappingRecord {
        try withTransaction {
            if let prior = try uaLedgerRow(operationID: operationID) {
                let rows = try query(
                    "SELECT mapping_id FROM ua_mapping WHERE operation_id=?",
                    bind: { $0.bindText(1, operationID) },
                    read: { $0.text(0) }
                )
                if let mappingID = rows.first,
                   let mapping = try uaMappingRow(mappingID: mappingID) {
                    return mapping
                }
            }
            guard try uaCarrierRow(carrierID: carrierID) != nil else {
                throw UAOperationError.carrierNotFound(carrierID)
            }
            let mappingID = UUID().uuidString
            let now = Date()
            try statement("""
              INSERT INTO ua_mapping(mapping_id, information_id, carrier_id, record_id,
                representation_id, actor_id, operation_id, from_version, mapped_at)
              VALUES (?,?,?,?,?,?,?,?,?)
            """, bind: {
                $0.bindText(1, mappingID)
                $0.bindText(2, informationID.rawValue)
                $0.bindText(3, carrierID)
                $0.bindText(4, recordID)
                $0.bindTextOpt(5, representationID)
                $0.bindText(6, actorID)
                $0.bindText(7, operationID)
                $0.bindTextOpt(8, fromVersion)
                $0.bindDouble(9, now.timeIntervalSince1970)
            })
            try statement(
                "UPDATE carriers SET revision=revision+1 WHERE carrier_id=?",
                bind: { $0.bindText(1, carrierID) }
            )
            let revision = (try uaCarrierRow(carrierID: carrierID))?.revision ?? 0
            try uaLedgerInsert(
                operationID: operationID, actorID: actorID, carrierID: carrierID,
                subjectID: informationID.rawValue, kind: "MAPPING", baseRevision: revision - 1,
                observedRevision: revision, outcome: .applied,
                fromVersion: fromVersion, resultingVersion: String(revision)
            )
            guard let mapping = try uaMappingRow(mappingID: mappingID) else {
                throw UAOperationError.carrierNotFound(carrierID)
            }
            return mapping
        }
    }

    // MARK: MA-10 snapshot / read version

    /// One committed WAL snapshot across carrier row, ordered events, and
    /// mapping rows; `readVersion` is the carrier revision every object in
    /// the snapshot observes. A "seemingly legal but never-existed" mixed
    /// state is not producible from this view (I22).
    func uaConsistentSnapshot(carrierID: String) async throws -> UACarrierSnapshot {
        try withReadSnapshot {
            let carrier = try uaCarrierRow(carrierID: carrierID)
            let events: [CarrierSessionEvent] = try query(
                """
                SELECT session_id, sequence, event_id, kind, payload, occurred_at,
                  produced_at, produced_by, source FROM session_events
                WHERE session_id=? ORDER BY sequence
                """,
                bind: { $0.bindText(1, carrierID) },
                read: Self.uaReadEvent
            )
            let mappings: [UAMappingRecord] = try query(
                """
                SELECT mapping_id, information_id, carrier_id, record_id, representation_id,
                  actor_id, operation_id, from_version, mapped_at FROM ua_mapping
                WHERE carrier_id=? ORDER BY rowid
                """,
                bind: { $0.bindText(1, carrierID) },
                read: Self.uaReadMapping
            )
            return UACarrierSnapshot(
                carrier: carrier,
                events: events,
                mappings: mappings,
                readVersion: carrier?.revision ?? 0
            )
        }
    }

    // MARK: MA-9 derived index isolation + rebuild completeness

    /// Index one document and record its IndexSource tracking row
    /// (source revision + build version = carrier revision at build).
    func uaIndexDocument(
        informationID: CarrierInformationID,
        carrierID: String,
        revisionID: CarrierRevisionID,
        title: String?,
        text: String
    ) async throws {
        try withTransaction {
            let buildVersion = try uaCarrierRow(carrierID: carrierID)?.revision ?? 0
            try statement(
                "DELETE FROM search_fts WHERE information_id=?",
                bind: { $0.bindText(1, informationID.rawValue) }
            )
            try statement(
                "INSERT INTO search_fts(information_id, revision_id, title, text) VALUES (?,?,?,?)",
                bind: {
                    $0.bindText(1, informationID.rawValue)
                    $0.bindText(2, revisionID.rawValue)
                    $0.bindTextOpt(3, title)
                    $0.bindText(4, text)
                }
            )
            try statement("""
              INSERT OR REPLACE INTO ua_index_builds(information_id, carrier_id,
                indexed_revision, build_version, built_at) VALUES (?,?,?,?,?)
            """, bind: {
                $0.bindText(1, informationID.rawValue)
                $0.bindText(2, carrierID)
                $0.bindText(3, revisionID.rawValue)
                $0.bindInt(4, buildVersion)
                $0.bindDouble(5, Date().timeIntervalSince1970)
            })
        }
    }

    /// MA-9 staleness detection: a carrier's index is stale when the
    /// carrier revision has advanced past the build version of any indexed
    /// document mapped to it (or a mapped information has no build row).
    func uaIndexStaleness() async throws -> [UAStaleIndexEntry] {
        try query(
            """
            SELECT m.carrier_id, m.information_id, c.revision, b.build_version
            FROM ua_mapping m
            JOIN carriers c ON c.carrier_id = m.carrier_id
            LEFT JOIN ua_index_builds b ON b.information_id = m.information_id
            WHERE b.build_version IS NULL OR b.build_version < c.revision
            GROUP BY m.carrier_id, m.information_id
            """,
            read: {
                UAStaleIndexEntry(
                    carrierID: $0.text(0),
                    informationID: $0.text(1),
                    carrierRevision: $0.int(2),
                    indexedBuildVersion: $0.intOpt(3)
                )
            }
        )
    }

    /// Full rebuild from the supplied authority-derived documents: clears
    /// the index AND its build tracking, reindexes at the current carrier
    /// revisions. Index writes never touch authority tables (MA-9).
    func uaRebuildIndex(
        documents: [(informationID: CarrierInformationID, carrierID: String,
                     revisionID: CarrierRevisionID, title: String?, text: String)]
    ) async throws -> UARebuildReport {
        try withTransaction {
            try statement("DELETE FROM search_fts")
            try statement("DELETE FROM ua_index_builds")
            CrashGate.trap("UA-C3")
            for document in documents {
                let buildVersion = try uaCarrierRow(carrierID: document.carrierID)?.revision ?? 0
                try statement(
                    "INSERT INTO search_fts(information_id, revision_id, title, text) VALUES (?,?,?,?)",
                    bind: {
                        $0.bindText(1, document.informationID.rawValue)
                        $0.bindText(2, document.revisionID.rawValue)
                        $0.bindTextOpt(3, document.title)
                        $0.bindText(4, document.text)
                    }
                )
                try statement("""
                  INSERT INTO ua_index_builds(information_id, carrier_id, indexed_revision,
                    build_version, built_at) VALUES (?,?,?,?,?)
                """, bind: {
                    $0.bindText(1, document.informationID.rawValue)
                    $0.bindText(2, document.carrierID)
                    $0.bindText(3, document.revisionID.rawValue)
                    $0.bindInt(4, buildVersion)
                    $0.bindDouble(5, Date().timeIntervalSince1970)
                })
            }
        }
        return UARebuildReport(documentsIndexed: documents.count, completedAt: Date())
    }

    func uaSearch(_ queryText: String, limit: Int) async throws -> [CarrierSearchResult] {
        try query(
            """
            SELECT information_id, revision_id, bm25(search_fts) AS rank
            FROM search_fts WHERE search_fts MATCH ? ORDER BY rank LIMIT ?
            """,
            bind: {
                $0.bindText(1, queryText)
                $0.bindInt(2, limit)
            },
            read: {
                CarrierSearchResult(
                    informationID: CarrierInformationID(rawValue: $0.text(0)),
                    revisionID: CarrierRevisionID(rawValue: $0.text(1)),
                    score: -$0.double(2)
                )
            }
        )
    }

    // MARK: Evidence surfaces (ledger / mappings / carriers)

    func uaOperationLedger() async throws -> [UAOperationRecord] {
        try query(
            """
            SELECT operation_id, actor_id, carrier_id, subject_id, kind, base_revision,
              observed_revision, outcome, from_version, resulting_version, recorded_at
            FROM ua_operations ORDER BY rowid
            """,
            read: Self.uaReadLedger
        )
    }

    func uaMappings() async throws -> [UAMappingRecord] {
        try query(
            """
            SELECT mapping_id, information_id, carrier_id, record_id, representation_id,
              actor_id, operation_id, from_version, mapped_at FROM ua_mapping ORDER BY rowid
            """,
            read: Self.uaReadMapping
        )
    }

    func uaCarrier(carrierID: String) async throws -> UACarrier? {
        try query(
            "SELECT carrier_id, kind, locator_scheme, locator_value, revision, created_at, created_by FROM carriers WHERE carrier_id=?",
            bind: { $0.bindText(1, carrierID) },
            read: Self.uaReadCarrier
        ).first
    }

    /// I21 evidence: APPLIED ledger rows missing any provenance component.
    func uaDanglingProvenanceCount() async throws -> Int {
        try query(
            """
            SELECT COUNT(*) FROM ua_operations
            WHERE outcome='APPLIED' AND (
              actor_id IS NULL OR actor_id='' OR carrier_id IS NULL OR
              observed_revision IS NULL OR resulting_version IS NULL)
            """,
            read: { $0.int(0) }
        ).first ?? 0
    }

    /// Authority fingerprint for the MA-9 audit: hash of all authority
    /// table contents + entity files. Rebuild must never change this.
    func uaAuthorityFingerprint(entities: POSIXEntityStore?) async throws -> String {
        var material = ""
        for table in ["carriers", "revisions", "representations", "locators",
                      "relations", "pins", "session_events", "session_summaries",
                      "availability", "ua_mapping", "ua_operations",
                      "ua_session_client_refs"] {
            let rows = try query(
                "SELECT * FROM \(table)",
                read: { stmt -> String in
                    var cells: [String] = []
                    let columnCount = sqlite3_column_count(stmt.handlePointer)
                    for column in 0..<columnCount {
                        if sqlite3_column_type(stmt.handlePointer, column) == SQLITE_NULL {
                            cells.append("∅")
                        } else {
                            cells.append(stmt.text(column))
                        }
                    }
                    return cells.joined(separator: "\u{1F}")
                }
            )
            material += "[\(table)]" + rows.joined(separator: "\u{1E}")
        }
        if let entities {
            let digests = try POSIXEntityStore.uaEntityFileDigests(root: entities.entitiesRoot)
            material += "[entities]" + digests.sorted().joined(separator: "\u{1E}")
        }
        return sha256Hex(Data(material.utf8))
    }

    // MARK: Internals (actor-isolated)

    func uaMintCarrierID() throws -> String {
        // UUIDv4, registry-minted (U-A recipe under the CC-1/A-1
        // obligation). Collision with an existing row fails the PRIMARY
        // KEY, which surfaces as a failed statement — never a silent merge.
        let candidate = UUID().uuidString
        if try uaCarrierRow(carrierID: candidate) != nil {
            return try uaMintCarrierID()
        }
        return candidate
    }

    func uaCarrierRow(carrierID: String) throws -> UACarrier? {
        try query(
            "SELECT carrier_id, kind, locator_scheme, locator_value, revision, created_at, created_by FROM carriers WHERE carrier_id=?",
            bind: { $0.bindText(1, carrierID) },
            read: Self.uaReadCarrier
        ).first
    }

    func uaLedgerRow(operationID: String) throws -> UAOperationRecord? {
        try query(
            """
            SELECT operation_id, actor_id, carrier_id, subject_id, kind, base_revision,
              observed_revision, outcome, from_version, resulting_version, recorded_at
            FROM ua_operations WHERE operation_id=?
            """,
            bind: { $0.bindText(1, operationID) },
            read: Self.uaReadLedger
        ).first
    }

    func uaMappingRow(mappingID: String) throws -> UAMappingRecord? {
        try query(
            """
            SELECT mapping_id, information_id, carrier_id, record_id, representation_id,
              actor_id, operation_id, from_version, mapped_at FROM ua_mapping WHERE mapping_id=?
            """,
            bind: { $0.bindText(1, mappingID) },
            read: Self.uaReadMapping
        ).first
    }

    func uaSessionEvent(sessionID: String, operationID: String) throws -> CarrierSessionEvent? {
        let sequence = try query(
            "SELECT resulting_version FROM ua_operations WHERE operation_id=?",
            bind: { $0.bindText(1, operationID) },
            read: { $0.text(0) }
        ).first.flatMap { entry -> Int? in
            entry.hasPrefix("seq:") ? Int(entry.dropFirst(4)) : nil
        }
        guard let sequence else { return nil }
        return try query(
            """
            SELECT session_id, sequence, event_id, kind, payload, occurred_at,
              produced_at, produced_by, source FROM session_events
            WHERE session_id=? AND sequence=?
            """,
            bind: {
                $0.bindText(1, sessionID)
                $0.bindInt(2, sequence)
            },
            read: Self.uaReadEvent
        ).first
    }

    func uaSessionEventByID(eventID: String) throws -> CarrierSessionEvent? {
        try query(
            """
            SELECT session_id, sequence, event_id, kind, payload, occurred_at,
              produced_at, produced_by, source FROM session_events WHERE event_id=?
            """,
            bind: { $0.bindText(1, eventID) },
            read: Self.uaReadEvent
        ).first
    }

    func uaLedgerInsert(
        operationID: String, actorID: String, carrierID: String?, subjectID: String?,
        kind: String, baseRevision: Int?, observedRevision: Int?,
        outcome: UAOperationOutcome, fromVersion: String?, resultingVersion: String?
    ) throws {
        try statement("""
          INSERT INTO ua_operations(operation_id, actor_id, carrier_id, subject_id, kind,
            base_revision, observed_revision, outcome, from_version, resulting_version, recorded_at)
          VALUES (?,?,?,?,?,?,?,?,?,?,?)
        """, bind: {
            $0.bindText(1, operationID)
            $0.bindText(2, actorID)
            $0.bindTextOpt(3, carrierID)
            $0.bindTextOpt(4, subjectID)
            $0.bindText(5, kind)
            $0.bindIntOpt(6, baseRevision)
            $0.bindIntOpt(7, observedRevision)
            $0.bindText(8, outcome.rawValue)
            $0.bindTextOpt(9, fromVersion)
            $0.bindTextOpt(10, resultingVersion)
            $0.bindDouble(11, Date().timeIntervalSince1970)
        })
    }

    static func uaReadCarrier(_ stmt: Stmt) -> UACarrier {
        UACarrier(
            carrierID: stmt.text(0),
            kind: UACarrierKind(rawValue: stmt.text(1)) ?? .file,
            locatorScheme: stmt.textOpt(2),
            locatorValue: stmt.textOpt(3),
            revision: stmt.int(4),
            createdAt: Date(timeIntervalSince1970: stmt.double(5)),
            createdBy: stmt.text(6)
        )
    }

    static func uaReadLedger(_ stmt: Stmt) -> UAOperationRecord {
        UAOperationRecord(
            operationID: stmt.text(0),
            actorID: stmt.text(1),
            carrierID: stmt.textOpt(2),
            subjectID: stmt.textOpt(3),
            kind: stmt.text(4),
            baseRevision: stmt.intOpt(5),
            observedRevision: stmt.intOpt(6),
            outcome: UAOperationOutcome(rawValue: stmt.text(7)) ?? .applied,
            fromVersion: stmt.textOpt(8),
            resultingVersion: stmt.textOpt(9),
            recordedAt: Date(timeIntervalSince1970: stmt.double(10))
        )
    }

    static func uaReadMapping(_ stmt: Stmt) -> UAMappingRecord {
        UAMappingRecord(
            mappingID: stmt.text(0),
            informationID: stmt.text(1),
            carrierID: stmt.text(2),
            recordID: stmt.text(3),
            representationID: stmt.textOpt(4),
            actorID: stmt.text(5),
            operationID: stmt.text(6),
            fromVersion: stmt.textOpt(7),
            mappedAt: Date(timeIntervalSince1970: stmt.double(8))
        )
    }

    static func uaReadEvent(_ stmt: Stmt) -> CarrierSessionEvent {
        CarrierSessionEvent(
            eventID: CarrierSessionEventID(rawValue: stmt.text(2)),
            sessionID: CarrierSessionID(rawValue: stmt.text(0)),
            sequence: stmt.int(1),
            kind: stmt.text(3),
            payload: stmt.blob(4),
            occurredAt: Date(timeIntervalSince1970: stmt.double(5)),
            provenance: CarrierInterface_provenance(stmt, 6, 7, 8)
        )
    }
}

extension POSIXEntityStore {
    static func uaEntityFileDigests(root: URL) throws -> [String] {
        var digests: [String] = []
        guard let shards = try? FileManager.default.contentsOfDirectory(atPath: root.path) else {
            return digests
        }
        for shard in shards {
            let shardURL = root.appendingPathComponent(shard)
            let files = (try? FileManager.default.contentsOfDirectory(atPath: shardURL.path)) ?? []
            for file in files where !file.hasPrefix(".") {
                let url = shardURL.appendingPathComponent(file)
                if let bytes = FileManager.default.contents(atPath: url.path) {
                    digests.append(sha256Hex(bytes))
                }
            }
        }
        return digests
    }
}

extension Stmt {
    func bindIntOpt(_ index: Int32, _ value: Int?) {
        if let value {
            bindInt(index, value)
        } else {
            sqlite3_bind_null(handle, index)
        }
    }
    func intOpt(_ column: Int32) -> Int? {
        sqlite3_column_type(handle, column) == SQLITE_NULL ? nil : int(column)
    }
}
