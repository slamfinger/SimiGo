# SRS-REAL-CLOSURE-01 — EXECUTION Authorization Request v0.7 — τN1 Interface Completion and Corrected Campaign

> **Status:** OPENED / SUBMITTED FOR HUMAN AUTHORIZATION REVIEW — NO STAGE
> AUTHORIZED
> **Date:** 2026-10-07
> **Human opening authorization, exact form:** “授权新的 corrected Request /
> records” — authorizes opening this corrected Request only. It does not
> approve the staged work/campaign, create records, modify τ, or revive old
> budgets.
> **Supersedes:** EXECUTION Authorization Request v0.6
> @ `8704c7572273769d6cec170bd2ab803c01dc38f3`
> (blob `8cc67786…`; SHA256 `a6f0e2c3…`). v0.6 was approved and records 003
> were instantiated at `bda7829…`, but campaign `exec-004-9966d31` stopped
> INVALID. Those records and budgets are consumed/non-reusable.
> **Review basis:** EXEC-004 Human Evidence Audit
> @ `df508d473a1a4631f69dcfe7ab67595b5847acad`
> (SHA256 `1aa8e6e0c216e884156f2a9c0b90a3d6ce244c69085ea9b6cff1928c62776221`).
> Root cause = bilateral `FIXTURE_RUNNER_TAU_INTERFACE_CONTRACT_DEFECT`: exact
> runner consumed undeclared top-level `d_prime_seed_path` and `dependencies`,
> while exact τN1 under-declared both.
> **Requested authorization set upon separate APPROVE:** one τN1 interface
> completion work cycle plus four new campaign records:
> `TAU_N1_INTERFACE_COMPLETION_RECORD_005`, `TAU_N1_INTERFACE_COMPLETION_SAR_005`,
> `EXECUTION_PROVENANCE_AND_BINDING_CLOSURE_RECORD_005`, `EXECUTION SAR 005`,
> `IS_MUTATION SAR 005`, and `OBSERVER AUTHORIZATION RECORD 005`.
> **No implementation, campaign, or run authority exists from opening this
> Request.**

## 1. Registered root cause

```text
exact runner mutate-n1 requires:
  tau["d_prime_seed_path"];
  tau["dependencies"][0]["dependency_id"];

exact τN1/runtime under-declared both;
N1 D' object = NOT CREATED;
revision-2 mapping = NOT WRITTEN;
ESN invalidly read revision-1 and returned REUSE.
```

This is a bilateral fixture-runner τ interface contract defect. Repair is
confined to an explicit τN1 interface completion; runner semantics, EPR004,
semantic decisions, and all other fixture artifacts remain unchanged.

## 2. Exact inherited bindings

Manifest v3, Completion Record v3, Acceptance Record 002, the eleven fixture
artifacts as of Manifest v3, T-IMPL-01 canonical sources, adapter runtime
`e88c996b…`, ENV-PROBE-V1, corrected environment identity `ad2abb68…`,
D-SEC-1/D-SEC-2, §9 v3 contract, ACCP-1 coverage boundary, EPR004, frozen
sequence, expected decisions, and stop doctrine are inherited unchanged.

Exact runner remains `9966d31` blob `875cb1d9…` / SHA256 `bc393362…`.

## 3. Part T — τN1 interface completion

Upon approval, authorize exactly one work cycle scoped to:

```text
docs/02-evidence/srs-real-closure-01/fixture/tau/tauN1.json;
docs/02-evidence/srs-real-closure-01/fixture/FIXTURE_MANIFEST.md;
docs/02-evidence/srs-real-closure-01/fixture/
  FIXTURE_PREPARATION_COMPLETION_RECORD.md.
```

The sole semantic repair is to replace `tauN1.json` with the exact completed
schema bound in Appendix A:

```text
tauN1_completed_schema_sha256 =
  156fa091f6f0093f384fcc863a2532d7c8750619584fbca351f50632a677089b;

required新增 fields =
  dependencies[0].dependency_id = "D-1";
  dependencies[0].d_prime_seed_path = "fixture/inputs/D_prime.md";
  dependencies[0].d_prime_expected_sha256 =
    8553f52449b67de21021bb50ad6380c455bf686ee2a06cc77ed51e9f30060955;
  dependencies[0].d_prime_revision = 2;
```

No other τ field, runner field, semantic decision, fixture artifact, or frozen
contract changes. Manifest shall advance to v4 and the completion record to v4
solely to rebind `tauN1.json` and record this interface completion.

Preflight shall verify exact tauN1 SHA256, exact D' SHA256, exact dependency
ID, relative-path containment, and runner-required field presence before launch.

## 4. Part E — corrected campaign after canonical τ completion

After the τ completion work cycle is canonical and its exact repository commit
is recorded, create the four execution records listed above. Each shall
exact-bind the immutable post-completion repository commit; later governance
commits are not execution state.

The frozen campaign remains:

```text
materialize -> es1 -> es2 -> mutate-n1 -> esn -> observer -> evidence package.
```

EPR004 remains mandatory. The provenance plan shall additionally preflight:

```text
command cwd =
  <post-completion-worktree>/docs/02-evidence/srs-real-closure-01;
exact_repository_commit = post-completion immutable SHA;
tauN1 required fields and D' SHA256;
driver required artifacts;
observer verdict.
```

Missing field/artifact, path escape, identity mismatch, or unexpected returncode
→ INVALID → STOP.

Expected outcomes remain frozen:

```text
ES2 = REUSE;
N1 mutation = D' object + revision-2 mapping;
ESN = BLOCK via dependencyBlockingInvalidation;
ES1 U ledger = 1; ES2/ESN U ledgers = 0.
```

## 5. New records and budgets

Approval creates one τ completion work-cycle budget and one new campaign budget.
All prior v0.3–v0.6 campaign opportunities, records 001–004, and partial IS
state are consumed/non-reusable. Automatic renewal is forbidden.

## 6. Required Human decision

```text
APPROVE T+E
  create TAU_N1_INTERFACE_COMPLETION_SAR_005 and completion record 005;
  execute only the τN1 interface completion;
  push/verify; instantiate the four execution records 005 exact-binding the
  post-completion commit; execute one frozen campaign through EPR004; STOP
  for evidence audit.

APPROVE T ONLY
  complete τN1 interface and STOP before execution records.

REVISE REQUEST   return with registered defects.
DENY REQUEST     do not complete or execute.
```

Opening this Request authorizes no stage. Core claim remains **NOT
ESTABLISHED**.

## Appendix A — completed τN1 exact content

The exact UTF-8 JSON below has SHA256
`156fa091f6f0093f384fcc863a2532d7c8750619584fbca351f50632a677089b`.

```json
{
  "task": "ES-N negative control: same srs_identity after dependency state advanced to D'",
  "dependencies": [
    {
      "dependency_id": "D-1",
      "d_prime_seed_path": "fixture/inputs/D_prime.md",
      "d_prime_expected_sha256": "8553f52449b67de21021bb50ad6380c455bf686ee2a06cc77ed51e9f30060955",
      "d_prime_revision": 2
    }
  ],
  "srs_identity": "RESOLVED_FROM_IS_INDEX_BY_ES1_OUTPUT",
  "request_id": "req-esn-negative-1",
  "request_class": "R1-continuation",
  "boundary_id": "B-ESN",
  "run_order": "after-mutate-n1",
  "tau_content_ref": "TO_BE_BOUND_AT_EXECUTION",
  "expected_decision": "BLOCK",
  "expected_path": "BLOCKED_NON_RECOMPUTE_PATH via DP-1",
  "expected_typed_failure": "HARD_BLOCK.dependencyBlockingInvalidation(D-1)"
}
```
