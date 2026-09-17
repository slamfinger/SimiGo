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

## Dense-cache / all-attention 对照组（2026-09-17 追加）

模型：`mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit`（`model_type: qwen3_moe`，48 层
全标准 attention、全层 `isTrimmable=true`）。FFN 是 MoE，但对照组比较的是 **cache 结构**，
故命名取「Dense-cache / all-attention」，避免把 FFN 稀疏性与 cache 可裁剪性混为一谈。
同一测试二进制，`SIMIGO_FORK_MODEL` 覆盖即可切换，断言按 config `model_type` 参数化。

| 指标 | GDN 混合（qwen3_5_moe） | Dense cache（qwen3_moe） |
|---|---|---|
| 快照 cache 组成 | MambaCache=30 + attn=10 | MambaCache=0 + attn=48 |
| 快照体积（≈5.5k tok） | 175MB | **544MB**（每 token KV 只落 10 层 vs 48 层） |
| 分支每轮预填 | 209 / 202 / 208 tok | **24 / 17 / 23 tok** |
| 分支 TTFT | 0.55–0.74s | **0.17–0.24s** |
| 冷路径 TTFT（同 prompt） | 6.1s | 5.8s |
| 输出一致性 / 记忆召回 | 逐字一致 / 4711 召回 | 逐字一致 / 4711 召回 |

结论：

1. **checkpoint fork 语义与 cache 架构无关**——同一套 save/load/分支路径在两种架构下
   全部成立；审查建议的「Dense 先行」作为方法学已无必要，直接实测补齐。
2. GDN 混合模型的 fork **内存经济学在这两个模型上更好**（KV 只落 10 层，快照 1/3 大小）。
   此结论**不外推**：快照成本应按各模型的 attention 层数、KV 维度、数据类型、
   Mamba/GDN 状态布局与序列长度逐模型估算，不能按参数量或「是否 MoE」推断。
3. 官方 `generationTokens` 口径不含结束 token 而快照账本含（dense 实测报告 +1、
   账本 +2；hybrid 两者恰同为 +2）——跨模型对账需留 ±2 口径差，测试已按此校准。
   ±2 容差只避免误报，**不等于恢复路径的 token 账本对账已闭合**：恢复分支
   `cachedPromptTokens=0`、无 `mode` 是官方 raw-cache 语义的计量盲区，修复位在上游。
4. 性能数字绑定本实验条件（单次运行、≈5.5k tok、本机构建）：分支续算量由新增
   token 数决定；两组 fragment token 数差异（209 vs 24）主要来自各自 chat template
   的渲染形态，与 cache 架构无关；TTFT 还受加载、编译与设备缓存影响。
   「Dense 一定更快 / GDN 一定更省」均不成立为普遍命题。

三个概念继续保持分离：**分支语义已验证 ≠ 生产级内存 fork 已完成 ≠ 增量计量协议闭合**。

## 内存版 fork（KVCache.copy()）专测（2026-09-17 追加）

`testInMemoryForkCopyOwnership`：直接打官方层（自建 ModelContainer），从**同一个内存快照**
构造两个分支——每 cache `copy()`（官方红线）、`LMOutput.State` 为 struct 值语义直接共享——
交错顺序 A1 → A2 → B → A3 覆盖双向污染探测：

- 分支每轮官方 `promptTokenCount`：209 / 202 / 208 / 208 tok，冷参照 5442 / 5441（fragment 量级直证）
- A、B 输出与各自全量渲染冷参照**逐字一致**；4711 双向召回（含 B 运行后 A 再续）
- 结论：**`copy()` 足以隔离**——「低成本内存内 fork」从未验证升级为实机建立

边界注记：本测试是单线程顺序交错；并发分支执行仍不在证据内（生产 `__global_generation__`
本就串行）。跨分支共享的 `state` 是 struct，行为断言背书了值语义成立。

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
