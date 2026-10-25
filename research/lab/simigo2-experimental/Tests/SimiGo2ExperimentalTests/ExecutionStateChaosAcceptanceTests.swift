import XCTest
import SimiGo2Experimental

/// Independent long-run / multi-process / chaos acceptance for the durable
/// Execution State line (semantic state + representation rehydration +
/// durable identity). The test process is only a driver: every mutation and
/// every verification runs inside spawned ExecutionStateChaosChild
/// processes, so the evidence is process-restart evidence, not in-process
/// state reuse.
///
/// Boundary (carried from the runtime handoff): all of this is PROCESS-crash
/// evidence (SIGKILL). It is NOT power-loss or storage-media durability
/// evidence and NOT a governance closure for G-5 / G-7 / G-8 / G-10.
final class ExecutionStateChaosAcceptanceTests: XCTestCase {
    private var workRoot: URL!

    override func setUpWithError() throws {
        workRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("execution-state-chaos-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: workRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workRoot)
    }

    // MARK: - Child plumbing

    private var labRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/SimiGo2ExperimentalTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // simigo2-experimental
            .deletingLastPathComponent()  // repo root
    }

    private var chaosChild: URL {
        labRoot.appendingPathComponent(
            "simigo2-experimental/.build/debug/ExecutionStateChaosChild")
    }

    private final class ChildProcess {
        let process: Process
        init(executable: URL, arguments: [String]) throws {
            process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
        }

        func waitAndCollect() -> Int32 {
            process.waitUntilExit()
            return process.terminationStatus
        }
    }

    private func launch(_ arguments: [String]) throws -> ChildProcess {
        try ChildProcess(executable: chaosChild, arguments: arguments)
    }

    private func runChild(_ arguments: [String]) throws -> Int32 {
        try launch(arguments).waitAndCollect()
    }

    private func waitForReadyFile(_ url: URL, timeout: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !FileManager.default.fileExists(atPath: url.path) {
            guard Date() < deadline else {
                XCTFail("child never signaled ready at \(url.path)")
                return
            }
            usleep(5_000)
        }
    }

    private func readReport<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    // MARK: - Multi-process identity allocation

    /// Four concurrent processes each reserve 25 generated identities
    /// against one ledger. Every append arbitrates against the on-disk
    /// ledger under the flock, so the final ledger must hold exactly 100
    /// unique reservations and replay cleanly in a fresh process.
    func testMultiProcessGeneratedIdentityAllocationIsUniqueAndReplaysClean() throws {
        let identityRoot = workRoot.appendingPathComponent("identity")
        var children: [ChildProcess] = []
        for namespace in 0..<4 {
            children.append(try launch([
                "--stage", "allocate",
                "--root", identityRoot.path,
                "--namespace", "ns\(namespace)",
                "--count", "25",
                "--report", workRoot.appendingPathComponent("alloc-\(namespace).json").path,
            ]))
        }
        for child in children {
            XCTAssertEqual(child.waitAndCollect(), 0)
        }
        XCTAssertEqual(
            try runChild([
                "--stage", "verify-identity",
                "--root", identityRoot.path,
                "--expect-reservations", "100",
                "--report", workRoot.appendingPathComponent("verify-id.json").path,
            ]), 0)
        let verdict = try readReport(
            ExecutionStateChaosHarness.VerifyIdentityReport.self,
            at: workRoot.appendingPathComponent("verify-id.json"))
        XCTAssertEqual(verdict.status, "pass")
        XCTAssertEqual(verdict.reservations, 100)
        XCTAssertEqual(verdict.ledgerLines, 100)
    }

    /// Two processes race for the SAME requested ID after both opened the
    /// ledger (ready/go barrier forces the stale-view interleaving). The
    /// on-disk arbitration under the flock must commit exactly one
    /// reservation: one winner, one explicit conflict, clean replay.
    func testCrossProcessRequestedIDConflictCommitsExactlyOneReservation() throws {
        let identityRoot = workRoot.appendingPathComponent("identity")
        let go = workRoot.appendingPathComponent("race-go")
        var children: [ChildProcess] = []
        var readyFiles: [URL] = []
        for contender in 0..<2 {
            let ready = workRoot.appendingPathComponent("race-ready-\(contender)")
            readyFiles.append(ready)
            children.append(try launch([
                "--stage", "allocate",
                "--root", identityRoot.path,
                "--namespace", "racer\(contender)",
                "--requested-id", "RACE-1",
                "--ready", ready.path,
                "--go", go.path,
                "--report", workRoot.appendingPathComponent("race-\(contender).json").path,
            ]))
        }
        for ready in readyFiles {
            try waitForReadyFile(ready, timeout: 30)
        }
        try Data("go".utf8).write(to: go)
        var statuses: [Int32] = []
        for child in children {
            statuses.append(child.waitAndCollect())
        }
        XCTAssertEqual(statuses.sorted(), [0, 3])

        var conflicts = 0
        var allocatedIDs: [String] = []
        for contender in 0..<2 {
            let report = try readReport(
                ExecutionStateChaosHarness.AllocateReport.self,
                at: workRoot.appendingPathComponent("race-\(contender).json"))
            if report.conflict {
                conflicts += 1
            } else {
                allocatedIDs = report.allocatedIDs
            }
        }
        XCTAssertEqual(conflicts, 1)
        XCTAssertEqual(allocatedIDs, ["RACE-1"])

        XCTAssertEqual(
            try runChild([
                "--stage", "verify-identity",
                "--root", identityRoot.path,
                "--expect-reservations", "1",
                "--report", workRoot.appendingPathComponent("verify-id.json").path,
            ]), 0)
        let verdict = try readReport(
            ExecutionStateChaosHarness.VerifyIdentityReport.self,
            at: workRoot.appendingPathComponent("verify-id.json"))
        XCTAssertEqual(verdict.status, "pass")
    }

    /// A process that opened the ledger before another process committed a
    /// token must recover the committed identity when it retries the same
    /// token — the stale view must not allocate a second identity.
    func testCrossProcessTokenRetryReturnsCommittedIdentity() throws {
        let identityRoot = workRoot.appendingPathComponent("identity")
        let ready = workRoot.appendingPathComponent("stale-ready")
        let go = workRoot.appendingPathComponent("stale-go")
        let stale = try launch([
            "--stage", "allocate",
            "--root", identityRoot.path,
            "--namespace", "retry",
            "--count", "1",
            "--ready", ready.path,
            "--go", go.path,
            "--report", workRoot.appendingPathComponent("stale.json").path,
        ])
        try waitForReadyFile(ready, timeout: 30)

        let writerStatus = try runChild([
            "--stage", "allocate",
            "--root", identityRoot.path,
            "--namespace", "retry",
            "--count", "1",
            "--report", workRoot.appendingPathComponent("writer.json").path,
        ])
        XCTAssertEqual(writerStatus, 0)
        let committed = try readReport(
            ExecutionStateChaosHarness.AllocateReport.self,
            at: workRoot.appendingPathComponent("writer.json"))

        try Data("go".utf8).write(to: go)
        XCTAssertEqual(stale.waitAndCollect(), 0)
        let retried = try readReport(
            ExecutionStateChaosHarness.AllocateReport.self,
            at: workRoot.appendingPathComponent("stale.json"))
        XCTAssertEqual(retried.allocatedIDs, committed.allocatedIDs)

        XCTAssertEqual(
            try runChild([
                "--stage", "verify-identity",
                "--root", identityRoot.path,
                "--expect-reservations", "1",
                "--report", workRoot.appendingPathComponent("verify-id.json").path,
            ]), 0)
        let verdict = try readReport(
            ExecutionStateChaosHarness.VerifyIdentityReport.self,
            at: workRoot.appendingPathComponent("verify-id.json"))
        XCTAssertEqual(verdict.status, "pass")
    }

    // MARK: - Chaos growth + exact committed-prefix verification

    private func growArguments(
        stateRoot: URL, ops: Int, killAfter: Int, crash: Bool, report: String
    ) -> [String] {
        [
            "--stage", "grow",
            "--state-root", stateRoot.path,
            "--ops", "\(ops)",
            "--kill-after", "\(killAfter)",
            "--crash", crash ? "true" : "false",
            "--report", workRoot.appendingPathComponent(report).path,
        ]
    }

    private func verifyStateArguments(
        stateRoot: URL, expectRecords: Int, expectPosition: Int64, report: String
    ) -> [String] {
        [
            "--stage", "verify-state",
            "--state-root", stateRoot.path,
            "--expect-records", "\(expectRecords)",
            "--expect-position", "\(expectPosition)",
            "--report", workRoot.appendingPathComponent(report).path,
        ]
    }

    private func assertVerifyPasses(
        stateRoot: URL, expectRecords: Int, expectPosition: Int64, report: String
    ) throws {
        XCTAssertEqual(
            try runChild(verifyStateArguments(
                stateRoot: stateRoot,
                expectRecords: expectRecords,
                expectPosition: expectPosition,
                report: report)), 0)
        let verdict = try readReport(
            ExecutionStateChaosHarness.VerifyStateReport.self,
            at: workRoot.appendingPathComponent(report))
        XCTAssertEqual(verdict.status, "pass", "failures: \(verdict.failures)")
    }

    /// SIGKILL at every sweep point of a growth script. The kill lands only
    /// between fully committed transitions, so each restart must observe the
    /// EXACT committed prefix — lifecycle records 1...k+1 contiguous, handle
    /// at position k, one representation per position 0...k with the
    /// deterministic token prefix — and then finish the script from the
    /// restored state.
    func testChaosKillDuringGrowthPreservesExactCommittedPrefix() throws {
        let ops = 8
        for killAfter in [0, 1, 3, 5, ops] {
            let stateRoot = workRoot.appendingPathComponent("chaos-\(killAfter)")
            let crashStatus = try runChild(growArguments(
                stateRoot: stateRoot, ops: ops, killAfter: killAfter,
                crash: true, report: "chaos-\(killAfter)-grow.json"))
            XCTAssertEqual(crashStatus, Int32(SIGKILL))
            try assertVerifyPasses(
                stateRoot: stateRoot,
                expectRecords: 1 + killAfter,
                expectPosition: Int64(killAfter),
                report: "chaos-\(killAfter)-verify.json")

            let remaining = ops - killAfter
            if remaining > 0 {
                let completionStatus = try runChild(growArguments(
                    stateRoot: stateRoot, ops: remaining, killAfter: remaining,
                    crash: false, report: "chaos-\(killAfter)-finish.json"))
                XCTAssertEqual(completionStatus, 0)
            }
            try assertVerifyPasses(
                stateRoot: stateRoot,
                expectRecords: 1 + ops,
                expectPosition: Int64(ops),
                report: "chaos-\(killAfter)-final.json")
        }
    }

    /// Long run: 20 successive process generations on ONE store. Each
    /// generation restores the persisted semantic state, appends four
    /// continue+bind transitions, and is then SIGKILLed; an independent
    /// verifier process rehydrates every representation into a fresh backend
    /// and checks full cumulative continuity before the next generation
    /// starts. Final state: 81 lifecycle records, position 80, 81 physically
    /// verified representations — across 20 process deaths.
    func testLongRunSuccessiveCrashGenerationsPreserveSemanticContinuity() throws {
        let stateRoot = workRoot.appendingPathComponent("longrun")
        let generations = 20
        let opsPerGeneration = 4
        for generation in 0..<generations {
            let crashStatus = try runChild(growArguments(
                stateRoot: stateRoot, ops: opsPerGeneration,
                killAfter: opsPerGeneration, crash: true,
                report: "longrun-\(generation)-grow.json"))
            XCTAssertEqual(crashStatus, Int32(SIGKILL))
            let totalOps = (generation + 1) * opsPerGeneration
            try assertVerifyPasses(
                stateRoot: stateRoot,
                expectRecords: 1 + totalOps,
                expectPosition: Int64(totalOps),
                report: "longrun-\(generation)-verify.json")
        }
    }

    /// Negative control: the verifier must actually reject a corrupted
    /// snapshot, not pass vacuously.
    func testVerifyChildDetectsCorruptedSnapshot() throws {
        let stateRoot = workRoot.appendingPathComponent("corrupt")
        XCTAssertEqual(
            try runChild(growArguments(
                stateRoot: stateRoot, ops: 2, killAfter: 2, crash: false,
                report: "corrupt-grow.json")), 0)
        try assertVerifyPasses(
            stateRoot: stateRoot, expectRecords: 3, expectPosition: 2,
            report: "corrupt-verify-good.json")

        try Data("{not-semantic-state".utf8).write(
            to: stateRoot.appendingPathComponent("execution-state.json"))
        let corruptStatus = try runChild(verifyStateArguments(
            stateRoot: stateRoot, expectRecords: 3, expectPosition: 2,
            report: "corrupt-verify-bad.json"))
        XCTAssertEqual(corruptStatus, 4)
        let verdict = try readReport(
            ExecutionStateChaosHarness.VerifyStateReport.self,
            at: workRoot.appendingPathComponent("corrupt-verify-bad.json"))
        XCTAssertEqual(verdict.status, "fail")
        XCTAssertFalse(verdict.failures.isEmpty)
    }
}
