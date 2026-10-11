# SRS-VAL-01 Decision Core implementation status

> **Status:** REVISION 5 CANDIDATE DELIVERED / PURE UNIT TESTS PASS /
> INDEPENDENT REVIEW REQUIRED
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
revision 2 independent review = REVISE / BLOCKING;
revision 3 independent review = REVISE / BLOCKING;
revision 4 independent review = REVISE / BLOCKING;
revision 5 non-generative result = PASS / 16 tests / 0 failures;
production trust anchors = ROTATED;
production signing private keys = ABSENT FROM REPOSITORY;
side effects = none;
MLX execution = none;
V6 rerun = none;
canonical PALACE mutation = none;
canonical Information Space mutation = none.
```

The core remains pure: no filesystem, database, process, network, model, or
persisted-state access.

Revision 5 closes the current review blockers and their validation defects:

```text
trust anchors = fresh production Ed25519 public-key anchors only;
signed-record binding = domain, canonical payload, and signer are covered by
  each Ed25519 signature;
canonical serialization = every signature payload uses deterministic
  SRSVAL-CANONICAL-TEXT-V1 encoding;
binding consistency = I-14 and predicate-rule bindings are derived from the
  same canonical payload that is signed;
authority chains = test issuers derive their public anchors from the test
  signing keys, not from placeholder hashes;
freshness fixtures = digest mismatch, expiry, and observation-time mismatch
  are exercised through the production evaluate entry point;
classification coverage = missing and contradictory outcomes fail closed
  without array-order dependence.
```

## Traceability matrix

| Frozen rule | Core behavior | Non-generative test |
| --- | --- | --- |
| DP-0 / I-16 | Signed inputs, exact references, object boundaries, ordering evidence, and authority payloads are validated before semantic decisions. | `testDP0DifferentObjectBoundaryFailsClosed`, `testCanonicalSerializationIsStableAcrossCodableRoundTrip` |
| Signed-record authority | Signatures are domain-separated and bind the canonical payload and signer; cross-domain or signer-substituted records fail. | `testCrossDomainSignedRecordFailsClosed` |
| Signed input integrity | A semantic input differing from its signed integrity record cannot enter validation. | `testSourceSemanticStateCannotBypassSignedIntegrity` |
| DP-1 / G-V1..G-V7 | Any hard-block failure outranks applicability and classification. | `testDP1LifecycleHardBlockOutranksEligibleFailure` |
| DP-2 / I-15 | Not-applicable and semantically unscoped requests fail closed. | `testDP2NotApplicableBlocks`, `testDP2UnscopedRequestBlocksIndeterminate` |
| DP-3 / I-14 + G-CLASS | All classifiable failures must be authoritative and eligible; a complete I-14 authorizes exact RECOMPUTE. | `testDP3AllEligibleFailuresWithAuthoritativeI14AuthorizeRecompute`, `testInvalidI14CannotProducePureReuse` |
| DP-3 mixed failures | One non-eligible failure blocks even when another is eligible. | `testDP3MixedEligibleAndNonEligibleFailuresBlock` |
| DP-4 / pure reuse | A fully verified authority chain with no remaining failure resolves REUSE. | `testDP4VerifiedAuthorityChainResolvesPureReuse` |
| G-CLASS | Missing classification fails closed; contradictory outcomes fail without order dependence. | `testGClassMissingClassificationFailsClosed`, `testContradictoryClassificationsFailClosedWithoutOrderDependence` |
| Freshness precision | Evidence digest, validity deadline, and requirement-to-I-16 observation time must match. | `testFreshnessDigestMismatchFailsClosed`, `testExpiredFreshnessFailsClosed`, `testFreshnessObservationTimeMismatchFailsClosed` |
| I-14 | Eligible failures require an exact authoritative authorization; invalid or absent I-14 never becomes REUSE. | `testDP3AllEligibleFailuresWithAuthoritativeI14AuthorizeRecompute`, `testInvalidI14CannotProducePureReuse` |
| I-15 / I-16 canonical coding | Codable round trips preserve canonical signature input and semantic equality. | `testCanonicalSerializationIsStableAcrossCodableRoundTrip` |

## Remaining boundaries

```text
persistent SRS representation = NOT IMPLEMENTED;
independent ES2 consumption = NOT IMPLEMENTED;
non-recompute attribution = NOT IMPLEMENTED;
production proof = NOT ESTABLISHED;
this decision core = NOT YET INDEPENDENTLY REVIEWED.
```
