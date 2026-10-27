# C 阶段设计：失效后的策略与文件变化窗口（设计稿 v2.2，已裁定，未实施）

状态：**设计合同，仅设计，不改产品行为**。owner 2026-10-27 裁定：阶段 B 保持 GO 且 B-7 / C-0 证据边界不扩大；#28 保持 pending；C 的八项设计决策已裁定，但**未授权生产实现、数据库迁移、清理测试残留根或调整 KV 目录行为**。

修订记录：

- v1（2026-10-27）初稿：三输入判定表、422≠可重算、TOCTOU 可保证边界与残余风险。
- v2（2026-10-27）依 owner 裁定：锚点改为「最近的有效祖先 + 五项谓词 + 禁止无条件回退」；引入显式重算策略，不与 `allow_recompute` 合并；新增血缘/审计分离；补残留根影响；指出重算接口缺口。
- v2.1（2026-10-27）设计自查：锚点精确到「状态 + 结算行」；新增事务边界两阶段；`model_calls` 与 `settlements_written` 分开计量。
- v2.2（2026-10-27，本稿）**并入八项正式裁定**：①策略字段定名 `recompute_policy` 及冲突规则；②`source_not_valid` 有条件纳入且必须保留内部原因；③审计关系独立承载、P2 失败零写入；④远祖合格即可重算但须语义充分；⑤as-of 输入快照持久化并进响应；⑥C v1 不引入 watcher 但必须落实新鲜度门槛；⑦`DERIVED_CONSUMPTION` 有条件可作锚点；⑧首版不强制互斥、允许并行分支。§7 事务合同按 owner 给的 P1 / G / P2 顺序重写为验收合同。

事实基线（本轮已取证，见 `ACCEPTANCE-20261026-BUILD-97043902.md` §3.27）：

- 失效只由**显式生产重扫**触发（`PUT/POST /v1/simigo/roots`、`/v1/simigo/reconcile`、MCP、env bootstrap）；没有文件系统 watcher。
- 重扫后的失效会级联：源结算 → 消费者结算 → retrieval 行；上游闭包整体 invalid（§3.27 两段 13/13 判据）。
- 消费入口已把准入拒绝分成 422 + 稳定码；来源失效时 `allow_recompute=true` **仍拒绝**，这是 B 的既定边界，C 不得扩大它。
- 受管续跑入口（`previous_es_state_id` → `admitContinuation` → `settleContinuation`）目前只有**一个**拒绝桶：422 `INPUT_ADMISSION_REFUSED`，`detail` 为自由文本，无分码、无重算许可（[ContinuationSettlement.swift:86](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Protocol/ContinuationSettlement.swift#L86)、[ContinuationAdmission.swift:46](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Protocol/ContinuationAdmission.swift#L46)）。C 的「保留内部具体原因」（裁定 2）必须先解决这个扁平桶，否则无法按原因判定。
- 消费的 canonical 依据读**库内摘要**（`canonicalDemandInput` → `file_contents`），未重扫期间仍命中旧值（[SimiGoESISDatabase.swift:1961](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L1961)）。
- 依赖闭包的读取**没有 kind 过滤**：`dependency_edges` 表本身有 `kind` 列（[schema:176](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L176)），但 `upstreamDependencyClosure` 取该表中所有 `to_settlement`（[:4126](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L4126)），`transitiveDependents` 同样不过滤（[:3524](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L3524)）。这条事实是裁定 3 选择独立审计记录的硬理由。
- **有效性挂在结算行上，不在 ES 状态上**：`execution_states` 只有 `state_id/parent_id/...`，没有 validity 列（[schema:168](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L168)）；`validity` 是 `settlements` 的列（[schema:208](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L208)）。同一状态可有多条结算行（原生生成、`DERIVED_CONSUMPTION`、`IS_RETRIEVAL`、`MIGRATED_LEGACY`），所以锚点必须是 `(anchor_state_id, anchor_settlement_id)`。
- 现有请求形状错误统一落 422 `invalid_entry`（[SettlementConsumptionEntry.swift:253](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Protocol/SettlementConsumptionEntry.swift#L253)），**没有** 400 形态。裁定 1 要求冲突返回 400，属于新增终端形态，见 §4.3 注记。

---

## 1. 两条路径的边界

| | 消费路径（阶段 B，GO） | 受管续跑/消费路径（阶段 C，设计已裁定） |
|---|---|---|
| 入口 | `/v1/responses` 的 `settlement_consumption` | `/v1/responses` 的 `previous_es_state_id` 与 C 作用域内的消费请求 |
| 许可字段 | `allow_recompute`（布尔，B 语义固定） | **`recompute_policy`**（默认 `never`），不复用、不扩大 `allow_recompute` |
| 失效来源 | 一律拒绝（本轮已真机证明） | 可进入重算候选，但须同时满足 §3 + §4 + §7 全部条件 |
| 产出 | 消费既有结算，或按 B 许可重算并回报理由 | 按合格锚点重算成**新分支**，否则终止 |

`recompute_policy` 只存在于 C 的显式受管续跑/结算消费请求对象里，**不是**影响所有普通聊天请求的全局开关。

---

## 2. 五条不变量（最高优先级，任何实现都不得违背）

1. 失效结算**永不复活**：任何路径都不得把 `validity` 从 `invalid` 改回 `valid`。
2. 新结果只能来自**本轮明确、有效、可追溯**的输入；旧失效结算只能作审计对象，不得充当可信输入。
3. **三项关系分离**：执行血缘（`parent_id`）、真实计算依赖（有效输入/结算的依赖边）、失效审计（被替代关系），三者不得混成一张图。
4. **计量分离**：生成前拒绝可以是 `model_calls=0`；生成后 P2 失败必须记 `model_calls>0`、`settlements_written=0`，不得称为「零生成」。
5. **不得以未核实的陈旧输入生成**：仅凭库内旧摘要不足以放行（裁定 6）。

---

## 3. 拒绝分类与重算资格

分类取自准入层的内部具体原因，不用 HTTP 码做决策（同一个 422 里装着性质完全不同的情况）。

| 类别（内部原因） | 是否可进入重算 | 语义 |
|---|---|---|
| `invalidated` 且原因已确认为**可恢复的输入失效**（如文件内容确实变化） | **有条件候选** | 裁定 2：必须同时满足当前输入已重核实 + 可建立可信起点 + 请求显式 `allow_safe_recompute` |
| `dependencyInvalid` / `dependencyMissing` | **有条件候选** | 同上；缺行与失效要分开记录 |
| 需求变化类（`canonical_input_mismatch` / `query_mismatch` / `roots_mismatch`） | **有条件候选** | 属调用方声明的事实，仍须许可 |
| 对象篡改 / 摘要完整性不符（`digestMismatch`） | 终止 | 裁定 2 明确列举的不可安全降级情形 |
| 身份违反（`producerBinding` 各码） | 终止 | 换模型重算不得冒充同一续跑 |
| 来源未知（`noSettlement` / `unknownSettlement`） | 终止 | — |
| `emptyValue` | 终止 | — |
| 合同/形状问题（`contract_*`、`identity_undeclared`、`extraction_unsupported`、`missing_field`） | 终止 | 重算不修合同 |
| `consumer_collision` | 终止 | 换新 consumer id 是另一件事，不是重算 |
| 引擎/存储故障 | 不进决策 | 500，不是业务拒绝 |

**裁定 2 的硬要求**：不能只凭 `source_not_valid` 这个外部码放行。内部必须保留具体失效原因并区分「可恢复输入失效」与「篡改/完整性/身份」。当前磁盘状态尚未核实、仅凭陈旧 DB 摘要无法判断时，**必须拒绝重算**。这不改变 B：`allow_recompute=true` 不会让失效来源直接通过消费。

---

## 4. 重算策略字段（裁定 1）

### 4.1 字段

`recompute_policy`，类型化枚举：

- `never`（**默认**，省略即此值）：消费/续跑失败时不触发模型重算。
- `allow_safe_recompute`：允许进入受限重算判定，**不保证**一定重算。

落点：C 阶段显式受管续跑/结算消费的请求对象内；不设全局开关。

### 4.2 与 `allow_recompute` 的兼容规则

- `allow_recompute` 保留 B 原有语义，不借机扩权。
- 同一请求同时给出两个字段 → **在模型调用和任何持久化写入之前**拒绝。
- 字段组合**不得**决定隐式优先级；不得把格式冲突当成业务准入拒绝。

### 4.3 冲突的终端形态（已裁定）

裁定要求 400。**事实**：现有 `invalid_entry` 是 422（[SettlementConsumptionEntry.swift:253](file:///Users/mr.simi/Documents/SimiGo/SimiGo/Protocol/SettlementConsumptionEntry.swift#L253)）。因此新增独立终端 `INVALID_REQUEST_ENTRY`（400）：

| 情形 | reasonCode |
|---|---|
| 未知 `recompute_policy` 取值 | `recompute_policy_invalid` |
| 与 `allow_recompute` 同现 | `recompute_policy_conflict` |

两个原因码都是本次设计新增的稳定代码；既有 422 `invalid_entry` 的语义与计数**完全不变**，§3.27 的 422 分类口径不受影响。二者互斥：取值非法时先报 `recompute_policy_invalid`。均在任何模型调用与持久化之前返回。详见 [C-INTERFACE-DESIGN-20261027.md](file:///Users/mr.simi/Documents/SimiGo/research/agent-runs/simigo-es-is-realmodel-20261026/C-INTERFACE-DESIGN-20261027.md) §D。

### 4.4 三条件（合取，缺一即终止）

1. 拒绝原因属于 §3 的可进入重算类别，且内部原因已被确认；
2. 请求显式 `allow_safe_recompute`；
3. 能建立可信新起点：合格锚点（§5）+ 当前输入、依赖闭包、身份全部重核实（§8）。

---

## 5. 锚点选择（裁定 4 + 裁定 7）

### 5.1 候选顺序

沿**父链**从近到远，标准是「最近的**合格**祖先」，不是「距离最近的状态」。近处结算无效时继续向历史分支回溯是允许的。每个候选过 §5.3 全部谓词，第一个全通过者当选；全部不通过 → 终止，不自动创建无父 ES，不降级成普通生成。

### 5.2 锚点定义

`(anchor_state_id, anchor_settlement_id)` 成对固定，一旦选定不得在 P1/P2 之间换成另一条行。选择必须复用现有的有效性与准入加载器（[SimiGoESISDatabase.swift:3600](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L3600)），**不得新增第三套过滤算法**；库里已存在彼此独立的有效性过滤（[:3590](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L3590)、[:3898](file:///Users/mr.simi/Documents/SimiGo/Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift#L3898)），口径漂移是现实风险。

### 5.3 五项资格谓词（全部必需）

1. **结算行有效**：`validity=valid`、未 `invalidated_at`、摘要自洽、身份绑定仍在。
2. **必要依赖闭包有效**：该祖先的上游闭包逐个 `valid`。
3. **意图与上下文可重建**：需求、必要上下文、复用合同都能从**当前有效输入**重建；只能靠读取失效后代才能重建 → 不合格。
4. **可独立重算**：不必读取任何失效结算的内容。
5. **身份与合同相容**：当前生产者身份、下一步合同均允许该次重算。

### 5.4 结算行类别规则（裁定 7）

| 状态下的结算行类别 | 锚点资格 | 约束 |
|---|---|---|
| 原生生成行 | **可** | 唯一可承担「血亲生父」的类别 |
| `DERIVED_CONSUMPTION` | **有条件可** | 见下 |
| `IS_RETRIEVAL` | 不可 | 检索结果不是执行结算 |
| `MIGRATED_LEGACY` | 不可 | 谓词 1 已排除 |
| 无结算行 | 不可 | 无已结算值可绑定 |

`DERIVED_CONSUMPTION` 作锚点的额外约束（全部满足才可）：

- 仍显式标记 `DERIVED_CONSUMPTION`，保留来源结算与派生链；
- 其来源结算、完整依赖闭包、必要身份条件均有效；
- 当前下一步合同**明确允许**消费这种派生结果；
- 不得把它解释为独立模型生成来源，不得虚增模型生成计数，不得伪造 `producer.*` 绑定。

### 5.5 只有远祖合格（裁定 4）

允许仅从 E0 这类远祖创建新分支，前提是当前任务所需上下文能从有效证据与最新输入完整重建、合同与身份满足。若缺失必要上下文、或只能依赖已失效后代重建 → 终止。**E0 仍有效 ≠ 对当前任务语义充分**，这是终止条件而不是捷径。

---

## 6. 三项关系分离（裁定 3）

```
E0/E1（最近的合格有效祖先） ──血缘(parent_id)──> E3（重算结果）
E1 的真实输入/结算 ──真实依赖边(dependency_edges)──> E3
S2（失效，永久）  ←── 审计记录（独立承载）──  E3 的本次重算
```

- **血缘**：`E3.parent_id = 合格祖先 state_id`，走现有执行图。
- **真实依赖边**：只记录 E3 实际依赖的**有效**输入、结算与证据，进 `dependency_edges`。
- **失效审计**：单独记录「E3 替代了 S2」，字段至少含 `superseded_settlement_id`、`reason_class`、`policy`、`anchor_state_id`、输入 `snapshot_id`、时间。
- **不得**把审计写成 `dependency_edges` 边：两个闭包读取器都不按 `kind` 过滤，写进去会让下一次失效传播把 E3 判无效，直接违反不变量 1/3。
- `S2` 的 `validity` 不因重算改变。
- **P2 失败时**：新结算零写入（回滚）。若要持久化这次失败尝试，必须在回滚之后写**独立审计事件**，不得把它伪装成已提交的成功重算。

---

## 7. 事务合同（验收合同；design only）

### 7.1 三段顺序

```
P1 · 只读
  定内部拒绝原因 → 选定并固定 (anchor_state_id, anchor_settlement_id) → 复核锚点与依赖状态
  → 核对当前输入新鲜度 → 构造并固定本轮 as-of 输入快照（§8.2）
  不持有长写事务，不写业务行，不写意图行

G · 事务外
  执行真实模型生成；产物绑定到本轮唯一 execution ID 与 input snapshot
  记录 model_calls 与执行结果；不持有 BEGIN IMMEDIATE，允许重扫与其它请求运行

P2 · 单写事务
  重新验证：固定锚点、有效结算行、依赖闭包、快照一致性、身份与合同、消费者冲突
  全部通过 → 一次提交 E3 状态 + 结算行 + 真实依赖边 + 成功审计记录
  任一步失败 → 回滚，零结算写入，不留半结算
```

### 7.2 为什么不能照抄 B 的单写事务

B 的硬顺序全程无长耗时操作；重算的 G 段是分钟级模型调用。把 `BEGIN IMMEDIATE` 横跨 G 会阻塞重扫、消费、其它续跑，WAL 持续增长，崩溃留半开事务。两阶段是正确性与可用性的必要折中，不是简化。

### 7.3 P2 必须重新复核，不能信 P1

P1→P2 之间锚点可能被重扫失效、闭包可能新增失效依赖、输入可能改变、身份可能被换。P2 的复核必须与 B 的准入**复用同一套判定**，不得另写一份。

### 7.4 快照的作用与边界

输入快照必须能表明**生成实际读取了哪些当前文件内容与上游来源**。仅记录「数据库当时认为文件有效」不足以消除 R7；仅在 P2 比较库内 canonical，也不足以证明磁盘内容在生成前后未变。P2 的一致性比较是「与 P1 固定快照比」，不是「与库内当时值比」。

---

## 8. 输入快照与新鲜度门槛（裁定 5 + 裁定 6）

### 8.1 新鲜度门槛（C v1，不引入 watcher）

- 当前文件与已记录摘要不符 → 必须先完成显式 reconcile，或拒绝当前请求。
- **不能让模型使用未核实的陈旧输入。**
- P1 固定并记录快照；P2 提交前重新核验来源与摘要是否仍与 P1 一致；不一致即丢弃产出。
- 仍保留残余 TOCTOU：磁盘读取与 SQLite 提交不是跨系统原子事务；P2 只能证明**核验时**的状态，不能宣称绝对防止核验后再次改动。若未来要求更强保证，应研究不可变文件快照/内容寻址输入，而不是认为加 watcher 就自动解决竞态。

### 8.2 快照记录内容（裁定 5）

必须可持久化、可展开、可核验：

- 不可变 `snapshot_id` 与整体摘要；
- 完整输入来源集合：来源标识、版本/修订信息、内容摘要；
- 摘要算法与 canonical 版本；
- 采集时间、相关根/来源标识。

结算行若不便内联全集，可**引用**独立的不可变快照记录；但**不得**只留一个无法展开的摘要而丢失来源明细。不能用 `information_demands.input_digest` 代替整个依赖输入集合。

HTTP 响应返回 `snapshot_id`、整体摘要、来源项数量、采集时间即可；默认不暴露文件内容或完整敏感路径。

**接口裁定（2026-10-27）**：快照在生命周期上有两段，两个不可变对象：

- `declared`（S 相位写入）：P1 固定下来的声明输入全集——引用精确既有对象，或内嵌本次读取的原始字节；含来源集合、摘要算法与 canonical 版本、`captured_at`、根/来源标识，以及排除 `captured_at` 后的 `declared_input_digest`（幂等指纹用）。
- `final`（P2 写入）：引用 `declared`，并记录本次实际使用的 `used` 清单。

结算行用**可空**列 `settlements.input_snapshot_object_id` 指向 `final`；不建关联表、不回填历史。

**跨阶段硬约束**：G 段实际使用的每项输入必须能对应到 `declared` 中同一 `(kind, 标识)` 且摘要相等（`used ⊆ declared`）。生成期间才出现或摘要不符的输入**不得**事后补写进 `used` 继续提交，只能判 `snapshot_used_undeclared` / `snapshot_used_mismatch` → P2 拒绝；此时 `model_calls` 可大于 0 而 `settlements_written` 必须为 0。

**容量（v1 工程限值，需实测调整）**：内嵌原始字节合计 ≤ 32 MiB；最终序列化对象 ≤ 48 MiB；两者都强制、都 fail-closed，不截断、不降级成「只留摘要」。编码为 JSON + Base64。

**可重放性（裁定 O2）**：`final.replayable = declared.replayable ∧ used.replayable ∧ (used ⊆ declared 且逐项摘要一致)`。逐项标记保留，整体必须由证据计算，调用方不得填写。`used` 缺失、含未声明项、摘要不符、必要字节不可重建、版本不可识别 —— 任一成立即整体不得标可重放。声明只能证明「事先声明了什么」，不能替代实际使用的证明。

**公开错误码（裁定 O1）**：封闭 allowlist——`recompute_policy_invalid` / `recompute_policy_conflict`（400）、`snapshot_unrepresentable`、`idempotency_conflict`（422），其余一律内部码 + 入口既有失败分类。公开码 ≠ 内部拒绝原因；内部枚举新增不自动增加公开码；模型生成后发现 `used` 违例不得报成 400 或笼统的「模型执行失败」。

**生命周期（裁定 O3）**：v1 无 TTL、无自动 GC、不按天数删除；引用数为零不构成删除授权；存储压力下**拒绝新建并报告存储问题**，不得删旧证据。

字段、时点、失败面与判定细则见 [C-INTERFACE-DESIGN-20261027.md](file:///Users/mr.simi/Documents/SimiGo/research/agent-runs/simigo-es-is-realmodel-20261026/C-INTERFACE-DESIGN-20261027.md) §A/§G。

### 8.3 文件变化窗口：三种机制仍按裁定保留为独立问题

| 机制 | 缩小窗口 | 可给出的保证 | 成本/风险 |
|---|---|---|---|
| ① 显式重扫 + 明确时间边界 | 不缩小 | 「重扫之后一致」 | 成本最低，保证最弱 |
| ② 消费前磁盘摘要复核 + as-of 证据 | 缩到「复核→返回」 | 「as of T 一致」 | 全量哈希延迟、权限/符号链接/超大文件新失败面，需定义超时语义（建议拒绝） |
| ③ 文件版本/内容寻址快照 | 可做到请求内根集合不变 | 请求持有具体版本 | 架构级改动，与 `file_contents` 结构不兼容 |

**注意**：C v1 采用 ①+② 的组合（§8.1），不采用 ③；②的形态是「事务外复核 + 事务内库内摘要 CAS + 响应带 as-of 证据」，不是把全量磁盘 I/O 塞进写事务。

### 8.4 残余风险

- R1 复核通过后、值返回前文件被改。
- R2 复核期间文件被改但摘要仍相同。
- R3 大文件哈希 I/O 抖动 → 超时语义须定义。
- R4 符号链接/硬链接替换，mtime 不变。
- R5 若将来引入 watcher：事件到达与重扫完成之间仍有窗口，watcher 只是加速器。
- R6 多消费者并发消费同一来源。
- R7 **在陈旧但尚未传播的输入上重算**：重算不制造新鲜度。闭合方式 = §8.2 的 as-of 快照，使事后能区分「重算吃的本就是旧输入」与「重算后输入才变」。
- R8 **并发重算**：见 §9。
- R9 **存储增长（已接受）**：v1 不回收、不设 TTL，孤儿快照与内嵌字节会持续积累；达到限制时以**拒绝新建**处理，不删旧证据（裁定 O3）。这是用存储成本换证据生命周期确定性的显式取舍。

### 8.5 可证伪的验证设计（授权后才执行）

- C-1：复核返回前注入写入 → as-of 证据与实际返回一致、盘上已不同。
- C-2：改文件但不重扫，连续两次消费 → 返回旧值且 as-of 显示旧摘要（证明「未重扫即陈旧」）。
- C-3：watcher 时延分布（如将来引入）。
- C-4：大根哈希延迟与超时行为（fail-closed 断言）。
- C-5：锚点判定三例——no-qualifying-ancestor / inputs-not-reconstructable 终止；成功例断言 `E3.parent_id` = 合格祖先、`S2` 仍 invalid、`dependency_edges` 中无 E3→S2 边。
- C-6：两阶段竞态——P1 通过后在 G 段让锚点失效或改输入，断言 P2 拒绝、`settlements_written=0`、`model_calls>0`，且 `S2` 未被改回 valid。
- C-7（裁定 7 专用）：以 `DERIVED_CONSUMPTION` 作锚点的成功例 + 反例（合同不允许消费派生结果时终止）；断言模型生成计数未因派生锚点增加。

---

## 9. 并发（裁定 8）

- 首版**不强制互斥**，不引入持久意图行；允许并行重算形成不同 ES 分支。
- 每条分支必须绑定自己的请求/执行 ID、输入快照、子 ES 与模型产出；**禁止两个执行混用生成产出**。
- 两个请求都必须各自通过 P2；执行期间锚点/闭包/输入摘要变化 → 后完成者仍须拒绝提交。
- 调用方显式指定同一 consumer ES ID 或幂等键 → 必须做冲突检测，避免两份产出写入同一分支。判等比较请求指纹、锚点、合同、输入快照、身份、产出摘要六项，不是最终文本（§11.2）。
- **并发同键的真实计量**：两个请求都可能真实调用模型，只有一个能提交；落败方记 `model_calls>0 && settlements_written=0`。不得把「幂等」表述为「模型只调用一次」。
- 若未来产品要求「同一意图只执行一次」，再单独引入意图行/租约；不得把全局互斥当作首版隐含要求。

---

## 10. 残留自建根与后续实验环境

- 两条自建根 `work-00000000903bb636`（修复前）、`work-0000000059acde6e`（修复后）及结算行**保留**在真实库，标记为测试残留；不删行、不级联删结算、不为清理改产品代码。
- 已观测副作用：后一轮检索把前一轮根文件也纳入绑定（14 vs 13 个 file binding），会影响后续实验的依赖闭包与 canonical 输入。
- C 验证环境优先用**独立测试数据库**或可隔离根集合（现有 `SIMIGO_STATE_GRAPH_STORE` / `SIMIGO_HOME` / `SIMIGO_CACHE_ROOT` 注入，见 `tools/make_isolated_xctestrun.py`）；若必须在真实库跑，读数须列出本次 root id 集合并说明残留根的影响。
- 环境恢复另提**可审计**清理方案（备份、逐行列举、可回滚），设计阶段不执行。

---

## 11. 裁定状态与后续接口设计事项

八项开放问题已于 2026-10-27 全部裁定（表内为结论）：

| # | 问题 | 裁定 |
|---|---|---|
| 1 | 策略字段与冲突 | `recompute_policy`，默认 `never`，与 `allow_recompute` 同现即 400 `INVALID_REQUEST_ENTRY`（`recompute_policy_conflict` / `recompute_policy_invalid`），先于模型调用与写入拒绝 |
| 2 | `source_not_valid` 是否可重算 | 有条件：保留内部原因，仅可恢复输入失效；陈旧未核实即拒绝 |
| 3 | 审计关系落点 | 独立审计记录，不改 `dependency_edges` 闭包语义；P2 失败零写入、失败审计在回滚后独立记录 |
| 4 | 只有远祖合格 | 允许，标准是「最近合格」；上下文不充分即终止 |
| 5 | as-of 证据 | 结算侧持久化 + HTTP 返回摘要；可引用不可变快照，但不得只剩不可展开的摘要 |
| 6 | watcher | C v1 不纳入；以重扫/复核建立保证边界，保留 TOCTOU 残余 |
| 7 | `DERIVED_CONSUMPTION` 锚点 | 有条件允许，不得冒充生成证据或虚增计数 |
| 8 | 并发互斥 | 首版不强制；允许并行分支；同 consumer id/幂等键需冲突检测 |

### 11.1 六项接口事项的裁定（2026-10-27，全部收口）

| # | 事项 | 裁定 |
|---|---|---|
| 1 | as-of 快照存储形态与引用字段 | `declared` + `final` 两个不可变 `is_objects` 对象；结算用**可空**列 `settlements.input_snapshot_object_id` → `final`；不建关联表、不回填 |
| 2 | 400 终端命名与 422 并存 | 新增 `INVALID_REQUEST_ENTRY`（400），原因码 `recompute_policy_invalid` / `recompute_policy_conflict`；既有 422 `invalid_entry` 语义与计数完全不变 |
| 3 | 失败审计结构与生命周期 | `is_objects` 事件 + `appendIndexEntry("c-failure-audit:<execution_id>")`；`execution_id` = 单次执行尝试；一次尝试一条终态审计；best-effort、回滚后写、失败不改变原始终止结果 |
| 4 | 幂等键/consumer ES ID 位置 | C 作用域请求对象字段；`execution_states.idempotency_key` 可空列 + 部分唯一索引；不复用 `continuation_id`；v1 全局唯一 |
| 5 | `INPUT_ADMISSION_REFUSED` 拆桶 | 结构化内部 `ManagedRefusal{cause, origin, evidence}`，外部 HTTP 码保持兼容；资格 = 原因 × 新鲜度；`MIGRATED_LEGACY` 独立分码；`invalidated_cause_unknown` 仅在直接文件绑定 `changed_verified` 时可用 |
| 6 | 快照采集实现位置 | ACQ-1..7 分布在 P1 / S / G / P2；G 段不持写事务；P2 事务内复核锚点/闭包/身份/合同/幂等；ACQ-5b 预检 + ACQ-6 完整复核 |

### 11.2 幂等判等（不是最终文本）

必须同时比较：请求指纹、固定锚点 `(state_id, settlement_id)`、复用合同（含版本）、输入快照（`declared_input_digest`，必要时加 `final` 快照 ID）、生产者身份、模型产出摘要。任一不同 → `422 idempotency_conflict`；六项全同且已提交 → 重放既有结算、不新建。

**并发口径**：不引入互斥/意图行，两个同键请求都可能真实调用模型；只有提交阶段去重。落败方必须记 `model_calls>0 && settlements_written=0`。**幂等语义不等于「模型调用只发生一次」**。

### 11.3 公开错误码、可重放性与生命周期（O1–O3 裁定，2026-10-27）

| # | 问题 | 裁定 |
|---|---|---|
| O1 | 新增 `reasonCode` 是否全部公开 | **不全部公开**，封闭 allowlist：两条 400 码 + `snapshot_unrepresentable` + `idempotency_conflict` + 入口既有分类。内部诊断码与公开 API 码分离；内部枚举增长须经显式公开映射审查；模型后 `used` 违例对外走入口既有 422 分类，内部精确记为快照合同违例 |
| O2 | `replayable` 是否合取 | **是**：`declared.replayable ∧ used.replayable ∧ used ⊆ declared（含逐项摘要一致）`；整体由逐项证据计算，调用方不得填写 |
| O3 | 孤儿快照保留期 | **v1 无 TTL、无自动 GC**；引用数为零不等于可删；存储压力下拒绝新建并报告，不删旧证据；将来 GC 需独立授权 |

三条合同边界（一句话形式）：**公开错误码不等于内部拒绝原因；可重放性不等于保存了一个摘要；没有当前引用不等于可以删除历史对象。**

**进展（2026-10-27）**：[C-INTERFACE-DESIGN-20261027.md](file:///Users/mr.simi/Documents/SimiGo/research/agent-runs/simigo-es-is-realmodel-20261026/C-INTERFACE-DESIGN-20261027.md) 已收口为 **v2 裁定收口版**（§A 快照 / §B 拒绝 / §C 链路验收 / §D 400 终端 / §E 失败审计 / §F 幂等 / §G 采集点 / §H 五项推断裁定记录 / §I 非目标 / §J 一致性审查与 O1–O3 收口）。该稿为**设计与合同**，未实施任何代码、迁移或 schema 变更。

**一致性审查（纯设计，2026-10-27）**：修正 10 处内部冲突——幂等指纹与取证字段分离（`declared_input_digest` 排除 `captured_at`/`idempotency_key`）、`final` 对象补版本字段、容量越限统一 422、P2 补 `used` 完整复核、errorKind 归属、索引身份前缀核实无碰撞、`execution_id` 措辞、对外/内部错误码分列、`replayable` 合取公式、存储压力条款。细节见接口稿 §J。

---

## 12. 本设计**不**包含

- 不实现决策函数、不给续跑路径加 `recompute_policy`、不拆 `INPUT_ADMISSION_REFUSED`。
- 不引入 watcher、不改 `canonicalDemandInput`、不改 `settleContinuation`、不改 `dependency_edges` 读取的 `kind` 过滤。
- 不引入意图行/租约、不建快照表、不做迁移。
- 不设 TTL、不做自动 GC、不按天数删除对象、不扩大公开错误码集合。
- 不改 `prefix-pool` / `branch-checkpoints`，不改普通续跑语义，不动真实库测试残留。
- 不把 §3.27 的读数扩展成「生产闭环已成立」或「文件一变即失效」。
