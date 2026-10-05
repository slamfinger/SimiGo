# Partial Cross-Model Matrix Report

Date: 2026-10-05  
Status: `PARTIAL SEMANTIC COMPARISON COMPLETE · NO 846 REMAPPING`

## Scope correction

The raw matrix contains **3 HTTP-success models × 4 samples = 12 outputs**.  
After the mechanical semantic-usability screen, only **2 models × 4 samples = 8 cells** enter normalization:

```text
A qwen3_moe        4/4 usable
C gemma4_unified   4/4 usable
B qwen3_next       0/4 available
D muse_glimmer     0/4 semantically usable despite HTTP 200
```

Therefore the correct scope is:

> **3-model × 4-sample raw partial matrix; 2-model × 4-sample semantic partial matrix.**

It is **not** a complete 4-model stability matrix.

## Quality exclusions

- `B qwen3_next`: runtime timeout / unavailable. Recorded only as an availability fact.
- `D muse_glimmer`: all four outputs are highly repetitive after HTTP 200. Raw output is preserved, but no semantic structure is extracted.

## Partial SM candidates

Only three process-level structures satisfy both cross-sample and partial cross-model stability:

1. `TASK_CONSTRAINT_BINDING`
2. `EVIDENCE_GROUNDING`
3. `DECISION_COMMITMENT`

These mean, respectively:

1. bind the task to an input-derived rule, hypothesis, scope, or comparison boundary;
2. connect claims to supplied evidence;
3. collapse observations into an explicit decision.

They are **candidates**, not established Information Core structures.

## Important non-candidates

`NUMERIC_RELATION_CHECK` is cross-sample but not cross-model in the current partial set.  
Models often differ in which numeric relation they select, whether they recompute it, and whether the resulting decision is consistent.

Content-level disagreement also remains high:

- S1: both see gamma constraints, but A releases gamma while C blocks gamma.
- S2: both see the management-expense change, but select different authoritative versions.
- S3: both see the `工程数量` header, but A supports and C rejects the 万元 hypothesis.
- S4: both find table-5 anomalies, but identify different anomaly types.

## Boundary

No 846 atom is mapped, merged, deleted, or rewritten.  
No minimal Information structure claim is made.  
No full cross-model stability claim is made.
