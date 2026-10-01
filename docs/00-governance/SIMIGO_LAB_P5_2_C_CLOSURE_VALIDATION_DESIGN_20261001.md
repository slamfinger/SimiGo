# P5-2-C: Backend Dependency Closure Validation — Design Draft (rev.2)

日期：2026-10-01  
状态：`DESIGN DRAFT rev.2 / AWAITING HUMAN AUTHORIZATION`  
前置：P4 PASS → P5-1 INCONCLUSIVE → P5-2 ER PASS-WITH-REVISIONS  
Closure：`{Identity, Position, Semantic Anchor, Continuation}` (provisional)  
Contract v1.0：不变  
 rev.1→rev.2 变更：区分 closure ablation 与 input validation；
-Anchor 引用 P5-1；结论改为 Backend Dependency Closure Validated

---

> **验证目标：当前 backend 中，closure relations 是否为 continuation
> 的 dependency prerequisite。** 不是证明理论最小闭包（那需要多
> backend）。不是验证 input validation（那是防御行为，不是 closure
> 行为）。

## §0 两层结论（rev.2 新增）

```text
Level 1: Implementation Dependency Closure（本实验验证）
  问题：MLX backend 当前实现中，移除一项 closure relation
        是否导致 continuation capability 丢失？
  结论形式：Backend Dependency Closure Validated / Not Validated

Level 2: Abstract Closure（不在本实验范围内）
  问题：这些关系是否属于 Execution State 的抽象定义？
  前提：需要 ≥2 个不同 backend 的交叉验证
  结论形式：Universal Minimal Closure Proven / Disproven
```

## §1 Hard boundaries

```text
❌ 不证明 Execution State = KV / cache / database / graph
❌ 不证明 Universal Minimal Closure（Level 2 超范围）
❌ 不修改 Contract v1.0
❌ 不选存储方案
❌ 不做 Palace / Security 实验
❌ 不将 input validation 混淆为 closure ablation（rev.2 核心修正）
```

## §2 closure ablation 与 input validation 的区分

```text
Input validation:
  系统检测到非法输入 → 拒绝 → throw
  例：modelId 值改为错误 → guard 检查失败 → throw
  这证明的是：系统有防御机制
  这不证明的是：Identity relation 是 continuation 的必要条件

Closure ablation:
  移除一条 closure relation → 系统接受了状态
  但 continuation 语义不完整（无法归属 / 无法定位 / 无法解释 /
  无法继续）
  这证明的是：该 relation 是 continuation 的必要前提
```

rev.2 修正：每个 arm 的设计必须产生 **closure ablation**（状态被
接受但语义缺失），而非 **input validation**（状态被拒绝）。
如果实现层面无法产生 closure ablation（系统在 closure 缺失前就
拒绝），则记录 `REJECTED_AT_VALIDATION_GATE`，并标注该 relation
在当前实现中不可独立消融。

## §3 实验矩阵（rev.2）

| Arm | 测试什么 | 实现方式 | 预期失败模式 |
|---|---|---|---|
| **Full** | 基线（closure 完整） | 标准 loadSessionCache + generate | PASS |
| **-I** | Identity provenance 缺失 | 删除 meta.json 中的 modelId 和 kvFingerprint 字段（物理 KV 不变） | `REJECTED_AT_VALIDATION_GATE`（guard 检查 nil → throw）或 `restore 成功但无法归属` |
| **-P** | Position relation 不可验证 | 修改 meta.json 中 history count 为与 KV cache 实际 token count 不一致的值（物理 KV 不变） | `REJECTED_AT_VALIDATION_GATE`（SHA check 仍 pass，但 ledger mismatch → rebuild）或 `continuation 在错误位置` |
| **-A** | Semantic Anchor 缺失 | **引用 P5-1**（history=[]），不重复执行 | rebuild（P5-1 trace 已证） |
| **-C** | Continuation path 不可达 | 保持完整 checkpoint，传入非 prefix messages | cold prefill（reuseMiss） |

### Arm -I 设计细节

物理 carrier 不变（same safetensors, same SHA256）。
从 meta.json 中**删除** `modelId` 和 `kvFingerprint` 字段
（不是改为错误值——错误值 = input validation；缺失值 = closure
ablation）。

预期路径：
1. `performLoad` L1619: `guard let checkpointGeneration` — generation
   仍在，pass
2. `performLoad` L1622: `guard metadata.modelId == currentModelId`
   — modelId 为 nil → **throw**
3. 记录：`REJECTED_AT_VALIDATION_GATE / modelId nil → throw`

如果系统在 validation gate 拒绝，则 Identity relation 在当前实现中
不可独立消融——它内嵌于 load 必要条件中。这本身是有价值的发现：
它意味着 Identity 在当前实现中是 **continuation 的硬前置条件**，
而非可缺失的软关系。

### Arm -P 设计细节

物理 carrier 不变（same safetensors, same SHA256）。
修改 meta.json 中 `history` 数组——用一个假的短数组（如 1 条消息）
替换原始的 16-17 条消息。

效果：`performLoad` 的 `cacheSHA256` check 仍然 pass（因为
cacheSHA256 是对 safetensors 的哈希，与 meta.json 的 history 无关）。
`SessionCacheMetadata.history.count = 1`，但实际 KV cache 有 31712
tokens。恢复后 ChatSession 的 `ledgerBootstrapPending` 看到：

```text
processedTokenCount = 31712
promptTokenIds.count = ~200（1 条假 history + probe）
31712 > 200 → ledger invalidated → rebuild
```

这测试的是：**Position relation（processedTokenCount ↔ ledger
alignment）被破坏时，continuation 是否仍可维持。**

与 -A（P5-1）的区别：P5-1 删除了全部 history text（anchor 消失）；
-P 保留假 history text（anchor 存在但 position 不匹配）。这区分了
Semantic Anchor（内容对齐）和 Position（计数对齐）。

### Arm -C 设计细节

完整 checkpoint，不做任何修改。
generate 传入一条与 history 无关的新消息（非 prefix）。
`isPrefix` 返回 false → `reuseMiss` → cold path。

这测试的是：**Continuation relation（S₀ → Δ 的接受规则）被破坏时
（Δ 不在允许的 continuation path 上），是否仍能从 S₀ 继续。**

## §4 判据（rev.2）

每个 Arm 有三种可能结果：

```text
CLOSURE_ABLATED     = 状态被系统接受，但 continuation 语义缺失
                      （rebuild / cold / 空输出 / 位置偏移）
VALIDATION_REJECTED = 系统在 validation gate 拒绝了状态
                      （该 relation 在当前实现中不可独立消融）
NO_EFFECT           = 状态被接受且 continuation 正常
                      （该 relation 不是必要成员）
```

判定矩阵：

| Arm | 预测 | CLOSURE_ABLATED | VALIDATION_REJECTED | NO_EFFECT |
|---|---|---|---|---|
| Full | PASS | — | — | 基线 ✓ |
| -I | VALIDATION_REJECTED | Identity 可独立消融（新发现） | **预测符合**：Identity 是硬前置 ✓ | Identity 非必要 → 修正 |
| -P | CLOSURE_ABLATED (rebuild) | **预测符合**：Position 必要 ✓ | Position 在实现中不可消融 | Position 非必要 → 修正 |
| -A | CLOSURE_ABLATED (rebuild) | **预测符合**（P5-1 引用） | — | Anchor 非必要 → 修正 |
| -C | CLOSURE_ABLATED (cold) | **预测符合**：Continuation 必要 ✓ | Continuation 不可消融 | Continuation 非必要 → 修正 |

**全部 CLOSURE_ABLATED 或 VALIDATION_REJECTED →
Backend Dependency Closure Validated（所有四项 relation 均为
continuation 的必要前提，在 MLX 当前实现中）。**

**任何 NO_EFFECT → 该 relation 从 backend dependency closure 中移除
→ 闭包修正提案（归 human）。**

## §5 预注册措辞（rev.2）

```text
VALIDATED 措辞（如果无 NO_EFFECT）:
  "MLX backend dependency closure validated：{I, P, A, C} 中的
   每一项都是 continuation 的必要前提。移除任何一项要么导致
   continuation 语义缺失（CLOSURE_ABLATED），要么被实现层
   validation gate 拒绝（VALIDATION_REJECTED = 硬前置条件）。
   该结论限于当前 MLX backend 实现（Level 1）。"

NOT_VALIDATED 措辞（如果有 NO_EFFECT）:
  "候选闭包中 {列出} 不是 MLX backend continuation 的必要前提。
   Backend dependency closure 需要修正。"

INCONCLUSIVE:
  "实验未能产生可判读结果。"
```

## §6 Harness 要求（不变，继承 P5-1 标准）

```text
✓ runUUID per process
✓ fresh summary cleanup（每 arm 独立 cleanup）
✓ SHA256 isolation before/after（checkpoints + prefix pool）
✓ adjudication 检查 runUUID
✓ baseline 在同一 run 内计算
+ 每 arm 独立 observation namespace
+ 判读输出：result_type (CLOSURE_ABLATED / VALIDATION_REJECTED /
  NO_EFFECT) + match/mismatch vs prediction
+ 畸形 checkpoint 的构造方式 + SHA256 + diff 记录
```

## §7 与 P5-1 的关系

P5-1 = -A arm 的先例（Anchor 消融）。P5-2-C 不重复执行 -A，
引用 P5-1 的 trace 根因（ledgerBootstrapPending）和结果（rebuild）
作为 evidence。

P5-2-C 新增价值：
- -P 区分了 Position（计数对齐）和 Anchor（内容对齐）
- -I 确认 Identity 在实现层是否可独立消融
- -C 确认 Continuation relation 的必要性
