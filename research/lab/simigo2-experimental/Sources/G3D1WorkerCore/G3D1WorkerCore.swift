import Foundation
import SimiGoRuntimeContract

// D1 WORKER ORCHESTRATION — the fixed order the worker must obey, and the exit
// codes that make each branch observable to the supervisor.
//
//   1. IDENTITY SELF-CHECK (G7b): the running image must equal the armed digest.
//      On any failure the worker exits 10 BEFORE touching the marker, so an
//      unbound process can never burn a one-shot authorization (fail-closed).
//   2. AUTHORIZATION CONSUMPTION (G7a): the marker must exist, bind this run/exec,
//      and be atomically consumed. Missing / replayed / mismatched -> exit 11.
//   3. CONSTRAINED ENTRY (G8a): the dual-arm run goes through the real public
//      isolation gate. Under the empty registry it refuses before any model call
//      and before binding consumption; that refusal is a SUCCESSFUL Phase 1
//      outcome (exit 0) because it proves the gate is on the call path. Only an
//      unexpected throw before the run is recorded -> exit 12.
//
// The worker NEVER exits 0 claiming a settled delivery; the audit record carries
// `claimsSettledDelivery=false` and the gate's real zero-generation refusal.

public enum G3D1WorkerCore {
    public enum ExitCode: Int32 {
        case completed = 0            // reached the constrained entry; gate refused as required
        case identityFailed = 10      // missing / mismatched / unreadable executable binding
        case authorizationFailed = 11 // absent / replayed / mismatched one-shot marker
        case runError = 12            // runner refused before dispatch, or an unexpected fault
    }

    public struct Config {
        public let slotID: String
        public let runID: String
        public let challengeNonce: String
        public let markerPath: String?
        public let auditPath: String?
        public let writeRoot: String
        public init?(env: [String: String]) {
            guard let runID = env[G3D1Authorization.runIDEnvKey],
                  !runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            self.runID = runID
            self.slotID = env["G3D1_SLOT"] ?? "slot"
            self.challengeNonce = env["G3D1_CHALLENGE_NONCE"] ?? "nonce-\(runID)"
            self.markerPath = env[G3D1Authorization.markerEnvKey]
            self.auditPath = env["G3D1_AUDIT_PATH"]
            self.writeRoot = env["G3D1_WRITE_ROOT"] ?? NSTemporaryDirectory()
        }
    }

    /// Run the whole worker lifecycle from `env`, write the audit record if a path
    /// is configured, and return the exit code. Synchronous entry (bridges the
    /// async gated run) so a plain `main.swift` can call it directly.
    @discardableResult
    public static func run(
        env: [String: String] = ProcessInfo.processInfo.environment,
        pid: Int32 = getpid()
    ) -> ExitCode {
        guard let config = Config(env: env) else {
            // No run ID: nothing to bind, refuse as a run error (fail-closed).
            return .runError
        }

        // (1) Identity self-check — BEFORE consuming the marker.
        let identity = G3D1Identity.check(env: env)
        guard case .verified(let verifiedSHA, let execPath) = identity else {
            let status: String
            switch identity {
            case .missingExpectation: status = "missing_expectation"
            case .mismatch: status = "mismatch"
            case .unreadable: status = "unreadable"
            default: status = "unknown"
            }
            let record = G3D1AuditRecord(
                pid: pid, slotID: config.slotID, runID: config.runID,
                identity: .init(status: status, verifiedExecSHA256: nil, execPath: nil,
                                expectedEnvPresent: env[G3D1Identity.expectedEnvKey] != nil),
                authorization: .init(status: "not_reached", markerPath: config.markerPath,
                                     consumedPathExists: false,
                                     detail: "identity check failed; marker not consumed (fail-closed)"),
                execution: .notReached(),
                exitCode: ExitCode.identityFailed.rawValue)
            emitAudit(record, to: config.auditPath)
            return .identityFailed
        }

        // (2) Authorization — one-shot, bound to this run/exec/slot. Two issuers
        // are valid and reported distinctly so neither can fake the other:
        //   * a live file marker (issued by G3D1Supervisor) the worker consumes;
        //   * an external research harness that already consumed its own O_EXCL
        //     claim before exec'ing us (value is an id, not a path).
        guard let markerValue = config.markerPath else {
            writeAuthFailure(config: config, pid: pid, sha: verifiedSHA, path: execPath,
                             marker: nil, status: "env_absent",
                             detail: "G3_AUTHORIZATION_MARKER not set")
            return .authorizationFailed
        }
        var authStatus = ""
        var authDetail: String?
        var authConsumed = false
        if FileManager.default.fileExists(atPath: markerValue) {
            let expected = G3D1Authorization.Binding(
                slotID: config.slotID, runID: config.runID, expectedExecSHA256: verifiedSHA)
            switch G3D1Authorization.consume(at: markerValue, expecting: expected) {
            case .accepted:
                authStatus = "accepted"
                authConsumed = G3D1Authorization.isConsumed(at: markerValue)
            case .missingOrReplayed:
                writeAuthFailure(config: config, pid: pid, sha: verifiedSHA, path: execPath,
                                 marker: markerValue, status: "missing_or_replayed",
                                 detail: "no live marker (absent or already consumed)")
                return .authorizationFailed
            case .bindingMismatch(let reason):
                writeAuthFailure(config: config, pid: pid, sha: verifiedSHA, path: execPath,
                                 marker: markerValue, status: "binding_mismatch", detail: reason)
                return .authorizationFailed
            case .malformed(let reason):
                writeAuthFailure(config: config, pid: pid, sha: verifiedSHA, path: execPath,
                                 marker: markerValue, status: "malformed", detail: reason)
                return .authorizationFailed
            }
        } else if G3D1Authorization.isExternallyAuthorized(env: env) {
            authStatus = "externally_authorized"
            authDetail = "one-shot claim consumed by the external harness before launch"
        } else {
            writeAuthFailure(config: config, pid: pid, sha: verifiedSHA, path: execPath,
                             marker: markerValue, status: "missing_or_replayed",
                             detail: "marker path absent and no external harness authorization")
            return .authorizationFailed
        }
        let auth = (status: authStatus, marker: markerValue, consumed: authConsumed, detail: authDetail)

        // (3) Constrained entry — real gate, model-free. A refusal is expected.
        // A reference box holds the async result so no captured `var` is mutated
        // across the concurrent boundary (clean under stricter language modes).
        final class ResultBox: @unchecked Sendable {
            var report: G3DualArmRunReport?
            var esRuns = 0
            var isRuns = 0
        }
        let bridge = DispatchQueue(label: "g3d1.worker.run")
        let box = ResultBox()
        let sem = DispatchSemaphore(value: 0)
        bridge.async {
            Task {
                do {
                    let r = try await G3D1GatedRun.run(
                        runID: config.runID, challengeNonce: config.challengeNonce,
                        writeRootBase: config.writeRoot)
                    box.report = r.report
                    box.esRuns = r.esExecutor.generateBodyRuns
                    box.isRuns = r.isExecutor.generateBodyRuns
                } catch {
                    box.report = nil
                }
                sem.signal()
            }
        }
        sem.wait()
        let esRuns = box.esRuns
        let isRuns = box.isRuns

        if let report = box.report {
            let arms = report.arms.map {
                G3D1AuditRecord.Arm(
                    armID: $0.armID, routedVia: $0.routedVia,
                    gateStage: $0.outcome.stage, gatePassed: $0.outcome.passed,
                    generationCallCount: $0.outcome.generationCallCount,
                    settleEntered: $0.settleEntered, bindingConsumed: $0.bindingConsumed,
                    settled: $0.settled, reason: $0.outcome.reason)
            }
            let execution = G3D1AuditRecord.Execution(
                reached: true, totalGenerationCallCount: report.totalGenerationCallCount,
                eachArmSettled: report.eachArmSettled,
                esGenerateBodyRuns: esRuns, isGenerateBodyRuns: isRuns, arms: arms)
            let record = G3D1AuditRecord(
                pid: pid, slotID: config.slotID, runID: config.runID,
                identity: .init(status: "verified", verifiedExecSHA256: verifiedSHA,
                                execPath: execPath, expectedEnvPresent: true),
                authorization: .init(status: auth.status, markerPath: auth.marker,
                                     consumedPathExists: auth.consumed,
                                     detail: auth.detail),
                execution: execution, exitCode: ExitCode.completed.rawValue)
            emitAudit(record, to: config.auditPath)
            return .completed
        } else {
            let execution = G3D1AuditRecord.Execution(
                reached: false, totalGenerationCallCount: 0, eachArmSettled: false,
                esGenerateBodyRuns: 0, isGenerateBodyRuns: 0, arms: [])
            let record = G3D1AuditRecord(
                pid: pid, slotID: config.slotID, runID: config.runID,
                identity: .init(status: "verified", verifiedExecSHA256: verifiedSHA,
                                execPath: execPath, expectedEnvPresent: true),
                authorization: .init(status: auth.status, markerPath: auth.marker,
                                     consumedPathExists: auth.consumed,
                                     detail: auth.detail),
                execution: execution, exitCode: ExitCode.runError.rawValue)
            emitAudit(record, to: config.auditPath)
            _ = esRuns; _ = isRuns
            return .runError
        }
    }

    private static func writeAuthFailure(
        config: Config, pid: Int32, sha: String, path: String,
        marker: String?, status: String, detail: String
    ) {
        let record = G3D1AuditRecord(
            pid: pid, slotID: config.slotID, runID: config.runID,
            identity: .init(status: "verified", verifiedExecSHA256: sha,
                            execPath: path, expectedEnvPresent: true),
            authorization: .init(status: status, markerPath: marker,
                                 consumedPathExists: marker.map(G3D1Authorization.isConsumed(at:)) ?? false,
                                 detail: detail),
            execution: .notReached(),
            exitCode: ExitCode.authorizationFailed.rawValue)
        emitAudit(record, to: config.auditPath)
    }

    /// Best-effort audit write. A failure never changes the worker's exit decision
    /// (the exit code is authoritative), so the write is best-effort by design.
    private static func emitAudit(_ record: G3D1AuditRecord, to path: String?) {
        guard let path else { return }
        try? record.write(to: path)
    }
}

extension G3D1AuditRecord.Execution {
    static func notReached() -> G3D1AuditRecord.Execution {
        .init(reached: false, totalGenerationCallCount: 0, eachArmSettled: false,
              esGenerateBodyRuns: 0, isGenerateBodyRuns: 0, arms: [])
    }
}
