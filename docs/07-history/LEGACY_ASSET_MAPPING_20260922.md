# Legacy Asset Mapping — 2026-09-22

> Purpose: provenance-safe inventory of existing SimiGo-Lab research assets against the new archive taxonomy.
> Scope: SimiGo-Lab only (slamfinger/SimiGo-Lab), branch refactor/research-archive-20260922.
> This is an index/mapping layer, not a migration order. Existing assets are not moved, renamed, rewritten, or reinterpreted by this file.

## 1. Mapping rules

| Field | Meaning |
|---|---|
| Original path | Existing repository location; provenance anchor |
| Asset type | State / memory / source / design / evidence / finding / decision / architecture / implementation-support |
| Archive layer | 00–08 conceptual destination |
| Current status | Current repository state; not changed here |
| Migration | NO unless a later explicit migration decision is registered |
| Review | Whether file-level semantic review remains |

Rules: existing track-*, exp-*, and runtime2-skeleton paths remain valid historical/workspace paths; mapping does not promote historical results into current evidence; FROZEN/CLOSED/SEALED/NOT STARTED/NOT DEFINED retain repository meanings; future physical moves require their own migration record and original provenance anchor.

## 2. Governance and definition assets

| Original path | Type | Archive layer | Current status | Migration | Review |
|---|---|---|---|---|---|
| docs/RESEARCH_STATE.md | state authority | 00-governance | authoritative / active | NO | reviewed |
| docs/AGENT_CONTEXT.md | governance / agent context | 00-governance | active | NO | reviewed |
| docs/RESEARCH_MEMORY.md | research memory | 08-research-memory | active memory layer | NO | reviewed |
| docs/SOURCE_RUNTIME_RESEARCH_DEFINITION_OPENING_v0.1.md | research definition source | 01-questions | STEP ① PASS | NO | reviewed |
| docs/SOURCE_RUNTIME_RESEARCH_QUESTION_DEFINITION_v0.1.md | RQ definition source | 01-questions | STEP ② PASS | NO | reviewed |
| docs/SOURCE_RUNTIME_INDEPENDENCE_ARGUMENT_v0.1.md | independence argument | 01-questions | STEP ③ PASS | NO | reviewed |
| docs/ARCHIVE_INDEX.md | archive master index | 00-governance | active | NO | reviewed |
| docs/00-governance/README.md | governance index | 00-governance | active | NO | reviewed |
| docs/00-governance/ARCHIVE_ARCHITECTURE_INSPIRATIONS.md | archive design rationale | 00-governance | active design record | NO | reviewed |
| docs/01-questions/README.md | questions index | 01-questions | active | NO | reviewed |
| docs/02-evidence/README.md | evidence index | 02-evidence | active | NO | reviewed |
| docs/03-findings/README.md | findings index | 03-findings | active | NO | reviewed |
| docs/04-decisions/README.md | decisions index | 04-decisions | active | NO | reviewed |
| docs/05-architecture/README.md | architecture index | 05-architecture | active | NO | reviewed |
| docs/06-closure/README.md | closure index | 06-closure | active | NO | reviewed |
| docs/07-history/README.md | history/provenance index | 07-history | active | NO | reviewed |
| docs/08-research-memory/README.md | memory index | 08-research-memory | active | NO | reviewed |

## 3. Architecture

| Original path | Type | Archive layer | Current status | Migration | Review |
|---|---|---|---|---|---|
| docs/architecture/ARCHITECTURE_2.0_PRERESEARCH_20260920.md | directional architecture source | 05-architecture | directional source; not 1.x authority | NO | reviewed |

The existing docs/architecture location remains the source location. The new 05-architecture layer is taxonomy, not a command to move this file.

## 4. Forward workspaces

| Original path | Type | Archive layer | Current status | Migration | Review |
|---|---|---|---|---|---|
| exp06-roofline/README.md | experiment definition | 01-questions | preregistered measurement line; not completed | NO | reviewed |
| exp06-roofline/MEASUREMENT_PLAN_20260920.md | preregistered measurement design | 01-questions | measurement plan; M1 not completed | NO | reviewed |
| trackA-kernel/README.md | research-line definition | 01-questions | NOT STARTED; conditional on exp06 | NO | reviewed |
| trackD-memory/README.md | research-line definition | 01-questions | NOT STARTED | NO | reviewed |
| runtime2-skeleton/README.md | future architecture note | 05-architecture | note-only / future / not implemented | NO | reviewed |

These remain workspace paths. They must not be expanded or relabeled merely to make the archive hierarchy look complete.

## 5. Track B — Execution State

Track B is documented as CLOSED / FROZEN. Its closure record limits the claim to lifecycle semantic correctness under the tested execution position; it does not establish performance superiority, estimator robustness, or general residency behavior.

| Original path | Type | Archive layer | Current status | Migration | Review |
|---|---|---|---|---|---|
| trackB-execution-state/README.md | track definition / closure context | 06-closure | CLOSED / FROZEN | NO | reviewed |
| trackB-execution-state/EXECUTION_FORK_F1_PROBE_RESULTS_20260920.md | experiment evidence | 02-evidence | historical Track B evidence | NO | pending |
| trackB-execution-state/EXECUTION_FORK_F2_GATE_RESULTS_20260920.md | gate evidence | 02-evidence | historical Track B evidence | NO | pending |
| trackB-execution-state/EXECUTION_FORK_F3_RESTORE_RESULTS_20260920.md | experiment evidence | 02-evidence | historical Track B evidence | NO | pending |
| trackB-execution-state/EXECUTION_FORK_F4EF_RESULTS_20260920.md | experiment evidence | 02-evidence | historical Track B evidence | NO | pending |
| trackB-execution-state/EXECUTION_FORK_F4_STRESS_RESULTS_20260920.md | experiment evidence | 02-evidence | historical Track B evidence | NO | pending |
| trackB-execution-state/EXECUTION_FORK_F5_1_REATTACH_RESULTS_20260920.md | experiment evidence | 02-evidence | historical Track B evidence | NO | pending |
| trackB-execution-state/EXECUTION_FORK_F5_2_MATRIX_RESULTS_20260920.md | experiment evidence | 02-evidence | historical Track B evidence | NO | pending |
| trackB-execution-state/EXECUTION_FORK_F5_3_STEP1_POLICY_SIM_RESULTS_20260921.md | experiment evidence | 02-evidence | historical Track B evidence | NO | pending |
| trackB-execution-state/EXECUTION_FORK_F5_3_STEP23_LIVE_RESULTS_20260921.md | experiment evidence | 02-evidence | historical Track B evidence | NO | pending |
| trackB-execution-state/EXTERNAL_REVIEW_RECONCILIATION_20260920.md | external review record | 02-evidence | historical review | NO | pending |
| trackB-execution-state/F4D_UPSTREAM_FACTS_SKELETON_20260920.md | upstream fact record | 02-evidence | historical supporting record | NO | pending |
| trackB-execution-state/PUBLISH_PAYLOAD_629_FOLLOWUP_20260921.md | publication/provenance payload | 07-history | released historical record | NO | pending |
| trackB-execution-state/TRACK_B_CLOSURE_RESULTS_20260921.md | closure / decision record | 06-closure | CLOSED / FROZEN | NO | reviewed |
| trackB-execution-state/TRACK_B_TECH_REPORT_629_FOLLOWUP_DRAFT_20260921.md | technical synthesis/report | 03-findings | released historical synthesis | NO | pending |
| trackB-execution-state/f5_3_policy_simulator.py | experiment implementation support | 07-history | historical experimental code | NO | pending |

All F1–F5 files remain evidence/history. The closure record is the legal endpoint; the README preserves the track boundary.

## 6. Track E — Residency / nodes-out

Track E contains multiple historical strata. Directory membership alone must not be used to infer one uniform state for every file. The current state records the nodes-out line as CLOSED; the mapping therefore preserves individual provenance.

### 6.1 Definition, design, finding, decision and closure records

| Original path | Type | Archive layer | Current status | Migration | Review |
|---|---|---|---|---|---|
| trackE-residency/README.md | track state / research definition | 00-governance + 01-questions | mixed historical state | NO | reviewed |
| trackE-residency/RESIDENCY_H-P1_OPENING_20260922.md | research opening | 01-questions | historical opening | NO | pending |
| trackE-residency/RESIDENCY_H-P1_DESIGN_20260922.md | experiment design | 01-questions | historical design | NO | pending |
| trackE-residency/RESIDENCY_H-P1_HOT_NULL_V2_DESIGN_20260922.md | null/design record | 01-questions | historical design | NO | pending |
| trackE-residency/RESIDENCY_H-P1_RESULTS_20260922.md | result evidence | 02-evidence | historical evidence | NO | pending |
| trackE-residency/RESIDENCY_NODES_OUT_DEFINITION_RECOVERY_20260922.md | definition recovery | 01-questions | historical definition record | NO | pending |
| trackE-residency/RESIDENCY_NODES_OUT_DESIGN_20260922.md | experiment design | 01-questions | historical design | NO | pending |
| trackE-residency/RESIDENCY_NODES_OUT_EXPERIMENT_DESIGN_20260922.md | experiment design | 01-questions | historical design | NO | pending |
| trackE-residency/NODES_OUT_EFFECT_INTERPRETATION_AUDIT_v0.1.md | interpretation audit | 03-findings | historical audit | NO | pending |
| trackE-residency/NODES_OUT_EFFECT_MECHANISM_SYNTHESIS_REVIEW_v0.1.md | synthesis review | 03-findings | historical synthesis | NO | pending |
| trackE-residency/NODES_OUT_EFFECT_VERDICT_DESIGN_REVISION_DRAFT_v0.1.md | decision/design draft | 04-decisions | historical draft | NO | pending |
| trackE-residency/NODES_OUT_EFFECT_VERDICT_DESIGN_REVISION_v0.2.md | decision/design revision | 04-decisions | accepted historical revision | NO | pending |
| trackE-residency/NODES_OUT_PATH_ENDPOINT_DECISION_v0.1.md | endpoint/path decision | 04-decisions | historical endpoint decision | NO | pending |
| trackE-residency/NODES_OUT_RESEARCH_ENDPOINT_DECISION_v0.1.md | research endpoint | 06-closure | accepted endpoint; basis of closure | NO | reviewed |
| trackE-residency/TRACK_E_CLOSED_RECORD_20260922.md | closure record | 06-closure | CLOSED | NO | reviewed |
| trackE-residency/RESIDENCY_POLICY_OPENING_20260921.md | policy opening | 01-questions | historical opening | NO | pending |
| trackE-residency/RESIDENCY_POLICY_SIM_V0_RESULTS_20260921.md | policy simulation evidence | 02-evidence | historical evidence | NO | pending |

### 6.2 Residency / P0–P3 evidence and audits

| Original path | Type | Archive layer | Current status | Migration | Review |
|---|---|---|---|---|---|
| trackE-residency/RESIDENCY_M1_RESULTS_20260921.md | result evidence | 02-evidence | historical result | NO | pending |
| trackE-residency/RESIDENCY_M2_RESULTS_20260921.md | result evidence | 02-evidence | historical result | NO | pending |
| trackE-residency/RESIDENCY_M3_RESULTS_20260921.md | result evidence | 02-evidence | historical result | NO | pending |
| trackE-residency/RESIDENCY_M3A_RESULTS_20260921.md | result evidence | 02-evidence | historical result | NO | pending |
| trackE-residency/RESIDENCY_M3B_RESULTS_20260921.md | result evidence | 02-evidence | historical result | NO | pending |
| trackE-residency/RESIDENCY_M3C_RESULTS_20260921.md | result evidence | 02-evidence | historical result | NO | pending |
| trackE-residency/RESIDENCY_M4_RESULTS_20260921.md | result evidence | 02-evidence | historical result | NO | pending |
| trackE-residency/RESIDENCY_P0_RESULTS_20260921.md | result evidence | 02-evidence | historical result | NO | pending |
| trackE-residency/RESIDENCY_P01_COST_UNIT_DRAFT_20260921.md | research/design draft | 01-questions | historical draft | NO | pending |
| trackE-residency/RESIDENCY_P02_RESULTS_20260921.md | result evidence | 02-evidence | historical result | NO | pending |
| trackE-residency/RESIDENCY_P3_DESIGN_DUAL_SCENARIO_20260921.md | experiment design | 01-questions | historical design | NO | pending |
| trackE-residency/RESIDENCY_P3_RESULTS_20260921.md | result evidence | 02-evidence | historical result | NO | pending |
| trackE-residency/RESIDENCY_P3A_RESULTS_20260921.md | result evidence | 02-evidence | historical result | NO | pending |
| trackE-residency/RESIDENCY_P3B_DESIGN_CAG_SHAPE_20260921.md | design / revision | 01-questions | historical design | NO | pending |
| trackE-residency/RESIDENCY_P3B_RESULTS_20260921.md | result evidence | 02-evidence | historical result | NO | pending |
| trackE-residency/RESIDENCY_P3C_DESIGN_F2_COUNTER_BASIS_20260921.md | design / decomposition | 01-questions | historical design | NO | pending |
| trackE-residency/RESIDENCY_P3C_RESULTS_20260921.md | result evidence | 02-evidence | historical result | NO | pending |
| trackE-residency/RESIDENCY_P3R2_RESULTS_20260921.md | result evidence | 02-evidence | historical result | NO | pending |
| trackE-residency/RESIDENCY_P4_AUDIT_20260921.md | audit / scope record | 03-findings | historical audit; current state says P4 proper NOT STARTED | NO | pending |

### 6.3 Track E implementation and run artifacts

| Original path | Type | Archive layer | Current status | Migration | Review |
|---|---|---|---|---|---|
| trackE-residency/hp1_hot_null_v2.py | experiment implementation | 07-history | historical code | NO | pending |
| trackE-residency/hp1_tier1_l1.py | experiment implementation | 07-history | historical code | NO | pending |
| trackE-residency/hp1_tier1_l3.py | experiment implementation | 07-history | historical code | NO | pending |
| trackE-residency/nodes_out_experiment_runner.py | experiment implementation | 07-history | frozen historical runner support | NO | pending |
| trackE-residency/nodes_out_tier1_mechanism_extractor.py | evidence extraction implementation | 07-history | historical/frozen support | NO | pending |
| trackE-residency/p4_live_policy_verifier.py | experiment implementation | 07-history | historical support; does not open P4 | NO | pending |
| trackE-residency/residency_policy_simulator_v0.py | simulation implementation | 07-history | historical implementation | NO | pending |
| trackE-residency/residency_policy_simulator_v1.py | simulation implementation | 07-history | historical implementation | NO | pending |
| trackE-residency/residency_policy_simulator_v2.py | simulation implementation | 07-history | historical implementation | NO | pending |
| trackE-residency/residency_policy_simulator_v3.py | simulation implementation | 07-history | historical implementation | NO | pending |
| trackE-residency/residency_policy_simulator_v4.py | simulation implementation | 07-history | historical implementation | NO | pending |
| trackE-residency/residency_policy_simulator_v5.py | simulation implementation | 07-history | historical implementation | NO | pending |
| trackE-residency/residency_policy_simulator_v6.py | simulation implementation | 07-history | historical implementation | NO | pending |
| trackE-residency/runs/ | run artifacts / provenance | 02-evidence + 07-history | historical run evidence | NO | inventory pending |

## 7. Result

This mapping establishes an archival overlay without destructive migration. Original track/experiment paths remain provenance locations. Current state remains governed by RESEARCH_STATE and endpoint/closure records. No research question, implementation, measurement, or experiment is opened by this document.

## 8. Next safe operation

Do not move files yet. Perform file-level semantic review in this order: Track B closure and F1–F5 chain; Track E endpoint and decision/audit chain; source/runtime Definition Opening chain; architecture source. Only after that should dedicated finding/decision cross-reference records be considered.

Until reviewed, entries marked pending remain pending.