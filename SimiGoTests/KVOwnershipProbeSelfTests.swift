import Foundation
import MLX
import MLXLMCommon
import XCTest

/// 所有权探针的自检：**先证明仪器不空转，再用它测真实模型**。
///
/// 这个文件只用几 KB 的数组，不开模型。它回答三件事：
///
///   ① `sameOwner` 认的是控制块，不是裸地址：视图与本体共享 owner，独立分配不共享。
///   ② `isAlive` 会真的过期：数组是作用域里唯一强引用的时后，观察句柄随后读到 false；
///      反过来，如果探针自己持有强引用，这条断言就会失败 —— 这正是本文件要防的
///      自欺（用仪器把被测对象撑住，再报告“没有释放”）。
///   ③ 快照逐一覆盖全部数组、按 `(tag, path, role)` 配对，且不遗漏任何一条记录。
final class KVOwnershipProbeSelfTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - 控制块语义

    func testViewSharesOwnerAndIndependentAllocationDoesNot() {
        let base = MLXArray((0 ..< 256).map { Float($0) }).reshaped([16, 16])
        base.eval()

        // 同一块存储的两种写法：`[.ellipsis]` 是切片表达式，不复制字节。
        let view = base[.ellipsis]
        view.eval()

        XCTAssertTrue(
            StorageOwnership.sameOwner(base, view),
            "视图与本体应当共享同一个 Data owner —— 否则 sameOwner 会把“共享”读成“分离”")
        XCTAssertEqual(
            StorageOwnership.identity(of: base), StorageOwnership.identity(of: view),
            "视图与本体应当指向同一个 Data 对象")

        // 一次真实分配：新数组有自己的 buffer 与自己的 Data。
        let independent = base + MLXArray([Float](repeating: 0, count: 256)).reshaped([16, 16])
        independent.eval()
        XCTAssertFalse(
            StorageOwnership.sameOwner(base, independent),
            "独立分配被读成共享 owner —— 探针无法区分“视图”与“真拷贝”")

        // 值相同不等于 owner 相同：这是本探针与 value digest 的分工。
        let again = MLXArray((0 ..< 256).map { Float($0) }).reshaped([16, 16])
        again.eval()
        XCTAssertEqual(base.asArray(Float.self), again.asArray(Float.self))
        XCTAssertFalse(
            StorageOwnership.sameOwner(base, again),
            "两份内容相同但独立分配的数组被读成共享 owner")
    }

    // MARK: - 非持有与过期

    /// 关键负向对照：观察句柄绝不能延长 `Data` 的寿命。
    func testObserverDoesNotKeepStorageAlive() {
        func observeTransient() -> MLXStorageObserver? {
            let array = MLXArray((0 ..< 1024).map { Float($0) })
            array.eval()
            return StorageOwnership.observe(array)
        }

        guard let observer = observeTransient() else {
            return XCTFail("无法观察一个已求值的数组")
        }
        XCTAssertFalse(
            observer.isAlive,
            "数组离开作用域后 owner 仍然存活 —— 观察句柄持有强引用，这个仪器会阻止它要测的释放")
        XCTAssertEqual(observer.strongCount, -1, "过期之后的强引用计数应当是 -1")

        // 同一个作用域内观察到的 owner，在数组存活期间必须是活的。
        let live = MLXArray((0 ..< 1024).map { Float($0) })
        live.eval()
        guard let liveObserver = StorageOwnership.observe(live) else {
            return XCTFail("无法观察一个已求值的数组")
        }
        XCTAssertTrue(liveObserver.isAlive, "数组仍被强引用时 owner 报告已过期")
        XCTAssertGreaterThanOrEqual(liveObserver.strongCount, 1)
        XCTAssertTrue(
            liveObserver.sharesOwner(with: liveObserver), "一个观察句柄应当与自身共享 owner")

        liveObserver.release()
        XCTAssertFalse(liveObserver.isAlive, "release() 之后观察句柄仍然报告存活")
    }

    // MARK: - 快照覆盖与配对

    func testSnapshotCoversEveryArrayAndPairsByKey() {
        let first = MLXArray((0 ..< 128).map { Float($0) })
        let second = first[.ellipsis]
        second.eval()
        let third = first + MLXArray([Float](repeating: 1, count: 128))
        third.eval()

        let snapshot = KVOwnershipProbe.snapshot([first, second, third])
        XCTAssertEqual(snapshot.entries.count, 3, "快照漏掉了数组")
        XCTAssertTrue(snapshot.allAlive)
        XCTAssertEqual(snapshot.aliveKeys.count, 3)
        // first 与 second 是同一个 owner，third 是另一个：三个数组两个 owner。
        XCTAssertEqual(snapshot.liveIdentities.count, 2, "同一 owner 的视图被算成了两个 owner")
        XCTAssertTrue(snapshot.sharesOwner("raw/array[0]", "raw/array[1]") ?? false)
        XCTAssertFalse(snapshot.sharesOwner("raw/array[0]", "raw/array[2]") ?? true)

        let overlap = KVOwnershipProbe.compare(parent: snapshot, child: KVOwnershipProbe.snapshot([first, second, third]))
        XCTAssertEqual(overlap.pairs.count, 3)
        XCTAssertTrue(overlap.allShared, "同一批数组的两次快照被读成“分离”")
        XCTAssertTrue(overlap.onlyInChild.isEmpty && overlap.onlyInParent.isEmpty)
    }

    // MARK: - 证据形状

    func testSnapshotSummarySeparatesTheThreeClaims() {
        let array = MLXArray((0 ..< 64).map { Float($0) })
        array.eval()
        let snapshot = KVOwnershipProbe.snapshot([array])
        let summary = snapshot.summary()
        guard let claims = summary["claims"] as? [String: String] else {
            return XCTFail("summary 缺少 claims")
        }
        XCTAssertEqual(claims["allocation_final_reference"], "not_observed")
        XCTAssertEqual(claims["buffer_left_mlx_pool"], "not_observed")
        XCTAssertEqual(claims["physical_pages"], "not_observed")
        XCTAssertEqual(summary["alive"] as? Int, 1)

        snapshot.releaseObservers()
        XCTAssertFalse(snapshot.entries[0].isAlive)
        let after = snapshot.summary()["claims"] as? [String: String]
        XCTAssertEqual(after?["allocation_final_reference"], "observed")
        XCTAssertEqual(after?["physical_pages"], "not_observed", "物理页永远不由 owner 过期推导")
    }
}
