# 交接报告：路线 B / P2 实施移交（2026-11-05）

**性质**: 移交文档 — 供新 Agent 接手路线 B 当前活跃工作流（P2 配置裁定收尾 → 真机执行授权 → 四阶段实验实施 → 公开复刻链）。本文档由移交会话生成；接手后本文档归新 Agent 维护。
**接手者第一步**: 读本文档 → 按 §2 文档地图通读 1–6 → 向用户确认接手 → 按 §5 当前队列继续（①–⑤已定案；真机执行授权待单独申请）。

---

## 1. 项目一页纸

- **ES/IS**：本仓库（SimiGo）在开发过程中形成的一套执行连续性与信息恢复相分离的研究思路——**Execution State（ES，执行续接权威）** 与 **Information Space（IS，信息空间：已结算信息及其来源/版本/依赖/有效性依据的权威状态）**。核心骨架一行式：`ES_n ──Settlement──▶ IS ──Admission──▶ ES_{n+1}`（Admission 在恢复时点 fail-closed 重判有效性与依赖完整性；不满足时只重执行失效闭包）。
- **命名（已裁定，勿改）**：IS = **Information Space（信息空间）**。"Information State" 是已废弃误称，不保留双重解释。
- **两条路线**：路线 A = llama.cpp 工程提案（独立，不在本交接范围）；路线 B = 面向开源生态的 ES/IS 语义研究开放。当前唯一活跃工作 = 路线 B 的 **P2 真机实验**。
- **对外姿态（已裁定）**：Research Note / Independent Technical Review——报告研究发现、邀请独立审查与复现，**不是**架构推介；四种审查结果（无新意/互补/复现成功/不采用）全部有效。
- **SimiGo 定位**：参考实现与验证载体，**不是** ES/IS 语义的边界。P2 全部通过也只支持该具体实现/模型/引擎/配置下的证据链，不证跨引擎普适。

## 2. 必读文档地图（按序通读）

| # | 文档 | 状态 | 用途 |
|---|---|---|---|
| 1 | `docs/upstream/DEEPSEEK_ES_IS_SEMANTIC_ROUTE_20261105.md` | 活文档 | 路线总纲（§0 姿态修订、§7 进度表） |
| 2 | `docs/upstream/B0_ESIS_GLOSSARY_20261105.md` | **ACCEPTED·冻结** | 15 术语正/反定义 + 3 项 OPEN（OQ-1/OQ-3/OQ-8）；**禁止扩充术语表** |
| 3 | `docs/upstream/B1_ESIS_MINIMAL_FORMALIZATION_20261105.md` | **ACCEPTED·冻结** | R1–R6 骨架、状态转换、恢复时约束；含 Settled(ρ)/Recoverable(ρ,ctx,t) 分离与 child ES 引用三分 |
| 4 | `docs/upstream/ROUTE_B_RESEARCH_NOTE_POSITIONING_20261105.md` | 活文档 | 对外姿态、分对象邀请矩阵、证据前置 P1–P3 |
| 5 | `docs/upstream/P2_EXPERIMENT_PLAN_20261105.md` | **G1 PASS·CLOSED** | 四阶段实验方案、两条红线操作化、§5 判据总表——**实施依据** |
| 6 | `docs/upstream/P2_CONFIG_RECORD_20261105.md` | **活文档★** | 配置裁定①–⑤全部定案；真机执行授权待单独申请——**你的日常工作文档** |
| 7 | 冻结契约（只可引用，**不可修改**） | — | `IS_EXTERNAL_TURN_CONTRACT_20261030.md`、`EXECUTION_RUNTIME_DESIGN_V16.md`、`BRANCH_FORK_PROTOCOL_DRAFT.md`、`AGENT-ACCESS.md`、`OPEN_SOURCE.md` |
| 8 | 研究层（背景） | — | `docs/research/EXECUTION_STATE_RESEARCH_STORY_20260922.md`（Track B 实验线） |

**不可修改清单**：上表 #2、#3、#7 全部；历史实验记录；路线 A 文件。发现文档间冲突：冻结契约与权威实现 > 配置记录 > 计划 > 路线文档，回改下层不改上层。

## 3. 语义红线（违反任一 = 实验无效或文档回改）

1. **Refuse ≠ 重执行**：Admission 拒绝是准入结论，不是执行命令；只有**实际发生 reexec** 才进入 E3.2b 验证 R3，否则 R3 记"本轮未验证"——不得因出现 Refuse 宣称 R3 已验证；
2. **Settled ≠ Recoverable**：失效不撤销结算事件（Settled(T) 仍真），只使 Recoverable(T, ctx, t₂) 为假；记录保留是实现行为，不是 Settled 的语义定义；
3. **checkpoint 陷阱**：磁盘工件存在 ≠ 失败；阶段 3/4 **实际消费**旧 checkpoint/KV = 一票否决；
4. **O2.2b 范围诚实**：观测范围必须明写；"未观察到"不得升级为"所有路径均不可达"；没有 telemetry 记录，只有在入口覆盖完整性已验证时才能作为"未触发"证据；
5. **O2.3 分级诚实**：G2（`L × 96 KiB/token`）是结构估算、G3（RSS）是间接读数，均不能单独证明 KV 已释放；只有 G1 中实际暴露的容量/分配读数可支持资源量主张；读数降级 ≠ 降低 O2.1/O2.2 要求；
6. **E4.4 两级结论**：「消费关系已验证」≠「具体值派生关系已验证」；降级不判失败，**冒进升格才判失败**；
7. **KV 容量公式只是理论基准**（96 KiB/token）——不可替代实际可归因读数；模型身份相等不构成 KV 状态相等或迁移证据，不得自行构造看似唯一的 KV ID；
8. **MoE 确定性不作前提**：固定模型与 tokenizer 身份；E4.x 是结构性主张，不依赖逐位输出一致；
9. **公开证据边界**（OPEN_SOURCE.md）：不宣称 universal / backend-independent / 跨引擎普适；【已核验】与【候选读数】两级标注纪律必须延续——引文必须直读源码核验，禁止转引未核验材料；
10. **B0 术语表冻结**：不扩充术语；OPEN 只有 OQ-1/OQ-3/OQ-8 三项；
11. **实验失败是有效结果**：任一阶段失败 → 停链、observed 照实入档，不构成对路线 B 的否定。

## 4. 当前状态快照（截至 2026-11-05 移交时）

- **B0 ACCEPTED / B1 ACCEPTED（六项复核 PASS）/ P2 方案 G1 PASS·CLOSED**；
- **配置裁定**：①–⑤已全部定案（详见配置记录 §1–§5；④附五项约束，G2 修正为结构估算，β 条件通过；⑤预算/阶段门/降级/授权边界已接受）；
- **授权状态**：零实现改动、零模型加载、零真机执行、零对外发送——每一项单独授权；
- **主模型**：本地缓存 `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit`（静态核查全过：qwen3_moe、48L、32Q/4KV GQA、无 hybrid、apache-2.0、权重 4 分片在场、runtime 注册表 `qwen3_moe` ✓、快照 `6e302ea604ad9ab206367e2c501d1571023e7b6d`）；备选 Qwen2.5-1.5B-Instruct-4bit（config 未核）；
- **仓库可及性事实**：IS 契约引用的真机验收材料（`research/agent-runs/...BUILD-97043902`）不在当前仓根目录——历史材料存在但不在本仓 ≠ 公开复刻链已建立；P2 针对后者，不重复制造历史实验。

## 5. 任务队列（接手后按序执行）

- **T1（已完成）**：向用户提交配置记录 §4 的④提案；用户已裁定批准并附加五项约束，已编入 §4；
- **T2（已完成）**：⑤预算与阶段间停止条件提案已获用户接受，配置记录 §5 已转为定案；
- **T3（E0 已完成 · PASS，等待进入 S1）**：真机执行授权请求见 `P2_EXECUTION_AUTHORIZATION_REQUEST_20261105.md`；用户已授权 C1，C2 未授权。E0 只读预检已于 2026-11-05 通过（配置记录 §5.10，证据 `work/p2-c1/evidence/s0/e0_report.json`），公开 HTTP 硬门槛已满足；阶段 1 须用户确认后启动，未确认前仍为零加载、零生成；
- **T4**：获授权后按 `P2_EXPERIMENT_PLAN_20261105.md` §3 执行阶段 1–4：每阶段读数 observed/expected 分列入档；执行配置钉死项清单见 §7；
- **T5**：执行后产出公开复刻包（方案 §6 形状：描述性步骤只依赖冻结合同+公开 HTTP 面+只读 SQL+工件清单）；
- **T6**（更远，均须届时授权）：P3 相关工作六问对照 → Research Note v0 → 分对象邀请（llama.cpp 第一优先，一次一个对象）。

**执行机制待钉死（T3/T4 时与用户确认，不得自行发明）**：Run A/Run B 的具体进程形态（优先公开 HTTP 的 App/runtime 前台路径；headless `G1G3Entry` 仅限辅助或被单独授权，不得替代公开 HTTP 证据）；HTTP 面端口与调用序列；隔离 `SIMIGO_HOME` 下的 SQLite 位置与只读访问方式。

## 6. 工作流规范（从移交会话习得，务必延续）

1. **节奏**：提案 → 用户逐条裁定（附详细理由与约束）→ 逐条编入文档 → （必要时）针对性复核 → 定案。不跳步、不抢跑；
2. **用户复核基于贴出文本**：重大交付前先自检（编号一致性、状态行、粗体标记、计数陈旧）；发现自己先前表述过时要主动更正并说明；
3. **裁定原文入档**：用户裁定的关键原话以引用形式保留进对应文档；
4. **每轮结束明确授权边界**：用一行状态收尾（当前零实现/零加载/零执行/零外发）；
5. **中文沟通**；技术术语用配置记录/B0 术语表的既定中英对照；
6. **诚实优先**：候选读数不冒充预期；降级如实标注；失败照实记录；代理扫描结果引用前必须直读核验。

## 7. 关键已核验代码事实（可直接引用；引用新事实前必须自己直读核验）

| 事实 | 位置 |
|---|---|
| 结算唯一前置门，fail-closed，先于任何写入 | `SettlementAuthority.swift:5-12` |
| SettledResult 类型 / digest 复核 | 同文件 `:20-28` / `:62-66` |
| IS 准入七步 fail-closed 检查单 | `ISAdmission.swift:92-99` |
| 显式命名结算准入（"must name it"） | 同文件 `:122-125` |
| invalid/dependencyInvalid 拒绝路径 | 同文件 `:146-160` |
| DERIVED_CONSUMPTION + evaluateConsumer | 同文件 `:161-169` |
| KV 复用权威在 IS（kvBindings 空则无权复用） | `ContinuationAdmission.swift:17-20` |
| 恢复值来自权威存储而非客户端 | 同文件 `:4-7`；esStateID 仅入口引用 `:56-59` |
| childESStateID 供下一次准入（ES↔IS 闭环） | `ContinuationSettlement.swift:105-106`；契约终端 `:4-23` |
| 依赖闭包递归 CTE | `ESISDatabase.swift:5654` |
| invalidateSourceFile 语义（无关保持 valid/无依赖者零操作/幂等） | 同文件 `:4946-4983` |
| 载体不 reinterpret 字节 | 同文件 `:853-855` |
| fork 是 storageKey 级、非 execution lineage | `ExecutionLineage.swift:28-31`（外审钉死） |
| EngineExecutionStateSnapshot 零行为（快照≠ES） | `ExecutionStateProjection.swift:4-9` |
| 结算前置条件族 / 复用四条件 | `AGENT-ACCESS.md:229-240` / `:102-109` |
| suspend 语义（checkpoint 文件唯一存活） | `BRANCH_FORK_PROTOCOL_DRAFT.md:39-43` |
| 主模型 config（qwen3_moe/48L/32Q/4KV/无 hybrid） | 本地快照 `6e302ea6…/config.json`（实测） |
| 注册表 `qwen3_moe` / `qwen3` 条目 | `slamfinger/mlx-swift-lm@6f88129` LLMModelFactory |

## 8. 授权阶梯（硬边界，逐项解锁）

| 动作 | 当前 | 解锁条件 |
|---|---|---|
| 实现修改 | **禁止** | 用户单独授权 |
| 模型加载（含最小加载验证） | **禁止** | 用户单独授权（范围由用户划定） |
| 真机实验执行 | **禁止** | 五项配置裁定完成 + 用户单独授权 |
| 对外发送/公开/建 PR | **禁止** | 届时单独确认，一次一个对象 |

## 9. 已知未决与风险

- ①–⑤已全部定案；C1 已授权但受 E0 硬门槛约束，C2 未授权；C1/C2 均未启动；
- 执行配置待钉死项（继承自③④⑤）：公开变更检测入口、T→R 绑定构造命令、旧 digest 匹配调用点、KV 内省暴露面、T 结算 kv 绑定有无（α/β）、探针 A 拒绝路径是否解析 M2 权重、restore 事件遥测显形形态、E4.1 候选字段核验、⑤预算计账与阶段门证据包格式；
- 项目记忆（`~/.zcode/cli/memories/projects/simigo-new-root-9f0d013baa19027b/memory/`）承载裁定史；**与本报告及配置记录冲突时，以仓内文档为准**；
- 用户强调过：以上复核基于移交会话贴出文本，非逐行仓库审计——接手后首次接触仓库时应按 §2 通读核实。

## 10. 移交核对清单

- [ ] 通读 §2 文档 1–6
- [ ] 向用户确认接手并复述当前状态（一行：①–⑤定案、执行授权未授予、四零边界）
- [x] T1 已完成（④已获批准并编入配置记录）
- [x] T2 已完成（⑤已获接受并转为定案）
- [x] T3a：C1 已授权；E0 只读预检 PASS（2026-11-05，配置记录 §5.10）
- [ ] T3b：向用户复述 E0 结论并请求确认进入 S1（阶段 1）
