import CryptoKit
import Foundation
import SimiGoRuntimeContract

enum GGUFModelIdentityError: LocalizedError, Equatable {
    case notAFile(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .notAFile(let path): return "GGUF 模型不是可读文件: \(path)"
        case .unreadable(let path): return "GGUF 模型内容无法读取: \(path)"
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
    /// The value a checkpoint gets when its bytes cannot be read. It is not a hex
    /// string on purpose: it can never be mistaken for, or collide with, a real
    /// digest, and two unreadable files never look like the same model by accident.
    static let unreadableMarker = "unreadable"

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

        func value(for key: String) -> GGUFModelIdentity? {
            lock.lock()
            defer { lock.unlock() }
            return entries[key]
        }

        func store(_ identity: GGUFModelIdentity, for key: String) {
            lock.lock()
            defer { lock.unlock() }
            entries[key] = identity
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
        let cacheKey =
            hubs == nil ? identityStamp(of: resolved) : nil
        if let cacheKey, let hit = resolvedCache.value(for: cacheKey) { return hit }

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
            digest = try streamingSHA256(of: resolved)
            source = .fileContents
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

    /// Everything a hash depends on. A rewrite that keeps size and mtime but
    /// changes bytes still changes the inode in every realistic copy path; a
    /// same-inode in-place rewrite within one filesystem timestamp tick is the
    /// only miss, and that one is indistinguishable by stat anywhere.
    private static func identityStamp(of url: URL) -> String? {
        guard let parts = identityParts(of: url) else { return nil }
        return "\(url.path)|\(parts.size)|\(parts.inode)|\(parts.modified)"
    }

    private static func identityParts(of url: URL) -> (size: Int64, inode: UInt64, modified: Double)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.int64Value,
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        else { return nil }
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return (size, inode, modified)
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
        if let parts = identityParts(of: url),
           let recorded = blobLedger.digest(
               path: url.path, size: parts.size, inode: parts.inode,
               modified: parts.modified) {
            return recorded
        }
        let digest = try streamingSHA256(of: url)
        if let parts = identityParts(of: url) {
            blobLedger.record(
                path: url.path, size: parts.size, inode: parts.inode,
                modified: parts.modified, sha256: digest)
        }
        return digest
    }

    /// Durable memo of verified blob digests. It is a cache, never an
    /// authority: deleting it costs one re-hash and changes no identity.
    struct BlobDigestLedger: Codable, Equatable {
        struct Entry: Codable, Equatable {
            var size: Int64
            var inode: UInt64
            var modified: Double
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

        func digest(path: String, size: Int64, inode: UInt64, modified: Double) -> String? {
            lock.lock()
            defer { lock.unlock() }
            guard let entry = ledger().entries[path] else { return nil }
            guard entry.size == size, entry.inode == inode, entry.modified == modified
            else { return nil }
            return entry.sha256
        }

        func record(path: String, size: Int64, inode: UInt64, modified: Double, sha256: String) {
            lock.lock()
            defer { lock.unlock() }
            var value = ledger()
            value.entries[path] = BlobDigestLedger.Entry(
                size: size, inode: inode, modified: modified, sha256: sha256,
                verifiedAt: Date())
            // Entries for files that no longer exist can never be consulted;
            // dropping them keeps the file bounded by the model library.
            value.entries = value.entries.filter {
                FileManager.default.fileExists(atPath: $0.key)
            }
            loaded = (url, value)
            guard let data = try? JSONEncoder().encode(value) else { return }
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }

        private func ledger() -> BlobDigestLedger {
            let url = self.url
            if let loaded, loaded.url == url { return loaded.ledger }
            let value = (try? Data(contentsOf: url)).flatMap {
                try? JSONDecoder().decode(BlobDigestLedger.self, from: $0)
            } ?? BlobDigestLedger()
            loaded = (url, value)
            return value
        }
    }

    static func streamingSHA256(of url: URL) throws -> String {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw GGUFModelIdentityError.unreadable(url.path)
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
                hasher.update(data: chunk)
                if Task.isCancelled { throw CancellationError() }
            }
        } catch let error as GGUFModelIdentityError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GGUFModelIdentityError.unreadable(url.path)
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
