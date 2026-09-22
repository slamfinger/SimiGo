# SimiGo-Lab Research State

> **This file is the authoritative snapshot of the current SimiGo-Lab research state.
> Conversation memory must not override it.**

**Last updated**: 2026-09-23（STEP④-A 收敛：MCVSD validity audit complete；进入 canonical semantic instantiation decision surface）

## 1. 当前阶段

Phase: Architecture 2.0 / P4 Redefinition / STEP④-A Canonical Decision Surface（STEP⑤ NECT mode blocked）
Next action: Human researcher must explicitly instantiate MCVSD `SourceStatus/VType/OutputDiscipline` and separately decide `Binding_C`; agent must not select semantic values
Gate status: OPEN — STEP① accepted; STEP② accepted; STEP③ passed; STEP④ passed with STEP④-A semantic instantiation open; STEP⑤ NECT mode blocked
RQ ID: 尚未分配（正式 RQ registration 尚未发生）
当前活动文档: docs/STEP4A_CANONICAL_DECISIONS.md

## 2. 状态词汇表

| 状态 | 含义 | 推理约束 |
|---|---|---|
| SEALED | 结论冻结 | 禁止继续优化该结论 |
| CLOSED | 研究问题已完成合法出口 | 不据此推导立即开始下一实验 |
| OPEN | 当前在册研究问题 | 仅此状态的问题构成当前任务 |
| DEFINED | 已定义但尚未开始 | 仅允许预注册 Allowed 动作 |
| NOT DEFINED | 连问题都尚未正式立项 | 禁止实现/采数/测量 |
| FROZEN | 基础设施可复用，但身份不可变 | 复用必须建立新 provenance |
| SEPARATELY SCOPED | 有关联，但不得并入当前研究 | 禁止跨线引用结论 |

## 3. 研究问题唯一 ID

| ID | 研究问题 | 状态 |
|---|---|---|
| RQ-B-01 | Execution State lifecycle 语义（收敛模型） | CLOSED / FROZEN |
| RQ-P3-01 | Residency policy 频率机制 | P3-A PASS / P3-B R3 CLOSED / P3-C R-W CLOSED·SEALED |
| RQ-H-01 | 结构信号存在性 | CLOSED / SEALED |
| RQ-NO-01 | 取消 node 粒度外化通道 | CLOSED |
| RQ-P4-01 | Architecture-induced Execution State 及其资源生命周期特征 | STEP④ PASS / MCVSD VALID / VTYPE UNDECLARED / OUTPUT DISCIPLINE UNDECLARED / SEMANTIC INSTANTIATION REQUIRED / NECT MODE BLOCKED / NOT REGISTERED |
| RQ-F-01 | Source/Runtime 机制可实现·可验证性 | RETIRED CANDIDATE / NOT DEFINED |

## 4. Mainline

Model Architecture Features → Computation → Execution State → State Characteristics → Resource Behavior → Loading / Residency / Layering / Working Set / Migration → Runtime Architecture

潜在反向研究路径（尚未验证）：

Post-Training → Computation / Execution-State Behavior

## 5. Sealed / Closed

Track B、Track E、P3、H-P1、nodes-out 保持原有 CLOSED / SEALED / FROZEN 状态。历史路线不自动重开。

## 6. Not started / not defined

| 项 | 状态 | 约束 |
|---|---|---|
| P4-A existence criterion | STEP⑤ OPEN / EC5 REJECTED / NDAC ACCEPTED / DOMAIN PARTITION ADOPTED / MCVSD VALID / SEMANTIC INSTANTIATION REQUIRED / NECT MODE BLOCKED | 只允许 human researcher 显式实例化 MCVSD，不授权实验 |
| Source/Runtime / RQ-F-01 | RETIRED / NOT DEFINED | 不进入 STEP⑤；此前状态不向 P4 转移 |
| Swift implementation | NOT STARTED / NO BASIS | 不因 STEP⑤ 获得授权 |
| Execution-State-oriented Post-Training | HYPOTHESIS / NOT REGISTERED | 不创建新 RQ，不授权实验/实现/测量 |

## 7. Current gate

P4 / RQ-P4-01 candidate
- STEP① 研究对象：ACCEPTED BY HUMAN RESEARCHER
- STEP② Research Question：ACCEPTED / GATE PASSED
- STEP③ Independence：PASS
- STEP④ Estimand：PASS / CLOSED FOR CURRENT FRAME / MFB-SR COMPLETE / SIA COMPLETE / CVSDR COMPLETE / MVSD COMPLETE / VSCA COMPLETE / FSAR COMPLETE / CVSR COMPLETE / CVS-ERR COMPLETE / MCVSD VALID / VTYPE UNDECLARED / OUTPUT DISCIPLINE UNDECLARED / CANDIDATE 2 REJECTED / CANDIDATE 1 NOT FROZEN
- STEP⑤ Nontrivial Phenomenon Existence Criterion：OPEN / NDAC ACCEPTED / SAT_INF_FIN DEFINED / DOMAIN PARTITION STRUCTURAL / IPR UNDECLARED / REVIEW-2 BLOCKED / NECT MODE BLOCKED
- STEP⑥–⑨：未开始

### Allowed

- 阅读并维护 `docs/STEP4A_CANONICAL_DECISIONS.md`；
- 由 human researcher 显式实例化 MCVSD：`SourceStatus=NEW_DECLARATION`、`VType`、`OutputDiscipline`；
- 单独决定 `Binding_C`，不默认任何聚合形式；
- 对新的 semantic instantiation 做一次必要的下游一致性审查；
- 其余既有 STEP④/⑤ 定义资产仅在发生具体语义矛盾时重新审查；
- 保持 `A/W/W_D` 为 carrier symbols only，保持 `J` 为 abstract index carrier；
- 继续保留既有 NDAC、SAT_INF_FIN、IPR 与 domain-partition 约束；
- 在语义实例化完成并合法通过后，再进入 Value Discipline / STEP④-B。

### Forbidden

- agent 自动选择 `VType`、`OutputDiscipline` 或 `Binding_C`；
- 新增 formal-basis、metadata 或 contract 审计层而没有具体语义矛盾；
- 从自然语言 “cost”、Risk、oracle、`D_loss`、STEP⑤ notation 或工程常识反向确定 `V_j`；
- 把 MCVSD_VALID 解释为 `V_j` 已声明或 Cost Value Semantics 已完成；
- 自动把 `V_j` 选择为 finite scalar、extended scalar、vector、typed record 或其他具体 carrier；
- 重新引入 `+infty` loss-value semantics；
- 进入 Value Discipline、Risk、`FinLoss`、residual status、NECT mode 或 STEP⑥，直到 semantic instantiation 完成并通过必要审查；
- Runtime implementation / research harness / data collection / profiling / performance measurement；
- 自动注册 RQ-P4-01；
- 重新研究 Track B 已闭合的 State lifecycle semantics；
- 将 Execution-State-oriented Post-Training 假设视为已成立。

## 8. Definition Gate

① 研究对象 → ② Research Question → ③ 独立性 → ④ estimand / envelope object definition → ⑤ nontrivial phenomenon existence criterion → ⑥ negative / insufficiency criterion → ⑦ discriminating power → ⑧ information value / cost → ⑨ Path / Harness / Experiment。

## 9. P4 方法原则

Architecture 2.0 采用：当前代表性架构 → 最小抽象 → 新架构反例 → 最小必要扩展 → 再验证。

通用性由真实架构反例推动，而不是由想象中的未来模型推动。没有反例，不增加抽象层；“不能泛化”本身是合法研究结果。

## 10. Current semantic boundary

STEP④-A 当前不再新增 formal-basis 或 metadata 审计层。历史审计文档全部保留在 `docs/07-history/` 作为 evidence；canonical decision surface 由 `docs/STEP4A_CANONICAL_DECISIONS.md` 承载。

当前唯一的 STEP④-A 语义决策面：

```
SourceStatus     = NEW_DECLARATION
VType            = UNDECLARED
OutputDiscipline = UNDECLARED
Binding_C        = UNDECLARED

J   = ABSTRACT INDEX CARRIER; MEMBERSHIP/COMPONENT SET UNDECLARED
A   = CARRIER SYMBOL ONLY
W   = CARRIER SYMBOL ONLY
W_D = CARRIER SYMBOL ONLY

Order         = DEFERRED
Measurability = DEFERRED
```

`Scalarity`、`finiteness`、`nonnegativity`、special-value admissibility 等输出限制，属于未来 `OutputDiscipline` 的实例化内容，不在 canonical layer 预选。

Infinity semantics remain:

```
LOSS_INFINITY_PREDEFINED = FALSE
IPR_VALUE                = UNDECLARED
```

STEP④-B / FinLoss / residual / NECT remain blocked.

## 11. Governance

本次 STEP④-A 收敛没有新增实验、harness、implementation 或 measurement authorization。
