import Foundation
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXLLM
import SimiGoRuntimeContract
import Tokenizers

/// E5 — end-to-end Execution State scenario on real MLX (v2: representation
/// -consuming execution).
///
/// Scenario: Create → Generate → Fork → Parent/Child Continue → Child Evict
/// (residency floor + representation release) → Re-materialize → Restore →
/// Child Continue (re-executed) → Discard child → Parent Continue.
///
/// Every continuation after the bootstrap generation consumes the CURRENT
/// bound representation through the ExecutionStateBackend contract
/// (`backend.continueExecution(state, nextInputTokens, maxTokens)`) — the
/// runtime NEVER reconstructs an equivalent input from chat messages. This
/// is the E3 prefix-recompute strategy executing for real.
///
/// Three identity checks, all on the REAL runtime:
/// N-I  non-interference: the parent's continuation after the whole child
///      episode is token-identical to the reference computed before the fork.
/// D-I  determinism through the resource cycle: the child's continuation
///      re-executed after evict + re-materialize + restore is token-identical
///      to its pre-eviction execution of the same next input.
/// L-I  consumption identity: the restored representation is CONSUMED by the
///      post-cycle continuation (run2 inputs = restored prefix + same next
///      input), so identical tokens prove the restored representation drove
///      real execution.
///
/// NOT a performance test.
public struct E5StepRecord: Codable, Sendable {
    public let label: String
    public let prefixLength: Int
    public let generatedTokenCount: Int
    public let residencyTransferDelta: Int
    public let residentGroupCount: Int
}

public struct E5ComparisonRecord: Codable, Sendable {
    public let label: String
    public let check: String
    public let pass: Bool
    public let detail: String
}

public struct E5ExecutionStateReport: Codable, Sendable {
    public let status: String
    public let boundary: String
    public let protocolVersion: String
    public let modelID: String
    public let modelType: String
    public let identityAssertions: [E5ComparisonRecord]
    public let steps: [E5StepRecord]
    public let finalLineage: [String: String]
    public let residencyReplayIdentical: Bool
    public let overallPass: Bool
}

public enum E5ExecutionStateScenario {
    public static let protocolVersion = "G1.9-E5.SCENARIO.V2"

    private static let userTextP0 = "Write a Python function that adds two numbers."
    private static let userTextU2 = "Now write the same function in JavaScript."
    private static let userTextUC = "Add type hints to the Python function."

    public static func run(
        modelDirectory: URL,
        maxTokens: Int = 12
    ) async throws -> E5ExecutionStateReport {
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
        _ = Set(inventory.groups.filter(\.alwaysResident).map(\.id))
        let coreBytes = inventory.groups
            .filter(\.alwaysResident)
            .reduce(Int64(0)) { $0 + $1.byteCount }

        let executionStateBackend = MLXExecutionStateBackend()
        let executor = MLXPrefixRecomputeExecutor(container: container, backend: executionStateBackend)
        let coordinator = ExecutionContinuityCoordinator(backend: executionStateBackend)
        let residency = ResidencyController(
            inventory: inventory,
            materializer: MLXResidencyBackend(container: container, inventory: inventory)
        )

        var steps: [E5StepRecord] = []
        var assertions: [E5ComparisonRecord] = []
        var lastResidencyLog = 0

        func recordStep(label: String, prefixLength: Int, generated: Int) {
            FileHandle.standardError.write(Data("E5 step: \(label)\n".utf8))
            let delta = residency.transferLog.count - lastResidencyLog
            lastResidencyLog = residency.transferLog.count
            steps.append(
                E5StepRecord(
                    label: label,
                    prefixLength: prefixLength,
                    generatedTokenCount: generated,
                    residencyTransferDelta: delta,
                    residentGroupCount: residency.residentGroupIDs.count
                )
            )
        }

        func assertCheck(_ label: String, check: String, pass: Bool, detail: String) {
            assertions.append(E5ComparisonRecord(label: label, check: check, pass: pass, detail: detail))
        }

        // 1. CREATE — logical execution state A.
        _ = try await coordinator.create(
            id: ExecutionID("A"),
            position: ExecutionPosition(0),
            continuation: ExecutionContinuation(nextInput: userTextP0, continuationID: "A-cont-0")
        )

        // 2. BOOTSTRAP GENERATION — the only text-seeded generation: raw
        // token encoding of the seed text (uniform continuation strategy:
        // every later continuation appends raw next-input tokens to the
        // bound prefix).
        let bootstrap = try await rawGenerate(
            container: container,
            promptTokens: try await executor.tokenizeSeedText(userTextP0),
            maxTokens: maxTokens
        )
        let prefixAfterTurn1 = bootstrap.promptTokenIDs + bootstrap.tokens
        _ = try await coordinator.continueExecution(
            coordinator.handle(ExecutionID("A"))!,
            continuation: ExecutionContinuation(nextInput: userTextU2, continuationID: "A-cont-1")
        )
        try await coordinator.bindRepresentation(
            executionID: ExecutionID("A"),
            position: ExecutionPosition(1),
            payload: MLXPrefixPayload(tokenPrefix: prefixAfterTurn1)
        )
        recordStep(label: "PARENT_GENERATE_TURN1", prefixLength: prefixAfterTurn1.count, generated: bootstrap.tokens.count)

        FileHandle.standardError.write(Data("E5 step: CAPTURE_REP1\n".utf8))
        // Checkpoint the parent's representation at position 1.
        _ = try await executionStateBackend.captureRepresentation(
            for: coordinator.handle(ExecutionID("A"))!
        )

        // 3. NON-INTERFERENCE REFERENCE (computed BEFORE the fork): the
        // parent's turn-2 continuation, consuming the bound representation.
        let u2Tokens = try await executor.tokenizeText(userTextU2)
        let referenceParentTurn2 = try await executor.continueExecution(
            coordinator.handle(ExecutionID("A"))!,
            nextInputTokens: u2Tokens,
            maxTokens: maxTokens
        )
        _ = try await coordinator.continueExecution(
            coordinator.handle(ExecutionID("A"))!,
            continuation: ExecutionContinuation(nextInput: userTextUC, continuationID: "A-cont-2")
        )
        try await coordinator.bindRepresentation(
            executionID: ExecutionID("A"),
            position: ExecutionPosition(2),
            payload: referenceParentTurn2.updatedPayload
        )
        recordStep(label: "PARENT_REFERENCE_TURN2", prefixLength: referenceParentTurn2.consumedPrefixLength + referenceParentTurn2.nextInputTokenCount + referenceParentTurn2.generatedTokenIDs.count, generated: referenceParentTurn2.generatedTokenIDs.count)

        FileHandle.standardError.write(Data("E5 step: CAPTURE_REP2\n".utf8))
        // Checkpoint the parent's representation at position 2.
        _ = try await executionStateBackend.captureRepresentation(
            for: coordinator.handle(ExecutionID("A"))!
        )

        // 4. FORK — child B derives from the parent's representation at
        // position 2.
        let child = try await coordinator.fork(
            ExecutionForkRequest(
                parent: coordinator.handle(ExecutionID("A"))!,
                childID: ExecutionID("B"),
                childPosition: ExecutionPosition(2),
                childContinuation: ExecutionContinuation(nextInput: userTextUC, continuationID: "B-cont-3")
            )
        )
        recordStep(label: "FORK_CHILD_B", prefixLength: 0, generated: 0)
        FileHandle.standardError.write(Data("E5 step: CAPTURE_REP_PRE\n".utf8))
        let childRepPre = try await executionStateBackend.captureRepresentation(
            for: child
        ) // fork-point checkpoint: the representation run-1 will consume
        // Register the checkpoint in the coordinator history so the later
        // logical RESTORE can find a physical representation at position 2.
        try await coordinator.bindRepresentation(
            executionID: ExecutionID("B"),
            position: ExecutionPosition(2),
            payload: childRepPre.payload
        )

        // 5. CHILD CONTINUE (run 1) — consumes the child's bound
        // representation (derived prefix) with the child's next input.
        let ucTokens = try await executor.tokenizeText(userTextUC)
        let childRun1 = try await executor.continueExecution(
            child,
            nextInputTokens: ucTokens,
            maxTokens: maxTokens
        )
        _ = try await coordinator.continueExecution(
            child,
            continuation: ExecutionContinuation(nextInput: userTextUC, continuationID: "B-cont-4")
        )
        try await coordinator.bindRepresentation(
            executionID: ExecutionID("B"),
            position: ExecutionPosition(3),
            payload: childRun1.updatedPayload
        )
        FileHandle.standardError.write(Data("E5 step: CAPTURE_REP3\n".utf8))
        let childRep3 = try await executionStateBackend.captureRepresentation(
            for: coordinator.handle(ExecutionID("B"))!
        )
        recordStep(label: "CHILD_CONTINUE_RUN1", prefixLength: childRun1.consumedPrefixLength + childRun1.nextInputTokenCount + childRun1.generatedTokenIDs.count, generated: childRun1.generatedTokenIDs.count)

        // 6. CHILD EVICT — residency floor (real group evictions) + release
        // of the child's CURRENT representation binding. The fork-point
        // checkpoint (childRepPre) survives the eviction.
        _ = try await residency.respondToMemoryPressure(targetBytes: coreBytes)
        try await executionStateBackend.releaseRepresentation(childRep3)
        recordStep(label: "CHILD_EVICT", prefixLength: 0, generated: 0)

        // 7. CHILD RE-MATERIALIZE — real group loads restore the physical
        // groups; the LOGICAL restore happens next (scenario order:
        // evict -> re-materialize -> restore -> continue).
        _ = try await residency.admit(
            requiredGroupIDs: allGroups,
            budget: ResidencyBudgetPolicy(fixedBytes: inventory.totalByteCount)
        )
        recordStep(label: "CHILD_REMATERIALIZE", prefixLength: 0, generated: 0)

        // 7b. LOGICAL RESTORE to position 2: the coordinator finds the
        // captured fork-point representation in its history and the backend
        // re-binds it.
        _ = try await coordinator.restore(
            child,
            request: ExecutionRestoreRequest(
                targetPosition: ExecutionPosition(2),
                continuation: ExecutionContinuation(nextInput: userTextUC, continuationID: "B-cont-3")
            )
        )

        // 8. CHILD CONTINUE (run 2) — consumes the RESTORED representation
        // with the SAME next input: token-identical to run 1 (D-I). The
        // consumption itself proves the restored representation drove real
        // execution.
        let childRun2 = try await executor.continueExecution(
            coordinator.handle(ExecutionID("B"))!,
            nextInputTokens: ucTokens,
            maxTokens: maxTokens
        )
        recordStep(label: "CHILD_CONTINUE_RUN2_AFTER_RESTORE", prefixLength: childRun2.consumedPrefixLength + childRun2.nextInputTokenCount, generated: childRun2.generatedTokenIDs.count)

        // 9. DISCARD the child — terminal; the parent is untouched.
        try await coordinator.discard(coordinator.handle(ExecutionID("B"))!)
        recordStep(label: "DISCARD_CHILD", prefixLength: 0, generated: 0)

        // 10. PARENT CONTINUE (turn 2, re-executed after the whole child
        // episode) — restores the parent's PRE-turn-2 checkpoint
        // representation (position 1) and consumes it; tokens MUST equal the
        // pre-fork reference (N-I).
        _ = try await coordinator.restore(
            coordinator.handle(ExecutionID("A"))!,
            request: ExecutionRestoreRequest(
                targetPosition: ExecutionPosition(1),
                continuation: ExecutionContinuation(nextInput: userTextU2, continuationID: "A-cont-1")
            )
        )
        let parentTurn2 = try await executor.continueExecution(
            coordinator.handle(ExecutionID("A"))!,
            nextInputTokens: u2Tokens,
            maxTokens: maxTokens
        )
        _ = try await coordinator.continueExecution(
            coordinator.handle(ExecutionID("A"))!,
            continuation: ExecutionContinuation(nextInput: userTextU2, continuationID: "A-cont-4")
        )
        try await coordinator.bindRepresentation(
            executionID: ExecutionID("A"),
            position: ExecutionPosition(3),
            payload: parentTurn2.updatedPayload
        )
        recordStep(label: "PARENT_CONTINUE_TURN2", prefixLength: parentTurn2.consumedPrefixLength + parentTurn2.nextInputTokenCount + parentTurn2.generatedTokenIDs.count, generated: parentTurn2.generatedTokenIDs.count)

        // Identity checks.
        let diverged = childRun1.generatedTokenIDs != referenceParentTurn2.generatedTokenIDs
        assertCheck(
            "FORK_DIVERGENCE", check: "child(UC) tokens != parent(U2) tokens",
            pass: diverged,
            detail: "child \(childRun1.generatedTokenIDs.count) tokens vs parent reference \(referenceParentTurn2.generatedTokenIDs.count) tokens"
        )
        let determinismPass = childRun2.generatedTokenIDs == childRun1.generatedTokenIDs
            && childRun2.generatedText == childRun1.generatedText
        assertCheck(
            "CHILD_DETERMINISM_THROUGH_RESOURCE_CYCLE",
            check: "child continuation re-executed after evict/remat/restore is token-identical",
            pass: determinismPass,
            detail: "run1 \(childRun1.generatedTokenIDs.count) tokens, run2 \(childRun2.generatedTokenIDs.count) tokens"
        )
        let nonInterferencePass = parentTurn2.generatedTokenIDs == referenceParentTurn2.generatedTokenIDs
        assertCheck(
            "PARENT_NON_INTERFERENCE",
            check: "parent turn-2 after the child episode == pre-fork reference",
            pass: nonInterferencePass,
            detail: "reference \(referenceParentTurn2.generatedTokenIDs.count) tokens vs actual \(parentTurn2.generatedTokenIDs.count) tokens"
        )

        let parentFinal = coordinator.handle(ExecutionID("A"))!
        let childFinal = coordinator.handle(ExecutionID("B"))!
        let parentStable =
            parentFinal.id == ExecutionID("A")
                && parentFinal.lineage.root == ExecutionID("A")
                && parentFinal.lineage.parent == nil
        let childTerminal =
            childFinal.lifecycle == .discarded
                && childFinal.lineage.parent == ExecutionID("A")
                && childFinal.lineage.root == ExecutionID("A")
        assertCheck(
            "PARENT_IDENTITY_STABLE", check: "parent id/lineage unchanged through the scenario",
            pass: parentStable, detail: "A@position \(parentFinal.position.value)"
        )
        assertCheck(
            "CHILD_LINEAGE_TRACEABLE", check: "discarded child lineage still traces to parent",
            pass: childTerminal, detail: "B discarded, lineage.parent = A"
        )

        // INV-1 as an explicit assertion (not a debug assert).
        let residencyReplayIdentical =
            residency.auditReplay().residentGroupIDs == residency.residentGroupIDs
        assertCheck(
            "RESIDENCY_INV1", check: "transfer-log replay == resident bookkeeping",
            pass: residencyReplayIdentical,
            detail: "log count \(residency.transferLog.count)"
        )

        let overallPass =
            diverged && determinismPass && nonInterferencePass
                && parentStable && childTerminal && residencyReplayIdentical

        return E5ExecutionStateReport(
            status: overallPass ? "PASS" : "FAIL",
            boundary:
                "REAL_RUNTIME_EXECUTION_STATE_SCENARIO / REPRESENTATION_CONSUMING_EXECUTION / COMPUTATIONAL_SEMANTICS_PRESERVATION / RESOURCE_STATE_CORRECTNESS / NOT_A_PERFORMANCE_TEST / NOT_PREDICTION",
            protocolVersion: protocolVersion,
            modelID: modelDirectory.path,
            modelType: modelType,
            identityAssertions: assertions,
            steps: steps,
            finalLineage: [
                "A": "root=A parent=nil lifecycle=\(parentFinal.lifecycle.rawValue) position=\(parentFinal.position.value)",
                "B": "root=A parent=A lifecycle=\(childFinal.lifecycle.rawValue) position=\(childFinal.position.value)",
            ],
            residencyReplayIdentical: residencyReplayIdentical,
            overallPass: overallPass
        )
    }

    // MARK: - Raw continuation helpers

    static func rawGenerate(
        container: ModelContainer,
        promptTokens: [Int],
        maxTokens: Int
    ) async throws -> (promptTokenIDs: [Int], tokens: [Int], text: String) {
        await container.perform { (context: ModelContext) -> (promptTokenIDs: [Int], tokens: [Int], text: String) in
            var generated: [Int] = []
            var input = MLXArray(promptTokens, [1, promptTokens.count])
            for _ in 0..<maxTokens {
                let logits = context.model(input, cache: nil)[0, -1]
                let nextToken = logits.argMax().item(Int.self)
                generated.append(nextToken)
                if nextToken == context.tokenizer.eosTokenId ?? -1 {
                    break
                }
                input = MLXArray(promptTokens + generated, [1, promptTokens.count + generated.count])
                eval(logits)
            }
            let text = context.tokenizer.decode(tokenIds: generated, skipSpecialTokens: true)
            Memory.clearCache()
            return (promptTokens, generated, text)
        }
    }

    // MARK: - Bootstrap helpers (text-seeded first generation only)

    private static func generateFromMessages(
        container: ModelContainer,
        modelDirectory: URL,
        messages: [[String: String]],
        maxTokens: Int
    ) async throws -> (promptTokenIDs: [Int], tokens: [Int], text: String) {
        let sendableMessages: [[String: any Sendable]] = messages.map { dict in
            ["role": dict["role"] ?? "", "content": dict["content"] ?? ""]
        }
        return try await container.perform { (context: ModelContext) -> (promptTokenIDs: [Int], tokens: [Int], text: String) in
            let external = modelDirectory.appendingPathComponent("chat_template.jinja")
            var promptTokens: [Int]
            if FileManager.default.fileExists(atPath: external.path) {
                let template = try String(contentsOf: external, encoding: .utf8)
                let checkpointTokenizer = try await Tokenizers.AutoTokenizer.from(
                    modelFolder: modelDirectory
                )
                promptTokens = try checkpointTokenizer.applyChatTemplate(
                    messages: sendableMessages,
                    chatTemplate: .literal(template),
                    addGenerationPrompt: true,
                    truncation: false,
                    maxLength: nil,
                    tools: nil,
                    additionalContext: ["enable_thinking": false]
                )
            } else if let configured = context.tokenizer as? Tokenizers.PreTrainedTokenizer,
                configured.hasChatTemplate
            {
                promptTokens = try configured.applyChatTemplate(
                    messages: sendableMessages,
                    tools: nil,
                    additionalContext: ["enable_thinking": false]
                )
            } else {
                promptTokens = try context.tokenizer.applyChatTemplate(messages: sendableMessages)
            }

            var generated: [Int] = []
            var input = MLXArray(promptTokens, [1, promptTokens.count])
            for _ in 0..<maxTokens {
                let logits = context.model(input, cache: nil)[0, -1]
                let nextToken = logits.argMax().item(Int.self)
                generated.append(nextToken)
                if nextToken == context.tokenizer.eosTokenId ?? -1 {
                    break
                }
                input = MLXArray(promptTokens + generated, [1, promptTokens.count + generated.count])
                eval(logits)
            }
            let text = context.tokenizer.decode(tokenIds: generated, skipSpecialTokens: true)
            Memory.clearCache()
            return (promptTokens, generated, text)
        }
    }
}
