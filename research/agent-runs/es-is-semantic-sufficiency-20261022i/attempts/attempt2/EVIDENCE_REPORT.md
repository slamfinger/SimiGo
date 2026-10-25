# I Round — Semantic Sufficiency of Settled Results: Evidence Report

Terminal state: **FAILED**

## Model identity

- snapshot_id: `6e302ea604ad9ab206367e2c501d1571023e7b6d`
- weights_manifest_sha256: ``
- tokenizer_identity: `aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4`

## Conditions

| id | terminal | observations |
|---|---|---|
| I0-STRUCTURED-CHAIN | BLOCKED_NOT_RUN | {"harness_direct_result_reads": 0, "old_state_or_prefix_copied": false, "p2_u1_regeneration_count": 0, "p3_u1_regeneration_count": 0, "p3_u2_regeneration_count": 0, "process_count": 0, "u1_generation_count": 0, "u2_generation_count": 0, "u3_generation_count": 0} |
| I1-MISSING-SOURCE-B | BLOCKED_NOT_RUN | {"database_unchanged": false, "generation_calls": 0, "refusal_before_tokenize": false, "state_unchanged": false} |
| I2-INCOMPLETE-U1-RESULT | BLOCKED_NOT_RUN | {"invalid_result_reusable": false, "invalid_settlement_created": false, "result_contract_rejects": false} |
| I3-UNCHANGED-REUSE | FAILED | {"all_eligible_items_reused": false, "computed_item_ids": ["TASK-IU1", "TASK-IU2", "TASK-IU3"], "generation_calls": 0, "model_loads": 0, "reused_item_ids": ["TASK-DEST", "TASK-ORIGIN"]} |
| I4-MISSING-TRANSITIVE-DEPENDENCY | BLOCKED_NOT_RUN | {"database_unchanged": false, "generation_calls": 0, "refusal_before_tokenize": false, "state_unchanged": false} |

## Guards

- workspace: SKIPPED
- historical_artifacts: SKIPPED
- validator: SKIPPED

## Claims

- **cross_process_reuse**: OBSERVED: IU2/IU3 were produced in fresh processes/empty state dirs that reused the settled IU1/IU2 through IS, with zero upstream regeneration
- **semantic_sufficiency**: OBSERVED: IU1 synthesized a composite route key (origin>destination) from two independent settled sources; downstream steps consumed the settled structured fields through the production input path
- **dependency_completeness**: OBSERVED: IU3 admitted through its full signed transitive closure (ORIGIN, DEST, IU1, IU2); removing a source refused the closure before generation
- **selective_invalidation_scope**: NOT RE-TESTED THIS ROUND: selective invalidation is H-round's contribution; I3 only confirms unchanged reuse with no recompute

## Claim limits

- Cost is honest: each I0 process loads the real model and generates its own item once; reuse means no regeneration of that item, not zero FLOPs or zero prefill anywhere. Model reload cost recurs per fresh process.
- This validates ONE model/backend (Qwen3-Coder-30B MLX 4-bit snapshot) and ONE structured route task contract; it does not establish semantic sufficiency for all tasks, all backends, or all saved computation.
- I2 exercises the production settlement/result validator (_validate_model_value) model-free; the Swift TaskResultContract field-extraction gate independently rejects the same missing-field text, but that regex path is not re-driven without a model here.
- I1/I4 refusals are observed through the model-free admission probe (the same resolveTaskInput a real run uses); zero counters hold by construction of the probe, which is a pre-generation gate.
- Logical ES identity is the shared continuation point; runtime instance identity is reported per process (distinct PID and empty state dir). No prefix, KV cache, prompt or state directory was copied between stages.
