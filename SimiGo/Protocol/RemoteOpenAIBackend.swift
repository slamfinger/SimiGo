import Foundation

public struct RemoteOpenAIBackend: @unchecked Sendable {
    static func makeURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 600
        return URLSession(configuration: configuration)
    }

    public let configuration: CloudBackendConfiguration
    public let apiKey: String

    private static let skippedRequestHeaders: Set<String> = [
        "authorization",
        "connection",
        "content-length",
        "host",
        "keep-alive",
        "proxy-authorization",
        "te",
        "trailers",
        "transfer-encoding",
        "upgrade",
    ]

    private static let skippedResponseHeaders: Set<String> = [
        "connection",
        "content-encoding",
        "content-length",
        "keep-alive",
        "transfer-encoding",
    ]

    public init(configuration: CloudBackendConfiguration, apiKey: String) {
        self.configuration = configuration
        self.apiKey = apiKey
    }

    public func makeRequest(
        path: String,
        method: String,
        headers: [String: String],
        body: Data
    ) throws -> URLRequest {
        guard let url = configuration.upstreamURL(path: path) else {
            throw ServiceError.backendNotAvailable("云端 Base URL 无效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 600
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")

        for (key, value) in headers where !Self.skippedRequestHeaders.contains(key.lowercased()) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let authorization = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !authorization.isEmpty else {
            throw ServiceError.backendNotAvailable("云端 API 需要配置 API Key")
        }
        request.setValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization")

        if body.isEmpty {
            request.httpBody = nil
            return request
        }

        request.httpBody = try configuration.model.isEmpty
            ? body
            : Self.overrideModel(in: body, with: configuration.model)
        return request
    }

    public func healthRequest() throws -> URLRequest {
        guard let url = configuration.upstreamURL(path: "/models") else {
            throw ServiceError.backendNotAvailable("云端 Base URL 无效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    public func isStreamingRequest(
        requestHeaders: [String: String],
        body: Data
    ) -> Bool {
        requestHeaders["accept"]?.lowercased().contains("text/event-stream") == true ||
        ((try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["stream"] as? Bool) == true
    }

    private static func overrideModel(in body: Data, with model: String) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return body
        }

        object["model"] = model
        if model.lowercased().contains("glm") {
            // GLM 5.3 rejects disabled thinking and also rejects `thinking:low`
            // when legacy reasoning flags remain. Force the only accepted
            // minimal-reasoning form.
            object["thinking"] = ["type": "low"]
            object.removeValue(forKey: "enable_thinking")
            object.removeValue(forKey: "reasoning_effort")
            object.removeValue(forKey: "reasoning")
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    func sanitizedResponseHeaders(_ response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            guard let key = key as? String, let value = value as? String else { continue }
            let normalizedKey = key.lowercased()
            guard !Self.skippedResponseHeaders.contains(normalizedKey) else { continue }
            headers[key] = value
        }

        if headers["Access-Control-Allow-Origin"] == nil {
            headers["Access-Control-Allow-Origin"] = "*"
        }
        headers["Connection"] = "close"
        headers["X-Request-Id"] = UUID().uuidString.lowercased()
        return headers
    }
}
