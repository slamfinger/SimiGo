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
            // 上限 4 由 owner 2026-10-30 放开（此前为 2）；默认仍为 1。
            let parallelSlots = max(1, min(4, configuredParallel))
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

final class ProcessRuntime: Runtime, @unchecked Sendable {
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
        state.withLock {
            $0.port = port
            $0.isStopping = false
            $0.healthURLString = "http://127.0.0.1:\(port)" + config.healthEndpoint
        }

        Service.log("🌐 \(config.name) Endpoint: bind=127.0.0.1:\(port)")

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

/// Which listener this process is hosting. The ES/IS host serves `/mcp` and
/// the IS read routes without a model; it is not a model backend.
public enum HostMode: Equatable, Sendable {
    case idle
    case model
    case informationSpace
}

@MainActor
public final class Service: ObservableObject {
    public static let shared = Service()

    public enum LogLevel: Int {
        case debug
        case info
        case warning
        case error
    }

    @Published public var status = "已停止"
    @Published public var isRunning = false
    @Published public var modelPath = ""
    @Published public var mlxModelPath = ""
    @Published public var llamaModelPath = ""
    @Published public var backendSelection: BackendSelection {
        didSet { AppConfig.set(backendSelection.rawValue, for: .backendSelection) }
    }
    @Published public private(set) var hostMode: HostMode = .idle
    @Published public var memoryPressure = "normal"
    @Published public var config = ModelConfig()
    @Published public private(set) var inferenceNode = InferenceNodeConfiguration.shared
    /// Execution State 窗口的引擎只读投影（nil = 无进程内执行状态）。
    @Published public private(set) var executionState: EngineExecutionStateSnapshot?

    private let runtimeState = Mutex<Runtime?>(nil)
    private var healthTask: Task<Void, Never>?
    private var backendKind: ModelKind?
    private var isStarting = false
    private var isRestarting = false

    // MARK: Init

    public init() {
        let savedPath = AppConfig.get(.modelPath) ?? ""
        self.modelPath = savedPath
        self.backendSelection = BackendSelection(rawValue: AppConfig.get(.backendSelection) ?? "") ?? .mlx
        self.mlxModelPath = AppConfig.get(.mlxModelPath) ?? ""
        self.llamaModelPath = AppConfig.get(.llamaModelPath) ?? ""

        if savedPath.isEmpty {
            modelPath = backendSelection == .llamaCpp ? llamaModelPath : mlxModelPath
        }

        if !savedPath.isEmpty {
            self.config = resolveConfig(for: savedPath)
        }

        // Unified path resolution: when the persisted portable reference resolves to
        // a live model under the external cache, prefer it over any stale absolute
        // path (this survives a cache relocation) and refresh the runtime locators.
        if let url = AppConfig.resolvedSelectedModelURL {
            let resolved = url.path
            if resolved != modelPath, FileManager.default.fileExists(atPath: resolved) {
                modelPath = resolved
                AppConfig.set(resolved, for: .modelPath)
                switch ModelDetector.detect(path: resolved).kind {
                case .mlx: mlxModelPath = resolved; AppConfig.set(resolved, for: .mlxModelPath)
                case .gguf: llamaModelPath = resolved; AppConfig.set(resolved, for: .llamaModelPath)
                }
                self.config = resolveConfig(for: resolved)
            }
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

    public var hasStartTarget: Bool {
        switch backendSelection {
        case .mlx: return canStartLocal(.mlx)
        case .llamaCpp: return canStartLocal(.gguf)
        }
    }

    public func canStartLocal(_ expectedKind: ModelKind) -> Bool {
        let path = expectedKind == .gguf ? llamaModelPath : mlxModelPath
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return false }
        return ModelDetector.detect(path: path).kind == expectedKind
    }

    public var isInformationSpaceHostRunning: Bool {
        isRunning && hostMode == .informationSpace
    }

    public var backendDisplayName: String {
        switch backendSelection {
        case .mlx: return ModelKind.mlx.displayName
        case .llamaCpp: return ModelKind.gguf.displayName
        }
    }

    public func selectModel(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }

        switch ModelDetector.detect(path: path).kind {
        case .mlx:
            mlxModelPath = path
            AppConfig.set(path, for: .mlxModelPath)
        case .gguf:
            llamaModelPath = path
            AppConfig.set(path, for: .llamaModelPath)
        }

        modelPath = path
        AppConfig.set(path, for: .modelPath)
        // Portable identity: persist (root_id + relative) when the model lives in an
        // external cache root; the absolute path remains only as a runtime locator.
        AppConfig.persistReference(forAbsolutePath: path)
    }

    public func start(_ selection: BackendSelection) async {
        backendSelection = selection
        await startSelected()
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
        // debug 档归入 verbose（2026-11-05）：逐帧轮询类提示默认不落档，
        // `SIMIGO_TRACE_VERBOSE=1` 时与旧行为一致。
        if level == .debug {
            RuntimeTraceLogger.shared.traceVerbose(line)
        } else {
            RuntimeTraceLogger.shared.trace(line)
        }

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
            return saved
        }

        if let recommended = AppConfig.recommendedConfig(for: path) {
            return recommended
        }

        return ModelConfig.fromModel(path)
    }

    // MARK: Config Logging

    /// 启动配置收口为一行（2026-11-05 日志瘦身）：此前 source= 与 ctx= 是
    /// 两行、且 source 每次 resolve 都打一遍（含不加载模型的恢复路径）；
    /// 现在 1 行带齐 model/source/ctx/采样开关，逐次启动仍是独立证据。
    private func logResolvedConfig(_ config: ModelConfig, path: String) {
        let source = AppConfig.savedConfig(for: path) != nil
            ? "saved"
            : (AppConfig.recommendedConfig(for: path) != nil ? "recommended" : "default")
        Self.log(
            "[CFG] source=\(source) model=\(modelName(from: path))"
            + " ctx=\(config.ctxSize) gpu=\(config.gpuLayers)" +
            " temp=\(config.temperature) topP=\(config.topP) topK=\(config.topK) minP=\(config.minP)" +
            " rep=\(config.repeatPenalty) pres=\(config.presencePenalty) flash=\(config.flashAttention)" +
            " jinja=\(config.jinja) codex=\(config.codexMode) mtp=\(config.useMTP)" +
            " draftN=\(config.specDraftNMax) thinkOff=\(config.disableThinking)"
        )
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

    public func startSelected() async {
        switch backendSelection {
        case .mlx:
            await startLocal(expectedKind: .mlx)
        case .llamaCpp:
            await startLocal(expectedKind: .gguf)
        }
    }

    public func startMLX() async { await start(.mlx) }

    public func startLLaMACpp() async { await start(.llamaCpp) }

    /// 启动不依赖模型的 ES/IS 服务宿主：HTTP listener、`/mcp` 与 IS 读路由
    /// 都由它自己持有，不需要先加载 MLX / llama.cpp。
    public func startInformationSpaceService() async {
        guard !isStarting, !isRestarting else {
            Self.log("⚠️ 服务正在启动或重启中，忽略重复启动请求", level: .warning)
            return
        }

        isStarting = true
        defer { isStarting = false }
        await internalStartInformationSpaceService()
    }

    private func startLocal(expectedKind: ModelKind) async {
        let path = expectedKind == .gguf ? llamaModelPath : mlxModelPath
        backendSelection = expectedKind == .gguf ? .llamaCpp : .mlx

        guard !path.isEmpty else {
            status = "❌ 请先选择 \(expectedKind.displayName) 模型"
            return
        }

        modelPath = path
        await start(path: path)
    }

    public func restartSelected() async {
        guard isRunning, !isRestarting, !isStarting else { return }

        isRestarting = true
        defer { isRestarting = false }

        let restartingInformationSpace = hostMode == .informationSpace
        await stop()
        if restartingInformationSpace {
            await internalStartInformationSpaceService()
        } else {
            await startSelected()
        }
    }

    private func internalStartInformationSpaceService() async {
        if isRunning || runtimeState.withLock({ $0 != nil }) {
            Self.log("🔄 检测到旧服务在运行，自动停止旧服务...", level: .warning)
            await stop()
        }

        let node = inferenceNode
        let runtime = InformationSpaceRuntime()
        runtimeState.withLock { $0 = runtime }
        backendKind = nil

        do {
            try await runtime.start(port: node.port)
            isRunning = true
            hostMode = .informationSpace
            status = "● 运行中 (信息空间服务)"
            Self.log("[READY] \(node.apiBaseURLString) host=informationSpace")
            startHealthCheck()
        } catch {
            Self.log("❌ 信息空间服务启动失败: \(error.localizedDescription)", level: .error)
            status = "❌ \(error.localizedDescription)"
            isRunning = false
            hostMode = .idle
            await runtime.stop()
            runtimeState.withLock { $0 = nil }
        }
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

        let expectedKind: ModelKind
        switch backendSelection {
        case .mlx: expectedKind = .mlx
        case .llamaCpp: expectedKind = .gguf
        }

        if info.kind != expectedKind {
            let message = "❌ 模型类型不匹配：选择的是 \(backendSelection.displayName)，但模型是 \(info.backendName)"
            Self.log(message, level: .error)
            status = message
            return
        }

        let node = inferenceNode

        Self.log("[NODE] backend=\(info.backendName) bind=\(node.bindHost):\(node.port) advertised=\(node.advertisedHost):\(node.port) lan=\(node.isLANEnabled)")

        let runtime: Runtime

        switch info.kind {
        case .mlx:
            runtime = NativeMLX(info: info, config: currentConfig)

        case .gguf:
            let backendConfig = BackendConfig.llama

            guard FileManager.default.fileExists(atPath: backendConfig.executable) else {
                let errorMessage = "❌ 未找到 llama-server 可执行文件"
                Self.log(errorMessage, level: .error)
                status = errorMessage
                return
            }

            runtime = ManagedGGUFRuntime(
                config: resolvedConfig, backendConfig: backendConfig)
        }

        runtimeState.withLock {
            $0 = runtime
        }

        do {
            try await runtime.start(info, port: node.port)

            let statusLabel = info.backendName
            isRunning = true
            hostMode = .model
            status = "● 运行中 (\(statusLabel))"

            // 结构化状态快照的后端身份（2026-11-06）：外部工具从
            // state/runtime.json 读引擎内部端口，不从 trace 文本反推。
            RuntimeStateReporter.shared.setContext(
                backend: info.backendName,
                model: modelName(from: info.path),
                enginePort: (runtime as? ManagedGGUFRuntime)?.enginePort)
            Self.log("[READY] \(node.apiBaseURLString)")

            if info.kind == .gguf {
                let environment = ProcessInfo.processInfo.environment
                let configuredSlots = Int(environment["SIMIGO_LLAMA_PARALLEL"] ?? "1") ?? 1
                let slots = max(1, min(4, configuredSlots))
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

    /// 停止当前监听者（模型或信息空间宿主）。不自动回落：接管、重启、
    /// 网络模式切换和退出都走这里；只有用户明确停止模型时才回落到宿主。
    public func stop() async {
        stopHealthCheck()

        // 归零前先记住是否真有运行实体：停两次（stopModelService 后再调
        // stop）此前会打两遍「服务已停止」，第二遍是空操作噪音。
        let wasRunning = isRunning || runtimeState.withLock { $0 != nil }
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
        hostMode = .idle
        backendKind = nil
        memoryPressure = "normal"
        status = "已停止"
        RuntimeStateReporter.shared.clearContext()

        if wasRunning {
            Self.log("✅ 服务已停止，显存/内存已清空", level: .info)
        }
    }

    /// 用户停止模型：卸载模型后把同一端口交还无模型的信息空间宿主，
    /// MCP 与 IS 读写接口不随模型卸载而消失。
    public func stopModelService() async {
        guard hostMode == .model else { return }
        await stop()
        await startInformationSpaceService()
    }

    // MARK: Execution State 投影

    /// 刷新引擎执行状态只读投影（Execution State 窗口消费）。native
    /// 运行时才有会话图；外部进程 / 信息空间宿主置 nil——不伪造状态。
    /// 同步锁内快照，无 IO。
    public func refreshExecutionState() {
        let runtime = runtimeState.withLock { $0 }
        guard let native = runtime as? NativeMLX else {
            if executionState != nil { executionState = nil }
            return
        }
        executionState = native.executionStateSnapshot()
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
        guard hasStartTarget || isInformationSpaceHostRunning else {
            Self.log("⚠️ 没有可启动的 backend，跳过重启", level: .warning)
            return
        }

        guard !isStarting, !isRestarting else { return }

        if isRunning {
            await restartSelected()
        } else {
            await startSelected()
        }
    }

    // MARK: Slot State

    /// Slot activity is read from the current runtime's own engine port, not
    /// from the product listener. Non-GGUF runtimes answer `unknown`.
    private func slotActivity(for runtime: Runtime?) async -> SlotActivity {
        await SlotActivityResolver.activity(for: runtime)
    }

    private func waitForIdle(timeout: TimeInterval = 10) async -> Bool {
        let start = Date()

        while Date().timeIntervalSince(start) < timeout {
            if Task.isCancelled {
                return false
            }

            let runtime = runtimeState.withLock { $0 }
            let activity = await slotActivity(for: runtime)
            // Cancellation can race with a successful URLSession response too;
            // an idle sample from a cancelled wait must not be reported as ready.
            if Task.isCancelled { return false }
            if activity == .idle {
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

    #if SIMIGO_HEALTH_CHECK_FAILURE_INJECTION
    /// Validation-build-only, one-shot health failure. The environment is read
    /// inside this compile condition, so a normal Release build has neither the
    /// state nor the symbol.
    ///
    /// This injects a *result*, it does not make the engine's `/health`
    /// endpoint answer 503. The real endpoint is not contacted on the cycle
    /// that consumes this flag.
    private static let injectedHealthFailureState = Mutex(false)

    nonisolated static func consumeInjectedHealthFailureIfRequested() -> Bool {
        guard
            ProcessInfo.processInfo.environment["SIMIGO_HEALTH_CHECK_FAIL_NEXT"]
                == "fail-next-health-check"
        else { return false }
        return injectedHealthFailureState.withLock { consumed in
            guard !consumed else { return false }
            consumed = true
            return true
        }
    }
    #endif

    private func startHealthCheck() {
        healthTask?.cancel()

        healthTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)

            while !Task.isCancelled {
                guard let self else { break }
                guard self.isRunning else { break }

                let currentRuntime = self.runtimeState.withLock { $0 }

                #if SIMIGO_HEALTH_CHECK_FAILURE_INJECTION
                var injectedHealthFailure = false
                #else
                let injectedHealthFailure = false
                #endif

                if let runtime = currentRuntime {
                    if runtime.isGenerating {
                        try? await Task.sleep(nanoseconds: 30_000_000_000)
                        continue
                    }

                    #if SIMIGO_HEALTH_CHECK_FAILURE_INJECTION
                    if self.backendKind == .gguf {
                        injectedHealthFailure =
                            Self.consumeInjectedHealthFailureIfRequested()
                    }
                    if injectedHealthFailure {
                        Self.log(
                            "🧪 [VALIDATION] 一次性注入健康检查失败结果；"
                                + "本轮未请求引擎 /health。",
                            level: .warning)
                    }
                    #endif

                    // NativeMLX: 空闲超时挂起模型（Phase 1 实验）。
                    // 仅释放模型驻留内存，HTTPServer 保持运行——不触发 restart。
                    // 超时为自适应：min(cap=360s, max(floor=240s, 最贵会话重建时长估算+60s 容错))
                    // —— 2026-10-23 由原 max(600s…) 收紧为带上限的收敛窗口，缓解推理结束后内存压力长时间黄色。
                    if self.backendKind == .mlx,
                       let nativeMLX = runtime as? NativeMLX {
                        // 健康循环只需“尝试挂起”，返回值用于静默处理。
                        let _ = await nativeMLX.suspendIfIdle()
                        // stop()/runtime replacement cancels this task; never
                        // let an older health iteration proceed after an await.
                        if Task.isCancelled { break }
                    }

                    // GGUF：slot 忙时先跳过本轮，防止生成中途误判无响应触发重启。
                    // 注入失败时故意走过这一跳，让“失败后仍有 busy slot”的
                    // 保护分支成为被验证的对象。unknown 不当作空闲，也不阻断
                    // 已死引擎的恢复——交给健康检查判定。
                    if !injectedHealthFailure,
                        !runtime.isInProcess,
                        self.backendKind == .gguf {
                        let activity = await self.slotActivity(for: runtime)
                        // The probe maps transport cancellation to .unknown.
                        // Re-check task cancellation before interpreting that
                        // value as a real observation.
                        if Task.isCancelled { break }
                        if activity == .busy {
                            Self.log("⏸ llama.cpp 当前存在活动 slot，跳过健康检查。", level: .debug)
                            try? await Task.sleep(nanoseconds: 30_000_000_000)
                            continue
                        }
                    }
                }

                let healthy =
                    injectedHealthFailure
                    ? false
                    : (await currentRuntime?.checkHealth() ?? false)
                // checkHealth() may finish after stopHealthCheck() has cancelled
                // this task. A cancelled iteration must not schedule a restart.
                if Task.isCancelled { break }

                if !healthy {
                    if self.backendKind == .gguf {
                        let activity = await self.slotActivity(for: currentRuntime)
                        if Task.isCancelled { break }
                        if activity == .busy {
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

    // 空闲挂起超时自适应（NativeMLX.adaptiveIdleTimeout）：
    // min(cap=360s, max(floor=240s, 最贵会话重建时长估算 + 60s))。带 cap 的收敛窗口
    // 是为缓解"推理结束后内存压力长时间黄色"：大会话最长 6 分钟即卸载（原 ≈14.5 分钟）；
    // floor 兜底保证小会话工具/思考间隙不反复缴冷启动税。
    // 健康检查循环周期 30s，实际挂起延迟收敛到 idleTimeout～idleTimeout+30s（≤ 6.5 分钟）。

    private func stopHealthCheck() {
        healthTask?.cancel()
        healthTask = nil
    }
}
