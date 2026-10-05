import Foundation

public struct CarrierConformanceResult: Hashable, Sendable {
    public let name: String
    public let passed: Bool
    public let detail: String

    public init(name: String, passed: Bool, detail: String = "") {
        self.name = name
        self.passed = passed
        self.detail = detail
    }
}

public struct CarrierConformanceReport: Hashable, Sendable {
    public let results: [CarrierConformanceResult]
    public let completedAt: Date

    public init(results: [CarrierConformanceResult], completedAt: Date) {
        self.results = results
        self.completedAt = completedAt
    }

    public var passed: Bool { results.allSatisfy(\.passed) }
}

public protocol CarrierRuntimeFactory: Sendable {
    func make() async throws -> InformationSpaceRuntime
}

public struct MemoryCarrierRuntimeFactory: CarrierRuntimeFactory {
    public init() {}

    public func make() async throws -> InformationSpaceRuntime {
        MemoryCarrierFactory().make().runtime
    }
}

/// Candidate-neutral conformance checks. A real carrier must pass these before
/// benchmarking. They check mechanical carrier invariants, not SimiGo semantic
/// judgment.
public struct CarrierConformanceSuite {
    private let factory: any CarrierRuntimeFactory
    private let date = Date(timeIntervalSinceReferenceDate: 0)

    public init(factory: any CarrierRuntimeFactory) {
        self.factory = factory
    }

    public func run() async throws -> CarrierConformanceReport {
        var results: [CarrierConformanceResult] = []
        results.append(try await checkLocatorMovePreservesIdentity())
        results.append(try await checkRevisionDoesNotEraseHistory())
        results.append(try await checkDeleteChangesAvailabilityOnly())
        results.append(try await checkHistoricalPinStaysStable())
        results.append(try await checkSessionOrdering())
        results.append(try await checkSearchRebuildEquivalence())
        results.append(try await checkCarrierInterfaceExposesContinuationWithoutSemanticClaim())
        return CarrierConformanceReport(results: results, completedAt: Date())
    }

    private func checkLocatorMovePreservesIdentity() async throws -> CarrierConformanceResult {
        let runtime = try await factory.make()
        let info = CarrierInformationID(rawValue: "conf-info-1")
        _ = try await createObject(info, on: runtime)

        let moved = try await runtime.move(
            CarrierMoveRequest(
                informationID: info,
                newLocatorID: CarrierLocatorID(rawValue: "conf-loc-2"),
                newLocator: CarrierLocator(scheme: "memory", value: "moved/1"),
                movedAt: date
            )
        )
        let resolved = try await runtime.resolve(CarrierResolveRequest(informationID: info))

        let passed = moved.informationID == info &&
            resolved.content.representation.informationID == info &&
            resolved.locator?.locator.value == "moved/1"
        return CarrierConformanceResult(
            name: "locator move preserves identity",
            passed: passed,
            detail: "moved locator and resolved the same InformationID"
        )
    }

    private func checkRevisionDoesNotEraseHistory() async throws -> CarrierConformanceResult {
        let runtime = try await factory.make()
        let info = CarrierInformationID(rawValue: "conf-info-2")
        let original = try await createObject(info, on: runtime)

        _ = try await runtime.revise(
            CarrierReviseRequest(
                informationID: info,
                revisionID: CarrierRevisionID(rawValue: "conf-rev-2"),
                representationID: CarrierRepresentationID(rawValue: "conf-rep-2"),
                payload: CarrierPayload(bytes: Data("v2".utf8)),
                locatorID: CarrierLocatorID(rawValue: "conf-loc-rev-2"),
                locator: CarrierLocator(scheme: "memory", value: "rev/2"),
                provenance: CarrierProvenance(producedAt: date, producedBy: "conformance"),
                predecessorRevisionID: original.revision.revisionID
            )
        )

        let latest = try await runtime.resolve(CarrierResolveRequest(informationID: info))
        let old = try await runtime.resolve(
            CarrierResolveRequest(
                informationID: info,
                revisionID: original.revision.revisionID
            )
        )
        let passed = latest.content.payload != old.content.payload &&
            old.content.representation.digest == original.representation.digest
        return CarrierConformanceResult(
            name: "revision preserves historical representation",
            passed: passed
        )
    }

    private func checkDeleteChangesAvailabilityOnly() async throws -> CarrierConformanceResult {
        let runtime = try await factory.make()
        let info = CarrierInformationID(rawValue: "conf-info-3")
        let created = try await createObject(info, on: runtime)

        _ = try await runtime.recordAvailability(
            CarrierAvailabilityRequest(
                informationID: info,
                revisionID: created.revision.revisionID,
                representationID: created.representation.representationID,
                state: .deleted,
                reason: "conformance delete",
                observedAt: date
            )
        )
        let resolved = try await runtime.resolve(CarrierResolveRequest(informationID: info))
        let passed = resolved.availability?.state == .deleted && !resolved.content.payload.bytes.isEmpty
        return CarrierConformanceResult(
            name: "delete records availability without destroying representation",
            passed: passed
        )
    }

    private func checkHistoricalPinStaysStable() async throws -> CarrierConformanceResult {
        let runtime = try await factory.make()
        let info = CarrierInformationID(rawValue: "conf-info-4")
        _ = try await createObject(info, on: runtime)
        let pin = try await runtime.pin(
            CarrierResolveRequest(informationID: info),
            pinID: CarrierPinID(rawValue: "conf-pin-1"),
            label: "before move",
            at: date
        )
        _ = try await runtime.move(
            CarrierMoveRequest(
                informationID: info,
                newLocatorID: CarrierLocatorID(rawValue: "conf-pin-move"),
                newLocator: CarrierLocator(scheme: "memory", value: "pin/moved"),
                movedAt: date
            )
        )
        let fetched = try await runtime.composition.relations.pin(pin.pinID)
        let passed = fetched == pin
        return CarrierConformanceResult(name: "historical pin remains stable", passed: passed)
    }

    private func checkSessionOrdering() async throws -> CarrierConformanceResult {
        let runtime = try await factory.make()
        let session = CarrierSessionID(rawValue: "conf-session")
        for sequence in 0..<3 {
            _ = try await runtime.appendSessionEvent(
                CarrierSessionAppendRequest(
                    eventID: CarrierSessionEventID(rawValue: "conf-event-\(sequence)"),
                    sessionID: session,
                    sequence: sequence,
                    kind: "test",
                    payload: Data("\(sequence)".utf8),
                    occurredAt: date,
                    provenance: CarrierProvenance(producedAt: date, producedBy: "conformance")
                )
            )
        }
        let events = try await runtime.composition.sessions.events(in: session, after: -1)
        let passed = events.map(\.sequence) == [0, 1, 2]
        return CarrierConformanceResult(name: "session events preserve order", passed: passed)
    }

    private func checkSearchRebuildEquivalence() async throws -> CarrierConformanceResult {
        let runtime = try await factory.make()
        let info = CarrierInformationID(rawValue: "conf-info-search")
        _ = try await createObject(info, on: runtime, text: "carrier rebuild needle")
        let before = try await runtime.search("needle")
        let documents = [
            CarrierSearchDocument(
                informationID: info,
                revisionID: CarrierRevisionID(rawValue: "conf-search-rev"),
                title: "needle",
                text: "carrier rebuild needle"
            )
        ]
        _ = try await runtime.composition.search.rebuild(with: documents)
        let after = try await runtime.search("needle")
        let passed = before.map(\.informationID) == after.map(\.informationID)
        return CarrierConformanceResult(name: "search rebuild preserves equivalence", passed: passed)
    }

    private func checkCarrierInterfaceExposesContinuationWithoutSemanticClaim() async throws -> CarrierConformanceResult {
        let runtime = try await factory.make()
        let info = CarrierInformationID(rawValue: "conf-info-c8")
        _ = try await createObject(info, on: runtime)
        let context = try await runtime.continuationContext(CarrierResolveRequest(informationID: info))
        let passed = context.informationID == info && context.availability == .available
        return CarrierConformanceResult(
            name: "C8 exposes continuation facts only",
            passed: passed,
            detail: "C8 returns identity, revision, representation, locator, and availability; it does not judge continuation"
        )
    }

    private func createObject(
        _ info: CarrierInformationID,
        on runtime: InformationSpaceRuntime,
        text: String = "conformance payload"
    ) async throws -> CarrierCreateResult {
        try await runtime.create(
            CarrierCreateRequest(
                informationID: info,
                revisionID: CarrierRevisionID(rawValue: "\(info.rawValue)-rev"),
                representationID: CarrierRepresentationID(rawValue: "\(info.rawValue)-rep"),
                payload: CarrierPayload(bytes: Data(text.utf8)),
                locatorID: CarrierLocatorID(rawValue: "\(info.rawValue)-loc"),
                locator: CarrierLocator(scheme: "memory", value: "\(info.rawValue)"),
                provenance: CarrierProvenance(producedAt: date, producedBy: "conformance"),
                searchableText: text
            )
        )
    }
}
