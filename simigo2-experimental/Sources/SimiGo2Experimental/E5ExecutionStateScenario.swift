import Foundation
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXLLM
import SimiGoRuntimeContract
import Tokenizers

/// E5 — end-to-end Execution State scenario on real MLX.
///
/// Scenario: Create → Generate → Fork → Parent/Child Continue → Child Evict
/// (residency floor + representation release) → Re-materialize → Restore →
/// Child Continue (again) → Discard child → Parent Continue.
///
/// Three identity checks, all on the REAL runtime:
/// N-I  non-interference: the parent's continuation after the whole child
///      episode equals a reference computed BEFORE the fork (token-identical).
/// D-I  determinism through the resource cycle: the child's continuation
///      re-executed after evict + re-materialize + restore is token-identical
///      to its pre-eviction execution of the same input.
/// L-I  logits re-forward identity: logits over the restored prefix checksum
///      identical before and after the eviction cycle.
///
/// NOT a performance test: no latency, throughput, or improvement claims.
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
    public let overallPass: Bool
}

public enum E5ExecutionStateScenario {
    public static let protocolVersion = "G1.9-E5.SCENARIO.V1"

    private static let userTextP0 = "Name the primary color of the sky on a clear day."
    private static let userTextU2 = "Now summarize your answer in one short sentence."
    private static let userTextUC = "Answer with a single word: is the sky blue? yes or no?"

    public static func run(
        modelDirectory: URL,
        cModelBytes: Int64 = 0,
        epsilonBytes: Int64 = 5 * 1024 * 1024,
        maxTokens: Int = 12
    ) async throws -> E5ExecutionStateReport {
        let inventory = try SafetensorsInventoryReader.readModelGroups(
            modelDirectory: modelDirectory
        )
        let container = try await LLMModelFactory.shared.loadContainer(
            from: modelDirectory,
            using: #huggingFaceTokenizerLoader()
        )
        let modelType = try await container.perform { (context: ModelContext) -> String in
            String(describing: type(of: context.model))
        }
        let allGroups = Set(inventory.groups.map(\.id))
        let coreIDs = Set(inventory.groups.filter(\.alwaysResident).map(\.id))

        let backend = MLXExecutionStateBackend()
        let coordinator = ExecutionContinuityCoordinator(backend: backend)
        let residencyBackend = MLXResidencyBackend(container: container, inventory: inventory)
        let residency = ResidencyController(
            inventory: inventory,
            materializer: residencyBackend
        )

        var steps: [E5StepRecord] = []
        var assertions: [E5ComparisonRecord] = []
        var lastResidencyLog = 0
        var lastPrefixLength = 0

        func recordStep(label: String, prefixLength: Int, generated: Int) {
            let delta = residency.transferLog.count - lastResidencyLog
            lastResidencyLog = residency.transferLog.count
            lastPrefixLength = prefixLength
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

        // 2. GENERATE (parent turn 1): real MLX generation; physical prefix
        // bound at position 0.
        let promptA0 = try await promptTokenIDsForMessages(
            container: container,
            modelDirectory: modelDirectory,
            messages: [["role": "user", "content": userTextP0]]
        )
        let turn1 = try await generateFromMessages(
            container: container,
            modelDirectory: modelDirectory,
            messages: [["role": "user", "content": userTextP0]],
            maxTokens: maxTokens
        )
        let prefixA1 = promptA0 + turn1.tokens
        try await coordinator.continueExecution(
            coordinator.handle(ExecutionID("A"))!,
            continuation: ExecutionContinuation(nextInput: userTextU2, continuationID: "A-cont-1")
        )
        try await coordinator.bindRepresentation(
            executionID: ExecutionID("A"),
            position: ExecutionPosition(1),
            payload: MLXPrefixPayload(tokenPrefix: prefixA1)
        )
        recordStep(label: "PARENT_GENERATE_TURN1", prefixLength: prefixA1.count, generated: turn1.tokens.count)

        // 3. NON-INTERFERENCE REFERENCE (computed BEFORE the fork): the
        // parent's turn-2 continuation.
        let referenceParentTurn2 = try await generateFromMessages(
            container: container,
            modelDirectory: modelDirectory,
            messages: [
                ["role": "user", "content": userTextP0],
                ["role": "assistant", "content": turn1.text],
                ["role": "user", "content": userTextU2],
            ],
            maxTokens: maxTokens
        )

        // 4. FORK — child B derives from the parent at position 1.
        let child = try await coordinator.fork(
            ExecutionForkRequest(
                parent: coordinator.handle(ExecutionID("A"))!,
                childID: ExecutionID("B"),
                childPosition: ExecutionPosition(1),
                childContinuation: ExecutionContinuation(nextInput: userTextUC, continuationID: "B-cont-2")
            )
        )
        let childPrefix = try await prefixForRepresentation(of: ExecutionID("B"), boundPosition: ExecutionPosition(1), backend: backend)
        recordStep(label: "FORK_CHILD_B", prefixLength: childPrefix.count, generated: 0)

        // 5. CHILD CONTINUE (run 1): real generation from the child's prefix
        // context.
        let childRun1 = try await generateFromMessages(
            container: container,
            modelDirectory: modelDirectory,
            messages: [
                ["role": "user", "content": userTextP0],
                ["role": "assistant", "content": turn1.text],
                ["role": "user", "content": userTextUC],
            ],
            maxTokens: maxTokens
        )
        let prefixB2 = childPrefix + childRun1.tokens
        try await coordinator.continueExecution(
            child,
            continuation: ExecutionContinuation(nextInput: userTextUC, continuationID: "B-cont-3")
        )
        try await coordinator.bindRepresentation(
            executionID: ExecutionID("B"),
            position: ExecutionPosition(2),
            payload: MLXPrefixPayload(tokenPrefix: prefixB2)
        )
        // Logits over the child's bound prefix (pre-eviction reference).
        let childLogitsChecksumPre = try await logitsChecksum(
            container: container, tokens: prefixB2
        )
        recordStep(label: "CHILD_CONTINUE_RUN1", prefixLength: prefixB2.count, generated: childRun1.tokens.count)

        // Divergence: the child's continuation with UC differs from the
        // parent's reference continuation with U2 (different next inputs).
        let diverged = childRun1.tokens != referenceParentTurn2.tokens
        assertCheck(
            "FORK_DIVERGENCE", check: "child(UC) tokens != parent(U2) tokens",
            pass: diverged,
            detail: "child \(childRun1.tokens.count) tokens vs parent reference \(referenceParentTurn2.tokens.count) tokens"
        )

        // 6. CHILD EVICT — residency shrinks to the core floor (real group
        // evictions) and the child's representation binding is released.
        _ = try await residency.respondToMemoryPressure(targetBytes: 0)
        try await backend.releaseRepresentation(
            ExecutionRepresentation(
                executionID: ExecutionID("B"),
                position: ExecutionPosition(2),
                payload: MLXPrefixPayload(tokenPrefix: prefixB2)
            )
        )
        recordStep(label: "CHILD_EVICT", prefixLength: 0, generated: 0)

        // 7. CHILD RE-MATERIALIZE — real group loads restore residency.
        _ = try await residency.admit(
            requiredGroupIDs: allGroups,
            budget: ResidencyBudgetPolicy(fixedBytes: inventory.totalByteCount)
        )
        // The representation is restored from the pre-eviction binding.
        try await backend.restoreRepresentation(
            ExecutionRepresentation(
                executionID: ExecutionID("B"),
                position: ExecutionPosition(2),
                payload: MLXPrefixPayload(tokenPrefix: prefixB2)
            )
        )
        recordStep(label: "CHILD_REMATERIALIZE", prefixLength: prefixB2.count, generated: 0)

        // L-I — logits re-forward identity after the eviction cycle.
        let childLogitsChecksumPost = try await logitsChecksum(
            container: container, tokens: prefixB2
        )
        let logitsIdentical = childLogitsChecksumPre == childLogitsChecksumPost
        assertCheck(
            "LOGITS_REFORWARD_IDENTITY", check: "prefix logits checksum identical after evict/remat",
            pass: logitsIdentical,
            detail: "checksum \(childLogitsChecksumPre) -> \(childLogitsChecksumPost)"
        )

        // 8. CHILD RESTORE + CONTINUE (run 2): same next input, re-executed
        // after the resource cycle — token-identical to run 1 (D-I).
        let restored = try await coordinator.restore(
            coordinator.handle(ExecutionID("B"))!,
            request: ExecutionRestoreRequest(
                targetPosition: ExecutionPosition(2),
                continuation: ExecutionContinuation(nextInput: userTextUC, continuationID: "B-cont-3")
            )
        )
        _ = try await coordinator.reattach(restored)
        let childRun2 = try await generateFromMessages(
            container: container,
            modelDirectory: modelDirectory,
            messages: [
                ["role": "user", "content": userTextP0],
                ["role": "assistant", "content": turn1.text],
                ["role": "user", "content": userTextUC],
            ],
            maxTokens: maxTokens
        )
        let determinismPass = childRun2.tokens == childRun1.tokens
        assertCheck(
            "CHILD_DETERMINISM_THROUGH_RESOURCE_CYCLE", check: "run2 tokens == run1 tokens",
            pass: determinismPass,
            detail: "run1 \(childRun1.tokens.count) tokens, run2 \(childRun2.tokens.count) tokens"
        )
        recordStep(label: "CHILD_CONTINUE_RUN2_AFTER_RESTORE", prefixLength: prefixB2.count, generated: childRun2.tokens.count)

        // 9. DISCARD the child — terminal; the parent is untouched.
        try await coordinator.discard(coordinator.handle(ExecutionID("B"))!)
        recordStep(label: "DISCARD_CHILD", prefixLength: 0, generated: 0)

        // 10. PARENT CONTINUE (turn 2, after the whole child episode) —
        // non-interference: tokens equal the pre-fork reference (N-I).
        let parentTurn2 = try await generateFromMessages(
            container: container,
            modelDirectory: modelDirectory,
            messages: [
                ["role": "user", "content": userTextP0],
                ["role": "assistant", "content": turn1.text],
                ["role": "user", "content": userTextU2],
            ],
            maxTokens: maxTokens
        )
        let nonInterferencePass = parentTurn2.tokens == referenceParentTurn2.tokens
        assertCheck(
            "PARENT_NON_INTERFERENCE", check: "parent turn2 tokens == pre-fork reference",
            pass: nonInterferencePass,
            detail: "reference \(referenceParentTurn2.tokens.count) tokens vs actual \(parentTurn2.tokens.count) tokens"
        )
        try await coordinator.continueExecution(
            coordinator.handle(ExecutionID("A"))!,
            continuation: ExecutionContinuation(nextInput: userTextU2, continuationID: "A-cont-2")
        )
        try await coordinator.bindRepresentation(
            executionID: ExecutionID("A"),
            position: ExecutionPosition(2),
            payload: MLXPrefixPayload(tokenPrefix: prefixA1 + parentTurn2.tokens)
        )
        recordStep(label: "PARENT_CONTINUE_TURN2", prefixLength: (prefixA1 + parentTurn2.tokens).count, generated: parentTurn2.tokens.count)

        // Identity/lineage assertions (logical side).
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

        // Residency INV-1 sanity after the whole scenario.
        assertResidencyReplay(residency)

        let overallPass =
            diverged && logitsIdentical && determinismPass && nonInterferencePass
                && parentStable && childTerminal

        return E5ExecutionStateReport(
            status: overallPass ? "PASS" : "FAIL",
            boundary:
                "REAL_RUNTIME_EXECUTION_STATE_SCENARIO / COMPUTATIONAL_SEMANTICS_PRESERVATION / RESOURCE_STATE_CORRECTNESS / NOT_A_PERFORMANCE_TEST / NOT_PREDICTION",
            protocolVersion: protocolVersion,
            modelID: modelDirectory.path,
            modelType: modelType,
            identityAssertions: assertions,
            steps: steps,
            finalLineage: [
                "A": "root=A parent=nil lifecycle=\(parentFinal.lifecycle.rawValue) position=\(parentFinal.position.value)",
                "B": "root=A parent=A lifecycle=\(childFinal.lifecycle.rawValue) position=\(childFinal.position.value)",
            ],
            overallPass: overallPass
        )
    }

    // MARK: - Helpers

    private static func assertResidencyReplay(_ residency: ResidencyController) {
        assert(residency.auditReplay().residentGroupIDs == residency.residentGroupIDs)
    }

    private static func promptTokenIDsForMessages(
        container: ModelContainer,
        modelDirectory: URL,
        messages: [[String: String]]
    ) async throws -> [Int] {
        let sendableMessages: [[String: any Sendable]] = messages.map { dict in
            ["role": dict["role"] ?? "", "content": dict["content"] ?? ""]
        }
        return try await container.perform { (context: ModelContext) -> [Int] in
            let external = modelDirectory.appendingPathComponent("chat_template.jinja")
            if FileManager.default.fileExists(atPath: external.path) {
                let template = try String(contentsOf: external, encoding: .utf8)
                let checkpointTokenizer = try await Tokenizers.AutoTokenizer.from(
                    modelFolder: modelDirectory
                )
                return try checkpointTokenizer.applyChatTemplate(
                    messages: sendableMessages,
                    chatTemplate: .literal(template),
                    addGenerationPrompt: true,
                    truncation: false,
                    maxLength: nil,
                    tools: nil,
                    additionalContext: ["enable_thinking": false]
                )
            }
            if let configured = context.tokenizer as? Tokenizers.PreTrainedTokenizer,
                configured.hasChatTemplate
            {
                return try configured.applyChatTemplate(
                    messages: sendableMessages,
                    tools: nil,
                    additionalContext: ["enable_thinking": false]
                )
            }
            return try context.tokenizer.applyChatTemplate(messages: sendableMessages)
        }
    }

    private static func generateFromMessages(
        container: ModelContainer,
        modelDirectory: URL,
        messages: [[String: String]],
        maxTokens: Int
    ) async throws -> (tokens: [Int], text: String) {
        let promptTokens = try await promptTokenIDsForMessages(
            container: container,
            modelDirectory: modelDirectory,
            messages: messages
        )
        return try await container.perform { (context: ModelContext) -> (tokens: [Int], text: String) in
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
            return (generated, text)
        }
    }

    private static func logitsChecksum(
        container: ModelContainer,
        tokens: [Int]
    ) async throws -> String {
        try await container.perform { (context: ModelContext) -> String in
            let input = MLXArray(tokens, [1, tokens.count])
            let logits = context.model(input, cache: nil)
            eval(logits)
            let checksum = InstrumentationIdentityProbe.sha256Base64(logits)
            Memory.clearCache()
            return checksum
        }
    }

    private static func prefixForRepresentation(
        of id: ExecutionID,
        boundPosition: ExecutionPosition,
        backend: MLXExecutionStateBackend
    ) async throws -> [Int] {
        let representation = try await backend.captureRepresentation(for: makeHandle(id.rawValue, position: boundPosition.value))
        guard let payload = representation.payload as? MLXPrefixPayload else {
            throw E5Error.foreignRepresentation(id)
        }
        return payload.tokenPrefix
    }

    private static func makeHandle(_ id: String, position: Int64) -> ExecutionStateHandle {
        ExecutionStateHandle(
            id: ExecutionID(id),
            lineage: ExecutionLineage(root: ExecutionID(id)),
            position: ExecutionPosition(position),
            continuation: ExecutionContinuation(nextInput: "", continuationID: ""),
            lifecycle: .active
        )
    }

    public enum E5Error: Error, Equatable {
        case foreignRepresentation(ExecutionID)
    }
}
