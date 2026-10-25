import Foundation

public struct MemoryCarrierBundle: Sendable {
    public let runtime: InformationSpaceRuntime
    public let registry: MemoryInformationRegistry
    public let representations: MemoryEntityRepresentationStore
    public let locators: MemoryLocatorIndex
    public let relations: MemoryRelationHistoryStore
    public let sessions: MemorySessionInformationStore
    public let search: MemoryDerivedSearchIndex
    public let availability: MemoryAvailabilityStore
    public let integrity: MemoryCarrierIntegrityReporter
}

public struct MemoryCarrierFactory: Sendable {
    public init() {}

    public func make() -> MemoryCarrierBundle {
        let registry = MemoryInformationRegistry()
        let representations = MemoryEntityRepresentationStore()
        let locators = MemoryLocatorIndex()
        let relations = MemoryRelationHistoryStore()
        let sessions = MemorySessionInformationStore()
        let search = MemoryDerivedSearchIndex()
        let availability = MemoryAvailabilityStore()
        let integrity = MemoryCarrierIntegrityReporter(
            representations: representations,
            locators: locators,
            availability: availability
        )

        return MemoryCarrierBundle(
            runtime: InformationSpaceRuntime(
                composition: CarrierComposition(
                    registry: registry,
                    representations: representations,
                    locators: locators,
                    relations: relations,
                    sessions: sessions,
                    search: search,
                    availability: availability,
                    integrity: integrity
                )
            ),
            registry: registry,
            representations: representations,
            locators: locators,
            relations: relations,
            sessions: sessions,
            search: search,
            availability: availability,
            integrity: integrity
        )
    }
}
