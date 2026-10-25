# SRS-REAL-CLOSURE-01 — EXECUTION Authorization Request v0.8 — Authoritative τN1 Schema Alignment and Corrected Campaign

> **Status:** OPENED / SUBMITTED FOR HUMAN AUTHORIZATION REVIEW — NO STAGE
> AUTHORIZED
> **Date:** 2026-10-07
> **Human opening authorization, exact form:** “授权‘Schema Authority + 新
> Request 起草’” — authorizes Schema Authority v1 and opening this Request
> only. It does not approve schema alignment, SAR/OAR creation, campaign, or
> any τ/runner/fixture modification.
> **Supersedes:** EXECUTION Authorization Request v0.7
> @ `e721f7a7460d3fbe0fe42c388bd4d07ce44709c2`
> (blob `e04a1219…`; SHA256 `fa393cab…`). v0.7 and records 005 @ `afca0d0…`
> were consumed by INVALID campaign `exec-005-fef0b2f` and are not reusable.
> **Review basis:** EXEC-005 evidence @ `5c5fcc4…`, forensic audit
> @ `7b176d1…`, and schema authority audit @ `9616133…`.
> **Requested authorization set upon separate APPROVE S+E:** five new records:
> `TAU_N1_INTERFACE_SCHEMA_ALIGNMENT_RECORD_006`,
> `EXECUTION_PROVENANCE_AND_BINDING_CLOSURE_RECORD_006`,
> `EXECUTION SAR 006`, `IS_MUTATION SAR 006`, and
> `OBSERVER AUTHORIZATION RECORD 006`.
> **No implementation, campaign, or run authority exists from opening this
> Request.**

## 1. Registered root cause and authority closure

EXEC-005 failed because Request v0.7 declared D' fields under
`dependencies[0]`, while exact runner consumes top-level `d_prime_seed_path`.
Schema Authority v1 now establishes the authoritative τN1 contract:

```text
schema_authority_identity =
  SRS_REAL_CLOSURE_01_TAU_N1_INTERFACE_SCHEMA_AUTHORITY_V1;
schema_authority_commit = a3e449cfaf92af76fec02f2dc2ca39d75c2ecbc6;
schema_authority_blob = e180f305d335059be5986c2e3674927576578198;
schema_authority_sha256 =
  8bf913d9a2fc3843566f52fece1f2bdac5a375e2237d85c23e5fed47a764d564.
```

Upon approval, `TAU_N1_INTERFACE_SCHEMA_ALIGNMENT_RECORD_006` shall adopt this
authority, and the scoped τN1 alignment work cycle shall remove deprecated
nested D' fields and add required top-level D' fields.

## 2. Exact execution state and inherited bindings

Pre-alignment exact execution state remains:

```text
9966d311e7e52ab3f5ca828e593ea569cddb008e.
```

Post-alignment execution state is not known while this Request is open. Upon
approval, the scoped alignment work cycle shall create an immutable
post-alignment commit; execution records 006 shall exact-bind that commit and
later governance commits are not execution state.

Inherited unchanged: Manifest v3 artifact set except τN1 to be aligned by the
scoped cycle, T-IMPL-01 sources, adapter runtime `e88c996b…`, ENV-PROBE-V1,
corrected environment identity `ad2abb68…`, D-SEC-1/D-SEC-2, §9 v3 contract,
ACCP-1 coverage boundary, frozen sequence, expected decisions, effect sets,
filesystem scope, no-network rule, and stop doctrine.

## 3. Part S — τN1 schema alignment work cycle

Upon approval, one work cycle scoped to:

```text
fixture/tau/tauN1.json;
fixture/FIXTURE_MANIFEST.md;
fixture/FIXTURE_PREPARATION_COMPLETION_RECORD.md.
```

shall:

```text
1. adopt Schema Authority v1;
2. remove deprecated nested D' fields from τN1;
3. add required top-level d_prime_seed_path =
   fixture/inputs/D_prime.md;
4. add required top-level d_prime_expected_sha256 =
   8553f52449b67de21021bb50ad6380c455bf686ee2a06cc77ed51e9f30060955;
5. add required top-level d_prime_revision = 2;
6. preserve dependencies[0].dependency_id = D-1;
7. preserve all inherited τN1 fields listed by Schema Authority v1;
8. advance Manifest to v5 and Completion Record to v5 solely for this
   alignment;
9. push and verify;
10. STOP for exact post-alignment commit instantiation of records 006.
```

No runner, observer, adapter, schema validator, D/D' seed, frozen contract, or
semantic decision may change.

## 4. Part E — corrected campaign through EPR004

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

Any failure remains INVALID. The ES2 REUSE observed in EXEC-004/005 is not
carried as campaign evidence.

## 5. Records and budgets

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
budget. v0.3–v0.7 opportunities, budgets, and records remain consumed/
non-reusable. Automatic renewal is forbidden.

## 6. Required Human decision

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
