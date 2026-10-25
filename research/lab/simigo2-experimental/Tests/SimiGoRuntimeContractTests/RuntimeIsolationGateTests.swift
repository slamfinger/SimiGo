import XCTest
@testable import SimiGoRuntimeContract

/// Native Swift port of the research-stage gate's rejection rules. The pure
/// evaluator is exercised with synthetic observations (that is what it is for);
/// the production entry is exercised ONLY through providers that must be refused,
/// because no live emitter is registered. A fake provider is never a trusted one.
final class RuntimeIsolationGateTests: XCTestCase {

    static let modelSHA = String(repeating: "a", count: 64)
    static let tokenizerSHA = String(repeating: "b", count: 64)
    static let sourceSHA = String(repeating: "c", count: 64)

    // MARK: builders

    private func arm(
        _ suffix: String,
        _ pid: Int,
        _ root: String,
        kvInstance: String? = nil,
        prefixNamespace: String? = nil,
        tokenizerInstance: String? = nil,
        kvNamespace: String? = nil,
        isolationUnit: String? = nil,
        mutableIDs: [String]? = nil,
        modelContent: String? = nil,
        tokenizerContent: String? = nil,
        initialized: Bool? = nil,
        invocations: Int? = nil
    ) -> RuntimeResourceObservation {
        RuntimeResourceObservation(
            workerPID: pid,
            isolationUnitID: isolationUnit ?? "sandbox-\(suffix)",
            modelInstanceID: "model-\(suffix)",
            modelContentSHA256: modelContent ?? Self.modelSHA,
            tokenizerInstanceID: tokenizerInstance ?? "tokenizer-\(suffix)",
            tokenizerContentSHA256: tokenizerContent ?? Self.tokenizerSHA,
            weightsBufferInstanceID: "weights-\(suffix)",
            kvCacheInstanceID: kvInstance ?? "kv-\(suffix)",
            prefixCacheInstanceID: "prefix-\(suffix)",
            runtimeBufferInstanceID: "rtbuf-\(suffix)",
            kvCacheNamespace: kvNamespace ?? "kv-ns-\(suffix)",
            prefixCacheNamespace: prefixNamespace ?? "prefix-ns-\(suffix)",
            runtimeWriteRoot: root,
            generationInvocationsBeforeGate: invocations ?? 0,
            initializedBeforeFirstGeneration: initialized ?? true,
            mutableResourceIDs: mutableIDs ?? ["mutable-\(suffix)-model", "mutable-\(suffix)-kv"]
        )
    }

    private func observation(
        _ label: String,
        _ observation: RuntimeResourceObservation,
        source: String? = nil,
        fields: Set<String>? = nil
    ) -> GateObservation {
        GateObservation(
            armID: RuntimeArmID(label),
            observation: observation,
            attestationSource: source ?? "live-probe-\(label)",
            observedFields: fields ?? RuntimeIsolationGate.requiredFieldNames
        )
    }

    private func pair() -> [GateObservation] {
        [
            observation("ES+IS", arm("a", 41001, "/tmp/simigo-g3/es-is")),
            observation("IS-only", arm("b", 41002, "/tmp/simigo-g3/is-only")),
        ]
    }

    // MARK: happy path

    func test_happy_path_passes_all_checks_but_is_not_live_evidence() {
        let report = RuntimeIsolationGate.evaluate(pair())
        XCTAssertTrue(report.passed, "\(report.failedChecks)")
        XCTAssertEqual(report.checkCount, 19)
        XCTAssertEqual(report.failedCount, 0)
        XCTAssertEqual(report.passedCount, 19)
        XCTAssertTrue(report.readOnlyModelArtifactSharingAllowed)
        // The core anti-false-green invariant: even a fully-true pure result is
        // never eligible as runtime evidence.
        XCTAssertFalse(report.eligibleForRuntimeEvidence)
        XCTAssertEqual(report.evidenceClass, "untrusted_observation_evaluation")
        XCTAssertFalse(report.modelGenerationStartedByGate)
    }

    // MARK: two-arm isolation negatives

    func test_shared_kv_instance_fails() {
        let first = arm("a", 41001, "/tmp/simigo-g3/es-is")
        let second = arm("b", 41002, "/tmp/simigo-g3/is-only",
                         kvInstance: first.kvCacheInstanceID)
        let report = RuntimeIsolationGate.evaluate([
            observation("ES+IS", first), observation("IS-only", second),
        ])
        XCTAssertFalse(report.checks["distinct_kv_cache_instances"] ?? true)
    }

    func test_shared_prefix_namespace_fails() {
        let first = arm("a", 41001, "/tmp/simigo-g3/es-is")
        let second = arm("b", 41002, "/tmp/simigo-g3/is-only",
                         prefixNamespace: first.prefixCacheNamespace)
        let report = RuntimeIsolationGate.evaluate([
            observation("ES+IS", first), observation("IS-only", second),
        ])
        XCTAssertFalse(report.checks["distinct_prefix_cache_namespaces"] ?? true)
    }

    func test_shared_tokenizer_instance_fails() {
        let first = arm("a", 41001, "/tmp/simigo-g3/es-is")
        let second = arm("b", 41002, "/tmp/simigo-g3/is-only",
                         tokenizerInstance: first.tokenizerInstanceID)
        let report = RuntimeIsolationGate.evaluate([
            observation("ES+IS", first), observation("IS-only", second),
        ])
        XCTAssertFalse(report.checks["distinct_tokenizer_instances"] ?? true)
    }

    func test_shared_mutable_resource_id_fails() {
        let first = arm("a", 41001, "/tmp/simigo-g3/es-is")
        let second = arm("b", 41002, "/tmp/simigo-g3/is-only",
                         mutableIDs: ["mutable-b-kv", first.mutableResourceIDs[0]])
        let report = RuntimeIsolationGate.evaluate([
            observation("ES+IS", first), observation("IS-only", second),
        ])
        XCTAssertFalse(report.checks["no_shared_mutable_resources"] ?? true)
    }

    func test_same_model_content_allowed_but_different_fails() {
        XCTAssertTrue(RuntimeIsolationGate.evaluate(pair()).checks["same_valid_model_content"] ?? false)
        let first = arm("a", 41001, "/tmp/simigo-g3/es-is")
        let second = arm("b", 41002, "/tmp/simigo-g3/is-only",
                         modelContent: String(repeating: "d", count: 64))
        XCTAssertFalse(RuntimeIsolationGate.evaluate([
            observation("ES+IS", first), observation("IS-only", second),
        ]).checks["same_valid_model_content"] ?? true)
    }

    func test_malformed_tokenizer_content_fails() {
        let first = arm("a", 41001, "/tmp/simigo-g3/es-is")
        let second = arm("b", 41002, "/tmp/simigo-g3/is-only", tokenizerContent: "not-a-sha256")
        XCTAssertFalse(RuntimeIsolationGate.evaluate([
            observation("ES+IS", first), observation("IS-only", second),
        ]).checks["same_valid_tokenizer_content"] ?? true)
    }

    func test_nested_write_roots_fail() {
        let first = arm("a", 41001, "/tmp/simigo-g3/es-is")
        let second = arm("b", 41002, "/tmp/simigo-g3/es-is/child")
        XCTAssertFalse(RuntimeIsolationGate.evaluate([
            observation("ES+IS", first), observation("IS-only", second),
        ]).checks["disjoint_runtime_write_roots"] ?? true)
    }

    func test_identical_write_roots_fail() {
        let first = arm("a", 41001, "/tmp/simigo-g3/shared")
        let second = arm("b", 41002, "/tmp/simigo-g3/shared")
        XCTAssertFalse(RuntimeIsolationGate.evaluate([
            observation("ES+IS", first), observation("IS-only", second),
        ]).checks["disjoint_runtime_write_roots"] ?? true)
    }

    func test_same_worker_pid_fails() {
        let first = arm("a", 41001, "/tmp/simigo-g3/es-is")
        let second = arm("b", 41001, "/tmp/simigo-g3/is-only")
        XCTAssertFalse(RuntimeIsolationGate.evaluate([
            observation("ES+IS", first), observation("IS-only", second),
        ]).checks["distinct_live_worker_pids"] ?? true)
    }

    func test_generation_before_gate_fails() {
        let first = arm("a", 41001, "/tmp/simigo-g3/es-is")
        let second = arm("b", 41002, "/tmp/simigo-g3/is-only", invocations: 1)
        XCTAssertFalse(RuntimeIsolationGate.evaluate([
            observation("ES+IS", first), observation("IS-only", second),
        ]).checks["zero_generation_invocations_before_gate"] ?? true)
    }

    func test_runtime_not_initialized_fails() {
        let first = arm("a", 41001, "/tmp/simigo-g3/es-is", initialized: false)
        let second = arm("b", 41002, "/tmp/simigo-g3/is-only")
        XCTAssertFalse(RuntimeIsolationGate.evaluate([
            observation("ES+IS", first), observation("IS-only", second),
        ]).checks["runtime_initialized_before_generation"] ?? true)
    }

    func test_empty_kv_namespace_fails() {
        let first = arm("a", 41001, "/tmp/simigo-g3/es-is")
        let second = arm("b", 41002, "/tmp/simigo-g3/is-only", kvNamespace: "")
        XCTAssertFalse(RuntimeIsolationGate.evaluate([
            observation("ES+IS", first), observation("IS-only", second),
        ]).checks["distinct_kv_cache_namespaces"] ?? true)
    }

    func test_missing_provenance_field_fails() {
        let first = arm("a", 41001, "/tmp/simigo-g3/es-is")
        let second = arm("b", 41002, "/tmp/simigo-g3/is-only")
        let reduced = RuntimeIsolationGate.requiredFieldNames.subtracting(["kv_cache_instance_id"])
        let report = RuntimeIsolationGate.evaluate([
            observation("ES+IS", first),
            observation("IS-only", second, fields: reduced),
        ])
        XCTAssertFalse(report.checks["live_attestation_provenance_complete"] ?? true)
    }

    func test_empty_attestation_source_fails() {
        let first = arm("a", 41001, "/tmp/simigo-g3/es-is")
        let second = arm("b", 41002, "/tmp/simigo-g3/is-only")
        let report = RuntimeIsolationGate.evaluate([
            observation("ES+IS", first),
            observation("IS-only", second, source: ""),
        ])
        XCTAssertFalse(report.checks["live_attestation_provenance_complete"] ?? true)
    }

    func test_wrong_arm_set_fails() {
        let report = RuntimeIsolationGate.evaluate([
            observation("ES+IS", arm("a", 41001, "/tmp/simigo-g3/es-is")),
            observation("OTHER", arm("b", 41002, "/tmp/simigo-g3/is-only")),
        ])
        XCTAssertFalse(report.checks["exact_two_expected_arms"] ?? true)
    }

    func test_empty_observations_fail_closed() {
        let report = RuntimeIsolationGate.evaluate([])
        XCTAssertFalse(report.passed)
        XCTAssertEqual(report.failedCount, report.checkCount)
        XCTAssertFalse(report.eligibleForRuntimeEvidence)
    }

    // MARK: provider trust — the production entry must fail closed

    func test_trust_registry_is_intentionally_empty() {
        XCTAssertTrue(RuntimeProviderTrustPolicy.registeredLiveProviderTypes.isEmpty)
    }

    func test_declared_fixture_provider_is_hard_rejected() {
        let request = try! AttestationRequest(runID: "g3-test", challengeNonce: "nonce-1")
        XCTAssertThrowsError(
            try RuntimeIsolationGate.requireIsolation(provider: DeclaredFixtureProvider(), request: request)
        ) { error in
            guard case RuntimeAttestationError.fixtureProviderRejected = error else {
                return XCTFail("expected fixtureProviderRejected, got \(error)")
            }
        }
    }

    func test_unregistered_live_claim_provider_is_rejected() {
        // A provider that claims a live kind but is not source-registered must
        // still be refused: claiming liveness is not proof of liveness.
        let request = try! AttestationRequest(runID: "g3-test", challengeNonce: "nonce-1")
        XCTAssertThrowsError(
            try RuntimeIsolationGate.requireIsolation(provider: UnregisteredLiveClaimProvider(), request: request)
        ) { error in
            guard case RuntimeAttestationError.unregisteredLiveProvider = error else {
                return XCTFail("expected unregisteredLiveProvider, got \(error)")
            }
        }
    }

    func test_production_entry_refuses_for_every_available_provider_while_registry_empty() {
        let request = try! AttestationRequest(runID: "g3-test", challengeNonce: "nonce-1")
        for provider in [DeclaredFixtureProvider(), UnregisteredLiveClaimProvider()] as [RuntimeAttestationProvider] {
            XCTAssertThrowsError(try RuntimeIsolationGate.requireIsolation(provider: provider, request: request))
        }
    }

    // MARK: envelope validation negatives

    func test_batch_requires_exact_arm_count() throws {
        let request = try AttestationRequest(runID: "g3-test", challengeNonce: "nonce-1")
        let only = [goodEnvelope(request, label: "ES+IS", suffix: "a", pid: 41001,
                                 root: "/tmp/simigo-g3/es-is")]
        XCTAssertThrowsError(try RuntimeIsolationGate.validateBatch(
            only, request, expectedProviderID: "p", expectedProviderKind: .pythonLiveWorker
        )) { error in
            guard case RuntimeAttestationError.invalidAttestation = error else {
                return XCTFail("expected invalidAttestation, got \(error)")
            }
        }
    }

    func test_batch_rejects_wrong_arm_order() throws {
        let request = try AttestationRequest(runID: "g3-test", challengeNonce: "nonce-1")
        let swapped = [
            goodEnvelope(request, label: "IS-only", suffix: "b", pid: 41002, root: "/tmp/simigo-g3/is-only"),
            goodEnvelope(request, label: "ES+IS", suffix: "a", pid: 41001, root: "/tmp/simigo-g3/es-is"),
        ]
        XCTAssertThrowsError(try RuntimeIsolationGate.validateBatch(
            swapped, request, expectedProviderID: "p", expectedProviderKind: .pythonLiveWorker
        )) { error in
            guard case RuntimeAttestationError.invalidAttestation(let message) = error else {
                return XCTFail("expected invalidAttestation, got \(error)")
            }
            XCTAssertTrue(message.contains("arms/order mismatch"))
        }
    }

    func test_batch_rejects_stale_challenge_nonce() throws {
        let request = try AttestationRequest(runID: "g3-test", challengeNonce: "nonce-1")
        let good = goodEnvelope(request, label: "ES+IS", suffix: "a", pid: 41001, root: "/tmp/simigo-g3/es-is")
        let stale = RuntimeAttestation(
            contractID: good.contractID, contractVersion: good.contractVersion,
            providerID: good.providerID, providerKind: good.providerKind,
            runID: good.runID, challengeNonce: "stale-nonce",
            armID: good.armID, capturedAtUTC: good.capturedAtUTC,
            sourceRevision: good.sourceRevision, sourceSHA256: good.sourceSHA256,
            observation: good.observation)
        let batch = [stale, goodEnvelope(request, label: "IS-only", suffix: "b", pid: 41002, root: "/tmp/simigo-g3/is-only")]
        XCTAssertThrowsError(try RuntimeIsolationGate.validateBatch(
            batch, request, expectedProviderID: "p", expectedProviderKind: .pythonLiveWorker
        )) { error in
            guard case RuntimeAttestationError.invalidAttestation(let message) = error else {
                return XCTFail("got \(error)")
            }
            XCTAssertTrue(message.contains("run_id/challenge_nonce mismatch"))
        }
    }

    func test_batch_rejects_malformed_source_digest() throws {
        let request = try AttestationRequest(runID: "g3-test", challengeNonce: "nonce-1")
        let first = goodEnvelope(request, label: "ES+IS", suffix: "a", pid: 41001, root: "/tmp/simigo-g3/es-is",
                                 sourceSHA: "not-a-sha")
        let batch = [first, goodEnvelope(request, label: "IS-only", suffix: "b", pid: 41002, root: "/tmp/simigo-g3/is-only")]
        XCTAssertThrowsError(try RuntimeIsolationGate.validateBatch(
            batch, request, expectedProviderID: "p", expectedProviderKind: .pythonLiveWorker
        )) { error in
            guard case RuntimeAttestationError.invalidAttestation(let message) = error else {
                return XCTFail("got \(error)")
            }
            XCTAssertTrue(message.contains("source_sha256"))
        }
    }

    func test_batch_rejects_non_utc_capture() throws {
        let request = try AttestationRequest(runID: "g3-test", challengeNonce: "nonce-1")
        let first = goodEnvelope(request, label: "ES+IS", suffix: "a", pid: 41001, root: "/tmp/simigo-g3/es-is",
                                 capturedAt: "2026-10-20T10:00:00+02:00")
        let batch = [first, goodEnvelope(request, label: "IS-only", suffix: "b", pid: 41002, root: "/tmp/simigo-g3/is-only")]
        XCTAssertThrowsError(try RuntimeIsolationGate.validateBatch(
            batch, request, expectedProviderID: "p", expectedProviderKind: .pythonLiveWorker
        )) { error in
            guard case RuntimeAttestationError.invalidAttestation(let message) = error else {
                return XCTFail("got \(error)")
            }
            XCTAssertTrue(message.contains("captured_at_utc"))
        }
    }

    func test_batch_validates_a_wellformed_live_envelope() throws {
        let request = try AttestationRequest(runID: "g3-test", challengeNonce: "nonce-1")
        let batch = [
            goodEnvelope(request, label: "ES+IS", suffix: "a", pid: 41001, root: "/tmp/simigo-g3/es-is"),
            goodEnvelope(request, label: "IS-only", suffix: "b", pid: 41002, root: "/tmp/simigo-g3/is-only"),
        ]
        let observations = try RuntimeIsolationGate.validateBatch(
            batch, request, expectedProviderID: "p", expectedProviderKind: .pythonLiveWorker)
        XCTAssertEqual(observations.map { $0.armID.rawValue }, ["ES+IS", "IS-only"])
        // Envelope-derived provenance, not caller-supplied.
        XCTAssertEqual(observations.first?.attestationSource, "p@rev-1")
    }

    // MARK: envelope helper

    private func goodEnvelope(
        _ request: AttestationRequest,
        label: String, suffix: String, pid: Int, root: String,
        providerID: String = "p",
        kind: RuntimeProviderKind = .pythonLiveWorker,
        sourceSHA: String = String(repeating: "c", count: 64),
        capturedAt: String = "2026-10-20T10:00:00Z"
    ) -> RuntimeAttestation {
        RuntimeAttestation(
            contractID: request.contractID,
            contractVersion: request.contractVersion,
            providerID: providerID,
            providerKind: kind,
            runID: request.runID,
            challengeNonce: request.challengeNonce,
            armID: RuntimeArmID(label),
            capturedAtUTC: capturedAt,
            sourceRevision: "rev-1",
            sourceSHA256: sourceSHA,
            observation: arm(suffix, pid, root)
        )
    }
}

// A provider that declares a fixture/test-double kind. Its `collect` would hand
// back perfectly-formed observations, yet it must never clear the production
// gate — the kind itself is disqualifying.
final class DeclaredFixtureProvider: RuntimeAttestationProvider {
    let providerID = "test.fixture.provider"
    let providerKind: RuntimeProviderKind = .fixture
    func collect(_ request: AttestationRequest) throws -> [RuntimeAttestation] { [] }
}

// A provider that claims a live kind but is not in the (empty) trust registry.
// Claiming liveness must not be enough to be trusted.
final class UnregisteredLiveClaimProvider: RuntimeAttestationProvider {
    let providerID = "simigo.g3.python-live-worker.v1"
    let providerKind: RuntimeProviderKind = .pythonLiveWorker
    func collect(_ request: AttestationRequest) throws -> [RuntimeAttestation] { [] }
}
