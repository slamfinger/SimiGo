# SimiGo-Lab Research State

> **This file is the authoritative snapshot of the current SimiGo-Lab research state.
> Conversation memory must not override it.**

**Last updated**: 2026-09-23（MVSD complete：minimal required declaration is carrier/type family；no specific `V_j` selected）

## 1. 当前阶段

Phase: Architecture 2.0 / P4 Redefinition / STEP④-A Minimal Value-Space Declaration Complete（STEP⑤ NECT mode blocked）
Next action: Value-Space Candidate Audit：逐一审查 finite scalar、extended scalar、vector、typed record 等候选是否有冻结证据支持或排除；不得直接选择
Gate status: OPEN — STEP① accepted; STEP② accepted; STEP③ passed; STEP④ passed with typed-codomain review open; STEP⑤ NECT mode blocked
RQ ID: 尚未分配（正式 RQ registration 尚未发生）
当前活动文档: docs/07-history/ARCHITECTURE_2.0_P4A_STEP4A_MINIMAL_VALUE_SPACE_DECLARATION_REVIEW_20260923.md

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
| RQ-P4-01 | Architecture-induced Execution State 及其资源生命周期特征 | STEP④ PASS / MFB-S TRUE / SIA COMPLETE / VSPACE NOT UNIQUELY DETERMINED / MVSD COMPLETE / CANDIDATE AUDIT NEXT / NECT MODE BLOCKED / NOT REGISTERED |
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
| P4-A existence criterion | STEP⑤ OPEN / EC5 REJECTED / NDAC ACCEPTED / DOMAIN PARTITION ADOPTED / MVSD COMPLETE / NO SPECIFIC V_J SELECTED / NECT MODE BLOCKED | 只允许进行 Value-Space Candidate Audit，不授权实验 |
| Source/Runtime / RQ-F-01 | RETIRED / NOT DEFINED | 不进入 STEP⑤；此前状态不向 P4 转移 |
| Swift implementation | NOT STARTED / NO BASIS | 不因 STEP⑤ 获得授权 |
| Execution-State-oriented Post-Training | HYPOTHESIS / NOT REGISTERED | 不创建新 RQ，不授权实验/实现/测量 |

## 7. Current gate

P4 / RQ-P4-01 candidate
- STEP① 研究对象：ACCEPTED BY HUMAN RESEARCHER
- STEP② Research Question：ACCEPTED / GATE PASSED
- STEP③ Independence：PASS
- STEP④ Estimand：PASS / CLOSED FOR CURRENT FRAME / MFB-SR COMPLETE / SIA COMPLETE / CVSDR COMPLETE / MVSD COMPLETE / NO SPECIFIC V_J SELECTED / CANDIDATE 2 REJECTED / CANDIDATE 1 REFORMULATED BLOCKED
- STEP⑤ Nontrivial Phenomenon Existence Criterion：OPEN / NDAC ACCEPTED / SAT_INF_FIN DEFINED / DOMAIN PARTITION STRUCTURAL / IPR UNDECLARED / REVIEW-2 BLOCKED / NECT MODE BLOCKED
- STEP⑥–⑨：未开始

### Allowed

- 继续定义与对抗 STEP⑤ existence criterion；
- 使用 NDAC 作为 NECT domain admission condition，并裁定 extended-real vs finite-finite descent mode；
- 使用 SAT_INF_FIN 审查 `+infinity -> finite` 的 domain / order / substantive / degeneracy identity；
- 声明并审查 Infinity Provenance Rule；若 loss value 与 boundary encoding 混合，先定义 typed envelope；
- 审查 finite-loss codomain、ordered extended-loss codomain 或 typed/tagged envelope 三类最小声明；
- 审查 finite completeness 与 no-finite-loss member 是否必须作为独立 typed 对象；
- 审查 envelope finite completeness、`R_s^fin` 与 `B_s=R_s\R_s^fin` 的 boundary status；
- 采用并攻击 `R_s^fin/R_s^nofin` domain partition 与 `F_s^fin:R_s^fin->[0,+infinity)`；
- 裁定 `FinLoss(P,theta)` definition 与 `R_s^nofin` residual status；
- 完成 STEP④ loss object completion：声明 `C/R/D_loss` codomain、expectation/inf conditions、oracle value discipline 与 excess-loss value discipline；
- 审查并冻结 MCSC abstract field schema 的 product-position semantics 与 arrow semantics；
- 建立全局 P4-A formal basis declaration，覆盖 foundational universe、product/arrow semantics、application/equality/substitution rules；
- 使用已冻结 `B_min={Pair Formation,Function Slot,Application,Typed Equality}`；
- 审查 Cost Value-Space Determinacy：STEP①–④ 是否唯一确定 `V_j`；
- 审查并分离 `V_j` 的 carrier/type、admissible-value discipline、order、measurability、definedness 与 finiteness；
- 使用已冻结的 L、D、sigma_D、S_det、rate convention、oracle normalization 与 scope；
- 设计最低成本的概念反例；
- 如确有必要，可要求本地 agent 执行已获授权的研究动作，并由 ChatGPT 获取、审查、分析结果；当前 STEP⑤ 尚未授予此类实验权限；
- 读取 Track B / Track E 历史资产作为背景约束，但不得转移其证据为 P4 结论。

### Forbidden

- 自动把 P4 candidate 升级为注册 RQ；
- 进入 STEP⑥–⑨；
- Runtime implementation / research harness / data collection / profiling / performance measurement；
- 预设 frontier 非空、非退化、低码率、共同形状或 Runtime usefulness；
- 把 NECT 叙述为 “frontier existence”，或把 strict descent 等同于 tradeoff / value / stable shape；
- 把 envelope object defined、`P_AS` 非空、单个 endpoint、L₀ trivial encoder、有限候选观察或未经证明的 infimum 断言自动视为 EC_T 通过；
- 把 `failure to establish EC_T` 等同于 `EC_T` 为假，或把 domain insufficient / flat negative / evidence insufficiency 合并为同一种 negative；
- 把 `EVIDENCE_INSUFFICIENT` 当作 STEP⑤ target output，或在 mode 未裁定时宣布 NECT true/false；
- 把 `+infinity -> finite` 是否属于 NECT 当作已决定；
- 把 evaluation failure / missing-data 的 `+infinity` 当作合法 loss value，或把 degeneracy risk 当作价值判断依据；
- 把 `+infinity` 的 loss-value / boundary-encoding 混用当作同一 NECT 对象，或在 IPR 未声明时裁定 NECT mode；
- 把 `IPR_VALUE=UNDECLARED` 等同于 `IPR=NA`，或凭实验/估计结果反推 codomain；
- 把 STEP⑤ 引入的 `[0,+infinity]` 回溯解释为已有 `+infinity` ordered loss-value 承诺，或因 typed envelope 更安全而直接选择 typed split；
- 把 “finite completeness 未证明” 等同于 `B_s` 非空，或把 no-finite-loss region 静默当作 applicability boundary；
- 为进入 `R_s^nofin` 而重新引入 `+infinity` loss value，或在 Review-3 前宣布 NECT 只能定义于 `R_s^fin`；
- 在 `FinLoss` 未被 STEP④ 唯一确定前裁定 Review-2、Candidate 1/3 或 NECT mode；
- 在 cost signature 未冻结前选择 `V_j` 的 finite/extended/vector/typed discipline、measurability，或用 natural-language cost terms 直接充当 `J`；
- 在 product/arrow semantics 未声明前假定 total function、set-theoretic product、`W_D=W`、shared `V_j` 或具体 component cardinality；
- 用 cost-local `×/->` patch替代全局 formal basis，或在 placeholder reading 外隐含选择 set/type/product/total/partial semantics；
- 把 minimal formal interface 的 placeholder application/equality/substitution 当作真实数学语义，或声称它已支持 MCSC semantic instantiation；
- 把 Projection 或 Substitution 重新偷渡进 `B_min`，或在 minimal interface 下宣称 total/measurable/finite-valued function；
- 在 Cost Value-Space Determinacy Review 前选择 `V_j` 的 finite scalar、extended scalar、vector、typed record 或具体 cost aggregation；
- 从自然语言 “cost” 或后续 `D_loss>=0` 反向确定 `V_j`；
- 把 carrier declaration、admissible-value discipline、order structure、measurability、definedness 或 finiteness 压缩成同一声明；
- 把 MCSC skeleton 的 carrier/value symbols 解释为具体 finite scalar、extended scalar、vector 或 typed record，或把 `Binding_C` 直接选为 sum/tuple/product/aggregation；
- 重新研究 Track B 已闭合的 State lifecycle semantics；
- 将 Execution-State-oriented Post-Training 假设视为已成立。

## 8. Definition Gate

① 研究对象 → ② Research Question → ③ 独立性 → ④ estimand / envelope object definition → ⑤ nontrivial phenomenon existence criterion → ⑥ negative / insufficiency criterion → ⑦ discriminating power → ⑧ information value / cost → ⑨ Path / Harness / Experiment。

## 9. P4 方法原则

Architecture 2.0 采用：当前代表性架构 → 最小抽象 → 新架构反例 → 最小必要扩展 → 再验证。

通用性由真实架构反例推动，而不是由想象中的未来模型推动。没有反例，不增加抽象层；“不能泛化”本身是合法研究结果。

## 10. 当前 STEP⑤ 入口约束

STEP④ 已将 estimand 固定为 frame-indexed Achievable Static Frontier。关键定义资产包括：

- S_det：确定性、预注册静态派生策略族；
- 固定 Rate counting convention；
- D=(A,C,sigma_D,Pi_W)；
- sigma_D：冻结成本族的最小因子化见证；
- Eval=(budget, estimator, sampling)；
- theta_tilde：联合决策相关层的 workload-regime 分布 / pushforward；
- semantic 与 deployment-economic frontier 分轨，后者显式带 N 或更一般 mu_D；
- 跨架构比较仅在公共可达 rate domain 上进行；不可评估或不可达区间记录为 applicability boundary；
- Target ≠ Estimator ≠ Observed frontier；STEP④ 不证明 finite-sample identifiability。

STEP⑤ 当前候选是 NECT（原 EC_T），但存在两个未裁决 mode：`NECT_E` 检测整个 extended-real envelope 的 strict descent，允许 `+infinity -> finite`；`NECT_F` 只检测 finite-loss region 内部的 descent。semantic 与 deployment-economic 分轨判定。NECT 是 target-level nontrivial phenomenon existence，不是 frontier object existence，不要求 infimum 被实际策略达到，也不是 finite-sample observation criterion。

`SAT_INF_FIN` 已定义，用于在 mode 裁定前检查 `+infinity -> finite` 的 domain identity、order identity、substantive identity 和 degeneracy annotation。当前进一步要求 Infinity Provenance Rule：`+infinity` 必须声明为 ordered loss value、no-finite-loss-member boundary encoding、mixed 或 evaluation NA。`MIXED` 必须先 typed split；`NA` 不属于 target envelope；finite-loss realizability onset 不得静默并入 NECT。

STEP⑤ 曾临时使用 envelope contract：`R_s` 上可行集非空，loss codomain 为 `[0,+infinity]`；但 Candidate 2 已被拒绝，因此当前 loss codomain unresolved。infimum existence 不要求 attainment。`NDAC(s): |R_s^tau|>=2` 已接受为 domain admission condition，不是 NECT 谓词本体。STEP⑤ target output 只有 `DOMAIN_INSUFFICIENT / NECT_TRUE / NECT_FALSE`；`EVIDENCE_INSUFFICIENT` 属于正交 evidence layer，不得由 STEP⑤ 输出。

IPR declaration audit 结果为 `UNDECLARED / FAILED`：当前原始 frame 只声明 Bayes risk 与 oracle excess loss，未声明成本/风险/loss codomain，也未声明 `+infinity` 是 ordered loss value、no-finite-loss sentinel 还是 evaluation NA。STEP④ infinity-loss entitlement ruling 进一步判定 `CANDIDATE_2 [0,+infinity] = REJECTED`，因为 STEP⑤ 引入的 extended-real codomain 不能回溯为既有 `+infinity` loss-value 承诺。

Domain/codomain orthogonality ruling 已取代 “证明 finite completeness over `R_s`” 的路线。当前采用 partition：`R_s=R_s^fin ⊔ R_s^nofin`，并定义 Candidate 1 reformulated 为 `F_s^fin:R_s^fin->[0,+infinity)`。`R_s^nofin` 不编码为 `+infinity`，也不参与 loss order。`FinLoss(P,theta)` definition 与 residual status 仍待裁定；完成前不得裁定 NECT domain 或 mode。

Review-1 已完成并裁定 `FinLoss` not uniquely determined。policy-level `FinLoss(P,theta)` 与 rate-level admission set `R_s^FL` 分层；冻结 frame 未声明 `C` codomain/finiteness、expectation existence、`Delta(I_P)` nonemptiness/inf convention、oracle finiteness 或 `D_loss` codomain。因此 STEP④ loss object definition incomplete，Review-2、Candidate 1 reformulated 与 NECT mode 均 blocked。

STEP④-A Cost Object audit 已完成：`C_OBJECT_COMPLETE=FALSE`。现有 frame 只有 declared cost function 与 factorization identity `C_j(a,w)=C'_j(a,sigma_D(w))`，未声明 `J`、exact domain、codomain、measurable spaces、measurability 或 pointwise value discipline。factorization equality 的 value space 仅是隐含的。STEP④-B Risk Well-definedness 被 blocking；不得为 NECT 便利倒推 `C` 的 finiteness 或 scalar codomain。

Cost Signature audit 进一步判定 `COST_SIGNATURE_UNIQUELY_DETERMINED=FALSE`。自然语言 hints `recomputation/migration/capacity` 不能直接当作 `J`；`A/W` 仅为符号，`W_D` 缺失，`V_j` 未声明，`C_j/sigma_D/C'_j` 仅为 symbol-level，equality space 与 `C` binding 未声明。下一步只能冻结最小 signature contract；value discipline 与 measurability 继续 deferred。

Minimal Cost Signature Contract skeleton 已采纳。它只冻结 formal positions：`J/A/W/W_D/(V_j)/(C_j)/sigma_D/(C'_j)/(=_{V_j})/Binding_C`，并给出 typed signatures `C_j:A×W→V_j`、`sigma_D:W→W_D`、`C'_j:A×W_D→V_j`。这不选择 `J` 成员、value discipline、measurability 或 `Binding_C` 的组合形式；semantic instantiation 仍 open，STEP④-B blocked。

Abstract Field Declaration Audit 已裁定 MCSC 可作为 well-formed placeholder schema，但不添加 substantive structural constraints。`J` 的 cardinality/nonemptiness、component uniqueness、carrier instantiation、`V_j` discipline、equality notion 与 `Binding_C` kind 均 deferred。新发现的 formal gaps 是 `PRODUCT_POSITION_SEMANTICS=UNDERDECLARED` 与 `ARROW_SEMANTICS=UNDERDECLARED`；完成二者前不得进入 value discipline 或 Risk review。

Product/Arrow formal basis audit 进一步判定：P4-A 没有统一可追溯的 `×/->` 数学语义；MCSC 只能读作 signature placeholders。该缺口是全局 formal basis 问题，不是 Cost Object 局部问题。下一步必须建立全局 formal basis declaration，覆盖 foundational universe、product/arrow semantics、application/equality/substitution rules；完成后才可回到 value discipline。

Minimal Formal Interface Sufficiency Review 进一步裁定路径为 split：MFI conditionally sufficient。它足以支撑 notation governance 和 MCSC placeholder positions，包括 pair formation、function slot、application placeholder、typed equality placeholder 与 substitution placeholder；但不足以实例化 cost semantics、判定 application definedness、断言 equality truth 或证明 substitution rule。因此不需要立即选择完整 foundation，也不得触发 M2 停摆；MCSC semantic instantiation 在 MFI interpretation 完成前保持 blocked。

MFB-SR 已按更窄裁定收口：`MINIMAL_FORMAL_BASIS_SUFFICIENT=TRUE`，但 `B_min` 仅包含 Pair Formation、Function Slot、Application 与 Typed Equality。Projection 与 Substitution 均 `NOT_REQUIRED`。这 supersede 前版将 substitution 作为 placeholder 的做法。全局 formal basis 仍只是 minimal interface，完整 foundation 未声明；product/arrow mathematical semantics 未声明。

Semantic Instantiation Audit 已完成：MCSC formally well-formed，但 not semantically instantiated。字段裁定为 `J/A/W/W_D/C_j/C'_j/Binding_C=UNDERDECLARED`、`V_j=UNDECLARED`、`σ_D=STRUCTURALLY PLACED / SEMANTICALLY UNDERDECLARED`、`=_{V_j}=MINIMALLY DETERMINED`。`Binding_C` 不得被默认为求和；合法顺序必须从 value space 到 binding、semantic definition、definedness、finiteness、measurability、Risk。下一步是 Cost Value-Space Determinacy Review。

Cost Value-Space Determinacy Review 已完成：`VSPACE_UNIQUELY_DETERMINED=FALSE`。自然语言 “cost”、cost-component hints 与 factorization equality 都只能确定 cost-related role 或 typed comparison position，不能确定 scalarity、order、finiteness、extendedness 或具体 carrier。后续 Risk 结构也不得反向补写 `V_j`。候选 finite scalar、extended scalar、vector、typed record 仅登记，不选择。下一步是 Minimal Value-Space Declaration Review。

Minimal Value-Space Declaration Review 已完成：使 `V_j` determinate 的最小要求是声明 carrier/type family `(V_j)_{j∈J}`。Value discipline、order structure、measurability、definedness 与 finiteness 均为 separate layers。若未来选择 `V_j=[0,+∞)`，必须记录为新的 Value-Space Instantiation；若选择 extended scalar `[0,+∞]`，必须重新面对 IPR review。当前没有任何具体 `V_j` 被选择。下一步是 Value-Space Candidate Audit。

在 Candidate 1 reformulated 中，`IPR_VALUE` 仍记录为 `UNDECLARED`；但 `R_s^nofin` 不再需要 infinity sentinel。若未来出现 actual infinity loss 的既有语义证据，必须重新进入 typed-codomain review，不得通过 residual domain 静默引入。

## 11. Governance

本次 STEP④→STEP⑤ 是研究治理状态转换。没有新增实验、harness、implementation 或 measurement authorization。
