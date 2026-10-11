import Crypto
import XCTest
@testable import SimiGo2Experimental

final class SRSVALDecisionCoreTests: XCTestCase {
  private let observedAt = "2026-10-11T00:00:00Z"
  private var testIssuerPrivateKeys: SRSVALTrustAnchors {
    SRSVALTrustAnchors(
      authorizationIssuer: Data(SHA256.hash(data: Data("TEST-ONLY PRIVATE KEYauthorization".utf8))),
      predicateRegistryIssuer: Data(SHA256.hash(data: Data("TEST-ONLY PRIVATE KEYpredicateRegistry".utf8))),
      classificationIssuer: Data(SHA256.hash(data: Data("TEST-ONLY PRIVATE KEYclassification".utf8))),
      observationIssuer: Data(SHA256.hash(data: Data("TEST-ONLY PRIVATE KEYobservation".utf8))),
      recordIntegrityIssuer: Data(SHA256.hash(data: Data("TEST-ONLY PRIVATE KEYrecordIntegrity".utf8)))
    )
  }

  private var testAnchors: SRSVALTrustAnchors {
    SRSVALTrustAnchors(
      authorizationIssuer: (try? testIssuer(.authorization, privateKeys: testIssuerPrivateKeys))?.publicKey ?? Data(),
      predicateRegistryIssuer: (try? testIssuer(.predicateRegistry, privateKeys: testIssuerPrivateKeys))?.publicKey ?? Data(),
      classificationIssuer: (try? testIssuer(.classification, privateKeys: testIssuerPrivateKeys))?.publicKey ?? Data(),
      observationIssuer: (try? testIssuer(.observation, privateKeys: testIssuerPrivateKeys))?.publicKey ?? Data(),
      recordIntegrityIssuer: (try? testIssuer(.recordIntegrity, privateKeys: testIssuerPrivateKeys))?.publicKey ?? Data()
    )
  }

  private func testIssuer(_ domain: SRSVALTrustDomain, privateKeys: SRSVALTrustAnchors) throws -> SRSVALIssuer {
    let raw = privateKeys.domain(domain)
    return try SRSVALIssuer(rawPrivateKey: raw)
  }

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

  private func sourceRelation(invalidation: SRSVALSourceInvalidationStatus = .none) -> SRSVALSourceRelation {
    SRSVALSourceRelation(
      binding: binding("RELATION"),
      semanticBinding: binding("RELATION-SEMANTICS"),
      applicabilityCoverage: binding("RELATION-COVERAGE"),
      invalidationRecord: binding("RELATION-INVALIDATION"),
      invalidationStatus: invalidation,
      identityRule: binding("RELATION-IDENTITY-RULE"),
      status: .current
    )
  }

  private func state() -> SRSVALSettledRelationState {
    SRSVALSettledRelationState(
      binding: binding("SRS"),
      settlementID: "SETTLEMENT",
      status: "DECLARED_SETTLED",
      sourceRelationIdentity: "RELATION",
      resultIdentity: "RESULT",
      requiresCanonicalIdentityRule: true,
      canonicalIdentityRule: binding("RELATION-IDENTITY-RULE"),
      provenanceBindings: [binding("SRS-PROVENANCE")]
    )
  }

  private func dependencies() -> SRSVALDependencySet {
    SRSVALDependencySet(
      boundary: boundary,
      dependencies: [SRSVALDependency(
        binding: binding("DEPENDENCY"),
        role: "REQUIRED_INPUT",
        necessity: "REQUIRED",
        resolution: .resolved,
        status: .current
      )]
    )
  }

  private func result() -> SRSVALResult {
    SRSVALResult(
      binding: binding("RESULT"),
      resolution: .resolvedWithoutRecompute,
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
    subject: String = "FRESH-A",
    status: SRSVALFreshnessStatus = .current,
    validUntil: String = "2030-01-01T00:00:00Z",
    observedAt: String = "2026-10-11T00:00:00Z",
    digestMismatch: Bool = false
  ) -> SRSVALFreshnessRequirement {
    SRSVALFreshnessRequirement(
      identity: subject,
      evidence: SRSVALBinding(
        identity: "FRESHNESS_EVIDENCE:\(subject)",
        version: "EVIDENCE_V1",
        contentDigest: digest(digestMismatch ? "WRONG:\(subject)" : "FRESHNESS:\(subject)")
      ),
      expectedEvidenceDigest: digest("FRESHNESS:\(subject)"),
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

  private func makeHealthyInputs(requestApplicability: SRSVALRequestApplicability = .applicable) -> Inputs {
    let request = SRSVALReuseRequest(
      binding: binding("I-15"),
      requestClass: "EXACT_REUSE_REQUEST",
      relationIdentity: "RELATION",
      resultIdentity: "RESULT",
      declaredApplicability: requestApplicability
    )
    return Inputs(
      state: state(), source: sourceRelation(), dependencies: dependencies(), result: result(),
      provenance: provenance(), lifecycle: lifecycle(), freshness: SRSVALFreshness(boundary: boundary, requirements: [freshnessRequirement()]), policy: policy(), request: request
    )
  }

  private func makeStaleEligibleInputs(lifecycleState: SRSVALLifecycleState = .declaredSettled) -> Inputs {
    let freshnessRequirements = [freshnessRequirement(
      subject: "FRESH-A",
      status: .recheckRequired,
      validUntil: "2030-01-01T00:00:00Z",
      observedAt: observedAt
    )]
    return Inputs(
      state: state(), source: sourceRelation(), dependencies: dependencies(), result: result(),
      provenance: provenance(), lifecycle: lifecycle(lifecycleState),
      freshness: SRSVALFreshness(boundary: boundary, requirements: freshnessRequirements),
      policy: policy(), request: request()
    )
  }

  private func fixtureFor(
    inputs: Inputs,
    rules: [SRSVALPredicateRulePayload],
    classifications: [SRSVALClassificationPayload],
    authorization: SRSVALAuthorizationPayload?
  ) throws -> (
    [SRSVALSignedRecord<SRSVALPredicateRulePayload>],
    [SRSVALSignedRecord<SRSVALClassificationPayload>],
    SRSVALSignedRecord<SRSVALAuthorizationPayload>?,
    SRSVALSignedRecord<SRSVALObservationPayload>,
    SRSVALSignedRecord<SRSVALInputIntegrityPayload>
  ) {
    let authBinding = authorization.map { SRSVALDecisionCore.authorizationBindingForPayload($0) }
    return (
      try rules.map { try signedRule(payload: $0) },
      try classifications.map { try signedClassification(payload: $0) },
      try authorization.map { try signedAuthorization(payload: $0) },
      try signedObservation(payload: observationPayload(inputs: inputs, authorizationBinding: authBinding, rules: rules, classifications: classifications)),
      try signedIntegrity(payload: SRSVALInputIntegrityPayload(settledRelationState: inputs.state, sourceRelation: inputs.source, dependencies: inputs.dependencies, result: inputs.result, provenance: inputs.provenance, lifecycle: inputs.lifecycle, freshness: inputs.freshness, policy: inputs.policy, reuseRequest: inputs.request))
    )
  }

  private func evaluateFixture(
    inputs: Inputs,
    rules: [SRSVALPredicateRulePayload] = [],
    classifications: [SRSVALClassificationPayload] = [],
    authorization: SRSVALAuthorizationPayload? = nil,
    request: SRSVALReuseRequest? = nil
  ) throws -> SRSVALDecisionOutcome {
    let actualInputs = request == nil ? inputs : Inputs(
      state: inputs.state, source: inputs.source, dependencies: inputs.dependencies,
      result: inputs.result, provenance: inputs.provenance, lifecycle: inputs.lifecycle,
      freshness: inputs.freshness, policy: inputs.policy, request: request!
    )
    let (rulesSigned, classificationsSigned, authorizationSigned, observation, integrity) = try fixtureFor(
      inputs: actualInputs, rules: rules, classifications: classifications, authorization: authorization
    )
    return SRSVALDecisionCore.evaluate(
      settledRelationState: actualInputs.state,
      sourceRelation: actualInputs.source,
      dependencies: actualInputs.dependencies,
      result: actualInputs.result,
      provenance: actualInputs.provenance,
      lifecycle: actualInputs.lifecycle,
      freshness: actualInputs.freshness,
      policy: actualInputs.policy,
      reuseRequest: actualInputs.request,
      registeredPredicateRules: rulesSigned,
      classificationRecords: classificationsSigned,
      authorization: authorizationSigned,
      observation: observation,
      inputIntegrity: integrity,
      anchors: testAnchors
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

  private func healthyInputs() -> Inputs {
    Inputs(
      state: state(), source: sourceRelation(), dependencies: dependencies(), result: result(),
      provenance: provenance(), lifecycle: lifecycle(), freshness: SRSVALFreshness(boundary: boundary, requirements: [freshnessRequirement()]), policy: policy(), request: request()
    )
  }

  private func staleInputs(subjects: [String] = ["FRESH-A"]) -> Inputs {
    let requirements = subjects.map {
      freshnessRequirement(subject: $0, status: .recheckRequired, validUntil: "2030-01-01T00:00:00Z", observedAt: observedAt)
    }
    return Inputs(
      state: state(), source: sourceRelation(), dependencies: dependencies(), result: result(),
      provenance: provenance(), lifecycle: lifecycle(), freshness: SRSVALFreshness(boundary: boundary, requirements: requirements),
      policy: policy(), request: request()
    )
  }

  private func predicateRulePayload(subject: String) -> SRSVALPredicateRulePayload {
    SRSVALPredicateRulePayload(
      registryAuthority: SRSVALPredicateRuleAuthority.required,
      identity: subject,
      version: "RULE_V1",
      failureClass: "FRESHNESS_RECHECK_REQUIRED",
      subjectIdentities: [subject]
    )
  }

  private func classificationPayload(rule: SRSVALPredicateRulePayload, classification: SRSVALClassification) -> SRSVALClassificationPayload {
    SRSVALClassificationPayload(
      registryAuthority: SRSVALPredicateRuleAuthority.required,
      predicateRule: SRSVALDecisionCore.predicateRuleBindingForPayload(rule),
      identity: rule.identity,
      version: rule.version,
      failureClass: rule.failureClass,
      subjectIdentity: rule.subjectIdentities.first ?? "",
      classification: classification
    )
  }

  private func authorizationPayload(classes: Set<String>, targetBoundary: SRSVALBinding? = nil, relationRule: SRSVALBinding? = nil) -> SRSVALAuthorizationPayload {
    SRSVALAuthorizationPayload(
      sourceRelationIdentity: "RELATION",
      invalidationClasses: Set(classes),
      requestClass: "EXACT_REUSE_REQUEST",
      authorizedResultIdentity: "RESULT",
      semanticClass: "EXACT_SEMANTIC_RECOMPUTE",
      coveredFailureClasses: Set(classes),
      targetBoundary: targetBoundary ?? boundary,
      relationIdentityRule: relationRule ?? binding("RELATION-IDENTITY-RULE")
    )
  }

  private func observationPayload(
    inputs: Inputs,
    authorizationBinding: SRSVALBinding?,
    rules: [SRSVALPredicateRulePayload],
    classifications: [SRSVALClassificationPayload]
  ) -> SRSVALObservationPayload {
    let observation = SRSVALObservation(
      boundary: boundary,
      orderingEvidence: binding("ORDERING_EVIDENCE:\(boundary.identity):\(observedAt)"),
      observedAtUTC: observedAt,
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
      i14Reference: authorizationBinding ?? SRSVALDecisionCore.i14NotUsedMarker,
      predicateRuleReferences: rules.map { SRSVALDecisionCore.predicateRuleBindingForPayload($0) },
      predicateClassifications: zip(rules, classifications).map { rule, payload in
        SRSVALPredicateClassification(
          predicateRule: SRSVALDecisionCore.predicateRuleBindingForPayload(rule),
          failureClass: payload.failureClass,
          subjectIdentity: payload.subjectIdentity,
          classification: payload.classification
        )
      }
    )
    return SRSVALObservationPayload(
      observation: observation,
      classifications: classifications.map { payload in
        SRSVALPredicateClassification(
        predicateRule: payload.predicateRule,
        failureClass: payload.failureClass,
        subjectIdentity: payload.subjectIdentity,
        classification: payload.classification
      )
    }
    )
  }

  private func signedObservation(payload: SRSVALObservationPayload) throws -> SRSVALSignedRecord<SRSVALObservationPayload> {
    try testIssuer(.observation, privateKeys: testIssuerPrivateKeys).seal(payload, domain: .observation)
  }

  private func signedIntegrity(payload: SRSVALInputIntegrityPayload) throws -> SRSVALSignedRecord<SRSVALInputIntegrityPayload> {
    try testIssuer(.recordIntegrity, privateKeys: testIssuerPrivateKeys).seal(payload, domain: .recordIntegrity)
  }

  private func signedRule(payload: SRSVALPredicateRulePayload) throws -> SRSVALSignedRecord<SRSVALPredicateRulePayload> {
    try testIssuer(.predicateRegistry, privateKeys: testIssuerPrivateKeys).seal(payload, domain: .predicateRegistry)
  }

  private func signedClassification(payload: SRSVALClassificationPayload) throws -> SRSVALSignedRecord<SRSVALClassificationPayload> {
    try testIssuer(.classification, privateKeys: testIssuerPrivateKeys).seal(payload, domain: .classification)
  }

  private func signedAuthorization(payload: SRSVALAuthorizationPayload) throws -> SRSVALSignedRecord<SRSVALAuthorizationPayload> {
    try testIssuer(.authorization, privateKeys: testIssuerPrivateKeys).seal(payload, domain: .authorization)
  }

  func testDP1LifecycleHardBlockOutranksEligibleFailure() throws {
    let inputs = makeStaleEligibleInputs(lifecycleState: .contested)
    let rulePayload = predicateRulePayload(subject: "FRESH-A")
    let classificationPayload = classificationPayload(rule: rulePayload, classification: .recomputeEligible)
    let authPayload = authorizationPayload(classes: ["FRESHNESS_RECHECK_REQUIRED"])
    let outcome = try evaluateFixture(
      inputs: inputs,
      rules: [rulePayload],
      classifications: [classificationPayload],
      authorization: authPayload
    )
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.provenanceLifecycle, outcome.reason)
  }

  func testDP2NotApplicableBlocks() throws {
    let inputs = makeHealthyInputs(requestApplicability: .notApplicable)
    let outcome = try evaluateFixture(inputs: inputs)
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.notApplicable, outcome.reason)
  }

  func testDP2UnscopedRequestBlocksIndeterminate() throws {
    let inputs = makeHealthyInputs()
    let request = SRSVALReuseRequest(
      binding: binding("I-15"),
      requestClass: "EXACT_REUSE_REQUEST",
      relationIdentity: "OTHER-RELATION",
      resultIdentity: "RESULT",
      declaredApplicability: .applicable
    )
    let outcome = try evaluateFixture(inputs: inputs, request: request)
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.applicabilityIndeterminate, outcome.reason)
  }

  func testGClassMissingClassificationFailsClosed() throws {
    let inputs = makeStaleEligibleInputs()
    let rulePayload = predicateRulePayload(subject: "FRESH-A")
    let authPayload = authorizationPayload(classes: ["FRESHNESS_RECHECK_REQUIRED"])
    let outcome = try evaluateFixture(
      inputs: inputs,
      rules: [rulePayload],
      classifications: [],
      authorization: authPayload
    )
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.predicateRuleClassificationRequired, outcome.reason)
  }

  func testContradictoryClassificationsFailClosedWithoutOrderDependence() throws {
    let inputs = makeStaleEligibleInputs()
    let rulePayload = predicateRulePayload(subject: "FRESH-A")
    let eligible = classificationPayload(rule: rulePayload, classification: .recomputeEligible)
    let nonEligible = classificationPayload(rule: rulePayload, classification: .nonRecompute)
    let authPayload = authorizationPayload(classes: ["FRESHNESS_RECHECK_REQUIRED"])
    let forward = try evaluateFixture(
      inputs: inputs,
      rules: [rulePayload],
      classifications: [eligible, nonEligible],
      authorization: authPayload
    )
    let reverse = try evaluateFixture(
      inputs: inputs,
      rules: [rulePayload],
      classifications: [nonEligible, eligible],
      authorization: authPayload
    )
    XCTAssertEqual(.block, forward.decision)
    XCTAssertEqual(.block, reverse.decision)
    XCTAssertEqual(forward.reason, reverse.reason)
  }

  func testExpectedDomainSeparationFailsClosedForAllTrustDomains() throws {
    let inputs = makeHealthyInputs()
    let authPayload = authorizationPayload(classes: ["FRESHNESS_RECHECK_REQUIRED"])
    let rule = predicateRulePayload(subject: "FRESH-A")
    let classification = classificationPayload(rule: rule, classification: .recomputeEligible)
    let observation = observationPayload(inputs: inputs, authorizationBinding: nil, rules: [], classifications: [])
    let integrity = SRSVALInputIntegrityPayload(
      settledRelationState: inputs.state,
      sourceRelation: inputs.source,
      dependencies: inputs.dependencies,
      result: inputs.result,
      provenance: inputs.provenance,
      lifecycle: inputs.lifecycle,
      freshness: inputs.freshness,
      policy: inputs.policy,
      reuseRequest: inputs.request
    )
    let wrongAuth = try testIssuer(.authorization, privateKeys: testIssuerPrivateKeys)
      .seal(authPayload, domain: .observation)
    XCTAssertFalse(wrongAuth.verify(
      anchor: testAnchors.authorizationIssuer,
      expectedDomain: .authorization
    ))

    let wrongRule = try testIssuer(.predicateRegistry, privateKeys: testIssuerPrivateKeys)
      .seal(rule, domain: .classification)
    XCTAssertFalse(wrongRule.verify(
      anchor: testAnchors.predicateRegistryIssuer,
      expectedDomain: .predicateRegistry
    ))

    let wrongClassification = try testIssuer(.classification, privateKeys: testIssuerPrivateKeys)
      .seal(classification, domain: .predicateRegistry)
    XCTAssertFalse(wrongClassification.verify(
      anchor: testAnchors.classificationIssuer,
      expectedDomain: .classification
    ))

    let wrongObservation = try testIssuer(.observation, privateKeys: testIssuerPrivateKeys)
      .seal(observation, domain: .recordIntegrity)
    XCTAssertFalse(wrongObservation.verify(
      anchor: testAnchors.observationIssuer,
      expectedDomain: .observation
    ))

    let wrongIntegrity = try testIssuer(.recordIntegrity, privateKeys: testIssuerPrivateKeys)
      .seal(integrity, domain: .authorization)
    XCTAssertFalse(wrongIntegrity.verify(
      anchor: testAnchors.recordIntegrityIssuer,
      expectedDomain: .recordIntegrity
    ))
  }

  func testCanonicalSerializationIsStableAcrossCodableRoundTrip() throws {
    let inputs = makeHealthyInputs()
    let payload = observationPayload(inputs: inputs, authorizationBinding: nil, rules: [], classifications: [])
    let data = payload.canonicalData
    let encoded = try JSONEncoder().encode(payload)
    let decoded = try JSONDecoder().decode(SRSVALObservationPayload.self, from: encoded)
    XCTAssertEqual(decoded.canonicalData, data)
    XCTAssertEqual(decoded, payload)
  }

  func testCanonicalBytesCoverDecisionFieldsWithoutAmbiguity() throws {
    let evidence = binding("FRESHNESS_EVIDENCE:FRESH-A", version: "EVIDENCE_V1")
    let digestBase = SRSVALFreshness(
      boundary: boundary,
      requirements: [SRSVALFreshnessRequirement(
        identity: "FRESH-A",
        evidence: evidence,
        expectedEvidenceDigest: digest("FRESHNESS:FRESH-A"),
        status: .current,
        validUntilUTC: "2030-01-01T00:00:00Z",
        observedAtUTC: observedAt
      )]
    )
    let digestChanged = SRSVALFreshness(
      boundary: boundary,
      requirements: [SRSVALFreshnessRequirement(
        identity: "FRESH-A",
        evidence: evidence,
        expectedEvidenceDigest: digest("CHANGED:FRESH-A"),
        status: .current,
        validUntilUTC: "2030-01-01T00:00:00Z",
        observedAtUTC: observedAt
      )]
    )
    XCTAssertNotEqual(digestBase.canonicalData, digestChanged.canonicalData)

    let state = state()
    let stateChanged = SRSVALSettledRelationState(
      binding: state.binding,
      settlementID: state.settlementID,
      status: state.status,
      sourceRelationIdentity: state.sourceRelationIdentity,
      resultIdentity: state.resultIdentity,
      requiresCanonicalIdentityRule: state.requiresCanonicalIdentityRule,
      canonicalIdentityRule: state.canonicalIdentityRule,
      provenanceBindings: [binding("SRS-PROVENANCE", version: "PROVENANCE_V2")]
    )
    XCTAssertNotEqual(state.canonicalData, stateChanged.canonicalData)

    let policy = SRSVALResolutionPolicy(
      resolutionRule: binding("RESOLUTION-RULE"),
      policies: [binding("POLICY")],
      boundary: boundary
    )
    let policyChanged = SRSVALResolutionPolicy(
      resolutionRule: policy.resolutionRule,
      policies: [binding("POLICY", version: "POLICY_V2")],
      boundary: policy.boundary
    )
    XCTAssertNotEqual(policy.canonicalData, policyChanged.canonicalData)

    let lifecycle = lifecycle()
    let lifecycleChanged = SRSVALProvenanceLifecycle(
      bindings: [binding("LIFECYCLE", version: "LIFECYCLE_V2")],
      lifecycle: lifecycle.lifecycle,
      boundary: lifecycle.boundary
    )
    XCTAssertNotEqual(lifecycle.canonicalData, lifecycleChanged.canonicalData)

    let rule = predicateRulePayload(subject: "FRESH-A")
    let changedRule = SRSVALPredicateRulePayload(
      registryAuthority: rule.registryAuthority,
      identity: rule.identity,
      version: rule.version,
      failureClass: "CHANGED",
      subjectIdentities: Set(rule.subjectIdentities)
    )
    let rulesBase = observationPayload(inputs: makeHealthyInputs(), authorizationBinding: nil, rules: [rule], classifications: [classificationPayload(rule: rule, classification: .recomputeEligible)])
    let rulesChanged = observationPayload(inputs: makeHealthyInputs(), authorizationBinding: nil, rules: [changedRule], classifications: [classificationPayload(rule: changedRule, classification: .recomputeEligible)])
    XCTAssertNotEqual(rulesBase.canonicalData, rulesChanged.canonicalData)

    let separateSubjects = SRSVALPredicateRulePayload(
      registryAuthority: rule.registryAuthority,
      identity: rule.identity,
      version: rule.version,
      failureClass: rule.failureClass,
      subjectIdentities: ["A", "B"]
    )
    let joinedSubjects = SRSVALPredicateRulePayload(
      registryAuthority: rule.registryAuthority,
      identity: rule.identity,
      version: rule.version,
      failureClass: rule.failureClass,
      subjectIdentities: ["A\u{1F}B"]
    )
    XCTAssertNotEqual(separateSubjects.canonicalData, joinedSubjects.canonicalData)
  }

  func testOrderedRecordsPreserveFieldRolesInSignatures() throws {
    let originalBinding = SRSVALBinding(
      identity: "RULE-X",
      version: "V1",
      contentDigest: digest("BINDING:RULE-X:V1")
    )
    let swappedBinding = SRSVALBinding(
      identity: originalBinding.version,
      version: originalBinding.identity,
      contentDigest: originalBinding.contentDigest
    )
    XCTAssertNotEqual(originalBinding.canonicalData, swappedBinding.canonicalData)
    let bindingSignature = try testIssuer(.predicateRegistry, privateKeys: testIssuerPrivateKeys)
      .seal(originalBinding, domain: .predicateRegistry)
    let swappedBindingRecord = SRSVALSignedRecord<SRSVALBinding>(
      domain: .predicateRegistry,
      payload: swappedBinding,
      signature: bindingSignature.signature,
      signer: bindingSignature.signer
    )
    XCTAssertTrue(bindingSignature.verify(
      anchor: testAnchors.predicateRegistryIssuer,
      expectedDomain: .predicateRegistry
    ))
    XCTAssertFalse(swappedBindingRecord.verify(
      anchor: testAnchors.predicateRegistryIssuer,
      expectedDomain: .predicateRegistry
    ))

    let relationRule = SRSVALBinding(
      identity: "RELATION-IDENTITY-RULE",
      version: "RULE_V1",
      contentDigest: digest("RELATION-IDENTITY-RULE:RULE_V1")
    )
    let swappedRelationRule = SRSVALBinding(
      identity: relationRule.version,
      version: relationRule.identity,
      contentDigest: relationRule.contentDigest
    )
    let authorization = authorizationPayload(classes: ["FRESHNESS_RECHECK_REQUIRED"], relationRule: relationRule)
    let swappedAuthorization = SRSVALAuthorizationPayload(
      sourceRelationIdentity: authorization.sourceRelationIdentity,
      invalidationClasses: Set(authorization.invalidationClasses),
      requestClass: authorization.requestClass,
      authorizedResultIdentity: authorization.authorizedResultIdentity,
      semanticClass: authorization.semanticClass,
      coveredFailureClasses: Set(authorization.coveredFailureClasses),
      targetBoundary: authorization.targetBoundary,
      relationIdentityRule: swappedRelationRule
    )
    XCTAssertNotEqual(authorization.canonicalData, swappedAuthorization.canonicalData)
    let authorizationSignature = try testIssuer(.authorization, privateKeys: testIssuerPrivateKeys)
      .seal(authorization, domain: .authorization)
    let swappedAuthorizationRecord = SRSVALSignedRecord<SRSVALAuthorizationPayload>(
      domain: .authorization,
      payload: swappedAuthorization,
      signature: authorizationSignature.signature,
      signer: authorizationSignature.signer
    )
    XCTAssertTrue(authorizationSignature.verify(
      anchor: testAnchors.authorizationIssuer,
      expectedDomain: .authorization
    ))
    XCTAssertFalse(swappedAuthorizationRecord.verify(
      anchor: testAnchors.authorizationIssuer,
      expectedDomain: .authorization
    ))

    func freshness(_ identity: String, observedAt: String) -> SRSVALFreshness {
      SRSVALFreshness(
        boundary: boundary,
        requirements: [SRSVALFreshnessRequirement(
          identity: identity,
          evidence: binding("FRESHNESS_EVIDENCE"),
          expectedEvidenceDigest: digest("FRESHNESS"),
          status: .current,
          validUntilUTC: "2030-01-01T00:00:00Z",
          observedAtUTC: observedAt
        )]
      )
    }
    let freshnessOriginal = freshness("REQ-A", observedAt: "TIME-A")
    let freshnessSwapped = freshness("TIME-A", observedAt: "REQ-A")
    XCTAssertNotEqual(freshnessOriginal.canonicalData, freshnessSwapped.canonicalData)
    let freshnessSignature = try testIssuer(.recordIntegrity, privateKeys: testIssuerPrivateKeys)
      .seal(freshnessOriginal, domain: .recordIntegrity)
    let swappedFreshnessRecord = SRSVALSignedRecord<SRSVALFreshness>(
      domain: .recordIntegrity,
      payload: freshnessSwapped,
      signature: freshnessSignature.signature,
      signer: freshnessSignature.signer
    )
    XCTAssertTrue(freshnessSignature.verify(
      anchor: testAnchors.recordIntegrityIssuer,
      expectedDomain: .recordIntegrity
    ))
    XCTAssertFalse(swappedFreshnessRecord.verify(
      anchor: testAnchors.recordIntegrityIssuer,
      expectedDomain: .recordIntegrity
    ))

    let rule = predicateRulePayload(subject: "FRESH-A")
    let classification = classificationPayload(rule: rule, classification: .recomputeEligible)
    let inputs = makeHealthyInputs()
    let observationOriginal = observationPayload(
      inputs: inputs,
      authorizationBinding: nil,
      rules: [rule],
      classifications: [classification]
    )
    let swappedClassification = SRSVALClassificationPayload(
      registryAuthority: classification.registryAuthority,
      predicateRule: classification.predicateRule,
      identity: classification.identity,
      version: classification.version,
      failureClass: classification.subjectIdentity,
      subjectIdentity: classification.failureClass,
      classification: classification.classification
    )
    let observationSwapped = observationPayload(
      inputs: inputs,
      authorizationBinding: nil,
      rules: [rule],
      classifications: [swappedClassification]
    )
    XCTAssertNotEqual(observationOriginal.canonicalData, observationSwapped.canonicalData)
    let observationSignature = try signedObservation(payload: observationOriginal)
    let swappedObservationRecord = SRSVALSignedRecord<SRSVALObservationPayload>(
      domain: .observation,
      payload: observationSwapped,
      signature: observationSignature.signature,
      signer: observationSignature.signer
    )
    XCTAssertTrue(observationSignature.verify(
      anchor: testAnchors.observationIssuer,
      expectedDomain: .observation
    ))
    XCTAssertFalse(swappedObservationRecord.verify(
      anchor: testAnchors.observationIssuer,
      expectedDomain: .observation
    ))
  }

  func testDP4VerifiedAuthorityChainResolvesPureReuse() throws {
    let inputs = healthyInputs()
    let observationPayload = observationPayload(inputs: inputs, authorizationBinding: nil, rules: [], classifications: [])
    let observation = try signedObservation(payload: observationPayload)
    let integrity = try signedIntegrity(payload: SRSVALInputIntegrityPayload(
      settledRelationState: inputs.state,
      sourceRelation: inputs.source,
      dependencies: inputs.dependencies,
      result: inputs.result,
      provenance: inputs.provenance,
      lifecycle: inputs.lifecycle,
      freshness: inputs.freshness,
      policy: inputs.policy,
      reuseRequest: inputs.request
    ))
    let outcome = try SRSVALDecisionCore.evaluate(
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
      inputIntegrity: try signedIntegrity(payload: SRSVALInputIntegrityPayload(
        settledRelationState: inputs.state,
        sourceRelation: inputs.source,
        dependencies: inputs.dependencies,
        result: inputs.result,
        provenance: inputs.provenance,
        lifecycle: inputs.lifecycle,
        freshness: inputs.freshness,
        policy: inputs.policy,
        reuseRequest: inputs.request
      )),
      anchors: testAnchors
    )
    XCTAssertEqual(.reuse, outcome.decision)
    XCTAssertTrue(outcome.i14NotUsedMarkerValid)
  }

  func testPublicEvaluateCannotInjectCustomTrustAnchors() throws {
    let inputs = healthyInputs()
    let payload = observationPayload(inputs: inputs, authorizationBinding: nil, rules: [], classifications: [])
    let observation = try signedObservation(payload: payload)
    let integrity = try signedIntegrity(payload: SRSVALInputIntegrityPayload(
      settledRelationState: inputs.state,
      sourceRelation: inputs.source,
      dependencies: inputs.dependencies,
      result: inputs.result,
      provenance: inputs.provenance,
      lifecycle: inputs.lifecycle,
      freshness: inputs.freshness,
      policy: inputs.policy,
      reuseRequest: inputs.request
    ))
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
      inputIntegrity: integrity
    )
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.validationInputStateInconsistent, outcome.reason)
  }

  func testDP0DifferentObjectBoundaryFailsClosed() throws {
    let inputs = healthyInputs()
    let payload = observationPayload(inputs: inputs, authorizationBinding: nil, rules: [], classifications: [])
    let observation = SRSVALSignedRecord(
      domain: .observation,
      payload: payload,
      signature: Data(base64Encoded: "ZYxex9pynFAVp0TJg/ZGSGz3ihigjdpn0vj4OLlXZIwetlFGJpUjFLTIyeUyR0JesF3HhBbpkvwQHtTuJ6KECg==")!,
      signer: testAnchors.observationIssuer
    )
    let mismatched = SRSVALObservation(
      boundary: payload.observation.boundary,
      orderingEvidence: payload.observation.orderingEvidence,
      observedAtUTC: payload.observation.observedAtUTC,
      srsEvidence: payload.observation.srsEvidence,
      dependencyEvidence: binding("OTHER-BOUNDARY"),
      resultEvidence: payload.observation.resultEvidence,
      provenanceEvidence: payload.observation.provenanceEvidence,
      freshnessPolicyEvidence: payload.observation.freshnessPolicyEvidence,
      lifecycleEvidence: payload.observation.lifecycleEvidence,
      policyEvidence: payload.observation.policyEvidence,
      consistencyEvidence: payload.observation.consistencyEvidence,
      closeBoundary: payload.observation.closeBoundary,
      requestReference: payload.observation.requestReference,
      i14Reference: payload.observation.i14Reference,
      predicateRuleReferences: payload.observation.predicateRuleReferences,
      predicateClassifications: payload.observation.predicateClassifications
    )
    let mismatchedRecord = SRSVALSignedRecord(
      domain: .observation,
      payload: SRSVALObservationPayload(observation: mismatched, classifications: payload.classifications),
      signature: Data(repeating: 7, count: 64),
      signer: testAnchors.observationIssuer
    )
    let outcome = try SRSVALDecisionCore.evaluate(
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
      observation: mismatchedRecord,
      inputIntegrity: try signedIntegrity(payload: SRSVALInputIntegrityPayload(
        settledRelationState: inputs.state,
        sourceRelation: inputs.source,
        dependencies: inputs.dependencies,
        result: inputs.result,
        provenance: inputs.provenance,
        lifecycle: inputs.lifecycle,
        freshness: inputs.freshness,
        policy: inputs.policy,
        reuseRequest: inputs.request
      )),
      anchors: testAnchors
    )
    XCTAssertEqual(.block, outcome.decision)
  }

  func testInvalidI14CannotProducePureReuse() throws {
    let inputs = healthyInputs()
    let authPayload = authorizationPayload(classes: ["FRESHNESS_RECHECK_REQUIRED"])
    let authBinding = SRSVALDecisionCore.authorizationBindingForPayload(authPayload)
    let observationPayload = observationPayload(
      inputs: inputs,
      authorizationBinding: authBinding,
      rules: [],
      classifications: []
    )
    var invalidAuthorization = try signedAuthorization(payload: authPayload)
    invalidAuthorization = SRSVALSignedRecord(domain: .authorization, payload: invalidAuthorization.payload, signature: Data(repeating: 9, count: 64), signer: invalidAuthorization.signer)
    let observation = try signedObservation(payload: observationPayload)
    let outcome = try SRSVALDecisionCore.evaluate(
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
      authorization: invalidAuthorization,
      observation: observation,
      inputIntegrity: try signedIntegrity(payload: SRSVALInputIntegrityPayload(
        settledRelationState: inputs.state,
        sourceRelation: inputs.source,
        dependencies: inputs.dependencies,
        result: inputs.result,
        provenance: inputs.provenance,
        lifecycle: inputs.lifecycle,
        freshness: inputs.freshness,
        policy: inputs.policy,
        reuseRequest: inputs.request
      )),
      anchors: testAnchors
    )
    XCTAssertEqual(.block, outcome.decision)
  }

  func testDP3MixedEligibleAndNonEligibleFailuresBlock() throws {
    let inputs = staleInputs(subjects: ["FRESH-A", "FRESH-B"])
    let ruleA = predicateRulePayload(subject: "FRESH-A")
    let ruleB = predicateRulePayload(subject: "FRESH-B")
    let classA = classificationPayload(rule: ruleA, classification: .recomputeEligible)
    let classB = classificationPayload(rule: ruleB, classification: .nonRecompute)
    let authPayload = authorizationPayload(classes: ["FRESHNESS_RECHECK_REQUIRED"])
    let rules = [ruleA, ruleB]
    let classifications = [classA, classB]
    let authorization = try signedAuthorization(payload: authPayload)
    let observation = try signedObservation(payload: observationPayload(inputs: inputs, authorizationBinding: SRSVALDecisionCore.authorizationBindingForPayload(authPayload), rules: rules, classifications: classifications))
    let outcome = try SRSVALDecisionCore.evaluate(
      settledRelationState: inputs.state,
      sourceRelation: inputs.source,
      dependencies: inputs.dependencies,
      result: inputs.result,
      provenance: inputs.provenance,
      lifecycle: inputs.lifecycle,
      freshness: inputs.freshness,
      policy: inputs.policy,
      reuseRequest: inputs.request,
      registeredPredicateRules: [
          try signedRule(payload: ruleA),
        try signedRule(payload: ruleB)
      ],
      classificationRecords: [
        try signedClassification(payload: classA),
        try signedClassification(payload: classB)
      ],
      authorization: authorization,
      observation: observation,
      inputIntegrity: try signedIntegrity(
        payload: SRSVALInputIntegrityPayload(
          settledRelationState: inputs.state,
          sourceRelation: inputs.source,
          dependencies: inputs.dependencies,
          result: inputs.result,
          provenance: inputs.provenance,
          lifecycle: inputs.lifecycle,
          freshness: inputs.freshness,
          policy: inputs.policy,
          reuseRequest: inputs.request
        )
      ),
      anchors: testAnchors
    )
    XCTAssertEqual(.block, outcome.decision)
  }

  func testDP3AllEligibleFailuresWithAuthoritativeI14AuthorizeRecompute() throws {
    let inputs = makeStaleEligibleInputs()
    let rule = predicateRulePayload(subject: "FRESH-A")
    let classification = classificationPayload(rule: rule, classification: .recomputeEligible)
    let authPayload = authorizationPayload(classes: ["FRESHNESS_RECHECK_REQUIRED"])
    let outcome = try evaluateFixture(
      inputs: inputs,
      rules: [rule],
      classifications: [classification],
      authorization: authPayload
    )
    XCTAssertEqual(.recompute, outcome.decision)
    XCTAssertEqual(.freshnessRecheckRequired, outcome.reason)
    XCTAssertEqual(SRSVALDecisionCore.authorizationBindingForPayload(authPayload), outcome.authorizationUsed)
  }

  func testFreshnessDigestMismatchFailsClosed() throws {
    let inputs = makeHealthyInputs()
    let requirements = [freshnessRequirement(
      subject: "FRESH-A",
      status: .recheckRequired,
      digestMismatch: true
    )]
    let mismatched = Inputs(
      state: inputs.state,
      source: inputs.source,
      dependencies: inputs.dependencies,
      result: inputs.result,
      provenance: inputs.provenance,
      lifecycle: inputs.lifecycle,
      freshness: SRSVALFreshness(boundary: boundary, requirements: requirements),
      policy: inputs.policy,
      request: inputs.request
    )
    let rule = predicateRulePayload(subject: "FRESH-A")
    let classification = classificationPayload(rule: rule, classification: .recomputeEligible)
    let outcome = try evaluateFixture(
      inputs: mismatched,
      rules: [rule],
      classifications: [classification]
    )
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.recomputeAuthorizationInvalid, outcome.reason)
    XCTAssertEqual(.freshnessRecheckRequired, outcome.failures.first?.reason)
    XCTAssertNil(outcome.authorizationUsed)
  }

  func testExpiredFreshnessFailsClosed() throws {
    let inputs = Inputs(
      state: state(), source: sourceRelation(), dependencies: dependencies(), result: result(),
      provenance: provenance(), lifecycle: lifecycle(),
      freshness: SRSVALFreshness(boundary: boundary, requirements: [freshnessRequirement(status: .current, validUntil: "2020-01-01T00:00:00Z", observedAt: observedAt)]),
      policy: policy(), request: request()
    )
    let rule = predicateRulePayload(subject: "FRESH-A")
    let classification = classificationPayload(rule: rule, classification: .recomputeEligible)
    let outcome = try evaluateFixture(
      inputs: inputs,
      rules: [rule],
      classifications: [classification]
    )
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.recomputeAuthorizationInvalid, outcome.reason)
    XCTAssertEqual(.freshnessRecheckRequired, outcome.failures.first?.reason)
    XCTAssertNil(outcome.authorizationUsed)
  }

  func testFreshnessObservationTimeMismatchFailsClosed() throws {
    let inputs = makeHealthyInputs()
    let mismatched = Inputs(
      state: inputs.state,
      source: inputs.source,
      dependencies: inputs.dependencies,
      result: inputs.result,
      provenance: inputs.provenance,
      lifecycle: inputs.lifecycle,
      freshness: SRSVALFreshness(
        boundary: boundary,
        requirements: [freshnessRequirement(observedAt: "2026-10-10T00:00:00Z")]
      ),
      policy: inputs.policy,
      request: inputs.request
    )
    let rule = predicateRulePayload(subject: "FRESH-A")
    let classification = classificationPayload(rule: rule, classification: .recomputeEligible)
    let outcome = try evaluateFixture(
      inputs: mismatched,
      rules: [rule],
      classifications: [classification]
    )
    XCTAssertEqual(.block, outcome.decision)
    XCTAssertEqual(.recomputeAuthorizationInvalid, outcome.reason)
    XCTAssertEqual(.freshnessRecheckRequired, outcome.failures.first?.reason)
    XCTAssertNil(outcome.authorizationUsed)
  }

  func testSourceSemanticStateCannotBypassSignedIntegrity() throws {
    let inputs = healthyInputs()
    let rawInvalidSource = sourceRelation(invalidation: .invalidated)
    let signedHealthy = try signedIntegrity(payload: SRSVALInputIntegrityPayload(
      settledRelationState: inputs.state,
      sourceRelation: inputs.source,
      dependencies: inputs.dependencies,
      result: inputs.result,
      provenance: inputs.provenance,
      lifecycle: inputs.lifecycle,
      freshness: inputs.freshness,
      policy: inputs.policy,
      reuseRequest: inputs.request
    ))
    let observation = try signedObservation(
      payload: observationPayload(inputs: inputs, authorizationBinding: nil, rules: [], classifications: []),
    )
    let outcome = try SRSVALDecisionCore.evaluate(
      settledRelationState: inputs.state,
      sourceRelation: rawInvalidSource,
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
      inputIntegrity: signedHealthy,
      anchors: testAnchors
    )
    XCTAssertEqual(.block, outcome.decision)
  }
}
