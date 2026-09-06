import XCTest
import MLXLMCommon
@testable import SimiGo

/// KV 选源契约测试（审计 2026-09-06 P1-2 回归）。
/// selectKVSourceLocked 锚定铁律 42/43/7 与架构指引 §2.1 双 Key 不变量：
/// 全局池按最长前缀复用（铁律 42），但只有**同 owner（storageKey）同分支**的源
/// 才允许在深拷贝取代后无损释放物理层（铁律 45/88）；跨会话同名分支源必须保留，
/// 否则 LAN 多用户（默认分支同为 "main"）会发生跨会话驱逐乒乓。
final class KVSourceSelectionTests: XCTestCase {
    private let toolFP = "fp-test"

    private func makeRevision(
        id: String,
        owner: String,
        branch: String,
        tokens: [Int],
        resident: Bool,
        fingerprint: String = "fp-test",
        lastActive: Date = Date()
    ) -> PhysicalKVRevision {
        PhysicalKVRevision(
            id: id,
            ownerStorageKey: owner,
            logicalBranchId: branch,
            toolFingerprint: fingerprint,
            physicalTokens: tokens,
            kvCache: resident ? [KVCacheSimple()] : [],
            lastActive: lastActive
        )
    }

    // MARK: - 归属裁决（P1-2 核心）

    func testSameOwnerSameBranchSourceIsMarkedForRelease() {
        var revisions = [
            makeRevision(
                id: "rev-a",
                owner: "agent/s1",
                branch: "main",
                tokens: [1, 2, 3, 4],
                resident: true
            )
        ]

        let selection = NativeMLX.selectKVSourceLocked(
            revisions: &revisions,
            promptTokens: [1, 2, 3, 4, 5],
            toolFingerprint: toolFP,
            targetStorageKey: "agent/s1",
            targetBranchId: "main"
        )

        XCTAssertEqual(selection.trimReleases.count, 1, "同 owner 同分支源被深拷贝取代后应标记释放")
        XCTAssertEqual(selection.trimReleases.first?.id, "rev-a")
        XCTAssertTrue(revisions[0].kvCache.isEmpty, "物理层应被清空（resident → false）")
        XCTAssertFalse(revisions[0].resident)
        XCTAssertEqual(
            revisions[0].physicalTokens,
            [1, 2, 3, 4],
            "账本必须保留（Lossless Eviction，铁律 45/88）"
        )
    }

    func testCrossSessionSameBranchNameSourceIsPreserved() {
        // P1-2 回归：会话 s2 命中会话 s1 的 "main" 分支 revision——
        // 不得因分支同名而释放对端链路仍需要的物理层（794f943 曾误释放）。
        var revisions = [
            makeRevision(
                id: "rev-s1",
                owner: "agent/s1",
                branch: "main",
                tokens: [1, 2, 3, 4],
                resident: true
            )
        ]

        let selection = NativeMLX.selectKVSourceLocked(
            revisions: &revisions,
            promptTokens: [1, 2, 3, 4, 9],
            toolFingerprint: toolFP,
            targetStorageKey: "agent/s2",
            targetBranchId: "main"
        )

        XCTAssertEqual(selection.commonLen, 4, "全局池最长前缀必须正常命中（铁律 42）")
        XCTAssertTrue(selection.trimReleases.isEmpty, "跨会话同名分支源不得释放")
        XCTAssertFalse(revisions[0].kvCache.isEmpty, "源 revision 必须保持 resident")
        XCTAssertNotNil(selection.cachesForReuse, "副本照常供本轮复用")
    }

    func testCrossOwnerExactTokenMatchIsStillPreserved() {
        // 与对端 revision 内容完全一致时也不释放：内容相同 ≠ 归属相同，
        // 对端下一轮仍依赖自己的 resident 物理层（否则退化为 Cold Prefill）。
        var revisions = [
            makeRevision(
                id: "rev-s1",
                owner: "agent/s1",
                branch: "main",
                tokens: [1, 2, 3],
                resident: true
            )
        ]

        let selection = NativeMLX.selectKVSourceLocked(
            revisions: &revisions,
            promptTokens: [1, 2, 3],
            toolFingerprint: toolFP,
            targetStorageKey: "agent/s2",
            targetBranchId: "main"
        )

        XCTAssertTrue(selection.trimReleases.isEmpty)
        XCTAssertFalse(revisions[0].kvCache.isEmpty)
    }

    // MARK: - 选择语义（铁律 42/43/7）

    func testLongestPrefixWins() {
        // 双源均驻留且都非本轮 owner：选中者不被重置、不触发释放
        var revisions = [
            makeRevision(id: "short", owner: "a/s1", branch: "b", tokens: [1, 2, 3], resident: true),
            makeRevision(id: "long", owner: "a/s2", branch: "b", tokens: [1, 2, 3, 4, 5], resident: true),
        ]

        let selection = NativeMLX.selectKVSourceLocked(
            revisions: &revisions,
            promptTokens: [1, 2, 3, 4, 9],
            toolFingerprint: toolFP,
            targetStorageKey: "a/s3",
            targetBranchId: "b"
        )

        XCTAssertEqual(selection.branch?.id, "long")
        XCTAssertEqual(selection.commonLen, 4)
        XCTAssertEqual(selection.rawCommonLen, 4)
        XCTAssertTrue(selection.trimReleases.isEmpty, "非本轮 owner 的胜者不得释放")
        for revision in revisions {
            XCTAssertFalse(revision.kvCache.isEmpty, "两个源都保持 resident")
        }
    }

    func testTieBreakPrefersRecentLastActive() {
        let older = makeRevision(
            id: "older",
            owner: "a/s1",
            branch: "b",
            tokens: [1, 2, 3],
            resident: true,
            lastActive: Date(timeIntervalSinceNow: -100)
        )
        let newer = makeRevision(
            id: "newer",
            owner: "a/s2",
            branch: "b",
            tokens: [1, 2, 3],
            resident: true,
            lastActive: Date()
        )

        var revisions = [older, newer]

        let selection = NativeMLX.selectKVSourceLocked(
            revisions: &revisions,
            promptTokens: [1, 2, 3],
            toolFingerprint: toolFP,
            targetStorageKey: "a/s3",
            targetBranchId: "b"
        )

        XCTAssertEqual(selection.branch?.id, "newer", "同长破平按 lastActive 新者优先")
        XCTAssertTrue(selection.trimReleases.isEmpty, "破平落选者与胜者都不是本轮 owner，均不得释放")
    }

    func testToolFingerprintMismatchFiltersCandidate() {
        var revisions = [
            makeRevision(
                id: "mismatch",
                owner: "agent/s1",
                branch: "main",
                tokens: [1, 2, 3],
                resident: true,
                fingerprint: "other-fp"
            )
        ]

        let selection = NativeMLX.selectKVSourceLocked(
            revisions: &revisions,
            promptTokens: [1, 2, 3],
            toolFingerprint: toolFP,
            targetStorageKey: "agent/s1",
            targetBranchId: "main"
        )

        XCTAssertNil(selection.branch, "指纹不匹配的 revision 不得成为复用源（铁律 43）")
        XCTAssertTrue(selection.sawToolFingerprintMismatch)
        XCTAssertEqual(selection.commonLen, 0)
        XCTAssertNil(selection.cachesForReuse, "指纹不匹配不得产生副本（降级 Cold）")
        XCTAssertTrue(selection.trimReleases.isEmpty, "过滤 ≠ 释放：语义不兼容只影响本轮选择")
    }

    func testEvictedSourceResetsCommonLen() {
        var revisions = [
            makeRevision(
                id: "evicted",
                owner: "agent/s1",
                branch: "main",
                tokens: [1, 2, 3, 4],
                resident: false
            )
        ]

        let selection = NativeMLX.selectKVSourceLocked(
            revisions: &revisions,
            promptTokens: [1, 2, 3, 4, 5],
            toolFingerprint: toolFP,
            targetStorageKey: "agent/s1",
            targetBranchId: "main"
        )

        XCTAssertNotNil(selection.branch, "命中但非驻留的 revision 应被识别")
        XCTAssertEqual(selection.commonLen, 0, "非驻留源必须重置复用长度，降级 Cold Prefill（铁律 8）")
        XCTAssertNil(selection.cachesForReuse)
        XCTAssertEqual(selection.sawUsableBranch, true)
    }

    // MARK: - 平凡前缀（审计 P2：单 token 前缀不复用）

    func testSingleTokenPrefixIsNotReused() {
        // 仅共享 1 个 token：复用收益趋零且 exact-match 场景会丢弃整个副本，
        // 选源必须直接拒绝，降级 Cold（KVM why=noCommonPrefix）
        var revisions = [
            makeRevision(
                id: "trivial",
                owner: "agent/s1",
                branch: "main",
                tokens: [7, 1, 2],
                resident: true
            )
        ]

        let selection = NativeMLX.selectKVSourceLocked(
            revisions: &revisions,
            promptTokens: [7, 9, 9],
            toolFingerprint: toolFP,
            targetStorageKey: "agent/s1",
            targetBranchId: "main"
        )

        XCTAssertNil(selection.branch, "单 token 公共前缀不得成为复用源")
        XCTAssertEqual(selection.commonLen, 0)
        XCTAssertNil(selection.cachesForReuse)
        XCTAssertTrue(selection.trimReleases.isEmpty, "拒绝复用 ≠ 释放：源保持原状")
        XCTAssertFalse(revisions[0].kvCache.isEmpty)
        XCTAssertEqual(selection.sawUsableBranch, true)
    }

    func testTwoTokenPrefixStillReused() {
        // 边界：恰好 2 个 token 公共前缀仍走复用路径
        var revisions = [
            makeRevision(
                id: "minimal",
                owner: "agent/s1",
                branch: "main",
                tokens: [7, 8],
                resident: true
            )
        ]

        let selection = NativeMLX.selectKVSourceLocked(
            revisions: &revisions,
            promptTokens: [7, 8, 9],
            toolFingerprint: toolFP,
            targetStorageKey: "agent/s1",
            targetBranchId: "main"
        )

        XCTAssertEqual(selection.branch?.id, "minimal")
        XCTAssertEqual(selection.commonLen, 2)
        XCTAssertNotNil(selection.cachesForReuse)
    }
}
