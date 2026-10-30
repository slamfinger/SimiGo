# W2′：prompt 边界整份快照 —— 设计裁定材料（2026-10-28，任务 #92）

状态：**设计（不实现）**。owner 已批准立项（2026-10-28 01:35 「同意」），本文只交付裁定所需的事实、代价与选项，不含产品代码改动。

## 1. 为什么 W2 原形被否、W2′ 还活着

三条实测（同一生产模型 `peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX`，`config.json` text_config：40 层、`full_attention_interval=4`、30×`linear_attention` ＋ 10×`full_attention`）：

- 切片导出唯一可用 API 是 `ChatSession.savePrefixSnapshot(to:upTo:)`（fork `bc64ee6`，`Libraries/MLXLMCommon/ChatSession.swift:1890-1925`）。它在 `for layer in stored.main.cache` 上要求 **每一层都是 `KVCacheSimple`**（:1909 `guard let simple = layer as? KVCacheSimple else { throw .noCacheAvailable }`），并要求 `stored.state == nil`（:1894）。本模型 30 层的缓存是 `MambaCache`（`Qwen35.swift:600` 起，`cache as? MambaCache`，`MambaCache: ArraysCache`，`KVCache.swift:1580`）→ 结构性不可切片，与边界怎么选无关。a17 实测每一轮 `poolTokenExportFailed`。
- GDN 层的状态是**跑到当前位置的递推摘要**（conv state ＋ recurrent state），不是逐 token 行 → 「截断到前 T 个 token」在语义上不存在。
- 反过来，**整份快照不需要截断**：快照边界就等于缓存当时已处理的那一段。所以唯一还站得住的复用形状是「在 prompt 边界整份导出 ＋ 位置精确装载」。

好消息是装载侧**已经写好在 fork 里**，不需要新设计：

- `ChatSession.crossSessionPrefixLookup`（:413 声明，:1357 消费）返回 `(cache: PromptCacheSnapshot, matchedTokenCount: Int)`；
- 装载点 :1368-1376 做 `kvCache.replace(with: snapshot.cache, processedTokenCount: matched)` ＋ **`lmState = snapshot.state`** ＋ 把 ledger 的 `cachedTokens` 置为 `promptTokenIds[..<matched]`、把待算 input 裁到 `promptTokenIds[matched...]`，`cacheReuseMode = "cross-session"`。
- 也就是说：带模型状态（M-RoPE delta）的整份快照，装载侧已支持；产品侧 `ChatSession.saveCache(to:)`（:1856，内部 `savePromptCacheWithReceipt(url:cache:state:)`）也已支持带状态导出，且序列化 switch 覆盖 `MambaCache`/`ArraysCache`（`KVCache.swift:2307`、:2313）。**缺的只有「在正确时刻调用它」和「按 token 精确性准入」。**

## 2. 唯一正确的导出时刻（这是本设计的核心，不是细节）

快照必须代表「prompt 全部进入缓存、且没有任何已生成 token 进入缓存」的那一刻。在 fork 里这个窗口是存在的且唯一：

- `TokenIterator.prepare(input:prefill:)`（`Evaluate.swift:861-895`）：`.tokens` 分支里模型按 `prefill.forEachChunk` 分块预填并**预留 1 个位置**，:875 `step(previous: y)` 把最后一个 prompt token 喂进缓存并采样出第一个 token（:876-877 只把它放进 `y`，**尚未写入缓存**），:882 上报终止进度 `(total, total)`，:894 `kvCachePlan.applyAndValidate(to: cacheStorage)`。
- ⇒ 终止进度点 **不能**用来导出：它早于 `applyAndValidate`，而装载侧要按 plan 应用后的层级结构整份替换（:1362 只核对 `snapshot.cache.count == kvCache.cache.count`，层级**类型**不一致会静默错装）。
- ⇒ 正确 seam 是 **:894 之后、首次 decode `step` 之前**。设计取一个新的 fork 钩子：

```swift
// PrefillParameters（fork 新增）
/// 预填已提交、plan 已应用、首个生成 token 尚未进缓存时调用一次。
/// 用于跨会话/跨进程的 prompt 边界整份快照导出。
public var committed: (@Sendable (_ cache: [KVCache], _ state: LMOutput.State?,
                                  _ promptTokenIds: [Int]) -> Void)?
```

宿主在 `NativeMLX` 里安装它，用现成的 `savePromptCache(url:cache:state:)` 落文件——不需要经过 `ChatSession.saveCache(to:)`（生成中 `cache` 被迭代器独占，走 `SerialAccessContainer.read` 有死锁风险），这一点决定了 **必须传数组出来** 而不是让宿主回头向 session 要快照。

## 3. 准入条件改成纯 token 精确（现在不是）

现状有两套制品，键不同：

| 制品 | 键 | 消费者 | 本模型可用性 |
| --- | --- | --- | --- |
| token 边界（`NativeMLXPrefixPool.exportTokenBoundaries:150-219`，边界=全量＋2048 网格） | `PrefixChain.cumulative(tokenIds)` 的真实 token 前缀哈希 | fork 钩子 `crossSessionPrefixLookup`（:130-146） | **导出必失败**（切片 API） |
| 消息链（`NativeMLX.swift:1661` 轮末 `saveCache(to:)`） | `PrefixMessageChain.stream(history)`，**每条消息 2 个单元**，所以 `tokenCount` 是单元数不是 token 数 | 宿主自己的受管 restore（`poolHit messages=`） | 能写，但边界与 token 位置不可对齐 |

W2′ 要的是把第一行的**键与边界保留、把写侧换成整份快照**，并加两条硬门：

1. `matched == snapshot.tokenCount`（整份快照只能整份用；不存在「用一半」）。装载前用真实 token 重算 `sha256(promptTokenIds[0..<T])` 与声明比对——**以 token id 为权威**，不以消息文本为权威（消息文本→渲染 token 之间隔着模板与 IS 注入块，文本级对账正是 a17 那些漂移的来源）。
2. 只有 `promptTokenIds.count > T` 才允许（fork :1361 已有同形态守卫），且 `input.text.mask == nil`、无媒体、`conversation.cachedTokens.isEmpty`（fork :1354-1356 已有）。

`ExecutionStatePrefixPool.admit` 的 `entry.tokenCount <= promptTokens.count`（:175-202）在此条件下自动满足，不用改语义；要改的是它登记的表示从「消息边界」变成「token 精确边界」，以及 A-2 的 `checkBindAuthority` 对 `.notGoverned` 的处理保持现状（a17 已证它不拦日常路径）。

## 4. 代价（有实测支撑，不是估计口径）

a17 我在真实根留下并随后按 refHash 逐文件删除的 6 个整份快照里，单文件 `169,541,598 B`，同轮 `promptTokens=5110`。按 dims 分解（`kv_heads=2`、`head_dim=256`、10 个 FA 层、bf16、KV 按 `step=256` 向上取整）：

- 10 层 FA：`10 × 2 × (2 × 5120 × 256) × 2B ≈ 105 MB` ⇒ **≈ 20.5 KB / token**，随 prompt 线性增长；
- 30 层 GDN：`169.5 − 105 ≈ 64 MB` **固定开销**，与 prompt 长度无关（≈ `32 值头 × 128 × 128 × 4B ≈ 2.1 MB/层 × 30`，加上 conv state）。

含义：

- 每个新边界写一次就是 **≈105 MB 起**（5k token 会话），且写在**首 token 之前**（同步，因为延迟序列化会撞上 `keys[..., previous..<offset] = …` 的原位切片赋值，读到的可能是带 decode 行的数组）。
- 每轮会话都产生一个新边界 ⇒ 池按轮次线性增长。真实根现在已积累 4.9 GB（a17 清理后），默认开池此前被实测否掉正是因为这条。
- a17 还实测 `prefillStep` 导出序列化量级 0.15 s@58k（那是密集模型切片口径），本模型整份的写盘时延**尚未测**，属实现前必测项。

## 5. 收益边界（以及为什么它排在 #90 之后）

同一安装版、同一模型、同一晚的两条读数把边界划清楚了：

- a16（有稳定会话身份）：`session=004305/main messages=6 reuse=true cacheHitTokens=4449 cacheEff=0.74 mode=extend promptTime=1.8s`（`build/a16/trace-window.log:18`）——**进程内前缀复用在生产 GDN 模型上工作正常**，零磁盘。
- a18（默认配置日常 multipart，无会话身份）：三轮全 `mode=cold cacheHitTokens=0`，引擎键逐请求不同（`1c00b3/main#b0363629` vs `305424/main#b0363629`）——见 §3.31。

⇒ 「回传完整历史的追加式多轮」这一主要场景，**#90（稳定会话身份）就足够**，收益即 a16 实测的 0.74 cacheEff，代价是一次身份解析改动、不落任何磁盘、天然满足「KV 可舍弃」。
⇒ W2′ 只在**内存 session 已不可用**时才独有收益：进程重启后、suspend 释放后、以及被取消轮（#93）里被逐出的 session。也就是说 W2′ 是 #93 的支撑件，而不是 #90 的替代品。

## 6. 与核心不变量的关系

「持久化 KV 不得成为语义连续性、已结算结果消费、suspend 资源释放或跨进程续跑的必要条件」在本设计里如何保持：

- 快照缺失/校验失败 ⇒ `committed` 什么都不做或装载返回 nil ⇒ 回到全量冷预填（慢但对）。**不存在任何依赖快照才能正确的语义路径**；结算消费（§3.31 G4）已经在零 KV 制品窗口里跑通。
- 因此 W2′ 必须是纯效率件：默认关闭，开关语义与 `SIMIGO_PREFIX_POOL` 一致；ES/IS 的行、身份、有效性一律不因它变化。
- 它给 #93 的正是「可舍弃的那一份」：取消轮的 prefill 成果若已在 prompt 边界落过快照，逐出毒 session 不再意味着全量重付；没落过快照就重付——可接受，不是错误。

## 7. 需要 owner 裁定的三点（我不自行选定）

1. **做不做**：W2′ 的独有收益只剩跨重启/跨取消，而单位代价是 ≈105 MB/边界同步写盘。若裁定「先做 #90 ＋ #93，跨重启的冷启动用 W4 预热兜」，则 W2′ 停在设计层。
2. **若做，写入门槛**：`tokenIds.count` 下限、是否只在同 ES scope 已有 ≥N 轮时才写、池容量/淘汰策略（现在没有按字节的淘汰，4.9 GB 是证据）。
3. **是否要 fork 改动**：`committed` 钩子必须进 fork（本仓已维护 fork 与 seam 先例 `6f0af10`）。若不想再动 fork，替代形态是宿主自己按「轮末＋整份」导出，但那代表的是 **prompt＋已生成 token** 的边界，只能在「客户端把上一轮 assistant 原文逐字回传」时对齐——比 token 精确边界弱，且把生成内容写进 KV 边界会放大 #93 的语义风险。我不建议用它冒充 W2′。

## 8. 实现前必测（若裁定做）

- 本模型 `committed` 点同步写盘的真实时延（预期决定它对 ttft 的影响是否可接受）。
- `snapshot.cache.count == kvCache.cache.count` 之外，层级**类型**一致性：装载 Mamba 层快照到按 plan 新建的缓存，`applyAndValidate` 是否幂等（fork 只核对数量，不核对类型——这是 §2 里我拒绝用终止进度点的同一个理由的反面）。
- 位置帧：`Qwen35.swift:397`（`offset = cache?.offset ?? 0` 推 position ids）、`:1090`（`["full_attention": faCache.offset]`）、`:1251`（warm cache 的 M-RoPE = cache offset ＋ state 里的 rope delta）。`ArraysCache.metaState`（:1523-1546）序列化 slotCount/presentSlots/leftPadding/lengths **不含 `offset`**；`KVCacheSimple` 的 offset 由 `state` setter 从 `keys.dim(2)` 恢复（:483）。⇒ 装载后 FA 层 offset 正确，GDN 层 offset 归 0：必须实测确认 GDN 路径不依赖 offset 决定 chunk/state 初始化，否则需在 metaState 增补 offset 持久化（fork 改动二）。这条是本设计**最大的未证风险**，且它是能在测试层先证伪的，不必占真机干净窗口。
