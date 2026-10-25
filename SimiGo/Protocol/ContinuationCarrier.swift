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
    /// Stable, audit-safe degradation reason when the fork failed.
    let reason: String?

    var isVerifiedWarmReuse: Bool {
        resolution == .forked && sourceOrigin == .esLineage
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
        ]
        if let reason { out["reason"] = reason }
        return out
    }

    /// One trace line. The mode/resolution pair is the thing a human must be
    /// able to read without cross-referencing a 200 response.
    var traceLine: String {
        "[CARRIER] continuation_carrier mode=\(mode.rawValue)"
            + " resolution=\(resolution.rawValue)"
            + " origin=\(sourceOrigin.rawValue)"
            + " source=\(sourceBranchID ?? "-")"
            + " target=\(targetBranchID)"
            + " client=\(clientBranchID)"
            + " mismatch=\(clientBranchMismatch)"
            + " forkTokens=\(forkTokenCount ?? 0)"
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
        }
    }
}
