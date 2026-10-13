// EngineBaselineCrashChild — process-level crash verification child for the
// DCC-1 durable session baseline (see
// docs/02-evidence/restore-atomicity-dcc-20261013). Spawned by
// EngineSessionBaselineTests; NOT a user-facing tool.
//
// Stages:
//   --stage bootstrap --store <dir> --model <dir> --report <file>
//       Bootstrap a durable session, write the report, then SIGKILL self.
//   --stage teardown --store <dir> --model <dir> --report <file>
//       Bootstrap + newSession (durable retirement), write, SIGKILL self.
//   --stage torn --store <dir> --model <dir>
//       Write a torn (truncated) baseline + pointer, exit 0.
//   --stage verify --store <dir> --model <dir>
//       Run recoverDurableSession and print the JSON verdict.

import Foundation
import SimiGo2Experimental

var arguments = Array(CommandLine.arguments.dropFirst())
func value(_ flag: String) -> String {
    if let index = arguments.firstIndex(of: flag), index + 1 < arguments.count {
        return arguments[index + 1]
    }
    fputs("missing \(flag)\n", stderr)
    exit(2)
}

let stage = value("--stage")
let storeRoot = URL(fileURLWithPath: value("--store"))
let modelRoot = URL(fileURLWithPath: value("--model"))
let reportURL = URL(fileURLWithPath: value("--report"))

#if DEBUG
func runStage() async -> Never {
    switch stage {
    case "bootstrap":
        await EngineBaselineCrashHarness.bootstrapCommitAndKillSelf(
            storeRoot: storeRoot, modelRoot: modelRoot, reportURL: reportURL)
    case "teardown":
        await EngineBaselineCrashHarness.teardownCommitAndKillSelf(
            storeRoot: storeRoot, modelRoot: modelRoot, reportURL: reportURL)
    case "torn":
        EngineBaselineCrashHarness.writeTornBaseline(storeRoot: storeRoot, modelRoot: modelRoot)
    case "verify":
        await EngineBaselineCrashHarness.verifyOutcome(storeRoot: storeRoot, modelRoot: modelRoot)
    default:
        fputs("unknown stage \(stage)\n", stderr)
        exit(2)
    }
}

await runStage()
#else
fputs("crash harness requires a DEBUG build\n", stderr)
exit(2)
#endif
