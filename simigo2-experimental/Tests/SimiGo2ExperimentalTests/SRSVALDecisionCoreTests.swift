import Crypto
import XCTest
@testable import SimiGo2Experimental

final class SRSVALDecisionCoreTests: XCTestCase {
  private func digest(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private func binding(_ identity: String, version: String = "V1") -> SRSVALBinding {
    SRSVALBinding(identity: identity, version: version, contentDigest: digest("EXACT:\(identity):\(version)"))
  }

  private let observedAt = "2026-10-11T00:00:00Z"
  private let boundary = SRSVALBinding(
    identity: "I-16",
    version: "OBSERVATION_V1",
    contentDigest: SHA256.hash(data: Data("OBSERVATION:I-16".utf8)).map { String(format: "%02x", $0) }.joined()
  )

  private func rule(
    subject: String,
    classification: SRSVALClassification,
    authorityBinding: SRSVALBinding? = nil
  ) -> SRSVALRegisteredPredicateRule? {
    SRSVALRegisteredPredicateRule.register(
      authority: SRSVALPredicateRuleAuthority(
        binding: authorityBinding ?? SRSVALPredicateRuleAuthority.required
      ),
      identity: subject,
      version: "RULE_V1",
      failureClass: "FRESHNESS_RECHECK_REQUIRED",
      subjectIdentities: [subject]
    )
  }

  private func sourceRelation() -> SRSVALSourceRelation {
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

  private func state(
    sourceRelationIdentity: String = "RELATION",
    resultIdentity: String = "RESULT"
  ) -> SRSVALSettledRelationState {
    SRSVALSettledRelationState(
      binding: binding("SRS"),
      settlementID: "SETTLEMENT",
      status: "DECLARED_SETTLED",
      sourceRelationIdentity: sourceRelationIdentity,
      resultIdentity: resultIdentity,
      requiresCanonicalIdentityRule: true,
      canonicalIdentityRule: binding("RELATION-IDENTITY-RULE"),
      provenanceBindings: [binding("SRS-PROVENANCE")]
    )
  }

  private func dependencies(resolution: SRSVALResolutionStatus = .resolved) -> SRSVALDependencySet {
    SRSVALDependencySet(
      boundary: boundary,
      dependencies: [SRSVALDependency(
        binding: binding("DEPENDENCY"),
        role: "REQUIRED_INPUT",
        necessity: "REQUIRED",
        resolution: resolution,
        status: .current
      )]
    )
  }

  private func result(resolution: SRSVALResultResolution = .resolvedWithoutRecompute) -> SRSVALResult {
    SRSVALResult(
      binding: binding("RESULT"),
      resolution: resolution,
      interpretabilityEvidence: binding("RESULT-INTERPRETABILITY"),
      status: .current
    )
  }

  private func provenance() -> SRSVALProvenanceLifecycle {
    SRSVALProvenanceLifecycle(
      bindings: [binding("SRS-PROVENANCE")],
      lifecycle: .declaredSettled,
      boundary: boundary
    )
  }

  private func lifecycle(_ state: SRSVALLifecycleState = .declaredSettled) -> SRSVALProvenanceLifecycle {
    SRSVALProvenanceLifecycle(
      bindings: [binding("LIFECYCLE")],
      lifecycle: state,
      boundary: boundary
    )
  }

  private func freshness(
    requirements: [SRSVALFreshnessRequirement]? = nil
  ) -> SRSVALFreshness {
    let resolvedRequirements = requirements ?? [defaultFreshnessRequirement()]
    return SRSVALFreshness(boundary: boundary, requirements: resolvedRequirements)
  }

  private func defaultFreshnessRequirement() -> SRSVALFreshnessRequirement {
    SRSVALFreshnessRequirement(
      identity: "FRESH-A",
      evidence: SRSVALBinding(
        identity: "FRESHNESS_EVIDENCE:FRESH-A",
        version: "V1",
        contentDigest: digest("FRESHNESS:FRESH-A")
      ),
      expectedEvidenceDigest: digest("FRESHNESS:FRESH-A"),
      status: .current,
      validUntilUTC: "2030-01-01T00:00:00Z",
      observedAtUTC: observedAt
    )
  }

  private func freshnessRequirement(
    identity: String,
    status: SRSVALFreshnessStatus = .current,
    validUntil: String = "2030-01-01T00:00:00Z",
    observedAt: String = "2026-10-11T00:00:00Z",
    digestMismatch: Bool = false,
    expectedDigest: String? = nil
  ) -> SRSVALFreshnessRequirement {
    SRSVALFreshnessRequirement(
      identity: identity,
      evidence: SRSVALBinding(
        identity: "FRESHNESS_EVIDENCE:\(identity)",
        version: "V1",
        contentDigest: digest(digestMismatch ? "WRONG:\(identity)" : "FRESHNESS:\(identity)")
      ),
      expectedEvidenceDigest: expectedDigest ?? digest("FRESHNESS:\(identity)"),
      status: status,
      validUntilUTC: validUntil,
      observedAtUTC: observedAt
    )
  }

  private func request(applicability: SRSVALRequestApplicability = .applicable) -> SRSVALReuseRequest {
    SRSVALReuseRequest(
      binding: binding("I-15"),
      requestClass: "EXACT_REUSE_REQUEST",
      relationIdentity: "RELATION",
      resultIdentity: "RESULT",
      declaredApplicability: applicability
    )
  }

  private func authorization(
    invalidationClasses: Set<String> = ["FRESHNESS_RECHECK_REQUIRED"],
    targetBoundary: SRSVALBinding? = nil,
    relationIdentityRule: SRSVALBinding? = nil
  ) -> SRSVALRecomputeAuthorization {
    SRSVALRecomputeAuthorization.authorize(
      sourceRelationIdentity: "RELATION",
      invalidationClasses: invalidationClasses,
      requestClass: "EXACT_REUSE_REQUEST",
      authorizedResultIdentity: "RESULT",
      semanticClass: "EXACT_SEMANTIC_RECOMPUTE",
      envelope: SRSVALRecomputeEnvelope(
        coveredFailureClasses: Array(invalidationClasses),
        targetBoundary: targetBoundary ?? boundary,
        relationIdentityRule: relationIdentityRule ?? binding("RELATION-IDENTITY-RULE")
      )
    )
  }

  private func observation(
    request: SRSVALReuseRequest,
    authorization: SRSVALRecomputeAuthorization?,
    state: SRSVALSettledRelationState,
    dependencies: SRSVALDependencySet,
    result: SRSVALResult,
    provenance: SRSVALProvenanceLifecycle,
    lifecycle: SRSVALProvenanceLifecycle,
    freshness: SRSVALFreshness,
    policy: SRSVALResolutionPolicy,
    registeredRules: [SRSVALRegisteredPredicateRule],
    classifications: [SRSVALPredicateClassification],
    observedAt: String? = nil,
    orderingEvidence: SRSVALBinding? = nil
  ) -> SRSVALObservation {
    let time = observedAt ?? self.observedAt
    return SRSVALObservation(
      boundary: boundary,
      orderingEvidence: orderingEvidence ?? binding("ORDERING_EVIDENCE:\(boundary.identity):\(time)"),
      observedAtUTC: time,
      srsEvidence: state.binding,
      dependencyEvidence: dependencies.boundary,
      resultEvidence: result.binding,
      provenanceEvidence: provenance.boundary,
      freshnessPolicyEvidence: freshness.boundary,
      lifecycleEvidence: lifecycle.boundary,
      policyEvidence: policy.boundary,
      consistencyEvidence: binding("CONSISTENCY"),
      closeBoundary: boundary,
      requestReference: request.binding,
      i14Reference: authorization?.binding ?? SRSVALDecisionCore.i14NotUsedMarker,
      predicateRuleReferences: registeredRules.map { $0.predicateRule },
      predicateClassifications: classifications
    )
  }

  private struct Inputs {
    let state: SRSVALSettledRelationState
    let source: SRSVALSourceRelation
    let dependencies: SRSVALDependencySet
    let result: SRSVALResult
    let provenance: SRSVALProvenanceLifecycle
    let lifecycle: SRSVALProvenanceLifecycle
    let freshness: SRSVALFreshness
    let policy: SRSVALResolutionPolicy
    let request: SRSVALReuseRequest
  }

  private func inputs(
    sourceRelationIdentity: String = "RELATION",
    resultIdentity: String = "RESULT",
    dependencyResolution: SRSVALResolutionStatus = .resolved,
    resultResolution: SRSVALResultResolution = .resolvedWithoutRecompute,
    lifecycleState: SRSVALLifecycleState = .declaredSettled,
    freshnessRequirements: [SRSVALFreshnessRequirement]? = nil,
    sourceInvalidation: SRSVALSourceInvalidationStatus = .none,
    requestApplicability: SRSVALRequestApplicability = .applicable
  ) -> Inputs {
    let source = sourceRelationIdentity == "RELATION" && sourceInvalidation == .none
      ? sourceRelation()
      : SRSVALSourceRelation(
        binding: binding("RELATION"),
        semanticBinding: binding("RELATION-SEMANTICS"),
        applicabilityCoverage: binding("RELATION-COVERAGE"),
        invalidationRecord: binding("RELATION-INVALIDATION"),
        invalidationStatus: sourceInvalidation,
        identityRule: binding("RELATION-IDENTITY-RULE"),
        status: .current
      )
    return Inputs(
      state: state(
        sourceRelationIdentity: sourceRelationIdentity,
        resultIdentity: resultIdentity
      ),
      source: source,
      dependencies: dependencies(resolution: dependencyResolution),
      result: result(resolution: resultResolution),
      provenance: provenance(),
      lifecycle: lifecycle(lifecycleState),
      freshness: freshness(requirements: freshnessRequirements),
      policy: SRSVALResolutionPolicy(
        resolutionRule: binding("RESOLUTION-RULE"),
        policies: [binding("POLICY")],
        boundary: boundary
      ),
      request: request(applicability: requestApplicability)
    )
  }

  private func evaluate(
    inputs: Inputs,
    registeredRules: [SRSVALRegisteredPredicateRule]? = [],
    classifications: [SRSVALPredicateClassification] = [],
    authorization: SRSVALRecomputeAuthorization? = nil,
    observationRecord: SRSVALObservation? = nil
  ) -> SRSVALDecisionOutcome {
    let selectedObservation = observationRecord ?? observation(
      request: inputs.request,
      authorization: authorization,
      state: inputs.state,
      dependencies: inputs.dependencies,
      result: inputs.result,
      provenance: inputs.provenance,
      lifecycle: inputs.lifecycle,
      freshness: inputs.freshness,
      policy: inputs.policy,
      registeredRules: registeredRules ?? [],
      classifications: classifications
    )
    return SRSVALDecisionCore.evaluate(
      settledRelationState: inputs.state,
      sourceRelation: inputs.source,
      dependencies: inputs.dependencies,
      result: inputs.result,
      provenance: inputs.provenance,
      lifecycle: inputs.lifecycle,
      freshness: inputs.freshness,
      policy: inputs.policy,
      reuseRequest: inputs.request,
      registeredPredicateRules: registeredRules,
      authorization: authorization,
      observation: selectedObservation
    )
  }

  private func eligibleClassifications(rules: [SRSVALRegisteredPredicateRule]) -> [SRSVALPredicateClassification] {
    rules.compactMap { rule in
      SRSVALPredicateClassification(
        predicateRule: rule.predicateRule,
        failureClass: rule.failureClass,
        subjectIdentity: rule.subjectIdentities.first ?? "",
        classification: .recomputeEligible
      )
    }
  }

  private func nonEligibleClassifications(rules: [SRSVALRegisteredPredicateRule]) -> [SRSVALPredicateClassification] {
    rules.compactMap { rule in
      SRSVALPredicateClassification(
        predicateRule: rule.predicateRule,
        failureClass: rule.failureClass,
        subjectIdentity: rule.subjectIdentities.first ?? "",
        classification: .nonRecompute
      )
    }
  }

  func testAllChecksPassResolvesPureReuse() {
    let inputs = inputs()
    let outcome = evaluate(inputs: inputs)
    XCTAssertEqual(.reuse, outcome.decision)
    XCTAssertNil(outcome.reason)
    XCTAssertTrue(outcome.failures.isEmpty)
    XCTAssertTrue(outcome.i14NotUsedMarkerValid)
  }

  func testDifferentObjectBoundaryFailsClosed() {
    let inputs = inputs()
    var observation = observation(
      request: inputs.request,
      authorization: nil,
      state: inputs.state,
      dependencies: inputs.dependencies,
      result: inputs.result,
      provenance: inputs.provenance,
      lifecycle: inputs.lifecycle,
      freshness: inputs.freshness,
      policy: inputs.policy,
      registeredRules: [],
      classifications: []
    )
    observation = SRSVALObservation(
      boundary: observation.boundary,
      orderingEvidence: observation.orderingEvidence,
      observedAtUTC: observation.observedAtUTC,
      srsEvidence: observation.srsEvidence,
      dependencyEvidence: binding("OTHER-DEPENDENCY-BOUNDARY"),
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
    let outcome = evaluate(inputs: inputs, observationRecord: observation)
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.validationInputStateInconsistent, outcome.reason)
  }

  func testMixedEligibleAndNonEligibleFailuresBlock() {
    let requirements = [
      freshnessRequirement(
        identity: "FRESH-A",
        status: .recheckRequired,
        validUntil: "2030-01-01T00:00:00Z",
        observedAt: observedAt
      ),
      freshnessRequirement(
        identity: "FRESH-B",
        status: .recheckRequired,
        validUntil: "2030-01-01T00:00:00Z",
        observedAt: observedAt
      ),
    ]
    let inputs = inputs(freshnessRequirements: requirements)
    let eligible = rule(subject: "FRESH-A", classification: .recomputeEligible)
    let nonEligible = rule(subject: "FRESH-B", classification: .nonRecompute)
    let rules = [eligible, nonEligible].compactMap { $0 }
    let outcome = evaluate(
      inputs: inputs,
      registeredRules: rules,
      classifications: eligibleClassifications(rules: [eligible!]) + nonEligibleClassifications(rules: [nonEligible!]),
      authorization: authorization(invalidationClasses: ["FRESHNESS_RECHECK_REQUIRED"])
    )
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.freshnessRecheckRequired, outcome.reason)
  }

  func testUnregisteredSubjectFailsClosed() {
    let requirements = [freshnessRequirement(
      identity: "FRESH-A",
      status: .recheckRequired,
      validUntil: "2030-01-01T00:00:00Z",
      observedAt: observedAt
    )]
    let inputs = inputs(freshnessRequirements: requirements)
    let outcome = evaluate(inputs: inputs)
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.predicateRuleBindingUnstableOrMissing, outcome.reason)
  }

  func testPredicateRuleCannotRegisterOutsideAuthoritativeRegistry() {
    XCTAssertNil(rule(
      subject: "UNAUTHORIZED",
      classification: .recomputeEligible,
      authorityBinding: binding("OTHER-REGISTRY")
    ))
  }

  func testSRSRelationIdentityMismatchBlocks() {
    let outcome = evaluate(inputs: inputs(sourceRelationIdentity: "OTHER-RELATION"))
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.srsDeclarationIntegrity, outcome.reason)
  }

  func testSRSResultIdentityMismatchBlocks() {
    let outcome = evaluate(inputs: inputs(resultIdentity: "OTHER-RESULT"))
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.srsDeclarationIntegrity, outcome.reason)
  }

  func testI14TargetBoundaryMismatchBlocks() {
    let requirements = [freshnessRequirement(
      identity: "FRESH-A",
      status: .recheckRequired,
      validUntil: "2030-01-01T00:00:00Z",
      observedAt: observedAt
    )]
    let inputs = inputs(freshnessRequirements: requirements)
    let rules = [rule(subject: "FRESH-A", classification: .recomputeEligible)].compactMap { $0 }
    let authorization = authorization(targetBoundary: binding("OTHER-I-16"))
    let outcome = evaluate(
      inputs: inputs,
      registeredRules: rules,
      classifications: eligibleClassifications(rules: rules),
      authorization: authorization
    )
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.recomputeAuthorizationInvalid, outcome.reason)
  }

  func testI14RelationIdentityRuleMismatchBlocks() {
    let requirements = [freshnessRequirement(
      identity: "FRESH-A",
      status: .recheckRequired,
      validUntil: "2030-01-01T00:00:00Z",
      observedAt: observedAt
    )]
    let inputs = inputs(freshnessRequirements: requirements)
    let rules = [rule(subject: "FRESH-A", classification: .recomputeEligible)].compactMap { $0 }
    let authorization = authorization(relationIdentityRule: binding("OTHER-RULE"))
    let outcome = evaluate(
      inputs: inputs,
      registeredRules: rules,
      classifications: eligibleClassifications(rules: rules),
      authorization: authorization
    )
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.recomputeAuthorizationInvalid, outcome.reason)
  }

  func testI14InvalidationClassMismatchBlocks() {
    let requirements = [freshnessRequirement(
      identity: "FRESH-A",
      status: .recheckRequired,
      validUntil: "2030-01-01T00:00:00Z",
      observedAt: observedAt
    )]
    let inputs = inputs(freshnessRequirements: requirements)
    let rules = [rule(subject: "FRESH-A", classification: .recomputeEligible)].compactMap { $0 }
    let authorization = authorization(invalidationClasses: ["OTHER_CLASS"])
    let outcome = evaluate(
      inputs: inputs,
      registeredRules: rules,
      classifications: eligibleClassifications(rules: rules),
      authorization: authorization
    )
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.recomputeAuthorizationInvalid, outcome.reason)
  }

  func testBlockingSourceInvalidationPreventsReuse() {
    let outcome = evaluate(inputs: inputs(sourceInvalidation: .invalidated))
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.sourceRelation, outcome.reason)
  }

  func testUnresolvedDependencyPreventsReuse() {
    let outcome = evaluate(inputs: inputs(dependencyResolution: .unresolved))
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.dependencies, outcome.reason)
  }

  func testUnresolvedResultPreventsReuse() {
    let outcome = evaluate(inputs: inputs(resultResolution: .unresolved))
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.result, outcome.reason)
  }

  func testFreshnessDigestMismatchFailsClosed() {
    let requirement = SRSVALFreshnessRequirement(
      identity: "FRESH-A",
      evidence: SRSVALBinding(
        identity: "FRESHNESS_EVIDENCE:FRESH-A",
        version: "V1",
        contentDigest: digest("WRONG-FRESHNESS:FRESH-A")
      ),
      expectedEvidenceDigest: digest("FRESHNESS:FRESH-A"),
      status: .current,
      validUntilUTC: "2030-01-01T00:00:00Z",
      observedAtUTC: observedAt
    )
    let outcome = evaluate(inputs: inputs(freshnessRequirements: [requirement]))
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertNotEqual(.reuse, outcome.decision)
  }

  func testExpiredFreshnessEvidenceFailsClosed() {
    let requirement = freshnessRequirement(
      identity: "FRESH-A",
      status: .current,
      validUntil: "2020-01-01T00:00:00Z",
      observedAt: observedAt
    )
    let outcome = evaluate(inputs: inputs(freshnessRequirements: [requirement]))
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertNil(outcome.authorizationUsed)
  }

  func testFreshnessObservationTimeMismatchFailsClosed() {
    let requirement = freshnessRequirement(
      identity: "FRESH-A",
      status: .current,
      validUntil: "2030-01-01T00:00:00Z",
      observedAt: observedAt
    )
    let inputs = inputs(freshnessRequirements: [requirement])
    let observation = observation(
      request: inputs.request,
      authorization: nil,
      state: inputs.state,
      dependencies: inputs.dependencies,
      result: inputs.result,
      provenance: inputs.provenance,
      lifecycle: inputs.lifecycle,
      freshness: inputs.freshness,
      policy: inputs.policy,
      registeredRules: [],
      classifications: [],
      observedAt: "2020-01-01T00:00:00Z"
    )
    let outcome = evaluate(inputs: inputs, observationRecord: observation)
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertNil(outcome.authorizationUsed)
  }

  func testOrderingEvidenceNotBoundToObservationTimeFailsClosed() {
    let inputs = inputs()
    let observation = observation(
      request: inputs.request,
      authorization: nil,
      state: inputs.state,
      dependencies: inputs.dependencies,
      result: inputs.result,
      provenance: inputs.provenance,
      lifecycle: inputs.lifecycle,
      freshness: inputs.freshness,
      policy: inputs.policy,
      registeredRules: [],
      classifications: [],
      orderingEvidence: binding("ORDERING_EVIDENCE:\(boundary.identity):1999-01-01T00:00:00Z")
    )
    let outcome = evaluate(inputs: inputs, observationRecord: observation)
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.validationInputStateInconsistent, outcome.reason)
  }

  func testContradictoryClassificationsFailClosedWithoutOrderDependence() {
    let requirements = [freshnessRequirement(
      identity: "FRESH-A",
      status: .recheckRequired,
      validUntil: "2030-01-01T00:00:00Z",
      observedAt: observedAt
    )]
    let inputs = inputs(freshnessRequirements: requirements)
    guard let rule = rule(subject: "FRESH-A", classification: .recomputeEligible) else {
      return XCTFail("registered rule expected")
    }
    let classifications = [
      SRSVALPredicateClassification(
        predicateRule: rule.predicateRule,
        failureClass: "FRESHNESS_RECHECK_REQUIRED",
        subjectIdentity: "FRESH-A",
        classification: .recomputeEligible
      ),
      SRSVALPredicateClassification(
        predicateRule: rule.predicateRule,
        failureClass: "FRESHNESS_RECHECK_REQUIRED",
        subjectIdentity: "FRESH-A",
        classification: .nonRecompute
      ),
    ]
    let forward = evaluate(inputs: inputs, registeredRules: [rule], classifications: classifications)
    let reverse = evaluate(inputs: inputs, registeredRules: [rule], classifications: classifications.reversed())
    XCTAssertEqual(.block, forward.decision)
    XCTAssertEqual(.block, reverse.decision)
    XCTAssertEqual(forward.reason, reverse.reason)
  }

  func testAllEligibleFailuresWithExactI14AuthorizeRecompute() {
    let requirements = [freshnessRequirement(
      identity: "FRESH-A",
      status: .recheckRequired,
      validUntil: "2030-01-01T00:00:00Z",
      observedAt: observedAt
    )]
    let inputs = inputs(freshnessRequirements: requirements)
    guard let rule = rule(subject: "FRESH-A", classification: .recomputeEligible) else {
      return XCTFail("registered rule expected")
    }
    let authorization = authorization()
    let outcome = evaluate(
      inputs: inputs,
      registeredRules: [rule],
      classifications: eligibleClassifications(rules: [rule]),
      authorization: authorization
    )
    XCTAssertEqual(.recompute, outcome.decision)
    XCTAssertEqual(.freshnessRecheckRequired, outcome.reason)
    XCTAssertEqual(authorization.binding, outcome.authorizationUsed)
    XCTAssertFalse(outcome.i14NotUsedMarkerValid)
  }
}
