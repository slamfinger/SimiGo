# Phase 1 Swift Core 最小边界裁定 — BOUNDARY CLOSED

Date: 2026-10-02  
Basis: Phase 0 Semantic Surface = FROZEN（`SIMIGO_LAB_PALACE_PHASE0_FROZEN_20261002.md`）  
Status: `PHASE 1 BOUNDARY = CLOSED / API NOT YET DESIGNED`

## 1. 六项边缘裁定（human 逐字要点）

| 项 | 裁定 | 归属 |
|---|---|---|
| C1 KG 三元组 | **不作为 `Information` 子类型进入 Core**；关系事实作为 Core 可表达的 Information/Relation 语义保留，**Relation 独立建模后置**（防 Phase 1 偷渡 KG） | Information Core 保留语义，不搬 KG |
| C2 diary 双层 | **Core 不定义 diary schema、不定义 diary 专用接口**；只冻结「事实与续作/continuity 分离」语义原则——不因当前 diary 单文档结构而视为同种语义 | Information / Execution 后续分层 |
| C3 activation | **不进入 Information Core，连空接口也不预埋**（`Information.activate()` / `ActivationProtocol` 均不做）；「存在 activation」≠「activation 是 Information」，链条 = Agent→Execution→activation→Information discovery | Execution 层 / 后续 runtime |
| C4 identity | **概念进 Core，机制不进**：`Information.identity` 语义必需；SHA/`ID_RECIPE="v3"`/normalization/编码 = persistence/implementation。判词 =「identity 是事实；identity recipe 是产生事实的机制」——后端更换时 identity 语义保持 | 语义入 Core / recipe 出 Core |
| C5 WAL 审计迹 | **不进 Information Core**（WAL 证明 durability/auditability，不是 Information 本身）；SQLite 事务细节、Chroma 同出 | persistence 层 |
| C6 checkpoint/ack/Layer0-1 | **全部不进 Information Core**，确认属 Execution continuity 侧（「Execution State 如何连续」≠「Information 是什么」）；未来 Execution State 消费/产出 Information Core | 后续 Execution State Core |

### C1 冻结形态（语义面追加）

```text
Information
├── content
├── identity
├── provenance
└── temporal

Relation
├── subject
├── predicate
├── object
└── provenance
```

Relation 语义进入冻结面；具体 Relation model 后置，非 Phase 1
必须实现的 Swift 类型。

## 2. Phase 1 最小边界（正式闭合）

```text
Phase 1 — Information Core

必须有：
Information        = identity / content / provenance / temporal
InformationStore   = 最小持久化生命周期操作
SQLiteStore        = 一个 persistence implementation
```

**进入语义 Core**：content、identity、provenance、temporal、
Information lifecycle。

**明确不进入**：KG implementation、diary schema、activation、
hash recipe、WAL、checkpoint、ack、Layer0/Layer1、Chroma/HNSW、
BM25、entities、closet/hallway、taxonomy、MCP、MemoryStack。

**Relation / Execution State / Activation = 后续层，不预埋接口。**

## 3. 最终架构边界（human 定稿图，逐字）

```text
                 ┌──────────────────────┐
                 │      Execution       │
                 │ checkpoint / ack     │
                 │ Layer0 / Layer1      │
                 │ activation           │
                 └──────────┬───────────┘
                            │
                            │ uses
                            ▼
                 ┌──────────────────────┐
                 │     Information      │
                 │ content              │
                 │ identity             │
                 │ provenance           │
                 │ temporal             │
                 └──────────┬───────────┘
                            │
                            ▼
                 ┌──────────────────────┐
                 │   InformationStore   │
                 └──────────┬───────────┘
                            │
                            ▼
                 ┌──────────────────────┐
                 │    Persistence       │
                 │ SQLite / WAL / ...   │
                 └──────────────────────┘
```

## 4. 下一道门

**最小 API 裁定**：据本冻结边界决定
`Information.swift / InformationStore.swift / SQLiteStore.swift`
的最小 API——方向锁死 = 语义决定 API，不得反向。API 裁定
完成前不产生 Swift 文件。

## 5. 未变项

Phase 0 Semantic Surface = FROZEN；Finding-1 审计教训（服务树
基准确认）继续适用；T4 = BLOCKED；Git 本地不推送。
