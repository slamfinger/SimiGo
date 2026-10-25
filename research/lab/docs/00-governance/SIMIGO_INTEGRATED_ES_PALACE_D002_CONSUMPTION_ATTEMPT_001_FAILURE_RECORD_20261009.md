# D-002 Consumption Attempt-001 Failure Record

> **Status:** EXECUTED / FAIL / WRITE-ONCE EVIDENCE RETAINED / NO RERUN
> **Date:** 2026-10-09
> **Manifest instance:** `A77A50E2-A9F9-445C-882F-6475474900F4`
> **Execution head:** `214661ad`

## 1. Budget consumption

```text
decision replay      = 1 / 1 CONSUMED;
bounded experiment   = 1 / 1 CONSUMED;
observer campaign    = 1 / 1 CONSUMED;
repair runs          = 0;
reruns               = 0;
canonical IS mutation = NONE;
PALACE source mutation = NONE;
E9                   = NOT EXECUTED / NOT AUTHORIZED;
EXP-004              = NOT EXECUTED / NOT AUTHORIZED.
```

Evidence parent:

```text
docs/02-evidence/integrated-es-palace-d002-consumption-v1/
```

`EVIDENCE_SHA256SUMS` verified all seven preceding evidence objects.

## 2. Outcome

```text
DECISION_REPLAY_RECORD   = PASS / REPLAY EXECUTED;
EXPERIMENT_RECORD        = FAIL / VECTOR NOT RECONCILED;
CARRIER_LIFECYCLE_RECORD = PASS / 7 RECORDS PERSISTED;
OBSERVER_RECORD          = PASS / INDEPENDENT EXECUTION;
RECONCILIATION_RECORD    = FAIL;
CLAIM_RECORD             = FAIL.
```

Source and snapshot remained bound:

```text
PALACE source SHA-256 =
  3f790600bfa0ebb0eb7bd4e9f28ac1b6353bd6802d5eeb8f964e7edb8861bf0a;
prepared snapshot SHA-256 =
  8b3856e2e4e3a1bd87580afc1ab42094e9a952e0985952323e02ae6595ce1444.
```

## 3. Failure classification

Two independent evidence-infrastructure defects caused the FAIL:

```text
D002_REPLAY_ADAPTER_CLOSURE_DIGEST_BINDING_DEFECT;
D002_OBSERVER_BOUNDARY_DIGEST_COMPARATOR_DEFECT.
```

The replay adapter computed the translated D-001 closure digest while its own
placeholder `closure_digest` was still present. The unchanged D-001 Decision
Core therefore correctly fail-closed six otherwise resolvable cases to
`MISSING_INFORMATION_BLOCK`. This is not a Decision Core semantic defect.

The observer comparator compared the generated structured boundary digest with a
different raw-string digest derivation, causing five lawful/blocked cases to be
misobserved as illegal. This is an observer comparator defect, not PALACE
mutation or forbidden-channel influence.

The `N-MISSING` case passed. Carrier persisted all seven identity records. No
forbidden channel was observed and no canonical/PALACE mutation occurred.

## 4. Non-defects

```text
PALACE representation          = NOT IMPLICATED;
snapshot integrity/consistency = NOT IMPLICATED;
D-001 Decision Core semantics  = NOT IMPLICATED;
Carrier semantics              = NOT IMPLICATED;
forbidden-channel compromise   = NOT OBSERVED;
canonical/PALACE mutation      = NOT OBSERVED.
```

## 5. Stop rule

The authorization allowed exactly one replay, one experiment, and one observer
campaign. All budgets are consumed. No rerun or repair-run is authorized.

## 6. Record integrity

Attempt-001 evidence is write-once. This Record is registered by the canonical
commit introducing it.
