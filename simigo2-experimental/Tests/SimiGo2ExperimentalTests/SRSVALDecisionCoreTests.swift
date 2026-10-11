import Crypto
import XCTest
@testable import SimiGo2Experimental

final class SRSVALDecisionCoreTests: XCTestCase {
  private func binding(_ identity: String, version: String = "V1") -> SRSVALBinding {
    let digest = SHA256.hash(data: Data("EXACT:\(identity):\(version)".utf8))
      .map { String(format: "%02x", $0) }.joined()
    return SRSVALBinding(identity: identity, version: version, contentDigest: digest)
  }

  private func freshnessPredicateRule() -> SRSVALBinding {
    let digest = SHA256.hash(data: Data("SRS-VAL-PREDICATE:FRESHNESS".utf8))
      .map { String(format: "%02x", $0) }.joined()
    return SRSVALBinding(identity: "FRESHNESS", version: "PREDICATE_V1", contentDigest: digest)
  }

  private func validSettledRelationState() -> SRSVALSettledRelationState {
    SRSVALSettledRelationState(
      binding: binding("SRS"),
      settlementID: "SETTLEMENT-01",
      status: "DECLARED_SETTLED",
      sourceRelationIdentity: "RELATION",
      resultIdentity: "RESULT",
      requiresCanonicalIdentityRule: false,
      canonicalIdentityRule: nil,
      provenanceBindings: [binding("SRS-PROVENANCE")]
    )
  }

  private func validSourceRelation() -> SRSVALSourceRelation {
    SRSVALSourceRelation(
      binding: binding("RELATION"),
      semanticBinding: binding("RELATION-SEMANTICS"),
      applicabilityCoverage: binding("RELATION-COVERAGE"),
      invalidationRecord: binding("RELATION-INVALIDATION"),
      status: .current
    )
  }

  private func validDependencies() -> [SRSVALDependency] {
    [SRSVALDependency(
      binding: binding("DEPENDENCY"),
      role: "REQUIRED_INPUT",
      necessity: "NECESSARY",
      resolution: "RESOLVED",
      status: .current
    )]
  }

  private func validResult() -> SRSVALResult {
    SRSVALResult(
      binding: binding("RESULT"),
      resolution: "RESOLVED_WITHOUT_RECOMPUTE",
      interpretabilityEvidence: binding("RESULT-INTERPRETABILITY"),
      status: .current
    )
  }

  private func validProvenance() -> SRSVALProvenanceLifecycle {
    SRSVALProvenanceLifecycle(bindings: [binding("PROVENANCE")], lifecycle: .declaredSettled)
  }

  private func validLifecycle() -> SRSVALProvenanceLifecycle {
    SRSVALProvenanceLifecycle(bindings: [binding("LIFECYCLE")], lifecycle: .declaredSettled)
  }

  private func validFreshness() -> SRSVALFreshness {
    SRSVALFreshness(requirements: [SRSVALFreshnessRequirement(identity: "FRESHNESS", evidence: binding("FRESHNESS-EVIDENCE"))])
  }

  private func missingFreshnessEvidence() -> SRSVALFreshness {
    SRSVALFreshness(requirements: [SRSVALFreshnessRequirement(identity: "FRESHNESS", evidence: nil)])
  }

  private func validPolicy() -> SRSVALResolutionPolicy {
    SRSVALResolutionPolicy(resolutionRule: binding("RESOLUTION-RULE"), policies: [binding("POLICY")])
  }

  private func validRequest(
    applicability: SRSVALRequestApplicability = .applicable
  ) -> SRSVALReuseRequest {
    SRSVALReuseRequest(
      binding: binding("I-15"),
      requestClass: "EXACT_REUSE_REQUEST",
      relationIdentity: "RELATION",
      resultIdentity: "RESULT",
      declaredApplicability: applicability
    )
  }

  private func validAuthorization() -> SRSVALRecomputeAuthorization {
    SRSVALRecomputeAuthorization(
      binding: binding("I-14", version: "AUTH-V1"),
      sourceRelationIdentity: "RELATION",
      invalidationClass: "FRESHNESS_RECHECK_REQUIRED",
      requestClass: "EXACT_REUSE_REQUEST",
      authorizedResultIdentity: "RESULT",
      semanticClass: "EXACT_SEMANTIC_RECOMPUTE",
      envelope: SRSVALRecomputeEnvelope(
        coveredFailureClasses: ["FRESHNESS_RECHECK_REQUIRED"],
        targetBoundary: binding("I-14-TARGET"),
        relationIdentityRule: binding("RELATION-IDENTITY-RULE")
      )
    )
  }

  private func validObservation(
    request: SRSVALReuseRequest,
    authorization: SRSVALRecomputeAuthorization?,
    predicateRule: SRSVALBinding? = nil,
    classifications: [SRSVALPredicateClassification] = [],
    boundary: SRSVALBinding? = nil
  ) -> SRSVALObservation {
    let resolvedBoundary = boundary ?? binding("I-16")
    return SRSVALObservation(
      boundary: resolvedBoundary,
      orderingEvidence: binding("ORDERING"),
      srsEvidence: binding("OBSERVED-SRS"),
      dependencyEvidence: binding("OBSERVED-DEPENDENCIES"),
      resultEvidence: binding("OBSERVED-RESULT"),
      freshnessPolicyEvidence: binding("OBSERVED-FRESHNESS"),
      lifecycleEvidence: binding("OBSERVED-LIFECYCLE"),
      consistencyEvidence: binding("CONSISTENCY"),
      closeBoundary: binding("CLOSE-BOUNDARY"),
      requestReference: request.binding,
      i14Reference: authorization?.binding ?? SRSVALDecisionCore.i14NotUsedMarker,
      predicateRuleReferences: predicateRule.map { [$0] } ?? [],
      predicateClassifications: classifications
    )
  }

  private func evaluate(
    settledRelationState: SRSVALSettledRelationState? = nil,
    sourceRelation: SRSVALSourceRelation? = nil,
    dependencies: [SRSVALDependency]? = nil,
    result: SRSVALResult? = nil,
    provenance: SRSVALProvenanceLifecycle? = nil,
    lifecycle: SRSVALProvenanceLifecycle? = nil,
    request: SRSVALReuseRequest? = nil,
    authorization: SRSVALRecomputeAuthorization? = nil,
    freshness: SRSVALFreshness? = nil,
    policy: SRSVALResolutionPolicy? = nil,
    observation: SRSVALObservation? = nil
  ) -> SRSVALDecisionOutcome {
    SRSVALDecisionCore.evaluate(
      settledRelationState: settledRelationState ?? validSettledRelationState(),
      sourceRelation: sourceRelation ?? validSourceRelation(),
      dependencies: dependencies ?? validDependencies(),
      result: result ?? validResult(),
      provenance: provenance ?? validProvenance(),
      lifecycle: lifecycle ?? validLifecycle(),
      freshness: freshness ?? validFreshness(),
      policy: policy ?? validPolicy(),
      reuseRequest: request ?? validRequest(),
      authorization: authorization,
      observation: observation ?? validObservation(request: request ?? validRequest(), authorization: authorization)
    )
  }

  func testGVAllChecksPassMapsToDP4PureReuse() {
    let outcome = evaluate()
    XCTAssertEqual(.reuse, outcome.decision)
    XCTAssertNil(outcome.reason)
    XCTAssertTrue(outcome.failures.isEmpty)
    XCTAssertNil(outcome.authorizationUsed)
    XCTAssertTrue(outcome.i14NotUsedMarkerValid)
  }

  func testDP0MissingObservationFieldFailsClosed() {
    let request = validRequest()
    let invalidBoundary = SRSVALBinding(identity: "", version: "", contentDigest: "")
    let observation = validObservation(request: request, authorization: nil, boundary: invalidBoundary)
    let outcome = evaluate(request: request, observation: observation)
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.validationInputStateInconsistent, outcome.reason)
  }

  func testDP1LifecycleHardBlockOutranksEligibleFailure() {
    let lifecycle = SRSVALProvenanceLifecycle(bindings: [binding("LIFECYCLE")], lifecycle: .contested)
    let outcome = evaluate(lifecycle: lifecycle, freshness: missingFreshnessEvidence())
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.provenanceLifecycle, outcome.reason)
    XCTAssertEqual(.hardBlock, outcome.failures.first { $0.rule == .provenanceLifecycle }?.severity)
  }

  func testDP2NotApplicableBlocks() {
    let outcome = evaluate(request: validRequest(applicability: .notApplicable))
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.notApplicable, outcome.reason)
  }

  func testDP2UnscopedRequestBlocksIndeterminate() {
    let request = SRSVALReuseRequest(
      binding: binding("I-15"),
      requestClass: "EXACT_REUSE_REQUEST",
      relationIdentity: "OTHER-RELATION",
      resultIdentity: "RESULT",
      declaredApplicability: .applicable
    )
    let outcome = evaluate(request: request)
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.applicabilityIndeterminate, outcome.reason)
  }

  private func classifiedObservation(
    request: SRSVALReuseRequest,
    authorization: SRSVALRecomputeAuthorization?,
    classification: SRSVALClassification,
    includeRule: Bool = true
  ) -> SRSVALObservation {
    let rule = freshnessPredicateRule()
    return validObservation(
      request: request,
      authorization: authorization,
      predicateRule: includeRule ? rule : nil,
      classifications: [
        SRSVALPredicateClassification(
          predicateRule: rule,
          failureClass: "FRESHNESS_RECHECK_REQUIRED",
          classification: classification
        )
      ]
    )
  }

  func testClassifiedNonRecomputeFailureIsBlockedNonRecompute() {
    let request = validRequest()
    let observation = classifiedObservation(request: request, authorization: nil, classification: .nonRecompute)
    let outcome = evaluate(
      request: request,
      freshness: missingFreshnessEvidence(),
      observation: observation
    )
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.freshnessRecheckRequired, outcome.reason)
    XCTAssertTrue(outcome.i14NotUsedMarkerValid)
  }

  func testSkippedClassificationCannotCreateNoRecomputePath() {
    let outcome = evaluate(request: validRequest(), freshness: missingFreshnessEvidence())
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.predicateRuleBindingUnstableOrMissing, outcome.reason)
    XCTAssertFalse(outcome.i14NotUsedMarkerValid)
  }

  func testSurvivingFailureWithoutMatchingClassificationFailsClosed() {
    let request = validRequest()
    let rule = freshnessPredicateRule()
    let observation = validObservation(
      request: request,
      authorization: nil,
      predicateRule: rule,
      classifications: []
    )
    let outcome = evaluate(
      request: request,
      freshness: missingFreshnessEvidence(),
      observation: observation
    )
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.predicateRuleClassificationRequired, outcome.reason)
    XCTAssertFalse(outcome.i14NotUsedMarkerValid)
  }

  func testMissingPredicateRuleBindingFailsClosed() {
    let request = validRequest()
    let observation = classifiedObservation(request: request, authorization: nil, classification: .recomputeEligible, includeRule: false)
    let outcome = evaluate(
      request: request,
      freshness: missingFreshnessEvidence(),
      observation: observation
    )
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.validationInputStateInconsistent, outcome.reason)
  }

  private func eligibleObservation(
    request: SRSVALReuseRequest,
    authorization: SRSVALRecomputeAuthorization?
  ) -> SRSVALObservation {
    classifiedObservation(request: request, authorization: authorization, classification: .recomputeEligible)
  }

  func testEligibleFailureWithExactRuleAndI14AuthorizesRecompute() {
    let request = validRequest()
    let authorization = validAuthorization()
    let outcome = evaluate(
      request: request,
      authorization: authorization,
      freshness: missingFreshnessEvidence(),
      observation: eligibleObservation(request: request, authorization: authorization)
    )
    XCTAssertEqual(.recompute, outcome.decision)
    XCTAssertEqual(.freshnessRecheckRequired, outcome.reason)
    XCTAssertEqual(authorization.binding, outcome.authorizationUsed)
    XCTAssertFalse(outcome.i14NotUsedMarkerValid)
  }

  func testEligibleFailureWithoutI14FailsClosed() {
    let request = validRequest()
    let outcome = evaluate(
      request: request,
      freshness: missingFreshnessEvidence(),
      observation: eligibleObservation(request: request, authorization: nil)
    )
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.recomputeAuthorizationInvalid, outcome.reason)
  }

  private func authorizationWithCoveredClasses(_ classes: [String]) -> SRSVALRecomputeAuthorization {
    let base = validAuthorization()
    return SRSVALRecomputeAuthorization(
      binding: base.binding,
      sourceRelationIdentity: base.sourceRelationIdentity,
      invalidationClass: base.invalidationClass,
      requestClass: base.requestClass,
      authorizedResultIdentity: base.authorizedResultIdentity,
      semanticClass: base.semanticClass,
      envelope: SRSVALRecomputeEnvelope(
        coveredFailureClasses: classes,
        targetBoundary: binding("I-14-TARGET"),
        relationIdentityRule: binding("RELATION-IDENTITY-RULE")
      )
    )
  }

  func testOverbroadI14FailsClosed() {
    let request = validRequest()
    let authorization = authorizationWithCoveredClasses(["UNRELATED_CLASS"])
    let outcome = evaluate(
      request: request,
      authorization: authorization,
      freshness: missingFreshnessEvidence(),
      observation: eligibleObservation(request: request, authorization: authorization)
    )
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.recomputeAuthorizationInvalid, outcome.reason)
  }

  func testInvalidRecomputeEnvelopeFailsClosed() {
    let request = validRequest()
    let base = validAuthorization()
    let authorization = SRSVALRecomputeAuthorization(
      binding: base.binding,
      sourceRelationIdentity: base.sourceRelationIdentity,
      invalidationClass: base.invalidationClass,
      requestClass: base.requestClass,
      authorizedResultIdentity: base.authorizedResultIdentity,
      semanticClass: base.semanticClass,
      envelope: SRSVALRecomputeEnvelope(
        coveredFailureClasses: base.envelope?.coveredFailureClasses,
        targetBoundary: nil,
        relationIdentityRule: base.envelope?.relationIdentityRule
      )
    )
    let outcome = evaluate(
      request: request,
      authorization: authorization,
      freshness: missingFreshnessEvidence(),
      observation: eligibleObservation(request: request, authorization: authorization)
    )
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.recomputeAuthorizationInvalid, outcome.reason)
  }

  func testCrossBoundaryI15ReferenceIsDP0Blocked() {
    let request = validRequest()
    let valid = validObservation(request: request, authorization: nil)
    let changed = SRSVALObservation(
      boundary: valid.boundary,
      orderingEvidence: valid.orderingEvidence,
      srsEvidence: valid.srsEvidence,
      dependencyEvidence: valid.dependencyEvidence,
      resultEvidence: valid.resultEvidence,
      freshnessPolicyEvidence: valid.freshnessPolicyEvidence,
      lifecycleEvidence: valid.lifecycleEvidence,
      consistencyEvidence: valid.consistencyEvidence,
      closeBoundary: valid.closeBoundary,
      requestReference: binding("OTHER-I-15"),
      i14Reference: valid.i14Reference,
      predicateRuleReferences: valid.predicateRuleReferences,
      predicateClassifications: valid.predicateClassifications
    )
    let outcome = evaluate(request: request, observation: changed)
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.validationInputStateInconsistent, outcome.reason)
  }
}
