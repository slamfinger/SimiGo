# SimiGo v1.3 发布说明

日期：2026-09-14
依赖基准：mlx-swift-lm `exp/cancel-retained-prefix@45ccd57`（本地 checkout `/Users/mr.simi/Documents/mlx-swift-lm`，fork 备份 `slamfinger/mlx-swift-lm`）

## 本版主题：接回 Exact Match 复用语义 + 连续命中率遥测

v1.2 迁移官方积木后，旧 NativeMLX 的 Exact Match（prompt 与物理 token 账本完全
一致时保留 N-1 行 KV、只重喂最后一个 prompt token 的续接语义）被丢失，凡
prompt 与账本一致的场景一律全量冷预填。v1.3 以官方复用策略层的第一类规则
将其接回，并把「复用/不复用」两个极端升级为逐轮连续命中率。

## 变更清单

### 引擎（mlx-swift-lm 45ccd57）

- `PromptCacheReusePolicy` 新增 `ExactMatchRefreshRule`（standardRules 首位）与
  `exactMatchRefresh(refreshIndex:)` 决策。八个安全条件缺一不可：
  `common == cached == prompt`、`common > 1`、main/draft 账本对齐、全参与层
  `isTrimmable`、无 media / attentionMask / modelState。任一不满足即落回
  既有规则（fork 仍 rebuild，不强行回卷）。
- 应用点走与 `trimToCommonPrefix` 相同的 trim→校验→降级 rebuild 契约：
  trim 短于请求即降级，绝不带病预填。
- `GenerateCompletionInfo` 新增 `cacheReuseMode`（extend / extend-main /
  exact-n1 / rewind / fork-no-rewind / rebuild / cold），由 ChatSession 按本轮
  实际物理路径注入。
- policy 单测 16/16 绿，含关键反例：identical prompt + 不可 trim（GDN 形态）
  → rebuild。

### Runtime（SimiGo）

- `[MLX]` 轮末日志新增 `mode=`，与既有 `cacheHitTokens=` / `promptTokens=`
  分子分母共同表达连续命中率：
  `cacheEff = cacheHitTokens / (cacheHitTokens + promptTokens)`。
- 修复工具轮击中率：真实客户端回传全量对话时剥离 assistant 的 `tool_calls`
  （`prefixMismatch historyTool=true incomingTool=false`），前缀比对每轮必挂，
  每个工具轮全量冷预填（冷/热交替，22k token 轮 TTFT 35s+）。现对
  「同 role+content、存储侧带工具、回传侧不带」的 assistant 消息容错续接
  （trace 行 `assistantToolEchoLoss`）；被续接 session 的内部会话保存权威
  工具调用记录，客户端对历史消息的回传从不参与渲染。内容不同仍按真分叉。
- 修复 SSE 心跳闭包残留 `[weak self]` 空捕获告警（行为零变化）。

## 已知限制（非本版引入）

- **Qwen3.5 混合缓存渲染分叉**：GDN 层不可回卷，assistant 消息含多个工具
  调用块时模板重渲染与生成流对齐失败即 `mode=fork-no-rewind` 全量重预填
  （遥测如实标记）。修复在上游；本地缓解=控上下文规模。单工具结果轮
  正常 extend（实测 0.87–1.00）。
- exact-n1 仅在 prompt 与账本完全一致时触发；SimiGo 同消息重试门
  （`incoming.count > existing.history.count`）未放开，同消息重试仍走
  新会话冷预填。放开与否属后续独立决策。

## 验证记录

- policy 单测 16/16（`xcodebuild test-without-building -only-testing:MLXLMTests/PromptCacheReusePolicyTests`）。
- Release clean 重建（`-derivedDataPath build/release`）EXIT=0 零 error；
  依赖 checkout 核对 45ccd57；产物符号表含 `cacheReuseMode`。
- 实机工具轮（03:49–03:51）：cacheEff 0.87–1.00、TTFT 1.2–2.5s，冷/热交替消失。
- DMG `hdiutil verify` VALID。
