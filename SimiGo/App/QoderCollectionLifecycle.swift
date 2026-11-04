import Combine
import Foundation
import SimiGoCollection

/// Owns the optional Qoder collector for the normal GUI app lifetime.
///
/// Collection is off unless the operator enables it. The collector runs in
/// collection-only mode: it commits source candidates and cursors to its
/// durable inbox but does not claim downstream delivery or write to the
/// Information Space.
@MainActor
final class QoderCollectionLifecycle: ObservableObject {
    static let shared = QoderCollectionLifecycle()

    @Published private(set) var isEnabled: Bool
    @Published private(set) var snapshot: QoderCollectionStatus?

    var isRunning: Bool { snapshot?.isRunning == true }
    var pendingCount: Int? { snapshot?.pendingCount }
    var unavailableReason: String? { snapshot?.unavailableReason }

    private var runner: QoderCollectionRunner?
    private var refreshTimer: Timer?

    private init() {
        isEnabled = AppConfig.qoderCollectionEnabled
    }

    func setEnabled(_ enabled: Bool) {
        AppConfig.qoderCollectionEnabled = enabled
        isEnabled = enabled
        if enabled {
            start()
        } else {
            stop()
        }
    }

    /// Called on the GUI launch path only. A disabled preference starts
    /// nothing, and neither does an XCTest host: preferences are the real user
    /// defaults, so a test run must not inherit a live collector.
    func startIfEnabled() {
        guard isEnabled else { return }
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              NSClassFromString("XCTestCase") == nil
        else { return }
        start()
    }

    private func start() {
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
