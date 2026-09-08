import XCTest
@testable import SimiGo

/// RuntimeTuning 常量契约：NativeMLX 的生成上限与 KV 投影都依赖这些集中值，
/// 意外改动会静默改变准入预算与生成行为（审计建议的 RuntimeTuningTests）。
/// 注：App target 默认 MainActor 隔离，故本类显式 @MainActor。
@MainActor
final class RuntimeTuningContractTests: XCTestCase {
    func testGenerationTokenLimitContract() {
        XCTAssertEqual(RuntimeTuning.maxGenerationTokens, 4096)
    }

    func testEstimatedKVBytesPerTokenContract() {
        XCTAssertEqual(
            RuntimeTuning.estimatedKVBytesPerToken,
            128 * 1024,
            "KV 字节/token 估算同时驱动 Delta KV 投影与 Physical residency 会计，改动须同步白皮书"
        )
    }

    func testAdmissionFloorDefendsAgainstZeroBudget() {
        XCTAssertGreaterThanOrEqual(
            RuntimeTuning.admissionFloorBytes,
            4 * 1024 * 1024 * 1024,
            "准入下限防御不得低于 4GB"
        )
    }

    func testAdmissionHardCeilingRemainsIndependent() {
        XCTAssertEqual(
            RuntimeTuning.admissionMemoryLimitBytes,
            22 * RuntimeTuning.gibibyte,
            "实验性 soft allowance 不得直接改变 22GiB hard ceiling"
        )
        XCTAssertEqual(
            RuntimeTuning.admissionSoftAllowanceBytes,
            2 * UInt64(RuntimeTuning.gibibyte),
            "当前实验窗口固定为 2GiB，正式合入前须以实机压力测试重新校准"
        )
        XCTAssertEqual(
            RuntimeTuning.admissionEmergencyReserveBytes,
            UInt64(RuntimeTuning.gibibyte),
            "soft path 必须保留独立 1GiB emergency reserve"
        )
        XCTAssertLessThanOrEqual(
            RuntimeTuning.admissionSoftAllowanceBytes,
            UInt64(RuntimeTuning.admissionMemoryLimitBytes),
            "soft allowance 不能大于 hard ceiling"
        )
    }
}
