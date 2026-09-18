
import Foundation

/// V1.6 S2 起点语义（先定义能力不定义实现，规格 §3/§4）：
/// ExecutionDecision 是决策词汇表，S3 起 DecisionPolicy 产出此类型
/// （接线前不强制使用）；ExecutionFacts 是 DecisionPolicy 的纯数据输入
/// 快照。二者当前仅作为 API 面声明，不承载行为。
enum ExecutionDecision {
    case extend
    case restore
    case rebuild
    case fork
}

/// 执行事实快照（纯数据）——S3 起 DecisionPolicy 的输入。
struct ExecutionFacts {
    var reuse: Bool
    var rollforwardRisk: Bool
    var deltaTokensEst: Int
    var kvFingerprintMatch: Bool
    var checkpointCompatible: Bool
}

import Foundation

/// V1.6 S2（外审四轮指定分层边界）：事实→决策→执行三层中的「事实 + 决策」层。
/// 本文件只承载既有判定纯函数（自 NativeMLX 逐字节搬家，2026-09-19），
/// 语义不变；flag 合并（conditionalRestore/rollforward → ExecutionPolicy
/// 配置面）留待 S3。
///
/// 证据链：docs/architecture/EXECUTION_RUNTIME_DESIGN_V16.md §3/§4。
enum ExecutionPolicy {

    /// S3：Conditional Restore 配置面——三 flag 合并的单一载体
    /// （rollforwardEnabled / conditionalRestoreEnabled /
    /// conditionalRestoreMaxDeltaTokens）。默认值 = v1.5 生产现值；
    /// `current()` 是从 RuntimeTuning 读值的唯一入口，generate 每请求
    /// 构造一次快照，决策全程只消费快照（外审七轮 P1 关注点：
    /// 配置一次性冻结，防跨时刻拼凑）。
    struct ConditionalRestoreConfiguration: Equatable, Sendable {
        /// 旧 rf 无条件放行路径（a210155 前 A/B 基准；生产默认 false）
        var legacyRollforwardEnabled: Bool = false
        /// Conditional Restore 总开关（生产默认 true）
        var conditionalRestoreEnabled: Bool = true
        /// delta 规模门（tok 估算上限；生产默认 8192）
        var restoreDeltaLimitTokens: Int = 8192

        /// 从 RuntimeTuning 构造当前生效配置。
        static func current() -> Self {
            .init(
                legacyRollforwardEnabled: RuntimeTuning.rollforwardEnabled,
                conditionalRestoreEnabled: RuntimeTuning.conditionalRestoreEnabled,
                restoreDeltaLimitTokens: RuntimeTuning.conditionalRestoreMaxDeltaTokens)
        }
    }
    /// Conditional Restore 风险检测：账本尾部 assistant 含 tool_calls（任意
    /// 参数形状）⇒ 下一轮全模板重渲染可能键序/转义分叉。分歧源是 tool_calls
    /// 的渲染本身（真机 74 连 stale、rollforwardDiff 归因），与参数复杂度
    /// 无关——2026-09-18 深夜生产实证（82bfa0 前端）：单键参数形状在旧
    /// 多键/嵌套判据下全程 risk=false，分歧照发（22,094 tok/36.3s rebuild
    /// 逃逸）。误报代价由 delta 规模门兜底（小 delta 才恢复，extend-hit 轮
    /// 误触发 ~1-2s）；漏报代价 = 分歧税 36-490s。形状细化判据退役。
    static func rollforwardRisk(lastJSON: JSONValue?) -> Bool {
        guard case .object(let obj)? = lastJSON,
              case .array(let calls)? = obj["tool_calls"] else { return false }
        return !calls.isEmpty
    }

    /// Conditional Restore 触发门决策（纯函数，单测覆盖）。
    enum ConditionalRestoreGateDecision: Equatable {
        case allowed
        case skipDisabled
        case skipDeltaTooLarge(Int)
    }

    /// 触发门：旧 rf（rollforwardEnabled）开启 ⇒ 无条件放行（保持 a210155
    /// 前的全量预判语义，可与条件路径 A/B）；否则 conditionalRestoreEnabled
    /// 时按 delta 规模门放行，都关 ⇒ 禁用（纯 extend）。本门只做规模判定，
    /// 不做行为判定——逻辑兼容性仍由 rollforwardCompatible 在恢复路径内
    /// 守卫（内容真分叉 → checkpointStale → 回退 extend，无回归）。
    static func conditionalRestoreGate(
        configuration: ConditionalRestoreConfiguration,
        incoming: [JSONValue],
        ledgerCount: Int
    ) -> ConditionalRestoreGateDecision {
        if configuration.legacyRollforwardEnabled { return .allowed }
        guard configuration.conditionalRestoreEnabled else { return .skipDisabled }
        let estimate = Self.estimateDeltaTokens(incoming: incoming, ledgerCount: ledgerCount)
        if estimate > configuration.restoreDeltaLimitTokens {
            return .skipDeltaTooLarge(estimate)
        }
        return .allowed
    }

    /// 新增消息 token 粗估（compact-JSON 字符数 ÷ 4）。只用于规模门，不进
    /// 任何渲染/行为路径；账本全覆盖时为 0。
    static nonisolated func estimateDeltaTokens(
        incoming: [JSONValue], ledgerCount: Int
    ) -> Int {
        guard incoming.count > ledgerCount else { return 0 }
        var chars = 0
        for message in incoming.dropFirst(max(0, ledgerCount)) {
            if let serialized = compactJSON(message) { chars += serialized.count }
        }
        return chars / 4
    }

    /// CJK 感知口径（log-only 校准对照，不参与门判定）：CJK 字符 ≈1 token、
    /// 其余 ÷4。chars÷4 对中文低估 ~4×（2026-09-18 生产 12k 级回填全过
    /// 8192 门），双口径并行记录攒真实样本后重校准。
    static nonisolated func estimateDeltaTokensCJK(
        incoming: [JSONValue], ledgerCount: Int
    ) -> Int {
        guard incoming.count > ledgerCount else { return 0 }
        var cjk = 0
        var other = 0
        for scalar in compactDeltaText(incoming: incoming, ledgerCount: ledgerCount).unicodeScalars {
            if scalar.properties.isIdeographic || (0x3000...0x30FF).contains(scalar.value) {
                cjk += 1
            } else {
                other += 1
            }
        }
        return cjk + other / 4
    }

    private static nonisolated func compactDeltaText(
        incoming: [JSONValue], ledgerCount: Int
    ) -> String {
        var text = ""
        for message in incoming.dropFirst(max(0, ledgerCount)) {
            if let serialized = compactJSON(message) { text += serialized }
        }
        return text
    }

    /// roll-forward 兼容守卫：checkpoint 的 transcript 必须是本轮 incoming 的
    /// 真前缀，且逐条消息在**渲染路径字段**上语义一致（role / content /
    /// tool_call_id / tool_calls 结构——这些字段决定重渲染 token；其余字段
    /// 缺失或差异按 isPrefix 容错守门规则不阻断）。仅比 content 会把 role/
    /// id/tool_calls 结构变化误判为兼容（外审 P0-2，2026-09-18）。
    static func rollforwardCompatible(incoming: [JSONValue], restoredHistory: [JSONValue]) -> Bool {
        guard restoredHistory.count < incoming.count else { return false }
        for (i, m) in restoredHistory.enumerated() {
            guard i < incoming.count else { return false }
            if !Self.messageRenderCompatible(m, incoming[i]) { return false }
        }
        return true
    }

    /// checkpointStale 的字段级 diff（纯诊断，log-only；2026-09-18 真机 74 连
    /// checkpointStale 无法归因，prefixDiff 8ee83a5 同型判别）：定位首个不一致
    /// 消息与分歧字段，两侧 compact-JSON 后做字符级公共前缀 + 分叉摘录 + 指纹。
    /// 只写 trace，不参与任何行为判定。
    static func rollforwardDiffLine(
        incoming: [JSONValue], restoredHistory: [JSONValue]
    ) -> String {
        guard restoredHistory.count < incoming.count else {
            return "[MLX] rollforwardDiff reason=historyCount" +
                " ckpt=\(restoredHistory.count) incoming=\(incoming.count)"
        }
        for (i, m) in restoredHistory.enumerated() {
            let n = incoming[i]
            guard case .object(let a) = m, case .object(let b) = n else {
                return "[MLX] rollforwardDiff index=\(i) field=shape" +
                    " ckpt=\(shapeTag(m)) incoming=\(shapeTag(n))"
            }
            for field in Self.renderReconcileFields {
                let av = a[field] ?? .null
                let bv = b[field] ?? .null
                // 与行为判定同规则（renderFieldCompatible，外审 P1：裸比较会把
                // arguments string≡object 同值轮误报为 tool_calls 首分歧）；摘录
                // 保留原始值——协议形状差本身是诊断信息，能走到这里的必是归一化
                // 后仍异的真分歧。
                if !Self.renderFieldCompatible(field, av, bv) {
                    return "[MLX] rollforwardDiff index=\(i) field=\(field)" +
                        valueDiff(av, bv)
                }
            }
        }
        return "[MLX] rollforwardDiff reason=none"
    }

    /// 两侧值 compact-JSON 后的 len/commonPrefix/fp/分叉摘录。
    private static nonisolated func valueDiff(_ a: JSONValue, _ b: JSONValue) -> String {
        guard let sa = compactJSON(a), let sb = compactJSON(b) else {
            return " ckpt=\(shapeTag(a)) incoming=\(shapeTag(b))"
        }
        var common = 0
        for (x, y) in zip(sa, sb) {
            if x != y { break }
            common += 1
        }
        return " len=\(sa.count)/\(sb.count) commonPrefix=\(common)" +
            " fp=\(fingerprint(sa))/\(fingerprint(sb))" +
            " ckpt='\(excerpt(sa, at: common))'" +
            " incoming='\(excerpt(sb, at: common))'"
    }

    private static nonisolated func compactJSON(_ v: JSONValue) -> String? {
        guard let data = try? JSONEncoder().encode(v) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static nonisolated func shapeTag(_ v: JSONValue) -> String {
        switch v {
        case .null: return "null"
        case .bool: return "bool"
        case .number: return "num"
        case .string(let s): return "str(\(s.count))"
        case .object(let o):
            return "obj{\(o.keys.sorted().prefix(4).joined(separator: ","))}"
        case .array(let a): return "arr[\(a.count)]"
        }
    }

    /// 渲染路径对账字段表——行为判定与 diff 诊断共用同一张表，防两套规则
    /// 漂移（外审 P1，2026-09-18）。
    static var renderReconcileFields: [String] {
        ["role", "content", "tool_call_id", "tool_calls"]
    }

    /// 单字段比较规则：tool_calls 先过 normalizeJSONStrings（arguments 归一化，
    /// 真机 12:50 rollforwardDiff 实锤：OpenAI 协议回显的 function.arguments 是
    /// JSON 字符串，引擎账本 commit 存的是结构化 object——.object ≠ .string 使
    /// 凡尾部带工具调用的轮次必然 stale，2026-09-18 真机 74 连 skip 根因）；
    /// 其余字段 JSONValue 结构相等（键序无关）而非 .description——后者键序敏感，
    /// 且类型折叠（.string("null") 与 .null 同为 "null"）会把不等判为相等
    /// （外审 P1，2026-09-18）。
    static func renderFieldCompatible(_ field: String, _ a: JSONValue, _ b: JSONValue) -> Bool {
        if field == "tool_calls" {
            return Self.normalizeJSONStrings(a) == Self.normalizeJSONStrings(b)
        }
        return a == b
    }

    /// 单条消息渲染路径字段对账。
    static func messageRenderCompatible(_ checkpoint: JSONValue, _ incoming: JSONValue) -> Bool {
        guard case .object(let a) = checkpoint,
              case .object(let b) = incoming else { return checkpoint == incoming }
        for field in Self.renderReconcileFields {
            if !Self.renderFieldCompatible(field, a[field] ?? .null, b[field] ?? .null) {
                return false
            }
        }
        return true
    }

    /// 把子树中 parse 成 object/array 的 string 归一化为结构；parse 失败或
    /// 结果为标量按原样保留，避免制造新的类型折叠（"3" 不等价 3）。
    static nonisolated func normalizeJSONStrings(_ v: JSONValue) -> JSONValue {
        switch v {
        case .string(let s):
            guard let data = s.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode(JSONValue.self, from: data)
            else { return v }
            switch parsed {
            case .object, .array: return parsed
            default: return v
            }
        case .object(let o): return .object(o.mapValues(normalizeJSONStrings))
        case .array(let a): return .array(a.map(normalizeJSONStrings))
        default: return v
        }
    }

    /// 分叉点前后各 ~24 字符的摘录，控制字符折叠为空格。
    static nonisolated func excerpt(_ s: String, at offset: Int) -> String {
        let radius = 24
        let start = max(0, offset - radius / 2)
        let end = min(s.count, start + radius)
        guard start < end else { return "" }
        let chars = s.suffix(s.count - start).prefix(end - start)
        return String(chars.map { ($0.isNewline || $0 == "\t") ? " " : $0 })
    }

    /// FNV-1a 64-bit 内容指纹，取前 8 hex——诊断对账用，非安全哈希。
    static nonisolated func fingerprint(_ s: String) -> String {
        var hash: UInt64 = 0xcbf2_6482_366b_2a85
        for byte in s.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        return String(format: "%08x", UInt32(truncatingIfNeeded: hash >> 32))
    }

}
