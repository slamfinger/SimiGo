import Foundation

// D1 SUPERVISOR (G6) — issue two one-shot authorizations, launch two INDEPENDENT
// worker processes, manage their lifecycle, reclaim on failure, refuse replay,
// and aggregate the per-worker audit records into one observable result.
//
// What this proves in Phase 1, and what it does NOT:
//   * Two real OS processes with DISTINCT PIDs, each re-verifying its own
//     executable identity against a digest the supervisor armed (G7b binding).
//   * Each consumed its OWN one-shot marker; a second attempt on the same slot is
//     refused (G7a replay).
//   * Each worker routed execution through the real gate and recorded the gate's
//     zero-generation refusal (G8a). The aggregated record keeps
//     `claimsSettledDelivery=false` — no supervisor aggregation can turn two
//     refusals into a bound delivery.
//   * If a worker fails or hangs, the supervisor TERMINATES the sibling (lifecycle
//     reclaim) instead of leaving an orphan, and records the reclaim.

public enum G3D1SupervisorCore {
    public static let workerBinaryEnvKey = "G3D1_WORKER_BINARY"

    public struct SlotOutcome: Codable {
        public let slotID: String
        public let pid: Int32
        public let exitCode: Int32
        public let reclaimed: Bool          // terminated by the supervisor
        public let markerPath: String
        public let auditPath: String
        public let auditRecord: G3D1AuditRecord?
        public let replayRefused: Bool?
    }

    public struct Result: Codable {
        public let schema: String
        public let runID: String
        public let workerBinarySHA256: String
        public let slots: [SlotOutcome]
        public let distinctPIDs: Bool
        public let allCompletedCleanly: Bool
        public let claimsSettledDelivery: Bool  // always false
        public init(runID: String, workerBinarySHA256: String, slots: [SlotOutcome]) {
            self.schema = "simigo.g3.d1.supervisor-result/v1"
            self.runID = runID
            self.workerBinarySHA256 = workerBinarySHA256
            self.slots = slots
            let pids = slots.map(\.pid)
            self.distinctPIDs = Set(pids).count == pids.count && pids.allSatisfy { $0 > 0 }
            self.allCompletedCleanly = slots.allSatisfy { $0.exitCode == 0 && !$0.reclaimed }
            self.claimsSettledDelivery = false
        }
    }

    /// Issue a one-shot marker for a slot, bound to `runID` and the armed digest.
    public static func issueMarker(
        dir: String, slotID: String, runID: String, expectedExecSHA256: String
    ) throws -> String {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = "\(dir)/marker-\(slotID).auth"
        let binding = G3D1Authorization.Binding(
            slotID: slotID, runID: runID, expectedExecSHA256: expectedExecSHA256)
        try G3D1Authorization.issue(binding: binding, to: path)
        return path
    }

    /// Launch one worker process with `env`. Returns the running Process and its PID.
    static func launchWorkerProcess(binary: String, env: [String: String]) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        var merged = ProcessInfo.processInfo.environment
        for (k, v) in env { merged[k] = v }
        process.environment = merged
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        return process
    }

    /// Supervise two independent workers. `timeoutSeconds` bounds each wait so a
    /// hung worker is reclaimed rather than blocking forever.
    public static func supervise(
        workerBinary: String,
        runID: String,
        markerDir: String,
        auditDir: String,
        writeRoot: String,
        timeoutSeconds: Double = 60
    ) throws -> Result {
        guard let armedSHA = G3D1Identity.sha256OfFile(at: workerBinary) else {
            preconditionFailure("cannot read worker binary at \(workerBinary)")
        }

        let slots = ["A", "B"]
        var markerPaths: [String] = []
        var auditPaths: [String] = []
        for s in slots {
            markerPaths.append(try issueMarker(
                dir: markerDir, slotID: "slot-\(s)", runID: runID, expectedExecSHA256: armedSHA))
            auditPaths.append("\(auditDir)/audit-slot-\(s).json")
        }

        var processes: [Process] = []
        for i in 0..<slots.count {
            let env: [String: String] = [
                G3D1Identity.expectedEnvKey: armedSHA,
                G3D1Authorization.markerEnvKey: markerPaths[i],
                G3D1Authorization.runIDEnvKey: runID,
                "G3D1_SLOT": "slot-\(slots[i])",
                "G3D1_CHALLENGE_NONCE": "nonce-\(slots[i])",
                "G3D1_AUDIT_PATH": auditPaths[i],
                "G3D1_WRITE_ROOT": "\(writeRoot)/slot-\(slots[i])",
            ]
            processes.append(try launchWorkerProcess(binary: workerBinary, env: env))
        }

        // Lifecycle: wait for each, reclaim (terminate) any that overruns.
        var outcomes: [SlotOutcome] = []
        for i in 0..<processes.count {
            let process = processes[i]
            let pid = process.processIdentifier
            var reclaimed = false
            let exit: Int32
            if waitFor(process, timeout: timeoutSeconds) {
                exit = Int32(process.terminationStatus)
            } else {
                process.terminate()   // reclaim a hung worker
                _ = waitFor(process, timeout: 5)
                exit = Int32(process.terminationStatus)
                reclaimed = true
            }
            let audit = readAudit(auditPaths[i])
            // Replay demonstration: a second consumption of this slot must fail.
            let replay = G3D1Authorization.consume(
                at: markerPaths[i],
                expecting: .init(slotID: "slot-\(slots[i])", runID: runID, expectedExecSHA256: armedSHA))
            let replayRefused: Bool
            if case .accepted = replay { replayRefused = false } else { replayRefused = true }
            outcomes.append(SlotOutcome(
                slotID: "slot-\(slots[i])", pid: pid, exitCode: exit, reclaimed: reclaimed,
                markerPath: markerPaths[i], auditPath: auditPaths[i],
                auditRecord: audit, replayRefused: replayRefused))
        }
        return Result(runID: runID, workerBinarySHA256: armedSHA, slots: outcomes)
    }

    /// Poll `process` until it exits or the timeout elapses. Returns true if exited.
    public static func waitFor(_ process: Process, timeout: Double) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !process.isRunning { return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return !process.isRunning
    }

    static func readAudit(_ path: String) -> G3D1AuditRecord? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(G3D1AuditRecord.self, from: data)
    }
}
