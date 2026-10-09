# D002 Carrier Integration Acceptance Matrix

| Required behavior | Evidence | Result |
| --- | --- | --- |
| Reuse existing append-only carrier | `DatabaseBackedIS` imported unchanged | PASS |
| Persistent content-addressed objects | all carrier objects verify | PASS |
| Current source version resolution | latest index entry selected | PASS |
| Settlement reuse without duplicate writes | second run reuses A/B/C | PASS |
| Source invalidation/selective recompute | B update recomputes B/C; A reused | PASS |
| Missing information fail-closed | missing D blocks | PASS |
| Isolation | no D002 campaign rerun; no D001/PALACE mutation | PASS |
