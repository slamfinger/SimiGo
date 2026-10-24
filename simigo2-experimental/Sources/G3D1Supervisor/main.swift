import Foundation
import G3D1WorkerCore

// D1 SUPERVISOR EXECUTABLE — arms two one-shot authorizations, launches two
// INDEPENDENT worker processes (distinct PIDs), manages their lifecycle (reclaim
// on hang/failure), demonstrates replay refusal, and prints the aggregated audit.
//
// Its success condition is honest: a clean Phase 1 supervision is BOTH workers
// completing with exit 0 (the constrained entry refused as required), distinct
// PIDs, both markers consumed exactly once with replay refused, and both audit
// records reporting zero generation and no settlement. It NEVER reports a bound
// delivery — the aggregate carries claimsSettledDelivery=false.

let env = ProcessInfo.processInfo.environment
let args = CommandLine.arguments

func resolveWorkerBinary() -> String? {
    if let p = args.dropFirst().first(where: { !$0.hasPrefix("--") }) { return p }
    return env[G3D1SupervisorCore.workerBinaryEnvKey]
}

guard let workerBinary = resolveWorkerBinary(),
      FileManager.default.fileExists(atPath: workerBinary) else {
    FileHandle.standardError.write(
        Data("usage: G3D1Supervisor <worker-binary> (or set G3D1_WORKER_BINARY)\n".utf8))
    exit(2)
}

let runID = env["G3D1_RUN_ID"] ?? "sup-run"
let workDir = env["G3D1_SUPERVISE_DIR"] ?? (NSTemporaryDirectory() + "g3d1-sup-\(runID)")
let timeout = Double(env["G3D1_SUPERVISE_TIMEOUT"] ?? "") ?? 60

do {
    let result = try G3D1SupervisorCore.supervise(
        workerBinary: workerBinary,
        runID: runID,
        markerDir: "\(workDir)/markers",
        auditDir: "\(workDir)/audits",
        writeRoot: "\(workDir)/write",
        timeoutSeconds: timeout)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(result)
    if let out = env["G3D1_SUPERVISE_RESULT_PATH"] {
        try data.write(to: URL(fileURLWithPath: out))
    }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    // Exit 0 only when the supervision was clean: distinct PIDs, both completed,
    // none reclaimed, every replay refused. Still never a bound-delivery claim.
    let replayOK = result.slots.allSatisfy { $0.replayRefused == true }
    exit(result.distinctPIDs && result.allCompletedCleanly && replayOK ? 0 : 1)
} catch {
    FileHandle.standardError.write(Data("supervisor failed: \(error)\n".utf8))
    exit(12)
}
