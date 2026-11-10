import Foundation

/// 目录清单导出：把一个人选定的目录扫一遍，写出一份 CSV，交给人在 Excel / WPS 里补标题。
///
/// 这是产品功能的一部分，不是外部脚本：编码（UTF-8 with BOM + CRLF）、跳过规则、
/// "标题只从文件内取"这些约定跟 IS 的身份模型绑在一起，散到外部脚本里迟早会走样。
///
/// 列：`root_id, relative_path, file_name, title, bytes, modified, summary, must_fix`
/// - `title` 只从文件内取；取不到就空着，并在 `must_fix` 里说明原因。
/// - `summary` 留空，由人补或由 ES 后续写入。
public extension ESISDatabase {

    struct DirectoryManifestReport: Equatable, Sendable {
        public let files: Int
        public let titled: Int
        public let mustFix: Int
        public let csvPath: String
    }

    enum ManifestTitleOutcome: String, Sendable {
        case titled = ""
        case missing = "title_missing"
        case unreadable = "title_unreadable"
        case noReader = "no_reader"
    }

    /// 扫描 `rootURL` 下所有文件，把清单写到 `csvURL`。
    @discardableResult
    func exportDirectoryManifest(
        rootID: String, rootURL: URL, to csvURL: URL, maxDepth: Int = 64
    ) throws -> DirectoryManifestReport {
        let root = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let output = csvURL.resolvingSymlinksInPath().standardizedFileURL.path
        let outputRelative = output.hasPrefix(root.path + "/")
            ? String(output.dropFirst(root.path.count + 1)) : nil
        var rows: [[String]] = []
        var titled = 0
        var mustFix = 0
        let stamp = Self.manifestFormatter()

        for (relative, url) in Self.manifestWalk(
            root: root, maxDepth: maxDepth, skipping: outputRelative
        ) {
            let (title, outcome) = Self.manifestTitle(of: url)
            if outcome == .titled { titled += 1 } else { mustFix += 1 }
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes?[.size] as? NSNumber)?.stringValue ?? ""
            let modified = (attributes?[.modificationDate] as? Date).map { stamp.string(from: $0) } ?? ""
            rows.append([rootID, relative, url.lastPathComponent, title, size, modified, "",
                         outcome.rawValue])
        }

        var text = "\u{FEFF}root_id,relative_path,file_name,title,bytes,modified,summary,must_fix\r\n"
        for row in rows {
            text += row.map(Self.csvField).joined(separator: ",") + "\r\n"
        }
        try Data(text.utf8).write(to: csvURL)
        return DirectoryManifestReport(files: rows.count, titled: titled,
                                       mustFix: mustFix, csvPath: csvURL.path)
    }

    // MARK: - 扫描

    /// 走相对路径，不走绝对路径：枚举器会把 `/var` 还原成 `/private/var`，
    /// 拿绝对路径对齐根目录就会把相对路径算错，而相对路径正是 `relative_path` 这一列。
    private static func manifestWalk(
        root: URL, maxDepth: Int, skipping outputRelative: String?
    ) -> [(String, URL)] {
        guard let enumerator = FileManager.default.enumerator(atPath: root.path) else { return [] }
        var out: [(String, URL)] = []
        for case let relative as String in enumerator {
            let name = (relative as NSString).lastPathComponent
            // Office 锁文件、系统垃圾、隐藏目录（.git 之类）都不算文件，也不必往下走。
            if name.hasPrefix(".") || name.hasPrefix("~$") || name == "Thumbs.db" {
                enumerator.skipDescendants()
                continue
            }
            if relative.components(separatedBy: "/").count - 1 > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            if relative == outputRelative { continue }
            let url = root.appendingPathComponent(relative)
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else { continue }
            out.append((relative, url))
        }
        return out.sorted { $0.0 < $1.0 }
    }

    // MARK: - 标题

    private static func manifestTitle(of url: URL) -> (String, ManifestTitleOutcome) {
        switch url.pathExtension.lowercased() {
        case "docx", "docm":
            if let title = officeTitle(url) { return (title, .titled) }
            return ("", .missing)
        case "xlsx", "xlsm":
            if let title = officeTitle(url) ?? firstSheetName(url) { return (title, .titled) }
            return ("", .missing)
        case "pptx":
            if let title = officeTitle(url) { return (title, .titled) }
            return ("", .missing)
        case "pdf":
            if let title = spotlightTitle(url), !title.isEmpty { return (title, .titled) }
            return ("", .missing)
        case "txt", "md":
            return textTitle(url)
        case "csv", "tsv":
            // 第一行是表头，不是标题：取来会让一堆文件都叫同一个名字。
            return ("", .missing)
        default:
            return ("", .noReader)
        }
    }

    private static func officeTitle(_ url: URL) -> String? {
        guard let xml = unzippedPart(url, "docProps/core.xml") else { return nil }
        guard let raw = firstCapture(in: xml, pattern: "<dc:title>(.*?)</dc:title>") else { return nil }
        let title = cleanTitle(xmlUnescape(raw))
        return title.isEmpty ? nil : title
    }

    private static func firstSheetName(_ url: URL) -> String? {
        guard let xml = unzippedPart(url, "xl/workbook.xml") else { return nil }
        guard let raw = firstCapture(in: xml, pattern: "<sheet[^>]*name=\"([^\"]*)\"") else { return nil }
        let name = cleanTitle(xmlUnescape(raw))
        // 软件给的默认表名不是标题。
        if name.isEmpty || name.range(of: "^(Sheet|工作表)\\d*$", options: .regularExpression) != nil {
            return nil
        }
        return name
    }

    private static func textTitle(_ url: URL) -> (String, ManifestTitleOutcome) {
        guard let data = try? Data(contentsOf: url) else { return ("", .unreadable) }
        guard let text = decodeText(data) else { return ("", .unreadable) }
        // CRLF 在 Swift 里是一个 Character，跟 "\n" 不相等；不先归一化，整份文件会算成一行。
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let heading = trimmed.replacingOccurrences(
                of: "^#{1,6}\\s+", with: "", options: .regularExpression)
            let title = cleanTitle(heading)
            return title.isEmpty ? ("", .missing) : (title, .titled)
        }
        return ("", .missing)
    }

    /// UTF-8 优先，老的中文文本文件回落到 GB18030（导入侧用的是同一套判断）。
    static func decodeText(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) { return text }
        let gb = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String(data: data, encoding: String.Encoding(rawValue: gb))
    }

    private static func spotlightTitle(_ url: URL) -> String? {
        // Spotlight 已经读过 PDF 的元数据，不必自己解 PDF 结构；没索引到就当作没有。
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdls")
        process.arguments = ["-raw", "-name", "kMDItemTitle", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let raw = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "(null)" { return nil }
        return cleanTitle(trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
    }

    // MARK: - 小工具

    private static func unzippedPart(_ url: URL, _ part: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, part]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func xmlUnescape(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func cleanTitle(_ text: String) -> String {
        let collapsed = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return String(collapsed.prefix(200))
    }

    private static func csvField(_ text: String) -> String {
        guard text.contains(",") || text.contains("\"") || text.contains("\n") || text.contains("\r")
        else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func manifestFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }
}
