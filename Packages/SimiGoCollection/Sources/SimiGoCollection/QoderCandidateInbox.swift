import Foundation

public typealias QoderCollectionStateError = CollectionStateError
public typealias QoderCandidateKind = CollectionCandidateKind

/// One durably recorded collection event awaiting delivery.
public struct QoderCandidate: Sendable, Equatable {
    public let key: String
    public let kind: QoderCandidateKind
    public let sequence: Int64
    public let recordedAt: Date
    public let event: QoderCollectionEvent

    public init(
        key: String, kind: QoderCandidateKind, sequence: Int64,
        recordedAt: Date, event: QoderCollectionEvent
    ) {
        self.key = key
        self.kind = kind
        self.sequence = sequence
        self.recordedAt = recordedAt
        self.event = event
    }

    public var delivery: QoderCandidateDelivery {
        QoderCandidateDelivery(
            key: key, kind: kind, sequence: sequence, event: event)
    }
}

public struct QoderCommitResult: Sendable, Equatable {
    public let insertedCandidates: Int
    /// Replayed events already present under the same key. A crash between
    /// reading and committing makes the next poll regenerate them, and these
    /// are the ones the unique key absorbed.
    public let duplicateCandidates: Int

    public init(insertedCandidates: Int, duplicateCandidates: Int) {
        self.insertedCandidates = insertedCandidates
        self.duplicateCandidates = duplicateCandidates
    }
}

/// One candidate handed to the delivery sink.
///
/// `key` is the idempotency key the inbox already persisted. Delivery is
/// at-least-once, so a consumer that receives the same key twice knows the
/// second delivery is a replay of the same durable candidate rather than a new
/// one; consumers must not have to re-derive that key themselves.
public struct QoderCandidateDelivery: Sendable, Equatable {
    public let key: String
    public let kind: QoderCandidateKind
    public let sequence: Int64
    public let event: QoderCollectionEvent

    public init(
        key: String, kind: QoderCandidateKind, sequence: Int64,
        event: QoderCollectionEvent
    ) {
        self.key = key
        self.kind = kind
        self.sequence = sequence
        self.event = event
    }
}

public enum QoderCandidateKey {
    /// Turns are keyed by source identity so a replayed transcript line maps to
    /// the same candidate. Everything else is keyed by its canonical payload:
    /// diagnostics carry no semantic identity, and identical diagnostics are
    /// indistinguishable, so the first durable copy is the complete record.
    public static func make(for event: QoderCollectionEvent) throws -> String {
        if case .turn(let turn) = event { return turn.identity.operationKey }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(event)
        } catch {
            throw QoderCollectionStateError.encoding(detail: String(describing: error))
        }
        return "SIM.qoder.candidate.v1:" + CollectionDigest.sha256Hex(data)
    }
}

extension QoderCollectionEvent: CollectionCandidateEvent {
    public var candidateKind: QoderCandidateKind {
        switch self {
        case .turn: return .turn
        case .closedWithoutAnswer: return .closedWithoutAnswer
        case .baseline: return .baseline
        case .parseFailure: return .parseFailure
        case .orphanAssistant: return .orphanAssistant
        case .compaction: return .compaction
        }
    }

    public func candidateKey() throws -> String {
        try QoderCandidateKey.make(for: self)
    }
}

/// Qoder's read position and legacy-cursor migration on top of the shared inbox.
///
/// The candidate table, its transaction, digest verification, and delivery
/// marking belong to the neutral store. What stays here is the part only Qoder
/// knows: the cursor type, and the one-time import of the pre-inbox
/// `cursor.json`. That import reads the legacy file before any new authoritative
/// state exists, because a damaged legacy file must fail closed rather than
/// become a first start.
final class QoderCandidateInbox {
    static let databaseFileName = CollectionInboxFiles.databaseFileName
    static let legacyCursorFileName = CollectionInboxFiles.legacyCursorFileName

    let directoryURL: URL
    private let store: CollectionCandidateInbox<QoderCollectionEvent>
    private var legacyImportChecked = false

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
        self.store = CollectionCandidateInbox(directoryURL: directoryURL)
    }

    var databaseURL: URL { store.databaseURL }
    var legacyCursorURL: URL { store.legacyCursorURL }

    /// `nil` only when nothing was ever committed here: no database, no legacy
    /// cursor. Damaged state throws instead of looking like a first start.
    func loadCursorState() throws -> QoderCursorState? {
        try migrateLegacyCursorIfNeeded()
        guard let data = try store.loadPosition() else { return nil }
        do {
            return try JSONDecoder().decode(QoderCursorState.self, from: data)
        } catch {
            throw QoderCollectionStateError.corruptState(
                path: databaseURL.path, detail: "cursor state decode: \(error)")
        }
    }

    @discardableResult
    func commit(
        events: [QoderCollectionEvent], cursorState: QoderCursorState
    ) throws -> QoderCommitResult {
        try migrateLegacyCursorIfNeeded()
        let result = try store.commit(
            events: events, position: try Self.encodePosition(cursorState))
        return QoderCommitResult(
            insertedCandidates: result.insertedCandidates,
            duplicateCandidates: result.duplicateCandidates)
    }

    func pendingCandidates(limit: Int = 256) throws -> [QoderCandidate] {
        try migrateLegacyCursorIfNeeded()
        return try store.pendingCandidates(limit: limit).map { candidate in
            QoderCandidate(
                key: candidate.key, kind: candidate.kind,
                sequence: candidate.sequence, recordedAt: candidate.recordedAt,
                event: candidate.event)
        }
    }

    func markDelivered(_ keys: [String]) throws {
        try store.markDelivered(keys)
    }

    func pendingCount() throws -> Int {
        try store.pendingCount()
    }

    /// Moves the database, its WAL files, and any legacy cursor aside so the
    /// next open starts fresh. This is the explicit operator recovery for a
    /// damaged state: it re-baselines existing transcripts at EOF, which is
    /// why it never happens implicitly.
    @discardableResult
    func quarantine() throws -> URL {
        legacyImportChecked = false
        return try store.quarantine()
    }

    /// A crash during the one-time import can leave the legacy file behind with
    /// no committed row, so the check runs again until the file is archived.
    ///
    /// The import commits through the store directly. Going back through
    /// `commit` would re-enter this method while the flag is still false and the
    /// legacy file still present, which never terminates.
    private func migrateLegacyCursorIfNeeded() throws {
        if legacyImportChecked { return }
        guard FileManager.default.fileExists(atPath: legacyCursorURL.path) else {
            legacyImportChecked = true
            return
        }
        // With no database the legacy file is the only authority, so read it
        // before any new state exists: damage must fail closed instead of
        // creating a fresh database that re-baselines the transcripts at EOF.
        let databaseExists = FileManager.default.fileExists(atPath: databaseURL.path)
        let hasPosition = databaseExists ? try store.loadPosition() != nil : false
        if !hasPosition {
            let legacyState = try loadLegacyState()
            try store.commit(
                events: [], position: try Self.encodePosition(legacyState))
        }
        archiveLegacyCursor()
        legacyImportChecked = true
    }

    private static func encodePosition(_ state: QoderCursorState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            return try encoder.encode(state)
        } catch {
            throw QoderCollectionStateError.encoding(detail: String(describing: error))
        }
    }

    private func loadLegacyState() throws -> QoderCursorState {
        let cursorStore = QoderFileCursorStore(directoryURL: directoryURL)
        guard let state = try cursorStore.load() else {
            throw QoderCollectionStateError.corruptLegacyCursor(
                path: legacyCursorURL.path,
                detail: "legacy cursor disappeared during migration")
        }
        return state
    }

    private func archiveLegacyCursor() {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: legacyCursorURL.path) else { return }
        let destination = directoryURL.appendingPathComponent(
            "cursor.json.imported-\(CollectionInboxFiles.timestamp())-\(UUID().uuidString.prefix(8))")
        try? fileManager.moveItem(at: legacyCursorURL, to: destination)
    }
}