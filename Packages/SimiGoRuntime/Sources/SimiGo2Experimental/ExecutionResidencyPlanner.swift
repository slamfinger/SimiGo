import Foundation

public struct ResidencyDemandHint: Hashable, Sendable, Codable {
    public let groupID: String
    public let priority: Double
    public let reason: String?

    public init(groupID: String, priority: Double, reason: String? = nil) {
        self.groupID = groupID
        self.priority = priority
        self.reason = reason
    }
}

public struct ResidencyBudgetPolicy: Hashable, Sendable, Codable {
    public enum Kind: String, Codable, Sendable {
        case fixedBytes
        case percentageOfRecommendedBytes
    }

    public let kind: Kind
    public let value: Double

    public init(fixedBytes: Int64) {
        self.kind = .fixedBytes
        self.value = Double(fixedBytes)
    }

    public init(percentageOfRecommendedBytes percentage: Double) {
        self.kind = .percentageOfRecommendedBytes
        self.value = percentage
    }

    public func resolve(recommendedBytes: Int64) -> Int64 {
        guard recommendedBytes > 0 else { return 0 }

        switch kind {
        case .fixedBytes:
            return max(0, Int64(value))
        case .percentageOfRecommendedBytes:
            guard value > 0 else { return 0 }
            return max(0, Int64(Double(recommendedBytes) * value / 100.0))
        }
    }
}

public struct ResidencyPlan: Hashable, Sendable, Codable {
    public let budgetBytes: Int64
    public let residentGroupIDs: Set<String>
    public let loadGroupIDs: Set<String>
    public let keepGroupIDs: Set<String>
    public let evictGroupIDs: Set<String>
    public let overflowGroupIDs: Set<String>
    public let residentBytes: Int64

    public var fitsBudget: Bool { overflowGroupIDs.isEmpty }
}

/// Pure planning layer. It does not load tensors, touch MLX, or mutate a model.
///
/// required execution set
///        ↓
/// residency planning
///        ↓
/// materialization / eviction
///
/// requiredGroupIDs are mandatory for the current execution. Demand hints
/// choose additional optional groups to retain/preload. Groups without a
/// hint are never auto-retained: an unhinted optional group is not a
/// retention candidate (contract R1.4 — no hints must not invent
/// additional demand).
public struct ExecutionResidencyPlanner: Sendable {
    public let inventory: LayerInventory

    public init(inventory: LayerInventory) {
        self.inventory = inventory
    }

    public func plan(
        currentResidentGroupIDs: Set<String>,
        requiredGroupIDs: Set<String>,
        demandHints: [ResidencyDemandHint],
        budget: ResidencyBudgetPolicy,
        recommendedBytes: Int64
    ) throws -> ResidencyPlan {
        let lookup = Dictionary(uniqueKeysWithValues: inventory.groups.map { ($0.id, $0) })
        let knownIDs = Set(inventory.groups.map(\.id))

        guard requiredGroupIDs.isSubset(of: knownIDs) else {
            throw PlannerError.unknownRequiredGroup
        }
        guard currentResidentGroupIDs.isSubset(of: knownIDs) else {
            throw PlannerError.unknownResidentGroup
        }

        var priorities: [String: Double] = [:]
        for hint in demandHints where knownIDs.contains(hint.groupID) {
            guard hint.priority.isFinite else {
                throw PlannerError.nonFinitePriority
            }
            priorities[hint.groupID] = max(priorities[hint.groupID] ?? -.infinity, hint.priority)
        }

        let budgetBytes = budget.resolve(recommendedBytes: recommendedBytes)
        let core = Set(inventory.groups.filter(\.alwaysResident).map(\.id))

        var desired = core.union(requiredGroupIDs)
        var residentBytes = desired.reduce(Int64(0)) {
            $0 + (lookup[$1]?.byteCount ?? 0)
        }

        let mandatory = core.union(requiredGroupIDs)
        var overflow: Set<String> = []
        if residentBytes > budgetBytes {
            overflow = mandatory
        }

        // Only hinted groups are retention candidates: unhinted optionals
        // are never auto-retained (contract R1.4).
        let optionalCandidates = inventory.groups
            .filter { !desired.contains($0.id) && priorities[$0.id] != nil }
            .sorted {
                let left = priorities[$0.id] ?? 0
                let right = priorities[$1.id] ?? 0
                if left != right { return left > right }
                if $0.byteCount != $1.byteCount { return $0.byteCount < $1.byteCount }
                return $0.id < $1.id
            }

        for group in optionalCandidates {
            let remaining = budgetBytes - residentBytes
            if group.byteCount <= remaining {
                desired.insert(group.id)
                residentBytes += group.byteCount
            }
        }

        if residentBytes > budgetBytes {
            overflow.formUnion(mandatory)
        }

        return ResidencyPlan(
            budgetBytes: budgetBytes,
            residentGroupIDs: desired,
            loadGroupIDs: desired.subtracting(currentResidentGroupIDs),
            keepGroupIDs: desired.intersection(currentResidentGroupIDs),
            evictGroupIDs: currentResidentGroupIDs.subtracting(desired),
            overflowGroupIDs: overflow,
            residentBytes: residentBytes
        )
    }

    public enum PlannerError: Error, Equatable, Sendable {
        case unknownRequiredGroup
        case unknownResidentGroup
        case nonFinitePriority
    }
}
