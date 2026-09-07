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

    func testRuntimeTracePolicyKeepsActionableEvents() {
        let retained = [
            "[ADMISSION BLOCK] projected=9000M limit=8500M action=reject",
            "[REQ ERROR] error=test",
            "[REQ CANCEL] why=cancelled",
            "[TOOL FORWARD] name=foo action=stop",
            "[TPFAIL] error=malformed",
            "[KVC REJECT] why=ledger_kv_mismatch",
            "[DEGEN-BLOCK] action=circuit_break",
            "[PERF] tok=32 dur=1.2s",
            "[LIFECYCLE] resume_done elapsed=1.0s"
        ]

        for message in retained {
            XCTAssertTrue(
                RuntimeTracePolicy.shouldPersist(message),
                "关键运行事件不得被默认日志策略过滤: \(message)"
            )
        }
    }

    func testRuntimeTracePolicyDropsHotPathNoise() {
        let dropped = [
            "[REQ] request=req-123",
            "[GATE] request=req-123 wait=0.3ms",
            "[KVD] br=main why=noCommonPrefix",
            "[KVS] br=main cp=181",
            "[KCP] src=G rev=abc cache=200",
            "[KVR] src=G cp=181 hit=82.3%",
            "[KVM] why=noGlobalRevision",
            "[COLD] p=1024",
            "[PWAIT] request=req-123 wait=1.2ms",
            "[TDUP] request=req-123 act=dup",
            "[DEG] br=main round=2 rep=1 cand=1 fwd=1 kv=1"
        ]

        for message in dropped {
            XCTAssertFalse(
                RuntimeTracePolicy.shouldPersist(message),
                "热路径噪声不应进入默认日志: \(message)"
            )
        }
    }

    func testRuntimeTracePolicyDoesNotRewriteSemanticFields() {
        let message = "[PERF] r=abc123 ttft=0.300s pre=900.0/s d=5.2/s tok=150 dur=28.87s"
        XCTAssertEqual(
            RuntimeTracePolicy.compactTag(message),
            message,
            "已是紧凑格式的性能日志不得再做昂贵的全字符串重写"
        )
    }
}
