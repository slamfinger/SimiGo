import Foundation

/// #90 B — 活会话（引擎内 `ChatSession` 缓存数组）驻留字节的口径与上限。
///
/// 计的是**内存里的缓存数组本身**，不是磁盘快照：注意力层 K/V 随已处理
/// token 线性增长，状态空间层（GDN / Mamba 的卷积态与递归态）是每会话
/// 固定量、与上下文长度无关。两部分都由模型 `config.json` 的几何字段算出。
///
/// 与真实数组的对账（qwen3_6-35b-a3b，40 层 = 10 full + 30 linear；实测样本
/// `~/.simigo/prefix-pool/44eaa202ce92e06d/e4890e3f1b45e353-12.safetensors`，
/// T = 10 102，张量段合计 271 278 080 B，与本公式逐项相加**逐字节相等**）：
/// - 注意力：`20 × (1, 2, T, 256) bf16`（每层 K、V 各一）⇒
///   `10×2×2×256×2 = 20 480 B/token`；
/// - 卷积态：`30 × (1, 3, 8192) bf16 = 30 × 49 152 = 1 474 560 B`；
/// - 递归态：`30 × (1, 32, 128, 128) f32 = 30 × 2 097 152 = 62 914 560 B`；
///   两者相加 `64 389 120 B` 是每会话固定量。
/// dtype 规则取自 fork 实现而不是猜：`Qwen35.swift` 的卷积态
/// `convState = zeros([B, convKernel-1, convDim], dtype: inputs.dtype)` 用**激活
/// dtype**（实测 bf16），递归态走 `mamba_ssm_dtype`（实测 f32）。
/// 磁盘侧只用于交叉验证，不是本类型的取数来源。
///
/// 方向性：KV 宽度同样取激活 dtype。若启用压缩策略（affine / turboquant）真实
/// 占用更小，本估读因此**偏高**——上限提前逐出，保守方向。
nonisolated struct LiveSessionResidency: Equatable, Sendable {
    /// 每个已处理 token 的注意力缓存字节（全部注意力层的 K+V）。
    let bytesPerToken: Int
    /// 每会话固定状态缓存字节（卷积态 + 递归态），与上下文长度无关。
    let fixedBytesPerSession: Int

    func estimatedBytes(processedTokens: Int) -> Int {
        fixedBytesPerSession + max(0, processedTokens) * bytesPerToken
    }

    /// 上限 = 既有两条预算的物理形态，不引入新常数：
    /// `RuntimeTuning.sessionLimit` 份固定状态 + `warmTokenBudget` token 的
    /// 注意力缓存。显式 env 覆盖优先。
    static func byteBudget(
        residency: LiveSessionResidency,
        override: Int? = RuntimeTuning.liveSessionByteBudgetOverrideBytes
    ) -> Int {
        if let override, override > 0 { return override }
        return residency.fixedBytesPerSession * RuntimeTuning.sessionLimit
            + residency.bytesPerToken * RuntimeTuning.warmTokenBudget
    }

    /// 由模型目录的 `config.json` 解析。几何字段不足以算出某一部分时返回
    /// `nil`——上限宁缺毋滥，不拿猜出来的几何冒充计量。
    static func resolve(modelPath: String) -> LiveSessionResidency? {
        guard let config = readModelConfig(modelPath: modelPath) else { return nil }
        // 复合 VLM 的几何字段在 `text_config` 里（Qwen35 / Gemma4 一类）。
        let text = (config["text_config"] as? [String: Any]) ?? config

        guard let layers = intValue(text["num_hidden_layers"]), layers > 0 else { return nil }
        let stateLayers = stateSpaceLayerCount(text: text, layers: layers)
        let attentionLayers = layers - stateLayers
        guard attentionLayers >= 0 else { return nil }

        // 注意力部分：层数 × (K,V) × kv_heads × head_dim × 激活宽度。
        let activationBytes = dtypeBytes(text["torch_dtype"]) ?? 2
        let kvHeads = intValue(text["num_key_value_heads"])
            ?? intValue(text["num_attention_heads"])
        let hidden = intValue(text["hidden_size"])
        let headDim = intValue(text["head_dim"])
            ?? (intValue(text["num_attention_heads"]).flatMap { heads in
                hidden.map { $0 / max(1, heads) }
            })
        var bytesPerToken = 0
        if attentionLayers > 0 {
            guard let kvHeads, let headDim, kvHeads > 0, headDim > 0 else { return nil }
            bytesPerToken = attentionLayers * 2 * kvHeads * headDim * activationBytes
        }

        // 状态部分：GDN 卷积态 (convKernel-1, 2·k 通道 + v 通道) 按 fork 实现
        // 用激活 dtype；递归态 (vHeads, kHeadDim, vHeadDim) 用 mamba_ssm_dtype。
        var fixedBytes = 0
        if stateLayers > 0 {
            guard
                let keyHeads = intValue(text["linear_num_key_heads"]),
                let valueHeads = intValue(text["linear_num_value_heads"]),
                let keyDim = intValue(text["linear_key_head_dim"]),
                let valueDim = intValue(text["linear_value_head_dim"]),
                let convKernel = intValue(text["linear_conv_kernel_dim"]),
                convKernel > 1, keyHeads > 0, valueHeads > 0, keyDim > 0, valueDim > 0
            else { return nil }
            let stateBytes = dtypeBytes(text["mamba_ssm_dtype"]) ?? 4
            let convChannels = 2 * keyHeads * keyDim + valueHeads * valueDim
            let conv = (convKernel - 1) * convChannels * activationBytes
            let recurrent = valueHeads * keyDim * valueDim * stateBytes
            fixedBytes = stateLayers * (conv + recurrent)
        }

        guard bytesPerToken > 0 || fixedBytes > 0 else { return nil }
        return LiveSessionResidency(
            bytesPerToken: bytesPerToken, fixedBytesPerSession: fixedBytes)
    }

    /// 层类型分布：`layer_types` 优先，其次 `full_attention_interval`（每 N 层
    /// 一个全注意力层），都没有就按纯注意力模型处理（无固定状态）。
    private static func stateSpaceLayerCount(text: [String: Any], layers: Int) -> Int {
        if let types = text["layer_types"] as? [String] {
            let recurrent: Set<String> = ["linear_attention", "mamba", "ssm", "recurrent"]
            return types.filter { recurrent.contains($0) }.count
        }
        if let interval = intValue(text["full_attention_interval"]), interval > 0 {
            return layers - (layers + interval - 1) / interval
        }
        return 0
    }

    private static func readModelConfig(modelPath: String) -> [String: Any]? {
        let url = URL(fileURLWithPath: modelPath).appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }

    /// dtype 名 → 字节宽度。未知名字返回 nil 由调用侧决定默认值。
    private static func dtypeBytes(_ value: Any?) -> Int? {
        guard let name = value as? String else { return nil }
        switch name.lowercased() {
        case "float32", "fp32", "float": return 4
        case "bfloat16", "bf16", "float16", "fp16", "half": return 2
        case "float8_e4m3fn", "float8_e5m2": return 1
        default: return nil
        }
    }
}

/// #90 B — 字节上限的逐出选择（纯函数，测试层可证伪）。
///
/// 调用侧负责将分片按 LRU 排序并排除本轮正在使用的分片（`keeping`）；本函数
/// 只做「超上限则按 LRU 释放，直到回到上限内」这一条判定。在途分片永不
/// 选中——淘汰对象与正在执行的请求隔离。若保护分片自身已超上限，循环会在
/// 可逐出集合耗尽后停止：不为了回到上限而打掉正在跑的会话。
nonisolated enum ResidencyGovernor {
    struct Resident: Sendable {
        let key: String
        let bytes: Int
        let isInFlight: Bool
    }

    struct Plan: Sendable {
        /// 需要逐出的键，按 LRU 顺序。
        let victims: [String]
        /// 逐出后的驻留总量（含保护分片与仍在途的分片）。
        let warmBytesAfter: Int
        var fired: Bool { !victims.isEmpty }
    }

    static func evictionPlan(
        _ residents: [Resident],
        protectedBytes: Int,
        ceiling: Int
    ) -> Plan {
        var warm = protectedBytes + residents.reduce(0) { $0 + $1.bytes }
        var victims: [String] = []
        for resident in residents {
            guard warm > ceiling else { break }
            guard !resident.isInFlight else { continue }
            warm -= resident.bytes
            victims.append(resident.key)
        }
        return Plan(victims: victims, warmBytesAfter: warm)
    }
}

/// #90 A — 跨请求活会话采纳的判据与选择（纯函数，测试层可证伪）。
///
/// 现象：客户端逐轮换 `sessionId`（`HTTPServer` 在无显式身份时铸造
/// `openai-request:<uuid>`）却回传逐条追加的同一份转录。按 `storageKey`
/// 查表必然 miss，于是每轮都新建分片、每轮都全量冷 prefill。采纳只发生在
/// 引擎层：身份解析规则、ES/IS 数据行与结算权威都不动。
nonisolated enum SessionAdoption {
    struct Candidate: Sendable {
        let key: String
        let historyCount: Int
        let historyIsStrictPrefixOfIncoming: Bool
        let kvFingerprint: String?
        /// `nil` = 该分片创建时未记录 thinking 配置 ⇒ 不可采纳（未知不相容）。
        let thinkingDisabled: Bool?
        let inFlightRequestId: String?
        /// 分片登记的作用域身份。`nil` = 未登记 ⇒ 不可采纳（未知不相容）。
        let agentId: String?
        let lastActivity: Date
    }

    struct Request: Sendable {
        let incomingCount: Int
        let kvFingerprint: String?
        let thinkingDisabled: Bool
        let agentId: String
    }

    /// 单条判据的结果。`eligible` 之外每个 case 都对应一个可读进拒绝理由：
    /// 采纳失败时把拒绝理由写进 trace，验收窗口据此证明「候选集合真的检过、
    /// 且没有一份合格」，而不是只看到「没有采纳」这一条否定结果。
    enum Eligibility: Equatable, Sendable {
        case eligible
        /// 分片未登记作用域身份（未知不相容）。
        case unknownAgent
        case differentAgent
        case inFlight
        case unknownThinking
        case thinkingMismatch
        case fingerprintMismatch
        /// 既有账本不短于入站转录（含重放自己的旧转录）。
        case notShorter
        case notStrictPrefix

        /// trace 理由码；`eligible` 无理由码。
        var reason: String? {
            switch self {
            case .eligible: return nil
            case .unknownAgent: return "unknownAgent"
            case .differentAgent: return "differentAgent"
            case .inFlight: return "inFlight"
            case .unknownThinking: return "unknownThinking"
            case .thinkingMismatch: return "thinkingMismatch"
            case .fingerprintMismatch: return "fpMismatch"
            case .notShorter: return "notShorter"
            case .notStrictPrefix: return "notPrefix"
            }
        }
    }

    /// 判据顺序与拒绝理由优先级一致：作用域先判（隔离裁定优先于复用收益；
    /// 跨会话共享只属于 #92/W2′，本窗口未开启），其后依次为在途、thinking
    /// 配置、KV 指纹、长度、严格前缀。
    static func eligibility(_ candidate: Candidate, for request: Request) -> Eligibility {
        guard let candidateAgent = candidate.agentId else { return .unknownAgent }
        guard candidateAgent == request.agentId else { return .differentAgent }
        guard candidate.inFlightRequestId == nil else { return .inFlight }
        guard let candidateThinking = candidate.thinkingDisabled else { return .unknownThinking }
        guard candidateThinking == request.thinkingDisabled else { return .thinkingMismatch }
        guard candidate.kvFingerprint == request.kvFingerprint else { return .fingerprintMismatch }
        guard candidate.historyCount < request.incomingCount else { return .notShorter }
        guard candidate.historyIsStrictPrefixOfIncoming else { return .notStrictPrefix }
        return .eligible
    }

    /// 全部判据满足才可采纳；多个合格候选取最近活跃者。
    /// 返回 `nil` = 没有可继续使用的活分片，走原有冷路径。
    static func eligibleCandidates(_ candidates: [Candidate], for request: Request) -> [Candidate] {
        candidates.filter { eligibility($0, for: request) == .eligible }
    }

    static func choose(_ candidates: [Candidate], for request: Request) -> Candidate? {
        eligibleCandidates(candidates, for: request)
            .max { $0.lastActivity < $1.lastActivity }
    }
}

/// #90 C — 取消时「逐出哪一份分片」的判据（纯函数，测试层可证伪）。
///
/// 取消不得产生有效提交（铁律 10）管的是账本；分片是否连带逐出是另一条
/// 决定，原先只写在生成流程的 if 链里，无权重就无法证伪。两条逐出理由
/// 语义不同，不能合并成一个条件：
/// - 本轮新建的分片：零流事件即被打断 ⇒ 内部执行状态可疑，留在表里会让
///   后续命中它的请求挂死（2026-09-17 真机实证连续 10 次无自愈）。判据沿用
///   既有的「零事件 + 非复用」。
/// - 本轮采纳来的分片：借用方无法为别人的表示背书，无论取消落在起点还是
///   中途一律逐出 ⇒ **不看**零事件条件。下一轮宁可重新冷 prefill。
/// 同一会话自己的复用轮（`reuse` 真且非采纳）行为不变，不因 #90 扩大逐出面。
///
/// 2026-10-29 owner 裁定（#134）：零输出**本身**不再单独定罪。上游
/// `ChatSession.record()` 在取消轮会把可证明的预填前缀留在分片里（trim 到
/// `retainedTokenCount` 并把账本重基为同长度的 token 数组），本层的 `clear()`
/// 会连带丢掉这份已证明的表示。因此「新建 + 零事件」这一支先问一条正向证据：
/// 账本非空**且**与物理 cache 的 `processedTokenCount` 逐字相等 ⇒ 保留内存
/// 会话。两个数不一致或账本为空 ⇒ 沿用既有驱逐。判据只认上游已经证明过的
/// 形状，不引入新的推断，也不放宽使用资格（复用仍要过 ES/IS 结算与绑定授权）。
nonisolated enum CancelEviction {
    /// 观测契约：两条驱逐行的标记。调用方直接引用这两个常量，测试断言的
    /// 也是它们 ⇒ 字符串不可能与产品路径分叉（`poisonedSessionEvict` 沿用
    /// 既有名字，不改观测）。
    static let freshShardMarker = "poisonedSessionEvict"
    static let adoptedShardMarker = "adoptedCancelEvict"

    enum Decision: Equatable, Sendable {
        /// 保持驻留。
        case keepResident
        /// 保留：上游已证明这一段取消前缀可用（记账并留驻，不清 cache）。
        case retainProvenPrefix
        /// 逐出本轮新建的分片及其别名条目。
        case evictFreshShard
        /// 逐出本轮采纳来的分片及其别名条目。
        case evictAdoptedShard
    }

    static func decide(
        rawEventCount: Int,
        reusedSameSession: Bool,
        adoptedForeignShard: Bool,
        retainedLedgerTokens: Int,
        cacheProcessedTokens: Int
    ) -> Decision {
        if adoptedForeignShard { return .evictAdoptedShard }
        if rawEventCount == 0, !reusedSameSession {
            let proven = retainedLedgerTokens > 0
                && retainedLedgerTokens == cacheProcessedTokens
            return proven ? .retainProvenPrefix : .evictFreshShard
        }
        return .keepResident
    }
}
