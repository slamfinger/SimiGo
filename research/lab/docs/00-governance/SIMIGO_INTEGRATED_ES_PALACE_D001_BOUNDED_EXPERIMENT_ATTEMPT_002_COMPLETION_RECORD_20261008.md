# D-001 Bounded Experiment Attempt-002 Completion Record

> **Status:** COMPLETE / BOUNDED EXPERIMENT + OBSERVER CAMPAIGN PASS
> **Date:** 2026-10-08
> **Completion ID:** `D001-BOUNDED-EXPERIMENT-ATTEMPT-002-COMPLETION-001`
> **Manifest instance:** `22A88D7B-E036-4578-9616-CB66DFD649CB`
> **Execution head:** `9676db65fd3b9bb2f85733eeb91b8420f7e2d12f`

## 1. Final result

```text
EXPERIMENT_RECORD                 = PASS;
OBSERVER_RECORD                   = PASS;
RECONCILIATION_RECORD             = PASS;
CLAIM_RECORD                      = PASS;
seven-case reconciliation         = PASS;
Carrier persistence               = PERSISTED / 7 records;
forbidden channels observed       = NONE;
canonical IS mutation             = NONE;
Decision Core semantic change     = NONE;
fixture/pre-registration drift    = NONE;
observer semantic change          = NONE;
EVIDENCE_SHA256SUMS               = PASS / five evidence objects covered.
```

The new evidence parent is:

```text
docs/02-evidence/integrated-es-palace-d001-bounded-experiment-attempt-002/
```

Key evidence bindings:

```text
EXPERIMENT_RECORD.json SHA256 =
  b3ab01b02131e069d8437fcc0e06506eb6da9a2824b8eae34e8e7dbc26189282;
OBSERVER_RECORD.json SHA256 =
  2e7c1c86f666fa679de585d61e6deb40fad51ea18184fa869444551344ca81cf;
RECONCILIATION_RECORD.json SHA256 =
  26e1741315e66fcf5f63294fcacb51a7311989b274cc61c8cc5a6d4c9a72c9c2;
CLAIM_RECORD.json SHA256 =
  d84c9b9ca0c579163016fc3484a6538564dba8687f542e4fbb0d6b9874efed76;
EVIDENCE_SHA256SUMS SHA256 =
  c367cb47c4db6d1fa5018c74aeae49ffce667664361b69230cd0ffd45a2e78cd.
```

## 2. Frozen-vector reconciliation

The comparator used only the frozen three-component basis:

```text
top-level decision == expected.decision;
continuation_class == expected.continuation_class;
precedence_reason == expected.precedence_reason.
```

Observed cases:

```text
P-LAWFUL     = CONTINUE / SETTLED_CONTINUATION / LAWFUL_CURRENT_CONTINUATION;
P-SETTLED    = REUSE   / SETTLED_CONTINUATION / REUSE_PREDICATE_COMPLETE;
P-BLOCKED    = BLOCK   / BLOCKED_LAWFUL_CONTINUATION / REGISTERED_BLOCKING_CONDITION;
N-MISSING    = BLOCK   / BLOCKED_DEFECT / MANDATORY_OBJECT_UNRESOLVABLE;
N-STALE      = BLOCK   / BLOCKED_DEFECT / MANDATORY_EVIDENCE_SUPERSEDED;
N-AMBIGUOUS  = BLOCK   / BLOCKED_DEFECT / CONFLICTING_VALID_POINTERS;
N-ILLEGAL    = BLOCK   / BLOCKED_DEFECT / REGISTERED_BOUNDARY_VIOLATION_PROVEN.
```

The runner retained the more specific negative output representations while the
frozen coarse decision, continuation class, and precedence reason governed
pass/fail.

## 3. Bounded claim

For the pre-registered D-001 fixture configuration, Execution State produced the
seven pre-registered typed decisions and the independent observer reconciled
those decisions without forbidden-channel influence or canonical IS mutation.

This claim does not establish PALACE equivalence, integrated SimiGo proof, a
general Execution State theorem, production SimiGo validity, LLM autonomy, or
validity for arbitrary IS/ES states.

## 4. Budget and stop

```text
attempt-002 experiment runs = 1 / 1 CONSUMED;
attempt-002 observer campaigns = 1 / 1 CONSUMED;
repairs after entry = 0;
reruns = 0.
```

The campaign is closed. A separate Human decision is required for any follow-on.

## 5. Record integrity

This Record is registered by the canonical commit introducing it. Attempt-001
failure evidence and Attempt-002 pass evidence remain write-once.
