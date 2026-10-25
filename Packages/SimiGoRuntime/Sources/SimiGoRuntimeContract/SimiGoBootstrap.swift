import Foundation

public enum BootstrapStepStatus: String, Codable, Sendable { case ok, skipped, failed }

public struct BootstrapStepResult: Codable, Equatable, Sendable {
    public let id: String
    public let status: BootstrapStepStatus
    public let detail: String
}

/// Machine-readable first-run deployment report. Written to disk as JSON so an
/// external verifier / the acceptance matrix can read it. `issueCount` counts
/// failed steps; a run with `issueCount == 0` is fully healthy.
public struct BootstrapReport: Codable, Equatable, Sendable {
    public var startedAt: String
    public var finishedAt: String
    public var schemaVersion: Int
    public var steps: [BootstrapStepResult]
    public var modelsDiscovered: Int
    public var workFilesIndexed: Int
    public var legacyMigrated: Bool
    public var issueCount: Int
    public var ok: Bool { issueCount == 0 }
}

/// Autonomous, repeatable SimiGo initialization.
///
/// Every step inspects current durable state before acting, so a re-run changes
/// nothing (idempotent) and an interrupted run resumes correctly: completed steps
/// stay completed, the failed one is simply retried. It NEVER destroys prior data,
/// NEVER creates `work`/`models` under the managed root, and NEVER copies external
/// files — it only indexes them by (root_id, relative_path).
public enum SimiGoBootstrap {
    public static func run(
        db: SimiGoESISDatabase,
        env: [String: String] = ProcessInfo.processInfo.environment,
        fm: FileManager = .default,
        legacyJSON: Data? = nil,
        workRoots: [(rootID: String, url: URL, category: String)] = [],
        managedRoot: URL? = nil,
        modelHubs: [URL]? = nil,
        reportURL: URL = SimiGoPaths.manifests.appendingPathComponent("bootstrap-report.json"),
        maxIndexDepth: Int = 4
    ) -> BootstrapReport {
        let fmt = ISO8601DateFormatter()
        let started = fmt.string(from: Date())
        var steps: [BootstrapStepResult] = []
        var models = 0
        var workIndexed = 0
        var legacyMigrated = false

        func step(_ id: String, _ body: () throws -> (BootstrapStepStatus, String)) {
            do { let (st, d) = try body(); steps.append(.init(id: id, status: st, detail: d)) }
            catch { steps.append(.init(id: id, status: .failed, detail: "\(error)")) }
        }

        // 1. Managed runtime directories — explicitly excluding work / models.
        let effectiveRoot = managedRoot ?? SimiGoPaths.managedRoot()
        step("ensure-dirs") {
            for name in SimiGoPaths.creatableSubdirectoryNames where !SimiGoPaths.forbiddenSubdirectories.contains(name) {
                try fm.createDirectory(at: effectiveRoot.appendingPathComponent(name, isDirectory: true), withIntermediateDirectories: true)
            }
            return (.ok, "created managed runtime directories under \(effectiveRoot.lastPathComponent)")
        }

        // 2. Schema migrations (idempotent).
        step("migrate-schema") {
            try db.runMigrations()
            let v = try db.schemaVersion()
            return (v >= 1 ? .ok : .failed, "schemaVersion=\(v)")
        }

        // 3. Legacy JSON migration — only if a graph was supplied AND the DB is
        //    still empty, so re-runs never double-import (resumable, idempotent).
        step("import-legacy") {
            if let legacy = legacyJSON, try db.count("execution_states") == 0 {
                let outcome = try db.importLegacyGraph(jsonData: legacy, sourceLabel: "bootstrap-legacy")
                legacyMigrated = true
                return (.ok, "states=\(outcome.statesImported) settlements=\(outcome.settlementsImported)")
            }
            return (.skipped, legacyJSON == nil ? "no legacy graph supplied" : "authority already populated")
        }

        // 4. Discover models from the external HF cache and index them (root_id +
        //    relative path only — no weights are copied).
        step("discover-models") {
            let found = SimiGoModelDiscovery.discover(env: env, fm: fm, hubs: modelHubs)
            models = found.count
            for m in found {
                try db.indexExternalFile(rootID: m.rootID, category: "model",
                                         relativePath: m.relativePath, kind: m.repoID,
                                         size: m.sizeBytes, modifiedAt: nil, contentDigest: nil)
            }
            return (.ok, "discovered \(found.count) model file(s)")
        }

        // 5. Index declared external work roots (bounded depth, files only).
        step("index-work") {
            for entry in workRoots {
                try db.upsertRoot(rootID: entry.rootID, category: entry.category,
                                  displayName: entry.url.lastPathComponent, locatorType: "path", status: "present")
                for file in enumerateFiles(entry.url, fm: fm, maxDepth: maxIndexDepth) {
                    let rel = relative(file, under: entry.url)
                    try db.indexExternalFile(rootID: entry.rootID, category: entry.category,
                                             relativePath: rel, kind: file.pathExtension,
                                             size: fileSize(file, fm: fm), modifiedAt: nil, contentDigest: nil)
                    workIndexed += 1
                }
            }
            return (workRoots.isEmpty ? .skipped : .ok, "indexed \(workIndexed) work file(s)")
        }

        let issues = steps.filter { $0.status == .failed }.count
        var report = BootstrapReport(
            startedAt: started, finishedAt: fmt.string(from: Date()),
            schemaVersion: (try? db.schemaVersion()) ?? 0,
            steps: steps, modelsDiscovered: models,
            workFilesIndexed: workIndexed, legacyMigrated: legacyMigrated,
            issueCount: issues)

        // 6. Emit the machine-readable report.
        step("write-report") {
            let data = try makeEncoder().encode(report)
            try fm.createDirectory(at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: reportURL, options: [.atomic])
            report.steps.append(.init(id: "write-report", status: .ok, detail: reportURL.lastPathComponent))
            return (.ok, reportURL.path)
        }
        return report
    }

    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static func enumerateFiles(_ root: URL, fm: FileManager, maxDepth: Int) -> [URL] {
        var out: [URL] = []
        var stack: [(URL, Int)] = [(root, 0)]
        while let (dir, depth) = stack.popLast() {
            if depth > maxDepth { continue }
            guard let children = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for c in children {
                let isDir = (try? c.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                if isDir { stack.append((c, depth + 1)) } else { out.append(c) }
            }
        }
        return out
    }

    private static func relative(_ file: URL, under root: URL) -> String {
        let a = file.standardizedFileURL.path, b = root.standardizedFileURL.path
        return a.hasPrefix(b + "/") ? String(a.dropFirst(b.count + 1)) : file.lastPathComponent
    }

    private static func fileSize(_ file: URL, fm: FileManager) -> Int64 {
        ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) }) ?? 0
    }
}
