# Gate Spec — Phase 1: Integration Boundary Gate

Date: 2026-10-02  
Status: `GATE OPENED（SPEC 已登记；实现按本 SPEC 执行）`  
Baseline: `d2a1ea7`（Human Acceptance = CLOSED）  
纪律：本 Gate 开启 ≠ 扩展模型；T4 = BLOCKED 不动；d2a1ea7 之后
的**新功能提交不推送**（实现提交仅本地）。

## 1. 目的

证明已接受的 `Information / InformationStore / SQLiteStore` 可以
作为一个**真实的上层使用边界**工作——真实调用链贯通，而
SQLite / 事务 / WAL / 物理 filing 等实现细节**不被带回语义层**。

通过后，SQLiteStore 才有资格被视为当前 Information 存储的
**可替换 Physical Filing backend**：

```text
Information semantic model
          │ stable boundary
          ▼
    InformationStore
          │ replaceable implementation
          ▼
     SQLiteStore
```

暂不做的事：不为「未来整个系统」证明任何事；不加下一批模型。

## 2. 输入

- 已验收三文件（`6feac8c`，ACCEPTED @ `d2a1ea7`）
- Phase 0 冻结语义面 + Phase 1 边界/API 裁定（全部封存件）
- 零新概念、零新模型

## 3. 允许修改范围

1. **新增**集成验证 harness：独立 target（独立模块），仅
   `import InformationCore`，通过 `any InformationStore` 绑定实现
2. `Package.swift` 仅为该 target 接线
3. **三个已验收文件零改动**——若暴露冻结契约无法表达，重开
   裁定（单独登记），不得静默修改
4. 组合根（composition root）允许知道 SQLiteStore 具体类型
   （依赖注入的唯一位置）；上层消费代码不得引用

## 4. 必须证明的 invariants

| # | 不变量 |
|---|---|
| I1 | 上层形成的 `Information` 经真实调用链完整落库 |
| I2 | 经 `InformationID` 取回**同一语义值**（相等性 roundtrip） |
| I3 | `absence == nil`（非异常） |
| I4 | 重复 `store` 幂等（事实不变） |
| I5 | `PhysicalFiling` 物理存在但**不重新进入 Information 语义面**（库内有、类型无、API 不可达） |
| I6 | 上层**零 SQLite/WAL/transaction 知识**（结构证明：上层源码无 SQLite 符号；仅组合根一处构造具体类型） |
| I7 | 零负空间类型（Relation/Activation/Diary/ExecutionState/checkpoint/ack/Layer0-1/taxonomy/MCP/retrieval） |
| I8 | 可替换性结构证据：上层仅依赖 `any InformationStore`，实现更换不触上层代码 |

## 5. 验证方式

1. 集成 harness 实跑：真实调用链
   `上层 → store → fetch → InformationStore → SQLiteStore → Physical Filing`
2. 编译即证明：上层源文件无 SQLite 符号（grep 审计 = 0 命中）
3. 结构审计：负空间符号全仓扫描（新代码 + InformationCore）= 0 命中
4. 物理层抽查：sqlite3 CLI 直查 filing 列存在且语义类型不携带
5. Build 零警告

## 6. Negative Space

同已封存清单全项禁止；另加：不新增 Information 字段、不新增
Store API、不新增语义类型、无 convenience extension、无
placeholder protocol、无「以后方便」预留。

## 7. Pass / Fail

- **PASS** = I1–I8 全证 + Build 零警告 + 审计零命中 + 三个已
  验收文件 diff 为零 ⇒ SQLiteStore 正式记为可替换 Physical
  Filing backend
- **FAIL** = 任一 invariant 不成立；或必须改动三文件才能通过
  ⇒ 停止，重开对应裁定（登记后再议），不静默修改
- 实现层 bug（编译错/误用模式）就地修复并记录，不构成 FAIL
