# #90：匿名入口的稳定续跑（引擎分片采纳）—— 设计裁定材料（2026-10-28）

状态：**设计，请求裁定**。不改产品码，不动 ES/IS 身份规则文本，不占真机窗口。依据全部来自本机 a16/a17/a18 三条同构建读数与现有代码，owner 已声明未在当前环境独立复验。

## 1. 事实：身份规则的效果与它的前提相反

`HTTPServer.resolveExecutionIdentity`（`SimiGo/Protocol/HTTPServer.swift:2683-2774`）第 5 条：无显式 session ⇒ `makeRequestScopedSessionId("openai")` ⇒ `<ns>-request:<UUID>`（:2650-2655，注释明写「不参与跨请求 KV reuse」）。规则 3 上方的注释（:2745-2756）给出的理由是：

> NativeMLX 后续仍可以：token prefix match / tool fingerprint match / physical KV reuse。因此不需要人为合并 Session。

**这条前提被同构建的两条读数直接否掉**：引擎能不能复用，取决于 `state.sessions[mapKey]` 里有没有那个会话，而

- `AgentExecutionKey.storageKey = "agentId/sessionId/logicalBranchId"`（`SimiGo/Inference/StreamTokenFilter.swift:170`）
- `sessionMapKey = storageKey + "#" + fingerprint(firstMessage)`（`NativeMLX.swift:255-264`）

⇒ sessionId 每请求唯一 ⇒ mapKey 每请求唯一 ⇒ **上方那三种匹配在结构上没有对象可匹配**。

| 读数 | 身份来源 | 引擎键 | 结果 |
| --- | --- | --- | --- |
| a16 `trace-window.log:18` | 显式 session | 两轮同为 `004305/main` | `reuse=true cacheHitTokens=4449 cacheEff=0.74 mode=extend promptTime=1.8s` |
| a18 `trace-window.log`（§3.31） | 无 session（默认配置） | T1 `1c00b3/main#b0363629`、T3 `305424/main#b0363629` | 三轮全 `mode=cold cacheHitTokens=0 cacheEff=0.00` |

后缀 `#b0363629` 在 a18 两轮间相同（首消息=同一 system prompt），变的只有 storageKey 里的 UUID 尾巴 ⇒ 复用失败的唯一原因就是那个 UUID。同请求内部还有一层不对称可以佐证这不是 IS 的问题：IS 侧 scope 是内容派生且跨轮稳定的（T1/T2 同为 `info-e6d3c032…`，因此拿到 `model_calls=0`），引擎侧没有。

附带事实：请求级会话在 v2.1.1 起被有意跳过 branch-checkpoint 落盘（`StreamTokenFilter.swift:172-181` + `NativeMLX.swift:1685-1688`，理由「durable receipt 永无复访者」，实测这类死重曾占 64G 预算的 85%）。**这句「永无复访者」是当前规则的真实代价的自供状**：不是不想复用，是身份铸造让它必然没有复访者。

## 2. 隔离要求（owner 既有裁定，作为硬约束保留）

「不同 agent 或不同会话请求要隔离；同一 agent 可能开着不同会话窗口，不同作用域会话代表不同身份。」

由此排除两条最省事的写法：

- **按内容铸造会话身份**（把 system＋首个 user 哈希成 session id，像 `informationScope` 那样）：两个窗口只要开场相同就合并成同一会话，A 窗的后续轮会写进 B 窗的历史——这正是被禁止的那类合并。**本文不提议它，也不建议把它用于引擎键。**
- **按连接（TCP/keep-alive）铸造默认身份**：跨连接即失效（客户端每请求新建连接就退回现状），且同连接上开两个逻辑会话又会合并。收益不稳、隔离不保，**不推荐**。

ES/IS 的会话身份规则**保持原样**（规则 1/2/3 一字不动，显式 session 仍优先）。

## 3. 提议：引擎分片「转录精确采纳」（adoption），只作用于 KV 层

一句话：**KV 分片的归属由「客户端自己回传的转录能否精确续上某个已存在分片的账本」决定，不由会话身份决定。**

复用现成判据，不新造机制：`NativeMLX.generateUsingChatSession` 已经在做

```swift
if let existing, incoming.count > existing.history.count,
   existing.kvFingerprint == kvFingerprint,
   Self.isPrefix(existing.history, of: incoming)   // NativeMLX.swift:1096-1099
```

今天的差别只在于 `existing` 必须来自同一个 mapKey。提议改为：`state.sessions[mapKey]` 精确命中优先；**仅当该查询 miss 且本次是请求级会话**（`AgentExecutionKey.isRequestScopedSession`）时，在 sessions 表内找满足以下全部条件的分片并采纳它：

1. `incoming.count > cand.history.count`（严格追加）
2. `isPrefix(cand.history, of: incoming)`（逐条 role＋content 相等）
3. 同 `kvFingerprint`、同 `thinkingDisabled`、同模型身份
4. 该分片当前不在生成中
5. 命中多个时取 `lastActivity` 最近的一个

### 为什么这不违反第 2 节的隔离要求

采纳的**准入证据是客户端自己回传的转录**：只有当 B 窗口的请求里已经逐字包含了某分片已提交的历史（含此前的 assistant 原文），它才会被并入。于是

- B 拿到 A 的答案作为前缀，只在「B 的客户端本来就显示着这份答案」时发生——**合并永远不会与任何客户端的既有视图矛盾**；
- 两窗口只要有任意一轮分叉，条件 2 立刻失败，各走各的分片；
- 不同 agent（条件里 agentId 本就在 storageKey 内）与不同显式会话不受影响：显式会话走原有精确命中路径，不进入采纳分支。

这与 vLLM 自动前缀缓存 / llama.cpp `--cache-reuse` 的做法同族（共享的是**已算状态**，不是会话语义），但不需要落盘、不需要新哈希键。

### 关键实现事实（降低风险的那条）

`generationGateKey(for:)` 已被常量化，所有生成跨会话**单飞**（`NativeMLX.swift:923-931`，P0-3 规避 qwen3_5_moe 动态编译并发首编互堵）。⇒ 查表与提交全程在互斥区内，采纳不需要新的锁协议，也不存在两个请求同时改写同一分片账本的窗口。

### 必须一起处理的三件事

1. **重键与所有权**：采纳后写回哪个 mapKey。建议保留被采纳分片的原键（不重命名），只在请求级会话与新键之间记一条「本请求使用过该分片」的 trace，`executionId`/Lineage 仍按请求级身份登记（ES 侧一行不改）。若不这样做，`lineage.attachCheckpoint`（:1700）与生命周期终态会失去 1:1 假设。
2. **取消语义联动（#93）**：`poisonedSessionEvict` 在「本轮新建、零事件即取消」时逐出分片（:1609-1623，源于 2026-09-17 毒 session 事故，连续 10 次零输出挂死不可自愈，**不得回退**）。采纳来的分片属「非本轮新建」，其 `reusedSession=true` 分支今天不逐出——需明确采纳分片中途取消是否同毒；未观测过，属新边界，须在实现里显式回答（建议：采纳分片一旦本轮零输出即同样逐出，宁可重付不冒挂死）。
3. **内存驻留与淘汰**：分片从此会有复访者 ⇒ `sessions` 表由「每请求一条、随 suspend 清空」变成真实驻留集合，需要按字节的 LRU 淘汰（**内存内**，不涉及磁盘，与 W2′ 的池淘汰是两回事）。当前只有 `enforceDefaultBranchCheckpointRetention`（磁盘侧）和 `suspendIfIdle`（超时全清），没有内存字节上限。这是本提议唯一的新机制，也是唯一需要真机读数验收的部分。

## 4. 收益边界（不夸大）

| 场景 | 本提议 | 备注 |
| --- | --- | --- |
| 同一会话的追加式多轮（客户端逐字回传转录） | **修好**：turn2..N 走 `mode=extend`，a16 实测 cacheEff=0.74 | 这是你 229s 那类「越聊越慢」的主因 |
| 同一会话的**首轮** | 不修：无账本可采纳 | 属 W4 预热（按 owner 裁定，W4 不得被记成快照恢复证据） |
| 新会话但复用别人的 system prompt 前缀 | 不修：前缀关系不成立（条件 2 要求严格追加） | 这正是被 DEFER 的 W2′ 唯一的用武之地 |
| 跨重启 / 被取消轮逐出后的续跑 | 不修：内存分片随进程死 | 核心不变量要求本就不允许它依赖持久化 KV；跨重启需求成立时再启 W2′ |

⇒ 若你期望「首句也变快」，#90′ 给不了，需要 W4；若期望「新开会话不必重付同一份长 system prompt」，需要 W2′（已 DEFER，门槛已在 #92 预先固定）。这条区分我不想含糊过去。

## 5. 需要你的裁定

1. 是否按第 3 节实施（改动集中在 `NativeMLX.generateUsingChatSession` 查表分支 ＋ 一个内存字节上限；**不触碰** `HTTPServer` 身份规则、不触碰 ES/IS 行与结算）。
2. 第 3 节「三件事」里两个我倾向保守的口子是否照我写的办：取消时采纳分片一并逐出；Lineage 仍按请求级身份登记。
3. 验收口径：先在测试层用两个不同请求级 sessionId、逐字追加的转录断言 `mode=extend`（stub 模型即可，不占真机窗口），再要一次真机读数取 `cacheEff` 与内存驻留曲线——是否同意这个两步顺序。

## 6. 实施与真实模型闭环（2026-10-28，owner GO 后）

### 6.1 构建身份（读数只绑定本行）

| 项 | 值 |
| --- | --- |
| Git HEAD | `b08525116b878dbfbee737005b0006130206cbd3`（35 项未提交，未提交、未打标签、远端 `main` 未动） |
| 承载改动代码的二进制 | `build/u3-check/Build/Products/Debug/SimiGo.app/Contents/MacOS/SimiGo.debug.dylib`，SHA-256 `495d54103fef1cdab851010c9ad8d1307bc46570be579ad69f44312f2fc52c5f`（单元电池与该 E2E 同为此哈希） |
| 测试包 | `SimiGoTests.xctest` SHA-256 `f0e7362bfe0af4e595c550ed71bea605ffe096a17ba3e0188d1f5deadbd737d5` |
| 隔离根 | `SIMIGO_HOME=/tmp/ninety0-isolated3/home`（每轮清空）、独立 cache/state-graph、端口 18241 |
| 模型 | mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit（日常路径模型） |

### 6.2 结果

- 单元电池（SessionAdoptionTests 等 10 套件，同 dylib 哈希）：74 执行 / 5 跳过 / 0 失败；SessionAdoptionTests 30/30。
- `SessionAdoptionE2ETests` 真实模型闭环：2/2 通过（主门 69.95 s，隔离根全新）。

### 6.3 本轮修正的两个时序问题（owner 2026-10-28 裁定）

1. **D 轮取消点**：原用固定 1 s 睡眠，extend 轮自然完成仅 ~0.9 s，取消落空（04:11 实测 `cancelCommitSkip` 缺失、账本已推进到 9）。改为**首字节到达即取消**（`ByteCounter` 轮询 20 ms，30 s 上限），D 轮用户话语改为要求长输出，保证首字节后仍有大量 token 未生成。取消窗口由流水线自身证明：`rawEv=1`。
2. **E 轮“必须冷”**：不再依赖“D 已取消”反推。`sessionAdoptMiss candidates=3 eligible=0` 逐条给出拒绝理由（`notShorter / notPrefix / fpMismatch`），并以 `reuse=false`、`mode=cold`、`cacheHitTokens=0`、`promptTokens=10136`（冷轮 9744 的 ~1.04×）证明整份冷 prefill。

### 6.4 本轮新发现的两个测试层陷阱（产品语义未改）

1. **已结算答案复用（默认开启，`isAnswerReuseEnabled`）按 (scope, 尾部用户话语) 命中**：负例 2 原尾部话语 `"Say DONE."` 与 B 轮相同 ⇒ 被 `[IS_REUSE] … model_calls=0` 零模型调用应答、不进引擎（04:11 实测无完成行）。修法是让每轮话语唯一（改为 `"Say CONFIG."`），**不是**关闭复用；正式产品语义保持不变。
2. **链接表探针必须区分“读失败”与“零行”**：异步结算写入 + WAL 检查点会短暂持锁，原探针把 `SQLITE_BUSY` 吞成空数组，使否定判据空转（04:17 实测：表里实有 3 行稳定身份，探针返回空）。现设 `busy_timeout=3s`、`nil` 表示读失败、非 nil 空数组才表示零行。

### 6.5 读数（同一次运行）

采纳/转移（引擎行原文）：

```
sessionAdopt key=6baf89/main from=e/main own=transfer history=3 incoming=4 delta=1
… session=6baf89/main messages=4 history=5 reuse=true cacheHitTokens=9746 cacheEff=0.99 mode=extend promptTokens=97 adopt=1
sessionAdopt key=5d7218/main from=9/main own=transfer history=5 incoming=6 delta=1
… session=5d7218/main messages=6 history=7 reuse=true cacheHitTokens=9846 cacheEff=0.99 mode=extend promptTokens=136 adopt=1
```

拒绝理由（每轮候选集都被检过）：

```
sessionAdoptMiss key=056297/main candidates=1 eligible=0 reasons=5d7218/main:notShorter      # 陈旧 A
sessionAdoptMiss key=5472e0/main candidates=2 eligible=0 reasons=5d7218/main:notPrefix,056297/main:notPrefix # 中段改写
sessionAdoptMiss key=364560/main candidates=3 eligible=0 reasons=5472e0/main:fpMismatch,056297/main:fpMismatch,5d7218/main:fpMismatch # kvCache 不同
sessionAdoptMiss key=7746ea/main candidates=3 eligible=0 reasons=5472e0/main:notShorter,056297/main:notPrefix,364560/main:fpMismatch # 逐出后 E
```

取消（两时点由追踪行分开证明）：

```
sessionAdopt key=4ad786/main from=8/main own=transfer history=7 incoming=8 delta=1
cancelCommitSkip session=4ad786/main history=7 rawEv=1 rawB=1 emitB=1
adoptedCancelEvict session=4ad786/main history=7 aliases=1 keys=3d4e5b
```

`history=7` 在取消时保持不变 ⇒ 提交（incoming+assistant）确未发生；`aliases=1` ⇒ 所有权转移后只有一个键。

驻留曲线（**账本口径** = 几何估算字节；**物理足迹** = 本进程 `phys_footprint`，两者分开报告）：

| 阶段 | ledgerBytes | warmTokens | sessions | footprint |
| --- | --- | --- | --- | --- |
| A(cold) | 959,545,344 | 9,761 | 2 | 21.50 GB |
| B(adopt) | 969,375,744 | 9,861 | 2 | 22.70 GB |
| C(adopt) | 983,040,000 | 10,000 | 2 | 22.70 GB |
| stale-A(cold) | 1,958,707,200 | 19,925 | 3 | 23.68 GB |
| neg1(cold) | 2,941,550,592 | 29,923 | 4 | 23.82 GB |
| neg2(cold) | 3,948,773,376 | 40,169 | 5 | 23.82 GB |
| E(cold) | 3,964,403,712 | 40,328 | 5 | 23.82 GB |

- 上限 `ceilingBytes=9,830,400,000`（= warmTokenBudget 100,000 × 98,304 B/token），全程 `plannedEvictions=0`：本轮曲线没有触碰上限，**淘汰路径未在真实模型上被触发**（其决策只在纯函数层被测）；字节上限是闸门，不是目标值。
- 物理足迹全程高于账本（模型常驻 16.5 GB + MLX 缓冲 + 分片 KV），**不得**把账本字节读成“RSS 被同等字节数硬限”。进程墙钟读数：`afterLoad footprint=16521MB`，`beforeUnload footprint=22721MB`。
- 链接表：3 行稳定身份（`sa-warmup`、两个 `info-*`），`%-request:%` 命中 0 行 ⇒ 采纳未把请求级身份写进链接表。
