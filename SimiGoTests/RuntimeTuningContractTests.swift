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
}
