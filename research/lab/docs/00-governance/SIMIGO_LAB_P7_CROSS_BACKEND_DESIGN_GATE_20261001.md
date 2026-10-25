# P7: Cross-backend Validation — Design Gate rev.1

日期：2026-10-01  
状态：`DESIGN GATE rev.1 / AWAITING OP-7 ANSWERS THEN HUMAN AUTHORIZATION`  
前置：P6 FROZEN (Conceptual Boundary)  
核心命题：Closure portability（Level 1：两个 backend 间的 mapping 验证）  
Contract v1.0：不变  
rev.0→rev.1 变更：output equality → closure invariant；mapping 方向
从 MLX→llama 转换改为 Abstract Closure→独立表达；OP-7 升级为执行前必须回答

---

## §0 核心命题

> 同一个抽象 Execution State Closure，能否被独立 carrier 分别表达，
> 并在各自 carrier 上保持 continuation invariant？

映射方向（rev.1 关键修正）：
```text
Abstract Closure
       ↓
MLX representation（expression 1）

Abstract Closure
       ↓
llama.cpp representation（expression 2）

不是：MLX state → llama state（转换工具）
而是：Abstract Closure → 独立表达
```

## §1 Hard boundaries

```text
❌ 不比性能
❌ 不测文件格式互操作（carrier 层）
❌ 不选"更好"的 backend
❌ 不修改 Contract v1.0 或 P6 frozen definition
❌ 不进入 Palace / Security
❌ 不将 mapping 失败归因于 closure 定义错误
```

## §2 Backend 选择（APPROVED）

| | Backend A | Backend B |
|---|---|---|
| 选定 | MLX (NativeMLX) | llama.cpp server |
| adapter | NativeMLX | LLAMAServerExecutionStateAdapter |
| 定位 | Level-1 mapping carrier 1 | Level-1 mapping carrier 2 |

Backend B = llama.cpp，APPROVED（Level-1 validation only）。
不代表所有 backend，仅作为独立实现路径的 carrier 表达。

## §3 Closure mapping（Abstract Closure → backend expression）

| Closure Relation | MLX expression | llama.cpp expression（候选） |
|---|---|---|
| Identity | modelId + kvFingerprint + storageKey | model hash + context params + session id |
| Position | processedTokenCount + cachedTokens | context position / n_past |
| Semantic Anchor | history[] + rendered prompt | conversation checkpoint / prompt cache |
| Continuation | isPrefix + PromptCacheReusePolicy | prompt prefix check / context extend |

映射原则：不同 backend 的表达方式不同，但关系结构应相同。

## §4 实验矩阵（rev.1：closure invariant，非 output equality）

### Cell 1: Identity — lineage recognition

测试：两 backend 是否识别同一 Execution lineage。

判据：
```text
PASS = 两 backend 均能建立 identity 对应（same model semantics
       + same conversation lineage）
FAIL = 一方无法建立对应（mapping unavailable，非 closure 错误）
```

### Cell 2: Position — continuation point expression

测试：两 backend 是否能表达相同的 continuation point。

判据：
```text
PASS = 两 backend 均能表达等价的 continuation point
FAIL = 一方无法表达（mapping unavailable）
```

### Cell 3: Anchor — semantic context correspondence（最关键）

测试：两 backend 是否能证明对应同一 semantic context。

判据：
```text
PASS = 两 backend 均能确认 anchor 对应同一 semantic context
FAIL = anchor 对应不可建立（mapping unavailable）
INCONCLUSIVE = tokenizer/carrier 差异阻碍判定（不归因 closure）
```

### Cell 4: Continuation — computation topology consistency

测试：后续输入是否沿同一 computation topology 继续。
比较 continuation consistency，不是 exact text match。

判据：
```text
PASS = 两 backend 的 continuation 沿同一 topology（语义等价）
FAIL = continuation topology 断裂（一侧无法从 S₀ 继续）
INCONCLUSIVE = 输出差异归因于 carrier 层
```

## §5 整体判定

```text
ALL PASS → Closure 可由独立 carrier 表达
          → ES 具备 cross-carrier portability (Level 1)

ANY FAIL → mapping 不可建立 / closure 要求需修订
          → 不等于 Execution State 不成立
          → 失败归因：adapter / capability / missing carrier support

MIXED    → 部分可 mapping，部分不可
          → 区分 invariant vs implementation detail
```

## §6 预注册措辞

```text
CROSS_BACKEND_PORTABILITY_VALIDATED_L1:
  "抽象 Execution State Closure {I,P,A,C} 可被 MLX 和 llama.cpp
   两个独立 carrier 分别表达并保持 continuation invariant。
   Closure 与 carrier 可分离（Level 1：两 backend 验证）。"

CLOSURE_PORTABILITY_LIMITED:
  "Closure 的 {列出} relation 在当前 mapping 中不可跨 carrier
   表达。需进一步区分 mapping 限制与 closure 本身限制。"

MAPPING_UNAVAILABLE:
  "当前 adapter/backend 不支持 {列出} closure relation 的表达。
   这是 mapping/capability 限制，不是 closure 定义错误。"
```

## §7 Harness 要求

```text
继承 P5 系列完整性标准
新增：
  + 双 backend 同时记录 runtime facts
  + 输出比较 = semantic equivalence / continuation consistency
    （不是 exact text match）
  + Carrier 差异记录（tokenizer / model format / context 管理）
```

## §8 Open questions（执行前必须回答）

```text
OP-7-1  Closure mapping 定义方向确认：
        Abstract Closure → 独立 backend expression（不是
        MLX state → llama state 转换）。
        LLAMAServerExecutionStateAdapter 当前支持哪些 relation？

OP-7-2  Identity 跨 backend 判定标准冻结：
        "same model" = same model file / same model semantics /
        same conversation lineage？
        三者不同，必须明确 P7 使用哪一个。

OP-7-3  Failure 归因规则冻结：
        llama.cpp 无法恢复 ≠ Execution State 不成立
        = 当前 backend mapping 未建立
        （失败可能来自 adapter / capability / missing carrier support）
```
