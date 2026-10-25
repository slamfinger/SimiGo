import Foundation
import SimiGoRuntimeContract

/// Outcome of an ES/IS continuation admission performed BEFORE generation.
/// `recoveredValue` is the semantic value recovered from a VERIFIED IS
/// settlement; the live dispatch feeds it into the continuation so the value
/// that reaches the model comes from the authoritative store, not the client.
///
/// `verifiedBindings` are the bindings THAT admission verified. The settlement
/// gate binds the produced result against exactly these values; it never
/// re-derives them from mutable execution state (`continueState` can rewrite
/// `nextInput` after the parent settled).
public struct ContinuationAdmissionOutcome: Sendable {
    public let esStateID: String
    public let recoveredValue: String
    public let verifiedBindings: [String: NativeContractValue]
    public init(
        esStateID: String,
        recoveredValue: String,
        verifiedBindings: [String: NativeContractValue]
    ) {
        self.esStateID = esStateID
        self.recoveredValue = recoveredValue
        self.verifiedBindings = verifiedBindings
    }
}

/// Per-request continuation binding, established by the pre-generation
/// admission and consumed by the post-generation settlement of the SAME
/// request: the verified parent anchor, the fresh child Execution State this
/// request executes under, and the bindings the admission verified.
struct ContinuationRequestBinding: Sendable {
    let parentESStateID: String
    let childESStateID: String
    let verifiedBindings: [String: NativeContractValue]
}

/// Typed, fail-closed reasons an opt-in continuation is refused before any
/// generation. Nothing here silently downgrades to an ordinary generation.
public enum ContinuationAdmissionFailure: Error, Sendable {
    /// `previous_es_state_id` was present but empty / not a usable identifier.
    case invalidAnchor
    /// No admission authority is wired for this runtime (fail closed).
    case unavailable
    /// The native IS admission refused: digest/validity/dependency-closure/
    /// identity/recovery check did not pass. Carries an audit-safe reason.
    case refused(String)
}

/// Injected by the runtime that owns the authoritative ES/IS store and the real
/// model identity. `HTTPServerResponses` calls it ONLY when a request explicitly
/// carries `previous_es_state_id`; absence of the field leaves the dispatch path
/// byte-for-byte unchanged.
public typealias ContinuationAdmissionHandler =
    @Sendable (_ esStateID: String) async throws -> ContinuationAdmissionOutcome
