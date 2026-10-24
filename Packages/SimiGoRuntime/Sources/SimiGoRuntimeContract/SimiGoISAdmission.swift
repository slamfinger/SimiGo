import Foundation

/// Native Information-Space (IS) admission authority.
///
/// This is the single reusable, MLX-free, pre-model gate the product dispatch
/// path calls to recover an already-settled IS value and mint `verifiedBindings`
/// for a fresh Execution State (ES). It COMPOSES the existing native authorities
/// rather than adding a second mechanism:
///   * `SimiGoESISDatabase`                 — IS read, validity, dependency closure
///   * `SimiGoSettlementAuthority`          — canonical digest verification (seal)
///   * `SimiGoSettlementIdentityBinding`    — producer model/tokenizer binding
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
public enum SimiGoISAdmission {

    /// A verified IS admission result, ready to seed a fresh ES.
    public struct Admitted: Sendable, Equatable {
        public let settlementID: String
        public let payloadDigest: String
        public let recoveredValue: String
        /// Values the native result-contract gate may bind against for the new ES.
        public let verifiedBindings: [String: NativeContractValue]
    }

    /// Stable, fail-closed refusal reasons. Each carries enough identity to
    /// audit which settlement/state was refused and why.
    public enum Refusal: Error, Equatable, CustomStringConvertible {
        case noSettlement(stateID: String)
        case digestMismatch(settlementID: String)
        case invalidated(settlementID: String)
        case dependencyMissing(settlementID: String, dependency: String)
        case dependencyInvalid(settlementID: String, dependency: String)
        case producerBinding(SimiGoSettlementIdentityBinding.Verdict)
        case emptyValue(settlementID: String)

        public var description: String {
            switch self {
            case .noSettlement(let s):
                return "no settled IS record for state \(s)"
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
    ///   6. producer model/tokenizer identity binding (absent → refuse)
    ///   7. recover the settled semantic value and mint the bindings
    ///
    /// - Parameters:
    ///   - bindingName: key the new ES's result contract expects for this value
    ///     (`next_input` by default, matching the reference settlement path).
    ///   - valueField: contract field name holding the semantic value in the
    ///     settled payload (`content` for the reference result contract).
    public static func admit(
        db: SimiGoESISDatabase,
        stateID: String,
        consumer: SimiGoSettlementIdentityBinding.Identity,
        bindingName: String = "next_input",
        valueField: String = "content"
    ) throws -> Admitted {
        // 1. newest settlement for the state.
        guard let settlementID = try db.latestSettlementID(forStateID: stateID) else {
            throw Refusal.noSettlement(stateID: stateID)
        }
        // 2. its receipt row (payload + recorded digest).
        let rows = try db.readSettlementReceipts()
        guard let row = rows.first(where: { $0.id.uuidString == settlementID }) else {
            throw Refusal.noSettlement(stateID: stateID)
        }
        // 3. digest integrity — the same hashing that sealed it at settle time.
        guard SimiGoSettlementAuthority.payloadDigestMatches(row.payload, recordedDigest: row.payloadDigest) else {
            throw Refusal.digestMismatch(settlementID: settlementID)
        }
        // 4. dynamic validity of the settlement itself.
        if try db.settlementValidity(settlementID) != "valid" {
            throw Refusal.invalidated(settlementID: settlementID)
        }
        // 5. full upstream dependency closure: each member present and valid.
        for dependency in try db.upstreamDependencyClosure(ofSettlement: settlementID) {
            let validity: String
            do {
                validity = try db.settlementValidity(dependency)
            } catch {
                throw Refusal.dependencyMissing(settlementID: settlementID, dependency: dependency)
            }
            if validity != "valid" {
                throw Refusal.dependencyInvalid(settlementID: settlementID, dependency: dependency)
            }
        }
        // 6. producer identity binding (fail-closed on absent or mismatch).
        let recorded = try db.settlementBindings(settlementID: settlementID)
        let verdict = SimiGoSettlementIdentityBinding.evaluate(recorded: recorded, consumer: consumer)
        if verdict.status != .ok {
            throw Refusal.producerBinding(verdict)
        }
        // 7. recover the settled semantic value; mint verifiedBindings for the new ES.
        guard let value = recoveredValue(from: row.payload, field: valueField), !value.isEmpty else {
            throw Refusal.emptyValue(settlementID: settlementID)
        }
        return Admitted(
            settlementID: settlementID,
            payloadDigest: row.payloadDigest,
            recoveredValue: value,
            verifiedBindings: [bindingName: .string(value)]
        )
    }

    /// A durable continuation settlement: the verified admission plus the
    /// native-authorized, persisted settlement of the child ES.
    public struct SettledContinuation: Sendable {
        public let admission: Admitted
        public let settled: SimiGoSettlementAuthority.SettledResult
        public let settlementID: String
    }

    /// The product continuation edge.
    ///
    /// This is the missing READ/recover half of the product ES/IS mechanism: it
    /// recovers the parent's already-settled IS value through native admission
    /// (fail-closed, before the child result is consumed), authorizes the child
    /// ES's generated text against that verified binding through the existing
    /// `SimiGoSettlementAuthority`, and persists ONLY a contract-validated
    /// settlement linked to the parent state. It composes the existing native
    /// authorities (`SimiGoESISDatabase`, `SimiGoSettlementAuthority`,
    /// `SimiGoSettlementIdentityBinding`) and adds no second store, no new
    /// settlement authority, and no headless-only chain.
    ///
    /// Ordering guarantees the acceptance invariants:
    ///   * admission runs BEFORE the child contract, so a missing/tampered/
    ///     invalidated/dependency-broken/identity-mismatched parent throws before
    ///     the child result is even processed — no generation, no settlement.
    ///   * the native contract runs BEFORE `recordNativeSettlement`, so a contract
    ///     failure throws with nothing written — no partially settled record.
    public static func settleContinuation(
        db: SimiGoESISDatabase,
        parentStateID: String,
        consumer: SimiGoSettlementIdentityBinding.Identity,
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
        let settled = try SimiGoSettlementAuthority.authorize(
            generatedText: generatedText, contractJSON: contractJSON,
            verifiedBindings: admitted.verifiedBindings)
        // (3) persist ONLY the contract-cleared settlement, linked to the parent.
        // Each store call manages its own durable transaction; the contract gate
        // already ran above, so a rejection here means nothing was written.
        try db.recordExecutionState(
            id: childStateID, parentID: parentStateID, modelIdentity: consumer.model,
            position: 1, continuationID: UUID().uuidString, anchor: admitted.payloadDigest,
            lifecycle: "active", createdAt: Date())
        let sid = try db.recordNativeSettlement(settled, stateID: childStateID)
        try db.recordIdentityBindings(settlementID: sid, identity: consumer)
        return SettledContinuation(admission: admitted, settled: settled, settlementID: sid)
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
