# H Round — Native Selective Invalidation: Evidence Report

Terminal state: **OBSERVED**

## Conditions

| id | kind | terminal | loads | tok_text | tok_seed | gen | computed | reused |
|---|---|---|---|---|---|---|---|---|
| H0 | preflight | OBSERVED | 0 | 0 | 0 | 0 | - | - |
| H5 | model_free_preflight | OBSERVED | 0 | 0 | 0 | 0 | - | - |
| H1 | real_model_baseline | OBSERVED | 4 | 4 | 4 | 4 | TASK-U1,TASK-U2,TASK-U3,TASK-V1 | TASK-SOURCE,TASK-SOURCE-B,TASK-U1,TASK-U2 |
| H2 | selective_invalidation | OBSERVED | 3 | 3 | 3 | 3 | TASK-U1,TASK-U2,TASK-U3 | TASK-SOURCE,TASK-SOURCE-B,TASK-U1,TASK-U2,TASK-V1 |
| H3 | unchanged_source_control | OBSERVED | 0 | 0 | 0 | 0 | - | TASK-SOURCE,TASK-SOURCE-B,TASK-U1,TASK-U2,TASK-U3,TASK-V1 |
| H4 | invalid_source_provenance_negative_control | OBSERVED | 0 | 0 | 0 | 0 | - | - |

## Guards

- workspace: PASS
- historical_artifacts: PASS

## Claim limits

- Cost is reported honestly: each H1/H2 recompute process loads the real model and generates its own item once; reuse of V1 means V1 performs no generation, not that no FLOPs occur anywhere.
- H3 reuse is shown at the model-free demand/settlement decision layer; the ordinary per-item entry computes an item it is explicitly asked to run.
- Only this four-node two-branch fixture is covered; results demonstrate feasibility of selective invalidation on the production path, not universal validity across all graphs, models or backends.
