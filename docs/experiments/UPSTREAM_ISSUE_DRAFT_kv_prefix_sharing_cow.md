# UPSTREAM DRAFT：Branchable KV cache RFC（mlx-swift-lm）

**性质**：上游 issue 草稿（2026-09-19 按 RFC/能力请求定位改写，外审建议：
描述能力缺口而非指定 API 实现——sequence identity / COW / fork() 降级为
Possible designs；标题采用 RFC: Branchable KV cache with shared-prefix /
copy-on-write semantics）
**提交状态**：提交就绪包见 `UPSTREAM_ISSUE_SUBMISSION_READY.md`
（连接器 403、gh 未登录，待用户提交或 gh auth login 后代提）
**目标仓库**：ml-explore/mlx-swift-lm（或 mlx-swift 分层讨论）
**动机数据**：`EXECUTION_FORK_F0_PROBE_RESULTS_20260919.md`（F0 探针）+
`docs/lessons/kv-fork-checkpoint-experiment-2026-09-17.md`

## 定位（外审 2026-09-19）

提交的是「shared-prefix / branchable KV cache 能力请求 + 实测证据」，
不是「请按 SimiGo 的 KVCacheHandle + seq_id + COW 设计实现」——
前者讨论真实能力缺口，后者替上游做设计决定。上游生态已有相邻讨论
（mlx-lm #1849 paged KV + external cache integration），时机合适。
预期管理：提交 ≠ 上游必实现；价值在获得明确的 accept / reject /
alternative。SimiGo 侧边界已定：无上游原语则不进 Core
（`docs/decisions/V15_ENDGAME_DECISION_20260919.md`），issue 不带来
架构负担。

## 英文 issue 正文（提交版见 GitHub issue 链接回填处）

```text
Title: RFC: Branchable KV cache with shared-prefix / copy-on-write semantics

Problem
-------
SimiGo is building a local macOS runtime on top of mlx-swift-lm.
We investigated whether a running KV cache can be branched into
independent executions without copying/recomputing the common prefix.

Current public API appears to provide:
1. prompt-cache save/load (file round-trip)
2. KVCache.copy() (independent deep copy)
3. trim/rewind where supported

But there does not appear to be a way to express:

        shared prefix
        /            \
    execution A    execution B

where A and B share the same underlying prefix storage and only
materialize private KV after divergence.

Observed cost (35B model, ~63.6k tokens)
----------------------------------------
checkpoint size:     ~1.53 GB
save/copy/load:      ~1.94 s

KVCache.copy() provides an independent cache, but its semantics are an
independent deep copy (per-layer state slices) rather than sequence-level
ownership of shared storage.

Why this matters
----------------
- agent branching and tool-call alternatives
- speculative execution at the application level
- prompt-prefix reuse across concurrent executions
- serving workloads with many requests sharing a prefix

Prior art
---------
llama.cpp exposes sequence-level KV ownership operations (seq_cp / seq_rm)
allowing multiple sequence identities to refer to shared KV storage.

Question
--------
Would mlx-swift-lm consider supporting a branchable KV-cache abstraction
with shared-prefix semantics? The exact API is open. Possible designs
include: sequence/branch identity; shared immutable prefix + copy-on-write
suffix; reference-counted cache segments; fork() returning an independent
logical cache handle. We are not proposing to copy the llama.cpp API.

References: full experiment write-up (F0 probe) at
slamfinger/SimiGo docs/experiments/EXECUTION_FORK_F0_PROBE_RESULTS_20260919.md
```

## 原始中文草稿（数据与用例，保留备查）

- 分支工作流：35B 模型 63.6k 上下文 checkpoint = **1.53GB**；现磁盘
  fork 往返 1.94s、内存 copy() 全量物化——分支每多一条，KV 常驻 ×2
- 恢复态延续：fragment-continuation 已实证（TTFT 0.17–0.74s @
  fragment 17–209 tok）；真共享可把「派生新执行」从 O(context) 降到
  O(delta)

## 现状边界（已核实）

- MLXLMCommon 全库无 sequence_id/seq_cp/seq_rm 概念（grep 零命中）
- `copy()` 9 个子类均为逐层全量切片（惰性全拷贝，非共享视图）
- 局部操作仅 `trim/isTrimmable`（GDN 不可 trim）；无 merge

## SimiGo 侧承诺

不改 fork MLXLMCommon 内部；能力就绪前生产走磁盘 checkpoint fork
（已发布 v1.4），并保留全部 A/B 对照数据回馈上游。
