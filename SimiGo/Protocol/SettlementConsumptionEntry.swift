import Foundation
import SimiGoRuntimeContract

// MARK: - Settlement consumption response contract v0.1
//
// Explicit zero-model-call consumption of an already-settled IS unit on the
// Responses path. Opt-in is a TYPED payload, never a boolean:
//
//   "settlement_consumption": {
//     "source_settlement_id": "...",
//     "contract": {
//       "id": "simigo.settlement-consumption",
//       "demand_class": "exact-repeat",
//       "version": "v1",
//       "extract": "content"
//     },
//     "query": "...",                    // the demand this unit answers
//     "root_ids": ["work"],              // optional; absent = all indexed roots
//     "allow_recompute": false,          // explicit permission to recompute
//     "identity": {                      // optional assertion, never authority
//       "model_identity": "...",
//       "tokenizer_identity": "..."
//     }
//   }
//
// Absence of the field leaves the ordinary Responses path byte-identical. A
// present-but-unusable payload is refused — it never degrades back to an
// ordinary generation. The runtime's OWN model identity is the consumer; a
// client assertion is only compared against it.
//
// Terminals:
//   * authority not wired            -> 503 SETTLEMENT_CONSUMPTION_AUTHORITY_UNAVAILABLE
//   * streaming path                 -> 501 SETTLEMENT_CONSUMPTION_UNSUPPORTED_ON_STREAM
//   * malformed payload              -> 422 SETTLEMENT_CONSUMPTION_REFUSED / invalid_entry
//   * identity assertion mismatch    -> 422 ... / identity_mismatch
//   * named source refused           -> 422 ... / <stable refusal code>
//   * infrastructure / unknown       -> 500 SETTLEMENT_CONSUMPTION_ENGINE_ERROR
//   * success                        -> 200 + settlement_consumption
//     {consumption_id, source_settlement_id, consumer_es_state_id,
//      consumer_settlement_id, demand_id, canonical_digest, model_calls: 0, ...}

/// Strictly parsed `settlement_consumption` payload. Every term is content:
/// the source unit, the reuse contract terms, the demand, and the extraction
/// rule all have to be named by the caller.
public struct SettlementConsumptionEntry: Sendable, Equatable {
    public let sourceSettlementID: String
    public let contractID: String
    public let demandClass: String
    public let contractVersion: String
    public let extractField: String
    public let query: String
    public let rootIDs: [String]
    public let allowRecompute: Bool
    /// The identity pair the caller EXPECTS to consume under. Optional and
    /// purely an assertion: the consumed identity is always re-derived from
    /// this runtime's model snapshot.
    public let identityAssertion: SimiGoSettlementIdentityBinding.Identity?

    public init(
        sourceSettlementID: String,
        contractID: String,
        demandClass: String,
        contractVersion: String,
        extractField: String,
        query: String,
        rootIDs: [String] = [],
        allowRecompute: Bool = false,
        identityAssertion: SimiGoSettlementIdentityBinding.Identity? = nil
    ) {
        self.sourceSettlementID = sourceSettlementID
        self.contractID = contractID
        self.demandClass = demandClass
        self.contractVersion = contractVersion
        self.extractField = extractField
        self.query = query
        self.rootIDs = rootIDs
        self.allowRecompute = allowRecompute
        self.identityAssertion = identityAssertion
    }

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case invalidField(String)

        public var description: String {
            switch self {
            case .invalidField(let f): return "invalid settlement_consumption field: \(f)"
            }
        }
    }

    private static let contractKeys: Set<String> = ["id", "demand_class", "version", "extract"]

    /// Parse strictly. A missing/mistyped required field is an error, never a
    /// default; unknown contract terms are refused so a typo cannot silently
    /// change what is being consumed.
    public static func parse(_ raw: Any) throws -> SettlementConsumptionEntry {
        guard let object = raw as? [String: Any] else {
            throw ParseError.invalidField("settlement_consumption (must be an object)")
        }
        let source = try requiredString(object, "source_settlement_id")
        let query = try requiredString(object, "query")

        guard let contract = object["contract"] as? [String: Any] else {
            throw ParseError.invalidField("contract (must be an object)")
        }
        let unknown = Set(contract.keys).subtracting(contractKeys)
        if let key = unknown.sorted().first {
            throw ParseError.invalidField("contract.\(key) (unknown term)")
        }
        let contractID = try requiredString(contract, "id")
        let demandClass = try requiredString(contract, "demand_class")
        let version = try requiredString(contract, "version")
        let extract = try requiredString(contract, "extract")

        var roots: [String] = []
        if let rawRoots = object["root_ids"] {
            guard let list = rawRoots as? [Any] else {
                throw ParseError.invalidField("root_ids (must be an array of strings)")
            }
            roots = try list.map { element in
                guard let root = element as? String,
                    !root.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    throw ParseError.invalidField("root_ids (must be an array of strings)")
                }
                return root
            }
        }

        var allowRecompute = false
        if let rawFlag = object["allow_recompute"] {
            guard let flag = rawFlag as? Bool else {
                throw ParseError.invalidField("allow_recompute (must be a boolean)")
            }
            allowRecompute = flag
        }

        var assertion: SimiGoSettlementIdentityBinding.Identity?
        if let rawIdentity = object["identity"] {
            guard let identity = rawIdentity as? [String: Any] else {
                throw ParseError.invalidField("identity (must be an object)")
            }
            assertion = SimiGoSettlementIdentityBinding.Identity(
                model: try requiredString(identity, "model_identity"),
                tokenizer: try requiredString(identity, "tokenizer_identity"))
        }

        return SettlementConsumptionEntry(
            sourceSettlementID: source,
            contractID: contractID,
            demandClass: demandClass,
            contractVersion: version,
            extractField: extract,
            query: query,
            rootIDs: roots,
            allowRecompute: allowRecompute,
            identityAssertion: assertion)
    }

    private static func requiredString(
        _ object: [String: Any], _ key: String
    ) throws -> String {
        guard let value = object[key] as? String,
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw ParseError.invalidField("\(key) (must be a non-empty string)")
        }
        return value
    }
}

/// Verified consumption result returned to the HTTP layer. `modelCalls` is 0
/// by construction; `value` was re-admitted from the committed consumer
/// settlement (never from the request body).
public struct SettlementConsumptionReceipt: Sendable, Equatable {
    public let consumptionID: String
    public let sourceSettlementID: String
    public let consumerESStateID: String
    public let consumerSettlementID: String
    public let demandID: String
    public let canonicalDigest: String
    public let value: String
    public let modelCalls: Int
    public let reusedExisting: Bool
    public let contractID: String
    public let demandClass: String
    public let contractVersion: String
    public let extractField: String

    public init(
        consumptionID: String,
        sourceSettlementID: String,
        consumerESStateID: String,
        consumerSettlementID: String,
        demandID: String,
        canonicalDigest: String,
        value: String,
        modelCalls: Int,
        reusedExisting: Bool,
        contractID: String,
        demandClass: String,
        contractVersion: String,
        extractField: String
    ) {
        self.consumptionID = consumptionID
        self.sourceSettlementID = sourceSettlementID
        self.consumerESStateID = consumerESStateID
        self.consumerSettlementID = consumerSettlementID
        self.demandID = demandID
        self.canonicalDigest = canonicalDigest
        self.value = value
        self.modelCalls = modelCalls
        self.reusedExisting = reusedExisting
        self.contractID = contractID
        self.demandClass = demandClass
        self.contractVersion = contractVersion
        self.extractField = extractField
    }
}

/// Handler result. `.recompute` is only reachable for a request that
/// explicitly allowed it; it carries the reason that MUST reach the response.
public enum SettlementConsumptionOutcome: Sendable, Equatable {
    case consumed(SettlementConsumptionReceipt)
    case recompute(reason: String)
}

/// Typed, fail-closed failures of the consumption entry.
public enum SettlementConsumptionFailure: Error, Sendable, Equatable {
    /// No consumption authority is wired for this runtime.
    case unavailable
    /// The typed payload itself is unusable.
    case invalidEntry(String)
    /// The caller's identity assertion disagrees with this runtime's identity.
    case identityMismatch
    /// The named source / contract / demand was refused. `code` is a stable
    /// machine-readable reason.
    case refused(code: String, detail: String)
    /// Infrastructure or unclassified fault (never a business refusal).
    case engine(String)
}

extension SettlementConsumptionFailure {
    var terminal: ContinuationTerminal {
        switch self {
        case .unavailable:
            return .consumptionAuthorityUnavailable
        case .invalidEntry(let detail):
            return ContinuationTerminal(
                status: 422,
                message: "Settlement consumption refused: \(detail)",
                errorKind: "SETTLEMENT_CONSUMPTION_REFUSED",
                reasonCode: "invalid_entry")
        case .identityMismatch:
            return ContinuationTerminal(
                status: 422,
                message: "Settlement consumption refused: consumer identity assertion does not match this runtime",
                errorKind: "SETTLEMENT_CONSUMPTION_REFUSED",
                reasonCode: "identity_mismatch")
        case .refused(let code, let detail):
            return ContinuationTerminal(
                status: 422,
                message: "Settlement consumption refused: \(detail)",
                errorKind: "SETTLEMENT_CONSUMPTION_REFUSED",
                reasonCode: code)
        case .engine(let detail):
            return ContinuationTerminal(
                status: 500,
                message: "Settlement consumption failed: \(detail)",
                errorKind: "SETTLEMENT_CONSUMPTION_ENGINE_ERROR",
                reasonCode: nil)
        }
    }
}

extension ContinuationTerminal {
    static let consumptionAuthorityUnavailable = ContinuationTerminal(
        status: 503,
        message: "Settlement consumption refused: authority unavailable",
        errorKind: "SETTLEMENT_CONSUMPTION_AUTHORITY_UNAVAILABLE",
        reasonCode: nil
    )

    static let consumptionUnsupportedOnStream = ContinuationTerminal(
        status: 501,
        message: "settlement_consumption is not supported on the streaming Responses path",
        errorKind: "SETTLEMENT_CONSUMPTION_UNSUPPORTED_ON_STREAM",
        reasonCode: nil
    )
}

/// Stable machine-readable codes for the native consumption refusals.
///
/// The IS admission gate (`SimiGoISAdmission.Refusal`) contributes its own
/// codes through the same 422 terminal, so a refusal after invalidation is
/// reported as a business refusal rather than an engine fault:
/// `unknown_source`, `source_tampered`, `source_not_valid`,
/// `dependency_missing`, `dependency_invalid`, `empty_value`, and the
/// producer-binding verdict code (`SETTLEMENT_BINDING_MODEL_MISMATCH` et al).
extension SimiGoSettlementConsumption.Refusal {
    var reasonCode: String {
        switch self {
        case .missingField: return "missing_field"
        case .unknownSource: return "unknown_source"
        case .sourceNotValid: return "source_not_valid"
        case .sourceTampered: return "source_tampered"
        case .identityUndeclared: return "identity_undeclared"
        case .contractUndeclared: return "contract_undeclared"
        case .contractMismatch: return "contract_mismatch"
        case .contractNotCovered: return "contract_not_covered"
        case .contractVersionUnsupported: return "contract_version_unsupported"
        case .canonicalInputMismatch: return "canonical_input_mismatch"
        case .rootsMismatch: return "roots_mismatch"
        case .queryMismatch: return "query_mismatch"
        case .extractionUnsupported: return "extraction_unsupported"
        case .consumerSettlementCollision: return "consumer_collision"
        }
    }
}

/// Pure classification: typed failures keep their terminal; anything else is a
/// 500 engine error, never a 422 business refusal.
func settlementConsumptionTerminal(for error: Error) -> ContinuationTerminal {
    if let failure = error as? SettlementConsumptionFailure {
        return failure.terminal
    }
    if let parse = error as? SettlementConsumptionEntry.ParseError {
        return SettlementConsumptionFailure.invalidEntry(String(describing: parse)).terminal
    }
    if let refusal = error as? SimiGoSettlementConsumption.Refusal {
        return SettlementConsumptionFailure.refused(
            code: refusal.reasonCode, detail: String(describing: refusal)).terminal
    }
    return SettlementConsumptionFailure.engine(
        "authoritative settlement consumption unavailable").terminal
}

/// Injected zero-call consumption authority. It MUST drive the product's
/// single native consumption transaction and never a second validation path.
public typealias SettlementConsumptionHandler =
    @Sendable (_ entry: SettlementConsumptionEntry) async throws
        -> SettlementConsumptionOutcome

// MARK: - Production adapter (NativeMLX wiring)

func makeNativeMLXSettlementConsumptionHandler(
    modelPath: String
) -> SettlementConsumptionHandler {
    return { entry in
        try await MainActor.run {
            try SimiGoProducerIdentity.consumeSettlement(
                entry: entry, modelPath: modelPath)
        }
    }
}
