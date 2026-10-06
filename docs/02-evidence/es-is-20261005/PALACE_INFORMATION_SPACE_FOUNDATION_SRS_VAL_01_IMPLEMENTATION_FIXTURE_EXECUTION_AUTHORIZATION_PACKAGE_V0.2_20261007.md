# SRS-VAL-01 Implementation / Fixture / Execution Authorization Package v0.2

> **Status:** PACKAGE V0.2 REVISE — SUPERSEDED BY V0.3 — IMPLEMENTATION / FIXTURE / EXECUTION NOT AUTHORIZED
> **Date:** 2026-10-07
> **Frozen semantic basis:** SRS-VAL-01 Design v0.8 at `1170208`
> **Review basis:** Human REVISE ruling on Authorization Package v0.1 at `43bcb7e`
> **Purpose:** upgrade fixture isolation to verifiable Execution-State independence and make stage authorization a scope-bound immutable object.
> **Review ruling:** REVISE; see `docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_IMPLEMENTATION_FIXTURE_EXECUTION_AUTHORIZATION_PACKAGE_V0.2_REVIEW_RULING_20261007.md`.
> **Superseded by:** `docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_IMPLEMENTATION_FIXTURE_EXECUTION_AUTHORIZATION_PACKAGE_V0.3_20261007.md`.

## 1. Effect of v0.2

v0.2 inherits Authorization Package v0.1 unless explicitly amended here.

It adds:

```text
A1  ES-IND-01, a mandatory Execution-State Independence Boundary.

A2  Observable evidence that ES2 resolves from declared Information Space / SRS
    artifacts, not ES1 transient execution state or other shared runtime state.

A3  An immutable, scope-bound Stage Authorization Record for every authorized
    stage.

A4  Runner-stop enforcement for missing, invalid, mutable, overbroad, expired,
    or out-of-scope authorization.
```

This revision does not change SRS-VAL-01 Design v0.8 or expand the experiment
matrix.

```text
SRS-VAL-01 Design v0.8      ACCEPT / FROZEN / IMMUTABLE BASIS
Authorization Package v0.1  REVISE / SUPERSEDED BY V0.2
Authorization Package v0.2  SUBMITTED FOR HUMAN REVIEW
Implementation              NOT AUTHORIZED
Fixture preparation         NOT AUTHORIZED
Experiment execution        NOT AUTHORIZED
IS mutation                 NOT AUTHORIZED
SimiGo code change          NOT AUTHORIZED
```

## 2. Immutable package identity

Every later stage must record:

```text
package_identity;
frozen_predicate_design =
  SRS-VAL-01 Design v0.8;
frozen_predicate_basis_commit =
  1170208;
package_design_revision =
  PACKAGE_V0.2;
package_integrity_binding =
  immutable commit/content binding of this package.
```

A mutable package pointer, after-the-fact plan edit, or unspecified design
revision cannot authorize a stage.

## 3. Implementation-faithfulness requirements

Inherit v0.1 §3 without weakening it. The implementation plan must retain a
rule-to-code traceability matrix for I-14, I-15, I-16, exact predicate-rule
binding, G-CLASS, DP-0..DP-4, all G-V checks, I-14 not-used semantics, the
RECOMPUTE envelope, and canonical identity-rule binding.

No implementation may weaken, strengthen, reorder, or reinterpret a frozen rule.
No mutable rule pointer may replace an exact identity/version/integrity binding.
No missing evidence may be interpreted as a pass.

## 4. ES-IND-01 — Execution-State Independence Boundary

Fixture isolation alone is insufficient. The proof object is independent
Execution State:

```text
ES1 computes or settles R.
R becomes reachable only through declared Information Space / SRS artifacts.
ES2 independently validates/reuses R from those declared artifacts.
```

For every ES-independence proof, ES1 and ES2 MUST NOT share:

```text
process;
model/runtime memory;
singleton or static mutable state;
agent/conversation memory;
in-memory object graph;
undeclared IPC or shared memory;
hidden runner cache;
runner session carry-over;
transient ES1 execution state.
```

ES2 MAY rely only on:

```text
explicitly declared Information Space / SRS artifacts;
explicitly declared immutable execution inputs.
```

For each proof, the plan must record:

```text
es1_runtime_identity;
es2_runtime_identity;
es1_process_boundary;
es2_process_boundary;
es1_termination_or_quiescence_boundary;
es2_runtime_initialization_boundary;
shared_state_scan_method_and_result;
allowed_shared_artifact_bindings;
forbidden_shared_artifact_bindings;
transient_state_reliance_scan_result;
before/after declared-state hashes;
runner and environment identities.
```

Hard rules:

```text
ES1 and ES2 must use separate runtime/process boundaries.

ES1 must terminate or enter a declared non-interactive quiescent boundary before
ES2 runtime initialization.

ES2 must not receive ES1's live object graph, model context, conversation
state, singleton cache, runner-local memo, or undeclared IPC payload.

Fixture equality does not imply Execution-State independence.

Missing, ambiguous, or failed ES-IND-01 evidence invalidates the independence
claim and fails the affected proof.
```

This requirement is in addition to fixture-level isolation, not a replacement
for it.

## 5. REUSE and RECOMPUTE proofs under ES-IND-01

The positive REUSE proof must additionally show that ES2 obtains the result
through declared IS/SRS artifacts, with zero invocation of ES1's transient
computation path and no hidden runtime retrieval.

The eligible RECOMPUTE proof must additionally show that ES2 receives only
declared immutable inputs and IS/SRS artifacts, while exact predicate-rule,
I-14, and envelope evidence remain bound inside the same validation boundary.

If ES-IND-01 fails, the affected case cannot establish REUSE, RECOMPUTE, or a
lawful BLOCK boundary conclusion.

## 6. Stage Authorization Record

No prose authorization is sufficient. Before each stage, the runner requires an
exact immutable `Stage Authorization Record`.

A record must bind at least:

```text
authorization_identity;
authorization_kind =
  STAGE_AUTHORIZATION_RECORD;
stage ∈ {
  IMPLEMENTATION,
  FIXTURE_PREPARATION,
  EXECUTION
};
package_identity;
frozen_design_identity;
frozen_design_version =
  SRS-VAL-01 Design v0.8;
frozen_design_commit =
  1170208;
authorized_repository_revision;
authorized_result_code_revision, when implementation output exists;
authorized_fixture_identities;
authorized_environment_identity;
authorized_effect_or_mutation_set;
authorized_filesystem_scope;
authorized_network_scope;
authorized_execution_run_ids_or_run_budget;
validity_boundary;
authorization_use_count_or_budget;
integrity_or_content_address_binding;
human_ruling_reference.
```

Scope rules:

```text
An IMPLEMENTATION record may authorize only the exact writable source scope it
names. It never authorizes fixture creation, execution, IS mutation, or network
access.

A FIXTURE_PREPARATION record may authorize only the exact fixture artifacts and
filesystem paths it names. It never authorizes implementation changes,
execution, IS mutation, or network access.

An EXECUTION record may authorize only the named run IDs or run budget,
environment, and declared effect set. It never authorizes implementation or
fixture creation.

IS mutation is never implicit. It is valid only when the EXECUTION record
enumerates it in authorized_effect_or_mutation_set.

An empty network scope means no network access.
An empty effect/mutation set means no effect or mutation.
```

Validation rules:

```text
authorization for one stage
  ≠ authorization for any later stage;

IMPLEMENTATION AUTHORIZED
  does not imply FIXTURE_PREPARATION AUTHORIZED,
  EXECUTION AUTHORIZED, or IS MUTATION AUTHORIZED;

missing record
  → runner stop;

mutable, unversioned, unpinned, expired, overbroad, out-of-scope,
cross-stage, or integrity-invalid record
  → runner stop;

typed stop reason =
  AUTHORIZATION_RECORD_MISSING_INVALID_OR_OUT_OF_SCOPE.
```

Each completed stage must record the exact authorization identity used and the
evidence showing that effects remained inside its declared scope.

## 7. Boundary-case additions

Inherit the v0.1 boundary matrix and add:

```text
B-INDEP-01  ES2 attempts reuse after ES1; all ES-IND-01 evidence is valid.
B-INDEP-02  ES1 and ES2 would share a process/runtime cache; the case is
            invalid for independence proof.
B-AUTH-01   required Stage Authorization Record is absent.
B-AUTH-02   authorization identity is valid but used for a different stage.
B-AUTH-03   authorization scope is overbroad or includes an undeclared effect.
```

Each case must have one auditable pass/stop outcome and no discretionary
override.

## 8. Decision requested

```text
ACCEPT PACKAGE V0.2   freeze Execution-State independence and Stage Authorization
                      Record requirements; no stage is executed until separately
                      authorized.
REVISE PACKAGE V0.2   return with registered defects.
REJECT PACKAGE V0.2   do not proceed.
```

No implementation, fixture preparation, experiment, IS mutation, or SimiGo code
change is authorized by this document.
