# Architecture 2.0 Session Knowledge — Curated Historical Record

**Date of curation:** 2026-09-22  
**Nature:** curated reconstruction of high-value SimiGo-Lab / Architecture 2.0 session knowledge  
**Authority:** historical/contextual record only; not current research state and not a replacement for evidence  
**Scope:** SimiGo-Lab / SimiGo 2.0 only. SimiGo 1.x product-development decisions are intentionally excluded.

> This is not a verbatim chat transcript. It records the architectural ideas, turning points, boundary decisions, and methodological lessons from the SimiGo-Lab discussions that are important enough that a future Agent should not have to rediscover them from conversation history.

## 1. The original architectural question

The 2.0 discussion began from a practical limit: long-context inference on Apple Silicon was approaching a memory/runtime boundary.

Two broad routes were considered:

1. **Hardware / memory scaling:** make the runtime tolerate substantially larger unified-memory machines without encoding today's memory size as a permanent architectural ceiling.
2. **Computation decomposition:** move beyond the assumption that one model + one complete context + one complete inference must be one indivisible computation.

The second route produced the central 2.0 idea:

> **Compute once, multiple futures.**

The objective was not simply to make one 256K prefill faster. It was to turn an expensive long-context computation into a reusable, branchable, recoverable **Execution State**.

That distinction became the conceptual center of Architecture 2.0.

## 2. The missing layer identified in the early discussions

The existing stack already contained pieces of the desired behavior:

```
chunked prefill
KV checkpoint / restore
prefix reuse
        ↓
      ??? 
        ↓
fork / branch / restore / continue
```

The key insight was that the missing abstraction was not another KV-cache optimization. It was an **Execution State layer** capable of preserving identity and continuation across derived states.

The early F0 probe then gave this idea a concrete boundary:

- the public MLXLMCommon surface did not expose the sequence identity needed for the intended fork semantics;
- a disk-level fork could reproduce state, but with a large copy/serialization cost;
- therefore the research problem was not “can bytes be copied?” but “can execution identity and continuation semantics become first-class runtime state?”

This distinction separated a storage operation from an execution-state mechanism.

## 3. Why the hybrid model mattered

The discussions recognized that the target Qwen3.5-style hybrid architecture was not merely an obstacle.

Its state has two qualitatively different components:

```
Execution State
├── Attention
│     └── KV state
│          └── append-oriented historical state
│
└── GDN
      └── fixed-size recurrent state
```

This suggested a unified **fork semantic** could contain heterogeneous representation rules:

- attention history can use shared historical segments plus private append regions;
- GDN state can be reference-forked / copied according to functional-state semantics;
- a fork therefore need not mean “deep-copy every tensor for the whole model”.

This became a major architectural hypothesis behind Track B.

The important idea was not a particular page size or data structure. It was:

> **one Execution State abstraction can contain component-specific fork semantics while preserving one externally coherent continuation identity.**

## 4. The early false path: “split computation and run it in parallel”

A major correction in the Architecture 2.0 discussion was the rejection of a superficially attractive route:

```
large GEMM / attention
        ↓
split into 4 application tasks
        ↓
run them concurrently
        ↓
merge
```

The research reasoning established why this cannot create free parallelism on a single GPU:

- the large kernel already occupies the available GPU execution resources;
- application-level splitting does not create additional hardware;
- attention K/V decomposition requires mathematically correct online-statistic merging;
- Swift-level decomposition can add materialization / reduction traffic;
- bandwidth pressure cannot be removed merely by creating more application tasks.

This did **not** mean computation decomposition is universally useless.

It established a boundary:

```
single GPU + same kernel resources
        → application split has no new parallel resource

kernel-level decomposition
        → Track A

multi-device decomposition
        → Track C
```

Thus the “split / distribute / merge” idea was preserved, but moved to the layer where it could have a real mechanism.

## 5. The first major methodological correction

A recurring lesson from the 2.0 sessions was:

> **Do not build the architecture first and then search for evidence that it works.**

The research sequence was progressively tightened toward:

```
Question
  ↓
independence
  ↓
estimand
  ↓
existence criterion
  ↓
insufficiency criterion
  ↓
discriminating power
  ↓
information value / cost
  ↓
path / harness
  ↓
experiment
  ↓
evidence
  ↓
finding
  ↓
decision
  ↓
architecture consequence
```

This later became the formal gate structure now used by SimiGo-Lab.

The practical consequence was significant: an attractive implementation idea could remain a candidate without receiving experimental authority.

## 6. Open-source deduplication changed the research boundary

The Architecture 2.0 discussions deliberately compared the proposed space against existing work rather than treating every mechanism as novel.

The resulting boundary was:

- do not reimplement FlashAttention / IO-aware attention as an algorithmic research project;
- do not reimplement KV-cache fundamentals already present in mlx-swift-lm;
- do not duplicate chunked prefill;
- do not duplicate prefix-cache systems;
- do not independently recreate paged KV storage if upstream work is already moving there;
- do not rebuild distributed communication primitives already supplied by MLX.

The remaining research space was therefore higher-level:

```
KV storage
     ↓
Execution State
     ↓
identity + fork + continuation + heterogeneous state
     ↓
runtime policy / planner
```

This “deduplicate before inventing” principle is part of the intellectual origin of Track B.

## 7. Architecture 2.0 research tracks as they originally emerged

The early architecture map was:

```
                    SimiGo 2.0
                        │
        ┌───────────────┼───────────────┐
        ↓               ↓               ↓
   Track B           Track A          Track C
Execution State     Kernel/BW       Multi-device
   immediate         conditional       future
        │
        └──── Track D: Adaptive Memory
```

### Track B — Execution State

Core hypothesis:

> an existing execution state can be forked at low cost, shared, continued, restored, and independently evolved without losing continuation correctness.

### Track A — Kernel / Bandwidth

Core question:

> is the current MLX → Metal execution path materially above the hardware roofline for the target long-context workload?

The important principle was to use a **roofline gate before writing a custom kernel**.

### Track C — Multi-device

This is the environment in which decomposition can obtain genuinely additional compute resources. It was deliberately deferred until hardware and scenario justify it.

### Track D — Adaptive Memory

The memory route was reframed from a fixed machine-size assumption into:

```
Physical Memory
→ System Available
→ Model/KV Requirement
→ Runtime Working Set
→ Dynamic Budget
```

The key safety principle was proactive pressure handling rather than waiting for swap/OOM.

## 8. The research tree became more important than the original roadmap

As experiments progressed, the project learned that not every branch should remain alive.

The intellectual tree became:

```
Execution State
      ↓
Residency
      ↓
P3 mechanism decomposition
      ↓
H-P1 structural-signal test
      ↓
nodes-out
      ↓
Track E closure
      ↓
P4 / Source-Runtime questions
```

The important lesson is that **closure is part of research knowledge**.

A future Agent must remember not only what worked, but why a branch was stopped:

- some routes were redundant;
- some had no discriminating mechanism;
- some were invalidated by their own controls;
- some remained interesting but separately scoped;
- some were permanently blocked by a closure decision.

Therefore a research archive without negative knowledge is incomplete.

## 9. Evolution from simulation mechanism to runtime question

The 2.0 research gradually exposed a critical distinction:

```
simulation mechanism
        ≠
real runtime mechanism
```

A mechanism seen in simulation does not automatically imply that a corresponding controllable object exists in Swift/MLX.

The intended chain became:

```
abstract mechanism
      ↓
runtime representation
      ↓
runtime-observable state
      ↓
controllable mechanism
      ↓
measurable effect
```

This is the intellectual bridge from Track E to the later Source/Runtime research direction.

It also explains why the current project is now at an **existence-criterion gate**, rather than jumping directly into Swift implementation.

## 10. The “unit” question

One of the most persistent Architecture 2.0 ideas was that the useful SimiGo unit may not equal the model's semantic unit.

Possible semantic decomposition:

```
model → layer → block → attention / MLP → tensor
```

Possible operational decomposition:

```
model
  → residency unit
      → migration unit
          → execution-state unit
```

The two hierarchies may overlap, but should not be assumed identical.

This produced a stronger question:

> What object has an independently meaningful residency, migration, execution-state, and cost identity?

And a methodological ordering:

> **Unit discovery precedes implementation choice.**

Choosing a unit merely because it is easy to instrument would reverse the research dependency.

## 11. Semantic-assisted versus semantic-dependent

Another durable distinction from the sessions:

```
semantic-assisted
    = upstream model semantics are available and useful

semantic-dependent
    = the mechanism cannot operate without upstream semantics
```

The long-term architectural hypothesis is that SimiGo should, where possible, derive essential decisions from runtime-observable behavior:

- access;
- co-access;
- residency;
- migration;
- reuse;
- execution continuity.

If that survives future validation, it would reduce coupling to a particular model family.

This remains a hypothesis, not a demonstrated runtime property.

## 12. Why “access pattern” became a candidate foundation

The discussions repeatedly returned to a deeper question:

> What determines the useful management granularity?

The emerging hypothesis was:

> **Useful granularity should be determined by access pattern rather than by management convenience or upstream naming.**

This connects:

```
access / co-access
      ↓
residency boundary
      ↓
migration boundary
      ↓
execution-state boundary
      ↓
cost identity
```

The connection is conceptually important, but it has not yet been established as a real Swift/MLX runtime law.

## 13. The role of Architecture 2.0 itself

Architecture 2.0 was intentionally kept as a **pre-research architecture**.

That means it records:

- why the program exists;
- candidate mechanisms;
- candidate tracks;
- known physical constraints;
- research priorities;
- expected acceptance gates.

It does **not** automatically establish:

- a production architecture;
- a runtime implementation;
- a universal model unit;
- a universal page size;
- a production policy;
- a proven real-runtime mechanism.

The later governance system formalized this distinction as:

```
Architecture hypothesis
        ↓
research question
        ↓
evidence
        ↓
decision
        ↓
architecture constraint
```

Only the last step produces a binding architecture consequence.

## 14. What must survive if the original conversations disappear

A future Agent should not need the original chat to rediscover these principles:

1. **2.0's central goal is compute-once / multiple-futures through reusable Execution State, not merely faster prefill.**
2. **Execution State is above raw KV storage; identity and continuation semantics are essential.**
3. **Hybrid model state may require component-specific fork semantics under one unified lifecycle.**
4. **Application-level parallel splitting on one saturated GPU is not a free performance mechanism.**
5. **Kernel-level and multi-device decomposition are different research layers.**
6. **Existing open-source mechanisms should be consumed rather than reimplemented when they already solve the relevant layer.**
7. **Research must establish mechanism existence before implementation authority.**
8. **A simulated mechanism is not automatically a runtime mechanism.**
9. **Operational unit discovery must precede implementation choice.**
10. **Semantic availability is not the same as semantic dependency.**
11. **Access pattern is a candidate foundation for operational granularity, not yet a proven runtime law.**
12. **Closed routes and failed hypotheses are durable knowledge, not discarded history.**
13. **Architecture documents are hypotheses until evidence and decisions promote a specific consequence.**
14. **The repository must preserve both factual evidence and intellectual branching history.**

## 15. Relationship to current repository state

This historical record does **not** change the current gate.

Current authoritative state remains in:

- `docs/RESEARCH_STATE.md`
- current endpoint / closure records
- experiment ledgers / evidence
- Git history

The current research position is therefore still the repository-registered STEP ⑤ existence-criterion definition gate.

No implementation, data collection, reopening of Track B/E, or automatic creation of RQ-F-01 follows from this historical record.

---

**Curated conclusion:** The most important thing preserved here is not a list of old ideas. It is the reasoning that transformed SimiGo 2.0 from “more aggressive long-context optimization” into a research program centered on **Execution State, residency, observable runtime boundaries, and evidence-gated architecture evolution**.
