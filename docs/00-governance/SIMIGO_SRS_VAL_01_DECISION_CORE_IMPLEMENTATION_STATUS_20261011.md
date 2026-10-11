# SRS-VAL-01 Decision Core implementation status

> **Status:** REVISION 2 IMPLEMENTATION DELIVERED / PURE UNIT TESTS PASS /
> REVIEW REQUIRED
> **Date:** 2026-10-11
> **Normative baseline:** SRS-VAL-01 Design v0.8, including inherited v0.7 predicates
> **Implementation authorization:** `SIMIGO_SRS_VAL_01_DECISION_CORE_IMPLEMENTATION_AUTHORIZATION_20261011.md`

## Scope completed

```text
implementation =
  simigo2-experimental/Sources/SimiGo2Experimental/SRSVALDecisionCore.swift;
tests =
  simigo2-experimental/Tests/SimiGo2ExperimentalTests/SRSVALDecisionCoreTests.swift;
revision 1 independent review = REVISE / BLOCKING;
revision 2 result = PASS / 17 tests / 0 failures;
side effects = none;
MLX execution = none;
V6 rerun = none;
canonical PALACE mutation = none;
canonical Information Space mutation = none.
```

The core is pure: no filesystem access, database access, process launch,
network access, model execution, or persisted state.

Revision 2 closes the blocking findings from review of revision 1
(`eaaea5bd6176afbd7fc68cb5ab01573eb41b1613`):

```text
mixed eligible/non-eligible failures = BLOCK, never RECOMPUTE;
predicate rules = externally registered exact content bindings with explicit
  failure-class and subject coverage;
I-16 = cross-object evidence references closed to actual semantic inputs;
I-14 = invalidation classes, target boundary, relation identity rule, covered
  classes, semantic class, and immutable content all matched;
G-V2/G-V3/G-V4/G-V7 = blocking invalidation, resolved dependency/result state,
  and current evidence identity/time are enforced;
contradictory classifications = fail closed without array-order dependence.
```

## Traceability matrix

| Frozen rule | Core behavior | Non-generative test |
| --- | --- | --- |
| DP-0 / I-16 | Missing, malformed, cross-boundary, or mismatched observation and I-15/I-16 references fail closed. | `testDP0MissingObservationFieldFailsClosed`, `testCrossBoundaryI15ReferenceIsDP0Blocked` |
| DP-1 / G-V1..G-V7 hard blockers | Any hard-block failure precedes applicability and classification. | `testDP1LifecycleHardBlockOutranksEligibleFailure` |
| DP-2 / I-15 applicability | `NOT_APPLICABLE`, malformed scope, and indeterminate current request block. | `testDP2NotApplicableBlocks`, `testDP2UnscopedRequestBlocksIndeterminate` |
| DP-3 / I-14 + G-CLASS | Only surviving failures classified eligible by an exact referenced predicate rule, fully covered by a valid exact I-14 and semantic envelope, resolve RECOMPUTE. | `testEligibleFailureWithExactRuleAndI14AuthorizesRecompute`, `testEligibleFailureWithoutI14FailsClosed`, `testOverbroadI14FailsClosed`, `testInvalidRecomputeEnvelopeFailsClosed` |
| DP-3 mixed failures | One non-eligible failure blocks even when another failure is eligible. | `testMixedEligibleAndNonEligibleFailuresBlock` |
| DP-4 / G-V1..G-V7 | No remaining failure resolves pure REUSE with the exact not-used marker. | `testGVAllChecksPassMapsToDP4PureReuse` |
| G-CLASS | A surviving failure with no referenced rule fails closed; a referenced rule with no matching classification cannot create a no-recompute path. | `testMissingPredicateRuleBindingFailsClosed`, `testSurvivingFailureWithoutMatchingClassificationFailsClosed` |
| Registered rule authority | Rules must have content-integrity evidence, explicit failure class, and subject coverage; core never manufactures an authoritative rule. | `testUnregisteredPredicateRuleFailsClosed`, `testRegisteredRuleWithoutSubjectCoverageFailsClosed` |
| Cross-object closure | SRS relation/result identities, provenance sets, I-16 evidence, boundary, freshness evidence identity/digest/time, and dependency/result states are semantically checked. | `testSRSRelationIdentityMismatchBlocks`, `testSRSResultIdentityMismatchBlocks`, `testSemanticallyInvalidObservationReferenceBlocks`, `testFreshnessEvidenceForDifferentRequirementPreventsPureReuse`, `testExpiredFreshnessEvidenceCannotReuseWithoutAuthorization` |
| I-14 exact scope | Invalidation classes, target boundary, canonical relation identity rule, covered classes, semantic class, request/result scope, and immutable content are matched. | `testI14InvalidationClassMismatchBlocks`, `testI14TargetBoundaryMismatchBlocks`, `testI14RelationIdentityRuleMismatchBlocks` |
| Classification determinism | Contradictory or duplicate classifications fail closed without array-order dependence. | `testContradictoryClassificationsFailClosedWithoutOrderDependence` |
| I-14 | Not-used is valid only with no surviving failure or a lawful higher-precedence resolution. Eligible failures require exact immutable authorization and valid envelope. | REUSE, missing-I-14, overbroad-I-14, and invalid-envelope tests |
| I-15 | Exact semantic request binding is mandatory and must match the observation and SRS scope. | DP-2 tests and cross-boundary test |
| G-V1..G-V7 | Core checks exact declaration, source relation, dependencies, result, resolution/policy, provenance/lifecycle, and freshness inputs; missing evidence never passes. | Reuse baseline plus hard-block and freshness failure paths |

## Remaining boundaries

```text
persistent SRS representation = NOT IMPLEMENTED;
independent ES2 consumption = NOT IMPLEMENTED;
non-recompute attribution = NOT IMPLEMENTED;
production proof = NOT ESTABLISHED;
this decision core = NOT YET INDEPENDENTLY REVIEWED.
```
