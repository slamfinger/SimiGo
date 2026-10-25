import Foundation
import G3D1WorkerCore

// D1 WORKER EXECUTABLE — the constrained entry point a supervisor arms. Its whole
// behavior is the ordered lifecycle in G3D1WorkerCore: identity self-check ->
// one-shot authorization consumption -> the real gated dual-arm run (which refuses
// under the empty trust registry before any model call or binding consumption) ->
// an auditable record. The exit code makes each branch observable.

// A supervisor-lifecycle test hook ONLY: when G3D1_HANG_SECONDS is set the worker
// stalls before doing any work, so the supervisor's reclaim path can be exercised.
// It is inert for every real run (the variable is never set there).
if let hang = ProcessInfo.processInfo.environment["G3D1_HANG_SECONDS"],
   let seconds = Double(hang), seconds > 0 {
    Thread.sleep(forTimeInterval: seconds)
    exit(13)  // 13: hung-worker sentinel (only reached if not reclaimed)
}

let code = G3D1WorkerCore.run()
exit(code.rawValue)
