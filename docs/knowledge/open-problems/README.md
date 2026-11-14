# Open Problems

本页仅登记当前产品中有证据支持、尚未关闭的问题；关闭须有对应验收读数。证据原件保留在原位置，本页不复制内容。

**基线：2026-11-10（补登 2026-11-10 审核提出的采集侧四项与本地 GGUF 身份）。** 云端 provider 代理已于 2026-11-03 从产品源码移除。旧代理“外部转发真机 E2E 缺失”不再作为当前产品问题；其历史合同和证据继续保留供追溯。

第 8–14 条由 2026-11-10 云端审核提出，已在源码逐条核对确认。**第 8–14 条已全部处理**：第 8、9、10、11、12、13 条已修复，第 14 条已接线（回归用例见各自条目）；据此移出本表，证据原文见文末「已关闭（保留证据）」，编号不复用。

**2026-11-15 补登第 3 条**：断连路径的终止态（`ad63021` #94）与停机遗留的启动清扫（`close-stranded-turns`）均已落地，包测试 469/469；安装版强杀重启已实证（`pending` → `abandoned`，`closed=1`）；断连成对 trace 已于 2026-11-15 06:10 取得（真实客户端 Codex Desktop，行 8368 `detached`，`r=a5b38a` 全链可对号）；第 3 条据此移出本表，证据原文见文末「已关闭（保留证据）」，编号 3 不复用。

| # | 问题 | 状态 | 证据 / 边界 |
|---|---|---|---|
| 1 | 自动答案复用未显式绑定本轮 resolve 的 demand identity | **部分修复（2026-11-08）· 冻结交互已实证并修复** | 2026-11-05 源码静态审查的 demand-identity 缺口已由 `reusableAnswer` 的 `expectedDemandID` 严格门关闭：门要求本轮 resolve 的 demand 非空且与历史 `answeredDemand.demandID` 相等，resolve 失败即 fail-closed。2026-11-08 本机实证补上第二处真缺口：IS 冻结快照（`ISContextLedger.stabilize`）与当前候选 demand 分叉时，复用门读的是冻结 demand，跨会话新信息落地后旧答案仍被 `model_calls=0` 回放（Responses 线实测复现）；修复=分叉时整轮刷新冻结快照（渲染/结算/门三者同读一份新快照，`frozenRefresh=1` 可观测），复用门改读当前候选 resolve。同批补齐 demand 变化、resolve-failure、reuse-event provenance 回归（Chat/Responses/MCP-E2E 隔离 lane 8 用例）。残余待验：真机负载下的冻结刷新频率与前缀成本仍无实测读数。 |
| 2 | 已结算答案在后续同 scope 请求中的消费资格与安装版 replay 证据 | 未关闭（部分观察已有） | [IS 外部轮次合同](../../architecture/IS_EXTERNAL_TURN_CONTRACT_20261030.md) §10：该窗口未观测同 scope 后续消费。§11.1 的 `replay=1` 是检索上下文复用标记，不是答案结算消费；§11.3 的 `model_calls=0` 后台标题/建议复用是跨日、跨 scope 的历史观察，不能代替同 scope 受控验收。Qoder 的 24408-token `memPoolHit` 是物理前缀/KV 加速，也不是 IS 语义答案复用。尚缺“同 scope 已结算答案→后续请求消费”的受控安装版验收；不得把不同层次的 replay / reuse 合并为同一证据。 |
| 4 | 本地路径缺少 `request_id` / `source_provider` | 未关闭 / 待裁定 | 同合同 §10；字段当前仅由历史外部数据合同路径使用 |
| 5 | Agent 类别（后台 rollout、内部记账等）的 `thread_source` 取证与检索资格 | 未关闭 | 同合同 §9；类别值及资格规则尚未完整取证 |
| 6 | W4 校准样本污染 | 独立问题未关闭 | prefill 时间门控路线已撤销；撤销不是修复，样本污染仍需独立处理 |
| 7 | 断连→重试的前缀保留 / 冷 prefill 不匹配 | 未关闭，待安装版验收 | [取消与 prefill ADR](../../decisions/ADR_LOCAL_OFFLINE_PREFILL_AND_CANCEL_20261030.md)：build 31 detach / bounded orphan 实现已落地；真机前缀保留路径未成立 |

## 使用规则

- 只有在修复前后证据满足对应范围时才关闭问题，并链接验收读数。
- 冻结证据（`docs/audit/`、`docs/experiments/`、`docs/benchmarks/`、`docs/lessons/`、`research/`）不因索引精简而删除或改写。
- 不将已撤销路线列为当前产品待办；不把测试层通过扩大为安装版或第三方 Agent 通过。

## 已关闭（保留证据）

本表只登记尚未关闭的问题。下面保留已关闭条目的证据原文，不再随表维护；编号不复用。

### 第 3 条 · 客户端断连后本地轮仍停留在 `pending`，存储状态未表达请求已结束

**已修复（断连 2026-11-07 · 停机遗留 2026-11-15 安装版实证 · 断连成对 trace 2026-11-15 06:10）· 已关闭。**

原状（§10，2026-10-30）：取消的本地轮 id 244 停在 `pending`，行状态不反映「该请求已死」。修法一（`ad63021` #94）：chat/responses 四条处理器退出时按出路终止自己写的那条 `pending` 行——客户端断开 → `detached`、运行期取消 → `cancelled`、其它未完成 → `failed`，行仍不进 `committed`，检索口径不变（`chatIndexRows` 只读 `committed`）。修法二（本轮）：进程在轮次中途结束（退出/崩溃/挂起）时没有处理器能执行，行会永久 `pending`，且同文本重试会**复用**该行；launch bootstrap 新增第 3 步 `close-stranded-turns`，`closeStrandedPendingTurns(launchedAt:)` 把「创建时间早于本次启动」的本地 `pending` 行置 `abandoned`（不冒充 `failed`/`cancelled`，仍不可检索），只按时间界判定，因此碰不到本进程正在服务的轮。验收：`testStrandedPendingTurnsCloseAtLaunchAndLiveTurnsSurvive`（旧行→`abandoned`；启动后的行仍 `pending`；重复调用返回 0；`abandoned` 行不可检索；同文本重试新建行）；包测试 469/469。现库只读拷贝 dry-run：14 条历史 `pending`（11 条 2026-10-30、3 条 2026-11-09）全部转 `abandoned`，`committed` 7336 条不变。**边界**：2026-11-15 之前库里那 11 条 `detached` / 2 条 `cancelled` 仍只能证明「断连会落到终止态」，不能逐条对号到某一次断连（当时未开客户端头取证）；成对读数只有下面 2026-11-15 06:10 这一条。`abandoned` 已进安装版并实证（`e5378ca2`，2026-11-15）：生成中 `kill -9` → 行仍 `pending`，重启 1 s 内变 `abandoned`，bootstrap 报告 `close-stranded-turns closed=1`，其余 standing 计数不变；同文本重试新建行、不复用该行；清扫假设单写者（两进程共用库时，后启动者会放弃先启动者的在途行）；**断连成对验收（2026-11-15 06:10，真实客户端 Codex Desktop 0.169.0-alpha.11.1，`responses` 线）**：`[CLIENT] originator="Codex Desktop"`（06:09:59）→ `[PROTOCOL] peerClosed r=a5b38a`（06:10:16，客户端在预填中途被 `kill -9`）→ `[DETACH] stop=1 r=req-a5b38a7f reason=generation_contended`（06:10:19，重试进入准入，孤儿让位）→ `[LC] RELEASED r=a5b38a s=01a1dc reason=detached_by_client`（06:10:24）→ `[CHAT_TURN_TERMINAL] session=01a1dc state=detached committed=0` → `chat_messages` 行 8368 `turn_state='detached'`；`trace_row_pair.py` 报 `paired=YES`。边界：只有客户端头、没有「哪条连接是哪个客户端」之外的额外取证；`[CLIENT]` 行不含 `r=`，与请求的关系靠同秒相邻（`ADMIT grant` 之后 0.4 s）判定。实证所用 `e5378ca2` 是工作区 WIP 快照包，不是发布版，v2.2.7-3 不因此成为正式发布；§10 的 id 244 未回写（历史缺口保留原值，不追溯改写）。

### 第 8 条 · 采集目录遍历先入内存再计费，上限约束不到读取与分配

**已修复（2026-11-10）**。

原状：root/项目/subagents 三层列举都走 `contentsOfDirectory`，在任何 `chargeEntry()` 之前就把整层读成数组（含逐项 stat），预算只约束其后的迭代。修法：三处换成私有 `DirectoryEntries`（`opendir`/`readdir` 惰性逐条产出，点开头条目跳过以对齐 `.skipsHiddenFiles`），预算触顶时迭代器不再被拉动，列举内存从 O(目录大小) 变 O(1)；readdir 中途失败记入 errors 使扫描变 partial（`isComplete == errors.isEmpty` 保证不退役 cursor）。验收：`testDirectoryListingStopsAtTheEntryBudgetMidDirectory`（8 文件目录、上限 3：恰 2 个入列即停）。**边界**：O(1) 内存是 readdir 流式的结构性质，行为断言只证明"列举被预算约束"，内存界靠代码评审；未在真实大目录上量过扫描耗时变化；listing 未换成 fd-based openat（独立加固项）。 

### 第 9 条 · subagent 文件不逐项计入 visitor 预算，也不复查文件上限

**已修复（2026-11-10）**。

原状：subagents 分支的 `for agent in agents` 循环既无 `chargeEntry()` 也无 `files.count < maxScannedFiles`，subagent 文件完全绕过两道预算。修法：agents 循环逐条 `chargeEntry()` + 文件上限复查（与主文件层同一套双预算，非 jsonl 条目同样计数），触发即 `break projectLoop` 置 budgetError → partial 不退役 cursor。验收：`testSubagentFilesShareTheScanFileBudget`（2 主 + 2 subagent、上限 3：恰 3 个入列且含 subagent）、`testSubagentEntriesShareTheScanEntryBudget`（上限 3 恰好卡在 subagents 分支：恰 1 个文件存活）；包测试 201/201。**边界**：语义变化是有意的——subagents 层的非 jsonl 条目现在也计入 entry 预算（旧代码完全不计数）。 

### 第 10 条 · 扫描触顶返回 partial，但不留续点，下一轮仍从根开始

**已修复（2026-11-10）**。

原状：`lastVisit` 只轮转已发现文件，预算触顶后未列出的条目下轮仍从根重走，大目录尾部 transcript 可能长期不被采集。修法：children/agents 两层留**续点水位**（按目录路径记**下一条待处理**条目名，存于 tailer 持有的 scanner，跨轮存活）；下轮对水位之前的条目**免计费跳过**（readdir 仍逐条看，内存 O(1)），**命中水位的条目本身照常处理**——所以被文件预算拒绝的条目、以及 subagents 中途触顶时所在的那个 session 目录，都不会被跳过（水位记"最后已处理"时这两处都会静默丢文件并误报 complete，已实测）；水位丢失即报 `scan resume entry not found`，该层诚实 partial 且下轮重走；完整走完即清水位，complete 扫描 prune 陈旧键。**关键配套**：跳过条目计入 `skippedLivePaths` 并入 live 集，且**跳过目录之下的 cursor 按祖先匹配保住**——否则"跳过目录 + 完整"会把目录内已有 cursor 误当删除退役，下轮再读即重复采集。验收：`testPartialScanLeavesAResumePointThatAdvancesAcrossPolls`（8 文件、预算限 3 文件/轮：三轮 3+3+2 零重复覆盖全树、第 3 轮 honest complete、cursor=8）、`testResumeWatermarkSelfHealsWhenItsEntryVanishes`（水位名丢失 → partial + 下轮重走，全删文件保证序无关）、`testNewFileCreatedUnderAWatermarkIsReadNoLaterThanFirstCompletePlusOne`（水位期新建文件延迟上界）、`testFileBudgetNeverLeavesTheWatermarkOnTheRefusedEntry`（4 文件/限 2：拒绝条目必须再被提供；旧写法丢 1 个文件并误报 complete，实测 3≠4）、`testBudgetStoppedInsideSubagentsResumesThatDirectory`（1 主 + 4 subagent/限 3，session 层 2 条、subagents 层 4 条，故预算**恒在 subagents 内触顶**、与 readdir 序无关：旧写法只 surface 4/5 且目录内 cursor 被退役到 1/5，实测 4≠5、1≠5——此用例同时锁定续点与祖先保活）；包测试 206/206（0 skipped）。**边界**：root 层不做项目级跳过（有意）——跳过整个项目会与子层未走完组合出假完整，代价是项目数超过 `maxVisitedEntries` 时仍会停滞（默认 16,384 下不现实）；**时间上界不是 O(1)，已实测**——内存 O(1) 成立，水位前缀每轮 readdir 重走（免计费但计时间）：10 万文件、4096/轮的追赶基准（一次性临时用例，读数记下后已删——CI 的 Transcript lane 要求 `skipped==0`，门控跳过的基准会让 gate 失败）测得 25 轮共 32.3s，单 poll 1117ms→1518ms 随已处理前缀单调增长（末段 +36% ≈ 9.6 万条前缀 readdir，约 4µs/条），稳态无水位整走 554ms/轮（2026-11-10，arm64/APFS tmpdir 实测读数）；**水位前的新文件延后**——持续 partial 期间，readdir 序落在水位之前的新文件每轮被跳过，直到首次 complete（清水位）后的下一轮才被读，无 cursor 副作用，延迟上界由 `testNewFileCreatedUnderAWatermarkIsReadNoLaterThanFirstCompletePlusOne` 锁定（最迟首次 complete 后一轮内被读，序无关）；续点只存内存，重启丢失退化为从头走（正确性不受影响）；`scan()` 改 `mutating` 是 source-breaking 变更（仓内唯一调用点已同步）；readdir 序任意，断言已按序无关写；祖先保活按路径逐级上溯（深度 ≤ 4），未在超深目录树或超大 cursor 集上量过耗时。 

### 第 11 条 · 超长行扫描按换行位置计费，实际磁盘读取大于预算

**已修复（2026-11-10）**。

原状：`findNewline` 一次 `pread` 最多 1 MiB，命中换行时只按 `scanned + found` 计费，`skipOversizedLine` 据此扣减 `budget`，剩余预算多于真实剩余磁盘量。修法：`findNewline` 额外返回 `charged`（实际读到的 `chunk.count` 累计），预算与 `readBytes` 一律按 `charged` 记，换行后的逻辑推进仍用 `scanned`。验收：`testOversizedLineChargesTheChunkItActuallyRead`（换行落在 1 MiB 块首，修复前 `readBytes` 报 1，修复后报整块）；包测试 197/197。**边界**：这是计费口径的修正，未在真实大目录上量过 poll 频率变化。 

### 第 12 条 · 文件身份重置未清理 `oversizedScan`，同路径换文件可能沿用旧偏移

**已修复（2026-11-10）**。

原状：`oversizedScan` 按路径保存，`baseline()` 只清 accumulator；`baseline()` 覆盖的 identity / truncation / fingerprint 三种重置、策略切换、resume 点损坏、读取后身份不符，这些路径都不清该表。修法：这四处一并清理。验收：`testReplacingAFileDropsThePendingOversizedScan`（旧文件留有未完成的超长行扫描 → 同路径换文件并追加 → 新内容必须被读出；修复前该文件永远读不出）。**边界**：只覆盖 identity reset 一条路径的行为，其余四处清理点没有各自的对应用例。 

### 第 13 条 · 单文件事件预算只在文件之间检查

**已修复（2026-11-10）**。

原状：`maxEventsPerPoll` 仅在循环头判定，单文件 `readAvailable()` 一次窗口可产出全部事件，`CollectionRunner` 的 staged 缓冲可被单文件洪峰撑破。修法：解析循环逐行检查 `deliveredEvents + 本文件已暂存事件数 >= maxEventsPerPoll`，触顶即停，游标停在最后解析完的行，余量下轮重读；`readBytes` 改按游标实际消费字节记。验收：`testEventBudgetStopsMidFileBeforeStagingASingleFileFlood`（6 回合单文件、上限 3：逐轮 ≤3、budgetExhausted 置位、跨轮事件总量与不设限读数一致）；包测试 198/198。**边界**：逐行检查跨线上限最多溢出一行的事件量；预算停在窗口中段时未解析字节下轮重读并重复计入字节预算（与 sink 失败重放同型）；未在真实大文件上量过轮次增加的影响。 

### 第 14 条 · 本地 GGUF producer 身份未按内容解析

**已接线（2026-11-10）**。

原状：`ProducerIdentity` 对非 HF blob 布局的 GGUF 只记 name+size，且 `identity.model` 对任意本地文件都是同一串全 null 绑定指纹，同名同尺寸不同字节得到同一 producer。修法：`identity(fromPath:)` / `canonicalModelIdentity(fromPath:)` 对单文件路径一律走 `GGUFModelIdentity`（按字节流式 SHA-256，HF blob 布局校验后走快路径，按 path+size+inode+mtime 缓存）；不可读文件用 `unreadable` 标记，绝不退回 name+size；`ManagedGGUFRuntime` 启动时解析一次并共享；headless G1/G3 的副本实现已删除改为委托，只剩一处公式。验收：`testProducerIdentityFollowsTheBytesOfALocalCheckpoint`、`testGGUFTokenizerIdentityIsTheContentDigestNotTheFilename`。**边界**：现行库里没有任何一条 producer 绑定使用过全 null 的本地绑定指纹（0 条），所以本次改身份没有让既有结算失效——这只说明该洞是潜在的、未被使用过，不代表旧值曾被验证正确；GGUF 的 settlement consumption 仍是 unsupported（`ManagedGGUFRuntime` 的 `settlementConsumption` 为 nil）；managed continuation 已接通，D6 四臂在真机上 4/4 通过（`346beda`，带模型调用、`cached_tokens=0`，单模型单构建）。 
