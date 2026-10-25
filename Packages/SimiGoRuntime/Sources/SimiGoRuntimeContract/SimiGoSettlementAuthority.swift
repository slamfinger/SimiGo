import Foundation

/// The single sanctioned pre-settlement authority in the SimiGo product runtime.
///
/// A semantic result produced by any producer (model, tool, or import) may only
/// become a settled Information-Space record after this type returns
/// successfully. It delegates to the native declarative result-contract gate
/// (`NativeProducerResultContractGate`) and:
///   * never falls back to a Python validator,
///   * never returns a payload when the gate rejects,
///   * performs no I/O — the caller must invoke this BEFORE any write/sign, so a
///     thrown error means nothing was persisted (fail-closed).
///
/// `verifiedBindings` must come from the normal IS admission path; this type
/// validates the declared relationship between generated fields and those
/// already-verified values, it does not establish their provenance.
public enum SimiGoSettlementAuthority {

    /// A native-authorized, canonical settlement. Carries only validated fields.
    public struct SettledResult: Codable, Sendable, Equatable {
        public let schemaVersion: String
        /// Canonical JSON of the validated contract fields (raw model text excluded).
        public let validatedPayload: Data
        /// SHA-256 (lowercase hex) over `validatedPayload`, for the IS digest index.
        public let payloadDigest: String
        public let trace: NativeResultValidationTrace
        public let settledAt: Date
    }

    /// Run the native gate before settlement/signature/persistence. Throws a
    /// `NativeResultContractError` on unknown constraint, missing binding,
    /// canonicalization failure, or digest/derivation mismatch. On throw the
    /// caller must not write or sign anything.
    public static func authorize(
        generatedText: String,
        contractJSON: Data,
        verifiedBindings: [String: NativeContractValue],
        settledAt: Date = Date()
    ) throws -> SettledResult {
        let trace = try NativeProducerResultContractGate.validateBeforeSettlement(
            generatedText: generatedText,
            contractJSON: contractJSON,
            verifiedBindings: verifiedBindings
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = try encoder.encode(trace.values)
        return SettledResult(
            schemaVersion: trace.schemaVersion,
            validatedPayload: payload,
            payloadDigest: NativeSHA256.hexDigest(payload),
            trace: trace,
            settledAt: settledAt
        )
    }

    /// Re-verify that a stored settlement payload's canonical SHA-256 matches the
    /// digest recorded in the Information Space. Uses the SAME production digest
    /// function `authorize` used to seal the payload, so a tampered payload or
    /// recorded digest is detected without any consumer re-implementing hashing.
    /// Pure, no I/O; safe to call from a reader before trusting a settled value.
    public static func payloadDigestMatches(
        _ payload: Data, recordedDigest: String
    ) -> Bool {
        NativeSHA256.hexDigest(payload) == recordedDigest
    }

    /// Canonical content SHA-256 using the SAME production digest that seals
    /// settlements. Public so identity/tokenizer digests can be computed without
    /// any consumer re-implementing hashing.
    public static func payloadDigest(_ payload: Data) -> String {
        NativeSHA256.hexDigest(payload)
    }
}
