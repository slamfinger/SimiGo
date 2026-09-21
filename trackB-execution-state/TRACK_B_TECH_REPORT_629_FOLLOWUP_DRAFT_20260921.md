# #629 Follow-up Draft — Technical Report(2026-09-21)

**性质**:Track B 收官技术报告 = mlx-swift-lm **#629**(本方 RFC)的
follow-up 评论**草稿**。正文英文(上游语境),可直接粘贴;**发布前
须经维护者(你)审定**——对外动作不代行。素材源:trackB 目录十份
实验记录 + Closure。#1849(mlx-lm)在 §7 对齐。

---

## Follow-up: Branchable execution state — design, measurements, and an adaptive representation policy (data package)

Following up on this RFC (#629) with the experimental package promised
in the original post. We built a working prototype of the semantics
proposed here (branch identifiers + immutable shared prefix +
copy-on-write suffix) as an in-cache segment table, measured it against
the four acceptance criteria sketched in #629, and closed with a full
lifecycle experiment. Everything below runs on the vendored
`mlx-swift-lm` experimental branch (based on `8f37dbc`); nothing here is
a production path or a version promise.

**Testbed**: MacBook Air M5 (32 GB, 153 GB/s), mlx-swift 0.31.6 pin,
Cyber-Tiel-Coder-35B-A3B-MLX-oQ4e (qwen3_5_moe: 10 full-attention
layers, 30 GDN/linear layers, KV ≈ 20 KiB/token).

### 1. Design (prototype)

- **Attention layers** (`KVCacheSimple`): a *segment table* — an ordered
  list of read-only `(buffer, rows)` references plus one append-only
  private tail (step-256 growth, same policy as stock). Fork = copy the
  segment list + append the parent's private tail as a new read-only
  segment: O(#segments), no copy.
- **GDN/linear layers** (`MambaCache`): fork = pass both state slots by
  reference. GDN updates are functional (slot reassignment), so both
  sides stay isolated with zero copies. `LMOutput.State` threads through
  by Swift value semantics.
- **Invariants** (all test-backed): (I1) children read parent buffers
  only in `[0, rows)`; parent appends never rewrite history rows
  (scatter writes are in-place — disjoint row ranges are safe; growth
  concats swap buffers rather than write back). (I2) offset monotone
  (trim disabled; hybrid architectures cannot rewind anyway). (I3)
  COW→COW fork composes at O(#segments). (I4) GDN fork = reference pair.

### 2. Core measurements (36B model, single machine — ranges, not specs)

| Property | Result |
|---|---|
| Fork cost | 0.02–0.06 ms per model fork (40 layers); no depth degradation 32K→128K (single-layer matrix, 72 cells) |
| Physical growth | exactly ∝ private suffix rows (1.00× used; 1.78× padded by step-256, amortizing); 4-way tree: 8 MiB vs 256 MiB full copies |
| Restore (page-level) | private-pages round-trip + segment re-attach is flat over a 16K/24K/32K chain (flatness 1.22, element-exact); full-view disk round-trip stays linear (baseline shape) |
| Correctness | token-exact greedy gates: 16/16, 32/32, 36/36, 96×4-way — fork/merged/mid-flight-switch continuations all match same-chunking from-scratch controls |
| Root unfreeze | parent continues writing rows ≥ forkDepth after being forked; re-fork afterwards still token-exact (rollback→continue→re-branch semantics) |
| Discard | unreachable private pages are reusable (20-round × 8 MiB churn: 0 KiB drift); single-point RSS not guaranteed to drop (MLX lazy-graph parent retention); combined-drop returns memory |

### 3. The multi-segment decode tax (and its removal)

A naive per-step `concat(shared segments, private tail)` view costs
**2×depth bytes of extra traffic per token**. Model-level steady-state
decode tax rises monotonically with depth: 1.03× (8K) → 1.09× (18K) →
1.14× (32K) → 1.26× (64K) at 4 segments (warm, interleaved, 3 reps,
token gates green). A first-order bandwidth model
`(W+3αD)/(W+2αD)` matches the curve (1.28 predicted @64K); this is an
attribution model, not a microarchitectural proof.

**Reattach** (materialize segments into one contiguous buffer via
`state = view; eval()`) removes the tax entirely: 1.22–1.26× → **1.006×**
post-merge @64K/4-seg, one-time cost 65–105 ms across 18–64K.
Performance-tax break-even (one-time merge cost ÷ avoidable per-token
tax) median ≈ 4 tokens steady-state across the 18/32/64K × 2/4/8-seg
matrix (9/9 cells ≤1.05× post-merge; 128K cells recorded N/A — peak
footprint exceeds this machine's safety line, not squeezed through by
raising limits).

### 4. Adaptive representation policy

Since the pre-merge tax fluctuates run-to-run (±0.1–0.5× same config),
static depth thresholds are unreliable. Policy:
`E[T_remaining] × τ̂_tax > Ĉ_reattach → reattach`, with τ̂ estimated
online (observation window k, sliding), E[T_remaining] = tokens already
generated (rolling; a fixed budget prior caused systematic over-migration
on short branches in simulation — fixed by the rolling estimator).

Live four-policy comparison (same continuation replayed through
COW / always-reattach / adaptive / oracle=min(COW,R)):
**adaptive −17.5% vs always-COW, +0.9% vs always-reattach, decision
regret +0.9%**; one long continuation finished **−1.0% below both pure
policies** (mid-flight switch is an operating point outside the
pure-strategy simplex). Observation window is a calibratable parameter:
k=8 beat k=4 (estimation error 8.1% vs 22%; k=4 is polluted by the
first-step view-materialization cache miss).

### 5. Lifecycle closure

One full run chained: fork → COW generation → tax observed → online
estimate → mid-flight reattach → continuous generation → four-way
continuation gate 96/96 → post-migration fork/branch/discard/continue on
the merged parent, semantics intact. Unified invariant throughout:
**representation migration must preserve execution identity and
continuation** (KV element-exact + identity + next-input + continuation
+ subsequent KV evolution — strictly stronger than KV equality; our own
harness bug where the next-input token wasn't migrated is the
counter-example that motivated it).

### 6. Position relative to #629's asks

The prototype is consistent with the RFC's proposed direction
(branch identifiers / immutable shared prefix / COW suffix / refcounted
segments / fork() returning an independent logical handle) at segment
granularity. Two notes for the discussion: (a) hybrid architectures
need the GDN half — reference-forked functional state — which no
paged-KV storage layer addresses (cf. mlx-lm #980: hybrid prefix caching
fails wholesale); (b) if #1849 lands paged KV storage with external
hooks, a segment-table execution-state layer is a candidate consumer of
those hooks rather than a competing storage design.

### 7. Known limitations (stated plainly)

Single machine, single model, single-digit trial counts for policy
numbers (all variance/scoping notes inline in the records); absolute
latencies are M5-Air-specific; view materialization is consumer-side
and O(depth) on first attention after fork; Discard guarantees reuse,
not immediate RSS drop; 128K multi-segment cells unmeasured here
(memory ceiling); the adaptive policy numbers are exploratory, not a
tuned production policy.

Full experiment records (10 documents, probe→result→decision format)
are maintained in the SimiGo-Lab research repository and available on
request.

---

*(草稿状态:待维护者审定后发布;发布时删除本行及文首中文说明。)*
