import Foundation
import Combine
import SimiGoRuntimeContract

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
    public static let defaultCommandInput = "hf download "
    @Published public var commandInput = EnvManager.defaultCommandInput
    @Published public var commandLog = ""
    @Published public var isRecording = false
    @Published public var commandStatus = "就绪"

    // MARK: - Paths
    // Single source of truth: SimiGoPaths (MLX-free runtime resolver). No `models`
    // directory is ever created under the managed root — model weights stay external
    // and are referenced from the Hugging Face cache / user-selected roots only.
    public static var simigoDir: String { SimiGoPaths.managedRoot().path }
    public static var binDir: String { SimiGoPaths.bin.path }
    public static var logsDir: String { SimiGoPaths.logs.path }
    public static var nativeMLXTraceLog: String { SimiGoPaths.logs.appendingPathComponent("native_mlx_trace.log").path }

    // MARK: - Engine selection (install page)
    /// Engines selectable at install time: bundled defaults plus any operator
    /// manifest entries. NOT hardcoded to llama.cpp — add an engine via manifest.
    public var availableEngines: [EngineRecipe] {
        SimiGoEngineRegistry.load(manifestURL: SimiGoPaths.manifests.appendingPathComponent(SimiGoEngineRegistry.manifestName))
    }

    /// Currently chosen engine id (persisted to config).
    @Published public var selectedEngineID: String = AppConfig.get(.selectedEngine) ?? "mlx-native" {
        didSet { AppConfig.set(selectedEngineID, for: .selectedEngine) }
    }

    /// Resolve an engine's lifecycle stage. Downloaded / built / adapted stay three
    /// DISTINCT states — a fetched source is not a built binary and neither is an
    /// adapted SimiGo runtime.
    public func engineStage(for id: String) -> EngineStage {
        guard let recipe = availableEngines.first(where: { $0.id == id }) else { return .absent }
        let binaryPresent = Self.findSystemLlamaServer() != nil
        let sourcePinned = FileManager.default.fileExists(atPath: SimiGoPaths.sources.path)
        let driverAdapted = id == "mlx-native" ? true : binaryPresent
        return SimiGoEngineRegistry.resolveStage(recipe: recipe,
                                                 sourcePresentAtPinnedRef: sourcePinned,
                                                 binaryPresent: binaryPresent,
                                                 driverAdapted: driverAdapted,
                                                 healthChecked: binaryPresent)
    }

    /// requirement②: the concrete OpenAI-compatible endpoint SimiGo will adopt
    /// for a SELECTED external server (ollama / LM Studio / …). `nil` means the
    /// selected engine is not an endpoint-adoptable external server (native MLX,
    /// source-build llama.cpp) or is fail-closed for lack of a manifest endpoint
    /// (SGLang). The install UI uses this to wire the existing remote runtime,
    /// so selecting a server actually routes inference instead of only logging.
    public func adoptedEndpoint(for id: String) -> SimiGoEngineRegistry.AdoptedEndpoint? {
        guard let recipe = availableEngines.first(where: { $0.id == id }) else { return nil }
        return SimiGoEngineRegistry.adoptedEndpoint(for: recipe)
    }

    /// requirement②: apply the selected external server's resolved OpenAI-compatible
    /// endpoint to the live runtime by configuring the existing, already-tested
    /// `.cloud` remote backend. Business logic lives here (not in the SwiftUI view)
    /// so it is the single source of truth and is directly testable. Returns `nil`
    /// (fail-closed) when the engine is not an endpoint-adoptable external server,
    /// leaving the Service untouched.
    @MainActor
    public func applyExternalAdoption(of id: String, to service: Service) -> SimiGoEngineRegistry.AdoptedEndpoint? {
        guard let ep = adoptedEndpoint(for: id) else { return nil }
        service.cloudBaseURL = ep.baseURL
        if let m = ep.defaultModel { service.cloudModel = m }
        service.backendSelection = .cloud
        commandStatus = "已采用外部服务端"
        statusMessage = "已采用外部服务端：\(ep.baseURL)"
        appendCommandLog("🔌 采用 \(id) → 云端运行时指向 \(ep.baseURL)")
        return ep
    }

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
            commandInput = Self.defaultCommandInput
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
        // Dispatch by the selected engine's KIND. Native MLX needs no external
        // binary; external servers (ollama / LM Studio / slang) are ADOPTED, not
        // built here. Only source-build recipes fall through to the compile path.
        let engine = selectedEngineID
        if let recipe = availableEngines.first(where: { $0.id == engine }), recipe.kind != .sourceBuild {
            switch recipe.kind {
            case .nativeRuntime:
                commandStatus = "就绪"
                statusMessage = "Native MLX 内置，无需外部依赖"
                appendCommandLog("✅ Native MLX 内置运行时，无需构建外部引擎。")
            default:
                let stage = engineStage(for: engine)
                commandStatus = stage == .absent ? "未检测到外部服务端" : "已采用外部服务端"
                statusMessage = commandStatus
                appendCommandLog("ℹ️ \(recipe.displayName) 为外部服务端（stage=\(stage)）：请确认已安装，SimiGo 只采用不构建。")
            }
            checkStatus()
            return
        }

        commandInput = "llama.cpp build"
        commandStatus = "构建中"
        appendCommandLog("🚀 开始准备 SimiGo 外部依赖：llama.cpp")

        let fm = FileManager.default

        // Installed-binary short circuit: a usable `bin/llama-server` satisfies
        // the dependency WITHOUT rebuilding. Cache pruning removes sources/build
        // after a successful build, so without this check every re-run (or any
        // offline re-run) would force a fresh clone of upstream.
        let installedLlama = "\(Self.binDir)/llama-server"
        if fm.fileExists(atPath: installedLlama), fm.isExecutableFile(atPath: installedLlama) {
            appendCommandLog("✅ 检测到已安装的 llama-server（\(installedLlama)），跳过构建。")
            commandStatus = "构建完成"
            commandInput = Self.defaultCommandInput
            checkStatus()
            return
        }

        do {
            try fm.createDirectory(atPath: Self.simigoDir, withIntermediateDirectories: true)
            try fm.createDirectory(atPath: Self.binDir, withIntermediateDirectories: true)
            // No `.simigo/models`: models are never copied into the managed root.
            try fm.createDirectory(atPath: Self.logsDir, withIntermediateDirectories: true)

            guard let git = Self.findTool("git") else {
                throw NSError(domain: "EnvManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "未找到 git，请先安装 Xcode Command Line Tools。"])
            }

            guard let cmake = Self.findTool("cmake") else {
                throw NSError(domain: "EnvManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "未找到 cmake，请安装 cmake。"])
            }

            // Locked version only: NO floating `git pull`. The pinned ref must come
            // from the engine manifest / operator setting; an unlocked recipe is
            // refused fail-closed instead of silently tracking upstream HEAD.
            guard let llamaRecipe = SimiGoEngineRegistry.recipe(
                    id: "llama.cpp",
                    manifestURL: SimiGoPaths.manifests.appendingPathComponent(SimiGoEngineRegistry.manifestName)),
                  llamaRecipe.isVersionLocked, let pinned = llamaRecipe.pinnedRef else {
                throw NSError(domain: "EnvManager", code: 409, userInfo: [NSLocalizedDescriptionKey:
                    "llama.cpp 未锁定版本：请在引擎清单 '\(SimiGoEngineRegistry.manifestName)' 指定 pinnedRef 后再构建（禁止随上游漂移）。"])
            }
            let source = SimiGoPaths.sources.appendingPathComponent("llama.cpp").path
            let build = SimiGoPaths.build.appendingPathComponent("llama.cpp").path

            // 网络重试：github 连接间歇性失败（HTTP2 framing / 443 超时实测），
            // 检出与更新各给 4 次机会（间隔 5s）。
            func networkStep(_ label: String, _ body: () async throws -> Void) async throws {
                var lastError: Error?
                for attempt in 1 ... 4 {
                    do {
                        try await body()
                        return
                    } catch {
                        lastError = error
                        appendCommandLog("⚠️ \(label) 第 \(attempt) 次失败：\(error.localizedDescription)")
                        if attempt < 4 {
                            try? await Task.sleep(nanoseconds: 5_000_000_000)
                        }
                    }
                }
                throw NSError(domain: "EnvManager", code: 502, userInfo: [
                    NSLocalizedDescriptionKey:
                        "网络无法访问 github.com（已重试 4 次）：\(lastError?.localizedDescription ?? "")。请检查网络后重试。",
                ])
            }

            if !fm.fileExists(atPath: "\(source)/.git") {
                appendCommandLog("📥 锁定检出 llama.cpp @ \(pinned) …")
                try await networkStep("锁定检出") {
                    for args in llamaRecipe.lockedCheckoutCommands(git: git, targetDir: source) {
                        try await runCommand(args[0], args: Array(args.dropFirst()))
                    }
                }
            } else {
                appendCommandLog("🔒 校验 llama.cpp 检出到锁定版本 \(pinned) …")
                try await networkStep("校验更新") {
                    try await runCommand(git, args: ["-C", source, "fetch", "--depth", "1", "origin", pinned])
                    try await runCommand(git, args: ["-C", source, "checkout", "--detach", pinned])
                }
            }

            if fm.fileExists(atPath: "\(build)/CMakeCache.txt") {
                appendCommandLog("⚡ 检测到已有构建缓存，执行增量构建…")
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

            // "构建完成后删除缓存只保留二进制": the installed binary already lives in
            // binDir, so drop exactly the cache set the recipe declares (single
            // source of truth — a recipe that names other cache dirs is honored) and
            // never a path the recipe did not list. bin/ is not in that set, so the
            // retained binary can never be pruned.
            appendCommandLog("🧹 构建完成，清理缓存仅保留二进制…")
            for rel in llamaRecipe.cachePathsToRemoveAfterBuild {
                precondition(!rel.hasPrefix("/") && !rel.contains(".."),
                             "recipe cache path must be relative and contained")
                let url = SimiGoPaths.managedRoot().appendingPathComponent(rel, isDirectory: true)
                if fm.fileExists(atPath: url.path) { try? fm.removeItem(at: url) }
            }
            appendCommandLog("✅ 已清理引擎缓存：\(llamaRecipe.cachePathsToRemoveAfterBuild.joined(separator: ", "))（仅保留二进制）")

            // Hugging Face CLI: NEVER pipe a remote script to a shell (curl | bash).
            // SimiGo only adopts an already-installed `hf`; if absent, HF model
            // downloads stay unavailable until the user installs the official CLI.
            if Self.findTool("hf") != nil {
                appendCommandLog("⚡ 已检测到官方 hf 工具，模型下载可用。")
            } else {
                appendCommandLog("ℹ️ 未检测到 hf CLI：出于安全（禁止 curl | bash）不自动安装。如需从 Hugging Face 下载模型，请自行安装官方 CLI。")
            }


            guard Self.findSystemLlamaServer() != nil else {
                throw NSError(domain: "EnvManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "llama-server 编译完成但未找到可执行文件。"])
            }

            appendCommandLog("🎉 llama-server 就绪。Native MLX 无需安装外部运行时。")
            commandStatus = "构建完成"
            commandInput = Self.defaultCommandInput
            checkStatus()
        } catch {
            appendCommandLog("❌ 构建中断：\(error.localizedDescription)")
            commandStatus = "构建失败"
            statusMessage = "构建失败"
        }
    }


    // MARK: - Generation environment bootstrap (env-bootstrap entry)

    /// Provision the `hf` CLI into the managed bin.
    ///
    /// Discovery order: an already usable `hf` (PATH or managed bin) is adopted
    /// as-is; otherwise Homebrew (a package manager, never `curl | bash`) is
    /// used to install the official `huggingface-cli`, and the binary is
    /// linked into `~/.simigo/bin`. Without Homebrew the step reports
    /// `manual_required` with instructions instead of failing the bootstrap.
    public func bootstrapHFTool() async -> [String: Any] {
        let fm = FileManager.default
        let binTarget = Self.binDir + "/hf"
        if let existing = Self.findTool("hf") {
            return ["status": "already_present", "path": existing]
        }
        if fm.fileExists(atPath: binTarget) && fm.isExecutableFile(atPath: binTarget) {
            return ["status": "already_present", "path": binTarget]
        }
        guard let brew = Self.findTool("brew") else {
            return [
                "status": "manual_required",
                "detail": "未找到 hf 且未安装 Homebrew：请安装官方 huggingface-cli 后重跑（禁止 curl | bash）",
            ]
        }
        do {
            appendCommandLog("📦 通过 Homebrew 安装官方 huggingface-cli …")
            try await runCommand(brew, args: ["install", "huggingface-cli"])
            // Locate the installed binary via brew's own prefix resolution.
            let prefix = try await Self.captureCommand(brew, args: ["--prefix", "huggingface-cli"])
            let candidate = (prefix as NSString).appendingPathComponent("/bin/hf")
            guard fm.fileExists(atPath: candidate) else {
                return ["status": "install_bin_missing", "detail": "brew 安装完成但未找到 \(candidate)"]
            }
            try? fm.removeItem(atPath: binTarget)
            try fm.createSymbolicLink(atPath: binTarget, withDestinationPath: candidate)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binTarget)
            return ["status": "installed", "path": binTarget, "target": candidate]
        } catch {
            return ["status": "install_failed", "detail": error.localizedDescription]
        }
    }

    /// Ensure a fresh authoritative ES/IS database exists and optionally
    /// register the operator's work root.
    ///
    /// An EXISTING database is never reset — the blank-database semantics apply
    /// to a new environment only. `workRoot`, when given, is registered in the
    /// `roots` table (category `work`, locator `path`) so Execution State and
    /// Information Space can index files under it without ever copying them in.
    public func bootstrapFreshDatabase(workRoot: String?) -> [String: Any] {
        let url = SimiGoPaths.databaseURL
        let existedBefore = FileManager.default.fileExists(atPath: url.path)
        do {
            let db = try SimiGoESISDatabase(url: url, createIfNeeded: true)
            try db.runMigrations()
            var report: [String: Any] = [
                "status": existedBefore ? "existing" : "created",
                "path": url.path,
                "schema_version": (try? db.schemaVersion()) ?? -1,
            ]
            if let workRoot, !workRoot.isEmpty {
                let standardized = (workRoot as NSString).standardizingPath
                let rootID = "work-" + Self.stableRootID(forPath: standardized)
                try db.upsertRoot(
                    rootID: rootID, category: "work",
                    displayName: standardized, locatorType: "path", status: "registered")
                report["work_root"] = [
                    "root_id": rootID,
                    "path": standardized,
                    "registered": true,
                ]
            }
            return report
        } catch {
            return ["status": "failed", "path": url.path, "detail": error.localizedDescription]
        }
    }

    /// Ensure a version-locked engine manifest exists before building.
    ///
    /// The build path is fail-closed without a pinned `llama.cpp` ref; an
    /// operator-supplied manifest is never overwritten. When none exists, this
    /// writes the default lock file pinning llama.cpp to the commit already
    /// validated in the user's real environment (2026-10-18, build 11720,
    /// `0878f7c3…`) — self-bootstrap without upstream drift.
    public func ensureDefaultEngineManifest() -> [String: Any] {
        let url = SimiGoPaths.manifests.appendingPathComponent(SimiGoEngineRegistry.manifestName)
        if FileManager.default.fileExists(atPath: url.path) {
            return ["status": "present", "path": url.path]
        }
        let pinned = "0878f7c304cc13915c831ae17694534c94940176"
        var recipes = SimiGoEngineRegistry.bundledDefaults
        if let idx = recipes.firstIndex(where: { $0.id == "llama.cpp" }) {
            recipes[idx] = EngineRecipe(
                id: "llama.cpp", displayName: "llama.cpp", kind: .sourceBuild,
                upstreamURL: "https://github.com/ggml-org/llama.cpp.git",
                pinnedRef: pinned,
                producedBinaryRelPath: "build/bin/llama-server")
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try FileManager.default.createDirectory(
                at: SimiGoPaths.manifests, withIntermediateDirectories: true)
            try encoder.encode(recipes).write(to: url)
            return ["status": "created", "pinned_ref": pinned, "path": url.path]
        } catch {
            return ["status": "failed", "detail": error.localizedDescription]
        }
    }

    /// One-shot provisioning of the full generation environment: managed
    /// directory tree, llama.cpp toolchain (version-locked build, caches
    /// pruned to binaries), the `hf` CLI, and the authoritative ES/IS
    /// database with an optional work-root registration. Returns a JSON-ready
    /// report; a step that cannot run reports its own status instead of
    /// aborting the rest.
    public func bootstrapGenerationEnvironment(workRoot: String?) async -> [String: Any] {
        var report: [String: Any] = [
            "managed_root": SimiGoPaths.managedRoot().path,
            "started_at": ISO8601DateFormatter().string(from: Date()),
        ]
        // 0) Version-locked engine manifest (operator manifest wins; the
        //    default pins llama.cpp to the validated commit).
        report["engine_manifest"] = ensureDefaultEngineManifest()
        // 1) Directory tree + llama.cpp (reuses the shipped, version-locked
        //    recipe path incl. cache pruning).
        let previousEngine = selectedEngineID
        selectedEngineID = "llama.cpp"
        await setupEnvironment()
        selectedEngineID = previousEngine
        report["llama_cpp"] = [
            "status": commandStatus,
            "llama_server": Self.llamaServerExecutable,
        ]
        // 2) hf CLI.
        report["hf"] = await bootstrapHFTool()
        // 3) Fresh ES/IS database + work root.
        report["database"] = bootstrapFreshDatabase(workRoot: workRoot)
        // 4) LOCALB operational status against the SAME managed root the
        //    identities now live in (file keychain). `operational` = the ES/IS
        //    serving path can bind TLS + auth; anything else names the recovery
        //    step (first-run ceremony via the management entry).
        switch try? LOCALBHostRuntime.resolveOperational(hostDirectory: LOCALBHostRuntime.defaultHostDirectory()) {
        case .operational:
            report["localb"] = ["status": "operational"]
        case .notInitialized:
            report["localb"] = [
                "status": "not_initialized",
                "recovery": "run first-run ceremony: SIMIGO_LOCALB_MGMT=prepare, then activate (real root: SIMIGO_LOCALB_ALLOW_REAL_ROOT=1)",
            ]
        default:
            report["localb"] = [
                "status": "unresolvable",
                "recovery": "identities may be locked to a previous build's signature in the login keychain; re-run the first-run ceremony against the managed root",
            ]
        }
        report["finished_at"] = ISO8601DateFormatter().string(from: Date())
        return report
    }

    /// Install an external binary from a URL: download to a temp cache,
    /// verify it is a Mach-O executable, move it into the managed bin
    /// (0755), then DELETE the download cache (owner 2026-10-26: 选择后
    /// 自动安装、转移并清理缓存). Named by the URL's last path component.
    @MainActor
    public func installExternalBinary(from url: URL) async -> [String: Any] {
        let name = url.lastPathComponent.isEmpty ? "tool" : url.lastPathComponent
        let cacheDir = SimiGoPaths.staging
        let tmp = cacheDir.appendingPathComponent("dl-\(UUID().uuidString)-\(name)")
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return ["status": "download_failed", "detail": "HTTP \(http.statusCode)"]
            }
            try data.write(to: tmp)
            // executable check: Mach-O magic (MH_MAGIC_64 / FAT)
            let magic = data.prefix(4)
            let isMachO = magic == Data([0xCF, 0xFA, 0xED, 0xFE])
                || magic == Data([0xCA, 0xFE, 0xBA, 0xBE])
                || magic == Data([0xFE, 0xED, 0xFA, 0xCF])
            guard isMachO else {
                try? fm.removeItem(at: tmp)
                return ["status": "not_executable", "detail": "\(name) is not a Mach-O binary"]
            }
            let target = SimiGoPaths.bin.appendingPathComponent(name)
            try fm.createDirectory(at: SimiGoPaths.bin, withIntermediateDirectories: true)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.moveItem(at: tmp, to: target)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
            return ["status": "installed", "path": target.path, "bytes": data.count]
        } catch {
            try? fm.removeItem(at: tmp)  // cache cleanup even on failure
            return ["status": "failed", "detail": error.localizedDescription]
        }
    }

    /// Update every installable binary in the managed bin (menu entry):
    /// llama.cpp rebuilds from the locked recipe (caches pruned to the
    /// binary), hf upgrades through brew when brew manages it. Returns a
    /// per-tool report.
    public func updateInstalledBinaries() async -> [String: Any] {
        var report: [String: Any] = [:]
        // llama.cpp: drop the installed binary so setupEnvironment rebuilds
        // from the (locked) recipe, then prune caches as usual.
        let llama = SimiGoPaths.bin.appendingPathComponent("llama-server")
        if FileManager.default.fileExists(atPath: llama.path) {
            try? FileManager.default.removeItem(at: llama)
            let previous = selectedEngineID
            selectedEngineID = "llama.cpp"
            await setupEnvironment()
            selectedEngineID = previous
            report["llama.cpp"] = ["status": commandStatus]
        }
        // hf: brew upgrade when present.
        if let brew = Self.findTool("brew"), Self.findTool("hf") != nil {
            do {
                try await runCommand(brew, args: ["upgrade", "huggingface-cli"])
                report["hf"] = ["status": "upgraded"]
            } catch {
                report["hf"] = ["status": "upgrade_failed", "detail": error.localizedDescription]
            }
        }
        return report
    }

    /// Import an operator-supplied external binary into the managed bin
    /// (owner 2026-10-26 install flow): copied verbatim, mode 0755. A name
    /// collision with a DIFFERENT source file is refused; re-importing the
    /// same bytes is a no-op.
    @discardableResult
    public func addExternalBinary(at sourceURL: URL) -> [String: Any] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceURL.path),
            !sourceURL.hasDirectoryPath
        else {
            return ["status": "invalid", "detail": "not a file: \(sourceURL.path)"]
        }
        let target = SimiGoPaths.bin.appendingPathComponent(sourceURL.lastPathComponent)
        do {
            try fm.createDirectory(at: SimiGoPaths.bin, withIntermediateDirectories: true)
            if fm.fileExists(atPath: target.path) {
                let existing = fm.contents(atPath: target.path)?.count ?? -1
                let incoming = fm.contents(atPath: sourceURL.path)?.count ?? -2
                guard existing != incoming else {
                    try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
                    return ["status": "already_present", "path": target.path]
                }
                return ["status": "name_conflict", "detail":
                            "bin/\(sourceURL.lastPathComponent) already exists with different content"]
            }
            try fm.copyItem(at: sourceURL, to: target)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
            return ["status": "imported", "path": target.path]
        } catch {
            return ["status": "failed", "detail": error.localizedDescription]
        }
    }

    /// Register an external work root in the authoritative database
    /// (shared by the first-run wizard and the menu entry).
    @discardableResult
    public func registerWorkRoot(_ path: String) -> [String: Any] {
        let standardized = (path as NSString).standardizingPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDir),
            isDir.boolValue
        else {
            return ["status": "invalid", "detail": "not a directory: \(standardized)"]
        }
        do {
            let db = try SimiGoESISDatabase(url: SimiGoPaths.databaseURL, createIfNeeded: true)
            try db.runMigrations()
            let rootID = "work-" + Self.stableRootID(forPath: standardized)
            try db.upsertRoot(
                rootID: rootID, category: "work", displayName: standardized,
                locatorType: "path", status: "registered")
            return ["status": "registered", "root_id": rootID, "path": standardized]
        } catch {
            return ["status": "failed", "detail": error.localizedDescription]
        }
    }

    /// Stable root id for a registered work root: FNV-1a over the
    /// standardized path — reproducible across runs, no crypto requirement.
    nonisolated static func stableRootID(forPath path: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016x", hash)
    }

    /// Run a command and return its trimmed stdout (used by hf provisioning).
    static func captureCommand(_ cmd: String, args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: cmd)
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "EnvManager", code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: "\(cmd) exited \(process.terminationStatus)"]))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
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

            process.terminationHandler = { [weak self] process in
                let handle = pipe.fileHandleForReading
                handle.readabilityHandler = nil
                // 竞态修复（2026-09-30）：置 nil 与进程退出之间管道里可能还压着
                // 最后一块输出——直接 resume 会把收尾总结行整个丢掉。先排干再
                // 恢复 continuation（Task 入队在 resume 之前，实践中先于收尾行）。
                let residual = handle.availableData
                if !residual.isEmpty, let text = String(data: residual, encoding: .utf8) {
                    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty {
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.appendCommandLog(clean)
                        }
                    }
                }
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
            commandInput = Self.defaultCommandInput
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
                let handle = pipe.fileHandleForReading
                handle.readabilityHandler = nil
                // 竞态修复（2026-09-30）：置 nil 与进程退出之间管道里可能还压着
                // 最后一块输出——直接 resume 会把收尾总结行整个丢掉。先排干再
                // 恢复 continuation（Task 入队在 resume 之前，实践中先于收尾行）。
                let residual = handle.availableData
                if !residual.isEmpty, let text = String(data: residual, encoding: .utf8) {
                    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty {
                        Task { @MainActor in onOutput(clean) }
                    }
                }
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
