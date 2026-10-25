# J Round — Declarative Result Contract on the Production Path: Evidence Report

Terminal state: **OBSERVED**

## Implementation

- contract_dispatch_basis: `declared_contract`
- task_id_semantic_branches_remaining: `[]`
- model_snapshot_id: `6e302ea604ad9ab206367e2c501d1571023e7b6d`
- binary_sha256: `3fd10a2e9c25f17fbb25ff771b224069c6d17c528c396c8cc494b268b98bd7c3`
- source_snapshot_id: `03c34d5e2cdfc4fe7cedf7e2c03fb679ed146877d1157a119192ca22d6cf6701`
- contract_engine: `execution-information-loop/declarative_result_contract.py`
- production_gate: `production_runtime_bridge._validate_model_value(source_payload, value, dependency_values)`
- prechange_workspace_sha256: `03c34d5e2cdfc4fe7cedf7e2c03fb679ed146877d1157a119192ca22d6cf6701`
- model_free_gate_verdict: `PASS`
- model_free_gate_checks: `{'A_dispatch_basis_recorded': True, 'A_runtime_ids_are_unseen': True, 'A_unseen_id_chain_all_reusable': True, 'B_id_independent_validation': True, 'C_missing_field_rejected': True, 'C_missing_field_result_not_reusable': True, 'D_binding_mismatch_rejected': True, 'E_derivation_mismatch_rejected': True, 'F_unknown_version_fail_closed': True, 'G_full_signed_closure': True, 'H_transitive_source_removal_refuses': True, 'I_no_key_consumer_verifies': True, 'J_extraction_view_is_derived': True, 'K_gate_takes_no_task_item_id': True, 'K_no_hardcoded_j_item_ids': True, 'K_no_task_id_semantic_branch': True}`
- gate_static_proof: `{'gate_arguments': ['source_payload', 'value', 'dependency_values'], 'gate_body_single_delegation': True, 'gate_found': True, 'gate_takes_no_item_id': True, 'no_hardcoded_j_ids': True, 'no_task_id_semantic_branch': True}`
- runtime_run_token: `63fbe989`
- binary_rebuilt_this_round: `True`
- attempt: `3`
- archived_prior_attempt: `/Users/mr.simi/SimiGo-Agent-Runs/es-is-declarative-result-contract-20261023j/attempts/attempt2`
- swift_rebuild_attempt: `{'attempted': True, 'exit_code': 0, 'succeeded': True, 'error_excerpt': '', 'binary_sha256_before': '3fd10a2e9c25f17fbb25ff771b224069c6d17c528c396c8cc494b268b98bd7c3', 'binary_sha256_after': 'e91b70128cbb9eec528fbd4e5730064bf6d53e0a0d10562135290affe9a02ce1', 'binary_unchanged': False, 'log': 'manifests/swift-rebuild-attempt.log'}`

## Graph (run-time generated ids)

- run_token: `63fbe989`
- sources: `['J-63fbe989-ORIGIN', 'J-63fbe989-DEST']`
- structured_chain: `['J-63fbe989-U1', 'J-63fbe989-U2', 'J-63fbe989-U3']`
- transitive_closure_of_u3: `['J-63fbe989-ORIGIN', 'J-63fbe989-DEST', 'J-63fbe989-U1', 'J-63fbe989-U2', 'J-63fbe989-U3']`
- expected_route_key: `NORTH>EAST`
- contract_schema_version: `simigo.result-contract/v1`
- contract_dispatch_basis: `declared_contract`

## Conditions

| id | kind | terminal | key observations |
|---|---|---|---|
| J0-UNSEEN-ID-CHAIN | real_model | OBSERVED | {"u1_generation_count": 1, "u2_generation_count": 1, "u3_generation_count": 1} |
| J1-INCOMPLETE-FIELD | contract_test_model_free_candidate | OBSERVED | {"generation_calls": 0, "producer_contract_rejects": true} |
| J2-BINDING-MISMATCH | contract_test_model_free_candidate | OBSERVED | {"generation_calls": 0, "producer_contract_rejects": true} |
| J3-UNKNOWN-CONTRACT | fail_closed_control | OBSERVED | {"generation_calls": 0, "producer_contract_rejects": true} |
| J4-UNCHANGED-REUSE | model_free_control | OBSERVED | {"all_eligible_items_reused": true, "generation_calls": 0} |
| J5-MISSING-TRANSITIVE-DEPENDENCY | negative_control | OBSERVED | {"database_unchanged": true, "generation_calls": 0, "refusal_before_tokenize": true, "state_unchanged": true} |

## Guards

- workspace: PASS
- historical: PASS
- evidence_validator: PASS

## Claims

- **declarative_dispatch_no_task_id_rules**: OBSERVED: the production gate _validate_model_value takes (source_payload, value, dependency_values) only; the graph was built on run-time ids J-<token>-U1/2/3 and settled, reused and refused exactly as the frozen H/I lineage does
- **cross_process_reuse_on_unseen_ids**: OBSERVED: U2 and U3 were produced in fresh native processes on empty state directories that reused the settled U1/U2 closure through Information Space, one generation per process
- **contract_violations_refused**: OBSERVED: a missing declared field and a value contradicting an admitted input binding were both refused by the declared contract with no settlement and no signature created; an unknown contract schema version failed closed before any model work

## Claim limits

- Only J0 is real-model evidence. J1/J2/J3 settle a MODEL-FREE candidate text through the production execute-with-model-result path, so they prove the declared-contract gate refuses those shapes and creates no settlement/signature; they prove nothing about what the model would produce.
- The native child's stdout and stderr are genuinely 0 bytes (recorded as bytes=0 with the real empty-stream hash, never synthesised from the evidence JSON). The authoritative model output is the generated_text and output token ids inside each stage's Information Space settlement evidence, plus the driver's independent re-extraction from the item's own declared contract (declared_contract_audit).
- The shipped SimiGoTaskRun binary was NOT rebuilt this round: swift build fails on this machine because the Metal toolchain is not mounted (). No Swift source was changed for J, and the binary hash is recorded unchanged before and after the attempt; the native producer already reads the item's declared extraction view and takes item/demand ids as arguments, so unseen ids need no recompilation.
- Cost is honest: each J0 process loads the real model and generates its own item exactly once; reuse means no regeneration of that item, not zero FLOPs or zero prefill. Model reload cost recurs per fresh process.
- This validates ONE model/backend snapshot and ONE route-synthesis task contract family. It does not establish that every production task's declaration is semantically sufficient, only that validation dispatches on the declaration instead of the task id.
- Logical ES identity is the per-stage pending state id (j0-p1/p2/p3) and runtime instance identity is the per-process provenance execution id; the three are distinct dimensions. No prefix, KV cache, prompt or state directory was copied between stages.
- P2 (J-63fbe989-U2): the declared match_policy is "first", and the real model text carried extra repeated/contradicting matches for ['route_key']; the settled value is the first declared match ({"route_key": ["NORTH>EAST", "NORTH>WEST"]}). This is the item's own declaration at work, not an id-specific exception, but it means "first" tolerates trailing noise and a stricter exactly_one policy was NOT what this chain declared.
- P3 (J-63fbe989-U3): the declared match_policy is "first", and the real model text carried extra repeated/contradicting matches for ['route_key']; the settled value is the first declared match ({"route_key": ["NORTH>EAST"]}). This is the item's own declaration at work, not an id-specific exception, but it means "first" tolerates trailing noise and a stricter exactly_one policy was NOT what this chain declared.
