# SRS-REAL-CLOSURE-01 — Database-Carrier R4 Serialization-Closure Completion Record 006

> **Status:** PART R4 COMPLETE / STOPPED FOR POST-R4 HUMAN REVIEW
> **Date:** 2026-10-08
> **Governing Request v1.7:** `1b518c822b586dc3a6a900327267f5e3512a7e49`
> **R4 instrumentation commit:** `44514117f7657eda98b15155a916966d4e7c9b19`
> **E5 fifth campaign:** NOT LAUNCHED

## 1. Scope closure

Part R4 is complete within the Human-authorized correction surface. The only
changed files between the Request and R4 are:

```text
database-carrier-replication/campaign/EVIDENCE_PATH_BINDING_MANIFEST.json;
database-carrier-replication/campaign/evidence_paths.py;
database-carrier-replication/campaign/run_equivalence_campaign.py.
```

The accepted implementation tree is unchanged. CarrierSQLite semantics, DB
schema and transaction semantics, ES2/ESN, decision boundary, fixture, runner
semantic sequence, and EQ/REJ criteria were not modified.

## 2. Fresh evidence path

```text
manifest identity =
  DATABASE_CARRIER_EQUIVALENCE_EVIDENCE_PATH_BINDING_MANIFEST_005;
destination count / version = 31 / 3;
fresh v1.7 evidence root =
  docs/02-evidence/database-carrier-equivalence-campaign-v1.7-20261008;
independent path preflight = 31/31 PASS;
manifest SHA256 = 67b742397f2e245dd002a9b8344c03cdcb6dbc83be45e6369d2d5d50ee9b7d0b.
```

The v1.7 output root was removed after preflight and remains fresh for any
future authorized campaign. No O0–O5 execution occurred.

## 3. Serialization invariant

The campaign now applies one fail-closed invariant to canonical evidence:

```text
pre-write recursive serialization check
→ exclusive write
→ reread
→ byte equality
→ parse
→ parsed-object equality
→ serialization binding
→ chain continuation.
```

The canonical writer rejects nonserializable values, non-finite values, and
path-like values before opening the destination. Path-like provenance values
are normalized to repository-relative POSIX strings. Exact reference and
adapter JSON bytes are separately persisted with the same reread/parse checks
without changing their authoritative byte identity.

## 4. Canonical post-commit self-check

All checks were run against the canonical R4 commit with a clean worktree:

```text
independent path preflight            = PASS 31/31;
Path pre-write rejection              = PASS;
canonical JSON write/reread/parse     = PASS;
exact reference JSON persistence      = PASS;
implementation-tree immutability      = PASS;
forbidden-scope diff                  = EMPTY;
worktree after checks                 = CLEAN.
```

`EVIDENCE_SERIALIZATION_SELF_CHECK` is registered as the authoritative 31st
POST_SEQUENCE destination. It will aggregate the evidence-path binding, every
canonical JSON artifact, transaction canonicalization, observer verdict and
persistence binding, preflight verification, runtime provenance, campaign
validation/outcome/process result, and its own self-check before SHA256SUMS.

## 5. Budget disposition

```text
R4 serialization/provenance correction budget = CONSUMED;
fifth campaign / IS-mutation / observer       = RESERVED, CONDITIONAL, 1;
E4 old-budget reuse                           = FORBIDDEN;
rerun or automatic E5 launch                  = FORBIDDEN.
```

## 6. Next lawful object

The next lawful object is explicit Human post-R4 review. The allowed ruling is
one of:

```text
APPROVE E5
REVISE R4
DENY E5
```

No fifth campaign may be drafted into execution, launched, retried, or treated
as authorized until the Human provides an explicit post-R4 ruling.

## 7. Record integrity

```text
record_integrity_binding = registered by the canonical commit introducing this
record; later modification creates a new content address and voids this
completion record.
```
