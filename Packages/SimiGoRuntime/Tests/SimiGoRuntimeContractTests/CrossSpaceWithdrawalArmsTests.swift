import Foundation
import SQLite3
import XCTest

@testable import SimiGoRuntimeContract

/// 跨空间撤回 · 库级四臂。
/// 预注册：ES-IS-research/docs/research/EXPERIMENT_COMPOSE_E2_LIBRARY_PREREG_V0.1_20261116.md
/// 读数与判定：同文件 §9。判据先写死再跑，**判定不进本文件的断言**。
///
/// 只问 B 臂那一格：第二个空间在**尚未重扫**时，是静默服务旧值（α）、
/// 服务旧值但账上可判陈旧（α′），还是拒绝（γ）。
///
/// **纪律：哪几臂断言、哪几臂只打印**
///   A（阳性对照）、D（装置检查）→ 带硬断言。它们不是被测问题，是"探针有没有效"：
///     A 不拒，说明重扫根本没播失效，B/C 的任何读数都不算数；D 非 0，说明这不是两个空间。
///   B（被测的未知格）、C → **一个断言都不带**，读数只打印成 `ARM_*` 行。
///     α 是本轮读数，不是裁定；把读数写成断言，等于把还没裁的问题当场裁掉。
///     这一点与隔壁 `ESISSourceInvalidationArmsTests`「只测量、不裁决」同族，
///     差别只在那个文件面对两套**未裁**判据、连对照臂都不断言，
///     而本文件断言的是装置有效性——装置无效时读数无意义，所以必须断言。
///
/// 四臂写在一个测试方法里，顺序即断言顺序，不写成注释：B 必须在 C 之前，
/// 且 B 期间不得对 S2 调用任何触碰根的 API。这条由语句顺序保证，是纪律不是机制。
///
/// 突变对照（证明 A 臂的断言有牙，不是从没红过的装饰）：
/// 把 `ESISDatabase.swift:6000` 的 `Array(invalidated)` 换成 `[]`（重扫照做、失效不播），
/// A 与 C 两臂当场变成 `ADMITTED`，A 臂断言见红，`invalidation_events` 全程停在 1。
/// 还原后 sha256 前后一致。读数见预注册 §9.5。
///
///     swift test --filter CrossSpaceWithdrawalArmsTests 2>&1 | grep '^ARM_'
final class CrossSpaceWithdrawalArmsTests: XCTestCase {

    private static let contract =
        #"{"schema_version":"simigo.result-contract/v1","fields":{"content":{"pattern":"^RESULT=(.+)$","capture_group":1,"type":"string","normalize":"trim","nonempty":true}},"constraints":[{"kind":"equals_binding","field":"content","binding":"next_input"}]}"#

    private let consumer = SettlementIdentityBinding.Identity(
        model: "consumer-model", tokenizer: "consumer-tokenizer")

    private func tempURL(_ name: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("simigo-xspace-\(name)-\(UUID().uuidString).sqlite3")
    }

    private func cleanup(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func open(_ name: String) throws -> (URL, ESISDatabase) {
        let url = tempURL(name)
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        return (url, db)
    }

    @discardableResult
    private func mkSettlement(_ db: ESISDatabase, stateID: String, value: String) throws -> String {
        try db.recordExecutionState(id: stateID, parentID: nil, modelIdentity: "m",
                                    position: 1, continuationID: "C", anchor: "a",
                                    lifecycle: "active", createdAt: Date())
        let settled = try SettlementAuthority.authorize(
            generatedText: "RESULT=\(value)", contractJSON: Data(Self.contract.utf8),
            verifiedBindings: ["next_input": .string(value)])
        let id = try db.recordNativeSettlement(settled, stateID: stateID)
        try db.linkSettlementToExternalFile(settlementID: id, binding: "content",
                                            rootID: "work", relativePath: "doc.txt")
        return id
    }

    /// 观测者读数：绕开被测库的 API，直接开它的 sqlite 文件看账上写了什么。
    /// 这是判 α / α′ 的证据——账上有，不等于读得出来。
    private func observe(_ url: URL, _ sql: String) -> String? {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let handle else { return nil }
        defer { sqlite3_close(handle) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) }
    }

    /// 同上，但取一列的所有行（D 臂求交集用）。
    private func observeAll(_ url: URL, _ sql: String) -> [String] {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let handle else { return [] }
        defer { sqlite3_close(handle) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return []
        }
        defer { sqlite3_finalize(stmt) }
        var rows: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "")
        }
        return rows
    }

    private func admitOutcome(_ db: ESISDatabase, _ settlementID: String) -> String {
        do {
            let admitted = try ISAdmission.admit(
                db: db, settlementID: settlementID, consumer: consumer)
            return "ADMITTED(value=\(admitted.recoveredValue))"
        } catch let refusal as ISAdmission.Refusal {
            return "REFUSED(\(refusal))"
        } catch {
            return "THREW(\(error))"
        }
    }

    private func accountDump(_ db: ESISDatabase, _ label: String) throws -> String {
        let roots = try db.listRoots().map { "\($0.rootID):\($0.status)" }.joined(separator: ",")
        let files = try db.listExternalFiles(rootID: "work")
            .map { "\($0.relativePath):\($0.status)" }.joined(separator: ",")
        return ("\(label) roots=[\(roots)] external_files=[\(files)] "
            + "settlements=\(try db.count("settlements")) "
            + "file_contents=\(try db.count("file_contents")) "
            + "dependency_edges=\(try db.count("dependency_edges")) "
            + "invalidation_events=\(try db.count("settlement_validity_events"))")
    }

    func testCrossSpaceWithdrawalArms() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("simigo-xspace-\(UUID().uuidString)")
        let root = dir.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let shared = root.resolvingSymlinksInPath()
        let doc = shared.appendingPathComponent("doc.txt")

        let (u1, s1) = try open("s1")
        let (u2, s2) = try open("s2")
        defer {
            s1.close(); s2.close(); cleanup(u1); cleanup(u2)
            try? FileManager.default.removeItem(at: dir)
        }

        // ---- 装置：一个共享根 R，两个各自独立的信息空间 S1 / S2 ----
        try Data("V1".utf8).write(to: doc)
        _ = try s1.settleWorkRootContents(rootID: "work", rootURL: shared)
        let a1 = try mkSettlement(s1, stateID: "A1", value: "v1")
        _ = try s2.settleWorkRootContents(rootID: "work", rootURL: shared)
        let a2 = try mkSettlement(s2, stateID: "A2", value: "v1")
        print("ARM_SETUP s1=\(a1) s2=\(a2) shared_root=\(shared.path)")
        print("ARM_SETUP " + (try accountDump(s1, "S1")))
        print("ARM_SETUP " + (try accountDump(s2, "S2")))

        // ---- A 臂：改源，S1 重扫。阳性对照，不拒则本轮作废 ----
        try Data("V2".utf8).write(to: doc)
        let r1 = try s1.settleWorkRootContents(rootID: "work", rootURL: shared)
        let aOutcome = admitOutcome(s1, a1)
        XCTAssertFalse(aOutcome.hasPrefix("ADMITTED"),
                       "A 臂阳性对照失败：S1 重扫后仍放行，探针是瞎的，B/C 读数不算数")
        print("ARM_A \(aOutcome) validity=\(try s1.settlementValidity(a1)) "
            + "changed=\(r1.changed) removed=\(r1.removed) "
            + "invalidatedSettlements=\(r1.invalidatedSettlements)")
        print("ARM_A " + (try accountDump(s1, "S1")))

        // ---- B 臂：本轮唯一真正的未知。此刻 S2 尚未重扫 ----
        // 从这里到 C 臂之间，不许对 s2 调用任何触碰根的 API。
        let bOutcome = admitOutcome(s2, a2)
        let bValidity = try s2.settlementValidity(a2)
        let bRootsVisible = try s2.listRoots().map { "\($0.rootID):\($0.status)" }
        let bScannedInAccount = observe(u2, "SELECT last_scanned_at FROM roots WHERE root_id='work';")
        let bDigestInAccount = observe(
            u2, "SELECT content_sha256 FROM file_contents WHERE root_id='work' AND relative_path='doc.txt';")
        print("ARM_B \(bOutcome) validity=\(bValidity) "
            + "readonly_roots_visible=\(bRootsVisible.joined(separator: ",")) "
            + "account_last_scanned_at=\(bScannedInAccount ?? "nil") "
            + "account_digest=\(bDigestInAccount?.prefix(12) ?? "nil")")
        print("ARM_B " + (try accountDump(s2, "S2")))
        // 观测者另读真相（不经 S2）：根上现在的摘要，用来判 S2 自己能不能判陈旧。
        let truthDigest = SnapshotContract.sha256Hex(try Data(contentsOf: doc))
        print("ARM_B truth_digest=\(truthDigest.prefix(12)) "
            + "account_matches_truth=\(bDigestInAccount == truthDigest)")

        // ---- C 臂：S2 重扫 ----
        let r2 = try s2.settleWorkRootContents(rootID: "work", rootURL: shared)
        let cOutcome = admitOutcome(s2, a2)
        print("ARM_C \(cOutcome) validity=\(try s2.settlementValidity(a2)) "
            + "changed=\(r2.changed) removed=\(r2.removed) "
            + "invalidatedSettlements=\(r2.invalidatedSettlements)")
        print("ARM_C " + (try accountDump(s2, "S2")))

        // ---- D 臂：装置检查。两库共享行数应为 0 ----
        let ids1 = Set(observeAll(u1, "SELECT settlement_id FROM settlements;"))
        let ids2 = Set(observeAll(u2, "SELECT settlement_id FROM settlements;"))
        let sharedRows = ids1.intersection(ids2).count
        print("ARM_D shared_settlement_rows=\(sharedRows) s1_rows=\(ids1.count) s2_rows=\(ids2.count)")
        print("ARM_D " + (try accountDump(s1, "S1")))
        print("ARM_D " + (try accountDump(s2, "S2")))
        XCTAssertEqual(sharedRows, 0, "两库有共享结算行，说明这不是两个空间，本轮设计不成立")
    }
}

