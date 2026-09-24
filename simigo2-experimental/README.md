# SimiGo 2.0 Experimental Scaffold

This is an experimental harness for **execution-state-driven layer-group residency**. Real MLX runtime gates now cover selective tensor materialization, whole-group lifecycle, parameter restore, single-group inference residency, and multi-state real-runtime residency benchmarks. The harness does not modify MLX internals or skip Transformer layers during complete inference.

## Current goal

Validate this loop first:

```text
external execution state
→ deterministic layer policy
→ layer-group residency transition
→ metrics
→ next external execution state
```

The current runtime path is a real MLX experiment plus a pure Swift/Safetensors materialization path. It is no longer gated on a hypothetical Phase 0 partial-layer API.

## Current experimental scope

The residency mechanism currently controls **idle retention between complete generations**:

```text
execution state
→ desired resident groups
→ release/retain after generation
→ next transition
→ reload missing groups
```

A complete Transformer generation still materializes all decoder-layer groups required by the model. Therefore the current experiment does **not** demonstrate layer skipping, reduced Transformer compute, or predictive next-state loading.

The current generation identity probe intentionally uses a cache-free forward path for controlled parameter-replacement/residency validation. Its generation time must not be interpreted as normal KV-cache decode latency.

## Supported runtime families

The grouping layer currently has separate strategies for:

- Qwen3-Coder-style switch/MoE MLP groups
- dense MLP groups used by Gemma4 and Muse-Glimmer-compatible checkpoints

Model compatibility is an experimental runtime gate, not a claim of universal MLX architecture support.

## Commands

```bash
swift build
swift test

# Inventory a local HF snapshot directory
swift run simigo2ctl inventory \
  /path/to/model-snapshot

# Simulate deterministic state transitions
swift run simigo2ctl simulate \
  /path/to/model-snapshot \
  --states STATE_A,STATE_B,STATE_ALL

# Compare full-resident, reactive, and llama.cpp-inspired lazy policies
swift run simigo2ctl benchmark \
  /path/to/model-snapshot \
  --states STATE_A,STATE_B,STATE_AB,STATE_A,STATE_ALL

# Read only newly required layer groups for each execution state
swift run simigo2ctl materialize \
  /path/to/model-snapshot \
  --states STATE_A,STATE_B,STATE_AB,STATE_A,STATE_ALL

# Gate 1: materialize one group as real MLX arrays
swift run simigo2ctl mlx-gate1 \
  /path/to/model-snapshot \
  --group SWITCH_MLP_L00_15

# Build the local SwiftUI app bundle
./scripts/build-app.sh debug

# Run the real-device residency self-test from the app bundle
./build/SimiGo2Experimental.app/Contents/MacOS/SimiGo2App \
  --self-test \
  --model /path/to/model-snapshot \
  --states STATE_A,STATE_B,STATE_AB,STATE_A,STATE_ALL
```

## MVP policy

```text
CORE_NON_SWITCH   = always resident
STATE_A           = CORE + SWITCH_MLP_L00_15
STATE_B           = CORE + SWITCH_MLP_L16_31
STATE_C           = CORE + SWITCH_MLP_L32_47
STATE_AB          = CORE + SWITCH_MLP_L00_15 + SWITCH_MLP_L16_31
STATE_BC          = CORE + SWITCH_MLP_L16_31 + SWITCH_MLP_L32_47
STATE_ALL         = CORE + all switch groups
```

## llama.cpp reference mapping

This scaffold borrows concepts, not implementation:

```text
llama.cpp n_gpu_layers / split_mode / mmap / lazy_mode / tensor_buft_override
    → SimiGo LayerPolicy / LayerGroup / ResidencyState / future RuntimeAdapter
```

The llama.cpp mapping is a conceptual reference only; it does not imply feature parity.

## Research boundary

Current evidence supports:

- selective Safetensors materialization
- real MLX parameter replacement/rematerialization
- group lifecycle and parameter restore
- output-identity validation
- execution-state-driven idle residency reduction
- reduced reload traffic versus naive on-demand in the tested workloads

Current evidence does **not** establish:

- normal KV-cache decode latency improvement
- overall performance improvement
- Transformer layer skipping
- reduced Transformer compute
- predictive loading from future-state probabilities
- a general SimiGo architecture

The next useful experiment is to vary and repeat **state sequences/locality** on stable model targets rather than expanding the model list indiscriminately.
