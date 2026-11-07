import Foundation

/// What a previous read of one snapshot document left behind, per source
/// session.
///
/// A whole-file carrier rewrites its document, so a byte offset cannot say what
/// was already delivered. The ledger answers the two questions the offset used
/// to answer: has this exact document been seen (`documents`), and at which
/// revision was each turn last delivered (`sessions`). Records of turns a
/// rewrite removed are kept: information space has no deletion path, and
/// forgetting a revision would let a changed turn reuse a delivered key.
public struct SnapshotReimportLedger: Sendable, Equatable, Codable {
    /// Covers the ledger shape and the turn fingerprint definition together: a
    /// change to either makes recorded digests incomparable, so an old ledger
    /// must be re-baselined instead of compared.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let sourceType: String
    public let adapterVersion: String
    /// Document key (the file name the read states) → what that document last
    /// committed.
    public let documents: [String: SnapshotDocumentRecord]
    /// Source session → every turn ever observed in it.
    public let sessions: [String: [SnapshotTurnRecord]]

    init(
        schemaVersion: Int, sourceType: String, adapterVersion: String,
        documents: [String: SnapshotDocumentRecord],
        sessions: [String: [SnapshotTurnRecord]]
    ) {
        self.schemaVersion = schemaVersion
        self.sourceType = sourceType
        self.adapterVersion = adapterVersion
        self.documents = documents
        self.sessions = sessions
    }

    /// Decodes a ledger read back from durable state. Damage throws: a corrupt
    /// position must stop collection, never read as a first start.
    public init(decoding data: Data) throws {
        do {
            self = try JSONDecoder().decode(SnapshotReimportLedger.self, from: data)
        } catch {
            throw SnapshotReimportError.unreadableLedger(detail: "\(error)")
        }
    }

    /// The form to commit as the inbox position. Sorted keys keep a re-encoded
    /// ledger byte-identical, so a committed position can be compared directly.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            return try encoder.encode(self)
        } catch {
            throw SnapshotReimportError.encoding(detail: "ledger encode: \(error)")
        }
    }
}

/// The last committed read of one snapshot document.
public struct SnapshotDocumentRecord: Sendable, Equatable, Codable {
    public let contentDigest: String
    /// Sessions this document stated at that read. A rewrite is compared
    /// against these only, so turns from a different document in the same
    /// ledger are not mistaken for deletions.
    public let sessionIDs: [String]

    init(contentDigest: String, sessionIDs: [String]) {
        self.contentDigest = contentDigest
        self.sessionIDs = sessionIDs
    }
}

/// One turn at the revision that was last delivered (or observed).
public struct SnapshotTurnRecord: Sendable, Equatable, Codable {
    public let sessionID: String
    public let turnID: String
    public let messageID: String
    public let revision: Int
    public let contentDigest: String

    init(
        sessionID: String, turnID: String, messageID: String, revision: Int,
        contentDigest: String
    ) {
        self.sessionID = sessionID
        self.turnID = turnID
        self.messageID = messageID
        self.revision = revision
        self.contentDigest = contentDigest
    }
}

/// Why a document was read without using the previous ledger.
public enum SnapshotRebaselineReason: String, Sendable, Equatable, Codable {
    /// No ledger existed for this source.
    case firstImport = "first_import"
    /// The adapter's parsing rules changed, so every identity and every
    /// content digest is a different fact.
    case adapterVersionChanged = "adapter_version_changed"
    /// The ledger shape or the fingerprint definition changed.
    case ledgerVersionChanged = "ledger_version_changed"
}

/// What a re-read of one snapshot document means for delivery.
public struct SnapshotReimportDecision: Sendable, Equatable {
    /// Turns that need delivery, in document order. Identities of revised
    /// turns already carry the next revision; unchanged and vanished turns
    /// never appear here.
    public let turns: [CollectedTurn]
    /// Observations compared and found identical to the committed revision.
    /// They are why a rewritten document can legitimately deliver nothing.
    public let unchangedTurnCount: Int
    /// Turns this document used to state and no longer does. They are neither
    /// delivered nor forgotten: information space cannot delete what an earlier
    /// revision made retrievable.
    public let vanishedTurns: [SnapshotTurnRecord]
    /// True only when the document digest matched the committed one, so no turn
    /// comparison ran at all.
    public let documentUnchanged: Bool
    /// Present when the previous ledger could not be used and every turn is a
    /// fresh observation.
    public let rebaselineReason: SnapshotRebaselineReason?
    /// State to commit atomically with `turns`.
    public let ledger: SnapshotReimportLedger

    init(
        turns: [CollectedTurn], unchangedTurnCount: Int,
        vanishedTurns: [SnapshotTurnRecord], documentUnchanged: Bool,
        rebaselineReason: SnapshotRebaselineReason?,
        ledger: SnapshotReimportLedger
    ) {
        self.turns = turns
        self.unchangedTurnCount = unchangedTurnCount
        self.vanishedTurns = vanishedTurns
        self.documentUnchanged = documentUnchanged
        self.rebaselineReason = rebaselineReason
        self.ledger = ledger
    }
}

public enum SnapshotReimportError: Error, Equatable, CustomStringConvertible {
    /// The durable ledger belongs to another carrier. Comparing across sources
    /// would treat unrelated turns as revisions of each other.
    case foreignLedger(storedSourceType: String, expectedSourceType: String)
    case unreadableLedger(detail: String)
    case encoding(detail: String)

    public var description: String {
        switch self {
        case .foreignLedger(let stored, let expected):
            return "snapshot ledger belongs to source \(stored), expected \(expected)"
        case .unreadableLedger(let detail):
            return "snapshot ledger cannot be read: \(detail)"
        case .encoding(let detail):
            return "snapshot ledger encoding failed: \(detail)"
        }
    }
}

/// Decides what a re-read of a whole-file snapshot means.
///
/// The order of checks is the evidence order. Bytes first: an identical
/// document digest means the same document, so nothing is delivered and the
/// comparison never runs. Then the identity of the observer: a different
/// adapter version or ledger schema invalidates every recorded digest, so the
/// document is re-baselined instead of read as a revision. Only then are turns
/// compared, by source identity, against the revisions already delivered.
public enum SnapshotReimport {
    public static func decide(
        sourceType: String,
        adapterVersion: String,
        documentKey: String,
        snapshot: SnapshotImport,
        ledger previous: SnapshotReimportLedger?
    ) throws -> SnapshotReimportDecision {
        if let previous, previous.sourceType != sourceType {
            throw SnapshotReimportError.foreignLedger(
                storedSourceType: previous.sourceType, expectedSourceType: sourceType)
        }
        guard let previous else {
            return try baseline(
                snapshot, sourceType: sourceType, adapterVersion: adapterVersion,
                documentKey: documentKey, reason: .firstImport)
        }
        guard previous.schemaVersion == SnapshotReimportLedger.currentSchemaVersion else {
            return try baseline(
                snapshot, sourceType: sourceType, adapterVersion: adapterVersion,
                documentKey: documentKey, reason: .ledgerVersionChanged)
        }
        guard previous.adapterVersion == adapterVersion else {
            return try baseline(
                snapshot, sourceType: sourceType, adapterVersion: adapterVersion,
                documentKey: documentKey, reason: .adapterVersionChanged)
        }
        if previous.documents[documentKey]?.contentDigest == snapshot.contentDigest {
            return SnapshotReimportDecision(
                turns: [], unchangedTurnCount: snapshot.turns.count, vanishedTurns: [],
                documentUnchanged: true, rebaselineReason: nil, ledger: previous)
        }

        var sessions = previous.sessions
        var delivered: [CollectedTurn] = []
        var observed: Set<SnapshotTurnKey> = []
        var unchanged = 0

        for turn in snapshot.turns {
            let digest = try SnapshotTurnFingerprint.digest(of: turn)
            let key = SnapshotTurnKey(
                sessionID: turn.identity.sourceSessionID,
                turnID: turn.identity.sourceTurnID,
                messageID: turn.identity.sourceMessageID)
            observed.insert(key)
            if let index = sessions[key.sessionID]?.firstIndex(where: {
                $0.turnID == key.turnID && $0.messageID == key.messageID
            }) {
                let record = sessions[key.sessionID]![index]
                if record.contentDigest == digest {
                    unchanged += 1
                    continue
                }
                let revision = record.revision + 1
                sessions[key.sessionID]![index] = SnapshotTurnRecord(
                    sessionID: key.sessionID, turnID: key.turnID,
                    messageID: key.messageID, revision: revision,
                    contentDigest: digest)
                delivered.append(turn.revisioned(revision))
            } else {
                sessions[key.sessionID, default: []].append(
                    SnapshotTurnRecord(
                        sessionID: key.sessionID, turnID: key.turnID,
                        messageID: key.messageID,
                        revision: turn.identity.sourceRevision,
                        contentDigest: digest))
                delivered.append(turn)
            }
        }

        var documents = previous.documents
        documents[documentKey] = SnapshotDocumentRecord(
            contentDigest: snapshot.contentDigest,
            sessionIDs: Set(snapshot.turns.map { $0.identity.sourceSessionID }).sorted())

        let ledger = SnapshotReimportLedger(
            schemaVersion: SnapshotReimportLedger.currentSchemaVersion,
            sourceType: sourceType, adapterVersion: adapterVersion,
            documents: documents, sessions: sessions)

        return SnapshotReimportDecision(
            turns: delivered, unchangedTurnCount: unchanged,
            vanishedTurns: vanishedTurns(
                previous: previous, documentKey: documentKey, observed: observed),
            documentUnchanged: false, rebaselineReason: nil, ledger: ledger)
    }

    /// Every turn is delivered as observed: the previous ledger is dropped, not
    /// merged, because its digests describe an interpretation that no longer
    /// applies.
    private static func baseline(
        _ snapshot: SnapshotImport, sourceType: String, adapterVersion: String,
        documentKey: String, reason: SnapshotRebaselineReason
    ) throws -> SnapshotReimportDecision {
        var sessions: [String: [SnapshotTurnRecord]] = [:]
        for turn in snapshot.turns {
            sessions[turn.identity.sourceSessionID, default: []].append(
                SnapshotTurnRecord(
                    sessionID: turn.identity.sourceSessionID,
                    turnID: turn.identity.sourceTurnID,
                    messageID: turn.identity.sourceMessageID,
                    revision: turn.identity.sourceRevision,
                    contentDigest: try SnapshotTurnFingerprint.digest(of: turn)))
        }
        let ledger = SnapshotReimportLedger(
            schemaVersion: SnapshotReimportLedger.currentSchemaVersion,
            sourceType: sourceType, adapterVersion: adapterVersion,
            documents: [
                documentKey: SnapshotDocumentRecord(
                    contentDigest: snapshot.contentDigest,
                    sessionIDs: Set(snapshot.turns.map {
                        $0.identity.sourceSessionID
                    }).sorted())
            ],
            sessions: sessions)
        return SnapshotReimportDecision(
            turns: snapshot.turns, unchangedTurnCount: 0, vanishedTurns: [],
            documentUnchanged: false, rebaselineReason: reason, ledger: ledger)
    }

    /// Scoped to the sessions this document stated at its previous read: the
    /// same ledger can hold turns from other documents, and those are not this
    /// document's deletions.
    private static func vanishedTurns(
        previous: SnapshotReimportLedger, documentKey: String,
        observed: Set<SnapshotTurnKey>
    ) -> [SnapshotTurnRecord] {
        guard let document = previous.documents[documentKey] else { return [] }
        var vanished: [SnapshotTurnRecord] = []
        for sessionID in document.sessionIDs {
            for record in previous.sessions[sessionID] ?? [] {
                let key = SnapshotTurnKey(
                    sessionID: sessionID, turnID: record.turnID,
                    messageID: record.messageID)
                if !observed.contains(key) { vanished.append(record) }
            }
        }
        return vanished.sorted {
            ($0.sessionID, $0.turnID, $0.messageID)
                < ($1.sessionID, $1.turnID, $1.messageID)
        }
    }
}

private struct SnapshotTurnKey: Hashable {
    let sessionID: String
    let turnID: String
    let messageID: String
}

/// What makes two observations of the same source turn "the same content".
///
/// The identity is excluded because it names the turn — the ledger already
/// keyed it — and everything the delivery sink would store is included, so a
/// change that would reach the information space always becomes a new
/// revision. The domain string keeps these digests from ever being read as
/// another kind of digest recorded elsewhere.
private enum SnapshotTurnFingerprint {
    private static let domain = "simigo.snapshot.turn/v1"

    private struct Content: Encodable {
        let provider: String
        let sessionKey: String
        let promptText: String
        let answerText: String
        let reasoningText: String?
        let answerModel: String?
        let timestamp: String?
        let attribution: CollectionAttribution
        let disposition: CollectionTurnDisposition

        init(_ turn: CollectedTurn) {
            provider = turn.provider
            sessionKey = turn.sessionKey
            promptText = turn.promptText
            answerText = turn.answerText
            reasoningText = turn.reasoningText
            answerModel = turn.answerModel
            timestamp = turn.timestamp
            attribution = turn.attribution
            disposition = turn.disposition
        }
    }

    static func digest(of turn: CollectedTurn) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body: Data
        do {
            body = try encoder.encode(Content(turn))
        } catch {
            throw SnapshotReimportError.encoding(
                detail: "turn fingerprint: \(error)")
        }
        var framed = Data(domain.utf8)
        framed.append(body)
        return CollectionDigest.sha256Hex(framed)
    }
}

extension CollectedTurn {
    /// The same observation under a new revision. Everything else is carried
    /// over verbatim: a revision states that the carrier restated this turn,
    /// not that the adapter observed a different one.
    fileprivate func revisioned(_ revision: Int) -> CollectedTurn {
        CollectedTurn(
            identity: CollectionSourceIdentity(
                sourceType: identity.sourceType,
                sourceSessionID: identity.sourceSessionID,
                sourceTurnID: identity.sourceTurnID,
                sourceMessageID: identity.sourceMessageID,
                sourceRevision: revision,
                adapterVersion: identity.adapterVersion),
            provider: provider, sessionKey: sessionKey,
            promptText: promptText, answerText: answerText,
            reasoningText: reasoningText, answerModel: answerModel,
            timestamp: timestamp, attribution: attribution,
            disposition: disposition)
    }
}