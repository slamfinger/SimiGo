import Foundation

/// Native Information-Space (IS) admission authority.
///
/// This is the single reusable, MLX-free, pre-model gate the product dispatch
/// path calls to recover an already-settled IS value and mint `verifiedBindings`
/// for a fresh Execution State (ES). It COMPOSES the existing native authorities
/// rather than adding a second mechanism:
///   * `ESISDatabase`                 — IS read, validity, dependency closure
///   * `SettlementAuthority`          — canonical digest verification (seal)
///   * `SettlementIdentityBinding`    — producer/consumer provenance metadata
///
/// Before this type existed, the same sequence was assembled inline in the
/// headless gate driver and could not be called from the product request path;
/// it also verified only the settlement itself, never the full upstream
/// dependency closure. This type closes both gaps at the native layer.
///
/// Fail-closed contract: every unmet precondition throws BEFORE any value or
/// binding is returned, so a caller cannot reach model generation with an
/// unverified IS value. On throw nothing is produced — `generation_call_count`
/// for a refused admission is provably zero because this performs no model work.
public enum ISAdmission {

    /// A verified IS admission result, ready to seed a fresh ES.
    public struct Admitted: Sendable, Equatable {
        public let settlementID: String
        public let payloadDigest: String
        public let recoveredValue: String
        /// Values the native result-contract gate may bind against for the new ES.
        public let verifiedBindings: [String: NativeContractValue]
        /// The prefix-representation binding rows (`kv.*`) the producer settled
        /// alongside this record, as name -> digest. Empty when the settlement
        /// claimed no KV representation — the safe default: a KV restore then has
        /// no authority to act on and must fall back to a cold prefill.
        ///
        /// This is the read half of A-2: the KV boundary a continuation is allowed
        /// to reuse is the one recorded by the settlement and independently checked
        /// by the engine against its concrete model/KV namespace and prefix boundary.
        public let kvBindings: [String: String]
        /// The producer identity rows (`producer.model_identity` /
        /// `producer.tokenizer_identity`) the settlement recorded, as name -> digest.
        /// These are provenance for semantic reuse, but at a PHYSICAL KV bind site
        /// they are a strict gate: the engine may only restore a settled prefix
        /// representation when its own re-derived model + tokenizer identity matches
        /// the producer's. Empty for a derived consumption (no producer KV claim).
        public let producerBindings: [String: String]

        public init(
            settlementID: String,
            payloadDigest: String,
            recoveredValue: String,
            verifiedBindings: [String: NativeContractValue],
            kvBindings: [String: String] = [:],
            producerBindings: [String: String] = [:]
        ) {
            self.settlementID = settlementID
            self.payloadDigest = payloadDigest
            self.recoveredValue = recoveredValue
            self.verifiedBindings = verifiedBindings
            self.kvBindings = kvBindings
            self.producerBindings = producerBindings
        }
    }

    /// Stable, fail-closed refusal reasons. Each carries enough identity to
    /// audit which settlement/state was refused and why.
    public enum Refusal: Error, Equatable, CustomStringConvertible {
        case noSettlement(stateID: String)
        case unknownSettlement(settlementID: String)
        case digestMismatch(settlementID: String)
        case invalidated(settlementID: String)
        case dependencyMissing(settlementID: String, dependency: String)
        case dependencyInvalid(settlementID: String, dependency: String)
        /// Legacy refusal retained for source compatibility. Producer/consumer
        /// identity mismatch is no longer a general IS semantic-admission refusal.
        case producerBinding(SettlementIdentityBinding.Verdict)
        case emptyValue(settlementID: String)

        public var description: String {
            switch self {
            case .noSettlement(let s):
                return "no settled IS record for state \(s)"
            case .unknownSettlement(let s):
                return "no settled IS record with id \(s)"
            case .digestMismatch(let s):
                return "settlement \(s) payload/digest verification failed (tamper)"
            case .invalidated(let s):
                return "settlement \(s) is not currently valid"
            case .dependencyMissing(let s, let d):
                return "settlement \(s) depends on \(d) which is absent from the IS"
            case .dependencyInvalid(let s, let d):
                return "settlement \(s) depends on \(d) which is invalidated"
            case .producerBinding(let v):
                return "producer identity binding refused: \(v.detail)"
            case .emptyValue(let s):
                return "settlement \(s) carries no recoverable value"
            }
        }
    }

    /// Verify the settled IS value for `stateID` and, only when EVERY native
    /// precondition holds, return the recovered value plus `verifiedBindings`
    /// for a fresh ES. The checks, in order, all fail-closed before returning:
    ///   1. resolve the newest settlement for the state (missing → refuse)
    ///   2. load its receipt row
    ///   3. canonical digest integrity via the SAME production seal digest
    ///   4. dynamic validity of the settlement itself
    ///   5. full upstream dependency closure — every member present AND valid
    ///   6. recover the settled semantic value and mint the bindings
    ///
    /// Producer identity remains provenance metadata. It is not a universal gate:
    /// semantically valid results may be reused by another model/Agent. A task that
    /// truly depends on a particular engine must express that as an explicit
    /// semantic dependency or result-contract constraint.
    ///
    /// - Parameters:
    ///   - bindingName: key the new ES's result contract expects for this value
    ///     (`next_input` by default, matching the reference settlement path).
    ///   - valueField: contract field name holding the semantic value in the
    ///     settled payload (`content` for the reference result contract).
    public static func admit(
        db: ESISDatabase,
        stateID: String,
        consumer: SettlementIdentityBinding.Identity,
        bindingName: String = "next_input",
        valueField: String = "content"
    ) throws -> Admitted {
        // 1. newest settlement for the state.
        guard let settlementID = try db.latestSettlementID(forStateID: stateID) else {
            throw Refusal.noSettlement(stateID: stateID)
        }
        return try admit(
            db: db, settlementID: settlementID, consumer: consumer,
            bindingName: bindingName, valueField: valueField)
    }

    /// Verify an EXPLICITLY NAMED settlement. A consumer that reuses a settled
    /// result must name it: "the newest settlement for that state" is a different
    /// (and possibly ambiguous) lookup. The checks are the same ones the
    /// state-based entry runs, so there is exactly one admission authority.
    public static func admit(
        db: ESISDatabase,
        settlementID: String,
        consumer: SettlementIdentityBinding.Identity,
        bindingName: String = "next_input",
        valueField: String = "content"
    ) throws -> Admitted {
        // Kept in the signature for existing callers; semantic IS admission does
        // not compare consumer identity with producer provenance.
        _ = consumer
        // 2. its receipt row (payload + recorded digest + producer/derivation status).
        guard let row = try db.settlementAdmissionRow(settlementID: settlementID),
            row.validationStatus != "MIGRATED_LEGACY"
        else {
            throw Refusal.unknownSettlement(settlementID: settlementID)
        }
        // 3. digest integrity — the same hashing that sealed it at settle time.
        guard SettlementAuthority.payloadDigestMatches(
            row.payload, recordedDigest: row.recordedPayloadDigest)
        else {
            throw Refusal.digestMismatch(settlementID: settlementID)
        }
        // 4. dynamic validity of the settlement itself.
        if row.validity != "valid" {
            throw Refusal.invalidated(settlementID: settlementID)
        }
        // 5. full upstream dependency closure: each member present and valid.
        for dependency in try db.upstreamDependencyClosure(ofSettlement: settlementID) {
            guard let validity = try db.settlementValidityIfPresent(dependency) else {
                throw Refusal.dependencyMissing(settlementID: settlementID, dependency: dependency)
            }
            if validity != "valid" {
                throw Refusal.dependencyInvalid(settlementID: settlementID, dependency: dependency)
            }
        }
        // 6. Read provenance and representation bindings. Producer/consumer
        // identity is retained for audit, not used as a universal semantic gate.
        // If identity is semantically material to a task, it must be declared by
        // that task's dependency/contract rather than inferred from its backend.
        let recorded = try db.settlementBindings(settlementID: settlementID)
        let derived = row.validationStatus == "DERIVED_CONSUMPTION"
        // 6b. carry the settled prefix representation binding forward. No KV
        // compatibility is inferred here: the engine must recompute and verify the
        // concrete representation before restore. A mismatch declines KV reuse
        // and falls back to cold prefill without discarding the admitted IS value.
        // A derived consumption never records a representation, so it cannot
        // authorize restoration of a producer's KV artifact.
        let kvBindings = derived
            ? [:]
            : SettlementKVBinding.recordedBindings(from: recorded)
        // Producer identity travels with the admission as provenance. Semantic
        // reuse ignores it (post-#169); the physical KV bind site is the one place
        // that turns it into a strict model+tokenizer gate. A derived consumption
        // records consumer.* rows, never a producer KV claim, so it carries none.
        let producerBindings = derived
            ? [:]
            : SettlementIdentityBinding.recordedProducerBindings(from: recorded)
        // 7. recover the settled semantic value; mint verifiedBindings for the new ES.
        guard let value = recoveredValue(from: row.payload, field: valueField), !value.isEmpty else {
            throw Refusal.emptyValue(settlementID: settlementID)
        }
        return Admitted(
            settlementID: settlementID,
            payloadDigest: row.recordedPayloadDigest,
            recoveredValue: value,
            verifiedBindings: [bindingName: .string(value)],
            kvBindings: kvBindings,
            producerBindings: producerBindings
        )
    }

    /// A durable continuation settlement: the verified admission plus the
    /// native-authorized, persisted settlement of the child ES.
    public struct SettledContinuation: Sendable {
        public let admission: Admitted
        public let settled: SettlementAuthority.SettledResult
        public let settlementID: String
    }

    /// The product continuation edge.
    ///
    /// This is the missing READ/recover half of the product ES/IS mechanism: it
    /// recovers the parent's already-settled IS value through native admission
    /// (fail-closed, before the child result is consumed), authorizes the child
    /// ES's generated text against that verified binding through the existing
    /// `SettlementAuthority`, and persists ONLY a contract-validated
    /// settlement linked to the parent state. It composes the existing native
    /// authorities (`ESISDatabase`, `SettlementAuthority`,
    /// `SettlementIdentityBinding`) and adds no second store, no new
    /// settlement authority, and no headless-only chain.
    ///
    /// Ordering guarantees the acceptance invariants:
    ///   * admission runs BEFORE the child contract, so a missing/tampered/
    ///     invalidated/dependency-broken parent throws before the child result is
    ///     processed — no child settlement is created.
    ///   * the native contract runs BEFORE `recordNativeSettlement`, so a contract
    ///     failure throws with nothing written — no partially settled record.
    public static func settleContinuation(
        db: ESISDatabase,
        parentStateID: String,
        consumer: SettlementIdentityBinding.Identity,
        childStateID: String,
        generatedText: String,
        contractJSON: Data,
        parentBindingName: String = "next_input",
        valueField: String = "content"
    ) throws -> SettledContinuation {
        // (1) recover + verify the parent's IS value (fail-closed before child work).
        let admitted = try admit(
            db: db, stateID: parentStateID, consumer: consumer,
            bindingName: parentBindingName, valueField: valueField)
        // (2) authorize the child result against the recovered, verified binding.
        let settled = try SettlementAuthority.authorize(
            generatedText: generatedText, contractJSON: contractJSON,
            verifiedBindings: admitted.verifiedBindings)
        // (3) persist ONLY the contract-cleared settlement, linked to the parent.
        // Each store call manages its own durable transaction; the contract gate
        // already ran above, so a rejection here means nothing was written.
        let childState = ESISDatabase.ChildExecutionState(
            id: childStateID, parentID: parentStateID, modelIdentity: consumer.model,
            position: 1, continuationID: UUID().uuidString, anchor: admitted.payloadDigest,
            createdAt: Date(), nextInput: admitted.recoveredValue)
        let sid = try db.recordNativeSettlementWithIdentity(
            settled, stateID: childStateID, identity: consumer, childState: childState,
            settlementDependencies: [
                .init(settlementID: admitted.settlementID, kind: "continuation-parent")
            ])
        return SettledContinuation(
            admission: admitted, settled: settled, settlementID: sid.uuidString)
    }

    /// Extract the semantic value from a settled canonical payload. Mirrors the
    /// headless reader's accepted shapes (top-level field, `values.<field>`, or
    /// `values.<field>.value`) so the authority reads exactly what was settled.
    private static func recoveredValue(from payload: Data, field: String) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return nil }
        if let direct = obj[field] as? String { return direct }
        if let inner = obj["values"] as? [String: Any] {
            if let value = inner[field] as? String { return value }
            if let wrapped = inner[field] as? [String: Any], let value = wrapped["value"] as? String { return value }
        }
        return nil
    }
}
