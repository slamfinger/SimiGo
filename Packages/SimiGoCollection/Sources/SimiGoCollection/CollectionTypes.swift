import Foundation

public enum SourceDigest {
    public static func sha256Hex(_ string: String) -> String {
        CollectionDigest.sha256Hex(string)
    }

    public static func sha256Hex(_ data: Data) -> String {
        CollectionDigest.sha256Hex(data)
    }
}

public enum AnchorKind: String, Sendable, Equatable, Codable {
    case humanPrompt = "human_prompt"
    case continuationPrompt = "continuation_prompt"
    case notificationPrompt = "notification_prompt"
    case supervisionCallback = "supervision_callback"
    case queuedCommand = "queued_command"

    public var isHuman: Bool { self == .humanPrompt }
}

public enum AttributionRelation: String, Sendable, Equatable, Codable {
    case parentChain = "parent_chain"
    case fileOrderAfterCompaction = "file_order_after_compaction"
    case fileOrderNoChain = "file_order_no_chain"
}

public enum ReviewReason: String, Sendable, Equatable, Codable {
    case fileOrderAfterCompaction = "file_order_after_compaction"
    case fileOrderNoChain = "file_order_no_chain"
    case interrupted
}

public enum TurnDisposition: Sendable, Equatable {
    case eligible
    case requiresReview(ReviewReason)
    case deferredAutoTurn(AnchorKind)
    case internalRecord
}

public enum ClosureReason: String, Sendable, Equatable, Codable {
    case interrupted
    case ambiguousTerminal = "ambiguous_terminal"
    case apiError = "api_error"
    case emptyAnswer = "empty_answer"
    case stopSequence = "stop_sequence"
    case toolOnly = "tool_only"
    case noAnswer = "no_answer"
    /// The accumulator discarded attribution evidence after reaching a hard retention limit.
    case historyLimitExceeded = "history_limit_exceeded"
}

public enum FinalizationBoundary: String, Sendable, Equatable, Codable {
    case nextAnchor = "next_anchor"
    case endOfInput = "end_of_input"
    case idleFlush = "idle_flush"
}

public struct AnchorSummary: Sendable, Equatable, Codable {
    public let id: String
    public let kind: AnchorKind
    public let segmentLine: Int64
    public let timestamp: String?
    public let originKind: String?
    public let isSidechain: Bool
}

public struct SupersededAnswer: Sendable, Equatable, Codable {
    public let messageID: String
    public let answerDigest: String
    public let textLength: Int
    public let segmentLine: Int64
    public let relation: AttributionRelation
}

public struct SourceIdentity: Sendable, Equatable, Hashable, Codable {
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
        adapterVersion: String = SourceIdentity.adapterVersion
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
    ///
    /// The namespace comes from `sourceType`. Qoder is the source that produced
    /// the rows already in the information space, and it is the only value the
    /// accumulator ever passes, so its key stays `SIM.qoder.collect.v1:` byte
    /// for byte while other carriers get their own namespace.
    public var operationKey: String {
        CollectionSourceIdentity(
            sourceType: sourceType, sourceSessionID: sourceSessionID,
            sourceTurnID: sourceTurnID, sourceMessageID: sourceMessageID,
            sourceRevision: sourceRevision, adapterVersion: adapterVersion
        ).operationKey
    }
}

public struct CollectedTurnRecord: Sendable, Equatable, Codable {
    public let candidateID: String
    public let identity: SourceIdentity
    public let projectID: String
    public let sessionID: String
    public let isSubagent: Bool
    public let anchor: AnchorSummary
    public let promptRaw: String
    public let promptText: String
    public let promptRawDigest: String
    public let promptDigest: String
    public let answerText: String
    public let answerDigest: String
    public let messageID: String
    public let answerModel: String?
    public let timestamp: String?
    public let relation: AttributionRelation
    public let disposition: TurnDisposition
    public let interrupted: Bool
    public let apiErrorAttempts: Int
    public let supersededEndTurns: [SupersededAnswer]
    public let firstSegmentLine: Int64
    public let lastSegmentLine: Int64
    public let finalizedBy: FinalizationBoundary
}

public struct TurnClosure: Sendable, Equatable, Codable {
    public let projectID: String
    public let sessionID: String
    public let isSubagent: Bool
    public let anchor: AnchorSummary
    public let reason: ClosureReason
    public let messageCount: Int
    public let terminalCount: Int
    public let apiErrorAttempts: Int
    public let firstSegmentLine: Int64
    public let lastSegmentLine: Int64
    public let finalizedBy: FinalizationBoundary
}

public struct BaselineEvent: Sendable, Equatable, Codable {
    public enum Reason: String, Sendable, Equatable, Codable {
        case existingFileAtEnd = "existing_file_at_end"
        case newFileFromStart = "new_file_from_start"
        /// 启用前就存在的文件，按「回填」策略从头读：采集的正是它已有的
        /// 会话内容，不是一个从 EOF 开始的空基线。
        case existingFileFromStart = "existing_file_from_start"
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

public struct ParseFailure: Sendable, Equatable, Codable {
    public let path: String
    public let sessionID: String
    public let segmentLine: Int64
    public let detail: String
}

public struct OrphanAssistant: Sendable, Equatable, Codable {
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

public struct CompactionEvent: Sendable, Equatable, Codable {
    public let path: String
    public let sessionID: String
    public let segmentLine: Int64
    public let uuid: String?
}

public enum CollectionEvent: Sendable, Equatable {
    case baseline(BaselineEvent)
    case turn(CollectedTurnRecord)
    case closedWithoutAnswer(TurnClosure)
    case parseFailure(ParseFailure)
    case orphanAssistant(OrphanAssistant)
    case compaction(CompactionEvent)
}

/// Durable inbox encoding. The discriminator strings double as
/// `CandidateKind` raw values so stored rows stay self-describing.
extension CollectionEvent: Codable {
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
            self = .baseline(try container.decode(BaselineEvent.self, forKey: .payload))
        case .turn:
            self = .turn(try container.decode(CollectedTurnRecord.self, forKey: .payload))
        case .closedWithoutAnswer:
            self = .closedWithoutAnswer(
                try container.decode(TurnClosure.self, forKey: .payload))
        case .parseFailure:
            self = .parseFailure(try container.decode(ParseFailure.self, forKey: .payload))
        case .orphanAssistant:
            self = .orphanAssistant(
                try container.decode(OrphanAssistant.self, forKey: .payload))
        case .compaction:
            self = .compaction(try container.decode(CompactionEvent.self, forKey: .payload))
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

extension TurnDisposition: Codable {
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
                try container.decode(ReviewReason.self, forKey: .reason))
        case .deferredAutoTurn:
            self = .deferredAutoTurn(
                try container.decode(AnchorKind.self, forKey: .anchorKind))
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
