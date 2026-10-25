# Phase 2 — Relation Boundary Gate：D1–D7 裁定封存

Date: 2026-10-02  
Status: `DECISIONS SEALED / MINIMAL IMPLEMENTATION AUTHORIZED`

## 1. 裁定表（human 逐字要点）

| # | 裁定 | 结论 |
|---|---|---|
| D1 | **(a)** | Relation = 引用 `InformationID` 的有向三元组（subject → predicate → object）+ provenance；**Relation 引用 Information，而不是重新定义实体**；服务树自由字符串 endpoint 留作外部/既有系统能力，不进 RelationCore 语义面；**InformationID 不得降级为 String**（否则 Phase 1 identity 边界重开） |
| D2 | **(a)** | opaque `RelationID`，确定性派生、机制侧铸造；**配方属机制层，不进 Relation 语义 API**；服务树 `datetime.now()` 盐反面观测 = 拒绝该模式的证据（服务树本身不需改造） |
| D3 | **(a)** | Relation immutable；**不引入** valid_from/valid_to/active/inactive/terminated 等需回写 Relation 的状态字段；「关系结束」未来 = 新的事实/状态层语义，不是修改已存在的 Relation；**Temporal validity 暂不属 Phase 2 RelationCore 最小语义面**（不预埋） |
| D4 | **(a)** | 独立 `RelationStore` ∥ `InformationStore`（绝不嵌套）；**不为方便把第二种语义对象塞进已定稿 S1–S6 persistence contract** |
| D5/D6 | 硬约束 | 照 Spec 原文：InformationCore/InformationStore/SQLiteStore/InMemoryStore diff = 0；Relation 落位 `RelationCore`；RelationCore → import InformationCore；**不得反向依赖，也不得把 Relation 类型导入 InformationCore** |
| D7 | **(a)** | 独立 `RelationCore`，仅依赖 InformationCore |

## 2. Phase 2 最小模型（human 定稿）

```text
                InformationCore
                       │
                 InformationID
                    ↗     ↖
                   /       \
                  /         \
           subject           object
                \             /
                 \           /
                  └ Relation ┘
                       │
                 RelationID
                       │
                RelationStore
```

```text
Information = immutable fact
Relation    = immutable relation between facts
```

**平行语义对象，不是父子对象。**

## 3. 特别锁定的 Negative Space

**当前不定义 Predicate taxonomy**：predicate 是语义位置，但不得
定义 `enum Predicate { parentOf, causedBy, … }`，不得建立
`RelationType / PredicateRegistry / Taxonomy / Ontology`——否则
本 Gate 从「证明 Relation 可以独立存在」扩大成「设计整个知识
图谱语义体系」。Predicate 具体编码保持在最小范围；实现若需具体
类型，作为**实现决策单独登记**。

## 4. 实现阶段证明清单（9 项）

1. Relation 可以引用两个 `InformationID`
2. Relation 自身有 opaque deterministic `RelationID`
3. Relation immutable
4. `RelationStore` 独立存在
5. InformationCore 五文件保持零 diff
6. InformationStore 保持零 diff
7. SQLiteStore / InMemoryStore 保持零 diff
8. RelationCore 只向下依赖 InformationCore
9. 不引入 temporal mutation / activation / taxonomy 等未来语义

**仍然不做**：Relation 查询、图遍历、排序、检索、服务树适配。
Gate 命题（human 逐字）：

> **Relation 能否在不改变已冻结 Information 语义和 Phase 1
> persistence contract 的情况下，成为独立的上层语义对象。**
