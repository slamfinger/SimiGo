import Foundation
import SimiGoRuntimeContract

/// 运行期状态的结构化外发面（2026-11-06）。
///
/// 为什么需要它：`native_mlx_trace.log` 是给人看、给事后审计用的**证据流**。
/// 一旦有代码去解析它做判断（例如 bench 开跑前的“有没有在途生成”），就等于
/// 把副作用当状态机——日志格式一变、行被降噪、日志被轮转，判定就悄悄失效。
/// 跨进程消费者（`tools/*.py`、验收脚本）需要的是一份可判定的结构化快照，
/// 因此这里以原子写维护 `state/runtime.json`；进程内消费者直接读
/// `RuntimeLifecycleCoordinator.snapshot()`，连文件都不用碰。
///
/// 写策略：合并写（150 ms 去抖），永远写“最新一份”，不做追加——它是状态，不是流水。
nonisolated final class RuntimeStateReporter: @unchecked Sendable {
    static let shared = RuntimeStateReporter()

    private struct Payload {
        var lifecycle = LifecycleSnapshot(byState: [:], transitions: [:], registered: 0)
        var backend: String?
        var model: String?
        var enginePort: Int?
        var active: Int?
        var waiting: Int?
    }

    private static let debounce: DispatchTimeInterval = .milliseconds(150)

    private let queue = DispatchQueue(label: "com.simigo.state.reporter", qos: .utility)
    private var latest = Payload()
    private var writePending = false
    private let fileURL: URL

    private init() {
        // 与 trace 日志同在受管根下（`SIMIGO_HOME` 覆盖时一并重定向），
        // 但目录独立：logs/ 是人类可读流，state/ 是机器可读快照。
        self.fileURL = SimiGoPaths.managedRoot()
            .appendingPathComponent("state", isDirectory: true)
            .appendingPathComponent("runtime.json")
    }

    /// 生命周期快照变化（注册/迁移/收口）——由协调器推送。
    func report(_ snapshot: LifecycleSnapshot) {
        queue.async { [self] in
            latest.lifecycle = snapshot
            scheduleWriteLocked()
        }
    }

    /// 准入窗口（并发槽位）变化——由协议层推送。
    func setAdmission(active: Int, waiting: Int) {
        queue.async { [self] in
            latest.active = active
            latest.waiting = waiting
            scheduleWriteLocked()
        }
    }

    /// 后端身份。引擎内部端口只在这里出现，不从日志里反推。
    func setContext(backend: String?, model: String?, enginePort: Int?) {
        queue.async { [self] in
            latest.backend = backend
            latest.model = model
            latest.enginePort = enginePort
            scheduleWriteLocked()
        }
    }

    /// 停止后清空身份，保留“无在途”的事实，避免外部工具读到上一轮的端口。
    func clearContext() {
        setContext(backend: nil, model: nil, enginePort: nil)
    }

    /// 立即落盘（测试/退出路径用），绕过去抖。
    func flush() {
        queue.sync {
            writeLocked()
        }
    }

    private func scheduleWriteLocked() {
        guard !writePending else { return }
        writePending = true
        queue.asyncAfter(deadline: .now() + Self.debounce) { [self] in
            writePending = false
            writeLocked()
        }
    }

    private func writeLocked() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)

        let snapshot = latest.lifecycle
        var document: [String: Any] = [
            "schema": 1,
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
            "updated_at": Self.iso.string(from: Date()),
            "in_flight": snapshot.inFlight,
            "tracked": snapshot.byState.values.reduce(0, +),
            "registered": snapshot.registered,
            "by_state": snapshot.byState,
            "transitions": snapshot.transitions,
        ]
        if let backend = latest.backend { document["backend"] = backend }
        if let model = latest.model { document["model"] = model }
        if let enginePort = latest.enginePort { document["engine_port"] = enginePort }
        if let active = latest.active, let waiting = latest.waiting {
            document["admission"] = ["active": active, "waiting": waiting]
        }

        guard let data = try? JSONSerialization.data(
            withJSONObject: document, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return }
        // 原子写：读者永远看到完整的一份，不会读到半个 JSON。
        try? data.write(to: fileURL, options: .atomic)
    }

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
