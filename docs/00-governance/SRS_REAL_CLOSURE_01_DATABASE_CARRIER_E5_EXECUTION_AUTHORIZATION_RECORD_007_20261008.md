# SRS-REAL-CLOSURE-01 — Database-Carrier E5 Execution Authorization Record 007

> **Status:** APPROVE E5 / ONE FRESH FROZEN CAMPAIGN AUTHORIZED
> **Date:** 2026-10-08
> **Human ruling, exact form:** `APPROVE E5`
> **Governing Request v1.7:** `1b518c822b586dc3a6a900327267f5e3512a7e49`
> **R4 instrumentation commit:** `44514117f7657eda98b15155a916966d4e7c9b19`
> **R4 completion record commit:** `9c6574622fb3cd6ec06434f3fe3b9f944d613568`
> **Post-R4 review base:** `3d0e754a936c7718c86d45ba68beb53ad4a908d9`

## 1. Authorization

This record registers the Human post-R4 review ruling `APPROVE E5`. It
authorizes exactly one new, independently budgeted fifth frozen Database-Carrier
equivalence campaign from the canonical state introduced by this record.

```text
E5 campaign budget                 = 1;
E5 database IS-mutation budget     = 1;
E5 observer budget                 = 1;
E5 rerun budget                    = 0;
E5 repair budget                   = 0;
E5 automatic renewal               = FORBIDDEN;
E4/old campaign/evidence reuse     = FORBIDDEN;
semantic implementation change     = FORBIDDEN;
fixture change                     = FORBIDDEN;
runner semantic-sequence change    = FORBIDDEN;
ES2/ESN change                     = FORBIDDEN;
decision-boundary change           = FORBIDDEN;
EQ/REJ criteria change             = FORBIDDEN.
```

## 2. Exact execution contract

```text
governing_request = Request v1.7 @ 1b518c822b586dc3a6a900327267f5e3512a7e49;
part_r4_state = 44514117f7657eda98b15155a916966d4e7c9b19;
fresh_output_root =
  docs/02-evidence/database-carrier-equivalence-campaign-v1.7-20261008;
exact_execution_commit = THE_CANONICAL_COMMIT_INTRODUCING_THIS_RECORD;
campaign_id = exec-dbcarrier-005-<short exact_execution_commit>;
expected repository state = CLEAN, canonical, no untracked evidence root;
implementation = accepted corrected implementation, unchanged from R4.
```

The harness must consume the authoritative v1.7 path map, execute exactly
O0-O5, persist all required evidence through serialization/provenance closure,
and stop for Human evidence audit. It must not self-establish CarrierSQLite
equivalence.

## 3. Success discipline

The first lawful success condition is complete evidence closure, not any
particular REUSE or BLOCK outcome. Before EQ/REJ adjudication is eligible for
Human audit, the campaign must produce and preserve:

```text
O0-O5 observations;
fresh/working/O5 database chain;
adapter inputs/outputs and build provenance;
transaction records;
runtime/provenance/preflight records;
canonical C3 observer verdict and persistence binding;
serialization self-check;
EQ/REJ evidence matrix;
campaign outcome and database validation;
process result and stderr;
complete SHA256SUMS.
```

Any missing, mismatched, noncanonical, partially written, or unparsable
evidence artifact is fail-closed. It consumes E5 and forbids repair, rerun,
evidence substitution, or use of O5 raw state to force adjudication.

If complete closure occurs, the mechanical campaign result remains only
`CANDIDATE_EQUIVALENCE_PENDING_HUMAN_AUDIT`. CarrierSQLite equivalence,
EQ-1..EQ-8, REJ-1..REJ-14, and any broader SimiGo/ES claim remain unestablished
until a separate Human evidence audit accepts the complete chain.

## 4. Stop

This authorization expires upon the first campaign start. The campaign must
stop after complete closure or the first fail-closed evidence defect. This
record authorizes no further campaign, repair, rerun, or renewal.
