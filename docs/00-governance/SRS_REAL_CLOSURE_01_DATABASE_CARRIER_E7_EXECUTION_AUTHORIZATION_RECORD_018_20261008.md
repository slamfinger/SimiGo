# SRS-REAL-CLOSURE-01 — Database-Carrier E7 Execution Authorization Record 018

> **Status:** APPROVE E7 — ONE FRESH INDEPENDENT FROZEN CAMPAIGN AUTHORIZED
> **Date:** 2026-10-08
> **Human ruling, exact form:** `APPROVE E7 — 作为全新、独立、冻结的 campaign 执行。`
> **Governing Request v2.0:** `3f8b33a7e97a3d4017e55ad4ca3080b90c95b934`
> **R6 correction commit:** `3f8b33a...`
> **R6 completion record:** `7a919fe79936362d63ce6c8230337ccef0023e1e`
> **E7 path-map integrity addendum:** `7e385b2fda1dc66288f7807cad92e43034e25b82`
> **E7 launch-review navigation:** `b8146e93822221aa20b90a40d62265a2a483c8b2`
> **Exact execution commit:** canonical commit introducing this record

## 1. Authorization

Exactly one new, independently budgeted E7 frozen campaign is authorized from
the canonical state introducing this record.

```text
E7 campaign budget       = 1;
E7 IS-mutation budget    = 1;
E7 observer budget       = 1;
E7 repair budget         = 0;
E7 rerun budget          = 0;
E7 renewal               = FORBIDDEN;
mid-campaign repair      = FORBIDDEN;
old campaign/evidence reuse = FORBIDDEN;
automatic equivalence    = FORBIDDEN.
```

## 2. Execution contract

The harness must consume the fresh v2.0 version-5 E7-reserved path map,
execute exactly O0–O5, close every evidence/provenance artifact, and stop for
separate Human evidence audit.

```text
campaign_id = exec-dbcarrier-007-<short exact_execution_commit>;
fresh_output_root = docs/02-evidence/database-carrier-equivalence-campaign-v2.0-e7-reserved-20261008;
expected repository state = clean and equal to exact_execution_commit.
```

## 3. Stop discipline

Any missing, mismatched, noncanonical, partially written, unparsable, or
path-bearing evidence artifact is fail-closed and consumes E7. No repair,
rerun, evidence reconstruction, or forced adjudication is authorized.

If E7 closes mechanically, it is only
`CANDIDATE_EQUIVALENCE_PENDING_HUMAN_AUDIT`. EQ/REJ adjudication,
CarrierSQLite equivalence, and broader claims remain unestablished until
separate Human evidence audit accepts the complete chain.
