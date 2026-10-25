import Foundation

// NATIVE RUNTIME ISOLATION GATE — authoritative isolation boundary for the
// Swift execution chain.
//
// This is the Swift counterpart of the research-stage Python gate. The gate
// lives here, at the runtime contract layer, because the code that owns the
// model, tokenizer, KV/prefix caches and mutable weight buffers is the code
// that must prove those resources are isolated between the ES+IS and IS-only
// arms. A Python orchestrator can at best observe values a Swift worker
// exports; it cannot prove that Swift-internal mutable resources are not
// shared, and a check made in Python before a later Swift generate call leaves
// a time-of-check / time-of-use gap. Therefore the real gate runs inside the
// Swift execution path, immediately after the backend is initialized and
// strictly before the first generation.
//
// This file is intentionally MLX-free and model-free. It defines the
// attestation envelope, the transport-neutral provider contract, the trust
// registry, and the pure isolation predicates. The concrete live emitter that
// samples real Swift/MLX resource handles is NOT implemented here and is not
// authorized yet; the trust registry below is deliberately empty so the
// production entry fails closed until such an emitter is implemented, reviewed,
// and registered.

// MARK: - Provider identity

/// Discriminates who produced an attestation. Only the two live worker kinds
/// may ever be treated as runtime evidence; the rest are test/synthetic kinds
/// that must never reach a production decision.
public enum RuntimeProviderKind: String, Hashable, Sendable {
    case pythonLiveWorker = "python-live-worker"
    case swiftMLXLiveWorker = "swift-mlx-live-worker"
    case fixture
    case testDouble = "test-double"
    case synthetic
    case replay

    public var isLive: Bool {
        self == .pythonLiveWorker || self == .swiftMLXLiveWorker
    }

    public var isFixture: Bool {
        switch self {
        case .fixture, .testDouble, .synthetic, .replay:
            return true
        case .pythonLiveWorker, .swiftMLXLiveWorker:
            return false
        }
    }
}

/// A stable label for one arm under test.
public struct RuntimeArmID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
}

// MARK: - Strongly-typed runtime observation

/// One arm's resource observation. Every field is required and concrete:
/// a caller cannot submit "a set of plausible booleans". The instance ids and
/// content digests must be sampled from actual runtime objects; ids for model
/// instances and mutable buffers may not be derived from the arm label or a
/// static configuration file.
public struct RuntimeResourceObservation: Hashable, Sendable {
    public let workerPID: Int
    public let isolationUnitID: String
    public let modelInstanceID: String
    public let modelContentSHA256: String
    public let tokenizerInstanceID: String
    public let tokenizerContentSHA256: String
    public let weightsBufferInstanceID: String
    public let kvCacheInstanceID: String
    public let prefixCacheInstanceID: String
    public let runtimeBufferInstanceID: String
    public let kvCacheNamespace: String
    public let prefixCacheNamespace: String
    public let runtimeWriteRoot: String
    public let generationInvocationsBeforeGate: Int
    public let initializedBeforeFirstGeneration: Bool
    public let mutableResourceIDs: [String]

    public init(
        workerPID: Int,
        isolationUnitID: String,
        modelInstanceID: String,
        modelContentSHA256: String,
        tokenizerInstanceID: String,
        tokenizerContentSHA256: String,
        weightsBufferInstanceID: String,
        kvCacheInstanceID: String,
        prefixCacheInstanceID: String,
        runtimeBufferInstanceID: String,
        kvCacheNamespace: String,
        prefixCacheNamespace: String,
        runtimeWriteRoot: String,
        generationInvocationsBeforeGate: Int,
        initializedBeforeFirstGeneration: Bool,
        mutableResourceIDs: [String]
    ) {
        self.workerPID = workerPID
        self.isolationUnitID = isolationUnitID
        self.modelInstanceID = modelInstanceID
        self.modelContentSHA256 = modelContentSHA256
        self.tokenizerInstanceID = tokenizerInstanceID
        self.tokenizerContentSHA256 = tokenizerContentSHA256
        self.weightsBufferInstanceID = weightsBufferInstanceID
        self.kvCacheInstanceID = kvCacheInstanceID
        self.prefixCacheInstanceID = prefixCacheInstanceID
        self.runtimeBufferInstanceID = runtimeBufferInstanceID
        self.kvCacheNamespace = kvCacheNamespace
        self.prefixCacheNamespace = prefixCacheNamespace
        self.runtimeWriteRoot = runtimeWriteRoot
        self.generationInvocationsBeforeGate = generationInvocationsBeforeGate
        self.initializedBeforeFirstGeneration = initializedBeforeFirstGeneration
        self.mutableResourceIDs = mutableResourceIDs
    }
}

/// Observation plus the provenance the evaluator reasons about. In the pure
/// research path the caller supplies `observedFields` and `attestationSource`,
/// which is exactly why the pure path is never treated as live evidence. In the
/// production path both are derived from the validated envelope, not the caller.
public struct GateObservation: Hashable, Sendable {
    public let armID: RuntimeArmID
    public let observation: RuntimeResourceObservation
    public let attestationSource: String
    public let observedFields: Set<String>

    public init(
        armID: RuntimeArmID,
        observation: RuntimeResourceObservation,
        attestationSource: String,
        observedFields: Set<String>
    ) {
        self.armID = armID
        self.observation = observation
        self.attestationSource = attestationSource
        self.observedFields = observedFields
    }
}

// MARK: - Attestation envelope, request, provider

public struct AttestationRequest: Hashable, Sendable {
    public let runID: String
    public let challengeNonce: String
    public let expectedArms: [RuntimeArmID]
    public let contractID: String
    public let contractVersion: Int

    public init(
        runID: String,
        challengeNonce: String,
        expectedArms: [RuntimeArmID] = RuntimeIsolationGate.defaultExpectedArms,
        contractID: String = RuntimeIsolationGate.attestationContractID,
        contractVersion: Int = RuntimeIsolationGate.attestationContractVersion
    ) throws {
        guard !runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RuntimeAttestationError.invalidRequest("run_id must be non-empty")
        }
        guard !challengeNonce.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RuntimeAttestationError.invalidRequest("challenge_nonce must be non-empty")
        }
        guard expectedArms.count == 2, Set(expectedArms).count == 2 else {
            throw RuntimeAttestationError.invalidRequest(
                "expected_arms must name exactly two distinct arms")
        }
        self.runID = runID
        self.challengeNonce = challengeNonce
        self.expectedArms = expectedArms
        self.contractID = contractID
        self.contractVersion = contractVersion
    }
}

/// One arm's envelope, exported by a live worker before generation.
/// `sourceSHA256` binds the concrete exporter/build identity, not model weights.
public struct RuntimeAttestation: Hashable, Sendable {
    public let contractID: String
    public let contractVersion: Int
    public let providerID: String
    public let providerKind: RuntimeProviderKind
    public let runID: String
    public let challengeNonce: String
    public let armID: RuntimeArmID
    public let capturedAtUTC: String
    public let sourceRevision: String
    public let sourceSHA256: String
    public let observation: RuntimeResourceObservation

    public init(
        contractID: String,
        contractVersion: Int,
        providerID: String,
        providerKind: RuntimeProviderKind,
        runID: String,
        challengeNonce: String,
        armID: RuntimeArmID,
        capturedAtUTC: String,
        sourceRevision: String,
        sourceSHA256: String,
        observation: RuntimeResourceObservation
    ) {
        self.contractID = contractID
        self.contractVersion = contractVersion
        self.providerID = providerID
        self.providerKind = providerKind
        self.runID = runID
        self.challengeNonce = challengeNonce
        self.armID = armID
        self.capturedAtUTC = capturedAtUTC
        self.sourceRevision = sourceRevision
        self.sourceSHA256 = sourceSHA256
        self.observation = observation
    }
}

/// Transport-neutral provider contract. A concrete provider must collect after
/// backend/model init and immediately before the first generation, and report a
/// real runtime generation count of zero at collection time. Conforming to this
/// protocol does NOT grant trust: the concrete type must also be registered in
/// ``RuntimeProviderTrustPolicy``.
public protocol RuntimeAttestationProvider: Sendable {
    var providerID: String { get }
    var providerKind: RuntimeProviderKind { get }
    func collect(_ request: AttestationRequest) throws -> [RuntimeAttestation]
}

// MARK: - Errors

public enum RuntimeAttestationError: Error, Equatable {
    case invalidRequest(String)
    case fixtureProviderRejected(String)
    case unregisteredLiveProvider(String)
    case providerTypeMismatch(providerID: String, expected: String, got: String)
    case invalidAttestation(String)
    case isolationGateRefused([String])
}

// MARK: - Trust registry

/// Exact concrete-type bindings that are allowed to serve live evidence.
///
/// Trust is granted by *type identity*, not by a caller-declared name or a
/// `providerKind == .isLive` flag: the value stored here is a real Swift
/// metatype that must be visible at compile time inside this module, and a
/// provider is only trusted when `Swift.type(of: provider)` is *that exact*
/// type. A duck-typed object, a test double, or a live-looking struct built in
/// another process cannot self-register at runtime, so they can never satisfy
/// this check by naming themselves correctly.
///
/// Intentionally EMPTY in this change: no real emitter has been implemented or
/// authorized. To enable production runs, add a concrete, reviewed Swift type
/// here for the selected worker. Until then a passing production gate is
/// impossible and the entry fails closed.
public enum RuntimeProviderTrustPolicy {
    public static let registeredLiveProviderTypes: [String: Any.Type] = [:]
}

// MARK: - Gate report

public struct GateReport: Hashable, Sendable {
    public let gate: String
    public let evidenceClass: String
    public let eligibleForRuntimeEvidence: Bool
    public let passed: Bool
    public let checkCount: Int
    public let passedCount: Int
    public let failedCount: Int
    public let failedChecks: [String]
    public let checks: [String: Bool]
    public let details: [String: String]
    public let modelGenerationStartedByGate: Bool
    public let readOnlyModelArtifactSharingAllowed: Bool
    public let providerID: String?
    public let providerKind: RuntimeProviderKind?
    public let runID: String?
    public let challengeNonce: String?
    public let attestationCount: Int?
}

// MARK: - Gate

public enum RuntimeIsolationGate {
    public static let gateID = "G3_RUNTIME_ISOLATION_PRECHECK_V1"
    public static let attestationContractID = "SIMIGO-G3-RUNTIME-ATTESTATION-V1"
    public static let attestationContractVersion = 1
    public static let defaultExpectedArms: [RuntimeArmID] = [
        RuntimeArmID("ES+IS"), RuntimeArmID("IS-only"),
    ]

    /// The resource fields every live attestation must have sampled. Mirrors the
    /// Python gate's required-provenance list so the two stay comparable.
    public static let requiredFieldNames: Set<String> = [
        "worker_pid", "isolation_unit_id", "model_instance_id", "model_content_sha256",
        "tokenizer_instance_id", "tokenizer_content_sha256", "weights_buffer_instance_id",
        "kv_cache_instance_id", "prefix_cache_instance_id", "runtime_buffer_instance_id",
        "kv_cache_namespace", "prefix_cache_namespace", "runtime_write_root",
        "generation_invocations_before_gate", "initialized_before_first_generation",
        "mutable_resource_ids",
    ]

    // MARK: Pure evaluator (research / contract path; never live evidence)

    /// Deterministic isolation predicates over two arm observations. Malformed or
    /// missing evidence fails closed. Its result is NEVER live execution
    /// evidence, even if every check is true: `eligibleForRuntimeEvidence` is
    /// hard-coded false on this path.
    public static func evaluate(
        _ observations: [GateObservation],
        expectedArms: [RuntimeArmID] = defaultExpectedArms
    ) -> GateReport {
        var checks: [String: Bool] = [:]
        var details: [String: String] = [:]
        func add(_ name: String, _ passed: Bool, _ detail: String) {
            checks[name] = passed
            details[name] = detail
        }

        let arms = observations.map { $0.armID }
        let two = observations.count == 2

        add("exact_two_expected_arms", two && arms == expectedArms,
            "expected \(expectedArms.map(\.rawValue)), observed \(arms.map(\.rawValue))")
        add("distinct_arm_ids", two && uniqueNonEmpty(arms.map(\.rawValue)),
            "arm_ids=\(arms.map(\.rawValue))")

        let pids = observations.map { $0.observation.workerPID }
        add("distinct_live_worker_pids",
            two && pids.allSatisfy { $0 > 0 } && Set(pids).count == 2,
            "worker_pids=\(pids)")

        struct DistinctField { let name: String; let check: String; let values: (RuntimeResourceObservation) -> String }
        let distinct: [DistinctField] = [
            .init(name: "isolation_unit_id", check: "distinct_isolation_units", values: \.isolationUnitID),
            .init(name: "model_instance_id", check: "distinct_model_instances", values: \.modelInstanceID),
            .init(name: "tokenizer_instance_id", check: "distinct_tokenizer_instances", values: \.tokenizerInstanceID),
            .init(name: "weights_buffer_instance_id", check: "distinct_weights_buffer_instances", values: \.weightsBufferInstanceID),
            .init(name: "kv_cache_instance_id", check: "distinct_kv_cache_instances", values: \.kvCacheInstanceID),
            .init(name: "prefix_cache_instance_id", check: "distinct_prefix_cache_instances", values: \.prefixCacheInstanceID),
            .init(name: "runtime_buffer_instance_id", check: "distinct_runtime_buffer_instances", values: \.runtimeBufferInstanceID),
            .init(name: "kv_cache_namespace", check: "distinct_kv_cache_namespaces", values: \.kvCacheNamespace),
            .init(name: "prefix_cache_namespace", check: "distinct_prefix_cache_namespaces", values: \.prefixCacheNamespace),
        ]
        for field in distinct {
            let actual = observations.map { field.values($0.observation) }
            add(field.check, two && uniqueNonEmpty(actual), "\(field.name)=\(actual)")
        }

        let modelHashes = observations.map { $0.observation.modelContentSHA256 }
        add("same_valid_model_content",
            two && modelHashes.allSatisfy(isValidSHA256) && modelHashes.first == modelHashes.last,
            "model_content_sha256=\(modelHashes)")
        let tokenizerHashes = observations.map { $0.observation.tokenizerContentSHA256 }
        add("same_valid_tokenizer_content",
            two && tokenizerHashes.allSatisfy(isValidSHA256) && tokenizerHashes.first == tokenizerHashes.last,
            "tokenizer_content_sha256=\(tokenizerHashes)")

        let roots = observations.map { $0.observation.runtimeWriteRoot }
        add("disjoint_runtime_write_roots", two && pathsDisjoint(roots),
            "runtime_write_roots=\(roots)")

        var wellFormed = true
        var mutableSets: [Set<String>] = []
        for row in observations {
            let raw = row.observation.mutableResourceIDs
            if raw.isEmpty || !raw.allSatisfy(nonEmpty) {
                wellFormed = false
                mutableSets.append([])
            } else {
                mutableSets.append(Set(raw))
            }
        }
        let shared = mutableSets.count == 2 ? mutableSets[0].intersection(mutableSets[1]) : []
        add("no_shared_mutable_resources",
            two && wellFormed && shared.isEmpty,
            "shared_mutable_resource_ids=\(shared.sorted()); well_formed=\(wellFormed)")

        let initialized = observations.map { $0.observation.initializedBeforeFirstGeneration }
        add("runtime_initialized_before_generation",
            two && initialized.allSatisfy { $0 == true },
            "initialized_before_first_generation=\(initialized)")
        let invocations = observations.map { $0.observation.generationInvocationsBeforeGate }
        add("zero_generation_invocations_before_gate",
            two && invocations.allSatisfy { $0 == 0 },
            "generation_invocations_before_gate=\(invocations)")

        var provenanceOK = two
        for row in observations {
            let missing = requiredFieldNames.subtracting(row.observedFields)
            let sourceOK = nonEmpty(row.attestationSource)
            if !missing.isEmpty || !sourceOK { provenanceOK = false }
        }
        add("live_attestation_provenance_complete", provenanceOK,
            "required_field_count=\(requiredFieldNames.count)")

        let failed = checks.filter { !$0.value }.keys.sorted()
        return GateReport(
            gate: gateID,
            evidenceClass: "untrusted_observation_evaluation",
            eligibleForRuntimeEvidence: false,
            passed: failed.isEmpty,
            checkCount: checks.count,
            passedCount: checks.values.filter { $0 }.count,
            failedCount: failed.count,
            failedChecks: failed,
            checks: checks,
            details: details,
            modelGenerationStartedByGate: false,
            readOnlyModelArtifactSharingAllowed: true,
            providerID: nil,
            providerKind: nil,
            runID: nil,
            challengeNonce: nil,
            attestationCount: nil
        )
    }

    // MARK: Production entry (trusted provider only; fail closed before generation)

    /// Require a source-registered live provider, collect after init and before
    /// the first generation, validate the envelope provenance, then evaluate.
    /// Refuses (throws) rather than falling back to fixtures, raw observations,
    /// or defaults. A passing report is what — and only what — authorizes the
    /// caller to enter generation.
    public static func requireIsolation(
        provider: RuntimeAttestationProvider,
        request: AttestationRequest
    ) throws -> GateReport {
        let trusted = try requireTrustedProvider(provider)
        let attestations = try trusted.collect(request)
        let observations = try validateBatch(
            attestations, request,
            expectedProviderID: trusted.providerID,
            expectedProviderKind: trusted.providerKind)
        let report = evaluate(observations, expectedArms: request.expectedArms)
        guard report.passed else {
            throw RuntimeAttestationError.isolationGateRefused(report.failedChecks)
        }
        // Only the trusted, envelope-validated path may claim runtime evidence.
        return GateReport(
            gate: report.gate,
            evidenceClass: "registered_live_runtime_attestation",
            eligibleForRuntimeEvidence: true,
            passed: report.passed,
            checkCount: report.checkCount,
            passedCount: report.passedCount,
            failedCount: report.failedCount,
            failedChecks: report.failedChecks,
            checks: report.checks,
            details: report.details,
            modelGenerationStartedByGate: false,
            readOnlyModelArtifactSharingAllowed: true,
            providerID: trusted.providerID,
            providerKind: trusted.providerKind,
            runID: request.runID,
            challengeNonce: request.challengeNonce,
            attestationCount: attestations.count
        )
    }

    static func requireTrustedProvider(
        _ provider: RuntimeAttestationProvider
    ) throws -> RuntimeAttestationProvider {
        let kind = provider.providerKind
        if kind.isFixture {
            throw RuntimeAttestationError.fixtureProviderRejected(
                "fixture provider kind refused: \(kind.rawValue)")
        }
        if !kind.isLive {
            throw RuntimeAttestationError.fixtureProviderRejected(
                "provider_kind must be a live worker kind; got \(kind.rawValue)")
        }
        let id = provider.providerID
        guard nonEmpty(id) else {
            throw RuntimeAttestationError.unregisteredLiveProvider(
                "provider has no source-controlled provider_id")
        }
        guard let expectedType = RuntimeProviderTrustPolicy.registeredLiveProviderTypes[id] else {
            throw RuntimeAttestationError.unregisteredLiveProvider(
                "no reviewed live provider is registered for \(id); refusing to treat a fixture as live")
        }
        // Authoritative grant: the concrete runtime type must BE the registered
        // metatype. Name comparison is only for the error message; identity is
        // decided by the metatype itself, so a same-named impostor type cannot
        // borrow trust.
        let gotType = Swift.type(of: provider)
        guard gotType == expectedType else {
            throw RuntimeAttestationError.providerTypeMismatch(
                providerID: id,
                expected: String(reflecting: expectedType),
                got: String(reflecting: gotType))
        }
        return provider
    }

    static func validateBatch(
        _ attestations: [RuntimeAttestation],
        _ request: AttestationRequest,
        expectedProviderID: String,
        expectedProviderKind: RuntimeProviderKind
    ) throws -> [GateObservation] {
        guard attestations.count == request.expectedArms.count else {
            throw RuntimeAttestationError.invalidAttestation(
                "expected \(request.expectedArms.count) arm attestations, got \(attestations.count)")
        }
        var observations: [GateObservation] = []
        var observedArms: [RuntimeArmID] = []
        for attestation in attestations {
            guard attestation.contractID == request.contractID,
                  attestation.contractVersion == request.contractVersion else {
                throw RuntimeAttestationError.invalidAttestation(
                    "attestation contract identity/version mismatch")
            }
            guard attestation.providerID == expectedProviderID,
                  attestation.providerKind == expectedProviderKind else {
                throw RuntimeAttestationError.invalidAttestation(
                    "attestation provider identity/kind mismatch")
            }
            guard attestation.providerKind.isLive, !attestation.providerKind.isFixture else {
                throw RuntimeAttestationError.fixtureProviderRejected(
                    "non-live provider kind refused: \(attestation.providerKind.rawValue)")
            }
            guard attestation.runID == request.runID,
                  attestation.challengeNonce == request.challengeNonce else {
                throw RuntimeAttestationError.invalidAttestation(
                    "attestation run_id/challenge_nonce mismatch")
            }
            guard nonEmpty(attestation.sourceRevision) else {
                throw RuntimeAttestationError.invalidAttestation("source revision is required")
            }
            guard isValidSHA256(attestation.sourceSHA256) else {
                throw RuntimeAttestationError.invalidAttestation(
                    "source_sha256 must be 64 lowercase hexadecimal characters")
            }
            guard isUTCISO8601(attestation.capturedAtUTC) else {
                throw RuntimeAttestationError.invalidAttestation(
                    "captured_at_utc must be timezone-aware UTC")
            }
            // Provenance is derived from the validated envelope, not the caller.
            observations.append(GateObservation(
                armID: attestation.armID,
                observation: attestation.observation,
                attestationSource: "\(attestation.providerID)@\(attestation.sourceRevision)",
                observedFields: requiredFieldNames
            ))
            observedArms.append(attestation.armID)
        }
        guard observedArms == request.expectedArms else {
            throw RuntimeAttestationError.invalidAttestation(
                "attestation arms/order mismatch: expected \(request.expectedArms.map(\.rawValue)), got \(observedArms.map(\.rawValue))")
        }
        return observations
    }

    // MARK: Predicates

    static func nonEmpty(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func uniqueNonEmpty(_ values: [String]) -> Bool {
        values.allSatisfy(nonEmpty) && Set(values).count == values.count
    }

    static func isValidSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit && $0.isLowercase }
    }

    static func normalizedPath(_ value: String) -> String? {
        guard nonEmpty(value) else { return nil }
        let expanded = (value as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    /// Two write roots may be equal or nested only if they are truly disjoint;
    /// equal, ancestor, or descendant roots are refused so one arm cannot write
    /// into a shared parent of the other.
    static func pathsDisjoint(_ paths: [String]) -> Bool {
        let normalized = paths.map(normalizedPath)
        if normalized.contains(where: { $0 == nil }) { return false }
        let resolved = normalized.compactMap { $0 }
        guard Set(resolved).count == resolved.count else { return false }
        for i in 0..<resolved.count {
            for j in (i + 1)..<resolved.count {
                if isAncestorOrEqual(resolved[i], resolved[j]) { return false }
            }
        }
        return true
    }

    private static func isAncestorOrEqual(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let ac = (a as NSString).pathComponents
        let bc = (b as NSString).pathComponents
        guard ac.count <= bc.count else { return false }
        return Array(bc.prefix(ac.count)) == ac
    }

    private static func isUTCISO8601(_ value: String) -> Bool {
        guard value.hasSuffix("Z") || value.contains("+00:00") else { return false }
        let withSeconds = ISO8601DateFormatter()
        withSeconds.formatOptions = [.withInternetDateTime]
        if withSeconds.date(from: value) != nil { return true }
        let noSeconds = ISO8601DateFormatter()
        noSeconds.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return noSeconds.date(from: value) != nil
    }
}
