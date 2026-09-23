# SimiGo 2.0 Runtime Reference Selection

**Date**: 2026-09-24  
**Status**: PRIMARY_RUNTIME_SELECTED / REFERENCE_AUDIT_PLANNED  
**Nature**: engineering runtime-selection decision; not a theory claim or implementation authorization

## 1. Decision

SimiGo 2.0 Experimental uses a two-runtime learning strategy, but implements only
one primary runtime path first:

```text
PRIMARY MVP RUNTIME   = MLX Swift LM on Apple Silicon / Metal
PRIMARY MODEL FORMAT  = MLX Safetensors checkpoint
REFERENCE RUNTIME     = llama.cpp
DEFERRED RUNTIME      = vLLM
```

The first implementation does not run both runtimes simultaneously and does not
introduce a universal runtime abstraction yet.

## 2. Roles

### MLX Swift LM — primary implementation base

MLX Swift LM is selected as the first executable base because it matches the local
Apple Silicon environment and the known positive-control checkpoint:

```text
mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit
```

It already provides the relevant model-loading and inference foundation:

```text
MLX model loading;
LLM architectures;
quantized checkpoints;
Swift runtime integration;
Metal execution.
```

SimiGo 2.0 will not rewrite Transformer inference, tokenization, quantization, KV
cache, or Metal kernels.

### llama.cpp — residency/offload reference

llama.cpp is selected as the first prior-art reference for layer residency and
offload behavior. Its public configuration concepts are useful references for the
SimiGo layer-manager interface:

```text
layer count assigned to accelerator;
layer-split placement;
CPU/GPU offload;
mmap-backed weight access;
lazy/on-demand tensor reading;
tensor buffer placement overrides;
CPU-offloaded MoE/FFN behavior.
```

These references help SimiGo design:

```text
LayerGroup;
ResidencyState;
PlacementPolicy;
LoadPolicy;
EvictionPolicy.
```

They are references, not commitments to port llama.cpp code or adopt GGUF as the
MVP model format.

### vLLM — deferred reference

vLLM is deferred. Its later value is expected to come from serving-oriented resource
ideas:

```text
paged KV memory;
continuous batching;
multi-request scheduling;
memory-pressure-aware placement.
```

These topics become relevant only after the single-model, single-request MVP loop is
measured.

## 3. First implementation boundary

The MVP remains:

```text
ExecutionStateObserver
→ LayerPolicy
→ LayerManager
→ MLX Swift LM RuntimeAdapter
→ MetricsCollector
```

It does not attempt to combine MLX and llama.cpp in one process, translate MLX
checkpoints to GGUF, or create a runtime-independent model format.

## 4. Phase 0 additions

Phase 0 now has three audits:

```text
1. Qwen3-Coder tensor/group inventory      = complete;
2. MLX Swift LM partial-load feasibility   = pending;
3. llama.cpp residency/offload reference    = pending source audit.
```

The key Phase 0 question remains:

```text
Can the selected runtime legally change layer-group residency without invasive
model-internal modification?
```

If MLX Swift LM cannot do this, the first result must be recorded as a residency
simulator, not as real execution.

## 6. References

```text
MLX Swift LM:
https://github.com/ml-explore/mlx-swift-lm

llama.cpp:
https://github.com/ggml-org/llama.cpp

llama.cpp public residency/offload interface examples:
https://github.com/ggml-org/llama.cpp/blob/master/include/llama.h
https://github.com/ggml-org/llama.cpp/blob/master/docs/multi-gpu.md

vLLM:
https://github.com/vllm-project/vllm
```

These references are prior-art inputs. The listed llama.cpp capabilities must still be
confirmed against the pinned source revision during the reference audit.

## 7. Boundaries

This decision does not authorize production integration, performance claims, a new
model architecture, R-INTERNAL-20, route reopening, R_ORACLE, Δ/gap, FinLoss, NECT,
STEP⑤/STEP⑥, data collection, profiling, measurement, or benchmark execution.
