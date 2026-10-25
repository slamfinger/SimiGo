// srsval_adapter.swift — thin fixture adapter for T-IMPL-01.
//
// Reads a canonical-JSON closed invocation value graph (schema documented in
// BUILD.md), constructs the SettledRelationValidationCore types, evaluates,
// and writes the decision output as canonical JSON on stdout.
//
// The Decision Core itself is the canonical implementation artifact; this
// adapter adds only transport (JSON <-> types). No repository change; built
// per BUILD.md against the exact canonical source bindings.

import Foundation
// NOTE: no module import — the three canonical T-IMPL-01 sources are compiled
// in the SAME compilation unit as this adapter (see BUILD.md), so their types
// are directly visible. This keeps the adapter bound to the exact canonical
// artifact sources instead of any built module product.

// MARK: - JSON helpers

struct J {
    static func dict(_ v: Any?) -> [String: Any]? { v as? [String: Any] }
    static func arr(_ v: Any?) -> [Any]? { v as? [Any] }
    static func sub(_ d: [String: Any]?, _ k: String) -> [String: Any]? { d?[k] as? [String: Any] }
    static func str(_ d: [String: Any]?, _ k: String) -> String { d?[k] as? String ?? "" }
    static func bool(_ d: [String: Any]?, _ k: String) -> Bool { d?[k] as? Bool ?? false }
}

func decodeExact(_ v: Any?) -> SRSVALExactBinding? {
    guard let d = J.dict(v), d["state"] as? String == "exact" else { return nil }
    return SRSVALExactBinding(identity: J.str(d, "identity"),
                              version: J.str(d, "version"),
                              contentAddress: J.str(d, "contentAddress"),
                              integrityBinding: J.str(d, "integrityBinding"))
}

func decodeBindingState<B>(_ v: Any?, _ make: (SRSVALExactBinding) -> B) -> SRSVALBindingState<B> {
    guard let d = J.dict(v) else { return .missing }
    switch d["state"] as? String {
    case "exact":
        if let b = decodeExact(v) { return .exact(make(b)) }
        return .integrityInvalid(reason: "exact state with empty fields")
    case "missing": return .missing
    case "ambiguous": return .ambiguous(reason: J.str(d, "reason"))
    case "unstable": return .unstable(reason: J.str(d, "reason"))
    case "integrityInvalid": return .integrityInvalid(reason: J.str(d, "reason"))
    default: return .missing
    }
}

func decodeBoundary(_ d: [String: Any]) -> SRSVALObservationBoundary {
    SRSVALObservationBoundary(
        boundaryIdentity: J.str(d, "boundaryIdentity"),
        closeBoundary: J.str(d, "closeBoundary"),
        orderingEvidenceReference: J.str(d, "orderingEvidenceReference"),
        orderingEvidenceIntegrity: J.str(d, "orderingEvidenceIntegrity"),
        consistencyDeclaration: SRSVALConsistencyDeclaration(
            rawValue: J.str(d, "consistencyDeclaration")) ?? .inconsistent)
}

func decodeSRS(_ d: [String: Any]) -> SRSVALSRSEvidence {
    let birthRaw = J.str(d, "birthStatus")
    let birth: SRSVALBirthStatus = birthRaw == "declaredSettled"
        ? .declaredSettled : .other(birthRaw)
    return SRSVALSRSEvidence(
        boundaryIdentity: J.str(d, "boundaryIdentity"),
        settlementIdentity: J.str(d, "settlementIdentity"),
        birthStatus: birth,
        sourceRelationBinding: J.str(d, "sourceRelationBinding"),
        canonicalIdentityRuleApplicable: J.bool(d, "canonicalIdentityRuleApplicable"),
        canonicalIdentityRule: decodeBindingState(d["canonicalIdentityRule"]) { $0 },
        resultIdentity: J.str(d, "resultIdentity"),
        provenanceBindings: (J.arr(d["provenanceBindings"]) as? [String]) ?? [])
}

func decodeSourceRelation(_ d: [String: Any]) -> SRSVALSourceRelationEvidence {
    var records: [SRSVALInvalidationRecord] = []
    for raw in J.arr(d["invalidationRecords"]) ?? [] {
        guard let r = J.dict(raw) else { continue }
        let handling: SRSVALInvalidationHandling
        switch J.str(r, "handling") {
        case "hardBlockViolation": handling = .hardBlockViolation
        case "lawfullyResolved":
            handling = .lawfullyResolved(evidenceReference: J.str(r, "evidenceReference"))
        default:
            handling = .declaredClassifiableFailure(failureID: J.str(r, "failureID"))
        }
        records.append(SRSVALInvalidationRecord(recordID: J.str(r, "recordID"),
                                                invalidationClass: J.str(r, "invalidationClass"),
                                                handling: handling))
    }
    return SRSVALSourceRelationEvidence(
        boundaryIdentity: J.str(d, "boundaryIdentity"),
        sourceIdentity: decodeBindingState(d["sourceIdentity"]) { $0 },
        semanticsIdentity: decodeBindingState(d["semanticsIdentity"]) { $0 },
        applicabilityCoverage: J.str(d, "applicabilityCoverage"),
        invalidationRecords: records)
}

func decodeDependencies(_ arr: [Any]?) -> [SRSVALDependencyEvidence] {
    var out: [SRSVALDependencyEvidence] = []
    for raw in arr ?? [] {
        guard let d = J.dict(raw) else { continue }
        out.append(SRSVALDependencyEvidence(
            boundaryIdentity: J.str(d, "boundaryIdentity"),
            dependencyIdentity: J.str(d, "dependencyIdentity"),
            revisionBinding: decodeBindingState(d["revisionBinding"]) { $0 },
            resolved: J.bool(d, "resolved"),
            integrityReference: J.str(d, "integrityReference"),
            role: J.str(d, "role"),
            necessity: J.str(d, "necessity"),
            blockingSupersession: J.bool(d, "blockingSupersession"),
            blockingInvalidation: J.bool(d, "blockingInvalidation")))
    }
    return out
}

func decodeResult(_ d: [String: Any]) -> SRSVALResultEvidence {
    SRSVALResultEvidence(
        boundaryIdentity: J.str(d, "boundaryIdentity"),
        resultIdentity: J.str(d, "resultIdentity"),
        resultRevision: J.str(d, "resultRevision"),
        resolvedWithoutRecomputation: J.bool(d, "resolvedWithoutRecomputation"),
        integrityReference: J.str(d, "integrityReference"),
        interpretable: J.bool(d, "interpretable"),
        superseded: J.bool(d, "superseded"),
        invalidated: J.bool(d, "invalidated"))
}

func decodeInvocation(_ data: Data) throws -> SRSVALInvocation {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let boundary = J.dict(root["boundary"]),
          let srs = J.dict(root["srs"]),
          let sourceRelation = J.dict(root["sourceRelation"]),
          let result = J.dict(root["result"]),
          let resolution = J.dict(root["resolution"]),
          let policy = J.dict(root["policy"]),
          let provenance = J.dict(root["provenance"]),
          let lifecycle = J.dict(root["lifecycle"]) else {
        throw NSError(domain: "srsval-adapter", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "malformed invocation graph"])
    }
    var freshness: [SRSVALFreshnessRequirement] = []
    for raw in J.arr(root["freshnessRequirements"]) ?? [] {
        guard let f = J.dict(raw), let st = J.dict(f["state"]) else { continue }
        let state: SRSVALFreshnessState
        switch st["state"] as? String {
        case "cleared": state = .cleared(evidenceReference: J.str(st, "evidenceReference"))
        case "recheckRequired": state = .recheckRequired
        default: state = .evidenceMissing
        }
        freshness.append(SRSVALFreshnessRequirement(
            requirementID: J.str(f, "requirementId"),
            boundaryIdentity: J.str(f, "boundaryIdentity"),
            state: state))
    }
    var declared: [SRSVALDeclaredFailure] = []
    for raw in J.arr(root["declaredSurvivingFailures"]) ?? [] {
        guard let f = J.dict(raw) else { continue }
        declared.append(SRSVALDeclaredFailure(failureID: J.str(f, "failureID"),
                                              failureClass: J.str(f, "failureClass"),
                                              evidenceReference: J.str(f, "evidenceReference")))
    }
    // I-14
    let governing: SRSVALI14Reference
    if let g = J.dict(root["governingAuthorization"]), g["kind"] as? String == "active" {
        let bd = J.sub(g, "binding") ?? [:]
        switch bd["state"] as? String {
        case "exact":
            if let b = decodeExact(bd),
               let canonicalRule = decodeExact(bd["canonicalRelationIdentityRule"]) {
                governing = .active(.exact(SRSVALI14Binding(
                    governingSemanticIdentity: b.identity,
                    exactVersion: b.version,
                    contentIntegrityEvidence: b.integrityBinding,
                    sourceRelationScope: J.str(bd, "sourceRelationScope"),
                    coveredInvalidationClasses: (J.arr(bd["coveredInvalidationClasses"]) as? [String]) ?? [],
                    requestClass: J.str(bd, "requestClass"),
                    authorizedResultOutcome: (J.str(bd, "authorizedResultOutcome") == "reuse")
                        ? .reuse : .recompute,
                    recomputationSemanticClass: J.str(bd, "recomputationSemanticClass"),
                    resultTargetDerivationBoundary: J.str(bd, "resultTargetDerivationBoundary"),
                    canonicalRelationIdentityRule: canonicalRule)))
            } else {
                governing = .active(.integrityInvalid(reason: "exact state with missing required fields"))
            }
        case "ambiguous": governing = .active(.ambiguous(reason: J.str(bd, "reason")))
        case "unstable": governing = .active(.unstable(reason: J.str(bd, "reason")))
        case "integrityInvalid": governing = .active(.integrityInvalid(reason: J.str(bd, "reason")))
        default: governing = .active(.missing)
        }
    } else {
        governing = .notUsedNoRecomputePath
    }
    // Predicate rule
    let rule: SRSVALPredicateRuleReference
    if let pr = J.dict(root["predicateRule"]), pr["kind"] as? String == "registered" {
        let ad = J.sub(pr, "artifact") ?? [:]
        switch ad["state"] as? String {
        case "exact":
            if let b = decodeExact(ad) {
                var classifications: [SRSVALPredicateRuleClassification] = []
                for raw in J.arr(ad["classifications"]) ?? [] {
                    guard let c = J.dict(raw) else { continue }
                    classifications.append(SRSVALPredicateRuleClassification(
                        failureClass: J.str(c, "failureClass"),
                        verdict: SRSVALClassificationVerdict(
                            rawValue: J.str(c, "verdict")) ?? .notRecomputeEligible))
                }
                rule = .registered(.exact(SRSVALPredicateRuleArtifact(
                    ruleIdentity: b.identity,
                    ruleVersion: b.version,
                    contentAddress: b.contentAddress,
                    integrityBinding: b.integrityBinding,
                    registrationAuthority: J.str(ad, "registrationAuthority"),
                    classifications: classifications)))
            } else {
                rule = .registered(.integrityInvalid(reason: "exact state with missing fields"))
            }
        case "ambiguous": rule = .registered(.ambiguous(reason: J.str(ad, "reason")))
        case "unstable": rule = .registered(.unstable(reason: J.str(ad, "reason")))
        case "integrityInvalid": rule = .registered(.integrityInvalid(reason: J.str(ad, "reason")))
        default: rule = .registered(.missing)
        }
    } else {
        rule = .notUsed
    }
    return SRSVALInvocation(
        boundary: decodeBoundary(boundary),
        srs: decodeSRS(srs),
        sourceRelation: decodeSourceRelation(sourceRelation),
        dependencies: decodeDependencies(J.arr(root["dependencies"])),
        result: decodeResult(result),
        resolution: SRSVALResolutionEvidence(
            boundaryIdentity: J.str(resolution, "boundaryIdentity"),
            ruleBinding: decodeBindingState(resolution["ruleBinding"]) { $0 }),
        policy: SRSVALPolicyEvidence(
            boundaryIdentity: J.str(policy, "boundaryIdentity"),
            applicablePolicyVersions: (J.arr(policy["applicablePolicyVersions"]) ?? [])
                .compactMap { decodeExact($0) }),
        provenance: SRSVALProvenanceEvidence(
            boundaryIdentity: J.str(provenance, "boundaryIdentity"),
            productionEvidence: J.str(provenance, "productionEvidence"),
            declarationEvidence: J.str(provenance, "declarationEvidence"),
            dependencyEvidence: J.str(provenance, "dependencyEvidence"),
            resultEvidence: J.str(provenance, "resultEvidence"),
            orderingEvidence: J.str(provenance, "orderingEvidence")),
        lifecycle: SRSVALLifecycleEvidence(
            boundaryIdentity: J.str(lifecycle, "boundaryIdentity"),
            state: SRSVALLifecycleState(rawValue: J.str(lifecycle, "state")) ?? .indeterminate),
        freshnessRequirements: freshness,
        reuseRequest: decodeReuseRequest(root["reuseRequest"]),
        governingAuthorization: governing,
        predicateRule: rule,
        declaredSurvivingFailures: declared)
}


/// I-15 decode: the exact state carries the binding fields in `exactBinding`
/// (nested), per the BUILD.md contract — not at the top level.
func decodeReuseRequest(_ v: Any?) -> SRSVALBindingState<SRSVALReuseRequestBinding> {
    guard let rr = J.dict(v) else { return .missing }
    switch rr["state"] as? String {
    case "exact":
        if let b = decodeExact(rr["exactBinding"]) {
            return .exact(SRSVALReuseRequestBinding(
                requestIdentity: J.str(rr, "requestIdentity"),
                exactBinding: b,
                requestedSettlementIdentity: J.str(rr, "requestedSettlementIdentity"),
                requestClass: J.str(rr, "requestClass"),
                applicability: (J.str(rr, "applicability") == "notApplicable")
                    ? .notApplicable : .applicable))
        }
        return .integrityInvalid(reason: "exact state with missing exactBinding")
    case "ambiguous": return .ambiguous(reason: J.str(rr, "reason"))
    case "unstable": return .unstable(reason: J.str(rr, "reason"))
    case "integrityInvalid": return .integrityInvalid(reason: J.str(rr, "reason"))
    default: return .missing
    }
}

// MARK: - Output encoding (typed failures flattened to stable code strings)

func hardBlockCode(_ h: SRSVALHardBlock) -> String {
    switch h {
    case .srsSettlementIdentityMissing: return "HARD_BLOCK.srsSettlementIdentityMissing"
    case .srsBirthStatusNotDeclaredSettled: return "HARD_BLOCK.srsBirthStatusNotDeclaredSettled"
    case .srsSourceRelationBindingMissing: return "HARD_BLOCK.srsSourceRelationBindingMissing"
    case .srsCanonicalIdentityRuleRequiredButNotExact: return "HARD_BLOCK.srsCanonicalIdentityRuleRequiredButNotExact"
    case .srsResultIdentityNotDistinct: return "HARD_BLOCK.srsResultIdentityNotDistinct"
    case .srsProvenanceBindingsMissing: return "HARD_BLOCK.srsProvenanceBindingsMissing"
    case .sourceRelationIdentityNotExact: return "HARD_BLOCK.sourceRelationIdentityNotExact"
    case .sourceRelationSemanticsNotExact: return "HARD_BLOCK.sourceRelationSemanticsNotExact"
    case .sourceRelationApplicabilityCoverageMissing: return "HARD_BLOCK.sourceRelationApplicabilityCoverageMissing"
    case .sourceRelationInvalidationUnlawfullyHandled: return "HARD_BLOCK.sourceRelationInvalidationUnlawfullyHandled"
    case .dependencyRevisionBindingNotExact(let id): return "HARD_BLOCK.dependencyRevisionBindingNotExact(\(id))"
    case .dependencyUnresolved(let id): return "HARD_BLOCK.dependencyUnresolved(\(id))"
    case .dependencyIntegrityMissing(let id): return "HARD_BLOCK.dependencyIntegrityMissing(\(id))"
    case .dependencyRoleMissing(let id): return "HARD_BLOCK.dependencyRoleMissing(\(id))"
    case .dependencyNecessityMissing(let id): return "HARD_BLOCK.dependencyNecessityMissing(\(id))"
    case .dependencyBlockingSupersession(let id): return "HARD_BLOCK.dependencyBlockingSupersession(\(id))"
    case .dependencyBlockingInvalidation(let id): return "HARD_BLOCK.dependencyBlockingInvalidation(\(id))"
    case .resultIdentityOrRevisionMissing: return "HARD_BLOCK.resultIdentityOrRevisionMissing"
    case .resultResolvedWithRecomputation: return "HARD_BLOCK.resultResolvedWithRecomputation"
    case .resultIntegrityMissing: return "HARD_BLOCK.resultIntegrityMissing"
    case .resultNotInterpretable: return "HARD_BLOCK.resultNotInterpretable"
    case .resultSupersededOrInvalidated: return "HARD_BLOCK.resultSupersededOrInvalidated"
    case .resolutionRuleBindingNotExact: return "HARD_BLOCK.resolutionRuleBindingNotExact"
    case .policyVersionBindingsMissing: return "HARD_BLOCK.policyVersionBindingsMissing"
    case .provenanceEvidenceMissing(let c): return "HARD_BLOCK.provenanceEvidenceMissing(\(c))"
    case .lifecycleContested: return "HARD_BLOCK.lifecycleContested"
    case .lifecycleUnresolvedConflict: return "HARD_BLOCK.lifecycleUnresolvedConflict"
    case .lifecycleInvalidated: return "HARD_BLOCK.lifecycleInvalidated"
    case .lifecycleIndeterminate: return "HARD_BLOCK.lifecycleIndeterminate"
    case .freshnessEvidenceMissing(let r): return "HARD_BLOCK.freshnessEvidenceMissing(\(r))"
    case .freshnessRecheckRequired(let r): return "HARD_BLOCK.freshnessRecheckRequired(\(r))"
    }
}

func failureCodes(_ failures: [SRSVALFailure]) -> [String] {
    failures.map { failure in
        switch failure {
        case .inputStateInconsistent(let i): return "INPUT_STATE_INCONSISTENT.\(i.rawValue)"
        case .hardBlock(let h): return hardBlockCode(h)
        case .applicability(let a):
            let name: String
            switch a {
            case .i15Missing: name = "I15_MISSING"
            case .i15Ambiguous: name = "I15_AMBIGUOUS"
            case .i15Unstable: name = "I15_UNSTABLE"
            case .i15Unmatched: name = "I15_UNMATCHED"
            case .notApplicable: name = "NOT_APPLICABLE"
            }
            return "APPLICABILITY.\(name)"
        case .classification(let c):
            switch c {
            case .predicateRuleBindingUnstableOrMissing:
                return "CLASSIFICATION.PREDICATE_RULE_BINDING_UNSTABLE_OR_MISSING"
            case .predicateRuleClassificationRequired(let ids):
                return "CLASSIFICATION.PREDICATE_RULE_CLASSIFICATION_REQUIRED(\(ids.joined(separator: ",")))"
            }
        case .recomputeAuthorization(let r):
            switch r {
            case .i14MissingOrNotExact: return "RECOMPUTE_AUTH.I14_MISSING_OR_NOT_EXACT"
            case .i14DoesNotCoverEligibleClasses(let c):
                return "RECOMPUTE_AUTH.I14_DOES_NOT_COVER(\(c.joined(separator: ",")))"
            case .i14RequestClassMismatch(let e, let a):
                return "RECOMPUTE_AUTH.I14_REQUEST_CLASS_MISMATCH(\(e)/\(a))"
            case .i14OutcomeNotAuthorizedToRecompute: return "RECOMPUTE_AUTH.I14_OUTCOME_NOT_AUTHORIZED"
            case .recomputeEnvelopeIncomplete(let f):
                return "RECOMPUTE_AUTH.ENVELOPE_INCOMPLETE(\(f))"
            }
        }
    }
}

func encodeOutput(_ out: SRSVALDecisionOutput) -> String {
    let trace = out.derivationTrace.entries.map {
        ["step": $0.step, "rule": $0.rule, "outcome": $0.outcome] as [String: Any]
    }
    let verdicts = out.bindingVerdicts.map {
        ["binding": $0.binding, "verdict": $0.verdict] as [String: Any]
    }
    let object: [String: Any] = [
        "traceLabel": SRSVALDerivationTrace.traceLabel,
        "evidenceDisclaimer": SRSVALDerivationTrace.nonEvidenceDisclaimer,
        "primaryDecision": out.primaryDecision.rawValue,
        "decisionPath": out.decisionPath.rawValue,
        "i14MarkerValidity": out.i14MarkerValidity.rawValue,
        "typedFailures": failureCodes(out.typedFailures),
        "bindingVerdicts": verdicts,
        "derivationTrace": trace,
    ]
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(data: data, encoding: .utf8) ?? "{}"
}

// MARK: - Entry point

if CommandLine.arguments.count < 2 {
    FileHandle.standardError.write("usage: srsval_adapter INVOCATION_GRAPH.json\n".data(using: .utf8)!)
    exit(64)
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let data = try? Data(contentsOf: url) else {
    FileHandle.standardError.write("cannot read invocation graph\n".data(using: .utf8)!)
    exit(66)
}
do {
    let invocation = try decodeInvocation(data)
    let output = SRSVALEvaluator.evaluate(invocation)
    print(encodeOutput(output))
    exit(0)
} catch {
    FileHandle.standardError.write("decode error: \(error)\n".data(using: .utf8)!)
    exit(65)
}
