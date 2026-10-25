# Real PALACE Structural Dependency Loop PASS

> **Status:** ISOLATED REAL-SOURCE STRUCTURAL GRAPH PASS  
> **Date:** 2026-10-09  
> **Canonical base before change:** `e39e08f1`

## 1. Replaced representation defect

The earlier real-source test connected seven metadata rows as a linear chain by
row order. That was not a PALACE-declared dependency graph. The adapter now
uses physical and declared relations only:

```text
collections.id
  ← segments.collection
  ← embeddings.segment_id
  ← embedding_metadata.id;

embedding_metadata.parent_drawer_id
  → already-selected parent metadata item.
```

No vector column, full-text table, queue or model is read.

## 2. Verified behavior

```text
materialized items = REAL-COLLECTION, REAL-SEGMENT, REAL-1..REAL-7;
first run          = COMPUTE all nine;
restored run       = REUSE all nine;
segment invalidation
                   = COMPUTE REAL-SEGMENT and REAL-1..REAL-7;
collection         = REMAINS REUSE;
carrier objects    = verify PASS;
PALACE mutation    = false;
model/cloud calls  = false;
D-002 rerun        = false;
D-001 execution    = false.
```

New write-once evidence:

```text
REAL_PALACE_STRUCTURAL_DEPENDENCY_E2E_RECORD.json
  SHA256 = b509ef329fa3d04991a9d70011e850484e8e18cb65295b35a0bd666a18da204f.
```

## 3. Boundary

This proves the selected closed nine-item structural graph in the sealed
snapshot. It does not prove arbitrary PALACE equivalence, dynamic source-change
observation, PALACE-supplied validity windows, production runtime integration,
or Integrated SimiGo. Those require separate authorization and validation.
