# R-C1 Attempt #4 Result

Date: 2026-10-03  
Status: `R-C1 #4 COMPLETED / LAYER 1 PRESERVED / LAYER 2 VALID / CONSEQUENCE REVIEW COMPLETE`  
Implementation baseline: `569fe540d1ff`  
Run root:
`docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375`

## 1. Layer 1 — Evidence integrity

```text
EVIDENCE INTEGRITY = PRESERVED
Lifecycle reconstructable = true
Old/fresh evidence separated = true
Physical change preserved = true
Carrier separation preserved = true
Forbidden-channel runtime checks failed = none
Implementation changed during run = false
Protocol changed during run = false
```

## 2. Layer 2 — Frozen protocol result

```text
Execution integrity = VALID

C-A = COMPLETED / PARTIAL SUCCESS
  X-1 = PASS
  X-2 = FAIL
  X-3 = FAIL
  X-4 = FAIL
  X-5 = FAIL

C-B = COMPLETED / FULL SUCCESS
  X-1…X-5 = PASS

C-C = COMPLETED / FULL SUCCESS
  X-1…X-5 = PASS
```

C-C used the persisted Relation path:

```text
I-S1 ──observed-change-of──> I-S0
```

The staged C-C validator accepted the run. No fallback to C-B's independent
Information path occurred.

## 3. Layer 3 — Bounded research observation

Within this fixed task, harness, lifecycle slice, and evidence boundary:

```text
C-A without persistent Information Space:
  only task identity recovered; state/change/action recovery failed.

C-B with persistent Information:
  full continuation recovered by independent Information path.

C-C with persistent Information + Relation:
  full continuation recovered through the Relation carrier path.
```

Therefore, this run supplies task-domain-bounded evidence that persistent
Information Space distinguished C-A from C-B/C-C. In this single-change task,
the persistent Relation carrier did not add measured continuation capability
beyond C-B's independent Information path, while C-C did demonstrably use its
Relation path.

This observation is not a universal Agent-memory claim, not a PALACE schema
claim, and not proof that Relation carriers are generally unnecessary.

## 4. Layer 3 — Formal bounded observations

### O1 — bounded positive observation

```text
In the fixed task / harness / lifecycle slice, C-A state-only restoration
recovered X-1 but failed X-2…X-5. Persistent Information enabled C-B to
recover X-1…X-5.
```

Bounded reading:

```text
Runtime state alone was insufficient for full semantic continuation.
Persistent Information outside the restored runtime execution state enabled
the full continuation sequence.
```

### O2 — bounded negative / undifferentiated observation

```text
C-B with independent persistent Information achieved full continuation.
C-C with persistent Information plus a persisted Relation carrier also achieved
full continuation through its Relation path.
```

Bounded reading:

```text
No additional continuation capability was observed for the Relation carrier
beyond independent persistent Information in this single-change task.
```

This is not evidence that Relation carriers are generally unnecessary; the task
did not discriminate a case requiring Relation beyond independent Information.

## 5. Research closure

```text
O1 = SUPPORTED / TASK-DOMAIN-BOUNDED
O2 = NOT OBSERVED / NOT A GENERAL NECESSITY CLAIM
Evidence/result audit = PASS
C-Design impact review = PASS / NO AMENDMENT
R-C1 #4 = CLOSED / VALID / EVIDENCE PRESERVED / OBSERVATIONS SEALED
```

Formal records:

```text
SIMIGO_LAB_RC1_ATTEMPT4_RESEARCH_INTERPRETATION_RECORD_20261003.md
SIMIGO_LAB_RC1_ATTEMPT4_EVIDENCE_RESULT_AUDIT_20261003.md
SIMIGO_LAB_C_DESIGN_IMPACT_REVIEW_20261003.md
```

## 6. Gate result

```text
B Track   = CLOSED
C Gate    = OPEN
C-Spec    = FROZEN / HUMAN RE-AUDIT PASS
C-Design  = CONFIRMED / HUMAN RE-AUDIT PASS WITH CONDITION
C-Impl    = D-4 REVISION AUDIT PASS
C-Execute = AUTHORIZED / CONSUMED
R-C1 #1   = STOPPED / INVALID INCONCLUSIVE
R-C1 #2   = STOPPED / INVALID INCONCLUSIVE
R-C1 #3   = STOPPED / INVALID INCONCLUSIVE
R-C1 #4   = COMPLETED / VALID / EVIDENCE PRESERVED
```


## 7. Consequence review — COMPLETE

`SIMIGO_LAB_BOUNDARY_SYNTHESIS_CONSEQUENCE_REVIEW_20261003.md` records the
post-H1…H3 consequences. R-C1 #4 remains valid and preserved; C Gate is paused
for the next separate gate decision.
