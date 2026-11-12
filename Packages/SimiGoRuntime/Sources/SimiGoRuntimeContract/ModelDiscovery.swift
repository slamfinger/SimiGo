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
public enum ModelDiscovery {
    public static let cacheRootID = "huggingface-cache"
    private static let weightExtensions: Set<String> = ["gguf", "safetensors", "bin", "metal", "ckpt"]

    public static func discover(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fm: FileManager = .default,
        hubs: [URL]? = nil
    ) -> [DiscoveredModel] {
        var found: [DiscoveredModel] = []
        for hub in (hubs ?? ManagedPaths.huggingFaceCacheCandidates(env: env)) {
            guard let repoDirs = try? fm.contentsOfDirectory(at: hub,
                       includingPropertiesForKeys: [.isDirectoryKey], options: []) else { continue }
            let resolvedHub = hub.resolvingSymlinksInPath().standardizedFileURL
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
                        var isDirectory: ObjCBool = false
                        guard fm.fileExists(atPath: file.path, isDirectory: &isDirectory),
                              !isDirectory.boolValue else { continue }
                        // Hugging Face snapshot files are commonly symlinks into
                        // this cache's blobs/ directory. Keep those aliases, but
                        // never advertise a snapshot symlink whose target escapes
                        // the configured cache root.
                        let resolvedFile = file.resolvingSymlinksInPath().standardizedFileURL
                        guard isDescendant(resolvedFile, of: resolvedHub) else { continue }
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

extension ModelDiscovery {
    /// Resolve a portable reference back to a local file URL by searching the
    /// runtime HF cache candidate roots (HF_HUB_CACHE → HF_HOME/hub →
    /// ~/.cache/huggingface/hub). A reference is a path, not a normalization
    /// request: ambiguous components are rejected instead of silently folded.
    /// The target must remain inside the same resolved cache root after symlinks
    /// are followed. This still accepts the normal snapshot → blobs symlink.
    public static func resolve(_ ref: ModelReference,
                               env: [String: String] = ProcessInfo.processInfo.environment,
                               fm: FileManager = .default) -> URL? {
        guard ref.rootID == cacheRootID,
              isValidRelativePath(ref.relativePath) else { return nil }

        for hub in ManagedPaths.huggingFaceCacheCandidates(env: env) {
            guard isDirectory(hub, fm: fm) else { continue }
            let lexicalRoot = hub.standardizedFileURL
            let candidate = lexicalRoot.appendingPathComponent(ref.relativePath)
                .standardizedFileURL
            var isDirectoryValue: ObjCBool = false
            guard fm.fileExists(atPath: candidate.path, isDirectory: &isDirectoryValue),
                  !isDirectoryValue.boolValue else { continue }

            let resolvedRoot = hub.resolvingSymlinksInPath().standardizedFileURL
            let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
            guard isDescendant(resolvedCandidate, of: resolvedRoot) else { continue }
            // Return the snapshot locator, not the blob target: the relative
            // reference remains stable and retains Hugging Face's snapshot alias.
            return candidate
        }
        return nil
    }

    /// Derive a portable reference from a legacy absolute path by matching it
    /// against the runtime cache roots. Both the supplied path and its resolved
    /// target are checked: a lexical in-root symlink to an external file is not
    /// a valid durable reference.
    public static func reference(forAbsolutePath path: String,
                                 env: [String: String] = ProcessInfo.processInfo.environment,
                                 fm: FileManager = .default) -> ModelReference? {
        guard path.hasPrefix("/"), !path.contains("\\0") else { return nil }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        var isDirectoryValue: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectoryValue),
              !isDirectoryValue.boolValue else { return nil }
        let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL

        for hub in ManagedPaths.huggingFaceCacheCandidates(env: env) {
            guard isDirectory(hub, fm: fm) else { continue }
            let lexicalRoot = hub.standardizedFileURL
            let resolvedRoot = hub.resolvingSymlinksInPath().standardizedFileURL
            guard isDescendant(resolvedURL, of: resolvedRoot) else { continue }

            // Prefer the lexical path so a snapshot → blob symlink is persisted
            // as the snapshot reference. The fallbacks cover callers that used
            // the resolved cache-root path or an external alias to an in-root
            // target; all are rechecked against the same canonical target.
            let relative = relativePathString(of: url, under: lexicalRoot)
                ?? relativePathString(of: url, under: resolvedRoot)
                ?? relativePathString(of: resolvedURL, under: resolvedRoot)
            guard let relative, isValidRelativePath(relative) else { continue }

            let candidate = lexicalRoot.appendingPathComponent(relative).standardizedFileURL
            let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
            guard isDescendant(resolvedCandidate, of: resolvedRoot),
                  resolvedCandidate.path == resolvedURL.path else { continue }
            return ModelReference(rootID: cacheRootID, relativePath: relative)
        }
        return nil
    }

    private static func isValidRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\0") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty else { return false }
        return components.allSatisfy { component in
            !component.isEmpty && component != "." && component != ".."
        }
    }

    private static func isDirectory(_ url: URL, fm: FileManager) -> Bool {
        var isDirectoryValue: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDirectoryValue)
            && isDirectoryValue.boolValue
    }

    private static func isDescendant(_ candidate: URL, of root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        let prefix = rootPath == "/" ? "/" : rootPath + "/"
        return candidatePath != rootPath && candidatePath.hasPrefix(prefix)
    }

    private static func relativePathString(of file: URL, under root: URL) -> String? {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        let prefix = rootPath == "/" ? "/" : rootPath + "/"
        guard filePath.hasPrefix(prefix) else { return nil }
        return String(filePath.dropFirst(prefix.count))
    }
}
