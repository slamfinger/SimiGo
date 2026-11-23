# ADR: 折叠复用轮摘要零调用复制 + 结算 demand 新鲜度改绑（build21）

- 日期：2026-11-23
- 状态：已采纳（owner 2026-11-23「两个一起改」裁定），随 build21 PR 实施
- 关联：ADR_ANCHORED_SUBSTITUTION_GATE_20261123、ADR_WARM_DIGEST_SETTLE_TIME_20261123

## 背景与实证根因

build20 重喂验收（session 0072cb0a，trace + DB 双证）暴露两个独立缺陷。

### 缺陷 A：折叠复用轮缺 digest → no_coverage 冷窗

- turn 1（Q `7fcdd2f9` + A `6c44308c`）21:38:43 结算；暖摘要 21:39:03 落库
  （`[DIGEST_WARM] elapsed_ms=18369`，swap 抬高）。
- turn 2 同 Q+A 的 ES 零调用复用 21:38:50 入账（ledger `live-d80c5206`），
  **比 turn 1 暖摘要早约 13s**。
- 替换门把连续同 Q+A 轮折叠为一个 run，但 `runCovered` 要求每个成员轮都有
  digest 行（build18 裁定，零信息损失）。复用轮无生成腿 → 无暖摘要 →
  turn 2 缺行 → `gate=0 reason=no_coverage ledger=2`。
- 异步兜底队列 21:42:05 才补上 turn 2（重新生成 173 tok）——约 3 分钟冷窗，
  期间每轮全冷重建。fix1（准入后刷新）只消滞后，不能凭空造覆盖。

### 缺陷 B：结算腿绑冻结 demand → 重试答案被丢

- 第二题 demand `05f761` RESOLVED；owner 暂停让 agent 重答，重试 is_search
  新建 `83b558`（同 query、同 request_identity），按 supersede 规则
  （`ESISDatabase.swift:7653`）把 `05f761` 置 SUPERSEDED。
- 21:41:38 生成答案 1127 tok（`toolCalls=0`），但 `settleInformationTurn`
  传 `turn.renderedResolution`（冻结 `05f761`）；advance 守卫
  （`ESISDatabase.swift:8213`）要求 `state=='RESOLVED'` →
  `invalidTransition(SUPERSEDED→ADVANCED)` → `[SETTLE_REJECT]`
  `chat_committed=0`，整轮 cancelled，答案丢失。
- 复用腿早已修过同类新鲜度问题（`HTTPServerChat.swift:1226` 注释：新鲜度
  读当前 candidate 而非冻结快照）；生成答案的结算腿未跟上这条规则。

## 决定

### 修复 A：`fillFoldedReuseDigests`（双向幂等零调用填充）

- `ESISDatabase.fillFoldedReuseDigests(sessionID:)`：按 `turnSourceHashes`
  升序扫描，记每个 `question|answer` 键最早有 digest 的轮；任何同键且无
  digest 的轮，零调用复制该 digest（`recordTurnDigest`，带源 hash 校验）。
  返回被填充轮供调用方喂渲染侧内存。
- 两个调用点覆盖两个时序：
  - **向后**：`scheduleLiveTurnDigest` 入账后调用——复用轮结算时源摘要已存在。
  - **前向**：`TurnDigestScheduler.recordDigestAndAssign` 写摘要后调用——
    复用轮先入账、源摘要后到（build20 真实时序）。
- 填充即喂 `ISContextLedger.rememberDigest`；留痕 `[DIGEST_COPY] model_calls=0`。
- **fail-open**：`try?` 包裹，填充失败回落原异步 schedule/兜底，绝不使已写
  摘要失效。
- 不改替换门不变量（仍要求每成员轮有行），只把行补上。房间归属仍走主写
  路径；复制行的搜索索引经 pending/backfill 自愈。

### 修复 B：`settlementResolution`（结算 demand 新鲜度改绑）

- `InformationLoop.settlementResolution(rendered:candidate:)`：仅当
  `rendered.demandID` 已 SUPERSEDED、candidate 仍 RESOLVED、且
  `candidate.resultSHA256 == rendered.resultSHA256`（检索内容基字节一致）
  时改绑 candidate；否则原样返回 rendered（保持历史拒绝）。
- `settleInformationTurn` 改用其结果传给 `settleTurn`；改绑留痕
  `[SETTLE_REBIND] basis=resultSHA256`。
- **fail-closed**：candidate 缺失 / 也被 supersede / 基不同 → 不改绑。
  `resultSHA256` 一致保证答案的信息基未变，只是 demand 行移动。

## 边界与诚实声明

- 修复 B 只覆盖「settle 时渲染 candidate 仍 RESOLVED」的 observed race；
  若 candidate 也被第三个 demand supersede，仍 fail-closed 拒绝（罕见，
  后续可迭代为 settle 时重解析）。
- 复制行的房间归属不在 fill 内做（coverage 优先），搜索索引自愈。
- 传输层错误（request `fbba430f`，连接接受即取消、未进引擎、无 DB 行）与
  本两缺陷无关，另行排查 zcode 客户端侧。

## 验证

- 包级 `InformationReuseTests` 22/22（含 4 新改绑守卫测试：正向改绑 /
  未 supersede 保持 / candidate 也 supersede fail-closed / 基不同 fail-closed）。
- app 级 `DigestPrefixSubstitutionTests` 32/32（含 2 新：向后零调用复制、
  前向迟到传播；`seedDigest` 改 UPSERT 适配自动复制）。
- 复用/取消套件 `ChatAnswerReuseHTTPTests` + `ResponsesAnswerReuseHTTPTests`
  + `CancelPathStubHTTPTests` 26/26。
