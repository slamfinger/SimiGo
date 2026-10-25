import Foundation
import SimiGoRuntimeContract

// G3 native isolation-gate control point (executable).
//
// The Python research harness invokes this binary before it would let any arm
// generate. The request is sent through the single ``G3ExecutionDispatch``
// funnel as a `.g3` route, whose only branch reaches the gate-protected
// continuation method; that method runs the native `RuntimeIsolationGate`
// through `G3FirstGenerationEntry.runAsync` strictly before generation, and the
// dispatcher has no fallback to a standard/fixture path on refusal.
//
// Because the trust registry is intentionally empty, no provider — including the
// live-kind provider constructed here — can clear the gate, so this entry always
// refuses and generation is never reached. That is the fail-closed behavior the
// harness relies on. It is MLX-free and does not load a model.
//
// Exit codes: 0 gate cleared (generation ran) · 3 gate refused before generation
// · 2 invalid arguments. The refusal/clear outcome is printed to stdout as a
// single JSON object so the harness can collect it verbatim.

func argumentValue(_ name: String, _ args: [String]) -> String? {
    guard let idx = args.firstIndex(of: name), idx + 1 < args.count else { return nil }
    return args[idx + 1]
}

let args = Array(CommandLine.arguments.dropFirst())
let runID = argumentValue("--run-id", args) ?? "g3-run"
let nonce = argumentValue("--challenge-nonce", args) ?? "g3-nonce"

guard !runID.trimmingCharacters(in: .whitespaces).isEmpty,
      !nonce.trimmingCharacters(in: .whitespaces).isEmpty else {
    FileHandle.standardError.write(Data("run-id and challenge-nonce must be non-empty\n".utf8))
    exit(2)
}

let request: AttestationRequest
do {
    request = try AttestationRequest(runID: runID, challengeNonce: nonce)
} catch {
    let outcome = G3GateOutcome(
        gate: RuntimeIsolationGate.gateID, stage: "request", passed: false,
        eligibleForRuntimeEvidence: false, evidenceClass: "gate_refused_before_generation",
        generationCallCount: 0, modelGenerationStartedByGate: false, isExecutionEvidence: false,
        reason: "invalid request: \(error)", failedChecks: [],
        runID: runID, challengeNonce: nonce, providerID: "n/a", providerKind: "n/a",
        trustedLiveProviderCount: RuntimeProviderTrustPolicy.registeredLiveProviderTypes.count)
    let data = try! JSONEncoder().encode(outcome)
    FileHandle.standardOutput.write(data + Data("\n".utf8))
    exit(3)
}

// A live-kind provider with no bound runtime probes. In the real design the
// live provider's probes come from the loaded MLX layer; here none exist, and
// regardless the empty trust registry refuses it before collection.
let provider = LiveResourceAttestationProvider(
    providerID: "simigo.g3.swift-runtime-resource-provider.v1",
    providerKind: .swiftMLXLiveWorker,
    sourceRevision: "g3-native-entry-unbuilt",
    sourceSHA256: String(repeating: "0", count: 64),
    probes: [:])

do {
    // The G3 request is expressed as a `.g3` route and sent through the single
    // dispatch funnel. That branch calls ONLY the gate-protected method, which
    // runs the isolation gate strictly before the generate closure. With the
    // trust registry empty the gate refuses, the throw propagates out of the
    // dispatcher (no fallback to a standard/fixture path), and generation never
    // runs — so the recorded generation-call count stays zero.
    let worker = G3IsolatedWorker(generate: {
        // Reaching here would mean the gate cleared. It must never print in the
        // current fail-closed state; kept as a live canary.
        FileHandle.standardError.write(Data("UNEXPECTED: generation reached\n".utf8))
    })
    let outcome = try await G3ExecutionDispatch.run(
        worker,
        route: .g3(provider: provider, request: request, registrar: nil),
        state: .g3RoutingPlaceholder,
        nextInputTokens: [],
        maxTokens: 0)
    let data = try JSONEncoder().encode(outcome)
    FileHandle.standardOutput.write(data + Data("\n".utf8))
    exit(outcome.stage == "cleared" ? 0 : 3)
} catch G3FirstGenerationEntry.EntryError.refused(let outcome) {
    let data = try! JSONEncoder().encode(outcome)
    FileHandle.standardOutput.write(data + Data("\n".utf8))
    exit(3)
} catch {
    let outcome = G3GateOutcome(
        gate: RuntimeIsolationGate.gateID, stage: "evaluate", passed: false,
        eligibleForRuntimeEvidence: false, evidenceClass: "gate_refused_before_generation",
        generationCallCount: 0, modelGenerationStartedByGate: false, isExecutionEvidence: false,
        reason: "unexpected error: \(error)", failedChecks: [],
        runID: runID, challengeNonce: nonce, providerID: provider.providerID,
        providerKind: provider.providerKind.rawValue,
        trustedLiveProviderCount: RuntimeProviderTrustPolicy.registeredLiveProviderTypes.count)
    let data = try! JSONEncoder().encode(outcome)
    FileHandle.standardOutput.write(data + Data("\n".utf8))
    exit(3)
}
