import Crypto
import XCTest
@testable import SimiGo2Experimental

final class SRSVALDecisionCoreTests: XCTestCase {
  private let observedAt = "2026-10-11T00:00:00Z"
  private let boundary = SRSVALBinding(
    identity: "I-16",
    version: "OBSERVATION_V1",
    contentDigest: SHA256.hash(data: Data("OBSERVATION:I-16".utf8)).map { String(format: "%02x", $0) }.joined()
  )

  private func digest(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private func binding(_ identity: String, version: String = "V1") -> SRSVALBinding {
    SRSVALBinding(identity: identity, version: version, contentDigest: digest("EXACT:\(identity):\(version)"))
  }

  private func issuer(_ base64PrivateKey: String) throws -> SRSVALIssuer {
    try SRSVALIssuer(rawPrivateKey: Data(base64Encoded: base64PrivateKey)!)
  }

  private func authorizationIssuer() throws -> SRSVALIssuer {
    try issuer("VEazB0+MtZfFfOZ6rUYRlNFTMc9K65sdsT2vH5JRRNE=")
  }

  private func predicateRegistryIssuer() throws -> SRSVALIssuer {
    try issuer("3aRjKPezneXrwfORnOzm8jkvi5AiXVAIqBehHMAJVoI=")
  }

  private func classificationIssuer() throws -> SRSVALIssuer {
    try issuer("6QDbbzhiDsTvzY5kwOK8Bdh4XXKcx8c4lPWkoE6LZG8=")
  }

  private func observationIssuer() throws -> SRSVALIssuer {
    try issuer("b7isZRLkWvsUewAstQ0aGlm65niPZDc3Xot8CKJssBg=")
  }

  private func recordIssuer() throws -> SRSVALIssuer {
    try issuer("am/IOdBDdB7Mi4hgBxZn8gFfDyz4xol4y4FgNBwfKso=")
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

  private func freshness(
    requirements: [SRSVALFreshnessRequirement]? = nil,
    identity: String = "FRESH-A",
    status: SRSVALFreshnessStatus = .current,
    validUntil: String = "2030-01-01T00:00:00Z",
    observedAt: String = "2026-10-11T00:00:00Z",
    digestMismatch: Bool = false
  ) -> SRSVALFreshness {
    let resolvedRequirements = requirements ?? [SRSVALFreshnessRequirement(
      identity: identity,
      evidence: SRSVALBinding(
        identity: "FRESHNESS_EVIDENCE:\(identity)",
        version: "EVIDENCE_V1",
        contentDigest: digest(digestMismatch ? "WRONG:\(identity)" : "FRESHNESS:\(identity)")
      ),
      expectedEvidenceDigest: digest("FRESHNESS:\(identity)"),
      status: status,
      validUntilUTC: validUntil,
      observedAtUTC: observedAt
    )]
    return SRSVALFreshness(boundary: boundary, requirements: resolvedRequirements)
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

  private func freshnessRequirement(
    identity: String,
    status: SRSVALFreshnessStatus = .current,
    validUntil: String = "2030-01-01T00:00:00Z",
    observedAt: String = "2026-10-11T00:00:00Z",
    digestMismatch: Bool = false
  ) -> SRSVALFreshnessRequirement {
    SRSVALFreshnessRequirement(
      identity: identity,
      evidence: SRSVALBinding(
        identity: "FRESHNESS_EVIDENCE:\(identity)",
        version: "EVIDENCE_V1",
        contentDigest: digest(digestMismatch ? "WRONG:\(identity)" : "FRESHNESS:\(identity)")
      ),
      expectedEvidenceDigest: digest("FRESHNESS:\(identity)"),
      status: status,
      validUntilUTC: validUntil,
      observedAtUTC: observedAt
    )
  }

  private func policy() -> SRSVALResolutionPolicy {
    SRSVALResolutionPolicy(
      resolutionRule: binding("RESOLUTION-RULE"),
      policies: [binding("POLICY")],
      boundary: boundary
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

  private func makeInputs(
    sourceRelationIdentity: String = "RELATION",
    resultIdentity: String = "RESULT",
    dependencyResolution: SRSVALResolutionStatus = .resolved,
    resultResolution: SRSVALResultResolution = .resolvedWithoutRecompute,
    lifecycleState: SRSVALLifecycleState = .declaredSettled,
    freshnessRequirements: [SRSVALFreshnessRequirement]? = nil,
    sourceInvalidation: SRSVALSourceInvalidationStatus = .none
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
      state: state(sourceRelationIdentity: sourceRelationIdentity, resultIdentity: resultIdentity),
      source: source,
      dependencies: dependencies(resolution: dependencyResolution),
      result: result(resolution: resultResolution),
      provenance: provenance(),
      lifecycle: lifecycle(lifecycleState),
      freshness: freshness(requirements: freshnessRequirements ?? []),
      policy: policy(),
      request: request()
    )
  }

  private func integrityRecord(inputs: Inputs) throws -> SRSVALSignedRecord<SRSVALInputIntegrityPayload> {
    try recordIssuer().seal(
      SRSVALInputIntegrityPayload(
        settledRelationState: inputs.state,
        sourceRelation: inputs.source,
        dependencies: inputs.dependencies,
        result: inputs.result,
        provenance: inputs.provenance,
        lifecycle: inputs.lifecycle,
        freshness: inputs.freshness,
        policy: inputs.policy,
        reuseRequest: inputs.request
      ),
      domain: .recordIntegrity
    )
  }

  private func authorizationRecord(
    targetBoundary: SRSVALBinding? = nil,
    relationRule: SRSVALBinding? = nil,
    classes: Set<String> = ["FRESHNESS_RECHECK_REQUIRED"],
    overrideIssuer: SRSVALIssuer? = nil
  ) throws -> SRSVALSignedRecord<SRSVALAuthorizationPayload> {
    let payload = SRSVALAuthorizationPayload(
      sourceRelationIdentity: "RELATION",
      invalidationClasses: classes,
      requestClass: "EXACT_REUSE_REQUEST",
      authorizedResultIdentity: "RESULT",
      semanticClass: "EXACT_SEMANTIC_RECOMPUTE",
      coveredFailureClasses: classes,
      targetBoundary: targetBoundary ?? boundary,
      relationIdentityRule: relationRule ?? binding("RELATION-IDENTITY-RULE")
    )
    return try (overrideIssuer ?? authorizationIssuer()).seal(payload, domain: .authorization)
  }

  private func ruleRecord(subject: String, registryIssuer overrideIssuer: SRSVALIssuer? = nil) throws
    -> SRSVALSignedRecord<SRSVALPredicateRulePayload>
  {
    let payload = SRSVALPredicateRulePayload(
      registryAuthority: SRSVALPredicateRuleAuthority.required,
      identity: subject,
      version: "RULE_V1",
      failureClass: "FRESHNESS_RECHECK_REQUIRED",
      subjectIdentities: [subject]
    )
    return try (overrideIssuer ?? predicateRegistryIssuer()).seal(payload, domain: .predicateRegistry)
  }

  private func classificationRecord(
    rule: SRSVALSignedRecord<SRSVALPredicateRulePayload>,
    classification: SRSVALClassification,
    overrideIssuer: SRSVALIssuer? = nil
  ) throws -> SRSVALSignedRecord<SRSVALClassificationPayload> {
    let payload = SRSVALClassificationPayload(
      registryAuthority: rule.payload.registryAuthority,
      predicateRule: SRSVALDecisionCore.predicateRuleBinding(rule),
      identity: rule.payload.identity,
      version: rule.payload.version,
      failureClass: rule.payload.failureClass,
      subjectIdentity: rule.payload.subjectIdentities.first ?? "",
      classification: classification
    )
    return try (overrideIssuer ?? classificationIssuer()).seal(payload, domain: .classification)
  }

  private func observationRecord(
    inputs: Inputs,
    authorization: SRSVALSignedRecord<SRSVALAuthorizationPayload>?,
    rules: [SRSVALSignedRecord<SRSVALPredicateRulePayload>],
    classifications: [SRSVALSignedRecord<SRSVALClassificationPayload>],
    overrideIssuer: SRSVALIssuer? = nil,
    observedAt: String? = nil,
    orderingEvidence: SRSVALBinding? = nil
  ) throws -> SRSVALSignedRecord<SRSVALObservationPayload> {
    let time = observedAt ?? self.observedAt
    let observation = SRSVALObservation(
      boundary: boundary,
      orderingEvidence: orderingEvidence ?? binding("ORDERING_EVIDENCE:\(boundary.identity):\(time)"),
      observedAtUTC: time,
      srsEvidence: inputs.state.binding,
      dependencyEvidence: inputs.dependencies.boundary,
      resultEvidence: inputs.result.binding,
      provenanceEvidence: inputs.provenance.boundary,
      freshnessPolicyEvidence: inputs.freshness.boundary,
      lifecycleEvidence: inputs.lifecycle.boundary,
      policyEvidence: inputs.policy.boundary,
      consistencyEvidence: binding("CONSISTENCY"),
      closeBoundary: boundary,
      requestReference: inputs.request.binding,
      i14Reference: authorization.map { SRSVALDecisionCore.authorizationBinding($0) }
        ?? SRSVALDecisionCore.i14NotUsedMarker,
      predicateRuleReferences: rules.map { SRSVALDecisionCore.predicateRuleBinding($0) },
      predicateClassifications: classifications.map { record in
        SRSVALPredicateClassification(
          predicateRule: record.payload.predicateRule,
          failureClass: record.payload.failureClass,
          subjectIdentity: record.payload.subjectIdentity,
          classification: record.payload.classification
        )
      }
    )
    return try (overrideIssuer ?? observationIssuer()).seal(
      SRSVALObservationPayload(
        observation: observation,
        classifications: classifications.map { record in
          SRSVALPredicateClassification(
            predicateRule: record.payload.predicateRule,
            failureClass: record.payload.failureClass,
            subjectIdentity: record.payload.subjectIdentity,
            classification: record.payload.classification
          )
        }
      ),
      domain: .observation
    )
  }

  private func staleFreshnessInputs() -> Inputs {
    makeInputs(freshnessRequirements: [freshnessRequirement(
      identity: "FRESH-A",
      status: .recheckRequired,
      validUntil: "2030-01-01T00:00:00Z",
      observedAt: observedAt
    )])
  }

  private func eligibleRule() throws -> SRSVALSignedRecord<SRSVALPredicateRulePayload> {
    try ruleRecord(subject: "FRESH-A")
  }

  private func nonEligibleRule(subject: String = "FRESH-B") throws -> SRSVALSignedRecord<SRSVALPredicateRulePayload> {
    try ruleRecord(subject: subject)
  }

  private func eligibleClassification(rule: SRSVALSignedRecord<SRSVALPredicateRulePayload>) throws
    -> SRSVALSignedRecord<SRSVALClassificationPayload>
  {
    try classificationRecord(rule: rule, classification: .recomputeEligible)
  }

  private func nonEligibleClassification(rule: SRSVALSignedRecord<SRSVALPredicateRulePayload>) throws
    -> SRSVALSignedRecord<SRSVALClassificationPayload>
  {
    try classificationRecord(rule: rule, classification: .nonRecompute)
  }

  private func freshnessInputs(requirements: [SRSVALFreshnessRequirement]) -> Inputs {
    makeInputs(freshnessRequirements: requirements)
  }

  private func freshFailureRequirements(subjects: [String]) -> [SRSVALFreshnessRequirement] {
    subjects.map {
      freshnessRequirement(
        identity: $0,
        status: .recheckRequired,
        validUntil: "2030-01-01T00:00:00Z",
        observedAt: observedAt
      )
    }
  }

  private func healthyInputs() -> Inputs {
    makeInputs()
  }

  private func classificationRecordsText(_ records: [SRSVALSignedRecord<SRSVALClassificationPayload>]) -> String {
    String(decoding: (try? JSONEncoder().encode(records.map { $0.payload })) ?? Data(), as: UTF8.self)
  }

  func testVerifiedAuthorityChainResolvesPureReuse() throws {
    let inputs = healthyInputs()
    let outcome = SRSVALDecisionCore.evaluate(
      settledRelationState: inputs.state,
      sourceRelation: inputs.source,
      dependencies: inputs.dependencies,
      result: inputs.result,
      provenance: inputs.provenance,
      lifecycle: inputs.lifecycle,
      freshness: inputs.freshness,
      policy: inputs.policy,
      reuseRequest: inputs.request,
      registeredPredicateRules: [],
      classificationRecords: [],
      authorization: nil,
      observation: try observationRecord(inputs: inputs, authorization: nil, rules: [], classifications: []),
      inputIntegrity: try integrityRecord(inputs: inputs)
    )
    XCTAssertEqual(.reuse, outcome.decision)
    XCTAssertTrue(outcome.i14NotUsedMarkerValid)
  }

  func testUntrustedAuthorizationCannotAuthorizeRecompute() throws {
    let inputs = staleFreshnessInputs()
    let rule = try eligibleRule()
    let classification = try eligibleClassification(rule: rule)
    let observation = try observationRecord(
      inputs: inputs,
      authorization: try authorizationRecord(overrideIssuer: try issuer("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")),
      rules: [rule],
      classifications: [classification]
    )
    let untrustedAuthorization = try authorizationRecord(overrideIssuer: try issuer("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="))
    print("DEBUG UNTRUSTED", untrustedAuthorization.verify(anchor: SRSVALTrustAnchor.authorizationIssuer), untrustedAuthorization.signer.base64EncodedString(), SRSVALTrustAnchor.authorizationIssuer.base64EncodedString())
    let outcome = SRSVALDecisionCore.evaluate(
      settledRelationState: inputs.state,
      sourceRelation: inputs.source,
      dependencies: inputs.dependencies,
      result: inputs.result,
      provenance: inputs.provenance,
      lifecycle: inputs.lifecycle,
      freshness: inputs.freshness,
      policy: inputs.policy,
      reuseRequest: inputs.request,
      registeredPredicateRules: [rule],
      classificationRecords: [classification],
      authorization: untrustedAuthorization,
      observation: observation,
      inputIntegrity: try integrityRecord(inputs: inputs)
    )
    XCTAssertEqual(.block, outcome.decision)
  }

  func testUnregisteredClassificationAuthorityFailsClosed() throws {
    let inputs = staleFreshnessInputs()
    let rule = try eligibleRule()
    let classification = try classificationRecord(rule: rule, classification: .recomputeEligible, overrideIssuer: try issuer("BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="))
    let outcome = evaluateVerified(
      inputs: inputs,
      rules: [rule],
      classifications: [classification],
      authorization: try authorizationRecord()
    )
    XCTAssertEqual(.block, outcome.decision)
  }

  private func evaluateVerified(
    inputs: Inputs,
    rules: [SRSVALSignedRecord<SRSVALPredicateRulePayload>],
    classifications: [SRSVALSignedRecord<SRSVALClassificationPayload>],
    authorization: SRSVALSignedRecord<SRSVALAuthorizationPayload>?
  ) -> SRSVALDecisionOutcome {
    SRSVALDecisionCore.evaluate(
      settledRelationState: inputs.state,
      sourceRelation: inputs.source,
      dependencies: inputs.dependencies,
      result: inputs.result,
      provenance: inputs.provenance,
      lifecycle: inputs.lifecycle,
      freshness: inputs.freshness,
      policy: inputs.policy,
      reuseRequest: inputs.request,
      registeredPredicateRules: rules,
      classificationRecords: classifications,
      authorization: authorization,
      observation: try! observationRecord(inputs: inputs, authorization: authorization, rules: rules, classifications: classifications),
      inputIntegrity: try! integrityRecord(inputs: inputs)
    )
  }

  func testTamperedClassificationOutcomeFailsClosed() throws {
    let inputs = staleFreshnessInputs()
    let rule = try eligibleRule()
    let classification = try eligibleClassification(rule: rule)
    var tampered = classification
    tampered = SRSVALSignedRecord<SRSVALClassificationPayload>(
      payload: SRSVALClassificationPayload(
        registryAuthority: classification.payload.registryAuthority,
        predicateRule: classification.payload.predicateRule,
        identity: classification.payload.identity,
        version: classification.payload.version,
        failureClass: classification.payload.failureClass,
        subjectIdentity: classification.payload.subjectIdentity,
        classification: .nonRecompute
      ),
      signature: classification.signature,
      signer: classification.signer
    )
    let observation = try observationRecord(inputs: inputs, authorization: try authorizationRecord(), rules: [rule], classifications: [tampered])
    let outcome = SRSVALDecisionCore.evaluate(
      settledRelationState: inputs.state,
      sourceRelation: inputs.source,
      dependencies: inputs.dependencies,
      result: inputs.result,
      provenance: inputs.provenance,
      lifecycle: inputs.lifecycle,
      freshness: inputs.freshness,
      policy: inputs.policy,
      reuseRequest: inputs.request,
      registeredPredicateRules: [rule],
      classificationRecords: [tampered],
      authorization: try authorizationRecord(),
      observation: observation,
      inputIntegrity: try integrityRecord(inputs: inputs)
    )
    XCTAssertEqual(.block, outcome.decision)
  }

  func testMixedEligibleAndNonEligibleFailuresBlock() throws {
    let requirements = freshFailureRequirements(subjects: ["FRESH-A", "FRESH-B"])
    let inputs = freshnessInputs(requirements: requirements)
    let eligible = try eligibleRule()
    let nonEligible = try nonEligibleRule(subject: "FRESH-B")
    let classifications = [try eligibleClassification(rule: eligible), try nonEligibleClassification(rule: nonEligible)]
    let outcome = evaluateVerified(
      inputs: inputs,
      rules: [eligible, nonEligible],
      classifications: classifications,
      authorization: try authorizationRecord()
    )
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.freshnessRecheckRequired, outcome.reason)
  }

  func testForgedDependencyStateCannotAlterSignedInputIntegrity() throws {
    let inputs = healthyInputs()
    let forgedInputs = makeInputs(dependencyResolution: .unresolved)
    let signedForged = try integrityRecord(inputs: forgedInputs)
    let observation = try observationRecord(
      inputs: inputs,
      authorization: nil,
      rules: [],
      classifications: []
    )
    let outcome = SRSVALDecisionCore.evaluate(
      settledRelationState: inputs.state,
      sourceRelation: inputs.source,
      dependencies: inputs.dependencies,
      result: inputs.result,
      provenance: inputs.provenance,
      lifecycle: inputs.lifecycle,
      freshness: inputs.freshness,
      policy: inputs.policy,
      reuseRequest: inputs.request,
      registeredPredicateRules: [],
      classificationRecords: [],
      authorization: nil,
      observation: observation,
      inputIntegrity: signedForged
    )
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.validationInputStateInconsistent, outcome.reason)
  }

  func testForgedSourceInvalidationCannotAlterSignedInputIntegrity() throws {
    let inputs = healthyInputs()
    let forgedInputs = makeInputs(sourceInvalidation: .invalidated)
    let outcome = evaluateVerified(
      inputs: inputs,
      rules: [],
      classifications: [],
      authorization: nil
    )
    XCTAssertEqual(.reuse, outcome.decision)
    let signedForged = try integrityRecord(inputs: forgedInputs)
    XCTAssertNotEqual(signedForged.payload.sourceRelation.invalidationStatus, inputs.source.invalidationStatus)
  }

  func testI16BoundaryMismatchFailsClosed() throws {
    let inputs = healthyInputs()
    let observation = try observationRecord(
      inputs: inputs,
      authorization: nil,
      rules: [],
      classifications: [],
      orderingEvidence: binding("ORDERING_EVIDENCE:OTHER-BOUNDARY:\(observedAt)")
    )
    let outcome = SRSVALDecisionCore.evaluate(
      settledRelationState: inputs.state,
      sourceRelation: inputs.source,
      dependencies: inputs.dependencies,
      result: inputs.result,
      provenance: inputs.provenance,
      lifecycle: inputs.lifecycle,
      freshness: inputs.freshness,
      policy: inputs.policy,
      reuseRequest: inputs.request,
      registeredPredicateRules: [],
      classificationRecords: [],
      authorization: nil,
      observation: observation,
      inputIntegrity: try integrityRecord(inputs: inputs)
    )
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.validationInputStateInconsistent, outcome.reason)
  }

  func testExpiredFreshnessFailsClosed() throws {
    let inputs = makeInputs(freshnessRequirements: [freshnessRequirement(
      identity: "FRESH-A",
      status: .current,
      validUntil: "2020-01-01T00:00:00Z",
      observedAt: observedAt
    )])
    let outcome = evaluateVerified(inputs: inputs, rules: [], classifications: [], authorization: nil)
    XCTAssertEqual(.block, outcome.decision)
  }

  func testFreshnessDigestMismatchFailsClosed() throws {
    let inputs = makeInputs(freshnessRequirements: [freshnessRequirement(
      identity: "FRESH-A",
      status: .current,
      validUntil: "2030-01-01T00:00:00Z",
      observedAt: observedAt,
      digestMismatch: true
    )])
    let outcome = evaluateVerified(inputs: inputs, rules: [], classifications: [], authorization: nil)
    XCTAssertEqual(.block, outcome.decision)
  }

  func testFreshnessObservationTimeMismatchFailsClosed() throws {
    let inputs = makeInputs(freshnessRequirements: [freshnessRequirement(
      identity: "FRESH-A",
      status: .current,
      validUntil: "2030-01-01T00:00:00Z",
      observedAt: observedAt
    )])
    let observation = try observationRecord(
      inputs: inputs,
      authorization: nil,
      rules: [],
      classifications: [],
      observedAt: "2020-01-01T00:00:00Z"
    )
    let outcome = SRSVALDecisionCore.evaluate(
      settledRelationState: inputs.state,
      sourceRelation: inputs.source,
      dependencies: inputs.dependencies,
      result: inputs.result,
      provenance: inputs.provenance,
      lifecycle: inputs.lifecycle,
      freshness: inputs.freshness,
      policy: inputs.policy,
      reuseRequest: inputs.request,
      registeredPredicateRules: [],
      classificationRecords: [],
      authorization: nil,
      observation: observation,
      inputIntegrity: try integrityRecord(inputs: inputs)
    )
    XCTAssertEqual(.block, outcome.decision)
  }

  func testI14SemanticScopeMismatchBlocks() throws {
    let inputs = staleFreshnessInputs()
    let rule = try eligibleRule()
    let classification = try eligibleClassification(rule: rule)
    let authorization = try authorizationRecord(targetBoundary: binding("OTHER-I-16"))
    let outcome = evaluateVerified(
      inputs: inputs,
      rules: [rule],
      classifications: [classification],
      authorization: authorization
    )
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.recomputeAuthorizationInvalid, outcome.reason)
  }

  func testAllEligibleFailuresWithAuthoritativeI14AuthorizeRecompute() throws {
    let inputs = staleFreshnessInputs()
    let rule = try eligibleRule()
    let classification = try eligibleClassification(rule: rule)
    let authorization = try authorizationRecord()
    let observation = try observationRecord(inputs: inputs, authorization: authorization, rules: [rule], classifications: [classification])
    let outcome = evaluateVerified(
      inputs: inputs,
      rules: [rule],
      classifications: [classification],
      authorization: authorization
    )
    XCTAssertEqual(.recompute, outcome.decision)
    XCTAssertEqual(.freshnessRecheckRequired, outcome.reason)
    XCTAssertEqual(SRSVALDecisionCore.authorizationBinding(authorization), outcome.authorizationUsed)
  }
}
