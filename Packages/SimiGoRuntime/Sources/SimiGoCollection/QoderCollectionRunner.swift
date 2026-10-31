import Foundation

public struct QoderCollectionConfiguration: Sendable {
    /// Qoder's own transcript root. Never written to; scanned read-only.
    public let scanRoot: URL
    /// Where this collector keeps its cursor. Inside the managed root, never
    /// inside the Qoder tree.
    public let stateDirectory: URL
    public let pollInterval: TimeInterval

    public init(scanRoot: URL, stateDirectory: URL, pollInterval: TimeInterval = 2.0) {
        self.scanRoot = scanRoot
        self.stateDirectory = stateDirectory
        self.pollInterval = pollInterval
    }

    /// `~/.qoder-cn/projects` and `<SIMIGO_HOME or ~/.simigo>/collectors/qoder`.
    /// The managed root is resolved here rather than imported from the runtime
    /// contract so this target stays dependency-free.
    public static func standard(
        env: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> QoderCollectionConfiguration {
        let scanRoot: URL
        if let override = env["QODER_PROJECTS_DIR"], !override.isEmpty {
            scanRoot = URL(
                fileURLWithPath: (override as NSString).standardizingPath,
                isDirectory: true)
        } else {
            scanRoot = homeDirectory.appendingPathComponent(
                ".qoder-cn/projects", isDirectory: true)
        }
        let managedRoot: URL
        if let override = env["SIMIGO_HOME"], !override.isEmpty {
            managedRoot = URL(
                fileURLWithPath: (override as NSString).standardizingPath,
                isDirectory: true)
        } else {
            managedRoot = homeDirectory.appendingPathComponent(
                ".simigo", isDirectory: true)
        }
        return QoderCollectionConfiguration(
            scanRoot: scanRoot,
            stateDirectory: managedRoot.appendingPathComponent(
                "collectors/qoder", isDirectory: true))
    }
}

/// Timer-driven host for `QoderTranscriptTailer`. All work, including the
/// sink, runs on one serial queue; a poll never overlaps another poll.
public final class QoderCollectionRunner {
    public typealias Sink = QoderTranscriptTailer.Sink

    public let configuration: QoderCollectionConfiguration

    private let sink: Sink
    private let store: QoderCursorStoring
    private let onError: ((String) -> Void)?
    private let queue = DispatchQueue(label: "com.simigo.collection.qoder")
    private let queueKey = DispatchSpecificKey<Bool>()
    private var timer: DispatchSourceTimer?
    private var tailer: QoderTranscriptTailer?
    private var needsInitialSave = false

    public init(
        configuration: QoderCollectionConfiguration,
        sink: @escaping Sink,
        store: QoderCursorStoring? = nil,
        onError: ((String) -> Void)? = nil
    ) {
        self.configuration = configuration
        self.sink = sink
        self.store = store ?? QoderFileCursorStore(
            directoryURL: configuration.stateDirectory)
        self.onError = onError
        queue.setSpecific(key: queueKey, value: true)
    }

    public var isRunning: Bool {
        onQueue { timer != nil }
    }

    public func start() {
        onQueue {
            guard timer == nil else { return }
            ensureTailer()
            persistIfNeeded()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(
                deadline: .now(), repeating: configuration.pollInterval,
                leeway: .milliseconds(250))
            timer.setEventHandler { [weak self] in _ = self?.pollLocked() }
            self.timer = timer
            timer.resume()
        }
    }

    public func stop() {
        onQueue {
            timer?.setEventHandler {}
            timer?.cancel()
            timer = nil
        }
    }

    @discardableResult
    public func pollOnce() -> QoderPollReport {
        onQueue { pollLocked() }
    }

    private func pollLocked() -> QoderPollReport {
        ensureTailer()
        guard let tailer else { return QoderPollReport() }
        let report = tailer.poll(sink: sink)
        for error in report.errors {
            onError?(error)
        }
        if report.stateChanged || needsInitialSave {
            persistIfNeeded()
        }
        return report
    }

    private func ensureTailer() {
        guard tailer == nil else { return }
        let loaded = store.load()
        needsInitialSave = loaded == nil
        tailer = QoderTranscriptTailer(
            scanRoot: configuration.scanRoot,
            state: loaded)
    }

    private func persistIfNeeded() {
        guard let tailer else { return }
        do {
            try store.save(tailer.cursorState)
            needsInitialSave = false
        } catch {
            onError?("cursor save failed: \(error)")
        }
    }

    private func onQueue<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) == true {
            return body()
        }
        return queue.sync(execute: body)
    }
}
