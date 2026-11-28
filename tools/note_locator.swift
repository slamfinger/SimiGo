// 构建: swiftc -O -parse-as-library tools/note_locator.swift -lsqlite3 -o note_locator
import Foundation
import SQLite3
import Darwin

private struct CLIError: Error {
    let message: String
    let exitCode: Int32
}

fileprivate enum Binding {
    case text(String)
    case double(Double)
    case int(Int)
}

@main
struct NoteLocator {
    private static let usageText = """
    用法: note_locator [--db PATH] <选择器> [--limit N] [--current-only] [--pretty]

    选择器（至少一个）:
      --kind KIND              kind 精确匹配（如 claim@L2）
      --kind-prefix PREFIX     kind 前缀匹配（如 claim@）
      --note-id ID             note_id 精确匹配（UUID，大小写不敏感）
      --note-id-prefix PREFIX  note_id 前缀匹配
      --after TIME             起始时间（含）：CFAbsoluteTime 数值或 ISO 8601
      --before TIME            截止时间（含）：同上

    其他:
      --db PATH                数据库路径（默认 ~/.simigo/simigo.sqlite3）
      --limit N                最多返回条数（默认 20，范围 1...500）
      --current-only           只返回未被后续 note supersede 的当前值
      --pretty                 JSON 缩进输出（默认单行）
      -h, --help               显示本帮助
    """

    static func main() {
        do {
            try run()
        } catch let error as CLIError {
            FileHandle.standardError.write(Data((error.message + "\n").utf8))
            exit(error.exitCode)
        } catch {
            FileHandle.standardError.write(Data(("note_locator: \(error)\n").utf8))
            exit(4)
        }
    }

    static func run() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains("-h") || args.contains("--help") {
            print(Self.usageText)
            return
        }
        var dbPath = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".simigo/simigo.sqlite3")
        var kind: String?
        var kindPrefix: String?
        var noteID: String?
        var noteIDPrefix: String?
        var after: Double?
        var before: Double?
        var limit = 20
        var currentOnly = false
        var pretty = false

        var index = 0
        func value(_ flag: String) throws -> String {
            index += 1
            guard index < args.count else {
                throw CLIError(message: "\(flag) 缺少值", exitCode: 2)
            }
            return args[index]
        }

        while index < args.count {
            switch args[index] {
            case "--db":
                dbPath = try value("--db")
            case "--kind":
                kind = try value("--kind")
            case "--kind-prefix":
                kindPrefix = try value("--kind-prefix")
            case "--note-id":
                noteID = try value("--note-id")
            case "--note-id-prefix":
                noteIDPrefix = try value("--note-id-prefix")
            case "--after":
                after = try parseTime(try value("--after"))
            case "--before":
                before = try parseTime(try value("--before"))
            case "--limit":
                let raw = try value("--limit")
                guard let parsed = Int(raw), (1...500).contains(parsed) else {
                    throw CLIError(message: "--limit 须为 1...500 的整数", exitCode: 2)
                }
                limit = parsed
            case "--current-only":
                currentOnly = true
            case "--pretty":
                pretty = true
            case "-h", "--help":
                print(Self.usageText)
                return
            default:
                throw CLIError(message: "未知参数: \(args[index])\n\n\(Self.usageText)", exitCode: 2)
            }
            index += 1
        }

        let hasSelector = kind != nil || kindPrefix != nil || noteID != nil
            || noteIDPrefix != nil || after != nil || before != nil
        guard hasSelector else {
            throw CLIError(
                message: "至少需要一个选择器（--kind/--kind-prefix/--note-id/--note-id-prefix/--after/--before）\n\n\(Self.usageText)",
                exitCode: 2)
        }
        for (flag, text) in [
            ("--kind", kind), ("--kind-prefix", kindPrefix),
            ("--note-id", noteID), ("--note-id-prefix", noteIDPrefix),
        ] {
            if let text, text.isEmpty {
                throw CLIError(message: "\(flag) 不能为空", exitCode: 2)
            }
        }

        var clauses: [String] = []
        var bindings: [Binding] = []
        if let kind {
            clauses.append("kind = ?")
            bindings.append(.text(kind))
        }
        if let kindPrefix {
            clauses.append("kind LIKE ? ESCAPE '\\'")
            bindings.append(.text(escapeLike(kindPrefix) + "%"))
        }
        if let noteID {
            clauses.append("note_id = ? COLLATE NOCASE")
            bindings.append(.text(noteID))
        }
        if let noteIDPrefix {
            clauses.append("note_id LIKE ? ESCAPE '\\'")
            bindings.append(.text(escapeLike(noteIDPrefix) + "%"))
        }
        if let after {
            clauses.append("CAST(recorded_at AS REAL) >= ?")
            bindings.append(.double(after))
        }
        if let before {
            clauses.append("CAST(recorded_at AS REAL) <= ?")
            bindings.append(.double(before))
        }
        if currentOnly {
            clauses.append(
                "note_id NOT IN (SELECT supersedes FROM project_notes WHERE supersedes IS NOT NULL)")
        }
        let whereSQL = clauses.joined(separator: " AND ")
        let sql = """
        SELECT note_id, kind, claim, supersedes, object_id, recorded_at,
               CASE WHEN note_id IN (
                   SELECT supersedes FROM project_notes WHERE supersedes IS NOT NULL
               ) THEN 0 ELSE 1 END AS is_current
          FROM project_notes
         WHERE \(whereSQL)
         ORDER BY CAST(recorded_at AS REAL) DESC, rowid DESC
         LIMIT ?;
        """
        let rows = try query(path: dbPath, sql: sql, bindings: bindings, limit: limit)
        let options: JSONSerialization.WritingOptions = pretty
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        let data = try JSONSerialization.data(withJSONObject: rows, options: options)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    static func escapeLike(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    static func parseTime(_ raw: String) throws -> Double {
        if let value = Double(raw) {
            return value
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) {
            return date.timeIntervalSinceReferenceDate
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: raw) {
            return date.timeIntervalSinceReferenceDate
        }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = TimeZone.current
        local.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = local.date(from: raw) {
            return date.timeIntervalSinceReferenceDate
        }
        throw CLIError(
            message: "无法解析时间: \(raw)（用 CFAbsoluteTime 数值或 ISO 8601）",
            exitCode: 2)
    }

    static func isoUTC(_ cfa: Double) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date(timeIntervalSinceReferenceDate: cfa))
    }

    static func cstString(_ cfa: Double) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            ?? TimeZone(secondsFromGMT: 8 * 3600)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date(timeIntervalSinceReferenceDate: cfa))
    }

    fileprivate static func query(
        path: String, sql: String, bindings: [Binding], limit: Int
    ) throws -> [[String: Any]] {
        var handle: OpaquePointer?
        let openCode = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil)
        guard openCode == SQLITE_OK, let db = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) }
                ?? "sqlite3_open_v2 rc=\(openCode)"
            if let handle { sqlite3_close(handle) }
            throw CLIError(message: "打开数据库失败（\(path)）: \(message)", exitCode: 3)
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let stmt = statement else {
            throw CLIError(
                message: "查询准备失败: \(String(cString: sqlite3_errmsg(db)))",
                exitCode: 4)
        }
        defer { sqlite3_finalize(stmt) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var bindIndex: Int32 = 1
        for binding in bindings {
            let code: Int32
            switch binding {
            case .text(let value):
                code = sqlite3_bind_text(stmt, bindIndex, value, -1, transient)
            case .double(let value):
                code = sqlite3_bind_double(stmt, bindIndex, value)
            case .int(let value):
                code = sqlite3_bind_int64(stmt, bindIndex, Int64(value))
            }
            guard code == SQLITE_OK else {
                throw CLIError(
                    message: "绑定参数失败: \(String(cString: sqlite3_errmsg(db)))",
                    exitCode: 4)
            }
            bindIndex += 1
        }
        guard sqlite3_bind_int64(stmt, bindIndex, Int64(limit)) == SQLITE_OK else {
            throw CLIError(
                message: "绑定 limit 失败: \(String(cString: sqlite3_errmsg(db)))",
                exitCode: 4)
        }

        func text(_ column: Int32) -> String? {
            guard let pointer = sqlite3_column_text(stmt, column) else { return nil }
            return String(cString: pointer)
        }

        var rows: [[String: Any]] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw CLIError(
                    message: "读取失败: \(String(cString: sqlite3_errmsg(db)))",
                    exitCode: 4)
            }
            let recordedAt = text(5) ?? ""
            let cfa = Double(recordedAt) ?? 0
            var row: [String: Any] = [
                "note_id": text(0) ?? "",
                "kind": text(1) ?? "",
                "claim": text(2) ?? "",
                "object_id": text(4) ?? "",
                "recorded_at": recordedAt,
                "recorded_at_iso": isoUTC(cfa),
                "recorded_at_cst": cstString(cfa),
                "is_current": sqlite3_column_int64(stmt, 6) != 0,
            ]
            row["supersedes"] = text(3) ?? NSNull()
            rows.append(row)
        }
        return rows
    }
}