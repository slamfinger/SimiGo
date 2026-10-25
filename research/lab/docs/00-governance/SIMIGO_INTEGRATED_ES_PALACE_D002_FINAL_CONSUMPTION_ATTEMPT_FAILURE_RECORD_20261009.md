# D-002 Final Consumption Attempt Failure Record

> **Status:** FINAL CAMPAIGN EXECUTED / FAIL / WRITE-ONCE EVIDENCE RETAINED / NO RERUN
> **Date:** 2026-10-09
> **Manifest instance:** `18FE111C-C258-4A12-B6F6-C184A2078625`
> **Execution head:** `ed3985d6`

## 1. Budget consumption

```text
decision replay        = 1 / 1 CONSUMED;
bounded experiment     = 1 / 1 CONSUMED;
observer campaign      = 1 / 1 CONSUMED;
repair-run after entry = 0;
rerun                  = 0;
canonical IS mutation  = NONE;
PALACE source mutation = NONE.
```

Evidence parent:

```text
docs/02-evidence/integrated-es-palace-d002-consumption-attempt-003/
```

`EVIDENCE_SHA256SUMS` verified all seven preceding evidence objects.

## 2. New completeness gate

```text
D002_MANIFEST_ADAPTER_CLOSURE = PASS.
```

The gate verified the completed package binding, adapter-required manifest
paths, frozen evidence objects, seven cases, retained fixture root, sealed
preparation validation, and exact source/snapshot bindings before budget
consumption.

## 3. Outcome

```text
DECISION_REPLAY_RECORD   = PASS / EXECUTED;
EXPERIMENT_RECORD        = FAIL;
CARRIER_LIFECYCLE_RECORD = PASS / 7 RECORDS PERSISTED;
OBSERVER_RECORD          = PASS;
RECONCILIATION_RECORD    = FAIL;
CLAIM_RECORD             = FAIL.
```

The independent observer classified all seven cases correctly:

```text
P-LAWFUL     = CONTINUE;
P-SETTLED    = REUSE;
P-BLOCKED    = BLOCK;
N-MISSING    = MISSING_INFORMATION_BLOCK;
N-STALE      = STALE_INFORMATION_BLOCK;
N-AMBIGUOUS  = AMBIGUOUS_INFORMATION_BLOCK;
N-ILLEGAL    = ILLEGAL_CONTINUATION_BLOCK.
```

However, the replay adapter produced unresolved D-001 inputs for all seven
cases. Only `N-MISSING` matched its frozen vector; the other six did not. The
unchanged D-001 Decision Core correctly fail-closed those unresolved inputs.

## 4. Boundaries remained stable

```text
PALACE source SHA-256 =
  3f790600bfa0ebb0eb7bd4e9f28ac1b6353bd6802d5eeb8f964e7edb8861bf0a;
snapshot SHA-256 =
  8b3856e2e4e3a1bd87580afc1ab42094e9a952e0985952323e02ae6595ce1444;
D-001 Decision Core hashes = unchanged;
D-002 fixtures and EXPECTED vectors = unchanged;
observer semantics = corrected and stable;
forbidden channels = NONE OBSERVED;
canonical/PALACE mutation = NONE.
```

## 5. Final classification

```text
primary_class = EVIDENCE_INFRASTRUCTURE_DEFECT;
secondary_label = D002_REPLAY_ADAPTER_UNRESOLVED_INPUT_DEFECT.
```

Because `D002_MANIFEST_ADAPTER_CLOSURE = PASS`, this failure must not be
classified as another manifest wiring omission. The exact adapter exception was
not captured in the write-once replay record. Since rerun is prohibited, the
precise internal exception cannot be recovered without a new authorization.

The evidence does not implicate PALACE representation semantics, typed mapping
semantics, Decision Core semantics, Carrier semantics, or observer semantics.

## 6. Stop rule

The final campaign budget is exhausted. No rerun, repair-run, evidence rewrite,
or automatic follow-up is authorized.

## 7. Record integrity

This Record is registered by the canonical commit introducing it. Attempt-001,
Attempt-002, and Attempt-003 evidence remain write-once.
