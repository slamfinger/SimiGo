# 代码级核验 3（#397）：roots PUT ／ branches 三条 ／ LOCALB challenge ／ reconcile 全写集

## 0. 身份、方法与边界

- 权威基线：`origin/main = 8d87e325928277078afc4fb892f4749a3ce39082`（2026-11-06 21:41:29 +0800）。所有锚点取 `git show origin/main:<file>` / `git grep -n … origin/main`，逐条现场重测；本地 HEAD 不用于任何结论。
- 只读副本：`/tmp/audit-om/`（本轮新增 `BranchLifecycle.swift`）。
- 本轮**零产品代码改动、零新真机实验、零架构裁决**。
- 证据等级：
  - **C** = 代码事实（调用关系、写集、事务边界、可达性由代码闭合）。
  - **C-NEG** = 负面核验（某路径不存在／某状态无生产者／某分支不可达）。
  - **R** = 仍需运行时证据。
  - **D** = 设计决策，依既有裁定只登记、不重新定性。

---

## 1. `POST /localb/auth/challenge` —— 零持久写（C-NEG）

真实调用顺序：路由 `SimiGo/Protocol/HTTPServer.swift:2614` → `handleLOCALBChallengeRequest` `:2399-2472`：

1. 传输信任门 `eligibleForLOCALBPairingBinding` `:2403`（否则抛 `localbTransportNotTrusted`）；
2. 授权可用性 `localbRequestAuthorization` `:2406`（nil 即抛）；
3. 客户端键 `x-simigo-localb-client-key-id` `:2409`；
4. 请求表示规范化 `:2413-2426`（canonical method／`/` 前缀／不含 `#`／≤ `maxTargetBytes`）；
5. 路由策略必须 `.protected(permission)` `:2434-2448` —— `.denied` 显式拒绝、`.open` 反而 `badRequest`；
6. `coordinator.issueRequestChallenge(clientKeyID:permission:checkpoint:)` `:2455-2459`；
7. `LOCALBStatus` → `badRequest(status.rawValue)` `:2460-2462`；返回 challenge 十六进制 + permission `:2463-2471`。

事务边界与写集：

- `LOCALBPairingCoordinator.swift:1242-1256` → `LOCALBRegistryStore.loadPairingState` `Packages/LOCALBCore/Sources/LOCALBCore/LOCALBRegistryStore.swift:168-180`：`exclusive:false, createRootIfMissing:false` ⇒ **只读共享锁**，不建根、不追加事件。
- 唯一写入 = `LOCALBClientChallengeLedger` `:989-1062`，纯进程内存（`issued: [String: IssuedChallenge]` + `issuanceLog`）；`issue` `:1009-1041` 生成 32 随机字节、id=sha256 hex、过期即过滤；`consume` `:1043-1056` 单次 `removeValue` + client/permission/过期校验。参数：`lifetimeMilliseconds=60_000`、`maximumPending=8_192`、`maximumPendingPerClient=64`、`issuanceWindowMilliseconds=10_000`、`maximumIssuesPerClientPerWindow=128`。
- SQLite：本路由零命中。

失败与重启：无持久状态残留；进程重启 ⇒ 台账清空 ⇒ 已发出挑战一律不可消费（客户端须重新挑战），不存在需要恢复的中间态。

journal 写类原语（`appendKeyRegistration:196`、`appendKeyStatusChange:236`、`commitPairing:393`、`appendClientRevocation:523`）只由管理面调用，**HTTP 可达路径不触及**。⇒ 结论 **C-NEG**：LOCALB 挑战路由不产生任何持久副作用。

---

## 2. branches 三条 —— HTTP 层零 DB 写，副作用全在引擎进程内 + 文件系统

路由：`HTTPServer.swift:2763`（fork）／`:2817`（delete）／`:2903`（list）。
LOCALB 策略：`:1634-1644` = `.protected(permission: .branchControl)`（owner 2026-11-05 S2 裁定，取代 B3 全拒；依既有裁定只登记）。

调用顺序：三条 handler 全部只调引擎闭包 —— `forkBranchHandler` `:2794`、`deleteBranchHandler` `:2848`、`listBranchesHandler` `:2925`（类型声明 `:654/:679/:680`，注入 `:797-799`、`:833-835`）。**三条路由对 SQLite／ES／IS 原语零命中**（C-NEG）。

引擎写集（`SimiGo/Inference/NativeMLX.swift`）：

| 操作 | 锚点 | 实际写入 |
|---|---|---|
| fork | `:3203-3339` | 键锁 `gate.withExclusive(transactionKeys)` `:3233`（`RuntimeTuning.serializeGeneration` 决定是否含全局代际键 `:3228-3230`）→ 内存会话表：旧 target `removeValue` `:3260-3262` + `clear()` `:3263`、新 child 写入 `:3285-3288` → 旧 target checkpoint 文件 `removeItem`（`.safetensors`/`.meta.json`，仅 `branchCheckpointsEnabled` `:3266-3271`）→ `NativeMLXPrefixPool…bindings.bind` `:3313` → `lineage.recordFork` `:3323` → trace `:3317-3322` |
| delete | `:3343-3382` | `gate.withExclusive(generationKey)` `:3357` → 会话表 `removeValue(forKey: key.storageKey)` `:3358-3360` → `session.clear()` `:3361-3363` → `bindings.detach` `:3368` → `PrefixMemoryPool.shared.purge(esStateID: logicalBranchId)` `:3371` → checkpoint 文件 `removeItem` `:3373-3377` → trace `:3379-3380` |
| list | `:3385-3408` | 只读：内存键前缀扫描 `:3394-3397` + `contentsOfDirectory` `:3401-3406`；`branchCheckpointsEnabled` 关闭时 `checkpoints` 直接为 `[]` `:3401` |

事务边界：无 SQLite 事务。原子性来自引擎**进程内键锁**，不是持久化事务 ⇒ 崩溃后不存在"半条分支记录"可回滚（C-NEG）。fork 返回值自陈是本次事件的描述符而非 durable receipt（`:3328-3337`）；child 的盘上 pair 由其首个成功轮写入。

血统与投影的持久化面（C-NEG，本条为该疑点的收尾读数）：`lineage.recordFork`（`NativeMLX.swift:3323` 调用）只向进程内环形缓冲追加 —— `SimiGo/Inference/ExecutionLineage.swift:80-88` 在 `lock.withLock` 内 `storage.forks.append(BranchForkEvent(parent:child:at:))`，超过 `capacity` 即 `removeFirst` 丢弃最旧（`capacity` 缺省 **128**，`:48`；存储为 `private struct Storage { records; forks }` `:40-43`，无任何文件／DB 句柄）。`snapshot`（`:90-94`）在产品侧只有一个消费者：`NativeMLX.executionStateSnapshot()` `:3123-3145`，其结果 `EngineExecutionStateSnapshot` 再经 `SimiGo/System/Service.swift:549` 的 `@Published` 交给 `SimiGo/App/ExecutionStateGraph.swift:1192/1220/1261` 的 SwiftUI 展示（fork 行 `parent → child` 标签）。⇒ **分支 fork 链不进 SQLite／ES／IS，重启即失，且仅作展示事实源**（该文件自陈"零 IO、零行为，不参与任何执行决策" `:3121-3122`）。据此可把本节顶部的"三条路由对 SQLite／ES／IS 原语零命中"加强为：**含 lineage 环形缓冲与内存池在内，三条分支路由的全部副作用限于进程内状态 + `branchCheckpointsEnabled` 之下的 checkpoint 文件**。

四个代码级差异点（本轮新增事实）：

1. **错误映射不对称（C）**：fork `:2794` 无局部 `do/catch`；delete `:2847-2880` 只捕 `BranchLifecycleError`（→ 404／409）。任何非 `BranchLifecycleError` 一律冒泡到 route 外层 `:1125-1142`，`HTTPServerError` 之外的错误按 **400** + `localizedDescription` 发出。
2. **陈旧性守卫只到传输层（C-NEG）**：`expected_generation` 被解析（`:2844`）并传入（`:2855`），但无宿主强制它 —— NativeMLX 闭包接住不用（`:485`，注释 `:495-499` 自陈 RESERVED）。`BranchLifecycleError.branchGenerationMismatch` 全仓仅两处：声明 `SimiGo/Protocol/BranchLifecycle.swift:55`、消费 `HTTPServer.swift:2870`，**零生产者** ⇒ 409 分支不可达。
3. **非 MLX 宿主的分支面（C／C-NEG）**：`InformationSpaceRuntime.swift:61-66`、`ManagedGGUFRuntime.swift:96-101`、`OversizedRuntime.swift:108-115` 把 fork/delete 实现为抛 `RuntError.generationFailed`／`RuntError.notLoaded`（**不是** `BranchLifecycleError`）⇒ 经第 1 点落为 400；三处 `listBranchesHandler` 均返回 `(live: [], checkpoints: [])` ⇒ 响应 `ok:true` + 空集，无法区分"该宿主不追踪分支"与"确实没有分支"。
4. **会话表键不对称（机制 C／可达性 R）**：fork 的 child 落在带客户端分片后缀的 `targetMapKey`（`:3256-3259` + `:3286`），而 `deleteSessionBranch` 只对精确 `key.storageKey` 做 `removeValue`（`:3359`），**不经** `resolveSessionMapKey`（`:296-305`，仅 save/load/fork 使用）。当后缀非空时：`listSessionBranches` 的前缀扫描使 `hadLive` 判真（`:3394-3397`）→ 守卫放行，但删除命中 `nil` ⇒ `session.clear()` 不执行，而 `bindings.detach`／`memPool purge`／文件清理照常发生，响应仍 `ok:true`，且 `remaining_live`（`:2890`）会把带后缀的键原样列出。分片后缀实际发生率未测 ⇒ 定性：机制已证、可达性 R。

顺带闭合的 #136 相关事实：内存池条目的 `esStateID` 字段实际存放 `executionKey.logicalBranchId`（capture 调用 `NativeMLX.swift:2194-2201`、采纳上下文 `:2020-2221`，`PrefixMemoryPool.setAdoptionContext:81-88`／`capture:95-141`／`purge(esStateID:):294-311`）。⇒ **C-NEG**：先前「delete 的 purge 永不命中」的怀疑被代码否定，键一致。代价是同一分支标签跨会话共享该身份字段；采纳仍受内容寻址 `poolKey`（modelID／kvFingerprint／tokenCount／boundaryHash，`:101-107`）与最长 token 前缀匹配约束，复用有效性来自内容而非会话。

身份与责任（C）：`agentId` 完全来自客户端声明字段（body `agent_id`／`x-simigo-agent`／`x-agent-id`，`resolveExplicitAgentId` 起 `HTTPServer.swift:3085`），缺失时 `AgentExecutionKey.normalize` 回落 `"default"`（`SimiGo/Inference/StreamTokenFilter.swift:157-167`）。LOCALB `branchControl` 签名认证的是**客户端**，不是 agent/session ⇒ 分支命名空间与认证主体之间无绑定（会话/分支标识可被任何持该权限的客户端指名）。

---

## 3. roots PUT —— 两段独立写，注册与内容结算之间有真实窗口

路由：`HTTPServer.swift:2651`（`PUT` 与 `POST` 共用 `handleSimigoRootsPutRequest`）。策略 `:1609-1610` = `.open`（**D**，依 owner 既有 LOCALB 明文裁定只登记）。

调用顺序 `:2345-2397`：

1. body／绝对路径校验 → 400 `:2349-2358`；
2. `standardizingPath` + 目录必须存在 → 422 `WORK_ROOT_NOT_FOUND` `:2359-2368`；
3. 句柄 `createIfNeeded: true` + `try db.runMigrations()` `:2370-2371`；
4. `rootID = "work-" + EnvManager.stableRootID(forPath:)` `:2372`（FNV-1a 64 位十六进制，`SimiGo/System/EnvManager.swift:878-885`）；
5. `try db.upsertRoot(…, displayName: 路径, locatorType: "path", status: "registered")` `:2373-2375`；
6. `try db.settleWorkRootContents(…, carryText: false)` `:2376-2378`；
7. 200 报告（含 `content_settle` 十字段）`:2379-2391`；
8. `catch` 统一 500 `DATABASE_ERROR` + `"\(error)"` `:2392-2396`。

事务边界（关键，**C**）：

- `upsertRoot`（`SimiGoESISDatabase.swift:5036-5055`）= 单条 `execBinding`（隐式 autocommit），**不在** settle 事务内；`ON CONFLICT` 只更新 category/display_name/locator_type/status，不重置 `created_at`，也不动 `last_scanned_at`。
- `settleWorkRootContents`（`:2654-2964`）= 整体包在 `transactionResult`（BEGIN IMMEDIATE，`:1510-1533`）之内，且**文件系统枚举（`:2726-2745`）与逐文件 `Data(contentsOf:)`（`:2777`）全部发生在写锁持有期间**。

⇒ 由此得两个事实：
1. 崩溃／失败窗口真实存在：**注册行已提交、内容结算全无**（`roots.status='registered'` 而无 `file_contents` 行）。因 handler 已把绝对路径写进 `display_name`（`:2374`），该行仍可被 reconcile 再扫描 ⇒ **C-NEG**：「PUT 失败留下不可定位的根」不成立。
2. 写锁跨越整棵目录树的磁盘 IO，而 chat／responses 的 T1–T4 各开独立 BEGIN IMMEDIATE 使用同一句柄 ⇒ **R**：并发时长与 `SQLITE_BUSY` 影响未测（与 #223-A 同故障域，不复用其结论）。

失败语义（settle 内部，全 C，全有或全无）：

- 不可枚举根 → `throw` `:2739-2745`（注释 `:2740-2742` 明确拒绝把"读不到"伪装成"全被删除"）；
- 枚举中任一子项错误 → 在计算删除**之前**抛 `:2814-2819`；
- 单文件读失败 → 抛 `:2776-2781` ⇒ 整个事务回滚；
- 容量超限／非 UTF-8 → 只计 `skipped` 并撤销旧内容 `:2767-2798`（区分"有意排除"与"I/O 错误"）。

settle 的完整写集（事务内逐条，**C**）：

| 序 | 锚点 | 写 |
|---|---|---|
| 1 | `:2668-2670` | `upsertRoot(status:"present", displayName=路径, locatorType:"path")` —— locator 的持久权威在此 |
| 2 | `:2672-2684` | 读快照 `file_contents`（digest + object_id） |
| 3 | `:2689-2714` | 读快照 `external_files WHERE COALESCE(status,'present')<>'missing'` |
| 4 | `:2843-2871` | 删除支：`affectedClosure`（递归 CTE，`:5275-5300`）→ `invalidateRetrievalSettlementsInTransaction`（`:5344-5379`）→ `DELETE file_contents`（`:2849-2854`）→ `information_items state='STALE'`（`:2855-2861`）→ `external_files status='missing'`（仅 missing，`:2862-2870`） |
| 5 | `:2873-2942` | 新增／更新支：`ensureObjectWithStatus`（`:1280`）写内容寻址对象 —— `carryText:false` 时对象是 `{locator,sha256,size,modified?}` 元数据 JSON（`:2891-2900`），**不是文件字节**；`file_contents.content` 恒绑 `''`（`:2903-2920`）；`information_items` upsert 为 `AVAILABLE`（`:2921-2936`）；`appendIndexEntryInTransaction`（`:1321`，调用 `:2937`）；`appendDependencyInTransaction`（`:1333`，`:2939-2941`，reason=`content-settle`/`content-update`） |
| 6 | `:2944-2951` | `indexExternalFile`（`:5080`）逐个索引文件（含 skipped 者） |
| 7 | `:2952` | `markSettlementsInvalidInTransaction`（`:5318-5339`：`settlements.validity='invalid'` + 桥接行 `retrieval_settlements.status='invalidated'`，只翻未失效者 ⇒ 幂等且不重写早期时间戳） |
| 8 | `:2953` | `markRootScanned`（`:5059-5067`）status 复位 `present`、写 `last_scanned_at` |

`createIfNeeded:true` 只存在于 `:1885`（search）与 `:2370`（roots PUT），其余 9 个只读入口全 `false` —— 依 owner 上轮裁定 **只登记，不重新定性**。

写集入口穷举（**C**，`git grep` 全 ref 路径重测，不限定子目录）：`upsertRoot` 的调用点共 6 处 —— 产品外部入口 4 处：`HTTPServer.swift:2373`（roots PUT）、`HTTPServerMCP.swift:436`（`simigo_root_register`，同样 `upsertRoot(registered)` + `settleWorkRootContents(carryText:false)`，`:421-454`）、`EnvManager.swift:556`（`bootstrapFreshDatabase`，声明在 `:542`）与 `:852`（`registerWorkRoot`，声明在 `:840`）；DB 内部 2 处：`SimiGoESISDatabase.swift:2668`（settle 第一段）与 `:5084`（`indexExternalFile`，声明 `:5080-5104`）。`markRootScanned`/`markRootStatus` 的产品侧调用者仅 `:2953` 与 `:3046`。

`indexExternalFile` 那条内部调用值得单列（**C** + **C-NEG**）：它传 `displayName: nil, locatorType:"path", status: 入参（默认 "present"）`，而 `upsertRoot` 的 `ON CONFLICT` 用 `display_name=COALESCE(excluded.display_name, display_name)`（`:5044`）⇒ 对已有 work 根**不会抹掉**已留存的 locator（settle 注释 `:2666-2667` 即为此保证）；但对**首次由索引创建**的根（启动面 `SimiGoBootstrap.swift:92` 的 `discover-models`，category `"model"`），落库行 `display_name IS NULL` ⇒ 该根永无 locator。reconcile 默认只跑 category `"work"`，而 HTTP（`:2301-2303`）与 MCP（`HTTPServerMCP.swift:458`）都接受任意 `category` 入参 ⇒ 若以 `category:"model"` 调用，这些行全部计入 `unlocatableRoots`（`:3033-3036`，语义自陈为"登记于 locator 保留之前，非扫描失败"`:2987-2989`）。本轮只登记这一形状，不定性。

---

## 4. reconcile 全写集 —— 循环体本身不开事务，部分完成是常态

入口三条（**C**）：

| 入口 | 锚点 | 策略 | 参数缺省 |
|---|---|---|---|
| HTTP `POST /v1/simigo/is/reconcile` | 路由 `HTTPServer.swift:2645`，handler `:2292-2340` | `.protected(srsWrite)` `:1619-1622` | `category="work"`、`max_age_seconds`>0 才生效 `:2301-2306`；`carryText` 不可传 ⇒ 恒 index-only |
| MCP `simigo_is_reconcile` | `SimiGo/Protocol/HTTPServerMCP.swift:456-471` | 整支 `.protected(srsWrite)` `:1623-1627` | `minAgeSeconds` 未传 ⇒ **0（全量重扫）**；形参缺省见 `SimiGoESISDatabase.swift:3008` |
| 启动面 | `Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoBootstrap.swift:119-133`，`minAgeSeconds:600` | — | 另有 step `index-work` `:102-112` 对声明的 work roots 逐个 `settleWorkRootContents(carryText:false)` |

`reconcileRegisteredRoots`（`SimiGoESISDatabase.swift:3007-3072`）真实顺序：

1. `SELECT root_id, display_name, last_scanned_at FROM roots WHERE category=? ORDER BY root_id` `:3012-3024`（**无事务**，autocommit 读）；
2. 逐根：locator 为空 ⇒ `unlocatableRoots++` `:3033-3036`；近期已扫 ⇒ `freshRoots++` 跳过 `:3037-3042`；目录不存在 ⇒ `markRootStatus(status:"missing")` 单条 UPDATE（`:5071-5075`）+ `missingRoots++` `:3043-3049`（**不清内容**，注释 `:3045-3046` 与函数头 `:2999-3001` 一致）；否则 `settleWorkRootContents`（第 3 节的整段事务）`:3050-3059`；
3. `catch { failedRoots += 1 }` `:3060-3062`。

事务边界 ⇒ **每次 reconcile 是 N 个互相独立的写事务**；前 k 个根已重结算、第 k+1 个未做是设计常态（C）。全有或全无只存在于单根内部。

时间码往返核验（**C-NEG**）：`stamp() = String(format:"%.17g", timeIntervalSinceReferenceDate)` `:6575-6577`；`parseISO8601` 先 `Double(text)` 再退 ISO8601 `:6579-6581` ⇒ 对本码写出的 `last_scanned_at` 可解析，`minAgeSeconds` 不会因格式失配而退化为"永不 fresh"。另：HTTP 字段名 `max_age_seconds` 映射到形参 `minAgeSeconds`，语义方向一致，无反转。

`invalidated_settlements` 的来源：各根 `ContentSettleReport.invalidatedSettlements` 之和 `:3059`，其值 = 单事务内跨文件累积的 `invalidated: Set<String>` `:2839/2844/2875` 的基数 —— 同一结算被多个文件命中只计一次（去重面已核）。

三个登记级事实：

1. **失败原因被吞（C）**：`:3060-3062` 不记 `error`；HTTP 只见 `failed_roots` 计数（`:2319-2334` 的 12 字段响应体，无逐根明细）；bootstrap 只把该 step 判 `.failed`（`:132`）。⇒ 只能知道"有几个根没扫成"，不能知道为什么。诊断面缺口，不定性为缺陷。
2. **legacy 失效作用域为全库（C）**：`invalidateRetrievalSettlementsInTransaction` 末段 `UPDATE retrieval_settlements SET status='invalidated' WHERE status='valid' AND inputs_digest LIKE 'legacy-v1:%'` `:5375-5378` **不带 root／path 约束** ⇒ 任一来源文件变更会使所有 legacy-v1 有效检索结算失效。注释 `:5370-5374` 自陈这是 provenance 不可证时的保守选择（方向是"宁可多失效"，非 fail-open）。
3. **两条失效／对账原语在产品代码零生产者（C-NEG）**：`invalidateSourceFile` `:5307-5314` 与 `reconcileRoot(rootID:seenRelativePaths:)` `:5386+` 的全部调用点为测试（`Packages/SimiGoRuntime/Tests/SimiGoRuntimeContractTests/SimiGoESISDatabaseG2Tests.swift:78`、`:102`；`SimiGoISAdmissionTests.swift:160`；`SimiGoESISDatabaseTests.swift:935`、`:942`）与 `docs/upstream` 文字引用；产品侧失效唯一触发面是"扫描"。另：全仓产品代码对 `FSEvents`／`makeFileSystemObjectSource`／`kFSEventStream` **零命中**（仅 `docs/experiments/V17_RUNTIME_MATRIX/evidence/*` 样本文本出现该字样）⇒ 「来源文件变化后运行时自动失效」在当前 main 不成立，须经 `/reconcile`、MCP 或重启。与 `docs/upstream/P2_CONFIG_RECORD_20261105.md:69` 把 `invalidateSourceFile` 记为"应急后备"一致，但产品代码里没有调用它的入口。

MCP 面附加事实（C）：`simigo_is_reconcile` 输出缺 `unlocatable_roots`（HTTP 有 `:2326`）；每个 MCP 工具都新开句柄并跑迁移（`openESISDatabase` `:796-800`，`createIfNeeded:true`），抛错被吞成 `isError:true` `:130-134`（承步骤 2 读数，不重复定性）。

---

## 5. #391 三类清单增量（本轮，不改既有 V-4 F-A/F-B/F-C 与 V-7 的独立性）

### A 类 —— 确认实现缺陷（代码级）

- **A-9** Responses 空身份静默返回（`HTTPServerResponses.swift:1030-1033`）：定性按 owner 限定 —— 在空身份条件下，T1 与后续结算记录之间存在静默断裂。承前，不升级。
- **A-10** branch delete 会话表键不对称（`NativeMLX.swift:3256-3286` vs `:3359`，且不经 `resolveSessionMapKey:296-305`）：机制已证 —— 守卫放行、`clear()` 未执行、其余清理照常、响应 `ok:true` 且 `remaining_live` 自证残留。**可达性属 R**（分片后缀实际发生率未测）。
- **A-11** 分支陈旧性守卫只到传输层：`expected_generation` 解析并传递（`HTTPServer.swift:2844`/`:2855`）但无宿主强制；`branchGenerationMismatch` 零生产者 ⇒ 409 不可达。与 S3-A「never a silent ok」承诺的覆盖面差一段：该承诺在**类型化错误面**成立，在**守卫生效面**尚未接通。

### B 类 —— 架构缺口

- **B-8** 失效触发面缺失：无文件监听、`invalidateSourceFile`／`reconcileRoot` 产品零调用 ⇒ 运行时自动失效未实现（承待裁项 #28）。
- **B-9** 身份与责任：分支命名空间由客户端声明字段决定（`agent_id`／`x-simigo-agent`／`x-agent-id`，缺省 `default`），与 LOCALB 认证主体无绑定。
- **B-10** `legacy-v1` 结算失效作用域为全库而非单根（`SimiGoESISDatabase.swift:5375-5378`）。
- **B-11** 非 MLX 宿主的 `branches/list` 与"无分支"不可区分（`ok:true` + 空集），且 fork/delete 拒绝被降级为通用 400。
- **B-12** 分支派生血统（parent→child）没有持久载体：唯一记录处是进程内 128 条环形缓冲（`ExecutionLineage.swift:80-88`/`:48`），面向展示的只读投影为其唯一消费者（`NativeMLX.swift:3123-3145`）。⇒ 重启后"该分支由谁派生"在产品侧无任何可查询事实；ES／IS／SQLite 均无分支级 lineage 行（C-NEG）。是否要求跨重启保留分支 provenance 属架构裁决，本轮不定性；`BranchForkEvent` 注释自陈语义为 checkpoint 派生而非执行级父子（`:28-31`），不得据此声称执行血统已覆盖。

### R 类 —— 仍需运行时证据

- **R-5** `settleWorkRootContents` 在 BEGIN IMMEDIATE 内做全树 IO，与 T1–T4 争同一句柄 ⇒ 并发时长／`SQLITE_BUSY`。
- **R-6** 分片后缀键场景发生率（A-10 可达性）。
- **R-7** 大根扫描对首启（bootstrap step 5/6）与 HTTP 延迟的影响。

### 只登记、不重新定性（依既有裁定）

- **D**：同一 IS 写面上 `.open` 的 roots PUT（`HTTPServer.swift:1609-1610`）与 `.protected(srsWrite)` 的 `/reconcile`（`:1619-1622`）分类不同；`createIfNeeded:true`（`:1885`/`:2370`）与只读入口 `false` 的句柄差异；branches 的 `.branchControl`（`:1634-1644`，owner S2 裁定）。

---

## 6. 本轮未核验（保持未验证，不列入结论）

- `SimiGo/System/EnvManager.swift:542`（`bootstrapFreshDatabase(workRoot:)`，`upsertRoot` 在 `:556`）与 `:840`（`registerWorkRoot`，`upsertRoot` 在 `:852`、`NotificationCenter` 广播在 `:859`）两条注册入口与 HTTP／MCP 两入口的写集等价性：形状同构，**未逐字段闭合比对**（`registerWorkRoot` 会广播 `workRootsDidChange`，`SimiGo/System/EnvManager.swift:806`；其消费方本轮未查）。
- ~~`lineage.recordFork` 在 `ExecutionStateGraph` 侧的持久化面本轮未展开~~ → **本条已闭合**，见 §2「血统与投影的持久化面」：`ExecutionLineage.swift:80-88` 为进程内环形缓冲，`snapshot` 唯一产品消费者为 `NativeMLX.swift:3123-3145` → `Service.swift:549` → `SimiGo/App/ExecutionStateGraph.swift:1192/1220/1261`（展示）。等级 C-NEG，不再列为未验证。
- 内存池跨会话共享分支标签的实际命中/失效影响（仅证键语义，未取读数）。
- 未提交候选与 PR 分支相对 `origin/main` 的差异一律不作为事实引用。
