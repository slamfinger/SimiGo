import Combine
import Foundation
import SimiGoCollection

/// Owns the one Qoder collector for the normal GUI app lifetime.
/// The collector runs in collection-only mode: it commits source candidates
/// and cursors to its durable inbox but does not claim downstream delivery or
/// write to the Information Space.
@MainActor
final class QoderCollectionLifecycle: ObservableObject {
    static let shared = QoderCollectionLifecycle()

    @Published private(set) var snapshot: QoderCollectionStatus?

    private var runner: QoderCollectionRunner?
    private var refreshTimer: Timer?

    private init() {}

    func start() {
        guard runner == nil else { return }

        let collector = QoderCollectionRunner(
            configuration: QoderCollectionConfiguration.standard(),
            onError: { message in
                NSLog("SimiGo Qoder collection: %@", message)
            })
        runner = collector
        collector.start()
        refreshSnapshot()

        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: 2.0, repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshSnapshot()
            }
        }
    }

    /// Normal shutdown releases the lease. A crash does not depend on this
    /// callback: the OS closes the descriptor and the next process resumes
    /// from the inbox's durable cursor and pending candidates.
    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        runner?.stop()
        runner = nil
        snapshot = nil
    }

    private func refreshSnapshot() {
        snapshot = runner?.statusSnapshot
    }
}
