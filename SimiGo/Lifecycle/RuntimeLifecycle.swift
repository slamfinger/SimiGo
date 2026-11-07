import Foundation

/// SimiGo v4.5 Lifecycle Control Plane
/// 依据 SimiGo架构收敛.md Commits 1-3 重建：RuntimeState + 合法迁移表 + 唯一终止入口。
/// 纯被动账本：不触碰 Physical KV / Gate / Scheduler / Tool Protocol（白皮书 §58 准入）。
/// Trace 统一落盘到 RuntimeTraceLogger（native_mlx_trace.log）。

public enum RuntimeState: String, Sendable, CaseIterable {
    case created = "CREATED"
    case queued = "QUEUED"
    case running = "RUNNING"
    case streaming = "STREAMING"
    case completing = "COMPLETING"
    case completed = "COMPLETED"
    case cancelling = "CANCELLING"
    case draining = "DRAINING"
    case releasing = "RELEASING"
    case released = "RELEASED"

    public var isTerminal: Bool {
        self == .released
    }
}

public struct RuntimeTransitionRule {
    /// 合法迁移表 —— SimiGo架构收敛.md §3。表外一律 INVALID。
    /// ponytail: RUNNING→COMPLETING 是文档表格外的补充边（非流式请求没有 STREAMING 阶段）；
    /// CREATED→COMPLETING 同理：SSE 直发收口后协议层不再执行 QUEUED/RUNNING 迁移，
    /// 请求从 CREATED 直接进入完成路径，表必须承认这一现实，否则每次正常完成都触发 FORCE_RELEASED。
    /// CREATED→RUNNING 同理：协议层 QUEUED 补位缺失的入口（2026-09-12 实测 OpenAI 协议
    /// 请求全部死于 INVALID_TRANSITION CREATED→RUNNING → cancelled_internally），
    /// 请求既已持有 generation gate，事实状态即 RUNNING；trace 线 from=CREATED to=RUNNING
    /// 即漏补位入口的定位标记。
    /// QUEUED→COMPLETING（2026-11-06）：不占引擎窗口就完成的路径客观存在——
    /// IS 复用（model_calls=0）、工具调用轮被跳过结算、`max_tokens` 直发收口。
    /// 这些请求从未拿到引擎，事实状态就该停在 QUEUED；若表不承认这条边，
    /// 每次复用答案都触发 FORCE_RELEASED，把「表拒绝」这个异常信号稀释成噪音。
    /// 注意：这条边**不**用来掩盖「真跑了引擎却没置 RUNNING」——那条由推理层
    /// 收口（NativeMLX 在拿到 gate 后置位，ManagedGGUFRuntime 自 2026-11-06 起同法）。
    public nonisolated static func isValid(
        from: RuntimeState,
        to: RuntimeState
    ) -> Bool {
        if to == .cancelling {
            // 收敛文档 §2：任何状态（除 RELEASED 终态）都可进入取消管道
            return from != .released
        }

        switch (from, to) {
        case (.created, .queued),
             (.created, .running),
             (.created, .completing),
             (.queued, .completing),
             (.queued, .running),
             (.running, .streaming),
             (.running, .completing),
             (.streaming, .completing),
             (.completing, .completed),
             (.completed, .releasing),
             (.cancelling, .draining),
             (.draining, .releasing),
             (.releasing, .released):
            return true
        default:
            return false
        }
    }
}

/// 拒绝风暴首尾记录器（2026-10-16）。
///
/// 客户端压缩失准时会以亚秒级间隔连发超限请求（2026-10-16 实测：
/// 222 笔/约 90s，每笔 7 行流水 ≈ 1100 行噪音，同期真实生成仅 3 笔）。
/// 语义上这是同一事件的重复：头笔完整记录；成员笔的 REJECT 行与 LC
/// 收尾流水抑制（arrive 与 QUEUED→RUNNING 在判定前已发出，天然保留
/// ——排枪节奏是客户端行为取证锚，execution_bench 依赖 to=RUNNING）；
/// 风暴结束（同键过门或窗口超时）补一行聚合尾。异常路径（表外迁移/
/// FORCE_RELEASED/INVALID_*/*_UNKNOWN）事件名不在抑制白名单内，永不抑制。
public final class RejectBurstTracker: @unchecked Sendable {

    public static let shared = RejectBurstTracker()

    /// 窗口：相邻两笔拒绝间隔 < 10s 视为同一风暴（实测排枪间隔 ~370ms；
    /// 正常用户轮次间隔远大于 10s，不会误并）。
    private static let burstWindow: TimeInterval = 10

    private struct Burst {
        var count = 0
        var firstAt = Date()
        var lastAt = Date()
        var demandMin = Int.max
        var demandMax = 0
    }

    private let lock = NSLock()
    private var bursts: [String: Burst] = [:]
    private var quietKeysByRequest: [String: String] = [:]
    private var flushTasks: [String: Task<Void, Never>] = [:]

    private init() {}

    /// REJECT 判定处调用。true = 本笔是风暴成员（其 REJECT 行与 LC
    /// 收尾流水由抑制钩子接管）；false = 头笔，调用方照常记录完整行。
    public func noteReject(
        key: String,
        requestID: String,
        demand: Int
    ) -> Bool {
        let now = Date()
        let member: Bool
        lock.lock()
        if var burst = bursts[key] {
            burst.count += 1
            burst.lastAt = now
            burst.demandMin = min(burst.demandMin, demand)
            burst.demandMax = max(burst.demandMax, demand)
            bursts[key] = burst
            quietKeysByRequest[requestID] = key
            member = true
        } else {
            bursts[key] = Burst(
                count: 1,
                firstAt: now,
                lastAt: now,
                demandMin: demand,
                demandMax: demand
            )
            member = false
        }
        lock.unlock()

        armFlush(key: key)
        return member
    }

    /// 同键请求过门（真实生成开始）时调用：立即冲刷聚合尾行。
    public func noteAdmitted(key: String) {
        flush(key: key)
    }

    /// LC trace 抑制查询：该请求是否为活跃风暴成员。
    public func isQuiet(requestID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return quietKeysByRequest[requestID] != nil
    }

    private func armFlush(key: String) {
        lock.lock()
        flushTasks[key]?.cancel()
        let task = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(Self.burstWindow * 1_000_000_000)
            )
            self?.flush(key: key)
        }
        flushTasks[key] = task
        lock.unlock()
    }

    private func flush(key: String) {
        lock.lock()
        guard let burst = bursts[key] else {
            lock.unlock()
            return
        }
        bursts[key] = nil
        flushTasks[key]?.cancel()
        flushTasks[key] = nil
        quietKeysByRequest = quietKeysByRequest.filter { $0.value != key }
        lock.unlock()

        guard burst.count > 1 else { return }
        RuntimeTraceLogger.shared.trace(
            "[CONTEXT SAFETY REJECT] burstSuppressed key=\(key)" +
            " count=\(burst.count) suppressed=\(burst.count - 1)" +
            " spanMs=\(Int(burst.lastAt.timeIntervalSince(burst.firstAt) * 1000))" +
            " demand=\(burst.demandMin)..\(burst.demandMax)" +
            " action=require_L1_compaction"
        )
    }
}

private struct RequestIdentity: Sendable {
    let agentID: String?
    let sessionID: String?

    nonisolated init(agentID: String?, sessionID: String?) {
        self.agentID = agentID
        self.sessionID = sessionID
    }
}

/// 生命周期聚合快照（2026-11-06）。
///
/// 状态是**运行期事实**：任何需要"现在有没有在途请求""这次取消走的是哪条
/// 管道"的判断，都从这份快照读，不要求调用方（测试、外部工具）去解析
/// `native_mlx_trace.log` 的文本。日志只承担事后取证，不承担判定。
public struct LifecycleSnapshot: Sendable, Equatable {
    /// 当前各状态的在册请求数（RELEASED 超过上限即逐出，不进这里）。
    public let byState: [String: Int]
    /// 累计迁移计数，键形如 `queued→running`；异常兜底另记 `forced`。
    public let transitions: [String: Int]
    /// 本进程注册过的请求总数。
    public let registered: Int

    /// 已进队或已在跑、尚未收口的请求数——"有没有在途生成"的唯一判据。
    public var inFlight: Int {
        (byState[RuntimeState.queued.rawValue] ?? 0)
            + (byState[RuntimeState.running.rawValue] ?? 0)
    }
}

public actor RuntimeLifecycleCoordinator {
    public static let shared = RuntimeLifecycleCoordinator()

    private var states: [String: RuntimeState] = [:]
    private var identities: [String: RequestIdentity] = [:]
    /// 每请求的迁移路径（`finish` 时一次写入），供进程内读取；
    /// 与 `states` 同寿命，随 RELEASED 逐出一并清理。
    private var paths: [String: [String]] = [:]
    private var transitionCounts: [String: Int] = [:]
    private var forcedCount = 0
    private var registeredCount = 0

    public init() {}

    /// 注册请求唯一身份（收敛文档 §1）。必须在首次 transition 之前完成。
    public func register(
        requestID: String,
        agentID: String? = nil,
        sessionID: String? = nil
    ) {
        guard states[requestID] == nil else {
            trace(requestID, event: "REGISTER_DUPLICATE")
            return
        }

        states[requestID] = .created
        identities[requestID] = RequestIdentity(
            agentID: agentID,
            sessionID: sessionID
        )
        registeredCount += 1
        trace(requestID, event: "REGISTER", to: RuntimeState.created.rawValue)
        publishSnapshot()
    }

    /// 受状态机校验的迁移（收敛文档 §3）：表外迁移一律 INVALID 并记录 Trace。
    @discardableResult
    public func transition(
        requestID: String,
        to target: RuntimeState
    ) throws -> RuntimeState {
        guard let current = states[requestID] else {
            trace(requestID, event: "TRANSITION_UNKNOWN", to: target.rawValue)
            throw RuntError.generationFailed(
                "Lifecycle: unknown request identity \(requestID), cannot transition to \(target.rawValue)"
            )
        }

        guard RuntimeTransitionRule.isValid(from: current, to: target) else {
            trace(requestID, event: "INVALID_TRANSITION", from: current.rawValue, to: target.rawValue)
            throw RuntError.generationFailed(
                "Invalid lifecycle transition from \(current.rawValue) to \(target.rawValue) for request \(requestID)"
            )
        }

        states[requestID] = target
        paths[requestID, default: [current.rawValue]].append(target.rawValue)
        bump("\(current.rawValue)→\(target.rawValue)")
        trace(requestID, event: "STATE_TRANSITION", from: current.rawValue, to: target.rawValue)
        publishSnapshot()
        return target
    }

    /// 统一终止入口（收敛文档 §5）：正常完成 / 取消 / 错误 / 断连全部汇入。
    /// 成功 → COMPLETING→COMPLETED→RELEASING→RELEASED；失败/取消 → CANCELLING→DRAINING→RELEASING→RELEASED。
    /// 幂等：重复 finish 只记录 Trace，不崩溃（收敛文档 §10：重复 release 不崩溃）。
    public func finish(
        requestID: String,
        success: Bool,
        reason: String
    ) {
        guard let current = states[requestID] else {
            trace(requestID, event: "FINISH_UNKNOWN", reason: reason)
            return
        }

        guard current != .released else {
            trace(requestID, event: "FINISH_DUPLICATE", reason: reason)
            return
        }

        let path: [RuntimeState] = success
            ? (current == .completed
               ? [.releasing, .released]
               : [.completing, .completed, .releasing, .released])
            : [.cancelling, .draining, .releasing, .released]

        // 收尾路径一次成型（2026-11-05 日志瘦身）：取消/完成的逐跳迁移由
        // 迁移表本身保证，逐跳 trace 没有独立信息量，只留一行带 `path=`
        // 的 RELEASED。异常（表外迁移被拒）照旧单独告警，不合并。
        var hops: [String] = [current.rawValue]
        for step in path {
            let from = states[requestID] ?? .released
            if !RuntimeTransitionRule.isValid(from: from, to: step) {
                // 迁移表意外拒绝时不允许卡死：收敛文档最终原则 —— 活跃 Runtime 必须收敛到 RELEASED
                forcedCount += 1
                trace(requestID, event: "FORCE_RELEASED", from: from.rawValue, reason: "unexpected table rejection")
            }
            states[requestID] = step
            hops.append(step.rawValue)
            bump("\(from.rawValue)→\(step.rawValue)")
        }
        paths[requestID] = hops
        trace(requestID, event: "RELEASED", reason: reason, path: hops.joined(separator: "→"))

        evictReleasedIfNeeded()
        publishSnapshot()
    }

    /// 收敛文档 §9 Invariant 1 观测点：NativeMLX 请求任务真实收尾时回报。
    /// RELEASED 之后才收到 ⇒ 释放先于任务收尾（取消路径的固有窗口），记入 Trace 供审计。
    public func noteRequestTaskEnded(requestID: String) {
        guard let current = states[requestID] else {
            trace(requestID, event: "TASK_ENDED_UNKNOWN")
            return
        }

        if current == .released {
            trace(requestID, event: "INVARIANT_TASK_ENDED_AFTER_RELEASE")
        } else {
            trace(requestID, event: "TASK_ENDED", to: current.rawValue)
        }
    }

    public func state(of requestID: String) -> RuntimeState? {
        states[requestID]
    }

    /// 该请求已走过的迁移路径（含起点）。收口后仍可读，直到被逐出。
    public func path(of requestID: String) -> [String] {
        paths[requestID] ?? []
    }

    /// 进程内聚合快照：判定"有没有在途生成""取消走了哪条管道"的唯一入口。
    public func snapshot() -> LifecycleSnapshot {
        var byState: [String: Int] = [:]
        for state in states.values {
            byState[state.rawValue, default: 0] += 1
        }
        var transitions = transitionCounts
        if forcedCount > 0 { transitions["forced"] = forcedCount }
        return LifecycleSnapshot(
            byState: byState,
            transitions: transitions,
            registered: registeredCount
        )
    }

    private func bump(_ key: String) {
        transitionCounts[key, default: 0] += 1
    }

    /// 结构化状态外发：跨进程消费者读 JSON，不解析 trace 文本。
    private func publishSnapshot() {
        RuntimeStateReporter.shared.report(snapshot())
    }

    /// 防状态积累：RELEASED 条目只用于短期审计，超过上限即逐出（收敛目标：Runtime 归零）。
    private func evictReleasedIfNeeded() {
        guard states.count > 512 else { return }

        for (id, state) in states where state == .released {
            states.removeValue(forKey: id)
            identities.removeValue(forKey: id)
            paths.removeValue(forKey: id)
        }
    }

    private func trace(
        _ requestID: String,
        event: String,
        from: String? = nil,
        to: String? = nil,
        reason: String? = nil,
        path: String? = nil
    ) {
        // 拒绝风暴成员（2026-10-16）：REJECT 语义已由风暴头笔 +
        // burstSuppressed 聚合尾行承载，成员笔的收尾流水抑制。
        // 收尾已合并为单行 RELEASED（2026-11-05），此处只剩这一处抑制点；
        // 异常路径（表外迁移/FORCE_RELEASED/INVALID_*/*_UNKNOWN）事件名
        // 不匹配，永不抑制。
        if event == "RELEASED" {
            if RejectBurstTracker.shared.isQuiet(requestID: requestID) {
                return
            }
        }

        // 生产降噪（2026-09-29）：正常路径只留两条定位锚——QUEUED→RUNNING
        // （在途标记：execution_bench preflight 与在途生成判别依赖 " to=RUNNING"）
        // 和 RELEASED（带 reason + path 收口）。被抑制的 REGISTER / CREATED→QUEUED /
        // RUNNING→COMPLETING / CREATED→COMPLETING 及收尾各跳：回归时签名仍在
        // ——漏 QUEUED 会以 from=CREATED to=RUNNING 现形（2026-09-12 实证），
        // 表外迁移/取消/FORCE_RELEASED 等异常路径永不抑制。
        if event == "REGISTER" {
            return
        }
        if event == "STATE_TRANSITION",
           from == "COMPLETING", to == "COMPLETED" {
            return
        }
        if event == "STATE_TRANSITION",
           from == "COMPLETED", to == "RELEASING" {
            return
        }
        if event == "STATE_TRANSITION",
           from == "RELEASING", to == "RELEASED" {
            return
        }
        if event == "STATE_TRANSITION",
           from == "CREATED", to == "QUEUED" {
            return
        }
        if event == "STATE_TRANSITION",
           from == "CREATED", to == "COMPLETING" {
            return
        }
        if event == "STATE_TRANSITION",
           from == "RUNNING", to == "COMPLETING" {
            return
        }

        let identity = identities[requestID]

        var parts = ["[LC]", event, "r=\(Self.shortID(requestID))"]
        if let session = identity?.sessionID {
            parts.append("s=\(Self.shortID(session))")
        }
        if let from {
            parts.append("from=\(from)")
        }
        if let to {
            parts.append("to=\(to)")
        }
        if let reason {
            parts.append("reason=\(reason)")
        }
        if let path {
            parts.append("path=\(path)")
        }

        RuntimeTraceLogger.shared.trace(
            parts.joined(separator: " ")
        )
    }

    private static func shortID(_ id: String) -> String {
        var value = id
        if value.hasPrefix("req-") {
            value.removeFirst(4)
        }
        return String(value.prefix(6))
    }

    /// 启动自检（收敛文档 §10 最小矩阵）。不使用 assert，Release 构建下同样生效。
    public static func demoSelfCheck() {
        Task {
            let coordinator = RuntimeLifecycleCoordinator()
            var failures: [String] = []

            func check(_ condition: Bool, _ name: String) {
                if !condition {
                    failures.append(name)
                }
            }

            // 1. 正常完成 → RELEASED
            await coordinator.register(requestID: "selfcheck-ok")
            var happyOK = true
            for step: RuntimeState in [.queued, .running, .completing, .completed, .releasing, .released] {
                let result = try? await coordinator.transition(requestID: "selfcheck-ok", to: step)
                if result == nil {
                    happyOK = false
                }
            }
            check(happyOK, "happy path")

            // 2. 取消管道收敛到 RELEASED；重复 finish 幂等不崩溃
            await coordinator.register(requestID: "selfcheck-cancel")
            await coordinator.finish(requestID: "selfcheck-cancel", success: false, reason: "selfcheck-cancel")
            await coordinator.finish(requestID: "selfcheck-cancel", success: false, reason: "selfcheck-duplicate")
            check(await coordinator.state(of: "selfcheck-cancel") == .released, "cancel converges + idempotent")

            // 3. Invariant 6：RELEASED 是终态，拒绝任何后续迁移
            let terminal = (try? await coordinator.transition(requestID: "selfcheck-ok", to: .running)) == nil
            check(terminal, "RELEASED is terminal")

            // 4. 未知身份迁移必须拒绝（唯一身份原则）
            let unknown = (try? await coordinator.transition(requestID: "selfcheck-missing", to: .queued)) == nil
            check(unknown, "unknown identity rejected")

            RuntimeTraceLogger.shared.trace(
                failures.isEmpty
                    ? "[LIFECYCLE] self-check passed (4/4)"
                    : "[LIFECYCLE] self-check FAILED: \(failures.joined(separator: ", "))"
            )
        }
    }
}
