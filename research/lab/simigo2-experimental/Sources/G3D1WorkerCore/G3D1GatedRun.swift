import Foundation
import SimiGoRuntimeContract

// G8a CONSTRAINED ENTRY — the D1 worker's execution MUST go through the real
// production gate, not a shortcut.
//
// This file wires a model-free dual-arm run onto the SAME funnel the shipping
// executor uses:
//   * `G3DualArmRunner.run(..., makeCacheSession:)` — the required per-arm cache
//     session makes the settlement-ledger entry unavoidable (a G3 run with no
//     cache is exactly the G8a hole, so the runner cannot express it).
//   * The executor's `.g3` continuation routes through the PUBLIC
//     `G3FirstGenerationEntry.runAsync`, which calls the real isolation gate
//     BEFORE the generate closure. Under the intentionally-empty trust registry
//     that gate REFUSES, so `generate` is never run: the model is never called
//     and the binding is never consumed. This is the honest Phase 1 result — the
//     worker proves the constrained entry refuses, it does NOT claim a delivery.
//
// The generation call count therefore stays zero and `eachArmSettled` stays
// false. A test double that produced a passing "delivery" here would be a fake;
// the whole point is that the gate refuses, and the record says so.

// MARK: - Model-free boundary

/// A model-free `G3ArmCacheBoundary`. It does not load a cache or a model; the
/// dual-arm runner only needs distinct per-arm boundary objects. Its default
/// `adoptTerminationAdjudication` returns false, which means even if a gate ever
/// cleared, `commitDelivery` would refuse fail-closed rather than fake a commit.
final class G3D1Boundary: G3ArmCacheBoundary {
    func beginStep() {}
    var isolationAborted: Bool { false }
    var isolationAbortReason: String? { nil }
}

// MARK: - Empty provider

/// Reports zero attestations. Conforming to the protocol grants NO trust; with
/// the registry still empty the gate refuses regardless — which is what Phase 1
/// requires (no live provider trust is registered).
struct G3D1Provider: RuntimeAttestationProvider {
    let providerID: String
    let providerKind: RuntimeProviderKind = .swiftMLXLiveWorker
    func collect(_ request: AttestationRequest) throws -> [RuntimeAttestation] { [] }
}

// MARK: - The gated executor

/// A model-free executor that conforms to BOTH `G3RoutableContinuation` and
/// `G3CacheSessionInstalling` — the same pair the production MLX executor
/// conforms to — so it can be handed a per-arm cache session and driven by the
/// real dual-arm runner. Its gated continuation calls ONLY the public isolation
/// gate; it never routes to the standard (ungated) path.
public final class G3D1ArmExecutor: G3RoutableContinuation, G3CacheSessionInstalling,
    @unchecked Sendable
{
    public typealias ContinuationResult = G3GateOutcome

    private let armLabel: String
    private(set) var session: G3ArmCacheSession?
    /// Counts how many times the gated forward body actually ran. Under the empty
    /// registry this MUST stay 0 — a nonzero count would mean the gate let a model
    /// call through, which Phase 1 must never produce.
    public private(set) var generateBodyRuns = 0

    public init(armLabel: String) { self.armLabel = armLabel }

    @discardableResult
    public func installG3CacheSession(_ session: G3ArmCacheSession) -> Bool {
        if let existing = self.session { return existing === session }
        self.session = session
        return true
    }

    /// The standard (ungated) route. The D1 worker NEVER uses it; if it is ever
    /// reached it is a wiring error, so it fails closed instead of running an
    /// ungated generation.
    public func continueExecution(
        _ state: ExecutionStateHandle, nextInputTokens: [Int], maxTokens: Int
    ) async throws -> G3GateOutcome {
        throw G3PerArmCacheError.missingCacheSession(
            "d1 worker must not route an ungated generation (\(armLabel))")
    }

    /// The G3-gated route: the public isolation gate runs strictly before the
    /// generate closure. A refusal propagates as `G3FirstGenerationEntry
    /// .EntryError.refused`, which the dual-arm runner records — never a fallback.
    public func continueExecutionG3(
        _ state: ExecutionStateHandle, nextInputTokens: [Int], maxTokens: Int,
        provider: any RuntimeAttestationProvider, request: AttestationRequest
    ) async throws -> G3GateOutcome {
        guard let session else {
            throw G3PerArmCacheError.missingCacheSession("d1:\(armLabel)")
        }
        let run = try await G3FirstGenerationEntry.runAsync(
            provider: provider, request: request,
            generate: {
                // Reached ONLY if the gate cleared. Under the empty registry this
                // line is never executed, so no binding is consumed and no model
                // runs. The body is written as the production shape would be so a
                // later, separately-authorized run has the wiring — not to fake a
                // Phase 1 pass.
                self.generateBodyRuns += 1
                let ledger = session.runLedger
                ledger.recordPhase(.generation, .succeeded("gated_forward"))
                ledger.markSettleEntered()
                ledger.markBindingConsumed()
                ledger.recordPhase(.decode, .succeeded("tokens=1"))
                ledger.recordPhase(.registration, .skipped("model_free_no_registrar"))
                _ = session.commitDelivery(isCancelled: { false }, finalize: {})
            })
        return run.outcome
    }
}

// MARK: - The constrained run

public enum G3D1GatedRun {
    public static let esArm = "ES+IS"
    public static let isArm = "IS-only"

    private static func resource(
        _ role: G3ResourceRole, id: String, arm: String
    ) -> OwnedResource {
        OwnedResource(
            role: role, ownerLabel: arm, access: .armExclusiveMutable,
            storage: .confirmed(id))
    }

    private static func makeOwner(_ arm: String, writeRoot: String) -> G3ArmResourceOwner {
        G3ArmResourceOwner(
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
            writeRoot: writeRoot)
    }

    private static func sessions() -> G3PerArmCacheSessionFactory {
        { armID, _ in
            G3ArmCacheSession(armID: armID.rawValue, boundary: G3D1Boundary())
        }
    }

    /// Drive both arms through the real dual-arm runner and public gate. Returns
    /// the report and the two executors (so the caller can assert the gated
    /// forward body never ran). Throws only if the runner refuses BEFORE dispatch
    /// (isolation precondition or cache wiring); a gate refusal is captured in the
    /// per-arm records, not thrown.
    public static func run(runID: String, challengeNonce: String, writeRootBase: String) async throws
        -> (report: G3DualArmRunReport, esExecutor: G3D1ArmExecutor, isExecutor: G3D1ArmExecutor)
    {
        let esExecutor = G3D1ArmExecutor(armLabel: esArm)
        let isExecutor = G3D1ArmExecutor(armLabel: isArm)
        let esOwner = makeOwner(esArm, writeRoot: "\(writeRootBase)/es")
        let isOwner = makeOwner(isArm, writeRoot: "\(writeRootBase)/is")
        let provider = G3D1Provider(providerID: "simigo.g3.d1.worker")
        let request = try AttestationRequest(runID: runID, challengeNonce: challengeNonce)
        let es = G3ArmExecution(
            owner: esOwner, executor: esExecutor, provider: provider, request: request,
            state: .g3RoutingPlaceholder, nextInputTokens: [1], maxTokens: 1)
        let isArmExec = G3ArmExecution(
            owner: isOwner, executor: isExecutor, provider: provider, request: request,
            state: .g3RoutingPlaceholder, nextInputTokens: [1], maxTokens: 1)
        let report = try await G3DualArmRunner.run(es, isArmExec, makeCacheSession: sessions())
        return (report, esExecutor, isExecutor)
    }
}
