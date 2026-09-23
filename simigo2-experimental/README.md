# SimiGo 2.0 Experimental Scaffold

This is an experimental harness for **execution-state-driven layer-group
residency**. MLX runtime gates now cover selective tensor materialization,
whole-group lifecycle, parameter restore, single-group inference residency, and a
multi-state real-runtime benchmark. It does not modify MLX internals or skip
layers during complete inference.

## Current goal

Validate this loop first:

```text
external execution state
→ deterministic layer policy
→ layer-group residency transition
→ metrics
→ next external execution state
```

The first runtime adapter is therefore a simulator. Real MLX partial-load behavior
is still gated by Phase 0.

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

# Run the real-device Gate 5 self-test from the app bundle
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

Do not add real MLX model loading until Phase 0 proves legal partial-layer loading.
