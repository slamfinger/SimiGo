import Foundation

public struct CarrierCreateRequest: Hashable, Sendable {
    public let informationID: CarrierInformationID
    public let revisionID: CarrierRevisionID
    public let representationID: CarrierRepresentationID
    public let label: String?
    public let payload: CarrierPayload
    public let locatorID: CarrierLocatorID
    public let locator: CarrierLocator
    public let provenance: CarrierProvenance
    public let searchableText: String?

    public init(
        informationID: CarrierInformationID,
        revisionID: CarrierRevisionID,
        representationID: CarrierRepresentationID,
        label: String? = nil,
        payload: CarrierPayload,
        locatorID: CarrierLocatorID,
        locator: CarrierLocator,
        provenance: CarrierProvenance,
        searchableText: String? = nil
    ) {
        self.informationID = informationID
        self.revisionID = revisionID
        self.representationID = representationID
        self.label = label
        self.payload = payload
        self.locatorID = locatorID
        self.locator = locator
        self.provenance = provenance
        self.searchableText = searchableText
    }
}

public struct CarrierCreateResult: Hashable, Sendable {
    public let revision: CarrierRevision
    public let representation: CarrierRepresentation
    public let locator: CarrierLocatorRecord
    public let availability: CarrierAvailabilityRecord

    public init(
        revision: CarrierRevision,
        representation: CarrierRepresentation,
        locator: CarrierLocatorRecord,
        availability: CarrierAvailabilityRecord
    ) {
        self.revision = revision
        self.representation = representation
        self.locator = locator
        self.availability = availability
    }
}

public struct CarrierMoveRequest: Hashable, Sendable {
    public let informationID: CarrierInformationID
    public let revisionID: CarrierRevisionID?
    public let representationID: CarrierRepresentationID?
    public let newLocatorID: CarrierLocatorID
    public let newLocator: CarrierLocator
    public let movedAt: Date

    public init(
        informationID: CarrierInformationID,
        revisionID: CarrierRevisionID? = nil,
        representationID: CarrierRepresentationID? = nil,
        newLocatorID: CarrierLocatorID,
        newLocator: CarrierLocator,
        movedAt: Date
    ) {
        self.informationID = informationID
        self.revisionID = revisionID
        self.representationID = representationID
        self.newLocatorID = newLocatorID
        self.newLocator = newLocator
        self.movedAt = movedAt
    }
}

public struct CarrierReviseRequest: Hashable, Sendable {
    public let informationID: CarrierInformationID
    public let revisionID: CarrierRevisionID
    public let representationID: CarrierRepresentationID
    public let label: String?
    public let payload: CarrierPayload
    public let locatorID: CarrierLocatorID
    public let locator: CarrierLocator
    public let provenance: CarrierProvenance
    public let predecessorRevisionID: CarrierRevisionID?
    public let searchableText: String?

    public init(
        informationID: CarrierInformationID,
        revisionID: CarrierRevisionID,
        representationID: CarrierRepresentationID,
        label: String? = nil,
        payload: CarrierPayload,
        locatorID: CarrierLocatorID,
        locator: CarrierLocator,
        provenance: CarrierProvenance,
        predecessorRevisionID: CarrierRevisionID? = nil,
        searchableText: String? = nil
    ) {
        self.informationID = informationID
        self.revisionID = revisionID
        self.representationID = representationID
        self.label = label
        self.payload = payload
        self.locatorID = locatorID
        self.locator = locator
        self.provenance = provenance
        self.predecessorRevisionID = predecessorRevisionID
        self.searchableText = searchableText
    }
}

public struct CarrierAvailabilityRequest: Hashable, Sendable {
    public let informationID: CarrierInformationID
    public let revisionID: CarrierRevisionID?
    public let representationID: CarrierRepresentationID?
    public let state: CarrierAvailability
    public let reason: String?
    public let observedAt: Date

    public init(
        informationID: CarrierInformationID,
        revisionID: CarrierRevisionID? = nil,
        representationID: CarrierRepresentationID? = nil,
        state: CarrierAvailability,
        reason: String? = nil,
        observedAt: Date
    ) {
        self.informationID = informationID
        self.revisionID = revisionID
        self.representationID = representationID
        self.state = state
        self.reason = reason
        self.observedAt = observedAt
    }
}

public struct CarrierSessionAppendRequest: Hashable, Sendable {
    public let eventID: CarrierSessionEventID
    public let sessionID: CarrierSessionID
    public let sequence: Int
    public let kind: String
    public let payload: Data
    public let occurredAt: Date
    public let provenance: CarrierProvenance

    public init(
        eventID: CarrierSessionEventID,
        sessionID: CarrierSessionID,
        sequence: Int,
        kind: String,
        payload: Data,
        occurredAt: Date,
        provenance: CarrierProvenance
    ) {
        self.eventID = eventID
        self.sessionID = sessionID
        self.sequence = sequence
        self.kind = kind
        self.payload = payload
        self.occurredAt = occurredAt
        self.provenance = provenance
    }
}
