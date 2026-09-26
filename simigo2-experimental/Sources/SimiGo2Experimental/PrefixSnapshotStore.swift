import Foundation
import MLXLMCommon

/// Disk artifact for one pool entry (B-2): the KV snapshot written by the
/// session-side exporter plus a sidecar carrying the content claims.
///
/// Sidecar (not in-file metadata) because the production export path is
/// `ChatSession.saveCache(to:)`, which takes no user metadata — a sidecar
/// avoids re-serializing multi-GB KV arrays just to attach claims. This is
/// the same safetensors + JSON-sidecar pattern the product already runs.
public struct DiskPrefixArtifact: PrefixArtifactHandle {
    public let snapshotURL: URL
    public let metadataURL: URL

    public init(snapshotURL: URL, metadataURL: URL) {
        self.snapshotURL = snapshotURL
        self.metadataURL = metadataURL
    }
}

/// P-I1's loud-failure half: the artifact's claims disagree with the pool
/// entry's claims, or the artifact cannot be read. The store removes the
/// offending pool entry (self-healing) and throws — a bind never
/// continues on a representation that fails to reconcile.
public enum PrefixSnapshotStoreError: Error, Equatable {
    case metadataMismatch(
        entryTokens: Int, entryHash: UInt64, snapshotTokens: Int, snapshotHash: UInt64)
    case namespaceMismatch(expected: PrefixPoolNamespace, snapshot: PrefixPoolNamespace)
    case artifactUnreadable(String)
}

struct PrefixSnapshotSidecar: Codable, Equatable {
    var version: Int = 1
    var modelID: String
    var kvFingerprint: String
    var tokenCount: Int
    var chainHash: UInt64
    var createdAt: Date
}

/// B-2 — the KV artifact adapter: disk-backed store wiring the prefix
/// pool to `ChatSession.saveCache` / `loadPromptCacheSnapshot`. Zero model
/// dependencies for its own logic; the session-side exporter is injected
/// as a closure at export time, which keeps this type unit-testable
/// without a model (E2 pattern).
///
/// Layout: `<root>/<namespaceHash>/<boundaryHash>-<tokenCount>.safetensors`
/// plus `.<tokenCount>.json` sidecar. Restart survival is free: the pool's
/// entries live on disk.
///
/// Reconciliation at bind: sidecar claims (modelID, kvFingerprint,
/// tokenCount, chainHash) must equal the admitted entry's claims —
/// together with the pool's admission check (entry hash == recomputed
/// prompt-prefix hash) this is the full P-I1 chain: prompt → entry →
/// artifact, each link verified, any failure loud.
public final class PrefixSnapshotStore: @unchecked Sendable {
    public let root: URL
    public let pool: ExecutionStatePrefixPool
    private let fileManager = FileManager.default

    public init(root: URL, pool: ExecutionStatePrefixPool) {
        self.root = root
        self.pool = pool
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    // MARK: - Export (turn commit)

    /// Export one boundary representation. `write` performs the
    /// session-side save (e.g. `session.saveCache(to:)`) into the URL it
    /// is given; the store places the file + sidecar and registers the
    /// entry with the pool. A failing `write` leaves the pool untouched.
    public func export(
        namespace: PrefixPoolNamespace,
        tokens: [Int],
        write: (URL) async throws -> Void
    ) async throws -> PrefixPoolEntry {
        precondition(!tokens.isEmpty)
        let hash = PrefixChain.hash(tokens)
        let dir = try namespaceDirectory(namespace, create: true)
        let baseName = "\(String(hash, radix: 16))-\(tokens.count)"
        let snapshotURL = dir.appendingPathComponent(baseName + ".safetensors")
        let metadataURL = dir.appendingPathComponent(baseName + ".json")

        // Write through a temp file so a failing exporter cannot leave a
        // truncated snapshot at the final location. The file is
        // PRE-CREATED: MLX's save path removes an existing destination
        // before writing, which fails with ENOENT on a missing file.
        let tempURL = dir.appendingPathComponent(".tmp-\(UUID().uuidString).safetensors")
        fileManager.createFile(atPath: tempURL.path, contents: Data())
        defer { try? fileManager.removeItem(at: tempURL) }
        try await write(tempURL)
        guard fileManager.fileExists(atPath: tempURL.path) else {
            throw PrefixSnapshotStoreError.artifactUnreadable(
                "exporter produced no file (e.g. noCacheAvailable)")
        }
        try fileManager.moveItem(at: tempURL, to: snapshotURL)

        let sidecar = PrefixSnapshotSidecar(
            modelID: namespace.modelID,
            kvFingerprint: namespace.kvFingerprint,
            tokenCount: tokens.count,
            chainHash: hash,
            createdAt: Date())
        let data = try JSONEncoder().encode(sidecar)
        try data.write(to: metadataURL, options: .atomic)

        return pool.export(
            namespace: namespace, tokens: tokens,
            artifact: DiskPrefixArtifact(snapshotURL: snapshotURL, metadataURL: metadataURL))
    }

    // MARK: - Bind (admission → verified snapshot)

    /// Reconcile the admitted entry against the artifact's own claims,
    /// then load the snapshot. Any disagreement or unreadability removes
    /// the entry from the pool and throws LOUD — never a silent miss, and
    /// never a bind that continues on an unreconciled representation.
    public func load(_ admission: PrefixAdmission) async throws -> PromptCacheSnapshot {
        let entry = admission.entry
        guard let artifact = entry.artifact as? DiskPrefixArtifact else {
            throw PrefixSnapshotStoreError.artifactUnreadable("foreign artifact handle")
        }
        do {
            let sidecarData = try fileManager.contents(
                atPath: artifact.metadataURL.path)
            guard let sidecar = try? JSONDecoder().decode(
                PrefixSnapshotSidecar.self, from: sidecarData ?? Data())
            else {
                throw PrefixSnapshotStoreError.artifactUnreadable(
                    "sidecar missing or undecodable: \(artifact.metadataURL.lastPathComponent)")
            }
            let snapshotNamespace = PrefixPoolNamespace(
                modelID: sidecar.modelID, kvFingerprint: sidecar.kvFingerprint)
            guard snapshotNamespace == entry.namespace else {
                throw PrefixSnapshotStoreError.namespaceMismatch(
                    expected: entry.namespace, snapshot: snapshotNamespace)
            }
            guard sidecar.tokenCount == entry.tokenCount,
                sidecar.chainHash == entry.boundaryHash
            else {
                throw PrefixSnapshotStoreError.metadataMismatch(
                    entryTokens: entry.tokenCount, entryHash: entry.boundaryHash,
                    snapshotTokens: sidecar.tokenCount, snapshotHash: sidecar.chainHash)
            }
            return try loadPromptCacheSnapshot(url: artifact.snapshotURL, materializeArrays: true)
        } catch let error as PrefixSnapshotStoreError {
            pool.remove(entry)
            throw error
        } catch {
            pool.remove(entry)
            throw PrefixSnapshotStoreError.artifactUnreadable(String(describing: error))
        }
    }

    /// Drop the entry and its files (budget eviction with disk cleanup is
    /// the caller's policy; this is the explicit remove).
    public func remove(_ entry: PrefixPoolEntry) {
        if let artifact = entry.artifact as? DiskPrefixArtifact {
            try? fileManager.removeItem(at: artifact.snapshotURL)
            try? fileManager.removeItem(at: artifact.metadataURL)
        }
        pool.remove(entry)
    }

    // MARK: - Layout

    private func namespaceDirectory(
        _ namespace: PrefixPoolNamespace, create: Bool
    ) throws -> URL {
        let key = namespace.modelID + "\u{1f}" + namespace.kvFingerprint
        var digest = [UInt8](repeating: 0, count: 8)
        var h = PrefixChain.seed
        for byte in key.utf8 {
            h = PrefixChain.fold(h, Int(byte))
        }
        withUnsafeBytes(of: h) { digest.replaceSubrange(0..<8, with: $0) }
        let dir = root.appendingPathComponent(digest.map { String(format: "%02x", $0) }.joined())
        if create {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
