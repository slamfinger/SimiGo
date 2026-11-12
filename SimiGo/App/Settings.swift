import SwiftUI
import AppKit
import Combine
import SimiGoRuntimeContract

struct Settings: View {
    @State private var envMessage = ""
    @EnvironmentObject var svc: Service
    @StateObject private var envMgr = EnvManager.shared
    @State private var collectionReport = ""
    @State private var collectionBusy = false
    @State private var workRoots: [EnvManager.WorkRootEntry] = []
    @State private var workRootPendingRemoval: EnvManager.WorkRootEntry?
    @State private var informationSpaceStatus = ""
    @State private var informationSpaceBusy = false
    /// 刷新时顺带读到的「轮号有、摘要没有」的轮数。它只决定「补摘要」这个
    /// 按钮出不出现——刷新本身只读，不偷偷写。
    @State private var missingDigests = 0
    @State private var digestProgress = ""
    /// 刷新时顺带读到的「有摘要但词不够」的轮数，只用来标注「修关键词」。
    @State private var thinKeywords = 0
    /// 库内房间。目录房间在上面的工作目录行里已经露过脸，这里只列没有目录的
    /// 内部房间（SimiGo / 信息空间 / 本地推理 / 其他），并把每个目录挂在哪个
    /// 房间记在 `rootRoomTitles` 里贴回目录行。
    @State private var rooms: [RoomSummary] = []
    @State private var rootRoomTitles: [String: String] = [:]
    @State private var roomMessage = ""
    @State private var newRoomTitle = ""
    @State private var showingNewRoom = false
    @State private var roomPendingDeletion: RoomSummary?
    @State private var pendingMerge: MergeRequest?

    private struct RoomSummary: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let titleSource: String
        let kind: String
        let roots: Int
        let turns: Int
    }

    private struct MergeRequest: Identifiable, Sendable {
        let id = UUID()
        let source: RoomSummary
        let target: RoomSummary
    }

    /// 版本脚注从 bundle 实读（CFBundleShortVersionString + CFBundleVersion），
    /// 随发版自动更新——硬编码 "SimiGo v1.3" 曾滞留四个大版本（2026-09-30）。
    static let versionFooter: String = {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "SimiGo v\(marketing) (build \(build))"
    }()


    private func refreshWorkRoots() {
        workRoots = EnvManager.shared.listWorkRoots()
    }

    private func addWorkRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let r = EnvManager.shared.registerWorkRoot(url.path)
        let imported = r["name_import"] as? [String: Any]
        let detail = imported.map { import_ in
            "文件 \(import_["files"] ?? 0) · 新增 \(import_["inserted"] ?? 0) · "
                + "刷新 \(import_["refreshed"] ?? 0) · 缺失 \(import_["missing"] ?? 0)"
        } ?? ""
        envMessage = """
        \(url.lastPathComponent): \(r["status"] ?? "?") \(r["root_id"] ?? (r["detail"] ?? ""))
        \(detail)
        """
        refreshWorkRoots()
        refreshRooms()
        refreshInformationSpace()
    }

    private func removeWorkRoot(_ root: EnvManager.WorkRootEntry) {
        let r = EnvManager.shared.removeWorkRoot(rootID: root.rootID)
        envMessage = "\(root.path): \(r["status"] ?? "?")"
        refreshWorkRoots()
        // 目录增删会改「哪个房间挂着谁」，状态与房间账一起跟上。
        refreshRooms()
        refreshInformationSpace()
    }

    /// 读房间账。只读，和「刷新状态」同一轮动作的两半：一个报载体，一个报归属。
    private func refreshRooms() {
        let roots = workRoots
        Task.detached(priority: .utility) {
            var rows: [RoomSummary] = []
            var titles: [String: String] = [:]
            do {
                let db = try ESISDatabase(
                    url: ManagedPaths.databaseURL, createIfNeeded: true)
                defer { db.close() }
                try db.runMigrations()
                rows = try db.listSpaces().map { space in
                    let occupancy = try db.spaceOccupancy(space.spaceID)
                    return RoomSummary(
                        id: space.spaceID, title: space.title,
                        titleSource: space.titleSource, kind: space.kind,
                        roots: occupancy.roots, turns: occupancy.turns)
                }
                for root in roots {
                    if let space = try db.space(forRoot: root.rootID) {
                        titles[root.rootID] = space.title
                    }
                }
            } catch {
                let message = "房间读取失败：\(error)"
                await MainActor.run { roomMessage = message }
                return
            }
            await MainActor.run {
                rooms = rows
                rootRoomTitles = titles
            }
        }
    }

    private func createRoom() {
        let title = newRoomTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        Task.detached(priority: .utility) {
            let message: String
            do {
                let db = try ESISDatabase(
                    url: ManagedPaths.databaseURL, createIfNeeded: true)
                defer { db.close() }
                try db.runMigrations()
                let space = try db.createSpace(
                    title: title, kind: "session", titleSource: "human")
                message = "已建房间「\(space.title)」"
            } catch {
                message = "建房间失败：\(error)"
            }
            await MainActor.run {
                roomMessage = message
                refreshRooms()
                refreshInformationSpace()
            }
        }
    }

    private func deleteRoom(_ room: RoomSummary) {
        Task.detached(priority: .utility) {
            let message: String
            do {
                let db = try ESISDatabase(
                    url: ManagedPaths.databaseURL, createIfNeeded: true)
                defer { db.close() }
                try db.deleteEmptySpace(room.id)
                message = "已删房间「\(room.title)」"
            } catch {
                message = "删房间失败：\(error)"
            }
            await MainActor.run {
                roomMessage = message
                refreshRooms()
                refreshInformationSpace()
            }
        }
    }

    private func mergeRoom(_ request: MergeRequest) {
        Task.detached(priority: .utility) {
            let message: String
            do {
                let db = try ESISDatabase(
                    url: ManagedPaths.databaseURL, createIfNeeded: true)
                defer { db.close() }
                let report = try db.mergeSpace(
                    source: request.source.id, into: request.target.id)
                message = "已把「\(request.source.title)」并入「\(request.target.title)」："
                    + "目录 \(report.movedRoots) · 轮次 \(report.movedTurns)"
                    + "（已在目标 \(report.absorbedTurns)） · 会话 \(report.movedSessions)"
            } catch {
                message = "合并失败：\(error)"
            }
            await MainActor.run {
                roomMessage = message
                refreshRooms()
                refreshInformationSpace()
            }
        }
    }

    /// 外部信息采集＝「选哪个目录就导入哪个目录」：点按钮弹目录面板，选完
    /// 递归扫一遍，按结构识别格式（Markdown 会话导出 / Codex 日志 /
    /// ChatGPT 导出 / AI Studio / DeepSeek / flat 导出），把已结束的问答对
    /// 写进 Information Space。一次性导入、可重复触发（幂等），不是监听器。
    /// 取消面板不改动任何状态。
    private func openCollectionBridge() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择要采集的目录（会话导出所在目录）"
        panel.prompt = "采集此目录"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        collectionBusy = true
        collectionReport = "扫描中… \(url.lastPathComponent)"
        Task.detached(priority: .utility) {
            let outcome = Result { try MultiFormatCollection().importDirectory(url) }
            await MainActor.run {
                collectionBusy = false
                switch outcome {
                case .success(let report):
                    collectionReport = report.summary
                    // 采集会新建房间与轮次归属，状态与房间账都跟着动。
                    refreshRooms()
                    refreshInformationSpace()
                case .failure(let error):
                    collectionReport = "采集失败：\(error)"
                }
            }
        }
    }

    /// 与首启向导同一张 `roots` 表：这里的 +/− 增减的就是安装时设定的
    /// 外部工作目录，磁盘文件一律不动。
    private var workRootsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("外部工作目录").font(.subheadline)
                Spacer()
                Button { addWorkRoot() } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("添加外部工作目录…")
            }
            if workRoots.isEmpty {
                Text("尚未登记工作目录")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(workRoots) { root in
                    HStack(spacing: 6) {
                        Image(systemName: "folder").font(.system(size: 11))
                        Text(root.path)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let room = rootRoomTitles[root.rootID] {
                            Text(room)
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(4)
                                .help("这个目录落在库内房间「\(room)」下")
                        }
                        Spacer()
                        Button { workRootPendingRemoval = root } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("移除（只移除索引，不删除磁盘文件）")
                    }
                }
            }
            Divider().padding(.vertical, 4)
            roomsSection
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
        .alert(
            "移除工作目录？",
            isPresented: Binding(
                get: { workRootPendingRemoval != nil },
                set: { if !$0 { workRootPendingRemoval = nil } }
            ),
            presenting: workRootPendingRemoval
        ) { root in
            Button("移除", role: .destructive) { removeWorkRoot(root) }
            Button("取消", role: .cancel) { workRootPendingRemoval = nil }
        } message: { root in
            Text("\(root.path)\n只从数据库移除索引，不会删除磁盘上的文件。")
        }
    }

    /// 库内房间：目录房间已经由上面的工作目录行代表，这里只列没有目录的房间，
    /// 并允许对它们直接操作数据库。删除只对空房间开放——房间是归属，不是内容。
    @ViewBuilder
    private var roomsSection: some View {
        let internalRooms = rooms.filter { $0.roots == 0 }
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("库内房间（无外部目录）").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    newRoomTitle = ""
                    showingNewRoom = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("新建空房间")
            }
            // 三个确认框挂在不同子视图上：同一个视图链上叠多个 alert，
            // SwiftUI 只保证最后那个能弹。
            .alert("新建房间", isPresented: $showingNewRoom) {
                TextField("房间标题", text: $newRoomTitle)
                Button("创建") { createRoom() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("只建一个空房间；轮次与目录的归属不会自动搬进去。")
            }

            if internalRooms.isEmpty {
                Text("没有仅存在于库内的房间")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(internalRooms) { room in
                        HStack(spacing: 6) {
                            Image(systemName: "rectangle.stack").font(.system(size: 11))
                            Text(room.title).font(.caption)
                            Text("\(room.turns) 轮")
                                .font(.caption2).foregroundStyle(.secondary)
                            if room.titleSource != "human" {
                                Text(room.titleSource)
                                    .font(.caption2).foregroundStyle(.secondary)
                                    .help("标题不是人写的，改名前先确认")
                            }
                            Spacer()
                            Menu("合并到…") {
                                ForEach(rooms.filter { $0.id != room.id }) { target in
                                    Button(target.title) {
                                        pendingMerge = MergeRequest(source: room, target: target)
                                    }
                                }
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .disabled(rooms.count < 2)
                            Button {
                                roomPendingDeletion = room
                            } label: {
                                Text("删除").font(.caption2)
                            }
                            .buttonStyle(.borderless)
                            .disabled(room.turns != 0)
                            .help(room.turns == 0
                                ? "删除这个空房间"
                                : "还有 \(room.turns) 轮归属，先合并到别的房间再删")
                        }
                    }
                }
                .alert(
                    "删除房间？",
                    isPresented: Binding(
                        get: { roomPendingDeletion != nil },
                        set: { if !$0 { roomPendingDeletion = nil } }
                    ),
                    presenting: roomPendingDeletion
                ) { room in
                    Button("删除", role: .destructive) { deleteRoom(room) }
                    Button("取消", role: .cancel) { roomPendingDeletion = nil }
                } message: { room in
                    Text("「\(room.title)」是空房间，删除只去掉这一行归属记录，"
                        + "不动任何轮次与文件。")
                }
            }
            if !roomMessage.isEmpty {
                Text(roomMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .alert(
            "合并房间？",
            isPresented: Binding(
                get: { pendingMerge != nil },
                set: { if !$0 { pendingMerge = nil } }
            ),
            presenting: pendingMerge
        ) { request in
            Button("合并", role: .destructive) { mergeRoom(request) }
            Button("取消", role: .cancel) { pendingMerge = nil }
        } message: { request in
            Text("把「\(request.source.title)」的 \(request.source.turns) 轮归属搬到"
                + "「\(request.target.title)」，然后删掉空掉的「\(request.source.title)」。"
                + "轮次、文件、结算都不删。")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: - Information Space
                sectionBox("Information Space（数据库）") {
                    VStack(alignment: .leading, spacing: 10) {
                        workRootsPanel
                        if !envMessage.isEmpty {
                            Text(envMessage).font(.caption).foregroundStyle(.secondary)
                        }
                        Divider()
                        // 只留两件：读状态（顺带逐对象校验，反正 9k 对象
                        // 0.06 秒），和缺摘要时的补齐。对账不再放按钮上——
                        // 它把「没扫到」写成 missing，语义与契约相反。
                        HStack {
                            Button("刷新状态") { refreshInformationSpace() }
                            if missingDigests > 0 {
                                Button("补摘要 \(missingDigests) 轮") { fillMissingDigests() }
                                // 先小样再全量：一轮实测十几秒，2,600 轮是
                                // 十几小时的量级，摘要质量得先看二十条。
                                Button("小样 100 轮") { fillMissingDigests(limit: 100) }
                            }
                            // 只补词、不动摘要：词是检索入口，缺口的这本账
                            // 和「缺摘要」不是一回事，所以不分开关。数字由上面
                            // 那次刷新读出来，所以它跟着刷新走，不另开一套账。
                            Button(thinKeywords > 0 ? "修关键词 \(thinKeywords) 轮" : "修关键词") {
                                repairKeywords()
                            }
                            Button("外部信息采集…") { openCollectionBridge() }
                                .disabled(collectionBusy)
                            if informationSpaceBusy {
                                ProgressView().controlSize(.small)
                            }
                        }
                        .disabled(informationSpaceBusy)
                        if !digestProgress.isEmpty {
                            Text(digestProgress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !collectionReport.isEmpty {
                            Text(collectionReport)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        if !informationSpaceStatus.isEmpty {
                            Text(informationSpaceStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                sectionBox("Backend 设置") {
                    localBackendRow(
                        title: "MLX",
                        path: svc.mlxModelPath,
                        selection: .mlx
                    )

                    Divider().padding(.vertical, 6)

                    localBackendRow(
                        title: "LLaMA.cpp",
                        path: svc.llamaModelPath,
                        selection: .llamaCpp
                    )

                    Divider().padding(.vertical, 6)

                    Text("本地推理参数 · 仅 MLX / LLaMA.cpp")
                        .font(.subheadline)

                    HStack(spacing: 12) {
                        paramRow("Temp", value: $svc.config.temperature, range: 0...2, step: 0.1)
                        paramRow("Top-P", value: $svc.config.topP, range: 0...1, step: 0.05)
                        intRow("Top-K", value: $svc.config.topK, width: 50)
                    }
                    HStack(spacing: 12) {
                        paramRow("Min-P", value: $svc.config.minP, range: 0...0.3, step: 0.01)
                        intRow("Max Tokens", value: $svc.config.maxTokens, width: 60)
                    }
                    HStack(spacing: 12) {
                        paramRow("Presence", value: $svc.config.presencePenalty, range: 0...2, step: 0.1)
                        paramRow("Repeat", value: $svc.config.repeatPenalty, range: 0.8...2, step: 0.05)
                    }
                    HStack(spacing: 16) {
                        Toggle("禁用思考", isOn: $svc.config.disableThinking)
                        Toggle("Trust Remote", isOn: $svc.config.trustRemoteCode)
                    }
                    Divider().padding(.vertical, 2)
                    HStack(spacing: 12) {
                        intRow("Speculative 草稿数", value: $svc.config.specDraftNMax, width: 60)
                        Text("共用参数").font(.caption).foregroundColor(.secondary)
                        Spacer()
                    }
                    Text("用于支持 Speculative Decode 的运行时。没有草稿模型时不会启用；数值表示每轮最多生成的草稿 Token 数。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("当前值：\(svc.config.specDraftNMax)")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text("LLaMA.cpp 专用").font(.subheadline)
                    HStack {
                        intRow("GPU Layers", value: $svc.config.gpuLayers, width: 60)
                        intRow("Context", value: $svc.config.ctxSize, width: 60)
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                        Toggle("Jinja", isOn: $svc.config.jinja)
                        Toggle("FlashAttn", isOn: $svc.config.flashAttention)
                        Toggle("MTP", isOn: $svc.config.useMTP)
                    }
                }

                // MARK: - 统一命令控制台
                sectionBox("统一命令控制台") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("输入命令，例如 hf download ... / llama-server ...", text: $envMgr.commandInput, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            // 下载期间禁用：防中途改命令；同时释放字段焦点——
                            // 否则聚焦的 NSTextField 字段编辑器会吞掉完成后
                            // 的程序化复位（commandInput 复位代码在 EnvManager，
                            // 绑定值变了但焦点框视觉不变）。
                            .disabled(envMgr.isDownloading)
                            .onSubmit {
                                executeCommand()
                            }

                        HStack(spacing: 8) {
                            Button("下载") {
                                Task {
                                    await envMgr.downloadModel(command: envMgr.commandInput)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(envMgr.isDownloading)

                            Button("升级") {
                                Task {
                                    // 显式升级：先切到 llama.cpp 再按锁定版本重建，
                                    // 已安装的构建不构成跳过理由。
                                    await envMgr.upgradeLlamaCpp()
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(envMgr.commandStatus == "构建中")

                            Button(envMgr.isRecording ? "停止记录" : "记录") {
                                if envMgr.isRecording {
                                    envMgr.stopTraceRecording()
                                } else {
                                    envMgr.startTraceRecording()
                                }
                            }
                            .buttonStyle(.bordered)

                            Button("复制") {
                                copyCommandLog()
                            }
                            .buttonStyle(.bordered)

                            Spacer()
                        }

                        Text("状态：\(envMgr.commandStatus)")
                            .font(.caption)
                            .foregroundColor(envMgr.isRecording ? .orange : .secondary)

                        if envMgr.isDownloading || !envMgr.commandLog.isEmpty {
                            commandLogView(log: envMgr.commandLog)
                        }
                    }
                }

                // MARK: - 操作
                HStack(spacing: 12) {
                    Button("保存默认") {
                        svc.saveCurrentConfigAsModelDefault()
                    }

                    Button("重启服务") {
                        svc.saveCurrentConfigAsModelDefault()
                        Task {
                            await svc.restartSelected()
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()

                    Button("重置") {
                        AppConfig.resetAll()
                    }
                    .foregroundColor(.red)
                }
                .padding(.horizontal)

                Text(Self.versionFooter)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding()
            .onAppear {
                refreshWorkRoots()
                refreshRooms()
                refreshInformationSpace()
            }
            .onReceive(NotificationCenter.default.publisher(for: EnvManager.workRootsDidChange)) { _ in
                refreshWorkRoots()
            }
        }
    }

    /// Carrier status is read off the main thread: deep verification re-hashes
    /// every object, and even the cheap report must not stall the settings UI.
    /// 读状态。逐对象校验一直开着：9,093 个对象 56 MB 实测 0.06 s，
    /// 再分「浅」和「深」两个按钮，只会让人以为浅的那个也能证明字节没坏。
    private func refreshInformationSpace() {
        informationSpaceBusy = true
        informationSpaceStatus = "读取中…"
        Task.detached(priority: .utility) {
            let text: String
            var pending = 0
            var thin = 0
            do {
                let db = try ESISDatabase(
                    url: ManagedPaths.databaseURL, createIfNeeded: true)
                try db.runMigrations()
                // 刷新状态是人的干预点，也是导入历史的第一次衔接：采集桥写进来
                // 的消息本来没有轮次账，没有账就没有摘要、没有关键词、没有房间。
                // 这里补的只是「一行账都没有」的会话，重复点是空操作。
                let imported = try db.backfillImportedTurnLedger()
                let report = try db.carrierReport(deepVerify: true)
                pending = report.turnsWithoutDigest
                thin = try db.turnsWithThinKeywordsCount()
                let unaddressed = report.unaddressedFileContents
                    + report.unaddressedChatMessages
                    + report.unaddressedRetrievalResults
                    + report.unaddressedSettlements
                text = """
                schema v\(report.schemaVersion) · 对象 \(report.objectCount)（\(report.objectBytes) 字节）· \
                索引 \(report.indexEntries) · 依赖 \(report.dependencyEntries) · 未寻址 \(unaddressed) · \
                内联旧载荷 \(report.inlineLegacyPayloads) · 悬空引用 \(report.danglingReferences) · \
                损坏 \(report.corruptObjects)（已逐对象校验）
                空间 \(report.spaces) · 依赖区间 开 \(report.dependencyIntervalsOpen)／闭 \(report.dependencyIntervalsClosed)／断点 \(report.dependencyIntervalBreaks)
                轮次摘要 \(report.turnDigests) 轮 · 缺摘要 \(report.turnsWithoutDigest) 轮 · \
                缺关键词 \(thin) 轮 · \
                导入轮 \(imported.importedTurnsTotal) 轮（本次补 \(imported.turnsInserted)，保留 \(imported.sessionsKept) 个会话的原有轮号）
                """
            } catch {
                text = "读取失败：\(error)"
            }
            await MainActor.run {
                informationSpaceStatus = text
                missingDigests = pending
                thinKeywords = thin
                informationSpaceBusy = false
            }
        }
    }

    /// 补摘要：走和自动摘要同一条路（本地模型 + recordTurnDigest），
    /// 只是这里由人按下去。一轮补完报一次进度，补完刷新一遍状态。
    private func fillMissingDigests(limit: Int? = nil) {
        informationSpaceBusy = true
        digestProgress = "补摘要中…"
        Task.detached(priority: .utility) {
            let result = await TurnDigestScheduler.fillMissing(limit: limit) { done, total in
                Task { @MainActor in
                    digestProgress = "补摘要 \(done)/\(total)"
                }
            }
            await MainActor.run {
                digestProgress = "补摘要完成：成 \(result.done) 轮，失败 \(result.failed) 轮"
                informationSpaceBusy = false
            }
            refreshInformationSpace()
        }
    }

    /// 修词：还是本地模型那条路，但只写 `keywords`——正文、来源标记、
    /// 写入时间都不动。补不上的轮次留在「词不够」里，不假装修过。
    private func repairKeywords(limit: Int? = nil) {
        informationSpaceBusy = true
        digestProgress = "修词中…"
        Task.detached(priority: .utility) {
            let result = await TurnDigestScheduler.repairKeywords(limit: limit) { done, total in
                Task { @MainActor in
                    digestProgress = "修词 \(done)/\(total)"
                }
            }
            await MainActor.run {
                digestProgress = "修词完成：成 \(result.done) 轮，失败 \(result.failed) 轮"
                informationSpaceBusy = false
            }
            refreshInformationSpace()
        }
    }

    private func localBackendRow(title: String, path: String, selection: BackendSelection) -> some View {
        let expectedKind: ModelKind = selection == .mlx ? .mlx : .gguf
        let isModelRunning = svc.isRunning && svc.hostMode == .model

        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)

                    if svc.backendSelection == selection {
                        Text(isModelRunning ? "运行中" : "已选择")
                            .font(.caption)
                            .foregroundColor(isModelRunning ? .green : .secondary)
                    }
                }

                Text(path.isEmpty ? "未选择模型" : path)
                    .font(.caption)
                    .foregroundColor(path.isEmpty ? .secondary : .primary)
                    .lineLimit(2)
                    .truncationMode(.head)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Button("选择模型...") {
                    chooseLocalModel(expectedKind: expectedKind, selection: selection)
                }
                .disabled(svc.hostMode == .model)

                Button("启动") {
                    Task { @MainActor in
                        await svc.start(selection)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(svc.backendSelection == selection && !svc.hasStartTarget)
            }
        }
    }

    private func chooseLocalModel(expectedKind: ModelKind, selection: BackendSelection) {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard ModelDetector.detect(path: url.path).kind == expectedKind else { return }

            svc.selectModel(url.path)
            svc.backendSelection = selection
        }
    }

    // MARK: - Command Actions
    private func executeCommand() {
        let command = envMgr.commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        Task {
            await envMgr.executeCommand(command)
        }
    }

    private func copyCommandLog() {
        let text = envMgr.commandLog
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - 极简复用组件
    @ViewBuilder
    private func sectionBox<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(.horizontal)
        Divider()
    }

    private func paramRow(_ label: String, value: Binding<Float>, range: ClosedRange<Float>, step: Float) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .frame(width: 80, alignment: .leading)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 50)
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
        }
    }

    private func intRow(_ label: String, value: Binding<Int>, width: CGFloat) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .frame(width: 80, alignment: .leading)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
        }
    }

    @ViewBuilder
    private func logPanel(title: String, isBusy: Bool, buttonTitle: String, progress: Double, log: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(isBusy ? .orange : .secondary)
                Spacer()
                Button(buttonTitle, action: action)
                    .disabled(isBusy)
                    .buttonStyle(.borderedProminent)
            }

            if isBusy || !log.isEmpty {
                logView(progress: progress, log: log)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func logView(progress: Double, log: String) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(log)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(6)
            }

            if progress > 0 && progress < 1 {
                ProgressView(value: progress)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
            }
        }
        .frame(height: 140)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.3))
        )
    }

    @ViewBuilder
    private func commandLogView(log: String) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(log.isEmpty ? "等待命令输出..." : log)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(log.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
                    .id("COMMAND_LOG_BOTTOM")
            }
            .onChange(of: log) { _, _ in
                proxy.scrollTo("COMMAND_LOG_BOTTOM", anchor: .bottom)
            }
        }
        .frame(minHeight: 180, maxHeight: 300)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.3))
        )
    }
}
