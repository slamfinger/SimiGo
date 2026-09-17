# UPSTREAM ISSUE DRAFT: qwen3.5/qwen3.6 hybrid — tool-result continuation forces full-context re-prefill (fork-no-rewind); proposal: Qwen35ToolRestartRule

> **状态**：证据包定稿待发（2026-09-18）。发布位置与仓库归属由维护者决定
> （mlx-swift-lm Swift 侧 / mlx-lm Python 侧 #980 交叉引用）。
> **遥测诚实性红线**：文中全部 `fork@common` 数据来自本仓库 vendor telemetry
> （本地 mlx-swift-lm 补丁 5ba0bc1 + SimiGo 3b127ba，+36 行），**不是上游原生
> 遥测**。发布时必须保留本标注。

---

## Summary

On qwen3.5/qwen3.6 hybrid architectures (GatedDeltaNet + attention), any
rendered-prompt divergence from the cached token ledger — including divergences
in the **last 0.3% of an 83k-token context** — triggers a **full-context
re-prefill**, because `RewindToCommonPrefixRule` requires `isTrimmable` and the
GDN recursive-state layers report `isTrimmable=false`.

For agent workloads this is the dominant cost: over a 4-day production window
(single user, single 35B-A3B model, M-series Mac), **144 fork-no-rewind rounds
re-rendered 9,092,262 tokens taking 65,735 s (18.3 h) of pure re-prefill**,
while the 2,589 strict-extension rounds averaged only 439 tokens each.

We propose a protocol-level splice rule, **`Qwen35ToolRestartRule`**, modeled on
the existing `HarmonyToolRestartRule` (~87 lines), which eliminates the
divergence at tool-result continuation boundaries — the empirically dominant
divergence source — without touching GDN state semantics.

## Why the common prefix cannot be reused (mechanism)

`PromptCacheReusePolicy` decision chain:

1. strict extension & longer → `ExtendCachedPrefixRule` → appendSuffix ✓
2. divergence → `RewindToCommonPrefixRule` → requires `isTrimmable` on all
   layers → `KVCache.swift:233` base default **false**; qwen3.5 GDN
   (GatedDeltaNet) recursive state has **no inverse** for the suffix tokens →
   cannot rewind → 3. full rebuild, `cacheEfficiency = 0.00`.

This is **correct behavior**: rewinding recursive state would produce wrong
outputs. The problem is not the rewind guard — it is that tool-result
continuation rounds **diverge at all**.

## Why tool rounds diverge: key-order instability

The chat template re-renders assistant `tool_calls` arguments from parsed JSON
objects. Our round-trip experiment (Swift `JSONValue` decoded → re-encoded with
the engine's semantics) shows multi-key nested objects are **not
byte-stable**:

```text
{"id":…,"content":…,"status":…,"deps":…}  →  {"id":…,"deps":…,"status":…,"content":…}
```

(first sub-object keys reorder alphabetically; single-key objects are stable.)
The re-rendered prefix therefore diverges at the previous round's assistant
message, while the ledger holds the original generation-order tokens.
22-round production alignment (ddc444): Bash 8/8 hit, AskUserQuestion 1/1 hit,
**TodoWrite 0/2 both full rebuild** — matching the mechanism exactly.
Upstream root: `swift-jinja` `Value.swift:63` sorts dict keys alphabetically at
the dict→Jinja boundary; per-format `promptCacheReuseRules` for `.qwen35`
returns `[]` (`ToolCallFormat.swift:217-231`), so no splice rule absorbs the
divergence.

## Production cost (vendor telemetry; see honesty note)

Single real agent session (`442fbf/main`, 73+ messages, 2026-09-18,
full trace: BENCH_442FBF_FORK_REWIND_20260918/):

| round | mode | promptTokens | promptTime | fork@common |
|---|---|--:|--:|--|
| 1 | cold | 17,663 | 35.4 s | — |
| 2–15 | extend ×14 | ≤6,075 each | ≤16.2 s | — |
| 16 | **fork-no-rewind** | **41,155** | **174.5 s** | — |
| 17–18 | extend | 44 / 23,268 | 8.9 / 381.1 s | — |
| 19 | **fork-no-rewind** | **65,593** | **299.2 s** | — |
| 20–21 | extend / **fork-no-rewind** | 967 / **66,530** | 7.3 / **251.5 s** | — |
| 22 | **fork-no-rewind** | **68,459** | **285.9 s** | — |
| 23 | **fork-no-rewind** | **70,113** | **293.2 s** | — |
| 24–32 | extend ×9 | ≤3,336 | ≤23.3 s | — |
| 33 | **fork-no-rewind** | **83,539** | **487.6 s** | **82,716/82,919** |
| 34 | extend | 393 | 4.4 s | — |

Session totals: **6 fork-no-rewind rounds = 395,389 tokens ≈ 30 min of pure
re-prefill**; divergence points sat at **99.5 %+ of the context every time**
(`divergenceToken` total 3,452) — i.e. **0.87 % divergent tokens caused a 115×
re-render amplification**. The sharpest single round: common prefix 82,716 of
82,919 (99.76 %), only 203 tokens unrecoverable, yet the full 83,539-token
prompt re-prefilled at 171 tok/s (promptTime÷promptTokens confirms physical
full evaluation).

4-day fleet window (same model/machine): fork-no-rewind n=144,
9,092,262 tokens, 65,735 s; extend n=2,589, mean 439 tokens;
rebuild n=7, 338,378 tokens; cold n=125 (80 on pre-existing sessions).
Waste ratio 86.4 % of all prefill tokens.

## Proposed fix: `Qwen35ToolRestartRule`

Spec (FIELD_OBSERVATION §11, commit 936fddb):

- `endToken` = `</tool_call>` (tokenizer anchors measured on qwen3.6-froggeric:
  `<tool_call>`=248058, `</tool_call>`=248059, `<tool_response>`=248066/248067 —
  isomorphic to Harmony `<|call|>`)
- divergence source = alphabetically-reordered argument re-render +
  reactive tool-result annotation (template L412-421 heuristic /
  `ns2.consecutive_failures` counter — template design itself breaks token
  prefix stability) + reasoning re-wrapping
- splice = `suffixStart` = first tool-result message after the last endToken;
  `representedTokens` = cached + suffix
- guards: `isToolResultContinuation` + aligned + non-empty ledger + structured
  count validation

This is protocol-level bookkeeping between the cache ledger and re-render —
it does **not** rewind GDN state and does not change outputs. Known boundary:
it removes per-round re-prefill at tool boundaries but not rendering divergence
itself (parameter order preservation is a separate layer).

## Alternatives considered and rejected

- **GDN rewind / checkpoint-rewind inside the engine**: correct only as
  checkpoint-and-branch (state serialization), not rewind; rewind of recursive
  state produces wrong outputs. External checkpointing via cache
  serialization works today and is how we ship branch-fork, but it cannot
  recover the divergence tax: the divergence lives in the live ledger tail.
- **Preserving key order end-to-end**: `swift-jinja` sorts at the boundary;
  `deterministic ≠ prefix-preserving`. Host-side fixes cannot penetrate that
  layer.
- **Fake cacheEff / host-side dict sorting**: prohibited (misrepresents
  engine semantics).

## References

- mlx-lm #980 (hybrid architectures lose prefix reuse; qwen3.5 listed;
  40K-context agent rounds ~200 s vs ~5 s healthy — same signature)
- mlx-lm #1480 (qwen3.5/3.6 hybrid MoE long-context prefill memory pressure)
- Local full evidence: FIELD_OBSERVATION_20260913_LONG_CONTEXT_TASK.md §7/§11
  (28-round cacheEff sequence; JSONValue round-trip repro
  jsonvalue-roundtrip-repro.swift); vendor patch for `fork@common` telemetry
  (ChatSession.swift/Evaluate.swift, +36 lines)

---

## 定稿备注（中文，发布前删除本节）

1. 发布位置二选一：Swift 侧仓库（Claude/mlx-swift-lm 上游）为主，
   mlx-lm #980 跟评引流；发布人=维护者（gh 未认证时网页粘贴）。
2. 发布时删除本中文节；英文正文可直接粘贴。
3. `fork@common` 出处标注已内嵌 Summary 前的引用块与 References，
   不得删。
4. 若上游要求最小复现：`jsonvalue-roundtrip-repro.swift` +
   BENCH fixture trace（脱敏后可附）。
