import Foundation
import CryptoKit
import MLX
import MLXNN
import MLXLMCommon
import SimiGoRuntimeContract

// REAL RESOURCE-OBSERVATION ADAPTER (MLX layer) — the bridge that lets the
// native G3 gate read genuine runtime identities from the objects that actually
// own the model, tokenizer and caches.
//
// Design rule from the gate contract: an observation must be *pulled from the
// live runtime*, not assembled from configuration or caller-declared booleans.
// This adapter therefore takes the real `ModelContext` and the real per-arm
// cache/buffer objects and derives instance identities from their object
// identity, the worker pid from the process, and content digests by hashing the
// artifacts the arm actually loaded. Generation state is read through closures
// bound to the executor's live counters, so no caller can inject a convenient
// `true`.
//
// TRUST STATUS: this adapter is NOT registered in
// ``RuntimeProviderTrustPolicy``. The registry is intentionally empty because a
// fully validated real emitter (streaming weight digests, true cache-namespace
// capture, and gate placement wired into the actual first-generation call site)
// is deferred to the authorization phase. Consequently a gate driven by this
// adapter still fails closed today — which is the correct behavior. It must
// never be used to write mock or synthetic results as real isolation evidence,
// and it must not be registered as trusted while the real emitter is unfinished.
//
// UNDERLYING-STORAGE IDENTITY: resources are now keyed on the genuine MLX
// storage identity read from the native runtime (`MLXArray.mlxStorageIdentity`,
// backed by `mlx_array_get_storage_identity` exposing the shared `Data`
// descriptor and the allocator buffer handle), NOT on the array's `id()` (which
// names the per-array `ArrayDesc`, not the shared data) and NOT on a Swift
// `ObjectIdentifier`. A `.sharedReadOnly` label is never taken on faith: a
// read-only store is only admitted when every one of its buffers is materialized
// and observable, and any mutable resource whose allocation cannot be confirmed
// is `.indeterminate`, which fails the isolation check closed.

/// Reads genuine per-arm runtime identities for the native G3 isolation gate.
///
/// The held handles are the arm's own MLX objects, sampled synchronously at gate
/// time; like the executor they are `@unchecked Sendable` because MLX object
/// types are not themselves declared Sendable.
public final class G3MLXRuntimeResourceProbe: RuntimeResourceProbe, @unchecked Sendable {
    private let armLabel: String
    private let context: ModelContext
    private let kvCache: AnyObject
    private let prefixCache: AnyObject
    private let runtimeBuffer: AnyObject
    private let weightsBuffer: AnyObject
    private let mutableResources: [AnyObject]
    private let writeRootURL: URL
    private let modelArtifactURL: URL
    private let tokenizerArtifactURL: URL
    private let generationInvocations: @Sendable () -> Int
    private let initializedBeforeGate: @Sendable () -> Bool
    private let isolationUnitIDValue: String
    /// Extension point for MUTABLE holders that are not plain `MLXArray` objects
    /// (opaque KV caches, dequant buffers). The real emitter folds such a holder
    /// down to a canonical allocator-level id only when it can rule out aliasing
    /// at the layer that owns the memory; returning nil reports `.indeterminate`,
    /// which fails any mutable isolation claim closed. Plain `MLXArray` resources
    /// do NOT use this — their identity is read from the native runtime via
    /// `MLXArray.mlxStorageIdentity`. See `makeResourceOwner`.
    private let opaqueMutableIdentity: @Sendable (AnyObject) -> G3StorageIdentity?

    /// The seam that supplies the buffers the run materialized DURING generation,
    /// role-tagged. Empty by default: the probe never invents an allocation to
    /// register, so an unwired probe reports "no post-check allocation observed"
    /// rather than a false pass. The authorization-phase emitter installs a source
    /// that returns the actual KV blocks / advanced prefix state / scratch buffers
    /// the forward loop allocated for this arm, and each is then mapped through the
    /// genuine native identity read and re-validated by the sealed owner.
    public var duringGenerationAllocationSource:
        @Sendable () -> [(role: G3ResourceRole, object: AnyObject)] = { [] }

    public init(
        armLabel: String,
        context: ModelContext,
        kvCache: AnyObject,
        prefixCache: AnyObject,
        runtimeBuffer: AnyObject,
        weightsBuffer: AnyObject,
        mutableResources: [AnyObject],
        writeRootURL: URL,
        modelArtifactURL: URL,
        tokenizerArtifactURL: URL,
        isolationUnitID: String,
        generationInvocations: @escaping @Sendable () -> Int,
        initializedBeforeGate: @escaping @Sendable () -> Bool,
        opaqueMutableIdentity: @escaping @Sendable (AnyObject) -> G3StorageIdentity? = { _ in nil }
    ) {
        self.armLabel = armLabel
        self.context = context
        self.kvCache = kvCache
        self.prefixCache = prefixCache
        self.runtimeBuffer = runtimeBuffer
        self.weightsBuffer = weightsBuffer
        self.mutableResources = mutableResources
        self.writeRootURL = writeRootURL
        self.modelArtifactURL = modelArtifactURL
        self.tokenizerArtifactURL = tokenizerArtifactURL
        self.isolationUnitIDValue = isolationUnitID
        self.generationInvocations = generationInvocations
        self.initializedBeforeGate = initializedBeforeGate
        self.opaqueMutableIdentity = opaqueMutableIdentity
    }

    // MARK: Identity helpers (real object identity, not config)

    private func instanceID(_ tag: String, _ object: AnyObject) -> String {
        "\(armLabel):\(tag):0x\(hex(ObjectIdentifier(object).hashValue))"
    }

    private func hex(_ value: Int) -> String {
        String(value.magnitude, radix: 16)
    }

    private func sha256(of url: URL) -> String {
        // Real emitter streams large weight files; this bridge reads the exact
        // artifact bytes the arm loaded so the digest reflects genuine content.
        guard let data = try? Data(contentsOf: url) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Underlying-storage identity (native runtime, not wrapper id)

    /// Fold ONE `MLXArray` to its underlying storage identity via the native
    /// accessor. A materialized array gives a confirmed id keyed on BOTH the
    /// shared `Data` descriptor and the allocator buffer handle, so two wrappers
    /// or views over one allocation collapse to the same id (aliasing detected),
    /// while independent allocations stay distinct. An unmaterialized array
    /// exposes no storage, so it is `.indeterminate` — never a false `distinct`.
    private static func identity(of array: MLXArray) -> G3StorageIdentity {
        let si = array.mlxStorageIdentity
        guard si.materialized else { return .indeterminate }
        return .confirmed("mlx:d=\(si.dataDescriptor):b=\(si.bufferHandle)")
    }

    /// Combine per-buffer identities into a single confirmed id ONLY when the set
    /// is non-empty and EVERY buffer is materialized. A single unobservable
    /// buffer makes the whole aggregate `.indeterminate`; a missing evidence axis
    /// is never grounds to declare resources isolated.
    private static func aggregate(_ identities: [MLXArrayStorageIdentity]) -> G3StorageIdentity {
        guard !identities.isEmpty, identities.allSatisfy({ $0.materialized }) else {
            return .indeterminate
        }
        let keys = identities
            .map { "d=\($0.dataDescriptor):b=\($0.bufferHandle)" }
            .sorted()
            .joined(separator: "|")
        return .confirmed("agg:" + SHA256.hash(data: Data(keys.utf8))
            .map { String(format: "%02x", $0) }.joined())
    }

    /// Identity for a MUTABLE runtime resource. Plain arrays read their genuine
    /// storage id from the native runtime; opaque holders go through the
    /// emitter-provided fold; anything unresolved is `.indeterminate` so mutable
    /// isolation fails closed rather than trusting a wrapper identity.
    private static func mutableIdentity(
        of object: AnyObject,
        opaque: @escaping @Sendable (AnyObject) -> G3StorageIdentity?
    ) -> G3StorageIdentity {
        if let array = object as? MLXArray { return identity(of: array) }
        if let arrays = object as? [MLXArray] {
            return aggregate(arrays.map { $0.mlxStorageIdentity })
        }
        return opaque(object) ?? .indeterminate
    }

    private func mutableIdentity(of object: AnyObject) -> G3StorageIdentity {
        Self.mutableIdentity(of: object, opaque: opaqueMutableIdentity)
    }

    /// One owned-resource entry per underlying buffer. A resource held as a
    /// collection of arrays is enumerated so EVERY buffer's storage id enters the
    /// arm's mutable set — recognizing only the container object could not prove
    /// all of its buffers were compared. The leading entry summarizes the whole
    /// buffer set; the trailing entries give per-buffer isolation granularity so
    /// even a partial cross-arm alias is caught.
    ///
    /// This is a static function on purpose: the pre-generation snapshot AND every
    /// during-generation allocation are mapped by the SAME code, so a post-check
    /// buffer can never be graded on a weaker identity rule than the snapshot was.
    private static func ownedMutable(
        _ role: G3ResourceRole,
        _ object: AnyObject,
        armLabel: String,
        opaque: @escaping @Sendable (AnyObject) -> G3StorageIdentity?
    ) -> [OwnedResource] {
        if let arrays = object as? [MLXArray] {
            let head = OwnedResource(
                role: role, ownerLabel: armLabel, access: .armExclusiveMutable,
                storage: aggregate(arrays.map { $0.mlxStorageIdentity }), backing: object)
            let perBuffer = arrays.map {
                OwnedResource(
                    role: role, ownerLabel: armLabel, access: .armExclusiveMutable,
                    storage: identity(of: $0), backing: $0)
            }
            return [head] + perBuffer
        }
        return [OwnedResource(
            role: role, ownerLabel: armLabel, access: .armExclusiveMutable,
            storage: mutableIdentity(of: object, opaque: opaque), backing: object)]
    }

    /// Instance view of the shared mapping: the arm label and the emitter's opaque
    /// fold come from this probe, the rule itself comes from the static function.
    private func ownedMutable(_ role: G3ResourceRole, _ object: AnyObject) -> [OwnedResource] {
        Self.ownedMutable(role, object, armLabel: armLabel, opaque: opaqueMutableIdentity)
    }

    // MARK: RuntimeResourceProbe

    public func workerPID() -> Int { Int(ProcessInfo.processInfo.processIdentifier) }
    public func isolationUnitID() -> String { isolationUnitIDValue }
    public func modelInstanceID() -> String { instanceID("model", context.model as AnyObject) }
    public func modelContentSHA256() -> String { sha256(of: modelArtifactURL) }
    public func tokenizerInstanceID() -> String { instanceID("tokenizer", context.tokenizer as AnyObject) }
    public func tokenizerContentSHA256() -> String { sha256(of: tokenizerArtifactURL) }
    public func weightsBufferInstanceID() -> String { instanceID("weights", weightsBuffer) }
    public func kvCacheInstanceID() -> String { instanceID("kv", kvCache) }
    public func prefixCacheInstanceID() -> String { instanceID("prefix", prefixCache) }
    public func runtimeBufferInstanceID() -> String { instanceID("rbuf", runtimeBuffer) }
    public func kvCacheNamespace() -> String { "kv://\(armLabel)/\(hex(ObjectIdentifier(kvCache).hashValue))" }
    public func prefixCacheNamespace() -> String { "prefix://\(armLabel)/\(hex(ObjectIdentifier(prefixCache).hashValue))" }
    public func runtimeWriteRoot() -> String { writeRootURL.standardizedFileURL.path }
    public func generationInvocationsBeforeGate() -> Int { generationInvocations() }
    public func runtimeInitializedBeforeFirstGeneration() -> Bool { initializedBeforeGate() }
    public func mutableResourceIDs() -> [String] {
        mutableResources.map { instanceID("mutable", $0) }
    }

    /// Build this arm's real resource OWNERSHIP by enumerating every underlying
    /// buffer and reading its genuine storage identity from the native runtime.
    ///
    /// WEIGHT STORE: `context.model` is not treated as an opaque object. Its
    /// parameter tree is flattened and EVERY weight array is sampled; the store is
    /// admitted as `.sharedReadOnly` (shareable across arms — the single-variable
    /// control) only when all buffers are materialized and their allocation
    /// identity is observable. If any weight buffer cannot be confirmed the store
    /// becomes `.unverified`, because a `.sharedReadOnly` LABEL is never taken on
    /// faith: an unobservable allocation could alias a per-arm mutable buffer and
    /// we refuse to certify immutability we cannot see. The tokenizer data is a
    /// genuinely non-MLX read-only store, so it stays read-only with an
    /// irrelevant (indeterminate) identity.
    ///
    /// MUTABLE STATE: KV cache, mutable prefix state, runtime scratch, the
    /// weights/dequant buffer and any extra mutable object are declared
    /// `.armExclusiveMutable` and keyed on their confirmed underlying-storage id
    /// (each array in a collection enumerated separately). A resource whose
    /// allocation cannot be confirmed is `.indeterminate`, which the isolation
    /// check fails closed — the Swift `ObjectIdentifier` of a wrapper never proves
    /// its backing `mlx::core::array` is unaliased.
    public func makeResourceOwner(armID: RuntimeArmID) -> G3ArmResourceOwner {
        // (1) Enumerate EVERY weight buffer in the model, not just the model object.
        let weightIdentities = context.model.parameters().flattened().map { $0.1.mlxStorageIdentity }
        let weightStorage = Self.aggregate(weightIdentities)
        // Only a fully observable weight store may be trusted as shared read-only.
        let weightAccess: G3ResourceAccess = weightStorage.isConfirmed ? .sharedReadOnly : .unverified
        let modelWeights = OwnedResource(
            role: .modelWeights, ownerLabel: armLabel, access: weightAccess,
            storage: weightStorage, backing: context.model as AnyObject)

        // (2) Tokenizer data is a read-only non-MLX store; identity is irrelevant
        // and never enters the mutable set.
        let tokenizerData = OwnedResource(
            role: .tokenizerData, ownerLabel: armLabel, access: .sharedReadOnly,
            storage: .indeterminate, backing: context.tokenizer as AnyObject)

        // (3) Mutable resources, each enumerated to per-buffer granularity.
        let kv = ownedMutable(.kvCache, kvCache)
        let prefix = ownedMutable(.prefixCache, prefixCache)
        let scratch = ownedMutable(.runtimeScratch, runtimeBuffer)
        // The per-arm weights/dequant buffer is mutable scratch, not the read-only
        // weight store, so it is arm-exclusive too; then any extra mutable objects.
        var listMutable = Array(kv.dropFirst()) + Array(prefix.dropFirst()) + Array(scratch.dropFirst())
        listMutable.append(contentsOf: ownedMutable(.extraMutable, weightsBuffer))
        for object in mutableResources {
            listMutable.append(contentsOf: ownedMutable(.extraMutable, object))
        }

        return G3ArmResourceOwner(
            armID: armID,
            isolationUnitID: isolationUnitIDValue,
            modelWeights: modelWeights,
            modelContentSHA256: modelContentSHA256(),
            tokenizerData: tokenizerData,
            tokenizerContentSHA256: tokenizerContentSHA256(),
            kvCache: kv[0],
            prefixCache: prefix[0],
            runtimeScratch: scratch[0],
            mutableResources: listMutable,
            writeRoot: runtimeWriteRoot())
    }

    // MARK: During-generation registration

    /// Map an object the run materialized AFTER the pre-generation check (a KV
    /// block, an advanced prefix tensor, a runtime scratch buffer) to owned
    /// resources, keyed on its GENUINE underlying-storage identity — the same
    /// native read the snapshot uses, so a post-check allocation is judged by the
    /// exact rule the seal used and cannot be graded on a weaker one. A collection
    /// of arrays is expanded per buffer, and an unobservable allocation stays
    /// `.indeterminate` so the mutable claim fails closed.
    ///
    /// The static form is the shared implementation for BOTH the wired probe and
    /// native tests that exercise registration against real `MLXArray` objects
    /// without loading a model — there is no separate "test mapping" that could
    /// drift from the production one.
    public static func mapAllocation(
        _ object: AnyObject,
        role: G3ResourceRole,
        armLabel: String,
        opaqueMutableIdentity: @escaping @Sendable (AnyObject) -> G3StorageIdentity? = { _ in nil }
    ) -> [OwnedResource] {
        ownedMutable(role, object, armLabel: armLabel, opaque: opaqueMutableIdentity)
    }

    /// Array-form entry point. A KV/prefix cache is normally held as a
    /// LAYER-INDEXED collection, and a Swift array is not an `AnyObject` instance,
    /// so the collection path needs its own signature rather than a cast. Mapping
    /// still runs through the same rule: one aggregate entry for the whole set plus
    /// one per buffer, so no block can hide inside a container that was itself
    /// judged "distinct".
    public static func mapAllocation(
        _ arrays: [MLXArray],
        role: G3ResourceRole,
        armLabel: String
    ) -> [OwnedResource] {
        ownedMutable(role, arrays as AnyObject, armLabel: armLabel, opaque: { _ in nil })
    }

    public func mapAllocation(_ object: AnyObject, role: G3ResourceRole) -> [OwnedResource] {
        ownedMutable(role, object)
    }

    /// Collection form of the instance mapping, for a cache held as per-layer
    /// arrays rather than a single buffer.
    public func mapAllocation(_ arrays: [MLXArray], role: G3ResourceRole) -> [OwnedResource] {
        ownedMutable(role, arrays as AnyObject)
    }

    /// Register one during-generation allocation with a sealed arm through the
    /// registrar. Throws ``G3AllocationRegistrar/RegistrationError/violation(reason:)``
    /// when the allocation aliases the peer's mutable storage or has no confirmable
    /// identity; the refusal is recorded by the owner so the run report surfaces it.
    /// This is the concrete call the executor's `duringGenerationRegistration` hook
    /// makes for each buffer the forward loop allocates.
    public func register(
        _ object: AnyObject, role: G3ResourceRole, through registrar: G3AllocationRegistrar
    ) throws {
        for resource in mapAllocation(object, role: role) {
            try registrar.register(resource)
        }
    }

    public func register(
        _ arrays: [MLXArray], role: G3ResourceRole, through registrar: G3AllocationRegistrar
    ) throws {
        for resource in mapAllocation(arrays, role: role) {
            try registrar.register(resource)
        }
    }

    /// Bind this probe to an arm executor's during-generation registration hook so
    /// allocations the forward loop materializes are mapped through this probe's
    /// genuine identity read and registered with the sealed owner. The executor
    /// keeps no policy of its own — it calls back into the probe that actually
    /// observed the arm's resources, so registration is graded on exactly the rule
    /// the pre-generation snapshot used.
    public func bind(to executor: MLXPrefixRecomputeExecutor) {
        executor.duringGenerationRegistration = { [weak self, weak executor] _, registrar in
            guard let self else { return }
            // Route every during-generation allocation through the arm's
            // G3KVAllocationGateway, so registration uses ONE admission gate built
            // on the SAME native identity read as the snapshot. When a per-arm
            // cache session is installed, REUSE its gateway: the write-boundary
            // observer already registered the KV buffers on that gateway, and a
            // second gateway would either double-admit them (refused as shared
            // within the arm) or grade them against a different registered set.
            let gateway = executor?.g3CacheGateway ?? G3KVAllocationGateway(
                registrar: registrar, armLabel: self.armLabel,
                opaqueMutableIdentity: self.opaqueMutableIdentity)
            // Which buffers were materialized during this generation comes from
            // `duringGenerationAllocationSource`. It is empty on the recompute path
            // (cache: nil allocates no persistent KV), so an unwired probe admits
            // nothing and the gateway reports `observedAnyAllocation == false` —
            // recorded as "KV not observed", NEVER as a verified-isolation pass.
            for allocation in self.duringGenerationAllocationSource() {
                if let arrays = allocation.object as? [MLXArray] {
                    _ = try gateway.admit(arrays, role: allocation.role)
                } else {
                    _ = try gateway.admitOpaque(allocation.object, role: allocation.role)
                }
            }
        }
    }
}

// MARK: - Production G3 arm wiring (compile-proven; needs a loaded context to run)

extension MLXPrefixRecomputeExecutor {
    /// Assemble one arm of a G3 dual-arm run. The owner is derived from the
    /// arm's own live probe (its real resources), and the executor is routed by
    /// ``G3DualArmRunner`` ONLY through ``G3ExecutionDispatch``'s `.g3` branch —
    /// the real G3 execution path, not the preflight example. Constructing the
    /// backing `G3MLXRuntimeResourceProbe` requires a loaded `ModelContext`, which
    /// is an authorization-phase action; this wiring is compiled here so the
    /// production branch is concrete, while control flow stays model-free-testable
    /// at the contract layer.
    public func g3ArmExecution(
        armID: RuntimeArmID,
        probe: G3MLXRuntimeResourceProbe,
        provider: any RuntimeAttestationProvider,
        request: AttestationRequest,
        state: ExecutionStateHandle,
        nextInputTokens: [Int],
        maxTokens: Int
    ) -> G3ArmExecution<MLXPrefixRecomputeExecutor> {
        // Wiring the arm to its probe installs the live registration channel, so
        // a G3 arm built through this entry can never be a snapshot-only run.
        probe.bind(to: self)
        return G3ArmExecution(
            owner: probe.makeResourceOwner(armID: armID),
            executor: self,
            provider: provider,
            request: request,
            state: state,
            nextInputTokens: nextInputTokens,
            maxTokens: maxTokens)
    }
}
