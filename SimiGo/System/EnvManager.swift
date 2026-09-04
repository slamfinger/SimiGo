import Foundation
import Combine

/// Manages external process dependencies and the shared command console.
/// Native MLX itself does not require an external Python environment.
@MainActor
public final class EnvManager: ObservableObject {
    public static let shared = EnvManager()

    // MARK: - Environment
                @Published public var statusMessage = "未构建"

    // MARK: - Hugging Face
    @Published public var isDownloading = false
    @Published public var downloadLog = ""
    @Published public var downloadProgress: Double = 0

    // MARK: - Shared Command Console
    @Published public var commandInput = "hf download "
    @Published public var commandLog = ""
    @Published public var isRecording = false
    @Published public var commandStatus = "就绪"

    // MARK: - Paths
    public static var simigoDir: String { "\(NSHomeDirectory())/.simigo" }
    public static var binDir: String { "\(simigoDir)/bin" }
    public static var modelsDir: String { "\(simigoDir)/models" }
    public static var logsDir: String { "\(simigoDir)/logs" }
    public static var nativeMLXTraceLog: String { "\(logsDir)/native_mlx_trace.log" }

    public static var llamaServerExecutable: String {
        Self.findSystemLlamaServer() ?? "\(binDir)/llama-server"
    }

    public var hasLlamaServer: Bool { Self.findSystemLlamaServer() != nil }
    public var isEnvironmentReady: Bool { hasLlamaServer }

    // MARK: - Process State
    private var traceProcess: Process?
    private var tracePipe: Pipe?

    private init() {
        checkStatus()
    }

    // MARK: - Status
    public func checkStatus() {
        statusMessage = hasLlamaServer ? "llama.cpp 就绪" : "仅 Native MLX 可用，llama.cpp 未安装"
    }

    // MARK: - Shared Command Console
    public func clearCommandLog() {
        commandLog = ""
    }

    public func appendCommandLog(_ message: String) {
        guard !message.isEmpty else { return }
        commandLog += message
        if !message.hasSuffix("\n") { commandLog += "\n" }
        print(message)
    }

    public func setCommand(_ command: String) {
        commandInput = command
    }

    public func executeCommand(_ command: String) async {
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        commandInput = normalized
        commandStatus = "执行中"
        appendCommandLog("$ \(normalized)")

        do {
            try await runCommandWithEnv(command: normalized, workDir: URL(fileURLWithPath: NSHomeDirectory())) { [weak self] output in
                guard let self else { return }
                self.appendCommandLog(output)
            }
            commandStatus = "执行完成"
        } catch {
            commandStatus = "执行失败"
            appendCommandLog("❌ 执行失败：\(error.localizedDescription)")
        }
    }

    // MARK: - Native MLX Trace
    public func startTraceRecording() {
        guard !isRecording else {
            appendCommandLog("⚠️ Native MLX 记录已经在运行。")
            return
        }

        let fm = FileManager.default
        do {
            try fm.createDirectory(atPath: Self.logsDir, withIntermediateDirectories: true)
            if !fm.fileExists(atPath: Self.nativeMLXTraceLog) {
                fm.createFile(atPath: Self.nativeMLXTraceLog, contents: nil)
            }
        } catch {
            commandStatus = "记录启动失败"
            appendCommandLog("❌ 无法创建 Native MLX 日志目录：\(error.localizedDescription)")
            return
        }

        stopTraceRecording()

        commandInput = "tail -f ~/.simigo/logs/native_mlx_trace.log"
        commandStatus = "记录中"
        isRecording = true
        appendCommandLog("$ tail -f ~/.simigo/logs/native_mlx_trace.log")

        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
        process.arguments = ["-f", Self.nativeMLXTraceLog]
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        process.environment = ProcessRunner.env()
        process.standardOutput = pipe
        process.standardError = pipe

        traceProcess = process
        tracePipe = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.appendCommandLog(text)
            }
        }

        process.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.tracePipe?.fileHandleForReading.readabilityHandler = nil
                self.traceProcess = nil
                self.tracePipe = nil
                self.isRecording = false
                if process.terminationStatus == 0 {
                    self.commandStatus = "记录已停止"
                } else {
                    self.commandStatus = "记录已结束"
                    self.appendCommandLog("⚠️ Native MLX trace 进程结束，退出码：\(process.terminationStatus)")
                }
            }
        }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            traceProcess = nil
            tracePipe = nil
            isRecording = false
            commandStatus = "记录启动失败"
            appendCommandLog("❌ 无法启动 tail：\(error.localizedDescription)")
        }
    }

    public func stopTraceRecording() {
        guard let process = traceProcess else {
            isRecording = false
            if commandStatus == "记录中" { commandStatus = "记录已停止" }
            return
        }

        tracePipe?.fileHandleForReading.readabilityHandler = nil

        if process.isRunning {
            process.terminate()
        }

        traceProcess = nil
        tracePipe = nil
        isRecording = false

        if commandStatus == "记录中" {
            commandStatus = "记录已停止"
        }

        appendCommandLog("⏹ Native MLX trace 记录已停止。")
    }

    public func toggleTraceRecording() {
        if isRecording {
            stopTraceRecording()
        } else {
            startTraceRecording()
        }
    }

    // MARK: - llama.cpp Environment Setup
    public func setupEnvironment() async {

        commandInput = "llama.cpp build"
        commandStatus = "构建中"
        appendCommandLog("🚀 开始准备 SimiGo 外部依赖：llama.cpp")

        let fm = FileManager.default

        do {
            try fm.createDirectory(atPath: Self.simigoDir, withIntermediateDirectories: true)
            try fm.createDirectory(atPath: Self.binDir, withIntermediateDirectories: true)
            try fm.createDirectory(atPath: Self.modelsDir, withIntermediateDirectories: true)
            try fm.createDirectory(atPath: Self.logsDir, withIntermediateDirectories: true)

            guard let git = Self.findTool("git") else {
                throw NSError(domain: "EnvManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "未找到 git，请先安装 Xcode Command Line Tools。"])
            }

            guard let cmake = Self.findTool("cmake") else {
                throw NSError(domain: "EnvManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "未找到 cmake，请安装 cmake。"])
            }

            let source = "\(Self.simigoDir)/llama.cpp"

            if !fm.fileExists(atPath: source) {
                appendCommandLog("📥 克隆 llama.cpp...")
                try await runCommand(git, args: ["clone", "https://github.com/ggml-org/llama.cpp.git", source])
            } else {
                appendCommandLog("🔄 更新 llama.cpp...")
                try? await runCommand(git, args: ["-C", source, "pull", "--ff-only"])
            }

            let build = "\(source)/build"

            if fm.fileExists(atPath: "\(build)/CMakeCache.txt") {
                appendCommandLog("⚡ 检测到已有缓存，执行高效增量构建...")
            } else {
                appendCommandLog("🧹 清理旧构建缓存以解决符号冲突...")
                try? fm.removeItem(atPath: build)
            }

            appendCommandLog("🛠️ 配置 Metal 构建...")
            try await runCommand(cmake, args: ["-B", build, "-S", source, "-DCMAKE_BUILD_TYPE=Release", "-DGGML_METAL=ON"])

            appendCommandLog("🔨 编译 llama-server...")
            try await runCommand(cmake, args: ["--build", build, "--config", "Release", "--target", "llama-server", "-j"])

            let builtBinaries = ["\(build)/bin/llama-server", "\(build)/bin/Release/llama-server", "\(build)/llama-server"]
            let targetBin = "\(Self.binDir)/llama-server"
            var installed = false

            for binPath in builtBinaries {
                if fm.fileExists(atPath: binPath) {
                    try? fm.removeItem(atPath: targetBin)
                    try fm.copyItem(atPath: binPath, toPath: targetBin)
                    try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: targetBin)

                    let home = NSHomeDirectory()
                    let localBin = "\(home)/.local/bin"
                    try? fm.createDirectory(atPath: localBin, withIntermediateDirectories: true)

                    let llamaServerLink = "\(localBin)/llama-server"
                    try? fm.removeItem(atPath: llamaServerLink)
                    try? fm.createSymbolicLink(atPath: llamaServerLink, withDestinationPath: targetBin)

                    let llamaWrapper = "\(localBin)/llama"
                    try? fm.removeItem(atPath: llamaWrapper)

                    let script = """
                    #!/bin/zsh
                    if [[ $# -eq 0 ]]; then
                        exec llama-server
                    else
                        if [[ $1 == serve ]]; then
                            shift
                            exec llama-server "$@"
                        else
                            exec llama-server "$@"
                        fi
                    fi
                    """

                    try? script.write(toFile: llamaWrapper, atomically: true, encoding: .utf8)
                    try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: llamaWrapper)

                    appendCommandLog("📌 已将 llama-server 安装到全局路径: \(targetBin)")
                    installed = true
                    break
                }
            }

            guard installed else {
                throw NSError(domain: "EnvManager", code: 501, userInfo: [NSLocalizedDescriptionKey: "llama-server 构建完成，但未找到构建产物。"])
            }


            let targetHf = "\(Self.binDir)/hf"

            if fm.fileExists(atPath: targetHf) {
                appendCommandLog("⚡ 检测到已安装官方 hf 工具，跳过重复安装。")
            } else {
                appendCommandLog("📥 正在安装官方 Hugging Face CLI 到 \(Self.simigoDir)...")
                try await runCommand("/bin/zsh", args: ["-c", "curl -LsSf https://hf.co/cli/install.sh | INSTALL_PREFIX=\(Self.simigoDir) bash"])
                appendCommandLog("✅ 官方 hf 工具已就绪。")
            }


            guard Self.findSystemLlamaServer() != nil else {
                throw NSError(domain: "EnvManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "llama-server 编译完成但未找到可执行文件。"])
            }

            appendCommandLog("🎉 llama-server 就绪。Native MLX 无需安装外部运行时。")
            commandStatus = "构建完成"
            checkStatus()
        } catch {
            appendCommandLog("❌ 构建中断：\(error.localizedDescription)")
            commandStatus = "构建失败"
            statusMessage = "构建失败"
        }
    }


    // MARK: - Process Runner
    private func runCommand(_ cmd: String, args: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: cmd)
            process.arguments = args
            process.environment = ProcessRunner.env()

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }

                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { return }

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.appendCommandLog(clean)
                }
            }

            process.terminationHandler = { process in
                pipe.fileHandleForReading.readabilityHandler = nil

                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(domain: "EnvManager", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "命令失败，退出码 \(process.terminationStatus)"]))
                }
            }

            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Tool Detection
    public static func findTool(_ name: String) -> String? {
        let home = NSHomeDirectory()
        let paths = ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)", "\(home)/.local/bin/\(name)", "\(binDir)/\(name)"]

        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    // MARK: - llama-server Detection
    public static func findSystemLlamaServer() -> String? {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let source = "\(simigoDir)/llama.cpp"

        let candidates = [
            "\(binDir)/llama-server",
            "\(source)/build/bin/llama-server",
            "\(source)/build/bin/Release/llama-server",
            "\(source)/build/llama-server",
            "\(home)/llama.cpp/build/bin/llama-server",
            "/opt/homebrew/bin/llama-server",
            "/usr/local/bin/llama-server",
            "\(home)/.local/bin/llama-server"
        ]

        if let configured = AppConfig.llamaServerBin?.path, fm.isExecutableFile(atPath: configured) {
            return configured
        }

        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    // MARK: - Hugging Face Command Parser
    public static func formatDownloadCommand(_ input: String) -> String {
        var raw = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if raw.contains(" --") {
            if !raw.hasPrefix("hf download ") && !raw.hasPrefix("huggingface-cli download ") {
                return "hf download \(raw)"
            }
            return raw
        }

        if raw.hasPrefix("hf download ") {
            raw = String(raw.dropFirst("hf download ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if raw.hasPrefix("huggingface-cli download ") {
            raw = String(raw.dropFirst("huggingface-cli download ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var repoTypeFlag = ""

        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            if let url = URL(string: raw), let host = url.host, host.contains("huggingface.co") || host.contains("hf-mirror.com") {
                var pathParts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

                if pathParts.first == "datasets" {
                    repoTypeFlag = " --repo-type dataset"
                    pathParts.removeFirst()
                } else if pathParts.first == "spaces" {
                    repoTypeFlag = " --repo-type space"
                    pathParts.removeFirst()
                }

                if pathParts.count >= 2 {
                    let repoId = "\(pathParts[0])/\(pathParts[1])"

                    if pathParts.count >= 4 && (pathParts[2] == "tree" || pathParts[2] == "blob") {
                        let subpath = pathParts.dropFirst(4).joined(separator: "/")
                        return buildHfDownload(repoId: repoId, subpath: subpath, extraFlags: repoTypeFlag)
                    } else if pathParts.count > 2 {
                        let subpath = pathParts.dropFirst(2).joined(separator: "/")
                        return buildHfDownload(repoId: repoId, subpath: subpath, extraFlags: repoTypeFlag)
                    }

                    return "hf download \(repoId)\(repoTypeFlag)"
                }
            }
        }

        if raw.hasPrefix("hf://") {
            raw = String(raw.dropFirst(5))

            if raw.hasPrefix("datasets/") {
                repoTypeFlag = " --repo-type dataset"
                raw = String(raw.dropFirst("datasets/".count))
            } else if raw.hasPrefix("spaces/") {
                repoTypeFlag = " --repo-type space"
                raw = String(raw.dropFirst("spaces/".count))
            }
        }

        let components = raw.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        if components.count >= 3 {
            let repoId = "\(components[0])/\(components[1])"
            let subpath = components.dropFirst(2).joined(separator: "/")
            return buildHfDownload(repoId: repoId, subpath: subpath, extraFlags: repoTypeFlag)
        } else if components.count == 2 {
            return "hf download \(components[0])/\(components[1])\(repoTypeFlag)"
        } else if !raw.isEmpty {
            return "hf download \(raw)\(repoTypeFlag)"
        }

        return "hf download \(raw)"
    }

    private static func buildHfDownload(repoId: String, subpath: String, extraFlags: String = "") -> String {
        let cleanSubpath = subpath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))

        guard !cleanSubpath.isEmpty else {
            return "hf download \(repoId)\(extraFlags)"
        }

        if cleanSubpath.contains("*") || cleanSubpath.contains("?") {
            return "hf download \(repoId) --include \"\(cleanSubpath)\"\(extraFlags)"
        }

        let knownFileExtensions = ["safetensors", "bin", "gguf", "json", "txt", "md", "pt", "pth", "model", "yaml", "yml", "py", "jinja", "onnx", "msgpack", "h5", "tflite", "csv", "parquet"]

        let lastComponent = cleanSubpath.split(separator: "/").last.map(String.init) ?? cleanSubpath
        let ext = lastComponent.split(separator: ".").last.map(String.init)?.lowercased() ?? ""
        let isFile = lastComponent.contains(".") && knownFileExtensions.contains(ext)

        if isFile {
            return "hf download \(repoId) --include \"\(cleanSubpath)\"\(extraFlags)"
        } else {
            return "hf download \(repoId) --include \"\(cleanSubpath)/*\"\(extraFlags)"
        }
    }

    // MARK: - Hugging Face Download
    public func downloadModel(command: String) async {
        guard !isDownloading else { return }

        let cmd = Self.formatDownloadCommand(command)

        isDownloading = true
        downloadProgress = 0
        downloadLog = "🚀 开始执行模型下载 (自动注入 HF_ENDPOINT=https://hf-mirror.com)...\n$ \(cmd)\n"
        commandInput = cmd
        commandStatus = "下载中"
        appendCommandLog("$ \(cmd)")

        var fullOutput = ""

        do {
            try await runCommandWithEnv(command: cmd, workDir: URL(fileURLWithPath: NSHomeDirectory())) { [weak self] output in
                guard let self else { return }
                fullOutput += output + "\n"
                self.downloadLog += output + "\n"
                self.appendCommandLog(output)
            }

            if fullOutput.contains("Fetching 0 files") {
                let warning = "\n⚠️ 未匹配到任何文件 (Fetching 0 files)！\n💡 提示：该仓库没有该子目录/文件。请检查仓库路径。\n"
                downloadLog += warning
                commandLog += warning
            } else {
                downloadLog += "\n🎉 下载/执行成功！\n"
                appendCommandLog("🎉 下载/执行成功！")
            }

            downloadProgress = 1.0
            commandStatus = "下载完成"
        } catch {
            let message = "\n❌ 执行失败：\(error.localizedDescription)\n"
            downloadLog += message
            appendCommandLog(message)
            commandStatus = "下载失败"
        }

        isDownloading = false
    }

    // MARK: - Command Runner With Environment
    private func runCommandWithEnv(command: String, workDir: URL, onOutput: @escaping @MainActor @Sendable (String) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            process.currentDirectoryURL = workDir
            process.environment = ProcessRunner.env()

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }

                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { return }

                Task { @MainActor in
                    onOutput(clean)
                }
            }

            process.terminationHandler = { process in
                pipe.fileHandleForReading.readabilityHandler = nil

                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(domain: "EnvManager", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "命令失败，退出码 \(process.terminationStatus)"]))
                }
            }

            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}
