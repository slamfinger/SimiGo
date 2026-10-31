import CryptoKit
import Foundation

public enum QoderDigest {
    public static func sha256Hex(_ string: String) -> String {
        sha256Hex(Data(string.utf8))
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public enum QoderAnchorKind: String, Sendable, Equatable {
    case humanPrompt = "human_prompt"
    case continuationPrompt = "continuation_prompt"
    case notificationPrompt = "notification_prompt"
    case supervisionCallback = "supervision_callback"
    case queuedCommand = "queued_command"

    public var isHuman: Bool { self == .humanPrompt }
}

public enum QoderAttributionRelation: String, Sendable, Equatable {
    case parentChain = "parent_chain"
    case fileOrderAfterCompaction = "file_order_after_compaction"
    case fileOrderNoChain = "file_order_no_chain"
    case unattached
}

public enum QoderReviewReason: String, Sendable, Equatable {
    case fileOrderAfterCompaction = "file_order_after_compaction"
    case fileOrderNoChain = "file_order_no_chain"
    case interrupted
    case unattached
}

public enum QoderTurnDisposition: Sendable, Equatable {
    case eligible
    case requiresReview(QoderReviewReason)
    case deferredAutoTurn(QoderAnchorKind)
    case internalRecord
}

public enum QoderClosureReason: String, Sendable, Equatable {
    case interrupted
    case ambiguousTerminal = "ambiguous_terminal"
    case apiError = "api_error"
    case emptyAnswer = "empty_answer"
    case stopSequence = "stop_sequence"
    case toolOnly = "tool_only"
    case noAnswer = "no_answer"
}

public enum QoderFinalizationBoundary: String, Sendable, Equatable {
    case nextAnchor = "next_anchor"
    case endOfInput = "end_of_input"
    case idleFlush = "idle_flush"
}

public struct QoderAnchorSummary: Sendable, Equatable {
    public let id: String
    public let kind: QoderAnchorKind
    public let segmentLine: Int64
    public let timestamp: String?
    public let originKind: String?
    public let isSidechain: Bool
}

public struct QoderSupersededAnswer: Sendable, Equatable {
    public let messageID: String
    public let answerDigest: String
    public let textLength: Int
    public let segmentLine: Int64
    public let relation: QoderAttributionRelation
}

public struct QoderSourceIdentity: Sendable, Equatable, Hashable {
    public static let adapterVersion = "qoder-transcript-final/v1"

    public let sourceType: String
    public let sourceSessionID: String
    public let sourceTurnID: String
    public let sourceMessageID: String
    public let sourceRevision: Int
    public let adapterVersion: String

    public init(
        sourceSessionID: String, sourceTurnID: String, sourceMessageID: String,
        sourceRevision: Int = 1, sourceType: String = "qoder",
        adapterVersion: String = QoderSourceIdentity.adapterVersion
    ) {
        self.sourceType = sourceType
        self.sourceSessionID = sourceSessionID
        self.sourceTurnID = sourceTurnID
        self.sourceMessageID = sourceMessageID
        self.sourceRevision = sourceRevision
        self.adapterVersion = adapterVersion
    }

    /// A stable idempotency key for the cross-path settlement store. It names
    /// the source message and revision, never the text, so two different
    /// messages with identical content stay distinct.
    public var operationKey: String {
        let payload: [String: String] = [
            "adapter_version": adapterVersion,
            "source_message_id": sourceMessageID,
            "source_revision": String(sourceRevision),
            "source_session_id": sourceSessionID,
            "source_turn_id": sourceTurnID,
            "source_type": sourceType,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]))
            ?? Data()
        return "SIM.qoder.collect.v1:" + QoderDigest.sha256Hex(data)
    }
}

public struct QoderCollectedTurn: Sendable, Equatable {
    public let candidateID: String
    public let identity: QoderSourceIdentity
    public let projectID: String
    public let sessionID: String
    public let isSubagent: Bool
    public let anchor: QoderAnchorSummary
    public let promptRaw: String
    public let promptText: String
    public let promptRawDigest: String
    public let promptDigest: String
    public let answerText: String
    public let answerDigest: String
    public let messageID: String
    public let answerModel: String?
    public let timestamp: String?
    public let relation: QoderAttributionRelation
    public let disposition: QoderTurnDisposition
    public let interrupted: Bool
    public let apiErrorAttempts: Int
    public let supersededEndTurns: [QoderSupersededAnswer]
    public let firstSegmentLine: Int64
    public let lastSegmentLine: Int64
    public let finalizedBy: QoderFinalizationBoundary
}

public struct QoderTurnClosure: Sendable, Equatable {
    public let projectID: String
    public let sessionID: String
    public let isSubagent: Bool
    public let anchor: QoderAnchorSummary
    public let reason: QoderClosureReason
    public let messageCount: Int
    public let terminalCount: Int
    public let apiErrorAttempts: Int
    public let firstSegmentLine: Int64
    public let lastSegmentLine: Int64
    public let finalizedBy: QoderFinalizationBoundary
}

public struct QoderBaselineEvent: Sendable, Equatable {
    public enum Reason: String, Sendable, Equatable {
        case existingFileAtEnd = "existing_file_at_end"
        case newFileFromStart = "new_file_from_start"
        case truncatedReset = "truncated_reset"
        case identityReset = "identity_reset"
        case fingerprintReset = "fingerprint_reset"
    }

    public let path: String
    public let projectID: String
    public let sessionID: String
    public let isSubagent: Bool
    public let offset: Int64
    public let reason: Reason
}

public struct QoderParseFailure: Sendable, Equatable {
    public let path: String
    public let sessionID: String
    public let segmentLine: Int64
    public let detail: String
}

public struct QoderOrphanAssistant: Sendable, Equatable {
    public enum Reason: String, Sendable, Equatable {
        case noOpenTurn = "no_open_turn"
        case beforeCurrentAnchor = "before_current_anchor"
        case lateForClosedTurn = "late_for_closed_turn"
    }

    public let path: String
    public let sessionID: String
    public let messageID: String?
    public let segmentLine: Int64
    public let reason: Reason
}

public struct QoderCompactionEvent: Sendable, Equatable {
    public let path: String
    public let sessionID: String
    public let segmentLine: Int64
    public let uuid: String?
}

public enum QoderCollectionEvent: Sendable, Equatable {
    case baseline(QoderBaselineEvent)
    case turn(QoderCollectedTurn)
    case closedWithoutAnswer(QoderTurnClosure)
    case parseFailure(QoderParseFailure)
    case orphanAssistant(QoderOrphanAssistant)
    case compaction(QoderCompactionEvent)
}
