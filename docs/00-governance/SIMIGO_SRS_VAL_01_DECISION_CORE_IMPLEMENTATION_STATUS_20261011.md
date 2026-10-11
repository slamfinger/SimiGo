# SRS-VAL-01 Decision Core implementation status

> **Status:** IMPLEMENTATION DELIVERED / PURE UNIT TESTS PASS / REVIEW REQUIRED
> **Date:** 2026-10-11
> **Normative baseline:** SRS-VAL-01 Design v0.8, including inherited v0.7 predicates
> **Implementation authorization:** `SIMIGO_SRS_VAL_01_DECISION_CORE_IMPLEMENTATION_AUTHORIZATION_20261011.md`

## Scope completed

```text
implementation =
  simigo2-experimental/Sources/SimiGo2Experimental/SRSVALDecisionCore.swift;
tests =
  simigo2-experimental/Tests/SimiGo2ExperimentalTests/SRSVALDecisionCoreTests.swift;
result = PASS / 14 tests / 0 failures;
side effects = none;
MLX execution = none;
V6 rerun = none;
canonical PALACE mutation = none;
canonical Information Space mutation = none.
```

The core is pure: no filesystem access, database access, process launch,
network access, model execution, or persisted state.

## Traceability matrix

| Frozen rule | Core behavior | Non-generative test |
| --- | --- | --- |
| DP-0 / I-16 | Missing, malformed, cross-boundary, or mismatched observation and I-15/I-16 references fail closed. | `testDP0MissingObservationFieldFailsClosed`, `testCrossBoundaryI15ReferenceIsDP0Blocked` |
| DP-1 / G-V1..G-V7 hard blockers | Any hard-block failure precedes applicability and classification. | `testDP1LifecycleHardBlockOutranksEligibleFailure` |
| DP-2 / I-15 applicability | `NOT_APPLICABLE`, malformed scope, and indeterminate current request block. | `testDP2NotApplicableBlocks`, `testDP2UnscopedRequestBlocksIndeterminate` |
| DP-3 / I-14 + G-CLASS | Only surviving failures classified eligible by an exact referenced predicate rule, fully covered by a valid exact I-14 and semantic envelope, resolve RECOMPUTE. | `testEligibleFailureWithExactRuleAndI14AuthorizesRecompute`, `testEligibleFailureWithoutI14FailsClosed`, `testOverbroadI14FailsClosed`, `testInvalidRecomputeEnvelopeFailsClosed` |
| DP-4 / G-V1..G-V7 | No remaining failure resolves pure REUSE with the exact not-used marker. | `testGVAllChecksPassMapsToDP4PureReuse` |
| G-CLASS | A surviving failure with no referenced rule fails closed; a referenced rule with no matching classification cannot create a no-recompute path. | `testMissingPredicateRuleBindingFailsClosed`, `testSurvivingFailureWithoutMatchingClassificationFailsClosed` |
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
