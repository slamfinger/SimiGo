# SimiGo 2.0 Phase 1 Scaffold — Execution-State Residency

**Date**: 2026-09-24  
**Status**: SCAFFOLD_IMPLEMENTED / POLICY_BENCHMARK_COMPLETE  
**Runtime**: pure Swift residency-control harness; no MLX internals modified  
**Location**: `simigo2-experimental/`

## 1. Implemented architecture

```text
simigo2ctl
    ↓
ExecutionStateLabel
    ↓
LayerResidencyPolicy
    ↓
LayerResidencyEngine
    ↓
TransitionReport / Metrics
```

Components:

```text
SafetensorsInventoryReader = read index/header tensor metadata without MLX;
LayerGroupCatalog          = partition Qwen3-Coder tensors;
Qwen3CoderStatePolicy      = external state → required layer groups;
LayerResidencyEngine       = load/keep/evict delta execution;
ResidencyBenchmark         = compare residency policies.
```

## 2. Validation

```text
swift build = PASS
swift test  = PASS / 5 tests
```

Tests cover:

```text
Qwen3-Coder group partition;
always-resident core policy;
state-to-group mapping;
load/evict delta behavior;
all policy report generation.
```

## 3. Qwen3-Coder benchmark

Command:

```bash
swift run simigo2ctl benchmark \
  /path/to/Qwen3-Coder-30B-A3B-Instruct-4bit \
  --states STATE_A,STATE_B,STATE_AB,STATE_A,STATE_ALL
```

| Policy | Initial/full resident bytes | Peak resident bytes | Cumulative loaded | Cumulative evicted | Control decisions |
| --- | ---: | ---: | ---: | ---: | ---: |
| `allResident` | 17,180,913,664 | 17,180,913,664 | 17,180,913,664 | 0 | 20 |
| `reactive` | 6,309,277,696 initial | 17,180,913,664 | 28,052,549,632 | 10,871,635,968 | 15 |
| `llamaCppLazy` | 6,309,277,696 initial | 17,180,913,664 | 28,052,549,632 | 10,871,635,968 | 15 |

Interpretation:

```text
allResident minimizes reload work but maximizes steady residency.
reactive and lazy reduce peak residency until STATE_ALL.
alternating/omnivorous states can increase cumulative load traffic.
```

This is a pure control-plane measurement. It does not measure real model latency or
Metal tensor-materialization cost.

## 4. llama.cpp concepts mapped

| llama.cpp concept | SimiGo 2.0 scaffold counterpart | Status |
| --- | --- | --- |
| `n_gpu_layers` | optional resident group cap | simulated |
| `split_mode=layer` | decoder-range `switch_mlp` groups | implemented in inventory/policy |
| mmap | future lazy tensor source | not implemented |
| lazy tensor read | future group materialization | not implemented |
| tensor buffer override | future placement policy | not implemented |

## 5. Next gate

The next implementation step is an MLX Swift LM probe:

```text
can switch_mlp tensors be lazily materialized or swapped by group
without changing model semantics?
```

If no, keep this harness as a residency simulator.
