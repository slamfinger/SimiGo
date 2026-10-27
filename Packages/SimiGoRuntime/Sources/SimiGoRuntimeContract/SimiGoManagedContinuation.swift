import Foundation

/// Typed `recompute_policy` for the managed-continuation entry.
///
/// `never` is the default: a resumed continuation whose inputs no longer match
/// the anchored evidence is refused instead of silently regenerated.
/// `allow_safe_recompute` permits exactly that case, and the commit records that
/// a recompute happened. Any other value is a request-format error, and asking
/// for a policy on a request that carries no managed anchor is one too.
public enum SimiGoRecomputePolicy: String, Sendable, CaseIterable {
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
    ) throws -> SimiGoRecomputePolicy {
        guard let raw else { return .never }
        guard let text = raw as? String, let policy = SimiGoRecomputePolicy(rawValue: text) else {
            throw SimiGoManagedRefusal.Refusal(
                cause: .recomputePolicyInvalid, origin: .request, phase: .pre,
                evidence: ["field": requestKey, "reason": "unsupported_value"])
        }
        if settlementConsumptionPresent {
            throw SimiGoManagedRefusal.Refusal(
                cause: .recomputePolicyConflict, origin: .request, phase: .pre,
                evidence: ["fields": "\(requestKey)+settlement_consumption"])
        }
        guard managedAnchorPresent else {
            throw SimiGoManagedRefusal.Refusal(
                cause: .recomputePolicyInvalid, origin: .request, phase: .pre,
                evidence: ["field": requestKey, "reason": "no_managed_anchor"])
        }
        return policy
    }
}

/// Six-dimension idempotency fingerprint. v1 is globally unique: one execution
/// per fingerprint, regardless of which caller submits it.
public struct SimiGoIdempotencyFingerprint: Sendable, Equatable {
    public static let dimensions = [
        "anchor_state_id", "anchor_settlement_id", "declared_input_digest",
        "contract", "root_ids", "recompute_policy"
    ]

    public let digest: String
    public let components: [String: String]

    public static func make(
        anchorStateID: String,
        anchorSettlementID: String,
        declaredInputDigest: String,
        contractJSON: Data?,
        rootIDs: [String],
        policy: SimiGoRecomputePolicy
    ) -> SimiGoIdempotencyFingerprint {
        let components: [String: String] = [
            "anchor_state_id": anchorStateID,
            "anchor_settlement_id": anchorSettlementID,
            "declared_input_digest": declaredInputDigest,
            "contract": contractJSON.map(SimiGoSnapshotContract.sha256Hex) ?? "-",
            "root_ids": SimiGoSnapshotContract.sha256Hex(
                Data(rootIDs.sorted().joined(separator: "\u{1f}").utf8)),
            "recompute_policy": policy.rawValue,
        ]
        let canonical = components.keys.sorted()
            .map { "\($0)=\(components[$0]!)" }
            .joined(separator: "\n")
        return SimiGoIdempotencyFingerprint(
            digest: SimiGoSnapshotContract.sha256Hex(Data(canonical.utf8)),
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
public enum SimiGoManagedContinuation {

    public struct Config {
        public let executionID: String
        public let attempt: Int
        public let anchorStateID: String
        public let policy: SimiGoRecomputePolicy
        public let snapshotRequest: SimiGoSnapshotContract.Request
        public let childStateID: String
        public let childModelIdentity: String
        public let childPosition: Int
        public let identity: SimiGoSettlementIdentityBinding.Identity
        public let capturedAt: Date
        /// Caller-supplied opaque key (optional). When present it is the row key;
        /// the six-dimension fingerprint is still re-checked on replay so the same
        /// key with different inputs is a conflict, never a silent replay.
        public let idempotencyKey: String?

        public init(
            executionID: String, attempt: Int = 1, anchorStateID: String,
            policy: SimiGoRecomputePolicy,
            snapshotRequest: SimiGoSnapshotContract.Request,
            childStateID: String, childModelIdentity: String, childPosition: Int,
            identity: SimiGoSettlementIdentityBinding.Identity,
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
        public let entries: [SimiGoSnapshotContract.DeclaredEntry]
        public let asOf: Date
        public init(entries: [SimiGoSnapshotContract.DeclaredEntry], asOf: Date = Date()) {
            self.entries = entries
            self.asOf = asOf
        }
    }

    /// Reads and hashes the sources named by the request. Injected so this module
    /// does no file I/O and stays unit-testable.
    public typealias Capture = (SimiGoSnapshotContract.Request) throws -> Captured

    /// The model call plus the native settlement gate. Runs OUTSIDE any write
    /// transaction; it may throw, and nothing is committed when it does.
    public struct Generated {
        public let used: [SimiGoSnapshotContract.UsedItem]
        public let settled: SimiGoSettlementAuthority.SettledResult
        public let nextInput: String
        public init(used: [SimiGoSnapshotContract.UsedItem],
                    settled: SimiGoSettlementAuthority.SettledResult,
                    nextInput: String) {
            self.used = used
            self.settled = settled
            self.nextInput = nextInput
        }
    }

    public typealias Generate = (SimiGoSnapshotContract.Declared) async throws -> Generated

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
        case refused(SimiGoManagedRefusal.Refusal, auditPersisted: Bool)
    }

    /// Runs one managed continuation attempt.
    ///
    /// Throws only for failures that are NOT refusals (a model failure, or a
    /// storage failure in P2): those keep the entry's existing classification.
    /// Refusals are returned so the caller can map them through
    /// `SimiGoManagedRefusal.external(_:entry:)`.
    public static func run(
        db: SimiGoESISDatabase,
        config: Config,
        capture: @escaping Capture,
        generate: Generate,
        now: Date = Date()
    ) async throws -> Outcome {
        // ---- P1 (read-only) -------------------------------------------------
        let anchor: PinnedAnchor
        do {
            anchor = try pinAnchor(db: db, stateID: config.anchorStateID)
        } catch let refusal as SimiGoManagedRefusal.Refusal {
            return refuse(db: db, config: config, refusal: refusal,
                          modelCalls: 0, settlementsWritten: 0)
        }

        let captured: Captured
        do {
            captured = try capture(config.snapshotRequest)
        } catch {
            return refuse(db: db, config: config,
                          refusal: .init(cause: .snapshotSourceUnreadable, origin: .snapshot,
                                         phase: .p1, evidence: ["reason": "capture_failed"]),
                          modelCalls: 0, settlementsWritten: 0)
        }

        let declared = SimiGoSnapshotContract.Declared(
            capturedAt: captured.asOf, request: config.snapshotRequest,
            anchor: SimiGoSnapshotContract.Anchor(
                stateID: anchor.stateID, settlementID: anchor.settlementID,
                payloadDigest: anchor.payloadDigest),
            entries: captured.entries)

        let currentDigest: String
        do {
            currentDigest = try declared.computeDeclaredInputDigest(phase: "P1")
        } catch let error as SimiGoSnapshotContract.SnapshotError {
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

        let fingerprint = SimiGoIdempotencyFingerprint.make(
            anchorStateID: anchor.stateID,
            anchorSettlementID: anchor.settlementID,
            declaredInputDigest: currentDigest,
            contractJSON: config.snapshotRequest.contractJSON,
            rootIDs: config.snapshotRequest.rootIDs,
            policy: config.policy)

        let executionKey = config.idempotencyKey ?? fingerprint.digest

        if let owner = try db.executionStateID(idempotencyKey: executionKey) {
            // Lookup by key alone is not proof of equality: with a caller key the
            // same key may describe different inputs. Only a committed execution
            // whose six-dimension fingerprint is identical is a replay; anything
            // else proceeds and is refused inside P2's write transaction.
            if try committedFingerprint(db: db, stateID: owner) == fingerprint.digest {
                let settlementID = try db.latestSettlementID(forStateID: owner) ?? ""
                let finalID = try db.settlementInputSnapshotObjectID(settlementID: settlementID)
                var declaredID = ""
                var replayable: Bool?
                if let finalID, let data = try? db.readObject(finalID),
                   let prior = try? SimiGoSnapshotContract.Final.decode(data) {
                    declaredID = prior.declaredSnapshotID
                    replayable = prior.replayable
                }
                return .committed(Committed(
                    executionID: config.executionID, childStateID: owner,
                    settlementID: settlementID, declaredSnapshotID: declaredID,
                    finalSnapshotID: finalID ?? "", fingerprint: fingerprint.digest,
                    modelCalls: 0, settlementsWritten: 0, replayable: replayable,
                    recomputed: false, reusedExecution: true))
            }
        }

        // ---- S (one immutable declared snapshot) ----------------------------
        let declaredBytes: Data
        do {
            declaredBytes = try declared.encoded()
        } catch let error as SimiGoSnapshotContract.SnapshotError {
            return refuse(db: db, config: config, refusal: refusal(from: error),
                          modelCalls: 0, settlementsWritten: 0)
        }
        let declaredID = try db.writeObject(declaredBytes)

        // ---- G (model call, outside any write transaction) ------------------
        let generated = try await generate(declared)

        // ---- P2 (single write transaction) ----------------------------------
        let final: SimiGoSnapshotContract.Final
        do {
            final = try SimiGoSnapshotContract.Final.make(
                declared: declared, declaredSnapshotID: declaredID,
                used: generated.used, verifiedAsOf: now,
                recheck: ["anchor": "rechecked", "closure": "rechecked",
                          "sources": "rechecked", "policy": config.policy.rawValue],
                capturedAt: now)
        } catch let error as SimiGoSnapshotContract.SnapshotError {
            return refuse(db: db, config: config, refusal: refusal(from: error),
                          modelCalls: 1, settlementsWritten: 0)
        }

        let finalBytes: Data
        do {
            finalBytes = try final.encoded()
        } catch let error as SimiGoSnapshotContract.SnapshotError {
            return refuse(db: db, config: config, refusal: refusal(from: error),
                          modelCalls: 1, settlementsWritten: 0)
        }

        let childState = SimiGoESISDatabase.ChildExecutionState(
            id: config.childStateID, parentID: anchor.stateID,
            modelIdentity: config.childModelIdentity,
            position: config.childPosition,
            continuationID: config.executionID, anchor: anchor.payloadDigest,
            createdAt: now, nextInput: generated.nextInput)

        let plan = SimiGoESISDatabase.ManagedContinuationPlan(
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
                    throw SimiGoManagedRefusal.Refusal(
                        cause: .invalidAnchor, origin: .snapshot, phase: .p2,
                        evidence: ["state_id": config.anchorStateID,
                                   "reason": "anchor_advanced"])
                }
                let recaptured = try capture(config.snapshotRequest)
                let reDeclared = SimiGoSnapshotContract.Declared(
                    capturedAt: captured.asOf, request: config.snapshotRequest,
                    anchor: SimiGoSnapshotContract.Anchor(
                        stateID: anchor.stateID, settlementID: anchor.settlementID,
                        payloadDigest: anchor.payloadDigest),
                    entries: recaptured.entries)
                let recheckDigest = try reDeclared.computeDeclaredInputDigest(phase: "P2")
                guard recheckDigest == currentDigest else {
                    throw SimiGoManagedRefusal.Refusal(
                        cause: .snapshotUnstable, origin: .snapshot, phase: .p2,
                        evidence: ["expected": currentDigest, "actual": recheckDigest])
                }
            })

        let commit: SimiGoESISDatabase.ManagedContinuationCommit
        do {
            commit = try db.commitManagedContinuation(plan)
        } catch let refusal as SimiGoManagedRefusal.Refusal {
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

    static func pinAnchor(db: SimiGoESISDatabase, stateID: String) throws -> PinnedAnchor {
        guard let position = try db.executionStatePosition(stateID) else {
            throw SimiGoManagedRefusal.Refusal(
                cause: .invalidAnchor, origin: .admission, phase: .p1,
                evidence: ["state_id": stateID, "reason": "unknown_state"])
        }
        guard let settlementID = try db.latestSettlementID(forStateID: stateID) else {
            throw SimiGoManagedRefusal.Refusal(
                cause: .noSettlement, origin: .admission, phase: .p1,
                evidence: ["state_id": stateID])
        }
        guard let digest = try db.settlementPayloadDigest(settlementID),
              SimiGoSnapshotContract.isValidDigest(digest) else {
            throw SimiGoManagedRefusal.Refusal(
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
    static func priorDeclaredInputDigest(
        db: SimiGoESISDatabase, settlementID: String
    ) throws -> String? {
        guard let objectID = try db.settlementInputSnapshotObjectID(settlementID: settlementID),
              let data = try? db.readObject(objectID),
              let prior = try? SimiGoSnapshotContract.Final.decode(data) else { return nil }
        return prior.declaredInputDigest
    }

    /// Re-derive the six-dimension fingerprint an already-committed execution
    /// recorded, from its final + declared snapshot objects. nil means "this
    /// owner carries no comparable evidence", which is never treated as equal.
    static func committedFingerprint(
        db: SimiGoESISDatabase, stateID: String
    ) throws -> String? {
        guard let settlementID = try db.latestSettlementID(forStateID: stateID),
              let objectID = try db.settlementInputSnapshotObjectID(settlementID: settlementID),
              let finalData = try? db.readObject(objectID),
              let priorFinal = try? SimiGoSnapshotContract.Final.decode(finalData),
              let declaredData = try? db.readObject(priorFinal.declaredSnapshotID),
              let priorDeclared = try? SimiGoSnapshotContract.Declared.decode(declaredData)
        else { return nil }
        let policy = priorDeclared.request.recomputePolicy
            .flatMap(SimiGoRecomputePolicy.init(rawValue:)) ?? .never
        return SimiGoIdempotencyFingerprint.make(
            anchorStateID: priorDeclared.anchor.stateID,
            anchorSettlementID: priorDeclared.anchor.settlementID,
            declaredInputDigest: priorFinal.declaredInputDigest,
            contractJSON: priorDeclared.request.contractJSON,
            rootIDs: priorDeclared.request.rootIDs,
            policy: policy).digest
    }

    // MARK: - Refusals and audit

    private static func refuse(
        db: SimiGoESISDatabase, config: Config,
        refusal: SimiGoManagedRefusal.Refusal,
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
        db: SimiGoESISDatabase, config: Config,
        phase: SimiGoManagedRefusal.Phase,
        refusal: SimiGoManagedRefusal.Refusal?,
        modelCalls: Int, settlementsWritten: Int, detail: String
    ) -> Bool {
        let event = SimiGoFailureAudit.Event(
            executionID: config.executionID, attempt: config.attempt, phase: phase,
            cause: refusal?.cause, origin: refusal?.origin ?? .snapshot,
            evidence: refusal?.evidence ?? [:],
            modelCalls: modelCalls, settlementsWritten: settlementsWritten,
            detail: detail)
        return db.recordFailureAudit(event).auditPersisted
    }

    /// Snapshot-contract errors are internal; only the four allowlisted codes can
    /// ever leave as a public `reasonCode`.
    static func refusal(from error: SimiGoSnapshotContract.SnapshotError) -> SimiGoManagedRefusal.Refusal {
        let cause: SimiGoManagedRefusal.Cause
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
        let phase = SimiGoManagedRefusal.Phase(rawValue: error.phase.uppercased()) ?? .p1
        return SimiGoManagedRefusal.Refusal(
            cause: cause, origin: .snapshot, phase: phase,
            evidence: ["snapshot_code": error.code])
    }
}
