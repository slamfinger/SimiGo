# Vertical Slice Acceptance Matrix

| Required behavior | Evidence in E2E run | Result |
| --- | --- | --- |
| Information access/provenance | source payload/version/digest persisted; settlements bind source and dependency digests | PASS |
| ES-driven demand | `demand-001` declares continuation point, obligations, conditions, A/B/C | PASS |
| Validity maintenance | invalidating B marks B/C stale/invalid | PASS |
| Incremental reuse | second run reuses A/B/C | PASS |
| Selective recomputation | after B invalidation: A reused; B/C recomputed | PASS |
| Persistence/restoration | each run opens a new `InformationLoop` from SQLite | PASS |
| Failure safety | missing D blocks; A payload digest mismatch blocks | PASS |
| Real auditable chain | append-only hash chain passes | PASS |
| Isolation | no PALACE/D001/D002 mutation or execution | PASS |
