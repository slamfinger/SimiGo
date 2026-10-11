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
// Codable conformances allow canonical signed payloads to describe every
// decision-critical semantic input without exposing mutable trusted state.
extension SRSVALClassification: Codable {}
extension SRSVALRecordStatus: Codable {}
extension SRSVALSourceInvalidationStatus: Codable {}
extension SRSVALResolutionStatus: Codable {}
extension SRSVALResultResolution: Codable {}
extension SRSVALFreshnessStatus: Codable {}
extension SRSVALLifecycleState: Codable {}
extension SRSVALRequestApplicability: Codable {}
extension SRSVALBinding: Codable {}
extension SRSVALSettledRelationState: Codable {}
extension SRSVALSourceRelation: Codable {}
extension SRSVALDependency: Codable {}
extension SRSVALResult: Codable {}
extension SRSVALResolutionPolicy: Codable {}
extension SRSVALProvenanceLifecycle: Codable {}
extension SRSVALDependencySet: Codable {}
extension SRSVALFreshnessRequirement: Codable {}
extension SRSVALFreshness: Codable {}
extension SRSVALReuseRequest: Codable {}
extension SRSVALRecomputeEnvelope: Codable {}

public struct SRSVALPredicateClassification: Equatable, Hashable, Sendable, Codable {
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
public struct SRSVALAuthorizationPayload: Codable, Equatable, Sendable {
  public var schemaID = "SRSVAL-AUTHORIZATION-V1"
  public var sourceRelationIdentity: String
  public var invalidationClasses: Set<String>
  public var requestClass: String
  public var authorizedResultIdentity: String
  public var semanticClass: String
  public var coveredFailureClasses: Set<String>
  public var targetBoundary: SRSVALBinding
  public var relationIdentityRule: SRSVALBinding

  public init(
    sourceRelationIdentity: String,
    invalidationClasses: Set<String>,
    requestClass: String,
    authorizedResultIdentity: String,
    semanticClass: String,
    coveredFailureClasses: Set<String>,
    targetBoundary: SRSVALBinding,
    relationIdentityRule: SRSVALBinding
  ) {
    self.sourceRelationIdentity = sourceRelationIdentity
    self.invalidationClasses = invalidationClasses
    self.requestClass = requestClass
    self.authorizedResultIdentity = authorizedResultIdentity
    self.semanticClass = semanticClass
    self.coveredFailureClasses = coveredFailureClasses
    self.targetBoundary = targetBoundary
    self.relationIdentityRule = relationIdentityRule
  }
}

public struct SRSVALPredicateRulePayload: Codable, Equatable, Sendable {
  public var schemaID = "SRSVAL-PREDICATE-RULE-V1"
  public var registryAuthority: SRSVALBinding
  public var identity: String
  public var version: String
  public var failureClass: String
  public var subjectIdentities: Set<String>

  public init(
    registryAuthority: SRSVALBinding,
    identity: String,
    version: String,
    failureClass: String,
    subjectIdentities: Set<String>
  ) {
    self.registryAuthority = registryAuthority
    self.identity = identity
    self.version = version
    self.failureClass = failureClass
    self.subjectIdentities = subjectIdentities
  }

  func covers(failureClass: String, subjectIdentity: String) -> Bool {
    self.failureClass == failureClass && subjectIdentities.contains(subjectIdentity)
  }
}

public struct SRSVALClassificationPayload: Codable, Equatable, Sendable {
  public var schemaID = "SRSVAL-PREDICATE-CLASSIFICATION-V1"
  public var registryAuthority: SRSVALBinding
  public var predicateRule: SRSVALBinding
  public var identity: String
  public var version: String
  public var failureClass: String
  public var subjectIdentity: String
  public var classification: SRSVALClassification

  public init(
    registryAuthority: SRSVALBinding,
    predicateRule: SRSVALBinding,
    identity: String,
    version: String,
    failureClass: String,
    subjectIdentity: String,
    classification: SRSVALClassification
  ) {
    self.registryAuthority = registryAuthority
    self.predicateRule = predicateRule
    self.identity = identity
    self.version = version
    self.failureClass = failureClass
    self.subjectIdentity = subjectIdentity
    self.classification = classification
  }
}

public enum SRSVALTrustDomain: String, Sendable {
  case authorization
  case predicateRegistry
  case classification
  case observation
  case recordIntegrity
}

/// Fixed trust anchors for the pure Decision Core. Production values are the
/// public keys only; private keys live solely in authorized issuers.
public enum SRSVALTrustAnchor {
  public static let authorizationIssuer = Data(base64Encoded:
    "Qpl9qC7Q83V2mj99Myr18MZnqCJ8wHkypM+T6uHJTWc=")!
  public static let predicateRegistryIssuer = Data(base64Encoded:
    "ZCcptTZPdWSefBEfSczDtl4HtMWFjkveQUb8B14mxjY=")!
  public static let classificationIssuer = Data(base64Encoded:
    "woTfbA0/cLUoNngKsxyJY2tssCJe9Z2XEkCgXcdh8CU=")!
  public static let observationIssuer = Data(base64Encoded:
    "FAA9GyXmMzXNK78geA7ArorovYukhvjJoQIAN4zEge4=")!
  public static let recordIntegrityIssuer = Data(base64Encoded:
    "IKINQXMRR4HXf0PihchX0fwewFL2ZpXrZnXd33X/5Sk=")!

  static func domain(_ domain: SRSVALTrustDomain) -> Data {
    switch domain {
    case .authorization: return authorizationIssuer
    case .predicateRegistry: return predicateRegistryIssuer
    case .classification: return classificationIssuer
    case .observation: return observationIssuer
    case .recordIntegrity: return recordIntegrityIssuer
    }
  }
}

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

/// A canonical signed record. Verification is always against a fixed trust
/// anchor; a self-consistent unsigned object has no decision authority.
public struct SRSVALSignedRecord<Payload: Codable & Equatable & Sendable>: Equatable, Sendable {
  public let payload: Payload
  public let signature: Data
  public let signer: Data

  public init(payload: Payload, signature: Data, signer: Data) {
    self.payload = payload
    self.signature = signature
    self.signer = signer
  }

  public func verify(anchor: Data) -> Bool {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let canonical = try? encoder.encode(payload),
      let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: anchor)
    else { return false }
    return publicKey.isValidSignature(signature, for: canonical)
  }

  func verifiedPayload(anchor: Data) -> Payload? {
    verify(anchor: anchor) ? payload : nil
  }

  static func seal(payload: Payload, domain: SRSVALTrustDomain, issuer: SRSVALIssuer) throws -> Self {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let canonical = try encoder.encode(payload)
    let signature = try issuer.signingKey.signature(for: canonical)
    return Self(payload: payload, signature: signature, signer: issuer.publicKey)
  }
}

/// Issuer is the only object holding an authorization signing key. Decision
/// Core intentionally has no issuer initializer and consumes signed records.
public struct SRSVALIssuer {
  let signingKey: Curve25519.Signing.PrivateKey
  public let publicKey: Data

  public init(rawPrivateKey: Data) throws {
    self.signingKey = try Curve25519.Signing.PrivateKey(rawRepresentation: rawPrivateKey)
    self.publicKey = signingKey.publicKey.rawRepresentation
  }

  public func seal<Payload: Codable & Equatable & Sendable>(
    _ payload: Payload,
    domain: SRSVALTrustDomain
  ) throws -> SRSVALSignedRecord<Payload> {
    try SRSVALSignedRecord.seal(payload: payload, domain: domain, issuer: self)
  }
}

public struct SRSVALInputIntegrityPayload: Codable, Equatable, Sendable {
  public var schemaID = "SRSVAL-INPUT-INTEGRITY-V1"
  public var settledRelationState: SRSVALSettledRelationState
  public var sourceRelation: SRSVALSourceRelation
  public var dependencies: SRSVALDependencySet
  public var result: SRSVALResult
  public var provenance: SRSVALProvenanceLifecycle
  public var lifecycle: SRSVALProvenanceLifecycle
  public var freshness: SRSVALFreshness
  public var policy: SRSVALResolutionPolicy
  public var reuseRequest: SRSVALReuseRequest

  public init(
    settledRelationState: SRSVALSettledRelationState,
    sourceRelation: SRSVALSourceRelation,
    dependencies: SRSVALDependencySet,
    result: SRSVALResult,
    provenance: SRSVALProvenanceLifecycle,
    lifecycle: SRSVALProvenanceLifecycle,
    freshness: SRSVALFreshness,
    policy: SRSVALResolutionPolicy,
    reuseRequest: SRSVALReuseRequest
  ) {
    self.settledRelationState = settledRelationState
    self.sourceRelation = sourceRelation
    self.dependencies = dependencies
    self.result = result
    self.provenance = provenance
    self.lifecycle = lifecycle
    self.freshness = freshness
    self.policy = policy
    self.reuseRequest = reuseRequest
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

extension SRSVALObservation: Codable {}

public struct SRSVALObservationPayload: Codable, Equatable, Sendable {
  public var schemaID = "SRSVAL-OBSERVATION-V1"
  public var observation: SRSVALObservation
  public var classifications: [SRSVALPredicateClassification]

  public init(observation: SRSVALObservation, classifications: [SRSVALPredicateClassification]) {
    self.observation = observation
    self.classifications = classifications
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

  public static func authorizationBinding(_ record: SRSVALSignedRecord<SRSVALAuthorizationPayload>) -> SRSVALBinding {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let canonical = (try? encoder.encode(record.payload)) ?? Data()
    return SRSVALBinding(
      identity: "I-14",
      version: "AUTHORITY_SIGNED_V1",
      contentDigest: SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
    )
  }

  public static func predicateRuleBinding(_ record: SRSVALSignedRecord<SRSVALPredicateRulePayload>) -> SRSVALBinding {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let canonical = (try? encoder.encode(record.payload)) ?? Data()
    return SRSVALBinding(
      identity: "SRSVAL:PREDICATE_RULE:\(record.payload.identity)",
      version: record.payload.version,
      contentDigest: SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
    )
  }

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
    registeredPredicateRules: [SRSVALSignedRecord<SRSVALPredicateRulePayload>],
    classificationRecords: [SRSVALSignedRecord<SRSVALClassificationPayload>],
    authorization: SRSVALSignedRecord<SRSVALAuthorizationPayload>?,
    observation: SRSVALSignedRecord<SRSVALObservationPayload>,
    inputIntegrity: SRSVALSignedRecord<SRSVALInputIntegrityPayload>
  ) -> SRSVALDecisionOutcome {
    // DP-0 begins with authority-chain verification. None of these records can
    // be self-declared into validity.
    guard
      inputIntegrity.verify(anchor: SRSVALTrustAnchor.domain(.recordIntegrity)),
      inputIntegrity.payload.schemaID == "SRSVAL-INPUT-INTEGRITY-V1",
      inputIntegrity.payload == SRSVALInputIntegrityPayload(
        settledRelationState: settledRelationState,
        sourceRelation: sourceRelation,
        dependencies: dependencies ?? SRSVALDependencySet(boundary: nil, dependencies: nil),
        result: result,
        provenance: provenance,
        lifecycle: lifecycle,
        freshness: freshness,
        policy: policy,
        reuseRequest: reuseRequest
      ),
      observation.verify(anchor: SRSVALTrustAnchor.domain(.observation)),
      observation.payload.schemaID == "SRSVAL-OBSERVATION-V1",
      registeredPredicateRules.allSatisfy({
        $0.verify(anchor: SRSVALTrustAnchor.domain(.predicateRegistry)) && $0.payload.schemaID == "SRSVAL-PREDICATE-RULE-V1"
      }),
      Set(registeredPredicateRules.map({ $0.payload.identity })).count == registeredPredicateRules.count,
      classificationRecords.allSatisfy({
        $0.verify(anchor: SRSVALTrustAnchor.domain(.classification)) && $0.payload.schemaID == "SRSVAL-PREDICATE-CLASSIFICATION-V1"
      })
    else {
      return block(.validationInputStateInconsistent, failures: [], markerValid: false)
    }

    let observation = observation.payload.observation
    let providedPredicateRules = registeredPredicateRules.map { $0.payload }
    let ruleBindings = registeredPredicateRules.map { predicateRuleBinding($0) }
    let authorizationBinding = authorization.map { authorizationBinding($0) }

    // DP-0: exact observation boundary, I-15/I-16 references, and cross-object
    // identity closure. Signed payload equality is checked above.
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
      providedPredicateRules.allSatisfy({
        $0.registryAuthority == SRSVALPredicateRuleAuthority.required
      }),
      Set(ruleBindings).count == ruleBindings.count,
      observation.predicateRuleReferences == ruleBindings,
      observation.predicateClassifications?.count == classificationRecords.count
    else {
      return block(.validationInputStateInconsistent, failures: [], markerValid: false)
    }

    // I-16 integrity includes the exact authorized classification outcomes.
    let classificationPayloads = classificationRecords.map({ $0.payload })
    struct ClassificationSummary: Equatable {
      let rule: SRSVALBinding
      let failureClass: String
      let subject: String
      let classification: SRSVALClassification
    }
    let observationClassifications = observation.predicateClassifications?.map { classification in
      ClassificationSummary(
        rule: classification.predicateRule,
        failureClass: classification.failureClass,
        subject: classification.subjectIdentity,
        classification: classification.classification
      )
    }
    let authorizedClassifications = classificationPayloads.map { payload in
      ClassificationSummary(
        rule: payload.predicateRule,
        failureClass: payload.failureClass,
        subject: payload.subjectIdentity,
        classification: payload.classification
      )
    }
    guard observationClassifications == authorizedClassifications else {
      return block(.validationInputStateInconsistent, failures: [], markerValid: false)
    }

    let expectedI14 = authorizationBinding ?? i14NotUsedMarker
    guard observation.i14Reference?.isExact == true,
      observation.i14Reference == expectedI14
    else {
      return block(.validationInputStateInconsistent, failures: [], markerValid: false)
    }
    let notUsedMarkerValid =
      observation.i14Reference == i14NotUsedMarker
      && authorization == nil

    // Authorization authenticity is established by the fixed issuer anchor;
    // field matching below only checks that it governs this invocation.
    let authorizationPayload = authorization?.verifiedPayload(anchor: SRSVALTrustAnchor.domain(.authorization))
    if let payload = authorizationPayload {
      guard payload.sourceRelationIdentity == reuseRequest.relationIdentity,
        payload.requestClass == reuseRequest.requestClass,
        payload.authorizedResultIdentity == reuseRequest.resultIdentity,
        payload.semanticClass == "EXACT_SEMANTIC_RECOMPUTE",
        payload.targetBoundary == observation.boundary,
        payload.relationIdentityRule == sourceRelation.identityRule
      else {
        return block(.recomputeAuthorizationInvalid, failures: [], markerValid: false)
      }
    }

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

    // G-CLASS: every classifiable failure must match one authoritative rule
    // and exactly one authoritative classification.
    var eligibleClasses: Set<String> = []
    var classifiedFailures = failures.filter { $0.severity != .classifiable }
    for failure in failures where failure.severity == .classifiable {
      let matchingRules = providedPredicateRules.filter {
        $0.covers(failureClass: failure.failureClass, subjectIdentity: failure.subjectIdentity)
      }
      guard matchingRules.count == 1, let rulePayload = matchingRules.first else {
        return block(.predicateRuleBindingUnstableOrMissing, failures: failures, markerValid: false)
      }
      let ruleIndex = providedPredicateRules.firstIndex { $0 == rulePayload }!
      let matchingClassifications = classificationPayloads.filter {
        $0.predicateRule == ruleBindings[ruleIndex]
          && $0.registryAuthority == rulePayload.registryAuthority
          && $0.identity == rulePayload.identity
          && $0.version == rulePayload.version
          && $0.failureClass == failure.failureClass
          && $0.subjectIdentity == failure.subjectIdentity
      }
      guard matchingClassifications.count == 1,
        let classification = matchingClassifications.first
      else {
        return block(.predicateRuleClassificationRequired, failures: failures, markerValid: false)
      }

      let classifiedFailure = SRSVALFailure(
        rule: failure.rule,
        reason: failure.reason,
        severity: failure.severity,
        failureClass: failure.failureClass,
        predicateRule: ruleBindings[ruleIndex],
        classification: classification.classification,
        subjectIdentity: failure.subjectIdentity
      )
      if classification.classification == .recomputeEligible {
        eligibleClasses.insert(failure.failureClass)
      }
      classifiedFailures.append(classifiedFailure)
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

    // DP-3: one non-eligible failure blocks even if another is eligible.
    guard nonEligibleFailure == nil, let authorizationPayload,
      let eligibleFailure = resolvedFailures.first(where: { $0.classification == .recomputeEligible }),
      authorizationPayload.invalidationClasses == eligibleClasses,
      authorizationPayload.coveredFailureClasses == eligibleClasses,
      !eligibleClasses.isEmpty
    else {
      return block(
        nonEligibleFailure?.reason ?? .recomputeAuthorizationInvalid,
        failures: resolvedFailures,
        markerValid: notUsedMarkerValid
      )
    }

    return SRSVALDecisionOutcome(
      decision: .recompute,
      reason: eligibleFailure.reason,
      failures: resolvedFailures,
      authorizationUsed: authorizationBinding,
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
