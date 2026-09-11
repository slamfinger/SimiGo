import Foundation

/// P1-3 Tool Governance Contract v1
/// （docs/decisions/TOOL_GOVERNANCE_CONTRACT.md，基线 6ba28f0 冻结）
///
/// Runtime 层工具治理：backend 只上报"模型产生了 tool call"；
/// 允许/验证/拒绝/派发/结果/失败的判定与记录在此层，与具体 backend 解耦。
///
/// 层边界：Backend observation ≠ Runtime governance fact ≠ Tool execution fact。

nonisolated public enum ToolGovernanceEvent: String, Sendable {
    case requested = "TOOL_REQUESTED"
    case validated = "TOOL_VALIDATED"
    case rejected = "TOOL_REJECTED"
    case dispatched = "TOOL_DISPATCHED"
    case result = "TOOL_RESULT"
    case failed = "TOOL_FAILED"
}

nonisolated public enum ToolGovernanceState: String, Sendable {
    case requested
    case validated
    case dispatched
    case rejected   // 终态（governance rejection）
    case result     // 终态（成功）
    case failed     // 终态（执行失败）
}

nonisolated public enum ToolGovernanceCode: String, Sendable {
    // REJECTED（治理阶段）
    case unknownTool = "unknown_tool"
    case invalidArguments = "invalid_arguments"
    case capabilityNotAllowed = "capability_not_allowed"
    case policyDenied = "policy_denied"
    case runtimeBusy = "runtime_busy"
    // FAILED（执行阶段）
    case executionError = "execution_error"
    // 跨阶段（按生命周期位置归属事件）
    case cancelled
    case timeout
}

/// 一次工具调用的生命周期记录。
nonisolated public struct ToolInvocation: Sendable {
    public let generationId: String
    public let tool: String
    public var state: ToolGovernanceState
    public var argumentsRaw: String?
    /// 工具在 SimiGo 外部执行（如 Codex client）→ 记录为 observed result；
    /// Runtime 内部执行器执行 → executed。v1 无内部执行器，恒为 observed。
    public var resultObserved: Bool

    public init(
        generationId: String,
        tool: String,
        state: ToolGovernanceState,
        argumentsRaw: String?,
        resultObserved: Bool = false
    ) {
        self.generationId = generationId
        self.tool = tool
        self.state = state
        self.argumentsRaw = argumentsRaw
        self.resultObserved = resultObserved
    }
}

/// Runtime 层工具治理状态机。
/// 非法转移不被伪造为其他终态——记录为 anomaly 并保持原状态（可诊断）。
public final class ToolGovernance: @unchecked Sendable {
    private let lock = NSLock()
    private var invocations: [String: ToolInvocation] = [:]
    private let emit: (String) -> Void

    public init(emit: @escaping (String) -> Void) {
        self.emit = emit
    }

    // MARK: - ① REQUESTED（backend observation → Runtime invocation）

    public func requested(
        requestId: String,
        generationId: String,
        toolCallId: String,
        tool: String,
        argumentsRaw: String?
    ) {
        lock.lock()
        if invocations[toolCallId] != nil {
            lock.unlock()
            emitLine(
                event: ToolGovernanceEvent.requested,
                requestId: requestId, generationId: generationId,
                toolCallId: toolCallId, tool: tool,
                state: nil, code: nil,
                anomaly: "duplicate_tool_call_id"
            )
            return
        }
        invocations[toolCallId] = ToolInvocation(
            generationId: generationId,
            tool: tool,
            state: .requested,
            argumentsRaw: argumentsRaw
        )
        lock.unlock()
        emitLine(
            event: .requested,
            requestId: requestId, generationId: generationId,
            toolCallId: toolCallId, tool: tool,
            state: .requested, code: nil, anomaly: nil
        )
    }

    // MARK: - ② VALIDATED / REJECTED / DISPATCHED

    public func validated(requestId: String, generationId: String, toolCallId: String) {
        transition(
            requestId: requestId, generationId: generationId, toolCallId: toolCallId,
            to: .validated, event: .validated, code: nil, message: nil
        )
    }

    public func rejected(
        requestId: String,
        generationId: String,
        toolCallId: String,
        code: ToolGovernanceCode,
        message: String
    ) {
        transition(
            requestId: requestId, generationId: generationId, toolCallId: toolCallId,
            to: .rejected, event: .rejected, code: code, message: message
        )
    }

    /// v1 预留：SimiGo 无内部工具执行器，当前不产生。
    /// 未来接入内部 executor 时，handoff 之后调用。
    public func dispatched(requestId: String, generationId: String, toolCallId: String) {
        transition(
            requestId: requestId, generationId: generationId, toolCallId: toolCallId,
            to: .dispatched, event: .dispatched, code: nil, message: nil
        )
    }

    // MARK: - ③ RESULT / FAILED（终态）

    /// 外部执行观测：tool result 由客户端回传（function_call_output）。
    public func resultObserved(
        requestId: String,
        generationId: String,
        toolCallId: String,
        sizeBytes: Int?
    ) {
        lock.lock()
        guard var invocation = invocations[toolCallId] else {
            lock.unlock()
            emitLine(
                event: .result,
                requestId: requestId, generationId: requestId,
                toolCallId: toolCallId, tool: "-",
                state: nil, code: nil,
                anomaly: "unknown_tool_call_id"
            )
            return
        }
        guard invocation.state == .validated || invocation.state == .dispatched else {
            lock.unlock()
            emitLine(
                event: .result,
                requestId: requestId,
                generationId: invocation.generationId,
                toolCallId: toolCallId, tool: invocation.tool,
                state: invocation.state, code: nil,
                anomaly: "unexpected_state"
            )
            return
        }
        invocation.state = .result
        invocation.resultObserved = true
        invocations[toolCallId] = invocation
        lock.unlock()
        emitLine(
            event: .result,
            requestId: requestId,
            generationId: invocation.generationId,
            toolCallId: toolCallId, tool: invocation.tool,
            state: .result, code: nil,
            anomaly: nil
        )
    }

    /// Runtime 内部执行器失败（预留；v1 无内部执行器）。
    public func failed(
        requestId: String,
        generationId: String,
        toolCallId: String,
        code: ToolGovernanceCode,
        message: String
    ) {
        lock.lock()
        guard var invocation = invocations[toolCallId] else {
            lock.unlock()
            emitLine(
                event: .failed,
                requestId: requestId, generationId: generationId,
                toolCallId: toolCallId, tool: "-",
                state: nil, code: code,
                anomaly: "unknown_tool_call_id"
            )
            return
        }
        invocation.state = .failed
        invocations[toolCallId] = invocation
        lock.unlock()
        emitLine(
            event: .failed,
            requestId: requestId, generationId: generationId,
            toolCallId: toolCallId, tool: invocation.tool,
            state: .failed, code: code,
            anomaly: nil
        )
    }

    // MARK: - 异常（孤儿/未知/重复）

    /// 生成收尾扫描：未终态 invocation 记录为 orphan anomaly。
    /// 不伪造 FAILED——"没有终态"与"工具执行失败"是不同事实。
    public func reportOrphans(requestId: String) {
        lock.lock()
        let orphans = invocations.values.filter { $0.state != .result && $0.state != .failed }
        lock.unlock()
        for invocation in orphans where invocation.state != .failed {
            emitLine(
                event: nil,
                requestId: requestId, generationId: requestId,
                toolCallId: "-", tool: invocation.tool,
                state: invocation.state, code: nil,
                anomaly: "orphan_invocation_state=\(invocation.state.rawValue)"
            )
        }
    }

    public func anomaly(requestId: String, message: String) {
        emitLine(
            event: nil,
            requestId: requestId, generationId: requestId,
            toolCallId: "-", tool: "-",
            state: nil, code: nil,
            anomaly: message
        )
    }

    // MARK: - 内部

    private func transition(
        requestId: String,
        generationId: String,
        toolCallId: String,
        to target: ToolGovernanceState,
        event: ToolGovernanceEvent,
        code: ToolGovernanceCode?,
        message: String?
    ) {
        lock.lock()
        guard var invocation = invocations[toolCallId] else {
            lock.unlock()
            emitLine(
                event: event,
                requestId: requestId, generationId: generationId,
                toolCallId: toolCallId, tool: "-",
                state: nil, code: code,
                anomaly: "unknown_tool_call_id"
            )
            return
        }
        guard isLegalTransition(from: invocation.state, to: target) else {
            lock.unlock()
            emitLine(
                event: event,
                requestId: requestId, generationId: generationId,
                toolCallId: toolCallId, tool: invocation.tool,
                state: invocation.state, code: code,
                anomaly: "illegal_transition_from=\(invocation.state.rawValue)"
            )
            return
        }
        invocation.state = target
        invocations[toolCallId] = invocation
        lock.unlock()
        emitLine(
            event: event,
            requestId: requestId, generationId: generationId,
            toolCallId: toolCallId, tool: invocation.tool,
            state: target, code: code,
            anomaly: nil
        )
    }

    private func emitLine(
        event: ToolGovernanceEvent?,
        requestId: String,
        generationId: String,
        toolCallId: String,
        tool: String,
        state: ToolGovernanceState?,
        code: ToolGovernanceCode?,
        anomaly: String?
    ) {
        var line = "[TOOL]"
        if let event { line += " event=\(event.rawValue)" }
        line += " r=\(requestId) gen=\(generationId) tc=\(toolCallId) tool=\(tool)"
        if let state { line += " state=\(state.rawValue)" }
        if let code { line += " code=\(code.rawValue)" }
        if let anomaly { line += " anomaly=\(anomaly)" }
        emit(line)
    }

    private func isLegalTransition(
        from: ToolGovernanceState,
        to targetState: ToolGovernanceState
    ) -> Bool {
        switch (from, targetState) {
        case (.requested, .validated),
             (.validated, .dispatched),
             (.validated, .rejected),
             (.requested, .rejected),      // dispatch 前取消（规则 4）
             (.dispatched, .result),
             (.dispatched, .failed):
            return true
        default:
            return false
        }
    }
}
