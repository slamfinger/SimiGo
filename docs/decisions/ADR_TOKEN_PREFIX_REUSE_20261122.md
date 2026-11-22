# ADR：token 级前缀复用——替换会话进程内复用的连续性粒度统一（2026-11-22）

**状态：提案（待 owner 裁定；引擎改动，未实施）。**
承 `ADR_IS_RENDERING_SNAPSHOT_PERSISTENCE_20261122`（#335，跨进程渲染链可复现，T4 集成验收已通过）：#335 修「可复现」，本 ADR 修「可复现的链在进程内真正可复用」。
驱动证据：`ES-IS-research` Spike A #4（063C118B）h100/h50 双臂 trace；根因分析注记 35ADB7F2。

## 问题（实证 + 代码锚点）

替换 ON 臂**每轮全 cold**：h100 100/100 轮 `mode=cold cacheHit=0 cacheEff=0.0`（h50 同）；T100 cttft 35.8s 中引擎 cold prefill 30.9s（87%）。OFF 全文臂 `mode=prefix cacheEff≈0.9`（h50 off turn8 cacheHit=21936；注意 `mlx_metrics` 合并 chat+digest 两条 [MLX] 行 last-wins，promptTokens 精确值须原始 trace 复核）。双臂 digest 都在同引擎跑（internal scope、DigestGenerationGate 串行、utility 优先级）→ **digest 交错不是 cold 的原因**。

根因（本分支现取锚点）：
1. 同会话复用门 `SimiGo/Inference/NativeMLX.swift:2050` `Self.isPrefix(existing.history, of: incoming)` 是 **[Chat.Message] 消息级**严格前缀（`messagesMatchForReuse` :3964：role+content+toolFlag 全等）。
2. 替换把第 N-1 轮 frontier 从 raw user+IS块+assistant **retroactive 重写**成 digest 消息 → 第 N 轮边界消息不匹配 → `reuseMiss prefix=false`（:2080 诊断行）→ 每轮全 cold。
3. token 级共享前缀（trunk + chain t1..t(N-2)，深度 ~95%+）**物理存在**，但消息级门看不见。
4. 跨分片 adoption 同粒度：`NativeMLXResidency.swift:244` `.notStrictPrefix`、`NativeMLX.swift:3220-3228`。

**内存不连续是结构性的（连续性契约粒度），不是调度时机**——digest 瞬间完成，cold 依旧。代码里已有预期：`prefixDiffLine` 注释（:3975 附近）自写「token 级 LCP 待接入 tokenizer 后作为后续档位」。

## 决定（提案）

**消息级前缀门失败且替换渲染激活时，降级到 token 粒度最长公共前缀（LCP）复用**：对 existing.history 与 incoming 分别 tokenize，取 LCP token 数，把 existing KV cache 截断到 LCP 边界，只预填 delta。

- **安全门不动**：count/kvFingerprint/agent/thinking 判据全部保留；token 前缀是比消息前缀**更强的物理证明**（逐 token 相等 ⇒ KV 状态逐位一致），不是放宽。
- **先例复用，不发明新机制**：
  - `toolEchoNormalize`（NativeMLX.swift:2062，2026-10-15 批准）已确立「表示漂移归一化后再复用」的裁定——本件是同一哲学在粒度维度上的延伸；
  - 磁盘池本就是 token 域（`NativeMLXPrefixPool.swift:263-272` `promptTokenIds` lookup/admit；`NativeMLX.swift:1663` 导出）——本件把 live-session 路径与 pool 路径的连续性粒度**统一**。
- **粒度不对称 note**：磁盘池 admit 是 token 域，跨进程 poolBind 可能已容忍替换边界（待实测）；进程内 live-session 复用是消息域 → 仍 cold。统一后两路同判据。

## 与 B（有界 fail-open）的分工

B（本 PR 已实施，`digestSubstitutedMessages` 最长连续覆盖前缀替换）把 digest 覆盖滞后的渲染代价从 O(depth) 降到 O(lag)，去掉 ~40 轮 ctx 墙悬崖。但 raw↔digest 边界每次转换仍重写一段已提交字节 → 消息门 miss → 该段 cold。**A 把这段 cold 限制在边界轮之后**：trunk+chain 共享前缀 token 级保留，只预填转换段。A>B>C>D 排序中 A 是最大杠杆（31s→亚秒 delta 预期）；C（deadline 调度）/D（生产成本近常数）延后。

## 安全 / 哲学对账

- 三平面不动：IS 真值 / ES 计算 / KV 物化。LCP 截断是 KV 物化层操作，不触碰 IS 语义准入（resolve/reusableAnswer 判据不变）。
- fail-open：tokenizer 不可用 / LCP 计算失败 → 退回今日消息门行为（cold），绝不复用错 KV。
- 量化交互：kvFingerprint 门不变；量化 KV 切片不进池（#333 裁定），pool token 域导出条件（kvCache≠基配置不产 .tokenIDs，缺口⑯）不在本件扩大。
- 产品默认不变：替换研究旗标 `SIMIGO_DIGEST_PREFIX_SUBSTITUTION` OFF；本件只在替换激活时生效。

## 不做（边界）

- 不改消息门本身（非替换会话行为零变化）。
- 不做 IS 渲染全量解耦 / 账本移除（承 2026-11-21 ADR 后续）。
- 不在本件实施 C/D 杠杆。

## 验证（实施时）

- 契约级：LCP 截断正确性（token 边界对齐、截断后 delta 预填字节级一致）、fail-open、安全门保留。
- 真机 A/B（研究模式，替换 ON）：cacheEff / cttft / swap 对照今日全 cold 基线；h100 深度复跑。
- 与 #335 叠加格：量化 × 替换 × 磁盘池 × 真重启 → poolBind + 进程内 LCP 复用同绿。

## 影响范围

- `SimiGo/Inference/NativeMLX.swift`：复用门降级档位（:2050 分支）+ tokenizer 接入（引擎已有 tokenizer，pool 路径在用）。
- `SimiGo/Inference/NativeMLXResidency.swift`：adoption 判据同档位（可后续）。
- 研究地图：连续性粒度统一补进 `docs/research/es-is`。
