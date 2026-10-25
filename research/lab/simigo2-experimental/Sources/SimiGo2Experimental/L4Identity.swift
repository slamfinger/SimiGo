import Foundation
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXLLM
import SimiGoRuntimeContract
import Tokenizers

/// L4-C: computational identity through the full controller path.
///
/// Baseline MLX generation vs Controller + Materializer + MLX generation on
/// the same prompts: token sequences, logits checksums, and max absolute
/// differences must match, while the residency side records the transfer
/// log, bookkeeping, retention rotation, and a DIRTY/recovery cycle.
/// NOT a performance test: no latency, throughput, or improvement claims.
public struct L4IdentityCase: Codable, Sendable {
    public let promptID: String
    public let prompt: String
    public let promptTokenCount: Int
    public let baselineTokenIDs: [Int]
    public let controllerTokenIDs: [Int]
    public let baselineText: String
    public let controllerText: String
    public let tokenSequenceIdentical: Bool
    public let baselineLogitsChecksum: String
    public let controllerLogitsChecksum: String
    public let logitsChecksumIdentical: Bool
    public let logitsMaxAbsDiff: Float
    public let logitsRelativeDiff: Float
    public let retentionGroupIDs: [String]
    public let transferLogCount: Int
    public let residentBytesAfterRetention: Int64
    public let dirtyCycleEncountered: Bool
    public let identityPass: Bool
}

public struct L4IdentityReport: Codable, Sendable {
    public let status: String
    public let boundary: String
    public let protocolVersion: String
    public let modelID: String
    public let modelType: String
    public let cases: [L4IdentityCase]
    public let overallPass: Bool
    public let finalTransferLogCount: Int
    public let finalResidentGroupIDs: [String]
    public let dirtyCycleExecuted: Bool
    public let dirtyCycleRecoveryPass: Bool
}

public enum L4IdentityProbe {
    public static let protocolVersion = "G1.9-L4C.IDENTITY.V1"

    public static let prompts: [(id: String, text: String)] = [
        (id: "P1", text: "Return exactly one word: ping"),
        (id: "P2", text: "Count from one to twelve."),
        (id: "P3", text: "Name five colors."),
    ]

    /// Retention rotation after each prompt's generation: A → AB → ALL
    /// over the sorted optional groups.
    public static func retentionSet(forPromptIndex index: Int, optionalIDs: [String]) -> Set<String> {
        switch index % 3 {
        case 0: return Set(optionalIDs.prefix(1))
        case 1: return Set(optionalIDs.prefix(2))
        default: return Set(optionalIDs)
        }
    }

    public static func run(
        modelDirectory: URL,
        maxTokens: Int = 24
    ) async throws -> L4IdentityReport {
        let inventory = try SafetensorsInventoryReader.readModelGroups(
            modelDirectory: modelDirectory
        )
        let container = try await LLMModelFactory.shared.loadContainer(
            from: modelDirectory,
            using: #huggingFaceTokenizerLoader()
        )
        let modelType = await container.perform { (context: ModelContext) -> String in
            String(describing: type(of: context.model))
        }
        let allGroups = Set(inventory.groups.map(\.id))
        let coreIDs = Set(inventory.groups.filter(\.alwaysResident).map(\.id))
        let optionalIDs = inventory.groups
            .filter { !$0.alwaysResident }
            .sorted { $0.layerRangeDescription < $1.layerRangeDescription }
            .map(\.id)

        // Baseline phase: per prompt — one perform block computing the full
        // forward (logits retained + checksummed), then a separate
        // generation. No controller involvement.
        var baselineLogits: [String: MLXArray] = [:]
        var baselineChecksums: [String: String] = [:]
        var baselineTokens: [String: [Int]] = [:]
        var baselineTexts: [String: String] = [:]
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
                let logits = context.model(input, cache: nil)
                eval(logits)
                let checksum = InstrumentationIdentityProbe.sha256Base64(logits)
                Memory.clearCache()
                return (tokenIDs, checksum)
            }
            baselineChecksums[promptCase.id] = checksum
            promptTokenCounts[promptCase.id] = tokenIDs.count

            let baselineBox = try await container.perform {
                (context: ModelContext) async throws -> UnsafeSendableBox<MLXArray> in
                let tokenIDs = try await ChatTemplateGeneration.promptTokenIDs(
                    tokenizer: context.tokenizer,
                    modelDirectory: modelDirectory,
                    prompt: promptCase.text
                )
                let input = MLXArray(tokenIDs, [1, tokenIDs.count])
                let logits = context.model(input, cache: nil)
                eval(logits)
                return UnsafeSendableBox(value: logits)
            }
            baselineLogits[promptCase.id] = baselineBox.value

            let outcome = try await ChatTemplateGeneration.generateWithTokens(
                container: container,
                modelDirectory: modelDirectory,
                prompt: promptCase.text,
                maxTokens: maxTokens
            )
            baselineTokens[promptCase.id] = outcome.tokenIDs
            baselineTexts[promptCase.id] = outcome.text
        }

        // Controller phase: residency transitions drive real loads/evicts
        // between generations; a DIRTY/recovery cycle runs mid-sequence.
        let backend = MLXResidencyBackend(container: container, inventory: inventory)
        let faulted = FaultInjectingResidencyMaterializer(base: backend)
        let controller = ResidencyController(
            inventory: inventory,
            materializer: faulted,
            initialResidentGroupIDs: allGroups
        )

        var cases: [L4IdentityCase] = []
        var dirtyCycleExecuted = false
        var dirtyCycleRecoveryPass = true

        for (index, promptCase) in prompts.enumerated() {
            // Load everything missing for this generation window.
            _ = try await controller.admit(
                requiredGroupIDs: allGroups,
                budget: ResidencyBudgetPolicy(fixedBytes: inventory.totalByteCount)
            )

            // Controller-path forward: logits identity vs the baseline array.
            guard let baselineArray = baselineLogits[promptCase.id] else {
                throw L4IdentityError.missingBaseline(promptCase.id)
            }
            let (controllerChecksum, maxDiff, relativeDiff) =
                try await container.perform(nonSendable: baselineArray) {
                    (context: ModelContext, baselineArray: MLXArray) async throws -> (String, Float, Float) in
                    let tokenIDs = try await ChatTemplateGeneration.promptTokenIDs(
                        tokenizer: context.tokenizer,
                        modelDirectory: modelDirectory,
                        prompt: promptCase.text
                    )
                    let input = MLXArray(tokenIDs, [1, tokenIDs.count])
                    let logits = context.model(input, cache: nil)
                    eval(logits)
                    let checksum = InstrumentationIdentityProbe.sha256Base64(logits)
                    let difference = abs(baselineArray - logits)
                    let maxDiff = difference.max().item(Float.self)
                    let baselineMax = abs(baselineArray).max().item(Float.self)
                    let relative = maxDiff / max(baselineMax, Float.leastNormalMagnitude)
                    Memory.clearCache()
                    return (checksum, maxDiff, relative)
                }

            // Controller-path generation over the managed resident state.
            let controllerOutcome = try await ChatTemplateGeneration.generateWithTokens(
                container: container,
                modelDirectory: modelDirectory,
                prompt: promptCase.text,
                maxTokens: maxTokens
            )

            let logAfterGeneration = controller.transferLog.count

            // Retention rotation AFTER the generation: real evictions.
            let retentionSet = retentionSet(forPromptIndex: index, optionalIDs: optionalIDs)
            let retentionRequired = coreIDs.union(retentionSet)
            let retentionBytes = retentionRequired.reduce(Int64(0)) { partial, id in
                partial + (inventory.groups.first(where: { $0.id == id })?.byteCount ?? 0)
            }
            _ = try await controller.admit(
                requiredGroupIDs: retentionRequired,
                budget: ResidencyBudgetPolicy(fixedBytes: retentionBytes)
            )

            // DIRTY/recovery cycle before the final prompt: an injected
            // release failure on a group that the recovery-gating admission
            // will actually try to evict (resident − core).
            var dirtyHere = false
            if index == prompts.count - 2 {
                let dirtyEvictSet = controller.residentGroupIDs.subtracting(coreIDs)
                if let victim = dirtyEvictSet.sorted().first {
                    faulted.failReleasesOf = [victim]
                    do {
                        _ = try await controller.admit(
                            requiredGroupIDs: coreIDs,
                            budget: ResidencyBudgetPolicy(fixedBytes: inventory.totalByteCount)
                        )
                        throw L4IdentityError.expectedReleaseFailure
                    } catch let error as ResidencyControllerError {
                        guard case .evictFailed(groupID: victim) = error else {
                            throw L4IdentityError.expectedReleaseFailure
                        }
                    }
                    dirtyHere = controller.state == .dirty
                    try controller.recover()
                    faulted.failReleasesOf = []
                    dirtyCycleExecuted = dirtyCycleExecuted || dirtyHere
                    dirtyCycleRecoveryPass = dirtyCycleRecoveryPass && controller.state == .clean
                }
            }

            let baselineCaseTokens = baselineTokens[promptCase.id] ?? []
            let tokensIdentical = baselineCaseTokens == controllerOutcome.tokenIDs
            let checksumIdentical = (baselineChecksums[promptCase.id] ?? "") == controllerChecksum

            cases.append(
                L4IdentityCase(
                    promptID: promptCase.id,
                    prompt: promptCase.text,
                    promptTokenCount: promptTokenCounts[promptCase.id] ?? 0,
                    baselineTokenIDs: baselineCaseTokens,
                    controllerTokenIDs: controllerOutcome.tokenIDs,
                    baselineText: baselineTexts[promptCase.id] ?? "",
                    controllerText: controllerOutcome.text,
                    tokenSequenceIdentical: tokensIdentical,
                    baselineLogitsChecksum: baselineChecksums[promptCase.id] ?? "",
                    controllerLogitsChecksum: controllerChecksum,
                    logitsChecksumIdentical: checksumIdentical,
                    logitsMaxAbsDiff: maxDiff,
                    logitsRelativeDiff: relativeDiff,
                    retentionGroupIDs: retentionSet.sorted(),
                    transferLogCount: logAfterGeneration,
                    residentBytesAfterRetention: controller.residentBytes,
                    dirtyCycleEncountered: dirtyHere,
                    identityPass: tokensIdentical && checksumIdentical
                )
            )
        }

        let overallPass = cases.allSatisfy(\.identityPass) && dirtyCycleRecoveryPass && dirtyCycleExecuted

        return L4IdentityReport(
            status: overallPass ? "PASS" : "FAIL",
            boundary:
                "COMPUTATIONAL_SEMANTICS_PRESERVATION / RESOURCE_STATE_CORRECTNESS / NOT_A_PERFORMANCE_TEST / NOT_PREDICTION",
            protocolVersion: protocolVersion,
            modelID: modelDirectory.path,
            modelType: modelType,
            cases: cases,
            overallPass: overallPass,
            finalTransferLogCount: controller.transferLog.count,
            finalResidentGroupIDs: controller.residentGroupIDs.sorted(),
            dirtyCycleExecuted: dirtyCycleExecuted,
            dirtyCycleRecoveryPass: dirtyCycleRecoveryPass
        )
    }

    public enum L4IdentityError: Error, Equatable {
        case missingBaseline(String)
        case expectedReleaseFailure
    }
}
