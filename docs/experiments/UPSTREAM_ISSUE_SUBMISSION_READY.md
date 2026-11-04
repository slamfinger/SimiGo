# 提交就绪包：mlx-swift-lm RFC issue（2026-09-19）

**已提交**：https://github.com/ml-explore/mlx-swift-lm/issues/629
（2026-09-19，gh CLI 代提，作者 slamfinger，状态 OPEN；本文件以下为
提交内容存档）

---

**Title**:

```
RFC: Branchable KV cache with shared-prefix / copy-on-write semantics
```

**Body**:

```markdown
## Problem

SimiGo is building a local macOS runtime on top of mlx-swift-lm.
We investigated whether a running KV cache can be branched into
independent executions without copying/recomputing the common prefix.

Current public API appears to provide:

1. prompt-cache save/load (file round-trip)
2. `KVCache.copy()` (independent deep copy)
3. trim/rewind where supported

But there does not appear to be a way to express:

        shared prefix
        /            \
    execution A    execution B

where A and B share the same underlying prefix storage and only
materialize private KV after divergence.

## Observed cost (35B model, ~63.6k tokens)

- checkpoint size: ~1.53 GB
- save/copy/load round-trip: ~1.94 s

`KVCache.copy()` provides an independent cache, but its semantics are an
independent deep copy (per-layer state slices, e.g. `KVCacheSimple.copy()`
mapping `state` through `[.ellipsis]`) rather than sequence-level ownership
of shared storage.

## Why this matters

- agent branching and tool-call alternatives
- speculative execution at the application level
- prompt-prefix reuse across concurrent executions
- serving workloads with many requests sharing a prefix

## Prior art

llama.cpp exposes sequence-level KV ownership operations (`seq_cp` /
`seq_rm`), allowing multiple sequence identities to refer to shared KV
storage without data duplication for the common prefix.

Related: mlx-lm #1849 discusses paged KV storage and external cache
integration on the Python side.

## Question

Would mlx-swift-lm consider supporting a branchable KV-cache abstraction
with shared-prefix semantics?

The exact API is open. Possible designs include:

- sequence/branch identity on cache entries
- shared immutable prefix + copy-on-write suffix
- reference-counted cache segments
- `fork()` returning an independent logical cache handle

We are not proposing to copy the llama.cpp API directly — the goal is to
raise the capability gap with real workload numbers and let maintainers
decide whether/how such an abstraction fits.

## References

Full experiment write-up (F0 capability probe: source survey of the
`KVCache` family, measured fork costs, and the divergence-immunity
context that motivated this):
[slamfinger/SimiGo — EXECUTION_FORK_F0_PROBE_RESULTS_20260919.md](https://github.com/slamfinger/SimiGo/blob/main/docs/experiments/EXECUTION_FORK_F0_PROBE_RESULTS_20260919.md)
```

---

**提交后**：把 issue 编号/URL 回填到本文件与本目录
`UPSTREAM_ISSUE_DRAFT_kv_prefix_sharing_cow.md`。
