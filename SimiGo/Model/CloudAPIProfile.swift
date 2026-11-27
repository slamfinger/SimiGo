import Foundation
import Security

/// Non-secret Cloud API configuration. The actual provider credential is stored
/// separately in macOS Keychain and addressed by `credentialID`.
struct CloudAPIProfile: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var baseURL: String
    var model: String

    var credentialID: String { id }

    init(
        id: String = UUID().uuidString.lowercased(),
        name: String = "Cloud API",
        baseURL: String = "https://api.openai.com/v1",
        model: String = ""
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
    }

    /// Validates the operator-supplied base URL and returns the Chat Completions
    /// endpoint. The base URL is expected to include the provider's API prefix
    /// (commonly `/v1`); SimiGo appends only `/chat/completions`.
    func chatCompletionsURL() throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else {
            throw CloudAPIProfileError.invalidBaseURL
        }

        let isLoopback = host == "localhost" || host == "127.0.0.1"
            || host == "::1" || host == "[::1]"
        guard scheme == "https" || (scheme == "http" && isLoopback) else {
            throw CloudAPIProfileError.insecureBaseURL
        }

        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        components.path = path + "/chat/completions"
        guard let endpoint = components.url else {
            throw CloudAPIProfileError.invalidBaseURL
        }
        return endpoint
    }

    func validate() throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw CloudAPIProfileError.missingRequiredField
        }
        _ = try chatCompletionsURL()
    }
}

enum CloudAPIProfileError: LocalizedError, Equatable {
    case invalidBaseURL
    case insecureBaseURL
    case missingRequiredField

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "API Base URL 无效；请输入完整的 HTTPS API 前缀（例如 https://api.example.com/v1）"
        case .insecureBaseURL:
            return "云端 API 必须使用 HTTPS；仅 localhost / 127.0.0.1 / ::1 允许 HTTP"
        case .missingRequiredField:
            return "请填写配置名称和模型名称"
        }
    }
}

/// Provider API keys are independent of LOCALB signing and transport identities.
/// Secrets never enter UserDefaults, profile JSON, request logs, or trace data.
final class CloudAPIKeychainStore: @unchecked Sendable {
    static let shared = CloudAPIKeychainStore()

    private let service = "com.simigo.cloud-api"

    enum StoreError: LocalizedError {
        case keychainStatus(OSStatus)
        case invalidCredentialData

        var errorDescription: String? {
            switch self {
            case .keychainStatus(let status):
                return "macOS Keychain 操作失败（OSStatus \(status)）"
            case .invalidCredentialData:
                return "Keychain 中的 API Key 不是有效 UTF-8 文本"
            }
        }
    }

    func save(_ apiKey: String, credentialID: String) throws {
        let value = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !credentialID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = value.data(using: .utf8)
        else {
            throw CloudAPIProfileError.missingRequiredField
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credentialID,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw StoreError.keychainStatus(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw StoreError.keychainStatus(updateStatus)
        }
    }

    func read(credentialID: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credentialID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw StoreError.keychainStatus(status)
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else {
            throw StoreError.invalidCredentialData
        }
        return value
    }

    func delete(credentialID: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credentialID,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.keychainStatus(status)
        }
    }
}
