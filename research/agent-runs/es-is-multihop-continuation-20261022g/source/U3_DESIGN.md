# G-round minimal native extension design (U1 -> U2 -> U3)

## Dependency shape (reuses F-round production code, no new policy)
- TASK-SOURCE (session-log)  -- settled at definition (deterministic registration)
- TASK-U1  deps=[SOURCE]      value {secret, ...}                 (producer P1 signs)
- TASK-U2  deps=[SOURCE,U1]   value {answer="<secret>-<checksum>"}(producer P2 signs)
- TASK-U3  deps=[U2]          value {stamp="<secret>"}            (producer P3 signs)
  - template binds {answer} from TASK-U2.answer; result_contract STAMP=([0-9a-f]{16})
  - U3 depends ONLY on U2, but admitting U2 recursively resolves U2's closure
    (SOURCE + U1) inside _resolve_settled_dependency. Removing U1's settlement
    binding makes U2 non-reusable -> U3 admission refuses BEFORE tokenize/generate.

## Model value contract (avoid long-copy unreliability)
- U3 model_task=derive_stamp: model copies the 16-hex secret that is the LEFT
  part of the admitted U2 answer already rendered in its input; short, reliable.

## Real code gaps (production, non-empty diff)
1. execution-information-loop/production_runtime_bridge.py
   - add TASK_U3_ID constant
   - add `if item_id == TASK_U3_ID` branch to _validate_model_value:
     value["stamp"] must equal answer.split("-")[0] of the settled U2 dependency.
2. simigo2-experimental/Sources/SimiGoDetachedDriver/main.swift
   - three child processes P1(U1 producer) / P2(U2 consumer=verify,producer) /
     P3(U3 consumer=verify), each distinct --execution-id + empty state dir;
     P2 gated on P1 exit, P3 gated on P2 exit; add closure checks.
3. simigo2-experimental/scripts/ordinary_task/run_phase_g.py (new harness)
   - define 3-item task fixture (put_source), run native driver, assemble
     evidence_schema summary; G1 from a COPY removing settlement:TASK-U1 binding;
     N4 isolation scan. Uses existing signed-settlement machinery only.
4. model-free fixtures + Swift closure test
   - admission_selftest.py: prepare_multihop_database settles U1,U2 and defines+
     settles U3; emit multihop-happy / multihop-missing-u1 (removes U1 binding).
   - Swift test: resolveTaskInput(TASK-U3) admits full closure {U2,U1,SOURCE} on
     happy; refuses pre-generation (0 tokenize/0 generate) on missing-u1.

## Invariants untouched
- carrier_loop._settlement_reuse_decision dependency_object_ids equality IS the
  transitive-closure check. Not modified. No new anti-rollback / trust root.
