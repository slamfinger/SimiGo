# SimiGo 2.0 Experimental Scaffold

This is an experimental harness for **execution-state-driven layer-group residency**. Real MLX runtime gates now cover selective tensor materialization, whole-group lifecycle, parameter restore, single-group inference residency, and multi-state real-runtime residency benchmarks. The harness does not modify MLX internals or skip Transformer layers during complete inference.

## Current goal

The residency path is being refined toward an execution-centric separation:

    execution context
        ↓
    required execution set
        ↓
    bounded residency plan
        ↓
    materialization / eviction
        ↓
    execution
        ↓
    runtime observations

The existing execution-state experiment remains the baseline. The new planner is an engineering layer and does not replace that baseline.

## Current experimental scope

The residency mechanism currently controls **idle retention between complete generations**.

A complete Transformer generation still materializes all decoder-layer groups required by the model. Therefore the current experiment does **not** demonstrate layer skipping, reduced Transformer compute, or predictive next-state loading.

The current generation identity probe intentionally uses a cache-free forward path for controlled parameter-replacement/residency validation. Its generation time must not be interpreted as normal KV-cache decode latency.

## ds4-inspired engineering refinement

The independent antirez/ds4 runtime demonstrates a useful execution-centric pattern: distinguish the parameters required by the current execution from the bounded set kept resident, then manage materialization and eviction under an explicit memory budget.

SimiGo now has a pure planning implementation of this separation:

    Required Execution Set
            ↓
    ExecutionResidencyPlanner
       ┌────┴──────────────┐
       │                   │
    mandatory/core     working-set candidates
       │                   │
       └─────────┬─────────┘
                 ↓
          Load / Keep / Evict
                 ↓
          Materialization
                 ↓
              MLX

The planner supports fixed or percentage budgets, mandatory/core reservation, externally supplied demand priorities, deterministic candidate ordering, and explicit overflow reporting.

This does not claim feature parity with ds4. In particular, SimiGo has not yet implemented ds4's model-specific expert routing, SSD-streaming backend, asynchronous I/O-compute overlap, or distributed execution.

## Supported runtime families

The grouping layer currently has separate strategies for:

- Qwen3-Coder-style switch/MoE MLP groups
- dense MLP groups used by Gemma4 and Muse-Glimmer-compatible checkpoints

Model compatibility is an experimental runtime gate, not a claim of universal MLX architecture support.

## Commands

    swift build
    swift test

    swift run simigo2ctl inventory /path/to/model-snapshot

    swift run simigo2ctl simulate /path/to/model-snapshot --states STATE_A,STATE_B,STATE_ALL

    swift run simigo2ctl benchmark /path/to/model-snapshot --states STATE_A,STATE_B,STATE_AB,STATE_A,STATE_ALL

    swift run simigo2ctl materialize /path/to/model-snapshot --states STATE_A,STATE_B,STATE_AB,STATE_A,STATE_ALL

    swift run simigo2ctl mlx-gate1 /path/to/model-snapshot --group SWITCH_MLP_L00_15

    swift run simigo2ctl mlx-sequence-sweep /path/to/model-snapshot --sequences BASELINE_ABA,LOCALITY_A,ALTERNATE_AB,CYCLE_ABC,ALTERNATE_A_AB,FULL_PARTIAL

## MVP policy

    CORE_NON_SWITCH   = always resident
    STATE_A           = CORE + SWITCH_MLP_L00_15
    STATE_B           = CORE + SWITCH_MLP_L16_31
    STATE_C           = CORE + SWITCH_MLP_L32_47
    STATE_AB          = CORE + SWITCH_MLP_L00_15 + SWITCH_MLP_L16_31
    STATE_BC          = CORE + SWITCH_MLP_L16_31 + SWITCH_MLP_L32_47
    STATE_ALL         = CORE + all switch groups

The existing CORE_NON_SWITCH classification remains a harness grouping, not a scientifically established permanent Core Resident Set.

## Research boundary

Current evidence supports:

- selective Safetensors materialization
- real MLX parameter replacement/rematerialization
- group lifecycle and parameter restore
- output-identity validation
- execution-state-driven idle residency reduction
- reduced reload traffic versus naive on-demand in the tested workloads
- a pure execution-residency planning layer with explicit budget semantics

Current evidence does **not** establish:

- normal KV-cache decode latency improvement
- overall performance improvement
- Transformer layer skipping
- reduced Transformer compute
- predictive loading from future-state probabilities
- a general SimiGo architecture
- universal layer/expert semantic specialization
- ds4 feature parity

The next useful validation is to run planner tests, compare planner decisions with the current deterministic residency baseline, and then use repeated real-device traces to measure cache hits, reload bytes, idle residency, and reload timing before introducing preload or I/O-compute overlap.

The research-depth governance remains in force: research depth follows evidence, not curiosity.
