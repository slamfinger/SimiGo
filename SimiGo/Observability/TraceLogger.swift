import Foundation
import CryptoKit
import MLXLMCommon

// MARK: - Runtime Trace Policy

/// Default runtime trace policy: keep only events that materially help diagnose
/// admission, lifecycle, protocol, tool, cancellation and end-to-end performance.
///
/// The previous logger compacted every message through many String replacements
/// before writing it. That work happened even for noisy per-request KV/gate events.
/// Filtering first avoids both the formatting cost and the async queue traffic.
nonisolated enum RuntimeTracePolicy {
    private static let retainedPrefixes: [String] = [
        "[ADMISSION BLOCK]",
        "[ADMISSION]",
        "[CONTEXT SAFETY REJECT]",
        "[REQ ERROR]",
        "[REQ CANCEL]",
        "[REQ REJECT]",
        "[CANCEL REQUEST]",
        "[CANCELLED]",
        "[CXL]",
        "[TOOL FORWARD]",
        "[TOOL]",
        "[TPFAIL]",
        "[KVC REJECT]",
        "[KVC]",
        "[BRANCH DEGENERATION BLOCKED]",
        "[DEGEN-BLOCK]",
        "[PERF]",
        "[LIFECYCLE]",
        "[MEM]"
    ]

    static func shouldPersist(_ message: String) -> Bool {
        retainedPrefixes.contains { message.hasPrefix($0) }
    }

    static func compactTag(_ input: String) -> String {
        switch true {
        case input.hasPrefix("[CONTEXT SAFETY REJECT]"):
            return input.replacingOccurrences(of: "[CONTEXT SAFETY REJECT]", with: "[CTX-REJ]")
        case input.hasPrefix("[CANCEL REQUEST]"):
            return input.replacingOccurrences(of: "[CANCEL REQUEST]", with: "[CANCEL]")
        case input.hasPrefix("[CANCELLED]"):
            return input.replacingOccurrences(of: "[CANCELLED]", with: "[CXL]")
        case input.hasPrefix("[TOOL FORWARD]"):
            return input.replacingOccurrences(of: "[TOOL FORWARD]", with: "[TOOL]")
        case input.hasPrefix("[BRANCH DEGENERATION BLOCKED]"):
            return input.replacingOccurrences(of: "[BRANCH DEGENERATION BLOCKED]", with: "[DEGEN-BLOCK]")
        case input.hasPrefix("[PERFORMANCE]"):
            return input.replacingOccurrences(of: "[PERFORMANCE]", with: "[PERF]")
        default:
            return input
        }
    }
}

// MARK: - Dedicated File Trace Logger (~/.simigo/logs)

nonisolated final class RuntimeTraceLogger: @unchecked Sendable {
    static let shared = RuntimeTraceLogger()

    private let logFileURL: URL
    private let queue = DispatchQueue(label: "com.simigo.runtime.tracelogger", qos: .utility)
    private var fileHandle: FileHandle?
    private var isClosed = false

    private static let traceTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let simigoDir = home.appendingPathComponent(".simigo/logs", isDirectory: true)

        if !FileManager.default.fileExists(atPath: simigoDir.path) {
            try? FileManager.default.createDirectory(at: simigoDir, withIntermediateDirectories: true)
        }

        self.logFileURL = simigoDir.appendingPathComponent("native_mlx_trace.log")
    }

    deinit {
        queue.sync {
            try? fileHandle?.close()
            fileHandle = nil
            isClosed = true
        }
    }

    func reset() {
        queue.async { [weak self] in
            guard let self else { return }

            self.closeFileHandleLocked()
            let ts = self.timestampLocked()
            let header = "=== SimiGo NativeMLX Trace Log (Reset at \(ts)) ===\n"

            guard let data = header.data(using: .utf8) else { return }

            // 保持同一 inode；避免 tail -f 丢失跟踪目标。
            if let handle = try? FileHandle(forWritingTo: self.logFileURL) {
                handle.truncateFile(atOffset: 0)
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: self.logFileURL, options: .atomic)
            }

            self.isClosed = false
            self.openFileHandleLocked()
        }
    }

    func trace(_ message: String, session: String? = nil) {
        // 关键优化：先过滤，再创建异步写任务、时间戳和 Data。
        guard RuntimeTracePolicy.shouldPersist(message) else { return }

        queue.async { [weak self] in
            guard let self else { return }

            let ts = self.timestampLocked()
            let compacted = RuntimeTracePolicy.compactTag(message)
            let prefix = (session != nil && !session!.isEmpty)
                ? "[\(ts)][s=\(Self.compactSession(session!))]"
                : "[\(ts)]"

            let line = "\(prefix) \(compacted)\n"
            guard let data = line.data(using: .utf8) else { return }
            self.writeLocked(data)
        }
    }

    // 原始日志通道：不经过 RuntimeTracePolicy；用于外部进程 stdout/stderr。
    func raw(_ message: String, prefix: String = "") {
        queue.async { [weak self] in
            guard let self else { return }

            let normalized = message
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")

            let lines = normalized.split(separator: "\n", omittingEmptySubsequences: true)
            for line in lines {
                let text = String(line)
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

                let ts = self.timestampLocked()
                let output = prefix.isEmpty ? "[\(ts)] \(text)\n" : "[\(ts)] \(prefix)\(text)\n"
                guard let data = output.data(using: .utf8) else { continue }
                self.writeLocked(data)
            }
        }
    }

    func rawProcessOutput(_ data: Data, prefix: String = "[llama.cpp] ") {
        guard !data.isEmpty else { return }
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
        raw(text, prefix: prefix)
    }

    func flush() {
        queue.sync {
            fileHandle?.synchronizeFile()
        }
    }

    private static func compactSession(_ value: String) -> String {
        let parts = value.split(separator: "/", omittingEmptySubsequences: true)
        guard let rawSession = parts.dropFirst().first else {
            return String(value.suffix(6))
        }

        let session = String(rawSession)
        if let anonRange = session.range(of: "anon_") {
            return String(session[anonRange.upperBound...].prefix(6))
        }
        return String(session.suffix(6))
    }

    private func timestampLocked() -> String {
        Self.traceTimestampFormatter.string(from: Date())
    }

    private func openFileHandleLocked() {
        guard fileHandle == nil else { return }

        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            try? Data().write(to: logFileURL, options: .atomic)
        }

        guard let handle = try? FileHandle(forWritingTo: logFileURL) else { return }
        handle.seekToEndOfFile()
        fileHandle = handle
        isClosed = false
    }

    private func closeFileHandleLocked() {
        try? fileHandle?.close()
        fileHandle = nil
        isClosed = true
    }

    private func writeLocked(_ data: Data) {
        if isClosed || fileHandle == nil {
            openFileHandleLocked()
        }

        guard let handle = fileHandle else {
            guard let fallback = try? FileHandle(forWritingTo: logFileURL) else { return }
            fallback.seekToEndOfFile()
            do {
                try fallback.write(contentsOf: data)
            } catch {
                try? fallback.close()
                return
            }
            try? fallback.close()
            return
        }

        do {
            try handle.write(contentsOf: data)
        } catch {
            closeFileHandleLocked()
        }
    }
}

// MARK: - Sendable Helpers & JSON Conversion

nonisolated struct SendableBox<T>: @unchecked Sendable {
    nonisolated let value: T
    nonisolated init(_ value: T) { self.value = value }
}

nonisolated func mlxJSONToSimiGo(_ value: MLXLMCommon.JSONValue) -> JSONValue {
    switch value {
    case .null: return .null
    case .bool(let b): return .bool(b)
    case .int(let i): return .number(Double(i))
    case .double(let d): return .number(d)
    case .string(let s): return .string(s)
    case .array(let arr): return .array(arr.map(mlxJSONToSimiGo))
    case .object(let dict): return .object(dict.mapValues(mlxJSONToSimiGo))
    }
}

nonisolated func jsonObjectString(_ value: Any) -> String? {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
          let string = String(data: data, encoding: .utf8) else {
        return nil
    }
    return string
}

nonisolated func normalizedToolCallArguments(_ value: Any?) -> String {
    guard let value else { return "{}" }
    if value is NSNull { return "{}" }

    if let string = value as? String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let canonical = jsonObjectString(dictionary) else {
            return "{}"
        }
        return canonical
    }

    if let dictionary = value as? [String: Any] {
        return jsonObjectString(dictionary) ?? "{}"
    }

    if let dictionary = value as? [String: any Sendable] {
        return jsonObjectString(dictionary) ?? "{}"
    }

    return "{}"
}

nonisolated func normalizedHistoricalToolCalls(_ value: Any) throws -> [[String: Any]] {
    guard let calls = value as? [[String: Any]] else { return [] }

    var normalized: [[String: Any]] = []
    normalized.reserveCapacity(calls.count)

    for original in calls {
        var call = original
        guard let function = call["function"] as? [String: Any],
              let rawName = function["name"] as? String else {
            throw NativeMLXValidationError.invalidMessageHistory("Historical tool call is missing a valid function name")
        }

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw NativeMLXValidationError.invalidMessageHistory("Historical tool call has empty function name")
        }

        var normalizedFunction = function
        normalizedFunction["name"] = name
        let rawArguments: Any? = function["arguments"]

        if rawArguments == nil || rawArguments is NSNull {
            normalizedFunction["arguments"] = "{}"
        } else if let dict = rawArguments as? [String: Any],
                  let canonical = jsonObjectString(dict) {
            normalizedFunction["arguments"] = canonical
        } else if let string = rawArguments as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "{}" {
                normalizedFunction["arguments"] = "{}"
            } else if let data = trimmed.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data),
                      let dict = object as? [String: Any],
                      let canonical = jsonObjectString(dict) {
                normalizedFunction["arguments"] = canonical
            } else {
                throw NativeMLXValidationError.invalidMessageHistory("Tool call '\(name)' has malformed/unparseable arguments JSON")
            }
        } else {
            throw NativeMLXValidationError.invalidMessageHistory("Tool call '\(name)' arguments has invalid type")
        }

        call["type"] = (call["type"] as? String) ?? "function"
        call["function"] = normalizedFunction
        normalized.append(call)
    }

    return normalized
}

nonisolated func toolValueToSendable(_ value: JSONValue) -> any Sendable {
    switch value {
    case .null: return NSNull()
    case .bool(let v): return v
    case .number(let v): return v
    case .string(let v): return v
    case .array(let arr): return arr.map(toolValueToSendable)
    case .object(let dict): return dict.mapValues(toolValueToSendable)
    }
}

// MARK: - Observable Semantic Tool-State Fingerprint

nonisolated func canonicalizeSemanticPayload(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed == "{}" || trimmed == "[]" || trimmed == "null" {
        return "<EMPTY_STATE>"
    }
    if let data = trimmed.data(using: .utf8),
       let object = try? JSONSerialization.jsonObject(with: data) {
        return canonicalValue(object)
    }
    return trimmed
}

nonisolated func computeSemanticProgressHash(_ messages: [[String: Any]]) -> String {
    struct ToolResult {
        let callId: String
        let explicitName: String
        let content: String
    }

    var results: [ToolResult] = []
    var callIdToName: [String: String] = [:]

    for message in messages.reversed() {
        let role = (message["role"] as? String) ?? ""

        if role == "assistant" {
            if let calls = message["tool_calls"] as? [[String: Any]] {
                for call in calls {
                    let id = (call["id"] as? String) ?? ""
                    let function = (call["function"] as? [String: Any]) ?? [:]
                    let name = (function["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                    if !id.isEmpty && !name.isEmpty {
                        callIdToName[id] = name
                    }
                }
            }
            break
        }

        guard role == "tool" else { continue }

        let callId = (message["tool_call_id"] as? String) ?? ""
        let explicitName = (message["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let content: Any = message["content"] ?? ""

        results.append(
            ToolResult(
                callId: callId,
                explicitName: explicitName,
                content: canonicalizeSemanticPayload(coerceContentToString(content))
            )
        )
    }

    guard !results.isEmpty else {
        return "state_no_tool_results"
    }

    let payload = results.reversed().map { item -> String in
        let name = callIdToName[item.callId]
            ?? (item.explicitName.isEmpty ? (item.callId.isEmpty ? "unknown_tool" : item.callId) : item.explicitName)

        return "tool:\(name)|res:\(item.content)"
    }.joined(separator: "||")

    let digest = SHA256.hash(data: Data(payload.utf8))
    return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
}

// MARK: - Canonical Tool Representation

nonisolated func canonicalValue(_ value: Any) -> String {
    switch value {
    case let dict as [String: any Sendable]:
        return "{" + dict.keys.sorted().map { "\($0):\(canonicalValue(dict[$0]!))" }.joined(separator: ",") + "}"

    case let dict as [String: Any]:
        return "{" + dict.keys.sorted().map { "\($0):\(canonicalValue(dict[$0]!))" }.joined(separator: ",") + "}"

    case let array as [any Sendable]:
        return "[" + array.map(canonicalValue).joined(separator: ",") + "]"

    case let array as [Any]:
        return "[" + array.map(canonicalValue).joined(separator: ",") + "]"

    case let string as String:
        return "\"\(string)\""

    case let boolean as Bool:
        return boolean ? "true" : "false"

    case let number as NSNumber:
        return number.stringValue

    case _ as NSNull:
        return "null"

    default:
        return String(describing: value)
    }
}

nonisolated func makeToolSpecs(_ tools: [JSONValue]?) -> [[String: any Sendable]]? {
    guard let tools, !tools.isEmpty else { return nil }

    let specs = tools.compactMap { tool -> [String: any Sendable]? in
        guard case .object(let dict) = tool else { return nil }
        return dict.mapValues(toolValueToSendable)
    }

    guard !specs.isEmpty else { return nil }

    return specs.sorted {
        let lhsName = toolName($0)
        let rhsName = toolName($1)

        if lhsName != rhsName {
            return lhsName < rhsName
        }

        return canonicalValue($0) < canonicalValue($1)
    }
}

nonisolated func toolName(_ dict: [String: any Sendable]) -> String {
    if let function = dict["function"] as? [String: any Sendable],
       let name = function["name"] as? String {
        return name
    }

    return (dict["name"] as? String) ?? ""
}

// MARK: - Content Normalization

nonisolated func coerceContentToString(_ content: Any) -> String {
    if let string = content as? String {
        return string
    }

    if content is NSNull {
        return ""
    }

    if let parts = content as? [Any] {
        var text = ""

        for part in parts {
            guard let dict = part as? [String: Any] else { continue }

            let type = dict["type"] as? String
            if type == "text" || type == "input_text" || type == "output_text" || type == nil,
               let value = dict["text"] as? String {
                text += value
            }
        }

        if !text.isEmpty {
            return text
        }
    }

    if let dict = content as? [String: Any] {
        if let text = dict["text"] as? String {
            return text
        }

        if let json = jsonObjectString(dict) {
            return json
        }
    }

    if let number = content as? NSNumber {
        return number.stringValue
    }

    return String(describing: content)
}
