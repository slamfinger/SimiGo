# Phase A — Execution State Semantic Inventory and Persistence / Representation Boundary Audit

日期：2026-09-29  
状态：`PHASE_A_CODE_AUDIT_COMPLETE / AWAITING_REVIEW`  
范围：`simigo2-experimental` 当前 Git 树  
性质：`code audit / synthesis only`

本文不是存储选型，不是 Palace database 设计，也不是 Llama adapter 授权。
所有结论遵守：

```text
observed code fact ≠ inferred minimal contract ≠ selected implementation
```

## 1. Evidence basis

主要源码事实来自：

```text
Sources/SimiGoRuntimeContract/ExecutionContinuityContract.swift
Sources/SimiGoRuntimeContract/ExecutionStateBackendContract.swift
Sources/SimiGo2Experimental/ExecutionContinuityCoordinator.swift
Sources/SimiGo2Experimental/ExecutionBindingRegistry.swift
Sources/SimiGo2Experimental/ExecutionStatePrefixPool.swift
Sources/SimiGo2Experimental/PrefixSnapshotStore.swift
Sources/SimiGo2Experimental/MaterializationCoordinator.swift
Sources/SimiGo2Experimental/MLXExecutionStateBackend.swift
Sources/SimiGo2Experimental/O6ExecutionStateOversized.swift
Sources/SimiGo2Experimental/LLAMAServerExecutionStateBackend.swift
```

机器检查证据：

```text
swift test --filter 'ExecutionContinuityContractTests|ExecutionContinuityLifecycleTreeTests|ExecutionContinuityCoordinatorTests|ExecutionStatePrefixPoolTests|PrefixSnapshotStoreTests|MaterializationCoordinatorTests|OversizedBackendAtomicityTests'

SimiGoRuntimeContractTests bundle: 15 / 15 PASS
SimiGo2ExperimentalTests bundle:   30 / 30 PASS
Total:                             45 / 45 PASS
```

summary artifact:

`simigo2-experimental/results/backend-conformance/execution-state-phase-a-boundary-audit-tests-20260929.json`

## 2. Semantic inventory

| Object | Observed carrier | Current class | Minimal-contract disposition |
|---|---|---|---|
| `ExecutionID` | opaque `rawValue: String` | D if persisted; today process-local | Execution identity |
| `ExecutionLineage` | `root` + optional `parent` | D if persisted; today process-local | Branch lineage minimum |
| `ExecutionPosition` | `Int64` in handle | D if persisted; today process-local | Canonical logical position |
| `ExecutionContinuation` | `nextInput` + `continuationID` | D if persisted; today process-local | Continuation semantics |
| `ExecutionBranchLifecycle` | `attached/active/restored/discarded` | D if persisted; today process-local | Lifecycle semantic state |
| `ExecutionStateHandle` | aggregate of the five fields above | D aggregate | The minimal D candidate |
| Coordinator handles | `handles: [ExecutionID: ExecutionStateHandle]` | R | Process-local materialization of D |
| Coordinator lifecycle records | append-like in-memory `records` + `sequence` | O / History | Useful for replay/audit, not minimum D |
| Representation history | `[ExecutionID: [ExecutionRepresentation]]` | R relation + P payloads | Restore accelerator/history, not D |
| `ExecutionRepresentation` | executionID + position + opaque payload | P | Physical representation envelope |
| `MLXPrefixPayload` / LLAMA / oversized prefix payloads | token array | P | Backend-specific or representation-strategy payload |
| Backend prefix/bound-position maps | dictionaries guarded by backend locks | R + P | Current physical binding |
| `RepresentationRef` | kind, model/KV/render identity, contentHash, boundLength, backendIdentity | P locator/claim | No execution identity inside |
| `ExecutionRepresentationBinding` | executionID, runtimeAddress, ref, generation, state, boundAt | R relation + P locator + O history | Durable binding would be a separate relation record |
| Prefix pool entry | namespace, tokenCount, boundaryHash, artifact handle | P claim + artifact locator | Representation layer, not Execution State |
| Disk snapshot + sidecar | safetensors payload + JSON claims | P | Artifact persistence and reconciliation |
| Prefix pool stats / recency tick | hits, misses, evictions, `lastUse`, `tick` | O + T | Policy/observability, not semantic recovery state |
| `PhysicalUseRegistry` | use counts + pending deletes | T | In-flight physical-use protection |
| Materialization in-flight map | `inFlight` tasks | T | Single-flight work state |
| Oversized token ledger | append-like entries / superseded markers | O | Reconciliation/history evidence |

Important negative facts:

- 本仓库源码中没有 `AgentExecutionKey` 类型；该概念只出现在历史治理文档中，不能作为本轮 observed identity fact。
- `ExecutionBindingRegistry` 显式以 `ExecutionID` 为 canonical key，且没有反向 Agent key index。
- `RepresentationRef` 不包含执行身份；`ExecutionBindingRegistry` 是 Execution 到 Representation 的关系层。
- Prefix pool 的 content identity 是 physical representation claim，不是 Execution position。

## 3. Boundary facts

### 3.1 Runtime owns logical semantics

`ExecutionContinuityContract.swift` 定义了 backend-neutral 的 `ExecutionID`、
`ExecutionLineage`、`ExecutionPosition`、`ExecutionContinuation`、lifecycle、
fork / restore 请求和 `ExecutionStateHandle`。文件注释明确 physical KV、
recurrent state 和 model-specific state 由 Backend 拥有。

`ExecutionStateBackendContract.swift` 进一步把 `ExecutionRepresentationPayload`
设为 opaque。Backend contract 明确 implementation 不得创建、分配或修改
Execution Identity、Lineage、Position semantics 或 Continuation。

### 3.2 Coordinator currently materializes semantics only in memory

`ExecutionContinuityCoordinator` 持有：

```text
handles
records
representationHistory
sequence
```

这些都没有注入 persistence sink，也没有自带 durable store。进程退出后，
当前 coordinator 的 Execution State、lifecycle history 和 representation
history 都不可恢复。

`continueExecution` 将 position 固定前进 `+1`；`fork` 采用 child 提供的
position；`restore` 采用 target position。因此 logical position 的权威来源是
coordinator 持有的 handle，不是 token 数，也不是 backend 的 prefix 长度。

### 3.3 Backend validates position/type, not generic content identity

MLX、LLAMA conformance 和 oversized backend 都用
`prefixes + boundPositions` 表达当前 physical binding，并在
`boundPrefix` / capture 中检查 backend bound position 与 logical handle
position 相等。

但 generic `ExecutionRepresentation` 只有 `(executionID, position, payload)`；
当前 generic backend contract 不要求 payload 内容 digest。`MLXPrefixPayload`
等只被类型检查。内容级 reconciliation 目前存在于 Prefix pool / disk sidecar
路径，而不是所有 backend 的公共必要条件。

### 3.4 Prefix representation has strong local reconciliation

`ExecutionStatePrefixPool.admit` 会重新计算 caller tokens 的 cumulative chain
hash，并且只在 hash 与 entry boundaryHash 相等时命中。`PrefixSnapshotStore.load`
会核对 sidecar 的 namespace、tokenCount、chainHash；不一致会移除 pool entry 并
loud throw。

这证明当前 Physical Representation 层已有 `prompt → entry → artifact` 的本地
一致性链。它仍然不是 Execution State durability：restart `rescan()` 只把 disk
claim 重新注册回 pool，不恢复 coordinator handles、lifecycle records 或
execution→representation bindings。

### 3.5 Transaction ordering is explicit at selected seams

Observed ordering：

```text
coordinator.fork:
  physical derive succeeds → logical child handle/record/history commit

coordinator.discard:
  current representation release succeeds → logical lifecycle becomes discarded

oversized release:
  foreign payload guard → current-binding check → physical releaseAll succeeds
  → recheck binding → drop prefix/bound-position
```

相应单元测试覆盖 failed release 不破坏 logical binding，以及 coordinator discard
传播 failed release 而不改变 state。

### 3.6 Physical artifact lifecycle is separate from Execution lifecycle

`PrefixSnapshotStore` 用 snapshot + sidecar 表达 artifact；export 先写 temp
snapshot，再 move 到 final path，再原子写 sidecar，最后注册 pool。`onEvict`
经 `PhysicalUseRegistry` 删除；in-flight use 会 defer deletion。
`MaterializationCoordinator` 对同一 ref key 做 single-flight，并包裹 acquire /
release。

这些属于 Representation availability / GC / concurrency boundary，不是 Execution
semantic evolution。

## 4. Answers to the Phase A questions

### Q1 — Execution Identity canonical source

Observed answer：canonical source is `ExecutionID.rawValue` as carried by
`ExecutionStateHandle.id`。Coordinator 的 `handles` dict 是当前权威 in-memory
lookup；`ExecutionBindingRegistry` 也以 executionID 为 canonical key。

Backend cannot redefine identity。目前 identity 由 caller 提供给
`create/attach/fork`，coordinator 只在 process 内拒绝 duplicate。没有 durable
identity allocation / collision registry。

### Q2 — Execution Position canonical source

Observed answer：canonical source is `ExecutionStateHandle.position` owned by the
coordinator。

`prefixes[tokenCount]`、`PrefixPoolEntry.tokenCount`、
`RepresentationRef.boundLength` 都是 physical boundary / representation claim。
它们可以约束 representation，但不得反向定义 logical position。当前二者没有
统一单位，也不应该统一。

### Q3 — Which Execution Evolution must be durable

Inferred minimal contract：每个非终止 Execution 需要一个可提交的 semantic
snapshot，等价于：

```swift
id
lineage.root
lineage.parent
position
continuation.nextInput
continuation.continuationID
lifecycle
```

`created / attached / continued / restored / reattached` 可以收敛为最新 semantic
snapshot；不需要为了恢复语义而持久化完整 event log。`fork` 必须留下 child 的
root/parent linkage，同时 parent snapshot 不变。若要禁止 identity 重用，需要把
`discarded` 作为 tombstone 保留到明确的生命周期策略允许 GC 为止。

完整 `LifecycleRecord` 是 replay / observability value，不是最小 D 闭包。

### Q4 — Is RepresentationRef Execution semantic state?

No。`RepresentationRef` 是 physical layer locator / claim：kind、model、KV
layout、render identity、contentHash、boundLength、backendIdentity。

Execution State 可以在 semantic 层独立于 RepresentationRef 存在。若未来
recovery 要直接 reattach artifact，应持久化单独的 binding/relation record，而不是
把 Ref 内联为 Execution State 的语义字段。`runtimeAddress`、generation、
boundAt 和 binding state 属于 relation/runtime metadata。

### Q5 — Should ExecutionBindingRegistry remain execution-scoped runtime state?

Observed answer：当前应当保持 execution-scoped runtime relation。

原因是：

1. registry 的 canonical key 是 executionID；
2. `runtimeAddress` 是 process/runtime addressing，不是 durable semantic identity；
3. Ref 是 physical locator，不是 Execution semantic state；
4. 当前 rows、lastGeneration 和 rows 的 active/superseded/detached 状态都在进程内；
5. restart 后 Prefix store 只恢复 representation claims，不恢复 bindings。

因此它当前是 R + P + O 的混合层，不是最小 D 闭包。若要做 durable reattach，需要
另立 minimal durable relation，而不是把整个 registry 原样提升为 Execution State。

### Q6 — Where is logical-vs-physical consistency bounded?

当前一致性边界有三级：

```text
D → R:
  ExecutionStateHandle.position must equal backend bound position
  before consume / capture。

D → P:
  generic backend 只强校验 payload type 和 representation position；
  不强校验 payload content digest。

P internal:
  Prefix pool + disk sidecar 强校验 namespace、tokenCount、chainHash，
  mismatch loud-fail 并移除 entry。
```

因此 generic Execution State 的 consistency statement 只能是
`logical position ↔ representation position`。Content correctness 在当前架构中
由具体 representation strategy 额外保证。这必须保留为 explicit layer boundary，
不得偷偷把所有 P 层内容校验提升为 D 层字段。

## 5. Minimal D closure

`observed minimum`：

```text
ExecutionStateHandle
```

`inferred durable minimum`：

```text
DurableExecutionRecord {
  id: ExecutionID
  root: ExecutionID
  parent: ExecutionID?
  position: ExecutionPosition
  continuation: ExecutionContinuation
  lifecycle: ExecutionBranchLifecycle
}
```

不属于 D minimum：

```text
lifecycle event log        = O / optional replay
RepresentationRef          = P locator / claim
execution→Ref binding      = separate relation
runtimeAddress             = R
generation                 = relation concurrency/version metadata
token prefix / KV snapshot = P
artifact sidecar           = P reconciliation metadata
prefix pool stats          = O
physical use count         = T
in-flight materialization  = T
```

## 6. Audit findings that Phase B must carry forward

1. 当前 Lab 没有持久化 Execution State；只有持久化 Prefix representation artifact。
2. Coordinator restore 依赖 in-memory representation history；进程重启后无法恢复。
3. `ExecutionBindingRegistry` 的 detached/superseded 转换是在原 row 上改写，不是
   strict append-only event log。不能把代码注释中的“append-only”直接读成存储设计。
4. `bindRepresentation` 只检查 execution 存在，不检查 lifecycle != discarded；这属于
   logical/physical seam 的现有 gap。
5. `ExecutionRepresentation` 没有通用 content identity；若 Phase B 要 durable
   reattach，必须在 P 层定义显式 content claim / digest 策略。
6. Snapshot + sidecar 的两文件写序能防止 exporter 失败污染 pool，但两个文件不是单一
   crash transaction。这里只登记 boundary，不选择存储方案。
7. Coordinator 自身没有 lock；backend / pool / registry 有各自锁。若未来持久化边界
   引入并发 mutation，需要显式事务/序列化策略。

## 7. Gate consequence

Phase A supports this narrow conclusion：

```text
The semantic D closure is the ExecutionStateHandle aggregate.
Representation, binding, history, stats, and in-flight work are separate layers.
```

它不证明：

```text
a Palace storage schema
a persistence format
a crash-consistent transaction protocol
a cross-backend durable artifact format
a Llama adapter
```

下一步必须先对本审计做 external review / human registration。若登记通过，再开启
Phase B 的 PALACE-1 minimal durable unit 问题；不得直接进入存储选型或 adapter
实现。
