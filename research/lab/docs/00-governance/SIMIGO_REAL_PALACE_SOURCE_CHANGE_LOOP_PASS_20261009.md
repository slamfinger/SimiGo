# Real PALACE Source-Change Loop PASS

> **Status:** ISOLATED REAL-SOURCE COPY CHANGE PASS  
> **Date:** 2026-10-09  
> **Canonical base before change:** `9a74b0aa`

## 1. Verified behavior

The sealed D002 snapshot was copied byte-for-byte into an isolated temporary
file. The copy initially matched the registered snapshot SHA-256. After real
reuse was established, only `embedding_metadata.last_modified` for internal
record `1` changed on the copy. The changed file digest was bound to a new
read-only adapter session.

```text
first run              = COMPUTE all nine structural items;
restored run           = REUSE all nine;
REAL-1 source change   = COMPUTE REAL-1 only;
unaffected items       = REUSE REAL-COLLECTION, REAL-SEGMENT, REAL-2..REAL-7;
changed version        = persisted and observed;
carrier objects        = verify PASS;
sealed snapshot change = false;
model/cloud calls      = false;
D-002 rerun            = false;
D-001 execution        = false.
```

New write-once evidence:

```text
REAL_PALACE_SOURCE_CHANGE_E2E_RECORD.json
  SHA256 = 5689b71c5061911bdc8695fd983ef1181623eacea0748a172f1c133487000856.
```

## 2. Boundary

This proves explicit source-change consumption on an isolated copy. It does not
prove automatic background discovery, production file watching, arbitrary
change ordering, crash-safe source observation, PALACE-supplied validity windows,
PALACE equivalence, or Integrated SimiGo. The canonical PALACE snapshot was not
mutated.
