import Foundation

/// Producer-identity binding for settled Information-Space rows.
///
/// A settlement records a semantic result, but a consumer that recovers it in a
/// fresh process must also know WHICH engine produced it: a different model or
/// tokenizer may not silently inherit another engine's settled value. This type
/// is the pure evaluation step used by the headless producer (to publish its
/// identity with the settlement) and by the consumer (to refuse a settlement
/// bound to a different engine) BEFORE any model work happens.
///
/// Scope limit, stated on purpose: these bindings are recorded by the producer
/// itself and are therefore an integrity/binding check, not an attestation. They
/// hold no signature, no trust anchor and no dependency-closure proof; signed
/// provenance remains unimplemented and must not be inferred from this type.
public enum SimiGoSettlementIdentityBinding {

    /// Binding names stored in `settlement_bindings`. The `producer.` prefix keeps
    /// them disjoint from contract constraint bindings written by the native gate.
    public static let modelKey = "producer.model_identity"
    public static let tokenizerKey = "producer.tokenizer_identity"

    /// The identity a producer publishes and a consumer must match. Both members
    /// are the product's own identity strings (`modelIdentity(fromPath:)` /
    /// `tokenizerIdentity(fromPath:)`), never user-supplied values.
    public struct Identity: Equatable, Sendable {
        public let model: String
        public let tokenizer: String

        public init(model: String, tokenizer: String) {
            self.model = model
            self.tokenizer = tokenizer
        }
    }

    public enum Status: String, Sendable {
        case ok
        case blocked
    }

    public struct Verdict: Equatable, Sendable {
        public let status: Status
        /// Stable refusal code; nil only when `status == .ok`.
        public let code: String?
        public let detail: String
        public let boundModel: Bool
        public let boundTokenizer: Bool

        public var evidence: [String: Any] {
            [
                "settlement_binding_status": status.rawValue,
                "settlement_binding_code": code ?? "",
                "settlement_binding_detail": detail,
                "settlement_binding_model_matched": boundModel,
                "settlement_binding_tokenizer_matched": boundTokenizer,
            ]
        }
    }

    public enum Refusal: String, Sendable {
        case modelAbsent = "SETTLEMENT_BINDING_MODEL_ABSENT"
        case tokenizerAbsent = "SETTLEMENT_BINDING_TOKENIZER_ABSENT"
        case modelMismatch = "SETTLEMENT_BINDING_MODEL_MISMATCH"
        case tokenizerMismatch = "SETTLEMENT_BINDING_TOKENIZER_MISMATCH"
    }

    /// Digest form of one identity string, using the SAME production digest that
    /// seals settlement payloads, so no consumer re-implements hashing.
    public static func digest(_ value: String) -> String {
        SimiGoSettlementAuthority.payloadDigest(Data(value.utf8))
    }

    /// The binding rows a producer must persist with its settlement.
    public static func bindings(for identity: Identity) -> [String: String] {
        [modelKey: digest(identity.model), tokenizerKey: digest(identity.tokenizer)]
    }

    /// Compare what the Information Space recorded against the consumer's own
    /// identity. Fail-closed: an absent binding is a refusal, not a pass, so a
    /// settlement written by an older producer can never be consumed silently.
    public static func evaluate(recorded: [String: String], consumer: Identity) -> Verdict {
        guard let recordedModel = recorded[modelKey], !recordedModel.isEmpty else {
            return Verdict(status: .blocked, code: Refusal.modelAbsent.rawValue,
                           detail: "settlement carries no \(modelKey) binding",
                           boundModel: false, boundTokenizer: false)
        }
        guard recordedModel == digest(consumer.model) else {
            return Verdict(status: .blocked, code: Refusal.modelMismatch.rawValue,
                           detail: "settlement was produced by a different model identity",
                           boundModel: false, boundTokenizer: false)
        }
        guard let recordedTokenizer = recorded[tokenizerKey], !recordedTokenizer.isEmpty else {
            return Verdict(status: .blocked, code: Refusal.tokenizerAbsent.rawValue,
                           detail: "settlement carries no \(tokenizerKey) binding",
                           boundModel: true, boundTokenizer: false)
        }
        guard recordedTokenizer == digest(consumer.tokenizer) else {
            return Verdict(status: .blocked, code: Refusal.tokenizerMismatch.rawValue,
                           detail: "settlement was produced by a different tokenizer identity",
                           boundModel: true, boundTokenizer: false)
        }
        return Verdict(status: .ok, code: nil,
                       detail: "settlement bound to this model and tokenizer",
                       boundModel: true, boundTokenizer: true)
    }
}
