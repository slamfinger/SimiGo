# B-Design — 最小 Execution Layer 设计（R-B1 验证用；零代码）

Date: 2026-10-03  
依据：B-Spec FROZEN（Q6 修正版）+ Boundary Audit PASS  
授权：DESIGN ONLY——零实现、零 R-B1 执行、零 Core 改动、零
hash/文件扫描机制实现  
Status: `B-DESIGN DRAFT / AWAITING HUMAN CONFIRMATION`（确认后
B-Impl 另行授权）

## 1. Execution Layer 定位（在已证结构中的位置）

```text
ExecutionCore（本设计，新增模块）
    │ depends on
    ├── InformationCore（FROZEN，零改动）
    └── RelationCore（FROZEN，零改动）
```

Execution Layer = Information/Relation 之上的**第一个消费者层**：
观察（fetch）、消费（读取使用）、形成（新 Information/Relation）
+ 自身私有工作态（Core 之外）。它不向 Core 添加任何语义；它是
五层链中「Execution 层」的最小可验证雏形——T4/T4-2 的 agent
会话在真实世界做的事，在此以可审计的最小组件形态落地。

**依赖方向（硬规则延续）**：ExecutionCore → InformationCore /
RelationCore；反向禁止。InformationCore/RelationCore 保持零
SimiGo/Execution 知识。

## 2. 组件设计（三件，全部 Core 之外）

### C1 — ExecutionScope（边界消费者）

```text
职责：绑定 any InformationStore + any RelationStore（组合根注入）；
      observe  = fetch（S4/R4 边界面直用）
      consume  = 取回值的内存消费（无 API，消费即使用）
      form     = 新 Information / 新 Relation 形成（经机制铸造）
语义：零新增——persist/retrieve 直通 S1–S6/R1–R6 形状
      （UpperLayer/ColdStartExecutor 同构模式平移）
```

### C2 — Observation formation（外部变化观察的形成规则）

```text
输入（声明观察材料，执行时提供）：
  实体 E 的 before 引用（基线 Information identity）或
    before 表示（基线未存时）
  实体 E 的 after 表示（当前观察）
  observer 身份 + observedAt
形成：
  after-state Information（内容 = after 表示逐字 +
    provenance.producedBy = observer、source = E 路径、
    extractionMode = "observation"）
  change Relation：subject = after.identity，
    predicate = "observed-change-of"，object = before.identity，
    provenance = 观察事件事实
基线未存情形：先形成 before-state Information（同一观察规则），
  再形成 after——两次 formation + change Relation（Q7 表达）
```

### C3 — 机制边界声明（本设计不实现项）

```text
hash 计算、文件扫描/监视、变更检测触发器 = 观察机制，属
  B-Impl（若获授权）；本设计仅定义其输入/输出接口形状
  （声明观察材料），不实现任何检测代码
```

## 3. R-B1 最小实验结构（E → X → V(±N) 四 run 设计）

| Run | 执行者 | 输入 | 产出 | 记录 |
|---|---|---|---|---|
| **E-run**（基线） | cold-start 执行者 | 实体 E 的 S0 表示（声明输入） | before-state Information 形成入库 | db-E |
| （真实世界） | 环境自身 | E：S0 → S1 外部变化（成因不入实验） | —— | 变更声明留档 |
| **X-run**（观察者） | cold-start 执行者 | E 的 S1 表示 + before 引用 | after-state Information + change Relation 入库 | db-X（含 E 库快照迁移或同库延续，执行时钉定） |
| **V-E-run**（验证者，实验组） | **fresh cold-start 执行者**（R-B1 主语） | 仅边界访问：待答问题 + change Relation identity | 变更回答（S0→S1 diff 陈述） | db-V 或复用 |
| **V-N-run**（阴性对照） | 同 V 形态 | 同问题；边界**空**（或仅 before，无 after/change） | —— | 对照 |

**R-B1 验证问题（V-run）**：仅经边界回答「实体 E 自上次观察
以来发生了什么外部变化？」——正确答案 = change Relation 指向
的 before/after 差值陈述。

**V 环境约束（channel 排除）**：V 不获得 E 的当前表示（禁止
重扫描实体）；唯一信息源 = 边界取回。

## 4. before → after → change Relation 充分性分析

```text
验证目标表达需求：
  ① 基线事实可引用        → before Information（identity 寻址）
  ② 变化后事实可引用      → after Information
  ③ 二者间的观察关系可寻址 → change Relation（R1–R6 内）
  ④ 冷启动者可按图取回    → fetch(by identity)（S4/R4）
结论：四需求全部落在已冻结语义组合内 ⇒ 充分，
      无需新增 Core 类型（无 InformationChange/Watcher 概念）
不覆盖（显式后置）：变更成因归属（Q6 裁定后置）、连续多次
  变更链（Relation 链可表达，实验不涉及）、自动检测机制
```

## 5. 正/负空间（B-Design 版）

**正空间（设计面允许）**：ExecutionCore 模块类型设计、观察/
形成/消费流程设计、R-B1 四 run 实验结构、验证判据设计、
confound 候选登记。

**负空间（零出现）**：
```text
Core 语义/文件改动；hash/文件扫描机制实现；R-B1 执行；
B-Impl/B-Execute 开启；MemoryCore；Palace/MCP；retrieval/
activation/taxonomy/diary；InformationChange/Watcher/超级
Store 等新 Core 类型；query/遍历/排序；预设 R-B1 结果
```

## 6. Confound 候选（登记，归实验期 Confound Audit）

| # | 候选 | 控制/登记 |
|---|---|---|
| C-1 | V 直接重扫实体（绕边界） | V 环境约束：不提供 E 当前表示；唯一信息源 = 边界 |
| C-2 | 观察者=验证者自我确认 | X-run 与 V-run 为独立 fresh 会话；记录者居中传递 |
| C-3 | V 指令泄漏变更内容 | V 问题零内容词（只问「发生了什么」）；逐字冻结 |
| C-4 | 边界内容超基线预置 | E 库仅含 before；X 库仅含 after+change（或同库延续，钉定时定） |
| C-5 | 执行者形态差异引入能力差 | 四 run 同执行者形态（fresh agent 会话） |

## 7. 验证判据（R-B1，预登记）

```text
V-AC-1  V-E 产出的变更陈述与真实 diff 一致（S0→S1 要素齐）
V-AC-2  消费痕迹因果链：V 先 fetch（relation/before/after）
        后作答，取回内容与陈述数值/要素一致
V-AC-3  V-N 无法作答（not-found 阻塞）或答案不可验证地
        错误 —— 空边界下不可答
⇒ V-AC-1∧2∧3 = R-B1 验证 PASS（boundary 对「变化认知」
  必要，本实验结构域有界）
```

## 8. 与既有 contract 平行性声明

ExecutionCore 不接触、不吸收、不修改 SimiGo 既有三 contract
（ExecutionState/Continuity/RuntimeBackend）——平行边界原则
延续；Execution State 的正式语义化属后续层，本设计仅建最小
可验证雏形。
