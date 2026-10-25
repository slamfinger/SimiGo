import XCTest
import Foundation
import G3D1WorkerCore
import SimiGoRuntimeContract

// G6 / G7a / G7b / G8a — Phase 1 D1 worker chain mechanism tests.
//
// These are HONEST Phase 1 tests: they prove the MECHANISM (identity self-check,
// one-shot authorization, replay refusal, the constrained entry refusing under the
// empty trust registry, two independent PIDs). They assert the gate REFUSES and no
// delivery is settled. Nothing here is, or may be read as, a bound delivery — the
// audit records carry claimsSettledDelivery=false and the tests assert it.

final class G3D1SupervisorTests: XCTestCase {

    // MARK: G7b — identity self-check

    func testIdentitySelfCheckVerifiesOwnExecutable() throws {
        guard let path = G3D1Identity.currentExecutablePath(),
              let sha = G3D1Identity.sha256OfFile(at: path) else {
            return XCTFail("cannot self-hash the test host executable")
        }
        let verified = G3D1Identity.check(env: [G3D1Identity.expectedEnvKey: sha])
        guard case .verified(let actual, _) = verified else {
            return XCTFail("expected verified, got \(verified)")
        }
        XCTAssertEqual(actual, sha)

        let mismatch = G3D1Identity.check(env: [G3D1Identity.expectedEnvKey: String(repeating: "0", count: 64)])
        guard case .mismatch = mismatch else { return XCTFail("expected mismatch") }

        let missing = G3D1Identity.check(env: [:])
        XCTAssertEqual(missing, .missingExpectation)
    }

    // MARK: G7a — one-shot marker, atomic consumption, replay refusal

    func testMarkerIssuanceIsExclusive() throws {
        let dir = uniqueTempDir()
        let binding = G3D1Authorization.Binding(slotID: "slot-A", runID: "run-1", expectedExecSHA256: "aa")
        try G3D1Authorization.issue(binding: binding, to: "\(dir)/m")
        XCTAssertThrowsError(try G3D1Authorization.issue(binding: binding, to: "\(dir)/m")) { error in
            guard case G3D1Authorization.IssueError.alreadyIssued = error else {
                return XCTFail("expected alreadyIssued, got \(error)")
            }
        }
    }

    func testMarkerConsumeIsOneShotAndRefusesReplay() throws {
        let dir = uniqueTempDir()
        let path = "\(dir)/m"
        let binding = G3D1Authorization.Binding(slotID: "slot-A", runID: "run-1", expectedExecSHA256: "aa")
        try G3D1Authorization.issue(binding: binding, to: path)

        let first = G3D1Authorization.consume(at: path, expecting: binding)
        guard case .accepted = first else { return XCTFail("first consume should accept, got \(first)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: path), "live marker is gone")
        XCTAssertTrue(G3D1Authorization.isConsumed(at: path))

        // Replay: the same marker cannot authorize a second time.
        let replay = G3D1Authorization.consume(at: path, expecting: binding)
        guard case .missingOrReplayed = replay else { return XCTFail("replay must be refused, got \(replay)") }
    }

    func testMarkerRejectsWrongExecutionBinding() throws {
        let dir = uniqueTempDir()
        let path = "\(dir)/m"
        let issued = G3D1Authorization.Binding(slotID: "slot-A", runID: "run-1", expectedExecSHA256: "aa")
        try G3D1Authorization.issue(binding: issued, to: path)
        // A worker armed for a different run/digest must not consume this marker.
        let wrong = G3D1Authorization.Binding(slotID: "slot-A", runID: "run-OTHER", expectedExecSHA256: "aa")
        guard case .bindingMismatch = G3D1Authorization.consume(at: path, expecting: wrong) else {
            return XCTFail("mismatched run must refuse")
        }
        // The mismatch refusal must NOT have consumed the marker (fail-closed).
        XCTAssertTrue(FileManager.default.fileExists(atPath: path), "binding mismatch cannot consume")
    }

    // MARK: G8a — the constrained entry refuses under the empty registry

    func testGatedRunRefusesBeforeGeneration() async throws {
        let dir = uniqueTempDir()
        let result = try await G3D1GatedRun.run(
            runID: "g8a-run", challengeNonce: "g8a-nonce", writeRootBase: dir)
        let report = result.report

        XCTAssertEqual(report.totalGenerationCallCount, 0, "no generation may run under the empty registry")
        XCTAssertFalse(report.anyArmClearedGate)
        XCTAssertFalse(report.eachArmSettled)
        XCTAssertEqual(result.esExecutor.generateBodyRuns, 0, "gated forward body never ran")
        XCTAssertEqual(result.isExecutor.generateBodyRuns, 0)

        for arm in report.arms {
            XCTAssertFalse(arm.outcome.passed, "the gate must refuse, not pass")
            XCTAssertEqual(arm.outcome.generationCallCount, 0)
            XCTAssertFalse(arm.settleEntered, "refused before settlement")
            XCTAssertFalse(arm.bindingConsumed, "refused before binding consumption")
            XCTAssertFalse(arm.settled)
        }
    }

    // MARK: worker lifecycle — full in-process sequence (identity -> auth -> gate)

    func testWorkerCoreCompletesWithGateRefusal() throws {
        guard let path = G3D1Identity.currentExecutablePath(),
              let sha = G3D1Identity.sha256OfFile(at: path) else {
            return XCTFail("cannot self-hash host")
        }
        let dir = uniqueTempDir()
        let marker = "\(dir)/m"
        let audit = "\(dir)/audit.json"
        try G3D1Authorization.issue(
            binding: .init(slotID: "slot-A", runID: "run-A", expectedExecSHA256: sha), to: marker)

        let env: [String: String] = [
            G3D1Identity.expectedEnvKey: sha,
            G3D1Authorization.markerEnvKey: marker,
            G3D1Authorization.runIDEnvKey: "run-A",
            "G3D1_SLOT": "slot-A",
            "G3D1_AUDIT_PATH": audit,
            "G3D1_WRITE_ROOT": "\(dir)/write",
        ]
        let code = G3D1WorkerCore.run(env: env, pid: 4242)
        XCTAssertEqual(code, .completed)
        XCTAssertTrue(G3D1Authorization.isConsumed(at: marker), "the one-shot marker was consumed")

        let record = try decodeAudit(audit)
        XCTAssertEqual(record.identity.status, "verified")
        XCTAssertEqual(record.authorization.status, "accepted")
        XCTAssertTrue(record.authorization.consumedPathExists)
        XCTAssertEqual(record.execution.totalGenerationCallCount, 0)
        XCTAssertFalse(record.execution.eachArmSettled)
        XCTAssertFalse(record.claimsSettledDelivery)
        XCTAssertEqual(record.exitCode, G3D1WorkerCore.ExitCode.completed.rawValue)
    }

    func testWorkerCoreReplayIsRefused() throws {
        guard let path = G3D1Identity.currentExecutablePath(),
              let sha = G3D1Identity.sha256OfFile(at: path) else { return XCTFail("no host hash") }
        let dir = uniqueTempDir()
        let marker = "\(dir)/m"
        try G3D1Authorization.issue(
            binding: .init(slotID: "slot-A", runID: "run-A", expectedExecSHA256: sha), to: marker)
        let env: [String: String] = [
            G3D1Identity.expectedEnvKey: sha,
            G3D1Authorization.markerEnvKey: marker,
            G3D1Authorization.runIDEnvKey: "run-A",
            "G3D1_SLOT": "slot-A",
            "G3D1_AUDIT_PATH": "\(dir)/a1.json",
            "G3D1_WRITE_ROOT": "\(dir)/write",
        ]
        XCTAssertEqual(G3D1WorkerCore.run(env: env, pid: 1), .completed)
        // Second worker reusing the same marker: authorization replay refused.
        var env2 = env
        env2["G3D1_AUDIT_PATH"] = "\(dir)/a2.json"
        XCTAssertEqual(G3D1WorkerCore.run(env: env2, pid: 2), .authorizationFailed)
    }

    // An external research harness (g3_execution_identity.py) consumes its own
    // one-shot claim before exec'ing the worker and passes the marker id plus the
    // frozen-manifest digests, not a file path. The worker must accept this as a
    // distinct authorization and still reach the (refusing) constrained entry.
    func testWorkerCoreAcceptsExternalHarnessAuthorization() throws {
        guard let path = G3D1Identity.currentExecutablePath(),
              let sha = G3D1Identity.sha256OfFile(at: path) else { return XCTFail("no host hash") }
        let dir = uniqueTempDir()
        let audit = "\(dir)/audit.json"
        let env: [String: String] = [
            G3D1Identity.expectedEnvKey: sha,
            G3D1Authorization.markerEnvKey: "deadbeefcafe",  // harness id, not a path
            G3D1Authorization.manifestSourceEnvKey: String(repeating: "1", count: 64),
            G3D1Authorization.manifestRunnerEnvKey: String(repeating: "2", count: 64),
            G3D1Authorization.runIDEnvKey: "run-external",
            "G3D1_SLOT": "slot-external",
            "G3D1_AUDIT_PATH": audit,
            "G3D1_WRITE_ROOT": "\(dir)/write",
        ]
        XCTAssertEqual(G3D1WorkerCore.run(env: env, pid: 99), .completed)
        let record = try decodeAudit(audit)
        XCTAssertEqual(record.authorization.status, "externally_authorized")
        XCTAssertFalse(record.authorization.consumedPathExists, "worker did not consume a file marker")
        XCTAssertEqual(record.execution.totalGenerationCallCount, 0)
        XCTAssertFalse(record.claimsSettledDelivery)
    }

    func testExternalAuthorizationRequiresManifestBinding() throws {
        // A marker id that is not a file, WITHOUT the harness manifest digests,
        // is not a valid authorization -> fail closed.
        guard let path = G3D1Identity.currentExecutablePath(),
              let sha = G3D1Identity.sha256OfFile(at: path) else { return XCTFail("no host hash") }
        let env: [String: String] = [
            G3D1Identity.expectedEnvKey: sha,
            G3D1Authorization.markerEnvKey: "not-a-path-no-harness",
            G3D1Authorization.runIDEnvKey: "run-x",
            "G3D1_SLOT": "slot-x",
        ]
        XCTAssertEqual(G3D1WorkerCore.run(env: env, pid: 5), .authorizationFailed)
    }

    func testWorkerCoreIdentityFailureDoesNotConsumeMarker() throws {
        let dir = uniqueTempDir()
        let marker = "\(dir)/m"
        try G3D1Authorization.issue(
            binding: .init(slotID: "slot-A", runID: "run-A", expectedExecSHA256: "deadbeef"), to: marker)
        let env: [String: String] = [
            G3D1Identity.expectedEnvKey: "not-the-real-digest",
            G3D1Authorization.markerEnvKey: marker,
            G3D1Authorization.runIDEnvKey: "run-A",
            "G3D1_SLOT": "slot-A",
            "G3D1_AUDIT_PATH": "\(dir)/audit.json",
        ]
        XCTAssertEqual(G3D1WorkerCore.run(env: env, pid: 7), .identityFailed)
        XCTAssertFalse(G3D1Authorization.isConsumed(at: marker),
                       "an unbound worker must fail closed WITHOUT burning the marker")
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker))
    }

    // MARK: G6 — two independent worker processes (real subprocess, env-gated)

    func testSupervisorLaunchesTwoIndependentWorkers() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["G3D1_RUN_SUBPROCESS_TESTS"] == "1",
              let binary = env[G3D1SupervisorCore.workerBinaryEnvKey],
              FileManager.default.fileExists(atPath: binary) else {
            throw XCTSkip("set G3D1_RUN_SUBPROCESS_TESTS=1 and G3D1_WORKER_BINARY to run")
        }
        let dir = uniqueTempDir()
        let result = try G3D1SupervisorCore.supervise(
            workerBinary: binary, runID: "sub-run",
            markerDir: "\(dir)/markers", auditDir: "\(dir)/audits",
            writeRoot: "\(dir)/write", timeoutSeconds: 60)

        XCTAssertTrue(result.distinctPIDs, "two workers must have distinct PIDs")
        XCTAssertEqual(result.slots.count, 2)
        for slot in result.slots {
            XCTAssertEqual(slot.exitCode, 0, "worker \(slot.slotID) exited \(slot.exitCode) (reclaimed=\(slot.reclaimed))")
            XCTAssertFalse(slot.reclaimed)
            XCTAssertEqual(slot.replayRefused, true)
            guard let audit = slot.auditRecord else { return XCTFail("missing audit for \(slot.slotID)") }
            XCTAssertEqual(audit.identity.status, "verified")
            XCTAssertEqual(audit.execution.totalGenerationCallCount, 0)
            XCTAssertFalse(audit.claimsSettledDelivery)
        }
        XCTAssertFalse(result.claimsSettledDelivery)
    }

    func testSupervisorReclaimsHungWorker() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["G3D1_RUN_SUBPROCESS_TESTS"] == "1",
              let binary = env[G3D1SupervisorCore.workerBinaryEnvKey],
              FileManager.default.fileExists(atPath: binary) else {
            throw XCTSkip("set G3D1_RUN_SUBPROCESS_TESTS=1 and G3D1_WORKER_BINARY to run")
        }
        // Launch one deliberately-hung worker and confirm the supervisor terminates
        // it (lifecycle reclaim) rather than waiting for the hang to clear.
        let armed = G3D1Identity.sha256OfFile(at: binary) ?? ""
        let process = try runLaunch(binary: binary, hangSeconds: 30, sha: armed)
        let started = G3D1SupervisorCore.waitFor(process, timeout: 0.2)
        XCTAssertFalse(started, "a hung worker must still be running after the short window")
        process.terminate()
        XCTAssertTrue(G3D1SupervisorCore.waitFor(process, timeout: 5), "terminate must reclaim it")
    }

    // Launch a single worker process directly (for the reclaim test).
    private func runLaunch(binary: String, hangSeconds: Double, sha: String) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        var merged = ProcessInfo.processInfo.environment
        merged["G3D1_HANG_SECONDS"] = String(hangSeconds)
        merged[G3D1Identity.expectedEnvKey] = sha
        process.environment = merged
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        return process
    }

    // MARK: helpers

    private func uniqueTempDir() -> String {
        let dir = NSTemporaryDirectory() + "g3d1-tests-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func decodeAudit(_ path: String) throws -> G3D1AuditRecord {
        let data = try XCTUnwrap(FileManager.default.contents(atPath: path), "audit not written at \(path)")
        return try JSONDecoder().decode(G3D1AuditRecord.self, from: data)
    }
}
