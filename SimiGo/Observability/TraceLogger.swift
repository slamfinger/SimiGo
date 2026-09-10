import Foundation

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

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private init() {
        let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".simigo/logs", isDirectory: true)

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
            for line in normalized.split(separator: "\n", omittingEmptySubsequences: true) {
                let output = "[\(Self.timestampFormatter.string(from: Date()))] \(prefix)\(line)\n"
                guard let encoded = output.data(using: .utf8) else { continue }
                self.writeLocked(encoded)
            }
        }
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
