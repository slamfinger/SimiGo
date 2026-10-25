// SPDX-License-Identifier: MIT

// G4 — CANCELLATION IS ADJUDICATED BY ITS POSITION, NOT BY ONE FINAL CHECK.
//
// These tests drive the REAL `MLXPrefixRecomputeExecutor.runGatedGeneration`
// body over a real per-arm `KVCacheSimple` boundary and a weightless model that
// only produces logits. Cancellation is placed deterministically through the
// executor's internal predicate seam (production default: `Task.isCancelled`),
// so each of the three reviewer cases is a separate runtime fact:
//
//   * before the settlement gate  -> settleEntered=false, bindingConsumed=false,
//                                    the bound prefix survives;
//   * after the settlement gate   -> settleEntered=true, bindingConsumed=true,
//                                    commit failed, and the prefix is gone;
//   * at the decode boundary      -> decode succeeded, commit failed, and the
//                                    consumed fact is still visible.
//
// No live model, no provider trust, no G3 execution evidence is claimed.

import Foundation
import MLX
import MLXLMCommon
import MLXNN
import SimiGoRuntimeContract
import Testing

@testable import SimiGo2Experimental

private enum CancellationTestBoundary: Error {
    case modelTouched
}

/// A weightless model that emits a [1, 1, vocab] logits tensor, so the real
/// generation loop can sample token 0 without loading a model.
private final class LogitsModel: Module, LanguageModel, KVCacheDimensionProvider,
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
        throw CancellationTestBoundary.modelTouched
    }

    func callAsFunction(_ inputs: MLXArray, cache: [KVCache]?) -> MLXArray {
        forwardCalls += 1
        let logits = MLXArray.zeros([1, 1, 8], dtype: .float32)
        logits.eval()
        return logits
    }
}

private struct UnusedProcessor: UserInputProcessor {
    func prepare(input: UserInput) async throws -> LMInput {
        throw CancellationTestBoundary.modelTouched
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

/// Thread-safe "cancel on the Nth predicate call". The order is fixed by the
/// executor: entry, step-start, forward, candidateToken, pre-settle, post-settle,
/// post-decode.
private final class CancelAfter: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private let trigger: Int

    init(trigger: Int) { self.trigger = trigger }

    func check() -> Bool {
        lock.lock(); defer { lock.unlock() }
        calls += 1
        return calls >= trigger
    }

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return calls
    }
}

@Suite("G3 cancellation points")
struct G3CancellationPointTests {
    /// A skipped MLX test is not evidence: locate the CPU metallib before any
    /// tensor is evaluated (same discovery the native-cache suite uses).
    private static let ensureRuntime: Void = {
        let fm = FileManager.default
        if let path = ProcessInfo.processInfo.environment["SIMIGO_MLX_METALLIB"],
           !path.isEmpty, fm.fileExists(atPath: path) {
            GPU.metallib = URL(fileURLWithPath: path); return
        }
        let relative = "mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
        let bases = [Bundle.main.resourceURL, Bundle.main.bundleURL,
                     Bundle.main.bundleURL.appendingPathComponent("../Resources")]
        for base in bases {
            let candidate = base?.appendingPathComponent(relative)
            if let candidate, fm.fileExists(atPath: candidate.path) {
                GPU.metallib = candidate; return
            }
        }
        let build = URL(fileURLWithPath: fm.currentDirectoryPath)
            .appendingPathComponent(".build")
        if let enumerator = fm.enumerator(at: build, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where url.path.hasSuffix(relative) {
                GPU.metallib = url; break
            }
        }
    }()

    private func mlx() { _ = Self.ensureRuntime }

    private let runID = ExecutionID("g4-cancel-run")

    private func handle() -> ExecutionStateHandle {
        ExecutionStateHandle(
            id: runID,
            lineage: ExecutionLineage(root: runID),
            position: ExecutionPosition(2),
            continuation: ExecutionContinuation(nextInput: "", continuationID: ""),
            lifecycle: .attached)
    }

    private func container(_ model: LogitsModel) -> ModelContainer {
        ModelContainer(
            context: ModelContext(
                configuration: ModelConfiguration(id: "g4-unused-model"),
                model: model,
                processor: UnusedProcessor(),
                tokenizer: UnusedTokenizer()))
    }

    private func resource(
        _ role: G3ResourceRole, id: String, arm: String
    ) -> OwnedResource {
        OwnedResource(
            role: role, ownerLabel: arm, access: .armExclusiveMutable,
            storage: .confirmed(id))
    }

    /// One sealed owner with a real registrar, so the native cache boundary can
    /// be built exactly as production builds it.
    private func sealedOwner(_ arm: String) -> G3ArmResourceOwner {
        let owner = G3ArmResourceOwner(
            armID: RuntimeArmID(arm), isolationUnitID: "iso-\(arm)",
            modelWeights: OwnedResource(
                role: .modelWeights, ownerLabel: arm, access: .sharedReadOnly,
                storage: .confirmed("weights-\(arm)")),
            modelContentSHA256: String(repeating: "a", count: 64),
            tokenizerData: OwnedResource(
                role: .tokenizerData, ownerLabel: arm, access: .sharedReadOnly,
                storage: .indeterminate),
            tokenizerContentSHA256: String(repeating: "b", count: 64),
            kvCache: resource(.kvCache, id: "kv-\(arm)", arm: arm),
            prefixCache: resource(.prefixCache, id: "prefix-\(arm)", arm: arm),
            runtimeScratch: resource(.runtimeScratch, id: "scratch-\(arm)", arm: arm),
            mutableResources: [resource(.extraMutable, id: "extra-\(arm)", arm: arm)],
            writeRoot: "/tmp/g3/cancel/\(arm)")
        let peer = G3ArmResourceOwner(
            armID: RuntimeArmID("\(arm)-peer"), isolationUnitID: "iso-\(arm)-peer",
            modelWeights: OwnedResource(
                role: .modelWeights, ownerLabel: arm, access: .sharedReadOnly,
                storage: .confirmed("weights-peer")),
            modelContentSHA256: String(repeating: "a", count: 64),
            tokenizerData: OwnedResource(
                role: .tokenizerData, ownerLabel: arm, access: .sharedReadOnly,
                storage: .indeterminate),
            tokenizerContentSHA256: String(repeating: "b", count: 64),
            kvCache: resource(.kvCache, id: "kv-peer", arm: arm),
            prefixCache: resource(.prefixCache, id: "prefix-peer", arm: arm),
            runtimeScratch: resource(.runtimeScratch, id: "scratch-peer", arm: arm),
            mutableResources: [resource(.extraMutable, id: "extra-peer", arm: arm)],
            writeRoot: "/tmp/g3/cancel/peer")
        owner.seal(against: peer)
        peer.seal(against: owner)
        return owner
    }

    private struct CancellationRun {
        let ledger: G3RunLedgerSnapshot
        let terminal: G3TerminalSnapshot
        let forwardCalls: Int
        let error: Error?
        let bindingSurvives: Bool
        let boundaryAdoptedDomain: Bool
        let latchedDuringRun: Bool
    }

    private func execute(
        trigger: Int = .max,
        raceTermination: Bool = false,
        duringRegistration: (@Sendable (G3ArmCacheSession) -> Void)? = nil
    ) async throws -> CancellationRun {
        let model = LogitsModel()
        let backend = MLXExecutionStateBackend()
        let state = handle()
        backend.bind(
            executionID: state.id, position: state.position, tokenPrefix: [1, 2])
        let owner = sealedOwner("ES+IS")
        let registrar = try #require(owner.makeRegistrar())
        let session = try MLXPerArmKVCacheFactory.makeSession(
            armID: owner.armID, registrar: registrar, caches: [KVCacheSimple()])
        let executor = MLXPrefixRecomputeExecutor(
            container: container(model), backend: backend)
        #expect(executor.installG3CacheSession(session))
        let counter = CancelAfter(trigger: trigger)
        executor.isCancelled = { counter.check() }
        if let duringRegistration {
            executor.duringGenerationRegistration = { _, _ in
                duringRegistration(session)
            }
        }

        var thrown: Error? = nil
        // G5: an independent thread latches the gateway while the REAL gated body
        // runs, so the commit is adjudicated against a termination that is not
        // synchronised with any of the body's own checkpoints.
        let raceLatch: DispatchSemaphore?
        if raceTermination, let mlx = session.boundary as? MLXKVCacheBoundary {
            let started = DispatchSemaphore(value: 0)
            let finished = DispatchSemaphore(value: 0)
            let thread = Thread {
                started.signal()
                usleep(UInt32(arc4random_uniform(3000)))
                mlx.terminateArm(reason: "race_stop")
                finished.signal()
            }
            thread.start()
            started.wait()
            raceLatch = finished
        } else {
            raceLatch = nil
        }
        do {
            _ = try await executor.runGatedGeneration(
                state, nextInputTokens: [3], maxTokens: 1,
                registrar: duringRegistration == nil ? nil : registrar)
        } catch {
            thrown = error
        }
        // Join the latch BEFORE reading the ledger: whatever interleaving happened,
        // its effect must already be recorded by the mechanism.
        raceLatch?.wait()

        let survives: Bool
        do {
            _ = try backend.boundPrefix(for: state)
            survives = true
        } catch {
            survives = false
        }

        return CancellationRun(
            ledger: session.runLedger.snapshot,
            terminal: session.terminalSnapshot(),
            forwardCalls: model.forwardCalls,
            error: thrown,
            bindingSurvives: survives,
            boundaryAdoptedDomain: session.boundaryAdoptsAdjudication,
            latchedDuringRun: raceTermination)
    }

    // MARK: 1. Before generation: no forward, no claim, no settlement

    @Test func cancellationBeforeGenerationLeavesBothAxesFalse() async throws {
        mlx()
        try await Device.withDefaultDevice(.cpu) {
            let run = try await execute(trigger: 1)
            #expect(run.error is CancellationError)
            #expect(run.forwardCalls == 0)
            #expect(run.ledger.cancellation == .beforeSettlement)
            #expect(run.ledger.settleEntered == false)
            #expect(run.ledger.bindingConsumed == false)
            #expect(run.ledger.delivery == .notEntered)
            #expect(run.bindingSurvives, "a pre-generation cancellation must not consume")
        }
    }

    // MARK: 2. During generation: the step is not entered

    @Test func cancellationDuringGenerationFailsTheStepBeforeForward() async throws {
        mlx()
        try await Device.withDefaultDevice(.cpu) {
            let run = try await execute(trigger: 2)
            #expect(run.forwardCalls == 0, "the step-start check runs before the forward")
            #expect(run.ledger.delivery.generation.state == .failed)
            #expect(run.ledger.cancellation == .duringGeneration)
            #expect(run.ledger.settleEntered == false)
            #expect(run.ledger.bindingConsumed == false)
            #expect(run.bindingSurvives)
        }
    }

    // MARK: 3. After generation, before the settlement gate

    @Test func cancellationBeforeSettlementRefusesBeforeConsuming() async throws {
        mlx()
        try await Device.withDefaultDevice(.cpu) {
            let run = try await execute(trigger: 5)
            #expect(run.forwardCalls == 1, "generation completed once")
            #expect(run.ledger.delivery.generation.state == .succeeded)
            #expect(run.ledger.cancellation == .beforeSettlement)
            #expect(run.ledger.settleEntered == false)
            #expect(run.ledger.bindingConsumed == false)
            #expect(run.bindingSurvives, "the binding must not be consumed pre-settlement")
        }
    }

    // MARK: 4. After the settlement gate: the consume is a fact, delivery is not

    @Test func cancellationAfterSettlementKeepsTheConsumeVisible() async throws {
        mlx()
        try await Device.withDefaultDevice(.cpu) {
            let run = try await execute(trigger: 6)
            #expect(run.error is CancellationError)
            #expect(run.ledger.delivery.generation.state == .succeeded)
            #expect(run.ledger.settleEntered)
            #expect(run.ledger.bindingConsumed)
            #expect(run.ledger.cancellation == .afterSettlement)
            #expect(run.ledger.delivery.decode.state == .notEntered)
            #expect(run.ledger.delivery.commit.state == .failed)
            #expect(run.bindingSurvives == false, "the bind was consumed before the check")
            #expect(run.terminal.effectiveTerminationReason == "task_cancelled")
        }
    }

    // MARK: 5. At the decode boundary: decode succeeded, commit blocked

    @Test func cancellationAtTheDecodeBoundaryBlocksCommit() async throws {
        mlx()
        try await Device.withDefaultDevice(.cpu) {
            let run = try await execute(trigger: 7)
            #expect(run.error is CancellationError)
            #expect(run.ledger.settleEntered)
            #expect(run.ledger.bindingConsumed)
            #expect(run.ledger.cancellation == .afterDecode)
            #expect(run.ledger.delivery.decode.state == .succeeded)
            #expect(run.ledger.delivery.commit.state == .failed)
            #expect(run.ledger.delivery.completed == false)
            #expect(run.bindingSurvives == false)
        }
    }

    // MARK: 6. Between decode and commit: the cutoff is the commit region
    //
    // This is the last point at which a cancellation can still refuse delivery.
    // The sample is taken INSIDE the arm's adjudication domain, together with the
    // commit transition, so no cancellation can land between "checked" and
    // "committed".

    @Test func cancellationAtTheCommitCutoffBlocksDelivery() async throws {
        mlx()
        try await Device.withDefaultDevice(.cpu) {
            let run = try await execute(trigger: 8)
            #expect(run.error is CancellationError)
            #expect(run.ledger.settleEntered)
            #expect(run.ledger.bindingConsumed)
            #expect(run.ledger.cancellation == .atCommitCutoff)
            #expect(run.ledger.delivery.decode.state == .succeeded)
            #expect(run.ledger.delivery.registration.state == .skipped)
            #expect(run.ledger.delivery.commit.state == .failed)
            #expect(
                run.ledger.delivery.commit.detail == "cancelled_at_commit_cutoff")
            #expect(run.ledger.delivery.completed == false)
            #expect(run.ledger.isFullyDelivered == false)
        }
    }

    // MARK: 7. G5: a gateway latch during registration blocks the commit

    @Test func gatewayLatchDuringRegistrationBlocksDelivery() async throws {
        mlx()
        try await Device.withDefaultDevice(.cpu) {
            let run = try await execute { session in
                (session.boundary as? MLXKVCacheBoundary)?
                    .terminateArm(reason: "gateway_stop")
            }
            guard case .armTerminated(reason: "gateway_stop") = run.error
                    as? G3PerArmCacheError else {
                Issue.record("expected armTerminated(gateway_stop), got \(String(describing: run.error))")
                return
            }
            #expect(run.ledger.settleEntered)
            #expect(run.ledger.bindingConsumed)
            #expect(run.ledger.postSettlementTermination == "gateway_stop")
            #expect(run.ledger.delivery.registration.state == .succeeded)
            #expect(run.ledger.delivery.commit.state == .failed)
            #expect(
                run.ledger.delivery.commit.detail
                == "terminated_at_commit_cutoff:gateway_stop",
                "the refusal comes out of the adjudicated region, not a pre-check")
            #expect(run.ledger.isFullyDelivered == false)
            #expect(run.terminal.gatewayTerminationReason == "gateway_stop")
            #expect(run.bindingSurvives == false, "the consume is not rolled back")
        }
    }

    // MARK: 8. G5: the production commit runs inside the arm's adjudication domain

    @Test func realGatedRunCommitsUnderTheArmDomain() async throws {
        mlx()
        try await Device.withDefaultDevice(.cpu) {
            let run = try await execute()
            #expect(run.error == nil)
            #expect(run.boundaryAdoptedDomain, "the production boundary adopts the domain")
            #expect(run.ledger.delivery.commit.detail == "result_delivered")
            #expect(
                run.ledger.transitions.contains {
                    $0.hasPrefix("commit.adjudicated_under=arm:")
                },
                "the commit transition must name the domain that serialized it")
            #expect(run.ledger.isFullyDelivered)
            #expect(run.bindingSurvives == false)
        }
    }

    // MARK: 9. G5: a gateway latch racing the real gated body is never lost

    @Test func gatewayLatchRacingTheRealRunNeverBecomesCleanEvidence() async throws {
        mlx()
        for _ in 0..<8 {
            try await Device.withDefaultDevice(.cpu) {
                let run = try await execute(raceTermination: true)
                // The latch always becomes visible — either the run refused, or the
                // commit went through and the LATCH ITSELF filed the late termination.
                #expect(run.terminal.gatewayTerminationReason == "race_stop")
                #expect(
                    run.ledger.isFullyDelivered == false,
                    "an arm whose gateway was latched is never clean evidence")
                if run.error == nil {
                    // Committed first: the consumed fact and the commit stand, and the
                    // late termination was recorded without any later sampling.
                    #expect(run.ledger.delivery.commit.state == .succeeded)
                    #expect(run.ledger.postSettlementTermination == "race_stop")
                    #expect(run.ledger.bindingConsumed)
                } else {
                    #expect(run.ledger.delivery.commit.state != .succeeded)
                }
            }
        }
    }
}
