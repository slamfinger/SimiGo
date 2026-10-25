// SettledRelationValidationCore — output types for the Decision Core.
//
// Output contract (T-IMPL-01, Audit v0.1 §2; Manifest v1.0 H2):
//   exactly one primary decision REUSE | BLOCK | RECOMPUTE
//   + deterministic semantic derivation trace (labeled
//     DETERMINISTIC_SEMANTIC_DERIVATION_TRACE — never observer-authoritative
//     execution evidence)
//   + typed failures and binding verdicts.

public enum SRSVALPrimaryDecision: String, Equatable, Sendable {
    case reuse = "REUSE"
    case block = "BLOCK"
    case recompute = "RECOMPUTE"
}

/// The completed decision path (Authorization Package v0.6 §3.5; Design v0.8
/// §4). `incompleteClassification` is *not* one of the three completed paths;
/// it is reported so the output names the unlawful-to-complete state directly.
public enum SRSVALDecisionPath: String, Equatable, Sendable {
    case reusePath = "REUSE_PATH"
    case blockedNonRecomputePath = "BLOCKED_NON_RECOMPUTE_PATH"
    case recomputeAuthorizationPath = "RECOMPUTE_AUTHORIZATION_PATH"
    case incompleteClassification = "INCOMPLETE_CLASSIFICATION"
}

/// Validity of the I-14 not-used marker, exactly the §3.5 states.
public enum SRSVALI14MarkerValidity: String, Equatable, Sendable {
    case validNoFailureRemains = "VALID_NO_FAILURE_REMAINS"
    case validHigherPrecedenceResolved = "VALID_HIGHER_PRECEDENCE_RESOLVED"
    case validClassificationCompleteNoEligible = "VALID_CLASSIFICATION_COMPLETE_NO_ELIGIBLE"
    case invalidClassificationRequired = "INVALID_CLASSIFICATION_REQUIRED"
    case notApplicableActiveBinding = "NOT_APPLICABLE_ACTIVE_BINDING"
}

// MARK: - Typed failures

/// DP-0 typed reasons (I-16: omitted/ambiguous/unstable/mixed-boundary/
/// integrity-invalid decision-critical input).
public enum SRSVALInputInconsistency: String, Equatable, Sendable {
    case boundaryIdentityMissing
    case closeBoundaryMissing
    case orderingEvidenceMissingOrIntegrityInvalid
    case consistencyDeclaredInconsistent
    case consistencyDeclaredAmbiguous
    case consistencyDeclaredUnstable
    case mixedObservationBoundary
    case integrityInvalidDecisionCriticalInput
    case danglingClassifiableFailureReference
}

/// DP-1 hard-block reasons. Each case maps to exactly one G-V obligation
/// (see `SRSVALTraceability.matrix`).
public enum SRSVALHardBlock: Equatable, Sendable {
    // G-V1 — SRS declaration integrity
    case srsSettlementIdentityMissing
    case srsBirthStatusNotDeclaredSettled
    case srsSourceRelationBindingMissing
    case srsCanonicalIdentityRuleRequiredButNotExact
    case srsResultIdentityNotDistinct
    case srsProvenanceBindingsMissing
    // G-V2 — source relation
    case sourceRelationIdentityNotExact
    case sourceRelationSemanticsNotExact
    case sourceRelationApplicabilityCoverageMissing
    case sourceRelationInvalidationUnlawfullyHandled
    // G-V3 — dependencies
    case dependencyRevisionBindingNotExact(dependencyIdentity: String)
    case dependencyUnresolved(dependencyIdentity: String)
    case dependencyIntegrityMissing(dependencyIdentity: String)
    case dependencyRoleMissing(dependencyIdentity: String)
    case dependencyNecessityMissing(dependencyIdentity: String)
    case dependencyBlockingSupersession(dependencyIdentity: String)
    case dependencyBlockingInvalidation(dependencyIdentity: String)
    // G-V4 — result
    case resultIdentityOrRevisionMissing
    case resultResolvedWithRecomputation
    case resultIntegrityMissing
    case resultNotInterpretable
    case resultSupersededOrInvalidated
    // G-V5 — resolution rule and policy
    case resolutionRuleBindingNotExact
    case policyVersionBindingsMissing
    // G-V6 — provenance and lifecycle
    case provenanceEvidenceMissing(component: String)
    case lifecycleContested
    case lifecycleUnresolvedConflict
    case lifecycleInvalidated
    case lifecycleIndeterminate
    // G-V7 — freshness
    case freshnessEvidenceMissing(requirementID: String)
    case freshnessRecheckRequired(requirementID: String)
}

/// DP-2 applicability reasons (I-15).
public enum SRSVALApplicabilityFailure: Equatable, Sendable {
    case i15Missing
    case i15Ambiguous(reason: String)
    case i15Unstable(reason: String)
    case i15Unmatched
    case notApplicable
}

/// DP-3 recompute-authorization failures.
public enum SRSVALRecomputeAuthorizationFailure: Equatable, Sendable {
    case i14MissingOrNotExact
    case i14DoesNotCoverEligibleClasses(classes: [String])
    case i14RequestClassMismatch(expected: String, actual: String)
    case i14OutcomeNotAuthorizedToRecompute
    case recomputeEnvelopeIncomplete(field: String)
}

/// G-CLASS failures.
public enum SRSVALClassificationFailure: Equatable, Sendable {
    case predicateRuleBindingUnstableOrMissing
    case predicateRuleClassificationRequired(unclassifiedFailureIDs: [String])
}

public enum SRSVALFailure: Equatable, Sendable {
    case inputStateInconsistent(SRSVALInputInconsistency)
    case hardBlock(SRSVALHardBlock)
    case applicability(SRSVALApplicabilityFailure)
    case classification(SRSVALClassificationFailure)
    case recomputeAuthorization(SRSVALRecomputeAuthorizationFailure)
}

// MARK: - Binding verdicts and derivation trace

public struct SRSVALBindingVerdict: Equatable, Sendable {
    public let binding: String
    public let verdict: String

    public init(binding: String, verdict: String) {
        self.binding = binding
        self.verdict = verdict
    }
}

public struct SRSVALTraceEntry: Equatable, Sendable {
    public let step: Int
    public let rule: String
    public let outcome: String

    public init(step: Int, rule: String, outcome: String) {
        self.step = step
        self.rule = rule
        self.outcome = outcome
    }
}

/// H2: the derivation trace is labeled DETERMINISTIC_SEMANTIC_DERIVATION_TRACE
/// and is *not* OBSERVER_AUTHORITATIVE_EXECUTION_EVIDENCE. Authoritative
/// execution evidence only ever comes from Subject → Independent Observer →
/// Observation Integrity Boundary, outside this module.
public struct SRSVALDerivationTrace: Equatable, Sendable {
    public static let traceLabel = "DETERMINISTIC_SEMANTIC_DERIVATION_TRACE"
    public static let nonEvidenceDisclaimer =
        "NOT OBSERVER_AUTHORITATIVE_EXECUTION_EVIDENCE"

    public let entries: [SRSVALTraceEntry]

    public init(entries: [SRSVALTraceEntry]) {
        self.entries = entries
    }
}

// MARK: - Decision output

public struct SRSVALDecisionOutput: Equatable, Sendable {
    public let primaryDecision: SRSVALPrimaryDecision
    public let decisionPath: SRSVALDecisionPath
    public let i14MarkerValidity: SRSVALI14MarkerValidity
    public let typedFailures: [SRSVALFailure]
    public let bindingVerdicts: [SRSVALBindingVerdict]
    public let derivationTrace: SRSVALDerivationTrace

    public init(
        primaryDecision: SRSVALPrimaryDecision,
        decisionPath: SRSVALDecisionPath,
        i14MarkerValidity: SRSVALI14MarkerValidity,
        typedFailures: [SRSVALFailure],
        bindingVerdicts: [SRSVALBindingVerdict],
        derivationTrace: SRSVALDerivationTrace
    ) {
        self.primaryDecision = primaryDecision
        self.decisionPath = decisionPath
        self.i14MarkerValidity = i14MarkerValidity
        self.typedFailures = typedFailures
        self.bindingVerdicts = bindingVerdicts
        self.derivationTrace = derivationTrace
    }
}
