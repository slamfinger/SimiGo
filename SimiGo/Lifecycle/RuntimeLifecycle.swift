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
    /// NativeMLX 接入流式细分状态后，生产路径应走 RUNNING→STREAMING→COMPLETING。
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
        let identity = identities[requestID]

        var parts = ["[LIFECYCLE]", "event=\(event)", "request=\(requestID)"]
        if let agent = identity?.agentID {
            parts.append("agent=\(agent)")
        }
        if let session = identity?.sessionID {
            parts.append("session=\(session)")
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
            parts.joined(separator: " "),
            session: identity?.sessionID
        )
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
