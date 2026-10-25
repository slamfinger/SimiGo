# Phase 1 最小 API 裁定 — 11/12 冻结 · A2′ 待裁

Date: 2026-10-02  
Status: `API RULING 11 FROZEN / A2′ IDENTITY FORMATION BOUNDARY PENDING`  
Constraint: 语义 → API 不得反向；Swift 文件仍为 0

## 1. 已冻结裁定（human 逐字要点）

### A. Information

- **A1 = 不可变值语义**：理由 = 语义事实（逐字存储/确定性
  identity/重复写 no-op）⇒ 不存在「同一 Information 被修改成
  另一个」；API 无 mutation/update
- **A2 = 专用 `InformationID`（opaque semantic identity）**：
  不暴露生成算法；SHA-256/`v3`/normalization/encoding 不得出现
  在其 API（区别于 `identity: String ❌`）
- **A3 = provenance 按事实分组**：producedAt/producedBy 必选；
  source/sourceTime/position/extractionMode 可选——「不因通常
  存在而升为必选」（服务树实际行为的边界）
- **A4 = temporal 成对可选**：`ContentDate?`（date + source）；
  禁止 `contentDate 有 / source nil` 的拆开状态；`unknown` 是
  服务默认来源标记、不得偷换成系统推断；不做回溯推断
- **A5 = 负空间零预埋**：wing/room/hall/entities/Relation/
  activation/diary/retrieval/taxonomy/ExecutionState 一概不出现，
  亦无空属性/protocol/placeholder

### B. InformationStore

- **B1 = `store(Information)` + `fetch(by: InformationID)`**；
  delete/search/list/query/rank/retrieve 一律不进（「当前没有
  充分语义证据，不进入 Core API」= 不预埋原则的正面执行）
- **B2 = 重复 identity = 成功 no-op**（existing 保持不变）；
  与 A1 闭环：「相同 identity 不是 update，而是确认已有事实」
- **B3 = `fetch → Information?`**：not found ≠ storage failure；
  正常 absence 不用 error 表达

### C. SQLiteStore

- **C1 = 职责三分**：schema + identity persistence/recipe
  mechanism + verbatim storage；不暴露 WAL/transaction/connection/
  normalization internals
- **C2 = wing/room 严格限定为 persistence filing metadata**：
  库内可存（service 实际用于归档），但**非 Information 语义
  属性**，禁止经 `information.room/.wing` 进 Core
- **C3 = verbatim 保证**：`content → SQLite TEXT → content`；
  禁止 Store 层为规范化/索引/去重改写 content

### D. 负空间

**全部正式裁定为不存在**：Relation/Activation/Diary/ExecutionState/
checkpoint/ack/Layer0/Layer1/taxonomy/MCP/retrieval/ranking/search/
BM25/Chroma/entities/closet/hallway——含 protocol/empty protocol/
placeholder type/optional property/"reserved for future"/extension hook
一切形态。

## 2. A2′ — 唯一待裁微裁定（Identity Formation Boundary）

human 发现的**结构性问题**（闭合前必须解决）：A2（Information
有 `InformationID`）× B1（`store(Information)`）× C1（ID 构造
属 SQLiteStore）同时成立 ⇒ **第一次创建 Information 时 ID 从
哪里来？**

- 若 `Information(...)` 要求调用者已提供 ID → ID 构造发生在
  Core 外部（而非 SQLiteStore）
- 若 `SQLiteStore.store(content,…)` 生成 ID → B1 退化为
  construct + store，把 API 便利性反向塞回语义设计

**不得凭直觉选 Swift 写法**。真正待裁的基础问题（唯一）：

> **InformationID 在 Information 形成时产生，还是在 Store
> 持久化时产生？**

human 倾向的语义表述（供 A2′ 裁定锚定，非结论）：

> **Identity 属于 Information 本身；identity 的生成算法不属于
> Information。**——semantic identity 与 identity construction
> mechanism 彻底分开。

裁定完成 ⇒ A1–C3 无缝闭合 ⇒ 才进入 **API → 首批 Swift 文件**
Gate。

## 3. Gate 状态

```text
A1✓ A2✓* A3✓ A4✓ A5✓
B1✓ B2✓ B3✓
C1✓ C2✓ C3✓
D ✓
* = 语义已裁；形成时点（A2′）待裁
Swift files = 0（纪律持续）
```
