# SimiGo-Lab Research State

> **This file is the authoritative snapshot of the current SimiGo-Lab research state.
> Conversation memory must not override it.**

**Last updated**: 2026-09-23（STEP④-A / STEP④-B 完成；LOSS-3 / LOSS-4 完成；LOSS-5 在当前 resolution level 完成并选择 R_OBJECT_SCHEMA=A；PDEP-2 路线选择 AGGREGATE_DECISION_LOSS；R-A / R-B / R-C / R-D 已声明；R_OBJECT 仍未声明；STEP⑤ downstream blocked）

## 1. 当前阶段

Phase: Architecture 2.0 / P4 Redefinition / STEP④-A COMPLETE → STEP④-B COMPLETE / Value Discipline（STEP⑤ NECT mode blocked）
Next action: Resolve the remaining PDEP-2 aggregate decision-loss object gates R-D/R-E/R-F; expectation-specific prerequisites are now explicit; no automatic R-object construction, STEP⑤ entry, or experiment
Gate status: OPEN — STEP① accepted; STEP② accepted; STEP③ passed; STEP④ passed with STEP④-A semantic instantiation COMPLETE and consistency review PASSED; STEP⑤ NECT mode blocked
RQ ID: 尚未分配（正式 RQ registration 尚未发生）
当前活动文档: docs/PDEP2_MIN_AGGREGATE_LOSS_OBJECT_GATE.md

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
| RQ-P4-01 | Architecture-induced Execution State 及其资源生命周期特征 | STEP④ PASS / MCVSD VALID / DG-4A-01 RESOLVED AS RESULT_FORM_DETERMINING / VTYPE=VECTOR / OUTPUT DISCIPLINE=FINITE_REAL_COORDINATEWISE / BINDING_C=VECTOR_COMPOSITION / SEMANTIC INSTANTIATION COMPLETE / VALUE DISCIPLINE COMPLETE / LOSS-3 CLOSED / LOSS-4 CLOSED / LOSS-5 RESOLVED AT CURRENT RESOLUTION LEVEL / PDEP-2 ROUTE=AGGREGATE_DECISION_LOSS / R_OBJECT_SCHEMA=A / R-A=PROJECTION_CANDIDATE / R-B=WORKLOAD_DISTRIBUTION / R-C=EXPECTATION_OVER_WORKLOAD_DISTRIBUTION / R-D=FINITE_REAL / R-E–R-F OPEN / R_OBJECT NOT DECLARED / STEP⑤ DOWNSTREAM BLOCKED / NOT REGISTERED |
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
| P4-A existence criterion | AGGREGATE DECISION-LOSS ROUTE SELECTED / R-A=PROJECTION_CANDIDATE / R-B=WORKLOAD_DISTRIBUTION / R-C–R-F OPEN / R_OBJECT NOT DECLARED / STEP⑤ HISTORICAL FORMULATION RETAINED / R、R_oracle NOT_DEFINED_BY_CURRENT_FRAMEWORK / Δ BLOCKED / FinLoss NOT LEGALLY AVAILABLE / NECT BLOCKED | 路线已选择；下一步仅定义实现该路线所需的最小 aggregate decision-loss object，不自动进入 STEP⑤ |
| Source/Runtime / RQ-F-01 | RETIRED / NOT DEFINED | 不进入 STEP⑤；此前状态不向 P4 转移 |
| Swift implementation | NOT STARTED / NO BASIS | 不因 STEP⑤ 获得授权 |
| Execution-State-oriented Post-Training | HYPOTHESIS / NOT REGISTERED | 不创建新 RQ，不授权实验/实现/测量 |

## 7. Current gate

P4 / RQ-P4-01 candidate
- STEP① 研究对象：ACCEPTED BY HUMAN RESEARCHER
- STEP② Research Question：ACCEPTED / GATE PASSED
- STEP③ Independence：PASS
- STEP④ Estimand：PASS / CLOSED FOR CURRENT FRAME / MFB-SR COMPLETE / SIA COMPLETE / CVSDR COMPLETE / MVSD COMPLETE / VSCA COMPLETE / FSAR COMPLETE / CVSR COMPLETE / CVS-ERR COMPLETE / MCVSD VALID / VTYPE=VECTOR / OUTPUT DISCIPLINE=FINITE_REAL_COORDINATEWISE / BINDING_C=VECTOR_COMPOSITION / SEMANTIC INSTANTIATION COMPLETE / VALUE DISCIPLINE VD-01～VD-05 COMPLETE / DOWNSTREAM DEPENDENCY REVIEW PASSED / CANDIDATE 2 REJECTED / CANDIDATE 1 NOT FROZEN
- LOSS-3 Cost Object：CLOSED / C_LOSS = NEW_INDEPENDENT_C_LOSS / COST_DOMAIN=FINITE_REAL / INFINITE_COST=NOT_PRESENT / C_DEFINEDNESS=TOTAL_ON_DECLARED_DOMAIN
- LOSS-4 Cost Evaluation Interface：CLOSED / C_LOSS : D_C → ℝ / D_C=A×W / D_C CURRENTLY MFI PLACEHOLDER / NO PROBABILISTIC SEMANTICS
- LOSS-5 Aggregation：RESOLVED AT CURRENT RESOLUTION LEVEL / R_OBJECT_SCHEMA=A / R_OBJECT=NOT_DECLARED / NO RISK OR AGGREGATE EVALUATION OBJECT
- PDEP-2 Route：AGGREGATE_DECISION_LOSS / route selected; implementation object not yet declared
- PDEP-2 R-object gate：R-A=PROJECTION_CANDIDATE / R-B=WORKLOAD_DISTRIBUTION / R-C=EXPECTATION_OVER_WORKLOAD_DISTRIBUTION / R-D=FINITE_REAL / R-E=PARTIAL_DEFINEDNESS / R-F=PARAMETERIZED_REGIME / R_OBJECT=NOT_DECLARED / C_LOSS↔R BRIDGE=NOT DECLARED
- PDEP-2 input boundary：W measurable structure=UNDECLARED / μ_W formal object=NOT INSTANTIATED / C_LOSS measurability=UNDECLARED / expectation=SELECTED_AS_AGGREGATION_RULE_NOT_YET_INSTANTIATED
- STEP⑤ Nontrivial Phenomenon Existence Criterion：HISTORICAL FORMULATION RETAINED / NDAC AND SAT_INF_FIN RETAINED AS HISTORICAL GATE LOGIC / R NOT_DEFINED_BY_CURRENT_FRAMEWORK / R_oracle NOT_DEFINED_BY_CURRENT_FRAMEWORK / Δ BLOCKED / FinLoss NOT LEGALLY AVAILABLE / NECT BLOCKED
- STEP⑥–⑨：未开始

### Allowed

- 阅读并维护 `docs/STEP4A_CANONICAL_DECISIONS.md`；
- 维护已完成的 STEP④-B / Value Discipline（VD-01～VD-05）；
- 维护 LOSS-3 / LOSS-4 / LOSS-5 的已声明边界；
- 对 P4-A 主链进行 dependency review，识别在当前 Loss boundary 下仍可独立成立的对象或研究问题；
- 保留历史 STEP⑤、IPR、domain-partition、NDAC、SAT_INF_FIN 文档及 provenance，不进行静默重写；
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
- 将 LOSS-5 schema A 改写成任何隐含的 R / Risk / aggregate object；
- 把历史 STEP⑤ 的 FinLoss、R_s^fin、R_s^nofin、F_s^fin 当作当前正式实例；
- 从自然语言 “cost”、Risk、oracle、D_loss、STEP⑤ notation 或工程常识反向补齐未声明语义；
- 进入 Risk、FinLoss、residual status、NECT mode 或 STEP⑥，除非其自身门禁被独立满足；
- Runtime implementation / research harness / data collection / profiling / performance measurement；
- 自动注册 RQ-P4-01；
- 重新研究 Track B 已闭合的 State lifecycle semantics；
- 将 Execution-State-oriented Post-Training 假设视为已成立。

## 8. Definition Gate

① 研究对象 → ② Research Question → ③ 独立性 → ④ estimand / envelope object definition → ⑤ nontrivial phenomenon existence criterion → ⑥ negative / insufficiency → ⑦ discriminating power → ⑧ information value / cost → ⑨ Path / Harness / Experiment。

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

`Scalarity`、`finiteness`、special-value admissibility 已由 `OutputDiscipline = FINITE_REAL_COORDINATEWISE` 治理。\n`nonnegativity` 未被声明（有限实数可正可负）。`Measurability` 继续 DEFERRED。

Infinity semantics remain:

```
LOSS_INFINITY_PREDEFINED = FALSE
IPR_VALUE                = UNDECLARED
```

STEP④-B is COMPLETE. FinLoss / residual / NECT remain blocked.

## 10.1 STEP④-B / Value Discipline — canonical researcher declarations

STEP④-B / Value Discipline was explicitly declared by the human researcher on 2026-09-23. The agent did not select the semantic values.

### VD-01 · Legal Value Operations

```
VD-01-A  Vector Equality                    = DECLARED
VD-01-B  Coordinate-wise Arithmetic        = DEFERRED
VD-01-C  Vector Difference as Research Value = DEFERRED
VD-01-D  Scalar Functional                 = EXCLUDED
```

`V_a = V_b ⇔ ∀i, v_{a,i} = v_{b,i}`. Equality is declared only; coordinate arithmetic and vector difference are not currently Value-level research operations; scalar functionals `f : ℝ^k → ℝ` are excluded at the Value layer.

### VD-02 · Coordinate Comparability

```
VD-02-A  Cross-Vector Coordinate Identity       = DEFERRED
VD-02-B  Cross-Vector Coordinate Comparability  = DEFERRED
VD-02-C  Coordinate Homogeneity                 = DEFERRED
```

`(j,i)` is only an internal positional address. Same-index coordinates across different `V_j` are not declared to have shared semantic identity, comparability, or homogeneity.

### VD-03 · Order Relation

```
VD-03-A  Intra-Vector Positional Order       = DECLARED
VD-03-B  Positional Addressing / Projection  = DECLARED
VD-03-C  Equality-only Same-Index Pairing    = DECLARED
VD-03-D  Value / Magnitude / Preference Order = DEFERRED
VD-03-E  Cross-Vector Positional Semantics    = DEFERRED
VD-03-F  Composition-Induced J Order          = DEFERRED
```

`Order = VECTOR_POSITIONAL` is structural position only. It does not introduce magnitude order, preference order, loss order, cross-vector coordinate semantics, or any ordering of `J`.

### VD-04 · Sign / Zero Discipline

```
VD-04-A  Zero Membership / Zero Admissibility       = DECLARED
VD-04-B  Positive / Negative Sign Admissibility     = DECLARED
VD-04-C  Zero as Semantic Value                     = DEFERRED
VD-04-D  Sign as Semantic Attribute                 = DEFERRED
VD-04-E  Non-Negativity / Positivity Constraint     = DEFERRED
VD-04-F  Sign-Based Comparison / Ordering           = DEFERRED
```

`0`, positive values, and negative values are admissible finite-real coordinate states. No zero semantics, sign semantics, non-negativity/positivity constraint, or sign-based ordering is declared.

### VD-05 · Value ↔ Loss / Risk Boundary

```
VD-05-A  Value → Loss Mapping                = DEFERRED
VD-05-B  Value → Risk Mapping                 = DEFERRED
VD-05-C  Loss Domain / Finiteness              = DEFERRED
VD-05-D  Loss Sign / Non-Negativity            = DEFERRED
VD-05-E  Loss Order / Minimization Semantics   = DEFERRED
VD-05-F  Value-to-Loss Functionalization      = DEFERRED
```

No Value → Loss / Risk semantic channel is open. `OutputDiscipline = FINITE_REAL_COORDINATEWISE` constrains Value coordinates only; it does not constrain Loss. `LOSS_INFINITY_PREDEFINED = FALSE` remains unchanged. Value-level scalarization remains excluded; an independent Loss functional is only deferred and is not currently authorized.

### STEP④-B semantic boundary

```
Legal:
  finite-real coordinatewise Vector
  coordinate position / addressing
  coordinatewise Vector Equality
  Vector Composition
  zero admissibility
  positive / negative coordinate admissibility

Not currently authorized:
  coordinate arithmetic
  vector difference / residual
  cross-vector coordinate semantics
  coordinate comparability / homogeneity
  magnitude / preference / loss ordering
  J ordering
  zero/sign semantic interpretation
  non-negativity / positivity constraint
  Value → Loss
  Value → Risk
  Loss finiteness / sign / minimization
  scalarization
```

Therefore:

```
VALUE DISCIPLINE = COMPLETE
VALUE ↔ LOSS/RISK CHANNEL = CLOSED
```

Completion of STEP④-B does not authorize Residual, FinLoss, NECT, STEP⑤, Runtime implementation, harness, data collection, profiling, performance measurement, or experiment.

## 10.1 Loss-layer boundary

LOSS-3 and LOSS-4 are closed at the following current interface:

```
C_LOSS : D_C → ℝ
D_C = A × W
```

No probability-space, random-variable, measurability, distribution, expectation, optimization, or experimental semantics are present.

LOSS-5 is complete at its current resolution level:

```
R_OBJECT_SCHEMA = A
R_OBJECT = NOT_DECLARED
R = NOT_DEFINED_BY_CURRENT_FRAMEWORK
R_oracle = NOT_DEFINED_BY_CURRENT_FRAMEWORK
Δ = BLOCKED
FinLoss = NOT LEGALLY AVAILABLE
```

## 10.2 STEP⑤ current status after LOSS-5

The historical STEP⑤ formulation is preserved but is not instantiated as the current downstream formal object.

```
historical STEP⑤ formulation
        ↓
LOSS-5 resolution
        ↓
R_OBJECT_SCHEMA = A
        ↓
R layer not instantiated
        ↓
R_s^fin / R_s^nofin / F_s^fin remain conditional / historical
        ↓
NECT remains BLOCKED
        ↓
STEP⑥ not entered
```

NDAC and SAT_INF_FIN remain historical STEP⑤ gate logic. This update does not declare them mathematically invalid; it prevents their downstream execution from being treated as currently authorized when their required loss objects are absent.

## 10.3 Research boundary after LOSS-5

The current formal loss chain stops at C_LOSS. No current framework object connects C_LOSS to R.

Therefore the next review is not “complete STEP⑤ by filling missing formulas”. It is a dependency review of the P4-A research proposition itself:

```
P4-A
 ↓
STEP④ semantic/value objects
 ↓
C_LOSS
 ↓
[no current R layer]
 ↓
STEP⑤ downstream blocked
```

The proposition-level route has now been selected explicitly:

```
PDEP-2 ROUTE = AGGREGATE_DECISION_LOSS
```

The route selection does not define the required R object. R-A has now been declared as PROJECTION_CANDIDATE; R-B has now been declared as WORKLOAD_DISTRIBUTION; R-C/R-D/R-E/R-F remain open. The C_LOSS↔R bridge remains undeclared. The workload-distribution declaration does not instantiate W measurability, μ_W, C_LOSS measurability, or expectation. Until the aggregate object is explicitly declared, R, R_oracle, Δ, and FinLoss remain unavailable.

## 11. Governance

The R-B workload-distribution declaration adds no probability-space, measure, expectation, experiment, harness, implementation, or measurement authorization.
