# SimiGo 架构演进白皮书
## Stable Foundation → Execution Batch → Paged KV → Continuous Serving

**文档定位：长期架构参考，不是阶段性开发计划。**

SimiGo 是运行在 Apple Silicon macOS 上的本地高性能 AI Inference Runtime，同时承担 Local/LAN 共享推理节点职责。

其核心目标不是复制某一个 GPU 推理框架，而是在 MLX 原生执行能力之上，建立：

```text
Protocol
+ Agent-safe Execution
+ Physical KV Reuse
+ Resource Governance
+ Lifecycle Safety
+ Multi-Agent Scheduling
+ Controlled Batch Execution
```

SimiGo 的外部 Agent 决定“做什么”，SimiGo 负责“把模型安全、可观测、高效地算出来”。

---

# 第一章 总体演进原则

## 1.1 守正：v4.5 Stable Foundation 永不被新能力反向破坏

SimiGo 当前 v4.5 Stable Foundation 继续作为长期稳定底座。

它不是旧版本，也不是下一阶段完成后准备删除的过渡层。

所有未来能力必须建立在以下不变量之上：

```text
Logical State Isolation
Physical KV Correctness
Physical Token Ledger
Tool Fingerprint Safety
Lifecycle Convergence
Cancellation Safety
Memory Admission Safety
Observability
Agent Runtime ≠ Inference Runtime
```

未来能力不得通过修改这些基础语义来取得性能收益。

尤其禁止：

```text
Batch 破坏 Session 隔离
Batch 共享 Logical Branch State
Batch 绕过 Generation Gate
Batch 绕过 Admission
Batch 绕过 Ledger
Batch 直接持有 Agent 生命周期
Batch 修改 Tool Protocol 语义
```

---

## 1.2 精简：减少重复结构，而不是减少安全边界

v4.5 中已经形成的若干机制可以逐步合并表达，但不得合并语义。

例如：

```text
多个 lifecycle helper
        ↓
统一 Runtime Lifecycle contract

多个 KV 判断逻辑
        ↓
统一 KV Capability / Selection contract

多个 admission 判断
        ↓
统一 Resource Admission contract
```

允许：

```text
实现更短
类型更少
辅助代码更少
Trace 更统一
```

禁止：

```text
不再验证
不再对账
不再收敛
不再区分 Logical / Execution / Physical State
```

原则：

> **代码可以精简，契约不能精简。**

---

# 第二章 三平面模型保持不变

SimiGo 始终保持三个核心平面：

```text
┌─────────────────────────────────────────┐
│ Logical Plane                            │
│ Agent → Session → Logical Branch → Request│
└────────────────────┬────────────────────┘
                     │
┌────────────────────▼────────────────────┐
│ Execution Plane                          │
│ Gate → Scheduler → Batch → Decode       │
└────────────────────┬────────────────────┘
                     │
┌────────────────────▼────────────────────┐
│ Physical Plane                           │
│ Physical KV → KV Memory → Model Runtime │
└─────────────────────────────────────────┘
```

此外仍保留独立 Resource / Observability / Lifecycle 语义，但不得把它们重新混成一个“大 Runtime State”。

---

# 第三章 当前 Stable Foundation 状态

截至当前演进基线：

```text
Lifecycle                 STABLE
Generation Gate           STABLE
Prefill Scheduler         STABLE
Cancellation              STABLE
Physical Token Ledger     STABLE
KV Prefix Reuse           STABLE
KV Admission              STABLE
KV Eviction               STABLE
Tool Protocol             STABLE
Runtime Trace             STABLE
Multi-owner Safety        STABLE
```

当前已经得到实机支持的新增能力：

```text
Standard-KV Batched Decode
Architecture feasibility:   PROVEN
    batch=4 ≈ 75.1 tok/s
    （性能实验结果——不代表正确性通过）
Current dependency:         BLOCKED
    T=1 batched decode 行 > 0 缺陷
    （mlx-swift-lm 3.31.4 / MLX 0.31.6）
Production:                 NO-GO
Qualification:              ACTIVE
    S1-R.1 取证完成
    Conformance Matrix 待依赖演进
```

S1 状态（审计第五轮定义）：

```text
S1-R  Dependency Qualification
      ✅ Forensics complete
      ❌ Current backend batch decode correctness REJECTED

S1-A  Execution Architecture
      ✅ skeleton complete（Capability 两层三态 + fixed-slot 调度骨架）
      ⏸ production integration blocked（等 S1-R 通过）

S1-B  Validated Batch Runtime
      等待 S1-R 通过后立项
```

最新测试仍保持：

```text
Standard-KV / Qwen3-Coder
79 / 79
（含 Batched 实验轨 EXPECTED-FAIL 固化：
 BatchDecodeDependencyConformanceTests——上游回归工件）

Hybrid / Tiel-Coder
79 tests
3 skip（Batched 实验轨门控）
0 failure
```

CI 报告分组口径：

```text
Foundation:     68/68 PASS
Experimental:   EXPECTED-FAIL（上游回归工件）
Hybrid:         3 SKIPPED
```

当前 Batch 仍属于实验轨，不属于 Core Runtime；生产 decode 路径保持
Single / interleaved（交错基线 ≈ 43 tok/s aggregate）。

---

# 第四章 演进纪律

未来任何能力都必须遵循：

```text
Design
  ↓
Smallest Prototype
  ↓
Real Hardware Benchmark
  ↓
Invariant Audit
  ↓
Stress / Failure Test
  ↓
Stable DMG
  ↓
Soak / Real-world Use
  ↓
Next Stage
```

禁止：

```text
理论可行
   ↓
直接合入 Core
```

也禁止：

```text
发现性能机会
   ↓
大规模重构底座
```

每个阶段必须：

1. 保留上一阶段可用版本；
2. 可一键关闭新能力；
3. 有明确回退路径；
4. 有 Benchmark 硬指标；
5. 有失败条件；
6. 有稳定 DMG 出口。

---

# 第五章 Evolution Track 总路线

SimiGo 的未来演进划分为三个主要时代。

```text
S1
Controlled Batched Execution
        ↓
S2
Paged / Block KV + Advanced Prefix Reuse
        ↓
S3
Continuous Serving + Arbitration + Speculative Execution
```

它们不是三个并行项目。

必须严格按顺序完成。

---

# 第六章 S1 —— Controlled Batched Execution

## 6.1 目标

把已经证明有效的：

```text
[B, L]
[B, 1]
```

模型级 Batch 原型升级成真正的：

```text
SimiGo Execution Batch
```

核心不是“让模型接受 batch”。

而是：

> **让多个独立 Request 在 Execution Plane 中共享一次 Model Forward，而 Logical State 与 Physical KV 语义保持独立。**

---

## 6.2 第一原则：Batch 属于 Execution Plane

正确：

```text
Request A ─┐
Request B ─┼→ Batch Execution → Model Forward
Request C ─┤
Request D ─┘
```

错误：

```text
Session → Batch
Branch  → Batch
Agent   → Batch
```

Batch 是执行编排对象，不是业务身份对象。

---

## 6.3 新增三个核心抽象

### `InferenceModelCapabilities`

模型能力声明：

```swift
struct InferenceModelCapabilities {
    let supportsBatchDecode: Bool
    let supportsPerSequenceRoPE: Bool
    let supportsIndependentKVState: Bool
    let supportsPromptCacheTrim: Bool
    let supportsRaggedBatch: Bool
    let supportsRecurrentStateBatch: Bool
    let supportsSpeculativeDecode: Bool
    let supportsPagedKV: Bool
}
```

Runtime 不允许根据 model name 写特殊分支：

```swift
if modelName.contains(...)
```

统一使用 Capability。

---

### `BatchSequence`

表示 Batch 内一个执行成员：

```text
BatchSequence
    requestId
    executionKey
    slotId
    tokenState
    cacheState
    cancelled
    active
```

其中：

```text
executionKey ≠ slotId
```

这是未来长期不变量。

---

### `BatchedDecodeScheduler`

职责：

```text
Waiting Requests
      ↓
Capability Filter
      ↓
Logical Safety Filter
      ↓
KV Admission
      ↓
Latency Budget
      ↓
Batch Formation
      ↓
Batched Forward
```

它不拥有 Session，不负责 Tool，不负责 Agent。

---

# 第七章 S1 第一阶段：Fixed Batch

第一版只支持：

```text
batch = 2 / 4
same model
standard-KV
greedy / deterministic
fixed decode quantum
```

先禁止：

```text
continuous batching
ragged batch
hybrid Mamba
mixed model batch
跨模型 batch
```

理由：

> 第一阶段必须首先证明“执行层 Batch 不会污染请求级状态”。

---

# 第八章 S1 第二阶段：Distinct Prompt Isolation

第一版原型当前存在的限制：

```text
A = Prompt
B = Prompt
C = Prompt
D = Prompt
```

下一阶段必须改成：

```text
A
B
C
D
```

而且每一路必须分别与：

```text
single(A)
single(B)
single(C)
single(D)
```

进行逐路结果比较。

硬契约：

```text
Batch[i].tokenPrefix
==
Single[i].tokenPrefix
```

并同时检查：

```text
Batch KV row independence
Batch token count
Batch cancellation
Batch completion
```

这是 S1 的 P0 正确性测试。

---

# 第九章 S1 第三阶段：Batch Cancellation

Batch 中允许：

```text
A
B ← CANCEL
C
D
```

定义：

```text
B cancelled
↓
B immediately leaves next decode step
↓
A/C/D continue
↓
B never commits partial KV
↓
A/C/D independently finalize
```

禁止因为一个 sequence cancellation：

```text
cancel whole batch
```

除非底层 Model Forward 本身已经无法恢复，这种情况下必须回退到独立执行并记录 Trace。

---

# 第十章 S1 第四阶段：Latency Arbitration

最终 Batch Scheduler 不应该简单使用：

```text
queue.count >= 4
```

而应根据：

```text
queue depth
request age
latency budget
expected decode length
model capability
KV availability
current decode load
```

进行 arbitration。

策略示例：

```text
单 Agent 交互：
    batch=1 preference

多 Agent：
    等待极短 quantum
    batch=2/4

延迟即将超限：
    立即 flush

Batch capacity 未达到：
    不得无限等待
```

---

# 第十一章 S1 准出标准

S1 只有满足以下条件才允许进入 Stable DMG：

```text
✅ batch=2/4 实机运行
✅ distinct prompt isolation
✅ per-sequence cancellation
✅ batch token accounting
✅ batch KV isolation
✅ no Logical State contamination
✅ no KV Ledger violation
✅ no Lifecycle regression
✅ baseline throughput > interleaved baseline
✅ single-request latency regression within accepted bound
```

性能方面：

```text
Current baseline ≈ 43 tok/s aggregate

Minimum:
    > 43

Target:
    ≥ 50

Strong result:
    ≥ 60
```

当前 batch=4 prototype 的 75.1 tok/s 已经证明目标具备现实性，但正式 Runtime 必须重新测量，因为接入 SimiGo scheduler、stream、KV 管理后会产生额外开销。

---

# 第十二章 S2 —— Paged / Block KV

S1 稳定后，才进入 KV 架构下一阶段。

当前：

```text
PhysicalKVRevision
    ↓
one complete KVCache
```

S2 逐步演化成：

```text
PhysicalKVRevision
    ↓
KV Region / Block references
    ↓
Block Pool
```

目标：

```text
shared prefix
copy-on-write
partial eviction
memory locality
batch-friendly cache
```

---

# 第十三章 S2 KV Block 模型

未来：

```text
KVBlock
    blockId
    tokenRange
    bytes
    resident
    refCount
    lastActive
```

Revision：

```text
Revision
    physicalTokens
    blocks[]
    logicalLength
    owner
    toolFingerprint
```

于是：

```text
Revision A
    [1][2][3][4]

Revision B
    [1][2][3][8]

Revision C
    [1][2][9]
```

共享：

```text
[1][2]
```

不再复制整份 KV。

---

# 第十四章 S2：Prefix Tree / Radix Cache

当前 Revision 数量较少时继续使用 Array。

当进入：

```text
多 Agent
多 Session
高 Revision 数
长上下文
```

再演进为：

```text
Prefix Tree
/
Radix Cache
```

逻辑：

```text
Token Prefix
     ↓
Radix Tree
     ↓
Longest Cached Prefix
     ↓
Block references
```

这一步借鉴 SGLang 的 Radix Cache 思路，但不复制其 Python/CUDA 实现。

SimiGo 只吸收其：

```text
prefix tree
reference
eviction
reuse
```

几个核心思想。

---

# 第十五章 S2 Admission 演进

当前：

```text
estimatedKVBytesPerToken
+
executionWorkingSet
+
safetyMargin
```

仍保留。

S2 开始允许：

```text
Block-level accounting
```

最终：

```text
Admission
    ↓
how many blocks
    ↓
which blocks can be evicted
    ↓
which blocks can remain shared
```

而不是：

```text
Revision-level whole-cache eviction
```

这会显著提高：

```text
memory utilization
+
multi-agent reuse
```

---

# 第十六章 S3 —— Continuous Serving

S3 才允许进入：

```text
Continuous Batching
```

此时执行队列成为：

```text
Running Batch
    ├── A
    ├── B
    ├── C
    └── D

Waiting
    ├── E
    ├── F
    └── G
```

每个 decode quantum：

```text
remove finished
remove cancelled
insert waiting
run next batch
```

这才是真正意义上的 Continuous Batching。

---

# 第十七章 S3 Batch Scheduler 最终形态

最终 Scheduler：

```text
                  Requests
                     │
                     ▼
             Capability Match
                     │
                     ▼
             Logical Isolation
                     │
                     ▼
             KV Block Admission
                     │
                     ▼
             Latency Arbitration
                     │
                     ▼
            Batch Formation
                     │
                     ▼
             Decode Quantum
                     │
          ┌──────────┼──────────┐
          ▼          ▼          ▼
        done       cancel      continue
          │          │          │
          └──────────┴──────────┘
                     │
                     ▼
               next quantum
```

这才是最终 Execution Runtime。

---

# 第十八章 S3 与 Speculative Decode

S3 稳定以后再增加：

```text
Speculative Decode
```

体系：

```text
Target Model
     ↑
accepted tokens

Draft Model
     ↓
candidate tokens
```

要求：

```text
KV block compatible
cache trim safe
per-sequence state isolated
```

Speculative Decode 不进入 S1。

---

# 第十九章 Hybrid / Mamba 路线

Hybrid 模型继续执行：

```text
NO-GO
```

直到上游真正提供：

```text
batched recurrent-state semantics
+
per-sequence state
+
correct position handling
```

当前 Hybrid 模型中的：

```text
MambaCache
```

不能因为 Standard-KV Batch 成功而被强行 Batch 化。

原则：

> **无法证明 State Semantics，就不做 Batch。**

因此：

```text
Standard-KV
    → Batch

Hybrid Mamba
    → Interleaved / Single

未来上游支持后
    → Re-open capability gate
```

---

# 第二十章 对优秀开源实现的借鉴边界

## mlx-lm

主要借鉴：

```text
BatchGenerator
BatchKVCache
cache merge
cache extend
batch generation
```

定位：

> Model/Cache 层参考实现。

---

## llama.cpp

主要借鉴：

```text
seq_id
parallel execution
llama_batch
sequence memory operations
continuous batching
```

定位：

> Execution Plane 参考实现。

---

## vLLM

主要借鉴：

```text
Scheduler
KVCacheManager
BlockPool
KV blocks
token budget
admission
```

定位：

> Resource/KV Plane 参考实现。

---

## SGLang

主要借鉴：

```text
Radix Cache
prefix tree
prefix reuse
reference management
```

定位：

> Future Prefix Cache 参考实现。

---

# 第二十一章 明确“不照搬”

SimiGo 不复制：

```text
vLLM CUDA kernel architecture
SGLang Python runtime architecture
llama.cpp complete C++ memory architecture
```

因为 SimiGo 的约束完全不同：

```text
Apple Silicon
MLX
Swift
macOS
Local/LAN
Agent-oriented execution
Native menu-bar application
```

SimiGo 的竞争优势不是“CUDA GPU 上再实现一次成熟方案”。

而是：

> **把成熟 Serving Runtime 的调度思想，重新映射到 Apple Silicon + MLX + Swift。**

---

# 第二十二章 稳定 DMG 发布纪律

每个 Evolution Stage 都必须产生稳定发行物。

标准：

```text
Development Branch
        ↓
Unit Test
        ↓
Integration Test
        ↓
Real Hardware Benchmark
        ↓
Invariant Audit
        ↓
Stress Test
        ↓
DMG Build
        ↓
Smoke Test
        ↓
Release
```

版本策略建议：

```text
v1.1.x
    Stable Foundation maintenance

v1.2.x
    S1 Controlled Batch

v1.3.x
    S1 Arbitration / Ragged

v1.4.x
    S2 Block KV

v1.5.x
    S2 Prefix Tree

v1.6.x
    S3 Continuous Serving

v1.7.x
    Speculative Decode
```

版本号只是发布版本。

架构身份仍保持：

```text
v4.5 Stable Foundation
+
Evolution Capability Track
```

因此无需重新制造：

```text
v4.6
v4.7
v4.8
```

作为新的基础架构。

---

# 第二十三章 “Stable DMG” 的准入红线

任何阶段出现以下任一项：

```text
KV Ledger mismatch
Logical State contamination
Lifecycle leak
Cancellation leak
Admission bypass
Tool Protocol regression
Batch sequence contamination
```

立即：

```text
NO RELEASE
```

即使性能提升：

```text
2×
5×
10×
```

也不得进入 Stable DMG。

---

# 第二十四章 每阶段必须保存的证据

每个稳定版本必须同时保存：

```text
Git Commit SHA
Benchmark Result
Hardware Model
Memory Size
OS Version
MLX Version
mlx-swift-lm Version
Test Count
Failure Count
Skipped Count
Trace Sample
Release DMG
```

形成：

```text
Commit
   ↓
Evidence
   ↓
DMG
```

的可追溯链。

---

# 第二十五章 当前下一阶段正式任务

现在不是继续进行“大范围架构改造”。

S1 的第一提交只做：

```text
1. InferenceModelCapabilities
2. BatchSequence
3. BatchedDecodeScheduler skeleton
4. Distinct Prompt prototype
5. Single-vs-Batch isolation contract
```

禁止在这一提交加入：

```text
Paged KV
Radix Tree
Continuous Batching
Speculative Decode
Hybrid Batch
```

然后实机：

```text
Qwen3-Coder-30B-A3B
batch=2
batch=4
```

验证：

```text
correctness
isolation
cancellation
throughput
latency
memory
```

通过以后，才允许进入 S1.2。

---

# 第二十六章 最终架构愿景

```text
                        ┌──────────────────────┐
                        │    OpenAI Protocol   │
                        └──────────┬───────────┘
                                   │
                        ┌──────────▼───────────┐
                        │    Logical Plane      │
                        │ Agent / Session /     │
                        │ Branch / Request     │
                        └──────────┬───────────┘
                                   │
                        ┌──────────▼───────────┐
                        │    Execution Plane    │
                        │                      │
                        │ Gate                 │
                        │ Prefill Scheduler    │
                        │ Batch Scheduler      │
                        │ Arbitration          │
                        │ Cancellation         │
                        └──────────┬───────────┘
                                   │
                        ┌──────────▼───────────┐
                        │ Capability Layer      │
                        │                      │
                        │ Batch                │
                        │ RoPE                 │
                        │ KV                   │
                        │ Recurrent            │
                        │ Speculative          │
                        └──────────┬───────────┘
                                   │
                        ┌──────────▼───────────┐
                        │ Physical KV Engine    │
                        │                      │
                        │ Revision             │
                        │ Block Pool           │
                        │ Prefix Tree          │
                        │ Admission            │
                        │ COW                  │
                        └──────────┬───────────┘
                                   │
                        ┌──────────▼───────────┐
                        │      MLX Runtime      │
                        │ Qwen / Gemma / ...   │
                        └──────────────────────┘
```

最终原则只有一句：

> **Logical Identity 永远属于 Request；Execution Batch 永远属于 Scheduler；Physical KV 永远属于 Compute Result。三者可以协作，但永远不能互相冒充。**