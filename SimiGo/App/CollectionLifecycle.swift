import Combine
import Foundation
import SimiGoCollection

/// 采集桥：**一次性**把用户选定目录里已有的 Qoder 会话导入 Information Space。
///
/// 它不是常驻监控。选目录后扫到不再读出字节就结束，释放 state lease；
/// 之后的新会话由 agent 自己走 MCP（`simigo_es_begin` / `es_settle`）进 IS，
/// 不靠这里持续 tail。
///
/// 落库走 `ExternalTurnSink`（IS 外部轮次合同）。交付是 at-least-once，
/// 幂等键是候选的源身份，所以重跑同一次导入不会追加行。
@MainActor
final class CollectionLifecycle: ObservableObject {
    static let shared = CollectionLifecycle()

    enum Phase: Equatable {
        case idle
        case importing
        case finished(turns: Int, files: Int, undelivered: Int, at: Date)
        case failed(String)
    }

    /// 单次导入的 poll 上限。每次 poll 最多读 `maxBytesPerPoll`（4 MiB），
    /// 所以这个上限只用来兜住「文件在扫描期间持续增长」时的空转。
    private static let maxPolls = 1000

    @Published private(set) var phase: Phase = .idle
    /// 有导入记录（用户选过目录并跑过一次）。菜单与设置行据此显示。
    @Published private(set) var isEnabled: Bool

    var isRunning: Bool { phase == .importing }

    var scanRootPath: String {
        AppConfig.qoderScanRootPath ?? Self.defaultScanRoot.path
    }

    var statusText: String {
        switch phase {
        case .idle:
            return ""
        case .importing:
            return "导入中…"
        case .finished(let turns, let files, let undelivered, _):
            var text = "已导入 \(turns) 轮（\(files) 个文件）"
            if undelivered > 0 { text += "，未投递 \(undelivered)" }
            return text
        case .failed(let reason):
            return "导入失败：\(reason)"
        }
    }

    /// Qoder 自己的默认 transcript 根。用户没选过目录时用它。
    static let defaultScanRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".qoder-cn/projects", isDirectory: true)

    private var runner: CollectionRunner?
    private let cancellation = ImportCancellation()

    private init() {
        isEnabled = AppConfig.qoderCollectionEnabled
    }

    /// 选目录：只记下来。真正导入由 `setEnabled(true)` 触发，这样面板取消时
    /// 不改动任何状态。传 nil 回到 Qoder 默认根。
    func setScanRoot(_ url: URL?) {
        guard let url else {
            AppConfig.qoderScanRootPath = nil
            return
        }
        var isDirectory: ObjCBool = false
        guard
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { return }
        AppConfig.qoderScanRootPath = url.standardizedFileURL.path
    }

    /// `true` 触发一次导入，`false` 取消正在进行的导入。语义是「跑一次」，
    /// 不是「开启监控」——导入完成后 `isEnabled` 仍为真，只表示跑过。
    func setEnabled(_ enabled: Bool) {
        if enabled {
            beginImport()
        } else {
            cancelImport()
        }
    }

    /// 进程退出时释放 lease。导入是幂等的，中断后重跑从持久游标继续。
    func stop() {
        cancellation.cancel()
        runner?.stop()
        runner = nil
        if phase == .importing { phase = .idle }
    }

    private func cancelImport() {
        stop()
    }

    private func beginImport() {
        guard runner == nil else { return }
        AppConfig.qoderCollectionEnabled = true
        isEnabled = true
        phase = .importing

        let sink = ExternalTurnSink()
        let collector = CollectionRunner(
            configuration: Self.configuration(),
            sink: { batch in try sink.deliver(batch) },
            onError: { message in
                NSLog("SimiGo Qoder collection: %@", message)
            })
        runner = collector
        cancellation.reset()

        let cancellation = self.cancellation
        let maxPolls = Self.maxPolls
        DispatchQueue.global(qos: .utility).async {
            var files = 0
            var turns = 0
            var failure: String?
            for _ in 0..<maxPolls {
                if cancellation.isCancelled { break }
                let report = collector.pollOnce()
                files = max(files, report.scannedFiles)
                turns += report.persistedCandidates
                if let first = report.errors.first {
                    failure = first
                    break
                }
                // 这一遍没有读出任何字节：目录里已有的内容已经读完。
                if report.readBytes == 0 { break }
            }
            let undelivered = collector.statusSnapshot.pendingCount ?? 0
            collector.stop()
            Task { @MainActor in
                CollectionLifecycle.shared.finish(
                    turns: turns, files: files, undelivered: undelivered,
                    failure: failure)
            }
        }
    }

    private func finish(turns: Int, files: Int, undelivered: Int, failure: String?) {
        runner = nil
        // 用户在这次导入结束前点了「停止」：不把取消覆盖成完成。
        guard phase == .importing else { return }
        phase = failure.map { .failed($0) }
            ?? .finished(turns: turns, files: files, undelivered: undelivered, at: Date())
    }

    /// 标准配置（环境变量校验语义原样保留），只把扫描根换成用户选定的目录。
    private static func configuration() -> CollectionConfiguration {
        let base = CollectionConfiguration.standard()
        // 采集桥的语义：开了就把这个目录**已有的**会话读进来，不只是之后的
        // 新增。目录由用户在目录面板里选，选谁采谁。
        let policy: BaselinePolicy = .readExisting
        guard let override = AppConfig.qoderScanRootPath else {
            return CollectionConfiguration(
                scanRoot: base.scanRoot,
                stateDirectory: base.stateDirectory,
                pollInterval: base.pollInterval,
                baselinePolicy: policy,
                configurationError: base.configurationError)
        }
        return CollectionConfiguration(
            scanRoot: URL(fileURLWithPath: override, isDirectory: true),
            stateDirectory: base.stateDirectory,
            pollInterval: base.pollInterval,
            baselinePolicy: policy,
            configurationError: base.configurationError)
    }
}

/// 导入循环跑在全局队列上，取消由主线程置位：只保护一个 Bool。
private final class ImportCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }

    func cancel() {
        lock.lock()
        flag = true
        lock.unlock()
    }

    func reset() {
        lock.lock()
        flag = false
        lock.unlock()
    }
}
