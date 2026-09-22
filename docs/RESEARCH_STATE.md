# SimiGo-Lab Research State

> **This file is the authoritative snapshot of the current SimiGo-Lab research state.
> Conversation memory must not override it.**
> Git 保存事实，会话负责推理：任何"项目到哪了"的问题，先读本文件与所引 endpoint 文档，再回答。

**Last updated**: 2026-09-22（STEP ③ 外审 PASS 登记，第④步解锁未启动）

## 0. 状态恢复流程（重进项目时固定执行，不得跳过）

```text
① 读取本文件（RESEARCH_STATE）
        ↓
② 读取当前阶段的 endpoint / closure 文档
        ↓
③ 核对最近 git log 与本文件是否一致
        ↓
④ 按 §2 状态词汇确认 sealed / closed / open / not-started
        ↓
⑤ 才允许回答问题或提出动作
```

## 1. 当前阶段

```text
Phase:        Definition / Opening（STEP ③ PASS；第④步解锁未启动）
Next action:  第④步：estimand 定义（NOT STARTED）
Gate status:  OPEN — STEP ③ PASS（外审+登记 2026-09-22）→ STEP ④ 解锁未启动
RQ ID:        未分配（Q2.1 裁定 ≠ ID 分配；ID 待整条 RQ 定义完成）
活跃文档:     docs/SOURCE_RUNTIME_RESEARCH_QUESTION_DEFINITION_v0.1.md
              （§8.1 STEP ② PASS）
              docs/SOURCE_RUNTIME_INDEPENDENCE_ARGUMENT_v0.1.md
              （§8.1 STEP ③ PASS；论证落档 d79a82f，外审 PASS 登记 a6924c1）
              docs/SOURCE_RUNTIME_RESEARCH_DEFINITION_OPENING_v0.1.md（STEP ① PASS）
```

## 2. 状态词汇表（禁止跨阶段推理）

| 状态 | 含义 | 推理约束 |
|---|---|---|
| SEALED | 结论冻结 | 禁止"继续优化该结论"类推理 |
| CLOSED | 研究问题已完成合法出口 | 禁止据此推导"立即开始下一实验" |
| OPEN | 当前在册研究问题 | 仅此状态的问题构成当前任务 |
| DEFINED | 已定义但尚未开始 | 仅允许其预注册 Allowed 动作 |
| NOT DEFINED | 连问题都尚未正式立项 | 禁止一切实现/采数/测量动作 |
| FROZEN | 基础设施可复用，但身份不可变 | 复用必须建立新 provenance 锚点 |
| SEPARATELY SCOPED | 有关联，但不得并入当前研究 | 禁止跨线引用结论 |

规则：看到任何旧阶段结果，先查其状态，再判断它与当前任务是否相关。
旧结论 + 新问题 ≠ 当前任务。

## 3. 研究问题唯一 ID

| ID | 研究问题 | 状态 | 锚点 |
|---|---|---|---|
| RQ-B-01 | Execution State lifecycle 语义（收敛模型） | CLOSED / FROZEN | `4184aa6` |
| RQ-P3-01 | Residency policy 频率机制 | P3-A 终判 PASS / P3-B R3 CLOSED / P3-C R-W CLOSED·SEALED | `ff52943` / `072fc2f` / `ac71e34` |
| RQ-H-01 | 结构信号存在性 | CLOSED / SEALED | `edc4dad` |
| RQ-NO-01 | 取消 node 粒度外化通道：粒度 / correctness / 边界成本 | CLOSED | `2cf244e` + `b6ad7c0` |
| RQ-P4-01 | 哪些结构/状态机制构成核心驻留机制 | NOT STARTED（独立立项） | — |
| RQ-F-01 | Source/Runtime 机制可实现·可验证性 | NOT DEFINED（连问题尚未立项） | — |

## 4. Mainline

```text
Execution State → Residency → P3 → H-P1 → nodes-out → Track E CLOSED
        ↓
[未定义] Source/Runtime 机制存在性（RQ-F-01 候选，未立项）
```

## 5. Sealed / Closed 清单

| 线 | 状态 | 证据 |
|---|---|---|
| Track B | CLOSED / FROZEN | `4184aa6`（Closure v4 终审 PASS/FREEZE） |
| Residency M1–M4 | FINAL PASS 封口 | 仓内 M1–M4 结果文档 |
| P3-A | 终判 PASS 盖章 | `ff52943` |
| P3-B | R3 CLOSED（底座内部归因未封，属另线） | `072fc2f` |
| P3-C | R-W CLOSED / SEALED | `ac71e34` |
| H-P1 | CLOSED / SEALED | `edc4dad` |
| nodes-out / Track E | CLOSED / 归档 | endpoint `trackE-residency/NODES_OUT_RESEARCH_ENDPOINT_DECISION_v0.1.md` + closure record `trackE-residency/TRACK_E_CLOSED_RECORD_20260922.md` |

## 6. Not started / Not defined

| 项 | 状态 | 约束 |
|---|---|---|
| P4（RQ-P4-01） | NOT STARTED | 串行链独立环节，须独立立项 |
| Track F（RQ-F-01） | NOT DEFINED | 无立项依据；`mlx-swift-lm` 无实验分支；立项价值须独立成立，不得表述为 Track E effect verdict 的延续 |
| Swift implementation | NOT STARTED / NO BASIS | — |

## 7. Registered prediction（登记态，非结论）

nodes-out endpoint §4.2：相同硬件、runtime 与工作负载条件下，nodes-out 新增事件路径预期不产生系统级正向收益；方向与量级留待未来 runtime 实验验证。

约束：本预测处于登记态，不得当作已证结论引用；任何检验必须先过独立 Design Revision + 外审门。

## 8. Current gate（版本化的"下一步"）

```text
RQ:           TBD（未分配）
Phase:        新研究问题定义（Definition / Opening Draft）
Status:       OPEN — STEP ③ PASS（独立性论证）→ STEP ④ 解锁未启动

外审保留意见（对第②–④步有约束力）:
- C1 第三条（Swift/MLX 可表达独立驻留状态）只能作为可检验边界；
- 不得反向变成"runtime 能表达 → 合理研究对象"的 implementation-first 预设。

STEP ③ 外审收紧（对后续各步有约束力）:
- "未暴露"结论只能登记为"预注册模型、workload 与观察边界内未获得
  足以支持存在性的证据"；禁止升级为"runtime 不存在自然粒度"；
- RM-005 / 访问模式原则的未来状态不得提前判定；若真实 runtime 暴露
  unit，只能进入"支持 / 限定 / 否定"的后续评价，不得预设"验证成功"。

Allowed:
- 第④步：estimand 定义（NOT STARTED）。
- 引用 STEP ② / STEP ③ 外审保留意见作为自查约束
- 历史资产盘点（只读取，FROZEN 身份不变）

Forbidden:
- 把 Q2.1 裁定当成 RQ ID 分配，或宣称 RQ 定义已完成
- 把四道 RQ 资格门当成第③–⑧步已完成的证明
- 以重复 Q2.1 四道门充当第③步独立性论证
  （Q2.1 证明的是候选资格与最小性；第③步要证明的是研究独立性——两事不可混同）
- 把 STEP ③ PASS 当作第④–⑨步已完成，或宣称 RQ 定义已完成
- 把 STEP ③ 负向出口表述成"runtime 不存在自然粒度"的全局结论
- 预设 RM-005 / 访问模式原则的未来验证结果
- 把 Opening 对象边界当作研究问题答案，或预选任何候选族
- runtime implementation / harness construction
- data collection / performance measurement
- 修改任何 FROZEN 资产身份
- 以旧阶段结论推导新实验
- 第④步外审通过前进入第⑤步及以后
```

### 8.1 Gate opening protocol（门开启后的必经序列；跳步无效）

本门被正式打开后，定义工作必须按序通过以下检查点，每步落档后方可进入下一步：

```text
① 研究对象是什么
② 研究问题是什么
③ 为什么它是一个独立问题
④ estimand 是什么
⑤ 什么观察结果构成"存在"
⑥ 什么结果构成"不足以支持存在"
⑦ discriminating power 是否成立
⑧ 值得测吗（成本-信息量比）
⑨ 通过后才决定 Path / Harness / Experiment
```

## 9. 重要边界

SimiGo 1.x product line ≠ SimiGo-Lab 2.0 research line。

伴生文档（非状态权威）：

- `docs/AGENT_CONTEXT.md` —— 行为层：Agent 操作规则与行为约束；
- `docs/RESEARCH_MEMORY.md` —— 思想层：RM-001~009 思想分支登记（条目均为
  CANDIDATE / HYPOTHESIS 态，禁止静默转为事实或 RQ）。

事实源优先级：Git 仓库（本文件 + endpoint 文档 + ledger + git log）> 一切对话记忆。
冲突时以 git log 与 endpoint 文档为准，回修本文件。

## 10. 状态维护规则

1. 任何状态变更（新门开启、门关闭、状态词汇变化）必须更新本文件并独立 commit；
2. 本文件只记"当前状态"；历史与论证进 endpoint 文档与 git log，不在本文件展开；
3. RQ ID 一经分配永久占用，废弃用 CLOSED/NOT DEFINED 标注，不复用编号。
