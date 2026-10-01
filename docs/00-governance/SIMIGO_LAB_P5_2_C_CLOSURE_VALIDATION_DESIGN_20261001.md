# P5-2-C: Minimal Closure Validation — Design Draft

日期：2026-10-01  
状态：`DESIGN DRAFT / AWAITING HUMAN AUTHORIZATION`  
前置：P4 PASS → P5-1 INCONCLUSIVE → P5-2 ER PASS-WITH-REVISIONS  
Closure：`{Identity, Position, Semantic Anchor, Continuation}` (provisional)  
Contract v1.0：不变

> **本实验验证最小性，不验证存在性。** P4 已证明 S₀ topology 存在。
> 本实验的问题是：从 S₀ 中移除一个 closure relation 后，continuation
> 是否仍可维持？如果移除任何一项都导致 continuation 失败 → 最小性
> 成立。如果某项移除后 continuation 仍成功 → 该项不是必要成员。

---

## §1 Hard boundaries

```text
❌ 不证明 Execution State = KV / cache / database / graph
❌ 不修改 Contract v1.0
❌ 不选存储方案
❌ 不做 Palace / Security 实验
❌ 不改 closure 定义（定义可能被结果修订，但修订归 human）
```

## §2 实验矩阵

在 MLX backend 上执行 remove-one-relation ablation。
基线 = Full Closure（P4 已证明的四关系全保留条件）。

| Arm | 移除项 | 实现方式 | 预期失败模式 |
|---|---|---|---|
| **Full**（基线） | 无 | 标准 loadSessionCache + generate | PASS（P4 已证） |
| **-Identity** | modelId 或 kvFingerprint | 修改 meta.json：modelId 改为错误值 | restore throw（model mismatch） |
| **-Position** | processedTokenCount | 修改 meta.json 或 KV 使 token count 归零 | rebuild（无法 bootstrap） |
| **-Anchor** | history text | P5-1 已做（history=[]） | rebuild（alignment 断裂） |
| **-Continuation** | nextInput / acceptance rule | 传入非 prefix 的 messages | reuseMiss → cold |

Arm **-Anchor** 可复用 P5-1 的 stripped fixture。
Arm **-Identity/-Position** 需要构造畸形 checkpoint。
Arm **-Continuation** 只改 messages 参数，不改 checkpoint。

## §3 判据

每个 Arm 独立判定：

```text
PASS  = continuation 成功（generate 返回非空输出，restore 未 throw）
FAIL  = continuation 失败（restore throw / rebuild / 空输出 / INCONCLUSIVE）
EXPECTED = P5-2-0 dependency map 预测的失败模式
```

关键判定：**不是 PASS/FAIL 本身，而是 PASS/FAIL 是否匹配 dependency map 的预测。**

```text
如果 -Identity → restore throw（预测正确）→ Identity 是必要成员 ✓
如果 -Identity → continuation 仍成功（预测错误）→ Identity 非必要 → 闭包修正
```

## §4 设计细节

### Arm -Identity（modelId mismatch）

修改 stripped fixture 的 meta.json：
```json
{"modelId": "wrong-model-name", ...}
```

预期：`performLoad` 行 1622 `guard metadata.modelId == currentModelId`
→ throw。

### Arm -Position（processedTokenCount = 0）

方案 A（不可行——processedTokenCount 在 safetensors 内部，不可直接修改）。
方案 B：使用一个空 safetensors 文件（零 KV rows）配合正常 meta.json。
预期：`loadPromptCacheSnapshot` 返回空 cache → `processedTokenCount = 0`
→ bootstrap 从零开始 → cold prefill。

### Arm -Anchor（P5-1 复用）

直接使用 P5-1 的 stripped fixture（history=[]）。
预期：ledgerBootstrapPending → 31712 > 212 → rebuild。

### Arm -Continuation（非 prefix messages）

保持完整 checkpoint，但 generate 传入一条不匹配 prefix 的消息：
```swift
messages: [userMsg("不相关的全新话题")]  // 非历史 prefix
```
预期：`isPrefix(existing.history, incoming) = false` → reuseMiss → cold。

## §5 判读矩阵

| Arm | 预测 | 若符合预测 | 若不符合 |
|---|---|---|---|
| Full | PASS | 基线确认 | — |
| -Identity | FAIL (throw) | Identity 必要 ✓ | Identity 非必要 → 闭包修正 |
| -Position | FAIL (rebuild) | Position 必要 ✓ | Position 非必要 → 闭包修正 |
| -Anchor | FAIL (rebuild) | Anchor 必要 ✓ | Anchor 非必要 → 闭包修正 |
| -Continuation | FAIL (cold) | Continuation 必要 ✓ | Continuation 非必要 → 闭包修正 |

**所有四项符合预测 → Closure {I,P,A,C} 最小性成立（在 MLX backend 上）。**

**任何一项不符合 → 该项从必要集合中移除 → 闭包修正提案（归 human）。**

## §6 与 P5-1 的关系

P5-1 只测试了 -Anchor 一个 arm。P5-2-C 补全其余三个 arm。
P5-1 的 trace 根因分析（ledgerBootstrapPending）为 -Anchor 的预测
提供了精确的机制解释。P5-2-C 的价值在于验证整个闭包，不是单点。

## §7 Harness 要求

```text
继承 P5-1 修正后的 harness 完整性标准：
  ✓ runUUID per process
  ✓ fresh summary cleanup（每 arm 独立 cleanup）
  ✓ SHA256 isolation before/after
  ✓ adjudication 检查 runUUID
  ✓ baseline 在同一 run 内计算
新增：
  + 每 arm 独立 observation namespace
  + 判读输出 match/mismatch vs dependency map prediction
  + 畸形 checkpoint 的构造和 SHA256 记录
```

## §8 预注册措辞

```text
PASS 措辞（如果所有 arm 符合预测）:
  "在 MLX backend 上，Execution State 的候选最小闭包
   {Identity, Position, Semantic Anchor, Continuation}
   中的每一项都是 continuation 的必要条件——移除任何一项
   均导致 continuation 失败，且失败模式与 dependency map
   预测一致。"

FAIL 措辞（如果任何 arm 不符合预测）:
  "候选闭包中 {列出非必要项} 不是 continuation 的必要条件
   （在 MLX backend 上）。闭包定义需要修正。"

INCONCLUSIVE 措辞:
  "实验未能在 MLX backend 上产生可判读结果。"
```
