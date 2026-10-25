# Architecture 2.0 — P4-A STEP④-A Minimal Cost Value-Semantics Declaration Contract

**Date:** 2026-09-23\
**Status:** MCVSD ADOPTED / `VType` UNDECLARED / `OutputDiscipline` UNDECLARED / SEMANTIC INSTANTIATION REQUIRES EXPLICIT RESEARCHER DECLARATION\
**RQ:** 尚未分配；本文不构成 RQ 注册

## 1. Contract purpose

CVS-ERR 已证明 `V_j` 无法从 STEP①–④ 既有材料中唯一恢复。

因此本 contract 只定义必须声明什么，不填写声明内容。

MCVSD 不选择：

```text
[0,+infinity)
```

也不选择：

```text
[0,+infinity]
```

更不选择 vector 或 record。

## 2. Minimal contract

```text
MCVSD = (
    SourceStatus,
    VType,
    OutputDiscipline
)
```

### 2.1 `SourceStatus`

`SourceStatus` 记录值语义来源。

未来合法 declaration 值只能属于：

```text
EXPLICIT_EXISTING
NEW_DECLARATION
DERIVED
```

当前状态为：

```text
SourceStatus = NEW_DECLARATION_REQUIRED
```

CVS-ERR 已排除 `EXPLICIT_EXISTING`；在 loss object completion 完成前，`DERIVED` 也不可用。

### 2.2 `VType`

`VType` 必须唯一回答：

```text
V_j = ?
```

它必须说明：

1. 是 shared value space 还是 per-component value-space family；
2. 每个 `V_j` 的 carrier/type；
3. 不同 `j` 的 value space 是否等同或需要 coercion。

当前：

```text
VType = UNDECLARED
```

### 2.3 `OutputDiscipline`

`OutputDiscipline` 必须回答：

```text
C_j(a,w) in ?
```

它必须显式说明是否允许：

1. non-finite values；
2. special values；
3. negative values；
4. 其他非标准 cost values。

当前：

```text
OutputDiscipline = UNDECLARED
```

## 3. Order 不进入 MCVSD

```text
Order notin MCVSD
```

当前任务是确定：

```text
V_j 是什么？
C_j 的合法输出是什么？
```

不是确定：

```text
V_j 如何排序？
```

若后续 Risk / loss comparison 证明需要 order structure，必须单独建立：

```text
Value Order Declaration
```

因此三层不得混合：

```text
Value Type -> Output Discipline -> Order
```

## 4. MCVSD excludes

MCVSD 不包含、也不解决：

1. `C` finite-valuedness proof；
2. `C` measurability；
3. `C` integrability；
4. expectation；
5. Risk definition；
6. Oracle definition；
7. `D_loss`；
8. `FinLoss`；
9. rate-level finite-loss domain；
10. NECT；
11. IPR decision；
12. experiment design。

尤其是：

```text
MCVSD != finite-valuedness proof
```

它只允许研究者声明 value space 与 output discipline；证明其数学性质属于后续层。

## 5. MCVSD 也不解决 `Binding_C`

MCVSD 只处理 value type 与 output discipline。

它不回答：

```text
C = Binding_C((C_j)_j)
```

因此不得把：

```text
C = sum_j C_j
```

或其他聚合方式偷渡进本 contract。

`Binding_C` 仍是单独 open field。

## 6. Instantiation boundary

下一步是：

```text
MCVSD Semantic Instantiation
```

必须由 human researcher 实际确定：

1. `VType`；
2. `OutputDiscipline`。

特别要显式回答：

> 成本组件 `C_j` 是否被定义为 finite nonnegative scalar-valued object？

如果答案是 yes，才可建立：

```text
V_j = [0,+infinity)
```

并重新检查其对：

```text
C, R, R_oracle, D_loss, FinLoss
```

的影响。

如果答案不是 yes，则必须按所选真实语义继续构造。

这一次不得由形式记号、agent preference 或 notation 自动作答。

## 7. Ruling

```text
MCVSD_STATUS                    = ADOPTED
MCVSD                           = (SourceStatus, VType, OutputDiscipline)
CURRENT_SOURCE_STATUS           = NEW_DECLARATION_REQUIRED
VTYPE                           = UNDECLARED
OUTPUT_DISCIPLINE               = UNDECLARED
ORDER                           = DEFERRED
MEASURABILITY                   = DEFERRED
FINITE_VALUEDNESS               = DEFERRED
BINDING_C                       = SEPARATE OPEN FIELD
RISK                            = BLOCKED
```

## 8. Current state

```text
MCVSD_STATUS                    = ADOPTED
SOURCE_STATUS_FIELD             = REQUIRED
CURRENT_SOURCE_STATUS           = NEW_DECLARATION_REQUIRED
VTYPE                           = UNDECLARED
OUTPUT_DISCIPLINE               = UNDECLARED
ORDER                           = DEFERRED
MEASURABILITY                   = DEFERRED
FINITE_VALUEDNESS               = DEFERRED
BINDING_C                       = SEPARATE OPEN FIELD
MCVSD_SEMANTIC_INSTANTIATION    = REQUIRED
STEP4_B_RISK_REVIEW             = BLOCKED
FINLOSS_DETERMINACY             = BLOCKED
RESIDUAL_STATUS                 = BLOCKED
NECT_MODE                       = BLOCKED
STEP⑥                           = NOT ENTERED
RQ                              = NOT ASSIGNED
EXPERIMENT AUTHORIZATION        = NONE
```

**Governance:** no implementation / harness / profiling / data collection / measurement authorization is created by this document.
