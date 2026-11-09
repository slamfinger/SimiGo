# 全仓代码级审核 — 步骤 1 / 步骤 2 发现（T1–T4 同构站点 + 失败与断连写集）

日期：2026-11-07
取证身份：产品仓 `origin/main = 8d87e325928277078afc4fb892f4749a3ce39082`
（提交时间 2026-11-06 21:41:29 +0800，"Merge pull request #69 …"）。本地 HEAD 已判定陈旧，
本轮所有锚点一律经 `git show origin/main:<path>` / `git grep … origin/main` 取，
只读副本位于 `/tmp/audit-om/`。未修改任何产品代码、未启动任何实验、未做架构裁决。

真实路径提醒（本轮踩过的坑）：
- `ESISDatabase.swift`(6583 行) 与 `InformationLoop.swift`(684 行)
  在 `Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/`，**不在** `SimiGo/Storage/`。
- `ISContextLedger.swift`(123 行) 同目录。

证据等级标记：
- **C** = 代码级已证（锚点 + 调用关系可在本轮重放）
- **C-NEG** = 代码级已证的「非缺陷」（负面结果，同样登记）
- **R** = 仍需运行时证据（锚点确定，实际触发频率/后果未实测）

---

## §1 各入口 T1–T4 写集对照（步骤 1）

段落命名沿用 V-7：**T0** 检索/demand 结算（在 `prepareInformationTurn` 内）
**T1** `commitChatTurn` **T2** `recordNativeSettlementWithIdentityAndAdvancement`（经 `settleTurn`）
**T3** `linkChatSession` **T4** `recordSettlementSummary`。

| 入口 | prepare/T0 | T1 | T2 | T3 | T4 | 结算前守卫 | 证据 |
|---|---|---|---|---|---|---|---|
| `/v1/chat/completions` 流式 | `prepareInformationTurn` HTTPServerChat:173→`loop.resolve` :216、`appendChatMessage` :272 | `settleInformationTurn` :341→:349 | `settleTurn` :371（Loop :593-660） | Loop :637 | Loop :641（`try?`） | 文本非空 :348 / eligibility :353 / `isSettleable` :359 / `producedToolCalls` :365 / **detach 例外** :977-998 | C |
| 同上 非流式 | 同上 :1239 | :1438→:349 | 同上 | 同上 | 同上 | 同四条守卫，**无 detach 例外**：守卫 :1422-1427 `guard !context.closed, !Task.isCancelled` | C |
| `/v1/responses` 流式 | `prepareInformationTurn` :1839（或 hoisted :1669） | `settleResponsesInformationTurn` :1004→:1013 | 两条分支：`settlementID != nil` 时**不调 `settleTurn`**（:1030-1054）；否则 :1058 `settleTurn` | :1044（仅 `settlementID` 分支，且仅当 `stateID != nil`）/ `settleTurn` 内 Loop :637 | :1051（`try?`）/ Loop :641 | 文本 :1012 / eligibility :1017 / `isSettleable` :1023；**无 `producedToolCalls` 守卫**（`grep -c producedToolCalls` chat=5 / responses=0）；**无 detach 例外** :1953-1958 | C |
| 同上 非流式 | :1299 | 同上 :1424 | 同上 | 同上 | 同上 | 同上；`settlementStep` :1409 唯一调用点 | C |
| `/v1/completions` | **无** | **无** | **无** | **无** | **无** | 声明式不托管 HTTPServerCompletions:58-66；`completionsBlock` :72-82 只贴 marker | C |
| `/mcp` `simigo_es_settle` | **无 T1**（不写 chat 行） | — | HTTPServerMCP:656 `settleTurn` | 同事务链内 Loop :637 | Loop :641 | 由调用方参数决定；**第 5 笔** `recordAnsweredDemand` :681-694（附加，失败只记 `demandError`）；抛错被 :130-134 吞成 `isError:true` | C |
| `/mcp` `simigo_is_search` | HTTPServerMCP:361-370 `openESISDatabase`+`loop.resolve` → 有 T0 副作用 | — | — | — | — | 只读工具名，实际写 demand+检索结算（同 §4） | C |
| Qoder 采集桥（第 6 条写入链） | `ExternalTurnSink.write` :70 `recordExternalTurn` → :74 `recordExternalResponse` → :78 `guard verified` → :79 `verifyExternalTurn` | 外部合同原语（DB :3666-3745），不借 chat T1/T2 | — | — | — | fail-closed：问答双方齐全才在同一事务提升为 `committed` | C |
| 受管续跑（C 阶段） | — | — | `ExecutionStateGraph:479` / `:564` / `ISAdmission:248` 各自**单事务** | — | — | 单事务形态，与 chat 的分段写形成对照 | C |

### §1.1 Responses 的 `eligibility` 来源（本轮遗留待核项，现已闭合）

`prepareInformationTurn` **只有一处定义**：HTTPServerChat.swift:173；Responses 的三个调用点
（:1299 / :1669 / :1839）复用的是同一函数体。因此 Responses 的
`turn.eligibility`（HTTPServerResponses:1016、:1017 读取）与 chat 走**完全相同的声明渠道**
`turnEligibility`(HTTPServerChat:123-139)：`metadata.simigo_request_scope` →
`client_metadata.simigo_request_scope` → `x-simigo-request-scope` 头部，首个非空值生效，
`internal|internal_operation|internal-op` → `.internalOperation`，其余 `.ordinary`。**C**
（结论：此处是真正同构，不是同名不同义。）

Responses 与 chat 在 prepare 入参上的两处**语义差**：
1. Responses 传 `sessionID: responsesInformationScope(parsed:json:headers:)` 与
   `queryOverride: lastUserText(parsed.currentInputMessages) ?? lastUserText(parsed.canonicalMessages)`
   （:1304-1307 / :1674-1677 / :1844-1847）；chat 两处都不传（:659、:1240）。
   ⇒ Responses 的检索 query 取自「本轮 input」而非「messages 里最后一条 user」，
   注入块却拼在 `continuationMessages`/`gatedMessages` 上。**C**（差异事实）；
   对检索质量的实际影响 **R**。
2. Responses 的 prepare 点在流式路径上有两个互斥分支（hoisted :1669 仅当
   `!parsed.esStateIDPresent`，否则 :1839）。现场核对：**同一请求只会执行一次 prepare**，
   不存在双写 demand / 双写 user 行。**C-NEG**

### §1.2 Responses 独有状态类（chat 不可能产生）

当 `parsed.continuationSettle` 为真且 `settlementStep` 返回 `.settled`（:1418-1419，
`settlementStep` 定义 :574-608，唯一调用点 :1409 ⇒ **仅非流式可达**），结算由另一权威
（注入的 `continuationSettlement` → `ContinuationSettlement:278` → `ExecutionStateGraph:520-580`
单事务）写入，`settleResponsesInformationTurn` 随后只做三件事：
`recordInformationAdvancement` :1036（`try?`）、`linkChatSession` :1044（`try?`，且要求 `stateID != nil`）、
`recordSettlementSummary` :1051（`try?`），**全程不调 `settleTurn`** :1057。**C**

新发现（此前任何清单都没有）：`:1030-1033` 的顺序缺陷形状——
```
1013  try? commitChatTurn(...)                       // T1 已落
...
1030  if let settlementID {
1031      guard !turn.renderedResolution.demandID.isEmpty,
1032          !turn.renderedResolution.retrievalSettlementID.isEmpty
1033      else { return }                            // 静默返回，无 [SETTLE_SKIP] trace
```
即：结算已由另一权威写入、assistant 行已 committed，但因 `renderedResolution` 的身份字段为空，
advancement / chat-session 链接 / 摘要**一笔都不写**，且**没有任何 trace 行**
（对照 :1017-1021 与 :1023-1027 都写 `[SETTLE_SKIP]`）。**C**（代码形状）

该空值有真实生产者，不需要崩溃即可到达：`prepareInformationTurn` 在 `loop.resolve` 抛错时
回落到 `Resolution(demandID: "", …, retrievalSettlementID: "", …)`（HTTPServerChat:219-221），
而 turn 仍被无条件返回（:325）；默认开启的上下文冻结
（`contextFreezingEnabled` = `env["SIMIGO_IS_CONTEXT_FREEZE"] != "0"`，HTTPServerChat:501-503）
会把这份空 resolution 按 (scope, userText) 冻结并在后续同文本轮次回放
（`ISContextLedger.stabilize` :72-88，进程内 LRU，重启即清）。**C**（可达链）/ **R**（真实频率）

---

## §2 prepare 的副作用先于所有前置门（步骤 2 的一半）

`prepareInformationTurn` 在返回前已经写完 T0（检索结算 + demand RESOLVED + 依赖边）
与 user `pending` 行（:216 `loop.resolve`、:272 `appendChatMessage`）。
其后才依次经过四道会「直接 return」的门：

| 门 | chat 流式锚点 | chat 非流式 | Responses 流式 | 拒绝时已落盘 |
|---|---|---|---|---|
| `fork_from_branch` 失败 400 | :667-682 | :1249-1263 | — | T0 + user pending |
| W4 预算门 503 `rejectOnRequestBudget` | :698-708 | :1303-1313 | :1685-1690 | 同上 |
| 并发 admission 拒绝 `concurrency_rejected` | :717-726 | :1326-1331 | — | 同上 |
| `markGenerationStarted()` false | :734-735 | :1339-1340 | — | 同上 |
| SSE 头写失败 | :796-804 | — | — | 同上 |
| 生成前 `context.closed`/cancel | :839-843 | — | :1953 前 | 同上 |

**结论（C）**：任何一条拒绝/早退路径都留下**持久的** `information_demands` RESOLVED 行、
`retrieval_settlements` status='valid' 行、`settlements` `validation_status='IS_RETRIEVAL'` 行、
两条 index 条目（:4371-4374）、`demand-input` 依赖边（:4446-4450），以及一条永不提升的
user `pending` 行。无失效、无回滚、无审计行。

检查后判定为**非缺陷**（C-NEG，避免把残留夸大成危害）：
- 这些残留**不会污染后续检索**：检索基线三源（files / committed chat / `citableSettlementSummaries`）
  分别排除 pending 行（DB:3954 `turn_state='committed'`）与 `IS_RETRIEVAL`（DB:5855），
  `backfillSettlementSummaries`（:5934）与 `readSettlementReceipts`（:6512）同样排除。
- 这些残留**不会被任何读侧消费**：demand 的三个查询点（:4020 / :4050 / :4117）都要求
  `state='ADVANCED'`。
- `SUPERSEDED` 只作用于 `session_id IS ? AND request_identity IS ?`（:4436-4439），
  故一次被拒请求**不能**推翻另一请求的 demand 水位。

⇒ 定性只到「**无消费者的持久残留 + 无失效语义**」，不写「数据污染」。

---

## §3 失败与断连写集分类（步骤 2）

### 3.1 失败类

| 事件 | 站点 | 类型 | 写集 | 证据 |
|---|---|---|---|---|
| `generateHandler` 抛错（流式） | HTTPServerChat:1082-1098 catch-all | **未处理**（仅 wire 错误 + `failureReason`） | 只保留 prepare 的 T0+pending user；T1/T2/T3/T4 全不写 | C |
| `CancellationError` | :1036-1056 | 未处理（同上） | 同上 | C |
| `NativeMLXValidationError.contextDemandExceeded` | :1058-1080 | 未处理 | 同上 | C |
| 引擎返回 `.capped` / `.cancelled` / `.unconfirmed` | :359-364（`isSettleable`） | **best-effort 半写** | T1 写（committed）、T2/T3/T4 不写、`[SETTLE_SKIP]` trace | C |
| 工具中间轮（chat） | :365-370 `producedToolCalls` | best-effort 半写（设计意图，PR #123/P2） | T1 写、结算不写 | C |
| 工具中间轮（**responses**） | 无对应守卫（:1017/:1023 之后直落 :1057） | **不写守卫 ⇒ 中间轮可被结算** | T1+T2+T3+T4 全写 | C（形状）/ R（V-4 已取真机读数，见 V4-FINDINGS） |
| MCP 工具抛错 | HTTPServerMCP:130-134 | **吞错**：`isError:true` 返回，先前已提交的写不回滚 | 按已执行到的段定格 | C |
| MCP `es_fail` | :735-744 `recordFailureAudit` | 同步处理（**唯一由 HTTP/MCP 侧调用者**，其余全是调用方自报字段） | failure_audit 行 | C |

**六条 wire 的失败路径均不调用 `recordFailureAudit`**：`git grep recordFailureAudit origin/main`
的产品侧调用者只有 `ManagedContinuation.swift:477` 与 `HTTPServerMCP.swift:735`。**C**

`.capped` / `.unconfirmed` 的生产者（本轮新闭合）：
- `NativeMLX.swift:2363-2368`：`stopReason` 为 `.none` ⇒ `.unconfirmed`（vendor 无信息事件即无证据）
- `NativeMLX.swift:1465`、`:1903`：入站消息为空 / delta 为空 ⇒ `text:"" , .unconfirmed`
- `GGUFEngineClient.swift:223-224`：`"length"` ⇒ `.capped`；**任何未知 finish_reason ⇒ `.unconfirmed`**
- `OversizedRuntime.swift:255`：⇒ `.unconfirmed`
实际触发频率与「模型确实产出了看似完整的答案却被判 unconfirmed」的运行时比例：**R**。

### 3.2 断连类（detach ≠ cancel）

`terminateForClientGone`(HTTPServer.swift:1233-1241) ⇒ `terminate(cancelGeneration:true, detach:true)`；
`closeAndTakeRequestTask`(:546-585)：`detachable` 需 `detach && _generationStarted &&
!_cancellationSignalled && !_closed`，命中则 `_detachedByClient=true`、保存 `_requestTask`，
且 `shouldCancel` 额外要求 `!detached` ⇒ **任务继续跑，连接已关**。**C**
触发面是**通用连接状态与 keepalive/心跳发送失败**（:1050-1064 / :1070-1086 / :1505-1556 / :3593），
因此**非流式与 Responses 同样可达**。**C**

四条 wire 在 detach 事件上的处理**互不相同**：

| wire | 站点 | detach 时本轮结果 | trace |
|---|---|---|---|
| chat 流式 | :977-998（`let settleAfterDetach = context.detachedByClient`，守卫 :978-981） | **照常结算**（T1-T4 全写） | `[IS] settleAfterDetach … reason=client_watchdog_not_user_cancel` :989-993 |
| chat 非流式 | :1422-1427 `guard !context.closed, !Task.isCancelled else { return }` | **静默丢弃**（已花掉一次生成，零持久结果） | 无 |
| responses 流式 | :1953-1958 | **静默丢弃** | 无 |
| responses 非流式 | :1388-1393 | **静默丢弃** | 无 |
| completions | 无结算语义 | 不适用 | — |
| MCP | 无生成路径 | 不适用 | — |

配套事实：`HTTPServer.swift:1172-1175` 的注释仍写「detach 之后本轮不取消、**不结算、不提交**
（recorded only）」，而 `HTTPServerChat.swift:970-977`（2026-11-05 修订）已实现
detach 照常结算并自带说明。**文档/注释与实现互相矛盾**，属可核验的实现级缺陷（描述面）。**C**

Runtime 停止（`markCancelledByRuntime` :523-528）与手动取消不经过 detach 分支，
走 `terminate(cancelGeneration:)` ⇒ 引擎被取消 ⇒ `.cancelled` ⇒ `isSettleable==false`
⇒ T1 写、T2-T4 不写（除非已 detach）。**C**

### 3.3 重启后状态

- 崩溃窗口：V-7 已实测 T1 与 T2 之间为真实多事务窗口（2.179 / 0.588 / 1.091 ms），
  重启后 `committed` 行进入 IS 检索资格（DB:3775 `isEligible`、:3954），
  而 settlement / ES lineage 未承认该轮完成 ⇒ **两种权威不一致**（owner 已裁定保留该定性）。
- 无补偿：`func (repair|heal|orphan|sweep|reconcile|backfill|adopt)` 在产品代码中
  仅 `reconcileRegisteredRoots`(DB:3007+) 与 `backfillSettlementSummariesInTransaction`(:5928)
  命中；后者只补 settlement→summary、且在迁移期（:803）调用，
  并显式排除 `IS_RETRIEVAL`/`MIGRATED_LEGACY`。**⇒ 产品内没有任何针对
  「committed 但无结算」「RESOLVED 但永不 ADVANCED」「pending 永不提升」的修复链**。**C**
- lifecycle / admission / budget 全为内存 + `state/runtime.json` + trace，**不写 SQLite**
  （HTTPServer:465-476、:1382/:1440、:3715）。**C**

---

## §4 `loop.resolve()` 内部：确定性半状态（非崩溃）

`InformationLoop.swift`：
```
294-302  try database.recordInformationRetrieval(...)   // 一个事务：settlements + 2×index
                                                        //   + retrieval_settlements valid
                                                        //   + information_demands RESOLVED
                                                        //   + SUPERSEDED + demand-input 依赖边
304-307  注释：没有 binding，失效闭包无路可走，已结算 demand 会在源变动后仍被复用
308-315  for hit in items where hit.kind=="file" { try database.linkSettlementToExternalFile(...) }
                                                    // 事务外、逐笔、会 throw
```
`ESISDatabase.swift:5202-5226`：`:5204-5205` 在文件未被索引时直接 `throw`。

⇒ 检索结算与源边绑定**分离**：绑定阶段抛错后，demand 已是 `RESOLVED` + `valid` 检索结算，
却没有任何源边；Loop :273-287 之后会按此 resolution 供 `reused`。**这是确定性可达的半状态，
不是崩溃专属，且抛错在 prepare 里被 `try?`（:216）吞掉。** **C**

对照（证明半状态并非 schema 必然）：`recordInformationRetrieval` 用单事务、
`verifyExternalTurn`(DB:3726-3745) 要求问答双方齐全才在同一事务里提升两行状态、
`ExecutionStateGraph:479`/`:564`/`ISAdmission:248` 也是单事务。**C**
全仓只有**两处** `turn_state` 提升站点：DB:3598（chat `commitChatTurn`）与 DB:3736（外部合同）。**C**

---

## §5 #391 三类清单 — 本轮增量

### A. 确认实现缺陷（代码级，锚点齐备）

- **A-新-1** Responses 在 `settlementID != nil` 分支里，T1 已提交后 `:1030-1033` 空身份守卫
  **静默 return**，advancement/link/summary 全不写且无 `[SETTLE_SKIP]` trace；
  空身份有真实生产者（HTTPServerChat:219-221 回落 + :325 无条件返回 + 冻结回放）。
- **A-新-2** detach 语义四条 wire 不一致：chat 流式结算、chat 非流式 / responses 流式 /
  responses 非流式全部静默丢弃（:1422-1427 / :1388-1393 / :1953-1958），
  且触发源 `terminateForClientGone` 与连接层站点证明非流式可达。
- **A-新-3** `HTTPServer.swift:1172-1175` 注释与 `HTTPServerChat.swift:970-977` 实现互相矛盾
  （描述面缺陷，会误导后续审核）。
- **A-新-4** `prepareInformationTurn` 的写副作用先于全部前置门（§2 表），
  被拒请求留下无消费者的持久残留，无失效、无审计行。
- **A-新-5** `loop.resolve` 检索事务与源边绑定分离（§4），绑定抛错被上层 `try?` 吞掉，
  留下「RESOLVED + valid 但无源边」且仍按 `reused` 供。
- **A-新-6** Responses 缺 `producedToolCalls` 守卫（chat 有），工具中间轮在该 wire 可被正常结算。
- **A-继承** V-4 F-A / F-B / F-C 与 V-7 保持独立条目，**不合并**、不并入本轮 A 项。

### B. 确认架构缺口

- **B-新-1** 产品内不存在任何 repair / reconcile / invalidate 链处理半写状态（§3.3）；
  唯一回填是迁移期 settlement→summary 且排除检索类。
- **B-新-2** IS 检索资格权威（`turn_state='committed'`，DB:3775 / :3954）与
  settlement / ES lineage 权威在 schema 层没有对齐机制 —— 与 owner 对 V-7 的裁定一致。
- **B-新-3** `ISAdmission.settleContinuation`（:223-252）是公开、单事务、
  已测试但未接线的权威入口：**无任何产品调用者**（`.admit` 才用于
  SettlementConsumption:205/:296、ExecutionStateGraph:628）。
- **B-继承** 跨原语崩溃窗口（V-7 定性保留）。

### C. 仍需运行时证据

- **C-新-1** `.capped`/`.unconfirmed` 的真实产生频率（生产者已定位，见 §3.1）。
- **C-新-2** §1.2 空 resolution 分支在真机的可达频率（需一次可控注入：让 `loop.resolve` 抛错，
  同时带 `continuationSettle`）。未做实验，保持未验证。
- **C-新-3** detach 在非流式/responses 上的静默丢弃是否曾在真实客户端出现
  （需断连窗口，与 #121/#134/#135 相关，不新起实验）。
- **C-新-4** Responses 用 `queryOverride` 后检索质量变化（与 P1 检索净化同域）。
- **C-继承** V-1 / V-3（GGUF 引擎侧、Oversized 长请求）仍等 owner 开 GGUF 隔离真机窗口。

---

## §6 本轮未核验 / 明确不声明的项

1. `.unconfirmed` 是否会与「模型已产出完整文本」同时出现（需引擎侧事件流实测）。
2. `commitChatTurn` 在 `userMessageID == -1`（`appendChatMessage` 抛错的 `?? -1` 回落，
   :274）时跳过 user 行提升（DB:3584-3607 条件 `userMessageID > 0`）的真实发生率 ——
   形状已证（C），频率未证（R）。
3. `information_demands.request_identity` 在各 wire 的具体取值分布（只证了 SUPERSEDED 的作用域）。
4. Oversized / GGUF 引擎侧对 `stopReason` 的实际填充率。
5. 任何「修复方向」结论 —— 按 owner 顺序，架构审核尚未开始。

---

## §7 本轮收口：全仓事实核验剩余调用链盘点（只盘点，不裁决）

`origin/main` 路由实测（HTTPServer.swift switch :2598 起 + LOCALB 策略表 :1602-1636），
共 17 个端点。逐条标注本轮代码级核验状态：

| 端点 | 核验状态 | 锚点 |
|---|---|---|
| POST /v1/chat/completions | 已核（§1/§2/§3） | HTTPServer:2945 → HTTPServerChat |
| POST /v1/responses | 已核（§1/§1.2/§3） | HTTPServer:2989 → HTTPServerResponses |
| POST /v1/completions | 已核：不托管（§1） | HTTPServer:2967 → HTTPServerCompletions:58-82 |
| POST/GET /mcp | 已核 9 工具写集（§1、下方） | HTTPServer:2648 → HTTPServerMCP |
| GET/POST /v1/simigo/search | 已核（§2 表 + 本节的写副作用面） | HTTPServer:2620-2622、:1885-1886、:1916-1920 |
| POST /v1/simigo/is/reconcile | 部分：只到 `reconcileRegisteredRoots` 入口 | HTTPServer:2645、:2309；DB:3007+ |
| PUT/POST /v1/simigo/roots | **未核**（写 roots 表 + FileManager 副作用） | HTTPServer:2345-2375 |
| POST /v1/branches/fork / delete / list | **未核**（策略 `.branchControl`） | HTTPServer:2763 / :2817 / :2903、:1634-1644 |
| POST /localb/auth/challenge | **未核**（LOCALB ceremony 与 RegistryStore 写入） | HTTPServer:2614；Packages/LOCALBCore |
| GET /health、/v1/models、/models、/v1/models/<id> | 只读面，未单独核 | HTTPServer:2654/:2698/:2745 |
| GET /v1/simigo/env / is/status / is/settlement / is/dependency / is/file / is/object | 只读；句柄一律 `createIfNeeded: false` | :1970/:2038/:2121/:2169/:2212/:2256 |

两条本轮实测得到的事实（不构成缺陷判定）：
1. **云端 API / 混合转发链在 main 已无代码**：
   `git grep -iE "forwardToRemote|RemoteProxy|remoteAPI|dashscope|api\.openai" origin/main -- SimiGo Packages`
   命中数为 **0**。owner 六范围中的「云端 API / 混合推理」需要重新界定为
   「LOCALB 远程面 + MCP 外部 Agent」，而非已删除的转发代理。**C**
2. 读路由的 DB 句柄形态**不一致**：9 个只读入口 `createIfNeeded: false`（fail-closed），
   而 `GET/POST /v1/simigo/search` 与 `PUT/POST /v1/simigo/roots` 用 `createIfNeeded: true`
   + `try db.runMigrations()`；MCP 每个工具都新开句柄并迁移（:796-798）；
   chat prepare 用 `try?`（HTTPServerChat:196，静默）。⇒ 一次匿名 GET search
   可在无 DB 的机器上**建库并迁移 schema**，并留下 §2 的 T0 持久写
   （该路由在 LOCALB 策略里是 `.open`，HTTPServer:1607-1608）。**C**（形状）
   真实影响是否可接受属 owner 明文回环裁定的既有范围，本轮不重新定性。

MCP 9 工具写集（本轮逐条定位）：
`simigo_is_search`:355（写 T0）、`simigo_is_status`:390、`simigo_roots_list`:406、
`simigo_root_register`:421（`upsertRoot` :436 / `settleWorkRootContents` :439）、
`simigo_is_reconcile`:456、`simigo_is_settlement`:473、`simigo_es_begin`:510
（新态才 `recordExecutionState` :548-552；resume 校验 model + tokenizer 身份 :525-534；
:556-559 显式声明 begin 不解析当前 demand）、`simigo_es_settle`:570、`simigo_es_fail`:720。**C**

⇒ 剩余待核调用链：roots 写入与文件系统副作用、branches 三条、LOCALB challenge 仪式、
reconcile 的完整写集。这四项完成后，六范围里的「完整副作用」与「完整调用链」才覆盖 main 全路由。
