# Settled Relation State Reuse Validation Predicate — SRS-VAL-01 Design v0.2

> **Status:** DESIGN V0.2 REVISE — SUPERSEDED BY V0.3 — IMPLEMENTATION / EXPERIMENT NOT AUTHORIZED
> **Date:** 2026-10-07
> **Supersedes:** SRS-VAL-01 Design v0.1, retained as audit input
> **Review basis:** Human REVISE ruling on v0.1 at `f733457`
> **Revision purpose:** decision-boundary correction only; no architecture redesign, implementation, fixture, or experiment.
> **Review ruling:** REVISE; see `docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_DESIGN_V0.2_REVIEW_RULING_20261007.md`.
> **Superseded by:** `docs/02-evidence/es-is-20261005/SIMIGO_ES_IS_SRS_VAL_01_REUSE_VALIDATION_PREDICATE_DESIGN_V0.3_20261007.md`.

## 1. Effect of v0.2

v0.2 inherits v0.1 unless explicitly amended here.

It adds or corrects:

```text
A1  SRS never authorizes RECOMPUTE.

A2  A separately bound governing recompute/reuse authorization is required as
    predicate input I-14.

A3  A non-natural-language current reuse request binding is required as
    predicate input I-15.

A4  All inputs for one decision must belong to one lawful validation observation
    boundary, added as predicate input I-16.

A5  Default outcome for missing, ambiguous, inconsistent, or unauthorized
    inputs is BLOCK.

A6  RECOMPUTE requires an exact governing authorization that explicitly covers
    the observed invalidation class.
```

## 2. Expanded validation input contract

The predicate receives only lawfully bound semantic inputs:

```text
I-1   target SRS declaration;
I-2   exact SRS settlement identity;
I-3   exact source-relation instance binding;
I-4   canonical identity-generation rule binding, when applicable;
I-5   exact dependency set with dependency roles;
I-6   exact dependency revision/integrity bindings;
I-7   exact result target identity/revision binding;
I-8   exact resolution-rule identity/version binding;
I-9   exact policy/semantic version bindings;
I-10  immutable provenance evidence bindings;
I-11  immutable lifecycle evidence bindings;
I-12  current freshness requirement set;
I-13  current lawful freshness evidence, when available;
I-14  governing recompute/reuse authorization binding;
I-15  exact current reuse request binding;
I-16  validation observation boundary binding.
```

### 2.1 I-14 — governing recompute/reuse authorization

This is the only possible authorization source for `RECOMPUTE`.

It must bind to:

```text
immutable governing contract/policy identity;
exact immutable governing contract/policy version;
immutable content address or equivalent integrity binding;
covered source-relation semantics/instance class;
covered invalidation class;
authorized result-handling outcome.
```

Hard rules:

```text
SRS never authorizes RECOMPUTE.
Validation failure alone never authorizes RECOMPUTE.
Model confidence, similarity, business intent, agent preference, or natural
language never authorizes RECOMPUTE.

Missing, expired, ambiguous, overbroad, mutable, or unversioned authorization
yields BLOCK.
```

### 2.2 I-15 — exact current reuse request binding

`current_reuse_request_binding` is not user natural language and is not business
intent.

It is the exact semantic request/context against which source-relation
applicability is evaluated.

It must bind to:

```text
immutable semantic request identity;
exact immutable semantic request version;
or immutable content address.
```

Required semantic content:

```text
requested source-relation instance or semantics binding;
requested dependency-role context;
requested result-use context;
scope boundary;
freshness policy reference.
```

Hard rules:

```text
No business intent, semantic similarity, model confidence, or free-form user
prompt may substitute for this binding.

If I-15 is missing, unstable, ambiguous, or cannot be exactly matched to the
SRS source-relation applicability boundary, applicability is INDETERMINATE.

Applicability INDETERMINATE → BLOCK.
```

### 2.3 I-16 — validation observation boundary

All inputs used for one decision must belong to one declared validation
observation boundary.

It must record:

```text
boundary identity;
observation ordering/time evidence;
included SRS evidence references;
included dependency-state references;
included result-state references;
included freshness/policy evidence references;
consistency method or evidence;
boundary close time or ordering marker.
```

Hard rules:

```text
Inputs from different observation boundaries must not be mixed for one
decision.

If cross-input consistency cannot be established, return BLOCK.

This design does not define a transaction mechanism.
```

## 3. Applicability semantics — conservative

Applicability is evaluated only by exact semantic comparison:

```text
SRS source-relation applicability boundary
  ↔ I-15 exact current reuse request binding.
```

Possible results:

```text
APPLICABLE
  the exact current reuse request binding is explicitly covered by the SRS
  source-relation applicability boundary.

NOT_APPLICABLE
  the exact binding is present but outside the boundary.

APPLICABILITY_INDETERMINATE
  I-15 is missing/unstable/ambiguous, or no exact comparison can be made.
```

`APPLICABILITY_INDETERMINATE` and `NOT_APPLICABLE` both produce:

```text
BLOCK
```

They never produce semantic guessing, similarity matching, or business judgment.

## 4. Lifecycle and freshness status

Inherit v0.1 checks G-V1..G-V7 with these corrections.

### 4.1 Freshness recheck — positive clearing form

Replace v0.1 V7.6:

```text
V7.6  if FRESHNESS_RECHECK_REQUIRED is present,
      lawful clearing evidence MUST be present before REUSE is permitted.

      If clearing evidence is missing, ambiguous, unstable, or unauthorized:
        BLOCK_FRESHNESS_RECHECK_REQUIRED.

      If lawful clearing evidence is present:
        continue the remaining freshness checks.
```

This inherits SRS-SEM-01 v0.5: `FRESHNESS_RECHECK_REQUIRED` is blocking.

## 5. Validation observation consistency

Before evaluating G-V1..G-V7, establish:

```text
O-1  every input belongs to I-16;
O-2  observation ordering is lawful and interpretable;
O-3  SRS evidence, dependency state, result target, freshness evidence, policy
     evidence, and lifecycle evidence are all within the same boundary;
O-4  no included evidence depends on an excluded boundary;
O-5  boundary consistency evidence is immutable or exact.
```

If any check fails:

```text
decision = BLOCK
reason   = VALIDATION_INPUT_STATE_INCONSISTENT
```

This design does not define the transaction or snapshot mechanism.

## 6. Decision algorithm — conservative

The predicate is a total semantic function over a valid observation boundary:

```text
D(SRS, current bindings, governing authorization, current reuse request,
  observation boundary)
  → REUSE | BLOCK | RECOMPUTE
```

### 6.1 Step 1 — observation consistency

```text
if I-16 or its inputs are missing, ambiguous, inconsistent, or unstable:
  return BLOCK / VALIDATION_INPUT_STATE_INCONSISTENT
```

### 6.2 Step 2 — hard structural validation

Evaluate G-V1, G-V4, G-V5, G-V6.

The following always produce `BLOCK`, never `RECOMPUTE`:

```text
missing or unstable settlement identity;
invalid birth/lifecycle status;
UNRESOLVED_LIFECYCLE_CONFLICT;
CONTESTED lifecycle state;
INVALIDATED lifecycle state;
missing/unstable provenance evidence;
missing/unstable result target;
result identity equal to SRS identity;
missing/unstable resolution-rule binding;
missing/unstable policy binding;
semantic-boundary malformedness.
```

### 6.3 Step 3 — dependency and freshness validation

Evaluate G-V2 dependency revision/integrity checks and G-V7 freshness checks.

If no failure exists, continue.

If failures exist, classify each as:

```text
HARD_BLOCK
  no governing recompute authorization exists or is applicable.

RECOMPUTE_ELIGIBLE
  I-14 explicitly and exactly authorizes this invalidation class for this
  source-relation/request scope.
```

If any failure is `HARD_BLOCK`, the decision is:

```text
BLOCK
```

Only if all failures are `RECOMPUTE_ELIGIBLE` and the exact governing
authorization passes may the decision become:

```text
RECOMPUTE
```

### 6.4 Step 4 — applicability

Evaluate I-15 against the SRS source-relation applicability boundary.

```text
APPLICABLE              → continue;
NOT_APPLICABLE          → BLOCK;
APPLICABILITY_INDETERMINATE → BLOCK.
```

### 6.5 Step 5 — remaining checks

If all remaining G-V checks pass:

```text
return REUSE.
```

Otherwise:

```text
return BLOCK with typed reasons.
```

## 7. RECOMPUTE authorization semantics

`RECOMPUTE` is possible only when:

```text
1.  the observation boundary is consistent;
2.  SRS structure and provenance are sufficiently valid to interpret the SRS;
3.  a concrete validation failure exists;
4.  I-14 is an exact immutable governing authorization binding;
5.  I-14 explicitly covers the observed invalidation class;
6.  I-14 explicitly covers the source-relation instance/semantics class;
7.  I-14 explicitly covers the current reuse request class;
8.  I-14 is within its validity boundary;
9.  I-14 does not contradict any SRS invalidation/lifecycle record;
10. no hard structural blocker exists.
```

Hard rule:

```text
SRS itself never authorizes RECOMPUTE.

RECOMPUTE ≠ “validation failed, so compute again.”

RECOMPUTE = a separately bound governing semantic contract/policy explicitly
authorizes recomputation for this invalidation class.
```

Authorization failures:

```text
missing I-14                     → BLOCK
ambiguous invalidation class     → BLOCK
overbroad authorization          → BLOCK
mutable/unversioned I-14         → BLOCK
expired I-14                     → BLOCK
I-14 contradicts lifecycle state → BLOCK
```

## 8. Updated failure taxonomy

Add to v0.1 taxonomy:

```text
FT-V26  VALIDATION_INPUT_STATE_INCONSISTENT
FT-V27  GOVERNING_RECOMPUTE_AUTHORIZATION_MISSING_OR_INVALID
FT-V28  APPLICABILITY_INDETERMINATE
FT-V29  CURRENT_REUSE_REQUEST_BINDING_MISSING_OR_INVALID
FT-V30  UNAUTHORIZED_RECOMPUTE_REQUEST
FT-V31  GOVERNING_AUTHORIZATION_OUTSIDE_REQUEST_SCOPE
FT-V32  GOVERNING_AUTHORIZATION_EXPIRED
FT-V33  GOVERNING_AUTHORIZATION_CONTRADICTS_LIFECYCLE
```

`RECOMPUTE` without a passing exact I-14 authorization is:

```text
FT-V30 UNAUTHORIZED_RECOMPUTE_REQUEST
```

## 9. Decision examples

### 9.1 Valid reuse

```text
I-15 exact request is covered by SRS applicability;
all dependencies remain exact;
freshness evidence satisfies requirements;
lifecycle is determinate reusable;
result resolves without recomputation;
I-14 is unnecessary.

Decision: REUSE.
```

### 9.2 Dependency mismatch without authorization

```text
SRS requires A@12;
current A@19;
I-14 absent.

Decision: BLOCK.
```

### 9.3 Dependency mismatch with exact authorization

```text
SRS requires A@12;
current A@19;
I-14 explicitly authorizes recompute for
  this source-relation class,
  this dependency-change class,
  and this request class;
I-14 is exact, immutable, unexpired, and non-contradictory.

Decision: RECOMPUTE.
```

### 9.4 Ambiguous move/rename or policy mismatch

```text
governing authorization is broad but does not explicitly cover the observed
invalidation class.

Decision: BLOCK.
```

### 9.5 Cross-time input inconsistency

```text
dependency state and freshness evidence belong to different observation
boundaries.

Decision: BLOCK / VALIDATION_INPUT_STATE_INCONSISTENT.
```

## 10. Updated invariants

```text
INV-SRS-VAL-01  SRS never authorizes RECOMPUTE.

INV-SRS-VAL-02  RECOMPUTE requires exact governing authorization binding.

INV-SRS-VAL-03  Governing authorization must explicitly cover the observed
                invalidation class.

INV-SRS-VAL-04  Applicability requires exact current reuse request binding.

INV-SRS-VAL-05  Applicability indeterminate → BLOCK.

INV-SRS-VAL-06  All validation inputs belong to one lawful observation
                boundary.

INV-SRS-VAL-07  Inconsistent observation boundary → BLOCK.

INV-SRS-VAL-08  Default outcome for uncertain validation is BLOCK.

INV-SRS-VAL-09  RECOMPUTE is never inferred from failure alone.

INV-SRS-VAL-10  RECOMPUTE does not authorize mutation of user files or frozen
                semantics.
```

## 11. Decision requested

```text
ACCEPT SRS-VAL-01 V0.2   freeze the corrected predicate decision boundary and
                         permit a separately reviewed implementation/fixture
                         plan.
REVISE SRS-VAL-01 V0.2   return with registered defects.
REJECT SRS-VAL-01 V0.2   do not proceed.
```

No implementation, fixture, experiment, IS mutation, or code change is
authorized.
