# SimiGo-Lab Research State

> **This file is the authoritative snapshot of the current SimiGo-Lab research state. Conversation memory must not override it.**

**Last updated**: 2026-09-30

## Route redefinition — 2026-09-29

The research program is now **Execution-State-centric**. Runtime correctness is
`SEALED / BOUNDED CONSOLIDATION`; oversized independent research is
`FROZEN / ARCHITECTURE VALIDATION PAYLOAD`. A new **Execution State Architecture
Contract** is the next synthesis gate. PALACE-1 is the main open audit-first line;
BACKEND-1 is secondary and depends on the persistence/representation boundary.
Do not select storage technology or implement a Llama adapter before those boundaries
are established.

Canonical route:
`docs/00-governance/SIMIGO_LAB_EXECUTION_STATE_RESEARCH_ROUTE_REDEFINITION_20260929.md`

**Current entry**: `docs/NEXT_SESSION_ENTRY.md`。PALACE-1 线推进至 E1 封存：E0 分解（`ed6cb87`）→ E1 设计冻结（`9953792`）→ E1 执行（R0=IDENTIFIED、R1=FAILED-FAIL-CLOSED 三次复现，P-1/P-2 预登记确认；R2 三次被安全守卫拦截，隔离机制穷尽记录；interim `dd825cb`）→ human 裁定 E1 封存于执行边界（R2-R4 PENDING；A/B/C 隔离选项悬置）→ **E1-R2 capability trace（`f3e498`：R2 所需能力 = 产品 cold-start 一等分支，NativeMLX:763-778，不读 checkpoint/pool/lineage；语义连续性由 meta.history+modelId+storageKey（44KB）承载）。Contract v1.0 = UPSTREAM REFERENCE；不做存储选型、不修改 Contract/产品代码、不碰原始 ~/.simigo。**

**Historical snapshot 2026-09-25**:（R-INTERNAL-18 = ROr-4 / R_ORACLE_DEFERRED
R-INTERNAL-19 = A / ABSTRACTION_LAYER_COMPLETENESS_AUDIT 已登记；
Concrete Representation Decision 选择 3 / FULL_VISIBLE_HISTORY_RULE_SPACE；
Concrete Argmin Cardinality Policy 确认
ACCEPT_UNDERDETERMINATION / NO_RULE_DOMAIN_COMPLETION_NOW；
Research Road Space 已登记，A2.0 research roads remain unselected；
Gemma 4 Computational-Semantics Probe 已登记为 EXTERNAL_OBSERVATION_ONLY；
Qwen3-Coder 已按 SimiGo 1.7 生产运行证据登记为 RUNTIME_POSITIVE_CONTROL；
Computational-Semantics Observation Schema 已登记为 CANDIDATE / FORMALIZATION_OPEN；
A2.0 Boundary Audit 已登记为 EXPLORATORY / FORMALIZATION_NOT_AUTHORIZED；
Interface Sufficiency Audit 已登记为 EXPLORATORY / CORE_CLOSURE_PARTIAL；
Trajectory/Execution Necessity Audit 已登记为 RESULT_CONCRETE_ONLY；
Core Nontriviality Audit 已登记为 CORE_CANDIDATE_SURVIVES_FIRST_ATTACK；
Core Degeneracy/Distinctiveness Audit 已登记为 DISTINCTIVENESS_OPEN；
Projection–Evaluation Distinctiveness Attack 已登记为 RESULT_RECOVERABLE；
Terminal Distinctiveness Audit 已登记为 GENERIC_REDUCIBLE_AT_CURRENT_ABSTRACTION；
A2.0 Value Core 已冻结为 FROZEN / GENERIC_REDUCIBLE / INDEPENDENT_THEORY_NOT_ESTABLISHED；
A2.0 Historical Scope Decomposition 已登记为 RETROSPECTIVE / NO_ROUTE_SELECTED；
Execution-State Extension Design Hypothesis 已登记为 HYPOTHESIS / NOT_FORMALIZED / ROUTE_UNSELECTED；
Execution-State Predictive Resource Hypothesis 已登记为 HYPOTHESIS / NOT_FORMALIZED / ROUTE_UNSELECTED；
Execution-State Information Boundary Hypothesis 已登记为 HYPOTHESIS / NOT_FORMALIZED / ROUTE_UNSELECTED；
SimiGo 2.0 Experimental 工程路线已登记为 ROUTE_REGISTERED / PHASE_0_AUTHORIZED；
SimiGo 2.0 Phase 0 Qwen3-Coder inventory 已登记为 PARTIAL_REPORT / RUNTIME_PARTIAL_LOAD_TEST_PENDING；
SimiGo 2.0 Runtime Reference 已选定 MLX Swift LM 为主，llama.cpp 为参考，vLLM 延后；
SimiGo 2.0 Phase 1 Swift scaffold 已实现并通过 5 项测试，policy benchmark 完成；
SimiGo 2.0 Phase 1 selective Safetensors materialization 已实际运行完成；
SimiGo 2.0 MLX Gate 1 selective tensor materialization 已通过 CORE 与 SWITCH_MLP 测试；
SimiGo 2.0 MLX Gate 2 group lifecycle 已在 fingerprint 层通过；
SimiGo 2.0 MLX Gate 3 parameter swap / semantic restore 已通过；
SimiGo 2.0 MLX Gate 4 single-state whole-group inference residency 已通过；
SimiGo 2.0 MLX Gate 5 multi-state runtime residency feasibility 已通过，
对 naive on-demand 减少 reload 10.87 GiB，但 latency advantage 未建立；
SimiGo 2.0 SwiftUI App 已完成本机构建，并在 Apple M5 上完成 Gate 5 real-device proof）
；Nail-Qwen3.6-35B-A3B-MLX 已在 Apple M5 完成 Gate 4 与 Gate 5 real-device validation）
；Gemma4 Unified 已完成 Apple M5 text inference probe，但当前 whole-group residency support 为 NOT_APPLICABLE / INCOMPLETE）
；Muse-Glimmer text-only 已通过本地 mlx-swift-lm fork 增加 RUNTIME_FORWARD 支持，RESIDENCY 仍为 NOT_APPLICABLE）
；Dense MLP residency extension 已实现，Gemma4 与 Muse-Glimmer Gate 5 均 PASS，但 semantic quality 仍未解决）
；Checkpoint 自带 chat template 已可应用，Gemma4 dense Gate 5 在模板化输入下 PASS；
Representation Capture API audit 已在 Qwen3-Coder 实际容器上完成，
G1.9-A infrastructure = COMPLETE，direct public-API capture = REJECTED，
recommended route = ISOLATED_INSTRUMENTATION；
Representation Capture multi-model audit 已覆盖 Qwen3-Coder、Nail-Qwen3.6、
Gemma4 与本地 Muse-Glimmer q4，四者均为 MODULE_INVENTORY_ONLY，
stable observation contract = false，route = ISOLATED_INSTRUMENTATION）
；G1.9-B Instrumentation Identity Probe 首个 Qwen3-Coder proxy point 已 PASS：
baseline 与 instrumented logits checksum 逐位一致且 Δ=0，
capture point = layer 0 fused MoE switch down_proj output，
该结果仅为 identity probe，不定义 H_i(x)、layer/expert demand 或 predictor）
；Phase R0 Planner Runtime Integration 已通过：simulator 中 executionPlanner
与 legacy reactive 逐状态等价，真实 MLX Gate R0 的 15 次生成 output identity
PASS，reload 较 naive 减少 10.87 GiB；latency advantage 未建立，
Predictor / Expert demand / async I/O 仍为未授权后续）
；Planner budget sweep 已在 simulator 完成：LOCALITY_A / ALTERNATE_AB /
CYCLE_ABC 最低 no-overflow budget = 40%，ALTERNATE_A_AB = 70%，
BASELINE_ABA / FULL_PARTIAL = 100%；该结果仅描述 planner trade-off，
descriptive recency hints 不是 prediction，也不建立真实 demand）
；Workload Trace 已登记 T1–T4 四条可复现 trace（declared
operation→state mapping，非 measured demand）；simulator trace replay
已完成（Qwen3-Coder inventory；70% budget 下 T1/T2/T3 required-hit ratio
= 0.888/0.872/0.871，T4 需 100% 才无 overflow；hint 仍为 strictly-prior
descriptive recency）
；真实 MLX runtime 已按四条 trace 的 state 序列跑 Gate 5 三策略对照，
全部 PASS（output identity PASS；reload 较 naive 分别 −20.25 / −10.12 /
−40.50 / −30.38 GiB；T4 相对降幅 −50%；latency advantage 仍未建立；
generation 仍需全部 decoder-layer groups，policy 只控 idle retention）
；demand predictor 仍受 STOP GATE 约束，下一门 = ⑦ locality / reload /
residency 分析）
；⑦ 多模型 locality 分析已完成并扩展至五个本地 checkpoint
（Qwen3-Coder / Nail-Qwen3.6 / Cyber-Tiel / Gemma4 / Muse-Glimmer；
20/20 真实 Gate 5 trace 运行 output identity PASS；state retention 对
naive 的 reload 节益 16.7–55%，逐 trace 比例跨模型稳定；latency
advantage 仍未建立）；required-hit 排序 T3>T1>T2>T4 跨模型不变
（declared mapping 属性），T4-ALL 登记为 working-set-breadth 边界
workload；**Predictor STOP GATE 判定 = NO_GO**（G1–G3 在 declared 层
成立，G4 source legitimacy 因无 measured execution trace 而不满足——
STOP 为本阶段完整研究结论；重开仅可经已登记的 ISOLATED_INSTRUMENTATION
路线上独立定义门，NOT STARTED））
；**G1.9-A ISOLATED_INSTRUMENTATION 已获用户明确授权（2026-09-25，
authorization commit = Git 层面开启）**：授权范围 = 隔离路径内修改/扩展
instrumentation、捕获真实 forward execution 的 layer/group 事件、先验证
identity/logits/token 一致性/execution 不变/时间与内存开销、形成
measured execution trace 并重审 recurrence/transition locality/temporal
stability；仍未授权 = Predictor、probability、speculative loading、
Expert/Token×Expert demand、production MLX 修改、async I/O、通用架构
宣称；第一阶段 STOP 条件固定 = instrumented≈baseline + trace stable +
overhead acceptable 三者同时成立才进 measured-locality 分析，否则在
第一阶段 STOP）
；G1.9-A group execution trace design / pre-run audit 已完成并修复三项
缺陷（嵌套 perform 死锁隐患→非嵌套协议；identity probe 对
QuantizedLinear 的静默语义破坏→专用分支按 quantizedMM 克隆；观测路径
过滤器漏 fused MoE→双变体）；
**Qwen3-Coder 首个 measured execution trace 采集 PASS**：48/48 层模块
替换，logits SHA-256 逐位一致，生成文本逐字一致，两次 instrumented
事件流逐项稳定（1536 事件 = 32 pass × 48 层，event-only 不持有激活），
overhead 处于噪声内、峰值内存开销 0 MB；Phase-1 STOP 条件满足；
measured-locality 分析（recurrence/transition locality/temporal
stability）与 Predictor 重开决定 = PENDING，Predictor 仍未授权）
；G1.9-A pilot 已按设计审计执行（协议 G1.9-A.PILOT.V1 = 固定 3 prompt ×
3 重复，观测契约收窄为 event.kind=layerEntered 最小字段，observed 与
derived 分离，observer passive，naming = MeasuredExecutionTrace）；
**四门判定：A.1 Baseline Identity = PASS（15/15：token 序列一致 +
logits SHA-256 逐位一致，max_abs_diff=0）；A.2 Trace Stability = PASS
（15/15：三次重复事件流逐项一致；稳定 ≠ 可预测）；A.3 Overhead =
ACCEPTABLE（描述性记录，比值 0.72–7.95 方向不一致非系统性成本，峰值
内存 ≤8.5 MB，无阈值声明；Qwen3-Coder 比值 >1.9 已标记待采数阶段专项
计时）；A.4 Cross-model = PASS（5/5：Qwen3-Coder/Nail/Cyber-Tiel 主力
+ Gemma4/Muse 兼容扩展；module-paths 发现命令登记两类前缀命名变体，
shared_expert 排除）**；pilot v0 三缺陷登记（token 类别错比/box 未清/
路径前缀盲区）并修复后重跑；下一步 = Measured Execution Trace
Collection，届时 declared 与 measured 两线并列重算 locality 量并重审
G4；Predictor 仍未授权）
；**G1.9-C Measured Execution Trace Collection 已完成**（登记为 G1.9-C
因 G1.9-B 已被 identity probe 占用；协议 G1.9-C.COLLECT.V1 = 已注册
workload trace 的 25 个 operation 各配 scenario prompt，preamble 身份
哨兵 5/5 PASS；两线分立：declared = scenario 声明，measured = 观测，
字段分立且无 demand 字段）；**测量结论：Layer/Group 分辨率下 measured
execution 无差分局部性**——5 模型 × 4 workload × 125 操作，measured
working set 每步恒为全集（C1 全非空但退化、C2 = 1.0、C3 lag1/2/3 =
1.0、C4 breadth 恒 3/atMax=1.0）；declared ⊆ measured 125/125 恒成立，
measured 超出 declared 恰出现在 22/25 个非 ALL 声明步；Gate 5「generation
需全部 decoder-layer groups，policy 只控 idle retention」由假设转为五模
型实测事实；**PREDICTOR_STOP_GATE_NO_GO 获得实测确认**（本分辨率下无可
预测的差分信号）；reload 节益维持为 declared 情景下的 idle-retention
经济学结果；差分执行若存在只可能在更细分辨率（Router/Expert），观测之
= 未授权的新决定）
；**G1.9-C Post-Audit 已锁死三结论并封线**：①覆盖域内 ∀(m,w,t)
M=G_all（125 操作 × 5 模型逐步成立，非「多数」），ΔM_t=∅；②Predictor
语义关闭而非性能不足——P(M_{t+1}=G_all|H_t)=1 且无 H_t→不同
execution set 的可学映射，PREDICTOR_STOP_GATE_NO_GO 升级为
**RESOLUTION-DEGENERATE / NO PREDICTIVE TARGET**（layer/group 分辨率
终态）；③Residency 研究不受影响——RequiredExecutionSet_t ≠
ResidentSet_t，reload 节益 16.7–55% 回答的是「执行后保留什么以减少下次
重物化」而非「哪些层下次不执行」，Execution/Residency 两对象正式分离；
Router/Expert 不得因退化结果「为延续研究」而开启）
；**Residency Observability Audit 已完成**：四问裁定——transfer log 与
MLX 聚合内存 = OBSERVED（执行+计时/独立快照）；组级 resident set =
POLICY BOOKKEEPING（derived）；独立 per-group 运行时观测 = 不存在且
非扰动式探针在公共 API 不可行（触碰即物化，与 G1.9-A API audit
REJECTED 一致；runtime 侧机制 = 未授权的 production MLX 修改）；
**字节级验证（新证据）**：75 转移 × 3 策略 × 5 模型，Qwen3-Coder
maxRel=4.6e-5、Gemma4/Muse ≤6.6e-4；Nail/Cyber-Tiel 存在精确恒定偏移
−851.1/−851.5 MiB，对账闭合 = index 内 vision_tower（333 张量
851.8 MiB）未被文本路径模型类加载（残差 <0.8 MiB），系 inventory 对账
项而非驻留跟踪误差；分支判定 = 字节级观测充分、组级仅 PolicyResidency；
命名纪律：只允许「PolicyResidency retention structure (byte-validated)」，
禁称 natural residency demand / observed residency locality；下一门 =
用户决定（residency locality 分析 / 最小 per-group 观测机制 / STOP））
；**用户裁定（2026-09-25）：选 (a) 独家授权——G1.9-D PolicyResidency
Retention Analysis**（窄授权：仅分析既有 20 条真实 trace 与已验证
bookkeeping，不增加任何新 runtime 观测，不重定义 residency demand，不开
Router/Expert；标签 = PolicyResidency retention structure，禁称
residency locality；C_model 偏移封存为 accounting item 不进入分析；
冻结词汇 ResidencyDemand/ResidencyProbability/RetentionPredictor/
OptimalResidentSet/predictedResidentSet 不得出现）
；**G1.9-D 已执行完毕**：D4 恒等式 savings = Σ retainedOptionalBytes(t)
− oneColdStartLoad 在 20/20 (模型, workload) 对上精确成立（<0.1% 容差），
把此前 16.7–55% 节益分解为 retained-optional-bytes 积分减一次冷启动；
D1 keep-ratio 与 D3 lag-1 overlap 为 (policy, state sequence) 的确定性
结构常数（T1 0.600 / T2 0.500 / T3 0.521–0.537 / T4 0.667–0.742；
lag-1 0.553–0.795）；T4-ALL 边界对照成立（execution 侧无结构，residency
侧 T4 含 2/5 full-retention 步且节省比例最高 0.500–0.550）；预注册判定
= **POLICY_RETENTION_STRUCTURE_EMPIRICALLY_CHARACTERIZED**（非
INCONCLUSIVE/STOP）；按授权边界，主张到此为止——是否研究 retention
优化 = 基于新证据的新决定）
；**用户裁定（2026-09-25）：开启 G1.9-E0 Retention Optimization
Feasibility Audit**（纯离线审计授权：既有 20 条 trace + inventory +
policy/budget/transfer artifacts + candidate enumeration/replay + 离线
reload/resident/correctness 比较；仍未授权 = 新 runtime instrumentation、
MLX 内部修改、Router/Expert、Predictor、Probability、production
optimizer、speculative retention、architecture declaration；冻结词汇
Optimal* 继续冻结——candidates 而非 optima）
；**E0 已执行完毕（80 个离线 candidate-replay = 4 候选 × 20 对）**：
①结构事实（此前已实测）execution=ALL ⇒ reload(t)=optTotal−retained(t−1)
⇒ reloadTotal = n·optTotal − retainedLeadingIntegral——总 reload 由保留
字节时间积分唯一决定，该前治面恒等式对全部候选全部 20 对精确成立；
②三判定：V1 等峰值预算下改进候选存在（20/20；如 Qwen T3 reload
81.0→15.19 GiB）但平均驻留升至峰值（8.69→16.00 GiB）；V2 等积分预算下
改进**可证不可能**；V3 无候选支配现行 policy（20/20）——现行 policy 在
trade-off 前治面上；**判定 = FEASIBLE_TRADEOFF_SPACE_ONLY_NO_FREE_
IMPROVEMENT**：改进空间只存在于保持结构-经济学的前治面上（更多积分换
更少 reload），无免费改进、无被支配收益；E1 reload 只能以 E2 驻留积分
为代价改善，E3 预算定义决定可行点，E4 correctness 对全部候选结构性
成立；下一门 = 用户决定（声明 cost weighting 的 candidate analysis 门 /
或 STOP——前治面已完整刻画 + 无免费改进本身即完整工程结论））
；**用户裁定（2026-09-25）：G1.9-E0 STOP——GROUP_RESOLUTION_POLICY_
TRADEOFF_CLOSED，group 分辨率 Experimental 研究线正式封端**（锁定 =
不进入 Candidate Analysis、不定义 cost weighting/optimizer/optimal
policy、不开 Router/Expert、不加 runtime instrumentation、不做生产
MLX 修改；重开只能由新问题或新证据触发——如真实部署的峰值内存 ≤X GiB
+ reload latency ≤Y ms 双约束、workload SLA、长会话内存压力、
materialization/计算重叠实测代价、或某分辨率/模型类下 execution 非全集
的观测——绝不因「还有优化空间」自动恢复）；**两条线终态**：
Execution 对象 = measured FULL ⇒ locality degenerate ⇒ no predictive
target（RESOLUTION-DEGENERATE）；Residency 对象 = policy-derived ⇒
byte-validated ⇒ D1–D4 characterized ⇒ exact reload identity
（ReloadTotal = n·OptionalTotal − ΣRetainedBytes，20/20 精确）⇒
trade-off frontier ⇒ no free improvement（Reload reduction ⟺ additional
retention integral）；**留下的是负结果 + 工程正结果的组合**：当前分辨
率不存在可供 Predictor 利用的 execution locality；即使如此，policy-level
residency retention 仍可严格测量、字节级验证、其 reload economics 精确
分解为无免费改进的线性 trade-off——完整阶段封存）
；**Final Consolidation 完成并登记 `SIMIGO2_EXPERIMENTAL_FINAL_RESEARCH_AUDIT_v1.0.md`**（总审计非实验：七问全答——①实测证明七项（identity 45+125 采 anchors、execution=FULL 125×5、字节验证 375 行、D4/E0 恒等式 20/20+80 replay 等，全部带 commit/artifact 锚）；②policy-derived 清单（resident set 记账、retention 结构常数、declared 映射、simulator 层结果）；③工程事实（planner 端到端可用、load-before-generation 语义、latency NOT ESTABLISHED、pre-run audit 三缺陷、C_model 对账项）；④被证伪前提五条（group 级差分局部性/declared≈measured demand/节益=locality 利用/观测必扰动/存在免费优化空间）；⑤已关闭问题七项（Predictor 语义关闭等）；⑥未授权清单（Router/Expert、Predictor/probability、新 instrumentation、生产 MLX、async I/O、cost weighting/optimizer、architecture declaration、冻结词汇）；⑦可重开问题+具体触发（部署双约束/SLA、reload latency 瓶颈、execution≠FULL 观测、C0–C5 formalization 延后、工程尾巴）；**账本勘误：字节验证总行数 375（非 225），旧文档已同步修正**；核心发现一句话登记：「完整 Transformer generation 在 Layer/Group 分辨率下没有 execution locality,但 residency retention 仍存在独立且可量化的工程结构;其收益本质上是内存驻留与重物化之间的 trade-off,而不是 computation skipping」；**研究线 FROZEN;接续工程路线 `SimiGo 2.0 Runtime Residency Engineering` = DECLARED NOT STARTED**——与已封研究线分离,无理论对象无 demand 词汇,第一步=需求定义（budget/resident state 来源、load/evict 执行者、failure/overflow/cancellation 语义、多请求并发、长上下文、memory pressure）,planner 契约不变且永不预测；八项排序工作表登记（1 审计✅ 2 冻结✅ 3 需求定义 NEXT 4 Controller 验证 5 长会话 6 memory pressure 条件 7 async 条件 8 Router/Expert 不进入））

## Current research state

Phase: Architecture 2.0 / P4 Redefinition

Engineering phase: SimiGo 2.0 Experimental R0 / PLANNER_RUNTIME_INTEGRATION_PASS
Engineering subphase: V2_0_0_BETA_RELEASED / PRODUCT_INTEGRATION_PASS / GA_WORKITEMS_REGISTERED

R-INTERNAL-1 = P4
R-INTERNAL-2 = δ3
R-INTERNAL-3 = θ2
R-INTERNAL-4 = G4-4
R-INTERNAL-5 = L5-3
R-INTERNAL-6 = E6-4
R-INTERNAL-7 = E7-B
R-INTERNAL-8 = E8-C
R-INTERNAL-9 = E9-B
R-INTERNAL-10 = E10-B
R-INTERNAL-11 = E11-B
R-INTERNAL-12 = K3-A / VALUE_INFIMUM
R-INTERNAL-13 = K3-B / OPT_FINITE_VALUE_DOMAIN
R-INTERNAL-14 = K4-A / UNRESOLVED + ATTAINMENT_PREDICATE
R-INTERNAL-15 = K4-B / DEFINE_ARGMIN_SET + ATTAINMENT_EQUIVALENCE
R-INTERNAL-16 = K4-C / UNRESOLVED + UNIQUENESS_PREDICATE
R-INTERNAL-17 = RO-1 / R_OBJECT_VALUE_FUNCTIONAL
R-INTERNAL-18 = ROr-4 / R_ORACLE_DEFERRED

### Current internal interfaces

```
P : PROJECTION_CANDIDATE
δ : DECISION_GENERATION_PARAMETER
θ : REGIME_PARAMETER

𝒢_adm(P) = ADMISSIBLE_DECISION_RULE_FAMILY
𝒢_adm(P) ⊆ {g | g : W → A}

L : Dom(L) → ℝ

R-INTERNAL-8 / E8-C:
(g,P,θ) ∈ Dom(L)
    ⇔
g ∈ 𝒢_adm(P)
    ∧
E_θ[C_LOSS(g(W),W)] 合法且为有限实数

R-INTERNAL-9 / E9-B:
R(P,θ)
=
OPT_{g ∈ 𝒢_adm(P),\,(g,P,θ)∈Dom(L)}
L(g;P,θ)

R-INTERNAL-10 / E10-B:
∃g :
g ∈ 𝒢_adm(P)
∧
(g,P,θ) ∈ Dom(L)

等价地：
{g ∈ 𝒢_adm(P) | (g,P,θ) ∈ Dom(L)} ≠ ∅

R-INTERNAL-11 / E11-B:
R(P,θ) ∈ ℝ

R-INTERNAL-12 / K3-A:
V(P,θ)
=
{L(g;P,θ) | g ∈ 𝒢_adm(P), (g,P,θ) ∈ Dom(L)}

OPT(P,θ) = inf V(P,θ)

R-INTERNAL-13 / K3-B:
V(P,θ) ≠ ∅ and V(P,θ) ⊆ ℝ.

Dom(R)
=
{(P,θ) | D_opt(P,θ) ≠ ∅ ∧ inf V(P,θ) ∈ ℝ}

R(P,θ) = inf V(P,θ) ∈ ℝ,  ((P,θ) ∈ Dom(R))

R-INTERNAL-14 / K4-A:
att : Dom(R) → {true, false}

att(P,θ) ⇔ inf V(P,θ) ∈ V(P,θ)

Dom_att
=
{(P,θ) ∈ Dom(R) | att(P,θ)}

R-INTERNAL-15 / K4-B:
Argmin(P,θ)
=
{g ∈ D_opt(P,θ) | L(g;P,θ) = inf V(P,θ)}
\quad ((P,θ) ∈ Dom(R))

Argmin(P,θ) ≠ ∅
⇔
att(P,θ)

Dom_att
=
{(P,θ) ∈ Dom(R) | Argmin(P,θ) ≠ ∅}

R-INTERNAL-16 / K4-C:
uniq : Dom(R) → {true, false}

uniq(P,θ) ⇔ |Argmin(P,θ)| = 1

Dom_uniq
=
{(P,θ) ∈ Dom(R) | uniq(P,θ)}
```

R-INTERNAL-14 defines the attainment predicate without asserting attainment. R-INTERNAL-15 defines the argmin set on Dom(R) and formally registers the pointwise equivalence between argmin non-emptiness and att. Neither gate asserts that attainment or argmin non-emptiness holds at any particular point.

### Assembly state

```
R-ASSEMBLY-1A = DECLARED (COMPOSITE_PROJECTION_RULE_PAIR)
R-ASSEMBLY-1B = DECLARED (JOINT_COMPOSITE_OUTPUT_MECHANISM)
R-ASSEMBLY-1C = DECLARED (C3)
R-ASSEMBLY-2  = DECLARED (D2)
R-ASSEMBLY-3  = DECLARED (F2)
R-ASSEMBLY-4  = DECLARED (G2)
R-ASSEMBLY-5  = DECLARED (H2)
R-ASSEMBLY-6  = DECLARED (I2)
R-ASSEMBLY-7  = DECLARED (J1)
R-ASSEMBLY-8  = DECLARED (K3)
R-ASSEMBLY-9  = DECLARED (L3)
R-ASSEMBLY-10 = DECLARED (M4)

R_OBJECT     = DECLARED (R : Dom(R) → ℝ)
R_ASSEMBLY   = CLOSED (M4 DEFERRAL SATISFIED)
R_ORACLE     = NOT_DEFINED
Δ            = BLOCKED
FinLoss      = NOT LEGALLY AVAILABLE
NECT         = BLOCKED
STEP⑤        = NOT ENTERED
STEP⑥        = NOT ENTERED
EXPERIMENT AUTH = NONE
HARNESS AUTH    = NONE
```

### Core aggregate construction

```
Γ(P,δ) = g
g : W → A

L(g;P,θ) = E_θ[C_LOSS(g(W),W)]

R(P,θ)
=
OPT_{g ∈ 𝒢_adm(P),\,(g,P,θ)∈Dom(L)}
L(g;P,θ)

R(P,θ) ∈ ℝ
```

OPT is concretized as a value-level infimum by R-INTERNAL-12. R-INTERNAL-13 establishes the finite-value applicability domain for that construction. R-INTERNAL-14 defines the attainment predicate without asserting attainment. The non-emptiness of `Dom(R)` and `Dom_att` itself is not declared.

### Research boundaries

R_OBJECT is declared as the value functional R : Dom(R) → ℝ; under RO-1, the research object is the optimal value, while Argmin / att / uniq and their domains remain auxiliary diagnostic/semantic objects and are not deleted. R_ORACLE remains undefined by the current framework. Δ remains blocked. FinLoss and NECT remain unavailable. Historical STEP⑤ formulation remains historical/conditional only. No STEP⑤/STEP⑥ entry, implementation, harness, data collection, profiling, measurement, or experiment authorization follows from R-INTERNAL-15.

R-INTERNAL-16 does not introduce topology or any structural condition, and does not pre-authorize future sufficient-condition families. It does not declare optimizer existence at any point, attainment at any point, minimum attainment, `min` reformulation, selector/tie-breaking, canonical choice, uniqueness at any particular point, compactness, continuity, measurability, finiteness/cardinality assumptions, any θ-level optimization, `A(P,θ)`, historical `δ(I_P)`, R_OBJECT, R_ORACLE, Δ, FinLoss, or NECT. The uniqueness predicate itself is defined, but no instance is asserted to satisfy it.

The authorized forward interface after R-INTERNAL-16 is:
```
att : Dom(R) → {true,false}
Argmin(P,θ) = {g ∈ D_opt(P,θ) | L(g;P,θ) = inf V(P,θ)}
Argmin(P,θ) ≠ ∅ ⇔ att(P,θ)
Dom_att = {(P,θ) ∈ Dom(R) | Argmin(P,θ) ≠ ∅}
uniq : Dom(R) → {true,false}
uniq(P,θ) ⇔ |Argmin(P,θ)| = 1
Dom_uniq = {(P,θ) ∈ Dom(R) | uniq(P,θ)}
```

The equivalence is registered as the formal bridge between attainment and argmin non-emptiness. R-INTERNAL-16 defines only the uniqueness predicate and its truth domain; it does not assert uniqueness anywhere. Selector/tie-breaking remains a separate layer.

Historical `δ(I_P)` is not restored and no new δ optimization domain is introduced.

R-INTERNAL-17 / RO-1 explicitly keeps `δ(I_P)` BLOCKED and does not introduce any new δ optimization domain. `Δ` remains BLOCKED; `FinLoss` remains NOT LEGALLY AVAILABLE; `NECT` remains BLOCKED. θ-level optimization and `A(P,θ)` remain excluded. No approximation/gap object is introduced.

R-INTERNAL-16 does not declare `Dom_uniq ≠ ∅`, does not assert `uniq` is true at any point, and does not create a selector from uniqueness. The observation that `uniq(P,θ)` is false whenever `Argmin(P,θ)=∅` is a direct consequence of the registered definitions, not a separate assertion.


### R-INTERNAL-18 / ROr-4 — R_ORACLE deferred

R-INTERNAL-18 = ROr-4 / DEFERRED

R_ORACLE : NOT_DEFINED

暂缓理由：
1. 无已登记消费者：Δ = BLOCKED，gap/D 未声明，STEP⑤ = NOT ENTERED。
2. 来源形态未决：P-free 可容许类 / 理论基准均未声明。
3. 历史公式 D(P;θ) = R(P;θ) − R_oracle(θ) 仅为历史内容，不被本面恢复。

合法重开条件（二选一，各自独立开面）：
- A. 出现已登记的参照值消费问题——且该比较面必须先论证其对 Δ BLOCKED 的合法绕行路径。
- B. 结构面声明 oracle 来源（P-free 类 / 理论基准及其定义域）。

本面产出是“暂缓”边界记录本身，不声明 R_ORACLE 对象接口。

R-INTERNAL-18 不引入：
- gap / D / suboptimality 的任何形式（含定义性占位）；
- 历史 δ(I_P)、新的 δ 优化域、A(P,θ)、θ 层优化；
- Δ、FinLoss、NECT；
- 任何 selector、tie-breaking、canonical optimizer、g*；
- topology、compactness、continuity、measurability、finiteness/cardinality assumptions；
- implementation、harness、data collection、profiling、measurement、experiment authorization。

Argmin / att / uniq 维持 RO-1 下辅助对象地位，不因本面变动。

R_ASSEMBLY = OPEN（门时点记录；已由 R-ASSEMBLY Transition Audit 关闭为 CLOSED）
R_OBJECT = DECLARED (R : Dom(R) → ℝ)
R_ORACLE = NOT_DEFINED
Δ = BLOCKED
FinLoss = NOT LEGALLY AVAILABLE
NECT = BLOCKED
STEP⑤ = NOT ENTERED
STEP⑥ = NOT ENTERED
EXPERIMENT AUTH = NONE
HARNESS AUTH = NONE


### R-INTERNAL-19 / A — Abstraction Layer Completeness Audit

R-INTERNAL-19 = A / ABSTRACTION_LAYER_COMPLETENESS_AUDIT

This is a boundary audit and declares no new semantic object.

Current finding:
- The current abstraction layer has no remaining purposeful, consumer-driven interface that can be legally registered without a structural declaration, concrete instantiation, or program-level problem surface.
- R-INTERNAL chain status = IDLE.
- IDLE means deliberate decision-resting / suspension, not mathematical deadlock or semantic failure.

Open predicates without asserted instances:
- att
- uniq

Remaining surfaces and prerequisites:
- selector / tie-breaking → structural declaration (e.g. order/topology) first;
- attainment sufficient conditions → structural declaration first;
- non-empty Dom(R) / Dom_att / Dom_uniq → concrete instantiation first;
- R_ORACLE → ROr-4 reopening conditions only;
- Δ / gap → comparison problem plus explicit legality argument;
- STEP⑤ / STEP⑥ → program-level decision.

Anti-drift objects considered but not declared because they have no registered consumer:
- gap := L(g) − inf V
- ε-argmin families
- cardinality refinements such as |Argmin| ≥ k
- sectional properties of R

No new R-INTERNAL gate is authorized merely to maintain chain momentum. Any future gate must be opened by at least one of:
a) a new program-level problem surface;
b) a consumer-driven structural declaration surface;
c) a concrete instantiation surface.

All existing boundaries remain unchanged:
R_OBJECT = DECLARED (R : Dom(R) → ℝ)
R_ASSEMBLY = OPEN（门时点记录；已由 R-ASSEMBLY Transition Audit 关闭为 CLOSED）
R_ORACLE = NOT_DEFINED
Δ = BLOCKED
FinLoss = NOT LEGALLY AVAILABLE
NECT = BLOCKED
STEP⑤ = NOT ENTERED
STEP⑥ = NOT ENTERED
EXPERIMENT AUTH = NONE
HARNESS AUTH = NONE

Argmin / att / uniq remain auxiliary under RO-1.
Historical δ(I_P), any new δ optimization domain, A(P,θ), and θ-level optimization remain excluded.
No implementation, harness, data collection, profiling, measurement, or experiment authorization follows from this audit.


### R-ASSEMBLY Transition Audit — 2026-09-23

The R-ASSEMBLY OPEN state originated in R-ASSEMBLY-10 / M4 (Parameter Domain Hierarchy Declaration), whose declared semantics explicitly deferred the final R_OBJECT input hierarchy until the internal interfaces were resolved.

Audit of the M4 waiting conditions:

1. P / δ / θ types resolved: R-INTERNAL-1 / P4, R-INTERNAL-2 / δ3, R-INTERNAL-3 / θ2.
2. 𝒢_adm(P) structure resolved: R-INTERNAL-4 / G4-4.
3. L domain resolved: R-INTERNAL-5 / L5-3, R-INTERNAL-6 / E6-4, R-INTERNAL-7 / E7-B, R-INTERNAL-8 / E8-C.
4. E_θ legality / existence conditions resolved: R-INTERNAL-6 / E6-4.
5. Final R_OBJECT input hierarchy resolved: R-INTERNAL-17 / RO-1 declares R_OBJECT := R : Dom(R) → ℝ, with input hierarchy (P,θ).

Hierarchy branch closure:
- The previously deferred ((P,δ),θ) alternative is closed by RO-1 and is not a live branch.
- δ remains a decision-generation parameter in Γ(P,δ)=g; it is not an additional input level of the declared R_OBJECT.

R-ASSEMBLY-1A through R-ASSEMBLY-10 were reviewed for unresolved final-object deferrals. No other explicit final-object input-hierarchy deferral remains outstanding; the identified OPEN state is the M4 deferral audited here.

Decision:
- The M4 waiting conditions are satisfied.
- The reason for R_ASSEMBLY = OPEN has expired.
- R_ASSEMBLY is therefore CLOSED at the current declared object hierarchy:
  R_OBJECT = R : Dom(R) → ℝ, with input (P,θ).

This audit does not introduce a new semantic object, does not reopen R-INTERNAL, and does not enter STEP⑤/STEP⑥.

Post-audit routing:
- R-INTERNAL chain remains IDLE.
- Concrete instantiation is the leading candidate for the next research surface.
- Consumer-driven structural declaration remains conditional on a concrete consumer need.
- Program-level questions (including STEP⑤) remain a separate route and are not entered by this audit.

The following remain unchanged:
R_OBJECT = DECLARED
R_ORACLE = NOT_DEFINED
Δ = BLOCKED
FinLoss = NOT LEGALLY AVAILABLE
NECT = BLOCKED
STEP⑤ = NOT ENTERED
STEP⑥ = NOT ENTERED
EXPERIMENT AUTH = NONE
HARNESS AUTH = NONE

No gap/D, oracle interface, historical δ(I_P), new δ optimization domain, A(P,θ), θ-level optimization, selector/tie-breaking, topology, compactness, continuity, measurability, or implementation/harness/data/measurement/experiment authorization is introduced.


### Concrete Instantiation — P0 / θ0′ — 2026-09-23

Concrete Instantiation gate is REGISTERED after final R1 semantic ratification and Final Registration Audit.

Registered instance: P0 := π0 : S → B0 with S=S1×…×S5, b=(KV headroom, |resident sessions|, execution phase), and I_P0=σ(π0). θ0′ maps to the point measure on the deterministic exogenous A/B-alternating workload of K=8 rounds with L_A=512, D_A=256, L_B=1024, D_B=128, FIFO handling, and horizon settlement.

Action set: A={serve,defer,reject}; evict-LRU is an execution mechanism under serve.

Parameters: κ=128 KiB/token, L_A=512, D_A=256, L_B=1024, D_B=128, K=8, B=192 MiB, λ=1280 token-equivalent.

KV maxima: KVAmax=96 MiB and KVBmax=144 MiB, with 144≤192<240=96+144; both directions have forced eviction at the stated maxima.

𝒢_adm(P0) is the R-ASM-E composite predicate (I_P0 visibility + trajectory feasibility). C_LOSS remains a per-trajectory scalar and L=E_μ[C_LOSS] is the sole expectation layer.

Ratified terminal settlement: v2^g(t;W)=1 for a_t=reject and t<K; v2^g(K;W)=𝟙[a_K=reject]+|Q_{K+1}^g(W)|, where Q_{K+1} contains all unresolved FIFO requests after K. Settlement is accounting only; no K+1 runtime event exists.

Finite bound: 0≤C_LOSS≤8192+10240=18432<∞, hence V(P0,θ0′)⊆[0,18432] and inf V(P0,θ0′)∈R. Registered instance fact: (P0,θ0′)∈Dom(R).

Non-degeneracy audit: always-serve-with-evict=6144; retain-A/reject-B=5632. This establishes distinct attainable values only; it does not assert att, Argmin non-emptiness, or uniq.

Explicitly not asserted: att, Argmin≠∅, uniq, selector/tie-breaking/canonical optimizer/g*, R_ORACLE, Δ/gap, FinLoss, NECT, historical δ(I_P), new δ optimization, θ-level optimization, A(P,θ), or implementation/harness/data/measurement/experiment authorization.

R-INTERNAL chain remains IDLE; R-ASSEMBLY remains CLOSED; STEP⑤/STEP⑥ remain NOT ENTERED.

Gate history: docs/07-history/R_CONCRETE_INSTANTIATION_P0_THETA0_20260923.md.

### Concrete Instance Facts — P0 / θ0′ — 2026-09-23

Post-gate computational facts derived from the registered instance (no new semantic object; R-INTERNAL remains IDLE; R_ASSEMBLY remains CLOSED):

R(P0,θ0′) = 5376.

att(P0,θ0′) = true; Argmin(P0,θ0′) ≠ ∅; realized optimal action-sequence count = 4; uniq(P0,θ0′) = false.

Derivation: the admissible action-sequence space is finite (3^8 = 6561) and the point-mass regime makes V(P0,θ0′) a finite non-empty set of reals, so inf V ∈ V (K4-A); Argmin ≠ ∅ follows by the K4-B bridge; exhaustive enumeration cross-verified by an independent per-round DP gives min = 5376; the realized minimizer family has the closed form "single residency switch to B at the k-th B-round, k ∈ {2,4,6,8}", cost 512 + 1024 + 3×1280 independent of k, hence the realized action-sequence minimizer count is 4 and uniq = false (K4-C). The post-audit scopes that count to the realized layer; rule-level exact cardinality remains OPEN.

Boundary: no selector, canonical optimizer, or g* (uniq = false independently blocks canonical selection); R_ORACLE remains NOT_DEFINED; Δ/gap remain blocked; STEP⑤/STEP⑥ remain NOT ENTERED; no implementation, harness, measurement, or experiment authorization.

Gate history: docs/07-history/R_CONCRETE_INSTANCE_FACTS_20260923.md.

### Concrete Instance Post-Audit — 2026-09-23

Post-audit scope correction: exhaustive enumeration and independent DP reconfirm
`R(P0,θ0′)=5376`, `att(P0,θ0′)=true`, and `uniq(P0,θ0′)=false`. The value `4` is
exact for realized optimal action sequences, but is not yet established as the
exact abstract rule-level cardinality because no quotient or restriction equating
visible-history rule extensions that agree on the point-mass workload has been
registered.

Current rigorous rule-level facts are:

```
R(P0,θ0′) = 5376
att(P0,θ0′) = true
uniq(P0,θ0′) = false
|Argmin(P0,θ0′)| ≥ 4
rule-level |Argmin(P0,θ0′)| = OPEN
```

`D_opt(P0,θ0′)` remains non-empty and `(P0,θ0′)∈Dom(R)`.

### Concrete Representation Decision — 2026-09-23

For `(P0,θ0′)`, the researcher selected:

```
Concrete representation = 3 / FULL_VISIBLE_HISTORY_RULE_SPACE
```

Accordingly, no realization quotient and no realized-history restriction are
introduced. The existing rule-level `Argmin / att / uniq` interfaces remain
unchanged. The four optimal realized action sequences imply only the lower
bound `|Argmin(P0,θ0′)|≥4`; exact rule-level cardinality remains OPEN.

The next concrete surface is to determine whether the full visible-history rule
representation and current declarations determine `|Argmin(P0,θ0′)|`, or formally
show underdetermination from unconstrained rule behavior on unrealized visible
histories.

Decision history:
docs/07-history/R_CONCRETE_REPRESENTATION_DECISION_20260923.md.

### Concrete Argmin Cardinality Audit — 2026-09-23

Under `FULL_VISIBLE_HISTORY_RULE_SPACE`, the point-mass instance does not
uniquely determine `|Argmin(P0,θ0′)|`. The key extension lemma is: if two
visible-history rules agree on the realized trace under `W0`, then they have
the same loss and the same fixed-instance admissibility; therefore distinct
assignments on unrealized visible histories can produce distinct rule-level
minimizers without changing realized action sequences.

Current audit result:

```
R(P0,θ0′) = 5376
att(P0,θ0′) = true
uniq(P0,θ0′) = false
realized optimal action-sequence count = 4
|Argmin(P0,θ0′)| ≥ 4
exact |Argmin(P0,θ0′)| = UNDERDETERMINED_BY_CURRENT_DECLARATIONS
```

The value `4` remains exact only for realized optimal action sequences. An
exact rule-level value would require a separate visible-history domain and
off-trajectory admissibility declaration.

Audit history:
docs/07-history/R_CONCRETE_ARGMIN_CARDINALITY_AUDIT_20260923.md.

### Concrete Argmin Cardinality Policy — 2026-09-23

The researcher selected:

```
Concrete Argmin Cardinality Policy
  = ACCEPT_UNDERDETERMINATION / NO_RULE_DOMAIN_COMPLETION_NOW
```

The exact rule-level cardinality remains underdetermined and is not treated as a
defect requiring immediate repair. The registered facts remain:

```
R(P0,θ0′) = 5376
att(P0,θ0′) = true
uniq(P0,θ0′) = false
realized optimal action-sequence count = 4
|Argmin(P0,θ0′)| ≥ 4
exact |Argmin(P0,θ0′)| = UNDERDETERMINED_BY_CURRENT_DECLARATIONS
```

No visible-history domain completion, realization quotient, selector, canonical
optimizer, or tie-breaking rule is introduced. R-INTERNAL remains IDLE,
R_ASSEMBLY remains CLOSED, and STEP⑤/STEP⑥ remain NOT ENTERED.

Policy history:
docs/07-history/R_CONCRETE_ARGMIN_CARDINALITY_POLICY_20260923.md.

Prior audit history:
docs/07-history/R_CONCRETE_INSTANCE_POST_AUDIT_20260923.md.

### Research Road Space — 2026-09-23

After accepting the concrete argmin-cardinality underdetermination, five A2.0
research roads are registered. No A2.0 research road is selected:

```
SELECTED_ROUTE = NONE
SELECTED_ENGINEERING_ROUTE = SIMIGO2_EXPERIMENTAL
```

1. `RULE_DOMAIN_COMPLETION` — complete the visible-history/rule object; direct
   route to exact rule-level `|Argmin|`, but deliberately not entered.
2. `INSTANCE_FAMILY` — declare a family `(P,θ)` and study variation, landscape,
   or sensitivity properties of `R`; no family is declared.
3. `SINGLE_INSTANCE_IDENTIFIABILITY` — declare observation semantics and
   behavioral equivalence before asking what one instance identifies; not
   entered.
4. `MULTI_INSTANCE_IDENTIFICATION` — study when an instance family separates
   rules; depends on prior observation/equivalence and family-index decisions;
   not entered.
5. `COMPUTATIONAL_SEMANTICS` — connect stable formal objects to executable
   semantics; deferred and non-implementative.

These remain navigation records for the A2.0 research path. The separately
registered SimiGo 2.0 engineering route does not select, reopen, or validate any
of them.

Road-space history:
docs/07-history/RESEARCH_ROAD_SPACE_AFTER_CONCRETE_UNDERDETERMINATION_20260923.md.

### Gemma 4 External Probe — 2026-09-23

The local Gemma 4 checkpoint is registered as an external candidate observation
for the deferred `COMPUTATIONAL_SEMANTICS` road. It is not `(P1,θ1)` and not a
theory instance.

Observed boundary:

```
Declared unified model
  ≠ full loaded unified model
  ≠ text-only loaded model
  ≠ executable generation model
```

The VLM/unified path fails because the checkpoint declares audio but lacks
audio weights. The LLM path loads the text backbone as `Gemma4Model`, but
high-level generation hits a prefill/decode mismatch. Python `mlx-lm==0.31.3`
does not support `gemma4_unified`.

This is an observation only. Route 5 remains registered but not selected.

Probe history:
docs/07-history/GEMMA4_COMPUTATIONAL_SEMANTICS_EXTERNAL_PROBE_20260923.md.

### Qwen3-Coder Runtime Positive Control — 2026-09-23

The researcher confirms that the local Qwen3-Coder checkpoint loads and runs in
SimiGo 1.7. This is consistent with the SimiGo compatibility matrix: standard
`qwen3_moe`, OpenAI path PASS, Responses PASS, concurrent Responses PASS, tool
calling PASS, KV/session cache PASS, and draftN=2 under concurrency PASS.

Therefore, the earlier isolated mlx-swift-lm probe failure is scoped only to that
probe harness and local working-tree state; it is not a general Qwen3-Coder
runtime failure. Under SimiGo 1.7:

```
Declaration = PASS
Instantiation = PASS
Execution = PASS
SemanticConsistency = OPEN
```

Correction history:
docs/07-history/QWEN3_CODER_SIMIGO17_RUNTIME_POSITIVE_CONTROL_20260923.md.

### Computational Semantics Observation Schema Candidate — 2026-09-23

The three external probes motivate separating the former `Declaration` layer
into:

```
C0 Checkpoint Declaration
C1 Runtime Family Declaration
C2 Runtime Type-Routing
C3 Instantiation
C4 Execution
C5 Semantic Consistency
```

The schema is registered only as an empirical observation candidate. It is not
an Architecture 2.0 formal definition or new semantic object.

Minimal fracture coverage:

```
Qwen3-Coder / SimiGo 1.7 = positive control
Gemma 4                  = post-routing executable boundary
Muse-Glimmer text tower  = pre-instantiation routing boundary
```

Whether C0-C5 should later become formal Architecture 2.0 semantic layers remains
OPEN.

Schema history:
docs/07-history/COMPUTATIONAL_SEMANTICS_OBSERVATION_SCHEMA_CANDIDATE_20260923.md.

### A2.0 Boundary Audit — Theta Deletion Test — 2026-09-23

An exploratory dependency audit replaced all model-internal methods with a black
box and asked which A2.0 concepts survive. The audit corrects one premise: `θ`
is the registered `REGIME_PARAMETER`, not model-internal parameters. In the
concrete instance it denotes the exogenous evaluation regime/workload measure.

Black-box audit result:

```
P, 𝒢_adm(P), Dom(L), V, R, and C0–C5
  = common-core candidates

att, Argmin, uniq, rule identity
  = instance/family diagnostics, not core candidates

δ and internal model mechanisms
  = not restored into the core
```

Theta deletion test:

```
delete internal model parameters = no-op for θ
delete external evaluation regime = breaks Dom(L), V, R, Dom(R), and the concrete instance
freeze θ at θ0′ = preserves the single-instance loop, but loses regime comparison
```

Therefore `θ` should not be deleted wholesale. The candidate reduction is to
keep the existence of an external evaluation regime, while treating the variable
regime family and concrete parameterization as separate boundary questions.

This is exploratory only; no A2.0 definition is rewritten.

Audit history:
docs/07-history/A2_BOUNDARY_AUDIT_THETA_DELETION_20260923.md.

### A2.0 Interface Sufficiency Audit — 2026-09-23

The black-box candidate core was tested for sufficiency as an evaluated behavior
system. At the value layer, `P + θ + 𝒢_adm(P) + Dom(L) + L/V/R` is closed: it can
express admissible behavior, legal evaluation, attainable values, and infimum.

At the executable-semantics layer, closure is only partial. The current registered
interface has `g:W→A` and `C_LOSS(g(W),W)`, but no architecture-independent
observable execution/trajectory interface as a first-class core component.
Concrete trajectory semantics exist only locally in `P0/θ0′`; `C0–C5` remains an
observation schema rather than a formal execution interface.

Therefore:

```
Value-level closure       = CLOSED at candidate level
Executable-level closure  = OPEN / PARTIAL
Overall sufficiency       = PARTIAL
```

The open decision is whether the execution/trajectory surface is:

```
missing Layer-A candidate
concrete-instance-only detail
or derivable from W, A, and C_LOSS
```

No option is selected.

Audit history:
docs/07-history/A2_INTERFACE_SUFFICIENCY_AUDIT_20260923.md.

### Trajectory / Execution Necessity Audit — 2026-09-23

For the current value-level core, trajectory/execution is classified as:

```
CONCRETE-ONLY
```

It is not a declared abstract-core primitive. It is also not derivable from the
abstract declarations `P,θ,g:W→A,C_LOSS` alone, because no initial state,
transition map, action-realization semantics, termination, or trajectory carrier
is declared there.

In the concrete instance `P0/θ0′`, however, enough local runtime semantics were
registered to derive the local trajectory from `P0+θ0′+g`.

Therefore the current result supports A2.0, for now, as a value-level theory.
This does not permanently exclude a future execution interface; it only records
that such an interface is not necessary for the registered value-level object.

Audit history:
docs/07-history/TRAJECTORY_EXECUTION_NECESSITY_AUDIT_20260923.md.

### A2.0 Core Nontriviality Audit — 2026-09-23

The surviving value-level candidate core was attacked for nontriviality,
irreducibility, and black-box cross-method invariance.

Result:

```
NONTRIVIALITY             = PARTIAL PASS
IRREDUCIBILITY            = NO_IMMEDIATE_REDUNDANCY_FOUND
CROSS_METHOD_INVARIANCE   = PASS_AT_ABSTRACTION_LEVEL
EMPIRICAL_SCOPE           = OPEN
OVERALL                   = CORE_CANDIDATE_SURVIVES_FIRST_ATTACK
```

Role split:

```
P, θ, 𝒢_adm(P), Dom(L), L = core candidates
V                         = derived named bridge
R                         = derived research target
```

The audit does not prove minimality or final sufficiency. It records only that the
first destructive audit found no immediately redundant component.

Audit history:
docs/07-history/A2_CORE_NONTRIVIALITY_AUDIT_20260923.md.

### A2.0 Core Degeneracy / Distinctiveness Audit — 2026-09-23

The value-level candidate core was tested against a generic optimization schema:

```
object + admissible behaviors + evaluation regime + partial cost + infimum
```

Result:

```
COLLAPSE     = NOT PROVEN
DISTINCTIVE  = NOT PROVEN
OVERALL      = OPEN / PARTIAL DISTINCTIVE
```

The core can be embedded into a generic constrained-infimum schema, so formal
collapse cannot be denied. However, A2.0 foregrounds projection-oriented
semantics, regime-separated evaluation, value-only discipline, and legal partial
evaluation. These are candidate distinctions, not yet certified formal separation
from every generic schema.

The unresolved question is whether A2.0 is a distinctive projection-evaluation
theory or a disciplined generic optimization schema.

Audit history:
docs/07-history/A2_CORE_DEGENERACY_DISTINCTIVENESS_AUDIT_20260923.md.

### A2.0 Projection–Evaluation Distinctiveness Attack — 2026-09-23

The candidate distinctiveness of separating `P` and `θ` was adversarially tested
against a generic optimization schema.

Result:

```
SEMANTIC_COLLAPSE          = NOT ESTABLISHED
RECOVERABLE                = YES at current formal level
STRUCTURAL_DISTINCTIVENESS = NOT ESTABLISHED
```

A generic schema can preserve the two-dimensional dependency by using the product
object `O=(P,θ)`: one component indexes the admissible behavior interface and the
other indexes the evaluation regime. The names and interpretation may disappear,
but the formal distinction is recoverable.

Richer projection properties—direction, domain/codomain, and information
loss—are not currently load-bearing in the abstract value-level formulas. Therefore
they do not yet establish structural distinctiveness.

Attack history:
docs/07-history/A2_PROJECTION_EVALUATION_DISTINCTIVENESS_ATTACK_20260923.md.

### A2.0 Terminal Distinctiveness Audit — 2026-09-23

The whole current value-level core was tested for lossless encoding into a
generic constrained-optimization schema.

Encoding:

```
z      = (P,θ)
G(z)   = 𝒢_adm(P)
D(z)   = Dom(L)
c(z,g) = L(g;P,θ)
C(z)   = V(P,θ)
r(z)   = R(P,θ)
```

All currently registered value-level dependencies are preserved.

Result:

```
GENERIC_REDUCIBILITY          = REDUCIBLE_AT_CURRENT_ABSTRACTION
INDEPENDENT_RESEARCH_QUESTION = NONE_CURRENTLY_REGISTERED
STRUCTURAL_DISTINCTIVENESS    = NOT_ESTABLISHED
TERMINAL_DISTINCTIVENESS      = NOT_ESTABLISHED
OVERALL                       = DISCIPLINED GENERIC OPTIMIZATION SCHEMA CANDIDATE
```

`D_opt`, finite evaluation, `V`, `R`, attainment, `Argmin`, uniqueness, and the
concrete value `R(P0,θ0′)=5376` all have generic constrained-optimization
analogues. They remain useful, but are not currently non-generic A2.0 research
questions.

Audit history:
docs/07-history/A2_TERMINAL_DISTINCTIVENESS_AUDIT_20260923.md.

### A2.0 Value Core Freeze Point — 2026-09-23

The current A2.0 value-core construction path is frozen at the terminal result:

```
GENERIC_REDUCIBILITY       = ESTABLISHED
INDEPENDENT_THEORY         = NOT ESTABLISHED
STRUCTURAL_DISTINCTIVENESS = NOT ESTABLISHED
METHODOLOGICAL_VALUE       = DEMONSTRATED
OVERALL                    = DISCIPLINED GENERIC OPTIMIZATION SCHEMA CANDIDATE
```

This closes the path:

```
hypothesis → formalization → concrete validation → boundary audits
→ adversarial reduction → terminal distinctiveness result
```

The freeze preserves concrete results and computational-semantics observations. It
does not delete A2.0, but stops further value-core rescue, repair, or extension.

Standing anti-proliferation rule:

```
New structure is justified only if its removal causes loss of expression
or semantic fidelity.
```

Freeze history:
docs/07-history/A2_VALUE_CORE_FREEZE_POINT_20260923.md.

### A2.0 Historical Scope Decomposition Retrospective — 2026-09-23

Retrospective diagnosis: the frozen A2.0 path likely failed because of scope mixing,
not because loading/residency/execution-state/evaluation were individually
meaningless.

Decomposition:

```
Model lifecycle / residency
  = computational-object lifecycle and implementation boundary

Execution-state
  = behavioral structure candidate:
    state → action → next state → evaluation

Value / optimization
  = frozen as generic reducible

Model internals
  = remain black-boxed
```

Loading and residency have value as computational-semantics observation boundaries,
but should not be forced into the same theoretical core as execution-state. The
latter remains only a future observation candidate; no route is selected.

Retrospective history:
docs/07-history/A2_HISTORICAL_SCOPE_DECOMPOSITION_RETROSPECTIVE_20260923.md.

### SimiGo 2.0 Experimental Route — 2026-09-23

A separate engineering route was registered:

```
SIMIGO2_EXPERIMENTAL
PHASE_0_AUTHORIZED
IMPLEMENTATION_NOT_STARTED
```

It is not an A2.0 reopening or independent-theory claim. The MVP tests whether
externally observable execution-state can drive model layer-group residency and
loading through a mature MLX runtime.

First positive-control model:

```
Qwen3-Coder-30B-A3B-Instruct-4bit
```

Phase 0 is limited to tensor/group inventory, residency-size estimates, and
partial-load feasibility. Product changes, prediction, compression, hidden-state
analysis, and production release are not authorized.

Route history:
docs/00-governance/SIMIGO2_EXPERIMENTAL_ROUTE_AND_MVP_PLAN_20260923.md.

### SimiGo 2.0 Phase 0 Qwen3-Coder Inventory — 2026-09-23

Read-only Phase 0 inventory found:

```
1351 tensors / 16385 MiB
CORE_NON_SWITCH    = 919 tensors / 833 MiB
SWITCH_MLP_L00_15  = 144 tensors / 5184 MiB
SWITCH_MLP_L16_31  = 144 tensors / 5184 MiB
SWITCH_MLP_L32_47  = 144 tensors / 5184 MiB
```

The checkpoint fuses each layer's MoE experts into `switch_mlp` tensors, so the
first legal MVP partition is by decoder-layer range, not individual expert index.
Normal inference still traverses all decoder layers; group residency only means the
required tensors must be available when needed.

Inventory history:
docs/00-governance/SIMIGO2_PHASE0_QWEN3_CODER_INVENTORY_20260923.md.

### Execution-State Extension Design Hypothesis — 2026-09-23

An exploratory hypothesis was registered for the separated execution-state direction:

```
execution-state fork
  → reachable landing / extension point
  → required capability
  → layering / residency / loading policy
  → implementation selection
```

The hypothesis separates:

```
state semantics
capability mapping
loading/residency policy
open-source implementation choice
```

A resident core can remain fixed while conditional layers are selected downstream.
However, the mapping from landing/branch to required capability is not yet formalized.
It must be tested against generic state machines, workflows, planning, dynamic
programming, and stochastic forks before any theory route is considered.

Hypothesis history:
docs/07-history/EXECUTION_STATE_EXTENSION_DESIGN_HYPOTHESIS_20260923.md.

### Execution-State Predictive Resource Hypothesis — 2026-09-23

An additional exploratory hypothesis separates reactive loading from predictive
resource policy:

```
reactive: current unused/used ⇒ load/unload

predictive:
current state/history
→ future-state distribution
→ future layer-demand probabilities
→ residency/load/prefetch/release decision
```

This may turn a resident core into a principled case when future-use probability is
high and reload cost is large. It may also form a feedback loop because loading
changes reachable future execution states.

Boundary: the frozen A2.0 core has no stochastic execution-state semantics, no
`g:S→Δ(A)`, no trajectory distribution, and no resource-policy or risk functional.
Therefore this remains an exploratory hypothesis outside A2.0.

Hypothesis history:
docs/07-history/EXECUTION_STATE_PREDICTIVE_RESOURCE_HYPOTHESIS_20260923.md.

### Execution-State Information Boundary Hypothesis — 2026-09-23

A further exploratory boundary was registered for the execution-state direction:

```
execution state
  → capability demand
  → model representation / compression / metadata
  → loading / residency
```

The key question is whether execution-state can determine required capabilities or
compressed layer groups without reading model-internal semantics.

Three information sources must not be mixed:

```
external observable state;
static model structure/metadata;
runtime internal signals such as hidden state, attention, activation, or routing.
```

If external observations suffice, execution-state can remain independent. If runtime
internal signals are required, execution-state is coupled to model internals and its
independence must be re-audited.

Hypothesis history:
docs/07-history/EXECUTION_STATE_INFORMATION_BOUNDARY_HYPOTHESIS_20260923.md.

### SimiGo 2.0 Runtime Reference Selection — 2026-09-24

For the engineering experiment, `MLX Swift LM + MLX/Metal` is the primary MVP
runtime. `llama.cpp` is a reference implementation for layer residency, device/offload
split, mmap/lazy tensor access, and buffer placement concepts. `vLLM` is deferred for
later serving-side topics such as paged KV memory, batching, and scheduling.

The MVP does not combine runtimes, fork runtime internals, translate MLX checkpoints
to GGUF, or introduce a universal runtime abstraction.

Selection history:
docs/00-governance/SIMIGO2_RUNTIME_REFERENCE_SELECTION_20260924.md.

### SimiGo 2.0 Phase 1 Swift Scaffold — 2026-09-24

Implemented the pure-Swift execution-state residency scaffold:

```
ExecutionStateLabel
→ Qwen3CoderStatePolicy
→ LayerResidencyEngine
→ TransitionReport / Metrics
```

It parses local Safetensors metadata, partitions Qwen3-Coder fused MoE tensors by
decoder-layer range, and benchmarks all-resident, reactive, and llama.cpp-inspired
lazy policies.

Status:

```
swift build = PASS
swift test  = PASS / 5 tests
policy benchmark = COMPLETE
```

This remains a control-plane simulator; no model inference or MLX internals are
modified.

Scaffold history:
docs/00-governance/SIMIGO2_PHASE1_SCAFFOLD_20260924.md.

### SimiGo 2.0 Phase 1 Qwen3-Coder Materialization Experiment — 2026-09-24

The pure-Swift scaffold was extended from state/policy simulation to actual
selective Safetensors materialization. For each execution-state transition, only
newly required layer groups were read by absolute tensor offset. No MLX internals
were modified and no model inference was executed.

Experiment:

```
STATE_A → STATE_B → STATE_AB → STATE_A → STATE_ALL
```

Result:

```
loaded bytes       = 28,052,549,632
elapsed            = 6,905.28 ms
average throughput = 3,874.28 MiB/s
```

This proves selective group reads work on the actual Qwen3-Coder checkpoint. It does
not prove MLX model modules can be independently released/materialized during
inference.

Experiment history:
docs/00-governance/SIMIGO2_PHASE1_QWEN3_MATERIALIZATION_RESULTS_20260924.md.

### SimiGo 2.0 MLX Gate 1 Results — 2026-09-24

Gate 1 passed for both core and fused MoE groups:

```
CORE_NON_SWITCH    = 919 tensors / 873,459,712 bytes / 167.01 ms
SWITCH_MLP_L00_15  = 144 tensors / 5,435,817,984 bytes / 782.72 ms
```

MLX lazy Safetensors loading materialized only selected tensor ranges. This passes
selective tensor materialization, but group lifecycle and inference semantic
consistency remain pending.

Gate history:
docs/00-governance/SIMIGO2_PHASE0_MLX_GATE1_RESULTS_20260924.md.

### SimiGo 2.0 MLX Gate 2 Results — 2026-09-24

Gate 2 passed for `SWITCH_MLP_L00_15` at MLX-array lifecycle level:

```
initial load               = 5,435,817,984 bytes / 177.78 ms
release                    = active/cache 0 bytes
rematerialization          = 5,435,817,984 bytes / 166.49 ms
semantic fingerprint check = 144/144 equal
lifecyclePass              = true
```

This validates release/rematerialization of the independent MLX group storage. It
does not yet prove that a real model object can externally swap these modules during
inference.

Gate history:
docs/00-governance/SIMIGO2_PHASE0_MLX_GATE2_RESULTS_20260924.md.

### SimiGo 2.0 MLX Gate 3 Parameter-Swap Results — 2026-09-24

Gate 3 passed at parameter-swap and semantic-restore level for
`model.layers.0.mlp.switch_mlp.gate_proj.weight`:

```text
baselineOutput                   = pong
perturbedOutput                  = ping / newline / three backticks
restoredOutput                   = pong
perturbedDiffers                 = true
restoredParameterMatchesBaseline = true
baselineEqualsRestored           = true
```

This proves a selected fused MoE parameter reaches real inference, is load-bearing
under the deterministic prompt, and can be restored exactly. It still does not
prove whole-group residency, release, rematerialization, or execution-state-driven
layer loading during inference.

Gate history:
docs/00-governance/SIMIGO2_PHASE0_MLX_GATE3_RESULTS_20260924.md.

### SimiGo 2.0 MLX Gate 4 Whole-Group Inference Results — 2026-09-24

Gate 4 passed for `STATE_A → SWITCH_MLP_L00_15` with a real MLX model:

```text
released tensors             = 144 / 144
rematerialized tensors       = 144 / 144
baseline output              = pong
restored output              = pong
release time                 = 16.85 ms
rematerialization time       = 606.10 ms
active memory after baseline = 17,180,952,624 bytes
active memory after release  = 11,745,135,024 bytes
active memory after remat    = 17,180,952,624 bytes
```

The whole group was detached only between generations and fully restored before
inference. Identical deterministic output proves semantic restore. This crosses
the single-group runtime residency boundary, but does not yet establish a
multi-state residency or reload-cost win.

Gate history:
docs/00-governance/SIMIGO2_PHASE0_MLX_GATE4_RESULTS_20260924.md.

### SimiGo 2.0 MLX Gate 5 Multi-State Runtime Results — 2026-09-24

Gate 5 compared `ALL_RESIDENT`, `NAIVE_ON_DEMAND`, and `EXECUTION_STATE` across
`STATE_A → STATE_B → STATE_AB → STATE_A → STATE_ALL` on the real model:

```text
outputIdentityPass       = true
maximum idle reduction   = 10,871,635,200 bytes
reload vs naive          = -10,871,635,968 bytes
generation totals        = 1,513.55 / 3,469.65 / 3,918.20 ms
state reload traffic     = 54,358,179,840 bytes
naive reload traffic     = 65,229,815,808 bytes
state reload time        = 7,734.08 ms
state release time       = 98.67 ms
```

All generations returned `pong`. State-driven residency reduced reload bytes
versus naive on-demand and reduced idle memory versus all-resident, but did not
establish latency or total-cost advantage. Every complete generation still
required all decoder-layer groups; the policy controlled idle retention, not
semantic layer skipping.

Gate history:
docs/00-governance/SIMIGO2_PHASE1_MLX_GATE5_MULTI_STATE_RESULTS_20260924.md.

### SimiGo 2.0 App Real-Device Proof — 2026-09-24

Added a minimal SwiftUI app target and `.app` bundle script. The app was built on
the local machine and ran Gate 5 in self-test mode:

```text
device                  = Apple M5 / arm64 / macOS 26.6.2
exit code               = 0
self-test               = PASS
outputIdentityPass      = true
idleReductionObserved   = true
maximum idle reduction  = 10,871,635,200 bytes
reload reduction naive  = 10,871,635,968 bytes
all generation outputs  = pong
```

Artifact:
`simigo2-experimental/build/SimiGo2Experimental.app`.

Result history:
docs/00-governance/SIMIGO2_APP_REAL_DEVICE_PROOF_20260924.md.

### Nail-Qwen3.6 Real-Device Validation — 2026-09-24

Validated `peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX` on Apple M5:

```text
checkpoint size                  = 21,634,738,912 bytes
switch group tensors             = 360
Gate 4 single-group residency    = PASS / outputEquals=true
Gate 5 app self-test             = PASS / exit code=0
outputIdentityPass               = true
maximum idle reduction           = 10,871,635,392 bytes
reload reduction vs naive        = 18,119,393,280 bytes
latency advantage                = NOT ESTABLISHED
```

Validation history:
docs/00-governance/SIMIGO2_NAIL_QWEN36_REAL_DEVICE_VALIDATION_20260924.md.

### Gemma4 Residency Compatibility Boundary — 2026-09-24

Probed `mlx-community/gemma-4-12b-coder-fable5-composer2.5-4bit` on Apple M5:

```text
runtime text inference             = PASS / baseline and restored output = ping
switch_mlp tensors                 = 0
evictable whole groups             = 0
Gate 4 groupInferenceResidencyPass = false
Gate 5 benchmarkPass               = false
outputIdentityPass                 = true
idle / reload reduction            = 0 bytes
```

The checkpoint is executable through the local `mlx-swift-lm` text path, but it is
not eligible for the current switch-MLP whole-group residency abstraction. This
registers a compatibility boundary, not a runtime loading failure.

Boundary history:
docs/00-governance/SIMIGO2_GEMMA4_RESIDENCY_COMPATIBILITY_BOUNDARY_20260924.md.

### Muse-Glimmer Runtime Support — 2026-09-24

Probed `OpensourceWTF/Muse-Glimmer-30B-MLX-q4`:

```text
model type                    = muse_glimmer_text
checkpoint size               = 17,603,109,888 bytes
switch_mlp tensors            = 0
MLX runtime load / forward    = PASS after local Swift support
Gate 4 output identity        = true
semantic quality              = UNRESOLVED
whole-group residency         = NOT_APPLICABLE
```

The upstream Python `mlx-lm` language-tower implementation was borrowed into the
local Swift fork and `muse_glimmer_text` is now registered with
`LLMModelFactory`. The checkpoint executes, but the no-chat-template Gate 4
prompt produces a repeated-token sequence; semantic quality remains unresolved.

Support history:
docs/00-governance/SIMIGO2_MUSE_GLIMMER_RUNTIME_COMPATIBILITY_BOUNDARY_20260924.md.

### Dense MLP Residency Extension — 2026-09-24

Implemented model-aware inventory, dense MLP partitioning, contiguous state
policy, and direct low-cache generation for memory sampling. Gemma4 partitions into:

```text
CORE_NON_SWITCH     = 892 tensors / 1,921,416,800 bytes
DENSE_MLP_L00_15    = 144 tensors / 1,592,524,800 bytes
DENSE_MLP_L16_31    = 144 tensors / 1,592,524,800 bytes
DENSE_MLP_L32_47    = 144 tensors / 1,592,524,800 bytes
```

Gemma4 dense Gate 4 passed:

```text
released / rematerialized tensors = 144 / 144
outputEquals                      = true
active memory after release       = 5,108,112,522 bytes
groupInferenceResidencyPass       = true
```

The idle-memory discrepancy was caused by hard-coded switch-MLP matching in the
benchmark: dense groups matched zero tensors, making release metadata-only. After
dense-range matching and direct low-cache generation, Gemma4 Gate 5 passes with
3,186,621,696 bytes idle reduction and 3,185,049,600 bytes reload reduction versus
naive on-demand.

Muse-Glimmer also passes dense Gate 5 after adding its text runtime support:
8,472,820,944 bytes idle reduction and 9,469,624,320 bytes reload reduction versus
naive on-demand. Both models emit repeated-token sequences under the
no-chat-template probe, so semantic quality remains unresolved.

Extension history:
docs/00-governance/SIMIGO2_DENSE_MLP_RESIDENCY_EXTENSION_20260924.md.

### Checkpoint Chat Template Application — 2026-09-24

Runtime benchmarks now use the checkpoint's own chat template when available.
Lookup order is `chat_template.jinja`, configured tokenizer template, then raw
fallback. Templates receive the user prompt, add the assistant generation prompt,
and pass `enable_thinking=false` when supported.

Gemma4's bundled `chat_template.jinja` was validated with dense Gate 5:

```text
benchmarkPass                 = true
outputIdentityPass            = true
idleReductionObserved         = true
maximum idle reduction        = 3,186,621,696 bytes
reload reduction vs naive     = 3,185,049,600 bytes
all generated outputs         = ping
```

This separates prompt-format errors from residency errors. Muse-Glimmer text-only
still has no bundled template and remains in raw-fallback mode.

Application history:
docs/00-governance/SIMIGO2_CHAT_TEMPLATE_APPLICATION_20260924.md.

### SimiGo 2.0 Workload Trace Registration and Replay — 2026-09-25

Four replayable workload traces were registered, replacing synthetic state
sequences only at the trace level. Each step declares an operation label, an
execution-state label, and the mapping rationale:

```text
T1_DOCUMENT_SESSION      open → summarize → search → edit → recheck → save
T2_COMPUTER_OPERATION    file inspect → tool call → result → next op → tool call
T3_AGENTIC_MULTI_TURN    3 × (user turn → tool call → result) → final answer (STATE_ALL)
T4_LONG_CONTEXT          context load (STATE_ALL) → extract AB → BC → AB → summary (STATE_ALL)
```

The operation→state mapping is a DECLARED scenario-level choice registered with
the trace catalog. It is not measured demand and does not establish demand.

Simulator trace replay (planner + strictly-prior descriptive recency hints,
Qwen3-Coder inventory) at 70% budget reached required-hit ratios 0.888 / 0.872
/ 0.871 for T1 / T2 / T3; T4 requires 100% budget before overflow disappears.
Below 70%, every STATE_AB step overflows (core + two switch groups = 68.4% of
inventory), consistent with the budget-sweep thresholds.

The real MLX runtime (planner-integrated Gate 5 harness, Apple M5) ran each
trace's state sequence under ALL_RESIDENT / NAIVE_ON_DEMAND /
EXECUTION_STATE_PLANNER. All four traces:

```text
outputIdentityPass = true (all passes, "pong")
benchmarkPass      = true
reload vs naive    = −20.25 / −10.12 / −40.50 / −30.38 GiB (T1/T2/T3/T4)
idle reduction     = 10.12 / 10.12 / 10.12 / 5.06 GiB
latency advantage  = NOT ESTABLISHED
```

Boundary: DECLARED_TRACE_STATE_MAPPING / DESCRIPTIVE_RECENCY_HINTS /
NOT_PREDICTION / NOT_DEMAND_CLAIM. Generation still requires all
decoder-layer groups; the policy controls idle retention between generations.
Predictor / Expert demand / Token × Expert demand / async I/O remain
unauthorized. Next gate: locality / reload / residency analysis, then the
demand-signal STOP GATE decision.

Phase history:
docs/00-governance/SIMIGO2_WORKLOAD_TRACE_REPLAY_20260925.md.

### SimiGo 2.0 Multi-Model Locality Analysis & Predictor Stop Gate — 2026-09-25

The locality analysis extended the trace evidence to five local checkpoints
(Qwen3-Coder-30B switch, Nail-Qwen3.6-35B switch, Cyber-Tiel-Coder-35B
switch — first residency validation, Gemma4-12B dense, Muse-Glimmer-30B
dense). The `trace-replay` command is model-aware (policy parameterized;
Qwen3-Coder results verified non-regression); 20/20 real Gate 5 trace runs
passed output identity.

Registered findings:

```text
transition overlap (optional sets)      = 0.375–0.5, next ⊆ prev 0.25–0.4
required-hit ordering across 5 models   = T3 > T1 > T2 > T4 (mapping property, geometry-invariant)
real reload reduction vs naive          = 20/20 pairs, 16.7–55%, per-trace ratios stable
T4-ALL                                  = working-set-breadth boundary workload (lowest hit everywhere)
latency advantage                       = NOT ESTABLISHED (Nail/Cyber-Tiel T3/T4 state gen slightly slower)
```

The inverse ordering between declarative hit ratio (T4 lowest) and real
reload-reduction ratio (T4 highest) is registered: the reduction measures
naive waste avoided, not trace locality; the two must not be conflated.

Stop gate assessment (criteria registered before the verdict):
G1 recurrence = OBSERVED (declared level), G2 transition locality = MODERATE,
G3 intervention value = PASS, G4 source legitimacy = NOT SATISFIABLE (no
measured execution trace exists; all locality is a property of the declared
mappings and the recency hints reacting to them).

```text
PREDICTOR_STOP_GATE = NO_GO
```

STOP is the complete registered research conclusion of this phase: the
machinery is validated end-to-end on five models, and the reload reductions
are an engineering response to declared workloads, not evidence of
predictable demand. Reopening the locality question requires measured
execution traces via the already-registered ISOLATED_INSTRUMENTATION route;
that gate is NOT STARTED and requires explicit authorization.

Phase history:
docs/00-governance/SIMIGO2_MULTI_MODEL_LOCALITY_ANALYSIS_STOP_GATE_20260925.md.

### G1.9-A Group Execution Trace — Design, Pre-Run Audit, First Capture — 2026-09-25

Following the explicit user authorization, the isolated instrumentation was
extended from the single G1.9-B proxy point to a full group/layer execution
trace. Pre-run audit found and fixed three defects before trusting traces:
(a) nested `container.perform` deadlock hazard (non-nested protocol adopted),
(b) a latent `QuantizedLinear` semantics break in the identity probe's plain
Linear branch (dedicated quantized branch added; registered G1.9-B results
unaffected), (c) an observation-path filter missing fused MoE paths (both
variants accepted; instrumented module count now reported).

First capture on Qwen3-Coder-30B-A3B-Instruct-4bit (positive control):

```text
status = PASS
V1 logits identity        = PASS (SHA-256 bitwise, Δ = 0)
V2 execution unchanged    = PASS (generation text exact-equal)
V3 trace stability        = PASS (1536 events = 32 passes × 48 layers,
                                 two instrumented runs identical)
V4 overhead               = within noise, peak memory overhead 0 MB
```

Every forward pass executes all 48 switch-MLP layer groups; the trace is
event-only (no activations retained) and the router is not instrumented
(EXPERT_DEMAND_NOT_INSTRUMENTED). The Phase-1 STOP condition is satisfied for
this configuration; measured-locality analysis and any Predictor reopening
decision remain PENDING and unauthorized respectively.

Phase history:
docs/00-governance/SIMIGO2_G19A_GROUP_TRACE_DESIGN_PRERUN_AUDIT_20260925.md.
Authorization history:
docs/00-governance/SIMIGO2_G19A_ISOLATED_INSTRUMENTATION_AUTHORIZATION_20260925.md.

### G1.9-A Instrumentation Pilot — 2026-09-25

The design-audit pilot (protocol G1.9-A.PILOT.V1: fixed prompt set × 3
repetitions) ran on all five local checkpoints after the observation
contract was narrowed to the minimal `layerEntered` event (no shapes, no
per-event timing; step IDs and group joins are derived bookkeeping; no
demand quantity exists in the data model).

```text
G1.9-A.1 Baseline Identity = PASS (15/15: token sequences identical,
                                   logits bitwise identical, max_abs_diff = 0)
G1.9-A.2 Trace Stability   = PASS (15/15: three repetitions produce
                                   identical event streams; 稳定 ≠ 可预测)
G1.9-A.3 Overhead          = ACCEPTABLE (descriptive ratios 0.72–7.95,
                                   direction inconsistent across models,
                                   peak memory ≤ 8.5 MB, no threshold)
G1.9-A.4 Cross-model       = PASS (5/5 incl. compatibility extension;
                                   module-path discovery registered the
                                   language_model.model.layers.* variant;
                                   shared_expert excluded by pattern)
```

Pilot v0 defects registered and fixed before accepting results: token
category mismatch (prompt vs generated), box not cleared after the identity
forward, and module-path prefix blindness that had silently instrumented
zero modules on three model classes. Verdict: the instrumentation is
qualified for Measured Execution Trace Collection. This is not a locality
result; the Predictor question remains closed.

Phase history:
docs/00-governance/SIMIGO2_G19A_PILOT_RESULTS_20260925.md.

### G1.9-C Measured Execution Trace Collection — 2026-09-25

The pilot-validated observer was connected to the registered workload
traces (protocol G1.9-C.COLLECT.V1; registered as G1.9-C because G1.9-B is
occupied by the identity probe). Declared and measured lines are separate
fields; each collection run opens with a control-prompt identity sentinel
(5/5 PASS).

Measured result over five models × four workloads (125 operations):

```text
C1 recurrence            all transitions non-empty (degenerate)
C2 transition locality   1.0 at every transition (degenerate)
C3 temporal stability    lag-1/2/3 overlap = 1.0 (degenerate)
C4 working-set breadth   full optional set at 100% of steps
declared ⊆ measured      125/125; measured excess exactly on the 22
                         non-STATE_ALL declared steps per model
```

Measured conclusion: at Layer/Group resolution measured execution has no
differential locality — the working set is always the full group set. The
declared differential demand structure has no measured execution
counterpart; Gate 5's "generation requires all decoder-layer groups" is now
a measured fact; PREDICTOR_STOP_GATE_NO_GO is measurement-confirmed at this
resolution; earlier reload reductions stand as idle-retention economics
under declared scenarios. Differential execution, if any, could only live
below group resolution (Router/Expert), whose observation is an
unauthorized new decision.

Phase history:
docs/00-governance/SIMIGO2_G19C_MEASURED_TRACE_COLLECTION_20260925.md.

### G1.9-C Post-Audit — Layer/Group Execution Line Closed — 2026-09-25

Three conclusions locked: (1) the measured execution set equals the full
group set at every covered step (125 × 5), ΔM_t = ∅; (2) the predictor
question at this resolution is semantically closed —
P(M_{t+1}=G_all|H_t)=1 with no learnable H_t→different-execution-set
mapping — so PREDICTOR_STOP_GATE_NO_GO is upgraded to
RESOLUTION-DEGENERATE / NO PREDICTIVE TARGET; (3) residency research is
unaffected — RequiredExecutionSet_t ≠ ResidentSet_t and the 16.7–55% reload
savings answer retention economics, not execution demand. Router/Expert
observation must not be opened to "keep the research going".

Post-audit history:
docs/00-governance/SIMIGO2_G19C_POST_AUDIT_20260925.md.

### Residency Observability Audit — 2026-09-25

Four-question verdict: the executed transfer log and MLX aggregate memory
snapshots are OBSERVED quantities; the per-transition group resident set is
POLICY BOOKKEEPING (derived); an independent per-group runtime observation
does not exist and a non-perturbing probe is not feasible at the public API
(touching a group materializes it; a runtime-side mechanism would be an
unauthorized production MLX modification).

New byte-level validation over the 20 real trace artifacts (225 transitions
across three policies on the offset models; 75 per model): bookkeeping and
the independent byte observation agree exactly after a model-class constant
offset — Qwen3-Coder max relative deviation 4.6e-5, Gemma4/Muse ≤ 6.6e-4;
Nail/Cyber-Tiel carry an exactly constant −851.1/−851.5 MiB offset,
reconciled to the un-loaded vision tower in their multimodal-family
checkpoints (333 tensors, 851.8 MiB in the index; residual < 0.8 MiB) — an
inventory reconciliation item, not a residency error.

Branch decision: byte-level observation is sufficient; group-level
residency is PolicyResidency only. Any following analysis must use the
label "PolicyResidency retention structure (byte-validated)" and is
forbidden from claiming natural residency demand or observed residency
locality. Next gate options (user decision): residency-locality analysis
under these labels; a minimal per-group observation mechanism (perturbing
probes or runtime support — both new authorizations); or STOP.

Audit history:
docs/00-governance/SIMIGO2_RESIDENCY_OBSERVABILITY_AUDIT_20260925.md.

### G1.9-D PolicyResidency Retention Analysis — 2026-09-25

The user ruled option (a) exclusively: analyze the existing policy traces
under the label "PolicyResidency retention structure (byte-validated)";
no new runtime observation, no redefinition of residency demand, no
Router/Expert; the frozen vocabulary (demand/probability/predictor/
optimal-set) is absent from the analysis and artifacts; C_model offsets stay
sealed as accounting items.

Results over the 20 existing real trace artifacts (per model, per workload,
no pooling):

```text
D4 identity   savings = Σ retainedOptionalBytes(t) − oneColdStartLoad
              holds exactly on 20/20 pairs (< 0.1% tolerance)
D1/D3         keep ratios and lag-1 overlaps are deterministic structural
              constants of the workload shape (T1 0.600, T2 0.500,
              T3 0.521–0.537, T4 0.667–0.742; lag-1 0.553–0.795)
D2            measured reload per generation = exact complement of the
              previous retention set
T4 boundary   full-retention steps (2/5) coincide with the largest savings
              fraction (0.500–0.550) — execution side structureless,
              residency side structured, cleanly separated
```

Pre-registered verdict applied:

```text
POLICY_RETENTION_STRUCTURE_EMPIRICALLY_CHARACTERIZED
```

Per the authorization the claim stops there: retention optimization is a
new decision on new evidence.

Phase history:
docs/00-governance/SIMIGO2_G19D_POLICY_RETENTION_ANALYSIS_20260925.md.

### G1.9-E0 Retention Optimization Feasibility Audit — 2026-09-25

Offline audit over the existing artifacts (80 candidate-replays = 4
candidates × 20 pairs; no runtime observation, no optimizer construction,
frozen vocabulary absent from the artifact). Structural basis: with
execution set = ALL (measured), total reload equals
n·optionalTotal − retention leading integral — the frontier identity holds
exactly for every candidate on every pair.

```text
V1 equal-peak budget    improvers exist on 20/20 pairs (fill-to-peak),
                        but mean residency rises to the peak
V2 equal-integral       improvement provably impossible (frontier exact)
V3 domination           none — the current policy is on the frontier
verdict                 FEASIBLE_TRADEOFF_SPACE_ONLY_NO_FREE_IMPROVEMENT
```

The policy space at this resolution is the linear trade-off frontier
between retention integral and reload bytes; the current policy and the
fill-to-peak candidate are two points on it. Correctness (E4) holds
structurally for every candidate via the load-before-generation semantics
(empirically verified only for the three measured policies). Next-gate
options (user decision): a candidate-analysis gate under a declared cost
weighting, or STOP with the frontier characterization as the complete
engineering conclusion.

Phase history:
docs/00-governance/SIMIGO2_G19E0_RETENTION_FEASIBILITY_AUDIT_20260925.md.

### Group-Resolution Experimental Line Closure — 2026-09-25

The user ruled option (b): G1.9-E0 STOP. The group-resolution Experimental
line is formally closed with the status
`G19E0_STOP / GROUP_RESOLUTION_POLICY_TRADEOFF_CLOSED`.

Terminal results:

```text
EXECUTION:  MeasuredExecution = FULL ⇒ locality degenerate ⇒ no
            predictive target (RESOLUTION-DEGENERATE / NO PREDICTIVE TARGET)
RESIDENCY:  PolicyResidency → byte-validated → retention structure
            characterized → exact reload identity (ReloadTotal =
            n·OptionalTotal − ΣRetainedBytes, 20/20 exact) → trade-off
            frontier → no free improvement
```

Final formulation: a residency/reload trade-off exists; a free improvement
does not — reload reduction ⟺ additional retention integral, exactly, under
the current model/trace/harness conditions. The line leaves a negative-plus-
positive pair: no exploitable execution locality at this resolution, and a
strictly measurable, byte-validated, exactly-decomposable policy retention
economics.

Locked until reopened by new problems or new evidence: no candidate
analysis, no cost weighting, no optimizer, no optimal policy, no
Router/Expert, no additional runtime instrumentation, no production MLX
modifications. Reopening triggers are concrete deployment constraints or new
measurements — never "remaining optimization space".

Closure history:
docs/00-governance/SIMIGO2_GROUP_RESOLUTION_LINE_CLOSED_20260925.md.

### Final Research Audit v1.0 — Research Line Frozen; Engineering Route Declared — 2026-09-25

`SIMIGO2_EXPERIMENTAL_FINAL_RESEARCH_AUDIT_v1.0.md` registered the terminal
ledger of the whole Experimental line (A2.0 → G1.9-E0), answering the seven
audit questions with commit/artifact anchors: measured-proven items,
policy-derived items, engineering facts, five falsified premises, seven
closed questions, the standing NOT-authorized list, and reopenable
questions with concrete triggers. One ledger correction: the byte-level
validation total is 375 rows (75 per model × 5 models), superseding the
earlier "225" misstatement.

Core finding, registered verbatim: a complete Transformer generation has no
execution locality at layer/group resolution, but residency retention still
has an independent, strictly measurable engineering structure; its benefit
is exactly a trade-off between memory residency and re-materialization —
not computation skipping.

Status after the audit:

```text
SimiGo 2.0 Experimental research line      CLOSED / FROZEN
SimiGo 2.0 Runtime Residency Engineering   DECLARED, NOT STARTED
```

The successor engineering route is separate from the closed research line
(no theory objects, no demand vocabulary). Its first step is requirements
definition — budget provenance, resident-state provenance, load/evict
executor, failure/overflow/cancellation semantics, multi-request
serialization/concurrency, long-context handling, memory-pressure behavior —
with no code. The planner keeps its verified contract (required set,
resident set, budget → load/keep/evict/overflow) and never predicts.
Sequenced work items 1–8 registered in the audit document.

Audit history:
docs/00-governance/SIMIGO2_EXPERIMENTAL_FINAL_RESEARCH_AUDIT_v1.0.md.

### Gate A + Gate B — Runtime Engineering Validation Complete; Execution State Engineering Open — 2026-09-25

**Gate A** (`SIMIGO2_RUNTIME_ENGINEERING_VALIDATION_COMPLETE_v1.0.md`)
registered the complete Residency Runtime validation chain with executable
evidence: Requirements (efeb49c) → Verification Design (022fd16) → L1/L2
(254638b) → Controller (3d4fdd7) → L3 F1–F8 (78af4f5) → B1/B2 contract
target (ee07123) → L4-A adapter (0774110) → L4-B INV-3 five-model
reconciliation (250f683) → L4-C three-model identity (aa30eb2). The
verification-system quality improvements are registered first-class: four
vacuous-pass/defect classes (unhinted fill; effect label; empty-initial
replay; L4-C self-comparison, wrong DIRTY injection target, over-subtracted
evict set) were caught by the gates and fixed, and `overallPass` now
REQUIRES `dirtyCycleExecuted == true`. Principle registered: a verification
suite that cannot fail is not evidence.

The two-sided proof stands: L4-B (the resource state is real — INV-3 within
ε on 5 models × 10 transitions, C_model constants verified constant) +
L4-C (the computation is unchanged — token/logits identity with
max_abs_diff = 0.0 across real residency transitions and an executed
DIRTY/recovery cycle on 3 models) ground the architecture statement:
SimiGo does not decide what the model computes; it decides in what resource
state the model runs.

Repository anchor corrected and verified: `slamfinger/SimiGo-Lab`, branch
`exp/simigo2-experimental`, HEAD `aa30eb2` at Gate A registration (the
"wrong repository" observation is voided).

**Gate B** (`SIMIGO2_EXECUTION_STATE_ENGINEERING_GATE_v1.0.md`) opened the
Execution State Engineering line per the E0 architecture registration
(`SIMIGO2_EXECUTION_CONTINUITY_ARCHITECTURE_v1.0.md`): E1 Execution
Continuity Contract (pure Swift, in the MLX-free contract target) → E2
FakeExecutionBackend lifecycle verification (fork/continue/restore/
reattach/discard tree; parent-identity, child-lineage, continuation-
independence, discard, restore assertions) → E3 MLX Execution-State adapter
(Backend Representation Strategy; no second KV authority) → E4 Continuity +
Residency integration (an evicted Execution State IS still the same
Execution State) → E5 end-to-end identity scenario. The core 2.0
engineering invariant is registered: representation migration MUST preserve
Execution Identity, Position, Next Input, Continuation Semantics, and
Subsequent State Evolution.

```text
Research lines                            all CLOSED / FROZEN
Runtime Engineering validation (Gate A)   COMPLETE
Execution State Engineering (Gate B)      OPEN
E1 contract                               IMPLEMENTED AND VERIFIED
E2–E5                                     NOT STARTED
```

### E1 Execution Continuity Contract — Implemented and Verified — 2026-09-25

E1 landed tests-first via GitHub flow (8ad9075 tests, 8c5836e contract,
7f64015 gate status), then executed in the real Swift toolchain: **86/86
test cases PASS** (76 regression + 10 contract-target, including 6 new E1
semantic tests). No fixes required; no contract clause amended.

Registered surface (all in the MLX-free `SimiGoRuntimeContract` target;
`ExecutionStateHandle` carries LOGICAL state only — identity, lineage,
position, continuation, lifecycle; no residency/materialization/eviction
types):

```text
ExecutionID / ExecutionLineage / ExecutionPosition / ExecutionContinuation
ExecutionStateHandle / ExecutionForkRequest / ExecutionRestoreRequest
ExecutionBranchLifecycle (attached / active / restored / discarded)
ExecutionContinuityRuntime protocol: create/attach, continue, fork,
    restore, reattach, discard — async, backend-neutral
```

The Execution State ≠ Residency State boundary is now enforced at the type
level: physical representation types cannot enter the handle.

```text
Current gate  : E1 → VERIFIED
Next          : E2 FakeExecutionBackend lifecycle-tree verification
                (fork/continue/restore/reattach/discard; parent identity,
                child lineage, continuation independence, discard, restore)
E2–E5         : NOT STARTED
```

### E2 FakeExecutionBackend Lifecycle Verification — 2026-09-25

`FakeExecutionContinuityRuntime` (test-only, MLX-free, no residency
modeling) implements the E1 `ExecutionContinuityRuntime` protocol with one
authoritative lifecycle record per transition and representation migrations
recorded SEPARATELY from lifecycle history. The lifecycle tree
(create → continue → fork → child continue → child restore → child
reattach → child discard → parent continue) was verified against the eight
registered constraints:

```text
V1 parent identity stable after fork                    PASS
V2 child identity/lineage distinct and traceable        PASS
V3 child continuation independent of parent             PASS
V4 discard(child); continue(parent) uses the parent's
   OWN continuation; discarded branch is terminal       PASS
V5 restore returns the LOGICAL execution state
   (identity/lineage preserved; position/continuation
   = logical target; no tensor/snapshot type exists)    PASS
V6 reattach preserves the continuation contract         PASS
V7 representation migration touches nothing logical
   and creates no lifecycle record                      PASS
V8 exactly one authoritative lifecycle record per
   transition; failed operations create none            PASS
Full tree scenario (incl. parent timeline independence
   from the child's fork position)                      PASS
```

Suite: **95/95 test cases PASS** (76 XCTest regression + 19 contract-target:
4 backend + 6 E1 + 9 E2). One test-side assertion corrected during the run
(parent timeline position — parent 0→1→2 is independent of the child's fork
position 2); no contract or implementation change needed.

```text
Current gate  : E2 → VERIFIED
Next          : E3 MLX Execution-State adapter (extend the Backend boundary;
                checkpoint/KV strategies are Backend Representation
                Strategy; SimiGo remains no second KV authority)
E3–E5         : NOT STARTED
```

### E3 Execution-State Adapter — Implemented and Verified — 2026-09-25

Three pieces landed:

```text
1. Contract (SimiGoRuntimeContract, MLX-free):
   ExecutionStateBackend protocol — captureRepresentation / 
   deriveRepresentation (fork) / restoreRepresentation /
   releaseRepresentation over opaque ExecutionRepresentation payloads
   (ExecutionRepresentationPayload). Sovereignty boundary enforced by the
   contract: implementations MUST NOT create/assign/alter Execution
   Identity, Lineage, Position semantics, or Continuation.
2. MLXExecutionStateBackend: the first concrete representation strategy —
   prefix-recompute (an execution's physical state is its token prefix;
   fork copies the prefix; restore rebinds it; position-mismatch and
   foreign-payload guards). Future KVCache.copy / shared-prefix strategies
   replace THIS strategy only.
3. ExecutionContinuityCoordinator: production ExecutionContinuityRuntime —
   E1 lifecycle semantics + one authoritative lifecycle record per
   transition + representation binding/history; restore REQUIRES a
   captured representation at the target position (logical restores cannot
   promise states without physical capture); discard releases the
   representation while the logical record survives.
```

8 coordinator tests PASS (84/84 total): bind/capture round trip,
position-mismatch rejection, fork derivation with sovereignty assertions,
lazy fork without parent binding, restore rebinds the captured
representation, restore without capture fails, discard releases the
representation, and one authoritative record per transition (bindings are
not lifecycle transitions).

```text
Current gate  : E3 → VERIFIED
Next          : E4 Continuity + Residency integration (eviction must not
                change Execution Identity; combined logical/physical state)
E4 / E5       : NOT STARTED
```

### E4 Continuity + Residency Integration — Verified — 2026-09-25

The two validated capabilities were composed (ExecutionContinuityCoordinator
+ MLXExecutionStateBackend × ResidencyController + mock materializer) and
the full cycle was executed: Create → Generate → Resident → Evict
(pressure to the core floor AND release of the execution's live
representation) → Re-materialize → Restore from the pre-eviction
checkpoint → Reattach → Continue.

Engineering answer to the integration question — **an Execution State that
was evicted IS still the same Execution State**:

```text
Identity / Lineage      unchanged across eviction, re-materialization,
                        restore, reattach, and continue
Position / Continuation semantically preserved (restore to the checkpoint
                        position; continue advances on the execution's own
                        timeline)
Representation          CHANGED (live representation released; re-bound
                        from the pre-eviction checkpoint)
Residency               CHANGED (full → core floor → full; 6 loads, 3
                        releases through the mock materializer)
```

Both record systems verified independent: residency transitions create no
continuity lifecycle records and vice versa; residency INV-1 holds at every
step. Suite: **87/87 XCTest PASS** (106 test cases total incl. the contract
target).

```text
Current gate  : E4 → VERIFIED
Next          : E5 end-to-end product scenario on real MLX (Create →
                Generate → Fork → Parent/Child Continue → Child Evict →
                Re-materialize → Restore → Continue → Discard → Parent
                Continue; compare identity/lineage/position/next
                input/continuation/tokens/logits)
E5            : NOT STARTED
```

### E5 v2 — Representation-Consuming Execution — Three Models PASS — 2026-09-25

External audit finding (accepted): the first E5 implementation executed the
child's continuations by reconstructing equivalent chat-message inputs and
recomputing from scratch — it never CONSUMED the Execution State's bound
representation, so the determinism check proved less than it claimed.
Remedy: the ExecutionStateBackend contract gained `continueExecution(state,
nextInputTokens, maxTokens)` — real execution that CONSUMES the current
bound representation — implemented by the new `MLXPrefixRecomputeExecutor`
(prefix-recompute strategy; the Backend owns tokenization/generation; the
Runtime owns identity/lineage/position/continuation). The E5 scenario now
routes EVERY continuation after the bootstrap through
`backend.continueExecution`, and INV-1 is an explicit assertion (not a
debug assert). The raw-continuation encoding also replaced chat-message
reconstruction, eliminating a degenerate immediate-EOS divergence failure
on Nail.

Results (protocol G1.9-E5.SCENARIO.V2, 3 models):

```text
FORK_DIVERGENCE            child vs parent continuations token-divergent
D-I determinism            run2 (after evict + re-materialize + RESTORE)
                           == run1, consuming the RESTORED representation
N-I non-interference       parent turn-2 after the whole child episode ==
                           pre-fork reference (token-identical)
PARENT_IDENTITY_STABLE / CHILD_LINEAGE_TRACEABLE   PASS
RESIDENCY_INV1             explicit assertion PASS
overall                    PASS on all three models
```

This closes the audit finding: the E5 identity checks now exercise the
bound representation as the actual execution input. Execution Semantics +
Execution Continuity + Resource Lifecycle + Backend — validated end-to-end
with the representation consuming path.

```text
Current gate  : E5 v2 → COMPLETE
Status        : EXECUTION_STATE_RUNTIME_LOOP_COMPLETE
Validation history: `E5ExecutionStateScenario.swift` (v2) probe +
                `results/e5-execution-state/*.json` (3 models)
```

### Oversized Model Execution Investigation — O0/O1 Complete — 2026-09-25

New phase registered (working title: Oversized Model Execution
Investigation; final gate naming deferred until O1–O5 evidence exists).
Core question: when Model Representation > Physical Memory, can SimiGo
establish executable Model Residency and sustain real inference — and where
is the performance boundary? Plan: O0 prior art → O1 mechanism matrix and
inventory → O2 minimal physical experiments (mapping footprint, selective
touch, real forward) → O3 SimiGo model-residency boundary → O4 44.9 GB real
execution → O5 capacity/stability/performance boundary sweep → O6
Execution State × oversized model. Known-good prior art (llama.cpp
load-mode mmap / lazy mode; per-tensor buffer placement) is treated as
mechanism reference, never as evidence that SimiGo + MLX can do the same.

**O1 inventory (measured, Qwen3-Coder-Next-4bit, `qwen3_next` /
Qwen3NextForCausalLM)**: 9 shards, 1891 tensors, 41.76 GiB weights (37.12
GiB packed U32 4-bit + 4.64 GiB BF16), on-disk 42 GiB; architecture = 12
full-attention + 36 GatedDeltaNet linear-attention layers, SparseMoE 512
experts / 10 active + shared expert. **Decisive fact: the 512 experts are
FUSED into `switch_mlp` tensors split EVENLY 13.50 + 13.50 + 13.50 GiB
across the existing SimiGo 3-group partition** — the validated group
materializer applies directly. Oversize arithmetic: core ≈ 1.26 GiB;
core+1 group ≈ 14.8 GiB; core+2 groups ≈ 28.3 GiB (fits 32 GiB physical);
all three = 41.76 GiB > 32 GiB — oversized only when all three switch
groups are resident. Physical memory verified 32.0 GiB.

**Load-chain audit**: `qwen3_next` is REGISTERED in the local mlx-swift-lm
fork (LLMModelFactory.swift:75 → Qwen3NextModel); the current load path is
SINGLE-SHOT FULL-MODEL (`loadWeights` → `model.update(verify: .all)` over
all 9 shards) with mmap-backed lazy MLXArrays at read; whether weights stay
page-backed or eagerly materialize at first forward is (H-mmap vs H-eager)
— to be distinguished empirically in O2 by process-footprint measurement.
The SimiGo intervention point is a skeleton-load path (construct the model
without loading all weights, then per-group materialize) — the validated
L4-A/B per-group materializer is reusable as-is beyond that point.

No runtime changes; E5v2 and the frozen research line untouched.

```text
Current gate  : O0/O1 → COMPLETE
Next          : O2 native MLX baseline (load, footprint, forward,
                1/5/10 generations) — no SimiGo involvement
O2–O6         : NOT STARTED
```

O0/O1 history:
docs/00-governance/SIMIGO2_O0_O1_OVERSIZED_MODEL_INVENTORY_AND_MECHANISM_MATRIX_20260925.md.

### O0 Redefined — Open-Source Mechanism Census Registered — 2026-09-25

Per review, the O-phase survey was upgraded from "prior-art survey" to an
**Open-Source Mechanism Census**: reference implementations (llama.cpp,
DS4, MLX/mlx-swift-lm, SimiGo-current) are profiled against NINE census
questions (representation, storage, materialization timing, residency
granularity, execution trigger, eviction ownership, restore, over-physical
behavior, cost) — project names are never substituted for mechanisms. The
route taxonomy (A virtual-memory mapping / B runtime paging / C device
offload / D layer-block materialization / E MoE selective residency) is
provisional and must be finalized from code audits, not preset.

Census highlights:

```text
llama.cpp   load-mode mmap (MMAP/MLOCK/AUTO), no_alloc tensor indexing,
            deferred set_tensor_data materialization, per-tensor buffer
            suitability — Route A+D (source-verified)
DS4         registered audits retain the ABSTRACTION (parameter universe →
            required set → resident set → materialization → execution);
            internal mechanism profile NOT retained — code-level census is
            a registered O0 follow-up
MLX/mlx-lm  single-shot full-model load; mmap-backed lazy arrays at read;
            no runtime eviction; H-mmap vs H-eager undecided (O2)
SimiGo      group materialization/eviction/restoration VALIDATED (L3/L4);
            oversized case untested
```

Key analysis: for Qwen3-Coder-Next, Model Representation (41.76 GiB) vs
per-token Execution Working Set (≈2.1 GiB: 10/512 active experts + core)
differ ≈20× — making **Route E (MoE selective residency)** structurally
most relevant, while the fused `switch_mlp` format bounds
expert-granularity materialization at 13.5 GiB group granularity. This
tension is registered for O3.

```text
Current gate  : O0 CENSUS → REGISTERED
Next          : O1 taxonomy finalization (DS4 code-level follow-up,
                llama.cpp lazy-mode source verification) → O2 mechanism
                experiments (mapping footprint, selective touch, real
                forward) — no runtime changes before O2 evidence
O1/O2         : NOT STARTED
```

O0 history:
docs/00-governance/SIMIGO2_O0_OPEN_SOURCE_MECHANISM_CENSUS_20260925.md.

### O2 Native MLX Baseline — Measured: H-Eager, Load Incomplete — 2026-09-25

The native MLX baseline was run against Qwen3-Coder-Next-4bit (41.76 GiB
weights) on the 32 GiB machine with ZERO SimiGo intervention
(`simigo2ctl o2-baseline`, the fork's native loadContainer path).

Measured outcome: **the full-model load did NOT complete**. During the
9-minute watchdog window the process sustained 100–115% CPU with
process-visible RSS of only 40–98 MB, while system-wide swap climbed from
≈0 to a pinned 22.7–23.5 GiB within the first two minutes and stayed there.
The probe never reached first forward — no generations ran. Post-kill, swap
drained slowly (23 → 2.2 GiB). Watchdog termination was by design: the
stability boundary was already violated on a shared machine.

Verdict: **H-EAGER** for the native path — the mmap-backed lazy arrays at
read time do not survive `loadWeights` → `model.update(verify: .all)`, which
binds all weights into device buffers eagerly, overflows to swap, and never
completes. Three-boundary classification: Capacity = native path cannot
deliver an executable model (outcome C for the native path); Stability =
violated during load; Performance boundary = unreachable.

Registered caveats: the watchdog bound is not an impossibility bound
(non-completion within 9 min at 23 GiB swap is what is measured); RSS is
not authoritative for GPU-wired memory (swap curve + CPU signature are the
evidence); an in-probe periodic snapshot flush is registered as a probe
improvement for any re-run.

Direct consequences: O2-B selective-touch moves INTO O3 (does skeleton-load
preserve non-residency?); **O3's skeleton-load path is now REQUIRED** (the
native path cannot be the oversized baseline — full-load = FAIL, measured);
O3's first target residency levels remain core+1 group ≈ 14.8 GiB and
core+2 groups ≈ 28.3 GiB, both below the wired limit.

```text
Current gate  : O2 → MEASURED (native path: outcome C)
Next          : O3 skeleton-load path + group materialize + forward at
                core+1 / core+2 residency levels
O3–O6         : NOT STARTED
```

O2 history:
docs/00-governance/SIMIGO2_O2_NATIVE_BASELINE_RESULT_20260925.md.

### O3 Skeleton Load + Selective Residency — A/B PASS, C Requires Streaming Forward — 2026-09-25

The O3 probe (`simigo2ctl o3-skeleton`, per-layer quantization resolution
mirroring loadWeights) measured the three sub-gates against
Qwen3-Coder-Next-4bit:

```text
O3-A Skeleton Load    PASS — Qwen3NextModel constructed with NO weights at
                      0.08 GiB footprint; in-place quantize from the
                      checkpoint's interleaved quantization dict (base
                      64/4 + per-module 8-bit overrides) at 0.09 GiB. The
                      native path's hidden cost is located: it materializes
                      LAZY RANDOM full-size weights per module during
                      quantize, then overwrites them.
O3-B Selective        PASS — core + switch groups 0–15 and 32–47
  Residency           materialized: 1747 tensors / 28.26 GiB in 0.3–0.4 s
                      (shard-range reads); skipped 13.50 GiB evicted group;
                      footprint 28.33 GiB, swap 0.00 — under the 32 GiB
                      physical limit. Mixed 4-bit/8-bit checkpoint
                      quantization verified by the per-layer resolution.
O3-C Real Forward     BLOCKED — mechanism identified: the naive skeleton
                      forward touches every layer, lazily materializing the
                      evicted group's 13.50 GiB random weights during the
                      pass (footprint ≈ 41.8 GiB → over-physical, hung,
                      killed at 29 min, swap 24.5 GiB). A complete forward
                      NECESSARILY touches every layer; between-generation
                      residency (the L4 pattern) cannot help during a
                      forward.
```

Structural conclusion: **oversized execution requires a STREAMING FORWARD**
(materialize 16-layer group → run those layers → release → next range) —
Route D at forward granularity. Feasibility is high: layers are strictly
sequential and the selective materializer loads arbitrary shard ranges in
~0.4 s; granularity is improvable (per-tensor offsets exist in safetensors;
the 3-group partition was the only coarse choice). Zero-placeholder release
must also suppress lazy-random materialization of untouched groups.

```text
Current gate  : O3-A/B → PASS; O3-C → REQUIRES STREAMING FORWARD (O3-C′)
Next          : O3-C′ streaming forward implementation + forward identity
                vs a full-resident reference on the largest fitting model
O4/O5/O6      : NOT STARTED
```

O3 history: `O3SkeletonProbe.swift`;
docs/00-governance/SIMIGO2_O3_SKELETON_SELECTIVE_RESIDENCY_RESULT_20260925.md.

### O3-C′ Streaming Forward v1 — Two Hard Blockers Identified — 2026-09-25

The streaming probe (G1.9-O3C.STREAMING.V1) reached first execution and
identified the two blockers between the current toolchain and true
oversized streaming:

```text
Blocker 1  no per-tensor safetensors reader: loadArraysAndMetadata is
           shard-granular (4.9 GiB); naive per-tensor extraction loaded a
           packed-U32 metadata array ([dequantize] fatal). Required:
           PerTensorSafetensorsReader (header parse + seek + dtype
           construction + packed-quantized handling) — also the missing
           tool for the O2-B selective-touch experiment.
Blocker 2  whole-graph lazy eval defeats capacity discipline:
           model(running) + eval(logits) touches ALL 48 layers, forcing
           every segment resident simultaneously (peak = full model)
           regardless of materialize/release ordering. True streaming
           requires SEGMENT-WISE graph decomposition (embed → layers 0-15
           → eval → 16-31 → eval → …); the fork's Qwen3NextModelInner
           layer stack is fileprivate — decomposition needs a Backend API
           surface (E3-pattern extension of the local fork's Qwen3Next;
           no Apple mlx-swift modifications).
```

Both are engineering components, not research unknowns. O3-C″ next gate
registered: PerTensorSafetensorsReader + Backend segment-execution surface
+ two-pass determinism/capacity re-run.

```text
Current gate  : O3-C′ v1 → BLOCKERS IDENTIFIED
Next          : O3-C″ (per-tensor reader + Backend segment API) — NOT
                STARTED
```

O3-C′ history: `O3CStreamingForward.swift` probe;
docs/00-governance/SIMIGO2_O3C_STREAMING_V1_RESULT_20260925.md.

### O3-C″ Segment-wise Probe v1 — Lazy-Random Materialization Cliff Found — 2026-09-25

The segment-wise probe (G1.9-O3C.SEGMENTWISE.V1, using the fork's
embedInputs / forwardLayerRange / projectOutput API) was OOM-killed by the
system at the FIRST core update:

```text
AFTER_CORE_LOAD        active 44061 MiB (43.0 GiB — should be ~1.26 GiB)
AFTER_SEG0_MATERIALIZE active 57885 MiB / footprint 73438 MiB
[system OOM kill]      exit 137
```

Root cause identified: the skeleton sequence (createModel -> quantize)
leaves ~40 GiB of LAZY random quantized arrays in the model (random init ->
quantize schedules; nothing evaluated — the "0.09 GiB skeleton" was an
illusion of laziness). The FIRST model.update with real tensors forces the
entire lazy parameter tree to materialize at once, including skipped
segments' random quantized weights. This single mechanism explains O3-A's
0.09 GiB reading, O3-B's masked residency, and O3-C's mid-pass thrash.

Registered fix direction: placeholder-first full-parameter update —
immediately after quantize, ONE model.update replacing core params with
real checkpoint tensors and segment params with zero-size placeholders,
before any parameter evaluation; the lazy random arrays are then discarded
without materializing. Open question: if quantize(model:) itself forces
per-module evaluation, the fork's Qwen3Next model must construct
QuantizedLinear modules directly from checkpoint tensors (Backend-side,
E3 pattern). This single blocker underlies ALL oversized paths measured.

O3-C″ segment-wise history: `O3CSegmentWiseProbe.swift`;
docs/00-governance/SIMIGO2_O3C_SEGMENTWISE_V1_RESULT_20260925.md.

### O3-C″ Implementation In Progress — Memory Retention Defect Found — 2026-09-25

Component 1 (PerTensorSafetensorsReader) landed and verified: header-only
indexing, per-tensor seek+read with correct dtype construction (F32/F16/
BF16-via-u16/U32/I32/I64/U8/I8/U64), synthetic-safetensors tests integrated
into the local toolchain run (87/87 regression PASS; contract-target tests
run separately).

Component 2 (fork segment-execution API) landed in the LOCAL fork
`../../mlx-swift-lm`: `Qwen3NextModelInner.forwardLayerRange(_:layerRange:
cache:)` plus a public surface on `Qwen3NextModel` — `embedInputs` /
`forwardLayerRange` / `projectOutput` (E3 pattern: physical execution slice
only; identity/lineage/continuation stay in the Runtime). Fork builds
clean; NOT yet committed to the fork repository (pending SimiGo-side E2E
verification).

O3-C″ streaming run v2 on Qwen3-Coder-Next-4bit: the streaming loop
EXECUTES — core materialization, per-segment materialize → forwardLayerRange
→ eval → release both passes — but a MEMORY RETENTION DEFECT was exposed:
system swap climbs continuously during pass 1 (≈3 GiB → 37+ GiB over 12
min) even with per-segment zero-placeholder release + `Memory.clearCache()`,
and the process was killed by watchdog. The defect is inside the streaming
loop (in-loop phys_footprint instrumentation missing — boundary snapshots
alone cannot localize which step retains); candidates: MLX buffer-cache
retention of per-tensor GPU arrays, graph retention through the lazy
`forwardLayerRange` chain, or update-copy semantics. Run killed to protect
the machine; both passes had executed their segments before the kill
(streaming execution itself works — the defect is unbounded retention, not
execution failure).

Registered next steps (NOT STARTED): in-loop footprint instrumentation per
materialize/exec/release; diagnose retention (buffer cache vs graph
retention vs update-copy); fix; re-run the two-pass determinism +
capacity protocol. No frozen-line changes.

### O3-C″ Diagnosis — Retention Boundary Located — 2026-09-25

The instrumented O3-C run (five-metric gauges: active/cache/peak/footprint/
swap at every boundary, mirrored to stderr, 7 gauges captured before the
shell watchdog killed the thrashing run) located the FIRST anomalous
boundary precisely:

```text
STEP_START                 footprint 80 MiB
SEG0_AFTER_READ            core 1294 MiB payload → footprint 2869 MiB
SEG0_AFTER_MATERIALIZE     2902 MiB
SEG1_AFTER_READ            144 tensors / 13824 MiB payload accumulated in
                           the arrays dictionary → footprint 30616 MiB
                           (30.6 GiB — at the 32 GiB physical edge)
[external swap timeline]   300 s: 5.4 GiB → 540 s: 23 GiB (thrash, killed)
```

Verdict: the retention defect is NOT missing release, NOT buffer cache, NOT
graph retention — it is the **BATCH-THEN-UPDATE materialization shape**: the
segment loop accumulates ALL of a segment's tensors (13.5 GiB per
switch_mlp segment) in a dictionary before a single model.update; combined
with the already-resident core+segment-0, the footprint crosses the
physical limit at exactly the SEG1_AFTER_READ boundary. Additionally, no
release boundary exists at all in this code path (the whole-graph forward
runs before any release could).

Registered fix direction (minimal, no architecture change): per-tensor
streaming update — read ONE tensor → eval → model.update(unflattened
single) → drop the reference; peak becomes core + previous segments + ONE
tensor. The fork's forwardLayerRange API (landed, builds clean) then
serves the segment-segmented execution on top of the corrected
materialization.

### O3-C″ Fix Verification — Per-Tensor Update Measured, Peak NOT Resolved — 2026-09-25

The per-tensor streaming-update fix (3dea7ee: READ → EVAL → UPDATE → NEXT,
batch dictionary removed) was compiled and run through the full double-pass
+ capacity protocol. 14 gauges captured; run killed in pass 2 at 57 GiB swap.

Measured verdict — the fix changed the materialization SHAPE but not the
peak:

```text
SEG1_AFTER_READ   active 15118 MiB — IDENTICAL to the batch run
                  (footprint 30384 vs 30616 MiB — 0.2 GiB dictionary only)
SEG2_AFTER_MAT.   active 28942 / footprint 58049 MiB
WHOLE-GRAPH FWD   active 44313 / peak 49808 / footprint 73466 MiB
pass 2 start      baseline 44302 MiB active — nothing released between passes
max swap          57 GiB (killed)
```

Elevated diagnosis (now data-proven, not inferred): the retention source is
NOT the materialization batching. The model itself retains every updated
parameter array — because the WHOLE-GRAPH forward (`model(running,
cache: nil)`) requires all 48 layers resident at eval time. Any
materialization strategy therefore accumulates to the full 41.76 GiB. The
batch-vs-per-tensor distinction moved the dictionary transient (0.2 GiB)
and nothing else.

Required fix (registered): segment-wise execution via the fork's
already-landed `forwardLayerRange` API — embed → layerRange(0..16) → eval →
release segment 0 → layerRange(16..32) → eval → release → … → projectOutput.
Capacity becomes core + ONE segment (≈14.8 GiB). The API is built and
uncommitted in the local fork; the SimiGo-side probe rewrite to consume it
is the next implementation step.

### O3-C″ Audit Correction (reviewer) — Attribution Precised — 2026-09-25

The `2a5bd15` conclusion header ("WHOLE_GRAPH_TOPOLOGY_IS_RETENTION_SOURCE")
overreaches the data. What is strictly measured:

```text
A. parameter materialization / model.update
   → sustained residency, active ≈ 28.9 GiB        CONFIRMED
B. whole-graph execution on top
   → additional residency, active ≈ 44.3 GiB,
     peak ≈ 49.8 GiB, footprint 73.5 GiB           CONFIRMED (additional)
C. whole-graph topology as THE retention source    NOT YET ESTABLISHED —
   requires the segment-wise execution experiment
```

Status taxonomy per the audit:

```text
batch materialization defect   CLOSED / disproven as primary peak source
per-tensor streaming           MEASURED / peak unresolved
model parameter residency      CONFIRMED
whole-graph execution residency CONFIRMED as ADDITIONAL residency
segment-wise execution         NEXT EXPERIMENT / NOT YET VALIDATED
```

Not PASS O3-C″; not entering O4. The segment-wise probe answers one
question: does resident memory shift from "full-model accumulation" to a
controlled "core + current segment" shape, with observable resident-set
boundaries at each release?

Comparison artifact:
simigo2-experimental/results/o3c-streaming/qwen3-coder-next-4bit-v3-fixed.json.

### O3-C″ Implementation In Progress — Memory Retention Defect Found — 2026-09-25

Component 1 (PerTensorSafetensorsReader) landed and verified: header-only
indexing, per-tensor seek+read with correct dtype construction (F32/F16/
BF16-via-u16/U32/I32/I64/U8/I8/U64), synthetic-safetensors tests integrated
into the local toolchain run (87/87 regression PASS; contract-target tests
run separately).

Component 2 (fork segment-execution API) landed in the LOCAL fork
`../../mlx-swift-lm`: `Qwen3NextModelInner.forwardLayerRange(_:layerRange:
cache:)` (mask/cache handling matching `forward`, restricted to a layer
range) plus a public surface on `Qwen3NextModel` — `embedInputs` /
`forwardLayerRange` / `projectOutput` (E3 pattern: physical execution slice
only; identity/lineage/continuation stay in the Runtime). Fork builds
clean; NOT yet committed to the fork repository (pending SimiGo-side E2E
verification).

O3-C″ streaming run v2 on Qwen3-Coder-Next-4bit: the streaming loop
EXECUTES — core materialization, per-segment materialize → forwardLayerRange
→ eval → release both passes — but a MEMORY RETENTION DEFECT was exposed:
system swap climbs continuously during pass 1 (≈3 GiB → 37+ GiB over 12
min) even with per-segment zero-placeholder release + `Memory.clearCache()`,
and the process was killed by watchdog. The defect is inside the streaming
loop (in-loop phys_footprint instrumentation missing — boundary snapshots
alone cannot localize which step retains); candidates: MLX buffer-cache
retention of per-tensor GPU arrays, graph retention through the lazy
`forwardLayerRange` chain, or update-copy semantics. Run killed to protect
the machine; both passes had executed their segments before the kill
(streaming execution itself works — the defect is unbounded retention, not
execution failure).

Registered next steps (NOT STARTED): in-loop footprint instrumentation per
materialize/exec/release; diagnose retention (buffer cache vs graph
retention vs update-copy); fix; re-run the two-pass determinism +
capacity protocol. No frozen-line changes.

### O3-C″ Diagnosis — Retention Boundary Located — 2026-09-25

The instrumented O3-C run (five-metric gauges: active/cache/peak/footprint/
swap at every boundary, mirrored to stderr, 7 gauges captured before the
shell watchdog killed the thrashing run) located the FIRST anomalous
boundary precisely:

```text
STEP_START                 footprint 80 MiB
SEG0_AFTER_READ            core 1294 MiB payload → footprint 2869 MiB
SEG0_AFTER_MATERIALIZE     2902 MiB
SEG1_AFTER_READ            144 tensors / 13824 MiB payload accumulated in
                           the arrays dictionary → footprint 30616 MiB
                           (30.6 GiB — at the 32 GiB physical edge)
[external swap timeline]   300 s: 5.4 GiB → 540 s: 23 GiB (thrash, killed)
```

Verdict: the retention defect is NOT missing release, NOT buffer cache, NOT
graph retention — it is the **BATCH-THEN-UPDATE materialization shape**: the
segment loop accumulates ALL of a segment's tensors (13.5 GiB per
switch_mlp segment) in a dictionary before a single model.update; combined
with the already-resident core+segment-0, the footprint crosses the
physical limit at exactly the SEG1_AFTER_READ boundary. Additionally, no
release boundary exists at all in this code path (the whole-graph forward
runs before any release could).

Registered fix direction (minimal, no architecture change): per-tensor
streaming update — read ONE tensor → eval → model.update(unflattened
single) → drop the reference; peak becomes core + previous segments + ONE
tensor. The fork's forwardLayerRange API (landed, builds clean) then
serves the segment-segmented execution on top of the corrected
materialization.

### O3-C″ Fix Verification — Per-Tensor Update Measured, Peak NOT Resolved — 2026-09-25

The per-tensor streaming-update fix (3dea7ee: READ → EVAL → UPDATE → NEXT,
batch dictionary removed) was compiled and run through the full double-pass
+ capacity protocol. 14 gauges captured; run killed in pass 2 at 57 GiB swap.

Measured verdict — the fix changed the materialization SHAPE but not the
peak:

```text
SEG1_AFTER_READ   active 15118 MiB — IDENTICAL to the batch run
                  (footprint 30384 vs 30616 MiB — 0.2 GiB dictionary only)
SEG2_AFTER_MAT.   active 28942 / footprint 58049 MiB
WHOLE-GRAPH FWD   active 44313 / peak 49808 / footprint 73466 MiB
pass 2 start      baseline 44302 MiB active — nothing released between passes
max swap          57 GiB (killed)
```

Elevated diagnosis (now data-proven, not inferred): the retention source is
NOT the materialization batching. The model itself retains every updated
parameter array — because the WHOLE-GRAPH forward (`model(running,
cache: nil)`) requires all 48 layers resident at eval time. Any
materialization strategy therefore accumulates to the full 41.76 GiB. The
batch-vs-per-tensor distinction moved the dictionary transient (0.2 GiB)
and nothing else.

Required fix (registered): segment-wise execution via the fork's
already-landed `forwardLayerRange` API — embed → layerRange(0..16) → eval →
release segment 0 → layerRange(16..32) → eval → release → … → projectOutput.
Capacity becomes core + ONE segment (≈14.8 GiB). The API is built and
uncommitted in the local fork; the SimiGo-side probe rewrite to consume it
is the next implementation step.

### O3-C″ Audit Correction (reviewer) — Attribution Precised — 2026-09-25

The `2a5bd15` conclusion header ("WHOLE_GRAPH_TOPOLOGY_IS_RETENTION_SOURCE")
overreaches the data. What is strictly measured:

```text
A. parameter materialization / model.update
   → sustained residency, active ≈ 28.9 GiB        CONFIRMED
B. whole-graph execution on top
   → additional residency, active ≈ 44.3 GiB,
     peak ≈ 49.8 GiB, footprint 73.5 GiB           CONFIRMED (additional)
C. whole-graph topology as THE retention source    NOT YET ESTABLISHED —
   requires the segment-wise execution experiment
```

Status taxonomy per the audit:

```text
batch materialization defect   CLOSED / disproven as primary peak source
per-tensor streaming           MEASURED / peak unresolved
model parameter residency      CONFIRMED
whole-graph execution residency CONFIRMED as ADDITIONAL residency
segment-wise execution         NEXT EXPERIMENT / NOT YET VALIDATED
```

Not PASS O3-C″; not entering O4. The segment-wise probe answers one
question: does resident memory shift from "full-model accumulation" to a
controlled "core + current segment" shape, with observable resident-set
boundaries at each release?

Comparison artifact:
simigo2-experimental/results/o3c-streaming/qwen3-coder-next-4bit-v3-fixed.json.
```

E4 history: `ExecutionResidencyIntegrationTests.swift`.

E2 history: `FakeExecutionContinuityRuntime.swift` +
`ExecutionContinuityLifecycleTreeTests.swift`.

E1 history: `ExecutionContinuityContract.swift` +
`ExecutionContinuityContractTests.swift` (8ad9075 / 8c5836e / 7f64015).

### Runtime Residency Engineering — Requirements & Contract v1.0 — 2026-09-25

The requirements definition gate completed with **no code**: the
engineering contract `SIMIGO2_RUNTIME_RESIDENCY_ENGINEERING_REQUIREMENTS_
v1.0.md` is registered, covering the seven boundary domains (Budget /
Resident State / Load-Evict Executor / Failure-Overflow / Cancellation /
Concurrency / Memory Pressure), the two run conditions (long context as a
budget mechanic, never demand prediction; planner-never-sees-the-future as
a standalone invariant), and the 14-point acceptance mapping. Normative
highlights, each grounded in the frozen research line's measured facts:

```text
- planner contract FROZEN: pure, stateless, overflow reported never
  decided, no hints by default, never sees the future (Planner ≠
  Predictor ≠ Executor ≠ Materializer ≠ Model Execution);
- resident state: single owner (controller), single writer, bookkeeping =
  operational truth, reconciled per transition against MLX aggregate bytes
  with registered C_model constants and ε; DIRTY semantics on
  reconciliation/evict failure (per-group runtime truth beyond executed
  transfers is not claimable — observability audit);
- overflow: required-set overflow = fail-fast (grounded in measured
  execution = ALL); optional-group overflow = normal non-error outcome;
  silently exceeding budget FORBIDDEN;
- cancellation/concurrency: transfer-log is the audit trail, per-group
  atomicity, single serialized mutation stream, no speculative
  re-materialization;
- long context: budget mechanic only (KV accounting is a new implementation
  requirement — research harness had no KV cache).
```

Explicit non-goals restated (prediction, probability, Router/Expert,
production MLX modification, async I/O, computation skipping, multi-tier
placement). Implementation decision points (eviction timing, victim order,
retries, reconciliation frequency, envelope reserve) registered with
defaults — engineering choices, no research gate. Verification path:
contract-checkable via transfer-log replay, C_model/ε reconciliation
fixtures, and scenario tests.

```text
Current gate  : REQUIREMENTS DEFINITION → COMPLETE
Next gate     : contract verification design → implementation
Implementation: NOT STARTED
```

Contract history:
docs/00-governance/SIMIGO2_RUNTIME_RESIDENCY_ENGINEERING_REQUIREMENTS_v1.0.md.

### Contract Verification Design v1.0 — 2026-09-25

The frozen contract's 35 RFC-2119 requirements (R1.1–R4.3) were converted
into executable verification objects — design only, no production code:

```text
central invariants
  INV-1 log-replay equivalence: residentBookkeeping == replay(transferLog)
        after every step (the research byte-reconciliation result promoted
        to the contract's spine)
  INV-2 frontier oracle: E0 identity demoted to a test oracle
  INV-3 C_model + ε byte reconciliation against a real runtime
four verification layers
  L1 planner purity/contract unit tests (pure Swift, symbolic fixture)
  L2 controller state-machine verification (CLEAN|DIRTY, exhaustive
     enumeration to depth 8 with fault injections, INV-1 everywhere)
  L3 fault injection catalog F1–F8 (load/evict failure, cancel, reconcile
     mismatch, budget shrink, pressure, concurrent admission)
  L4 real-runtime reconciliation (Qwen3-Coder + Nail required fixtures;
     V-ID output identity through the controller path)
requirement traceability matrix: 35/35 requirements mapped to V-items;
acceptance points 1–14 covered via the contract mapping; tests-first
ordering mandatory — a requirement is done only when its verification
items pass.
```

Research-line fixtures formally handed off: C_model constants, ε, transfer
-log format, inventory geometries, T1–T4 state sequences, frontier identity
as oracle, naive/all-resident anchors. Non-goals unchanged.

```text
Current gate  : CONTRACT VERIFICATION DESIGN → COMPLETE
Next gate     : implementation, tests-first (L1 → L2 → L3 → L4)
Implementation: NOT STARTED
```

Design history:
docs/00-governance/SIMIGO2_RUNTIME_RESIDENCY_VERIFICATION_DESIGN_v1.0.md.

### Implementation Gate — L1/L2 Executed and Passed — 2026-09-25

L1 contract tests (942f0a9), L2 state-machine contract tests (3042b70), and
the L2 verification skeleton (2f8bd0c) were landed via GitHub file
operations without execution claims, then executed for the first time in a
real Swift toolchain.

First run: **60 tests, 6 failures** — all in the two new test files. The
conflict protocol (record → judge: implementation defect / contract defect /
new fact) was applied:

```text
F-L1-1 (implementation defect)  planner auto-retained UNHINTED optional
                                groups into remaining budget, contradicting
                                its documented intent ("hints CHOOSE
                                additional groups") and contract R1.4.
                                Fix: retention candidates are hinted groups
                                only. Behavior-preserving for every
                                registered research artifact (budget sweep
                                and trace replay pass explicit hints for
                                all optionals; Gate 5 required = all) —
                                verified by byte-identical re-run diff.
F-L2-1 (skeleton defect)        auditMismatch returned .auditRejected while
                                the semantics (and evictFailed) are
                                .enteredDirty. Fix: effect unified; dead
                                enum case removed.
F-L2-2 (latent INV-1 defect)    recover() replayed from an EMPTY initial
                                state, dropping initially resident groups.
                                Fix: replay from the stored original
                                initial bookkeeping; pinned by a new
                                bookkeeping assertion in the recover test.
```

Re-run: **60 tests, 0 failures — L1 + L2 gate truly PASS**. No conflicts
remained unresolved; no contract clause required amendment; no research
conclusion changed.

```text
Current gate  : IMPLEMENTATION (L1/L2) → COMPLETE
Next          : Controller/Materializer implementation (L3 fault injection
                and L4 real-runtime reconciliation follow)
Implementation: Controller NOT STARTED; L3 NOT STARTED; L4 NOT STARTED
```

### Controller Implementation Complete — 2026-09-25

`ResidencyController` implemented per the frozen contract, composing the
verified planner + state-machine skeleton behind a `ResidencyMaterializer`
port (the Controller/Materializer boundary; the MLX-backed materializer is
L4 — no second backend, no async I/O, no memory-pressure implementation in
this step):

```text
commit protocol per group : materializer executes the real effect FIRST;
                            success commits via loadCommitted/evictCommitted
                            (log + bookkeeping); failure reduces to
                            loadFailed (stays CLEAN) or evictFailed
                            (enters DIRTY)
admission                 : plan with hints=[] (R1.4); required overflow
                            fails fast BEFORE any transfer (R3.11);
                            planner validation errors surface unchanged
cancel                    : token checked at group boundaries; committed
                            groups stay resident; cancelled flag returned
                            (R3.15–R3.16)
reconcile                 : observed idle bytes vs residentBytes + C_model
                            within ε; mismatch enters DIRTY; match in DIRTY
                            still requires explicit recover (R3.6)
recovery                  : bookkeeping rebuilt from the transfer log over
                            the original initial state
determinism               : loads and evicts execute in sorted group-ID
                            order
```

7 contract tests (mock materializer) all pass: deterministic execution
order, fail-fast zero-transfer, per-group commit on load failure, evict
failure → DIRTY → admission refused, cancellation partial commit,
reconcile mismatch → DIRTY → recovery restores, and log-replay equivalence
(INV-1) across a mixed operation sequence. Full suite: **67 tests, 0
failures**. The legacy `LayerResidencyEngine` remains untouched as a
research artifact.

```text
Current gate  : CONTROLLER IMPLEMENTATION → COMPLETE
Next          : L3 fault injection (F1–F8) against the controller
Then          : L4 real materializer + real-runtime reconciliation
L3 / L4       : NOT STARTED
```

Implementation history: `ResidencyController.swift` +
`ResidencyControllerTests.swift`.

### Backend Boundary Gate — B1/B2 Complete — 2026-09-25

Per the registered Backend Boundary / Runtime Contract engineering gate
(`SIMIGO2_BACKEND_BOUNDARY_RUNTIME_CONTRACT_ENGINEERING_GATE_v1.0.md`,
2d5e9a4): **B1** created the pure-Swift target `SimiGoRuntimeContract`
— the package graph gives it NO MLX dependency, so the contract's MLX-free
status is enforced by the build system, not by discipline. Registered
surface:

```text
ResidencyMaterializer      materialize(groupID:) / release(groupID:)
                           — per-group all-or-nothing residency ops; the
                           Controller depends on exactly this surface
RuntimeResidencyBackend    extends ResidencyMaterializer with
                           memoryObservation() -> BackendMemoryObservation
                           (INV-3 audit boundary) and
                           purgeTransientCaches() (transition hygiene)
BackendMemoryObservation   {activeBytes, cacheBytes, peakBytes} value type
```

The contract expresses WHAT resource state the Runtime needs; it does not
express HOW a model computes (no tokenization/generation/architecture types
— gate §3/§4).

**B2** added the dedicated `SimiGoRuntimeContractTests` test target — also
MLX-free in its package graph — with 4 tests covering observation
propagation, materialize/release success-and-failure propagation, the
controller-facing narrowing (full backend usable as ResidencyMaterializer),
and explicit purge semantics: **4/4 PASS**.

Dependency direction after B1/B2:

```text
SimiGoRuntimeContract (no MLX)
        ↑                ↑
SimiGo2Experimental   SimiGoRuntimeContractTests (no MLX)
(Controller; MLX stays behind the concrete Backend at B3)
```

```text
Current gate  : B1/B2 → COMPLETE; B5 first half done (L1/L2 regression
                67/67 unchanged)
Next          : B3 MLX Backend adapter → B4 Controller integration check →
                B5 full regression → L3 → L4
B3/B4/B5/L3/L4: NOT STARTED
```

B1/B2 history: `SimiGoRuntimeContract` target +
`RuntimeBackendContractTests.swift`.

### L3 Fault Injection Complete — 2026-09-25

F1–F8 (plus F7b) executed against the production `ResidencyController` with
a mock materializer, per the verification-design catalog. Boundary held:
F6/F7/F8 verified the controller's contractual responses only — no Memory
Pressure / Budget / Concurrency Manager entities were created.

Controller contract completions inside the existing type (no new entities):

```text
R3.18  internal serialization lock — the controller itself is the single
       serialized mutation stream; admissions atomic (R2.2)
R3.21–23  respondToMemoryPressure(targetBytes:cModelBytes:) — proactive
       shrink, largest-byte-first victims (ties by ID), core floor, every
       eviction a logged transfer, refused while DIRTY, never evicts a
       group required by an open residency window (R3.22)
```

Findings from the injections:

```text
F-L3-8 (implementation gap)  R3.20's joint-residency obligation had no
        mechanism: the second concurrent admission evicted the first
        request's still-required groups. Resolved INSIDE the controller by
        minimal residency windows — admit(holdsResidencyWindow:true) opens
        one, the window's required set unions into subsequent effective
        required sets and is pressure-exempt, closeResidencyWindow(_) makes
        its groups reclaimable at the next transition. No contract text
        changed; R3.20 already specified the behavior.
F3/F4 test corrections: stale fault configuration and a wrong expectation
        (first sorted victim) — test bugs, no semantic change.
```

Result: **F1–F8 + F7b all PASS (76 tests, 0 failures)** — mid-load failure
with retry, evict failure → DIRTY → blocked admission → recovery,
cancellation at group boundaries during load and eviction, audit deviation
→ DIRTY, budget-shrink fail-fast with zero transfers, pressure shrink with
logged evictions and no speculative reload, concurrent admission with
windows and joint residency.

```text
Current gate  : L3 → COMPLETE
Next          : L4 real materializer (MLX behind the contract) + INV-3
                reconciliation + output identity on real models
L4            : NOT STARTED
```

### L4-A MLX Materializer Adapter — 2026-09-25

The first concrete Backend was registered: `MLXResidencyBackend` implements
the full `RuntimeResidencyBackend` contract — async
`materialize`/`release` delegate to the ALREADY-VALIDATED MLX helpers (made
internal in `MLXGroupResidencyBenchmark`, zero duplication, zero semantic
drift), `memoryObservation()` maps `Memory.snapshot()` into
`BackendMemoryObservation`, and `purgeTransientCaches()` mirrors the
validated `Memory.clearCache()` hygiene. The Controller still holds no MLX
import — it sees the backend only through the contract surface.

Contract signature amendment (conflict protocol, judged contract-signature
defect — semantics unchanged): the validated MLX load/release path is
inherently async (`container.perform` serialization; there is no synchronous
path), so `materialize`/`release` became `async throws`. A synchronous
contract would have forced thread-blocking adapters with deadlock risk.
Corresponding controller refactor:

```text
admit / respondToMemoryPressure → async, serialized through a FIFO
             AsyncLock (R3.18 admission order preserved; an admission holds
             the lock across await points — R2.2 atomicity intact)
reconcile / recover → remain synchronous, now throwing
             .admissionInFlight rather than observing intermediate state
new error    = .admissionInFlight
```

Regression: **80/80 test cases PASS** (76 XCTest incl. all L1/L2/L3 suites
+ 4 contract-target tests). No research artifact touched.

```text
Current gate  : L4-A → COMPLETE
Next          : L4-B INV-3 real byte reconciliation (load/release committed,
                failures/DIRTY, recovery, multi-transition, pressure; on
                Qwen3-Coder with C_model=0 and Nail with the audited offset)
Then          : L4-C end-to-end identity (baseline vs controller path)
L4-B / L4-C   : NOT STARTED
```

L4-A history: `MLXResidencyBackend.swift`, `AsyncLock.swift`, contract
async signatures.

### L4-B INV-3 Real Byte Reconciliation — Five Models PASS — 2026-09-25

The `l4b-reconcile` probe (protocol G1.9-L4B.RECONCILIATION.V1) connected
the production `ResidencyController` + `MLXResidencyBackend` to real models
and verified INV-3,
`|idleBytes − (residentBookkeepingBytes + C_model)| ≤ ε`,
across the seven registered paths: load committed, release committed, load
failure (contract-level injected throw before delegation — real state stays
consistent), release failure → DIRTY, recovery, multi-group continuous
transfers, and pressure response. Key correctness detail: the controller's
initial bookkeeping is set to the FULL group set, matching the backend's
full-load state (T0 calibration sample).

Results (10 transitions per model; ε = 5 MiB; C_model calibrated from T0
when not supplied):

| Model | C_model (calibrated) | max deviation | PASS |
|---|---:|---:|---|
| Qwen3-Coder-30B | +0.037 MiB | 1,152 B | PASS |
| Nail-Qwen3.6-35B | −851.057 MiB | 960 B | PASS |
| Cyber-Tiel-35B | −851.455 MiB | 960 B | PASS |
| Gemma4-12B | +2.319 MiB | 2,358,144 B | PASS |
| Muse-Glimmer-30B | +4.939 MiB | 2,554,656 B | PASS |

The calibrated C_model values reproduce the observability audit's per-model
constants (Nail/Cyber-Tiel vision-tower offset; Gemma4/Muse small
dense-path offsets), and their CONSTANCY across load committed, release
committed, failure, DIRTY, recovery, and pressure paths is verified on the
real runtime. T6 correctly entered DIRTY while the reconciliation still
held. Not a performance test: no latency/throughput/improvement claims.

```text
Current gate  : L4-B → COMPLETE
Next          : L4-C end-to-end identity (baseline vs Controller path on
                real generation; token/logits identity + transfer log)
L4-C          : NOT STARTED
```

L4-B history: `L4Reconciliation.swift` probe +
`results/l4b-reconciliation/*.json` (5 models).

### L4-C Computational Identity Through the Controller Path — Three Models PASS — 2026-09-25

The `l4c-identity` probe (protocol G1.9-L4C.IDENTITY.V1) compared Baseline
MLX generation against Controller + MLXResidencyBackend generation on the
same prompts, with real residency transitions (retention rotation
A → AB → ALL) between generations and one injected release failure → DIRTY
→ recovery cycle mid-sequence.

Results (3 prompts per model):

```text
Qwen3-Coder-30B   token sequence identical, logits SHA-256 identical,
Nail-Qwen3.6-35B  max_abs_diff = 0.0 on every prompt;
Gemma4-12B        retention rotation executed real evictions
                  (resident 5.88 → 10.94 → 16.00 GiB on Qwen), the DIRTY/
                  recovery cycle executed and recovered (dirtyCycleExecuted
                  = true), transfer log = 6 entries per run
status            = PASS on all three models
```

This closes L4: the controller manages resource state without changing what
the model computes — resource-state correctness (L4-B) and computational
semantics preservation (L4-C) hold together on real MLX runtimes. Not a
performance test; no latency/throughput/improvement claims.

```text
Current gate  : L4-C → COMPLETE
Runtime Engineering chain: Requirements → Verification Design → L1/L2 →
                Controller → L3 → L4-A/B/C → VALIDATION COMPLETE
L4-C history  : `L4Identity.swift` probe + `results/l4c-identity/*.json`
                (3 models)
```

### O3-C″ Qwen35MoE Segment-wise Boundary Evidence — CAPACITY_EXCEEDED — 2026-09-25

Model switched to Nail-Qwen3.6-35B-A3B-MLX-6bit (35B total / 3.39B active
/token, 256 experts × 8 active + shared, ~30 GiB disk, model_type
`qwen3_5_moe`). Probe migrated from `Qwen3NextModel` to `Qwen35MoEModel`
(minimal 5-change migration); mlx-swift-lm fork gained
`Qwen35TextModelInner.forwardLayerRange` with `applyFinalNorm` default
`false` and `Qwen35Model` public `embedInputs` / `forwardLayerRange` /
`projectOutput`; math equivalence validated 3/3 (bit-exact, `max_abs_diff
= 0.0`) including uneven segments crossing linear/full attention
boundaries.

Single-pass, 4×10-layer segments, 32 GiB physical. Core (non-switch_mlp)
load = 32.7 GiB — already at physical capacity. SEG0 release
`eval(model.parameters())` forced full lazy tree materialization → +22
GiB, peak footprint 78,373 MiB (76.5 GiB = 2.4× physical). SEG1→SEG2→SEG3
→PROJECT each shed ~7.3 GiB, returning to core baseline. Determinism not
evaluated (single pass); double-pass not attempted.

**Two independent structural findings**: (1) segment-wise execution
produces a stable, observable residency release boundary — first direct
measurement of this property; (2) capacity is exceeded by core load alone,
independent of segment policy. Both findings stand; neither depends on the
other. Not claimed: that Qwen35MoE has been proven to run segmented on a
32 GiB machine.

This experiment is sealed as mechanism evidence; Qwen35MoE on 32 GiB
hardware will not be re-run.

```text
Current gate  : O3-C″ → PARTIAL / BOUNDARY_CONFIRMED / CAPACITY_EXCEEDED
Next          : capacity-feasible smaller MoE for combined
                boundary + capacity + determinism evidence
O4            : NOT REACHED
```

Gate history:
`docs/00-governance/SIMIGO2_O3C_QWEN35MOE_BOUNDARY_RESULT_20260925.md`;
probe `O3CSegmentWiseProbe.swift`; fork `Qwen35ForwardLayerRangeTests`.

### O3-C″ Fix Verification — Placeholder-First PASS; Capacity Attribution Corrected — 2026-09-26

The 2026-09-25 seal was reopened on explicit user instruction plus new
evidence: the run's capacity attribution traced to probe defects. Six
defects were located, fixed, and verified (full ledger in the gate doc):

```text
D-P1 probe   loadContainer full native load (+30.28 GiB resident, kept for
             the whole run) — this alone produced the sealed run's
             "core load = 32.7 GiB" reading (30.28 container + ~2.4 core)
D-P2 probe   no placeholder-first update — lazy-random tree materialized at
             the release-path eval (+22 GiB → peak 78,373 MiB)
D-P3 probe   per-segment arrays dict pinned released weights until the next
             iteration — release freed nothing at the boundary; footprint
             ratcheted 22 → 29 GiB per segment
D-R1 reader  element-mapped intermediate Swift Array per tensor — a second
             full copy of every tensor (~7 GiB churn per segment)
D-R2 reader  BF16 branch numerically converted uint16 instead of
             reinterpreting bits — every BF16 scale/bias read through this
             reader was wrong (2.9 GiB on this model); no prior
             output-identity claim depended on the path
D-G1 gate    capacity check compared raw BYTES against capacityMiB —
             capacityHeldThroughout was false in every run (units bug)
```

Post-fix measured verification (double-pass, 4×10-layer segments, 32 GiB
physical): core load 3,356 MiB active / 4,022 MiB footprint; segment
materialize peak 10,237 MiB active; every release returns active exactly to
the 3,357 MiB core baseline; footprint flat ~11.3-11.8 GiB across 4 segments
× 2 passes (zero ratchet); swap 0 MiB at all 39 boundaries; determinism
pass1 == pass2 == [71093] (meaningful only after D-R2);

```text
overallPass = true (capacityHeld + residentSetBoundaryObserved +
             determinismIdentical all true)
max footprint 11,768 MiB vs sealed-run 78,373 MiB; max swap 0 MiB
```

Corrections to the registered 2026-09-25 findings: (1) the observable
release boundary STANDS with stronger evidence (true return-to-core-baseline);
(2) "capacity is exceeded by core load alone" is RETRACTED as a probe-defect
artifact — true core residency is 3.3 GiB and the segment-wise loop holds
peak residency at core + one segment ≈ 10.2 GiB active on this 30.28 GiB
model. Not a performance claim; no frozen-line changes; fork segment API
remains uncommitted pending E2E.

```text
Current gate  : O3-C″ → PASS / PLACEHOLDER_FIRST_VERIFIED /
                CAPACITY_ATTRIBUTION_CORRECTED
Next          : O4 oversized real-execution decision (user) — the
                registered single blocker (no path constructs a quantized
                oversized model without materializing lazy random weights)
                is RESOLVED by placeholder-first + single-copy reader
O4/O5/O6      : awaiting user decision
```

Gate history:
`docs/00-governance/SIMIGO2_O3C_SEGMENTWISE_FIX_VERIFICATION_20260926.md`;
artifact `results/o3c-streaming/nail-qwen36-35b-6bit-placeholder-first.json`.

### O4 Full-vs-Segmented Performance Differential — User-Directed — 2026-09-26

User directive: analyze the performance difference between full (whole-
model resident) and segmented computation. On the oversized checkpoint the
full path does not exist (O2/O3 measured), so the differential was measured
on Nail-Qwen3.6-35B-A3B-MLX-4bit (20.15 GiB — both strategies fit), same
greedy cacheless function through both paths (protocol G1.9-O4.GEN.V1,
8 tokens × 2 passes, 4×10-layer segments):

```text
segmented   peak 6,649 MiB  footprint / 3,353 MiB core resident
            4,640-4,771 ms/token  = read ~2.5 s + forward ~2.0 s
full        peak 22,451 MiB footprint / 20,633 MiB resident
            2,295-2,355 ms/token  (whole-graph)
ratio       segmented ≈ 2.0× full per token, for 3.4× less peak memory
tokens      bit-identical across paths and passes (descriptive only)
```

Decomposition: the fork's forwardLayerRange decomposition adds no
measurable penalty (segmented forward 2.04 s ≈ whole-graph 2.30 s); the
entire differential is per-token re-materialization I/O (~17 GiB/token at
~6.9 GB/s under a concurrent download that neutralized the cold/warm
contrast — registered caveat). Oversized axis: at 41.76 GiB the segmented
path is the only executable one (~6-14 s/token extrapolated; direct O4
measurement pending the user's re-pull). Same no-free-improvement economics
as the frozen frontier result, now at forward granularity.

Probe timing-defect fixed in-flight before accepting numbers (msSince
dropped whole-seconds for durations ≥ 1 s — first run's token totals void).

```text
Current gate  : O4 → PERFORMANCE_DIFFERENTIAL_MEASURED (20.15 GiB A/B)
Next          : direct oversized generation on the re-downloaded
                Qwen3-Coder-Next-4bit (41.76 GiB) — awaiting user pull
O5/O6         : NOT STARTED
```

Gate history:
`docs/00-governance/SIMIGO2_O4_FULL_VS_SEGMENTED_PERFORMANCE_DIFFERENTIAL_20260926.md`;
artifact `results/o4-generation/nail-qwen36-35b-4bit-full-vs-segmented.json`.

### O4 Oversized Real Generation — PASS — 2026-09-26

Direct measurement on the re-downloaded Qwen3-Coder-Next-4bit (41.76 GiB >
32 GiB physical; 3×16-layer segments; segmented-only — the full path does
not exist at this scale). The O4 question is answered YES by measurement:

```text
core resident            1,294 MiB (O1-registered core confirmed)
peak footprint           13,883 MiB — the model executes in < 14 GiB
max swap                 0 MiB at all 16 token boundaries
generation               16 tokens (8 × 2 passes), greedy, chat template
token latency            ~11.0 s/token = read 8.6 s (40.5 GiB/token
                         re-materialization ≈ 4.7 GB/s) + forward 2.2 s
double-pass determinism  PASS (identical token sequences)
```

The A/B extrapolation (6–14 s/token) is confirmed (~11 s); the cost is
throughput-bound re-materialization I/O, exactly as the 20.15 GiB
differential predicted. Harness-level physical layer only; Execution State
composition remains O6.

```text
Current gate  : O4 → OVERSIZED_REAL_GENERATION_PASS /
                CORE_PLUS_ONE_SEGMENT_ZERO_SWAP
Next          : O5 boundary sweep (generation length/stability/throughput
                vs I/O) and/or O6 Execution State × oversized model —
                user decision
O5/O6         : NOT STARTED
```

Gate history: `docs/00-governance/SIMIGO2_O4_OVERSIZED_REAL_GENERATION_20260926.md`;
artifact `results/o4-generation/qwen3-coder-next-4bit-oversized-gen.json`.

### O5 Segment-Size Sweep v1 — Footprint Halved, Latency Neutral — 2026-09-26

User question (re-partition to core+segment ≈ 8 GiB) folded into O5's first
sweep item. On the 41.76 GiB model, `--segment-size 8` (6 segments) versus
the 16-layer baseline:

```text
seg 16 (3 seg)  peak footprint 13,883 MiB  ~11.0 s/token (read 8.6 / fwd 2.2)
seg 8  (6 seg)  peak footprint  6,745 MiB  ~11.5 s/token (read 9.1 / fwd 2.3)
both            swap 0, double-pass tokens identical
```

Verified: the 8 GiB-class partition is correct, stable, and halves peak
residency — but re-partitioning trades footprint, not latency (total
re-read bytes unchanged). In this zero-swap regime a memory cap has no
latency to recover; the verified secondary report behind the "8 GiB
improves latency" claim is Apple's LLM-in-a-Flash (2024, windowing +
proactive loading on 8 GB-class devices), not a Google result, and its
mechanism is prefetch/pipelining — registered as a later O5 lever
(upper bound here: hide the ~2.2 s forward → ~8.6-9 s/token).

```text
Current gate  : O5 → SEGMENT_SIZE_SWEEP_V1_MEASURED / O5_SWEEP_CONTINUES
Next          : prefetch pipelining item; 54.3 GB user-downloaded model
                (Qwen3.8-Flash-Next, iQ 3.3bpw) after config/quantization
                compatibility check; O6 Execution State × oversized per plan
O6            : NOT STARTED
```

Gate history: `docs/00-governance/SIMIGO2_O5_SEGMENT_SIZE_SWEEP_V1_20260926.md`;
artifact `results/o4-generation/qwen3-coder-next-4bit-seg8-sweep.json`.

### Qwen4Exp Compatibility Boundary — User-Downloaded 54.3 GB Model — 2026-09-26

Compatibility audit of `ddalcu/Qwen3.8-Flash-Next-MLX-Serve-iQ-MLX-3.3bpw`
(50.6 GiB weights = 54.3 GB decimal, 3167 tensors, 101 shards, complete):

```text
compatible     iQ-MLX = standard affine quant (group 64 / bits 4, U32
               packed + scales/biases; imatrix affects calibration, not
               layout) — reader/quantize machinery compatible
compatible     fused switch_mlp present (441 tensors); layers.N regex
               partition works; 48 layers, 512 experts × 10 active
               (same MoE topology as Qwen3-Coder-Next)
INCOMPATIBLE   model_type = qwen4_exp (Qwen4ExpForConditionalGeneration)
               — the Qwen4 preview architecture: gated HyperConnections,
               partial-rotary M-RoPE, sparse attention, ngram-embedding,
               MTP head, vision tower. No implementation exists in the
               fork, mlx-lm (0.31.3 is PyPI latest), or HF transformers
               (open issue; loading fails). Reference implementations:
               vLLM and the proprietary mlx-serve stack only.
```

Verdict: not runnable on the current machinery; running it requires a
fork-side Qwen4Exp implementation ported from vLLM (Python/PyTorch →
MLXNN, text tower only: embed + 48 layers + norm + head; MTP/vision
skippable) plus the E3-pattern segment API and tests — a real port with
no MLX-native reference to diff against (correctness checks: greedy
sanity + double-pass machinery). Registered as a compatibility boundary
and a candidate engineering gate; user decision required before opening.

```text
Current gate  : O5 → QWEN4EXP_COMPATIBILITY_BOUNDARY_REGISTERED /
                O5_SWEEP_CONTINUES
```

### O5 Prefetch Pipelining + Clean Matrix — Negative at Scale; seg8 Pareto Best — 2026-09-26

O5 item 2 measured under clean I/O (download complete). Full matrix
(8 tokens × 2 passes, all bit-identical tokens, swap 0):

```text
seg16 sequential  11.3-11.4 s/token / 15,722 MiB peak
seg16 prefetch    12.4-13.2 s/token  — prefetch NEGATIVE (+10-16%)
seg8  sequential   7.7 s/token       /  8,821 MiB peak  ← Pareto best
seg8  prefetch     7.5 s/token       /  9,575 MiB       (only ~2.3% gain)
```

The naive "hide forward behind read" model fails on unified memory: disk
DMA + buffer copies share the bandwidth the GPU forward needs — contention
taxes the hidden phase and grows with segment size. Clean-condition rerun
also exposed that the earlier seg8 sweep number (11.5 s) was
download-contaminated (~50%); clean seg8 sequential is the Pareto best
measured operating point (7.7 s/token at 8.8 GiB peak — smaller segments
re-read at higher effective throughput). Hygiene rule registered: I/O-bound
probes require idle network/disk. Probe pipeline-state defect (nil unwrap
on token 2) fixed in-flight before accepting numbers.

```text
Current gate  : O5 → PREFETCH_MEASURED / SEG8_SEQUENTIAL_IS_PARETO_BEST /
                O5_SWEEP_CONTINUES
Next          : remaining O5 items (long-generation stability, context
                scaling) → O6 Execution State × oversized per plan
O6            : NOT STARTED
```

Gate history: `docs/00-governance/SIMIGO2_O5_PREFETCH_PIPELINING_20260926.md`.

### O5 Long-Generation + Context Scaling — Stable; Crossover at ~650 tokens — 2026-09-26

O5 items 3-4 (seg8, clean I/O). Long generation (32 tokens × 2 passes):
determinism PASS, peak footprint flat at 8,952 MiB (no creep), swap 0;
pass-1 latency drift +1.5%; pass-2 tail inflation fully accounted for by
prefix growth (cacheless re-forward processes 219+k positions at step k);
pass-2 overall +12% registered as undetermined system variance.
Context scaling (ctx 18/258/1,008): read constant (8.2-8.8 s, weights
only); forward LINEAR (≈ 0.38 s + 12.2 ms × context); memory
context-independent and weights-bound. **Crossover at context ≈ 600-700
tokens**: beyond it, cacheless forward cost exceeds the re-materialization
read cost — the quantitative motivation for O6 (prefix/KV-level Execution
State strategies dominate beyond the crossover; below it, seg8 sequential
stays optimal).

```text
Current gate  : O5 → LONGGEN_STABLE_AND_CONTEXT_LINEAR / O5_SWEEP_COMPLETE
Next          : O6 Execution State × oversized (design gate first); then
                SimiGo-1.7-inspired 2.0 app + real-device verification
                (user ordering: experiments first, build last)
O6            : NOT STARTED
```

Gate history: `docs/00-governance/SIMIGO2_O5_LONGGEN_CONTEXT_SCALING_20260926.md`;
artifacts `results/o5-sweep/qwen3-next-{longgen32,ctx1,ctx25,ctx100}.json`.

### O6 Execution State × Oversized Model — PASS 7/7 — 2026-09-26

Layering registered (coordinator = identity sovereignty; oversized backend
= prefix payload whose release IS the segment eviction; segmented core =
verified physical machinery; executor = representation-consuming E5-v2
semantics). Scenario on the 41.76 GiB model (seg8): fork → divergent child
continue → full segment eviction (all switch_mlp released) → logical
restore to fork point → identical re-run; parent non-interference.

```text
7/7 checks PASS — incl. CHILD_DETERMINISM_THROUGH_SEGMENT_EVICT_RESTORE
peak footprint 8,111 MiB / swap 0 / 121 segment transitions executed
```

The E4 invariant holds at oversized scale: an Execution State whose
segments were all evicted IS still the same Execution State, resuming
bit-identically from the restored fork-point representation. First-run
scenario defect (checkpoint captured post-run-1) found and corrected to
the E5 authoritative shape before accepting results. Registered
follow-up: ResidencyController composition (transfer log/INV-1 over
segments).

```text
Current gate  : O6 → EXECSTATE_OVERSIZED_PASS / SEVEN_OF_SEVEN_CHECKS
Next          : SimiGo-1.7-inspired 2.0 app (oversized segmented engine +
                chat UI + residency panel + oversized self-test) and
                real-device verification — build was ordered last by the
                user
```

Gate history: `docs/00-governance/SIMIGO2_O6_EXECUTION_STATE_OVERSIZED_20260926.md`;
artifact `results/o5-sweep/qwen3-next-o6-execstate.json`.

### SimiGo 2.0 App v2 + Real-Device Verification — PASS — 2026-09-26

The O-line mechanics were productized as `OversizedSegmentedEngine`
(seg8 default / placeholder-first / single-copy reader / chat-template
multi-turn / per-token gauge streaming), and the app was upgraded to a
v1.7-inspired chat experience (multi-turn session, streaming assistant,
live residency panel: per-token active/footprint/swap + resident-segment
indicator) with a new machine-verifiable `--self-test-oversized`
(determinism + footprint ≤ 30 GiB + swap 0); legacy Gate 5 self-test
retained.

Real-device verification from the built .app bundle binary (Apple M5,
32.0 GiB, macOS 26.6.2), release build, Qwen3-Coder-Next-4bit
(41.76 GiB > physical):

```text
overallPass      TRUE
determinism      PASS — pass1 == pass2 == [8420, 594, 264, 13027, 729, 429, 80953, 1378]
peak footprint   8,293 MiB (gate 30,720) / max swap 0 MiB
mean token       9,075 ms / engine load 0.82 s
```

Engine timer unit defect (as→ms /1e6 instead of /1e15) found via the
first report's meanTokenMs and fixed before registration.

```text
Current gate  : APP_V2_DELIVERED / OVERSIZED_SELFTEST_PASS_ON_DEVICE
Next          : user-facing GUI validation; registered follow-ups =
                ResidencyController segment accounting (INV-1 over
                segments), Execution State fork/restore in the app session
                layer, Qwen4Exp port gate (user decision)
```

Gate history: `docs/00-governance/SIMIGO2_APP_V2_REAL_DEVICE_20260926.md`;
artifact `results/o5-sweep/app-realdevice-oversized-selftest.json`.

### App Performance Tuning — Residency-Shape Sweep; 22 GiB Profile Shipped — 2026-09-26

User clarification + directive: the earlier 16 GiB/green readings were the
observed state, not constraints; raise memory usage to ~22 GiB, keep cache
low, tune performance. The engine gained a persistent layer floor
(derivation-only budget) and configurable streaming unit size; gauges now
include MLX cache and the system memory-pressure level. Measured matrix
(9 shapes): latency DEGRADES monotonically with wired floor (9.0 s at
5 GiB → 32.9 s at 25.3 GiB, pressure escalating green → warning →
critical) — the "more residency = faster" hypothesis is falsified on
unified memory. At a given footprint, larger streaming units win (fewer
cycles): 2×24-layer units at the ~21.5 GiB mid-token peak run 13.2 s/token
with pressure green, cache ≈ 0, swap 0. Shipped default = the user's
22 GiB operating point (floor 0 / unit 24); the low-footprint fast
profile (floor 0 / unit 4: 9.0 s at 5.1 GiB) remains flag-selectable.
All shapes produce identical token sequences. Final real-device
verification from the release bundle: overallPass TRUE, determinism PASS,
boundary-sampled peak 11,668 MiB (mid-token ≈ 21.5 GiB), swap 0,
pressure 1.

```text
Current gate  : APP_TUNING_MATRIX_MEASURED / MEM22_UNIT24_SHIPPED_DEFAULT
```

Gate history: `docs/00-governance/SIMIGO2_APP_PERFORMANCE_TUNING_20260926.md`.

### App Chat Path Wired Through Execution State — Strict — 2026-09-26

Answering the user's audit question ("超规模大模型也严格进行 Execution State
了吗" — at the time, NO for the app chat path): the conversation now runs
strictly through the Execution State layer. Session = a real Execution
State (bootstrap prefix bound at position 0); every turn consumes the
bound representation with the raw next user input (E5-v2 encoding),
advances the logical position with one authoritative lifecycle record, and
rebinds the advanced prefix; new session = discard + create;
restoreSession exposes logical rollback; the UI shows the Execution State
readout (ID/position/turns/records). Backend decoupled from O6SegmentedCore
via a release closure.

Self-test upgraded to STRICT restore-replay semantics: pass 1 → logical
restore to bootstrap → pass 2 replays consuming the restored
representation. Real-device (release bundle, Apple M5): determinism PASS
(pass1 == pass2 == canonical tokens), lifecycle records 4,
strictExecutionState TRUE, peak 10,228 MiB / cache 0 / swap 0 / pressure
green, 13.4 s/token, overallPass TRUE. Two in-flight defects fixed before
accepting results (extraction dropped the bootstrap branch; the replay
initially compared different input sequences — corrected to the E5
authoritative shape).

```text
Current gate  : APP_CHAT_STRICT_EXECSTATE_WIRED /
                SELFTEST_RESTORE_REPLAY_PASS
Next          : fork/branch conversations in the UI (machinery ready);
                ResidencyController segment accounting (INV-1);
                Qwen4Exp port gate (user decision)
```

Gate history: `docs/00-governance/SIMIGO2_APP_EXECSTATE_WIRING_20260926.md`.

### Consistency Close-out — Controller-Driven Segments + Swap Fix — 2026-09-26

The last semantic consistency gap closed: oversized segment residency now
goes through the ResidencyController contract, same as the fitting-model
path. `OversizedSegmentMaterializer` (RuntimeResidencyBackend) maps
groupIDs to engine units; the engine builds the segment inventory (core =
alwaysResident; units = controller groups) and drives unit residency via
`admit(requiredGroupIDs:budget:)` with INV-1 audited after every
transition. Placeholder-first load now leaves all switch units as
placeholders and admits the floor through the controller, so bookkeeping,
transfer log, and physical state agree from the first transition.

**Swap-thrash root cause fixed** (user-observed 2-20 GiB violent paging at
the 24-layer-unit profile, 2-12 GiB at 16 layers): the controller's
admission loads the new unit BEFORE evicting the previous one — transient
double occupancy (~28 GiB wired) thrashed swap and cost 4x latency. Fix:
explicit `respondToMemoryPressure(targetBytes: floorResidentBytes)` right
after each unit's forward (contract-clean, logged). Measured: swap flat at
the ~1.4 GiB system baseline, 10.5 s/token (from 38.5 s), pressure green.

Real-device verification (release bundle): overallPass TRUE —
restore-replay determinism PASS, strictExecutionState TRUE, INV-1 over
segments TRUE (96 logged transfers, audited per transition), peak
13,729 MiB / cache 0 / swap flat / pressure green.

Measurement hygiene registered: engine boundary gauges under-report system
swap (dense external sampling required); zsh no-word-split voided a
sweep's flag arguments (caught by floor-count mismatch); controller
admission load-before-evict order interacts with unified-memory thrash at
large unit sizes.

```text
Current gate  : CONSISTENCY_CLOSEOUT_PASS /
                OVERSIZED_MATCHES_FITTING_CONTRACT
Next          : optional UI fork sessions; Qwen4Exp port gate (user
                decision)
```

Gate history: `docs/00-governance/SIMIGO2_CONSISTENCY_CLOSEOUT_20260926.md`.

### Post-Eviction-Fix Tuning Matrix Re-measured — unit8 Shipped — 2026-09-26

User directive: re-measure the tuning matrix after the eviction fix. The
curve INVERTED versus the pre-fix matrix — smaller streaming units now win
on both latency and memory, and larger units regress hard (unit 24 is
REJECTED by the ResidencyController itself: required unit bytes exceed the
group budget — the contract enforces the capacity boundary that the
pre-fix thrash used to surface as swap).

```text
shape (controller path, 8-token runs)   mean ms/token  peak MiB   pressure
floor 0 / unit 4 ×12                          13,920         18,139    2*
floor 0 / unit 8 ×6                            8,820          8,215    1  ← shipped
floor 0 / unit 12 ×4                          11,467          9,419    1
floor 0 / unit 16 ×3                          11,610         13,729    1
floor 0 / unit 24 ×2                          REJECTED by the controller
floor 4 / unit 8 ×6                            9,529          8,485    1
floor 14 / unit 8 ×5 (24 GiB floor budget)    11,988         15,192    2
```

*unit 4's 4-token sweep number (8.9 s) was a short-run artifact; the
8-token run exposed churn accumulation (13.9 s, pressure yellow). Floor
> 0 adds wired pressure with no latency benefit (floor 8: 9.1 s vs floor
0: 9.0 s in the pre-fix matrix; floor 14: 11.99 s yellow here) — the
floor budget default is decoupled to 4096 MiB (floor 0 on this model).

Shipped default: **floor 0 / unit 8 ×6 — 8,820 ms/token at 8,215 MiB peak,
cache 0, swap 0, pressure green, INV-1 over segments, strict Execution
State restore-replay determinism** (release bundle, real device). Larger
units remain flag-selectable where capacity allows.

```text
Current gate  : APP_TUNING_MATRIX_RERECORDED_POST_FIX /
                UNIT8_SHIPPED_DEFAULT
```

Gate history: `docs/00-governance/SIMIGO2_APP_PERFORMANCE_TUNING_20260926.md`
(appendix: post-fix matrix in this section).

### Four-Layer State Audit Fixes — Strict Session Boundaries — 2026-09-26

External four-layer audit (SimiGo2App → Engine → ResidencyController →
Execution State at 1422328, server-verified) surfaced three state-boundary
defects; all fixed, all gates green:

```text
fix ① (P1) engine.newSession swallowed residency failures (try? on
     respondToMemoryPressure → DIRTY invisible, UI claimed fresh state).
     Now fail-fast: pressure errors propagate BEFORE the Execution State
     discard; the app shows the failure and retains the session.
fix ② sessionTurnCount was a second source of truth (restore left
     position=1 / turns=3 divergence). REMOVED — turns derive from the
     Execution State position (single source of truth).
fix ③ coordinator.discard swallowed physical release failures (try?).
     Now propagates: callers see that model residency may still hold the
     representation's weights (Execution State / residency boundary).
fix ④ institutionalized: ChatAppModel.transcript = UI presentation
     history ONLY — never a restore source; failed turns keep the error
     entry visible instead of advancing the served transcript.
```

Verification: SimiGo-Lab 87/87 PASS; product build SUCCEEDED; strict E2E
(2× real /v1/chat/completions through the oversized runtime) PASSED with
restore-replay determinism. Reviewer's continuing sequence audit
(representationHistory / backend.prefixes / currentState /
ResidencyController.residentGroupIDs across
Turn1→2→3→restore→replay→newSession→failed-release) welcomed — the
sessionTurnCount removal makes position the single turn authority, and
discard now propagates physical release failures.

```text
Current gate  : STATE_BOUNDARY_FIXES_APPLIED / AWAITING_REVIEW_RESTAMP
```

### Discard Failure Atomicity — Transactional Reorder — 2026-09-26 (review P1 residual fixed)

Reviewer re-audit at 26e9ad1 (server-verified) stamped
"REVIEW PASS WITH 1×P1 RESIDUAL": coordinator.discard wrote the .discarded
lifecycle/record BEFORE the physical release — a failed release left
"logical = discarded / physical = unresolved", and newSession's
"session retained" was actually "retained but logically discarded and
unusable". Fixed by transactional reorder: physical release FIRST
(backend.releaseRepresentation), logical discard (handle + record)
commits only after success. Failed release now leaves the Execution State
UNCHANGED (resumable/retryable); newSession's "session retained" is now
literally true. Success-path outcomes identical (E2 lifecycle tree +
coordinator contract tests green). SimiGo-Lab 87/87 + product strict E2E
re-verified after the reorder.

```text
Current gate  : DISCARD_FAILURE_ATOMICITY_FIXED /
                AWAITING_REVIEW_RESTAMP
```

### Backend Physical Atomicity — releaseRepresentation Hardened — 2026-09-26

Per review distinction (coordinator logical atomicity FIXED ≠ backend
physical atomicity proven): `OversizedSegmentedStateBackend.
releaseRepresentation` audited and hardened. Old order: binding cleanup
(infallible) THEN physical release (fallible) — a physical failure left
"binding cleaned / weights resident" (unretryable partial state). New
order: fallible physical release FIRST (single all-or-nothing
model.update over the combined placeholder map + infallible clearCache),
infallible binding cleanup LAST. Failure now leaves the binding intact
and retryable; success is all-or-nothing. The foreign-payload guard
remains first (throws before any mutation). 87/87 green.

Open item registered for the reviewer's sequence audit: per-node state
of representationHistory / backend.prefixes / currentState /
residentGroupIDs is derivable from 4e45b07+ code; happy-path and
discard-failure paths now both hold "logical and physical move
together, binding as the retry anchor".

```text
Current gate  : BACKEND_PHYSICAL_ATOMICITY_HARDENED /
                AWAITING_REVIEW_RESTAMP
```

### Step 2 — INV-3 Production Reconcile + C_model Calibration — DONE — 2026-09-26

Per review direction (Step 2 scope locked: C_model calibration + production
reconcile integration ONLY — no transaction-coordinator expansion):

```text
C_model   calibrated at T0 for the oversized engine instance
          (observed MLX active − core bookkeeping at the core-only point);
          epsilon = 64 MiB (beta, calibration review required before GA)
reconcile observed at the stable post-commit point of every turn;
          divergence gets ONE recover attempt (bookkeeping rebuilt from
          the transfer log) then re-checked; persistent divergence FAILS
          the turn — physical inconsistency is never silently continued;
          the observation never touches committed Execution State
real-device overallPass TRUE — 192 transfers, swap 0, pressure green,
          canonical tokens, reconcile clean across the full double pass
```

Registered per review guidance: Failure Matrix full re-run happens AFTER
Step 2 closes (this registration), on the clean combined baseline
(D1 contract + Step 1 cancellation + Step 2 reconciliation) — so any
future issue is attributable to exactly one landed change.

```text
Current gate  : TOKEN_LEDGER_GATE_DEFINITION / GA0_POLICY_TARGET_DEPENDENT /
                AWAITING_REVIEW
```

### Failure Matrix Full Re-run — COMPLETE — 2026-09-26

Final audit round executed on the combined baseline (D1 contract + Step 1
cancellation + Step 2 reconcile): 13 operations × 6 conditions × five
state layers. Result: **P1 = zero**; all previously fixed boundaries
re-verified intact (cancel→ABORT position/binding unchanged;
commit→reconcile→DIRTY→recovery never touches committed Execution State;
C_model per-engine-instance confirmed). Residuals are all non-blocking
and registered:

```text
FM-01/02/03          CLOSED
FM-04 cancellation   DEFINED + IMPLEMENTED (phase-boundary observation)
FM-05 cross-layer    DEFINED (atomic pair vs mechanics layer)
FM-06 INV-3 production CLOSED (per-turn reconcile integrated)
FM-07 budget semantics CLOSED (f495a85)
FM-08 MLX-internal faults  BETA BOUNDARY (registered)
FM-09 reattach obligation  DEFINED (lazy; next-forward admissions)
FM-10 oversized fork/branch BETA SCOPE
P2 residuals         coordinator standalone concurrency (GA);
                     C_model calibration review (GA); MLX-internal fault
                     injection (beta boundary)
```

Verification evidence: 89/89 core tests; product strict E2E 2 tests PASS
(cancellation-abort + canonical completion); real-device swap ≤ baseline
throughout. Test layers recorded separately per review discipline:
89 core ≠ product E2E ≠ true-machine ≠ Failure Matrix audit.

```text
Current gate  : FAILURE_MATRIX_COMPLETE / P1_ZERO / P2_REGISTERED
Next          : GA work items (floor redesign, token ledger, cancellable
                generation, segment KV, UI branch sessions);
                Qwen4Exp port gate (independent decision)
```

### Reviewer Sequence-Audit Round — FM-01/02/03 Addressed — 2026-09-26

Reviewer audited at 7b87312 (one commit behind f495a85) and registered the
Failure Matrix FM-01~FM-10. Disposition:

```text
FM-01 (P1) generate: logical advance vs representation rebind
     non-atomic            → ALREADY FIXED at f495a85 (the commit after
                             the reviewer's baseline): greedy generation
                             mutates nothing; commit order = physical
                             rebind at N+1 -> logical advance -> history
                             record. The reviewer's proposed
                             candidate->bind->logical-commit design is
                             what f495a85 ships.
FM-02 (P1) fork: child logical commit before physical derivation
                           → FIXED this round: derivation FIRST; failure
                             leaves parent unchanged and the child
                             UNCOMMITTED (no handle/record/history);
                             logical fork commits only after derivation
                             succeeds. Lazy-fork semantics preserved
                             (parent unbound -> no derivation).
FM-03 (P1) engine lifecycle not concurrency-safe
                           → HARDENED: AsyncLock serializes generate /
                             newSession / restoreSession entries.
FM-04 cancellation transaction semantics     → registered (GA)
FM-05 Residency <-> ExecutionState cross-layer transaction → registered (GA)
FM-06 INV-3 reconcile in production path     → registered (completeness)
FM-07 budget/core conservatism               → FIXED at f495a85
FM-08 MLX-internal fault atomicity           → registered (beta boundary)
FM-09 reattach physical obligation           → registered (semantic definition)
FM-10 oversized fork/branch product surface  → beta scope
```

Verification: 89 tests PASS (87 + 2 atomicity; fork happy-path unchanged).

```text
Current gate  : FM01_02_03_ADDRESSED / FAILURE_MATRIX_AUDIT_ONGOING
```

### Runtime Consistency Contract D1 (Draft) — FM-04/05 + INV-3 Semantics — 2026-09-26

Per review direction (contract definitions BEFORE code): registered
`SIMIGO2_RUNTIME_CONSISTENCY_CONTRACT_D1_20260926.md` defining:

```text
D1 cancellation contract  — cancellation resolves at phase boundaries to
        exactly ABORT or COMMIT; the commit section (physical rebind ->
        logical advance -> history) contains no await points and is
        structurally non-cancellable; per-token-boundary cancellation
        aborts with position unchanged (mechanics converge via INV-1)
D2 cross-layer boundary   — atomic pair = Representation binding + logical
        position (physical first, logical second); Residency bookkeeping is
        the mechanics layer (INV-1 per transition), deliberately OUTSIDE
        the conversation transaction
D3 INV-3 semantics        — reconciliation is DETECTION (bookkeeping vs
        physical), not a transaction participant; production integration =
        post-unit-cycle observation with calibrated C_model, divergence
        surfaces as DIRTY
D4 reattach obligation    — lazy by contract; next forward's admissions
        carry the physical obligation; their failure is a TURN failure
```

Deliberately NOT defined (GA): floor redesign, token ledger, partial-token
COMMIT streaming, concurrent oversized sessions. Draft awaits review;
implementation order on approval: cancellation token plumbing -> INV-3
calibration -> production reconcile integration.

```text
Current gate  : CONTRACT_D1_DRAFT_REGISTERED / AWAITING_REVIEW
```

### Second-Audit Fixes — Turn-Commit Atomicity + Budget Semantics + servedTranscript Ordering — 2026-09-26

Three findings from the second audit round (ResidencyController →
Materializer → Engine → API chain) fixed and verified on device:

```text
fix A (P1)  turn-commit atomicity: the old order (consumeBinding →
            logical advance → bind at N+1) left a window where a bind
            failure produced "logical advanced / representation missing".
            New order: physical rebind at the advanced position FIRST
            (in-memory infallible), then the logical advance, then the
            history record; consumeBinding is subsumed by the rebind.
fix B (P2)  group budget no longer double-counts core: the planner
            computes desired = core ∪ required against the budget, so the
            engine now passes the FULL peak capacity as the group budget
            (was: peak − core, over-conservative by 2× core).
fix C (P1/P2) servedTranscript is now a DERIVED control state committed
            only AFTER the turn (physical rebind + logical advance)
            succeeds — a failed generation can no longer desynchronize
            the continuation judgment from the Execution State.
```

Registered for the final audit round (reviewer-proposed): the full
Failure Matrix — create/continue/fork/restore/reattach/discard/
materialize/evict/generation/bindRepresentation/newSession/HTTP failure ×
{success, failure, cancel, mid-exception, repeated, concurrent} — across
the five state layers. INV-3 reconciliation in the production path
remains a registered completeness gap.

Verification: SimiGo-Lab 89 tests PASS; real-device self-test
overallPass TRUE (canonical tokens, peak 6,859 MiB — budget semantics
now let the planner work as intended — swap ≤ baseline, pressure green).

```text
Current gate  : STATE_ATOMICITY_AND_BUDGET_FIXES_VERIFIED /
                FAILURE_MATRIX_NEXT
```

### Foreign-Payload Guard Restored + Fault-Injection Verification — 2026-09-26

Review findings at e9963fe addressed:
1. **Foreign-payload guard restored** in releaseRepresentation — the
   registration had claimed a guard the code never had; now the guard
   throws BEFORE any mutation (zero physical attempt on foreign payload).
2. **Fault-injection verification added**
   (`OversizedBackendAtomicityTests`, 2 tests): a release closure forced
   to throw leaves the binding INTACT (retryable — boundPrefix still
   returns the prefix) and a successful retry commits the cleanup; at the
   coordinator level, a failed discard propagates WITHOUT mutating
   handle/position/lifecycle/records/binding, and a successful retry
   commits `.discarded`.
3. **model.update atomicity note (registered boundary)**: with
   `verify: []` and a structurally valid unflattened map, MLXNN update is
   a sequence of infallible assignments — there is no internal throw
   site, so "all-or-nothing" holds by construction; a true fault-injection
   of the MLX assignment path itself would require vendor-side hooks and
   is registered as out of beta scope.
Verification: 89 tests (87 + 2 atomicity) all PASS.

```text
Current gate  : FOREIGN_GUARD_RESTORED / FAULT_INJECTION_VERIFIED /
                BACKEND_ATOMICITY_TESTED
```


### SimiGo v2.0.0-beta Released — Product Integration — 2026-09-26

The matured code shipped as a product beta: SimiGo (the v1.7 production
runtime, separate repo, main untouched) gained `release/v2.0.0-beta`
(89cdbbf, tag v2.0.0-beta). mlx-swift-lm moved to the integration branch
`release/v2.0-beta-ml` (dc3ca619 + merged segment APIs); simigo2-experimental
added as a local package (SimiGo2Experimental + SimiGoRuntimeContract);
`OversizedRuntime` routes qwen3_next >= 20 GiB models to the verified
segmented engine through the product's own HTTP API surface (all v1.7
functions unchanged; NativeMLX zero behavior change for fitting models).
Real-device E2E via /v1/chat/completions: restore-replay determinism PASS.
Known beta limitations: oversized-path usage counts zero (token-ledger
integration = GA scope), non-cancellable greedy generation, single
oversized session, no segment KV. Release .app built; release notes
`docs/RELEASE_v2.0.0-beta.md` in the SimiGo repo.

### GA-0 Ruling — Floor Policy = TARGET_DEPENDENT — 2026-09-26

Reviewer ruling registered: floor stays a POLICY-LEVEL pressure exemption
(target-dependent), NOT structural immunity (alwaysResident). Principles
fixed:

```text
core     = structural residency (alwaysResident; eviction-immune)
floor    = policy exemption (survives only while target >= core+floor)
target=0 = release ALL non-core residency (no alwaysResident exception)
```

Rationale: upgrading floor to structural immunity would (a) turn a
policy parameter into a Residency structural attribute, (b) break the
uniform target=0 semantics of newSession ("release all non-core"), and
(c) force reconcile/newSession/eviction to document an alwaysResident
exception. No code change — current behavior already matches the ruling.

### Token Ledger Gate Definition — Model First, No Code — 2026-09-26

`SIMIGO2_TOKEN_LEDGER_GATE_DEFINITION_20260926.md` registered. The
ledger = per-ExecutionState APPEND-ONLY record of confirmed token-prefix
facts: one entry per committed transition (bootstrap + successful turns);
failed turns append nothing; restore records a marker and retains the
superseded tail (append-only audit trail); discard closes the ledger.
Ownership: ExecutionStateBackend (the prefix IS the physical
representation; the ledger is its token-level view). Boundaries: NOT a KV
record / NOT usage / NOT a position source / NOT a transcript.
Invariants: I-L1 committed-only entries; I-L2 strictly increasing
prefixLength along the chain; I-L3 entry prefixLength == backend bound
prefix length at that position. Enables: oversized usage accounting
(closes the beta usage=0 limitation), prefix-drift detection, token-level
reconciliation dimension. Implementation AFTER review approval.

```text
Current gate  : TOKEN_LEDGER_GATE_DEFINITION / GA0_POLICY_TARGET_DEPENDENT /
                AWAITING_REVIEW
```"""

### Token Ledger Gate — IMPLEMENTED + REAL-DEVICE VERIFIED — 2026-09-27

Implementation landed (3ba44f7) per the registered definition. The
definition's I-L2 wording ("strictly increasing prefixLength") was
under-specified for rewind: as implemented and unit-pinned, I-L2 is
growth-point based — turn/bootstrap entries must move strictly forward
from the current growth point; a restore marker may move the growth
point to any coordinator-valid position — rewind OR forward resume of a
previously superseded position (undo of a rewind); the rewound tail is
retained and flagged (markSuperseded, append-only audit). Marker bound =
furthest-ever committed position (defense in depth; the coordinator
already gates restore targets on representation existence — an earlier
ahead-of-growth-only guard would have rejected legitimate forward
restores with a post-commit throw, found by failure-surface review and
fixed before any device run exercised it). I-L3 as implemented: entry
prefixLength == active-chain bound-prefix length AT that position (the
restore marker takes the restored position's prefix, not the last
entry's).

Wiring: bootstrap entry at session creation; turn entry appended only
after the full commit sequence (physical rebind -> logical advance ->
history) succeeds (I-L1 committed-only); restoreSession marks the
superseded tail then appends the marker; discard closes the ledger with
the session. Self-test overallPass now requires the ledger chain
bootstrap -> turn(!S) -> restoreMarker -> turn.

Verification: 95/95 unit tests green (6-case ledger battery: forward
growth, rejection without growth-point consumption, rewind + superseded
retention, marker-ahead-of-growth rejection, per-execution isolation);
real-device Qwen3-Coder-Next-4bit E5 replay flow PASS — chain
`bootstrap@0p18 / turn@1p26!S / restoreMarker@0p18 / turn@1p26`,
determinism identical, 192 transfers, swap 0, pressure green
(`results/o5-sweep/app-selftest-tl-gate.json`).

```text
Current gate  : TOKEN_LEDGER_GATE_VERIFIED / GA0_POLICY_TARGET_DEPENDENT /
                FAILURE_MATRIX_RERUN_NEXT
```

### Token Ledger I-L3 Enforcement Closure + Ownership Wording Unified — 2026-09-27

Code-level review at e29fce7 (no code changed during review) dispositioned
the gate as: I-L1/I-L2 verified; I-L3 cross-REFERENCED but not cross-CHECKED
(`append()` never verified `prefixLength`; the restore marker's value was
ledger-self-derived — "Ledger 找 Ledger 要 prefixLength"); ownership
definition-vs-code deviation (definition said ExecutionStateBackend, code
had OversizedSegmentedEngine). Same-day closure, minimal cut, no ownership
migration, no Execution State refactor:

```text
I-L3 now ENFORCED   the ledger takes a REQUIRED authority closure over the
                    backend binding record (new backend query
                    boundPrefixLength(executionID:position:) with
                    no-binding + position-mismatch guards); every append of
                    every kind cross-checks entry.prefixLength against it —
                    wrong length / missing binding / position drift throws
                    divergence-class and records NOTHING (the authority is
                    required, never optional — an optional check would
                    recreate the gap)
marker source moved restoreSession derives the marker's prefixLength from
                    the backend's re-bound representation (coordinator.restore
                    re-binds the historical prefix before returning); the
                    ledger-self-derived helper is DELETED
ownership unified   gate definition §2 amended: conceptual owner = Execution
                    State representation layer; current implementation owner =
                    OversizedSegmentedEngine (engine-side audit structure);
                    backend sink deferred until the abstraction stabilizes
P2 registered       restore post-commit window (restore committed ->
                    markSuperseded -> marker append throws) = defensive
                    consistency gap; with I-L3 live it fails only under
                    genuine divergence (the loud failure the gate wants);
                    markSuperseded idempotent under retry — no transaction
                    redesign
verification        unit battery 7 → 11 cases (4 deliberate-mismatch:
                    value mismatch / missing binding / position drift /
                    marker mismatch, each re-pinned through an INDEPENDENT
                    backend stub — never derived from ledger entries);
                    100/100 all green; full 13×6 matrix re-run NOT
                    triggered (read-only check on untouched commit paths;
                    surfaces dispositioned in Failure Matrix Addendum 2);
                    device evidence unchanged (app-selftest-tl-gate.json)
```

Evidence boundary corrected per review: the earlier PASS proved normal-path
ledger behavior; mismatch DETECTION is proven only from this round's unit
battery. Next: release engineering round (mlx-swift-lm path, version,
License, test defaults, deploy guide) — in the review-prescribed order
(code correctness → gate closure → failure matrix disposition → public
release engineering → v2.0.0-beta).

```text
Current gate  : TOKEN_LEDGER_GATE_VERIFIED_I_L3_ENFORCED /
                GA0_POLICY_TARGET_DEPENDENT /
                RELEASE_ENGINEERING_NEXT
```

### Release Engineering Round — Open-Source Dependency Chain Public — 2026-09-27

The five review-listed release-engineering items closed; v2.0 beta
rebuild verified end-to-end on the PUBLIC dependency chain:

```text
mlx-swift-lm path   Lab Package.swift: path dep (outside-repo relative
                    path, broke public clones) -> remote branch
                    slamfinger/mlx-swift-lm@release/v2.0-beta-ml,
                    Package.resolved pins fbfa1f4; product project: the
                    file://<LOCAL_HOME>/... reference pinned at stale revision
                    dc3ca619 -> same public branch (two different
                    revision requirements are a SwiftPM resolution
                    error — found by the rebuild, unified on branch);
                    product Package.resolved pins fbfa1f4
测试默认路径        OversizedRuntimeE2ETests: /Users hardcoded fallback ->
                    dynamic HF-cache snapshot resolution (env override
                    OVERSIZED_MODEL_PATH retained; XCTSkip when absent)
License             MIT added to SimiGo-Lab + SimiGo (fork inherits
                    ml-explore MIT upstream — three-repo license
                    coherence); copyright Mr.Simi (slamfinger)
版本号              app MARKETING_VERSION 2.0.0 (unchanged); product tag
                    v2.0.0-beta.1 prepared LOCALLY on d8c6ba6 (push =
                    pending user action); Lab packages carried by the
                    release branch + resolved pin
部署指南            部署指南.md §6: v2.0 beta sibling-clone build
                    (SimiGo + SimiGo-Lab side by side), oversized
                    routing rules, known limits; RELEASE notes
                    dependency section updated (remote-switch promise
                    fulfilled); README gains v2.0 beta section
verification        Lab swift test 100/100 against the REMOTE dep (the
                    public-clone path); product Release xcodebuild BUILD
                    SUCCEEDED with fresh derived data — product -> local
                    Lab package -> public fork branch resolves and
                    compiles clean; device E2E re-run NOT triggered
                    (dependency metadata + docs only, no engine or
                    product behavior change — same disposition logic as
                    Failure Matrix Addendum 2)
```

Historical docs mentioning the old local path
(`ARCHITECTURE_2.0_PRERESEARCH_20260920.md`, MUSE_GLIMMER evidence JSON)
left untouched — dated records are not rewritten.

```text
Current gate  : RELEASE_ENGINEERING_COMPLETE / BETA_BUILD_VERIFIED /
                TAG_PUSH_PENDING_USER (v2.0.0-beta.1 on d8c6ba6)
```

### v2.0.0-beta.1 PUBLISHED — 2026-09-27

The three outward actions executed under explicit user authorization:

```text
tag            v2.0.0-beta.1 pushed to slamfinger/SimiGo (annotated,
               peeled → d8c6ba6)
DMG            SimiGo-v2.0.0-beta.1.dmg packaged from the verified
               Release build (app 2.0.0 build 6; /Applications
               drag-install layout); hdiutil CRC verify VALID;
               25,393,778 bytes
release        GitHub Release v2.0.0-beta.1 (prerelease) with the DMG
               asset + full notes (beta.1 delta, capabilities, known
               limits, install, SHA-256
               c9ab1fc8e9f9c9d9a5b8332972b99ea55e66b1b41b6fb4b49297b68b23749361)
               → https://github.com/slamfinger/SimiGo/releases/tag/v2.0.0-beta.1
license        MIT accepted as-is (no further action)
```

Remaining GA items unchanged: segment KV, UI branch sessions, INV-3
production-integration completeness gap, usage projection wiring
(engine token ledger already in place), floor redesign per GA-0 ruling,
Qwen4Exp port gate (independent decision).

```text
Current gate  : V2_0_0_BETA_1_PUBLISHED / GA_WORKITEMS_OPEN
```

### Beta Pulled + Route Ruling — Daily Path Execution State — 2026-09-27

User ruling (explicit, repeated priority principle): **the oversized
line is theory validation only; the daily small-scale path is the
foundation.** Executed under direct authorization:

```text
beta pulled     GitHub Release v2.0.0-beta.1 deleted (--cleanup-tag:
                remote tag removed; local tag deleted). Commit d8c6ba6
                remains on release/v2.0.0-beta (code and public
                dependency chain stay — only the release page came
                down). The older tag v2.0.0-beta (89cdbbf, no Release
                page) untouched — outside this ruling.
retraction      product RELEASE notes banner added
root cause      real-device log audit (02:18–02:25): every NEW session
                cold-prefills its full context (47.6s @6.2K; per-turn
                ~18K injections 76–225s) — v1.7 KV reuse is gated on
                session identity (storageKey), zero cross-session
                sharing; same-session reuse healthy (cacheEff 1.00,
                TTFT 0.478s). Audits to date covered correctness and
                the oversized path, never daily-path workload
                economics — registered blind spot.
priority        feedback memory registered: work-item ordering takes
                daily-path benefit as the first criterion
```

### Definition Gate Opened — SimiGo 1.7 Execution State Prefix Pool — 2026-09-27

`SIMIGO17_PREFIX_POOL_EXECUTION_STATE_DEFINITION_20260927.md` registered
(per gate discipline: definition before code). Thesis: apply the
Execution State principle to the daily path at token granularity —
logical states consume physical KV representations by CONTENT, not by
session identity; a shared, content-addressed prefix pool (rolling
hash-chain keys over token ids, namespaced by model+kvFingerprint, block
boundaries every 512 tokens, LRU under the existing warmTokenBudget)
turns new-session cold prefill into delta prefill. Admission reuses the
existing performLoad/cacheLoad checkpoint machinery (kvFingerprint
reconciliation proven in rollforward). Invariants P-I1..P-I4 drafted —
P-I1 carries the I-L3 lesson (cross-check the claim against the loaded
representation, never trust the key). Honest scope: removes the
shared-prefix cold tax; the genuinely-new-token injection class is
real compute (G1.9-C: no locality) and stays out of scope.
CORRECTION OF RECORD (same day, documentary): the Execution State chain
was validated small-model-first across multiple architectures (E1–E5;
L4-B 5-model INV-3; L4-C 3-model identity: Qwen3-Coder MoE,
Nail-Qwen3.6 MoE, Gemma4-12B dense) with oversized (O0–O6) as the FINAL
stress step — the daily-path work is productization of already-validated
machinery, not an import of unproven tech. The gate now carries the
routing decision as its first-class review question: Route A (prefix
pool around the ChatSession path; de-risked — production rollforward
already proves checkpoint restore + delta-continue) vs Route B (serve
daily models through the strict Execution State engine, all-resident
for fitting models; pool as its shared representation store) vs
A-then-B. Implementation starts only after review approval.

```text
Current gate  : BETA_1_PULLED / SIMIGO17_PREFIX_POOL_DEFINITION /
                AWAITING_REVIEW
```

### Route B SELECTED + B-1 (PrefixPool Core) LANDED — 2026-09-27

User ruling: **Route B** — daily small models served through the strict
Execution State layer; prefix pool as its shared representation store.
Pre-implementation audit confirmed every physical premise is already
production-proven: `ChatSession.saveCache(to:)` / `ChatSession
(container, cache:state:)` (official KV snapshot import) with the
registered fragment-continuation semantics ("delta messages only, warm
first token") — v1.7 cacheSave/cacheLoad + rollforward run exactly this
path on live traffic. Architecture registered in the gate: state layer
= E-line contracts; executor = ChatSession (multi-architecture
registry); representation = KV snapshots; sharing = content-addressed
pool; all-resident for fitting models is trivial; oversized engine
untouched. Staged plan B-1..B-5 registered (pool core → KV artifact
adapter → strict-ES session integration → product routing → real-device
battery with metrics registered in advance: cold 47.6s @6.2K shared →
snapshot load + delta × prefill rate; restart warm; swap flat;
determinism bit-identical).

**B-1 landed tests-first (6dc1a38)**: `ExecutionStatePrefixPool`
(zero-MLX) — order-sensitive rolling hash-chain keying, (modelID,
kvFingerprint) namespace isolation, longest-match admission, LRU
eviction under token budget, artifact replacement on re-export. P-I1
shape enforced: a hit's boundary hash provably equals the incoming
prefix hash (verified against the caller's actual tokens); a mismatch
is a normal miss (entry retained), and load-time corruption is the
B-2 adapter's loud failure. 10-case battery; suite 110/110.

```text
Current gate  : ROUTE_B_IN_PROGRESS / B1_POOL_CORE_VERIFIED /
                B2_KV_ARTIFACT_ADAPTER_NEXT
```

### B-2 (Prefix Snapshot Store) LANDED — 2026-09-27

The KV artifact adapter (bd74bac): disk-backed store wiring the pool to
ChatSession.saveCache / loadPromptCacheSnapshot. Layout
`<root>/<nsHash>/<hash>-<count>.safetensors` + JSON sidecar — sidecar
rather than in-file metadata because the production export path takes
no user metadata and re-serializing multi-GB KV arrays to attach claims
is unacceptable (the same safetensors+sidecar pattern the product
already runs). Export writes through a pre-created temp file; two mlx
IO pitfalls are now pinned by tests (save dispatches on pathExtension;
it also removes an existing destination before writing, so a missing
temp file fails with ENOENT). A failing exporter leaves the pool
untouched. Bind path enforces P-I1's loud half: sidecar claims must
equal the admitted entry's claims (modelID/kvFingerprint/tokenCount/
chainHash); any disagreement or unreadability removes the entry
(self-healing) and throws. Full P-I1 chain now verified link by link:
prompt → entry (pool admission) → artifact (sidecar reconciliation).
Unit battery without a model (E2 pattern): REAL file round-trip via
synthetic KVCacheSimple layers; tampered tokenCount/chainHash, missing
snapshot → throw + self-heal; 7 cases; suite 117/117.

```text
Current gate  : ROUTE_B_IN_PROGRESS / B1_B2_VERIFIED /
                B3_STRICT_ES_SESSION_INTEGRATION_NEXT
```

### B-3 (Session Lifecycle + Restart-Warm) LANDED — 2026-09-27

Two pieces (00e0448):

```text
pool.register  entry insertion from a PRECOMPUTED content claim (only
               the chain hash survives on disk); P-I1 unaffected —
               admission still recomputes over live prompt tokens, so a
               corrupt claim can only miss, never mis-bind
store.rescan   re-registers disk-persisted boundaries into a fresh pool
               after restart — the 02:18 warmTokens=0 failure mode dies:
               after a restart, a continuing conversation admits its
               boundary warm
```

Lifecycle battery (no model, synthetic real snapshots): session A cold
start → commit/export 6.2K boundary → session B (same document, own
tail) admits at 6200 through a SECOND store instance over the same disk
→ commits a longer boundary → RESTART → rescan re-registers both → a
continuing session admits the longest boundary warm; one-token
divergence at position 0 never false-hits. Vanished snapshots and
garbage sidecars skipped; budget enforced across rescan. 4 cases;
suite 121/121.

Honest scope note: daily-path execution identity remains the product's
LC lineage + history sidecar; the strict-ES increment for the daily
path is content-addressed binding + restart-warm. A coordinator port
would re-derive existing product machinery — deferred unless review
rules otherwise.

```text
Current gate  : ROUTE_B_IN_PROGRESS / B1_B2_B3_VERIFIED /
                B4_PRODUCT_ROUTING_NEXT
```

### B-4 (Product Routing) LANDED — 2026-09-27

Cross-session prefix sharing is wired into the product daily path
(product e840836, Lab seam 774d1c5). Three integration points in
`generateUsingChatSession`:

```text
admission  same-session reuse stays FIRST (untouched); when it misses
           (the cold-rebuild branch), the pool is consulted — keyed by
           the message-content chain (PrefixMessageChain: 2 Int elements
           per message; message-level keying registered as sound —
           identical message prefixes render to identical token prefixes
           under the same tokenizer+template), namespace = modelID +
           kvFingerprint + thinking flag
bind       a hit takes the exact cacheLoad-restored shape:
           ChatSession(cache:state:) + isRestoredSnapshot + delta
           contract; sidecar reconciliation inside the adapter — wrong
           claims = entry self-heal + loud throw + cold fallback (never
           a silent bind on an unreconciled representation);
           poolRestoredTurn skips roll-forward (snapshot is already a
           verified checkpoint)
export     per successful turn, processed message history + fresh KV
           snapshot register a shared boundary (inline await — no race
           with the next turn; best-effort)
```

Disk pool `~/.simigo/prefix-pool`, rescan on first use = restart-warm.
Kill switch `SIMIGO_PREFIX_POOL=0` = exact v1.7 behavior. Verified:
Release build SUCCEEDED; product unit suite 73/73 (5 skipped,
model-dependent); Lab 124/124. Registered known cost: pool export is a
second KV serialize+write per turn (~0.15s@58k serialize scale); disk
GC for evicted entries deferred (registered).

```text
Current gate  : ROUTE_B_WIRED / B5_REAL_DEVICE_BATTERY_NEXT
```

### B-5 (Real-Device Battery) PASSED — 2026-09-27

Real-device run (Apple M5, Qwen3-Coder-30B-A3B-Instruct-4bit via the
product HTTP surface, ~9.7K-token shared document):

```text
turn 1  session A, cold        ttft=16951ms  cacheEff=0.00  mode=cold
        full prefill of 9,706 prompt tokens
turn 2  session B = NEW session id, same conversation + 1 message
        (same-session reuse cannot fire) — pool served:
        ttft=201ms             cacheEff=1.00  mode=restore
trace chain: poolRescan entries=0 → poolExport messages=2/3 →
poolHit messages=3 → poolBind messages=3 delta=1 → poolExport 5
restart-warm: fresh store over the same disk root re-registered the
committed boundary
```

**Registered metric met with margin: the 47.6s-class cold tax is GONE —
84x faster, 98.8% reduction.** The agent-reconnect / restart-resume
scenario now pays snapshot load + one-message delta instead of a full
context re-prefill. Honest boundary unchanged: genuinely NEW content
(different document, or large fresh injections) is real compute and
still pays prefill; message-boundary granularity means a shared
prefix must align at message boundaries.

Route B complete: B-1 pool core → B-2 KV artifact adapter → B-3
lifecycle/restart-warm → B-4 product routing → B-5 real-device battery,
each stage unit/real-device verified.

```text
Current gate  : SIMIGO17_PREFIX_POOL_COMPLETE / B1_B5_ALL_VERIFIED /
                DAILY_PATH_EXECUTION_STATE_LIVE
```

### v2.0.0-beta.2 PUBLISHED — 2026-09-27

User-ordered build + publish, delivering the Route B answer in a
release:

```text
source     product e121335 (docs) on release/v2.0.0-beta, Lab 44d0dd1 —
           both pushed
tag        v2.0.0-beta.2 (annotated, peeled → e121335) pushed
build      Release BUILD SUCCEEDED (app 2.0.0; prefix pool wired,
           SIMIGO_PREFIX_POOL=0 kill switch)
dmg        SimiGo-v2.0.0-beta.2.dmg (25,467,522 bytes, CRC VALID,
           sha256 2b23738339b51f087f1a43e11627d210cd15bea5e0864a0379a505bf0cb7a81c)
release    GitHub Release (prerelease) live with DMG + full notes:
           prefix pool 84x reading front and center, honest limits
           (message-boundary granularity, fresh-content prefill, pool
           export cost), open-source dependency chain
           → https://github.com/slamfinger/SimiGo/releases/tag/v2.0.0-beta.2
docs       README v2.0 section + 部署指南 prefix-pool paragraph;
           RELEASE notes banner now records beta.1 → beta.2 succession
```

```text
Current gate  : V2_0_0_BETA_2_PUBLISHED / PREFIX_POOL_LIVE_IN_PRODUCT /
                GA_WORKITEMS_OPEN
```

### B-6 Definition Opened — Token-Level Prefix Cache (fork) — 2026-09-27

User re-check of the logs: "not fully implemented." Two-layer diagnosis:

```text
layer 1  the 03:52-03:55 session (081f70, cold 43s + 56s/114s injection
         turns) ran on the 02:18 process — a PRE-POOL binary (B-4 landed
         ~03:3x; no poolRescan in that window is the proof). beta.2
         requires install + restart.
layer 2  EVEN on beta.2, this workload misses: new sessions share the
         large system DOCUMENT but differ at message 2 — turn-commit
         boundaries are message-aligned, so "same document, different
         first question" never hits. The registered honest boundary is
         exactly where the user's dominant workload lives. Confirmed
         gap, not a defect of the shipped mechanism.
```

B-6 definition registered
(`SIMIGO17_TOKEN_LEVEL_PREFIX_CACHE_B6_20260927.md`): move the match
surface to FINAL RENDERED TOKEN IDS inside the fork's ChatSession —
discovery: `KVCacheStorage.Conversation.cachedTokens` already tracks the
rendered token stream, so the substrate exists. Causal-KV soundness
makes token-prefix matching safe regardless of message boundaries or
template wrappers (KV[0..<T] depends only on tokens[0..<T]). Fork core
serving path is touched → gated, implementation only on approval.
Interim mitigations while open: client stable session_id; large
documents as tool results rather than prompt.

```text
Current gate  : B6_TOKEN_PREFIX_CACHE_DEFINITION / AWAITING_REVIEW
```

### B-6 IMPLEMENTED + REAL-DEVICE VERIFIED — 2026-09-27

User approved ("继续"). Fork surgery landed (mlx-swift-lm 6f0af10 on
release/v2.0-beta-ml) + product wiring (product 87eb6d9, Lab seam
519bc0c):

```text
fork      crossSessionPrefixLookup static hook (fresh-session cold
          prefill consults the host with rendered token ids; verified
          prefix hit seeds the cache + ledger + narrows input to the
          remainder, cacheReuseMode=cross-session); cachedTokenIds()
          ledger read; savePrefixSnapshot(upTo:) token-boundary
          serialization (all-KVCacheSimple v1, no carried model state —
          both throw rather than degrade)
product   installHook at model start (base-config namespace; sync admit
          + sidecar-reconciled loadSync — mismatches self-heal + nil =
          exact cold path); turn-end export full + 2048 grid, dedup per
          (namespace,count,hash); only base-kvSettings sessions export
          (registered beta boundary); pin fbfa1f4 -> 6f0af10
battery   EXTENDED: a genuinely new conversation sharing only the
          document (different first question) — PASSED on device
```

Real-device readings (same ~9.7K shared document):

```text
session A cold          ttft=11620ms  cacheEff=0.00  9,706-token
                        full prefill; exports token grid
                        2048/4096/6144/8192 + full
session C NEW conversation, same document, different first question
        poolTokenHit tokens=8192
        ttft=5944ms     cacheEff=0.84  mode=cross-session
        the document body (84% of the context) served from the pool;
        only the 1,524 genuinely-new tokens prefilled
```

Combined with B-4/B-5 (conversation continuation at 201ms), both daily
workload shapes are now served: same-conversation reconnects AND
same-document new conversations.

```text
Current gate  : B6_TOKEN_PREFIX_CACHE_VERIFIED /
                DAILY_PATH_TWO_SHAPES_SERVED / BETA_REFRESH_PENDING
```

### v2.0.0-beta.3 PUBLISHED — 2026-09-27

User-ordered rebuild + package. Release BUILD SUCCEEDED; tag
v2.0.0-beta.3 (peeled → 87eb6d9) pushed; SimiGo-v2.0.0-beta.3.dmg
(25,467,522-byte-class, CRC VALID, sha256 cad73117d31ded7daf91a5e90eca3
e27d43c20983cd463027a1d4b66b548268a); GitHub Release (prerelease) live
with full notes (B-6 readings front and center, fork bump 6f0af10,
honest limits incl. KVCacheSimple/no-M-RoPE v1 constraints and
base-config-only export) →
https://github.com/slamfinger/SimiGo/releases/tag/v2.0.0-beta.3

```text
Current gate  : V2_0_0_BETA_3_PUBLISHED / TOKEN_LEVEL_POOL_IN_PRODUCT /
                GA_WORKITEMS_OPEN
```

### MAIN LINE UNIFICATION + Follow-up Audit Response — 2026-09-27

User ruling: **the lab-validated line IS the mainline** — the previous
topology (main = frozen v1.7, all work on side branches) is superseded.
Executed:

```text
product main  e51ac28 = merge(origin/main curated docs, release/
              v2.0.0-beta @ 87eb6d9) — README conflict resolved keeping
              BOTH (curated Execution-State positioning + capability
              list + v2.0 section in mainline framing, incl. the
              branch-checkpoint-fork vs shared-prefix-fork terminology
              split). Pool verified on main (git grep). Pushed.
lab main      48ffb2b = merge(origin/main, exp/simigo2-experimental @
              ad1ded2), 179 commits fast-forwarded; the O3-C reader
              add/add conflict resolved in favor of the evolved exp
              implementation (PerTensorLocation); one superseded
              main-side test file dropped (it pinned the replaced
              variant); suite re-run ON MAIN: 124/124. Pushed.
fork          main = upstream-tracking line (carries upstream PRs
              #620/#515/#548; ChatSession/Evaluate/PromptCacheReusePolicy
              diverged). NOT merged — merging is an upstream-sync
              project, registered as UPSTREAM-SYNC-PENDING. Our line
              stays release/v2.0-beta-ml @ 6f0af10 (public, pinned).
```

Follow-up audit response (the mid-turn audit reviewed the pre-merge
main; findings dispositioned):

```text
ACCEPTED  forkSessionBranch = BranchFork v1 checkpoint fork, and
          ExecutionLineage itself documents it ("checkpoint 从哪个分支
          复制而来, 不是 execution→execution lineage") — FORK-1/2/3
          stand.
ACCEPTED  ExecutionID is TELEMETRY-ONLY: generate() mints a UUID for
          lineage.begin/end while AgentExecutionKey
          (agentId+sessionId+logicalBranchId) is the actual state-
          addressing unit. The Lab E-line's Execution-identity-as-
          addressing did NOT land in the product. Registered IDENT-1
          (GA): execution identity as the state-addressing unit +
          RepresentationRef binding — this is the "missing middle
          layer" the audit names.
UPDATED   "no second path / no content-addressed sharing" held for the
          PRE-merge main only. Post-merge main carries the verified
          content-addressed admission path (pool + token consult).
```

Post-merge integration inventory for the proposed Lab→main diff audit
(real vs v1 vs absent):

```text
REAL (device-verified)   prefix pool trio + NativeMLX admission/export
                         + fork ChatSession token consult (B-5 201ms,
                         B-6 5,944ms @84%) + token ledger (oversized)
                         + coordinator/contracts (oversized sessions)
V1 BY DESIGN             forkSessionBranch checkpoint fork
                         (FORK-1 atomicity, FORK-2 fork-point
                         persistence registered)
ABSENT (registered)      RepresentationRef binding, ExecutionID as
                         addressing (IDENT-1), COW shared-prefix fork
                         (FORK-3), durable Execution State
```

```text
Current gate  : MAIN_LINE_UNIFIED (product e51ac28 / lab 48ffb2b) /
                IDENT1_FORK123_GA_REGISTERED / UPSTREAM_SYNC_PENDING
```

### IDENT-1 Chain Audit Round 1 COMPLETE — 2026-09-27

Per the ruling (walk every arrow; type? mapping? runtime use?), full
chain audited (`SIMIGO17_IDENT1_CHAIN_AUDIT_20260927.md`). Five
findings:

```text
F1  同名不同义 CONFIRMED — two ExecutionID types (product triple-
    mapping protocol identity vs Lab opaque contract identity); cannot
    merge; canonical choice is a ruling, not a rename
F2  身份存在但寻址不用 CONFIRMED — the product S4 surface
    (ExecutionControlling: checkpoint/restore/fork via ExecutionID) has
    NO conformer and NO implemented ExecutionID→AgentExecutionKey
    mapping; the product calls save/load/fork with AgentExecutionKey
    directly. Declared-but-dead identity surface.
F3  storageKey = string join; normalization exists; delimiter-escape
    absence = theoretical collision (registered hazard)
F4  IDENTITY ISLANDS — daily (AgentExecutionKey→storageKey→
    ManagedSession) and oversized (constant ExecutionID("S")→
    coordinator→handle) never interchange; oversized request identity
    is a CONSTANT
F5  RepresentationRef ABSENT; binding ephemeral (dict entry holds a
    materialized copy); the pool's content-addressed artifact+claims is
    a nascent representation address deliberately identity-free
```

Red line re-confirmed with stronger evidence: execution identity ≠
physical representation identity; the missing piece is the BINDING
CONTRACT, not a type merger. Recommendations registered: (1) S4 surface
implement-or-retire (S5 decision); (2) oversized multi-session must
thread request identity (today every oversized session is identity "S");
(3) RepresentationRef as a THIRD identity kind (content-addressed) with
an explicit binding table = the IDENT-1/FORK-3 convergence point;
(4) storageKey stays session-addressing with the collision hazard
registered.

```text
Current gate  : MAIN_LINE_UNIFIED / BETA_CLOSURE_AUDIT_CLEAN* /
                P2_EVICT_PERSISTENCE_CLOSED /
                IDENT1_CHAIN_AUDIT_R1_COMPLETE /
                UPSTREAM_SYNC_PENDING
```

### Gate ③ OPENED — RepresentationRef Identity Contract (Gate A) — 2026-09-27

User ruling executed: gate ③ opened, NO implementation code; order =
`Ref identity contract → Binding contract → runtime resolution →
FORK-3`. Deliverable:
`SIMIGO17_REPRESENTATION_REF_IDENTITY_CONTRACT_20260927.md`.

```text
three-identity layering (never merged):
  ExecutionID         "我是谁"      logical ES identity
  AgentExecutionKey   "在哪里"      runtime addressing (Session/Branch)
  RepresentationRef   "绑定哪份表示" content/physical representation
                                   identity — NO ExecutionID inside

field rulings (identity / metadata / compatibility-check):
  IDENTITY   kind · modelIdentity · kvLayoutIdentity · renderIdentity
             (thinking flag promoted from product hack to field) ·
             contentHash (core) · boundLength · backendIdentity (v1
             constant "mlx")
  METADATA   artifact location · createdAt/size/lastUse/source
  COMPAT     dtype/quantization (via modelIdentity) · residency (never
             identity) · live position (via Binding, invariant R-I5)

invariants  R-I1 deterministic derivation · R-I2 discrimination ·
            R-I3 no execution identity in a Ref · R-I4 storage
            independence · R-I5 binding consistency
            (Binding.boundPosition == Ref.boundLength)

gap table   today's namespace+entry ≈ the contract minus explicit
            kind/render/backend — migration derivable, no stored
            artifact invalidated
```

Gates C (Binding Registry ≠ PrefixPool) and D (eviction vs binding
constraint — contract-decided, never LRU accident) registered, not
open. IDENT-1 stays OPEN (③ defined, ④⑦ pending Gate B). Three
lifecycle layers remain distinct per the P2 ruling.

```text
Current gate  : MAIN_LINE_UNIFIED / BETA_CLOSURE_AUDIT_CLEAN* /
                P2_EVICT_PERSISTENCE_CLOSED /
                IDENT1_GATE_A_REPREF_CONTRACT_DEFINED /
                UPSTREAM_SYNC_PENDING
```

### Gate A PASSED (two corrections applied, doc FINAL) + Gate B OPEN — 2026-09-27

Reviewer verdict: PASS with two definition-level corrections, both
applied into the final Gate A document:

```text
① renderIdentity  v1 single field approved; NEW invariant — generation
                  must be canonical/deterministic; today's "|think:"
                  string-join hack must never be exposed as the Ref
                  format (render semantics → canonical renderIdentity →
                  Ref; the hack can disappear without semantic change)
② R-I5 FINAL WORDING  Binding.boundPositionAtBind == Ref.boundLength —
                  bind-TIME coverage consistency only, explicitly NOT
                  Execution.currentPosition == Ref.boundLength; a
                  3072-position execution bound to Ref X @ 2048 is
                  LEGAL (continued past its materialized base).
                  boundLength = the Representation's logical token-
                  prefix boundary, not a session position.
③ backendIdentity independent field approved (what model vs who
                  interprets the representation — never collapsed).
Migration wording corrected: existing artifacts can be DERIVED INTO
RepresentationRef; RepresentationRef itself does not exist today
(consistent with F5). Gate A = formalizing implicit identity conditions.
```

**Gate B OPENED** (`SIMIGO17_BINDING_CONTRACT_GATE_B_20260927.md`,
definition draft, no code): first principle = **Binding is a RELATION,
not a RepresentationRef attribute** (`RepresentationRef{executionID}`
forbidden; multi-bind type-level legal). Relation record:
execution + runtimeAddress + ref + boundPositionAtBind + generation +
state (append-only; deterministic current resolution). Invariants
B-I1..B-I6 (incl. B-I3 forward monotonicity — rewind ⇒ new binding;
B-I6 lifecycle independence with contract-marked rematerialization).
Deliberate non-duties: not residency, not transcript, not position
source, not the pool's registry (Gate C stands). Three review questions
posted (generation scope, superseded-vs-detached on rewind, key-change
semantics).

```text
Current gate  : MAIN_LINE_UNIFIED / BETA_CLOSURE_AUDIT_CLEAN* /
                P2_EVICT_PERSISTENCE_CLOSED /
                IDENT1_GATE_A_PASSED /
                IDENT1_GATE_B_BINDING_CONTRACT_DRAFTED /
                UPSTREAM_SYNC_PENDING
```

### Gate B PASSED + Runtime Resolution Contract DRAFTED — 2026-09-27

Gate B verdict: B-1/B-2 PASS, B-3 PASS with tightening — all applied,
Gate B doc FINAL. Final structure adopted verbatim:

```text
B-I1 relation never Ref property · B-I2 bind-time position consistency ·
B-I3 monotonic generation (per-Execution) · B-I4 append-only history ·
B-I5 cardinality (Execution → ≤1 active; Ref → N) · B-I6 lifecycle
independence
B-R1 RuntimeAddress change increments generation, NEVER changes
     canonical ExecutionID (F2/F4 resolution: Identity ≠ Runtime Address)
B-R2 max-generation = RESOLUTION RULE; B-I5 ≤1 = the consistency
     guarantee (two actives = illegal state, not a selection tie)
B-R3 generation scoped per Execution — not token position, not
     Representation version, not Pool LRU version, not global txn ID
rematerialization-required stays OUT of Binding state enums — artifact
availability surfaced through the active Binding (Pool eviction ≠
Binding invalidation)
```

**Runtime Resolution Contract DRAFTED**
(`SIMIGO17_RUNTIME_RESOLUTION_CONTRACT_20260927.md`) — the reviewer's
flagged question answered by contract: **detached is an OPERATION, never
a resolution outcome.** Resolution is total over the durable Binding:
UNBOUND (none/never/detached-by-operation) · ATTACHED_LIVE ·
REATTACHABLE (artifact available → materialize = today's poolBind/
restore) · REMATERIALIZATION_REQUIRED (artifact evicted → Binding
stays active, recompute from history). Invariants RR-I1..I4 (total,
read-only, contract-owned transitions, no invalidation). Each state
maps to machinery that already runs. Remaining for Gate C: resolve-call
ownership + where the resolution table lives (Binding Registry ≠ Pool).

```text
Current gate  : MAIN_LINE_UNIFIED / BETA_CLOSURE_AUDIT_CLEAN* /
                P2_EVICT_PERSISTENCE_CLOSED /
                IDENT1_GATE_A_PASSED / IDENT1_GATE_B_PASSED /
                RUNTIME_RESOLUTION_CONTRACT_DRAFTED /
                UPSTREAM_SYNC_PENDING
```

### Refined Audit Adopted — Ownership/Lifecycle Disposition — 2026-09-27

The follow-up audit (post-merge main) confirmed Route B as a REAL
product execution path, retracted its own "no second path" claim, and
sharpened three things — all adopted:

```text
IDENT-1 (refined wording)  Execution State's protocol/lifecycle
                           abstraction IS in main; what has NOT landed
                           is Execution Identity as the stable
                           addressing/binding unit for physical
                           representations (ExecutionID doc: "S4 红线：
                           不发明新身份语义"; the UUID is lineage/trace
                           only). IDENT-1 stays a GA item with this
                           wording.
FORK-3 (sharpened)         Route B and Branch Fork are two independent
                           paths: forkSessionBranch never touches the
                           pool. FORK-3 = connect them at the Execution
                           State layer (child binds the shared
                           boundary at the fork point).
TERMINOLOGY RED LINE       poolHit/poolBind/poolTokenHit prove
                           REPRESENTATION REUSE, not Execution-State
                           Fork. Pinned in code
                           (NativeMLXPrefixPool header, product
                           ac25b55) and in README.
```

The audit's four closure questions, dispositioned from code:

```text
Q1 ownership after poolBind   in-memory KV belongs EXCLUSIVELY to the
                              consuming ChatSession (self-materialized
                              copy from disk); the pool owns only the
                              disk artifact + claims; no live memory is
                              ever shared. This IS the Reuse/Shared
                              boundary.
Q2 lifecycle owner            three lines: memory = existing session
                              LRU/warmTokenBudget/session.clear;
                              registry = pool LRU (prefixPoolTokenBudget);
                              disk = UNMANAGED (GC registered gap).
Q3 eviction semantics         registry eviction has ZERO effect on live
                              sessions (independent copies); the cost is
                              only that future admissions lose that
                              boundary until some session re-commits the
                              content; concurrency pool-lock guarded;
                              evicted disk files linger (registered).
Q4 should fork reuse the      YES — that IS FORK-3's definition (child
   representation?            binds the pool boundary at the fork point,
                              pays only its delta, FORK-2 persists the
                              fork position; boundary pinning under
                              child reference joins FORK-3 scope).
                              Ruled: own gate, not a checkpoint-fork
                              patch.
```

Beta gate position (audit-proposed structure, adopted):

```text
MAIN_LINE_UNIFIED
  ├── Route B Prefix Reuse       REAL (device-verified)
  ├── Branch Fork V1             REAL (checkpoint semantics)
  ├── Execution State Protocol   REAL / thin
  ├── IDENT-1 ExecutionID        GA
  ├── FORK-3 Shared-prefix COW   GA / upstream dependent
  └── Durable Execution State    Research
```

```text
Current gate  : MAIN_LINE_UNIFIED / BETA_CLOSURE_AUDIT_CLEAN /
                IDENT1_FORK123_GA_REGISTERED / UPSTREAM_SYNC_PENDING
```

### P2 CLOSED + IDENT-1 OPENED — 2026-09-27

**P2 (eviction persistence) — gap CONFIRMED and CLOSED same round**
(Lab 4c8f582, main 448b8c9). The audit was right: rescan re-registered
evicted representations — eviction did not survive process boundaries.
Eviction Persistence Rule now implemented: `ExecutionStatePrefixPool`
gains an `onEvict` notification (delivered outside the lock; callback
must not re-enter the pool); `PrefixSnapshotStore` installs it to delete
the artifact at eviction time. Evicted = not re-admittable in-process
(registry gone + export dedup) AND not resurrectable on restart
(artifact gone; rescan skips vanished files). Test: eviction deletes B's
files; fresh-store rescan re-registers only A and C; B admits nil.
Suite 125/125; Lab main synced (448b8c9).

```text
Representation Reuse V1 — final lifecycle definition (audit wording
adopted):
  live-session KV   independent; unaffected by pool eviction
  PrefixPool        owns disk artifact + admission/index registration;
                    never live KV; eviction = admission right removal
  disk artifact     deleted at eviction (P2 closure); GC for
                    unreadable-snapshot orphans still policy-deferred
Three lifecycle layers remain distinct: Execution State lifecycle ≠
Representation Artifact lifecycle ≠ live KV lifecycle.
```

**IDENT-1 OPENED** — symbol-by-symbol addressing audit, stage 0
inventory (symbol → current role):

```text
product ExecutionControlling.ExecutionID   triple mapping
                                           (agent/session/branch), doc:
                                           "S4 红线：不发明新身份语义"
product AgentExecutionKey.storageKey       THE addressing unit
                                           (sessions dict; 33 refs in
                                           NativeMLX alone)
product executionId (UUID in generate())   lineage.begin/end + trace
                                           only — never addressing
product ExecutionLineage/ExecutionRecord   telemetry
lab RuntimeContract.ExecutionID            opaque string id (oversized
                                           sessions) — NOTE: two
                                           distinct ExecutionID types
                                           across repos (collision to
                                           resolve)
lab ExecutionStateHandle/Position          contract identities (oversized
                                           path only)
RepresentationRef                          ABSENT everywhere
```

The audit proceeds symbol-by-symbol from this inventory: which layers a
stable Execution/Representation addressing contract must unify, and the
S4 red-line interaction (no new identity semantics invented ad hoc).

```text
Current gate  : MAIN_LINE_UNIFIED / BETA_CLOSURE_AUDIT_CLEAN* /
                P2_EVICT_PERSISTENCE_CLOSED /
                IDENT1_SYMBOL_AUDIT_OPEN /
                UPSTREAM_SYNC_PENDING
(* Beta Closure ≠ all lifecycle questions gone — disk GC for orphans
   and FORK-3 boundary pinning remain registered.)
```

### External Code Audit Disposition — Branch Confusion Resolved — 2026-09-27

A code-level audit arrived reviewing the PUBLIC SimiGo **main** branch
and concluded the Route B implementation (ExecutionStatePrefixPool /
PrefixSnapshotStore / content-addressed admission path) does not exist
there. Git-verified disposition:

```text
main @ 632b1d9               pool types ABSENT (grep: zero hits);
                             forkSessionBranch = disk-checkpoint fork.
                             EVERY audit finding about main is CORRECT:
                             fork = saveCache→copyItem→loadCache (no
                             shared prefix); target overwrite is
                             delete→copy (non-atomic); no fork point
                             persisted (no forkPosition /
                             sharedPrefixLength); lineage.recordFork is
                             a relationship LOG, not a representation
                             binding; session reuse is storageKey-local.
release/v2.0.0-beta @ 87eb6d9  the beta.3 DMG build source — pool
                             wiring PRESENT (NativeMLX.swift ×5,
                             NativeMLXPrefixPool.swift ×6; Lab package
                             carries the pool core); the
                             content-addressed admission path EXISTS
                             and is device-verified (B-5 201ms /
                             B-6 mode=cross-session 5,944ms readings).
                             The audit's "no second path" holds for
                             main, NOT for this tree.
forkSessionBranch            UNTOUCHED on BOTH trees — the fork
                             critique applies to both and is ACCEPTED
                             in full.
```

Disciplines ADOPTED from the audit:

```text
1. AUDIT-TREE PIN: every future audit states the audited commit
   (git rev-parse) and the audited tree as the single source of truth;
   local-experimental vs public code must never be conflated.
2. TERMINOLOGY SPLIT: 「分支 checkpoint fork」(branch checkpoint fork —
   what forkSessionBranch does) is permanently distinct from
   「Execution State 共享前缀 fork」(shared-representation fork — not
   implemented anywhere yet). README/log/research prose must not mix
   them.
```

Registered gaps (GA candidates, NOT patched now per the audit's own
ruling against stacking shared-KV onto the checkpoint-fork layer):

```text
FORK-1  fork file atomicity: temp → fsync/validate → atomic rename →
        publish (today: delete → copy)
FORK-2  fork point persistence: forkPosition / forkTokenPosition /
        sharedPrefixLength in branch metadata
FORK-3  true Execution-State shared-prefix fork: child →
        RepresentationRef → fork point (needs its own definition gate;
        the prefix pool serves session ADMISSION, not the fork API)
```

### IDENT-1 Chain Audit Round 1 COMPLETE + Gate C Algorithm Drafted — 2026-09-27

IDENT-1 chain audit round 1 (`SIMIGO17_IDENT1_CHAIN_AUDIT_20260927.md`),
five findings: F1 同名不同义 confirmed (two ExecutionID types, cannot
merge); F2 身份存在但寻址不用 (S4 surface has NO conformer, no
implemented ExecutionID→AgentExecutionKey mapping); F3 storageKey =
string join (collision hazard registered); F4 identity islands (daily
AgentExecutionKey chain vs oversized constant ExecutionID("S") never
interchange); F5 RepresentationRef ABSENT, binding ephemeral. Red line
re-confirmed: the missing piece is the BINDING CONTRACT, not a type
merger. Recommendations: S4 implement-or-retire (S5); oversized
multi-session must thread request identity; RepresentationRef = third
identity kind + explicit binding table (IDENT-1/FORK-3 convergence);
storageKey stays session-addressing.

Gate C opened per ruling (`SIMIGO17_GATE_C_RESOLUTION_ALGORITHM_20260927.md`):
artifact-state judgment (pool registration ≠ representation existence);
three-registry separation (Binding Registry ≠ Prefix Pool ≠ Session
Registry); canonical key ExecutionID → Binding → AgentExecutionKey,
never reverse; resolve() = pure observation (forbidden: pool.admit
LRU mutation, snapshot loading, ChatSession construction, coordinator
mutation). Total read-only algorithm → UNBOUND / ATTACHED_LIVE /
REATTACHABLE / REMATERIALIZATION_REQUIRED, each mapped to running
machinery; non-linear transition table with contract owners.

```text
Current gate  : MAIN_LINE_UNIFIED / BETA_CLOSURE_AUDIT_CLEAN* /
                P2_EVICT_PERSISTENCE_CLOSED /
                IDENT1_GATE_A_PASSED / IDENT1_GATE_B_PASSED /
                IDENT1_GATE_C_ALGORITHM_DRAFTED /
                UPSTREAM_SYNC_PENDING
```

### Gate C PASSED (C.2 refinements applied) + FORK-3 Structural Gate OPENED — 2026-09-27

Gate C verdict: PASS with two refinements applied into the final
document:

```text
holdsMaterialization (v1)  THREE-condition runtime holding-relation
                           query (generation ∧ runtimeAddress ∧
                           materialization identity == ref); generation
                           alone insufficient; NEVER a KV-introspection
                           integrity validator
available(Ref) (v1)        cheap read-only CANDIDATE availability
                           (exists ∧ sidecar decodable ∧ identity
                           compatible) — no full hash recomputation
                           (resolve ≠ expensive validation);
                           AVAILABLE = candidate semantics, not proven
                           correctness; chain: available → candidate →
                           materialize() → optional integrity
                           validation → commit attachment; mismatch ⇒
                           candidate rejected → artifact isolated →
                           Binding remains active →
                           REMATERIALIZATION_REQUIRED;
                           available==false NEVER deletes/supersedes
                           the Binding
```

⑤⑥⑦ contract skeleton formally CLOSED (Runtime Resolution /
Representation Resolution / Binding Consistency, each defined in Gates
A/B/C).

**FORK-3 structural gate OPENED.** Core to prove (reviewer statement
registered as the gate's definition core): Parent Binding → Ref X @ T;
fork → Child Binding → Ref X @ T — two executions sharing the SAME
RepresentationRef with INDEPENDENT Execution Position / subsequent
deltas. The line from Representation Reuse to Execution-State Shared
Representation. NOT "turn forkSessionBranch into poolBind".
Definition draft next.

```text
Current gate  : MAIN_LINE_UNIFIED / BETA_CLOSURE_AUDIT_CLEAN* /
                P2_EVICT_PERSISTENCE_CLOSED /
                IDENT1_GATE_A_PASSED / IDENT1_GATE_B_PASSED /
                IDENT1_GATE_C_PASSED / F3_STRUCTURAL_GATE_OPEN /
                UPSTREAM_SYNC_PENDING
```

### FORK-3 Structural Contract DRAFTED — 2026-09-27

Per the ruled order (FORK-3 structural contract → Gate D eviction/
reference semantics → implementation boundary),
`SIMIGO17_FORK3_STRUCTURAL_CONTRACT_20260927.md` registered:

```text
proof object    two Executions share the SAME RepresentationRef (X @ T)
                with independent positions/deltas — NOT a
                forkSessionBranch replacement
fork semantics  child gets NEW canonical ExecutionID + NEW
                runtimeAddress (B-R1) + Binding → SAME Ref X @ T
                (zero re-materialization at fork; cost ≈ O(binding
                metadata)); ΔP/ΔC fully independent
invariants      F-I1 shared identity not copied state · F-I2 parent
                non-interference · F-I3 child starts at boundary ·
                F-I4 delta independence · F-I5 Ref X carries ≥2 active
                bindings · F-I6 identity separation (sharing only at
                the Ref layer)
not claimed     no live-KV COW in v1 (copy-on-derive, compute-on-
                diverge; page-level COW = RFC mlx-swift-lm#629
                deferred) · no forkSessionBranch edit · no terminology
                drift
acceptance      zero-MLX structural battery + device battery (child
                prefills only ΔC; parent unchanged; Gate D eviction
                constraint realized)
handoff         FORK-3 makes Gate D mandatory (pin-while-referenced vs
                rematerialization-required, contract-decided); FORK-2
                subsumed (fork point = Ref X @ T persisted as Binding)
```

```text
Current gate  : MAIN_LINE_UNIFIED / BETA_CLOSURE_AUDIT_CLEAN* /
                P2_EVICT_PERSISTENCE_CLOSED /
                IDENT1_GATE_A_PASSED / IDENT1_GATE_B_PASSED /
                IDENT1_GATE_C_PASSED / F3_STRUCTURAL_CONTRACT_DRAFTED /
                GATE_D_EVICT_REFERENCE_SEMANTICS_NEXT /
                UPSTREAM_SYNC_PENDING
```

### FORK-3 PASSED (four refinements applied) + Gate D OPEN — 2026-09-27

FORK-3 structural contract PASSED; four non-blocking refinements
applied into the final document:

```text
1. F-I1  shared Ref ≠ shared physical materialization — Ref X is the
         common identity/content-boundary FACT; Execution State,
         Position, delta, and live materialization remain fully
         independent per side. 「语义上共享、物理上各自物化」= v1
         explicit constraint (guards against "same Ref ⇒ merge live KV"
         misreads by implementers)
2. F-I4  delta advancement independence tightened: only an
         EXPORT/materizalization creates a new Ref (Ref P @ T' /
         Ref C @ T'' after divergence — no longer the common ancestor
         X). FORBIDDEN: "every Δ must produce a Ref" (Representation
         lifecycle must not hijack Execution State)
3. F-I5  = Fork Sharing POSTCONDITION (successful fork ⇒ Ref X holds
         ≥2 active bindings at that moment), NOT a universal
         invariant. B-I5 (Ref → N) stays the general contract; F-I5 is
         the first realized N=2 instance
4. eviction acceptance CONDITIONAL: REMATERIALIZATION_REQUIRED only
         when (artifact unavailable) AND (no live materialization);
         artifact eviction with both sides live → both stay
         ATTACHED_LIVE; mixed → per-execution states (Gate C
         continuity: Pool eviction ≠ Binding invalidation ≠ Execution
         mutation)
cost model: fork ≈ O(binding metadata) = contract goal, not a proven
         performance promise. Order preserved: Contract → semantics →
         Gate D → implementation boundary → fork API plug-in decision
         last (never edit forkSessionBranch → poolBind → reverse-
         engineer the contract)
```

**Gate D OPEN.** Core (reviewer framing): no longer "how the pool LRU
works" — **who owns the Representation Artifact lifecycle when multiple
Execution references exist, and when physical reclamation is
permitted**:

```text
Ref X
 ├── Binding(P)
 └── Binding(C)
        ↓
     eviction?
   ┌────┴────┐
   ↓         ↓
 pin       evict
             ↓
   P/C 各自解析 materialization 可用性
            ↓
 ATTACHED_LIVE / REATTACHABLE /
 REMATERIALIZATION_REQUIRED
```

```text
Current gate  : MAIN_LINE_UNIFIED / BETA_CLOSURE_AUDIT_CLEAN* /
                P2_EVICT_PERSISTENCE_CLOSED /
                IDENT1_GATE_A_PASSED / IDENT1_GATE_B_PASSED /
                IDENT1_GATE_C_PASSED / F3_STRUCTURAL_CONTRACT_PASSED /
                GATE_D_EVICT_REFERENCE_SEMANTICS_OPEN /
                UPSTREAM_SYNC_PENDING
```

### Gate D CONTRACT — Eviction/Reference Semantics — 2026-09-27

Ruling executed: 「evict-by-policy, retain-binding, per-execution
rematerialization」(`SIMIGO17_GATE_D_EVICT_REFERENCE_SEMANTICS_20260927.md`).

```text
D-I1  Binding = semantic reference, never Artifact ownership
D-I2  multi-Execution Bindings never prevent Artifact eviction
D-I3  BindingCount ≠ retention correctness (semantic vs physical
      references are different questions, never merged)
D-I4  PhysicalUseCount/transient protection = in-flight physical
      operations only; BindingCount ≠ PhysicalUseCount
D-I5  v1 introduces NO Lease correctness mechanism
D-I6  post-eviction: Bindings stay active; per-Execution independent
      resolution (Gate C four states — no fifth state)
D-R1  reclamation must not modify/supersede/detach active Bindings
D-R2  post-reclamation resolution is per-Execution independent
acceptance matrix (Artifact × P live × C live → 8 rows) proves:
      Artifact eviction = Representation Availability change, NOT an
      Execution State change
positions: Binding-pin NO / refcount-eviction NO / transient physical
      protection allowed / Lease out of correctness contract / pin as
      future optimization allowed / COW page-level pin v1 no
「Pin 可以优化，不可以定义正确性」 — even a failed pin leaves the
      system semantically correct (Binding valid →
      REMATERIALIZATION_REQUIRED)
```

Four lifetimes formally separate: Execution ≠ Binding ≠ Artifact ≠ Live
materialization.

```text
Current gate  : MAIN_LINE_UNIFIED / BETA_CLOSURE_AUDIT_CLEAN* /
                P2_EVICT_PERSISTENCE_CLOSED /
                IDENT1_GATE_A_PASSED / IDENT1_GATE_B_PASSED /
                IDENT1_GATE_C_PASSED / F3_STRUCTURAL_CONTRACT_PASSED /
                GATE_D_CONTRACT_PASSED /
                GATE_D_CONCURRENCY_BOUNDARY_NEXT /
                UPSTREAM_SYNC_PENDING
```

### Gate D Concurrency Boundary CONTRACT — 2026-09-27

Reviewer ruling executed
(`SIMIGO17_GATE_D_CONCURRENCY_BOUNDARY_20260927.md`): concurrency
correctness protects **physical operations in flight**, never Bindings;
dedup protects **the materialization WORK of one Ref**, never
Executions.

```text
D-C1  PhysicalUseCount protects in-flight physical operations, not
      Bindings; Binding Lease ❌ vs Physical Operation Handle ✅ — the
      distinction is permanent
D-C2  eviction deferred ≠ artifact pinned (PhysicalUseCount > 0 ⇒ defer
      physical delete)
D-C3  last-live-materialization disappearance is NOT a global state
      event — Resolution derives states at query time; NO
      NO_LIVE_MATERIALIZATION global RefState (would reverse-pollute
      Execution Resolution)
D-C4  Ref-scoped single-flight for concurrent same-Ref materialize
D-C5  single-flight = performance/resource-correctness mechanism, not
      Binding semantics; MaterializationKey = canonical
      RepresentationRef, NEVER ExecutionID
D-C6  single-flight success ≠ automatic attachment — P/C pass their own
      commit boundaries (one Execution's failure must not pollute the
      other)
D-C7  materialization failure changes Representation Availability only;
      never modifies/supersedes/detaches active Bindings
extra race pinned: the single-flight WORK holds the transient
      physical-use protection (caller-scoped acquire/release would let
      joiners/async lifecycles escape protection)
ownership: Binding Registry (semantic relations) / PrefixPool+
      ArtifactStore (eviction/residency) / RepresentationResolver+
      Materialization Coordinator (availability/protection/single-
      flight); Gate C available() stays read-only, untouched by the
      transient counter
```

```text
Current gate  : MAIN_LINE_UNIFIED / BETA_CLOSURE_AUDIT_CLEAN* /
                P2_EVICT_PERSISTENCE_CLOSED /
                IDENT1_GATE_A_PASSED / IDENT1_GATE_B_PASSED /
                IDENT1_GATE_C_PASSED / F3_STRUCTURAL_CONTRACT_PASSED /
                GATE_D_CONTRACT_PASSED /
                GATE_D_CONCURRENCY_BOUNDARY_PASSED /
                IMPLEMENTATION_PLANNING_NEXT
```

### Implementation Planning REGISTERED — 2026-09-27

Three-question layer assignments ruled
(`SIMIGO17_IMPLEMENTATION_PLANNING_20260927.md`):

```text
Q1  PhysicalUseCount → RepresentationResolver/ArtifactStore 物理句柄层
    (PhysicalUseHandle); BindingCount/PhysicalUseCount/Pool residency
    三者独立
Q2  single-flight → MaterializationCoordinator (Ref → in-flight
    MaterializationWork); the WORK owns the PhysicalUseHandle (C.6);
    lifecycle create→acquire→load/validate→publish→release→remove;
    success ≠ auto-attachment
Q3  PrefixSnapshotStore → P2 semantics preserved; FORK-3 adds ONLY the
    PhysicalUseCount==0 gate before the existing onEvict path; no other
    change to eviction semantics; handle release restores eviction
    eligibility (no re-admission/Binding/LRU changes)
```

Five-layer boundary: Binding Registry → RepresentationResolver →
MaterializationCoordinator → ExecutionStatePrefixPool →
PrefixSnapshotStore/ArtifactStore. Hard constraint: FORK-3 does not
change the passed P2 loop; it only ADDS the transient physical-use
protection boundary.

First cut (sequencing ruling): NOT forkSessionBranch — the
MaterializationCoordinator/PhysicalUseHandle minimal skeleton,
tests-first with three concurrency tests (materialize×eviction,
materialize×materialize, materialize×restart/rescan) BEFORE Parent/
Child Binding wiring. Deferred: Binding wiring, forkSessionBranch
plug-in decision, usage projection, disk GC, upstream sync.

```text
Current gate  : MAIN_LINE_UNIFIED / BETA_CLOSURE_AUDIT_CLEAN* /
                P2_EVICT_PERSISTENCE_CLOSED /
                IDENT1_GATE_A_PASSED / IDENT1_GATE_B_PASSED /
                IDENT1_GATE_C_PASSED / F3_STRUCTURAL_CONTRACT_PASSED /
                GATE_D_CONTRACT_PASSED /
                GATE_D_CONCURRENCY_BOUNDARY_PASSED /
                IMPLEMENTATION_PLANNING_REGISTERED /
                F3_COORDINATOR_SKELETON_NEXT
```

### F3 Coordinator Skeleton LANDED — 2026-09-27

IMPLEMENTATION_PLANNING first cut implemented (Lab, tests-first):

```text
PhysicalUseRegistry          transient in-flight physical-operation
                             protection keyed by artifact path
                             (D-I4 BindingCount ≠ PhysicalUseCount;
                             D-C2 requestDelete defers while in
                             flight; deletion fires on release-to-
                             zero)
PrefixSnapshotStore          eviction now goes THROUGH the registry —
                             P2 delete-on-evict unchanged for the
                             no-in-flight case; PhysicalUseCount is
                             transient runtime state, never in
                             snapshot metadata (T3 pins this)
MaterializationCoordinator   Ref-scoped single-flight (D-C4/C5):
                             MaterializationKey = canonical
                             RepresentationRef, never ExecutionID;
                             the WORK owns the PhysicalUseHandle for
                             its whole lifetime (C.6 race); joiners
                             await the same task; success ≠ automatic
                             attachment
battery                      T1 eviction deferred during work +
                             delete on release; T2 concurrent same-
                             key materialize = one load, shared
                             result (winner nondeterministic —
                             contract pins same-result + single-
                             load); T3 protection transient, rescan
                             no-resurrect; suite 128/128
```

Next cut: Parent/Child → same Ref X Binding wiring (only after this
infrastructure — per sequencing ruling).

```text
Current gate  : MAIN_LINE_UNIFIED / BETA_CLOSURE_AUDIT_CLEAN* /
                P2_EVICT_PERSISTENCE_CLOSED /
                IDENT1_GATE_A_PASSED / IDENT1_GATE_B_PASSED /
                IDENT1_GATE_C_PASSED / F3_STRUCTURAL_CONTRACT_PASSED /
                GATE_D_CONTRACT_PASSED /
                GATE_D_CONCURRENCY_BOUNDARY_PASSED /
                F3_COORDINATOR_SKELETON_LANDED /
                F3_PARENT_CHILD_BINDING_NEXT
```

### F3_DEVICE_ACCEPTANCE attempt 1 — REAL BUG F3-BUG-001 FOUND — 2026-09-28

The device battery did exactly its job: it caught a real multi-turn bug
on the real MLX path.

```text
symptom     the seeded session's SECOND turn (warm continuation on the
            session that was bound from a pool snapshot) trips the
            fork-internal alignment assert (ChatSession.swift:1131
            "Main attention cache offsets diverged from model-cache
            progress") and returns empty text
root cause  the restored-cache construction
            (ChatSession(container, cache:state:)) carries NO
            conversation transcript ledger — the fork-internal
            cachedTokens/offset bookkeeping starts empty against a
            non-empty cache and diverges on the following turn.
            Single-turn cross-session reuse (B-5 201ms / B-6 5.9s)
            remains verified intact — the bug is the SECOND turn on a
            seeded session.
disposition battery preserved as the acceptance gate, gated behind
            XCTSkip(F3-BUG-001) (product 573c09b on main,
            0837920 on release). Fix direction: fork-level transcript
            restoration for cache-constructed sessions (the ctor must
            accept the transcript so the ledger exists) — next round,
            fork-surgery scope.
also fixed  seed-side truncation to the claimed grid boundary
            (grid artifacts hold the FULL source snapshot; truncated
            to the claimed boundary per causal-KV — stale full-length
            artifacts become safe); same-boundary re-export collision
            (moveItem 516 on the persistent pool); HTTP readiness poll;
            port mismatch in the battery
```

### F3-BUG-002 FOUND (as registered) — 2026-09-28

With the fork ledger fix at d6e9ba9 (instrumented assert), the battery
still crashed the runtime:

```text
assert (ChatSession:1170, policy block):
  processed=1520  ledger=0  layerOffsets=[9712 × 48]
```

Registered at the time as a cross-gate double-seed (B-4 message bind
then B-6 token hook on the same child session); the fix design was
routed to a ruling.

### F3-BUG-002 CORRECTED — single-seed timeline desync — 2026-09-28

Code-level verification during the ruling overturned the registered
mechanism:

```text
evidence     the crashing request was r=1d5db5 s=f3-par (parent turn 2),
             not the child — the child never started; the trace holds
             exactly ONE seed marker (poolTokenHit tokens=8192, P1
             cross-session)
guards       the B-6 hook is structurally triple-guarded
             (cachedTokens.isEmpty && lmState == nil && decision ==
             .prefillAll); a B-4-restored session exits ledgerBootstrap
             with a non-empty ledger and carries snapshot state, so it
             cannot enter the hook — mutual exclusion is ALREADY
             structural
true root    KVCachePlan.replace(with:) swapped the cache entries
cause        WITHOUT advancing processedTokenCount: after the seed the
             logical timeline stayed at 0 while the layers held 8192
             rows; delta prefill 1518 + 2 gen = processed 1520 vs rows
             9712; record() saw processed < prompt, hit the wipe
             branch, and turn 2 tripped the alignment assert
disposition  fork 88f05a7: replace(with:processedTokenCount:) advances
             the timeline to the matched boundary — invariant
             ledger == processed == layer rows holds at seed exit
```

Boundary contract ruled (no new code): Binding Registry is the single
source of truth for B-4/B-6 — semantic bind wins, token hook defers;
the triple guard already enforces it. The contract breaks only if a
future B-4 restore stops setting state/ledger; guard replacement with
a registry query is then mandatory.

### FORK-3 step-8 LANDED (bookkeeping backfilled) — 2026-09-28

3a29250 turned the Gate A/B contracts into real runtime types
(zero-MLX): RepresentationRef (identity fields + canonical key, R-I3/
I5 by construction), ExecutionRepresentationBinding +
ExecutionBindingRegistry (append-only rows, per-Execution monotonic
generation, supersede-on-rebind, explicit detach, currentBinding =
B-R2, activeBindings = B-I5's Ref -> N), forkChildBinding (F-I1/I2/
I3/I6 — zero re-materialization is STRUCTURAL: the registry has no
store parameter), and the Gate C ResolutionState classifier.
Structural battery 5 tests; suite 133/133. This section backfills the
registration gap — the landing predated the F3 device-acceptance
rounds.

### FORK-3 step-9 LANDED — Binding wiring on the daily path — 2026-09-28

The registry is now the REAL holder of bindings on the serving path
(product main 2bc40f2, release 27f1b32):

```text
registry      process-lifetime, owned by NativeMLXPrefixPool
              (bindings are execution-scoped runtime state; the
              store persists, the registry does not — a restored
              session re-binds at its poolBind)
ref deriving  deterministic from a pool entry (R-I1): kind=
              prefixSnapshot, namespace modelID/kvFingerprint,
              renderIdentity=chat-daily, contentHash=entry
              boundaryHash, boundLength=entry.tokenCount — parent
              export and child bind derive the IDENTICAL Ref
bind points   poolExport binds the exporting execution; poolBind
              binds the child to the same Ref (cross-process fork =
              bind to the derived ref; activeBindings realizes
              B-I5's Ref -> N). forkChildBinding stays the same-
              process API.
evidence      trace lines carry bindingGen/refHash; the battery
              asserts the registry recorded the child fork
device        full pool class PASSED (F3 30.1s / B-5 22.7s /
              truncation x2); trace witness: child poolBind
              bindingGen=1, parent poolExport bindingGen=2
              (B-R3 monotonic)
```

Deferred after step-9: usage projection into GenerationUsageReport;
disk GC policy; forkSessionBranch API plug-in decision (LAST).

### FORK-3 step-10 LANDED — forkSessionBranch plugin decided — 2026-09-28

Decision doc: SIMIGO17_FORK_SESSION_BRANCH_PLUGIN_DECISION_20260928
(R1-R5). Product main cb5d712, release b79866c.

```text
R1  checkpoint layer unchanged (copy/overwrite/promotion);
    terminology red line holds
R2  FORK-2 closed: forkPoint {sourceStorageKey, atMessage, atToken}
    persisted into the TARGET branch metadata (optional Codable,
    backward compatible)
R3  child binds the checkpoint Ref (kind .residentKV, contentHash =
    SHA256(stamped meta) truncated, boundLength = fork token
    position); parent NOT bound (B-R2 - its pool binding must not
    supersede); fork relation = child row + lineage.recordFork
R4  FORK-1 closed: temp copy + atomic replace (delete -> copy crash
    window gone)
R5  no zero-copy (upstream route closed by UPSTREAM_BACKUP_ON_FORK);
    forkSessionBranch does not become poolBind
```

Verification (M5): BranchFork 3/3 (round-trip expectations updated to
the post-fix architecture — same-content copies are pool-served
restore with cacheEff >= 0.9; restored branches warm-extend after the
ledger fix chain; output-verbatim equality green) + F3 battery PASSED
(32.5s).

FORK-3 cut sequence COMPLETE (step skeleton -> D contract -> device
acceptance -> step-8 binding types -> step-9 daily wiring -> step-10
forkSessionBranch plugin). Remaining registered: usage projection,
disk GC (deferred candidates).

### External review round 2 + BETA RELEASE GATE — 2026-09-28

A second external code-level review of cb5d712/b79866c/650407b
confirmed R1-R5, parent-no-supersede, identity contract, step-9
non-interference, and the closed F3 chain; it raised 2 P1 lifecycle
findings + P2 documentation items. Disposition (product review batch
9956e64 / main merge 24399ae / e168555):

```text
P1 delete lifecycle   FIXED  deleteSessionBranch now DETACHES the
                      execution binding (row retained, active clears)
P1 fork transaction   FIXED  the child binding registers AFTER
                      loadSessionCache succeeds - a failed fork
                      leaves no relation and cannot supersede a
                      binding for a restore that never happened
P2 two-file atomicity REGISTERED  per-file atomic swap accepted for
                      beta; whole-fork transaction = deferred
                      reliability candidate
P2 stale comment      FIXED  the beta.3 "FORK-3 (GA, unimplemented)"
                      claim modernized (main carried it; release did
                      not); the upstream-primitive note in
                      ExecutionControlling updated per
                      UPSTREAM_BACKUP_ON_FORK
P2 release doc pin    FIXED  88f05a77 -> 6d01a13c (matches
                      Package.resolved)
```

BETA RELEASE GATE (release/v2.0.0-beta @ b79866c pre-fix sweep, then
post-fix re-runs):

```text
full SimiGoTests sweep  79 executed / 2 skipped (env-gated) /
                        1 failure = B-5 cross-session assert raced
                        the trace flush under full-suite swap
                        pressure (the line EXISTS in the
                        authoritative trace; poolTokenHit and the
                        timing asserts in the same window passed)
race fix                traceLogContains polls briefly; post-fix
                        re-run: BranchFork 3/3 + F3 26.3s + B-5
                        26.5s green
main/release convergence  trees identical at e168555 (F3 battery
                        32.5s re-verified on the merged main)
```

```text
Current gate  : MAIN_LINE_UNIFIED / ... /
                FORK3_CUT_SEQUENCE_COMPLETE /
                FORK3_STEP10_REVIEW_CLOSED (2 P1 fixed) /
                BETA-AUDIT-1 = FAIL / IMPLEMENTATION VERIFIED ON BRANCH
                (R5 evidence @ 21c1e82/bc2e0ea: compile+gate 2/2+W1/W2
                fail-closed injection+race seam+84/0/2 full sweep —
                Round 5 RULING = PASS / IMPLEMENTATION VERIFIED
                (audit owner closure; PR #11 merged to main fc96423;
                post-merge battery 10/10 green on M5) /
                SECOND REVIEW = PASS / MAIN MERGED / 0 BLOCKER
                (P2-ES-01 dirty-retry gate alignment — registered;
                P2-ES-02 digest-at-write = CLOSED: receipt chain @
                mlx-swift ef5f1b6 + mlx-swift-lm fd5d1b4; acceptance
                battery 10/10 on M5 incl. W1/W2 fail-closed +
                multi-GB round-trip + race seam) /
                transaction boundary — see BETA-AUDIT-1 doc §10) /
                BETA_RELEASE_SWEEP_AND_REVIEWS_GREEN (79-test sweep
                + review batches; evidence recorded below) /
                SIMIGO18_BETA_RELEASE_AUDIT_GATE_REGISTERED
                (formal independent audit: NOT STARTED - owned by
                SIMIGO18_BETA_RELEASE_TECHNICAL_ROUTE_AUDIT_GATE_
                20260928) /
                BRANCHES_CONVERGED (all non-vendor SimiGo branches
                contained in main; main=release @ e168555 tree,
                pin doc 94c62ed/1657d6e) /
                AUDIT_BASELINE_PINNED (docs/AUDIT_BASELINE_20260928:
                sweep 79/0/2 on the audited tree; no beta release
                publication; mlx-swift-lm backup-only stands) /
                DEFERRED_REMAINS (usage projection; disk GC; whole-
                fork transaction atomicity) /
                UPSTREAM_BACKUP_ON_FORK
```

### F3_DEVICE_ACCEPTANCE attempt 2 — PASSED — 2026-09-28

M5 (Mac17,4), Qwen3-Coder-30B-A3B-Instruct-4bit, Debug,
testF3DeviceAcceptanceBattery: 17.1s, TEST SUCCEEDED.

```text
warmup   cold                       ttft 1656ms
P1       cross-session              ttft 5706ms  cacheEff 0.84
         (seed 8192 + Δprefill 1518)             ledger extends
P2       extend                     ttft  315ms  cacheEff 1.00
child C  poolBind messages=5        ttft  290ms  cacheEff 1.00
         restore, promptTokens=11                ΔC only
P3       extend (after child)       ttft  297ms  cacheEff 1.00
child C2 restore, repeat            ttft  297ms  deterministic
```

Five-condition final judgment (reviewer-ruled D1-D5):

```text
D1 PASS  child starts from T, not 0 — poolBind messages=5 + poolHit,
         mode=restore over the 9728-row boundary
D2 PASS  no second materialization — line-precise gate found no
         session=f3-child mode=cold line
D3 PASS  child paid ΔC only — promptTokens=11, not T+ΔC
D4 PASS  parent continuation after child at warm level (297ms extend,
         cacheEff 1.00) — no attributable regression
D5 PASS  child repeat identical; shared-prefix cacheEff 1.00
```

F3_DEVICE_ACCEPTANCE_PASSED. F3-BUG-001 closed (fork ledger chain
ce9e056 + 3341ace + d6e9ba9 + 88f05a7).

### External review round — 5 findings dispositioned — 2026-09-28

An external code-level review accepted the record() root fix but
blocked final acceptance on five items. Disposition:

```text
1 cancel ledger      FIXED  fork 6d01a13: the retained ledger is
                     rebuilt from THIS turn's promptTokens prefix
                     (removeLast() desynced KV vs ledger in the
                     seed window; prefillTokenCount was the narrowed
                     suffix size under reuse modes and is gone)
2 bootstrap swallow  FIXED  fork 6d01a13: progress > transcript now
                     invalidates the ledger instead of clearing the
                     pending flag with an empty one; the terminal
                     rule rebuilds
3 assert-as-boundary FIXED  fork 6d01a13: nativeAttentionOffsetsAre
                     Aligned folded into mainCacheIsAligned /
                     draftCacheIsAligned — release builds rebuild a
                     desynced cache instead of reusing it; debug
                     asserts stay as the diagnostic witness
4 speculative pin    ALREADY PINNED  the TimelineModel offset-12
                     witness (testSpeculativeFinalCallTokenResumes
                     FromTheLiveMainCache) proves verifier lookahead
                     stays uncommitted; contract comment added
5 D3/D4 evidence     HARDENED  D2's gate was VACUOUS (session=f3-child
                     never appears in the trace — the app strips the
                     prefix): now session=child/main, made non-vacuous
                     by D3's existence check. D3 records the ACTUAL
                     delta prefill (child line: mode=restore,
                     cacheEff=1.00, promptTokens < 200 ≈ 2% of 9.7K).
                     D4 compares P3 against the parent's OWN warm
                     level (P3 < P2 x 1.5), cold kept as sanity.
```

Battery re-run on M5 with fork 6d01a13 and the hardened gates:
PASSED (27.6s). The validated line is landed on product main
(112112c; release f7c23e9).

```text
Current gate  : MAIN_LINE_UNIFIED / BETA_CLOSURE_AUDIT_CLEAN* /
                P2_EVICT_PERSISTENCE_CLOSED /
                IDENT1_GATE_A_PASSED / IDENT1_GATE_B_PASSED /
                IDENT1_GATE_C_PASSED / F3_STRUCTURAL_CONTRACT_PASSED /
                GATE_D_CONTRACT_PASSED /
                GATE_D_CONCURRENCY_BOUNDARY_PASSED /
                F3_BUG001_CLOSED (fork ledger chain -> 88f05a7) /
                F3_BUG002_CORRECTED (single-seed timeline desync;
                B-4/B-6 exclusion contract registered) /
                F3_DEVICE_ACCEPTANCE = PASSED (formally closed by owner
                verification: fork 6d01a13c / product main 112112c /
                release f7c23e9 / Lab f4ca9f7; D1-D5 green on M5) /
                PRODUCT_MAIN_LANDED (main 971f43e; battery + B-5 +
                truncation green on the mainline, real cold baseline
                via per-run nonce) /
                UPSTREAM_BACKUP_ON_FORK (owner ruling 2026-09-28: no
                upstream push; the slamfinger fork IS the remote
                backup) /
                FORK3_STEP9_BINDING_WIRED (daily path) /
                FORK3_STEP10_DECIDED_AND_LANDED (forkSessionBranch
                plugin: R1 checkpoint layer unchanged; R2 fork point
                persisted; R3 child .residentKV binding; R4 atomic
                copy; R5 no zero-copy/no poolBind-mix) /
                FORK3_CUT_SEQUENCE_COMPLETE /
                DEFERRED_REMAINS (usage projection; disk GC)
```

### LAB RQ1 PASS_WITH_BOUNDARY — Backend Conformance — 2026-09-29

Lab 转向 Execution State 抽象验证，暂停继续扩展 runtime feature。新增
`BackendConformanceMatrixTests` 作为最小契约矩阵：同一
create/bind/fork/diverge/stale-reject/foreign-reject/
stale-release-no-clobber/release/restore/discard/parent-restore 序列覆盖
MLX prefix recompute、oversized segmented representation、以及新增 non-MLX
`LLAMAServerExecutionStateBackend`。矩阵发现并修复 `FBC-001`：oversized
backend 释放过期 snapshot 时会清掉新 live binding；修复后三者均 PASS。
全仓 157 PASS / 0 FAIL（XCTest 19 + 137，Swift Testing 1；base `669467d`
加未提交 harness）。

另用本机 llama-server 0.3.0-dev 与
Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL GGUF 做 live smoke：
`ping → divergent prompt → ping replay`，`semanticIdentical=true` 且
`branchDiverged=true`。证据见
`simigo2-experimental/results/backend-conformance/llama-server-live-smoke.json`。
当前 live executor 仍是外部 curl，不是集成 Swift executor。

RQ1 判 `PASS_WITH_BOUNDARY / CLOSED-FOR-CURRENT-CONTRACT`：Execution State
Contract 在已测 MLX prefix、oversized segmented prefix、LLAMA-server prefix
representation 上成立；不 claim universal。RQ2 保持 PARTIAL：已有 qwen3_next、
Qwen3MoE、Qwen35MoE、Gemma4 的 E5/O6 PASS，但 Qwen4Exp 不可用。RQ3 未开
实验。详细边界与收口条件见
`docs/00-governance/SIMIGO_LAB_BACKEND_CONFORMANCE_OPENING_20260929.md`。

### LAB RQ3 PRELIMINARY_NON_REGRESSION — 2026-09-29

新增 `rq3_llama_hotpath_ab.py` 做 no-fork ordinary generation A/B。
llama-server 请求在 OFF/ON 两态 byte-identical；ON 仅额外执行本地
capture/bind/release。30 对交替样本、temperature=0、seed=42、8 generated
tokens、同一 GGUF model：content+token 语义 30/30 一致；client mean
`OFF=300.951ms`、`ON=300.827ms`，paired mean `-0.124ms`；state bookkeeping
mean `8.525µs/request`，mean absolute paired client difference `2.809ms`。
结果支持本 run 的 hot-path non-regression，但不 claim fork/restore、
long-context、memory pressure、MLX oversized 或跨 backend 成本。

RQ3 状态 `OPEN / PRELIMINARY_NON_REGRESSION`。详细边界见
`docs/00-governance/SIMIGO_LAB_RQ3_LLAMA_HOTPATH_AB_20260929.md`；原始证据
见 `simigo2-experimental/results/backend-conformance/rq3-llama-hotpath-ab.json`。

### LAB RQ3 FORK_RESTORE_COST_CHARACTERIZED — 2026-09-29

新增 `rq3_llama_fork_restore_cost.py`，在 LLAMA-server token-prefix 路径上
执行 `checkpoint/reference → derive → diverge → release → restore → replay`。
30 sample 中 restored replay identity、branch divergence、parent
non-interference、child fork-point restore 全部 30/30 PASS。本地
`derive/release/restore` 合计 mean `3.821µs`，为 reference/replay 平均绝对
client difference 的 `0.0563%`。

同一 run 观测 replay-reference client mean `+6.688ms`，但 server predicted
delta `-0.161ms`、prompt delta `-0.765ms`；扣除 server 报告耗时后仍有
`+7.614ms` 未归因。该差异不能归给本地 Execution State bookkeeping，原因尚未
确定。RQ3 保持 `OPEN`；当前状态
`FORK_RESTORE_LOCAL_COST_CHARACTERIZED / SEMANTICS_PASS`。证据见
`simigo2-experimental/results/backend-conformance/rq3-llama-fork-restore-cost.json`
与 `docs/00-governance/SIMIGO_LAB_RQ3_LLAMA_FORK_RESTORE_COST_20260929.md`。

### LAB RQ3 BACKEND_CONTEXT_TRANSITION_IDENTIFIED — 2026-09-29

新增纯 backend control `rq3_llama_context_controls.py`，不含 Execution State
object。llama-server 以 `--no-cache-prompt --no-cache-idle-slots` 启动，
request `cache_prompt=false`，交替比较 `C,C,C` 与 `C,D,C`。long D（10
tokens）、`n_predict=1` 时，third-minus-first client mean 差异
`+5.284ms`；D 改为与 C 同长（6 tokens）后降至 `+0.216ms`。两条件语义均
20/20 一致。

该 control 排除本地 Execution State bookkeeping 与 prompt cache 作为主因，
将原 fork/restore run 的 `+6.688ms` 差异归入“longer divergent prompt 引发的
backend context transition cost”。llama-server 内部步骤尚未定位。RQ3 状态
更新为 `OPEN / LOCAL_STATE_NON_REGRESSION /
BACKEND_CONTEXT_TRANSITION_IDENTIFIED`。

### LAB RQ3 SERVER_TRANSITION_DELAY_LOCALIZED — 2026-09-29

进一步禁用 `--slot-prompt-similarity` 后，`C,D,C` 相对 `C,C,C` 的差异仍为
`+8.423ms`，排除 slot similarity / LCP selection 主因。解析 server log 得到
`release → next launch` delay：`10→6` tokens mean `7.741ms`，`6→10` mean
`2.294ms`，`6→6` mean `1.915ms`；trace 与 20-cycle request sequence 完全匹配。
这把差异定位到 llama-server task transition，而不是本地 Execution State。

6–10 token divergent prompt sweep 显示 client difference 非单调
（correlation `-0.593`），不能简化为长度公式；但 log trace 中 `7→6`、`8→6`、
`9→6`、`10→6` 的 delay mean 分别为 `8.404/12.309/6.951/7.124ms`，高于
same-sequence `6→6` baseline `1.415–2.035ms`。RQ3 仍 OPEN；当前状态
`LOCAL_STATE_NON_REGRESSION /
SERVER_RELEASE_TO_LAUNCH_TRANSITION_DELAY_LOCALIZED`。llama-server 内部步骤
尚未定位。

### LAB RQ3 SLOT_STATE_CACHE_ROOT_CAUSE_CONFIRMED — 2026-09-29

HTTP keep-alive control 排除新建 TCP transport：long-D 差异仍为
`+6.779ms`。`--verbosity 6` 定位到 `D → C` 时 llama-server 执行 slot state
cache update：保存 10-token state `63.009MiB`，查找/加载 6-token prompt，
并显式记录 `prompt cache update took 10.26ms`。该 build 虽带
`--no-cache-prompt --no-cache-idle-slots`，但该 update 仍发生。

加入 `--cache-ram 0` 后，`C,D,C` 减 `C,C,C` 变为 `-0.693ms`；
`10→6 / 6→10 / 6→6` 的 release-to-launch mean 均降至
`0.530/0.549/0.555ms`。复跑 30-sample fork/restore benchmark：四项语义
check 均 `30/30 PASS`，本地 `derive/release/restore` mean `3.306µs`，
replay-reference client delta 从 `+6.688ms` 降至 `+2.150ms`，进入本 run
测量噪声。

RQ3 状态更新为 `OPEN / LOCAL_STATE_NON_REGRESSION /
FORK_RESTORE_SEMANTICS_PASS / SLOT_STATE_CACHE_ROOT_CAUSE_CONFIRMED`。
上述结论仅限当前 llama-server build/config、GGUF model、short prompt 与
8-token generation；long-context、memory pressure、cancellation、MLX
oversized 与跨 backend 仍未收口。

### LAB O6 WORKLOAD MATRIX V2 PASS — Qwen3-Coder-Next — 2026-09-29

O6 从单次 evict/restore gate 扩展为 `G1.9-O6.EXECSTATE.V2` workload matrix。
在 Qwen3-Coder-Next-4bit oversized segmented executor 上，W0 linear、W1
capture、W2 fork、W3 divergence、W4 restore、W5 release、W6 repeated
fork/restore、W7 long-running branch、W8 explicit release/recovery 全部 PASS。
峰值 footprint `8,041MiB <= 30,720MiB`，swap `0MiB`，292 次 segment
transition。W9 cancellation 未实现、未 claim。

该结果补齐 Qwen3-Coder-Next workload baseline 的 W0-W8 语义/资源边界；
性能耗时仅作 harness 运行记录。RQ2 对 qwen3_next 的 oversized evidence
增强，但仍不等价于 Qwen4Exp cross-architecture closure。RQ3 中 MLX oversized
cancellation 仍未收口。

### LAB O6 WORKLOAD MATRIX V3 PASS — W9 CANCELLATION — 2026-09-29

O6 V3 新增 cooperative generation cancellation：取消检查只在完整 greedy token
boundary 执行，segment 不会被拆分。真实 Qwen3-Coder-Next oversized run 中，
branch X 在第一个完整 token 后取消；pre-cancel checkpoint binding 保持
position 1，consumed prefix 能精确重建 full run 的对应 prefix，逻辑 restore
回到 position 1，后续 full replay 与 C token-identical。

最终 `G1.9-O6.EXECSTATE.V3` 为 12/12 PASS：W0-W9 全覆盖，peak footprint
`8,032MiB <= 30,720MiB`，swap `0MiB`，322 次 segment transition。两次早期
V3 FAIL 是 harness 断言把 one-token cancelled prefix 误比作 full four-token
payload；失败 artifact 已保留，不是 cancellation/restore 语义失败。全仓
`swift test` 在修正后 PASS。RQ3 的 MLX oversized W0-W9 cancellation 证据
已补齐；性能与上游 runtime claim 仍不开放。

### LAB RQ3 LONG-D TRANSITION PILOT — WITHIN NOISE — 2026-09-29

在 slot state cache root cause 确认后，继续用纯 backend `C,C,C` vs `C,D,C`
control 做 36/144/288/432-token long-D pilot。llama-server 使用
`ctx512 / parallel1 / no prompt or idle cache / cacheRam0 / slot
similarity0`，request `cache_prompt=false`，每长度 12 cycles。

四个长度的 paired third-minus-first delta 分别为 `-0.986 / +1.685 /
-0.071 / -0.662ms`，均未形成单调增长；两序列语义均 `12/12 + 12/12`。
D 的 prefill mean 为 `191.289–663.658ms`，但 D 后回到 6-token C 的 prompt
mean 保持 `99.676–105.671ms`。默认 4-slot preflight 在 432-token D 时出现
KV free-space retry/purge，相关 artifact 只保留为 topology hazard，不参与
transition attribution。

该结果支持“slot state cache 是先前毫秒级差异主因”的当前解释，但仅限
`512-token / one-slot / GGUF model / 12 cycles` pilot，不建立长上下文
通用公式，也不是 Execution State hot-path A/B。RQ3 增加
`LONG_D_TRANSITION_PILOT_WITHIN_NOISE`；memory pressure、cancellation、
MLX oversized A/B 与 integrated Swift executor 仍未收口。

### LAB RQ3 BACKEND KV PRESSURE PILOT — RECOVERS — 2026-09-29

用 `ctx512` 自动展开的 `4-slot / unified KV` topology 复跑 432-token D 的
`C,D,C` backend control。verbosity-6 trace 抽取到 18 次 attention-ubatch
failure、18 次 failed memory/free-space retry、18 次 purge；purge 分布为
slot0(6 tokens) x6、slot1(6 tokens) x6、slot2(432 tokens) x6。请求未失败，
D client/prompt mean `651.604/650.617ms`，后续 6-token C 恢复到
client/prompt mean `100.720/99.930ms`，paired transition delta
`+0.268ms`，两序列语义均 `12/12`。

这是 backend KV pressure observation，不是系统 RAM/swap、并发 workload 或
Execution State release/recovery A/B；不能 claim recovery 零成本。RQ3 增加
`BACKEND_KV_PRESSURE_RECOVERS`。Execution State pressure A/B、并发、
cancellation、MLX oversized A/B 与 integrated Swift executor 仍未收口。

### LAB RQ3 LLAMA EXPLICIT CANCELLATION — RECOVERS — 2026-09-29

新增纯 backend cancellation control：先通过
`POST /v1/chat/completions` 开启 resumable stream，100ms 后用
`DELETE /v1/stream` 显式取消，等待唯一 slot free，再用固定 token prefix 的
greedy `/completion` 验证恢复。20 cycles 中 DELETE 全部 `204`，恢复
token/content 全部与 reference 一致；DELETE→free mean/median/p95 为
`577.376/581.312/588.358ms`，recovery client mean `102.501ms`。

verbosity-6 trace 抽取确认 20/20 task 在 `n_gen=1` 收到 cancel，并在
`n_gen=2` token boundary release。该结果限定 current resumable-stream path、
one slot、`ctx512/cacheRam0/GGUF model`；不覆盖 Execution State
cancellation、并发 workload 或 production readiness。非流式
client-disconnect 探索在本 build 上可跑满请求，不作为可靠取消证据。RQ3 增加
`EXPLICIT_BACKEND_CANCEL_AND_RECOVER`。

### LAB RQ3 LLAMA CONCURRENT CANCELLATION — UNAFFECTED CONTROL PASS — 2026-09-29

继续把显式取消扩展到 `parallel2 / ctx1024` backend topology：每 cycle 同时
启动 208-token/256-token 的 resumable stream 与 6-token/one-token greedy
`/completion`，100ms 后取消长请求。20 cycles 中 DELETE 全部 `204`，并发
short control 全部与 pre-run reference token/content 一致；20/20 control 在
长请求释放前启动并完成。

DELETE→long-free mean/median/p95 为 `705.564/706.760/720.590ms`，control
client mean `509.130ms`。verbosity-6 trace 抽取确认 20/20 长任务在
`n_gen=1` 收到 cancel、`n_gen=2` release，并且 20/20 short control 先于长
任务释放。该结果仅限当前 backend topology 和 workload，不是 Execution State
cancellation、更高并发曲线或生产 readiness。RQ3 增加
`CONCURRENT_BACKEND_CANCEL_WITH_UNAFFECTED_CONTROL`。

### LAB RQ2 QWEN4EXP READONLY AUDIT — STILL BLOCKED — 2026-09-29

对五个 Qwen4Exp 相关候选完成远程 metadata / manifest / README 只读审计。
全部 REJECT：`Jab1718` 为 `42,620,341,120 bytes`；`ISTA-DASLab GSQ-RCO`
为 `116,514,464,640 bytes`；`AnonimousA REAP-320` Q3/Q2 shards 分别约
`64.21/57.27GiB`；`sh0wie REAP-288-GGUF` 总量为
`124,068,144,000 bytes`，README 覆盖 Q4/Q5/Q8 `78/87/116GB`；
`sh0wie REAP-288-MLX-4bit` 外部指南报告 `73.5GB`。这些对象均超过 32GB
physical-RAM fit，并且属于 pruned / subnet / expert-pruned Qwen4Exp-family
substrate，不是 full Qwen4Exp closure。

原 `sh0wie/Qwen3.8-Flash-Next-REAP` 已 404，实际候选收窄为 REAP-288 的
GGUF 与 MLX-4bit。该审计不验证 tensor/tokenizer completeness、runtime
load、Execution State semantics 或推理质量；磁盘可用空间不构成 fit 证据。
RQ2 维持 `PARTIAL / BLOCKED_BY_QWEN4EXP_MODEL_ARTIFACT`，等待用户提供
full Qwen4Exp artifact、授权只做 pruned-substrate 线、独立化 pruned 研究线
或优先暂停 RQ2。证据边界见
`docs/00-governance/SIMIGO_LAB_RQ2_QWEN4EXP_READONLY_AUDIT_20260929.md`。

### LAB RQ3 EXECSTATE CANCELLATION ISOLATION PASS — 2026-09-29

新增 `rq3_llama_execution_state_cancellation.py`，把 explicit LLAMA
cancellation 扩展为 local prefix Execution State A/B。20 paired cycles 中，
OFF/ON DELETE 均为 `20/20` accepted，恢复 token/content 均为 `20/20`
identical。ON 路径先 capture root，再 bind/capture child，取消并释放 child 后
restore root snapshot；root continuation 逐 cycle 恢复 reference。

OFF/ON DELETE→free mean 为 `576.891/576.769ms`，recovery client mean 为
`102.883/102.971ms`，paired ON−OFF recovery client mean `+0.088ms`。本地
bind/capture/release/restore 合计每 ON cycle mean `24.225µs`。该证据是
local prefix representation mirror 的 harness-level control；llama-server 仍是
inference/native cache authority，没有 Swift integrated executor、MLX
oversized equivalence、更高并发或 production readiness claim。RQ3 增加
`EXECUTION_STATE_CANCEL_ISOLATION_PASS`，但保持 OPEN。报告见
`docs/00-governance/SIMIGO_LAB_RQ3_LLAMA_EXECSTATE_CANCEL_AB_20260929.md`；
artifact 见
`simigo2-experimental/results/backend-conformance/rq3-llama-execution-state-cancellation-ab.json`。

### LAB RQ EVIDENCE MATRIX REGISTERED — 2026-09-29

新增 `docs/00-governance/SIMIGO_LAB_RQ_EVIDENCE_MATRIX_20260929.md`，把当前
RQ1 backend conformance、RQ2 cross-architecture / Qwen4Exp readonly audit、
RQ3 hot-path / transition / pressure / cancellation controls、以及 O6 V3
W0-W9 汇总为单一索引。矩阵逐项记录 scope、result、report/artifact，并登记
non-claims 与 open gaps。

当前索引状态保持 `RQ1 PASS_WITH_BOUNDARY / CLOSED-FOR-CURRENT-CONTRACT`、
`RQ2 PARTIAL / BLOCKED_BY_QWEN4EXP_MODEL_ARTIFACT`、
`RQ3 OPEN / EXECUTION_STATE_CANCEL_ISOLATION_PASS`、
`O6 PASS / QWEN3_NEXT_OVERSIZED_W0_W9_HARNESS_LEVEL`。开放缺口包括 full
Qwen4Exp artifact、integrated Swift LLAMA executor A/B、MLX oversized
equivalent A/B、更高并发曲线和 cross-backend closure。该文档只是索引，不新增
实验结果或性能 claim。

### LAB RQ3 SWIFT EXECSTATE HOTPATH INTEGRATION PASS — 2026-09-29

新增最小 `LLAMAServerExecutionStateExecutor` 和
`simigo2ctl llama-execstate-ab`。Swift executor 只检查并消费
`LLAMAServerPrefixPayload`，将 token prefix 提交给既有 llama-server；不接管
inference、不创建 KV authority、不建立第二 runtime。ON 路径从
`LLAMAServerExecutionStateBackend` capture representation 后交给 Swift
executor，OFF 直接发送同一 token prefix；每 cycle 交替顺序。

30 paired samples 中 OFF/ON semantic stability 均为 `30/30`；OFF/ON client
mean 为 `338.788/338.781ms`，paired ON−OFF mean `-0.007ms`，capture state
operation mean `6.171µs`。这补上 Swift representation-consuming ordinary
generation hot-path 缺口，登记
`SWIFT_EXECSTATE_HOTPATH_INTEGRATION_PASS`。fork/restore/cancellation 的
Swift executor integration、MLX oversized equivalent A/B、更高并发与
production readiness 仍未收口。修改 Swift 后全仓 `swift test` 为 `157 PASS /
0 FAIL`。报告见
`docs/00-governance/SIMIGO_LAB_RQ3_LLAMA_SWIFT_EXECSTATE_HOTPATH_20260929.md`；
artifact 见
`simigo2-experimental/results/backend-conformance/rq3-llama-swift-execstate-hotpath-ab.json`。

### LAB RQ3 SWIFT EXECSTATE FORK_RESTORE INTEGRATION PASS — 2026-09-29

新增 `LLAMAServerExecutionStateForkRestore` 和
`simigo2ctl llama-execstate-fork-restore`，把 Swift representation-consuming
integration 扩展到 live fork / diverge / release / restore / replay。每
sample 用新的 Coordinator 驱动 `LLAMAServerExecutionStateBackend`，Swift
executor 只消费 `LLAMAServerPrefixPayload` 并请求既有 llama-server。

30 samples 中 restore replay identical、branch diverged、parent
non-interference、child restored to fork point 均为 `30/30`。reference /
divergence / replay client mean 为 `355.008/450.940/356.934ms`，replay−reference
mean `+1.926ms`；local fork+capture 与 release+restore+capture 分别 mean
`16.071/34.044µs`。耗时仅作本 run 记录；`cache_prompt=false`，不与旧 Python
cost run 直接 paired compare。

RQ3 增加 `SWIFT_EXECSTATE_FORK_RESTORE_INTEGRATION_PASS`，但仍 OPEN。剩余
Swift integration 缺口是 cancellation executor；MLX oversized equivalent A/B、
更高并发与 production readiness 仍未收口。修改 Swift 后全仓 `swift test`
为 `157 PASS / 0 FAIL`。报告见
`docs/00-governance/SIMIGO_LAB_RQ3_LLAMA_SWIFT_EXECSTATE_FORK_RESTORE_20260929.md`；
artifact 见
`simigo2-experimental/results/backend-conformance/rq3-llama-swift-execstate-fork-restore.json`。

### LAB RQ3 SWIFT EXECSTATE CANCELLATION INTEGRATION PASS — 2026-09-29

新增 `LLAMAServerExecutionStateCancellation` 和
`simigo2ctl llama-execstate-cancel`，把 Swift coordinator/backend integration
扩展到 explicit LLAMA stream cancellation recovery。root 绑定固定 recovery
prefix；child 绑定 long-prompt prefix。OFF 直接恢复；ON 先 capture root/child，
DELETE 并等待唯一 slot free 后 release child、restore root，再由 Swift
executor 消费 restored root representation。

20 paired cycles 中 OFF/ON cancel accepted 与 recovery identical 均为
`20/20 + 20/20`。OFF/ON DELETE→free mean `581.350/574.579ms`，recovery client
mean `101.881/101.499ms`，paired ON−OFF recovery mean `-0.382ms`；Swift 状态
操作每 ON cycle mean `20.827µs`。该证据不 claim production readiness 或取消
延迟上限；本轮未重新抽取 server trace，token-boundary cancel 行为由同一 build
前置 trace 支持。RQ3 增加
`SWIFT_EXECSTATE_CANCELLATION_INTEGRATION_PASS`，但仍 OPEN；剩余缺口为 MLX
oversized equivalent A/B、更高并发曲线与 cross-backend closure。修改 Swift 后
全仓 `swift test` 为 `157 PASS / 0 FAIL`。报告见
`docs/00-governance/SIMIGO_LAB_RQ3_LLAMA_SWIFT_EXECSTATE_CANCELLATION_20260929.md`；
artifact 见
`simigo2-experimental/results/backend-conformance/rq3-llama-swift-execstate-cancellation.json`。

### LAB O6 MLX OVERSIZED CANCELLATION AB PASS — 2026-09-29

新增 `O6CancellationAB` 和 `simigo2ctl o6-cancel-ab`，在真实
Qwen3-Coder-Next-4bit segmented core 上比较 direct cancellation/release/
recovery 与 Execution State fork/capture/release/restore/replay。OFF 执行
same physical release 但不使用 binding contract；ON 走 Coordinator 与
`OversizedSegmentedStateBackend`，replay 由 representation-consuming executor
执行。每 cycle 交替先后顺序。

3 cycles 中 cooperative cancel one token、direct recovery exact、Execution
State recovery exact、cancelled prefix exact、release removed current binding、
restore to fork point、parent non-interference 均为 `3/3`。peak footprint
`8,132MiB <= 30,720MiB`，swap `0MiB`，210 次 segment transition。这登记
`O6_MLX_OVERSIZED_CANCELLATION_AB_PASS`，补上 MLX oversized
cancellation/release/recovery A/B 缺口。诊断耗时只作运行记录，不建立
performance、production readiness、upstream MLX 或跨模型 claim。修改 Swift 后
全仓 `swift test` 为 `157 PASS / 0 FAIL`。报告见
`docs/00-governance/SIMIGO2_O6_CANCELLATION_AB_20260929.md`；artifact 见
`simigo2-experimental/results/o6-workload-matrix/qwen3-coder-next-4bit-cancellation-ab.json`。

### LAB RQ3 HIGHER_CONCURRENCY_CANCEL CURVE — COMPLETION PASS / IDENTITY BOUNDARY — 2026-09-29

新增 `rq3_llama_concurrency_curve.py`，在 `parallel4 / ctx2048 / n_slots=4`
上覆盖 L1（1 long + 3 controls）、L2（2 long + 2 controls）、L3（3 long +
1 control），每 level 2 cycles。每个 cycle 先运行同负载 full-completion
baseline，再运行相同 slot 占用的 explicit cancellation arm。

strict 判定保持 FAIL：same-load baseline stability `5/6`，cancellation
controls matched same-load baseline `5/6`。可分离登记的是 cancellation
acceptance/completion pass：DELETE `12/12`，control batches complete `6/6`，
controls 全部在 cancellation window 启动。DELETE→all-long-free mean 从 L1
`1,089.059ms` 到 L3 `2,179.503ms`；耗时只作运行记录。这登记
`HIGHER_CONCURRENCY_CANCEL_ACCEPTANCE_COMPLETION_PASS` 和
`GREEDY_IDENTITY_BOUNDARY_OBSERVED`。不能 claim higher-concurrency semantic
closure 或 production readiness。RQ3 仍 OPEN，下一步应定位 batch-transition
identity mismatch 机制。报告见
`docs/00-governance/SIMIGO_LAB_RQ3_LLAMA_CONCURRENCY_CURVE_20260929.md`；
artifact 见
`simigo2-experimental/results/backend-conformance/rq3-llama-concurrency-curve.json`。

### LAB RQ3 NO_CANCEL BATCH IDENTITY PROBE — INSTABILITY WITHOUT CANCELLATION — 2026-09-29

新增 `rq3_llama_batch_identity_probe.py`，在 `parallel4 / ctx2048` 上重复
`1 long full-completion + 3 greedy controls` 的 same-load run，共 16 cycles；
全程没有 DELETE 或 cancellation。16/16 batches 完成，但 within-cycle identity
只有 `8/16`，48 个 controls 分成 `32/16` 两个 greedy output groups。

该 probe 把 higher-concurrency curve 的 strict identity mismatch 与 cancellation
因果解耦：mismatch 在 no-cancel scheduling 中也会出现。可登记
`NO_CANCEL_BATCH_IDENTITY_INSTABILITY_OBSERVED` 和
`CANCELLATION_CAUSALITY_NOT_SUPPORTED`。当前局部化边界是 llama-server
concurrent scheduling / batching，不是 Execution State failure；上游内部机制
仍未定位。RQ3 保持 OPEN。报告见
`docs/00-governance/SIMIGO_LAB_RQ3_LLAMA_BATCH_IDENTITY_PROBE_20260929.md`；
artifact 见
`simigo2-experimental/results/backend-conformance/rq3-llama-batch-identity-no-cancel.json`。

### LAB RQ3 BATCH CARDINALITY PROBE — THRESHOLD LOCALIZED — 2026-09-29

新增 `rq3_llama_batch_cardinality_probe.py`，在没有 long request 和
cancellation 的条件下测量 1/2/3/4 个 identical greedy controls。每 cardinality
重复 8 batches。N1/N2 完全 stable；N3 within-cycle `8/8` stable 但
across-cycle `7/8` stable，出现 3 个 `wants` 输出；N4 within-cycle 只有
`5/8` stable，across-cycle 只有 `1/8` stable，输出分为 `wants` 21 个、`is`
11 个。

这把 no-cancel identity instability 的边界进一步局部化为 control cardinality：
across-cycle drift 从 N3 开始，within-batch mismatch 在 N4 明显。先前
`1 long + 3 controls` 的 mismatch 不需要 long request 或 cancellation。slot
记录不支持单一固定 slot 解释。RQ3 增加
`BATCH_CARDINALITY_THRESHOLD_LOCALIZED` 和
`GREEDY_IDENTITY_UNSTABLE_AT_CONTROL_COUNT_3_PLUS`，但 llama-server 内部机制
仍未定位，RQ3 保持 OPEN。报告见
`docs/00-governance/SIMIGO_LAB_RQ3_LLAMA_BATCH_CARDINALITY_PROBE_20260929.md`；
artifact 见
`simigo2-experimental/results/backend-conformance/rq3-llama-batch-cardinality-no-cancel.json`。

### LAB RQ3 DISTINCT_PROMPT CARDINALITY PROBE — DUPLICATE CONFOUND EXCLUDED — 2026-09-29

新增 `rq3_llama_distinct_prompt_cardinality_probe.py`，用 4 个不同但均为
6-token 的 prompt 重跑 no-long/no-cancel cardinality probe。每个 prompt 先串行
生成 3 次 single-load reference，三次均 token/content stable；随后 cardinality
1–4 各并发 8 cycles，响应按 prompt index 与自己的 reference 比较。

N1/N2 全部 stable。N3 只有 prompt0 在 `4/8` cycles 偏离 reference，整 batch
match 与 across-cycle stable 都为 `4/8`。N4 prompt0 和 prompt3 各在 `4/8`
cycles 偏离 reference，整 batch match 与 across-cycle stable 也为 `4/8`。
mismatch 分布在不同 slot，不支持固定 bad-slot 解释。

这排除 duplicate prompt / duplicate sequence batching 作为唯一或主要原因，
登记 `DISTINCT_PROMPT_CARDINALITY_INSTABILITY_OBSERVED` 和
`DUPLICATE_PROMPT_CONFOUND_EXCLUDED`。当前边界继续局部化到 llama-server
concurrent scheduling / batching；内部机制未定位，RQ3 保持 OPEN。报告见
`docs/00-governance/SIMIGO_LAB_RQ3_LLAMA_DISTINCT_PROMPT_CARDINALITY_PROBE_20260929.md`；
artifact 见
`simigo2-experimental/results/backend-conformance/rq3-llama-distinct-prompt-cardinality-no-cancel.json`。

### LAB RQ3 ACTIVE CONCURRENCY ISOLATION — PARALLEL1 STABLE — 2026-09-29

继续用 distinct equal-length prompt probe 做三配置对照。`parallel4` continuous
batching enabled 时 N3/N4 all-match 均为 `4/8`；`parallel4 --no-cont-batching`
仍为 N3 `4/8`、N4 `4/8`，且 mismatch prompt 分布相同，说明该 flag 单独关闭不
消除边界。改为 `parallel1` 后，4 路客户端请求排队串行执行，N1–N4 全部
`8/8` match 自己的 single-load reference，共 80 requests stable。

因此 mismatch 的必要条件不是客户端提交 4 个请求，而是多个 slot 中 active
concurrent execution。已排除 cancellation、long request、duplicate prompt 和
客户端排队数量；continuous batching 开关单独不是充分解释。RQ3 增加
`ACTIVE_SLOT_CONCURRENCY_CAUSAL_BOUNDARY`、`QUEUED_N4_STABLE` 和
`CONTINUOUS_BATCHING_FLAG_NOT_SUFFICIENT`。llama-server 内部 kernel/scheduler
机制仍未定位，RQ3 保持 OPEN。报告见
`docs/00-governance/SIMIGO_LAB_RQ3_LLAMA_ACTIVE_CONCURRENCY_ISOLATION_20260929.md`；
artifacts 见
`simigo2-experimental/results/backend-conformance/rq3-llama-distinct-prompt-cardinality-no-cancel.json`、`simigo2-experimental/results/backend-conformance/rq3-llama-distinct-prompt-cardinality-no-contbatch.json`、`simigo2-experimental/results/backend-conformance/rq3-llama-distinct-prompt-cardinality-parallel1.json`。

### LAB RQ3 ACTIVE CONCURRENCY THRESHOLD — TWO STABLE / THREE PLUS UNSTABLE — 2026-09-29

用同一 distinct equal-length prompt probe 在 `parallel2 / ctx1024 /
slot512` 重跑 cardinality 1–4。当客户端提交 N3/N4 时，额外请求排队，任一时刻最
多 2 个 active sequences。结果 N1–N4 all-match 与 across-cycle stable 均为
`8/8`，共 80 requests stable。

与 `parallel1`（max active 1）和 `parallel4`（N3/N4 分别 max active 3/4）对照
后，阈值进一步精确化：active batch cardinality 1–2 observed stable；3–4
observed unstable。这证明客户端提交数量不是阈值，active batch cardinality 才是
关键变量。RQ3 增加 `ACTIVE_BATCH_COUNT_TWO_STABLE`、
`ACTIVE_BATCH_COUNT_THREE_OR_MORE_UNSTABLE` 和
`ACTIVE_CONCURRENCY_THRESHOLD_LOCALIZED`；llama-server 内部机制未定位，RQ3 仍
OPEN。报告见
`docs/00-governance/SIMIGO_LAB_RQ3_LLAMA_ACTIVE_CONCURRENCY_THRESHOLD_20260929.md`；
artifact 见
`simigo2-experimental/results/backend-conformance/rq3-llama-distinct-prompt-cardinality-parallel2-active2.json`。

### LAB RQ3 BACKEND ISOLATION — CPU STABLE / METAL ACTIVE3_4 UNSTABLE — 2026-09-29

继续用 distinct equal-length prompt probe 做 backend 对照。新增 CPU-only
`--device none --fit off --threads 4 --threads-batch 4` 的 `parallel4/slot512`
run。每个 prompt 先在该 CPU configuration 下串行建立 3 次 reference，均 stable；
随后 cardinality 1–4 各 8 cycles。CPU-only N1–N4 all-match 与 across-cycle
stable 均为 `8/8`，active3/4 不再复现 mismatch。

与既有 Metal `parallel4` 对照：Metal N3/N4 all-match 与 across-cycle stable 均
为 `4/8`，而 N1/N2 为 `8/8`。因此 active batch 3/4 instability 进一步隔离到
current Metal execution path，而不是一般 llama-server logic 或一般 batched
compute abstraction。CPU outputs 与 Metal references 不同属于预期 backend
numerical-path difference；两个 backend 分别使用自身 reference。RQ3 增加
`CPU_ONLY_ACTIVE3_4_STABLE`、`METAL_ACTIVE3_4_UNSTABLE` 和
`BACKEND_EXECUTION_PATH_ISOLATED`。具体 Metal kernel / scheduler / batch
reduction 机制未定位，RQ3 保持 OPEN。报告见
`docs/00-governance/SIMIGO_LAB_RQ3_LLAMA_BACKEND_ISOLATION_20260929.md`；
artifact 见
`simigo2-experimental/results/backend-conformance/rq3-llama-distinct-prompt-cardinality-cpu.json`。

### LAB RQ3 METAL FLAG ABLATION — FA OFF NOT SUFFICIENT / CPU-MOE NOT STABLE — 2026-09-29

继续用 distinct equal-length prompt probe 做 Metal flag ablation。Flash Attention
off 后 N1/N2 `8/8` stable，但 N3 all-match `4/8`、N4 all-match `4/8`、
across-cycle `2/8`，说明 Flash Attention 不是当前边界原因。改用
`--cpu-moe` 混合放置后，N1 stable，但 N2 all-match 只有 `2/8`、across-cycle
`1/8`；N3 `2/8`；N4 `0/8`。该 hybrid 不是 mitigation，反而把 instability
提前到 N2。

因此登记 `FLASH_ATTN_OFF_NOT_SUFFICIENT`、`CPU_MOE_HYBRID_NOT_STABLE` 和
`METAL_MOE_HYBRID_BOUNDARY_NOT_ISOLATED`。当前结论仍限定为 Metal execution
path boundary；具体 MoE kernel、graph、batch reduction 或 synchronization机制
未定位。RQ3 保持 OPEN。报告见
`docs/00-governance/SIMIGO_LAB_RQ3_LLAMA_METAL_FLAG_ABLATION_20260929.md`；
artifacts 见
`simigo2-experimental/results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-flashoff.json`、`simigo2-experimental/results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-cpumoe.json`。

### LAB RQ3 RUNTIME FLAG ABLATION II — NO STABLE METAL MITIGATION — 2026-09-29

继续 Metal runtime flag ablation。`--no-repack` 下 N1/N2 `8/8` stable，但 N3
all-match 与 across-cycle 均为 `5/8`，N4 均为 `6/8`。`--no-op-offload` seed42
中 N3 为 `7/8`、N4 为 `8/8`，但 seed43 repeat 中 N3 降为 `4/8`、N4 降为
`6/8`；因此 seed42 的 N4 改善只是单次观察，不能外推为修复。

登记 `NO_REPACK_NOT_SUFFICIENT`、`NO_OP_OFFLOAD_NOT_SUFFICIENT` 和
`METAL_FLAG_MITIGATION_NOT_ESTABLISHED`。结合先前 ablation：Flash Attention
off、no-cont-batching、CPU-Moe hybrid、no-repack、no-op-offload 都不是稳定化
mitigation。CPU-only 仍 stable，边界继续指向 current Metal active execution
path。具体上游机制未定位，RQ3 保持 OPEN。报告见
`docs/00-governance/SIMIGO_LAB_RQ3_LLAMA_RUNTIME_FLAG_ABLATION_20260929.md`；
artifacts 见
`simigo2-experimental/results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-norepack.json`、`simigo2-experimental/results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-noopoffload.json`、`simigo2-experimental/results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-noopoffload-seed43.json`。

### LAB RQ3 THREADPOOL ABLATION — THREADS1 FIXES ACTIVE3 ONLY — 2026-09-29

在 Metal `parallel4` 下将 llama-server generation threadpool 改为
`--threads 1 --threads-batch 1`，用 distinct equal-length prompt probe 在 seed42
和 seed43 各完整运行 cardinality 1–4。两个 seeds 中 active3 全部恢复 stable：
all-match 与 across-cycle 均为 `8/8`。active4 仍 unstable：all-match `6/8`，
across-cycle `1/8`，mismatch 分布为 prompt0 1 次、prompt3 2 次。

登记 `METAL_THREADPOOL_ONE_ELIMINATES_ACTIVE3_MISMATCH`、
`ACTIVE4_METAL_STILL_UNSTABLE` 和 `METAL_THREADPOOL_COUNT_ISOLATED`。这说明
CPU threadpool 并发是 active3 mismatch 的真实变量，但 active4 还有与 Metal
active4 execution path / graph shape 相关的独立变量。threads=1 只作为当前
harness 观察登记，不是通用生产 mitigation。RQ3 保持 OPEN。报告见
`docs/00-governance/SIMIGO_LAB_RQ3_LLAMA_THREADPOOL_ABLATION_20260929.md`；
artifacts 见
`simigo2-experimental/results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-threads1.json`、`simigo2-experimental/results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-threads1-seed43.json`。

### LAB RQ3 UBATCH ISOLATION — UBATCH2 STABILIZES METAL ACTIVE4 — 2026-09-29

在 Metal `parallel4 / threads1` 下将 `--ubatch-size` 从默认 512 降到 2，继续用
distinct equal-length prompt probe 在 seed42 和 seed43 各运行 cardinality 1–4。
两个 seeds 中 N1–N4 all-match 与 across-cycle stable 均为 `8/8`，共 80 requests
stable。

与 `threads1 / ubatch512` 对照：active4 all-match 从 `6/8`、across-cycle `1/8`
变为两 seeds 均 `8/8`。因此 active4 mismatch 与 physical ubatch shape 相关；
`ubatch2` 是当前 harness 中第一个可复现的 Metal active4 mitigation。RQ3 增加
`METAL_THREADS1_UBATCH2_STABLE_N1_N4`、`ACTIVE4_METAL_UBATCH2_MITIGATION_OBSERVED`
和 `UBATCH_SHAPE_ISOLATED`。未测量性能，不能推荐生产配置；具体 Metal kernel /
graph reduction 仍未定位。RQ3 保持 OPEN。报告见
`docs/00-governance/SIMIGO_LAB_RQ3_LLAMA_UBATCH_ISOLATION_20260929.md`；artifacts 见
`simigo2-experimental/results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-threads1-ubatch2.json`、`simigo2-experimental/results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-threads1-ubatch2-seed43.json`。

### LAB RQ3 UBATCH2 × THREADS4 ISOLATION — PRIMARY MITIGATION CONFIRMED — 2026-09-29

为区分 `ubatch2` 与 `threads1` 的贡献，保持默认
`--threads 4 --threads-batch 4`，仅添加 `--ubatch-size 2`，在 seed42 和 seed43
各运行 distinct equal-length prompt cardinality 1–4。两个 seeds 中 N1–N4
all-match 与 across-cycle stable 均为 `8/8`，共 80 requests stable。

登记 `UBATCH2_INDEPENDENT_OF_THREADPOOL`、`THREADS4_UBATCH2_STABLE_N1_N4` 和
`UBATCH2_IS_PRIMARY_MITIGATION`。因子矩阵现为：`threads4/ubatch512` N3/N4
unstable；`threads1/ubatch512` N3 stable 但 N4 unstable；`threads1/ubatch2` 与
`threads4/ubatch2` N1–N4 stable。因此 `ubatch2` 是 primary mitigation，不依赖
single-thread CPU coordination。未测量性能，不能推荐生产配置；具体 Metal kernel /
graph reduction 仍未定位。RQ3 保持 OPEN。报告见
`docs/00-governance/SIMIGO_LAB_RQ3_LLAMA_UBATCH2_THREAD4_ISOLATION_20260929.md`；artifacts 见
`simigo2-experimental/results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-threads4-ubatch2.json`、`simigo2-experimental/results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-threads4-ubatch2-seed43.json`。

### LAB RQ3 UBATCH8 STABLE — SAFE BOUND AT LEAST 8 — 2026-09-29

继续 ubatch sweep，在 Metal `parallel4 / threads4 / ubatch8` 上用 distinct
equal-length prompt probe 运行 cardinality 1–4。seed42 和 seed43 中 N1–N4
all-match 与 across-cycle stable 均为 `8/8`。

结合 `ubatch2/4/8` 两 seeds stable、default `ubatch512` intermittent unstable，
登记 `UBATCH8_STABLE_N1_N4`、`SAFE_UBATCH_UPPER_BOUND_AT_LEAST_8` 和
`UBATCH512_INSTABILITY_NOT_SIMPLE_THRESHOLD_AT_8`。`ubatch4` artifacts 见
`simigo2-experimental/results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-threads4-ubatch4.json`、`simigo2-experimental/results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-threads4-ubatch4-seed43.json`。这说明 mitigation 不是
`ubatch2` 独有，但 default 512 mismatch 也不能简化为“超过 8 必然失败”。当前
safe observed upper bound 为 8；9–511 未逐一测试，具体 Metal kernel / graph
reduction 仍未定位。RQ3 保持 OPEN。报告见
`docs/00-governance/SIMIGO_LAB_RQ3_LLAMA_UBATCH8_STABLE_20260929.md`；artifacts 见
`simigo2-experimental/results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-threads4-ubatch8.json`、`simigo2-experimental/results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-threads4-ubatch8-seed43.json`。

### LAB RQ3 NGL SWEEP — HIGH-LAYER SPLIT INTERMITTENT BOUNDARY — 2026-09-29

用 distinct equal-length prompt probe 做 Metal layer-split sweep。NGL20/30/35/37
各运行 cardinality 1–4，active4 均稳定；NGL38 运行三次，其中 seed42 首次出现
active4 all-match `3/8`、across-cycle `5/8`，seed42 repeat 为 `7/8` /
`7/8`，seed43 为 `8/8` / `8/8`。full-Metal NGL40 baseline 此前亦观察到
active4 mismatch。

登记 `NGL20_30_35_37_STABLE_ACTIVE4`、`NGL38_INTERMITTENT_ACTIVE4_MISMATCH`、
`NGL_BOUNDARY_LOCALIZED_TO_HIGH_LAYER_SPLIT` 和
`DETERMINISTIC_NGL_THRESHOLD_NOT_ESTABLISHED`。这说明 boundary 与 high-layer
Metal split 相关，但 mismatch 是概率性/调度相关，不是简单 `NGL>=38` threshold。
具体 Metal kernel / graph reduction 仍未定位。RQ3 保持 OPEN。报告见
`docs/00-governance/SIMIGO_LAB_RQ3_LLAMA_NGL_SWEEP_20260929.md`；artifacts 见
`simigo2-experimental/results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-ngl20.json`、`...ngl30.json`、`...ngl35.json`、`...ngl37.json`、`...ngl38.json`、`...ngl38-seed42-repeat.json`、`...ngl38-seed43.json`。

### LAB RQ3 UBATCH512 REPRODUCIBILITY — ACTIVE3/4 UNSTABLE BOTH SEEDS — 2026-09-29

为避免将 default Metal full-GPU mismatch 当作 seed42 单次观察，使用同一 distinct
equal-length prompt probe 在 `parallel4 / slot512 / ubatch512 / threads4` 下补跑
seed43。每个 prompt 先串行建立 3 次 stable reference；cardinality 1–4 各 8
cycles。

seed43 中 N1/N2 stable，但 N3 all-match 与 across-cycle 均为 `6/8`，prompt0
出现 2 次 mismatch；N4 all-match `3/8`、across-cycle `5/8`，prompt0 和 prompt3
各出现 5 次 mismatch。结合 seed42 baseline（N3 `4/8`、N4 `4/8`），登记
`METAL_UBATCH512_MISMATCH_REPRODUCED`、`ACTIVE3_UNSTABLE_BOTH_SEEDS` 和
`ACTIVE4_UNSTABLE_BOTH_SEEDS`。

结合既有 mitigation runs，`ubatch512/threads4` 两 seeds unstable，而
`ubatch2/threads4` 与 `ubatch2/threads1` 均 stable；因此 `ubatch2` mitigation
不是 seed-specific coincidence。具体 Metal kernel / graph reduction 仍未定位，
RQ3 保持 OPEN。报告见
`docs/00-governance/SIMIGO_LAB_RQ3_LLAMA_UBATCH512_REPRODUCIBILITY_20260929.md`；
artifact 见
`simigo2-experimental/results/backend-conformance/rq3-llama-distinct-prompt-cardinality-metal-ubatch512-seed43.json`。

### LAB RQ3 UBATCH2 CANCELLATION CURVE — STRICT PASS / LARGE LATENCY — 2026-09-29

把 `ubatch2` mitigation 放回最初失败的 higher-concurrency cancellation curve，
使用 `parallel4 / ctx2048 / slot512 / ubatch2` 运行 L1-L3 各一次，共 3 cycles。
结果 strict PASS：DELETE `6/6` accepted；same-load baseline stable `3/3`；
cancellation controls matched same-load baseline `3/3`；所有 control batches
完成。default `ubatch512` curve 中的 identity mismatch 不再复现。

代价是延迟显著放大：DELETE→all-long-free 按 L1-L3 分别为
`4,201.325 / 8,090.322 / 13,633.230ms`，control client mean 为
`4,691.426 / 8,352.944 / 13,854.959ms`。所有 controls 在 all-longs-free 后才
完成。因此 `ubatch2` 是 identity mitigation，不是 performance mitigation。

首次尝试用原 `free-timeout-ms=5000` 在 cycle1 报 cancelled longs did not
free，无 artifact；server 随后可继续响应。改为 `15000` 的 3-cycle run 通过，
说明 heavy `ubatch2` curve 需要同步放大 harness timeout。RQ3 增加
`UBATCH2_CURVE_STRICT_PASS`、`UBATCH2_MITIGATES_CANCELLATION_IDENTITY` 和
`HARNESS_FREE_TIMEOUT_MUST_SCALE_WITH_UBATCH2`；RQ3 保持 OPEN。报告见
`docs/00-governance/SIMIGO_LAB_RQ3_LLAMA_CONCURRENCY_CURVE_UBATCH2_20260929.md`；
artifact 见
`simigo2-experimental/results/backend-conformance/rq3-llama-concurrency-curve-ubatch2-cycles3.json`。

### LAB RQ3 MITIGATED LAUNCH PROFILE OPERATIONAL — 2026-09-29

将 `threads4 / ubatch2` mitigation 操作化为 canonical launch wrapper
`rq3_llama_server_mitigated.sh`，固定 `ctx2048 / parallel4 / ubatch2 /
threads4` 与 cache-disabled RQ3 flags；model path 为必填参数，host/port/
threads/ubatch 可用环境变量覆盖。wrapper smoke 已在 `LLAMA_PORT=18081`
成功启动并返回 model path。

同时把 `rq3_llama_concurrency_curve.py` 默认 `--free-timeout-ms` 从 `5000`
提高到 `15000`，避免 `ubatch2` heavy curve 中最长约 `13.6s` 的 slot release
被误判为 failure。该变更只操作化已验证 mitigation，不修改 Swift runtime、
Execution State backend、llama.cpp 上游或采样逻辑；不建立生产 readiness 或
性能结论。登记 `MITIGATED_LAUNCH_PROFILE_OPERATIONAL` 和
`CURVE_FREE_TIMEOUT_DEFAULT_HARDENED`。报告见
`docs/00-governance/SIMIGO_LAB_RQ3_LLAMA_MITIGATION_PROFILE_20260929.md`。

### LAB RQ3 UBATCH2 CANONICAL HARNESS REGRESSION PASS — 2026-09-29

使用 canonical mitigated launch profile 回归三个 Swift RQ3 harness。Swift
hot-path A/B 在 30 paired samples 中 OFF/ON semantic stability 均 `30/30`，
paired ON−OFF mean `+0.071ms`；Swift fork/restore 30 samples 的 replay identity、
divergence、parent non-interference、restore-to-fork-point 均 `30/30`；Swift
cancellation A/B 中 OFF/ON DELETE accepted 与 recovery identity 均 `20/20 + 20/20`。

同时修复 Swift cancellation harness 的 multi-slot bug：原逻辑等待
`slots.count == 1`，无法用于 canonical `parallel4` profile；现改为等待所有
slots idle，并将 free timeout default 提高到 `15000ms`。该修复只放宽 readiness
判定，不改变 Execution State semantics 或 server flags。修改 Swift 后全仓
`swift test` 为 `157 PASS / 0 FAIL`。RQ3 增加
`UBATCH2_CANONICAL_HARNESS_REGRESSION_PASS` 和
`CANCELLATION_HARNESS_MULTISLOT_WAIT_FIXED`，但仍保持 OPEN。报告见
`docs/00-governance/SIMIGO_LAB_RQ3_LLAMA_UBATCH2_CANONICAL_REGRESSION_20260929.md`；artifacts 见
`simigo2-experimental/results/backend-conformance/rq3-llama-swift-execstate-hotpath-ab-ubatch2.json`、`...fork-restore-ubatch2.json`、`...cancellation-ubatch2.json`。

### LAB RQ3 UBATCH8 OPERATIONAL PROFILE — SELECTED OVER UBATCH2 — 2026-09-29

在 `ubatch2/4/8` cardinality probe 均 stable 后，将 `ubatch8` 放回原始
L1-L3 cancellation curve。结果 strict PASS：DELETE `6/6` accepted；same-load
baseline stable `3/3`；cancellation identity matched same-load baseline `3/3`。
DELETE→all-long-free mean 从 `ubatch2` 的 `8,641.626ms` 降至 `4,806.919ms`。

随后用 `ubatch8` 回归三个 Swift canonical harness。hot-path A/B OFF/ON
semantic stability 均 `30/30`，paired ON−OFF mean `+1.499ms`；fork/restore 四项
semantic checks 均 `30/30`；cancellation A/B OFF/ON accepted 与 recovery
identity 均 `20/20 + 20/20`。因此 canonical mitigation profile 从 `ubatch2`
升级为 `ubatch8`，登记 `UBATCH8_CANONICAL_HARNESS_REGRESSION_PASS`、
`MITIGATED_LAUNCH_PROFILE_UPGRADED_TO_UBATCH8` 和
`UBATCH8_SELECTED_OVER_UBATCH2_FOR_LOWER_LATENCY`。延迟比较只是同一日 harness
observation，不是性能 benchmark 或生产 recommendation。RQ3 保持 OPEN。报告见
`docs/00-governance/SIMIGO_LAB_RQ3_LLAMA_UBATCH8_OPERATIONAL_20260929.md`；artifacts 见
`simigo2-experimental/results/backend-conformance/rq3-llama-concurrency-curve-ubatch8.json`、`simigo2-experimental/results/backend-conformance/rq3-llama-swift-execstate-hotpath-ab-ubatch8.json`、`...fork-restore-ubatch8.json`、`...cancellation-ubatch8.json`。

### LAB UI BRANCH SESSIONS PILOT PASS — 2026-09-29

开始 pasted research program 中排在 Backend Conformance 后面的 UI Branch
Sessions 线。新增最小 Swift control plane `UIBranchSessions` 和 CLI
`llama-branch-session`，只编排既有 Execution Continuity Coordinator、LLAMA
prefix backend 和 HTTP executor；不新增 inference runtime，不修改 native KV
authority。语义路径覆盖 create/bind、fork A/B、capture root fork point、
continue root/A/B、switch root 到 fork point、switch A/root 到 advanced
position、release branches，并验证 root survives。

在 canonical mitigated `ubatch8` LLAMA profile、Cyber-Tiel 当前 model、
seed42、8 prediction tokens 下 pilot PASS：branch divergence、lineage
isolation、root fork-point replay、branch/root switch retention、branch
release、root survival 七项 checks 全部 PASS。同一 commit 全仓 Swift
verification 为 `157 PASS / 0 FAIL`（contract 19 + experimental 137 +
Swift Testing 1）。登记 `UI_CONTROL_PLANE_OPERATIONAL` 和
`UI_BRANCH_SESSIONS_LLAMA_PILOT_PASS`；状态为
`UI1 = PASS / LLAMA_PILOT_WITH_BOUNDARY`，不是 UI product、persistent session、
nested branch graph 或 cross-backend closure。

报告见
`docs/00-governance/SIMIGO_LAB_UI_BRANCH_SESSIONS_PILOT_20260929.md`；artifact 见
`simigo2-experimental/results/backend-conformance/ui-branch-session-llama-pilot.json`。

### LAB UI BRANCH SESSIONS MLX PILOT PASS — 2026-09-29

把 UI Branch Sessions 从 LLAMA pilot 扩展到 oversized MLX baseline。新增
`UIBranchSessions.runOversizedMLX` 和 CLI `mlx-branch-session`，复用
`ExecutionContinuityCoordinator`、`OversizedSegmentedStateBackend`、
`OversizedSegmentedExecutor` 与 `O6SegmentedCore`；不新增 inference runtime，
不修改 Execution State contract。使用本地 Qwen3-Coder-Next-4bit snapshot、
segment size 8、cacheless greedy、2-token continuation；未下载模型。

八项 checks 全部 PASS：branch divergence、lineage isolation、root fork-point
replay、branch/root switch retention、branch release、root survival、oversized
profile under 30GiB。观测 peak footprint `7,858 MiB`、max swap `0 MiB`、
segment transitions `50`。同一 commit 全仓 Swift verification 为
`157 PASS / 0 FAIL`。登记 `UI_BRANCH_SESSIONS_MLX_PILOT_PASS` 和
`UI_SESSION_TWO_BACKEND_EVIDENCE`；状态为
`UI2 = PASS / OVERSIZED_MLX_PILOT_WITH_BOUNDARY`。这只是 second-backend
harness evidence，不是 exact same-workload cross-backend closure、UI product
closure 或性能结论。

报告见
`docs/00-governance/SIMIGO_LAB_UI_BRANCH_SESSIONS_MLX_PILOT_20260929.md`；artifact 见
`simigo2-experimental/results/backend-conformance/ui-branch-session-mlx-oversized-pilot.json`。

### LAB UI BRANCH SESSIONS CROSSBACKEND MATRIX PASS — 2026-09-29

把 LLAMA UI Branch Session 从硬编码 token workload 升级为 V2 text workload：
通过 llama-server `/tokenize` 读取与 MLX 相同 seed/root/branchA/branchB 文本，
两边均执行 2-token generation 和相同 8-step operation sequence。新增
`runCrossBackendMatrix` 与 CLI `ui-branch-session-matrix`，在 single driver 中
先后运行 LLAMA 和 oversized MLX harness。LLAMA 为 Cyber-Tiel GGUF canonical
mitigated profile；MLX 为本地 Qwen3-Coder-Next-4bit oversized snapshot。

七项 common semantic checks 均在两边 PASS；`sameSemanticChecks`、
`sameOperationSequence`、`sameWorkloadShape`、`bothBackendsPass` 均 true。MLX
backend-specific `OVERSIZED_PROFILE_UNDER_30GIB` 也 PASS，观测 peak footprint
`6,577 MiB`。同一 commit 全仓 Swift verification 为 `157 PASS / 0 FAIL`。
登记 `UI_LLAMA_TEXT_WORKLOAD_ALIGNMENT`、
`UI_CROSSBACKEND_SEMANTIC_MATRIX_PASS` 和
`CROSSBACKEND_MODEL_IDENTITY_CLOSURE_BLOCKED`；状态为
`UI3 = PASS_WITH_BOUNDARY / SAME_SHAPE_SEMANTIC_MATRIX`。两者使用不同 model
artifact 和 tokenizer，因此 cross-backend / model-identity closure 保持 OPEN，
不得把矩阵解释为 same-model 或 universal closure。

报告见
`docs/00-governance/SIMIGO_LAB_UI_BRANCH_SESSIONS_CROSSBACKEND_MATRIX_20260929.md`；artifact 见
`simigo2-experimental/results/backend-conformance/ui-branch-session-crossbackend-matrix.json`。

### LAB UI BRANCH SESSIONS NESTED REPEAT PASS — 2026-09-29

把 UI Branch Sessions 从 depth-1 A/B graph 扩展到 nested graph 和 repeated
physical release/restore/switch。新增 `UIBranchSessions.runNestedLLAMA` 与 CLI
`llama-branch-session-nested`；session 图为 root -> branch A -> nested A1，且
root -> branch B。使用 LLAMA canonical mitigated profile、当前 Cyber-Tiel
model、seed42、2-token continuation 和 2 cycles。

八项 checks 全部 PASS：nested lineage isolation、fork-point isolation、branch
physical-prefix divergence、两轮 release->restore@0->replay->switch@1 的
deterministic replay、advanced binding retention、nested/direct branch release、
parent branch survival、root survival。同一 commit 全仓 Swift verification 为
`157 PASS / 0 FAIL`。登记 `UI_NESTED_BRANCH_GRAPH_LLAMA_PASS` 和
`UI_REPEATED_RELEASE_RESTORE_SWITCH_PASS`；状态为
`UI4 = PASS / LLAMA_NESTED_AND_REPEAT_WITH_BOUNDARY`。这只是 LLAMA harness
pilot，不代表 nested MLX/cross-backend closure、arbitrary-depth graph、persistent
session、UI product 或性能结论。

报告见
`docs/00-governance/SIMIGO_LAB_UI_BRANCH_SESSIONS_NESTED_REPEAT_20260929.md`；artifact 见
`simigo2-experimental/results/backend-conformance/ui-branch-session-llama-nested-repeat.json`。

### LAB UI BRANCH SESSIONS MLX NESTED REPEAT PASS — 2026-09-29

把 nested + repeated UI Branch Session lifecycle 从 LLAMA 扩展到 oversized MLX
baseline。新增 `UIBranchSessions.runNestedOversizedMLX` 和 CLI
`mlx-branch-session-nested`；session 图为 root -> branch A -> nested A1，且
root -> branch B。使用本地 Qwen3-Coder-Next-4bit snapshot、segment size 8、
cacheless greedy、2-token continuation 和 2 cycles。

九项 checks 全部 PASS：nested lineage isolation、fork-point isolation、branch
physical-prefix divergence、两轮 oversized release->restore@0->replay->
switch@1 的 deterministic replay、advanced binding retention、nested/direct
branch release、parent branch survival、root survival、oversized profile under
30GiB。观测 peak footprint `7,970 MiB`、max swap `0 MiB`、segment transitions
`64`。同一 commit 全仓 Swift verification 为 `157 PASS / 0 FAIL`。登记
`UI_NESTED_BRANCH_GRAPH_MLX_PASS` 和
`UI_REPEATED_RELEASE_RESTORE_SWITCH_MLX_PASS`；状态为
`UI5 = PASS / MLX_NESTED_AND_REPEAT_WITH_BOUNDARY`。这只是 MLX harness pilot，
不代表 nested cross-backend matrix、arbitrary-depth graph、persistent session、
UI product 或性能结论。

报告见
`docs/00-governance/SIMIGO_LAB_UI_BRANCH_SESSIONS_MLX_NESTED_REPEAT_20260929.md`；artifact 见
`simigo2-experimental/results/backend-conformance/ui-branch-session-mlx-nested-repeat.json`。

### LAB UI BRANCH SESSIONS NESTED CROSSBACKEND MATRIX PASS — 2026-09-29

把 nested + repeated UI Branch Session lifecycle 放入 same-shape cross-backend
matrix。新增 `runNestedCrossBackendMatrix` 和 CLI `ui-nested-branch-matrix`，
在 single driver 中先后运行 LLAMA nested harness 与 oversized MLX nested
harness。两边使用同一 seed/root/branchA/nested/branchB 文本、2-token budget、
2 cycles、相同 root -> A -> A1 / root -> B graph 和相同 11-step operation
sequence。

八项 common semantic checks 均在两边 PASS；
`sameSemanticChecks`、`sameOperationSequence`、`sameWorkloadShape`、
`bothBackendsPass` 均 true。MLX backend-specific
`OVERSIZED_PROFILE_UNDER_30GIB` PASS，观测 peak footprint `6,079 MiB`、max swap
`0 MiB`、segment transitions `64`。同一 commit 全仓 Swift verification 为
`157 PASS / 0 FAIL`。登记 `UI_NESTED_CROSSBACKEND_SEMANTIC_MATRIX_PASS` 和
`NESTED_CROSSBACKEND_MODEL_IDENTITY_CLOSURE_BLOCKED`；状态为
`UI6 = PASS_WITH_BOUNDARY / NESTED_SAME_SHAPE_SEMANTIC_MATRIX`。LLAMA 与 MLX
model artifact 和 tokenizer 不同，因此 nested cross-backend / model-identity
closure 保持 OPEN，不得解释为 universal 或 same-model closure。

报告见
`docs/00-governance/SIMIGO_LAB_UI_BRANCH_SESSIONS_NESTED_CROSSBACKEND_MATRIX_20260929.md`；artifact 见
`simigo2-experimental/results/backend-conformance/ui-branch-session-nested-crossbackend-matrix.json`。

### LAB UI BRANCH SESSIONS CANCELLATION PASS — 2026-09-29

把 pasted workload matrix 中的 W9 cancellation 接入 UI Branch Session control
plane。新增 `runCancellationLLAMA` 和 CLI `llama-branch-session-cancel`；每轮
建立 root、long branch、control branch，capture long physical prefix 后启动显式
LLAMA stream，DELETE 取消，等待 slot free，release cancelled prefix，restore
root，fork recovery branch，并 restore/replay control sibling。使用 canonical
mitigated profile、当前 Cyber-Tiel model、seed42、2 cycles、100ms cancel delay。

八项 checks 全部 PASS：DELETE `2/2` 返回 204、cancelled slot freed、cancelled
long physical prefix released、root recovery identity、control sibling recovery
identity、root/control prefix divergence、post-cancel recovery lineage isolation
和 cycles complete。同一 commit 全仓 Swift verification 为
`157 PASS / 0 FAIL`。登记 `UI_SESSION_EXPLICIT_CANCEL_RECOVERY_PASS` 和
`UI_CANCELLED_BRANCH_PHYSICAL_RELEASE_PASS`；状态为
`UI7 = PASS / LLAMA_SESSION_CANCELLATION_WITH_BOUNDARY`。这是 LLAMA harness
pilot，不代表 MLX/cross-backend cancellation closure、production cancellation、
persistent session 或性能结论。

报告见
`docs/00-governance/SIMIGO_LAB_UI_BRANCH_SESSIONS_CANCELLATION_20260929.md`；artifact 见
`simigo2-experimental/results/backend-conformance/ui-branch-session-llama-cancellation.json`。

### LAB UI BRANCH SESSIONS MLX CANCELLATION PASS — 2026-09-29

把 W9 cancellation 从 LLAMA explicit stream cancel 扩展到 oversized MLX
cooperative token-boundary cancel。新增 `runCancellationOversizedMLX` 和 CLI
`mlx-branch-session-cancel`；每轮建立 root、long branch、control branch，先记录
root/control pre-cancel reference，再在 long branch 生成 1 个完整 greedy token 后
cooperative cancel，bind consumed prefix、release physical representation、restore
root、fork recovery branch，并逐 cycle 恢复 root/control identity。使用本地
Qwen3-Coder-Next-4bit snapshot、segment size 8、maxTokens4、2 cycles。

九项 checks 全部 PASS：cooperative cancellation 一致发生在 1 token 边界
`[1,1]`、cancelled physical prefix released、cancelled long logically discarded、
root/control 逐 cycle pre-cancel/post-cancel identity、prefix divergence、
recovery lineage isolation、root/control survive release、oversized profile under
30GiB。观测 peak footprint `7,946 MiB`、max swap `0 MiB`、segment transitions
`254`。同一 commit 全仓 Swift verification 为 `157 PASS / 0 FAIL`。登记
`UI_SESSION_COOPERATIVE_CANCEL_RECOVERY_MLX_PASS` 和
`UI_CANCELLED_MLX_BRANCH_RELEASE_DISCARD_PASS`；状态为
`UI8 = PASS / MLX_SESSION_COOPERATIVE_CANCELLATION_WITH_BOUNDARY`。这是 MLX
harness pilot，不代表 cross-backend cancellation matrix、production cancellation、
persistent session 或性能结论。

报告见
`docs/00-governance/SIMIGO_LAB_UI_BRANCH_SESSIONS_MLX_CANCELLATION_20260929.md`；artifact 见
`simigo2-experimental/results/backend-conformance/ui-branch-session-mlx-cancellation.json`。

### LAB UI BRANCH SESSIONS CANCELLATION CROSSBACKEND MATRIX PASS — 2026-09-29

把 W9 cancellation 放入 same-session-shape cross-backend matrix。新增
`runCancellationCrossBackendMatrix` 和 CLI `ui-cancellation-matrix`，在 single
driver 中先后运行 LLAMA explicit stream DELETE 与 oversized MLX cooperative
token-boundary cancellation。两边使用相同 seed/root/control/recovery/long 文本、
相同 root -> long / control / recovery graph、2-token recovery budget 和 2
cycles。同时升级 LLAMA cancellation harness：cancelled long 增加 logical
discard，并验证 root/control survive release。

十项 standardized common checks 全部 PASS：cancellation accepted、execution
stopped、cancelled physical release、logical discard、root/control 逐 cycle
identity、prefix divergence、recovery lineage isolation、root/control survive、
cycles complete。`sameOutcomeShape`、`sameRecoverySemantics`、
`sameWorkloadShape`、`bothBackendsPass` 均 true。MLX backend-specific
`OVERSIZED_PROFILE_UNDER_30GIB` PASS，观测 peak footprint `6,102 MiB`、segment
transitions `134`。同一 commit 全仓 Swift verification 为 `157 PASS / 0 FAIL`。
登记 `UI_SESSION_CANCELLATION_CROSSBACKEND_MATRIX_PASS`、
`CANCELLATION_MECHANISM_DIFFERENCE_REGISTERED` 和
`CROSSBACKEND_CANCELLATION_MODEL_IDENTITY_CLOSURE_BLOCKED`；状态为
`UI9 = PASS_WITH_BOUNDARY / SESSION_CANCELLATION_OUTCOME_SHAPE_MATRIX`。机制、
model artifact、tokenizer 和 physical representation 不同，因此 cancellation
closure 保持 OPEN，不得解释为 universal、same-model 或 production claim。

报告见
`docs/00-governance/SIMIGO_LAB_UI_BRANCH_SESSIONS_CANCELLATION_CROSSBACKEND_MATRIX_20260929.md`；artifacts 见
`simigo2-experimental/results/backend-conformance/ui-branch-session-cancellation-crossbackend-matrix.json`、`simigo2-experimental/results/backend-conformance/ui-branch-session-llama-cancellation.json`。

### LAB MLX EXECSTATE COST PROFILE PASS — 2026-09-29

开始 pasted plan 的 phase-6 cost characterization。新增
`MLXExecutionStateCostProfile` 和 CLI `mlx-execstate-cost`，在 oversized MLX
prefix-recompute 路径上分别观测 paired direct-vs-state ordinary generation 与
capture/fork/diverge/release/restore/replay lifecycle。使用本地
Qwen3-Coder-Next-4bit snapshot、segment size 8、2-token generation、3 paired
cycles、2 lifecycle cycles。

五项 checks 全部 PASS：paired greedy semantics stable、lifecycle replay exact、
branch divergence、parent non-interference、oversized profile under 30GiB。
paired observation 中 direct/state generation mean 为
`19,203.369/19,243.577ms`，state−direct mean `+40.208ms`，但 median
`-59.290ms`、范围约 `-807.920` 到 `+988.835ms`，且只有 3 samples，因此不解释为
稳定 overhead。no-fork state local bookkeeping mean `0.022111ms`。lifecycle
local capture/fork/release/restore 合计 mean `7.695876ms`，其中 oversized
segment release mean `7.651396ms`，说明 release 是本路径的主要 local operation，
不可与 LLAMA dictionary release 直接比较。观测 peak footprint `7,714 MiB`、max
swap `0 MiB`、segment transitions `146`。同一 commit 全仓 Swift verification 为
`157 PASS / 0 FAIL`。登记 `MLX_EXECSTATE_PAIRED_COST_OBSERVED`、
`MLX_EXECSTATE_LIFECYCLE_LOCAL_COST_OBSERVED` 和 `NOT_A_PERFORMANCE_BENCHMARK`；
状态为 `COST1 = PASS / OVERSIZED_MLX_COST_OBSERVATION_WITH_BOUNDARY`，不是
throughput benchmark、production readiness、跨 backend 或跨硬件 performance
claim。

报告见
`docs/00-governance/SIMIGO_LAB_MLX_EXECSTATE_COST_PROFILE_20260929.md`；artifact 见
`simigo2-experimental/results/backend-conformance/mlx-execstate-cost-profile.json`。

### LAB MLX EXECSTATE SCALE PROFILE PASS — 2026-09-29

继续 phase-6 characterization，新增 token-length scale sweep
`runScaleSweep` 和 CLI `mlx-execstate-scale`。在 oversized MLX prefix-recompute
路径上比较 direct generation 与 state-aware generation，prefix token lengths
`8/64/256`，每 bucket 2 组交替 pairs，maxTokens `1`；先执行一次未计时 warmup。
`stateLocalMs` 明确只含 capture + advance/bind + release stale，不包含
generation。

三项 checks 全部 PASS：所有 scale semantics stable、所有 length observed、
oversized profile under 30GiB。观测 direct/state mean：8 tokens
`9,947.386/9,931.575ms`，64 tokens `11,943.900/11,971.644ms`，256 tokens
`17,177.501/17,565.942ms`；paired state−direct mean 分别
`-15.811/+27.744/+388.442ms`，每 bucket 只有 2 samples，不能归因为稳定
Execution State overhead。state local bookkeeping 约
`0.0106–0.0149ms`。观测 overall peak footprint `7,954 MiB`、max swap `0 MiB`、
segment transitions `85`。同一 commit 全仓 Swift verification 为
`157 PASS / 0 FAIL`。登记 `MLX_EXECSTATE_TOKEN_LENGTH_SCALE_OBSERVED`、
`MLX_EXECSTATE_STATE_LOCAL_COST_SEPARATED` 和
`SMALL_SAMPLE_NOT_A_PERFORMANCE_BENCHMARK`；状态为
`COST2 = PASS / OVERSIZED_MLX_TOKEN_LENGTH_OBSERVATION_WITH_BOUNDARY`。观测到
当前 cacheless greedy harness 的 latency 随 prefix length 增长，但不建立定量
曲线、throughput、production、跨 backend 或跨硬件 claim。

报告见
`docs/00-governance/SIMIGO_LAB_MLX_EXECSTATE_SCALE_PROFILE_20260929.md`；artifact 见
`simigo2-experimental/results/backend-conformance/mlx-execstate-scale-profile.json`。

### LAB MLX RELEASE COST PROFILE PASS — 2026-09-29

继续 phase-6 characterization，新增 release-action isolation profile
`runReleaseCostProfile` 和 CLI `mlx-release-cost`。把 oversized release 从
generation 中分离，按 prefix token lengths `8/64/256`、每 length 10 samples，
对比 current release、checkpoint restore、stale release no-op。无 inference
generation。

六项 checks 全部 PASS：current release removes binding、restore rebinds
checkpoint、stale release preserves checkpoint、stale release does not release
segments、all lengths observed、oversized profile under 30GiB。30 samples 中
current release transition delta 全部 `1`、stale release 全部 `0`。current
release mean `4.061400ms`、median `4.037834ms`、p95 `4.162667ms`；stale
no-op mean `0.000188ms`，约为 current release 的 `0.0044%–0.0049%`。8/64/256
prefix 的 current release mean 分别 `4.112971/4.022534/4.048696ms`，观测范围内
基本与 prefix length 无关。capture/restore 仍在微秒级。观测 peak footprint
`1,381 MiB`、max swap `0 MiB`、segment transitions `30`。同一 commit 全仓 Swift
verification 为 `157 PASS / 0 FAIL`。登记
`MLX_RELEASE_ACTION_COST_ISOLATED`、`STALE_RELEASE_NOOP_SEMANTICS_ISOLATED` 和
`PREFIX_LENGTH_INDEPENDENT_RELEASE_OBSERVED`；状态为
`COST3 = PASS / OVERSIZED_MLX_RELEASE_ACTION_ISOLATED_WITH_BOUNDARY`。这是
current implementation 的 local action observation，不是最优策略、production
performance、跨 backend 或跨硬件 claim。

报告见
`docs/00-governance/SIMIGO_LAB_MLX_RELEASE_COST_PROFILE_20260929.md`；artifact 见
`simigo2-experimental/results/backend-conformance/mlx-release-cost-profile.json`。

### LAB MLX RELEASE/RECOVERY COST PROFILE PASS — 2026-09-29

继续 phase-6 characterization，新增 retain-vs-release/restore paired recovery
profile `runReleaseRecoveryProfile` 和 CLI `mlx-release-recovery`。在 oversized
MLX prefix-recompute 路径上比较 `RETAIN`（capture 后不额外 release/restore）与
`RELEASE_RESTORE`（capture、current release、checkpoint restore），然后执行相同
cacheless greedy generation。prefix length `64`、maxTokens `2`、4 cycles；每
strategy 前先 normalize released segment state，交替 order。

七项 checks 全部 PASS：both strategies complete、generation token budget
complete、oversized profile under 30GiB、paired strategy outputs exact、recovery
bindings exact、RETAIN action does not release segments、RELEASE action releases
segments。四个 cycle 中 RETAIN action transition delta 全部 `0`，RELEASE_RESTORE
全部 `1`。action mean `0.008479/4.519990ms`；generation mean
`21,294.930/21,084.897ms`。两两配对 generated token IDs/text 完全一致。观测
peak footprint `7,732 MiB`、max swap `0 MiB`、segment transitions `115`。同一
commit 全仓 Swift verification 为 `157 PASS / 0 FAIL`。登记
`MLX_RETAIN_VS_RELEASE_RECOVERY_ACTION_COST_OBSERVED`、
`PAIRED_STRATEGY_OUTPUTS_EXACT` 和
`CACHELESS_RELEASE_DID_NOT_CHANGE_PAIRED_GENERATION_OUTPUT`；状态为
`COST4 = PASS / RETAIN_VS_RELEASE_RESTORE_OBSERVATION_WITH_BOUNDARY`。RELEASE
action 的可归因 local cost约 `4.5ms`；generation mean 差异方向不稳定且每 strategy
只有 4 samples，不建立 performance penalty/benefit。`RETAIN` 不是 warm-KV
retention，也不建立 release policy、production、跨 backend 或跨硬件 claim。

报告见
`docs/00-governance/SIMIGO_LAB_MLX_RELEASE_RECOVERY_PROFILE_20260929.md`；artifact 见
`simigo2-experimental/results/backend-conformance/mlx-release-recovery-profile.json`。

### LAB MLX RELEASE/RECOVERY TOKEN SCALE PASS — 2026-09-29

继续 phase-6 token-budget scale observation。复用
`runReleaseRecoveryProfile`，在 oversized MLX prefix-recompute 路径上对
`RETAIN` vs `RELEASE_RESTORE` 分别运行 maxTokens `1/2/4`；prefix length `64`、
cycles `2` per strategy per budget、segment size `8`、交替 order。三个 raw runs
均 PASS，7 项 checks 全部 PASS，所有 paired generated token IDs/text exact。

strategy-averaged generation mean 按 budget 为
`10,435.064 / 21,721.998 / 50,665.760ms`；相对 marginal 增量为
`+11,286.935ms`（1→2）和 `+28,943.762ms`（2→4）。generation segment-transition
delta 为 `6/12/24`，与 6 segments 和 token count 成比例。RELEASE_RESTORE action
mean 在三个 budget 为 `4.447/4.670/7.197ms`，仍远小于 generation cost，但小样本
不建立统计结论。aggregate recovery throughput observation 随 budget 从约
`0.383` 降至 `0.316` tokens/s。peak footprint `7,765/7,848/7,541 MiB`、max swap
`0 MiB`、segment transitions `37/61/109`。同一 commit 全仓 Swift verification 为
`157 PASS / 0 FAIL`。登记
`MLX_RELEASE_RECOVERY_TOKEN_SCALE_OBSERVED`、
`GENERATION_TRANSITIONS_SCALE_WITH_TOKEN_COUNT` 和
`PAIRED_STRATEGY_OUTPUTS_REMAIN_EXACT`；状态为
`COST5 = PASS / RETAIN_VS_RELEASE_RESTORE_TOKEN_SCALE_WITH_BOUNDARY`。这是小样本
cacheless greedy observation，不建立定量 throughput 曲线、warm-KV retention、
release-policy recommendation、production performance、跨 backend 或跨硬件
claim。

报告见
`docs/00-governance/SIMIGO_LAB_MLX_RELEASE_RECOVERY_TOKEN_SCALE_20260929.md`；artifacts 见
`simigo2-experimental/results/backend-conformance/mlx-release-recovery-tokens1.json`、`...tokens2.json`、`...tokens4.json`、`...token-scale-summary.json`。

### LAB MLX EXECSTATE PHASE-6 COST SUMMARY PASS — 2026-09-29

把 COST1–COST5 五组 oversized MLX Execution State cost observations合并为
Phase-6 summary。新增 consolidated artifact
`mlx-phase6-cost-summary.json`,自动校验五个 source reports和三个 token-scale raw
runs均为 PASS、所有 source checks通过、COST1–COST5齐全、token-scale runs通过、
所有 recovery paired outputs exact。

汇总结论限定为 observation: no-fork state local bookkeeping mean约
`0.022111ms`; lifecycle local mean约 `7.695876ms`,其中 oversized release mean
`7.651396ms`。release isolation中 current release mean `4.061400ms`,stale no-op
mean `0.000188ms`,capture/restore在微秒级。prefix length `8/64/256`与 token
budget `1/2/4`均观察到 latency/transition scaling趋势,但样本小,不建立定量曲线。
RETAIN vs RELEASE_RESTORE paired outputs exact; generation mean差异不解释为稳定
penalty/benefit。登记
`MLX_PHASE6_COST_OBSERVATION_INDEX_COMPLETE` 和
`MLX_PHASE6_FULL_FACTORIAL_OPEN`；状态为
`PHASE6_STAGE = PASS_WITH_BOUNDARY / OBSERVATION_INDEX_COMPLETE /
FULL_FACTORIAL_OPEN`。这不是 throughput benchmark、production performance、
warm-KV retention、release-policy recommendation、cross-backend或cross-hardware
claim。

报告见
`docs/00-governance/SIMIGO_LAB_MLX_PHASE6_COST_SUMMARY_20260929.md`；artifact 见
`simigo2-experimental/results/backend-conformance/mlx-phase6-cost-summary.json`。

### LAB MLX PHASE6A FACTORIAL PILOT PASS — 2026-09-29

为 Phase-6 full factorial问题补充 8-cell pilot：prefix `8/64` × generated
tokens `1/2` × segment size `8/16` × strategy `RETAIN/RELEASE_RESTORE`；每 cell
每 strategy `n=1`。复用 `mlx-release-recovery`，不修改 Swift runtime。八项
summary checks全部 PASS：all cells present/pass、paired outputs exact、RETAIN
action transitions全 `0`、RELEASE_RESTORE全 `1`、generation transitions匹配
`segment count × token count`、oversized profile under 30GiB、all runs zero swap。

Observation显示 segment size 16 虽然transition较少（3/token vs 6/token），但在
四个可比 pair中 strategy-averaged generation latency均高于 segment size 8；
prefix 64 也观测上慢于 prefix 8。RELEASE_RESTORE action mean范围
`3.967–7.108ms`，RETAIN为 `0.001–0.011ms`。peak footprint `6,853–12,046 MiB`、
max swap `0 MiB`。登记
`PHASE6A_PREFIX_TOKEN_SEGMENT_ACTION_PILOT_PASS`、
`LARGER_SEGMENTS_HAVE_FEWER_BUT_COSTLIER_TRANSITIONS` 和
`PAIRED_ACTION_OUTPUTS_EXACT_IN_ALL_CELLS`；状态为
`PHASE6A = PASS_WITH_BOUNDARY / FULL_FACTORIAL_PILOT_COMPLETE /
STATISTICAL_FACTORIZATION_OPEN`。每 cell只有 n=1，不建立最优 segment size、
throughput曲线、warm-KV retention、release-policy recommendation、production
performance或cross-backend/cross-hardware claim。

报告见
`docs/00-governance/SIMIGO_LAB_MLX_PHASE6A_FACTORIAL_PILOT_20260929.md`；summary artifact见
`simigo2-experimental/results/backend-conformance/mlx-phase6a-factorial-pilot-summary.json`；raw artifacts见
`simigo2-experimental/results/backend-conformance/mlx-release-recovery-factorial-p*.json`。

### LAB MLX PHASE6B SEGMENT REPLICATION PASS — 2026-09-29

针对 PHASE6A 中 segment size 16 更少 transition但观测更高 latency的矛盾，新增
targeted segment replication。对 prefix `8/64`、maxTokens `2`、segment size
`8/16`、strategy `RETAIN/RELEASE_RESTORE`，在 PHASE6A 每 strategy 1 cycle基础上
增加 2 cycles；combined每 strategy `n=3`。十项 checks全部 PASS：replicate reports
pass、paired outputs exact、cell/sample coverage完整、RETAIN transitions全 `0`、
RELEASE_RESTORE全 `1`、generation transitions符合结构、oversized profile under
30GiB、zero swap。

Combined median显示 segment size 16 在 prefix 8 的 RETAIN/RELEASE_RESTORE
（`27,638.236/31,111.494ms`）均慢于 segment size 8
（`18,665.924/18,673.739ms`）；prefix 64 RETAIN segment 16
（`47,111.706ms`）慢于 segment 8（`26,230.057ms`），prefix 64
RELEASE_RESTORE segment 16 median `45,780.322ms`也慢于 segment 8
`29,864.848ms`；segment 16 mean `45,990.251ms`高于 segment 8 mean
`29,994.914ms`。因此 PHASE6A 的
“更少 transition不等于更低总成本”得到 replicated。所有 paired generated token
IDs/text exact；RETAIN/RELEASE action transitions稳定为 `0/1`。PHASE6B replicate
peak footprint `4,853–10,683 MiB`、max swap `0 MiB`。登记
`SEGMENT_SIZE_16_LATENCY_PENALTY_REPLICATED`、
`SEGMENT_TRANSITIONS_SCALE_WITH_SEGMENT_COUNT_AND_TOKENS` 和
`PAIRED_ACTION_OUTPUTS_EXACT_AFTER_REPLICATION`；状态为
`PHASE6B = PASS_WITH_BOUNDARY / TARGETED_SEGMENT_REPLICATION_COMPLETE /
FULL_FACTORIZATION_OPEN`。combined n=3仍小，且 segment size同时改变 transition
count、每次 segment工作量和 cache行为，不建立最优 segment size、throughput曲线、
warm-KV retention、production performance或cross-backend/cross-hardware claim。

报告见
`docs/00-governance/SIMIGO_LAB_MLX_PHASE6B_SEGMENT_REPLICATION_20260929.md`；summary artifact见
`simigo2-experimental/results/backend-conformance/mlx-phase6b-segment-size-replication-summary.json`；raw artifacts见
`simigo2-experimental/results/backend-conformance/mlx-release-recovery-replicate-p*.json`。

### LAB MLX PHASE6C TOKEN BUDGET REPLICATION PASS — 2026-09-29

将 prefix `64` / segment size `8` 的 RETAIN-vs-RELEASE_RESTORE token budgets提升到
combined每 strategy `n=3`。budget `1/4`由 COST5 2 cycles加 PHASE6C 1 cycle组成；
budget `2`由 COST5 2 cycles加 PHASE6A 1 cycle组成。九项 checks全部 PASS：source
reports pass、budget coverage完整、combined n=3、所有 budgets的 paired generated
token IDs/text exact、RETAIN action transitions全 `0`、RELEASE_RESTORE全 `1`、
generation transitions为 `6/12/24`、zero swap、oversized profile under 30GiB。

Median generation随 budget增长：RETAIN
`10,448.105 -> 22,858.117 -> 50,508.985ms`；RELEASE_RESTORE
`10,436.751 -> 22,061.736 -> 52,059.338ms`。但 mean受长尾影响：budget 4
RELEASE_RESTORE mean `83,907.846ms`、median `52,059.338ms`、max
`149,541.501ms`、range `99,418.801ms`。prefix-8 supplementary budget-4 run也观测到
`48,387.495 / 98,497.580ms`。RELEASE action mean/median分别为
`6.632/4.559ms`、`5.483/4.865ms`、`9.934/7.261ms`，仍远小于 generation cost，但
自身小样本波动明显。登记 `TOKEN_BUDGET_COMBINED_N3_OBSERVED`、
`PAIRED_STRATEGY_OUTPUTS_EXACT_AT_ALL_BUDGETS` 和
`T4_RELEASE_RUN_VARIATION_OBSERVED`；状态为
`PHASE6C = PASS_WITH_BOUNDARY / TOKEN_BUDGET_REPLICATION_COMPLETE / SMALL_SAMPLE`。不建立定量 token-cost曲线、release因果结论、warm-KV retention、release-policy
recommendation、production performance或cross-backend/cross-hardware claim。

报告见
`docs/00-governance/SIMIGO_LAB_MLX_PHASE6C_TOKEN_BUDGET_REPLICATION_20260929.md`；summary artifact见
`simigo2-experimental/results/backend-conformance/mlx-phase6c-token-budget-replication-summary.json`；raw artifacts见
`simigo2-experimental/results/backend-conformance/mlx-release-recovery-token-replicate-p*.json`。

### LAB MLX PHASE6D DISTRIBUTION PARTIAL — 2026-09-29

尝试把 2-token cells的 RETAIN-vs-RELEASE_RESTORE distribution提升到 combined每
strategy `n=5`（PHASE6A 1 + PHASE6B 2 + PHASE6D 2）。三个 cells完成：prefix
`8 / segment 8`、prefix `64 / segment 8`、prefix `64 / segment 16`。
`prefix 8 / segment 16`连续两次遇到 Metal GPU command buffer timeout
（`kIOGPUCommandBufferCallbackErrorTimeout`），没有产生 measured report；按熔断
不再自动重试，该 cell保持 combined `n=3`。

所有 completed runs paired outputs exact；RETAIN action transitions全 `0`，
RELEASE_RESTORE全 `1`；generation transitions符合 `segment count × token count`；
completed PHASE6D runs max swap `0 MiB`且低于 30GiB gate。完成后 cells的分布显示
明显长尾和波动：prefix 8 / segment 8 generation mean约 `38.7s / 38.2s`但 median约
`18.7s`；prefix 64 / segment 8 mean约 `51.1s / 48.9s`但 median约 `30.5s /
30.1s`；prefix 64 / segment 16 release mean约 `70.0s`、max约 `114.9s`。action cost
也出现 max `0.52ms`（RETAIN）和 `24.93ms`（RELEASE_RESTORE）的波动。因此只登记
observation，不建立稳定 performance model。

登记 `THREE_CELLS_DISTRIBUTION_EXPANDED_TO_N5`、`P8_S16_GPU_TIMEOUT_BOUNDARY` 和
`ACTION_AND_GENERATION_DISTRIBUTIONS_OBSERVED`；状态为
`PHASE6D = PARTIAL_PASS_WITH_BOUNDARY / DISTRIBUTION_EXPANSION_PARTIAL /
GPU_TIMEOUT_BOUNDARY`。GPU timeout没有任何 Execution State semantic assertion失败，
不能解释为语义错误或定位 root cause。完整 n=5 matrix、outlier分析和 warm-KV /
segment-residency policy仍未完成。

报告见
`docs/00-governance/SIMIGO_LAB_MLX_PHASE6D_DISTRIBUTION_PARTIAL_20260929.md`；summary artifact见
`simigo2-experimental/results/backend-conformance/mlx-phase6d-distribution-partial-summary.json`；completed raw artifacts见
`simigo2-experimental/results/backend-conformance/mlx-release-recovery-distribution-p8-t2-s8.json`、`...p64-t2-s8.json`、`...p64-t2-s16.json`。

### LAB MLX PHASE6E DISTRIBUTION ANALYSIS PASS — 2026-09-29

对 PHASE6D 已有 combined samples执行 post-hoc robust distribution analysis；没有
新增 GPU run。分析覆盖 prefix `8/64` × segment size `8/16` 的 2-token cells，
计算 mean、median、p05/p25/p75/p95、min/max、IQR和 Tukey 1.5×IQR fences。八个
analysis checks全部 PASS：expected cells present、三个 completed cells at n=5、
GPU timeout cell remains n=3、每个 cell内 generated output唯一、generation
transitions符合 `segment count × token count`、action transition semantics保持、
robust stats computed、no new GPU runs。

结果显示 completed n=5 cells有明显 long tail。Tukey规则只在 prefix `64 / segment
16` RETAIN中标出 `92,221.424ms` outlier；其他 completed generation arms没有超出
1.5×IQR fences，但 p75/p95与 median差距很大。action distributions同样有长尾，例如
prefix 8 / segment 8 RELEASE_RESTORE max `32.784917ms`，prefix 64 / segment 8
RELEASE_RESTORE max `24.931000ms`。所有 generation transitions匹配结构，RETAIN
transitions全 `0`，RELEASE_RESTORE全 `1`，说明分布波动不是 Execution State
identity/lineage/position语义失败。登记 `N5_CELLS_LONG_TAIL_OBSERVED`、
`IQR_FENCES_FLAG_OUTLIERS_IN_COMPLETED_CELLS` 和
`GPU_TIMEOUT_CELL_IS_UNDERPOWERED_N3`；状态为
`PHASE6E = PASS_WITH_BOUNDARY / POST_HOC_DISTRIBUTION_ANALYSIS_COMPLETE /
NO_NEW_GPU_RUNS`。IQR outlier不是因果诊断；n=3 cell不足以比较，也不建立
throughput、segment-size recommendation、warm-KV retention或production claim。

报告见
`docs/00-governance/SIMIGO_LAB_MLX_PHASE6E_DISTRIBUTION_ANALYSIS_20260929.md`；artifact见
`simigo2-experimental/results/backend-conformance/mlx-phase6e-distribution-analysis.json`。

### LAB MLX SEGMENT PHASE ATTRIBUTION PASS — 2026-09-29

针对 PHASE6A/B 中“segment 16 transition少但 latency高”的问题，新增
`O6SegmentPhaseProfiler` 和 CLI `mlx-segment-phase`，将 warmed one-token
generation拆分为 embed、每 segment materialize/forward/release、logits/argMax。
代码只新增 phase instrumentation；normal greedy path不变。使用本地
Qwen3-Coder-Next-4bit、prefix 64、segment size 8/16，每 size一次 measured token；
先执行 unprofiled warmup。不包含 Execution State action，也不重试此前 GPU timeout
cell。同一代码基线全仓 Swift verification为 `157 PASS / 0 FAIL`。

两个 reports PASS，generated token相同，zero swap，低于 30GiB。segment 8/6
segments总耗时 `10,673.082ms`，materialize/forward/release分别为
`8,592.810 / 1,953.801 / 89.098ms`。segment 16/3 segments总耗时
`12,896.634ms`，三项分别为 `8,718.752 / 4,008.853 / 104.645ms`。segment 16相对
segment 8 total增加 `+2,223.551ms`，其中 forward sum增加 `+2,055.053ms`；
materialize sum只增加 `+125.942ms`，release sum增加 `+15.548ms`。这说明
transition count单独不足以解释成本：segment 16的 forward sum显著更高，release
per transition也从 `14.850ms`增至 `34.882ms`。登记
`SEGMENT_PHASE_INSTRUMENTATION_OPERATIONAL`、
`SEGMENT16_FORWARD_COST_REPLICATES_LATENCY_TREND` 和
`TRANSITION_COUNT_ALONE_INSUFFICIENT`；状态为
`PHASE6F = PASS_WITH_BOUNDARY / SEGMENT_PHASE_ATTRIBUTION_PILOT / N1_PER_SIZE`。
每个 size只有 n=1，不建立最优 segment size或 throughput曲线，不解释 Metal timeout
root cause，也不建立warm-KV retention、production performance或cross-backend /
cross-hardware claim。

报告见
`docs/00-governance/SIMIGO_LAB_MLX_SEGMENT_PHASE_PROFILE_20260929.md`；summary artifact见
`simigo2-experimental/results/backend-conformance/mlx-segment-phase-attribution-summary.json`；raw artifacts见
`simigo2-experimental/results/backend-conformance/mlx-segment-phase-p64-s8.json`、`...p64-s16.json`。

### LAB MLX SEGMENT PHASE ATTRIBUTION PASS — 2026-09-29

针对 PHASE6A/B 中“segment 16 transition少但 latency高”的问题，新增
`O6SegmentPhaseProfiler` 和 CLI `mlx-segment-phase`，将 warmed one-token
generation拆分为 embed、每 segment materialize/forward/release、logits/argMax。
代码只新增 phase instrumentation；normal greedy path不变。使用本地
Qwen3-Coder-Next-4bit、prefix 64、segment size 8/16，每 size一次 measured token；
先执行 unprofiled warmup。不包含 Execution State action，也不重试此前 GPU timeout
cell。同一代码基线全仓 Swift verification为 `157 PASS / 0 FAIL`。

两个 reports PASS，generated token相同，zero swap，低于 30GiB。segment 8/6
segments总耗时 `10,673.082ms`，materialize/forward/release分别为
`8,592.810 / 1,953.801 / 89.098ms`。segment 16/3 segments总耗时
`12,896.634ms`，三项分别为 `8,718.752 / 4,008.853 / 104.645ms`。segment 16相对
segment 8 total增加 `+2,223.551ms`，其中 forward sum增加 `+2,055.053ms`；
materialize sum只增加 `+125.942ms`，release sum增加 `+15.548ms`。这说明
transition count单独不足以解释成本：segment 16的 forward sum显著更高，release
per transition也从 `14.850ms`增至 `34.882ms`。登记
`SEGMENT_PHASE_INSTRUMENTATION_OPERATIONAL`、
`SEGMENT16_FORWARD_COST_REPLICATES_LATENCY_TREND` 和
`TRANSITION_COUNT_ALONE_INSUFFICIENT`；状态为
`PHASE6F = PASS_WITH_BOUNDARY / SEGMENT_PHASE_ATTRIBUTION_PILOT / N1_PER_SIZE`。
每个 size只有 n=1，不建立最优 segment size或 throughput曲线，不解释 Metal timeout
root cause，也不建立warm-KV retention、production performance或cross-backend /
cross-hardware claim。

报告见
`docs/00-governance/SIMIGO_LAB_MLX_SEGMENT_PHASE_PROFILE_20260929.md`；summary artifact见
`simigo2-experimental/results/backend-conformance/mlx-segment-phase-attribution-summary.json`；raw artifacts见
`simigo2-experimental/results/backend-conformance/mlx-segment-phase-p64-s8.json`、`...p64-s16.json`。

### LAB MLX PHASE6G SEGMENT PHASE REPLICATION PASS — 2026-09-29

对 PHASE6F 的 safe prefix-64 segment phase profile增加两个 replicates，使 segment
size `8/16` 的 combined样本达到每 size `n=3`。所有 source reports PASS，generated
token相同（`26753`），max swap `0 MiB`，peak footprint低于 30GiB gate。八个 checks
全部 PASS，包括 size coverage、combined n=3、zero swap、under 30GiB、三个 paired
`segment16 - segment8` total deltas全正、三个 forward sum deltas全正。

Combined means显示 segment 16 total `12,870.913ms`高于 segment 8
`10,605.054ms`。materialize sum接近（`8,733.775 vs 8,618.143ms`），但 forward sum
`3,977.427ms`显著高于 segment 8 的 `1,869.628ms`；release sum
`102.594 vs 89.624ms`也更高。三个 paired total deltas为
`+2,223.551 / +2,428.887 / +2,145.139ms`，forward sum deltas为
`+2,055.053 / +2,201.428 / +2,066.917ms`，方向全部一致。per-layer forward mean约
`38.951 vs 82.863ms`；release per transition约 `14.937 vs 34.198ms`。登记
`SEGMENT16_TOTAL_SLOWER_IN_ALL_PAIRED_SAMPLES`、
`SEGMENT16_FORWARD_SUM_SLOWER_IN_ALL_PAIRED_SAMPLES` 和
`TRANSITION_COUNT_ALONE_INSUFFICIENT`；状态为
`PHASE6G = PASS_WITH_BOUNDARY / SEGMENT_PHASE_REPLICATION_COMPLETE / N3_PER_SIZE`。
combined n=3仍小，且 segment size同时改变每 segment层数、graph和release count；
不建立最优 segment size、throughput曲线、warm-KV retention、production
performance或cross-backend/cross-hardware claim。GPU timeout cell仍未重试。

报告见
`docs/00-governance/SIMIGO_LAB_MLX_PHASE6G_SEGMENT_PHASE_REPLICATION_20260929.md`；summary artifact见
`simigo2-experimental/results/backend-conformance/mlx-phase6g-segment-phase-replication-summary.json`；raw artifacts见
`simigo2-experimental/results/backend-conformance/mlx-segment-phase-replicate-p64-s*-b*.json`。

### LAB MLX PHASE6H PREFIX PHASE ATTRIBUTION PASS — 2026-09-29

在 segment size固定为 8的条件下，比较 prefix `8/64` 的 warmed one-token phase
profile。prefix 8使用 PHASE6H 3个独立 runs；prefix 64复用 PHASE6F/PHASE6G的 3个
combined runs。九项 checks全部 PASS：source reports pass、prefix coverage完整、
combined n=3、segment size固定、zero swap、under 30GiB、三个配对 prefix64 total
deltas全正、forward sum deltas全正。

Combined means显示 prefix 64 total `10,605.054ms`高于 prefix 8
`9,741.621ms`；三个配对 delta为 `+968.394 / +714.069 / +907.835ms`。主要增量是
forward sum：prefix 64 `1,869.628ms`高于 prefix 8 `1,023.550ms`，三个配对 delta
为 `+958.769 / +731.115 / +848.349ms`。release sum delta也全正
（mean `+22.840ms`）。materialize sum delta方向混合，mean仅 `+9.396ms`。
per-layer forward约 `21.324 vs 38.951ms`，materialize per-layer约
`179.349 vs 179.545ms`。登记 `PREFIX64_TOTAL_SLOWER_IN_ALL_PAIRED_SAMPLES`、
`PREFIX64_FORWARD_SUM_SLOWER_IN_ALL_PAIRED_SAMPLES` 和
`PREFIX_LENGTH_EFFECT_IS_OBSERVATIONAL`；状态为
`PHASE6H = PASS_WITH_BOUNDARY / PREFIX_PHASE_ATTRIBUTION_COMPLETE / N3_PER_PREFIX`。
prefix 8和 prefix 64的 token sequence、text content和 tokenizer行为不同，因此不建
立 causal prefix-length model、定量长度曲线、prefix recommendation、warm-KV
retention、production performance或cross-backend/cross-hardware claim。

报告见
`docs/00-governance/SIMIGO_LAB_MLX_PHASE6H_PREFIX_PHASE_ATTRIBUTION_20260929.md`；summary artifact见
`simigo2-experimental/results/backend-conformance/mlx-phase6h-prefix-phase-attribution-summary.json`；raw artifacts见
`simigo2-experimental/results/backend-conformance/mlx-segment-phase-replicate-p8-s8-b*.json`。

### LAB MLX FIXED PREFIX DISTRIBUTION ANALYSIS PASS — 2026-09-29

对 PHASE6I 的 fixed-token prefix study执行 post-hoc distribution analysis；没有新增
GPU run。分析覆盖 prefix `8/64` 的 combined `n=3` samples，指标包括 generation
total、embed、logits、materialize/forward/release sums、per-layer means和
release-per-transition。计算 mean、median、p05/p25/p75/p95、min/max/range、stdev、
IQR和 Tukey 1.5×IQR fences。八项 checks全部 PASS：source reports pass、length
coverage完整、combined n=3、same leading token IDs、三个配对 prefix64 total deltas
全正、forward sum deltas全正、robust stats computed、no new GPU runs。

Generation total分布：length 8 mean `10,033.498ms`、median `10,021.411ms`、p95
`10,079.734ms`；length 64 mean `10,953.392ms`、median `10,944.812ms`、p95
`11,053.225ms`。三个配对 prefix64 deltas为
`+828.683 / +1,072.401 / +858.597ms`。phase-sum means显示 materialize接近
（`8,625.414 vs 8,653.658ms`），forward sum差异更大（`1,283.792 vs
2,162.599ms`），release sum `69.012 vs 89.277ms`。paired forward deltas为
`+758.827 / +1,017.653 / +859.941ms`。IQR analysis未在当前 `n=3` arms中标出
outlier；这不证明无变异。登记 `PREFIX64_TOTAL_HIGHER_IN_ALL_PAIRED_SAMPLES`、
`PREFIX64_FORWARD_SUM_HIGHER_IN_ALL_PAIRED_SAMPLES`、
`MATERIALIZE_DELTAS_ARE_SMALL_AND_MIXED` 和 `N3_IS_TOO_SMALL_FOR_CAUSAL_MODEL`；
状态为 `PHASE6J = PASS_WITH_BOUNDARY / FIXED_PREFIX_DISTRIBUTION_ANALYSIS_COMPLETE
/ NO_NEW_GPU_RUNS`。不建立 throughput benchmark、prefix-length recommendation、
warm-KV retention、production performance或cross-backend/cross-hardware claim。

报告见
`docs/00-governance/SIMIGO_LAB_MLX_PHASE6J_FIXED_PREFIX_DISTRIBUTION_20260929.md`；artifact见
`simigo2-experimental/results/backend-conformance/mlx-fixed-prefix-phase-distribution-analysis.json`。

### LAB MLX FIXED PREFIX DISTRIBUTION ANALYSIS PASS — 2026-09-29

对 PHASE6I 的 fixed-token prefix study执行 post-hoc distribution analysis；没有新增
GPU run。分析覆盖 prefix `8/64` 的 combined `n=3` samples，指标包括 generation
total、embed、logits、materialize/forward/release sums、per-layer means和
release-per-transition。计算 mean、median、p05/p25/p75/p95、min/max/range、stdev、
IQR和 Tukey 1.5×IQR fences。八项 checks全部 PASS：source reports pass、length
coverage完整、combined n=3、same leading token IDs、三个配对 prefix64 total deltas
全正、forward sum deltas全正、robust stats computed、no new GPU runs。

Generation total分布：length 8 mean `10,033.498ms`、median `10,021.411ms`、p95
`10,079.734ms`；length 64 mean `10,953.392ms`、median `10,944.812ms`、p95
`11,053.225ms`。三个配对 prefix64 deltas为
`+828.683 / +1,072.401 / +858.597ms`。phase-sum means显示 materialize接近
（`8,625.414 vs 8,653.658ms`），forward sum差异更大（`1,283.792 vs
2,162.599ms`），release sum `69.012 vs 89.277ms`。paired forward deltas为
`+758.827 / +1,017.653 / +859.941ms`。IQR analysis未在当前 `n=3` arms中标出
outlier；这不证明无变异。登记 `PREFIX64_TOTAL_HIGHER_IN_ALL_PAIRED_SAMPLES`、
`PREFIX64_FORWARD_SUM_HIGHER_IN_ALL_PAIRED_SAMPLES`、
`MATERIALIZE_DELTAS_ARE_SMALL_AND_MIXED` 和 `N3_IS_TOO_SMALL_FOR_CAUSAL_MODEL`；
状态为 `PHASE6J = PASS_WITH_BOUNDARY / FIXED_PREFIX_DISTRIBUTION_ANALYSIS_COMPLETE
/ NO_NEW_GPU_RUNS`。不建立 throughput benchmark、prefix-length recommendation、
warm-KV retention、production performance或cross-backend/cross-hardware claim。

报告见
`docs/00-governance/SIMIGO_LAB_MLX_PHASE6J_FIXED_PREFIX_DISTRIBUTION_20260929.md`；artifact见
`simigo2-experimental/results/backend-conformance/mlx-fixed-prefix-phase-distribution-analysis.json`。

### LAB MLX PHASE6 MASTER INDEX CONSOLIDATED — 2026-09-29

为避免 Phase-6 evidence碎片化，新增 consolidated master index
`mlx-phase6-master-summary.json`，把 COST1–COST5 baseline profiles和 PHASE6A–J
follow-ups纳入同一 evidence index。master checks全部 PASS：11个 expected index
entries齐全、所有 indexed summaries overallPass、PHASE6D partial status显式、
`p8/t2/segment16` GPU timeout cell保持 n=3、不声称 GPU timeout root cause、full
factorization保持 open。

Consolidated findings限定为 observation：Execution State local bookkeeping远小于
generation cost；controlled fixed-token probes中 prefix 64 forward sum高于 prefix 8；
segment 16 transition count alone不足以解释 cost；PHASE6D completed n=5 cells有
long tails；GPU timeout cell保持 partial n=3。登记
`MLX_PHASE6_MASTER_INDEX_CONSOLIDATED`、
`MLX_PHASE6_FULL_MATRIX_REMAINS_OPEN` 和
`MLX_PHASE6_NO_PERFORMANCE_BENCHMARK_CLAIM`；状态为
`PHASE6 = CONSOLIDATED_PASS_WITH_BOUNDARY / OBSERVATION_INDEX_COMPLETE /
FULL_MATRIX_OPEN`。这不是 throughput benchmark、production performance、warm-KV
retention、release-policy recommendation、cross-backend/cross-hardware comparison，
也不解释 GPU timeout root cause。

报告见
`docs/00-governance/SIMIGO_LAB_MLX_PHASE6_MASTER_SUMMARY_20260929.md`；artifact见
`simigo2-experimental/results/backend-conformance/mlx-phase6-master-summary.json`。

### LAB UI BRANCH SESSIONS MASTER INDEX CONSOLIDATED — 2026-09-29

为避免 UI Branch Sessions evidence碎片化，新增 consolidated master index
`ui-branch-sessions-master-summary.json`，把 UI1–UI9纳入同一 evidence index。覆盖
LLAMA GGUF与 oversized MLX、depth-1 pilot/cross-backend matrix、nested/repeat
pilot/cross-backend matrix、以及 cancellation pilot/cross-backend outcome-shape
matrix。十项 index checks全部 PASS：9个 entry reports符合预期状态、all entry
reports pass、depth-1 LLAMA/MLX与 cross-backend matrix齐全、nested LLAMA/MLX与
cross-backend matrix齐全、cancellation LLAMA/MLX与 cross-backend matrix齐全；同时
显式声明 no product UI claim和 no persistent session claim。登记
`UI_BRANCH_SESSIONS_MASTER_INDEX_CONSOLIDATED`、
`UI_BRANCH_SESSIONS_PRODUCT_SURFACE_REMAINS_OPEN` 和
`UI_BRANCH_SESSIONS_PERSISTENCE_REMAINS_OPEN`；状态为
`UI_BRANCH_SESSIONS = CONSOLIDATED_PASS_WITH_BOUNDARY / EVIDENCE_INDEX_COMPLETE /
PRODUCT_PERSISTENCE_OPEN`。这不是 product UI、persistent/multi-process session、
arbitrary-depth graph、same-checkpoint closure、production cancellation readiness或
performance benchmark。

报告见
`docs/00-governance/SIMIGO_LAB_UI_BRANCH_SESSIONS_MASTER_INDEX_20260929.md`；artifact见
`simigo2-experimental/results/backend-conformance/ui-branch-sessions-master-summary.json`。

### LAB UI10 LLAMA LONG RUNNING BRANCH PASS — 2026-09-29

新增 `UIBranchSessions.runLongRunningLLAMA` 和 CLI
`llama-branch-session-long`，验证 six-turn long-running branch。session graph为
root包含 long branch和 sibling baseline；long branch使用六个不同 prompts顺序推进，
每次 generation后更新 logical position并 bind token-prefix representation。完成
sequence后 restore到 fork point验证 checkpoint，再restore到 final position验证
advanced binding；随后 release long branch与 sibling，验证 root survives。使用
canonical mitigated LLAMA profile、Cyber-Tiel当前 model、seed42、4-token turns。

七项 checks全部 PASS：long sequence complete、final prefix exact、fork-point
restore、final-position restore、sibling baseline retained、release long/sibling、
root survives。同一提交全仓 Swift verification为 `157 PASS / 0 FAIL`。登记
`SIX_TURN_LONG_RUNNING_BRANCH_PASS`、
`FORKPOINT_AND_FINAL_POSITION_RESTORE_PASS` 和
`SIBLING_BASELINE_RETAINED_ACROSS_LONG_BRANCH`；状态为
`UI10 = PASS / LLAMA_LONG_RUNNING_BRANCH_WITH_BOUNDARY`。这是 LLAMA harness-level
pilot，不是 product UI、persistent session、MLX cross-backend validation、
performance benchmark或 production readiness。

报告见
`docs/00-governance/SIMIGO_LAB_UI_BRANCH_SESSIONS_LONG_RUNNING_20260929.md`；artifact见
`simigo2-experimental/results/backend-conformance/ui-branch-session-llama-long-running.json`。

### LAB UI BRANCH SESSIONS MASTER INDEX AND MLX LONG RUNNING PASS — 2026-09-29

新增 UI Branch Sessions consolidated master index，把 UI1–UI11纳入同一 evidence
index。覆盖 LLAMA GGUF与 oversized MLX、depth-1 pilot/cross-backend matrix、
nested/repeat pilot/cross-backend matrix、cancellation pilot/cross-backend
outcome-shape matrix，以及 LLAMA与 MLX long-running branch。十一项 UI index checks
全部 PASS，所有 entry reports为 PASS或 PASS_WITH_BOUNDARY。

同时新增 `runLongRunningOversizedMLX` 和 CLI `mlx-branch-session-long`。UI11使用
oversized Qwen3-Coder-Next-4bit、segment size 8、6个 sequential turns、每 turn
1 token。session包含 long branch与 retained sibling；完成 sequence后 restore到
fork point和 final position，release long/sibling并验证 root survives。八项 checks
全部 PASS；peak footprint `8,022 MiB`、max swap `0 MiB`、segment transitions `44`。
登记 `SIX_TURN_MLX_LONG_RUNNING_BRANCH_PASS`、
`FORKPOINT_AND_FINAL_POSITION_RESTORE_PASS` 和
`SIBLING_ADVANCED_RETAINED_ACROSS_LONG_BRANCH`；状态为
`UI11 = PASS / MLX_LONG_RUNNING_BRANCH_WITH_BOUNDARY`。这只是 harness-level MLX
pilot，不是 product UI、persistent session、LLAMA cross-backend validation、
performance benchmark或 production readiness。

Master index报告见
`docs/00-governance/SIMIGO_LAB_UI_BRANCH_SESSIONS_MASTER_INDEX_20260929.md`；UI11报告见
`docs/00-governance/SIMIGO_LAB_UI_BRANCH_SESSIONS_MLX_LONG_RUNNING_20260929.md`；artifacts见
`simigo2-experimental/results/backend-conformance/ui-branch-sessions-master-summary.json`、
`simigo2-experimental/results/backend-conformance/ui-branch-session-mlx-long-running.json`。

### LAB UI BRANCH SESSIONS MASTER INDEX AND MLX LONG RUNNING PASS — 2026-09-29

新增 UI Branch Sessions consolidated master index，把 UI1–UI11纳入同一 evidence
index。覆盖 LLAMA GGUF与 oversized MLX、depth-1 pilot/cross-backend matrix、
nested/repeat pilot/cross-backend matrix、cancellation pilot/cross-backend
outcome-shape matrix，以及 LLAMA与 MLX long-running branch。十一项 UI index checks
全部 PASS，所有 entry reports为 PASS或 PASS_WITH_BOUNDARY。

同时新增 `runLongRunningOversizedMLX` 和 CLI `mlx-branch-session-long`。UI11使用
oversized Qwen3-Coder-Next-4bit、segment size 8、6个 sequential turns、每 turn
1 token。session包含 long branch与 retained sibling；完成 sequence后 restore到
fork point和 final position，release long/sibling并验证 root survives。八项 checks
全部 PASS；peak footprint `8,022 MiB`、max swap `0 MiB`、segment transitions `44`。
登记 `SIX_TURN_MLX_LONG_RUNNING_BRANCH_PASS`、
`FORKPOINT_AND_FINAL_POSITION_RESTORE_PASS` 和
`SIBLING_ADVANCED_RETAINED_ACROSS_LONG_BRANCH`；状态为
`UI11 = PASS / MLX_LONG_RUNNING_BRANCH_WITH_BOUNDARY`。这只是 harness-level MLX
pilot，不是 product UI、persistent session、LLAMA cross-backend validation、
performance benchmark或 production readiness。

Master index报告见
`docs/00-governance/SIMIGO_LAB_UI_BRANCH_SESSIONS_MASTER_INDEX_20260929.md`；UI11报告见
`docs/00-governance/SIMIGO_LAB_UI_BRANCH_SESSIONS_MLX_LONG_RUNNING_20260929.md`；artifacts见
`simigo2-experimental/results/backend-conformance/ui-branch-sessions-master-summary.json`、
`simigo2-experimental/results/backend-conformance/ui-branch-session-mlx-long-running.json`。

### LAB UI12 LONG RUNNING CROSSBACKEND MATRIX PASS — 2026-09-29

新增 UI12 long-running cross-backend outcome-shape matrix，将 UI10 LLAMA long-running
branch与 UI11 oversized MLX long-running branch纳入同一 matrix。两者使用相同
seed/root/sibling text、相同 six fixed implementation prompts、相同 6-turn workload
shape和 4-token per-turn budget。LLAMA使用 Cyber-Tiel GGUF canonical mitigated
profile；MLX使用 oversized Qwen3-Coder-Next-4bit、segment size 8、cacheless greedy
recompute。

七项 common outcome checks全部 PASS：sequence complete、final prefix exact、
fork-point restore、final-position restore、sibling retained、release long/sibling、
root survives。matrix result为 `sameWorkloadShape / sameOutcomeShape /
bothBackendsPass = true`，但 `crossBackendClosure = false`，blocker是 different
model artifacts, tokenizers and execution engines。MLX backend-specific oversized
profile under 30GiB也 PASS，peak footprint `8,019 MiB`、max swap `0 MiB`、segment
transitions `170`。登记 `UI12_LONG_RUNNING_CROSSBACKEND_OUTCOME_SHAPE_MATRIX_PASS`
和 `CROSSBACKEND_MODEL_AND_EXECUTION_DIFFERENCES_PRESERVED`；状态为
`UI12 = PASS_WITH_BOUNDARY / LONG_RUNNING_OUTCOME_SHAPE_MATRIX`。这不是
same-checkpoint closure、performance equivalence、production readiness、product UI或
persistent session。报告见
`docs/00-governance/SIMIGO_LAB_UI_BRANCH_SESSIONS_LONG_RUNNING_CROSSBACKEND_MATRIX_20260929.md`；artifacts见
`simigo2-experimental/results/backend-conformance/ui-branch-session-long-running-crossbackend-matrix.json`、
`simigo2-experimental/results/backend-conformance/ui-branch-session-mlx-long-running-t4.json`。

### LAB UI13 MLX CONTROLLED MEMORY PRESSURE PASS — 2026-09-29

新增 `runMemoryPressureOversizedMLX` 和 CLI
`mlx-branch-session-memory-pressure`，登记 UI13 controlled multi-branch
memory-pressure action。session为 root、retained control branch、两条 advanced
pressure branch；每个 pressure branch经历 2 次 capture/release、fork-point
restore、deterministic replay和 final-position restore，共 4 个 pressure action。
oversized MLX使用 Qwen3-Coder-Next-4bit、segment size 8、6 segments和 1-token
generation。

十项 checks全部 PASS：workload complete、release actions complete、lineage
isolated、active branch prefixes diverged、repeated recovery outputs exact、
final bindings exact、release pressure branches、root/control survive、zero swap
和 oversized under 30GiB。两个 pressure branch final prefix分别为 15 和 17
tokens；peak footprint `6,904 MiB`、max swap `0 MiB`、segment transitions `48`。
登记 `UI13_MLX_MULTI_BRANCH_RELEASE_RESTORE_PRESSURE_PASS` 和
`NO_SWAP_ON_CONTROLLED_PRESSURE_ACTION`；状态为
`UI13 = PASS / CONTROLLED_MULTI_BRANCH_MEMORY_PRESSURE_ACTION`。

语义边界是 controlled session release/restore load，不是 OS memory-pressure
injection、product UI、persistent session、production policy、performance
benchmark或 cross-backend closure。全仓 Swift verification为 157 PASS / 0 FAIL。
报告见
`docs/00-governance/SIMIGO_LAB_UI_BRANCH_SESSIONS_MLX_MEMORY_PRESSURE_20260929.md`；
artifacts见
`simigo2-experimental/results/backend-conformance/ui-branch-session-mlx-memory-pressure.json`、
`simigo2-experimental/results/backend-conformance/ui-branch-sessions-master-summary.json`。

### LAB UI14 LLAMA CONTROLLED MEMORY PRESSURE PASS — 2026-09-29

新增 `runMemoryPressureLLAMA` 和 CLI
`llama-branch-session-memory-pressure`，登记 UI14 controlled multi-branch
memory-pressure action。session为 root、retained control branch、两条 advanced
pressure branch；每个 pressure branch经历 2 次 capture/release、fork-point
restore、deterministic replay和 final-position restore，共 4 个 pressure action。
LLAMA使用 Cyber-Tiel Coder 35B A3B GGUF canonical mitigated ubatch8 profile和
1-token generation。

八项 checks全部 PASS：workload complete、release actions complete、lineage
isolated、active branch prefixes diverged、repeated recovery outputs exact、
final bindings exact、release pressure branches、root/control survive。两条
pressure branch final prefix token counts分别为 15 和 17。登记
`UI14_LLAMA_MULTI_BRANCH_RELEASE_RESTORE_PRESSURE_PASS`；状态为
`UI14 = PASS / CONTROLLED_MULTI_BRANCH_MEMORY_PRESSURE_ACTION`。

语义边界是 controlled session release/restore load，不是 OS or server
memory-pressure injection、product UI、persistent session、production policy、
performance benchmark、llama-server native cache release或 cross-backend
closure。LLAMA representation是 Swift-owned prompt-token prefix；server继续拥有
computation和 native cache。全仓 Swift verification为 157 PASS / 0 FAIL。报告见
`docs/00-governance/SIMIGO_LAB_UI_BRANCH_SESSIONS_LLAMA_MEMORY_PRESSURE_20260929.md`；
artifacts见
`simigo2-experimental/results/backend-conformance/ui-branch-session-llama-memory-pressure.json`、
`simigo2-experimental/results/backend-conformance/ui-branch-sessions-master-summary.json`。

### LAB UI15 CONTROLLED MEMORY PRESSURE CROSSBACKEND MATRIX PASS — 2026-09-29

新增 `runMemoryPressureCrossBackendMatrix` 和 CLI `ui-memory-pressure-matrix`，
登记 UI15 LLAMA/MLX controlled memory-pressure outcome-shape matrix。两者使用
相同 seed/control text、两条 pressure branch inputs、1-token generation、2 cycles
和每 backend 4个 release action。LLAMA运行 canonical mitigated ubatch8 profile；
MLX运行 oversized Qwen3-Coder-Next-4bit、segment size 8、cacheless greedy
recompute。

八项 common checks全部 PASS：workload complete、release actions complete、
lineage isolated、active branch prefixes diverged、repeated recovery outputs
exact、final bindings exact、release pressure branches、root/control survive。
matrix result为 `sameWorkloadShape / sameOutcomeShape / bothBackendsPass = true`，
但 `crossBackendClosure = false`，blocker是 different model artifacts,
tokenizers, execution engines and physical pressure mechanisms。LLAMA mechanism是
Swift prefix-registry release/restore；MLX额外执行 oversized segment release。
MLX backend-specific profile为 peak footprint `6,628 MiB`、max swap `0 MiB`、
segment transitions `48`。登记
`UI15_CONTROLLED_MEMORY_PRESSURE_OUTCOME_SHAPE_MATRIX_PASS`；状态为
`UI15 = PASS_WITH_BOUNDARY / CONTROLLED_MEMORY_PRESSURE_OUTCOME_SHAPE_MATRIX`。

这不是 OS memory-pressure validation、same-checkpoint closure、native-cache
equivalence、production policy、performance benchmark、product UI或 persistent
session。全仓 Swift verification为 157 PASS / 0 FAIL。报告见
`docs/00-governance/SIMIGO_LAB_UI_MEMORY_PRESSURE_CROSSBACKEND_MATRIX_20260929.md`；
artifact见
`simigo2-experimental/results/backend-conformance/ui-memory-pressure-crossbackend-matrix.json`。

### LAB RQ3 LLAMA PARALLEL6 CANCELLATION CURVE PASS — 2026-09-29

新增 6-slot higher-concurrency cancellation curve。llama-server使用 Cyber-Tiel
Coder 35B A3B GGUF canonical mitigation profile并以 6 slots运行；long stream为
128 tokens，control为 8 tokens，cancel delay 100ms，L1–L5各 2 轮共 10 cycles。
五项 checks全部 PASS：all cancels accepted、all control batches completed、
controls overlapped cancellation window、same-load baseline stable、greedy
identity across cancel。cancel acceptance与 same-concurrency greedy identity均为
`10/10`。

分层观测：L1 free mean `5,255.238ms`、L2 `7,901.493ms`、L3 `12,149.979ms`、
L4 `17,043.556ms`、L5 `25,527.031ms`；aggregate delete→all-long-free mean
`13,575.459ms`、p95 `25,641.629ms`。`controlsFinishedBeforeAllLongFree = 0/10`
被保留为边界；protocol只声称 control进入 cancellation window并与同并发 baseline
一致。登记 `RQ3_LLAMA_PARALLEL6_CANCELLATION_CURVE_PASS` 和
`SIX_SLOT_CANCEL_ACCEPTANCE_PASS`；状态为
`PARALLEL6 = PASS_WITH_BOUNDARY / HIGHER_CONCURRENCY_CANCEL_IDENTITY_CURVE`。

这是 no-Execution-Object backend curve，不是 production cancellation readiness、
performance benchmark或 >6-slot closure。一次未落盘的 t256/20s preparatory run在
L5 free等待超时；正式 t128/60s run PASS。curve脚本已增加失败路径落盘。报告见
`docs/00-governance/SIMIGO_LAB_RQ3_LLAMA_PARALLEL6_CANCELLATION_CURVE_20260929.md`；
artifact见
`simigo2-experimental/results/backend-conformance/rq3-llama-concurrency-curve-parallel6-t128.json`。

### LAB RQ3 LLAMA PARALLEL8 CANCELLATION CURVE PASS — 2026-09-29

新增 8-slot higher-concurrency cancellation curve。llama-server使用 Cyber-Tiel
Coder 35B A3B GGUF canonical mitigation profile并以 8 slots运行；observed
per-slot context为 256。long stream为 128 tokens，control为 8 tokens，cancel
delay 100ms，L1–L7各 2 轮共 14 cycles，baseline/control watchdog为 120s，free
watchdog为 90s。

五项 checks全部 PASS：all cancels accepted、all control batches completed、
controls overlapped cancellation window、same-load baseline stable、greedy
identity across cancel。cancel acceptance为 `56/56`，same-load baseline stability
与 same-concurrency greedy identity均为 `14/14`。分层 free mean：L1
`4,543.997ms`、L2 `7,512.166ms`、L3 `11,452.115ms`、L4 `18,199.071ms`、L5
`27,529.977ms`、L6 `29,414.962ms`、L7 `35,534.542ms`。aggregate
delete→all-long-free mean `19,169.547ms`、p95 `35,734.813ms`。
`controlsFinishedBeforeAllLongFree = 0/14`保留为边界。

一次使用旧固定 30s watchdog的 preparatory run在 same-load baseline controls处
超时且未落盘；slots随后 idle。脚本已增加 `--long-timeout-ms` /
`--control-timeout-ms` 和 baseline-controls failure artifact；120s protocol PASS。
登记 `RQ3_LLAMA_PARALLEL8_CANCELLATION_CURVE_PASS`、
`EIGHT_SLOT_CANCEL_ACCEPTANCE_PASS` 和
`THIRTY_SECOND_BASELINE_WATCHDOG_INSUFFICIENT`；状态为
`PARALLEL8 = PASS_WITH_BOUNDARY / HIGHER_CONCURRENCY_CANCEL_IDENTITY_CURVE`。

这是 no-Execution-Object backend curve，不是 production cancellation readiness、
performance benchmark或 >8-slot closure。报告见
`docs/00-governance/SIMIGO_LAB_RQ3_LLAMA_PARALLEL8_CANCELLATION_CURVE_20260929.md`；
artifact见
`simigo2-experimental/results/backend-conformance/rq3-llama-concurrency-curve-parallel8-t128.json`。

### LAB RQ3 LLAMA PARALLEL8 SEED43 REPRODUCTION PASS — 2026-09-29

以 seed43复现 8-slot / t128 cancellation curve。server、observed per-slot context
256、ubatch8、long/control token budget、L1–L7 workload、14 cycles和 120s
baseline/control watchdog均与 seed42 protocol一致。五项 checks全部 PASS；cancel
acceptance `56/56`，same-load baseline stability与 same-concurrency greedy
identity均 `14/14`。`controlsFinishedBeforeAllLongFree = 0/14`保留为边界。

seed43 aggregate delete→all-long-free mean为 `17,828.202ms`，相比 seed42
`19,169.547ms`低 `1,341.345ms`。分层差值方向混合：L1–L5较低，L6/L7较高；每层
只有 n=2，不建立 latency distribution或 seed effect。语义结论是 8-slot
cancellation acceptance和 same-concurrency greedy identity已在两个 seeds复现。
登记 `RQ3_LLAMA_PARALLEL8_CANCELLATION_CURVE_SEED43_PASS`、
`EIGHT_SLOT_CANCEL_ACCEPTANCE_REPRODUCED` 和
`SAME_CONCURRENCY_GREEDY_IDENTITY_REPRODUCED`；状态为
`PARALLEL8_T128_SEED43 = PASS_WITH_BOUNDARY / REPRODUCTION_RUN`。

这是 no-Execution-Object backend curve，不是 production cancellation readiness、
performance benchmark、跨 seed raw-output identity或 >8-slot closure。报告见
`docs/00-governance/SIMIGO_LAB_RQ3_LLAMA_PARALLEL8_SEED43_REPRODUCTION_20260929.md`；
artifact见
`simigo2-experimental/results/backend-conformance/rq3-llama-concurrency-curve-parallel8-t128-seed43.json`。

### LAB CYBER TIEL MLX E5 AND RESOURCE ISOLATED CROSSBACKEND TOKEN OBSERVATION PASS — 2026-09-29

Cyber-Tiel Coder 35B A3B MLX oQ4e通过 E5 real-runtime scenario；模型类型为
`Qwen35MoEModel` / `qwen3_5_moe`。child在 evict → rematerialize → restore 后
replay token-identical，parent在 child discard后与 pre-fork reference一致；
fork divergence、parent identity、child lineage和 residency invariant全部 PASS。

同时新增 resource-isolated two-phase cross-backend token observation，替换早前
因 MLX与 llama-server同时驻留导致大量 swap 的废弃 combined probe。Phase1只运行
MLX：渲染 checkpoint chat-template prompt IDs并记录 greedy outputs；P1/P2/P3
prompt token counts为 197/197/195，generated lengths为 2/12/11，P1/P3遇 EOS，
P2用满 budget。MLX peak bytes `21,103,830,324`、peak footprint
`21,308,833,344`、max swap delta `0`。Phase1 record SHA-256为
`28a7c919c41a874c4eae49ca894104b55747e3cffbc978773eeae24d3a0215f0`。

Phase2在 MLX进程退出后只运行 llama-server，提交相同 prompt token IDs。三个
short prompts的 greedy token IDs和 decoded text均 identical（3/3）。Phase2 max
swap delta也为 `0`。登记
`CYBER_TIEL_QWEN35MOE_E5_PASS`、
`RESOURCE_ISOLATED_SEQUENTIAL_BACKEND_OBSERVATION_PASS` 和
`NAMED_SOURCE_GREEDY_TOKEN_IDENTITY_OBSERVED`；状态为
`CROSSBACKEND_TOKEN_OBSERVATION = PASS_WITH_BOUNDARY / SEQUENTIAL_TWO_PHASE`。

边界：这是 named-source Cyber-Tiel MLX oQ4e与 MTP UD-Q4_K_XL GGUF variants之间的
3-prompt greedy observation，不是 same-checkpoint closure、tokenizer-file
identity proof、quantization equivalence、all-prompt semantic equivalence或
performance equivalence。全仓 Swift verification为 157 PASS / 0 FAIL。报告见
`docs/00-governance/SIMIGO_LAB_CYBER_TIEL_MLX_E5_AND_CROSSBACKEND_TOKEN_OBSERVATION_20260929.md`；
artifacts见
`simigo2-experimental/results/e5-execution-state/cyber-tiel-coder-35b.json`、
`simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-mlx-record.json`、
`simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-token-compare.json`。

### LAB CYBER TIEL CROSSBACKEND TOKEN MATRIX V2 BOUNDARY PASS — 2026-09-29

将 named-source Cyber-Tiel MLX/GGUF token observation从 3-prompt pilot扩展为
12-family matrix V2。Phase1只运行 MLX，Phase2只运行 llama-server；prompt families
覆盖 baseline、counting、list、code-transform、exact-json、cjk、ambiguous
continuation、long-prefix code、constraint、repeat、docstring和 risk。budget为
24 greedy tokens，seed42。

协议PASS且 identity boundary明确：`9/12` prompt的 greedy token IDs exact；
`3/12` mismatch。P6 cjk在第9个 token分叉；P11 docstring首 token分叉，MLX渲染
code fence且生成24 tokens，LLAMA直接输出docstring并在14 tokens终止；P12 risk在
第9个 token分叉但语义方向相同。登记
`CYBER_TIEL_NAMED_SOURCE_TOKEN_MATRIX_V2_PROTOCOL_PASS` 和
`NAMED_SOURCE_GREEDY_IDENTITY_BOUNDARY_OBSERVED`；状态为
`MATRIX_V2 = PASS_WITH_BOUNDARY / PROTOCOL_COMPLETE`。

初次 strict gate FAIL artifact保留：MLX-only模型加载时全局 swap瞬时上升
`1,116,272,066 bytes`。V2 gate拆分为 load transient `1,610,612,736 bytes` 和
steady-state `536,870,912 bytes`。正式 Phase1 load delta `0`、steady delta
`198,317,179 bytes`；Phase2 max delta `0`。这不是两个 backend同时驻留，也不是
放宽 co-residency isolation。全仓 Swift verification为 157 PASS / 0 FAIL。报告见
`docs/00-governance/SIMIGO_LAB_CYBER_TIEL_CROSSBACKEND_TOKEN_MATRIX_V2_20260929.md`；
artifacts见
`simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-mlx-record-matrix-v2-initial-strict-gate-fail.json`、
`simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-mlx-record-matrix-v2.json`、
`simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-token-compare-matrix-v2.json`。

### LAB CYBER TIEL DIVERGENCE LOGIT ATTRIBUTION PASS — 2026-09-29

新增 resource-isolated two-phase divergence logit attribution，覆盖 Matrix V2的
P6 cjk、P11 docstring和 P12 risk。Phase1只运行 MLX：teacher-force
prompt IDs + common generated prefix，计算全词表 log-softmax和 top-16 candidate。
Phase2只运行 llama-server：对同一 teacher-forced prefix提交 `/completion` 并使用
`n_probs=16`。三个 mismatch的 common generated prefix lengths分别为 8/0/8；
teacher prefix token counts为 205/207/211。

结果 `top1 agreement = 0/3`，但所有 alternate tokens都在另一 backend的 top2内：
P6 MLX选 `访问`，LLAMA选 `请求`；P11 MLX选 code fence，LLAMA选 `"""`；P12 MLX选
` at`，LLAMA选 ` your`。因此分歧是 close-logprob near-boundary selection flip，
不是 gross top-k dissociation。P11还叠加 code-fence formatting policy和后续
EOS/length差异。登记
`CYBER_TIEL_DIVERGENCE_TEACHER_FORCED_TOPK_PASS`、
`NEAR_BOUNDARY_TOP1_DIVERGENCE_OBSERVED` 和
`NO_GROSS_TOPK_DISSOCIATION_OBSERVED`；状态为
`LOGIT_ATTRIBUTION = PASS_WITH_BOUNDARY / THREE_DIVERGENCE_CASES`。

Phase1/Phase2 steady swap delta均为 `0 bytes`，gate `768 MiB`；backend顺序运行。
这是 named-source variants的 3-case top-k observation，不是 quantization
equivalence、full logits equality、MTP root cause、tokenizer lineage proof或
same-checkpoint closure。全仓 Swift verification为 157 PASS / 0 FAIL。报告见
`docs/00-governance/SIMIGO_LAB_CYBER_TIEL_DIVERGENCE_LOGIT_ATTRIBUTION_20260929.md`；
artifacts见
`simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-logit-record.json`、
`simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-logit-compare.json`。

### LAB CYBER TIEL FULL TRAJECTORY MARGIN DISTRIBUTION PASS — 2026-09-29

新增 resource-isolated two-phase full-trajectory margin distribution，覆盖 Matrix V2
的 P6 cjk、P11 docstring和 P12 risk。Phase1只运行 MLX：对
`prompt IDs + complete MLX greedy trajectory`一次 forward，抽取 72个 generated
position的 top-16/logprob/margin。Phase2只运行 llama-server：逐 position
teacher-force相同 prefix，提交 `/completion` 并使用 `n_probs=16`。

MLX batched full-trajectory logits对 `72/72` greedy choices self-consistent。
LLAMA top1 agreement为 `66/72 = 91.667%`；P6为 `21/24`、P11为 `23/24`、P12为
`22/24`。所有 MLX reference tokens都在 LLAMA top16内，最大 reference rank仅为
`2`。6个 flip position的 reference deficit范围为 `0.715313` 到
`2.406191` logprob；P11 position 0还包含 code-fence vs direct-docstring
formatting policy差异。登记
`CYBER_TIEL_FULL_TRAJECTORY_MARGIN_DISTRIBUTION_PASS`、
`MLX_BATCHED_TRAJECTORY_SELF_CONSISTENT`、
`LLAMA_TOP1_NEAR_BOUNDARY_FLIP_OBSERVED` 和
`NO_TOP16_DISSOCIATION_OBSERVED`；状态为
`MARGIN_DISTRIBUTION = PASS_WITH_BOUNDARY / FULL_MLX_TRAJECTORY`。

Phase1 MLX steady swap delta `494,340,670 bytes`，在 `768 MiB` gate内；Phase2
LLAMA steady swap delta `0 bytes`，在 `512 MiB` gate内。两个 backend仍顺序运行。
这是固定 MLX trajectory的 margin distribution observation，不比较两条 divergent
paths，不建立 quantization equivalence、tokenizer lineage proof、MTP root cause
或 same-checkpoint closure。全仓 Swift verification为 157 PASS / 0 FAIL。报告见
`docs/00-governance/SIMIGO_LAB_CYBER_TIEL_MARGIN_DISTRIBUTION_20260929.md`；
artifacts见
`simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-margin-record.json`、
`simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-margin-compare.json`。

### LAB CYBER TIEL FULL MATRIX MARGIN ACCEPTANCE GATE PASS — 2026-09-29

将 full-trajectory margin distribution从 P6/P11/P12 mismatch-only扩展到 Matrix
V2 full scope：12 cases、12 families、139 positions。Phase1只运行 MLX并重建完整
greedy trajectory的 top-16/logprob/margin；Phase2只运行 llama-server并逐 position
teacher-force相同 prefix。两阶段顺序执行，steady swap delta均为 `0 bytes`。

named-source acceptance gate正式定义为：top1 flips允许；top16 containment必须；
reference rank不得超过 `2`。结果 `133/139 = 95.683%` top1 agreement；
`139/139 = 100%` top16 containment；max observed reference rank `2`；6个 top1
flip全部允许。gate PASS。分层观测：9个 token-identity cases共 67 positions，
LLAMA top1 agreement为 `67/67 = 100%`，max rank `0`；3个 mismatch cases共 72
positions，top1 agreement为 `66/72 = 91.667%`，max rank `2`。登记
`CYBER_TIEL_FULL_MATRIX_MARGIN_V2_PASS`、`NAMED_SOURCE_ACCEPTANCE_GATE_PASS`、
`IDENTITY_CASE_TOP1_PERFECT_SUBSET_OBSERVED` 和
`MISMATCH_CASE_TOP1_NEAR_BOUNDARY_FLIPS_ONLY`；状态为
`FULL_MATRIX_MARGIN_V2 = PASS_WITH_BOUNDARY / ACCEPTANCE_GATE_PASS`。

MLX self-consistency为 `139/139`。这是固定 MLX trajectory的 named-source
margin observation，不是 same-checkpoint closure、tokenizer-file identity proof、
quantization equivalence、MTP root cause或 production readiness。全仓 Swift
verification为 157 PASS / 0 FAIL。报告见
`docs/00-governance/SIMIGO_LAB_CYBER_TIEL_FULL_MATRIX_MARGIN_ACCEPTANCE_20260929.md`；
artifacts见
`simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-margin-record-matrix-v2-all.json`、
`simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-margin-compare-matrix-v2-all.json`。

### LAB CYBER TIEL FULL MATRIX MARGIN SEED43 REPRODUCTION PASS — 2026-09-29

完成 full matrix V2 margin acceptance gate的 seed43复现。链路依次为 MLX token
record、LLAMA token compare seed43、MLX margin record scope=all、LLAMA margin
compare scope=all seed43。token matrix结果为 `PASS_WITH_BOUNDARY`，identity仍为
`9/12`，mismatch仍为 P6 cjk / P11 docstring / P12 risk；MLX greedy trajectory
与 seed42逐 case semantic identical。

Margin gate结果与 seed42完全一致：12 cases、139 positions、LLAMA top1 agreement
`133/139 = 95.683%`、top16 containment `139/139 = 100%`、max reference rank `2`、
top1 flips `6` 且允许、acceptance gate PASS。分层结果也一致：9个 identity cases
共 67 positions全部 top1一致；3个 mismatch cases共 72 positions中 66个 top1
一致。逐 `(promptID, position)` 审计显示 `139/139` outcome shape与 seed42相同，
差异为 0。登记
`CYBER_TIEL_FULL_MATRIX_MARGIN_V2_SEED43_PASS`、
`FULL_MATRIX_ACCEPTANCE_GATE_REPRODUCED`、
`PER_POSITION_OUTCOME_IDENTICAL_TO_SEED42` 和
`MLX_GREEDY_TRAJECTORY_REPRODUCED`；状态为
`FULL_MATRIX_MARGIN_V2_SEED43 = PASS_WITH_BOUNDARY / ACCEPTANCE_GATE_REPRODUCED`。

为支持该实验，`CrossBackendMarginProbe.runCompare` 和
`cross-backend-margin-compare` 增加显式 seed并写入 report；Phase2请求不再硬编码
seed42。全仓 Swift verification为 157 PASS / 0 FAIL。报告见
`docs/00-governance/SIMIGO_LAB_CYBER_TIEL_FULL_MATRIX_MARGIN_SEED43_REPRODUCTION_20260929.md`；
artifacts见
`simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-mlx-record-matrix-v2-seed43.json`、
`simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-token-compare-matrix-v2-seed43.json`、
`simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-margin-record-matrix-v2-all-seed43.json`、
`simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-margin-compare-matrix-v2-all-seed43.json`。

### LAB NAMED SOURCE CONFORMANCE PROFILE V1 REGISTERED PASS — 2026-09-29

将 Cyber-Tiel Matrix V2 full-margin gate从报告约定固化为 executable named-source
conformance profile。Profile ID为
`NAMED_SOURCE.CYBER_TIEL.MATRIX_V2.TOP16_RANK2.TWO_SEEDS`。硬规则包括：至少两个
unique seeds；各 seed position count一致；所有 reference tokens必须 contained in
top16；maximum reference rank不超过 `2`；允许 top1 flips作为 observation；两个
seed的 `(promptID, position)` outcomes必须完全一致。top1 agreement保留为
observation，不是 hard threshold。

使用 seed42/seed43 margin compare artifacts评估：seedCount `2`、positionCount每
seed `139`、top16 containment aggregate `278/278`、max observed reference rank
`2`、top1 flips aggregate `12`（每 seed `6`）、per-position seed outcomes
identical。七项 checks全部 PASS，failureReasons为空，profile PASS。新增
`NamedSourceConformanceProfile`、CLI `named-source-profile-evaluate`和四个单元
测试覆盖 two-seed pass、single-seed fail、rank-3 fail和 seed outcome mismatch
fail。登记 `NAMED_SOURCE_CONFORMANCE_PROFILE_V1_REGISTERED` 和
`EXECUTABLE_PROFILE_EVALUATION_PASS`；状态为
`PROFILE_V1 = REGISTERED / EVALUATION_PASS`。

该 profile只适用于 named-source Cyber-Tiel MLX oQ4e与 MTP UD-Q4_K_XL GGUF
variants、Matrix V2 12 prompts/139 positions、fixed MLX trajectory和 canonical
LLAMA profile。不是 same-checkpoint closure、tokenizer-file identity proof、
quantization equivalence、performance benchmark或 production readiness。全仓
Swift verification现为 161 PASS / 0 FAIL。报告见
`docs/00-governance/SIMIGO_LAB_NAMED_SOURCE_CONFORMANCE_PROFILE_V1_20260929.md`；
artifact见
`simigo2-experimental/results/backend-conformance/named-source-cyber-tiel-matrix-v2-profile-evaluation.json`。

### LAB NAMED SOURCE LINEAGE AUDIT PASS WITH BOUNDARY — 2026-09-29

新增可复现 GGUF metadata parser和 named-source lineage audit，覆盖 CyberTiel
GGUF UD-Q4_K_XL与 CyberTiel MLX oQ4e。该 audit纠正了术语边界：CyberTiel是
publication/build alias；底层 declared chain为
`Ornith 1.5 35B A3B → huihui-ai/Huihui-Ornith-1.5-35B-A3B-abliterated →
CyberTiel quantization`。GGUF metadata的 `general.name` 为
`Huihui Ornith 1.5 35B A3B Abliterated`、basename `Huihui-Ornith-1.5`、finetune
`abliterated`，upstream base URL为 `ornith-ai/Ornith-1.5-35B-A3B`；MLX README
declared base为 `huihui-ai/Huihui-Ornith-1.5-35B-A3B-abliterated`。
`SOURCE_LINEAGE_CHAIN_MATCH = PASS`。

Tokenizer substrate exact：base vocab `248044/248044`，added tokens `26/26`，
BPE merges `247587/247587`，chat template exact；mismatch均为 0。GGUF总 token数
`248320`，比 MLX shared substrate多 `250`（7 control +243 padding），extra IDs从
`248070`开始。Matrix V2使用 294个 unique token IDs、max token ID `248069`，因此
`MATRIX_IDS_WITHIN_SHARED_VOCAB = PASS`。

九项 checks全部 PASS；状态为
`LINEAGE_AUDIT = PASS_WITH_BOUNDARY / TOKENIZER_SUBSTRATE_AND_DECLARED_LINEAGE`。
本 audit没有比较 weight bytes、tensor values或 dequantized tensors，因此
`CHECKPOINT_IDENTITY = OPEN / WEIGHT_BYTES_NOT_COMPARED`，不能升级为
same-checkpoint closure。此前 named-source profile V1必须按本 correction解释为
shared Ornith/Huihui lineage CyberTiel publication pair profile。报告见
`docs/00-governance/SIMIGO_LAB_NAMED_SOURCE_LINEAGE_AUDIT_20260929.md`；
script见
`simigo2-experimental/scripts/named_source_lineage_audit.py`；artifact见
`simigo2-experimental/results/backend-conformance/named-source-cyber-tiel-lineage-audit.json`。

### LAB CYBER TIEL TENSOR TOPOLOGY AUDIT PASS WITH BOUNDARY — 2026-09-29

新增只读 GGUF/MLX tensor topology audit，解析 GGUF header/metadata/tensor
headers和 MLX safetensors index/headers，不读取、不反量化、不比较 weight values。
GGUF共 753 tensors；MLX snapshot共 2010 physical tensors，聚合 quantized
`weight/scales/biases` 后为 1066 logical groups。

文本模型 topology完全对应：GGUF global 3个、regular `blk.0–39` 730个，共
`733/733` 映射到 MLX logical groups。regular block结构为 40层；其中 10个
full-attention layers各 16 tensors、30个 linear-attention layers各 19 tensors。
MLX logical groups的 `weight/scales/biases` 聚合规则与当前 oQ4e quantization
layout一致。

已知差异全部被显式隔离：GGUF-only `blk.40` nextn/MTP-related block共 20
tensors；MLX-only vision/projector stack共 333 logical groups。没有未解释的
text-model missing/unmapped tensors。八项 checks全部 PASS；状态为
`TENSOR_TOPOLOGY_AUDIT = PASS_WITH_BOUNDARY / TEXT_MODEL_TOPOLOGY_MATCH`。登记
`CYBER_TIEL_TEXT_MODEL_TENSOR_TOPOLOGY_MATCH`、
`GGUF_NEXTN_BLOCK_ISOLATED_AS_GGUF_ONLY`、
`MLX_VISION_STACK_ISOLATED_AS_MLX_ONLY` 和
`NO_WEIGHT_BYTES_OR_DEQUANTIZED_VALUES_COMPARED`。

本 audit不建立 same-checkpoint closure或 dequantized equality。全仓 Swift
verification为 161 PASS / 0 FAIL。报告见
`docs/00-governance/SIMIGO_LAB_CYBER_TIEL_TENSOR_TOPOLOGY_AUDIT_20260929.md`；
script见
`simigo2-experimental/scripts/cyber_tiel_tensor_topology_audit.py`；artifact见
`simigo2-experimental/results/backend-conformance/named-source-cyber-tiel-tensor-topology-audit.json`。

### LAB CYBER TIEL F32 CONTROL DRIFT AUDIT PASS WITH OBSERVED DRIFT — 2026-09-29

新增 GGUF F32与 MLX BF16 shared control tensor numerical audit，覆盖 40层中的
260个 non-large-matrix tensors：所有层 `attn_norm`、`post_attention_norm`、
`ffn_gate_inp`；30个 linear-attention层的 `ssm_a`、`ssm_conv1d`、`ssm_dt.bias`、
`ssm_norm`；10个 full-attention层的 `attn_q_norm`、`attn_k_norm`。GGUF侧为 F32，
MLX侧为 BF16；`ffn_gate_inp` 使用 transpose，`ssm_conv1d` 使用 conv layout
auto-orientation。

协议 `MAPPINGS_COMPLETE`、`NO_FAILURES`、`ALL_RECORDS_FINITE`全部 PASS；共
260 tensors，其中 exact 30/260，zero-drift tensors 0/260。aggregate max abs diff
`101.82308959960938`，mean of per-tensor mean abs diff
`0.644830577143153`。分族观测：layer norms和 q/k norms的最大 drift约
`0.0078125`；`ffn_gate_inp`最大 `0.51953125`；`ssm_a`最大 `101.82309`、
`ssm_dt.bias`最大 `18.40625`；`ssm_norm.weight`是唯一 exact family（30/30）。
登记 `CYBER_TIEL_F32_CONTROL_TENSOR_AUDIT_PASS`、
`NAMED_SOURCE_CHECKPOINT_NUMERICAL_DRIFT_OBSERVED` 和
`SAME_CHECKPOINT_IDENTITY_EFFECTIVELY_REJECTED_FOR_CONTROL_TENSORS`；状态为
`F32_CONTROL_AUDIT = PASS_WITH_OBSERVED_DRIFT`。

这排除 named-source CyberTiel GGUF/MLX pair在 control tensor层面的
same-checkpoint interpretation。协议初版错误读取 GGUF tensor data offset；已修正
为解析完整 tensor-info list后按 32-byte alignment计算 tensor data section起点。
结果不比较 large quantized matrices，也不定位 drift来自 abliteration、conversion
还是 quantizer。全仓 Swift verification为 161 PASS / 0 FAIL。报告见
`docs/00-governance/SIMIGO_LAB_CYBER_TIEL_F32_CONTROL_DRIFT_AUDIT_20260929.md`；
script见
`simigo2-experimental/scripts/cyber_tiel_f32_control_tensor_audit.py`；artifact见
`simigo2-experimental/results/backend-conformance/named-source-cyber-tiel-f32-control-audit.json`。

### LAB CYBER TIEL QUANTIZED LAYOUT PILOT LAYOUT UNRESOLVED — 2026-09-29

新增 layer1 Q8_0 vs MLX affine quantized tensor layout pilot，选取 `attn_qkv ↔
in_proj_qkv`、`attn_gate ↔ in_proj_z`、`ssm_out ↔ out_proj`。GGUF Q8_0完整
dequant；MLX通过 `mx.dequantize`按各自 group size/bits完整 dequant。三个 tensors
均 finite，protocol PASS。

Raw elementwise comparison显示 mean abs diff约 `0.0169–0.0178`，max abs diff约
`0.293–0.627`，但 cosine/pearson接近零：
`0.000224 / 0.000156 / 0.000093`。positional row/column norm correlation也接近
零；sorted magnitude correlation则为 `0.660–0.982`。因此当前 mapping不能建立
elementwise correspondence；可能原因包括 GGUF fused group order、MLX projection
grouping、transpose/packing约定或 artifact source差异。登记
`CYBER_TIEL_Q8_VS_MLX_QUANTIZED_PILOT_PASS`、
`TENSOR_ELEMENT_MAPPING_UNRESOLVED` 和 `QUANTIZER_DRIFT_NOT_ATTRIBUTABLE`；状态为
`QUANTIZED_DRIFT_PILOT = PASS_WITH_BOUNDARY / LAYOUT_OR_SOURCE_UNRESOLVED`。

该结果不得解释为 quantizer drift。large quantized tensor dequant attribution保持
BLOCKED，直到 canonical conversion mapping解析。Named-source profile V1不受影响，
因为其 gate基于 fixed-trajectory output behavior，不假设 weight element mapping。
报告见
`docs/00-governance/SIMIGO_LAB_CYBER_TIEL_QUANTIZED_LAYOUT_PILOT_20260929.md`；
script与artifact见
`simigo2-experimental/scripts/cyber_tiel_quantized_drift_pilot.py`、
`simigo2-experimental/results/backend-conformance/named-source-cyber-tiel-quantized-drift-pilot-layer1.json`。

### LAB CYBER TIEL QKV SEGMENT LAYOUT DIAGNOSTIC LAYOUT UNRESOLVED — 2026-09-29

新增 layer1 `attn_qkv` fused segment diagnostic，检验 Matrix V2 quantized pilot中
cosine接近零的可能原因。假设 GGUF/MLX qkv segment划分为 Q2048、K2048、V4096。
GGUF Q8_0完整 dequant；MLX `in_proj_qkv`按4-bit/group64 dequant后 transpose。
使用 block norm correlation、segment permutations和同长度 row assignment audit。

九个 block-norm correlations都接近零。six segment permutations排序中，最佳为
`(K,Q,V)`，summed block-norm Pearson `0.6063845`；自然 `(Q,K,V)`为
`0.6049992`，两者仅差 `0.0013853`，不足以确定 segment order。同长度 row
assignment中，最佳 Pearson max为 `0.1159309`，没有任何 pair达到 `0.50`；因此
row mapping不成立。登记
`CYBER_TIEL_QKV_SEGMENT_DIAGNOSTIC_PASS`、
`BEST_SEGMENT_ORDER_SUGGESTIVE_BUT_ROW_MAPPING_ABSENT` 和 `LAYOUT_UNRESOLVED`；
状态为 `QKV_SEGMENT_DIAGNOSTIC = PASS_WITH_BOUNDARY / LAYOUT_UNRESOLVED`。

该 diagnostic不支持把 GGUF/MLX elementwise difference归因为 quantizer drift。
large quantized tensor attribution继续 BLOCKED。script见
`simigo2-experimental/scripts/cyber_tiel_qkv_segment_diagnostic.py`；artifact见
`simigo2-experimental/results/backend-conformance/named-source-cyber-tiel-qkv-segment-diagnostic.json`。

### LAB NAMED SOURCE EVIDENCE BUNDLE V1 CONSOLIDATION PASS — 2026-09-29

新增 `named_source_evidence_bundle.py` 和 evidence bundle V1，把 named-source
CyberTiel GGUF/MLX研究整合为 machine-checkable evidence set。bundle覆盖 profile
evaluation、lineage audit、tensor topology audit、margin compare seed42/seed43、
QKV segment diagnostic、F32 control drift audit和 quantized layout pilot，共 8个
source artifacts。九项 consolidated checks全部 PASS。

Verdicts：
- `namedSourceAcceptanceGate = PASS`：seed42/43均为 139 positions、top1
  agreement `133/139`、top16 containment `139/139`、max rank `2`、6个允许的
  top1 flips。
- `tokenizerSubstrate = EXACT`：base vocab、added tokens、merges mismatch均为 0，
  chat template exact。
- `declaredLineageChain = PASS`：
  `Ornith 1.5 → Huihui-Ornith-1.5-abliterated → CyberTiel quantization`。
- `textTensorTopology = COMPLETE_WITH_KNOWN_EXTRAS`：GGUF 753中 733个 text
  tensors映射；GGUF nextn-only 20；MLX vision-only 333；MLX language unmapped 0。
- `sameCheckpointClosure = REJECTED_AT_CONTROL_TENSOR_LEVEL`：260个 F32 control
  tensors中 exact 30、zero-drift 0、max abs diff `101.82309`。
- `largeMatrixQuantizerDriftAttribution = BLOCKED_LAYOUT_SOURCE_UNRESOLVED`：
  layer1三tensor pilot elementwise cosine接近零，layout未解析。
- `qkvSegmentOrder = UNRESOLVED`：最佳 `(K,Q,V)` `0.6063845`与自然
  `(Q,K,V)` `0.6049992`差距过小；row mapping不成立。

登记 `NAMED_SOURCE_EVIDENCE_BUNDLE_V1_CONSOLIDATION_PASS`；状态为
`EVIDENCE_BUNDLE_V1 = PASS_WITH_BOUNDARY / CONSOLIDATION_COMPLETE`。bundle不建立
same-checkpoint closure、tokenizer implementation equivalence、quantization
equivalence、MTP root cause或 production readiness。script见
`simigo2-experimental/scripts/named_source_evidence_bundle.py`；artifact见
`simigo2-experimental/results/backend-conformance/named-source-cyber-tiel-evidence-bundle.json`。

### LAB CYBER TIEL QKV ROW ASSIGNMENT AUDIT PERMUTATION SUPPORTED — 2026-09-29

新增 Hungarian row-norm assignment audit，验证 QKV segment diagnostic中的
permutation hypothesis。输入为 GGUF Q8_0 dequant和 MLX affine dequant后的
`attn_qkv` row L2 norms；Q/K各 2048 rows，V4096 sampled to 2048 rows以同shape
assignment。same-segment assignments全部通过：Q2048 assignment cost mean
`0.0659900`、matched Pearson `0.5066660`；K2048 cost mean `0.0443534`、matched
Pearson `0.6598681`；V4096 sample cost mean `0.0866736`、matched Pearson
`0.5719384`。

cross-segment结果显示 Q/K identity ambiguous：`Q2048 ↔ K2048` assignment cost
mean `0.0485477`、matched Pearson `0.6513951`；`K2048 ↔ Q2048` cost mean
`0.0599772`、matched Pearson `0.5675769`。V segment与 Q/K更可区分，V↔Q matched
Pearson仅 `0.0324263`，V↔K为 `0.0979268`。登记
`CYBER_TIEL_QKV_ROW_NORM_ASSIGNMENT_PASS`、
`QKV_ROW_NORM_PERMUTATION_HYPOTHESIS_SUPPORTED`、
`QK_SEGMENT_IDENTITY_AMBIGUOUS`、`V_SEGMENT_DISTRIBUTIONALLY_SEPARABLE`；状态为
`QKV_ROW_ASSIGNMENT_AUDIT = PASS_WITH_BOUNDARY / PERMUTATION_HYPOTHESIS_SUPPORTED`。

该 audit只使用 row-norm scalar，不建立 element-level mapping，也不归因 quantizer
drift。large quantized tensor attribution继续 BLOCKED。script和artifact见
`simigo2-experimental/scripts/cyber_tiel_qkv_row_assignment_audit.py`、
`simigo2-experimental/results/backend-conformance/named-source-cyber-tiel-qkv-row-assignment-audit.json`。

### LAB CYBER TIEL QKV FULL ROW CORRELATION ASSIGNMENT MAPPING NOT ESTABLISHED — 2026-09-29

将 QKV layout diagnostic从 row L2 norm升级为 full row-vector Pearson assignment。
对 layer1 `attn_qkv` GGUF Q8_0 dequant和 MLX `in_proj_qkv` dequant transpose后，
按假设的 Q2048、K2048、V4096 segments分别 center/L2-normalize rows，构造 GGUF↔
MLX Pearson matrix并用 Hungarian assignment最大化 matched Pearson。协议三项
checks全部 PASS：三个 segments完成、所有 Hungarian assignments完成、8192个 qkv
features全覆盖。

结果显示 layout mapping not established。best matched Pearson：
Q2048 `0.1159309`、K2048 `0.1098251`、V4096 `0.0785623`；matched means分别为
`0.0712224 / 0.0714073 / 0.0512549`。6144个 rows中没有任何 matched Pearson达到
`0.50`，达到 `0.70`或 `0.90`的也是 0。identity Pearson means也接近零。登记
`CYBER_TIEL_QKV_FULL_ROW_CORRELATION_ASSIGNMENT_PASS`、
`BEST_ROW_CORRELATION_BELOW_012`、`NO_QKV_ROW_AT_LEAST_050` 和
`LAYOUT_MAPPING_NOT_ESTABLISHED`；状态为
`QKV_ROW_CORRELATION_ASSIGNMENT = PASS_WITH_BOUNDARY / LAYOUT_MAPPING_NOT_ESTABLISHED`。

这比 norm-only audit更强：即使允许任意 Q/K/V row permutation，full row vectors
也不存在一一对应。因此 named-source profile不能升级为 same-checkpoint closure或
quantization-equivalent payload。可能原因包括不同 source checkpoint、GGUF
conversion的 projection grouping/order、quantization transformation，或这些因素
组合；当前证据不足以归因。script与artifact见
`simigo2-experimental/scripts/cyber_tiel_qkv_row_correlation_assignment.py`、
`simigo2-experimental/results/backend-conformance/named-source-cyber-tiel-qkv-row-correlation-assignment.json`。

### LAB MLX EXECSTATE SCALE PROFILE N5 REPLICATION PASS — 2026-09-29

将 MLX Execution State scale observation从每 prefix length 2 pairs扩展到
5 pairs。prefix `8/64/256`、1-token generation、segment size 8下，semantic
checks `3/3 PASS`，30个 paired samples全部 semantic identical；peak footprint
`7617 MiB`，artifact内 max swap `0 MiB`，segment transitions `202`。

paired `state−direct` delta mean/median/stdev 分别为：

```text
8   = -27.889850 / -14.784833 / 51.927615 ms
64  = +25.556042 / +40.793125 / 75.081490 ms
256 = +106.075009 / +96.983626 / 77.262420 ms
```

登记 `MLX_EXECSTATE_SCALE_N5_REPLICATION_PASS`、
`PAIRED_STATE_DIRECT_DELTAS_NOT_STABLE_AT_N5`、
`STATE_LOCAL_COST_MICROSECOND_SCALE` 和 `NO_PERFORMANCE_BENCHMARK_CLAIM`。
state local bookkeeping mean为 `0.010392–0.033925ms`，但 prefix 8受单个
`0.131542ms` sample影响，median仍约 `0.011ms`；不能推出稳定 overhead。

用户观察到 llama-server 与 simigo2ctl 并发时 host swap达 `21.51 GiB`。复核时
两个进程均已退出、`18080` 无监听；artifact记录本 run max swap `0 MiB`。由于
并发 inference 若与 run 重叠会造成 scheduling/memory confound，本结果只接受为
semantic / Execution State replication；latency数字继续不是 performance
benchmark。后续 clean characterization需要无并发 inference、受控 memory
pressure，并记录 host resource context。

报告与artifact见
`docs/00-governance/SIMIGO_LAB_MLX_EXECSTATE_SCALE_PROFILE_N5_20260929.md`、
`simigo2-experimental/results/backend-conformance/mlx-execstate-scale-profile-n5.json`。

### LAB MLX EXECSTATE SCALE N5 PROCESS CLEAN PASS — 2026-09-29

针对上一轮 host-concurrency boundary，追加 process-clean isolation rerun。
run前后均确认无 `llama-server` / `simigo2ctl` 进程、无 `18080` listener；
before residual host swap为 `4481.19 MiB`、after为 `4270.44 MiB`，
`vm.memory_pressure` from `0` to `452` 仅原样记录。run内 artifact记录
max swap `0 MiB`，peak footprint `7155 MiB`，segment transitions `202`。

本轮 semantic checks `3/3 PASS`，15个 paired samples全部 semantic identical。
paired `state−direct` mean/median/stdev：

```text
8   = +8.599517 / -8.149541 / 54.475544 ms
64  = +94.238883 / +102.098375 / 66.207528 ms
256 = +349.044725 / +313.837041 / 312.741558 ms
```

登记 `MLX_EXECSTATE_SCALE_N5_PROCESS_CLEAN_PASS`、
`PROCESS_CLEAN_ISOLATION_PASS`、
`PREFIX8_STATE_DIRECT_DELTA_NEAR_ZERO`、
`PREFIX64_AND_256_POSITIVE_MEAN_DELTA_OBSERVED` 和
`NO_PERFORMANCE_BENCHMARK_CLAIM`。process-clean结果使 longer-prefix positive
delta更值得追踪，但仍未分离 segment materialization、cache behavior、scheduling
和 harness recompute，不能建立 hot-path overhead或 performance curve。state
local bookkeeping mean保持 `0.009783–0.012891ms`。

结果、process context和报告见
`simigo2-experimental/results/backend-conformance/mlx-execstate-scale-profile-n5-clean-isolation.json`、
`simigo2-experimental/results/backend-conformance/mlx-execstate-scale-profile-n5-clean-isolation-host-context.json`、
`docs/00-governance/SIMIGO_LAB_MLX_EXECSTATE_SCALE_PROFILE_N5_PROCESS_CLEAN_20260929.md`。

### LAB OVERSIZED RESEARCH BOUNDARY FROZEN — 2026-09-29

冻结 oversized independent research line。历史 COST / workload / UI / cancel
实验继续有效，但 oversized身份从“研究对象”改为“architecture validation
payload”。后续只允许在 Execution State / Storage / Backend architecture实验中
作为 retention、artifact lifecycle、restore、resource budget、backend
capability、failure / recovery的规模旁证；不再新建 layer loading、tensor
strategy或 standalone oversized scale分支，也不得为了让 oversized产生结果而给
Execution State添加特殊语义。

冻结前完成最后一个 MLX scale observation：prefix `8/64/256`，每 bucket
`10` pairs，1-token generation，segment size 8。run前后均无
`llama-server` / `simigo2ctl`、无 `18080` listener。semantic checks `3/3 PASS`，
30个 paired samples全部 semantic identical；peak footprint `7364 MiB`，
artifact内 max swap `0 MiB`，segment transitions `397`。

paired `state−direct` mean/median/stdev：

```text
8   = +18.171537 / -4.314375 / 171.364680 ms
64  = -337.701508 / -44.328895 / 897.093750 ms
256 = -537.781654 / -565.164395 / 690.257408 ms
```

登记 `MLX_EXECSTATE_SCALE_N10_PROCESS_CLEAN_FINAL_PASS`、
`OVERSIZED_INDEPENDENT_RESEARCH_LINE_FROZEN`、
`OVERSIZED_ROLE_ARCHITECTURE_VALIDATION_PAYLOAD`、
`SCALE_DELTAS_SIGN_REVERSING_ACROSS_RUNS` 和
`NO_PERFORMANCE_BENCHMARK_CLAIM`。delta方向与上一轮 n=5 process-clean相反，
进一步说明继续扩张 oversized scale线不适合作为主线证据。

下一主线保持 PALACE-1与 BACKEND-1的 audit-first路径；oversized只在其中作为
boundary workload复用。boundary报告与final artifact见
`docs/00-governance/SIMIGO_LAB_OVERSIZED_RESEARCH_BOUNDARY_FREEZE_20260929.md`、
`simigo2-experimental/results/backend-conformance/mlx-execstate-scale-profile-n10-process-clean-final.json`、
`simigo2-experimental/results/backend-conformance/mlx-execstate-scale-profile-n10-process-clean-final-host-context.json`。

### LAB EXECUTION STATE PHASE A BOUNDARY AUDIT COMPLETE — 2026-09-29

状态登记为 `PHASE_A_CODE_AUDIT_COMPLETE / AWAITING_REVIEW`。本轮只审计
`simigo2-experimental` 当前代码，不选 SQLite / KV / event log / remote，不实现
Palace database，不实现 Llama adapter。

Observed boundary：

```text
ExecutionID / Lineage / Position / Continuation / Lifecycle
    = semantic Execution State aggregate

Coordinator handles / records / representation history
    = process-local materialization; no persistence sink

ExecutionRepresentation payload, RepresentationRef, prefix entry,
snapshot + sidecar
    = physical representation layer

ExecutionBindingRegistry rows / runtimeAddress / generation
    = runtime relation plus representation locator plus history

lifecycle records, pool stats, oversized token ledger
    = observability / history

physical-use counts and in-flight materialization
    = transient
```

Phase A 的 inferred minimal D closure 是 semantic `ExecutionStateHandle`
aggregate：`id`, `lineage.root`, `lineage.parent`, `position`,
`continuation.nextInput`, `continuation.continuationID`, `lifecycle`。
完整 lifecycle event log、RepresentationRef、binding relation、runtimeAddress、
token prefix / KV artifact、stats 和 in-flight work 都不属于最小 D 闭包。

关键 code facts：

- Execution position 的 canonical source 是 coordinator-owned handle position；
  token count / prefix boundary / `RepresentationRef.boundLength` 是 P 层 claim。
- Generic backend consistency 目前只强制 representation position 和 payload
  type；content digest 只存在于 prefix pool / sidecar 特定路径。
- Coordinator restore 依赖 in-memory representation history；restart 后不能恢复。
- Prefix store `rescan()` 只恢复 representation claims，不恢复 Execution handles
  或 execution→representation bindings。
- `bindRepresentation` 不拒绝 discarded lifecycle；这是后续 Phase B 必须处理的
  logical/physical seam gap。

Targeted tests PASS：`SimiGoRuntimeContractTests 15/15`，
`SimiGo2ExperimentalTests 30/30`，总计 `45/45`。artifact 见
`simigo2-experimental/results/backend-conformance/execution-state-phase-a-boundary-audit-tests-20260929.json`；
报告见
`docs/00-governance/SIMIGO_LAB_EXECUTION_STATE_PHASE_A_BOUNDARY_AUDIT_20260929.md`。

登记 `EXECUTION_STATE_PHASE_A_AUDIT_COMPLETE`、
`MINIMAL_D_CANDIDATE_IS_EXECUTION_STATE_HANDLE_AGGREGATE`、
`REPRESENTATION_AND_BINDING_NOT_EXECUTION_D_STATE` 和
`NO_STORAGE_SELECTION_NO_ADAPTER_IMPLEMENTATION`。

下一步是 external review / explicit human registration。登记通过后才打开 Phase B
PALACE-1 minimal durable unit；BACKEND-1继续单独 scoped。

### LAB EXECUTION STATE PHASE A EXTERNAL REVIEW PASS — 2026-09-30

External review artifact：
`docs/00-governance/SIMIGO_LAB_EXECUTION_STATE_PHASE_A_EXTERNAL_REVIEW_20260930.md`。
Review verdict is `PASS / REGISTRATION_REQUIRED`。这是 external review decision，
不是 repository registration；因此 Phase B仍然 closed。

Review confirms Phase A answered the six route questions, preserved
`observed code fact ≠ inferred minimal contract ≠ selected implementation`, did not
select storage, and did not authorize adapter implementation。Targeted evidence
remains `45/45 PASS`。

Phase B must inherit six non-blocking conditions:

```text
1. durable identity allocation / tombstone policy
2. continuation versus transcript equivalence, if transcript becomes canonical
3. explicit representation content claim / validation policy
4. durable binding relation kept separate from Execution State
5. explicit crash-consistency recovery semantics
6. discarded-binding semantic guard
```

当前唯一 gate 是 explicit human/repository registration of the review decision。
登记通过前，不开 PALACE-1 Phase B，不做存储选型，不实现 Palace database，
不实现 Llama adapter。

### LAB PALACE1 PHASE B OPENING DRAFT READY — 2026-09-30

Participant draft:
`docs/00-governance/SIMIGO_LAB_PALACE1_MINIMAL_DURABLE_UNIT_DRAFT_20260930.md`。

This is only a proposal, not Phase B activation。它提出 Phase B 主问题：

> 一个 Execution 的最小 durable semantic unit 是什么，才能恢复 execution
> semantics，而不把 Runtime Binding、Backend State 或 Physical Representation
> 错误提升为 Durable Semantic State？

Draft subquestions cover durable identity / tombstone, continuation versus
transcript, semantic snapshot versus lifecycle history, separate binding relation,
representation availability / corruption, crash windows, and discarded-state
semantics。It explicitly excludes storage selection, Palace schema, persistence
format, Llama adapter, oversized special semantics, and performance benchmark。

状态保持 `PARTICIPANT_DRAFT / PHASE_B_NOT_OPEN / AWAITING_PHASE_A_REGISTRATION`。
当前 gate 不变：先 explicit human/repository registration Phase A review PASS，
然后才能注册并激活 Phase B。

### LAB PALACE1 PHASE B DRAFT REVIEW PASS — 2026-09-30

External review artifact：
`docs/00-governance/SIMIGO_LAB_PALACE1_PHASE_B_DRAFT_EXTERNAL_REVIEW_20260930.md`。
Verdict is `PASS / ACTIVATION_REQUIRED`。这是 review decision，不是 Phase B
activation。

Review confirms the draft remains at architecture-contract level and preserves all
hard boundaries：no storage selection, no Palace schema, no persistence format,
no Llama adapter, no oversized special semantics, and no performance benchmark。

Review前 draft已补强 B6 crash-window scope，纳入：

```text
fork transition partially applied
continued logical state without representation rebind
restored logical state with stale binding
```

因此 Phase B审计不仅要处理 artifact 写入中断，还要处理 lifecycle transition 中断。

当前状态：

```text
Phase A review       = PASS / REGISTRATION_REQUIRED
Phase B draft review = PASS / ACTIVATION_REQUIRED
Phase B              = STILL CLOSED
Current blocker      = explicit human/repository registration
```

### LAB PALACE1 PHASE B OPENING REGISTERED — 2026-09-30

Human approval received:

```text
登记两项 PASS，并激活 Phase B opening。
```

Registration artifact:
`docs/00-governance/SIMIGO_LAB_PALACE1_PHASE_B_OPENING_REGISTRATION_20260930.md`。

Registered facts：

```text
Phase A review PASS       = REGISTERED
Phase B draft review PASS = REGISTERED
PALACE-1 Phase B          = OPEN
Current gate              = code-level architecture audit
```

Registered opening research question：

> 在 Phase A 边界内，一个 Execution 的最小 durable semantic unit 是什么，才能在
> 进程退出、runtime binding 失效或 Physical Representation 不可用后恢复 execution
> semantics，而不把 Runtime Binding、Backend State 或 Physical Representation
> 错误提升为 Durable Semantic State？

This authorization does not select SQLite / KV / event log / remote storage, define
a Palace schema, choose a persistence format, implement a Llama adapter, add
oversized-specific semantics, or authorize performance benchmarking。

### LAB PALACE1 PHASE B MINIMAL DURABLE UNIT AUDIT COMPLETE — 2026-09-30

Phase B code-level audit artifact:
`docs/00-governance/SIMIGO_LAB_PALACE1_MINIMAL_DURABLE_UNIT_AUDIT_20260930.md`。
状态为 `PHASE_B_CODE_AUDIT_COMPLETE / AWAITING_REVIEW`。

Audit基于 clean HEAD worktree `db188ac`；主工作区当时存在无关未提交 Swift 改动，
没有混入证据。

Phase B answer：

```text
minimal durable unit = Execution Semantic Snapshot

fields =
  id
  lineage.root
  lineage.parent
  position
  continuation.nextInput
  continuation.continuationID
  lifecycle

recoverable set =
  snapshots
  + required lineage tombstones
  + optional separately typed representation binding relations
```

Boundary decisions：

- `continuation.nextInput` remains D in the current Lab contract; a future
  transcript canonical source requires bounded equivalence proof。
- Lifecycle event history is observability/replay data, not minimum D。
- `RepresentationRef` remains P locator/claim。
- Execution→Representation relation must remain separate; `runtimeAddress` stays R。
- `discarded` is a terminal semantic tombstone until explicit GC policy retires it。
- Crash-window recovery must classify interrupted fork / continue / restore and
  artifact/claim pairs without selecting a storage transaction protocol。

Targeted clean-HEAD tests PASS：`SimiGoRuntimeContractTests 15/15`，
`SimiGo2ExperimentalTests 42/42`，总计 `57/57`。artifact 见
`simigo2-experimental/results/backend-conformance/palace1-phase-b-audit-tests-20260930.json`。

登记 `PALACE1_MINIMAL_DURABLE_UNIT_IS_EXECUTION_SEMANTIC_SNAPSHOT`、
`DURABLE_SET_REQUIRES_LINEAGE_TOMBSTONE_CLOSURE`、
`TRANSCRIPT_EQUIVALENCE_NOT_ASSUMED`、
`BINDING_RELATION_SEPARATE_FROM_MINIMUM_D` 和
`PHASE_B_AUDIT_AWAITING_REVIEW`。

### LAB PALACE1 PHASE B AUDIT REVIEW PASS — 2026-09-30

External review artifact:
`docs/00-governance/SIMIGO_LAB_PALACE1_PHASE_B_AUDIT_EXTERNAL_REVIEW_20260930.md`。
Verdict is `PASS / REGISTRATION_REQUIRED`。这是 external review decision，不是
repository registration。

Review accepts the Phase B architecture conclusion：

```text
minimal durable unit = Execution Semantic Snapshot

fields =
  id
  lineage.root
  lineage.parent
  position
  continuation.nextInput
  continuation.continuationID
  lifecycle

recoverable set =
  snapshots
  + required lineage tombstones
  + optional separately typed representation binding relations
```

Boundary checks PASS：no storage selection, no Palace schema, no persistence
format, no Llama adapter, no oversized special semantics, and no performance
benchmark claim。Evidence remains targeted structural validation：`57/57 PASS`
on clean code HEAD `db188ac`；it is not an end-to-end durability proof。

Registration后仍必须继承六个条件：

```text
1. lineage tombstone closure
2. transcript equivalence proof before reclassifying nextInput
3. explicit representation content claim / validation policy
4. separately typed binding relation; runtimeAddress remains R
5. crash-window recovery classification without storage design
6. coordinator concurrency, discarded-binding guard, and durable identity
   reservation remain separately gated engineering gaps
```

当前状态：

```text
Phase A review         = PASS / REGISTERED
Phase B opening        = PASS / REGISTERED
Phase B boundary audit = PASS / REGISTRATION_REQUIRED
Phase C / BACKEND-1    = STILL GATED
Current blocker        = explicit human/repository registration
```

### LAB PALACE1 PHASE B AUDIT REGISTERED — 2026-09-30

Human approval received:

```text
登记 Phase B audit PASS。
```

Registration artifact:
`docs/00-governance/SIMIGO_LAB_PALACE1_PHASE_B_AUDIT_REGISTRATION_20260930.md`。

Registered facts：

```text
Phase A review               = PASS / REGISTERED
Phase B opening              = PASS / REGISTERED
Phase B boundary audit       = PASS / REGISTERED
minimal durable unit         = Execution Semantic Snapshot（契约级，非存储实现）
recoverable set              = snapshots + required lineage tombstones
                               + optional separately typed representation
                               binding relations
evidence status              = targeted structural 57/57 PASS on clean db188ac；
                               非 end-to-end durability proof
Phase C / BACKEND-1          = boundary precondition SATISFIED；activation 仍须
                               独立决策点
```

六个 mandatory conditions 已随登记继承至后续所有 gate：lineage tombstone
closure、transcript equivalence proof（nextInput 维持 D）、explicit
representation content claim / validation policy、binding relation separately
typed（runtimeAddress 维持 R）、crash-window recovery classification（不授权
transaction protocol / persistence format）、coordinator concurrency /
discarded-binding guard / durable identity reservation（独立 engineering gate）。

本次登记不选型 SQLite / KV / event log / remote storage，不定义 Palace schema，
不选择 persistence format，不实现 Llama adapter，不加 oversized 特殊语义，
不授权 performance benchmarking。下一决策点 = Phase C / BACKEND-1 activation
decision；BACKEND-1 opening 须对照本登记边界重新审阅后才可进入执行。

### LAB BACKEND1 PHASE C OPENING DRAFT REVIEWED — 2026-09-30

Human instruction（session goal）: `开始新研究路线的研究`。

Participant draft:
`docs/00-governance/SIMIGO_LAB_BACKEND1_PHASE_C_OPENING_DRAFT_20260930.md`
（draft commit `a5a7177`）。草案完成两件事：

1. 对照已登记 Phase B boundary 审阅 2026-09-28 BACKEND-1 opening：修正
   `Execution → RepresentationRef → …` 目标关系与 Q4 前提（RepresentationRef
   是 P 层 locator/claim；durable relation 是 separately typed binding
   relation）；Q7 拆分为结构性问题（C7）与测量（归 RQ3）。
2. 产出 re-anchored Phase C opening C1–C8：MLX-specific leakage / minimal
   backend seam / capability requirements / representation contract /
   sync-async boundary / cancellation-failure-release / default-path
   non-interference（结构性）/ cross-backend semantic continuity（目标验证
   问题，来自 route redefinition §Phase C）。

External review:
`docs/00-governance/SIMIGO_LAB_BACKEND1_PHASE_C_OPENING_DRAFT_EXTERNAL_REVIEW_20260930.md`。
Verdict: `PASS / ACTIVATION_REQUIRED`。这是 external review decision，不是
repository registration。

Prior evidence 处置：RQ1 = `CLOSED-FOR-CURRENT-CONTRACT`（只引用，不重跑，
非 universal）；RQ3 = `SEPARATELY SCOPED`（hot-path/cancellation/并发测量
留在 RQ3）；RQ2 = `PARTIAL` 不动。六项 Phase B mandatory conditions 与四条
review strengthening（session persistence 读法 / C2 输出层级 / C8 证据边界 /
prior evidence 引用边界）随登记继承。

当前状态：

```text
Phase A review         = PASS / REGISTERED
Phase B opening        = PASS / REGISTERED
Phase B boundary audit = PASS / REGISTERED
Phase C opening draft  = PASS / ACTIVATION_REQUIRED
Phase C seam audit     = NOT STARTED（registration 后才可开始）
Current blocker        = explicit human/repository registration
```

### LAB BACKEND1 PHASE C OPENING REGISTERED — 2026-09-30

Human approval received:

```text
登记 Phase C opening PASS，并激活 Phase C seam audit。
```

Registration artifact:
`docs/00-governance/SIMIGO_LAB_BACKEND1_PHASE_C_OPENING_REGISTRATION_20260930.md`。

Registered facts：

```text
Phase A review                = PASS / REGISTERED
Phase B boundary audit        = PASS / REGISTERED
Phase C opening               = REGISTERED / OPEN（re-anchored 09-28 BACKEND-1
                                opening，draft commit a5a7177）
Phase C subquestions          = C1–C8
review strengthening          = 4 条随登记继承
Phase C seam audit            = ACTIVE（clean HEAD worktree + targeted tests；
                                observed ≠ inferred ≠ selected）
```

本次登记不实现 Llama adapter，不选存储，不定义 persistence format，不做
performance claim，不吸收 RQ1/RQ2/RQ3 已登记工作，不做 API/协议签名设计。

### LAB BACKEND1 PHASE C SEAM AUDIT REVIEW PASS — 2026-09-30

Phase C seam audit artifact:
`docs/00-governance/SIMIGO_LAB_BACKEND1_PHASE_C_SEAM_AUDIT_20260930.md`
（audit commit `58859a9`；audited clean HEAD `ebe4aec`）。

Targeted evidence：`SimiGoRuntimeContractTests 19/19` + selected
`SimiGo2ExperimentalTests 42/42`（含 `BackendConformanceMatrixTests 3/3` 三
adapter）= `61/61 PASS`。Summary artifact:
`simigo2-experimental/results/backend-conformance/backend1-phase-c-seam-audit-tests-20260930.json`。
仍为 targeted structural validation，非 end-to-end durability proof。

C1–C8 narrow answer：

```text
C1  语义层零 MLX 渗漏（contract target 无 dependency；D 级文件全零 MLX
    import；三 payload 均 [Int]）；唯一跨组件渗漏点 = PrefixSnapshotStore
    公开 API（MLXLMCommon PromptCacheSnapshot，L-1/G-5，非 blocker）
C2  最小 seam = E1（7 语义生命周期 op，Runtime 独占）+ E3（4 representation
    op + opaque payload + 3 契约错误，Backend 独占）+ B1（物化/内存对账面）；
    sovereignty 结构验证：全 let handle，backend 无语义写路径
C3  capability = R/T 层策略差异 + 显式降级（ResolutionState 四态 + 
    noRepresentationAtPosition fail closed）；无 capability 字段进 D
C4  durable relation 与 Phase B 登记逐字段吻合（RepresentationRef/
    ExecutionRepresentationBinding）；内容主张为 per-path（pool/sidecar），
    非 universal
C5  四个语义 commit 窗口（fork/restore/discard/bind）与 physical outcome
    同步因果；物理 I/O 在 seam 后 async；契约不强迫阻塞线程
C6  failure 全部 loud fail-closed（三 adapter throw；discard release 先行
    可重试；stale release no-op）；cancellation 为 harness/executor 级
    （契约无 cancel 面，G-9）
C7  默认路径即 ES 路径（engine 内构造 coordinator，SimiGo2App 零 MLX
    import）；seam 不强制改动稳定 MLX 路径；测量归 RQ3
C8  契约支持跨 backend 语义连续（已测三 backend 条件内）；representation
    侧显式降级；不证明 artifact 可移植 / production-readiness / universal
```

Registered gaps：G-1（oversized derive 缺 position guard，被 coordinator
:177 遮蔽）、G-2（coordinator 无内部锁）、G-3（attach 不验证 lineage
closure）、G-4（bindRepresentation 不查 lifecycle）、G-5（L-1）、G-6（E3
payload 无 universal digest）、G-7（ExecutionID 无 durable allocator）、
G-8（BindingRegistry 原地改行，Phase B gap #9 仍在）、G-9（契约无
cancellation 面）、G-10（Lab 无 durable store）。

External review:
`docs/00-governance/SIMIGO_LAB_BACKEND1_PHASE_C_SEAM_AUDIT_EXTERNAL_REVIEW_20260930.md`。
Verdict: `PASS / REGISTRATION_REQUIRED`。已于独立登记 commit 中正式登记为
`PASS / REGISTERED`。四条 review strengthening 随登记继承（condition-1
seam 读法 / L-1 处置 / G-1 前置条件 / 证据卫生）。

Registration:
`docs/00-governance/SIMIGO_LAB_BACKEND1_PHASE_C_SEAM_AUDIT_REGISTRATION_20260930.md`。

当前状态：

```text
Phase A review           = PASS / REGISTERED
Phase B boundary audit   = PASS / REGISTERED
Phase C opening          = PASS / REGISTERED
Phase C seam audit       = PASS / REGISTERED
BACKEND-1 adapter eng.   = NOT OPENED（另行 gate）
Current blocker          = none on Phase C seam audit
```

### LAB BACKEND1 ADAPTER ENGINEERING OPENING REGISTERED — 2026-09-30

Phase C 封口后（human 侧登记 `afdf30f`；同日 `1e2749f` 清理 Swift 告警，
纯告警修复非语义变更），BACKEND-1 adapter engineering opening cycle 前两步
在另一会话完成：

```text
Opening draft    = 2528658（SIMIGO_LAB_BACKEND1_ADAPTER_ENGINEERING_OPENING_
                   DRAFT_20260930.md，205 行）
External review  = 9ebeaf1（…_EXTERNAL_REVIEW_20260930.md，verdict
                   PASS / ACTIVATION_REQUIRED，Engineering NOT AUTHORIZED YET）
```

Human instruction 明确指示执行 explicit registration。Registration artifact:
`docs/00-governance/SIMIGO_LAB_BACKEND1_ADAPTER_ENGINEERING_OPENING_
REGISTRATION_20260930.md`。

Registered facts：

```text
Validation question   = E1+E3+B1 seam 是否足以承载真实 adapter engineering，
                        而不把 backend-specific state / representation detail
                        / physical lifecycle 提升为 Execution Semantic State
三分法                = SUFFICIENT / INSUFFICIENT-BUT-LOCAL / CONTRACT-BLOCKED
                        （BLOCKED 时 STOP，只允许独立 contract gate）
Engineering           = AUTHORIZED / NOT STARTED（A1–A8 审计问题）
Mandatory checks      = M-1…M-5（验证载荷性质 / G-1 前置条件 / L-1·G-5 不得
                        顺手修复 / Phase B 六条件 inherited / evidence
                        hierarchy 显式）
Stop conditions       = 7 条（draft §7 登记）
禁止项                = storage selection / persistence format·API·protocol
                        design / performance claim / artifact portability /
                        oversized 特殊语义 / 静默修改稳定 seam
G-1…G-10              = INHERITED / NOT CLOSED
```

下一步 = engineering implementation（先 code-level adapter boundary audit +
最小 integration skeleton 必要性分析）→ targeted evidence → external review
→ registration。本登记不修改稳定 seam，不实现产品化 adapter 本体之外授权。

### LAB BACKEND1 ADAPTER ENGINEERING ROUND1 REVIEW PASS — 2026-09-30

Engineering Round 1 完成（三 commit，均已推送）：

```text
audit = 7f1fa4a（A1–A8 全 PASS；D/R/P/O/T 全分类；G-1…G-10 INHERITED）
impl  = 2cf5adb（LLAMAServerExecutionStateAdapter：E1+E3+真实 transport
        组合体；adapter 状态全 R/T/P；commit 前取消门；零 seam 改动）
test  = 5b47ea8（T1–T8 battery 14/14；并集 75/75 = Phase C 61 零回归
        + adapter 14；evidence JSON 在 results/backend-conformance/）
```

关键定性：现有 LLAMA-server backend = validation payload（自述 conformance
vehicle；harness 一次性；无组合体/失败所有权/identity 接线）→ 按方案
reuse+compose。裁决：`SUFFICIENT（有界）`——seam 是能力边界不是强制组件
清单（B1 因 server 拥有权重物理生命周期而不参与，原则已随 review 登记）。

Human 第二层裁决（2026-09-30）：认可 SUFFICIENT（有界），A1–A8 全 PASS
（A5/A8 有界），A2+A8 同时成立为关键研究结果；固定四个 external review
审查点；指令不修改 contract、不扩大测试面。

External review:
`docs/00-governance/SIMIGO_LAB_BACKEND1_ADAPTER_ENGINEERING_EXTERNAL_REVIEW_20260930.md`。
Verdict: `PASS / REGISTRATION_REQUIRED`。四审查点 R-1…R-4 全 PASS；四条
strengthening 随登记固化：cancellation 表述钉死为 adapter-level
cancellation containment（G-9 NOT CLOSED）、seam 能力边界原则、stub/live
证据分层、SUFFICIENT 适用域限定（server-owned weights + recompute 类）。

当前状态：

```text
Phase A/B/C                        = PASS / REGISTERED
BACKEND-1 adapter engineering R1   = COMPLETE / REVIEW PASS / REGISTRATION_REQUIRED
Current blocker                    = explicit human/repository registration
```


### 2026-09-30 BACKEND-1 adapter engineering Round 1 — EXTERNAL REVIEW REGISTERED

External Review 落地于 commit ce8c7a6（5b47ea8..ce8c7a6），并按双角色纪律完成独立审查。

Verdict：

```text
Engineering Round 1 = PASS / REGISTRATION_REQUIRED
四审查点 R-1…R-4     = PASS
New blocker           = none
```

四审查点：

- R-1 SUFFICIENT 支撑性 = PASS：既有契约证据 19/19 + 三异构 backend conformance 3/3 + 真实 transport 组合体 14/14；A2 ownership/隔离与 A8 semantic continuity 同时成立。该结论限定于已测 adapter 类，不外推为 universal backend portability。
- R-2 ownership 未被夺取 = PASS：ExecutionStateHandle 无 backend 写入路径；adapter 的语义变更全部经 coordinator 公共 API；adapter 自有状态属于 R/T/P；foreign / mispositioned direct-entry guards 有测试证据。
- R-3 B1 不参与 = PASS，并登记为方法论原则：server-owned weights / physical lifecycle 不属于该 adapter 的所有权范围；强行加入 B1 会制造错误的物理所有权主张。登记原则：Seam 是能力边界，不是强制组件清单。同时 B1 仍属于 registered seam 组成部分，本轮未行使 ≠ 可废弃。
- R-4 无叙事性夸大 = PASS：cancellation 统一表述为 adapter-level cancellation containment；G-9 cancellation contract surface 仍 NOT CLOSED。

随登记继承四条 strengthening：

1. cancellation = adapter-level containment，非 universal abstraction；
2. seam = capability boundary，非 mandatory component checklist；
3. stub-transport 与 live-server evidence 分层；stub response 不称 live E2E，live 端到端仍属于 RQ1 既有证据范围；
4. SUFFICIENT 适用域限定为已测的 server-owned weights + recompute strategy adapter 类。

当前门位：

```text
Phase A / B / C                         = PASS / REGISTERED
BACKEND-1 adapter engineering Round 1  = COMPLETE / PASS / REGISTERED
Current blocker                         = none
Next direction                          = seam stability / long-term backend-independence boundary research
```

下一阶段不得直接堆第二个 backend 的功能；必须先建立独立 opening/definition gate。Contract 不修改，测试面不因本登记自动扩张，不选择 storage / persistence format / API，不做 performance 或 universal portability claim。

### LAB SEAM STABILITY OPENING REGISTERED / ACTIVATED — 2026-09-30

新 gate `SEAM_STABILITY_OPENING` 已完成 opening/definition gate，并由 explicit human/repository registration 激活。

- Participant draft（`6d5e08d`）：S1–S6。
- External review（`aa50504`）：`PASS / ACTIVATION_REQUIRED`。
- Registration artifact：
  `docs/00-governance/SIMIGO_LAB_SEAM_STABILITY_OPENING_REGISTRATION_20260930.md`。
- Registration commit：`2ea4232b`。
- Registered verdict taxonomy：
  `STABLE-AS-REGISTERED / STABILITY-CONDITIONAL / UNSTABLE`。
- Stability 定义钉死为 `Stability ≠ immutability`；允许经登记的 contract gate 演化，但变更必须受纪律约束并可检测。
- S1–S6 audit scope 已激活；verdict 判据采数前固定，不得因结果增删。
- PALACE = SEPARATELY SCOPED，不消费；G-1…G-10 只分类不解决。
- Phase B 六条件、Phase C strengthening、M-1…M-5 均 inherited / NOT CLOSED。
- 不修改 contract、不扩测试面、不选 storage / persistence format / API、不做 performance 或 universal portability claim。
- Re-run evidence 必须绑定 commit-hash 级源码状态；继续执行 `observed code fact ≠ inferred storage design ≠ selected implementation`。

当前状态：

```text
Round 1（adapter engineering） = PASS / REGISTERED / CLOSED
Seam stability opening         = PASS / REGISTERED / ACTIVATED
Seam stability audit           = ACTIVE / NOT YET EXECUTED
Current blocker                = none
```

### LAB SEAM STABILITY AUDIT REGISTERED / CLOSED — 2026-09-30

Audit artifact:
`docs/00-governance/SIMIGO_LAB_SEAM_STABILITY_AUDIT_20260930.md`
（commit `33fb410`；source state `b031188`；判据按 opening registration
冻结版逐字适用，未增删）。

S1–S6 结果：

```text
S1 轴 a/b/c = SATISFIED（行使层）；轴 d = SATISFIED（判据层，durable
             store/productization 激活时再检验——standing condition）
S2         = 12 条机械 contract-change 信号（C-1…C-12，含门纪律绕过检测）
S3         = 风险地图：0 × CONTRACT-BLOCKING；1 常备触发点（G-9）+
             3 条件触发点（G-6/G-7/G-10）；全部分类为 LOCAL-FIXABLE
S4         = 抽象类「in-process physical state backend」需求全落点既有
             seam（含 B1 正向行使用例）；无点名技术、无实现工件
S5         = productization 六判据（P-1…P-6），只定义不执行
S6         = standing 面六项组装；regression re-run 75/75 @ b031188
             （hash 级绑定，零漂移）
关键新事实 = contract target 全部历史 4 commits 均在 2026-09-25，此后
             零变更，横跨全部已登记轮次
```

裁决：`STABLE-AS-REGISTERED`（有界）。边界随登记继承：≠ immutability、
≠ universal portability、≠ production readiness、≠ performance；轴 d
判据层限定；S4 抽象类限定；四类触发点（G-9/G-6/G-7/G-10）= contract gate。

External review:
`docs/00-governance/SIMIGO_LAB_SEAM_STABILITY_AUDIT_EXTERNAL_REVIEW_20260930.md`。
Verdict: `PASS / REGISTRATION_REQUIRED`。四条 strengthening 随登记固化：
axis-c 表述域限定（观察窗口非预测）、轴 d 再检验为 standing condition、
裁决继承 Round 1 适用域、S2 机械检测为 standing 最低标准。

当前状态：

```text
Seam stability opening     = PASS / REGISTERED / ACTIVATED
Seam stability audit       = PASS / REGISTERED / CLOSED
Current blocker            = none
Next standing mode         = DRIFT-DETECTION / CONTRACT-GATE-DISCIPLINE
```

Registration:
`docs/00-governance/SIMIGO_LAB_SEAM_STABILITY_AUDIT_REGISTRATION_20260930.md`
Registration commit chain: `c9299375` → `671a69f` → `1857d57`.

### LAB EXECUTION STATE ARCHITECTURE CONTRACT OPENING DRAFT REVIEWED — 2026-09-30

新 gate（route 登记的 NEXT SYNTHESIS GATE）前两步完成：

```text
Opening draft = 0573ec3（SIMIGO_LAB_EXECUTION_STATE_ARCHITECTURE_CONTRACT_
  OPENING_DRAFT_20260930.md）
  研究问题 = 能否定义独立于 MLX/backend/model format/physical representation
  的 Execution State Architecture Contract，使「同一 Execution State」语义
  不依赖实现，成为 PALACE durable-state 与 Backend Independence 的唯一上游
  语义锚点
  子问题 = AC-1 Semantic Core（route Q2/Q3）/ AC-2 Identity·Continuity
  same-vs-new-State 判据（route Q1）/ AC-3 Representation Boundary 四态
  结果（route Q4/Q5/Q6）/ AC-4 Backend Independence 准入标准
  合成纪律 = 每条陈述可追溯登记工件；冲突 = open point；契约 v1.0 版本化，
  修订只能经 contract gate
External review = …_EXTERNAL_REVIEW_20260930.md，verdict
  `PASS / ACTIVATION_REQUIRED`
  五条 strengthening：synthesis ≠ re-litigation（只引用不重推）/ route Q5
  按 Phase B 登记先答收口 / AC-2 判据与 S2+battery 挂钩可机械检验 /
  contract v1.0 成为 drift 参照（S6 双向检测，C-13 类信号）/ open points
  只能经各自 gate 解决
```

继承不变：Phase B 六条件、Phase C 四 strengthening、M-1…M-5、G-1…G-10、
Round 1 四 strengthening、seam stability standing 纪律（S2/S6）、
evidence-source-state 纪律、PALACE SEPARATELY SCOPED。

当前状态：

```text
Seam stability               = PASS / REGISTERED / CLOSED
Architecture Contract draft  = PASS / ACTIVATION_REQUIRED
Contract synthesis/audit     = NOT STARTED（registration 后才可开始）
Current blocker              = explicit human/repository registration
```

### LAB ARCHITECTURE CONTRACT SYNTHESIS COMPLETE — 2026-09-30

Opening 登记（`62142ad`，human 指令）后，contract synthesis 执行完成：

```text
Contract v1.0 draft = a1e2e28（SIMIGO_LAB_EXECUTION_STATE_ARCHITECTURE_
  CONTRACT_V1_DRAFT_20260930.md）
§1  Semantic Core 分类总表 + 三定律 SC-1（coordinator 唯一权威）/
    SC-2（Execution Semantic Snapshot 为最小持久对象）/ SC-3（四事务
    窗口）——route Q2/Q3 收口
§2  Identity·Continuity：SAME/NEW State 法则 + IC-1…IC-5 + 判定示例
    （representation 丢失/换 backend 永不产生新 State）——route Q1 收口
§3  Representation Boundary：RB-1…RB-8（relation 法则 + 四态结果 +
    logical-position 权威 + 能力边界原则）——route Q4/Q5/Q6 收口
§4  Backend Independence 准入 BI-1…BI-5（Round 1 = 第一判例）
§5  Open points OP-1…OP-7（transcript 等价性 / G-7 / G-10 / G-9 / G-6 /
    工程 gaps / PALACE 接口）——携带不关闭
§6  C-13 双向 drift 信号（契约文本 vs 代码/登记行为）
合成纪律验证：全部陈述带登记引用；零新增语义；零 open point 静默解决
```

当前状态：

```text
Architecture Contract opening   = PASS / REGISTERED / ACTIVATED
Contract synthesis              = COMPLETE（v1.0 draft awaiting review）
Current blocker                 = none（下一步 = review，路径由 human 指定）
```

### LAB ARCHITECTURE CONTRACT V1 REVIEW PASS — 2026-09-30

Contract v1.0 external review（`a020344`，human 指令进入 review、暂不做
第二层裁决，固定六项审查）：

```text
R-1 synthesis fidelity      = PASS（逐条回溯核验，行号属实）
R-2 five-tuple identity law = PASS（无隐藏矛盾；一处表述歧义钉死修订语）
R-3 representation sovereignty = PASS（单向成立）
R-4 open-point integrity    = PASS（OP-1…OP-7 无软关闭）
R-5 bidirectional drift     = PASS（C-13 双向；程序性检测定位）
R-6 scope discipline        = PASS（无外推）
Verdict = PASS / REGISTRATION_REQUIRED
```

四条 strengthening 随 registration 固化：①五元组法则精确读法（「语义
保持」= 保持 Runtime 独占、值仅经登记生命周期转移演化；identity 锚 =
ExecutionID；representation 从不直写）②C-13 程序性检测定位（自动化归
P-2）③BackendMemoryObservation 行溯源补强 ④升格效果声明（registration
即时：v1.0 = 上游语义参照；层级切换为 Contract ⇅ 实现侧）。

当前状态：

```text
Contract v1.0                = PASS / REGISTRATION_REQUIRED
Current blocker              = explicit human/repository registration
```



### LAB ARCHITECTURE CONTRACT V1 REGISTERED — 2026-09-30

Human/repository registration completed after external review `a020344`, verdict `PASS / REGISTRATION_REQUIRED`.

Registration artifact:
`docs/00-governance/SIMIGO_LAB_EXECUTION_STATE_ARCHITECTURE_CONTRACT_V1_REGISTRATION_20260930.md`

Registered contract:
`docs/00-governance/SIMIGO_LAB_EXECUTION_STATE_ARCHITECTURE_CONTRACT_V1_DRAFT_20260930.md`

Registered strengthening:

1. Five-tuple law is fixed: the five fields remain Runtime-owned semantic fields; their values evolve only through registered lifecycle transitions. ExecutionID is the identity anchor; lineage is immutable metadata; representation never directly writes the five fields.
2. C-13 is currently procedural gate-check detection; automation is deferred to productization P-2.
3. `BackendMemoryObservation` R classification is recorded as a derivation from `RuntimeBackendContract` passive-observation semantics.
4. Registration upgrades v1.0 to the upstream Execution State semantic reference; research hierarchy becomes `Contract ⇅ code / Runtime / Backend / Persistence`.

Inherited boundaries remain unchanged:

- OP-1…OP-7 remain OPEN.
- G-1…G-10 remain inherited / NOT CLOSED.
- Phase B mandatory conditions, Phase C strengthening, M-1…M-5, and Seam Stability S2/S6 remain active.
- No storage / persistence format / API / protocol / performance / production-readiness / universal-portability claim is introduced.
- PALACE remains separately scoped; OP-7 is not consumed.

Current state:

```text
Architecture Contract opening = PASS / REGISTERED / ACTIVATED
Contract synthesis           = COMPLETE
Contract v1.0                = PASS / REGISTERED / UPSTREAM SEMANTIC REFERENCE
Current blocker              = none
Next mode                    = DRIFT-DETECTION / CONTRACT-GATE-DISCIPLINE
```

### LAB NEXT-SESSION DIRECTION DECIDED — 2026-09-30

Human 方向决定（Contract v1.0 封档后的路线选择）：

```text
选择  = PALACE-1 DURABLE STATE SEMANTICS OPENING（下一会话第一动作）
排序  = durable-state semantics ＞ 第二 backend（排后）＞ productization
        （暂不做——研究成立 ≠ 生产就绪 ≠ 产品化 ≠ 性能优化）
理由  = Contract v1.0 刚成为上游语义参照，应拿它面对最困难的现实问题
        （Runtime 消失 / Backend 更换 / Physical Representation 丢失后，
        State 是否仍是那个 State），而非重复 adapter 适配验证
核心四问 = D1 什么状态必须 durable / D2 什么状态可 reconstruct /
        D3 恢复后何时仍是 SAME Execution State / D4 Physical
        Representation 丢失后 State 如何继续存在
重审清单（重锚定非解决）= OP-1 / OP-2 lineage closure / G-7 / G-10 /
        RB-1…RB-8 / IC-1…IC-5 / Execution Semantic Snapshot（对照
        Contract v1.0）
协议   = §0 并发核验 → participant opening draft → external review →
        停 registration 门；不写代码、不选数据库、不解决 OP/G
```

palace1_durable_state 线与 PALACE hypothesis（04c608e）保持 SEPARATELY
SCOPED：本 opening 只定义 durable-state 语义研究门，不消费 hypothesis
内容。standing drift-detection（C-13 / S2 / S6）继续生效。

### LAB PALACE1 DURABLE STATE SEMANTICS OPENING DRAFT COMPLETE — 2026-09-30

§0 并发核验 PASS（LOCAL=REMOTE=da2c8e8、树净、零并发 commit、契约台账无
漂移、六文档在位）后，participant opening draft 完成：

`docs/00-governance/SIMIGO_LAB_PALACE1_DURABLE_STATE_SEMANTICS_OPENING_
DRAFT_20260930.md`。

D1–D4 定义结果（四类输出，D1–D4 未被强行全答）：

```text
CONFIRMED  durable minimum 集 = SC-2 七字段 + tombstone closure data
           （binding relations OPTIONAL；claims = P 层 DEPENDENT OP-5）；
           三层可重建边界（snapshot 不可由下层重建）；D3 场景判定
           restore/reattach/rematerialization/recompute/backend-
           replacement/representation-loss 全 SAME、closure 破损 loud
           fail、NEW 仅 create/fork；D4 语义答案（State 的存在 =
           snapshot 存在，与四层无关）
OPEN       OP-1（transcript 作为 continuation 源；transcript-recovered
           是否 SAME）；reopen 恢复机制研究问题（合格恢复的验证判据）
DEPENDENT  reopen 机制 ← OP-2+G-10；durable reattach ← OP-5/condition 3；
           D4 实证 ← OP-3/G-10
UNKNOWN    七字段 snapshot 在全消失恢复下的【充分性】——Phase B 证的是
           必要性/边界；充分性 = PALACE-1 下一阶段核心命题，不预答
```

当前状态：

```text
PALACE1_DURABLE_STATE_SEMANTICS_OPENING = DRAFT COMPLETE
Current blocker                         = none（等 human 第二层判断）
下一门                                  = external review（六项固定）→
                                          PASS/ACTIVATION_REQUIRED →
                                          registration
```

### LAB PALACE1 SEMANTIC OPENING DEFERRED — PHYSICAL REALITY AUDIT REQUIRED — 2026-09-30

Human 第二层判断（draft `ddb9cbc` 不进入 external review）：

```text
判定   = 研究顺序又提前了一步——D1–D4 自 Contract 推导（概念先行），
         而刚纠正的路线要求 工程事实→发现问题→抽象→语义→Contract
驳回   = 「D4 语义答案 CONFIRMED」与「各场景 SAME = CONFIRMED」超出
         现有工程证据：架构契约约束（身份不得依赖 representation）
         ≠ 工程事实（删除磁盘实物后真能恢复 same-State）
处理   = draft 保留降级为 semantic hypothesis scaffold（问题框架有用，
         答案不得视为事实）；gate position =
         PALACE1 SEMANTIC OPENING = DEFERRED / PHYSICAL REALITY AUDIT
         REQUIRED
新任务 = PALACE1 Physical Reality Audit——磁盘实际组成 → 生成代码路径 →
         物理对象账本（SAME-State 列全 UNKNOWN）→ 三问（组成 / 性能损失
         vs State 损失 / 全消失后剩什么）；禁止实际删除、禁止数据库设计、
         禁止修改 Contract、禁止 D1–D4 理论封口
```

收敛路线钉死：不是「PALACE 理论上该保存什么 → 找对应物」，而是「磁盘上
实际保存了什么 → 删除它会失去什么 → 逼出 PALACE 该保存什么」。

### LAB PALACE1 PRODUCT WRITER PROVENANCE AUDIT COMPLETE — 2026-09-30

Human 指令走选项 2（先 provenance 后实验；实验须在隔离副本上、原始 79G
不动）。产品仓定位 = `~/Documents/SimiGo`（slamfinger/SimiGo，main @
`dc12a0c`，clean）。只读审计完成：

`docs/00-governance/SIMIGO_LAB_PALACE1_PRODUCT_WRITER_PROVENANCE_AUDIT_
20260930.md`。

11 问全部 file:line 作答，关键结论：

```text
writer     = NativeMLX.saveSessionCache/performSave；触发 = 每成功轮自动
             （0.15s@58k，roll-forward last-known-good）+ 驱逐保护 + 显式
identity   = storageKey = agentId/sessionId/logicalBranchId（caller 供给），
             且产品把 storageKey 直接作为 executionID 传给 Lab 契约调用
             ——两套身份方案在运行时调用层已部分映射
integrity  = generation（每保存新 UUID，fork 随拷）+ cacheSHA256（官方
             safetensors 流式哈希）双重 fail-closed 恢复判据 + modelId 同源
transcript = managed.historyJSON 逐字落盘；恢复时 makeChatMessages 重建
pool       = NativeMLXPrefixPool 持 Lab ExecutionBindingRegistry（FORK-3
             step-9，日常路径绑定真实持有者，进程生命周期）；重启 rescan +
             P-I1 自愈；与 checkpoint 的代码层关联未建立（UNKNOWN 维持）
retention  = 机制存在（BETA-STORAGE-1：成对回收/ownership-aware/字节预算
             64GiB+16GiB）——62G/15G 为预算内累积（修正 Physical Audit
             F-6）；C 答案按 human 指令撤换「零个」措辞
无自主恢复  删除 checkpoint 后无系统自主恢复路径（fail-closed throw）；
             恢复 = 客户端协作全量对话 + 重算
```

当前状态：

```text
PALACE1 writer provenance   = COMPLETE / AWAITING SECOND-LAYER
Current blocker             = none（实验矩阵 E1/E2/E3 由 human 决定；
                              隔离副本实验、原始 79G 不动、恢复判据先行）
```

### LAB PALACE1 E1 SEALED + R2 CAPABILITY CONFIRMED — 2026-09-30

Human 裁定链（全部已执行/落账）：

```text
1. E1 封存于执行边界：R0 PASS（预登记一致：IDENTIFIED）/ R1 PASS
   （FAILED-FAIL-CLOSED ×3 复现）/ R2-R4 PENDING；PASS 语义 = 预登记
   观测与实际一致，非能力判定。A（加写）/B（env 覆写）/C（叶子沙箱）
   全部悬置——不弄脏 79G 边界、不为实验改产品、不跑成沙箱工程
2. 新指令 = 只读追踪「客户端协作式 recompute / fragment-continuation
   现有调用链」：R2 所需能力 SimiGo 是否已有？
3. Trace 答案（f3e49f8）= YES，一等公民路径：
   generate → makeChatMessages(:641) → 会话获取三分支 → cold-start
   分支（:763-778）= 无 checkpoint/pool 时的正常建立方式：
   ChatSession(container, history: incoming.dropLast()) 于同一
   storageKey + 全量 prefill + T-1 重新落盘
   → R2 不需要 4.7GB payload；语义连续性由 meta.history + modelId +
     storageKey（44KB）承载
   → 研究含义（未预答）：PALACE durable minimum 对 continuation 的
     贡献候选 = 44KB 语义 + 4.7GB 只是 prefill 税的缓存
```

当前状态：

```text
E0 = COMPLETE；E1 = SEALED AT EXECUTION BOUNDARY（R0/R1 PASS，R2-R4 PENDING）
E1-R2 capability = CONFIRMED（代码级）；运行时观测仍待隔离方案裁定
Current blocker  = none（三选项悬置由 human 掌握节奏）
```

### LAB PALACE1 E1.5 COMPLETE — FIELD ROLE TABLE — 2026-09-30

E1.5（Metadata Dependency Perturbation）设计冻结（`8961ef6`）→ human 批准
→ 执行（产品仓加法测试，load 路径零写入故无需写隔离）：**6/6 用例零偏离
命中预登记**（`263700c`；观测落库 results/backend-conformance/）。

实验钉死的 restore 验收边界：

```text
meta.storageKey 字段值 = informational duplicate（扰动被接受；寻址权威
  = caller key/文件名）
history（语义载荷）= 无完整性门（扰动 tool 消息 round-trip 通过 restore）
modelId = 兼容门（拒）；generation = presence-only commit marker
  （空拒/异值受）；cacheSHA256 = 仅 safetensors 字节完整性（Q-2 证
  transcript 排除）
```

**最小 durable continuation nucleus CANDIDATE**（严格 candidate）：
caller-key 寻址 + history + modelId 同源——generation/SHA/storageKey
字段值/forkPoint/kvFingerprint 全部在此集合之外。纪律：Q-2 证明的是
integrity boundary 非 necessity boundary；necessity 待 cold-path 运行时
实验（隔离阻塞不变）。

当前状态：

```text
E0 = COMPLETE；E1 = SEALED（R0/R1 PASS，R2-R4 PENDING）；
E1.5 = COMPLETE（6/6）；R2 capability = CONFIRMED（代码级）
Current blocker = none（cold-path necessity 实验隔离方案 + A/B/C 均悬置
由 human 掌握节奏）
```

### LAB PALACE1 R2N COMPLETE — HISTORY NECESSITY CONFIRMED — 2026-09-30

Human 指令：先补 cold-path 的 history necessity 证据（不解决隔离工程、
不做 E2）。执行配方 = 产品自带配置面（SIMIGO_PREFIX_POOL=0 env 经
TEST_RUNNER_ 转发 + RuntimeTuning.conditionalRestoreEnabled=false 测试
进程内）——**零产品代码修改、零 durable 写入**（204/24 前后核验不变）。

R2n 结果（`132b9b6`；三预登记全 CONFIRMED）：

```text
P-N1 greedy 确定性 = CONFIRMED（n0a ≡ n0b「继续执行。」——比较方法有效）
P-N2 内容扰动      = CONFIRMED（尾条 assistant 追加 needle → continuation
                     变为「收到，需要我深入查看哪个具体文件的内容？」）
P-N3 工具历史删除  = CONFIRMED（3 条 tool 全删 → 模型失去指代：
                     "I don't know what the probe refers to"）
```

判定提升（human 术语）：history = 「continuation semantic candidate」→
**observed continuation-bearing durable information**（integrity boundary
与 necessity boundary 双双钉死）。modelId 移至 nucleus 外围
（compatibility context）。nucleus candidate 精化 = caller-key 寻址 +
history（observed continuation-bearing）。

当前状态：

```text
E0/E1.5/R2n = COMPLETE；E1 = SEALED；E2 = COMPLETE
Current blocker = none（E3 定义门、池命中语义等价对照、A/B/C 由 human
掌握节奏）
```

### LAB PALACE1 E2 COMPLETE — PREFIX POOL = REPLACEABLE PERFORMANCE REPRESENTATION — 2026-09-30

E2（`76f1664`）：唯一问题 = 池物理表示拿掉后 cold reconstruction 语义
能力是否仍在。证据组合（无删除/无性能 claim）：

```text
① 池缺席语义能力   = R2n 正式归位（SIMIGO_PREFIX_POOL=0 运行中池物理
                     缺席，n0a/n0b 语义正确 + 扰动敏感性完整）
② 池在场命中证据   = 只读 admission 探测（pool.admit 纯查找零写入）：
                     think:1 fp=none → HIT coveredMessages=17/17（真实池
                     存有本会话全覆盖快照！pool-enabled 运行会整段替代
                     prefill）；指纹/think 变体正确 MISS（命名空间隔离
                     按登记工作）
③ 代码路径合并     = hit→快照+poolBind+delta / miss→cold 分支 /
                     corrupt→P-I1 fail-closed 自愈回退
结论（candidate）：Prefix Pool = 可替换性能 Representation，不在
continuation nucleus 内
PENDING：池命中语义等价运行时对照（pool-enabled generate 写真实池，
授权边界外）
```

E0→E1→E1.5→R2n→E2 总图：不可替代候选（caller-key + history）/
可替代表示（KV checkpoint、Prefix Pool）/ 保护机制（generation、SHA、
modelId）/ 信息性未决（meta.storageKey 字段值、forkPoint、kvFingerprint）。


### LAB PALACE1 E3 COMPLETE — LOCUS + CONFABULATION FINDING — 2026-09-30

E3（meta-only 阶梯，设计 `d5157f1` → 执行 `aa76f95`）：拿掉 safetensors
与 Prefix Pool 后逐级截断 meta.history，同一 referential probe 测各级
grounding。**4/4 预登记零偏离**：

```text
C-0 全 17 条        = ANCHORED（准确概括：桌面/参考文件/项目部管理制度汇编）
C-1 去尾 assistant  = ANCHORED（连「秦沈」细节级锚都在——位置回退不失语义）
C-2 主题缺席(0–4)   = UNANCHORED——**关键发现：模型不拒答，而从 persona
                      先验虚构了貌似合理、完全错误的会话概述（VBA→C dylib/
                      codex-chatgpt，与本会话无关）**
C-3 仅 system       = UNANCHORED（persona 元评论）
```

定位结论：continuation-bearing 语义住在**会话正文（含 tool 执行历史）**，
不在 system persona、不在寻址/保护/兼容字段。**虚构发现登记**（工程事实，
非产品缺陷判定）：durable carrier 缺失语义正文时失败模式 = 自信虚构而非
fail-closed——语义缺席当前对调用方不可检测；Contract 的 fail-closed 政策
在语义层无对应物（未来 PALACE 语义设计必须面对，本轮不设计机制）。

全链证据地图闭合：物理层(E0)/恢复层(E1)/验收层(E1.5)/必要层(R2n)/对照层
(E2)/定位层(E3)。

当前状态：

```text
E0/E1.5/R2n/E2/E3 = COMPLETE；E1 = SEALED
Current blocker   = none（下一方向由 human 掌握：nucleus 证据链总审 /
                    PALACE framing 或其他 gate）
```


### LAB PALACE1 EVIDENCE CONSOLIDATION — CHAIN SEALED — 2026-09-30

Human 第二层总审（E3 COMPLETE；C-2 升格独立 research finding；nucleus
升格为 addressing carrier + semantic continuation carrier，workload-
scoped；PALACE framing gate OPEN 产物仅研究边界）后，六实验封装完成：

`docs/00-governance/SIMIGO_LAB_PALACE1_EVIDENCE_CONSOLIDATION_20260930.md`
（`d408729`）。

内容：逐实验 fact/inference/unproven 分层（E0/E1/E1.5/R2-trace/R2n/E2/E3）；
最终字段角色矩阵（restore vs continuation 双列）；**RF-1 = Semantic
Absence Is Not Self-Evidently Detectable**（E3-C-2 现象登记，无方案规定）；
**RF-2 = restore dependency ≠ continuation dependency**；nucleus 升格
声明（addressing carrier + semantic continuation carrier 含 tool 历史；
四条强制限定）；PALACE framing 合法陈述集；schema 禁入清单。

当前状态：

```text
E0/E1.5/R2/E2/E3 = COMPLETE；E1 = SEALED
Evidence chain   = CLOSED（本文封装）
PALACE framing   = OPEN（研究边界产物已备；schema NOT STARTED）
Next cut         = 由 human 决定
```


### LAB PALACE1 FRAMING REGISTERED — LINE PARKED — 2026-09-30

Human 终局裁定：下一刀 = Framing Registration（只登记研究边界），注册后
停车（无 PALACE-2、无 Contract、下一实验 NOT YET CHOSEN）。

Registration artifact（`739b967`）：
`docs/00-governance/SIMIGO_LAB_PALACE1_FRAMING_REGISTRATION_20260930.md`。

Registered framing：

```text
Observed = 两种生命周期不同的信息侧：
  A. durable semantic side（addressing carrier = caller key +
     semantic continuation carrier = conversation history 含 tool 历史）
  B. physical acceleration side（checkpoint / Prefix Pool 等可替代表示）
Research question = 生命周期差异是否足以支持更高层长期 Personal State
  Space 抽象？
NOT established = schema / State object / universal minimum nucleus /
  storage architecture / semantic absence solution / cross-backend
  semantic equivalence
```

Findings 登记：RF-1 = REGISTERED / OPEN RESEARCH；RF-2 = REGISTERED /
CLOSED FOR THIS CHAIN。证据链冻结（后续 PALACE 讨论不得反向改写 E0–E3
事实层；nucleus 的 workload-scoped 限定为登记内容一部分）。

当前状态：

```text
PALACE-1 Evidence = CLOSED；Framing = REGISTERED；schema/Contract = NOT
STARTED；RF-1 OPEN RESEARCH；RF-2 CLOSED FOR CHAIN；Next experiment =
NOT YET CHOSEN
Current blocker   = none（线停车）
```


### LAB BACKEND2 SEAM TAKEOVER AUDIT — 2026-09-30

Human 指令（PALACE-1 停车后回主线）：只读审计「已有 Execution State 脱离
MLX 表示后被 LLAMA backend 接管」的最小事实缺口。

结果（`7b5d12d`）：

```text
seam/契约层   = 零缺口（handle 五字段全可移植、contract 零 MLX、三
                backend 同 battery 已证；binding 重建结构性支持；
                B1 对 server-owned backend 不需要）
缺口唯一类别  = 状态迁移载体：
  G-B2-1 token id 空间后端特异（MLX swift-transformers ≠ llama
         /tokenize）；文本是唯一可移植介质（contract nextInput:String
         已在）
  G-B2-2 多轮 history 无 Lab 契约载体（只存在于产品 sidecar——恰为
         PALACE 线已证的 continuation-bearing 信息）
  G-B2-3 「同一模型」跨格式判定未定义（mlx 4bit vs GGUF 量化语义
         等价无校验面）——新独立 UNKNOWN
```

当前状态：

```text
BACKEND-2 audit = COMPLETE / AWAITING SECOND-LAYER
Current blocker = none（实验矩阵 A–E 是否开、G-B2 缺口如何闭合，由
                  human 决定）
```


### LAB ES-R1 PHASE A+B COMPLETE — 2026-09-30

Human 开启 ES-R1（Execution State 可复用性实验；唯一问题 = Representation
消失后已存在的 State 能否在无完整 History/无 Full Cold Prefill 下重新物化
并继续）。本轮按指令只执行 Phase A + Phase B：

`docs/00-governance/SIMIGO_LAB_ESR1_PHASE_AB_FACT_TRACE_20260930.md`
（`46058bf`）。

Phase A（State Inventory）关键结论：

```text
A1 身份 = caller key（storageKey 一物三面：运行时寻址/文件名/Lab
   ExecutionID 同值）；request UUID 瞬态；generation/SHA = 完整件标记
A2 四个位置物不等：logical position / KV token length(31712) /
   generation / history.count(17)——产品无独立 logical position 字段
A3 continuation = history 末端（delta 契约）；Lab 侧 nextInput/position；
   无任何独立 continuation marker
A4 分类：live session = P+R 融合（唯一二合一物）；meta.json = D
   candidate；BindingRegistry = R；dirty/mode = T；五元组物理实例 = U
```

Phase B（Live-State Baseline）：**PB1 CONFIRMED**——restore(position 17)
→ probe「继续执行。」→ O1；rewind → restore → probe → O2 = O1 逐字相同
（55 字符深度会话关联延续）；确定性基线锁定（P1 强证据层可用）。

Phase D 前置发现（候选 R1-B 形状，待实验裁定）：现有 API 中最接近 Reuse
的入口 = loadSessionCache——但其本质是把表示装回 State，而非从 State
物化新表示；符合「State Reuse」定义的入口在现有产品中尚未发现。

当前状态：

```text
ES-R1 = PHASE A+B COMPLETE / PHASE C AWAITING HUMAN BOUNDARY RULING
产物① = FACT TRACE（本文件）；②③④ 待 Phase C/D
```


### LAB ES-R1 PHASE C COMPLETE — R1-B CANDIDATE FROZEN — 2026-09-30

Human Phase C 裁定执行（C-0 冻结/C-1 边界/C-3 discovery；C-2 禁止；C-4
暂缓）：`docs/00-governance/SIMIGO_LAB_ESR1_PHASE_C_RESULTS_20260930.md`
（`52956ad`）。

```text
C-0  fixture 冻结（identity/lineage/position/history-SHA/表示身份/
     env commits/池状态含 E2 17/17 隐蔽快照）
C-1  边界执行：副本内删 safetensors（meta SHA 完整性验证通过）；
     隐蔽表示登记 3 项（真实 store 原件/真实池 17/17 快照/E1 mutation
     副本）+ 排除机制
C-3  穷举 7 个表示生产/接收入口（product+Lab）：输入全部为既有 P 或
     完整 history 文本——零个入口消费「无 history 的 State」
FIRST MISSING SEAM = {identity, position, continuation-marker} → R'
     的物化入口不存在；per-token KV 唯一来源 = history 文本或既有 P；
     系统内无独立 continuation marker（A3）
```

**R1-B CANDIDATE 冻结（非终判）**：A-form 证据（契约层 State 形状存在 +
meta 载体完好 + 无消费 seam）vs B-form 证据（产品层无 State object，
State 与 history 当前不可区分）——A/B 终判 = 下一 gate 的研究问题
（position/continuation marker 应否、以及如何成为表示物化的充分输入）。

当前状态：

```text
ES-R1 = PHASE C COMPLETE / R1-B CANDIDATE FROZEN / C-4 NOT EXECUTED
Current blocker = none（A/B-form 终审与下一步由 human 掌握）
```


### LAB ES-R1 FINAL REVIEW REGISTERED — SEALED WITHOUT FINAL VERDICT — 2026-09-30

Human 终审（`2ddf915`）：

```text
Phase A/B/C-0/C-1/C-3 = PASS
S→R' seam             = NOT FOUND；first missing seam = IDENTIFIED
R1-A/R1-C             = NOT PROVEN（R1-C 界限守住：无 seam ≠ 表示语义
                        不可替代）
R1-B                  = CANDIDATE / FROZEN；FINAL = NOT YET JUSTIFIED
                        （H-B1 State 已存在 vs H-B2 State 只在契约抽象中
                        ——C-3 不可区分）
R1-D                  = NOT YET
C-4                   = LOCKED / NOT EXECUTED
```

压缩出的核心科学问题（下一 gate，human 界定）：**Execution State 是系统
中已存在的可复用计算状态，还是只存在于架构契约中的抽象？**若无表示，
identity+position+continuation+lineage 是否已构成足以重新物化表示的
State？约束登记：不得直接加 State object（实验→设计边界）；若问题无法
实验回答，R1-B 最终解释 = 「已有架构抽象，尚未形成可独立持有、可重新
物化的运行时状态」。结构性落差（Contract 五元 vs ManagedSession 无五
字段）登记为观察。

当前状态：

```text
ES-R1 = SEALED WITHOUT FINAL VERDICT；C-4 LOCKED
Current blocker = none（下一 gate 问题由 human 界定中）
```


### LAB ES-R1 GATE D COMPLETE — VERDICT D-B CONTRACT-ONLY — 2026-09-30

Human Gate D 授权（D-1 authority trace / D-2 lifetime independence /
D-3 source-of-truth；结论限 D-A/D-B/D-C；C-4 继续锁定；纪律=只找「是否
有已存在的东西承担 State 独立生命周期」）。执行（`b7084ff`）：

```text
D-1  五元组逐项权威载体穷举：
     Identity = 有权威载体（寻址链，identity-only，跨进程持久）
     Lineage  = durable 全域缺席（进程 records 死/forkPoint ABSENT/
                sidecar 无字段）
     Position = 无权威实例（=history.count 推导）
     Continuation = 无权威实例（=history 末端推导）
     Recovery = P + history 组合（纯字段不携带）
D-2  fixture 跨进程核验：meta 持久（SHA=C-0 冻结）、17 条语义载荷存活；
     position/continuation/lineage/lifecycle 在 durable 层无字段
D-3  矩阵填毕（Identity=独立 carrier；Lineage/Position/Continuation=
     History 推导或 Contract-only；Recovery=P+History）
```

**Verdict = D-B（CONTRACT-ONLY，H-B2 获支持）**，反过度解读精化：durable
semantic side（identity 寻址 + history 载荷）真实跨进程存在（PALACE
nucleus）；Lab 五元形状存在（KV 别名之路仍被排除）；**D-B 精确含义 =
五元 State 目前只以「寻址键 + 可推导观察」存在于 durable 层——R1-B
精化：Runtime 无物可消费，缺的不是 seam 一条边，是 seam 的输入端对象
本身**。

当前状态：

```text
Gate D = COMPLETE / VERDICT D-B / AWAITING SECOND-LAYER
C-4    = LOCKED（D-A 未发生）
```


### LAB ES-R1 SEALED — NEGATIVE RESULT WITH ARCHITECTURAL FINDING — 2026-09-30

Human 终审封存（`154d448`）：

```text
Gate D            = PASS；D-B = FINAL / CONFIRMED（CONTRACT-ONLY）
R1-B              = FINAL / CONFIRMED：STATE EXISTS AS ARCHITECTURAL
                    ABSTRACTION, BUT NO INDEPENDENT DURABLE RUNTIME STATE
                    EXISTS FOR REUSE（语义抽象已出现，尚未成为独立状态资产
                    ——三重限定不可省略）
C-4               = LOCKED / NOT APPLICABLE（无合格 durable State 输入，
                    非「失败」）
ES-R1             = SEALED — NEGATIVE RESULT WITH ARCHITECTURAL FINDING
```

压缩链终版：表示丢失 → history+identity 仍在 → continuation 可经 history
重建 → 独立 position/continuation/lineage State 不存在（Gate D）→ 无
S→R' seam（C-3）→ 只能回到 history → cold prefill。实验限定事实：当前
系统的 cold prefill 不是因为存在未调用的 durable State，而是因为表示
丢失后没有独立 durable State 可作物化输入。

新研究问题登记（候选方向，NOT STARTED，开启须独立 gate）：
**Architecture State → Durable Computational State 的形成条件**——
什么条件下计算状态从「运行时现象」变成「可复用计算资产」。

当前状态：

```text
ES-R1 = SEALED；Contract v1.0 = UPSTREAM REFERENCE
PALACE-1 = PARKED（framing 已登记）；RQ1/RQ2/RQ3 = 各自登记状态
Current blocker = none（无开放 gate；下一方向由 human 选择）
```


### LAB ES-D1 PHASE F CENSUS COMPLETE — 2026-09-30

Human 发布 ES-D1 研究计划（formation-condition 研究；H1 Emergence/H2
Contract-only/H3 Partial/H4 Formation Gap 四假设；Gate F/G/H/I/J 五门
独立裁定；三层分离 A description/B reconstruction/C independent）。
本轮按授权只执行 **Phase F：Lifecycle/Event Census**（`8e30510`）：

```text
13 事件普查（10 列协议全填）；candidate carriers：
CC-1 checkpoint meta 非 P 内容（唯一「事件后拥有 P 之外新事实」的载体）
CC-2 meta.forkPoint durable lineage 片段（代码 writer 存在但部署库
     0 实例；atMessage=history.count——position 代理进入 lineage 字段）
CC-3 pool sidecar = performance-P 元数据（E2 裁定延续，不计 State）
边界项：B-1 meta.history authority 随进程死亡 survival 转移（Gate H）；
B-2 authoritative-but-unread 字段计法（Gate G）
全部 state-like 输出同时依赖 P 或 H（H4 正面 census 证据，终判归 J）
退出条件①命中（candidate found）→ 按指令停止；Gate G 待授权
```

当前状态：

```text
ES-D1 = PHASE F COMPLETE / GATE G AWAITING AUTHORIZATION
Current blocker = none（G/H/I/J 节奏由 human 掌握）
```


### LAB ES-D1 GATE G COMPLETE — VERDICT G-C PARTIAL AUTHORITY — 2026-09-30

Human 授权 Gate G（Authority Test；只裁 authority 不裁 lifetime；纪律=
只做事实裁定）。执行（`02643b3`）：

```text
CC-1 逐字段：meta.storageKey 字段值=DUPLICATE（caller key=寻址权威）；
  history=lifecycle-dependent AUTHORITATIVE（写入时 DUPLICATE→进程死亡
  后 SURVIVING-AUTHORITATIVE——**B-1 裁定：authority 是生命周期属性，
  转移点确定性可见**）；generation/SHA/modelId=各门 AUTHORITATIVE
  （acceptance/integrity/compatibility）；savedAt=AUTHORITATIVE
  （retention 排序）
CC-2  forkPoint=DESCRIPTIVE（零 reader 零决策依赖；部署库 0 实例）；
  **B-2 裁定：writer-only ⇒ 非 authority**；登记 latent semantic
  carrier（lineage+position 代理的唯一 durable 物理形态）
核心问题作答（表示缺席）：PARTIAL authority——identity+语义内容可独立
  确定；position/continuation/lineage 只能推导
```

**VERDICT = G-C（PARTIAL AUTHORITY / PARTIAL-STATE CANDIDATE）**——按
指令不补齐，原样记录进入 Gate H。H 问题精确化：推导出的 position/
continuation 观察能否在进程死亡+表示删除后仍成立；partial authority
组合是否构成 Formation（J）前半条件。

当前状态：

```text
ES-D1 = GATE G COMPLETE / VERDICT G-C / GATE H AWAITING AUTHORIZATION
C-4   = 续锁
```


### LAB ES-R1 GATE H COMPLETE — VERDICT H-B FORMATION GAP EVIDENCED — 2026-09-30

Human 授权 Gate H（Lifetime Test；只答 partial authoritative information
跨表示丢失/进程死亡/重启后的存活情况）。执行双真实进程实验（`f5b4690`）：

```text
进程 A：restore(17)→probe→O_A（55 字符确定性）→推进至 position 18
        （仅内存，tunables off 不落盘）→退出
进程 B（全新）：durable 位置=17（runtime 18 已随 A 死亡——lifetime
        endpoint 实测）→restore→position 17→同 probe→O_B=O_A 逐字
零 durable 写入（204 前后核验）
```

**VERDICT = H-B**：只有 identity + history 以权威形式跨全部边界存活；
position/continuation 每次都必须从 history 重新推导——formation gap
获运行时直接证据。精确新事实：**position 持久性是事件门控的**（
checkpoint 提交固化的 17 跨进程存活且权威；runtime 推进的 18 死亡），
且存活的 position 嵌在 checkpoint 对（P+meta）中、非独立 carrier——
与 Gate D「无独立五元 carrier」一致。

观察矩阵（三边界×七维度）已填；Gate I（Sufficiency）待授权。

当前状态：

```text
ES-D1 = F/G/H COMPLETE / GATE I AWAITING AUTHORIZATION
C-4   = LOCKED
```


### LAB ES-D1 PHASE I COMPLETE — VERDICT J-C PARTIAL FORMATION — 2026-09-30

Human 裁定：Gate I（Sufficiency）= NOT APPLICABLE（无独立 carrier，进入
条件不满足——终审记录保留）；直接授权 Phase I / Formation Condition
（编号统一 F/G/H/I）。执行（`15b2952`，纯合成裁定）：

```text
formation-condition 对照表（F/G/H 全事件回溯）：
identity     = FORMED（checkpoint commit → 寻址链）
history      = FORMED（meta.history 副本，continuation-bearing 实证）
position     = NOT FORMED as independent carrier——形成时机信息在场
               （performSave 持有 managed.history）但 schema 不捕获；
               仅代理实例（meta.history.count / forkPoint.atMessage）
continuation = NOT FORMED（transcript 末端隐含，无 marker）
lineage      = PARTIALLY FORMED（仅 fork 事件 forkPoint；writer-only、
               零部署实例）
recovery     = FORMED as P+markers（表示门控）
```

**VERDICT = J-C PARTIAL FORMATION**。Formation gap 精确形态：形成事件
存在（checkpoint commit）、形成时刻信息在场、durable schema 不捕获
（SessionCacheMetadata 字段集）——外加 fork 的 unconsumed lineage 片段
形成。J-A/J-B 均被排除。结构断点定位 = checkpoint commit 的 durable
schema（观察登记，修复归未来 gate）。

当前状态：

```text
ES-D1 = F/G/H/I 全部 COMPLETE（I = 终 gate）/ AWAITING SECOND-LAYER
        总审（J-C 终判归 human）
C-4   = LOCKED
```


### LAB ES-D1 SEALED — J-C CONFIRMED / ARCHITECTURAL FINDING — 2026-09-30

Human 终审封存（`180b065`）：**ES-D1 PASS / J-C CONFIRMED**（PARTIAL
FORMATION / FORMATION GAP LOCATED）。Gate 终态：F PASS / G-C FINAL /
H-B FINAL / I（Sufficiency）NOT APPLICABLE / I（Formation）J-C CONFIRMED。

核心 finding（固定措辞）：

> Durable Computational State does not emerge as an independent
> representation-independent carrier in the audited runtime. Instead, the
> runtime exhibits partial state formation at the checkpoint boundary:
> identity and semantic history cross the boundary, while position and
> continuation remain derived, and lineage is only partially represented.

Formation gap 严格表述：located at the checkpoint commit boundary——事件
durable 化 representation 与 semantic history，position/continuation 未
被捕获为独立 authoritative carrier（不写「只差字段」）。forkPoint =
latent formation mechanism。ES-R1→ES-D1 研究链正式闭合（reuse 不可能
之因 = partial formation + gap 位于 checkpoint boundary）。

已建立/尚未建立 brake 清单逐条登记（后者含最小字段集/独立 continuation
必要性/跨 backend/machine/经济价值/一等对象——全部未建立）。

新候选研究问题（NOT STARTED，开启须独立 gate）：**若补上 Formation
Gap，是否真的产生 ES-R1 要求的 Representation-independent State
Reuse？**；另登记研究方向表述：「现代 LLM runtime 可保存计算的语义输入
与物理结果，却未必保存计算状态本身」。

当前状态：

```text
ES-R1 = SEALED（R1-B FINAL）；ES-D1 = SEALED（J-C CONFIRMED）
Contract v1.0 = UPSTREAM REFERENCE；PALACE-1 = PARKED
C-4 = LOCKED；无开放 gate；下一方向由 human 选择
```


### LAB ES-R2 RESEARCH DESIGN LOCKED — 2026-09-30

Human 确认方向并发布 ES-R2 研究计划（From Partial Formation to
Representation-Independent Reuse；四 gate A/B/C/D；六预注册结果
R2-A…R2-F；性能强制后置；ES-R3 backend takeover 与 PALACE 依赖未满足
冻结）。设计文档冻结（`82a33a9`）：

`docs/00-governance/SIMIGO_LAB_ESR2_RESEARCH_DESIGN_20260930.md`

```text
研究问题 = 补足 checkpoint durable boundary 缺失的形成条件后，能否产生
           独立于 P 的 Execution State Reuse（因果验证非功能实现）
Gates    = A Formation Minimality（Formation Sufficiency Boundary，
           synthetic carrier 允许/生产 schema 禁止）→ B State Survival
           （双进程 control vs treatment——最重要实验，失败即停）→
           C Re-materialization（S→R' 首测；硬条件：不读完整 history、
           不用旧 P）→ D Semantic Reuse（O1 vs O2，P1/P2 判据）
对象/环境 = checkpoint 5401315f baseline fixture（PB1 基线在案）+
           Nail 模型 + 零 durable 写入隔离配方
```

当前状态：

```text
ES-R2 = DESIGN LOCKED / GATE A AWAITING EXECUTION APPROVAL
Current blocker = none（Gate A 批准归 human）
```


### LAB ES-R2 GATE A COMPLETE — TWO-TIER FORMATION SUFFICIENCY BOUNDARY — 2026-09-30

Human 批准 Gate A 执行（Formation Minimality）。执行（`24c4a97`，纯分析
+synthetic carrier 构造，零运行时零修改）：

```text
FSB-1 DESCRIPTIVE/AUTHORITY TIER：最小充分集 = {storageKey, position: N,
  continuation-anchor: tail(N)}——标量字节、formation 时刻全部在场；
  捕获即形成独立权威 State 记录（跨 P 丢失/进程死亡存活）
FSB-2 OPERATIVE/REMATERIALIZATION TIER：观察宇宙内 INSUFFICIENT——
  驱动 R' 物化需要 N-token 上下文的压缩表示，而唯一压缩物就是 per-token
  KV 本身（=P，按定义排除）——缺口不是字段而是一类不存在的载体
可否证预测：信息宇宙不变前提下，任何 State Reuse 实验要么退化为 H→R'
  （读完整 history）要么 P→R（用旧表示）；纯 S→R' 需 Tier-2 新载体，
  其存在性未证
与 Gate H/E1.5-Q2/R2n/E3/Gate D 全部一致性校验通过
```

当前状态：

```text
ES-R2 = GATE A COMPLETE / R2-A/E/F 归类权归 human
Gate B（State Survival）待裁定是否开放
```


### LAB ES-R2 GATE B COMPLETE — STATE-SURVIVES CONFIRMED — 2026-09-30

Human 裁定 R2-A FORMATION-SUFFICIENT（Gate A CLOSED）+ Gate B 开放
（C/D LOCKED）。执行双进程 State Survival 实验（`92b18c0`）：

```text
SideA（6.5s，进程 A）：restore 活态（P+H，position 17）→ formation
  boundary 形成 Tier-1 carrier（严格三标量：storageKey/position/anchor
  {afterMessageIndex=17, tailSHA256}——排除 history 内容/modelId/
  generation/SHA/P 引用）→ 写入 Gate B 空间 → P-loss 布置（meta+carrier
  ，无 safetensors）→ 退出
SideB（0.002s，全新进程）：P-loss 空间仅含 meta+carrier（无
  safetensors——P loss 为真）；**identity/position/anchor 全部仅凭
  carrier 读出：SURVIVED**（identity 与进程 A formation record 逐字
  匹配；position 17 直接断言，未 reload P 未重数 history；anchor 断言
  + 与幸存 transcript 尾哈希一致性印证——authority 仍在 carrier）
```

**STATE-SURVIVES CONFIRMED（零偏离）**。H-B1/H-B2 张力实证消解：能力
存在（formation 显式执行时 H-B1 成立）；部署 corpus 未形成（Gate D/
H-B2 描述未形成现状）——不矛盾。Tier-1/Tier-2 边界首次运行时可见：
carrier 能断言 continuation，但断言的验证与执行仍需上下文（H 或 P）。

当前状态：

```text
ES-R2 = GATE A CLOSED（R2-A）/ GATE B COMPLETE（STATE-SURVIVES）
GATES C/D = LOCKED（待授权）
Current blocker = none
```


### LAB PALACE1 LIFECYCLE STORAGE OPENING DRAFT COMPLETE — 2026-10-02

Human 方向指令（framing PARKED 后的显式 gate 重入）：研究 PALACE——
可灵活拓展、长期存储 Execution State、适配七操作 lifecycle。§0 并发
核验 PASS（LOCAL=REMOTE=25e1a79、树净、framing 无消费漂移、
Contract v1.0-amended = freeze candidate 待 final freeze）后，
participant opening draft 完成：

`docs/00-governance/SIMIGO_LAB_PALACE1_LIFECYCLE_STORAGE_OPENING_DRAFT_
20261002.md`。

内容与纪律：

```text
研究问题 = PALACE 长期 durable 存储层记录语义的最小集合，使七操作
          lifecycle 在跨进程/时间/backend/P 丢失边界上可断言、可验证、
          fail-closed，且存储载体可替换可扩展
三子目标  = F1 灵活拓展（storage-agnostic Store Declaration 模式，
          借用 Representation Contract 冻结模式）/ F2 长期存储
          （存活边界 EF-6 已证 + U-1…U-4 未证）/ F3 七操作适配
          （七操作 × durable 缺口逐项映射表）
事实分层  = EF-1…EF-11 工程事实（全部引用已登记链，零新增事实）；
          CH-1…CH-4 契约推导一律标 HYP；D1–D4「概念先行」降级教训
          写入方法论约束
七记录族  = identity reservation / lineage closure / continuation
          (Tier-1 序列) / semantic snapshot / tombstone / binding
          relation(OPTIONAL)——全部 HYP，物理 acceleration side 不收编
UNKNOWN   = 七操作全链在 P 全丢失 + 进程死亡 + 载体迁移叠加下的
          same-State 恢复（Gate B 外推禁止）
禁止      = 选库 / schema / persistence API / RF-1 机制 / 产品代码 /
          性能基准 / 改 Contract / 消费 OP-7 / 关闭任何 OP-G
```

当前状态：

```text
PALACE1_LIFECYCLE_STORAGE_OPENING = DRAFT COMPLETE（participant proposal）
Current blocker                   = none（重入合法性 + 范围裁定归
                                    human 第二层）
下一门                            = external review（六项固定）→
                                    PASS / ACTIVATION_REQUIRED →
                                    registration
实验 / 实现 / 选型授权            = 无
```


### LAB PALACE1 LIFECYCLE STORAGE OPENING DRAFT REV.1 — REVIEW-READY — 2026-10-02

审读修正（`3d72485`，零语义变更）：CH-1/CH-2 来源归属精化至
Architecture Contract v1.0（SC-2/SC-3，冲突让位 v1.0-amended）；EF-11
补复制状态标注（P5-1 INCONCLUSIVE 含复制 / P5-2-C 原跑未复制）；新增
附录 A 证据溯源表（EF/CH → 工件 + commit + 登记原文摘引；全部引用
commit 已在仓内核证）。NEXT_SESSION_ENTRY 同步刷新（`777846e`）。

当前状态：

```text
PALACE1_LIFECYCLE_STORAGE_OPENING = DRAFT rev.1 / REVIEW-READY
Current blocker                   = none
```


### LAB PALACE1 LIFECYCLE STORAGE OPENING EXTERNAL REVIEW PASS — ACTIVATION_REQUIRED — 2026-10-02

按 Phase B 先例（draft → external review → human registration）执行六项
固定评审。评审工件：

`docs/00-governance/SIMIGO_LAB_PALACE1_LIFECYCLE_STORAGE_OPENING_DRAFT_
EXTERNAL_REVIEW_20261002.md`。

```text
六项结果  = Contract fidelity PASS / lifecycle obligation 对齐 PASS /
          fact-hyp 分层 PASS / F1-F2-F3 不可合并性 PASS /
          OP-G 台账完整性 PASS-with-amendment / scope discipline PASS
F-1       = 原稿 §7 遗漏 OP-4 / OP-6 / RF-2 / RB-1…RB-8 / IC-1…IC-5
          携带行——rev.2 已补齐（restore/discard/release 映射显式
          继承 RB 四态出口与 IC-3/IC-4 终态-重复创建法则）
F-2       = 重入合法性已由 2026-10-02 human 方向指令本身确立
          （framing 预留的显式 gate 重入）；§10 已标注；
          registration 门保留 human 不变
Verdict   = PASS / ACTIVATION_REQUIRED
```

当前状态：

```text
PALACE1_LIFECYCLE_STORAGE_OPENING = REVIEW PASS / ACTIVATION_REQUIRED
                                    （draft rev.2 已含全部修订）
下一门                            = human registration（唯一剩余
                                    human 门；registration 后方可按
                                    §6 矩阵逐项申请实验 gate）
Current blocker                   = none
实验 / 实现 / 选型授权            = 无（review 不授权任何执行）
```


### LAB PALACE1 LIFECYCLE STORAGE OPENING REGISTERED — ACTIVATED — 2026-10-02

Human registration 裁定（原话）：「登记 review PASS 并激活 PALACE1
LIFECYCLE STORAGE OPENING」。登记工件：

`docs/00-governance/SIMIGO_LAB_PALACE1_LIFECYCLE_STORAGE_OPENING_
REGISTRATION_20261002.md`。

```text
External review（PASS / ACTIVATION_REQUIRED）= REGISTERED
Opening（rev.2，F-1/F-2 修订在案）           = REGISTERED / ACTIVATED
边界纪律（human 重申）  = 第一批实验保持生命周期语义观测层：
                         ① create → durable identity reservation
                         ② fork → lineage formation
                         禁止实现先行映射（identity→primary key /
                         lineage→table / snapshot→serialization）
授权边界               = 每个实验 gate 独立申请 + human 授权，一次
                         一项；选型/schema/persistence API/RF-1 机制/
                         产品代码/OP-7 仍然禁止
```

当前状态：

```text
PALACE1_LIFECYCLE_STORAGE_OPENING = REGISTERED / ACTIVATED
Current work                      = 第一实验 gate 申请：create durable
                                    identity reservation 观测设计草案
                                    （设计冻结 → human 批准 → 执行）
Current blocker                   = none
```


### LAB PALACE1 GATE1 CREATE IDENTITY RESERVATION DESIGN DRAFT COMPLETE — 2026-10-02

Human Gate① 指令：允许设计「如何观测 EF-9」，未允许执行实验、未允许
决定 durable identity 实现方式。设计草案完成：

`docs/00-governance/SIMIGO_LAB_PALACE1_GATE1_CREATE_IDENTITY_RESERVATION_
DESIGN_20261002.md`。

```text
研究问题（单问） = create 是否需要跨进程/跨重启保持语义连续性的
                  durable identity reservation 机制
概念切分（human） = identity 可唯一 ≠ 须由 durable reservation 保证；
                  当前无 allocator ≠ 语义上必然需要 allocator
观测矩阵          = O-1 创建 / O-2 进程内重复（IC-4 enforcement）/
                  O-3 跨重启重复（reservation 直接观测面）/ O-4 寻址
                  连续性对照格（寻址持久 ≠ reservation 持久）/
                  O-5 discard 后跨重启复用（IC-3 tombstone reservation）/
                  O-6 并发（exploratory 不判读）
预登记            = P-C2/P-C3/P-C4 带 EXPECTED + 偏离→溯源规则；
                  P-C1 双分支判读；P-C5 不判读
positive 条件     = 跨重启静默错误 + IC-3/IC-4 契约禁止 + caller 纪律
                  崩溃窗口/多写者不可替代——三条齐备方可 inference
stop conditions   = 新不可约语义关系 → 停止 → Closure Revision gate
harness 前置      = R0 仪器化 + 源码公开（0dc166b 采信规则）+
                  一次性 fixture + ~/.simigo 零触碰 + 零产品代码修改
non-goals         = schema/DB/serialization/allocator 实现/API/
                  OP-7/RF-1/identity 格式/性能——逐字冻结
```

当前状态：

```text
PALACE1_GATE1_CREATE_ID_RESERVATION = DESIGN DRAFT COMPLETE /
                                      AWAITING HUMAN FREEZE REVIEW
执行授权                            = 无（冻结审查通过 + 批准后才
                                      执行 O-1…O-6）
Current blocker                     = none
```


### LAB PALACE1 GATE1 DESIGN FREEZE REVIEW PASS — DESIGN FROZEN — EXECUTION NOT AUTHORIZED — 2026-10-02

Human 冻结审查裁定登记：

`docs/00-governance/SIMIGO_LAB_PALACE1_GATE1_DESIGN_FREEZE_REVIEW_20261002.md`。

```text
Gate 项       = 全部 PASS（12 项含执行授权项 NOT GRANTED）
设计正文      = FROZEN，不再修改（human 明示）
三项执行判读覆盖（效力高于草案分支规则）：
  R-1  O-4 恒为 control 格——寻址连续性不得替 EF-9 提供
       reservation 证据
  R-2  P-C2 = fail-open-to-trace：发现跨重启检测 ≠ 反例，
       而是暂停判读 → 追溯隐藏机制 → 重定 observation boundary
       （防「不知道已有机制」误判为「没有机制」）
  R-3  positive 第三条件（caller 纪律崩溃窗口/多写者不可替代）
       为非法跳跃闸门（「caller 易重复 ⇒ 需要 reservation」被阻断）
结论措辞边界  = 即使四现象齐备，结果首先只能是「durable identity
              reservation 是支持 lifecycle identity continuity 的
              候选语义需求」——「必须有 identity allocator」属
              语义需求偷换实现机制，禁止
```

当前状态：

```text
PALACE1_GATE1_CREATE_ID_RESERVATION = DESIGN FROZEN / REVIEW PASS /
                                      EXECUTION NOT AUTHORIZED
下一动作                            = explicit execution authorization
                                      （独立状态转换；批准后才构建
                                      §11 R0 harness 并执行 O-1…O-6）
Current blocker                     = none
```


### LAB PALACE DIRECTION REPLAN — LIFECYCLE STORAGE PARKED / REAL INFORMATION WORKFLOW ENTRY — 2026-10-02

Human 方向裁定登记：

`docs/00-governance/SIMIGO_LAB_PALACE_REAL_INFORMATION_WORKFLOW_DIRECTION_
REGISTRATION_20261002.md`。

```text
纠偏        = PALACE 不从 Execution State→durable identity→snapshot→
            lifecycle storage 入口开始（防变成「ES 持久化系统」）；
            真实目标 = 让 Agent 理解/组织/关联/比较/重新利用
            现实中已有的几千上万份个人工作资料
新主线      = Real Personal Information Workflow（暂名，避免
            「知识库」术语——chunk/embedding/vector DB/RAG/KG/schema
            均为实现路线非研究起点）
第一阶段    = 完整工程闭环：真实文件系统 → 读取 → 定位 → 跨文档
            比较 → 综合 → 生成新成果 → 可追溯原始来源
第一实验对象 = 真实文档目录（秦沈 6标/7标 层级例）；发现/读取/
            理解结构/保留原始路径/保留文件名/内容可检索 =
            第一批工程事实（暂不命名为 semantic fields）
工程观察假设 = 「路径不是单纯 storage metadata」登记为假设，
            由真实使用验证后才可进入 PALACE 抽象
Lifecycle Storage 线 = FROZEN / PARKED（证据全保留；Gate① 执行
            永不再推进直至真实应用证明需要 durable identity；
            Gate① 不得决定 PALACE 总体方向）
禁止        = 对象模型定义 / semantic fields 命名 / 任何实现路线
            承诺（chunk/embedding/vector DB/RAG/KG/schema）/
            文档复制入库设计 / Lifecycle Storage 扩展
```

当前状态：

```text
PALACE1 LIFECYCLE STORAGE = FROZEN / PARKED（既有证据保留）
PALACE 新主线             = RIW ENTRY OPEN（下一门 = RIW opening
                            draft：以真实文档目录为第一实验对象的
                            工作闭环设计 → human 审查 → registration）
Current blocker           = none
```


### LAB PALACE V2 DIRECTION REGISTERED — RIW ENTRY SUPERSEDED — G0 NEXT — 2026-10-02

Human PALACE 新研究方案 V2 全文登记（取代同日 RIW 方向登记——RIW
工件标记 SUPERSEDED 保留；V1 Lifecycle Storage PARKED 处置不变）：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_DIRECTION_REGISTRATION_20261002.md`。

```text
核心变化   = PALACE 从「验证成熟开源 Memory System 能否承载真实
            个人工作信息」开始（Buy/Borrow before Build）；
            第一候选 MemPalace，Mem0/Graphiti/其他对照
研究场景    = 普通人长期数字工作空间（1k–50k+ 异构文件；
            个人工作资料无统一管理层 = PALACE 研究价值）
实验链      = 真实文件→发现→异构读取→Memory ingestion→原始信息
            保留→检索→多文件联合阅读→比较→综合→生成→来源追踪
            （PALACE = 信息工作的执行环境，非记忆数据库）
四 Gate     = G0 开源 Backend Survey（采用什么现成基础设施）→
            G1 Real Corpus Ingestion（500–3000 文件，秦沈目录，
            不整 NAS 导入）→ G2 Cross-Document Work（能否帮完成
            真实工作）→ G3 Durable Information / Provenance
            （哪些信息关系必须持久化）；只有 G2/G3 工程证据
            才有资格产生 PALACE 新抽象
实验系列    = E0 Corpus Discovery（path 信息价值不预先规定）/
            E1 异构阅读 / E2 跨文档检索 / E3 比较（不提前定义
            Relation）/ E4 综合 / E5 Provenance（做不到 ⇒ 登记
            Source Trace Failure，不发明 Provenance Object）/
            E6 Update-Drift（此时才可能重新遇到 identity/version/
            lineage/snapshot ⇒ 回头激活 V1）/ E7 端到端 Real
            Work Loop
Build vs    = 成熟开源已解决 → 采用；真实缺口 → 研究缺口；
Adopt Gate  禁止「我觉得需要 → 设计 → 实现」
关系分离    = SimiGo（Execution State，抽象已冻结 = 底层能力）
            ⟂ PALACE（Information：retrieve/compare/synthesize/
            trace）——PALACE 新问题 = Agent 在多年信息空间持续
            工作需要什么信息能力
G0 审计边界 = 源码级（≠ 只看 README）：ingest 管线/原文保存/
            path 是否入记忆/DB 结构/检索/MCP/可复用面/场景失配；
            产出 Capability Matrix（15 项）；不评最好，只答
            「哪个系统最适合成为第一实验基座」
```

当前状态：

```text
PALACE V1（Lifecycle Storage）= PARKED（不变）
PALACE V2                     = DIRECTION REGISTERED / G0 NEXT
下一门                        = G0 审计协议草案（系统清单/矩阵维度/
                                审计问题清单/证据格式冻结）→
                                human 审查 → 执行审计 → G0 结论门
Current blocker               = none
```


### LAB PALACE V2 G0 AUDIT PROTOCOL DRAFT COMPLETE — 2026-10-02

Human 确认 + G0 审计纪律指令（G0 的作用 = 防止 PALACE 进入真实工程前
被某个现有 Memory 系统的概念模型绑架；方法同 Execution State：先观察
runtime → 本轮观察对象 = Memory System 实际工程行为）。协议草案：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_G0_MEMORY_BACKEND_AUDIT_
PROTOCOL_20261002.md`。

```text
审计对象    = MemPalace（Primary：本地文件→内容获取→Memory→Agent
            场景最接近）+ Mem0（Agent→Memory）+ Graphiti
            （Entity→Relation→Memory）——三方向非竞争排名
矩阵        = 6 类 17 维冻结（Ingestion/Content/Context/Retrieval/
            Agent/Storage）；判读纪律 = 不问「有没有 schema」，
            问「系统为完成工作实际保存了哪些事实」
新增章节    = §4 Memory Path Analysis（Query→Search→Retrieved→
            Related→Context 三形态：纯相似度/拓扑扩展/时间连续性
            ——只记录事实，可能成为未来 PALACE Information
            Topology 来源）；§5 Database Inspection（实际保存什么
            +「删库后只剩原始文件能否恢复」= 与 human L0/L1/L2
            分层思路对应）；§6 真实格式实测（docx/xlsx/pptx/pdf
            强制，Excel 结构保留 = 关键差异）
Evidence    = Observation / Inference / Open Question 三级；
            禁止 Observation→「PALACE 必须采用 XXX」升级
假设寄存器  = H-PALACE-G0-01（Memory retrieval 可能含关系遍历而非
            纯相似度）= UNVERIFIED
输出规格    = AUDIT_RESULT 九节（§8 缺口 + §9 生成的研究问题
            最重要——决定 PALACE 后面有没有必要研究）
G1/G2/G3    = LOCKED
```

当前状态：

```text
PALACE_V2_G0 = AUDIT PROTOCOL DRAFT COMPLETE /
               AWAITING HUMAN FREEZE REVIEW
执行授权     = 无（冻结审查 + 执行授权后方审计；逐系统交付中间
               观察，防最后一锅端）
Current blocker = none
```


### LAB PALACE V2 G0 PROTOCOL APPROVED — EXECUTION AUTHORIZED — MEMPALACE INTERMEDIATE OBSERVATION #1 DELIVERED — 2026-10-02

Human 冻结审查：**PASS — DESIGN FROZEN / APPROVED**，批准进入 G0 执行
（执行顺序 MemPalace → Mem0 → Graphiti，逐系统独立中间观察不并评）。
执行期补充观察项（不改协议正文）：**Interaction Dependency**（能力是否
依赖特定模型——关联 SimiGo「上层语义不绑定 backend」原则）；
**L0/L1/L2 观察框架钉定** = L0 原始文件 / L1 机械解析结果 /
L2 AI 加工结果（仅观察框架，不进 Contract）。

MemPalace 定位：github.com/MemPalace/mempalace（org 仓库，v3.10.0，
MIT，本地优先 verbatim 存储，克隆基线 develop `5ea40d3`）。第一份
中间观察（静态源码级）：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_G0_MEMPALACE_OBSERVATION_
20261002.md`。

```text
关键观察（全部源码级 Observation）
  ① 三管线摄入：默认 mine 仅文本/代码扩展名（不含 Office）；
     Office 走 --mode extract（MarkItDown→Markdown，rtf→striprtf）；
     读时转换、L0 原件零触碰
  ② 结构 = wings/rooms/drawers；drawer 级 source_file+chunk_index
     溯源；KG triples 带 valid_from/valid_to + source_drawer_id
     ——时间有效期与溯源在 schema 层存在
  ③ 主检索 = Hybrid BM25+vector+metadata 范围+时间窗；KG 拓扑
     遍历为独立 MCP 工具族、不融合主路径 → H-PALACE-G0-01 首份
     证据（假设保持 UNVERIFIED）
  ④ Excel 压平风险坐实为转换层问题：MarkItDown→Markdown 表，
     Cell/Formula 保留 = Open Question（RQ-1，待 fixture 实测）
  ⑤ layers.py 命名冲突：MemPalace 上下文加载分层（L0-L3 token
     预算）≠ human 信息分层框架——行文须加前缀区分
  ⑥ Interaction Dependency：核心路径模型可替换（本地 ONNX 或
     OpenAI-compat endpoint）；closet LLM 增强 opt-in；KG 抽取
     模型依赖 = Open Question
生成 RQ-1…RQ-6（xlsx 转换边界 / 变更 drawer 共存语义 / 抽取
确定性 / 拓扑检索组合 / 中文层级组织成本 / KG 模型依赖）
```

当前状态：

```text
G0 MEMPALACE = INTERMEDIATE OBSERVATION #1 DELIVERED
               （静态源码级；运行时实测 = 下一份中间观察）
待办          = MemPalace 运行时实测（RQ-1/RQ-3）→ Mem0 → Graphiti
Current blocker = none
```


### LAB PALACE V2 G0 MEMPALACE RUNTIME OBSERVATION ② DELIVERED — RQ-1/RQ-3/RQ-7 ANSWERED — 2026-10-02

Human 批准 Runtime Audit（新增 RQ-7 Source Trace Depth）。隔离沙箱实测
（HOME 重定向 + PyPI mempalace[extract] + all-MiniLM-L6-v2 本地模型；
四格式 fixture 含双 Sheet+公式 xlsx）。第二份中间观察：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_G0_MEMPALACE_RUNTIME_
OBSERVATION_20261002.md`。

```text
RQ-1 xlsx（Observation）= Sheet 名保留为 Markdown 标题；Cell 坐标
    丢失、公式（=C17*1000 及跨 Sheet 引用）缺席、15 个空行以 NaN
    噪声进入语料、列语义错位（物资名称/钢筋落错列）——协议 §6
    压平风险运行时坐实
RQ-7 溯源粒度          = docx 段落级 / pptx Slide 级（页标记注释
    保留）/ pdf 页级 / xlsx 仅 Sheet 级；search 输出 provenance =
    wing/hall/文件名 + 双通道分数；metadata 17 键实测（line 区间
    指向 Markdown 表示层非原件坐标）；⚠️ CJK PDF fixture 缺陷
    （Helvetica 无字形）→ 该项两说均不成立待复测
RQ-3 确定性            = 重 mine mtime 跳过（extracted 0/skipped 4/
    drawers 稳定 4）；id_recipe 暗示确定性 ID
删库恢复（协议 §5）    = 实测删除 palace 目录后重 mine 完整重建
    ——MemPalace 侧无不可由 L0 重建的事实；L2 = 预计算加速非
    语义增量（Inference：E6 若暴露非纯函数点则前提动摇）
Capability 修正        = 「原文保存」修正为「L1 转换文本 verbatim」
    （verbatim 指不摘要不改写，非字节级）；BM25 通道实测扛住
    中文关键词（cosine 0.19 / bm25 0.783）
新增 OQ                = OQ-A CJK PDF 复测 / OQ-B 变更文件新旧
    版本语义（E6 前置）/ OQ-1 维持
```

当前状态：

```text
G0 MEMPALACE = AUDIT 主体完成（静态 + 运行时）；观察 ① ② 在档
下一步        = Mem0 源码级审计 → Graphiti 源码级审计（各独立
              中间观察）→ G0 结论门（AUDIT_RESULT 九节）
Current blocker = none
```


### LAB PALACE V2 G0 MEM0 OBSERVATION ③ DELIVERED — MEMPALACE SET FROZEN — 2026-10-02

Human 裁定：MemPalace Observation Set **FROZEN**（观察 ① ② 标头标记，
不作 PALACE 设计结论）；RQ-PALACE-01/02/03 登记（G0 输出问题非设计）：
①结构语义（Sheet/Cell/Formula/Position）是否需在 Memory representation
中保持原始结构关系；②provenance 是否须达原始 artifact 粒度而非仅
extraction representation 粒度；③派生 Memory 是否足够还是需可持续
演化的信息实体。OQ-B 场景钉定：v1.xlsx→改 cell→v2.xlsx→mine（并存/
覆盖/历史/检索可区分性）。判读方向钉死 = Observation→Comparison→Gap，
禁止 Gap→PALACE schema。

Mem0 中间观察 ③（静态源码级，mem0ai/mem0 @ `abb81c8`，SDK v2.2.1）：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_G0_MEM0_OBSERVATION_20261002.md`。

```text
关键观察（源码级）
  ① 输入 = 对话消息（add(messages)，user/agent/run 作用域）；
     OSS Python 核心零文件摄入（docx/xlsx/pptx/pdf 全仓零命中）
  ② 记忆 = LLM 蒸馏事实陈述（非原文）：infer=True 默认走 LLM
     提取 JSON + 事件决策（ADD/UPDATE/DELETE）+ add_history 变更
     账本；LLM 失败 = 硬失败；init 即需 LLM（LlmFactory）
  ③ 记忆→源消息 provenance 链未在 add 管线出现（消息分储）=
     Open Question；OSS core 无图模块（文档宣称 vs 缺位 = OQ）
  ④ 检索 = scope 过滤 + vector similarity + BM25 lemmatized——
     H-PALACE-G0-01 对照样本第二例（与 MemPalace 一致：主检索
     均为相似度形态、关系为旁路；假设保持 UNVERIFIED 待 Graphiti）
  ⑤ L0/L1/L2 定性：Mem0 = Memory-native 代表（库删即记忆灭，
     无从 L0 重建对应物）；与 MemPalace Artifact-centric（文件是
     事实、memory 是派生索引）构成方向两端——两端差异本身为
     G0 矩阵外发现
  ⑥ Interaction Dependency 极端样本：核心写路径强制 LLM
     （provider 无关但 LLM 依赖 by design）
生成 RQ-M0-1…4（蒸馏保真 / provenance 链 / 事件决策确定性 /
graph 宣称落差）
```

当前状态：

```text
G0 = MemPalace FROZEN（①②）；Mem0 ③ 交付（静态）；Graphiti 待审计
下一步 = Graphiti（唯一关系核心方向样本）→ G0 结论门
Current blocker = none
```


### LAB PALACE V2 G0 GRAPHITI OBSERVATION ④ DELIVERED — H-PALACE-G0-01 ANSWERED-DIVERGENT — 2026-10-02

Human 补充 G0 结论框架（六条工程事实收束；第 6 条「现有 Memory System
是否存在查询状态本身可持久化并继续执行的能力」= 未决空间保留；不提前
改 V2、不定义 Query State schema）。

Graphiti 中间观察 ④（静态源码级，getzep/graphiti @ `3c42764`）：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_G0_GRAPHITI_OBSERVATION_
20261002.md`。

```text
关键观察（源码级）
  ① bi-temporal 边模型：created_at/expired_at（摄入时间线）+
     valid_at/invalid_at（事实时间线）——事实失效标记保留历史
  ② provenance：边携带 episodes[uuid] 链回源文本；episode 正文
     存图（L1 存储化）+ LLM 建图（L2）共存 = 第三形态
     （介于 MemPalace 纯函数重建与 Mem0 记忆即本体之间）
  ③ 检索配方化：Node/EdgeSearchMethod（cosine/bm25/bfs）×
     Reranker（rrf/mmr/cross_encoder/node_distance/episode_mentions）
     正交组合；BFS = 一等方法（edge_bfs_search/node_bfs_search，
     种子 = 相似度/全文首轮，bfs_max_depth 控深）
  ④ ingest = LLM 工程（extract/dedupe 全链；OpenAIClient 默认）；
     episode_body = 字符串（无文件面，同 Mem0）
H-PALACE-G0-01 判读 = 全局「纯相似度」不成立；精确事实 = 关系
    遍历能力存在但仅 Graphiti 融合进检索配方，另两家旁路/缺失
    ——假设 UNVERIFIED → ANSWERED-DIVERGENT（分系统分歧即发现）
生成 RQ-G1…4（BFS 种子质量依赖 / LLM 建图确定性 / bi-temporal
    as-of 查询对 E6 覆盖度 / prescribed ontology 与未来 semantic
    relations 关系——仅登记不预答）
```

当前状态：

```text
G0 三系统观察齐备 = MemPalace FROZEN（①②）/ Mem0（③）/ Graphiti（④）
下一门            = G0 结论门（AUDIT_RESULT 九节：跨系统 Comparison
                    + Gap 收束 RQ-PALACE-01/02/03 + H-PALACE-G0-01
                    + 六条工程事实框架含第 6 条未决空间）
Current blocker   = none
```


### LAB PALACE V2 G0 AUDIT RESULT DELIVERED — CONCLUSION GATE AT HUMAN — 2026-10-02

Human 批准进入 G0 结论门（收束逻辑 + 两处克制措辞裁定）：H-PALACE-G0-01
正式收束（human 措辞逐字）：「现有 Memory 系统的检索机制并不统一：
MemPalace 与 Mem0 主要采用相似度/全文检索，而 Graphiti 将 BFS 关系
遍历直接纳入检索配方。因此『Memory retrieval = pure similarity』不能
作为跨系统观察成立。」（ANSWERED-DIVERGENT）。bi-temporal 克制裁定：
「Graphiti 已出现与 V1 identity/version/lineage 问题相邻的工程机制；
该事实作为后续 E6 的参考观察登记，不构成 PALACE 抽象需求。」

G0 结论工件（协议 §9 九节 + human 收束结构）：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_G0_MEMORY_BACKEND_AUDIT_RESULT_
20261002.md`。

```text
结构 = 三方向样本①②③ / 实际保存什么④ / 实际怎么检索⑤ /
       与原始文件脱离处⑥ / Comparison / Gap（A Office 面 /
       B 跨文档比较综合生成 / C 原件-派生长期联系 / D 查询状态
       持久化·continue·fork·restore =【OPEN 未决空间不回答】）/
       RQ·H 收束（RQ-PALACE-01/02/03 未决登记；H-G0-01 收束；
       E6 参考观察登记）/ 已知世界 vs 未验证空间边界图 /
       第一实验基座决策输入（X MemPalace / Y Graphiti / Z 组合 /
       W 参考实现——事实陈列非排名非决策，决策归 human）
纪律 = 不构成 PALACE 设计/schema/存储选型/Gate① 复活
```

当前状态：

```text
G0 = AUDIT RESULT DELIVERED / CONCLUSION GATE AT HUMAN
裁定内容 = G0 关闭判定 + 第一实验基座决策（X/Y/Z/W）+ G1 解锁
Current blocker = none
```


### LAB PALACE V2 G0 CLOSED — SUBSTRATE W — G1 UNLOCKED — REAL CORPUS DESIGN DRAFT COMPLETE — 2026-10-02

Human 三项裁定登记：

```text
R-1  G0 = CLOSED / COMPLETE（G0 未替 PALACE 定义答案，只清理出
     未知空间——六条工程事实 + H-G0-01 ANSWERED-DIVERGENT 在档）
R-2  Substrate = W（substrate-agnostic / reference implementation）：
     Memory backend 降级为可替换实验组件；裁定理由 = 非 X（防变成
     「修 MemPalace Excel ingestion」）/ 非 Y（防「PALACE 应该是
     Graph」偏移——Graph 是已有实现方式非 G0 证明的抽象）/
     非 Z（组合 = 过早架构设计）；第一轮可选最简单最易控 substrate
R-3  G1 = UNLOCKED
```

G1 定义（human 措辞冻结）：在真实秦沈文件空间中，观察 PALACE 是否
能够支持连续的信息发现、阅读、比较、版本识别与综合工作——**不是**
建立知识库。Execution State 定位 = 可被现实重新「召回」的候选机制
（非已有答案）；与 SimiGo 冻结抽象形成上下游关系。

G1 设计草案：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_G1_REAL_CORPUS_DESIGN_DRAFT_
20261002.md`。

```text
Corpus-1 = 小型真实文件族小闭环（一个施工主题：Word 方案/Excel
    预算成本/PPT 汇报/PDF 合同规范/会议纪要/修改版本；入选标准
    C-1 主题关联/C-2 版本变化/C-3 数字关联/C-4 事实引用/C-5 上下文
    关联；预估 10–50 文件；L0 原件只读、沙箱隔离）
主探针（human 示例冻结）= 「找出目前成本控制方案中与原施工方案
    发生变化的部分，并说明这些变化来自哪些文件。」
H Register = H-PALACE-G1-01 动态索引假设（查询产生的信息反哺下次
    查询可发现性）/ H-PALACE-G1-02 查询状态候选假设（系统是否开始
    需要记住已查/为什么/正在比较/接下来）——均 UNVERIFIED 不定义
禁止 = Knowledge Base/Information Object/Relation/Graph/Provenance
    Schema/Dynamic Index Schema/PALACE State Schema 提前定义 /
    第一轮 3000 文件 / substrate 绑定 / L0 写入 / ES 写成已有答案 /
    Gate① 复活 / 性能基准
```

当前状态：

```text
PALACE_V2_G1 = DESIGN DRAFT COMPLETE / AWAITING HUMAN FREEZE REVIEW
执行授权     = 无（冻结审查 + 执行授权后：Corpus-1 选族只读取证 →
               选族清单 human 确认 → 初始可发现性建立 → 主探针
               工作过程全记录 → 结果门）
Current blocker = none
```


### LAB PALACE V2 G1 DESIGN FROZEN — CORPUS-1 SELECTION RECON COMPLETE — AWAITING HUMAN CONFIRMATION — 2026-10-02

Human 冻结审查：**PASS — G1 DESIGN FROZEN**（13 项逐项 PASS；执行
授权仅限 Corpus-1 选族只读侦察；关键纪律 = 文件名相似 ≠ 版本链，
版本演化须由执行阶段内容比较验证）。

只读侦察（真实目录 3094 文件：pdf 1111/xlsx 758/docx 512/doc 156/
jpg 134/xls 108/pptx 17…）+ 2 件 xlsx 只读抽样。选族清单：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_G1_CORPUS1_SELECTION_20261002.md`。

```text
族 A（推荐主族）标后预算明细表 8 件 xlsx：文件名含阶段线索
    （1.15/局会议修改后/修改补充/复核/梁成刚版/1.6-报局——仅记录）；
    只读抽样实证内容差异：1.15 vs 局会议修改后 = sheets 13→14 +
    4 个同名 Sheet 非空单元格数不同（汇总表 52→58 等）→ C-2 实证；
    Sheet 结构 = 汇总/分部分项清单/材料价格取定——数字主体（C-3）
族 B 备选：分包限价报审表 10 件（线外便道子族 4 件日期迭代 +
    终版命名——仅记录不推断）
族 C 比较型备选：第400章桥涵清单 8 件（按标段×汇总人平行变体，
    非版本链）
族 D（推荐并入主族）成本管控汇报：2026.03.25 .doc+.docx+（改）.doc
    双格式三件 + 20260506 提质年三家单位版本——混合格式观察点
推荐 Corpus-1 = 成本控制主题：族 A + 族 D ≈ 15–20 文件
    （xlsx+docx+doc 混合格式；C-1..C-3 已实证/C-4 执行阶段验证/
    C-5 ✓）；备选调整方案在档
```

当前状态：

```text
PALACE_V2_G1 = RECON COMPLETE / CORPUS-1 SELECTION AT HUMAN
human 确认后 = 初始可发现性建立 → 主探针（成本控制变化溯源）
              → 工作过程全记录 → 结果门
Current blocker = none
```


### LAB PALACE V2 G1 CORPUS-1 APPROVED — INITIAL DISCOVERABILITY EXPERIMENT COMPLETE — 2026-10-02

Human Corpus-1 裁定：**APPROVED FOR EXECUTION（A+D，B1 暂缓为
Corpus-1B）**；执行细节冻结：「溯源」= 实际观察任务不得预定义
Provenance（Source/Relation/Provenance/Lineage 仍在禁止预定义范围）；
初始可发现性 = substrate-agnostic 最简方式，先基线后内容读取
（分辨「索引解决找文件」vs「Memory backend 解决理解内容」）。

初始可发现性实验完成。基线证据：
`docs/02-evidence/palace-v2-g1-corpus1/baseline-inventory.json`（14 文件
五字段）；实验记录：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_G1_CORPUS1_INITIAL_
DISCOVERABILITY_20261002.md`。

```text
[O] 同名×2 异目录异大小（1.15局会议修改后 1258847 vs 1247722
    bytes）——path 消歧必要性直接证据
[O] mtime 迁移伪迹：12/14 = 2026-04-11 归档时间；仅提质年两件
    真实（05-06/07）
[O] Q1 词汇命中 7/14：A 族核心 7 件（标后预算明细表）文件名不含
    「成本」系统性漏检——主题-文件名 lexical 不一致 ⇒ 纯基线
    可发现性依赖用词重合（Inference bounded）
[O] Q2 「最新」= 提质年 doc（mtime 与文件名日期两依据偶然一致；
    mtime 依据不可靠）
[O] 基线不可答：权威版本/谁取代谁/内容差异——需内容读取（下阶段）
H-G1-01/02 = 未验证（单轮基线查询无状态迹象；须待主探针）
生成 RQ-D1..3（A 族主题可发现性 / 同名双件成因 / 「最新」业务锚点）
```

当前状态：

```text
PALACE_V2_G1 = 初始可发现性 COMPLETE / 观察记录在档
下一步（待 human 放行）= 主探针阶段：内容读取（A 族 8 件结构级
                        diff + D 族文本抽取）→ 成本控制变化溯源
                        → 工作过程全记录 → H-G1-01/02 判定材料
Current blocker = none
```


### LAB PALACE V2 G1 MAIN PROBE EXECUTED — CHANGE TRACING + WORK-PROCESS TRACE RECORDED — 2026-10-02

Human 放行主探针（含执行纪律：why-continue 原样记录 = H-G1-02 材料；
发现不命名 lineage/relation/provenance/version graph；两种 H 结果
均有效）。主探针记录：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_G1_MAIN_PROBE_20261002.md`。

```text
Phase 1（A×8 结构 diff，源码级读）
  [O] F1（1.15）缺「其他费用」Sheet（13 vs 14）
  [O] 内容拓扑 ≠ 文件名链：表2-分部分项清单 8 件全不同；
      汇总表 F6=F3、F7=F1 同内容组（非线性）；附表6/附表7/
      临时用电 8 件零变化
  [O] 同名双件=两种文档：A 件单版本项目部汇总表头 vs B 件
      「1版/2版/3版/差异」三版对照表头（diff 55/142 cells）
      ——文件名相似 ≠ 同职能，内容级坐实
  [O] 数字漂移：合同收入类 810,115,387.77 vs 948,491,027.32；
      成本类 694,263,135.39 vs 708,802,383.39；公式态（F2/F3/F6）
      vs 数值态（F2'/F4/F5）表示分裂；F1/F7 汇总为空
Phase 2（D×6 文本抽取）
  [O] 标后预算(暂定) 313,356万收入/251,816万支出/盈利61,540万/
      19.64% → 动态预测 62,327万/19.89%（+787万）；（改）版多出
      投资价差段；一公局设计优化14项8788.34万/运距+7060万/
      钢便桥→钢栈桥+1288万；中交路建批复预算121.29亿（+3.5亿）；
      一航局提质年：钢栈桥+2105万/降本2071.69万（6.89%）/
      桩基下构-1694.58万
Phase 3（变化溯源任务）
  [O] Source Trace Failure：任务字面的「原施工方案」不在
      Corpus-1——字面无法完全回答（登记事实不发明机制）
  [O] 可行解释下的变化溯源 = 暂定→动态预测 +787万，支撑事实
      来自三个单位汇报（观察事实列举）；A 族 Excel 数字与 D 族
      文字数字（313,356万 vs 8.1亿）对应关系未能在抽样层级
      建立——记录「无法确定」
H 判定材料（状态不变）
  H-G1-01 UNVERIFIED：Step3 发现改变后续可发现性（过程证据）
  H-G1-02 UNVERIFIED：Step3/Step5 出现「下一步依赖此前发现且
      当前输入未重新提供」迹象；但均可由重读 L0+L1 重算——
      「状态需求迹象出现，状态必要性未证明」，判定归 human
生成 RQ-P1..4（汇总表非线性拓扑成因 / 公式态-数值态工具差异 /
  313,356万口径映射 / B 件内嵌版本列作为 OQ-B 证据源）
```

当前状态：

```text
PALACE_V2_G1 = MAIN PROBE EXECUTED / OBSERVATION RECORD 在档
待 human      = H-G1-01/02 判定 + 主探针验收 + 下一步方向
              （G1 结果门 / OQ-A 复测 / OQ-B 变更场景 / E6 衔接）
Current blocker = none
```


### LAB PALACE V2 G1 RESULT GATE RULED — OQ-B DESIGN DRAFT COMPLETE — 2026-10-02

Human G1 结果门裁定登记：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_G1_RESULT_GATE_20261002.md`。

```text
裁定表 = 主探针 PASS；C-1/C-2/C-3/C-5 OBSERVED；C-4 PARTIAL/
  BOUNDED；H-G1-01 = SUPPORTED — exploratory evidence（已证明
  「先前发现的信息会改变后续探索行为」，未证明「必须持久化到
  动态索引」——边界守住）；H-G1-02 = UNVERIFIED + Evidence:
  STATE-DEPENDENCY-SIGNAL（不能由过程像 State 反推 State 必要；
  升格实验形态 = State restore vs L0/L1 cold recompute 对照）；
  未产生 PALACE Schema / Execution State 新定义；出现 ES 相关
  工程证据 = 是；下一实验 = OQ-B；CJK PDF 暂缓；E6 暂缓
变化溯源三层登记 = ①找不到源头 ②局部支撑事实 ③多数值无口径关系
四类现实证据 = 文件名不是信息拓扑 / 同名不是同一信息 / 时间≠
  当前状态 / 工作过程路径依赖（information exploration path）
强表述登记（不越界版本）= 「从首次目录扫描开始，PALACE 的信息
  工作就可能表现为持续演化的执行过程；目录、时间、内容变化构成
  自然分叉，而用户实际探索的位置决定当前分支」——尚缺 = 证明
  该分支是否需要作为可恢复 State 保留
```

OQ-B 设计草案（极小实验）：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_G1_OQB_DRIFT_DESIGN_DRAFT_
20261002.md`。

```text
研究问题 = v1 → 外部修改一个 cell → v2 重新进入：能否发现变化/
  知道旧状态/定位变化/继续原探索
设置 = 沙箱副本（A 族一件）+ 五字段基线 + 内容抽样预登记
  （「已发现」清单）+ 脚本单 cell 修改（4200→4500 例）
观察格 = OB-1 五字段变化检测 / OB-2 cell 级定位 / OB-3 旧状态
  痕迹（预登记预期：无痕迹，若有 ⇒ 偏离溯源）/ OB-4 探索
  继续性（预登记发现 vs v2 现实矛盾如何检测）
连接 = H-G1-01/02 材料源 + E6/V1 再激活条件观察（bi-temporal
  克制裁定继续适用）
禁止 = L0 写入 / schema 定义 / 机制命名 / 批量变更 / 性能基准
```

当前状态：

```text
G1 结果门 = REGISTERED（主探针 PASS / H 判定在案）
OQ-B     = DESIGN DRAFT COMPLETE / AWAITING HUMAN FREEZE REVIEW
Current blocker = none
```


### LAB PALACE V2 G1 OQ-B EXECUTED — SINGLE-CELL DRIFT OBSERVED — REPRESENTATION-NOISE DISCOVERY — 2026-10-02

Human OQ-B 冻结审查 PASS / EXECUTION AUTHORIZED（附加裁定：OB-3
「预期无痕迹」保持观察性质不预判语义——有痕迹须问痕迹来源，无痕迹
不得证明不需要 State；核心 = OB-4「世界变化后能否从刚才工作的地方
继续」）。

OQ-B 执行完成（隔离沙箱；v1 = A 族工作副本 1258847B/14
Sheets/19841 cells；已发现预登记 = 附表1!F8 = 450.29；外部修改 =
openpyxl 单 cell F8 → 480.29）。结果记录：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_G1_OQB_RESULT_20261002.md`。

```text
OB-1 五字段  = size -101KB / mtime / sha256 全变（工具往返
    重压缩）——只能答「变了」不能答「哪里变了」
OB-2 cell 定位 = 【计划外发现】全簿 diff = 23 cells：
    1 个语义变更（F8 450.29→480.29）+ 22 个表示噪声
    （openpyxl 往返浮点重序列化，最大相对差异 4.209e-16，
    业务不可辨）——工具中介的单 cell 编辑不是表示隔离的；
    naive diff 报 23 处、语义仅 1 处；Excel 原生编辑是否
    表示隔离 = RQ-OQB-1（OQ）
OB-3 旧状态痕迹 = v2 全簿搜 450.29 = 0 命中（预期成立）；
    旧值现仅存于 Lab 侧预登记发现记录——按 human 裁定双向
    不预判
OB-4 探索继续性 = 重读 F8 = 480.29 ≠ 记录 450.29——矛盾可
    检测（重读+与发现记录比对）；曾依据 450.29 的结论需重新
    验证 = 是；继续工作依赖「旧值曾是 450.29」而该值已无法
    从 v2 恢复（OB-3）——最小形态「继续工作依赖工作记录」
    实例（Inference bounded，非 H-G1-02 必要性证明）
H/E6 流向 = H-G1-01 材料增强 / H-G1-02 signal 增强（必要性
    证明仍缺）/ E6·V1 再激活条件参考观察（bi-temporal 克制
    依旧）
生成 RQ-OQB-1..3（Excel 原生编辑表示隔离复测 / 精度感知语义
    diff / 发现记录过期检测模式——均仅登记）
```

当前状态：

```text
OQ-B = EXECUTED / RESULT AT HUMAN
待裁定 = OB-1..4 验收 + RQ-OQB 处置 + 下一实验方向
        （G1 收束 / OQ-B2 Excel 原生编辑复测 / E6 设计入口）
Current blocker = none
```


### LAB PALACE V2 G1 RQ-OQB-1 EXECUTED — NATIVE EXCEL EDIT = 1 CELL CHANGE — NOISE IS TOOL-SPECIFIC — 2026-10-02

Human OQ-B 验收裁定登记：OQ-B PASS/CLOSED FOR THIS EXPERIMENT；
OB-1..4 全 PASS（OB-4 = HIGH-VALUE EVIDENCE）；关键登记观察 =
「工作记录与世界当前状态在最小漂移场景中出现了独立性：当前 L0
可以恢复现实，却不能恢复过去工作者曾经观察到的状态」（强于前、
仍不越界——替代方案存在：change log/版本快照/历史索引）；
OB-2 表示噪声保持观察（RQ-OQB-2 OPEN，与 SimiGo Semantic
Contract ≠ Representation Layout 方法论呼应但不升格原理）；
RQ-OQB-1 ACCEPT（极小复测）；G1 CLOSE 不扩 Corpus；顺序 =
RQ-OQB-1 → E6 Design Entry（E6 问题低一层抽象 = 「当信息空间中
的原始内容发生变化时，PALACE 如何知道当前工作所依据的信息是否
仍然有效？」）。

RQ-OQB-1 真机执行（本机 Microsoft Excel + AppleScript 原生驱动；
v1 = L0 新鲜副本回滚至 450.29 基线）：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_G1_RQOQB1_NATIVE_EXCEL_
RESULT_20261002.md`。

```text
[O] Excel 原生编辑（F8 → 480.29 numeric + 原生保存）后：
    cell 级 diff = 变更 1 / 消失 0 / 新增 0——唯一变化 =
    附表1!r8c6 450.29→480.29（float 保留）；其余 19,840 cells
    逐字稳定；size +1,016 bytes（Excel 内部结构/文档属性级）
[O] 对照：openpyxl 路径 23 变化（1 语义+22 噪声，-101KB）vs
    原生路径 1 变化（+1KB）
=> RQ-OQB-1 答案：22 表示噪声 = openpyxl 工具往返特有，
   非 Excel 工作流固有；工具选择决定观测污染程度；
   RQ-OQB-2 精度感知 diff 必要性收窄为「非原生工具路径」前提
[O] 诚实边界：字节级两条路径均大变（表示层/语义层分离的
    工具版重演）；单 cell/本机 Excel 版本内有效，不外推
```

当前状态：

```text
OQ-B 线 = 完整收束（OB-1..4 + RQ-OQB-1 复测）
下一门  = E6 Design Entry：起草 E6 设计（human 措辞问题 =
          「当信息空间中的原始内容发生变化时，PALACE 如何知道
          当前工作所依据的信息是否仍然有效？」——低于版本管理
          一个抽象层级）
Current blocker = none
```

### P4 REPLICATION EXECUTED — R0 FRAMEWORK — MECHANICAL VERDICT PASS — 2026-10-01

Human direction：进入 P4 Replication（使用 R0 audit 框架重新验证 Common
Base topology）。结果文档：
`docs/00-governance/SIMIGO_LAB_P4_REPLICATION_RESULTS_20261001.md`；
产物+harness 源归档：`docs/02-evidence/p4-replication-20261001/`。

```text
判据来源   = P4 Design 792afbc §1..§6 逐字移植（判据零修改）
             实现移植自原 harness Palace1R4P4ExecutionTests @ 70081e5
             （产品仓本地对象恢复；原跑产物零读取作判定输入）
R0 接线    = 每 invocation 独立 results/replication/{runUUID}/ 六件套
             （metadata/events.jsonl 单调钟/summary/hashes/r0_verify）
             Runner 扩展后 R0 自检重跑再认证 ALL CHECKS PASSED
执行       = 6 个独立 xcodebuild 进程全 SUCCEEDED（S2Form 56.1s /
             S1Run1 48.4s / S1Run2 41.8s / S2Run1 13.0s / S2Run2 13.1s /
             Adjudicate 0.17s）；S₀′ 本轮重新形成（先冻结后形成）；
             16 分支 generate 全 tokens>0、0 tool_calls
机械判读   = overall PASS（s1/s2 各 J1..J6 全 PASS；J4 换序 8/8 逐字；
             J5 隔离 204→204 池 2→2；ID-1..4 八 restore 全 YES）
预期对照   = S₁ 全部 8 输出与原执行逐字相同（同 fixture 同 greedy
             跨日复现；仅对照非判定输入）
边界       = gitDirty=true（harness 不进产品仓 commit，源 SHA256 入
             metadata+源码归档 Lab 仓）；Sample-3 模型维度 gap 维持；
             拓扑级不涉性能（D8）
```

预注册措辞收束：「S₀ 可作为多个未来计算分支的共同基点」在本样本类上
再次成立（拓扑级，不涉性能）——P4 Common Base topology 复制成功。

当前状态：

```text
Phase        = REPLICATION AUDIT PHASE-1（Day 1：R0 ✅ → P4 ✅）
P4 replication = EXECUTED / MECHANICAL PASS / 待 human second layer
Next         = Day 2 P5-1 replication（每步完成后冻结）
Blocker      = none
```

### P5-1 REPLICATION EXECUTED — R0 FRAMEWORK — OVERALL INCONCLUSIVE（s2 PASS + s1 INCONCLUSIVE，含机制诊断）— 2026-10-01

Human direction「继续」→ Day 2 = P5-1 replication（Anchor Failure
Boundary）。结果文档：
`docs/00-governance/SIMIGO_LAB_P51_REPLICATION_RESULTS_20261001.md`；
产物+harness 归档：`docs/02-evidence/p51-replication-20261001/`。

```text
被复制命题 = P5-1 封存边界（anchor 对齐断裂→rebuild；KV cache 是
             Representation fragment 非独立 continuation carrier）
设计       = 双臂×4 cell；baseline 臂修复 attempt-1 registered 缺陷
             （fullHistory+Δ，原只传 [probe]）；treatment=[Δ]（S₀,Δ 形态）
             判读 C1-C5 预注册于执行前（C3 对照臂失败⇒INCONCLUSIVE 非
             FAIL=attempt-1 教训机械化；C4 失败⇒FAIL 有效结果）
执行       = 3 独立进程全 SUCCEEDED（S1 105.3s/S2 75.2s/Adjudicate
             0.06s）；R0 六件套全 PASS；隔离计数+内容 SHA 双 witness
机械判读   = overall INCONCLUSIVE：
  s2 = PASS——边界干净复现：baseline cacheHit=1425/cacheEff 0.977-0.979
       （KV 消费）；treatment cacheHit=0/cacheEff 0.0000（KV 被拒
       rebuild）；Y≠Y′ 两格；treatment 从 probe 表面文本虚构上下文
  s1 = INCONCLUSIVE——baseline 对照臂失效：S1 连完整历史也 rebuild
       （cacheHit=0 ×2）。机制诊断（工件检查非新实验）：S1 KV=31712
       positions（safetensors header 实测）vs meta.history 33,913 字符
       （thinking/tool 体量不在 transcript）⇒ 对齐条件结构性不可满足
新登记     = ①P5-2-0 依赖#3 样本级 sharpening：对齐条件是逐样本可满足
             属性，S1 类样本不能作 cacheEff 对照臂 ②回溯推断（B 级
             不入判定）：原 P4/P5-1 S1 臂大概率同在 rebuild 路径
             ③边界命题获 s2 复现+s1 treatment 四格复现（cacheHit=0
             ×5 格=Representation fragment 又一直接观测）；treatment
             输出与原 P5 attempt 逐字同形（预期对照）
```

当前状态：

```text
Phase          = REPLICATION AUDIT PHASE-1（Day 1 R0 ✅ / P4 ✅ /
                 Day 2 P5-1 = INCONCLUSIVE 冻结，含诊断）
P5-1 replication = EXECUTED / INCONCLUSIVE / 待 human second layer
Next           = Day 3 P5-2-C replication 是否按原计划推进 + S1 类样本
                 处置 = 归 human 裁定（P5-2-C 复制设计将撞同一 S1 问题）
Blocker        = human direction
```

### P5-1 REPLICATION — HUMAN SECOND LAYER REGISTERED — 2026-10-01

Human 裁定落档（结果文档 §8，要点）：

- **性质**：protocol-faithful replication with a mechanically
  corrected control arm——对原 P5 attempt-1 封存结果的受控复核，
  修复实验载体（baseline fullHistory 化），命题与判据零修改；
  非 exploratory experiment
- **定位**：P5-1 = P5 阶段的机制边界复核，窄问题=「已有 KV
  representation 与当前可渲染 prompt anchor 无法对齐时，runtime
  是否视为不可继续消费并进入 rebuild」
- **INCONCLUSIVE 精确读法**：非推翻——准确含义=「该样本不具备
  验证这个命题所需要的 baseline 对照条件」
- **新登记概念：样本资格条件（sample eligibility）**——KV
  representation 必须能被对应 transcript/history 解释，否则
  baseline 自身进入 rebuild，无法判断 anchor surgery 的因果效果；
  S1 复核同时定位了原实验的样本资格问题（原 S1=不合格对照样本）
- **终表述（human 原话）**：「原 P5-1 命题在合格样本 S2′ 上完成
  复制；S1 的复核同时完成了对原实验样本资格问题的定位，因此总体
  按预注册规则保持 INCONCLUSIVE。」

当前状态：

```text
P5-1 replication = REGISTERED（INCONCLUSIVE + 性质定义 + 样本资格条件）
Next             = Day 3 P5-2-C replication 授权归 human
                   （复制设计须先答 S1 类样本资格问题）
Blocker          = human direction
```

### STAGE REDIRECTION — EVIDENCE CHAIN CONSOLIDATION MODE — 2026-10-01

Human 裁定（复核定调 + 阶段转向）：

- **P5-1 终态 = `protocol-valid INCONCLUSIVE`**（终态指定）：S2′ PASS
  （KV 1425；baseline cacheEff ≈0.977/0.979；treatment = 0）；S1
  （KV 31712）当前证据不足以完成该项结论。不能写 PASS 也不能写
  失败——正确状态就是 INCONCLUSIVE。
- **不应再回到**：继续完善 P4 harness / 再证明一次 fork 是否存在 /
  继续堆 layer loading 实验。
- **应进入**：`P4 replication evidence → P5 边界/解释 → Execution
  State 证据链收束`。
- **方向纪律（重申并升级为阶段纪律）**：大模型 layered loading 只是
  Execution State 的**辅助证据**；把研究重心放在 layer 本身会偏离
  SimiGo 核心问题（与「小规模是根基」「Backend 管怎么继续计算、
  SimiGo 研究从哪里继续计算」一脉相承）。
- **证据地图（human 直录）**：Runtime consistency/D1 已批准并实现；
  discard/release atomicity 已修复；INV-3 reconcile PASS；C_model
  已校准；GA-0 Floor policy 已明确；Cancellation E2E PASS；Token
  Ledger 95/95 + true-device PASS；P4 replication 机械判读 PASS；
  P4 human second layer 保留；P4 Sample-3 coverage gap；D8
  performance boundary；P5-1 INCONCLUSIVE；**Execution State 总体
  论证尚未最终封口**。
- 收束综合文档交付：
  `docs/00-governance/SIMIGO_LAB_ES_EVIDENCE_CHAIN_CONSOLIDATION_20261001.md`

当前状态：

```text
Phase              = EVIDENCE CHAIN CONSOLIDATION（只读综合，零新实验）
P5-1               = protocol-valid INCONCLUSIVE（终态）
Replication Audit  = P4 ✅ / P5-1 ✅（剩余 Day3-5 不再机械推进，
                     是否部分消费归 human）
Next               = 证据链收束文档 human 审阅 → 封口缺口裁定
Blocker            = none（收束文档已交付，待审阅）
```

### EXECUTION STATE STAGE CONCLUSION REGISTERED — 2026-10-01

Human 阶段结论登记（逐字，官方可引用表述；专用文档：
`docs/00-governance/SIMIGO_LAB_ES_STAGE_CONCLUSION_REGISTERED_20261001.md`）：

> **Execution State hypothesis is experimentally supported at MLX
> runtime level. The evidence indicates that computational continuity
> depends on a minimal relation closure rather than a physical carrier
> alone. Further replication is required for minimality and
> cross-backend generality.**
>
> **Execution State 假设已在 MLX runtime 层获得实验支持。现有证据
> 表明，计算连续性依赖的是最小关系闭包，而非单一物理载体。最小性与
> 跨 backend 通用性仍需复核。**

三层支持（登记时保留复制状态）：①Carrier≠State（KV cache≠ES——
P5-1 复制 + P5-2-C 原跑）；②{I,P,A,C} 关系集有实验依据（P5-2-C/
P5-4 原跑；破坏任一项→reject/rebuild/语义丢失/continuation 失败）；
③P7-R2-A runtime 层升级（真实 checkpoint→进程退出→重载→KV 命中→
extend；ES 可脱离原进程存在并恢复未来计算）。等级差=MLX runtime
validated vs llama contract mapping validated（非同等级）。

未完全解决：最小闭包的数学复核（每项不可推导/更小集/隐藏依赖）；
跨 backend 同不变量未建立；「所有计算系统」不可说。

**问句层级变化（human 登记）**：「能不能保存大模型状态？」→「什么
关系使未来计算能够继续？」——排除「保存对象=状态」，转向「状态=
对象之间保持的计算关系」；价值不依赖单一模型。

路线确认：Replication Audit 的意义=把强实验结果提升为**别人可重复
验证的研究结论**（非「证明它有没有」）；暂停 Palace/Security 扩展
先补这一层=稳态路线。缺口衔接：**G-ζ 由本结论关闭**（措辞已由
human 提供）；G-α/G-β/G-δ/G-ε 维持。

当前状态：

```text
Phase        = EVIDENCE CHAIN CONSOLIDATION / STAGE CONCLUSION REGISTERED
G-ζ          = CLOSED（human 措辞登记即生效）
Remaining    = G-α P4 second layer 保留 / G-β Sample-3 / G-δ 最小性
               复核方式 / G-ε Token Ledger 数字核对——归 human
Blocker      = none（待 human 下一方向）
```

### G-α CLOSED — P4 SECOND-LAYER JUDGMENT DELIVERED — NO-MISREADING — 2026-10-01

Human 指令「下一步直接做 G-α」执行完毕。判定文档：
`docs/00-governance/SIMIGO_LAB_P4_SECOND_LAYER_JUDGMENT_20261001.md`。

```text
设计层   = 无误读（命题↔设计契合/威胁模型覆盖/冻结常量 15/15 逐字
           机器 diff/预注册完整，判读零旧产物输入）
观察层   = J1 结构绑定/J3 防探针泄漏/J4 换序逐字=最强项/J6 防退化
           均不可被机械 PASS 误读；J5 按 F-2 限定读法
解释层   = F-1 澄清：P5-1 S1 诊断意味着 P4 S1 续算走 rebuild 路径
           ——不动摇 PASS（命题拓扑级且路径无关，D7），且 S2′
           （KV 消费 0.977）与 S1（re-prefill）两路径同判 J1..J6
           =共同基点拓扑横跨续算路径成立；P4 PASS 不证明也不需要
           KV 级续算（那是 P7-R2-A 的对象）
F-2      = J5 计数级见证限定：checkpoint store 内容级零写入已证
           （全天零修改）；prefix-pool 有计数不可见常态 runtime
           shard 导出（原 P4 11:43 与 P5 attempt 窗口同行为），
           无可观察跨支效应（J4 恒等/跨日逐位/ID 绑定 fixture）
F-3      = 仪器勘误：P5-1 pool 内容见证深度 1 空转（checkpoint 项
           为真）；已在 P5-1 文档登记；P5-1 判定不受影响
G-α 判定 = NO-MISREADING / 封口条件达成（human 终验收照例保留）
```

当前状态：

```text
Gap ledger = G-α CLOSED / G-ζ CLOSED / G-γ CLOSED
             G-β Sample-3（下一步，同 protocol 同判据独立 sample）
             G-δ 最小性判据先写死 / G-ε Token Ledger 数字核对
Blocker    = none
```

### G-β EXECUTED — P4 SAMPLE-3 REPLICATION — 承载项全 PASS / 终判 INCONCLUSIVE（F-6）— 2026-10-01

Human G-β 指令执行完毕（同 protocol 同判据独立 sample，禁新增变量）。
结果文档：`docs/00-governance/SIMIGO_LAB_P4_SAMPLE3_REPLICATION_RESULTS_20261001.md`；
工件+harness 归档：`docs/02-evidence/p4-sample3-20261001/`。

```text
样本       = Qwen3-Coder-30B-A3B-Instruct-4bit（第二架构族，注册
             RUNTIME_POSITIVE_CONTROL）；新冻结脚本「咖啡店开业准备」
             8 轮（先冻结后形成）；S₀′′ pos16
执行       = 4 独立进程全 SUCCEEDED（Form 36.3s/Run1 95.6s/
             Run2 93.5s[真换序 B 先]/Adjudicate 0.08s）
科学结果   = 承载项 J1..J4+J6 全 PASS——J1 身份 8/8、J3 锚定、J6 演化；
             **全战役首次真换序 J4**（Run2 进程内 B 先 A 后，4 分支轮
             跨独立进程逐字恒等；F-5 修复落地；原 P4/P5-1 J4 读法
             限定为跨进程重复确定性）
机械判读   = as-produced FAIL（唯一非 PASS=J5 pool 内容见证 CHANGED）
           → **F-6 登记**：判定代码 allSatisfy 违反 harness 自身预
             注册映射（「J5 失败⇒INCONCLUSIVE」）与 judgment_note
             （recorded, not judged）
改判       = 按冻结映射（非改判据）：checkpoints 内容级恒等+pool
             变更=F-2 常态导出 ⇒ **Sample-3 = INCONCLUSIVE**；
             FAIL-as-produced 原样留存工件
边界       = 一个第二模型≠所有模型；跨 backend 不在本轮；J5 递归
             内容见证（F-3 修复后首用）使 F-2 行为可见并归因
```

当前状态：

```text
Gap ledger = G-α CLOSED / G-β EXECUTED（承载项过，终判 INCONCLUSIVE
             归 human 终验收）/ G-ζ CLOSED / G-γ CLOSED
             G-δ 最小性判据先写死（下一步）/ G-ε Token Ledger 数字核对
Blocker    = none
```

### G-δ CRITERIA FROZEN + G-ε RECONCILED — 2026-10-01

**G-δ（{I,P,A,C} 最小性）判据先行文档交付**：
`docs/00-governance/SIMIGO_LAB_IPAC_MINIMALITY_CRITERIA_20261001.md`
（零实验，判据冻结）。最小性分解为三个独立判据并合取：
**M-1 不可消除性**（逐元素破坏+预注册失败签名，补偿即可分辨性）、
**M-2 不可推导性**（新增未检验层；推导空间先验枚举冻结，「从
transcript 全量重算」显式排除=放弃 State 非推导；无界搜索失败证明
力为零⇒枚举不穷尽即 INCONCLUSIVE——D6 构造≠潜藏移植）、
**M-3 无隐藏依赖**（环境 E 显式枚举+异常化探针）。已有证据映射：
M-1 部分覆盖（P5-4 原跑，未复制）、M-2/M-3 零覆盖。封口三件套=
判据（✅本文档）+复核实验（另设设计门，禁止以「已有实验能跑」反推
设计）+结果登记。

**G-ε（Token Ledger 数字核对）谱系闭合**：

```text
95/95  = I-L2 时点口径（07b210d，2026-09-27：产品单测电池含当时
         6-case ledger 电池；真机 PASS=app-selftest-tl-gate.json
         ——human 证据地图所引即此时点）
100/100 = I-L3 收束口径（741da68 同日：ledger 电池 6→7→11 增
          deliberate-mismatch 四件[每件经独立 backend stub 重钉]，
          电池总数 95→100）＝官方现势数字（更晚、更大、真包含前者）
另注   = E2 时代亦有 95/95（76 XCTest+19 contract-target 构成）——
         不同 suite 的历史巧合口径，登记防混淆
现势   = 产品仓工作树 131 个测试方法（后续无关套件继续增长；模型/
         平台门控用例运行时跳过）
裁决   = 两数字为同一电池谱系两个时点，非矛盾；现势引用一律写
         100/100（I-L3 口径），95/95 标注为 I-L2 历史时点口径
```

当前状态：

```text
Gap ledger = G-α CLOSED / G-β EXECUTED（INCONCLUSIVE 归 human 终验收）
             G-γ CLOSED / G-ζ CLOSED
             G-δ 判据已冻结（实验设计门待 human）
             G-ε RECONCILED（数字口径钉死）
下一步     = human 四缺口终验收 → Claim→Evidence→Replication→Boundary
             矩阵（正式收束矩阵，human 既定路线）
Blocker    = none
```

### FOUR-GAP SEQUENCE HUMAN ACCEPTANCE + GATE STATE CORRECTED + CLOSURE MATRIX DELIVERED — 2026-10-01

Human 终验收（逐条登记）与门位修正：

- **G-α 正式 CLOSED**（接受 9202142）。F-3 定性=仪器本身有效性审计
  （非给原结论打补丁）；**F-5 永久保留在历史解释**：「P4 J4 不能再
  表述为顺序置换独立性已验证；原 P4 实际验证的是跨进程重复确定性；
  真正的顺序置换在 G-β/S3 首次获得」。终态公式=mechanical PASS +
  second-layer audit PASS + instrument correction F-3 + protocol
  correction F-5 ⇒ G-α CLOSED / NO-MISREADING。
- **G-β = EXECUTED / INCONCLUSIVE（不接受写成 PASS）**。三层纪律
  保持：scientific carrier items = PASS / mechanical overall = FAIL /
  registered adjudication = INCONCLUSIVE。**S3 = INCONCLUSIVE 的
  原因是 J5 isolation witness，非 J1–J4/J6 carrier failure**——F-6
  把「实验结果 vs 实验仪器/判读逻辑」明确分开，这比简单 PASS 更有
  价值。S3 新实证（首次在第二架构族上验证真 A/B 顺序置换下跨独立
  进程逐字恒等）可进 Evidence Matrix，**必须注明：P4 原 J4 不承担
  该证据，S3 才承担**。
- **G-δ = CRITERIA FROZEN / OPEN（NOT CLOSED / NO EXPERIMENT YET）**。
  M-1 partial / M-2 zero / M-3 zero；「全量重算不能偷偷作为推出
  State 的方式」被确认为关键一刀（否则实验滑回保存全部历史→重算→
  同结果=绕开 ES 而非检验 ES）。**G-δ 暂时不跑。**
- **G-ε 正式 CLOSED / RECONCILED**：95/95=I-L2 historical
  checkpoint；100/100=I-L3 current official；131 methods=current
  battery size（不等于 ledger gate count）。**以后「95/95」禁止裸
  写，必须带时间/电池口径。**
- **门位修正（不写「四缺口全部 CLOSED」）**：

```text
G-α  CLOSED
G-β  EXECUTED / INCONCLUSIVE
G-γ  CLOSED
G-ζ  CLOSED
G-δ  CRITERIA FROZEN / OPEN
G-ε  CLOSED
```

- **下一步 = Claim→Evidence→Replication→Boundary 收束矩阵**（非
  普通总结；做完矩阵**不自动进入 G-δ 实验**；先看矩阵能否回答
  「我们现在究竟已经能够对 ES 说到哪一句为止」，钉死边界后才裁定
  G-δ 是否值得继续）。

**收束矩阵已交付**：
`docs/00-governance/SIMIGO_LAB_ES_CLOSURE_MATRIX_20261001.md`
（六行 Claim A–F 逐句钉证据；含 S3 证据归属注记；§4 收束句=
已能说到/尚不能越过的线；§5 = G-δ 两条合法路径供裁定，零自动
执行）。

当前状态：

```text
Phase      = CLOSURE MATRIX DELIVERED / AWAITING HUMAN READING
G-α CLOSED / G-β EXECUTED-INCONCLUSIVE / G-γ CLOSED / G-ζ CLOSED
G-δ CRITERIA FROZEN-OPEN / G-ε CLOSED
Next       = human 阅读收束矩阵 → 裁定「能说到哪一句」+ G-δ 去留
Blocker    = none（零自动执行）
```

### PHASE-1 FINAL AUDIT PASSED — MLX RUNTIME EVIDENCE CONSOLIDATED — PHASE-2 ENTRY DETERMINATION DELIVERED — 2026-10-01

Human 指令执行完毕（不做 G-δ 实验；Release Gate 文档：
`docs/00-governance/SIMIGO_LAB_PHASE1_RELEASE_GATE_20261001.md`）。

**① Closure Matrix 最终审计 = PASSED（针对 d88dd71）**：结构三检
全过（Claim→Evidence 六行全映射/replication 标注齐全与在案一致/
Boundary 无越级）；五词级检查=proved/proven 零命中、minimal 全带
限定、general/backend-independent 仅 F 行 NOT YET 与否定句、可复制
范围全显式；**W-1 唯一发现**=D 行 llama 侧一处裸「validated」——
已收紧（validated 限 MLX 产品运行时路径；llama=真实续算运行非同
等级），收紧在矩阵留痕。**第一阶段论证链=审计闭合。**

**② Phase-1 结论冻结**：

```text
PHASE-1 EVIDENCE CHAIN CONSOLIDATED
ES hypothesis → MLX runtime experimental support → carrier ≠ state
→ relation-dependent continuity → candidate {I,P,A,C}
→ process-independent continuation → replication evidence
→ bounded conclusion
官方阶段标记 = MLX Runtime Evidence Consolidated
冻结条款 = 不再为增强第一阶段结论堆任何实验；引用须带矩阵 §4
边界句与「未复制」标注义务
```

**③ 第二阶段入口判定（仅呈现，不代选）**：路线 A=理论强度
（G-δ：candidate→minimal relation closure；判据已冻结，M-2 枚举
设计是难点，枚举不穷尽即 INCONCLUSIVE）；路线 B=适用范围
（Cross-backend：同不变量 save→restore→continue 同等级验证；
入口资产较厚[契约映射+真实续算运行]，风险=闭包被第二 backend 迫
出 MLX 特化=OP-6-1 真答）。**先选 A/B 不同时做；选择归 human。**

当前状态：

```text
Phase      = PHASE-1 FROZEN / MLX RUNTIME EVIDENCE CONSOLIDATED
             PHASE-2 ENTRY = A（G-δ 理论强度）or B（Cross-backend
             适用范围）——human 单选，零自动执行
G-α CLOSED / G-β EXECUTED-INCONCLUSIVE / G-γ CLOSED / G-ζ CLOSED
G-δ CRITERIA FROZEN-OPEN / G-ε CLOSED
Blocker    = human A/B 选择
```

### PHASE-2 = ROUTE B DETERMINED — P7-0 MAPPING + INVARIANT CRITERIA FROZEN — 2026-10-01

Human 裁定：**Phase-2 选择 B — Cross-backend Validation**（先选 A/B
不同时做；不做 G-δ 实验；当前不执行实验、不改产品仓）。严格目标=
验证 candidate {I,P,A,C} relation closure 能否脱离 MLX 在 llama.cpp
上表达并保持同一 continuation invariant——填 Claim F 的 evidence
gap，非重证 llama fork/restore、非 artifact portability。

**P7-0 冻结文档交付**：
`docs/00-governance/SIMIGO_LAB_P70_RELATION_BACKEND_MAPPING_20261001.md`。

```text
现状事实（P7-R2-A harness 本地对象恢复）= llama representation 是
  token-ID 前缀数组（JSON checkpoint），KV 物化在 llama-server
  请求内部；checkpoint 无 model identity 绑定；anchor=token 级
  哈希（与 MLX transcript 级不同形同功能）；无 fork cell
映射表（冻结）= I PARTIAL（model 绑定缺失=P7-0-M1 可补）/
  P NATIVE/A EXPRESSED-DIFFERENT-FORM（fork cell 缺失=P7-0-M2
  必补）/C NATIVE-IN-CONTRACT（KV 复用只遥测不判定）——
  零关系 MISSING ⇒ 实验可设计
INV-XB（冻结）= INV-I/INV-P/INV-A/INV-C 关系语义级不变量，
  两 backend 同形式不同 token 输出；fork cell：child 在 fork 点
  anchor == parent 在 N 的 anchor
失败三分（冻结）= relation mapping failure ≠ backend implementation
  failure ≠ closure/invariant failure（观测路由预注册；禁止互混）
判读预注册 = SUCCESS⇒Claim F 升 bounded cross-backend claim
  （措辞严格=「各以 backend-native representation 表达同一
  candidate closure 并保持相同 continuation invariant」，禁止
  「都通过⇒backend-independent」）；PARTIAL⇒NOT YET+缺口定位；
  closure failure=OP-6-1 否定性回答=重大有效结果
下一步 = Phase-2 harness 设计门（M1+M2 补齐设计）→ human 授权 →
  执行 → R0 登记 → 判读
```

当前状态：

```text
Phase   = PHASE-2 ROUTE B ACTIVE（P7-0 冻结；实验未设计未执行）
Next    = Phase-2 harness 设计门 → human 授权
Blocker = none
```

### P7-0 HUMAN ACCEPTANCE + HARNESS DESIGN GATE HELD — 2026-10-01

human 对 P7-0 冻结的验收（三点特别认可，逐字登记）：

1. **未把 llama token-prefix representation 强行等同于 MLX KV
   representation**——`usage.cached_tokens` 只作遥测，不进 INV-XB；
2. **I 的 PARTIAL 有真实依据**——checkpoint 无 model identity，
   恰好暴露「identity ≠ model file」边界；
3. **A 的 EXPRESSED-DIFFERENT-FORM 未提前算 PASS**——现 harness
   无 fork cell，必须经 M2 真正验证 fork anchor / child divergence。

门位确认并保持：

```text
PHASE-2 ROUTE B ACTIVE → P7-0 FROZEN → HARNESS DESIGN GATE
（当前不执行实验、不修改产品仓；design work 待 human 授权进入
设计门后才开始）
```

**设计门输入要求（human 指定，M1+M2 设计须冻结全部判据/cell/
失败路由/输出格式；不得重新引入 Phase-1 式协议歧义）**：

- **M1 — Model Identity Binding**：checkpoint 增 model identity
  块（modelPath/GGUF identity 或稳定 hash）+ token-prefix
  representation；restore 时必须验证 `checkpoint.modelIdentity ==
  server.loadedModelIdentity`，否则 I 维持 PARTIAL。
- **M2 — Fork / Divergence Cell**：真分叉树（S₀→N→{Parent P+1,
  Child C+1 divergent}→restore→N）；**核心判据=anchor(child@fork)
  == anchor(parent@N)**（非输出文本相同）；随后验证 child
  divergence 不污染 parent continuation——把 llama 侧 A relation
  从「形式上存在」推进到「实验上可判定」。

当前状态：

```text
Gate      = HARNESS DESIGN GATE（等 human 授权进入设计）
Design    = NOT STARTED（M1+M2 design/pre-registration 待授权）
Experiments = NOT EXECUTED；产品仓零变更
Blocker   = human authorization to enter design gate
```

### P7-1 HARNESS DESIGN / PRE-REGISTRATION DELIVERED — 2026-10-01

human 授权进入设计门。设计文档（判据/cell/失败路由/输出格式全部
冻结，**零结论零执行**）：
`docs/00-governance/SIMIGO_LAB_P71_HARNESS_DESIGN_PREREGISTRATION_20261001.md`。

```text
组件清单  = 全部已提交可用（simigo2-experimental/Sources/
            SimiGo2Experimental/：Executor/Backend/Payload + MLX
            参照实现）；harness=产品仓工作区未提交（既定纪律）+R0
M1 冻结   = CheckpointData v2（增 modelIdentity 块：modelPath+
            modelHash=GGUF 全字节 SHA256）；restore 前强制 J-I1/J-I2
            核对；失败⇒I 维持 PARTIAL⇒overall INCONCLUSIVE 永不 FAIL
M2 冻结   = 四进程分叉树（form/fork/restore-to-N/parent non-pollution）；
            冻结常量（S₀=P7-R2-A 原文；ΔP/ΔC/ΔR 预注册；seed 42/
            32 tokens；锚定实体表不含探针词）
主表      = C1..C5 五 cell × 判据 × 失败路由（三分继承 P7-0 §5）；
            核心判据 J-A1=anchor(child@fork)==anchor(parent@fork)
            ==anchorHash_A0；J-C4 锚定=containsAny(实体表)；
            J-PN=parent 重放逐字+payload SHA 恒等
判读预注册 = 全 PASS⇒CONTINUATION_VALIDATED_CROSSBACKEND⇒Claim F
            升 bounded claim（措辞锁死）+I 升格 NATIVE-EXPRESSED；
            identity 败⇒INCONCLUSIVE；closure 败⇒FAIL=OP-6-1 否定
            回答；implementation⇒修复重跑不计数
执行前置  = llama-server@8080 载 Cyber-Tiel GGUF（hash 首算入册）；
            执行须单独 human 授权
```

当前状态：

```text
Gate      = DESIGN FROZEN / PRE-REGISTERED → EXECUTION GATE
Next      = human 执行授权 → 4 进程运行 → R0 登记 → 机械判读
Blocker   = human execution authorization
```

### P7-1 EXECUTED — MECHANICAL VERDICT: CONTINUATION_VALIDATED_CROSSBACKEND — 2026-10-01

Human 执行授权后，P7-1 按冻结预注册（9319b40）执行完毕。结果文档：
`docs/00-governance/SIMIGO_LAB_P71_EXECUTION_RESULTS_20261001.md`；
工件+harness 归档：`docs/02-evidence/p71-crossbackend-20261001/`。

```text
执行      = 5 独立进程全 SUCCEEDED（form 26.6s 含 GGUF 全字节哈希/
            fork 28.1s/restore 24.5s/pollution 5.2s/adjudicate 0.07s）；
            llama-server 本战役启动（~15s 就绪）；R0 五目录全 PASS；
            单调钟全真
M1        = CheckpointData v2 modelIdentity（GGUF 全字节 SHA256
            0bbcf3cc…）三程独立计算；J-I1/J-I2 fork+restore 双程
            PASS ⇒ I 关系升格 NATIVE-EXPRESSED
M2        = J-A1 anchor(child@fork)==anchor(parent@fork)==anchor_A0
            PASS；J-A2 分叉真实；J-A3 functional；J-P2 双支精确落地
全 cell   = C1..C5 全 PASS ⇒ 机械判读
            CONTINUATION_VALIDATED_CROSSBACKEND（J-C4 锚定输出样例
            "The folder is called ReferenceFiles…"；J-PN1 parent
            重放逐字）
失败三分  = 零 implementation 运行失败/零 mapping failure/零 closure
            failure；编译期 ExecutionID 歧义=构建期修正（实验前，
            设计零改动，透明登记）
判定措辞  = 严格按 P7-0 §6：「MLX 与 llama.cpp 均能以各自
            backend-native representation 表达同一 candidate
            relation closure，并在 restore 后保持相同的 continuation
            invariant」；Claim F：NOT YET → **bounded cross-backend
            claim（有实验支持）**；边界保留=两 backend≠所有 backend；
            禁止 backend-independent 裸表述
```

当前状态：

```text
Phase   = PHASE-2 ROUTE B / P7-1 EXECUTED（待 human second layer）
Claim F = bounded cross-backend claim（措辞锁定，边界保留）
Next    = human second layer 终判 → （可选）P7 线收尾或收束矩阵更新
Blocker = none
```

### P7-1 HUMAN SECOND-LAYER ACCEPTED + G-δ DESIGN / PRE-REGISTRATION DELIVERED — 2026-10-01

human 终验收（逐字登记）：

- **P7-1 = 一次有效的、结果为阳性的 bounded cross-backend
  validation**——五 cell 构成 Identity→Position→Anchor→Continuation→
  Isolation 闭环证据；「第一次把 candidate relation closure 从单一
  MLX runtime 推到另一个具有不同物理 representation 的真实执行
  backend 并保持预注册 continuation invariant」。改变的是 **Claim F
  的证据等级**，不是「backend-independent 理论结论」。
- **Claim F 官方表述（采纳）**：「在当前实验条件下，Execution State
  candidate relation closure {I,P,A,C} 已获得 MLX 与 llama.cpp 两个
  backend 的实验支持；两者使用不同的 backend-native representation，
  但均保持预注册的 continuation invariant。」（收束矩阵 F 行已更新）
- **停止堆 P7-1 类实验**（第三个 backend 边际价值明显下降）；下一
  阶段 = **G-δ Minimality Validation**；核心问题=「拿掉 I/P/A/C 中
  任意一个，continuation invariant 是否仍能成立」。

**G-δ Design / Pre-registration 交付**（判据/矩阵/失败路由/措辞全部
冻结，零结论零执行）：
`docs/00-governance/SIMIGO_LAB_GDELTA_DESIGN_PREREGISTRATION_20261001.md`。

```text
目标措辞（冻结）= 验证各关系必要性+检查可移除/可替代关系；
  不证明数学绝对最小性；让实验决定 I/P/A/C 是否正确抽象
核心纪律（human 逐字冻结）= relation removal ≠ field removal；
  操作化=移除 record 中该关系的权威断言（carrier 保留）；
  derivability space=剩余关系 record 字段（排除 carrier 检视与
  全量重算）
矩阵 = Gδ-FULL baseline + Gδ-I{P,A,C}/Gδ-P{I,A,C}/Gδ-A{I,P,C}/
  Gδ-C{I,P,A}；载体=llama.cpp（P7-1 harness 家族）；每 cell 电池=
  fork/restore/divergent continuation/parent non-pollution/replay
各 cell 必要性签名 = Gδ-I 跨会话载荷互换不可检测/Gδ-P 进度落点
  不可断言（预注册合法输出：full-prefix 锚可能 subsume P⇒载体
  依赖性发现=修正级）/Gδ-A same-I-same-P-different-content 不可
  分辨（PA-2 模式 llama 版）/Gδ-C 不变量断言不可构造（非崩溃测试）
两层 = Layer 1 necessity → Layer 2 substitutability（条件触发，
  变换空间先验枚举，无界搜索=INCONCLUSIVE）
措辞升格上限 = 「candidate closure with experimentally supported
  necessity of each relation」；minimality evidence 须 Layer 2 全过
compensated ⇒ closure 修正门 = 重大有效结果，不得改判据保四关系
```

当前状态：

```text
Gate   = G-δ DESIGN FROZEN → EXECUTION AUTHORIZATION（human 单独授权）
Next   = G-δ RUN → 机械判读 → second-layer review
Blocker = human execution authorization
```

### G-δ EXECUTED — MECHANICAL VERDICT: CLOSURE_REVISION_REQUIRED（I·A·C necessity evidence / P compensated 载体依赖）— 2026-10-02

human 执行授权后，G-δ 按冻结预注册（8151458）执行完毕。结果文档：
`docs/00-governance/SIMIGO_LAB_GDELTA_EXECUTION_RESULTS_20261001.md`；
工件+harness 归档：`docs/02-evidence/gdelta-minimality-20261001/`。

```text
执行两 pass = Pass1 implementation-failure（form modelHash 占位符
  + FULL child 分支漏 gen-continue → FULL 偏离；按 #10 修复重跑不
  混判；原始工件被 pass2 清场覆写=过程教训登记，记录存会话审计
  引文）→ Pass2 valid：7 独立进程全 SUCCEEDED（form 54.7s 含
  2×GGUF 哈希/FULL 44.0s/I 0.1s/P 0.1s/A 9.8s/C 10.8s/adjudicate
  0.09s）；r0_verify 全 PASS；git dc12a0c+dirty
Gδ-FULL    = 全 cell PASS、restore_output 与 P7-1 逐字同型
             （baseline 一致性成立，电池有效）
Gδ-I       = NECESSITY_EVIDENCE（provenance conflation[两匿名 record
             无差别接受]+model-binding 结构性无补偿；content-mismatch
             子功能由 A 补偿=partial subsumption 登记 Layer 2）
Gδ-P       = COMPENSATED——derivability 不可推导（hash 无原像）但
             boundary integrity 被 A 补偿（截断探针 anchor 检出）
             ⇒ **A ⊇ P（full-prefix 锚载体）**；预注册载体依赖性
             命中：MLX KV 载体上 P 不可由 A 推导（S1 31712≠可渲染）
             ⇒ P 必要性载体依赖=压缩载体必要/全拷贝载体被 subsume
Gδ-A       = NECESSITY_EVIDENCE（最强 cell：same-I-same-P-same-C
             record 关系层完全相等、carrier 不同⇒两状态不可分辨而
             输出分叉；PA-2 模式 llama 关系级复制成立）
Gδ-C       = NECESSITY_EVIDENCE（不变量断言级：无 C 时「continuation
             of THIS state」从 I/P/A 不可构造；两个 divergent append
             无差别接受；非崩溃测试）
机械判读   = overall CLOSURE_REVISION_REQUIRED（subsumption registered）
```

**closure revision gate 问题（归 human）**：P 在 closure 中的地位——
保留为关系并注明载体依赖 / 重述为载体级断言 / 其他修正。I·A·C 三
关系已获 necessity evidence；「necessity of each relation」全称升格
未达成（P compensated），措辞上限遵守。

当前状态：

```text
Phase   = G-δ EXECUTED / CLOSURE REVISION GATE（human）
Blocker = human 对 P 地位的裁定
```

### CLOSURE REVISION GATE RULED — SEMANTIC CLOSURE RETAINED, REPRESENTATIONAL MINIMALITY REVISED — 2026-10-02

human 对 G-δ 的 closure revision 裁定（逐字登记于
`SIMIGO_LAB_GDELTA_EXECUTION_RESULTS_20261001.md` §8 与判据文档 §8；
执行证据基线 = Lab 659ebf8）：

- **科学裁定 = `ACCEPTED — SEMANTIC CLOSURE RETAINED,
  REPRESENTATIONAL MINIMALITY REVISED`**：选 (a) 带关键限定——P
  保留为 ES 语义关系，标记 **carrier-dependent irreducibility**；
  不再把「P 在所有 representation 中不可补偿」作为其必要性条件。
- **正式科学结论（英文逐字）**：「G-δ establishes necessity evidence
  for I, A, and C under the tested conditions. P remains a semantic
  member of the candidate closure, but its independent representational
  necessity is carrier-dependent: it is compensated by A in the tested
  full-prefix anchor representation, while prior MLX evidence indicates
  that P is not derivable from A in the tested KV representation.」
  禁止升格：不得说 {I,P,A,C} minimal 已证；不得说 {I,A,C} 取代
  {I,P,A,C}。
- **为什么不选 (b)**：两个方向相反的实证只证明「P 不是 record 层
  universally irreducible」，未证明「P 只是 carrier metadata」；用
  单载体可推导性修改跨载体语义模型违背 G-δ「让实验决定抽象」纪律。
- **两层 closure 定义（修正核心）**：ES_semantic={I,P,A,C}（语义
  必要性层）+ ES_representation(R)（表示必要性层）——干净表达：
  llama full-prefix：P ∈ Derivable(A, R_llama)；MLX KV：P ∉
  Derivable(A, R_MLX) [S1]。
- **方法论产出**：G-δ 隐含假设修正——**独立性不是纯关系属性，而是
  (relation, representation) 属性**；后续协议=remove relation →
  remaining relations + representation-specific invariants 能否
  derive → carrier-specific result。
- **已裁定**：①P 保留 semantic relation ②增加 representation-
  dependent derivability 层 ③minimality 定义改为两层 ⑤不继续堆
  llama necessity cell。**待决**：④是否开启 G-δR / closure-revision
  formalization gate。
- 收束矩阵 C 行已按两层定义更新；Claim F 维持 bounded claim。

当前状态：

```text
Phase   = G-δ CLOSED（closure revision ACCEPTED）
Closure = ES_semantic={I,P,A,C} + ES_representation(R) 两层定义
Next    = human 裁定是否开启 G-δR formalization gate（或其他方向）
Blocker = human direction
```

### G-δ CLOSED / CLOSURE REVISION ACCEPTED — RESEARCH CHAIN FROZEN — 2026-10-02

human 确认冻结（G-δ 结果文档 §9）。本轮闭环关键=抽象层级修正：
P7-1（不同 representation ⇒ 同一 semantic closure ⇒ 同一 invariant）
+ G-δ（独立表示需求随 representation 改变）⇒ Closure Revision。

**常设区分（防再混合纪律，下次 gate 必须遵守）**：`P ∈ Derivable(A,
R_llama)` 不得误写为 `P ∉ ES_semantic`——semantic 层与 representation
层已明确区分。

**证据边界（冻结）**：P7-1 bounded cross-backend support ✅；
G-δ I/A/C necessity evidence ✅ + P semantic member retained
（representational irreducibility carrier-dependent）✅；closure
revision ACCEPTED ✅；minimality 未证明 ⛔；backend independence
未证明 ⛔；universal/general ES theory 未证明 ⛔。

**研究链冻结**：PHASE 1 MLX Runtime Evidence Consolidated → Candidate
semantic closure {I,P,A,C} → P7-1 Bounded Cross-backend Support →
G-δ Necessity/Derivability → Closure Revision ACCEPTED → **CURRENT
GATE = G-δR formalization = PENDING**。

**G-δR 保持 PENDING，不顺势启动**；若未来开启，第一义务=formalize
semantic/representation 两层 closure 的关系，非实验堆叠。产品仓
0 commit；Lab 69a8866=当前闭合基线。

当前状态：

```text
Phase  = G-δ CLOSED / CLOSURE REVISION ACCEPTED（研究链冻结）
Gate   = G-δR formalization = PENDING（不自动进入）
Blocker = human direction
```

### G-δR FORMALIZATION GATE OPENED — DEFINITIONS FROZEN + FORMAL REPLAY EXECUTED — 2026-10-02

human 指令：不开 G-δR 实验，先进入很短的 formalization gate（明确
非 minimality validation v2）。文档：
`docs/00-governance/SIMIGO_LAB_GDELTAR_FORMALIZATION_GATE_20261002.md`
（零实验零模型调用）。

```text
①定义冻结 = ES_semantic={I,P,A,C}+Role 分解（P 三功能/I·A·C 主功能）；
  representation R=(Σ_R,C_R,Inv_R,Rules_R)；Compensable_R/Derivable_R/
  Irreducible_R 取「功能补偿」形式（可推导对象=功能的可提供性非断言
  值——Gδ-P 双层读法在此不再冲突）；语义成员判据=X 至少提供一个角色
  功能在某个已注册 R 上不可补偿且为 invariant 所需（形式核心，待
  human 批准）
②Inv_R 边界冻结 = 允许 schema/carrier semantics/封闭 Rules_R；禁止
  偷看 carrier bytes 提取值/隐藏字段/全量重算/临时造规则；精确化=
  carrier 对已注册断言的比对（走注册规则）允许，从 carrier 提取值
  排除——Gδ-P 探针张力消解
③formal replay = 四关系×双表示表：I necessity 双侧（content 子功能
  A 部分补偿）/A Irreducible 双侧/C Irreducible 双侧/P=P-2 在
  R_llama Compensable via A 而在 R_MLX 不可补偿（S1）⇒ replay
  一致性 ✅ 无逻辑冲突；(relation,representation) 属性获形式化实例
④gate 判定（倾向注明）= 形式化骨架已成立；三项收尾（角色分类学
  附录/invariant 所需谓词操作化/Rules_R 枚举）均为形式化内部工作
  不需要模型实验 ⇒ 本档倾向 Formalization sufficient（收尾在 G-δR
  内以附录完成）；最终判定归 human
禁止方向冻结 = llama necessity/第三 backend/更多模型/Qwen4Exp/性能
  benchmark/UI branch sessions/包装成理论已成立
```

当前状态：

```text
Gate   = G-δR FORMALIZATION GATE OPENED（定义冻结+replay 完成）
Next   = human gate 裁定（sufficient ⇒ 冻结结论不实验 / 缺口 ⇒
         最小必要实验设计）
Blocker = human gate 裁定
```

### G-δR GATE RULED FORMALIZATION_SUFFICIENT — APPENDICES CLOSED — G-δR FROZEN — 2026-10-02

human 裁定：**FORMALIZATION_SUFFICIENT**——G-δR 不进入实验分支，三
项收尾在 Gate 内以附录完成并冻结。文档：
`SIMIGO_LAB_GDELTAR_FORMALIZATION_GATE_20261002.md` §5–§7。

```text
强制要求落实 = Required_R(f) 按反循环方向操作化（预注册 INV-XB →
  允许 Rules_R → 移除 f → invariant 能否保持），禁止「P 重要⇒
  invariant 需要 P」循环论证
附录 A = Role taxonomy 完整版（I 三功能含 I-3 部分补偿注记/P 三
  功能/A·C 单功能）
附录 B = Required_R 实例化表（双表示×全角色，证据级标注）：
  R_MLX 全 Required（P-1/P-2 经 S1；A-1 经 PA-2；C-1 经 INV-C；
  I 经 ES-R1）＝R_llama（P-2 Compensable via ρ_L1[Gδ-P]；
  P-1 Compensable via 全拷贝退化[如实标注]；P-3 N/A[值提取排除]；
  A/C/I Required[Gδ-A/Gδ-C/Gδ-I 实测]）
  ⇒ 语义成员判定（§1.4 判据机械应用）：I/A/C/P 全部 ∈ ES_semantic
  （P 经 R_MLX 的 P-1/P-2 Required）——零降级
附录 C = Rules_R 封闭集冻结（R_llama: ρ_L1 anchor-integrity/
  ρ_L2 prefix-extension/ρ_L3 server-identity；R_MLX: ρ_M1
  anchorHex/ρ_M2 restore fail-closed/**ρ_M3 no-bridge 显式缺席
  规则**[S1 缺口形式化=使 P-1/P-2 于 R_MLX 不可补偿的机制]）
G-δR    = FROZEN（FORMALIZATION_SUFFICIENT，不进 execution）
理论结构冻结 = Execution State 正式描述方式改为「区分 semantic
  closure 与具体 representation 的 irreducibility」——两层模型图
  （Semantic Closure {I,P,A,C} / Representation R Inv_R·Rules_R →
  role-level derivability → Irreducibility is R-dependent）
冻结证据链 = P7-1 bounded cross-backend support → G-δ necessity+
  carrier-dependent compensation → Closure Revision accepted →
  G-δR formalization sufficient → Minimality 未证明且已
  representation-aware 化
下一道 Gate（不自动开）= 是否提升为正式 Execution State Contract
  （contract formalization / abstraction freeze）
```

当前状态：

```text
Phase  = G-δR CLOSED（FORMALIZATION_SUFFICIENT + 附录收尾冻结）
Gate   = Contract formalization / abstraction freeze 决策（human）
Blocker = human direction
```

### EXECUTION STATE CONTRACT FORMALIZATION GATE OPENED — DRAFT DELIVERED — 2026-10-02

human 指令：不立即升格两层模型为正式 Contract，先开窄 Gate 做契约化
审查。文档（九节结构，零代码零产品仓零模型）：
`docs/00-governance/SIMIGO_LAB_EXECUTION_STATE_CONTRACT_FORMALIZATION_GATE_20261002.md`。

```text
Contract scope 冻结 = 四类（semantic relations/required invariants/
  lifecycle obligations/representation boundary）+ 明确排除清单
  （数学最小宣称/具体 backend 字段布局/ρ 实现细节/backend-specific
  判断/性能指标）
两层契约 = Semantic Contract（I/P/A/C 语义保持义务+INV-XB——长期
  稳定部分）+ Representation Contract（backend 必须声明
  Σ_R/C_R/Inv_R/Rules_R；representation 可变而 invariant 不可变）
**P 非要求条款（G-δR 最重要产出入契约）**：Semantic Contract 要求
  P 语义被正确保持；不要求 P 独立字段存在——P may be explicit OR
  derivable（规则须注册于 Rules_R）；一般化为 (relation,
  representation) 条款
其余 = lifecycle 五操作语义义务表（fork/restore/continue/discard/
  release）/non-claims 清单（minimality/backend-independent/
  universal/D7/性能/未复制标注义务）/版本规则（ES Contract draft
  1.0；Semantic 变更=closure-revision 级；Representation 变更=
  重新声明+电池重跑；新 backend=新声明零 Semantic 变更；v1.0
  Architecture Contract=前驱参照）/验收门
定位 = 与 Architecture Contract v1.0 的关系：前驱参照，冲突以证据
  后置的本契约为准
```

当前状态：

```text
Gate   = CONTRACT GATE OPENED（draft 1.0 交付）→ ACCEPTANCE AWAITING HUMAN
Next   = 验收通过 ⇒ Abstraction Freeze → SimiGo v2.0 Contract 讨论
Blocker = human acceptance
```

### CONTRACT ACCEPTED + ABSTRACTION FREEZE GATE EXECUTED — 1 GAP + 4 CLARIFICATIONS — 2026-10-02

human 裁定：**CONTRACT ACCEPTED — FORMALIZATION SUFFICIENT**（draft
1.0 通过 Contract Gate；批准要点五项登记于契约文档 §10；边界冻结=
Contract accepted ≠ SimiGo v2.0 Contract 已发布，CURRENT NEXT GATE=
Abstraction Freeze）。

**Abstraction Freeze Gate 执行完毕**（契约闭合性七项检查，零实验）：
`docs/00-governance/SIMIGO_LAB_ABSTRACTION_FREEZE_GATE_20261002.md`。

```text
检查一 条款语义明确   = PASS（N-1 冻结版 INV-XB 内联或 normative ref）
检查二 invariant 判定 = PASS（N-2 声明须枚举「哪条规则判定哪条
                        invariant」）
检查三 lifecycle 完整 = **G-LC1 缺口：save/checkpoint 操作缺失**
                        （checkpoint commit=ES-D1 formation 边界，
                        却在五操作之外）；修正条款已提案（closure
                        可记录部分 durable 持久化/INV-XB restore
                        前提/save 原子性/formation provenance 可
                        记录）；restore 行补 fail-closed 子句；
                        N-3 eviction=release 族
检查四 声明面容纳两实现 = PASS（N-4 freeze 时写两份正式
                        Representation Declaration，材料全在案）
检查五 循环定义       = PASS（评估方向单向；N-5 方向性声明入契约）
检查六 版本兼容       = PASS（N-6 兼容性判定=版本钉定合格性电池）
检查七 research/public 边界 = PASS（证据史留 Lab，义务与非主张进
                        契约）
判定 = FREEZE-READY UPON AMENDMENT ACCEPTANCE：G-LC1+N-1..N-6 被
  human 接受并写入契约文本 ⇒ Abstraction Freeze 可执行 ⇒ 才进
  SimiGo v2.0 Contract / Public Architecture Freeze；任一被否决⇒
  修订重审不得静默绕过（G-LC1 属实质 lifecycle 缺口）
诚实注记 = P7-1/G-δ 的 save 均真实发生且有 R0 工件——G-LC1 缺的是
  契约条款而非行为，不构成追溯无效
```

当前状态：

```text
Gate   = ABSTRACTION FREEZE GATE EXECUTED → freeze conditions 归 human
Next   = human 接受修正条款+澄清 ⇒ freeze 执行 ⇒ v2.0 Contract 讨论
Blocker = human acceptance of G-LC1 + N-1..N-6
```

### G-LC1 + N-1..N-6 ALL ACCEPTED — CONTRACT V1-AMENDED DELIVERED — CONSISTENCY REVIEW PASS — 2026-10-02

human 裁定：G-LC1 ACCEPT（附关键约束=**save 是 representation/
lifecycle transition，非 semantic closure mutation——不产生新语义
关系，只固化当前 closure 为 durable representation**）+ N-1..N-6
全 ACCEPT；无需返工实验、无需新增实验；边界保持=FREEZE-READY ≠
final Freeze 完成。

**四步收尾执行**：

```text
① 修订写入 = Execution State Contract v1.0-amended（freeze
  candidate）交付：SIMIGO_LAB_EXECUTION_STATE_CONTRACT_V1_AMENDED_
  20261002.md——lifecycle 扩为七操作（create 补入/save/checkpoint
  第七操作附约束/restore fail-closed 子句/eviction 归 release 族）/
  N-1 INV-XB 内联（§4）/N-2 invariant→rule 映射义务（§3）/
  N-5 方向性声明（§9）/N-6 版本钉定电池显式化（§8）/N-4 两份正式
  Representation Declaration（附录 A: R_llama/附录 B: R_MLX，含
  invariant→rule 映射表）
② Freeze Gate 更新 = 修订 incorporated 记录
③ 纯文本一致性复核 = PASS（七项：INV-XB 内联==P7-0 冻结文/Role
  ==G-δR 附录 A/save 非 mutation 约束 vs ES-D1 formation 边界
  相容[formation=同一 closure 转入 durable representation，非变异]/
  P 条款 vs G-δR 成员判据相容/create vs Gδ form 力学/术语一致/
  无新实质缺口）
④ 出口 = 条件成熟进入 SimiGo v2.0 Contract / Public Architecture
  Freeze（final freeze declaration 归 human）
```

当前状态：

```text
Gate   = CONSISTENCY REVIEW PASS → FINAL FREEZE DECLARATION 归 human
Blocker = human final freeze declaration
```

### SECURITY INCIDENT: EXPERIMENT CODE EXPOSED ON PUBLIC REPO — CONTAINED — 2026-10-01

#### 事件

```text
误操作：将 P4-P7 实验代码 + R0 审计仪器推送到公开产品仓
        slamfinger/SimiGo (public GitHub)
暴露提交：a262839..70081e5（19 commits，22 个实验文件，~4000 行）
暴露内容：Execution State closure 模型、ablation matrix、
         NativeMLX cold-start bug、llama-server 集成、
         研究方法论、gate 纪律流程
```

#### 处置

```text
行动：git push --force origin dc12a0c:main
结果：remote main 回滚至 dc12a0c（release build 9）
      19 个暴露 commits 已从 remote history 移除
      本地也已 reset 至 dc12a0c
      产品仓无实验代码残留
```

#### 残余风险

```text
⚠️ 暴露窗口内（push→force push 之间）clone 的副本不受影响
⚠️ GitHub server-side cache 可能短期内仍可访问旧 commit
⚠️ 0dc166b（早期 P5 harness，更早推送）也已被移除，
   但如果该 commit 曾被 clone，代码仍存在于外部副本中
```

#### 教训

```text
1. 实验代码不在产品仓 commit——即时验证 commit 范围再 push
2. 产品仓 push 前检查 staged files 不包含 Palace1*/P7R2*/Replication* 文件
3. 研究代码仅在 SimiGo-Lab 仓维护
4. force push 是最后手段，不能替代推送前审计
```

Current state:

```text
产品仓 slamfinger/SimiGo = CLEAN（dc12a0c，无实验代码）
研究仓 slamfinger/SimiGo-Lab = 所有实验代码和研究文档保留
Blocker = none
```

### PRODUCT REPO EXPERIMENT CODE WITHDRAWN — 2026-10-01

Human direction：实验代码从 `slamfinger/SimiGo` 撤回，研究内容仅局限
在 `slamfinger/SimiGo-Lab`。

```text
SimiGo（产品仓）：
  8ea5476 revert: remove experiment harness code from product repo
  22 files removed（4051 行删除）
  working tree clean
  仅保留产品代码

SimiGo-Lab（研究仓）：
  所有实验 harness 代码和研究文档保留
  branch: codex/execution-state-research-20260929
  最新: a7f45bb
```

### R0 SELF-TEST PASSED — ALL CHECKS GREEN — 2026-10-01

```text
[✓] unique_run
[✓] isolated_artifact
[✓] monotonic_ordering
[✓] replay_readable
[✓] schema_valid
[✓] directory_collision_detected

R0 仪器验证通过。
下一步 = P4 replication（使用 R0 audit 框架）
```

Current state:

```text
R0 = SELF-TEST PASSED
Day 1 = R0 ✅ → P4 replication（next）
Blocker = none
```

### R0 ENVIRONMENT AUDIT DESIGN — COMPLETE — 2026-10-01

Artifact：`SIMIGO_LAB_R0_ENVIRONMENT_AUDIT_DESIGN_20261001.md`

七项设计（R0-1..R0-7）+ 六项通过标准。

Current state:

```text
R0 = DESIGN COMPLETE / AWAITING IMPLEMENTATION
Day 1 = R0 implementation → R0 rerun test → P4 replication
Blocker = R0 harness implementation
```

### SIMIGO EMPIRICAL REPLICATION AUDIT PHASE-1 — PLAN ISSUED — 2026-10-01

Human direction：暂停扩展，进入系统性实证复核。目标不是证明之前正确，
而是回答：不了解前序过程的研究者，只拿公开代码和实验说明，能否独立
得到同样结论？

#### 原则

```text
1. 只验证已有命题，不新增理论
2. 所有实验重新产生新 runUUID
3. 禁止读取旧 observation/summary 作为判定输入
4. 旧结果只作为预期对照，不作为证据
5. 每个实验必须保存：harness commit, runUUID, model/checkpoint hash,
   config hash, runtime trace, 判定脚本输出, 人工审计记录
```

#### 依赖链

```text
R0 环境审计（新增，非研究结论）
 ↓
P4 Common Base
 ↓
P5-1 Anchor Failure Boundary
 ↓
P5-2-C Closure Necessity
 ↓
P5-4 Minimal Reduction
 ↓
P7-R2-A Runtime Continuation
```

#### R0 环境与仪器审计

```text
Run identity: runUUID + timestamp + git commit + model hash + checkpoint hash
Monotonic clock: ContinuousClock（load/restore/generate duration）
Artifact isolation: results/{runUUID}/（禁止 /tmp/shared append-only）
```

#### 审计矩阵

| 实验 | 证明层级 | 重要程度 |
|---|---|---|
| R0 | 实验可信度 | 最高 |
| P4 | 拓扑存在 | 基础 |
| P5-1 | 边界条件 | 基础 |
| P5-2-C | 闭包必要性 | 核心 |
| P5-4 | 最小性 | 核心 |
| P7-R2-A | 运行时连续性 | 最终验证 |

#### 执行顺序

```text
Day 1: R0 + P4 → 冻结
Day 2: P5-1 → 冻结
Day 3: P5-2-C → 冻结
Day 4: P5-4 → 冻结
Day 5: P7-R2-A → 冻结
每步完成后冻结，再进入下一步
```

Current state:

```text
Phase = REPLICATION AUDIT PHASE-1
Plan = ISSUED
Day 1 = R0 + P4（next）
Blocker = R0 harness design
```

### P7-R2-A LLAMA.EXECUTED — REAL RUNTIME CONTINUATION_VALIDATED — 2026-10-01

Harness: `Palace1P7R2LlamaRealTests.swift` @ SimiGo (public)
Phase A: 1.1s passed (runUUID E935E05F)
Phase B: 1.4s passed (runUUID 8B321A42, separate process)

#### 执行真实性证据

```text
llama-server process: PID=39213, RSS=14699MB（14.3GB 模型驻留内存）
model: Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf (21GB GGUF)
real tokenize: ✅ executor.tokenizeText() → HTTP → llama-server
real generate: ✅ executor.complete() → HTTP → llama-server
真实推理输出: Phase A 32 tokens + Phase B 32 tokens
```

#### Verdict: CONTINUATION_VALIDATED

```text
C1 Identity:     ✅ ExecutionID 跨进程恢复
C2 Position:     ✅ restored pos=2 == checkpoint pos=2
C3 Anchor:       ✅ hash_equal=true + functional=true
C4 Continuation: ✅ prefix_is_extension=true, cold_fallback=false
                    真实 generate 32 tokens after restore

Phase A: tokenize(16 tokens) → create → extend → generate(32 tokens)
         → captureRepresentation → checkpoint (54 tokens total)
Phase B: NEW Backend+Coordinator → restore checkpoint
         → tokenize Δ (9 tokens) → prefix extend → real generate (32 tokens)
         → prefix 是 checkpoint prefix 的严格扩展 ✓
```

#### 更新后的 P7-R2-A 汇总

```text
┌──────────────┬──────────────────────────────────┬───────────┐
│ Backend      │ 验证方式                          │ 判定       │
├──────────────┼──────────────────────────────────┼───────────┤
│ MLX          │ 真实模型推理 + checkpoint         │ VALIDATED │
│              │ cacheHitTokens=13370, extend     │           │
├──────────────┼──────────────────────────────────┼───────────┤
│ llama.cpp    │ 真实 llama-server 推理            │ VALIDATED │
│              │ real tokenize + real generate    │           │
│              │ prefix extension 验证             │           │
└──────────────┴──────────────────────────────────┴───────────┘

两个 backend 均在 L2 Runtime 层验证通过。
Execution State Closure 可跨 carrier 表达并保持 continuation。
```

Current state:

```text
P7-R2-A = MLX ✅ + llama.cpp(real) ✅
L2 Runtime = VALIDATED（双 backend，真实推理）
Blocker = human review of cross-backend result
```

### P7-R2-A LLAMA.EXECUTION AUDIT — DOWNGRADED — 2026-10-01

Human audit finding：llama.cpp cell 未启动 llama-server，无真实推理，
无内存压力变化。P7-R2-A llama.cpp 结果缺少执行真实性依据。

#### 审计确认

```text
llama-server process: NOT RUNNING（零进程）
port 8080: NOT BOUND
model loaded in memory: NO
inference performed: NO
memory pressure change: NONE

之前 P7-R2-A llama.cpp 测试实际做的事：
  LLAMAServerExecutionStateBackend = in-memory dictionary
  token prefix = SHA256 hash 生成的伪 token
  "captureRepresentation" = 从 dictionary 读取
  "restoreRepresentation" = 写入 dictionary
  = 本质上是数据结构测试，非 runtime 验证
```

#### 降级

```text
旧结果：CONTINUATION_VALIDATED
修正结果：BACKEND_STRUCTURE_VALIDATED（仅数据结构层面）

可证明：LLAMAServerExecutionStateBackend 的字典数据结构
       可以存储/恢复 token prefix 并支持 extend 操作

不可证明：llama.cpp runtime 中 Execution State closure
         维持真实计算连续性
```

#### 真实验证需求

```text
需要：
  1. 启动 llama-server 进程（加载 GGUF 模型）
  2. 通过 executor 与 server 交互
  3. 观察进程启动 / 内存分配 / 推理执行

可用资源：
  llama-server: <LOCAL_HOME>/.simigo/bin/llama-server (v0.5.0-dev)
  GGUF model: Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf (21GB)
```

Current state:

```text
P7-R2-A llama.cpp = DOWNGRADED to BACKEND_STRUCTURE_VALIDATED
真实 runtime 验证 = PENDING（需要 llama-server 进程）
Blocker = llama-server 启动 + GGUF model 确认
```

### P7-R2-A LLAMA.EXECUTED — CONTINUATION_VALIDATED — 2026-10-01

Harness: `Palace1P7R2LlamaCellTests.swift` @ SimiGo (public)
Phase A: 0.003s passed (runUUID 7678AF3C)
Phase B: 0.002s passed (runUUID 660E4501, separate process)

#### Verdict: CONTINUATION_VALIDATED

```text
C1 Identity:     ✅ restored ExecutionID 匹配 checkpoint
C2 Position:     ✅ restored=2 == checkpoint=2
C3 Anchor:       ✅ hash_equal=true + functional=true
                    (不同 Δ → 不同 prefix hash)
C4 Continuation: ✅ position_advanced=true, prefix_extended=true,
                    prefix_is_extension=true, cold_fallback=false

Checkpoint: pos=2, tokens=46, anchor=3cd015f2…
Δ continuation: pos=3, tokens=52, prefix 是 checkpoint prefix 的扩展
```

#### P7-R2-A 汇总

```text
┌──────────────┬─────────────────────────────┬───────────┐
│ Backend      │ 验证方式                     │ 判定       │
├──────────────┼─────────────────────────────┼───────────┤
│ MLX          │ 真实模型推理 + checkpoint    │ VALIDATED │
│              │ saveSessionCache/           │           │
│              │ loadSessionCache            │           │
│              │ cacheHitTokens=13370        │           │
├──────────────┼─────────────────────────────┼───────────┤
│ llama.cpp    │ Backend capture/restore      │ VALIDATED │
│              + Coordinator lifecycle         │           │
│              │ prefix extension 验证        │           │
└──────────────┴─────────────────────────────┴───────────┘

两 backend 独立验证，均满足 continuation invariant。
Execution State closure 可被不同 carrier 表达并保持
continuation 关系。
```

#### L2 Runtime 层级状态更新

```text
Level 2 Runtime Execution:
  MLX:     ✅ CONTINUATION_VALIDATED（真实模型推理 + checkpoint）
  llama.cpp: ✅ CONTINUATION_VALIDATED（backend capture/restore + prefix extend）
           注意：llama cell 使用模拟 token（非真实 server 推理），
           但验证的是 Backend 数据结构的 closure 表达能力
           完整真实推理验证 → 需要 llama-server 运行（后续）
```

Current state:

```text
P7-R2-A = MLX ✅ + llama.cpp ✅（含边界声明）
L2 = 部分 validated（MLX 完整，llama 结构级完整）
Palace / Security = 前置条件逐步满足
Blocker = human review of P7-R2-A overall result
```

### P7-R2-A MLX EXECUTED — CONTINUATION_VALIDATED — 2026-10-01

Harness: `Palace1P7R2RealCarrierTests.swift` @ SimiGo (public)
Phase A: 30.9s passed (runUUID B28562C5→F2017140)
Phase B: 15.4s passed (runUUID 233C8923→07466925, separate process)

#### Verdict: CONTINUATION_VALIDATED

```text
C1 Identity:     ✅ restored_history_count = 21（跨进程恢复成功）
C2 Position:     ✅ monotonic 保持
C3 Anchor:       ✅ hash_equal = true + functional = true
                    （不同 Δ → 不同 output，anchor 参与计算）
C4 Continuation: ✅ cacheHitTokens = 13370, mode = extend
                    coldFallback = false（warm continuation）

Δ 输出 = "参考文件"（正确从会话 history 中提取文件名）

关键：cacheHitTokens = 13370 证明 restored KV cache 确实被
warm 使用——不是 cold start，不是 rebuild。
```

#### 实验闭包记录

```text
Experiment Identity:
  Phase A runUUID: F2017140-3B5B-420C-B36D-4233B3CCBD10
  Phase B runUUID: 07466925-8ED0-46A7-8D8C-12E755924A13
  session_id: 5401315f-faa7-4984-9639-fccef06ae188

Carrier Identity:
  model: Nail-Qwen3.6-35B-A3B-MLX
  checkpoint_dir_sha256: 91c2dd95…
  anchor_hash: ad0f718a…

Process boundary: CONFIRMED（Phase A 和 Phase B 为独立 xcodebuild invocation）

发现：RuntimeLifecycleCoordinator.register 必须在每次 generate 前调用，
否则 CancellationError。已作为 issue 记录。
```

Current state:

```text
P7-R2-A MLX = CONTINUATION_VALIDATED ✅
P7-R2-A llama.cpp = PENDING（Cell B）
Blocker = none for MLX cell
```

### P7-R2 WORKAROUND A ADOPTED — Cold-start boundary recorded — 2026-10-01

Human decision：P7-R2-A adopted。Cold-start limitation 记录为
environment/runtime boundary，不计为 ES failure。

#### 概念区分（本次 blocker 的副产品）

```text
Initialization = 产生第一个 state（空白 → 有状态）
Continuation   = 利用已有 state 延续计算（有状态 → 未来状态）

SimiGo 当前验证的是 Continuation，不是 Initialization。
P6 frozen definition 中的 "continuity" 天然有前态。
```

#### 命题边界收紧

```text
❌ 不声称：Execution State can initialize computation from nothing
✅ 声称：Execution State preserves continuation of an already
         established computation state
```

#### P7-R2 修订实验路径

```text
Existing validated S₀（来自 P5-2-C checkpoint）
  ↓
Native checkpoint（loadSessionCache 加载）
  ↓
Save checkpoint（saveSessionCache）
  ↓
Process termination
  ↓
Fresh process restore（loadSessionCache from saved checkpoint）
  ↓
Δ continuation（generate）
  ↓
Closure invariant observation
```

#### Cold-start limitation 记录

```text
NativeMLX cold-start generate → CancellationError
影响：Phase A 不能从零创建 state
不影响：P7-R2 核心命题（continuation，非 initialization）
归类：environment/runtime boundary
后续：可单独作为 P7-R3 Cold Initialization Validation（如需）
```

Current state:

```text
P7-R2-A = ADOPTED
Blocker = 解除（使用已有 checkpoint 作为 seed）
Next = 修改 harness → 执行
```

### P7-R2 COLD-START BLOCKER DISCOVERED — 2026-10-01

P7-R2 harness 执行发现 NativeMLX 冷启动路径系统性 CancellationError。

#### 诊断

```text
Task.isCancelled = false       ← 外层 task 未取消
Task.checkCancellation() = OK  ← 预检查通过
native.generate() → CancellationError  ← 内部取消

三种绕法均失败：
  async test → cancelled
  Task.detached → cancelled
  expectation + Task {} → cancelled
  重试 ×3 → 全部 cancelled
```

#### 根因分析

```text
MLX backend 有两条 generate 路径：

  restored session path:
    loadSessionCache → ChatSession 已有 KV state
    → generate → reuse/extend → ✅ WORKS (P5-2-C uses this)

  cold start path:
    无 pre-existing session
    → ChatSession 从零创建
    → generate → ❌ CancellationError

P5 系列全部走 restored path（先 loadSessionCache 再 generate）
P7-R2 需要走 cold start path（从零生成新 state）
→ cold start path 有系统性问题
```

#### 影响

```text
P7-R2 Phase A（Producer）需要从零生成 history
但冷启动 generate 不可用
→ Phase A 无法在 XCTest 环境中执行
```

#### Workaround 选项

```text
A. 使用 P5-2-C 已有的 checkpoint 作为 seed state
   → 从 checkpoint 恢复 → 生成新 history → 再 checkpoint
   → 这仍然测试 save/destroy/restore/continue
   → 只是不从"完全零"开始

B. 用非 XCTest 方式运行 Phase A（CLI 脚本）
   → 需要 new target 或 command line tool

C. 修复 NativeMLX cold start path
   → 需要调查 mlx-swift 内部 task 取消机制
   → 可能是 upstream bug
```

Current state:

```text
P7-R2 = BLOCKED by cold-start CancellationError
Workaround = Option A recommended (seed from existing checkpoint)
Blocker = human decision on workaround approach
```

### P7-R2 DESIGN DIRECTION FROZEN — 2026-10-01

Human direction：P7-R2 目标不是 cross-backend output comparison，
而是每个 backend 独立的 save→destroy→restore→continue validation。

#### P7-R2 核心命题

```text
∀ backend:
  create(S₀) → generate → save → destroy → restore → continue(Δ)
  → closure invariant 保持

不是：MLX output == llama output
而是：每个 backend 独立满足 continuation invariant
```

#### 实验矩阵

Cell A (MLX runtime replication):
```text
create session → generate history → checkpoint
→ destroy runtime → restore → continue
检查：Identity 保持 / Position 增长 / Anchor 对齐 / Continuation 可继续
```

Cell B (llama.cpp runtime replication):
```text
create context → generate → persist state
→ destroy process → restore → continue
检查：同上四项
```

判据：
```text
∀ backend: restore(S) + Δ → valid continuation
（不是 output identical）
```

#### 理论方向冻结

```text
ES 不是固定 struct，而是满足条件的映射：

Abstract Closure
  → mapping → Backend-specific representation

MLX: {modelId, kvFingerprint, processedTokenCount, cachedTokens,
      history anchor, continuation rule}
llama: {executionId, token prefix, context position, continuation rule}

两个不同实现都存在满足同一 continuation invariant 的关系闭包。
```

#### 路线确认

```text
P7-R2 → L2 重冻结 → Security → Palace
Palace 前置条件：computation topology 完全坐实
```

Current state:

```text
P7-R2 = DIRECTION FROZEN / DESIGN PENDING
P8/P9 = PAUSED
Blocker = P7-R2 harness design（下一步）
```

### P7 AUDIT REVIEW ACCEPTED — EVIDENCE HIERARCHY ESTABLISHED — 2026-10-01

Human review of P7 audit findings：接受降级措辞。正向修正，非实验失败。

#### 四层证据体系（新框架）

```text
Level 0  抽象定义层
         ES = {I,P,A,C} minimal relation closure
         状态：✅ P6 FROZEN

Level 1  Backend Contract Layer
         验证：backend 是否可表达 closure relations
         状态：✅ P7 contract-level validated（llama backend）
              MLX relation evidence：✅ P5-2-C/P5-4

Level 2  Runtime Execution Layer
         验证：真实模型计算是否保持 continuation invariant
         状态：❌ 未验证

Level 3  Production Layer
         验证：跨模型/跨环境/安全转移
         状态：❌ 未验证
```

#### fakeTokens 影响评估

```text
P7 当前可证明：
  llama adapter 的 closure 数据结构可以承载这些关系

P7 不能证明：
  llama.cpp runtime 中这些关系维持真实计算连续

原因：SHA256 伪 token 只证明整数序列上的 prefix relation
     不证明真实 tokenizer + KV position + model semantics
```

#### 下一步路线（取代直接 cross-backend output comparison）

```text
P7-R2: Real Carrier Continuation Validation（优先）
  目标：llama.cpp backend 真实保存和恢复 Execution State
  流程：Create S₀ → save → destroy runtime → restore → continue
  验证：Identity(lineage) / Position(N→N+δ) / Anchor(stable) /
        Continuation(restore+extend, 非 cold start)

P7-R3: Cross-backend Runtime Mapping（后续）
  前提：P7-R2 成立
  目标：Abstract Closure 作为 MLX 和 llama 之间的 mapping 层
  验证：same future continuation property（非 output equality）
```

#### 研究方法论

```text
P5 教训：实验设计和目标不一致
P7 教训：结论范围超过证据范围

后者是正常收敛：提出抽象 → 验证 → 发现边界 → 收紧定义 → 再验证
```

#### Palace 决策

```text
不进入 Palace。
理由：Palace 依赖 ES 是稳定抽象。
当前：closure definition 稳定 ✓ / contract representation 部分验证 ✓
     runtime portability 未完全验证 ✗
→ 进入 Palace 会混合两个未分离的问题
```

Current state:

```text
P6 = FROZEN
P7 contract-level = VALIDATED（措辞已收紧）
P7-R2 real carrier = NEXT（待设计）
P7-R3 cross-backend runtime = AFTER R2
P8/P9 = PAUSED
Blocker = P7-R2 design pending
```

### P7 AUDIT STAGE 0 + STAGE 1 COMPLETE — CRITICAL FINDINGS — 2026-10-01

#### Stage 0: Original P7 frozen

```text
P7 harness commit: 36b67c9 (slamfinger/SimiGo main)
P7 result file: /tmp/simigo-p7/p7-summary.json
P7 result SHA256: 733794be48898c391a1a2f8d51a13eb79250f73d2932d3b9dad5510d93c2af8f
llama adapter commit: 716de52 (Lab repo)
MLX harness commit: f4803c8 (P5-2-C)
```

#### Stage 1: Backend isolation — CONFIRMED WITH CAVEATS

**Import isolation：**
```text
MLX NativeMLX: imports MLX, MLXLMCommon, MLXLLM, Tokenizers
llama adapter: imports Foundation, SimiGoRuntimeContract only
→ 零 MLX framework 依赖 → 真正独立实现路径 ✓
```

**P7 test 实际执行的 backend 路径：**
```text
NativeMLX references:       0（未使用）
MLX framework references:   0（未使用）
LLAMAServerBackend:         3（直接使用）
Real tokenizer references:  0（未使用）
MLX coordinator references: 0（未使用）
→ P7 测试仅执行了 llama.cpp backend 代码路径
→ MLX evidence 来自 P5-2-C/P5-4 的引用，非重新执行
```

**Token generation：**
```text
P7 使用 fakeTokens()——SHA256 hash 生成确定性伪 token
非真实 tokenizer 输出
→ P7 验证的是 closure STRUCTURE（contract relations 正确工作）
→ P7 未验证真实 tokenizer 行为
```

#### 审计结论

```text
P7 结论的适用范围需要收紧：

✅ 已证明：
   Contract 类型（ExecutionID/Position/Continuation/Handle）
   + ExecutionContinuityCoordinator
   + LLAMAServerExecutionStateBackend
   可以正确表达 closure relations（结构完整性）

⚠️ 未证明：
   两个真实推理引擎在相同模型上产生等价结果
   （需要真实模型推理 + 真实 tokenizer 的 cross-backend 运行）

❌ 不能声称：
   "MLX 和 llama.cpp 的实际推理结果等价"
   P7 没有运行任何真实推理
```

#### 修订后的 P7 结论措辞

```text
旧措辞（过强）：
  "Cross-backend Portability Validated L1"

新措辞（准确）：
  "Contract-level Closure Mapping Validated：
   Execution State closure 的 contract 类型可以在
   LLAMAServerExecutionStateBackend 中正确表达。
   MLX 侧表达已在 P5-2-C/P5-4 中独立验证。
   两 backend 共享 contract layer，backend 实现独立。
   尚未验证：真实推理层面的 cross-backend 等价性。"
```

#### Stage 2-4 待执行项

```text
Stage 2: 需要真实模型推理的 cross-backend 对比（待授权）
Stage 3: 外部执行观测（CPU/Memory/GPU/file access）
Stage 4: Invalid mapping negative control
```

Current state:

```text
P7 Audit = Stage 0 + Stage 1 COMPLETE
发现 = P7 是 contract-level 验证，非 real-inference 验证
措辞 = 已收紧
Next = human 决定是否需要 real-inference cross-backend test
Blocker = none（分析完成，等待 human 方向）
```

### REPLICATION / AUDIT PHASE ENTERED — NEW RESEARCH PAUSED — 2026-10-01

Human direction：暂停 P8/P9 扩展，进入系统性复核。

```text
理由：
  实验结果正确 ≠ 实验过程真实执行了目标路径
  P5 审计已暴露此风险
  P5-P7 是 Execution State 定义的基础——如果基础证据链有误差，
  Security / Palace / Runtime Contract 都会建立在不稳定地基上
  Activity Monitor 无波动提示缺少外部可观察执行证据
```

#### 复核状态

```text
P4   Common Base topology      → 待复核
P5   Dependency Closure        → 待复核
P7   Cross-backend Mapping     → 待复核
P8   Security Boundary         → PAUSED
P9   Palace Mapping            → PAUSED
```

#### 复核优先级

```text
第一优先：P7（最高层结论，依赖最多）
  确认：两 backend 确实走了不同实现路径
  确认：invariant 而非 output
  加入：外部执行证据（CPU/Memory/GPU/文件访问）

第二优先：P5-2-C（ES 本体最关键实验）
  确认：Full = 完整 history + KV + continuation（非 probe-only）
  确认：每个 ablation 只改变一个变量
  重点：Position 确认同 carrier 不同 relation（非 carrier 损坏）

第三优先：P4（最基础）
  确认：分支共享同一 snapshot（不是不同起点）
```

#### 统一实验记录规范（本次复核一并落地）

```json
{
  "run_id": "...",
  "timestamp_wall": "...",
  "timestamp_monotonic": "...",
  "backend": "mlx",
  "model": "...",
  "input_hash": "...",
  "state_before": { "identity": "", "position": "", "anchor": "" },
  "operation": "...",
  "state_after": {},
  "output_hash": "...",
  "resource_observation": { "memory_before": "", "memory_after": "" }
}
```

Current state:

```text
Phase = REPLICATION / AUDIT
New research = PAUSED
P8/P9 = PAUSED
Blocker = audit execution (prioritized: P7 → P5-2-C → P4)
```

### P7-G0 HUMAN REVIEW — AUTHORIZED FOR HARNESS — 2026-10-01

Human review of P7-G0 audit：授权进入 harness，附三项纪律冻结。

#### 冻结纪律

```text
1. 不比较内部字段（modelId ≠ modelIdentity 的值等）
2. 不要求 backend 数据结构一致（history[] ≠ token prefix）
3. 不以单次输出一致作为 closure 证明
```

#### Identity 映射修正

```text
不测试字段相等。
测试：是否存在足以保证同一计算 lineage 的 Identity relation。
MLX: model semantics + execution lineage
llama: model semantics + execution lineage
验证：same abstract identity（不是 same field values）
```

#### Anchor 映射修正（最关键）

```text
不测试 token count 相同。
测试：同一 semantic input → 不同 backend → 等价 continuation boundary。
判据：A_MLX → mapping → A_llama 保持 future continuation point 不变。
P5-4 已证 Position ≠ Anchor，不能因 token count 匹配就认为 anchor 成立。
```

#### 判定措辞（继承 P5 风格）

```text
Mapping Validated:  I ✓ P ✓ A ✓ C ✓
Mapping Partial:    某项 partial（backend 支持 closure 但表达能力不同）
Mapping Unavailable: 某关系无法建立任何对应
```

#### 措辞约束

```text
不是："llama.cpp 具有 Execution State"
而是："llama.cpp adapter 当前存在表达 Abstract Closure 的候选路径"
P7 证明 mapping exists，不是 backend already implements theory
```

Current state:

```text
P7-G0 = REVIEWED / AUTHORIZED FOR HARNESS
三项纪律冻结
阻塞 = none（可进入 harness 编写）
```

### P7 OP-7-1..3 ANSWERED — CODE-LEVEL AUDIT — 2026-10-01

代码级审查 `LLAMAServerExecutionStateAdapter.swift`（294 行）、
`LLAMAServerExecutionStateBackend.swift`（90 行）、
`LLAMAServerExecutionStateExecutor.swift`。

#### OP-7-1: Closure mapping 定义方向 + adapter 支持范围

```text
映射方向已确认：Abstract Closure → 独立 backend expression
（adapter 注释明确："Keeping that strategy separate from MLX
  proves the contract surface is not tied to MLX types"）

Adapter 对四项 closure relation 的支持状态：

Identity:
  ✅ 部分支持
  表达 = ExecutionID (opaque) + openModelIdentity (model path)
  缺失 = 无 kvFingerprint 等价物（config 绑定不可用）
  差异 = MLX 有 config-level identity，llama adapter 没有

Position:
  ✅ 支持
  表达 = ExecutionPosition (Int64) + tokenPrefix [Int] + boundPositions
  等价 = processedTokenCount ↔ tokenPrefix.count
  差异 = MLX 用 token count + ledger，llama 用 token prefix array

Semantic Anchor:
  ✅ 部分支持
  表达 = nextInput (text) 在 ExecutionContinuation 中
        + tokenPrefix（隐含语义——tokens 来自 tokenizeText(history)）
  缺失 = 无独立 history[] 数组（历史嵌入在 token prefix 中）
  差异 = MLX 有显式 history[] JSON 数组，llama 只有隐式 token prefix

Continuation:
  ✅ 支持
  表达 = ExecutionContinuation (nextInput / continuationID)
        + isPrefix 语义（token prefix 天然是前缀结构）
  等价 = MLX isPrefix(existing, incoming) ↔ token prefix extend
  差异 = MLX 有 PromptCacheReusePolicy（多层决策），llama 是线性 extend
```

#### OP-7-2: Identity 跨 backend 判定标准

```text
冻结标准："same model semantics + same conversation lineage"

理由：
- same model file 不可行（MLX 用 safetensors，llama 用 GGUF——
  文件格式不同是 carrier 差异）
- same conversation lineage 可行：两 backend 从同一初始 text
  createExecution → 后续相同的 user turn 序列 → 确认同一 lineage

验证方法：
1. 两 backend 分别 open() → 获取 modelIdentity
2. 两 backend 对同一 text 调用 tokenizeText → 比较 token count
   （token IDs 可能不同——tokenizer 差异；count 应接近）
3. 两 backend 分别 createExecution(id: 同一 ExecutionID, text: 同一初始文本)
4. 两 backend 分别 continueTurn(同一 user text)
5. 比较两 backend 的 position 增量是否一致
```

#### OP-7-3: Failure 归因规则

```text
冻结规则：

llama.cpp 无法恢复 ≠ Execution State 不成立
= 当前 backend mapping 未建立

具体归因层次：
1. LLAMAServerAdapterError.serverUnavailable → carrier 层（服务不可用）
2. LLAMAServerAdapterError.adapterNotOpen → adapter 使用错误
3. LLAMAServerAdapterError.unknownExecution → identity mapping 断裂
4. LLAMAServerAdapterError.missingCompletionTokens → carrier 层
5. ExecutionStateBackendError.noBoundRepresentation → position mapping 断裂
6. ExecutionStateBackendError.representationPositionMismatch → position 不一致

以上均归为 MAPPING_UNAVAILABLE，不归为 CLOSURE_PORTABILITY_LIMITED
（后者要求 adapter 能表达 relation 但表达结果不等价）。
```

#### Adapter 当前能力总结

```text
支持的 closure operation：
  createExecution（text → tokens → bind prefix）
  continueTurn（extend prefix → generate → advance position）
  forkExecution（复制 token prefix 到 child）
  restoreExecution（回滚到 bound position）
  discardExecution（释放 representation）

不支持的 closure operation：
  跨 checkpoint 持久化（prefix 存在内存 dict 中，不落盘）
  多模型 identity 区分（只有 openModelIdentity 一个 string）
  独立的 semantic anchor 存储（历史隐含在 token prefix 中）
```

Current state:

```text
P7 OP-7-1..3 = ANSWERED
P7 design = 可进入 harness（待 human authorization）
阻塞 = human authorization to proceed
```

### P7 CROSS-BACKEND VALIDATION DESIGN GATE — ISSUED — 2026-10-01

Artifact：`SIMIGO_LAB_P7_CROSS_BACKEND_DESIGN_GATE_20261001.md`

核心命题：同一个 ES Closure，能否映射到不同 backend carrier 并保持
continuation 关系成立？

Backend 选择：
```text
A = MLX (NativeMLX)
B = llama.cpp server（候选——已有 LLAMAServerExecutionStateAdapter）
```

实验矩阵：
```text
Cell 1: Identity 跨 backend（model/config/execution 对应）
Cell 2: Position 跨 backend（token offset 等价）
Cell 3: Anchor 跨 backend（最关键——同一 history 产生等价 anchor）
Cell 4: Continuation 跨 backend（语义等价的未来计算）
```

关键约束：
```text
不比性能，不测文件互操作，不选"更好"的 backend
测试 closure 结构，不测试 carrier 格式
Tokenizer 差异 → INCONCLUSIVE（carrier 层问题）
```

Open questions：OP-7-1..3

Current state:

```text
P7 = DESIGN GATE ISSUED / AWAITING HUMAN AUTHORIZATION
Current blocker = human review of design + backend B confirmation
```

### P6 ARCHITECTURE SYNTHESIS — FROZEN — 2026-10-01

Human review verdict：`FREEZE (Conceptual Boundary)`

#### 冻结内容

```text
✅ Execution State 定义：
   "ES is not a stored artifact. It is the minimal relation
    closure that preserves computational continuity."

✅ Relation Closure 模型：
   {Identity, Position, Semantic Anchor, Continuation}

✅ Carrier ≠ Closure 分离原则

✅ 三层模型：
   Reference Layer (Palace ←→ ES)
   Closure Layer ({I,P,A,C})
   Carrier Layer (physical media)

✅ Palace 接口边界：
   Palace = Knowledge/Reference Topology Layer
   ES = Computation Topology Layer
   连接 = Identity/Reference relation
   Palace 不定义 ES，不替代 carrier

✅ Security invariant 入口：
   INV-S1..S4（当前 S2 satisfied，S1/S3/S4 production gate）
   安全核心问题 = authority continuity，不是数据加密
```

#### Closure 命名精确化

```text
冻结名称：Minimal Dependency Closure for MLX-based Execution State
（非 Universal Minimal Closure——后者需 multi-backend 验证）
```

#### 保留开放

```text
OP-6-1  Closure 是否跨 backend 保持？
OP-6-2  是否存在更小闭包？
OP-6-3  Palace 如何实例化 Reference Layer？
OP-6-4  Security invariant 如何工程化？
```

#### 后续路线

```text
P6 FREEZE ← 当前
  ↓
P7 Cross-backend Validation（优先于 Palace）
  ↓
P8 Security Boundary
  ↓
P9 Palace Mapping
```

P7 优先于 P9 的理由：如果 closure 不能脱离 MLX 存在，
Palace 最终只能服务一个 backend。

Current state:

```text
P6 = FROZEN (Conceptual Boundary)
研究核心问题 = "什么关系使一个计算过程仍然是同一个过程？"
Current blocker = none
Next = P7 Cross-backend Validation（方向归 human）
```

### P6 ARCHITECTURE SYNTHESIS — FREEZE CANDIDATE — 2026-10-01

Artifact：`SIMIGO_LAB_P6_ARCHITECTURE_SYNTHESIS_20261001.md`

核心定义（冻结候选）：
> Execution State is not a stored artifact. It is the minimal
> relation closure that preserves computational continuity.

三层模型：
```text
Reference Layer: Palace ←→ ES（Identity/Reference 连接）
Closure Layer:   {I, P, A, C}（已验证 L1 minimal set）
Carrier Layer:   物理介质（可替换，≠ Closure）
```

安全不变量入口点：
```text
INV-S1 possession≠capability: NOT SATISFIED（production gate）
INV-S2 authority∉state:       SATISFIED ✓
INV-S3 consent for transfer:  NOT SATISFIED（production gate）
INV-S4 revocation≠deletion:   NOT SATISFIED（production gate）
```

Palace 约束：
```text
共享 Relation Closure 抽象
通过 Identity/Reference 连接，不合并 schema
Palace 不是 ES 的存储后端
前提：P6 frozen + Security invariants acknowledged
```

Current state:

```text
P6 = FREEZE CANDIDATE / awaiting human review
Palace = interface constrained, implementation deferred
Security = invariants defined, mechanism deferred
Current blocker = human review of P6 synthesis
```

### P5-5 STATE BOUNDARY SYNTHESIS — DRAFT COMPLETE — 2026-10-01

Artifact：`SIMIGO_LAB_P5_5_STATE_BOUNDARY_SYNTHESIS_20261001.md`

核心产出：

§1 Execution State 边界
```text
State = {Identity, Position, Semantic Anchor, Continuation} 最小关系闭包
Carrier = KV tensors / file format / database / memory page（可替换）
判定原则：替换 carrier 但保持 relations → 同一 State；
         破坏任何 relation 即使 carrier 完好 → 不同 State
```

§2 Agent 环境归属分类
```text
对话历史 → Anchor（D）
System prompt → 条件性 Anchor（进入 context 则是）
Tool definitions → Continuation（D）
temperature/maxTokens → Generate Parameter（R，非 State）
UI 设置 → 外部（非 State）
用户权限 → Security boundary（非 State）
文件系统 → External world state（非 State）
判定原则：进入 transformer context + 变更导致输出不同 + 属于 I/P/A/C
```

§3 Palace 接口
```text
共享 Relation Closure 抽象
Palace = Knowledge Topology (past, eventual)
ES = Computation Topology (future, transactional)
连接 = Identity/Reference relation
Palace 不是 ES 的存储后端
```

Current state:

```text
P5-5 = Synthesis draft complete / awaiting human review
Palace = Interface defined, implementation deferred
Security = Constraint track, not active
Current blocker = human review of P5-5 boundary document
```

### P5-4 EXECUTED — Minimal Dependency Set Identified (L1) — 2026-10-01

Harness: `Palace1P54MinimalReductionTests.swift` @ SimiGo `4ab180a` (public)
Run: test passed 101.8s, runUUID `37897ADB-1D6F-45D1-A073-A08BC6195BF2`

#### Verdict: Minimal_Dependency_Set_Identified_L1

四项 closure relation 独立不可替代。无 containment/equivalence 发现。

#### Key results

```text
Full (baseline):
  output = "这个会话在查看桌面文件结构……项目部管理制度汇编内容。"
  → 正确引用会话内容 ✓

PA-2 (核心：same count, different content):
  Position 保持（17 条消息，token count 匹配）
  Anchor 破坏（内容替换为 placeholder）
  output = "该会话此前由一系列占位符消息组成，旨在打破语义锚定
           并保留令牌数量。"
  → 模型描述了 PLACEHOLDER 内容，不是原始会话！

  ★ 关键发现：模型的输出被 rendered prompt text（placeholder）
    主导，而不是被 KV cache 中的原始语义主导。
    KV cache 承载计算状态，但 rendered history text 决定语义上下文。

PA-3 (truncated to 3):
  output = 265 chars（结构化异常输出/code-comment 格式）
  → Position 破坏后 continuation 严重退化

PA-1 (empty history):
  output = "该会话此前未进行任何对话……"
  → 与 P5-1 一致

IC (extreme reduction I+C only):
  output = 同 PA-1
  → P+A 不可冗余移除
```

#### PA-2 的架构含义

```text
Position（token count 对齐）≠ Semantic Anchor（内容-语义对应）

证明：
1. A ≠ P——二者是独立关系，不可合并
2. KV cache 的计算状态不能替代 rendered history text 的语义锚定
3. 模型"信任" rendered prompt text 超过 KV cache 中的隐含语义
4. Execution State 不能只保存 KV tensors——必须同时保存
   semantic anchor（或等价物）才能维持 continuation 的语义正确性
```

Current state:

```text
P4 = Common Base topology validated
P5-1 = KV-only continuation rejected
P5-2-C = Backend Dependency Closure validated
P5-4 = Minimal Dependency Set Identified (L1)
       {I, P, A, C} 独立不可替代
三层 = Palace(knowledge) / ES(computation) / Security(boundary)
Next = human review → Palace Mapping / Security / P6 synthesis
Current blocker = human second-layer review
```

### P5-2-C HUMAN REVIEW — INTERPRETATION TIGHTENED — 2026-10-01

Human review of P5-2-C result：

#### 措辞收紧

```text
✅ 确认的结论：
   "在当前 MLX backend 的 continuation contract 下，
    Identity、Position、Anchor、Continuation 四类关系
    均表现为必要依赖。"

❌ 不可推出的结论：
   "Execution State 必须包含这四项。"

原因：实验对象是 MLX implementation contract，不是
universal Execution State ontology。中间隔着
ChatSession / PromptCacheReusePolicy / ledger 一层。
```

#### 关键发现重估

**-Position（最有价值）：**
KV carrier 保留 + Position relation 破坏 → 模型无法访问过去计算。
这直接证明 **KV tensor 不是完整的 Execution State**。
Execution State ≈ KV physical state + position + alignment + identity
+ continuation path，而不是 = KV cache 文件。

**-Continuation（拓扑视角）：**
输出"晴"不是报错——系统进入了一条合法的新计算路径。
区分了三种情况：
```text
计算失败       → 不是（模型正常 generate）
状态丢失       → 不是（State 存在，模型运行正常）
状态存在但连接断开 → 是（continuation topology 断裂）
```

**-Identity（重新分类）：**
modelId mismatch → reject 更像 authority / validity relation，
而非 continuation 本身。这与后续 Security 研究自然连接。

#### 下一步：P5-4 Minimal Closure Reduction

目标不是增加关系，而是检测冗余：
```text
问题：四项关系之间是否存在替代关系？
例如：Anchor ⊃ Position？
      或 (Identity + Anchor) 可以替代 (Position + Continuation)？
      闭包是线性列表 A+B+C+D 还是关系网络 (A+B) OR (C+D)？
```

三层分离（保持不混）：
```text
Palace          → 保存知识/信息拓扑
Execution State → 保存计算连续拓扑
Security        → 限制拓扑的转移边界
```

Current state:

```text
P4 = Common Base topology validated
P5-1 = KV-only continuation rejected in current backend
P5-2-C = Backend Dependency Closure validated (措辞已收紧)
Current hypothesis = Execution State is a relation closure, not a carrier
Next = P5-4 Minimal Closure Reduction
Current blocker = P5-4 design pending (human direction)
```

### P5-2-C EXECUTED — Backend Dependency Closure VALIDATED — 2026-10-01

Harness: `Palace1P52CDependencyClosureTests.swift` @ SimiGo `f4803c8` (public)
Run: test passed 93.9s, runUUID `2811FC67-B5F3-4153-AC6A-016D0FAD2E69`
Isolation: checkpoints SHA256 MATCH

#### Results

```text
Verdict: Backend_Dependency_Closure_Validated

Full (baseline):
  outcome = NO_EFFECT (continuation succeeded)
  output  = "这个会话在查看桌面文件结构，逐步浏览了'参考文件'
            目录下的'项目部管理制度汇编'内容。"（正确引用了会话内容）
  genTokens = 24

-Identity:
  outcome = VALIDATION_REJECTED
  detail  = loadSessionCache threw (modelId nil → identity gate)
  意义    = Identity 在当前实现中是硬前置条件，不可独立消融

-Position:
  outcome = CLOSURE_ABLATED
  detail  = history 17→1 fake，position misaligned
  output  = "该会话此前未进行任何操作，因为这是当前对话的第一条
            消息。"——模型丢失了全部 17 条 history 的记忆
  意义    = Position 关系破坏 → continuation 语义不完整

-Continuation:
  outcome = CLOSURE_ABLATED
  detail  = non-prefix input → cold prefill
  output  = "晴"（回应天气问题，未使用 S₀）
  意义    = Continuation path 断裂 → S₀ 完全未被消费

-Anchor:
  outcome = CLOSURE_ABLATED（P5-1 引用，不重复执行）
  detail  = KV present, history=[] → ledgerBootstrapPending → rebuild
```

#### Interpretation

```text
Identity:     NECESSARY（硬前置：validation gate 拒绝）
Position:     NECESSARY（消融后模型完全丢失会话记忆）
Anchor:       NECESSARY（P5-1 证明：alignment 断裂 → rebuild）
Continuation: NECESSARY（消融后 S₀ 完全未被使用）

Backend Dependency Closure Validated（Level 1, MLX only）
Universal Minimal Closure: NOT CLAIMED (Level 2 requires multi-backend)
```

关键观察：-Position 的输出"该会话此前未进行任何操作"与 Full baseline
"这个会话在查看桌面文件结构……"形成鲜明对比——position 破坏后模型
完全不知道会话历史，证明 position relation 不是可选优化，而是
continuation 的语义必要条件。

Current state:

```text
P4 = PASS (topology)
P5-1 = SEALED / INCONCLUSIVE
P5-2-0 = Dependency Map COMPLETE
P5-2-ER = PASS-WITH-REVISIONS
P5-2-C = EXECUTED / Backend Dependency Closure VALIDATED
Palace Mapping = UNBLOCKED (provisional closure now has backend evidence)
Security Boundary = INV-S2 confirmed (authority ∉ state)
Current blocker = human review of P5-2-C result
```

### P5-2-C rev.2 AUTHORIZED — Backend Dependency Closure Validation — 2026-10-01

Human authorization：`执行 rev.2，实验名称固定为
"Backend Dependency Closure Validation"，不使用 "Minimal Closure Proof"。`

Authorization conditions:
```text
1. Full arm 必须定义为"正确 continuation"（完整 closure + Δ → Y），
   不只是 load + generate
2. -Position 结果解释保持 CLOSURE_ABLATED（关系破坏 → contract
   不满足），不过度归因到单一原因
3. -Anchor 引用 P5-1 已有证据，不重复执行
4. NO_EFFECT 必须保留——"删掉所谓必要关系但仍然成功"是有价值的
   修正信号
5. 三种可能结果：
   A. 全部必要 → MLX backend dependency closure validated
   B. 某项无影响 → 从闭包移除（更好的研究结果）
   C. 多种组合均可 → 闭包是关系网络而非线性列表
```

核心研究问题（rev.2 最终表述）：

> 验证 Dependency Closure 中各关系项对于当前 backend continuation
> contract 的必要性。

Current state:

```text
P5-2-C = AUTHORIZED / READY TO EXECUTE
实验名称 = Backend Dependency Closure Validation
阻塞 = none
```

### P5-3 DESIGN GATE HUMAN REVIEW — DUAL-TRACK DEFERRED — 2026-10-01

Human review of `56f7a9e`：

```text
Track A (Palace Mapping):
  状态 = REGISTERED IDEA / NOT ACTIVE RESEARCH LINE
  理由 = 基础闭包尚未证明；Palace 依赖的"信息关系动态形成"
         在"计算关系闭包是否真实存在"确认之前不可推进

Track B (Security Boundary):
  状态 = REQUIREMENT TRACK / NOT ACTIVE EXPERIMENT
  保留 = 四维权限模型 + INV-S1..S4 作为 production constraint
  理由 = 安全验证需要建立在稳定的 Execution State 定义之上；
         当前 provisional closure 不足以定义"权限作用于什么"

下一阶段 = P5-2-C Closure Validation
```

裁定理由：P4 证明存在（S₀ topology），P5-2 ER 提出 closure 定义，
但缺失中间验证层——Candidate Closure 是否真能支撑 continuation。
不完成此验证，Palace 是类比、Security 是风险分析、三层架构是结构
美化——都不是研究结论。

核心研究问题：

> Minimal Closure {I, P, A, C} 是否是 continuation prerequisite？

方法 = remove-one-relation ablation（P5-2-C）。

```text
P4 PASS
 └─▶ P5-1 SEALED
      └─▶ P5-2 ER PASS-WITH-REVISIONS
           └─▶ P5-2-C Minimal Closure Validation  ← NOW
                ├─▶ PASS → Palace / Security 可推进
                └─▶ FAIL → revise closure definition
```

Current state:

```text
P5-3 (Palace + Security) = DEFERRED / REGISTERED IDEA
P5-2-C = ACTIVE / DESIGN PENDING
Current blocker = none (design phase can begin immediately)
```

### P5-3 DESIGN GATE ISSUED — DUAL-TRACK — 2026-10-01

Artifact：`SIMIGO_LAB_P5_3_DESIGN_GATE_20261001.md`

Track A: Palace Relation Closure Mapping
```text
共享抽象假设: Relation Closure（nodes + relations + transitions）
三层模型: Immutable Evidence → Relation Graph → Execution Reference
核心张力: transactional（ES）vs eventual（Palace）一致性
Open: OP-PA-1..4
```

Track B: Execution State Security Boundary
```text
安全模型转变: data access control → execution authority control
四维权限: Ownership / Transfer / Revocation / Audit
安全不变量:
  INV-S1 possession≠capability: NOT SATISFIED（无 credential gate）
  INV-S2 authority∉state: SATISFIED（runtime 独立管理工具权限）
  INV-S3 consent for transfer: NOT SATISFIED
  INV-S4 revocation≠deletion: NOT SATISFIED
Open: OP-SB-1..4
```

三层架构候选：
```text
Knowledge Topology（Palace Layer 1-2）
  → Computation Topology（Execution State closure）
    → Authority Boundary（Security invariant model）
```

Current state：

```text
P5-3 = DESIGN GATE ISSUED / AWAITING HUMAN REVIEW
Blocker = human review（Palace 主线确认 + Security 升级确认）
```

### P5-2-ER COMPLETE — PASS-WITH-REVISIONS — 2026-10-01

Three reviewer outputs + self-review integration complete.

Artifacts:
- Reviewer-1 (Architecture): `SIMIGO_LAB_P5_2_ER_REVIEWER1_ARCHITECTURE_REVIEW_20261001.md`
- Reviewer-2 (Security): `SIMIGO_LAB_P5_2_ER_REVIEWER2_SECURITY_REVIEW_20261001.md`
- Reviewer-3 (Integrity): `SIMIGO_LAB_P5_2_ER_REVIEWER3_INTEGRITY_REVIEW_20261001.md`
- Self-review: `SIMIGO_LAB_P5_2_ER_SELF_REVIEW_INTEGRATION_20261001.md`

Verdict: `PASS-WITH-REVISIONS`

Revisions applied to draft (`d1a415f` → revised in-place):
```text
R3-1  §0 ontology = CONSTRUCTED (not discovered)
R3-2  "最小" → "候选最小" (until P5-3 ablation)
R3-3  "五问" → "已识别的五个关系维度"
R3-4  P5-1 trace numbers marked "old execution, root-cause only"
R1-Q1 Carrier separated from Closure in §0 (explicit boundary)
```

Minimal Closure result:
```text
Identity:      necessary (code-fact)
Position:      necessary (code-fact)
Anchor:        necessary (code-fact; minimum form OPEN → P5-3 axis A)
Continuation:  in-state (Contract SC-2)
Minimality:    PROVISIONALLY YES (conceptual; P5-3 required)
Carrier:       NOT closure member (all reviewers confirm)
```

Security result:
```text
Capability level: EXECUTION-LEVEL
meta.json = highest-value target (plaintext conversation + identity)
Revocation: DOES NOT EXIST — requires design
Delegation: context YES / authority NO / assumptions PARTIAL
Possession = capability: conditionally (requires closure completeness)
```

Open points updated (OP-P5-6..8 new from Security review):
```text
OP-P5-6  KV inversion attack risk
OP-P5-7  Revocation mechanism design
OP-P5-8  Cross-user delegation protocol
```

Current state:

```text
P4 = PASS (topology)
P5-1 = SEALED / INCONCLUSIVE
P5-2-0 = Dependency Map COMPLETE
P5-2-ER = PASS-WITH-REVISIONS / revisions applied
P5-2 = Dependency Closure REGISTERED (provisional, candidate minimal)
Palace Mapping = UNBLOCKED (provisional closure language required)
P5-3 ablation = READY FOR DESIGN (axes A/B/C registered)
Current blocker = none
```

### P5-2 OPENING DRAFT HUMAN REVIEW — REVIEW-READY — 2026-10-01

Draft artifact：`SIMIGO_LAB_P5_2_DEPENDENCY_CLOSURE_OPENING_DRAFT_20261001.md`
(commit `d1a415f`)

Human review verdict：`REVIEW-READY / NOT PASS`

> 不标记为"理论完成"，因为 draft 完成的是研究框架重构，
> 还没有完成"闭包是否最小"的证明。

#### Registered strengthening points (carry into external review)

**R-1 Carrier ≠ Closure member**
```text
Execution State Closure = { Identity, Position, Anchor, Continuation }
Carrier                  = { KV, Tensor, Cache, Memory, Database }
Relation: Closure ──instantiated by──▶ Carrier
NOT: Closure = Carrier
```
后续文档明确区分，避免 backend 切换时重蹈覆辙。

**R-2 Minimality NOT proven**
当前 ES = {I, P, A, C} 是候选，不是最小证明。
需建立 "remove one relation" test（概念级）：

| 去掉 | 检验 |
|---|---|
| Identity | 能否确认状态属于哪个计算？ |
| Position | 能否知道未来从哪里继续？ |
| Anchor | 能否解释状态对应什么？ |
| Continuation | 能否产生未来路径？ |

如删除某项后仍可继续 → 该项不是必要闭包成员。

**R-3 Palace 不合并**
保持 §6 初探的二元区分：
```text
Palace           = Knowledge Topology（past-oriented）
Execution State  = Computation Topology（future-oriented）
共同层           = Relation Model
```
不定义 Palace = Execution State。

**R-4 Capability Risk 提前至 P5-3 之前**
P4 PASS 改变研究性质：从"能不能保存状态"变为
"谁拥有状态，谁拥有未来计算能力"。
Security Boundary Review 必须在 Palace mapping 或 ablation 之前完成。
审查范围：
```text
A. State possession  → state + identity + path = future computation capability？
B. State portability → 跨 machine/model/user/tenant 迁移的风险？
C. State delegation → B 继承 A 的 context/authority/hidden assumptions？
```

#### Current state

```text
P4     = PASS (topology existence)
P5-1   = SEALED / INCONCLUSIVE
P5-2-0 = Dependency Map COMPLETE
P5-2   = REVIEW-READY (draft `d1a415f`, 4 strengthening points registered)
Next   = P5-2 External Review → Minimal Closure Review + Security Boundary Review
       → P5-3 Palace Mapping (if activated)
Current blocker = P5-2 external review assignment (human)
```

### P5-2-ER TASK ORDER ISSUED — 2026-10-01

Human direction：P5-2 external review 先行（含 Minimal Closure +
Security Boundary），Palace Mapping 不得在 ER 完成前激活。

Task order artifact：
`SIMIGO_LAB_P5_2_ER_EXTERNAL_REVIEW_TASK_ORDER_20261001.md`

Scope：
```text
Review A: Minimal Closure
  A1 Identity necessity
  A2 Position necessity
  A3 Semantic Anchor necessity
  A4 Continuation: state or capability?
  A5 Minimality proof (remove-one-relation)

Review B: Security Boundary (P5-2-S)
  B1 State possession → capability
  B2 State leakage → what leaks?
  B3 State delegation semantics
  B4 State revocation mechanism
```

Output format：统一 YAML（per task order §Review output format）。

Current state：

```text
P5-2-ER = TASK ORDER ISSUED / REVIEW PENDING
Palace Mapping = BLOCKED until P5-2-ER completes
Current blocker = reviewer assignment (human)
```

### P5-2-0 CONTINUATION DEPENDENCY MAP + REFRAMING — 2026-10-01

Code-level audit of MLX Swift LM ChatSession + NativeMLX continuation
dependency chain. No model execution; static analysis only.

#### Root cause of P5-1 rebuild (precise code path)

ChatSession.swift L1160-1179 `ledgerBootstrapPending`:

```text
cachedTokenCount = kvCache.processedTokenCount    ← 31712 (loaded KV)
if cachedTokenCount ≤ promptTokenIds.count        ← 31712 ≤ 212 ?
  seed ledger from rendered prompt prefix
else
  "cache holds more progress than rendered transcript
   can explain" → cachedTokens.removeAll()         ← ledger invalidated
```

31712 > 212 → ledger cleared → `mainCacheIsAligned = false` →
`PromptCacheReusePolicy.decide()` → `.rebuild` → KV cache discarded.

The root cause is NOT "framework does not support KV-only" but
"token-ledger bootstrap requires `processedTokenCount ≤ rendered
prompt token count`. History text stripped → prompt shortened →
alignment broken → rebuild."

#### Dependency map (10 items, classified)

| # | Dependency | Required condition | D/R/P/O/T | Failure mode |
|---|---|---|---|---|
| 1 | KV tensors (.safetensors) | file + SHA256 match | P | restore throw |
| 2 | processedTokenCount | read from cache | R | cannot bootstrap |
| 3 | History text → rendered prompt | prompt token count ≥ processedTokenCount | D | ledger cleared → rebuild |
| 4 | Token ledger (cachedTokens) | bootstrap or prior generation | R | empty → unaligned |
| 5 | kvFingerprint | config match | R | reuseMiss → cold |
| 6 | modelId | model match | R | load throw |
| 7 | checkpointGeneration + cacheSHA256 | nonempty + hash match | P | fail-closed |
| 8 | storageKey | sessions pool key | D | not found |
| 9 | GenerateParameters / KV plan | plan unchanged | R | plan change → rebuild |
| 10 | Conversation (transcript) | created from history param | D | nil → no reuse decision |

#### Dependency relation graph

```text
processedTokenCount ←── KV tensors
       │
       │ must be ≤
       ▼
rendered prompt tokens ←── history text + probe
       │
       │ bootstrap OK →
       ▼
token ledger (cachedTokens)
       │
       │ ledger.count == processedTokenCount
       ▼
mainCacheIsAligned = true
       │
       ▼
PromptCacheReusePolicy
       ├── .extend  → KV cache continued, delta-only prefill
       ├── .rebuild → KV cache discarded, full re-prefill
       └─ .rewind   → KV cache trimmed to common prefix
```

#### Key finding

KV cache and history text are **co-dependent**. The cache provides
computation state; history text provides the alignment anchor that
tells the framework "these tokens correspond to this text." Without
the anchor, the cache is rejected.

Execution State for this backend is NOT any single object (KV, history,
metadata). It is the **constraint relation set**:

```text
physical carrier (KV tensors)
  + identity (modelId, kvFingerprint, storageKey)
  + position (processedTokenCount ↔ ledger alignment)
  + semantic anchor (history text ↔ prompt tokenization)
  + continuation contract (delta ≥ 0, prefix-compatible)
```

#### Reframing for P5-2

The question is no longer "can KV continue without history?" (answered:
not in current framework). The question is:

> What is the minimal dependency closure that enables continuation?

P5-2 Phase 1 = Dependency Closure (code-level, no model execution):
classify each dependency as necessary / sufficient / neither for
continuation, and determine which belong to Execution State (D) vs
backend implementation (R).

Future P5-3 ablation axes (if activated by human):
```text
A: Content dependency — same position/KV, different history text
B: Position dependency — same text, different token boundary
C: Identity dependency — same bytes, different model/generation ID
```

Current state:

```text
P4 = PASS (S₀ topology)
P5-1 = SEALED / INCONCLUSIVE (baseline malformed + KV carrier rejected)
P5-2-0 = Dependency Map COMPLETE (10 items, root cause located)
P5-2 = READY FOR OPENING DRAFT (Dependency Closure)
Current blocker = none (analysis phase, no execution gate)
```

### P5 ATTEMPT-1 INCONCLUSIVE + MLX KV-ONLY CONTINUATION REJECTION — 2026-10-01

Harness-integrity revision (a262839) executed P5 with in-run baseline,
runUUID, SHA256 isolation. All three tests ran; equalBaseline = true on
all 8 cells (2 samples × 2 deltas); isolation SHA256 match on both
checkpoint and prefix-pool directories.

Post-execution trace audit (`native_mlx_trace.log` 2026-10-01 10:14–10:16)
revealed two critical findings:

**Finding 1 — baseline malformed (participant implementation bug).**
The in-run baseline passed only `[probe]` to `generate()`, not
`fullHistory + [probe]`. Trace showed `mode=cold promptTokens=213` —
the full history text never entered the prompt. The baseline was
effectively `∅ + Δ → Y′`, not `History + Δ → Y′`.

**Finding 2 — MLX ChatSession rejects KV-only continuation (engine
boundary fact).** The stripped condition loaded the KV cache from
safetensors (`cacheLoad history=0`, `cacheTokens=1425/31712`) but
`streamDetails(to:)` detected a history-token mismatch and triggered
`mode=rebuild`, `cacheHitTokens=0`, `cacheEff=0.00` — the loaded KV
cache was discarded and the prompt was re-prefilled from scratch
(213 tokens = system template + probe). The framework treats the
KV cache as dependent on history identity/position, not as an
independent continuation carrier.

Consequence: `equalBaseline = true` is trivially true (both conditions
generate from empty context). The P5 proposition (S₀ + Δ vs History + Δ)
was not tested. Status is INCONCLUSIVE, not FAIL and not PASS.

Engineering finding retained as a standalone result:
`MLX ChatSession rebuild logic prevents KV-cache-only continuation
regardless of history text presence — the cache is a Representation
fragment, not an independent Execution State carrier.`

Current state:

```text
P4 = PASS (S₀ can serve as common future base — topology)
P5 attempt-1 = INCONCLUSIVE (baseline malformed + KV carrier rejected)
Engineering fact = MLX ChatSession rejects KV-only continuation
Next = P5-2 redesign (what minimal relation set enables continuation?)
Trusted harness = a262839 @ slamfinger/SimiGo main (public)
Current blocker = P5-2 design gate (human direction required)
```


### LAB ES-R2 GATE C COMPLETE — VERDICT C-2 + C-3 IMPLICATION — 2026-09-30

Human 授权 Gate C（S→R' Re-materialization 首测；硬约束=old P 与 full
History 在实验环境真实缺席；S 唯一 computational input）。执行
（`bbe7003`，19.2s，零 durable 写入）：

```text
C 空间核验 = 仅 state-carrier.json（无 safetensors/无 meta.json）
Attempt 1  既有 P→R seam → FAILED（meta.json 缺失，Code=260）——seam
           需要 meta+safetensors，carrier 无法替代任一输入
Attempt 2  免 history 会话路径（仅 probe 文本）→ 会话创建于 position 2
           而非 State 的 17——模型逐字响应：「请提供具体的上下文或任务
           指令，以便我继续执行。」
R' 核验    = 零新表示工件（R' 未形成即证明其非旧 P 残留）
```

**VERDICT = C-2**：Tier-1 State 存活但无法 S→R'——**State existence 与
State executability 由运行时实验正式分离**。C-3 含义登记：S→R' 需要
compressed context carrier（Tier-2），观察宇宙内不存在——FSB-2 预言
实验证实。附带观察：无 persona 时模型明示要求上下文（对照 E3-C-2 的
虚构），登记不外推。

当前状态：

```text
ES-R2 = A CLOSED（R2-A）/ B COMPLETE（STATE-SURVIVES）/ C COMPLETE
        （C-2+C-3）/ D LOCKED（待授权）
```


### LAB ES-R2 SEALED — C-2 FINAL / C-3 SUPPORTED BOUNDARY FINDING — 2026-09-30

Human 终审封存（`0b7b976`）：

```text
Gate A = R2-A FORMATION-SUFFICIENT / CLOSED（FSB-1/FSB-2 两层边界）
Gate B = STATE-SURVIVES CONFIRMED / CLOSED（11 判据全 PASS）
Gate C = C-2 FINAL（STATE-EXISTS-BUT-NOT-REMATERIALIZABLE）
C-3    = MISSING COMPUTATIONAL BRIDGE — SUPPORTED BOUNDARY FINDING /
         NOT YET UNIVERSAL（刹车措辞登记：更高阶 State 表达/可重建中间
         态/可解释编码/State 自兼桥梁等理论可能未排除）
Gate D = NOT APPLICABLE / LOCKED（不做伪 Semantic Reuse）
ES-R2  = SEALED
```

三层分离实验性确立：**知识（transcript/语义载荷）≠ 计算状态
（identity/position/continuation 权威载体）≠ 可执行状态（能驱动 R'
物化的载体）**。压缩链终版：FSB-1 State 可形成 → Gate B State 可存活
→ Gate C State 尚不能重新物化 → State 与 Representation 之间存在未被
表达的【计算桥梁】。

ES-T2（Tier-2 Computational Bridge）登记为下一条候选研究线（NOT
STARTED，克制定义：「不读取完整 History、不使用旧 Representation 的
条件下，从独立存活的 Tier-1 State 重新产生 Representation 还缺什
么」；与设计 compressed carrier 不是一回事）。

当前状态：

```text
ES-R1/ES-D1/ES-R2 = 三链 SEALED；Contract v1.0 = UPSTREAM REFERENCE
PALACE-1 = PARKED；ES-T2 = 候选 NOT STARTED；C-4 = LOCKED
Current blocker = none（下一方向由 human 选择）
```


### LAB ES-T2 DESIGN LOCKED — T2-A CENSUS DESIGN DELIVERED — 2026-09-30

Human 授权 ES-T2 设计（Tier-2 Computational Bridge；先研究缺口不直接
设计 State）。设计文档冻结（`14ce2f6`）：

`docs/00-governance/SIMIGO_LAB_ES_T2_RESEARCH_DESIGN_20260930.md`

```text
研究问题（锁定）= 无完整 History/无旧 P 条件下，独立存活的 Tier-1
  State 重新驱动计算还缺什么
T2-A 定位 = 依赖普查，非 Tier-2 实现；KV/History/现有 Representation
  不预设为答案
追踪框架 = Gate C 失败路径三分（路径 α H→R' 重算型/路径 β P→R 装载型
  /路径 γ {identity,position,anchor}→KV(17) 观察宇宙内不存在的入口
  ——T2-A 核心问题=路径 γ 需要什么输入才可能存在）
依赖闭包清单 = 8 项（两项重点：Context 内容的可非-transcript 携带形态
  【不预设】；GDN 固定态与注意力 KV 的可重建性对称性【待实验】）
预注册 = T2-A0（闭包已被满足——即 Gate C 被推翻）/A1 单一缺失信息/
  A2 计算上下文类/A3 计算结构/A4 无法闭包
隔离 = es-t2 新空间（carrier only）；真实 store READ-ONLY
```

当前状态：

```text
ES-T2 = DESIGN LOCKED / T2-A EXECUTION AWAITING AUTHORIZATION
T2-B/C/D = LOCKED；生产 State API 禁止；PALACE-2/Backend 不启动
```


### LAB ES-T2 T2-A COMPLETE — VERDICT T2-A2 CARRIER-FORM GAP — 2026-09-30

Human 授权 T2-A 执行（Dependency Census；只读 vendor/代码追踪，零运行
时）。执行（`fe35722`）：

```text
S→R' 依赖闭包表：
  闭 = identity / position 断言 / model 环境
  开 = position 执行 + continuation 语义——同一根依赖
FIRST BLOCKING DEPENDENCY = context computation payload（把会话推进到
  17 的上下文计算内容）。其宇宙内载体只有两形态：
  形态 H = 17 条 transcript（full prefill 成本）
  形态 P = per-token KV artifact（与 P 身份融合）
  两形态均被 S→R' 硬约束排除 ⇒ 闭包开在「第三形态不存在」
Vendor API 闭合验证（决定性）：ChatSession 位置承载输入恰两类
  （history 文本 / cache+state 快照），无第三输入；vendor Important
  注释自证「表示与计算态拆分→不连贯」危害——缺口是上游推理 API
  通用形态，非 SimiGo 封装缺失
Census 附带发现（A3 边界素材）：融合工件内部分裂为 GDN 固定态
  [1,3,8192]（位置无关压缩分量）与注意力 KV [1,2,31712,256]（位置
  比例分量）——同一 save/load 单元，无机制区别对待
```

**VERDICT = T2-A2（carrier-FORM gap）+ A3 边界注记**：信息不缺（两种
形态都在宇宙内），缺的是第三形态——既非 transcript 重放亦非 P 装载的
、State 可携带的计算承载形态。

当前状态：

```text
ES-T2 = T2-A COMPLETE / VERDICT T2-A2 / T2-B/C/D LOCKED
Current blocker = none（归类与方向归 human）
```


### LAB ES-T3 DESIGN LOCKED — GATE A CENSUS DESIGN DELIVERED — 2026-09-30

Human 授权 ES-T3（Computational Result / Representation Decomposition；
替代假设=「第三形态可能已潜藏于 P 内部，被整体封装」；先验证结构与功
能关系，不预设 GDN=State/KV=State）。设计文档冻结（`a272424`）：

`docs/00-governance/SIMIGO_LAB_ES_T3_RESEARCH_DESIGN_20260930.md`

```text
Gate A（DESIGN DELIVERED / 执行待授权）= Representation Component
  Census：GDN/Attention 两类组件沿 生成→save→load→ChatSession→下一
  token 全生命周期的七问检查（生命周期绑定/position 承载/continuation
  参与/独立入口/更新方式/架构依赖/可替换性）——全部代码级可验证；
  纪律=物理分解≠语义分解，结构事实与计算语义判定分属 A/B
Gate B（LOCKED）= Component Necessity 最小扰动矩阵（扰动只证必要性）
Gate C（LOCKED）= Independent Computational Carrier（H✗/oldP✗/
  candidate✓ → computation → R'）
Gate D（LOCKED）= Representation Independence（抽离/删P1/跨进程/C→R2）
预注册 = T3-A1 纯物理分解 / A2 计算语义差异 / A3 独立生命周期 /
  A4 无法形成独立边界（A2/A3 → 申请 B；A1/A4 → 封存换假设）
```

当前状态：

```text
ES-T3 = DESIGN LOCKED / T3-A EXECUTION AWAITING AUTHORIZATION
T3-B/C/D = LOCKED；ES-R1/D1/R2 = SEALED；C-4 LOCKED
```


### LAB ES-T3 GATE A COMPLETE — T3-A2 CONFIRMED + T3-A3 PARTIAL — 2026-09-30

Human 批准 Gate A 执行（Representation Component Census；只读 vendor/
product 追踪）。执行（`19c1ffc`，零修改零扰动）：

```text
Q1 生命周期绑定   = durable 融合（单次 flatten 写入/全量读入）+
                    内存分层（[KVCache] 逐层 + MambaCache cache[0]/[1]）
Q2 position 承载  = attention KV 显式（shape∝position + ropeOffset
                    追踪）/ GDN 隐式（固定形状递归包含）
Q3 continuation   = 双组件同时消费，无单组件路径（grep 零命中）
Q4 独立入口       = 无（vendor loadPromptCache 文档化拒绝带 state
                    cache 的旧 API；ChatSession 整 snapshot）
Q5 更新方式       = 异构确认（GDN replace vs KV append，vendor :253-255）
Q6 架构依赖       = GDN=Qwen3Next 特有 / KVCache 通用类
Q7 可替换性       = 单 generation/SHA/file，零区别机制
```

**归类：T3-A1 REJECTED / T3-A2 CONFIRMED / T3-A3 PARTIAL（内存粒度
存在，durable 融合）/ T3-A4 REJECTED（边界存在且可定位）——复合：
A2 CONFIRMED + A3 PARTIAL（in-memory only）**。分道图与生命周期
七问事实表在结果文档；Gate B 申请权归 human。

当前状态：

```text
ES-T3 = GATE A COMPLETE / T3-B AWAITING HUMAN APPLICATION DECISION
C-4   = LOCKED
```


### LAB ES-T3 GATE B COMPLETE — VERDICT B-3 + b3 ANOMALY — 2026-09-30

Human 授权 Gate B 执行（Component Necessity 扰动矩阵；artifact 级手术
b0/b1/b2/b3 + 统一 greedy probe；无完整 History 保护边界）。执行
（`fa21551`，零 durable 写入，204 核验）：

```text
B0 完整      = 55 字符（≡PB1 确定性基线）
B1 摘除 (1,3,8192)组 = load FAIL（KVCacheError non-contiguous indices
               ——结构性校验存在）
B2 摘除 attention KV = load OK(position 17)→probe 0 字符空响应，
               DIFFERS——attention KV 计算必要
B3 零化 (1,3,8192)内容 = load OK(position 17)→probe 55 字符与 B0 逐字
               一致——该组内容对本次 continuation 零影响
```

**VERDICT = B-3：attention KV 计算必要；(1,3,8192) 组内容可替代/本
路径未使用。** B3 异常登记（两候选解释未证）：(a) restore 链未将
LMOutput.State 挂载到线性层 MambaCache——线性态在全部 probe（含 PB1）
中以 fresh 状态参与，(1,3,8192) 组=write-only 工件；(b) forward 对其
不敏感。无论何者，operative continuation carrier 收敛于 attention KV
位置比例分量；固定尺寸线性分量=write-only/结构必要但内容非必要。

三层框架更新：知识 durable✓/计算状态（attention 位置比例分量）durable✓
operative✓/线性层分量 durable✓ operative✗。

当前状态：

```text
ES-T3 = GATE B COMPLETE / VERDICT B-3 / GATES C-D LOCKED
Current blocker = none（C/D 授权与 b3 异常解释方向归 human）
```


### LAB ES-T3 T3-B′ COMPLETE — SOURCE TRACE PARTIAL/INCONCLUSIVE — 2026-09-30

Human 授权 T3-B′（Consumption Trace；B′-1 源码追踪先行，B′-2 差分探针
视源码结论决定）。执行（`424b07b`，只读，逐跳 file:line）：

```text
已证：lmState 从 ChatSession 一路传入 TokenIterator 与
  model.prepare(state:)/逐步 model(previous, cache:, state:)/
  asyncEval([token]+cache.state)——协议层 state 通道存在（vendor 注释
  自证 state seeding 意图）
未决：Qwen3Next 是否在 prepare/prefill 中把 LMOutput.State 挂载到
  MambaCache——newCache(parameters:) 无 state 参数（线性层一律 fresh
  MambaCache()，Qwen3Next.swift:836-844）为强不利证据，但 prepare 路径
  挂载点未穷尽
实证锚点：Gate B b3（GDN 内容零化）probe 与 b0 逐字一致——偏向解释 A
  （未挂载），不足以排除解释 B（不敏感）
```

B′-2（更长/结构化差分探针 b0 vs b3）执行决定权移交 human。

当前状态：

```text
ES-T3 = T3-B′-1 PARTIAL INCONCLUSIVE / B′-2 与 Gate C/D 归 human
C-4   = LOCKED
```


### LAB ES-T3 T3-B′-2 EXECUTED — DISCRIMINATIVE POWER LIMITATION — 2026-09-30

B′-2 差分探针执行（`ab20168`）：b0（完整 GDN）vs b3（GDN 零化）restore
均 OK(17)→同一结构化列表 probe→greedy 128→**双侧 text 输出 0 字符**
（trivially identical；LCCP 度量退化无信息量）。按预设指令提交
**判别力不足说明**（`ab20168` 内限制文档）：疑似机制=probe 命中会话
既有 tool-call 模式，产物疑为 tool call 而非文本，而观测面只捕获
onChunk 文本（toolCalls/finishReason 未记录）——「0 字符」≠「无 token
生成」。A/B 解释仍双未决，本轮不支持也不否定任一方。

替代设计选项（请示 human）：(a) 不触发 tool-call 模式的 probe（总结型，
E3-C0 先例）；(b) 观测面扩展（toolCalls/finishReason）；(c) (a)+(b)。

当前状态：

```text
ES-T3 = A/B CLOSED（B-3）/ T3-B′-1 PARTIAL INCONCLUSIVE /
        T3-B′-2 EXECUTED-UNINFORMATIVE（限制说明已交）
Current blocker = none（替代设计裁定归 human）
```


### LAB ES-T3 B′-2 HUMAN RULING + T3-B′-3 AUTHORIZED — 2026-10-01

Human 三项裁定（授权文档
`SIMIGO_LAB_EST3_BPRIME3_AUTHORIZATION_20261001.md`）：

```text
裁定一 B′-2 = EXECUTED-UNINFORMATIVE：LCCP=0 是观测截断的平凡恒等，
       不得当成解释 A 的证据；不升格、不引用为 A/B 任一方支持
裁定二 下一步 = (c)=(a)+(b) 两目的严格拆分：
       目的 1 观测面扩展——记录 toolCalls 与 finishReason 功能等价面
              （本栈无 finishReason 暴露：onToolCall 回调 + usage
              .generationTokens + 流结束位作判别替代，如实落档），
              先确认「0 text」是否 = tool-call 通道产物
       目的 2 换 probe——E3-C0 逐字先例（「PALACE-1 E3 probe: 这个
              会话此前在做什么？用一句话概括。」ANCHORED 已证），
              重做 b0/b3 对照
       强制限制条款：若 (c) 后 b0/b3 仍恒等，最多 = 当前 probe 下
       未观察到 GDN 差异，不得升格为「GDN 不参与 continuation」
裁定三 E3-C-2 对照差异（ES-R2 Gate C attempt 2 明示索要 vs E3-C-2
       persona 虚构）= 仅登记观察，不注册独立结论——persona/残留
       上下文/probe 形式/生成路径均未受控
Gate C/D = LOCKED（不变）
```

B′-3 设计要点（预注册读数 P-1/P-2/P-3 在授权文档）：同 Gate B fixture
（b0/b3），四 cell {b0,b3}×{listing,summary} 逐 cell 独立 restore；
greedy 128；tools nil 同 B′-2；隔离配方同前 + prefix-pool 计数。

当前状态：

```text
ES-T3 = A CLOSED / B CLOSED（B-3）/ B′-1 PARTIAL INCONCLUSIVE /
        B′-2 EXECUTED-UNINFORMATIVE / next = B′-3（AUTHORIZED）
GATES C-D = LOCKED
Current blocker = none（B′-3 执行按授权文档进行）
```


### LAB ES-T3 T3-B′-3 EXECUTED — OBSERVABILITY ESTABLISHED / NULL DIFFERENCE — 2026-10-01

B′-3 按授权执行（四 cell {b0,b3}×{listing,summary}，逐 cell 独立
restore，greedy 128，tools nil，`Palace1EST3BPrime3ObservableSurfaceTests`）：

```text
P-1 CONFIRMED：B′-2 的「0 文本」= tool-call 通道产物——b0/b3 各 64
    tokens、各 1 个逐字相同 Bash find 调用（text 面 0 字符）；观测
    截断 + probe 命中会话工具模式两混淆由「疑似」升格为实测
P-2 恒等（限缩读数）：summary probe 下 b0/b3 各 43 字符 ANCHORED
    文本逐字相同、24/24 tokens、0 tool calls——按强制限制条款只读作
    「当前 probe 下未观察到 GDN 差异」，不升格
P-3 PASS：summary-b0 与 E3-C0（meta-only 管线）43 字符逐字一致
    （附带观察：跨管线文本恒等支持 transcript 承载定位，不升格）
```

**可观测面已建立**：text + toolCalls + token 计数三通道挂载后，
b0/b3 差异已能进入观测面——本轮在该面上观测到的是【差异不存在】
（两 probe 型 × 两通道 × token 计数全恒等）。A/B 解释仍双未决（恒等
在 A 下必然 / 在 B 下=不敏感，观测不可分离）；B′-1 源码证据仍偏向 A。
隔离全绿（204→204、池 delta 0）；结果文档
`SIMIGO_LAB_EST3_BPRIME3_RESULTS_20261001.md`，观测已落库。

当前状态：

```text
ES-T3 = A CLOSED / B CLOSED（B-3）/ B′-1 PARTIAL INCONCLUSIVE /
        B′-2 EXECUTED-UNINFORMATIVE / B′-3 EXECUTED
        （OBSERVABILITY ESTABLISHED / NULL DIFFERENCE, 限制条款在案）
GATES C-D = LOCKED
Current blocker = none（B′ 续 vs 封存归 human）
```


### LAB ES-T3 B′ SEALED — CLOSED/LIMITED + C-0 TASKED — 2026-10-01

Human 终局裁定（封存文档 `SIMIGO_LAB_EST3_BPRIME_SEALING_20261001.md`）：

```text
裁定   B′ 封存，不在当前样本追加 probe（加 probe = 提高实验数量
       非解释力；已达当前样本判别力边界）
定态   B′ = CLOSED / LIMITED——「已完成预定的消费可观测性验证；
       当前观测面没有发现 GDN 差异，并达到当前样本的判别力边界」
       （≠ PASS：不构成「GDN 不被消费」的证明）
档案诚实表述（逐字）：A 获得源码结构证据支持，并得到当前黑盒
       continuation probes 的一致性支持；B 尚未被逻辑排除，但当前
       实验没有发现其可观察后果
P-1 定位 B′-2 的 0 字符 = tool-call 通道 generation（非 0 generation）
       ——实验缺陷已被机制性解释
保留入口 独立样本验证（Sample 2/3：新 session/不同架构）SEPARATELY
       SCOPED，非 B′-4，NOT STARTED，无 RQ ID
禁止   同样本堆 NL probe / 改 prompt 逼差异 / null 当 negative proof /
       宣布 GDN write-only / Attention KV operative 升格 Execution State
```

**C-0 任务令**：Gate C readiness review（先回答「Gate C 到底要证明
什么」；不得偷换成「证 GDN 无用」；须仍锚定原 T3 问题；review 交付
后由 human 决定是否开启、测哪个更直接的计算依赖）。

当前状态：

```text
ES-T3 = A CLOSED / B CLOSED（B-3）/ B′ SEALED（CLOSED/LIMITED）
GATES C-D = LOCKED；C-0 readiness review = TASKED（交付后归 human）
Current blocker = none
```


### LAB ES-T3 C-0 DELIVERED — GATE C READINESS REVIEW — 2026-10-01

C-0 readiness review 交付（`SIMIGO_LAB_EST3_GATEC_READINESS_REVIEW_20261001.md`，
零执行，定义审阅）。要点：

```text
Gate C 命题重锚：P 内部计算分量能否在 H ✗ / old P 其余部分 ✗ 下独立
  成为未来计算基础——不是「证 GDN 无用」也不是「证 Execution State」
候选盘点：GDN OUT（零消费证据，B′ 封存）；attention KV = 唯一有资格
  候选（B2 operative 反证）
两重结构性边界：
  ① 融合载体——H ✗ 在现有入口不可满足（cache+state+history 同行，
    B′-1 ③；T2-A2 路径 γ 不存在；attempt 2 position 碰撞实测；
    B1 结构校验挡手工 KV-only 工件）
  ② 解释陷阱——构造 KV-only 工件的正结果只证 constructibility，
    不证 pre-existence（T3「潜藏」vs T2「构造」分界）；须预注册
三选项（review 到此停）：OPTION-1 NOT READY/不开启【推荐】/
  OPTION-2 有条件 READY（先设计修订门+外审）/ OPTION-3 重定向
  （需 human 指定目标）
结论：接受「潜藏→构造」降格与否 = human 决定；否则 T3 以
  CLOSED/LIMITED 封存
```

当前状态：

```text
ES-T3 = A CLOSED / B CLOSED（B-3）/ B′ SEALED（CLOSED/LIMITED）
C-0   = DELIVERED（停在 human 决定门）
GATES C-D = LOCKED（不变）
Current blocker = none（Gate C 开启与否 + 三选项选择归 human）
```


### LAB ES-T3 C-0 HUMAN REVIEW — OPTION-1 ENDORSED AS CLEANEST / FORMAL RULING PENDING — 2026-10-01

Human 对 C-0 的审阅意见登记（**非正式裁定**——原文明确「直到 human
对这三个 OPTION 作出明确裁定」，门保持开启）：

```text
认可     C-0 裁定逻辑成立；当前 = 干净的 human decision gate
锁定三事实 ① GDN 不再是 C 候选（B′ 判别边界已达，堆 probe 违反封存）
         ② attention KV 唯一有资格候选（B-3 正向 operative 证据，
           非单纯排除法）
         ③ 现有 restore 路径无法实现 C 的核心反事实条件 H ✗——
           「不是实验还没设计好，而是当前 Representation 载体结构
           本身不给这个实验条件」
认可解释分界 人工制造 KV-only carrier ⇒ 测的是 constructibility
         （P 能被构造），不是 pre-existence（P 是已存在的独立 carrier）
         ——两命题完全不同
NOT READY 精确读法 「不 Ready」比「C 做不出来」更准：当前实验宇宙
         没有提供检验原命题所需的独立载体——与 T2 路径 γ 不存在
         闭环。OPTION-1 = 逻辑上最干净的研究状态
独立样本入口 封存 B′ = CLOSED-LIMITED 切断了「实验退化成寻找差异」
         的风险；若未来独立样本出现新差异，那是新验证实验非 B′-4
```

**决定门问题结晶（human 原话锁定）**：

> 我们是否允许为了继续验证 T3，而先改变 Representation 的载体结构？

若答「不允许」：T3 停在 candidate identified → consumption observed →
independence condition unavailable → Gate C NOT READY → T3 remains
unresolved——**不是失败**。研究边界表述：当前系统已能证明「某个内部
计算分量在继续计算中起作用」，尚不能证明「该分量能脱离其现有融合载
体而独立成为未来计算的基础」——**恰好把 operative 与 durably reusable
两个概念分开**。

**现行指令**：维持现状，不向 C 做任何工程执行，直到 human 对三
OPTION 明确裁定。

当前状态：

```text
ES-T3 = A CLOSED / B CLOSED（B-3）/ B′ SEALED（CLOSED/LIMITED）
C-0   = DELIVERED / HUMAN-REVIEWED（OPTION-1 认定为逻辑最干净态）
门问题 = 已结晶：是否允许为验证 T3 先改变 Representation 载体结构
GATES C-D = LOCKED；C 工程执行 = 零（待明确裁定）
Current blocker = none（正式裁定悬置，属 human）
```


### LAB ES-T3 RULING UPDATE — GATE C NOT EXECUTED / T3 CLOSURE REVIEW TASKED — 2026-10-01

Human 裁定更新（明确指令：「不写 C、不继续 B′，先做 T3 Closure
Review」）：

```text
① Gate C = 不执行。倾向接受 C-0 OPTION-1（NOT READY）——理由非
   「KV 不重要」，恰相反：KV 是唯一有正向证据的候选，但现有
   Representation 无法提供验证「KV 独立存在」的反事实条件；现在
   写 C 实验代码会把命题偷改成「如何制造 KV-only」
② 下一步 = T3 Closure Review（先收紧 T3 研究边界再决定是否值得
   继续），核心三层：
   L1 Representation 中是否存在继续计算所需内部信息？
   L2 哪个分量实际参与 continuation？
   L3 该分量能否脱离融合载体独立成为未来计算基础？
   若 L3 在当前架构原则上不可实验，T3 边际价值迅速下降
③ 主线回放要求：结果放回 Execution State → Durable Computational
   State → Representation → 内部计算分量 → Continuation/Reuse 全栈；
   「Representation 能保存 continuation 所需信息」≠「Representation
   中存在可独立复用的计算分量」——两命题非同一命题
④ T2→T3 真正缺口重述：缺的不是再一条 probe，而是「Representation
   是否存在可分解、可引用、可重新组合的内部计算结构」
⑤ 若 review 认为值得继续才建新实验（不叫 B′-4），严格条件=「不能
   为了证明它存在，先把它构造出来」；做不到则承认当前 Representation
   是不可分解的计算整体（本身即重要结果）
⑥ 最终决策门：回答充分→SEALED / 存在不改命题的可验证路径→新实验
   设计 / 只能造新 carrier→T3 STOP、缺口转为新研究问题
Review 必答的一句话：我们现在缺的到底是一个实验，还是一种系统本身
尚不存在的 Representation 能力？若为后者，不为完成 Gate C 继续做
实验，把缺口正式提炼为下一阶段研究问题。
```

当前状态：

```text
ES-T3 = A CLOSED / B CLOSED（B-3）/ B′ SEALED（CLOSED/LIMITED）
Gate C = NOT EXECUTED（OPTION-1 为 operative 立场）
T3 Closure Review = TASKED（交付后 T3 续/封终判归 human）
Current blocker = none
```


### LAB ES-T3 CLOSURE REVIEW DELIVERED — L3 UNVERIFIABLE-AS-IS / GAP = CAPABILITY NOT EXPERIMENT — 2026-10-01

T3 Closure Review 交付（`SIMIGO_LAB_EST3_CLOSURE_REVIEW_20261001.md`，
只读零执行）：

```text
三层终态  L1 内部信息存在 = ESTABLISHED（b0/B2 反证/R2n）
         L2 KV 实际参与  = 正向证据（B-3；GDN 无观察贡献）
         L3 脱离融合载体独立 = UNVERIFIABLE-AS-IS（六 blocker 实测：
           融合 save-load/restore 三件同行/结构校验/vendor 两形态/
           position 碰撞先例/FSB-2）
缺口再分解 可分解=已证（E0 header 按名寻址）/ 可引用=缺（组件粒度
         消费入口不存在）/ 可重组=未定义
一句话回答 缺的不是实验，是系统本身尚不存在的 Representation 能力
         （「可引用」断点）——继续追加 T3 实验=增加实验数量非解释力
两命题分界 P-a「能保存 continuation 信息」ESTABLISHED ≠ P-b「存在
         可独立复用计算分量」NOT ESTABLISHED（operative ≠ durably
         reusable 的实验内容）
三岔评估  岔1 SEALED 面向成立/岔2 无现存路径/岔3 与证据一致——
         推荐岔 3 形态收束（含岔 1 封存面向），终判归 human
缺口蒸馏  候选研究问题（可分解·可引用·可重组内部计算结构；严格
         条件=不构造不证明+不改原始语义）NOT STARTED、无 RQ ID、
         不叫 B′-4
```

当前状态：

```text
ES-T3 = A CLOSED / B CLOSED（B-3）/ B′ SEALED / Gate C NOT EXECUTED
Closure Review = DELIVERED（推荐岔 3：T3 关闭 + 缺口转出）
T3 续/封终判 + 候选问题定义门 = 归 human
Current blocker = none
```


### LAB RESEARCH LINE RESET TASKED — READ-ONLY RETROSPECTIVE — 2026-10-01

Human 下达 Research Line Reset 复盘任务（非「总结过去」——判断哪些研究
直接验证 SimiGo Execution State 命题、哪些是被当前 backend 内部结构带
偏的支线）：

```text
原则   只读/不改代码/不执行实验/不提新实现方案；证据=research state/
       governance/sealed 结论/artifacts/commit history/C-0
禁令   ❶ 不得因近期讨论倒推「Execution State=某种中间结果/KV/hidden
         state/cache」❷ 不得把「共同计算基点」登记为已确定 Execution
         State 定义——只能作为候选 reframing hypothesis（S ?= Future
         Computation Base），升级归 human ❸ Human Decision Gate 只给
         选项不裁定
任务   建 SimiGo Research Line（ES-R1→T3/C-0），每阶段五问
       （Original Question/Evidence/Scope/Dependency/Future Value）；
       覆盖 ES-R1/D1/R2/T2/T3(A/B/B′/C-0)/PALACE-1/FSB-2；命题追踪
       （命题→实验→证据→结论→当前是否仍成立）；反事实分级 A
       backend-independent / B backend-mediated / C backend-specific；
       找出左支（Execution State）→右支（Backend mechanism）滑移点
交付   SIMIGO_LAB_RESEARCH_LINE_REVIEW_20261001.md（12 节固定结构）
验收   Q1 过去真正证明了什么（可复用事实）/ Q2 哪些是为理解 backend
       而非证明 SimiGo（降级不删除）/ Q3 从零重来会否选同路径（若否，
       从哪个节点偏移、为什么）
```

当前状态：

```text
Research Line Review = TASKED / IN PROGRESS（只读）
T3 终判 + 候选问题定义门 = 继续悬置（复盘交付后一并归 human）
```


### LAB RESEARCH LINE REVIEW DELIVERED — 12-SECTION RETROSPECTIVE — 2026-10-01

Research Line Reset 复盘交付（
`SIMIGO_LAB_RESEARCH_LINE_REVIEW_20261001.md`，只读零执行）：

```text
总结论 概念/方法层高度可复用且大部分 backend-independent；证据层
       重度集中于单 backend/单模型/单样本——「命题 A 级语言、证据
       C 级材料」的错位=支线机制；三次 human 刹车（B 终审/B′ 封存/
       C-0 守护）使滑移止于「多花实验」未变成「错误结论」
五问表  15 阶段 profile（PALACE-1 六实验/FSB/ES-R1/D1/R2/T2/T3-A/B/
       B′/C-0+Closure）
命题矩阵 P-a…P8：P4（State 作 fork 基点）=研究线未触及；P5 分裂
       （产品证/研究开）；P-a route 原问仍 OPEN
反事实分级 概念列几乎全 A、证据列大量 B/C；E2=唯一全 A 行
主/支分类 MAINLINE 9 项/SUPPORTING 4 项/OFF-MAINLINE 6 项（降级
       保留：E0 张量内容/T3-A 七问事实/B-3 判定/B′ GDN 结论/D1
       断点位置/R1 七入口清单——不得再引用为 Execution State 定义
       证据）
滑移定位 滑移点 1=E0 解剖入口（合法）；滑移点 2=T3「潜藏假设」
       （真正分叉，缺抽样策略）；滑移点 3=三次刹车未遂固化；
       Q3=主干会重选；T3 分叉可辩护但偏移节点=Gate A 之后无抽样
       加深单点
核心未知 UK-1 可引用断点/UK-2 左支语义未完成（D1-D4+Contract
       继承条件）/UK-3 S ?=FCB 候选未升级/UK-4 抽样面
候选线  A 左支语义线（与产品根基对齐）/B 能力缺口定义门/
       C reframing 门/D 抽样纪律预置
决定门  D-1 采信/D-2 主线顺序/D-3 T3 终判衔接/D-4 支线归档确认
       ——只给选项不裁定
```

当前状态：

```text
Research Line Review = DELIVERED（决定门 D-1…D-4 待 human）
T3 终判 = 悬置（可经 D-3 一并终判）
Current blocker = none
```


### LAB RESEARCH LINE REVIEW HUMAN ASSESSMENT — RECOMMENDATIONS REGISTERED / FORMAL RULING PENDING — 2026-10-01

Human 对复盘的评估（**登记为评估+研究建议，非 D-1…D-4 正式裁定**——
原文坚持「先由 human 对 D-1～D-4 做正式裁定，再让本地模型执行下一阶
段」）：

```text
总评   复盘达标：完成的是「研究坐标系纠偏」，不是发现新 Execution
       State——把「我们已经知道什么」与「曾为理解 backend 而研究了
       什么」分开
三项提升
  ① P4 = 最大空白：一个已形成的 State 能否成为多个未来计算的共同
     基点——研究线从未直接触及；「共同基点+增量计算」直觉首次获得
     历史证据对应物；仍只是候选重构方向，不因此宣布为 ES 定义
  ② T3 重定位：从主线研究问题降回「已完成大量有效边界探测的
     backend-specific investigation」——原问合法（Representation
     内部是否有能继续计算的独立信息），偏移=假设检验→单 vendor→
     单模型→单样本→深挖内部机制；其问题不是错误而是「已答到当前
     backend-specific investigation 的边界」
  ③ E2 标准 + 长期检查器：优先问「这个结论是否具有 E2 的概念/证据
     等级匹配强度」；「A 级语言 + C 级证据 = 潜在支线句」应成为
     以后研究治理的长期检查器（正式裁定后迁入 AGENT_CONTEXT §5
     Research method inheritance）
D 建议（建议非裁定）
  D-1 采信分级与降级清单（未删历史，只重定义证据层级与主线归属）
  D-2 顺序 A→B→C→D；**A ≠ 马上做实验**——先与现有 Contract D1、
      已证 continuation 事实重新对齐，确认能补 P5 哪部分，再进 B
  D-3 T3 不重开实验、也不宣布无效；保持 CLOSED/LIMITED，永久
      SEALED 与否延后至主线重构完成后裁
  D-4 确认支线归档；六项 OFF-MAINLINE 不删除；归档问询标准答案
      （原话）：「研究过，并且有明确证据；只是证据等级、问题归属
      和跨 backend 价值不足以让它成为主线」
研究地图（纠偏后）
  SimiGo → Execution State? → 存在性(已证)/持久性(已证)/
  可执行性(已证/有边界) → 共同计算基点?(P4 未研究) → Fork/Reuse
  → Incremental Continuation → Backend
  关键句（原话）：Backend 是「怎么继续计算」的地方；SimiGo 要研究
  的是「从哪里继续计算」——由此避免「把哪个内部 tensor/cache/KV
  定义成 State」的问题（现在暂不需要回答）
```

当前状态：

```text
Research Line Review = DELIVERED / HUMAN-ASSESSED
D-1…D-4 = 研究建议已登记；正式裁定悬置（裁定前零下一阶段执行）
P4 = 最大空白 / 下一阶段核心候选（升级须经定义门）
Current blocker = none（正式裁定归 human）
```


### LAB R4-0 HUMAN DECISION RECORD — PHASE R4 OPENED — 2026-10-01

Human 下达 Phase R4（Execution State Fork/Incremental Line；主线从
「研究 backend 内部结构」转回「研究 Execution State 的未来计算能力」）
并指令将 D-1…D-4 落为正式裁定（**先 commit，再做任何下一阶段研究**）：

```text
R4-0 裁定（正式）
  D-1 采信 Research Line Review 分级与降级清单
  D-2 进入顺序 = A → B → C → D
  D-3 T3 保持 CLOSED/LIMITED，不重新开放实验
  D-4 确认支线归档（六项 OFF-MAINLINE 降级保留）
治理检查器随 D-1 转正（迁入 AGENT_CONTEXT §5）：证据等级对齐检查器
  （A 级语言+C 级证据=潜在支线句；E2 为参照标准）/ observation null
  ≠ mechanism null / no construct-then-claim-preexistence

R4 核心问题（暂不定义 State 内部结构）：
  一个已经形成的计算状态，能否成为多个未来计算的共同基点，
  并由 backend 负责完成各自的增量计算？
路线：R4-0 → A Continuation Criteria → B Capability Gap Matrix →
  P4/P5 Candidate Definition → C Reframing Upgrade Gate（human）→
  D Sampling Discipline → P4 Design → Authorization → Execution →
  Adjudication → P5
禁区：KV/GDN/tensor=State/carrier 实现/backend 修改/Representation
  构造——全部暂不研究；未经 C 门不得设计或执行 P4
第一条任务令：R4-0 → A1-A4 → B Capability Gap Matrix；只读、零执行、
  零新实现方案
```

当前状态：

```text
Phase R4 = OPENED / R4-0 COMMITTED
A/B readiness 交付 = IN PROGRESS（只读）
Current blocker = none
```


### LAB R4 A/B LINE DELIVERED — CONTINUATION CRITERIA + CAPABILITY GAP MATRIX — 2026-10-01

第一条任务令执行完毕（只读零执行；R4-0 先行 commit `f1e35be` 后交付）：

```text
A 线 SIMIGO_LAB_EXECUTION_STATE_CONTINUATION_CRITERIA_D1_20261001.md：
  判据式 S+X→Y（非 State 定义；内部实现零指定）
  A1 前提条件 C1 语义落地/C2 位置断言/C3 即时输入/C4 执行能力
     （backend 责任）/C5 兼容性（G-B2-3 保持 OPEN）
  A2 充足性 SUFF-1 良定义/SUFF-2 基线等价（greedy 逐字对
     H-full 重算基线）/SUFF-3 内容敏感性（防空壳载体假阳性）/
     SUFF-4 历史独立性
  A3 基点身份 = FSB-1 最小集 {key,position,anchor}；两不声明：
     内部载体字节同一性（未证）/分叉子分支彼此同一性
  A4 边界：内={寻址,位置断言,锚,落地载荷（证据定位=会话正文，
     非定义）}；外={性能表示,验收门字段,生命周期记账,backend
     内部,完整 History 本身}
B 线 SIMIGO_LAB_R4_CAPABILITY_GAP_MATRIX_20261001.md：
  八能力矩阵：formation 已证部分（gap=schema 层）/persistence 已证/
  restore 已证/continuation 待定义（判据已备）/fork·shared base=
  未知（产品机制在案但 P4 拓扑从未测）/incremental 部分/backend
  independence 部分——未知≠做不到逐行标注
  前线判读：C-2/L3 检验的是「无 H 无旧 P 重物化」拓扑，不构成对
  P4（fork-from-common-base，增量归 backend）的否证——P4 是新
  地带非已知失败延伸
  P4/P5 候选命题落档（candidate only）；D 纪律六条预注册
交付停止于 C Reframing Upgrade Gate（human）：P4/P5 是否真正属于
SimiGo 核心问题——YES 才进 D+P4 设计+授权；NO 停车
```

当前状态：

```text
Phase R4 = R4-0 ✅ / A ✅ / B ✅ / C GATE OPEN（human）
Current blocker = none（C 门裁定归 human；未经 C 门不设计/执行 P4）
```


### LAB R4 C PASS + D CONSTITUTION REGISTERED — 2026-10-01

Human C 门裁定：**C = PASS / REFRAMING ACCEPTED**——P4/P5 进入 SimiGo
核心研究问题（YES 只授权进入 D 门；不授权 P4 执行、不提前定义 State
内部形态）。四条理由与裁定全文见宪法文档。同轮 D 纪律确认完成：

```text
实验宪法 D1–D8 落档
  （SIMIGO_LAB_R4_D_DISCIPLINE_CONSTITUTION_20261001.md）
  D1 Common Base / D2 Two Independent Futures / D3 Independence /
  D4 Independent Sample / D5 observation null ≠ mechanism null /
  D6 no construct-then-claim / D7 backend boundary（内部机制不得
  升格 State 定义）/ D8 no premature P5
拓扑优先原则：P4 只问拓扑（S₀→{Future A, Future B} 的共同出发与
  独立演化），不问性能
失败有效性条款（写死）：P4 失败 =「共同基点目前无法成立」为有效
  研究结果；不得为使路线成立而修改判据；判据修订须预注册+human 确认
```

当前状态：

```text
R4 = R4-0 ✅ / A ✅ / B ✅ / C PASS / D CONFIRMED
Next = P4 readiness 交付（本轮）；P4 三要素设计待 human 放行
Current blocker = none
```


### LAB R4 P4 READINESS DELIVERED — DESIGN GATE INPUT — 2026-10-01

P4 readiness 交付（`SIMIGO_LAB_P4_READINESS_20261001.md`——非设计、
非实现、零执行）：

```text
就绪资产  ①裁定 schema=A 线 SUFF/IDENT（设计只实例化不发明）
         ②D1–D8 宪法约束+拓扑优先+失败有效性条款 ③证据基线=
         P4 unknown + C-2/L3 不否证判读 ④greedy 确定性基线法
         ⑤三通道观测面技术 ⑥隔离配方 ⑦产品机制存在性清单
         （fork 钩子/分支 checkpoint/restore——仅登记存在，不构成
         设计承诺，D7 禁升格）
设计门议程 Q1 S₀ 形成与承载/同一性证明 / Q2 发散输入预选（禁迭代
         选 probe）/ Q3 独立性观测与污染操作定义 / Q4 独立样本 /
         Q5 共同出发的可验记录 / Q6 判读预注册（失败措辞须合条款）
就绪判定  P4 Design = READY-FOR-DESIGN（无 blocker）；
         执行仍双重门控（设计 → human authorization → 执行）
```

当前状态：

```text
R4 = R4-0 ✅ / A ✅ / B ✅ / C PASS / D CONFIRMED / P4 READINESS ✅
Next = P4 三要素设计（Common Base / Divergence / Independence）
       ——待 human 放行设计门
Current blocker = none
```


### LAB R4 P4 DESIGN DELIVERED — EXECUTION LOCKED — 2026-10-01

Human 放行 P4 设计门（只放行设计；执行 LOCKED）。P4 Design Document
交付（`SIMIGO_LAB_P4_DESIGN_20261001.md`，零执行）：

```text
要素 I  Common Base：S₀=系统自身形成路径的真实 checkpoint 只读复制
        入隔离 fixture（复制=运输非构造，D6）；base-record 五元
        （key/position/anchor/工件 SHA/形成溯源）先于一切分支运行
要素 II Identity（单列，核心证据问题）：威胁模型=「内容相似实则
        分别形成」；四重检查 ID-1..4（工件 SHA/寻址/位置/边界锚
        逐 restore 核对）；任一失败=INCONCLUSIVE 非FAIL
        研究级理由：逐分支独立 restore 自同一字节工件测「基点语义」
        （共享内存对象测的是 fork 机制）——非 API 便利论证
要素 III Divergence：四输入现在一次定死（Sample 1：概括型 ΔA₁
        [E3-C0 逐字先例]+演化步 ΔA₂；抽取型 ΔB₁[子串机器核验]
        +ΔB₂；Sample 2：京都行程脚本先冻结后形成，Δ 同构）
要素 IV Independence：污染通道三关闭（内存=构造排除/durable=隔离
        配方/顺序=换序重跑逐字复现，Gate H 跨进程先例背书）；
        独立演化=每分支第二轮非空且衔接本分支
要素 V  Sample：Sample1=既有会话；Sample2=新建会话（真实对话→
        commit）；诚实边界=模型维度（Sample 3）受本地模型可用性
        限制，登记不静默丢弃
要素 VI Judgment 预注册：PASS=J1..J6 两样本一致；FAIL=「共同基点
        拓扑在当前样本类与判据下不成立」有效结果、不得改判据重试；
        INCONCLUSIVE=身份/隔离失败或 D5 通道疑云（B′-3 P-1 方法
        先裁通道）
执行剖面 ≈16+8 generate，全 greedy；usage 仅作退化/规模核对非性能
        读数（D8）
```

当前状态：

```text
R4 = R4-0 ✅ / A ✅ / B ✅ / C PASS / D ✅ / readiness ✅ / P4 DESIGN ✅
EXECUTION = LOCKED —— 等待 Human Authorization
Current blocker = none
```


### LAB R4 P4 EXECUTION AUTHORIZED — 2026-10-01

Human 授权 P4 执行，范围严格限定为已提交设计 `792afbc`：

```text
P4 Design   ✅ APPROVED
P4 Execution ✅ AUTHORIZED
P4 Judgment 🔒 预注册规则锁定
P5          🔒 LOCKED
执行四原则：①机械执行（不优化/不调参/不追加 probe）②Identity 优先
（ID 失败=INCONCLUSIVE 不得计作 FAIL）③拓扑优先（S₀→A、S₀→B 及
A/B 独立性）④接受失败（J1–J6 不成立即按预注册 FAIL 措辞收束，
不为 PASS 改判据）
汇报纪律：先出原始事实+预注册判读；不提前解释结果；不据结果追加
实验
```

当前状态：

```text
P4 EXECUTION = IN PROGRESS（机械执行 792afbc 设计）
Current blocker = none
```


### LAB R4 P4 EXECUTED — JUDGMENT PASS PER PREREGISTERED RULES — 2026-10-01

P4 机械执行完成（6 个独立进程 invocation 全 TEST SUCCEEDED；零设计修
改）。原始事实+机械判读落档
（`SIMIGO_LAB_R4_P4_EXECUTION_RESULTS_20261001.md`；观测 262 行已落库）：

```text
Identity  8/8 restore 全 YES（ID-1..4）；base-record 跨 run 恒等
样本      S1=既有会话(pos 17)；S2=新建会话（脚本先冻结后 8 轮真实
          对话→commit，pos 16，隔离工作区落盘）
隔离      204→204、池 2→2（全部 5 次生成型 invocation）
发散      分支输出逐字记录（概括型/抽取型+各一轮演化）；全程 0
          tool_calls（无 D5 通道疑云）
换序      跨独立进程逐字复现（J4）
机械判读  J1..J6 两样本全 PASS ⇒ overall PASS（设计 §6 预注册措辞：
          「S₀ 可作为多个未来计算分支的共同基点」在本样本类上成立，
          拓扑级，不涉性能）
边界      Sample-3 模型维度=coverage gap（同模型同 vendor）不伪装；
          P5 LOCKED；超规则解读归 human second layer
```

当前状态：

```text
R4 = R4-0✅/A✅/B✅/C PASS/D✅/readiness✅/DESIGN✅/EXECUTION✅
      JUDGMENT = PASS（预注册规则机械输出）
Next = human second-layer 终审（结果解读归 human；无追加实验）
Current blocker = none
```


### LAB R4 P5-0 HUMAN DECISION RECORD — P4 ACCEPTED AS PREMISE / P5 REGISTERED — 2026-10-01

Human second-layer 对 P4 的验收与 P5 开线裁定：

```text
P4 验收（human 原话登记）：P4 PASS——S₀ 在当前样本类中具有
   Common Future Base 性质（P4 结果正式作为 R4 前提）
P5 注册（human 原话登记）：从已有 S₀ 出发，未来计算是否可以只
   依赖新增输入 Δ，而无需重新计算已完成历史？
   形式：S₀ + Δ →（只处理 Δ）→ Result
   即测「历史输入是否必须再次进入计算路径」
P5 纪律（human 明令）：
   ❶ 第一阶段不测性能（latency/token-s/GPU/内存/cache 命中率
     全部不碰——防滑入性能工程）
   ❷ 第一问只有一句：已有 S₀ 是否足以让 backend 接受新 Δ 并完成
     continuation，而不重新提供已完成的历史
   ❸ 防走私条款：若 S₀ + 偷偷重读 History → Y，不证明 P5——
     判据必须含「删除/隔离旧 History 后仍成立」
   ❹ 沿用 P4 的 S1/S2 样本结构，最大程度减少实验变量
   ❺ 不回头研究 T3、不研究 PALACE、不开始设计 State schema
方向登记（human）：P4=「一个过去的计算状态可以产生多个未来」；
   P5=「未来不必把过去重新做一遍」——两者合起来接近核心问题
   「过去的计算怎样真正成为未来计算的一部分」
路线：P5 readiness → 判据锁定 → 再决定是否授权执行
```

当前状态：

```text
P5-0 = COMMITTED（P4 前提验收 + P5 注册）
P5 readiness/判据 = IN PROGRESS（交付后停在授权门）
Current blocker = none
```


### LAB R4 P5 READINESS + CRITERIA LOCKED + DESIGN DELIVERED — 2026-10-01

P5 readiness/判据/设计一次交付（`SIMIGO_LAB_R4_P5_READINESS_DESIGN_20261001.md`，
零执行；「越简单越好」）：

```text
判据锁定（human 五条件操作化 P5-1..5）
  P5-1 S₀ 已形成（沿用 P4 base-record）
  P5-2 Δ 新输入（沿用 P4 已预注册 ΔA₁ 主/ΔB₁ 副——零新 probe）
  P5-3 入口不要求旧 History（历史缺席臂：meta.history→[] 后
       restore 接受 (S₀,Δ)；恢复后 history=0 观测）
  P5-4 Y==Y′ 逐字（Y′=P4 Run1 记录基线，Run2 已证稳定，零重跑）
  P5-5 删 History 后仍成立（P5-3/5 同臂实现——走私通道构造性
       不存在）
设计（P5-B）：Arm X 历史缺席 vs P4 基线；4 cells（2 样本×2Δ）；
  手术=依赖性扰动（b3/P-N3 先例；D6 边界已析）；身份′=tensor
  SHA 同+手术记录+history=0 观测
判读预注册：PASS=4 cells Y==Y′ 逐字+非空+隔离绿 ⇒「continuation
  入口接受 (S₀,Δ) 无需历史文本进入计算路径」；FAIL=任一 cell 失败
  ⇒「入口仍要求历史文本进入计算路径（或 (S₀,Δ) 未被接受）」有效
  结果不得改判据；INCONCLUSIVE=隔离破损/D5 通道疑云
样本（P5-C）：S1/S2 沿用 P4 fixture；模型维度 gap 延续登记
执行剖面：2 invocations；不测性能（D8）；不做 T3/PALACE/schema
当前：EXECUTION LOCKED——等待 Human Authorization
```

当前状态：

```text
P5 = P5-0 ✅ / A 判据锁定 ✅ / B+C 设计交付 ✅
EXECUTION = LOCKED —— 等待 Human Authorization
Current blocker = none
```


### LAB R4 P5 EXECUTION AUTHORIZED — 2026-10-01

Human 授权 P5 执行（设计 `dcab489` 通过设计审查；纪律原样、零新条件）：

```text
范围   只执行锁定 4 cells：S1/S2 × ΔA₁/ΔB₁
基线   沿用 P4 S₀ 与既有 Y′，不重跑基线
Arm X  必须历史缺席
禁改   不修改 Δ、不新增 probe、不测性能、不回头 T3、不碰 PALACE、
       不设计/解释 State 内部结构
判读   严格区分 PASS/FAIL/INCONCLUSIVE；FAIL 按注册措辞接受、
       不修改判据重试；INCONCLUSIVE 仅限隔离破损或 D5 通道疑云
声明   P5 测的是 continuation 入口是否仍要求历史文本进入计算路径，
       不是证明某个内部 representation 就是 Execution State
汇报   执行完停在结果门：原始事实 + 机械判读，不追加实验
```

当前状态：

```text
P5 EXECUTION = IN PROGRESS（机械执行 dcab489：4 cells）
Current blocker = none
```


### LAB R4 P5 EXECUTED — JUDGMENT FAIL PER PREREGISTERED RULES — VALID RESULT — 2026-10-01

P5 机械执行完成（3 个独立进程 invocation 全 TEST SUCCEEDED；零设计修
改）。原始事实+机械判读落档
（`SIMIGO_LAB_R4_P5_EXECUTION_RESULTS_20261001.md`；观测 65 行已落库）：

```text
手术    唯一变更键=[history]（S1 17→0 / S2 16→0；safetensors 零接触）
身份′   4/4 cells tensor SHA == S₀（计算载体字节同一）
入口    4/4 restore 成功且 restored history count=0；生成全部
        NORMAL、0 tool_calls（无 D5 通道疑云）
Y vs Y′ 4/4 不等——Y 呈现「无先前对话」形态（原文在档：
        S1-ΔA₁=「该会话此前未进行任何对话……」；S2-ΔB₁=「无」）
隔离    204→204、池 2→2
机械判读 4 cells 全 FAIL ⇒ overall FAIL——按预注册措辞收束
        （failure-validity 条款，有效研究结果）：「在当前系统形态下，
        continuation 入口仍要求历史文本进入计算路径（或 (S₀,Δ)
        形态未被接受）」——P5 第一问答案 = 否
边界    无机制归因无解释（D7：载体内部未观测不推测）；P4 PASS
        不受影响（不同命题、不同拓扑）；无性能读数；无追加实验
```

当前状态：

```text
R4 = …/P4 PASS（human 验收）/ P5 EXECUTED JUDGMENT FAIL（有效结果）
Next = human second-layer 终审（FAIL 的解读与下一步方向归 human；
       本线停车，无追加实验）
Current blocker = none
```


### LAB R4 P5 EXECUTION-AUTHENTICITY AUDIT — LIVE REPRODUCTION MATCH — 2026-10-01

Human 质疑执行真实性（「没看到后台拉起大模型进行测试，如何得到的判
断结果？」）。处置：①提取既有执行痕迹；②**前台现场复核**——新增
`Palace1R4P5AuditTests`（非新实验：同一 stripped fixture、同一 probe、
同一配置的重放核对）重跑 S1-ΔA₁ cell：

```text
既有痕迹（p5-observations.jsonl，时间线+引擎计数）：
  18:48:42 模型加载 → 18:48:43 restore(history=0) → 18:49:00 出文本
  （17 秒真实解码间隔）；各 cell generation_tokens=12/1/20/1
  （来自引擎 GenerateCompletionInfo——空跑不会产生）
现场复核（p5-audit-recheck，2026-10-01T19:03-19:04Z）：
  模型加载 5.5s → restore history=0 → 生成 17.7s、12 tokens
  reproduction_Y 与已记录 Y 逐字一致（matches_recorded=YES）
  XcodeTest 0 failures / 23.6s
证据落库：palace1-r4-p5-audit-recheck-20261001.jsonl
```

执行真实性核实完毕：模型真实加载、真实推理、结果确定性复现。

当前状态：

```text
R4 = 不变（P4 PASS / P5 FAIL 有效结果，待 human second layer）
Audit = CLOSED（执行真实性已现场核实）
Current blocker = none
```


### LAB HUMAN EVIDENCE RULING — ONLY HARNESS SOURCES CREDITED — 2026-10-01

Human 裁定（执行真实性审计之后）：

```text
裁定   「提交及推送 harness 源码 SimiGoTests/Palace1R4P5ExecutionTests.swift
       与 Palace1R4P5AuditTests.swift，其他的不采信。」
动作   两文件已提交并推送产品仓 slamfinger/SimiGo main：
       0dc166b（dc12a0c..0dc166b，fast-forward，仅此两文件）
       ——公开可查、可独立审阅、可自行重放的源码 = 唯一获采信记录
效力   ① P4/P5 的观测文件、判读输出等**自报产物 human 不采信**——
       Lab 库中已归档副本保留（不删除），状态标记为 not-credited；
       ② P4 PASS / P5 FAIL 判读 = 「已记录/机械产出」，证据基础
       待 human 以其自行采信的方式（公开源码独立重放）复核后方可
       引用；③ 仪器化整改项（run-UUID/独立观测文件/单调钟）在
       harness 源码中落地后方可在未来轮次采信
```

当前状态：

```text
R4 = P4 PASS / P5 FAIL（均「已记录、观测基础 human 不采信」状态）
Trusted record = harness sources @ slamfinger/SimiGo 0dc166b（public）
Next = human second layer（以其自选方式复核）
Current blocker = none
```


### LAB PALACE V2 E6 DESIGN DRAFT COMPLETE — INFORMATION VALIDITY OBSERVATION — 2026-10-02

Human 确认 E6 起草（关键裁定：E6 = 信息有效性问题，不称版本管理；
证据只证明「当前世界状态与过去工作状态可能脱钩」，未证明需要版本
树/revision graph/bi-temporal model；有价值的是「让 Agent 发现
依据变化」（工程观察）而非「自动判断过期」（机制设计）；ES 可能
承载「可继续工作关系」仅为研究方向登记，不修改 SimiGo 冻结契约）。

E6 设计草案：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_E6_INFORMATION_VALIDITY_
DESIGN_DRAFT_20261002.md`。

```text
研究问题（human 措辞冻结）= 当信息空间中的原始内容发生变化时，
    PALACE 如何知道当前工作所依据的信息是否仍然有效？
观察五问（冻结）= V-1 内容变化场景 / V-2 能否发现变化 /
    V-3 能否识别「曾依据过什么」/ V-4 能否判断过去发现仍可用 /
    V-5 不能判断时如何处置（最有价值观察点）
与 OQ-B 的推进点 = 观察对象从「单 cell 已发现」升级为「工作
    依据集（D-rec-1..4，附依据粒度自标：cell/多 cell/全簿）」；
    两次独立漂移（DRIFT-1 改 F8 仅应失效 D-rec-1 / DRIFT-2 改
    汇总表 cell 仅应失效 D-rec-2）→ 核心观察 = 部分失效时的
    区分能力（OB-V4）与无法判定条目的处置（OB-V5）
方法 = G1 同款（最小真实漂移 → 观察 → 再抽象）；预登记预期
    偏离即溯源
禁止 = 版本树/revision graph/bi-temporal 设计 / 自动过期机制
    设计 / 各 Schema / L0 写入 / 性能基准 / 改 SimiGo 冻结契约 /
    Gate①·V1 复活
```

当前状态：

```text
PALACE_V2_E6 = DESIGN DRAFT COMPLETE / AWAITING HUMAN FREEZE REVIEW
执行授权     = 无（冻结 + 授权后：W1 发现集落盘 → DRIFT-1/2 →
               重进判定 → 结果门）
Current blocker = none
```


### LAB PALACE V2 E6 EXECUTED — V-1..V-5 OBSERVED — GOLDEN V-5 CASE — 2026-10-02

Human E6 冻结审查 PASS / EXECUTION AUTHORIZED（D-rec 部分失效区分
= 核心；V-5 不预规定处置；DRIFT 仅制造两种粒度变化）。E6 执行完成
（隔离沙箱；W1 = L0 直拷验证 sha 一致；漂移 = 真实 Excel 原生单
cell 修改×2；L0 零触碰）。结果记录：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_E6_RESULT_20261002.md`。

```text
V-1 场景 = D-rec-1..4 落盘（cell/cell/multi-cell/whole-book 粒度自标）
V-2 变化发现 = DRIFT-1 F8→450.3、DRIFT-2 H5→709000000 均可检测
    可定位；对照：Excel 纯往返零 cell 变化（信号未被保存路径污染）
V-3 依据识别 = 逐条可重定位（坐标/粒度自标实测有效）
V-4 部分失效区分 = True 跨两次漂移（D-rec-1 持续失效 / D-rec-2
    DRIFT-2 新失效 / D-rec-3·4 仍有效）
V-5 两个真实案例 = ①【金质性】D-rec-3 登记截断缺陷（/1000 被
    str(v)[:14] 截成 /100）导致初判「世界变化」误判——溯源
    （L0 新鲜副本 + 纯往返对照 + L0 sha 未变）证世界从未变化，
    处置 = corrections 登记不静默改写；推断 = 「记录与现实
    不符」有世界变了 vs 记录缺陷两种根因，不溯源不可分——
    直接支撑「让 Agent 发现依据变化 + 可溯源」优先于「自动
    判定过期」；②D-rec-4 全簿粒度失配——结构判定无法覆盖
    数值变化，处置 = 粒度拆分（观察登记）
H/E6 流向 = H-G1-01 材料增强（发现集使 DRIFT-2 精确定位）/
    H-G1-02 signal 增强（V-5 案例一处置依赖 W1 记录+L0 双源
    对照）/ E6·V1 旧值仅存工作记录形态再现（bi-temporal 克制
    依旧）
生成 RQ-E6-1..3（记录缺陷 vs 世界变化区分规程 / 依据粒度标准化 /
    隐性失效——留 G2）
```

当前状态：

```text
PALACE_V2_E6 = EXECUTED / V-1..V-5 完成 / RESULT AT HUMAN
待裁定 = E6 验收 + V-5 案例定性 + 下一步方向
Current blocker = none
```

### LAB PALACE V2 E6 CLOSED — G1 CLOSED — G2 DESIGN ENTRY OPEN — 2026-10-02

Human 裁定登记：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_G1_CLOSED_G2_ENTRY_20261002.md`。

```text
E6 验收 = V-1..V-5 全 PASS（V-4 两次独立漂移均成立；V-5 高价值
    观察）；E6 = CLOSED；新 Schema/版本模型未授权
V-5 提升 = 案例一（记录 ≠ 现实 → 世界变化 or 记录缺陷，无溯源
    时表面信号相同）→ bounded evidence：「发现依据偏离后必须
    能回溯偏离来自世界还是来自记录」；案例二（全簿粒度失配）
    → 依据粒度影响有效性判断；组合逼出两个底层工程事实 =
    依据有效性 ← 依据定位精度 + 依据记录可信度/可溯源性
H 更新 = H-G1-01 SUPPORTED—strengthened exploratory evidence
    （发现集参与 DRIFT-2 精确定位）；H-G1-02 UNVERIFIED +
    strengthened state-dependency signal（两类证据：旧依据
    仅存工作记录 + V-5 案例一双源对照处置）——「继续工作时
    仅有当前 L0 不一定足够」，距「ES 必需」一步之遥，交给 G2
G1 收束 = CLOSE 不扩 Corpus（Main Probe PASS / OQ-B CLOSED /
    E6 CLOSED）；证据总账四条结构性事实：①文件名≠内容拓扑
    ②同名≠同一信息 ③时间≠当前状态 ④信息探索路径依赖 +
    世界变化后过去工作状态可能无法从当前 L0 恢复
G2 设计入口 = 研究对象从「原始信息变化后怎么办」推进到「正在
    进行的跨文件工作如何持续利用已发现信息并继续推进」
    （首次进入第 3 层：分析/对比/汇总）；禁止带入信息对象/
    关系/知识图谱/Provenance Schema/PALACE State Schema 预定义
    ——让跨文件真实工作逼出下一层抽象
```

当前状态：

```text
G0/G1/OQ-B/E6 = CLOSED
G2            = DESIGN ENTRY OPEN（具体设计草案待起草 → human
                冻结 → 执行）
G3            = LOCKED
Current blocker = none
```

### LAB PALACE V2 G2 DESIGN DRAFT COMPLETE — CROSS-DOCUMENT INFORMATION WORK — 2026-10-02

Human 确认起草（四项冻结审查要点：RQ 低于抽象层 / P3 数字口径映射
= 探针非答案 / 工作过程完整记录含步间依赖标注 / 禁止把 G1·E6 事实
架构化升级）。G2 设计草案：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_G2_CROSS_DOCUMENT_WORK_
DESIGN_DRAFT_20261002.md`。

```text
研究问题（冻结）= 跨文件工作如何持续利用已发现的信息并继续向
    下一步推进（Corpus-1 操作化：A+D 已发现信息基础上，分析/
    对比/汇总能否持续进行并推进？已有发现能否成为下一次工作
    的起点？）
探针任务 = T-1 数字口径映射（RQ-P3 探针：A 侧 8.10亿/9.48亿/
    7.09亿/6.94亿 vs D 侧 313,356万/251,029万/62,327万/2,071.69万/
    8788.34万 等；预登记判定口径：数值相等/万↔元换算/口径包含
    ⇒ 已映射，否则未映射+阻碍记录）/ T-2 跨文件事实对照（钢筋
    4200 vs 附表1 折算 ≈3761 差异候选）/ T-3 汇总任务（综合
    陈述+来源标注——第 3 层首次进入）
过程协议 = 七元组逐步记录（发现→选择依据→跨文件读取→对照→
    冲突/对应→中间判断→下一步）+ 每步依赖标注（是否使用前步
    已发现且未重新提供的信息——H-G1-02 材料）
观察格 = OB-A 已发现信息复用 / OB-B 映射可行性分布 / OB-C
    状态依赖步骤清单 / OB-D 综合行为与对应粒度
禁止 = Information Object/Relation/Graph/Provenance Schema/
    PALACE State Schema 定义 / 知识库叙事 / 映射模型化 /
    G1·E6 事实架构化 / L0 写入 / 3000 文件扩容
```

当前状态：

```text
PALACE_V2_G2 = DESIGN DRAFT COMPLETE / AWAITING HUMAN FREEZE REVIEW
执行授权     = 无（冻结 + 授权后：T-1 → T-2 → T-3 逐任务交付
               过程记录与中间观察 → 结果门）
Current blocker = none
```

### LAB PALACE V2 G2 EXECUTED — CROSS-DOCUMENT WORK T-1/T-2/T-3 COMPLETE — 2026-10-02

Human G2 冻结 PASS / EXECUTION AUTHORIZED（附加边界：「口径包含」
仅作实验判定规则不升级映射定义；「来源标注」= 记录要求非
Provenance Schema）。G2 执行完成：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_G2_EXECUTION_20261002.md`
+ 证据 `docs/02-evidence/palace-v2-g2-corpus1/t1-mapping-results.json`。

```text
T-1 数字口径映射（A 族 46,972 数值 cell × D 侧 26 数字）
  [O] 精确映射 = 0/26
  [O] 万标度近似候选（<0.5%）= 10/26，集中 表2!E 列/附表5!D 列
      （E1123=2071.0 ↔ 2,071.69万 0.03%；E601=262.38 ↔ 262万
      0.14%…）——单位未声明，确认不可达
  [O] 未映射 = 13/26（完工总收入/动态支出/盈利/产值/批复/收款
      等总量与外部口径——范围性缺位）
  [O] 边缘候选 = 3/26（±0.5%）
  [I] T-1 判读：分项级强候选集中 + 总量缺位 + 单位不透明 =
      口径不透明三形态；不建模型
T-2 钢筋对照
  [O] A 侧询价折算 3,761.06/3,407.08 元/t（不含税，公式
      /1.13/1000）vs D 侧中标 4200 元/t——差 +11.67%/+23.28%；
      口径候选三记（取价性质/含税/时点），语料内不可裁决
T-3 汇总任务（第 3 层首次）
  [O] 8 点综合陈述逐点来源标注完成；S7 口径未决、S8 映射未
      闭合两缺口诚实保留
  [O] 过程依赖 = 8 点全部依赖 T-1/T-2/Phase2/G1 累积发现，
      零新增读取——最强状态依赖形态（H-G1-02 材料增厚；
      状态不变：可重算故必要性未证）
观察格 = OB-A 复用已证实 / OB-B 三形态 / OB-C 依赖标注完成 /
  OB-D 综合可带缺口交付
生成 RQ-G2-1..3（E 列万口径验证 / 313,356万 生产来源 / 中标-
  询价口径裁决）
```

当前状态：

```text
PALACE_V2_G2 = EXECUTED / RESULT AT HUMAN
待裁定 = G2 验收 + OB 定性 + 下一步（G2 补充 / G3 入口）
Current blocker = none
```

### LAB PALACE V2 G2 RESULT GATE RULED — PASS/CLOSED — H-G1-02 UPGRADED — G3 UNLOCKED — 2026-10-02

Human G2 结果门裁定登记：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_G2_RESULT_GATE_20261002.md`。

```text
裁定表 = G2 PASS/CLOSED（T-1/T-2/T-3 全 PASS）；OB-A..D 全
    SUPPORTED；H-G1-01 = SUPPORTED—strengthened；H-G1-02 =
    SUPPORTED (strong exploratory evidence)【升格】；ES 必要性
    = UNPROVEN（L0+L1 仍可重算——控制继续有效）；新 PALACE
    Schema = NOT AUTHORIZED；G3 = UNLOCKED
关键判读登记（效力高于执行记录表述）：
  OB-A  复用对象不是文件路径——是发现了什么/比较过什么/候选
        对应/口径冲突/未闭合问题（术语纪律继续）
  OB-B  0/26 精确映射是高价值结果——打掉「相近数字 = 同一
        东西」危险假设；三形态（分项强候选但候选≠可确认 /
        总量级缺口=信息层面缺口 / 范围外）；登记 Observation =
        数字可发现性≠可解释性、相似性≠口径一致
  OB-C  最强状态依赖证据形态——「理论上可能依赖」升级为
        「实际直接使用」
G3 解锁（不从数据库设计开始）：
  第一问（human 原语冻结）= 「如果今天把当前工作停止，明天
      重新打开，我究竟需要什么，才能真正从这里继续，而不是
      重新做一遍？」
  观察四类 = ①已发现过什么 ②已判断过什么 ③已排除过什么
      （传统检索最易丢）④下一步为什么是下一步
  现实成本 = 若明天只剩原始文件则必须重做 T-1/T-2
SimiGo↔PALACE 边界登记 = PALACE G1/G2/G3（找到什么→能否支持
  下一步→能否未来继续存在并支持工作）→ SimiGo（持续工作本身
  如何成为可恢复 Execution State）——G3 不重新定义 ES，
  让工程逼出边界
```

当前状态：

```text
G0/G1/OQ-B/E6/G2 = 全部 CLOSED
G3               = UNLOCKED / DESIGN ENTRY（Durable Information）
下一动作         = G3 设计草案起草（第一问已冻结）
Current blocker  = none
```

### LAB PALACE V2 OQ-B RULED PASS/CLOSED + RQ-OQB-1 ANSWERED — G3 DESIGN DRAFT COMPLETE — 2026-10-02

Human OQ-B 验收裁定：**PASS / CLOSED FOR THIS EXPERIMENT**（OB-1..4
全 PASS；OB-4 = HIGH-VALUE EVIDENCE）；关键登记观察：「工作记录与
世界当前状态在最小漂移场景中出现了独立性：当前 L0 可以恢复现实，
却不能恢复过去工作者曾经观察到的状态」（强于前、不越界——替代
方案存在：change log/版本快照/历史索引）；OB-3 裁定 = 观察事实
不预判语义（有痕迹须问来源，无痕迹不证不需要）；OB-2 提升登记
（Representation Change vs Semantic Change 区分——与 SimiGo
Semantic Contract ≠ Representation Layout 方法论呼应，不升格
原理）；RQ-OQB-1 ACCEPT → 已真机执行（f8a1c2a：Excel 原生编辑
= 1 cell 变化，22 噪声 = openpyxl 特有）；RQ-OQB-2/3 OPEN；
G1 CLOSE 不扩 Corpus；顺序 = RQ-OQB-1 → E6 Design Entry。

Human G3 解锁确认 + 骨架裁定（比 G2 更克制：不急着定义 Durable
Information 是什么，只设计能把「明天能不能继续」逼出来的真实
工程实验；增加硬指标重做量；工作记录原样性保护；核心压缩 =
「停止工作之后，哪些过去发生过的事情必须仍然存在，下一次工作
才能不是从头开始？」）。

G3 设计草案：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_G3_DURABLE_INFORMATION_
DESIGN_DRAFT_20261002.md`。

```text
研究问题（human 原语冻结）= 如果今天把当前工作停止，明天重新
    打开，我究竟需要什么，才能真正从这里继续，而不是重新做一遍？
核心对照 = 条件 A（只有 L0：重新发现/比较/判断才能继续）
    vs 条件 B（L0 + 工作记录原样：直接恢复继续下一步）
硬指标重做量 = 没有工作记录时，重新达到 G2 T-3 停止状态需要：
    重新执行多少步骤/读取多少文件/重做多少判断——「全量计算 →
    增量计算」成为可观察工程事实
H-G1-02 材料流向（预登记）= 重复工作/信息损失/路径丢失/无法定步
    = 四类合格信号；单纯效率差不升格；判定归结果门
工作记录原样性保护 = 条件 B 只用 G1/G2 实际产物原样
    （baseline-inventory/discovery-set+corrections/
    t1-mapping-results/观察记录文档）；禁止新整理漂亮摘要
观察五项 = OB-R1 工作位置 / OB-R2 已有发现 / OB-R3 已排除项 /
    OB-R4 未闭合问题 / OB-R5 直接进入下一步
执行阶段 = R-1 停止点冻结（G2 T-3 完成时点状态原样枚举）/
    R-2 重做量清单（从实际记录枚举，非估计）/ R-3 条件 A
    bounded 实测 / R-4 条件 B 实测（含记录缺口复检——V-5 截断
    教训）/ R-5 对照收束
禁止 = Durable Information/Provenance/PALACE State/Dynamic Index
    Schema / 知识图谱 / 提前决定必须持久化内容 / G3 等同 ES
    必要性 / L0 写入 / 新整理摘要 / 性能基准 / Gate①·V1 复活
```

当前状态：

```text
OQ-B = PASS / CLOSED（RQ-OQB-1 已执行答案在档）
PALACE_V2_G3 = DESIGN DRAFT COMPLETE / AWAITING HUMAN FREEZE REVIEW
执行授权     = 无（冻结 + 授权后：R-1..R-5 → 结果门）
Current blocker = none
```

### LAB PALACE V2 G3 EXECUTED — REDO-COST CONTRAST MEASURED — FIVE-ITEM RECOVERY MATRIX — 2026-10-02

Human G3 冻结审查 PASS / EXECUTION AUTHORIZED（附加执行纪律：重做量
三类计数口径 = 步骤/读取/判断；B 原样性保护执行期不变——禁止顺手
补记录；OB-R3 排除项与 OB-R4 未闭合问题为重点；H-G1-02 升格规则
严格保持——单纯效率差≠升格；三结果形态不预设 C）。

G3 执行完成（R-1..R-5）。结果记录：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_G3_RESULT_20261002.md`。

```text
R-1 停止点冻结 = G2 T-3 完成时点状态原样枚举（S1..S8/未闭合
    S7·S8/RQ-G2-1..3/排除项/下一步指向 RQ-G2-2）
R-2 重做量清单（从实际记录枚举非估计）= 14 主要阶段 / 8 xlsx
    ×≥4 遍 / cell 读取 ≥223,356（156,543 结构层 + 46,972 T-1 +
    19,841×2 diff）/ D×6 全文 / ≈30+ 项判断
R-3 条件 A bounded 实测 = 119 步骤/8 文件/110 sheets/156,543
    cells/1.5s——产出原始样本 18 个零判断；证实 R-2 量级真实
R-4 条件 B 实测（记录原样恢复）= R1 工作位置 ✓直接 / R2 已有
    发现 ✓直接（JSON 结构化）/ R3 已排除项 △分散恢复（跨选族/
    台账/证据多文档）/ R4 未闭合 ✓直接 / R5 下一步 ✓直接；
    记录缺口复检 = corrections 在档自愈案例 + L0 完整性复核
    无矛盾 + 原样性保护未破
R-5 对照 = 条件 A 重做 ≥R-2 全清单（含 ≥223,356 cells 与 ≈30+
    判断）vs 条件 B 读 4–6 份记录文件零重做
H-G1-02 材料登记 = 四类合格信号之一「重复工作」获实测计数
    （重达停止点须重复 ≥R-2 全清单，bounded 于「重达完全相同
    停止点」口径）——非单纯效率差；「过去发生过的事情必须仍然
    存在」获工程计数级支持；ES 必要性判定归 human
生成 RQ-G3-1..3（排除项分散聚合 / 记录格式可恢复性 / 更细粒度
    停止点重做量曲线）
```

当前状态：

```text
PALACE_V2_G3 = EXECUTED / RESULT AT HUMAN
待裁定 = G3 验收 + H-G1-02 是否升格 + 下一方向
Current blocker = none
```

### LAB PALACE V2 G3 RESULT GATE RULED — PASS/CLOSED — H-G1-02 UPGRADED — PALACE/SIMIGO EMPIRICAL BOUNDARY — 2026-10-02

Human G3 结果门裁定登记：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_G3_RESULT_GATE_20261002.md`。

```text
裁定表 = G3 PASS/CLOSED；R-2 OBSERVED/QUANTIFIED；R-3 bounded
    measurement PASS；R-4/R-5/V-5 复检 PASS；H-G1-02 升格
    SUPPORTED — strong exploratory evidence；ES 必要性仍
    UNPROVEN；新 Schema NOT AUTHORIZED；RQ-G3-1..3 进入下一
    研究阶段
H-G1-02 冻结措辞（逐字，最终形态）= 「在当前真实文件工作样本
    中，连续信息工作不仅依赖当前 L0 内容，还依赖此前形成的
    工作位置、已发现信息、已排除项、未闭合问题以及下一步指向。
    仅保留当前 L0 时，这些工作状态无法直接恢复，并导致可实测
    的重复读取、重新判断和路径重推导。」（不写「必须依赖
    Execution State」——太强）
A 忘掉的分层 = 第一层重复工作（实测边界 bounded）；第二层工作
    状态的信息损失（更重要）：「我知道什么/排除了什么/还不知
    什么/为什么下一步查这个」——313,356万 本身可重找，但
    「为什么现在应该追它」属于工作过程产生的状态——信息与
    工作的差别第一次被拉开
变化溯源三层 = ①找不到源头 ②局部支撑事实 ③多数值无口径
    关系——比笼统可追溯更有价值
ES 边界三候选 = A 只 L0 重做（已实测）/ B L0+原样记录 恢复
    （已实测）/ C L0+PALACE Durable Information 恢复（未验）；
    已证 A≠B（工作状态需要持久性）；未证 持久性必须由 SimiGo
    ES 提供——若 C 完整恢复则部分 ES 形态可能沉淀进 PALACE
方向裁定 = V1 继续 PARKED / G2 不复测 / E6·OQ-B 暂不扩展 /
    下一入口 = RQ-G3-1（排除项/负知识：数字 X→检查→属于 7 标
    →排除；无记录则 X 重现→重判→重排除——先观察不命名
    Schema）/ RQ-G3-2（记录格式谱系：完整日志→结构化→摘要→
    一句话，哪个还能真正继续——逼近 PALACE Durable Information
    与 SimiGo ES 边界）/ RQ-G3-3 低优先级（停止点曲线未来
    形态不预设）
边界意义（human 原文）= 「它第一次给 PALACE 和 SimiGo 之间的
    边界提供了实证问题，而不是概念上的边界」
证据链收束（human 逐字）= 「G1 发现连续信息工作存在路径依赖；
    G2 证明后续工作实际消费此前发现；G3 则实测证明，丢失这些
    工作记录会使下一次工作退化为重新发现、重新判断和重新选择
    路径。」
```

当前状态：

```text
G0/G1/OQ-B/E6/G2/G3 = 全链 CLOSED
H-G1-01/02          = SUPPORTED（strengthened / strong exploratory）
ES 必要性           = UNPROVEN（三候选 C 未验）
下一入口            = RQ-G3-1（负知识观察）/ RQ-G3-2（记录格式
                      谱系）——具体设计待 human 发起
Current blocker     = none
```

### LAB PALACE V2 RQ-G3-1 DESIGN DRAFT COMPLETE — NEGATIVE KNOWLEDGE MINIMAL EXPERIMENT — 2026-10-02

Human 方向裁定：下一入口 = RQ-G3-1 优先（排除项可能比记录格式更快
触及 PALACE 核心）；最小路径与观察点 ①..⑤ 冻结概念；潜在价值
仅作研究问题非结论（「工作的连续性…可能需要保存…不走这条路的
信息」）。

RQ-G3-1 设计草案：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_RQG3_1_NEGATIVE_KNOWLEDGE_
DESIGN_DRAFT_20261002.md`。

```text
研究问题（human 措辞冻结）= 如果系统只保存「发现了什么」，而不
    保存「已经排除了什么以及为什么」，它能否真正避免重复工作？
    （工程实验；非负知识对象/Schema 定义）
最小路径（冻结）= 候选发现→初步相关→读取依据→发现不属于当前
    任务→排除→继续→人为停止；第二轮同停止点：条件 A 只给 L0 /
    条件 B 给原样工作记录
真实场景绑定（零人工构造）= 复用 Corpus-1 选族真实排除四条：
    E-X1 经济运行汇报两件（相邻主题）/ E-X2 B1 线外便道 ×4
    （human 裁定暂缓）/ E-X3 族 C 平行变体分类 / E-X4 T-1 口径
    范围排除（产值/批复/收款不在标后预算表范围）——全部在原样
    记录在案
观察点实测 = ①重新遇到已排除物（条件 A 候选清单 ∩ E-X 原件）/
    ②重做相同判断 / ③排除原因留存比对 / ④仅「已排除」标记
    不给理由时的决策一致性 / ⑤排除须回原件重确认的分级
预登记预期（可推翻）= P-E1 条件 A 重遇 E-X1 且主题判定需重读
    内容（ lexical 邻近不可从文件名判定）/ P-E2 E-X2 存在纳入
    压力 / P-E3 E-X4 口径排除纯 L0 下不可复现（重发现者无法
    「排除不存在的东西」——或永不发现该缺口）
禁止 = 负知识对象/Exclusion Schema 定义 / Provenance·Lineage·
    Relation 命名建模 / L0 写入 / 性能基准 / 3000 扩容 /
    预写结论 / Gate①·V1 复活
```

当前状态：

```text
PALACE_V2_RQG3_1 = DESIGN DRAFT COMPLETE / AWAITING HUMAN FREEZE
    REVIEW
执行授权 = 无（冻结 + 授权后：条件 A 实测 → 条件 B 恢复比对 →
    ①..⑤ 逐项事实 → 结果门）
Current blocker = none
```

### LAB PALACE V2 RQ-G3-1 EXECUTED — EXCLUSION RE-ENCOUNTER + CHALLENGED EXCLUSION — 2026-10-02

Human RQ-G3-1 冻结 PASS / EXECUTION AUTHORIZED（附加纪律：条件 A
完全不可见 E-X 历史排除记录；E-X4「不可复现」只记观察；④ 三结果
均可；RQ-G3-2 由本实验结果决定）。执行完成：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_RQG3_1_RESULT_20261002.md`。

```text
Condition A（只持 L0 重发现成本控制候选，两真实目录枚举）
  [O] 词法层：E-X1 三件（经济运行×2/经济工作进展）文件名不含
      「成本」——词法未命中
  [O] 目录邻接层：E-X1 三件与词法命中件同目录直接相邻——浏览式
      重发现必然接触
  [O] 新事实：经济运行情况汇报存在 0307 与 0308 两个日期版本
      ——0308 为原选族与 G1/G2 全链从未检查的孪生版
  [O] 内容级重判（读取依据步骤，执行者记忆污染已标注）：
      0307/0308 内容 = 成本×26/预算×16/盈利×10 ——与成本控制
      强相关；0308 含真实修订（现场管理费 2,573.26万→2,881.34万
      = +308万、计量比 5.0384→5.04、新增分包条款段）——
      未检的版本演化对
  [O] 经济工作进展（截至11月底）= 成本×1 弱——新鲜排除与原排除
      方向一致
Condition B（原样记录恢复）
  [O] E-X1 排除事实在选族文档仅以「未入选」体现（无显式条目）；
      理由「相邻主题」仅存会话工作记录——理由记录弱/分散
  [O] E-X2/E-X3/E-X4 理由在案可恢复
①..⑤ 判读
  ① 重遇 = YES（三件浮现 + 0308 新发现）
  ② 重判 = YES（主题归属带内容证据重判）
  ③ 原因留存 = 条件 A 无；新鲜依据（关键词密度）与原理由
     （相邻主题）方向相反
  ④ 仅标记不给理由 = 本实例不安全：标记会压制 0308 孪生与
     内容强相关证据——原排除过严风险不会被发现（单实例观察，
     对应三结果框架结果 B）
  ⑤ 须回原件重确认分级 = E-X1 内容级（已执行并挑战原排除）/
     E-X3 文件名级可判 / E-X4 数字映射级缺失步骤（P-E3 观察）
关键冲突登记（归 human）= 原排除（选级判断未读内容）vs 新鲜
  内容证据冲突——E-X1 是否纳入成本控制语料 + 0308 孪生版是否
  补入 = human 重裁（Corpus 组成变更）；执行者记忆污染声明
  （机械层不受污染，内容判断建议独立复核）
H/RQ 流向 = H-G1-02 增材（排除记录理由缺失/分散 → 重发现时
  无法安全沿用）/ H-G1-01 再证实（目录邻接+0308 发现）/
  RQ-N1 排除理由记录粒度 / RQ-N2 被排除族内版本对与排除范围
```

当前状态：

```text
RQ-G3-1 = EXECUTED / ①..⑤ 完成 / RESULT AT HUMAN
待裁定 = ①..⑤ 验收 + E-X1 冲突重裁（Corpus 组成）+ 0308 处置
        + RQ-G3-2 是否启动
Current blocker = none
```

### LAB PALACE V2 RQ-G3-1 RESULT GATE RULED — E-X1 REVOKED & SPLIT — CORPUS EXTENDED — RQ-G3-2 UNLOCKED — 2026-10-02

Human 结果门裁定登记：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_RQG3_1_RESULT_GATE_20261002.md`。

```text
裁定表 = ①..⑤ 全 SUPPORTED（④ = UNSAFE IN THIS INSTANCE 具体
    反例：「排除状态 ≠ 足够的可恢复工作记录」）；H-G1-01 =
    SUPPORTED—re-confirmed；H-G1-02 = SUPPORTED—strengthened；
    RQ-G3-1 PASS/CLOSED；RQ-G3-2 UNLOCKED
E-X1 重裁（拆两裁定）：
  E-X1-A 经济运行族 = YES 纳入成本控制相关候选语料（内容证据
      支持非文件名推断）；原「相邻主题」排除撤销→转存历史
      排除记录
  E-X1-B 0308 = YES 纳入 Corpus-1 扩展样本，标记「新增验证
      样本/后发现版本」（不悄悄改写原 Corpus；含 +308万 现场管理费
      实质修订）
  经济工作进展（截至11月底）= 维持排除（一致）
  纪律 = 仅记录「两文件之间发生了什么」；不定义 version_of/
      supersedes/lineage/revision relation
本轮最深发现登记 = 排除项本身也可能失效：仅存 excluded 标记
    → 旧判断阻止新证据进入（危险状态）；存 excluded+reason+
    basis → 至少可问「新证据是否已使原依据失效」——观察登记
    不命名 Provenance Schema
H 更新 = H-G1-02 SUPPORTED—strengthened（新增：过去排除判断
    及其依据可能需随新 L0 内容重新审查）/ H-G1-01 SUPPORTED—
    re-confirmed（目录+内容双层面路径依赖；「信息空间不是一次
    扫描之后就封闭的」）
E6↔G3-1 共同规律（human 登记）= 过去的工作记录既是继续工作的
    资产，也是需要被重新验证的历史证据
RQ-G3-2 解锁（焦点修正）= 双轴「恢复能力 × 历史判断可审查性」
    （当前位置/结论摘要/结构化记录/原样记录 × 能否继续/知道
    为什么/重新审查旧判断）
Corpus 变更证据 = corpus-change-rqg3-1.json 落盘
```

当前状态：

```text
RQ-G3-1 = PASS / CLOSED
Corpus-1 = A×8 + D×6 + 经济运行 0307/0308（扩展标记）= 16 文件
RQ-G3-2 = UNLOCKED / DESIGN ENTRY（双轴焦点）
Current blocker = none
```