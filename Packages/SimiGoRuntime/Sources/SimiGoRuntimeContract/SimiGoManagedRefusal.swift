import Foundation

/// C-stage managed-continuation refusal classification and append-only failure
/// audit.
///
/// Two rules from the owner rulings are enforced structurally here:
///   * a public `reasonCode` is an explicit allowlist, never the internal cause
///     enum — new internal cases do not become public API codes by existing;
///   * an audit record is a new immutable object behind an append-only identity,
///     so a second attempt never rewrites an earlier record.
public enum SimiGoManagedRefusal {

    /// Internal refusal causes. The raw values are diagnostics only.
    public enum Cause: String, Sendable, CaseIterable {
        case invalidAnchor = "invalid_anchor"
        case authorityUnavailable = "authority_unavailable"
        case noSettlement = "no_settlement"
        case unknownSettlement = "unknown_settlement"
        case legacyMigrated = "legacy_migrated"
        case digestMismatch = "digest_mismatch"
        case invalidatedCauseUnknown = "invalidated_cause_unknown"
        case dependencyMissing = "dependency_missing"
        case dependencyInvalid = "dependency_invalid"
        case identityNonconformance = "identity_nonconformance"
        case refusalCauseUnconfirmed = "refusal_cause_unconfirmed"
        case snapshotRootUnavailable = "snapshot_root_unavailable"
        case snapshotUnstable = "snapshot_unstable"
        case snapshotSourceMissing = "snapshot_source_missing"
        case snapshotSourceUnreadable = "snapshot_source_unreadable"
        case snapshotInconsistent = "snapshot_inconsistent"
        case snapshotUnrepresentable = "snapshot_unrepresentable"
        case snapshotUsedUndeclared = "snapshot_used_undeclared"
        case snapshotUsedMismatch = "snapshot_used_mismatch"
        case idempotencyConflict = "idempotency_conflict"
        case recomputePolicyInvalid = "recompute_policy_invalid"
        case recomputePolicyConflict = "recompute_policy_conflict"
    }

    /// Where the refusal was decided. Used by P2 to distinguish "we refused an
    /// input before generating" from "we refused after the model ran".
    public enum Origin: String, Sendable {
        case request
        case admission
        case snapshot
        case idempotency
    }

    public enum Phase: String, Sendable {
        case pre = "PRE"
        case p1 = "P1"
        case s = "S"
        case g = "G"
        case p2 = "P2"
    }

    /// The entry whose failure classification is being produced. Only the 400
    /// family is new; every other outcome reuses the entry's existing bucket.
    public enum Entry: String, Sendable {
        case managedContinuation = "INPUT_ADMISSION_REFUSED"
        case settlementConsumption = "SETTLEMENT_CONSUMPTION_REFUSED"
    }

    public struct Refusal: Error, Sendable, Equatable, LocalizedError {
        public let cause: Cause
        public let origin: Origin
        public let phase: Phase
        /// Diagnostic evidence. Internal only: identifiers and digests, never
        /// file contents or absolute paths, and never sent in an HTTP body.
        public let evidence: [String: String]

        public init(cause: Cause, origin: Origin, phase: Phase, evidence: [String: String] = [:]) {
            self.cause = cause
            self.origin = origin
            self.phase = phase
            self.evidence = evidence
        }

        public var errorDescription: String? {
            "managed refusal \(cause.rawValue) at \(phase.rawValue) (\(origin.rawValue))"
        }
    }

    public struct External: Sendable, Equatable {
        public let status: Int
        public let errorKind: String
        public let reasonCode: String?
    }

    /// The closed set of codes an HTTP response may carry (ruling O1). Anything
    /// outside this set is internal and maps onto the entry's existing class.
    public static let publiclyExposedReasonCodes: Set<String> = [
        "recompute_policy_invalid",
        "recompute_policy_conflict",
        "snapshot_unrepresentable",
        "idempotency_conflict"
    ]

    public static let invalidRequestEntryKind = "INVALID_REQUEST_ENTRY"

    public static func isPubliclyExposed(_ reasonCode: String) -> Bool {
        publiclyExposedReasonCodes.contains(reasonCode)
    }

    /// Exhaustive mapping. `authorityUnavailable` keeps its 503; everything else
    /// is a 422 in the entry's own bucket, with a public code only when the cause
    /// is on the allowlist.
    public static func external(_ refusal: Refusal, entry: Entry) -> External {
        switch refusal.cause {
        case .recomputePolicyInvalid:
            return External(status: 400, errorKind: invalidRequestEntryKind,
                            reasonCode: "recompute_policy_invalid")
        case .recomputePolicyConflict:
            return External(status: 400, errorKind: invalidRequestEntryKind,
                            reasonCode: "recompute_policy_conflict")
        case .snapshotUnrepresentable:
            return External(status: 422, errorKind: entry.rawValue,
                            reasonCode: "snapshot_unrepresentable")
        case .idempotencyConflict:
            return External(status: 422, errorKind: entry.rawValue,
                            reasonCode: "idempotency_conflict")
        case .authorityUnavailable:
            return External(status: 503, errorKind: entry.rawValue, reasonCode: nil)
        default:
            return External(status: 422, errorKind: entry.rawValue, reasonCode: nil)
        }
    }

    /// Guard for any other producer of a `reasonCode`: a code that is not on the
    /// allowlist must be dropped from the response, not passed through.
    public static func sanitizedReasonCode(_ code: String?) -> String? {
        guard let code, isPubliclyExposed(code) else { return nil }
        return code
    }
}

/// One terminal audit event per execution attempt.
///
/// The event is stored as an immutable `is_objects` object and indexed under
/// `c-failure-audit:<execution_id>`; the index is append-only, so history is never
/// replaced. Writing is best-effort and happens after rollback: a failed audit
/// write must not change the original terminal result, and `audit_persisted`
/// reports what actually happened.
public enum SimiGoFailureAudit {
    public static let schemaVersion = "c-failure-audit-v1"
    public static let indexPrefix = "c-failure-audit:"

    public struct Event: Sendable, Equatable {
        public let executionID: String
        public let attempt: Int
        public let phase: SimiGoManagedRefusal.Phase
        /// nil for a failure that is not a refusal (for example a storage
        /// failure in P2): the entry keeps its existing classification instead
        /// of being reported as an admission refusal.
        public let cause: SimiGoManagedRefusal.Cause?
        public let origin: SimiGoManagedRefusal.Origin
        public let evidence: [String: String]
        public let modelCalls: Int
        public let settlementsWritten: Int
        public let recordedAt: Date
        public let detail: String

        public init(
            executionID: String,
            attempt: Int,
            phase: SimiGoManagedRefusal.Phase,
            cause: SimiGoManagedRefusal.Cause?,
            origin: SimiGoManagedRefusal.Origin,
            evidence: [String: String] = [:],
            modelCalls: Int,
            settlementsWritten: Int,
            recordedAt: Date = Date(),
            detail: String = ""
        ) {
            self.executionID = executionID
            self.attempt = attempt
            self.phase = phase
            self.cause = cause
            self.origin = origin
            self.evidence = evidence
            self.modelCalls = modelCalls
            self.settlementsWritten = settlementsWritten
            self.recordedAt = recordedAt
            self.detail = detail
        }
    }

    public struct WriteResult: Sendable, Equatable {
        /// True only when this call created and indexed the object.
        public let auditPersisted: Bool
        public let objectID: String?
        /// Set when nothing was persisted: `duplicate_execution_id` or the
        /// storage failure class. Never changes the terminal result.
        public let failureClass: String?
    }

    public static func identity(executionID: String) -> String {
        indexPrefix + executionID
    }

    public static func encoded(_ event: Event) throws -> Data {
        let object: [String: Any] = [
            "schema_version": schemaVersion,
            "execution_id": event.executionID,
            "attempt": event.attempt,
            "phase": event.phase.rawValue,
            "cause": event.cause?.rawValue ?? NSNull(),
            "origin": event.origin.rawValue,
            "evidence": event.evidence,
            "model_calls": event.modelCalls,
            "settlements_written": event.settlementsWritten,
            "recorded_at": SimiGoSnapshotContract.timestamp(event.recordedAt),
            "detail": event.detail
        ]
        guard JSONSerialization.isValidJSONObject(object) else {
            throw SimiGoSnapshotContract.SnapshotError(
                code: "failure_audit_unrepresentable", phase: "audit",
                detail: "audit event is not representable JSON")
        }
        return try JSONSerialization.data(
            withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    public static func decode(_ data: Data) throws -> Event {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SimiGoSnapshotContract.SnapshotError(
                code: "failure_audit_invalid", phase: "audit", detail: "audit record is not a JSON object")
        }
        guard let version = object["schema_version"] as? String, version == schemaVersion else {
            throw SimiGoSnapshotContract.SnapshotError(
                code: "failure_audit_invalid", phase: "audit",
                detail: "unknown audit schema \(object["schema_version"] ?? "missing")")
        }
        guard let executionID = object["execution_id"] as? String,
              let attempt = object["attempt"] as? Int,
              let phaseText = object["phase"] as? String,
              let phase = SimiGoManagedRefusal.Phase(rawValue: phaseText),
              let originText = object["origin"] as? String,
              let origin = SimiGoManagedRefusal.Origin(rawValue: originText),
              let modelCalls = object["model_calls"] as? Int,
              let settlementsWritten = object["settlements_written"] as? Int,
              let recordedText = object["recorded_at"] as? String else {
            throw SimiGoSnapshotContract.SnapshotError(
                code: "failure_audit_invalid", phase: "audit", detail: "audit record is missing required fields")
        }
        let cause: SimiGoManagedRefusal.Cause?
        if let causeText = object["cause"] as? String {
            guard let parsed = SimiGoManagedRefusal.Cause(rawValue: causeText) else {
                throw SimiGoSnapshotContract.SnapshotError(
                    code: "failure_audit_invalid", phase: "audit",
                    detail: "unknown audit cause \(causeText)")
            }
            cause = parsed
        } else {
            cause = nil
        }
        return Event(
            executionID: executionID,
            attempt: attempt,
            phase: phase,
            cause: cause,
            origin: origin,
            evidence: (object["evidence"] as? [String: String]) ?? [:],
            modelCalls: modelCalls,
            settlementsWritten: settlementsWritten,
            recordedAt: try SimiGoSnapshotContract.parseTimestamp(recordedText, phase: "audit"),
            detail: (object["detail"] as? String) ?? "")
    }
}
