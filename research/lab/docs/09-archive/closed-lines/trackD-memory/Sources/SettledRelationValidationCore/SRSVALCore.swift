// SettledRelationValidationCore — the Decision Core evaluator.
//
// Deterministic decision precedence (Authorization Package v0.6 §3.4):
//   DP-0 observation boundary inconsistent/ambiguous/unstable → BLOCK
//   DP-1 any HARD_BLOCK across G-V1..G-V7 domains            → BLOCK
//   DP-2 applicability NOT_APPLICABLE / INDETERMINATE        → BLOCK
//   DP-3 surviving failures classified RECOMPUTE_ELIGIBLE under the exact
//        bound predicate rule and exactly covered by valid I-14 and its valid
//        semantic envelope                                    → RECOMPUTE
//   DP-4 no failure remains and all checks pass              → REUSE
//
// REUSE, BLOCK, and RECOMPUTE are mutually exclusive. Failure alone never
// authorizes recomputation. REUSE never requires I-14. Mixed eligible and
// hard-block failures yield BLOCK (hard blocks resolve first at DP-1).
//
// G-CLASS (Design v0.8 §2): every surviving failure, unless a higher-
// precedence rule already resolved the invocation, is classified by the exact
// registered predicate-rule binding before BLOCKED_NON_RECOMPUTE_PATH or
// RECOMPUTE. Incomplete classification → BLOCK with the applicable typed
// reason and an INVALID not-used marker.
//
// Scope discipline: this evaluator performs mechanical structural checks only.
// It never judges semantic correctness — that boundary is registered, not
// solved (no semantic oracle).

public enum SRSVALEvaluator {
    /// Evaluate one closed immutable validation invocation value graph.
    /// Pure and deterministic: same input graph, same output, no clock, no
    /// randomness, no environment access.
    public static func evaluate(_ invocation: SRSVALInvocation) -> SRSVALDecisionOutput {
        var trace: [SRSVALTraceEntry] = []
        var step = 0
        func record(_ rule: String, _ outcome: String) {
            step += 1
            trace.append(SRSVALTraceEntry(step: step, rule: rule, outcome: outcome))
        }

        // MARK: DP-0 — observation boundary consistency (I-16)

        var dp0Failures: [SRSVALFailure] = []
        if invocation.boundary.boundaryIdentity.isEmpty {
            dp0Failures.append(.inputStateInconsistent(.boundaryIdentityMissing))
        }
        if invocation.boundary.closeBoundary.isEmpty {
            dp0Failures.append(.inputStateInconsistent(.closeBoundaryMissing))
        }
        if invocation.boundary.orderingEvidenceReference.isEmpty
            || invocation.boundary.orderingEvidenceIntegrity.isEmpty {
            dp0Failures.append(.inputStateInconsistent(.orderingEvidenceMissingOrIntegrityInvalid))
        }
        switch invocation.boundary.consistencyDeclaration {
        case .consistent:
            break
        case .inconsistent:
            dp0Failures.append(.inputStateInconsistent(.consistencyDeclaredInconsistent))
        case .ambiguous:
            dp0Failures.append(.inputStateInconsistent(.consistencyDeclaredAmbiguous))
        case .unstable:
            dp0Failures.append(.inputStateInconsistent(.consistencyDeclaredUnstable))
        case .mixedBoundary:
            dp0Failures.append(.inputStateInconsistent(.mixedObservationBoundary))
        }
        if case .integrityInvalid = invocation.reuseRequest {
            dp0Failures.append(.inputStateInconsistent(.integrityInvalidDecisionCriticalInput))
        }
        if case .active(.integrityInvalid) = invocation.governingAuthorization {
            dp0Failures.append(.inputStateInconsistent(.integrityInvalidDecisionCriticalInput))
        }
        if case .registered(.integrityInvalid) = invocation.predicateRule {
            dp0Failures.append(.inputStateInconsistent(.integrityInvalidDecisionCriticalInput))
        }
        // Mixed-boundary detection: every evidence member must declare the
        // same boundary identity as the I-16 boundary itself.
        let expectedBoundary = invocation.boundary.boundaryIdentity
        let memberBoundaryIdentities = [
            invocation.srs.boundaryIdentity,
            invocation.sourceRelation.boundaryIdentity,
            invocation.result.boundaryIdentity,
            invocation.resolution.boundaryIdentity,
            invocation.policy.boundaryIdentity,
            invocation.provenance.boundaryIdentity,
            invocation.lifecycle.boundaryIdentity,
        ] + invocation.dependencies.map(\.boundaryIdentity)
            + invocation.freshnessRequirements.map(\.boundaryIdentity)
        if !expectedBoundary.isEmpty, memberBoundaryIdentities.contains(where: { $0 != expectedBoundary }) {
            dp0Failures.append(.inputStateInconsistent(.mixedObservationBoundary))
        }
        // Dangling classifiable-failure references from invalidation handling.
        let declaredFailureIDs = Set(invocation.declaredSurvivingFailures.map(\.failureID))
        let referencedFailureIDs = invocation.sourceRelation.invalidationRecords.compactMap { record -> String? in
            if case .declaredClassifiableFailure(let failureID) = record.handling {
                return failureID
            }
            return nil
        }
        if referencedFailureIDs.contains(where: { !declaredFailureIDs.contains($0) }) {
            dp0Failures.append(.inputStateInconsistent(.danglingClassifiableFailureReference))
        }

        if !dp0Failures.isEmpty {
            record("DP-0", "BLOCK — VALIDATION_INPUT_STATE_INCONSISTENT")
            return block(
                path: .blockedNonRecomputePath,
                markerValidity: markerValidity(for: invocation, resolvedByHigherPrecedence: true),
                failures: dp0Failures,
                trace: &trace
            )
        }
        record("DP-0", "PASS — observation boundary consistent")

        // MARK: DP-1 — G-V1..G-V7 hard blocks

        var hardBlocks: [SRSVALHardBlock] = []
        hardBlocks.append(contentsOf: evaluateGV1(invocation.srs))
        hardBlocks.append(contentsOf: evaluateGV2(invocation.sourceRelation))
        hardBlocks.append(contentsOf: evaluateGV3(invocation.dependencies))
        hardBlocks.append(contentsOf: evaluateGV4(invocation.result))
        hardBlocks.append(contentsOf: evaluateGV5(invocation.resolution, invocation.policy))
        hardBlocks.append(contentsOf: evaluateGV6(invocation.provenance, invocation.lifecycle))
        hardBlocks.append(contentsOf: evaluateGV7(invocation.freshnessRequirements))

        let gvRules = ["G-V1", "G-V2", "G-V3", "G-V4", "G-V5", "G-V6", "G-V7"]
        for (index, rule) in gvRules.enumerated() {
            let domainFailures = hardBlocks.filter { failure in
                domain(of: failure) == index
            }
            record(rule, domainFailures.isEmpty ? "PASS" : "HARD_BLOCK ×\(domainFailures.count)")
        }

        if !hardBlocks.isEmpty {
            record("DP-1", "BLOCK — HARD_BLOCK present")
            return block(
                path: .blockedNonRecomputePath,
                markerValidity: markerValidity(for: invocation, resolvedByHigherPrecedence: true),
                failures: hardBlocks.map { .hardBlock($0) },
                trace: &trace
            )
        }
        record("DP-1", "PASS — no hard block")

        // MARK: DP-2 — applicability (I-15)

        let applicabilityFailure: SRSVALApplicabilityFailure?
        switch invocation.reuseRequest {
        case .missing:
            applicabilityFailure = .i15Missing
        case .ambiguous(let reason):
            applicabilityFailure = .i15Ambiguous(reason: reason)
        case .unstable(let reason):
            applicabilityFailure = .i15Unstable(reason: reason)
        case .integrityInvalid:
            // Already resolved at DP-0; unreachable here.
            applicabilityFailure = nil
        case .exact(let request):
            if request.requestedSettlementIdentity != invocation.srs.settlementIdentity {
                applicabilityFailure = .i15Unmatched
            } else if request.applicability == .notApplicable {
                applicabilityFailure = .notApplicable
            } else {
                applicabilityFailure = nil
            }
        }

        if let failure = applicabilityFailure {
            record("DP-2", "BLOCK — applicability failure: \(failureName(failure))")
            return block(
                path: .blockedNonRecomputePath,
                markerValidity: markerValidity(for: invocation, resolvedByHigherPrecedence: true),
                failures: [.applicability(failure)],
                trace: &trace
            )
        }
        record("DP-2", "PASS — applicability determined")

        // MARK: DP-4 candidate — no surviving failure remains

        if invocation.declaredSurvivingFailures.isEmpty {
            record("DP-4", "REUSE — no failure remains, all checks pass")
            var verdicts = standardVerdicts(invocation)
            verdicts.append(SRSVALBindingVerdict(binding: "I-14", verdict: "not-required-for-reuse"))
            if case .active = invocation.governingAuthorization {
                record("I-14", "active binding declared but not exercised; REUSE never requires I-14")
            }
            return SRSVALDecisionOutput(
                primaryDecision: .reuse,
                decisionPath: .reusePath,
                i14MarkerValidity: .validNoFailureRemains,
                typedFailures: [],
                bindingVerdicts: verdicts,
                derivationTrace: SRSVALDerivationTrace(entries: trace)
            )
        }
        record("G-CLASS", "mandatory classification required for \(invocation.declaredSurvivingFailures.count) surviving failure(s)")

        // MARK: G-CLASS — mandatory classification under the bound rule

        let ruleArtifact: SRSVALPredicateRuleArtifact
        switch invocation.predicateRule {
        case .notUsed:
            record("G-CLASS", "BLOCK — predicate-rule binding missing (not-used marker cannot classify)")
            return block(
                path: .incompleteClassification,
                markerValidity: .invalidClassificationRequired,
                failures: [.classification(.predicateRuleBindingUnstableOrMissing)],
                trace: &trace
            )
        case .registered(.exact(let artifact)):
            if artifact.ruleIdentity.isEmpty || artifact.ruleVersion.isEmpty
                || artifact.contentAddress.isEmpty || artifact.integrityBinding.isEmpty
                || artifact.registrationAuthority.isEmpty {
                record("G-CLASS", "BLOCK — predicate-rule binding unstable (inexact artifact fields)")
                return block(
                    path: .incompleteClassification,
                    markerValidity: .invalidClassificationRequired,
                    failures: [.classification(.predicateRuleBindingUnstableOrMissing)],
                    trace: &trace
                )
            }
            ruleArtifact = artifact
        case .registered(.missing), .registered(.ambiguous), .registered(.unstable):
            record("G-CLASS", "BLOCK — predicate-rule binding unstable or missing")
            return block(
                path: .incompleteClassification,
                markerValidity: .invalidClassificationRequired,
                failures: [.classification(.predicateRuleBindingUnstableOrMissing)],
                trace: &trace
            )
        case .registered(.integrityInvalid):
            // Already resolved at DP-0; unreachable here.
            record("G-CLASS", "BLOCK — predicate-rule binding integrity invalid")
            return block(
                path: .incompleteClassification,
                markerValidity: .invalidClassificationRequired,
                failures: [.classification(.predicateRuleBindingUnstableOrMissing)],
                trace: &trace
            )
        }
        record(
            "G-CLASS",
            "bound rule \(ruleArtifact.ruleIdentity)@\(ruleArtifact.ruleVersion) (\(ruleArtifact.contentAddress))"
        )

        var classified: [(failure: SRSVALDeclaredFailure, verdict: SRSVALClassificationVerdict)] = []
        var unclassified: [String] = []
        for failure in invocation.declaredSurvivingFailures {
            let match = ruleArtifact.classifications.first { $0.failureClass == failure.failureClass }
            guard let verdict = match?.verdict else {
                unclassified.append(failure.failureID)
                continue
            }
            classified.append((failure, verdict))
            record(
                "G-CLASS",
                "classified \(failure.failureID) [\(failure.failureClass)] → \(verdict.rawValue) under bound rule version"
            )
        }

        if !unclassified.isEmpty {
            record("G-CLASS", "BLOCK — PREDICATE_RULE_CLASSIFICATION_REQUIRED")
            return block(
                path: .incompleteClassification,
                markerValidity: .invalidClassificationRequired,
                failures: [.classification(.predicateRuleClassificationRequired(unclassifiedFailureIDs: unclassified))],
                trace: &trace
            )
        }

        let eligible = classified.filter { $0.verdict == .recomputeEligible }

        // MARK: DP-3 / BLOCKED_NON_RECOMPUTE resolution

        if eligible.isEmpty {
            record("DP-3", "no surviving failure classified RECOMPUTE_ELIGIBLE")
            record("PATH", "BLOCKED_NON_RECOMPUTE_PATH — classification complete, none eligible")
            var verdicts = standardVerdicts(invocation)
            verdicts.append(SRSVALBindingVerdict(binding: "I-14", verdict: "not-exercised-no-eligible-failure"))
            return SRSVALDecisionOutput(
                primaryDecision: .block,
                decisionPath: .blockedNonRecomputePath,
                i14MarkerValidity: .validClassificationCompleteNoEligible,
                typedFailures: [],
                bindingVerdicts: verdicts,
                derivationTrace: SRSVALDerivationTrace(entries: trace)
            )
        }

        record("DP-3", "\(eligible.count) surviving failure(s) classified RECOMPUTE_ELIGIBLE — I-14 and envelope required")

        // I-14 must be an active exact binding.
        let i14Binding: SRSVALI14Binding
        switch invocation.governingAuthorization {
        case .notUsedNoRecomputePath:
            record("DP-3", "BLOCK — I-14 missing on RECOMPUTE authorization path")
            return block(
                path: .recomputeAuthorizationPath,
                markerValidity: .notApplicableActiveBinding,
                failures: [.recomputeAuthorization(.i14MissingOrNotExact)],
                trace: &trace
            )
        case .active(.exact(let binding)):
            i14Binding = binding
        case .active(.missing), .active(.ambiguous), .active(.unstable):
            record("DP-3", "BLOCK — I-14 not exact on RECOMPUTE authorization path")
            return block(
                path: .recomputeAuthorizationPath,
                markerValidity: .notApplicableActiveBinding,
                failures: [.recomputeAuthorization(.i14MissingOrNotExact)],
                trace: &trace
            )
        case .active(.integrityInvalid):
            // Already resolved at DP-0; unreachable here.
            record("DP-3", "BLOCK — I-14 integrity invalid")
            return block(
                path: .recomputeAuthorizationPath,
                markerValidity: .notApplicableActiveBinding,
                failures: [.recomputeAuthorization(.i14MissingOrNotExact)],
                trace: &trace
            )
        }

        // Semantic envelope validity (mechanical checks over the I-14 fields).
        var envelopeFailures: [SRSVALRecomputeAuthorizationFailure] = []
        let eligibleClasses = eligible.map { $0.failure.failureClass }
        let uncovered = eligibleClasses.filter { !i14Binding.coveredInvalidationClasses.contains($0) }
        if !uncovered.isEmpty {
            envelopeFailures.append(.i14DoesNotCoverEligibleClasses(classes: uncovered))
        }
        if case .exact(let request) = invocation.reuseRequest {
            if request.requestClass != i14Binding.requestClass {
                envelopeFailures.append(.i14RequestClassMismatch(expected: request.requestClass, actual: i14Binding.requestClass))
            }
        }
        if i14Binding.authorizedResultOutcome != .recompute {
            envelopeFailures.append(.i14OutcomeNotAuthorizedToRecompute)
        }
        if i14Binding.sourceRelationScope.isEmpty {
            envelopeFailures.append(.recomputeEnvelopeIncomplete(field: "source_relation_scope"))
        }
        if i14Binding.recomputationSemanticClass.isEmpty {
            envelopeFailures.append(.recomputeEnvelopeIncomplete(field: "recomputation_semantic_class"))
        }
        if i14Binding.resultTargetDerivationBoundary.isEmpty {
            envelopeFailures.append(.recomputeEnvelopeIncomplete(field: "result_target_derivation_boundary"))
        }

        if !envelopeFailures.isEmpty {
            record("DP-3", "BLOCK — I-14/semantic envelope invalid")
            return block(
                path: .recomputeAuthorizationPath,
                markerValidity: .notApplicableActiveBinding,
                failures: envelopeFailures.map { .recomputeAuthorization($0) },
                trace: &trace
            )
        }

        record("DP-3", "RECOMPUTE — exact I-14 covers eligible failures, envelope valid")
        var verdicts = standardVerdicts(invocation)
        verdicts.append(SRSVALBindingVerdict(binding: "I-14", verdict: "active-exact-envelope-valid"))
        verdicts.append(SRSVALBindingVerdict(binding: "PREDICATE_RULE", verdict: "\(ruleArtifact.ruleIdentity)@\(ruleArtifact.ruleVersion)"))
        return SRSVALDecisionOutput(
            primaryDecision: .recompute,
            decisionPath: .recomputeAuthorizationPath,
            i14MarkerValidity: .notApplicableActiveBinding,
            typedFailures: [],
            bindingVerdicts: verdicts,
            derivationTrace: SRSVALDerivationTrace(entries: trace)
        )
    }

    // MARK: - G-V structural evaluations

    /// Returns the G-V domain index (0-based) of a hard block.
    static func domain(of failure: SRSVALHardBlock) -> Int {
        switch failure {
        case .srsSettlementIdentityMissing, .srsBirthStatusNotDeclaredSettled,
             .srsSourceRelationBindingMissing, .srsCanonicalIdentityRuleRequiredButNotExact,
             .srsResultIdentityNotDistinct, .srsProvenanceBindingsMissing:
            return 0
        case .sourceRelationIdentityNotExact, .sourceRelationSemanticsNotExact,
             .sourceRelationApplicabilityCoverageMissing, .sourceRelationInvalidationUnlawfullyHandled:
            return 1
        case .dependencyRevisionBindingNotExact, .dependencyUnresolved, .dependencyIntegrityMissing,
             .dependencyRoleMissing, .dependencyNecessityMissing, .dependencyBlockingSupersession,
             .dependencyBlockingInvalidation:
            return 2
        case .resultIdentityOrRevisionMissing, .resultResolvedWithRecomputation, .resultIntegrityMissing,
             .resultNotInterpretable, .resultSupersededOrInvalidated:
            return 3
        case .resolutionRuleBindingNotExact, .policyVersionBindingsMissing:
            return 4
        case .provenanceEvidenceMissing, .lifecycleContested, .lifecycleUnresolvedConflict,
             .lifecycleInvalidated, .lifecycleIndeterminate:
            return 5
        case .freshnessEvidenceMissing, .freshnessRecheckRequired:
            return 6
        }
    }

    static func evaluateGV1(_ srs: SRSVALSRSEvidence) -> [SRSVALHardBlock] {
        var failures: [SRSVALHardBlock] = []
        if srs.settlementIdentity.isEmpty {
            failures.append(.srsSettlementIdentityMissing)
        }
        if srs.birthStatus != .declaredSettled {
            failures.append(.srsBirthStatusNotDeclaredSettled)
        }
        if srs.sourceRelationBinding.isEmpty {
            failures.append(.srsSourceRelationBindingMissing)
        }
        if srs.canonicalIdentityRuleApplicable {
            if case .exact = srs.canonicalIdentityRule {} else {
                failures.append(.srsCanonicalIdentityRuleRequiredButNotExact)
            }
        }
        if !srs.resultIdentity.isEmpty, srs.resultIdentity == srs.settlementIdentity {
            failures.append(.srsResultIdentityNotDistinct)
        }
        if srs.provenanceBindings.isEmpty {
            failures.append(.srsProvenanceBindingsMissing)
        }
        return failures
    }

    static func evaluateGV2(_ relation: SRSVALSourceRelationEvidence) -> [SRSVALHardBlock] {
        var failures: [SRSVALHardBlock] = []
        if case .exact = relation.sourceIdentity {} else {
            failures.append(.sourceRelationIdentityNotExact)
        }
        if case .exact = relation.semanticsIdentity {} else {
            failures.append(.sourceRelationSemanticsNotExact)
        }
        if relation.applicabilityCoverage.isEmpty {
            failures.append(.sourceRelationApplicabilityCoverageMissing)
        }
        if relation.invalidationRecords.contains(where: { $0.handling == .hardBlockViolation }) {
            failures.append(.sourceRelationInvalidationUnlawfullyHandled)
        }
        return failures
    }

    static func evaluateGV3(_ dependencies: [SRSVALDependencyEvidence]) -> [SRSVALHardBlock] {
        var failures: [SRSVALHardBlock] = []
        for dependency in dependencies {
            let id = dependency.dependencyIdentity
            if case .exact = dependency.revisionBinding {} else {
                failures.append(.dependencyRevisionBindingNotExact(dependencyIdentity: id))
            }
            if !dependency.resolved {
                failures.append(.dependencyUnresolved(dependencyIdentity: id))
            }
            if dependency.integrityReference.isEmpty {
                failures.append(.dependencyIntegrityMissing(dependencyIdentity: id))
            }
            if dependency.role.isEmpty {
                failures.append(.dependencyRoleMissing(dependencyIdentity: id))
            }
            if dependency.necessity.isEmpty {
                failures.append(.dependencyNecessityMissing(dependencyIdentity: id))
            }
            if dependency.blockingSupersession {
                failures.append(.dependencyBlockingSupersession(dependencyIdentity: id))
            }
            if dependency.blockingInvalidation {
                failures.append(.dependencyBlockingInvalidation(dependencyIdentity: id))
            }
        }
        return failures
    }

    static func evaluateGV4(_ result: SRSVALResultEvidence) -> [SRSVALHardBlock] {
        var failures: [SRSVALHardBlock] = []
        if result.resultIdentity.isEmpty || result.resultRevision.isEmpty {
            failures.append(.resultIdentityOrRevisionMissing)
        }
        if !result.resolvedWithoutRecomputation {
            failures.append(.resultResolvedWithRecomputation)
        }
        if result.integrityReference.isEmpty {
            failures.append(.resultIntegrityMissing)
        }
        if !result.interpretable {
            failures.append(.resultNotInterpretable)
        }
        if result.superseded || result.invalidated {
            failures.append(.resultSupersededOrInvalidated)
        }
        return failures
    }

    static func evaluateGV5(
        _ resolution: SRSVALResolutionEvidence,
        _ policy: SRSVALPolicyEvidence
    ) -> [SRSVALHardBlock] {
        var failures: [SRSVALHardBlock] = []
        if case .exact = resolution.ruleBinding {} else {
            failures.append(.resolutionRuleBindingNotExact)
        }
        if policy.applicablePolicyVersions.isEmpty {
            failures.append(.policyVersionBindingsMissing)
        }
        return failures
    }

    static func evaluateGV6(
        _ provenance: SRSVALProvenanceEvidence,
        _ lifecycle: SRSVALLifecycleEvidence
    ) -> [SRSVALHardBlock] {
        var failures: [SRSVALHardBlock] = []
        let components: [(String, String)] = [
            ("production", provenance.productionEvidence),
            ("declaration", provenance.declarationEvidence),
            ("dependency", provenance.dependencyEvidence),
            ("result", provenance.resultEvidence),
            ("ordering", provenance.orderingEvidence),
        ]
        for (name, value) in components where value.isEmpty {
            failures.append(.provenanceEvidenceMissing(component: name))
        }
        switch lifecycle.state {
        case .determinate:
            break
        case .contested:
            failures.append(.lifecycleContested)
        case .unresolvedLifecycleConflict:
            failures.append(.lifecycleUnresolvedConflict)
        case .invalidated:
            failures.append(.lifecycleInvalidated)
        case .indeterminate:
            failures.append(.lifecycleIndeterminate)
        }
        return failures
    }

    static func evaluateGV7(_ requirements: [SRSVALFreshnessRequirement]) -> [SRSVALHardBlock] {
        var failures: [SRSVALHardBlock] = []
        for requirement in requirements {
            switch requirement.state {
            case .cleared(let reference):
                if reference.isEmpty {
                    failures.append(.freshnessEvidenceMissing(requirementID: requirement.requirementID))
                }
            case .recheckRequired:
                failures.append(.freshnessRecheckRequired(requirementID: requirement.requirementID))
            case .evidenceMissing:
                failures.append(.freshnessEvidenceMissing(requirementID: requirement.requirementID))
            }
        }
        return failures
    }

    // MARK: - Helpers

    static func failureName(_ failure: SRSVALApplicabilityFailure) -> String {
        switch failure {
        case .i15Missing: return "I15_MISSING"
        case .i15Ambiguous: return "I15_AMBIGUOUS"
        case .i15Unstable: return "I15_UNSTABLE"
        case .i15Unmatched: return "I15_UNMATCHED"
        case .notApplicable: return "NOT_APPLICABLE"
        }
    }

    static func markerValidity(
        for invocation: SRSVALInvocation,
        resolvedByHigherPrecedence: Bool
    ) -> SRSVALI14MarkerValidity {
        switch invocation.governingAuthorization {
        case .notUsedNoRecomputePath:
            return resolvedByHigherPrecedence ? .validHigherPrecedenceResolved : .validNoFailureRemains
        case .active:
            return .notApplicableActiveBinding
        }
    }

    static func standardVerdicts(_ invocation: SRSVALInvocation) -> [SRSVALBindingVerdict] {
        var verdicts: [SRSVALBindingVerdict] = []
        verdicts.append(SRSVALBindingVerdict(binding: "OBSERVATION_BOUNDARY", verdict: "single-consistent-boundary"))
        switch invocation.reuseRequest {
        case .exact:
            verdicts.append(SRSVALBindingVerdict(binding: "I-15", verdict: "exact-and-matched"))
        default:
            verdicts.append(SRSVALBindingVerdict(binding: "I-15", verdict: "deficient"))
        }
        switch invocation.governingAuthorization {
        case .notUsedNoRecomputePath:
            verdicts.append(SRSVALBindingVerdict(binding: "I-14", verdict: "I14_NOT_USED_NO_RECOMPUTE_PATH"))
        case .active:
            verdicts.append(SRSVALBindingVerdict(binding: "I-14", verdict: "active-binding-declared"))
        }
        switch invocation.predicateRule {
        case .notUsed:
            verdicts.append(SRSVALBindingVerdict(binding: "PREDICATE_RULE", verdict: "not-bound"))
        case .registered(.exact(let artifact)):
            verdicts.append(SRSVALBindingVerdict(binding: "PREDICATE_RULE", verdict: "\(artifact.ruleIdentity)@\(artifact.ruleVersion)"))
        case .registered:
            verdicts.append(SRSVALBindingVerdict(binding: "PREDICATE_RULE", verdict: "deficient"))
        }
        return verdicts
    }

    static func block(
        path: SRSVALDecisionPath,
        markerValidity: SRSVALI14MarkerValidity,
        failures: [SRSVALFailure],
        trace: inout [SRSVALTraceEntry]
    ) -> SRSVALDecisionOutput {
        SRSVALDecisionOutput(
            primaryDecision: .block,
            decisionPath: path,
            i14MarkerValidity: markerValidity,
            typedFailures: failures,
            bindingVerdicts: [],
            derivationTrace: SRSVALDerivationTrace(entries: trace)
        )
    }
}

// MARK: - Implementation faithfulness traceability (Authorization Package v0.6 §3.6)

/// Machine-readable traceability matrix: every frozen rule implemented by this
/// module maps to its component and forbidden alternate behavior. No
/// implementation may weaken, strengthen, reorder, omit, or reinterpret a
/// frozen rule; no mutable pointer may replace an exact binding; no missing
/// evidence may be interpreted as a pass.
public enum SRSVALTraceability {
    public struct Row: Equatable, Sendable {
        public let rule: String
        public let component: String
        public let forbiddenAlternateBehavior: String

        public init(rule: String, component: String, forbiddenAlternateBehavior: String) {
            self.rule = rule
            self.component = component
            self.forbiddenAlternateBehavior = forbiddenAlternateBehavior
        }
    }

    public static let matrix: [Row] = [
        Row(rule: "I-14", component: "SRSVALI14Reference / SRSVALI14Binding / DP-3 envelope checks",
            forbiddenAlternateBehavior: "RECOMPUTE without exact I-14 coverage; treating missing I-14 as pass"),
        Row(rule: "I-15", component: "SRSVALReuseRequestBinding / DP-2 evaluation",
            forbiddenAlternateBehavior: "reuse with missing/unstable/ambiguous/unmatched request"),
        Row(rule: "I-16", component: "SRSVALObservationBoundary + per-evidence boundaryIdentity + DP-0 checks",
            forbiddenAlternateBehavior: "accepting mixed boundaries or integrity-invalid decision-critical input"),
        Row(rule: "G-V1", component: "evaluateGV1",
            forbiddenAlternateBehavior: "accepting non-DECLARED_SETTLED birth, non-distinct result identity, missing provenance bindings"),
        Row(rule: "G-V2", component: "evaluateGV2",
            forbiddenAlternateBehavior: "accepting inexact source identity/semantics or unlawfully handled invalidation"),
        Row(rule: "G-V3", component: "evaluateGV3",
            forbiddenAlternateBehavior: "accepting unresolved/inexact-revision/blocking-superseded dependencies"),
        Row(rule: "G-V4", component: "evaluateGV4",
            forbiddenAlternateBehavior: "accepting recomputed-result resolution, superseded/invalidated results"),
        Row(rule: "G-V5", component: "evaluateGV5",
            forbiddenAlternateBehavior: "accepting unstable resolution rule or empty policy versions"),
        Row(rule: "G-V6", component: "evaluateGV6",
            forbiddenAlternateBehavior: "accepting CONTESTED / UNRESOLVED_LIFECYCLE_CONFLICT / INVALIDATED reusable state"),
        Row(rule: "G-V7", component: "evaluateGV7",
            forbiddenAlternateBehavior: "interpreting FRESHNESS_RECHECK_REQUIRED as cleared without positive lawful evidence"),
        Row(rule: "G-CLASS", component: "classification gate in evaluate(_:)",
            forbiddenAlternateBehavior: "resolving BLOCKED_NON_RECOMPUTE or RECOMPUTE with skipped classification"),
        Row(rule: "DP-0", component: "boundary consistency stage",
            forbiddenAlternateBehavior: "proceeding past inconsistent/ambiguous/unstable boundaries"),
        Row(rule: "DP-1", component: "G-V hard-block stage",
            forbiddenAlternateBehavior: "downgrading hard blocks to classifiable failures"),
        Row(rule: "DP-2", component: "applicability stage",
            forbiddenAlternateBehavior: "reusing under NOT_APPLICABLE or INDETERMINATE applicability"),
        Row(rule: "DP-3", component: "recompute-authorization stage",
            forbiddenAlternateBehavior: "RECOMPUTE from failure alone without rule classification and I-14 envelope"),
        Row(rule: "DP-4", component: "reuse stage",
            forbiddenAlternateBehavior: "requiring I-14 for pure REUSE"),
        Row(rule: "PATHS", component: "SRSVALDecisionPath",
            forbiddenAlternateBehavior: "presenting incomplete classification as a completed path"),
        Row(rule: "INV-SRS-VAL-57", component: "classification gate",
            forbiddenAlternateBehavior: "skipping classification of any surviving failure"),
        Row(rule: "INV-SRS-VAL-58", component: "SRSVALI14MarkerValidity",
            forbiddenAlternateBehavior: "using the not-used marker to represent skipped classification"),
        Row(rule: "INV-SRS-VAL-59", component: "BLOCKED_NON_RECOMPUTE resolution",
            forbiddenAlternateBehavior: "blocked-non-recompute without higher-precedence resolution or completed classification"),
        Row(rule: "H1", component: "SRSVALPredicateRuleArtifact as data input",
            forbiddenAlternateBehavior: "core naming/versioning/registering itself as the predicate rule"),
        Row(rule: "H2", component: "SRSVALDerivationTrace.traceLabel",
            forbiddenAlternateBehavior: "presenting the derivation trace as observer-authoritative execution evidence"),
        Row(rule: "H3", component: "closed Equatable value-graph input types",
            forbiddenAlternateBehavior: "lazy resolvers, handles, callbacks, clocks, registries, or mutable references in the graph"),
    ]
}
