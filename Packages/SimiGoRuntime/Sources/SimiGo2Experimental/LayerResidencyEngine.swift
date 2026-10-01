import Foundation

public struct LayerGroupEvent: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let executionState: ExecutionStateLabel
    public let groupID: String
    public let action: Action
    public let byteCount: Int64

    public enum Action: String, Codable, Sendable {
        case load
        case keep
        case evict
    }

    init(
        id: UUID = UUID(),
        executionState: ExecutionStateLabel,
        groupID: String,
        action: Action,
        byteCount: Int64
    ) {
        self.id = id
        self.executionState = executionState
        self.groupID = groupID
        self.action = action
        self.byteCount = byteCount
    }
}

public struct TransitionReport: Hashable, Sendable, Codable {
    public let executionState: ExecutionStateLabel
    public let desiredGroupIDs: Set<String>
    public let loadedGroupIDs: Set<String>
    public let keptGroupIDs: Set<String>
    public let evictedGroupIDs: Set<String>
    public let residentGroupIDs: Set<String>
    public let loadedBytes: Int64
    public let evictedBytes: Int64
    public let residentBytes: Int64
    public let peakResidentBytes: Int64
    public let cumulativeLoadedBytes: Int64
    public let cumulativeEvictedBytes: Int64
    public let events: [LayerGroupEvent]
}

/// The first executable harness is deliberately a residency simulator.
/// It validates state-to-policy-to-layer transition semantics before touching MLX internals.
public struct LayerResidencyEngine: Sendable {
    public let inventory: LayerInventory
    public let policy: any LayerResidencyPolicy
    public private(set) var residentGroupIDs: Set<String> = []
    public private(set) var events: [LayerGroupEvent] = []
    public private(set) var peakResidentBytes: Int64 = 0
    public private(set) var cumulativeLoadedBytes: Int64 = 0
    public private(set) var cumulativeEvictedBytes: Int64 = 0

    public init(inventory: LayerInventory, policy: any LayerResidencyPolicy) {
        self.inventory = inventory
        self.policy = policy
    }

    public mutating func transition(to state: ExecutionStateLabel) throws -> TransitionReport {
        let desired = policy.desiredGroupIDs(for: state)
        let current = residentGroupIDs

        let loaded = desired.subtracting(current)
        let evicted = current.subtracting(desired)
        let kept = desired.intersection(current)

        residentGroupIDs = desired

        let groupLookup = Dictionary(uniqueKeysWithValues: inventory.groups.map { ($0.id, $0) })
        var transitionEvents: [LayerGroupEvent] = []

        for groupID in loaded.sorted() {
            let bytes = groupLookup[groupID]?.byteCount ?? 0
            transitionEvents.append(
                LayerGroupEvent(executionState: state, groupID: groupID, action: .load, byteCount: bytes)
            )
            cumulativeLoadedBytes += bytes
        }

        for groupID in kept.sorted() {
            let bytes = groupLookup[groupID]?.byteCount ?? 0
            transitionEvents.append(
                LayerGroupEvent(executionState: state, groupID: groupID, action: .keep, byteCount: bytes)
            )
        }

        for groupID in evicted.sorted() {
            let bytes = groupLookup[groupID]?.byteCount ?? 0
            transitionEvents.append(
                LayerGroupEvent(executionState: state, groupID: groupID, action: .evict, byteCount: bytes)
            )
            cumulativeEvictedBytes += bytes
        }

        events.append(contentsOf: transitionEvents)

        let residentBytes = residentGroupIDs.reduce(Int64(0)) { partial, groupID in
            partial + (groupLookup[groupID]?.byteCount ?? 0)
        }

        peakResidentBytes = max(peakResidentBytes, residentBytes)

        return TransitionReport(
            executionState: state,
            desiredGroupIDs: desired,
            loadedGroupIDs: loaded,
            keptGroupIDs: kept,
            evictedGroupIDs: evicted,
            residentGroupIDs: residentGroupIDs,
            loadedBytes: loaded.reduce(Int64(0)) { partial, groupID in
                partial + (groupLookup[groupID]?.byteCount ?? 0)
            },
            evictedBytes: evicted.reduce(Int64(0)) { partial, groupID in
                partial + (groupLookup[groupID]?.byteCount ?? 0)
            },
            residentBytes: residentBytes,
            peakResidentBytes: peakResidentBytes,
            cumulativeLoadedBytes: cumulativeLoadedBytes,
            cumulativeEvictedBytes: cumulativeEvictedBytes,
            events: transitionEvents
        )
    }
}
