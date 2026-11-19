import Foundation

/// A risk notice annotating a preserved settlement whose freshness or upstream
/// lineage is compromised. Notices never delete or rewrite a result; they let a
/// human judge and accept the risk (owner ruling A7195E7A).
///
/// The integrity of the settlement's OWN sealed object — row present, payload
/// digest matching, value non-empty — is never a notice; it stays a hard refusal.
/// Only validity and the upstream dependency closure (invalid OR missing members)
/// are risk notices an explicit acceptance may proceed past.
public struct SettlementRiskNotice: Sendable, Equatable {
    public static let invalidated = "invalidated"
    public static let upstreamInvalidated = "upstream_invalidated"
    public static let upstreamMissing = "upstream_missing"

    public let code: String
    /// The settlement the notice is about (the invalidated or missing member).
    public let settlementID: String
    /// Recorded invalidation cause, when known (e.g. the changed source file).
    public let detail: String

    public init(code: String, settlementID: String, detail: String = "") {
        self.code = code
        self.settlementID = settlementID
        self.detail = detail
    }
}

/// Read-only risk report for a preserved settlement (ruling ⑤). The settled value
/// is returned regardless of validity: invalidation flips a status, it never
/// deletes a result, so a historical query is always answerable. Notices flag the
/// stale freshness / broken lineage for a human to judge; this imposes no gate.
public struct SettlementRiskReport: Sendable, Equatable {
    public let settlementID: String
    public let validity: String
    /// The preserved semantic value, when recoverable for the requested field.
    public let value: String?
    public let notices: [SettlementRiskNotice]

    public init(
        settlementID: String, validity: String,
        value: String?, notices: [SettlementRiskNotice]
    ) {
        self.settlementID = settlementID
        self.validity = validity
        self.value = value
        self.notices = notices
    }
}

/// One refusal-shaped finding of the ruling-④ gate. `unknownSettlement` and
/// `payloadDigestMismatch` are integrity findings — no acceptance may bypass
/// them. `invalidated`, `upstreamMissing` and `upstreamInvalidated` are
/// freshness findings: the gate either appends the matching
/// `SettlementRiskNotice` (explicit acceptance) or returns the finding for the
/// caller to refuse in its own vocabulary.
public struct SettlementFreshnessFinding: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case unknownSettlement
        case payloadDigestMismatch
        case invalidated
        case upstreamMissing
        case upstreamInvalidated
    }

    public let kind: Kind
    /// The settlement the finding is about: the gate's subject for the integrity
    /// and own-validity kinds, the closure member for the upstream kinds.
    public let settlementID: String
    /// Recorded invalidation cause, when the row carries one.
    public let detail: String

    public init(kind: Kind, settlementID: String, detail: String = "") {
        self.kind = kind
        self.settlementID = settlementID
        self.detail = detail
    }
}