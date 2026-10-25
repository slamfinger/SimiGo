# SimiGo-Lab Research Route Redefinition — 2026-09-29

状态：`ROUTE_REDEFINED / EXECUTION-STATE-CENTRIC / AUDIT-FIRST`

## Decision

本次调整不是新增一个并列实验线，而是对后续研究树重新分层。

核心研究问题收束为：

> **Execution State 能否从当前 MLX 实现与具体 Physical Representation 中抽象出来，成为可持久化、可恢复、可跨 Representation / Backend 演进的一等运行时状态？**

因此：

- Execution State Runtime correctness：`SEALED / BOUNDED CONSOLIDATION`
- Execution State Architecture Contract：`NEXT SYNTHESIS GATE`
- PALACE-1：`MAIN OPEN / AUDIT FIRST`
- BACKEND-1：`SECONDARY OPEN / DEPENDENT ON BOUNDARY`
- oversized：`FROZEN / ARCHITECTURE VALIDATION PAYLOAD`

## Why the route changes

已有 Runtime 证据已经覆盖 fork / restore / delete、cancellation、discard atomicity、checkpoint consistency、generation gate、digest / retry 等核心语义；Beta lifecycle audit 已达到 PASS / 0 blocker。因此继续扩大 Runtime correctness harness 的边际收益很低。

已有 oversized measured-execution 研究则给出 Layer/Group 分辨率下的终态负结果：

`RequiredExecutionSet = ALL decoder groups`

因此该分辨率没有可供 Predictor 利用的 execution locality。与此同时，Residency 与 Execution 已被证据分离；retention 的收益属于物理驻留与重物化之间的 trade-off，而不是 computation skipping。故 oversized 独立研究冻结，不再作为主问题扩张。

## New research tree

```
SimiGo-Lab
├── 0. Execution State Runtime
│      └── SEALED / BOUNDED CONSOLIDATION
│
├── 1. Execution State Architecture Contract
│      ├── identity
│      ├── position
│      ├── evolution
│      ├── persistence boundary
│      ├── representation boundary
│      ├── runtime binding
│      └── consistency boundary
│
├── 2. PALACE-1
│      ├── minimal durable unit
│      ├── transcript / lineage persistence
│      ├── RepresentationRef / artifact locator
│      ├── lifecycle / GC
│      └── crash / recovery
│
├── 3. BACKEND-1
│      ├── MLX semantic leakage
│      ├── backend seam
│      ├── capability
│      ├── Representation contract
│      └── cancellation / failure / release
│
└── 4. Validation Payloads
       ├── ordinary model
       ├── oversized model
       ├── large artifact
       ├── long transcript
       └── LAN / remote
```

## Dependency rule

PALACE-1 和 BACKEND-1 不再视为两个完全并列、可立即实现的路线。

依赖关系：

```
Execution State semantic contract
          ↓
Persistence / Representation boundary
          ↓
PALACE durable-state model
          ↓
Backend capability / seam
          ↓
cross-backend validation
```

因此不得在 persistence / representation boundary 未审清前直接实现 Llama adapter，也不得在 minimal durable unit 未确定前进行 SQLite / KV / remote 选型。

## Phase A — Execution State Architecture Contract

目标不是重新发明 Execution State，而是从已经验证的 Runtime 代码中提炼最小架构契约。

首轮只做 code audit / synthesis，不写生产实现。

每个状态触点分类为：

- `D` = Durable Semantic State
- `R` = Runtime Binding
- `P` = Physical Representation
- `O` = Observability / History
- `T` = Transient / Reconstructable

必须回答：

1. Execution Identity 的 canonical source 是什么？
2. Execution Position 的 canonical source 是什么？
3. 哪些 Execution Evolution 必须 durable？
4. RepresentationRef 属于 Execution semantic state 还是 physical layer reference？
5. ExecutionBindingRegistry 为什么/是否保持 execution-scoped runtime state？
6. logical state 与 physical representation 的一致性边界在哪里？

输出必须严格区分：

`observed code fact ≠ inferred storage design ≠ selected implementation`

## Phase B — PALACE-1

只有在 Phase A 得到边界后，才研究：

- minimal durable unit
- transcript representation
- fork point / lineage
- RepresentationRef
- artifact locator
- checkpoint / recovery
- delete / GC
- shared representation
- crash consistency

Storage technology（SQLite、embedded KV、event log、remote service 等）暂时只是 candidate implementation space，不是独立研究问题。

## Phase C — BACKEND-1

在 Execution/Representation boundary 明确后审计：

- MLX-specific leakage
- minimal backend seam
- capability requirements
- Representation contract
- synchronous/asynchronous boundary
- cancellation
- failure propagation
- resource release

目标不是“接入 llama.cpp”本身，而是验证：

> Execution State 是否可以在 backend / representation 变化后保持语义连续。

Llama 是验证 backend，不是新的 Execution State 定义。

## Validation policy

普通模型负责证明默认路径。

oversized、large artifact、long transcript、memory pressure、LAN/remote 等只作为同一架构机制的边界载荷。

禁止：

- standalone oversized scale sweep
- 新 layer / tensor / loading-strategy 语义
- 为 oversized 添加特殊 Execution State semantics
- 将 latency delta当作未注册的 performance benchmark
- 用 oversized 旁证替代普通模型的默认路径证明

## Immediate next action

进入 Phase A：

> **Execution State semantic inventory + persistence / representation boundary audit**

随后再注册 PALACE-1 minimal durable unit question。

