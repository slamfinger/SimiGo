import Crypto
import Foundation

/// Pure SRS-VAL-01 Decision Core for frozen Design v0.8.
/// It performs no I/O, no persistence, no model execution, and no mutation.
public enum SRSVALDecision: String, Equatable, Sendable {
  case reuse
  case block
  case recompute
}

public enum SRSVALRule: String, Equatable, Sendable, CaseIterable {
  case srsDeclarationIntegrity = "G-V1"
  case sourceRelation = "G-V2"
  case dependencies = "G-V3"
  case result = "G-V4"
  case resolutionPolicy = "G-V5"
  case provenanceLifecycle = "G-V6"
  case freshness = "G-V7"
}

public enum SRSVALFailureReason: String, Equatable, Sendable {
  case validationInputStateInconsistent = "VALIDATION_INPUT_STATE_INCONSISTENT"
  case srsDeclarationIntegrity = "SRS_DECLARATION_INTEGRITY_FAILURE"
  case sourceRelation = "SOURCE_RELATION_FAILURE"
  case dependencies = "DEPENDENCY_FAILURE"
  case result = "RESULT_FAILURE"
  case resolutionPolicy = "RESOLUTION_OR_POLICY_FAILURE"
  case provenanceLifecycle = "PROVENANCE_OR_LIFECYCLE_FAILURE"
  case freshnessRecheckRequired = "FRESHNESS_RECHECK_REQUIRED"
  case notApplicable = "NOT_APPLICABLE"
  case applicabilityIndeterminate = "APPLICABILITY_INDETERMINATE"
  case predicateRuleBindingUnstableOrMissing = "PREDICATE_RULE_BINDING_UNSTABLE_OR_MISSING"
  case predicateRuleClassificationRequired = "PREDICATE_RULE_CLASSIFICATION_REQUIRED"
  case recomputeAuthorizationInvalid = "RECOMPUTE_AUTHORIZATION_INVALID"
}

public enum SRSVALSeverity: String, Equatable, Sendable {
  case hardBlock
  case classifiable
}

public enum SRSVALClassification: String, Equatable, Sendable {
  case recomputeEligible
  case nonRecompute
}

public enum SRSVALRecordStatus: String, Equatable, Sendable {
  case current
  case superseded
  case invalidated
}

public enum SRSVALSourceInvalidationStatus: String, Equatable, Sendable {
  case none
  case superseded
  case invalidated
}

public enum SRSVALResolutionStatus: String, Equatable, Sendable {
  case resolved
  case unresolved
}

public enum SRSVALResultResolution: String, Equatable, Sendable {
  case resolvedWithoutRecompute = "RESOLVED_WITHOUT_RECOMPUTE"
  case unresolved
}

public enum SRSVALFreshnessStatus: String, Equatable, Sendable {
  case current
  case recheckRequired = "FRESHNESS_RECHECK_REQUIRED"
}

public enum SRSVALLifecycleState: String, Equatable, Sendable {
  case declaredSettled = "DECLARED_SETTLED"
  case contested = "CONTESTED"
  case unresolvedLifecycleConflict = "UNRESOLVED_LIFECYCLE_CONFLICT"
  case invalidated = "INVALIDATED"
}

public enum SRSVALRequestApplicability: String, Equatable, Sendable {
  case applicable
  case notApplicable
  case indeterminate
}

/// An exact semantic identity/version/content binding. Missing evidence is
/// never interpreted as a pass.
public struct SRSVALBinding: Equatable, Hashable, Sendable {
  public let identity: String
  public let version: String
  public let contentDigest: String

  public init(identity: String, version: String, contentDigest: String) {
    self.identity = identity
    self.version = version
    self.contentDigest = contentDigest
  }

  public var isExact: Bool {
    !identity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && contentDigest.count == 64
      && contentDigest.allSatisfy(\.isHexDigit)
  }
}

public struct SRSVALFailure: Equatable, Hashable, Sendable {
  public let rule: SRSVALRule
  public let reason: SRSVALFailureReason
  public let severity: SRSVALSeverity
  public let failureClass: String
  public let predicateRule: SRSVALBinding?
  public let classification: SRSVALClassification?
  public let subjectIdentity: String

  public init(
    rule: SRSVALRule,
    reason: SRSVALFailureReason,
    severity: SRSVALSeverity,
    failureClass: String,
    predicateRule: SRSVALBinding? = nil,
        classification: SRSVALClassification? = nil,
        subjectIdentity: String = ""
  ) {
    self.rule = rule
    self.reason = reason
    self.severity = severity
    self.failureClass = failureClass
    self.predicateRule = predicateRule
    self.classification = classification
        self.subjectIdentity = subjectIdentity
  }
}

public struct SRSVALSettledRelationState: Equatable, Sendable {
  public let binding: SRSVALBinding?
  public let settlementID: String
  public let status: String
  public let sourceRelationIdentity: String
  public let resultIdentity: String
  public let requiresCanonicalIdentityRule: Bool
  public let canonicalIdentityRule: SRSVALBinding?
  public let provenanceBindings: [SRSVALBinding]?

  public init(
    binding: SRSVALBinding?,
    settlementID: String,
    status: String,
    sourceRelationIdentity: String,
    resultIdentity: String,
    requiresCanonicalIdentityRule: Bool,
    canonicalIdentityRule: SRSVALBinding?,
    provenanceBindings: [SRSVALBinding]?
  ) {
    self.binding = binding
    self.settlementID = settlementID
    self.status = status
    self.sourceRelationIdentity = sourceRelationIdentity
    self.resultIdentity = resultIdentity
    self.requiresCanonicalIdentityRule = requiresCanonicalIdentityRule
    self.canonicalIdentityRule = canonicalIdentityRule
    self.provenanceBindings = provenanceBindings
  }
}

public struct SRSVALSourceRelation: Equatable, Sendable {
  public let binding: SRSVALBinding?
  public let semanticBinding: SRSVALBinding?
  public let applicabilityCoverage: SRSVALBinding?
  public let invalidationRecord: SRSVALBinding?
  public let invalidationStatus: SRSVALSourceInvalidationStatus
  public let identityRule: SRSVALBinding?
  public let status: SRSVALRecordStatus

  public init(
    binding: SRSVALBinding?,
    semanticBinding: SRSVALBinding?,
    applicabilityCoverage: SRSVALBinding?,
    invalidationRecord: SRSVALBinding?,
    invalidationStatus: SRSVALSourceInvalidationStatus,
    identityRule: SRSVALBinding?,
    status: SRSVALRecordStatus
  ) {
    self.binding = binding
    self.semanticBinding = semanticBinding
    self.applicabilityCoverage = applicabilityCoverage
    self.invalidationRecord = invalidationRecord
    self.invalidationStatus = invalidationStatus
    self.identityRule = identityRule
    self.status = status
  }
}

public struct SRSVALDependency: Equatable, Sendable {
  public let binding: SRSVALBinding?
  public let role: String
  public let necessity: String
  public let resolution: SRSVALResolutionStatus
  public let status: SRSVALRecordStatus

  public init(
    binding: SRSVALBinding?,
    role: String,
    necessity: String,
        resolution: SRSVALResolutionStatus,
    status: SRSVALRecordStatus
  ) {
    self.binding = binding
    self.role = role
    self.necessity = necessity
    self.resolution = resolution
    self.status = status
  }
}

public struct SRSVALResult: Equatable, Sendable {
  public let binding: SRSVALBinding?
  public let resolution: SRSVALResultResolution
  public let interpretabilityEvidence: SRSVALBinding?
  public let status: SRSVALRecordStatus

  public init(
    binding: SRSVALBinding?,
        resolution: SRSVALResultResolution,
    interpretabilityEvidence: SRSVALBinding?,
    status: SRSVALRecordStatus
  ) {
    self.binding = binding
    self.resolution = resolution
    self.interpretabilityEvidence = interpretabilityEvidence
    self.status = status
  }
}

public struct SRSVALResolutionPolicy: Equatable, Sendable {
  public let resolutionRule: SRSVALBinding?
  public let policies: [SRSVALBinding]?
  public let boundary: SRSVALBinding?

  public init(
    resolutionRule: SRSVALBinding?,
    policies: [SRSVALBinding]?,
    boundary: SRSVALBinding?
  ) {
    self.resolutionRule = resolutionRule
    self.policies = policies
    self.boundary = boundary
  }
}

public struct SRSVALProvenanceLifecycle: Equatable, Sendable {
  public let bindings: [SRSVALBinding]?
  public let lifecycle: SRSVALLifecycleState
  public let boundary: SRSVALBinding?

  public init(
    bindings: [SRSVALBinding]?,
    lifecycle: SRSVALLifecycleState,
    boundary: SRSVALBinding?
  ) {
    self.bindings = bindings
    self.lifecycle = lifecycle
    self.boundary = boundary
  }
}

public struct SRSVALDependencySet: Equatable, Sendable {
  public let boundary: SRSVALBinding?
  public let dependencies: [SRSVALDependency]?

  public init(boundary: SRSVALBinding?, dependencies: [SRSVALDependency]?) {
    self.boundary = boundary
    self.dependencies = dependencies
  }
}

public struct SRSVALFreshnessRequirement: Equatable, Sendable {
  public let identity: String
  public let evidence: SRSVALBinding?
  public let expectedEvidenceDigest: String
  public let status: SRSVALFreshnessStatus
  public let validUntilUTC: String?
  public let observedAtUTC: String

  public init(
    identity: String,
    evidence: SRSVALBinding?,
    expectedEvidenceDigest: String,
    status: SRSVALFreshnessStatus,
    validUntilUTC: String? = nil,
    observedAtUTC: String
  ) {
    self.identity = identity
    self.evidence = evidence
    self.expectedEvidenceDigest = expectedEvidenceDigest
    self.status = status
    self.validUntilUTC = validUntilUTC
    self.observedAtUTC = observedAtUTC
  }
}

public struct SRSVALFreshness: Equatable, Sendable {
  public let boundary: SRSVALBinding?
  public let requirements: [SRSVALFreshnessRequirement]?

  public init(boundary: SRSVALBinding?, requirements: [SRSVALFreshnessRequirement]?) {
    self.boundary = boundary
    self.requirements = requirements
  }
}

public struct SRSVALReuseRequest: Equatable, Sendable {
  public let binding: SRSVALBinding?
  public let requestClass: String
  public let relationIdentity: String
  public let resultIdentity: String
  public let declaredApplicability: SRSVALRequestApplicability

  public init(
    binding: SRSVALBinding?,
    requestClass: String,
    relationIdentity: String,
    resultIdentity: String,
    declaredApplicability: SRSVALRequestApplicability
  ) {
    self.binding = binding
    self.requestClass = requestClass
    self.relationIdentity = relationIdentity
    self.resultIdentity = resultIdentity
    self.declaredApplicability = declaredApplicability
  }
}

public struct SRSVALRecomputeEnvelope: Equatable, Sendable {
  public let coveredFailureClasses: [String]?
  public let targetBoundary: SRSVALBinding?
  public let relationIdentityRule: SRSVALBinding?

  public init(
    coveredFailureClasses: [String]?,
    targetBoundary: SRSVALBinding?,
    relationIdentityRule: SRSVALBinding?
  ) {
    self.coveredFailureClasses = coveredFailureClasses
    self.targetBoundary = targetBoundary
    self.relationIdentityRule = relationIdentityRule
  }
}

/// Immutable governing I-14 authorization. Required only after mandatory
/// classification produces a RECOMPUTE_ELIGIBLE surviving failure. Creation is
/// sealed to a canonical content encoding so every authorization field is
/// covered by the binding digest.
public struct SRSVALRecomputeAuthorization: Equatable, Sendable {
  public let binding: SRSVALBinding?
  public let content: String
  public let canonicalContent: String
  public let sourceRelationIdentity: String
  public let invalidationClasses: Set<String>
  public let requestClass: String
  public let authorizedResultIdentity: String
  public let semanticClass: String
  public let envelope: SRSVALRecomputeEnvelope?

  private init(
    binding: SRSVALBinding?,
    content: String,
    canonicalContent: String,
    sourceRelationIdentity: String,
    invalidationClasses: Set<String>,
    requestClass: String,
    authorizedResultIdentity: String,
    semanticClass: String,
    envelope: SRSVALRecomputeEnvelope?
  ) {
    self.binding = binding
    self.content = content
    self.canonicalContent = canonicalContent
    self.sourceRelationIdentity = sourceRelationIdentity
    self.invalidationClasses = invalidationClasses
    self.requestClass = requestClass
    self.authorizedResultIdentity = authorizedResultIdentity
    self.semanticClass = semanticClass
    self.envelope = envelope
  }

  public static func authorize(
    sourceRelationIdentity: String,
    invalidationClasses: Set<String>,
    requestClass: String,
    authorizedResultIdentity: String,
    semanticClass: String,
    envelope: SRSVALRecomputeEnvelope
  ) -> SRSVALRecomputeAuthorization {
    let lines = [
      "SRSVAL-AUTHORIZATION-V1",
      srsvalField("source_relation", sourceRelationIdentity),
      srsvalField("invalidation_classes", invalidationClasses.sorted().joined(separator: "\u{1F}")),
      srsvalField("request_class", requestClass),
      srsvalField("authorized_result", authorizedResultIdentity),
      srsvalField("semantic_class", semanticClass),
      srsvalField(
        "covered_classes",
        envelope.coveredFailureClasses?.sorted().joined(separator: "\u{1F}") ?? ""
      ),
      srsvalBindingField("target_boundary", envelope.targetBoundary),
      srsvalBindingField("relation_identity_rule", envelope.relationIdentityRule),
    ]
    let canonical = lines.joined(separator: "\n")
    let binding = SRSVALBinding(
      identity: "I-14",
      version: "EXACT_AUTHORIZATION_V1",
      contentDigest: SHA256.hash(data: Data(canonical.utf8))
        .map { String(format: "%02x", $0) }.joined()
    )
    return SRSVALRecomputeAuthorization(
      binding: binding,
      content: canonical,
      canonicalContent: canonical,
      sourceRelationIdentity: sourceRelationIdentity,
      invalidationClasses: invalidationClasses,
      requestClass: requestClass,
      authorizedResultIdentity: authorizedResultIdentity,
      semanticClass: semanticClass,
      envelope: envelope
    )
  }
}

/// A pure decision core accepts predicate rules only from this immutable
/// registry authority. The authority does not perform I/O; it fixes the trust
/// boundary for the in-memory registered-rule input.
public struct SRSVALPredicateRuleAuthority: Equatable, Hashable, Sendable {
  public static let required = SRSVALBinding(
    identity: "SRSVAL:PREDICATE_RULE_REGISTRY",
    version: "AUTHORITY_V1",
    contentDigest: SHA256.hash(data: Data("SRSVAL-PREDICATE-RULE-REGISTRY-AUTHORITY".utf8))
      .map { String(format: "%02x", $0) }.joined()
  )

  public let binding: SRSVALBinding

  public init(binding: SRSVALBinding) {
    self.binding = binding
  }
}

/// A registered rule is sealed to its authority, identity, version, failure
/// class, and complete subject coverage through canonical content.
public struct SRSVALRegisteredPredicateRule: Equatable, Hashable, Sendable {
  public let registryAuthority: SRSVALBinding
  public let predicateRule: SRSVALBinding
  public let identity: String
  public let version: String
  public let content: String
  public let canonicalContent: String
  public let failureClass: String
  public let subjectIdentities: Set<String>

  private init(
    registryAuthority: SRSVALBinding,
    predicateRule: SRSVALBinding,
    identity: String,
    version: String,
    content: String,
    canonicalContent: String,
    failureClass: String,
    subjectIdentities: Set<String>
  ) {
    self.registryAuthority = registryAuthority
    self.predicateRule = predicateRule
    self.identity = identity
    self.version = version
    self.content = content
    self.canonicalContent = canonicalContent
    self.failureClass = failureClass
    self.subjectIdentities = subjectIdentities
  }

  public static func register(
    authority: SRSVALPredicateRuleAuthority,
    identity: String,
    version: String,
    failureClass: String,
    subjectIdentities: Set<String>
  ) -> SRSVALRegisteredPredicateRule? {
    guard authority.binding == SRSVALPredicateRuleAuthority.required,
      !identity.isEmpty, !version.isEmpty, !failureClass.isEmpty,
      !subjectIdentities.isEmpty,
      subjectIdentities.allSatisfy({ !$0.isEmpty }),
      !identity.contains("\n"), !version.contains("\n"),
      !failureClass.contains("\n"),
      !subjectIdentities.contains(where: { $0.contains("\n") })
    else { return nil }

    let subjectLines = subjectIdentities
      .sorted()
      .map { srsvalField("subject", $0) }
      .joined(separator: "\n")
    let canonical = [
      "SRSVAL-PREDICATE-RULE-V1",
      srsvalField("registry_authority", authority.binding.identity),
      srsvalField("registry_version", authority.binding.version),
      srsvalField("identity", identity),
      srsvalField("version", version),
      srsvalField("failure_class", failureClass),
      subjectLines,
    ].joined(separator: "\n")
    let predicateRule = SRSVALBinding(
      identity: "SRSVAL:PREDICATE_RULE:\(identity)",
      version: version,
      contentDigest: SHA256.hash(data: Data(canonical.utf8))
        .map { String(format: "%02x", $0) }.joined()
    )
    return SRSVALRegisteredPredicateRule(
      registryAuthority: authority.binding,
      predicateRule: predicateRule,
      identity: identity,
      version: version,
      content: canonical,
      canonicalContent: canonical,
      failureClass: failureClass,
      subjectIdentities: subjectIdentities
    )
  }

  var isValid: Bool {
    registryAuthority == SRSVALPredicateRuleAuthority.required
      && predicateRule.isExact
      && predicateRule.contentDigest == SHA256.hash(data: Data(canonicalContent.utf8))
        .map { String(format: "%02x", $0) }.joined()
      && content == canonicalContent
      && !failureClass.isEmpty
      && !subjectIdentities.isEmpty
  }

  func covers(failureClass: String, subjectIdentity: String) -> Bool {
    self.failureClass == failureClass && subjectIdentities.contains(subjectIdentity)
  }
}

private func srsvalField(_ label: String, _ value: String) -> String {
  let bytes = Array(value.utf8)
  return "\(label):\(bytes.count):\(value)"
}

private func srsvalBindingField(_ label: String, _ binding: SRSVALBinding?) -> String {
  let value = [
    binding?.identity ?? "",
    binding?.version ?? "",
    binding?.contentDigest ?? "",
  ].map { field in
    let bytes = Array(field.utf8)
    return "\(bytes.count):\(field)"
  }.joined(separator: "\u{1F}")
  return srsvalField(label, value)
}

public struct SRSVALPredicateClassification: Equatable, Hashable, Sendable {
  public let predicateRule: SRSVALBinding
  public let failureClass: String
  public let subjectIdentity: String
  public let classification: SRSVALClassification

  public init(
    predicateRule: SRSVALBinding,
    failureClass: String,
    subjectIdentity: String,
    classification: SRSVALClassification
  ) {
    self.predicateRule = predicateRule
    self.failureClass = failureClass
    self.subjectIdentity = subjectIdentity
    self.classification = classification
  }
}

public struct SRSVALObservation: Equatable, Sendable {
  public let boundary: SRSVALBinding?
  public let orderingEvidence: SRSVALBinding?
  public let observedAtUTC: String
  public let srsEvidence: SRSVALBinding?
  public let dependencyEvidence: SRSVALBinding?
  public let resultEvidence: SRSVALBinding?
  public let provenanceEvidence: SRSVALBinding?
  public let freshnessPolicyEvidence: SRSVALBinding?
  public let lifecycleEvidence: SRSVALBinding?
  public let policyEvidence: SRSVALBinding?
  public let consistencyEvidence: SRSVALBinding?
  public let closeBoundary: SRSVALBinding?
  public let requestReference: SRSVALBinding?
  public let i14Reference: SRSVALBinding?
  public let predicateRuleReferences: [SRSVALBinding]?
  public let predicateClassifications: [SRSVALPredicateClassification]?

  public init(
    boundary: SRSVALBinding?,
    orderingEvidence: SRSVALBinding?,
    observedAtUTC: String,
    srsEvidence: SRSVALBinding?,
    dependencyEvidence: SRSVALBinding?,
    resultEvidence: SRSVALBinding?,
    provenanceEvidence: SRSVALBinding?,
    freshnessPolicyEvidence: SRSVALBinding?,
    lifecycleEvidence: SRSVALBinding?,
    policyEvidence: SRSVALBinding?,
    consistencyEvidence: SRSVALBinding?,
    closeBoundary: SRSVALBinding?,
    requestReference: SRSVALBinding?,
    i14Reference: SRSVALBinding?,
    predicateRuleReferences: [SRSVALBinding]?
    ,predicateClassifications: [SRSVALPredicateClassification]?
  ) {
    self.boundary = boundary
    self.orderingEvidence = orderingEvidence
    self.observedAtUTC = observedAtUTC
    self.srsEvidence = srsEvidence
    self.dependencyEvidence = dependencyEvidence
    self.resultEvidence = resultEvidence
    self.provenanceEvidence = provenanceEvidence
    self.freshnessPolicyEvidence = freshnessPolicyEvidence
    self.lifecycleEvidence = lifecycleEvidence
    self.policyEvidence = policyEvidence
    self.consistencyEvidence = consistencyEvidence
    self.closeBoundary = closeBoundary
    self.requestReference = requestReference
    self.i14Reference = i14Reference
    self.predicateRuleReferences = predicateRuleReferences
    self.predicateClassifications = predicateClassifications
  }
}

public struct SRSVALDecisionOutcome: Equatable, Sendable {
  public let decision: SRSVALDecision
  public let reason: SRSVALFailureReason?
  public let failures: [SRSVALFailure]
  public let authorizationUsed: SRSVALBinding?
  public let i14NotUsedMarkerValid: Bool

  public init(
    decision: SRSVALDecision,
    reason: SRSVALFailureReason?,
    failures: [SRSVALFailure],
    authorizationUsed: SRSVALBinding?,
    i14NotUsedMarkerValid: Bool
  ) {
    self.decision = decision
    self.reason = reason
    self.failures = failures
    self.authorizationUsed = authorizationUsed
    self.i14NotUsedMarkerValid = i14NotUsedMarkerValid
  }
}

public enum SRSVALDecisionCore {
  public static let i14NotUsedMarker = SRSVALBinding(
    identity: "I-14_NOT_USED",
    version: "FROZEN_V0.8",
    contentDigest: SHA256.hash(data: Data("I14_NOT_USED_NO_RECOMPUTE_PATH".utf8))
      .map { String(format: "%02x", $0) }.joined()
  )

  public static func evaluate(
    settledRelationState: SRSVALSettledRelationState,
    sourceRelation: SRSVALSourceRelation,
    dependencies: SRSVALDependencySet?,
    result: SRSVALResult,
    provenance: SRSVALProvenanceLifecycle,
    lifecycle: SRSVALProvenanceLifecycle,
    freshness: SRSVALFreshness,
    policy: SRSVALResolutionPolicy,
    reuseRequest: SRSVALReuseRequest,
    registeredPredicateRules: [SRSVALRegisteredPredicateRule]?,
    authorization: SRSVALRecomputeAuthorization?,
    observation: SRSVALObservation
  ) -> SRSVALDecisionOutcome {
    // DP-0: exact observation boundary, I-15/I-16 references, and cross-object
    // identity closure. Format validity alone is never accepted as binding.
    let observationFields: [SRSVALBinding?] = [
      observation.boundary,
      observation.orderingEvidence,
      observation.srsEvidence,
      observation.dependencyEvidence,
      observation.resultEvidence,
      observation.provenanceEvidence,
      observation.freshnessPolicyEvidence,
      observation.lifecycleEvidence,
      observation.policyEvidence,
      observation.consistencyEvidence,
      observation.closeBoundary,
    ]
    let providedPredicateRules = registeredPredicateRules ?? []
    guard observationFields.allSatisfy({ $0?.isExact == true }),
      observation.srsEvidence == settledRelationState.binding,
      observation.dependencyEvidence == dependencies?.boundary,
      dependencies?.boundary == observation.boundary,
      observation.resultEvidence == result.binding,
      observation.provenanceEvidence == provenance.boundary,
      provenance.boundary == observation.boundary,
      observation.lifecycleEvidence == lifecycle.boundary,
      lifecycle.boundary == observation.boundary,
      observation.freshnessPolicyEvidence == freshness.boundary,
      freshness.boundary == observation.boundary,
      observation.policyEvidence == policy.boundary,
      policy.boundary == observation.boundary,
      observation.closeBoundary == observation.boundary,
      observation.requestReference?.isExact == true,
      observation.requestReference == reuseRequest.binding,
      utcTime(observation.observedAtUTC) != nil,
      observation.orderingEvidence?.isExact == true,
      observation.orderingEvidence?.identity
        == "ORDERING_EVIDENCE:\(observation.boundary?.identity ?? ""):\(observation.observedAtUTC)",
      providedPredicateRules.allSatisfy({ $0.isValid }),
      providedPredicateRules.allSatisfy({
        $0.registryAuthority == SRSVALPredicateRuleAuthority.required
      }),
      Set(providedPredicateRules.map({ $0.predicateRule })).count == providedPredicateRules.count,
      observation.predicateRuleReferences?.allSatisfy({ $0.isExact }) == true,
      observation.predicateClassifications != nil,
      observation.predicateClassifications?.allSatisfy({ classification in
        classification.predicateRule.isExact
          && !classification.failureClass.isEmpty
          && !classification.subjectIdentity.isEmpty
          && providedPredicateRules.contains { $0.predicateRule == classification.predicateRule }
          && observation.predicateRuleReferences?.contains(classification.predicateRule) == true
      }) == true
    else {
      return block(.validationInputStateInconsistent, failures: [], markerValid: false)
    }

    let expectedI14 = authorization?.binding ?? i14NotUsedMarker
    guard observation.i14Reference?.isExact == true,
      observation.i14Reference == expectedI14
    else {
      return block(.validationInputStateInconsistent, failures: [], markerValid: false)
    }
    let notUsedMarkerValid =
      observation.i14Reference == i14NotUsedMarker
      && authorization?.binding == nil

    let registeredPredicateRules = providedPredicateRules

    let failures = validationFailures(
      settledRelationState: settledRelationState,
      sourceRelation: sourceRelation,
      dependencies: dependencies,
      result: result,
      provenance: provenance,
      lifecycle: lifecycle,
      freshness: freshness,
      policy: policy,
      observedAtUTC: observation.observedAtUTC
    )

    // DP-1: any HARD_BLOCK outranks classifiable failures and DP-2.
    if let hardBlock = failures.first(where: { $0.severity == .hardBlock }) {
      return block(hardBlock.reason, failures: failures, markerValid: notUsedMarkerValid)
    }

    // DP-2: applicability must be positively determinate.
    let applicability = requestApplicability(
      request: reuseRequest,
      settledRelationState: settledRelationState
    )
    if applicability == .notApplicable {
      return block(.notApplicable, failures: failures, markerValid: notUsedMarkerValid)
    }
    if applicability == .indeterminate {
      return block(.applicabilityIndeterminate, failures: failures, markerValid: notUsedMarkerValid)
    }

    // G-CLASS: choose exactly one registered rule for every classifiable
    // failure and exactly one matching classification. Duplicates and order
    // dependence are rejected.
    var eligibleClasses: Set<String> = []
    var classifiedFailures = failures.filter { $0.severity != .classifiable }
    for var failure in failures where failure.severity == .classifiable {
      let matchingRules = registeredPredicateRules.filter {
        $0.covers(failureClass: failure.failureClass, subjectIdentity: failure.subjectIdentity)
      }
      guard matchingRules.count == 1,
        let registeredRule = matchingRules.first,
        observation.predicateRuleReferences?.contains(registeredRule.predicateRule) == true
      else {
        return block(
          .predicateRuleBindingUnstableOrMissing,
          failures: failures,
          markerValid: false
        )
      }

      let classifications = observation.predicateClassifications?.filter {
        $0.predicateRule == registeredRule.predicateRule
          && $0.failureClass == failure.failureClass
          && $0.subjectIdentity == failure.subjectIdentity
      } ?? []
      guard classifications.count == 1, let classification = classifications.first else {
        return block(
          .predicateRuleClassificationRequired,
          failures: failures,
          markerValid: false
        )
      }

      failure = SRSVALFailure(
        rule: failure.rule,
        reason: failure.reason,
        severity: failure.severity,
        failureClass: failure.failureClass,
        predicateRule: registeredRule.predicateRule,
        classification: classification.classification,
        subjectIdentity: failure.subjectIdentity
      )
      if classification.classification == .recomputeEligible {
        eligibleClasses.insert(failure.failureClass)
      }
      classifiedFailures.append(failure)
    }

    let resolvedFailures = classifiedFailures
    let nonEligibleFailure = resolvedFailures.first {
      $0.severity == .classifiable && $0.classification != .recomputeEligible
    }

    guard resolvedFailures.isEmpty == false else {
      return SRSVALDecisionOutcome(
        decision: .reuse,
        reason: nil,
        failures: [],
        authorizationUsed: nil,
        i14NotUsedMarkerValid: notUsedMarkerValid
      )
    }

    // DP-3 requires every surviving classifiable failure to be eligible. A
    // single non-eligible failure blocks even when another failure is eligible.
    guard nonEligibleFailure == nil else {
      return block(
        nonEligibleFailure?.reason ?? .predicateRuleClassificationRequired,
        failures: resolvedFailures,
        markerValid: notUsedMarkerValid
      )
    }

    let eligibleFailure = resolvedFailures.first { $0.classification == .recomputeEligible }
    let authorizationValid = authorization?.isValid(
      sourceRelationIdentity: settledRelationState.sourceRelationIdentity,
      resultIdentity: settledRelationState.resultIdentity,
      request: reuseRequest,
      observation: observation,
      identityRule: sourceRelation.identityRule,
      eligibleClasses: eligibleClasses
    ) == true
    guard let authorization, let eligibleFailure, authorizationValid else {
      return block(.recomputeAuthorizationInvalid, failures: resolvedFailures, markerValid: false)
    }

    return SRSVALDecisionOutcome(
      decision: .recompute,
      reason: eligibleFailure.reason,
      failures: resolvedFailures,
      authorizationUsed: authorization.binding,
      i14NotUsedMarkerValid: false
    )
  }

  private static func block(
    _ reason: SRSVALFailureReason,
    failures: [SRSVALFailure],
    markerValid: Bool
  ) -> SRSVALDecisionOutcome {
    SRSVALDecisionOutcome(
      decision: .block,
      reason: reason,
      failures: failures,
      authorizationUsed: nil,
      i14NotUsedMarkerValid: markerValid
    )
  }

  private static func requestApplicability(
    request: SRSVALReuseRequest,
    settledRelationState: SRSVALSettledRelationState
  ) -> SRSVALRequestApplicability {
    let exactlyScoped = request.binding?.isExact == true
      && request.relationIdentity == settledRelationState.sourceRelationIdentity
      && request.resultIdentity == settledRelationState.resultIdentity
    if request.declaredApplicability == .indeterminate || !exactlyScoped {
      return .indeterminate
    }
    return request.declaredApplicability
  }

  private static func validationFailures(
    settledRelationState: SRSVALSettledRelationState,
    sourceRelation: SRSVALSourceRelation,
    dependencies: SRSVALDependencySet?,
    result: SRSVALResult,
    provenance: SRSVALProvenanceLifecycle,
    lifecycle: SRSVALProvenanceLifecycle,
    freshness: SRSVALFreshness,
    policy: SRSVALResolutionPolicy,
    observedAtUTC: String
  ) -> [SRSVALFailure] {
    var failures: [SRSVALFailure] = []
    let sourceIdentity = sourceRelation.binding?.identity
    let resultIdentity = result.binding?.identity

    // G-V1, including closure to the actual source/result objects.
    if settledRelationState.binding?.isExact != true
      || settledRelationState.settlementID.isEmpty
      || settledRelationState.status != SRSVALLifecycleState.declaredSettled.rawValue
      || settledRelationState.sourceRelationIdentity.isEmpty
      || settledRelationState.resultIdentity.isEmpty
      || settledRelationState.sourceRelationIdentity == settledRelationState.resultIdentity
      || settledRelationState.sourceRelationIdentity != sourceIdentity
      || settledRelationState.resultIdentity != resultIdentity
      || settledRelationState.provenanceBindings?.isEmpty != false
      || settledRelationState.provenanceBindings?.allSatisfy({ $0.isExact }) != true
      || Set(settledRelationState.provenanceBindings ?? []) != Set(provenance.bindings ?? [])
      || (settledRelationState.requiresCanonicalIdentityRule
        && (settledRelationState.canonicalIdentityRule?.isExact != true
          || settledRelationState.canonicalIdentityRule != sourceRelation.identityRule))
    {
      failures.append(SRSVALFailure(
        rule: .srsDeclarationIntegrity,
        reason: .srsDeclarationIntegrity,
        severity: .hardBlock,
        failureClass: "SRS_DECLARATION_INTEGRITY"
      ))
    }

    // G-V2: an unresolved blocking invalidation is not reusable.
    if sourceRelation.binding?.isExact != true
      || sourceRelation.semanticBinding?.isExact != true
      || sourceRelation.applicabilityCoverage?.isExact != true
      || sourceRelation.invalidationRecord?.isExact != true
      || sourceRelation.invalidationStatus != .none
      || sourceRelation.identityRule?.isExact != true
      || sourceRelation.status != .current
    {
      failures.append(SRSVALFailure(
        rule: .sourceRelation,
        reason: .sourceRelation,
        severity: .hardBlock,
        failureClass: "SOURCE_RELATION"
      ))
    }

    // G-V3: exact binding, current status, required necessity, and resolved
    // semantic resolution are all mandatory.
    if dependencies?.boundary?.isExact != true
      || dependencies?.dependencies == nil
      || dependencies?.dependencies?.allSatisfy({
        $0.binding?.isExact == true
          && !$0.role.isEmpty
          && $0.necessity == "REQUIRED"
          && $0.resolution == .resolved
          && $0.status == .current
      }) != true
    {
      failures.append(SRSVALFailure(
        rule: .dependencies,
        reason: .dependencies,
        severity: .hardBlock,
        failureClass: "DEPENDENCY"
      ))
    }

    // G-V4: the result must be positively resolved without recomputation.
    if result.binding?.isExact != true
      || result.resolution != .resolvedWithoutRecompute
      || result.interpretabilityEvidence?.isExact != true
      || result.status != .current
    {
      failures.append(SRSVALFailure(
        rule: .result,
        reason: .result,
        severity: .hardBlock,
        failureClass: "RESULT"
      ))
    }

    // G-V5
    if policy.resolutionRule?.isExact != true
      || policy.policies?.isEmpty != false
      || policy.policies?.allSatisfy({ $0.isExact }) != true
      || policy.boundary?.isExact != true
    {
      failures.append(SRSVALFailure(
        rule: .resolutionPolicy,
        reason: .resolutionPolicy,
        severity: .hardBlock,
        failureClass: "RESOLUTION_OR_POLICY"
      ))
    }

    // G-V6
    if provenance.bindings?.isEmpty != false
      || provenance.bindings?.allSatisfy({ $0.isExact }) != true
      || provenance.boundary?.isExact != true
      || lifecycle.bindings?.isEmpty != false
      || lifecycle.bindings?.allSatisfy({ $0.isExact }) != true
      || lifecycle.boundary?.isExact != true
      || lifecycle.lifecycle != .declaredSettled
    {
      failures.append(SRSVALFailure(
        rule: .provenanceLifecycle,
        reason: .provenanceLifecycle,
        severity: .hardBlock,
        failureClass: "PROVENANCE_OR_LIFECYCLE"
      ))
    }

    // G-V7: current evidence must name the exact requirement and remain valid
    // at the observation time. Missing, mismatched, or expired evidence is a
    // classifiable freshness failure.
    if freshness.boundary?.isExact != true || freshness.requirements == nil {
      failures.append(SRSVALFailure(
        rule: .freshness,
        reason: .freshnessRecheckRequired,
        severity: .hardBlock,
        failureClass: "FRESHNESS"
      ))
    } else {
      for requirement in freshness.requirements ?? [] {
        let evidenceMatches = requirement.evidence?.isExact == true
          && requirement.evidence?.identity == "FRESHNESS_EVIDENCE:\(requirement.identity)"
          && requirement.evidence?.contentDigest == requirement.expectedEvidenceDigest
        let timeValid: Bool
        if let validUntil = utcTime(requirement.validUntilUTC),
          let observedAt = utcTime(requirement.observedAtUTC),
          requirement.observedAtUTC == observedAtUTC {
          timeValid = validUntil > observedAt
        } else {
          timeValid = false
        }
        if requirement.status != .current || !evidenceMatches || !timeValid {
          failures.append(SRSVALFailure(
            rule: .freshness,
            reason: .freshnessRecheckRequired,
            severity: .classifiable,
            failureClass: "FRESHNESS_RECHECK_REQUIRED",
            subjectIdentity: requirement.identity
          ))
        }
      }
    }

    return failures
  }

  private static func utcTime(_ value: String?) -> Date? {
    guard let value, !value.isEmpty else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
  }
}

extension SRSVALRecomputeAuthorization {
  fileprivate func isValid(
    sourceRelationIdentity: String,
    resultIdentity: String,
    request: SRSVALReuseRequest,
    observation: SRSVALObservation,
    identityRule: SRSVALBinding?,
    eligibleClasses: Set<String>
  ) -> Bool {
    let contentDigest = SHA256.hash(data: Data(canonicalContent.utf8))
      .map { String(format: "%02x", $0) }.joined()
    guard binding?.isExact == true,
      binding?.contentDigest == contentDigest,
      content == canonicalContent,
      self.sourceRelationIdentity == sourceRelationIdentity,
      invalidationClasses == eligibleClasses,
      !invalidationClasses.isEmpty,
      requestClass == request.requestClass,
      authorizedResultIdentity == resultIdentity,
      semanticClass == "EXACT_SEMANTIC_RECOMPUTE",
      let envelope,
      let covered = envelope.coveredFailureClasses,
      !covered.isEmpty,
      Set(covered) == eligibleClasses,
      envelope.targetBoundary == observation.boundary,
      envelope.relationIdentityRule == identityRule
    else { return false }
    return true
  }
}
