# P5-4: Minimal Closure Reduction — Design Draft

日期：2026-10-01  
状态：`AUTHORIZED FOR EXECUTION`  
前置：P5-2-C Backend Dependency Closure Validated  
Closure：`{I, P, A, C}` (provisional, P5-2-C 后端证据)  
Contract v1.0：不变

> **目标：检测冗余，不是再证必要。** P5-2-C 已证明每项单独移除
> 均导致 continuation 失败。P5-4 的问题是：这些失败是否因为
> 关系不可替代，还是因为某些关系实际表达同一约束？

---

## §0 核心问题

```text
必要 ≠ 最小

如果 Position 失败且 Anchor 也失败，
可能二者表达同一约束（例如：ledger alignment）。

P5-4 问题：
在保持 continuation 成立时，
哪些关系可以被移除、合并或由其他关系替代？
```

## §1 Hard boundaries

```text
❌ 不进入 Palace / Security
❌ 不定义 Carrier
❌ 不证明 Universal Execution State closure（Level 3 超范围）
❌ 不重复 P5-2-C 单项移除（引用已有结果）
```

## §2 结论等级

```text
Level 1: Minimal Dependency Set for MLX continuation identified
Level 2: Relation equivalence / containment discovered
Level 3: Universal Execution State closure → NOT IN SCOPE
```

## §3 实验设计

### Phase 1: 单项移除（引用 P5-2-C，不重复执行）

| Arm | P5-2-C 结果 | 引用 |
|---|---|---|
| -I | VALIDATION_REJECTED | 已证：硬前置 |
| -P | CLOSURE_ABLATED | 已证：模型丢失记忆 |
| -A | CLOSURE_ABLATED | P5-1 证据：rebuild |
| -C | CLOSURE_ABLATED | 已证：S₀ 未被消费 |

### Phase 2: 关键组合测试（本实验核心）

优先测试最高研究价值的组合：

| Arm | 保留 | 移除 | 目的 |
|---|---|---|---|
| **PA-1** | I + C | P + A | P+A 组合是否必要（不能区分二者） |
| **PA-2** | I + P + C | A | 保持 Position 成立时，破坏 Anchor → continuation contract 是否仍成立？（关系独立性） |
| **PA-3** | I + A + C | P | 保持 Anchor 存在时，破坏 Position → continuation contract 是否仍成立？（关系独立性） |
| **IC** | I + C | P + A | I+C 是否足够（无状态定位） |
| **PC** | P + C | I + A | 不可能的组合（reference only） |
| **AC** | A + C | I + P | 不可能的组合（reference only） |

#### Arm PA-1: Remove P + A

物理 KV 完整。meta.json 修改：
- history = []（移除 Anchor / alignment source）
- 不修改 token count 相关字段（Position 由 KV 内部决定）

预期：与 -A 相同（rebuild），但确认 P+A 组合移除的效果
是否与单独 -A 一致。

#### Arm PA-2: Remove A, keep P

物理 KV 完整。保持 meta.json history count = 原始值（Position 完整），
但将 history 内容替换为同长度但不同文本的内容（Anchor 破坏——
内容不匹配但 token count 匹配）。

这是**最关键的 arm**。不预设"替代关系"结论。
测试的是：Position 条件成立（token count 匹配）时，
Semantic Anchor 破坏（内容不匹配）是否导致 continuation
contract 失效。

可能结果（不预设）：
```text
情况 1: output ≈ Full baseline → KV 语义携带 > anchor 校验
情况 2: output ≠ Full baseline 但格式正常 → Position 满足形式对齐
         但不足以保证 semantic continuation → A ≠ P
情况 3: framework reject / rebuild → 当前实现检测到 semantic
         inconsistency → VALIDATION_REJECTED（不是 closure proof）
```

#### Arm PA-3: Remove P, keep A

物理 KV 完整。history 内容不变（Anchor 完整），但修改
history 数组的消息数使其与 KV token count 不匹配（Position 破坏）。

测试：Anchor 信息存在（内容不变）时，Position relation 破坏
（count 不匹配）是否导致 continuation contract 失效。

#### Arm IC: Keep only I + C

极度削减测试——只保留 Identity 和 Continuation path。
移除 P 和 A（history=[]，不修改其他）。

预期：rebuild（与 -A 相同——没有 anchor，position 无从验证）。

## §4 判读

```text
PA-2 (keep P, remove A):
  情况 1 output ≈ baseline → KV semantic carrying sufficient
  情况 2 output ≠ baseline → A ≠ P (semantic continuation broken)
  情况 3 rebuild → VALIDATION_REJECTED (semantic inconsistency detected)

PA-3 (keep A, remove P):
  rebuild → P ≠ A (position misalignment breaks continuation)
  output 正常 → P 冗余（被 A 包含）
```

## §5 预注册措辞

```text
Level 1（如果所有组合测试确认四项独立不可替代）:
  "Minimal Dependency Set for MLX continuation identified:
   {Identity, Position, Semantic Anchor, Continuation}——
   每项均不可被其他项替代或包含。"

Level 2（如果发现 containment/equivalence）:
  "Relation containment discovered: {描述哪项包含哪项}。
   Minimal closure 修正为 {缩减后的集合}。"
```

## §6 Harness 要求

继承 P5-2-C 全部完整性标准。新增：
- PA-2 是核心 arm（同长度不同内容 history）
- PA-2 必须验证 cachedTokenCount == renderedTokenCount
  （否则退化成 P5-1 rebuild，无新信息）
- 每 arm 必须记录：processedTokenCount, renderedTokenCount,
  cachedTokens.count, reuse decision
- 记录 output 与 Full baseline 的差异度（edit distance 或 hash 比较）
- 每组合独立 fixture 目录
