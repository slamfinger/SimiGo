# SimiGo-Lab — O0 Open-Source Mechanism Census — 2026-09-25

Status: O0_CENSUS_REGISTERED / O1_MECHANISM_TAXONOMY_NEXT
Phase: Oversized Model Execution Investigation
Scope: census only — what mechanisms ACTUALLY EXIST in reference
implementations. No runtime changes; no conclusions about SimiGo's design
drawn yet; the taxonomy (O1) is provisional until the code audits complete.

## 0. Purpose and discipline

The census replaces "find the best reference implementation". Different
projects solve "Model Representation > Physical Memory" with DIFFERENT
mechanisms, possibly at different layers. Project names are never
substituted for mechanisms: each implementation answers nine questions, and
the mechanisms — not the projects — are what SimiGo may later absorb.

The nine census questions:

```text
1. What is the Representation?
2. Where is Storage?
3. When does Materialization happen?
4. What is the Residency granularity?
5. How does Execution trigger materialization?
6. Who owns Eviction?
7. How does Restore happen?
8. What REALLY happens when physical memory is exceeded?
9. Where is the performance cost?
```

## 1. Census profile — llama.cpp / ggml

Source: `src/llama-model-loader.cpp` (master; externally verified this
session).

```text
1 Representation   GGUF file; tensors indexed by file offset
                   (llama_tensor_weight), no_alloc = true at index time
2 Storage          the model FILES, memory-mapped when use_mmap
3 Materialization  deferred: a set_tensor_data callback materializes a
                   tensor's data later (model code decides when) — loader
                   does not read data up front
4 Residency gran.  per-tensor / per-buffer-bucket
5 Exec trigger     backend buffer placement: per-tensor suitability check
                   (weight_buft_supported builds a dummy op) then data
                   copy into the chosen backend buffer
6 Eviction         OS-level (mmap paging); no explicit runtime eviction in
                   the loader
7 Restore          = page re-fault through the mapping (OS)
8 Over-physical    mmap lets the file exceed RAM; pages fault from disk on
                   access — capacity comes from the OS, cost is I/O
9 Cost             page faults / disk I/O on first and (evicted) repeated
                   access; mlock variants trade flexibility for latency
```

Route classification: **Route A (virtual-memory mapping) + Route D
(per-tensor/buffer placement)**; load modes: MMAP / MMAP_MLOCK / AUTO.

## 2. Census profile — DS4

Source: registered audits in this repository
(`DS4_RUNTIME_DESIGN_AUDIT_20260924.md`, `DS4_RUNTIME_DESIGN_ADAPTATION_v0.1.md`).

```text
1 Representation   parameter universe (project-specific; details NOT
                   retained in the registered audit)
2 Storage          not retained in the registered audit
3 Materialization  at execution need: required execution set → resident set
                   → materialization (the registered abstraction)
4 Residency gran.  execution-set-driven groups (abstraction level)
5 Exec trigger     the required execution set drives materialization
6 Eviction         resident set management outside the required set
7 Restore          re-materialization from storage (abstraction level)
8 Over-physical    the abstraction exists precisely for this case; the
                   registered audit did not retain DS4's internal mechanism
9 Cost             not retained in the registered audit
```

Route classification: **Route B/D hybrid (runtime-managed selective
materialization)** — provisional.

Census gap (registered): the DS4 audits captured the reusable ABSTRACTION
(parameter universe → required set → resident set → materialization →
execution) and explicitly REJECTED adopting its mechanisms (expert loading,
SSD streaming) without evidence. A code-level DS4 mechanism census is an
O0 follow-up requiring the DS4 reference source.

## 3. Census profile — MLX / mlx-swift-lm

Source: local code audit (mlx-swift `IO.swift`, mlx-swift-lm
`Load.swift`, `LLMModelFactory.swift`, `Qwen3Next.swift`).

```text
1 Representation   safetensors files (sharded); MLXArray lazy views at
                   read (loadArrays is mmap-backed)
2 Storage          model files on disk
3 Materialization  load-time: loadWeights reads ALL shards and
                   model.update(parameters, verify: .all) binds every
                   parameter — single-shot FULL-MODEL load; whether weight
                   buffers materialize eagerly at load or lazily at first
                   forward is the H-mmap vs H-eager question (O2 empirical)
4 Residency gran.  none at runtime: the whole model is one unit
5 Exec trigger     none: generation consumes whatever is resident
6 Eviction         only manual cache hygiene (Memory.clearCache); no
                   parameter-level eviction in the load path (the SimiGo
                   L4 release pattern is runtime-side, not MLX-side)
7 Restore          not applicable (nothing is ever de-resident)
8 Over-physical    unverified: H-mmap (page-backed, OS paging) vs H-eager
                   (allocation failure / swap pressure) — O2 decides
9 Cost             first-forward materialization; if over-physical, swap
                   / pressure / allocation failure
```

Route classification: **none today** (single-shot resident); mmap-lazy
behavior at read is Route-A-adjacent but unverified past load.

## 4. Census profile — SimiGo (current, validated)

Source: L1/L2/L3/L4-A/B/C validation chain (registered).

```text
1 Representation   group-bound parameter sets (per-group materializer
                   validated on 4 models; L4-A adapter)
2 Storage          safetensors shards (per-group re-materialization from
                   shards proven in L4-B)
3 Materialization  controller-driven, per group, commit-after-effect
4 Residency gran.  layer-group (switch_mlp / dense ranges); window-
                   protected required sets
5 Exec trigger     admission: required set drives loads before execution
6 Eviction         controller-owned (pressure response, retention
                   rotation), every eviction a logged transfer
7 Restore          representation rebind from captured checkpoints
                   (prefix strategy) + group re-materialization
8 Over-physical    UNTESTED — this investigation's target
9 Cost             reload traffic vs retention (trade-off frontier,
                   frozen research line); latency effect unquantified
```

Route classification: **Route B/D (runtime paging + group
materialization)** — validated at group granularity, oversized case
untested.

## 5. Route taxonomy (provisional — from the census, not preset)

```text
Route A  Virtual-memory mapping        llama.cpp (mmap modes); MLX
                                       read-time (unverified past load)
Route B  Runtime paging                SimiGo (validated at group level);
                                       DS4 (abstraction level)
Route C  Device offload (CPU/GPU/SSD)  none audited yet
Route D  Layer/block materialization   llama.cpp (buffer placement);
                                       SimiGo (group materializer)
Route E  MoE selective residency       NONE audited yet — and the most
                                       relevant route for Qwen3-Coder-Next
```

## 6. Qwen3-Coder-Next: representation vs working set (the decisive gap)

Measured (O1 inventory): 41.76 GiB representation (fused 512-expert
switch_mlp 40.50 GiB + attention/linear/shared/norms/embed ≈ 1.26 GiB);
execution working set per token: 10 of 512 experts active per MoE layer +
shared expert + attention/linear state ≈ **1.26 GiB + 40.50 GiB × (10/512) ≈
2.1 GiB**.

```text
Model Representation  ≈ 41.76 GiB
Execution Working Set ≈ ≈2.1 GiB per token (static estimate)
Ratio                 ≈ 20×
```

This makes **Route E (expert-selective residency)** the structurally most
relevant mechanism for this model — and the one NO reference
implementation in the census has been audited for. The physical floor is
however bounded by the fused `switch_mlp` tensor granularity (13.5 GiB per
16-layer group): expert-level selectivity would require finer-grained
materialization than the current fused format exposes — a registered
tension for O3.

## 7. Mechanism reuse qualification principle

The census is a **mechanism-space inventory, not a code-reuse shortlist**.

An implementation being mature, elegant, performant, or successful does not
by itself qualify its mechanism for SimiGo. Open-source research first
establishes **what mechanism exists and what problem it solves**; reuse is a
separate engineering judgment subject to SimiGo's actual constraints.

The following rule is registered for all subsequent oversized-model work:

```text
discover mechanism
    → separate mechanism from project-specific implementation
    → verify mechanism in its original implementation
    → test compatibility with SimiGo / MLX / Apple Silicon constraints
    → preserve SimiGo semantic authority
    → adopt the minimum reusable mechanism
    → validate on the real model / real machine
    → retain or reject based on measured result
```

### Reuse qualification levels

```text
L0  Concept
    The mechanism addresses the same class of problem.
    No implementation or integration claim follows.

L1  Mechanism feasibility
    The mechanism can be implemented in SimiGo's actual technology stack.
    Still no claim that it can participate in MLX execution.

L2  Semantic compatibility
    The mechanism can be integrated without violating frozen SimiGo
    semantic boundaries:
      Execution Identity
      Lineage
      Position
      Continuation
      Representation / Residency separation
    It must not create a second authority for Execution State semantics.

L3  Runtime viability
    The mechanism works on the real target model / machine and its
    capacity, stability, and performance cost are measured.
    Only this level can justify retaining it as an engineering mechanism.
```

Therefore:

> **Can implement ≠ can integrate ≠ can execute correctly ≠ worth adopting.**

In particular, the presence of mmap, lazy loading, SSD streaming, expert
caching, paging, or another mechanism in an external implementation must
never be converted into a SimiGo design requirement merely because the
reference implementation is strong.

The census may produce **candidate mechanisms**. It does not select a
winner, rank projects, or authorize adoption. O2/O3/O4/O5 provide the
evidence required to move a mechanism from census knowledge toward SimiGo
implementation.

## 8. Next gates

```text
O1  Mechanism taxonomy finalization (after DS4 code-level follow-up,
    llama.cpp lazy-mode source verification)
O2  Mechanism experiments on THIS machine (mapping footprint, selective
    touch, real forward over mapped data; H-mmap vs H-eager)
O3  SimiGo model-residency boundary (skeleton-load + group materialize)
O4  44.9 GB real execution through SimiGo residency
O5  capacity / stability / performance boundary sweep
O6  Execution State × oversized model (E5v2 composition)
```

Mechanism comparison experiments (same model, same machine, same prompt,
same token budget — memory/latency/tok-s/I-O per mechanism) are registered
as the O2/O5 method: the census never substitutes for local measurement,
and no claim of "llama.cpp proves SimiGo can" is permitted.
