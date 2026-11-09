# ES/IS 研究地图 V0.1

日期：2026-11-08
对照对象：`PAPER_REWRITE_SKELETON_V0.2_20261108.md`（§1–§8、P1–P4）
代码基线：`Packages/SimiGoRuntime`，schema v23，契约测试 **286/286**

每个论题给三样：代码锚点、检查它的测试、可引用读数。缺一样就进 §4 缺口清单。

载体侧第二基线：`~/Documents/SimiGo-llamacpp-fork-lab`（llama.cpp fork `llama-pr30970` `61e6777d9`
`--slot-attach`；实验目录 `rq4-es-carrier-20261104/`）。两侧读数不同源，不合并、不相除。

---

## 1. 骨架 → 实现

| 骨架节 | 正文要说的 | 代码锚点 | 已有证据 | 状态 |
|---|---|---|---|---|
| §1 Introduction | 两个答案、一次反常 | `InformationLoop.reusableAnswer`（L436）→ `ESISDatabase.recordInformationReuse`（L4665） | Arm A：`reuse_hit=1 model_calls=0 settlements_delta=0` | 已实现 |
| §2 Background | 六圈假设及其证人 | 无论文侧代码 | 文献表在论文，不在本仓 | 不适用 |
| §3 Model | 两谓词、四格、三路径 | `settleTurn`（`InformationLoop` L617）、`ISAdmission.admit`（L112/L132）、`SettlementConsumption.consume`（L171）、`resolve`（L132） | 7 步准入 + 三路径写入清单；Arm A/B | 已实现 |
| §4 Mechanism | 门、七步、闭包、schema 分离 | `admit` 六步校验；`dependency_edges` 唯一索引（v22）；`settlement_consumptions.model_calls CHECK(model_calls=0)`；v23 有效性事件账本（`ESISDatabase` L963） | `ISAdmissionTests`、`ESISDatabaseTests` 迁移测试 | 已实现（需同步论文措辞，见 G5） |
| §5 Propositions | 四条被逼出来的命题 | 见 §2 | 见 §2 | 已实现，读数见 §2 |
| §6 Guarantees | C1–C10 作为推论 | 见 §3 | 见 §3 | 8 条已测，2 条附条件 |
| §7 Evaluation | 三层证据 + 分歧案例 | 结构＝测试；行为＝11 对（既有）+ Arm A/B（新）；运行时＝单机 | 见实验记录 | 分歧案例本轮补上 |
| §8 Conclusion | 复用不是键的属性 | `key` 只是 `admissible(settlement, declaration, t)` 的一个输入 | 由 §3 的 C5–C8 支撑 | 已实现 |

---

## 2. 四条命题 → 代码 → 可反驳条件

**P1 保存的单位是结算，不是状态；复用天然有两条轴。**
锚点：`settlements` 与 `execution_states` 是两张表；直出复用不写 `settlements`、不建 `execution_states`、不写 `settlement_consumptions`，只写 `information_reuse_events`（L546）。
读数：Arm A `settlements_delta=0 states_delta=0 consumptions_delta=0`。
若为假会看到：只保存 KV 就能恢复对话——即直出路径必须造一个结算或状态才能返回文本。现在不需要。

**P2 恢复是重判，不是重建。**
锚点：`admit` 的六步（payload 摘要、结算有效性、上游闭包逐成员、值恢复）；失效由 v23 的 `settlement_validity_events` 追加，不覆写结算行。
读数：`invalidateSourceFile` 后 `invalidatedSettlements=2`（检索 + 建立其上的答案），同查询得到新 demand（Arm B）。
若为假会看到：键相同即可安全复用——朴素键缓存正是这个反例，返回陈旧的 5.6 且静默。

**P3 续算的根据是关系，不是物质。**
锚点：`dependency_edges`（v22 唯一索引，`from,to,kind`）；`settlement_bindings.source_file_id` 是文件失效闭包的种子（P1 装置实测：去掉绑定后 `invalidatedSettlements=0`）。
读数：P1 装置 `changed=1 → invalidatedSettlements=1`；绑定删除对照组为 0。
若为假会看到：KV 语义可兜底 Position——位置相同就应继承，现在不成立。

**P4 零调用有两个含义，判别必须靠结构。**
锚点：消费路径 `settlement_consumptions.model_calls INTEGER NOT NULL CHECK(model_calls=0)`（schema 级，非零不可表示）；直出路径 `information_reuse_events.model_calls=0` 且无结算行。
读数：两条路径的计数器都给 0；区别只在行的种类与主键域（consumption 的 `demand_id` vs reuse 的 `demand_id` 不同域，且 reuse 无 `consumer_settlement_id`）。
若为假会看到：计数器能把两者分开——现在分不开，所以必须结构判别。

---

## 3. C1–C10 → 锚点 → 测试

| # | 断言（压缩） | 代码锚点 | 测试 | 状态 |
|---|---|---|---|---|
| C1 | 消费原子且零调用，三处一致 | `SettlementConsumption.consume` L171 | `SettlementConsumptionTests:151/:202/:423` | 已测 |
| C2 | 拒绝是结论，不是命令 | `ManagedRefusal` 四码 + 审计 best-effort | `RefusalSideEffectTests:133/:168/:203/:336` | 已测 |
| C3 | 降级从不静默 | `Refusal` 类型枚举，无 fallback 校验器 | `ISAdmissionTests:126/:150`、`ManagedRefusalTests` | 已测 |
| C4 | 无门不结算 | `SettlementAuthority.authorize` | `SettlementAuthorityTests:28–80` | 已测 |
| C5 | 一 state 一结算 | 声明写入的重放/冲突分支 | `SettlementIdempotencyTests:330` | 已测（声明写入边界） |
| C6 | 一 source 一 revision | `settlement_source_identities` + `settlement_operation_keys` | `SettlementIdempotencyTests:101/:124/:148/:173/:431` | 已测 |
| C7 | 一指纹一次 | 六维指纹 + `object_id == SHA256(payload)` | `ManagedContinuationTests:347`；`SnapshotContractTests` | 已测；正文需补 content-addressability 段（G6） |
| C8 | 复用靠声明 | 消费必须带 declaration；无声明不可消费 | `SettlementConsumptionTests:558`、`SettlementIdempotencyTests:221/:238` | 已测 |
| C9 | 失效沿闭包且停在边界 | `markSettlementsInvalidInTransaction` L5971 + 闭包 | `ESISDatabaseG2Tests:56/:87/:110`、`InformationLoopTests` 闭包组 | 已测 |
| C10 | 缺席身份不是通配 | 身份仅溯源；声明显式引用才设闸 | `SettlementIdentityBindingTests`、`InformationReuseTests:181/:210` | 已测 |

---

## 4. 缺口（不写成已完成）

| # | 缺口 | 现状 | 处理 |
|---|---|---|---|
| G1 | 骨架 §3 的两个分歧臂 | 本轮已补：Arm A 直出复用、Arm B 朴素键缓存 | 关闭；边界见实验记录的“不主张” |
| G2 | continuation 的载体实现 | **两侧都已实现**（见 §5）：MLX 产品路径（`NativeMLXPrefixPool` + `settleContinuationResult(kvRepresentation:)`）；llama.cpp fork（`--slot-attach` 从另一 slot 的 KV cells 起跑）。产品侧 GGUF runtime 未接 settlement handler，ES 锚定请求 fail-closed | 正文写"两侧各有载体机制、跨引擎不可迁移"；不写"未测" |
| G3 | mutation 分类学的机械化程度 | 2 例有机械对应、1 例只有词汇、1 例部分、1 例开放 | 保留论文原表述 |
| G4 | 外部效度 | **读数**单模型（A 路本地）、单机、无独立复现；**路径**不绑定模型来源——B 路云端 Agent 经 MCP 自声明身份结算，C 路采集桥把外部轮次写进 IS（不补 ES 结算）。载体与模型来源都不止一种，但没有跨模型、跨载体的成对读数 | 威胁句分"读数"与"路径"两句写；删"单 carrier / 单 model"的合成句 |
| G5 | §4/§5 与 v23 拆表不同步 | 论文仍写“settlements 行带 validity” | **下一轮先改**：改为事件账本 + `settlement_current_validity` 派生视图 |
| G6 | C7 的 content-addressability 论证 | 只在骨架里一句 | 正文补一段：值嵌在构成 id 的对象里（`ensureObject` 用内容摘要作 id，`payload_digest` 同源），故上游值变→id 变→下游重算 |

---

## 5. 载体侧：两个引擎各自的续算机制

前提：**"续算"不等于"KV 可移植"**。两侧各自把执行状态表示成自己能装载的形态，跨引擎时过界的是**值**，不是状态表示。

| 项 | MLX（产品路径） | llama.cpp（fork 实验路径） |
|---|---|---|
| 载体表示 | `NativeMLXPrefixPool.representation(forBranch:)`：生成结束前按 child ES id 导出，准入侧按同一 id 取用（`NativeMLX.swift:561`、`ContinuationSettlement.swift:262`） | `--slot-attach`：任务从另一 slot 的 KV cells 起跑，并在与已知前缀分歧处建 checkpoint（fork `llama-pr30970` `61e6777d9`；`tools/server/server-context.cpp` `find_attach`/`slot_attach`；metrics `slot_attach_total`/`slot_attach_tokens_total`） |
| 结算路径（非续算） | **共用**：`Service.swift` 两个 runtime 各注入 `informationTurnProducer`，chat 轮经同一 `settleTurn` 落结算（`HTTPServerChat.swift:422`） | 同左（GGUF 也传 producer）；受影响的是续算，不是结算 |
| 续算结算 | `settleContinuationResult(..., kvRepresentation:)`；`kvRepresentation` 可为 `nil`——无 KV 声明时结算照写，只是准入侧无 KV 权威可给 | 实验驱动 `es_probe.c`/`fork_cost.py`（`rq4-es-carrier-20261104/`），不经过产品结算门 |
| 免预填读数（1024 tok） | 产品 11 对：consuming 0.013–0.021 s（论文 §6.3） | 首轮 prefill 3.3–3.8 s → 子请求 0.74–0.78 s（`prompt_n=12`、`cache_n=1031`）；KV 拷贝 `cp_ms=0.1`（量程下限）；追赶 `tail_ms=10–70` |
| 父不受伤 | 由 child ES id 隔离 | `parent_lost_its_slot=false`；只拷后移除捐体 `pos_donor_after_rm=-1` |
| 保存/恢复 | prefix pool 表示 | 6 tok → 2.72 MB，restore 0.43 ms，续写与 cold 同文；401 tok → 268 MB，512 ctx 可恢复，256 ctx 返回 400（边界，如实报） |
| 子序列一致性 | 产品测试断言返回存量值 | 同捐体各臂（ref / 只拷 / cold / 复用拷贝）`child_toks` 逐 token 相同；同一捐体两个子请求都相同；**换捐体则尾两 token 变**（q4_0 p2、q4_0 p4、f16 p4 三组）——子请求跟的是被交给它的状态，不是它复述的提示 |
| 产品接线 | 已接：`HTTPServerResponses` 的 `continuationSettle`，KV 走 `NativeMLXPrefixPool` | **已接（2026-11-08 夜）**：`ManagedGGUFRuntime` 传 `continuationAdmission`（`recoverForContinuation(modelPath: info.path)`）与 `continuationSettlement`（`makeContinuationSettlementHandler(modelPath:) { _ in nil }`）——同一结算权威，KV 声明为 nil；分支快照仍显式拒绝（`forkBranchHandler` 抛错）；零调用消费与 managed pipeline 仍是 MLX 独占 |
| 跨引擎续算 | KV 不可移植；值可过（准入不比对消费者身份，`ISAdmission.admit` 明确注释） | 同上；接线后 GGUF 侧可**按值**续算 MLX 落的结算，反之亦然——KV 声明为 nil，故只是无 KV 权威 |

一句话：**两侧载体各自成立且各自有读数；跨载体只有值能过。**

nil-KV 的机械前提已单跑验证（`work/kvcheck`，隔离临时库）：结算写入后 `settlement_validity=valid`、`recovered_value=carried-value`、`verified_bindings=1`、`kv_bindings=0`——即 GGUF 侧续算按值成立，KV 恢复没有权威（`ISAdmission.Admitted.kvBindings` 注释即此语义）。

### 5.1 模型来源：三条入口（G4 的真实边界）

| 入口 | 谁在算 | SimiGo 记什么 | 锚点 |
|---|---|---|---|
| A 本地引擎 OpenAI 兼容 | 本机 MLX / llama.cpp | 每轮 demand、检索、结算、身份绑定、advancement | `BackendSelection.swift:7`（`mlx`/`llamaCpp`）、`Service.swift:920–938` |
| B MCP 生命周期 | **Agent 自己的云端 API**；SimiGo 不代理模型请求 | `simigo_es_settle` 写入的结算；`model`/`tokenizer` 由 Agent 声明 | `HTTPServerMCP.swift:662`（`settleTurn` 收 `.init(model:tokenizer:)`）、`docs/AGENT-ACCESS.md` §3.2–3.4。边界：MCP 面 `reusable_answer` 恒为 null——云端 Agent 能结算，但**复用门在 Chat/Responses 线上**，不经 MCP 回给外部 Agent |
| C 采集桥（Qoder） | 外部 Agent 云端 API，事后采集 | 外部轮次问答写入 IS 检索面；**不补 ES 结算**（"事后补一个 ES 就是把观测冒充执行"） | `ExternalTurnSink.swift:1–26`、`recordExternalTurn` |

结论：**结算路径不绑定模型来源，读数绑定。** §6 的 11 对全部来自 A 路一个本地模型；B、C 两路已实现但未跑成对读数。与 G4 同族的一条口径：B 路的 `model` 是**声明**（溯源），不是核验——所以在论文里它属于 C10 的"缺席身份不是通配"一侧，不构成"多模型已验证"。

由此，论文里的威胁句要分四件说，不能合成一句"单 carrier / 单 model / 未测"：

1. **两侧都实现了 continuation 的载体机制**，不是只有一边。
2. **产品层只有 MLX 接了结算路径**；GGUF 侧 fail-closed 是显式设计（不伪造分支元数据），不是漏测。
3. **跨引擎续算未做且 KV 层做不了**——这是 ES/IS 的论点（过界的是值），不是未被覆盖的实验缺口。
4. **模型来源不止一种**（A 本地两引擎 / B 云端 Agent 自声明 / C 采集桥只写 IS），但**成对读数只有 A 路一个模型**——"未测"的是跨模型读数，不是路径。

---

## 6. 下一轮顺序（按依赖）

1. §4/§5 的 v23 措辞修正（G5）——先让论文与当前 schema 自洽。
2. Arm A/B 读数进 §7 表（G1）——与既有 11 对并列，不合并样本。
3. C7 段（G6）——源码事实，无需新实验。
4. 附录追溯矩阵 P→C→测试→读数——用本文件 §2/§3 直接生成；载体一栏用 §5。
5. 再动 11k 词全文改写。
