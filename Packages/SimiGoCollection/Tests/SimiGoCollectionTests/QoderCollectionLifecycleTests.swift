import Foundation
import XCTest
@testable import SimiGoCollection

/// P2: the collector lifecycle that was previously walked by hand.
///
/// Lease ownership is exercised against a real second process, so the kernel
/// release path - a descriptor that goes away because the process does - is
/// covered and not only the in-process release. The holder is `/usr/bin/python3`
/// taking the same `flock` on the same lock file; it stands in for a SIGKILLed
/// collector because it performs no unlock and no cleanup. Collector code stays
/// the thing under test.
///
/// No test here reads a live Qoder transcript: the scan root is a static copy
/// written by `Fixture` into a throwaway directory, and the only writes are
/// inside a throwaway state directory. The zero-information-space claim is
/// checked on the filesystem against the product's known IS store names, so it
/// is a check rather than an inference from intent.
final class QoderCollectionLifecycleTests: XCTestCase {
    private var root: URL!
    private var project: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "qoder-lifecycle-\(UUID().uuidString)", isDirectory: true)
        project = root.appendingPathComponent(Fixture.projectID, isDirectory: true)
        try FileManager.default.createDirectory(
            at: project, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func mainFile() -> URL {
        project.appendingPathComponent("\(Fixture.sessionID).jsonl")
    }

    private func configuration() -> QoderCollectionConfiguration {
        QoderCollectionConfiguration(
            scanRoot: root,
            stateDirectory: root.appendingPathComponent("state", isDirectory: true),
            pollInterval: 30)
    }

    private func lockFile(_ configuration: QoderCollectionConfiguration) -> URL {
        configuration.stateDirectory.appendingPathComponent(
            QoderCollectionLease.lockFileName)
    }

    /// The pid written by whichever process currently owns the lock.
    private func leaseHolderPID(_ configuration: QoderCollectionConfiguration) throws
        -> Int32
    {
        let data = try XCTUnwrap(
            try? Data(contentsOf: lockFile(configuration)),
            "no lease file at \(lockFile(configuration).path)")
        let text = try XCTUnwrap(
            String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "the lease file is not UTF-8 text")
        return try XCTUnwrap(Int32(text), "the lease file holds no pid: \(text)")
    }

    private func waitFor(
        _ predicate: () -> Bool, timeout: TimeInterval = 10
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return true }
            usleep(20_000)
        }
        return predicate()
    }

    /// (bytes, mtime, content hash) keyed by path, for every regular file under
    /// `directory`.
    private func fingerprintTree(_ directory: URL) throws -> [String: String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [:] }
        var result: [String: String] = [:]
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [
                .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
            ])
            guard values.isRegularFile == true else { continue }
            let data = try Data(contentsOf: url)
            let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
            result[url.path] = "\((values.fileSize ?? 0))@\(modified)"
                + "@\(QoderDigest.sha256Hex(data))"
        }
        return result
    }

    private func secondTurnLines() -> [String] {
        Fixture.turnLines(
            anchor: "u-2", answerUUID: "a-2", messageID: "m-2",
            prompt: "second", answer: "answer two", nextAnchor: "u-3",
            parent: "a-1")
    }

    // MARK: - start -> lease -> second instance refused -> stop -> resume

    func testStartTakesTheLeaseAndStopLetsANewInstanceResume() throws {
        let file = mainFile()
        try Fixture.writeLines(Fixture.turnLines(), to: file)
        let configuration = self.configuration()

        let first = QoderCollectionRunner(configuration: configuration) { _ in }
        first.start()
        XCTAssertTrue(first.isRunning)

        // start() schedules an immediate asynchronous poll; do not assume the
        // timer callback has committed the first-sight baseline before stop().
        // A synchronous poll on the runner's serial queue joins that first scan.
        let initial = first.pollOnce()
        XCTAssertTrue(initial.errors.isEmpty, "\\(initial.errors)")
        XCTAssertEqual(try leaseHolderPID(configuration), getpid())

        // While that instance is alive, a second one must be refused rather than
        // sharing - or overwriting - the state directory.
        var fromContender: [QoderCandidateDelivery] = []
        let contender = QoderCollectionRunner(configuration: configuration) {
            fromContender.append(contentsOf: $0)
        }
        let blocked = contender.pollOnce()
        XCTAssertTrue(
            blocked.errors.contains { $0.contains("already owned") },
            "a second runner was not refused: \(blocked.errors)")
        XCTAssertNotNil(contender.unavailableReason)
        XCTAssertTrue(fromContender.isEmpty)

        // Normal termination gives the lease up, and the next instance resumes at
        // the stored position: nothing re-baselined, and it still reads what was
        // appended while the first one was stopped.
        first.stop()
        XCTAssertFalse(first.isRunning)
        try Fixture.writeLines(secondTurnLines(), to: file, append: true)

        var fromNext: [QoderCandidateDelivery] = []
        let next = QoderCollectionRunner(configuration: configuration) {
            fromNext.append(contentsOf: $0)
        }
        let report = next.pollOnce()
        XCTAssertTrue(report.errors.isEmpty, "\(report.errors)")
        XCTAssertEqual(report.baselinedFiles, 0)
        XCTAssertEqual(report.persistedCandidates, 1)
        XCTAssertEqual(
            Fixture.turns(fromNext.map(\.event)).map(\.answerText), ["answer two"])
        XCTAssertEqual(try leaseHolderPID(configuration), getpid())
        XCTAssertNotNil(next.statusSnapshot.pendingCount)
        next.stop()
    }

    // MARK: - SIGKILL of the holder -> kernel releases the flock -> recovery

    func testSIGKILLOfTheLeaseHolderReleasesTheLockAndCollectionResumes() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else {
            throw XCTSkip("the cross-process holder needs /usr/bin/python3 fcntl.flock")
        }
        let file = mainFile()
        try Fixture.writeLines(Fixture.turnLines(), to: file)
        let configuration = self.configuration()

        // Seed a durable cursor plus accepted-and-marked candidates, then stop
        // normally, so the holder below takes over a directory that a live
        // collector had already used. A first-sight baseline is itself a durable
        // candidate, so the two polls leave [baseline, turn] delivered.
        var seeded: [QoderCandidateDelivery] = []
        let first = QoderCollectionRunner(configuration: configuration) {
            seeded.append(contentsOf: $0)
        }
        _ = first.pollOnce()
        try Fixture.writeLines(secondTurnLines(), to: file, append: true)
        XCTAssertEqual(first.pollOnce().persistedCandidates, 1)
        XCTAssertEqual(seeded.map(\.kind), [.baseline, .turn])
        first.stop()

        let state = configuration.stateDirectory.path
        let lock = lockFile(configuration).path
        let script = """
            import fcntl, os, sys, time
            fd = os.open(sys.argv[2], os.O_CREAT | os.O_RDWR, 0o600)
            fcntl.flock(fd, fcntl.LOCK_EX)
            with open(os.path.join(sys.argv[1], "holder.pid"), "w") as handle:
                handle.write("%d\\n" % os.getpid())
                handle.flush()
            time.sleep(120)
            """
        let holder = Process()
        holder.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        holder.arguments = ["-c", script, state, lock]
        holder.standardOutput = Pipe()
        holder.standardError = Pipe()
        try holder.run()
        defer {
            if holder.isRunning {
                _ = kill(holder.processIdentifier, SIGKILL)
                holder.waitUntilExit()
            }
        }
        let pidFile = configuration.stateDirectory.appendingPathComponent("holder.pid")
        XCTAssertTrue(
            waitFor { FileManager.default.fileExists(atPath: pidFile.path) },
            "the helper process never reported owning the lock")
        let holderText = try String(contentsOf: pidFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let holderPID = try XCTUnwrap(
            Int32(holderText), "the helper reported no pid: \(holderText)")
        XCTAssertNotEqual(holderPID, getpid())

        let refused = QoderCollectionRunner(configuration: configuration) { _ in }
        let refusedReport = refused.pollOnce()
        XCTAssertTrue(
            refusedReport.errors.contains { $0.contains("already owned") },
            "collection ran while another process owned the lock: "
                + "\(refusedReport.errors)")
        XCTAssertNotNil(refused.unavailableReason)
        refused.start()
        XCTAssertFalse(refused.isRunning)

        // SIGKILL: no unlock call, no deinit, no cleanup of any kind.
        XCTAssertEqual(kill(holder.processIdentifier, SIGKILL), 0)
        holder.waitUntilExit()

        // A new instance recovers, and recovers *at the stored position*: nothing
        // re-baselined, nothing re-collected, nothing delivered twice.
        var afterRecovery: [QoderCandidateDelivery] = []
        let recovered = QoderCollectionRunner(configuration: configuration) {
            afterRecovery.append(contentsOf: $0)
        }
        let report = recovered.pollOnce()
        XCTAssertTrue(report.errors.isEmpty, "\(report.errors)")
        XCTAssertEqual(report.baselinedFiles, 0)
        XCTAssertEqual(report.persistedCandidates, 0)
        XCTAssertEqual(report.duplicateCandidates, 0)
        XCTAssertTrue(afterRecovery.isEmpty)
        let owner = try leaseHolderPID(configuration)
        XCTAssertEqual(owner, getpid())
        XCTAssertNotEqual(owner, holderPID)
        XCTAssertEqual(recovered.statusSnapshot.pendingCount, 0)
        recovered.stop()
    }

    // MARK: - read-only source, isolated state, zero information space

    func testCollectionReadsAStaticCopyAndWritesOnlyInsideItsOwnStateDirectory()
        throws {
        let configuration = self.configuration()
        var deliveries: [QoderCandidateDelivery] = []
        let runner = QoderCollectionRunner(configuration: configuration) {
            deliveries.append(contentsOf: $0)
        }
        // Freeze the initialization instant with no transcript present, then drop
        // the static copy in, so the collector is proven to read a file created
        // after it started instead of skipping it.
        XCTAssertTrue(runner.pollOnce().errors.isEmpty)
        let file = mainFile()
        try Fixture.writeLines(Fixture.turnLines(), to: file)
        let firstRead = runner.pollOnce()
        XCTAssertEqual(firstRead.newFilesFromStart, 1)
        // A brand-new file yields two durable candidates: the first-sight
        // baseline record and the completed turn.
        XCTAssertEqual(firstRead.persistedCandidates, 2)
        XCTAssertEqual(deliveries.map(\.kind), [.baseline, .turn])

        try Fixture.writeLines(secondTurnLines(), to: file, append: true)
        let writtenLines = Fixture.turnLines() + secondTurnLines()
        let expectedData = Data((writtenLines.map { $0 + "\n" }.joined()).utf8)
        let before = try fingerprintTree(project)

        let secondRead = runner.pollOnce()
        XCTAssertEqual(secondRead.persistedCandidates, 1)
        XCTAssertEqual(deliveries.count, 3)
        XCTAssertEqual(
            try fingerprintTree(project), before,
            "the collector changed the transcript copy")
        XCTAssertEqual(try Data(contentsOf: file), expectedData)
        runner.stop()

        // Paired control for the read-only claim: the same fingerprint must be
        // able to see a write, so the equality above is evidence and not an
        // assertion that can never fail.
        try Fixture.writeLines([Fixture.userLine(uuid: "u-9", text: "control")], to: file)
        XCTAssertNotEqual(try fingerprintTree(project), before)

        // Only these exact names may exist in the state directory; the check is a
        // plain listing against an allow-list, not a prefix match.
        let database = QoderCandidateInbox.databaseFileName
        let unexpected = try unexpectedStateEntries(
            in: configuration.stateDirectory,
            allowed: [
                database, "\(database)-wal", "\(database)-shm", "\(database)-journal",
                QoderCollectionLease.lockFileName,
            ])
        XCTAssertEqual(
            unexpected, [], "unexpected files in the collector state directory: "
                + "\(unexpected)")

        // Paired control: a file that hides behind the database name's prefix must
        // still be reported, which is why the allow-list is exact.
        let lookalike = configuration.stateDirectory
            .appendingPathComponent("\(database)-lookalike")
        try Data("control".utf8).write(to: lookalike)
        XCTAssertEqual(
            try unexpectedStateEntries(
                in: configuration.stateDirectory,
                allowed: [
                    database, "\(database)-wal", "\(database)-shm", "\(database)-journal",
                    QoderCollectionLease.lockFileName,
                ]),
            ["\(database)-lookalike"])
        try FileManager.default.removeItem(at: lookalike)

        // And no information-space store appears anywhere under the test root.
        // This package has no IS dependency; the claim is checked against the
        // known IS store names, not assumed.
        let strays = informationSpaceStores(under: root)
        XCTAssertEqual(strays, [], "information-space writes appeared: \(strays)")

        // Paired control for that claim too: a planted store and its sidecar must
        // both be visible to the same scan.
        let planted = [
            root.appendingPathComponent("simigo.sqlite3"),
            root.appendingPathComponent("simigo.sqlite3-wal"),
        ]
        for url in planted { try Data("control".utf8).write(to: url) }
        XCTAssertEqual(
            informationSpaceStores(under: root).map {
                URL(fileURLWithPath: $0).lastPathComponent
            }.sorted(),
            ["simigo.sqlite3", "simigo.sqlite3-wal"])
        for url in planted { try FileManager.default.removeItem(at: url) }
        XCTAssertEqual(informationSpaceStores(under: root), [])
    }

    /// Entries of `directory` that the collector is not allowed to leave behind.
    private func unexpectedStateEntries(
        in directory: URL, allowed: Set<String>
    ) throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ).map(\.lastPathComponent).filter { !allowed.contains($0) }.sorted()
    }

    /// Paths under `directory` matching the names the product uses for its
    /// authoritative ES/IS database (plus its SQLite sidecars) and the older
    /// `information-space` naming. This is a known-name scan, not a general
    /// classifier: it can only show that no store named like this was written.
    private func informationSpaceStores(under directory: URL) -> [String] {
        let names: Set<String> = [
            "simigo.sqlite3", "simigo.sqlite3-wal",
            "simigo.sqlite3-shm", "simigo.sqlite3-journal",
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [] }
        return enumerator.compactMap { item in
            guard let url = item as? URL else { return nil }
            guard names.contains(url.lastPathComponent)
                || url.path.contains("information-space") else { return nil }
            return url.path
        }.sorted()
    }
}
