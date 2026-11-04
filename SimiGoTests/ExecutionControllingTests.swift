import XCTest
@testable import SimiGo

/// S4 验收：ExecutionControlling 五动作薄封装——
/// 未加载模型时各动作必须透传底层错误（notLoaded/no live session），
/// 证明协议面是纯委托、零第二套执行语义（外审八轮红线）。
final class ExecutionControllingTests: XCTestCase {
    private func freshRuntime() -> NativeMLX {
        NativeMLX(
            info: ModelInfo(path: "/nonexistent-model", kind: .mlx),
            config: ModelConfig())
    }

    private let identity = ExecutionID(sessionId: "s4", logicalBranchId: "main")

    func testExecuteDelegatesAndSurfacesNotLoaded() async {
        let runtime = freshRuntime()
        do {
            _ = try await runtime.execute(ExecutionRequest(
                requestId: "s4-execute", identity: identity,
                messages: [.object(["role": .string("user"),
                                    "content": .string("x")])],
                config: ModelConfig()))
            XCTFail("未加载模型时 execute 应抛错")
        } catch let error as RuntError {
            if case .notLoaded = error {
                // 预期：底层 notLoaded 透传
            } else {
                XCTFail("意外 RuntError: \(error)")
            }
        } catch {
            XCTFail("意外错误类型: \(error)")
        }
        XCTAssertFalse(runtime.isGenerating)
    }

    func testContinueDelegatesAndSurfacesNotLoaded() async {
        let runtime = freshRuntime()
        do {
            _ = try await runtime.continue(ExecutionRequest(
                requestId: "s4-continue", identity: identity,
                messages: [.object(["role": .string("user"),
                                    "content": .string("x")])],
                config: ModelConfig()))
            XCTFail("未加载模型时 continue 应抛错")
        } catch let error as RuntError {
            if case .notLoaded = error {
                // 预期：底层 notLoaded 透传
            } else {
                XCTFail("意外 RuntError: \(error)")
            }
        } catch {
            XCTFail("意外错误类型: \(error)")
        }
    }

    func testCheckpointRestoreForkDelegationWithoutModel() async {
        let runtime = freshRuntime()
        await XCTAssertThrowsNotLoadedAsync(try await runtime.checkpoint(
            identity, to: nil))
        await XCTAssertThrowsNotLoadedAsync(try await runtime.restore(
            identity, from: nil))
        await XCTAssertThrowsNotLoadedAsync(try await runtime.fork(
            identity, sourceBranch: "main", targetBranch: "s4fork", in: nil))
    }

    /// 协议面调度验证：经 `any ExecutionControlling` existential 调用，
    /// 证明 协议定义→conformance→existential→调用 全链可用（外审九轮
    /// P2 测试增强：静态类型 NativeMLX 直调只证明了 extension 存在）。
    func testProtocolExistentialDispatch() async {
        let controller: any ExecutionControlling = freshRuntime()
        do {
            _ = try await controller.execute(ExecutionRequest(
                requestId: "s4-existential", identity: identity,
                messages: [.object(["role": .string("user"),
                                    "content": .string("x")])],
                config: ModelConfig()))
            XCTFail("未加载模型时协议面 execute 应抛错")
        } catch let error as RuntError {
            if case .notLoaded = error {
                // 预期：底层 notLoaded 透传
            } else {
                XCTFail("意外 RuntError: \(error)")
            }
        } catch {
            XCTFail("意外错误类型: \(error)")
        }
    }

    /// S4 红线钉子（2026-10-16 收敛补）：ExecutionID ↔ AgentExecutionKey
    /// 三元组直映射——协议面不得发明第二套身份语义。字段逐一直等，
    /// storageKey 拼接形态同时钉死（UI 投影的标签推导依赖此形态）。
    func testExecutionIdentityDirectMapping() throws {
        let id = ExecutionID(agentId: "agent-a", sessionId: "es-idmap", logicalBranchId: "b1")
        let key = try AgentExecutionKey.resolve(
            agentId: id.agentId,
            sessionId: id.sessionId,
            logicalBranchId: id.logicalBranchId)
        XCTAssertEqual(key.agentId, id.agentId)
        XCTAssertEqual(key.sessionId, id.sessionId)
        XCTAssertEqual(key.logicalBranchId, id.logicalBranchId)
        XCTAssertEqual(key.storageKey, "agent-a/es-idmap/b1")
    }

    /// 投影标签惯例（2026-10-16 收敛补）：compactLabel 必须镜像
    /// traceKey 语义（default agent 省略、session 折叠末段 ≤6 位），
    /// client-split 分片后缀原样保留——双客户端分片在 UI 必须可区分。
    func testCompactLabelMirrorsTraceKeyConvention() throws {
        let key = try AgentExecutionKey.resolve(
            agentId: nil, sessionId: "01a13e47-9dc810ab", logicalBranchId: "main")
        XCTAssertEqual(key.traceKey, "c810ab/main")
        XCTAssertEqual(
            EngineExecutionStateSnapshot.compactLabel(mapKey: key.storageKey),
            key.traceKey)
        XCTAssertEqual(
            EngineExecutionStateSnapshot.compactLabel(mapKey: key.storageKey + "#b2b3ae34"),
            "c810ab/main#b2b3ae34")
        XCTAssertEqual(
            EngineExecutionStateSnapshot.compactLabel(mapKey: "agent-x/01a13e47-9dc810ab/main"),
            "agent-x/c810ab/main")
        // 非标准 storageKey 形态（退化路径）：末 12 字符 + 分片后缀。
        XCTAssertEqual(
            EngineExecutionStateSnapshot.compactLabel(mapKey: "irregular#abc"),
            "irregular#abc")
    }

    /// F1 回归钉（2026-10-16 外审）：展示标签经有损压缩可碰撞——两个
    /// 原始键不同、压缩后标签相同的会话，列表身份（mapKey）必须不同。
    /// ForEach 不得用 label 作 id。
    func testCollidingLabelsKeepDistinctIdentities() {
        let first = "default/s-aaaa111111/main"
        let second = "default/s-bbbb111111/main"
        let firstLabel = EngineExecutionStateSnapshot.compactLabel(mapKey: first)
        let secondLabel = EngineExecutionStateSnapshot.compactLabel(mapKey: second)
        XCTAssertEqual(firstLabel, secondLabel, "用例构造前提：两键压缩标签必须相同")
        XCTAssertNotEqual(first, second, "身份必须以完整 mapKey 区分，不受标签碰撞影响")
    }

    /// F4 收紧（2026-10-16 外审）：生产标签路径是 label(mapKey:executionKey:)
    /// ——executionKey 在场时用 traceKey + storageKey 前缀差还原分片后缀，
    /// 该分支的碰撞/保留语义须单独钉住（compactLabel 测试覆盖不到它）。
    func testProductionLabelBranchKeepsShardSuffix() throws {
        let key = try AgentExecutionKey.resolve(
            agentId: nil, sessionId: "01a13e47-9dc810ab", logicalBranchId: "main")
        XCTAssertEqual(key.traceKey, "c810ab/main")
        XCTAssertEqual(
            EngineExecutionStateSnapshot.label(mapKey: key.storageKey, executionKey: key),
            key.traceKey)
        XCTAssertEqual(
            EngineExecutionStateSnapshot.label(
                mapKey: key.storageKey + "#b2b3ae34", executionKey: key),
            "c810ab/main#b2b3ae34")
        XCTAssertEqual(
            EngineExecutionStateSnapshot.label(mapKey: "unrelated", executionKey: key),
            key.traceKey)
    }

    /// F2 残余收口回归（2026-10-16 复审）：紧凑标签碰撞时（同 agent/
    /// session 尾段/branch），fork 展示标识仍必须可区分——摘要位由
    /// 完整 storageKey 决定。同时钉稳定性：同键同标识。
    func testForkProvenanceLabelsDistinctUnderLabelCollision() {
        let first = "default/s-aaaa111111/main"
        let second = "default/s-bbbb111111/main"
        XCTAssertEqual(
            EngineExecutionStateSnapshot.compactLabel(mapKey: first),
            EngineExecutionStateSnapshot.compactLabel(mapKey: second),
            "用例构造前提：两键紧凑标签必须相同（碰撞场景）")
        XCTAssertNotEqual(
            EngineExecutionStateSnapshot.forkProvenanceLabel(storageKey: first),
            EngineExecutionStateSnapshot.forkProvenanceLabel(storageKey: second),
            "完整键不同的 fork 展示标识必须可区分")
        XCTAssertEqual(
            EngineExecutionStateSnapshot.forkProvenanceLabel(storageKey: first),
            EngineExecutionStateSnapshot.forkProvenanceLabel(storageKey: first),
            "同键标识必须稳定")
        XCTAssertTrue(
            EngineExecutionStateSnapshot.forkProvenanceLabel(storageKey: first)
                .hasSuffix("~" + EngineExecutionStateSnapshot.digestSuffix(first)),
            "展示标识 = 紧凑标签 + 摘要后缀的组成形态")
    }

    /// F4 收紧（2026-10-16 外审）：身份直映射必须钉住**生产调用路径**。
    /// execute → generate 的身份透传经 lineage 可观察（admission 失败也
    /// 是 failed execution，记录原始三元组）——协议面若误传/换序字段，
    /// 此处即红。免重构：不需要为测试开新接缝。
    func testExecuteIdentityPassthroughPinnedByLineage() async {
        let runtime = freshRuntime()
        let id = ExecutionID(agentId: "agent-pin", sessionId: "es-pin", logicalBranchId: "bp")
        do {
            _ = try await runtime.execute(ExecutionRequest(
                requestId: "pin-exec", identity: id,
                messages: [.object(["role": .string("user"),
                                    "content": .string("x")])],
                config: ModelConfig()))
            XCTFail("未加载模型时 execute 应抛错")
        } catch {
            // 预期：notLoaded
        }
        let records = runtime.lineage.snapshot.records
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.requestId, "pin-exec")
        XCTAssertEqual(records.first?.agentId, id.agentId)
        XCTAssertEqual(records.first?.sessionId, id.sessionId)
        XCTAssertEqual(records.first?.logicalBranchId, id.logicalBranchId)
        XCTAssertEqual(records.first?.status, .failed)
    }

    /// 投影只读性（2026-10-16 收敛补）：未加载模型的 runtime 投影必须
    /// 可得且零副作用——不抛错、不改变 isGenerating/isRunning。
    func testExecutionStateSnapshotWithoutModel() {
        let runtime = freshRuntime()
        let snapshot = runtime.executionStateSnapshot()
        XCTAssertFalse(snapshot.isRunning)
        XCTAssertTrue(snapshot.sessions.isEmpty)
        XCTAssertTrue(snapshot.lineageRecords.isEmpty)
        XCTAssertTrue(snapshot.forks.isEmpty)
        XCTAssertEqual(snapshot.pendingRequests, 0)
        XCTAssertEqual(snapshot.activeGenerations, 0)
    }
}

/// S4 P2-1 收紧（外审九轮）：异步路径的"底层错误透传证明"必须断言
/// 精确错误类型——任意 error 即过无法区分委托透传与实现错误。
func XCTAssertThrowsNotLoadedAsync(
    _ expression: @autoclosure () async throws -> some Any
) async {
    do {
        _ = try await expression()
        XCTFail("预期抛 RuntError.notLoaded，实际成功返回")
    } catch let error as RuntError {
        if case .notLoaded = error {
            // 预期
        } else {
            XCTFail("意外 RuntError: \(error)")
        }
    } catch {
        XCTFail("意外错误类型: \(error)")
    }
}
