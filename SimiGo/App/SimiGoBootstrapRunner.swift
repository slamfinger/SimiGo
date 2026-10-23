import Foundation
import SimiGoRuntimeContract

/// Launch-time autonomous bootstrap.
///
/// Idempotent and resumable — safe to run on EVERY app launch: completed steps
/// stay completed, a previously failed step is simply retried, and no prior data
/// is ever destroyed. It opens the authoritative SQLite ES/IS store, runs schema
/// migrations, transactionally imports any pre-existing JSON reference graph,
/// discovers external Hugging Face models, indexes declared work roots, and emits
/// a machine-readable `bootstrap-report.json`. Failures are recorded in the report
/// and logged; bootstrap is never fatal to startup.
enum SimiGoBootstrapRunner {
    @discardableResult
    static func launchIfNeeded(
        storeURL: URL = ExecutionStateGraphStore.defaultStoreURL(),
        dbURL: URL = SimiGoPaths.databaseURL
    ) -> BootstrapReport? {
        let fm = FileManager.default
        do {
            let db = try SimiGoESISDatabase(url: dbURL)
            let legacy: Data? = fm.fileExists(atPath: storeURL.path)
                ? (try? Data(contentsOf: storeURL))
                : nil
            let report = SimiGoBootstrap.run(db: db, legacyJSON: legacy)
            NSLog("SimiGo bootstrap: issueCount=\(report.issueCount) models=\(report.modelsDiscovered) work=\(report.workFilesIndexed) legacyMigrated=\(report.legacyMigrated)")
            return report
        } catch {
            // Fail closed: an unwritable / corrupt authority is surfaced, never overwritten.
            NSLog("SimiGo bootstrap skipped (fail-closed): \(error)")
            return nil
        }
    }
}
