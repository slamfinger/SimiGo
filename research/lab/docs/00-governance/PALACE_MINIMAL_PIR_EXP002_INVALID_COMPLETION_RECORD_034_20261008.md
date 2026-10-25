# PALACE — MINIMAL-PIR-EXP-002 Invalid Completion Record 034

> **Status:** RAW INVALID COMPLETION — HUMAN EVIDENCE AUDIT NOT OPEN
> **Date:** 2026-10-08
> **Experiment:** MINIMAL-PIR-EXP-002
> **Authorization commit:** `ff051483343a24025cd25347d03b4f1a4e3d8e32`
> **Execution commit:** same canonical execution commit

## 1. Disposition

MINIMAL-PIR-EXP-002 is **INVALID / NON-ADJUDICATIVE**. The corrected EV-P08
persistence path worked and E-L completed all 20 bounded physical
reconciliations, but fail-closed evaluation found one false-negative MOVE.

```text
outcome = FAIL_CLOSED / INVALID / NON-ADJUDICATIVE;
stop_code = MINIMAL_PIR_EXPERIMENT_ASSERTION_FAILURE;
root_cause_class =
  HARNESS_FIXTURE_MEASURED_REGISTRY_POST_CHANGE_SNAPSHOT_DEFECT.
```

## 2. Exact evidence

```text
fresh fixture = E-L;
accepted Information Scope = 20/20;
physical observations = 20;
physical checks = 20;
W_obs_age = PASS;
W_latency = 140ms / PASS;
oracle planted changes = 5;
true positives = 4;
false negatives = 1;
false positives = 0;
Fresh Closure = structurally complete but experiment assertion FAIL.
```

The failed predicate was the registered `PC-MOVE`:

```text
stable object = dcaacd34cd0835802e3b218f2520d9d3b5377df3dfe950aed701a120c8ac6d0d;
oracle old locator = objects/f70fc1c8823ef46a448f55f2466df123e15e2bf911e03989be4a9948c0841f55.json;
post-change locator = objects/dcaacd34cd0835802e3b218f2520d9d3b5377df3dfe950aed701a120c8ac6d0d.moved.json;
observed verdict = FRESH_WITHIN_WINDOW;
expected verdict = PHYSICALLY_MOVED.
```

## 3. Root cause

Fixture preparation wrote the post-change registry record with `record.locator`
already updated to the moved destination. Therefore the measured path received
the destination as if it were the current lawful registered locator, erased the
old-to-new reconciliation problem, and classified the destination as fresh.

This is a fixture/measured-registry snapshot binding defect. It is not a PIR
semantic defect, physical filesystem misuse, oracle leakage, IS mutation, or
EQ/REJ criteria defect.

## 4. Evidence disposition

E-L observations and the structurally complete Fresh Closure are raw,
non-authoritative evidence only. The one MOVE was not correctly adjudicated, so
the experiment cannot be promoted to PASS.

## 5. Budget disposition

```text
E8-style corrected experiment budget = CONSUMED;
physical observation budget          = CONSUMED;
evidence budget                      = CONSUMED BY FAIL-CLOSED ATTEMPT;
E-S / no-change execution            = NOT REACHED;
repair                               = NOT AUTHORIZED;
rerun                                = NOT AUTHORIZED;
renewal                              = FORBIDDEN.
```

## 6. Claim disposition

```text
bounded PIR effectiveness        = NOT ESTABLISHED;
move/rename reconciliation proof = NOT ESTABLISHED;
PIR performance theorem          = NOT ESTABLISHED;
PALACE equivalence               = NOT ESTABLISHED;
integrated SimiGo proof          = NOT ESTABLISHED.
```

## 7. Next lawful object

The next lawful object is Human evidence audit of INVALID EXP-002. If further
work is proposed, it requires a new independently budgeted Request scoped to
fixture/measured-registry pre-change snapshot preservation and a potential
future run. Stopping is a lawful research outcome.

## 8. Record integrity

```text
record_integrity_binding = registered by the canonical commit introducing this
record; later modification creates a new content address and voids this
completion record.
```
