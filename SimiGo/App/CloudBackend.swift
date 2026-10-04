import Foundation
import Security

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

public struct CloudBackendConfiguration: Sendable {
    nonisolated public static let defaultBaseURL = "https://open.bigmodel.cn/api/coding/paas/v4"
    nonisolated public static let defaultModel = "glm-5.3-flash"

    public var baseURLString: String
    public var model: String

    public init(
        baseURLString: String = CloudBackendConfiguration.defaultBaseURL,
        model: String = CloudBackendConfiguration.defaultModel
    ) {
        self.baseURLString = baseURLString
        self.model = model
    }

    public var baseURL: URL? {
        URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public func validated(apiKey: String) throws {
        guard let baseURL, let host = baseURL.host?.lowercased(), !host.isEmpty else {
            throw ServiceError.backendNotAvailable("云端 Base URL 无效")
        }

        let isLoopback = ["127.0.0.1", "localhost", "::1"].contains(host)
        guard isLoopback || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServiceError.backendNotAvailable("云端 API 需要配置 API Key")
        }
    }

    /// Accept either a host root (`https://api.example.com`) or a versioned
    /// base (`https://api.example.com/v1`) without producing `/v1/v1/...`.
    public func upstreamURL(path: String) -> URL? {
        guard var baseURL else { return nil }
        var suffix = path.hasPrefix("/") ? path : "/" + path

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
        return baseURL
    }

    nonisolated private static func isVersionSegment(_ segment: Substring) -> Bool {
        guard segment.first == "v", segment.count > 1 else { return false }
        return segment.dropFirst().allSatisfy(\.isNumber)
    }
}

enum CloudKeychain: Sendable {
    private static let service = "SimiGo"
    private static let account = "cloud.api-key"

    static func readAPIKey() -> String {
        var query: [String: Any] = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func writeAPIKey(_ value: String) {
        let query = baseQuery
        SecItemDelete(query as CFDictionary)

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var attributes = query
        attributes[kSecValueData as String] = Data(trimmed.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
