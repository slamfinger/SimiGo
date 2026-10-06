# Settled Relation State Reuse Validation Predicate — SRS-VAL-01 Design v0.1

> **Status:** DESIGN V0.1 REVISE — SUPERSEDED BY V0.2 — IMPLEMENTATION / EXPERIMENT NOT AUTHORIZED
> **Date:** 2026-10-07
> **Frozen semantic basis:** SRS-SEM-01 Design v0.5 = ACCEPT / FROZEN
> **Commission:** Human accepted SRS-SEM-01 and commissioned SRS-VAL-01 design.
> **Purpose:** define the semantic reuse-validation predicate that maps a validated SRS and current binding state to `REUSE`, `BLOCK`, or `RECOMPUTE`.
> **Scope guard:** design only. No implementation, fixture, experiment, IS mutation, user-file mutation, RelationCore/InformationCore change, U-A change, or Frozen Contract change.
> **Review ruling:** REVISE; see `docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_DESIGN_V0.1_REVIEW_RULING_20261007.md`.
> **Superseded by:** `docs/02-evidence/es-is-20261005/SIMIGO_ES_IS_SRS_VAL_01_REUSE_VALIDATION_PREDICATE_DESIGN_V0.2_20261007.md`.

## 1. Research object

```text
Given a Settled Relation State produced by ES₁,
can an independent ES₂ lawfully validate and reuse it,
compute only genuinely new delta,
and correctly block or recompute when required state is invalid?
```

This design defines the validation predicate, not an implementation.

## 2. Predicate boundary

```text
SRS-SEM-01 answers:
  What is a stable Settled Relation State?

SRS-VAL-01 answers:
  Under current bindings and evidence, may ES₂ reuse it,
  block it, or recompute it?
```

The predicate is semantic and decision-level.

It does not define storage schema, query API, performance optimization, model
runtime, agent framework, MCP, remote API, or business-judgment policy.

## 3. Validation input contract

The predicate receives only lawfully bound semantic inputs:

```text
I-1  target SRS declaration;
I-2  exact SRS settlement identity;
I-3  exact source-relation instance binding;
I-4  canonical identity-generation rule binding, when applicable;
I-5  exact dependency set with dependency roles;
I-6  exact dependency revision/integrity bindings;
I-7  exact result target identity/revision binding;
I-8  exact resolution-rule identity/version binding;
I-9  exact policy/semantic version bindings;
I-10 immutable provenance evidence bindings;
I-11 immutable lifecycle evidence bindings;
I-12 current freshness requirement set;
I-13 current lawful freshness evidence, when available.
```

Forbidden inputs:

```text
semantic equivalence assumptions;
latest revision substitution;
mutable result slot;
latest resolution rule;
latest policy;
mutable evidence pointer;
agent memory;
conversation history;
business intent;
model confidence;
semantic similarity;
MCP / remote API data;
undocumented side channels.
```

## 4. Required validation groups

### 4.1 G-V1 — SRS declaration integrity

```text
V1.1  settlement_id is present and addressable.
V1.2  birth status is DECLARED_SETTLED.
V1.3  source relation instance binding is context-independent and immutable.
V1.4  canonical identity-generation rule binding is exact when applicable.
V1.5  result identity is distinct from settlement identity.
V1.6  provenance evidence bindings are immutable or exact.
```

### 4.2 G-V2 — source relation validation

```text
V2.1  source-relation instance identity still resolves exactly.
V2.2  relation semantics identity/version remains exact.
V2.3  source-relation applicability boundary still covers the current reuse
      request.
V2.4  no source-relation invalidation record blocks reuse.
```

### 4.3 G-V3 — dependency validation

For every required dependency:

```text
V3.1  binding_kind remains EXACT_REVISION.
V3.2  information_id resolves.
V3.3  revision_binding remains exact.
V3.4  integrity_binding verifies when required.
V3.5  dependency role remains applicable.
V3.6  dependency necessity is satisfied.
V3.7  no dependency supersession/invalidation blocks reuse.
```

Any failed required dependency invalidates reuse.

### 4.4 G-V4 — result validation

```text
V4.1  result binding kind is exact immutable result identity or exact immutable
      result revision.
V4.2  result target resolves without recomputation.
V4.3  result integrity verifies when required.
V4.4  result remains interpretable under relation semantics.
V4.5  result has not been superseded or invalidated.
```

### 4.5 G-V5 — resolution and policy version validation

```text
V5.1  resolution_rule_binding remains EXACT_RULE_VERSION.
V5.2  exact resolution rule identity/version resolves.
V5.3  resolution rule integrity verifies when required.
V5.4  policy bindings remain exact immutable policy versions.
V5.5  exact policy semantics still apply to this reuse request.
```

### 4.6 G-V6 — provenance and lifecycle validation

```text
V6.1  provenance evidence bindings are immutable, exact-revision, or immutable
      content addresses.
V6.2  producing ES, declaration, dependency, result, and ordering evidence are
      present.
V6.3  lifecycle evidence bindings satisfy the same immutable-binding rule.
V6.4  lifecycle status is determinate.
V6.5  lifecycle status is not CONTESTED.
V6.6  lifecycle status is not UNRESOLVED_LIFECYCLE_CONFLICT.
V6.7  lifecycle status is not INVALIDATED.
```

A superseded SRS may be referenced as history but is not directly reusable.

### 4.7 G-V7 — freshness validation

SRS supplies freshness requirements. Current lawful evidence is evaluated
against them.

```text
V7.1  every freshness requirement has applicable current evidence or a typed
      blocker.
V7.2  immutable evidence references satisfy the SRS freshness conditions.
V7.3  source-state freshness policy is satisfied where required.
V7.4  observation freshness policy is satisfied where required.
V7.5  policy freshness is satisfied where required.
V7.6  FRESHNESS_RECHECK_REQUIRED has not been cleared by lawful evidence.
```

Freshness failure produces `BLOCK_FRESHNESS_INVALID`, never a semantic guess.

## 5. Decision semantics

The predicate returns exactly one primary decision:

```text
REUSE
BLOCK
RECOMPUTE
```

`INDETERMINATE` is not a fourth reusable outcome. It is represented as `BLOCK`
with a typed reason.

### 5.1 REUSE

`REUSE` requires all:

```text
G-V1 through G-V7 PASS;
current request remains within source-relation applicability;
all required dependencies remain exact and fresh;
result resolves without recomputation;
lifecycle status is determinate and reusable;
provenance evidence is stable;
no supersession/invalidation blocker exists.
```

REUSE means:

```text
ES₂ may consume the settled relation and compute only genuinely new delta.
```

### 5.2 BLOCK

`BLOCK` is required when:

```text
required evidence is missing or unstable;
lifecycle status is CONTESTED or unresolved;
SRS is invalidated;
dependency identity/revision/integrity fails;
result target is unstable or missing;
resolution-rule or policy version is unstable/missing;
freshness requirements fail or lack evidence;
current request exceeds source-relation applicability;
or any required semantic binding cannot be validated.
```

BLOCK means:

```text
ES₂ must not consume the SRS as fresh settled state.
```

### 5.3 RECOMPUTE

`RECOMPUTE` is a typed consequence, not a cache miss side effect.

It is required when:

```text
a required dependency has changed and the SRS itself authorizes recompute under
the source-relation applicability boundary;
or the exact source relation can be lawfully recomputed from current inputs;
or the governing semantic contract explicitly maps this invalidation class to
recomputation.
```

RECOMPUTE means:

```text
ES₂ must not consume stale SRS as reusable.
ES₂ may create a new settlement only under a separately authorized ES→IS
settlement contract.
```

## 6. Non-recomputation boundary

If the predicate returns `REUSE`, then:

```text
the settled relation must not be recomputed;
the result must be obtained from the exact immutable result binding;
validation may read bindings/evidence but must not regenerate the settled work;
only genuinely new delta computation may occur.
```

For evaluation, this must be observable through:

```text
execution-op trace;
absence/presence of settled-relation computation op;
input/output evidence path;
or another pre-registered independent measurement.
```

## 7. Validation evidence output

Every validation result must record:

```text
decision: REUSE / BLOCK / RECOMPUTE;
SRS settlement identity;
source-relation instance binding;
dependency check matrix;
result target check;
resolution-rule and policy version check;
provenance/lifecycle evidence checks;
freshness check matrix;
typed failure reasons;
independence declaration;
non-recomputation evidence class;
timestamp/ordering evidence;
validation input integrity hashes.
```

No validation output may claim universal SRS reuse or production readiness.

## 8. Failure taxonomy

```text
FT-V01  missing settlement identity
FT-V02  invalid birth/lifecycle status
FT-V03  unresolved lifecycle conflict
FT-V04  CONTESTED SRS
FT-V05  superseded SRS used as directly reusable
FT-V06  invalidated SRS used as reusable
FT-V07  source-relation identity unstable or missing
FT-V08  source-relation semantics version changed
FT-V09  dependency information missing
FT-V10  dependency revision mismatch
FT-V11  dependency integrity failure
FT-V12  dependency role/necessity unsatisfied
FT-V13  result target unstable or missing
FT-V14  result integrity failure
FT-V15  result semantic mismatch
FT-V16  resolution-rule identity/version unstable or missing
FT-V17  policy identity/version unstable or missing
FT-V18  provenance evidence unstable or missing
FT-V19  lifecycle evidence unstable or missing
FT-V20  freshness requirement failed
FT-V21  freshness evidence missing
FT-V22  current request outside applicability boundary
FT-V23  hidden side-channel or non-independent ES path
FT-P24  recomputation used while predicate returned REUSE
FT-P25  validation output cannot support audit
```

## 9. Independence requirements

`ES₂` must be independent of `ES₁` at the semantic and execution boundary.

Allowed shared surface:

```text
lawful Information Space / SRS evidence.
```

Forbidden shared state:

```text
runtime process;
model memory;
agent notes;
conversation history;
private model state;
implementation singleton;
hidden cache;
undocumented side channel.
```

This separation is required to distinguish SRS reuse from ordinary cache hit.

## 10. Positive and negative validation scenarios

### 10.1 Positive scenarios

```text
PV-1  all exact bindings stable → REUSE.
PV-2  all provenance/lifecycle evidence immutable → REUSE.
PV-3  freshness requirements satisfied → REUSE.
PV-4  result target resolves without recomputation → REUSE.
```

### 10.2 Negative scenarios

```text
NV-1  dependency revision changes → BLOCK or RECOMPUTE.
NV-2  dependency integrity fails → BLOCK or RECOMPUTE.
NV-3  result target changes → BLOCK.
NV-4  resolution rule version changes → BLOCK.
NV-5  policy version changes → BLOCK or RECOMPUTE under policy.
NV-6  provenance evidence missing → BLOCK.
NV-7  lifecycle evidence unstable → BLOCK.
NV-8  lifecycle CONTESTED → BLOCK.
NV-9  lifecycle INVALIDATED → BLOCK or RECOMPUTE.
NV-10 only bare result remains → BLOCK.
```

These scenarios are design-level validation classes, not commissioned fixtures.

## 11. Human review questions

```text
HQ-1  Are G-V1..G-V7 sufficient without importing business judgment?
HQ-2  Is the REUSE / BLOCK / RECOMPUTE split precise?
HQ-3  Is RECOMPUTE correctly subordinated to a separately authorized settlement
      contract?
HQ-4  Is the non-recomputation evidence boundary strong enough?
HQ-5  Are independence requirements sufficient to distinguish SRS reuse from
      cache hit?
HQ-6  Should additional typed blockers be registered before implementation
      design?
```

## 12. Decision requested

```text
ACCEPT SRS-VAL-01 V0.1    freeze this validation-predicate design and permit a
                          separately reviewed implementation/fixture plan.
REVISE SRS-VAL-01 V0.1    return with registered defects.
REJECT SRS-VAL-01 V0.1    do not proceed.
```

This document does not authorize implementation, fixture creation, experiment
execution, IS mutation, or code change.
