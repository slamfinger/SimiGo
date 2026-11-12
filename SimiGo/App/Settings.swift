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
    @State private var digestProgress = ""
    /// 长任务（补摘要）的停止开关。人已经证明会直接杀进程，那就给一个按钮。
    @State private var repairStop = RepairStop()

    /// 补摘要一轮十几秒，几千轮就是几小时。停止要做成可传递的旗子，
    /// 而不是靠「杀掉窗口」。
    final class RepairStop: @unchecked Sendable {
        var stopped = false
    }
    /// 库内房间。目录房间在上面的工作目录行里已经露过脸，这里只列没有目录的
    /// 内部房间（SimiGo / 信息空间 / 本地推理 / 其他），并把每个目录挂在哪个
    /// 房间记在 `rootRoomTitles` 里贴回目录行。
    @State private var rooms: [RoomSummary] = []
    @State private var rootRoomTitles: [String: String] = [:]
    @State private var roomMessage = ""
    @State private var newRoomTitle = ""
    @State private var showingNewRoom = false
    /// 多选合并用的勾选集合；房间只是名字，勾几个就并几个。
    @State private var selectedRooms: Set<String> = []
    /// 删名字：有接管房间 → `pendingDeletion`；库里只剩它一个 → `roomWithoutHome`。
    @State private var pendingDeletion: DeletionRequest?
    @State private var roomWithoutHome: RoomSummary?
    /// 合并前先确认「保留哪个名字」，确认框里把它写出来。
    @State private var pendingMergeTitle: String?
    @State private var pendingMergeID: String?
    /// 改名保留（删名时没有房间可接管的那条退路）。
    @State private var renameTarget: RoomSummary?
    /// 建新房间是为了接管某个要被删掉的名字。
    @State private var pendingHandover: RoomSummary?

    private struct RoomSummary: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let titleSource: String
        let kind: String
        let roots: Int
        let turns: Int
    }

    private struct DeletionRequest: Identifiable, Sendable {
        let id = UUID()
        let room: RoomSummary
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
    }

    private func removeWorkRoot(_ root: EnvManager.WorkRootEntry) {
        let r = EnvManager.shared.removeWorkRoot(rootID: root.rootID)
        envMessage = "\(root.path): \(r["status"] ?? "?")"
        refreshWorkRoots()
        // 目录增删会改「哪个房间挂着谁」，状态与房间账一起跟上。
        refreshRooms()
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
        let handover = pendingHandover
        pendingHandover = nil
        Task.detached(priority: .utility) {
            let message: String
            do {
                let db = try ESISDatabase(
                    url: ManagedPaths.databaseURL, createIfNeeded: true)
                defer { db.close() }
                try db.runMigrations()
                let space = try db.createSpace(
                    title: title, kind: "session", titleSource: "human")
                if let handover {
                    let report = try db.mergeSpace(source: handover.id, into: space.spaceID)
                    message = "已建「\(space.title)」接管「\(handover.title)」："
                        + "目录 \(report.movedRoots) · 轮次 \(report.movedTurns)"
                        + " · 会话 \(report.movedSessions)"
                } else {
                    message = "已建房间「\(space.title)」"
                }
            } catch {
                message = "建房间失败：\(error)"
            }
            await MainActor.run {
                roomMessage = message
                refreshRooms()
            }
        }
    }

    /// 点「删除」先问库里：谁接管这个名称的归属。没有接管者就别删——
    /// 名称是标签，标签没了归属不能悬空，所以退路是新建或改名保留。
    private func deleteRoomName(_ room: RoomSummary) {
        Task.detached(priority: .utility) {
            var target: RoomSummary?
            var failure: String?
            do {
                let db = try ESISDatabase(
                    url: ManagedPaths.databaseURL, createIfNeeded: true)
                defer { db.close() }
                if let row = try db.spaceDeletionTarget(for: room.id) {
                    target = RoomSummary(
                        id: row.spaceID, title: row.title,
                        titleSource: row.titleSource, kind: row.kind, roots: 0, turns: 0)
                }
            } catch {
                failure = "查接管房间失败：\(error)"
            }
            await MainActor.run {
                if let failure {
                    roomMessage = failure
                } else if let target {
                    pendingDeletion = DeletionRequest(room: room, target: target)
                } else {
                    roomWithoutHome = room
                }
            }
        }
    }

    /// 真正的删名：归属整体搬给接管房间，然后只删掉这个名字那一行。
    private func handOver(_ request: DeletionRequest) {
        Task.detached(priority: .utility) {
            let message: String
            do {
                let db = try ESISDatabase(
                    url: ManagedPaths.databaseURL, createIfNeeded: true)
                defer { db.close() }
                let report = try db.mergeSpace(
                    source: request.room.id, into: request.target.id)
                message = "已删名字「\(request.room.title)」，归属交给「\(request.target.title)」："
                    + "目录 \(report.movedRoots) · 轮次 \(report.movedTurns)"
                    + " · 会话 \(report.movedSessions)"
            } catch {
                message = "删名失败：\(error)"
            }
            await MainActor.run {
                pendingDeletion = nil
                roomMessage = message
                refreshRooms()
            }
        }
    }

    /// 多选合并。保留哪个名字不让人再选一次：选成员最多的那个（并列取列表里
    /// 靠前的），确认框把结果写出来——合并只动名字，不动数据。
    private func mergeSelectedRooms() {
        let chosen = rooms.filter { selectedRooms.contains($0.id) }
        guard chosen.count >= 2 else { return }
        let kept = chosen.max { lhs, rhs in
            lhs.turns + lhs.roots < rhs.turns + rhs.roots
        } ?? chosen[0]
        pendingMergeTitle = kept.title
        pendingMergeID = kept.id
    }

    private func commitMerge(keeping title: String) {
        let sources = rooms.filter {
            selectedRooms.contains($0.id) && $0.id != pendingMergeID
        }
        let targetID = pendingMergeID
        pendingMergeTitle = nil
        pendingMergeID = nil
        guard let targetID, !sources.isEmpty else { return }
        let targetTitle = title
        Task.detached(priority: .utility) {
            var moved = 0
            var failure: String?
            do {
                let db = try ESISDatabase(
                    url: ManagedPaths.databaseURL, createIfNeeded: true)
                defer { db.close() }
                for source in sources {
                    let report = try db.mergeSpace(source: source.id, into: targetID)
                    moved += report.movedTurns + report.movedRoots + report.movedSessions
                }
            } catch {
                failure = "\(error)"
            }
            await MainActor.run {
                roomMessage = failure.map { "合并失败：\($0)" }
                    ?? "已合并 \(sources.count) 个名字到「\(targetTitle)」，搬运 \(moved) 项归属"
                selectedRooms.subtract(sources.map(\.id))
                refreshRooms()
            }
        }
    }

    private func renameRoom(_ room: RoomSummary) {
        let title = newRoomTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        renameTarget = nil
        Task.detached(priority: .utility) {
            let message: String
            do {
                let db = try ESISDatabase(
                    url: ManagedPaths.databaseURL, createIfNeeded: true)
                defer { db.close() }
                try db.renameSpace(room.id, title: title)
                message = "已把「\(room.title)」改名为「\(title)」"
            } catch {
                message = "改名失败：\(error)"
            }
            await MainActor.run {
                roomMessage = message
                refreshRooms()
            }
        }
    }

    private static let exportDirKey = "simigo.sourceTimeExportDirectory"

    private static var sourceTimeExportDirectory: URL? {
        guard let path = UserDefaults.standard.string(forKey: exportDirKey),
            !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// 时间回填要读源导出文件（AI Studio 的会话文件、深寻的 conversations.json）。
    /// 目录由人选一次后记住：猜路径只会在别人机器上猜错。
    private func chooseExportDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择会话导出目录（含 AI Studio 会话文件或 deepseek 的 conversations.json）"
        panel.prompt = "用这个目录"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: Self.exportDirKey)
        informationSpaceStatus = "时间来源目录：\(url.path)"
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

    /// 库内房间：目录房间已经由上面的工作目录行代表，这里只列没有目录的房间。
    /// 房间只是名字：列表只显示名称，多选后合并，或删掉一个名字把归属交给别处。
    @ViewBuilder
    private var roomsSection: some View {
        let internalRooms = rooms.filter { $0.roots == 0 }
        let selected = internalRooms.filter { selectedRooms.contains($0.id) }
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
                .alert("新建房间", isPresented: $showingNewRoom) {
                    TextField("房间标题", text: $newRoomTitle)
                    Button("创建") { createRoom() }
                    Button("取消", role: .cancel) { pendingHandover = nil }
                } message: {
                    Text(pendingHandover == nil
                        ? "只建一个空房间；轮次与目录的归属不会自动搬进去。"
                        : "建一个新房间，接管「\(pendingHandover!.title)」留下的归属。")
                }
                Button("合并所选") {
                    mergeSelectedRooms()
                }
                .buttonStyle(.borderless)
                .disabled(selected.count < 2)
                .help(selected.count < 2 ? "先勾选两个以上房间" : "把这些房间合并成一个名字")
            }

            if internalRooms.isEmpty {
                Text("没有仅存在于库内的房间")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(internalRooms) { room in
                        HStack(spacing: 6) {
                            Toggle("", isOn: Binding(
                                get: { selectedRooms.contains(room.id) },
                                set: { on in
                                    if on { selectedRooms.insert(room.id) }
                                    else { selectedRooms.remove(room.id) }
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            Text(room.title).font(.caption)
                            Spacer()
                            Button {
                                deleteRoomName(room)
                            } label: {
                                Text("删除").font(.caption2)
                            }
                            .buttonStyle(.borderless)
                            .help("删掉这个房间名：归属交给别的房间，数据与关系不删")
                        }
                    }
                }
                .alert(
                    "删除房间名？",
                    isPresented: Binding(
                        get: { pendingDeletion != nil },
                        set: { if !$0 { pendingDeletion = nil } }
                    ),
                    presenting: pendingDeletion
                ) { request in
                    Button("删除名字", role: .destructive) { handOver(request) }
                    Button("取消", role: .cancel) { pendingDeletion = nil }
                } message: { request in
                    Text("「\(request.room.title)」的归属交给「\(request.target.title)」，"
                        + "只少一个名字；轮次、目录、会话与结算都不动。")
                }
                .alert(
                    "没有可接管的房间",
                    isPresented: Binding(
                        get: { roomWithoutHome != nil },
                        set: { if !$0 { roomWithoutHome = nil } }
                    ),
                    presenting: roomWithoutHome
                ) { room in
                    Button("新建一个接管") {
                        pendingHandover = room
                        roomWithoutHome = nil
                        newRoomTitle = "新房间"
                        showingNewRoom = true
                    }
                    Button("改名保留") {
                        renameTarget = room
                        roomWithoutHome = nil
                        newRoomTitle = room.title
                    }
                    Button("取消", role: .cancel) { roomWithoutHome = nil }
                } message: { room in
                    Text("「\(room.title)」是库里最后一个房间，删掉名字它的归属就没处可去。"
                        + "建一个新房间接管，或者把这个名字留着改一个。")
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
            "合并房间名？",
            isPresented: Binding(
                get: { pendingMergeTitle != nil },
                set: { if !$0 { pendingMergeTitle = nil } }
            ),
            presenting: pendingMergeTitle
        ) { kept in
            Button("合并", role: .destructive) { commitMerge(keeping: kept) }
            Button("取消", role: .cancel) { pendingMergeTitle = nil }
        } message: { kept in
            Text("这些房间的归属都挂到名字「\(kept)」下面，其余名字消失；"
                + "轮次、目录、会话与结算都不动。")
        }
        .alert(
            "改房间名",
            isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            ),
            presenting: renameTarget
        ) { room in
            TextField("房间标题", text: $newRoomTitle)
            Button("改名") { renameRoom(room) }
            Button("取消", role: .cancel) { renameTarget = nil }
        } message: { _ in
            Text("只改这一行名字，归属不动。")
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
                        // 两个入口两种活，别混：
                        //   外部信息采集 = 入口，人指定一个目录，把里面的会话**搬进来**；
                        //   刷新状态     = 收口，把已经进来的东西补成能用的账（轮账、时间、
                        //                  房间、摘要、关键词）。它不引入任何新素材。
                        // 读状态那一屏数字撤了：数不产生动作，要知道状态去问代理。
                        // 对账也不放按钮上：它把「没扫到」写成 missing，语义相反。
                        HStack {
                            Button("刷新状态") { refreshInformationSpace() }
                            if informationSpaceBusy {
                                Button("停止") { repairStop.stopped = true }
                                ProgressView().controlSize(.small)
                            }
                            Button("时间来源目录…") { chooseExportDirectory() }
                                .help("选会话导出目录（AI Studio / 深寻），回填原始对话时间用；只读，记一次就够")
                            Button("外部信息采集…") { openCollectionBridge() }
                                .disabled(collectionBusy)
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
                if informationSpaceStatus.isEmpty {
                    informationSpaceStatus =
                        "未收口。按「刷新状态」把历史补齐：轮账 → 时间 → 房间 → 摘要 → 关键词。"
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: EnvManager.workRootsDidChange)) { _ in
                refreshWorkRoots()
            }
        }
    }

    /// 「刷新状态」＝ 把**已经进来的**东西一次性收口，五个动作，按依赖排队：
    ///
    /// 1 补轮账（补采）：采集桥写进来的消息本来没有轮次账，没有账就没有摘要、
    ///   没有关键词、没有房间。只补「一行账都没有」的会话，重复点是空操作。
    /// 2 补时间：`seen_at` 是导入批次时间，排不出真实先后；原始时间在会话 id
    ///   与源导出文件里。六条来源，缺源文件就记缺口——不假装对上。
    /// 3 补房间：按内容把轮次归进房间（每轴每轮最多一间）。
    /// 4 补摘要 / 5 补关键词：要本地模型，一轮十几秒，所以放最后——前面的账
    ///   是它的输入。可中途「停止」。
    ///
    /// 为什么不读状态：读数不产生动作，人盯着一堆数字没有意义；要知道状态去问
    /// 代理。这里只留一行回执，说清每一段补了多少、还剩多少。
    ///
    /// 一次性的活。之后新轮次由本地模型增量补（写入那一轮时就补），不走这条路。
    private func refreshInformationSpace() {
        guard !informationSpaceBusy else { return }
        informationSpaceBusy = true
        repairStop.stopped = false
        let stop = repairStop
        let exportDir = Self.sourceTimeExportDirectory
        digestProgress = "收口 1/5：补轮账（补采）"

        Task.detached(priority: .utility) {
            var lines: [String] = []
            func step(_ text: String) {
                Task { @MainActor in digestProgress = text }
            }
            func act(_ body: (ESISDatabase) throws -> String) {
                do {
                    let db = try ESISDatabase(
                        url: ManagedPaths.databaseURL, createIfNeeded: true)
                    defer { db.close() }
                    try db.runMigrations()
                    lines.append(try body(db))
                } catch {
                    lines.append("中断：\(error)")
                }
            }

            act { db in
                let r = try db.backfillImportedTurnLedger()
                return "轮账：导入 \(r.importedTurnsTotal) 轮（本次补 \(r.turnsInserted)，"
                    + "保留 \(r.sessionsKept) 个会话原轮号）"
            }
            guard !stop.stopped else {
                await finish(lines, stop: true)
                return
            }

            step("收口 2/5：补时间")
            act { db in
                let r = try db.backfillSourceTimes(
                    deepseekJSON: exportDir?.appendingPathComponent("conversations.json"),
                    aistudioDirectories: exportDir.map { [$0] } ?? [])
                var text = "时间：命中 \(r.updated) 轮，缺 \(r.missing) 轮"
                if r.missing > 0 {
                    let detail = r.missByPrefix
                        .sorted { $0.value > $1.value }
                        .map { "\($0.key) 缺 \($0.value)" }
                        .joined(separator: "、")
                    text += "（\(detail)）"
                    if exportDir == nil {
                        text += "；AI Studio／深寻要给一次导出目录"
                    }
                }
                return text
            }
            guard !stop.stopped else {
                await finish(lines, stop: true)
                return
            }

            step("收口 3/5：补房间归属")
            act { db in
                let r = try db.assignTurnSpaces()
                return "房间：\(r.rowsWritten) 行归属（关键词命中 \(r.keywordHits) 轮，"
                    + "人工指定保留 \(r.humanRowsKept) 行）"
            }
            await MainActor.run { refreshRooms() }
            guard !stop.stopped else {
                await finish(lines, stop: true)
                return
            }

            step("收口 4/5：补摘要")
            let digests = await TurnDigestScheduler.fillMissing(
                shouldStop: { stop.stopped }
            ) { done, total in
                Task { @MainActor in digestProgress = "补摘要 \(done)/\(total)" }
            }
            lines.append("摘要：成 \(digests.done) 轮，败 \(digests.failed) 轮")
            guard !stop.stopped else {
                await finish(lines, stop: true)
                return
            }

            step("收口 5/5：补关键词")
            let words = await TurnDigestScheduler.repairKeywords(
                shouldStop: { stop.stopped }
            ) { done, total in
                Task { @MainActor in digestProgress = "补关键词 \(done)/\(total)" }
            }
            lines.append("关键词：成 \(words.done) 轮，败 \(words.failed) 轮")
            await finish(lines, stop: false)
        }
    }

    /// 收口回执。停止与走完共用一条出口：留下的账必须一样，差别只在开头那句。
    @MainActor
    private func finish(_ lines: [String], stop: Bool) {
        informationSpaceStatus = (stop ? "已停止。这一段留下的是：\n" : "收口完成：\n")
            + lines.joined(separator: "\n")
        digestProgress = stop ? "已停止" : "收口完成"
        informationSpaceBusy = false
        refreshRooms()
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
