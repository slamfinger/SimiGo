# J Round — Declarative Result Contract on the Production Path: Evidence Report

Terminal state: **BLOCKED_NOT_RUN**

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
- runtime_run_token: `0145e5b8`
- binary_rebuilt_this_round: `False`
- attempt: `1`
- archived_prior_attempt: `None`

## Graph (run-time generated ids)

- run_token: `0145e5b8`
- sources: `['J-0145e5b8-ORIGIN', 'J-0145e5b8-DEST']`
- structured_chain: `['J-0145e5b8-U1', 'J-0145e5b8-U2', 'J-0145e5b8-U3']`
- transitive_closure_of_u3: `['J-0145e5b8-ORIGIN', 'J-0145e5b8-DEST', 'J-0145e5b8-U1', 'J-0145e5b8-U2', 'J-0145e5b8-U3']`
- expected_route_key: `NORTH>EAST`
- contract_schema_version: `simigo.result-contract/v1`
- contract_dispatch_basis: `declared_contract`

## Conditions

| id | kind | terminal | key observations |
|---|---|---|---|
| J0-UNSEEN-ID-CHAIN | blocked | BLOCKED_NOT_RUN | {} |
| J1-INCOMPLETE-FIELD | contract_test_model_free_candidate | OBSERVED | {"generation_calls": 0, "producer_contract_rejects": true} |
| J2-BINDING-MISMATCH | contract_test_model_free_candidate | OBSERVED | {"generation_calls": 0, "producer_contract_rejects": true} |
| J3-UNKNOWN-CONTRACT | fail_closed_control | OBSERVED | {"generation_calls": 0, "producer_contract_rejects": true} |
| J4-UNCHANGED-REUSE | blocked | BLOCKED_NOT_RUN | {} |
| J5-MISSING-TRANSITIVE-DEPENDENCY | blocked | BLOCKED_NOT_RUN | {} |

## Guards

- workspace: PASS
- historical: PASS
- evidence_validator: PASS

## Claims

- **declarative_dispatch_no_task_id_rules**: OBSERVED: the production gate _validate_model_value takes (source_payload, value, dependency_values) only; the graph was built on run-time ids J-<token>-U1/2/3 and settled, reused and refused exactly as the frozen H/I lineage does
- **cross_process_reuse_on_unseen_ids**: OBSERVED: U2 and U3 were produced in fresh native processes on empty state directories that reused the settled U1/U2 closure through Information Space, one generation per process
- **contract_violations_refused**: OBSERVED: a missing declared field and a value contradicting an admitted input binding were both refused by the declared contract with no settlement and no signature created; an unknown contract schema version failed closed before any model work

## Claim limits

