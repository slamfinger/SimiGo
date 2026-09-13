# Upstream Issue 草稿：mlx-swift-lm ChatSession 取消生成清空整个 token ledger

> 目标仓库：`ml-explore/mlx-swift-lm`（@ 238ad74）。本文件是提交前的 issue 草稿与核对清单，
> 不是 SimiGo 的运行时修改。**注意：生产 trace 含用户小说内容，上游 issue 只引用统计与
> token 序列摘要，不得粘贴原始 trace 片段。**

---

## Issue 正文（英文，可直接提交）

**Title**: ChatSession: a cancelled generation wipes the entire token ledger (`cachedTokens.removeAll()`), forcing the next request into a full cold re-prefill

**Environment**
- mlx-swift-lm @ 238ad74 (main)
- macOS 15.x, Apple Silicon, 32GB unified memory
- Model: Qwen3.5/3.6 hybrid MoE (GatedDeltaNet linear attention + full/sliding attention), 4-bit MLX quant
- Workload: OpenAI-compatible agent loop (multi-turn tool calling), 43–90K token contexts, client-side patience timeout (~10 min)

**Summary**

When a generation is cancelled mid-flight — the normal case in agent loops where the client
enforces a patience timeout — `AssistantGeneration.shouldRecord` is `false` and
`Conversation.record(_:generatedTokens:processedTokenCount:)` takes the invalidation path:

```swift
guard assistant.shouldRecord else {
    // A cancelled or semantically empty generation has no
    // assistant turn to replay. Its cache may nevertheless
    // contain generated or lookahead tokens, so invalidate
    // the ledger and rebuild from the retained messages.
    cachedTokens.removeAll()
    uncommittedTokens.removeAll()
    return false
}
```

This discards the **entire token ledger**. The KV cache physically still holds the prompt and
(often) a large fully-computed partial prefill, but with the ledger gone the next request takes
the `prefillAll` path and re-prefills everything from token 0.

**Why this matters**

In long-context agent workflows the client enforces a patience timeout (~10 min is common).
Once the context is large enough that a single turn (prefill + generation) approaches that
budget, the loop becomes non-convergent:

```text
cancel (client patience)
  → ledger wiped
  → next attempt: full re-prefill of the whole context
  → exceeds patience again
  → cancel → ...
```

The task becomes uncompletable, and each cycle re-computes tokens that were already computed
and (for the prompt prefix) still resident in the KV cache.

**Observed (production)**

28-round agent task at 43→90K context: 13 rounds reported `cacheEfficiency == 0.0` (full
re-prefill, including one whose new-token delta was a ~60-token tool result); 6 client
cancellations; every post-cancellation round started from token 0.

**Expected**

On cancellation, retain the ledger up to the boundary the cache has actually computed **and**
that is consistent with the retained message prefix — i.e. keep `cachedTokens` aligned with the
physical `processedTokenCount` for the prefix matching the retained transcript, and drop/mark
only the remainder (generated/lookahead tokens beyond it) as uncommitted or discarded.

With that, a retry whose rendered prompt shares the retained prefix takes the warm
`appendSuffix` path instead of a full cold re-prefill.

**Note on scope**: the fix is bookkeeping-only. No inference semantics, no GDN/rewind changes,
no chat-template changes. The physical KV cache already holds the computed prefix positions —
only the ledger was invalidated.

**Related**
- mlx-lm #980 (hybrid-architecture prefix reuse degradation) — same model family. The GDN
  layers being non-trimmable means a post-divergence partial rewind is unavailable, which
  amplifies the cost of the ledger wipe.
- Companion findings (can be separate issues): (a) tool-call argument serialization is not
  order-stable across parse→re-render (`JSONValue.object` = `[String: JSONValue]`), which
  causes prefix divergence on multi-key arguments even without cancellations; (b) a
  `PromptCacheReuseRule` for the `qwen3_5` tool-call format (tool-result continuation splice),
  analogous to `HarmonyToolRestartRule`.

**Repro data**: available — 28-round production trace (per-round `cacheEfficiency`, prefill
timelines, cancellation timestamps) + a minimal round-trip script demonstrating the key-order
instability of multi-key tool-call arguments.

---

## 中文注记

1. **提交目标**：`ml-explore/mlx-swift-lm` issue（英文正文上述）。
2. **提交前核对**：
   - [ ] revision 复述为 238ad74（与本机 checkout、SimiGo Package.resolved、v1.2 DMG 四方一致已验）；
   - [ ] 生产数据**脱敏**：只引用 cacheEff 序列、token 数、时间戳——不贴含小说内容的原始 trace；
   - [ ] 复现脚本 `jsonvalue-roundtrip-repro.swift` 可独立运行（不依赖用户数据）；
   - [ ] 与 mlx-lm #980 的关系表述为「同类模型家族、不同层」（#980 是 hybrid reuse 退化；本 issue 是取消记账清空）。
3. **三件套定位**（供 issue 正文 Related 与后续 PR 排序）：
   - P0 本 issue：取消清空账本 → 重试全量冷预填；
   - P1 `Qwen35ToolRestartRule`（qwen3_5 格式的工具结果续接拼接，参考 `HarmonyToolRestartRule` 87 行）；
   - P2 ToolCall arguments 序列化保序/规范化（多键参数渲染分叉的根治）。

## SimiGo 侧状态（零改动声明）

- `NativeMLX.swift:714-715` 纯透传官方 `cachedPromptTokenCount/cacheEfficiency`——无观测层缺陷；
- `cancelCommitSkip`（39ff354）保证取消不污染 SimiGo 自己的会话账本——与上游本 issue 互补
  （上游修「取消不清 ledger」，SimiGo 侧修「取消不污染 SimiGo 会话」——两层各司其职）；
- 观察窗口纪律维持：SimiGo 运行时冻结，等待上游修复或窗口期满立项。
