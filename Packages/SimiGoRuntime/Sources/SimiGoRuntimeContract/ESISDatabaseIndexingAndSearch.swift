import Darwin
import Foundation
import SQLite3

/// Classify only filesystem reachability errors as transient unavailable. Symlink,
/// root-identity, digest and malformed-index failures remain separate refusals.
func sourceFilesystemError(
    path: String, code: Int32, operation: String
) -> ESISDatabase.DatabaseError {
    if code == ENOENT || code == ENOTDIR {
        return .sourceGone(path: path)
    }
    let unavailableCodes: [Int32] = [
        EACCES, EPERM, EIO, ENOTCONN, ETIMEDOUT,
        EHOSTDOWN, EHOSTUNREACH, ENETDOWN, ENODEV, ENXIO,
    ]
    if unavailableCodes.contains(code) {
        return .sourceReadUnavailable(path: path, code: code)
    }
    return .sql("\(operation): \(String(cString: strerror(code)))")
}

/// Indexing settlement and demand-driven retrieval, moved verbatim from
/// ESISDatabase.swift to keep the carrier file navigable. Pure file move;
/// no logic changes.
extension ESISDatabase {
    // MARK: - 工作目录内容结算（ES/IS：索引执行的结果落库，Δ 复用）

    public struct ContentSettleReport: Equatable, Sendable {
        public let scanned: Int
        public let reused: Int
        public let settled: Int
        public let skippedBinaryOrLarge: Int
        public let changed: Int
        /// Legacy report field. Directory-scan absence is not deletion evidence,
        /// so this counter stays zero; unavailability is reported by an actual read.
        public let removed: Int
        public let invalidatedSettlements: Int
        public let objectsCreated: Int
        public let deduplicated: Int
        public let bytesAddressed: Int
        /// True when the pass built only a physical index (locator/digest/size)
        /// and did not copy entity bytes into the object store.
        public let indexOnly: Bool
        /// Bytes read from the filesystem to compute digests / validate text.
        /// These are read-only; `bytesAddressed` stays the copy measure.
        public let entityBytesRead: Int
        /// The path still exists but answers with a different directory inode:
        /// a mount was replaced, a bind mount appeared, or the volume changed.
        /// Nothing was removed or invalidated on this pass — the inventory was
        /// not trusted as evidence of absence.
        public let locatorIdentityChanged: Bool
    }

    private struct FileContentState {
        let digest: String
        let objectID: String?
    }

    private struct PendingSettlement {
        let relativePath: String
        let url: URL
        let data: Data
        let digest: String
        let size: Int64
        let modified: String?
        /// The source's own timestamp for this version. This is the world clock
        /// the interval is expressed in; `recorded_at` is when ES saw it.
        let modifiedDate: Date?
        let previous: FileContentState?
        /// Raw bytes read for a tail-window digest, before dropping a partial line.
        let tailWindowBytes: Int?
    }

    /// 结算一个工作根：逐文件计算 SHA-256，内容写入内容寻址对象库
    /// （相同字节只存一次），`file_contents` 只保留身份/摘要引用；索引与
    /// 稳定来源依赖账本追加记录，历史不覆盖。实际读到的新字节形成新 revision；
    /// 目录扫描未出现的路径不推断为删除、不撤销内容引用，也不使依赖失效。
    /// 文本判定：utf8 且 ≤ fileByteCap。
    /// Root-wide guards default to 16,384 visited entries, 4,096 regular files,
    /// and 64 MiB of bytes read. The aggregate read cap also bounds Data retained
    /// in pending settlements.
    @discardableResult
    public func settleWorkRootContents(
        rootID: String, rootURL: URL, category: String = "work",
        fileByteCap: Int = 1 << 20, tailBytes: Int = 256 << 10, maxDepth: Int = 4,
        maxObservedFiles: Int = 4_096,
        maxVisitedEntries: Int = 16_384,
        maxTotalBytesRead: Int = 64 * 1024 * 1024,
        carryText: Bool = true
    ) throws -> ContentSettleReport {
        // Serialize the baseline snapshot, filesystem observation and all index
        // mutations. Otherwise two overlapping scans can commit in reverse order
        // and let an older observation overwrite a newer settlement.
        var sourceRetryCount = 0
        var revalidationRejected = false
        while true {
            do {
                revalidationRejected = false
                return try transactionResult {
        let fm = FileManager.default
        guard fileByteCap >= 0, tailBytes >= 0, maxDepth > 0,
              maxObservedFiles >= 0, maxObservedFiles < Int.max,
              maxVisitedEntries >= 0, maxTotalBytesRead >= 0 else {
            throw DatabaseError.sql("settleWorkRootContents: invalid scan limits")
        }
        let inventoryRowLimit = Int64(maxObservedFiles) + 1
        let requestedRootPath = try canonicalDirectoryPath(atPath: rootURL.path)
        let requestedRoot = URL(fileURLWithPath: requestedRootPath, isDirectory: true)
        let scanRoot: URL
        if let registeredPath = try rootLocatorPath(rootID) {
            let registeredRoot = URL(fileURLWithPath: registeredPath).standardizedFileURL
            guard registeredRoot.path == requestedRoot.path else {
                throw DatabaseError.sql(
                    "settleWorkRootContents: registered root locator changed for \(rootID)")
            }
            scanRoot = registeredRoot
        } else {
            scanRoot = requestedRoot
        }
        let rootDirectoryFD = try openDirectoryNoFollow(atPath: scanRoot.path)
        defer { Darwin.close(rootDirectoryFD) }
        // file_contents references roots, so the root must exist before any
        // content row is written (new roots start here, not in the index pass).
        // Recording the absolute path here is what makes the locator evidence
        // durable: later metadata-only upserts must not erase it.
        try upsertRoot(rootID: rootID, category: category,
                       displayName: scanRoot.path,
                       locatorType: "path", status: "present")
        // 同一个路径换了目录：挂载被替换、bind mount、整个卷换掉，都会长这样。
        // 这时「看不到文件」不是删除，后面的清账一步都不许做。
        let locatorIdentityChanged = try noteLocatorIdentity(
            rootID: rootID, path: scanRoot.path)
        if locatorIdentityChanged {
            // The caller must explicitly adopt this physical directory with
            // adoptRootLocatorIdentity before any bytes can be settled under
            // the existing root ID. Merely suppressing removals is insufficient:
            // a same-relative-path file could otherwise overwrite the old
            // digest and invalidate the old root's dependent settlements.
            return ContentSettleReport(
                scanned: 0, reused: 0, settled: 0,
                skippedBinaryOrLarge: 0, changed: 0, removed: 0,
                invalidatedSettlements: 0, objectsCreated: 0,
                deduplicated: 0, bytesAddressed: 0,
                indexOnly: !carryText, entityBytesRead: 0,
                locatorIdentityChanged: true)
        }
        var previous: [String: FileContentState] = [:]
        let prevStmt = try prepare("""
        SELECT relative_path, content_sha256, object_id FROM file_contents
        WHERE root_id=? ORDER BY relative_path LIMIT ?;
        """)
        defer { sqlite3_finalize(prevStmt) }
try bind(prevStmt, 1, rootID)
        try bind(prevStmt, 2, inventoryRowLimit)
        while try stepRowOrDone(prevStmt) {
            func text(_ i: Int32) -> String {
                sqlite3_column_text(prevStmt, i).map { String(cString: $0) } ?? ""
            }
            previous[text(0)] = FileContentState(
                digest: text(1),
                objectID: sqlite3_column_type(prevStmt, 2) == SQLITE_NULL ? nil : text(2))
        }
        guard previous.count <= maxObservedFiles else {
            throw DatabaseError.sql(
                "settleWorkRootContents: prior file_contents inventory exceeds maxObservedFiles (\(maxObservedFiles))")
        }

        // Files absent from a directory enumeration are not observed values.
        // Keep the existing index projection and carried information unchanged;
        // availability is resolved only when a consumer actually opens the source.

        var scanned = 0, reused = 0, skipped = 0
        var visitedEntries = 0
        var entityBytesRead = 0
        var pending: [PendingSettlement] = []
        var indexedFiles: [(
            rel: String, url: URL, size: Int64, modified: String?, digest: String?,
            device: Int64, inode: UInt64,
            modificationNanoseconds: Int64, changeTimeNanoseconds: Int64,
            descriptorForFinalCheck: Int32?
        )] = []
        defer {
            for file in indexedFiles {
                if let descriptor = file.descriptorForFinalCheck {
                    Darwin.close(descriptor)
                }
            }
        }
        // Detached snapshots need their original inode held through the final
        // check so rename/hard-link churn can be distinguished from later writes.
        // Keep this small enough for macOS processes with conservative FD limits.
        let maximumDetachedFinalCheckDescriptors = 64
        var retainedDetachedFinalCheckDescriptors = 0
        let modifiedFormatter = ISO8601DateFormatter()

        var enumerationFailure: (path: String, message: String)?
        guard let enumerator = fm.enumerator(
            at: scanRoot,
            includingPropertiesForKeys: [
                .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { url, error in
                if enumerationFailure == nil {
                    enumerationFailure = (url.path, error.localizedDescription)
                }
                // A skipped subtree would make the observed path set incomplete.
                return false
            })
        else {
            // Enumerating an unreadable root must not look like "every file was
            // deleted" — that would strand the carried content behind a mass
            // invalidation. Refuse and leave the previous settlement intact.
            throw DatabaseError.sql(
                "settleWorkRootContents: cannot enumerate root \(rootID)")
        }
        while let file = enumerator.nextObject() as? URL {
            visitedEntries += 1
            guard visitedEntries <= maxVisitedEntries else {
                throw DatabaseError.sql(
                    "settleWorkRootContents: maxVisitedEntries exceeded (\(maxVisitedEntries))")
            }
            var enumeratedInfo = stat()
            let lstatResult = file.path.withCString { Darwin.lstat($0, &enumeratedInfo) }
            guard lstatResult == 0 else {
                throw DatabaseError.sql(
                    "settleWorkRootContents: cannot inspect \(file.path): \(String(cString: strerror(errno)))")
            }
            let relative = relativePath(of: file, under: scanRoot)
            let fileType = enumeratedInfo.st_mode & S_IFMT
            if fileType == S_IFDIR {
                if !relative.isEmpty,
                   relative.split(separator: "/").count >= maxDepth {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard !relative.isEmpty,
                  relative.split(separator: "/").count <= maxDepth else { continue }
            guard fileType == S_IFREG else {
                throw DatabaseError.sql(
                    "settleWorkRootContents: refuses symbolic or non-regular source \(relative)")
            }
            guard scanned < maxObservedFiles else {
                throw DatabaseError.sql(
                    "settleWorkRootContents: maxObservedFiles exceeded (\(maxObservedFiles))")
            }
            let enumeratedSize = Int64(enumeratedInfo.st_size)
            guard enumeratedSize >= 0 else {
                throw DatabaseError.sql(
                    "settleWorkRootContents: negative source size for \(relative)")
            }
            let remainingBytes = maxTotalBytesRead - entityBytesRead
            if enumeratedSize <= Int64(fileByteCap) {
                guard enumeratedSize <= Int64(remainingBytes) else {
                    throw DatabaseError.sql(
                        "settleWorkRootContents: maxTotalBytesRead exceeded (\(maxTotalBytesRead))")
                }
            }

            // Every component is opened relative to the pinned root FD; no
            // symlink can redirect either an intermediate directory or the leaf.
            // The helper also checks the opened file's fstat size against the
            // remaining aggregate budget, not only this earlier lstat snapshot.
            let canRetainDetachedDescriptor =
                retainedDetachedFinalCheckDescriptors < maximumDetachedFinalCheckDescriptors
            let read = try readRootFileNoFollow(
                rootDirectoryFD: rootDirectoryFD,
                relativePath: relative,
                maximumBytes: fileByteCap,
                tailBytes: tailBytes,
                maximumTotalBytesRead: remainingBytes,
                retainDescriptorForFinalCheck: canRetainDetachedDescriptor)
            guard !read.detachedSnapshot || read.descriptorForFinalCheck != nil else {
                throw DatabaseError.sql(
                    "settleWorkRootContents: detached snapshot descriptor budget exceeded "
                        + "(\(maximumDetachedFinalCheckDescriptors))")
            }
            if read.descriptorForFinalCheck != nil {
                retainedDetachedFinalCheckDescriptors += 1
            }
            var finalCheckDescriptor = read.descriptorForFinalCheck
            defer {
                if let descriptor = finalCheckDescriptor {
                    Darwin.close(descriptor)
                }
            }
            guard read.device == Int64(enumeratedInfo.st_dev),
                  read.inode == UInt64(enumeratedInfo.st_ino) else {
                throw DatabaseError.sql(
                    "settleWorkRootContents: source changed during scan: \(relative)")
            }

            scanned += 1
            let size = read.size
            let modified = read.modificationDate.map {
                modifiedFormatter.string(from: $0)
            }
            guard let data = read.data else {
                skipped += 1
                indexedFiles.append((
                    relative, file, size, modified, nil,
                    read.device, read.inode,
                    read.modificationNanoseconds, read.changeTimeNanoseconds,
                    finalCheckDescriptor))
                finalCheckDescriptor = nil
                continue
            }

            // A tail window is not the whole document: bind the digest to the
            // file's size so an append always reads as a change, and so a tail
            // digest can never collide with a whole-file digest of the same
            // bytes.
            let indexedData = read.isTail ? Self.indexedTailData(data) : data
            let digest = read.isTail
                ? NativeSHA256.hexDigest(Data("tail:\(size):".utf8) + indexedData)
                : NativeSHA256.hexDigest(indexedData)
            let nextEntityBytesRead = entityBytesRead.addingReportingOverflow(data.count)
            guard !nextEntityBytesRead.overflow,
                  nextEntityBytesRead.partialValue <= maxTotalBytesRead else {
                throw DatabaseError.sql(
                    "settleWorkRootContents: maxTotalBytesRead exceeded (\(maxTotalBytesRead))")
            }
            entityBytesRead = nextEntityBytesRead.partialValue
            indexedFiles.append((
                relative, file, size, modified, digest,
                read.device, read.inode,
                read.modificationNanoseconds, read.changeTimeNanoseconds,
                finalCheckDescriptor))
            finalCheckDescriptor = nil
            guard String(data: indexedData, encoding: .utf8) != nil else {
                skipped += 1
                continue
            }
            if let old = previous[relative], old.digest == digest,
                carryText ? old.objectID != nil : old.objectID == nil
            {
                reused += 1
                continue
            }
            pending.append(PendingSettlement(
                relativePath: relative, url: file, data: indexedData, digest: digest,
                size: size, modified: modified, modifiedDate: read.modificationDate,
                previous: previous[relative],
                tailWindowBytes: read.isTail ? data.count : nil))
        }

        // Enumeration errors can occur after some descendants were yielded.
        // Abort before computing removals or opening the settlement transaction.
        if let failure = enumerationFailure {
            throw DatabaseError.sql(
                "settleWorkRootContents: cannot enumerate \(failure.path): \(failure.message)")
        }

        // Enumeration uses the canonical path while file reads use the pinned
        // descriptor. If that path was replaced after the initial identity
        // check, an empty successor directory could otherwise look like every
        // old file disappeared. Verify the path still names the pinned root
        // before interpreting the observed set as an inventory.
        let afterEnumerationHook = afterRootEnumerationForTesting
        afterRootEnumerationForTesting = nil
        afterEnumerationHook?()
        try verifyRootDescriptorStillNamed(rootDirectoryFD, path: scanRoot.path)

        // Absence from an inventory cannot establish ENOENT at the consumption
        // point and cannot establish a content change. A new path is not inferred
        // to be a rename of an old dependency; the agent must explicitly associate
        // it through the move API. Preserve old path projections and settlement
        // history until such an observation/association is made.
        let removed = 0
        var invalidated = Set<String>()
        var created = 0, deduplicated = 0, bytesAddressed = 0
        let now = Self.stamp(Date())

        // Refresh the mutable path projection before assigning or resolving
        // stable source identities. The dependency id itself is never a path.
        for file in indexedFiles {
            try indexExternalFile(
                rootID: rootID, category: category,
                relativePath: file.rel,
                kind: file.url.pathExtension.isEmpty ? nil : file.url.pathExtension,
                size: file.size, modifiedAt: file.modified,
                contentDigest: file.digest)
        }

            for item in pending {
                if let old = item.previous {
                    invalidated.formUnion(try affectedClosure(
                        rootID: rootID, relativePath: item.relativePath))
                    try invalidateRetrievalSettlementsInTransaction(
                        rootID: rootID, relativePath: item.relativePath,
                        oldDigest: old.digest)
                }
                // Index-only mode stores a locator/digest/size record, never the
                // entity bytes. The object appended to the carrier ledger is that
                // metadata record, so the physical file stays the single copy of
                // its own content. carryText keeps the explicit carrier mode.
                let identity = "file:\(rootID)/\(item.relativePath)"
                let indexObject: (id: String, created: Bool)
                if carryText {
                    indexObject = try ensureObjectWithStatus(item.data)
                    bytesAddressed += item.data.count
                } else {
                    var metadata: [String: Any] = [
                        "locator": identity,
                        "sha256": item.digest,
                        "size": item.size,
                        "is_tail": item.tailWindowBytes != nil,
                    ]
                    if let tailWindowBytes = item.tailWindowBytes {
                        metadata["tail_bytes"] = tailWindowBytes
                    }
                    if let modified = item.modified { metadata["modified"] = modified }
                    let encoded = try JSONSerialization.data(
                        withJSONObject: metadata,
                        options: [.sortedKeys, .withoutEscapingSlashes])
                    indexObject = try ensureObjectWithStatus(encoded)
                }
                if indexObject.created { created += 1 } else { deduplicated += 1 }
                try execBinding("""
                INSERT INTO file_contents(
                    root_id, relative_path, content_sha256, content, settled_at, object_id)
                VALUES(?,?,?,'',?,?)
                ON CONFLICT(root_id, relative_path) DO UPDATE SET
                    content_sha256=excluded.content_sha256, content='',
                    settled_at=excluded.settled_at, object_id=excluded.object_id;
                """) { stmt in
                    try bind(stmt, 1, rootID)
                    try bind(stmt, 2, item.relativePath)
                    try bind(stmt, 3, item.digest)
                    try bind(stmt, 4, now)
                    if carryText {
                        try bind(stmt, 5, indexObject.id)
                    } else {
                        try bindNull(stmt, 5)
                    }
                }
                try execBinding("""
                INSERT INTO information_items(
                    item_id, kind, locator, source_version, source_payload_sha256, state, updated_at)
                VALUES(?,?,?,?,?,'AVAILABLE',?)
                ON CONFLICT(item_id) DO UPDATE SET
                    source_version=excluded.source_version,
                    source_payload_sha256=excluded.source_payload_sha256,
                    state='AVAILABLE', updated_at=excluded.updated_at;
                """) { stmt in
                    try bind(stmt, 1, identity)
                    try bind(stmt, 2, "file")
                    try bind(stmt, 3, item.url.path)
                    try bind(stmt, 4, item.modified ?? item.digest)
                    try bind(stmt, 5, item.digest)
                    try bind(stmt, 6, now)
                }
                _ = try appendIndexEntryInTransaction(
                    identity: identity, objectID: indexObject.id)

                let sourceDependencyID = try ensureExternalSourceDependencyInTransaction(
                    rootID: rootID, relativePath: item.relativePath)
                // Index-only stores do not retain the document bytes. Its
                // dependency address is therefore a sealed object containing
                // the observed file digest; carried-text mode can point at the
                // actual immutable content object. Neither address derives from
                // the path or mutable stat metadata.
                let sourceValueAddress: String
                if carryText {
                    sourceValueAddress = indexObject.id
                } else {
                    sourceValueAddress = try ensureObject(Data(item.digest.utf8))
                }
                _ = try recordExternalSourceContentObservationInTransaction(
                    dependencyID: sourceDependencyID, rootID: rootID,
                    relativePath: item.relativePath,
                    contentAddress: sourceValueAddress,
                    sourceDigest: item.digest,
                    reason: item.previous == nil ? "content-settle" : "content-update")
            }
            try markSettlementsInvalidInTransaction(
                Array(invalidated), cause: "source-changed:\(rootID)")
            try markRootScanned(rootID)

            // Recheck after all source reads and writes, not only after
            // enumeration. A path replacement or same-inode rewrite in the
            // reconciliation window must roll back the inventory publication.
            let beforeCommitHook = beforeRootScanCommitForTesting
            beforeRootScanCommitForTesting = nil
            beforeCommitHook?()
            // Ordinary reads are reopened relative to the pinned root and compared
            // through ctime as well as identity/size/mtime. A same-size rewrite can
            // restore mtime, but cannot restore the inode's ctime.
            //
            // If metadata churn happened during the original read (rename/link),
            // the original descriptor is retained until this boundary. That lets
            // us accept the already byte-verified detached snapshot without
            // following its old path, while still detecting a later rewrite or
            // unlink of the same inode.
            for file in indexedFiles {
                if let descriptor = file.descriptorForFinalCheck {
                    var currentInfo = stat()
                    guard Darwin.fstat(descriptor, &currentInfo) == 0 else {
                        throw DatabaseError.sql(
                            "settleWorkRootContents: final descriptor fstat failed: "
                                + String(cString: strerror(errno)))
                    }
                    let currentMTime =
                        Int64(currentInfo.st_mtimespec.tv_sec) * 1_000_000_000
                        + Int64(currentInfo.st_mtimespec.tv_nsec)
                    let currentCTime =
                        Int64(currentInfo.st_ctimespec.tv_sec) * 1_000_000_000
                        + Int64(currentInfo.st_ctimespec.tv_nsec)
                    guard Int64(currentInfo.st_dev) == file.device,
                          UInt64(currentInfo.st_ino) == file.inode,
                          Int64(currentInfo.st_size) == file.size,
                          currentMTime == file.modificationNanoseconds,
                          currentCTime == file.changeTimeNanoseconds else {
                        revalidationRejected = true
                        throw DatabaseError.sourceChangedWhileBeingRead(path: file.rel)
                    }
                } else {
                    let current = try readRootFileNoFollow(
                        rootDirectoryFD: rootDirectoryFD,
                        relativePath: file.rel,
                        maximumBytes: 0,
                        tailBytes: nil,
                        maximumTotalBytesRead: 0)
                    guard current.device == file.device,
                          current.inode == file.inode,
                          current.size == file.size,
                          current.modificationNanoseconds == file.modificationNanoseconds,
                          current.changeTimeNanoseconds == file.changeTimeNanoseconds else {
                        revalidationRejected = true
                        throw DatabaseError.sourceChangedWhileBeingRead(path: file.rel)
                    }
                }
            }
            try verifyRootDescriptorStillNamed(rootDirectoryFD, path: scanRoot.path)

        return ContentSettleReport(
            scanned: scanned, reused: reused, settled: pending.count,
            skippedBinaryOrLarge: skipped,
            changed: pending.filter { $0.previous != nil }.count,
            removed: removed, invalidatedSettlements: invalidated.count,
            objectsCreated: created, deduplicated: deduplicated,
            bytesAddressed: bytesAddressed,
            indexOnly: !carryText, entityBytesRead: entityBytesRead,
            locatorIdentityChanged: locatorIdentityChanged)
                }
            } catch let error as DatabaseError {
                // Only a rejected pre-commit revalidation earns the single
                // retry. A read whose own verification failed is reported as
                // it stands; it must not get a second chance to look settled.
                guard sourceRetryCount == 0, revalidationRejected else { throw error }
                switch error {
                case .sourceChangedWhileBeingRead(_), .sourceGone(_):
                    // The first snapshot was overtaken while being read.
                    // Roll it back and retry against the bytes currently reachable.
                    // Only an observed changed value is published as a revision;
                    // an old path that disappeared remains a transient unavailable
                    // source rather than an inferred deletion.
                    sourceRetryCount += 1
                default:
                    throw error
                }
            }
        }
    }

    struct NoFollowFileRead {
        let data: Data?
        let size: Int64
        let modificationDate: Date?
        let modificationNanoseconds: Int64
        let changeTimeNanoseconds: Int64
        /// Duplicated only for a detached snapshot whose path may be renamed
        /// before the final commit revalidation.
        let descriptorForFinalCheck: Int32?
        /// True when this read already saw metadata churn and re-verified its
        /// bytes, so the snapshot is the version its descriptor held.
        var detachedSnapshot: Bool = false
        let device: Int64
        let inode: UInt64
        /// True when `data` is the last `tailBytes` of a file that exceeded
        /// the whole-file cap. The digest then covers (size, tail), so an
        /// append still changes it.
        var isTail: Bool = false
    }

    /// The tail index discards its first possibly partial line identically
    /// during settlement and later source revalidation.
    private static func indexedTailData(_ rawData: Data) -> Data {
        guard let firstBreak = rawData.firstIndex(of: 0x0A) else { return rawData }
        return rawData[rawData.index(after: firstBreak)...]
    }

    func canonicalDirectoryPath(atPath path: String) throws -> String {
        let resolved = path.withCString { Darwin.realpath($0, nil) }
        guard let resolved else {
            let code = errno
            throw sourceFilesystemError(
                path: path, code: code, operation: "canonicalDirectoryPath")
        }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
            .standardizedFileURL.path
    }

    func openDirectoryNoFollow(atPath path: String) throws -> Int32 {
        let canonicalPath = try canonicalDirectoryPath(atPath: path)
        guard canonicalPath == URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL.path else {
            throw DatabaseError.sql(
                "openDirectoryNoFollow: registered directory path now resolves elsewhere")
        }

        // macOS temporary roots can traverse APFS firmlink/alias components
        // which are canonicalized by realpath but are not all traversable via
        // a strict component-by-component O_NOFOLLOW walk. Resolve once, then
        // bind the opened directory descriptor to the exact lstat identity of
        // that canonical leaf. Descendant paths remain component-wise no-follow.
        var pathInfo = stat()
        let statResult = canonicalPath.withCString { Darwin.lstat($0, &pathInfo) }
        guard statResult == 0 else {
            throw sourceFilesystemError(
                path: canonicalPath, code: errno, operation: "openDirectoryNoFollow lstat")
        }
        guard (pathInfo.st_mode & S_IFMT) == S_IFDIR else {
            throw DatabaseError.sql("openDirectoryNoFollow: canonical root is not a directory")
        }
        let descriptor = canonicalPath.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw sourceFilesystemError(
                path: canonicalPath, code: errno, operation: "openDirectoryNoFollow open")
        }
        var openedInfo = stat()
        guard Darwin.fstat(descriptor, &openedInfo) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw sourceFilesystemError(
                path: canonicalPath, code: code, operation: "openDirectoryNoFollow fstat")
        }
        guard (openedInfo.st_mode & S_IFMT) == S_IFDIR,
              openedInfo.st_dev == pathInfo.st_dev,
              openedInfo.st_ino == pathInfo.st_ino else {
            Darwin.close(descriptor)
            throw DatabaseError.sql("openDirectoryNoFollow: canonical root identity changed")
        }
        return descriptor
    }

    func verifyRootDescriptorStillNamed(_ descriptor: Int32, path: String) throws {
        var opened = stat()
        guard Darwin.fstat(descriptor, &opened) == 0 else {
            throw sourceFilesystemError(
                path: path, code: errno, operation: "verifyRootDescriptorStillNamed fstat")
        }
        var current = stat()
        let result = path.withCString { Darwin.lstat($0, &current) }
        guard result == 0 else {
            throw sourceFilesystemError(
                path: path, code: errno, operation: "verifyRootDescriptorStillNamed lstat")
        }
        guard (current.st_mode & S_IFMT) == S_IFDIR,
              opened.st_dev == current.st_dev,
              opened.st_ino == current.st_ino else {
            throw DatabaseError.sql(
                "verifyRootDescriptorStillNamed: root path changed during capture")
        }
    }

    func readRootFileNoFollow(
        rootDirectoryFD: Int32,
        relativePath: String,
        maximumBytes: Int?,
        tailBytes: Int? = nil,
        maximumTotalBytesRead: Int = Int.max,
        retainDescriptorForFinalCheck: Bool = false
    ) throws -> NoFollowFileRead {
        if let maximumBytes, maximumBytes < 0 {
            throw DatabaseError.sql("readRootFileNoFollow: negative byte limit")
        }
        guard maximumTotalBytesRead >= 0 else {
            throw DatabaseError.sql("readRootFileNoFollow: negative aggregate byte limit")
        }
        let components = relativePath.split(
            separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw DatabaseError.sql("readRootFileNoFollow: invalid relative path")
        }

        var parentFD = Darwin.dup(rootDirectoryFD)
        guard parentFD >= 0 else {
            throw DatabaseError.sql(
                "readRootFileNoFollow: dup failed: \(String(cString: strerror(errno)))")
        }
        for component in components.dropLast() {
            let next = String(component).withCString {
                Darwin.openat(
                    parentFD, $0,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            }
            guard next >= 0 else {
                let code = errno
                Darwin.close(parentFD)
                throw sourceFilesystemError(
                    path: relativePath, code: code,
                    operation: "readRootFileNoFollow parent openat")
            }
            Darwin.close(parentFD)
            parentFD = next
        }

        let leaf = String(components[components.count - 1])
        let fileFD = leaf.withCString {
            Darwin.openat(
                parentFD, $0,
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        }
        let openError = errno
        Darwin.close(parentFD)
        guard fileFD >= 0 else {
            throw sourceFilesystemError(
                path: relativePath, code: openError,
                operation: "readRootFileNoFollow leaf openat")
        }
        defer { Darwin.close(fileFD) }

        var initial = stat()
        guard Darwin.fstat(fileFD, &initial) == 0 else {
            throw sourceFilesystemError(
                path: relativePath, code: errno, operation: "readRootFileNoFollow fstat")
        }
        guard (initial.st_mode & S_IFMT) == S_IFREG, initial.st_size >= 0 else {
            throw DatabaseError.sql("readRootFileNoFollow: source is not a regular file")
        }
        let device = Int64(initial.st_dev)
        let inode = UInt64(initial.st_ino)
        let modificationDate = Date(
            timeIntervalSince1970: Double(initial.st_mtimespec.tv_sec)
                + Double(initial.st_mtimespec.tv_nsec) / 1_000_000_000)
        let initialSize = Int64(initial.st_size)
        let modificationNanoseconds =
            Int64(initial.st_mtimespec.tv_sec) * 1_000_000_000
            + Int64(initial.st_mtimespec.tv_nsec)
        func changeTime(_ info: stat) -> Int64 {
            Int64(info.st_ctimespec.tv_sec) * 1_000_000_000
                + Int64(info.st_ctimespec.tv_nsec)
        }
        var verifiedChangeTimeNanoseconds = changeTime(initial)
        var detachedSnapshot = false

        func rereadWindow(
            from offset: off_t, byteCount: Int) throws -> Data? {
            var fresh = Data()
            fresh.reserveCapacity(byteCount)
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while fresh.count < byteCount {
                let requestCount = min(buffer.count, byteCount - fresh.count)
                let amount = buffer.withUnsafeMutableBytes { raw -> Int in
                    guard let base = raw.baseAddress else { return -1 }
                    return Darwin.pread(fileFD, base, requestCount, offset + off_t(fresh.count))
                }
                if amount < 0 && errno == EINTR { continue }
                if amount < 0 {
                    throw sourceFilesystemError(
                        path: relativePath, code: errno,
                        operation: "readRootFileNoFollow reread")
                }
                guard amount > 0 else { return nil }
                fresh.append(contentsOf: buffer.prefix(amount))
            }
            return fresh
        }

        func verifyUnchanged(
            recheck readBytes: Data? = nil,
            windowStart: off_t = 0) throws {
            // 挂牌（过渡措施，非契约）：本校验只在「结算仍要读盘」时成立——它守的是
            // 这次 read 的字节没被并发改写，不回答「这条值现在还可不可信」。等结算
            // 不再读盘（内容进对象库、依赖按内容判同）时，verifyUnchanged 与
            // rereadWindow 一并删除。见 #147。
            if let hook = beforeRootFileVerificationForTesting {
                beforeRootFileVerificationForTesting = nil
                hook()
            }
            var finalInfo = stat()
            guard Darwin.fstat(fileFD, &finalInfo) == 0 else {
                throw sourceFilesystemError(
                    path: relativePath, code: errno,
                    operation: "readRootFileNoFollow final fstat")
            }
            guard finalInfo.st_dev == initial.st_dev,
                  finalInfo.st_ino == initial.st_ino,
                  finalInfo.st_size == initial.st_size,
                  finalInfo.st_mtimespec.tv_sec == initial.st_mtimespec.tv_sec,
                  finalInfo.st_mtimespec.tv_nsec == initial.st_mtimespec.tv_nsec else {
                throw DatabaseError.sourceChangedWhileBeingRead(path: relativePath)
            }
            let ctOK = finalInfo.st_ctimespec.tv_sec == initial.st_ctimespec.tv_sec
                && finalInfo.st_ctimespec.tv_nsec == initial.st_ctimespec.tv_nsec
            if ctOK {
                verifiedChangeTimeNanoseconds = changeTime(finalInfo)
                return
            }
            detachedSnapshot = true
            // ctime moves for metadata too — rename, link, chmod — so a bare
            // ctime change cannot tell a same-size rewrite (mtime restored, the
            // #146 case) from an untouched file whose inode was merely renamed.
            // Decide on bytes: re-read this exact window and require the content
            // we indexed, then require ctime to have held across that re-read.
            guard let readBytes, let fresh = try rereadWindow(
                from: windowStart, byteCount: readBytes.count), fresh == readBytes else {
                throw DatabaseError.sourceChangedWhileBeingRead(path: relativePath)
            }
            var afterReread = stat()
            guard Darwin.fstat(fileFD, &afterReread) == 0 else {
                throw sourceFilesystemError(
                    path: relativePath, code: errno,
                    operation: "readRootFileNoFollow post-reread fstat")
            }
            guard afterReread.st_ctimespec.tv_sec == finalInfo.st_ctimespec.tv_sec,
                  afterReread.st_ctimespec.tv_nsec == finalInfo.st_ctimespec.tv_nsec else {
                throw DatabaseError.sourceChangedWhileBeingRead(path: relativePath)
            }
            verifiedChangeTimeNanoseconds = changeTime(afterReread)
        }

        func descriptorForFinalCheck() throws -> Int32? {
            guard retainDescriptorForFinalCheck, detachedSnapshot else { return nil }
            let descriptor = Darwin.dup(fileFD)
            guard descriptor >= 0 else {
                throw DatabaseError.sql(
                    "readRootFileNoFollow: duplicate final-check descriptor failed: "
                        + String(cString: strerror(errno)))
            }
            return descriptor
        }

        if let maximumBytes, initialSize > Int64(maximumBytes) {
            // Append-only logs (agent session transcripts) grow past any cap;
            // the last window still answers "what was said recently", and the
            // ledger keeps its own full-size + digest bookkeeping. Callers that
            // do not ask for a tail window index the file without its bytes.
            guard let tailBytes, tailBytes > 0 else {
                try verifyUnchanged()
                return NoFollowFileRead(
                    data: nil, size: initialSize,
                    modificationDate: modificationDate,
                    modificationNanoseconds: modificationNanoseconds,
                    changeTimeNanoseconds: verifiedChangeTimeNanoseconds,
                    descriptorForFinalCheck: try descriptorForFinalCheck(),
                    detachedSnapshot: detachedSnapshot, device: device, inode: inode)
            }
            let expectedByteCount = Int(min(initialSize, Int64(tailBytes)))
            guard expectedByteCount <= maximumTotalBytesRead else {
                throw DatabaseError.sql(
                    "settleWorkRootContents: maxTotalBytesRead exceeded (\(maximumTotalBytesRead))")
            }
            let start = initialSize - Int64(expectedByteCount)
            guard Darwin.lseek(fileFD, off_t(start), SEEK_SET) == off_t(start) else {
                throw sourceFilesystemError(
                    path: relativePath, code: errno, operation: "readRootFileNoFollow seek")
            }
            var tail = Data()
            tail.reserveCapacity(expectedByteCount)
            var tailBuffer = [UInt8](repeating: 0, count: 64 * 1024)
            while tail.count < expectedByteCount {
                let requestCount = min(tailBuffer.count, expectedByteCount - tail.count)
                let amount = tailBuffer.withUnsafeMutableBytes { raw -> Int in
                    guard let base = raw.baseAddress else { return -1 }
                    return Darwin.read(fileFD, base, requestCount)
                }
                if amount < 0 && errno == EINTR { continue }
                guard amount >= 0 else {
                    throw sourceFilesystemError(
                        path: relativePath, code: errno, operation: "readRootFileNoFollow tail read")
                }
                if amount == 0 {
                    try verifyUnchanged()
                    throw DatabaseError.sql(
                        "readRootFileNoFollow: short or inconsistent tail read")
                }
                tail.append(contentsOf: tailBuffer.prefix(amount))
            }
            try verifyUnchanged(recheck: tail, windowStart: off_t(start))
            guard tail.count == expectedByteCount else {
                throw DatabaseError.sql(
                    "readRootFileNoFollow: short or inconsistent tail read")
            }
            return NoFollowFileRead(
                data: tail, size: initialSize,
                modificationDate: modificationDate,
                modificationNanoseconds: modificationNanoseconds,
                changeTimeNanoseconds: verifiedChangeTimeNanoseconds,
                descriptorForFinalCheck: try descriptorForFinalCheck(),
                detachedSnapshot: detachedSnapshot, device: device, inode: inode,
                isTail: true)
        }
        guard initialSize <= Int64(maximumTotalBytesRead) else {
            throw DatabaseError.sql(
                "settleWorkRootContents: maxTotalBytesRead exceeded (\(maximumTotalBytesRead))")
        }

        // Read exactly the size observed by fstat. Reading until EOF can consume
        // unbounded extra bytes if a file grows concurrently; the final fstat
        // rejects that mutation after at most the budgeted initial size is read.
        let expectedByteCount = Int(initialSize)
        var data = Data()
        data.reserveCapacity(expectedByteCount)
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while data.count < expectedByteCount {
            let requestCount = min(buffer.count, expectedByteCount - data.count)
            let amount = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.read(fileFD, base, requestCount)
            }
            if amount < 0 && errno == EINTR { continue }
            guard amount >= 0 else {
                throw sourceFilesystemError(
                    path: relativePath, code: errno, operation: "readRootFileNoFollow read")
            }
            if amount == 0 {
                try verifyUnchanged()
                throw DatabaseError.sql("readRootFileNoFollow: short or inconsistent file read")
            }
            data.append(contentsOf: buffer.prefix(amount))
        }
        try verifyUnchanged(recheck: data)
        guard Int64(data.count) == initialSize else {
            throw DatabaseError.sql("readRootFileNoFollow: short or inconsistent file read")
        }
        return NoFollowFileRead(
            data: data, size: initialSize,
            modificationDate: modificationDate,
            modificationNanoseconds: modificationNanoseconds,
            changeTimeNanoseconds: verifiedChangeTimeNanoseconds,
            descriptorForFinalCheck: try descriptorForFinalCheck(),
            detachedSnapshot: detachedSnapshot, device: device, inode: inode)
    }

    /// Component-aligned relative path. The enumerator can hand back a
    /// canonicalized path (`/private/var/...`) while the caller supplied
    /// `/var/...`; string-prefix matching would silently skip every file.
    private func relativePath(of file: URL, under root: URL) -> String {
        let rootParts = Array(root.pathComponents.dropFirst())
        let fileParts = Array(file.pathComponents.dropFirst())
        guard !rootParts.isEmpty, fileParts.count >= rootParts.count else {
            return rootParts.isEmpty ? fileParts.joined(separator: "/") : ""
        }
        for start in 0...(fileParts.count - rootParts.count)
        where Array(fileParts[start..<(start + rootParts.count)]) == rootParts {
            return fileParts[(start + rootParts.count)...].joined(separator: "/")
        }
        return ""
    }

    public struct RootReconcileReport: Equatable, Sendable {
        public let rootCount: Int
        public let settledRoots: Int
        public let freshRoots: Int
        public let missingRoots: Int
        /// Registered before the locator was retained and therefore not
        /// re-scannable until registered again. Not a scan failure.
        public let unlocatableRoots: Int
        public let failedRoots: Int
        public let scanned: Int
        public let reused: Int
        public let changed: Int
        public let removed: Int
        public let invalidatedSettlements: Int
    }

    /// Scan budget for one registered root: the file cap (4,096) times the
    /// per-file tail window (256 KB). Used by reconcile and by launch bootstrap
    /// instead of the conservative 64 MiB single-settlement ceiling, which made
    /// real desktop roots fail every launch (measured: 2.0 GB and 17.6 GB).
    public static let rootScanReadBudget = 4_096 * (256 << 10)

    /// Re-index roots that are reachable at this call. An unlocatable or
    /// inaccessible root is counted in this call's report only: no root status,
    /// file status, dependency, or settlement validity is changed. Directory
    /// absence cannot establish a source value change. `minAgeSeconds` skips
    /// roots that were scanned recently, which bounds launch-time work.
    ///
    /// `carryText` defaults to index-only: the product keeps a locator + digest
    /// per file and never copies entity bytes into the store.
    @discardableResult
    public func reconcileRegisteredRoots(
        category: String = "work", minAgeSeconds: TimeInterval = 0,
        carryText: Bool = false,
        maxTotalBytesRead: Int = ESISDatabase.rootScanReadBudget
    ) throws -> RootReconcileReport {
        let fm = FileManager.default
        let stmt = try prepare("""
        SELECT root_id, display_name, last_scanned_at FROM roots
        WHERE category=? ORDER BY root_id;
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, category)
        var rows: [(id: String, path: String?, scanned: String?)] = []
        while try stepRowOrDone(stmt) {
            func text(_ i: Int32) -> String? {
                sqlite3_column_text(stmt, i).map { String(cString: $0) }
            }
            rows.append((text(0) ?? "", text(1), text(2)))
        }
        try reset(stmt)

        var settledRoots = 0, freshRoots = 0, missingRoots = 0, failedRoots = 0
        var unlocatableRoots = 0
        var scanned = 0, reused = 0, changed = 0, removed = 0, invalidated = 0
        let now = Date()

        for row in rows {
            guard let path = row.path, !path.isEmpty else {
                unlocatableRoots += 1
                continue
            }
            if minAgeSeconds > 0, let scannedAt = row.scanned.flatMap(parseISO8601),
                now.timeIntervalSince(scannedAt) < minAgeSeconds
            {
                freshRoots += 1
                continue
            }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
                // Unavailable is a per-call observation only. Preserve the
                // registered root and every dependent historical value.
                missingRoots += 1
                continue
            }
            do {
                let result = try settleWorkRootContents(
                    rootID: row.id, rootURL: URL(fileURLWithPath: path),
                    category: category,
                    maxTotalBytesRead: maxTotalBytesRead,
                    carryText: carryText)
                settledRoots += 1
                scanned += result.scanned
                reused += result.reused
                changed += result.changed
                removed += result.removed
                invalidated += result.invalidatedSettlements
            } catch {
                if error is CancellationError { throw error }
                if let databaseError = error as? DatabaseError,
                   case .executionFailure = databaseError {
                    throw databaseError
                }
                failedRoots += 1
            }
        }

        return RootReconcileReport(
            rootCount: rows.count, settledRoots: settledRoots,
            freshRoots: freshRoots, missingRoots: missingRoots,
            unlocatableRoots: unlocatableRoots,
            failedRoots: failedRoots, scanned: scanned, reused: reused,
            changed: changed, removed: removed,
            invalidatedSettlements: invalidated)
    }

    // MARK: - Demand 驱动的信息检索（原研究 execute_demand 语义）

    public struct DemandRetrieval: Equatable, Sendable {
        public let demandID: String
        public let reused: Bool
        public let hits: [ContentHit]
        public let resultSHA256: String
        public let status: String
    }

    /// The canonical input basis of a demand: the query plus every settled
    /// file-content digest under the requested roots, in `root/path=sha` form,
    /// ordered by `(root_id, relative_path)`. One helper serves both the
    /// retrieval demand (`executeInformationDemand`) and settlement consumption,
    /// so both compare the SAME input basis. Passing nil or an empty root list
    /// means every registered root.
    public struct CanonicalDemandInput: Equatable, Sendable {
        public struct Entry: Equatable, Sendable {
            public let rootID: String
            public let relativePath: String
            public let contentSHA256: String
            public let objectID: String?

            public init(rootID: String, relativePath: String,
                        contentSHA256: String, objectID: String?) {
                self.rootID = rootID
                self.relativePath = relativePath
                self.contentSHA256 = contentSHA256
                self.objectID = objectID
            }
        }

        public let query: String
        public let rootIDs: [String]
        public let entries: [Entry]
        public let canonical: String
        public let digest: String

        public init(query: String, rootIDs: [String], entries: [Entry],
                    canonical: String, digest: String) {
            self.query = query
            self.rootIDs = rootIDs
            self.entries = entries
            self.canonical = canonical
            self.digest = digest
        }
    }

    /// Caller owns any transaction; the query reads the current settled content
    /// index, so a consumption computing this inside `BEGIN IMMEDIATE` cannot
    /// race a content settlement (which also opens a write transaction).
    public func canonicalDemandInput(
        query: String, rootIDs: [String]? = nil
    ) throws -> CanonicalDemandInput {
        var sql = "SELECT root_id, relative_path, content_sha256, object_id FROM file_contents"
        var bound: [String] = []
        if let rootIDs, !rootIDs.isEmpty {
            bound = Array(Set(rootIDs)).sorted()
            sql += " WHERE root_id IN ("
                + Array(repeating: "?", count: bound.count).joined(separator: ",") + ")"
        }
        sql += " ORDER BY root_id, relative_path;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        for (index, root) in bound.enumerated() {
            try bind(stmt, Int32(index + 1), root)
        }
        let reserved = "\u{001E}"
        guard !query.contains(reserved) else {
            throw DatabaseError.sql("canonicalDemandInput: query contains reserved U+001E")
        }
        if let rootIDs, rootIDs.contains(where: { $0.contains(reserved) }) {
            throw DatabaseError.sql("canonicalDemandInput: root scope contains reserved U+001E")
        }

        var digests: [String] = []
        var roots: [String] = []
        var entries: [CanonicalDemandInput.Entry] = []
        while try stepRowOrDone(stmt) {
            func col(_ i: Int32) -> String {
                sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
            }
            let root = col(0)
            let path = col(1)
            let sha = col(2)
            guard !root.contains(reserved), !path.contains(reserved) else {
                throw DatabaseError.sql(
                    "canonicalDemandInput: source root/path contains reserved U+001E")
            }
            digests.append("\(root)/\(path)=\(sha)")
            if !roots.contains(root) { roots.append(root) }
            let objectID = sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : col(3)
            entries.append(.init(rootID: root, relativePath: path,
                                 contentSHA256: sha, objectID: objectID))
        }

        // Preserve the historical byte-for-byte basis for ordinary components.
        // The legacy grammar is not injective when a component contains one of
        // its separators (query '|', entry ';', field '=' or root/path '/').
        let needsStructuredEncoding =
            query.contains(where: { "|;=".contains($0) }) ||
            entries.contains { entry in
                entry.rootID.contains(where: { "|;=/".contains($0) }) ||
                    entry.relativePath.contains(where: { "|;=".contains($0) })
            }
        let canonical: String
        if needsStructuredEncoding {
            let structured: [String: Any] = [
                "version": 2,
                "query": query,
                "entries": entries.map { entry in
                    [
                        "root_id": entry.rootID,
                        "relative_path": entry.relativePath,
                        "content_sha256": entry.contentSHA256,
                    ]
                },
            ]
            canonical = "\u{001E}simigo-demand-input-v2:" + (try Self.canonicalJSON(structured))
        } else {
            canonical = query + "|" + digests.joined(separator: ";")
        }
        return CanonicalDemandInput(
            query: query, rootIDs: roots, entries: entries,
            canonical: canonical,
            digest: NativeSHA256.hexDigest(Data(canonical.utf8)))
    }

    /// Legacy demand resolution. No production caller remains: the live path is
    /// `InformationLoop.resolve`, which adds the source bindings this
    /// function does not write. Kept because the tests and the stored-basis
    /// format (see `invalidateRetrievalSettlementsInTransaction`) still refer to
    /// it; do not wire new callers to it.
    ///
    /// 执行一次信息需求（demand）：
    ///   demand_id = SHA256(query + 注册根集合 + 全部已结算内容摘要的规范串联)
    /// 同一 demand 且结算有效 → 直接返回已结算结果（**不再重复计算**，即
    /// ES₁ 已结算关系对 ES₂ 合法复用）；任一输入摘要变化 → 新 demand，重算
    /// 并落新结算，旧结算置 invalidated。结果逐项摘要绑定，确定性 consumer
    /// 不造内容。
    ///
    /// 澄清（2026-11-16，owner 裁定 `ANOMALY_LEDGER_V0.1_20261116.md` A-09「改」）：上句「旧结算置
    /// invalidated」指**因源变更而失效**（`invalidateRetrievalSettlementsInTransaction` /
    /// `markSettlementsInvalidInTransaction`），**不是**同 query 的最新者胜清扫。本函数内曾有一条
    /// 按 `query` 匹配、排除自己的 UPDATE，把同 query 的其它结算一律判失效，与「互斥结算并存、
    /// 不提升任一为答案」的教义相反（`ConflictingSettlementTests`），已按该裁定删除；勿再加回。
    public func executeInformationDemand(
        query: String, rootID: String? = nil, limit: Int = 200
    ) throws -> DemandRetrieval {
        // The input basis, cache check, result scan and publication must observe
        // one database revision. BEGIN IMMEDIATE also prevents a competing root
        // settlement from changing file_contents between these stages.
        return try transactionResult {
            // 1) 输入摘要：查询 + 相关根的已结算内容摘要（规范排序串联）
            let canonicalInput = try canonicalDemandInput(
                query: query, rootIDs: rootID.map { [$0] })
            // 候选文件的地址必须可解析，缺了就报错。但候选不等于依赖：
            // 一次 demand 的 canonical input 是整个根的文件清单（实测一条
            // demand 带回约 700 个候选），把它们逐条写成依赖边，184k 条
            // 里 99% 都是候选清单，不是被引用的信息。
            for entry in canonicalInput.entries where entry.objectID == nil {
                // Index-only settlement: the address is the identity record's
                // metadata object, not a copy of the entity bytes.
                let identity = "file:\(entry.rootID)/\(entry.relativePath)"
                guard try latestIndexObjectID(identity: identity) != nil else {
                    throw DatabaseError.sql(
                        "executeInformationDemand: missing metadata object address for \(identity)")
                }
            }
            let canonical = canonicalInput.canonical
            // The result limit and filename-index matches both change the
            // persisted hit set, so they are part of retrieval identity.
            let effectiveLimit = max(0, limit)
            let filenameHits = try fileNameHits(
                query: query, rootID: rootID, limit: effectiveLimit)
            let demandBasis = try Self.canonicalJSON([
                "canonical_input": canonical,
                "root_scope": rootID.map { $0 as Any } ?? NSNull(),
                "result_limit": effectiveLimit,
                "filename_hits": filenameHits.map {
                    ["root_id": $0.rootID, "relative_path": $0.relativePath]
                },
            ])
            let demandID = NativeSHA256.hexDigest(Data(demandBasis.utf8))
            let roots = canonicalInput.rootIDs

            // Validate locator-backed bytes before considering a cached result:
            // settled database rows can be unchanged while physical files move.
            var currentHits = try searchSettledContent(
                query: query, rootID: rootID, limit: effectiveLimit,
                strictSourceValidation: true)
            if currentHits.isEmpty { currentHits = filenameHits }

            // 2) 复用检查：同 demand 且结算有效 → 读回已结算对象
            let settled = try prepare("""
            SELECT result_object_id, result_sha256, result_json FROM retrieval_settlements
            WHERE demand_id=? AND status='valid';
            """)
            try bind(settled, 1, demandID)
            let settledRC = sqlite3_step(settled)
            if settledRC == SQLITE_ROW {
                func col(_ i: Int32) -> String {
                    sqlite3_column_text(settled, i).map { String(cString: $0) } ?? ""
                }
                let objectID = col(0)
                let storedSHA = col(1)
                let legacyJSON = col(2)
                sqlite3_finalize(settled)

                let data: Data?
                if !objectID.isEmpty {
                    do {
                        if let hook = beforeDemandCacheObjectReadForTesting {
                            beforeDemandCacheObjectReadForTesting = nil
                            try hook(objectID)
                        }
                        data = try readObject(objectID)
                    } catch let error as DatabaseError {
                        // A missing or byte/address-mismatched cache object is a
                        // cache miss. A SQLite execution failure is a carrier
                        // failure and must not be hidden by recomputation.
                        guard case .sql = error else { throw error }
                        data = nil
                    }
                } else {
                    data = Data(legacyJSON.utf8)
                }
                if let data,
                    NativeSHA256.hexDigest(data) == storedSHA,
                    let rows = try? JSONDecoder().decode([ContentHit].self, from: data),
                    rows == currentHits
                {
                    return DemandRetrieval(
                        demandID: demandID, reused: true, hits: rows,
                        resultSHA256: storedSHA, status: "reused")
                }
            } else {
                sqlite3_finalize(settled)
                guard settledRC == SQLITE_DONE else {
                    throw Self.sqliteFailure(handle, resultCode: settledRC)
                }
            }

            // 3) 重算：在同一数据库快照上、逐一校验 locator 后的检索结果
            let hits = currentHits
            let resultData = try JSONEncoder().encode(hits)
            let resultSHA = NativeSHA256.hexDigest(resultData)

            // 4) 结果写入对象库，结算行只保留引用；索引追加 demand 身份
            let objectID = try ensureObject(resultData)
            // No latest-wins sweep. A statement here used to invalidate every
            // other retrieval settlement carrying the same query text. That
            // contradicted the doctrine that mutually exclusive settlements all
            // remain retrievable and none is promoted to "the answer"
            // (ConflictingSettlementTests), and it made a newer demand the sole
            // authority by side effect rather than by evidence. Staleness is
            // this row's own business: it is invalidated only when a source it
            // cited changes, through invalidateRetrievalSettlementsInTransaction
            // / markSettlementsInvalidInTransaction. Removed by owner ruling
            // 2026-11-16 (ANOMALY_LEDGER A-09); do not re-add.
            try execBinding("""
            INSERT INTO retrieval_settlements(
                demand_id, query, root_ids, root_ids_json, inputs_digest,
                result_sha256, result_json, hit_count, status, settled_at, result_object_id)
            VALUES(?,?,?,?,?,?,'',?,?,?,?)
            ON CONFLICT(demand_id) DO UPDATE SET
                query=excluded.query, root_ids=excluded.root_ids,
                root_ids_json=excluded.root_ids_json, inputs_digest=excluded.inputs_digest,
                result_sha256=excluded.result_sha256, result_json='',
                hit_count=excluded.hit_count, status='valid',
                settled_at=excluded.settled_at, result_object_id=excluded.result_object_id;
            """) { stmt in
                try bind(stmt, 1, demandID)
                try bind(stmt, 2, query)
                try bind(stmt, 3, roots.joined(separator: ","))
                try bind(stmt, 4, try Self.canonicalJSON(Array(Set(roots)).sorted()))
                try bind(stmt, 5, demandBasis)
                try bind(stmt, 6, resultSHA)
                try bind(stmt, 7, Int64(hits.count))
                try bind(stmt, 8, "valid")
                try bind(stmt, 9, Self.stamp(Date()))
                try bind(stmt, 10, objectID)
            }
            _ = try appendIndexEntryInTransaction(
                identity: "demand:\(demandID)", objectID: objectID)

            return DemandRetrieval(
                demandID: demandID, reused: false, hits: hits,
                resultSHA256: resultSHA, status: "settled")
        }
    }

    /// 文件名/路径命中的确定性 consumer（demand 结果的一部分）。
    private func fileNameHits(query: String, rootID: String?, limit: Int) throws -> [ContentHit] {
        guard limit > 0 else { return [] }
        var sql = """
        SELECT root_id, relative_path FROM external_files
        WHERE relative_path LIKE ? AND COALESCE(status,'present')='present'
        """
        if rootID != nil { sql += " AND root_id=" + Self.sqlQuotedLiteral(rootID!) }
        sql += " ORDER BY relative_path LIMIT \(limit);"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, "%" + query + "%")
        guard limit > 0 else { return [] }
        var hits: [ContentHit] = []
        while hits.count < limit {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                func col(_ i: Int32) -> String {
                    guard let c = sqlite3_column_text(stmt, i) else { return "" }
                    return String(cString: c)
                }
                hits.append(ContentHit(
                    rootID: col(0), relativePath: col(1), lineNo: 0,
                    lineText: col(1)))
                continue
            }
            guard rc == SQLITE_DONE else {
                throw Self.sqliteFailure(handle, resultCode: rc)
            }
            return hits
        }
        // The SQL query has the same LIMIT, so reaching this count is a
        // deliberate bounded completion rather than a partial error result.
        return hits
    }

    public struct ContentHit: Equatable, Sendable, Codable {
        public let rootID: String
        public let relativePath: String
        public let lineNo: Int
        public let lineText: String
    }

    /// 信息拓扑检索：在已结算的文件索引上按关键词命中（行级）。索引可以
    /// 只保存定位符 + 摘要（不拷贝实体），因此文本从注册根的定位符读取，
    /// 并**逐次校验结算摘要**：磁盘内容已变而尚未重新结算 → 该行不是命中，
    /// 由 ES 侧触发再结算（IS 只存/验，不判断语义）。
    public func searchSettledContent(query: String, rootID: String? = nil, limit: Int = 200)
        throws -> [ContentHit]
    {
        // Non-strict form: currently a test/query entry point only —
        // production demand settlement takes the strict overload below.
        // Historical content whose source is unavailable is skipped for this
        // call; a readable source whose digest changed is also skipped, but
        // remains separately classified by InformationLoop.
        try searchSettledContent(
            query: query, rootID: rootID, limit: limit,
            strictSourceValidation: false)
    }

    private func searchSettledContent(
        query: String, rootID: String?, limit: Int,
        strictSourceValidation: Bool
    ) throws -> [ContentHit] {
        guard !query.isEmpty, limit > 0 else { return [] }
        let rows = try settledFileRows(rootID: rootID)
        var hits: [ContentHit] = []
        for row in rows {
            let body: String
            do {
                body = try searchableFileText(row)
            } catch let error as DatabaseError {
                if !strictSourceValidation {
                    switch error {
                    case .staleExternalSource, .sourceUnavailable:
                        continue
                    default:
                        break
                    }
                }
                throw error
            }
            for (idx, line) in body.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.localizedCaseInsensitiveContains(query) {
                hits.append(ContentHit(
                    rootID: row.rootID, relativePath: row.relativePath,
                    lineNo: idx + 1, lineText: String(line.prefix(200))))
                if hits.count >= limit { return hits }
            }
        }
        return hits
    }

    struct SettledFileRow {
        let rootID: String
        let relativePath: String
        let digest: String
        let objectID: String?
        let legacy: Data
        let indexedSize: Int64?
    }

    func settledFileRows(rootID: String?) throws -> [SettledFileRow] {
        try settledFileRows(rootIDs: rootID.map { [$0] })
    }

    /// Compatibility collection API. InformationLoop uses the row callback below
    /// so a root with many settled files does not retain every legacy BLOB at once.
    func settledFileRows(rootIDs: [String]?) throws -> [SettledFileRow] {
        var rows: [SettledFileRow] = []
        try forEachSettledFileRow(rootIDs: rootIDs) { rows.append($0) }
        return rows
    }

    /// Visit one settled file row at a time. An empty or nil scope retains the
    /// historical all-roots behavior; non-empty scopes are pushed into SQLite.
    func forEachSettledFileRow(
        rootIDs: [String]?, _ body: (SettledFileRow) throws -> Void
    ) throws {
        let scopedRootIDs = Array(Set(rootIDs ?? [])).sorted()
        var sql = """
        SELECT f.root_id, f.relative_path, f.content_sha256, f.object_id, f.content, e.size
        FROM file_contents f
        LEFT JOIN external_files e
          ON e.root_id=f.root_id AND e.relative_path=f.relative_path
        """
        if !scopedRootIDs.isEmpty {
            let placeholders = Array(repeating: "?", count: scopedRootIDs.count)
                .joined(separator: ",")
            sql += " WHERE f.root_id IN (\(placeholders))"
        }
        sql += " ORDER BY f.root_id COLLATE BINARY, f.relative_path COLLATE BINARY;"
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        for (index, rootID) in scopedRootIDs.enumerated() {
            try bind(stmt, Int32(index + 1), rootID)
        }
        while true {
            try checkInformationScanCancellation()
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                func text(_ i: Int32) -> String? {
                    sqlite3_column_text(stmt, i).map { String(cString: $0) }
                }
                let bytes = Int(sqlite3_column_bytes(stmt, 4))
                let legacy = sqlite3_column_blob(stmt, 4).map { Data(bytes: $0, count: bytes) } ?? Data()
                let indexedSize: Int64? = sqlite3_column_type(stmt, 5) == SQLITE_NULL
                    ? nil : sqlite3_column_int64(stmt, 5)
                try body(SettledFileRow(
                    rootID: text(0) ?? "", relativePath: text(1) ?? "",
                    digest: text(2) ?? "", objectID: text(3),
                    legacy: legacy, indexedSize: indexedSize))
                continue
            }
            guard rc == SQLITE_DONE else {
                throw Self.sqliteFailure(handle, resultCode: rc)
            }
            return
        }
    }

    /// Resolve and verify every settled text row. Missing, unreadable or changed
    /// index-only sources are errors, not ordinary no-match results: silently
    /// skipping one would let a partial retrieval be persisted under a full basis.
    ///
    /// 一条 root 的身份缺口是例外：它先走内容自证（R-17②），证不出来才降级成
    /// `.staleExternalSource`（R-17①）——单点存疑不拖垮整库检索。
    /// The two callers of the shared index-only source reader, and the only
    /// places they deliberately differ: retrieval surfaces a vanished source as
    /// a stale marker (and owns the self-proving loop that may re-pin to the
    /// directory's current identity and adopt an unusable locator when the
    /// content proves it is the same root), while the content query answers a
    /// vanished or unlocatable source with nil.
    enum IndexOnlySourceContext {
        case retrieval(provingRootIdentity: Bool)
        case contentQuery

        var label: String {
            switch self {
            case .retrieval: return "searchableFileText"
            case .contentQuery: return "carriedFileContent"
            }
        }
    }

    /// The shared spine of the two index-only live-source reads: pin the
    /// registered root identity (or, in the self-proving loop, the directory's
    /// current identity), prove the opened directory is the same directory we
    /// checked, validate the index-only metadata contract (locator / sha256 /
    /// size), then read the tail window or the bounded full file and verify the
    /// framed digest. Returns nil only under `.contentQuery` for a vanished or
    /// unlocatable source; every mismatch throws. The directory fd is opened,
    /// re-verified (verifyRootDescriptorStillNamed) and closed inside.
    func indexOnlySourceData(
        rootID: String, relativePath: String, digest: String,
        indexedSize: Int64?, context: IndexOnlySourceContext
    ) throws -> Data? {
        let label = context.label
        func stale() -> DatabaseError {
            .staleExternalSource(rootID: rootID, relativePath: relativePath)
        }
        guard let locator = try rootLocatorPath(rootID) else {
            if case .contentQuery = context { return nil }
            throw DatabaseError.sourceUnavailable(
                rootID: rootID, relativePath: relativePath)
        }
        guard !relativePath.isEmpty,
            !relativePath.split(separator: "/").contains("..")
        else {
            if case .contentQuery = context { return nil }
            throw DatabaseError.sql(
                "\(label): invalid relative path for \(rootID)/\(relativePath)")
        }
        func isContentQuery(_ context: IndexOnlySourceContext) -> Bool {
            if case .contentQuery = context { return true }
            return false
        }
        func mapGone<T>(_ body: () throws -> T) throws -> T {
            do {
                return try body()
            } catch ESISDatabase.DatabaseError.sourceGone {
                throw DatabaseError.sourceUnavailable(
                    rootID: rootID, relativePath: relativePath)
            } catch ESISDatabase.DatabaseError.sourceReadUnavailable {
                throw DatabaseError.sourceUnavailable(
                    rootID: rootID, relativePath: relativePath)
            }
        }
        // Index-only bytes still live at a path. Pin that path to the registered
        // root identity before opening it, then prove the opened descriptor is
        // the same directory we checked.
        //
        // 钉桩失败不再等于「整库检索不可用」。旗标本身有理由：换卷/迁移之后
        // device+inode 变了，不能默认还是同一个目录，fail-closed 是对的。没有
        // 道理的是 fail 的**粒度**，以及清旗以前只能人工介入。所以先让内容自己
        // 作证（②）；证不出来就只把这一条 root 降级为不参与本次检索（①），其余
        // root 照常。严格路径照旧把这个 stale 抛出去记账，不会因此发布残缺基准。
        let snapshot: RootLocatorSnapshot
        switch context {
        case .retrieval(let provingRootIdentity):
            if provingRootIdentity {
                // 自证回路要的是「这个目录当下的真身」，不是数据库记的那一对，
                // 所以走 static 的 lstat 而不是可被测试探针改写的实例方法。
                let identity = try mapGone { try Self.directoryIdentity(atPath: locator) }
                snapshot = RootLocatorSnapshot(
                    path: URL(fileURLWithPath: locator, isDirectory: true)
                        .standardizedFileURL.path,
                    device: identity.device, inode: UInt64(bitPattern: identity.inode))
            } else {
                do {
                    snapshot = try mapGone { try rootLocatorSnapshot(rootID: rootID) }
                } catch let error as DatabaseError {
                    guard case .rootLocatorUnusable = error else { throw error }
                    guard try mapGone({
                        try adoptRootIdentityIfContentProvesSame(rootID: rootID)
                    }) else {
                        throw DatabaseError.staleExternalSource(
                            rootID: rootID, relativePath: relativePath)
                    }
                    snapshot = try mapGone { try rootLocatorSnapshot(rootID: rootID) }
                }
            }
        case .contentQuery:
            do {
                snapshot = try rootLocatorSnapshot(rootID: rootID)
            } catch let error as DatabaseError {
                switch error {
                case .sourceGone, .sourceReadUnavailable:
                    return nil
                default:
                    throw error
                }
            }
        }
        guard snapshot.path == URL(fileURLWithPath: locator, isDirectory: true)
                .standardizedFileURL.path else {
            throw DatabaseError.sql(
                "\(label): registered root path now resolves elsewhere")
        }
        let rootDirectoryFD: Int32
        do {
            rootDirectoryFD = try openDirectoryNoFollow(atPath: locator)
        } catch let error as DatabaseError {
            if isContentQuery(context) {
                switch error {
                case .sourceGone, .sourceReadUnavailable: return nil
                default: throw error
                }
            }
            switch error {
            case .sourceGone, .sourceReadUnavailable:
                throw DatabaseError.sourceUnavailable(
                    rootID: rootID, relativePath: relativePath)
            default:
                throw error
            }
        }
        defer { Darwin.close(rootDirectoryFD) }
        var openedRoot = stat()
        guard Darwin.fstat(rootDirectoryFD, &openedRoot) == 0 else {
            throw DatabaseError.sourceUnavailable(
                rootID: rootID, relativePath: relativePath)
        }
        guard Int64(openedRoot.st_dev) == snapshot.device,
              UInt64(openedRoot.st_ino) == snapshot.inode else {
            throw DatabaseError.sql(
                "\(label): opened root does not match its registered identity")
        }

        // Index-only metadata is itself a content-addressed object. It records
        // whether the settled digest covers the whole file or a tail window and
        // the exact raw window size needed to reproduce that digest.
        let identity = "file:\(rootID)/\(relativePath)"
        func readSource(
            maximumBytes: Int?, tailBytes: Int? = nil,
            maximumTotalBytesRead: Int
        ) throws -> NoFollowFileRead? {
            do {
                return try readRootFileNoFollow(
                    rootDirectoryFD: rootDirectoryFD,
                    relativePath: relativePath,
                    maximumBytes: maximumBytes,
                    tailBytes: tailBytes,
                    maximumTotalBytesRead: maximumTotalBytesRead)
            } catch let error as DatabaseError {
                if isContentQuery(context) {
                    switch error {
                    case .sourceGone, .sourceReadUnavailable: return nil
                    default: throw error
                    }
                }
                switch error {
                case .sourceGone, .sourceReadUnavailable:
                    throw DatabaseError.sourceUnavailable(
                        rootID: rootID, relativePath: relativePath)
                default:
                    throw error
                }
            }
        }
        guard let metadataObjectID = try latestIndexObjectID(identity: identity),
              !metadataObjectID.isEmpty else {
            throw DatabaseError.sql(
                "\(label): missing index-only metadata for \(rootID)/\(relativePath)")
        }
        let metadataData = try readObject(metadataObjectID)
        guard let metadata = try JSONSerialization.jsonObject(with: metadataData)
                as? [String: Any],
              let metadataLocator = metadata["locator"] as? String,
              let metadataDigest = metadata["sha256"] as? String,
              let metadataSize = metadata["size"] as? Int64,
              metadataSize >= 0 else {
            throw DatabaseError.sql(
                "\(label): malformed index-only metadata for \(rootID)/\(relativePath)")
        }
        guard metadataLocator == identity, metadataDigest == digest,
              indexedSize == nil || indexedSize == metadataSize else {
            throw stale()
        }

        if metadata["is_tail"] as? Bool == true {
            let maximumTailReadBytes = 64 * 1024 * 1024
            guard let tailWindowBytes = metadata["tail_bytes"] as? Int,
                  tailWindowBytes > 0, tailWindowBytes <= maximumTailReadBytes,
                  metadataSize > 0, metadataSize <= Int64(Int.max) else {
                throw stale()
            }
            guard let read = try readSource(
                maximumBytes: tailWindowBytes - 1,
                tailBytes: tailWindowBytes,
                // Force the bounded tail path based on the read window, not
                // the original full source size. If the source shrank but is
                // still larger than the tail budget, a size-based threshold
                // would try to read the whole changed file and throw a generic
                // budget error instead of classifying it as stale.
                maximumTotalBytesRead: tailWindowBytes) else {
                return nil
            }
            guard read.isTail, read.size == metadataSize, let rawTail = read.data else {
                throw stale()
            }
            let indexedData = Self.indexedTailData(rawTail)
            let framed = NativeSHA256.hexDigest(
                Data("tail:\(metadataSize):".utf8) + indexedData)
            guard framed == digest else {
                throw stale()
            }
            do {
                try verifyRootDescriptorStillNamed(rootDirectoryFD, path: locator)
            } catch let error as DatabaseError {
                if isContentQuery(context) {
                    switch error {
                    case .sourceGone, .sourceReadUnavailable: return nil
                    default: throw error
                    }
                }
                switch error {
                case .sourceGone, .sourceReadUnavailable:
                    throw DatabaseError.sourceUnavailable(
                        rootID: rootID, relativePath: relativePath)
                default:
                    throw error
                }
            }
            return indexedData
        }

        // Full-file index-only revalidation is bounded independently of the
        // caller's custom scan limits; larger sources require a tail marker.
        let maximumFullReadBytes = 64 * 1024 * 1024
        guard metadataSize <= Int64(maximumFullReadBytes) else {
            throw stale()
        }
        guard let read = try readSource(
            maximumBytes: Int(metadataSize),
            maximumTotalBytesRead: maximumFullReadBytes) else { return nil }
        guard !read.isTail, read.size == metadataSize, let data = read.data,
              NativeSHA256.hexDigest(data) == digest else {
            throw stale()
        }
        do {
            try verifyRootDescriptorStillNamed(rootDirectoryFD, path: locator)
        } catch let error as DatabaseError {
            if isContentQuery(context) {
                switch error {
                case .sourceGone, .sourceReadUnavailable: return nil
                default: throw error
                }
            }
            switch error {
            case .sourceGone, .sourceReadUnavailable:
                throw DatabaseError.sourceUnavailable(
                    rootID: rootID, relativePath: relativePath)
            default:
                throw error
            }
        }
        return data
    }

    func searchableFileText(_ row: SettledFileRow) throws -> String {
        try searchableFileText(row, provingRootIdentity: false)
    }

    /// `provingRootIdentity` 只在下面那条自证回路里为 true：那时注册身份还没被
    /// 采纳，钉桩必然失败、也不该失败——要证的是「还是这批字节」，不是「还是这个
    /// 挂载点」。除此之外两条路径共用同一份逐字节口径，不另写第二套 digest 框架。
    private func searchableFileText(
        _ row: SettledFileRow, provingRootIdentity: Bool
    ) throws -> String {
        if let objectID = row.objectID, !objectID.isEmpty {
            let data = try readObject(objectID)
            if NativeSHA256.hexDigest(data) == row.digest {
                return String(decoding: data, as: UTF8.self)
            }
            // A carried tail is stored as the indexed text window, while its
            // content digest is framed with the full source size. Verify that
            // representation instead of comparing it to a whole-file digest.
            if let indexedSize = row.indexedSize, indexedSize >= 0,
               NativeSHA256.hexDigest(Data("tail:\(indexedSize):".utf8) + data) == row.digest {
                return String(decoding: data, as: UTF8.self)
            }
            throw DatabaseError.sql(
                "searchableFileText: carried object digest mismatch for \(row.rootID)/\(row.relativePath)")
        }
        if !row.legacy.isEmpty {
            if NativeSHA256.hexDigest(row.legacy) == row.digest {
                return String(decoding: row.legacy, as: UTF8.self)
            }
            if let indexedSize = row.indexedSize, indexedSize >= 0,
               NativeSHA256.hexDigest(Data("tail:\(indexedSize):".utf8) + row.legacy) == row.digest {
                return String(decoding: row.legacy, as: UTF8.self)
            }
            throw DatabaseError.sql(
                "searchableFileText: legacy content digest mismatch for \(row.rootID)/\(row.relativePath)")
        }
        guard let data = try indexOnlySourceData(
            rootID: row.rootID, relativePath: row.relativePath,
            digest: row.digest, indexedSize: row.indexedSize,
            context: .retrieval(provingRootIdentity: provingRootIdentity))
        else {
            // .retrieval never answers nil; the compiler needs this branch.
            throw DatabaseError.staleExternalSource(
                rootID: row.rootID, relativePath: row.relativePath)
        }
        return String(decoding: data, as: UTF8.self)
    }

    func rootLocatorPath(_ rootID: String) throws -> String? {
        let stmt = try prepare("""
        SELECT display_name FROM roots
        WHERE root_id=? AND locator_type='path';
        """)
        defer { sqlite3_finalize(stmt) }
        try bind(stmt, 1, rootID)
        guard try stepRowOrDone(stmt), let c = sqlite3_column_text(stmt, 0)
        else { return nil }
        let path = String(cString: c)
        return path.isEmpty ? nil : URL(fileURLWithPath: path).standardizedFileURL.path
    }

    /// Persistent directory identity is the POSIX (device, inode) pair:
    /// inode numbers are only unique within one filesystem. Inode 0 remains
    /// unsupported for persistent identity, but the pair still pins one capture.
    static func directoryIdentity(atPath path: String) throws -> RootDirectoryIdentity {
        var info = stat()
        let result = path.withCString { Darwin.lstat($0, &info) }
        guard result == 0 else {
            throw sourceFilesystemError(
                path: path, code: errno, operation: "directoryIdentity")
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR else {
            throw DatabaseError.sql("directoryIdentity: not a directory: \(path)")
        }
        return RootDirectoryIdentity(device: Int64(info.st_dev), inode: Int64(info.st_ino))
    }

    /// Compatibility helper for callers that only need to know whether an inode
    /// is available. Persistent root checks must use directoryIdentity instead.
    static func directoryINode(atPath path: String) throws -> Int64? {
        let identity = try directoryIdentity(atPath: path)
        return identity.inode == 0 ? nil : identity.inode
    }

    func rootDirectoryIdentity(atPath path: String) throws -> RootDirectoryIdentity {
        if let probe = rootDirectoryIdentityProbeForTesting {
            return try probe(path)
        }
        return try Self.directoryIdentity(atPath: path)
    }

    /// 记下或比对 root 所在目录的 device/inode pair。返回 true 表示「还是这个路径，
    /// 但不是这个目录了」。第一次见到就记下来；README 里那三种挂载形状都靠它分开。
    @discardableResult
    func noteLocatorIdentity(rootID: String, path: String) throws -> Bool {
        let current = try rootDirectoryIdentity(atPath: path)

        let storedDevice: Int64?
        let storedInode: Int64?
        let identityUnverified: Bool
        do {
            let stmt = try prepare("""
                SELECT locator_device, locator_inode, locator_identity_unverified
                  FROM roots WHERE root_id=?;
                """)
            defer { sqlite3_finalize(stmt) }
            try bind(stmt, 1, rootID)
            guard try stepRowOrDone(stmt) else {
                throw DatabaseError.sql("noteLocatorIdentity: unknown root \(rootID)")
            }
            storedDevice = sqlite3_column_type(stmt, 0) != SQLITE_NULL
                ? sqlite3_column_int64(stmt, 0) : nil
            storedInode = sqlite3_column_type(stmt, 1) != SQLITE_NULL
                ? sqlite3_column_int64(stmt, 1) : nil
            identityUnverified = sqlite3_column_int(stmt, 2) != 0
        }

        // Migration v39 marks every legacy row whose pair cannot be proven.
        // Keep its inventory isolated until a user explicitly adopts this path.
        if identityUnverified { return true }

        if current.inode == 0 {
            // Device + inode 0 is not unique within one filesystem. A new root
            // without a persistent inode cannot safely acquire an inventory.
            if storedDevice != nil || storedInode != nil { return true }
            throw DatabaseError.sql(
                "noteLocatorIdentity: filesystem does not provide a persistent directory inode")
        }
        guard let storedInode else {
            guard storedDevice == nil else {
                throw DatabaseError.sql("noteLocatorIdentity: incomplete persisted root identity")
            }
            try execBinding("""
            UPDATE roots SET locator_device=?, locator_inode=? WHERE root_id=?;
            """) { stmt in
                try bind(stmt, 1, current.device)
                try bind(stmt, 2, current.inode)
                try bind(stmt, 3, rootID)
            }
            return false
        }
        // A legacy row that could not be upgraded during migration has no
        // trustworthy device baseline. Do not silently infer it during a scan.
        guard let storedDevice else { return true }
        return storedDevice != current.device || storedInode != current.inode
    }

    /// 人确认「还是同一个目录，只是换了挂载」之后调用：把当前 device/inode pair 收作它的。
    public func adoptRootLocatorIdentity(rootID: String) throws {
        guard let path = try rootLocatorPath(rootID) else {
            throw DatabaseError.sql(
                "adoptRootLocatorIdentity: no directory behind \(rootID)")
        }
        let identity = try rootDirectoryIdentity(atPath: path)
        guard identity.inode != 0 else {
            throw DatabaseError.sql(
                "adoptRootLocatorIdentity: filesystem does not provide a persistent inode")
        }
        try execBinding("""
        UPDATE roots
           SET locator_device=?, locator_inode=?, locator_identity_unverified=0
         WHERE root_id=?;
        """) { stmt in
            try bind(stmt, 1, identity.device)
            try bind(stmt, 2, identity.inode)
            try bind(stmt, 3, rootID)
        }
    }

    /// 自动采纳留下的审计行落在 append-only 索引里（与 C 阶段失败审计同一套
    /// 机制，不新建表、不加迁移）：identity = `root-identity-adoption:<root_id>`，
    /// 只增不改，用 `resolveIndexIdentity` + `readObject` 就能原样读回。
    public static let rootIdentityAdoptionIndexPrefix = "root-identity-adoption:"
    public static let rootIdentityAdoptionSchema = "root-identity-adoption-v1"

    public static func rootIdentityAdoptionIdentity(rootID: String) -> String {
        rootIdentityAdoptionIndexPrefix + rootID
    }

    /// 内容 digest 自证同一 → 自动采纳，并记审计行（R-17②）。
    ///
    /// 用的尺比 device/inode 更直接：**已结算字节自己**。该 root 每一条
    /// index-only 行都从注册定位符读回，按检索那同一份口径（含 tail 窗口）比对
    /// 结算 digest，全部一致才采纳。携带对象与库内正文这两条快路径不碰磁盘、
    /// 证不了目录，跳过；一条 index-only 行都没有就等于没有证据，也不采纳。
    ///
    /// 采纳与审计同一个事务：审计写不进去就不采纳——宁可降级，也不留一次没人
    /// 知道的身份变更。任何证明失败都只让这一条 root 降级、不外抛；代价是真正
    /// 的载体故障在这里也会被报成 stale，但严格路径仍会把它记账，不是静默。
    ///
    /// 边界：**重定向不是身份缺口**。注册路径被换成符号链接指向别处时照旧大声
    /// 拒绝，既不降级也不采纳；目录整个没了抛 `sourceGone`，由调用方收成 stale。
    ///
    /// 复杂度：证明失败时该 root 每条 index-only 行都会重跑一次证明（证明在首个
    /// 不一致处停下），最坏 O(n·k)。裁定针对的换卷/迁移场景里证明是成功的，一次
    /// 就清旗，走不到这里。
    private func adoptRootIdentityIfContentProvesSame(rootID: String) throws -> Bool {
        guard let locator = try rootLocatorPath(rootID) else { return false }
        // 复用 `openDirectoryNoFollow` 的第一道 guard（realpath 之后必须仍等于
        // 注册路径）来分辨「重定向」与「身份缺口」，不另写第二把尺。
        let probeFD = try openDirectoryNoFollow(atPath: locator)
        Darwin.close(probeFD)
        var proved = 0
        var unproved = false
        try forEachSettledFileRow(rootIDs: [rootID]) { row in
            guard !unproved else { return }
            guard (row.objectID ?? "").isEmpty, row.legacy.isEmpty else { return }
            do {
                if let hook = beforeRootIdentityProofForTesting {
                    beforeRootIdentityProofForTesting = nil
                    try hook()
                }
                _ = try searchableFileText(row, provingRootIdentity: true)
                proved += 1
            } catch {
                if error is CancellationError { throw error }
                if let databaseError = error as? DatabaseError,
                   case .executionFailure = databaseError {
                    throw databaseError
                }
                unproved = true
            }
        }
        guard proved > 0, !unproved else { return false }
        let event: [String: Any] = [
            "schema_version": Self.rootIdentityAdoptionSchema,
            "root_id": rootID,
            "reason": "settled content digests prove the same root",
            "proved_index_only_files": proved,
            "recorded_at": SnapshotContract.timestamp(Date()),
        ]
        do {
            try transaction {
                try adoptRootLocatorIdentity(rootID: rootID)
                let objectID = try ensureObject(
                    try JSONSerialization.data(
                        withJSONObject: event,
                        options: [.sortedKeys, .withoutEscapingSlashes]))
                _ = try appendIndexEntryInTransaction(
                    identity: Self.rootIdentityAdoptionIdentity(rootID: rootID),
                    objectID: objectID)
            }
        } catch {
            if error is CancellationError { throw error }
            if let databaseError = error as? DatabaseError,
               case .executionFailure = databaseError {
                throw databaseError
            }
            return false
        }
        return true
    }

}
