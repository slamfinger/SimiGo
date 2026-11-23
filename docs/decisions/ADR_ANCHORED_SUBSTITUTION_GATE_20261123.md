# ADR: 身份锚定替换门 + 活跃会话驱逐保护（P0/P1）

- 日期：2026-11-23
- 状态：已采纳（owner 2026-11-23 12:50 两条设计裁定），随 PR #337 实施
- 关联：ADR_IS_RENDERING_KV_DECOUPLING_20261121、ADR_TOKEN_PREFIX_REUSE_20261122、ADR_IS_RENDERING_SNAPSHOT_PERSISTENCE_20261122

## 背景与证据

真实客户端复核（zcode 外部客户端 + 本机 Ornith-1.5-35B-A3B-MLX-4bit，人工喂题
21 轮，会话 002e68ef / 引擎键 3f9be7，证据
`ES-IS-research/runs/client_recheck_20261123/`）暴露两个独立缺陷：

1. **替换门 21 轮零放行。** 轮账 21 连续、摘要 21/21 全落库，但
   `substituted=1` 一次没有出现。根因：门按**位置**数历史里的真用户消息
   （`envelopeStripped` 只认 system-reminder / user_info /
   environment_context 三标签），客户端注入的噪声用户消息虚增计数，
   `pastGenuine` 恒大于 ledger.highest，门静默返回 nil，无日志。
2. **第 19 轮起的冷填崩塌是驱逐自残。** trace 实证：11:51:19 digest 回环
   请求（r=a4ff2f，1725 tok）的 admission 驱逐主会话分片 sp-0076bff6
   （102640 tok）；12:01:03 另一个 digest 请求（r=219566）再次驱逐刚重建
   的主分片（105766 tok）。主分片单独超 warmTokenBudget（100000），且
   digest 请求恰好落在用户两轮之间（主会话不在途）→ 每次 digest
   admission 必驱逐主分片 → t19–21 全 cold（105–113k tok，ttft
   517870 / 519669 / 553474 ms）。轮末治理又反向驱逐 digest 分片
   （keys=bWFpbg），形成互相驱逐循环。内存压力（peak 25.2GB / swap
   3.9GB / tps 21.7→10.0）是放大器，不是根因。

## owner 裁定（2026-11-23 12:50）

- Q1：每轮自带前缀 → **首算（客户端 trunk）保持不替换及驱逐**，每轮前缀
  校验后略过（KV 复用），然后每轮 digest + KV 复用。
- Q2：**工具会话整轮替换，工具不是结论，digest 要跟上。**

## 决定

### P0 身份锚定门（HTTPServerChat.digestSubstitutedMessages）

- 每个已结算 ledger 轮以**问题正文 SHA-256** 锚定到真实用户消息。数据源
  `chat_turn_ledger.request_id ⋈ chat_messages ⋈ is_objects`，复用补摘要
  的 `digestableTurnSourcePredicate`（用户行唯一且对象可读），新方法
  `ESISDatabase.turnQuestionHashes(sessionID:)`，**无 schema 改动**。
  正文口径与 settle 落库、TurnDigestScheduler.sourceSHA256 完全一致
  （genuine 问句上 retrievalQuery == envelopeStripped）。
- 锚定读**原始客户端数组**（settle 存的就是注入前正文）；渲染数组里
  附着的 IS 冻结块字节不属于问题哈希。两数组在 trunkEnd..<needIndex
  区间索引一致（attach 只原位改写 user content）。
- 锚定轮必须按数组序恰好构成 t1..tk；计数门 k == ledger.highest，或
  k == highest-1 且滞后真轮在锚定前缀之后**可见**（上一轮结算在途）。
  账上有、数组里没有问题且无可见滞后轮（截断/混合/外部历史）→ fail-closed。
- 摘要链长度封顶到锚定数（`covered = min(covered, pastGenuine)`）：
  摘要行或渲染侧记忆单独不授权替换。
- 替换起点 = 第一个锚定轮：未结算头轮（如永不结算的任务简报）原文保留。
  未锚定真轮（结算滞后/被客户端改写）在 raw 尾部逐字保留，绝不随段删除。
  噪声消息不计数，随所属轮整段替换（Q2 整轮裁定），段外噪声原文保留。
- **每次门判定打 reason 日志**（gate=0 reason=… / gate=1 anchored=…
  covered=…），终结静默失败。
- 有界 fail-open、形态②触发压实、冻结块回放、occurrence 键语义全部不变。

### P1 活跃会话驱逐保护（NativeMLX.evictSessionsIfNeeded）

- 本轮 key 之外**最近活跃的会话**在三个维度（数量 / swap 预算 / 驻留
  字节）统一豁免驱逐（`SessionEvictionSelection.activeProtectedKey`，
  纯函数可测）。digest 回环请求为本轮时，保护位恰好落在刚活跃的主会话
  分片上；用户轮为本轮时主分片已由 keeping 保护。
- 超限先驱其余空闲会话，驱无可驱**软容忍**（不打掉活跃会话来凑预算），
  留痕 `[MLX] evictProtectActive … soft-tolerated`。
- trunk 与历史同分片（sp-* 键），保护活跃分片即保护首算 KV；trunk 本身
  仍是替换碰不到的永久渲染地板（P0 不动 trunkEnd 之前的系统段）。

## 不做的事

- 不调 warmTokenBudget / 驻留上限：容量杠杆归 P3 KV 量化（暖池字节上限
  ~4×，独立 PR），不是 trim 复用（已证伪）。
- 不动 IS 注入块冻结纪律（P2：replay=0 追溯刷新的周期税另案）。
- 不动 digest 调度器（复核期间 21/21 跟上，Q2 的「digest 要跟上」已满足）；
  永不结算的纯工具轮无摘要永久 raw，轮内压实归 owner 未决。
- 压实 KEEP 维持 0（owner 裁定）。

## 验证与边界

- 隔离测试 45 例（DigestPrefixSubstitution 23 + TurnDigestRetry 9 +
  TurnDigestReceipt 4 + EngineIdentityLedger 8 + activeProtectedKey 1），
  含新契约：噪声不顶门、未结算头轮原文保留、工具腿随整段替换、未锚定轮
  即使有摘要也保留 raw、滞后轮可见性判定。
- 测试还暴露并修复了一个真实隐患：锚定若读渲染数组，历史问句附着的 IS
  冻结块会污染哈希（随空间积累非确定性失败）——锚定必须读原始数组。
- **边界**：生产验收（再喂 20 轮看 substituted=1、cacheEff 恢复、无自残
  驱逐、evictProtectActive 留痕）待装机 build17 后执行；本 ADR 的数字均为
  2026-11-23 复核时点值。软容忍意味着活跃分片单独超预算时暖池常驻超限，
  这是设计行为，物理上界由 P3 容量杠杆解决，不是本门的责任。

## 增补（2026-11-23 build18）：ES 零调用复用轮折叠

**真实 zcode 验收暴露的卡死（session 174f54，build17，DB+trace 实证）**：
owner 人工喂 20 题，替换门全程 `gate=0 reason=anchor_mismatch
anchored=ledger-1`，substituted 永不 1。根因不是锚定设计错，而是一个设计外
的真实场景：zcode 重试了第一题，ES 零调用复用（`13:45:25 [IS_REUSE]
settlement=88440E model_calls=0`）把同一问题结算成第二个 ledger 轮 t2，
t1/t2 问题与答案**逐字相同**；客户端去重后数组只保留一份问题。原门对重复
哈希保留最早轮、要求锚定序严格 t1..tk 连续 → t2 永远锚不上 → 永久空洞 →
fail-closed 卡死。合成噪声单测全绿，恰恰没覆盖「复用轮 + 客户端去重」。

**裁定**：连续且 **Q+A 全同**的 ledger 轮折叠为一个 effective run（可证同一
轮、零信息损失）。
- 契约 `turnQuestionHashes → turnSourceHashes`，返回问题与答案双哈希
  （`TurnSourceHashes`，复用 `digestableTurnSourcePredicate`，无 schema 改动）。
- run 渲染头轮 digest；覆盖需**全部成员** digest 行（复用轮也要有自己的摘要）。
- **不同答案的重复不折叠**：独立 run，未锚定则原文保留（无信息损失、不误映射）。
- **非连续重复仍 fail-closed**（防冒充，保留原 anti-masquerade）。
- 每个 run 至多锚定一次（consumed 集）；客户端若显示两份相同问题，第二份
  在锚定前缀内随整段替换，未锚定则 raw 保留。

**对账守卫（测试抓出的回归）**：count guard 必须以**权威 ledger.highest**
为准，用「已锚定 run 的成员总数」对账，而非 run 数。否则「幻影 ledger 轮」
（有账无配对消息，如外部导入）不在任何 run 里却不被发现 → 丢失 fail-closed。
成员求和同时保住复用折叠与幻影守卫：`anchoredLedgerCount == ledger.highest`
（或 `-1 && lagVisible`）。`anchor_mismatch` 增 `matched=` 序列诊断。

**验证**：隔离 48 例全绿（DigestPrefixSubstitution 26〔+3：复用折叠 / 显示
两次折叠 / 不同答案保留 raw〕+ TurnDigestRetry 9 + TurnDigestReceipt 4 +
EngineIdentityLedger 8 + activeProtectedKey 1），非干涉审计通过。既有
`testLedgerHistoryMismatchFallsBack`（幻影轮）先红后绿，证明回归被守住。

**build17 验收其余面（21 ledger 轮 = 20 题 + 1 复用）**：P1 活跃保护实战
生效——主会话全程无自残驱逐、cacheEff 0.96–0.97、尾段多次
`evictProtectActive … soft-tolerated`；摘要 21/21 追上。内存压力信号：上下文
~99k tok 时个别轮 ttft 100–118s @ cacheEff 0.97（swap 3.8GB），属 P3 容量杠杆。
build18 装机后须重喂验收替换门（substituted=1、gate=1、上下文被摘要链压下去）。
