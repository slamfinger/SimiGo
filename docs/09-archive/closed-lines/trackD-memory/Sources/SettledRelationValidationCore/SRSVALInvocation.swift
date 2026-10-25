// SettledRelationValidationCore — T-IMPL-01 SRS-VAL Decision Core
//
// Frozen semantic basis (exact bindings registered in AUTH-REQ-01 SAR
// IMPLEMENTATION 001):
//   SRS-VAL-01 Design v0.8            @ 1170208 (blob dbbeb5cb, sha256 1f661bda…)
//   Authorization Package v0.6 §3     @ 6089f0b (blob fb05a60d, sha256 e16ca843…)
//   Implementation Boundary Audit v0.1 @ cb95c09 (T-IMPL-01 minimum target)
//   Manifest Contract v1.0            @ f69a0e2 (H1/H2/H3 obligations)
//
// Stage boundary: this module is a pure predicate over a closed immutable
// validation invocation value graph. It excludes carrier, SQLite, persistence,
// runner, observer, fixture building, model/runtime stacks, execution harnesses,
// and IS-mutation executors (Audit v0.1 §2).
//
// H3 closure: every input is an Equatable value type. There are no closures,
// handles, callbacks, environment lookups, clocks, global registries, or
// mutable references anywhere in the input graph or the evaluator. Time and
// ordering enter only as caller-supplied opaque evidence values.
//
// Dependency policy: Swift standard library only.

/// An exact immutable binding: identity, version, content address, integrity.
/// Construction fails on any empty field, so an `exact` state is fully exact.
public struct SRSVALExactBinding: Equatable, Hashable, Sendable {
    public let identity: String
    public let version: String
    public let contentAddress: String
    public let integrityBinding: String

    public init?(identity: String, version: String, contentAddress: String, integrityBinding: String) {
        guard !identity.isEmpty, !version.isEmpty, !contentAddress.isEmpty, !integrityBinding.isEmpty else {
            return nil
        }
        self.identity = identity
        self.version = version
        self.contentAddress = contentAddress
        self.integrityBinding = integrityBinding
    }
}

/// Binding state for a decision-critical input. Deficient states are
/// representable on purpose: the Decision Core must be able to *receive*
/// deficient inputs and resolve them through the frozen precedence rules,
/// not refuse construction. `integrityInvalid` is a DP-0-scoped state
/// (Authorization Package v0.6 §3.1: integrity-invalid decision-critical
/// input produces VALIDATION_INPUT_STATE_INCONSISTENT).
public enum SRSVALBindingState<Bond: Equatable & Sendable>: Equatable, Sendable {
    case exact(Bond)
    case missing
    case ambiguous(reason: String)
    case unstable(reason: String)
    case integrityInvalid(reason: String)
}

// MARK: - I-16 observation boundary

/// The single lawful validation observation boundary (I-16). Every evidence
/// struct below carries `boundaryIdentity`; the core detects mixed boundaries
/// mechanically by comparing each against `boundaryIdentity`.
public struct SRSVALObservationBoundary: Equatable, Sendable {
    public let boundaryIdentity: String
    /// Close-boundary marker/reference for the observation (non-empty).
    public let closeBoundary: String
    /// Ordering/time evidence as caller-supplied opaque values; the core never
    /// reads a clock (H3).
    public let orderingEvidenceReference: String
    public let orderingEvidenceIntegrity: String
    public let consistencyDeclaration: SRSVALConsistencyDeclaration

    public init(
        boundaryIdentity: String,
        closeBoundary: String,
        orderingEvidenceReference: String,
        orderingEvidenceIntegrity: String,
        consistencyDeclaration: SRSVALConsistencyDeclaration
    ) {
        self.boundaryIdentity = boundaryIdentity
        self.closeBoundary = closeBoundary
        self.orderingEvidenceReference = orderingEvidenceReference
        self.orderingEvidenceIntegrity = orderingEvidenceIntegrity
        self.consistencyDeclaration = consistencyDeclaration
    }
}

public enum SRSVALConsistencyDeclaration: String, Equatable, Sendable {
    case consistent
    case inconsistent
    case ambiguous
    case unstable
    case mixedBoundary
}

// MARK: - G-V1 SRS declaration evidence

public enum SRSVALBirthStatus: Equatable, Sendable {
    case declaredSettled
    case other(String)
}

public struct SRSVALSRSEvidence: Equatable, Sendable {
    public let boundaryIdentity: String
    /// Addressable settlement identity (non-empty).
    public let settlementIdentity: String
    public let birthStatus: SRSVALBirthStatus
    /// Immutable source-relation binding reference (non-empty).
    public let sourceRelationBinding: String
    /// Whether an exact canonical identity rule applies to this settlement.
    public let canonicalIdentityRuleApplicable: Bool
    /// Required exact when `canonicalIdentityRuleApplicable` is true.
    public let canonicalIdentityRule: SRSVALBindingState<SRSVALExactBinding>
    /// Distinct result identity (must differ from `settlementIdentity`).
    public let resultIdentity: String
    /// Immutable provenance bindings (non-empty array).
    public let provenanceBindings: [String]

    public init(
        boundaryIdentity: String,
        settlementIdentity: String,
        birthStatus: SRSVALBirthStatus,
        sourceRelationBinding: String,
        canonicalIdentityRuleApplicable: Bool,
        canonicalIdentityRule: SRSVALBindingState<SRSVALExactBinding>,
        resultIdentity: String,
        provenanceBindings: [String]
    ) {
        self.boundaryIdentity = boundaryIdentity
        self.settlementIdentity = settlementIdentity
        self.birthStatus = birthStatus
        self.sourceRelationBinding = sourceRelationBinding
        self.canonicalIdentityRuleApplicable = canonicalIdentityRuleApplicable
        self.canonicalIdentityRule = canonicalIdentityRule
        self.resultIdentity = resultIdentity
        self.provenanceBindings = provenanceBindings
    }
}

// MARK: - G-V2 source relation evidence

/// How a recorded invalidation is handled. `.declaredClassifiableFailure`
/// references an entry in `SRSVALInvocation.declaredSurvivingFailures` and is
/// routed to mandatory classification (G-CLASS / DP-3). `.hardBlockViolation`
/// is a DP-1 hard block. `.lawfullyResolved` carries its own evidence.
public enum SRSVALInvalidationHandling: Equatable, Sendable {
    case declaredClassifiableFailure(failureID: String)
    case hardBlockViolation
    case lawfullyResolved(evidenceReference: String)
}

public struct SRSVALInvalidationRecord: Equatable, Sendable {
    public let recordID: String
    public let invalidationClass: String
    public let handling: SRSVALInvalidationHandling

    public init(recordID: String, invalidationClass: String, handling: SRSVALInvalidationHandling) {
        self.recordID = recordID
        self.invalidationClass = invalidationClass
        self.handling = handling
    }
}

public struct SRSVALSourceRelationEvidence: Equatable, Sendable {
    public let boundaryIdentity: String
    public let sourceIdentity: SRSVALBindingState<SRSVALExactBinding>
    public let semanticsIdentity: SRSVALBindingState<SRSVALExactBinding>
    /// Exact applicability coverage reference (non-empty).
    public let applicabilityCoverage: String
    public let invalidationRecords: [SRSVALInvalidationRecord]

    public init(
        boundaryIdentity: String,
        sourceIdentity: SRSVALBindingState<SRSVALExactBinding>,
        semanticsIdentity: SRSVALBindingState<SRSVALExactBinding>,
        applicabilityCoverage: String,
        invalidationRecords: [SRSVALInvalidationRecord]
    ) {
        self.boundaryIdentity = boundaryIdentity
        self.sourceIdentity = sourceIdentity
        self.semanticsIdentity = semanticsIdentity
        self.applicabilityCoverage = applicabilityCoverage
        self.invalidationRecords = invalidationRecords
    }
}

// MARK: - G-V3 dependency evidence

public struct SRSVALDependencyEvidence: Equatable, Sendable {
    public let boundaryIdentity: String
    public let dependencyIdentity: String
    /// Exact revision binding (G-V3: exact revision binding and resolution).
    public let revisionBinding: SRSVALBindingState<SRSVALExactBinding>
    /// Resolution state: unresolved dependencies are a G-V3 hard block.
    public let resolved: Bool
    /// Integrity evidence reference (non-empty when resolved).
    public let integrityReference: String
    /// Role binding (non-empty).
    public let role: String
    /// Necessity binding (non-empty).
    public let necessity: String
    /// A blocking supersession is a G-V3 hard block.
    public let blockingSupersession: Bool
    /// A blocking invalidation is a G-V3 hard block; non-blocking invalidation
    /// is declared as a surviving failure instead.
    public let blockingInvalidation: Bool

    public init(
        boundaryIdentity: String,
        dependencyIdentity: String,
        revisionBinding: SRSVALBindingState<SRSVALExactBinding>,
        resolved: Bool,
        integrityReference: String,
        role: String,
        necessity: String,
        blockingSupersession: Bool,
        blockingInvalidation: Bool
    ) {
        self.boundaryIdentity = boundaryIdentity
        self.dependencyIdentity = dependencyIdentity
        self.revisionBinding = revisionBinding
        self.resolved = resolved
        self.integrityReference = integrityReference
        self.role = role
        self.necessity = necessity
        self.blockingSupersession = blockingSupersession
        self.blockingInvalidation = blockingInvalidation
    }
}

// MARK: - G-V4 result evidence

public struct SRSVALResultEvidence: Equatable, Sendable {
    public let boundaryIdentity: String
    public let resultIdentity: String
    public let resultRevision: String
    /// G-V4: resolution without recomputation.
    public let resolvedWithoutRecomputation: Bool
    /// Integrity evidence reference (non-empty).
    public let integrityReference: String
    /// Interpretability (G-V4).
    public let interpretable: Bool
    public let superseded: Bool
    public let invalidated: Bool

    public init(
        boundaryIdentity: String,
        resultIdentity: String,
        resultRevision: String,
        resolvedWithoutRecomputation: Bool,
        integrityReference: String,
        interpretable: Bool,
        superseded: Bool,
        invalidated: Bool
    ) {
        self.boundaryIdentity = boundaryIdentity
        self.resultIdentity = resultIdentity
        self.resultRevision = resultRevision
        self.resolvedWithoutRecomputation = resolvedWithoutRecomputation
        self.integrityReference = integrityReference
        self.interpretable = interpretable
        self.superseded = superseded
        self.invalidated = invalidated
    }
}

// MARK: - G-V5 resolution rule and policy evidence

public struct SRSVALResolutionEvidence: Equatable, Sendable {
    public let boundaryIdentity: String
    public let ruleBinding: SRSVALBindingState<SRSVALExactBinding>

    public init(boundaryIdentity: String, ruleBinding: SRSVALBindingState<SRSVALExactBinding>) {
        self.boundaryIdentity = boundaryIdentity
        self.ruleBinding = ruleBinding
    }
}

public struct SRSVALPolicyEvidence: Equatable, Sendable {
    public let boundaryIdentity: String
    /// Exact applicable policy version bindings (non-empty array).
    public let applicablePolicyVersions: [SRSVALExactBinding]

    public init(boundaryIdentity: String, applicablePolicyVersions: [SRSVALExactBinding]) {
        self.boundaryIdentity = boundaryIdentity
        self.applicablePolicyVersions = applicablePolicyVersions
    }
}

// MARK: - G-V6 provenance and lifecycle evidence

public struct SRSVALProvenanceEvidence: Equatable, Sendable {
    public let boundaryIdentity: String
    /// Immutable/exact evidence references for production, declaration,
    /// dependency, result, and ordering (each non-empty).
    public let productionEvidence: String
    public let declarationEvidence: String
    public let dependencyEvidence: String
    public let resultEvidence: String
    public let orderingEvidence: String

    public init(
        boundaryIdentity: String,
        productionEvidence: String,
        declarationEvidence: String,
        dependencyEvidence: String,
        resultEvidence: String,
        orderingEvidence: String
    ) {
        self.boundaryIdentity = boundaryIdentity
        self.productionEvidence = productionEvidence
        self.declarationEvidence = declarationEvidence
        self.dependencyEvidence = dependencyEvidence
        self.resultEvidence = resultEvidence
        self.orderingEvidence = orderingEvidence
    }
}

public enum SRSVALLifecycleState: String, Equatable, Sendable {
    case determinate
    case contested                         // CONTESTED
    case unresolvedLifecycleConflict       // UNRESOLVED_LIFECYCLE_CONFLICT
    case invalidated                       // INVALIDATED
    case indeterminate
}

public struct SRSVALLifecycleEvidence: Equatable, Sendable {
    public let boundaryIdentity: String
    public let state: SRSVALLifecycleState

    public init(boundaryIdentity: String, state: SRSVALLifecycleState) {
        self.boundaryIdentity = boundaryIdentity
        self.state = state
    }
}

// MARK: - G-V7 freshness evidence

public enum SRSVALFreshnessState: Equatable, Sendable {
    /// Positively cleared by lawful evidence (non-empty reference).
    case cleared(evidenceReference: String)
    /// FRESHNESS_RECHECK_REQUIRED — remains blocking until positively cleared.
    case recheckRequired
    /// No evidence at all.
    case evidenceMissing
}

public struct SRSVALFreshnessRequirement: Equatable, Sendable {
    public let requirementID: String
    public let boundaryIdentity: String
    public let state: SRSVALFreshnessState

    public init(requirementID: String, boundaryIdentity: String, state: SRSVALFreshnessState) {
        self.requirementID = requirementID
        self.boundaryIdentity = boundaryIdentity
        self.state = state
    }
}

// MARK: - I-15 exact current reuse request

public enum SRSVALRequestApplicability: String, Equatable, Sendable {
    case applicable
    case notApplicable
}

/// I-15: the exact semantic request binding for the current reuse request.
/// Not natural language and not business intent (Authorization Package v0.6 §3.1).
public struct SRSVALReuseRequestBinding: Equatable, Sendable {
    public let requestIdentity: String
    public let exactBinding: SRSVALExactBinding
    /// Must match the invocation's settlement identity; mismatch = unmatched.
    public let requestedSettlementIdentity: String
    public let requestClass: String
    public let applicability: SRSVALRequestApplicability

    public init(
        requestIdentity: String,
        exactBinding: SRSVALExactBinding,
        requestedSettlementIdentity: String,
        requestClass: String,
        applicability: SRSVALRequestApplicability
    ) {
        self.requestIdentity = requestIdentity
        self.exactBinding = exactBinding
        self.requestedSettlementIdentity = requestedSettlementIdentity
        self.requestClass = requestClass
        self.applicability = applicability
    }
}

// MARK: - I-14 governing recompute/reuse authorization

public enum SRSVALI14AuthorizedOutcome: String, Equatable, Sendable {
    case recompute
    case reuse
}

/// I-14 binds, per Authorization Package v0.6 §3.1: immutable governing
/// semantic identity, exact immutable version, immutable content/integrity
/// evidence, source-relation scope, invalidation class, request class,
/// authorized result outcome, recomputation semantic class, result-target
/// derivation boundary, and exact canonical relation-identity rule.
public struct SRSVALI14Binding: Equatable, Sendable {
    public let governingSemanticIdentity: String
    public let exactVersion: String
    public let contentIntegrityEvidence: String
    public let sourceRelationScope: String
    /// Invalidation classes this authorization covers (the semantic envelope).
    public let coveredInvalidationClasses: [String]
    public let requestClass: String
    public let authorizedResultOutcome: SRSVALI14AuthorizedOutcome
    public let recomputationSemanticClass: String
    public let resultTargetDerivationBoundary: String
    /// Exact canonical relation-identity rule binding.
    public let canonicalRelationIdentityRule: SRSVALExactBinding

    public init(
        governingSemanticIdentity: String,
        exactVersion: String,
        contentIntegrityEvidence: String,
        sourceRelationScope: String,
        coveredInvalidationClasses: [String],
        requestClass: String,
        authorizedResultOutcome: SRSVALI14AuthorizedOutcome,
        recomputationSemanticClass: String,
        resultTargetDerivationBoundary: String,
        canonicalRelationIdentityRule: SRSVALExactBinding
    ) {
        self.governingSemanticIdentity = governingSemanticIdentity
        self.exactVersion = exactVersion
        self.contentIntegrityEvidence = contentIntegrityEvidence
        self.sourceRelationScope = sourceRelationScope
        self.coveredInvalidationClasses = coveredInvalidationClasses
        self.requestClass = requestClass
        self.authorizedResultOutcome = authorizedResultOutcome
        self.recomputationSemanticClass = recomputationSemanticClass
        self.resultTargetDerivationBoundary = resultTargetDerivationBoundary
        self.canonicalRelationIdentityRule = canonicalRelationIdentityRule
    }
}

/// I-14 reference for one invocation: either the exact not-used marker or an
/// active exact binding (possibly deficient — see `SRSVALBindingState`).
public enum SRSVALI14Reference: Equatable, Sendable {
    case notUsedNoRecomputePath
    case active(SRSVALBindingState<SRSVALI14Binding>)
}

// MARK: - Registered Predicate Rule Artifact (H1: separate from the core)

public enum SRSVALClassificationVerdict: String, Equatable, Sendable {
    case recomputeEligible = "RECOMPUTE_ELIGIBLE"
    case notRecomputeEligible = "NOT_RECOMPUTE_ELIGIBLE"
}

public struct SRSVALPredicateRuleClassification: Equatable, Sendable {
    public let failureClass: String
    public let verdict: SRSVALClassificationVerdict

    public init(failureClass: String, verdict: SRSVALClassificationVerdict) {
        self.failureClass = failureClass
        self.verdict = verdict
    }
}

/// The Registered Predicate Rule Artifact is a *separate bindable artifact*
/// (Manifest v1.0 H1; Acceptance §2.1). It is data, not code: the Decision
/// Core never names, versions, hashes, registers, or authorizes itself as the
/// predicate rule; it only interprets the exact bound artifact supplied in the
/// invocation. Changing classification behavior changes the input artifact
/// (new identity/version/content address), never the core.
public struct SRSVALPredicateRuleArtifact: Equatable, Sendable {
    public let ruleIdentity: String
    public let ruleVersion: String
    public let contentAddress: String
    public let integrityBinding: String
    public let registrationAuthority: String
    /// Covered failure classes with their verdicts at exactly this rule version.
    public let classifications: [SRSVALPredicateRuleClassification]

    public init(
        ruleIdentity: String,
        ruleVersion: String,
        contentAddress: String,
        integrityBinding: String,
        registrationAuthority: String,
        classifications: [SRSVALPredicateRuleClassification]
    ) {
        self.ruleIdentity = ruleIdentity
        self.ruleVersion = ruleVersion
        self.contentAddress = contentAddress
        self.integrityBinding = integrityBinding
        self.registrationAuthority = registrationAuthority
        self.classifications = classifications
    }
}

public enum SRSVALPredicateRuleReference: Equatable, Sendable {
    case notUsed
    case registered(SRSVALBindingState<SRSVALPredicateRuleArtifact>)
}

// MARK: - Declared surviving failures

/// A surviving (non-hard-block) validation failure declared inside the
/// observation boundary, awaiting mandatory predicate-rule classification.
public struct SRSVALDeclaredFailure: Equatable, Sendable {
    public let failureID: String
    /// The failure class the predicate rule artifact must cover.
    public let failureClass: String
    public let evidenceReference: String

    public init(failureID: String, failureClass: String, evidenceReference: String) {
        self.failureID = failureID
        self.failureClass = failureClass
        self.evidenceReference = evidenceReference
    }
}

// MARK: - Invocation (closed immutable validation invocation value graph)

/// The complete closed value graph consumed by one Decision Core evaluation.
/// I-16 membership is explicit: boundary, ordering evidence, SRS evidence,
/// dependency state, result state, freshness/policy evidence, lifecycle
/// evidence, consistency declaration, close boundary, exact I-15 reference,
/// exact I-14 reference or not-used marker, and exact predicate-rule binding
/// reference or not-used marker.
public struct SRSVALInvocation: Equatable, Sendable {
    public let boundary: SRSVALObservationBoundary
    public let srs: SRSVALSRSEvidence
    public let sourceRelation: SRSVALSourceRelationEvidence
    public let dependencies: [SRSVALDependencyEvidence]
    public let result: SRSVALResultEvidence
    public let resolution: SRSVALResolutionEvidence
    public let policy: SRSVALPolicyEvidence
    public let provenance: SRSVALProvenanceEvidence
    public let lifecycle: SRSVALLifecycleEvidence
    public let freshnessRequirements: [SRSVALFreshnessRequirement]
    /// I-15 — mandatory for every invocation; missing/unstable/ambiguous is
    /// representable and resolves at DP-2.
    public let reuseRequest: SRSVALBindingState<SRSVALReuseRequestBinding>
    /// I-14 — active exact reference or the exact not-used marker.
    public let governingAuthorization: SRSVALI14Reference
    /// Registered Predicate Rule Artifact reference or not-used marker.
    public let predicateRule: SRSVALPredicateRuleReference
    /// Surviving failures declared inside the boundary (classification input).
    public let declaredSurvivingFailures: [SRSVALDeclaredFailure]

    public init(
        boundary: SRSVALObservationBoundary,
        srs: SRSVALSRSEvidence,
        sourceRelation: SRSVALSourceRelationEvidence,
        dependencies: [SRSVALDependencyEvidence],
        result: SRSVALResultEvidence,
        resolution: SRSVALResolutionEvidence,
        policy: SRSVALPolicyEvidence,
        provenance: SRSVALProvenanceEvidence,
        lifecycle: SRSVALLifecycleEvidence,
        freshnessRequirements: [SRSVALFreshnessRequirement],
        reuseRequest: SRSVALBindingState<SRSVALReuseRequestBinding>,
        governingAuthorization: SRSVALI14Reference,
        predicateRule: SRSVALPredicateRuleReference,
        declaredSurvivingFailures: [SRSVALDeclaredFailure]
    ) {
        self.boundary = boundary
        self.srs = srs
        self.sourceRelation = sourceRelation
        self.dependencies = dependencies
        self.result = result
        self.resolution = resolution
        self.policy = policy
        self.provenance = provenance
        self.lifecycle = lifecycle
        self.freshnessRequirements = freshnessRequirements
        self.reuseRequest = reuseRequest
        self.governingAuthorization = governingAuthorization
        self.predicateRule = predicateRule
        self.declaredSurvivingFailures = declaredSurvivingFailures
    }
}
