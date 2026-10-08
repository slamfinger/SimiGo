# D-002 Consumption Attempt-002 Failure Record

> **Status:** EXECUTED / FAIL / WRITE-ONCE EVIDENCE RETAINED / NO RERUN
> **Date:** 2026-10-09
> **Manifest instance:** `D1326CC7-6A02-43B6-A169-717EBB777864`
> **Execution head:** `3b34eaac`

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
docs/02-evidence/integrated-es-palace-d002-consumption-attempt-002/
```

`EVIDENCE_SHA256SUMS` verified all seven preceding evidence objects.

## 2. Entry gates

All four newly required gates passed before budget consumption:

```text
correction_scope_clean      = true;
D001_CORE_DIGESTS_UNCHANGED = true;
FIXTURE_EXPECTED_UNCHANGED  = true;
SNAPSHOT_SOURCE_BINDINGS    = true.
```

The D-001 core digests remained:

```text
schemas.py        = a226522c60bb4352494d01992f09c34f546e56839c19de64440ec40449296216;
inventory.py      = 39508edee8826e9728d48ccb4f8a7c430890c7b5349d1424aaf10a756c071a27;
reconstruction.py = 78af949080c48a8ae01e015cded42464c4e970f94470e2c305e825b7b2c95b41;
continuation.py   = c4af004dbb8993cbaee40b145a95ae41c185e63d34316c574f85c2a3cb98038b;
carrier.py        = b377e8b5a933d5f9e4b3859f1dd0716be6d42df4634429c2378251c45f286e2e.
```

Source and snapshot remained:

```text
source   = 3f790600bfa0ebb0eb7bd4e9f28ac1b6353bd6802d5eeb8f964e7edb8861bf0a;
snapshot = 8b3856e2e4e3a1bd87580afc1ab42094e9a952e0985952323e02ae6595ce1444.
```

## 3. Outcome

```text
DECISION_REPLAY_RECORD   = PASS / EXECUTED;
EXPERIMENT_RECORD        = FAIL;
CARRIER_LIFECYCLE_RECORD = PASS / 7 RECORDS PERSISTED;
OBSERVER_RECORD          = PASS;
RECONCILIATION_RECORD    = FAIL;
CLAIM_RECORD             = FAIL.
```

The corrected observer independently produced the expected seven classifications:

```text
P-LAWFUL     = CONTINUE;
P-SETTLED    = REUSE;
P-BLOCKED    = BLOCK;
N-MISSING    = MISSING_INFORMATION_BLOCK;
N-STALE      = STALE_INFORMATION_BLOCK;
N-AMBIGUOUS  = AMBIGUOUS_INFORMATION_BLOCK;
N-ILLEGAL    = ILLEGAL_CONTINUATION_BLOCK.
```

Thus Attempt-001's observer comparator defect is corrected.

## 4. Remaining failure classification

```text
D002_RUN_MANIFEST_PACKAGE_BINDING_OMISSION_DEFECT.
```

The Attempt-002 Run Manifest lacked top-level `package_binding` and `package_id`
fields required by the replay adapter's I6 translation. The unchanged D-001
Decision Core therefore correctly fail-closed six otherwise resolvable cases to
`MISSING_INFORMATION_BLOCK`. `N-MISSING` passed.

This is an evidence-infrastructure manifest configuration defect. It is not a
PALACE representation defect, typed mapping semantic defect, Decision Core
defect, Carrier defect, observer defect, forbidden-channel compromise, or
canonical/PALACE mutation.

## 5. Stop rule

The Attempt-002 authorization allowed exactly one replay, one experiment, and one
observer campaign. All budgets are consumed. No rerun or repair-run is
authorized.

## 6. Record integrity

Attempt-001 and Attempt-002 evidence remain write-once. This Record is registered
by the canonical commit introducing it.
