# B0 · ES/IS 术语表（中英对照 · 定义边界 · 实现映射）

**Status**: B0 ACCEPTED（2026-11-05 用户裁定）；本版含裁定修订——OQ 收敛为三项（OQ-1 / OQ-3 / OQ-8）、OQ-2 关闭、OQ-3 拆分、命名终定。术语对应关系已冻结；未证明的语义边界以 §3 为准，不再扩充
**Date**: 2026-11-05
**授权边界**: 本文件仅新建于路线 B 本地材料；未修改任何冻结契约、`OPEN_SOURCE.md`、路线 A 文件、历史实验记录或验收证据
**上游路线文档**: `docs/upstream/DEEPSEEK_ES_IS_SEMANTIC_ROUTE_20261105.md`（§7 B0）

**命名裁定（2026-11-05，用户）**：ES/IS 指 **Execution State / Information Space**。IS 沿用仓库既有名称（信息空间），不引入 "Information State"；路线文档标题已同步修正。

---

## 0. 使用规则与状态图例

定义状态不是成熟度评级，而是告诉后续研究者哪些词可以直接使用、哪些是 B1 论证对象：

| 状态 | 含义 |
|---|---|
| 【核心定义】 | 语义层定义可直接使用；路线文档与提案层采用 |
| 【已建立 · 待形式化】 | 仓库已有同名/等价机制与现行规则；形式化定义由 B1 给出 |
| 【新术语】 | 本表新引入；仓库无对应名称（概念可能有部分承载者，如实标注） |
| 【区分性术语】 | 为钉死边界而设，本身不是一项执行语义 |
| 【机制原则 · 待形式化】 | 方向已采纳为原则，形式化规则待 B1 |

**冻结边界**：本表只冻结"术语对应关系与现行语义"，不冻结尚未证明的语义边界（B1 处理，见 §3）。

**冲突规则**：冻结契约与权威实现 > 本表 > 路线文档。发现冲突时回改本表，不改契约。

---

## 1. 三个规范性语义边界（复核裁定要求）

### 1.1 ES ≠ Execution Snapshot ≠ Carrier

- **Execution State**：管理执行进展、分支关系、续接与结算判定的**权威状态**。
- **Execution Snapshot**：某一时刻对运行状态的**物理记录**（载体层产物）。
- **Execution Carrier**：承载执行信息的**具体机制**（KV、sequence、slot、文件、数据库）。

判据：**具备快照能力 ≠ 具备 ES**。代码已有此区分的实例：`EngineExecutionStateSnapshot` 是"纯数据快照……零行为、零 IO、零新执行语义——不参与 reuse/restore/驱逐任何决策"（`SimiGo/Inference/ExecutionStateProjection.swift:4-9`），而 ES 的权威体现在执行控制面（`ExecutionControlling` 五动作：execute / continue / checkpoint / restore / fork，协议见 `docs/architecture/EXECUTION_RUNTIME_DESIGN_V16.md:24-30`，实现 `SimiGo/Inference/ExecutionControlling.swift:78` 起）。

### 1.2 Settlement / Settled Result / Settlement Record 三分

- **Settlement** = 结算行为（判定动作）。
- **Settled Result** = 结算产出的结果本体。
- **Settlement Record** = 记录结算事实及其依据的记录。

仓库契约已固化"入库 ≠ 结算 ≠ 可检索"三分：IS 外部轮次契约 §1 把 recorded / committed / retrievable 定义为三个独立状态，并明言"把「入库」「结算」「可检索」当同一个开关是此前 Codex 污染事件的根因之一"（`docs/architecture/IS_EXTERNAL_TURN_CONTRACT_20261030.md:24-37`）。

**归属裁定（2026-11-05，OQ-2 RESOLVED — semantic ownership established; implementation mapping evidenced）**：

| 对象 | 归属 | 含义 |
|---|---|---|
| Settlement Act | ES | 执行结算决策及状态转换，拥有结算行为的权威 |
| Settled Result | IS | 已结算、可供后续续接使用的信息 |
| Settlement Record | IS | 记录结果的来源、依赖、版本及有效性依据 |
| Settlement Outcome | ES → IS | ES 执行结算后产生、并由 IS 接收和保存的结果 |

限制（编入 B1 R1/R2 的语义地位）：IS 保存结算结果**不代表 IS 决定某项执行是否已完成**；ES 拥有结算行为权威**不代表 ES 必须永久保留已结算的全部结果或旧 KV Cache**。`settleValidatedResult` 等实现位置是佐证，不是契约定义本身。

### 1.3 Carrier Independence 分两层

- **语义层独立性**：ES/IS 的定义不引用任何特定 carrier —— **设计原则**（已采纳）。
- **实现层可迁移性**：具体结果跨 carrier 恢复 —— **实验命题**，逐载体、逐迁移路径验证（对应 Track B 的 representation transition / migration / reattach 实验线，`docs/research/EXECUTION_STATE_RESEARCH_STORY_20260922.md` F4–F5）。

两层不得混用；本表与路线文档均不得把实现层命题写成已证结论。

---

## 2. 术语条目

### 2.1 执行状态 · Execution State (ES) —【核心定义】

**正面定义**：管理一次执行谱系的进展、分支关系、续接与结算判定的权威状态；回答"从哪里继续、存在哪些分支、哪些结果已结算"。它是判定权威，不是某个时刻的物理记录。

**非定义**：不是运行状态快照（见 2.10）；不是载体；不绑定单一引擎的 KV 生命周期；与 `ExecutionStateLabel`（STATE_A/B/C 层驻留负载标签，`Packages/SimiGoRuntime/Sources/SimiGo2Experimental/ExecutionState.swift:5`）无关——命名巧合，禁止混读。

**实现对应**：`ExecutionStateRecord`（position / anchor / prefix / parentID / continuationID，`SimiGo/App/ExecutionStateGraph.swift:39-53`）；`protocol ExecutionControlling` 五动作面（`EXECUTION_RUNTIME_DESIGN_V16.md:24-30`、`ExecutionControlling.swift:78`，NativeMLX 依从 `:96`）；五身份分离红线 sessionID ≠ executionID ≠ kvFingerprint ≠ checkpointID ≠ traceKey（`EXECUTION_RUNTIME_DESIGN_V16.md:15`；`SimiGo/Inference/ExecutionLineage.swift:4-6`）。测试：`ExecutionStateGraphTests`、`ExecutionControllingTests`、`ExecutionLineageTests`。

**裁定（2026-11-05）**：OQ-2 RESOLVED——Settlement Act 归 ES 权威（归属表见 §1.2）。

### 2.2 信息空间 · Information Space (IS) —【核心定义】（命名已裁定）

**正面定义**：已结算信息及其可恢复性、来源、版本、依赖和有效性依据所构成的权威状态。关键能力不是存储，而是判断某项结果在新的执行生命周期中是否仍然成立、是否可被恢复使用。

**非定义**：不是数据库；不是结果缓存；不是对话历史存储——存储只是载体（见 2.9）；"已在数据库里"不等于已结算、更不等于可检索（IS 契约 §1 三分）。

**实现对应**：权威实现 `SimiGoESISDatabase`（`IS_EXTERNAL_TURN_CONTRACT_20261030.md:4`）；IS 三状态 recorded / committed / retrievable（同文件 §1:24-37）；运行时 `InformationSpaceRuntime`（`SimiGo/Inference/InformationSpaceRuntime.swift:17`）；结算门语义"may only become a settled **Information-Space** record"（`SimiGoSettlementAuthority.swift:5-6`）；复用四条件（`docs/AGENT-ACCESS.md:102-109`）。测试：`MCPInformationSpaceTests`、`SimiGoExternalTurnContractTests`。

**OPEN**：OQ-8（IS 的完整语义定义目前散布于多份契约，B1 归拢）。

### 2.3 结算 · Settlement —【已建立 · 待形式化】

**正面定义**：将一次执行的产出判定为"可成为后续续接权威信息"的 fail-closed 行为：必须先通过唯一前置结算门、先于任何写入；一个执行 state 只结算一次；换模型必须新开 state；声明依赖必须是载体中已封存的对象 id，未封存则整次拒绝。

**非定义**：不等同于生成完成（`finish_reason == "length"` 不结算；流式须 `[DONE]` / `response.completed`，IS 契约 §3.1:78-84）；不等同于写入数据库（recorded ≠ committed）；`simigo_es_fail` 只落审计、不产生结算（`AGENT-ACCESS.md:227`）；不是缓存命中。

**实现对应**：`SimiGoSettlementAuthority`（`SimiGoSettlementAuthority.swift:5-12`："A semantic result produced by any producer (model, tool, or import) may only become a settled Information-Space record after this type returns successfully"；"the caller must invoke this BEFORE any write/sign, so a thrown error means nothing was persisted (fail-closed)"）；结算前置条件（`AGENT-ACCESS.md:229-240`）；写入族 `recordNativeSettlement*`（`SimiGoESISDatabase.swift:1568/1756/1788`）；轮次结算 `commitChatTurn`（:3283）/ `verifyExternalTurn`（:3425）。跨路径恒等：`CrossPathSettlementIdentityHTTPTests`（同一声明集合只结算一次）。

**裁定（2026-11-05）**：归属划分 RESOLVED（§1.2）。结算键的一般化并入 B1（R1 参数化方向，随 OQ-8 归拢；现行键 `(session_id, request_id, source_kind)` 见 `IS_EXTERNAL_TURN_CONTRACT_20261030.md:119`）。

### 2.4 已结算结果 · Settled Result —【已建立 · 待形式化】

**正面定义**：通过结算判定后的结果本体：语义完整（按 wire 判据）、依赖完整（闭包内地址已封存）、来源与生产者身份已绑定。

**非定义**：不等同于"生成完成后的文本"（不完整/失败不产生结算）；不等同于缓存条目（缓存命中没有结算身份与依据）。

**实现对应**：`SettledResult` 类型（`SimiGoSettlementAuthority.swift:20-28`，仅携带已验证字段与 payloadDigest）；轮次层 committed 行（`turn_state='committed'` + `verified_at`）；`validationStatus: "VALID"`（`NativeDeclarativeResultContract.swift:495`）。

### 2.5 结算记录 · Settlement Record —【已建立 · 命名归拢待 B1】

**正面定义**：记录结算事实及其依据（来源、版本、依赖、有效性）的权威记录；是"为什么这个结果曾经/仍然算数"的承载，区别于结果本体。

**非定义**：不是结果本身；不是审计日志（es_fail 落审计但不产生结算——审计与结算记录是两类，`AGENT-ACCESS.md:227`）。

**实现对应**：现行三种形态——`settlements` 表（含 `validity` 列，`SimiGoESISDatabase.swift:267`）；`SettlementReceipt`（`ExecutionStateGraph.swift:71`）；`SimiGoSettlementIdentityBinding`（producer.model_identity / producer.tokenizer_identity，`SimiGoSettlementIdentityBinding.swift:16,34-37`）。另有消费侧 `SettlementConsumptionEntry`（`SimiGo/Protocol/SettlementConsumptionEntry.swift:37`）。

**归拢去向（2026-11-05 裁定）**：三种形态（settlements 表 / receipt / identity binding）是否统一收拢于单一 "Settlement Record" 术语，随 OQ-8（IS 总定义归拢）一并处理，不单列 OPEN。注意身份绑定的已声明边界："hold no signature, no trust anchor and no dependency-closure proof; signed provenance remains unimplemented"（`SimiGoSettlementIdentityBinding.swift:11-13`）。

### 2.6 可靠结算结果 · Reliably Settled Result —【新术语】

**正面定义**：在恢复时点仍通过有效性判定的已结算结果——有效 + 依赖闭包逐项完整有效 + 身份绑定一致。它是 ES/IS 研究的核心对象：执行生命周期结束后仍具备可靠续接价值的单位。

**非定义**：不等同于缓存命中；不等同于历史记录；不等同于 checkpoint。

**实现对应**：名称不存在于代码；概念由 IS 准入的有序 fail-closed 检查单承载（`SimiGoISAdmission.swift:92-99`：resolve newest settlement → receipt → digest 完整性 → settlement 自身 validity → 上游依赖闭包逐项 present AND valid → producer model/tokenizer 身份绑定 → recover value）。

**裁定（2026-11-05）+ OPEN**：可靠结算**不是一次性认证标签，而是有条件的可恢复资格**——恢复/续接时逐项重判（记录可信、结果完整、依赖闭包满足、来源/版本/有效性依据成立、无失效变化）；七步检查单是实现依据，**不提升为完整、普遍适用的定义**。OQ-1（充分必要集）保留为三项 OPEN 之一。

### 2.7 续接 · Continuation —【核心定义】

**正面定义**：依据 ES 在新的执行生命周期中恢复执行进展并继续计算的行为。以准入判定为先（typed fail-closed refusal，任何生成之前）；恢复值来自权威存储而非客户端；结算与准入绑定同一组已验证值；结算产出的 child ES state 是下一次续接的准入锚。

**非定义**：不等同于重放（replay）；不等同于上下文拼接；不等同于"从最近一行接着写"（结算键不是「最近一行」，IS 契约:119）；准入失败绝不静默降级为普通生成。

**实现对应**：`ContinuationAdmissionOutcome` —— "recoveredValue is the semantic value recovered from a VERIFIED IS settlement; …the value that reaches the model comes from the authoritative store, not the client"（`SimiGo/Protocol/ContinuationAdmission.swift:4-7`）；"The settlement gate binds the produced result against exactly these values; it never re-derives them from mutable execution state"（:9-12）；opt-in 门——仅当请求显式携带 `previous_es_state_id`，缺省时"dispatch path byte-for-byte unchanged"（:56-59）；机器可读契约终端与"两类拒绝永不互扮"（`ContinuationSettlement.swift:4-23`）；`childESStateID` "returned to the client so the NEXT continuation admits through it"（:105-106）；无伪造结果通道（:123-126）。管线：`SimiGoManagedContinuation` P1→S→G→P2（`SimiGoManagedContinuation.swift:96,195`）。测试：`ResponsesContinuationAdmissionGateTests` 等。

### 2.8 分支 · Branch —【已建立 · 身份层级待明确】

**正面定义**：具有明确来源（parent provenance）与独立执行边界的执行谱系分叉。显式触发，不做隐式 fork；不做 merge（KV 不可合并——合并=选边）。

**非定义**：不是 UI 层面的会话分组；不等同于引擎原生 sequence copy——无原生 fork 的载体上，分支语义层仍须成立（路线 B 前提），只是实现层可迁移性受限。

**实现对应**：fork v1 已发布（`docs/decisions/BRANCH_FORK_PROTOCOL_DRAFT.md:3-6`：`forkSessionBranch` / `deleteSessionBranch` / `listSessionBranches` + `POST /v1/branches/{fork,delete,list}` + `fork_from_branch` 内联触发）；能力边界已实证：磁盘 checkpoint fork（双架构）、内存 `KVCache.copy()` 双向隔离、fork 增量 prefill、fork/cold greedy 逐字一致（同文件:9-10）；显式触发原则（:16-19）；不做 merge（:37）。`BranchForkEvent`（`ExecutionLineage.swift:32`）。测试：`LOCALBBranchLifecycleTests`、`SimiGoTests/BranchFork/`。

**裁定（2026-11-05，OQ-3 拆分）**：

- RESOLVED：Branch 不以 KV Copy 为定义条件——语义层"分支"不得依赖 KV copy 存在。
- RESOLVED：当前实现的 fork 属于 storageKey 操作层。
- OPEN（OQ-3 保留部分）：Semantic Branch ↔ Execution Lineage 的正式身份关系；generation 的生命周期语义由 ES lifecycle 决定，不得由 LOCALB 的存在性检查替代（LOCALB 审计 W1，用户引述）。

层级区分：

| 层级 | 定义边界 |
|---|---|
| Semantic Branch | ES 中具有独立续接意义的执行分支 |
| Execution Lineage | 执行之间的来源、派生关系 |
| Storage Key | 当前实现用于定位或区分存储对象的标识 |
| KV Copy | 可选的载体层操作，不构成 Branch 的语义定义 |

身份层级现状（如实钉死）：`BranchForkEvent` 是 "**storageKey 级**分支寻址……**不是** execution→execution lineage（当前 fork 不产生执行级父子）"，且"外审十一轮 P2-2：语义钉死，防误读为执行血统"（`ExecutionLineage.swift:28-31`）；执行级 parentExecutionID 留待 F1/上游原语（`EXECUTION_RUNTIME_DESIGN_V16.md:53`）。注意：该钉死只证明当前实现的 fork 层级，**不能**推出所有语义分支等于 storageKey。

### 2.9 载体 · Carrier —【核心定义】

**正面定义**：物理承载机制：KV cache、sequence、slot、文件、数据库、对象存储等。载体只承载、不 reinterpret；它不是执行或信息的最终权威。

**非定义**：载体能力差异（有无原生 fork、有无 in-memory snapshot）影响性能与实现层可迁移性，不影响 ES/IS 语义层成立性；数据库只是载体。

**实现对应**：`CarrierObject` / `CarrierReport` / `carrierReport(deepVerify:)`（`SimiGoESISDatabase.swift:856,863,1100`，MARK "Information-Space physical carrier" :851）；"the database is only a carrier, so it never reinterprets the bytes"（:853-855）；telemetry `carrier` 字段与 `information_space` 磁盘对象存储（`AGENT-ACCESS.md:54`）；`R_Reference_v1` reference carrier（`README.md:217`）；KV/sequence 层 `kvFingerprint`（V16:54）、`PrefixMemoryPool`；迁移/reattach 实验线（`ExecutionContinuityCoordinator.swift`；研究故事 F5）。

### 2.10 执行快照 · Execution Snapshot —【区分性术语】

**正面定义**：某一时刻对运行状态的物理记录；载体层产物，可持久化、可载入。

**非定义**：快照 ≠ ES；具备快照能力不等于具备 ES（判据见 §1.1）。`EngineExecutionStateSnapshot` 是"纯数据快照……零行为、零 IO、零新执行语义——不参与 reuse/restore/驱逐任何决策"（`ExecutionStateProjection.swift:4-9`）；`ExecutionCheckpoint` 是状态的 durable 固化、"save/checkpoint：当前 closure durable 固化……不新建 semantic state"（V2.1 参考架构 §2）。

**实现对应**：`SimiGoSnapshotContract`（immutable declared/final、`used ⊆ declared`、replayability 连言，`SimiGoSnapshotContract.swift:3-15`）；`ExecutionCheckpoint`（`ExecutionStateGraph.swift:59`）；checkpoint/restore 动作（`ExecutionControlling.swift:85-87`）。测试：`SimiGoSnapshotContractTests`、`SessionCachePersistenceTests`。

### 2.11 依赖闭包 · Dependency Closure —【已建立 · 形式化待 B1】

**正面定义**：判断一个已结算结果能否安全复用的依赖范围：从该结算沿依赖边的传递闭包；复用条件是闭包内**每一成员**都存在且有效。

**非定义**：不是"对话上下文"；不是直接依赖的浅层列表（是传递闭包）；未封存的依赖地址使整次结算被拒（`AGENT-ACCESS.md:235-236`）。

**实现对应**：`upstreamDependencyClosure(ofSettlement:)` 递归 CTE（`SimiGoESISDatabase.swift:5654`）；`appendDependency` / `DependencyEntry`（:1059, :894，含 contentAddress / revision / reason / recordedAt）；准入闭包检查（`SimiGoISAdmission.swift:149-160`：dependencyMissing / dependencyInvalid）；失效沿闭包传播（`invalidateSourceFile` → `markSettlementsInvalidInTransaction`，:4943-4982，"Unrelated settlements keep validity='valid'"）；HTTP `GET /v1/simigo/is/dependency`。

**去向（2026-11-05 裁定）**：OQ-4 并入 B1 恢复时约束 C-dep（`B1_ESIS_MINIMAL_FORMALIZATION_20261105.md` §6）；闭包充分必要集的进一步完备化随 OQ-8 归拢，不单列 OPEN。

### 2.12 有效性依据 · Validity Basis —【新术语（谓词已建立）】

**正面定义**：判断既有结算在新执行生命周期中是否仍然成立的依据集合。现有实现中的依据成分：结算行 validity 状态、上游依赖闭包逐项有效性、来源文件失效检查、生产者 model/tokenizer 身份绑定。

**非定义**：不是 TTL / 过期时间（仓库无 TTL/expiry 概念）；失效是显式判定的（来源文件变更 → 闭包传播失效），不是定时衰减。

**实现对应**：`settlements.validity`（'valid'/'invalid'，`SimiGoESISDatabase.swift:267,5102`）；失效传播（:4949）；准入拒绝 `Refusal.invalidated`（`SimiGoISAdmission.swift:146-148`）；引用门——invalid 的检索结算不可被新结果引用（`HTTPServerMCP.swift:618-620`）；语义说明"这是捕捉「来源文件已变」的依赖检查"（`AGENT-ACCESS.md:105-106`）。

**去向（2026-11-05 裁定）**：OQ-5 并入 B1 恢复时约束 C-val；V(ρ) 依据集的未来扩展（模型/量化/采样参数变更、unknown 第三态）随 OQ-8 归拢，不单列 OPEN。无 TTL 是已验证缺省。

### 2.13 语义充分性 · Semantic Sufficiency —【新术语（部分覆盖存在）】

**正面定义（工作定义）**：一项已结算结果不依赖其产生时的执行上下文残余、即可支撑后续续接的性质——"结果本身足以作为续接依据，不需要附带未结算的隐式状态"。

**非定义**：不等同于结果非空（`Refusal.emptyValue` 只是下界）；不等同于格式合法。

**实现对应（部分覆盖，无统一名称）**：`NativeProducerResultContractGate.validateBeforeSettlement`（拒绝类：unknown constraint / missing binding / canonicalization failure / digest-derivation mismatch，`SimiGoSettlementAuthority.swift:30-33`）；wire 完整性判据（IS 契约 §3.1）；复用门要求载荷含非空顶层 `content`（`AGENT-ACCESS.md:224`）。

**去向（2026-11-05 裁定）**：OQ-6 暂缓，不作 OPEN 追踪。**占位纪律不变**：判据未决前，本词只作占位，不得用于任何强宣称（B1 R2 的 complete(r) 同此纪律）。

### 2.14 选择性重执行 · Selective Re-execution —【机制原则 · 待形式化】

**正面定义**：已结算且有效 → 恢复使用；缺失、失效或依赖变化 → 仅对失效闭包内部分重执行；重执行决策必须显式门控，绝不静默重生成、不做"尽力而为"的近似回答。

**非定义**：不是无条件重新生成；不是"缓存未命中就重算"——重执行范围由失效的依赖闭包决定（这是与缓存语义的本质区别）。

**实现对应（部分）**：`SimiGoRecomputePolicy`（`never` 默认 | `allow_safe_recompute`；"a resumed continuation whose inputs no longer match the anchored evidence is refused instead of silently regenerated"，`SimiGoManagedContinuation.swift:3-10`；P1 期锚定证据不匹配 + policy 不允许 → 拒绝，:234-245）；`ExecutionDecision {extend / restore / rebuild / fork}`（`SimiGo/Inference/ExecutionPolicy.swift:8-12`）；复用四条件不满足即"走正常生成，不做「尽力而为」的近似回答"（`AGENT-ACCESS.md:102-109`）；`SettlementConsumptionEntry.allowRecompute` 与 `recompute(reason:)`。

**去向（2026-11-05 裁定）**：OQ-9 并入 B1 R3——范围公式 `reexec(ρ, t)` 已作为骨架定义给出（`B1_ESIS_MINIMAL_FORMALIZATION_20261105.md` §4）；最小重执行集的算法化随后续证据深化，不单列 OPEN。

### 2.15 载体独立性 · Carrier Independence —【两层定义】

**正面定义**：分两层——(i) **语义层独立性**：ES/IS 的定义不引用任何特定 carrier（设计原则，已采纳）；(ii) **实现层可迁移性**：具体结果跨 carrier 恢复（实验命题，逐载体/逐迁移路径验证，见 §1.3）。

**非定义**：不是"所有载体能力等同"；不是已完成的跨引擎实验结论（现有跨路径恒等证据限于单引擎内）。

**实现对应**：原则已在代码中显形——数据库不 reinterpret 字节（`SimiGoESISDatabase.swift:853-855`）；KV 复用权威来自 IS 记录而非引擎："Empty means the settlement claimed no prefix representation, so the continuation **has no authority to reuse KV state**"（`ContinuationAdmission.swift:17-20`）；表示声明与载体诊断分离（`README.md:140-145,217`）；representation transition / migration / reattach 实验层（研究故事 F4–F5）。

**去向（2026-11-05 裁定）**：OQ-7 暂缓，留待实验证据阶段，不作 OPEN 追踪。

---

## 3. OPEN 问题清单（2026-11-05 裁定后收敛为三项）

**裁定记录（2026-11-05）**：B0 ACCEPTED。OQ-2 **RESOLVED** — semantic ownership established; implementation mapping evidenced（归属表见 §1.2）。OQ-3 拆分：两项 RESOLVED（Branch 不以 KV Copy 为定义条件；现实现 fork ∈ storageKey 层）+ 一项 OPEN（保留于下表）。OQ-4 / OQ-9 并入 B1（恢复时约束 C-dep、R3 范围公式 `reexec(ρ, t)`）；OQ-6 / OQ-7 暂缓，不作 OPEN 追踪。IS 命名歧义关闭（命名裁定：IS = Information Space）。术语表不再扩充。

| # | 涉及术语 | 问题 | 现状与证据边界 | 处理时点 |
|---|---|---|---|---|
| OQ-1 | 2.4 / 2.6 | 可靠结算的充分必要集与恢复时重判规则 | 可靠结算是**有条件的可恢复资格**，非一次性认证标签；七步检查单为实现依据，不提升为完整、普遍适用的定义 | B1 已按条件资格形式化（R6）；完备化保留 OPEN |
| OQ-3 | 2.8 | Semantic Branch ↔ Execution Lineage 的正式身份关系；generation 的生命周期语义（由 ES lifecycle 决定，不由 LOCALB 存在性检查替代） | 已 RESOLVED：Branch 不以 KV Copy 为定义条件；现实现 fork ∈ storageKey 层。身份关系本身 OPEN——实现映射不得由 storageKey 钉死外推 | B1 R5 显式留空；B1+ |
| OQ-8 | 2.2 | IS 语义总定义的归拢 | 命名已定（Information Space）；现行语义散布于 ESIS 数据库契约、外部轮次契约、AGENT-ACCESS 规则，无单一总定义文档 | B1 后续 |

---

## 4. 权威来源与冲突规则

本表收编下列来源的**现行语义**，未修改其中任何文字：

1. `docs/architecture/IS_EXTERNAL_TURN_CONTRACT_20261030.md` — IS 外部轮次数据契约（§1 三状态、§3 写入与结算规则、§4 并发不变量）
2. `docs/architecture/EXECUTION_RUNTIME_DESIGN_V16.md` — 执行运行时规格（五身份分离、能力 API 面、数据/决策分离）
3. `docs/decisions/BRANCH_FORK_PROTOCOL_DRAFT.md` — 分支 fork v1 已发布协议与实证边界
4. `docs/AGENT-ACCESS.md` — §2.4 复用四条件、§3.4–3.6 结算规则
5. `OPEN_SOURCE.md` — 公开证据边界（本表遵守：不宣称 universal / backend-independent）
6. 代码层权威实现：`SimiGoESISDatabase.swift`、`SimiGoSettlementAuthority.swift`、`SimiGoISAdmission.swift`、`SimiGoManagedContinuation.swift`、`ContinuationAdmission.swift`、`ContinuationSettlement.swift`、`ExecutionControlling.swift`、`ExecutionLineage.swift`、`ExecutionStateProjection.swift`
7. `docs/research/EXECUTION_STATE_RESEARCH_STORY_20260922.md` — Track B 生命周期实验线（证据来源，非契约）

**冲突规则**：冻结契约与权威实现 > 本表 > 路线文档。发现冲突 → 回改本表，不改契约。

**逐字引用核验记录**：本表中的逐字引文均经直接读源核验（`SimiGoSettlementAuthority.swift`、`SimiGoISAdmission.swift:85-169`、`SimiGoESISDatabase.swift:845-894`、`ExecutionLineage.swift:1-45`、`ExecutionStateProjection.swift:1-20`、`ContinuationAdmission.swift:1-62`、`ContinuationSettlement.swift:1-160`、`IS_EXTERNAL_TURN_CONTRACT`、`EXECUTION_RUNTIME_DESIGN_V16`、`BRANCH_FORK_PROTOCOL_DRAFT`、`AGENT-ACCESS.md` 两段）；其余 file:line 定位来自全仓扫描代理，引用前建议复核具体行。
