// SPDX-License-Identifier: MIT

// NATIVE ES-HANDOFF END-TO-END TESTS — real MLX carrier + real IS bridge, ZERO weights
//
// The two halves are already proven separately:
//   * NativeCarrierLifecycleTests — the settle -> release -> fresh-ES recover ->
//     continue PROTOCOL and its fail-closed branches, but the carrier is a
//     model-free double whose retired mutable-storage set is empty.
//   * NativeMLXCarrierReleaseTests — a REAL G3ArmCacheSession (MLXKVCacheBoundary
//     + KVCacheSimple + write observer) releases for real and storage identity is
//     read from real MLXArrays, but it never runs the production IS->ES recovery.
//
// This file welds them into ONE path: a real MLX KV carrier is settled, released
// through the PRODUCTION integration entrypoint `releaseExecutionCarrier`, and a
// brand-new ES recovers the settled representation through `recoverExecutionState`
// (IS authority + settlement-checkpoint cross-validation + persisted rebind + the
// carrier-isolation gate fed by the REAL gateway's confirmed ids), then continues
// WITHOUT re-tokenizing the seed. Model weights are never loaded: the forward that
// admits real KV runs synthetic CPU tensors through the genuine cache, and the
// continuation is model-free.
//
// THREE PROPOSITIONS, STILL KEPT APART (the reviewer's standing warning):
//   (A) ARC object lifecycle — weak probes show the released cache/gateway/observer
//       deallocate once no holder remains. A Swift reference fact.
//   (B) old-carrier non-reuse — the retired backend carrier and the retired G3
//       session slot refuse read/rebind/re-arm. Tombstone + terminal-state fact.
//   (C) storage relationship — the handoff isolation gate grades REAL
//       `mlxStorageIdentity`-derived ids: disjoint -> isolated, overlap -> shared
//       (refused), retired-nonempty vs adopting-empty -> unobservable (refused).
//   NONE of these measures MLX's allocator returning device pages to the OS, and
//   nothing here proves ES recovery continuation on a real loaded model. D1 NO-GO.

import XCTest
import MLX
import MLXLMCommon
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

/// A real MLX G3 KV carrier wrapped in a model-free continuation executor. Its
/// `ExecutionCarrierReleasing` methods are the PRODUCTION executor's release logic
/// verbatim — same single-use `G3CacheSessionSlot`, same `G3KVAllocationGateway
/// .registeredBufferIDs` snapshot, same `MLXExecutionStateBackend` tombstone, same
/// `CarrierStorageIsolationEvaluator` — so the handoff is exercised against real
/// MLX objects, while tokenization/generation stay synthetic (no model loaded).
final class RealCarrierHandoffExecutor: ProductionRuntimeModelContinuationExecutor,
    ExecutionCarrierReleasing, @unchecked Sendable {

    let backend: MLXExecutionStateBackend
    private let slot = G3CacheSessionSlot()
    private var retiredCarrierStorage: [ExecutionID: Set<String>] = [:]

    private(set) var tokenizeSeedCallCount = 0
    private(set) var tokenizeTextCallCount = 0
    private(set) var continueExecutionCallCount = 0

    /// Injected failure so a test proves the native lifecycle refuses the handoff
    /// (and leaves the old carrier intact) when release does not take.
    var releaseCarrierError: Error?

    init(backend: MLXExecutionStateBackend) { self.backend = backend }

    var g3CacheSession: G3ArmCacheSession? { slot.installed }
    var g3CacheGateway: G3KVAllocationGateway? {
        (slot.installed?.boundary as? MLXKVCacheBoundary)?.gateway
    }
    /// The REAL confirmed mutable-storage ids THIS carrier currently observes.
    var observedStorageIDs: Set<String> { g3CacheGateway?.registeredBufferIDs ?? [] }

    /// Install a real session over a real `KVCacheSimple` and commit one step of
    /// synthetic CPU KV so the gateway genuinely registers mutable storage ids.
    /// Must be called inside a CPU `Device.withDefaultDevice` block.
    @discardableResult
    func installAdmittedRealSession(arm: String, registrar: G3AllocationRegistrar) throws
        -> G3ArmStepOutcome {
        let cache = KVCacheSimple()
        let session = try MLXPerArmKVCacheFactory.makeSession(
            armID: RuntimeArmID(arm), registrar: registrar, caches: [cache])
        guard slot.install(session) else {
            preconditionFailure("a fresh slot must accept the first session")
        }
        let q = MLXKVHandoffFixtures.kv(1)
        let step = session.runStep(
            forward: { MLXKVHandoffFixtures.attend(cache, q: q) },
            candidateToken: { 7 })
        return step
    }

    // MARK: ProductionRuntimeModelContinuationExecutor — model-free continuation

    func tokenizeText(_ text: String) async throws -> [Int] {
        tokenizeTextCallCount += 1
        return Array(text.utf8.prefix(24)).map(Int.init)
    }

    func tokenizeSeedText(_ text: String) async throws -> [Int] {
        tokenizeSeedCallCount += 1
        return Array(text.utf8.prefix(32)).map(Int.init)
    }

    func continueExecution(
        _ state: ExecutionStateHandle, nextInputTokens: [Int], maxTokens: Int
    ) async throws -> ExecutionContinuationResult {
        continueExecutionCallCount += 1
        // Consume the CURRENT physical binding exactly as the production executor
        // does after a forward; the Runtime rebinds the advanced representation.
        let bound = try backend.boundPrefix(for: state)
        backend.consumeBinding(for: state)
        return ExecutionContinuationResult(
            executionID: state.id,
            consumedPrefixLength: bound.prefix.count,
            nextInputTokenCount: nextInputTokens.count,
            generatedTokenIDs: [101, 102, 103],
            generatedText: "real-carrier-handoff",
            updatedPayload: MLXPrefixPayload(tokenPrefix: [9, 18, 27]))
    }

    // MARK: ExecutionCarrierReleasing — production release logic, real MLX carrier

    func releaseExecutionCarrier(for state: ExecutionStateHandle) throws {
        if let releaseCarrierError { throw releaseCarrierError }
        retiredCarrierStorage[state.id] = g3CacheGateway?.registeredBufferIDs ?? []
        slot.release()
        backend.releaseCarrier(for: state.id)
    }

    func verifyCarrierUnusable(for state: ExecutionStateHandle) throws {
        guard backend.isCarrierRetired(for: state.id) else {
            throw CarrierLifecycleError.releaseIncomplete(
                reason: "physical representation carrier not retired")
        }
        do {
            _ = try backend.boundPrefix(for: state)
            throw CarrierLifecycleError.carrierStillUsable(executionID: state.id.rawValue)
        } catch let error as ExecutionStateBackendError {
            guard case .carrierReleased = error else {
                throw CarrierLifecycleError.releaseIncomplete(
                    reason: "bound read failed as \(error), not carrierReleased")
            }
        }
        guard slot.isRetired else {
            throw CarrierLifecycleError.releaseIncomplete(reason: "G3 cache session slot not retired")
        }
    }

    func retiredCarrierStorageIDs(for state: ExecutionStateHandle) -> Set<String> {
        retiredCarrierStorage[state.id] ?? []
    }

    func verifyAdoptedCarrierIsolated(
        from retiredStorageIDs: Set<String>, for state: ExecutionStateHandle
    ) throws {
        let adopting = g3CacheGateway?.registeredBufferIDs ?? []
        switch CarrierStorageIsolationEvaluator.evaluate(
            retired: retiredStorageIDs, adopting: adopting) {
        case .isolated:
            return
        case .shared(let overlap):
            throw CarrierLifecycleError.carriersShareStorage(
                executionID: state.id.rawValue, sharedBufferIDs: overlap.sorted())
        case .unobservable:
            throw CarrierLifecycleError.carrierStorageIsolationUnobservable(
                executionID: state.id.rawValue)
        }
    }
}

/// Model-free helpers to build/admit real CPU KV, shared by the executor and the
/// test body. No weights, no GPU.
enum MLXKVHandoffFixtures {
    static func kv(_ seq: Int, headDim: Int = 8) -> MLXArray {
        let t = ones([1, 1, seq, headDim], dtype: .float32)
        t.eval()
        return t
    }

    static func attend(_ cache: KVCacheSimple, q: MLXArray) {
        let attended = attentionWithCacheUpdate(
            queries: q, keys: q, values: q, cache: cache, scale: 0.25)
        attended.eval()
    }
}

final class NativeMLXCarrierHandoffTests: XCTestCase {

    // MARK: Runtime + IS-bridge harness

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
            let cand = base?.appendingPathComponent(relative)
            if let cand, fm.fileExists(atPath: cand.path) { GPU.metallib = cand; return }
        }
        let build = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(".build")
        if let e = fm.enumerator(at: build, includingPropertiesForKeys: nil) {
            for case let url as URL in e where url.path.hasSuffix(relative) {
                GPU.metallib = url; break
            }
        }
    }()

    private func mlx() { _ = Self.ensureRuntime }

    private func resource(
        _ role: G3ResourceRole, id: String, arm: String,
        access: G3ResourceAccess = .armExclusiveMutable
    ) -> OwnedResource {
        OwnedResource(role: role, ownerLabel: arm, access: access, storage: .confirmed(id))
    }

    private func makeArm(_ arm: String) -> G3ArmResourceOwner {
        G3ArmResourceOwner(
            armID: RuntimeArmID(arm), isolationUnitID: "iso-\(arm)",
            modelWeights: resource(.modelWeights, id: "weights-\(arm)", arm: arm, access: .sharedReadOnly),
            modelContentSHA256: String(repeating: "a", count: 64),
            tokenizerData: OwnedResource(
                role: .tokenizerData, ownerLabel: arm, access: .sharedReadOnly, storage: .indeterminate),
            tokenizerContentSHA256: String(repeating: "b", count: 64),
            kvCache: resource(.kvCache, id: "kv-\(arm)", arm: arm),
            prefixCache: resource(.prefixCache, id: "prefix-\(arm)", arm: arm),
            runtimeScratch: resource(.runtimeScratch, id: "scratch-\(arm)", arm: arm),
            mutableResources: [resource(.extraMutable, id: "extra-\(arm)", arm: arm)],
            writeRoot: "/tmp/g3-e2e/\(arm)")
    }

    private func sealedPair() -> (G3ArmResourceOwner, G3ArmResourceOwner) {
        let es = makeArm("ES+IS")
        let peer = makeArm("IS-only")
        es.seal(against: peer); peer.seal(against: es)
        return (es, peer)
    }

    private func makeTemporaryDatabase() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-e2e-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("production_runtime.sqlite")
    }

    private func makeIsolatedConfiguration() throws -> (
        configuration: ProductionRuntimeLaunchConfiguration, directory: URL
    ) {
        let labRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-e2e-policy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let policy = directory.appendingPathComponent("validity-policy.json")
        let policyObject: [String: Any] = [
            "schema_id": "SIMIGO-INFO-VALIDITY-POLICY-V1",
            "policy_version": "native-mlx-carrier-handoff-test",
            "policy_source": "ISOLATED_TEST_ONLY",
            "missing_policy": "REJECT",
            "dependency_propagation": "ALL_TRANSITIVE",
            "default_valid_until_utc": "2030-12-31T23:59:59Z",
        ]
        try JSONSerialization.data(withJSONObject: policyObject).write(to: policy)
        let configuration = ProductionRuntimeLaunchConfiguration(
            runtimeRoot: labRoot.appendingPathComponent("execution-information-loop"),
            pythonExecutable: URL(fileURLWithPath: "/usr/bin/python3"),
            snapshotPath: labRoot.appendingPathComponent(
                "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite"),
            validityPolicyPath: policy)
        return (configuration, directory)
    }

    private func stateDirectory(in isolated: (configuration: ProductionRuntimeLaunchConfiguration, directory: URL), _ name: String) -> URL {
        isolated.directory.appendingPathComponent("es-state-\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    private func latestExecutionState(
        _ integration: ProductionRuntimeInformationIntegration, database: URL
    ) throws -> [String: Any]? {
        try integration.status(database: database)["execution_state"] as? [String: Any]
    }

    // MARK: End-to-end — real carrier settles, releases through production, fresh ES recovers isolated

    func testRealCarrierSettlesReleasesThroughProductionThenFreshCarrierRecoversIsolated() async throws {
        mlx()
        let database = try makeTemporaryDatabase()
        let isolated = try makeIsolatedConfiguration()
        // Both the settling ES and the recovering ES read the SAME durable store:
        // recovery is a fresh backend + coordinator over the store the old session
        // persisted, never a fresh empty store.
        let storeA = stateDirectory(in: isolated, "old")

        // OLD ES on a REAL MLX KV carrier.
        let (es, _) = sealedPair()
        let oldRegistrar = try XCTUnwrap(es.makeRegistrar())
        let oldBackend = MLXExecutionStateBackend()
        let oldExecutor = RealCarrierHandoffExecutor(backend: oldBackend)
        // Admit real KV so the retired carrier genuinely held observable mutable storage.
        try Device.withDefaultDevice(.cpu) {
            XCTAssertEqual(try oldExecutor.installAdmittedRealSession(arm: "ES+IS", registrar: oldRegistrar),
                           .committed(token: 7))
        }
        XCTAssertTrue(!oldExecutor.observedStorageIDs.isEmpty,
                      "a real admitted KV session must register confirmed ids")

        let first = try ProductionRuntimeInformationIntegration(
            configuration: isolated.configuration, modelExecutor: oldExecutor,
            backend: oldBackend, semanticStateDirectory: storeA)
        try first.initialize(database: database, validUntil: "2030-12-31T23:59:59Z")
        let phaseOne = try await first.continueWithRealInformation(
            database: database, handle: nil,
            advancementID: "hand-001", evaluatedAtUTC: "2026-10-09T00:00:00Z")
        XCTAssertEqual(phaseOne.handle.position, ExecutionPosition(1))

        // RELEASE through the PRODUCTION entrypoint: capture the real retired ids.
        let retired = try first.releaseExecutionCarrier(for: phaseOne.handle)
        XCTAssertEqual(retired, oldExecutor.retiredCarrierStorageIDs(for: phaseOne.handle))
        XCTAssertTrue(!retired.isEmpty, "the retired real carrier must report its real storage ids")

        // Proposition B — the old backend carrier is genuinely unusable.
        XCTAssertTrue(oldBackend.isCarrierRetired(for: phaseOne.handle.id))
        XCTAssertThrowsError(try oldBackend.boundPrefix(for: phaseOne.handle)) { error in
            guard case ExecutionStateBackendError.carrierReleased = error else {
                return XCTFail("expected carrierReleased, got \(error)")
            }
        }
        // Proposition A — the real cache/gateway/observer deallocate with the slot.
        XCTAssertNil(oldExecutor.g3CacheSession)
        XCTAssertNil(oldExecutor.g3CacheGateway)

        // FRESH ES on a NEW real carrier over DISJOINT real storage, new backend.
        let (es2, _) = sealedPair()
        let freshRegistrar = try XCTUnwrap(es2.makeRegistrar())
        let freshBackend = MLXExecutionStateBackend()
        let freshExecutor = RealCarrierHandoffExecutor(backend: freshBackend)
        try Device.withDefaultDevice(.cpu) {
            _ = try freshExecutor.installAdmittedRealSession(arm: "ES+IS", registrar: freshRegistrar)
        }
        let second = try ProductionRuntimeInformationIntegration(
            configuration: isolated.configuration, modelExecutor: freshExecutor,
            backend: freshBackend, semanticStateDirectory: storeA)

        // Recovery: IS authority + checkpoint + persisted rebind + real isolation gate.
        let recovered = try await second.recoverExecutionState(
            database: database, carrierIsolationAgainst: retired)
        XCTAssertEqual(recovered.position, ExecutionPosition(1))
        let bound = try freshBackend.boundPrefix(for: recovered)
        XCTAssertEqual(bound.prefix, [9, 18, 27],
                       "the recovered representation is the settled one, not a re-derived prefix")

        // Continue on the recovered ES — no seed re-tokenization, genuine reuse.
        let phaseTwo = try await second.continueWithRealInformation(
            database: database, handle: recovered,
            advancementID: "hand-002", evaluatedAtUTC: "2026-10-09T00:01:00Z")
        XCTAssertEqual(phaseTwo.report.state, "ADVANCED")
        XCTAssertEqual(phaseTwo.report.reusedItemIDs.count, 9)
        XCTAssertEqual(freshExecutor.tokenizeSeedCallCount, 0,
                       "recovery must not fabricate a prefix by re-tokenizing the seed")
        XCTAssertEqual(freshExecutor.continueExecutionCallCount, 1)
    }

    // MARK: Fail-closed injection 1 — a real carrier that cannot be released

    func testRealCarrierReleaseFailureRefusesHandoffAndKeepsOldCarrierUsable() async throws {
        mlx()
        let database = try makeTemporaryDatabase()
        let isolated = try makeIsolatedConfiguration()
        let store = stateDirectory(in: isolated, "release-fail")

        let (es, _) = sealedPair()
        let registrar = try XCTUnwrap(es.makeRegistrar())
        let backend = MLXExecutionStateBackend()
        let executor = RealCarrierHandoffExecutor(backend: backend)
        try Device.withDefaultDevice(.cpu) {
            _ = try executor.installAdmittedRealSession(arm: "ES+IS", registrar: registrar)
        }
        let first = try ProductionRuntimeInformationIntegration(
            configuration: isolated.configuration, modelExecutor: executor,
            backend: backend, semanticStateDirectory: store)
        try first.initialize(database: database, validUntil: "2030-12-31T23:59:59Z")
        let phaseOne = try await first.continueWithRealInformation(
            database: database, handle: nil,
            advancementID: "hand-010", evaluatedAtUTC: "2026-10-09T00:00:00Z")

        // A release that throws must refuse the handoff and leave the carrier live.
        executor.releaseCarrierError = NSError(domain: "release-refused", code: 7)
        XCTAssertThrowsError(try first.releaseExecutionCarrier(for: phaseOne.handle))
        XCTAssertFalse(backend.isCarrierRetired(for: phaseOne.handle.id),
                       "a failed release must NOT retire the carrier")
        XCTAssertNoThrow(try backend.boundPrefix(for: phaseOne.handle),
                         "the old carrier is still usable, so no fresh recovery may assume release")
    }

    // MARK: Fail-closed injection 2 — real shared storage refuses before a handle is returned

    func testSharedRealStorageRefusesRecoveryBeforeHandleReturned() async throws {
        mlx()
        let database = try makeTemporaryDatabase()
        let isolated = try makeIsolatedConfiguration()
        let storeOld = stateDirectory(in: isolated, "share-old")

        // Settle and release the old real carrier.
        let (es, _) = sealedPair()
        let oldBackend = MLXExecutionStateBackend()
        let oldExecutor = RealCarrierHandoffExecutor(backend: oldBackend)
        try Device.withDefaultDevice(.cpu) {
            _ = try oldExecutor.installAdmittedRealSession(
                arm: "ES+IS", registrar: try XCTUnwrap(es.makeRegistrar()))
        }
        let first = try ProductionRuntimeInformationIntegration(
            configuration: isolated.configuration, modelExecutor: oldExecutor,
            backend: oldBackend, semanticStateDirectory: storeOld)
        try first.initialize(database: database, validUntil: "2030-12-31T23:59:59Z")
        let phaseOne = try await first.continueWithRealInformation(
            database: database, handle: nil,
            advancementID: "hand-020", evaluatedAtUTC: "2026-10-09T00:00:00Z")
        _ = try first.releaseExecutionCarrier(for: phaseOne.handle)

        // The adopted fresh carrier genuinely holds a real confirmed buffer; if the
        // retired carrier is reported to hold that SAME buffer (the old state was
        // never released and the fresh one aliases it), the recovery gate refuses.
        let (es2, _) = sealedPair()
        let freshBackend = MLXExecutionStateBackend()
        let freshExecutor = RealCarrierHandoffExecutor(backend: freshBackend)
        try Device.withDefaultDevice(.cpu) {
            _ = try freshExecutor.installAdmittedRealSession(
                arm: "ES+IS", registrar: try XCTUnwrap(es2.makeRegistrar()))
        }
        let aliased = freshExecutor.observedStorageIDs
        XCTAssertFalse(aliased.isEmpty)
        let second = try ProductionRuntimeInformationIntegration(
            configuration: isolated.configuration, modelExecutor: freshExecutor,
            backend: freshBackend, semanticStateDirectory: storeOld)

        do {
            _ = try await second.recoverExecutionState(
                database: database, carrierIsolationAgainst: aliased)
            XCTFail("recovery over aliased real storage must be refused")
        } catch let error as CarrierLifecycleError {
            guard case .carriersShareStorage(let executionID, let shared) = error else {
                return XCTFail("expected carriersShareStorage, got \(error)")
            }
            XCTAssertEqual(executionID, ProductionRuntimeInformationIntegration.executionID.rawValue)
            XCTAssertEqual(Set(shared), aliased)
        }
        // The refusal returned no handle and performed no model work.
        XCTAssertEqual(freshExecutor.continueExecutionCallCount, 0)
    }

    // MARK: Fail-closed injection 2b — unobservable adopted carrier refuses (real retired ids)

    func testUnobservableAdoptedCarrierRefusesRecovery() async throws {
        mlx()
        let database = try makeTemporaryDatabase()
        let isolated = try makeIsolatedConfiguration()
        let storeOld = stateDirectory(in: isolated, "unobs-old")

        // Retire a real carrier that DID hold observable mutable storage.
        let (es, _) = sealedPair()
        let oldBackend = MLXExecutionStateBackend()
        let oldExecutor = RealCarrierHandoffExecutor(backend: oldBackend)
        try Device.withDefaultDevice(.cpu) {
            _ = try oldExecutor.installAdmittedRealSession(
                arm: "ES+IS", registrar: try XCTUnwrap(es.makeRegistrar()))
        }
        let first = try ProductionRuntimeInformationIntegration(
            configuration: isolated.configuration, modelExecutor: oldExecutor,
            backend: oldBackend, semanticStateDirectory: storeOld)
        try first.initialize(database: database, validUntil: "2030-12-31T23:59:59Z")
        let phaseOne = try await first.continueWithRealInformation(
            database: database, handle: nil,
            advancementID: "hand-030", evaluatedAtUTC: "2026-10-09T00:00:00Z")
        let retired = try first.releaseExecutionCarrier(for: phaseOne.handle)
        XCTAssertFalse(retired.isEmpty)

        // The fresh carrier installs a session but observes NO mutable storage:
        // isolation from a real retired set is UNPROVEN, never assumed distinct.
        let freshBackend = MLXExecutionStateBackend()
        let freshExecutor = RealCarrierHandoffExecutor(backend: freshBackend)
        XCTAssertTrue(freshExecutor.observedStorageIDs.isEmpty)
        let second = try ProductionRuntimeInformationIntegration(
            configuration: isolated.configuration, modelExecutor: freshExecutor,
            backend: freshBackend, semanticStateDirectory: storeOld)

        do {
            _ = try await second.recoverExecutionState(
                database: database, carrierIsolationAgainst: retired)
            XCTFail("unproven isolation must fail closed")
        } catch let error as CarrierLifecycleError {
            guard case .carrierStorageIsolationUnobservable = error else {
                return XCTFail("expected unobservable, got \(error)")
            }
        }
        XCTAssertEqual(freshExecutor.continueExecutionCallCount, 0)
    }

    // MARK: Fail-closed injection 3 — a stale ES checkpoint refuses before any new side effect

    func testCheckpointMismatchRefusesRealCarrierRecoveryBeforeAnyNewSideEffect() async throws {
        mlx()
        let database = try makeTemporaryDatabase()
        let isolated = try makeIsolatedConfiguration()
        let staleStore = stateDirectory(in: isolated, "stale")

        // Settle the real carrier at hand-001 under its durable store.
        let (es, _) = sealedPair()
        let backend = MLXExecutionStateBackend()
        let executor = RealCarrierHandoffExecutor(backend: backend)
        try Device.withDefaultDevice(.cpu) {
            _ = try executor.installAdmittedRealSession(
                arm: "ES+IS", registrar: try XCTUnwrap(es.makeRegistrar()))
        }
        let first = try ProductionRuntimeInformationIntegration(
            configuration: isolated.configuration, modelExecutor: executor,
            backend: backend, semanticStateDirectory: staleStore)
        try first.initialize(database: database, validUntil: "2030-12-31T23:59:59Z")
        _ = try await first.continueWithRealInformation(
            database: database, handle: nil,
            advancementID: "hand-001", evaluatedAtUTC: "2026-10-09T00:00:00Z")

        // IS independently advances to hand-002 via a separate authority (its own
        // store), so the stale ES checkpoint (hand-001) now lags the Information
        // Space. The executor and the integration must share ONE backend instance.
        let advBackend = MLXExecutionStateBackend()
        let advancer = try ProductionRuntimeInformationIntegration(
            configuration: isolated.configuration,
            modelExecutor: RealCarrierHandoffExecutor(backend: advBackend),
            backend: advBackend,
            semanticStateDirectory: stateDirectory(in: isolated, "advancer"))
        _ = try await advancer.continueWithRealInformation(
            database: database, handle: nil,
            advancementID: "hand-002", evaluatedAtUTC: "2026-10-09T00:01:00Z")
        let isLatest = try XCTUnwrap(latestExecutionState(advancer, database: database))
        XCTAssertEqual(isLatest["state_id"] as? String, "hand-002:runtime-applied")

        // Recovering the stale real-carrier ES must fail closed on the checkpoint
        // mismatch BEFORE any rebind or model work.
        let recoverBackend = MLXExecutionStateBackend()
        let recoverExecutor = RealCarrierHandoffExecutor(backend: recoverBackend)
        let stale = try ProductionRuntimeInformationIntegration(
            configuration: isolated.configuration, modelExecutor: recoverExecutor,
            backend: recoverBackend, semanticStateDirectory: staleStore)
        do {
            _ = try await stale.recoverExecutionState(database: database)
            XCTFail("stale ES checkpoint must be rejected against an advanced IS")
        } catch let error as ProductionRuntimeInformationError {
            guard case .settlementCheckpointMismatch(_, let field) = error else {
                return XCTFail("unexpected recovery error: \(error)")
            }
            XCTAssertEqual(field, "confirmation_state_id")
        }
        XCTAssertEqual(recoverExecutor.tokenizeSeedCallCount, 0)
        XCTAssertEqual(recoverExecutor.tokenizeTextCallCount, 0)
        XCTAssertEqual(recoverExecutor.continueExecutionCallCount, 0)
        // IS did not advance or get wrongly settled by the rejection.
        let after = try XCTUnwrap(latestExecutionState(stale, database: database))
        XCTAssertEqual(after["state_id"] as? String, "hand-002:runtime-applied")
    }
}
