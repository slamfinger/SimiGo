import Foundation

/// One replayable workload step. The execution state mapping is a declared
/// scenario-level label, not a measured or predicted demand.
public struct WorkloadTraceStep: Codable, Hashable, Sendable {
    public let operation: String
    public let executionState: ExecutionStateLabel
    public let mappingReason: String

    public init(
        operation: String,
        executionState: ExecutionStateLabel,
        mappingReason: String
    ) {
        self.operation = operation
        self.executionState = executionState
        self.mappingReason = mappingReason
    }
}

/// A replayable workload trace replacing synthetic state sequences. The
/// operation-to-state mapping is registered with the trace definition.
public struct WorkloadTrace: Codable, Hashable, Sendable {
    public let id: String
    public let kind: String
    public let summary: String
    public let steps: [WorkloadTraceStep]

    public init(id: String, kind: String, summary: String, steps: [WorkloadTraceStep]) {
        self.id = id
        self.kind = kind
        self.summary = summary
        self.steps = steps
    }
}

public enum WorkloadTraceCatalog {
    public static let traces: [WorkloadTrace] = [
        WorkloadTrace(
            id: "T1_DOCUMENT_SESSION",
            kind: "DOCUMENT",
            summary: "open → summarize → search → edit → recheck → save on one document",
            steps: [
                WorkloadTraceStep(
                    operation: "OPEN_DOCUMENT",
                    executionState: .stateA,
                    mappingReason: "single active document; localized intake"
                ),
                WorkloadTraceStep(
                    operation: "SUMMARIZE_DOCUMENT",
                    executionState: .stateAB,
                    mappingReason: "whole-document comprehension spans adjacent capability groups"
                ),
                WorkloadTraceStep(
                    operation: "SEARCH_DOCUMENT",
                    executionState: .stateA,
                    mappingReason: "targeted lookup; localized"
                ),
                WorkloadTraceStep(
                    operation: "EDIT_DOCUMENT",
                    executionState: .stateB,
                    mappingReason: "localized rewrite outside the intake region"
                ),
                WorkloadTraceStep(
                    operation: "RECHECK_DOCUMENT",
                    executionState: .stateAB,
                    mappingReason: "cross-region consistency check"
                ),
                WorkloadTraceStep(
                    operation: "SAVE_DOCUMENT",
                    executionState: .stateA,
                    mappingReason: "write-out; localized"
                )
            ]
        ),
        WorkloadTrace(
            id: "T2_COMPUTER_OPERATION",
            kind: "COMPUTER_OPERATION",
            summary: "file inspect → tool call → tool result → next operation → tool call again",
            steps: [
                WorkloadTraceStep(
                    operation: "FILE_INSPECT",
                    executionState: .stateA,
                    mappingReason: "file browsing; localized"
                ),
                WorkloadTraceStep(
                    operation: "TOOL_CALL_1",
                    executionState: .stateAB,
                    mappingReason: "tool invocation engages a broader capability set"
                ),
                WorkloadTraceStep(
                    operation: "TOOL_RESULT_1",
                    executionState: .stateB,
                    mappingReason: "result consumption stays on the tool-side set"
                ),
                WorkloadTraceStep(
                    operation: "NEXT_OPERATION",
                    executionState: .stateA,
                    mappingReason: "next browsing step; localized"
                ),
                WorkloadTraceStep(
                    operation: "TOOL_CALL_2",
                    executionState: .stateAB,
                    mappingReason: "second tool invocation; same broader set"
                )
            ]
        ),
        WorkloadTrace(
            id: "T3_AGENTIC_MULTI_TURN",
            kind: "AGENTIC_MULTI_TURN",
            summary: "three user turns interleaved with tool calls and results, then a final answer",
            steps: [
                WorkloadTraceStep(
                    operation: "USER_TURN_1",
                    executionState: .stateA,
                    mappingReason: "user request phrasing; localized"
                ),
                WorkloadTraceStep(
                    operation: "TOOL_CALL_1",
                    executionState: .stateAB,
                    mappingReason: "tool invocation; broader capability set"
                ),
                WorkloadTraceStep(
                    operation: "TOOL_RESULT_1",
                    executionState: .stateB,
                    mappingReason: "result consumption; tool-side set"
                ),
                WorkloadTraceStep(
                    operation: "USER_TURN_2",
                    executionState: .stateA,
                    mappingReason: "follow-up request; localized"
                ),
                WorkloadTraceStep(
                    operation: "TOOL_CALL_2",
                    executionState: .stateAB,
                    mappingReason: "tool invocation; broader capability set"
                ),
                WorkloadTraceStep(
                    operation: "TOOL_RESULT_2",
                    executionState: .stateB,
                    mappingReason: "result consumption; tool-side set"
                ),
                WorkloadTraceStep(
                    operation: "USER_TURN_3",
                    executionState: .stateA,
                    mappingReason: "third request; localized"
                ),
                WorkloadTraceStep(
                    operation: "TOOL_CALL_3",
                    executionState: .stateAB,
                    mappingReason: "tool invocation; broader capability set"
                ),
                WorkloadTraceStep(
                    operation: "FINAL_ANSWER",
                    executionState: .stateAll,
                    mappingReason: "final long-form answer draws on the full capability space"
                )
            ]
        ),
        WorkloadTrace(
            id: "T4_LONG_CONTEXT",
            kind: "LONG_CONTEXT",
            summary: "one loaded context, repeated executions over different regions, then a summary",
            steps: [
                WorkloadTraceStep(
                    operation: "CONTEXT_LOAD",
                    executionState: .stateAll,
                    mappingReason: "initial full-context ingest"
                ),
                WorkloadTraceStep(
                    operation: "EXTRACT_1",
                    executionState: .stateAB,
                    mappingReason: "extraction in one context region"
                ),
                WorkloadTraceStep(
                    operation: "EXTRACT_2",
                    executionState: .stateBC,
                    mappingReason: "extraction in a different region; different group pair"
                ),
                WorkloadTraceStep(
                    operation: "EXTRACT_3",
                    executionState: .stateAB,
                    mappingReason: "return to the first region"
                ),
                WorkloadTraceStep(
                    operation: "CONTEXT_SUMMARY",
                    executionState: .stateAll,
                    mappingReason: "summary over the whole context"
                )
            ]
        )
    ]

    public static func named(_ id: String) throws -> WorkloadTrace {
        guard let value = traces.first(where: { $0.id == id }) else {
            throw LayerResidencyError.unknownWorkloadTrace(id)
        }
        return value
    }
}

public struct TraceReplayStepRecord: Codable, Hashable, Sendable {
    public let stepIndex: Int
    public let operation: String
    public let executionState: ExecutionStateLabel
    public let requiredGroupIDs: [String]
    public let residentBeforeGroupIDs: [String]
    public let residentAfterGroupIDs: [String]
    public let requiredHitBytes: Int64
    public let requiredMissBytes: Int64
    public let loadedBytes: Int64
    public let evictedBytes: Int64
    public let residentBytes: Int64
    public let budgetBytes: Int64
    public let overflow: Bool
}

public struct TraceReplayRun: Codable, Hashable, Sendable {
    public let traceID: String
    public let budgetPercent: Double
    public let budgetBytes: Int64
    public let stepCount: Int
    public let stepRecords: [TraceReplayStepRecord]
    public let cumulativeLoadedBytes: Int64
    public let cumulativeEvictedBytes: Int64
    public let requiredHitBytesTotal: Int64
    public let requiredMissBytesTotal: Int64
    public let requiredHitRatio: Double
    public let zeroRetentionMissBytesTotal: Int64
    public let reloadReductionVsZeroRetentionBytes: Int64
    public let overflowStepCount: Int
    public let peakResidentBytes: Int64
    public let optionalGroupLoadCounts: [String: Int]
    public let optionalGroupRequiredStepIndices: [String: [Int]]
}

public struct WorkloadTraceReplayReport: Codable, Hashable, Sendable {
    public let boundary: String
    public let recommendedBytes: Int64
    public let coreBytes: Int64
    public let runs: [TraceReplayRun]
}

/// Simulator-only replay of declared workload traces through the
/// ExecutionResidencyPlanner. Hints use strictly prior steps of the same trace
/// and remain descriptive recency labels; they do not predict future state.
public enum WorkloadTraceReplay {
    public static let defaultBudgetPercents: [Double] = [40, 70, 100, 150]

    public static func run(
        inventory: LayerInventory,
        traces: [WorkloadTrace]? = nil,
        budgetPercents: [Double] = defaultBudgetPercents,
        policy: LayerResidencyPolicy? = nil
    ) throws -> WorkloadTraceReplayReport {
        guard !budgetPercents.isEmpty else {
            throw WorkloadTraceReplayError.noBudgets
        }
        guard budgetPercents.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw WorkloadTraceReplayError.invalidBudget
        }

        let selectedTraces = traces ?? WorkloadTraceCatalog.traces
        let resolvedPolicy = policy ?? Qwen3CoderStatePolicy(inventory: inventory)
        let planner = ExecutionResidencyPlanner(inventory: inventory)
        let groupLookup = Dictionary(uniqueKeysWithValues: inventory.groups.map { ($0.id, $0) })
        let coreGroupIDs = Set(inventory.groups.filter(\.alwaysResident).map(\.id))
        let optionalGroupIDs = Set(inventory.groups.filter { !$0.alwaysResident }.map(\.id))
        let coreBytes = inventory.groups
            .filter(\.alwaysResident)
            .reduce(Int64(0)) { $0 + $1.byteCount }

        func bytes(_ groupIDs: Set<String>) -> Int64 {
            groupIDs.reduce(Int64(0)) { $0 + (groupLookup[$1]?.byteCount ?? 0) }
        }

        var runs: [TraceReplayRun] = []
        runs.reserveCapacity(selectedTraces.count * budgetPercents.count)

        for trace in selectedTraces {
            for percent in budgetPercents.sorted() {
                let budget = ResidencyBudgetPolicy(percentageOfRecommendedBytes: percent)
                var resident = coreGroupIDs
                var stepRecords: [TraceReplayStepRecord] = []
                stepRecords.reserveCapacity(trace.steps.count)

                var cumulativeLoadedBytes: Int64 = 0
                var cumulativeEvictedBytes: Int64 = 0
                var requiredHitBytesTotal: Int64 = 0
                var requiredMissBytesTotal: Int64 = 0
                var zeroRetentionMissBytesTotal: Int64 = 0
                var overflowStepCount = 0
                var peakResidentBytes: Int64 = 0
                var optionalGroupLoadCounts: [String: Int] = [:]
                var optionalGroupRequiredStepIndices: [String: [Int]] = [:]

                for (index, step) in trace.steps.enumerated() {
                    let required = resolvedPolicy.desiredGroupIDs(for: step.executionState)
                    let priorStates = trace.steps.prefix(index).map(\.executionState)
                    let hints = recencyHints(
                        priorStates: priorStates,
                        policy: resolvedPolicy,
                        optionalGroupIDs: optionalGroupIDs
                    )

                    let plan = try planner.plan(
                        currentResidentGroupIDs: resident,
                        requiredGroupIDs: required,
                        demandHints: hints,
                        budget: budget,
                        recommendedBytes: inventory.totalByteCount
                    )

                    let hitBytes = bytes(required.intersection(resident))
                    let missBytes = bytes(required.subtracting(resident))
                    let loadedBytes = bytes(plan.loadGroupIDs)
                    let evictedBytes = bytes(plan.evictGroupIDs)

                    stepRecords.append(
                        TraceReplayStepRecord(
                            stepIndex: index,
                            operation: step.operation,
                            executionState: step.executionState,
                            requiredGroupIDs: required.sorted(),
                            residentBeforeGroupIDs: resident.sorted(),
                            residentAfterGroupIDs: plan.residentGroupIDs.sorted(),
                            requiredHitBytes: hitBytes,
                            requiredMissBytes: missBytes,
                            loadedBytes: loadedBytes,
                            evictedBytes: evictedBytes,
                            residentBytes: plan.residentBytes,
                            budgetBytes: plan.budgetBytes,
                            overflow: !plan.fitsBudget
                        )
                    )

                    requiredHitBytesTotal += hitBytes
                    requiredMissBytesTotal += missBytes
                    zeroRetentionMissBytesTotal += bytes(required.subtracting(coreGroupIDs))
                    cumulativeLoadedBytes += loadedBytes
                    cumulativeEvictedBytes += evictedBytes
                    peakResidentBytes = max(peakResidentBytes, plan.residentBytes)
                    if !plan.fitsBudget {
                        overflowStepCount += 1
                    }
                    for groupID in plan.loadGroupIDs where optionalGroupIDs.contains(groupID) {
                        optionalGroupLoadCounts[groupID, default: 0] += 1
                    }
                    for groupID in required where optionalGroupIDs.contains(groupID) {
                        optionalGroupRequiredStepIndices[groupID, default: []].append(index)
                    }

                    resident = plan.residentGroupIDs
                }

                let hitDenominator = requiredHitBytesTotal + requiredMissBytesTotal

                runs.append(
                    TraceReplayRun(
                        traceID: trace.id,
                        budgetPercent: percent,
                        budgetBytes: budget.resolve(recommendedBytes: inventory.totalByteCount),
                        stepCount: trace.steps.count,
                        stepRecords: stepRecords,
                        cumulativeLoadedBytes: cumulativeLoadedBytes,
                        cumulativeEvictedBytes: cumulativeEvictedBytes,
                        requiredHitBytesTotal: requiredHitBytesTotal,
                        requiredMissBytesTotal: requiredMissBytesTotal,
                        requiredHitRatio:
                            hitDenominator == 0
                            ? 1.0
                            : Double(requiredHitBytesTotal) / Double(hitDenominator),
                        zeroRetentionMissBytesTotal: zeroRetentionMissBytesTotal,
                        reloadReductionVsZeroRetentionBytes:
                            zeroRetentionMissBytesTotal - requiredMissBytesTotal,
                        overflowStepCount: overflowStepCount,
                        peakResidentBytes: peakResidentBytes,
                        optionalGroupLoadCounts: optionalGroupLoadCounts,
                        optionalGroupRequiredStepIndices: optionalGroupRequiredStepIndices
                    )
                )
            }
        }

        return WorkloadTraceReplayReport(
            boundary:
                "SIMULATOR_ONLY / DECLARED_TRACE_STATE_MAPPING / DESCRIPTIVE_RECENCY_HINTS / NOT_PREDICTION / NOT_DEMAND_CLAIM",
            recommendedBytes: inventory.totalByteCount,
            coreBytes: coreBytes,
            runs: runs
        )
    }

    /// Same recency construction as PlannerBudgetSweep: a three-step window
    /// over strictly prior steps, decayed priorities, 0.1 baseline. Prior-only
    /// by construction; no future step is read.
    static func recencyHints(
        priorStates: [ExecutionStateLabel],
        policy: LayerResidencyPolicy,
        optionalGroupIDs: Set<String>
    ) -> [ResidencyDemandHint] {
        let history = priorStates.suffix(3).map { policy.desiredGroupIDs(for: $0) }
        return optionalGroupIDs.map { groupID in
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
    }
}

public enum WorkloadTraceReplayError: Error, Equatable, Sendable {
    case noBudgets
    case invalidBudget
}
