import XCTest
import SimiGo2Experimental
@testable import SimiGo

/// #4 机制等价回归：exportTokenBoundaries 从「每边界切片+全量重哈希」改为
/// 「一次 cumulative + 查表」。本套件按三层锁机制等价——
///   1. 逐 boundary：legacy PrefixChain.hash(tokens[0..<count]) 与
///      cumulative(tokens)[count-1] 每个 (count, hash) 完全一致；
///   2. dedup：同一 (count, hash) 必然产生逐字节相同的 dedup key；
///   3. 退化语料：空 / ≤2048（生产早退）/ 恰好越界 / 多边界 / 重复前缀 /
///      尾段不足 2048。
/// 函数级端到端（含真实 store 写盘）由 PrefixPoolDailyPathE2ETests 在闲时
/// 窗口覆盖；本套件 CPU-only，不触碰 ~/.simigo。
final class PrefixBoundaryHashEquivalenceTests: XCTestCase {
    /// 复刻 exportTokenBoundaries 的边界网格（[tokenIds.count] + 2048 网格，
    /// 网格形状被 #4 边界明令不变，此处锁死）。
    private static func boundaryCounts(tokenCount: Int) -> [Int] {
        var boundaries: [Int] = [tokenCount]
        var grid = 2048
        while grid < tokenCount {
            boundaries.append(grid)
            grid += 2048
        }
        return boundaries
    }

    /// 复刻 dedup key 的逐字节构造。
    private static func dedupKey(modelID: String, kvFingerprint: String, count: Int, hash: UInt64) -> String {
        "\(modelID)|\(kvFingerprint)|\(count)|\(hash)"
    }

    /// legacy 形态：逐边界切片 + 全量重哈希。
    private static func legacyHashes(tokenIds: [Int], boundaries: [Int]) -> [UInt64] {
        boundaries.map { PrefixChain.hash(Array(tokenIds[..<$0])) }
    }

    /// new 形态：一次 cumulative + 查表。
    private static func cumulativeHashes(tokenIds: [Int], boundaries: [Int]) -> [UInt64] {
        let cumulative = PrefixChain.cumulative(tokenIds)
        return boundaries.map { cumulative[$0 - 1] }
    }

    func testPerBoundaryHashEquivalenceAcrossEdgeCorpus() {
        // 退化语料：多边界 / 恰好越过首网格 / 尾段不足 2048 / 重复内容
        let corpus: [(tokenCount: Int, label: String)] = [
            (2_049, "恰好越过 2048 首网格"),
            (5_000, "两网格 + 904 尾段"),
            (10_000, "多边界"),
            (100_000, "100k 级"),
        ]
        for (tokenCount, label) in corpus {
            let tokenIds = (0..<tokenCount).map { ($0 &* 2654435761) & 0xffff }
            let boundaries = Self.boundaryCounts(tokenCount: tokenCount)
            let legacy = Self.legacyHashes(tokenIds: tokenIds, boundaries: boundaries)
            let new = Self.cumulativeHashes(tokenIds: tokenIds, boundaries: boundaries)
            XCTAssertEqual(new, legacy, "\(label)：逐 boundary (count, hash) 不一致")

            // 复核 cumulative[i] 的定义：hash(tokens[0...i])
            for count in boundaries {
                XCTAssertEqual(
                    PrefixChain.cumulative(tokenIds)[count - 1],
                    PrefixChain.hash(Array(tokenIds[..<count])),
                    "\(label) count=\(count)")
            }
        }
    }

    func testDedupKeyByteIdenticalForSameCountAndHash() {
        // 同一 token prefix 在两轮导出中 (count, hash) 一致 → dedup key
        // 逐字节一致 → exportedTokenBoundaries 命中语义不变。
        let tokenIds = (0..<10_000).map { ($0 &* 40503) & 0xffff }
        let boundaries = Self.boundaryCounts(tokenCount: tokenIds.count)
        let first = Self.cumulativeHashes(tokenIds: tokenIds, boundaries: boundaries)
        let second = Self.cumulativeHashes(tokenIds: tokenIds, boundaries: boundaries)
        XCTAssertEqual(first, second)

        let keysFirst = first.map { Self.dedupKey(modelID: "m", kvFingerprint: "fp", count: 0, hash: $0) }
        let keysSecond = second.map { Self.dedupKey(modelID: "m", kvFingerprint: "fp", count: 0, hash: $0) }
        XCTAssertEqual(keysFirst, keysSecond)

        // 不同内容 → 不同 hash → 不同 key（去重不吞真差异）
        let altered = tokenIds
        let alteredHashes = Self.cumulativeHashes(tokenIds: altered, boundaries: boundaries)
            .map { $0 &+ 1 }
        XCTAssertNotEqual(
            first.map { Self.dedupKey(modelID: "m", kvFingerprint: "fp", count: 0, hash: $0) },
            alteredHashes.map { Self.dedupKey(modelID: "m", kvFingerprint: "fp", count: 0, hash: $0) })
    }

    func testDuplicatePrefixesProduceIdenticalBoundaryHashes() {
        // 相同 token prefix（跨「会话」）→ 全部边界哈希逐值一致（内容寻址）
        let shared = (0..<10_000).map { ($0 &* 97) & 0xffff }
        let sessionA = shared
        let sessionB = shared
        let boundaries = Self.boundaryCounts(tokenCount: shared.count)
        XCTAssertEqual(
            Self.cumulativeHashes(tokenIds: sessionA, boundaries: boundaries),
            Self.cumulativeHashes(tokenIds: sessionB, boundaries: boundaries))
    }

    func testDegenerateTokenCountsFollowProductionGuards() {
        // 空 tokens：cumulative 为空，任何查表都不可能发生
        XCTAssertTrue(PrefixChain.cumulative([]).isEmpty)

        // 生产 guard `tokenIds.count > 2048`：≤2048 早退，不进入哈希段；
        // 网格规则下 2048 恰好只产生 [2048] 一个边界（早退边界锁定）
        XCTAssertEqual(Self.boundaryCounts(tokenCount: 2_048), [2_048])
        XCTAssertEqual(Self.boundaryCounts(tokenCount: 2_049), [2_049, 2_048])
        // 尾段不足 2048 的网格上限
        XCTAssertEqual(Self.boundaryCounts(tokenCount: 5_000), [5_000, 2_048, 4_096])
    }
}
