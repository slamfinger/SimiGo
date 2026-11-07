# #391 全仓问题清单 全貌（三类，截至 2026-11-07）

## 0. 基线、来源与编号纪律

- 权威基线：`origin/main = 8d87e325928277078afc4fb892f4749a3ce39082`（2026-11-06 21:41:29 +0800）。本地 `main = 6c093f9` 是其祖先，落后 37 个提交，不用于任何结论。
- 本文**只是汇总**，不新增事实、不重新定性、不给修复方向。每一条都带来源标记，可回放到下列四份记录之一：
  - **[M]** 核验 1–9 汇总（会话内报告，条目号 `D-*`／`G-*`／`V-*`）
  - **[S12]** [CODE-AUDIT-STEPS-1-2-20261107.md](./CODE-AUDIT-STEPS-1-2-20261107.md) §5（条目号 `A新-*`／`B新-*`／`C新-*`）
  - **[S3]** [CODE-AUDIT-STEP3-397-20261107.md](./CODE-AUDIT-STEP3-397-20261107.md) §5（条目号 `A-*`／`B-*`／`R-*`）
  - **[V4]**／**[V7]** 真机读数 [V4-FINDINGS-20261107.md](./V4-FINDINGS-20261107.md)、[V7-FINDINGS-20261107.md](./V7-FINDINGS-20261107.md)（条目号 `V-4`／`F-A/B/C`／`V-7`）
- **编号命名空间不合并**：`D/G/V`、`A新/B新/C新`、`A/B/R` 是三套轮次内编号，同一事实在不同轮被重新编号过。本文保留原始 ID 作 provenance，本文自身的顺序号（Ⅰ-1 … Ⅲ-13）只是目录位置，不得当引用键。
- V-4 的 **F-A／F-B／F-C** 与 **V-7** 依 owner 裁定继续独立，不并入任何同类条目。
- 证据等级沿用 [S3] §0：C=代码事实；C-NEG=负面核验；R=仍需运行时证据；D=设计决策（依既有裁定只登记）。

---

## Ⅰ. 已确认的实现缺陷（代码层可直读证明；20 条）

| # | 条目 | 锚点／来源 | 等级与限定 |
|---|---|---|---|
| Ⅰ-1 | chat 提交失败被静默吞掉且不阻断结算：三处 `try? turn.db.commitChatTurn(...)`，返回值与错误都不检查，紧接着照常写权威结算 | `HTTPServerChat.swift:349`、`:527`、`HTTPServerResponses.swift:1013` [M D-1] | C；两个方向的持久化不一致都成立 |
| Ⅰ-2 | chat 的「提交 + 结算」是两个事务，`commitChatTurn` 单事务与 `settleTurn` 之间无边界；`839e1ed` 只原子化了 continuation 侧 | `SimiGoESISDatabase.swift:3584-3607`、`SimiGoISAdmission.swift:226-249` [M D-2] | C；可命中性由 [V7 V-7] 真机证实（独立条目） |
| Ⅰ-3 | responses 线缺 `producedToolCalls` 中间轮守卫（chat 有） | `HTTPServerResponses.swift:1017-1028` vs `HTTPServerChat.swift:365-369`；`grep producedToolCalls origin/main` 仅命中 chat [M D-3] = [S12 A新-6] | C（守卫缺失）+ 条件性风险；[V4 V-4] 真机**未复现**脏结算，未被证伪 |
| Ⅰ-4 | demand 状态可回退且推进无前置条件：检索写入把已 `ADVANCED` 倒回 `RESOLVED` 并覆写 5 列；推进侧无条件 UPDATE | `SimiGoESISDatabase.swift:4411-4419`、`:4544` [M D-4] | C；`information_demands.state` 不单调 |
| Ⅰ-5 | `pending` 用户行是无人认领终态：失败／取消／断连／internal-operation 轮永不转正，全仓无对账或回收站点，检索门永久排除 | `SimiGoESISDatabase.swift:3954`（门）[M D-5] | C；正常工具轮会被后续 `commitChatTurn` 提升 [V4 §2]，「客户端拿到 function_call 后不再继续」一支未覆盖 |
| Ⅰ-6 | 失败与取消轮没有任何持久化事实：三处 catch 只写 trace；`recordFailureAudit` 产品侧唯一调用点是 MCP `simigo_es_fail` | `HTTPServerChat.swift:1036/1058/1082`、`HTTPServerMCP.swift:735` [M D-6]；六条 wire 全部命中 [S12 §3.1] | C（A-6 覆盖面＝六条 wire 零调用，非仅 chat） |
| Ⅰ-7 | 断连（detach）语义在四条 wire 上互不相同：只有 chat 流式照常结算，chat 非流式／responses 流式／responses 非流式静默丢弃 | `HTTPServerChat.swift:977-983` vs `:1421-1427`、`HTTPServerResponses.swift:1388-1393`、`:1953-1958` [M D-7] = [S12 A新-2] | C；同一条缺陷的两轮覆盖面，非两个缺陷。真实客户端发生率＝Ⅲ-10 |
| Ⅰ-8 | 汇总是 best-effort 追加：`_ = try? recordSettlementSummary(...)`，失败不影响结算成立，且无重试或补偿入口 ⇒「已结算无摘要」是允许态 | `SimiGoInformationLoop.swift:593-657` [M D-8] | C；发生率＝Ⅲ-7 |
| Ⅰ-9 | 工具治理孤儿扫描从不运行、登记表永不淘汰：`reportOrphans` 产品零调用，`invocations` 无清理站点 | `ToolGovernance.swift:227`、`:53-55` [M D-9] | C |
| Ⅰ-10 | 外部轮次转正不校验任何身份：同 `(session_id, request_id)` 两行齐即 `recorded→committed` 并获检索可见性，与「谁执行、谁有权提交结果」无关 | `SimiGoESISDatabase.swift:3726-3745` [M D-10] | C；责任面缺口见 Ⅱ-2 |
| Ⅰ-11 | GGUF 受管入口丢弃调用者身份：解构把 agentId／sessionId／logicalBranchId 全部扔掉 | `ManagedGGUFRuntime.swift:74` [M D-11] | C；这是 #90 冷 prefill 的代码根因，可测后果归 Ⅲ-1 |
| Ⅰ-12 | 描述面缺陷：注释与实现互相矛盾（注释仍写「detach 不结算不提交」） | `HTTPServer.swift:1172-1175` vs `HTTPServerChat.swift:970-977` [S12 A新-3] | C；后果是误导后续审核 |
| Ⅰ-13 | `prepareInformationTurn` 的写副作用先于全部前置门（六道门：fork 400／W4 503／admission／markGenerationStarted／SSE 头／生成前取消），被拒请求留下无消费者的持久残留，无失效、无审计行 | [S12 §2 表] | C；「污染检索」的夸大成法已核掉（读侧三源排除 pending 与 `IS_RETRIEVAL`；demand 三查询点要求 `ADVANCED`；`SUPERSEDED` 由 `request_identity` 限在同一请求内，`SimiGoESISDatabase.swift:4436-4439`） |
| Ⅰ-14 | `loop.resolve` 的检索事务与源边绑定分离，绑定抛错被上层 `try?` 吞掉，留下「RESOLVED + valid 但无源边」且仍按 `reused` 供 | [S12 §4] | C |
| Ⅰ-15 | Responses 空身份静默返回：`settlementID != nil` 分支里 T1 已提交后直接 `return`，advancement／link／summary 一笔不写，且连 `[SETTLE_SKIP]` trace 都没有；空 `demandID` 有真实生产者 | `HTTPServerResponses.swift:1030-1033`（对比 `:1017`/`:1023` 均有 trace）、`HTTPServerChat.swift:219-221`+`:325`、`SimiGoISContextLedger.swift:72-88` [S12 A新-1] = [S3 A-9] | C；定性按 owner 限定 —— **仅在空身份条件下**，T1 与后续结算记录之间存在静默断裂 |
| Ⅰ-16 | branch delete 会话表键不对称：fork 的 child 落在带客户端分片后缀的 `targetMapKey`，delete 只对精确 `storageKey` 做 `removeValue` 且不经 `resolveSessionMapKey` ⇒ 守卫放行、`session.clear()` 不执行、其余清理照常、响应仍 `ok:true` 且 `remaining_live` 自证残留 | `NativeMLX.swift:3256-3286` vs `:3359`、`:296-305`、`:3394-3397`、`HTTPServer.swift:2890` [S3 A-10] | 机制 C；可达性 R＝Ⅲ-9 |
| Ⅰ-17 | 分支陈旧性守卫只到传输层：`expected_generation` 被解析并传入但无宿主强制；`branchGenerationMismatch` 零生产者 ⇒ 409 分支不可达 | `HTTPServer.swift:2844`/`:2855`/`:2870`、`BranchLifecycle.swift:55`、`NativeMLX.swift:485`+注释 `:495-499` [S3 A-11] | C + C-NEG；S3-A「never a silent ok」在类型化错误面成立、在守卫生效面未接通 |
| Ⅰ-18 | **[F-A]** 未认证 `GET /v1/simigo/search` 跨会话读取整个个人 IS 空间（真机：返回另一会话的 user 原文与 assistant 答案） | `HTTPServer.swift:1912-1913` [V4 §3] | 真机+代码双证；配对负控 `hits=0` ⇒ 问题在**范围**与**未认证**，不在「不过滤」。其 `.open` 分类本身属 Ⅳ 只登记项 |
| Ⅰ-19 | **[F-B]** 同一 GET 是持久化写操作且重复同输入永不复用：三次相同 `q` 各产生新 `information_demands`/`settlements`/`retrieval_settlements` 行（4→5→6→7），行停 `RESOLVED`、`session_id IS NULL` | `SimiGoInformationLoop.swift:161`、`:264-271`、`:273-283`；与路由自述 `HTTPServer.swift:1858` 冲突 [V4 §3] | 真机+代码双证；未认证方可无界增长该三表 |
| Ⅰ-20 | **[F-C]** 检索结果摘要含时间戳，同结果集摘要不稳定 | `SimiGoInformationLoop.swift:289`、`:291-295`；实测同 3 条 items 得 3 个不同 `result_sha256` [V4 §3] | 真机+代码双证；边界：`reused=true` 分支摘要稳定，但该分支在 /search 入口不可达 ⇒ 不是「摘要到处不稳定」 |

F-A／F-B／F-C 的 main 归属已核：三处站点在载体 `66984a1` 与 `origin/main 8d87e32` 上逐字节一致（两个代码块 md5 相同、`call:` 生成行同为 `:161`）。

---

## Ⅱ. 已确认的架构缺口（需要承载体，加枚举解决不了；15 条）

| # | 条目 | 依据／来源 |
|---|---|---|
| Ⅱ-1 | **G-1** 推理入口与结算写集耦合：`inference` 一次调用实际触碰 `appendChatMessage → recordInformationRetrieval → linkSettlementToExternalFile → commitChatTurn → recordNativeSettlement… → insertInformationAdvancementRows → recordSettlementSummary`，而权限表从未表达这一串 ⇒ 现有四值权限矩阵不是完整权限矩阵 | `HTTPServer.swift:1596` [M G-1] |
| Ⅱ-2 | **G-2** 四个身份平面（认证面 `clientKeyID`／声明面 `simigo_source_*`+MCP 参数／测得面 `SimiGoSettlementIdentityBinding`／进度面 ES）没有分离承载体；声明身份与测得身份写进同一组字段（MCP begin 与原生 settle 同表） | `HTTPServerMCP.swift:510-549` [M G-2] |
| Ⅱ-3 | **G-3** 认证主体在写入发生前已不可用（`clientKeyID` 进 handler 前被丢弃）⇒ 任何只加枚举而不贯通身份的修复落不到具体写行 | [M G-3] |
| Ⅱ-4 | **G-4** 工具执行没有事实面：无内部执行器（v1 恒为 observed），返回内容从不入库，GGUF／Oversized 两线未接治理 ⇒ 改文件／改库／调外部 API／产生新 Agent 任务／工具成功而模型随后失败，五类副作用在 ES/IS 里无处可查；`VALIDATED ≠ 结果已纳入 ES/IS` | `ToolGovernance.swift:53-55` [M G-4] |
| Ⅱ-5 | **G-5** 「结算不依赖 KV」目前只是 NativeMLX 的设计原则 + 一条默认关路径实现：`kvRepresentation` 唯一生产来源 `NativeMLXPrefixPool.representation` 而磁盘池默认 OFF；GGUF 与 Oversized 诚实拒绝分支；vendored ChatSession 物理 KV 未测 | `ContinuationSettlement.swift:261`、`ManagedGGUFRuntime.swift:94-101`、`OversizedRuntime.swift:111-116` [M G-5] |
| Ⅱ-6 | **G-6** 管理与推理没有能力边界：`LOCALBPermission` 无 management 类；起停引擎／换模型／改 roots 与推理同平面；缺陷实质是**未认证调用能够触发持久化副作用** | `HTTPServer.swift:1596-1645` [M G-6] |
| Ⅱ-7 | **G-7** 生命周期只表达成功推进：取消／失败／被放弃的轮次无状态承载（Ⅰ-6 是其实现层表现，Ⅱ-7 是设计层原因） | [M G-7] |
| Ⅱ-8 | **B新-1** 产品内不存在任何 repair／reconcile／invalidate 链处理半写状态；唯一回填是迁移期 settlement→summary 且排除检索类 | [S12 §3.3]；与 [V7 §6] 动态证据同向，各自独立保留 |
| Ⅱ-9 | **B新-2** IS 检索资格权威（`turn_state='committed'`）与 settlement／ES lineage 权威在 schema 层没有对齐机制 | `SimiGoESISDatabase.swift:3775`、`:3954` [S12]；owner 对 V-7 的裁定即此条的研究含义 |
| Ⅱ-10 | **B新-3** `SimiGoISAdmission.settleContinuation` 是公开、单事务、已测试但**未接线**的权威入口（产品零调用者；`.admit` 才用于 `SimiGoSettlementConsumption:205/:296`、`ExecutionStateGraph:628`） | `SimiGoISAdmission.swift:223-252` [S12] |
| Ⅱ-11 | **B-8** 失效触发面缺失：无文件监听，`invalidateSourceFile`／`reconcileRoot` 产品零调用 ⇒ 运行时自动失效未实现（承待裁项 #28） | [S3 §4/§5] |
| Ⅱ-12 | **B-9** 分支命名空间由客户端声明字段决定（`agent_id`／`x-simigo-agent`／`x-agent-id`，缺省 `default`），与 LOCALB 认证主体无绑定：`branchControl` 认证的是客户端 | `HTTPServer.swift:3085`、`StreamTokenFilter.swift:157-167` [S3] |
| Ⅱ-13 | **B-10** `legacy-v1` 结算失效作用域为全库而非单根 | `SimiGoESISDatabase.swift:5375-5378` [S3] |
| Ⅱ-14 | **B-11** 非 MLX 宿主的 `branches/list` 与「无分支」不可区分（`ok:true` + 空集），且 fork/delete 拒绝被降级为通用 400（抛 `RuntError`，非 `BranchLifecycleError`） | `InformationSpaceRuntime.swift:61-66`、`ManagedGGUFRuntime.swift:96-101`、`OversizedRuntime.swift:108-115`、`HTTPServer.swift:1125-1142` [S3] |
| Ⅱ-15 | **B-12** 分支派生血统（parent→child）无持久载体：唯一记录处是进程内 128 条环形缓冲，其唯一产品消费者是只读展示投影 ⇒ 重启后「该分支由谁派生」在产品侧无可查询事实；ES/IS/SQLite 无分支级 lineage 行 | `ExecutionLineage.swift:80-88`/`:48`、`NativeMLX.swift:3123-3145`、`Service.swift:549`、`ExecutionStateGraph.swift:1192/1220/1261` [S3 §2] |

---

## Ⅲ. 仍需运行时证据（有设计意图 ≠ PASS；开放 13 条）

| # | 条目 | 关联缺陷 | 前置条件 |
|---|---|---|---|
| Ⅲ-1 | **V-1** llama.cpp abort 后引擎是否继续生成到完成、slot KV 取消后处于何态、引擎侧 `cache_prompt` 复用（`GGUFEngineClient.swift:262`、`cached_tokens` `:164-166`）是否归属到任何主体 | Ⅰ-11 | 需 owner 开 GGUF 隔离真机窗口（#393；本机 llama.cpp 未下载完全） |
| Ⅲ-2 | **V-2** vendored `ChatSession.streamDetails` 的物理 KV extend／rewind 可证明边界 | Ⅱ-5 | 同上类窗口 |
| Ⅲ-3 | **V-3** Oversized 全局 `generationLock`（`:182`）叠加取消 no-op（`:122`）时，不可取消长请求对其他客户端的实际阻塞时长 | — | #393 |
| Ⅲ-4 | **V-6** TLS（secure）监听器在真实部署里是否默认启用 | — | 部署形态，非代码 |
| Ⅲ-5 | **V-9** 并发度 >1 时 admission／`finishLifecycle` 与 FORCE_RELEASED 的分布（GGUF 曾实测 32 次，修复后未复测） | — | 干净窗口 |
| Ⅲ-6 | **C新-1** `.capped`／`.unconfirmed` 的真实产生频率（生产者已定位：`NativeMLX.swift:2363-2368`、`:1465`、`:1903`、`GGUFEngineClient.swift:223-224`、`OversizedRuntime.swift:255`） | — | 引擎事件流实测 |
| Ⅲ-7 | **V-8** `recordSettlementSummary` 在真实负载下的失败率 | Ⅰ-8 | 统计窗口 |
| Ⅲ-8 | **C新-2** 空 resolution 分支在真机的可达频率（需让 `loop.resolve` 抛错同时带 `continuationSettle`）——**未做实验，保持未验证** | Ⅰ-14 | 可控注入 |
| Ⅲ-9 | **R-6** 分片后缀键场景的实际发生率（Ⅰ-16 的可达性） | Ⅰ-16 | 真实双客户端分片 |
| Ⅲ-10 | **C新-3** detach 在非流式／responses 上的静默丢弃是否曾在真实客户端出现 | Ⅰ-7 | 断连窗口；与 #121/#134/#135 同域，不新起实验 |
| Ⅲ-11 | **C新-4** Responses 用 `queryOverride` 后的检索质量变化（与 P1 检索净化同域） | — | 真实模型对照 |
| Ⅲ-12 | **R-5** `settleWorkRootContents` 在 BEGIN IMMEDIATE 内做全树 IO，与 T1–T4 争同一句柄 ⇒ 并发时长／`SQLITE_BUSY` | Ⅰ-13 同库面 | 并发实测 |
| Ⅲ-13 | **R-7** 大根扫描对首启（bootstrap step 5/6）与 HTTP 延迟的影响 | — | 真机计时 |

**已取读数、不再列在待验证类**：

- **V-4**（responses 工具循环中间轮是否签发脏结算）——真机 **未复现**；[V4 §1] 明写「不是已证实的产品故障，也未被证伪」，覆盖缺口＝换用会先叙述再调用的后端即可能触发，本窗口未覆盖。关联 Ⅰ-3。
- **V-7**（chat 提交后、ES 结算前真实 SIGKILL）——真机 **命中**，产生持久半状态；六层定性依 owner 2026-11-07 裁定分列且**不合并**（实现缺陷／恢复机制／IS 资格／ES lineage 各为确认，数据损坏与答案丢失、模型实际消费崩溃答案＝未证实不升级）。关联 Ⅰ-2、Ⅱ-8、Ⅱ-9。
- **V-5**（云端 API／混合推理）——依 owner 2026-11-06 裁定改为三分，不再是「待验证」：现存路径核验＝LOCALB 远程面 + MCP 外部 Agent；缺失路径事实＝当前 main 无云端 API forwarding／RemoteProxy（`forwardToRemote|RemoteProxy|remoteAPI|dashscope|api.openai` 在 `8d87e325` 命中 0，C-NEG）；不作推论＝不因此认定云端/混合架构设计不存在，也不把路径缺失归类为实现缺陷。

---

## Ⅳ. 只登记、不重新定性（依既有裁定）

- `.open` 的 `PUT|POST /v1/simigo/roots`（`HTTPServer.swift:1609-1610`）与 `.protected(srsWrite)` 的 `/reconcile`（`:1619-1622`）在同一 IS 写面上分类不同；branches 三条 = `.protected(.branchControl)`（`:1634-1644`，owner 2026-11-05 S2 裁定取代 B3 全拒）。
- IS 句柄形态差异：`/search` 与 roots PUT 走 `createIfNeeded: true` + `try runMigrations()`（`:1885`/`:2370`），9 个只读入口走 `false`。
- 明文回环许可集 `{.inference, .informationRead, .srsWrite}` 的分类后果 —— 属 owner 2026-10-26／11-05 既有裁定范围。

## Ⅴ. 关键负面核验（C-NEG 目录，防止把「不存在」误读成「已修」）

1. 当前 main **无**云端 API 转发／RemoteProxy 实现（多关键词命中 0）。
2. `/localb/auth/challenge` **零持久副作用**：`loadPairingState` 只读共享锁（`exclusive:false` + `createRootIfMissing:false`，`Packages/LOCALBCore/Sources/LOCALBCore/LOCALBRegistryStore.swift:168-180`），唯一写入是进程内存台账（`LOCALBClientChallengeLedger`，同包 `LOCALBPairingCoordinator.swift:989-1062`，`issue :1009`／`consume :1043`）；journal 写类原语只由管理面调用，HTTP 可达路径不触及。
3. branches 三条对 SQLite／ES／IS **零命中**，含 lineage 与内存池；全部副作用限于进程内状态 + `branchCheckpointsEnabled` 下的 checkpoint 文件。
4. `branchGenerationMismatch` **零生产者** ⇒ delete 的 409 不可达。
5. MCP `simigo_is_reconcile` **不接** `max_age_seconds`（`HTTPServerMCP.swift:456-471` ⇒ `minAgeSeconds=0`）且响应形状缺 `unlocatable_roots` ⇒ 两入口报告不等价。
6. 三个先前怀疑被代码否证（原样保留，不降级为「未核验」）：`purge(esStateID:)` 与 capture 键一致（`NativeMLX.swift:2199`/`:2020`）；roots PUT 失败不会留下不可定位根（`HTTPServer.swift:2374` + `COALESCE` `SimiGoESISDatabase.swift:5044`）；Apple-epoch 时间码不妨碍 `minAgeSeconds`（`parseISO8601` 先 `Double` 往返，`:6579-6581`）。
7. `git grep` 的 pathspec 通配 **不跨 `/`**：限定 `Packages/*/Sources` 会静默漏掉 RuntimeContract 内部调用点 ⇒ 穷举类断言必须无路径限制重跑（曾因此把 `upsertRoot` 的 6 个调用点误报为 4 个）。

## Ⅵ. 覆盖度：全仓事实核验现在到哪里

- **端点面**：`origin/main` 实测 **17 个 HTTP 端点**（[S12 §7] 表）。覆盖率要分两面说，不得合并成一句「已全核」：
  - **写入／副作用链已逐条闭合**：三条推理线（chat／responses／completions）、MCP 9 工具、`/search`（含 T0 持久写）、`/reconcile`、`roots` PUT/POST、branches 三条、`/localb/auth/challenge`，以及六条 wire 的失败／取消／断连／进程终止写集。六范围里的「完整调用链」与「完整副作用」到此覆盖 main 全部**有副作用**的路由。
  - **只读面只盘点了句柄形态**（`GET /health`、`/v1/models`、`/models`、`/v1/models/<id>`、`/v1/simigo/env`、`is/status`、`is/settlement`、`is/dependency`、`is/file`、`is/object`：`createIfNeeded: false`，锚点见 [S12 §7] 末两行），**未逐端点单独核验**其读集与错误面。这是一项覆盖度限定，不是负面结论。
- **[M #387] 的六项残留**已被三类清单逐条吸收，不需独立再跑：GGUF 引擎侧→Ⅲ-1；OversizedRuntime→Ⅲ-3；advancement SQL→Ⅰ-4；ToolGovernance→Ⅰ-9；vendor KV→Ⅲ-2；TLS 默认→Ⅲ-4。
- **仍未核验、保持未验证**（不得当作结论引用）：
  1. `EnvManager.swift:542`（`bootstrapFreshDatabase`）与 `:840`（`registerWorkRoot`）两条注册入口与 HTTP／MCP 入口的写集等价性 —— 形状同构，未逐字段闭合；`registerWorkRoot` 的 `workRootsDidChange` 广播（`:806`/`:859`）消费方未查。
  2. 内存池跨会话共享分支标签的实际命中／失效影响 —— 仅证键语义，未取读数。
  3. `indexExternalFile` 首建根的 `display_name IS NULL` ⇒ 以 `category:"model"` 调 reconcile 时全计入 `unlocatableRoots` —— 已登记形状，实际后果未测。
  4. 未提交候选与 PR 分支相对 `origin/main` 的差异一律不作为事实引用。
- - 分类纪律不变：Ⅰ 类可局部修复；Ⅱ 类需要设计承载体；Ⅲ 类不得因代码中的设计意图转 PASS。
- **P1／P2 优先级口径本轮未逐条赋值**：既有记录里只有零散的优先级引用（如 G-6 关联 owner「P2 1」、A-9 依 owner 判断「优先级值得提高」）。逐条排序属产品改造取舍，按既定顺序应在架构审核阶段由 owner 输入，本文不代拟。
