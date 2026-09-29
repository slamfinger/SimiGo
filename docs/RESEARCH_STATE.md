# SimiGo-Lab Research State

> **This file is the authoritative snapshot of the current SimiGo-Lab research state. Conversation memory must not override it.**

**Last updated**: 2026-09-25（R-INTERNAL-18 = ROr-4 / R_ORACLE_DEFERRED
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
                    file:///Users/... reference pinned at stale revision
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
