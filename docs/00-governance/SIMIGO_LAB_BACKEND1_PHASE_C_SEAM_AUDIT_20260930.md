# BACKEND-1 Phase C Seam Audit — Backend-Neutral Execution Seam

日期：2026-09-30  
状态：`PHASE_C_SEAM_AUDIT_COMPLETE / AWAITING_REVIEW`  
Audited HEAD：`ebe4aec`（clean detached-HEAD worktree）  
范围：registered Phase C opening C1–C8  
性质：`architecture seam audit only`

本文不实现 Llama adapter，不选存储，不定义 persistence format，不做
performance benchmark claim，不设计 API/协议签名。所有结论区分：

```text
observed code fact ≠ inferred seam contract ≠ selected implementation
```

## 1. Evidence basis

审计基于 `ebe4aec` 的 clean detached-HEAD worktree。主工作区存在与本审计
无关的未提交 Swift 源码改动，未混入验证。

Targeted tests：

```text
SimiGoRuntimeContractTests bundle: 19 / 19 PASS
  ExecutionContinuityContractTests      6
  ExecutionContinuityLifecycleTreeTests 9
  RuntimeBackendContractTests           4
SimiGo2ExperimentalTests（selected）:   42 / 42 PASS
  BackendConformanceMatrixTests         3（三 adapter 同一 battery）
  ExecutionContinuityCoordinatorTests   8
  ExecutionStatePrefixPoolTests        10
  PrefixSnapshotStoreTests              7
  MaterializationCoordinatorTests       3
  OversizedBackendAtomicityTests        2
  PrefixPoolSessionLifecycleTests       4
  Fork3StructuralBattery                5
Total:                                  61 / 61 PASS
```

Evidence artifact：
`simigo2-experimental/results/backend-conformance/backend1-phase-c-seam-audit-tests-20260930.json`
（含 raw log）。与 Phase B 一样，这是 targeted structural evidence，不是
end-to-end durability proof。

## 2. C1 — MLX-specific leakage

### 2.1 Package-level containment（observed）

```text
SimiGoRuntimeContract  = 无任何 dependency（Package.swift:30-32）；
                         3 个文件仅 import Foundation
SimiGo2App             = 仅依赖 SimiGo2Experimental（Package.swift:57-60）；
                         imports = Darwin/Foundation/SimiGo2Experimental/
                         SwiftUI（SimiGo2App.swift:1-4），无 MLX import
SimiGo2Experimental    = 依赖 SimiGoRuntimeContract + MLX/MLXLMCommon/MLXLLM/
                         MLXHuggingFace/Tokenizers/MLXNN（Package.swift:33-44）
```

### 2.2 Semantic-layer zero-MLX（observed）

以下 D 级语义层文件全部零 MLX import（逐文件核对）：

```text
ExecutionContinuityCoordinator.swift   仅 Foundation + SimiGoRuntimeContract
ExecutionBindingRegistry.swift         仅 Foundation（文件头自述 Zero-MLX :5）
ExecutionStatePrefixPool.swift         仅 Foundation（自述 ZERO-MLX :12-14）
MLXExecutionStateBackend.swift         仅 Foundation + SimiGoRuntimeContract
LLAMAServerExecutionStateBackend.swift 仅 Foundation + SimiGoRuntimeContract
ModelInventoryReference.swift          仅 Foundation
NamedSourceConformanceProfile.swift    仅 Foundation
```

三个 `ExecutionRepresentationPayload` 实现均为 MLX-free（`[Int]` token
prefix）：`MLXPrefixPayload`（MLXExecutionStateBackend.swift:15-21）、
`LLAMAServerPrefixPayload`（LLAMAServerExecutionStateBackend.swift:10-16）、
`OversizedPrefixPayload`（O6ExecutionStateOversized.swift:31-36）。

### 2.3 MLX 类型的实际驻留面（observed）

`import MLX*` 命中 SimiGo2Experimental 内 32 个文件（代表性：
OversizedSegmentedEngine.swift:2-5、O6ExecutionStateOversized.swift:2-5、
E5ExecutionStateScenario.swift:2-5、MLXResidencyBackend.swift:2-3、
Instrumentation/*:2-6、O2–O4 probe 系、CrossBackend* probe 系）。分类：

| 层 | MLX 驻留 | 穿透方式 |
|---|---|---|
| D 语义层（contract/coordinator/registry/pool） | 无 | — |
| E3 payload | 无（`[Int]`） | — |
| P 物理操作 | O6SegmentedCore（MLXArray/model.update/Memory.clearCache，O6ExecutionStateOversized.swift:134-238） | 经注入 `releaseAll` 闭包进入 backend（:348/:589） |
| P 物化/内存 | MLXResidencyBackend 持 `ModelContainer`（MLXResidencyBackend.swift:17） | 经 `ResidencyMaterializer` 面（:6-9 自述 Controller never sees MLX） |
| P 持久化 | **PrefixSnapshotStore.swift:2 import MLXLMCommon** | 见 2.4 |
| harness/probe | 32 文件 | 实验线，非产品路径 |

### 2.4 Leakage 清单（inferred，供 review 裁定）

```text
L-1  PrefixSnapshotStore 公开 API 返回 MLXLMCommon 类型 PromptCacheSnapshot
     （PrefixSnapshotStore.swift:2、:155、:185、:203-205、:226）——
     P 层持久化组件把 MLX 家族类型带出公共边界；E3 侧 payload 是 opaque 的，
     该 store 不是。唯一的跨组件 MLX 类型渗漏点。
     非 blocker：store 在 Sources/ 内无实例化点，接线在产品仓（B-2 sidecar，
     ChatSession.saveCache/loadCache 经注入闭包，PrefixSnapshotStore.swift:8/:48）。
L-2  其余 MLX 驻留全部在 P/harness 层，被 E3/B1 两个 seam 面封住（见 C2），
     不构成语义渗漏。
```

### 2.5 09-28 opening scope 的 Lab 对应（observed）

```text
ChatSession        = 产品仓类型；Lab 内 MLXParameterSwapGate.swift:66 实例化
                     （probe 专用），PrefixSnapshotStore/Pool 注释引用其接线
NativeMLX          = Lab Sources/ 内零命中
NativeMLXPrefixPool→ ExecutionStatePrefixPool.swift
OversizedRuntime   → OversizedSegmentedEngine.swift
session persistence→ Lab 侧无磁盘会话持久化（SimiGo2App 无任何写盘；
                     transcript 仅 UI 展示层，SimiGo2App.swift:211-215 自述
                     "never a source for Execution State restore/replay"）
HTTP/OpenAI 入口   = Lab 无监听型 server；网络边界唯一方向是 Swift HTTP
                     客户端 → 外部 llama-server（默认 127.0.0.1:18080，
                     LLAMAServerExecutionStateForkRestore.swift:57-69）；
                     /v1/chat/completions 仅作为 CLIENT 用于 cancellation
                     harness（LLAMAServerExecutionStateCancellation.swift:343-361）
```

Session persistence 读法（按 review strengthening #1）：可执行历史 =
coordinator + bound prefix（OversizedSegmentedEngine.swift:123/:807-816），
符合 snapshot-closure 视角；Lab 内不存在 transcript-derived recovery 路径。

## 3. C2 — Minimal backend seam

### 3.1 已存在的 seam（observed）

seam 不是提案，是已运行的结构——三个零 MLX 契约组成两个接缝面：

```text
E1  ExecutionContinuityRuntime（ExecutionContinuityContract.swift:133-165）
    create / attach / continueExecution / fork / restore / reattach / discard
    —— 语义生命周期，Runtime 独占

E3  ExecutionStateBackend（ExecutionStateBackendContract.swift:48-72）
    captureRepresentation / deriveRepresentation / restoreRepresentation /
    releaseRepresentation + opaque ExecutionRepresentationPayload（:18）
    + 三类契约错误（noBoundRepresentation / representationPositionMismatch /
    foreignRepresentationPayload，:38-46）
    —— representation 策略，Backend 独占

B1  RuntimeResidencyBackend（RuntimeBackendContract.swift:57-67）
    materialize / release + memoryObservation / purgeTransientCaches
    —— 物化与内存对账面（INV-3），Controller 只依赖 ResidencyMaterializer

host-side 胶水：coordinator.bindRepresentation（host 在每轮生成后驱动绑定，
ExecutionContinuityCoordinator.swift:98-113）；executor consumeBinding →
返回 advanced payload → host 重绑（O6ExecutionStateOversized.swift:538/:546、
MLXExecutionStateBackend.swift:64-70）。
```

### 3.2 Sovereignty 验证（observed）

`ExecutionStateHandle` 全 `let` 字段（ExecutionContinuityContract.swift:70-75），
不存在 backend 改写 id/lineage/position/continuation 的代码路径：四个
ExecutionStateBackend 实现都只读 `state.id`/`state.position`，只写自己的私有
字典（MLX :30-31；LLAMA :20-21；oversized :344-345）。三个 prefix mismatch
错误全部 throw（MLX :54-60/:89-95；LLAMA :40-46/:65-71；oversized
:369-372/:395-398/:412-415）。唯一形状例外见 §8 gap G-1。

### 3.3 最小 seam 推断（inferred，非 API 设计）

一个 backend 要进入该契约，必须提供且只需提供：

```text
1. capture：在 bound position 给出当前物理 representation（位置不符必须 throw）
2. derive：在 fork 点从 parent 物理派生 child（失败则 child 不 commit）
3. restore：使 backend 物理状态匹配某 representation（完成后 bound position
   == representation position）
4. release：释放 representation（stale snapshot 不得清掉 live binding）
payload 对 Runtime opaque；identity/lineage/position/continuation/lifecycle
与 commit ordering 全部归 Runtime。
```

三个异构 backend（MLX prefix-recompute / 外部 llama-server / oversized 分段）
在互不改语义断言的前提下通过同一 battery（BackendConformanceMatrixTests
3/3），是该 seam 最小性的行为证据。

## 4. C3 — Capability requirements

Observed 能力差异（同一契约下三种策略）：

| Capability | MLX prefix | LLAMA-server | Oversized segmented |
|---|---|---|---|
| capture/derive/restore 物理动作 | 内存字典 | 内存字典；计算与 native cache 归外部 llama-server | 内存字典；release 触发真实权重驱逐 |
| release 物理效应 | 字典清理（:118-129） | 字典清理（:94-105，`releaseIfCurrent`） | `releaseAll` → `model.update` 零尺寸占位 + `Memory.clearCache()`（O6:215-223/:461） |
| 内存对账 | — | — | `RuntimeResidencyBackend`（memoryObservation 映射 `Memory.snapshot()`，MLXResidencyBackend.swift:40-47） |

Inferred：capability 表达为 R/T 层策略差异 + 显式降级结果，不进 D：
(1) restore 是否可行由「目标位置是否存在已捕获 representation」门控
（coordinator `noRepresentationAtPosition`，:214-221，fail closed）；
(2) release 是否有物理效应由 backend 策略决定，契约只要求 stale 安全；
(3) 能力缺失的语义结果 = `rematerializationRequired` / recompute——
`ResolutionState.classify`（ExecutionBindingRegistry.swift:213-220）给出
unbound / attachedLive / reattachable / rematerializationRequired 的结构化
四态分类。无任何 capability 字段进入 `ExecutionStateHandle`。

## 5. C4 — Representation contract

Observed：durable relation 形状与 Phase B 登记逐字段吻合：

```text
RepresentationRef（ExecutionBindingRegistry.swift:20-58）
  kind / modelIdentity / kvLayoutIdentity / renderIdentity /
  contentHash(UInt64 chain hash) / boundLength / backendIdentity(默认 "mlx")
ExecutionRepresentationBinding（:68-78）
  executionID / runtimeAddress / ref / boundPositionAtBind(==ref.boundLength)
  / generation(per-execution monotonic) / state(active|superseded|detached)
  / boundAt
ResolutionState 四态分类（:205-221）；forkChildBinding 结构化 N=2（:185-199）
```

内容主张（condition 3）现状：E3 payload 本身无 content digest（Phase B gap
#6 仍在）；内容主张存在于 pool 路径——`PrefixSnapshotSidecar{version,
modelID, kvFingerprint, tokenCount, chainHash}`（PrefixSnapshotStore.swift:38-45）
+ FNV `PrefixChain` 滚动哈希（ExecutionStatePrefixPool.swift:80-103）+ 绑定前
对账 P-I1（mismatch → remove entry + throw，PrefixSnapshotStore.swift:203-227）
+ `RepresentationRef.contentHash`。Inferred：durable reattachment 的内容主张
当前是 per-path（pool/sidecar）而非 universal；跨 backend durable reattach
仍需 per-backend content claim + validation policy 才可登记。

Observed gap（Phase B gap #9 仍在）：registry 注释自述 append-only，但
supersede/detach 以 `rows[index] = …` 原地改状态（:158、:174）——按 Phase B
裁定仅可作为 runtime relation 行为，不得读作 durable event log。

## 6. C5 — Synchronous / asynchronous boundary

Observed commit ordering（与 Phase B B6 登记一致，clean HEAD 复核）：

```text
fork:    物理 derive 先行 → child 语义 commit（:169-203；derive 失败 →
         parent 不变、child 未 commit、无部分 representation history）
restore: backend.restoreRepresentation 先行 → logical restored commit
         （:222-231）
discard: 物理 release 先行 → discarded tombstone commit（:258-270；release
         失败 → 逻辑状态不变，可重试；OversizedBackendAtomicityTests 2/2）
bind:    backend.restoreRepresentation → representation history append
         （:111-112）
```

Inferred：四个语义 commit 窗口内，semantic commit 与 physical outcome 的
先后是同步因果；一切物理 I/O（文件 export、HTTP、权重 load/evict）在 seam
后异步进行。契约明确不强迫实现阻塞线程（RuntimeBackendContract.swift:39-42
「MUST NOT force implementations to block threads」；B1 物化 transfer 在
契约层原子：要么返回要么 throw 且该 group 状态不变，:43-50）。seam 侧允许
async 的环节 = capture 之后的 executor 生成、representation export、
物理 materialize/release 本身。

## 7. C6 — Cancellation / failure propagation / resource release

Observed failure mapping（全部 loud、fail closed）：

```text
backend →  noBoundRepresentation / representationPositionMismatch /
           foreignRepresentationPayload（三 adapter 实测 throw）
runtime →  duplicateExecution / unknownExecution / discardedExecution
           （guardKnown 对 discarded 拒绝，:84-86）/
           noRepresentationAtPosition
release →  stale snapshot 释放 = no-op，不得清掉 live binding（FBC-001 修复
           在三 adapter 一致：MLX :124-126、LLAMA :98-105、oversized :457-460）
```

Cancellation（observed，seam 侧分类）：

```text
契约面：E1/E3 无 cancellation 操作——cancellation 不是契约级语义。
LLAMA 侧：harness 级——HTTP DELETE /v1/stream + URLSessionDataTask.cancel()
          （LLAMAServerExecutionStateCancellation.swift:95-109/:363-371）+
          /slots 轮询等空闲（:373-383）；llama-server 进程生命周期完全外部
          （全仓唯一 Process() = sysctl 内存探测，CrossBackendTokenProbe.swift:122-124）
MLX 侧：  token 边界 cooperative cancellation 为已登记 O6 W9 先证；
          本审计不重跑
```

Resource release：in-flight 保护 = `PhysicalUseRegistry` 延迟删除
（PrefixSnapshotStore.swift:78-95）+ `MaterializationCoordinator` 单飞/驱逐
延迟（tests 3/3）；oversized release 顺序 = foreign guard → stale no-op →
可失败物理释放 → 绑定清理（:452-467），失败可重试。

## 8. Registered gaps（审计产出，非新授权）

```text
G-1  OversizedSegmentedStateBackend.deriveRepresentation 不校验
     parent/child position 相等（O6:421-431），MLX/LLAMA adapter 均校验。
     当前被 coordinator fork 前置检查（:177）遮蔽；直连 backend 调用可绕过。
     fail-closed 政策下应补 guard——留给后续 engineering gate，不在本审计改码。
G-2  coordinator 无内部锁（@unchecked Sendable + 明文 var 字典，:12/:47-52）
     ——condition 6 engineering gate。
G-3  attach() 接受任意 supplied handle，不独立验证 lineage closure（:137-144）
G-4  bindRepresentation 只查存在性，不查 lifecycle≠discarded（:103-105）
G-5  PrefixSnapshotStore 公开 API 渗漏 MLXLMCommon 类型（L-1）
G-6  E3 payload 无 universal content digest；内容主张仅 pool/sidecar 路径
G-7  ExecutionID 为 opaque caller-supplied String，无 durable allocator/
     跨重启 reservation（contract :8-14）——condition 6
G-8  BindingRegistry supersede/detach 原地改行（:158/:174）——Phase B gap #9 仍在
G-9  契约无 cancellation 面（harness/executor 级先证，语义化待独立 gate）
G-10 Lab 无 durable Execution State store（Phase B gap #1 仍在）；session
     无磁盘持久化
```

## 9. C7 — Default-path non-interference（结构性）

Observed：Lab app 的默认聊天路径就是 Execution State 路径——
`ChatAppModel` 持 `OversizedSegmentedEngine`（SimiGo2App.swift:91），engine
内部构造 `ExecutionContinuityCoordinator(backend: OversizedSegmentedStateBackend)`
（OversizedSegmentedEngine.swift:807-816）；SimiGo2App 无 MLX import、无第二
runtime、无并行非 ES 聊天实现。E5 默认路径以 `MLXExecutionStateBackend` +
`MLXPrefixRecomputeExecutor` 运行（E5ExecutionStateScenario.swift:89）。

Inferred：seam 不强制改动稳定 MLX 路径——MLX 完全被封在
MLXExecutionStateBackend / O6SegmentedCore / MLXResidencyBackend 之后；语义层
（coordinator/registry/pool/contract）零 MLX 改动即可接入异构 backend
（三 adapter 同 battery 是行为证据）。bookkeeping 是否塞进默认路径的结构
答案：绑定驱动是 host 侧显式步骤（bind/consumeBinding），不是 MLX 执行路径
内的隐式分支。测量问题（快慢）归 RQ3，本审计不答。

## 10. C8 — Cross-backend semantic continuity（目标验证问题）

契约支持性结论（targeted evidence 边界内）：

```text
1. identity/lineage/position/continuation/lifecycle 由零 MLX contract target
   承载（Package.swift:30-32），Handle 全 let，backend 无写路径（§3.2）——
   语义连续性不依赖 backend 类型体系，by construction。
2. 同一 conformance battery 接入三个异构 backend 不改语义断言
   （BackendConformanceMatrixTests 3/3；RQ1 先证 + 本次复跑）。
3. backend 变化时 representation 侧结果显式化：reattach / 
   rematerializationRequired / recompute（ResolutionState 四态 + 
   noRepresentationAtPosition fail closed），无静默换语义。
4. restore/fork/discard 的事务序与 backend 无关，由 coordinator 固定（§6）。
```

Inferred boundary（不升级为 universal）：

```text
✔ 契约支持跨 backend 语义连续（在已测 MLX prefix / oversized segmented /
  LLAMA-server prefix 条件下）
✘ 不证明跨 backend artifact 可移植（payload 按 backend 类型化 by design；
  oversized/MLX artifact 不能被 llama 加载——连续性在语义层 + prefix
  recompute，不在 artifact 格式）
✘ 不证明 production-readiness / universal Execution State
✘ 不构成 performance claim
```

## 11. Gate consequence

Phase C supports this narrow answer:

```text
最小 backend seam 已存在并被三个异构 backend 行为验证：
E1（语义生命周期，Runtime 独占）+ E3（representation 策略，Backend 独占，
payload opaque）+ B1（物化/内存对账面）。MLX 语义渗漏为零；唯一跨组件
类型渗漏点在 PrefixSnapshotStore 公开 API（L-1/G-5）。跨 backend 语义
连续在契约层成立，representation 侧显式降级，无静默换语义。
```

This does not establish:

```text
一个 adapter 实现 / 产品化路径
一个存储引擎 / schema / 序列化格式
跨 backend artifact 格式
并发协议 / durable identity allocator（condition 6）
任何 performance 结论
```

Next required action is external review of this Phase C seam audit.
