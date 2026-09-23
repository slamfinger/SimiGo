# SimiGo-Lab Research State

> **This file is the authoritative snapshot of the current SimiGo-Lab research state.
> Conversation memory must not override it.**

**Last updated**: 2026-09-23（STEP④-A 完成：human researcher 已显式实例化 VType=VECTOR / OutputDiscipline=FINITE_REAL_COORDINATEWISE / Binding_C=VECTOR_COMPOSITION；下游一致性审查通过）

## 1. 当前阶段

Phase: Architecture 2.0 / P4 Redefinition / STEP④-A COMPLETE → STEP④-B / Value Discipline（STEP⑤ NECT mode blocked）
Next action: Enter Value Discipline / STEP④-B（semantic instantiation 已完成并通过必要的一致性审查）；进入与否由 human researcher 决定
Gate status: OPEN — STEP① accepted; STEP② accepted; STEP③ passed; STEP④ passed with STEP④-A semantic instantiation COMPLETE and consistency review PASSED; STEP⑤ NECT mode blocked
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
| RQ-P4-01 | Architecture-induced Execution State 及其资源生命周期特征 | STEP④ PASS / MCVSD VALID / DG-4A-01 RESOLVED AS RESULT_FORM_DETERMINING / VTYPE=VECTOR / OUTPUT DISCIPLINE=FINITE_REAL_COORDINATEWISE / BINDING_C=VECTOR_COMPOSITION / SEMANTIC INSTANTIATION COMPLETE / CONSISTENCY REVIEW PASSED / VALUE DISCIPLINE OPEN / NECT MODE BLOCKED / NOT REGISTERED |
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
| P4-A existence criterion | STEP⑤ OPEN / EC5 REJECTED / NDAC ACCEPTED / DOMAIN PARTITION ADOPTED / MCVSD VALID / DG-4A-01 RESOLVED AS RESULT_FORM_DETERMINING / SEMANTIC INSTANTIATION COMPLETE / CONSISTENCY REVIEW PASSED / NECT MODE BLOCKED | 语义实例化已完成；下一步为 Value Discipline / STEP④-B，仍不授权实验 |
| Source/Runtime / RQ-F-01 | RETIRED / NOT DEFINED | 不进入 STEP⑤；此前状态不向 P4 转移 |
| Swift implementation | NOT STARTED / NO BASIS | 不因 STEP⑤ 获得授权 |
| Execution-State-oriented Post-Training | HYPOTHESIS / NOT REGISTERED | 不创建新 RQ，不授权实验/实现/测量 |

## 7. Current gate

P4 / RQ-P4-01 candidate
- STEP① 研究对象：ACCEPTED BY HUMAN RESEARCHER
- STEP② Research Question：ACCEPTED / GATE PASSED
- STEP③ Independence：PASS
- STEP④ Estimand：PASS / CLOSED FOR CURRENT FRAME / MFB-SR COMPLETE / SIA COMPLETE / CVSDR COMPLETE / MVSD COMPLETE / VSCA COMPLETE / FSAR COMPLETE / CVSR COMPLETE / CVS-ERR COMPLETE / MCVSD VALID / VTYPE=VECTOR / OUTPUT DISCIPLINE=FINITE_REAL_COORDINATEWISE / BINDING_C=VECTOR_COMPOSITION / SEMANTIC INSTANTIATION COMPLETE / CANDIDATE 2 REJECTED / CANDIDATE 1 NOT FROZEN
- STEP⑤ Nontrivial Phenomenon Existence Criterion：OPEN / NDAC ACCEPTED / SAT_INF_FIN DEFINED / DOMAIN PARTITION STRUCTURAL / IPR UNDECLARED / REVIEW-2 BLOCKED / NECT MODE BLOCKED
- STEP⑥–⑨：未开始

### Allowed

- 阅读并维护 `docs/STEP4A_CANONICAL_DECISIONS.md`；
- 进入 Value Discipline / STEP④-B（semantic instantiation 已完成并通过必要审查）；
- 继续遵守 `DG_4A_01=RESULT_FORM_DETERMINING` 与已实例化的 `Binding_C=VECTOR_COMPOSITION`：`C` 的 semantic form 为向量组合对象，local-to-global relation 由该 form 派生；
- 其余既有 STEP④/⑤ 定义资产仅在发生具体语义矛盾时重新审查；
- 保持 `A/W/W_D` 为 carrier symbols only，保持 `J` 为 abstract index carrier；
- 继续保留既有 NDAC、SAT_INF_FIN、IPR 与 domain-partition 约束；
- 禁止把 `V_j` 的向量维度 `k` 或 `C` 的坐标结构默认等同于 `J` 的 membership/cardinality；
- `V_j` 的所有坐标均为普通有限实数（排除 `±∞`、`NaN`、缺失值）。

### Forbidden

- 重新打开已完成的 `VType`、`OutputDiscipline`、`Binding_C` 实例化，除非出现具体语义矛盾；
- 新增 formal-basis、metadata 或 contract 审计层而没有具体语义矛盾；
- 从自然语言 “cost”、Risk、oracle、`D_loss`、STEP⑤ notation 或工程常识反向修改 `V_j` 的已声明语义；
- 重新引入 `+infty` loss-value semantics 或向 `V_j` 坐标引入 `±∞` / `NaN` / 缺失值；
- 进入 Risk、`FinLoss`、residual status、NECT mode 或 STEP⑥，Value Discipline / STEP④-B 完成前不得越过其自身门禁；
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
VType            = VECTOR (V_j ∈ ℝ^k)
OutputDiscipline = FINITE_REAL_COORDINATEWISE (all coordinates finite reals)
Binding_C        = VECTOR_COMPOSITION (C = [V_1, V_2, ...], vector result form)

J   = ABSTRACT INDEX CARRIER; MEMBERSHIP/COMPONENT SET UNDECLARED
A   = CARRIER SYMBOL ONLY
W   = CARRIER SYMBOL ONLY
W_D = CARRIER SYMBOL ONLY

Order         = VECTOR_POSITIONAL (intrinsic to declared vector forms)
Measurability = DEFERRED
```

`Scalarity`、`finiteness`、special-value admissibility 已由 `OutputDiscipline = FINITE_REAL_COORDINATEWISE` 治理。`nonnegativity` 未被声明（有限实数可正可负）。`Measurability` 继续 DEFERRED。

Infinity semantics remain:

```
LOSS_INFINITY_PREDEFINED = FALSE
IPR_VALUE                = UNDECLARED
```

STEP④-B / FinLoss / residual / NECT remain blocked.

## 11. Governance

本次 STEP④-A 收敛没有新增实验、harness、implementation 或 measurement authorization。
