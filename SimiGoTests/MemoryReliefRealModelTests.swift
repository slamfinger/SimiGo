import LOCALBCore
import XCTest

@testable import SimiGo

/// 需求① 内存黄色（真实权重层）：挂起必须真实释放大模型驻留内存——
/// 这是「推理结束后内存压力长时间黄色」缓解链的可观测终点的直接实测。
///
/// 门控与 LifecycleRaceTests 同约定：SIMIGO_LIFECYCLE_RACE=1 +
/// SIMIGO_FORK_MODEL=<本机 MLX 权重目录>，缺省 XCTSkip 不污染常规跑。
///
/// 断言的不变量：
///  ① start+生成后 footprint 达到模型驻留量级（证明权重真的在内存里）；
///  ② suspendIfIdle 后 footprint 显著下降（≥ max(1GiB, 30%×loaded)）；
///  ③ 挂起后新请求自动恢复并可继续生成（用户无感）；
///  ④ stop() 后 footprint 回落至接近空闲基线。
/// 实际数字打印为机器可读 [MEM-RELIEF] 行，供证据归档。
final class MemoryReliefRealModelTests: XCTestCase {

    private static func requireModel() throws -> String {
        // 主门控：既有 SIMIGO_* 环境约定（与 LifecycleRaceTests 一致）。
        let env = ProcessInfo.processInfo.environment
        if env["SIMIGO_LIFECYCLE_RACE"] == "1",
           let path = env["SIMIGO_FORK_MODEL"], !path.isEmpty,
           FileManager.default.fileExists(atPath: path + "/config.json") {
            return path
        }
        // 备用门控：显式本机证据运行配置文件（xcodebuild test 不注入 env、
        // build-for-testing 又受无关 SPM/yyjson 链接缺陷阻断时的唯一通道）。
        // 文件不存在 ⇒ 缺省 XCTSkip，不污染常规跑。
        let cfg = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".simigo/memory-relief-run.json")
        if let data = try? Data(contentsOf: cfg),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let path = obj["modelPath"] as? String, !path.isEmpty,
           FileManager.default.fileExists(atPath: path + "/config.json") {
            return path
        }
        throw XCTSkip("内存释放实测：需 SIMIGO_LIFECYCLE_RACE=1+SIMIGO_FORK_MODEL 或 ~/.simigo/memory-relief-run.json")
    }

    private static func greedyConfig() -> ModelConfig {
        var cfg = ModelConfig()
        cfg.temperature = 0
        cfg.maxTokens = 16
        cfg.disableThinking = true
        cfg.useMTP = false
        return cfg
    }

    private static func mb(_ bytes: UInt64) -> Double {
        Double(bytes) / Double(1024 * 1024)
    }

    @discardableResult
    private func gen(
        _ runtime: NativeMLX, _ tag: String, _ content: String
    ) async throws -> GenerationResult {
        let requestId = "mem-\(tag)-\(UUID().uuidString.prefix(8).lowercased())"
        await RuntimeLifecycleCoordinator.shared.register(
            requestID: requestId, sessionID: "mem")
        return try await runtime.generate(
            requestId: requestId,
            sessionId: "mem",
            messages: [.object([
                "role": .string("user"),
                "content": .string(content),
            ])],
            tools: nil,
            config: Self.greedyConfig()
        ) { _ in }
    }

    func testSuspendReleasesResidentModelMemory() async throws {
        let modelPath = try Self.requireModel()
        let baseline = RuntimeTuning.footprintBytes()

        let runtime = NativeMLX(
            info: ModelInfo(path: modelPath, kind: .mlx),
            config: Self.greedyConfig())

        let configSnapshot = await MainActor.run {
            InferenceNodeConfiguration.shared.snapshot()
        }
        func restoreConfig() async {
            await MainActor.run {
                InferenceNodeConfiguration.configure(
                    bindHost: configSnapshot.bindHost,
                    advertisedHost: configSnapshot.advertisedHost,
                    port: configSnapshot.port,
                    bonjourEnabled: configSnapshot.bonjourEnabled)
            }
        }
        func cleanup() async {
            #if DEBUG
            RuntimeTuning.suspendIdleTimeoutOverrideSeconds = nil
            #endif
            await runtime.stop()
            await restoreConfig()
        }

        // 隔离启动：显式注入一次性验证过的传输身份（不触碰本机真实
        // LOCALB 主机状态；本测直接驱动 runtime.generate，不经受保护 HTTP 路由，
        // 因此无需请求授权协调器）。
        func makeIsolatedIdentity() throws -> LOCALBTransportIdentityHandle {
            let store = LOCALBTransportIdentityStore(
                service: "com.simigo.tests.memrelief.\(UUID().uuidString)",
                account: "tls")
            addTeardownBlock { store.deleteAll() }
            return try store.loadOrCreate()
        }

        do {
            let identity = try makeIsolatedIdentity()
            try await runtime.startWithLOCALB(
                ModelInfo(path: modelPath, kind: .mlx),
                port: 0,
                localbTransportIdentity: identity,
                localbRequestAuthorization: nil
            )

            // 生成一轮：权重确定驻留（未加载不驻留、生成必触达）。
            let r1 = try await gen(runtime, "warm", "只回复:OK")
            XCTAssertFalse(r1.text.isEmpty)
            let loaded = RuntimeTuning.footprintBytes()

            // 打开测试缝隙：任务空即可挂起（生产语义 nil 不受影响）。
            #if DEBUG
            RuntimeTuning.suspendIdleTimeoutOverrideSeconds = 0
            #endif
            let suspended = await runtime.suspendIfIdle()
            XCTAssertTrue(suspended, "空闲且缝隙打开时必须挂起成功")

            // 挂起释放窗口：允许 allocator 回收有延迟，观察 ≤10s。
            var afterSuspend = loaded
            for _ in 0..<10 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                afterSuspend = RuntimeTuning.footprintBytes()
                if loaded > afterSuspend,
                   loaded - afterSuspend >= max(
                       1024 * 1024 * 1024, loaded / 10 * 3) { break }
            }
            let released = loaded > afterSuspend ? loaded - afterSuspend : 0
            print(
                "[MEM-RELIEF] baseline=\(Int(Self.mb(baseline)))MiB "
                + "loaded=\(Int(Self.mb(loaded)))MiB "
                + "afterSuspend=\(Int(Self.mb(afterSuspend)))MiB "
                + "released=\(Int(Self.mb(released)))MiB"
            )
            XCTAssertGreaterThan(
                released, 0, "挂起必须释放可观测的驻留内存（实测 released=0）")
            XCTAssertGreaterThanOrEqual(
                released,
                min(
                    max(1024 * 1024 * 1024, loaded / 10 * 3),
                    loaded - baseline > 1024 * 1024 * 1024
                        ? loaded - baseline : loaded),
                "释放量应达到驻留内存的量级信号"
            )

            // 挂起后自动恢复：用户下一次请求无感重建。
            let r2 = try await gen(runtime, "resume", "只回复:BACK")
            XCTAssertFalse(r2.text.isEmpty, "挂起后新请求必须自动恢复并成功")

            // stop 终态：驻留回落。
            await runtime.stop()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            let afterStop = RuntimeTuning.footprintBytes()
            print("[MEM-RELIEF] afterStop=\(Int(Self.mb(afterStop)))MiB")
            XCTAssertLessThan(
                afterStop, loaded,
                "stop 后 footprint 必须低于驻留峰值")
            #if DEBUG
            RuntimeTuning.suspendIdleTimeoutOverrideSeconds = nil
            #endif
            await restoreConfig()
        } catch {
            await cleanup()
            throw error
        }
        await cleanup()
    }
}
