# SimiGo 2.0 Experimental — ds4 Runtime Design Adaptation v0.1

Date: 2026-09-24
Status: EXPERIMENTAL / ENGINEERING ADAPTATION
A2.0 status: FROZEN / UNAFFECTED

## 1. Purpose

The independent antirez/ds4 runtime provides a mature, concrete example of execution-centric model residency engineering. SimiGo 2.0 Experimental will borrow its engineering principles and selectively reusable code patterns, without treating ds4's model-specific implementation as a universal architecture.

Reference repository:
https://github.com/antirez/ds4

The ds4 repository is MIT licensed. Any future direct code reuse must preserve the applicable copyright and license notice.

## 2. What is being borrowed

The important reusable ideas are not simply "load/unload experts".

### 2.1 Actual execution set before residency set

Make the runtime distinction explicit:

    model parameter universe
            ↓
    currently required execution set
            ↓
    residency decision
            ↓
    materialization / eviction

required and resident are different sets.

A group may be resident without being required for the current step. A required group may be cold and therefore need materialization.

### 2.2 Bounded working-set cache

Instead of treating all optional parameters as permanently resident, use an explicit byte/slot budget:

    mandatory/core
          +
    required working set
          +
    optional preload candidates
          ≤ residency budget

This follows the useful engineering pattern visible in ds4's SSD-streaming path: non-routed/shared weights are retained when possible, while a bounded cache is used for routed experts.

SimiGo does not assume that this policy is universally optimal. It is an implementation hypothesis to measure.

### 2.3 Preload as an optional optimization

Preloading is downstream of demand evidence.

The planner may consume a demand priority, but the priority is not itself a probability and does not imply predictive correctness.

    observed/declared demand hint
            ↓
    candidate priority
            ↓
    optional preload

No predictor is introduced by this layer.

### 2.4 Eviction is a policy decision, not an execution fact

A group being cold is an observed/runtime condition. Eviction is an engineering response.

The planner therefore produces:

- load;
- keep;
- evict;
- overflow.

It does not mutate MLX or the model.

### 2.5 Materialization source remains replaceable

The planner is independent from current materialization mechanisms:

    ResidencyPlanner
          ↓
    RuntimeAdapter
       ├── current MLX parameter replacement/rematerialization
       └── future byte-range / mmap / streaming source

The current pure Swift Safetensors byte-range materializer remains the lowest-level proof that selective materialization is possible.

## 3. What is deliberately NOT borrowed yet

The following ds4 capabilities are not silently added to SimiGo:

- model-specific DeepSeek/GLM router internals;
- expert routing implementation;
- asynchronous SSD read/compute overlap;
- CUDA/ROCm/Metal backend internals;
- GGUF-specific tensor streaming;
- model-specific cache popularity tables;
- speculative decoding;
- distributed tensor/pipeline parallelism;
- any claim that SimiGo has feature parity with ds4.

These require independent local validation.

## 4. New SimiGo experimental separation

The residency stack is now conceptually:

    Execution Context
           ↓
    Actual / observed demand
           ↓
    Required Execution Set
           ↓
    Residency Planner
       ┌───┴─────────────┐
       │                 │
    Core / mandatory   Working-set cache
       │                 │
       └───────┬─────────┘
               ↓
        Load / Keep / Evict
               ↓
       Materialization source
               ↓
           MLX runtime
               ↓
           Execution
               ↓
      Runtime observations

This is an engineering decomposition, not a new A2.0 theory object.

## 5. Current implementation

ExecutionResidencyPlanner.swift adds a pure planning layer.

It currently supports:

- explicit fixed-byte budgets;
- percentage budgets relative to a declared recommended working-set size;
- mandatory/core reservation;
- required execution groups;
- optional demand-priority candidates;
- deterministic priority/size/id ordering;
- load/keep/evict planning;
- explicit overflow reporting.

It intentionally does not:

- infer demand from model internals;
- predict future state;
- perform I/O;
- modify MLX;
- claim a scientifically established Core Resident Set.

## 6. Research-depth consequence

This adaptation is a horizontal engineering improvement, not a vertical research-depth escalation.

The depth governance remains:

    phenomenon
    → measurement
    → repeatability
    → sufficient resolution?

We do not jump from the current group-level residency problem directly to Router/Expert/Token×Expert research merely because ds4 exposes those concepts.

If later evidence shows that group-level execution demand is insufficient, the next resolution may be introduced one level at a time.

## 7. Immediate validation

The local validation sequence is:

1. swift test for planner semantics.
2. Compare planner output against existing deterministic residency transitions.
3. Run the real MLX residency benchmark with the planner only if pure planner tests pass.
4. Measure cache hit/reload bytes/reload time before changing runtime behavior.
5. Only then consider preload or I/O-compute overlap experiments.

The current baseline remains the reference. A planner PASS is not a runtime performance claim.

## 8. Architectural candidate, not architecture claim

The useful architectural candidate emerging from ds4 is therefore:

    execution
       ↓
    required set
       ↓
    bounded residency
       ↓
    materialization
       ↓
    compute
       ↘
        observation / locality

The loop may later become:

    execution history
       ↓
    demand / locality
       ↓
    residency decision
       ↓
    materialization
       ↓
    compute

But the second loop must be earned by measurements. It is not being declared as the final SimiGo 2.0 architecture.
