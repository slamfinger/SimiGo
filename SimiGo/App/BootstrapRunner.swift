import Darwin
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
enum BootstrapRunner {
    @discardableResult
    static func launchIfNeeded(
        storeURL: URL = ExecutionStateGraphStore.defaultStoreURL(),
        dbURL: URL = ManagedPaths.databaseURL,
        launchedAt: Date = Date(),
        reportURL: URL = ManagedPaths.manifests.appendingPathComponent("bootstrap-report.json")
    ) -> BootstrapReport? {
        do {
            let db = try ESISDatabase(url: dbURL)
            let legacy: Data?
            do {
                legacy = try Self.loadLegacyGraph(at: storeURL)
            } catch let preflightError {
                do {
                    _ = try Bootstrap.writePreflightFailureReport(
                        stepID: "load-legacy-graph",
                        error: preflightError,
                        schemaVersion: (try? db.schemaVersion()) ?? 0,
                        reportURL: reportURL,
                        startedAt: launchedAt)
                } catch let reportError {
                    Service.log(
                        "SimiGo bootstrap failure report could not be written: \(reportError)",
                        level: .error)
                }
                throw preflightError
            }
            let report = Bootstrap.run(
                db: db, legacyJSON: legacy, reportURL: reportURL,
                launchedAt: launchedAt)
            Service.log("SimiGo bootstrap: issueCount=\(report.issueCount) models=\(report.modelsDiscovered) work=\(report.workFilesIndexed) legacyMigrated=\(report.legacyMigrated)")
            return report
        } catch {
            // Fail closed: an unwritable / corrupt authority is surfaced, never overwritten.
            Service.log("SimiGo bootstrap skipped (fail-closed): \(error)", level: .error)
            return nil
        }
    }

    /// A missing legacy graph is optional; an existing but unreadable one is not.
    /// Do not let an I/O failure masquerade as "nothing to migrate".
    static func loadLegacyGraph(at url: URL) throws -> Data? {
        var metadata = stat()
        let result = url.path.withCString { Darwin.lstat($0, &metadata) }
        guard result == 0 else {
            let code = errno
            if code == ENOENT { return nil }
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(code),
                userInfo: [NSLocalizedDescriptionKey:
                    "cannot inspect legacy execution-state graph at \(url.path)"])
        }
        return try Data(contentsOf: url)
    }
}
