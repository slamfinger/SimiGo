import Foundation
import XCTest
@testable import SimiGoRuntimeContract

/// 目录清单导出：人加目录 → 扫一遍 → 出一份能在 Excel/WPS 里补标题的 CSV。
///
/// 这份 CSV 是人和 IS 之间的交接单，所以量的是三件事：
/// 1. 标题只从文件内取，取不到必须落在 `must_fix` 里，不能悄悄用文件名冒充；
/// 2. 编码是 UTF-8 with BOM + CRLF（Excel/WPS 直接双击不乱码）；
/// 3. 扫的是目录，不是字节：隐藏文件、Office 锁文件、软链、输出文件自己都不算。
final class DirectoryManifestExportTests: XCTestCase {

    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/format-swap")

    private var scratch: [URL] = []

    override func tearDown() {
        for url in scratch {
            try? FileManager.default.removeItem(at: url)
        }
        scratch = []
        super.tearDown()
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-manifest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        scratch.append(root)
        return root
    }

    private func open() throws -> ESISDatabase {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-manifest-\(UUID().uuidString).sqlite3")
        scratch.append(url)
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        return db
    }

    /// 一个 CSV 单元格拆成数组；只处理本测试用到的引号写法。
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

    private func export(_ db: ESISDatabase, root: URL, name: String = "manifest.csv") throws
        -> (report: ESISDatabase.DirectoryManifestReport, rows: [[String]], raw: Data)
    {
        let csv = root.appendingPathComponent(name)
        let report = try db.exportDirectoryManifest(rootID: "root-1", rootURL: root, to: csv)
        let raw = try Data(contentsOf: csv)
        let text = String(data: raw, encoding: .utf8) ?? ""
        return (report, rows(text), raw)
    }

    // MARK: - 真实样本：Word/Excel 换存法那一批

    func testFormatSwapManifestCountsTitleOnlyFromInsideTheFile() throws {
        guard FileManager.default.fileExists(atPath: Self.fixtures.path) else {
            throw XCTSkip("format-swap 样本只在实验分支上，这里没有")
        }
        let db = try open()
        let root = try makeRoot()
        for name in try FileManager.default.contentsOfDirectory(atPath: Self.fixtures.path) {
            try FileManager.default.copyItem(at: Self.fixtures.appendingPathComponent(name),
                                             to: root.appendingPathComponent(name))
        }

        let (report, table, raw) = try export(db, root: root)
        XCTAssertEqual(report.files, 11)
        XCTAssertEqual(report.titled, 6)
        XCTAssertEqual(report.mustFix, 5)
        XCTAssertEqual(table.count, 12)                     // 表头 + 11 行
        XCTAssertEqual(table[0].count, 8)

        var outcome: [String: String] = [:]
        for row in table.dropFirst() { outcome[row[2]] = row[7] }

        // 纯文本：首行就是标题。
        XCTAssertEqual(outcome["contract-v1.txt"], "")
        XCTAssertEqual(outcome["contract-v1.docx.extract.txt"], "")
        // 二进制 Office 文档里 dc:title 是空的，默认表名 "Sheet" 也不算标题。
        XCTAssertEqual(outcome["contract-v1.docx"], "title_missing")
        XCTAssertEqual(outcome["contract-v1-resaved.docx"], "title_missing")
        XCTAssertEqual(outcome["amount-v1.xlsx"], "title_missing")
        // 表头不是标题；没有读取器的格式不猜。
        XCTAssertEqual(outcome["amount-v1.csv"], "title_missing")
        XCTAssertEqual(outcome["make_fixtures.py"], "no_reader")

        // 标题不许拿文件名顶替。
        for row in table.dropFirst() where row[7].isEmpty {
            XCTAssertFalse(row[3].isEmpty, "\(row[2]) 标了有标题却是空的")
            XCTAssertNotEqual(row[3], row[2])
        }
        for row in table.dropFirst() where !row[7].isEmpty {
            XCTAssertEqual(row[3], "", "\(row[2]) 取不到标题却写了值")
        }

        // Excel/WPS 直接可读的编码。
        XCTAssertEqual(Array(raw.prefix(3)), [0xEF, 0xBB, 0xBF])
        let text = String(decoding: raw, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("\u{FEFF}root_id,relative_path,file_name,title,"))
        XCTAssertEqual(text.components(separatedBy: "\n").count - 1,
                       text.components(separatedBy: "\r\n").count - 1,
                       "有裸 \\n，不是纯 CRLF")
    }

    // MARK: - 标题只在文件内：Office 包里的那几处

    private func makeZip(at url: URL, entries: [String: String]) throws {
        let staging = try makeRoot()
        for (name, body) in entries {
            let file = staging.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try body.write(to: file, atomically: true, encoding: .utf8)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", "-X", "-r", url.path] + entries.keys.sorted()
        process.currentDirectoryURL = staging
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "zip 失败")
    }

    private func coreProperties(_ title: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" \
        xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>\(title)</dc:title></cp:coreProperties>
        """
    }

    func testDocxTitleComesFromCoreProperties() throws {
        let db = try open()
        let root = try makeRoot()
        try makeZip(at: root.appendingPathComponent("考核办法.docx"),
                    entries: ["docProps/core.xml": coreProperties("考核办法（2026 修订）")])
        try makeZip(at: root.appendingPathComponent("空标题.docx"),
                    entries: ["docProps/core.xml": coreProperties("")])

        let (report, table, _) = try export(db, root: root)
        XCTAssertEqual(report.files, 2)
        let titles = Dictionary(uniqueKeysWithValues: table.dropFirst().map { ($0[2], ($0[3], $0[7])) })
        XCTAssertEqual(titles["考核办法.docx"]?.0, "考核办法（2026 修订）")
        XCTAssertEqual(titles["空标题.docx"]?.1, "title_missing")
    }

    func testXlsxFallsBackToSheetNameButNotTheDefaultOne() throws {
        let db = try open()
        let root = try makeRoot()
        func workbook(_ sheet: String) -> [String: String] {
            ["docProps/core.xml": coreProperties(""),
             "xl/workbook.xml": """
             <?xml version="1.0" encoding="UTF-8"?>
             <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
             <sheets><sheet name="\(sheet)" sheetId="1" state="visible"/></sheets></workbook>
             """]
        }
        try makeZip(at: root.appendingPathComponent("台账.xlsx"), entries: workbook("考核台账"))
        try makeZip(at: root.appendingPathComponent("默认表.xlsx"), entries: workbook("Sheet1"))
        try makeZip(at: root.appendingPathComponent("默认中文表.xlsx"), entries: workbook("工作表2"))

        let (report, table, _) = try export(db, root: root)
        XCTAssertEqual(report.titled, 1)
        let titles = Dictionary(uniqueKeysWithValues: table.dropFirst().map { ($0[2], $0[3]) })
        XCTAssertEqual(titles["台账.xlsx"], "考核台账")
        XCTAssertEqual(titles["默认表.xlsx"], "")
        XCTAssertEqual(titles["默认中文表.xlsx"], "")
    }

    func testRelativePathIsUnderRootAndTitleComesFromFileBody() throws {
        let db = try open()
        let root = try makeRoot()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("章节"),
                                                withIntermediateDirectories: true)
        try "# 第三章 考核与结算\n\n正文不清".write(to: root.appendingPathComponent("章节/草稿.md"),
                                                atomically: true, encoding: .utf8)

        let (_, table, _) = try export(db, root: root)
        XCTAssertEqual(table.count, 2)
        let row = table[1]
        XCTAssertEqual(row[1], "章节/草稿.md")
        XCTAssertEqual(row[2], "草稿.md")
        XCTAssertEqual(row[3], "第三章 考核与结算")     // `#` 不是标题的一部分
        XCTAssertEqual(row[7], "")
    }

    // MARK: - 扫的是目录，不是字节

    func testSkipsHiddenLockAndSymlinkAndTheOutputItself() throws {
        let db = try open()
        let root = try makeRoot()
        try "真文件\n".write(to: root.appendingPathComponent("real.txt"),
                           atomically: true, encoding: .utf8)
        try "锁\n".write(to: root.appendingPathComponent("~$合同.docx"),
                        atomically: true, encoding: .utf8)
        try "藏\n".write(to: root.appendingPathComponent(".hidden.txt"),
                        atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link.txt"),
            withDestinationURL: root.appendingPathComponent("real.txt"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("loop"),
            withDestinationURL: root)

        let (report, table, _) = try export(db, root: root)
        XCTAssertEqual(report.files, 1)
        XCTAssertEqual(table.dropFirst().map { $0[2] }, ["real.txt"])
    }

    func testMaxDepthStopsDescending() throws {
        let db = try open()
        let root = try makeRoot()
        let deep = root.appendingPathComponent("a/b")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        try "顶层\n".write(to: root.appendingPathComponent("top.txt"),
                          atomically: true, encoding: .utf8)
        try "深处\n".write(to: deep.appendingPathComponent("deep.txt"),
                          atomically: true, encoding: .utf8)

        let csv = root.appendingPathComponent("m.csv")
        let shallow = try db.exportDirectoryManifest(
            rootID: "r", rootURL: root, to: csv, maxDepth: 1)
        XCTAssertEqual(shallow.files, 1)

        let all = try db.exportDirectoryManifest(rootID: "r", rootURL: root, to: csv, maxDepth: 64)
        XCTAssertEqual(all.files, 2)
    }

    /// 隐藏文件出现在列表中间时，不能把它后面的同级文件一起吃掉
    /// （`skipDescendants` 跳的是"当前目录剩下的部分"，对文件调用等于截断目录）。
    func testHiddenFileDoesNotSwallowItsSiblings() throws {
        let db = try open()
        let root = try makeRoot()
        for name in ["a.txt", ".DS_Store", "b.txt", "~$锁.docx", "c.txt"] {
            try "行\n".write(to: root.appendingPathComponent(name),
                            atomically: true, encoding: .utf8)
        }
        let sub = root.appendingPathComponent("子目录")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        for name in ["d.txt", "e.txt"] {
            try "行\n".write(to: sub.appendingPathComponent(name),
                            atomically: true, encoding: .utf8)
        }

        let (report, table, _) = try export(db, root: root)
        XCTAssertEqual(report.files, 5)
        XCTAssertEqual(table.dropFirst().map { $0[2] }.sorted(),
                       ["a.txt", "b.txt", "c.txt", "d.txt", "e.txt"])
    }

    /// Windows 换行、GB18030 编码的旧文本文件：标题仍然是首行，不是整份文件。
    func testWindowsLineEndingsAndLegacyChineseEncoding() throws {
        let db = try open()
        let root = try makeRoot()
        try "第一章 总则\r\n\r\n正文\r\n".write(to: root.appendingPathComponent("crlf.txt"),
                                              atomically: true, encoding: .utf8)
        let gb = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        let legacy = "第二章 合同额\r\n正文\r\n".data(using: String.Encoding(rawValue: gb))!
        try legacy.write(to: root.appendingPathComponent("gbk.txt"))

        let (report, table, _) = try export(db, root: root)
        XCTAssertEqual(report.titled, 2)
        XCTAssertEqual(report.mustFix, 0)
        let titles = Dictionary(uniqueKeysWithValues: table.dropFirst().map { ($0[2], $0[3]) })
        XCTAssertEqual(titles["crlf.txt"], "第一章 总则")
        XCTAssertEqual(titles["gbk.txt"], "第二章 合同额")
    }

    /// 手动探针：`SIMIGO_MANIFEST_PROBE_DIR=<真实目录> swift test --filter testProbeOnPickedFolder`
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
        print("MANIFEST_PROBE files=\(report.files) titled=\(report.titled) must_fix=\(report.mustFix)")
        for row in rows(text).dropFirst() where !row[7].isEmpty {
            print("MANIFEST_PROBE must_fix \(row[1]) -> \(row[7])")
        }
    }

    func testCommaInFileNameStaysOneCell() throws {
        let db = try open()
        let root = try makeRoot()
        try "标题\n".write(to: root.appendingPathComponent("合同, 修订版.txt"),
                          atomically: true, encoding: .utf8)

        let (report, table, raw) = try export(db, root: root)
        XCTAssertEqual(report.files, 1)
        try raw.write(to: URL(fileURLWithPath: "/tmp/dbg-manifest.csv"))
        XCTAssertEqual(table.count, 2, "只解析出 \(table.count) 行")
        guard table.count == 2 else { return }
        XCTAssertEqual(table[1].count, 8)
        if table[1].count > 2 { XCTAssertEqual(table[1][2], "合同, 修订版.txt") }
    }
}
