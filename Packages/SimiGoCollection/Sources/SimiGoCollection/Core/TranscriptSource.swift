import Foundation

/// How a carrier exposes its history, which decides how re-reading is judged.
public enum TranscriptSourceKind: String, Sendable, Equatable, Codable {
    /// Bytes are only ever appended, so a byte offset is a valid read position.
    case appendOnlyLog = "append_only_log"
    /// The carrier rewrites the whole document, so only a content digest can
    /// tell an unchanged re-import from a revision.
    case wholeFileSnapshot = "whole_file_snapshot"
}

/// One transcript carrier the collector can read.
///
/// The protocol carries identity and grading, not parsing: each carrier's
/// document shape is different enough that a shared parser would only hide the
/// differences. What must be shared is the naming of a turn and the decision
/// about what the information space may do with it.
public protocol TranscriptSource: Sendable {
    /// Key namespace and `source_provider` value. Stable across versions: it is
    /// already persisted in delivered rows.
    static var sourceType: String { get }
    /// Parsing rules that produced an identity. Changing them must change this
    /// string so revised interpretations do not collide with delivered rows.
    static var adapterVersion: String { get }
    static var sourceKind: TranscriptSourceKind { get }

    /// Information-space session for a source session. Qoder's existing rows use
    /// `qoder:<project>/<session>`; each adapter owns its own shape.
    ///
    /// A carrier that has no project concept passes an empty `projectID`, and the
    /// default then drops the component instead of writing an empty one: a key
    /// ending in `/` would sort next to the real project keys and read as if a
    /// project existed.
    static func sessionKey(projectID: String, sessionID: String) -> String

    static func identity(
        sessionID: String, turnID: String, messageID: String, revision: Int
    ) -> CollectionSourceIdentity
}

extension TranscriptSource {
    public static func identity(
        sessionID: String, turnID: String, messageID: String, revision: Int = 1
    ) -> CollectionSourceIdentity {
        CollectionSourceIdentity(
            sourceType: sourceType, sourceSessionID: sessionID, sourceTurnID: turnID,
            sourceMessageID: messageID, sourceRevision: revision,
            adapterVersion: adapterVersion)
    }

    public static func sessionKey(projectID: String, sessionID: String) -> String {
        if projectID.isEmpty { return "\(sourceType):\(sessionID)" }
        return "\(sourceType):\(projectID)/\(sessionID)"
    }
}

/// Result of reading one whole-file snapshot.
public struct SnapshotImport: Sendable, Equatable {
    public let turns: [CollectedTurn]
    public let diagnostics: [CollectionDiagnostic]
    /// Digest of the exact bytes read. It is the revision evidence: the same
    /// digest means the same document, a different digest means a new revision.
    public let contentDigest: String

    public init(
        turns: [CollectedTurn], diagnostics: [CollectionDiagnostic], contentDigest: String
    ) {
        self.turns = turns
        self.diagnostics = diagnostics
        self.contentDigest = contentDigest
    }
}

/// A carrier whose history arrives as complete documents rather than a tail.
public protocol SnapshotTranscriptSource: TranscriptSource {
    /// Reads one document. An unreadable or foreign document must surface as a
    /// diagnostic or a thrown error, never as an empty import: "no turns" and
    /// "not this carrier" are different facts.
    ///
    /// The default implementation is the shared part of every snapshot read:
    /// take the bytes, digest them, confirm recognition, then hand the document
    /// to the adapter's own interpretation.
    static func readSnapshot(at url: URL) throws -> SnapshotImport

    /// Turns and diagnostics of a document this adapter has already recognised.
    /// `contentDigest` is the digest of the exact bytes, so an adapter cannot
    /// restate or reformat it.
    static func interpret(
        _ data: Data, path: String, contentDigest: String) throws -> SnapshotImport

    /// Discovery cannot be extension-based: real exports arrive without an
    /// extension while their sibling attachments carry misleading ones. Each
    /// adapter therefore recognises its own document by structure.
    static func recognizes(_ data: Data) -> Bool
}

extension SnapshotTranscriptSource {
    public static func readSnapshot(at url: URL) throws -> SnapshotImport {
        let path = url.lastPathComponent
        let data = try SnapshotShape.bytes(from: url)
        guard recognizes(data) else {
            throw SnapshotReadError.foreignDocument(
                path: path, detail: "\(Self.sourceType) does not claim this document")
        }
        return try interpret(data, path: path, contentDigest: CollectionDigest.sha256Hex(data))
    }
}