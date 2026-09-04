import Foundation
import CryptoKit
import Network
import Synchronization
import MLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import Tokenizers
import Darwin

// (The rest of the file is unchanged)

private nonisolated struct RuntimeMemorySnapshot: Sendable {
    let residentBytes: UInt64
    let virtualBytes: UInt64
    let swapUsedBytes: UInt64?
    let swapTotalBytes: UInt64?
    let swapFreeBytes: UInt64?

    var residentGB: Double { Double(residentBytes) / 1024.0 / 1024.0 / 1024.0 }
    var virtualGB: Double { Double(virtualBytes) / 1024.0 / 1024.0 / 1024.0 }

    var swapUsedGB: Double? {
        guard let value = swapUsedBytes else { return nil }
        return Double(value) / 1024.0 / 1024.0 / 1024.0
    }

    var swapTotalGB: Double? {
        guard let value = swapTotalBytes else { return nil }
        return Double(value) / 1024.0 / 1024.0 / 1024.0
    }

    var swapFreeGB: Double? {
        guard let value = swapFreeBytes else { return nil }
        return Double(value) / 1024.0 / 1024.0 / 1024.0
    }
}

private nonisolated enum RuntimeMemoryProbe {
    static func snapshot() -> RuntimeMemorySnapshot {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { buffer in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), buffer, &count)
            }
        }

        let residentBytes: UInt64
        let virtualBytes: UInt64

        if result == KERN_SUCCESS {
            residentBytes = UInt64(info.resident_size)
            virtualBytes = UInt64(info.virtual_size)
        } else {
            residentBytes = 0
            virtualBytes = 0
        }

        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size

        let swapResult = sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0)
        if swapResult == 0 {
            return RuntimeMemorySnapshot(
                residentBytes: residentBytes,
                virtualBytes: virtualBytes,
                swapUsedBytes: UInt64(swapUsage.xsu_used),
                swapTotalBytes: UInt64(swapUsage.xsu_total),
                swapFreeBytes: UInt64(swapUsage.xsu_avail)
            )
        }

        return RuntimeMemorySnapshot(
            residentBytes: residentBytes,
            virtualBytes: virtualBytes,
            swapUsedBytes: nil,
            swapTotalBytes: nil,
            swapFreeBytes: nil
        )
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

            // ponytail: 必须原地截断保持同一 inode。.atomic 会替换文件，
            // 掐断 tail -f（含应用内置日志查看器 EnvManager），表现为"日志不再实时记录"。
            if let handle = try? FileHandle(forWritingTo: self.logFileURL) {
                handle.truncateFile(atOffset: 0)
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                // 首次创建，尚无 tail 跟随者，原子写入即可
                try? data.write(to: self.logFileURL, options: .atomic)
            }

            self.isClosed = false
            self.openFileHandleLocked()
        }
    }

    func trace(_ message: String, session: String? = nil) {
        queue.async { [weak self] in
            guard let self else { return }

            let ts = self.timestampLocked()
            let compacted = self.compactTraceMessage(message)
            let prefix = (session != nil && !session!.isEmpty) ? "[\(ts)][s=\(Self.compactSession(session!))]" : "[\(ts)]"

            let line = "\(prefix) \(compacted)\n"
            guard let data = line.data(using: .utf8) else { return }
            self.writeLocked(data)
        }
    }

    // 原始日志通道：不经过 compactTraceMessage。用于外部进程（llama.cpp）的 stdout/stderr。
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

    // Process Pipe 专用接口。
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

    private func compactTraceMessage(_ input: String) -> String {
        var text = input

        let tags: [(String, String)] = [
            ("[MEMORY SNAPSHOT]", "[MEM]"),
            ("[OBSERVATION SUMMARY]", "[SUM]"),
            ("[GENERATION GATE GRANTED]", "[GATE]"),
            ("[GENERATION START]", "[GEN]"),
            ("[TOOL COMPLETED]", "[TOOL]"),
            ("[TOOL DEDUP]", "[TDUP]"),
            ("[TOOL DROP]", "[TDROP]"),
            ("[RAW TOOL XML]", "[RAWTOOL]"),
            ("[STRUCTURED TOOL]", "[STOOL]"),
            ("[TOOL PARSE FAIL]", "[TPFAIL]"),
            ("[KV DIAGNOSTIC]", "[KVD]"),
            ("[KV SELECTED]", "[KVS]"),
            ("[KV COPY]", "[KCP]"),
            ("[KV SELECT]", "[KVR]"),
            ("[KV MISS]", "[KVM]"),
            ("[KV COMMIT]", "[KVC]"),
            ("[COLD PREFILL]", "[COLD]"),
            ("[PREFILL WAIT]", "[PWAIT]"),
            ("[BRANCH DEGENERATION BLOCKED]", "[DEGEN-BLOCK]"),
            ("[DEGEN]", "[DEG]"),
            ("[PERFORMANCE]", "[PERF]"),
            ("[CANCEL REQUEST]", "[CANCEL]"),
            ("[CANCELLED]", "[CXL]"),
            ("[REQUEST]", "[REQ]"),
            ("[CONTEXT SAFETY REJECT]", "[CTX-REJ]")
        ]

        for (from, to) in tags {
            text = text.replacingOccurrences(of: from, with: to)
        }

        let fields: [(String, String)] = [
            ("logicalBranch=", "br="),
            ("logicalBranchId=", "br="),
            ("request=", "r="),
            ("requestId=", "r="),
            ("agent=", "a="),
            ("session=", "s="),
            ("branch=", "br="),
            ("selectedIndex=", "i="),
            ("rawCommonPrefix=", "rawcp="),
            ("commonPrefix=", "cp="),
            ("cachedTokens=", "cache="),
            ("tokensGenerated=", "tok="),
            ("physicalTokens=", "ktok="),
            ("promptTokens=", "p="),
            ("generated=", "g="),
            ("globalRevisions=", "revs="),
            ("toolFingerprint=", "tf="),
            ("prefillQueueWait=", "qw="),
            ("ToolCallDetected=", "tool="),
            ("ToolCallsForwarded=", "fwd="),
            ("rawToolCallDetected=", "raw="),
            ("structuredToolCalls=", "stool="),
            ("SelectedCachedTokens=", "cache="),
            ("SelectedCommonPrefix=", "cp="),
            ("PromptTokens=", "p="),
            ("Branches=", "revs="),
            ("TTFT(Prefill)=", "ttft="),
            ("Prefill=", "pre="),
            ("Decode=", "dec="),
            ("Total=", "dur="),
            ("Delta=", "d="),
            ("Tokens=", "tok="),
            ("time=", "t=")
        ]

        for (from, to) in fields {
            text = text.replacingOccurrences(of: from, with: to)
        }

        text = compactRequestFields(text)
        text = compactSessionFields(text)
        text = compactHexFields(text)
        text = text.replacingOccurrences(of: "disableThinking=", with: "thinkOff=")
        text = text.replacingOccurrences(of: "messagesCount=", with: "m=")
        text = text.replacingOccurrences(of: "toolsCount=", with: "tools=")
        text = text.replacingOccurrences(of: "maxTokens=", with: "max=")
        text = text.replacingOccurrences(of: "activeRequests=", with: "q=")
        text = text.replacingOccurrences(of: "activeGenerations=", with: "gen=")
        text = text.replacingOccurrences(of: "generatingSessions=", with: "gs=")
        text = text.replacingOccurrences(of: "physicalRevisions=", with: "rev=")
        text = text.replacingOccurrences(of: "physicalTokens=", with: "ktok=")
        text = text.replacingOccurrences(of: "sessions=", with: "sess=")
        text = text.replacingOccurrences(of: "source=runtime-global", with: "src=G")
        text = text.replacingOccurrences(of: "source=global", with: "src=G")
        text = text.replacingOccurrences(of: "invariant=OK", with: "ok")
        text = text.replacingOccurrences(of: "action=drop_duplicate", with: "act=dup")
        text = text.replacingOccurrences(of: "reason=noGlobalRevision", with: "why=noRev")
        text = text.replacingOccurrences(of: "reason=toolFingerprintMismatch", with: "why=toolFP")
        text = text.replacingOccurrences(of: "reason=noCommonPrefix", with: "why=noCP")
        text = text.replacingOccurrences(of: "reason=evictedPhysicalKV", with: "why=evicted")
        text = text.replacingOccurrences(of: "reason=noUsableLineage", with: "why=noLineage")
        text = text.replacingOccurrences(of: "reason=empty_tool_name", with: "why=noName")
        text = text.replacingOccurrences(of: "prefillQueueWait", with: "qw")

        return text
    }

    private func compactSessionFields(_ input: String) -> String {
        var result = input
        var searchStart = result.startIndex

        while let range = result.range(of: "s=", range: searchStart..<result.endIndex) {
            let valueStart = range.upperBound
            let valueEnd = result[valueStart...].firstIndex(where: { $0 == " " || $0 == "," || $0 == "|" }) ?? result.endIndex
            let raw = String(result[valueStart..<valueEnd])

            if raw.count > 8 {
                let short: String
                if let anon = raw.range(of: "anon_") {
                    short = String(raw[anon.upperBound...].prefix(6))
                } else {
                    short = String(raw.suffix(6))
                }
                result.replaceSubrange(valueStart..<valueEnd, with: short)
                searchStart = result.index(valueStart, offsetBy: min(short.count, result.distance(from: valueStart, to: result.endIndex)))
            } else {
                searchStart = valueEnd
            }
        }
        return result
    }

    private func compactHexFields(_ input: String) -> String {
        var result = input

        for key in ["rev=", "tf=", "revision=", "progressHash="] {
            var searchStart = result.startIndex

            while let range = result.range(of: key, range: searchStart..<result.endIndex) {
                let valueStart = range.upperBound
                let valueEnd = result[valueStart...].firstIndex(where: { $0 == " " || $0 == "," || $0 == "|" || $0 == "]" }) ?? result.endIndex
                let raw = String(result[valueStart..<valueEnd])
                let isHex = raw.count >= 12 && raw.allSatisfy { $0.isHexDigit }

                if isHex {
                    result.replaceSubrange(valueStart..<valueEnd, with: String(raw.prefix(6)))
                    searchStart = result.index(valueStart, offsetBy: min(6, result.distance(from: valueStart, to: result.endIndex)))
                } else {
                    searchStart = valueEnd
                }
            }
        }
        return result
    }

    private func compactRequestFields(_ input: String) -> String {
        var result = input
        let keys = ["r=", "request="]

        for key in keys {
            var searchStart = result.startIndex

            while let range = result.range(of: key, range: searchStart..<result.endIndex) {
                let valueStart = range.upperBound
                let valueEnd = result[valueStart...].firstIndex(where: { $0 == " " || $0 == "," || $0 == "|" }) ?? result.endIndex
                let raw = String(result[valueStart..<valueEnd])

                if raw.count > 8 {
                    let cleaned = raw.replacingOccurrences(of: "req-", with: "")
                    let short = String(cleaned.prefix(6))
                    result.replaceSubrange(valueStart..<valueEnd, with: short)
                    searchStart = result.index(valueStart, offsetBy: min(short.count, result.distance(from: valueStart, to: result.endIndex)))
                } else {
                    searchStart = valueEnd
                }
            }
        }
        return result
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

private nonisolated struct SendableBox<T>: @unchecked Sendable {
    nonisolated let value: T
    nonisolated init(_ value: T) { self.value = value }
}

private nonisolated func mlxJSONToSimiGo(_ value: MLXLMCommon.JSONValue) -> JSONValue {
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

private nonisolated func jsonObjectString(_ value: Any) -> String? {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
          let string = String(data: data, encoding: .utf8) else {
        return nil
    }
    return string
}

private nonisolated func normalizedToolCallArguments(_ value: Any?) -> String {
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

private nonisolated func normalizedHistoricalToolCalls(_ value: Any) throws -> [[String: Any]] {
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

private nonisolated func toolValueToSendable(_ value: JSONValue) -> any Sendable {
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

private nonisolated func canonicalizeSemanticPayload(_ text: String) -> String {
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

private nonisolated func computeSemanticProgressHash(_ messages: [[String: Any]]) -> String {
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

private nonisolated func canonicalValue(_ value: Any) -> String {
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

private nonisolated func makeToolSpecs(_ tools: [JSONValue]?) -> [[String: any Sendable]]? {
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

private nonisolated func toolName(_ dict: [String: any Sendable]) -> String {
    if let function = dict["function"] as? [String: any Sendable],
       let name = function["name"] as? String {
        return name
    }

    return (dict["name"] as? String) ?? ""
}

// MARK: - Content Normalization

private nonisolated func coerceContentToString(_ content: Any) -> String {
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

// MARK: - Raw <tool_call> Stream Fallback Parser

private struct RawToolCallParserFailure: Error, LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

nonisolated private final class RawToolCallStreamParser: @unchecked Sendable {
    private static let openTag = "<tool_call>"
    private static let closeTag = "</tool_call>"
    private var buffer = ""
    private var insideToolCall = false
    private(set) var rawToolCallDetected = false
    private(set) var failure: RawToolCallParserFailure?
    private static let openHoldback = openTag.count - 1

    nonisolated func feed(_ text: String, onText: (String) -> Void, onToolCall: (ParsedToolCall) -> Void) {
        guard !text.isEmpty, failure == nil else { return }

        buffer.append(contentsOf: text)

        while failure == nil {
            if insideToolCall {
                guard let closeRange = buffer.range(of: Self.closeTag) else { return }

                let body = String(buffer[..<closeRange.lowerBound])
                buffer = String(buffer[closeRange.upperBound...])
                rawToolCallDetected = true

                guard let call = parseToolCall(body) else {
                    failure = RawToolCallParserFailure(message: "Malformed raw <tool_call> payload")
                    buffer = ""
                    insideToolCall = false
                    return
                }

                onToolCall(call)
                insideToolCall = false
                continue
            }

            guard let openRange = buffer.range(of: Self.openTag) else {
                if buffer.count > Self.openHoldback {
                    let outputCount = buffer.count - Self.openHoldback
                    let splitIndex = buffer.index(buffer.startIndex, offsetBy: outputCount)
                    let output = String(buffer[..<splitIndex])
                    buffer = String(buffer[splitIndex...])

                    if !output.isEmpty {
                        onText(output)
                    }
                }

                return
            }

            let before = String(buffer[..<openRange.lowerBound])

            if !before.isEmpty {
                onText(before)
            }

            buffer = String(buffer[openRange.upperBound...])
            insideToolCall = true
            rawToolCallDetected = true
        }
    }

    nonisolated func flush(onText: (String) -> Void) {
        guard failure == nil else { return }

        if insideToolCall {
            failure = RawToolCallParserFailure(message: "Incomplete raw <tool_call> at end of generation")
            buffer = ""
            insideToolCall = false
            return
        }

        if !buffer.isEmpty {
            onText(buffer)
        }

        buffer = ""
    }

    private nonisolated func parseToolCall(_ rawBody: String) -> ParsedToolCall? {
        let trimmed = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let rawName = dictionary["name"] as? String else {
            return nil
        }

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty, dictionary.keys.contains("arguments") else {
            return nil
        }

        let rawArguments = dictionary["arguments"]
        let argumentDictionary: [String: Any]

        if let dictionary = rawArguments as? [String: Any] {
            argumentDictionary = dictionary
        } else if let argumentString = rawArguments as? String {
            let trimmedArguments = argumentString.trimmingCharacters(in: .whitespacesAndNewlines)

            guard let argumentData = trimmedArguments.data(using: .utf8),
                  let argumentObject = try? JSONSerialization.jsonObject(with: argumentData),
                  let dictionary = argumentObject as? [String: Any] else {
                return nil
            }

            argumentDictionary = dictionary
        } else {
            return nil
        }

        guard JSONSerialization.isValidJSONObject(argumentDictionary),
              let argumentData = try? JSONSerialization.data(withJSONObject: argumentDictionary, options: [.sortedKeys]),
              let normalizedArguments = try? JSONDecoder().decode([String: JSONValue].self, from: argumentData) else {
            return nil
        }

        let callId: String

        if let rawId = dictionary["id"] as? String,
           !rawId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            callId = rawId
        } else {
            callId = UUID().uuidString
        }

        return ParsedToolCall(id: callId, name: name, arguments: normalizedArguments)
    }
}

// MARK: - Stream Token Filter

nonisolated final class StreamTokenFilter: @unchecked Sendable {
    private static let thinkStartTags = ["<think>", "<|start_of_think|>", "<thought>", "<|thought|>"]
    private static let thinkEndTags = ["</think>", "<|end_of_think|>", "</thought>", "<|end_of_thought|>"]

    private static let knownSpecialTokens: Set<String> = [
        "<|im_start|>", "<|im_end|>", "<|endoftext|>", "<|assistant|>",
        "<|user|>", "<|system|>", "<|tool|>", "<|eot_id|>",
        "<|eom_id|>", "<|begin_of_text|>", "<|end_of_text|>",
        "<|start_header_id|>", "<|end_header_id|>"
    ]

    private var buffer = ""
    private var pendingText = ""
    private var isInsideThink = false
    private let disableThinking: Bool
    private static let maxPendingCharacters = 128

    nonisolated init(disableThinking: Bool = false) {
        self.disableThinking = disableThinking
    }

    // MARK: Feed

    nonisolated func feed(_ text: String, onChunk: (String) -> Void) {
        guard !text.isEmpty else { return }

        buffer.append(contentsOf: text)

        while true {
            if isInsideThink {
                if let endRange = earliestRange(in: buffer, tags: Self.thinkEndTags) {
                    buffer = String(buffer[endRange.upperBound...])
                    isInsideThink = false
                    continue
                }

                let holdback = maxTagLength(Self.thinkEndTags)

                if buffer.count > holdback {
                    buffer = String(buffer.suffix(holdback))
                }

                return
            }

            if let startRange = earliestRange(in: buffer, tags: Self.thinkStartTags) {
                let before = String(buffer[..<startRange.lowerBound])

                if !before.isEmpty {
                    pendingText.append(contentsOf: Self.sanitize(before))
                    emitStableText(onChunk: onChunk, force: false)
                }

                buffer = String(buffer[startRange.upperBound...])
                isInsideThink = true
                continue
            }

            if let endRange = earliestRange(in: buffer, tags: Self.thinkEndTags) {
                let before = String(buffer[..<endRange.lowerBound])

                if !before.isEmpty {
                    pendingText.append(contentsOf: Self.sanitize(before))
                    emitStableText(onChunk: onChunk, force: false)
                }

                buffer = String(buffer[endRange.upperBound...])
                continue
            }

            let holdback = max(maxTagLength(Self.thinkStartTags), maxTagLength(Self.thinkEndTags))

            if buffer.count > holdback {
                let outputCount = buffer.count - holdback
                let splitIndex = buffer.index(buffer.startIndex, offsetBy: outputCount)
                let output = String(buffer[..<splitIndex])
                buffer = String(buffer[splitIndex...])

                if !output.isEmpty {
                    pendingText.append(contentsOf: Self.sanitize(output))
                    emitStableText(onChunk: onChunk, force: false)
                }
            }

            return
        }
    }

    // MARK: Flush

    nonisolated func flush(onChunk: (String) -> Void) {
        if isInsideThink {
            buffer = ""
            pendingText = ""
            isInsideThink = false
            return
        }

        if !buffer.isEmpty {
            let cleaned = Self.removeThinkTagsAndSpecialTokens(buffer)

            if !cleaned.isEmpty {
                pendingText.append(contentsOf: cleaned)
            }
        }

        buffer = ""
        emitStableText(onChunk: onChunk, force: true)
    }

    // MARK: Stable Text Emission

    private nonisolated func emitStableText(onChunk: (String) -> Void, force: Bool) {
        guard !pendingText.isEmpty else { return }

        if force {
            let output = pendingText
            pendingText = ""

            if !output.isEmpty {
                onChunk(output)
            }

            return
        }

        while !pendingText.isEmpty {
            guard let boundary = findSafeBoundary(
                in: pendingText,
                allowPartial: pendingText.count > Self.maxPendingCharacters
            ) else {
                return
            }

            let candidate = String(pendingText[..<boundary])
            pendingText = String(pendingText[boundary...])

            if !candidate.isEmpty {
                onChunk(candidate)
            }
        }
    }

    // MARK: Safe Boundary

    private nonisolated func findSafeBoundary(in text: String, allowPartial: Bool) -> String.Index? {
        guard !text.isEmpty else { return nil }

        var bestIndex: String.Index?

        for index in text.indices {
            let char = text[index]
            let nextIndex = text.index(after: index)

            if char.isWhitespace || char.isNewline || Self.isPunctuationOrSymbol(char) {
                bestIndex = nextIndex
            } else if let scalar = char.unicodeScalars.first, Self.isCJKCharacter(scalar) {
                bestIndex = nextIndex
            }
        }

        if let bestIndex {
            return bestIndex
        }

        if allowPartial && text.count >= Self.maxPendingCharacters {
            return text.index(text.startIndex, offsetBy: Self.maxPendingCharacters)
        }

        return nil
    }

    // MARK: Tag Search

    private nonisolated func earliestRange(in text: String, tags: [String]) -> Range<String.Index>? {
        var result: Range<String.Index>?

        for tag in tags {
            guard let candidate = text.range(of: tag) else { continue }

            if result == nil || candidate.lowerBound < result!.lowerBound {
                result = candidate
            }
        }

        return result
    }

    private nonisolated func maxTagLength(_ tags: [String]) -> Int {
        tags.map(\.count).max() ?? 0
    }

    // MARK: Character Helpers

    private nonisolated static func isCJKCharacter(_ scalar: UnicodeScalar) -> Bool {
        let value = scalar.value

        return (0x4E00...0x9FFF).contains(value) ||
               (0x3400...0x4DBF).contains(value) ||
               (0x20000...0x2A6DF).contains(value) ||
               (0x3040...0x309F).contains(value) ||
               (0x30A0...0x30FF).contains(value) ||
               (0xAC00...0xD7AF).contains(value)
    }

    private nonisolated static func isPunctuationOrSymbol(_ char: Character) -> Bool {
        let symbols = ",.!?;:，。！？；：、\"'()[]{}（）《》〈〉【】『』“”‘’—–…·`"
        return symbols.contains(char)
    }

    // MARK: Sanitization

    private nonisolated static func sanitize(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        return removeThinkTagsAndSpecialTokens(text)
    }

    private nonisolated static func removeThinkTagsAndSpecialTokens(_ input: String) -> String {
        var result = input

        for token in knownSpecialTokens {
            result = result.replacingOccurrences(of: token, with: "")
        }

        for tag in thinkStartTags {
            result = result.replacingOccurrences(of: tag, with: "")
        }

        for tag in thinkEndTags {
            result = result.replacingOccurrences(of: tag, with: "")
        }

        return result
    }
}

// MARK: - Physical Token Recorder & Iterator

private nonisolated final class PhysicalTokenRecorder: @unchecked Sendable {
    private var tokens: [Int] = []

    nonisolated init() {}

    nonisolated func append(_ token: Int) {
        tokens.append(token)
    }

    nonisolated func discardLastIfPresent() {
        _ = tokens.popLast()
    }

    nonisolated func snapshot() -> [Int] {
        tokens
    }
}

private nonisolated struct PhysicalLedgerTokenIterator: TokenIteratorProtocol, @unchecked Sendable {
    private var base: TokenIterator
    private let recorder: PhysicalTokenRecorder

    nonisolated init(base: TokenIterator, recorder: PhysicalTokenRecorder) {
        self.base = base
        self.recorder = recorder
    }

    nonisolated var maxTokens: Int? { base.maxTokens }
    nonisolated var tokenCount: Int { base.tokenCount }
    nonisolated var promptPrefillTime: TimeInterval { base.promptPrefillTime }
    nonisolated var speculativeDecodingTelemetry: SpeculativeDecodingTelemetry? { base.speculativeDecodingTelemetry }

    nonisolated mutating func discardGeneratedToken() {
        recorder.discardLastIfPresent()
        base.discardGeneratedToken()
    }

    nonisolated mutating func next() -> Int? {
        guard let token = base.next() else { return nil }
        recorder.append(token)
        return token
    }
}

// MARK: - Agent / Session / Branch Identity

private nonisolated struct AgentExecutionKey: Hashable, Sendable {
    let agentId: String
    let sessionId: String
    let logicalBranchId: String

    init(agentId: String?, sessionId: String, logicalBranchId: String) throws {
        self.agentId = Self.normalize(agentId) ?? "default"

        guard let session = Self.normalize(sessionId) else {
            throw NativeMLXValidationError.invalidExecutionKey("sessionId cannot be empty")
        }

        guard let branch = Self.normalize(logicalBranchId) else {
            throw NativeMLXValidationError.invalidExecutionKey("logicalBranchId cannot be empty")
        }

        self.sessionId = session
        self.logicalBranchId = branch
    }

    var storageKey: String { "\(agentId)/\(sessionId)" }
    var gateKey: String { "\(agentId)/\(sessionId)/\(logicalBranchId)" }
    var traceKey: String { gateKey }

    private static func normalize(_ value: String?) -> String? {
        guard let value else { return nil }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.count <= 128 {
            return trimmed
        }

        let prefix = String(trimmed.prefix(64))
        let hash = SHA256.hash(data: Data(trimmed.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        return "\(prefix)_\(hash.prefix(16))"
    }

    static func resolve(agentId: String?, sessionId: String, logicalBranchId: String) throws -> AgentExecutionKey {
        try AgentExecutionKey(agentId: agentId, sessionId: sessionId, logicalBranchId: logicalBranchId)
    }
}

private enum NativeMLXValidationError: Error, LocalizedError, Sendable {
    case invalidExecutionKey(String)
    case invalidMessageHistory(String)
    case contextDemandExceeded(Int, Int)

    var errorDescription: String? {
        switch self {
        case .invalidExecutionKey(let message), .invalidMessageHistory(let message):
            return message

        case .contextDemandExceeded(let demand, let budget):
            return "Effective context demand (\(demand)) exceeds safety budget (\(budget)). L1 Agent Compaction required."
        }
    }
}

private enum GateWaiterState {
    case waiting
    case granted
    case cancelled
}

// MARK: - Tier 1: Runtime Lifecycle Gate

private actor RuntimeLifecycleGate {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
        var state: GateWaiterState = .waiting
    }

    private var busy = false
    private var waiters: [Waiter] = []

    func withLock<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try Task.checkCancellation()

        guard await acquire() else {
            throw CancellationError()
        }

        defer {
            release()
        }

        try Task.checkCancellation()
        return try await operation()
    }

    func withLockVoid(_ operation: @Sendable () async -> Void) async {
        guard !Task.isCancelled else { return }
        guard await acquire() else { return }

        defer {
            release()
        }

        guard !Task.isCancelled else { return }
        await operation()
    }

    private func acquire() async -> Bool {
        if Task.isCancelled {
            return false
        }

        if !busy {
            busy = true
            return true
        }

        let waiterId = UUID()

        return await withTaskCancellationHandler(
            operation: {
                await withCheckedContinuation { continuation in
                    enqueue(id: waiterId, continuation: continuation)
                }
            },
            onCancel: {
                Task {
                    await self.cancel(id: waiterId)
                }
            }
        )
    }

    private func enqueue(id: UUID, continuation: CheckedContinuation<Bool, Never>) {
        if Task.isCancelled {
            continuation.resume(returning: false)
            return
        }

        waiters.append(Waiter(id: id, continuation: continuation))
    }

    private func cancel(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }

        var waiter = waiters.remove(at: index)
        guard case .waiting = waiter.state else { return }

        waiter.state = .cancelled
        waiter.continuation.resume(returning: false)
    }

    private func release() {
        while !waiters.isEmpty {
            var waiter = waiters.removeFirst()
            guard case .waiting = waiter.state else { continue }

            waiter.state = .granted
            waiter.continuation.resume(returning: true)
            return
        }

        busy = false
    }
}

// MARK: - Tier 2: Session / Branch Generation Gate

private actor SessionGenerationGate {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
        var state: GateWaiterState = .waiting
    }

    private var activeKeys: Set<AgentExecutionKey> = []
    private var waiters: [AgentExecutionKey: [Waiter]] = [:]
    private var isShuttingDown = false
    private var drainContinuations: [CheckedContinuation<Void, Never>] = []

    func withExclusive<T: Sendable>(_ key: AgentExecutionKey, operation: @Sendable () async throws -> T) async throws -> T {
        try Task.checkCancellation()

        guard await acquire(key) else {
            throw CancellationError()
        }

        defer {
            release(key)
        }

        try Task.checkCancellation()
        return try await operation()
    }

    private func acquire(_ key: AgentExecutionKey) async -> Bool {
        if isShuttingDown || Task.isCancelled {
            return false
        }

        if activeKeys.insert(key).inserted {
            return true
        }

        let waiterId = UUID()

        return await withTaskCancellationHandler(
            operation: {
                await withCheckedContinuation { continuation in
                    enqueue(id: waiterId, key: key, continuation: continuation)
                }
            },
            onCancel: {
                Task {
                    await self.cancel(id: waiterId, key: key)
                }
            }
        )
    }

    private func enqueue(id: UUID, key: AgentExecutionKey, continuation: CheckedContinuation<Bool, Never>) {
        if isShuttingDown || Task.isCancelled {
            continuation.resume(returning: false)
            return
        }

        waiters[key, default: []].append(
            Waiter(id: id, continuation: continuation)
        )
    }

    private func cancel(id: UUID, key: AgentExecutionKey) {
        guard var queue = waiters[key],
              let index = queue.firstIndex(where: { $0.id == id }) else {
            return
        }

        var waiter = queue.remove(at: index)

        if queue.isEmpty {
            waiters.removeValue(forKey: key)
        } else {
            waiters[key] = queue
        }

        guard case .waiting = waiter.state else { return }

        waiter.state = .cancelled
        waiter.continuation.resume(returning: false)
    }

    private func release(_ key: AgentExecutionKey) {
        if isShuttingDown {
            activeKeys.remove(key)
            notifyDrainIfNeeded()
            return
        }

        guard var queue = waiters[key], !queue.isEmpty else {
            activeKeys.remove(key)
            notifyDrainIfNeeded()
            return
        }

        while !queue.isEmpty {
            var waiter = queue.removeFirst()

            if queue.isEmpty {
                waiters.removeValue(forKey: key)
            } else {
                waiters[key] = queue
            }

            guard case .waiting = waiter.state else { continue }

            waiter.state = .granted
            activeKeys.insert(key)
            waiter.continuation.resume(returning: true)
            return
        }

        activeKeys.remove(key)
        notifyDrainIfNeeded()
    }

    func beginShutdown() {
        isShuttingDown = true

        for key in waiters.keys {
            guard let queue = waiters[key] else { continue }

            for var waiter in queue {
                guard case .waiting = waiter.state else { continue }

                waiter.state = .cancelled
                waiter.continuation.resume(returning: false)
            }
        }

        waiters.removeAll()
        notifyDrainIfNeeded()
    }

    func awaitDrain() async {
        if activeKeys.isEmpty {
            return
        }

        await withCheckedContinuation { continuation in
            if activeKeys.isEmpty {
                continuation.resume()
            } else {
                drainContinuations.append(continuation)
            }
        }
    }

    private func notifyDrainIfNeeded() {
        guard activeKeys.isEmpty, !drainContinuations.isEmpty else { return }

        let continuations = drainContinuations
        drainContinuations.removeAll()

        for continuation in continuations {
            continuation.resume()
        }
    }
}

// MARK: - Branch Degeneration State

private struct BranchDegenerationState: Sendable {
    struct Probe: Sendable {
        let signatures: [String]
        let progress: String
        let projected: Int
        let blocked: Bool
    }

    var lastSignatures: [String] = []
    var lastProgress: String?
    var consecutive = 0
    var round = 0

    func preview(signatures: [String], progress: String, threshold: Int = 3) -> Probe {
        let projected = (signatures == lastSignatures && progress == lastProgress) ? (consecutive + 1) : 1

        return Probe(
            signatures: signatures,
            progress: progress,
            projected: projected,
            blocked: projected >= threshold
        )
    }

    mutating func commitForwarded(_ probe: Probe) {
        round += 1
        lastSignatures = probe.signatures
        lastProgress = probe.progress
        consecutive = probe.projected
    }

    mutating func recordBlocked(_ probe: Probe) {
        commitForwarded(probe)
    }

    mutating func resetOnPlain() {
        round += 1
        lastSignatures.removeAll(keepingCapacity: false)
        lastProgress = nil
        consecutive = 0
    }
}

private struct LogicalBranchState: Sendable {
    let logicalBranchId: String
    var toolFingerprint: String
    var degenerationState = BranchDegenerationState()
    var lastActive = Date()
}

// MARK: - Runtime-global Physical KV Revision

private struct PhysicalKVRevision: @unchecked Sendable {
    var id: String
    var logicalBranchId: String
    var toolFingerprint: String
    var physicalTokens: [Int]
    var kvCache: [any KVCache]
    var lastActive: Date

    var cacheTokenCount: Int { physicalTokens.count }
    var resident: Bool { !kvCache.isEmpty }
    var estimatedResidentBytes: UInt64 { resident ? UInt64(physicalTokens.count) * 128 * 1024 : 0 }

    mutating func releasePhysicalMemory() {
        for kv in kvCache {
            _ = kv.trim(physicalTokens.count)
        }

        kvCache.removeAll(keepingCapacity: false)
    }
}

private struct SessionLogicalState: Sendable {
    var logicalBranches: [String: LogicalBranchState] = [:]
    var lastActive: Date = Date()
}

// MARK: - Compact Log Helpers

private nonisolated func compactTokenCount(_ count: Int) -> String {
    if count >= 1000 {
        return String(format: "%.1fk", Double(count) / 1000.0)
    }

    return String(count)
}

// MARK: - Native MLX Runtime

public final class NativeMLX: Runtime, @unchecked Sendable {
    private static let gibibyte = 1024 * 1024 * 1024
    private static let inferenceMemoryLimit = 22 * gibibyte
    private static let inferenceCacheLimit = 4 * gibibyte
    /// 权重感知预算下的 OS + App 基线预留（白皮书 §30，铁律 63 校准项）。
    private static let osReserveBytes = 4 * gibibyte
    private static let maxPhysicalKVRevisions = 16
    private static let longContextThreshold = 16384
    private static let sessionMaxIdleTime: TimeInterval = 1800
    private static let prefillStepSize = 1024

    /// 量取模型权重文件体积，用于权重感知的 KV 预算（铁律 63：参数须有实测依据）。
    private static func measureWeightsBytes(atPath path: String) -> UInt64 {
        let fileManager = FileManager.default
        var totalBytes: UInt64 = 0

        guard let enumerator = fileManager.enumerator(atPath: path) else {
            return 0
        }

        for case let file as String in enumerator {
            let isWeightFile =
                file.hasSuffix(".safetensors") ||
                file.hasSuffix(".npz") ||
                file.hasSuffix(".gguf")

            guard isWeightFile else { continue }

            let attributes = try? fileManager.attributesOfItem(
                atPath: path + "/" + file
            )

            totalBytes += (attributes?[.size] as? UInt64) ?? 0
        }

        return totalBytes
    }

    private struct State {
        var modelContainer: ModelContainer?
        var isRunning = false
        var isGenerating = false
        var generatingSessions: Set<String> = []
        var httpServer: HTTPServer?
        var sessionCaches: [String: SessionLogicalState] = [:]
        var physicalRevisions: [PhysicalKVRevision] = []
        var activeRequestTasks: [String: Task<String, Error>] = [:]
        var activeGenerationTasks: [String: Task<Void, Never>] = [:]
        var peakActiveRequests = 0
        var peakActiveGenerationTasks = 0
        var peakResidentBytes: UInt64 = 0
        var peakSwapUsedBytes: UInt64 = 0
    }

    private let state = Mutex(State())
    private let modelPath: String
    private let modelWeightsBytes: UInt64
    private let baseConfig: ModelConfig
    private let lifecycleGate = RuntimeLifecycleGate()
    private let gateHolder = Mutex(SessionGenerationGate())
    private let prefillScheduler = PrefillScheduler()
    private let traceLogger = RuntimeTraceLogger.shared

    // MARK: - Observability

    private nonisolated func emitRuntimeObservation(
        _ label: String,
        requestId: String? = nil,
        executionKey: AgentExecutionKey? = nil
    ) {
        let memory = RuntimeMemoryProbe.snapshot()

        let runtime = state.withLock { state in
            let revisionTokens = state.physicalRevisions.map { $0.physicalTokens.count }

            return (
                activeRequests: state.activeRequestTasks.count,
                activeGenerations: state.activeGenerationTasks.count,
                generatingSessions: state.generatingSessions.count,
                revisions: state.physicalRevisions.count,
                revisionTokens: revisionTokens,
                sessions: state.sessionCaches.count
            )
        }

        state.withLock { state in
            state.peakActiveRequests = max(state.peakActiveRequests, runtime.activeRequests)
            state.peakActiveGenerationTasks = max(state.peakActiveGenerationTasks, runtime.activeGenerations)
            state.peakResidentBytes = max(state.peakResidentBytes, memory.residentBytes)

            if let swap = memory.swapUsedBytes {
                state.peakSwapUsedBytes = max(state.peakSwapUsedBytes, swap)
            }
        }

        let visible: Set<String> = [
            "runtime-start-preload",
            "request-admitted",
            "generation-start",
            "cancel-request-issued",
            "cancelled",
            "request-complete",
            "shutdown-begin",
            "shutdown-after-drain",
            "shutdown-after-kv-release",
            "shutdown-after-memory-clear"
        ]

        guard visible.contains(label) else { return }

        let labelMap: [String: String] = [
            "runtime-start-preload": "start",
            "request-admitted": "admit",
            "generation-start": "gen",
            "cancel-request-issued": "cancel",
            "cancelled": "cancelled",
            "request-complete": "done",
            "shutdown-begin": "stop",
            "shutdown-after-drain": "drain",
            "shutdown-after-kv-release": "kvfree",
            "shutdown-after-memory-clear": "memfree"
        ]

        let phase = labelMap[label] ?? label
        let rid = requestId.map { String($0.replacingOccurrences(of: "req-", with: "").prefix(6)) }
        let req = rid.map { "r=\($0)" } ?? ""

        let revSummary = runtime.revisionTokens.isEmpty
            ? "-"
            : runtime.revisionTokens.map(compactTokenCount).joined(separator: ",")

        let swap: String

        if let used = memory.swapUsedGB, let total = memory.swapTotalGB {
            swap = String(format: "sw=%.2f/%.2fG", used, total)
        } else {
            swap = "sw=?"
        }

        let sessionPart: String

        if let executionKey {
            let raw = executionKey.sessionId
            let short = raw.contains("anon_")
                ? String(raw.split(separator: "_").last.map(String.init)?.prefix(6) ?? raw.suffix(6))
                : String(raw.suffix(6))

            sessionPart = "s=\(short) br=\(executionKey.logicalBranchId)"
        } else {
            sessionPart = ""
        }

        let memoryLine = "[MEM] p=\(phase)" +
            (req.isEmpty ? "" : " \(req)") +
            (sessionPart.isEmpty ? "" : " \(sessionPart)") +
            String(format: " rss=%.2fG vm=%.2fG", memory.residentGB, memory.virtualGB) +
            " \(swap)" +
            " q=\(runtime.activeRequests)/\(runtime.activeGenerations)" +
            " sess=\(runtime.sessions)" +
            " rev=\(runtime.revisions)" +
            " ktok=\(revSummary)"

        traceLogger.trace(memoryLine, session: executionKey?.traceKey)
    }

    private nonisolated func emitObservationSummary() {
        let memory = RuntimeMemoryProbe.snapshot()

        let stats = state.withLock { state in
            let revisionTokens = state.physicalRevisions.map { $0.physicalTokens.count }

            return (
                activeRequests: state.activeRequestTasks.count,
                activeGenerations: state.activeGenerationTasks.count,
                revisions: state.physicalRevisions.count,
                revisionTokens: revisionTokens,
                peakActiveRequests: state.peakActiveRequests,
                peakActiveGenerations: state.peakActiveGenerationTasks,
                peakResidentBytes: state.peakResidentBytes,
                peakSwapUsedBytes: state.peakSwapUsedBytes
            )
        }

        let peakResidentGB = Double(stats.peakResidentBytes) / 1024.0 / 1024.0 / 1024.0
        let peakSwapGB = Double(stats.peakSwapUsedBytes) / 1024.0 / 1024.0 / 1024.0

        let revisionSummary = stats.revisionTokens.isEmpty
            ? "-"
            : stats.revisionTokens.map(compactTokenCount).joined(separator: ",")

        let currentSwap = memory.swapUsedGB.map { String(format: "%.2fG", $0) } ?? "?"

        traceLogger.trace(
            String(
                format: "[SUM] q=%d/%d rev=%d ktok=%@ peakRSS=%.2fG peakSW=%.2fG rss=%.2fG sw=%@",
                stats.activeRequests,
                stats.activeGenerations,
                stats.revisions,
                revisionSummary,
                peakResidentGB,
                peakSwapGB,
                memory.residentGB,
                currentSwap
            )
        )
    }

    // MARK: Runtime Conformance

    public var isInProcess: Bool { true }
    public var isGenerating: Bool { state.withLock { $0.isGenerating || !$0.generatingSessions.isEmpty } }
    public var isRunning: Bool { state.withLock { $0.isRunning } }

    public init(info: ModelInfo, config: ModelConfig) {
        self.modelPath = info.path
        self.modelWeightsBytes = Self.measureWeightsBytes(atPath: info.path)
        self.baseConfig = config

        Memory.memoryLimit = Self.inferenceMemoryLimit
        Memory.cacheLimit = Self.inferenceCacheLimit

        let weightsGB = Double(modelWeightsBytes) / Double(Self.gibibyte)
        traceLogger.trace(
            "Init NativeMLX Runtime: memoryLimit=22GB, cacheLimit=4GB, weights=\(String(format: "%.1f", weightsGB))GB, prefillStepSize=\(Self.prefillStepSize), " +
            "maxPhysicalKVRevisions=\(Self.maxPhysicalKVRevisions), logicalSessionEviction=TTL(\(Int(Self.sessionMaxIdleTime))s), modelPath=\(info.path)"
        )
    }

    // MARK: Lifecycle

    public func start(_ info: ModelInfo, port: Int) async throws {
        try await lifecycleGate.withLock { [weak self] in
            guard let self else {
                throw RuntError.notLoaded
            }

            guard !self.state.withLock({ $0.isRunning }) else {
                return
            }

            let oldRevisions = self.state.withLock { state -> [PhysicalKVRevision] in
                let revisions = state.physicalRevisions

                state.physicalRevisions.removeAll()
                state.sessionCaches.removeAll()
                state.generatingSessions.removeAll()

                return revisions
            }

            if !oldRevisions.isEmpty {
                await MainActor.run {
                    for var revision in oldRevisions {
                        revision.releasePhysicalMemory()
                    }
                }
            }

            Memory.clearCache()
            self.emitRuntimeObservation("runtime-start-preload")
            self.gateHolder.withLock { $0 = SessionGenerationGate() }
            self.traceLogger.reset()

            Service.log("🚀 [NativeMLX] 正在加载本地模型: \(info.path)")
            self.traceLogger.trace("Loading model container from \(info.path)")

            do {
                let modelURL = URL(fileURLWithPath: info.path)

                let container = try await LLMModelFactory.shared.loadContainer(
                    from: modelURL,
                    using: #huggingFaceTokenizerLoader()
                )

                let modelId = modelName(from: info.path)

                let nodeConfiguration = await MainActor.run {
                    let current = InferenceNodeConfiguration.shared.snapshot()

                    if current.port != port {
                        InferenceNodeConfiguration.configure(
                            bindHost: current.bindHost,
                            advertisedHost: current.advertisedHost,
                            port: port,
                            bonjourEnabled: current.bonjourEnabled
                        )

                        return InferenceNodeConfiguration.shared.snapshot()
                    }

                    return current
                }

                let server = await MainActor.run {
                    HTTPServer(
                        port: nodeConfiguration.port,
                        modelId: modelId,
                        bindHost: nodeConfiguration.bindHost,
                        bonjourEnabled: nodeConfiguration.bonjourEnabled,
                        generateHandler: { [weak self] rid, agent, sess, branch, msgs, tools, cfg, onChunk, onToolCall in
                            guard let self else { return "" }

                            return try await self.generate(
                                requestId: rid,
                                agentId: agent,
                                sessionId: sess,
                                logicalBranchId: branch,
                                messages: msgs,
                                tools: tools,
                                config: cfg,
                                onChunk: onChunk,
                                onToolCall: onToolCall
                            )
                        },
                        checkHealthHandler: { [weak self] in
                            await self?.checkHealth() ?? false
                        },
                        cancelGenerationHandler: { [weak self] requestId in
                            self?.cancelGeneration(requestId: requestId)
                        }
                    )
                }

                try await MainActor.run {
                    try server.start()
                }

                self.state.withLock {
                    $0.modelContainer = container
                    $0.isRunning = true
                    $0.isGenerating = false
                    $0.httpServer = server
                    $0.sessionCaches.removeAll()
                    $0.physicalRevisions.removeAll()
                    $0.generatingSessions.removeAll()
                }

                self.traceLogger.trace(
                    "Model ready on port \(nodeConfiguration.port), bindHost=\(nodeConfiguration.bindHost), modelId=\(modelId)"
                )

                Service.log(
                    "✅ [NativeMLX] 原生模型已就绪 (Model ID: \(modelId), Port: \(nodeConfiguration.port), Bind: \(nodeConfiguration.bindHost))"
                )
            } catch {
                self.traceLogger.trace("Model load failed: \(error.localizedDescription)")
                throw RuntError.loadFailed(error.localizedDescription)
            }
        }
    }

    public func stop() async {
        await lifecycleGate.withLockVoid { [weak self] in
            guard let self else { return }

            self.emitRuntimeObservation("shutdown-begin")

            let (server, requestTasks, generationTasks, gate) = self.state.withLock { state in
                let server = state.httpServer
                let requestTasks = Array(state.activeRequestTasks.values)
                let generationTasks = Array(state.activeGenerationTasks.values)
                let gate = self.gateHolder.withLock { $0 }

                state.httpServer = nil
                state.isRunning = false
                state.isGenerating = false
                state.generatingSessions.removeAll()

                return (server, requestTasks, generationTasks, gate)
            }

            if let server {
                await MainActor.run {
                    server.stop()
                }
            }

            await self.prefillScheduler.cancelAll()
            await gate.beginShutdown()

            for task in requestTasks {
                task.cancel()
            }

            for task in generationTasks {
                task.cancel()
            }

            for task in requestTasks {
                _ = try? await task.value
            }

            for task in generationTasks {
                await task.value
            }

            await gate.awaitDrain()
            self.emitRuntimeObservation("shutdown-after-drain")

            let revisions = self.state.withLock { state -> [PhysicalKVRevision] in
                let revisions = state.physicalRevisions

                state.physicalRevisions.removeAll()
                state.sessionCaches.removeAll()
                state.generatingSessions.removeAll()
                state.modelContainer = nil

                return revisions
            }

            if !revisions.isEmpty {
                await MainActor.run {
                    for var revision in revisions {
                        revision.releasePhysicalMemory()
                    }
                }
            }

            self.emitRuntimeObservation("shutdown-after-kv-release")

            Memory.clearCache()
            self.emitRuntimeObservation("shutdown-after-memory-clear")
            self.emitObservationSummary()

            Service.log("🛑 [NativeMLX] 模型已物理卸载，Task + Scheduler + Gate + Global KV 已完成最终一致性清扫")
            self.traceLogger.trace("NativeMLX runtime stopped and memory cleared (Two-Phase Teardown complete).")
            self.traceLogger.flush()
        }
    }

    public func checkHealth() async -> Bool {
        state.withLock { $0.isRunning && $0.modelContainer != nil }
    }

    // MARK: Inference Entry

    public func generate(
        requestId: String = "internal-\(UUID().uuidString.lowercased())",
        agentId: String? = nil,
        sessionId: String = "default",
        logicalBranchId: String = "main",
        messages: [JSONValue],
        tools: [JSONValue]?,
        config: ModelConfig,
        onChunk: @escaping @Sendable (String) -> Void,
        onToolCall: @escaping @Sendable (ParsedToolCall) -> Void = { _ in }
    ) async throws -> String {
        let executionKey = try AgentExecutionKey.resolve(
            agentId: agentId,
            sessionId: sessionId,
            logicalBranchId: logicalBranchId
        )

        let gate = gateHolder.withLock { $0 }

        traceLogger.trace(
            "[REQ] request=\(requestId) a=\(executionKey.agentId) s=\(executionKey.sessionId) br=\(executionKey.logicalBranchId)",
            session: executionKey.traceKey
        )

        emitRuntimeObservation(
            "request-admitted",
            requestId: requestId,
            executionKey: executionKey
        )

        let gateWaitStart = Date()

        let task: Task<String, Error> = Task { [weak self] in
            guard let self else {
                throw RuntError.notLoaded
            }

            return try await gate.withExclusive(executionKey) {
                let gateWait = max(Date().timeIntervalSince(gateWaitStart), 0)

                self.traceLogger.trace(
                    "[GATE] request=\(requestId) wait=\(String(format: "%.1f", gateWait * 1000))ms",
                    session: executionKey.traceKey
                )

                await MainActor.run {
                    self.emitRuntimeObservation(
                        "generation-gate-granted",
                        requestId: requestId,
                        executionKey: executionKey
                    )
                }

                return try await self.generateAfterGate(
                    requestId: requestId,
                    executionKey: executionKey,
                    messages: messages,
                    tools: tools,
                    config: config,
                    onChunk: onChunk,
                    onToolCall: onToolCall
                )
            }
        }

        state.withLock { state in
            state.activeRequestTasks[requestId] = task
            state.peakActiveRequests = max(state.peakActiveRequests, state.activeRequestTasks.count)
        }

        defer {
            _ = state.withLock {
                $0.activeRequestTasks.removeValue(forKey: requestId)
            }

            emitRuntimeObservation(
                "request-task-removed",
                requestId: requestId,
                executionKey: executionKey
            )

            // Invariant 1 观测：真实任务收尾回报给生命周期账本
            Task {
                await RuntimeLifecycleCoordinator.shared.noteRequestTaskEnded(
                    requestID: requestId
                )
            }
        }

        return try await withTaskCancellationHandler(
            operation: {
                try await task.value
            },
            onCancel: {
                task.cancel()
            }
        )
    }

    // MARK: Generation Core

    private func generateAfterGate(
        requestId: String,
        executionKey: AgentExecutionKey,
        messages: [JSONValue],
        tools: [JSONValue]?,
        config: ModelConfig,
        onChunk: @escaping @Sendable (String) -> Void,
        onToolCall: @escaping @Sendable (ParsedToolCall) -> Void
    ) async throws -> String {
        let t0 = Date()
        let sessionKey = executionKey.storageKey
        let targetLogicalBranchId = executionKey.logicalBranchId
        let traceSession = executionKey.traceKey

        guard !Task.isCancelled else {
            throw CancellationError()
        }

        let proceed = state.withLock { state -> Bool in
            guard state.isRunning, state.modelContainer != nil else {
                return false
            }

            state.generatingSessions.insert(sessionKey)
            purgeStaleSessionCachesLocked(&state)

            return true
        }

        guard proceed else {
            throw RuntError.notLoaded
        }

        defer {
            _ = state.withLock {
                $0.generatingSessions.remove(sessionKey)
            }
        }

        guard let container = state.withLock({ $0.modelContainer }) else {
            throw RuntError.notLoaded
        }

        // MARK: Message Normalization

        var messagesAny: [[String: Any]] = []
        var systemMerged = false
        var sawNonSystemPrefix = false

        for value in messages {
            guard case .object(let dict) = value else { continue }

            var message = dict.mapValues {
                $0.toAny()
            }

            if let rawCalls = message["tool_calls"] {
                let normalizedCalls = try normalizedHistoricalToolCalls(rawCalls)

                if normalizedCalls.isEmpty {
                    message.removeValue(forKey: "tool_calls")
                } else {
                    message["tool_calls"] = normalizedCalls
                }
            }

            let hasToolCalls = (message["tool_calls"] as? [[String: Any]])?.isEmpty == false
            let role = (message["role"] as? String) ?? "user"

            if let content = message["content"] {
                let normalizedContent = coerceContentToString(content)

                if hasToolCalls && normalizedContent.isEmpty {
                    message.removeValue(forKey: "content")
                } else {
                    message["content"] = normalizedContent
                }
            } else if !hasToolCalls && role != "assistant" {
                message["content"] = ""
            }

            let isSystemLike = role == "system" || role == "developer"

            if isSystemLike && !sawNonSystemPrefix {
                let body = (message["content"] as? String) ?? ""

                if !systemMerged {
                    message["role"] = "system"
                    messagesAny.append(message)
                    systemMerged = true
                } else if !body.isEmpty, let base = messagesAny.first?["content"] as? String {
                    messagesAny[0]["content"] = base + "\n\n" + body
                }

                continue
            }

            sawNonSystemPrefix = true

            if isSystemLike || !["user", "assistant", "tool"].contains(role) {
                message["role"] = "user"
            }

            messagesAny.append(message)
        }

        // MARK: Parameters

        let thinkingDisabled = config.disableThinking || baseConfig.disableThinking
        let requestedMaxTokens = config.maxTokens > 0 ? config.maxTokens : (baseConfig.maxTokens > 0 ? baseConfig.maxTokens : 4096)
        let maxTokens = min(requestedMaxTokens, 4096)
        let temperature = config.temperature != 0.0 ? config.temperature : baseConfig.temperature
        let topP = config.topP != 0.0 ? config.topP : (baseConfig.topP != 0.0 ? baseConfig.topP : 1.0)
        let topK = config.topK != 0 ? config.topK : baseConfig.topK
        let minP = config.minP != 0.0 ? config.minP : baseConfig.minP
        let repeatPenalty = config.repeatPenalty != 0.0 ? config.repeatPenalty : baseConfig.repeatPenalty
        let presencePenalty = config.presencePenalty != 0.0 ? config.presencePenalty : baseConfig.presencePenalty

        let params = GenerateParameters(
            maxTokens: maxTokens,
            maxKVSize: nil,
            temperature: Float(temperature),
            topP: topK > 0 ? 1.0 : Float(topP),
            topK: topK,
            minP: minP,
            repetitionPenalty: repeatPenalty,
            presencePenalty: presencePenalty,
            prefillStepSize: Self.prefillStepSize
        )

        let toolsAny = makeToolSpecs(tools)
        let additionalContext: [String: Any]? = thinkingDisabled ? ["enable_thinking": false] : nil
        let userInput = UserInput(
            messages: messagesAny,
            tools: toolsAny,
            additionalContext: additionalContext
        )

        traceLogger.trace(
            "[INF] m=\(messagesAny.count) tools=\(toolsAny?.count ?? 0) thinkOff=\(thinkingDisabled) max=\(maxTokens)",
            session: traceSession
        )

        // MARK: Official Prompt Preparation

        let lmInput = try await container.prepare(input: userInput)
        let allPromptTokens = lmInput.text.tokens.asArray(Int.self)

        guard !allPromptTokens.isEmpty else {
            traceLogger.trace("⚠️ Tokenization produced 0 tokens, aborting.", session: traceSession)
            return ""
        }

        let effectiveContextDemand = allPromptTokens.count + maxTokens
        let runtimeSafetyContextBudget = max(1024, config.ctxSize)

        guard effectiveContextDemand <= runtimeSafetyContextBudget else {
            traceLogger.trace(
                "[CONTEXT SAFETY REJECT] demand=\(effectiveContextDemand), budget=\(runtimeSafetyContextBudget), action=require_L1_compaction",
                session: traceSession
            )

            throw NativeMLXValidationError.contextDemandExceeded(
                effectiveContextDemand,
                runtimeSafetyContextBudget
            )
        }

        guard !Task.isCancelled else {
            throw CancellationError()
        }

        // MARK: Tool Fingerprint + Semantic Progress

        let toolFingerprint = makeToolFingerprint(toolsAny)
        let semanticProgressHash = computeSemanticProgressHash(messagesAny)

        let logicalStateReleases = state.withLock { state -> [PhysicalKVRevision] in
            var session = state.sessionCaches[sessionKey] ?? SessionLogicalState()

            if session.logicalBranches[targetLogicalBranchId] == nil {
                session.logicalBranches[targetLogicalBranchId] = LogicalBranchState(
                    logicalBranchId: targetLogicalBranchId,
                    toolFingerprint: toolFingerprint
                )
            }

            if var logical = session.logicalBranches[targetLogicalBranchId] {
                logical.toolFingerprint = toolFingerprint
                logical.lastActive = Date()
                session.logicalBranches[targetLogicalBranchId] = logical
            }

            session.lastActive = Date()
            state.sessionCaches[sessionKey] = session

            return []
        }

        _ = logicalStateReleases

        var selectedBranch: PhysicalKVRevision?
        var selectedIndex = -1
        var selectedCommonLen = 0
        var selectedRawCommonLen = 0
        var sawUsableBranch = false
        var sawToolFingerprintMismatch = false
        var activeKVCacheFromPrefix: [any KVCache]?

        state.withLock { state in
            for (index, revision) in state.physicalRevisions.enumerated() {
                guard !revision.physicalTokens.isEmpty else { continue }

                sawUsableBranch = true

                guard revision.toolFingerprint == toolFingerprint else {
                    sawToolFingerprintMismatch = true
                    continue
                }

                let rawCommon = computeCommonPrefix(
                    revision.physicalTokens,
                    allPromptTokens
                )

                let boundedCommon = min(
                    rawCommon,
                    revision.physicalTokens.count,
                    allPromptTokens.count
                )

                if boundedCommon > selectedCommonLen ||
                    (boundedCommon == selectedCommonLen &&
                     boundedCommon > 0 &&
                     revision.lastActive > (selectedBranch?.lastActive ?? .distantPast)) {
                    selectedCommonLen = boundedCommon
                    selectedRawCommonLen = rawCommon
                    selectedBranch = revision
                    selectedIndex = index
                }
            }

            if let revision = selectedBranch, selectedCommonLen > 0 {
                if !revision.resident {
                    selectedCommonLen = 0
                    activeKVCacheFromPrefix = nil

                    traceLogger.trace(
                        "[KVD] br=\(targetLogicalBranchId) why=evicted rev=\(revision.id)",
                        session: traceSession
                    )
                } else {
                    activeKVCacheFromPrefix = revision.kvCache.map {
                        $0.copy()
                    }

                    var touched = revision
                    touched.lastActive = Date()

                    if selectedIndex >= 0,
                       selectedIndex < state.physicalRevisions.count {
                        state.physicalRevisions[selectedIndex].lastActive = touched.lastActive
                    }
                }
            }
        }

        if sawToolFingerprintMismatch {
            traceLogger.trace(
                "[KVD] br=\(targetLogicalBranchId) why=toolFP reuse=0",
                session: traceSession
            )
        }

        if selectedBranch != nil {
            traceLogger.trace(
                "[KVS] br=\(targetLogicalBranchId) i=\(selectedIndex) rawcp=\(selectedRawCommonLen) cp=\(selectedCommonLen)",
                session: traceSession
            )
        }

        // MARK: Prefill Scheduler

        let prefillPermit = await prefillScheduler.acquire(requestId: requestId)

        guard prefillPermit.granted else {
            traceLogger.trace(
                "🛑 Prefill Scheduler acquisition cancelled.",
                session: traceSession
            )

            throw CancellationError()
        }

        if prefillPermit.waited > 0.005 {
            traceLogger.trace(
                "[PWAIT] request=\(requestId) wait=\(String(format: "%.1f", prefillPermit.waited * 1000))ms",
                session: traceSession
            )
        }

        var prefillSlotReleased = false

        defer {
            if !prefillSlotReleased {
                Task {
                    await prefillScheduler.release(requestId: requestId)
                }
            }
        }

        // MARK: Build Active KV Cache

        var activeKVCache: [any KVCache]
        var finalInput: LMInput = lmInput
        var deltaTokenCount = allPromptTokens.count
        var hasReusableCache = false

        if let branch = selectedBranch,
           selectedCommonLen > 0,
           let copiedKV = activeKVCacheFromPrefix {
            activeKVCache = copiedKV

            traceLogger.trace(
                "[KCP] src=G rev=\(branch.id) cache=\(branch.physicalTokens.count) kv=\(activeKVCache.count) p=\(allPromptTokens.count) cp=\(selectedCommonLen)",
                session: traceSession
            )

            selectedCommonLen = min(
                selectedCommonLen,
                branch.physicalTokens.count,
                allPromptTokens.count
            )

            let stalePhysicalCount = max(
                branch.physicalTokens.count - selectedCommonLen,
                0
            )

            if stalePhysicalCount > 0 {
                for index in activeKVCache.indices {
                    _ = activeKVCache[index].trim(stalePhysicalCount)
                }
            }

            let deltaCount = max(
                allPromptTokens.count - selectedCommonLen,
                0
            )

            if deltaCount > 0 {
                let deltaTokens = Array(
                    allPromptTokens.dropFirst(selectedCommonLen)
                )

                finalInput = LMInput(
                    tokens: MLXArray(deltaTokens)
                )

                deltaTokenCount = deltaTokens.count
                hasReusableCache = true

                let skippedPercent = String(
                    format: "%.1f",
                    Double(selectedCommonLen) /
                        Double(max(allPromptTokens.count, 1)) * 100.0
                )

                Service.log(
                    "⚡️ [Global KV Reuse] branch=\(branch.id), reused=\(selectedCommonLen), delta=\(deltaCount), skipped=\(skippedPercent)%"
                )

                traceLogger.trace(
                    "[KVR] src=G i=\(selectedIndex) rev=\(branch.id) cache=\(branch.physicalTokens.count) cp=\(selectedCommonLen) d=\(deltaCount) hit=\(skippedPercent)%",
                    session: traceSession
                )
            } else if selectedCommonLen > 1 {
                for index in activeKVCache.indices {
                    _ = activeKVCache[index].trim(1)
                }

                let reprimeToken = allPromptTokens[selectedCommonLen - 1]
                finalInput = LMInput(
                    tokens: MLXArray([reprimeToken])
                )

                deltaTokenCount = 1
                hasReusableCache = true
                selectedCommonLen -= 1

                let skippedPercent = String(
                    format: "%.1f",
                    Double(selectedCommonLen) /
                        Double(max(allPromptTokens.count, 1)) * 100.0
                )

                Service.log(
                    "⚡️ [Global KV Reuse] exact prompt match: branch=\(branch.id), reused=\(selectedCommonLen), delta=1, skipped=\(skippedPercent)%"
                )

                traceLogger.trace(
                    "[EXACT MATCH REPRIME] source=global, index=\(selectedIndex), branch=\(branch.id), reused=\(selectedCommonLen), delta=1, reuse=\(skippedPercent)%",
                    session: traceSession
                )
            } else {
                hasReusableCache = false

                let newCacheBox = await container.perform { (context: ModelContext) -> SendableBox<[any KVCache]> in
                    SendableBox(
                        context.model.newCache(parameters: params)
                    )
                }

                activeKVCache = newCacheBox.value
                finalInput = lmInput
                deltaTokenCount = allPromptTokens.count
            }
        } else {
            let newCacheBox = await container.perform { (context: ModelContext) -> SendableBox<[any KVCache]> in
                SendableBox(
                    context.model.newCache(parameters: params)
                )
            }

            activeKVCache = newCacheBox.value
            finalInput = lmInput
            deltaTokenCount = allPromptTokens.count

            let revisionCount = state.withLock {
                $0.physicalRevisions.count
            }

            let missReason: String

            if revisionCount == 0 {
                missReason = "noGlobalRevision"
            } else if sawToolFingerprintMismatch {
                missReason = "toolFingerprintMismatch"
            } else if selectedBranch != nil && !(selectedBranch!.resident) {
                missReason = "evictedPhysicalKV"
            } else if sawUsableBranch {
                missReason = "noCommonPrefix"
            } else {
                missReason = "noUsableLineage"
            }

            Service.log(
                "⚡️ [Global Physical KV Cold] prompt=\(allPromptTokens.count)"
            )

            traceLogger.trace(
                "[KVM] why=\(missReason) p=\(allPromptTokens.count) tf=\(toolFingerprint) revs=\(revisionCount)",
                session: traceSession
            )

            traceLogger.trace(
                "[COLD] p=\(allPromptTokens.count) tf=\(toolFingerprint) revs=\(revisionCount)",
                session: traceSession
            )
        }

        // MARK: Long Context Policy & Admission Control

        let estimatedBytesPerToken: UInt64 = 128 * 1024
        let projectedKVBytes = UInt64(deltaTokenCount) * estimatedBytesPerToken
        let executionWorkingSetBytes: UInt64 = 3 * 1024 * 1024 * 1024
        let safetyMarginBytes: UInt64 = 1 * 1024 * 1024 * 1024

        // 白皮书 §30 + 铁律 63：Admission 预算必须与物理内存对账。
        // 权重不计入预算的旧口径在 20G 权重模型 + 32G 机器上超订 ~9G，
        // macOS 被迫页出权重，实测 decode 33→12.7 tok/s（日志 2026-09-05）。
        // limit = min(22G, RAM − weights − OS 基线)，下限 4G 防御。
        let physicalRAMBytes = ProcessInfo.processInfo.physicalMemory
        let reservedBytes = modelWeightsBytes &+ UInt64(Self.osReserveBytes)
        let weightAwareLimit: UInt64 = physicalRAMBytes > reservedBytes
            ? physicalRAMBytes &- reservedBytes
            : 4 * 1024 * 1024 * 1024
        let admissionLimit = min(
            UInt64(Self.inferenceMemoryLimit),
            weightAwareLimit
        )

        let currentResidentKVBytes: UInt64 = state.withLock { state in
            state.physicalRevisions
                .map(\.estimatedResidentBytes)
                .reduce(0, +)
        }

        let admissionMemorySnapshot = RuntimeMemoryProbe.snapshot()
        let internalKVGB = Double(currentResidentKVBytes) / Double(Self.gibibyte)
        let rssGB = admissionMemorySnapshot.residentGB
        let weightsGB = Double(modelWeightsBytes) / Double(Self.gibibyte)
        let budgetGB = Double(admissionLimit) / Double(Self.gibibyte)

        traceLogger.trace(
            "[ADMISSION OBS] r=\(requestId) kv=\(String(format: "%.2f", internalKVGB))G rss=\(String(format: "%.2f", rssGB))G sw=\(admissionMemorySnapshot.swapUsedGB.map { String(format: "%.2f", $0) } ?? "?")G weights=\(String(format: "%.1f", weightsGB))G budget=\(String(format: "%.1f", budgetGB))G",
            session: traceSession
        )

        var projectedMemory =
            currentResidentKVBytes +
            projectedKVBytes +
            executionWorkingSetBytes +
            safetyMarginBytes

        if projectedMemory > admissionLimit {
            let isLongContext = allPromptTokens.count >= Self.longContextThreshold
            let targetEvictionBytes = projectedMemory - admissionLimit

            var freedBytes: UInt64 = 0
            var evictedCount = 0

            state.withLock { state in
                var evictCandidates = state.physicalRevisions.indices.filter {
                    state.physicalRevisions[$0].resident
                }

                evictCandidates.sort {
                    state.physicalRevisions[$0].lastActive < state.physicalRevisions[$1].lastActive
                }

                for index in evictCandidates {
                    if freedBytes >= targetEvictionBytes && !isLongContext {
                        break
                    }

                    let bytes = state.physicalRevisions[index].estimatedResidentBytes

                    state.physicalRevisions[index].releasePhysicalMemory()
                    freedBytes += bytes
                    evictedCount += 1

                    if isLongContext &&
                        freedBytes >= targetEvictionBytes + 2 * 1024 * 1024 * 1024 {
                        break
                    }
                }
            }

            if evictedCount > 0 {
                Memory.clearCache()

                traceLogger.trace(
                    "[ADMISSION] r=\(requestId) projected=\(projectedMemory / 1024 / 1024)M limit=\(admissionLimit / 1024 / 1024)M evicted=\(evictedCount) est_freed=\(freedBytes / 1024 / 1024)M",
                    session: traceSession
                )

                projectedMemory =
                    (currentResidentKVBytes - freedBytes) +
                    projectedKVBytes +
                    executionWorkingSetBytes +
                    safetyMarginBytes
            }

            if projectedMemory > admissionLimit {
                Memory.clearCache()

                traceLogger.trace(
                    "[ADMISSION WARN] Still exceeding limit after eviction. Projected: \(projectedMemory / 1024 / 1024)M",
                    session: traceSession
                )
            }
        }

        // MARK: Physical Ledger

        let ledgerRecorder = PhysicalTokenRecorder()
        let cacheBox = SendableBox(activeKVCache)
        let inputBox = SendableBox(finalInput)
        let toolsBox = SendableBox(toolsAny)
        let generationUsesReusableCache = hasReusableCache

        let generationBox: SendableBox<
            (
                AsyncStream<Generation>,
                Task<Void, Never>,
                [any KVCache],
                TimeInterval
            )
        > = try await container.perform {
            (context: ModelContext) -> SendableBox<
                (
                    AsyncStream<Generation>,
                    Task<Void, Never>,
                    [any KVCache],
                    TimeInterval
                )
            > in
            let iterator = try TokenIterator(
                input: inputBox.value,
                model: context.model,
                cache: cacheBox.value,
                parameters: params
            )

            if generationUsesReusableCache {
                let promptKVState = cacheBox.value.flatMap {
                    $0.state
                }

                if !promptKVState.isEmpty {
                    eval(promptKVState)
                }
            }

            let promptPrefillTime = iterator.promptPrefillTime

            let recordingIterator = PhysicalLedgerTokenIterator(
                base: iterator,
                recorder: ledgerRecorder
            )

            let (stream, task) = MLXLMCommon.generateTask(
                promptTokenCount: inputBox.value.text.tokens.size,
                modelConfiguration: context.configuration,
                tokenizer: context.tokenizer,
                iterator: recordingIterator,
                tools: toolsBox.value
            )

            return SendableBox(
                (
                    stream,
                    task,
                    cacheBox.value,
                    promptPrefillTime
                )
            )
        }

        prefillSlotReleased = true
        await prefillScheduler.release(requestId: requestId)

        let (stream, generationTask, generationKVCache, promptPrefillTime) = generationBox.value

        state.withLock { state in
            state.activeGenerationTasks[requestId] = generationTask
            state.peakActiveGenerationTasks = max(
                state.peakActiveGenerationTasks,
                state.activeGenerationTasks.count
            )
        }

        traceLogger.trace(
            "[GENERATION START] request=\(requestId), agent=\(executionKey.agentId), session=\(executionKey.sessionId), prefillQueueWait=\(String(format: "%.1f", prefillPermit.waited * 1000))ms",
            session: traceSession
        )

        emitRuntimeObservation(
            "generation-start",
            requestId: requestId,
            executionKey: executionKey
        )

        defer {
            _ = state.withLock {
                $0.activeGenerationTasks.removeValue(forKey: requestId)
            }

            emitRuntimeObservation(
                "generation-task-removed",
                requestId: requestId,
                executionKey: executionKey
            )
        }

        // MARK: Stream Consume

        let filter = StreamTokenFilter(
            disableThinking: thinkingDisabled
        )

        let rawToolCallParser = RawToolCallStreamParser()
        var completedText = ""
        var isInterrupted = false
        var toolCallDetected = false
        var rawToolCallDetected = false
        var turnToolCalls: [ParsedToolCall] = []
        var attemptedToolSignatures = Set<String>()

        func appendToolCallCandidate(_ call: ParsedToolCall) {
            let normalizedName = call.name.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !normalizedName.isEmpty else {
                traceLogger.trace(
                    "[TDROP] request=\(requestId) why=noName",
                    session: traceSession
                )

                return
            }

            let canonicalArguments = canonicalValue(
                call.arguments.mapValues(toolValueToSendable)
            )

            let signature = "\(normalizedName)\u{001F}\(canonicalArguments)"

            guard attemptedToolSignatures.insert(signature).inserted else {
                traceLogger.trace(
                    "[TDUP] request=\(requestId) name=\(normalizedName) act=dup",
                    session: traceSession
                )

                return
            }

            toolCallDetected = true

            turnToolCalls.append(
                ParsedToolCall(
                    id: call.id,
                    name: normalizedName,
                    arguments: call.arguments
                )
            )
        }

        emitRuntimeObservation(
            "decode-start",
            requestId: requestId,
            executionKey: executionKey
        )

        let decodeStartTime = Date()

        for await generation in stream {
            if Task.isCancelled || !state.withLock({ $0.isRunning }) {
                isInterrupted = true
                generationTask.cancel()
                break
            }

            switch generation {
            case .chunk(let text):
                if text.contains("<tool_call>") || text.contains("</tool_call>") {
                    traceLogger.trace(
                        "[RAWTOOL] request=\(requestId) chunkLen=\(text.count)",
                        session: traceSession
                    )
                }

                rawToolCallParser.feed(
                    text,
                    onText: { plainText in
                        filter.feed(plainText) { chunk in
                            completedText.append(chunk)
                            onChunk(chunk)
                        }
                    },
                    onToolCall: { call in
                        rawToolCallDetected = true
                        appendToolCallCandidate(call)
                    }
                )

            case .toolCall(let toolCall):
                let argumentObject = toolCall.function.arguments.reduce(
                    into: [String: JSONValue]()
                ) { result, item in
                    result[item.key] = mlxJSONToSimiGo(item.value)
                }

                appendToolCallCandidate(
                    ParsedToolCall(
                        id: toolCall.id ?? UUID().uuidString,
                        name: toolCall.function.name,
                        arguments: argumentObject
                    )
                )

            case .info:
                break
            }
        }

        if isInterrupted {
            generationTask.cancel()
        }

        await generationTask.value

        emitRuntimeObservation(
            "generation-task-completed",
            requestId: requestId,
            executionKey: executionKey
        )

        let decodeWallTime = max(
            Date().timeIntervalSince(decodeStartTime),
            0.001
        )

        // First flush Raw Tool Call Parser

        rawToolCallParser.flush { plainText in
            filter.feed(plainText) { chunk in
                completedText.append(chunk)
                onChunk(chunk)
            }
        }

        filter.flush { chunk in
            completedText.append(chunk)
            onChunk(chunk)
        }

        rawToolCallDetected =
            rawToolCallDetected ||
            rawToolCallParser.rawToolCallDetected

        if let failure = rawToolCallParser.failure {
            traceLogger.trace(
                "[TPFAIL] request=\(requestId) raw=1 error=\(failure.localizedDescription) kv=0",
                session: traceSession
            )

            throw failure
        }

        let actualGeneratedTokenIDs = ledgerRecorder.snapshot()

        if toolCallDetected {
            traceLogger.trace(
                "[TOOL] request=\(requestId) tok=\(actualGeneratedTokenIDs.count) raw=\(rawToolCallDetected ? 1 : 0) calls=\(turnToolCalls.count)",
                session: traceSession
            )
        }

        if rawToolCallDetected {
            traceLogger.trace(
                "[RAWTOOL] request=\(requestId) raw=\(rawToolCallDetected ? 1 : 0) structured=\(turnToolCalls.count)",
                session: traceSession
            )
        }

        // MARK: Cross-Turn Degeneration State Machine

        var forwardedToolCount = 0
        var stateAdvanced = false
        var kvCommittedSuccessfully = false

        let candidateSignatures = turnToolCalls.map {
            "\($0.name)\u{001F}" +
            canonicalValue($0.arguments.mapValues(toolValueToSendable))
        }.sorted()

        var actualForwardedSignatures: [String] = []
        var degenerationBlocked = false

        var currentDegenerationState = state.withLock {
            $0.sessionCaches[sessionKey]?
                .logicalBranches[targetLogicalBranchId]?
                .degenerationState
                ?? BranchDegenerationState()
        }

        if !isInterrupted && !Task.isCancelled {
            if turnToolCalls.isEmpty {
                if !rawToolCallDetected {
                    currentDegenerationState.resetOnPlain()
                    stateAdvanced = true
                }
            } else {
                let probe = currentDegenerationState.preview(
                    signatures: candidateSignatures,
                    progress: semanticProgressHash
                )

                if probe.blocked {
                    currentDegenerationState.recordBlocked(probe)
                    stateAdvanced = true
                    degenerationBlocked = true

                    traceLogger.trace(
                        "[BRANCH DEGENERATION BLOCKED] request=\(requestId), branch=\(targetLogicalBranchId), projectedRounds=\(probe.projected), action=circuit_break, forwarded=0, kvCommitted=false, stateAdvanced=true",
                        session: traceSession
                    )
                } else {
                    for tool in turnToolCalls {
                        if Task.isCancelled {
                            isInterrupted = true
                            break
                        }

                        onToolCall(tool)
                        forwardedToolCount += 1

                        actualForwardedSignatures.append(
                            "\(tool.name)\u{001F}" +
                            canonicalValue(tool.arguments.mapValues(toolValueToSendable))
                        )
                    }

                    actualForwardedSignatures.sort()

                    if forwardedToolCount > 0 {
                        currentDegenerationState.commitForwarded(
                            BranchDegenerationState.Probe(
                                signatures: candidateSignatures,
                                progress: semanticProgressHash,
                                projected: probe.projected,
                                blocked: false
                            )
                        )

                        stateAdvanced = true
                    }
                }
            }

            state.withLock { state in
                var session = state.sessionCaches[sessionKey] ?? SessionLogicalState()

                var logical = session.logicalBranches[targetLogicalBranchId] ?? LogicalBranchState(
                    logicalBranchId: targetLogicalBranchId,
                    toolFingerprint: toolFingerprint
                )

                logical.degenerationState = currentDegenerationState
                logical.toolFingerprint = toolFingerprint
                logical.lastActive = Date()

                session.logicalBranches[targetLogicalBranchId] = logical
                session.lastActive = Date()

                state.sessionCaches[sessionKey] = session
            }
        }

        // MARK: Physical KV Commit

        if !degenerationBlocked &&
            !isInterrupted &&
            !Task.isCancelled &&
            forwardedToolCount == turnToolCalls.count &&
            !allPromptTokens.isEmpty &&
            !generationKVCache.isEmpty {

            var physicalTokens: [Int] = []

            physicalTokens.reserveCapacity(
                allPromptTokens.count +
                actualGeneratedTokenIDs.count
            )

            physicalTokens.append(contentsOf: allPromptTokens)
            physicalTokens.append(contentsOf: actualGeneratedTokenIDs)

            let branchId = makeBranchID(
                logicalBranchId: targetLogicalBranchId,
                toolFingerprint: toolFingerprint,
                promptTokens: allPromptTokens
            )

            let revision = PhysicalKVRevision(
                id: branchId,
                logicalBranchId: targetLogicalBranchId,
                toolFingerprint: toolFingerprint,
                physicalTokens: physicalTokens,
                kvCache: generationKVCache,
                lastActive: Date()
            )

            let revisionsToRelease = state.withLock { state -> [PhysicalKVRevision] in
                var retained: [PhysicalKVRevision] = []
                var toRelease: [PhysicalKVRevision] = []

                retained.reserveCapacity(
                    state.physicalRevisions.count + 1
                )

                for existing in state.physicalRevisions {
                    if existing.id == revision.id ||
                        (existing.logicalBranchId == revision.logicalBranchId &&
                         existing.toolFingerprint == revision.toolFingerprint &&
                         existing.physicalTokens == revision.physicalTokens) {
                        toRelease.append(existing)
                    } else {
                        retained.append(existing)
                    }
                }

                retained.append(revision)
                retained.sort {
                    $0.lastActive > $1.lastActive
                }

                let maxPhysicalRevisions = Self.maxPhysicalKVRevisions

                if retained.count > maxPhysicalRevisions {
                    let discarded = Array(
                        retained.suffix(from: maxPhysicalRevisions)
                    )

                    toRelease.append(contentsOf: discarded)
                    retained.removeLast(
                        retained.count - maxPhysicalRevisions
                    )
                }

                state.physicalRevisions = retained

                if var session = state.sessionCaches[sessionKey],
                   var logical = session.logicalBranches[targetLogicalBranchId] {
                    logical.lastActive = Date()
                    logical.toolFingerprint = toolFingerprint

                    session.logicalBranches[targetLogicalBranchId] = logical
                    session.lastActive = Date()

                    state.sessionCaches[sessionKey] = session
                }

                return toRelease
            }

            if !revisionsToRelease.isEmpty {
                await MainActor.run {
                    for var oldRevision in revisionsToRelease {
                        oldRevision.releasePhysicalMemory()
                    }
                }

                Memory.clearCache()
            }

            kvCommittedSuccessfully = true

            traceLogger.trace(
                "[KVC] src=G rev=\(branchId) br=\(targetLogicalBranchId) p=\(allPromptTokens.count) g=\(actualGeneratedTokenIDs.count) ktok=\(physicalTokens.count) revs=\(state.withLock { $0.physicalRevisions.count }) ok",
                session: traceSession
            )

            emitRuntimeObservation(
                "kv-commit",
                requestId: requestId,
                executionKey: executionKey
            )
        } else if isInterrupted || Task.isCancelled {
            Service.log(
                "🛑 [NativeMLX] 本轮生成已中断/取消，安全跳过 KV Cache Commit"
            )

            traceLogger.trace(
                "[CXL] request=\(requestId) kv=0",
                session: traceSession
            )

            emitRuntimeObservation(
                "cancelled",
                requestId: requestId,
                executionKey: executionKey
            )
        }

        traceLogger.trace(
            "[DEG] br=\(targetLogicalBranchId) round=\(currentDegenerationState.round) rep=\(currentDegenerationState.consecutive) cand=\(candidateSignatures.count) fwd=\(actualForwardedSignatures.count) kv=\(kvCommittedSuccessfully ? 1 : 0) adv=\(stateAdvanced ? 1 : 0) ph=\(semanticProgressHash)",
            session: traceSession
        )

        // MARK: Performance Telemetry

        let totalDuration = Date().timeIntervalSince(t0)

        let decodeTPS = actualGeneratedTokenIDs.count > 0
            ? Double(actualGeneratedTokenIDs.count) / decodeWallTime
            : 0

        let prefillTPS = promptPrefillTime > 0.001
            ? Double(deltaTokenCount) / promptPrefillTime
            : 0

        let branchCount = state.withLock {
            $0.physicalRevisions.count
        }

        let perfSummary = "[PERF] r=\(requestId)" +
            " ttft=\(String(format: "%.3f", promptPrefillTime))s" +
            " pre=\(String(format: "%.1f", prefillTPS))/s" +
            " d=\(String(format: "%.1f", decodeTPS))/s" +
            " p=\(allPromptTokens.count)" +
            " cp=\(selectedCommonLen)" +
            " cache=\(selectedBranch?.physicalTokens.count ?? 0)" +
            " tok=\(actualGeneratedTokenIDs.count)" +
            " tool=\(toolCallDetected ? 1 : 0)" +
            " fwd=\(forwardedToolCount)" +
            " rev=\(branchCount)" +
            " dur=\(String(format: "%.2f", totalDuration))s"

        Service.log(
            "📈 [MLX] r=\(requestId) p=\(allPromptTokens.count) cp=\(selectedCommonLen) tok=\(actualGeneratedTokenIDs.count) tool=\(toolCallDetected ? 1 : 0) rev=\(branchCount) dur=\(String(format: "%.2f", totalDuration))s"
        )

        traceLogger.trace(
            perfSummary,
            session: traceSession
        )

        emitRuntimeObservation(
            "request-complete",
            requestId: requestId,
            executionKey: executionKey
        )

        return completedText
    }

    // MARK: - Session / Logical Cache Maintenance

    private func purgeStaleSessionCachesLocked(_ state: inout State) {
        let now = Date()

        for sessionID in Array(state.sessionCaches.keys) {
            guard var session = state.sessionCaches[sessionID] else {
                continue
            }

            let activeBranches = session.logicalBranches.filter {
                _, branch in
                now.timeIntervalSince(branch.lastActive) < Self.sessionMaxIdleTime
            }

            if activeBranches.isEmpty {
                state.sessionCaches.removeValue(
                    forKey: sessionID
                )
            } else {
                session.logicalBranches = Dictionary(
                    uniqueKeysWithValues: activeBranches.map {
                        ($0.key, $0.value)
                    }
                )

                session.lastActive =
                    session.logicalBranches.values
                    .map(\.lastActive)
                    .max() ?? now

                state.sessionCaches[sessionID] = session
            }
        }
    }

    // MARK: - Tool Fingerprint

    private nonisolated func makeToolFingerprint(
        _ tools: [[String: any Sendable]]?
    ) -> String {
        guard let tools, !tools.isEmpty else {
            return "none"
        }

        let canonical = tools
            .map { canonicalValue($0) }
            .joined(separator: "\n")

        let digest = SHA256.hash(
            data: Data(canonical.utf8)
        )

        return digest
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(16)
            .description
    }

    // MARK: - Branch ID

    private nonisolated func makeBranchID(
        logicalBranchId: String,
        toolFingerprint: String,
        promptTokens: [Int]
    ) -> String {
        var hasher = SHA256()

        hasher.update(data: Data(logicalBranchId.utf8))
        hasher.update(data: Data([0]))
        hasher.update(data: Data(toolFingerprint.utf8))
        hasher.update(data: Data([0]))

        for token in promptTokens {
            var value = UInt64(
                bitPattern: Int64(token)
            ).bigEndian

            withUnsafeBytes(of: &value) {
                hasher.update(data: $0)
            }
        }

        let digest = hasher.finalize()

        return digest
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(16)
            .description
    }

    // MARK: - Common Prefix

    private nonisolated func computeCommonPrefix(
        _ a: [Int],
        _ b: [Int]
    ) -> Int {
        let limit = min(a.count, b.count)
        var count = 0

        while count < limit, a[count] == b[count] {
            count += 1
        }

        return count
    }

    // MARK: - Cancellation

    public func cancelGeneration(requestId: String) {
        let handles = state.withLock { state in
            (
                request: state.activeRequestTasks[requestId],
                generation: state.activeGenerationTasks[requestId]
            )
        }

        traceLogger.trace(
            "[CANCEL REQUEST] request=\(requestId), hasRequestTask=\(handles.request != nil), hasGenerationTask=\(handles.generation != nil)"
        )

        // 统一终止入口（收敛文档 §5）：账本进入取消释放序列；真实 task 取消仍在下方执行。
        Task {
            await RuntimeLifecycleCoordinator.shared.finish(
                requestID: requestId,
                success: false,
                reason: "cancel_generation"
            )
        }
        handles.request?.cancel()
        handles.generation?.cancel()

        emitRuntimeObservation(
            "cancel-request-issued",
            requestId: requestId
        )
    }
}
