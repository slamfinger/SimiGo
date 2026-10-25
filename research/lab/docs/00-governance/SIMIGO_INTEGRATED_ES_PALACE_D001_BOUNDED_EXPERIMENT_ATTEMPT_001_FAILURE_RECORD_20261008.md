# Integrated ES–PALACE D-001 Bounded Experiment Attempt 001 Failure Record

> **Status:** EXECUTED / FAIL / WRITE-ONCE EVIDENCE RETAINED / NO RERUN
> **Date:** 2026-10-08
> **Manifest instance:** `76F0DD14-3FFF-4B1F-B56C-2EE71321A5B8`
> **Execution head:** `1023b1332b3d2d366b163b39ff84af0a702912b8`

## 1. Campaign consumption

```text
experiment runs        = 1 / 1 CONSUMED;
observer campaigns     = 1 / 1 CONSUMED;
repairs                = 0;
reruns                 = 0;
canonical IS mutation  = NONE;
E9                     = NOT AUTHORIZED / NOT EXECUTED;
EXP-004                = NOT AUTHORIZED / NOT EXECUTED.
```

The evidence parent is:

```text
docs/02-evidence/integrated-es-palace-d001-bounded-experiment-v1/
```

`EVIDENCE_SHA256SUMS` verified all five preceding evidence objects.

## 2. Outcome

```text
EXPERIMENT_RECORD        = FAIL;
OBSERVER_RECORD          = PASS;
RECONCILIATION_RECORD    = FAIL;
CLAIM_RECORD             = FAIL.
```

The independent observer reconciled all seven decisions:

```text
P-LAWFUL     = CONTINUE;
P-SETTLED    = REUSE;
P-BLOCKED    = BLOCK;
N-MISSING    = MISSING_INFORMATION_BLOCK;
N-STALE      = STALE_INFORMATION_BLOCK;
N-AMBIGUOUS  = AMBIGUOUS_INFORMATION_BLOCK;
N-ILLEGAL    = ILLEGAL_CONTINUATION_BLOCK.
```

All observer checks reported:

```text
inventory_complete       = true;
invocation_closed        = true;
side_channels_denied     = true;
forbidden_channels_observed = false;
canonical_is_mutated     = false.
```

## 3. Failure classification

The experiment comparator compared the four negative cases against coarse
`EXPECTED.decision = BLOCK`, while the experiment correctly emitted the
pre-registered specific typed labels:

```text
MISSING_INFORMATION_BLOCK;
STALE_INFORMATION_BLOCK;
AMBIGUOUS_INFORMATION_BLOCK;
ILLEGAL_CONTINUATION_BLOCK.
```

This is a bounded campaign harness comparator defect. It does not indicate
Carrier semantic failure, PALACE failure, observer disagreement, forbidden
channel influence, canonical IS mutation, E9 activity, or EXP-004 activity.

## 4. Stop rule

The authorization allowed exactly one experiment and one observer campaign. No
rerun, repair-run, or new campaign is authorized by Attempt 001. A new Human
authorization would be required before any correction rerun.

## 5. Record integrity

This Record is registered by the canonical commit introducing it. The failed
evidence is retained unchanged.
