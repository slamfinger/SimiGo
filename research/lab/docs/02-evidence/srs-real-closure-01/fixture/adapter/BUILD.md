# Adapter Build Specification — SRS-REAL-CLOSURE-01

The adapter is built ONLY in a temporary directory outside the repository.
The build script verifies the canonical source bindings BEFORE compiling.

## Canonical source bindings (from AUTH-REQ-01 Implementation Completion Record §2)

| File | Git blob | SHA256 |
|---|---|---|
| SRSVALInvocation.swift | `0fd65bdf40b7c9885de2ada491d66348ebfa28fa` | `6583a80444848a3b42b55ea82f9de6cc1350af6154f6f23c3c3ab61427226c75` |
| SRSVALDecision.swift | `cbd24721a97f3c06e012fb02649feb19c2b9cb8b` | `e219aeeadceb74a2d37cb20fdb76ee18d23ee739a743ecf6309e7384b58b15de` |
| SRSVALCore.swift | `9f11ef1af45be6bc9450e0fbdc0117211f99a74a` | `9725217063b9aa560752e8485dac64aae41a314c429f6b9aa1d8808a4860d56e` |

Sources are exported via `git show <commit>:<path>` from the canonical
implementation commit `07176ec` and their SHA256 verified before use.

## Build command (execution stage; run in a temp dir)

```bash
# 1. export + verify canonical sources (sha256 must match the table above)
git show 07176ec:trackD-memory/Sources/SettledRelationValidationCore/SRSVALInvocation.swift > SRSVALInvocation.swift
git show 07176ec:trackD-memory/Sources/SettledRelationValidationCore/SRSVALDecision.swift   > SRSVALDecision.swift
git show 07176ec:trackD-memory/Sources/SettledRelationValidationCore/SRSVALCore.swift       > SRSVALCore.swift
shasum -a 256 -c <<'EOF'
6583a80444848a3b42b55ea82f9de6cc1350af6154f6f23c3c3ab61427226c75  SRSVALInvocation.swift
e219aeeadceb74a2d37cb20fdb76ee18d23ee739a743ecf6309e7384b58b15de  SRSVALDecision.swift
9725217063b9aa560752e8485dac64aae41a314c429f6b9aa1d8808a4860d56e  SRSVALCore.swift
EOF

# 2. compile adapter + canonical sources into one binary
#    (swiftc requires top-level statements to live in a file named main.swift)
cp srsval_adapter.swift main.swift
swiftc -O \
  SRSVALInvocation.swift SRSVALDecision.swift SRSVALCore.swift \
  main.swift \
  -o srsval_adapter
```

## Invocation-graph JSON contract (adapter input)

Top-level object with exactly the fields of `SRSVALInvocation`:

```text
boundary:                { boundaryIdentity, closeBoundary, orderingEvidenceReference,
                           orderingEvidenceIntegrity, consistencyDeclaration }
srs:                     { boundaryIdentity, settlementIdentity,
                           birthStatus: "declaredSettled" | other-string,
                           sourceRelationBinding, canonicalIdentityRuleApplicable,
                           canonicalIdentityRule: <binding-state>,
                           resultIdentity, provenanceBindings: [string] }
sourceRelation:          { boundaryIdentity, sourceIdentity: <binding-state>,
                           semanticsIdentity: <binding-state>, applicabilityCoverage,
                           invalidationRecords: [{recordID, invalidationClass, handling:
                             "hardBlockViolation" | "lawfullyResolved"(evidenceReference)
                             | "declaredClassifiableFailure"(failureID)}] }
dependencies:            [{ boundaryIdentity, dependencyIdentity,
                           revisionBinding: <binding-state>, resolved, integrityReference,
                           role, necessity, blockingSupersession, blockingInvalidation }]
result:                  { boundaryIdentity, resultIdentity, resultRevision,
                           resolvedWithoutRecomputation, integrityReference,
                           interpretable, superseded, invalidated }
resolution:              { boundaryIdentity, ruleBinding: <binding-state> }
policy:                  { boundaryIdentity, applicablePolicyVersions: [<binding-state exact>] }
provenance:              { boundaryIdentity, productionEvidence, declarationEvidence,
                           dependencyEvidence, resultEvidence, orderingEvidence }
lifecycle:               { boundaryIdentity, state: determinate | contested |
                           unresolvedLifecycleConflict | invalidated | indeterminate }
freshnessRequirements:   [{ requirementId, boundaryIdentity,
                           state: {state:"cleared",evidenceReference} |
                                  {state:"recheckRequired"} | {state:"evidenceMissing"} }]
reuseRequest:            <binding-state of: { requestIdentity, exactBinding: <exact>,
                           requestedSettlementIdentity, requestClass, applicability }>
governingAuthorization:  { kind: "notUsedNoRecomputePath" }
                       | { kind: "active", binding: <binding-state of I-14 fields incl.
                           coveredInvalidationClasses, authorizedResultOutcome,
                           canonicalRelationIdentityRule> }
predicateRule:           { kind: "notUsed" }
                       | { kind: "registered", artifact: <binding-state of: rule fields,
                           registrationAuthority, classifications:
                           [{failureClass, verdict: RECOMPUTE_ELIGIBLE |
                             NOT_RECOMPUTE_ELIGIBLE}]> }
declaredSurvivingFailures: [{ failureID, failureClass, evidenceReference }]
```

`<binding-state>` = `{state:"exact", identity, version, contentAddress, integrityBinding}`
or `{state:"missing"}` / `{state:"ambiguous"|"unstable"|"integrityInvalid", reason}`.

## Adapter output (stdout, canonical JSON)

```text
{ traceLabel, evidenceDisclaimer, primaryDecision, decisionPath,
  i14MarkerValidity, typedFailures: [code-string], bindingVerdicts: [...],
  derivationTrace: [{step, rule, outcome}] }
```

Typed failures are flattened to stable dotted code strings (e.g.
`HARD_BLOCK.dependencyBlockingInvalidation(D-1)`); the mapping is exhaustive
over the core's failure enum.
