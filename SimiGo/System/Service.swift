import Foundation
import AppKit
import SwiftUI
import Combine
import Synchronization
import Darwin

// MARK: - Error

public enum ServiceError: LocalizedError, Sendable {
    case notLoaded
    case portInUse(Int)
    case startupTimeout
    case backendNotAvailable(String)

    public var errorDescription: String? {
        switch self {
        case .notLoaded: return "运行时未加载模型"
        case .portInUse(let port): return "端口 \(port) 已被占用"
        case .startupTimeout: return "服务启动超时"
        case .backendNotAvailable(let msg): return msg
        }
    }
}

// MARK: - Global Shared Process Helpers

nonisolated private func runShell(_ command: String) async -> String {
    await Task.detached(priority: .utility) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", command]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }.value
}

nonisolated private func processIDsOnPort(_ port: Int) async -> [Int32] {
    let output = await runShell("lsof -nP -tiTCP:\(port) -sTCP:LISTEN 2>/dev/null")
    return output.split(whereSeparator: \.isNewline).compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
}

nonisolated private func processCommandLine(_ pid: Int32) async -> String {
    await runShell("ps -p \(pid) -o command= 2>/dev/null")
}

nonisolated private func isProcessMatch(_ command: String, executable: String) -> Bool {
    let expectedName = URL(fileURLWithPath: executable).lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !expectedName.isEmpty else { return false }
    return command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().contains(expectedName)
}

nonisolated private func cleanupOwnedProcessesOnPort(_ port: Int, executable: String) async -> Bool {
    let pids = await processIDsOnPort(port)
    guard !pids.isEmpty else { return true }
    var foundForeignProcess = false
    for pid in pids {
        let command = await processCommandLine(pid)
        if isProcessMatch(command, executable: executable) {
            kill(pid, SIGKILL)
        } else {
            foundForeignProcess = true
        }
    }
    if foundForeignProcess { return false }
    try? await Task.sleep(nanoseconds: 150_000_000)
    return (await processIDsOnPort(port)).isEmpty
}

nonisolated private func getSwapUsedMegabytes() -> Int? {
    var usage = xsw_usage()
    var size = MemoryLayout<xsw_usage>.size
    guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
    return Int(usage.xsu_used / 1024 / 1024)
}

// MARK: - Backend Configuration

public struct BackendConfig: Sendable {
    public let name: String
    private let customExecutable: String?

    public var executable: String {
        guard kind == .gguf else { return "" }
        if let custom = customExecutable, !custom.isEmpty { return custom }
        if let configured = AppConfig.llamaServerBin?.path, FileManager.default.fileExists(atPath: configured) { return configured }
        return EnvManager.findSystemLlamaServer() ?? AppConfig.defaultLlamaServerBinPath
    }

    /// ModelInfo + ModelConfig + Port → 一次性编译为 launchArgs。
    /// ProcessRuntime 不重新生成参数。
    public let args: @Sendable (ModelInfo, ModelConfig, Int) -> [String]
    public let healthEndpoint: String
    public let startupTimeout: TimeInterval
    public let kind: ModelKind

    nonisolated public static let dynamicMetalMemoryLimitMB: String = {
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let limitMB = Int(Double(totalMemory) * 0.85 / (1024 * 1024))
        return "\(max(4096, limitMB))"
    }()

    public init(name: String, customExecutable: String? = nil, args: @escaping @Sendable (ModelInfo, ModelConfig, Int) -> [String], healthEndpoint: String, startupTimeout: TimeInterval, kind: ModelKind) {
        self.name = name
        self.customExecutable = customExecutable
        self.args = args
        self.healthEndpoint = healthEndpoint
        self.startupTimeout = startupTimeout
        self.kind = kind
    }

    // MARK: - llama.cpp Argument Builder

    nonisolated public static let llama = BackendConfig(
        name: "llama.cpp",
        customExecutable: nil,
        args: { info, config, port in
            let modelAlias = modelName(from: info.path)
            let endpoint = InferenceNodeConfiguration.shared.snapshot()
            let environment = ProcessInfo.processInfo.environment
            let configuredParallel = Int(environment["SIMIGO_LLAMA_PARALLEL"] ?? "1") ?? 1
            let parallelSlots = max(1, min(2, configuredParallel))
            let configuredNGL = Int(environment["SIMIGO_LLAMA_NGL"] ?? "\(config.gpuLayers)") ?? config.gpuLayers
            let gpuLayers = max(0, min(999, configuredNGL))
            var args: [String] = [
                "--model", info.path,
                "--port", "\(port)",
                "--host", endpoint.bindHost,
                "--alias", modelAlias,
                "--parallel", "\(parallelSlots)",
                "--cache-prompt",
                "--slots",
                "--cache-type-k", "q4_0",
                "--cache-type-v", "q4_0",
                "-ngl", "\(gpuLayers)",
                "-b", "1024",
                "-ub", "512",
                "--ctx-size", "\(max(1024, config.ctxSize))"
            ]
            args.reserveCapacity(42)

            // MARK: Chat Template / Jinja

            if config.useChatTemplate {
                let lowerPath = info.path.lowercased()
                let template: String
                if !config.chatTemplate.isEmpty {
                    template = config.chatTemplate
                } else if lowerPath.contains("qwen") || config.codexMode {
                    template = "chatml"
                } else {
                    template = ""
                }
                if !template.isEmpty {
                    args.append(contentsOf: ["--chat-template", template])
                }
                if config.jinja || config.codexMode || !config.chatTemplate.isEmpty {
                    args.append("--jinja")
                }
            }

            // MARK: Speculative Decoding

            let speculativeEnabled = config.useMTP
            if speculativeEnabled {
                if let draft = info.draftModelPath, !draft.isEmpty, FileManager.default.fileExists(atPath: draft) {
                    let draftName = URL(fileURLWithPath: draft).lastPathComponent
                    let specType = Detector.isDFlashModel(draftName) ? "draft-dflash" : "draft-mtp"
                    let defaultNMax = max(1, config.specDraftNMax)
                    let configuredNMax = Int(environment["SIMIGO_LLAMA_SPEC_NMAX"] ?? "\(defaultNMax)") ?? defaultNMax
                    let nMax = max(1, min(8, configuredNMax))
                    args.append(contentsOf: ["--model-draft", draft, "--spec-type", specType, "--spec-draft-n-max", "\(nMax)"])
                    if gpuLayers > 0 {
                        args.append(contentsOf: ["--spec-draft-ngl", "\(gpuLayers)"])
                    }
                    Service.log("⚡ Speculative Decoding: ON | type=\(specType) | nMax=\(nMax) | draft=\(draftName)")
                } else {
                    Service.log("⚠️ Speculative Decode 已启用，但未找到有效 Draft 模型，跳过。", level: .warning)
                }
            }

            // MARK: Flash Attention

            let flashAttention = environment["SIMIGO_LLAMA_FLASH_ATTN"] ?? "on"
            let flashEnabled = !["off", "0", "false"].contains(flashAttention.lowercased())
            args.append(contentsOf: ["--flash-attn", flashEnabled ? "on" : "off"])

            // MARK: Multi-Modal Projector

            if let mmproj = info.mmprojPath, !mmproj.isEmpty, FileManager.default.fileExists(atPath: mmproj) {
                args.append(contentsOf: ["--mmproj", mmproj])
            }

            // MARK: Sampling

            args.append(contentsOf: [
                "--temp", "\(config.temperature)",
                "--top-p", "\(config.topP)",
                "--top-k", "\(config.topK)",
                "--min-p", "\(config.minP)",
                "--repeat-penalty", "\(config.repeatPenalty)",
                "--presence-penalty", "\(config.presencePenalty)"
            ])

            return args
        },
        healthEndpoint: "/health",
        startupTimeout: 180,
        kind: .gguf
    )
}

// MARK: - Runtime Protocol

public protocol Runtime: AnyObject, Sendable {
    var isRunning: Bool { get }
    var isGenerating: Bool { get }
    var isInProcess: Bool { get }
    func start(_ info: ModelInfo, port: Int) async throws
    func stop() async
    func checkHealth() async -> Bool
}

// MARK: - External Process Runtime

private final class ProcessRuntime: Runtime, @unchecked Sendable {
    private struct State: @unchecked Sendable {
        var process: Process?
        var isRunning = false
        var isStopping = false
        var port = InferenceNodeDefaults.apiPort
        var healthURLString = ""
    }

    private let state = Mutex(State())
    private let config: BackendConfig
    private let launchArgs: [String]

    var isInProcess: Bool { false }
    var isRunning: Bool { state.withLock { $0.isRunning } }
    var isGenerating: Bool { false }

    init(config: BackendConfig, launchArgs: [String]) {
        self.config = config
        self.launchArgs = launchArgs
    }

    // MARK: Process Creation

    private func createProcess(with info: ModelInfo, port: Int) -> Process {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: config.executable)
        task.arguments = launchArgs

        var environment = ProcessRunner.env()
        if config.kind == .gguf {
            let binDirectory = (config.executable as NSString).deletingLastPathComponent
            environment["PATH"] = "\(binDirectory):/opt/homebrew/bin:/usr/local/bin:\(environment["PATH"] ?? "")"
        }

        task.environment = environment
        task.qualityOfService = .userInitiated

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            RuntimeTraceLogger.shared.rawProcessOutput(data)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            RuntimeTraceLogger.shared.rawProcessOutput(data)
        }

        task.terminationHandler = { [weak self] process in
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil

            let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            if !remainingStdout.isEmpty {
                RuntimeTraceLogger.shared.rawProcessOutput(remainingStdout)
            }
            if !remainingStderr.isEmpty {
                RuntimeTraceLogger.shared.rawProcessOutput(remainingStderr)
            }

            guard let self else { return }
            let stopping = self.state.withLock { $0.isStopping }
            if stopping { return }

            let exitCode = process.terminationStatus
            if exitCode != 0 {
                Service.log("❌ \(self.config.name) 异常退出 (Exit Code: \(exitCode))", level: .error)
            }

            self.state.withLock {
                $0.isRunning = false
                $0.process = nil
            }

            RuntimeTraceLogger.shared.flush()
        }

        return task
    }

    // MARK: Start

    func start(_ info: ModelInfo, port: Int) async throws {
        let endpoint = InferenceNodeConfiguration.shared.snapshot()

        state.withLock {
            $0.port = port
            $0.isStopping = false
            $0.healthURLString = endpoint.internalBaseURLString + config.healthEndpoint
        }

        Service.log("🌐 \(config.name) Endpoint: bind=\(endpoint.bindHost):\(port), advertised=\(endpoint.advertisedHost):\(port), LAN=\(endpoint.isLANEnabled)")

        let pids = await processIDsOnPort(port)

        if !pids.isEmpty {
            var foreignProcessFound = false

            for pid in pids {
                let command = await processCommandLine(pid)
                if isProcessMatch(command, executable: config.executable) {
                    kill(pid, SIGKILL)
                } else {
                    foreignProcessFound = true
                }
            }

            if foreignProcessFound {
                throw ServiceError.portInUse(port)
            }

            try? await Task.sleep(nanoseconds: 150_000_000)

            if !(await processIDsOnPort(port)).isEmpty {
                throw ServiceError.portInUse(port)
            }
        }

        let task = createProcess(with: info, port: port)
        Service.log("🚀 启动外部推理后端 \(config.name) | 端口: \(port)")

        do {
            try task.run()
        } catch {
            state.withLock {
                $0.process = nil
                $0.isRunning = false
            }
            throw ServiceError.backendNotAvailable("无法启动 \(config.name): \(error.localizedDescription)")
        }

        state.withLock {
            $0.process = task
            $0.isRunning = true
        }

        do {
            try await waitReady(port, timeout: config.startupTimeout)
        } catch {
            state.withLock {
                $0.isStopping = true
                $0.isRunning = false
            }

            task.terminationHandler = nil

            if let stdout = task.standardOutput as? Pipe {
                stdout.fileHandleForReading.readabilityHandler = nil
            }
            if let stderr = task.standardError as? Pipe {
                stderr.fileHandleForReading.readabilityHandler = nil
            }

            if task.isRunning {
                kill(task.processIdentifier, SIGKILL)
            }

            if task.isRunning {
                task.waitUntilExit()
            }

            state.withLock {
                $0.process = nil
                $0.isRunning = false
                $0.isStopping = false
            }

            RuntimeTraceLogger.shared.flush()
            throw error
        }

        state.withLock {
            $0.isStopping = false
        }
    }

    // MARK: Stop

    func stop() async {
        let (process, port) = state.withLock { currentState -> (Process?, Int) in
            currentState.isStopping = true
            let process = currentState.process
            let port = currentState.port
            currentState.process = nil
            currentState.isRunning = false
            return (process, port)
        }

        guard let process else {
            _ = await cleanupOwnedProcessesOnPort(port, executable: config.executable)
            state.withLock { $0.isStopping = false }
            RuntimeTraceLogger.shared.flush()
            return
        }

        let pid = process.processIdentifier
        process.terminationHandler = nil

        if let stdout = process.standardOutput as? Pipe {
            stdout.fileHandleForReading.readabilityHandler = nil
        }
        if let stderr = process.standardError as? Pipe {
            stderr.fileHandleForReading.readabilityHandler = nil
        }

        if process.isRunning {
            kill(pid, SIGKILL)
        }

        await killProcessTree(pid: pid)

        if process.isRunning {
            process.waitUntilExit()
        }

        _ = await cleanupOwnedProcessesOnPort(port, executable: config.executable)

        state.withLock {
            $0.process = nil
            $0.isRunning = false
            $0.isStopping = false
        }

        RuntimeTraceLogger.shared.flush()
    }

    // MARK: Process Tree

    private func killProcessTree(pid: Int32) async {
        _ = await runShell("pkill -9 -P \(pid) 2>/dev/null")
    }

    // MARK: Ready Check

    private func waitReady(_ port: Int, timeout: TimeInterval) async throws {
        let start = Date()
        try await Task.sleep(nanoseconds: 250_000_000)

        while Date().timeIntervalSince(start) < timeout {
            try Task.checkCancellation()

            let alive = state.withLock { $0.isRunning }
            guard alive else {
                throw ServiceError.startupTimeout
            }

            if await checkHealth() {
                let elapsed = Date().timeIntervalSince(start)
                Service.log("✅ \(config.name) 后端就绪 (\(String(format: "%.1f", elapsed))秒)")
                return
            }

            try await Task.sleep(nanoseconds: 400_000_000)
        }

        throw ServiceError.startupTimeout
    }

    // MARK: Health

    func checkHealth() async -> Bool {
        let healthURLString = state.withLock { $0.healthURLString }

        guard !healthURLString.isEmpty, let url = URL(string: healthURLString) else {
            return false
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

// MARK: - Service

@MainActor
public final class Service: ObservableObject {
    public enum LogLevel: Int {
        case debug
        case info
        case warning
        case error
    }

    @Published public var status = "已停止"
    @Published public var isRunning = false
    @Published public var modelPath = ""
    @Published public var memoryPressure = "normal"
    @Published public var config = ModelConfig()
    @Published public private(set) var inferenceNode = InferenceNodeConfiguration.shared

    private let runtimeState = Mutex<Runtime?>(nil)
    private var healthTask: Task<Void, Never>?
    private var backendKind: ModelKind = .gguf
    private var isStarting = false
    private var isRestarting = false

    // MARK: Init

    public init() {
        let savedPath = AppConfig.get(.modelPath) ?? ""
        self.modelPath = savedPath

        if !savedPath.isEmpty {
            self.config = resolveConfig(for: savedPath)
        }

        let node = InferenceNodeConfiguration.fromEnvironment(defaultPort: AppConfig.apiPort)

        InferenceNodeConfiguration.configure(
            bindHost: node.bindHost,
            advertisedHost: node.advertisedHost,
            port: node.port,
            bonjourEnabled: node.bonjourEnabled
        )

        inferenceNode = InferenceNodeConfiguration.shared
    }

    // MARK: Logging

    nonisolated private static var consoleLoggingEnabled: Bool {
        let value = ProcessInfo.processInfo.environment["SIMIGO_LOG_CONSOLE"]?.lowercased()
        return value == "1" || value == "true" || value == "on"
    }

    nonisolated public static func log(_ message: String, level: LogLevel = .info) {
        let icon: String

        switch level {
        case .debug: icon = "🔍"
        case .info: icon = "ℹ️"
        case .warning: icon = "⚠️"
        case .error: icon = "❌"
        }

        let line = "\(icon) \(message)"
        RuntimeTraceLogger.shared.trace(line)

        if consoleLoggingEnabled || level.rawValue >= LogLevel.warning.rawValue {
            print(line)
        }
    }

    // MARK: Public Config

    public var currentConfig: ModelConfig {
        config
    }

    public var pressureColor: Color {
        switch memoryPressure {
        case "critical": return .red
        case "warn": return .orange
        default: return .green
        }
    }

    // MARK: Configuration Resolution

    private nonisolated func resolveConfig(for path: String) -> ModelConfig {
        if let saved = AppConfig.savedConfig(for: path) {
            Self.log("💾 使用模型已保存配置: \(modelName(from: path))")
            return saved
        }

        if let recommended = AppConfig.recommendedConfig(for: path) {
            Self.log("⭐ 使用 SimiGo 推荐配置: \(modelName(from: path))")
            return recommended
        }

        let modelDefault = ModelConfig.fromModel(path)
        Self.log("📄 使用模型 generation_config.json / ModelConfig 默认配置: \(modelName(from: path))")
        return modelDefault
    }

    // MARK: Config Logging

    private func logResolvedConfig(_ config: ModelConfig, path: String) {
        let environment = ProcessInfo.processInfo.environment

        Self.log("""
        ⚙️ 最终模型配置:
          model=\(modelName(from: path))
          ctx=\(config.ctxSize)
          gpuLayers=\(config.gpuLayers)
          temp=\(config.temperature)
          topP=\(config.topP)
          topK=\(config.topK)
          minP=\(config.minP)
          repeatPenalty=\(config.repeatPenalty)
          presencePenalty=\(config.presencePenalty)
          flashAttention=\(config.flashAttention)
          jinja=\(config.jinja)
          codexMode=\(config.codexMode)
          useMTP=\(config.useMTP)
          specDraftNMax=\(config.specDraftNMax)
          disableThinking=\(config.disableThinking)
        🔧 llama.cpp Runtime Overrides:
          parallel=\(environment["SIMIGO_LLAMA_PARALLEL"] ?? "1")
          ngl=\(environment["SIMIGO_LLAMA_NGL"] ?? "\(config.gpuLayers)")
          flashAttn=\(environment["SIMIGO_LLAMA_FLASH_ATTN"] ?? "on")
          specNMax=\(environment["SIMIGO_LLAMA_SPEC_NMAX"] ?? "\(max(1, config.specDraftNMax))")
        """)
    }

    // MARK: Node Configuration

    public var inferenceBaseURL: String {
        inferenceNode.baseURLString
    }

    public var inferenceAPIBaseURL: String {
        inferenceNode.apiBaseURLString
    }

    public var isLANEnabled: Bool {
        inferenceNode.isLANEnabled
    }

    public func configureInferenceNode(bindHost: String, advertisedHost: String? = nil, port: Int = AppConfig.apiPort, bonjourEnabled: Bool = true) {
        guard !isRunning else {
            Self.log("⚠️ 服务运行中不能修改推理节点地址，请先停止服务。", level: .warning)
            return
        }

        InferenceNodeConfiguration.configure(
            bindHost: bindHost,
            advertisedHost: advertisedHost,
            port: port,
            bonjourEnabled: bonjourEnabled
        )

        inferenceNode = InferenceNodeConfiguration.shared

        Self.log("🌐 推理节点配置: bind=\(inferenceNode.bindHost):\(inferenceNode.port), advertised=\(inferenceNode.advertisedHost):\(inferenceNode.port), LAN=\(inferenceNode.isLANEnabled)")
    }

    public func configureLocalNode(port: Int = AppConfig.apiPort) {
        configureInferenceNode(
            bindHost: InferenceNodeDefaults.defaultBindHost,
            advertisedHost: InferenceNodeDefaults.defaultBindHost,
            port: port,
            bonjourEnabled: false
        )
    }

    public func configureLANNode(advertisedHost: String = "SimiGo.local", port: Int = AppConfig.apiPort, bonjourEnabled: Bool = true) {
        configureInferenceNode(
            bindHost: InferenceNodeDefaults.lanBindHost,
            advertisedHost: advertisedHost,
            port: port,
            bonjourEnabled: bonjourEnabled
        )
    }

    // MARK: Start

    public func start(path: String) async {
        guard !isStarting, !isRestarting else {
            Self.log("⚠️ 服务正在启动或重启中，忽略重复启动请求", level: .warning)
            return
        }

        isStarting = true
        defer { isStarting = false }

        await internalStart(path: path)
    }

    private func internalStart(path: String) async {
        if isRunning || runtimeState.withLock({ $0 != nil }) {
            Self.log("🔄 检测到旧模型在运行，自动卸载旧模型...", level: .warning)
            await stop()
        }

        guard !path.isEmpty else {
            status = "❌ 路径为空"
            return
        }

        guard FileManager.default.fileExists(atPath: path) else {
            status = "❌ 不存在"
            return
        }

        modelPath = path

        let resolvedConfig = resolveConfig(for: path)
        applyConfig(resolvedConfig)
        logResolvedConfig(resolvedConfig, path: path)

        let info = ModelDetector.detect(path: path)
        backendKind = info.kind

        let node = inferenceNode

        Self.log("🌐 SimiGo Node: bind=\(node.bindHost):\(node.port), advertised=\(node.advertisedHost):\(node.port), LAN=\(node.isLANEnabled)")
        Self.log("📊 运行时后端: \(info.backendName)")

        let runtime: Runtime

        switch info.kind {
        case .mlx:
            Self.log("🚀 启动 NativeMLX 原生 Metal 运行时")
            runtime = NativeMLX(info: info, config: currentConfig)

        case .gguf:
            let backendConfig = BackendConfig.llama

            guard FileManager.default.fileExists(atPath: backendConfig.executable) else {
                let errorMessage = "❌ 未找到 llama-server 可执行文件"
                Self.log(errorMessage, level: .error)
                status = errorMessage
                return
            }

            let port = node.port
            let launchArgs = backendConfig.args(info, resolvedConfig, port)

            Self.log("🧩 llama-server 参数: " + launchArgs.joined(separator: " "))
            runtime = ProcessRuntime(config: backendConfig, launchArgs: launchArgs)
        }

        runtimeState.withLock {
            $0 = runtime
        }

        do {
            try await runtime.start(info, port: node.port)

            let statusLabel = info.backendName
            isRunning = true
            status = "● 运行中 (\(statusLabel))"

            Self.log("✅ SimiGo 节点已就绪: \(node.apiBaseURLString)")

            if info.kind == .gguf {
                let environment = ProcessInfo.processInfo.environment
                let configuredSlots = Int(environment["SIMIGO_LLAMA_PARALLEL"] ?? "1") ?? 1
                let slots = max(1, min(2, configuredSlots))
                let ngl = environment["SIMIGO_LLAMA_NGL"] ?? "\(resolvedConfig.gpuLayers)"
                let flashAttn = environment["SIMIGO_LLAMA_FLASH_ATTN"] ?? "on"
                let specNMax = environment["SIMIGO_LLAMA_SPEC_NMAX"] ?? "\(max(1, resolvedConfig.specDraftNMax))"
                Self.log("🧩 llama.cpp 性能配置: parallel=\(slots) | ngl=\(ngl) | specNMax=\(specNMax) | flash-attn=\(flashAttn)")
            }

            startHealthCheck()
        } catch {
            Self.log("❌ 启动失败: \(error.localizedDescription)", level: .error)
            status = "❌ \(error.localizedDescription)"
            isRunning = false
            await runtime.stop()

            runtimeState.withLock {
                $0 = nil
            }
        }
    }

    private func applyConfig(_ config: ModelConfig) {
        self.config = config
    }

    // MARK: Model Config Persistence

    public func saveCurrentConfigAsModelDefault() {
        guard !modelPath.isEmpty else {
            Self.log("⚠️ 当前没有模型，无法保存模型配置", level: .warning)
            return
        }

        AppConfig.save(currentConfig, for: modelPath)
        Self.log("💾 已保存模型配置: \(modelName(from: modelPath))")
    }

    public func clearModelConfig() {
        guard !modelPath.isEmpty else { return }

        AppConfig.remove(for: modelPath)

        let restored = resolveConfig(for: modelPath)
        applyConfig(restored)

        Self.log("🧹 已清除用户模型配置，恢复默认配置: \(modelName(from: modelPath))")
    }

    // MARK: Stop

    public func stop() async {
        stopHealthCheck()

        let runtime = runtimeState.withLock { state -> Runtime? in
            let runtime = state
            state = nil
            return runtime
        }

        if let runtime {
            await runtime.stop()
        } else if backendKind == .gguf {
            let node = inferenceNode
            _ = await cleanupOwnedProcessesOnPort(node.port, executable: BackendConfig.llama.executable)
        }

        malloc_zone_pressure_relief(nil, 0)
        RuntimeTraceLogger.shared.flush()

        isRunning = false
        memoryPressure = "normal"
        status = "已停止"

        Self.log("✅ 大模型已完全卸载，显存/内存已清空", level: .info)
    }

    // MARK: Restart

    public func restart(path: String) async {
        guard !path.isEmpty else { return }
        guard isRunning, !isRestarting, !isStarting else { return }

        isRestarting = true
        defer { isRestarting = false }

        await stop()
        await internalStart(path: path)
    }

    public func forceRestart() async {
        guard !modelPath.isEmpty else {
            Self.log("⚠️ 模型路径为空，跳过重启", level: .warning)
            return
        }

        guard !isStarting, !isRestarting else { return }

        if isRunning {
            await restart(path: modelPath)
        } else {
            await start(path: modelPath)
        }
    }

    // MARK: Slot State

    private func areSlotsIdle() async -> Bool? {
        let endpoint = inferenceNode
        let urlString = endpoint.internalBaseURLString + "/slots"

        guard let url = URL(string: urlString) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return nil
            }

            for slot in jsonArray {
                if let state = slot["state"] as? Int, state != 0 {
                    return false
                }
            }

            return true
        } catch {
            return nil
        }
    }

    private func waitForIdle(timeout: TimeInterval = 10) async -> Bool {
        let start = Date()

        while Date().timeIntervalSince(start) < timeout {
            if Task.isCancelled {
                return false
            }

            if let idle = await areSlotsIdle(), idle {
                return true
            }

            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return false
            }
        }

        return false
    }

    // MARK: Health Check

    private func startHealthCheck() {
        healthTask?.cancel()

        healthTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)

            while !Task.isCancelled {
                guard let self else { break }
                guard self.isRunning else { break }

                let currentRuntime = self.runtimeState.withLock { $0 }

                if let runtime = currentRuntime {
                    if runtime.isGenerating {
                        try? await Task.sleep(nanoseconds: 30_000_000_000)
                        continue
                    }

                    // NativeMLX: 空闲超时挂起模型（Phase 1 实验）。
                    // 仅释放模型驻留内存，HTTPServer 保持运行——不触发 restart。
                    // GGUF 的 Swap/restart 机制与 NativeMLX 空闲挂起完全独立，互不干扰。
                    if self.backendKind == .mlx,
                       let nativeMLX = runtime as? NativeMLX {
                        // 健康循环只需“尝试挂起”，返回值用于静默处理。
                        let _ = await nativeMLX.suspendIfIdle(
                            idleTimeout: Self.idleSuspendTimeout
                        )
                    }

                    if !runtime.isInProcess && self.backendKind == .gguf {
                        if let slotsIdle = await self.areSlotsIdle(), !slotsIdle {
                            Self.log("⏸ llama.cpp 当前存在活动 slot，跳过健康/Swap检查。", level: .debug)
                            try? await Task.sleep(nanoseconds: 30_000_000_000)
                            continue
                        }

                        let fetchedSwap = getSwapUsedMegabytes()

                        if let swapMB = fetchedSwap, swapMB > 2048 {
                            Self.log("⚠ [外部子进程] Swap 过高 (\(swapMB) MB)，触发重启...", level: .warning)

                            Task { @MainActor [weak self] in
                                guard let self else { return }
                                await self.forceRestart()
                            }

                            return
                        }
                    }
                }

                let healthy = await currentRuntime?.checkHealth() ?? false

                if !healthy {
                    if self.backendKind == .gguf {
                        if let slotsIdle = await self.areSlotsIdle(), !slotsIdle {
                            Self.log("⏸ Health 检查失败但 llama.cpp 仍有活动 slot，暂不重启。", level: .warning)
                            try? await Task.sleep(nanoseconds: 30_000_000_000)
                            continue
                        }
                    }

                    Self.log("⚠ 模型服务无响应，触发解耦重启...", level: .warning)

                    Task { @MainActor [weak self] in
                        await self?.forceRestart()
                    }

                    return
                }

                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    // MARK: - Health Check Tuning

    /// Phase 1 实验用的空闲挂起超时（秒）。验证成功后改为 300。
    /// 健康检查循环周期 30s，使挂起延迟收敛到 idleTimeout～idleTimeout+30s。
    private static let idleSuspendTimeout: TimeInterval = 300

    private func stopHealthCheck() {
        healthTask?.cancel()
        healthTask = nil
    }
}
