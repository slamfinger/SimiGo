# SimiGo-Lab Session Continuity

> 用于新会话恢复研究上下文；权威语义以 `docs/RESEARCH_STATE.md` 为准。本文件是连续性索引，不覆盖 RESEARCH_STATE。

**保存时间**：2026-09-23

## 项目身份与仓库边界

- 当前研究仓库：`slamfinger/SimiGo-Lab`
- 产品/实现仓库：`slamfinger/SimiGo`
- 本阶段只推进 SimiGo-Lab 的研究状态，不将研究声明直接转化为产品实现。
- 新会话恢复入口：先读取 `docs/RESEARCH_STATE.md`，再读取本文件；不得用旧会话记忆覆盖仓库权威状态。

## 当前研究阶段

- Phase：Architecture 2.0 / P4 Redefinition
- STEP④ semantic instantiation：COMPLETE
- STEP④-B / Value Discipline：COMPLETE
- Loss layer boundary：reached
- LOSS-3：CLOSED
- LOSS-4：CLOSED
- LOSS-5：SUSPENDED_AT_CURRENT_RESOLUTION_LEVEL
- PDEP-2：AGGREGATE_DECISION_LOSS
- R-A through R-F：DECLARED
- R-ASM-A：C_LOSS
- R-ASM-B：REGIME_INDEXED_WORKLOAD_DISTRIBUTION_FAMILY
- R-ASM-C：DECISION_RULE_FAMILY_WITH_OPTIMIZATION
- R-ASM-D：PARAMETER_INDEXED_PROBABILITY_MEASURE_FAMILY_WITH_MEASURABILITY_REQUIREMENT
- R-ASM-E：COMPOSITE_ADMISSION_PREDICATE
- R-ASM-F：COMPOSITE_SIGNATURE
- R-ASSEMBLY-1A：COMPOSITE_PROJECTION_RULE_PAIR
- R-ASSEMBLY-1B：JOINT_COMPOSITE_OUTPUT_MECHANISM
- R-ASSEMBLY-1C：C3
- R-ASSEMBLY-2：D2
- R-ASSEMBLY-3：F2
- R-ASSEMBLY-4：G2
- R-ASSEMBLY-5：H2
- R-ASSEMBLY-6：I2
- R-ASSEMBLY-7：J1
- R-ASSEMBLY-8：K3
- R-ASSEMBLY-9：L3
- R-ASSEMBLY-10：M4
- R-INTERNAL-1：P4
- R-INTERNAL-2：δ3
- R-INTERNAL-3：θ2
- R-INTERNAL-4：G4-4
- R-INTERNAL-5：L5-3
- R-INTERNAL-6：E6-4
- R-INTERNAL-7：E7-B
- R-INTERNAL-8：E8-C
- R-INTERNAL-9：E9-B
- R-INTERNAL-10：E10-B
- R-INTERNAL-11：E11-B
- R-INTERNAL-12：K3-A / VALUE_INFIMUM
- R-INTERNAL-13：K3-B / OPT_FINITE_VALUE_DOMAIN

## 当前已声明的内部接口

```
P : PROJECTION_CANDIDATE
δ : DECISION_GENERATION_PARAMETER
θ : REGIME_PARAMETER

𝒢_adm(P) = ADMISSIBLE_DECISION_RULE_FAMILY
𝒢_adm(P) ⊆ {g | g : W → A}

L : Dom(L) → ℝ

(g,P,θ) ∈ Dom(L)
    ⇔
g ∈ 𝒢_adm(P)
∧
E_θ[C_LOSS(g(W),W)] 合法且为有限实数

R(P,θ)
=
OPT_{g ∈ 𝒢_adm(P), (g,P,θ)∈Dom(L)}
L(g;P,θ)

{g ∈ 𝒢_adm(P) | (g,P,θ) ∈ Dom(L)} ≠ ∅

R(P,θ) ∈ ℝ
```

其中：

- E7-B：Dom(L) 中的三元组必须满足 `g ∈ 𝒢_adm(P)`。
- E8-C：进一步声明 Dom(L) 与 admissibility + 合法有限实数期望之间的双向条件。
- E9-B：有效优化域同时受 `𝒢_adm(P)` 与 Dom(L) 约束。
- E10-B：有效优化域非空。
- E11-B：aggregate optimization output `R(P,θ)` 为有限实数。

## 必须保持的语义区分

```
effective optimization domain nonempty
≠
optimizer exists
≠
optimum attained
≠
OPT = min / inf / argmin
```

当前没有声明 optimizer existence、attainment，也没有选择 `min`、`inf`、`argmin` 或其他具体 OPT construction。

## 尚未声明/仍被阻断

- R_OBJECT：NOT_DECLARED
- R_ASSEMBLY：OPEN
- R_ORACLE：NOT_DEFINED
- Δ：BLOCKED
- FinLoss：NOT LEGALLY AVAILABLE
- NECT：BLOCKED
- STEP⑤：NOT ENTERED
- STEP⑥：NOT ENTERED
- EXPERIMENT AUTH：NONE
- HARNESS AUTH：NONE
- 不得据此自行进入 implementation / harness / data collection / profiling / measurement / experiment。

## Value / Loss 边界

Value layer 已冻结：

```
V_j ∈ ℝ^k
C = [V_1,V_2,...]
```

- 坐标为有限实数；不含 infinity / NaN / missing。
- A、W、W_D、J 等仍为抽象 carrier；不得隐式补充 membership/order/cardinality。
- Value layer 不进行 scalar functionalization。
- Value ↔ Loss/Risk channel 已关闭。
- 不隐式等同 k 与 J。
- C_LOSS 已作为独立新对象声明；其当前成本域为有限实数，definedness 在已声明域上为 total。

## 历史内容限制

历史公式：

```
R(P;θ) = inf_{δ∈Δ(I_P)} E_θ[C(δ(I_P),W)]
D(P;θ) = R(P;θ) - R_oracle(θ)
```

仅作为历史研究内容保留，不得自动恢复为当前定义。

特别是：
- 历史 δ(I_P) 不恢复。
- 不引入新的 δ optimization domain。
- R_ORACLE 当前仍未定义。
- Δ 当前仍 blocked。

## 继续工作的操作规则

1. 用户说“继续”时，先检查 `docs/RESEARCH_STATE.md` 和是否已经存在下一道 R-INTERNAL gate。
2. 若下一 gate 尚不存在，只提出下一语义决策面及选项，不替研究者选择。
3. 用户直接声明 `R-INTERNAL-N = EX` 等语义值时，按既定流程记录并提交到 main；若与已有 gate ID 冲突，必须先指出冲突，不得静默覆盖。
4. 每次声明应形成历史记录（`docs/07-history/`）并同步更新 `docs/RESEARCH_STATE.md`。
5. GitHub 仓库是连续性与权威状态的可恢复来源；不要声称账户级 ChatGPT Memory 已被写入。
6. 研究者保留最终 semantic authority；助手负责检查一致性、列出决策面、记录与验证。

## 最近关键提交

- R-INTERNAL-13 历史：由当前提交记录
- R-INTERNAL-12 历史：由当前提交记录
- R-INTERNAL-11 历史：`dec4c22a91290eb96c0e791ded8e5a27e5680550`
- R-INTERNAL-11 state：`bad597bd954e7c7dbb3e584f0e2869a75ff392fb`
- R-INTERNAL-10 state：`3efc91ddab3df236ca1655c1b19e029913efe5e4`
- R-INTERNAL-9 state：`418f82209540db2473731949b047804b768ac6c5`
- R-INTERNAL-8 state：`c2f212f150bd536b7063a7a58167313cdd2e7a41`

## 新会话最短恢复指令

```
继续 SimiGo-Lab。
读取 docs/RESEARCH_STATE.md 和 docs/SESSION_CONTINUITY.md。
以仓库状态为唯一权威，继续下一道尚未声明的 R-INTERNAL gate。
```
