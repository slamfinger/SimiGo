# Nodes-out Tier-1 Mechanism Accounting Report v0.1

**状态**：`MECHANISM ACCOUNTING COMPLETE / EFFECT VERDICT LOCKED`  
**边界**：按 Effect Interpretation Contract v0.1 只做机制账本；无性能 PASS/FAIL，无优劣结论，无跨粒度 raw count 比较。

## Provenance

| item | value |
|---|---|
| Contract commit | `0918260c722a98a2c9b6ccaa94efb0ca9668d9ec` |
| Audited Runner commit | `f4d880efd4cac21e60a55688dd686b801f3b7044` |
| Baseline | `17bde28` |
| Baseline blob | `ff6d4e21df40db800e64bd5c949c39b3d77d22aa` |
| Runner SHA-256 | `ace241fc6ca22bd1dd40d2e6036662ae0b1e2e1564f49fe3a140900e26495f17` |
| Official artifact SHA-256 | `556ab61f2fe39fdf0db0a392d2bc99496d6ba83b09fc9e427f481aac68216521` |
| Extractor SHA-256 | `b9f151d34a6b1fb0b1df83102743863e8563e984ac8a1c2779f955262c6928a8` |

## Binding

- `runner_commit`: `f4d880efd4cac21e60a55688dd686b801f3b7044`
- `contract_commit`: `0918260c722a98a2c9b6ccaa94efb0ca9668d9ec`
- `runner_sha256`: `ace241fc6ca22bd1dd40d2e6036662ae0b1e2e1564f49fe3a140900e26495f17`
- `official_artifact_sha256`: `556ab61f2fe39fdf0db0a392d2bc99496d6ba83b09fc9e427f481aac68216521`
- `baseline_blob`: `ff6d4e21df40db800e64bd5c949c39b3d77d22aa`
- `runner_sha_matches_official`: `True`
- `baseline_blob_matches_official`: `True`
- `hot_baseline_matches_official`: `True`
- `hot_candidate_counts_match_official`: `True`
- `tree_baseline_matches_official`: `True`
- `tree_candidate_counts_match_official`: `True`
- `all_source_and_artifact_checks_pass`: `True`

## Per-workload mechanism ledger

### hot

| metric | baseline | Candidate A |
|---|---:|---:|
| M02 covered steps | 2000 | 2000 |
| M04 covered steps | 2000 | 2000 |
| M06 terminal slot occupancy ratio | 1.000000 | 1.000000 |
| M07 terminal resident byte exposure KiB | 938952 | 938952 |
| M08 raw rehydrate count | 696 | 1392 |
| M09 rehydrate byte mass KiB | 54459216 | 54459216 |
| M10 acquisition incidence | 696 | 696 |
| M11 raw externalize count | 684 | 1368 |
| M12 externalize byte mass KiB | 53520264 | 53520264 |
| M13 compatible J disclosure | 973.080000 | 1946.160000 |
| M14 deterministic diff | 0 | 0 |

Candidate event split:

| metric | GDN | ATT | total |
|---|---:|---:|---:|
| M08 rehydrate count | 696 | 696 | 1392 |
| M09 rehydrate KiB | 42762240 | 11696976 | 54459216 |
| M11 externalize count | 684 | 684 | 1368 |
| M12 externalize KiB | 42024960 | 11495304 | 53520264 |

Stop-condition violations: 0.

Step-aggregate state and occupancy disclosure:

| metric | baseline | Candidate A |
|---|---:|---:|
| M05 full-node node-steps mean | 11.957500 | 11.957500 |
| M05 partial-node node-steps mean | 0.000000 | 0.000000 |
| M05 empty-node node-steps mean | 20.042500 | 20.042500 |
| M06 occupancy ratio mean | 0.996458 | 0.996458 |
| M06 occupancy ratio min/max | 0.083333/1.000000 | 0.083333/1.000000 |
| M07 byte exposure mean | 935626.545000 | 935626.545000 |
| M07 byte exposure min/max | 78246/938952 | 78246/938952 |

Candidate state-shape terminal: full=12, partial=0, empty=20. State replay binding=True.

### tree

| metric | baseline | Candidate A |
|---|---:|---:|
| M02 covered steps | 2000 | 2000 |
| M04 covered steps | 2000 | 2000 |
| M06 terminal slot occupancy ratio | 1.000000 | 1.000000 |
| M07 terminal resident byte exposure KiB | 938952 | 938952 |
| M08 raw rehydrate count | 1015 | 2030 |
| M09 rehydrate byte mass KiB | 79419690 | 79419690 |
| M10 acquisition incidence | 1015 | 1015 |
| M11 raw externalize count | 1003 | 2006 |
| M12 externalize byte mass KiB | 78480738 | 78480738 |
| M13 compatible J disclosure | 1422.870000 | 2845.740000 |
| M14 deterministic diff | 0 | 0 |

Candidate event split:

| metric | GDN | ATT | total |
|---|---:|---:|---:|
| M08 rehydrate count | 1015 | 1015 | 2030 |
| M09 rehydrate KiB | 62361600 | 17058090 | 79419690 |
| M11 externalize count | 1003 | 1003 | 2006 |
| M12 externalize KiB | 61624320 | 16856418 | 78480738 |

Stop-condition violations: 0.

Step-aggregate state and occupancy disclosure:

| metric | baseline | Candidate A |
|---|---:|---:|
| M05 full-node node-steps mean | 11.967000 | 11.967000 |
| M05 partial-node node-steps mean | 0.000000 | 0.000000 |
| M05 empty-node node-steps mean | 20.033000 | 20.033000 |
| M06 occupancy ratio mean | 0.997250 | 0.997250 |
| M06 occupancy ratio min/max | 0.083333/1.000000 | 0.083333/1.000000 |
| M07 byte exposure mean | 936369.882000 | 936369.882000 |
| M07 byte exposure min/max | 78246/938952 | 78246/938952 |

Candidate state-shape terminal: full=12, partial=0, empty=20. State replay binding=True.

## Forbidden interpretations

- Raw M08/M11 values are model-internal counts, not comparable effects.
- M09/M12 are identity-mapping accounting disclosures, not measured bandwidth, latency, or economic cost.
- M10 is a mapped descriptor; equality or difference does not establish event equivalence.
- M13 is compatibility disclosure only, not a primary criterion.
- hot and tree remain separate; no pooling, averaging, or generalization.
- Correctness PASS and this accounting do not imply Candidate A is better, worse, production-ready, or causal in a real system.
