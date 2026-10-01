import Foundation

public enum ResidencyPolicyKind: String, Codable, Sendable, CaseIterable {
    case allResident
    case reactive
    case llamaCppLazy
    case executionPlanner

    public var displayName: String {
        switch self {
        case .allResident: return "All groups resident"
        case .reactive: return "External-state reactive"
        case .llamaCppLazy: return "llama.cpp-inspired lazy residency"
        case .executionPlanner: return "Execution residency planner"
        }
    }
}

public struct ExecutionPlannerPolicy: LayerResidencyPolicy {
    private let inventory: LayerInventory
    private let planner: ExecutionResidencyPlanner
    private let requiredPolicy: Qwen3CoderStatePolicy
    private let budgetOverride: ResidencyBudgetPolicy?

    public init(
        inventory: LayerInventory,
        requiredPolicy: Qwen3CoderStatePolicy = Qwen3CoderStatePolicy(
            alwaysResidentGroupIDs: []
        ),
        budget: ResidencyBudgetPolicy? = nil
    ) {
        self.inventory = inventory
        self.planner = ExecutionResidencyPlanner(inventory: inventory)
        self.requiredPolicy = requiredPolicy
        self.budgetOverride = budget
    }

    public func desiredGroupIDs(for state: ExecutionStateLabel) -> Set<String> {
        let required = requiredPolicy.desiredGroupIDs(for: state)
        let budget = budgetOverride ?? strictBudget(for: required)

        guard let plan = try? planner.plan(
            currentResidentGroupIDs: [],
            requiredGroupIDs: required,
            demandHints: [],
            budget: budget,
            recommendedBytes: inventory.totalByteCount
        ) else {
            return requiredPolicy.desiredGroupIDs(for: state)
        }
        return plan.residentGroupIDs
    }

    private func strictBudget(for required: Set<String>) -> ResidencyBudgetPolicy {
        let requiredBytes = inventory.groups
            .filter { required.contains($0.id) }
            .reduce(Int64(0)) { $0 + $1.byteCount }
        return ResidencyBudgetPolicy(fixedBytes: requiredBytes)
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

        case .executionPlanner:
            let plannerPolicy = ExecutionPlannerPolicy(
                inventory: inventory,
                requiredPolicy: basePolicy
            )
            handler = { state in
                plannerPolicy.desiredGroupIDs(for: state)
            }
        }
    }

    public func desiredGroupIDs(for state: ExecutionStateLabel) -> Set<String> {
        handler(state)
    }
}
