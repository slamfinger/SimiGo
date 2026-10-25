# J Round — Declarative Result Contract on the Production Path: Evidence Report

Terminal state: **OBSERVED**

## Implementation

- contract_dispatch_basis: `declared_contract`
- task_id_semantic_branches_remaining: `[]`
- model_snapshot_id: `6e302ea604ad9ab206367e2c501d1571023e7b6d`
- binary_sha256: `e91b70128cbb9eec528fbd4e5730064bf6d53e0a0d10562135290affe9a02ce1`
- source_snapshot_id: `03c34d5e2cdfc4fe7cedf7e2c03fb679ed146877d1157a119192ca22d6cf6701`
- contract_engine: `execution-information-loop/declarative_result_contract.py`
- production_gate: `production_runtime_bridge._validate_model_value(source_payload, value, dependency_values)`
- prechange_workspace_sha256: `03c34d5e2cdfc4fe7cedf7e2c03fb679ed146877d1157a119192ca22d6cf6701`
- model_free_gate_verdict: `PASS`
- model_free_gate_checks: `{"A_dispatch_basis_recorded": true, "A_runtime_ids_are_unseen": true, "A_unseen_id_chain_all_reusable": true, "B_id_independent_validation": true, "C_missing_field_rejected": true, "C_missing_field_result_not_reusable": true, "D_binding_mismatch_rejected": true, "E_derivation_mismatch_rejected": true, "F_unknown_version_fail_closed": true, "G_full_signed_closure": true, "H_transitive_source_removal_refuses": true, "I_no_key_consumer_verifies": true, "J_extraction_view_is_derived": true, "K_gate_takes_no_task_item_id": true, "K_no_hardcoded_j_item_ids": true, "K_no_task_id_semantic_branch": true}`
- gate_static_proof: `{"gate_arguments": ["source_payload", "value", "dependency_values"], "gate_body_single_delegation": true, "gate_found": true, "gate_takes_no_item_id": true, "no_hardcoded_j_ids": true, "no_task_id_semantic_branch": true}`
- runtime_run_token: `f8973ab6`
- binary_rebuilt_this_round: `True`
- regression_suite: `{"artifact": "tests/regression-attempt9", "members": {"<unit>": {"check_count": 0, "condition_count": 0, "exit_code": 0, "failed_checks": [], "verdict": "PASS"}, "admission_selftest": {"check_count": 0, "condition_count": 7, "exit_code": 0, "failed_checks": [], "verdict": "PASS"}, "h_selective_invalidation_selftest": {"check_count": 5, "condition_count": 0, "exit_code": 0, "failed_checks": [], "verdict": "PASS"}, "i_semantic_sufficiency_selftest": {"check_count": 7, "condition_count": 0, "exit_code": 0, "failed_checks": [], "verdict": "PASS"}, "j_contract_selftest": {"check_count": 16, "condition_count": 0, "exit_code": 0, "failed_checks": [], "verdict": "PASS"}}, "verdict": "PASS"}`
- attempt: `9`
- archived_prior_attempt: `/Users/mr.simi/SimiGo-Agent-Runs/es-is-declarative-result-contract-20261023j/attempts/attempt8`
- swift_rebuild_attempt: `{"attempted": true, "binary_sha256_after": "e91b70128cbb9eec528fbd4e5730064bf6d53e0a0d10562135290affe9a02ce1", "binary_sha256_before": "e91b70128cbb9eec528fbd4e5730064bf6d53e0a0d10562135290affe9a02ce1", "binary_unchanged": true, "error_excerpt": "", "exit_code": 0, "log": "manifests/swift-rebuild-attempt.log", "succeeded": true}`
- run_binary_matches_recorded_sha256: `True`

## Graph (run-time generated ids)

- run_token: `f8973ab6`
- sources: `["J-f8973ab6-ORIGIN", "J-f8973ab6-DEST"]`
- structured_chain: `["J-f8973ab6-U1", "J-f8973ab6-U2", "J-f8973ab6-U3"]`
- transitive_closure_of_u3: `["J-f8973ab6-ORIGIN", "J-f8973ab6-DEST", "J-f8973ab6-U1", "J-f8973ab6-U2", "J-f8973ab6-U3"]`
- expected_route_key: `NORTH>EAST`
- contract_schema_version: `simigo.result-contract/v1`
- contract_dispatch_basis: `declared_contract`

## Conditions

| id | kind | terminal | key observations |
|---|---|---|---|
| J0-UNSEEN-ID-CHAIN | real_model | OBSERVED | {"closure_signature_verified": true, "ids_unseen": true, "p2_u1_regeneration_count": 0, "p3_u1_regeneration_count": 0, "p3_u2_regeneration_count": 0, "process_count": 3, "u1_generation_count": 1, "u2_generation_count": 1, "u3_generation_count": 1} |
| J1-INCOMPLETE-FIELD | contract_test_model_free_candidate | OBSERVED | {"generation_calls": 0, "observed_error": "PRODUCER_RESULT_FIELD_MISSING: field=priority required field was not present in generated text", "producer_contract_rejects": true} |
| J2-BINDING-MISMATCH | contract_test_model_free_candidate | OBSERVED | {"generation_calls": 0, "observed_error": "PRODUCER_RESULT_BINDING_MISMATCH: field=priority actual '3' != bound value '5'", "producer_contract_rejects": true} |
| J3-UNKNOWN-CONTRACT | fail_closed_control | OBSERVED | {"generation_calls": 0, "observed_error": "CONTRACT_UNKNOWN_SCHEMA_VERSION: expected 'simigo.result-contract/v1', found 'simigo.result-contract/v9'", "producer_contract_rejects": true} |
| J4-UNCHANGED-REUSE | model_free_control | OBSERVED | {"all_eligible_items_reused": true, "generation_calls": 0} |
| J5-MISSING-TRANSITIVE-DEPENDENCY | negative_control | OBSERVED | {"database_unchanged": true, "generation_calls": 0, "refusal_before_tokenize": true, "state_unchanged": true} |

## J0: one row per real process

| stage | pid | logical ES id | runtime instance id | task item | state empty at start | generations | computed | reused | child stdout bytes | re-extraction agrees |
|---|---|---|---|---|---|---|---|---|---|---|
| P1 | 25562 | j0-p1 | be144903-2ab5-4c48-8913-3e0b0b8712e8 | J-f8973ab6-U1 | True | 1 | ["J-f8973ab6-U1"] | ["J-f8973ab6-ORIGIN", "J-f8973ab6-DEST"] | 0 | True |
| P2 | 26824 | j0-p2 | 02fc1808-da6d-457f-a9a9-062a040d8800 | J-f8973ab6-U2 | True | 1 | ["J-f8973ab6-U2"] | ["J-f8973ab6-ORIGIN", "J-f8973ab6-DEST", "J-f8973ab6-U1"] | 0 | True |
| P3 | 27087 | j0-p3 | 5120879c-a1e5-4e1a-8346-c69d4101472c | J-f8973ab6-U3 | True | 1 | ["J-f8973ab6-U3"] | ["J-f8973ab6-ORIGIN", "J-f8973ab6-DEST", "J-f8973ab6-U1", "J-f8973ab6-U2"] | 0 | True |

## J0: the contract each item declared, and what re-applying it produced

- P1 (J-f8973ab6-U1): schema `simigo.result-contract/v1`, declared fields ["destination_code", "origin_code", "priority", "route_key"], re-extracted {"destination_code": "EAST", "origin_code": "NORTH", "priority": "5", "route_key": "NORTH>EAST"}
- P2 (J-f8973ab6-U2): schema `simigo.result-contract/v1`, declared fields ["route_key"], re-extracted {"route_key": "NORTH>EAST"}
- P3 (J-f8973ab6-U3): schema `simigo.result-contract/v1`, declared fields ["route_key"], re-extracted {"route_key": "NORTH>EAST"}

## Guards

- workspace: PASS
- historical: PASS
- evidence_validator: PASS

## Validation

- in-driver strict acceptance run: `{"issue_count": 0, "issues": [], "result": "PASS"}`
- the closing independent re-run of validate_j_evidence.py records the sha256 of this final on-disk summary.json in `manifests/validator-independent-rerun.json`.

## Claims

- **declarative_dispatch_no_task_id_rules**: OBSERVED: the production gate _validate_model_value takes (source_payload, value, dependency_values) only; the graph was built on run-time ids J-<token>-U1/2/3 and settled, reused and refused exactly as the frozen H/I lineage does
- **cross_process_reuse_on_unseen_ids**: OBSERVED: U2 and U3 were produced in fresh native processes on empty state directories that reused the settled U1/U2 closure through Information Space, one generation per process
- **contract_violations_refused**: OBSERVED: a missing declared field and a value contradicting an admitted input binding were both refused by the declared contract with no settlement and no signature created; an unknown contract schema version failed closed before any model work. No J0 real-model generation failed its contract this round, so these three refusals are the same production gate driven by model-free candidate texts, not observed model failures

## Claim limits

- Only J0 is real-model evidence. J1/J2/J3 settle a MODEL-FREE candidate text through the production execute-with-model-result path, so they prove the declared-contract gate refuses those shapes and creates no settlement/signature; they prove nothing about what the model would produce.
- No real-model contract failure was observed this round: all three J0 generations satisfied their declared contract on their first and only generation call, and the driver never retried a generation. The refusal path is therefore evidenced by the model-free candidates, not by a model that broke its contract.
- The native child's stdout and stderr are genuinely 0 bytes (recorded as bytes=0 with the real empty-stream hash, never synthesised from the evidence JSON). The authoritative model output is the generated_text and output token ids inside each stage's Information Space settlement evidence, plus the driver's independent re-extraction from the item's own declared contract (declared_contract_audit).
- Native rebuild: `swift build --product SimiGoTaskRun` succeeded and left the binary byte-identical (e91b70128cbb), so the run binary is the shipped binary and the rebuild claim is a no-op.
- Cost is honest: each J0 process loads the real model and generates its own item exactly once; reuse means no regeneration of that item, not zero FLOPs or zero prefill. Model reload cost recurs per fresh process.
- This validates ONE model/backend snapshot and ONE route-synthesis task contract family. It does not establish that every production task's declaration is semantically sufficient, only that validation dispatches on the declaration instead of the task id.
- Logical ES identity is the per-stage pending state id (j0-p1/p2/p3) and runtime instance identity is the per-process provenance execution id; the three are distinct dimensions. No prefix, KV cache, prompt or state directory was copied between stages.
- P2 (J-f8973ab6-U2): the declared match_policy is "first", and the real model text carried extra repeated/contradicting matches for ['route_key']; the settled value is the first declared match ({"route_key": ["NORTH>EAST", "NORTH>WEST"]}). This is the item's own declaration at work, not an id-specific exception, but it means "first" tolerates trailing noise and a stricter exactly_one policy was NOT what this chain declared.
- P3 (J-f8973ab6-U3): the declared match_policy is "first", and the real model text carried extra repeated/contradicting matches for ['route_key']; the settled value is the first declared match ({"route_key": ["NORTH>EAST"]}). This is the item's own declaration at work, not an id-specific exception, but it means "first" tolerates trailing noise and a stricter exactly_one policy was NOT what this chain declared.

## Environment

- summary.validator_final is written after the in-driver validation pass (it is that pass's own transcript); the closing independent run of validate_j_evidence.py in this round's artifacts re-checks the final on-disk summary.json, so the accepted evidence is the re-checked file.
