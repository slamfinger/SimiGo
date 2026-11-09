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
    enum ContentSource: String, Equatable, Sendable {
        /// A Hugging Face cache blob whose file name is its own SHA-256. The
        /// structure is verified before the name is trusted; multi-GB weights
        /// are not re-hashed on every start.
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

    static func resolve(path: String, hubs: [URL]? = nil) throws -> GGUFModelIdentity {
        let original = URL(fileURLWithPath: path).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: original.path, isDirectory: &isDirectory),
              !isDirectory.boolValue
        else {
            throw GGUFModelIdentityError.notAFile(path)
        }
        let resolved = original.resolvingSymlinksInPath()

        let digest: String
        let source: ContentSource
        if let blob = huggingFaceBlobDigest(for: resolved) {
            digest = blob
            source = .huggingFaceCacheBlob
        } else {
            digest = try streamingSHA256(of: resolved)
            source = .fileContents
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let provenance = provenance(for: original, resolved: resolved, hubs: hubs)
        let modelIdentity = contentFingerprint(sha256: digest, byteCount: size)

        return GGUFModelIdentity(
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

    /// The HF hub names blobs by the SHA-256 of their contents and snapshots
    /// link to them. The fast path is accepted only when the resolved target is
    /// a regular file in `models--<repo>/blobs/<64-hex>` — i.e. the layout the
    /// hub writes — so an ordinary local file can never masquerade as a
    /// content-addressed blob just by being named like one.
    static func huggingFaceBlobDigest(for resolved: URL) -> String? {
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
