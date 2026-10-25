import Foundation

// MARK: - Continuation carrier contract
//
// A settle-continuation has TWO distinct lineages, and conflating them is what
// made a warm request silently become a cold rebuild:
//
//   * semantic lineage  parent ES --IS settlement--> child ES   (verified)
//   * carrier lineage   source branch --fork--> target branch    (KV owner)
//
// The target is always the child ES id that admission minted. The SOURCE is
// whatever branch the runtime actually reads the parent's KV from, and it must
// be named explicitly — never "whatever logical_branch_id the client happened
// to keep sending".
//
// Source resolution has exactly one verified form and one unverified form:
//
//   .esLineage       the parent ES row was itself produced by a settle
//                    continuation, and this product executes such a request
//                    under the child ES id as its branch id. So that row's
//                    `id` IS the authoritative carrier name for its KV.
//   .clientAsserted  no verified relation exists (e.g. the anchor is a root
//                    row settled outside the fork path), so the client's
//                    logical branch is used. It is labelled as unverified in
//                    the response and can never satisfy `warm`.
//
// `warm` therefore has a strict meaning: a verified source must exist and the
// fork must succeed, otherwise the request is refused BEFORE generation.
// `cold` declares that no parent KV is expected. `auto` keeps the historical
// best-effort behaviour, but every deviation is reported, so "the client asked
// for reuse and got a rebuild" is a field, not an inference from a 200.

/// What a settle-continuation is allowed to do with the parent's KV.
public enum ContinuationCarrierMode: String, Sendable, Equatable {
    /// Verified source must exist and the fork must succeed, else refuse.
    case warm
    /// Parent KV is explicitly not expected: rebuild the context.
    case cold
    /// Best effort (default): verified source if available, otherwise the
    /// client-asserted branch, with the deviation published either way.
    case auto
}

/// How the branch fork that carries the parent's KV must relate to the
/// parent's STORAGE.
///
/// This is an argument of the fork operation, never a global mode: the caller
/// states what THIS request needs, that value travels to the runtime, and the
/// runtime either does it or refuses. A policy that were implied by something
/// else (a tuning flag, or "is this request warm") would make a strict fork and
/// an ordinary one indistinguishable both at the call site and on the wire.
public enum BranchForkPolicy: String, Sendable, Equatable, CaseIterable {
    /// Plain in-process fork (`ChatSession.fork()`). The child reads slices of
    /// the source's KV buffers: enough for two live branches that write on
    /// their own, not enough for a host that intends to RETIRE the source.
    case sharedCOW = "shared_cow"
    /// The child owns KV storage the source does not read. The copy is
    /// evaluated and verified BEFORE the child is registered, and a failure is
    /// a refusal — never a downgrade to `sharedCOW`.
    case detached = "detached"
}

/// What a `detached` fork PROVED, in the terms the gate checked.
///
/// Present only on a `detached` fork, and only after the runtime's
/// `forkDetached()` returned: these counters come from the verification itself,
/// not from a second, independent count. Nothing here is a durable claim — an
/// address means something only while both sessions are alive, and no field
/// says the source's last reference was released or that the OS reclaimed a
/// page. Those two stay unobserved on the release path.
public struct BranchForkStorageIsolation: Sendable, Equatable, Codable {
    /// KV cache leaves the copy covered (a `CacheList` counts as its children).
    public let leaves: Int
    /// Arrays compared: addresses differed and values matched for every one.
    public let arrays: Int
    /// Sum of the copies' byte counts (logical bytes, not allocator pages).
    public let bytes: Int
    public let valuesMatched: Int
    public let addressesSeparated: Int
    public let processedTokenCount: Int
    public let cacheKinds: [String]

    public init(
        leaves: Int,
        arrays: Int,
        bytes: Int,
        valuesMatched: Int,
        addressesSeparated: Int,
        processedTokenCount: Int,
        cacheKinds: [String]
    ) {
        self.leaves = leaves
        self.arrays = arrays
        self.bytes = bytes
        self.valuesMatched = valuesMatched
        self.addressesSeparated = addressesSeparated
        self.processedTokenCount = processedTokenCount
        self.cacheKinds = cacheKinds
    }

    /// Every compared array read different storage than its source.
    public var storageSeparated: Bool { arrays > 0 && addressesSeparated == arrays }
    /// Every compared array presented the same values as its source.
    public var valuesPreserved: Bool { arrays > 0 && valuesMatched == arrays }
    public var isVerified: Bool { storageSeparated && valuesPreserved }

    /// Published inside `continuation_carrier`, so "detached" is a measurement
    /// on the wire rather than an adjective in a log line.
    public var responsePayload: [String: Any] {
        [
            "leaves": leaves,
            "arrays": arrays,
            "bytes": bytes,
            "values_matched": valuesMatched,
            "addresses_separated": addressesSeparated,
            "storage_separated": storageSeparated,
            "values_preserved": valuesPreserved,
            "processed_token_count": processedTokenCount,
            "cache_kinds": cacheKinds,
        ]
    }
}

/// Where the chosen source branch name came from.
public enum ContinuationCarrierSourceOrigin: String, Sendable, Equatable {
    /// Derived from the verified parent ES row (its carrier name is its id).
    case esLineage = "es_lineage"
    /// The client's `logical_branch_id`. Recorded, never treated as verified.
    case clientAsserted = "client_asserted"
    /// No source at all (declared cold).
    case none = "none"
}

/// What actually happened to the carrier for THIS request.
public enum ContinuationCarrierResolution: String, Sendable, Equatable {
    /// Not a settle-continuation: no child ES, no carrier decision.
    case notApplicable = "not_applicable"
    /// A fork was performed and returned metadata.
    case forked = "forked"
    /// Declared cold: no fork was attempted.
    case cold = "cold"
    /// A fork was attempted and failed; generation continued on a rebuilt
    /// child branch (auto mode only — warm mode refuses instead).
    case degradedForkFailed = "degraded_fork_failed"
}

/// The per-request carrier decision, established BEFORE generation and
/// published with the settled response.
struct ContinuationCarrierDecision: Sendable, Equatable {
    let mode: ContinuationCarrierMode
    let resolution: ContinuationCarrierResolution
    /// The branch the runtime was asked to read the parent KV from.
    let sourceBranchID: String?
    let sourceOrigin: ContinuationCarrierSourceOrigin
    /// The branch this request executes under (the admitted child ES id).
    let targetBranchID: String
    /// The client's logical branch for this request (conversation lineage).
    let clientBranchID: String
    /// The source the runtime itself recorded on the fork metadata. This is the
    /// runtime's own answer to "where did the KV come from", not our intent.
    let runtimeForkSource: String?
    /// How many tokens the fork carried (0 when no fork).
    let forkTokenCount: Int?
    /// The storage policy this request asked for, and that the fork operation
    /// was actually given. Published so "detached" is never inferred.
    let forkPolicy: BranchForkPolicy
    /// What a `detached` fork proved. `nil` for `sharedCOW` (nothing is
    /// claimed) and for decisions taken before any fork (cold / notApplicable).
    let storageIsolation: BranchForkStorageIsolation?
    /// Stable, audit-safe degradation reason when the fork failed.
    let reason: String?

    var isVerifiedWarmReuse: Bool {
        resolution == .forked && sourceOrigin == .esLineage
    }

    /// The storage claim, independently of the lineage claim: a fork can be
    /// verified along ES lineage and still share its KV buffers.
    var hasVerifiedDetachedStorage: Bool {
        resolution == .forked && forkPolicy == .detached
            && (storageIsolation?.isVerified ?? false)
    }

    var clientBranchMismatch: Bool {
        sourceOrigin == .esLineage && sourceBranchID != clientBranchID
    }

    /// Published next to `continuation_settlement` in the completed response.
    var responsePayload: [String: Any] {
        var out: [String: Any] = [
            "mode": mode.rawValue,
            "resolution": resolution.rawValue,
            "source_origin": sourceOrigin.rawValue,
            "target_branch_id": targetBranchID,
            "client_branch_id": clientBranchID,
            "client_branch_mismatch": clientBranchMismatch,
            "verified_warm_reuse": isVerifiedWarmReuse,
            "source_branch_id": sourceBranchID ?? "-",
            "runtime_fork_source": runtimeForkSource ?? "-",
            "fork_token_count": forkTokenCount ?? 0,
            "fork_policy": forkPolicy.rawValue,
            "detached_storage_verified": hasVerifiedDetachedStorage,
        ]
        if let storageIsolation {
            out["storage_isolation"] = storageIsolation.responsePayload
        }
        if let reason { out["reason"] = reason }
        return out
    }

    /// One trace line. The mode/resolution pair is the thing a human must be
    /// able to read without cross-referencing a 200 response.
    var traceLine: String {
        "[CARRIER] continuation_carrier mode=\(mode.rawValue)"
            + " resolution=\(resolution.rawValue)"
            + " policy=\(forkPolicy.rawValue)"
            + " origin=\(sourceOrigin.rawValue)"
            + " source=\(sourceBranchID ?? "-")"
            + " target=\(targetBranchID)"
            + " client=\(clientBranchID)"
            + " mismatch=\(clientBranchMismatch)"
            + " forkTokens=\(forkTokenCount ?? 0)"
            + (storageIsolation.map {
                " detachedArrays=\($0.arrays) detachedBytes=\($0.bytes)"
                    + " separated=\($0.addressesSeparated)/\($0.arrays)"
            } ?? "")
            + (reason.map { " reason=\($0)" } ?? "")
    }
}

/// Typed refusals raised when a declared `warm` continuation cannot be
/// honoured. Both are pre-generation: nothing is generated, nothing settles.
enum ContinuationCarrierFailure: Error, Equatable {
    /// No verified carrier source exists for this anchor (the parent ES row was
    /// not produced by a settle continuation, so IS has no record of its KV).
    case sourceUnverified
    /// A verified source exists but the runtime could not fork it (e.g. the
    /// carrier was already released or the process restarted). The raw runtime
    /// error stays in the trace; the wire contract carries only the stable code.
    case forkFailed
    /// This request asked for detached KV storage and the runtime could not
    /// establish it: an unsupported cache kind, a copy that failed verification,
    /// or a source that is alive but holds no realized cache. Refused before
    /// generation — a detached request never receives a shared fork.
    case detachedUnavailable
    /// This request asked for detached KV storage but will not fork a branch
    /// (no settle continuation, or a declared `cold`). There is no parent KV to
    /// copy, so the guarantee cannot be met and the flag is not silently
    /// ignored.
    case detachedRequiresFork
}

extension ContinuationCarrierFailure {
    var terminal: ContinuationTerminal {
        switch self {
        case .sourceUnverified:
            return ContinuationTerminal(
                status: 422,
                message: "Continuation refused before generation: no verified carrier "
                    + "source for the parent execution state (warm continuation requires one)",
                errorKind: "CARRIER_SOURCE_UNVERIFIED",
                reasonCode: "source_unverified"
            )
        case .forkFailed:
            return ContinuationTerminal(
                status: 422,
                message: "Continuation refused before generation: the source carrier "
                    + "could not be forked",
                errorKind: "CARRIER_FORK_FAILED",
                reasonCode: "fork_failed"
            )
        case .detachedUnavailable:
            return ContinuationTerminal(
                status: 422,
                message: "Continuation refused before generation: detached KV storage "
                    + "could not be established (the source cache cannot be copied and "
                    + "verified), and this request does not accept a shared fork",
                errorKind: "CARRIER_DETACHED_UNAVAILABLE",
                reasonCode: "detached_unavailable"
            )
        case .detachedRequiresFork:
            return ContinuationTerminal(
                status: 422,
                message: "Continuation refused before generation: detached KV storage "
                    + "was required but this request will not fork a branch (no settle "
                    + "continuation, or a declared `cold`), so there is no copy to detach",
                errorKind: "CARRIER_DETACHED_REQUIRES_FORK",
                reasonCode: "detached_requires_fork"
            )
        }
    }
}
