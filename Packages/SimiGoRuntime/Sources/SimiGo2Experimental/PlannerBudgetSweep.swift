import Foundation

public struct PlannerBudgetSweepPoint: Codable, Hashable, Sendable {
    public let sequenceID: String
    public let states: [ExecutionStateLabel]
    public let budgetPercent: Double
    public let budgetBytes: Int64
    public let transitionCount: Int
    public let overflowTransitionCount: Int
    public let cumulativeLoadedBytes: Int64
    public let cumulativeEvictedBytes: Int64
    public let peakResidentBytes: Int64
    public let finalResidentBytes: Int64
    public let fitsBudget: Bool
}

public struct PlannerBudgetSweepReport: Codable, Hashable, Sendable {
    public let boundary: String
    public let recommendedBytes: Int64
    public let coreBytes: Int64
    public let entries: [PlannerBudgetSweepPoint]
}

public enum PlannerBudgetSweep {
    public static let defaultBudgetPercents: [Double] = [
        25, 40, 50, 60, 70, 80, 90, 100, 110, 120, 150,
    ]

    public static func run(
        inventory: LayerInventory,
        sequenceIDs: [String]? = nil,
        budgetPercents: [Double] = defaultBudgetPercents
    ) throws -> PlannerBudgetSweepReport {
        guard !budgetPercents.isEmpty else {
            throw PlannerBudgetSweepError.noBudgets
        }
        guard budgetPercents.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw PlannerBudgetSweepError.invalidBudget
        }

        let selectedSequences = try (sequenceIDs ?? StateSequenceCatalog.cases.map(\.id))
            .map(StateSequenceCatalog.named)
        let planner = ExecutionResidencyPlanner(inventory: inventory)
        let requiredPolicy = Qwen3CoderStatePolicy(inventory: inventory)
        let groupLookup = Dictionary(uniqueKeysWithValues: inventory.groups.map { ($0.id, $0) })
        let coreGroupIDs = Set(inventory.groups.filter(\.alwaysResident).map(\.id))
        let optionalGroupIDs = Set(inventory.groups.filter { !$0.alwaysResident }.map(\.id))
        let coreBytes = inventory.groups
            .filter(\.alwaysResident)
            .reduce(Int64(0)) { $0 + $1.byteCount }

        var entries: [PlannerBudgetSweepPoint] = []
        entries.reserveCapacity(selectedSequences.count * budgetPercents.count)

        for sequence in selectedSequences {
            for percent in budgetPercents.sorted() {
                let budget = ResidencyBudgetPolicy(
                    percentageOfRecommendedBytes: percent
                )
                var resident = coreGroupIDs
                var cumulativeLoadedBytes: Int64 = 0
                var cumulativeEvictedBytes: Int64 = 0
                var peakResidentBytes: Int64 = 0
                var overflowTransitionCount = 0
                var fitsBudget = true

                for state in sequence.states {
                    let required = requiredPolicy.desiredGroupIDs(for: state)
                    let history = sequence.states
                        .prefix(while: { $0 != state })
                        .suffix(3)
                        .map { requiredPolicy.desiredGroupIDs(for: $0) }
                    let hints = optionalGroupIDs.map { groupID -> ResidencyDemandHint in
                        let recentIndex = history.lastIndex(where: { $0.contains(groupID) })
                        let priority = recentIndex.map { index in
                            1.0 - Double(history.count - 1 - index) * 0.25
                        } ?? 0.1
                        return ResidencyDemandHint(
                            groupID: groupID,
                            priority: priority,
                            reason: "RECENT_STATE_DESCRIPTIVE_HINT"
                        )
                    }

                    let plan = try planner.plan(
                        currentResidentGroupIDs: resident,
                        requiredGroupIDs: required,
                        demandHints: hints,
                        budget: budget,
                        recommendedBytes: inventory.totalByteCount
                    )

                    cumulativeLoadedBytes += plan.loadGroupIDs.reduce(Int64(0)) {
                        $0 + (groupLookup[$1]?.byteCount ?? 0)
                    }
                    cumulativeEvictedBytes += plan.evictGroupIDs.reduce(Int64(0)) {
                        $0 + (groupLookup[$1]?.byteCount ?? 0)
                    }
                    peakResidentBytes = max(peakResidentBytes, plan.residentBytes)
                    resident = plan.residentGroupIDs

                    if !plan.fitsBudget {
                        overflowTransitionCount += 1
                        fitsBudget = false
                    }
                }

                let finalResidentBytes = resident.reduce(Int64(0)) {
                    $0 + (groupLookup[$1]?.byteCount ?? 0)
                }

                entries.append(
                    PlannerBudgetSweepPoint(
                        sequenceID: sequence.id,
                        states: sequence.states,
                        budgetPercent: percent,
                        budgetBytes: budget.resolve(recommendedBytes: inventory.totalByteCount),
                        transitionCount: sequence.states.count,
                        overflowTransitionCount: overflowTransitionCount,
                        cumulativeLoadedBytes: cumulativeLoadedBytes,
                        cumulativeEvictedBytes: cumulativeEvictedBytes,
                        peakResidentBytes: peakResidentBytes,
                        finalResidentBytes: finalResidentBytes,
                        fitsBudget: fitsBudget
                    )
                )
            }
        }

        return PlannerBudgetSweepReport(
            boundary:
                "SIMULATOR_ONLY / DESCRIPTIVE_RECENCY_HINTS / NOT_PREDICTION / NOT_DEMAND_CLAIM",
            recommendedBytes: inventory.totalByteCount,
            coreBytes: coreBytes,
            entries: entries
        )
    }
}

public enum PlannerBudgetSweepError: Error, Equatable, Sendable {
    case noBudgets
    case invalidBudget
}
