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

public actor RuntimeLifecycleCoordinator {
    public static let shared = RuntimeLifecycleCoordinator()

    private var states: [String: RuntimeState] = [:]
    private var identities: [String: RequestIdentity] = [:]

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
        trace(requestID, event: "REGISTER", to: RuntimeState.created.rawValue)
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
        trace(requestID, event: "STATE_TRANSITION", from: current.rawValue, to: target.rawValue)
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

        for step in path {
            let from = states[requestID] ?? .released
            if RuntimeTransitionRule.isValid(from: from, to: step) {
                trace(requestID, event: "STATE_TRANSITION", from: from.rawValue, to: step.rawValue)
            } else {
                // 迁移表意外拒绝时不允许卡死：收敛文档最终原则 —— 活跃 Runtime 必须收敛到 RELEASED
                trace(requestID, event: "FORCE_RELEASED", from: from.rawValue, reason: "unexpected table rejection")
            }
            states[requestID] = step
        }
        trace(requestID, event: "RELEASED", reason: reason)

        evictReleasedIfNeeded()
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

    /// 防状态积累：RELEASED 条目只用于短期审计，超过上限即逐出（收敛目标：Runtime 归零）。
    private func evictReleasedIfNeeded() {
        guard states.count > 512 else { return }

        for (id, state) in states where state == .released {
            states.removeValue(forKey: id)
            identities.removeValue(forKey: id)
        }
    }

    private func trace(
        _ requestID: String,
        event: String,
        from: String? = nil,
        to: String? = nil,
        reason: String? = nil
    ) {
        // 拒绝风暴成员（2026-10-16）：REJECT 语义已由风暴头笔 +
        // burstSuppressed 聚合尾行承载，成员笔的收尾流水抑制。
        // 只抑制收尾白名单（RELEASED 与取消管道三跳）；异常路径
        // （表外迁移/FORCE_RELEASED/INVALID_*/*_UNKNOWN）事件名不
        // 匹配，永不抑制。
        if event == "RELEASED"
            || (event == "STATE_TRANSITION"
                && (from == "RUNNING"
                    || from == "CANCELLING"
                    || from == "DRAINING")) {
            if RejectBurstTracker.shared.isQuiet(requestID: requestID) {
                return
            }
        }

        // 生产降噪（2026-09-29）：正常路径只留两条定位锚——QUEUED→RUNNING
        // （在途标记：execution_bench preflight 与在途生成判别依赖 " to=RUNNING"，
        // 排队计时依赖 CREATED→QUEUED / QUEUED→RUNNING 两条，故保留）
        // 和 RELEASED（带 reason 收口）。被抑制的 REGISTER / CREATED→QUEUED /
        // RUNNING→COMPLETING / CREATED→COMPLETING 及成功尾段：回归时签名仍在
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
