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
