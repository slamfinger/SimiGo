import Foundation
import CarrierInterface

// C2 — revision registry.
public struct SQLiteInformationRegistry: InformationRegistry {
    let core: SQLiteCore

    public func register(_ revision: CarrierRevision) async throws {
        try await core.run(
            "INSERT INTO revisions(revision_id, information_id, label, produced_at, produced_by, source) VALUES (?,?,?,?,?,?)",
            bind: { stmt in
                stmt.bindText(1, revision.revisionID.rawValue)
                stmt.bindText(2, revision.informationID.rawValue)
                stmt.bindTextOpt(3, revision.label)
                stmt.bindDouble(4, revision.provenance.producedAt.timeIntervalSince1970)
                stmt.bindText(5, revision.provenance.producedBy)
                stmt.bindTextOpt(6, revision.provenance.source)
            }
        )
    }

    public func revision(_ id: CarrierRevisionID) async throws -> CarrierRevision? {
        try await core.query(
            "SELECT revision_id, information_id, label, produced_at, produced_by, source FROM revisions WHERE revision_id=?",
            bind: { $0.bindText(1, id.rawValue) },
            read: Self.read
        ).first
    }

    public func revisions(for informationID: CarrierInformationID) async throws -> [CarrierRevision] {
        try await core.query(
            "SELECT revision_id, information_id, label, produced_at, produced_by, source FROM revisions WHERE information_id=? ORDER BY rowid",
            bind: { $0.bindText(1, informationID.rawValue) },
            read: Self.read
        )
    }

    public func latestRevision(for informationID: CarrierInformationID) async throws -> CarrierRevision? {
        try await core.query(
            "SELECT revision_id, information_id, label, produced_at, produced_by, source FROM revisions WHERE information_id=? ORDER BY rowid DESC LIMIT 1",
            bind: { $0.bindText(1, informationID.rawValue) },
            read: Self.read
        ).first
    }

    static func read(_ stmt: Stmt) -> CarrierRevision {
        CarrierRevision(
            revisionID: CarrierRevisionID(rawValue: stmt.text(0)),
            informationID: CarrierInformationID(rawValue: stmt.text(1)),
            label: stmt.textOpt(2),
            provenance: CarrierInterface_provenance(stmt, 3, 4, 5)
        )
    }
}

func CarrierInterface_provenance(_ stmt: Stmt, _ at: Int32, _ by: Int32, _ source: Int32) -> CarrierProvenance {
    CarrierProvenance(
        producedAt: Date(timeIntervalSince1970: stmt.double(at)),
        producedBy: stmt.text(by),
        source: stmt.textOpt(source)
    )
}

// C3 — locator index with atomic move handoff.
public struct SQLiteLocatorIndex: LocatorIndex {
    let core: SQLiteCore

    public func assign(_ record: CarrierLocatorRecord) async throws {
        try await core.assignLocator(record)
    }

    public func retire(_ id: CarrierLocatorID, at date: Date) async throws {
        try await core.retireLocator(id.rawValue, retiredAt: date)
    }

    public func current(
        for informationID: CarrierInformationID,
        revisionID: CarrierRevisionID?
    ) async throws -> CarrierLocatorRecord? {
        let sql = """
          SELECT locator_id, information_id, revision_id, representation_id, scheme, value, created_at, retired_at
          FROM locators WHERE information_id=? AND retired_at IS NULL
        """
        var rows = try await core.query(sql, bind: { $0.bindText(1, informationID.rawValue) }, read: Self.read)
        if let revisionID {
            rows = rows.filter { $0.revisionID == revisionID }
        }
        return rows.max { $0.createdAt < $1.createdAt }
    }

    public func history(for informationID: CarrierInformationID) async throws -> [CarrierLocatorRecord] {
        try await core.query(
            """
            SELECT locator_id, information_id, revision_id, representation_id, scheme, value, created_at, retired_at
            FROM locators WHERE information_id=? ORDER BY created_at
            """,
            bind: { $0.bindText(1, informationID.rawValue) },
            read: Self.read
        )
    }

    static func read(_ stmt: Stmt) -> CarrierLocatorRecord {
        CarrierLocatorRecord(
            locatorID: CarrierLocatorID(rawValue: stmt.text(0)),
            informationID: CarrierInformationID(rawValue: stmt.text(1)),
            revisionID: CarrierRevisionID(rawValue: stmt.text(2)),
            representationID: CarrierRepresentationID(rawValue: stmt.text(3)),
            locator: CarrierLocator(scheme: stmt.text(4), value: stmt.text(5)),
            createdAt: Date(timeIntervalSince1970: stmt.double(6)),
            retiredAt: stmt.doubleOpt(7).map { Date(timeIntervalSince1970: $0) }
        )
    }
}

// C4 — relations and historical pins.
public struct SQLiteRelationHistoryStore: RelationHistoryStore {
    let core: SQLiteCore

    public func append(_ relation: CarrierRelation) async throws {
        await core.bumpRelation()
        CrashGate.trap("F5-\(await core.relationCount())")
        try await core.run(
            "INSERT INTO relations(relation_id, subject, predicate, object, produced_at, produced_by, source) VALUES (?,?,?,?,?,?,?)",
            bind: { stmt in
                stmt.bindText(1, relation.relationID.rawValue)
                stmt.bindText(2, relation.subject.rawValue)
                stmt.bindText(3, relation.predicate)
                stmt.bindText(4, relation.object.rawValue)
                stmt.bindDouble(5, relation.provenance.producedAt.timeIntervalSince1970)
                stmt.bindText(6, relation.provenance.producedBy)
                stmt.bindTextOpt(7, relation.provenance.source)
            }
        )
    }

    public func relation(_ id: CarrierRelationID) async throws -> CarrierRelation? {
        try await core.query(
            "SELECT relation_id, subject, predicate, object, produced_at, produced_by, source FROM relations WHERE relation_id=?",
            bind: { $0.bindText(1, id.rawValue) },
            read: Self.read
        ).first
    }

    public func relations(involving informationID: CarrierInformationID) async throws -> [CarrierRelation] {
        try await core.query(
            "SELECT relation_id, subject, predicate, object, produced_at, produced_by, source FROM relations WHERE subject=? OR object=?",
            bind: {
                $0.bindText(1, informationID.rawValue)
                $0.bindText(2, informationID.rawValue)
            },
            read: Self.read
        )
    }

    public func pin(_ historicalPin: CarrierHistoricalPin) async throws {
        try await core.run(
            "INSERT INTO pins(pin_id, information_id, revision_id, representation_id, digest, locator_scheme, locator_value, label, pinned_at) VALUES (?,?,?,?,?,?,?,?,?)",
            bind: { stmt in
                stmt.bindText(1, historicalPin.pinID.rawValue)
                stmt.bindText(2, historicalPin.informationID.rawValue)
                stmt.bindText(3, historicalPin.revisionID.rawValue)
                stmt.bindText(4, historicalPin.representationID.rawValue)
                stmt.bindText(5, historicalPin.digest)
                stmt.bindTextOpt(6, historicalPin.locator?.scheme)
                stmt.bindTextOpt(7, historicalPin.locator?.value)
                stmt.bindTextOpt(8, historicalPin.label)
                stmt.bindDouble(9, historicalPin.pinnedAt.timeIntervalSince1970)
            }
        )
    }

    public func pin(_ id: CarrierPinID) async throws -> CarrierHistoricalPin? {
        try await core.query(
            "SELECT pin_id, information_id, revision_id, representation_id, digest, locator_scheme, locator_value, label, pinned_at FROM pins WHERE pin_id=?",
            bind: { $0.bindText(1, id.rawValue) },
            read: Self.readPin
        ).first
    }

    public func pins(for informationID: CarrierInformationID) async throws -> [CarrierHistoricalPin] {
        try await core.query(
            "SELECT pin_id, information_id, revision_id, representation_id, digest, locator_scheme, locator_value, label, pinned_at FROM pins WHERE information_id=?",
            bind: { $0.bindText(1, informationID.rawValue) },
            read: Self.readPin
        )
    }

    static func read(_ stmt: Stmt) -> CarrierRelation {
        CarrierRelation(
            relationID: CarrierRelationID(rawValue: stmt.text(0)),
            subject: CarrierInformationID(rawValue: stmt.text(1)),
            predicate: stmt.text(2),
            object: CarrierInformationID(rawValue: stmt.text(3)),
            provenance: CarrierInterface_provenance(stmt, 4, 5, 6)
        )
    }

    static func readPin(_ stmt: Stmt) -> CarrierHistoricalPin {
        let scheme = stmt.textOpt(5)
        let value = stmt.textOpt(6)
        return CarrierHistoricalPin(
            pinID: CarrierPinID(rawValue: stmt.text(0)),
            informationID: CarrierInformationID(rawValue: stmt.text(1)),
            revisionID: CarrierRevisionID(rawValue: stmt.text(2)),
            representationID: CarrierRepresentationID(rawValue: stmt.text(3)),
            digest: stmt.text(4),
            locator: scheme.map { CarrierLocator(scheme: $0, value: value ?? "") },
            label: stmt.textOpt(7),
            pinnedAt: Date(timeIntervalSince1970: stmt.double(8))
        )
    }
}

// C5 — session events and summaries.
public struct SQLiteSessionInformationStore: SessionInformationStore {
    let core: SQLiteCore

    public func append(_ event: CarrierSessionEvent) async throws {
        await core.bumpSession()
        CrashGate.trap("F6-\(await core.sessionCount())")
        try await core.run(
            "INSERT INTO session_events(session_id, sequence, event_id, kind, payload, occurred_at, produced_at, produced_by, source) VALUES (?,?,?,?,?,?,?,?,?)",
            bind: { stmt in
                stmt.bindText(1, event.sessionID.rawValue)
                stmt.bindInt(2, event.sequence)
                stmt.bindText(3, event.eventID.rawValue)
                stmt.bindText(4, event.kind)
                stmt.bindBlob(5, event.payload)
                stmt.bindDouble(6, event.occurredAt.timeIntervalSince1970)
                stmt.bindDouble(7, event.provenance.producedAt.timeIntervalSince1970)
                stmt.bindText(8, event.provenance.producedBy)
                stmt.bindTextOpt(9, event.provenance.source)
            }
        )
    }

    public func events(in sessionID: CarrierSessionID, after sequence: Int) async throws -> [CarrierSessionEvent] {
        try await core.query(
            "SELECT session_id, sequence, event_id, kind, payload, occurred_at, produced_at, produced_by, source FROM session_events WHERE session_id=? AND sequence>? ORDER BY sequence",
            bind: {
                $0.bindText(1, sessionID.rawValue)
                $0.bindInt(2, sequence)
            },
            read: Self.readEvent
        )
    }

    public func addSummary(_ summary: CarrierSessionSummary) async throws {
        try await core.run(
            "INSERT INTO session_summaries(summary_id, session_id, through_sequence, payload, created_at, produced_at, produced_by, source) VALUES (?,?,?,?,?,?,?,?)",
            bind: { stmt in
                stmt.bindText(1, summary.summaryID.rawValue)
                stmt.bindText(2, summary.sessionID.rawValue)
                stmt.bindInt(3, summary.throughSequence)
                stmt.bindBlob(4, summary.payload)
                stmt.bindDouble(5, summary.createdAt.timeIntervalSince1970)
                stmt.bindDouble(6, summary.provenance.producedAt.timeIntervalSince1970)
                stmt.bindText(7, summary.provenance.producedBy)
                stmt.bindTextOpt(8, summary.provenance.source)
            }
        )
    }

    public func summaries(in sessionID: CarrierSessionID) async throws -> [CarrierSessionSummary] {
        try await core.query(
            "SELECT summary_id, session_id, through_sequence, payload, created_at, produced_at, produced_by, source FROM session_summaries WHERE session_id=?",
            bind: { $0.bindText(1, sessionID.rawValue) },
            read: Self.readSummary
        )
    }

    static func readEvent(_ stmt: Stmt) -> CarrierSessionEvent {
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

    static func readSummary(_ stmt: Stmt) -> CarrierSessionSummary {
        CarrierSessionSummary(
            summaryID: CarrierSummaryID(rawValue: stmt.text(0)),
            sessionID: CarrierSessionID(rawValue: stmt.text(1)),
            throughSequence: stmt.int(2),
            payload: stmt.blob(3),
            createdAt: Date(timeIntervalSince1970: stmt.double(4)),
            provenance: CarrierInterface_provenance(stmt, 5, 6, 7)
        )
    }
}

// C7 — availability observations.
public struct SQLiteAvailabilityStore: AvailabilityStore {
    let core: SQLiteCore

    public func record(_ record: CarrierAvailabilityRecord) async throws {
        try await core.run(
            "INSERT INTO availability(information_id, revision_id, representation_id, state, reason, observed_at) VALUES (?,?,?,?,?,?)",
            bind: { stmt in
                stmt.bindText(1, record.informationID.rawValue)
                stmt.bindText(2, record.revisionID.rawValue)
                stmt.bindText(3, record.representationID.rawValue)
                stmt.bindText(4, record.state.rawValue)
                stmt.bindTextOpt(5, record.reason)
                stmt.bindDouble(6, record.observedAt.timeIntervalSince1970)
            }
        )
    }

    public func current(
        informationID: CarrierInformationID,
        representationID: CarrierRepresentationID?
    ) async throws -> CarrierAvailabilityRecord? {
        var rows = try await core.query(
            "SELECT information_id, revision_id, representation_id, state, reason, observed_at FROM availability WHERE information_id=? ORDER BY seq",
            bind: { $0.bindText(1, informationID.rawValue) },
            read: Self.read
        )
        if let representationID {
            rows = rows.filter { $0.representationID == representationID }
        }
        return rows.last
    }

    public func history(for informationID: CarrierInformationID) async throws -> [CarrierAvailabilityRecord] {
        try await core.query(
            "SELECT information_id, revision_id, representation_id, state, reason, observed_at FROM availability WHERE information_id=? ORDER BY seq",
            bind: { $0.bindText(1, informationID.rawValue) },
            read: Self.read
        )
    }

    static func read(_ stmt: Stmt) -> CarrierAvailabilityRecord {
        CarrierAvailabilityRecord(
            informationID: CarrierInformationID(rawValue: stmt.text(0)),
            revisionID: CarrierRevisionID(rawValue: stmt.text(1)),
            representationID: CarrierRepresentationID(rawValue: stmt.text(2)),
            state: CarrierAvailability(rawValue: stmt.text(3)) ?? .detached,
            reason: stmt.textOpt(4),
            observedAt: Date(timeIntervalSince1970: stmt.double(5))
        )
    }
}

// C6 — FTS5 derived search. Registry tables are the rebuild authority.
public struct SQLiteDerivedSearchIndex: DerivedSearchIndex {
    let core: SQLiteCore

    public func upsert(_ document: CarrierSearchDocument) async throws {
        CrashGate.trap("F2")
        // UA-IF-3b: the legacy (pre-U-A) path owns ONLY its NULL-carrier_id
        // rows — a legacy upsert must never erase U-A carrier-scoped
        // searchable representations of the same information.
        try await core.run(
            "DELETE FROM search_fts WHERE information_id=? AND carrier_id IS NULL",
            bind: { $0.bindText(1, document.informationID.rawValue) }
        )
        try await core.run(
            "INSERT INTO search_fts(information_id, carrier_id, revision_id, title, text) VALUES (?,NULL,?,?,?)",
            bind: { stmt in
                stmt.bindText(1, document.informationID.rawValue)
                stmt.bindText(2, document.revisionID.rawValue)
                stmt.bindTextOpt(3, document.title)
                stmt.bindText(4, document.text)
            }
        )
    }

    public func delete(informationID: CarrierInformationID) async throws {
        // UA-IF-3b: legacy scope only (NULL carrier_id rows).
        try await core.run(
            "DELETE FROM search_fts WHERE information_id=? AND carrier_id IS NULL",
            bind: { $0.bindText(1, informationID.rawValue) }
        )
    }

    public func search(_ query: String, limit: Int) async throws -> [CarrierSearchResult] {
        try await core.query(
            """
            SELECT information_id, revision_id, bm25(search_fts) AS rank
            FROM search_fts WHERE search_fts MATCH ? ORDER BY rank LIMIT ?
            """,
            bind: {
                $0.bindText(1, query)
                $0.bindInt(2, limit)
            },
            read: { stmt in
                CarrierSearchResult(
                    informationID: CarrierInformationID(rawValue: stmt.text(0)),
                    revisionID: CarrierRevisionID(rawValue: stmt.text(1)),
                    score: -stmt.double(2)
                )
            }
        )
    }

    public func clear() async throws {
        try await core.run("DELETE FROM search_fts")
    }

    public func rebuild(with documents: [CarrierSearchDocument]) async throws -> CarrierRebuildReport {
        try await core.run("DELETE FROM search_fts")
        CrashGate.trap("F7")
        for document in documents {
            try await core.run(
                "INSERT INTO search_fts(information_id, carrier_id, revision_id, title, text) VALUES (?,NULL,?,?,?)",
                bind: { stmt in
                    stmt.bindText(1, document.informationID.rawValue)
                    stmt.bindText(2, document.revisionID.rawValue)
                    stmt.bindTextOpt(3, document.title)
                    stmt.bindText(4, document.text)
                }
            )
        }
        return CarrierRebuildReport(documentsIndexed: documents.count, completedAt: Date())
    }
}
