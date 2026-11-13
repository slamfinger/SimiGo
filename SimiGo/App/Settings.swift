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
    /// 采集回执的收尾凭据：每写一次换号重计时，旧的定时器就不再清屏。
    @State private var collectionToken = 0
    @State private var workRoots: [EnvManager.WorkRootEntry] = []
    @State private var workRootPendingRemoval: EnvManager.WorkRootEntry?
    @State private var informationSpaceStatus = ""
    @State private var informationSpaceBusy = false
    @State private var digestProgress = ""
    /// 一次性文本的收尾凭据。每开一轮加一，旧定时器看见号变了就不再清屏，
    /// 否则上一轮 10 秒到点会把这一轮的进度擦掉。
    @State private var transientToken = 0
    /// 缺口：轮账 / 时间 / 摘要 / 关键词各缺多少。界面拿它当入口。
    @State private var gaps: ESISDatabase.TurnGapCounts?
    /// 归属恢复状态：待办队列、已放弃记录与房间缺口共同决定恢复入口。
    @State private var spaceRetry: ESISDatabase.SpaceAssignmentRetryStatus?
    /// 缺口那一行默认不露脸：点过「状态刷新」才出现，出现后右边才长出开始/停止。
    @State private var gapsRevealed = false
    /// 长任务（补摘要）的停止开关。人已经证明会直接杀进程，那就给一个按钮。
    /// 状态与轮询都在 `TurnDigestScheduler.DigestStop` 里（锁保护，且能打断
    /// 正在跑的生成），界面只负责按一下。
    @State private var repairStop = TurnDigestScheduler.DigestStop()
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
    /// 靠前的），确认框把结果写出来。合并搬的是归属行（目录/轮次/会话），
    /// 轮次和对象本身不动。
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

    /// 导出目录下面还常有一层：`<目录>/deepseek_data-*/conversations.json`、
    /// `<目录>/Google AI Studio/<标题>`。只往下看一层——再深就是在猜别人的目录结构了。
    private static func exportSubdirectories(_ dir: URL) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return [dir] + entries.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    private static func deepseekExportFile(_ dir: URL) -> URL? {
        for candidate in exportSubdirectories(dir) {
            let file = candidate.appendingPathComponent("conversations.json")
            if FileManager.default.fileExists(atPath: file.path) { return file }
        }
        return nil
    }

    /// 信息采集＝「选哪个目录就是哪个目录」，一个按钮管两件事：
    ///   1 把目录里的会话递归扫一遍，按结构识别格式（Markdown 会话导出 / Codex 日志 /
    ///     ChatGPT 导出 / AI Studio / DeepSeek / flat 导出）搬进 Information Space；
    ///   2 把同一个目录记成时间回填的来源（AI Studio 会话文件 / 深寻 conversations.json）。
    /// 两件事本来就吃同一份数据，分开选目录只会让人选两次、还可能选成两个。
    /// 一次性导入、可重复触发（幂等），不是监听器。取消面板不改动任何状态。
    ///
    /// 回执自己收（成功 10 秒、失败留着）：它说的是「刚才发生了什么」，
    /// 不是当前状态——当前状态是缺口、房间那几行。写一次就换号重计时，
    /// 因为房间判定那行是后追加的，不能被前一段的定时器提前擦掉。
    @MainActor
    private func showCollection(_ text: String, appending: Bool = false, keep: Bool = false) {
        collectionReport = appending ? collectionReport + "\n" + text : text
        collectionToken += 1
        guard !keep else { return }
        let token = collectionToken
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard collectionToken == token, !collectionBusy else { return }
            collectionReport = ""
        }
    }

    private func collectFromDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择导出目录（会话导出 / 深寻 conversations.json / AI Studio 会话文件）"
        panel.prompt = "采集此目录"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: Self.exportDirKey)
        collectionBusy = true
        showCollection("扫描中… \(url.lastPathComponent)", keep: true)
        Task.detached(priority: .utility) {
            let outcome = Result { try MultiFormatCollection().importDirectory(url) }
            await MainActor.run {
                collectionBusy = false
                switch outcome {
                case .success(let report):
                    showCollection("采集完成（来源 \(url.path)）：\n" + report.summary)
                    // 采集只把素材搬进来。新轮次必须当场进房间——不归属的轮次
                    // 等于人进来了没人认识，下一次检索找不到它。这条不等按钮。
                    refreshRooms()
                    refreshGapCounts()
                    assignRoomsAfterCollection()
                case .failure(let error):
                    showCollection("采集失败：\(error)", keep: true)
                }
            }
        }
    }

    /// 采集完就归房间。跟「补录」收尾那一步同一套判据，只是不等人按。
    /// 结果追加在采集回执下面，免得人以为采集完就完事了。
    private func assignRoomsAfterCollection() {
        Task.detached(priority: .utility) {
            let message: String
            do {
                let db = try ESISDatabase(
                    url: ManagedPaths.databaseURL, createIfNeeded: true)
                defer { db.close() }
                try db.runMigrations()
                let r = try db.assignTurnSpaces()
                message = "房间：\(r.rowsWritten) 行归属（自动判定）"
            } catch {
                message = "房间归属失败：\(error)"
            }
            await MainActor.run {
                showCollection(message, appending: true)
                refreshRooms()
                refreshGapCounts()
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

    /// 三页：本地模型那套 / 数据库里那些东西 / 版本。原来挤在一页里，前半页说库、
    /// 后半页说模型，翻起来像两件事被钉在同一张纸上。
    private enum Tab { case settings, informationSpace, version }
    @State private var tab: Tab = .settings

    var body: some View {
        VStack(spacing: 0) {
            // 标签做成顶上一排：窗口 420 宽、不可缩放，侧边栏塞不下也不好看。
            Picker("", selection: $tab) {
                Text("设置").tag(Tab.settings)
                Text("信息空间").tag(Tab.informationSpace)
                Text("版本").tag(Tab.version)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch tab {
                    case .settings: settingsSection
                    case .informationSpace: informationSpaceSection
                    case .version: versionSection
                    }
                }
                .padding()
            }
            .onAppear {
                refreshWorkRoots()
                refreshRooms()
                refreshGapCounts()
            }
            .onReceive(NotificationCenter.default.publisher(for: EnvManager.workRootsDidChange)) { _ in
                refreshWorkRoots()
            }
        }
    }

    /// 第一页：本地模型那一套——后端、参数、命令行、保存/重启/重置。
    @ViewBuilder
    private var settingsSection: some View {
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
    }

    /// 第二页：数据库里那些东西——外部工作目录、缺口与补录、库内房间、采集回执。
    @ViewBuilder
    private var informationSpaceSection: some View {
        // MARK: - Information Space
        sectionBox("Information Space（数据库）") {
            VStack(alignment: .leading, spacing: 10) {
                workRootsPanel
                if !envMessage.isEmpty {
                    Text(envMessage).font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                // 两个入口两种活，别混：
                //   信息采集 = 入口，人指定一个目录，把里面的会话**搬进来**，
                //     同时把这个目录记成时间回填的源（同一份数据，不选两次）；
                //   状态刷新 = 收口，只数缺口；数完才露缺口那一行，缺的人
                //     才按得动「开始」——这就是「看到缺，点一下补」。
                // 没有对应动作的数字不放这里（对象数、未寻址、损坏数去问代理）。
                HStack(spacing: 10) {
                    Button("状态刷新") {
                        gapsRevealed = true
                        refreshGapCounts()
                    }
                    .help("数一遍缺口：轮账、时间、摘要、关键词各缺多少")
                    Button("信息采集…") { collectFromDirectory() }
                        .disabled(collectionBusy || informationSpaceBusy)
                        .help("选一个导出目录：会话搬进来，同时记作时间回填的来源目录")
                    if collectionBusy || informationSpaceBusy {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                }
                // 缺口在按钮下面出现，右边接着长开始/停止——顺序是
                // 先看见缺多少，再决定动不动手；补完自己收回去。
                if gapsRevealed {
                    gapLine
                    spaceRetryLine
                }
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
    }

    /// 仓库地址。发版页只给身份与去处，不抄一份会过期的说明。
    private static let repoURL = URL(string: "https://github.com/slamfinger/SimiGo")!

    /// 第三页：版本。版本号从 bundle 实读（见 versionFooter），不写死；
    /// 变更记录与许可不内嵌，链到仓库——抄进应用里的说明一定会落后于仓库。
    @ViewBuilder
    private var versionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Self.versionFooter)
                .font(.title3.monospaced())
                .textSelection(.enabled)
            Text("本地推理 + 信息空间。库只存，判断在模型这边。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Link(destination: Self.repoURL) {
                Label("github.com/slamfinger/SimiGo", systemImage: "link")
                    .font(.caption)
            }
            HStack(spacing: 12) {
                Link("变更记录", destination: Self.repoURL.appendingPathComponent("tree/main/docs/releases"))
                Link("许可", destination: Self.repoURL.appendingPathComponent("blob/main/LICENSE"))
                Link("第三方声明", destination: Self.repoURL.appendingPathComponent("blob/main/THIRD_PARTY_NOTICES.md"))
                Link("安全报告", destination: Self.repoURL.appendingPathComponent("blob/main/SECURITY.md"))
            }
            .font(.caption2)

            Divider()

            Text("升级影响：数据库只做前向迁移（当前 schema 36，旧库就地升级、不回退）；"
                + "覆盖安装会清掉首次运行标记，重走一遍首启向导。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("build 号是候选版序号，不是发版信号；装上不等于发布。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 缺口就一行：轮账几个会话、时间几轮、摘要几轮、关键词几轮；右边是开始/停止。
    /// 开始只在「还有缺口」时露面，停止只在「正跑着」时露面——补完了两个一起消失，
    /// 不用人盯着看哪一步该点了。
    private var gapLine: some View {
        HStack(spacing: 10) {
            if let gaps {
                Text("缺口：轮账 \(gaps.ledgerSessions) 个会话 · 时间 \(gaps.times) 轮 · "
                    + "摘要 \(gaps.digests) 轮 · 关键词 \(gaps.keywords) 轮 · "
                    + "房间 \(gaps.rooms) 轮")
                    .font(.caption2)
                    .foregroundStyle(gaps.total == 0 ? .secondary : .primary)
            } else {
                Text("正在数缺口…").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if informationSpaceBusy {
                Button("停止") { repairStop.cancel() }
                    .help("停止补录：当前数据库步骤完成后停止；模型生成期间会取消当前请求")
            } else if (gaps?.total ?? 0) > 0 {
                Button("开始") { runRepair() }
            }
        }
    }

    /// 数缺口。四个 COUNT，不碰对象字节——快，所以能在每次补录后重数。
    private func refreshGapCounts() {
        Task.detached(priority: .utility) {
            var counts: ESISDatabase.TurnGapCounts?
            var retry: ESISDatabase.SpaceAssignmentRetryStatus?
            do {
                let db = try ESISDatabase(
                    url: ManagedPaths.databaseURL, createIfNeeded: true)
                defer { db.close() }
                counts = try db.turnGapCounts()
                retry = try db.spaceAssignmentRetryStatus()
            } catch {
                NSLog("[gaps] 数缺口失败：\(error)")
            }
            await MainActor.run {
                if let counts { gaps = counts }
                spaceRetry = retry
            }
        }
    }

    /// 归属重试队列那一行（#187 审核 2026-11-13）：待办、已放弃、最近一次为什么
    /// 失败，右边一个「重放」。放弃的轮不会再自己动——没有这个入口，它们只能等
    /// 下一次全量重建，而重建没人保证会发生。
    @ViewBuilder private var spaceRetryLine: some View {
        let pending = spaceRetry?.pending ?? 0
        let rooms = gaps?.rooms ?? 0
        let abandoned = spaceRetry?.abandoned ?? 0
        if pending > 0 || rooms > 0 {
            HStack(spacing: 8) {
                Text("归属缺口：\(rooms) 轮 · 重试队列 \(pending) 轮"
                    + (abandoned > 0 ? " · 已放弃 \(abandoned) 轮" : ""))
                    .font(.caption2)
                    .foregroundStyle(abandoned > 0 || rooms > 0 ? .primary : .secondary)
                if let last = spaceRetry?.lastError, !last.isEmpty {
                    Text(last)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("重放") { replaySpaceAssignments() }
                    .disabled(informationSpaceBusy)
                    .help("把未归属摘要补入队列，并重新尝试待办与已放弃的归属；不碰模型")
            }
        }
    }

    /// 人按「重放」：先把放弃的轮重新武装（次数归零、退避清掉），再重放一遍。
    private func replaySpaceAssignments() {
        Task.detached(priority: .utility) {
            do {
                let db = try ESISDatabase(
                    url: ManagedPaths.databaseURL, createIfNeeded: true)
                defer { db.close() }
                // 先把「有摘要、没归属、又不在队列里」的轮捞进队列——工具补的
                // 摘要、丢过的一行都在这一类里，只重放队列补不到它们。
                let added = try db.enqueueDigestsWithoutRoom()
                let armed = try db.resetSpaceAssignmentRetries()
                let report = try db.retryPendingSpaceAssignments()
                NSLog("[spaces] 手动重放：补入队 \(added)，重新武装 \(armed)，"
                      + "试 \(report.retried)，"
                      + "成 \(report.succeeded)，仍失败 \(report.stillPending)，"
                      + "没到时间 \(report.deferred)")
            } catch {
                NSLog("[spaces] 手动重放失败：\(error)")
            }
            await MainActor.run {
                // 还没到点的行要靠监视器叫醒；它可能已经因队列清空停表了。
                TurnDigestScheduler.startRoomAssignmentRetryMonitor()
                refreshGapCounts()
            }
        }
    }

    /// 补录一次跑完，四步加一个收尾，不让人点下一步：
    ///
    /// 1 轮账（补采）→ 2 时间 → 3 摘要 → 4 关键词 → 收尾：房间归属。
    /// 前三步是后一步的输入（没账就没轮、没摘要就没词、没词就没房间）。
    /// 全部由本机大模型与本地库按序跑完；人只做两件事：开始、停止。
    ///
    /// 房间放最后而不是算第五步：它不吃缺口（是重算），而且采集完成时也要
    /// 单独跑一次——新进来的轮次必须当场认识路。
    private func runRepair() {
        guard !informationSpaceBusy else { return }
        informationSpaceBusy = true
        // 上一轮的报告还挂着就先收掉：这一轮从哪开始，面板上就该只有这一轮的进度。
        transientToken += 1
        informationSpaceStatus = ""
        repairStop.reset()
        let stop = repairStop
        let exportDir = Self.sourceTimeExportDirectory
        digestProgress = "1/4：补轮账"

        Task.detached(priority: .utility) {
            var lines: [String] = []
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

            // 1 轮账。若任务启动后立刻按停止，不再开启数据库工作。
            if !stop.isCancelled {
                act { db in
                    let r = try db.backfillImportedTurnLedger()
                    return "轮账：导入 \(r.importedTurnsTotal) 轮（本次补 \(r.turnsInserted)，"
                        + "保留 \(r.sessionsKept) 个会话原轮号）"
                }
            }

            // 2 时间
            if !stop.isCancelled {
                await MainActor.run { digestProgress = "2/4：补时间" }
                act { db in
                    let r = try db.backfillSourceTimes(
                        deepseekJSON: exportDir.flatMap(Self.deepseekExportFile),
                        aistudioDirectories: exportDir.map(Self.exportSubdirectories) ?? [])
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
            }

            // 3 摘要
            if !stop.isCancelled {
                await MainActor.run { digestProgress = "3/4：补摘要" }
                let result = await TurnDigestScheduler.fillMissing(
                    stop: stop
                ) { done, total in
                    Task { @MainActor in digestProgress = "补摘要 \(done)/\(total)" }
                }
                lines.append(receiptLine(title: "摘要", result: result))
            }

            // 4 关键词
            if !stop.isCancelled {
                await MainActor.run { digestProgress = "4/4：补关键词" }
                let result = await TurnDigestScheduler.repairKeywords(
                    stop: stop
                ) { done, total in
                    Task { @MainActor in digestProgress = "补关键词 \(done)/\(total)" }
                }
                lines.append(receiptLine(title: "关键词", result: result))
            }

            // 收尾：房间归属。词补完了才判得准。
            if !stop.isCancelled {
                await MainActor.run { digestProgress = "收尾：补房间" }
                act { db in
                    let r = try db.assignTurnSpaces()
                    return "房间：\(r.rowsWritten) 行归属（关键词命中 \(r.keywordHits) 轮）"
                }
                await MainActor.run { refreshRooms() }
            }
            await finish(lines, stop: stop.isCancelled)
        }
    }

    /// 补录回执的一行（#189）：成败数字之后跟失败明细——每轮失败都有名字
    /// （格式不合 / HTTP / 写库），让位与停止不是失败、单独说。明细截前 8 条，
    /// 全量留在缺口账上，回执是给人看的，不是给人翻的。
    private func receiptLine(title: String, result: DigestRepairReceipt) -> String {
        var text = "\(title)：成 \(result.done) 轮，败 \(result.failed) 轮"
        if result.yielded > 0 { text += "，让位 \(result.yielded) 次" }
        if let stoppedAt = result.stoppedAt { text += "，停止于 \(stoppedAt)" }
        var lines = [text]
        for failure in result.failures.prefix(8) {
            lines.append("　· \(failure.key)：\(failure.reason)")
        }
        if result.failures.count > 8 {
            lines.append("　· …另有 \(result.failures.count - 8) 条失败明细")
        }
        return lines.joined(separator: "\n")
    }

    /// 一次补录的出口。停止与走完共用：留下的账一样，差别只在开头那句。
    /// 出口处重数缺口——补了多少是过程，还剩多少才是判断。
    ///
    /// 这两行说的是「刚才发生了什么」，不是当前状态——当前状态是缺口、房间、
    /// 服务那几行。所以它们自己会收：进度行 3 秒，报告留 10 秒给人看一眼。
    /// 不自动收的话，它就一直挂到关窗重开。
    @MainActor
    private func finish(_ lines: [String], stop: Bool) {
        informationSpaceStatus = (stop ? "已停止。这一段留下的是：\n" : "补录完成：\n")
            + (lines.isEmpty ? "没有可补的" : lines.joined(separator: "\n"))
        digestProgress = stop ? "已停止" : "补录完成"
        informationSpaceBusy = false
        refreshRooms()
        refreshGapCounts()
        transientToken += 1
        let token = transientToken
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard transientToken == token, !informationSpaceBusy else { return }
            digestProgress = ""
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            guard transientToken == token, !informationSpaceBusy else { return }
            informationSpaceStatus = ""
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
