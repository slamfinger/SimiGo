# Cross-model Pre-runtime Comparative Observation

Date: 2026-10-05<br>
Status: `STATIC PRE-RUNTIME COMPARISON ONLY / NO J3 SCORING / NO 846 MAPPING / NO RUNTIME`

## 1. Purpose

This artifact compares already-existing Round-1 and cross-model pilot
observations in order to select observable dimensions and candidate phenomena
for the future formal 16-cell run.

It does **not**:

```text
assign J3 PASS/FAIL;
declare stable invariants;
perform semantic normalization;
score cross-model stability;
map to 846;
authorize runtime.
```

## 2. Evidence streams

### Round 1 — formal, complete

```text
17 / 17 arms valid JSON;
isolation enforced;
TC-A release-gate scope only.
```

Bounded observations:

```text
R-D2 raw / decoded-text / semantic-object = PASS / PASS / PASS;
M2 deleted = FAIL;
M1 all or gamma-only with M2.b = PASS;
M1 absent = FAIL;
explanation presence failed in this run;
source-hash/tool-evidence variants showed no stable rescue.
```

### Cross-model — pilot only, incomplete

The current raw stream contains 11 final-answer files:

```text
Model A: S1, S2, S3, S4;
Model C: S1, S2, S3, S4;
Model D: S1, S2, S3;
Model B: no final answers.
```

Raw parse inventory:

```text
strict JSON                   = 3;
markdown-fence-strippable JSON = 2;
invalid / degenerate           = 6.
```

The aggregate runner record tracks only four Model-C cells. The stream is
therefore incomplete and inconsistent. Runtime isolation was not enforced, so
these outputs are candidate-generation material only.

## 3. Observation dimensions

| ID | Dimension | Question |
|---|---|---|
| D1 | Task outcome presence | Is there an identifiable decision or explicit failure? |
| D2 | Key-decision structure | Does the required decision type appear? |
| D3 | Required-information presence | Are minimal facts/evidence present? |
| D4 | Relation/conjunction formation | Are separate facts combined into the needed relation? |
| D5 | Representation compliance | Is strict JSON satisfied without repair? |
| D6 | Explanation sensitivity | Does explanation change decision/order/output viability? |
| D7 | Provenance/tool sensitivity | Does process evidence affect immediate behavior? |
| D8 | Uncertainty boundary | Is missing or uncertain evidence preserved? |
| D9 | Degradation mode | Is failure truncation, fencing, repetition, schema drift, or contradiction? |

## 4. Candidate phenomena

| ID | Candidate | Observation |
|---|---|---|
| CI-A | Task-relative decision skeleton | Nondegenerate outputs attempt a sample-specific decision; degenerate outputs do not. |
| CI-B | Evidence-grounded findings | Valid outputs usually attach source-grounded evidence; truncated/degenerate outputs cannot support that reading. |
| CI-C | Relation/conjunction dependence | Round 1 shows the S1 continuation needs gamma baseline decision plus pair decisions; isolated fields failed. S1 pilot models also disagree on relation interpretation. |
| CI-D | Representation/semantics separation | Some semantically plausible outputs fail strict JSON due to fencing or truncation. |
| CI-E | Long/high-complexity degradation | Model A is strict-valid on short S1/S3 but truncated on longer S2/S4; Model C wraps output and drifts schema; Model D degenerates. |
| CI-F | Explanation/provenance not obviously core | Round 1 gives no stable rescue from explanation, source hashes, or tool evidence. |

These are candidate observations only.

## 5. What formal 16 cells should prioritize observing

```text
D1 task outcome presence;
D2 normalized decision class, not wording;
D3 minimal fact/evidence presence;
D4 relation/conjunction formation;
D5 strict JSON and schema compliance;
D9 failure-mode classification.
```

No J3 score is assigned here.

## 6. Relation to 846

This comparison does not map or rewrite 846.

It only suggests that many fine-grained atoms may later group into a small set of
observable macro-functions:

```text
task framing / projection;
semantic decision;
constraint and relation application;
evidence grounding;
uncertainty/absence boundary;
representation contract compliance.
```

Whether that grouping survives formal cross-model observation remains open.

## 7. Boundary

```text
Formal runtime             = NOT AUTHORIZED;
Observer                   = NOT RUN;
InformationCore store      = NOT RUN;
semantic normalization     = NOT PERFORMED;
J1/J2/J3 scoring           = NOT PERFORMED;
stability matrix           = NOT PERFORMED;
vertical decomposition     = NOT PERFORMED;
846 mapping                = NOT PERFORMED.
```
