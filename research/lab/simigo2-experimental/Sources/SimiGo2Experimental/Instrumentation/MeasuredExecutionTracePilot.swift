import Foundation
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXLLM
import MLXNN
import Tokenizers

/// G1.9-A first pilot: instrumentation feasibility / identity / stability.
///
/// Design audit constraints (2026-09-25 review):
/// - Observation granularity = Layer / Group. Router / Expert /
///   Token×Expert are NOT instrumented (Minimum Sufficient Resolution).
/// - Observer must be passive: the instrumentation changes no parameters,
///   inputs, structure, execution order, cache, or residency; it performs no
///   extra tensor computation and makes no decisions from observations.
/// - Observed vs Derived separation: events assert only `layerEntered`.
///   step IDs and group joins are derived bookkeeping at report time. No
///   demand quantity exists anywhere in this layer — `executed ≠ demand`.
/// - Trace naming: ExecutionTrace (observation). Demand is a later
///   interpretation and has no data structure here.

public struct MeasuredExecutionTrace: Codable, Sendable {
    public let traceID: String
    public let modelID: String
    public let boundary: String

    /// Observed layer: the raw `layerEntered` event stream.
    public let events: [ExecutionTraceEvent]

    /// Derived bookkeeping: step segmentation (layer-0 restart) plus the
    /// declared inventory partition join. Contains no demand quantity.
    public let steps: [ExecutionTraceStepRecord]
}

public struct ExecutionTraceStepRecord: Codable, Sendable {
    public let stepID: Int
    /// Groups in first-entry order within the step.
    public let observedGroupOrder: [String]
    public let groupExecutionCounts: [String: Int]
    public let eventCount: Int
}

public struct PilotIdentityRecord: Codable, Sendable {
    public let promptID: String
    public let prompt: String
    public let promptTokenCount: Int
    public let baselineTokenIDs: [Int]
    public let instrumentedTokenIDs: [Int]
    public let tokenSequenceIdentical: Bool
    public let baselineText: String
    public let instrumentedText: String
    public let baselineLogitsChecksum: String
    public let instrumentedLogitsChecksum: String
    public let logitsBitwiseIdentical: Bool
    public let logitsMaxAbsDiff: Float
    public let logitsRelativeDiff: Float
}

public struct PilotOverheadRecord: Codable, Sendable {
    public let baselineSteadyGenerationMilliseconds: Double
    public let instrumentedGenerationMilliseconds: [Double]
    public let meanInstrumentedGenerationMilliseconds: Double
    public let overheadRatio: Double?
    public let peakMemoryOverheadMegabytes: Double
    public let timingBoundary: String
}

public struct PilotCaseReport: Codable, Sendable {
    public let promptID: String
    public let identity: PilotIdentityRecord
    public let overhead: PilotOverheadRecord
    public let repetitions: Int
    public let traceStableAcrossRepetitions: Bool
    public let passCounts: [Int]
    public let traces: [MeasuredExecutionTrace]
    public let g19a1BaselineIdentityPass: Bool
    public let g19a2TraceStabilityPass: Bool
}

public struct ExecutionTracePilotReport: Codable, Sendable {
    public let status: String
    public let boundary: String
    public let protocolVersion: String
    public let modelID: String
    public let modelType: String
    public let pilotScope: String
    public let instrumentedModuleCount: Int
    public let observedScope: String
    public let cases: [PilotCaseReport]
    public let g19a1BaselineIdentityPass: Bool
    public let g19a2TraceStabilityPass: Bool
    public let g19a3OverheadSummary: [String: Double]
    public let g19a4Scope: String
}

public enum ExecutionTracePilot {
    /// Fixed pilot prompt set (registered).
    public static let prompts: [(id: String, text: String)] = [
        (id: "P1", text: "Return exactly one word: ping"),
        (id: "P2", text: "Count from one to twelve."),
        (id: "P3", text: "Name five colors."),
    ]

    public static let defaultRepetitions = 3

    /// Layer → declared group join from the model-aware inventory. Returns
    /// nil for core layers (core entry is not directly observed by the pilot
    /// capture points).
    public static func groupID(forLayer layer: Int, inventory: LayerInventory) -> String? {
        for group in inventory.groups where !group.alwaysResident {
            if let range = parseLayerRange(group.layerRangeDescription),
                layer >= range.lowerBound, layer <= range.upperBound
            {
                return group.id
            }
        }
        return nil
    }

    static func parseLayerRange(_ description: String) -> ClosedRange<Int>? {
        let parts = description.split(separator: "-")
        guard parts.count == 2, let lo = Int(parts[0]), let hi = Int(parts[1]) else {
            return nil
        }
        return lo...hi
    }

    /// Derived bookkeeping: segment the observed event stream into forward
    /// passes (a pass starts where the layer-0 module fires again) and join
    /// each event to its declared group. Pure function of the events plus
    /// the registered inventory; no demand interpretation.
    public static func measuredTrace(
        traceID: String,
        modelID: String,
        events: [ExecutionTraceEvent],
        inventory: LayerInventory
    ) -> MeasuredExecutionTrace {
        var steps: [ExecutionTraceStepRecord] = []
        var currentOrder: [String] = []
        var currentCounts: [String: Int] = [:]
        var currentEventCount = 0

        func closeStep() {
            guard currentEventCount > 0 else { return }
            steps.append(
                ExecutionTraceStepRecord(
                    stepID: steps.count,
                    observedGroupOrder: currentOrder,
                    groupExecutionCounts: currentCounts,
                    eventCount: currentEventCount
                )
            )
            currentOrder = []
            currentCounts = [:]
            currentEventCount = 0
        }

        var layerZeroPath: String?
        for event in events {
            if event.decoderLayer == 0 {
                if event.modulePath == layerZeroPath {
                    closeStep()
                } else if layerZeroPath == nil {
                    layerZeroPath = event.modulePath
                }
            }
            let group = groupID(forLayer: event.decoderLayer, inventory: inventory)
            if let group, currentCounts[group] == nil {
                currentOrder.append(group)
            }
            if let group {
                currentCounts[group, default: 0] += 1
            }
            currentEventCount += 1
        }
        closeStep()

        return MeasuredExecutionTrace(
            traceID: traceID,
            modelID: modelID,
            boundary:
                "OBSERVED_LAYER_ENTERED_ONLY / GROUP_JOIN_DERIVED / NOT_DEMAND / NOT_PREDICTION",
            events: events,
            steps: steps
        )
    }

    public static func run(
        modelDirectory: URL,
        repetitions: Int = defaultRepetitions,
        maxTokens: Int = 24
    ) async throws -> ExecutionTracePilotReport {
        guard repetitions >= 2 else {
            throw PilotError.insufficientRepetitions
        }
        let inventory = try SafetensorsInventoryReader.readModelGroups(
            modelDirectory: modelDirectory
        )
        let container = try await LLMModelFactory.shared.loadContainer(
            from: modelDirectory,
            using: #huggingFaceTokenizerLoader()
        )
        let modelID = modelDirectory.path

        // Baseline phase: per prompt — warm logits forward (checksum kept),
        // warm generation, timed steady generation. No instrumentation yet.
        var baselineLogits: [String: MLXArray] = [:]
        var baselineTokenIDs: [String: [Int]] = [:]
        var baselineTexts: [String: String] = [:]
        var baselineGeneratedTokenIDs: [String: [Int]] = [:]
        var baselineChecksums: [String: String] = [:]
        var baselineSteadyMs: [String: Double] = [:]
        var promptTokenCounts: [String: Int] = [:]

        for promptCase in prompts {
            let (tokenIDs, checksum) = try await container.perform {
                (context: ModelContext) async throws -> ([Int], String) in
                let tokenIDs = try await ChatTemplateGeneration.promptTokenIDs(
                    tokenizer: context.tokenizer,
                    modelDirectory: modelDirectory,
                    prompt: promptCase.text
                )
                let input = MLXArray(tokenIDs, [1, tokenIDs.count])
                _ = context.model(input, cache: nil)
                let logits = context.model(input, cache: nil)
                eval(logits)
                let checksum = InstrumentationIdentityProbe.sha256Base64(logits)
                Memory.clearCache()
                return (tokenIDs, checksum)
            }
            baselineTokenIDs[promptCase.id] = tokenIDs
            baselineChecksums[promptCase.id] = checksum
            promptTokenCounts[promptCase.id] = tokenIDs.count

            let baselineBox = try await container.perform {
                (context: ModelContext) async throws -> UnsafeSendableBox<MLXArray> in
                let input = MLXArray(tokenIDs, [1, tokenIDs.count])
                let logits = context.model(input, cache: nil)
                eval(logits)
                return UnsafeSendableBox(value: logits)
            }
            baselineLogits[promptCase.id] = baselineBox.value

            _ = try await ChatTemplateGeneration.generate(
                container: container,
                modelDirectory: modelDirectory,
                prompt: promptCase.text,
                maxTokens: maxTokens
            )
            let steadyStart = ContinuousClock.now
            let outcome = try await ChatTemplateGeneration.generateWithTokens(
                container: container,
                modelDirectory: modelDirectory,
                prompt: promptCase.text,
                maxTokens: maxTokens
            )
            baselineSteadyMs[promptCase.id] =
                Double(steadyStart.duration(to: .now).components.attoseconds) / 1e18 * 1000
            baselineTexts[promptCase.id] = outcome.text
            baselineGeneratedTokenIDs[promptCase.id] = outcome.tokenIDs
        }

        let memoryBeforeInstrumented = Memory.snapshot()

        // Install trace modules once; replacement persists across perform
        // blocks.
        let box = ExecutionTraceEventBox()
        let installed = try await container.perform {
            (context: ModelContext) async throws -> [String] in
            let paths = GroupExecutionTraceProbe.allObservationPaths(model: context.model)
            return try GroupExecutionTraceProbe.install(
                model: context.model,
                observationPaths: Set(paths),
                box: box
            )
        }

        // Instrumented phase: per prompt — logits forward (checksum kept for
        // bitwise comparison), then `repetitions` traced generations.
        var cases: [PilotCaseReport] = []
        var memoryAfterInstrumented = memoryBeforeInstrumented

        for promptCase in prompts {
            guard let baselineLogitsArray = baselineLogits[promptCase.id] else {
                throw PilotError.missingBaseline(promptCase.id)
            }
            guard let expectedTokenIDs = baselineTokenIDs[promptCase.id] else {
                throw PilotError.missingBaseline(promptCase.id)
            }
            let (instrumentedChecksum, maxAbsDiff, relativeDiff) =
                try await container.perform(nonSendable: baselineLogitsArray) {
                (context: ModelContext, baselineLogitsArray: MLXArray) async throws -> (String, Float, Float) in
                let input = MLXArray(expectedTokenIDs, [1, expectedTokenIDs.count])
                let logits = context.model(input, cache: nil)
                eval(logits)
                let checksum = InstrumentationIdentityProbe.sha256Base64(logits)
                let difference = abs(baselineLogitsArray - logits)
                let maxDiff = difference.max().item(Float.self)
                let baselineMax = abs(baselineLogitsArray).max().item(Float.self)
                let relative = maxDiff / max(baselineMax, Float.leastNormalMagnitude)
                Memory.clearCache()
                return (checksum, maxDiff, relative)
            }

            // The logits forward above also emitted events; clear the box so
            // rep 0 contains exactly its own generation passes.
            box.clear()

            var instrumentedMs: [Double] = []
            var instrumentedTokens: [Int] = []
            var instrumentedText = ""
            var traces: [MeasuredExecutionTrace] = []
            var passCountsPerRep: [Int] = []

            for rep in 0..<repetitions {
                let repStart = ContinuousClock.now
                let outcome = try await ChatTemplateGeneration.generateWithTokens(
                    container: container,
                    modelDirectory: modelDirectory,
                    prompt: promptCase.text,
                    maxTokens: maxTokens
                )
                instrumentedMs.append(
                    Double(repStart.duration(to: .now).components.attoseconds) / 1e18 * 1000
                )
                instrumentedTokens = outcome.tokenIDs
                instrumentedText = outcome.text
                let events = box.snapshot()
                box.clear()
                passCountsPerRep.append(
                    GroupExecutionTraceProbe.passCount(events: events)
                )
                traces.append(
                    measuredTrace(
                        traceID: "TRACE/\(promptCase.id)/rep\(rep)",
                        modelID: modelID,
                        events: events,
                        inventory: inventory
                    )
                )
            }
            memoryAfterInstrumented = Memory.snapshot()

            let baselineTokens = baselineGeneratedTokenIDs[promptCase.id] ?? []
            let identity = PilotIdentityRecord(
                promptID: promptCase.id,
                prompt: promptCase.text,
                promptTokenCount: promptTokenCounts[promptCase.id] ?? 0,
                baselineTokenIDs: baselineTokens,
                instrumentedTokenIDs: instrumentedTokens,
                tokenSequenceIdentical: baselineTokens == instrumentedTokens,
                baselineText: baselineTexts[promptCase.id] ?? "",
                instrumentedText: instrumentedText,
                baselineLogitsChecksum: baselineChecksums[promptCase.id] ?? "",
                instrumentedLogitsChecksum: instrumentedChecksum,
                logitsBitwiseIdentical:
                    baselineChecksums[promptCase.id] == instrumentedChecksum,
                logitsMaxAbsDiff: maxAbsDiff,
                logitsRelativeDiff: relativeDiff
            )

            let meanInstrumented = instrumentedMs.reduce(0, +) / Double(instrumentedMs.count)
            let baselineMs = baselineSteadyMs[promptCase.id] ?? 0
            let overhead = PilotOverheadRecord(
                baselineSteadyGenerationMilliseconds: baselineMs,
                instrumentedGenerationMilliseconds: instrumentedMs,
                meanInstrumentedGenerationMilliseconds: meanInstrumented,
                overheadRatio: baselineMs == 0 ? nil : meanInstrumented / baselineMs,
                peakMemoryOverheadMegabytes: Double(
                    memoryAfterInstrumented.peakMemory - memoryBeforeInstrumented.peakMemory
                ) / (1024 * 1024),
                timingBoundary:
                    "WARMUP_SYMMETRIC / ONE_TIMED_BASELINE_VS_REP_MEAN / OVERHEAD_DESCRIPTIVE_NO_THRESHOLD"
            )

            let stable = repetitions == traces.count
                && zip(traces, traces.dropFirst()).allSatisfy { a, b in
                    GroupExecutionTraceProbe.tracesStable(a.events, b.events)
                }

            let a1 = identity.tokenSequenceIdentical && identity.logitsBitwiseIdentical
            let a2 = stable
                && traces.allSatisfy { !$0.steps.isEmpty }
                && Set(passCountsPerRep).count == 1

            cases.append(
                PilotCaseReport(
                    promptID: promptCase.id,
                    identity: identity,
                    overhead: overhead,
                    repetitions: repetitions,
                    traceStableAcrossRepetitions: stable,
                    passCounts: passCountsPerRep,
                    traces: traces,
                    g19a1BaselineIdentityPass: a1,
                    g19a2TraceStabilityPass: a2
                )
            )
        }

        let a1All = cases.allSatisfy(\.g19a1BaselineIdentityPass)
        let a2All = cases.allSatisfy(\.g19a2TraceStabilityPass)
        let ratios = cases.compactMap { $0.overhead.overheadRatio }
        var overheadSummary: [String: Double] = [:]
        if !ratios.isEmpty {
            overheadSummary["meanOverheadRatio"] = ratios.reduce(0, +) / Double(ratios.count)
            overheadSummary["maxOverheadRatio"] = ratios.max()
            overheadSummary["minOverheadRatio"] = ratios.min()
        }
        overheadSummary["peakMemoryOverheadMegabytes"] = Double(
            memoryAfterInstrumented.peakMemory - memoryBeforeInstrumented.peakMemory
        ) / (1024 * 1024)

        let modelType = await container.perform {
            (context: ModelContext) -> String in
            String(describing: type(of: context.model))
        }

        return ExecutionTracePilotReport(
            status: a1All && a2All ? "PASS" : "FAIL",
            boundary:
                "ISOLATED_INSTRUMENTATION / LAYER_ENTERED_ONLY / OBSERVER_PASSIVE / NOT_DEMAND / NOT_PREDICTION / EXPERT_DEMAND_NOT_INSTRUMENTED",
            protocolVersion: "G1.9-A.PILOT.V1",
            modelID: modelID,
            modelType: modelType,
            pilotScope: "INSTRUMENTATION_FEASIBILITY_IDENTITY_STABILITY_PILOT",
            instrumentedModuleCount: installed.count,
            observedScope: "DECODER_MLP_DOWN_PROJ / CORE_NOT_DIRECTLY_OBSERVED",
            cases: cases,
            g19a1BaselineIdentityPass: a1All,
            g19a2TraceStabilityPass: a2All,
            g19a3OverheadSummary: overheadSummary,
            g19a4Scope: "PRIMARY"
        )
    }

    public enum PilotError: Error, Equatable {
        case insufficientRepetitions
        case missingBaseline(String)
    }
}
