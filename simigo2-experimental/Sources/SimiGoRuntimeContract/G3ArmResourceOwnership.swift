import Foundation

// G3 ARM RESOURCE OWNERSHIP — model each arm's actual runtime ownership so that
// isolation is decided against the UNDERLYING STORAGE, not a Swift label and not
// the identity of a thin wrapper object.
//
// Why the wrapper's identity is NOT enough (reviewer boundary): a resource *id*
// string is only a projection, and even a Swift `ObjectIdentifier` is only the
// identity of one wrapper instance. MLX's `MLXArray` is a `final class` holding a
// `mlx_array` handle that points at a `mlx::core::array`; two distinct `MLXArray`
// objects can be built over the SAME underlying storage (or over handles that
// alias the same buffer). Comparing their Swift object identity would report
// "distinct" and miss the alias. So isolation is keyed on a NORMALIZED STORAGE
// IDENTITY supplied by the native holder that actually owns the memory. When that
// holder cannot produce a canonical identity — because it cannot rule out
// aliasing at the layer it controls — the resource is `.indeterminate` and any
// MUTABLE use of it fails closed: we refuse the run rather than certify a leak we
// cannot see through.
//
// Sharing policy is unified in the types (issue: the old model both refused a
// shared `weights_buffer` instance AND described shared read-only weights as the
// allowed single-variable control — those are not the same claim, because equal
// content does not mean shared storage). Each resource now declares one of:
//   * `.sharedReadOnly`      — a store the holder has VERIFIED is not written for
//                              the whole run (immutable weight store, read-only
//                              tokenizer data). Sharing it across arms is allowed;
//                              it is the controlled variable, not a leak.
//   * `.armExclusiveMutable` — per-arm state that MUST be owned by exactly one
//                              arm (KV cache, mutable prefix state, runtime
//                              scratch). Two arms may not share a confirmed
//                              storage id, and an indeterminate id is refused.
//   * `.unverified`          — mutability could not be established → refuse.
//
// Lifecycle is live, not a snapshot: once the pre-generation isolation check
// passes the owner is SEALED against its peer, and any mutable resource the run
// allocates AFTER that point must be registered through `registerDuringGeneration`
// and is re-validated immediately, so a first-generation allocation cannot slip a
// shared buffer past a check that only saw the pre-run picture.
//
// This file is MLX-free and model-free so ownership + lifecycle are unit-testable
// without loading a model. The concrete adapter over real MLX objects lives in the
// SimiGo2Experimental layer and decides, per object, whether it can hand back a
// `.confirmed` canonical identity or must report `.indeterminate`.

// MARK: - Resource role

/// The role a runtime resource plays for a G3 arm. Roles are matched pairwise
/// across the two arms; some roles are definitionally mutable and may never be
/// downgraded to `.sharedReadOnly` to evade the isolation check.
public enum G3ResourceRole: String, CaseIterable, Hashable, Sendable {
    case modelWeights = "model_weights"     // verified immutable weight store
    case tokenizerData = "tokenizer_data"   // read-only tokenizer data
    case kvCache = "kv_cache"               // per-arm mutable attention cache
    case prefixCache = "prefix_cache"       // per-arm mutable prefix state
    case runtimeScratch = "runtime_scratch" // per-arm scratch / activation buffer
    case extraMutable = "extra_mutable"     // any other per-arm mutable instance
    case writeTarget = "write_target"       // the arm's write destination

    /// Roles that hold per-arm MUTABLE state and therefore may never be declared
    /// read-only to bypass isolation. Mislabelling one of these as shared read-only
    /// is itself a fail-closed violation.
    public var requiresArmExclusion: Bool {
        switch self {
        case .kvCache, .prefixCache, .runtimeScratch, .extraMutable, .writeTarget:
            return true
        case .modelWeights, .tokenizerData:
            return false
        }
    }
}

// MARK: - Storage identity

/// The normalized identity of a resource's UNDERLYING STORAGE, as attested by the
/// native holder that owns the memory — never the Swift wrapper's `ObjectIdentifier`
/// and never an arm label. Two wrappers that alias the same live storage MUST fold
/// to the same confirmed id so sharing is detected. When the holder cannot rule
/// aliasing out (e.g. it only sees a lazily-materialized `MLXArray` whose backing
/// buffer it does not own), it reports `.indeterminate` and any mutable use fails
/// closed.
public enum G3StorageIdentity: Hashable, Sendable {
    case confirmed(String)
    case indeterminate

    public var isConfirmed: Bool { if case .confirmed = self { return true }; return false }
    public var confirmedID: String? { if case .confirmed(let id) = self { return id }; return nil }
}

// MARK: - Access class

/// How a resource may be used across the two arms. This is the single place the
/// "what can be shared vs. what must be isolated" policy is expressed; the checker
/// and the lifecycle registry both read it, so the type and the logic cannot drift.
public enum G3ResourceAccess: String, Hashable, Sendable {
    case sharedReadOnly
    case armExclusiveMutable
    case unverified
}

// MARK: - Owned resource

/// A single owned resource instance. Isolation is decided from `storage` (a
/// normalized underlying id) plus `access` (the declared mutability policy) — the
/// optional `backing` object is retained only to keep the live allocation alive for
/// the run and is NEVER used to decide sharing.
public final class OwnedResource: @unchecked Sendable {
    public let role: G3ResourceRole
    /// The arm that owns this resource. Diagnostics only — never used to decide sharing.
    public let ownerLabel: String
    public let access: G3ResourceAccess
    public let storage: G3StorageIdentity
    /// The real runtime object, retained for lifetime only. Not an identity source.
    public let backing: AnyObject?

    public init(
        role: G3ResourceRole,
        ownerLabel: String,
        access: G3ResourceAccess,
        storage: G3StorageIdentity,
        backing: AnyObject? = nil
    ) {
        self.role = role
        self.ownerLabel = ownerLabel
        self.access = access
        self.storage = storage
        self.backing = backing
    }
}

// MARK: - Arm resource owner

/// The live authority that owns one arm's runtime resources and enforces isolation
/// across the arm's whole lifecycle. It starts `active`, is `sealed` against its
/// peer once the pre-generation check passes, and can refuse any post-seal mutable
/// allocation that would break isolation. `released` owners are never trusted.
public final class G3ArmResourceOwner: @unchecked Sendable {
    public enum LifecycleState: Hashable, Sendable { case active, sealed, released }

    public let armID: RuntimeArmID
    public let isolationUnitID: String

    // Read-only artifact identity: allowed (and for a single-variable run required)
    // to be equal across arms — that is shared content, not a mutable leak.
    public let modelContentSHA256: String
    public let tokenizerContentSHA256: String

    // Fixed, role-tagged owned resources. Weights/tokenizer are read-only and may
    // be shared; KV/prefix/scratch are per-arm mutable.
    public let modelWeights: OwnedResource
    public let tokenizerData: OwnedResource
    public let kvCache: OwnedResource
    public let prefixCache: OwnedResource
    public let runtimeScratch: OwnedResource
    public let mutableResources: [OwnedResource]   // extra per-arm mutable set

    public let writeRoot: String

    private(set) public var state: LifecycleState = .active

    // Seal-time state.
    private weak var peerRef: G3ArmResourceOwner?
    private let lock = NSLock()
    private var liveMutableConfirmedIDs: Set<String> = []
    private var dynamicResources: [OwnedResource] = []
    private var _allocationViolations: [String] = []

    public init(
        armID: RuntimeArmID,
        isolationUnitID: String,
        modelWeights: OwnedResource,
        modelContentSHA256: String,
        tokenizerData: OwnedResource,
        tokenizerContentSHA256: String,
        kvCache: OwnedResource,
        prefixCache: OwnedResource,
        runtimeScratch: OwnedResource,
        mutableResources: [OwnedResource],
        writeRoot: String
    ) {
        self.armID = armID
        self.isolationUnitID = isolationUnitID
        self.modelWeights = modelWeights
        self.modelContentSHA256 = modelContentSHA256
        self.tokenizerData = tokenizerData
        self.tokenizerContentSHA256 = tokenizerContentSHA256
        self.kvCache = kvCache
        self.prefixCache = prefixCache
        self.runtimeScratch = runtimeScratch
        self.mutableResources = mutableResources
        self.writeRoot = writeRoot
    }

    /// Every resource this arm currently owns, fixed plus any allocated after seal.
    public var allOwnedResources: [OwnedResource] {
        lock.lock(); defer { lock.unlock() }
        return [modelWeights, tokenizerData, kvCache, prefixCache, runtimeScratch]
            + mutableResources + dynamicResources
    }

    /// The confirmed underlying storage ids of this arm's MUTABLE resources. Only
    /// confirmed ids are comparable; a mutable resource with an indeterminate id is
    /// surfaced as a violation by `G3OwnershipIsolation` / the seal-time registry,
    /// not silently omitted.
    public var confirmedMutableIDs: Set<String> {
        lock.lock(); defer { lock.unlock() }
        var ids = liveMutableConfirmedIDs
        for resource in fixedMutableResourcesLocked() {
            if let id = resource.storage.confirmedID { ids.insert(id) }
        }
        for resource in dynamicResources {
            if let id = resource.storage.confirmedID { ids.insert(id) }
        }
        return ids
    }

    private func fixedMutableResourcesLocked() -> [OwnedResource] {
        // The roles that are definitionally mutable for this arm.
        [kvCache, prefixCache, runtimeScratch] + mutableResources
    }

    /// Violations recorded when a post-seal allocation was refused.
    public var allocationViolations: [String] {
        lock.lock(); defer { lock.unlock() }
        return _allocationViolations
    }

    /// Freeze the arm against its peer after the pre-generation isolation check has
    /// passed. From this point on, new mutable resources must go through
    /// `registerDuringGeneration`, which validates them against both arms' live
    /// mutable storage. A released owner cannot be sealed.
    public func seal(against peer: G3ArmResourceOwner) {
        lock.lock(); defer { lock.unlock() }
        guard state == .active else { return }
        peerRef = peer
        // Snapshot this arm's own confirmed mutable ids so later allocations are
        // checked against the already-owned set too.
        for resource in fixedMutableResourcesLocked() {
            if let id = resource.storage.confirmedID { liveMutableConfirmedIDs.insert(id) }
        }
        state = .sealed
    }

    /// Errors raised when a post-seal allocation is refused. The allocation is not
    /// admitted; a caller that ignores the throw cannot obtain the resource.
    public enum AllocationError: Error, Equatable {
        case notSealed(RuntimeArmID)
        case ownerReleased(RuntimeArmID)
        case violation(reason: String)
    }

    /// Register a resource that the run allocates AFTER sealing (e.g. a KV cache
    /// buffer materialized on the first forward). Isolation is re-checked live:
    ///   * `.unverified` mutability, or an exclusion role mislabelled read-only, is
    ///     refused.
    ///   * an `.armExclusiveMutable` resource with an `.indeterminate` storage id is
    ///     refused (we cannot prove it does not alias the peer).
    ///   * an `.armExclusiveMutable` resource whose confirmed id already appears in
    ///     either arm's live mutable set is refused as a shared allocation.
    /// A refused allocation is recorded in `allocationViolations` for the run report.
    @discardableResult
    public func registerDuringGeneration(_ resource: OwnedResource) throws -> OwnedResource {
        lock.lock(); defer { lock.unlock() }
        switch state {
        case .released: throw AllocationError.ownerReleased(armID)
        case .active:   throw AllocationError.notSealed(armID)
        case .sealed:   break
        }

        if let reason = violationReason(for: resource) {
            _allocationViolations.append(reason)
            throw AllocationError.violation(reason: reason)
        }

        // Admit the allocation and record its identity so later allocations (and the
        // peer) see it.
        dynamicResources.append(resource)
        if resource.access == .armExclusiveMutable, let id = resource.storage.confirmedID {
            liveMutableConfirmedIDs.insert(id)
        }
        return resource
    }

    /// The live isolation rule for a single candidate resource, shared by the
    /// snapshot check and the post-seal registry so the two cannot drift.
    fileprivate func violationReason(for resource: OwnedResource) -> String? {
        switch resource.access {
        case .unverified:
            return "indeterminate_mutability(\(resource.role.rawValue))"
        case .sharedReadOnly:
            if resource.role.requiresArmExclusion {
                return "role_requires_isolation(\(resource.role.rawValue))"
            }
            return nil   // verified read-only store may be shared; identity is irrelevant
        case .armExclusiveMutable:
            guard let id = resource.storage.confirmedID else {
                return "indeterminate_storage_identity(\(resource.role.rawValue))"
            }
            // Conflict with this arm's own set or the peer's live set means the two
            // arms (or two roles within one arm) alias the same mutable storage.
            if liveMutableConfirmedIDs.contains(id) {
                return "shared_mutable_storage(\(resource.role.rawValue))"
            }
            if let peer = peerRef, peer.confirmedMutableIDsSnapshotContains(id) {
                return "shared_mutable_storage(\(resource.role.rawValue))"
            }
            return nil
        }
    }

    fileprivate func confirmedMutableIDsSnapshotContains(_ id: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if liveMutableConfirmedIDs.contains(id) { return true }
        for resource in fixedMutableResourcesLocked() where resource.access == .armExclusiveMutable {
            if resource.storage.confirmedID == id { return true }
        }
        for resource in dynamicResources where resource.storage.confirmedID == id {
            return true
        }
        return false
    }

    /// End the owner's lifecycle. A released owner fails every later check so a
    /// stale or reused owner can never authorize generation.
    public func release() { lock.lock(); state = .released; lock.unlock() }

    /// The registration authority handed to a G3 generation path. Returns nil
    /// unless this owner is currently `.sealed`, i.e. unless the pre-generation
    /// isolation precondition actually passed. An active owner has not been
    /// checked yet and a released owner is dead — neither may accept a
    /// during-generation allocation, so the executor simply receives no channel
    /// and any later attempt to reach `registerDuringGeneration` fails closed.
    public func makeRegistrar() -> G3AllocationRegistrar? {
        lock.lock(); defer { lock.unlock() }
        guard state == .sealed else { return nil }
        return G3AllocationRegistrar(owner: self)
    }
}

// MARK: - During-generation allocation registrar

/// The channel through which a resource the run materializes AFTER the
/// pre-generation isolation check (a KV cache block, an advanced prefix store,
/// a runtime scratch buffer) reaches the sealed ``G3ArmResourceOwner``.
///
/// This exists so ownership registration is not a one-shot pre-run snapshot:
/// the dual-arm runner hands a registrar to each arm's gated continuation, and
/// every new allocation the executor makes during first generation must be
/// re-validated live against BOTH arms before it is admitted. A registrar only
/// exists for a sealed owner (see `G3ArmResourceOwner.makeRegistrar`), so a
/// path that skipped the isolation precondition cannot register anything.
///
/// The registrar adds no policy of its own — it forwards to
/// `registerDuringGeneration`, which is the single place the live isolation
/// rule is expressed, so the snapshot check and the during-generation registry
/// cannot drift apart.
public final class G3AllocationRegistrar: @unchecked Sendable {
    /// Errors surfaced to a generation path whose allocation was refused. The
    /// underlying owner rule is carried verbatim so a caller cannot interpret a
    /// refusal as something other than a fail-closed isolation violation.
    public enum RegistrationError: Error, Equatable {
        case notSealed(RuntimeArmID)
        case ownerReleased(RuntimeArmID)
        case violation(reason: String)
    }

    private let owner: G3ArmResourceOwner

    init(owner: G3ArmResourceOwner) { self.owner = owner }

    public var armID: RuntimeArmID { owner.armID }

    /// Register one resource the run allocated during generation. Throws when the
    /// allocation would break isolation; a refused resource is never admitted and
    /// is recorded in the owner's `allocationViolations` for the run report.
    @discardableResult
    public func register(_ resource: OwnedResource) throws -> OwnedResource {
        do {
            return try owner.registerDuringGeneration(resource)
        } catch G3ArmResourceOwner.AllocationError.notSealed(let arm) {
            throw RegistrationError.notSealed(arm)
        } catch G3ArmResourceOwner.AllocationError.ownerReleased(let arm) {
            throw RegistrationError.ownerReleased(arm)
        } catch G3ArmResourceOwner.AllocationError.violation(let reason) {
            throw RegistrationError.violation(reason: reason)
        }
    }

    /// Register a batch of resources from one allocation (e.g. a KV cache mapped
    /// to an aggregate entry plus its per-buffer entries). Each entry is validated
    /// and admitted in order and the FIRST refusal aborts the batch, so a caller
    /// cannot treat a partially-accepted set as a fully-isolated one — it must
    /// handle the throw and stop. Note the already-admitted prefix stays in the
    /// live set: registering more can only make later checks STRICTER, never
    /// looser, so a mid-batch refusal still fails the run closed via the recorded
    /// violation rather than silently leaving a hole.
    @discardableResult
    public func registerAll(_ resources: [OwnedResource]) throws -> [OwnedResource] {
        for resource in resources { try register(resource) }
        return resources
    }
}

// MARK: - Isolation decision

public struct G3OwnershipIsolationReport: Codable, Hashable, Sendable {
    public let passed: Bool
    public let failedReasons: [String]
    /// Diagnostic only: identity comparison never relied on these labels.
    public let arms: [String]

    public init(passed: Bool, failedReasons: [String], arms: [String]) {
        self.passed = passed
        self.failedReasons = failedReasons
        self.arms = arms
    }
}

public enum G3OwnershipIsolation {
    /// Decide isolation from NORMALIZED UNDERLYING STORAGE IDENTITY + declared
    /// access policy + lifecycle — never from a Swift wrapper identity or a label.
    ///
    /// Fails closed on: same owner instance, same arm id, unverified mutability, an
    /// exclusion role mislabelled read-only, a mutable resource with an
    /// indeterminate storage id, any confirmed mutable storage id shared across the
    /// two arms, non-disjoint write roots, or a non-active/sealed owner.
    /// Equal READ-ONLY model/tokenizer storage or content is allowed (shared
    /// immutable artifact — the single-variable control, not a leak).
    public static func check(
        _ a: G3ArmResourceOwner,
        _ b: G3ArmResourceOwner
    ) -> G3OwnershipIsolationReport {
        var reasons: [String] = []

        if a === b { reasons.append("same_owner_instance") }
        if a.armID == b.armID { reasons.append("same_arm_id") }

        // Per-resource policy: unverified mutability, exclusion roles downgraded to
        // read-only, and mutable resources with no confirmable storage identity.
        for resource in a.allOwnedResources {
            if let reason = a.violationReason(for: resource) { reasons.append(reason) }
        }
        for resource in b.allOwnedResources {
            if let reason = b.violationReason(for: resource) { reasons.append(reason) }
        }

        // Cross-arm aliasing over CONFIRMED mutable ids: no underlying mutable store
        // may appear in both arms' owned sets. (Indeterminate stores already failed
        // above; sharing read-only stores is intentionally not checked here.)
        let sharedMutable = a.confirmedMutableIDs.intersection(b.confirmedMutableIDs)
        if !sharedMutable.isEmpty {
            reasons.append("shared_mutable_storage(count=\(sharedMutable.count))")
        }

        // Write roots must be genuinely disjoint (equal/nested roots refused).
        if !RuntimeIsolationGate.pathsDisjoint([a.writeRoot, b.writeRoot]) {
            reasons.append("runtime_write_roots_not_disjoint")
        }

        // Both owners must be live (not released) at decision time.
        if a.state == .released { reasons.append("owner_not_active(\(a.armID.rawValue))") }
        if b.state == .released { reasons.append("owner_not_active(\(b.armID.rawValue))") }

        return G3OwnershipIsolationReport(
            passed: reasons.isEmpty,
            failedReasons: reasons,
            arms: [a.armID.rawValue, b.armID.rawValue])
    }
}
