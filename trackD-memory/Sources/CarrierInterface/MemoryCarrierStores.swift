import Foundation
import CryptoKit

// Memory implementations are test/fake carriers only. They are not candidate
// backends and imply no database selection.
public enum MemoryCarrierDigest {
    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public actor MemoryInformationRegistry: InformationRegistry {
    private var revisions: [CarrierRevision] = []

    public init() {}

    public func register(_ revision: CarrierRevision) async throws {
        guard !revisions.contains(where: { $0.revisionID == revision.revisionID }) else { return }
        revisions.append(revision)
    }

    public func revision(_ id: CarrierRevisionID) async throws -> CarrierRevision? {
        revisions.first { $0.revisionID == id }
    }

    public func revisions(for informationID: CarrierInformationID) async throws -> [CarrierRevision] {
        revisions
            .filter { $0.informationID == informationID }
            .sorted { $0.provenance.producedAt < $1.provenance.producedAt }
    }

    public func latestRevision(for informationID: CarrierInformationID) async throws -> CarrierRevision? {
        try await revisions(for: informationID).last
    }
}

public actor MemoryEntityRepresentationStore: EntityRepresentationStore {
    private var contents: [CarrierRepresentationID: CarrierRepresentationContent] = [:]

    public init() {}

    public func put(_ content: CarrierRepresentationContent) async throws {
        guard contents[content.representation.representationID] == nil else { return }
        contents[content.representation.representationID] = content
    }

    public func content(_ id: CarrierRepresentationID) async throws -> CarrierRepresentationContent? {
        contents[id]
    }

    public func representations(
        for informationID: CarrierInformationID,
        revisionID: CarrierRevisionID?
    ) async throws -> [CarrierRepresentation] {
        contents.values
            .filter { $0.representation.informationID == informationID }
            .filter { revisionID == nil || $0.representation.revisionID == revisionID }
            .map(\.representation)
            .sorted { $0.createdAt < $1.createdAt }
    }

    public func allRepresentations() async throws -> [CarrierRepresentation] {
        contents.values.map(\.representation).sorted { $0.createdAt < $1.createdAt }
    }
}

public actor MemoryLocatorIndex: LocatorIndex {
    private var records: [CarrierLocatorRecord] = []

    public init() {}

    public func assign(_ record: CarrierLocatorRecord) async throws {
        guard !records.contains(where: { $0.locatorID == record.locatorID }) else { return }
        records.append(record)
    }

    public func retire(_ id: CarrierLocatorID, at date: Date) async throws {
        guard let index = records.firstIndex(where: { $0.locatorID == id }) else {
            throw CarrierInterfaceError.notFound("locator \(id.rawValue)")
        }
        let old = records[index]
        records[index] = CarrierLocatorRecord(
            locatorID: old.locatorID,
            informationID: old.informationID,
            revisionID: old.revisionID,
            representationID: old.representationID,
            locator: old.locator,
            createdAt: old.createdAt,
            retiredAt: date
        )
    }

    public func current(
        for informationID: CarrierInformationID,
        revisionID: CarrierRevisionID?
    ) async throws -> CarrierLocatorRecord? {
        records
            .filter { $0.informationID == informationID }
            .filter { $0.retiredAt == nil }
            .filter { revisionID == nil || $0.revisionID == revisionID }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    public func history(for informationID: CarrierInformationID) async throws -> [CarrierLocatorRecord] {
        records
            .filter { $0.informationID == informationID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    public func allRecords() async throws -> [CarrierLocatorRecord] {
        records.sorted { $0.createdAt < $1.createdAt }
    }
}

public actor MemoryRelationHistoryStore: RelationHistoryStore {
    private var relations: [CarrierRelation] = []
    private var pins: [CarrierHistoricalPin] = []

    public init() {}

    public func append(_ relation: CarrierRelation) async throws {
        guard !relations.contains(where: { $0.relationID == relation.relationID }) else { return }
        relations.append(relation)
    }

    public func relation(_ id: CarrierRelationID) async throws -> CarrierRelation? {
        relations.first { $0.relationID == id }
    }

    public func relations(involving informationID: CarrierInformationID) async throws -> [CarrierRelation] {
        relations.filter { $0.subject == informationID || $0.object == informationID }
    }

    public func pin(_ historicalPin: CarrierHistoricalPin) async throws {
        guard !pins.contains(where: { $0.pinID == historicalPin.pinID }) else { return }
        pins.append(historicalPin)
    }

    public func pin(_ id: CarrierPinID) async throws -> CarrierHistoricalPin? {
        pins.first { $0.pinID == id }
    }

    public func pins(for informationID: CarrierInformationID) async throws -> [CarrierHistoricalPin] {
        pins.filter { $0.informationID == informationID }
    }
}

public actor MemorySessionInformationStore: SessionInformationStore {
    private var events: [CarrierSessionEvent] = []
    private var summaries: [CarrierSessionSummary] = []

    public init() {}

    public func append(_ event: CarrierSessionEvent) async throws {
        guard !events.contains(where: { $0.eventID == event.eventID }) else { return }
        events.append(event)
    }

    public func events(
        in sessionID: CarrierSessionID,
        after sequence: Int
    ) async throws -> [CarrierSessionEvent] {
        events
            .filter { $0.sessionID == sessionID && $0.sequence > sequence }
            .sorted { $0.sequence < $1.sequence }
    }

    public func addSummary(_ summary: CarrierSessionSummary) async throws {
        guard !summaries.contains(where: { $0.summaryID == summary.summaryID }) else { return }
        summaries.append(summary)
    }

    public func summaries(in sessionID: CarrierSessionID) async throws -> [CarrierSessionSummary] {
        summaries.filter { $0.sessionID == sessionID }
    }
}

public actor MemoryDerivedSearchIndex: DerivedSearchIndex {
    private var documents: [CarrierInformationID: CarrierSearchDocument] = [:]

    public init() {}

    public func upsert(_ document: CarrierSearchDocument) async throws {
        documents[document.informationID] = document
    }

    public func delete(informationID: CarrierInformationID) async throws {
        documents.removeValue(forKey: informationID)
    }

    public func search(_ query: String, limit: Int) async throws -> [CarrierSearchResult] {
        let terms = query.lowercased().split(separator: " ").map(String.init)
        return documents.values.compactMap { document in
            let haystack = ((document.title ?? "") + " " + document.text).lowercased()
            let matches = terms.filter { haystack.contains($0) }.count
            guard !terms.isEmpty, matches > 0 else { return nil }
            return CarrierSearchResult(
                informationID: document.informationID,
                revisionID: document.revisionID,
                score: Double(matches) / Double(terms.count)
            )
        }
        .sorted { $0.score > $1.score }
        .prefix(limit)
        .map { $0 }
    }

    public func clear() async throws {
        documents.removeAll()
    }

    public func rebuild(with documents: [CarrierSearchDocument]) async throws -> CarrierRebuildReport {
        self.documents.removeAll()
        for document in documents {
            self.documents[document.informationID] = document
        }
        return CarrierRebuildReport(documentsIndexed: documents.count, completedAt: Date())
    }
}

public actor MemoryAvailabilityStore: AvailabilityStore {
    private var records: [CarrierAvailabilityRecord] = []

    public init() {}

    public func record(_ record: CarrierAvailabilityRecord) async throws {
        records.append(record)
    }

    public func current(
        informationID: CarrierInformationID,
        representationID: CarrierRepresentationID?
    ) async throws -> CarrierAvailabilityRecord? {
        records
            .filter { $0.informationID == informationID }
            .filter { representationID == nil || $0.representationID == representationID }
            .sorted { $0.observedAt < $1.observedAt }
            .last
    }

    public func history(for informationID: CarrierInformationID) async throws -> [CarrierAvailabilityRecord] {
        records.filter { $0.informationID == informationID }
    }

    public func allRecords() async throws -> [CarrierAvailabilityRecord] {
        records.sorted { $0.observedAt < $1.observedAt }
    }
}

public actor MemoryCarrierIntegrityReporter: CarrierIntegrityReporter {
    private let representations: MemoryEntityRepresentationStore
    private let locators: MemoryLocatorIndex
    private let availability: MemoryAvailabilityStore
    private let now: @Sendable () -> Date

    public init(
        representations: MemoryEntityRepresentationStore,
        locators: MemoryLocatorIndex,
        availability: MemoryAvailabilityStore,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.representations = representations
        self.locators = locators
        self.availability = availability
        self.now = now
    }

    public func integrityReport() async throws -> CarrierIntegrityReport {
        var issues: [CarrierIntegrityIssue] = []
        let representations = try await representations.allRepresentations()
        let locatorRecords = try await locators.allRecords()
        let availabilityRecords = try await availability.allRecords()

        for representation in representations {
            let matchingLocators = locatorRecords.filter {
                $0.representationID == representation.representationID
            }
            let availability = availabilityRecords.last {
                $0.representationID == representation.representationID
            }

            if matchingLocators.isEmpty {
                issues.append(
                    CarrierIntegrityIssue(
                        kind: .orphanRepresentation,
                        informationID: representation.informationID,
                        representationID: representation.representationID,
                        detail: "representation has no locator record"
                    )
                )
            }

            for locator in matchingLocators where
                locator.informationID != representation.informationID ||
                locator.revisionID != representation.revisionID {
                issues.append(
                    CarrierIntegrityIssue(
                        kind: .locatorMismatch,
                        informationID: locator.informationID,
                        representationID: locator.representationID,
                        detail: "locator endpoints do not match representation"
                    )
                )
            }

            if availability == nil {
                issues.append(
                    CarrierIntegrityIssue(
                        kind: .unavailableCurrentObject,
                        informationID: representation.informationID,
                        representationID: representation.representationID,
                        detail: "representation has no availability observation"
                    )
                )
            }
        }

        return CarrierIntegrityReport(issues: issues, checkedAt: now())
    }
}
