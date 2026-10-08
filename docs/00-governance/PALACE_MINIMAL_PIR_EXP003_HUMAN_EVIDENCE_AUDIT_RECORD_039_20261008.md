# PALACE — MINIMAL-PIR-EXP-003 Human Evidence Audit Record 039

> **Status:** CLOSED — THREE-POINT HUMAN EVIDENCE AUDIT PASS WITH RELEASE-SELECTION
> DEFECT; EXPERIMENT REMAINS INVALID / NON-ADJUDICATIVE
> **Date:** 2026-10-08
> **Experiment:** MINIMAL-PIR-EXP-003
> **Authorization/execution commit:** `515ae2ee14c486313809dd33aac811e52e1e4e84`
> **Invalid completion record:** `7b228ecd95b9ead7e176f8fcfc5e2b0bd3c1d5f5`
> **Audit base:** `eea90e6a0957d370904b0d5240fa4ece69010de8`

## 1. Ruling

EXP-003 remains **INVALID / NON-ADJUDICATIVE**. The failure is confirmed as a
narrow **stale committed fixture / release-selection defect**, not a v2.7
correction regression, PIR semantic defect, oracle leakage, IS mutation, or
EQ/REJ criteria defect.

```text
root_cause_class =
  HARNESS_FIXTURE_RELEASE_SELECTION_STALE_MEASURED_SNAPSHOT_DEFECT.
```

## 2. Check 1 — v2.7 correction and targeted validation remained correct

The v2.7 correction changed only:

```text
docs/02-evidence/es-is-20261005/PIR_RM001_IMPLEMENTATION/implementation/pir_probe.py;
docs/02-evidence/es-is-20261005/PIR_RM001_IMPLEMENTATION/implementation/minimal_pir_experiment.py.
```

The source retains the corrected pre-change snapshot behavior. The separate
targeted validation artifact reported:

```text
implementation self-check = PASS;
oracle isolation = PASS;
physical observations generated during preparation = 0;
IS mutations = 0;
E-L pre-change/post-change MOVE snapshot = PASS;
E-S pre-change/post-change MOVE snapshot = PASS.
```

Therefore no v2.7 correction regression occurred.

## 3. Check 2 — stale fixture release selection

EXP-003 selected the committed E-L measured fixture at:

```text
docs/02-evidence/es-is-20261005/PIR_RM001_IMPLEMENTATION/fixtures/E-L/measured_input.json.
```

That selected snapshot lacked `pre_change_locator` for the planted MOVE and
pointed directly at the post-change destination:

```text
selected registered locator =
  objects/dcaacd34cd0835802e3b218f2520d9d3b5377df3dfe950aed701a120c8ac6d0d.moved.json.
```

By contrast, the corrected v2.7 builder produces both:

```text
pre-change locator =
  objects/f70fc1c8823ef46a448f55f2466df123e15e2bf911e03989be4a9948c0841f55.json;
post-change locator =
  objects/dcaacd34cd0835802e3b218f2520d9d3b5377df3dfe950aed701a120c8ac6d0d.moved.json.
```

Thus:

```text
intended corrected fixture ≠ selected committed fixture.
```

The selected object identity, content hash and byte size were the same; only the
snapshot lineage was stale. The failure was release selection, not fixture
builder regeneration.

## 4. Check 3 — causal consequence

Because the measured registry no longer carried the pre-change locator, the
reconciliation path saw the moved destination as a current registered object:

```text
observed verdict = FRESH_WITHIN_WINDOW;
expected verdict = PHYSICALLY_MOVED.
```

Candidate discovery did not fail. Deterministic correlation was not erroneous. The
lost input was the pre-change locator required to recognize old-to-new movement.

## 5. Raw execution facts — accepted but non-adjudicative

```text
E-L accepted Information Scope = 20/20;
physical observations = 20;
W_obs_age = PASS for all objects;
W_latency = 137ms / PASS / limit 5,000ms;
oracle planted changes = 5;
true positives = 4:
  3 × PC-MODIFY;
  1 × PC-DELETE;
false negatives = 1 × PC-MOVE;
false positives = 0;
Fresh Closure structure = COMPLETE / NON-AUTHORITATIVE.
```

`PC-CREATE` was not exercised; it remains deferred by frozen design.

These are raw facts only. The 4/5 correct outcomes cannot repair or substitute for
the missing MOVE adjudication.

## 6. Evidence disposition

```text
PIR effectiveness                  = NOT ESTABLISHED;
MOVE/RENAME reconciliation proof   = NOT ESTABLISHED;
PIR performance theorem            = NOT ESTABLISHED;
PALACE equivalence                 = NOT ESTABLISHED;
integrated SimiGo proof            = NOT ESTABLISHED;
E8 bounded CarrierSQLite equivalence = ESTABLISHED / UNCHANGED.
```

Post-stop process/stderr captures are non-authoritative failure evidence.

## 7. Budget disposition

```text
EXP-003 experiment budget           = CONSUMED;
physical observation budget         = CONSUMED;
evidence budget                     = CONSUMED BY FAIL-CLOSED ATTEMPT;
E-S / no-change execution           = NOT REACHED;
IS mutation                         = NONE;
repair                              = NOT AUTHORIZED;
rerun                               = NOT AUTHORIZED;
renewal                             = FORBIDDEN.
```

## 8. Next lawful object

The next lawful object is an explicit Human strategic decision:

```text
STOP, retaining PIR = NOT ESTABLISHED and treating E3–EXP-003 raw execution
facts as research diagnostics; or

authorize a new independently budgeted Request scoped only to
release-process / fixture provenance correction and targeted validation.
```

Any future execution remains a separate explicit Human authorization. This audit
does not authorize EXP-004, fixture correction, release repair, rerun, or PIR
equivalence.

## 9. Record integrity

```text
record_integrity_binding = registered by the canonical commit introducing this
record; later modification creates a new content address and voids this audit
closure.
```
