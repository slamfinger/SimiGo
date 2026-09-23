import Foundation

public enum ResidencyPolicyKind: String, Codable, Sendable, CaseIterable {
    case allResident
    case reactive
    case llamaCppLazy

    public var displayName: String {
        switch self {
        case .allResident: return "All groups resident"
        case .reactive: return "External-state reactive"
        case .llamaCppLazy: return "llama.cpp-inspired lazy residency"
        }
    }
}

public struct LlamaCppControlOptions: Codable, Hashable, Sendable {
    public var maxOptionalResidentGroups: Int
    public var usesMemoryMap: Bool
    public var allowsLazyMaterialization: Bool
    public var placement: String

    public static let `default` = LlamaCppControlOptions(
        maxOptionalResidentGroups: 2,
        usesMemoryMap: true,
        allowsLazyMaterialization: true,
        placement: "METAL_PREFERRED"
    )

    public init(
        maxOptionalResidentGroups: Int,
        usesMemoryMap: Bool,
        allowsLazyMaterialization: Bool,
        placement: String
    ) {
        self.maxOptionalResidentGroups = maxOptionalResidentGroups
        self.usesMemoryMap = usesMemoryMap
        self.allowsLazyMaterialization = allowsLazyMaterialization
        self.placement = placement
    }
}

public struct AnyLayerResidencyPolicy: LayerResidencyPolicy {
    private let handler: @Sendable (ExecutionStateLabel) -> Set<String>

    public init(
        kind: ResidencyPolicyKind,
        inventory: LayerInventory,
        llamaOptions: LlamaCppControlOptions = .default
    ) {
        let allGroupIDs = Set(inventory.groups.map(\.id))
        let coreGroupIDs = Set(inventory.groups.filter(\.alwaysResident).map(\.id))
        let switchGroupIDs = Set(
            inventory.groups
                .filter { !$0.alwaysResident }
                .map(\.id)
        )
        let basePolicy = Qwen3CoderStatePolicy(inventory: inventory)

        switch kind {
        case .allResident:
            handler = { _ in allGroupIDs }

        case .reactive:
            handler = { state in
                basePolicy.desiredGroupIDs(for: state)
            }

        case .llamaCppLazy:
            handler = { [llamaOptions] state in
                // Borrowed control idea: required tensors stay resident; optional
                // groups are admitted only while the placement budget remains.
                let desired = basePolicy.desiredGroupIDs(for: state)
                let desiredSwitchGroups = desired.intersection(switchGroupIDs).sorted()
                let capacity = max(0, llamaOptions.maxOptionalResidentGroups)
                var admitted = Array(desiredSwitchGroups.prefix(capacity))

                // Preserve the current state's required groups even when the cap is
                // exceeded; this models fallback placement rather than semantic skip.
                for groupID in desiredSwitchGroups where !admitted.contains(groupID) {
                    admitted.append(groupID)
                }

                return coreGroupIDs.union(admitted)
            }
        }
    }

    public func desiredGroupIDs(for state: ExecutionStateLabel) -> Set<String> {
        handler(state)
    }
}
