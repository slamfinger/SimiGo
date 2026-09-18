import XCTest
@testable import SimiGo

/// S3 验收（外审七轮 P1 关注点）：ConditionalRestoreConfiguration
/// 默认值与 v1.5 生产现值等价、A/B 开关路径与旧语义逐路径一致、
/// 快照一次性冻结（RuntimeTuning 变更不影响已构造快照）。
final class ExecutionPolicyGateTests: XCTestCase {
    private func config(
        legacy: Bool = false, conditional: Bool = true, limit: Int = 8192
    ) -> ExecutionPolicy.ConditionalRestoreConfiguration {
        .init(legacyRollforwardEnabled: legacy,
              conditionalRestoreEnabled: conditional,
              restoreDeltaLimitTokens: limit)
    }

    private func toolMessage(_ chars: Int) -> [SimiGo.JSONValue] {
        [.object(["role": .string("tool"),
                  "content": .string(String(repeating: "x", count: chars))])]
    }

    func testDefaultConfigurationMatchesV15ProductionValues() {
        let c = ExecutionPolicy.ConditionalRestoreConfiguration()
        XCTAssertFalse(c.legacyRollforwardEnabled)
        XCTAssertTrue(c.conditionalRestoreEnabled)
        XCTAssertEqual(c.restoreDeltaLimitTokens, 8192)
    }

    func testGatePathEquivalenceWithLegacyFlags() {
        // 旧 rf 开 → 无条件放行（连 skipDisabled 都不出现）
        XCTAssertEqual(ExecutionPolicy.conditionalRestoreGate(
            configuration: config(legacy: true, conditional: false),
            incoming: [], ledgerCount: 0), .allowed)
        // 都关 → skipDisabled（纯 extend）
        XCTAssertEqual(ExecutionPolicy.conditionalRestoreGate(
            configuration: config(legacy: false, conditional: false),
            incoming: [], ledgerCount: 0), .skipDisabled)
        // conditional 开 + 小 delta（400 字符 ≈107 tok）→ 放行
        XCTAssertEqual(ExecutionPolicy.conditionalRestoreGate(
            configuration: config(),
            incoming: toolMessage(400), ledgerCount: 0), .allowed)
        // conditional 开 + 大 delta（40k 字符 ≈10k tok > 8192）→ 拒且带回估算
        if case .skipDeltaTooLarge(let estimate) = ExecutionPolicy.conditionalRestoreGate(
            configuration: config(), incoming: toolMessage(40_000), ledgerCount: 0) {
            XCTAssertGreaterThan(estimate, 8192)
        } else {
            XCTFail("expected skipDeltaTooLarge")
        }
    }

    func testSnapshotIsolationFromRuntimeTuningMutation() {
        // 快照一次性冻结：构造后变更 RuntimeTuning，已冻结配置不受影响
        RuntimeTuning.conditionalRestoreMaxDeltaTokens = 1
        defer { RuntimeTuning.conditionalRestoreMaxDeltaTokens = 8192 }
        let frozen = ExecutionPolicy.ConditionalRestoreConfiguration.current()
        XCTAssertEqual(frozen.restoreDeltaLimitTokens, 1)
        RuntimeTuning.conditionalRestoreMaxDeltaTokens = 8192
        // frozen 仍持 limit=1：小 delta 估算 >1 → 拒（若读活值则应为 allowed）
        if case .skipDeltaTooLarge = ExecutionPolicy.conditionalRestoreGate(
            configuration: frozen,
            incoming: toolMessage(400), ledgerCount: 0) {
        } else {
            XCTFail("frozen 快照应保持 limit=1，不受活值恢复影响")
        }
        // 活值路径：同输入走 current()（已恢复 8192）→ allowed
        XCTAssertEqual(ExecutionPolicy.conditionalRestoreGate(
            configuration: .current(),
            incoming: toolMessage(400), ledgerCount: 0), .allowed)
    }
}
