import Foundation
import SQLite3
import XCTest
@testable import SimiGoRuntimeContract

/// `project_notes.recorded_at` 的纪元归一（defect FDC884A7 / BFC75162）。
///
/// 2026-11-27 有九行绕过产品写路径、用 Unix 秒落库。账本 append-only，那九行
/// 是证据，不改；产品在读侧归一。这里用产品自己的写路径造出同形的行——
/// `stamp()` 忠实写入传入的 `Date`，所以一个参考日秒大于 1e9 的 `Date`
/// 落库后与那九行逐字节同形——再断言：原件不动、读数归一、跨纪元比较与
/// 排序按真实时刻成立。
final class ProjectNoteEpochTests: XCTestCase {

    /// 与生产那九行同形的存量值：Unix 秒，整数，10 字符。
    private let unixShapedStored = "1795784239"
    /// 同一时刻的参考日秒（= Unix 秒 − 978307200）。
    private let referenceShaped = "817477039"

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-epoch-\(UUID().uuidString)-\(name).sqlite3")
    }

    private func cleanup(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func rawText(_ url: URL, _ sql: String) throws -> String? {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            sqlite3_close(handle)
            throw ESISDatabase.DatabaseError.cannotOpen(url.path)
        }
        defer { sqlite3_close(handle) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_finalize(stmt)
            throw ESISDatabase.DatabaseError.sql("prepare failed: \(sql)")
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) }
    }

    /// 归一只对越界值动手：合法行必须逐字节原样回来，否则每次读都在悄悄改写
    /// 账本的读数，那比缺陷本身更糟。
    func testWellFormedStampIsReturnedByteIdentical() throws {
        let url = tempURL("well-formed")
        defer { cleanup(url) }
        let db = try ESISDatabase(url: url)
        defer { db.close() }
        try db.runMigrations()

        let stamp = "817484534.66173196"
        let note = try db.recordProjectNote(
            kind: "brief@owner", claim: "v1",
            at: Date(timeIntervalSinceReferenceDate: 817_484_534.66173196)).note
        XCTAssertEqual(note.recordedAt, stamp)
        XCTAssertEqual(
            try rawText(url, "SELECT recorded_at FROM project_notes;"), stamp,
            "存量与读数一致：合法行根本不进归一分支")
        XCTAssertEqual(
            try db.currentProjectNote(kind: "brief@owner")?.recordedAt, stamp)
    }

    /// 九行的形状：存量保持 Unix 秒（原件不改），读数归一为参考日秒。
    func testUnixShapedRowReadsNormalizedAndStaysUnrewritten() throws {
        let url = tempURL("unix-shaped")
        defer { cleanup(url) }
        let db = try ESISDatabase(url: url)
        defer { db.close() }
        try db.runMigrations()

        let note = try db.recordProjectNote(
            kind: "defect@owner", claim: "unix-shaped row",
            at: Date(timeIntervalSinceReferenceDate: 1_795_784_239)).note
        XCTAssertEqual(
            try rawText(
                url, "SELECT recorded_at FROM project_notes WHERE note_id='\(note.noteID)';"),
            unixShapedStored,
            "写路径忠实落库＝与生产那九行同形；本修复不得改写它")
        XCTAssertEqual(note.recordedAt, referenceShaped)
        XCTAssertEqual(
            try db.currentProjectNote(kind: "defect@owner")?.recordedAt, referenceShaped)
        XCTAssertEqual(
            try db.projectNoteHistory(kind: "defect@owner").map(\.recordedAt),
            [referenceShaped],
            "历史视图走同一个解码口")
    }

    /// 真正的后果面：Unix 秒行恒大于任何合法行，于是它永远「更新」，
    /// `stale` 恒 true、`newer_notes` 永久被污染；排序也把它甩到最后。
    func testNewerNotesAreOrderedByTrueInstantAcrossMixedEpochs() throws {
        let url = tempURL("mixed-epochs")
        defer { cleanup(url) }
        let db = try ESISDatabase(url: url)
        defer { db.close() }
        try db.runMigrations()

        let base = 817_477_039.0
        let earlier = try db.recordProjectNote(
            kind: "status@owner", claim: "one hour before",
            at: Date(timeIntervalSinceReferenceDate: base - 3600)).note
        let unixShaped = try db.recordProjectNote(
            kind: "defect@owner", claim: "unix-shaped row",
            at: Date(timeIntervalSinceReferenceDate: 1_795_784_239)).note
        let later = try db.recordProjectNote(
            kind: "receipt@owner", claim: "one hour after",
            at: Date(timeIntervalSinceReferenceDate: base + 3600)).note

        for scope in [true, false] {
            let label = scope ? "scoped" : "unscoped"
            func newer(than stamp: String) throws -> [ESISDatabase.ProjectNote] {
                try scope
                    ? db.projectNotesNewerThan(than: stamp, scope: "owner")
                    : db.projectNotesNewerThan(than: stamp)
            }

            XCTAssertEqual(
                try newer(than: earlier.recordedAt).map(\.noteID),
                [unixShaped.noteID, later.noteID],
                "\(label): 越界行按真实时刻排在中间，不是甩到最后")
            XCTAssertEqual(
                try newer(than: unixShaped.recordedAt).map(\.noteID),
                [later.noteID],
                "\(label): 以越界行为基准也按真实时刻比较")
            XCTAssertEqual(
                try newer(than: later.recordedAt).map(\.noteID), [],
                "\(label): 最新一条之后没有材料＝stale 不再被恒钉为 true")
        }
    }

    /// 判据取自时钟而非常量：一条记录不可能落在远未来，所以只有越过
    /// 「现在＋一天」的数值才当 Unix 秒。常量 1e9 看着更简单，但参考日秒
    /// 2032-09 就过 1e9，从那天起每条合法行都会被静默移回 31 年。
    func testRuleIsReadOffTheClockAndIdempotent() {
        let now = Date(timeIntervalSinceReferenceDate: 817_484_534)
        let threshold = ProjectNoteEpoch.threshold(now)
        XCTAssertEqual(threshold, 817_484_534 + ProjectNoteEpoch.futureTolerance)

        XCTAssertEqual(
            ProjectNoteEpoch.referenceSeconds("817484534.66173196", threshold: threshold),
            817_484_534.66173196)
        XCTAssertEqual(
            ProjectNoteEpoch.normalizedStamp("817484534.66173196", threshold: threshold),
            "817484534.66173196", "合法行逐字节原样")
        XCTAssertEqual(
            ProjectNoteEpoch.referenceSeconds(unixShapedStored, threshold: threshold),
            1_795_784_239 - ProjectNoteEpoch.unixToReferenceOffset)
        XCTAssertEqual(
            ProjectNoteEpoch.normalizedStamp(unixShapedStored, threshold: threshold),
            referenceShaped)
        XCTAssertEqual(
            ProjectNoteEpoch.normalizedStamp(
                ProjectNoteEpoch.normalizedStamp(unixShapedStored, threshold: threshold),
                threshold: threshold),
            referenceShaped, "归一两次不再动")
        XCTAssertNil(
            ProjectNoteEpoch.referenceSeconds("2026-11-27T15:30:40Z", threshold: threshold))
        XCTAssertEqual(
            ProjectNoteEpoch.normalizedStamp("2026-11-27T15:30:40Z", threshold: threshold),
            "2026-11-27T15:30:40Z", "旧 ISO 行不归 `Double` 管")
    }

    /// 2032-09 之后参考日秒本身就超过 1e9：常量判据从那天起误伤合法行，
    /// 时钟判据仍能分开两者。这条是选择时钟判据的理由，不是装饰。
    func testRuleStillSeparatesEpochsAfterReferenceSecondsPassOneBillion() {
        let threshold = ProjectNoteEpoch.threshold(
            Date(timeIntervalSinceReferenceDate: 1_050_000_000))
        XCTAssertEqual(
            ProjectNoteEpoch.normalizedStamp("1050000000", threshold: threshold),
            "1050000000", "那时的合法行不被当成 Unix 秒")
        XCTAssertEqual(
            ProjectNoteEpoch.normalizedStamp("2050000000", threshold: threshold),
            String(format: "%.17g", 2_050_000_000.0 - ProjectNoteEpoch.unixToReferenceOffset),
            "同一时期的 Unix 秒行照样归一")
    }

    /// `WHERE`/`ORDER BY` 用的是 SQL 侧那份归一，读数用的是 Swift 这份；
    /// 两份规则若走岔，比较与展示就会各自说一套。
    func testSQLExpressionAgreesWithSwiftNormalization() throws {
        let url = tempURL("sql-agreement")
        defer { cleanup(url) }
        let db = try ESISDatabase(url: url)
        defer { db.close() }
        try db.runMigrations()

        let stamps: [Double] = [817_477_039, 1_795_784_239, 817_484_534.66173196]
        var ids: [String] = []
        for (index, stamp) in stamps.enumerated() {
            ids.append(try db.recordProjectNote(
                kind: "status@owner", claim: "row \(index)",
                at: Date(timeIntervalSinceReferenceDate: stamp)).note.noteID)
        }
        for id in ids {
            let decoded = try db.projectNoteHistory(kind: "status@owner")
                .first { $0.noteID == id }?.recordedAt
            let fromSQL = try rawText(url, """
            SELECT CAST(\(ProjectNoteEpoch.recordedAtSQL()) AS TEXT)
              FROM project_notes WHERE note_id='\(id)';
            """)
            XCTAssertEqual(
                fromSQL.flatMap { Double($0) }, decoded.flatMap { Double($0) },
                "SQL 与 Swift 对 \(id) 给出同一时刻")
        }
    }
}
