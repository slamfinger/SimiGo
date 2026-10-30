import Foundation
import SimiGoRuntimeContract

public enum BackendSelection: String, CaseIterable, Sendable {
    case mlx
    case llamaCpp
    case cloud

    public var displayName: String {
        switch self {
        case .mlx: return "MLX"
        case .llamaCpp: return "LLaMA.cpp"
        case .cloud: return "云端 API"
        }
    }

    public var modelPathKey: AppKey {
        switch self {
        case .mlx: return .mlxModelPath
        case .llamaCpp: return .llamaModelPath
        case .cloud: return .modelPath
        }
    }
}

/// Upstream access style SimiGo adopts as its model provider.
///
/// All three speak the OpenAI-compatible `POST /v1/chat/completions` body, so the
/// chat/completions path itself needs no per-provider code. What differs is the
/// model-listing probe and whether a credential exists at all: Ollama and
/// LM Studio bind loopback and accept requests without any API key, so a
/// provider-blind key requirement made them unreachable even though
/// `validated(apiKey:)` already accepted a keyless loopback base URL.
public enum UpstreamProvider: String, CaseIterable, Sendable {
    case openai
    case ollama
    case lmstudio

    public var displayName: String {
        switch self {
        case .openai: return "OpenAI-compatible"
        case .ollama: return "Ollama"
        case .lmstudio: return "LM Studio"
        }
    }

    /// Native model-enumeration path. Ollama serves `/api/tags` at its origin
    /// root; the OpenAI-compatible servers answer under `/v1/models`.
    public var modelsPath: String {
        switch self {
        case .openai, .lmstudio: return "/v1/models"
        case .ollama: return "/api/tags"
        }
    }

    public var defaultPort: Int {
        switch self {
        case .openai: return 443
        case .ollama: return 11434
        case .lmstudio: return 1234
        }
    }
}

public struct CloudBackendConfiguration: Sendable {
    nonisolated public static let defaultBaseURL = "https://open.bigmodel.cn/api/coding/paas/v4"
    nonisolated public static let defaultModel = "glm-5.3-flash"

    public var baseURLString: String
    public var model: String
    public var provider: UpstreamProvider

    public init(
        baseURLString: String = CloudBackendConfiguration.defaultBaseURL,
        model: String = CloudBackendConfiguration.defaultModel,
        provider: UpstreamProvider = .openai
    ) {
        self.baseURLString = baseURLString
        self.model = model
        self.provider = provider
    }

    public var baseURL: URL? {
        URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public var isLoopbackUpstream: Bool {
        guard let host = baseURL?.host?.lowercased() else { return false }
        return ["127.0.0.1", "localhost", "::1", "::ffff:127.0.0.1"].contains(host)
            || host.hasPrefix("127.")
    }

    public var requiresAPIKey: Bool { !isLoopbackUpstream }

    public func validated(apiKey: String) throws {
        guard let baseURL, let host = baseURL.host?.lowercased(), !host.isEmpty else {
            throw ServiceError.backendNotAvailable("云端 Base URL 无效")
        }

        guard isLoopbackUpstream || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.backendNotAvailable("云端 API 需要配置 API Key")
        }
    }

    /// Accept either a host root (`https://api.example.com`) or a versioned
    /// base (`https://api.example.com/v1`) without producing `/v1/v1/...`.
    /// The path may carry a query string (origin-form request target):
    /// `append(path:)` percent-encodes `?`, so the query is split off first
    /// and re-attached verbatim after path construction.
    public func upstreamURL(path: String) -> URL? {
        guard var baseURL else { return nil }
        var suffix = path.hasPrefix("/") ? path : "/" + path

        // Split the query before any path handling; the LOCALB request
        // target has already been parser-validated (canonical escapes, no
        // control bytes), so the query re-attaches verbatim.
        var query: Substring?
        if let queryStart = suffix.firstIndex(of: "?") {
            query = suffix[suffix.index(after: queryStart)...]
            suffix = String(suffix[..<queryStart])
        }

        var basePath = baseURL.path
        while basePath != "/" && basePath.hasSuffix("/") {
            basePath.removeLast()
        }

        if basePath.split(separator: "/").last.map(Self.isVersionSegment) == true,
           let clientVersion = suffix.split(separator: "/").first,
           Self.isVersionSegment(clientVersion) {
            suffix = "/" + suffix.dropFirst(clientVersion.count + 2)
        }

        baseURL.append(path: suffix)
        if let query, !query.isEmpty,
           let withQuery = URL(
               string: baseURL.absoluteString + "?" + query
           ) {
            return withQuery
        }
        return baseURL
    }

    /// Provider-aware model enumeration. OpenAI-compatible bases are versioned,
    /// so `/models` resolves through `upstreamURL`; Ollama serves its native
    /// `/api/tags` at the origin root, which no path-joining rule can produce
    /// from a `…/v1` base.
    public func modelsProbeURL() -> URL? {
        if provider == .openai { return upstreamURL(path: "/models") }
        guard let baseURL, let scheme = baseURL.scheme, let host = baseURL.host else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = baseURL.port ?? provider.defaultPort
        components.path = provider.modelsPath
        return components.url
    }

    nonisolated private static func isVersionSegment(_ segment: Substring) -> Bool {
        guard segment.first == "v", segment.count > 1 else { return false }
        return segment.dropFirst().allSatisfy(\.isNumber)
    }
}

enum CloudKeychain: Sendable {
    /// The cloud API key lives in a 0600 file under the managed root
    /// (`<root>/cloud/api-key`), redirected by `SIMIGO_HOME` like every other
    /// managed path. It is NEVER read from or written to the login Keychain:
    /// a login-Keychain item is bound to the code signature of whichever
    /// ad-hoc build created it, so every re-signed build was met with a
    /// SecurityAgent prompt that no password satisfies (observed 2026-10-26;
    /// the same signature-ACL failure that locked the LOCALB identities).
    /// Existing login-Keychain items are left untouched and simply unused.
    private static var fileURL: URL {
        SimiGoPaths.managedRoot()
            .appendingPathComponent("cloud", isDirectory: true)
            .appendingPathComponent("api-key", isDirectory: false)
    }

    static func readAPIKey() -> String {
        guard let data = FileManager.default.contents(atPath: fileURL.path) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func writeAPIKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = fileURL
        let fm = FileManager.default
        do {
            try fm.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if trimmed.isEmpty {
                try? fm.removeItem(at: url)
                return
            }
            try Data(trimmed.utf8).write(to: url, options: [.atomic])
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // A failed credential write must never crash startup; the key is
            // simply absent until the next successful write.
            return
        }
    }
}
