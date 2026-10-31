import Foundation

public struct QoderCollectionConfiguration: Sendable {
    /// Qoder's own transcript root. Never written to; scanned read-only.
    public let scanRoot: URL
    /// Where this collector keeps its durable inbox: candidates and the read
    /// position in one SQLite database. Inside the managed root and never
    /// inside the Qoder tree.
    public let stateDirectory: URL
    public let pollInterval: TimeInterval
    /// Invalid explicit environment configuration. The runner refuses to
    /// acquire a lease or create state while this value is non-nil.
    public let configurationError: String?

    public init(
        scanRoot: URL, stateDirectory: URL, pollInterval: TimeInterval = 2.0,
        configurationError: String? = nil
    ) {
        self.scanRoot = scanRoot
        self.stateDirectory = stateDirectory
        self.pollInterval = pollInterval
        self.configurationError = configurationError
    }

    /// Uses the Qoder default only when QODER_PROJECTS_DIR is unset. An
    /// explicitly supplied empty, relative, or existing non-directory path is
    /// a configuration error; silently falling back could scan real user data.
    /// The same rule applies to SIMIGO_HOME because it controls write placement.
    public static func standard(
        env: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> QoderCollectionConfiguration {
        let defaultScanRoot = homeDirectory.appendingPathComponent(
            ".qoder-cn/projects", isDirectory: true)
        let scan = directoryOverride(
            key: "QODER_PROJECTS_DIR", env: env, fallback: defaultScanRoot)

        let defaultManagedRoot = homeDirectory.appendingPathComponent(
            ".simigo", isDirectory: true)
        let managed = directoryOverride(
            key: "SIMIGO_HOME", env: env, fallback: defaultManagedRoot)

        let errors = [scan.error, managed.error].compactMap { $0 }
        return QoderCollectionConfiguration(
            scanRoot: scan.url,
            stateDirectory: managed.url.appendingPathComponent(
                "collectors/qoder", isDirectory: true),
            configurationError: errors.isEmpty ? nil : errors.joined(separator: "; "))
    }

    private static func directoryOverride(
        key: String, env: [String: String], fallback: URL
    ) -> (url: URL, error: String?) {
        guard let raw = env[key] else { return (fallback, nil) }
        guard !raw.isEmpty else {
            return (fallback, "\(key) is explicitly set but empty")
        }
        guard (raw as NSString).isAbsolutePath else {
            return (fallback, "\(key) must be an absolute path")
        }

        let url = URL(fileURLWithPath: raw, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           !isDirectory.boolValue {
            return (fallback, "\(key) points to an existing non-directory path: \(url.path)")
        }
        return (url, nil)
    }
}
/// A read-only snapshot of the collector's process-local operational state.
public struct QoderCollectionStatus: Sendable, Equatable {
    public let isRunning: Bool
    public let unavailableReason: String?
    /// Nil when the state directory is not owned or cannot be read.
    public let pendingCount: Int?
    /// Time the configured sink last accepted a delivery in this process.
    /// This is an operational observation, not a settlement record.
    public let lastDeliveryAt: Date?
    /// Time a poll, delivery, or status read last reported an error.
    public let lastFailureAt: Date?
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
///
/// One runner owns the state directory at a time through an exclusive lease, so
/// a second instance cannot commit an older cursor snapshot over a newer one.
public final class QoderCollectionRunner {
    /// Receives durably committed candidates. The pair of `key` and `event`
    /// makes every delivery identifiable, so an accepted-but-not-marked crash
    /// redelivers under the same key instead of forcing consumers to re-derive
    /// identity from the event.
    public typealias Sink = ([QoderCandidateDelivery]) throws -> Void

    public let configuration: QoderCollectionConfiguration

    private let sink: Sink?
    private let inbox: QoderCandidateInbox
    private let onError: ((String) -> Void)?
    private let queue = DispatchQueue(label: "com.simigo.collection.qoder")
    private let queueKey = DispatchSpecificKey<Bool>()
    private var timer: DispatchSourceTimer?
    private var lease: QoderCollectionLease?
    private var tailer: QoderTranscriptTailer?
    private var failure: String?
    private var lastDeliveryAt: Date?
    private var lastFailureAt: Date?

    private init(
        configuration: QoderCollectionConfiguration,
        sink: Sink?,
        onError: ((String) -> Void)?
    ) {
        self.configuration = configuration
        self.sink = sink
        self.inbox = QoderCandidateInbox(
            directoryURL: configuration.stateDirectory)
        self.onError = onError
        queue.setSpecific(key: queueKey, value: true)
    }

    /// Delivery-enabled initializer. The sink is called only after candidates
    /// and their cursor have committed to the durable inbox.
    public convenience init(
        configuration: QoderCollectionConfiguration,
        sink: @escaping Sink,
        onError: ((String) -> Void)? = nil
    ) {
        self.init(configuration: configuration, sink: Optional(sink), onError: onError)
    }

    /// Collection-only mode. Candidates remain pending in the durable inbox;
    /// no delivery or information-space write is implied.
    public convenience init(
        configuration: QoderCollectionConfiguration,
        onError: ((String) -> Void)? = nil
    ) {
        self.init(configuration: configuration, sink: nil, onError: onError)
    }

    public var isRunning: Bool {
        onQueue { timer != nil && failure == nil }
    }

    /// Non-nil while state cannot be used. Unreadable or damaged state is
    /// recovered through `quarantineState()`; a directory owned by another
    /// runner needs that owner to stop or exit first.
    public var unavailableReason: String? {
        onQueue { failure ?? configuration.configurationError }
    }

    /// Captures operational status on the runner's serial queue. A missing
    /// count means the state directory is not owned or could not be read.
    public var statusSnapshot: QoderCollectionStatus {
        onQueue {
            var pending: Int?
            var reason = failure ?? configuration.configurationError
            if lease != nil {
                do {
                    pending = try inbox.pendingCount()
                } catch {
                    reason = reason ?? String(describing: error)
                    lastFailureAt = Date()
                }
            }
            return QoderCollectionStatus(
                isRunning: timer != nil && reason == nil,
                unavailableReason: reason,
                pendingCount: pending,
                lastDeliveryAt: lastDeliveryAt,
                lastFailureAt: lastFailureAt)
        }
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

    /// Stops polling and gives up the state lease so another runner (or this
    /// one, restarted) can take it. In-memory turn state is dropped; the next
    /// start replays the open turn from the durable cursor.
    public func stop() {
        onQueue {
            timer?.setEventHandler {}
            timer?.cancel()
            timer = nil
            tailer = nil
            lease = nil
        }
    }

    @discardableResult
    public func pollOnce() -> QoderPollReport {
        onQueue { pollLocked() }
    }

    /// Moves unusable state aside and clears the failure so the next poll
    /// starts fresh. Existing transcripts are then baselined at EOF, which is
    /// a deliberate loss of anything not yet durably recorded. Only the runner
    /// that owns the state directory may do this.
    @discardableResult
    public func quarantineState() -> URL? {
        onQueue {
            guard lease != nil else {
                onError?(
                    "state quarantine requires ownership of "
                        + configuration.stateDirectory.path)
                return nil
            }
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
            lastFailureAt = Date()
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
        if !report.errors.isEmpty { lastFailureAt = Date() }
        for error in report.errors { onError?(error) }
        return report
    }

    private func ensureReadyLocked() -> Bool {
        if failure != nil { return false }
        if let configurationError = configuration.configurationError {
            failure = configurationError
            lastFailureAt = Date()
            onError?("collection unavailable: \(configurationError)")
            return false
        }
        if tailer != nil { return true }
        do {
            if lease == nil {
                lease = try QoderCollectionLease.acquire(
                    directoryURL: configuration.stateDirectory)
            }
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
            lastFailureAt = Date()
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
            lastFailureAt = Date()
            onError?("collection unavailable: \(failure ?? "unknown error")")
        }
    }

    private func drainLocked(_ report: inout QoderPollReport) {
        // Collection-only mode intentionally retains every candidate as
        // pending. A no-op sink would falsely mark data delivered.
        guard let sink else { return }
        do {
            while true {
                let batch = try inbox.pendingCandidates(limit: 128)
                if batch.isEmpty { return }
                var accepted: [String] = []
                for candidate in batch {
                    do {
                        try sink([candidate.delivery])
                        lastDeliveryAt = Date()
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
            let reason = String(describing: error)
            report.errors.append("candidate delivery failed: \(reason)")
            lastFailureAt = Date()
            if case QoderCollectionStateError.corruptState = error {
                // Corrupt durable payload is not a transient sink failure.
                // Stop further collection until explicit quarantine/recovery.
                failure = reason
                tailer = nil
            }
        }
    }

    private func onQueue<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) == true {
            return body()
        }
        return queue.sync(execute: body)
    }
}
