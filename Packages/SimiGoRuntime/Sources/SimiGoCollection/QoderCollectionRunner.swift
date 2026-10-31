import Foundation

public struct QoderCollectionConfiguration: Sendable {
    /// Qoder's own transcript root. Never written to; scanned read-only.
    public let scanRoot: URL
    /// Where this collector keeps its durable inbox: candidates and the read
    /// position in one SQLite database. Inside the managed root and never
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

/// Timer-driven host for `QoderTranscriptTailer` and the durable inbox.
///
/// Poll order is read → commit candidates and cursor in one transaction →
/// deliver. A crash before the commit replays the same lines and the unique
/// candidate keys absorb the retry; a crash after it leaves a durable backlog
/// that the next drain delivers without re-reading the transcript. All work
/// runs on one serial queue and polls never overlap.
///
/// State that exists but cannot be read or decoded stops collection instead of
/// being replaced in place: re-baselining would silently skip transcripts
/// whose turns were never durably recorded. Recovery is explicit through
/// `quarantineState()`.
public final class QoderCollectionRunner {
    public typealias Sink = QoderTranscriptTailer.Sink

    public let configuration: QoderCollectionConfiguration

    private let sink: Sink
    private let inbox: QoderCandidateInbox
    private let onError: ((String) -> Void)?
    private let queue = DispatchQueue(label: "com.simigo.collection.qoder")
    private let queueKey = DispatchSpecificKey<Bool>()
    private var timer: DispatchSourceTimer?
    private var tailer: QoderTranscriptTailer?
    private var failure: String?

    public init(
        configuration: QoderCollectionConfiguration,
        sink: @escaping Sink,
        onError: ((String) -> Void)? = nil
    ) {
        self.configuration = configuration
        self.sink = sink
        self.inbox = QoderCandidateInbox(
            directoryURL: configuration.stateDirectory)
        self.onError = onError
        queue.setSpecific(key: queueKey, value: true)
    }

    public var isRunning: Bool {
        onQueue { timer != nil }
    }

    /// Non-nil while durable state is unusable; collection is stopped and
    /// `quarantineState()` is the only way back.
    public var unavailableReason: String? {
        onQueue { failure }
    }

    public func start() {
        onQueue {
            guard timer == nil else { return }
            guard ensureReadyLocked() else { return }
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

    /// Moves unusable state aside and clears the failure so the next poll
    /// starts fresh. Existing transcripts are then baselined at EOF, which is
    /// a deliberate loss of anything not yet durably recorded.
    @discardableResult
    public func quarantineState() -> URL? {
        onQueue {
            do {
                let destination = try inbox.quarantine()
                tailer = nil
                failure = nil
                return destination
            } catch {
                onError?("state quarantine failed: \(error)")
                return nil
            }
        }
    }

    private func pollLocked() -> QoderPollReport {
        var report = QoderPollReport()
        guard ensureReadyLocked() else {
            report.errors.append(failure ?? "collection state is unavailable")
            return report
        }
        guard let tailer else { return report }

        var staged: [QoderCollectionEvent] = []
        report = tailer.poll { staged.append(contentsOf: $0) }

        if report.stateChanged || !staged.isEmpty {
            do {
                let result = try inbox.commit(
                    events: staged, cursorState: tailer.cursorState)
                report.persistedCandidates = result.insertedCandidates
                report.duplicateCandidates = result.duplicateCandidates
            } catch {
                report.errors.append("durable commit failed: \(error)")
                reloadAfterCommitFailure()
                for error in report.errors { onError?(error) }
                return report
            }
        }

        drainLocked(&report)
        for error in report.errors { onError?(error) }
        return report
    }

    private func ensureReadyLocked() -> Bool {
        if failure != nil { return false }
        if tailer != nil { return true }
        do {
            let loaded = try inbox.loadCursorState()
            let created = QoderTranscriptTailer(
                scanRoot: configuration.scanRoot, state: loaded)
            if loaded == nil {
                // Freeze the initialization instant before the first scan so
                // files created later are read from their first byte.
                try inbox.commit(events: [], cursorState: created.cursorState)
            }
            tailer = created
            return true
        } catch {
            let reason = String(describing: error)
            failure = reason
            onError?("collection unavailable: \(reason)")
            return false
        }
    }

    /// The transaction rolled back, so the stored cursor is still the older
    /// one; rebuilding the tailer from it makes the next poll replay the same
    /// bytes, and the inbox key absorbs nothing because nothing committed.
    private func reloadAfterCommitFailure() {
        do {
            let loaded = try inbox.loadCursorState()
            if loaded == nil {
                tailer = nil
            } else {
                tailer = QoderTranscriptTailer(
                    scanRoot: configuration.scanRoot, state: loaded)
            }
        } catch {
            tailer = nil
            failure = String(describing: error)
            onError?("collection unavailable: \(failure ?? "unknown error")")
        }
    }

    private func drainLocked(_ report: inout QoderPollReport) {
        do {
            while true {
                let batch = try inbox.pendingCandidates(limit: 128)
                if batch.isEmpty { return }
                var accepted: [String] = []
                for candidate in batch {
                    do {
                        try sink([candidate.event])
                        accepted.append(candidate.key)
                    } catch {
                        report.errors.append(
                            "delivery failed for \(candidate.key): \(error)")
                        break
                    }
                }
                if !accepted.isEmpty {
                    try inbox.markDelivered(accepted)
                }
                report.deliveredCandidates += accepted.count
                if accepted.count < batch.count { return }
            }
        } catch {
            report.errors.append("candidate delivery failed: \(error)")
        }
    }

    private func onQueue<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) == true {
            return body()
        }
        return queue.sync(execute: body)
    }
}
