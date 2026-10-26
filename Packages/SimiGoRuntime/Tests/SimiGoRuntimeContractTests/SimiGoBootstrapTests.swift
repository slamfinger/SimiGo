import SQLite3
import XCTest
@testable import SimiGoRuntimeContract

final class SimiGoBootstrapTests: XCTestCase {

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("boot-\(UUID().uuidString)-\(name)")
    }

    /// Out-of-band statement, used to simulate time passing between launches.
    private func rawExec(_ url: URL, _ sql: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            throw SimiGoESISDatabase.DatabaseError.cannotOpen(url.path)
        }
        defer { sqlite3_close(handle) }
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw SimiGoESISDatabase.DatabaseError.sql(
                String(cString: sqlite3_errmsg(handle)))
        }
    }

    private func makeFakeHFHub() -> (hub: URL, env: [String: String]) {
        let fm = FileManager.default
        let hub = tempURL("hub")
        let repo = hub.appendingPathComponent("models--Foo--Bar/snapshots/deadbeef", isDirectory: true)
        try? fm.createDirectory(at: repo, withIntermediateDirectories: true)
        let w = repo.appendingPathComponent("model.gguf")
        try? Data("x".utf8).write(to: w)
        return (hub, ["HF_HUB_CACHE": hub.path])
    }

    // MARK: discovery
    func testDiscoveryReadsHFStyleLayoutAsRootRelativeRefs() {
        let (hub, env) = makeFakeHFHub()
        defer { try? FileManager.default.removeItem(at: hub) }
        let found = SimiGoModelDiscovery.discover(env: env, hubs: [hub])
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.repoID, "Foo/Bar")
        XCTAssertEqual(found.first?.rootID, SimiGoModelDiscovery.cacheRootID)
        XCTAssertFalse(found.first!.relativePath.hasPrefix("/"), "relative path must not be absolute")
        XCTAssertTrue(found.first!.relativePath.hasSuffix("model.gguf"))
    }

    // MARK: bootstrap happy path + report
    func testBootstrapProducesMachineReadableReportAndIsIdempotent() throws {
        let fm = FileManager.default
        let dbURL = tempURL("db.sqlite3"); defer { try? fm.removeItem(at: dbURL) }
        let reportURL = tempURL("bootstrap-report.json"); defer { try? fm.removeItem(at: reportURL) }
        let (hub, env) = makeFakeHFHub(); defer { try? fm.removeItem(at: hub) }
        let work = tempURL("work"); try? fm.createDirectory(at: work, withIntermediateDirectories: true); defer { try? fm.removeItem(at: work) }
        try? Data("hello".utf8).write(to: work.appendingPathComponent("note.txt"))

        let db = try SimiGoESISDatabase(url: dbURL)
        let r1 = SimiGoBootstrap.run(db: db, env: env, fm: fm,
                                     workRoots: [(rootID: "work-1", url: work, category: "work")],
                                     modelHubs: [hub], reportURL: reportURL)
        XCTAssertEqual(r1.issueCount, 0, "healthy first run: \(r1.steps)")
        XCTAssertTrue(r1.ok)
        XCTAssertEqual(r1.modelsDiscovered, 1)
        XCTAssertGreaterThanOrEqual(r1.workFilesIndexed, 1)

        // report is decodable JSON on disk
        let data = try Data(contentsOf: reportURL)
        let decoded = try JSONDecoder().decode(BootstrapReport.self, from: data)
        XCTAssertEqual(decoded.issueCount, 0)

        // idempotent re-run: same counts, models already indexed (no dup), execution_states stay 0
        let r2 = SimiGoBootstrap.run(db: db, env: env, fm: fm,
                                     workRoots: [(rootID: "work-1", url: work, category: "work")],
                                     modelHubs: [hub], reportURL: reportURL)
        XCTAssertEqual(r2.issueCount, 0)
        XCTAssertEqual(r2.modelsDiscovered, r1.modelsDiscovered)
        // unique (root_id, relative_path) => exactly one model row despite two runs
        let modelRows = try db.listExternalFiles(rootID: SimiGoModelDiscovery.cacheRootID)
        XCTAssertEqual(modelRows.count, 1)
        // work rows likewise must NOT double across the two runs (real assertion).
        let workRowsAfterR2 = try db.listExternalFiles(rootID: "work-1").count
        XCTAssertEqual(workRowsAfterR2, r1.workFilesIndexed,
                       "work re-run must not duplicate (root_id, relative_path)")
        let carrier = try db.carrierReport()
        XCTAssertGreaterThan(carrier.objectCount, 0, "bootstrap carries work text")
        XCTAssertEqual(carrier.unaddressedFileContents, 0)
        XCTAssertEqual(carrier.inlineLegacyPayloads, 0)
    }

    // MARK: resumability of legacy migration
    func testBootstrapMigratesLegacyOnceAndSkipsOnReRun() throws {
        let fm = FileManager.default
        let dbURL = tempURL("db.sqlite3"); defer { try? fm.removeItem(at: dbURL) }
        let reportURL = tempURL("bootstrap-report.json"); defer { try? fm.removeItem(at: reportURL) }
        let legacy = Data("""
        {"contractVersion":"v1.0-amended","representationID":"R_Reference_v1",
         "states":[{"id":"S-0001","parentID":null,"modelIdentity":"m","createdAt":700000000,
                    "position":0,"continuationID":"c","nextInput":"","anchor":"a","prefix":[],
                    "lifecycle":"active","checkpointIDs":[]}],
         "checkpoints":[]}
        """.utf8)
        let db = try SimiGoESISDatabase(url: dbURL)
        let r1 = SimiGoBootstrap.run(db: db, env: [:], fm: fm, legacyJSON: legacy, reportURL: reportURL)
        XCTAssertTrue(r1.legacyMigrated)
        XCTAssertEqual(r1.steps.first(where: { $0.id == "import-legacy" })?.status, .ok)
        XCTAssertEqual(try db.count("execution_states"), 1)

        // second run must NOT double-import
        let r2 = SimiGoBootstrap.run(db: db, env: [:], fm: fm, legacyJSON: legacy, reportURL: reportURL)
        XCTAssertFalse(r2.legacyMigrated)
        XCTAssertEqual(r2.steps.first(where: { $0.id == "import-legacy" })?.status, .skipped)
        XCTAssertEqual(try db.count("execution_states"), 1)
    }

    // MARK: never creates work/models under managed root
    func testBootstrapNeverCreatesWorkOrModelsDirectories() throws {
        let fm = FileManager.default
        let dbURL = tempURL("db.sqlite3"); defer { try? fm.removeItem(at: dbURL) }
        let reportURL = tempURL("bootstrap-report.json"); defer { try? fm.removeItem(at: reportURL) }
        let db = try SimiGoESISDatabase(url: dbURL)
        let root = tempURL("managed"); defer { try? fm.removeItem(at: root) }
        _ = SimiGoBootstrap.run(db: db, env: [:], fm: fm, managedRoot: root, reportURL: reportURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("work").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("models").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("logs").path), "allowed runtime dirs are created")
    }

    // MARK: external work files are indexed by (root_id, relative_path) with no second physical copy

    /// "导入外部 work 索引 / 不复制第二份物理文件": the DB stores root-relative
    /// index rows and carries settled text in the content-addressed object store;
    /// the physical files stay in the external source and no copies land under the
    /// managed root. Re-runs reconcile without duplicating.
    func testWorkFilesAreIndexedByRootRelativeAndNeverCopied() throws {
        let fm = FileManager.default
        let dbURL = tempURL("db.sqlite3"); defer { try? fm.removeItem(at: dbURL) }
        let reportURL = tempURL("bootstrap-report.json"); defer { try? fm.removeItem(at: reportURL) }
        let managed = tempURL("managed"); try? fm.createDirectory(at: managed, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: managed) }
        // external work root with a few nested files, OUTSIDE the managed root
        let work = tempURL("work"); 
        try fm.createDirectory(at: work.appendingPathComponent("sub", isDirectory: true), withIntermediateDirectories: true)
        try Data("1".utf8).write(to: work.appendingPathComponent("a.txt"))
        try Data("22".utf8).write(to: work.appendingPathComponent("sub/b.txt"))
        try Data("333".utf8).write(to: work.appendingPathComponent("sub/c.md"))
        defer { try? fm.removeItem(at: work) }

        let db = try SimiGoESISDatabase(url: dbURL)
        let r = SimiGoBootstrap.run(db: db, env: [:], fm: fm,
                                    workRoots: [(rootID: "work-1", url: work, category: "work")],
                                    managedRoot: managed, reportURL: reportURL)
        XCTAssertEqual(r.issueCount, 0, "\(r.steps)")
        XCTAssertEqual(r.workFilesIndexed, 3)

        let rows = try db.listExternalFiles(rootID: "work-1")
        XCTAssertEqual(Set(rows.map { $0.relativePath }), ["a.txt", "sub/b.txt", "sub/c.md"])
        XCTAssertTrue(rows.allSatisfy { !$0.relativePath.hasPrefix("/") }, "stored as relative, never absolute")
        XCTAssertTrue(rows.allSatisfy { $0.rootID == "work-1" && $0.status == "present" })

        // no physical copies under the managed root — only external index rows exist
        for name in ["a.txt", "b.txt", "c.md"] {
            let found = (try? fm.subpathsOfDirectory(atPath: managed.path)) ?? []
            XCTAssertFalse(found.contains { $0.hasSuffix(name) }, "managed root must not contain a copy of \(name)")
        }
        XCTAssertFalse(fm.fileExists(atPath: managed.appendingPathComponent("work").path))

        // re-run reconciles the same 3 rows without duplication
        _ = SimiGoBootstrap.run(db: db, env: [:], fm: fm,
                                workRoots: [(rootID: "work-1", url: work, category: "work")],
                                managedRoot: managed, reportURL: reportURL)
        XCTAssertEqual(try db.listExternalFiles(rootID: "work-1").count, 3)
    }

    // MARK: mid-run failure is recorded AND the next run recovers (可恢复)

    /// "首次初始化可重复执行、中途失败可恢复": a step that fails surfaces as
    /// `issueCount > 0` (never silently swallowed), the run leaves no corrupt half
    /// state, and once the obstruction is cleared a subsequent run completes healthy
    /// on the SAME managed root.
    func testBootstrapRecordsFailureThenRecoversOnReRun() throws {
        let fm = FileManager.default
        let dbURL = tempURL("db.sqlite3"); defer { try? fm.removeItem(at: dbURL) }
        let reportURL = tempURL("bootstrap-report.json"); defer { try? fm.removeItem(at: reportURL) }
        // Obstruct ensure-dirs: the managed root is a FILE, so subdirs can't be made.
        let blocked = tempURL("blocked")
        try Data("not a directory".utf8).write(to: blocked)
        defer { try? fm.removeItem(at: blocked) }

        let db = try SimiGoESISDatabase(url: dbURL)
        let r1 = SimiGoBootstrap.run(db: db, env: [:], fm: fm, managedRoot: blocked, reportURL: reportURL)
        XCTAssertGreaterThan(r1.issueCount, 0, "a failing step must surface, not be swallowed")
        XCTAssertEqual(r1.steps.first(where: { $0.id == "ensure-dirs" })?.status, .failed)

        // clear the obstruction -> replace the file with nothing, recovery run succeeds
        try fm.removeItem(at: blocked)
        let r2 = SimiGoBootstrap.run(db: db, env: [:], fm: fm, managedRoot: blocked, reportURL: reportURL)
        XCTAssertEqual(r2.issueCount, 0, "recovery run must complete healthy: \(r2.steps)")
        XCTAssertEqual(r2.steps.first(where: { $0.id == "ensure-dirs" })?.status, .ok)
        XCTAssertTrue(try db.integrityCheck(), "a prior failed step must not corrupt the authority")
    }

    // MARK: cross-session reconciliation

    /// A change made while the app was closed is picked up by the next launch:
    /// the reconcile step re-derives validity for roots registered in an earlier
    /// session, and a vanished file becomes an explicit `missing` row rather
    /// than a stale `present` one.
    func testBootstrapReconcileCatchesChangesFromAnEarlierSession() throws {
        let fm = FileManager.default
        let dbURL = tempURL("db.sqlite3"); defer { try? fm.removeItem(at: dbURL) }
        let reportURL = tempURL("bootstrap-report.json"); defer { try? fm.removeItem(at: reportURL) }
        let (hub, env) = makeFakeHFHub(); defer { try? fm.removeItem(at: hub) }
        let work = tempURL("work")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        try Data("one".utf8).write(to: work.appendingPathComponent("keep.txt"))
        try Data("two".utf8).write(to: work.appendingPathComponent("gone.txt"))

        let db = try SimiGoESISDatabase(url: dbURL)
        let r1 = SimiGoBootstrap.run(
            db: db, env: env, fm: fm,
            workRoots: [(rootID: "work-1", url: work, category: "work")],
            modelHubs: [hub], reportURL: reportURL)
        XCTAssertEqual(r1.issueCount, 0, "\(r1.steps)")

        // The app was closed: a file disappeared, and the previous scan is old.
        try fm.removeItem(at: work.appendingPathComponent("gone.txt"))
        try rawExec(dbURL, "UPDATE roots SET last_scanned_at='0' WHERE root_id='work-1';")

        let r2 = SimiGoBootstrap.run(
            db: db, env: env, fm: fm, modelHubs: [hub], reportURL: reportURL)
        XCTAssertEqual(r2.issueCount, 0, "\(r2.steps)")
        XCTAssertEqual(
            r2.steps.first(where: { $0.id == "reconcile-roots" })?.status, .ok)

        let rows = try db.listExternalFiles(rootID: "work-1")
        XCTAssertEqual(rows.first(where: { $0.relativePath == "gone.txt" })?.status,
                       "missing")
        XCTAssertEqual(rows.first(where: { $0.relativePath == "keep.txt" })?.status,
                       "present")
        XCTAssertNil(try db.carriedFileContent(rootID: "work-1", relativePath: "gone.txt"))
    }
}
