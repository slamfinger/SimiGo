import Foundation

/// Typed `recompute_policy` for the managed-continuation entry.
///
/// `never` is the default: a resumed continuation whose inputs no longer match
/// the anchored evidence is refused instead of silently regenerated.
/// `allow_safe_recompute` permits exactly that case, and the commit records that
/// a recompute happened. Any other value is a request-format error, and asking
/// for a policy on a request that carries no managed anchor is one too.
public enum RecomputePolicy: String, Sendable, CaseIterable {
    case never
    case allowSafeRecompute = "allow_safe_recompute"

    public static let requestKey = "recompute_policy"

    /// Resolve the typed policy. The validation order is fixed (interface design
    /// §D2): an unsupported value is reported before the two-entry conflict, so
    /// an invalid value is never described as a conflict. Absence is `.never`
    /// and — unlike presence — never makes two otherwise valid entries conflict.
    public static func resolve(
        managedAnchorPresent: Bool,
        settlementConsumptionPresent: Bool,
        raw: Any?
    ) throws -> RecomputePolicy {
        guard let raw else { return .never }
        guard let text = raw as? String, let policy = RecomputePolicy(rawValue: text) else {
            throw ManagedRefusal.Refusal(
                cause: .recomputePolicyInvalid, origin: .request, phase: .pre,
                evidence: ["field": requestKey, "reason": "unsupported_value"])
        }
        if settlementConsumptionPresent {
            throw ManagedRefusal.Refusal(
                cause: .recomputePolicyConflict, origin: .request, phase: .pre,
                evidence: ["fields": "\(requestKey)+settlement_consumption"])
        }
        guard managedAnchorPresent else {
            throw ManagedRefusal.Refusal(
                cause: .recomputePolicyInvalid, origin: .request, phase: .pre,
                evidence: ["field": requestKey, "reason": "no_managed_anchor"])
        }
        return policy
    }
}

/// Seven-dimension idempotency fingerprint. v1 is globally unique: one execution
/// per fingerprint, regardless of which caller submits it.
public struct IdempotencyFingerprint: Sendable, Equatable {
    public static let dimensions = [
        "anchor_state_id", "anchor_settlement_id", "declared_input_digest",
        "contract", "result_contract", "root_ids", "recompute_policy"
    ]

    public let digest: String
    public let components: [String: String]

    public static func make(
        anchorStateID: String,
        anchorSettlementID: String,
        declaredInputDigest: String,
        contractJSON: Data?,
        rootIDs: [String],
        policy: RecomputePolicy,
        resultContractJSON: Data? = nil
    ) -> IdempotencyFingerprint {
        let components: [String: String] = [
            "anchor_state_id": anchorStateID,
            "anchor_settlement_id": anchorSettlementID,
            "declared_input_digest": declaredInputDigest,
            "contract": contractJSON.map(SnapshotContract.sha256Hex) ?? "-",
            // The task-level RESULT contract is bound separately from the snapshot
            // contract: opening derivation lets one input settle under different
            // task contracts, and those must never share an idempotency key.
            "result_contract": resultContractJSON.map(SnapshotContract.sha256Hex) ?? "-",
            "root_ids": SnapshotContract.sha256Hex(
                Data(rootIDs.sorted().joined(separator: "\u{1f}").utf8)),
            "recompute_policy": policy.rawValue,
        ]
        let canonical = components.keys.sorted()
            .map { "\($0)=\(components[$0]!)" }
            .joined(separator: "\n")
        return IdempotencyFingerprint(
            digest: SnapshotContract.sha256Hex(Data(canonical.utf8)),
            components: components)
    }
}

/// Managed continuation (`previous_es_state_id` + `recompute_policy`).
///
/// Three phases around one model call:
///   P1  read-only: pin the anchor, capture the inputs, decide whether this is a
///       resumption or a permitted recompute, check the idempotency fingerprint.
///   S   write exactly one immutable `declared` snapshot (the as-of draft).
///   G   run the model OUTSIDE any write transaction; `used` stays in memory.
///   P2  one write transaction: re-verify anchor + inputs, re-check `used ⊆
///       declared`, write the `final` snapshot and the settlement that
///       references it, and set the idempotency key — one commit.
///
/// A refusal before G means `model_calls = 0`; a refusal inside P2 means
/// `model_calls > 0` and `settlements_written = 0`. Neither is rewritten into
/// the other, and each attempt writes at most one append-only audit record.
public enum ManagedContinuation {

    public struct Config {
        public let executionID: String
        public let attempt: Int
        public let anchorStateID: String
        public let policy: RecomputePolicy
        public let snapshotRequest: SnapshotContract.Request
        public let childStateID: String
        public let childModelIdentity: String
        public let childPosition: Int
        public let identity: SettlementIdentityBinding.Identity
        public let capturedAt: Date
        /// Caller-supplied opaque key (optional). When present it is the row key;
        /// the seven-dimension fingerprint is still re-checked on replay so the same
        /// key with different inputs is a conflict, never a silent replay.
        public let idempotencyKey: String?

        public init(
            executionID: String, attempt: Int = 1, anchorStateID: String,
            policy: RecomputePolicy,
            snapshotRequest: SnapshotContract.Request,
            childStateID: String, childModelIdentity: String, childPosition: Int,
            identity: SettlementIdentityBinding.Identity,
            capturedAt: Date = Date(),
            idempotencyKey: String? = nil
        ) {
            self.executionID = executionID
            self.attempt = attempt
            self.anchorStateID = anchorStateID
            self.policy = policy
            self.snapshotRequest = snapshotRequest
            self.childStateID = childStateID
            self.childModelIdentity = childModelIdentity
            self.childPosition = childPosition
            self.identity = identity
            self.capturedAt = capturedAt
            self.idempotencyKey = idempotencyKey
        }
    }

    public struct Captured {
        public let entries: [SnapshotContract.DeclaredEntry]
        public let asOf: Date
        public init(entries: [SnapshotContract.DeclaredEntry], asOf: Date = Date()) {
            self.entries = entries
            self.asOf = asOf
        }
    }

    /// Reads and hashes the sources named by the request. Injected so this module
    /// does no file I/O and stays unit-testable.
    public typealias Capture = (SnapshotContract.Request) throws -> Captured

    /// The model call plus the native settlement gate. Runs OUTSIDE any write
    /// transaction; it may throw, and nothing is committed when it does.
    public struct Generated {
        public let used: [SnapshotContract.UsedItem]
        public let settled: SettlementAuthority.SettledResult
        public let nextInput: String
        public init(used: [SnapshotContract.UsedItem],
                    settled: SettlementAuthority.SettledResult,
                    nextInput: String) {
            self.used = used
            self.settled = settled
            self.nextInput = nextInput
        }
    }

    public typealias Generate = (SnapshotContract.Declared) async throws -> Generated

    public struct Committed: Equatable, Sendable {
        public let executionID: String
        public let childStateID: String
        public let settlementID: String
        public let declaredSnapshotID: String
        public let finalSnapshotID: String
        public let fingerprint: String
        public let modelCalls: Int
        public let settlementsWritten: Int
        public let replayable: Bool?
        public let recomputed: Bool
        /// True when an identical execution already existed and nothing was run.
        public let reusedExecution: Bool
    }

    public enum Outcome: Equatable, Sendable {
        case committed(Committed)
        /// `auditPersisted` reports what actually reached the store; a failed
        /// audit write never changes the terminal result.
        case refused(ManagedRefusal.Refusal, auditPersisted: Bool)
    }

    /// Runs one managed continuation attempt.
    ///
    /// Throws only for failures that are NOT refusals (a model failure, or a
    /// storage failure in P2): those keep the entry's existing classification.
    /// Refusals are returned so the caller can map them through
    /// `ManagedRefusal.external(_:entry:)`.
    public static func run(
        db: ESISDatabase,
        config: Config,
        capture: @escaping Capture,
        generate: Generate,
        now: Date = Date()
    ) async throws -> Outcome {
        try Task.checkCancellation()
        // ---- P1 (read-only) -------------------------------------------------
        let anchor: PinnedAnchor
        do {
            anchor = try pinAnchor(db: db, stateID: config.anchorStateID)
        } catch let refusal as ManagedRefusal.Refusal {
            return refuse(db: db, config: config, refusal: refusal,
                          modelCalls: 0, settlementsWritten: 0)
        }

        let captured: Captured
        do {
            captured = try capture(config.snapshotRequest)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return refuse(db: db, config: config,
                          refusal: .init(cause: .snapshotSourceUnreadable, origin: .snapshot,
                                         phase: .p1, evidence: ["reason": "capture_failed"]),
                          modelCalls: 0, settlementsWritten: 0)
        }

        try Task.checkCancellation()
        let declared = SnapshotContract.Declared(
            capturedAt: captured.asOf, request: config.snapshotRequest,
            anchor: SnapshotContract.Anchor(
                stateID: anchor.stateID, settlementID: anchor.settlementID,
                payloadDigest: anchor.payloadDigest),
            entries: captured.entries)

        let currentDigest: String
        do {
            currentDigest = try declared.computeDeclaredInputDigest(phase: "P1")
        } catch let error as SnapshotContract.SnapshotError {
            return refuse(db: db, config: config, refusal: refusal(from: error),
                          modelCalls: 0, settlementsWritten: 0)
        }

        var recomputed = false
        if let priorDigest = try priorDeclaredInputDigest(
            db: db, settlementID: anchor.settlementID), priorDigest != currentDigest {
            guard config.policy == .allowSafeRecompute else {
                return refuse(db: db, config: config,
                              refusal: .init(
                                cause: .snapshotInconsistent, origin: .snapshot, phase: .p1,
                                evidence: ["expected": priorDigest, "actual": currentDigest]),
                              modelCalls: 0, settlementsWritten: 0)
            }
            recomputed = true
        }

        let fingerprint = IdempotencyFingerprint.make(
            anchorStateID: anchor.stateID,
            anchorSettlementID: anchor.settlementID,
            declaredInputDigest: currentDigest,
            contractJSON: config.snapshotRequest.contractJSON,
            rootIDs: config.snapshotRequest.rootIDs,
            policy: config.policy,
            // The managed entry settles under this same contract (one contract for
            // snapshot + gate), so the result-contract dimension is re-derivable on
            // replay from the persisted declared request.
            resultContractJSON: config.snapshotRequest.contractJSON)

        let executionKey = config.idempotencyKey ?? fingerprint.digest

        if let owner = try db.executionStateID(idempotencyKey: executionKey) {
            // Lookup by key alone is not proof of equality: with a caller key the
            // same key may describe different inputs. Only a committed execution
            // whose seven-dimension fingerprint is identical is a replay; anything
            // else proceeds and is refused inside P2's write transaction.
            if try committedFingerprint(db: db, stateID: owner) == fingerprint.digest {
                guard let settlementID = try db.latestSettlementID(forStateID: owner),
                      let finalID = try db.settlementInputSnapshotObjectID(settlementID: settlementID)
                else {
                    throw ESISDatabase.DatabaseError.sql(
                        "ManagedContinuation replay: committed owner has no final snapshot")
                }
                let (priorFinal, _) = try verifiedSnapshotPair(
                    db: db, finalSnapshotID: finalID)
                return .committed(Committed(
                    executionID: config.executionID, childStateID: owner,
                    settlementID: settlementID,
                    declaredSnapshotID: priorFinal.declaredSnapshotID,
                    finalSnapshotID: finalID, fingerprint: fingerprint.digest,
                    modelCalls: 0, settlementsWritten: 0, replayable: priorFinal.replayable,
                    recomputed: false, reusedExecution: true))
            }
        }

        // ---- S (one immutable declared snapshot) ----------------------------
        let declaredBytes: Data
        do {
            declaredBytes = try declared.encoded()
        } catch let error as SnapshotContract.SnapshotError {
            return refuse(db: db, config: config, refusal: refusal(from: error),
                          modelCalls: 0, settlementsWritten: 0)
        }
        try Task.checkCancellation()
        let declaredID = try db.writeObject(declaredBytes)

        // ---- G (model call, outside any write transaction) ------------------
        try Task.checkCancellation()
        let generated = try await generate(declared)
        try Task.checkCancellation()

        // ---- P2 (single write transaction) ----------------------------------
        let final: SnapshotContract.Final
        do {
            final = try SnapshotContract.Final.make(
                declared: declared, declaredSnapshotID: declaredID,
                used: generated.used, verifiedAsOf: now,
                recheck: ["anchor": "rechecked", "closure": "rechecked",
                          "sources": "rechecked", "policy": config.policy.rawValue],
                capturedAt: now)
        } catch let error as SnapshotContract.SnapshotError {
            return refuse(db: db, config: config, refusal: refusal(from: error),
                          modelCalls: 1, settlementsWritten: 0)
        }

        let finalBytes: Data
        do {
            finalBytes = try final.encoded()
        } catch let error as SnapshotContract.SnapshotError {
            return refuse(db: db, config: config, refusal: refusal(from: error),
                          modelCalls: 1, settlementsWritten: 0)
        }

        let childState = ESISDatabase.ChildExecutionState(
            id: config.childStateID, parentID: anchor.stateID,
            modelIdentity: config.childModelIdentity,
            position: config.childPosition,
            continuationID: config.executionID, anchor: anchor.payloadDigest,
            createdAt: now, nextInput: generated.nextInput)

        let plan = ESISDatabase.ManagedContinuationPlan(
            executionID: config.executionID, attempt: config.attempt,
            idempotencyKey: executionKey, fingerprint: fingerprint.digest,
            finalSnapshot: finalBytes, settled: generated.settled,
            identity: config.identity, childState: childState,
            preCommit: {
                // Re-verify while the write lock is held: the anchor must not
                // have advanced, and the sources must still hash to the inputs
                // the model actually saw. File reads happen here on purpose —
                // this is the last point at which a change can still be refused
                // before anything is committed.
                let rechecked = try pinAnchor(db: db, stateID: config.anchorStateID)
                guard rechecked.settlementID == anchor.settlementID,
                      rechecked.payloadDigest == anchor.payloadDigest else {
                    throw ManagedRefusal.Refusal(
                        cause: .invalidAnchor, origin: .snapshot, phase: .p2,
                        evidence: ["state_id": config.anchorStateID,
                                   "reason": "anchor_advanced"])
                }
                let recaptured = try capture(config.snapshotRequest)
                let reDeclared = SnapshotContract.Declared(
                    capturedAt: captured.asOf, request: config.snapshotRequest,
                    anchor: SnapshotContract.Anchor(
                        stateID: anchor.stateID, settlementID: anchor.settlementID,
                        payloadDigest: anchor.payloadDigest),
                    entries: recaptured.entries)
                let recheckDigest = try reDeclared.computeDeclaredInputDigest(phase: "P2")
                guard recheckDigest == currentDigest else {
                    throw ManagedRefusal.Refusal(
                        cause: .snapshotUnstable, origin: .snapshot, phase: .p2,
                        evidence: ["expected": currentDigest, "actual": recheckDigest])
                }
            })

        let commit: ESISDatabase.ManagedContinuationCommit
        do {
            commit = try db.commitManagedContinuation(plan)
        } catch let refusal as ManagedRefusal.Refusal {
            return refuse(db: db, config: config, refusal: refusal,
                          modelCalls: 1, settlementsWritten: 0)
        } catch {
            // Not a refusal: the caller's entry keeps its own classification.
            // The audit still records that the model ran and nothing settled.
            _ = audit(db: db, config: config, phase: .p2, refusal: nil,
                      modelCalls: 1, settlementsWritten: 0,
                      detail: "managed_commit_failed")
            throw error
        }

        return .committed(Committed(
            executionID: config.executionID, childStateID: config.childStateID,
            settlementID: commit.settlementID, declaredSnapshotID: declaredID,
            finalSnapshotID: commit.finalSnapshotObjectID,
            fingerprint: fingerprint.digest, modelCalls: 1, settlementsWritten: 1,
            replayable: final.replayable, recomputed: recomputed,
            reusedExecution: false))
    }

    // MARK: - Anchor pinning

    struct PinnedAnchor {
        let stateID: String
        let settlementID: String
        let payloadDigest: String
        let position: Int
    }

    static func pinAnchor(db: ESISDatabase, stateID: String) throws -> PinnedAnchor {
        guard let position = try db.executionStatePosition(stateID) else {
            throw ManagedRefusal.Refusal(
                cause: .invalidAnchor, origin: .admission, phase: .p1,
                evidence: ["state_id": stateID, "reason": "unknown_state"])
        }
        guard let settlementID = try db.latestSettlementID(forStateID: stateID) else {
            throw ManagedRefusal.Refusal(
                cause: .noSettlement, origin: .admission, phase: .p1,
                evidence: ["state_id": stateID])
        }
        guard let digest = try db.settlementPayloadDigest(settlementID),
              SnapshotContract.isValidDigest(digest) else {
            throw ManagedRefusal.Refusal(
                cause: .digestMismatch, origin: .admission, phase: .p1,
                evidence: ["settlement_id": settlementID, "reason": "missing_or_malformed_digest"])
        }
        return PinnedAnchor(
            stateID: stateID, settlementID: settlementID,
            payloadDigest: digest, position: position)
    }

    /// The declared-input digest of the snapshot the anchor settlement committed
    /// with, when it has one. Rows predating snapshot capture report nil, which
    /// means "no prior evidence to compare", never "unchanged".
    /// Nil is reserved for legacy settlements with no snapshot object ID.
    /// Once an ID exists, missing/corrupt bytes or a mismatched final/declared
    /// pair are storage-integrity failures and must not become "no prior evidence".
    static func priorDeclaredInputDigest(
        db: ESISDatabase, settlementID: String
    ) throws -> String? {
        guard let objectID = try db.settlementInputSnapshotObjectID(settlementID: settlementID)
        else { return nil }
        let (prior, _) = try verifiedSnapshotPair(db: db, finalSnapshotID: objectID)
        return prior.declaredInputDigest
    }

    /// Re-derive the seven-dimension fingerprint an already-committed execution
    /// recorded, from its final + declared snapshot objects. nil means "this
    /// owner carries no comparable evidence", which is never treated as equal.
    static func committedFingerprint(
        db: ESISDatabase, stateID: String
    ) throws -> String? {
        guard let settlementID = try db.latestSettlementID(forStateID: stateID),
              let objectID = try db.settlementInputSnapshotObjectID(settlementID: settlementID)
        else { return nil }
        let (priorFinal, priorDeclared) = try verifiedSnapshotPair(
            db: db, finalSnapshotID: objectID)
        let policy = priorDeclared.request.recomputePolicy
            .flatMap(RecomputePolicy.init(rawValue:)) ?? .never
        return IdempotencyFingerprint.make(
            anchorStateID: priorDeclared.anchor.stateID,
            anchorSettlementID: priorDeclared.anchor.settlementID,
            declaredInputDigest: priorFinal.declaredInputDigest,
            contractJSON: priorDeclared.request.contractJSON,
            rootIDs: priorDeclared.request.rootIDs,
            policy: policy,
            resultContractJSON: priorDeclared.request.contractJSON).digest
    }

    /// Read and cross-verify both immutable objects. This is shared by anchor
    /// comparison and idempotent replay so a missing/corrupt declared object or a
    /// final snapshot that points at the wrong declared digest always propagates.
    private static func verifiedSnapshotPair(
        db: ESISDatabase, finalSnapshotID: String
    ) throws -> (SnapshotContract.Final, SnapshotContract.Declared) {
        let final = try SnapshotContract.Final.decode(db.readObject(finalSnapshotID))
        let declared = try SnapshotContract.Declared.decode(
            db.readObject(final.declaredSnapshotID))
        try final.verify(against: declared)
        return (final, declared)
    }

    // MARK: - Refusals and audit

    private static func refuse(
        db: ESISDatabase, config: Config,
        refusal: ManagedRefusal.Refusal,
        modelCalls: Int, settlementsWritten: Int
    ) -> Outcome {
        let persisted = audit(
            db: db, config: config, phase: refusal.phase, refusal: refusal,
            modelCalls: modelCalls, settlementsWritten: settlementsWritten,
            detail: refusal.errorDescription ?? refusal.cause.rawValue)
        return .refused(refusal, auditPersisted: persisted)
    }

    @discardableResult
    private static func audit(
        db: ESISDatabase, config: Config,
        phase: ManagedRefusal.Phase,
        refusal: ManagedRefusal.Refusal?,
        modelCalls: Int, settlementsWritten: Int, detail: String
    ) -> Bool {
        let event = FailureAudit.Event(
            executionID: config.executionID, attempt: config.attempt, phase: phase,
            cause: refusal?.cause, origin: refusal?.origin ?? .snapshot,
            evidence: refusal?.evidence ?? [:],
            modelCalls: modelCalls, settlementsWritten: settlementsWritten,
            detail: detail)
        return db.recordFailureAudit(event).auditPersisted
    }

    /// Snapshot-contract errors are internal; only the four allowlisted codes can
    /// ever leave as a public `reasonCode`.
    static func refusal(from error: SnapshotContract.SnapshotError) -> ManagedRefusal.Refusal {
        let cause: ManagedRefusal.Cause
        switch error.code {
        case "snapshot_used_undeclared": cause = .snapshotUsedUndeclared
        case "snapshot_used_mismatch": cause = .snapshotUsedMismatch
        case "snapshot_unrepresentable": cause = .snapshotUnrepresentable
        case "snapshot_schema_unknown", "snapshot_part_unknown",
             "snapshot_replayable_mismatch", "snapshot_digest_mismatch":
            cause = .snapshotInconsistent
        default:
            cause = .snapshotInconsistent
        }
        let phase = ManagedRefusal.Phase(rawValue: error.phase.uppercased()) ?? .p1
        return ManagedRefusal.Refusal(
            cause: cause, origin: .snapshot, phase: phase,
            evidence: ["snapshot_code": error.code])
    }
}
