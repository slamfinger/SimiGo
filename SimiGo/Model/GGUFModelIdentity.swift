import CryptoKit
import Darwin
import Darwin
import Foundation
import SimiGoRuntimeContract

enum GGUFModelIdentityError: LocalizedError, Equatable {
    case notAFile(String)
    case unreadable(String)
    case changedDuringRead(String)

    var errorDescription: String? {
        switch self {
        case .notAFile(let path): return "GGUF 模型不是可读文件: \(path)"
        case .unreadable(let path): return "GGUF 模型内容无法读取: \(path)"
        case .changedDuringRead(let path): return "GGUF 模型在身份核验期间发生变化: \(path)"
        }
    }
}

/// Content identity of the GGUF checkpoint a runtime actually loads.
///
/// The binding digest is derived from the model BYTES. Repository/revision/root
/// are recorded as provenance evidence only and never replace the content
/// digest: two files with the same name and size but different bytes must not
/// admit each other's settlements, and the same bytes reached through the HF
/// cache or a local copy describe the same producer.
///
/// The tokenizer is embedded in the GGUF container, so its identity is bound to
/// the model file digest. It is explicitly labelled as a model-file-bound
/// tokenizer identity, NOT an independently computed tokenizer digest.
///
/// One instance is resolved at runtime start and shared by the information-turn
/// producer, continuation admission and continuation settlement, so all three
/// derive the same value from the same file.
struct GGUFModelIdentity: Equatable, Sendable {
    /// Non-hex prefix for the per-file fallback marker produced by
    /// `unreadableMarker(forPath:)`. It can never be mistaken for a content digest.
    static let unreadableMarker = "unreadable"
    /// The digest ledger is a disposable cache, never a reason to allocate
    /// unbounded memory or trust a symlinked/non-owned file.
    static let maximumBlobLedgerBytes = 8 * 1024 * 1024
    static let maximumBlobLedgerEntries = 4_096
    static let maximumResolvedCacheEntries = 4_096

    enum ContentSource: String, Equatable, Sendable {
        /// A Hugging Face cache blob: a file inside `models--<repo>/blobs/` whose
        /// name equals the SHA-256 of its own bytes. The name is checked against
        /// the digest of the bytes, not taken on faith (see
        /// `verifiedBlobDigest`); the hash itself is memoised per file version.
        case huggingFaceCacheBlob
        /// Every other file: streamed SHA-256 over the actual contents.
        case fileContents
    }

    let contentSHA256: String
    let byteCount: Int64
    let contentSource: ContentSource
    let resolvedPath: String
    let repository: String?
    let revision: String?
    let rootID: String?

    /// Durable identity for execution states and producer bindings.
    let modelIdentity: String
    let producer: SettlementIdentityBinding.Identity

    /// Hash results keyed by the file's identity-bearing attributes. `identity()`
    /// runs on every admission, settlement and consumption, and a checkpoint is
    /// multi-GB: re-hashing per request would cost seconds each time. A replaced
    /// or rewritten file has a different size/mtime/inode and therefore misses.
    private final class ResolvedCache: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String: GGUFModelIdentity] = [:]
        private var insertionOrder: [String] = []

        func value(for key: String) -> GGUFModelIdentity? {
            lock.lock()
            defer { lock.unlock() }
            return entries[key]
        }

        func store(_ identity: GGUFModelIdentity, for key: String) {
            lock.lock()
            defer { lock.unlock() }
            insertionOrder.removeAll { $0 == key }
            insertionOrder.append(key)
            entries[key] = identity
            while insertionOrder.count > GGUFModelIdentity.maximumResolvedCacheEntries {
                let oldest = insertionOrder.removeFirst()
                entries[oldest] = nil
            }
        }
    }

    private static let resolvedCache = ResolvedCache()

    static func resolve(path: String, hubs: [URL]? = nil) throws -> GGUFModelIdentity {
        let original = URL(fileURLWithPath: path).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: original.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            throw GGUFModelIdentityError.notAFile(path)
        }
        let resolved = original.resolvingSymlinksInPath()

        // Provenance is part of the cached value, so a call with its own `hubs`
        // skips the cache: a hit must never hand back another hub's answer.
        let fileIdentity = identityParts(of: resolved)
        let fileStamp = fileIdentity.map { "\(resolved.path)|\($0.stamp)" }
        let cacheKey = hubs == nil ? fileStamp : nil
        if let cacheKey, let hit = resolvedCache.value(for: cacheKey) {
            guard identityStamp(of: resolved) == cacheKey else {
                throw GGUFModelIdentityError.changedDuringRead(resolved.path)
            }
            return hit
        }

        let digest: String
        let source: ContentSource
        if let claimedName = huggingFaceBlobName(for: resolved) {
            let actual = try verifiedBlobDigest(of: resolved)
            digest = actual
            if actual == claimedName {
                source = .huggingFaceCacheBlob
            } else {
                // The name is a convention, the bytes are the object. A blob
                // rewritten under its old name must lose the identity it no
                // longer holds instead of inheriting settlements from it.
                Service.log(
                    "HF blob 名与字节摘要不一致，以字节为准: \(resolved.path)",
                    level: .warning)
                source = .fileContents
            }
        } else {
            digest = try streamingSHA256(of: resolved, expectedIdentity: fileIdentity)
            if let fileIdentity, identityParts(of: resolved) != fileIdentity {
                throw GGUFModelIdentityError.changedDuringRead(resolved.path)
            }
            source = .fileContents
        }
        if let fileStamp, identityStamp(of: resolved) != fileStamp {
            throw GGUFModelIdentityError.changedDuringRead(resolved.path)
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let provenance = provenance(for: original, resolved: resolved, hubs: hubs)
        let modelIdentity = contentFingerprint(sha256: digest, byteCount: size)

        let identity = GGUFModelIdentity(
            contentSHA256: digest,
            byteCount: size,
            contentSource: source,
            resolvedPath: resolved.path,
            repository: provenance.repository,
            revision: provenance.revision,
            rootID: provenance.rootID,
            modelIdentity: modelIdentity,
            producer: SettlementIdentityBinding.Identity(
                model: modelIdentity,
                tokenizer: tokenizerFingerprint(modelContentSHA256: digest)))
        if let cacheKey { resolvedCache.store(identity, for: cacheKey) }
        return identity
    }

    /// File identity used by both the in-memory resolver cache and the durable
    /// HF blob digest memo. ctime is essential: an in-place rewrite can preserve
    /// inode, size and even restore mtime, while ctime still changes.
    private struct FileIdentityParts: Equatable {
        let size: Int64
        let device: UInt64
        let inode: UInt64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        let changedSeconds: Int64
        let changedNanoseconds: Int64

        var stamp: String {
            "\(device):\(inode):\(size):\(modifiedSeconds):\(modifiedNanoseconds):"
                + "\(changedSeconds):\(changedNanoseconds)"
        }
    }

    private static func identityStamp(of url: URL) -> String? {
        guard let parts = identityParts(of: url) else { return nil }
        return "\(url.path)|\(parts.stamp)"
    }

    private static func identityParts(of url: URL) -> FileIdentityParts? {
        var info = stat()
        // `Darwin.stat` is shadowed by the `stat` struct on some toolchains (the CI
        // runner reads it as a call to the struct's memberwise init), so ask through
        // `fstatat`, whose name has no struct twin. Flags 0 follow a symlinked model
        // the way the content read below does.
        guard url.path.withCString({ Darwin.fstatat(AT_FDCWD, $0, &info, 0) }) == 0
        else { return nil }
        return identityParts(from: info)
    }

    private static func identityParts(from info: stat) -> FileIdentityParts? {
        guard (info.st_mode & S_IFMT) == S_IFREG, info.st_size >= 0 else { return nil }
        return FileIdentityParts(
            size: Int64(info.st_size),
            device: UInt64(info.st_dev),
            inode: UInt64(info.st_ino),
            modifiedSeconds: Int64(info.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec),
            changedSeconds: Int64(info.st_ctimespec.tv_sec),
            changedNanoseconds: Int64(info.st_ctimespec.tv_nsec))
    }

    /// An unreadable file cannot be identified by its contents. Keep that
    /// fallback local to this exact filesystem object instead of assigning the
    /// same constant marker to every file with the same byte count. A file that
    /// cannot even be stat'ed gets a one-call nonce and therefore fails closed
    /// on the next identity derivation.
    static func unreadableMarker(forPath path: String) -> String {
        let resolved = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let stamp = identityParts(of: resolved)?.stamp ?? UUID().uuidString
        return "\(unreadableMarker):\(resolved.path):\(stamp)"
    }

    /// Content digest only. Byte count is included so a hash collision across
    /// differently sized files is still a distinct identity.
    static func contentFingerprint(sha256: String, byteCount: Int64) -> String {
        ProducerIdentity.canonicalFingerprint([
            "model_format": "gguf",
            "content_sha256": sha256,
            "content_bytes": byteCount,
        ])
    }

    static func tokenizerFingerprint(modelContentSHA256: String) -> String {
        ProducerIdentity.canonicalFingerprint([
            "tokenizer_scope": "embedded_in_model_file",
            "derivation": "model_file_bound",
            "model_content_sha256": modelContentSHA256,
        ])
    }

    /// The name an HF cache blob claims, or nil when the resolved target is not
    /// shaped like one. Only a regular file in `models--<repo>/blobs/<64-hex>` —
    /// the layout the hub writes — gets that far, so an ordinary local file
    /// cannot masquerade as a content-addressed blob by being named like one.
    ///
    /// This is a *name*, not a digest: `verifiedBlobDigest` is what turns it
    /// into an identity.
    static func huggingFaceBlobName(for resolved: URL) -> String? {
        let name = resolved.lastPathComponent.lowercased()
        guard name.count == 64, name.allSatisfy({ $0.isHexDigit }) else { return nil }
        let blobs = resolved.deletingLastPathComponent()
        guard blobs.lastPathComponent == "blobs",
              blobs.deletingLastPathComponent().lastPathComponent.hasPrefix("models--")
        else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else { return nil }
        return name
    }

    /// SHA-256 of the blob's actual bytes.
    ///
    /// A blob name is a claim the hub makes, and nothing in the file system
    /// keeps it true: a truncated download, an in-place edit or a corrupt copy
    /// leaves the name and changes the bytes. Hashing a multi-GB checkpoint on
    /// every launch would be too expensive to pay for that check, so the digest
    /// is remembered against the file's identity stamp: the first resolve of a
    /// file version hashes it, later ones (and later launches) reuse the
    /// verdict until the file itself changes.
    static func verifiedBlobDigest(of url: URL) throws -> String {
        let before = identityParts(of: url)
        if let before,
           let recorded = blobLedger.digest(path: url.path, identityStamp: before.stamp) {
            guard identityParts(of: url) == before else {
                throw GGUFModelIdentityError.changedDuringRead(url.path)
            }
            return recorded
        }

        let digest = try streamingSHA256(of: url, expectedIdentity: before)
        if let before {
            // Never bind a digest to a stamp sampled after the read: the file
            // must still be the exact object/version whose bytes were hashed.
            guard identityParts(of: url) == before else {
                throw GGUFModelIdentityError.changedDuringRead(url.path)
            }
            blobLedger.record(
                path: url.path, identityStamp: before.stamp, sha256: digest)
        }
        return digest
    }

    /// Durable memo of verified blob digests. It is a cache, never an
    /// authority: deleting it costs one re-hash and changes no identity.
    struct BlobDigestLedger: Codable, Equatable {
        struct Entry: Codable, Equatable {
            var identityStamp: String
            var sha256: String
            var verifiedAt: Date
        }
        var entries: [String: Entry] = [:]
    }

    /// Tests point this at their own temporary file so no test writes into the
    /// user's managed root.
    static var blobLedgerURLOverride: URL?

    private static let blobLedger = BlobLedgerStore()

    private final class BlobLedgerStore: @unchecked Sendable {
        private let lock = NSLock()
        /// Cached by URL: an override that moves the file must not be served
        /// from the previous location's copy.
        private var loaded: (url: URL, ledger: BlobDigestLedger)?

        private var url: URL {
            GGUFModelIdentity.blobLedgerURLOverride
                ?? ManagedPaths.managedRoot()
                    .appendingPathComponent("model-content-digests.json")
        }

        func digest(path: String, identityStamp: String) -> String? {
            lock.lock()
            defer { lock.unlock() }
            guard let entry = ledger().entries[path],
                  entry.identityStamp == identityStamp else { return nil }
            return entry.sha256
        }

        func record(path: String, identityStamp: String, sha256: String) {
            lock.lock()
            defer { lock.unlock() }
            var entries = ledger().entries
            entries[path] = BlobDigestLedger.Entry(
                identityStamp: identityStamp, sha256: sha256, verifiedAt: Date())
            entries = entries.filter {
                FileManager.default.fileExists(atPath: $0.key)
            }

            // Retain the newest verified entries first. A path that no longer
            // exists is removed above; a large but live model library is still
            // bounded by both entry count and the encoded byte limit.
            if entries.count > GGUFModelIdentity.maximumBlobLedgerEntries {
                let newest = entries.sorted {
                    if $0.value.verifiedAt != $1.value.verifiedAt {
                        return $0.value.verifiedAt < $1.value.verifiedAt
                    }
                    return $0.key < $1.key
                }.suffix(GGUFModelIdentity.maximumBlobLedgerEntries)
                entries = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
            }

            var bounded = BlobDigestLedger(entries: entries)
            var encoded = try? JSONEncoder().encode(bounded)
            while let data = encoded,
                  data.count > GGUFModelIdentity.maximumBlobLedgerBytes,
                  let oldest = entries.min(by: {
                      if $0.value.verifiedAt != $1.value.verifiedAt {
                          return $0.value.verifiedAt < $1.value.verifiedAt
                      }
                      return $0.key < $1.key
                  })?.key
            {
                entries.removeValue(forKey: oldest)
                bounded = BlobDigestLedger(entries: entries)
                encoded = try? JSONEncoder().encode(bounded)
            }
            loaded = (url, bounded)
            guard let data = encoded,
                  data.count <= GGUFModelIdentity.maximumBlobLedgerBytes else { return }
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }

        private func ledger() -> BlobDigestLedger {
            let url = self.url
            if let loaded, loaded.url == url { return loaded.ledger }
            let value = readLedger(at: url)
            loaded = (url, value)
            return value
        }

        /// Read one bounded, owned regular file through a no-follow descriptor.
        /// Any bad cache state is a miss: the caller re-hashes the model bytes.
        private func readLedger(at url: URL) -> BlobDigestLedger {
            let descriptor = url.path.withCString {
                Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            }
            guard descriptor >= 0 else { return BlobDigestLedger() }
            defer { Darwin.close(descriptor) }

            var before = stat()
            guard Darwin.fstat(descriptor, &before) == 0,
                  (before.st_mode & S_IFMT) == S_IFREG,
                  before.st_uid == getuid(),
                  before.st_nlink == 1,
                  before.st_size >= 0,
                  before.st_size <= off_t(GGUFModelIdentity.maximumBlobLedgerBytes)
            else {
                return BlobDigestLedger()
            }

            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let count = buffer.withUnsafeMutableBytes { raw in
                    Darwin.read(descriptor, raw.baseAddress, raw.count)
                }
                if count > 0 {
                    guard count <= GGUFModelIdentity.maximumBlobLedgerBytes - data.count else {
                        return BlobDigestLedger()
                    }
                    data.append(contentsOf: buffer.prefix(count))
                } else if count == 0 {
                    break
                } else if errno != EINTR {
                    return BlobDigestLedger()
                }
            }

            var after = stat()
            guard Darwin.fstat(descriptor, &after) == 0,
                  before.st_dev == after.st_dev,
                  before.st_ino == after.st_ino,
                  before.st_size == after.st_size,
                  before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
                  before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
                  before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
                  before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
                  let value = try? JSONDecoder().decode(BlobDigestLedger.self, from: data),
                  value.entries.count <= GGUFModelIdentity.maximumBlobLedgerEntries,
                  value.entries.values.allSatisfy({
                      $0.sha256.count == 64 && $0.sha256.allSatisfy { $0.isHexDigit }
                  })
            else {
                return BlobDigestLedger()
            }
            return value
        }
    }

    static func streamingSHA256(of url: URL) throws -> String {
        try streamingSHA256(of: url, expectedIdentity: nil)
    }

    /// Hash one opened regular-file descriptor, not a pathname that can be
    /// swapped between stat and open. The descriptor identity is checked before
    /// and after the read; callers that sampled the path first pass that identity
    /// so a replacement before open is refused as well.
    private static func streamingSHA256(
        of url: URL, expectedIdentity: FileIdentityParts?
    ) throws -> String {
        let descriptor = url.path.withCString {
            Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw GGUFModelIdentityError.unreadable(url.path)
        }
        defer { Darwin.close(descriptor) }

        var beforeInfo = stat()
        guard Darwin.fstat(descriptor, &beforeInfo) == 0,
              let openedIdentity = identityParts(from: beforeInfo)
        else {
            throw GGUFModelIdentityError.unreadable(url.path)
        }
        if let expectedIdentity, openedIdentity != expectedIdentity {
            throw GGUFModelIdentityError.changedDuringRead(url.path)
        }

        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 4 * 1024 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { raw in
                Darwin.read(descriptor, raw.baseAddress, raw.count)
            }
            if count > 0 {
                hasher.update(data: Data(buffer.prefix(count)))
                if Task.isCancelled { throw CancellationError() }
            } else if count == 0 {
                break
            } else if errno != EINTR {
                throw GGUFModelIdentityError.unreadable(url.path)
            }
        }

        var afterInfo = stat()
        guard Darwin.fstat(descriptor, &afterInfo) == 0,
              identityParts(from: afterInfo) == openedIdentity
        else {
            throw GGUFModelIdentityError.changedDuringRead(url.path)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func provenance(
        for original: URL, resolved: URL, hubs: [URL]?
    ) -> (repository: String?, revision: String?, rootID: String?) {
        let match = ModelDiscovery.discover(hubs: hubs).first {
            isWithin(original.path, $0.fileURL.standardizedFileURL.path)
                || isWithin(resolved.path, $0.fileURL.standardizedFileURL.path)
        }
        guard let match else { return (nil, nil, nil) }
        return (match.repoID, match.revision, match.rootID)
    }

    private static func isWithin(_ path: String, _ root: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
}
