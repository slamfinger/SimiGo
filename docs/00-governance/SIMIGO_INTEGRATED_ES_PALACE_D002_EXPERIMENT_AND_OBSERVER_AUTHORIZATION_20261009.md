# D-002 Bounded Decision Replay, Experiment, and Observer Authorization

> **Status:** AUTHORIZED — ONE DECISION REPLAY + ONE EXPERIMENT + ONE OBSERVER
> **Date:** 2026-10-09
> **Authorization ID:** `D002-BOUNDED-REPLAY-EXPERIMENT-OBSERVER-AUTH-001`
> **Canonical base:** `fe9a945676b7ffa2ac0e63c52c4d90717ff20824`

## 1. Human ruling

```text
ACCEPT D-002 PREPARATION COMPLETION

AUTHORIZE:
  one D-002 DECISION REPLAY
  one D-002 BOUNDED EXPERIMENT
  one independent D-002 OBSERVER CAMPAIGN

EXPERIMENT SCOPE:
  real PALACE snapshot only
  seven pre-registered real-source cases
  frozen R-I1..R-I10 mapping
  unchanged D-001 Decision Core
  frozen three-component expected vector
  independent observer reconciliation

REQUIRED:
  write-once evidence
  fail-closed on first-fault
  exact source/snapshot digest binding
  no hidden semantic input
  no semantic search
  no embedding/vector traversal
  no model/cloud participation

MUST REMAIN CLOSED:
  canonical IS mutation
  PALACE source mutation
  E9
  EXP-004
  PIR reopening
  D-001 rerun
  PALACE equivalence claim
  integrated SimiGo proof

BUDGET:
  decision replay = 1 / 1
  experiment = 1 / 1
  observer campaign = 1 / 1
  rerun / repair-run = NOT AUTHORIZED
```

## 2. Authority separation

Decision replay, experiment, and observer must remain separately recorded. The
experiment runner must not itself act as observer authority. The observer must
receive no expected verdicts.

## 3. Evidence parent

```text
docs/02-evidence/integrated-es-palace-d002-consumption-v1/
```

The evidence objects are write-once and exactly:

```text
RUN_MANIFEST_INSTANCE.json
DECISION_REPLAY_RECORD.json
EXPERIMENT_RECORD.json
CARRIER_LIFECYCLE_RECORD.json
OBSERVER_RECORD.json
RECONCILIATION_RECORD.json
CLAIM_RECORD.json
EVIDENCE_SHA256SUMS
```

`EVIDENCE_SHA256SUMS` is final.

## 4. Continuing prohibitions

```text
canonical IS mutation      = NOT AUTHORIZED;
PALACE source mutation     = NOT AUTHORIZED;
E9                         = NOT AUTHORIZED;
EXP-004                    = NOT AUTHORIZED;
PIR reopening              = NOT AUTHORIZED;
D-001 rerun                = NOT AUTHORIZED;
semantic search            = FORBIDDEN;
embedding/vector traversal = FORBIDDEN;
model/cloud participation  = FORBIDDEN;
PALACE equivalence claim   = FORBIDDEN;
integrated SimiGo proof    = FORBIDDEN;
general ES theorem         = FORBIDDEN;
production validity        = FORBIDDEN;
LLM autonomy               = FORBIDDEN.
```

## 5. Stop rule

After one replay, one experiment, and one observer campaign, execution stops. No
rerun or repair-run is authorized by this Record.

## 6. Record integrity

This authorization is registered by the canonical commit introducing it. Later
modification creates a new content address and does not silently revise the
Human ruling.
