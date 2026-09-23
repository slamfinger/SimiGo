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
