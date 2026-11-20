import Foundation
import SimiGoRuntimeContract

// MARK: - Dedicated File Trace Logger (~/.simigo/logs)

/// Small serialized file logger used by NativeMLX diagnostics.
///
/// The logger deliberately does not own log formatting, KV diagnostics, or protocol state.
/// External process output keeps a tiny compatibility path for the legacy llama.cpp pipe.
nonisolated final class RuntimeTraceLogger: @unchecked Sendable {
    static let shared = RuntimeTraceLogger()

    private let logFileURL: URL
    private let queue = DispatchQueue(label: "com.simigo.runtime.tracelogger", qos: .utility)
    private var fileHandle: FileHandle?
    private var isClosed = false
    private var bytesWritten: UInt64 = 0

    /// Bound the diagnostic file: rotate at 8 MB and keep four generations
    /// (~40 MB total). The readings the traces exist for stay available for
    /// recent history; the unbounded single file (37.9 MB after two weeks)
    /// was the actual bloat.
    private static let maximumBytes: UInt64 = 8 * 1024 * 1024
    private static let retainedArchives = 4

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private init() {
        // Resolved through the shared runtime path resolver so that an isolated
        // test/experiment root (SIMIGO_HOME) also relocates the trace log. With no
        // override this is still <home>/.simigo/logs: default behaviour is unchanged,
        // only the previously hardcoded home is now injectable.
        let logsDirectory = ManagedPaths.logs

        try? FileManager.default.createDirectory(
            at: logsDirectory,
            withIntermediateDirectories: true
        )

        self.logFileURL = logsDirectory.appendingPathComponent("native_mlx_trace.log")
    }

    deinit {
        queue.sync {
            try? fileHandle?.close()
            fileHandle = nil
            isClosed = true
        }
    }

    func trace(_ message: String) {
        queue.async { [weak self] in
            guard let self else { return }

            let timestamp = Self.timestampFormatter.string(from: Date())
            let line = "[\(timestamp)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }

            self.writeLocked(data)
        }
    }

    /// 诊断档开关（2026-11-05 日志瘦身）：默认不落 verbose 行。
    ///
    /// 只影响“留档取证”的粒度，不改变任何调用点语义 —— 需要复现
    /// 1.7 时代的工具回显/前缀分叉细节时，`SIMIGO_TRACE_VERBOSE=1`
    /// 启动即恢复全量。
    static var verboseEnabled: Bool {
        ProcessInfo.processInfo.environment["SIMIGO_TRACE_VERBOSE"] == "1"
    }

    /// 诊断档 trace：未开 verbose 时整行丢弃。
    func traceVerbose(_ message: String) {
        guard Self.verboseEnabled else { return }
        trace(message)
    }

    /// trace 内长标识的统一压缩口径：一律 6 字符，与 `[LC] r=/s=` 同源
    /// （`req-` 前缀先剥掉，保证与 Lifecycle 的短 id 逐字节一致）。
    /// 只做展示截断，不参与任何判定（不可回读）。
    static func short(_ id: String) -> String {
        var value = id
        for prefix in ["req-", "info-"] where value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
        }
        return value.count > 6 ? String(value.prefix(6)) : value
    }

    /// Compatibility path for the external llama.cpp stdout/stderr pipe.
    /// Keeps the raw stream outside the normal diagnostic formatter.
    func rawProcessOutput(_ data: Data, prefix: String = "[llama.cpp] ") {
        guard !data.isEmpty else { return }
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }

        queue.async { [weak self] in
            guard let self else { return }
            let normalized = text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            for line in normalized.split(separator: "\n", omittingEmptySubsequences: true)
            where Self.verboseEnabled || Self.keepRawProcessLine(line) {
                let output = "[\(Self.timestampFormatter.string(from: Date()))] \(prefix)\(line)\n"
                guard let encoded = output.data(using: .utf8) else { continue }
                self.writeLocked(encoded)
            }
        }
    }

    /// 原始流过滤（2026-11-05 瘦身）：llama.cpp 的 `I` 级行（初始化横幅、
    /// slot 启停、graph realloc、get_available 轮询）是 1.7 GGUF 时代验证
    /// 启动参数的取证手段，现在既无对应问题也无判定依赖；只留 W/E/F 与
    /// 每请求两行 `print_timing`（预填耗时、生成耗时），引擎侧时延仍可核。
    private static func keepRawProcessLine(_ line: Substring) -> Bool {
        guard line.contains(" I ") else { return true }
        return line.contains(" n_gen = ") || line.contains("prompt processing")
    }

    func flush() {
        queue.sync {
            fileHandle?.synchronizeFile()
        }
    }

    private func openFileHandleLocked() {
        guard fileHandle == nil else { return }

        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            try? Data().write(to: logFileURL)
        }

        guard let handle = try? FileHandle(forWritingTo: logFileURL) else { return }
        handle.seekToEndOfFile()
        bytesWritten = handle.offsetInFile
        fileHandle = handle
        isClosed = false
    }

    private func rotateLocked() {
        closeFileHandleLocked()
        let fm = FileManager.default
        func archive(_ index: Int) -> URL { logFileURL.appendingPathExtension("\(index)") }
        try? fm.removeItem(at: archive(Self.retainedArchives))
        for index in stride(from: Self.retainedArchives - 1, through: 1, by: -1) {
            guard fm.fileExists(atPath: archive(index).path) else { continue }
            try? fm.moveItem(at: archive(index), to: archive(index + 1))
        }
        try? fm.moveItem(at: logFileURL, to: archive(1))
        bytesWritten = 0
        openFileHandleLocked()
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

        if bytesWritten + UInt64(data.count) > Self.maximumBytes {
            rotateLocked()
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
            bytesWritten += UInt64(data.count)
        } catch {
            closeFileHandleLocked()
        }
    }
}
