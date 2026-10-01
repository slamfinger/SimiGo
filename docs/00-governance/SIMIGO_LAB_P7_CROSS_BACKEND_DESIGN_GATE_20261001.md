# P7: Cross-backend Validation — Design Gate

日期：2026-10-01  
状态：`DESIGN GATE / AWAITING HUMAN AUTHORIZATION`  
前置：P6 FROZEN (Conceptual Boundary)  
核心命题：Closure 与 Carrier 是否可分离  
Contract v1.0：不变

---

## §0 核心命题

> 同一个 Execution State Closure，能否映射到不同 backend 的 carrier，
> 并保持 continuation 关系成立？

不是问"哪个 backend 更快"，不是问"能否读同一个文件"。

形式化：
```text
同一个 S₀ closure
       │
       ├── Carrier A (MLX)  → continuation → Y_A
       │
       └── Carrier B (other) → continuation → Y_B

Y_A ≈ Y_B → Closure 跨 carrier 保持
Y_A ≠ Y_B → Closure 是 backend-specific
```

## §1 Hard boundaries

```text
❌ 不比性能
❌ 不测文件格式互操作（那是 carrier 层，不是 closure 层）
❌ 不选"更好"的 backend
❌ 不修改 Contract v1.0 或 P6 frozen definition
❌ 不进入 Palace / Security
```

## §2 Backend 选择

最小有效验证：两个独立 runtime。

| | Backend A | Backend B |
|---|---|---|
| 当前 | MLX (NativeMLX) | 待选 |
| 候选 | — | llama.cpp server（已有 LLAMAServerExecutionStateAdapter） |

候选 B 选择标准：
1. 已有 adapter（P5-2-ER Phase C 已实现 LLAMAServerExecutionStateAdapter）
2. 与 MLX 架构差异足够大（不同 KV 格式 / 不同 tokenizer / 不同 context 管理）
3. 可在当前环境运行

## §3 Closure mapping（跨 backend 的四关系映射）

| Closure Relation | MLX 表达 | Candidate B 表达（候选） |
|---|---|---|
| Identity | modelId + kvFingerprint + storageKey | model hash + context params + session id |
| Position | processedTokenCount + cachedTokens | context position / n_past |
| Semantic Anchor | history[] in meta.json + rendered prompt | conversation checkpoint / prompt cache |
| Continuation | isPrefix check + PromptCacheReusePolicy | prompt prefix check / context extend |

映射原则：不同 backend 的**表达方式**不同，但**关系结构**应相同。

## §4 实验矩阵

### Cell 1: Identity 跨 backend

测试：同一 model/config/execution 在两个 backend 中是否产生
可对应的 Identity。

判据：
```text
PASS = 两 backend 均能确认"这是同一个 model + config 的状态"
FAIL = 一方无法建立 identity 对应
```

### Cell 2: Position 跨 backend

测试：相同的计算位置（如 token offset N）在两个 backend 中
是否可表达且等价。

判据：
```text
PASS = 两 backend 均能表示 position=N 且语义一致
FAIL = position 表达不可映射
```

### Cell 3: Anchor 跨 backend（最关键）

测试：同一 conversation history 在两个 backend 中是否产生
等价的 semantic anchoring。

这隐含一个前提：两 backend 使用同一模型（否则 KV 不兼容）。
但 tokenizer 可能不同（MLX vs llama.cpp 的 tokenizer 实现）。

判据：
```text
PASS = 两 backend 在相同 history 输入下产生等价的 anchor 表达
FAIL = tokenizer 差异导致 anchor 不可比较
INCONCLUSIVE = tokenizer 差异是 carrier 层问题，不影响 closure 定义
```

### Cell 4: Continuation 跨 backend

测试：从等价的 S₀ 出发，两个 backend 是否产生属于同一
computation topology 的未来计算。

注意：greedy decoding（temperature=0）下，如果模型和 tokenizer
完全相同，输出应一致。如果 tokenizer 不同，输出可能不同但语义等价。

判据：
```text
PASS = 两 backend 的 continuation output 语义等价
FAIL = continuation 语义不等价（closure 断裂）
INCONCLUSIVE = 输出差异归因于 carrier 层（tokenizer 差异）
```

## §5 成功/失败的整体判定

```text
ALL PASS → Execution State Closure 跨 carrier 保持
          → ES 从 MLX-specific 提升为 backend-independent abstraction

ANY FAIL → Closure 依赖 backend-specific semantics
          → 需要找 backend-independent core
          → P6 frozen definition 可能需要修订（归 human）

MIXED    → 部分 relation 可跨 backend，部分不可
          → 需要进一步分析哪些是 invariant 哪些是 implementation detail
```

## §6 预注册措辞

```text
CROSS_BACKEND_VALIDATED:
  "Execution State Closure {I,P,A,C} 在 MLX 和 {B} 两个
   backend 中均可表达并保持 continuation 关系。closure 与
   carrier 可分离。"

BACKEND_SPECIFIC:
  "Execution State Closure 依赖 backend-specific semantics。
   {列出哪些 relation 不可跨 backend}。"

INCONCLUSIVE:
  "实验受 carrier 层差异（tokenizer/model format）阻碍，
   closure 层等价性无法判定。"
```

## §7 Harness 要求

```text
继承 P5 系列完整性标准
新增：
  + 双 backend 同时记录 runtime facts
  + 输出语义等价性判定标准（在 tokenizer 可能不同的前提下）
  + Carrier 差异记录（tokenizer / model format / context 管理）
```

## §8 Open questions

```text
OP-7-1  LLAMAServerExecutionStateAdapter 是否已支持全部四项
        closure relation 的映射？
OP-7-2  Tokenizer 差异是否可以通过 canonical text comparison
        绕过（不比较 token IDs，只比较输出文本）？
OP-7-3  如果两个 backend 使用不同的 KV format，Identity 的
        "同 model + config" 判定标准是什么？
```
