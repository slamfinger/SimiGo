# SRS-VAL-01 Decision Core implementation status

> **Status:** REVISION 10 CANDIDATE DELIVERED / PURE UNIT TESTS PASS /
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
revision 5 independent review = REVISE / BLOCKING;
revision 6 independent review = REVISE / BLOCKING;
revision 7 independent review = REVISE / BLOCKING;
revision 8 independent review = REVISE / BLOCKING;
revision 9 independent review = REVISE / BLOCKING;
revision 10 non-generative result = PASS / 24 tests / 0 failures;
production trust anchors = FIXED AT COMPILE TIME;
leaked Revision 4 keys = REVOKED / PERMANENTLY UNTRUSTED;
production signing private keys = ABSENT FROM REPOSITORY;
side effects = none;
MLX execution = none;
V6 rerun = none;
canonical PALACE mutation = none;
canonical Information Space mutation = none.
```

The core remains pure: no filesystem, database, process, network, model, or
persisted-state access.

Revisions 6 through 8 close the outstanding trust, canonical, presence, and ordering findings:

```text
trust-root injection = the public evaluate entry point has no anchors
  parameter and always uses compiled production anchors; anchor construction
  and the anchors-bearing evaluate path are internal test/harness scope;
canonical completeness = freshness expectedEvidenceDigest and complete
  identity/version/contentDigest fields are signed for all binding collections;
unambiguous encoding = SRSVAL-CANONICAL-TEXT-V4 uses nil/list markers,
  element counts, and byte-length-prefixed elements;
expected domain separation = record verification requires the declared domain
  to equal the object's expected domain in the production evaluate path;
revision 7 canonical model = ordered semantic records and unordered collections are separated;
canonical encoding = SRSVAL-CANONICAL-TEXT-V4;
optional collection presence = NIL and explicit empty LIST have distinct signed bytes;
unordered validation = rule-reference and classification-record comparison is order-independent and duplicate-count exact;
observation classification closure = the outer payload list, nested observation list, and signed classification records must agree as exact multisets;
input-integrity comparison = unordered collection fields are compared through normalized canonical semantics, while NIL and explicit-empty presence remain distinct;
binding fields = identity, version, and digest have fixed field roles;
freshness requirement = fixed-role ordered record embedded in an unordered requirement set;
classification tuple = fixed-role ordered record embedded in an unordered classification set;
field-role mutation = identity/version, I-14 relation-rule, freshness role, and classification role swaps change bytes and break signatures;
negative coverage = custom trust-root injection, all five wrong-domain
  signatures, expected-digest mutation, binding-field mutations, and
  separator-collision subject sets are rejected or produce different bytes;
```

## Traceability matrix

| Frozen rule | Core behavior | Non-generative test |
| --- | --- | --- |
| Fixed production trust root | Public `evaluate` cannot receive or override trust anchors; a custom-signed valid chain fails against compiled production anchors. | `testPublicEvaluateCannotInjectCustomTrustAnchors` |
| Signed-record expected domain | Wrong-domain records signed by the corresponding trusted issuer fail for authorization, registry, classification, observation, and integrity domains. | `testExpectedDomainSeparationFailsClosedForAllTrustDomains` |
| Signed-record integrity | Cross-domain records and signer substitution fail signature verification. | `testExpectedDomainSeparationFailsClosedForAllTrustDomains` |
| Signed input integrity | A semantic input differing from its signed integrity record cannot enter validation. | `testSourceSemanticStateCannotBypassSignedIntegrity` |
| Canonical field completeness | Expected freshness digest and full binding metadata mutate canonical bytes. | `testCanonicalBytesCoverDecisionFieldsWithoutAmbiguity` |
| Input-integrity collection semantics | Signed integrity comparison normalizes collection order; reversing covered unordered arrays preserves the decision, while actual content changes still fail closed. | `testInputIntegrityComparesUnorderedCollectionsSemantically`, `testInputIntegrityStillRejectsCollectionContentChange` |
| Optional collection presence | Freshness requirements, dependency sets, and observation classifications preserve NIL versus explicit-empty semantics at the signature layer; nil-to-empty mutations invalidate signatures. | `testOptionalCollectionPresenceIsSigned` |
| Unordered collections | Rule-reference and classification-record checks are order-independent while preserving duplicate counts against the signed observation. | `testUnorderedRuleAndClassificationInputsAcceptAnyOrder` |
| Observation classification closure | A trusted but internally contradictory signed Observation Payload cannot reach REUSE; outer payload, nested observation, and classification records must agree as exact multisets. | `testObservationPayloadClassificationRepresentationsMustAgree`, `testDP4VerifiedAuthorityChainResolvesPureReuse` |
| Ordered semantic records | Binding identity/version roles, I-14 relation-rule roles, freshness field roles, and classification field roles cannot swap without changing canonical bytes and invalidating the original signature. | `testOrderedRecordsPreserveFieldRolesInSignatures` |
| Unambiguous collections | Distinct subject-set semantics cannot collide through a separator. | `testCanonicalBytesCoverDecisionFieldsWithoutAmbiguity` |
| Canonical coding round trip | Codable round trips preserve semantic equality and canonical signature input. | `testCanonicalSerializationIsStableAcrossCodableRoundTrip` |
| DP-0 / I-16 | Exact references, object boundaries, ordering evidence, and signed authority payloads validate first. | `testDP0DifferentObjectBoundaryFailsClosed` |
| DP-1 / G-V1..G-V7 | Any hard-block failure outranks applicability and classification. | `testDP1LifecycleHardBlockOutranksEligibleFailure` |
| DP-2 / I-15 | Not-applicable and semantically unscoped requests fail closed. | `testDP2NotApplicableBlocks`, `testDP2UnscopedRequestBlocksIndeterminate` |
| DP-3 / I-14 + G-CLASS | All failures must be authoritative and eligible; complete I-14 authorizes exact RECOMPUTE. | `testDP3AllEligibleFailuresWithAuthoritativeI14AuthorizeRecompute`, `testInvalidI14CannotProducePureReuse` |
| DP-3 mixed failures | One non-eligible failure blocks even when another is eligible. | `testDP3MixedEligibleAndNonEligibleFailuresBlock` |
| DP-4 / pure reuse | A fully verified authority chain with no remaining failure resolves REUSE. | `testDP4VerifiedAuthorityChainResolvesPureReuse` |
| G-CLASS | Missing or contradictory classification fails closed without order dependence. | `testGClassMissingClassificationFailsClosed`, `testContradictoryClassificationsFailClosedWithoutOrderDependence` |
| Freshness precision | Evidence digest, validity deadline, and requirement-to-I-16 observation time must match. | `testFreshnessDigestMismatchFailsClosed`, `testExpiredFreshnessFailsClosed`, `testFreshnessObservationTimeMismatchFailsClosed` |

## Remaining boundaries

```text
persistent SRS representation = NOT IMPLEMENTED;
independent ES2 consumption = NOT IMPLEMENTED;
non-recompute attribution = NOT IMPLEMENTED;
production proof = NOT ESTABLISHED;
this decision core = NOT YET INDEPENDENTLY REVIEWED.
```
