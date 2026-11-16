import Foundation
import Darwin
import MLXLMCommon


private let prefixSnapshotMaximumSidecarBytes = 64 * 1024
private let prefixSnapshotMaximumRescanDirectories = 4_096
private let prefixSnapshotMaximumRescanFiles = 16_384

private func prefixStatNoFollow(_ url: URL) -> stat? {
    var info = stat()
    let rc = url.path.withCString { Darwin.lstat($0, &info) }
    return rc == 0 ? info : nil
}

private func prefixIsRegularFileNoFollow(_ url: URL) -> Bool {
    guard let info = prefixStatNoFollow(url) else { return false }
    return (info.st_mode & S_IFMT) == S_IFREG
}

private func prefixIsDirectoryNoFollow(_ url: URL) -> Bool {
    guard let info = prefixStatNoFollow(url) else { return false }
    return (info.st_mode & S_IFMT) == S_IFDIR
}

private func prefixFileSizeNoFollow(_ url: URL) -> Int? {
    guard let info = prefixStatNoFollow(url),
          (info.st_mode & S_IFMT) == S_IFREG,
          info.st_size >= 0, info.st_size <= Int64(Int.max)
    else { return nil }
    return Int(info.st_size)
}

private func prefixSameObject(_ lhs: stat, _ rhs: stat) -> Bool {
    lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino
        && (lhs.st_mode & S_IFMT) == (rhs.st_mode & S_IFMT)
}

private func prefixSameFileVersion(_ lhs: stat, _ rhs: stat) -> Bool {
    lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino
        && lhs.st_size == rhs.st_size
        && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
        && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
        && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
        && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
}

private func prefixIsDirectChild(_ url: URL, of parent: URL) -> Bool {
    url.standardizedFileURL.deletingLastPathComponent().path
        == parent.standardizedFileURL.path
}

/// Read a small metadata file through an O_NOFOLLOW descriptor. The size and
/// file identity are checked on that same descriptor before and after reading.
private func prefixReadRegularFileNoFollow(_ url: URL, maximumBytes: Int) throws -> Data {
    let descriptor = url.path.withCString {
        Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    }
    guard descriptor >= 0 else {
        throw PrefixSnapshotStoreError.artifactUnreadable(
            "cannot open sidecar without following symlinks: \(url.lastPathComponent), errno=\(errno)")
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? handle.close() }

    var before = stat()
    guard Darwin.fstat(descriptor, &before) == 0,
          (before.st_mode & S_IFMT) == S_IFREG,
          before.st_size > 0,
          before.st_size <= Int64(maximumBytes)
    else {
        throw PrefixSnapshotStoreError.artifactUnreadable(
            "sidecar is not a bounded regular file: \(url.lastPathComponent)")
    }
    let (readLimit, overflow) = maximumBytes.addingReportingOverflow(1)
    guard !overflow else {
        throw PrefixSnapshotStoreError.artifactUnreadable("sidecar read limit overflow")
    }
    let data = try handle.read(upToCount: readLimit) ?? Data()
    var after = stat()
    guard data.count <= maximumBytes,
          Darwin.fstat(descriptor, &after) == 0,
          prefixSameFileVersion(before, after),
          data.count == Int(before.st_size)
    else {
        throw PrefixSnapshotStoreError.artifactUnreadable(
            "sidecar changed while being read: \(url.lastPathComponent)")
    }
    return data
}

/// Disk artifact for one pool entry (B-2): the KV snapshot written by the
/// session-side exporter plus a sidecar carrying the content claims.
///
/// Sidecar (not in-file metadata) because the production export path is
/// `ChatSession.saveCache(to:)`, which takes no user metadata — a sidecar
/// avoids re-serializing multi-GB KV arrays just to attach claims. Version 2
/// pins device/inode/size/mtime/ctime so replaced or modified snapshots fail
/// closed without hashing multi-GB KV bytes on every bind.
public struct DiskPrefixArtifact: PrefixArtifactHandle, Equatable, Sendable {
    public let snapshotURL: URL
    public let metadataURL: URL
    /// Persisted in the sidecar and filename. Legacy v2 artifacts have no generation.
    public let generationID: String?

    public var replacementIdentity: String? {
        snapshotURL.standardizedFileURL.path + "\u{1f}"
            + metadataURL.standardizedFileURL.path + "\u{1f}"
            + (generationID ?? "legacy")
    }

    public var physicalByteCount: Int? {
        guard let snapshotBytes = prefixFileSizeNoFollow(snapshotURL),
              let metadataBytes = prefixFileSizeNoFollow(metadataURL)
        else { return nil }
        let (total, overflow) = snapshotBytes.addingReportingOverflow(metadataBytes)
        return overflow ? nil : total
    }

    public init(snapshotURL: URL, metadataURL: URL, generationID: String? = nil) {
        self.snapshotURL = snapshotURL
        self.metadataURL = metadataURL
        self.generationID = generationID
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

struct PrefixSnapshotFileIdentity: Codable, Equatable {
    let device: UInt64
    let inode: UInt64
    let byteCount: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64

    init(_ info: stat) {
        device = UInt64(info.st_dev)
        inode = UInt64(info.st_ino)
        byteCount = info.st_size
        modifiedSeconds = Int64(info.st_mtimespec.tv_sec)
        modifiedNanoseconds = Int64(info.st_mtimespec.tv_nsec)
        changedSeconds = Int64(info.st_ctimespec.tv_sec)
        changedNanoseconds = Int64(info.st_ctimespec.tv_nsec)
    }

    func matches(_ info: stat) -> Bool {
        device == UInt64(info.st_dev)
            && inode == UInt64(info.st_ino)
            && byteCount == info.st_size
            && modifiedSeconds == Int64(info.st_mtimespec.tv_sec)
            && modifiedNanoseconds == Int64(info.st_mtimespec.tv_nsec)
            && changedSeconds == Int64(info.st_ctimespec.tv_sec)
            && changedNanoseconds == Int64(info.st_ctimespec.tv_nsec)
    }
}

struct PrefixSnapshotSidecar: Codable, Equatable {
    var version: Int = 3
    var modelID: String
    var kvFingerprint: String
    var tokenCount: Int
    var chainHash: UInt64
    var generationID: String?
    var snapshotIdentity: PrefixSnapshotFileIdentity
    var createdAt: Date
}

/// B-2 — the KV artifact adapter: disk-backed store wiring the prefix
/// pool to `ChatSession.saveCache` / `loadPromptCacheSnapshot`. Zero model
/// dependencies for its own logic; the session-side exporter is injected
/// as a closure at export time, which keeps this type unit-testable
/// without a model (E2 pattern).
///
/// Layout: `<root>/<namespaceHash>/<boundaryHash>-<tokenCount>-<generation>.safetensors`
/// plus a matching JSON sidecar. Each export is immutable; legacy v2 paths remain
/// readable during migration. Restart survival is free: the pool's entries live on disk.
///
/// Reconciliation at bind: sidecar claims (modelID, kvFingerprint,
/// tokenCount, chainHash) must equal the admitted entry's claims, and the
/// sidecar's file identity must still match the snapshot. Together with the
/// pool's admission check this verifies prompt → entry → artifact.
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

    private let rootDevice: dev_t?
    private let rootInode: ino_t?

    public init(root: URL, pool: ExecutionStatePrefixPool) {
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        self.root = resolvedRoot
        self.pool = pool
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: resolvedRoot, withIntermediateDirectories: true)
        let identity = prefixStatNoFollow(resolvedRoot)
        self.rootDevice = identity?.st_dev
        self.rootInode = identity?.st_ino
        let registry = PhysicalUseRegistry(onDelete: { key in
            let snapshotURL = URL(fileURLWithPath: key).standardizedFileURL
            let metadataURL = snapshotURL.deletingPathExtension()
                .appendingPathExtension("json")
            guard let expectedDevice = identity?.st_dev,
                  let expectedInode = identity?.st_ino,
                  let rootNow = prefixStatNoFollow(resolvedRoot),
                  (rootNow.st_mode & S_IFMT) == S_IFDIR,
                  rootNow.st_dev == expectedDevice, rootNow.st_ino == expectedInode,
                  Self.isSafeArtifactPaths(
                    snapshotURL: snapshotURL, metadataURL: metadataURL, root: resolvedRoot)
            else { return }
            try? fileManager.removeItem(at: snapshotURL)
            try? fileManager.removeItem(at: metadataURL)
        })
        self.physicalUse = registry
        // Evictions and same-content generation replacements share the same
        // physical-use-aware deletion path. Live materialization defers deletion;
        // otherwise the exact retired generation is removed immediately.
        let retireArtifact: (PrefixPoolEntry) -> Void = { entry in
            guard let artifact = entry.artifact as? DiskPrefixArtifact else { return }
            registry.requestDelete(artifact.snapshotURL.path)
        }
        pool.onEvict = retireArtifact
        pool.onReplace = retireArtifact
    }

    private func safeRootIdentity() -> stat? {
        guard let expectedDevice = rootDevice, let expectedInode = rootInode,
              let current = prefixStatNoFollow(root),
              (current.st_mode & S_IFMT) == S_IFDIR,
              current.st_dev == expectedDevice, current.st_ino == expectedInode
        else { return nil }
        return current
    }

    private static func isSafeArtifactPaths(
        snapshotURL: URL, metadataURL: URL, root: URL
    ) -> Bool {
        let snapshot = snapshotURL.standardizedFileURL
        let metadata = metadataURL.standardizedFileURL
        let directory = snapshot.deletingLastPathComponent()
        guard snapshot.pathExtension == "safetensors",
              metadata.pathExtension == "json",
              metadata.deletingPathExtension().path == snapshot.deletingPathExtension().path,
              prefixIsDirectChild(directory, of: root),
              prefixIsDirectChild(snapshot, of: directory),
              prefixIsDirectChild(metadata, of: directory),
              prefixIsDirectoryNoFollow(root),
              prefixIsDirectoryNoFollow(directory),
              prefixIsRegularFileNoFollow(snapshot),
              prefixIsRegularFileNoFollow(metadata)
        else { return false }
        return true
    }

    private static func isValidGenerationID(_ value: String) -> Bool {
        guard let uuid = UUID(uuidString: value) else { return false }
        return uuid.uuidString.lowercased() == value
    }

    private func isExpectedArtifact(
        _ artifact: DiskPrefixArtifact, namespace: PrefixPoolNamespace,
        tokenCount: Int, chainHash: UInt64
    ) -> Bool {
        guard safeRootIdentity() != nil,
              let directory = try? namespaceDirectory(namespace, create: false)
        else { return false }
        if let generationID = artifact.generationID,
           !Self.isValidGenerationID(generationID) {
            return false
        }
        let suffix = artifact.generationID.map { "-\($0)" } ?? ""
        let baseName = "\(String(chainHash, radix: 16))-\(tokenCount)\(suffix)"
        let expectedSnapshot = directory.appendingPathComponent(baseName + ".safetensors")
        let expectedMetadata = directory.appendingPathComponent(baseName + ".json")
        guard artifact.snapshotURL.standardizedFileURL.path == expectedSnapshot.standardizedFileURL.path,
              artifact.metadataURL.standardizedFileURL.path == expectedMetadata.standardizedFileURL.path
        else { return false }
        return Self.isSafeArtifactPaths(
            snapshotURL: artifact.snapshotURL, metadataURL: artifact.metadataURL, root: root)
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
        guard !tokens.isEmpty else {
            throw PrefixSnapshotStoreError.artifactUnreadable("empty token boundary")
        }
        guard tokens.count <= pool.configuredTokenBudget else {
            throw PrefixSnapshotStoreError.artifactUnreadable(
                "token boundary exceeds configured pool budget")
        }
        let hash = PrefixChain.hash(tokens)
        let dir = try namespaceDirectory(namespace, create: true)
        guard let directoryIdentity = prefixStatNoFollow(dir) else {
            throw PrefixSnapshotStoreError.artifactUnreadable("namespace directory vanished")
        }
        let generationID = UUID().uuidString.lowercased()
        let baseName = "\(String(hash, radix: 16))-\(tokens.count)-\(generationID)"
        let snapshotURL = dir.appendingPathComponent(baseName + ".safetensors")
        let metadataURL = dir.appendingPathComponent(baseName + ".json")

        // Isolate the exporter in a newly-created real directory. The file is
        // pre-created with O_EXCL|O_NOFOLLOW because MLX saveCache removes an
        // existing destination before writing it.
        let tempDirectory = dir.appendingPathComponent(
            ".tmp-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: false)
        guard prefixIsDirectoryNoFollow(tempDirectory) else {
            throw PrefixSnapshotStoreError.artifactUnreadable("temporary export directory is not real")
        }
        defer { try? fileManager.removeItem(at: tempDirectory) }
        let tempURL = tempDirectory.appendingPathComponent("snapshot.safetensors")
        let descriptor = tempURL.path.withCString {
            Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                        mode_t(S_IRUSR | S_IWUSR))
        }
        guard descriptor >= 0 else {
            throw PrefixSnapshotStoreError.artifactUnreadable(
                "cannot create exclusive snapshot temporary file, errno=\(errno)")
        }
        Darwin.close(descriptor)
        try await write(tempURL)

        guard prefixIsDirectoryNoFollow(root),
              let currentDirectory = prefixStatNoFollow(dir),
              prefixSameObject(directoryIdentity, currentDirectory),
              prefixIsDirectoryNoFollow(tempDirectory),
              let tempBytes = prefixFileSizeNoFollow(tempURL), tempBytes > 0
        else {
            throw PrefixSnapshotStoreError.artifactUnreadable(
                "exporter replaced or removed its temporary snapshot")
        }

        // POSIX rename atomically replaces a previous regular snapshot. Refuse
        // a symlink or non-regular destination instead of writing through it.
        if let existing = prefixStatNoFollow(snapshotURL),
           (existing.st_mode & S_IFMT) != S_IFREG {
            throw PrefixSnapshotStoreError.artifactUnreadable(
                "snapshot destination is not a regular file")
        }
        let renameResult = tempURL.path.withCString { source in
            snapshotURL.path.withCString { destination in Darwin.rename(source, destination) }
        }
        guard renameResult == 0,
              prefixIsRegularFileNoFollow(snapshotURL),
              let afterRename = prefixStatNoFollow(dir),
              prefixSameObject(directoryIdentity, afterRename)
        else {
            throw PrefixSnapshotStoreError.artifactUnreadable(
                "atomic snapshot rename failed, errno=\(errno)")
        }

        guard let snapshotInfo = prefixStatNoFollow(snapshotURL),
              (snapshotInfo.st_mode & S_IFMT) == S_IFREG
        else {
            throw PrefixSnapshotStoreError.artifactUnreadable(
                "snapshot identity unavailable after atomic publication")
        }
        let sidecar = PrefixSnapshotSidecar(
            modelID: namespace.modelID,
            kvFingerprint: namespace.kvFingerprint,
            tokenCount: tokens.count,
            chainHash: hash,
            generationID: generationID,
            snapshotIdentity: PrefixSnapshotFileIdentity(snapshotInfo),
            createdAt: Date())
        let data = try JSONEncoder().encode(sidecar)
        if let existing = prefixStatNoFollow(metadataURL),
           (existing.st_mode & S_IFMT) != S_IFREG {
            throw PrefixSnapshotStoreError.artifactUnreadable(
                "sidecar destination is not a regular file")
        }
        try data.write(to: metadataURL, options: .atomic)
        guard prefixIsRegularFileNoFollow(metadataURL),
              let afterMetadata = prefixStatNoFollow(dir),
              prefixSameObject(directoryIdentity, afterMetadata),
              isExpectedArtifact(
                DiskPrefixArtifact(
                    snapshotURL: snapshotURL, metadataURL: metadataURL,
                    generationID: generationID),
                namespace: namespace, tokenCount: tokens.count, chainHash: hash)
        else {
            throw PrefixSnapshotStoreError.artifactUnreadable(
                "sidecar publication escaped or changed the namespace directory")
        }

        return pool.export(
            namespace: namespace, tokens: tokens,
            artifact: DiskPrefixArtifact(
                snapshotURL: snapshotURL, metadataURL: metadataURL,
                generationID: generationID))
    }

    // MARK: - Bind (admission → verified snapshot)

    /// Remove one pool entry by ARTIFACT identity when it carries a
    /// `DiskPrefixArtifact`. The pool's `==` is content-only (namespace,
    /// tokenCount, boundaryHash), so a stale handle — an expired load or an
    /// explicit remove of a superseded entry — is otherwise indistinguishable
    /// from a same-content replacement and would wrongly evict the newer entry.
    /// Every removal path funnels through here so the artifact guard cannot be
    /// bypassed. Foreign artifact handles fall back to content-based removal.
    private func removeFromPool(_ entry: PrefixPoolEntry) {
        if let artifact = entry.artifact as? DiskPrefixArtifact {
            _ = pool.remove(entry, artifact: artifact)
        } else {
            pool.remove(entry)
        }
    }

    /// Reconcile the admitted entry against the artifact's own claims,
    /// then load the snapshot. Any disagreement or unreadability removes
    /// the entry from the pool and throws LOUD — never a silent miss, and
    /// never a bind that continues on an unreconciled representation.
    public func load(_ admission: PrefixAdmission) async throws -> PromptCacheSnapshot {
        let entry = admission.entry
        guard let artifact = entry.artifact as? DiskPrefixArtifact else {
            removeFromPool(entry)
            throw PrefixSnapshotStoreError.artifactUnreadable("foreign artifact handle")
        }
        do {
            let snapshot = try reconciledSnapshot(entry: entry, artifact: artifact)
            return snapshot
        } catch let error as PrefixSnapshotStoreError {
            // A corrupt in-root artifact must not remain on disk and escape
            // the pool's byte budget after its in-memory entry is gone.
            remove(entry)
            throw error
        } catch {
            remove(entry)
            throw PrefixSnapshotStoreError.artifactUnreadable(String(describing: error))
        }
    }

    /// Drop the entry and its files (budget eviction with disk cleanup is
    /// the caller's policy; this is the explicit remove).
    public func remove(_ entry: PrefixPoolEntry) {
        if let artifact = entry.artifact as? DiskPrefixArtifact,
           isExpectedArtifact(
                artifact, namespace: entry.namespace,
                tokenCount: entry.tokenCount, chainHash: entry.boundaryHash) {
            physicalUse.requestDelete(artifact.snapshotURL.path)
        }
        removeFromPool(entry)
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
            // A corrupt in-root artifact must not remain on disk and escape
            // the pool's byte budget after its in-memory entry is gone.
            remove(entry)
            throw error
        } catch {
            remove(entry)
            throw PrefixSnapshotStoreError.artifactUnreadable(String(describing: error))
        }
    }

    /// Shared reconciliation + snapshot read for both load paths.
    private func reconciledSnapshot(
        entry: PrefixPoolEntry, artifact: DiskPrefixArtifact
    ) throws -> PromptCacheSnapshot {
        guard isExpectedArtifact(
            artifact, namespace: entry.namespace,
            tokenCount: entry.tokenCount, chainHash: entry.boundaryHash)
        else {
            throw PrefixSnapshotStoreError.artifactUnreadable(
                "artifact path is outside the pool root or is a symlink")
        }
        let sidecarData = try prefixReadRegularFileNoFollow(
            artifact.metadataURL, maximumBytes: prefixSnapshotMaximumSidecarBytes)
        guard let sidecar = try? JSONDecoder().decode(PrefixSnapshotSidecar.self, from: sidecarData),
              !sidecar.modelID.isEmpty, !sidecar.kvFingerprint.isEmpty,
              sidecar.tokenCount > 0
        else {
            throw PrefixSnapshotStoreError.artifactUnreadable(
                "sidecar missing, unsupported, or malformed: \(artifact.metadataURL.lastPathComponent)")
        }
        let generationMatches: Bool
        switch sidecar.version {
        case 2:
            generationMatches = sidecar.generationID == nil && artifact.generationID == nil
        case 3:
            generationMatches = sidecar.generationID == artifact.generationID
                && sidecar.generationID.map(Self.isValidGenerationID) == true
        default:
            generationMatches = false
        }
        guard generationMatches else {
            throw PrefixSnapshotStoreError.artifactUnreadable(
                "sidecar generation does not match the admitted artifact")
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
        guard let snapshotInfo = prefixStatNoFollow(artifact.snapshotURL),
              (snapshotInfo.st_mode & S_IFMT) == S_IFREG,
              snapshotInfo.st_size > 0,
              sidecar.snapshotIdentity.matches(snapshotInfo)
        else {
            throw PrefixSnapshotStoreError.artifactUnreadable(
                "snapshot file identity no longer matches its sidecar")
        }
        let snapshot = try loadPromptCacheSnapshot(url: artifact.snapshotURL, materializeArrays: true)
        guard isExpectedArtifact(
            artifact, namespace: entry.namespace,
            tokenCount: entry.tokenCount, chainHash: entry.boundaryHash),
            let afterLoad = prefixStatNoFollow(artifact.snapshotURL),
            sidecar.snapshotIdentity.matches(afterLoad)
        else {
            throw PrefixSnapshotStoreError.artifactUnreadable(
                "artifact path or snapshot identity changed while loading")
        }
        return snapshot
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
        guard let rootIdentity = safeRootIdentity() else {
            throw PrefixSnapshotStoreError.artifactUnreadable(
                "pool root is missing, replaced, or not a real directory")
        }
        let dirs = try fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil)
        guard dirs.count <= prefixSnapshotMaximumRescanDirectories else {
            throw PrefixSnapshotStoreError.artifactUnreadable(
                "too many namespace directories during rescan")
        }

        struct Candidate {
            let namespace: PrefixPoolNamespace
            let tokenCount: Int
            let chainHash: UInt64
            let createdAt: Date
            let artifact: DiskPrefixArtifact
        }
        var candidates: [Candidate] = []
        var visitedFiles = 0
        for dir in dirs {
            guard prefixIsDirectChild(dir, of: root),
                  prefixIsDirectoryNoFollow(dir),
                  let directoryIdentity = prefixStatNoFollow(dir)
            else { continue }
            let files = try fileManager.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)
            visitedFiles += files.count
            guard visitedFiles <= prefixSnapshotMaximumRescanFiles else {
                throw PrefixSnapshotStoreError.artifactUnreadable(
                    "too many files during prefix-pool rescan")
            }

            var directoryCandidates: [Candidate] = []
            for metaURL in files where metaURL.pathExtension == "json" {
                guard prefixIsDirectChild(metaURL, of: dir),
                      prefixIsRegularFileNoFollow(metaURL),
                      let metadataBytes = prefixFileSizeNoFollow(metaURL),
                      metadataBytes > 0,
                      metadataBytes <= prefixSnapshotMaximumSidecarBytes
                else { continue }
                guard let data = try? prefixReadRegularFileNoFollow(
                    metaURL, maximumBytes: prefixSnapshotMaximumSidecarBytes),
                    let sidecar = try? JSONDecoder().decode(PrefixSnapshotSidecar.self, from: data),
                    !sidecar.modelID.isEmpty, !sidecar.kvFingerprint.isEmpty,
                    sidecar.tokenCount > 0,
                    sidecar.tokenCount <= pool.configuredTokenBudget
                else { continue }
                let generationIsValid: Bool
                switch sidecar.version {
                case 2:
                    generationIsValid = sidecar.generationID == nil
                case 3:
                    generationIsValid = sidecar.generationID
                        .map(Self.isValidGenerationID) == true
                default:
                    generationIsValid = false
                }
                guard generationIsValid else { continue }

                let namespace = PrefixPoolNamespace(
                    modelID: sidecar.modelID, kvFingerprint: sidecar.kvFingerprint)
                guard let expectedDirectory = try? namespaceDirectory(namespace, create: false),
                      expectedDirectory.standardizedFileURL.path == dir.standardizedFileURL.path
                else { continue }
                let generationSuffix = sidecar.generationID.map { "-\($0)" } ?? ""
                let baseName = "\(String(sidecar.chainHash, radix: 16))-\(sidecar.tokenCount)\(generationSuffix)"
                guard metaURL.lastPathComponent == baseName + ".json" else { continue }
                let snapshotURL = dir.appendingPathComponent(baseName + ".safetensors")
                guard prefixIsDirectChild(snapshotURL, of: dir),
                      prefixIsRegularFileNoFollow(snapshotURL),
                      let snapshotInfo = prefixStatNoFollow(snapshotURL),
                      (snapshotInfo.st_mode & S_IFMT) == S_IFREG,
                      snapshotInfo.st_size > 0,
                      sidecar.snapshotIdentity.matches(snapshotInfo),
                      let snapshotBytes = prefixFileSizeNoFollow(snapshotURL),
                      snapshotBytes > 0
                else { continue }
                let (artifactBytes, overflow) = snapshotBytes.addingReportingOverflow(metadataBytes)
                guard !overflow,
                      pool.configuredPhysicalByteBudget.map({ artifactBytes <= $0 }) ?? true
                else { continue }
                let artifact = DiskPrefixArtifact(
                    snapshotURL: snapshotURL, metadataURL: metaURL,
                    generationID: sidecar.generationID)
                guard Self.isSafeArtifactPaths(
                    snapshotURL: snapshotURL, metadataURL: metaURL, root: root)
                else { continue }
                directoryCandidates.append(Candidate(
                    namespace: namespace, tokenCount: sidecar.tokenCount,
                    chainHash: sidecar.chainHash, createdAt: sidecar.createdAt,
                    artifact: artifact))
            }
            if let currentDirectory = prefixStatNoFollow(dir),
               prefixSameObject(directoryIdentity, currentDirectory) {
                // A crash may leave multiple immutable generations on disk.
                // Register oldest first so the newest committed sidecar wins;
                // pool.onReplace retires the superseded generation safely.
                candidates.append(contentsOf: directoryCandidates.sorted {
                    if $0.createdAt == $1.createdAt {
                        return ($0.artifact.generationID ?? "")
                            < ($1.artifact.generationID ?? "")
                    }
                    return $0.createdAt < $1.createdAt
                })
            }
        }

        guard let currentRoot = safeRootIdentity(),
              prefixSameObject(rootIdentity, currentRoot)
        else {
            throw PrefixSnapshotStoreError.artifactUnreadable(
                "pool root changed during restart rescan")
        }

        var registered = 0
        for candidate in candidates {
            guard isExpectedArtifact(
                candidate.artifact, namespace: candidate.namespace,
                tokenCount: candidate.tokenCount, chainHash: candidate.chainHash)
            else { continue }
            pool.register(
                namespace: candidate.namespace,
                tokenCount: candidate.tokenCount,
                boundaryHash: candidate.chainHash,
                artifact: candidate.artifact)
            registered += 1
        }
        return registered
    }

    // MARK: - Layout

    private func namespaceDirectory(
        _ namespace: PrefixPoolNamespace, create: Bool
    ) throws -> URL {
        guard safeRootIdentity() != nil else {
            throw PrefixSnapshotStoreError.artifactUnreadable(
                "pool root is missing, replaced, or not a real directory")
        }
        let key = namespace.modelID + "\u{1f}" + namespace.kvFingerprint
        var digest = [UInt8](repeating: 0, count: 8)
        var h = PrefixChain.seed
        for byte in key.utf8 {
            h = PrefixChain.fold(h, Int(byte))
        }
        withUnsafeBytes(of: h) { digest.replaceSubrange(0..<8, with: $0) }
        let dir = root.appendingPathComponent(digest.map { String(format: "%02x", $0) }.joined())
        if create {
            if prefixStatNoFollow(dir) == nil {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: false)
            }
            guard prefixIsDirectoryNoFollow(dir) else {
                throw PrefixSnapshotStoreError.artifactUnreadable(
                    "namespace path is a symlink or not a directory")
            }
        }
        guard prefixIsDirectChild(dir, of: root) else {
            throw PrefixSnapshotStoreError.artifactUnreadable("namespace path escaped pool root")
        }
        return dir
    }
}
