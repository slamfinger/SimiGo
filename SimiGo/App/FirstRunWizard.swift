import Foundation
import SwiftUI
import SimiGoRuntimeContract

// 首次运行安装向导（owner 验收 2026-10-26）：
//   删除 ~/.simigo 后安装 DMG 打开 App，向导引导完成
//   ① 选定外部工作目录（写入权威数据库 roots）
//   ② 导入自定义外部二进制（转移至 <root>/bin，0755）
//   ③ 自动自举完整生成环境（目录树/llama.cpp/hf/空白数据库/LOCALB/DMG 留存）
//   ④ 把 App 落位 /Applications 并重启
// 菜单栏常驻同等入口（见 MenuPanelView 的"环境"分区）。

enum FirstRunWizard {

    static var doneMarkerURL: URL {
        SimiGoPaths.manifests.appendingPathComponent("first-run-done.json")
    }

    static func isNeeded() -> Bool {
        !FileManager.default.fileExists(atPath: doneMarkerURL.path)
    }

    static func markDone(workRoots: [String], binaries: [String]) {
        let payload: [String: Any] = [
            "finished_at": ISO8601DateFormatter().string(from: Date()),
            "version": (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""),
            "work_roots": workRoots,
            "binaries": binaries,
        ]
        try? FileManager.default.createDirectory(
            at: SimiGoPaths.manifests, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) {
            try? data.write(to: doneMarkerURL)
        }
    }

    static func pickDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    static func pickBinaryFiles() -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }

    /// 把当前运行的 App 落位 /Applications（DMG 拖装后的规范位置）并重启。
    /// 已在 /Applications 时为 no-op；目标已存在不同内容时先移入废纸篓级替换
    /// （直接删除旧副本——安装场景语义）。
    @MainActor
    static func moveToApplicationsAndRelaunch() -> Bool {
        let src = Bundle.main.bundleURL
        let apps = "/Applications"
        if src.deletingLastPathComponent().path == apps { return true }
        let dst = URL(fileURLWithPath: apps).appendingPathComponent(src.lastPathComponent)
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: dst.path) {
                try fm.removeItem(at: dst)
            }
            try fm.moveItem(at: src, to: dst)
        } catch {
            return false
        }
        // 重启到新位置
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [dst.path]
        try? process.run()
        NSApp.terminate(nil)
        return true
    }
}

struct FirstRunWizardView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var workRoots: [String] = []
        @State private var runLog: [String] = []
    @State private var isRunning = false
    @State private var moveResult: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            switch step {
            case 0: welcomeStep
            case 1: workRootStep
            case 2: binaryStep
            case 3: runStep
            case 4: moveStep
            default: EmptyView()
            }
        }
        .padding(20)
        .frame(width: 520, height: 430)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "shippingbox.and.arrow.down.fill")
                .font(.system(size: 30))
                .foregroundStyle(.blue)
            VStack(alignment: .leading) {
                Text("SimiGo 2.2.0 安装向导").font(.title2.bold())
                Text("首次运行：设定工作目录、导入外部二进制、自举生成环境")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Step 0 欢迎与说明

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("将为你完成以下事项：").font(.body.weight(.medium))
            bullet("1", "选定外部工作目录（Execution State / Information Space 的数据入库范围）")
            bullet("2", "从引擎适配清单勾选外部二进制（自动安装 → ~/.simigo/bin → 清理缓存）")
            bullet("3", "自举生成环境：目录树、llama.cpp 工具链、hf、空白数据库、LOCALB")
            bullet("4", "把 SimiGo 落位到 /Applications 并重启")
            Text("目标目录：\(SimiGoPaths.managedRoot().path)")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            HStack {
                Spacer()
                Button("开始") { step = 1 }.keyboardShortcut(.defaultAction).controlSize(.large)
            }
        }
    }

    // MARK: Step 1 工作目录（进入即弹出选择器）

    private var workRootStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择外部工作目录").font(.headline)
            Text("Execution State / Information Space 的数据入库范围（可多次添加；之后菜单栏也可追加）")
                .font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                if workRoots.isEmpty {
                    HStack {
                        Image(systemName: "folder.badge.plus").foregroundStyle(.blue)
                        Text("尚未选择").foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
                ForEach(workRoots, id: \.self) { path in
                    HStack {
                        Image(systemName: "folder")
                        Text(path).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button {
                            workRoots.removeAll { $0 == path }
                        } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }.padding(.vertical, 2)
                }
            }
            .padding(8).frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor)).cornerRadius(6)
            HStack {
                Button("再选一个…") { pickAnother() }
                Spacer()
                Button("跳过") { step = 2 }
                Button("下一步") { step = 2 }.keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            // 延后异步弹选择器：onAppear 阶段直接 runModal 会吞掉向导窗口
            // 自身的显示（modal 重入主循环，窗口未完成首帧），表现为"闪退"。
            if workRoots.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    NSApp.activate(ignoringOtherApps: true)
                    pickAnother()
                }
            }
        }
    }

    private func pickAnother() {
        if let url = FirstRunWizard.pickDirectory(), !workRoots.contains(url.path) {
            workRoots.append(url.path)
        }
    }

    // MARK: Step 2 外部二进制（引擎适配清单）

    /// 勾选的 sourceBuild 引擎 id（目前仅 llama.cpp 已适配；适配一个
    /// 增加一个 = 在引擎清单 engine-recipes.json 里加 recipe 即出现在此）。
    @State private var selectedEngines: Set<String> = []

    private var engineRecipes: [EngineRecipe] {
        SimiGoEngineRegistry.load(
            manifestURL: SimiGoPaths.manifests
                .appendingPathComponent(SimiGoEngineRegistry.manifestName))
    }

    private var binaryStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("外部二进制（引擎适配清单）").font(.headline)
            Text("勾选要自动安装的引擎（自动下载/构建 → 移入 ~/.simigo/bin → 清理缓存）。适配一个即在此新增一个。")
                .font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(engineRecipes, id: \.id) { recipe in
                    engineRow(recipe)
                }
            }
            .padding(8).frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor)).cornerRadius(6)
            HStack {
                Spacer()
                Button("执行安装") { step = 3 }.keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder
    private func engineRow(_ recipe: EngineRecipe) -> some View {
        HStack {
            Image(systemName: iconFor(recipe))
                .foregroundStyle(colorFor(recipe))
            VStack(alignment: .leading, spacing: 1) {
                Text(recipe.displayName).font(.body.weight(.medium))
                Text(subtitleFor(recipe)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            switch recipe.kind {
            case .sourceBuild:
                Toggle("", isOn: Binding(
                    get: { selectedEngines.contains(recipe.id) },
                    set: { on in
                        if on { selectedEngines.insert(recipe.id) }
                        else { selectedEngines.remove(recipe.id) }
                    }))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            default:
                Text("采用型").font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15)).cornerRadius(4)
            }
        }
        .padding(.vertical, 2)
    }

    private func iconFor(_ recipe: EngineRecipe) -> String {
        switch recipe.kind {
        case .nativeRuntime: return "cpu"
        case .sourceBuild: return "shippingbox.and.arrow.down"
        case .externalServer: return "network"
        }
    }

    private func colorFor(_ recipe: EngineRecipe) -> Color {
        switch recipe.kind {
        case .sourceBuild: return .blue
        case .nativeRuntime: return .green
        case .externalServer: return .orange
        }
    }

    private func subtitleFor(_ recipe: EngineRecipe) -> String {
        switch recipe.kind {
        case .nativeRuntime: return "内置运行时，无需安装"
        case .sourceBuild:
            return recipe.isVersionLocked
                ? "自动安装（锁定 \(recipe.pinnedRef ?? "")）"
                : "自动安装（清单未锁定版本时默认锁定）"
        case .externalServer:
            return "外部服务端：产品采用、不自动安装（\(recipe.id)）"
        }
    }

    // MARK: Step 3 执行自举

    private var runStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("安装执行").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    if runLog.isEmpty {
                        Text("…").foregroundStyle(.secondary)
                    }
                    ForEach(Array(runLog.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(size: 11, design: .monospaced))
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .border(Color.secondary.opacity(0.3))
            HStack {
                if isRunning { ProgressView().controlSize(.small) }
                Spacer()
                Button("继续") { step = 4 }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isRunning || runLog.isEmpty)
            }
        }
        .task { await runInstall() }
    }

    // MARK: Step 4 落位 /Applications

    private var moveStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("落位应用程序文件夹").font(.headline)
            if Bundle.main.bundleURL.deletingLastPathComponent().path == "/Applications" {
                Label("已在 /Applications", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("把 SimiGo 移动到 /Applications 并重启（DMG 内运行时为标准收尾）。")
                if let moveResult, moveResult != "ok" {
                    Text(moveResult).foregroundStyle(.red).font(.caption)
                }
            }
            Spacer()
            HStack {
                Button("暂不") { finish() }
                Spacer()
                if Bundle.main.bundleURL.deletingLastPathComponent().path != "/Applications" {
                    Button("移动并重启") {
                        if FirstRunWizard.moveToApplicationsAndRelaunch() {
                            _ = finishAndClose()
                        } else {
                            moveResult = "移动失败（可能正在从只读介质运行）：请手动拖入 /Applications"
                        }
                    }
                    .controlSize(.large).keyboardShortcut(.defaultAction)
                } else {
                    Button("完成") { finish() }
                        .controlSize(.large).keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    // MARK: helpers

    private func bullet(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(n).font(.callout.bold()).frame(width: 16)
            Text(text).font(.callout)
        }
    }

    @discardableResult
    private static func pickDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    static func pickBinaryFiles() -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return [] }
        return panel.urls
    }

    private func log(_ line: String) {
        runLog.append(line)
    }

    private func runInstall() async {
        guard runLog.isEmpty else { return }
        isRunning = true
        defer { isRunning = false }

        log("== 外部二进制（引擎适配清单自动安装）==")
        for engineID in selectedEngines.sorted() {
            let previous = EnvManager.shared.selectedEngineID
            EnvManager.shared.selectedEngineID = engineID
            await EnvManager.shared.setupEnvironment()
            EnvManager.shared.selectedEngineID = previous
            log("\(engineID): \(EnvManager.shared.commandStatus)")
        }
        log("== 工作目录 ==")
        for path in workRoots {
            let r = EnvManager.shared.registerWorkRoot(path)
            log("\(path): \(r["status"] ?? "?") \(r["root_id"] ?? (r["detail"] ?? ""))")
        }
        log("== 生成环境自举 ==")
        let report = await EnvManager.shared.bootstrapGenerationEnvironment(workRoot: nil)
        for key in ["engine_manifest", "llama_cpp", "hf", "database", "localb", "dmg"] {
            if let v = report[key] as? [String: Any] {
                log("\(key): \(v["status"] ?? v["ceremony"] ?? "?")")
            }
        }
        FirstRunWizard.markDone(workRoots: workRoots, binaries: selectedEngines.sorted())
        log("== 完成 ==")
    }

    private func finish() {
        FirstRunWizard.markDone(workRoots: workRoots, binaries: selectedEngines.sorted())
        _ = finishAndClose()
    }

    private func finishAndClose() -> Bool {
        NSApp.windows
            .first(where: { ($0.contentView as? NSHostingView<FirstRunWizardView>) != nil })?
            .close()
        return true
    }
}
