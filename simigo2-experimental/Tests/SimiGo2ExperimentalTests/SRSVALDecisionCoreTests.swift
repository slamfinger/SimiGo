import Crypto
import XCTest

@testable import SimiGo2Experimental

final class SRSVALDecisionCoreTests: XCTestCase {
  private func digest(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private func binding(_ identity: String, version: String = "V1") -> SRSVALBinding {
    SRSVALBinding(
      identity: identity, version: version, contentDigest: digest("EXACT:\(identity):\(version)"))
  }

  private func freshnessRule(subject: String, classification: SRSVALClassification)
    -> SRSVALRegisteredPredicateRule
  {
    let content = "FRESHNESS_RECHECK_REQUIRED:\(subject):\(classification.rawValue)"
    let predicate = SRSVALBinding(
      identity: "PREDICATE:FRESHNESS:\(subject)",
      version: "REGISTERED_V1",
      contentDigest: digest(content)
    )
    return SRSVALRegisteredPredicateRule(
      predicateRule: predicate,
      content: content,
      failureClass: "FRESHNESS_RECHECK_REQUIRED",
      subjectIdentities: [subject]
    )
  }

  private func validSourceRelation() -> SRSVALSourceRelation {
    SRSVALSourceRelation(
      binding: binding("RELATION"),
      semanticBinding: binding("RELATION-SEMANTICS"),
      applicabilityCoverage: binding("RELATION-COVERAGE"),
      invalidationRecord: binding("RELATION-INVALIDATION"),
      invalidationStatus: .none,
      identityRule: binding("RELATION-IDENTITY-RULE"),
      status: .current
    )
  }

  private func validSettledRelationState(
    sourceRelationIdentity: String = "RELATION",
    resultIdentity: String = "RESULT"
  ) -> SRSVALSettledRelationState {
    SRSVALSettledRelationState(
      binding: binding("SRS"),
      settlementID: "SETTLEMENT-01",
      status: "DECLARED_SETTLED",
      sourceRelationIdentity: sourceRelationIdentity,
      resultIdentity: resultIdentity,
      requiresCanonicalIdentityRule: true,
      canonicalIdentityRule: binding("RELATION-IDENTITY-RULE"),
      provenanceBindings: [binding("SRS-PROVENANCE")]
    )
  }

  private func validDependencies(resolution: SRSVALResolutionStatus = .resolved)
    -> SRSVALDependencySet
  {
    SRSVALDependencySet(
      boundary: binding("DEPENDENCY-BOUNDARY"),
      dependencies: [
        SRSVALDependency(
          binding: binding("DEPENDENCY"),
          role: "REQUIRED_INPUT",
          necessity: "REQUIRED",
          resolution: resolution,
          status: .current
        )
      ]
    )
  }

  private func validResult(resolution: SRSVALResultResolution = .resolvedWithoutRecompute)
    -> SRSVALResult
  {
    SRSVALResult(
      binding: binding("RESULT"),
      resolution: resolution,
      interpretabilityEvidence: binding("RESULT-INTERPRETABILITY"),
      status: .current
    )
  }

  private func validPolicy() -> SRSVALResolutionPolicy {
    SRSVALResolutionPolicy(
      resolutionRule: binding("RESOLUTION-RULE"),
      policies: [binding("POLICY")],
      boundary: binding("POLICY-BOUNDARY")
    )
  }

  private func validProvenance() -> SRSVALProvenanceLifecycle {
    SRSVALProvenanceLifecycle(
      bindings: [binding("SRS-PROVENANCE")],
      lifecycle: .declaredSettled,
      boundary: binding("PROVENANCE-BOUNDARY")
    )
  }

  private func validLifecycle() -> SRSVALProvenanceLifecycle {
    SRSVALProvenanceLifecycle(
      bindings: [binding("LIFECYCLE")],
      lifecycle: .declaredSettled,
      boundary: binding("LIFECYCLE-BOUNDARY")
    )
  }

  private func freshnessRequirement(
    identity: String,
    status: SRSVALFreshnessStatus = .current,
    mismatchEvidence: Bool = false,
    expectedEvidenceDigest: String? = nil,
    validUntil: String? = "2030-01-01T00:00:00Z",
    observedAt: String? = "2026-10-11T00:00:00Z"
  ) -> SRSVALFreshnessRequirement {
    SRSVALFreshnessRequirement(
      identity: identity,
      evidence: SRSVALBinding(
        identity: "FRESHNESS_EVIDENCE:\(identity)",
        version: "EVIDENCE_V1",
        contentDigest: digest(mismatchEvidence ? "WRONG-FRESHNESS:\(identity)" : "FRESHNESS:\(identity)")
      ),
      expectedEvidenceDigest: expectedEvidenceDigest ?? digest("FRESHNESS:\(identity)"),
      status: status,
      validUntilUTC: validUntil,
      observedAtUTC: observedAt
    )
  }

  private func validFreshness(
    requirements: [SRSVALFreshnessRequirement]?? = nil
  ) -> SRSVALFreshness {
    SRSVALFreshness(
      boundary: binding("FRESHNESS-BOUNDARY"),
      requirements: requirements ?? [freshnessRequirement(identity: "FRESHNESS")]
    )
  }

  private func validRequest(applicability: SRSVALRequestApplicability = .applicable)
    -> SRSVALReuseRequest
  {
    SRSVALReuseRequest(
      binding: binding("I-15"),
      requestClass: "EXACT_REUSE_REQUEST",
      relationIdentity: "RELATION",
      resultIdentity: "RESULT",
      declaredApplicability: applicability
    )
  }

  private func validAuthorization(
    invalidationClasses: Set<String> = ["FRESHNESS_RECHECK_REQUIRED"],
    targetBoundary: SRSVALBinding?? = nil,
    relationIdentityRule: SRSVALBinding?? = nil
  ) -> SRSVALRecomputeAuthorization {
    let target = targetBoundary ?? binding("I-16")
    let identityRule = relationIdentityRule ?? binding("RELATION-IDENTITY-RULE")
    let content = "I-14:RELATION:RESULT:FRESHNESS_RECHECK_REQUIRED"
    return SRSVALRecomputeAuthorization(
      binding: SRSVALBinding(identity: "I-14", version: "AUTH_V1", contentDigest: digest(content)),
      content: content,
      sourceRelationIdentity: "RELATION",
      invalidationClasses: invalidationClasses,
      requestClass: "EXACT_REUSE_REQUEST",
      authorizedResultIdentity: "RESULT",
      semanticClass: "EXACT_SEMANTIC_RECOMPUTE",
      envelope: SRSVALRecomputeEnvelope(
        coveredFailureClasses: Array(invalidationClasses),
        targetBoundary: target,
        relationIdentityRule: identityRule
      )
    )
  }

  private func validObservation(
    request: SRSVALReuseRequest,
    authorization: SRSVALRecomputeAuthorization?,
    state: SRSVALSettledRelationState,
    dependencies: SRSVALDependencySet,
    result: SRSVALResult,
    provenance: SRSVALProvenanceLifecycle,
    lifecycle: SRSVALProvenanceLifecycle,
    freshness: SRSVALFreshness,
    policy: SRSVALResolutionPolicy,
    boundary: SRSVALBinding? = nil,
    registeredRules: [SRSVALRegisteredPredicateRule] = [],
    classifications: [SRSVALPredicateClassification] = []
  ) -> SRSVALObservation {
    let resolvedBoundary = boundary ?? binding("I-16")
    return SRSVALObservation(
      boundary: resolvedBoundary,
      orderingEvidence: binding("ORDERING"),
      srsEvidence: state.binding,
      dependencyEvidence: dependencies.boundary,
      resultEvidence: result.binding,
      provenanceEvidence: provenance.boundary,
      freshnessPolicyEvidence: freshness.boundary,
      lifecycleEvidence: lifecycle.boundary,
      policyEvidence: policy.boundary,
      consistencyEvidence: binding("CONSISTENCY"),
      closeBoundary: resolvedBoundary,
      requestReference: request.binding,
      i14Reference: authorization?.binding ?? SRSVALDecisionCore.i14NotUsedMarker,
      predicateRuleReferences: registeredRules.map { $0.predicateRule },
      predicateClassifications: classifications
    )
  }

  private func baseInputs(
    sourceRelationIdentity: String = "RELATION",
    resultIdentity: String = "RESULT",
    dependencies: SRSVALDependencySet? = nil,
    resultResolution: SRSVALResultResolution = .resolvedWithoutRecompute,
    lifecycle: SRSVALLifecycleState = .declaredSettled,
    requirements: [SRSVALFreshnessRequirement]?? = nil,
    sourceInvalidationStatus: SRSVALSourceInvalidationStatus = .none
  ) -> (
    SRSVALSettledRelationState,
    SRSVALSourceRelation,
    SRSVALDependencySet,
    SRSVALResult,
    SRSVALProvenanceLifecycle,
    SRSVALProvenanceLifecycle,
    SRSVALFreshness,
    SRSVALResolutionPolicy,
    SRSVALReuseRequest
  ) {
    let source = validSourceRelation()
    let state = validSettledRelationState(
      sourceRelationIdentity: sourceRelationIdentity,
      resultIdentity: resultIdentity
    )
    return (
      state,
      sourceRelationIdentity == "RELATION" && sourceInvalidationStatus == .none
        ? source
        : SRSVALSourceRelation(
          binding: source.binding,
          semanticBinding: source.semanticBinding,
          applicabilityCoverage: source.applicabilityCoverage,
          invalidationRecord: source.invalidationRecord,
          invalidationStatus: sourceInvalidationStatus,
          identityRule: source.identityRule,
          status: source.status
        ),
      dependencies ?? validDependencies(),
      validResult(resolution: resultResolution),
      validProvenance(),
      SRSVALProvenanceLifecycle(
        bindings: [binding("LIFECYCLE")],
        lifecycle: lifecycle,
        boundary: binding("LIFECYCLE-BOUNDARY")
      ),
      validFreshness(requirements: requirements ?? [freshnessRequirement(identity: "FRESHNESS")]),
      validPolicy(),
      validRequest()
    )
  }

  private func evaluate(
    state: SRSVALSettledRelationState,
    source: SRSVALSourceRelation,
    dependencies: SRSVALDependencySet,
    result: SRSVALResult,
    provenance: SRSVALProvenanceLifecycle,
    lifecycle: SRSVALProvenanceLifecycle,
    freshness: SRSVALFreshness,
    policy: SRSVALResolutionPolicy,
    request: SRSVALReuseRequest,
    registeredRules: [SRSVALRegisteredPredicateRule]?,
    authorization: SRSVALRecomputeAuthorization?,
    observation: SRSVALObservation
  ) -> SRSVALDecisionOutcome {
    SRSVALDecisionCore.evaluate(
      settledRelationState: state,
      sourceRelation: source,
      dependencies: dependencies,
      result: result,
      provenance: provenance,
      lifecycle: lifecycle,
      freshness: freshness,
      policy: policy,
      reuseRequest: request,
      registeredPredicateRules: registeredRules,
      authorization: authorization,
      observation: observation
    )
  }

  private func evaluateBase(
    sourceRelationIdentity: String = "RELATION",
    resultIdentity: String = "RESULT",
    dependencies: SRSVALDependencySet? = nil,
    resultResolution: SRSVALResultResolution = .resolvedWithoutRecompute,
    lifecycle: SRSVALLifecycleState = .declaredSettled,
    requirements: [SRSVALFreshnessRequirement]?? = nil,
    sourceInvalidationStatus: SRSVALSourceInvalidationStatus = .none,
    registeredRules: [SRSVALRegisteredPredicateRule]? = [],
    classifications: [SRSVALPredicateClassification] = [],
    authorization: SRSVALRecomputeAuthorization? = nil,
    observationOverride: ((inout SRSVALObservation) -> Void)? = nil
  ) -> SRSVALDecisionOutcome {
    let inputs = baseInputs(
      sourceRelationIdentity: sourceRelationIdentity,
      resultIdentity: resultIdentity,
      dependencies: dependencies,
      resultResolution: resultResolution,
      lifecycle: lifecycle,
      requirements: requirements,
      sourceInvalidationStatus: sourceInvalidationStatus
    )
    var observation = validObservation(
      request: inputs.8,
      authorization: authorization,
      state: inputs.0,
      dependencies: inputs.2,
      result: inputs.3,
      provenance: inputs.4,
      lifecycle: inputs.5,
      freshness: inputs.6,
      policy: inputs.7,
      registeredRules: registeredRules ?? [],
      classifications: classifications
    )
    observationOverride?(&observation)
    return evaluate(
      state: inputs.0,
      source: inputs.1,
      dependencies: inputs.2,
      result: inputs.3,
      provenance: inputs.4,
      lifecycle: inputs.5,
      freshness: inputs.6,
      policy: inputs.7,
      request: inputs.8,
      registeredRules: registeredRules,
      authorization: authorization,
      observation: observation
    )
  }

  private func eligibleClassifications(rules: [SRSVALRegisteredPredicateRule])
    -> [SRSVALPredicateClassification]
  {
    rules.map {
      SRSVALPredicateClassification(
        predicateRule: $0.predicateRule,
        failureClass: $0.failureClass,
        subjectIdentity: $0.subjectIdentities.first ?? "",
        classification: .recomputeEligible
      )
    }
  }

  private func nonEligibleClassifications(rules: [SRSVALRegisteredPredicateRule])
    -> [SRSVALPredicateClassification]
  {
    rules.map {
      SRSVALPredicateClassification(
        predicateRule: $0.predicateRule,
        failureClass: $0.failureClass,
        subjectIdentity: $0.subjectIdentities.first ?? "",
        classification: .nonRecompute
      )
    }
  }

  func testAllChecksPassResolvesPureReuse() {
    let outcome = evaluateBase()
    XCTAssertEqual(.reuse, outcome.decision)
    XCTAssertNil(outcome.reason)
    XCTAssertTrue(outcome.failures.isEmpty)
    XCTAssertNil(outcome.authorizationUsed)
    XCTAssertTrue(outcome.i14NotUsedMarkerValid)
  }

  func testMixedEligibleAndNonEligibleFailuresBlock() {
    let requirements = [
      freshnessRequirement(identity: "FRESH-A", status: .recheckRequired),
      freshnessRequirement(identity: "FRESH-B", status: .recheckRequired),
    ]
    let rules = [
      freshnessRule(subject: "FRESH-A", classification: .recomputeEligible),
      freshnessRule(subject: "FRESH-B", classification: .nonRecompute),
    ]
    let outcome = evaluateBase(
      requirements: requirements,
      registeredRules: rules,
      classifications: eligibleClassifications(rules: [rules[0]])
        + nonEligibleClassifications(rules: [rules[1]]),
      authorization: validAuthorization(
        invalidationClasses: ["FRESHNESS_RECHECK_REQUIRED"],
        targetBoundary: binding("I-16"),
        relationIdentityRule: binding("RELATION-IDENTITY-RULE")
      )
    )
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.freshnessRecheckRequired, outcome.reason)
    XCTAssertNil(outcome.authorizationUsed)
  }

  func testUnregisteredPredicateRuleFailsClosed() {
    let outcome = evaluateBase(
      requirements: [freshnessRequirement(identity: "FRESH-A", status: .recheckRequired)],
      registeredRules: [],
      classifications: []
    )
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.predicateRuleBindingUnstableOrMissing, outcome.reason)
  }

  func testRegisteredRuleWithoutSubjectCoverageFailsClosed() {
    let rule = freshnessRule(subject: "OTHER", classification: .recomputeEligible)
    let outcome = evaluateBase(
      requirements: [freshnessRequirement(identity: "FRESH-A", status: .recheckRequired)],
      registeredRules: [rule],
      classifications: [
        SRSVALPredicateClassification(
          predicateRule: rule.predicateRule,
          failureClass: "FRESHNESS_RECHECK_REQUIRED",
          subjectIdentity: "FRESH-A",
          classification: .recomputeEligible
        )
      ]
    )
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.predicateRuleBindingUnstableOrMissing, outcome.reason)
  }

  func testSRSRelationIdentityMismatchBlocks() {
    let outcome = evaluateBase(sourceRelationIdentity: "OTHER-RELATION")
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.srsDeclarationIntegrity, outcome.reason)
  }

  func testSRSResultIdentityMismatchBlocks() {
    let outcome = evaluateBase(resultIdentity: "OTHER-RESULT")
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.srsDeclarationIntegrity, outcome.reason)
  }

  func testSemanticallyInvalidObservationReferenceBlocks() {
    let outcome = evaluateBase { observation in
      observation = SRSVALObservation(
        boundary: observation.boundary,
        orderingEvidence: observation.orderingEvidence,
        srsEvidence: self.binding("OTHER-SRS"),
        dependencyEvidence: observation.dependencyEvidence,
        resultEvidence: observation.resultEvidence,
        provenanceEvidence: observation.provenanceEvidence,
        freshnessPolicyEvidence: observation.freshnessPolicyEvidence,
        lifecycleEvidence: observation.lifecycleEvidence,
        policyEvidence: observation.policyEvidence,
        consistencyEvidence: observation.consistencyEvidence,
        closeBoundary: observation.closeBoundary,
        requestReference: observation.requestReference,
        i14Reference: observation.i14Reference,
        predicateRuleReferences: observation.predicateRuleReferences,
        predicateClassifications: observation.predicateClassifications
      )
    }
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.validationInputStateInconsistent, outcome.reason)
  }

  func testI14InvalidationClassMismatchBlocks() {
    let authorization = validAuthorization(invalidationClasses: ["OTHER_CLASS"])
    let rules = [freshnessRule(subject: "FRESHNESS", classification: .recomputeEligible)]
    let outcome = evaluateBase(
      requirements: [freshnessRequirement(identity: "FRESHNESS", status: .recheckRequired)],
      registeredRules: rules,
      classifications: eligibleClassifications(rules: rules),
      authorization: authorization
    )
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.recomputeAuthorizationInvalid, outcome.reason)
  }

  func testI14TargetBoundaryMismatchBlocks() {
    let authorization = validAuthorization(targetBoundary: binding("OTHER-BOUNDARY"))
    let rules = [freshnessRule(subject: "FRESHNESS", classification: .recomputeEligible)]
    let outcome = evaluateBase(
      requirements: [freshnessRequirement(identity: "FRESHNESS", status: .recheckRequired)],
      registeredRules: rules,
      classifications: eligibleClassifications(rules: rules),
      authorization: authorization
    )
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.recomputeAuthorizationInvalid, outcome.reason)
  }

  func testI14RelationIdentityRuleMismatchBlocks() {
    let authorization = validAuthorization(relationIdentityRule: binding("OTHER-RULE"))
    let rules = [freshnessRule(subject: "FRESHNESS", classification: .recomputeEligible)]
    let outcome = evaluateBase(
      requirements: [freshnessRequirement(identity: "FRESHNESS", status: .recheckRequired)],
      registeredRules: rules,
      classifications: eligibleClassifications(rules: rules),
      authorization: authorization
    )
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.recomputeAuthorizationInvalid, outcome.reason)
  }

  func testBlockingSourceInvalidationPreventsReuse() {
    let outcome = evaluateBase(sourceInvalidationStatus: .invalidated)
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.sourceRelation, outcome.reason)
  }

  func testUnresolvedDependencyPreventsReuse() {
    let outcome = evaluateBase(dependencies: validDependencies(resolution: .unresolved))
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.dependencies, outcome.reason)
  }

  func testUnresolvedResultPreventsReuse() {
    let outcome = evaluateBase(resultResolution: .unresolved)
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.result, outcome.reason)
  }

  func testFreshnessEvidenceForDifferentRequirementPreventsPureReuse() {
    let outcome = evaluateBase(
      requirements: [freshnessRequirement(
        identity: "FRESHNESS",
        mismatchEvidence: true,
        expectedEvidenceDigest: digest("FRESHNESS:FRESHNESS")
      )],
      registeredRules: [],
      classifications: []
    )
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.predicateRuleBindingUnstableOrMissing, outcome.reason)
  }

  func testExpiredFreshnessEvidenceCannotReuseWithoutAuthorization() {
    let outcome = evaluateBase(
      requirements: [
        freshnessRequirement(
          identity: "FRESHNESS",
          status: .current,
          validUntil: "2020-01-01T00:00:00Z",
          observedAt: "2026-10-11T00:00:00Z"
        )
      ]
    )
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertNil(outcome.authorizationUsed)
  }

  func testContradictoryClassificationsFailClosedWithoutOrderDependence() {
    let rule = freshnessRule(subject: "FRESHNESS", classification: .recomputeEligible)
    let classifications = [
      SRSVALPredicateClassification(
        predicateRule: rule.predicateRule,
        failureClass: "FRESHNESS_RECHECK_REQUIRED",
        subjectIdentity: "FRESHNESS",
        classification: .recomputeEligible
      ),
      SRSVALPredicateClassification(
        predicateRule: rule.predicateRule,
        failureClass: "FRESHNESS_RECHECK_REQUIRED",
        subjectIdentity: "FRESHNESS",
        classification: .nonRecompute
      ),
    ]
    let forward = evaluateBase(
      requirements: [freshnessRequirement(identity: "FRESHNESS", status: .recheckRequired)],
      registeredRules: [rule],
      classifications: classifications
    )
    let reverse = evaluateBase(
      requirements: [freshnessRequirement(identity: "FRESHNESS", status: .recheckRequired)],
      registeredRules: [rule],
      classifications: classifications.reversed()
    )
    XCTAssertEqual(.block, forward.decision)
    XCTAssertEqual(.block, reverse.decision)
    XCTAssertEqual(forward.reason, reverse.reason)
  }

  func testAllEligibleFailuresWithExactI14AuthorizeRecompute() {
    let rules = [freshnessRule(subject: "FRESHNESS", classification: .recomputeEligible)]
    let outcome = evaluateBase(
      requirements: [freshnessRequirement(identity: "FRESHNESS", status: .recheckRequired)],
      registeredRules: rules,
      classifications: eligibleClassifications(rules: rules),
      authorization: validAuthorization()
    )
    XCTAssertEqual(.recompute, outcome.decision)
    XCTAssertEqual(.freshnessRecheckRequired, outcome.reason)
    XCTAssertEqual(validAuthorization().binding, outcome.authorizationUsed)
    XCTAssertFalse(outcome.i14NotUsedMarkerValid)
  }
}
