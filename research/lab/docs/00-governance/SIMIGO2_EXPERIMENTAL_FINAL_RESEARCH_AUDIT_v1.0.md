# SimiGo 2.0 Experimental — Final Research Audit v1.0

Status: FINAL_AUDIT_v1.0_REGISTERED / RESEARCH_LINE_FROZEN / RUNTIME_RESIDENCY_ENGINEERING_DECLARED
Date: 2026-09-25
Purpose: terminal ledger of the entire SimiGo 2.0 Experimental research line
(A2.0 → G1.9-E0). This is an audit, not an experiment: every claim below is
anchored to a registered commit and artifact. Research line = FROZEN.
Successor engineering route = declared, requirements-first, not started.

## 0. Chain overview (with anchors)

```text
A2.0 value core
  → formalization → concrete instance (P0,θ0′: R=5376, att=true, uniq=false)
  → boundary/adversarial audits → GENERIC_REDUCIBLE, INDEPENDENT_THEORY
    NOT ESTABLISHED → FROZEN/TERMINAL (2026-09-23)
      docs/07-history/A2_VALUE_CORE_FREEZE_POINT_20260923.md
SimiGo 2.0 Experimental route registered (PHASE_0_AUTHORIZED, 2026-09-23)
  → Phase 0/1 foundations: inventory, Gates 1–5, real-device proofs (2026-09-24)
  → R0 planner↔runtime integration PASS (725a2f1)
  → planner budget sweep, simulator (125a9c7)
  → ⑥ workload traces T1–T4: simulator replay + real MLX replay (9c31954)
  → ⑦ multi-model locality analysis → PREDICTOR_STOP_GATE_NO_GO (6e8b153)
  → G1.9-A authorization (fae0bfc) → first capture (fed32b2) → pilot (8cf0710)
  → G1.9-C measured collection (7c9cb68) → degenerate
  → G1.9-C post-audit + residency observability audit (bb2fc1e)
  → G1.9-D retention analysis (329d762) → exact economics identity
  → G1.9-E0 feasibility audit (8eb27bb) → trade-off frontier only
  → user ruling STOP (35c1d18) → CURRENT RESOLUTION CLOSED
    docs/00-governance/SIMIGO2_GROUP_RESOLUTION_LINE_CLOSED_20260925.md
```

Historical pre-experimental mainline (RQ-B-01 / P3 / H-P1 / Track E) was
already CLOSED/SEALED before this route began and is unaffected.

## 1. Measured and proven (real models, real runs)

Each item names its instrument and evidence:

1. **Semantic preservation under group residency.** Selective
   materialization/release of layer groups does not change model outputs:
   Gate 3/4 (single group, single model), Gate 5 and all 20 real trace runs
   (5 models × 4 workloads) pass output identity; planner-integrated R0
   passed 15-generation identity. Reload savings measured against naive
   on-demand: 16.7–55% per (model, trace) pair.
2. **Instrumentation preserves computation exactly.** Isolated module
   replacement (Linear / QuantizedLinear / SwitchLinear / QuantizedSwitchLinear
   re-implementations) yields bitwise-identical logits (SHA-256, max_abs_diff
   = 0) and identical generated token sequences: 15/15 pilot cases, plus the
   collection identity sentinels 5/5, plus first-capture battery V1–V4.
3. **Instrumentation observes stably.** Repeated identical inputs produce
   event-stream-identical traces (3 repetitions × 15 pilot cases; collection
   pass counts identical across repetitions).
4. **Execution set at layer/group resolution is the full set.** 125
   operations × 5 models: every forward pass executes every decoder-layer
   MLP group; C1/C3 degenerate, C2 = 1.0, C4 breadth = full at 100% of
   steps. Declared ⊆ measured at 125/125 steps with excess exactly on the
   22 non-STATE_ALL declared steps per model.
5. **Residency bookkeeping is byte-validated by an independent observation.**
   375 transition rows (25 transitions × 3 policies × 5 models): MLX
   aggregate idle bytes equal the bookkeeping-predicted resident bytes after
   a per-model-class constant offset (Qwen3-Coder maxRel 4.6e-5; Gemma4
   3.6e-4; Muse 6.6e-4; Nail/Cyber-Tiel exactly constant −851.1/−851.5 MiB,
   reconciled to the un-loaded vision_tower: 333 tensors, 851.8 MiB,
   residual < 0.8 MiB).
6. **Reload economics decompose exactly.** D4 identity
   `savings = Σ_t retainedOptionalBytes(t) − oneColdStartLoad` holds on
   20/20 pairs (<0.1%); E0 frontier identity
   `reloadTotal = n·optionalTotal − retainedLeadingIntegral` holds for all
   4 candidates × 20 pairs (80 offline replays).
7. **Cross-model viability.** Five checkpoints (three switch-MoE — Qwen3-
   Coder, Nail-Qwen3.6, Cyber-Tiel (first residency validation) — and two
   dense — Gemma4-12B, Muse-Glimmer-30B) are inventory-able, instrumentable,
   and pass the full identity battery; module-naming variants
   (`model.layers.*` vs `language_model.model.layers.*`) and shared_expert
   exclusion are registered.

## 2. Policy-derived (labeled as such, never natural observations)

- Per-transition group resident sets (Swift-side bookkeeping; byte-validated
  in aggregate only).
- Retention-structure constants (D1 keep ratios T1 0.600 / T2 0.500 /
  T3 0.521–0.537 / T4 0.667–0.742; D3 lag-1 overlaps 0.553–0.795):
  deterministic functions of (policy, state sequence).
- Declared workload→state mappings (T1–T4) and their scenario prompts
  (G1.9-C registry): scenario declarations, not measured demand.
- Simulator-layer results: planner budget-sweep thresholds (40/70/100%),
  trace-replay required-hit ratios, recency-hint behavior — planning-layer
  measurements under declared inputs.

## 3. Engineering facts

- `ExecutionResidencyPlanner` is a pure planner that runs end-to-end inside
  a real MLX runtime (R0, Gate 5 harness): inputs (resident, required,
  budget) → outputs (load/keep/evict/overflow) → executed transfers with
  output identity preserved.
- The Gate 5 harness's load-before-generation semantics (execution = ALL)
  is what makes any post-generation retention policy correctness-preserving.
- Latency advantage was never established (generation totals comparable;
  Nail/Cyber-Tiel T3/T4 state-side slightly slower) — honest negative.
- Harness limitations registered: no-KV-cache generation loop (quadratic);
  overhead timing at sub-second scales is noise-dominated (pilot A.3:
  0.72–7.95, direction inconsistent); Qwen3-Coder pilot ratio >1.9 flagged
  for a dedicated timing study if it ever matters.
- Pre-run audit yield: three real defects found and fixed before any trace
  was trusted (nested `container.perform` deadlock; QuantizedLinear
  mis-cloning in the identity probe; module-path prefix blindness), plus a
  module-path discovery command and a C_model inventory reconciliation item
  (vision_tower).

## 4. Falsified premises

1. **"Group-level execution has differential locality to exploit."**
   Falsified by measurement (G1.9-C): execution = FULL everywhere observed;
   ΔM_t = ∅.
2. **"Declared workload states reflect measured execution demand."**
   Falsified as an identification claim: declared is a strict subset of the
   measured full set, with excess exactly where the scenario declared less
   than ALL. Declared mappings are scenario labels.
3. **"The measured 16.7–55% reload savings indicate exploitable execution
   locality."** Falsified as an interpretation: the savings are retention
   economics (D4 identity), and the ordering evidence is inverse (T4 lowest
   declarative hit, highest real savings).
4. **"Observing execution must perturb it."** Refuted within the validated
   boundary: event-only isolated instrumentation is bitwise-neutral and
   ≈zero-overhead (within noise), though the claim stays scoped to the
   tested battery.
5. **"There is remaining free optimization space in the group-resolution
   policy space."** Falsified (E0): any reload gain is exactly paid for by
   higher retention integral; no candidate dominates the current policy.

## 5. Closed questions

- **Predictor (layer/group resolution): CLOSED** —
  RESOLUTION-DEGENERATE / NO PREDICTIVE TARGET (semantic closure, measured).
- **Group-resolution execution locality: CLOSED** (degenerate).
- **Retention structure characterization: CLOSED** (empirically
  characterized; exact economics identity).
- **Free-improvement existence: CLOSED** (none; exact frontier; no
  domination).
- **Does isolated instrumentation change compute semantics: CLOSED** (no,
  within the registered battery).
- **A2.0 independent-theory question: CLOSED** (FROZEN/TERMINAL generic
  reduction; methodological value demonstrated).
- **Group-resolution Experimental research line: CLOSED** (G19E0_STOP,
  35c1d18).

## 6. Explicitly NOT authorized (standing)

- Router / Expert / Token×Expert observation or modeling;
- Predictor, probability, demand-probability, speculative loading/retention;
- new runtime instrumentation beyond the registered isolated path;
- production MLX modifications;
- async I/O / I/O-compute overlap implementation;
- cost weighting, optimizer, optimal-policy definitions;
- general-architecture declarations from any result above;
- frozen vocabulary stays frozen: OptimalResidentSet, OptimalRetentionPolicy,
  RetentionPredictor, ResidencyDemand, ResidencyProbability.

## 7. Reopenable questions (with concrete triggers)

1. **Bounded residency optimization** — trigger: a real deployment
   constraint pair (e.g. peak memory ≤ X GiB AND reload latency ≤ Y ms) or
   workload SLA/long-session memory-pressure evidence. This would supply
   the missing value weights that E0 showed are prerequisite.
2. **Async materialization / I-O–compute overlap** — trigger: measured
   reload latency becoming an actual bottleneck under a real serving loop.
3. **Finer-resolution execution observation (Router/Expert)** — trigger: a
   concrete phenomenon that requires it (e.g. execution ≠ FULL observed at
   some resolution/model class, which itself needs new observation
   authorization). Model class being MoE is not a trigger.
4. **C0–C5 computational-semantics formalization** — registered candidate,
   deferred; unchanged.
5. **Engineering follow-ups** (non-research): Muse-Glimmer semantic quality
   (UNRESOLVED); Qwen3-Coder pilot overhead timing study; KV-cache-bearing
   generation harness.

## 8. The core finding

> **A complete Transformer generation has no execution locality at
> layer/group resolution, but residency retention still has an independent,
> strictly measurable engineering structure; its benefit is exactly a
> trade-off between memory residency and re-materialization — not
> computation skipping.**

Negative result: no exploitable execution locality at this resolution (no
predictive target). Positive result: policy-level residency retention is
measurable, byte-validated, exactly decomposable, and sits on a fully
characterized linear trade-off frontier with no free improvement.

## 9. Ledger corrections

- The residency observability audit document stated "225 transitions" for
  the byte-level validation; the correct total is **375 rows** (75 per
  model × 5 models; 25 transitions × 3 policies each). Per-model figures
  were correct; only the total was misstated. This document supersedes that
  count.

## 10. Handoff — research line frozen, engineering route declared

```text
SimiGo 2.0 Experimental research line : CLOSED / FROZEN (this audit)
SimiGo 2.0 Runtime Residency Engineering : DECLARED, NOT STARTED
```

The successor engineering route (separate from the closed research line;
no theory objects, no demand vocabulary) is registered with the sequenced
work items:

| # | Work item | Status |
|---|---|---|
| 1 | Final Research Audit (this document) | DONE |
| 2 | G1.9 research line freeze | DONE (35c1d18 + this audit) |
| 3 | Runtime Residency Engineering requirements definition | NEXT (no code) |
| 4 | Planner → Runtime Controller verification | engineering validation |
| 5 | Long-session / real SimiGo workload integration | engineering validation |
| 6 | Memory pressure / budget policy | conditional entry |
| 7 | Async materialization | only if reload latency becomes the bottleneck |
| 8 | Router / Expert | not entered |

Requirements-definition questions registered for item 3 (from the review):
budget provenance; resident-state provenance; who executes load/evict;
failure, overflow, and cancellation semantics; multi-request
serialization/concurrency; long-context handling; memory-pressure behavior.
The planner keeps its verified contract: inputs (required execution set,
current resident set, memory budget) → outputs (load / keep / evict /
overflow) — and never predicts.

## Appendix — artifact index

```text
docs/00-governance/SIMIGO2_EXPERIMENTAL_ROUTE_AND_MVP_PLAN_20260923.md
docs/00-governance/SIMIGO2_PLANNER_RUNTIME_INTEGRATION_R0_20260924.md
docs/00-governance/SIMIGO2_PLANNER_BUDGET_SWEEP_20260925.md
docs/00-governance/SIMIGO2_WORKLOAD_TRACE_REPLAY_20260925.md
docs/00-governance/SIMIGO2_MULTI_MODEL_LOCALITY_ANALYSIS_STOP_GATE_20260925.md
docs/00-governance/SIMIGO2_G19A_ISOLATED_INSTRUMENTATION_AUTHORIZATION_20260925.md
docs/00-governance/SIMIGO2_G19A_GROUP_TRACE_DESIGN_PRERUN_AUDIT_20260925.md
docs/00-governance/SIMIGO2_G19A_PILOT_RESULTS_20260925.md
docs/00-governance/SIMIGO2_G19C_MEASURED_TRACE_COLLECTION_20260925.md
docs/00-governance/SIMIGO2_G19C_POST_AUDIT_20260925.md
docs/00-governance/SIMIGO2_RESIDENCY_OBSERVABILITY_AUDIT_20260925.md
docs/00-governance/SIMIGO2_G19D_POLICY_RETENTION_ANALYSIS_20260925.md
docs/00-governance/SIMIGO2_G19E0_RETENTION_FEASIBILITY_AUDIT_20260925.md
docs/00-governance/SIMIGO2_GROUP_RESOLUTION_LINE_CLOSED_20260925.md
simigo2-experimental/results/{workload-trace,g19a-pilot,g19-collect,
  residency-audit,instrumentation-audits,planner-budget-sweep,planner-integration}/
simigo2-experimental/scripts/{analyze_trace_locality,analyze_measured_locality,
  audit_residency_observability,analyze_policy_retention,
  audit_retention_feasibility}.py
Commits: 725a2f1 125a9c7 9c31954 6e8b153 fae0bfc fed32b2 8cf0710 7c9cb68
         bb2fc1e 329d762 8eb27bb 35c1d18
```
