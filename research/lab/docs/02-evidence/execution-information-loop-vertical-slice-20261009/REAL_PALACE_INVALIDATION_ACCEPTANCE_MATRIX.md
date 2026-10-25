# Real PALACE Invalidation Acceptance Matrix

| Requirement | Evidence | Result |
| --- | --- | --- |
| Explicit settlement invalidation | REAL-2..REAL-7 INVALID records appended | PASS |
| Dependency propagation | REAL-3..REAL-7 recomputed after REAL-2 | PASS |
| Unaffected reuse | REAL-1 reused | PASS |
| No PALACE mutation | PALACE source/snapshot unchanged | PASS |
| No D-002 rerun | isolated real-source loop only | PASS |
| Typed determinism | all results digest-bound | PASS |
