# Architecture 2.0 — P4-A STEP④ 收口与 STEP⑤ 开放

**Date:** 2026-09-22  
**Status:** STEP④ PASS / STEP⑤ OPEN  
**RQ:** 尚未分配；本文件记录治理状态转换，不构成 RQ 注册

## 1. STEP④ 收口裁定

P4-A STEP④ Estimand 经连续攻击后正式收口。当前 estimand 采用 frame-indexed Achievable Static Frontier，不存在脱离测量框架的无索引“the frontier”。

核心形式为：

F_AS,X^(L,D,S_det)(R; theta_tilde) = inf over P in P_AS(X; S_det), Rate(P) <= R, of D_X(P; theta_tilde)

其中定义域为架构 X 在冻结 Description Language、Decision Problem Family 与确定性静态派生策略族下的可达 rate domain R_X。

STEP④ 明确完成以下闭合：

- S 的输出必须确定：每个策略为确定性函数；若存在自由参数/平局规则，则必须逐项预注册为独立策略成员，或明确采用全部可能输出集合。当前采用 S_det：确定性策略族作为 estimand 基础。
- Rate 计数约定必须冻结：符号数、bit code length 等不是可事后切换的计数标准。当前 Rate 属于固定 Description Language / 编码规则下的预注册码长。
- R_X 是 estimand 的合法定义域；跨架构比较只能在公共可达域上进行。某架构某 rate 区间无可达 encoder 是 applicability finding，不得为比较而修改语言或任务。
- workload prior 记为 Pi_W；evaluation protocol 改记为 Eval=(budget, estimator, sampling)，消除符号冲突。
- theta 的合法 quotient 必须位于整个 Decision Problem Family 的联合决策相关层，而不是任一单 task 的边缘统计量。
- sigma_D 定义为冻结成本族的联合因子化见证：每个冻结成本函数必须可经由 sigma_D 因子化。它不能根据 projection/frontier 结果扩充。
- sigma_D 应取通过因子化约束的最粗/最小充分见证；若存在多个不可比最小见证，可声明见证族。若最小见证退化到近似 identity，则必须记录为 workload 全食性/框架边界，不得静默接受 sigma=id 使压缩命题失去意义。
- N 是 deployment amortization 的显式索引；更一般可由 decision-frequency measure mu_D 表达。semantic frontier 与 deployment-economic frontier 分轨，不得混为一个 estimand。
- O(A)/O(D) 分解本身不是本体对象；若只改变 accounting allocation 而总 deployment cost 不变，则属于同一 deployment estimand。只有当某一分项被明确声明为研究目标时，它才成为独立 estimand coordinate。
- oracle baseline 必须与相同 workload/cost/decision regime 配对；归一化规则固定为统一形式，架构只通过 R_oracle,X 的输入值进入，不能改变 normalization semantics。
- Target、Estimator、Observed frontier 严格分离。STEP④ 只确定 target，不证明 finite-sample identifiability 或 precision。

## 2. Joint Sufficiency / Quotient Invariance Gate

最后一刀攻击了 sigma_D 同时满足联合充分、非循环、非平凡压缩的可能性。

裁定采用构造性判据：

forall j,a,w: C_j(a,w) = C'_j(a, sigma_D(w))

即冻结 Decision Problem Family 的每一个成本函数都必须经由同一个 sigma_D 因子化。

因此：

1. 联合充分性变成可审计的 definition-level condition，而非抽象口号；
2. 非循环性由成本族先于 projection 定义、且成本函数签名不含 P/frontier，结构上阻断“根据结果扩充 sigma”；
3. 非平凡性由最小因子化见证承担，而非靠把全部 workload W 原样塞入 sigma。

同时明确：

> sigma_D 是 D 的镜子，不是 D 的法官。

若冻结成本族遗漏了真实 decision semantics，应修订 Decision Problem / frame，而不是经由 sigma 偷偷补充语义。若最小 sigma 接近 identity，则这是关于该 decision family 的真实边界，而不是定义失败的理由。

## 3. 等价参数化裁定

规格参数的等价关系定义为：两个参数化若诱导相同的 Decision Problem、admissible projection set、rate accounting 与 decision-risk functional，则属于同一 estimand 的不同表示。

因此要求：

q1 ~_D q2  =>  F_AS(q1)=F_AS(q2)

参数化变化若仅改变坐标表示，则由 quotient 吸收；若改变 induced decision regime，则是不同的预注册 estimand，而非同一 estimand 的歧义。

由此正式区分：

> 参数化等价是身份问题，靠 quotient invariance 解决；数据可识别性/估计精度是估计问题，进入后续设计。

同一数据服务多个已预注册 estimand 是合法的多目标结构，不构成规格歧义。

## 4. STEP④ 最终独立性条件

STEP④ 通过依赖以下冻结条件：

- L：Description Language 与 Rate counting convention；
- D=(A,C,sigma_D,Pi_W)：完整 Decision Problem Family；
- S_det：确定性、预注册的静态派生策略族；
- Eval=(budget, estimator, sampling)：评估协议的独立名称与后续执行接口；
- theta_tilde：位于联合决策相关层的 workload-regime distribution / pushforward；
- N 或 mu_D：仅在 deployment-economic estimand 中出现；
- R_X：由冻结语言与策略族实际诱导的架构特定可达域；
- R_oracle,X：与相同决策/成本/workload regime 配对的 full-information reference。

任何这些坐标在观察 frontier 后改变，都不是“修正估计”，而是新 frame / 新 estimand，必须重新走治理门。

## 5. STEP④ 不证明什么

本次 PASS 不证明：

- Achievable Static Frontier 已经存在于真实模型；
- 任意架构都有非平凡 frontier；
- sigma_D 一定低维；
- 跨架构 frontier 一定具有共同形状；
- analytic projection 一定优于 architecture-specific state；
- Runtime adoption value；
- finite-sample estimability 或统计精度；
- STEP⑤ existence criterion 已经通过。

## 6. 正式进入 STEP⑤

研究者明确要求：

> 正式收口 STEP④、进入 STEP⑤（Existence Criterion）。

因此当前治理状态转换为：

- STEP①：ACCEPTED BY HUMAN RESEARCHER
- STEP②：ACCEPTED
- STEP③：PASS
- STEP④：PASS / CLOSED FOR CURRENT FRAME
- STEP⑤：OPEN / EXISTENCE CRITERION
- RQ ID：尚未分配
- Experiment / harness / profiling / data collection / measurement：仍未授权

STEP⑤ 的问题不再是“如何定义 frontier”，而是：

> 在不预设 frontier 必然非空、非退化、低码率或跨架构共性的前提下，什么最小、可证伪、非循环的观察条件，才足以宣布 Achievable Static Frontier 在给定 frame 与 scope 内“存在”并获得继续研究资格？

## 7. STEP⑤ 初始边界

STEP⑤ 必须首先攻击以下潜在偷渡：

- P_AS 非空是否就被误当作科学意义上的存在；
- 一个端点或 L₀ trivial encoder 是否被误当作非平凡 frontier；
- 数学 infimum 是否被误当作实际可构造 encoder；
- 单架构、单 workload、单 regime 的偶然现象是否被误升格为跨架构 existence；
- “有一个 projection 能工作”是否偷渡 Runtime usefulness；
- existence criterion 是否把未来的 discriminating power / information value 预先塞进去；
- Track B 的 State lifecycle evidence 是否被转移为 P4-A existence evidence。

STEP⑤ 只定义“什么现象获得存在资格”，不提前定义其价值、优越性或跨架构泛化。

**Governance:** no implementation / harness / profiling / measurement authorization is created by this transition.
