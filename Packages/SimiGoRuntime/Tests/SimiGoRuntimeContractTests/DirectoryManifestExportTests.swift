import Foundation
import XCTest
@testable import SimiGoRuntimeContract

/// 目录清单导出：人加目录 → 扫一遍 → 出一份能在 Excel/WPS 里改标题的 CSV。
///
/// 量和约定的三件事：
/// 1. 标题默认就是文件名去后缀、去「附件N：」前缀——人整理文件时文件名就是标题；
/// 2. 只有整份文件是一个附件标签时，才用「主文件名 + 附件标签」，认不出主文件就标 must_fix；
/// 3. 编码是 UTF-8 with BOM + CRLF，隐藏项、Office 锁文件、软链、输出文件自己都不算。
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

    private func touch(_ root: URL, _ names: [String]) throws {
        for name in names {
            let url = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try "正文\n".write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - 标题就是文件名

    func testTitleIsFileNameWithoutExtension() throws {
        let db = try open()
        let root = try makeRoot()
        try touch(root, ["中华人民共和国合同法.docx", "考核台账 2026.xlsx",
                         "第三章 考核与结算.md", "make_fixtures.py"])

        let (_, table, _) = try export(db, root: root)
        let titles = Dictionary(uniqueKeysWithValues: table.dropFirst().map { ($0[2], $0[3]) })
        XCTAssertEqual(titles["中华人民共和国合同法.docx"], "中华人民共和国合同法")
        XCTAssertEqual(titles["考核台账 2026.xlsx"], "考核台账 2026")
        XCTAssertEqual(titles["第三章 考核与结算.md"], "第三章 考核与结算")
        XCTAssertEqual(titles["make_fixtures.py"], "make_fixtures")
    }

    func testAttachmentPrefixIsDropped() throws {
        let db = try open()
        let root = try makeRoot()
        try touch(root, [
            "附件1：申报表.docx",
            "641附件：成本管理提升方案.doc",
            "451附件.防亏减亏工作方案.pdf",
            "附件1.经济活动分析管理办法（试行）.docx",
            "附件：安全生产责任书.docx",
        ])

        let (report, table, _) = try export(db, root: root)
        XCTAssertEqual(report.mustFix, 0)
        let titles = Dictionary(uniqueKeysWithValues: table.dropFirst().map { ($0[2], $0[3]) })
        XCTAssertEqual(titles["附件1：申报表.docx"], "申报表")
        XCTAssertEqual(titles["641附件：成本管理提升方案.doc"], "成本管理提升方案")
        XCTAssertEqual(titles["451附件.防亏减亏工作方案.pdf"], "防亏减亏工作方案")
        XCTAssertEqual(titles["附件1.经济活动分析管理办法（试行）.docx"], "经济活动分析管理办法（试行）")
        XCTAssertEqual(titles["附件：安全生产责任书.docx"], "安全生产责任书")
    }

    /// 「附件管理办法」是真名词，不是附件标签：没有编号也没有分隔符就不拆。
    func testOrdinaryWordStartingWithAttachmentIsKeptWhole() throws {
        let db = try open()
        let root = try makeRoot()
        try touch(root, ["附件管理办法.docx", "附件清单 2026.xlsx"])

        let (_, table, _) = try export(db, root: root)
        XCTAssertEqual(table.dropFirst().map { $0[3] }, ["附件清单 2026", "附件管理办法"])
    }

    /// 整份文件只是一个附件标签：同目录只有一个不带标签的文件时，用「主文件名 + 附件标签」。
    func testBareAttachmentTakesTheMainFileName() throws {
        let db = try open()
        let root = try makeRoot()
        let dir = "关于印发《物资管理办法》的通知"
        try touch(root, [
            "\(dir)/关于印发《物资管理办法》的通知.pdf",
            "\(dir)/附件11-1.rar",
            "\(dir)/附件10-1~10-4.rar",
            "\(dir)/附件1：物资采购管理办法.docx",
        ])

        let (report, table, _) = try export(db, root: root)
        XCTAssertEqual(report.files, 4)
        XCTAssertEqual(report.fromMainFile, 2)
        XCTAssertEqual(report.mustFix, 0)
        let titles = Dictionary(uniqueKeysWithValues: table.dropFirst().map { ($0[2], $0[3]) })
        XCTAssertEqual(titles["附件11-1.rar"], "关于印发《物资管理办法》的通知附件11-1")
        XCTAssertEqual(titles["附件10-1~10-4.rar"], "关于印发《物资管理办法》的通知附件10-1~10-4")
        XCTAssertEqual(titles["附件1：物资采购管理办法.docx"], "物资采购管理办法")
        XCTAssertEqual(titles["关于印发《物资管理办法》的通知.pdf"], "关于印发《物资管理办法》的通知")
    }

    /// 认不出主文件（同目录两个都不带标签，或者一个都没有）就不猜，标出来给人补。
    func testBareAttachmentWithoutMainFileIsFlagged() throws {
        let db = try open()
        let root = try makeRoot()
        try touch(root, ["甲.pdf", "乙.pdf", "附件.zip"])

        let (report, table, _) = try export(db, root: root)
        XCTAssertEqual(report.mustFix, 1)
        XCTAssertEqual(report.fromMainFile, 0)
        let att = table.dropFirst().first { $0[2] == "附件.zip" }
        XCTAssertEqual(att?[3], "附件")
        XCTAssertEqual(att?[7], "no_main_file")
    }

    func testRelativePathIsUnderRoot() throws {
        let db = try open()
        let root = try makeRoot()
        try touch(root, ["章节/草稿.md"])

        let (_, table, _) = try export(db, root: root)
        XCTAssertEqual(table.count, 2)
        XCTAssertEqual(table[1][1], "章节/草稿.md")
        XCTAssertEqual(table[1][2], "草稿.md")
        XCTAssertEqual(table[1][3], "草稿")
    }

    // MARK: - 真实样本

    func testFormatSwapManifestGivesEveryFileATitle() throws {
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
        XCTAssertEqual(report.titled, 11)
        XCTAssertEqual(report.mustFix, 0)
        XCTAssertEqual(table.count, 12)                     // 表头 + 11 行
        XCTAssertEqual(table[0].count, 8)

        for row in table.dropFirst() {
            XCTAssertEqual(row[3], (row[2] as NSString).deletingPathExtension,
                           "\(row[2]) 的标题不是去后缀的文件名")
        }

        // Excel/WPS 直接可读的编码。
        XCTAssertEqual(Array(raw.prefix(3)), [0xEF, 0xBB, 0xBF])
        let text = String(decoding: raw, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("\u{FEFF}root_id,relative_path,file_name,title,"))
        XCTAssertEqual(text.components(separatedBy: "\n").count - 1,
                       text.components(separatedBy: "\r\n").count - 1,
                       "有裸 \\n，不是纯 CRLF")
    }

    // MARK: - 扫的是目录，不是字节

    func testSkipsHiddenLockAndSymlinkAndTheOutputItself() throws {
        let db = try open()
        let root = try makeRoot()
        try touch(root, ["real.txt", "~$合同.docx", ".hidden.txt"])
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link.txt"),
            withDestinationURL: root.appendingPathComponent("real.txt"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("loop"), withDestinationURL: root)

        let (report, table, _) = try export(db, root: root)
        XCTAssertEqual(report.files, 1)
        XCTAssertEqual(table.dropFirst().map { $0[2] }, ["real.txt"])
    }

    func testMaxDepthStopsDescending() throws {
        let db = try open()
        let root = try makeRoot()
        try touch(root, ["top.txt", "a/b/deep.txt"])

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
        try touch(root, ["a.txt", ".DS_Store", "b.txt", "~$锁.docx", "c.txt",
                         "子目录/d.txt", "子目录/e.txt"])

        let (report, table, _) = try export(db, root: root)
        XCTAssertEqual(report.files, 5)
        XCTAssertEqual(table.dropFirst().map { $0[2] }.sorted(),
                       ["a.txt", "b.txt", "c.txt", "d.txt", "e.txt"])
    }

    func testCommaInFileNameStaysOneCell() throws {
        let db = try open()
        let root = try makeRoot()
        try touch(root, ["合同, 修订版.txt"])

        let (report, table, raw) = try export(db, root: root)
        XCTAssertEqual(report.files, 1)
        XCTAssertEqual(table.count, 2, "解析出来 \(table.count) 行")
        guard table.count == 2 else { return }
        XCTAssertEqual(table[1].count, 8)
        if table[1].count > 3 { XCTAssertEqual(table[1][3], "合同, 修订版") }
        XCTAssertEqual(raw.count > 0, true)
    }

    /// 手动探针：`SIMIGO_MANIFEST_PROBE_DIR=<真实目录> [SIMIGO_MANIFEST_PROBE_OUT=<csv>] swift test --filter testProbeOnPickedFolder`
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
}
