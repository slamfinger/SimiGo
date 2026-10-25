# PALACE — MINIMAL-PIR-EXP-003 Invalid Completion Record 038

> **Status:** RAW INVALID COMPLETION — HUMAN EVIDENCE AUDIT NOT OPEN
> **Date:** 2026-10-08
> **Experiment:** MINIMAL-PIR-EXP-003
> **Authorization/execution commit:** `515ae2ee14c486313809dd33aac811e52e1e4e84`

## 1. Disposition

MINIMAL-PIR-EXP-003 is **INVALID / NON-ADJUDICATIVE**. The corrected EV-P08
recorder worked, and E-L completed all 20 bounded physical observations with
passing freshness windows, but fail-closed evaluation found one false-negative
PC-MOVE.

```text
outcome = FAIL_CLOSED / INVALID / NON-ADJUDICATIVE;
stop_code = MINIMAL_PIR_STALE_FIXTURE_PRECHANGE_SNAPSHOT_DEFECT;
root_cause_class = HARNESS_FIXTURE_STALE_PRECHANGE_SNAPSHOT_ARTIFACT_DEFECT.
```

## 2. Exact cause

Request v2.7 corrected the fixture builder and validated newly generated
fixtures, but the committed E-L measured fixture used by EXP-003 was not
regenerated after that correction. Therefore its measured registry lacked the
preserved `pre_change_locator`.

The MOVE destination existed and matched content/size, but the measured path saw
it as the current registered locator rather than as a moved destination. It was
classified:

```text
FRESH_WITHIN_WINDOW
```

instead of:

```text
PHYSICALLY_MOVED
```

This is a stale fixture artifact / release-selection defect. It is not PIR
semantic inference, oracle leakage, IS mutation, CarrierSQLite regression, or an
EQ/REJ criteria defect.

## 3. Raw facts

```text
E-L accepted scope = 20/20;
physical observations = 20;
physical checks = 20;
W_obs_age = PASS;
W_latency = PASS;
oracle planted changes = 5;
true positives = 4;
false negatives = 1 (PC-MOVE);
false positives = 0;
Fresh Closure structure = COMPLETE but non-authoritative after failed assertion.
```

The missed MOVE:

```text
stable object =
  dcaacd34cd0835802e3b218f2520d9d3b5377df3dfe950aed701a120c8ac6d0d;
oracle old locator =
  objects/f70fc1c8823ef46a448f55f2466df123e15e2bf911e03989be4a9948c0841f55.json;
oracle new locator =
  objects/dcaacd34cd0835802e3b218f2520d9d3b5377df3dfe950aed701a120c8ac6d0d.moved.json;
observed verdict = FRESH_WITHIN_WINDOW;
expected verdict = PHYSICALLY_MOVED.
```

## 4. Evidence disposition

E-L observations and the structurally complete Fresh Closure are raw,
non-authoritative evidence. They cannot be promoted because the pre-registered
MOVE assertion failed.

The stale measured fixture proves that the v2.7 correction implementation exists
but was not connected to the executed fixture artifact. It does not authorize
repair, rerun, or selective evidence promotion.

Post-stop process/stderr captures are failure evidence only.

## 5. Claim disposition

```text
bounded PIR effectiveness        = NOT ESTABLISHED;
MOVE/RENAME reconciliation proof = NOT ESTABLISHED;
PIR performance theorem          = NOT ESTABLISHED;
PALACE equivalence               = NOT ESTABLISHED;
integrated SimiGo proof          = NOT ESTABLISHED.
```

## 6. Budget disposition

```text
MINIMAL-PIR-EXP-003 experiment budget    = CONSUMED;
physical observation budget              = CONSUMED;
evidence budget                          = CONSUMED BY FAIL-CLOSED ATTEMPT;
E-S / no-change execution                = NOT REACHED;
IS mutation                              = NONE;
repair                                   = NOT AUTHORIZED;
rerun                                    = NOT AUTHORIZED;
renewal                                  = FORBIDDEN.
```

## 7. Next lawful object

The next lawful object is Human evidence audit of INVALID EXP-003. Given the
repeated evidence-infrastructure failures, the Human may reasonably choose to
stop or to authorize a tightly scoped release-process correction. Any future
execution requires a new independent budget and explicit authorization.

## 8. Record integrity

```text
record_integrity_binding = registered by the canonical commit introducing this
record; later modification creates a new content address and voids this
completion record.
```
