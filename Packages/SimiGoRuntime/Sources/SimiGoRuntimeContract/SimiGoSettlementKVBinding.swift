import Foundation

/// KV-representation binding for a settled Execution State computation.
///
/// A settlement records a semantic result. The prefix-pool artifact that the
/// producing turn committed (its KV snapshot) is the SAME computation expressed
/// as a physical representation — until this type existed, nothing in the
/// authoritative store named it, so a later execution could only find it by
/// re-deriving a token-chain hash, and the reuse decision never consulted the
/// settlement at all (the IS/KV wiring gap, 2026-10-26).
///
/// This type makes the settled computation addressable: the producer stores the
/// digest of the pool entry key it exported alongside the settlement, and a
/// consumer that has ALREADY passed IS admission (digest integrity, dynamic
/// validity, dependency closure, producer identity) may bind KV only to the
/// representation that settlement names. Any disagreement is a refusal, so the
/// engine falls back to a full cold prefill instead of silently continuing on an
/// representation a verified settlement does not authorize.
///
/// Scope limits, stated on purpose:
/// * like `SimiGoSettlementIdentityBinding`, these rows are written by the
///   producer itself — a binding, not an attestation;
/// * only digests are stored, never a model path, a token array or weight bytes;
/// * the check is an authorization boundary for the continuation edge. The
///   content-addressed same-session path (no settlement involved) is untouched.
public enum SimiGoSettlementKVBinding {

    /// Binding names stored in `settlement_bindings`. The `kv.` prefix keeps
    /// them disjoint from `producer.` identity rows and native-gate constraint rows.
    public static let poolKey = "kv.pool_key"
    public static let cacheFingerprint = "kv.cache_fingerprint"

    /// The prefix-pool entry that a settled turn committed, in the producer's own
    /// vocabulary. `boundaryHash` is the chain hash over the covered message
    /// stream — the pool's content claim, not a new identity scheme.
    public struct Representation: Equatable, Sendable {
        public let modelID: String
        /// Namespace fingerprint as the pool uses it (kv layout + thinking flag).
        public let kvFingerprint: String
        public let tokenCount: Int
        public let boundaryHash: UInt64

        public init(
            modelID: String, kvFingerprint: String, tokenCount: Int, boundaryHash: UInt64
        ) {
            self.modelID = modelID
            self.kvFingerprint = kvFingerprint
            self.tokenCount = tokenCount
            self.boundaryHash = boundaryHash
        }

        /// Canonical pool entry key. One string, one format: the prefix pool builds
        /// the same key for its dedup ledger, so a recorded binding and a live entry
        /// are comparable without a second addressing scheme.
        public var poolKey: String {
            "\(modelID)|\(kvFingerprint)|\(tokenCount)|"
                + String(boundaryHash, radix: 16, uppercase: false)
        }
    }

    /// Digest form of any binding value, using the SAME production digest that
    /// seals settlement payloads and identity bindings.
    public static func digest(_ value: String) -> String {
        SimiGoSettlementAuthority.payloadDigest(Data(value.utf8))
    }

    /// The binding rows a producer must persist with its settlement.
    public static func bindings(for representation: Representation) -> [String: String] {
        [
            poolKey: digest(representation.poolKey),
            cacheFingerprint: digest(representation.kvFingerprint),
        ]
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

        public var evidence: [String: Any] {
            [
                "kv_binding_status": status.rawValue,
                "kv_binding_code": code ?? "",
                "kv_binding_detail": detail,
            ]
        }
    }

    public enum Refusal: String, Sendable {
        case poolKeyAbsent = "SETTLEMENT_KV_POOL_KEY_ABSENT"
        case fingerprintAbsent = "SETTLEMENT_KV_FINGERPRINT_ABSENT"
        case fingerprintMismatch = "SETTLEMENT_KV_FINGERPRINT_MISMATCH"
        case poolKeyMismatch = "SETTLEMENT_KV_POOL_KEY_MISMATCH"
    }

    /// Compare what the settlement recorded against the representation the
    /// consumer actually holds. Fail-closed in both directions: an absent binding
    /// refuses (a settlement from before this wiring has no authorized
    /// representation), and so does any disagreement about the namespace, the
    /// covered length or the content claim.
    public static func evaluate(
        recorded: [String: String], consumer: Representation
    ) -> Verdict {
        guard let recordedFingerprint = recorded[cacheFingerprint], !recordedFingerprint.isEmpty
        else {
            return Verdict(status: .blocked, code: Refusal.fingerprintAbsent.rawValue,
                           detail: "settlement carries no \(cacheFingerprint) binding")
        }
        guard recordedFingerprint == digest(consumer.kvFingerprint) else {
            return Verdict(status: .blocked, code: Refusal.fingerprintMismatch.rawValue,
                           detail: "settled representation was produced under a different KV namespace")
        }
        guard let recordedPoolKey = recorded[poolKey], !recordedPoolKey.isEmpty else {
            return Verdict(status: .blocked, code: Refusal.poolKeyAbsent.rawValue,
                           detail: "settlement carries no \(poolKey) binding")
        }
        guard recordedPoolKey == digest(consumer.poolKey) else {
            return Verdict(status: .blocked, code: Refusal.poolKeyMismatch.rawValue,
                           detail: "settled representation names a different prefix boundary")
        }
        return Verdict(status: .ok, code: nil,
                       detail: "settled representation matches the bound prefix boundary")
    }

    /// The `kv.`-prefixed rows of one settlement, ready to hand to `evaluate`.
    /// Constraint and producer rows live in the same table and are excluded here
    /// so callers cannot pass the whole dictionary and get a false pass.
    public static func recordedBindings(from all: [String: String]) -> [String: String] {
        all.filter { $0.key == poolKey || $0.key == cacheFingerprint }
    }
}
