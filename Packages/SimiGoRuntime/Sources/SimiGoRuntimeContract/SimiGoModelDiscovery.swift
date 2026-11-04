import Foundation

/// A model found in an external runtime cache. It carries BOTH a durable
/// (root_id + relative_path) identity — the authority SimiGo persists — and a
/// convenience absolute URL for the current machine only. The absolute URL is
/// never treated as portable state; weights are never copied into `.simigo`.
public struct DiscoveredModel: Equatable, Sendable {
    public let repoID: String          // e.g. "Qwen/foo-4bit"
    public let revision: String?       // snapshot hash when resolvable
    public let rootID: String          // stable root id, e.g. "huggingface-cache"
    public let relativePath: String    // path relative to the cache root
    public let fileURL: URL            // local absolute (non-authoritative)
    public let sizeBytes: Int64
}

/// Discovers existing models from the Hugging Face cache location the runtime
/// actually resolves to (HF_HUB_CACHE → HF_HOME/hub → ~/.cache/huggingface/hub),
/// WITHOUT moving anything into SimiGo.
public enum SimiGoModelDiscovery {
    public static let cacheRootID = "huggingface-cache"
    private static let weightExtensions: Set<String> = ["gguf", "safetensors", "bin", "metal", "ckpt"]

    public static func discover(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fm: FileManager = .default,
        hubs: [URL]? = nil
    ) -> [DiscoveredModel] {
        var found: [DiscoveredModel] = []
        for hub in (hubs ?? SimiGoPaths.huggingFaceCacheCandidates(env: env)) {
            guard let repoDirs = try? fm.contentsOfDirectory(at: hub,
                       includingPropertiesForKeys: [.isDirectoryKey], options: []) else { continue }
            for repoDir in repoDirs where repoDir.lastPathComponent.hasPrefix("models--") {
                let repoID = repoDir.lastPathComponent
                    .replacingOccurrences(of: "models--", with: "")
                    .replacingOccurrences(of: "--", with: "/")
                let snapshots = repoDir.appendingPathComponent("snapshots", isDirectory: true)
                guard let revDirs = try? fm.contentsOfDirectory(at: snapshots,
                           includingPropertiesForKeys: nil, options: []) else { continue }
                for rev in revDirs {
                    let revision = rev.lastPathComponent
                    guard let files = try? fm.contentsOfDirectory(at: rev,
                               includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { continue }
                    for file in files where weightExtensions.contains(file.pathExtension.lowercased()) {
                        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
                        let rel = relativePath(of: file, under: hub)
                        found.append(DiscoveredModel(repoID: repoID, revision: revision,
                                                     rootID: cacheRootID, relativePath: rel,
                                                     fileURL: file, sizeBytes: size))
                    }
                }
            }
        }
        return found.sorted {
            ($0.repoID, $0.relativePath) < ($1.repoID, $1.relativePath)
        }
    }

    private static func relativePath(of file: URL, under root: URL) -> String {
        let a = file.standardizedFileURL.path
        let b = root.standardizedFileURL.path
        if a.hasPrefix(b + "/") { return String(a.dropFirst(b.count + 1)) }
        return file.lastPathComponent
    }
}

/// A portable, persistable model identity: the durable authority is ALWAYS
/// (root_id + relative_path), never an absolute local path. The absolute locator
/// is derived at runtime from the external cache roots and is treated as machine
/// convenience only — models are never copied into `.simigo`.
public struct ModelReference: Codable, Equatable, Hashable, Sendable {
    public let rootID: String
    public let relativePath: String
    public init(rootID: String, relativePath: String) {
        self.rootID = rootID
        self.relativePath = relativePath
    }
    public init(_ model: DiscoveredModel) {
        self.rootID = model.rootID
        self.relativePath = model.relativePath
    }
}

extension SimiGoModelDiscovery {
    /// Resolve a portable reference back to a local file URL by searching the
    /// runtime HF cache candidate roots (HF_HUB_CACHE → HF_HOME/hub →
    /// ~/.cache/huggingface/hub). Fail-closed: returns nil when the model is not
    /// present under any known root — it NEVER invents a path and NEVER relocates
    /// a model into `.simigo`.
    public static func resolve(_ ref: ModelReference,
                               env: [String: String] = ProcessInfo.processInfo.environment,
                               fm: FileManager = .default) -> URL? {
        guard ref.rootID == cacheRootID, !ref.relativePath.isEmpty else { return nil }
        // Reject references that try to escape the cache root.
        let normalized = ref.relativePath.split(separator: "/").filter { $0 != "." && $0 != ".." }
        guard ref.relativePath.hasPrefix("/") == false, !normalized.isEmpty else { return nil }
        let rel = normalized.joined(separator: "/")
        for hub in SimiGoPaths.huggingFaceCacheCandidates(env: env) {
            let candidate = hub.appendingPathComponent(rel)
            if fm.fileExists(atPath: candidate.standardizedFileURL.path) {
                return candidate.standardizedFileURL
            }
        }
        return nil
    }

    /// Derive a portable reference from a legacy absolute path by matching it
    /// against the runtime cache roots. Returns nil when the path is outside every
    /// known root, so the caller can fail closed instead of storing a bare
    /// absolute path as the durable identity.
    public static func reference(forAbsolutePath path: String,
                                 env: [String: String] = ProcessInfo.processInfo.environment,
                                 fm: FileManager = .default) -> ModelReference? {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard fm.fileExists(atPath: url.path) else { return nil }
        for hub in SimiGoPaths.huggingFaceCacheCandidates(env: env) {
            let b = hub.standardizedFileURL.path
            if url.path.hasPrefix(b + "/") {
                return ModelReference(rootID: cacheRootID,
                                      relativePath: String(url.path.dropFirst(b.count + 1)))
            }
        }
        return nil
    }
}
