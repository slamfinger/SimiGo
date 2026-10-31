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

public enum QoderAnchorKind: String, Sendable, Equatable, Codable {
    case humanPrompt = "human_prompt"
    case continuationPrompt = "continuation_prompt"
    case notificationPrompt = "notification_prompt"
    case supervisionCallback = "supervision_callback"
    case queuedCommand = "queued_command"

    public var isHuman: Bool { self == .humanPrompt }
}

public enum QoderAttributionRelation: String, Sendable, Equatable, Codable {
    case parentChain = "parent_chain"
    case fileOrderAfterCompaction = "file_order_after_compaction"
    case fileOrderNoChain = "file_order_no_chain"
    case unattached
}

public enum QoderReviewReason: String, Sendable, Equatable, Codable {
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

public enum QoderClosureReason: String, Sendable, Equatable, Codable {
    case interrupted
    case ambiguousTerminal = "ambiguous_terminal"
    case apiError = "api_error"
    case emptyAnswer = "empty_answer"
    case stopSequence = "stop_sequence"
    case toolOnly = "tool_only"
    case noAnswer = "no_answer"
}

public enum QoderFinalizationBoundary: String, Sendable, Equatable, Codable {
    case nextAnchor = "next_anchor"
    case endOfInput = "end_of_input"
    case idleFlush = "idle_flush"
}

public struct QoderAnchorSummary: Sendable, Equatable, Codable {
    public let id: String
    public let kind: QoderAnchorKind
    public let segmentLine: Int64
    public let timestamp: String?
    public let originKind: String?
    public let isSidechain: Bool
}

public struct QoderSupersededAnswer: Sendable, Equatable, Codable {
    public let messageID: String
    public let answerDigest: String
    public let textLength: Int
    public let segmentLine: Int64
    public let relation: QoderAttributionRelation
}

public struct QoderSourceIdentity: Sendable, Equatable, Hashable, Codable {
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

public struct QoderCollectedTurn: Sendable, Equatable, Codable {
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

public struct QoderTurnClosure: Sendable, Equatable, Codable {
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

public struct QoderBaselineEvent: Sendable, Equatable, Codable {
    public enum Reason: String, Sendable, Equatable, Codable {
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

public struct QoderParseFailure: Sendable, Equatable, Codable {
    public let path: String
    public let sessionID: String
    public let segmentLine: Int64
    public let detail: String
}

public struct QoderOrphanAssistant: Sendable, Equatable, Codable {
    public enum Reason: String, Sendable, Equatable, Codable {
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

public struct QoderCompactionEvent: Sendable, Equatable, Codable {
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

/// Durable inbox encoding. The discriminator strings double as
/// `QoderCandidateKind` raw values so stored rows stay self-describing.
extension QoderCollectionEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case payload
    }

    private enum Kind: String, Codable {
        case baseline
        case turn
        case closedWithoutAnswer = "closed_without_answer"
        case parseFailure = "parse_failure"
        case orphanAssistant = "orphan_assistant"
        case compaction
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .baseline:
            self = .baseline(try container.decode(QoderBaselineEvent.self, forKey: .payload))
        case .turn:
            self = .turn(try container.decode(QoderCollectedTurn.self, forKey: .payload))
        case .closedWithoutAnswer:
            self = .closedWithoutAnswer(
                try container.decode(QoderTurnClosure.self, forKey: .payload))
        case .parseFailure:
            self = .parseFailure(try container.decode(QoderParseFailure.self, forKey: .payload))
        case .orphanAssistant:
            self = .orphanAssistant(
                try container.decode(QoderOrphanAssistant.self, forKey: .payload))
        case .compaction:
            self = .compaction(try container.decode(QoderCompactionEvent.self, forKey: .payload))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .baseline(let event):
            try container.encode(Kind.baseline, forKey: .kind)
            try container.encode(event, forKey: .payload)
        case .turn(let event):
            try container.encode(Kind.turn, forKey: .kind)
            try container.encode(event, forKey: .payload)
        case .closedWithoutAnswer(let event):
            try container.encode(Kind.closedWithoutAnswer, forKey: .kind)
            try container.encode(event, forKey: .payload)
        case .parseFailure(let event):
            try container.encode(Kind.parseFailure, forKey: .kind)
            try container.encode(event, forKey: .payload)
        case .orphanAssistant(let event):
            try container.encode(Kind.orphanAssistant, forKey: .kind)
            try container.encode(event, forKey: .payload)
        case .compaction(let event):
            try container.encode(Kind.compaction, forKey: .kind)
            try container.encode(event, forKey: .payload)
        }
    }
}

extension QoderTurnDisposition: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case reason
        case anchorKind
    }

    private enum Kind: String, Codable {
        case eligible
        case requiresReview
        case deferredAutoTurn
        case internalRecord
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .eligible:
            self = .eligible
        case .requiresReview:
            self = .requiresReview(
                try container.decode(QoderReviewReason.self, forKey: .reason))
        case .deferredAutoTurn:
            self = .deferredAutoTurn(
                try container.decode(QoderAnchorKind.self, forKey: .anchorKind))
        case .internalRecord:
            self = .internalRecord
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .eligible:
            try container.encode(Kind.eligible, forKey: .kind)
        case .requiresReview(let reason):
            try container.encode(Kind.requiresReview, forKey: .kind)
            try container.encode(reason, forKey: .reason)
        case .deferredAutoTurn(let kind):
            try container.encode(Kind.deferredAutoTurn, forKey: .kind)
            try container.encode(kind, forKey: .anchorKind)
        case .internalRecord:
            try container.encode(Kind.internalRecord, forKey: .kind)
        }
    }
}
