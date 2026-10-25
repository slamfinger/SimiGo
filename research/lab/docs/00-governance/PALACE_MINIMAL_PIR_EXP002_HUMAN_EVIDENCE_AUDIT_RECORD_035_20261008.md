# PALACE — MINIMAL-PIR-EXP-002 Human Evidence Audit Record 035

> **Status:** CLOSED — HUMAN EVIDENCE AUDIT PASS WITH ONE ISOLATED FIXTURE
> SNAPSHOT DEFECT; EXPERIMENT REMAINS INVALID / NON-ADJUDICATIVE
> **Date:** 2026-10-08
> **Experiment:** MINIMAL-PIR-EXP-002
> **Authorization commit:** `ff051483343a24025cd25347d03b4f1a4e3d8e32`
> **Invalid completion record:** `8bdf99f...`
> **Audit base:** `530ab7534464beba89a00d30fca61b2bfb24bf5e`

## 1. Four-point audit ruling

```text
1. EV-P08 recorder regression        = NONE / PASS;
2. MOVE causal chain                 = fixture/measured-registry snapshot defect;
3. broader fixture/oracle pollution  = NONE;
4. promotable equivalence evidence   = NONE.
```

The experiment remains **INVALID / NON-ADJUDICATIVE** because the pre-registered
MOVE case was a false negative.

## 2. Check 1 — EV-P08 correction held

```text
EV-P08 physical observations = 20/20 persisted;
format = compact JSONL, one JSON object per line;
line count = record count = 20;
parse = PASS;
physical observations generated during preparation = 0;
IS mutations = 0.
```

The EXP-001 bytes-to-text persistence defect did not recur.

## 3. Check 2 — MOVE causal chain

The defect occurred before the measured registry was serialized:

```text
fixture builder created the pre-change record;
fixture builder performed the planted move in current physical state;
fixture builder updated record.locator to the destination;
fixture builder then built measured_registry from the mutated records;
measured path therefore received only the post-change destination;
reconciliation saw a registered, digest-matching destination;
reconciliation classified it FRESH_WITHIN_WINDOW instead of PHYSICALLY_MOVED.
```

Exact chain:

```text
oracle old locator =
  objects/f70fc1c8823ef46a448f55f2466df123e15e2bf911e03989be4a9948c0841f55.json;
oracle new locator =
  objects/dcaacd34cd0835802e3b218f2520d9d3b5377df3dfe950aed701a120c8ac6d0d.moved.json;
measured registry locator = oracle new locator;
observed locator = oracle new locator;
observed verdict = FRESH_WITHIN_WINDOW;
expected verdict = PHYSICALLY_MOVED.
```

Therefore the lost fact was the **pre-change locator**. This was not candidate
discovery failure: the destination candidate was present. It was not
deterministic-correlation failure: correlation was unnecessary because the
measured path no longer saw a missing old locator. It was not oracle leakage:
measured input contained no planted-change ledger. It was not PIR semantic-rule
or freshness-window failure: the destination matched registered digest, size and
age.

## 4. Check 3 — defect isolation

```text
PC-MODIFY content #1 = detected PHYSICALLY_CHANGED;
PC-MODIFY content #2 = detected PHYSICALLY_CHANGED;
PC-MODIFY metadata   = detected PHYSICALLY_CHANGED;
PC-DELETE            = detected PHYSICALLY_DELETED;
PC-MOVE              = FALSE NEGATIVE;
PC-CREATE            = NOT EXERCISED / DEFERRED BY FROZEN DESIGN.
```

No oracle leakage was found. The measured registry source contained no
planted-change ledger, planned-change list, oracle data, fixture role or
expected-verdict field. No unrelated object was materially inspected or updated.
The failure is therefore an isolated fixture/measured-registry snapshot defect,
not evidence of broad fixture architecture corruption.

## 5. Check 4 — accepted raw facts versus forbidden promotion

Accepted raw execution facts:

```text
20/20 physical observations persisted;
all observations were compact JSONL records;
W_obs_age = PASS for all accepted objects;
W_latency = 140ms / PASS against 5,000ms;
Fresh Closure structure = COMPLETE;
false-positive physical changes = 0;
three PC-MODIFY observations = persisted raw facts;
one PC-DELETE observation = persisted raw fact;
one PC-MOVE destination observation = persisted raw fact but wrong adjudication.
```

Not established:

```text
PC-MOVE reconciliation = NOT ADJUDICATED;
PIR effectiveness = NOT ESTABLISHED;
MOVE/RENAME proof = NOT ESTABLISHED;
PIR performance theorem = NOT ESTABLISHED;
PALACE equivalence = NOT ESTABLISHED;
integrated SimiGo proof = NOT ESTABLISHED.
```

The four correct outcomes cannot be combined to repair or promote the missing
MOVE adjudication.

## 6. Root-cause classification

```text
root_cause_class =
  HARNESS_FIXTURE_MEASURED_REGISTRY_POST_CHANGE_SNAPSHOT_DEFECT.
```

More precisely, fixture preparation mutated the authoritative object record
before constructing the measured registry, erasing the pre-change locator needed
to adjudicate old-to-new movement.

## 7. Boundary attribution

```text
PIR semantic model        = NOT DEFECTIVE IN THIS STOP;
Physical Scope discovery  = NOT DEFECTIVE IN THIS STOP;
deterministic correlation = NOT REACHED FOR MOVE / NOT DEFECTIVE;
freshness rule            = NOT DEFECTIVE IN THIS STOP;
oracle                    = NO LEAKAGE;
Information Space         = NO MUTATION;
CarrierSQLite / E8 ruling = UNCHANGED;
EQ/REJ criteria           = UNCHANGED.
```

## 8. Artifact bindings

```text
EV-P08 observations SHA256 =
  36ae035cc92256fdd57f024432873f6fa702d91b3def0cdddea9043c4ff549e1;
W_obs_age calculations SHA256 =
  9668ba6b2dd9dc2d1fce432b2f922f3c4c2a9a15c51e544fe31b4fcfee1473d7;
W_latency calculations SHA256 =
  9adc99a7570ee5f45c47948790e9a22959c5a1d9b7c29dc2956b488a5871c37b;
Fresh Closure SHA256 =
  b0e0731ebb82f081d5ede8b583ae466de596ce3c990010962e23d684512f2eae;
evaluation join SHA256 =
  032804fe941119e690778644be225d0779f3e0ff4db60bd31cde49d38494f6f8;
MOVE correlation evidence SHA256 =
  ba95784a30f52fc7c7ee7389affa08fd45ae4ae1be373afc038c8fba7b552051;
authorized fixture measured input SHA256 =
  a0e136dc9c144fc6f80c25be6ca8335ba6431a8c25b364a72474cff8d4539124;
oracle ledger SHA256 =
  b70a953db032e81d9d62d88c65dedc1aff6958e076e6c48b544df7e2f35aedb3.
```

## 9. Next lawful object

The next lawful object is an explicit Human strategic decision:

```text
DENY further PIR work; or
authorize a new independently budgeted Request scoped to
fixture/measured-registry pre-change snapshot preservation and targeted
fixture validation.
```

A future corrected run, if ever authorized, would require fresh fixtures and a
separate Experiment Launch Review. This audit neither authorizes repair, EXP-003,
fixture regeneration, run execution, nor scope broadening.

## 10. Record integrity

```text
record_integrity_binding = registered by the canonical commit introducing this
record; later modification creates a new content address and voids this audit
closure.
```
