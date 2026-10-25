// ExecutionStateChaosChild — process-level chaos acceptance child for the
// durable Execution State line (see ExecutionStateChaosHarness). Spawned by
// ExecutionStateChaosAcceptanceTests; NOT a user-facing tool.
//
// Stages:
//   --stage allocate --root <dir> --namespace <s> --count <n>
//       [--requested-id <id>] [--ready <file> --go <file>] --report <file>
//       Reserve generated or requested identities against one ledger.
//   --stage grow --state-root <dir> --ops <n> --kill-after <k> --crash <bool>
//       --report <file>
//       Bootstrap-or-restore the root execution, perform continue+bind
//       transitions, optionally SIGKILL self after k committed transitions.
//   --stage verify-state --state-root <dir> --expect-records <n>
//       --expect-position <p> --report <file>
//       Reload the store, rehydrate representations into a fresh backend,
//       verify the full deterministic script. Exit 0 pass / 4 fail.
//   --stage verify-identity --root <dir> --expect-reservations <n>
//       --report <file>
//       Reopen the identity ledger and verify a clean replay. Exit 0/4.

import Foundation
import SimiGo2Experimental

var arguments = Array(CommandLine.arguments.dropFirst())
func value(_ flag: String) -> String {
    guard let index = arguments.firstIndex(of: flag),
        index + 1 < arguments.count
    else {
        fputs("missing \(flag)\n", stderr)
        exit(2)
    }
    return arguments[index + 1]
}
func optionalValue(_ flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag),
        index + 1 < arguments.count
    else { return nil }
    return arguments[index + 1]
}
func intValue(_ flag: String) -> Int {
    guard let parsed = Int(value(flag)) else {
        fputs("invalid \(flag)\n", stderr)
        exit(2)
    }
    return parsed
}

let stage = value("--stage")

#if DEBUG
func runStage() async -> Never {
    switch stage {
    case "allocate":
        let barrier: ExecutionStateChaosHarness.Barrier?
        if let ready = optionalValue("--ready"), let go = optionalValue("--go") {
            barrier = ExecutionStateChaosHarness.Barrier(
                ready: URL(fileURLWithPath: ready),
                go: URL(fileURLWithPath: go))
        } else {
            barrier = nil
        }
        await ExecutionStateChaosHarness.allocateIdentities(
            root: URL(fileURLWithPath: value("--root"), isDirectory: true),
            namespace: value("--namespace"),
            count: optionalValue("--count").flatMap(Int.init) ?? 1,
            requestedID: optionalValue("--requested-id"),
            barrier: barrier,
            reportURL: URL(fileURLWithPath: value("--report")))
    case "grow":
        await ExecutionStateChaosHarness.growSemanticState(
            stateRoot: URL(fileURLWithPath: value("--state-root"), isDirectory: true),
            ops: intValue("--ops"),
            killAfter: intValue("--kill-after"),
            crash: (optionalValue("--crash") ?? "false") == "true",
            reportURL: URL(fileURLWithPath: value("--report")))
    case "verify-state":
        await ExecutionStateChaosHarness.verifySemanticState(
            stateRoot: URL(fileURLWithPath: value("--state-root"), isDirectory: true),
            expectRecords: intValue("--expect-records"),
            expectPosition: Int64(intValue("--expect-position")),
            reportURL: URL(fileURLWithPath: value("--report")))
    case "verify-identity":
        await ExecutionStateChaosHarness.verifyIdentityLedger(
            root: URL(fileURLWithPath: value("--root"), isDirectory: true),
            expectedReservations: intValue("--expect-reservations"),
            reportURL: URL(fileURLWithPath: value("--report")))
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
