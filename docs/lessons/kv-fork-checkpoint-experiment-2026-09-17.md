# KV checkpoint 分叉实验：GDN 不可 rewind 但可 fork（2026-09-17）

**日期：** 2026-09-17
**模型：** peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX（`model_type: qwen3_5_moe`，快照 31a0106）
**依赖：** mlx-swift-lm `5ba0bc1`（vendor 快照谱系，Package.resolved 钉扎）
**载体：** `SimiGoTests/KVBranchForkExperimentTests.swift`（`SIMIGO_FORK_EXP=1` 触发，宿主式 Release 测试，37s 全绿）

## 背景

fork-no-rewind 遥测已证明：qwen3_5_moe 的 GDN 层（MambaCache，30 层）`isTrimmable=false`，
渲染分叉后无法倒回公共前缀，只能整会话 rebuild。本实验验证相反方向的命题：
**在分叉发生之前保存 checkpoint，从 checkpoint 派生多个分支，各分支只计算新增 token**——
即「GDN 不可 rewind，但可 fork」。

## 证实结论（四验收）

| 验收 | 结果 | 证据 |
|---|---|---|
| A1 快照携带 GDN 状态 | ✅ | safetensors 头解析 `MambaCache=30 attn=10`（与 30 GDN + 10 attention 层审计一致），175MB |
| A2 分支零重算 | ✅ | forkA 两轮 + forkB 各只预填 **209 / 202 / 208 tok**，TTFT 0.55–0.74s；checkpoint 账本 5413 tok 逐位在列（trace `cacheTokens=5413`） |
| A3 输出与冷路径一致 | ✅ | greedy 下 forkA≡coldA、forkB≡retr 逐字相同；4711 长程记忆探针跨 checkpoint 往返后仍召回（GDN 状态功能等价，非仅结构在） |
| A4 rewind 不可用的代价对照 | ✅ | 同一 prompt 双路径：fork 208 tok/561ms vs 冷 5441 tok/6131ms（prefill 26×、TTFT 11×） |

## 踩坑一：saveCache 的文件后缀必须是 `.safetensors`

`NativeMLX.saveSessionCache` 原用自造后缀 `.cachesnapshot`，首次实跑即抛
`unknownExtension("cachesnapshot")`。官方 `mlx-swift` IO（`Source/MLX/IO.swift`）
按 `url.pathExtension` 严格分派，只认 `safetensors`/`npy`。该 API 此前零调用方，
实验首次驱动即抓到。已修：快照文件名 `<baseName>.safetensors`（meta sidecar 不变）。

## 踩坑二：恢复分支的复用遥测是盲区（官方语义，非缺陷）

从 checkpoint 恢复的会话是 raw-cache + fragment-continuation：**没有 token 账本**，
官方 PromptCacheReusePolicy 无可对照对象 → 不发 `mode` 字符串，`cachedPromptTokens=0`、
`cacheEff=0.00`（官方原值透传，SimiGo 不估算）。分叉零重算的物理证据只能由
`cacheTokens`（载入后账本长度）、`promptTokens`（本轮实际预填 delta）、TTFT 三项承担。
若未来要让恢复路径进入命中率统计，需官方在 fragment 路径补账本语义——升级候选，非本地可修。

## 结论适用范围

- 分叉点是**会话边界**（某次生成完成后），不是任意 token 位置；覆盖生产主要分叉场景
  （重试、分支续写、tool 分叉的公共祖先）。
- 分支隔离靠磁盘反序列化天然独立实例（等价官方「copy the caches before constructing
  multiple sessions」红线）；实验中 forkA/forkB 输出互不污染。
- 实验为 3k 级上下文单机样本；更大上下文的快照体积（175MB@5.4k tok ≈ 32KB/tok）
  与加载耗时需另行评估。

## 后续候选（观察窗口内不改）

- 生产化 branch-fork：`AgentExecutionKey.logicalBranchId` 寻址已备，缺的只是 UI/协议层触发点。
- 恢复路径遥测补全（依赖官方账本语义）。
- 内存版 fork（`KVCache.copy()` 共享不可变缓冲）避免每分支整份反序列化。
