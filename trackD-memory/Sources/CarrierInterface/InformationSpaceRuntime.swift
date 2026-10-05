import Foundation
import CryptoKit

public struct CarrierComposition: Sendable {
    public let registry: any InformationRegistry
    public let representations: any EntityRepresentationStore
    public let locators: any LocatorIndex
    public let relations: any RelationHistoryStore
    public let sessions: any SessionInformationStore
    public let search: any DerivedSearchIndex
    public let availability: any AvailabilityStore

    public init(
        registry: any InformationRegistry,
        representations: any EntityRepresentationStore,
        locators: any LocatorIndex,
        relations: any RelationHistoryStore,
        sessions: any SessionInformationStore,
        search: any DerivedSearchIndex,
        availability: any AvailabilityStore
    ) {
        self.registry = registry
        self.representations = representations
        self.locators = locators
        self.relations = relations
        self.sessions = sessions
        self.search = search
        self.availability = availability
    }
}

/// Dependency-injected composition root for C1-C7. It sequences carrier
/// operations but does not define semantic identity continuity, applicability,
/// validity, judgment, or continuation reasoning.
public struct InformationSpaceRuntime {
    public let composition: CarrierComposition

    public init(composition: CarrierComposition) {
        self.composition = composition
    }

    static func digest(_ payload: CarrierPayload) -> String {
        SHA256.hash(data: payload.bytes).map { String(format: "%02x", $0) }.joined()
    }

    public func create(_ request: CarrierCreateRequest) async throws -> CarrierCreateResult {
        let revision = CarrierRevision(
            revisionID: request.revisionID,
            informationID: request.informationID,
            label: request.label,
            provenance: request.provenance
        )
        let representation = CarrierRepresentation(
            representationID: request.representationID,
            informationID: request.informationID,
            revisionID: request.revisionID,
            digest: Self.digest(request.payload),
            byteCount: request.payload.bytes.count,
            mediaType: request.payload.mediaType,
            createdAt: request.provenance.producedAt
        )
        let locator = CarrierLocatorRecord(
            locatorID: request.locatorID,
            informationID: request.informationID,
            revisionID: request.revisionID,
            representationID: request.representationID,
            locator: request.locator,
            createdAt: request.provenance.producedAt
        )
        let availability = CarrierAvailabilityRecord(
            informationID: request.informationID,
            revisionID: request.revisionID,
            representationID: request.representationID,
            state: .available,
            reason: "created",
            observedAt: request.provenance.producedAt
        )

        try await composition.registry.register(revision)
        try await composition.representations.put(
            CarrierRepresentationContent(representation: representation, payload: request.payload)
        )
        try await composition.locators.assign(locator)
        try await composition.availability.record(availability)

        if let text = request.searchableText {
            try await composition.search.upsert(
                CarrierSearchDocument(
                    informationID: request.informationID,
                    revisionID: request.revisionID,
                    title: request.label,
                    text: text
                )
            )
        }

        return CarrierCreateResult(
            revision: revision,
            representation: representation,
            locator: locator,
            availability: availability
        )
    }

    public func move(_ request: CarrierMoveRequest) async throws -> CarrierLocatorRecord {
        let current = try await composition.locators.current(
            for: request.informationID,
            revisionID: request.revisionID
        )
        guard let current else {
            throw CarrierInterfaceError.notFound("current locator for \(request.informationID.rawValue)")
        }
        let representationID = request.representationID ?? current.representationID
        let revisionID = request.revisionID ?? current.revisionID
        try await composition.locators.retire(current.locatorID, at: request.movedAt)

        let replacement = CarrierLocatorRecord(
            locatorID: request.newLocatorID,
            informationID: request.informationID,
            revisionID: revisionID,
            representationID: representationID,
            locator: request.newLocator,
            createdAt: request.movedAt
        )
        try await composition.locators.assign(replacement)
        return replacement
    }

    public func revise(_ request: CarrierReviseRequest) async throws -> CarrierCreateResult {
        let result = try await create(
            CarrierCreateRequest(
                informationID: request.informationID,
                revisionID: request.revisionID,
                representationID: request.representationID,
                label: request.label,
                payload: request.payload,
                locatorID: request.locatorID,
                locator: request.locator,
                provenance: request.provenance,
                searchableText: request.searchableText
            )
        )

        if let predecessor = request.predecessorRevisionID {
            try await composition.availability.record(
                CarrierAvailabilityRecord(
                    informationID: request.informationID,
                    revisionID: predecessor,
                    representationID: result.representation.representationID,
                    state: .superseded,
                    reason: "revised by \(request.revisionID.rawValue)",
                    observedAt: request.provenance.producedAt
                )
            )
            try await composition.relations.append(
                CarrierRelation(
                    relationID: CarrierRelationID(rawValue: "successor:\(predecessor.rawValue):\(request.revisionID.rawValue)"),
                    subject: CarrierInformationID(rawValue: request.revisionID.rawValue),
                    predicate: "successor-of",
                    object: CarrierInformationID(rawValue: predecessor.rawValue),
                    provenance: request.provenance
                )
            )
        }

        return result
    }

    public func recordAvailability(_ request: CarrierAvailabilityRequest) async throws -> CarrierAvailabilityRecord {
        let current = try await composition.locators.current(
            for: request.informationID,
            revisionID: request.revisionID
        )
        let representationID = request.representationID ?? current?.representationID
        let revisionID = request.revisionID ?? current?.revisionID

        guard let revisionID, let representationID else {
            throw CarrierInterfaceError.notFound("locatable representation for \(request.informationID.rawValue)")
        }

        let record = CarrierAvailabilityRecord(
            informationID: request.informationID,
            revisionID: revisionID,
            representationID: representationID,
            state: request.state,
            reason: request.reason,
            observedAt: request.observedAt
        )
        try await composition.availability.record(record)
        return record
    }

    public func relate(
        relationID: CarrierRelationID,
        subject: CarrierInformationID,
        predicate: String,
        object: CarrierInformationID,
        provenance: CarrierProvenance
    ) async throws -> CarrierRelation {
        let relation = CarrierRelation(
            relationID: relationID,
            subject: subject,
            predicate: predicate,
            object: object,
            provenance: provenance
        )
        try await composition.relations.append(relation)
        return relation
    }

    public func appendSessionEvent(_ request: CarrierSessionAppendRequest) async throws -> CarrierSessionEvent {
        let event = CarrierSessionEvent(
            eventID: request.eventID,
            sessionID: request.sessionID,
            sequence: request.sequence,
            kind: request.kind,
            payload: request.payload,
            occurredAt: request.occurredAt,
            provenance: request.provenance
        )
        try await composition.sessions.append(event)
        return event
    }

    public func addSessionSummary(
        summaryID: CarrierSummaryID,
        sessionID: CarrierSessionID,
        throughSequence: Int,
        payload: Data,
        provenance: CarrierProvenance
    ) async throws -> CarrierSessionSummary {
        let summary = CarrierSessionSummary(
            summaryID: summaryID,
            sessionID: sessionID,
            throughSequence: throughSequence,
            payload: payload,
            createdAt: provenance.producedAt,
            provenance: provenance
        )
        try await composition.sessions.addSummary(summary)
        return summary
    }

    public func search(_ query: String, limit: Int = 20) async throws -> [CarrierSearchResult] {
        try await composition.search.search(query, limit: limit)
    }
}

extension InformationSpaceRuntime: CarrierExecutionInterface {
    public func resolve(_ request: CarrierResolveRequest) async throws -> CarrierResolvedObject {
        let revision = try await selectedRevision(request)
        let representations = try await composition.representations.representations(
            for: request.informationID,
            revisionID: revision.revisionID
        )
        guard let representation = representations.last else {
            throw CarrierInterfaceError.notFound("representation for \(revision.revisionID.rawValue)")
        }
        guard let content = try await composition.representations.content(representation.representationID) else {
            throw CarrierInterfaceError.notFound("payload for \(representation.representationID.rawValue)")
        }
        let locator = try await composition.locators.current(
            for: request.informationID,
            revisionID: revision.revisionID
        )
        let availability = try await composition.availability.current(
            informationID: request.informationID,
            representationID: representation.representationID
        )
        return CarrierResolvedObject(
            revision: revision,
            content: content,
            locator: locator,
            availability: availability
        )
    }

    public func consume(
        _ request: CarrierResolveRequest,
        receiptID: CarrierReceiptID,
        at date: Date
    ) async throws -> CarrierConsumptionReceipt {
        let resolved = try await resolve(request)
        return CarrierConsumptionReceipt(
            receiptID: receiptID,
            informationID: resolved.revision.informationID,
            revisionID: resolved.revision.revisionID,
            consumedAt: date
        )
    }

    public func produce(_ request: CarrierCreateRequest) async throws -> CarrierCreateResult {
        try await create(request)
    }

    public func pin(
        _ request: CarrierResolveRequest,
        pinID: CarrierPinID,
        label: String?,
        at date: Date
    ) async throws -> CarrierHistoricalPin {
        let resolved = try await resolve(request)
        let pin = CarrierHistoricalPin(
            pinID: pinID,
            informationID: resolved.revision.informationID,
            revisionID: resolved.revision.revisionID,
            representationID: resolved.content.representation.representationID,
            digest: resolved.content.representation.digest,
            locator: resolved.locator?.locator,
            label: label,
            pinnedAt: date
        )
        try await composition.relations.pin(pin)
        return pin
    }

    public func continuationContext(_ request: CarrierResolveRequest) async throws -> CarrierContinuationContext {
        let resolved = try await resolve(request)
        return CarrierContinuationContext(
            informationID: resolved.revision.informationID,
            revisionID: resolved.revision.revisionID,
            representationID: resolved.content.representation.representationID,
            locator: resolved.locator?.locator,
            availability: resolved.availability?.state ?? .detached
        )
    }

    private func selectedRevision(_ request: CarrierResolveRequest) async throws -> CarrierRevision {
        if let requested = request.revisionID {
            guard let revision = try await composition.registry.revision(requested) else {
                throw CarrierInterfaceError.notFound("revision \(requested.rawValue)")
            }
            return revision
        }
        guard let revision = try await composition.registry.latestRevision(for: request.informationID) else {
            throw CarrierInterfaceError.notFound("information \(request.informationID.rawValue)")
        }
        return revision
    }
}
