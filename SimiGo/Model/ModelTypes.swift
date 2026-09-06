import Foundation

// MARK: - Helper Functions

nonisolated public func modelName(from path: String) -> String {
    let comps = path.split(separator: "/")
    if let i = comps.firstIndex(of: "snapshots"), i > 0 {
        return String(comps[i - 1])
            .replacingOccurrences(of: "models--", with: "")
            .replacingOccurrences(of: "--", with: "/")
    }
    return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
}

// MARK: - Error

public enum RuntError: LocalizedError, Sendable {
    case notLoaded
    case loadFailed(String)
    case generationFailed(String)
    case invalidModelDirectory(String)
    case modelNotSupported(String)
    case admissionExceeded(UInt64, UInt64)
    case duplicateRequestId(String)

    public var errorDescription: String? {
        switch self {
        case .notLoaded: return "模型未加载"
        case .loadFailed(let r): return "模型加载失败: \(r)"
        case .generationFailed(let r): return "生成失败: \(r)"
        case .invalidModelDirectory(let p): return "无效的模型目录: \(p)"
        case .modelNotSupported(let r): return "不支持的模型: \(r)"
        case .admissionExceeded(let projected, let limit):
            return "内存超额拒绝: 投影 \(projected / 1024 / 1024)M > 上限 \(limit / 1024 / 1024)M（eviction 后仍超预算）"
        case .duplicateRequestId(let id):
            return "重复的 requestId: \(id)（前一请求仍在处理中，未完成前不得复用）"
        }
    }
}

// MARK: - Model Kind & Info

nonisolated public enum ModelKind: Equatable, Sendable {
    case gguf
    case mlx

    public var displayName: String {
        switch self {
        case .gguf: return "llama.cpp"
        case .mlx: return "MLX Native"
        }
    }

    public var isPythonBackend: Bool { false }
    public var pipPackage: String? { nil }
}

nonisolated public struct ModelInfo: Equatable, Sendable {
    public let path: String
    public let kind: ModelKind
    public let mmprojPath: String?
    public let draftModelPath: String?

    public init(path: String, kind: ModelKind, mmprojPath: String? = nil, draftModelPath: String? = nil) {
        self.path = path
        self.kind = kind
        self.mmprojPath = mmprojPath
        self.draftModelPath = draftModelPath
    }

    public var name: String { modelName(from: path) }
    public var backendName: String { kind.displayName }
    public var isVisualModel: Bool { mmprojPath != nil }
}

// MARK: - Model Configuration

nonisolated public struct ModelConfig: Codable, Equatable, Sendable {
    public var temperature: Float = 1.0
    public var topP: Float = 0.9
    public var topK: Int = 20
    public var minP: Float = 0.05
    public var maxTokens: Int = 4096
    public var gpuLayers: Int = 99
    public var ctxSize: Int = 131072
    public var useChatTemplate: Bool = true
    public var trustRemoteCode: Bool = true
    public var jinja: Bool = false
    public var chatTemplate: String = ""
    public var codexMode: Bool = false
    public var flashAttention: Bool = true
    public var useMTP: Bool = false
    public var specDraftNMax: Int = 2
    public var disableThinking: Bool = true
    public var presencePenalty: Float = 0.0
    public var repeatPenalty: Float = 1.05
    public var sleepIdleSeconds: Int = 600
    public var isMoE: Bool = false
    public var moeMaxSlots: Int = 256

    nonisolated public static func fromModel(_ path: String) -> ModelConfig {
        let fm = FileManager.default
        let paths = [
            path + "/generation_config.json",
            (path as NSString).deletingLastPathComponent + "/generation_config.json"
        ]
        for p in paths where fm.fileExists(atPath: p) {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: p)),
               let cfg = try? JSONDecoder().decode(ModelConfig.self, from: data) {
                return cfg
            }
        }
        return ModelConfig()
    }

    nonisolated public func merging(_ other: ModelConfig?) -> ModelConfig {
        other ?? self
    }
}
