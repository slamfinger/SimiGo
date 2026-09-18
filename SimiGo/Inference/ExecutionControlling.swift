import Foundation

/// V1.6 S4：Execution Controlling 协议面（外审八轮放行；红线=薄封装
/// 零新语义——五个动作全部直映射既有运行路径，不得产生第二套执行语义）。
///
/// 映射表（唯一事实源，S4 期间不得偏离）：
/// ```text
/// execute    → NativeMLX.generate（新执行）
/// continue   → NativeMLX.generate（同 lineage 续跑；reuse 决策在
///              generate 内部，lineage 区分留 S5）
/// checkpoint → NativeMLX.saveSessionCache（BranchFork v1 存储语义）
/// restore    → NativeMLX.loadSessionCache（raw-cache 恢复语义）
/// fork       → NativeMLX.forkSessionBranch（磁盘 checkpoint fork v1；
///              真共享 fork 等上游原语，见 RFC mlx-swift-lm#629）
/// ```

/// Execution 身份 = 现有 AgentExecutionKey 三元组的直映射。
/// S4 红线：不发明新身份语义；独立 ExecutionID（随机 id8）已在 S1 以
/// 遥测形式存在（trace 观测用），与本协议的寻址身份分属不同职责。
public struct ExecutionID: Equatable, Sendable {
    public var agentId: String?
    public var sessionId: String
    public var logicalBranchId: String

    public init(agentId: String? = nil, sessionId: String, logicalBranchId: String = "main") {
        self.agentId = agentId
        self.sessionId = sessionId
        self.logicalBranchId = logicalBranchId
    }
}

/// checkpoint 身份 = Execution 身份 + 存储目录（BranchFork v1 语义）。
public struct CheckpointID: Equatable, Sendable {
    public var identity: ExecutionID
    public var store: URL

    public init(identity: ExecutionID, store: URL) {
        self.identity = identity
        self.store = store
    }
}

/// 执行请求 = 现有 generate 入参的直映射（含流式回调，缺省空实现）。
public struct ExecutionRequest: Sendable {
    public var requestId: String
    public var identity: ExecutionID
    public var messages: [JSONValue]
    public var tools: [JSONValue]?
    public var config: ModelConfig
    public var onChunk: @Sendable (String) -> Void
    public var onToolCall: @Sendable (ParsedToolCall) -> Void

    public init(
        requestId: String,
        identity: ExecutionID,
        messages: [JSONValue],
        tools: [JSONValue]? = nil,
        config: ModelConfig,
        onChunk: @escaping @Sendable (String) -> Void = { _ in },
        onToolCall: @escaping @Sendable (ParsedToolCall) -> Void = { _ in }
    ) {
        self.requestId = requestId
        self.identity = identity
        self.messages = messages
        self.tools = tools
        self.config = config
        self.onChunk = onChunk
        self.onToolCall = onToolCall
    }
}

public protocol ExecutionControlling: Sendable {
    /// 新执行：直映射 NativeMLX.generate。
    func execute(_ request: ExecutionRequest) async throws -> GenerationResult
    /// 同 lineage 续跑：当前与 execute 同映射（reuse 决策在底层内部）；
    /// lineage 区分是 S5 交付，不在 S4 虚构。
    func `continue`(_ request: ExecutionRequest) async throws -> GenerationResult
    /// 持久化：直映射 saveSessionCache（BranchFork v1 checkpoint 语义）。
    func checkpoint(_ id: ExecutionID, to store: URL?) async throws -> URL
    /// 恢复：直映射 loadSessionCache（raw-cache + fragment-continuation）。
    func restore(_ id: ExecutionID, from store: URL?) async throws -> SessionCacheMetadata
    /// 派生：直映射 forkSessionBranch（磁盘 checkpoint fork；一个 parent
    /// → 一个 child，不做 merge）。
    func fork(
        _ id: ExecutionID, sourceBranch: String, targetBranch: String,
        in store: URL?
    ) async throws -> SessionCacheMetadata
}

extension NativeMLX: ExecutionControlling {
    public func execute(_ request: ExecutionRequest) async throws -> GenerationResult {
        try await generate(
            requestId: request.requestId,
            agentId: request.identity.agentId,
            sessionId: request.identity.sessionId,
            logicalBranchId: request.identity.logicalBranchId,
            messages: request.messages,
            tools: request.tools,
            config: request.config,
            onChunk: request.onChunk,
            onToolCall: request.onToolCall)
    }

    public func `continue`(_ request: ExecutionRequest) async throws -> GenerationResult {
        // 与 execute 同映射：reuse/restore/extend 的分派是底层执行语义，
        // 协议面只提供统一入口（S4 红线：薄封装零新语义）。
        try await execute(request)
    }

    public func checkpoint(_ id: ExecutionID, to store: URL?) async throws -> URL {
        try await saveSessionCache(
            agentId: id.agentId,
            sessionId: id.sessionId,
            logicalBranchId: id.logicalBranchId,
            to: store ?? Self.defaultBranchCheckpointStore())
    }

    public func restore(_ id: ExecutionID, from store: URL?) async throws -> SessionCacheMetadata {
        try await loadSessionCache(
            agentId: id.agentId,
            sessionId: id.sessionId,
            logicalBranchId: id.logicalBranchId,
            from: store ?? Self.defaultBranchCheckpointStore())
    }

    public func fork(
        _ id: ExecutionID, sourceBranch: String, targetBranch: String,
        in store: URL?
    ) async throws -> SessionCacheMetadata {
        try await forkSessionBranch(
            agentId: id.agentId,
            sessionId: id.sessionId,
            sourceBranch: sourceBranch,
            targetBranch: targetBranch,
            in: store)
    }
}
