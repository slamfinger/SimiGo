# SRS-REAL-CLOSURE-01 — EXECUTION Authorization Request v0.9 — Corrected Predecessor Binding, Authoritative τN1 Schema Alignment, and Corrected Campaign

> **Status:** OPENED / SUBMITTED FOR HUMAN AUTHORIZATION REVIEW — NO STAGE
> AUTHORIZED
> **Date:** 2026-10-07
> **Human opening authorization, exact form:** “REVISE REQUEST” on Request
> v0.8, solely to correct its predecessor binding. This authorizes opening
> Request v0.9 only; it does not approve Part S/E, create records 006, modify
> τN1, execute EPR004, or revive budgets.
> **Supersedes:** EXECUTION Authorization Request v0.8
> @ `cfa514c46482e29aeb27db71899bed73d638d45c`
> (blob `25b36a51…`; SHA256 `bc738e8c…`). v0.8 is superseded by this revised
> Request and cannot be approved or executed.
> **Sole revision:** the predecessor/fixture baseline is corrected from
> ambiguous “Manifest v3 artifact set” to the current canonical post-τN1-
> completion state:
>
> ```text
> fef0b2fa5b3ac817a099bac885522fd17f4d3362
> + FIXTURE_MANIFEST v4
> + FIXTURE_PREPARATION_COMPLETION_RECORD v4
> + completed τN1
> ```
>
> Schema Authority v1, EPR004, inherited artifact/D-SEC/§9/environment/
> decision bindings, scoped Part S, Part E, records 006, and stop doctrine
> remain otherwise unchanged.
> **Requested authorization set upon separate APPROVE S+E:** five new records:
> `TAU_N1_INTERFACE_SCHEMA_ALIGNMENT_RECORD_006`,
> `EXECUTION_PROVENANCE_AND_BINDING_CLOSURE_RECORD_006`,
> `EXECUTION SAR 006`, `IS_MUTATION SAR 006`, and
> `OBSERVER AUTHORIZATION RECORD 006`.
> **No implementation, campaign, or run authority exists from opening this
> Request.**

## 1. Registered review cause

EXEC-005 stopped INVALID after EPR004-launched driver/materialize failure.
The schema authority audit correctly identified shared/bilateral
`TAU_N1_RUNNER_SCHEMA_AUTHORITY_ABSENCE`. Request v0.8 correctly added Schema
Authority v1 and proposed τN1 schema alignment, but its inherited-baseline
wording still referred to Manifest v3 rather than the current canonical τN1
completion state. This revised Request removes that binding ambiguity.

## 2. Exact authority and predecessor bindings

```text
schema_authority_identity =
  SRS_REAL_CLOSURE_01_TAU_N1_INTERFACE_SCHEMA_AUTHORITY_V1;
schema_authority_commit = a3e449cfaf92af76fec02f2dc2ca39d75c2ecbc6;
schema_authority_blob = e180f305d335059be5986c2e3674927576578198;
schema_authority_sha256 =
  8bf913d9a2fc3843566f52fece1f2bdac5a375e2237d85c23e5fed47a764d564;

current_fixture_baseline_commit =
  fef0b2fa5b3ac817a099bac885522fd17f4d3362;

current_fixture_manifest =
  FIXTURE_MANIFEST v4,
  git:blob:34c0c66cc566577764b663f34ac6959b8d37ae77,
  sha256 abbc342e11709838cf3a474b43c3f94ae653ecbb3fd27f4495a8b99fb9ebe6c9;

current_fixture_completion_record =
  FIXTURE_PREPARATION_COMPLETION_RECORD v4,
  git:blob:a1d4eb6f4dd1a4e352a9370f037b6377c01aebd0,
  sha256 ef4728bbdad1e7f0af7c8d98b518ba0e64270a2b360930107a7737ef3d3858d0;

completed_tauN1 =
  docs/02-evidence/srs-real-closure-01/fixture/tau/tauN1.json,
  git:blob:0d5434ec8ef2de497f52f0605e4fe8c09d524315,
  sha256 156fa091f6f0093f384fcc863a2532d7c8750619584fbca351f50632a677089b.
```

Manifest v3 is historical provenance only. The Part S alignment baseline is
Manifest v4 / Completion Record v4 at `fef0b2f`.

## 3. Exact execution state boundary

Pre-alignment exact execution state remains `9966d31`; however, the approved
Part S alignment will create a new immutable post-alignment commit. Execution
records 006 shall exact-bind that post-alignment commit, not this Request
commit and not later governance commits.

All inherited artifact bindings other than τN1 remain unchanged from current
Manifest v4. T-IMPL-01 sources, adapter runtime `e88c996b…`, ENV-PROBE-V1,
corrected environment identity `ad2abb68…`, D-SEC-1/D-SEC-2, §9 v3 contract,
ACCP-1 coverage boundary, frozen sequence, expected decisions, effect sets,
filesystem scope, no-network rule, and stop doctrine remain unchanged.

## 4. Part S — τN1 schema alignment v4 → v5

Upon approval, one work cycle scoped to τN1, Manifest, and Completion Record
shall adopt Schema Authority v1:

```text
remove deprecated nested D' fields:
  dependencies[0].d_prime_seed_path;
  dependencies[0].d_prime_expected_sha256;
  dependencies[0].d_prime_revision;

add required top-level fields:
  d_prime_seed_path = fixture/inputs/D_prime.md;
  d_prime_expected_sha256 =
    8553f52449b67de21021bb50ad6380c455bf686ee2a06cc77ed51e9f30060955;
  d_prime_revision = 2;

preserve:
  dependencies[0].dependency_id = D-1;
  all other inherited τN1 fields listed by Schema Authority v1.
```

Manifest shall advance v4 → v5 and Completion Record shall advance v4 → v5
solely to record this alignment. No runner, observer, adapter, validator, D/D'
seed, frozen contract, or semantic decision changes.

The scoped completion shall push/verify and stop so that the immutable
post-alignment commit can be exact-bound by records 006.

## 5. Part E — corrected campaign through EPR004

After records 006 exact-bind the immutable post-alignment commit, one campaign
shall run through EPR004. EPR004 shall fail closed on:

```text
exact repository commit mismatch;
command cwd != <post-alignment worktree>/docs/02-evidence/srs-real-closure-01;
τN1 schema authority SHA mismatch;
required top-level D' fields absent;
deprecated nested D' fields present;
D' path escape or SHA mismatch;
executable identity/argv/process fact mismatch;
required artifact absence;
unexpected returncode.
```

Frozen expected outcomes remain:

```text
materialize = PASS;
ES1 = PASS;
ES2 = PASS and REUSE;
mutate-n1 = PASS, creating D' object and revision-2 mapping;
ESN = PASS and BLOCK via dependencyBlockingInvalidation;
ES1 U ledger = 1; ES2/ESN U ledgers = 0;
observer bounded checks = PASS.
```

Any failure remains INVALID. Prior ES2 REUSE observations from EXEC-004/005
are not carried as campaign evidence.

## 6. Records and budgets

Upon separate `APPROVE S+E`, create:

```text
TAU_N1_INTERFACE_SCHEMA_ALIGNMENT_RECORD_006;
EXECUTION_PROVENANCE_AND_BINDING_CLOSURE_RECORD_006;
EXECUTION SAR 006;
IS_MUTATION SAR 006;
OBSERVER AUTHORIZATION RECORD 006.
```

All execution records shall exact-bind the immutable post-alignment commit.
This Request grants one schema alignment work-cycle budget and one new campaign
budget. v0.3–v0.8 opportunities, budgets, and records remain consumed/
non-reusable. Automatic renewal is forbidden.

## 7. Required Human decision

```text
APPROVE S+E
  authorize scoped τN1 schema alignment and corrected campaign records;
  complete alignment; instantiate records 006 exact-binding the
  post-alignment commit; run one frozen campaign through EPR004; STOP for
  evidence audit.

APPROVE S ONLY
  authorize schema alignment only; stop before records 006/campaign.

REVISE REQUEST   return with registered defects.
DENY REQUEST     do not align or execute.
```

Opening this Request authorizes no stage. Core claim remains **NOT
ESTABLISHED**.
