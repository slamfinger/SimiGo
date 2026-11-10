import XCTest
@testable import SimiGo

/// 2026-11-10 实测的缺口：llama.cpp 启动失败（`❌ llama.cpp 异常退出 (Exit Code: 6)`
/// → `❌ 启动失败: 服务启动超时`）之后，端口 8000 上再无监听者——`/mcp` 整个消失，
/// 直到 App 重启才回来。
///
/// 原因不是"模型没起来"，而是 `internalStart` 一进门就 `stop()` 掉了信息空间宿主
/// （模型要独占那个端口），失败路径却没有把它放回去。模型缺席时 `/mcp` 与 IS 读写
/// 接口本该继续可用——`stopModelService()` 就是这么做的。
final class ServiceHostFallbackTests: XCTestCase {

    /// 覆盖"最先撞上的那条失败腿"（路径不存在）。引擎启动失败的 catch 腿走同一个
    /// 回落函数，但要让引擎真的失败得先有一份能跑的引擎或一份坏模型，不适合放进
    /// 常规套件——那条腿的证据是 15:28 的现场日志，不是这条测试。
    @MainActor
    func testFailedModelStartLeavesTheInformationSpaceHostServing() async throws {
        let service = Service.shared
        let port = Int(try GGUFRestFixture.freePort())
        service.configureLocalNode(port: port)
        addTeardownBlock { @MainActor in await service.stop() }

        await service.startInformationSpaceService()
        XCTAssertEqual(
            service.hostMode, .informationSpace,
            "precondition: the information-space host owns the port")
        try GGUFRestFixture.waitUntilListening(port: port)

        await service.start(path: "/tmp/absent-\(UUID().uuidString).gguf")

        XCTAssertEqual(
            service.hostMode, .informationSpace,
            "a failed model start must leave the host on port \(port), not an empty port")
        XCTAssertNoThrow(
            try GGUFRestFixture.waitUntilListening(port: port),
            "the MCP/IS surface must survive a failed model load")
        XCTAssertTrue(
            service.status.contains("信息空间"),
            "status must still name what is actually serving; got: \(service.status)")
        XCTAssertTrue(
            service.status.contains("模型启动失败"),
            "status must keep the failure reason instead of hiding it; got: \(service.status)")
    }
}
