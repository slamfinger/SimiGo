# SimiGo 2.0 Workload Trace Replay — 2026-09-25

Status: PHASE_WORKLOAD_TRACE_SIMULATOR_PASS / PHASE_WORKLOAD_TRACE_REAL_PASS / LOCALITY_ANALYSIS_PENDING
Model inventory: `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit`
Boundary: DECLARED_TRACE_STATE_MAPPING / DESCRIPTIVE_RECENCY_HINTS / NOT_PREDICTION / NOT_DEMAND_CLAIM
(Simulator replay = SIMULATOR_ONLY; real-runtime parts use the existing planner-integrated Gate 5 harness.)

## What was registered

Synthetic state sequences are now complemented by four replayable workload
traces. Each trace step carries a declared operation label, an execution-state
label, and the mapping rationale. The operation→state mapping is a declared
scenario-level choice registered with the trace catalog; it is not measured
demand and does not establish demand.

```text
T1_DOCUMENT_SESSION      DOCUMENT            open → summarize → search → edit → recheck → save
T2_COMPUTER_OPERATION    COMPUTER_OPERATION  file inspect → tool call → result → next op → tool call
T3_AGENTIC_MULTI_TURN    AGENTIC_MULTI_TURN  3 × (user turn → tool call → result) → final answer (ALL)
T4_LONG_CONTEXT          LONG_CONTEXT        context load (ALL) → extract AB → BC → AB → summary (ALL)
```

New simulator command:

```bash
simigo2ctl trace-replay MODEL_DIRECTORY [--traces ID,ID] [--budgets P,P]
```

The replay runs the `ExecutionResidencyPlanner` per step with the same
recency-hint construction as the budget sweep (three-step window, strictly
prior steps, decayed priority, 0.1 baseline). Per step it records required /
resident sets, required hit vs miss bytes, loaded / evicted bytes, overflow,
and per-run locality aggregates (required hit ratio, zero-retention
comparator, per-group load counts, required step indices).

## Simulator replay results (Qwen3-Coder inventory)

```text
recommended bytes = 17,180,913,664
core bytes        = 873,459,712
entries           = 66
```

Selected budgets (required-hit ratio / cumulative loaded GiB / overflow steps):

| Trace | 40% | 70% | 100% |
|---|---|---|---|
| `T1_DOCUMENT_SESSION` | 0.554 / 20.25 / 2 | 0.888 / 10.12 / 0 | 0.888 / 15.19 / 0 |
| `T2_COMPUTER_OPERATION` | 0.487 / 20.25 / 2 | 0.872 / 10.12 / 0 | 0.872 / 15.19 / 0 |
| `T3_AGENTIC_MULTI_TURN` | 0.547 / 35.44 / 4 | 0.871 / 15.19 / 1 | 0.935 / 15.19 / 0 |
| `T4_LONG_CONTEXT` | 0.531 / 30.38 / 5 | 0.531 / 30.38 / 2 | 0.766 / 15.19 / 0 |

Observations (descriptive, for the declared mappings only):

- At 70% budget the recency window covers the declared working set of T1/T2
  and almost all of T3 (its single ALL step overflows); required-hit ratios
  reach 0.871–0.888 with lower loaded bytes than the 100% budget.
- T4 touches `STATE_ALL` twice and `STATE_BC`; it needs 100% budget before
  overflow disappears.
- Below 70% every `STATE_AB` step overflows (core + two switch groups =
  68.4% of inventory), consistent with the budget-sweep thresholds.
- These numbers are properties of the declared trace mappings plus recency
  hints. They are not evidence that real workloads have this locality.

## Real-runtime trace results (Gate 5 harness, Apple M5)

The existing planner-integrated `mlx-gate5` benchmark (ALL_RESIDENT vs
NAIVE_ON_DEMAND vs EXECUTION_STATE_PLANNER, chat-template prompt) ran over
each trace's state sequence:

| Trace | benchmarkPass | output identity | idle reduction | reload vs naive | naive reload | state reload | gen (naive/state) |
|---|---|---|---:|---:|---:|---:|---|
| `T1` | PASS | PASS (`pong`) | 10.12 GiB | −20.25 GiB | 75.94 GiB | 55.69 GiB | 10.17 s / 9.71 s |
| `T2` | PASS | PASS (`pong`) | 10.12 GiB | −10.12 GiB | 60.75 GiB | 50.62 GiB | 8.42 s / 8.47 s |
| `T3` | PASS | PASS (`pong`) | 10.12 GiB | −40.50 GiB | 121.50 GiB | 81.00 GiB | 15.66 s / 14.63 s |
| `T4` | PASS | PASS (`pong`) | 5.06 GiB | −30.38 GiB | 60.75 GiB | 30.38 GiB | 8.24 s / 7.35 s |

Observations:

- State-driven retention reduced cumulative reload bytes versus naive
  on-demand on every trace. The largest reduction is on the longest trace
  (T3: 121.50 → 81.00 GiB) and the highest relative reduction on T4
  (60.75 → 30.38 GiB, −50%), whose ALL-start pattern keeps more of the
  working set relevant.
- Latency advantage remains NOT ESTABLISHED: generation totals are
  comparable between policies, and reload time is accounted separately, as
  in Gate 5.
- Real-runtime semantics are unchanged: every complete generation requires
  all decoder-layer groups; the policy controls idle retention between
  generations, not semantic layer skipping.

## Boundary

This phase does not authorize Predictor, Expert demand, Token × Expert
demand, real async I/O, or production residency policy. The trace state
mappings are declared scenario labels; hints are descriptive recency labels
derived only from prior steps; no result here predicts future state or
establishes execution demand.

Next gate (plan step ⑦): locality / reload / residency analysis over these
trace artifacts, followed by the demand-signal STOP GATE decision. A demand
predictor remains gated behind that decision.

Raw artifacts:

```text
simigo2-experimental/results/workload-trace/qwen3-coder-default.json       (simulator)
simigo2-experimental/results/workload-trace/qwen3-coder-real-T1..T4.json   (real runtime)
```
