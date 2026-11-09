import Foundation

/// Qoder as one carrier among several rather than the collector itself.
///
/// The defaults in `TranscriptSource` already produce Qoder's persisted shapes:
/// `qoder:<project>/<session>` for the information-space session and
/// `SIM.qoder.collect.v1:` for the idempotency namespace. They are restated here
/// only through `sourceType`, so the values stay derived rather than duplicated.
public enum TranscriptSourceAdapter: TranscriptSource {
    public static let sourceType = "qoder"
    public static let adapterVersion = SourceIdentity.adapterVersion
    public static let sourceKind: TranscriptSourceKind = .appendOnlyLog
}

extension CollectedTurnRecord {
    /// The source-neutral view of this turn, for consumers that must not know
    /// which carrier produced it.
    ///
    /// The grading mirrors the accepted information-sink mapping exactly:
    /// retrievable means the answer is complete and bound to its prompt, which
    /// includes the two file-order attributions and queued commands; an
    /// interrupted answer and the agent's own continuation/notification/callback
    /// turns are recorded but never retrieved; sidechain work is audit only.
    /// `interrupted` and `isSubagent` are deliberately not consulted here — the
    /// disposition already encodes them, and reading them again would let the
    /// neutral view disagree with the sink that wrote the existing rows.
    ///
    /// Qoder's transcript carries no separate reasoning channel, so
    /// `reasoningText` is nil rather than an empty string: "not observed" and
    /// "observed and empty" are different facts.
    public var collectedTurn: CollectedTurn {
        CollectedTurn(
            identity: CollectionSourceIdentity(
                sourceType: identity.sourceType,
                sourceSessionID: identity.sourceSessionID,
                sourceTurnID: identity.sourceTurnID,
                sourceMessageID: identity.sourceMessageID,
                sourceRevision: identity.sourceRevision,
                adapterVersion: identity.adapterVersion),
            provider: TranscriptSourceAdapter.sourceType,
            sessionKey: TranscriptSourceAdapter.sessionKey(
                projectID: projectID, sessionID: sessionID),
            promptText: promptText,
            answerText: answerText,
            reasoningText: nil,
            answerModel: answerModel,
            timestamp: timestamp,
            attribution: Self.neutralAttribution(relation),
            disposition: Self.neutralDisposition(disposition))
    }

    private static func neutralDisposition(
        _ disposition: TurnDisposition
    ) -> CollectionTurnDisposition {
        switch disposition {
        case .eligible:
            return .retrievable
        case .requiresReview(.fileOrderAfterCompaction), .requiresReview(.fileOrderNoChain):
            return .retrievable
        case .requiresReview(.interrupted):
            return .recordedIncompleteAnswer
        case .deferredAutoTurn(.queuedCommand):
            return .retrievable
        case .deferredAutoTurn:
            return .recordedAutomatedTurn
        case .internalRecord:
            return .auditOnly
        }
    }

    private static func neutralAttribution(
        _ relation: AttributionRelation
    ) -> CollectionAttribution {
        switch relation {
        case .parentChain:
            return .declared
        case .fileOrderAfterCompaction:
            return .fileOrderAfterCompaction
        case .fileOrderNoChain:
            return .fileOrderOnly
        }
    }
}