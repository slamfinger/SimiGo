import Foundation

// C2 — stable logical Information and revision registry.
public protocol InformationRegistry: Sendable {
    func register(_ revision: CarrierRevision) async throws
    func revision(_ id: CarrierRevisionID) async throws -> CarrierRevision?
    func revisions(for informationID: CarrierInformationID) async throws -> [CarrierRevision]
    func latestRevision(for informationID: CarrierInformationID) async throws -> CarrierRevision?
}

// C1 — immutable entity representation storage.
public protocol EntityRepresentationStore: Sendable {
    func put(_ content: CarrierRepresentationContent) async throws
    func content(_ id: CarrierRepresentationID) async throws -> CarrierRepresentationContent?
    func representations(
        for informationID: CarrierInformationID,
        revisionID: CarrierRevisionID?
    ) async throws -> [CarrierRepresentation]
}

// C3 — mutable locator mapping over stable identities.
public protocol LocatorIndex: Sendable {
    func assign(_ record: CarrierLocatorRecord) async throws
    func retire(_ id: CarrierLocatorID, at date: Date) async throws
    func current(
        for informationID: CarrierInformationID,
        revisionID: CarrierRevisionID?
    ) async throws -> CarrierLocatorRecord?
    func history(for informationID: CarrierInformationID) async throws -> [CarrierLocatorRecord]
}

// C4 — explicit lineage and immutable historical pins.
public protocol RelationHistoryStore: Sendable {
    func append(_ relation: CarrierRelation) async throws
    func relation(_ id: CarrierRelationID) async throws -> CarrierRelation?
    func relations(involving informationID: CarrierInformationID) async throws -> [CarrierRelation]
    func pin(_ historicalPin: CarrierHistoricalPin) async throws
    func pin(_ id: CarrierPinID) async throws -> CarrierHistoricalPin?
    func pins(for informationID: CarrierInformationID) async throws -> [CarrierHistoricalPin]
}

// C5 — append-oriented session facts and derived summary objects.
public protocol SessionInformationStore: Sendable {
    func append(_ event: CarrierSessionEvent) async throws
    func events(
        in sessionID: CarrierSessionID,
        after sequence: Int
    ) async throws -> [CarrierSessionEvent]
    func addSummary(_ summary: CarrierSessionSummary) async throws
    func summaries(in sessionID: CarrierSessionID) async throws -> [CarrierSessionSummary]
}

// C6 — rebuildable derived retrieval; never semantic authority.
public protocol DerivedSearchIndex: Sendable {
    func upsert(_ document: CarrierSearchDocument) async throws
    func delete(informationID: CarrierInformationID) async throws
    func search(_ query: String, limit: Int) async throws -> [CarrierSearchResult]
    func clear() async throws
    func rebuild(with documents: [CarrierSearchDocument]) async throws -> CarrierRebuildReport
}

// C7 — representation availability and integrity observation.
public protocol AvailabilityStore: Sendable {
    func record(_ record: CarrierAvailabilityRecord) async throws
    func current(
        informationID: CarrierInformationID,
        representationID: CarrierRepresentationID?
    ) async throws -> CarrierAvailabilityRecord?
    func history(for informationID: CarrierInformationID) async throws -> [CarrierAvailabilityRecord]
}

public protocol CarrierIntegrityReporter: Sendable {
    func integrityReport() async throws -> CarrierIntegrityReport
}

// C8 — carrier ↔ SimiGo interface only. The carrier exposes capabilities;
// it does not execute IPAC, applicability, validity, judgment, or continuation
// reasoning.
public struct CarrierResolveRequest: Hashable, Sendable {
    public let informationID: CarrierInformationID
    public let revisionID: CarrierRevisionID?

    public init(
        informationID: CarrierInformationID,
        revisionID: CarrierRevisionID? = nil
    ) {
        self.informationID = informationID
        self.revisionID = revisionID
    }
}

public struct CarrierResolvedObject: Hashable, Sendable {
    public let revision: CarrierRevision
    public let content: CarrierRepresentationContent
    public let locator: CarrierLocatorRecord?
    public let availability: CarrierAvailabilityRecord?

    public init(
        revision: CarrierRevision,
        content: CarrierRepresentationContent,
        locator: CarrierLocatorRecord?,
        availability: CarrierAvailabilityRecord?
    ) {
        self.revision = revision
        self.content = content
        self.locator = locator
        self.availability = availability
    }
}

public struct CarrierConsumptionReceipt: Hashable, Sendable {
    public let receiptID: CarrierReceiptID
    public let informationID: CarrierInformationID
    public let revisionID: CarrierRevisionID
    public let consumedAt: Date

    public init(
        receiptID: CarrierReceiptID,
        informationID: CarrierInformationID,
        revisionID: CarrierRevisionID,
        consumedAt: Date
    ) {
        self.receiptID = receiptID
        self.informationID = informationID
        self.revisionID = revisionID
        self.consumedAt = consumedAt
    }
}

public struct CarrierContinuationContext: Hashable, Sendable {
    public let informationID: CarrierInformationID
    public let revisionID: CarrierRevisionID
    public let representationID: CarrierRepresentationID
    public let locator: CarrierLocator?
    public let availability: CarrierAvailability

    public init(
        informationID: CarrierInformationID,
        revisionID: CarrierRevisionID,
        representationID: CarrierRepresentationID,
        locator: CarrierLocator?,
        availability: CarrierAvailability
    ) {
        self.informationID = informationID
        self.revisionID = revisionID
        self.representationID = representationID
        self.locator = locator
        self.availability = availability
    }
}

public protocol CarrierExecutionInterface: Sendable {
    func resolve(_ request: CarrierResolveRequest) async throws -> CarrierResolvedObject
    func produce(_ request: CarrierCreateRequest) async throws -> CarrierCreateResult
    func consume(
        _ request: CarrierResolveRequest,
        receiptID: CarrierReceiptID,
        at date: Date
    ) async throws -> CarrierConsumptionReceipt
    func pin(
        _ request: CarrierResolveRequest,
        pinID: CarrierPinID,
        label: String?,
        at date: Date
    ) async throws -> CarrierHistoricalPin
    func continuationContext(_ request: CarrierResolveRequest) async throws -> CarrierContinuationContext
}
