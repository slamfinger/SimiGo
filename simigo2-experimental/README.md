# SimiGo 2.0 Experimental Scaffold

This is a Phase 1 engineering scaffold for **execution-state-driven layer-group
residency**. It intentionally does **not** implement model inference or modify MLX
internals.

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
