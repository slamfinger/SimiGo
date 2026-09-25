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
Engineering subphase: RUNTIME_ENGINEERING_VALIDATION_COMPLETE / EXECUTION_STATE_ENGINEERING_GATE_OPEN_E1_CONTRACT_NEXT

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
E1 contract                               NEXT (tests-first)
E2–E5                                     NOT STARTED
```

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
