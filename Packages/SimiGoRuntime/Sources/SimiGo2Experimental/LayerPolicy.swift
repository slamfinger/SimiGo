import Foundation

public protocol LayerResidencyPolicy: Sendable {
    func desiredGroupIDs(for state: ExecutionStateLabel) -> Set<String>
}

public struct Qwen3CoderStatePolicy: LayerResidencyPolicy, Sendable {
    public let alwaysResidentGroupIDs: Set<String>

    public init(alwaysResidentGroupIDs: Set<String>) {
        self.alwaysResidentGroupIDs = alwaysResidentGroupIDs
    }

    public init(inventory: LayerInventory) {
        self.init(
            alwaysResidentGroupIDs: Set(
                inventory.groups.filter(\.alwaysResident).map(\.id)
            )
        )
    }

    public func desiredGroupIDs(for state: ExecutionStateLabel) -> Set<String> {
        var desired = alwaysResidentGroupIDs

        switch state {
        case .stateA:
            desired.insert("SWITCH_MLP_L00_15")
        case .stateB:
            desired.insert("SWITCH_MLP_L16_31")
        case .stateC:
            desired.insert("SWITCH_MLP_L32_47")
        case .stateAB:
            desired.formUnion(["SWITCH_MLP_L00_15", "SWITCH_MLP_L16_31"])
        case .stateBC:
            desired.formUnion(["SWITCH_MLP_L16_31", "SWITCH_MLP_L32_47"])
        case .stateAll:
            desired.formUnion([
                "SWITCH_MLP_L00_15",
                "SWITCH_MLP_L16_31",
                "SWITCH_MLP_L32_47"
            ])
        }

        return desired
    }
}

public struct ContiguousLayerStatePolicy: LayerResidencyPolicy, Sendable {
    public let alwaysResidentGroupIDs: Set<String>
    public let optionalGroupIDs: [String]

    public init(inventory: LayerInventory) {
        alwaysResidentGroupIDs = Set(
            inventory.groups.filter(\.alwaysResident).map(\.id)
        )
        optionalGroupIDs = inventory.groups
            .filter { !$0.alwaysResident }
            .sorted { $0.layerRangeDescription < $1.layerRangeDescription }
            .map(\.id)
    }

    public func desiredGroupIDs(for state: ExecutionStateLabel) -> Set<String> {
        func optionalGroups(_ indices: [Int]) -> Set<String> {
            Set(indices.compactMap { optionalGroupIDs.indices.contains($0) ? optionalGroupIDs[$0] : nil })
        }

        var desired = alwaysResidentGroupIDs
        switch state {
        case .stateA: desired.formUnion(optionalGroups([0]))
        case .stateB: desired.formUnion(optionalGroups([1]))
        case .stateC: desired.formUnion(optionalGroups([2]))
        case .stateAB: desired.formUnion(optionalGroups([0, 1]))
        case .stateBC: desired.formUnion(optionalGroups([1, 2]))
        case .stateAll: desired.formUnion(Set(optionalGroupIDs))
        }
        return desired
    }
}
