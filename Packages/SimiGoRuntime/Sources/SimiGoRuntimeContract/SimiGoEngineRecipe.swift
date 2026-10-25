import Foundation

/// Extensible external-engine build / adopt registry.
///
/// Deliberately NOT hardcoded to llama.cpp: every engine declares a *recipe* as
/// data (a locked manifest entry), so adding another macOS engine — ollama, LM
/// Studio, slang, or future servers — is a new manifest entry, not a code change.
///
/// Three DISTINCT lifecycle states are modelled explicitly, because the plan
/// requires them to never be collapsed:
///   • `.downloaded`  — source/archive fetched AND checksum-verified
///   • `.built`       — compiled and a binary produced
///   • `.adapted`     — SimiGo wired a driver and health-checked the binary
/// A successful download is NOT a successful build, and neither means SimiGo can
/// actually use the engine yet.
public enum EngineStage: Int, Comparable, Sendable {
    case absent = 0
    case downloaded = 1
    case built = 2
    case adapted = 3

    public static func < (lhs: EngineStage, rhs: EngineStage) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum EngineKind: String, Codable, Sendable {
    /// Fetched and compiled by SimiGo from a locked recipe (e.g. llama.cpp).
    case sourceBuild
    /// A user-installed local server SimiGo can adopt at runtime (ollama / LM Studio / slang).
    case externalServer
    /// The bundled Native MLX runtime — no external binary at all.
    case nativeRuntime
}

/// A single engine recipe. Decodes from the locked on-disk manifest so pinned
/// refs / checksums live with operator-verified data, never baked into source.
public struct EngineRecipe: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let kind: EngineKind
    /// Origin to clone / fetch from. Required only for `.sourceBuild`.
    public let upstreamURL: String?
    /// Pinned tag or commit that MUST be checked out. A floating branch is not
    /// allowed: `isVersionLocked` rejects anything that is not an immutable ref.
    public let pinnedRef: String?
    /// SHA256 of the pinned archive. `nil` (or empty) disables unattended
    /// download fail-closed — the operator must pin a verified value first.
    public let expectedSourceSHA256: String?
    /// Binary path relative to the build tree (e.g. `build/bin/llama-server`).
    public let producedBinaryRelPath: String?
    /// Default command template used to launch an adopted external server.
    public let serveCommand: [String]?
    /// OpenAI-compatible base URL SimiGo routes to when ADOPTING an external
    /// server (ollama / LM Studio / slang). `nil` means SimiGo has no concrete
    /// endpoint to connect to for this recipe, so adoption is fail-closed and the
    /// operator must supply one via the manifest. Optional so pre-existing
    /// manifests (without this key) still decode.
    public let endpointBaseURL: String?
    /// Default model id the adopted server is expected to serve, if any.
    public let defaultModel: String?

    public init(id: String, displayName: String, kind: EngineKind,
                upstreamURL: String? = nil, pinnedRef: String? = nil,
                expectedSourceSHA256: String? = nil, producedBinaryRelPath: String? = nil,
                serveCommand: [String]? = nil, endpointBaseURL: String? = nil,
                defaultModel: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.upstreamURL = upstreamURL
        self.pinnedRef = pinnedRef
        self.expectedSourceSHA256 = expectedSourceSHA256
        self.producedBinaryRelPath = producedBinaryRelPath
        self.serveCommand = serveCommand
        self.endpointBaseURL = endpointBaseURL
        self.defaultModel = defaultModel
    }

    /// An immutable ref is a full commit SHA (40 hex) or a release tag (starts
    /// with `b`+digits, llama.cpp style, or an explicit `v`-tag). Branch names
    /// such as `master`/`main`/`develop` are NOT locked and are rejected.
    public var isVersionLocked: Bool {
        guard let ref = pinnedRef?.trimmingCharacters(in: .whitespaces), !ref.isEmpty else { return false }
        let floating: Set<String> = ["main", "master", "develop", "HEAD", "stable"]
        if floating.contains(ref.lowercased()) { return false }
        if ref.count == 40, ref.allSatisfy({ $0.isHexDigit }) { return true }   // commit SHA
        if ref.hasPrefix("v") || ref.hasPrefix("b") {
            let tail = ref.dropFirst()
            return !tail.isEmpty && tail.allSatisfy { $0.isNumber || $0 == "." || $0 == "-" }
        }
        return ref.contains(".") // dot-separated version tags (e.g. 1.2.3)
    }

    /// Auto-download is fail-closed unless a real checksum is pinned. We never
    /// invent a hash: absent value => refuse unattended fetch.
    public var allowsAutomatedDownload: Bool {
        guard let sum = expectedSourceSHA256?.trimmingCharacters(in: .whitespaces), !sum.isEmpty else { return false }
        return sum.count == 64 && sum.allSatisfy { $0.isHexDigit }
    }

    /// Git commands to obtain the pinned ref WITHOUT a floating `git pull`.
    /// Clone (depth-1) then fetch+checkout the exact immutable ref.
    public func lockedCheckoutCommands(git: String, targetDir: String) -> [([String])] {
        guard let url = upstreamURL, let ref = pinnedRef, isVersionLocked else { return [] }
        return [
            [git, "clone", "--depth", "1", url, targetDir],
            [git, "-C", targetDir, "fetch", "--depth", "1", "origin", ref],
            [git, "-C", targetDir, "checkout", "--detach", ref],
        ]
    }

    /// Relative paths to REMOVE after a successful build, keeping only the
    /// installed binary. This realises "构建完成后删除缓存只保留二进制".
    public var cachePathsToRemoveAfterBuild: [String] { ["sources", "build", "staging"] }

    /// Retained-binary location under the engine root after pruning.
    public var retainedBinaryRelPath: String {
        let name = producedBinaryRelPath.map { ($0 as NSString).lastPathComponent } ?? id
        return "bin/\(id)/\(name)"
    }

    /// Enforce "构建完成后删除缓存只保留二进制": relocate the freshly built binary
    /// to a stable `bin/<id>/` path, THEN delete the source/build/staging caches.
    ///
    /// Pure with respect to app state and driven only by an injected FileManager,
    /// so it is unit-testable against a temp directory without running a real
    /// toolchain. Fail-safe by construction: if the produced binary is not yet on
    /// disk (build incomplete), NOTHING is removed and `nil` is returned, so a
    /// partial build can never be pruned into an unrecoverable state.
    @discardableResult
    public func pruneCacheKeepingBinary(engineRoot: URL, fm: FileManager = .default) throws -> URL? {
        guard kind == .sourceBuild, let rel = producedBinaryRelPath, !rel.isEmpty else { return nil }
        let built = engineRoot.appendingPathComponent(rel, isDirectory: false)
        guard fm.fileExists(atPath: built.path) else { return nil }   // incomplete -> keep everything

        let retained = engineRoot.appendingPathComponent(retainedBinaryRelPath, isDirectory: false)
        try fm.createDirectory(at: retained.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        // Move (copy+remove for cross-device safety) the single binary we keep.
        if fm.fileExists(atPath: retained.path) { try? fm.removeItem(at: retained) }
        do { try fm.moveItem(at: built, to: retained) }
        catch {
            try fm.copyItem(at: built, to: retained)
            try fm.removeItem(at: built)
        }

        // Only now drop the caches, never the retained binary.
        for sub in cachePathsToRemoveAfterBuild {
            let url = engineRoot.appendingPathComponent(sub, isDirectory: true)
            if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        }
        return retained
    }
}

/// Loads and resolves recipes. The first bundled, verified recipe is llama.cpp;
/// external servers are adoptable entries with no source build.
public enum SimiGoEngineRegistry {
    public static let manifestName = "engine-recipes.json"

    /// Bundled defaults. llama.cpp pins a locked ref but ships WITHOUT a
    /// fabricated checksum, so unattended download stays fail-closed until an
    /// operator supplies `expectedSourceSHA256` via the manifest.
    public static var bundledDefaults: [EngineRecipe] {
        [
            EngineRecipe(id: "mlx-native", displayName: "Native MLX（内置）", kind: .nativeRuntime),
            EngineRecipe(id: "llama.cpp", displayName: "llama.cpp",
                         kind: .sourceBuild,
                         upstreamURL: "https://github.com/ggml-org/llama.cpp.git",
                         pinnedRef: nil,             // must be pinned by manifest to a real tag/commit
                         producedBinaryRelPath: "build/bin/llama-server"),
            EngineRecipe(id: "ollama", displayName: "Ollama", kind: .externalServer,
                         serveCommand: ["ollama", "serve"],
                         endpointBaseURL: "http://127.0.0.1:11434/v1",
                         defaultModel: "qwen2.5-coder:7b"),
            EngineRecipe(id: "lm-studio", displayName: "LM Studio", kind: .externalServer,
                         endpointBaseURL: "http://127.0.0.1:1234/v1"),
            // SGLang has no fixed local port/endpoint by default: adoption is
            // fail-closed until an operator manifest supplies endpointBaseURL.
            EngineRecipe(id: "slang", displayName: "SGLang", kind: .externalServer),
        ]
    }

    /// Merge bundled defaults with an operator manifest (manifest entries win by id).
    public static func load(manifestURL: URL) -> [EngineRecipe] {
        var byID = Dictionary(uniqueKeysWithValues: bundledDefaults.map { ($0.id, $0) })
        if let data = try? Data(contentsOf: manifestURL),
           let decoded = try? JSONDecoder().decode([EngineRecipe].self, from: data) {
            for r in decoded { byID[r.id] = r }
        }
        return byID.values.sorted { $0.id < $1.id }
    }

    public static func recipe(id: String, manifestURL: URL? = nil) -> EngineRecipe? {
        let all = manifestURL.map(load(manifestURL:)) ?? bundledDefaults
        return all.first { $0.id == id }
    }

    /// The concrete OpenAI-compatible connection SimiGo uses when ADOPTING an
    /// external server. Non-`nil` ONLY for `.externalServer` recipes that declare
    /// an endpoint. Source-build engines (llama.cpp) and the bundled native MLX
    /// runtime are never "adopted over an endpoint", so they resolve to `nil` —
    /// this deliberately prevents a selection from silently mis-routing inference.
    /// Adoption is fail-closed: a `.externalServer` with no endpoint (e.g. SGLang
    /// until an operator manifest supplies one) resolves to `nil`.
    public struct AdoptedEndpoint: Equatable, Sendable {
        public let baseURL: String
        public let defaultModel: String?
    }

    public static func adoptedEndpoint(for recipe: EngineRecipe) -> AdoptedEndpoint? {
        guard recipe.kind == .externalServer,
              let url = recipe.endpointBaseURL?.trimmingCharacters(in: .whitespaces),
              !url.isEmpty else {
            return nil
        }
        return AdoptedEndpoint(baseURL: url, defaultModel: recipe.defaultModel)
    }

    /// Resolve the current lifecycle stage from on-disk evidence. Kept pure so it
    /// is unit-testable without running real downloads/builds.
    public static func resolveStage(recipe: EngineRecipe,
                                    sourcePresentAtPinnedRef: Bool,
                                    binaryPresent: Bool,
                                    driverAdapted: Bool,
                                    healthChecked: Bool) -> EngineStage {
        switch recipe.kind {
        case .nativeRuntime:
            return driverAdapted ? .adapted : .built
        case .externalServer:
            if binaryPresent && driverAdapted && healthChecked { return .adapted }
            if binaryPresent { return .built }   // server installed & reachable
            return .absent
        case .sourceBuild:
            if binaryPresent && driverAdapted && healthChecked { return .adapted }
            if binaryPresent { return .built }
            if sourcePresentAtPinnedRef { return .downloaded }
            return .absent
        }
    }
}
