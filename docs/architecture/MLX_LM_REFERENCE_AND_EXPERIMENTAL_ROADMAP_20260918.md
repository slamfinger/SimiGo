# mlx-lm 工程能力对照与 SimiGo 演进路线基准

日期：2026-09-18  
基线：SimiGo `main` @ `1d085c4cca5a8fece69eeed6aefb794ad1568be6`  
分支：`research/mlx-lm-reference-roadmap-20260918`

## 1. 目的

本文件不是把 `mlx-lm` Python 实现翻译成 Swift，也不是为 SimiGo 增加一套平行的 LLM Runtime。

目标是建立一个长期参照表：

1. **mlx-lm 已经解决的问题，优先复用其设计思想、官方 MLX API 或上游已有能力，避免 SimiGo 重造轮子。**
2. **SimiGo 已经解决的问题，不因参考 mlx-lm 而重新制造第二套状态真值。**
3. **SimiGo 尚未解决的问题，先建立可量测基线，再做最小实验切片。**
4. **任何优化都必须有 Before/After、正确性不变量、失败条件和回退路径。**
5. 参考 mlx-lm 的工程经验，不等于证明该方案适合 SimiGo；适配结论必须由 SimiGo 自己的实机实验产生。

---

## 2. 参考对象

本轮重点参考 mlx-lm 当前 main 中以下工程模块：

- `mlx_lm/generate.py`
  - `stream_generate`
  - `prefill_step_size`
  - prompt prefill / decode 分离
  - `BatchGenerator`
  - speculative decoding 相关生成路径
- `mlx_lm/models/cache.py`
  - `KVCache`
  - `RotatingKVCache`
  - prompt cache
  - LRU prompt cache
  - cache merge / extend / trim
  - prompt cache save/load
- `mlx_lm/server.py`
  - ModelProvider
  - ResponseGenerator
  - prompt cache 服务化
  - request queue
  - tool-call formatter
  - generation health / lifecycle
- `mlx_lm` 的模型加载、采样、chat template / tool-call 适配等基础能力。

参考链接：

- https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/generate.py
- https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/models/cache.py
- https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/server.py

> 注意：以上是外部参考实现，不是 SimiGo 的代码依赖关系。SimiGo 的 Runtime 真值仍以 NativeMLX + MLX/MLXLMCommon 官方 API 和 SimiGo 自己的实机证据为准。

---

# 3. 总体对照

| 能力 | mlx-lm 已有工程模块 | SimiGo 当前状态 | SimiGo 面临的问题 | 处理原则 |
|---|---|---|---|---|
| 模型加载 | ModelProvider / load | 已有 NativeMLX 模型容器 | 多模型/模型切换时内存治理 | 借鉴加载/释放纪律，不重复造模型加载器 |
| 生成循环 | stream_generate | 已由 ChatSession 官方 API 承担 | 长会话、取消、恢复 | 优先保持官方 Session 真值 |
| Prefill | prefill_step_size / chunked prefill | 已有 prefill telemetry；cold prefill 是压力源 | 大上下文 cold prefill 峰值、swap | 先量测 chunk size→TTFT/峰值内存曲线 |
| Decode | 单步/批量生成 | Single/interleaved 为生产基线 | 多请求并行利用率 | Batch 属 Execution Plane，独立于 Session |
| KV Cache | KVCache / RotatingKVCache | 官方 ChatSession 持有 KV；SimiGo 做 admission/eviction 外围治理 | 长上下文、并发 session 的 KV 压力 | 不建立第二套 Physical KV 真值 |
| Prompt Cache | LRUPromptCache / nearest cache | 已有官方 session/cache + SimiGo session 管理 | checkpoint/recovery 与长期复用 | 参考 cache persistence；不复制 token-level ledger |
| Cache trim | can_trim / trim_prompt_cache | GDN 路径明确存在不可 trim 边界 | 不可逆状态不能伪造 rewind | capability-first；不可 trim 就不假装可 rewind |
| Cache save/load | save/load prompt cache | checkpoint / roll-forward 已进入探索 | save/load 成本、恢复后 fragment 语义 | 先做 A/B 实验，再决定进入 Core |
| LRU | LRUPromptCache | SimiGo 已有 session LRU + P2 admission | token budget 是快照估算 | 借鉴 LRU 结构；SimiGo 继续以实机内存为基准 |
| Admission | 服务层按 cache/request 管理 | P2 已落地 | overBudget、并发替换、未来预测式预驱逐 | 先量测，再升级到 predictive admission |
| Batch | BatchGenerator | 已有实验轨；当前生产保持 single/interleaved | distinct prompt、KV isolation、cancel | 逐路与 single baseline 对比 |
| Continuous batching | server queue + batch generation 思路 | 尚未进入 Core | scheduler/arbitration | 后置，必须先完成 batch correctness |
| Speculative decode | mlx-lm 已有相关生成能力 | 未进入当前 Core | KV/state compatibility | capability gate；不得提前接入 |
| Tool calling | ToolCallFormatter / parser | SimiGo 有独立 Tool Governance | 工具密集长会话会放大 prompt 分歧 | 参考 parser/formatting；保留 SimiGo trace 与证据链 |
| Sampling | sampler/logits processors | 已有生成配置 | 不属于当前主要瓶颈 | 不重复实现成熟采样基础设施 |
| Memory release | gc + mx.clear_cache 等 | 已有 Memory / lifecycle settle | swap、cache buffer、模型 unload | 以 footprint/MLX memory telemetry 验证 |
| 服务健康 | generation thread / health | SimiGo 有 Lifecycle/health | 长请求、重连、总时长型失败 | 继续用真实 trace 验证 |
| 请求队列 | Queue / generation thread | Generation Gate 已存在 | 排队与实际 RUNNING 的边界 | 保持 lifecycle 状态与实际执行一致 |
| 模型能力声明 | mlx-lm 通过实际 cache/model 能力组织 | SimiGo 已有 ModelCapabilityContract | 多模型适配 | capability-first，不写 model-name 特判 |

---

# 4. 第一优先级：直接借鉴 mlx-lm，而不是自己发明

## 4.1 Chunked Prefill

mlx-lm 已把 `prefill_step_size` 作为正式生成参数：将长 prompt 分段处理，并在每段后显式评估 cache state。

SimiGo 当前已经证明：

- cold prefill 是高内存压力源；
- 长上下文下 swap 会明显改变执行时间；
- `fork-no-rewind` 会造成完整上下文重渲染。

因此下一步不应直接改 kernel，而应建立实验矩阵：

```
promptTokens
× prefillStepSize
× warm/cold
× memory footprint
× swap
× TTFT
× total prefill time
```

### 必须保存的基准

每次实验至少记录：

- model / model revision
- hardware
- OS
- MLX / mlx-swift-lm 版本
- promptTokens
- prefillStepSize
- cachedPromptTokens
- promptTime
- TTFT
- peak footprint
- swap
- decode tok/s
- completion correctness

### 准入条件

不能只因为：

> 峰值内存下降

就认定优化成功。

必须同时证明：

```
correctness == baseline
AND
peak memory ↓
AND
TTFT / total latency 在接受范围
```

---

## 4.2 Prompt Cache / Save & Load

mlx-lm 已有 prompt cache 保存/加载能力。

SimiGo 当前探索的 roll-forward：

```
last-known-good
      ↓
saveSessionCache
      ↓
risk detection
      ↓
high-risk → loadSessionCache
      ↓
fragment continuation
```

因此这里最重要的原则是：

> **借鉴“cache 是可持久化计算结果”这一成熟工程事实，不重新实现 token-level Physical KV。**

SimiGo 自己需要验证的是更上层的：

> 恢复后的会话是否进入 fragment continuation，并真正避免 ledger comparison → divergence → rewind → full prefill。

### 第一阶段只做实验，不直接进入 Core

必须记录：

- saveCache time
- cache bytes
- loadCache time
- first resumed fragment token count
- resumed TTFT
- fork-no-rewind count
- total prompt tokens
- memory footprint
- swap
- output correctness

### 证伪条件

若长程恢复会话出现：

```
fork-no-rewind > 0
OR
fragment token ≈ full context
OR
TTFT 回到 full-prefill 量级
```

则“恢复会话对 ledger divergence 免疫”的假设立即判为失败，停止继续产品化。

---

# 5. 第二优先级：Prefill / KV / Admission 的系统化治理

## 5.1 KV Cache：不要复制 mlx-lm 的底层真值

mlx-lm 已经有成熟的 cache class。

SimiGo 当前的正确边界：

```
Official ChatSession
        ↓
official KV state
        ↓
SimiGo service governance
    ├── session ownership
    ├── admission
    ├── eviction
    ├── lifecycle
    └── telemetry
```

禁止：

```
Official KV
+
SimiGo Physical KV ledger
+
SimiGo second cache protocol
```

因为历史审计已经证明，第二套 Physical KV 真值会产生状态漂移风险。

---

## 5.2 Admission

mlx-lm 的 prompt cache/LRU 设计可以作为结构参考。

SimiGo 当前 P2 已经具备：

- warm token budget
- LRU victim
- 官方 clear()
- 从 sessions 池原子移除
- 锁外 clear
- overBudget telemetry

下一阶段不是重新写 LRU，而是研究：

> **什么时候驱逐，比驱逐谁更重要。**

也就是：

```
当前：
memory pressure
    ↓
LRU eviction

未来实验：
predicted cold-prefill cost
+
predicted memory pressure
+
request admission
    ↓
pre-eviction
```

### 进入实现前必须先得到的数据

- admission 前后 swap
- admission 前后 peak footprint
- cold prefill duration
- 被驱逐 session 的 token 数
- 随后重新 cold/rebuild 的成本
- eviction hit rate
- overBudget duration

没有这组数据，不进入 predictive admission 实现。

---

# 6. 第三优先级：Batch

mlx-lm 已经提供 BatchGenerator 等模型级批量执行经验。

SimiGo 不能直接复制其结构，因为 SimiGo 还要处理：

- Agent identity
- Session identity
- logical branch
- lifecycle
- cancellation
- tool protocol
- admission
- physical KV

因此 Batch 必须继续遵循：

> **Batch 是 Execution Plane 对象，不是 Session 对象。**

实验顺序：

```
batch=2
   ↓
distinct prompt
   ↓
single-vs-batch token equality
   ↓
KV isolation
   ↓
per-sequence cancel
   ↓
latency arbitration
   ↓
batch=4
   ↓
continuous batching
```

### 硬基准

对每一个 batch member：

```
Batch[i].output
==
Single[i].output
```

并记录：

- batch size
- aggregate tok/s
- per-request tok/s
- TTFT
- queue wait
- active decode time
- memory peak
- cancellation correctness
- KV isolation
- lifecycle correctness

当前生产基线仍是既有 single/interleaved 基线；历史 batch prototype 的性能数字只能作为实验参考，不能直接视为生产性能。

---

# 7. 第四优先级：Tool Calling 与长会话

mlx-lm 已有 ToolCallFormatter、parser、chat message conversion 等工程经验。

SimiGo 应借鉴：

- tool-call 解析边界；
- streaming tool-call 状态；
- malformed/truncated tool-call 的处理；
- chat template 与 tool schema 的分离。

但不要因此重写 SimiGo 的 Tool Governance。

当前真正的问题不是“怎么 parse tool call”，而是：

```
tool result
    ↓
message reconstruction
    ↓
prompt divergence
    ↓
GDN cannot rewind
    ↓
fork-no-rewind
    ↓
full prefill
```

因此工具协议的每项改动都必须同时测：

- tool-call correctness
- message byte/token representation
- divergenceToken
- fork-no-rewind
- promptTokens
- promptTime
- TTFT

不能只测“工具还能不能正常调用”。

---

# 8. 第五优先级：Continuous Serving

mlx-lm server 的 request queue / generation thread / batch generation 可以作为设计参考。

但 SimiGo 不应现在直接进入 continuous batching。

当前路线：

```
S1
fixed batch
    ↓
distinct prompt isolation
    ↓
per-sequence cancellation
    ↓
latency arbitration
    ↓
S2
block/paged KV
    ↓
S3
continuous batching
```

原因：

> 当前最大的未知量仍是长上下文 KV / prefill / swap / fork 模态，而不是队列本身。

如果基础 KV 行为没有被证明，continuous batching 只会把问题放大。

---

# 9. 第六优先级：Speculative Decode

mlx-lm 已经具备 speculative generation 方向的工程实现，因此 SimiGo 不需要从零发明 draft/target generation protocol。

但当前不应接入 Core。

进入条件：

```
model capability
+
cache compatibility
+
per-sequence state isolation
+
deterministic correctness
```

基准至少包括：

- acceptance rate
- target model calls
- draft model calls
- output equality
- TTFT
- decode tok/s
- memory
- KV growth

没有 correctness baseline，不接受“速度提升”。

---

# 10. SimiGo 当前独有、mlx-lm 不能替代的部分

这些是 SimiGo 应该继续投入，而不是为了“向 mlx-lm 看齐”而删掉的能力：

### 10.1 Poisoned Session

```
cancel
  ↓
session state corruption
  ↓
reuse
  ↓
no-event hang
```

这是 SimiGo 已经通过真实设备实验发现并修正的 Runtime lifecycle 问题。

基准：

- cancel point
- raw event count
- session identity
- reuse/rebuild
- next request completion

---

### 10.2 Runtime Lifecycle

必须继续保持：

```
STOPPED
LOADING
RUNNING
SUSPENDED
RESUMING
```

并让请求生命周期：

```
QUEUED
RUNNING
COMPLETED
CANCELLED
FAILED
```

与实际执行一致。

---

### 10.3 Prefill Modal Telemetry

当前已经有：

```
cold
extend
rebuild
fork-no-rewind
other
```

这是 SimiGo 非常重要的实验资产。

任何未来优化都必须能够回答：

> 优化后到底减少了哪一种 prefill？

而不是只给一个平均 tok/s。

---

### 10.4 442fbf Benchmark

442fbf 是现阶段最重要的 regression fixture 之一。

关键事实：

- divergenceToken = 3,452
- 实际重渲 = 395,389 tokens
- 放大约 115×
- 最后一轮 common prefix 约 82,716 / 82,919
- 仍发生约 83,539 token full prefill

以后任何与：

- prompt cache
- session recovery
- message rendering
- fork
- prefill scheduler

有关的修改，都应保留这个 fixture 作为回归基准。

---

# 11. “借鉴但不造轮子”判定规则

以后新增能力前，先回答四个问题：

### Q1：mlx-lm / MLX 已经有吗？

如果有：

```
优先调用官方能力
        ↓
或者复用设计思想
        ↓
不要复制第二套底层实现
```

### Q2：SimiGo 是否已经有同类真值？

如果有：

```
保留现有真值
        ↓
只扩展外围治理
```

### Q3：这个问题到底在哪一层？

必须标记：

```
Model
Tokenizer
Chat Template
MLX
mlx-swift-lm
GDN
SimiGo Logical Plane
SimiGo Execution Plane
SimiGo Resource Plane
OS / Memory / Swap
```

### Q4：能不能用实验把假设证伪？

不能量测：

```
NO IMPLEMENTATION
```

没有 baseline：

```
NO OPTIMIZATION CLAIM
```

---

# 12. 每项工作的统一实验模板

以后所有 Runtime 工作统一采用：

```
Hypothesis
    ↓
Current Baseline
    ↓
Smallest Change
    ↓
Controlled Experiment
    ↓
Real Hardware
    ↓
Trace / Metrics
    ↓
Invariant Audit
    ↓
Comparison
    ↓
Stress / Failure
    ↓
Decision
    ├── Promote
    ├── Iterate
    └── Reject
```

## 必备基准

### 性能

- TTFT
- prompt tokens
- prompt time
- decode tok/s
- total latency

### Cache

- cached prompt tokens
- cache tokens
- cache bytes
- hit/miss
- save/load time

### Memory

- footprint
- active memory
- MLX cache
- swap
- peak

### Runtime

- session identity
- execution key
- lifecycle state
- cancel point
- completion/failure

### Prefill

- mode
- promptTokens
- cachedPromptTokens
- divergenceToken
- fork@common
- prefill time

### 正确性

- output equality
- token-prefix equality
- KV isolation
- no poisoned session
- no ledger mismatch
- no lifecycle leak

---

# 13. 当前路线排序

基于当前 SimiGo main 和已有实验，不把未来工作全部同时启动。

## P0：保持证据闭环

```
Qwen35ToolRestartRule
+
fork-no-rewind evidence
+
442fbf fixture
+
prefill statistics
```

状态：已有基础，不再重复实现。

---

## P1：Roll-forward 第一实验切片

目标：

> 验证 checkpoint recovery 是否真的构成一种“分歧隔离执行模式”。

只做：

```
save last-known-good
+
risk detection
+
load checkpoint
+
fragment continuation
```

必须带：

- feature flag
- rollback
- save/load timing
- fragment token telemetry
- fork-no-rewind telemetry
- 10/20/50+ 长程工具会话

---

## P1：Prefill Step Size 实验

目标：

> 找到 cold prefill 的 memory/latency Pareto 曲线。

不直接改变生产默认值。

---

## P2：Predictive Admission

前提：

> 先从生产窗口证明当前 LRU admission 在哪些 workload 下仍然不够。

---

## P2：Batch correctness

先 distinct prompt + isolation，再性能。

---

## P3：Continuous batching / Block KV / Prefix tree

只有前置基准稳定后才启动。

---

## P4：Speculative decode

等待 Batch、KV、cache semantics 稳定。

---

# 14. 长期架构原则

SimiGo 不应该成为：

> “Swift 重写版 mlx-lm”。

更合理的关系是：

```
                    MLX
                     │
          ┌──────────┴──────────┐
          │                     │
       mlx-lm                SimiGo
       reference              Runtime
          │                     │
   model/cache/generate    lifecycle
   serving primitives      session governance
                            admission
                            recovery
                            observability
                            experiments
                            Apple Silicon UX
```

mlx-lm 负责证明大量基础工程模式已经可行。

SimiGo 的价值在于：

> **把这些成熟能力作为底座，把“长期、本机、Agent、多 Session、可恢复、可量测”的 Runtime 问题继续向上解决。**

---

# 15. 最终红线

任何新功能，无论来自 mlx-lm、llama.cpp、vLLM、SGLang 还是自己的想法，都必须满足：

```
参考实现
    ↓
层位判断
    ↓
SimiGo baseline
    ↓
最小实验
    ↓
实机测量
    ↓
不变量验证
    ↓
失败条件
    ↓
可回退
    ↓
才允许进入 Core
```

**“mlx-lm 已经做过”只能证明值得研究，不能证明 SimiGo 可以直接合入。**

**“理论上更快”不能替代 benchmark。**

**“代码看起来正确”不能替代真机实验。**

**“性能提高”不能覆盖 correctness / lifecycle / KV safety 回归。**

最终目标不是减少代码量，而是：

> **让 SimiGo 少造轮子，把工程精力集中在 mlx-lm 没有替 SimiGo 解决的 Runtime 问题；同时让每一次借鉴都留下可量测、可实验、可复核的证据链。**
