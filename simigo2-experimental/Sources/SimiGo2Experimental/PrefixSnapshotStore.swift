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

    public var physicalByteCount: Int? {
        let snapshotBytes = (try? snapshotURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        let metadataBytes = (try? metadataURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return snapshotBytes + metadataBytes
    }

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
    /// F3 (IMPLEMENTATION_PLANNING Q1): transient in-flight physical-use
    /// protection, keyed by artifact snapshot path. Gate D eviction goes
    /// THROUGH this registry: a deletion while a materialization work
    /// holds the artifact is deferred until release (D-C1/C2) — the P2
    /// delete-on-evict semantics are unchanged for the no-in-flight case.
    public let physicalUse: PhysicalUseRegistry
    private let fileManager = FileManager.default

    public init(root: URL, pool: ExecutionStatePrefixPool) {
        self.root = root
        self.pool = pool
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let registry = PhysicalUseRegistry(onDelete: { key in
            let snapshotURL = URL(fileURLWithPath: key)
            let metadataURL = snapshotURL.deletingPathExtension()
                .appendingPathExtension("json")
            try? fileManager.removeItem(at: snapshotURL)
            try? fileManager.removeItem(at: metadataURL)
        })
        self.physicalUse = registry
        // P2 eviction persistence: an evicted entry's artifact is deleted
        // (immediately when unused; deferred while a physical operation
        // holds it — Gate D) — eviction must survive restarts (rescan
        // only finds files that were never evicted).
        pool.onEvict = { entry in
            guard let artifact = entry.artifact as? DiskPrefixArtifact else {
                return
            }
            registry.requestDelete(artifact.snapshotURL.path)
        }
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
        // Same-content re-exports (persistent pool across runs) hit an
        // existing destination: replace it — moveItem alone throws 516.
        if fileManager.fileExists(atPath: snapshotURL.path) {
            try? fileManager.removeItem(at: snapshotURL)
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
            let snapshot = try reconciledSnapshot(entry: entry, artifact: artifact)
            return snapshot
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

    /// Synchronous twin of `load` for host hooks that run inside a
    /// session's synchronous consult path (B-6). Same reconciliation, same
    /// self-healing.
    public func loadSync(_ admission: PrefixAdmission) throws -> PromptCacheSnapshot {
        let entry = admission.entry
        guard let artifact = entry.artifact as? DiskPrefixArtifact else {
            throw PrefixSnapshotStoreError.artifactUnreadable("foreign artifact handle")
        }
        do {
            let snapshot = try reconciledSnapshot(entry: entry, artifact: artifact)
            return snapshot
        } catch let error as PrefixSnapshotStoreError {
            pool.remove(entry)
            throw error
        } catch {
            pool.remove(entry)
            throw PrefixSnapshotStoreError.artifactUnreadable(String(describing: error))
        }
    }

    /// Shared reconciliation + snapshot read for both load paths.
    private func reconciledSnapshot(
        entry: PrefixPoolEntry, artifact: DiskPrefixArtifact
    ) throws -> PromptCacheSnapshot {
        let sidecarData = fileManager.contents(atPath: artifact.metadataURL.path)
        guard let sidecar = sidecarData.flatMap({
            try? JSONDecoder().decode(PrefixSnapshotSidecar.self, from: $0)
        }) else {
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
    }

    // MARK: - Restart (disk → pool)

    /// Re-register disk-persisted boundaries into the pool after a
    /// restart. Only the sidecar claims survive on disk (the token array
    /// is not reconstructable from its hash), so this registers claims —
    /// which is sound because P-I1 holds at ADMISSION: a claim that does
    /// not match a live prompt's recomputed chain can only miss, never
    /// mis-bind. Entries whose snapshot file has vanished are skipped.
    ///
    /// - Returns: the number of entries re-registered.
    @discardableResult
    public func rescan() throws -> Int {
        var registered = 0
        let dirs = try fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey])
        for dir in dirs where dir.hasDirectoryPath {
            let files = try fileManager.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)
            for metaURL in files where metaURL.pathExtension == "json" {
                guard
                    let data = fileManager.contents(atPath: metaURL.path),
                    let sidecar = try? JSONDecoder().decode(
                        PrefixSnapshotSidecar.self, from: data)
                else { continue }
                let snapshotURL = metaURL.deletingPathExtension()
                    .appendingPathExtension("safetensors")
                guard fileManager.fileExists(atPath: snapshotURL.path) else {
                    continue
                }
                pool.register(
                    namespace: PrefixPoolNamespace(
                        modelID: sidecar.modelID, kvFingerprint: sidecar.kvFingerprint),
                    tokenCount: sidecar.tokenCount,
                    boundaryHash: sidecar.chainHash,
                    artifact: DiskPrefixArtifact(
                        snapshotURL: snapshotURL, metadataURL: metaURL))
                registered += 1
            }
        }
        return registered
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
