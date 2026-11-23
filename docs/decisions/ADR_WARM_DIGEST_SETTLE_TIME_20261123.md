# ADR: 暖摘要——结算即落库 + 即时替换（Q2）

- 日期：2026-11-23
- 状态：已采纳（owner 2026-11-23 裁定），随 PR #339 实施
- 关联：ADR_ANCHORED_SUBSTITUTION_GATE_20261123、ADR_TOKEN_PREFIX_REUSE_20261122、ADR_IS_RENDERING_KV_DECOUPLING_20261121

## 背景

digest 回环的异步空闲产出（等空窗 + 安静 1.5s、有人排队就让位）是**上一
阶段为检索索引**做的设计——「不跟人抢引擎」。那时摘要只是搜索入口，晚
一点落库没有功能损失。

本阶段摘要已经是**替换功能件**，处在上下文压缩的关键路径上：替换门要求
「锚定轮全部有摘要」才放行，摘要滞后 → raw 尾撑大 prompt → 内存压力下
慢 prefill。build18 重喂监控实证（note 2444ECDD）：r=cc5cf8 的 10693
delta tok prefill 耗 231s（~46 tok/s，swap 2.8GB），根因正是摘要滞后 ×
swap 压力，摘要补齐即消解。owner 据此裁定改设计。

## owner 裁定（2026-11-23）

- 本机大模型计算完答案后，**还在 warm 阶段**对已在内存的问答再做一次
  精编摘要计算（不是节选，不是延迟异步排空）。
- **摘要结算时即落库，同时还要替换。**
- 形态 A：暖摘要在答案送达客户端（[DONE]/JSON 发出）之后跑，**占住
  admission permit 约 2–5s** 再释放；异步排空保留为兜底（回填/重试/
  复用轮/工具轮/暖失败）。

## 决定

### 暖产出路径（HTTPServerChat.produceWarmDigest）

- chat 流式/非流式两个生成站点：settle 返回 `LiveDigestJob?`（轮号 +
  内存里的 Q+A），[DONE]/JSON 发出后、permit 释放前 `await` 暖产出。
- **直调 `generateHandler`**（进程内引擎入口），不走 loopback、不二次
  过 HTTP admission。生命周期按 G1G3 先例：先
  `RuntimeLifecycleCoordinator.register`，生成后 `finish`。
- **常量 digest 会话键 `simigo-turn-digest`**：与所有聊天会话 KV 分离，
  不碰聊天前缀；所有暖摘要共用一条 lane，模板+简报前缀跨轮可复用。
- 配置镜像回环产出器的三个覆盖（temperature 0.2 / maxTokens 600 /
  repeatPenalty 1.15），其余落模型 baseConfig。
- 提示词复用 `TurnDigestText.prompt(question:answer:background:)`，
  background 复用 `TurnDigestScheduler.briefBackground()`（改为 internal，
  单一事实源）。

### 落库 + 即时替换（复用既有写路径，零新机制）

- `TurnDigestScheduler.recordDigestAndAssign`：源 SHA 校验落
  turn_digests + `ISContextLedger.rememberDigest`（渲染内存）+ 归属。
  下一轮替换门立即 covered==anchored，**无 raw 尾滞后**。

### 有界 fail-open

- 30s 超时竞赛（`warmDigestTimeoutForTesting` 可注）：超时即取消生成
  （引擎逐 token 检查取消），task group 等取消完成才返回——下一个请求
  不会撞上停了一半的引擎。
- 任何失败（格式/写库/超时/引擎）都不抛：**兜底 job 已在队列里**，异步
  drain 原样接管。`SIMIGO_DIGEST_WARM=0` 只关暖路径（诊断 A/B）。

### 兜底竞态修复（TurnDigestScheduler.generate）

- digest 存在性复查从「等空窗前」移到「等空窗后」：暖写在 drain 等待
  期间落地时，drain 直接跳过，不再重复生成一次（省一次引擎调用）。
  暖路径占 permit 期间 drain 的 waitForIdle 必然阻塞，所以复查时暖写
  已成定局，判据可靠。

### 本期范围

- reuse 轮：无新生成，保留异步兜底（复用折叠渲染头轮 digest）。后续：
  直接复制源轮 digest（零模型调用）。
- responses 线：保留异步兜底，零行为变化。
- 工具叙述腿：照旧 commit-only，不入账不摘要。

## 证据

- 隔离 51/51 全绿（build19-warm-r2，非干涉通过）：
  DigestPrefixSubstitution 29（+3 回归：暖写+下轮即时替换 / 格式不合
  兜底 / 有界超时）、retry 9、receipt 4、engineIdentity 8、
  activeProtectedKey 1。
- 首轮 trace（产品路径，测试桩引擎）：
  `[DIGEST_WARM] turn=1 wrote=1 elapsed_ms=4 fallback=queued_noop` →
  下一轮 `gate=1 anchored=1 covered=1 ledger=1 substituted=1 messages=3`。
  **注意：4ms 是测试桩引擎的数字，不是真实模型时长。**真实模型暖摘要
  耗时（预期 2–5s 量级）与 permit 占用对下一轮 ttft 的影响，待 owner
  重喂验收实测。

## 后果与权衡

- 下一请求的准入被暖摘要占住约一次摘要生成的时长（有界 30s）。这是
  owner 批准的形态 A：用答案后的一段占用，换下一轮 prompt 立即被摘要
  链压低——关键路径上的总开销下降（raw 尾不再撑大 prefill）。
- digest lane 是独立小会话（~3–5k tok 量级），远低于驱逐阈值；与 P1
  活跃保护的交互在重喂验收中观察（预期无自残驱逐）。
- 异步 drain 保留全部既有职责：启动回填、暂时失败重试、reuse 轮、
  工具轮后的最终轮、暖失败兜底。暖路径只是把「最常见的成功路径」从
  空闲窗口搬到了答案后的暖窗口。

## 未决

- reuse 轮 digest 复制（零调用）。
- responses 线暖接线。
- 真实模型暖摘要时长 / permit 占用 / 内存压力改善的验收实测。

## 增补：build19 重喂验收基线 + 修复 1（2026-11-23 晚）

### 暖态真实基线（real session 174f54，26–36 轮）

- `[DIGEST_WARM] elapsed_ms` 实测 **8.6–12.1s，随 swap 压力上升**（不是
  测试桩的 4ms，也高于先前 4–6s 估计）。分解：digest prefill ~1.1–2.2s
  （1179–1334 tok）+ 解码 ~137–175 tok（标称 tps 46–50，swap 下墙钟更长）
  + 落库/归属 ~0.7s + 准入/建立 ~1–2s。
- 暖路径机制成立：每轮 `wrote=1 fallback=queued_noop`（drain 跳过，竞态
  修复生效）；permit 确实占到暖写完成（下一轮 `waited=0ms` 紧接准入）。

### 暴露的真问题：覆盖滞后一轮 → 每轮全冷重建

- 每轮 `partial covered=(anchored-1)`。根因：渲染门
  `prepareInformationTurn` 在**准入之前**跑，冻结快照比上一轮暖写落地早
  ~0.7s；快喂（间隔 < 暖摘要耗时）下一轮渲染总赶在暖写之前。
- 铁证：`prefixDiff index=32 stored(user,len=3813)='请说明市政道路工程移交
  养护管理单位…' incoming(user,len=258)='[Earlier turn t26 digest…'`。
  上一轮 KV 里 t26 还是 raw 原文，这一轮翻成 digest——滞后致 raw→digest
  **晚翻一轮**，前缀匹配归零 → 全冷 37–42k tok，prefill 45.9→63.5→75.9→
  98.8s 逐轮恶化，decode tps 30→19.9。
- 排除内存回收：`memPoolPurge entries=0`、无 suspend——冷重建是渲染前缀
  本身每轮在变，不是 KV 被回收。叠加 IS 注入块每轮 churn（P2）。
- swap 压力回升：空闲 87%→34–42%，swap→4.2G，模型 18.6G + KV peak 22G。

### 修复 1：准入后覆盖刷新（PR #340，build20）

- `InformationTurn.presubstitution` 携带预替换快照（IS 块已附着）。
- 拿到 permit 后（上一轮暖写已落地）、生成前，`refreshedDigestMessages`
  重跑**同一个门**，读 `ISContextLedger` 最新覆盖 → 生成用
  `covered==anchored`，无滞后 raw 尾。fail-open 保留冻结渲染；不重渲染。
- chat 流式/非流式两站点；responses 线本期不动。
- 隔离 52/52 全绿（build20-fix1-r1），+1 回归
  `testPostAdmissionRefreshCoversLaggingTurn`，DIGEST_REFRESH 全套触发 22 次。

### 诚实边界

修复 1 消除滞后一轮、最小化 prompt。**KV 前缀复用是否完全恢复**还取决于
引擎 message-prefix 复用如何处理推进的 digest 边界 + IS 注入前缀块 churn
（P2 冻结）——门注释把边界成本界定交给 token-level prefix-reuse ADR。
build20 重喂量 cacheEff；若前缀仍 churn，P2 是下一杠杆。swap 底因归 P3
（KV 量化 warm-pool 字节上界 / 降 ctx）。
