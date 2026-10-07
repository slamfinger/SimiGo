# SRS-REAL-CLOSURE-01 — EXEC-002 Forensic Human Audit Record

> **Status:** READ-ONLY FORENSIC AUDIT CLOSED
> **Date:** 2026-10-07
> **Audit object:** canonical campaign evidence `c46537da…` against exact
> execution state `9966d31…`
> **Ruling type:** root-cause classification only
> **Authorization effect:** NONE

## 1. Audited chain

```text
request_v0_4 =
  commit 79ce4e3d313f13b66f946e2ed1e948745e4a1e82,
  blob 0b892d66103c736806a3ef54377cd82f3cbfe167,
  sha256 d64e4ebcc821f70601960cc53bea5b7e42630bd0d61a3edfd29ae476ca8368c4;

authorization_records_commit =
  86df16bbb145e24927716284b3b2b84da928456f;

exact_execution_repository_commit =
  9966d311e7e52ab3f5ca828e593ea569cddb008e;

campaign_evidence_commit =
  c46537da1c5d07a820a1db7540cfb33fde0ab3db;

campaign_run_id = exec-002-9966d31;
campaign_outcome = INVALID;
registered_stop_class = CAMPAIGN_EVIDENCE_ARTIFACTS_MISSING.
```

This audit did not execute the runner or observer, did not rebuild the
campaign, and did not modify fixture, runner, Request, SAR/OAR, or IS state.

## 2. Candidate A — mechanical zero-evidence chain

### A1 Exact source binding

At exact execution state `9966d31`:

```text
observer/observer.py =
  git:blob:248d3003c08609bbe3823ae7c05fb5c8747e2b52;
runner/es_runner.py =
  git:blob:875cb1d9577940e65fa507bf8228d477b2e171ff.
```

These match OAR 002's observer binding and Request v0.4's fixture bindings.

### A2 Runtime binding

OAR 002 and Request v0.4 bind:

```text
/Applications/Xcode.app/Contents/Developer/usr/bin/python3
sha256 dff595035109e19c43c4b3e73ee08b5f4651e719f25f8b4713f819d28964dc19
```

Step 0 used and hashed that runtime consistently. However, step 0 proves a
separate probe invocation; it does not prove which interpreter object executed
the later driver/observer processes.

### A3 Intended argv / invocation

The execution wrapper recorded these intended paths and a driver/observer pair:

```text
runner_path =
  <exact-9966d31-worktree>/docs/02-evidence/srs-real-closure-01/fixture/
    runner/es_runner.py;
observer_path =
  <exact-9966d31-worktree>/docs/02-evidence/srs-real-closure-01/fixture/
    observer/observer.py;
driver argv = driver RUN_DIR TAU_DIR IS_DIR ADAPTER_BIN;
observer argv = RUN_DIR IS_DIR.
```

The wrapper's return-code record is not a kernel-level process provenance
record. Therefore exact execution-time process identity/argv cannot be proven
from canonical evidence alone.

### A4 Observed process result

```text
driver_returncode = 0;
observer_returncode = 0;
driver stdout = 0 bytes;
driver stderr = 0 bytes;
observer stdout = 0 bytes;
observer stderr = 0 bytes.
```

The canonical wrapper also recorded:

```text
driver event logs = absent;
per-process event logs = absent;
IS objects = absent;
IS index entries = absent;
invocation graphs = absent;
decision outputs = absent;
observer_verdict.json = absent.
```

### A5 Run-directory destination

The driver/observer stdout/stderr redirect files exist in the authorized run
directory. Thus the shell-level redirect destination was present. This does not
prove that the Python child processes executed the exact bound artifacts.

### A6 Exact-source creation semantics

At `9966d31`, runner `EventLog.__init__` creates and immediately fsync-writes
`process_start`:

```text
runner lines 75-87.
```

For driver mode, the first act of `mode_driver` is to create
`driver-events.jsonl`:

```text
runner lines 668-672.
```

For observer mode, `main()` writes `observer_verdict.json` before printing and
before returning zero/nonzero:

```text
observer lines 106-113.
```

Therefore, if the exact driver source had executed in driver mode, a nonempty
`driver-events.jsonl` was mechanically required. If the exact observer source
had executed, `observer_verdict.json` was mechanically required.

## 3. Candidate A ruling

```text
CANDIDATE A = ACCEPTED AS ROOT-CAUSE CLASS;
ROOT_CAUSE_CLASS =
  EXACT_ARTIFACT_EXECUTION_CHAIN_NOT_ESTABLISHED;
```

The observed combination

```text
returncode = 0
+ exact-source-required evidence = absent
```

is incompatible with successful execution of the exact runner driver path and
exact observer artifact. Consequently, returncode 0 cannot be attributed to
those artifacts. The campaign failed at the mechanical execution/evidence
production chain before any semantic evidence existed.

The deeper operating-system-level mechanism remains unresolved. This ruling
does not claim which alternative binary, no-op, path mismatch, or process
substitution occurred.

## 4. Candidate B — `_001/V1` ↔ `_002/V2`

### B1-B3 Binding facts

Request v0.4 and OAR 002 require:

```text
observer_authorization_identity =
  SRS_REAL_CLOSURE_01_OBSERVER_AUTHORIZATION_RECORD_002;
channel_universe_identity =
  SRS-REAL-CLOSURE-01-CHANNEL-UNIVERSE-V2.
```

But exact runner `9966d31` embeds:

```text
OBSERVER_AUTHORIZATION_IDENTITY =
  SRS_REAL_CLOSURE_01_OBSERVER_AUTHORIZATION_RECORD_001;
CHANNEL_UNIVERSE_IDENTITY =
  SRS-REAL-CLOSURE-01-CHANNEL-UNIVERSE-V1.
```

Thus a pre-authorization cross-binding mismatch existed.

### B4 Actual consumption

No `READ_INSTANCE` records, event logs, or other runner outputs exist. There is
therefore no canonical evidence that the runner consumed either identity during
EXEC-002.

### B5 Causal relevance

The mismatch cannot explain the absent driver event log or absent observer
verdict. Those artifacts are produced before or independently of any
`READ_INSTANCE` identity payload. Candidate B is therefore not the root cause
of `CAMPAIGN_EVIDENCE_ARTIFACTS_MISSING`.

## 5. Final classification

```text
campaign_result = INVALID;
semantic_experiment_result = NOT RUN;
E1-E6 = ABSENT;
positive_REUSE = ABSENT;
N1_BLOCK = ABSENT;
core_claim = NOT ESTABLISHED;

root_cause_class =
  EXACT_ARTIFACT_EXECUTION_CHAIN_NOT_ESTABLISHED;

separate_registered_defect =
  PRE_AUTHORIZATION_CROSS_BINDING_MISMATCH;

runtime_environment_drift = NOT SUPPORTED;
fixture_semantic_defect = NOT SUPPORTED;
T_IMPL_01_defect = NOT SUPPORTED.
```

## 6. Budget and boundary

```text
execution_campaign_budget = consumed;
observer_attempt_budget = consumed;
IS_MUTATION_budget = unconsumed;
rerun = NOT AUTHORIZED;
runner/observer repair = NOT AUTHORIZED;
fixture repair = NOT AUTHORIZED;
automatic renewal = forbidden.
```

## 7. Next lawful object

The next lawful object is a Human decision whether to authorize a corrected
Request/record set that addresses:

```text
1. exact-artifact execution provenance and mandatory evidence production;
2. the separate `_001/V1` ↔ `_002/V2` cross-binding mismatch.
```

This record does not draft, approve, or authorize that correction.

## 8. Record integrity

```text
record_integrity_binding = registered by the governing commit introducing
this audit record on main; later modification creates a new content address
and voids this audit record.
```
