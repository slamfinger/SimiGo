# Real PALACE Integrated Closed-Loop PASS

> **Status:** ISOLATED REAL-SOURCE INTEGRATED CLOSED-LOOP PASS  
> **Date:** 2026-10-09  
> **Canonical base before change:** `053b75ab`

## 1. Scope

This is not a composite of separate PASS files. One SQLite carrier and one
byte-identical copy of the sealed D002 snapshot ran the following behaviors in
one ordered acceptance flow:

```text
real structural graph materialization;
Execution State persistence, reopen and restore;
valid settlement reuse;
explicit invalidation and dependency propagation;
real source change and selective recompute;
validity-window change and dependent propagation;
malformed observation-time fail-closed;
mid-demand exception atomic rollback;
full carrier object verification;
final Execution State restoration.
```

## 2. Acceptance matrix

| Requirement | Result |
| --- | --- |
| Information persistence and verification | PASS |
| ES-defined minimal continuation demand | PASS |
| Validity maintenance and non-permanent settlement | PASS |
| Unaffected incremental reuse | PASS |
| Missing / invalid / dependency-changed selective recompute | PASS |
| Persistence and restart recovery | PASS |
| Missing, malformed and mid-demand failure safety | PASS |
| One auditable real-source closed-loop record | PASS |

The atomic gate also fixes a newly exposed semantic defect: changing an item's
current validity window now invalidates an older settlement whose basis records
a different window.

New write-once evidence:

```text
REAL_PALACE_INTEGRATED_CLOSED_LOOP_E2E_RECORD.json
  SHA256 = ce40eed5ca520b9dbd66808900afee2c2508c522fb6933afccf1aaed6895873e.
```

## 3. Remaining boundaries

```text
canonical PALACE mutation = false;
canonical Information Space mutation = false;
D-001 execution = false;
D-002 campaign rerun = false;
model/cloud/vector/full-text participation = false;
PALACE-supplied validity window = NOT ESTABLISHED;
automatic background source discovery = NOT ESTABLISHED;
production SimiGo runtime integration = NOT ESTABLISHED;
PALACE equivalence = NOT ESTABLISHED;
Integrated SimiGo proof = NOT ESTABLISHED.
```
