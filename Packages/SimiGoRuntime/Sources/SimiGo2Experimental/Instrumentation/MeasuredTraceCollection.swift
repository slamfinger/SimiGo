import Foundation
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXLLM
import MLXNN
import Tokenizers

/// G1.9-C Measured Execution Trace Collection.
///
/// Connects the pilot-validated passive observer to the registered workload
/// traces. Two lines are kept separate by construction:
///
///   declared line : WorkloadTrace → state → declared optional groups
///                   (scenario declaration, registered with the catalog)
///   measured line : Input (operation prompt) → MeasuredExecutionTrace
///                   (observed layerEntered events only)
///
/// The report records both per step but never merges them: no field asserts
/// `state = measured demand`. The registered architectural expectation is
/// that measured execution at layer/group resolution covers all decoder
/// layer groups on every pass; the collection exists to convert that
/// expectation into a measured fact and to quantify the declared/measured
/// divergence.

public struct MeasuredStepRecord: Codable, Sendable {
    public let traceID: String
    public let stepIndex: Int
    public let operation: String
    public let executionState: String
    public let prompt: String
    /// Declared optional groups for this step (scenario line, registered
    /// catalog mapping; core excluded as always-resident).
    public let declaredOptionalGroupIDs: [String]
    /// Observed groups in this operation's measured trace (measured line).
    public let measuredGroupIDs: [String]
    public let measuredGroupEventCounts: [String: Int]
    public let passCount: Int
    public let eventCount: Int
    public let generatedTokenCount: Int
    public let generationMilliseconds: Double
}

public struct MeasuredWorkloadRecord: Codable, Sendable {
    public let traceID: String
    public let summary: String
    public let steps: [MeasuredStepRecord]
}

public struct CollectionPreambleRecord: Codable, Sendable {
    public let controlPrompt: String
    public let baselineText: String
    public let instrumentedText: String
    public let baselineTokenIDs: [Int]
    public let instrumentedTokenIDs: [Int]
    public let identityPass: Bool
}

public struct MeasuredTraceCollectionReport: Codable, Sendable {
    public let status: String
    public let boundary: String
    public let protocolVersion: String
    public let modelID: String
    public let modelType: String
    public let instrumentedModuleCount: Int
    public let preamble: CollectionPreambleRecord
    public let workloads: [MeasuredWorkloadRecord]
}

public enum MeasuredTraceCollection {
    public static let protocolVersion = "G1.9-C.COLLECT.V1"
    public static let controlPrompt = "Return exactly one word: ping"

    /// Registered scenario realizations: one concrete input per workload
    /// operation. These are declared prompts, not measured or predicted
    /// demand.
    public static let operationPrompts: [String: [String: String]] = [
        "T1_DOCUMENT_SESSION": [
            "OPEN_DOCUMENT": "Open the project report and read the first section.",
            "SUMMARIZE_DOCUMENT": "Summarize the report you just opened in two sentences.",
            "SEARCH_DOCUMENT": "Find every mention of the delivery date in the report.",
            "EDIT_DOCUMENT": "Rewrite the second paragraph of the report more concisely.",
            "RECHECK_DOCUMENT": "Check the edited paragraph against the rest of the report.",
            "SAVE_DOCUMENT": "Confirm the changes and save the report.",
        ],
        "T2_COMPUTER_OPERATION": [
            "FILE_INSPECT": "List the files in the current project folder.",
            "TOOL_CALL_1": "Run the test suite for this project and report failures.",
            "TOOL_RESULT_1": "The test run returned three failures. Which module do they belong to?",
            "NEXT_OPERATION": "Inspect the failing module's main file.",
            "TOOL_CALL_2": "Run the failing module's tests again with verbose output.",
        ],
        "T3_AGENTIC_MULTI_TURN": [
            "USER_TURN_1": "Find the largest file in this repository.",
            "TOOL_CALL_1": "Search the repository for files larger than ten megabytes.",
            "TOOL_RESULT_1": "The search found one large asset file. Continue.",
            "USER_TURN_2": "Now check when that file was last modified.",
            "TOOL_CALL_2": "Look up the modification history of that asset file.",
            "TOOL_RESULT_2": "The file was modified two weeks ago. Continue.",
            "USER_TURN_3": "Summarize what we found about this file.",
            "TOOL_CALL_3": "Collect the file size and modification date into one line.",
            "FINAL_ANSWER": "Write the final one-paragraph answer about the asset file.",
        ],
        "T4_LONG_CONTEXT": [
            "CONTEXT_LOAD": "Read the whole conversation above as one context.",
            "EXTRACT_1": "Extract the first question asked in this context.",
            "EXTRACT_2": "Extract the last answer given in this context.",
            "EXTRACT_3": "Extract the first question again and compare it with the last answer.",
            "CONTEXT_SUMMARY": "Summarize the entire context in three sentences.",
        ],
    ]

    /// Every registered workload step must have a scenario prompt.
    public static func validatePromptCoverage() throws {
        for trace in WorkloadTraceCatalog.traces {
            guard let prompts = operationPrompts[trace.id] else {
                throw CollectionError.missingPromptSet(trace.id)
            }
            for step in trace.steps where prompts[step.operation] == nil {
                throw CollectionError.missingPrompt(trace.id, step.operation)
            }
        }
    }

    public static func run(
        modelDirectory: URL,
        maxTokens: Int = 16
    ) async throws -> MeasuredTraceCollectionReport {
        try validatePromptCoverage()
        let inventory = try SafetensorsInventoryReader.readModelGroups(
            modelDirectory: modelDirectory
        )
        let declaredPolicy = ContiguousLayerStatePolicy(inventory: inventory)
        let coreGroupIDs = Set(inventory.groups.filter(\.alwaysResident).map(\.id))
        let container = try await LLMModelFactory.shared.loadContainer(
            from: modelDirectory,
            using: #huggingFaceTokenizerLoader()
        )
        let modelID = modelDirectory.path

        // Preamble: one baseline generation, then install, then one
        // instrumented generation of the same control prompt. Collection
        // proceeds only when identity holds.
        let baselineOutcome = try await ChatTemplateGeneration.generateWithTokens(
            container: container,
            modelDirectory: modelDirectory,
            prompt: controlPrompt,
            maxTokens: maxTokens
        )

        let box = ExecutionTraceEventBox()
        let installed = try await container.perform {
            (context: ModelContext) async throws -> [String] in
            let paths = GroupExecutionTraceProbe.allObservationPaths(model: context.model)
            let installed = try GroupExecutionTraceProbe.install(
                model: context.model,
                observationPaths: Set(paths),
                box: box
            )
            return installed
        }
        let modelType = await container.perform {
            (context: ModelContext) -> String in
            String(describing: type(of: context.model))
        }

        let instrumentedOutcome = try await ChatTemplateGeneration.generateWithTokens(
            container: container,
            modelDirectory: modelDirectory,
            prompt: controlPrompt,
            maxTokens: maxTokens
        )
        box.clear()

        let preamble = CollectionPreambleRecord(
            controlPrompt: controlPrompt,
            baselineText: baselineOutcome.text,
            instrumentedText: instrumentedOutcome.text,
            baselineTokenIDs: baselineOutcome.tokenIDs,
            instrumentedTokenIDs: instrumentedOutcome.tokenIDs,
            identityPass: baselineOutcome.tokenIDs == instrumentedOutcome.tokenIDs
        )
        guard preamble.identityPass else {
            throw CollectionError.identityLost
        }

        func generationMilliseconds(_ start: ContinuousClock.Instant) -> Double {
            Double(start.duration(to: .now).components.attoseconds) / 1e18 * 1000
        }

        var workloads: [MeasuredWorkloadRecord] = []

        for trace in WorkloadTraceCatalog.traces {
            var steps: [MeasuredStepRecord] = []
            for (index, traceStep) in trace.steps.enumerated() {
                let prompt = operationPrompts[trace.id]![traceStep.operation]!
                box.clear()
                let start = ContinuousClock.now
                let outcome = try await ChatTemplateGeneration.generateWithTokens(
                    container: container,
                    modelDirectory: modelDirectory,
                    prompt: prompt,
                    maxTokens: maxTokens
                )
                let elapsed = generationMilliseconds(start)
                let events = box.snapshot()
                box.clear()

                let measured = ExecutionTracePilot.measuredTrace(
                    traceID: "COLLECT/\(trace.id)/step\(index)",
                    modelID: modelID,
                    events: events,
                    inventory: inventory
                )
                var measuredGroups: Set<String> = []
                var measuredCounts: [String: Int] = [:]
                for stepRecord in measured.steps {
                    for (group, count) in stepRecord.groupExecutionCounts {
                        measuredGroups.insert(group)
                        measuredCounts[group, default: 0] += count
                    }
                }
                let declaredOptional = declaredPolicy
                    .desiredGroupIDs(for: traceStep.executionState)
                    .subtracting(coreGroupIDs)

                steps.append(
                    MeasuredStepRecord(
                        traceID: trace.id,
                        stepIndex: index,
                        operation: traceStep.operation,
                        executionState: traceStep.executionState.rawValue,
                        prompt: prompt,
                        declaredOptionalGroupIDs: declaredOptional.sorted(),
                        measuredGroupIDs: measuredGroups.sorted(),
                        measuredGroupEventCounts: measuredCounts,
                        passCount: measured.steps.count,
                        eventCount: events.count,
                        generatedTokenCount: outcome.tokenIDs.count,
                        generationMilliseconds: elapsed
                    )
                )
            }
            workloads.append(
                MeasuredWorkloadRecord(
                    traceID: trace.id,
                    summary: trace.summary,
                    steps: steps
                )
            )
        }

        return MeasuredTraceCollectionReport(            status: "COLLECTED",
            boundary:
                "ISOLATED_INSTRUMENTATION / LAYER_ENTERED_ONLY / OBSERVER_PASSIVE / DECLARED_LINE_IS_SCENARIO / MEASURED_LINE_IS_OBSERVATION / NOT_DEMAND / NOT_PREDICTION / EXPERT_DEMAND_NOT_INSTRUMENTED",
            protocolVersion: protocolVersion,
            modelID: modelID,
            modelType: modelType,
            instrumentedModuleCount: installed.count,
            preamble: preamble,
            workloads: workloads
        )
    }

    public enum CollectionError: Error, Equatable {
        case missingPromptSet(String)
        case missingPrompt(String, String)
        case identityLost
    }
}
