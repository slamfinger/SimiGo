import XCTest
@testable import SimiGoRuntimeContract

// Control-flow tests for the G3-specific native execution entry. They prove:
//   * an unregistered live provider is refused BEFORE generation, count stays 0;
//   * a fixture provider is hard-rejected and cannot impersonate a live run;
//   * missing / malformed observations fail closed with a recorded reason;
//   * generation is reached ONLY after a cleared gate;
//   * mock results never become real resource-isolation evidence;
//   * the refusal record is stable JSON the Python harness can collect verbatim.
//
// All providers here are UNTRUSTED (the shipping registry is empty), so none of
// these runs can clear the gate through the real production path.
final class G3IsolatedExecutionEntryTests: XCTestCase {
    static let modelSHA = String(repeating: "a", count: 64)
    static let tokSHA = String(repeating: "b", count: 64)
    static let sourceSHA = String(repeating: "c", count: 64)

    // MARK: Mock live probe (stands in for a real runtime; NOT trusted)

    final class MockProbe: RuntimeResourceProbe, @unchecked Sendable {
        let arm: String
        let pid: Int
        let writeRoot: String
        let mutable: [String]
        let genBeforeGate: Int
        let initialized: Bool
        init(arm: String, pid: Int, writeRoot: String, mutable: [String],
             genBeforeGate: Int = 0, initialized: Bool = true) {
            self.arm = arm; self.pid = pid; self.writeRoot = writeRoot
            self.mutable = mutable; self.genBeforeGate = genBeforeGate; self.initialized = initialized
        }
        func workerPID() -> Int { pid }
        func isolationUnitID() -> String { "iso-\(arm)" }
        func modelInstanceID() -> String { "model-\(arm)" }
        func modelContentSHA256() -> String { G3IsolatedExecutionEntryTests.modelSHA }
        func tokenizerInstanceID() -> String { "tok-\(arm)" }
        func tokenizerContentSHA256() -> String { G3IsolatedExecutionEntryTests.tokSHA }
        func weightsBufferInstanceID() -> String { "wbuf-\(arm)" }
        func kvCacheInstanceID() -> String { "kv-\(arm)" }
        func prefixCacheInstanceID() -> String { "pc-\(arm)" }
        func runtimeBufferInstanceID() -> String { "rbuf-\(arm)" }
        func kvCacheNamespace() -> String { "kv-ns-\(arm)" }
        func prefixCacheNamespace() -> String { "pc-ns-\(arm)" }
        func runtimeWriteRoot() -> String { writeRoot }
        func generationInvocationsBeforeGate() -> Int { genBeforeGate }
        func runtimeInitializedBeforeFirstGeneration() -> Bool { initialized }
        func mutableResourceIDs() -> [String] { mutable }
    }

    struct FixtureProvider: RuntimeAttestationProvider {
        let providerID = "simigo.g3.fixture"
        let providerKind: RuntimeProviderKind = .fixture
        func collect(_ request: AttestationRequest) throws -> [RuntimeAttestation] { [] }
    }

    // MARK: Helpers

    func request() throws -> AttestationRequest {
        try AttestationRequest(runID: "run-1", challengeNonce: "nonce-1")
    }

    func liveProvider(
        arms: [RuntimeArmID] = RuntimeIsolationGate.defaultExpectedArms
    ) -> LiveResourceAttestationProvider {
        var probes: [RuntimeArmID: any RuntimeResourceProbe] = [:]
        for (i, arm) in arms.enumerated() {
            probes[arm] = MockProbe(
                arm: arm.rawValue, pid: 1000 + i,
                writeRoot: "/tmp/g3/\(arm.rawValue)",
                mutable: ["mut-\(arm.rawValue)"])
        }
        return LiveResourceAttestationProvider(
            providerID: "simigo.g3.swift-runtime-resource-provider.v1",
            sourceRevision: "rev-abc",
            sourceSHA256: G3IsolatedExecutionEntryTests.sourceSHA,
            probes: probes)
    }

    func clearedReport() -> GateReport {
        GateReport(
            gate: RuntimeIsolationGate.gateID,
            evidenceClass: "registered_live_runtime_attestation",
            eligibleForRuntimeEvidence: true,
            passed: true, checkCount: 19, passedCount: 19, failedCount: 0,
            failedChecks: [], checks: [:], details: [:],
            modelGenerationStartedByGate: false, readOnlyModelArtifactSharingAllowed: true,
            providerID: "simigo.g3.swift-runtime-resource-provider.v1",
            providerKind: .swiftMLXLiveWorker,
            runID: "run-1", challengeNonce: "nonce-1", attestationCount: 2)
    }

    // MARK: Provider pulls genuine identity from the probe (not bools/config)

    func testObservationIsAssembledByQueryingTheProbe() {
        let probe = MockProbe(arm: "ES+IS", pid: 4242, writeRoot: "/tmp/g3/es", mutable: ["m1", "m2"])
        let obs = runtimeResourceObservation(from: probe)
        XCTAssertEqual(obs.workerPID, 4242)
        XCTAssertEqual(obs.modelInstanceID, "model-ES+IS")
        XCTAssertEqual(obs.kvCacheNamespace, "kv-ns-ES+IS")
        XCTAssertEqual(obs.mutableResourceIDs, ["m1", "m2"])
        XCTAssertEqual(obs.generationInvocationsBeforeGate, 0)
        XCTAssertTrue(obs.initializedBeforeFirstGeneration)
    }

    func testCollectEmitsEnvelopePerArmInRequestOrder() throws {
        let provider = liveProvider()
        let envelopes = try provider.collect(request())
        XCTAssertEqual(envelopes.count, 2)
        XCTAssertEqual(envelopes.map(\.armID), RuntimeIsolationGate.defaultExpectedArms)
        XCTAssertEqual(envelopes.allSatisfy { $0.providerKind.isLive }, true)
        // A missing probe fails closed at collect time.
        let partial = LiveResourceAttestationProvider(
            providerID: "p", sourceRevision: "r",
            sourceSHA256: G3IsolatedExecutionEntryTests.sourceSHA,
            probes: [:])
        XCTAssertThrowsError(try partial.collect(request())) { error in
            guard case RuntimeAttestationError.invalidAttestation = error else {
                return XCTFail("expected invalidAttestation, got \(error)")
            }
        }
    }

    // MARK: Unregistered live provider refused BEFORE generation

    func testUnregisteredLiveProviderRefusesBeforeGeneration() throws {
        let provider = liveProvider()
        var generated = 0
        XCTAssertThrowsError(
            try G3FirstGenerationEntry.run(provider: provider, request: request()) {
                generated += 1
            }
        ) { error in
            guard case G3FirstGenerationEntry.EntryError.refused(let outcome) = error else {
                return XCTFail("expected refusal, got \(error)")
            }
            XCTAssertEqual(generated, 0)
            XCTAssertEqual(outcome.generationCallCount, 0)
            XCTAssertEqual(outcome.stage, "provider_trust")
            XCTAssertFalse(outcome.passed)
            XCTAssertFalse(outcome.eligibleForRuntimeEvidence)
            XCTAssertFalse(outcome.isExecutionEvidence)
            XCTAssertEqual(outcome.trustedLiveProviderCount, 0)
        }
    }

    func testFixtureProviderIsHardRejectedNoImpersonation() throws {
        var generated = 0
        XCTAssertThrowsError(
            try G3FirstGenerationEntry.run(provider: FixtureProvider(), request: request()) {
                generated += 1
            }
        ) { error in
            guard case G3FirstGenerationEntry.EntryError.refused(let outcome) = error else {
                return XCTFail("expected refusal, got \(error)")
            }
            XCTAssertEqual(generated, 0)
            XCTAssertEqual(outcome.stage, "provider_trust")
            XCTAssertTrue(outcome.reason.contains("fixture"))
        }
    }

    // MARK: Missing / malformed observation fails closed with reason

    func testEvaluateFailureRefusesWithFailedChecksAndNoGeneration() throws {
        // Simulate a trusted provider whose gate still refuses on isolation
        // predicates (via injected isolation), proving fail-closed + reason.
        let provider = liveProvider()
        var generated = 0
        XCTAssertThrowsError(
            try G3FirstGenerationEntry.run(
                provider: provider, request: request(),
                generate: { generated += 1 },
                isolation: { _, _ in throw RuntimeAttestationError.isolationGateRefused(
                    ["distinct_kv_cache_instances", "no_shared_mutable_resources"]) }
            )
        ) { error in
            guard case G3FirstGenerationEntry.EntryError.refused(let outcome) = error else {
                return XCTFail("expected refusal, got \(error)")
            }
            XCTAssertEqual(generated, 0)
            XCTAssertEqual(outcome.generationCallCount, 0)
            XCTAssertEqual(outcome.stage, "evaluate")
            XCTAssertEqual(Set(outcome.failedChecks),
                           ["distinct_kv_cache_instances", "no_shared_mutable_resources"])
        }
    }

    // MARK: Generation happens ONLY after a cleared gate

    func testGenerationRunsOnceAfterClearedGate() throws {
        let provider = liveProvider()
        var generated = 0
        let outcome = try G3FirstGenerationEntry.run(
            provider: provider, request: request(),
            generate: { generated += 1 },
            isolation: { _, _ in self.clearedReport() }
        )
        XCTAssertEqual(generated, 1)
        XCTAssertEqual(outcome.generationCallCount, 1)
        XCTAssertEqual(outcome.stage, "cleared")
        XCTAssertTrue(outcome.passed)
        // Even when cleared through an injected gate, the entry itself never
        // claims to be G3 execution evidence.
        XCTAssertFalse(outcome.isExecutionEvidence)
    }

    func testGenerationNeverRunsWhenGateThrowsEvenIfProviderLooksLive() throws {
        let provider = liveProvider()
        var generated = 0
        XCTAssertThrowsError(
            try G3FirstGenerationEntry.run(
                provider: provider, request: request(),
                generate: { generated += 1 },
                isolation: { _, _ in throw RuntimeAttestationError.unregisteredLiveProvider("simigo.g3.swift-runtime-resource-provider.v1") }
            )
        )
        XCTAssertEqual(generated, 0)
    }

    // MARK: Refusal record is stable JSON for verbatim collection

    func testRefusalRecordEncodesToStableJSON() throws {
        let provider = liveProvider()
        var captured: G3GateOutcome?
        do {
            _ = try G3FirstGenerationEntry.run(provider: provider, request: request()) { XCTFail("must not generate") }
        } catch G3FirstGenerationEntry.EntryError.refused(let outcome) {
            captured = outcome
        }
        let outcome = try XCTUnwrap(captured)
        let data = try JSONEncoder().encode(outcome)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["gate", "stage", "passed", "generationCallCount", "isExecutionEvidence",
                    "reason", "failedChecks", "runID", "challengeNonce", "trustedLiveProviderCount"] {
            XCTAssertNotNil(obj[key], "missing JSON key \(key)")
        }
        XCTAssertEqual(obj["generationCallCount"] as? Int, 0)
        // Round-trips back to an equal value.
        let decoded = try JSONDecoder().decode(G3GateOutcome.self, from: data)
        XCTAssertEqual(decoded, outcome)
    }

    // MARK: Async executor seam — gate strictly before the awaited forward

    func testRunAsyncRefusesBeforeGenerationWithUnregisteredProvider() async throws {
        let provider = liveProvider()
        var generated = 0
        do {
            _ = try await G3FirstGenerationEntry.runAsync(
                provider: provider, request: try request()) {
                generated += 1
                return "should-not-run"
            }
            XCTFail("expected refusal")
        } catch G3FirstGenerationEntry.EntryError.refused(let outcome) {
            XCTAssertEqual(generated, 0)                 // forward never awaited
            XCTAssertEqual(outcome.generationCallCount, 0)
            XCTAssertEqual(outcome.stage, "provider_trust")
            XCTAssertFalse(outcome.passed)
            XCTAssertFalse(outcome.eligibleForRuntimeEvidence)
            XCTAssertEqual(outcome.trustedLiveProviderCount, 0)
        }
    }

    func testRunAsyncFixtureProviderIsHardRejectedNoGeneration() async throws {
        var generated = 0
        do {
            _ = try await G3FirstGenerationEntry.runAsync(
                provider: FixtureProvider(), request: try request()) {
                generated += 1
                return "should-not-run"
            }
            XCTFail("expected refusal")
        } catch G3FirstGenerationEntry.EntryError.refused(let outcome) {
            XCTAssertEqual(generated, 0)
            XCTAssertEqual(outcome.stage, "provider_trust")
            XCTAssertTrue(outcome.reason.contains("fixture"))
        }
    }

    func testRunAsyncEvaluateFailureRefusesWithNoGeneration() async throws {
        let provider = liveProvider()
        var generated = 0
        do {
            _ = try await G3FirstGenerationEntry.runAsync(
                provider: provider, request: try request(),
                generate: { generated += 1; return "x" },
                isolation: { _, _ in throw RuntimeAttestationError.isolationGateRefused(
                    ["distinct_kv_cache_instances"]) })
            XCTFail("expected refusal")
        } catch G3FirstGenerationEntry.EntryError.refused(let outcome) {
            XCTAssertEqual(generated, 0)
            XCTAssertEqual(outcome.generationCallCount, 0)
            XCTAssertEqual(outcome.stage, "evaluate")
            XCTAssertEqual(outcome.failedChecks, ["distinct_kv_cache_instances"])
        }
    }

    func testRunAsyncGenerationRunsOnlyAfterClearedGate() async throws {
        let provider = liveProvider()
        var generated = 0
        let pair = try await G3FirstGenerationEntry.runAsync(
            provider: provider, request: try request(),
            generate: { generated += 1; return "ran" },
            isolation: { _, _ in self.clearedReport() })
        XCTAssertEqual(generated, 1)                      // awaited only post-clear
        XCTAssertEqual(pair.value, "ran")
        XCTAssertEqual(pair.outcome.generationCallCount, 1)
        XCTAssertTrue(pair.outcome.passed)
        // Even a cleared executor run records no execution evidence from Python's
        // side and started nothing on its own authority.
        XCTAssertFalse(pair.outcome.isExecutionEvidence)
    }
}
