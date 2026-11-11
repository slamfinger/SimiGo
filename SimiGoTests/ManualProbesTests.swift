import Foundation
import XCTest
import SimiGoRuntimeContract

/// 手动探针：这里的两件事都要碰真实目录、甚至碰人自己的权威库，不该在 CI 上跑；
/// 而契约用例集那边的门要求 `skipped==0`，探针放进去会把整条离线车道弄红。
/// 所以它们留在这个目标里，按需 `-only-testing` 跑：
///
///     xcodebuild test -scheme SimiGo \
///       -only-testing:SimiGoTests/ManualProbesTests/testProbeOnPickedFolder
final class ManualProbesTests: XCTestCase {

    private var scratch: [URL] = []

    override func tearDown() {
        for url in scratch {
            try? FileManager.default.removeItem(at: url)
        }
        scratch = []
        super.tearDown()
    }

    private func open() throws -> ESISDatabase {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-probe-\(UUID().uuidString).sqlite3")
        scratch.append(url)
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        return db
    }

    /// 一个 CSV 单元格拆成数组；只处理探针用到的引号写法。
    private func rows(_ text: String) -> [[String]] {
        var out: [[String]] = []
        var field = ""
        var row: [String] = []
        var quoted = false
        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]
            if quoted {
                if ch == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        index = next
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(ch)
                }
            } else if ch == "\"" {
                quoted = true
            } else if ch == "," {
                row.append(field)
                field = ""
            } else if ch == "\r\n" || ch == "\n" || ch == "\r" {
                row.append(field)
                out.append(row)
                row = []
                field = ""
            } else {
                field.append(ch)
            }
            index = text.index(after: index)
        }
        return out
    }

    /// `SIMIGO_MANIFEST_PROBE_DIR=<真实目录> [SIMIGO_MANIFEST_PROBE_OUT=<csv>]`
    /// 拿一个真实目录出一份清单，把 must_fix 的条目打出来。
    func testProbeOnPickedFolder() throws {
        guard let path = ProcessInfo.processInfo.environment["SIMIGO_MANIFEST_PROBE_DIR"]
        else { throw XCTSkip("未指定 SIMIGO_MANIFEST_PROBE_DIR") }
        let root = URL(fileURLWithPath: path)
        // 指定了输出路径就是给人留的，跑完不能删；没指定才落在临时目录里。
        let explicit = ProcessInfo.processInfo.environment["SIMIGO_MANIFEST_PROBE_OUT"]
        let csv = explicit.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("simigo-manifest-probe-\(UUID().uuidString).csv")
        if explicit == nil { scratch.append(csv) }
        let report = try open().exportDirectoryManifest(rootID: "probe", rootURL: root, to: csv)
        let text = String(decoding: try Data(contentsOf: csv), as: UTF8.self)
        print("MANIFEST_PROBE files=\(report.files) titled=\(report.titled) "
              + "from_main=\(report.fromMainFile) must_fix=\(report.mustFix)")
        for row in rows(text).dropFirst() where !row[7].isEmpty {
            print("MANIFEST_PROBE must_fix \(row[1]) -> \(row[7])")
        }
    }

    /// `SIMIGO_IMPORT_MANAGED_ROOT=<目录>`
    /// 把真实根目录复核进权威库（等同图形界面里「＋ 加外部目录」）。
    func testProbeImportIntoManagedDatabase() throws {
        guard let path = ProcessInfo.processInfo.environment["SIMIGO_IMPORT_MANAGED_ROOT"]
        else { throw XCTSkip("未指定 SIMIGO_IMPORT_MANAGED_ROOT") }
        let db = try ESISDatabase(url: ManagedPaths.databaseURL)
        try db.runMigrations()
        guard let root = try db.listRoots(category: "work").first(where: {
            $0.displayName == path
        }) else { throw XCTSkip("库里没有这个根：\(path)") }
        let report = try db.importDirectoryNames(
            rootID: root.rootID, rootURL: URL(fileURLWithPath: path))
        print("MANAGED_IMPORT \(root.rootID) files=\(report.files) inserted=\(report.inserted) "
              + "refreshed=\(report.refreshed) missing=\(report.missing)")
    }
}
