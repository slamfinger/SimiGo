# SRS-REAL-CLOSURE-01 — Database-Carrier Fresh Initialization & Provenance Regeneration Request v1.2

> **Status:** OPENED / SUBMITTED FOR HUMAN AUTHORIZATION REVIEW — NO STAGE
> AUTHORIZED
> **Date:** 2026-10-08
> **Human opening authorization, exact form:** “继续 v1.2：只重新初始化一次，
> 且必须从干净的 `7392fcb` 执行。”
> **Requested stage set:** fresh initialization + exact provenance
> regeneration + selfcheck/manifest verification only.

## 1. Purpose

Regenerate initialization provenance against corrected implementation
`7392fcb…`. The prior initialization used commit `6a095ec…`, before the
corrected implementation commit existed; identical empty database bytes do not
repair provenance.

## 2. Exact bindings

```text
corrected_implementation_commit = 7392fcb79fb7e8465b73f9e1837c4634e56c0409;
accepted_design_package =
  21acba4e07f312fcb818968f33fd9e0c185fccf0;
schema_authority_v1 =
  a3e449cfaf92af76fec02f2dc2ca39d75c2ecbc6;
superseded_initialization_manifest =
  git:blob:6dbb53c369a797017beedaab120554759738722d,
  sha256 2a0350c2356e44d46933335293f643fffb04084f05747bd75c22fd977bbe07cc;

required_tauN1_sha256 =
  a78de04d4197841907f09e5927d070f20f7da126fa2750ddb0c2ba527a11fd39;
required_manifest_v5_sha256 =
  8b0976d54bfc064f0a8e166b9629ff81dc7aaad9017be83bfa394e99e49e6bb8;
required_completion_record_v4_sha256 =
  e139838f216a6d02942509b163dfb1a21c4a4fc1a53d5c8bc527e6b8f67a86bf.
```

## 3. Authorized action

One fresh initialization against clean exact execution state `7392fcb…`:

```text
detached checkout of 7392fcb…;
create one fresh empty SQLite-backed IS;
create only is_objects, is_index_entries and dependency_entries;
insert zero logical rows;
perform no logical import;
verify schema, integrity, table set, and zero row counts;
regenerate exact initialization provenance with corrected implementation
  commit, argv, cwd, UTC/monotonic timing, returncode, Python/SQLite versions,
  final schema SHA256, database hash/size, and zero row counts;
verify completed τN1 SHA256
  a78de04d4197841907f09e5927d070f20f7da126fa2750ddb0c2ba527a11fd39;
verify Manifest v5 SHA256
  8b0976d54bfc064f0a8e166b9629ff81dc7aaad9017be83bfa394e99e49e6bb8;
verify Completion Record v4 SHA256
  e139838f216a6d02942509b163dfb1a21c4a4fc1a53d5c8bc527e6b8f67a86bf;
STOP for Human review.
```

## 4. Forbidden scope

```text
implementation or τN1 modification;
runner/observer/schema modification;
logical import or nonzero logical rows;
campaign execution;
IS mutation;
observer execution;
old database/manifest reuse;
equivalence claim or adjudication;
automatic follow-on.
```

## 5. Required Human decision

```text
APPROVE FRESH INITIALIZATION + PROVENANCE REGENERATION
APPROVE INITIALIZATION ONLY
REVISE REQUEST
DENY REQUEST
```

Opening this Request authorizes no stage. CarrierSQLite equivalence remains
**NOT ESTABLISHED**.
