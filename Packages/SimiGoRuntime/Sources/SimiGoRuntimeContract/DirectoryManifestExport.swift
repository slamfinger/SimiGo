import Foundation

/// 目录清单导出：把一个人选定的目录扫一遍，写出一份 CSV，交给人在 Excel / WPS 里改标题。
///
/// 这是产品功能的一部分，不是外部脚本：编码（UTF-8 with BOM + CRLF）、跳过规则、
/// 标题从哪来，这些约定跟 IS 的身份模型绑在一起，散到外部脚本里迟早会走样。
///
/// 列：`root_id, relative_path, file_name, title, bytes, modified, summary, must_fix`
/// - `title` 默认就是文件名去后缀、再去掉「附件N：」这类前缀——人整理文件时文件名就是标题；
///   只有整份文件就是一个附件标签时，才用「主文件名 + 附件标签」。
/// - `summary` 留空，由人补或由 ES 后续写入。
public extension ESISDatabase {

    struct DirectoryManifestReport: Equatable, Sendable {
        public let files: Int
        public let titled: Int
        public let fromMainFile: Int
        public let mustFix: Int
        public let csvPath: String
    }

    enum ManifestTitleOutcome: Sendable {
        case fromFileName
        case fromMainFile
        /// 整份文件只剩一个附件标签，而同目录里认不出主文件——留给人补。
        case noMainFile

        /// 写进 CSV 的 `must_fix` 列：只有需要人动手的那一类才有值。
        var columnFlag: String {
            switch self {
            case .fromFileName, .fromMainFile: return ""
            case .noMainFile: return "no_main_file"
            }
        }
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
        let stamp = Self.manifestFormatter()
        let entries = Self.manifestWalk(
            root: root, maxDepth: maxDepth, skipping: outputRelative)
        let mainStems = Self.mainStemsByDirectory(entries)

        var rows: [[String]] = []
        var fromMainFile = 0
        var mustFix = 0
        for (relative, url) in entries {
            let directory = (relative as NSString).deletingLastPathComponent
            let (title, outcome) = Self.manifestTitle(
                ofFile: url.lastPathComponent, mainStem: mainStems[directory])
            if outcome == .fromMainFile { fromMainFile += 1 }
            if outcome == .noMainFile { mustFix += 1 }
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes?[.size] as? NSNumber)?.stringValue ?? ""
            let modified = (attributes?[.modificationDate] as? Date)
                .map { stamp.string(from: $0) } ?? ""
            rows.append([rootID, relative, url.lastPathComponent, title, size, modified, "",
                         outcome.columnFlag])
        }

        var text = "\u{FEFF}root_id,relative_path,file_name,title,bytes,modified,summary,must_fix\r\n"
        for row in rows {
            text += row.map(Self.csvField).joined(separator: ",") + "\r\n"
        }
        try Data(text.utf8).write(to: csvURL)
        return DirectoryManifestReport(files: rows.count, titled: rows.count - mustFix,
                                       fromMainFile: fromMainFile, mustFix: mustFix,
                                       csvPath: csvURL.path)
    }

    // MARK: - 标题

    /// 标题 = 文件名去后缀、去「附件N：」前缀；剩下空的时候用「主文件名 + 附件标签」。
    private static func manifestTitle(
        ofFile name: String, mainStem: String?
    ) -> (String, ManifestTitleOutcome) {
        let stem = (name as NSString).deletingPathExtension
        let (label, rest) = splitAttachmentPrefix(stem)
        if !rest.isEmpty { return (cleanTitle(rest), .fromFileName) }
        if let main = mainStem, let label {
            return (cleanTitle(main + label), .fromMainFile)
        }
        return (cleanTitle(stem), .noMainFile)
    }

    /// 拆开「(可选编号)附件(标签)(分隔符)」：`附件1：xx` / `641附件：xx` / `附件1.xx` / `附件10-1~10-4`。
    /// 半角冒号不作为分隔符认——文件名里出现它本身就是不规范的写法，剩下那截原样留给人看。
    private static func splitAttachmentPrefix(_ stem: String) -> (label: String?, rest: String) {
        let pattern = "^[0-9]{0,4}\\s*(附件(?:[0-9一二三四五六七八九十]+(?:[~～－-][0-9]+)*)?)([：、.．])?"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: stem, range: NSRange(stem.startIndex..., in: stem)),
              match.range.length > 0,
              let labelRange = Range(match.range(at: 1), in: stem)
        else { return (nil, stem) }
        let label = String(stem[labelRange])
        var rest = String(stem.dropFirst(match.range.length))
        while let first = rest.first, "：:、.． 　".contains(first) { rest.removeFirst() }
        rest = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        // 整份文件就叫「附件」：那就是个附件包，没有可拆的内容。
        if rest.isEmpty { return (label, rest) }
        // 「附件管理办法」这种是真名词，不是附件标签：既没有编号也没有分隔符，就不拆。
        let hasNumber = label.dropFirst("附件".count).isEmpty == false
        let hasSeparator = match.range(at: 2).length > 0
        guard hasNumber || hasSeparator else { return (nil, stem) }
        return (label, rest)
    }

    /// 同目录里认得出的主文件：只有一个不带附件标签的文件时，拿它当主文件名。
    private static func mainStemsByDirectory(_ entries: [(String, URL)]) -> [String: String] {
        var names: [String: [String]] = [:]
        for (relative, url) in entries {
            names[(relative as NSString).deletingLastPathComponent, default: []]
                .append(url.lastPathComponent)
        }
        var out: [String: String] = [:]
        for (directory, files) in names {
            let plain = files.filter { splitAttachmentPrefix(
                ($0 as NSString).deletingPathExtension).label == nil }
            if plain.count == 1 {
                out[directory] = (plain[0] as NSString).deletingPathExtension
            }
        }
        return out
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
            let url = root.appendingPathComponent(relative)
            let values = try? url.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            let name = (relative as NSString).lastPathComponent
            let isDirectory = values?.isDirectory == true
            let depth = relative.components(separatedBy: "/").count - 1
            // Office 锁文件、系统垃圾、隐藏目录（.git 之类）都不算文件，也不必往下走。
            // 注意：skipDescendants 跳的是"当前所在目录的剩余部分"，对文件调用会把同级后面
            // 的文件一起跳掉——这在本机 1332 个文件的真实目录上一次漏了 854 个，所以只对目录调。
            if name.hasPrefix(".") || name.hasPrefix("~$") || name == "Thumbs.db" {
                if isDirectory { enumerator.skipDescendants() }
                continue
            }
            if isDirectory {
                if depth >= maxDepth { enumerator.skipDescendants() }
                continue
            }
            if depth > maxDepth { continue }
            if relative == outputRelative { continue }
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else { continue }
            out.append((relative, url))
        }
        return out.sorted { $0.0 < $1.0 }
    }

    // MARK: - 小工具

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
