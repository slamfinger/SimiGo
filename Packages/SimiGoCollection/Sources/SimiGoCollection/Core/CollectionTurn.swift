import CryptoKit
import Foundation

/// Source-neutral digest used by every adapter and by the durable inbox.
public enum CollectionDigest {
    public static func sha256Hex(_ string: String) -> String {
        sha256Hex(Data(string.utf8))
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Identity of one collected answer in its source, independent of the carrier.
///
/// The key names the source message and revision, never the text, so two
/// different messages with identical content stay distinct and a re-read of the
/// same message maps to the same durable row. `sourceType` selects the key
/// namespace: Qoder rows already in the information space were written under
/// `SIM.qoder.collect.v1:`, so that source must keep resolving to those bytes.
public struct CollectionSourceIdentity: Sendable, Equatable, Hashable, Codable {
    public let sourceType: String
    public let sourceSessionID: String
    public let sourceTurnID: String
    public let sourceMessageID: String
    public let sourceRevision: Int
    public let adapterVersion: String

    public init(
        sourceType: String, sourceSessionID: String, sourceTurnID: String,
        sourceMessageID: String, sourceRevision: Int, adapterVersion: String
    ) {
        self.sourceType = sourceType
        self.sourceSessionID = sourceSessionID
        self.sourceTurnID = sourceTurnID
        self.sourceMessageID = sourceMessageID
        self.sourceRevision = sourceRevision
        self.adapterVersion = adapterVersion
    }

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
        return "SIM.\(sourceType).collect.v1:" + CollectionDigest.sha256Hex(data)
    }
}

/// What the information space may do with a collected turn.
///
/// This is the source-neutral form of the collector's grading vocabulary. It
/// names the consequence, not the carrier detail that produced it, so a new
/// adapter classifies its own evidence without inventing new storage states.
public enum CollectionTurnDisposition: String, Sendable, Equatable, Codable {
    /// Answer complete and bound to its prompt: both rows may be committed.
    case retrievable
    /// Answer is truncated or interrupted: record it, never retrieve it.
    case recordedIncompleteAnswer = "recorded_incomplete_answer"
    /// The agent talked to itself (continuation, notification, callback).
    case recordedAutomatedTurn = "recorded_automated_turn"
    /// Subagent or sidechain work: kept for audit only.
    case auditOnly = "audit_only"
}

/// How the answer was bound to its prompt.
public enum CollectionAttribution: String, Sendable, Equatable, Codable {
    /// The carrier states the relation (parent link, explicit turn grouping).
    case declared
    /// Only file order supports it, after a context compaction broke the chain.
    case fileOrderAfterCompaction = "file_order_after_compaction"
    /// Only file order supports it and the carrier never had a chain.
    case fileOrderOnly = "file_order_only"
}

/// One question and its complete answer, as observed in a transcript.
///
/// Reasoning is carried beside the answer, never inside it: a carrier's thought
/// fragments are not what the agent said, and mixing them in would let private
/// deliberation become retrievable content.
public struct CollectedTurn: Sendable, Equatable, Codable {
    public let identity: CollectionSourceIdentity
    public let provider: String
    public let sessionKey: String
    public let promptText: String
    public let answerText: String
    public let reasoningText: String?
    public let answerModel: String?
    public let timestamp: String?
    public let attribution: CollectionAttribution
    public let disposition: CollectionTurnDisposition

    public init(
        identity: CollectionSourceIdentity, provider: String, sessionKey: String,
        promptText: String, answerText: String, reasoningText: String? = nil,
        answerModel: String? = nil, timestamp: String? = nil,
        attribution: CollectionAttribution, disposition: CollectionTurnDisposition
    ) {
        self.identity = identity
        self.provider = provider
        self.sessionKey = sessionKey
        self.promptText = promptText
        self.answerText = answerText
        self.reasoningText = reasoningText
        self.answerModel = answerModel
        self.timestamp = timestamp
        self.attribution = attribution
        self.disposition = disposition
    }

    public var promptDigest: String { CollectionDigest.sha256Hex(promptText) }
    public var answerDigest: String { CollectionDigest.sha256Hex(answerText) }
}

/// A carrier observation that is not a question/answer pair. Adapters emit these
/// for diagnosis; they are never information-space content.
public struct CollectionDiagnostic: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Equatable, Codable {
        case unparsableFile = "unparsable_file"
        case unsupportedShape = "unsupported_shape"
        case incompleteTurn = "incomplete_turn"
        case unsentDraft = "unsent_draft"
        case unboundAnswer = "unbound_answer"
        case skippedAttachment = "skipped_attachment"
        /// Search or tool traffic inside a round whose answer was still imported.
        case toolTraffic = "tool_traffic"
    }

    public let kind: Kind
    public let sourceType: String
    public let locator: String
    public let detail: String

    public init(kind: Kind, sourceType: String, locator: String, detail: String) {
        self.kind = kind
        self.sourceType = sourceType
        self.locator = locator
        self.detail = detail
    }
}