# Gate Spec — Phase 2: Relation Persistence Semantics Gate（仅 Spec，零实现）

Date: 2026-10-02  
Status: `GATE OPENED（SPEC 已登记；契约确认 + 实现待 human go）`  
前置：Phase 2 Relation Boundary Gate = PASS；RelationCore 最小实现
**ACCEPTED**（human 终态确认）  
命题：把 `RelationStore` 从「镜像 InformationStore 的实现」提升为
**正式 backend-independent contract**——使未来 Relation backend
独立实现而**零语义漂移**（Phase 1 Persistence Semantics Gate 的
Relation 平移复刻）。

## 1. 契约面（提案 = human 提出的 R1–R6，镜像已定稿 S1–S6）

| # | 输入 | 契约（提案） | 现状 |
|---|---|---|---|
| R1 | store，new RelationID | 持久化 | 测试 backend 已实现，未双 backend 形式化 |
| R2 | store，same RelationID + same Relation | 成功 no-op 确认 | 同上 |
| R3 | store，same RelationID + conflicting Relation | 成功 no-op，**first-write-wins**，existing 保持权威 | **R4b 已单 backend 实测成立**；未双 backend 形式化 |
| R4 | fetch，present | 返回该 Relation | 同 R1 |
| R5 | fetch，absent | nil（非异常） | 同上 |
| R6 | storage failure | throw（仅 failure，永不表 absence） | 实现层 |

行为形状 = S1–S6 的 Relation 平移；**本 Gate 不发明新语义**，只把
镜像实现升格为显式契约并做双 backend 一致性验证。

## 2. 验证方式

1. **Backend-1 = SQLiteRelationStore**（本 Gate 新增，harness/测试
   侧落位——契约验证用；生产落位为后续独立决策）：SQLite 持久化
   Relation，实现公共协议 `RelationStore`，自带机制侧 minting 不
   强制（identity 由 minter/组合根供给；backend 只持久化已形成
   Relation）
2. **Backend-2 = InMemoryRelationStore**（既有 harness 测试 backend，
   零改动或仅签名级适配）
3. 同一未改动消费者经 `any RelationStore` 分别驱动双 backend，
   R1–R6 全项断言；**R3 冲突探针**（同 RelationID + 不同
   predicate/object 的冲突 Relation）双 backend 行为逐项一致
4. diff 审计：InformationCore 三文件 + Relation.swift/
   RelationMinter.swift/RelationStore.swift/UpperLayer.swift/
   InMemoryStore.swift/SQLiteStore.swift **全部 diff = 0**
5. 符号审计：双 Relation backend 零越界符号；声明级负空间审计
   零命中；Build 零警告

## 3. 硬边界（human 逐字锁定）

> **不要因为 RelationStore 出现，就把 `InformationStore` 与
> `RelationStore` 抽象成一个泛型超级 Store。**

禁止：`Store<Entity>`、`PersistentObject`、
`AnySemanticObjectStore`、统一超级协议、任何把两个语义对象
差异重新隐藏的抽象。

```text
InformationStore   ← 平行 boundary，各自独立
RelationStore   ←
```

未来若事实证明存在真正稳定的共同抽象，**另开 Gate**。

## 4. Negative Space

延续全项（activation/diary/execution state/checkpoint/ack/
Layer0-1/taxonomy/MCP/retrieval/ranking/query/traversal/排序/
服务树适配）+ 本 Gate 特有：零泛型超级 Store、零 RelationStore
契约外能力（list/query/delete 除非未来单独 Gate）、零
InformationStore 契约改动。

## 5. Pass / Fail

- **PASS** = R1–R6 契约经 human 确认 + 双 backend 行为逐项一致
  且符合契约 + 受保护文件 diff 全 0 + 零超级 Store 抽象 +
  Build 零警告 ⇒ `RelationStore` 契约正式定稿（Relation 平移
  S1–S6 ⇒ R1–R6 FINALIZED）
- **FAIL** = 双 backend 对任一契约项行为不一致且无法按契约对齐
  ⇒ 停止，登记语义缺口重开裁定

## 6. Git / 推进

3 个本地提交保持原样（不 squash 不 rewrite）；本 Spec 提交 +
后续实现/结果提交成链；推送节奏待 human 指令。T4 = BLOCKED
不动。Gate 节奏不变：Spec → human 确认 → minimal implementation
→ structural audit → runtime evidence → PASS → seal。
