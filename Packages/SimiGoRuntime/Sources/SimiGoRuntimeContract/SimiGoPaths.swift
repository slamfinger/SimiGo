import Foundation

/// Single runtime path resolver for the SimiGo product.
///
/// All managed locations are derived from a home directory resolved at runtime
/// (or the `SIMIGO_HOME` override used by tests / non-standard installs), so no
/// developer-machine absolute path is ever written into code, config, or the DB.
/// The managed root intentionally contains NO `work/` and NO `models/` children:
/// user work directories and model weights stay external and are only indexed by
/// `root_id + relative path` (see `RootReference`).
public enum SimiGoPaths {

    /// Directory names that must NEVER be created under the managed root.
    public static let forbiddenSubdirectories: Set<String> = ["work", "models"]

    /// The managed `.simigo` root. `SIMIGO_HOME` overrides the derived location;
    /// otherwise it is `<current-user-home>/.simigo` resolved via Foundation.
    public static func managedRoot(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = env["SIMIGO_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).standardizingPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".simigo", isDirectory: true)
    }

    public static var bin: URL { managedRoot().appendingPathComponent("bin", isDirectory: true) }
    public static var sources: URL { managedRoot().appendingPathComponent("sources", isDirectory: true) }
    public static var build: URL { managedRoot().appendingPathComponent("build", isDirectory: true) }
    public static var manifests: URL { managedRoot().appendingPathComponent("manifests", isDirectory: true) }
    public static var logs: URL { managedRoot().appendingPathComponent("logs", isDirectory: true) }
    public static var staging: URL { managedRoot().appendingPathComponent("staging", isDirectory: true) }
    public static var locks: URL { managedRoot().appendingPathComponent("locks", isDirectory: true) }

    /// The authoritative ES/IS database file (Phase 2). Lives directly in the managed root.
    public static var databaseURL: URL { managedRoot().appendingPathComponent("simigo.sqlite3") }

    /// The subdirectories bootstrap is allowed to create (idempotent). Never `work`/`models`.
    public static let creatableSubdirectories: [URL] = [bin, sources, build, manifests, logs, staging, locks]

    /// Names of the runtime subdirectories that MAY be created under a managed root.
    /// "work" and "models" are intentionally absent and are forbidden (see forbiddenSubdirectories).
    public static let creatableSubdirectoryNames: [String] = ["bin", "sources", "build", "manifests", "logs", "staging", "locks"]

    /// External Hugging Face cache candidates, in priority order. Honors
    /// `HF_HUB_CACHE` and `HF_HOME` when set, else the `<home>/.cache/huggingface/hub`
    /// convention. These are references only — models are never copied into `.simigo`.
    public static func huggingFaceCacheCandidates(env: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        var out: [URL] = []
        if let hub = env["HF_HUB_CACHE"], !hub.isEmpty {
            out.append(URL(fileURLWithPath: (hub as NSString).standardizingPath, isDirectory: true))
        }
        if let home = env["HF_HOME"], !home.isEmpty {
            out.append(URL(fileURLWithPath: (home as NSString).standardizingPath, isDirectory: true)
                .appendingPathComponent("hub", isDirectory: true))
        }
        let derived = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache", isDirectory: true)
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("hub", isDirectory: true)
        if !out.contains(derived) { out.append(derived) }
        return out
    }

    public enum PathError: Error, Equatable {
        case relativeEscape(String)
        case notRelative(String)
    }

    /// A portable external-root reference: a stable `rootID` plus a normalized
    /// `relativePath`. No absolute path is stored; the local absolute URL is only
    /// produced by resolving against a root that the caller has located (or a
    /// security-scoped bookmark) at runtime.
    public struct RootReference: Codable, Sendable, Hashable {
        public let rootID: String
        public let relativePath: String

        public init(rootID: String, relativePath: String) {
            self.rootID = rootID
            self.relativePath = relativePath
        }

        /// Resolve the relative path against `root`, rejecting `..` components that
        /// would escape the root and absolute inputs. Symlink containment is the
        /// caller's responsibility (it needs the real filesystem).
        public func resolve(against root: URL) throws -> URL {
            guard !relativePath.hasPrefix("/") else {
                throw PathError.notRelative(relativePath)
            }
            let components = relativePath
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
            var result = root
            for component in components {
                switch component {
                case ".": continue
                case "..":
                    // `..` may only stay within the root; a bare root has no parent to pop.
                    if result.standardizedFileURL.path == root.standardizedFileURL.path {
                        throw PathError.relativeEscape(relativePath)
                    }
                    result = result.deletingLastPathComponent()
                default:
                    result.appendPathComponent(component)
                }
            }
            let standardized = result.standardizedFileURL
            let rootStandardized = root.standardizedFileURL
            guard standardized.path == rootStandardized.path
                    || standardized.path.hasPrefix(rootStandardized.path + "/") else {
                throw PathError.relativeEscape(relativePath)
            }
            return standardized
        }
    }
}
