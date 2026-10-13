import Foundation
import MLXLMCommon

/// Disk artifact for one pool entry (B-2): the KV snapshot written by the
/// session-side exporter plus a sidecar carrying the content claims.
///
/// Sidecar (not in-file metadata) because the production export path is
/// `ChatSession.saveCache(to:)`, which takes no user metadata — a sidecar
/// avoids re-serializing multi-GB KV arrays just to attach claims. This is
/// the same safetensors + JSON-sidecar pattern the product already runs.
public struct DiskPrefixArtifact: PrefixArtifactHandle, Equatable {
    public let snapshotURL: URL
    public let metadataURL: URL
    /// Nil only for artifacts registered by pre-generation sidecars.
    public let generation: UUID?
        private let publishedPhysicalByteCount: Int?

    public var physicalByteCount: Int? {
            if let publishedPhysicalByteCount { return publishedPhysicalByteCount }
        let snapshotBytes = (try? snapshotURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        let metadataBytes = (try? metadataURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return snapshotBytes + metadataBytes
    }

        public init(
            snapshotURL: URL, metadataURL: URL, generation: UUID? = nil,
            publishedPhysicalByteCount: Int? = nil
        ) {
        self.snapshotURL = snapshotURL
        self.metadataURL = metadataURL
        self.generation = generation
            self.publishedPhysicalByteCount = publishedPhysicalByteCount
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
    case artifactGenerationMismatch(expected: UUID?, actual: UUID?)
    case artifactDeletionFailed(path: String, underlyingDescription: String)
    case physicalUseUnavailable(path: String)
}

struct PrefixSnapshotSidecar: Codable, Equatable {
    var version: Int = 1
    var modelID: String
    var kvFingerprint: String
    var tokenCount: Int
    var chainHash: UInt64
    var createdAt: Date
    var generation: UUID? = nil
}

private struct RescanArtifactChanged: Error {}

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
    private let artifactIOLock: NSLock
    private let fileManager = FileManager.default
    private let willPublishSidecar: @Sendable (URL) throws -> Void
    private let willRollback: @Sendable () throws -> Void
    private let willCommitPoolEntry: @Sendable () -> Void
    private let willBeginRescanGeneration: @Sendable () throws -> Void

    internal init(
        root: URL,
        pool: ExecutionStatePrefixPool,
        artifactIOLock: NSLock,
        deleteArtifact: @escaping (String, UUID?) throws -> Void,
        willPublishSidecar: @escaping @Sendable (URL) throws -> Void = { _ in },
        willRollback: @escaping @Sendable () throws -> Void = { },
        willCommitPoolEntry: @escaping @Sendable () -> Void = { },
        willBeginRescanGeneration: @escaping @Sendable () throws -> Void = { }
    ) {
        self.root = root
        self.pool = pool
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        self.artifactIOLock = artifactIOLock
        self.physicalUse = PhysicalUseRegistry(onDelete: deleteArtifact)
        self.willPublishSidecar = willPublishSidecar
        self.willRollback = willRollback
        self.willCommitPoolEntry = willCommitPoolEntry
        self.willBeginRescanGeneration = willBeginRescanGeneration
        // P2 eviction persistence: an evicted entry's artifact is deleted
        // (immediately when unused; deferred while a physical operation
        // holds it — Gate D) — eviction must survive restarts (rescan
        // only finds files that were never evicted).
        pool.onEvict = { [weak self] entry in
            guard let self, let artifact = entry.artifact as? DiskPrefixArtifact else {
                return
            }
            self.physicalUse.requestDelete(
                artifact.snapshotURL.path, generation: artifact.generation)
        }
    }

    public convenience init(root: URL, pool: ExecutionStatePrefixPool) {
        let artifactIOLock = NSLock()
        self.init(
            root: root,
            pool: pool,
            artifactIOLock: artifactIOLock,
            deleteArtifact: { key, expectedGeneration in
                let snapshotURL = URL(fileURLWithPath: key)
                let metadataURL = snapshotURL.deletingPathExtension()
                    .appendingPathExtension("json")
                artifactIOLock.lock()
                defer { artifactIOLock.unlock() }
                let snapshotExists = FileManager.default.fileExists(atPath: snapshotURL.path)
                let metadataExists = FileManager.default.fileExists(atPath: metadataURL.path)
                guard snapshotExists || metadataExists else { return }
                let sidecar = FileManager.default.contents(atPath: metadataURL.path)
                    .flatMap { try? JSONDecoder().decode(PrefixSnapshotSidecar.self, from: $0) }
                guard let sidecar else {
                    throw PrefixSnapshotStoreError.artifactUnreadable(
                        "artifact sidecar missing or unreadable: \(metadataURL.path)")
                }
                guard sidecar.generation == expectedGeneration else {
                    throw PrefixSnapshotStoreError.artifactGenerationMismatch(
                        expected: expectedGeneration, actual: sidecar.generation)
                }
                do {
                    if FileManager.default.fileExists(atPath: snapshotURL.path) {
                        try FileManager.default.removeItem(at: snapshotURL)
                    }
                } catch {
                    throw PrefixSnapshotStoreError.artifactDeletionFailed(
                        path: snapshotURL.path,
                        underlyingDescription: String(describing: error))
                }
                do {
                    if FileManager.default.fileExists(atPath: metadataURL.path) {
                        try FileManager.default.removeItem(at: metadataURL)
                    }
                } catch {
                    throw PrefixSnapshotStoreError.artifactDeletionFailed(
                        path: metadataURL.path,
                        underlyingDescription: String(describing: error))
                }
            },
            willPublishSidecar: { _ in }
        )
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
        let generation = UUID()

        // Write through a temp file so a failing exporter cannot leave a
        // truncated snapshot at the final location. The file is
        // PRE-CREATED: MLX's save path removes an existing destination
        // before writing, which fails with ENOENT on a missing file.
        let tempURL = dir.appendingPathComponent(".tmp-\(UUID().uuidString).safetensors")
        fileManager.createFile(atPath: tempURL.path, contents: Data())
        var newSnapshotPublished = false
        defer {
            if !newSnapshotPublished { try? fileManager.removeItem(at: tempURL) }
        }
        try await write(tempURL)
        guard fileManager.fileExists(atPath: tempURL.path) else {
            throw PrefixSnapshotStoreError.artifactUnreadable(
                "exporter produced no file (e.g. noCacheAvailable)")
        }
        let sidecar = PrefixSnapshotSidecar(
            modelID: namespace.modelID,
            kvFingerprint: namespace.kvFingerprint,
            tokenCount: tokens.count,
            chainHash: hash,
            createdAt: Date(),
            generation: generation)
        let sidecarData = try JSONEncoder().encode(sidecar)
        let sidecarTempURL = dir.appendingPathComponent(".tmp-\(UUID().uuidString)-sidecar")
        try sidecarData.write(to: sidecarTempURL, options: .atomic)
        let snapshotAttributes = try fileManager.attributesOfItem(atPath: tempURL.path)
        guard let snapshotByteCount = snapshotAttributes[.size] as? Int else {
            throw PrefixSnapshotStoreError.artifactUnreadable(
                "exporter byte count unavailable")
        }
        var sidecarPublished = false
        defer {
            if !sidecarPublished { try? fileManager.removeItem(at: sidecarTempURL) }
        }

        // Replace the complete snapshot/sidecar pair or restore the old pair.
        var publishedEntry: PrefixPoolEntry?
        try physicalUse.beginGeneration(
            snapshotURL.path,
            generation: generation,
            publish: { [artifactIOLock, fileManager, pool] in
            let backupSnapshotURL = dir.appendingPathComponent(
                ".backup-\(UUID().uuidString).safetensors")
            let backupMetadataURL = dir.appendingPathComponent(
                ".backup-\(UUID().uuidString).metadata")
            var oldSnapshotMoved = false
            var oldMetadataMoved = false

            func quarantine(_ url: URL) throws {
                guard fileManager.fileExists(atPath: url.path) else { return }
                try fileManager.moveItem(
                    at: url,
                    to: dir.appendingPathComponent(".quarantine-\(UUID().uuidString)"))
            }

            artifactIOLock.lock()
            do {
                defer { artifactIOLock.unlock() }
            do {
                if fileManager.fileExists(atPath: snapshotURL.path) {
                    try fileManager.moveItem(at: snapshotURL, to: backupSnapshotURL)
                    oldSnapshotMoved = true
                }
                if fileManager.fileExists(atPath: metadataURL.path) {
                    try fileManager.moveItem(at: metadataURL, to: backupMetadataURL)
                    oldMetadataMoved = true
                }
                try fileManager.moveItem(at: tempURL, to: snapshotURL)
                newSnapshotPublished = true
                try willPublishSidecar(metadataURL)
                try fileManager.moveItem(at: sidecarTempURL, to: metadataURL)
                sidecarPublished = true
                let publishedSidecar = fileManager.contents(atPath: metadataURL.path)
                    .flatMap { try? JSONDecoder().decode(PrefixSnapshotSidecar.self, from: $0) }
                guard publishedSidecar?.generation == generation else {
                    throw PrefixSnapshotStoreError.artifactGenerationMismatch(
                        expected: generation, actual: publishedSidecar?.generation)
                }
            } catch {
                var rollbackError: Error?
                do {
                    try willRollback()
                    if newSnapshotPublished {
                        try quarantine(metadataURL)
                    }
                    if oldMetadataMoved {
                        try fileManager.moveItem(at: backupMetadataURL, to: metadataURL)
                    }
                    if newSnapshotPublished {
                        try quarantine(snapshotURL)
                    }
                    if oldSnapshotMoved {
                        try fileManager.moveItem(at: backupSnapshotURL, to: snapshotURL)
                    }
                } catch {
                    rollbackError = error
                }
                if let rollbackError {
                    physicalUse.markGenerationQuarantined(
                        snapshotURL.path, generation: generation)
                    throw PhysicalUseRegistry.PublicationQuarantinedError(
                        key: snapshotURL.path,
                        generation: generation,
                        underlyingError: rollbackError)
                }
                throw error
            }

            try? fileManager.removeItem(at: backupSnapshotURL)
            try? fileManager.removeItem(at: backupMetadataURL)
            } catch {
                throw error
            }

            // Keep pool registration inside `beginGeneration`: admission and
            // another publication must not run between disk publication and
            // the pool's generation switch.
            willCommitPoolEntry()
            publishedEntry = pool.export(
                namespace: namespace, tokens: tokens,
                artifact: DiskPrefixArtifact(
                    snapshotURL: snapshotURL, metadataURL: metadataURL,
                    generation: generation,
                    publishedPhysicalByteCount: snapshotByteCount + sidecarData.count))
            }
        )

        guard let publishedEntry else {
            throw PrefixSnapshotStoreError.artifactUnreadable(
                "publication returned without a committed pool entry")
        }
        return publishedEntry
    }

    // MARK: - Bind (admission → verified snapshot)

    private func removeFromPool(_ entry: PrefixPoolEntry) {
        if let artifact = entry.artifact as? DiskPrefixArtifact {
            _ = pool.remove(entry, artifact: artifact)
        } else {
            pool.remove(entry)
        }
    }

    /// Remove a failed admission from the pool and request generation-bound
    /// cleanup. A stale request cannot delete a replacement; an invalid
    /// sidecar leaves the cleanup failure observable in the registry.
    private func retireFailedArtifact(_ entry: PrefixPoolEntry) {
        removeFromPool(entry)
        guard let artifact = entry.artifact as? DiskPrefixArtifact else { return }
        _ = physicalUse.requestDelete(
            artifact.snapshotURL.path, generation: artifact.generation)
    }

    /// Reconcile the admitted entry against the artifact's own claims,
    /// then load the snapshot. Any disagreement or unreadability removes
    /// the entry from the pool and throws LOUD — never a silent miss, and
    /// never a bind that continues on an unreconciled representation.
    public func load(_ admission: PrefixAdmission) async throws -> PromptCacheSnapshot {
        let entry = admission.entry
        guard let artifact = entry.artifact as? DiskPrefixArtifact else {
            throw PrefixSnapshotStoreError.artifactUnreadable("foreign artifact handle")
        }
        return try leasedReconciledSnapshot(entry: entry, artifact: artifact)
    }

    /// Drop the entry and its files (budget eviction with disk cleanup is
    /// the caller's policy; this is the explicit remove. Immediate deletion
    /// failures are thrown. If deletion is deferred behind an active lease,
    /// later failures remain observable through
    /// `PhysicalUseRegistry.takeDeleteFailures(_:)`.
    public func remove(_ entry: PrefixPoolEntry) throws {
        guard let artifact = entry.artifact as? DiskPrefixArtifact else {
            removeFromPool(entry)
            return
        }
        // A prior failed remove has already detached the entry. Reissuing the
        // generation-bound request makes retry observable; a replacement makes
        // a stale retry harmless.
        pool.remove(entry, artifact: artifact)
        if let failure = physicalUse.requestDelete(
            artifact.snapshotURL.path, generation: artifact.generation)
        {
            throw failure
        }
    }

    /// Synchronous twin of `load` for host hooks that run inside a
    /// session's synchronous consult path (B-6). Same reconciliation, same
    /// self-healing.
    public func loadSync(_ admission: PrefixAdmission) throws -> PromptCacheSnapshot {
        let entry = admission.entry
        guard let artifact = entry.artifact as? DiskPrefixArtifact else {
            throw PrefixSnapshotStoreError.artifactUnreadable("foreign artifact handle")
        }
        return try leasedReconciledSnapshot(entry: entry, artifact: artifact)
    }

    private func leasedReconciledSnapshot(
        entry: PrefixPoolEntry, artifact: DiskPrefixArtifact
    ) throws -> PromptCacheSnapshot {
        guard let lease = physicalUse.acquire(artifact.snapshotURL.path) else {
            throw PrefixSnapshotStoreError.physicalUseUnavailable(
                path: artifact.snapshotURL.path)
        }
        do {
            defer { physicalUse.release(lease) }
            let snapshot = try reconciledSnapshot(entry: entry, artifact: artifact)
            return snapshot
        } catch let error as PrefixSnapshotStoreError {
            retireFailedArtifact(entry)
            throw error
        } catch {
            retireFailedArtifact(entry)
            throw PrefixSnapshotStoreError.artifactUnreadable(String(describing: error))
        }
    }

    /// Shared reconciliation + snapshot read for both load paths.
    private func reconciledSnapshot(
        entry: PrefixPoolEntry, artifact: DiskPrefixArtifact
    ) throws -> PromptCacheSnapshot {
        artifactIOLock.lock()
        defer { artifactIOLock.unlock() }
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
        guard sidecar.generation == artifact.generation else {
            throw PrefixSnapshotStoreError.artifactGenerationMismatch(
                expected: artifact.generation, actual: sidecar.generation)
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
                try willBeginRescanGeneration()
                // Register the generation before pool.commit: immediate
                // self-eviction must issue a live delete, not a stale no-op.
                let registeredThisScan: Bool
                do {
                    registeredThisScan = try physicalUse.beginGenerationIfCurrentOrUnregistered(
                        snapshotURL.path, generation: sidecar.generation
                    ) {
                    // The scan itself is outside the I/O lock. Revalidate while
                    // preparing blocks a newly started delete; if a delete has
                    // already completed, this sees the vanished generation.
                    func validateStillOnDisk() throws -> (snapshotBytes: Int, metadataBytes: Int) {
                        artifactIOLock.lock()
                        defer { artifactIOLock.unlock() }
                        let currentData = fileManager.contents(atPath: metaURL.path)
                        let currentSidecar = currentData.flatMap {
                            try? JSONDecoder().decode(PrefixSnapshotSidecar.self, from: $0)
                        }
                        guard currentSidecar == sidecar,
                            fileManager.fileExists(atPath: snapshotURL.path)
                        else {
                            throw RescanArtifactChanged()
                        }
                        let snapshotAttributes = try fileManager.attributesOfItem(
                            atPath: snapshotURL.path)
                        guard let snapshotBytes = snapshotAttributes[.size] as? Int else {
                            throw PrefixSnapshotStoreError.artifactUnreadable(
                                "rescanned artifact byte count unavailable")
                        }
                        return (snapshotBytes, currentData?.count ?? 0)
                    }
                    let diskByteCount = try validateStillOnDisk()
                    pool.register(
                        namespace: PrefixPoolNamespace(
                            modelID: sidecar.modelID, kvFingerprint: sidecar.kvFingerprint),
                        tokenCount: sidecar.tokenCount,
                        boundaryHash: sidecar.chainHash,
                        artifact: DiskPrefixArtifact(
                            snapshotURL: snapshotURL, metadataURL: metaURL,
                            generation: sidecar.generation,
                            publishedPhysicalByteCount: diskByteCount.snapshotBytes + diskByteCount.metadataBytes))
                    }
                } catch is RescanArtifactChanged {
                    continue
                }
                guard registeredThisScan else { continue }
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
