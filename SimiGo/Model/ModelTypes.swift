import Foundation

// MARK: - Helper Functions

nonisolated public func modelName(from path: String) -> String {
    let comps = path.split(separator: "/")
    if let i = comps.firstIndex(of: "snapshots"), i > 0 {
        let repositoryName = comps[i - 1].description
        return repositoryName
            .replacingOccurrences(of: "models--", with: "")
            .replacingOccurrences(of: "--", with: "/")
    }
    let url = URL(fileURLWithPath: path)
    return url.deletingPathExtension().lastPathComponent
}

// MARK: - Error

public enum RuntError: LocalizedError, Sendable {
    case notLoaded
    case loadFailed(String)
    case generationFailed(String)
    case invalidModelDirectory(String)
    case modelNotSupported(String)

    public var errorDescription: String? {
        switch self {
        case .notLoaded: return "模型未加载"
        case .loadFailed(let r): return "模型加载失败: \(r)"
        case .generationFailed(let r): return "生成失败: \(r)"
        case .invalidModelDirectory(let p): return "无效的模型目录: \(p)"
        case .modelNotSupported(let r): return "不支持的模型: \(r)"
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
    public var kvCache: KVCacheSettings?

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

/// 官方 `KVCacheConfiguration` 的最小映射（nil = 官方默认 fullPrecision、不限容量）。
///
/// 策略名与官方预设一一对应：`affine4` / `affine8`（Affine 量化）、
/// `turboQuality` / `turboBalanced` / `turboMemory`（TurboQuant 官方预设）、
/// `fullPrecision`。注意：切换 KV 策略或容量会使官方 token 账本失效，
/// 下一轮请求将全量 prefill（README_base §5.1.1）。
nonisolated public struct KVCacheSettings: Codable, Equatable, Sendable {
    public var strategy: String?
    public var maxTokens: Int?
    public var preservedPrefixTokens: Int?

    public init(
        strategy: String? = nil,
        maxTokens: Int? = nil,
        preservedPrefixTokens: Int? = nil
    ) {
        self.strategy = strategy
        self.maxTokens = maxTokens
        self.preservedPrefixTokens = preservedPrefixTokens
    }
}

// MARK: - Model Capability Contract（P1-1）

/// 能力三态。unsupported = 明确知道不支持；unverified = 尚未验证。
/// 不允许从"无证据"推断 unsupported（SimiGo 不猜测）。
nonisolated public enum CapabilityStatus: String, Codable, Equatable, Sendable {
    case supported
    case unsupported
    case unverified
}

/// 能力集合：模型/协议层能力，三态。
nonisolated public struct ModelCapabilitySet: Codable, Equatable, Sendable {
    public var chat: CapabilityStatus = .unverified
    public var streaming: CapabilityStatus = .unverified
    public var toolCalling: CapabilityStatus = .unverified
    public var vision: CapabilityStatus = .unverified
    public var reasoning: CapabilityStatus = .unverified
    public var structuredOutput: CapabilityStatus = .unverified

    public init() {}
}

/// 运行约束/特征——描述当前 Runtime 形态，不与能力混装。
nonisolated public struct RuntimeCharacteristics: Codable, Equatable, Sendable {
    public var concurrency: String
    /// KV 配置变更时的失效策略声明（P0-5）。
    public var cacheInvalidation: String
    /// 显式约束清单（如串行化开关的缘由）。
    public var constraints: [String]
    public var maxKVSize: Int?

    public init(concurrency: String, cacheInvalidation: String, constraints: [String], maxKVSize: Int?) {
        self.concurrency = concurrency
        self.cacheInvalidation = cacheInvalidation
        self.constraints = constraints
        self.maxKVSize = maxKVSize
    }
}

/// 协议端点能力。
nonisolated public struct ProtocolCapabilities: Codable, Equatable, Sendable {
    public var chatCompletions: CapabilityStatus = .unverified
    public var textCompletions: CapabilityStatus = .unverified
    public var responses: CapabilityStatus = .unverified

    public init() {}
}

/// P1-1 能力契约：来源分离的显式声明。
/// 四层来源（declared / backend / runtime / config）在此解析层汇成最终三态；
/// 未知能力保持 unverified，不反向驱动 Runtime 行为（不自动 serialize/切换 cache）。
nonisolated public struct ModelCapabilityContract: Codable, Equatable, Sendable {
    public var backend: String
    public var architecture: String?
    public var contextLength: Int?
    public var capabilities: ModelCapabilitySet
    public var runtime: RuntimeCharacteristics
    public var protocolEndpoints: ProtocolCapabilities

    public init(
        backend: String,
        architecture: String?,
        contextLength: Int?,
        capabilities: ModelCapabilitySet,
        runtime: RuntimeCharacteristics,
        protocolEndpoints: ProtocolCapabilities
    ) {
        self.backend = backend
        self.architecture = architecture
        self.contextLength = contextLength
        self.capabilities = capabilities
        self.runtime = runtime
        self.protocolEndpoints = protocolEndpoints
    }
}

nonisolated public extension ModelCapabilityContract {
    /// V1 解析器：已实测架构族（兼容矩阵 2026-09-11/12 实证）走 runtime 数据，
    /// 未实测架构族全部保持 unverified——不从无证据推断。
    /// 已实测族：qwen3_5_moe（单请求/串行 ✓，并发 ⚠ 已由 serializeGeneration 缓解）、
    /// qwen3_moe（全 ✓ 含并发）。
    static func resolve(
        backend: String,
        modelType: String?,
        contextLength: Int?,
        serializeGeneration: Bool,
        maxKVSize: Int?
    ) -> ModelCapabilityContract {
        let verifiedFamilies: Set<String> = ["qwen3_5_moe", "qwen3_moe"]
        let verified = modelType.map { verifiedFamilies.contains($0) } ?? false

        var caps = ModelCapabilitySet()
        // 通用路径：任何经 ChatSession 加载的 LLM 均走 chat/streaming。
        caps.chat = .supported
        caps.streaming = .supported
        // 以下按兼容矩阵实测填充；未实测族保持 unverified。
        caps.toolCalling = verified ? .supported : .unverified
        caps.vision = .unsupported      // Runtime 未接入视觉输入处理（明确不支持）
        caps.reasoning = .unverified    // thinking 过滤已实现；reasoning 事件透出未实现
        caps.structuredOutput = .unverified

        let concurrency = serializeGeneration
            ? "global single-flight (serializeGeneration=true)"
            : "per-session"

        var protocolCaps = ProtocolCapabilities()
        protocolCaps.chatCompletions = .supported
        protocolCaps.textCompletions = .supported
        protocolCaps.responses = verified ? .supported : .unverified

        return ModelCapabilityContract(
            backend: backend,
            architecture: modelType,
            contextLength: contextLength,
            capabilities: caps,
            runtime: RuntimeCharacteristics(
                concurrency: concurrency,
                cacheInvalidation: "kvFingerprint mismatch → 旧缓存失效，全量 prefill",
                constraints: serializeGeneration
                    ? ["serializeGeneration=true：并发生成跨 session 单飞（qwen3_5_moe 编译锁互堵缓解，2026-09-11 实测）"]
                    : [],
                maxKVSize: maxKVSize
            ),
            protocolEndpoints: protocolCaps
        )
    }
}
