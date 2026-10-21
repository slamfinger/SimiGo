import Foundation

// G3-SPECIFIC ISOLATED EXECUTION ENTRY — the control point that turns the
// native gate from a standalone correct implementation into a checkpoint the
// G3 run must pass before any generation.
//
// Scope discipline:
//   * This entry is G3-only. Normal SimiGo inference does NOT route through it,
//     so an empty trust registry never changes unrelated production behavior.
//   * The gate runs BEFORE the first generation. If it refuses, generation is
//     never invoked and the recorded generation-call count stays zero.
//   * There is NO fallback. On refusal the entry throws a structured record; it
//     does not drop to a fixture, a synthetic observation, or a default.
//
// This file stays MLX-free and model-free so the control flow is unit-testable
// without loading a model. The concrete resource-reading adapter lives in the
// MLX layer (SimiGo2Experimental) and is intentionally NOT registered as a
// trusted provider here: until a real emitter is implemented, reviewed, and
// added to ``RuntimeProviderTrustPolicy``, every provider — including the one
// defined below — fails closed. Mock results are never recorded as real
// resource-isolation evidence.

// MARK: - Live resource probe (genuine runtime identity source)

/// The runtime that actually owns the model, tokenizer, KV/prefix caches and
/// mutable buffers answers these queries from live objects. The provider must
/// *pull* each value from a probe; it cannot accept a caller-supplied boolean
/// bundle or a pre-filled observation, and it cannot derive an instance id from
/// the arm label or a static config file. This is what makes an observation an
/// observation rather than an assertion.
public protocol RuntimeResourceProbe: Sendable {
    func workerPID() -> Int
    func isolationUnitID() -> String
    func modelInstanceID() -> String
    func modelContentSHA256() -> String
    func tokenizerInstanceID() -> String
    func tokenizerContentSHA256() -> String
    func weightsBufferInstanceID() -> String
    func kvCacheInstanceID() -> String
    func prefixCacheInstanceID() -> String
    func runtimeBufferInstanceID() -> String
    func kvCacheNamespace() -> String
    func prefixCacheNamespace() -> String
    func runtimeWriteRoot() -> String
    func generationInvocationsBeforeGate() -> Int
    func runtimeInitializedBeforeFirstGeneration() -> Bool
    func mutableResourceIDs() -> [String]
}

/// Assemble one arm's observation strictly by querying a live probe. Nothing
/// here is configurable: the only inputs are the probe's own answers.
public func runtimeResourceObservation(from probe: RuntimeResourceProbe) -> RuntimeResourceObservation {
    RuntimeResourceObservation(
        workerPID: probe.workerPID(),
        isolationUnitID: probe.isolationUnitID(),
        modelInstanceID: probe.modelInstanceID(),
        modelContentSHA256: probe.modelContentSHA256(),
        tokenizerInstanceID: probe.tokenizerInstanceID(),
        tokenizerContentSHA256: probe.tokenizerContentSHA256(),
        weightsBufferInstanceID: probe.weightsBufferInstanceID(),
        kvCacheInstanceID: probe.kvCacheInstanceID(),
        prefixCacheInstanceID: probe.prefixCacheInstanceID(),
        runtimeBufferInstanceID: probe.runtimeBufferInstanceID(),
        kvCacheNamespace: probe.kvCacheNamespace(),
        prefixCacheNamespace: probe.prefixCacheNamespace(),
        runtimeWriteRoot: probe.runtimeWriteRoot(),
        generationInvocationsBeforeGate: probe.generationInvocationsBeforeGate(),
        initializedBeforeFirstGeneration: probe.runtimeInitializedBeforeFirstGeneration(),
        mutableResourceIDs: probe.mutableResourceIDs()
    )
}

// MARK: - Live resource attestation provider (NOT registered as trusted)

/// A live worker provider that builds each arm's envelope by reading a probe.
/// It reports a live provider kind, but conforming to the protocol grants no
/// trust: with ``RuntimeProviderTrustPolicy/registeredLiveProviderTypes`` empty,
/// ``RuntimeIsolationGate/requireIsolation(provider:request:)`` refuses this
/// provider before it can ever authorize generation. This is deliberate — the
/// real emitter is not implemented or authorized yet, so no provider, mock or
/// otherwise, is allowed to clear the gate.
public struct LiveResourceAttestationProvider: RuntimeAttestationProvider {
    public let providerID: String
    public let providerKind: RuntimeProviderKind
    /// The emitter's own build identity (not the model weights); legitimately
    /// self-described by the reviewed exporter binary.
    public let sourceRevision: String
    public let sourceSHA256: String
    /// Probes are looked up per arm and supplied by the owning runtime.
    private let probes: [RuntimeArmID: any RuntimeResourceProbe]
    private let clock: @Sendable () -> String

    public init(
        providerID: String,
        providerKind: RuntimeProviderKind = .swiftMLXLiveWorker,
        sourceRevision: String,
        sourceSHA256: String,
        probes: [RuntimeArmID: any RuntimeResourceProbe],
        clock: @escaping @Sendable () -> String = LiveResourceAttestationProvider.utcNowISO8601
    ) {
        self.providerID = providerID
        self.providerKind = providerKind
        self.sourceRevision = sourceRevision
        self.sourceSHA256 = sourceSHA256
        self.probes = probes
        self.clock = clock
    }

    public static func utcNowISO8601() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }

    public func collect(_ request: AttestationRequest) throws -> [RuntimeAttestation] {
        var envelopes: [RuntimeAttestation] = []
        // Produce attestations strictly in the request's expected-arm order.
        for arm in request.expectedArms {
            guard let probe = probes[arm] else {
                throw RuntimeAttestationError.invalidAttestation(
                    "no live runtime probe available for arm \(arm.rawValue)")
            }
            let observation = runtimeResourceObservation(from: probe)
            envelopes.append(RuntimeAttestation(
                contractID: request.contractID,
                contractVersion: request.contractVersion,
                providerID: providerID,
                providerKind: providerKind,
                runID: request.runID,
                challengeNonce: request.challengeNonce,
                armID: arm,
                capturedAtUTC: clock(),
                sourceRevision: sourceRevision,
                sourceSHA256: sourceSHA256,
                observation: observation))
        }
        return envelopes
    }
}

// MARK: - Refusal / outcome record (collected verbatim by the harness)

/// A machine-readable outcome the G3 entry emits. It is intentionally a small,
/// stable schema (Codable) so the native entry can print it as JSON and the
/// Python orchestrator can collect it without reinterpretation. It never claims
/// execution evidence on a refusal.
public struct G3GateOutcome: Codable, Hashable, Sendable {
    public let gate: String
    public let stage: String              // request|provider_trust|collect|validate|evaluate|cleared
    public let passed: Bool
    public let eligibleForRuntimeEvidence: Bool
    public let evidenceClass: String
    public let generationCallCount: Int   // 0 unless the gate cleared and generate ran
    public let modelGenerationStartedByGate: Bool
    public let isExecutionEvidence: Bool
    public let reason: String
    public let failedChecks: [String]
    public let runID: String
    public let challengeNonce: String
    public let providerID: String
    public let providerKind: String
    public let trustedLiveProviderCount: Int

    public init(
        gate: String,
        stage: String,
        passed: Bool,
        eligibleForRuntimeEvidence: Bool,
        evidenceClass: String,
        generationCallCount: Int,
        modelGenerationStartedByGate: Bool,
        isExecutionEvidence: Bool,
        reason: String,
        failedChecks: [String],
        runID: String,
        challengeNonce: String,
        providerID: String,
        providerKind: String,
        trustedLiveProviderCount: Int
    ) {
        self.gate = gate
        self.stage = stage
        self.passed = passed
        self.eligibleForRuntimeEvidence = eligibleForRuntimeEvidence
        self.evidenceClass = evidenceClass
        self.generationCallCount = generationCallCount
        self.modelGenerationStartedByGate = modelGenerationStartedByGate
        self.isExecutionEvidence = isExecutionEvidence
        self.reason = reason
        self.failedChecks = failedChecks
        self.runID = runID
        self.challengeNonce = challengeNonce
        self.providerID = providerID
        self.providerKind = providerKind
        self.trustedLiveProviderCount = trustedLiveProviderCount
    }
}

// MARK: - The G3 first-generation control point

public enum G3FirstGenerationEntry {
    public enum EntryError: Error, Equatable {
        case refused(G3GateOutcome)
    }

    /// Public entry: gate before generation, using the real production gate.
    /// Because the trust registry is empty this currently always refuses, so
    /// `generate` is never called and the generation count stays zero.
    public static func run(
        provider: RuntimeAttestationProvider,
        request: AttestationRequest,
        generate: () throws -> Void
    ) throws -> G3GateOutcome {
        try run(
            provider: provider, request: request, generate: generate,
            isolation: { p, r in try RuntimeIsolationGate.requireIsolation(provider: p, request: r) })
    }

    /// Injectable-isolation variant so a test can prove ordering (generation
    /// happens only after a cleared gate) without registering a fictitious
    /// trusted provider into the shipping registry.
    static func run(
        provider: RuntimeAttestationProvider,
        request: AttestationRequest,
        generate: () throws -> Void,
        isolation: (RuntimeAttestationProvider, AttestationRequest) throws -> GateReport
    ) throws -> G3GateOutcome {
        let report: GateReport
        do {
            report = try isolation(provider, request)
        } catch let error as RuntimeAttestationError {
            throw EntryError.refused(refusal(error: error, provider: provider, request: request))
        } catch {
            throw EntryError.refused(refusal(
                error: .invalidAttestation("isolation failed: \(error)"),
                provider: provider, request: request))
        }

        // The gate must have actually cleared AND be eligible before generation.
        guard report.passed, report.eligibleForRuntimeEvidence else {
            throw EntryError.refused(refusal(
                error: .isolationGateRefused(report.failedChecks),
                provider: provider, request: request))
        }

        // Generation is reached ONLY here, strictly after a cleared gate.
        try generate()

        return clearedOutcome(report: report, provider: provider, request: request)
    }

    /// Async variant for execution paths that perform generation with `await`
    /// (e.g. the MLX executor's forward loop). The gate is evaluated strictly
    /// BEFORE the async `generate` closure is awaited: on refusal the closure is
    /// never run, so the real generation-call count stays zero. Normal inference
    /// does not route through this entry.
    public static func runAsync<T>(
        provider: RuntimeAttestationProvider,
        request: AttestationRequest,
        generate: () async throws -> T
    ) async throws -> (outcome: G3GateOutcome, value: T) {
        try await runAsync(
            provider: provider, request: request, generate: generate,
            isolation: { p, r in try RuntimeIsolationGate.requireIsolation(provider: p, request: r) })
    }

    /// Injectable-isolation async variant so a test can prove ordering without
    /// registering a fictitious trusted provider into the shipping registry.
    static func runAsync<T>(
        provider: RuntimeAttestationProvider,
        request: AttestationRequest,
        generate: () async throws -> T,
        isolation: (RuntimeAttestationProvider, AttestationRequest) throws -> GateReport
    ) async throws -> (outcome: G3GateOutcome, value: T) {
        let report: GateReport
        do {
            report = try isolation(provider, request)
        } catch let error as RuntimeAttestationError {
            throw EntryError.refused(refusal(error: error, provider: provider, request: request))
        } catch {
            throw EntryError.refused(refusal(
                error: .invalidAttestation("isolation failed: \(error)"),
                provider: provider, request: request))
        }
        guard report.passed, report.eligibleForRuntimeEvidence else {
            throw EntryError.refused(refusal(
                error: .isolationGateRefused(report.failedChecks),
                provider: provider, request: request))
        }
        // Awaited ONLY after a cleared gate — this is the executor's real forward.
        let value = try await generate()
        return (clearedOutcome(report: report, provider: provider, request: request), value)
    }

    static func clearedOutcome(
        report: GateReport,
        provider: RuntimeAttestationProvider,
        request: AttestationRequest
    ) -> G3GateOutcome {
        G3GateOutcome(
            gate: report.gate,
            stage: "cleared",
            passed: true,
            eligibleForRuntimeEvidence: report.eligibleForRuntimeEvidence,
            evidenceClass: report.evidenceClass,
            generationCallCount: 1,
            modelGenerationStartedByGate: report.modelGenerationStartedByGate,
            isExecutionEvidence: false,   // the entry itself is not G3 execution evidence
            reason: "isolation gate cleared; generation entered",
            failedChecks: report.failedChecks,
            runID: request.runID,
            challengeNonce: request.challengeNonce,
            providerID: provider.providerID,
            providerKind: provider.providerKind.rawValue,
            trustedLiveProviderCount: RuntimeProviderTrustPolicy.registeredLiveProviderTypes.count)
    }

    static func refusal(
        error: RuntimeAttestationError,
        provider: RuntimeAttestationProvider,
        request: AttestationRequest
    ) -> G3GateOutcome {
        let stage: String
        let reason: String
        let failedChecks: [String]
        switch error {
        case let .invalidRequest(msg):
            stage = "request"; reason = msg; failedChecks = []
        case let .fixtureProviderRejected(msg):
            stage = "provider_trust"; reason = msg; failedChecks = []
        case let .unregisteredLiveProvider(msg):
            stage = "provider_trust"; reason = msg; failedChecks = []
        case let .providerTypeMismatch(id, expected, got):
            stage = "provider_trust"
            reason = "provider \(id) type mismatch: expected \(expected), got \(got)"
            failedChecks = []
        case let .invalidAttestation(msg):
            stage = "collect_or_validate"; reason = msg; failedChecks = []
        case let .isolationGateRefused(checks):
            stage = "evaluate"; reason = "isolation predicates failed"; failedChecks = checks
        }
        return G3GateOutcome(
            gate: RuntimeIsolationGate.gateID,
            stage: stage,
            passed: false,
            eligibleForRuntimeEvidence: false,
            evidenceClass: "gate_refused_before_generation",
            generationCallCount: 0,   // refused: never generated
            modelGenerationStartedByGate: false,
            isExecutionEvidence: false,
            reason: reason,
            failedChecks: failedChecks,
            runID: request.runID,
            challengeNonce: request.challengeNonce,
            providerID: provider.providerID,
            providerKind: provider.providerKind.rawValue,
            trustedLiveProviderCount: RuntimeProviderTrustPolicy.registeredLiveProviderTypes.count)
    }
}
