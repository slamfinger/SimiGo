// SPDX-License-Identifier: MIT

// G8a — THE POST-GATE ADMISSION GUARD IS EXECUTABLE, NOT JUST ORDERED TEXT
//
// The reviewer's acceptance condition is stronger than "candidateToken stayed
// zero": the refusal must land before the real model entry (`context.model`) and
// before `consumeBinding`. The public gated entry cannot reach its generate
// closure while the trusted-provider registry is empty, so this test drives the
// exact production body (`runGatedGeneration`, internal, only called from inside
// the cleared-gate closure) on an executor built from a counting, weightless
// model container.
//
// It proves, at runtime:
//   * the missing-session error is raised, not a later cache/binding error;
//   * the model's forward was never entered (forwardCalls == 0);
//   * a previously bound prefix survives (consumeBinding did not run);
//   * no session exists, so no claim or settlement can have happened.
//
// It does not prove the public entry's gate ordering (covered by the
// G3FirstGenerationEntry tests) and it is not a live-model D1 run.

import Foundation
import MLX
import MLXLMCommon
import MLXNN
import SimiGoRuntimeContract
import Testing

@testable import SimiGo2Experimental

private enum DummyBoundaryError: Error {
    case modelTouched
}

/// A weightless model that counts real forward entries. Any entry is a test
/// failure: the admission guard must throw before `context.model` is called.
private final class ForwardCountingModel: Module, LanguageModel, KVCacheDimensionProvider,
    @unchecked Sendable
{
    private(set) var forwardCalls = 0

    var kvHeads: [Int] { [] }

    func prepare(
        _ input: LMInput,
        cache: [KVCache],
        state: LMOutput.State?,
        prefill: PrefillParameters
    ) throws -> PrepareResult {
        throw DummyBoundaryError.modelTouched
    }

    func callAsFunction(_ inputs: MLXArray, cache: [KVCache]?) -> MLXArray {
        forwardCalls += 1
        return MLXArray(0)
    }
}

private struct UnusedProcessor: UserInputProcessor {
    func prepare(input: UserInput) async throws -> LMInput {
        throw DummyBoundaryError.modelTouched
    }
}

private struct UnusedTokenizer: Tokenizer {
    func encode(text: String, addSpecialTokens: Bool) -> [Int] { [] }
    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String { "" }
    func convertTokenToId(_ token: String) -> Int? { nil }
    func convertIdToToken(_ id: Int) -> String? { nil }

    var bosToken: String? { nil }
    var eosToken: String? { nil }
    var unknownToken: String? { nil }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        []
    }
}

/// A well-formed live provider that the shipping trust registry does NOT list.
/// The real gate therefore refuses it at `provider_trust`, which is exactly the
/// production state until G7a registers a one-time provider.
private struct UnregisteredLiveProvider: RuntimeAttestationProvider {
    let providerID = "simigo.g8a.public-entry.unregistered"
    let providerKind: RuntimeProviderKind = .swiftMLXLiveWorker
    func collect(_ request: AttestationRequest) throws -> [RuntimeAttestation] { [] }
}

@Suite("G3 gated-entry admission")
struct G3GatedEntryAdmissionTests {
    private let runID = ExecutionID("g8a-admission-run")

    private func handle() -> ExecutionStateHandle {
        ExecutionStateHandle(
            id: runID,
            lineage: ExecutionLineage(root: runID),
            position: ExecutionPosition(2),
            continuation: ExecutionContinuation(nextInput: "", continuationID: ""),
            lifecycle: .attached)
    }

    private func container(_ model: ForwardCountingModel) -> ModelContainer {
        ModelContainer(
            context: ModelContext(
                configuration: ModelConfiguration(id: "g8a-unused-model"),
                model: model,
                processor: UnusedProcessor(),
                tokenizer: UnusedTokenizer()))
    }

    @Test func missingSessionRefusesBeforeModelOrBindingConsumption() async throws {
        let model = ForwardCountingModel()
        let backend = MLXExecutionStateBackend()
        let state = handle()
        backend.bind(
            executionID: state.id, position: state.position, tokenPrefix: [1, 2])
        let executor = MLXPrefixRecomputeExecutor(
            container: container(model), backend: backend)

        do {
            _ = try await executor.runGatedGeneration(
                state, nextInputTokens: [3], maxTokens: 1, registrar: nil)
            Issue.record("a sessionless gated body must not return a result")
        } catch let error as G3PerArmCacheError {
            #expect(
                error == .missingCacheSession("g3_route_requires_per_arm_cache_session"),
                "the refusal must be the session admission, not a later cache/binding error")
        } catch {
            Issue.record("unexpected error: \(error)")
        }

        #expect(model.forwardCalls == 0, "context.model must not be entered")
        #expect(executor.g3CacheSession == nil, "no session exists to claim")
        let bound = try backend.boundPrefix(for: state)
        #expect(bound.prefix == [1, 2], "consumeBinding must not have run")
    }

    /// G8a layer 2: the PUBLIC entry. A sessionless executor is not enough to
    /// skip admission: `continueExecutionG3` must go through the real gate, and
    /// with the shipping registry empty it refuses at `provider_trust` before
    /// any model forward or binding consumption.
    ///
    /// This is a different evidence class from the body test above: it proves
    /// the public entry cannot reach generation on its own, not that the gate
    /// closure is safe once a trusted provider exists (that ordering is the
    /// `source_order` check plus the guard inside the body).
    @Test func publicEntryRefusesAtGateBeforeModelOrBindingConsumption() async throws {
        let model = ForwardCountingModel()
        let backend = MLXExecutionStateBackend()
        let state = handle()
        backend.bind(
            executionID: state.id, position: state.position, tokenPrefix: [1, 2])
        let executor = MLXPrefixRecomputeExecutor(
            container: container(model), backend: backend)
        let request = try AttestationRequest(
            runID: "g8a-public-entry", challengeNonce: "g8a-public-entry-nonce")

        do {
            _ = try await executor.continueExecutionG3(
                state, nextInputTokens: [3], maxTokens: 1,
                provider: UnregisteredLiveProvider(), request: request, registrar: nil)
            Issue.record("the public entry must not generate without a trusted provider")
        } catch let error as G3FirstGenerationEntry.EntryError {
            guard case .refused(let outcome) = error else {
                Issue.record("unexpected entry error: \(error)")
                return
            }
            #expect(outcome.stage == "provider_trust")
            #expect(outcome.passed == false)
            #expect(outcome.generationCallCount == 0)
            #expect(outcome.isExecutionEvidence == false)
        } catch {
            Issue.record("unexpected error: \(error)")
        }

        #expect(model.forwardCalls == 0, "the public entry must not enter the model")
        #expect(executor.g3CacheSession == nil, "no session was ever installed")
        let bound = try backend.boundPrefix(for: state)
        #expect(bound.prefix == [1, 2], "the public entry must not consume a binding")
    }
}
