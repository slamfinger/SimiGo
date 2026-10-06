import Foundation
import CryptoKit
import CarrierInterface

/// C1 — content-addressed POSIX entity store. Durable acknowledgement =
/// file write + fsync + rename + directory fsync + digest re-read match
/// (frozen A1 manifest §2.2). Representation metadata rows live in the
/// SQLite registry; the file is addressed by its SHA-256 digest.
public struct POSIXEntityStore: EntityRepresentationStore {
    let core: SQLiteCore
    let rootURL: URL

    public init(core: SQLiteCore, rootURL: URL) {
        self.core = core
        self.rootURL = rootURL
    }

    private func fileURL(for digest: String) -> URL {
        let prefix = String(digest.prefix(2))
        return rootURL.appendingPathComponent("entities", isDirectory: true)
            .appendingPathComponent(prefix, isDirectory: true)
            .appendingPathComponent(digest)
    }

    private func durableWrite(digest: String, bytes: Data) throws -> Bool {
        let url = fileURL(for: digest)
        if FileManager.default.fileExists(atPath: url.path) { return false }
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let temp = dir.appendingPathComponent(".tmp-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: temp.path, contents: nil)
        let handle = try FileHandle(forWritingTo: temp)
        do {
            try handle.write(contentsOf: bytes)
            try handle.synchronize() // fsync file data
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
        try FileManager.default.moveItem(at: temp, to: url)
        fsyncDirectory(dir) // fsync directory entry
        return true
    }

    private func fsyncDirectory(_ url: URL) {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return }
        // F_FULLFSYNC is macOS-specific; fall back to fsync.
#if os(macOS)
        fcntl(fd, F_FULLFSYNC)
#else
        fsync(fd)
#endif
        close(fd)
    }

    private func verifiedContent(from representation: CarrierRepresentation) throws -> CarrierRepresentationContent {
        let url = fileURL(for: representation.digest)
        guard let bytes = FileManager.default.contents(atPath: url.path) else {
            throw CarrierInterfaceError.integrityIssue("entity file missing for \(representation.digest)")
        }
        let actual = sha256Hex(bytes)
        guard actual == representation.digest else {
            throw CarrierInterfaceError.integrityIssue(
                "entity digest mismatch for \(representation.digest): found \(actual)"
            )
        }
        return CarrierRepresentationContent(
            representation: representation,
            payload: CarrierPayload(bytes: bytes, mediaType: representation.mediaType)
        )
    }

    public func put(_ content: CarrierRepresentationContent) async throws {
        let representation = content.representation
        let actual = sha256Hex(content.payload.bytes)
        guard actual == representation.digest else {
            throw CarrierInterfaceError.integrityIssue(
                "payload digest \(actual) does not match representation \(representation.digest)"
            )
        }
        guard representation.byteCount == content.payload.bytes.count else {
            throw CarrierInterfaceError.integrityIssue("byte count mismatch for \(representation.representationID.rawValue)")
        }
        // 1) durable entity write with digest re-read verification.
        try durableWrite(digest: representation.digest, bytes: content.payload.bytes)
        if let written = FileManager.default.contents(atPath: fileURL(for: representation.digest).path),
           sha256Hex(written) != representation.digest {
            throw CarrierInterfaceError.integrityIssue("post-write digest reread mismatch for \(representation.digest)")
        }
        CrashGate.trap("F1")
        // 2) registry row commit (F1 exposure lives between 1 and 2).
        try await core.run("""
          INSERT OR IGNORE INTO representations(representation_id, information_id, revision_id,
            digest, byte_count, media_type, created_at) VALUES (?,?,?,?,?,?,?)
        """, bind: { stmt in
            stmt.bindText(1, representation.representationID.rawValue)
            stmt.bindText(2, representation.informationID.rawValue)
            stmt.bindText(3, representation.revisionID.rawValue)
            stmt.bindText(4, representation.digest)
            stmt.bindInt(5, representation.byteCount)
            stmt.bindTextOpt(6, representation.mediaType)
            stmt.bindDouble(7, representation.createdAt.timeIntervalSince1970)
        })
    }

    public func content(_ id: CarrierRepresentationID) async throws -> CarrierRepresentationContent? {
        let rows = try await core.query(
            "SELECT representation_id, information_id, revision_id, digest, byte_count, media_type, created_at FROM representations WHERE representation_id=?",
            bind: { $0.bindText(1, id.rawValue) },
            read: Self.readRepresentation
        )
        guard let representation = rows.first else { return nil }
        return try verifiedContent(from: representation)
    }

    public func representations(
        for informationID: CarrierInformationID,
        revisionID: CarrierRevisionID?
    ) async throws -> [CarrierRepresentation] {
        if let revisionID {
            return try await core.query(
                "SELECT representation_id, information_id, revision_id, digest, byte_count, media_type, created_at FROM representations WHERE information_id=? AND revision_id=?",
                bind: {
                    $0.bindText(1, informationID.rawValue)
                    $0.bindText(2, revisionID.rawValue)
                },
                read: Self.readRepresentation
            )
        }
        return try await core.query(
            "SELECT representation_id, information_id, revision_id, digest, byte_count, media_type, created_at FROM representations WHERE information_id=?",
            bind: { $0.bindText(1, informationID.rawValue) },
            read: Self.readRepresentation
        )
    }

    static func readRepresentation(_ stmt: Stmt) -> CarrierRepresentation {
        CarrierRepresentation(
            representationID: CarrierRepresentationID(rawValue: stmt.text(0)),
            informationID: CarrierInformationID(rawValue: stmt.text(1)),
            revisionID: CarrierRevisionID(rawValue: stmt.text(2)),
            digest: stmt.text(3),
            byteCount: stmt.int(4),
            mediaType: stmt.textOpt(5),
            createdAt: Date(timeIntervalSince1970: stmt.double(6))
        )
    }

    /// Entity-file scan for the integrity reporter: returns digests present
    /// on disk that no registry row references.
    func orphanFiles(referenced: Set<String>) throws -> [String] {
        let entities = rootURL.appendingPathComponent("entities", isDirectory: true)
        var orphans: [String] = []
        guard let shards = try? FileManager.default.contentsOfDirectory(atPath: entities.path) else {
            return orphans
        }
        for shard in shards {
            let shardURL = entities.appendingPathComponent(shard)
            let files = (try? FileManager.default.contentsOfDirectory(atPath: shardURL.path)) ?? []
            for file in files where file.hasPrefix(".") == false && !referenced.contains(file) {
                orphans.append(file)
            }
        }
        return orphans
    }
}
