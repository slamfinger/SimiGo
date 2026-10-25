# G-round production call graph (read-only review, before any source edit)

Repo HEAD at snapshot: e7f63856298390deb8596a4a30e173d3fb466eaa (branch main).
Reviewed on the current working tree (F-round edits are already present as dirty files).

## Process / execution-state orchestration
- Sources/SimiGoDetachedDriver/main.swift — native supervisor. Owns ONLY process
  boundaries, ES state-directory identity, timing, evidence assembly. Never loads the
  model, never reads a settlement, never builds a model input. Today TWO children:
  U1 (producer env required) then after waitUntilExit() U2 (consumer env verify), each
  a distinct --execution-id + independently verified EMPTY state dir. checks L357-385
  already prove: producer-exited-before-consumer, distinct PIDs, distinct execution ids,
  empty consumer state, generated-once, reused U1 / did-not-recompute, verifies U1 sig,
  did-not-remint-U1.  G GAP: add third child (P3/U3) gated on P2 exit + closure checks.
- Sources/SimiGoTaskRun/main.swift — ordinary entry, one item/process, item-DATA driven
  (reads source_payload: prompt_seed, next_input_template, input_bindings, result_contract),
  calls production continueTask. CountingModelExecutor counts tokenize/generate.
  --admission-probe runs resolveTaskInput with NO executor (0/0 by construction).
  NO per-stage change needed for U3.
- Sources/SimiGoTaskRun/TaskResultContract.swift — generic result_contract.fields regex
  extraction; U3 supplies its own fields.

## IS resolve / settle / signature
- ProductionRuntimeInformationIntegration.swift
  continueTask L1110: FIRST resolveTaskInput (pre-tokenize admission) THEN checkpoint
  cross-check, tokenize, create/attach ES@0, capture repr, ONE continuation, build value,
  execute-with-model-result (producer signs its OWN new settlement), logical advance+rebind,
  confirm-runtime-application, persist ES-IS checkpoint.
  resolveTaskInput L1491: bridge resolve-model-input -> byte verify -> consumer Ed25519
  verify via SettlementProvenanceVerifier against deployment anchor; refusal BEFORE tokenize.
- production_runtime_bridge.py
  _resolve_settled_dependency L775: RECURSIVE dependency closure (memo resolved, cycle
  visiting, current dependency_object_ids from RESOLVED ids, admitted via the SAME
  _settlement_reuse_decision). Missing/tampered/unsigned/expired/closure-mismatch ->
  AdmissionRefusal before model work.
  resolve_model_input L874: expand item's OWN template from admitted dependency values only.
  _validate_model_value L1056: per-item semantic guard, hard-coded TASK-U1/TASK-U2.
  G GAP: add TASK-U3 branch requiring U3 value derivable from settled U2 answer.
  execute_with_model_result L1155: settle under provenance required; refuses if a dependency
  is not reusable (calculator only accepts the executed item).
- carrier_loop.py
  _settlement_reuse_decision L1094: reusable iff all anchors agree AND dependency_object_ids
  == freshly resolved closure (L1139-1140) AND detached signature verifies. THIS is the
  transitive-closure invariant G0 relies on and G1 breaks.

## G1 negative-control mechanism (confirmed feasible)
mutate_remove_u1 deletes dependency_entries/is_index_entries for settlement:TASK-U1 while
leaving settlement:TASK-U2 present. Replayed on a COPY of the G0 db, the ordinary P3
continueTask for U3 fails in resolveTaskInput -> _resolve_settled_dependency(U1) with a
pre-tokenize refusal (tokenize_text=0, tokenize_seed=0, generate=0), DB/state unchanged.
Exercises existing closure admission, not a new policy.

## Environment / model identity
- Model: HF snapshot mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit @
  6e302ea604ad9ab206367e2c501d1571023e7b6d (weights not copied; canonical resolved path).
- Toolchain: Swift 6.4, arm64-apple-macosx27.0.0, Metal present.
- Trust root + signing key provisioned OUTSIDE every database (run_phase_e.provision_trust);
  consumers admit under verify (public anchor only, cannot re-mint).
