# SimiGo 2.0 Experimental Route and MVP Plan

**Date**: 2026-09-23  
**Status**: ROUTE_REGISTERED / PHASE_0_COMPLETE / PHASE_1_COMPLETE / MLX_RUNTIME_GATES_1_5_PASS / PHASE_3_FEASIBILITY_PASS / APP_REAL_DEVICE_PROOF_PASS / NAIL_QWEN36_REAL_DEVICE_VALIDATION_PASS / GEMMA4_RESIDENCY_BOUNDARY_REGISTERED / MUSE_GLIMMER_TEXT_FORWARD_SUPPORTED / DENSE_MLP_EXTENSION_IMPLEMENTED / GEMMA4_DENSE_GATE5_PASS / MUSE_GLIMMER_DENSE_GATE5_PASS / SEMANTIC_QUALITY_UNRESOLVED / LATENCY_ADVANTAGE_NOT_ESTABLISHED
**Nature**: engineering experiment registration; not an A2.0 reopening, new formal theory, product release, or performance claim

## 1. Decision

Select a separate engineering route:

```text
SIMIGO2_EXPERIMENTAL
```

This is distinct from the frozen A2.0 value-core path. It does not rescue A2.0,
reopen R-INTERNAL, define a new theory, or claim architectural independence.

## 2. Experimental hypothesis

Use externally observable execution-state as the upstream control signal for model
layer-group residency and loading. Observe whether this state-driven resource
management has practical benefit over full-resident and naive on-demand baselines.

Minimal loop:

```text
external execution state
→ layer policy
→ layer residency / load / evict
→ model runtime execution
→ next execution state
```

## 3. MVP scope

### Included

```text
ExecutionStateObserver
LayerPolicy
LayerManager
RuntimeAdapter
MetricsCollector
BenchmarkRunner
```

First version uses deterministic external labels, for example:

```text
STATE_A   → CORE + GROUP_A
STATE_B   → CORE + GROUP_B
STATE_AB  → CORE + GROUP_A + GROUP_B
```

No prediction, compression, hidden-state analysis, model-internal interpretation, or
new mathematical theory is required in the first version.

### Excluded

```text
rewriting MLX/Metal kernels;
rewriting tokenizers or Transformer inference;
new quantization algorithms;
layer-similarity compression;
probability prediction;
hidden-state activation inspection;
production SimiGo 1.7 behavior changes.
```

## 4. Runtime strategy

Use mature open-source components, but implement only one primary runtime path in
the MVP:

```text
PRIMARY   = MLX Swift LM + MLX/Metal;
REFERENCE = llama.cpp residency/offload design;
DEFERRED  = vLLM serving/resource-management ideas.
```

The initial positive-control model is:

```text
mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit
```

because it is already known to load and run in SimiGo 1.7.

The experimental implementation should use a separate branch/harness. It must not
modify SimiGo 1.7 production behavior or the frozen research docs.

### Runtime reference rule

SimiGo 2.0 does not initially fork runtime internals. It wraps the selected runtime
and treats llama.cpp as prior art for layer/device residency, offload, mmap/lazy
tensor access, and buffer placement. vLLM is deferred until multi-request and KV
resource scheduling become relevant.

Runtime-selection record:

```text
docs/00-governance/SIMIGO2_RUNTIME_REFERENCE_SELECTION_20260924.md
```

## 5. Layer residency state machine

```text
RELEASED
  → LOADING
  → RESIDENT
  → ACTIVE
  → RESERVE / EVICTING
  → RELEASED
```

For MVP, `CORE` remains resident. Conditional groups are selected by deterministic
state policy.

Important: if the runtime cannot safely omit and later reload selected tensors, the
experiment must use a residency simulator rather than pretend that omitted tensors
can be skipped during real inference.

## 6. Phase plan

### Phase 0 — Feasibility and inventory

Complete. The Qwen3-Coder Safetensors inventory and MLX selective group
materialization probes are complete.

Deliverables:

```text
weight/tensor inventory by logical group;
resident-size estimate per group;
runtime partial-load capability report;
candidate CORE/GROUP_A/GROUP_B partition;
identified runtime limitations.
```

Initial inventory report:

```text
docs/00-governance/SIMIGO2_PHASE0_QWEN3_CODER_INVENTORY_20260923.md
```

Gate results:

```text
docs/00-governance/SIMIGO2_PHASE0_MLX_GATE1_RESULTS_20260924.md
docs/00-governance/SIMIGO2_PHASE0_MLX_GATE2_RESULTS_20260924.md
```

Pending Phase 0 audits:

```text
llama.cpp residency/offload reference audit.
```

### Phase 1 — Residency-manager harness

Implement state and layer-group state transitions without necessarily performing
real inference.

### Phase 2 — Runtime adapter integration

Integrate with the selected MLX runtime only after Phase 0 proves a legal load path.

### Phase 3 — Benchmark

Run full-resident, naive on-demand, and state-driven policies.

## 7. Metrics

```text
first load time;
state-transition overhead;
resident layer count / bytes;
peak memory;
time-to-first-token;
decode tokens/second;
reload count;
end-to-end latency;
output/token consistency where the same tensors are loaded.
```

## 8. Baselines

```text
A: all groups resident;
B: naive on-demand load;
C: SimiGo 2.0 execution-state-driven policy.
```

## 9. Success / pivot criteria

Success requires:

```text
generation completes;
state policy actually changes residency;
semantic output remains consistent when required tensors are resident;
memory or latency benefit is measurable over at least one baseline.
```

Pivot or stop if:

```text
partial group loading is impossible without invasive model-internal changes;
state labels cannot be derived from external observations;
overhead exceeds all practical benefit;
the result collapses into ordinary on-demand loading with no execution-state value.
```

## 10. Boundaries

This route does not reopen A2.0, define new mathematical objects, select an A2.0
research road, create `R-INTERNAL-20`, define R_ORACLE or Δ/gap, enable FinLoss or
NECT, enter STEP⑤/STEP⑥, or authorize production release.
