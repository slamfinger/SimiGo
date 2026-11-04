import Foundation
import SimiGoRuntimeContract

// MARK: - Continuation response contract v0.1
//
// Machine-readable terminals for the ES/IS continuation edge, per the owner's
// ruling: the two refusal classes must never masquerade as each other.
//
// * admission authority not wired            -> 503 ADMISSION_AUTHORITY_UNAVAILABLE
// * explicit admission refusal                 -> 422 INPUT_ADMISSION_REFUSED
//   with stable reason_code {invalid_anchor, is_refusal}
// * unknown admission-stage error              -> 500 ADMISSION_ENGINE_ERROR
//   (never falls back to 422)
// * settlement authority not wired, or asked
//   without a continuation anchor              -> fail closed BEFORE generation
//   (503 SETTLEMENT_AUTHORITY_UNAVAILABLE / 400 SETTLEMENT_WITHOUT_ANCHOR)
// * post-generation native contract rejection  -> 422 NATIVE_RESULT_CONTRACT_REJECTED
// * settlement infrastructure / unclassified   -> 500 SETTLEMENT_ENGINE_ERROR
// * success                                    -> 200 + continuation_settlement
//   payload {settlement_id, identity_binding_published}
//
// The kind travels in structured JSON fields (`error.error_kind` /
// `error.reason_code`). Clients must never infer a refusal cause from prose.

/// One structured continuation error: status + stable kind + optional stable
/// reason code. `message` is audit-safe prose kept for humans only.
struct ContinuationTerminal: Equatable {
    let status: Int
    let message: String
    let errorKind: String
    let reasonCode: String?
}

extension ContinuationTerminal {
    static let settleWithoutAnchor = ContinuationTerminal(
        status: 400,
        message: "continuation_settle requires previous_es_state_id",
        errorKind: "SETTLEMENT_WITHOUT_ANCHOR",
        reasonCode: nil
    )

    static let admissionAuthorityUnavailable = ContinuationTerminal(
        status: 503,
        message: "Continuation refused before generation: admission authority unavailable",
        errorKind: "ADMISSION_AUTHORITY_UNAVAILABLE",
        reasonCode: nil
    )

    static let settlementAuthorityUnavailable = ContinuationTerminal(
        status: 503,
        message: "Continuation refused before generation: settlement authority unavailable",
        errorKind: "SETTLEMENT_AUTHORITY_UNAVAILABLE",
        reasonCode: nil
    )

    static let settlementUnsupportedOnStream = ContinuationTerminal(
        status: 501,
        message: "continuation_settle is not supported on the streaming Responses path",
        errorKind: "SETTLEMENT_UNSUPPORTED_ON_STREAM",
        reasonCode: nil
    )

    static let admissionEngineError = ContinuationTerminal(
        status: 500,
        message: "Continuation refused before generation: admission engine error",
        errorKind: "ADMISSION_ENGINE_ERROR",
        reasonCode: nil
    )

    static let settlementEngineError = ContinuationTerminal(
        status: 500,
        message: "Continuation settlement failed: settlement engine error",
        errorKind: "SETTLEMENT_ENGINE_ERROR",
        reasonCode: nil
    )
}

extension ContinuationAdmissionFailure {
    /// Stable reason codes for the v0.1 contract.
    var terminal: ContinuationTerminal {
        switch self {
        case .invalidAnchor:
            return ContinuationTerminal(
                status: 422,
                message: "Continuation refused before generation: invalid ES state anchor",
                errorKind: "INPUT_ADMISSION_REFUSED",
                reasonCode: "invalid_anchor"
            )
        case .unavailable:
            return .admissionAuthorityUnavailable
        case .refused(let detail):
            return ContinuationTerminal(
                status: 422,
                message: "Continuation refused before generation: IS admission refused: \(detail)",
                errorKind: "INPUT_ADMISSION_REFUSED",
                reasonCode: "is_refusal"
            )
        }
    }
}

/// Outcome of a successful post-generation settlement step through the
/// product's IS settlement authority. `identityBindingPublished` reports
/// whether the settlement's producer identity binding was made readable.
/// `childESStateID` is the child Execution State the settlement belongs to; it
/// is returned to the client so the NEXT continuation admits through it.
public struct ContinuationSettlementOutcome: Sendable, Equatable {
    public let settlementID: String
    public let identityBindingPublished: Bool
    public let childESStateID: String

    public init(
        settlementID: String,
        identityBindingPublished: Bool,
        childESStateID: String
    ) {
        self.settlementID = settlementID
        self.identityBindingPublished = identityBindingPublished
        self.childESStateID = childESStateID
    }
}

/// One continuation settlement request: the text THIS dispatch generated, the
/// verified parent anchor, the child Execution State the settlement belongs to,
/// and the bindings the pre-generation admission verified. There is no channel
/// for a caller-fabricated result or a re-read of mutable ES state.
public struct ContinuationSettlementRequest: Sendable {
    public let generatedText: String
    public let parentESStateID: String
    public let childESStateID: String
    public let verifiedBindings: [String: NativeContractValue]

    public init(
        generatedText: String,
        parentESStateID: String,
        childESStateID: String,
        verifiedBindings: [String: NativeContractValue]
    ) {
        self.generatedText = generatedText
        self.parentESStateID = parentESStateID
        self.childESStateID = childESStateID
        self.verifiedBindings = verifiedBindings
    }
}

/// Typed failures of the settlement step. Only a native result-contract
/// rejection may be `contractRejected`; SQLite, signature and other
/// infrastructure errors must map to `engine` and never masquerade as a
/// business refusal.
public enum ContinuationSettlementFailure: Error, Sendable {
    /// Generated output was refused by the native pre-settlement contract.
    /// `auditDetail` must be audit-safe (no internal disclosure).
    case contractRejected(auditDetail: String)
    /// Settlement infrastructure or unclassified failure.
    case engine(safeReason: String)
}

extension ContinuationSettlementFailure {
    /// Map authoritative-store errors. A native contract rejection is the ONLY
    /// source of `contractRejected`; everything else is engine.
    init(storeError error: Error) {
        if let contract = error as? NativeResultContractError {
            self = .contractRejected(
                auditDetail: "generated output does not satisfy the declared result contract (\(contract.code))"
            )
        } else {
            self = .engine(safeReason: "authoritative settlement unavailable")
        }
    }

    var terminal: ContinuationTerminal {
        switch self {
        case .contractRejected(let detail):
            return ContinuationTerminal(
                status: 422,
                message: "Generated output refused by the native result contract: \(detail)",
                errorKind: "NATIVE_RESULT_CONTRACT_REJECTED",
                reasonCode: nil
            )
        case .engine(let reason):
            return ContinuationTerminal(
                status: 500,
                message: "Continuation settlement failed: \(reason)",
                errorKind: "SETTLEMENT_ENGINE_ERROR",
                reasonCode: nil
            )
        }
    }
}

/// Pure admission-stage classification: typed failure -> its terminal; any
/// unknown error -> 500 ADMISSION_ENGINE_ERROR, never a 422 business refusal.
func continuationAdmissionTerminal(for error: Error) -> ContinuationTerminal {
    if let failure = error as? ContinuationAdmissionFailure {
        return failure.terminal
    }
    return .admissionEngineError
}

/// Pure settlement-stage classification. A raw `NativeResultContractError`
/// thrown through an untyped boundary still maps to the contract refusal;
/// everything else is a 500 engine error.
func continuationSettlementTerminal(for error: Error) -> ContinuationTerminal {
    if let failure = error as? ContinuationSettlementFailure {
        return failure.terminal
    }
    return ContinuationSettlementFailure(storeError: error).terminal
}

/// Injected post-generation settlement authority. It MUST drive the existing
/// native gate + IS settlement (`ExecutionStateGraphStore.settleProducerResult
/// (...producerIdentity:)`) and MUST NOT create a second validation path.
/// Throws `ContinuationSettlementFailure` (or a raw store error, which maps
/// through `init(storeError:)`).
public typealias ContinuationSettlementHandler =
    @Sendable (_ request: ContinuationSettlementRequest) async throws
    -> ContinuationSettlementOutcome

/// Result of the post-generation settlement step on the dispatch path.
enum ContinuationSettlementStep {
    case notRequested
    case settled(ContinuationSettlementOutcome)
    /// An error terminal has already been written for this request; the
    /// dispatch must return without emitting a completed response.
    case refused
}

// MARK: - Production settlement adapter (NativeMLX wiring)

/// Build the production post-generation settlement authority for a native
/// runtime bound to the model snapshot at `modelPath`. It is the wiring site
/// between the Responses hot path and the product's IS settlement authority,
/// and it adds no second result-contract validation, signature or settlement
/// logic:
///
/// * the generated text, the verified parent anchor, the child Execution State
///   and the verified bindings are the ones the pre-generation admission and
///   the dispatch produced for THIS request (see `settlementStep`); the adapter
///   never accepts a caller-fabricated result, a re-read of mutable ES state,
///   or an identity borrowed from another execution — the producer identity is
///   re-derived from the runtime's own model snapshot, the same way the
///   admission side derives its consumer;
/// * settlement runs through `ExecutionStateGraphStore.settleContinuationResult`
///   -> native gate + ONE authoritative SQLite transaction that creates the
///   child ES, its settlement and the producer identity bindings;
/// * a native result-contract refusal surfaces as
///   `NATIVE_RESULT_CONTRACT_REJECTED`, any infrastructure or missing-authority
///   fault as `SETTLEMENT_ENGINE_ERROR`, and the native gate throws BEFORE the
///   store writes, so a refused request leaves no child state and no partial
///   settlement.
func makeNativeMLXContinuationSettlementHandler(
    modelPath: String
) -> ContinuationSettlementHandler {
    return { request in
        // A-2 write side: the engine exported this branch's prefix representation
        // at the end of the turn that generated THIS text (the export is awaited
        // before generation returns), and it is looked up by THIS request's child
        // ES id — never taken from the request body or from another execution.
        // `nil` means the turn produced no KV boundary claim, so the settlement
        // records none and the next admission has no KV authority to grant.
        let kvRepresentation = NativeMLXPrefixPool.shared.representation(
            forBranch: request.childESStateID)
        return try await MainActor.run {
            try settleForNativeMLXContinuation(
                store: ExecutionStateGraphStore(),
                request: request,
                modelPath: modelPath,
                kvRepresentation: kvRepresentation
            )
        }
    }
}

/// The adapter body, separated from the actor hop so it can be driven
/// directly against an isolated authoritative store. Same authority, same
/// native gate: it only calls the store's continuation settlement entry.
@MainActor
func settleForNativeMLXContinuation(
    store: ExecutionStateGraphStore,
    request: ContinuationSettlementRequest,
    modelPath: String,
    kvRepresentation: SimiGoSettlementKVBinding.Representation? = nil
) throws -> ContinuationSettlementOutcome {
    // The anchor must name a live state in the authoritative graph; an
    // unknown anchor is an authority/infrastructure fault, never a
    // business (contract) refusal.
    guard store.state(request.parentESStateID) != nil else {
        throw ContinuationSettlementFailure.engine(
            safeReason: "continuation anchor not found in the authoritative graph")
    }
    // Producer identity is re-derived from THIS runtime's own model snapshot —
    // never supplied by the caller, never taken from another execution.
    let producer = SimiGoProducerIdentity.identity(fromPath: modelPath)
    let commit = try store.settleContinuationResult(
        generatedText: request.generatedText,
        parentStateID: request.parentESStateID,
        childStateID: request.childESStateID,
        verifiedBindings: request.verifiedBindings,
        producerIdentity: producer,
        kvRepresentation: kvRepresentation
    )
    // The atomic database method returns only after the child state row, the
    // settlement rows and both producer identity rows commit as one unit.
    // Tests independently read the stored rows back from SQLite; no racy
    // post-commit latest lookup is needed.
    return ContinuationSettlementOutcome(
        settlementID: commit.settlementID,
        identityBindingPublished: true,
        childESStateID: commit.childStateID
    )
}
