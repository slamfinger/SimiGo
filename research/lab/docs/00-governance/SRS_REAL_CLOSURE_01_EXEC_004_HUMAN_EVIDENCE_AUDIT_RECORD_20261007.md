# SRS-REAL-CLOSURE-01 — EXEC-004 Human Evidence Audit Record

> **Status:** READ-ONLY HUMAN EVIDENCE AUDIT CLOSED
> **Date:** 2026-10-07
> **Audit object:** canonical campaign evidence `4238529…` against exact
> execution state `9966d31…`
> **Authorization effect:** NONE

## 1. Audited chain

```text
request_v0_6 =
  commit 8704c7572273769d6cec170bd2ab803c01dc38f3,
  blob 8cc67786d0af60cfab4f14c38fdab4667a1cdce1,
  sha256 a6f0e2c35b6821154d630a648ea0cc1a77afb98d6818d2d8eec1775572e25772;

authorization_records_commit =
  b80c17a2a2f45a6843856d630f0b8dabc24f2d6b;

exact_execution_repository_commit =
  9966d311e7e52ab3f5ca828e593ea569cddb008e;

campaign_evidence_commit =
  4238529b6a6c527a3d3ab7b0bb987715fe2e1fa8;

navigation_commit_at_audit_open =
  ad09ed0e1cd655871c099a82bcec7f4e4c7b60b1;

campaign_run_id = exec-004-9966d31;
campaign_outcome = INVALID;
stop_code = MUTATE_N1_TAU_D_PRIME_SEED_PATH_BINDING_DEFECT.
```

This audit did not execute runner, observer, mutate-n1, ESN, or any campaign
stage; did not modify τ, runner, fixture, authorization records, or IS state;
and did not draft a corrected Request.

## 2. Confirmed execution progress

Step 0, EPR004, adapter runtime, corrected environment identity, materialize,
ES1, and ES2 all succeeded. The provenance recorder enforced exact cwd, exact
repository commit, D/D' repository-contained bindings, executable identity,
argv, process facts, and required artifacts.

ES2 emitted the pre-registered:

```text
primaryDecision = REUSE;
decisionPath = REUSE_PATH;
expected REUSE = actual REUSE;
continuation completed.
```

That observation is recorded, but it is not campaign evidence because the
frozen sequence did not complete.

## 3. N1 precondition failure

`mutate-n1` failed immediately at:

```text
runner lines 614-616:
  open(tau["d_prime_seed_path"], "rb")

observed error:
  KeyError: d_prime_seed_path
```

The bound `tauN1-runtime.json` contained only:

```text
boundary_id, expected_decision, expected_path, expected_typed_failure,
request_class, request_id, run_order, srs_identity, task, tau_content_ref
```

It contained neither:

```text
d_prime_seed_path
dependencies
```

Therefore:

```text
D' object creation = NOT PERFORMED;
revision-2 mapping entry = NOT PERFORMED;
N1 dependency-state advance = ABSENT.
```

ESN then sealed/read revision-1 state:

```text
declared_immutable_revision = 1;
resolved_declared_content_digest =
  806fffadef09d3ad491d75c6b42738e99626ee1961ed1aecf2d593aefd55980c;
dependency D-1 resolved = true.
```

Consequently ESN emitted:

```text
primaryDecision = REUSE;
expected BLOCK = actual REUSE mismatch.
```

That ESN `REUSE` is invalid derived behavior: its required N1 precondition was
absent. It is neither positive semantic evidence nor a negative refutation.

## 4. Contract-responsibility ruling

The exact runner imposes an undeclared top-level τ requirement:

```text
tau["d_prime_seed_path"]
```

and additionally uses:

```text
tau["dependencies"][0]["dependency_id"]
```

But the exact bound τN1/runtime artifact does not declare either field. The
frozen Design, Manifest, fixture completion record, and Request v0.6 likewise
do not define a τ schema assigning `d_prime_seed_path` or `dependencies` to
τN1.

Therefore this is not a one-sided “τ path missing” defect or one-sided “runner
bug.” The canonical ruling is:

```text
FIXTURE_RUNNER_TAU_INTERFACE_CONTRACT_DEFECT;
responsibility_boundary = SHARED / BILATERAL;

runner-side defect component:
  consume an undeclared top-level τ field;

τ-side defect component:
  under-declare the fields required by the bound runner's mutate-n1 mode;

specification-side defect component:
  Request v0.6 exact-bound both sides without requiring a τ interface schema
  or preflight field-contract validation.
```

This classification does not authorize choosing a repair direction. A future
corrected Request may bind an explicit τ interface schema and require preflight
validation, but that decision is not made here.

## 5. Final campaign classification

```text
campaign_result = INVALID;
semantic_experiment_result = PARTIALLY LAUNCHED / NOT VALIDLY COMPLETED;
materialize = PASS;
ES1 = PASS;
ES2 = PASS;
ES2 observed REUSE = INVALID AS CAMPAIGN EVIDENCE;
N1 mutation = NOT PERFORMED;
N1 BLOCK = ABSENT;
E1-E6 = INCOMPLETE / NOT JOINTLY ESTABLISHED;
semantic_hypothesis = NEITHER SUPPORTED NOR REFUTED;
core_claim = NOT ESTABLISHED;
root_cause_class =
  FIXTURE_RUNNER_TAU_INTERFACE_CONTRACT_DEFECT.
```

## 6. Budget and boundary

```text
execution_campaign_budget = consumed;
observer_use_budget = consumed;
IS_MUTATION_campaign_budget = consumed by partial lawful writes;
D'_addition/revision-2 write = NOT PERFORMED;
rerun = NOT AUTHORIZED;
tau repair = NOT AUTHORIZED;
runner repair = NOT AUTHORIZED;
fixture repair = NOT AUTHORIZED;
automatic renewal = forbidden.
```

## 7. Next lawful object

The next lawful object is a Human decision whether to authorize a corrected
Request/record set. Any future correction must address:

```text
1. explicit τN1 interface schema;
2. required mutate-n1 fields, including D' binding and dependency ID source;
3. preflight τ field/schema validation before launch;
4. preservation of the existing `_001/V1` cross-binding audit finding if still
   in scope.
```

This record does not draft, approve, or authorize that correction.

## 8. Record integrity

```text
record_integrity_binding = registered by the governing commit introducing this
audit record on main; later modification creates a new content address and
voids this audit record.
```
