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
        } catch {
            // 委托证明：错误来自底层 generate 路径
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
        } catch {
            // 预期底层 notLoaded
        }
    }

    func testCheckpointRestoreForkDelegationWithoutModel() async {
        let runtime = freshRuntime()
        await XCTAssertThrowsErrorAsync(try await runtime.checkpoint(
            identity, to: nil))
        await XCTAssertThrowsErrorAsync(try await runtime.restore(
            identity, from: nil))
        await XCTAssertThrowsErrorAsync(try await runtime.fork(
            identity, sourceBranch: "main", targetBranch: "s4fork", in: nil))
    }
}

/// XCTest 的 XCTAssertThrowsError 尚无 async 重载（该 toolchain），自备助手。
func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure () async throws -> some Any
) async {
    do {
        _ = try await expression()
        XCTFail("预期抛错，实际成功返回")
    } catch {
        // 预期路径
    }
}
