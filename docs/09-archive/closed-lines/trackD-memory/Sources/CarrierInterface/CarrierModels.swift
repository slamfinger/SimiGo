import Foundation

public enum CarrierInterfaceError: Error, Hashable, Sendable {
    case notFound(String)
    case alreadyExists(String)
    case invalidOperation(String)
    case unsupported(String)
    case integrityIssue(String)
}

public struct CarrierProvenance: Hashable, Sendable {
    public let producedAt: Date
    public let producedBy: String
    public let source: String?

    public init(producedAt: Date, producedBy: String, source: String? = nil) {
        self.producedAt = producedAt
        self.producedBy = producedBy
        self.source = source
    }
}

public struct CarrierPayload: Hashable, Sendable {
    public let bytes: Data
    public let mediaType: String?

    public init(bytes: Data, mediaType: String? = nil) {
        self.bytes = bytes
        self.mediaType = mediaType
    }
}

public struct CarrierRepresentation: Hashable, Sendable {
    public let representationID: CarrierRepresentationID
    public let informationID: CarrierInformationID
    public let revisionID: CarrierRevisionID
    public let digest: String
    public let byteCount: Int
    public let mediaType: String?
    public let createdAt: Date

    public init(
        representationID: CarrierRepresentationID,
        informationID: CarrierInformationID,
        revisionID: CarrierRevisionID,
        digest: String,
        byteCount: Int,
        mediaType: String? = nil,
        createdAt: Date
    ) {
        self.representationID = representationID
        self.informationID = informationID
        self.revisionID = revisionID
        self.digest = digest
        self.byteCount = byteCount
        self.mediaType = mediaType
        self.createdAt = createdAt
    }
}

public struct CarrierRepresentationContent: Hashable, Sendable {
    public let representation: CarrierRepresentation
    public let payload: CarrierPayload

    public init(representation: CarrierRepresentation, payload: CarrierPayload) {
        self.representation = representation
        self.payload = payload
    }
}

public struct CarrierRevision: Hashable, Sendable {
    public let revisionID: CarrierRevisionID
    public let informationID: CarrierInformationID
    public let label: String?
    public let provenance: CarrierProvenance

    public init(
        revisionID: CarrierRevisionID,
        informationID: CarrierInformationID,
        label: String? = nil,
        provenance: CarrierProvenance
    ) {
        self.revisionID = revisionID
        self.informationID = informationID
        self.label = label
        self.provenance = provenance
    }
}

public enum CarrierAvailability: String, Hashable, Sendable {
    case available
    case superseded
    case deleted
    case detached
    case archived
    case restored
}

public struct CarrierAvailabilityRecord: Hashable, Sendable {
    public let informationID: CarrierInformationID
    public let revisionID: CarrierRevisionID
    public let representationID: CarrierRepresentationID
    public let state: CarrierAvailability
    public let reason: String?
    public let observedAt: Date

    public init(
        informationID: CarrierInformationID,
        revisionID: CarrierRevisionID,
        representationID: CarrierRepresentationID,
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

public struct CarrierLocator: Hashable, Sendable {
    public let scheme: String
    public let value: String

    public init(scheme: String, value: String) {
        self.scheme = scheme
        self.value = value
    }
}

public struct CarrierLocatorRecord: Hashable, Sendable {
    public let locatorID: CarrierLocatorID
    public let informationID: CarrierInformationID
    public let revisionID: CarrierRevisionID
    public let representationID: CarrierRepresentationID
    public let locator: CarrierLocator
    public let createdAt: Date
    public let retiredAt: Date?

    public init(
        locatorID: CarrierLocatorID,
        informationID: CarrierInformationID,
        revisionID: CarrierRevisionID,
        representationID: CarrierRepresentationID,
        locator: CarrierLocator,
        createdAt: Date,
        retiredAt: Date? = nil
    ) {
        self.locatorID = locatorID
        self.informationID = informationID
        self.revisionID = revisionID
        self.representationID = representationID
        self.locator = locator
        self.createdAt = createdAt
        self.retiredAt = retiredAt
    }
}

public struct CarrierRelation: Hashable, Sendable {
    public let relationID: CarrierRelationID
    public let subject: CarrierInformationID
    public let predicate: String
    public let object: CarrierInformationID
    public let provenance: CarrierProvenance

    public init(
        relationID: CarrierRelationID,
        subject: CarrierInformationID,
        predicate: String,
        object: CarrierInformationID,
        provenance: CarrierProvenance
    ) {
        self.relationID = relationID
        self.subject = subject
        self.predicate = predicate
        self.object = object
        self.provenance = provenance
    }
}

public struct CarrierHistoricalPin: Hashable, Sendable {
    public let pinID: CarrierPinID
    public let informationID: CarrierInformationID
    public let revisionID: CarrierRevisionID
    public let representationID: CarrierRepresentationID
    public let digest: String
    public let locator: CarrierLocator?
    public let label: String?
    public let pinnedAt: Date

    public init(
        pinID: CarrierPinID,
        informationID: CarrierInformationID,
        revisionID: CarrierRevisionID,
        representationID: CarrierRepresentationID,
        digest: String,
        locator: CarrierLocator? = nil,
        label: String? = nil,
        pinnedAt: Date
    ) {
        self.pinID = pinID
        self.informationID = informationID
        self.revisionID = revisionID
        self.representationID = representationID
        self.digest = digest
        self.locator = locator
        self.label = label
        self.pinnedAt = pinnedAt
    }
}

public struct CarrierSessionEvent: Hashable, Sendable {
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

public struct CarrierSessionSummary: Hashable, Sendable {
    public let summaryID: CarrierSummaryID
    public let sessionID: CarrierSessionID
    public let throughSequence: Int
    public let payload: Data
    public let createdAt: Date
    public let provenance: CarrierProvenance

    public init(
        summaryID: CarrierSummaryID,
        sessionID: CarrierSessionID,
        throughSequence: Int,
        payload: Data,
        createdAt: Date,
        provenance: CarrierProvenance
    ) {
        self.summaryID = summaryID
        self.sessionID = sessionID
        self.throughSequence = throughSequence
        self.payload = payload
        self.createdAt = createdAt
        self.provenance = provenance
    }
}

public struct CarrierSearchDocument: Hashable, Sendable {
    public let informationID: CarrierInformationID
    public let revisionID: CarrierRevisionID
    public let title: String?
    public let text: String

    public init(
        informationID: CarrierInformationID,
        revisionID: CarrierRevisionID,
        title: String? = nil,
        text: String
    ) {
        self.informationID = informationID
        self.revisionID = revisionID
        self.title = title
        self.text = text
    }
}

public struct CarrierSearchResult: Hashable, Sendable {
    public let informationID: CarrierInformationID
    public let revisionID: CarrierRevisionID
    public let score: Double

    public init(
        informationID: CarrierInformationID,
        revisionID: CarrierRevisionID,
        score: Double
    ) {
        self.informationID = informationID
        self.revisionID = revisionID
        self.score = score
    }
}

public struct CarrierRebuildReport: Hashable, Sendable {
    public let documentsIndexed: Int
    public let completedAt: Date

    public init(documentsIndexed: Int, completedAt: Date) {
        self.documentsIndexed = documentsIndexed
        self.completedAt = completedAt
    }
}

public enum CarrierIntegrityIssueKind: String, Hashable, Sendable {
    case orphanRepresentation
    case missingLocator
    case missingRepresentation
    case locatorMismatch
    case unavailableCurrentObject
}

public struct CarrierIntegrityIssue: Hashable, Sendable {
    public let kind: CarrierIntegrityIssueKind
    public let informationID: CarrierInformationID?
    public let representationID: CarrierRepresentationID?
    public let detail: String

    public init(
        kind: CarrierIntegrityIssueKind,
        informationID: CarrierInformationID? = nil,
        representationID: CarrierRepresentationID? = nil,
        detail: String
    ) {
        self.kind = kind
        self.informationID = informationID
        self.representationID = representationID
        self.detail = detail
    }
}

public struct CarrierIntegrityReport: Hashable, Sendable {
    public let issues: [CarrierIntegrityIssue]
    public let checkedAt: Date

    public init(issues: [CarrierIntegrityIssue], checkedAt: Date) {
        self.issues = issues
        self.checkedAt = checkedAt
    }

    public var isClean: Bool { issues.isEmpty }
}
