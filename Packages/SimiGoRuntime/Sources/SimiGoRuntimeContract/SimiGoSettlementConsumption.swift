import Foundation

/// Stage B: consume a settled Information-Space unit into a NEW Execution State
/// without running the model.
///
/// This is not a KV recovery path. It moves no representation and creates no
/// prefix pool entry: it recovers the already-settled semantic value, re-verifies
/// the named source and its dependency closure inside the SAME write transaction,
/// and commits a consumer ES plus a `DERIVED_CONSUMPTION` settlement that records
/// what was consumed, why reuse was allowed, and who consumed it.
///
/// Fail-closed order (all inside one `BEGIN IMMEDIATE`):
///   1. named source re-admission (exists, digest, valid, closure, identity)
///   2. reuse contract terms (id, class, version, extraction)
///   3. canonical input digest over the CURRENT settled file contents
///   4. idempotency lookup on (source, consumer, demand)
///   5. consumer ES + derived settlement + consumption row + dependency edge +
///      ledger + advancement
/// Any failure rolls every write back. A missing declaration is never consumable.
public enum SimiGoSettlementConsumption {

    /// The one reuse contract this build understands. A declaration naming a
    /// different class/version is refused, not reinterpreted.
    public enum Contract {
        public static let contractID = "simigo.settlement-consumption"
        public static let demandClass = "exact-repeat"
        public static let version = "v1"
        public static let defaultExtractField = "content"
        /// Human-readable identity requirement; the enforced comparison is the
        /// producer/consumer binding pair recorded with the settlement.
        public static let identityBinding =
            "producer.model_identity+producer.tokenizer_identity"
    }

    public struct Request: Sendable {
        public let sourceSettlementID: String
        public let consumerStateID: String
        public let consumerParentStateID: String?
        public let consumerPosition: Int
        public let consumerModelIdentity: String
        public let consumerIdentity: SimiGoSettlementIdentityBinding.Identity
        public let contractID: String
        public let demandClass: String
        public let contractVersion: String
        /// The extraction rule the caller names. It must equal the declaration's
        /// rule; a request never silently consumes a field it did not ask for.
        public let extractField: String
        public let query: String
        public let rootIDs: [String]
        /// Only an explicit request may turn an uncovered/changed demand into a
        /// recompute outcome; without it the operation refuses.
        public let allowRecompute: Bool
        public let resultContractJSON: Data
        public let consumedAt: Date

        public init(
            sourceSettlementID: String,
            consumerStateID: String,
            consumerParentStateID: String? = nil,
            consumerPosition: Int = 1,
            consumerModelIdentity: String,
            consumerIdentity: SimiGoSettlementIdentityBinding.Identity,
            contractID: String = Contract.contractID,
            demandClass: String = Contract.demandClass,
            contractVersion: String = Contract.version,
            extractField: String = Contract.defaultExtractField,
            query: String,
            rootIDs: [String] = [],
            allowRecompute: Bool = false,
            resultContractJSON: Data = SimiGoInformationLoop.chatResultContractJSON,
            consumedAt: Date = Date()
        ) {
            self.sourceSettlementID = sourceSettlementID
            self.consumerStateID = consumerStateID
            self.consumerParentStateID = consumerParentStateID
            self.consumerPosition = consumerPosition
            self.consumerModelIdentity = consumerModelIdentity
            self.consumerIdentity = consumerIdentity
            self.contractID = contractID
            self.demandClass = demandClass
            self.contractVersion = contractVersion
            self.extractField = extractField
            self.query = query
            self.rootIDs = rootIDs
            self.allowRecompute = allowRecompute
            self.resultContractJSON = resultContractJSON
            self.consumedAt = consumedAt
        }
    }

    public struct Consumed: Equatable, Sendable {
        public let consumptionID: String
        public let sourceSettlementID: String
        public let consumerStateID: String
        public let consumerSettlementID: String
        public let demandID: String
        public let canonicalDigest: String
        /// The verified settled value, re-admitted from the consumer settlement
        /// so even an idempotent repeat returns a verified value.
        public let value: String
        /// Provenance, in data: this operation performed zero model calls.
        public let modelCalls: Int
        /// True when an identical consumption already existed and was returned
        /// instead of writing a second one.
        public let reusedExisting: Bool
    }

    public enum Outcome: Equatable, Sendable {
        case consumed(Consumed)
        /// No consumption record was written. The caller may run the normal
        /// generation path and must record this reason.
        case recompute(reason: String)
    }

    public enum Refusal: Error, Equatable, CustomStringConvertible {
        case missingField(String)
        case unknownSource(String)
        case sourceNotValid(String)
        case sourceTampered(String)
        case identityUndeclared(String)
        case contractUndeclared(settlementID: String)
        case contractMismatch(field: String, expected: String, actual: String)
        case contractNotCovered(demandClass: String, allowed: String)
        case contractVersionUnsupported(String)
        case canonicalInputMismatch(expected: String, actual: String)
        case rootsMismatch(expected: [String], actual: [String])
        case queryMismatch(expected: String, actual: String)
        case extractionUnsupported(field: String)
        case consumerSettlementCollision(String)

        public var description: String {
            switch self {
            case .missingField(let f):
                return "settlement consumption: missing required field \(f)"
            case .unknownSource(let s):
                return "settlement consumption: unknown source settlement \(s)"
            case .sourceNotValid(let s):
                return "settlement consumption: source settlement \(s) is not valid"
            case .sourceTampered(let s):
                return "settlement consumption: source settlement \(s) failed digest verification"
            case .identityUndeclared(let s):
                return "settlement consumption: source settlement \(s) declares no identity binding"
            case .contractUndeclared(let s):
                return "settlement \(s) declared no reuse contract; it is not consumable"
            case .contractMismatch(let f, let e, let a):
                return "reuse contract \(f) mismatch: expected \(e), got \(a)"
            case .contractNotCovered(let d, let a):
                return "demand_class \(d) is not covered by the reuse contract (allowed: \(a))"
            case .contractVersionUnsupported(let v):
                return "reuse contract version \(v) is not supported by this build"
            case .canonicalInputMismatch(let e, let a):
                return "canonical input digest changed: declared \(e), current \(a)"
            case .rootsMismatch(let e, let a):
                return "demand roots changed: declared \(e), current \(a)"
            case .queryMismatch(let e, let a):
                return "demand query changed: declared \(e), current \(a)"
            case .extractionUnsupported(let f):
                return "extraction field \(f) is not supported"
            case .consumerSettlementCollision(let s):
                return "consumer state \(s) already carries a different settlement"
            }
        }
    }

    /// Consume a settled unit. The source must be named explicitly; validity,
    /// closure, identity, contract and the canonical input basis are all
    /// re-checked inside the write transaction, never from an earlier read.
    public static func consume(
        db: SimiGoESISDatabase, request: Request
    ) throws -> Outcome {
        try consume(db: db, request: request, afterAdmission: nil)
    }

    /// `afterAdmission` is a test seam for the race matrix: it runs after the
    /// named source was re-admitted and before any row is written, while the
    /// write transaction is held. Production callers never pass it.
    static func consume(
        db: SimiGoESISDatabase, request: Request,
        afterAdmission: (() throws -> Void)?
    ) throws -> Outcome {
        for (name, value) in [
            ("source_settlement_id", request.sourceSettlementID),
            ("consumer_state_id", request.consumerStateID),
            ("contract_id", request.contractID),
            ("demand_class", request.demandClass),
            ("contract_version", request.contractVersion),
            ("extract", request.extractField),
            ("query", request.query),
            ("consumer_model_identity", request.consumerModelIdentity),
        ] where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw Refusal.missingField(name)
        }

        return try db.transactionResult {
            guard let declaration = try db.settlementReuseContract(
                settlementID: request.sourceSettlementID)
            else {
                throw Refusal.contractUndeclared(
                    settlementID: request.sourceSettlementID)
            }

            // 1. Re-admit the NAMED source inside the write transaction. A
            // refusal here (missing/tampered/invalid/dependency/identity) is
            // final: no row is written and no recompute is silently substituted.
            let admitted = try SimiGoISAdmission.admit(
                db: db, settlementID: request.sourceSettlementID,
                consumer: request.consumerIdentity,
                valueField: declaration.extractField)
            try afterAdmission?()

            // 2. Contract terms.
            guard declaration.contractID == request.contractID else {
                throw Refusal.contractMismatch(
                    field: "contract_id", expected: declaration.contractID,
                    actual: request.contractID)
            }
            guard declaration.demandClass == request.demandClass else {
                if request.allowRecompute {
                    return .recompute(
                        reason: "demand_class \(request.demandClass) not covered by \(declaration.contractID)")
                }
                throw Refusal.contractNotCovered(
                    demandClass: request.demandClass,
                    allowed: declaration.demandClass)
            }
            guard declaration.contractVersion == request.contractVersion else {
                throw Refusal.contractMismatch(
                    field: "contract_version",
                    expected: declaration.contractVersion,
                    actual: request.contractVersion)
            }
            guard request.contractVersion == Contract.version else {
                throw Refusal.contractVersionUnsupported(request.contractVersion)
            }
            guard request.extractField == declaration.extractField else {
                throw Refusal.contractMismatch(
                    field: "extract", expected: declaration.extractField,
                    actual: request.extractField)
            }
            guard declaration.extractField == Contract.defaultExtractField else {
                throw Refusal.extractionUnsupported(field: declaration.extractField)
            }

            // 3. Canonical input over the CURRENT settled content. BEGIN IMMEDIATE
            // already holds the write lock, so a content settlement cannot land
            // between this read and the commit.
            let canonical = try db.canonicalDemandInput(
                query: request.query, rootIDs: request.rootIDs)
            if canonical.digest != declaration.canonicalDigest
                || canonical.canonical != declaration.canonicalText {
                if request.allowRecompute {
                    return .recompute(reason: "canonical input changed")
                }
                throw Refusal.canonicalInputMismatch(
                    expected: declaration.canonicalDigest,
                    actual: canonical.digest)
            }
            let requestedRoots = request.rootIDs.isEmpty
                ? canonical.rootIDs
                : Array(Set(request.rootIDs)).sorted()
            guard requestedRoots == declaration.rootIDs else {
                if request.allowRecompute {
                    return .recompute(reason: "demand roots changed")
                }
                throw Refusal.rootsMismatch(
                    expected: declaration.rootIDs, actual: requestedRoots)
            }
            guard request.query == declaration.query else {
                if request.allowRecompute {
                    return .recompute(reason: "demand query changed")
                }
                throw Refusal.queryMismatch(
                    expected: declaration.query, actual: request.query)
            }

            // 4. Idempotency: the same source, consumer and demand is one record.
            let demandID = Self.demandID(
                contractID: declaration.contractID,
                contractVersion: declaration.contractVersion,
                demandClass: declaration.demandClass,
                canonicalDigest: canonical.digest)
            if let existing = try db.settlementConsumption(
                sourceSettlementID: request.sourceSettlementID,
                consumerStateID: request.consumerStateID,
                demandID: demandID)
            {
                guard existing.consumerSettlementID
                    == (try db.latestSettlementID(forStateID: request.consumerStateID)
                        ?? existing.consumerSettlementID)
                else {
                    throw Refusal.consumerSettlementCollision(request.consumerStateID)
                }
                // A repeat is not an unchecked cache hit: re-admit the derived
                // settlement under this caller's identity (it binds the consumer
                // that produced it) and return only the value that verifies.
                let repeatAdmitted = try SimiGoISAdmission.admit(
                    db: db, settlementID: existing.consumerSettlementID,
                    consumer: request.consumerIdentity,
                    valueField: declaration.extractField)
                return .consumed(Consumed(
                    consumptionID: existing.consumptionID,
                    sourceSettlementID: existing.sourceSettlementID,
                    consumerStateID: existing.consumerStateID,
                    consumerSettlementID: existing.consumerSettlementID,
                    demandID: existing.demandID,
                    canonicalDigest: existing.canonicalDigest,
                    value: repeatAdmitted.recoveredValue,
                    modelCalls: existing.modelCalls,
                    reusedExisting: true))
            }
            guard try db.latestSettlementID(forStateID: request.consumerStateID) == nil else {
                throw Refusal.consumerSettlementCollision(request.consumerStateID)
            }

            // 5. Write the complete consumption unit.
            let basisJSON = try Self.basisJSON(
                sourceSettlementID: request.sourceSettlementID,
                sourcePayloadDigest: admitted.payloadDigest,
                declaration: declaration,
                canonical: canonical,
                roots: requestedRoots,
                request: request)
            let plan = SimiGoESISDatabase.SettlementConsumptionPlan(
                consumptionID: UUID().uuidString,
                sourceSettlementID: request.sourceSettlementID,
                sourcePayloadDigest: admitted.payloadDigest,
                consumerState: .init(
                    id: request.consumerStateID,
                    parentID: request.consumerParentStateID,
                    modelIdentity: request.consumerModelIdentity,
                    position: request.consumerPosition,
                    continuationID: UUID().uuidString,
                    anchor: admitted.payloadDigest,
                    createdAt: request.consumedAt,
                    nextInput: admitted.recoveredValue),
                consumerIdentity: request.consumerIdentity,
                consumerResultContractJSON: request.resultContractJSON,
                consumedValue: admitted.recoveredValue,
                demandID: demandID,
                query: request.query,
                rootIDs: requestedRoots,
                canonicalText: canonical.canonical,
                canonicalDigest: canonical.digest,
                contractID: declaration.contractID,
                demandClass: declaration.demandClass,
                contractVersion: declaration.contractVersion,
                requiredIdentityJSON: declaration.requiredIdentityJSON,
                extractField: declaration.extractField,
                basisJSON: basisJSON,
                consumedAt: request.consumedAt)
            let commit = try db.recordSettlementConsumption(plan)
            return .consumed(Consumed(
                consumptionID: commit.consumptionID,
                sourceSettlementID: request.sourceSettlementID,
                consumerStateID: request.consumerStateID,
                consumerSettlementID: commit.consumerSettlementID,
                demandID: commit.demandID,
                canonicalDigest: canonical.digest,
                value: admitted.recoveredValue,
                modelCalls: 0,
                reusedExisting: false))
        }
    }

    private static func demandID(
        contractID: String, contractVersion: String,
        demandClass: String, canonicalDigest: String
    ) -> String {
        let basis = "settlement-consumption|\(contractID)|\(contractVersion)|"
            + "\(demandClass)|\(canonicalDigest)"
        return NativeSHA256.hexDigest(Data(basis.utf8))
    }

    private static func basisJSON(
        sourceSettlementID: String,
        sourcePayloadDigest: String,
        declaration: SimiGoESISDatabase.SettlementReuseDeclaration,
        canonical: SimiGoESISDatabase.CanonicalDemandInput,
        roots: [String],
        request: Request
    ) throws -> Data {
        let object: [String: Any] = [
            "validity_basis": "rechecked-in-write-transaction",
            "dependency_closure_checked": true,
            "source_validity": "valid",
            "source_settlement_id": sourceSettlementID,
            "source_payload_digest": sourcePayloadDigest,
            "canonical_digest": canonical.digest,
            "canonical_text": canonical.canonical,
            "query": request.query,
            "roots": roots,
            "contract_id": declaration.contractID,
            "demand_class": declaration.demandClass,
            "contract_version": declaration.contractVersion,
            "required_identity": declaration.requiredIdentityJSON,
            "identity_verdict": "ok",
            "extract_field": declaration.extractField,
            "model_calls": 0,
        ]
        return try JSONSerialization.data(
            withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
