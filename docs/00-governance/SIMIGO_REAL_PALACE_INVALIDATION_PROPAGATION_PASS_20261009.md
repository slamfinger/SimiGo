# Real PALACE Invalidation Propagation PASS

> **Status:** ISOLATED INVALIDATION / SELECTIVE RECOMPUTE PASS  
> **Date:** 2026-10-09  
> **Canonical base before change:** `0c7b989d701d2c5e2c13986ac3ecb8cebf586b0c`

## 1. Verified behavior

After the seven real PALACE-derived records were settled and reused, REAL-2 was
explicitly invalidated. The next real-source demand produced:

```text
REAL-1 = REUSE;
REAL-2 = COMPUTE;
REAL-3 = COMPUTE;
REAL-4 = COMPUTE;
REAL-5 = COMPUTE;
REAL-6 = COMPUTE;
REAL-7 = COMPUTE.
```

Thus invalidation propagated through the dependency closure while unaffected
REAL-1 remained reused.

## 2. Boundary

This isolated test does not mutate PALACE, canonical Information Space, D-001,
or D-002 evidence. It proves explicit invalidation and selective recomputation
for the retained real-source fixture graph only.

## 3. Evidence

```text
docs/02-evidence/execution-information-loop-vertical-slice-20261009/
  REAL_PALACE_INVALIDATION_E2E_RECORD_FIXED.json.
```
