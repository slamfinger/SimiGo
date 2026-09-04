import Foundation

public enum AppKey: String, CaseIterable, Sendable {
    case modelPath = "SelectedModelPath"
    case llamaCppRoot = "LlamaCppRoot"
    case llamaServerBin = "LlamaServerBin"
    case apiListenMode = "APIListenMode"
    case apiPort = "APIPort"
    case bonjourName = "BonjourName"

    nonisolated public var defaultValue: String? {
        switch self {
        case .llamaCppRoot:
            return "\(NSHomeDirectory())/llama.cpp"
        case .llamaServerBin:
            return "\(NSHomeDirectory())/llama.cpp/build/bin/llama-server"
        case .modelPath:
            return nil
        case .apiListenMode:
            return "localhost"
        case .apiPort:
            return "\(InferenceNodeDefaults.apiPort)"
        case .bonjourName:
            return "SimiGo"
        }
    }
}

public enum APIListenMode: String, CaseIterable, Codable, Sendable {
    case localhost
    case lan

    nonisolated public var host: String {
        switch self {
        case .localhost:
            return InferenceNodeDefaults.defaultBindHost
        case .lan:
            return InferenceNodeDefaults.lanBindHost
        }
    }

    nonisolated public var displayName: String {
        switch self {
        case .localhost:
            return "仅本机"
        case .lan:
            return "局域网"
        }
    }
}

public struct AppConfig: Sendable {
    nonisolated(unsafe) private static let defs = UserDefaults.standard
    nonisolated private static let modelPrefix = "model_cfg_"

    nonisolated public static func set(_ val: String?, for key: AppKey) {
        if let val {
            defs.set(val, forKey: key.rawValue)
        } else {
            defs.removeObject(forKey: key.rawValue)
        }
    }

    nonisolated public static func get(_ key: AppKey) -> String? {
        let value = defs.string(forKey: key.rawValue)
        return (value?.isEmpty ?? true) ? key.defaultValue : value
    }

    nonisolated public static func reset(_ key: AppKey) {
        defs.removeObject(forKey: key.rawValue)
    }

    nonisolated public static func resetAll() {
        AppKey.allCases.forEach(reset)
    }

    // MARK: - API Network Configuration

    nonisolated public static var apiListenMode: APIListenMode {
        get {
            APIListenMode(rawValue: get(.apiListenMode) ?? "localhost") ?? .localhost
        }
        set {
            set(newValue.rawValue, for: .apiListenMode)
        }
    }

    nonisolated public static var isLANEnabled: Bool {
        get {
            apiListenMode == .lan
        }
        set {
            apiListenMode = newValue ? .lan : .localhost
        }
    }

    nonisolated public static func setLANEnabled(_ enabled: Bool) {
        apiListenMode = enabled ? .lan : .localhost
    }

    nonisolated public static var apiHost: String {
        apiListenMode.host
    }

    nonisolated public static var apiPort: Int {
        get {
            let value = Int(get(.apiPort) ?? "\(InferenceNodeDefaults.apiPort)") ?? InferenceNodeDefaults.apiPort
            return max(1, min(value, 65535))
        }
        set {
            set(String(max(1, min(newValue, 65535))), for: .apiPort)
        }
    }

    nonisolated public static var apiListenAddress: String {
        "\(apiHost):\(apiPort)"
    }

    nonisolated public static var localAPIBaseURL: URL {
        URL(string: "http://\(InferenceNodeDefaults.defaultBindHost):\(apiPort)/v1")!
    }

    nonisolated public static var lanAPIBaseURL: URL {
        URL(string: "http://\(bonjourName).local:\(apiPort)/v1")!
    }

    nonisolated public static var currentAPIBaseURL: URL {
        switch apiListenMode {
        case .localhost:
            return localAPIBaseURL
        case .lan:
            return lanAPIBaseURL
        }
    }

    nonisolated public static var localAPIAddress: String {
        "http://\(InferenceNodeDefaults.defaultBindHost):\(apiPort)/v1"
    }

    nonisolated public static var lanAPIAddress: String {
        "http://\(bonjourName).local:\(apiPort)/v1"
    }

    nonisolated public static var currentAPIAddress: String {
        switch apiListenMode {
        case .localhost:
            return localAPIAddress
        case .lan:
            return lanAPIAddress
        }
    }

    // MARK: - Bonjour

    nonisolated public static var bonjourName: String {
        get {
            let value = get(.bonjourName) ?? "SimiGo"
            return value.isEmpty ? "SimiGo" : value
        }
        set {
            let value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            set(value.isEmpty ? "SimiGo" : value, for: .bonjourName)
        }
    }

    // MARK: - Model Config

    nonisolated public static func savedConfig(for path: String) -> ModelConfig? {
        let key = modelPrefix + modelName(from: path)
        guard let data = defs.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ModelConfig.self, from: data)
    }

    nonisolated public static func save(_ config: ModelConfig, for path: String) {
        let key = modelPrefix + modelName(from: path)
        if let data = try? JSONEncoder().encode(config) {
            defs.set(data, forKey: key)
        }
    }

    nonisolated public static func recommendedConfig(for path: String) -> ModelConfig? {
        ModelConfig.fromModel(path)
    }

    nonisolated public static func remove(for path: String) {
        defs.removeObject(forKey: modelPrefix + modelName(from: path))
    }

    // MARK: - LLaMA.cpp

    nonisolated public static var llamaCppRoot: URL? {
        url(for: .llamaCppRoot, exec: false)
    }

    nonisolated public static var llamaServerBin: URL? {
        url(for: .llamaServerBin, exec: true)
    }

    private nonisolated static func url(for key: AppKey, exec: Bool) -> URL? {
        guard let path = get(key) else { return nil }
        let url = URL(fileURLWithPath: path)
        let reachable = (try? url.checkResourceIsReachable()) == true
        let executable = !exec || FileManager.default.isExecutableFile(atPath: path)
        return reachable && executable ? url : nil
    }

    nonisolated public static var defaultLlamaCppPath: String {
        "\(NSHomeDirectory())/llama.cpp"
    }

    nonisolated public static var defaultLlamaServerBinPath: String {
        "\(defaultLlamaCppPath)/build/bin/llama-server"
    }

    // MARK: - Reset Network Settings

    nonisolated public static func resetAPISettings() {
        reset(.apiListenMode)
        reset(.apiPort)
        reset(.bonjourName)
    }
}
