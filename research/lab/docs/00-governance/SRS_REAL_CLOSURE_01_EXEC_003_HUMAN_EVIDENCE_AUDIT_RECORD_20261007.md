# SRS-REAL-CLOSURE-01 — EXEC-003 Human Evidence Audit Record

> **Status:** READ-ONLY HUMAN EVIDENCE AUDIT CLOSED
> **Date:** 2026-10-07
> **Audit object:** canonical campaign evidence `a50ff8b…` against exact
> execution state `9966d31…`
> **Authorization effect:** NONE

## 1. Audited chain

```text
request_v0_5 =
  commit 888a6a75022ffd2a84f5126055cef883c303c111,
  blob 45baf0b87deeabecfe41813ec0c5055a4ef8c646,
  sha256 bb3b9e427bbc07d1ee60c0bcb22df223b61d6d513607a4607c316fbd8b3a0a21;

authorization_records_commit =
  bda782913e719b0a465c8679fca4681429eb726f;

exact_execution_repository_commit =
  9966d311e7e52ab3f5ca828e593ea569cddb008e;

campaign_evidence_commit =
  a50ff8b317fc73ebf664b22dfbbf0b686c5cc02a;

campaign_run_id = exec-003-9966d31;
campaign_outcome = INVALID;
registered_primary_stop =
  EXECUTION_PROVENANCE_RECORDER_OUTPUT_PATH_INVALID;
registered_secondary_stop =
  CAMPAIGN_CWD_SEED_PATH_MISMATCH.
```

This audit did not execute runner, observer, EPR003, or any campaign stage, and
did not modify runner, fixture, EPR003, authorization records, or IS state.

## 2. Audit A — EPR003 provenance contract

Request v0.5 §4 explicitly declares:

```text
provenance_output =
  runs/<run_id>/execution_provenance.json.
```

The canonical launch plan instead set:

```text
output_path =
  /private/tmp/srs-exec3-9966d31.ztRput/docs/02-evidence/
    srs-real-closure-01/runs/exec-003-9966d31
```

That path is the run directory, not `execution_provenance.json`. EPR003
executed the driver, assembled command facts, then attempted
`Path(output_path).write_text(...)` and raised `IsADirectoryError`. Therefore
the required `execution_provenance.json` was absent.

### A ruling

```text
AUDIT_A = ACCEPTED;
defect_class =
  PROVENANCE_RECORDER_OUTPUT_PATH_BINDING_DEFECT;
```

This is a Request/launch-plan contract defect. EPR003's source also lacked a
preflight rejection of a directory-valued `output_path`; that implementation
validation gap is registered with it, but EPR003 did not fabricate a manifest or
pretend success. It failed closed.

## 3. Audit B — execution cwd / seed-path exact-state binding

The canonical provenance plan records:

```text
driver cwd =
  /Users/mr.simi/Documents/SimiGo-Lab;
tau1.seed_path =
  fixture/inputs/D.md.
```

The driver/materialize traceback records:

```text
FileNotFoundError:
  fixture/inputs/D.md
materialize_returncode = 1;
materialize completed = false;
IS objects written = 0;
IS index entries written = 0.
```

Path existence checks show:

```text
/Users/mr.simi/Documents/SimiGo-Lab/fixture/inputs/D.md = ABSENT;
/private/tmp/srs-exec3-9966d31.ztRput/fixture/inputs/D.md = ABSENT;
/Users/mr.simi/Documents/SimiGo-Lab/docs/02-evidence/srs-real-closure-01/
  fixture/inputs/D.md = PRESENT.
```

Thus the failure was not merely that driver cwd differed from the detached
worktree root. The frozen `tau1.seed_path` was repository-layout-relative and
would not resolve under either host repository root or detached worktree root.
A lawful campaign would have needed an explicit cwd/path resolution contract,
for example binding cwd to
`docs/02-evidence/srs-real-closure-01` or replacing `seed_path` with an exact
absolute/manifest-bound path.

### B ruling

```text
AUDIT_B = ACCEPTED;
defect_class =
  EXECUTION_CWD_AND_SEED_PATH_BINDING_DEFECT;
```

Request v0.5 exact-bound the repository commit and fixture artifacts, but did
not mechanically prebind runtime cwd to the exact execution layout or precheck
relative seed-path resolution before launch.

## 4. Causal relationship

The two defects are independent:

```text
B occurred first inside materialize:
  invalid seed-path resolution
    → materialize exit 1
    → no IS write;

A occurred in the recorder after driver completion:
  invalid output_path
    → manifest write failure
    → execution_provenance.json absent.
```

Therefore the registered primary stop classification must not be read as the
sole causal defect. It is the post-driver completeness/manifest stop class;
the causally earlier semantic-blocking failure was B.

## 5. Final classification

```text
campaign_result = INVALID;
semantic_experiment_result = NOT RUN;
E1-E6 = ABSENT;
positive_REUSE = ABSENT;
N1_BLOCK = ABSENT;
core_claim = NOT ESTABLISHED;

defect_A = PROVENANCE_RECORDER_OUTPUT_PATH_BINDING_DEFECT;
defect_B = EXECUTION_CWD_AND_SEED_PATH_BINDING_DEFECT;
relationship = INDEPENDENT;

runtime_environment_drift = NOT SUPPORTED;
crossbinding_001_V1_mismatch = SEPARATE PRE-AUTHORIZATION FINDING;
fixture_semantic_defect = NOT SUPPORTED;
T_IMPL_01_defect = NOT SUPPORTED.
```

## 6. Budget and boundary

```text
execution_campaign_budget = consumed;
provenance_closure_record = consumed;
IS_MUTATION_budget = unconsumed;
observer_attempt_budget = unconsumed;
rerun = NOT AUTHORIZED;
EPR003 repair = NOT AUTHORIZED;
runner/fixture repair = NOT AUTHORIZED;
automatic renewal = forbidden.
```

## 7. Next lawful object

The next lawful object is a Human decision whether to authorize a corrected
Request/record set addressing:

```text
1. EPR003 output_path contract and preflight validation;
2. exact execution cwd/path resolution and seed-path binding;
3. the separately registered `_001/V1` cross-binding finding, if still in
   scope.
```

This record does not draft, approve, or authorize that correction.

## 8. Record integrity

```text
record_integrity_binding = registered by the governing commit introducing this
audit record on main; later modification creates a new content address and
voids this audit record.
```
