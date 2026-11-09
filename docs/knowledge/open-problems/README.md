# Open Problems

本页仅登记当前产品中有证据支持、尚未关闭的问题；关闭须有对应验收读数。证据原件保留在原位置，本页不复制内容。

**基线：2026-11-10（补登 2026-11-10 审核提出的采集侧四项与本地 GGUF 身份）。** 云端 provider 代理已于 2026-11-03 从产品源码移除。旧代理“外部转发真机 E2E 缺失”不再作为当前产品问题；其历史合同和证据继续保留供追溯。

第 8–14 条由 2026-11-10 云端审核提出，已在源码逐条核对确认。其中**第 8、9 条已按统一遍历方案修复**、**第 11、12、13 条已修复**、**第 14 条已接线**（回归用例见各自条目），其余一条（第 10 条）仍只登记、未修复，不代表已排期。

| # | 问题 | 状态 | 证据 / 边界 |
|---|---|---|---|
| 1 | 自动答案复用未显式绑定本轮 resolve 的 demand identity | **部分修复（2026-11-08）· 冻结交互已实证并修复** | 2026-11-05 源码静态审查的 demand-identity 缺口已由 `reusableAnswer` 的 `expectedDemandID` 严格门关闭：门要求本轮 resolve 的 demand 非空且与历史 `answeredDemand.demandID` 相等，resolve 失败即 fail-closed。2026-11-08 本机实证补上第二处真缺口：IS 冻结快照（`ISContextLedger.stabilize`）与当前候选 demand 分叉时，复用门读的是冻结 demand，跨会话新信息落地后旧答案仍被 `model_calls=0` 回放（Responses 线实测复现）；修复=分叉时整轮刷新冻结快照（渲染/结算/门三者同读一份新快照，`frozenRefresh=1` 可观测），复用门改读当前候选 resolve。同批补齐 demand 变化、resolve-failure、reuse-event provenance 回归（Chat/Responses/MCP-E2E 隔离 lane 8 用例）。残余待验：真机负载下的冻结刷新频率与前缀成本仍无实测读数。 |
| 2 | 已结算答案在后续同 scope 请求中的消费资格与安装版 replay 证据 | 未关闭（部分观察已有） | [IS 外部轮次合同](../../architecture/IS_EXTERNAL_TURN_CONTRACT_20261030.md) §10：该窗口未观测同 scope 后续消费。§11.1 的 `replay=1` 是检索上下文复用标记，不是答案结算消费；§11.3 的 `model_calls=0` 后台标题/建议复用是跨日、跨 scope 的历史观察，不能代替同 scope 受控验收。Qoder 的 24408-token `memPoolHit` 是物理前缀/KV 加速，也不是 IS 语义答案复用。尚缺“同 scope 已结算答案→后续请求消费”的受控安装版验收；不得把不同层次的 replay / reuse 合并为同一证据。 |
| 3 | 客户端断连后本地轮仍停留在 `pending`，存储状态未表达请求已结束 | 未关闭 | 同合同 §10；fail-closed 防止错误结算，但状态未终止 |
| 4 | 本地路径缺少 `request_id` / `source_provider` | 未关闭 / 待裁定 | 同合同 §10；字段当前仅由历史外部数据合同路径使用 |
| 5 | Agent 类别（后台 rollout、内部记账等）的 `thread_source` 取证与检索资格 | 未关闭 | 同合同 §9；类别值及资格规则尚未完整取证 |
| 6 | W4 校准样本污染 | 独立问题未关闭 | prefill 时间门控路线已撤销；撤销不是修复，样本污染仍需独立处理 |
| 7 | 断连→重试的前缀保留 / 冷 prefill 不匹配 | 未关闭，待安装版验收 | [取消与 prefill ADR](../../decisions/ADR_LOCAL_OFFLINE_PREFILL_AND_CANCEL_20261030.md)：build 31 detach / bounded orphan 实现已落地；真机前缀保留路径未成立 |
| 8 | 采集目录遍历先入内存再计费，上限约束不到读取与分配 | **已修复（2026-11-10）** | 原状：root/项目/subagents 三层列举都走 `contentsOfDirectory`，在任何 `chargeEntry()` 之前就把整层读成数组（含逐项 stat），预算只约束其后的迭代。修法：三处换成私有 `DirectoryEntries`（`opendir`/`readdir` 惰性逐条产出，点开头条目跳过以对齐 `.skipsHiddenFiles`），预算触顶时迭代器不再被拉动，列举内存从 O(目录大小) 变 O(1)；readdir 中途失败记入 errors 使扫描变 partial（`isComplete == errors.isEmpty` 保证不退役 cursor）。验收：`testDirectoryListingStopsAtTheEntryBudgetMidDirectory`（8 文件目录、上限 3：恰 2 个入列即停）。**边界**：O(1) 内存是 readdir 流式的结构性质，行为断言只证明"列举被预算约束"，内存界靠代码评审；未在真实大目录上量过扫描耗时变化；listing 未换成 fd-based openat（独立加固项）。 |
| 9 | subagent 文件不逐项计入 visitor 预算，也不复查文件上限 | **已修复（2026-11-10）** | 原状：subagents 分支的 `for agent in agents` 循环既无 `chargeEntry()` 也无 `files.count < maxScannedFiles`，subagent 文件完全绕过两道预算。修法：agents 循环逐条 `chargeEntry()` + 文件上限复查（与主文件层同一套双预算，非 jsonl 条目同样计数），触发即 `break projectLoop` 置 budgetError → partial 不退役 cursor。验收：`testSubagentFilesShareTheScanFileBudget`（2 主 + 2 subagent、上限 3：恰 3 个入列且含 subagent）、`testSubagentEntriesShareTheScanEntryBudget`（上限 3 恰好卡在 subagents 分支：恰 1 个文件存活）；包测试 201/201。**边界**：语义变化是有意的——subagents 层的非 jsonl 条目现在也计入 entry 预算（旧代码完全不计数）。 |
| 10 | 扫描触顶返回 partial，但不留续点，下一轮仍从根开始 | 未关闭 | `lastVisit` 只轮转**已发现**文件；未发现的部分不推进。大目录下尾部 transcript 可能长期不被采集——公平轮转解决的是"已入列文件的先后"，不是"未入列文件何时轮到"。 |
| 11 | 超长行扫描按换行位置计费，实际磁盘读取大于预算 | **已修复（2026-11-10）** | 原状：`findNewline` 一次 `pread` 最多 1 MiB，命中换行时只按 `scanned + found` 计费，`skipOversizedLine` 据此扣减 `budget`，剩余预算多于真实剩余磁盘量。修法：`findNewline` 额外返回 `charged`（实际读到的 `chunk.count` 累计），预算与 `readBytes` 一律按 `charged` 记，换行后的逻辑推进仍用 `scanned`。验收：`testOversizedLineChargesTheChunkItActuallyRead`（换行落在 1 MiB 块首，修复前 `readBytes` 报 1，修复后报整块）；包测试 197/197。**边界**：这是计费口径的修正，未在真实大目录上量过 poll 频率变化。 |
| 12 | 文件身份重置未清理 `oversizedScan`，同路径换文件可能沿用旧偏移 | **已修复（2026-11-10）** | 原状：`oversizedScan` 按路径保存，`baseline()` 只清 accumulator；`baseline()` 覆盖的 identity / truncation / fingerprint 三种重置、策略切换、resume 点损坏、读取后身份不符，这些路径都不清该表。修法：这四处一并清理。验收：`testReplacingAFileDropsThePendingOversizedScan`（旧文件留有未完成的超长行扫描 → 同路径换文件并追加 → 新内容必须被读出；修复前该文件永远读不出）。**边界**：只覆盖 identity reset 一条路径的行为，其余四处清理点没有各自的对应用例。 |
| 13 | 单文件事件预算只在文件之间检查 | **已修复（2026-11-10）** | 原状：`maxEventsPerPoll` 仅在循环头判定，单文件 `readAvailable()` 一次窗口可产出全部事件，`CollectionRunner` 的 staged 缓冲可被单文件洪峰撑破。修法：解析循环逐行检查 `deliveredEvents + 本文件已暂存事件数 >= maxEventsPerPoll`，触顶即停，游标停在最后解析完的行，余量下轮重读；`readBytes` 改按游标实际消费字节记。验收：`testEventBudgetStopsMidFileBeforeStagingASingleFileFlood`（6 回合单文件、上限 3：逐轮 ≤3、budgetExhausted 置位、跨轮事件总量与不设限读数一致）；包测试 198/198。**边界**：逐行检查跨线上限最多溢出一行的事件量；预算停在窗口中段时未解析字节下轮重读并重复计入字节预算（与 sink 失败重放同型）；未在真实大文件上量过轮次增加的影响。 |
| 14 | 本地 GGUF producer 身份未按内容解析 | **已接线（2026-11-10）** | 原状：`ProducerIdentity` 对非 HF blob 布局的 GGUF 只记 name+size，且 `identity.model` 对任意本地文件都是同一串全 null 绑定指纹，同名同尺寸不同字节得到同一 producer。修法：`identity(fromPath:)` / `canonicalModelIdentity(fromPath:)` 对单文件路径一律走 `GGUFModelIdentity`（按字节流式 SHA-256，HF blob 布局校验后走快路径，按 path+size+inode+mtime 缓存）；不可读文件用 `unreadable` 标记，绝不退回 name+size；`ManagedGGUFRuntime` 启动时解析一次并共享；headless G1/G3 的副本实现已删除改为委托，只剩一处公式。验收：`testProducerIdentityFollowsTheBytesOfALocalCheckpoint`、`testGGUFTokenizerIdentityIsTheContentDigestNotTheFilename`。**边界**：现行库里没有任何一条 producer 绑定使用过全 null 的本地绑定指纹（0 条），所以本次改身份没有让既有结算失效——这只说明该洞是潜在的、未被使用过，不代表旧值曾被验证正确；GGUF 的 settlement consumption / managed continuation 仍是 unsupported。 |

## 使用规则

- 只有在修复前后证据满足对应范围时才关闭问题，并链接验收读数。
- 冻结证据（`docs/audit/`、`docs/experiments/`、`docs/benchmarks/`、`docs/lessons/`、`research/`）不因索引精简而删除或改写。
- 不将已撤销路线列为当前产品待办；不把测试层通过扩大为安装版或第三方 Agent 通过。
