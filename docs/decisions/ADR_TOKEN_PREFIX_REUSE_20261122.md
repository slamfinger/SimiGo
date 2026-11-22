# ADR：digest 接地滚动压实（形态②）+ 前缀复用——模型可行性裁定（2026-11-22）

**状态：形态②触发式压实 + 键锚定 brief 已实施；产品默认替换 ON（owner 2026-11-23 裁定，env=0 可关，fail-open 不变）。实验 1（perf-full-ON 同轮 100，build aeaa3a51）性能杠达标（深轮清洁同轮 2.5×、前缀封顶、预填速率回清洁档、零 fail-open 灾难）；needle 质量门 normal 7/29 FAIL（叙事 brief 丢精确键 + IS 块行级词法 echo 仅 4/29 键 + 模型先验幻觉）——修复杠杆键锚定 brief 已实施（逐字保留 key:value 锚点 + 仅压叙事，离线 needle-prefix 24/29 键保留），装机复验待跑。实验 2 A 杠杆（可 trim 模型 fork 复用）引擎已实施：reuseMiss 时 `ChatSession.fork(history:)` 把暖 KV 接到重写转录、引擎 token-LCP 政策 trim（`SIMIGO_TRIM_REUSE` 研究旗标，默认 OFF，产品冷重建行为不变）；模型前提现取核实——当前产品选择 Nail-Qwen3.6-35B-A3B（qwen3_5_moe，30 GDN 层，不可 trim），实验 2 在本地 Qwen3-Coder-30B-A3B-4bit（qwen3_moe，48 全注意力，可 trim）上跑 A/B，验证亚秒 delta + 模型选择杠杆是否值得切换产品目标模型。SimiGo 对适合的大模型保持兼容（模型选择是杠杆）。owner 2026-11-22 细化：brief 是冷填重建点，按 h100 最小冷填速率在轮次/token 上选检查点触发压实，而非每轮；故障或冷 prefill 预计超时即做 brief 冷填。**
本 ADR 经**两个本机模型**现取核实后重写：A（token 级 LCP 截断复用）**模型相关**——本机当前 GDN 模型（Ornith）不可 trim、A 不可行；纯注意力模型（Qwen3-Coder-30B-A3B）可 trim、A 已核实可行（见 §2）。**撤回的是「A 是当前 GDN 模型主杠杆」的断言，不是 A 本身。** 可行核心 = **形态②滚动压实 + append-only 复用纪律**，A 作为可 trim 模型上的复合杠杆。
驱动证据：`ES-IS-research` Spike A #4（063C118B）h100/h50 双臂 trace；根因注记 35ADB7F2；owner 裁定（形态②、磁盘池永久 OFF、物化证据已完成）。

## 1. 问题（实证）

替换 ON 臂**每轮全 cold**：h100 100/100 轮 `mode=cold cacheHit=0 cacheEff=0.0`；T100 cttft 35.8s 中 cold prefill 30.9s（87%）。OFF 全文臂 `mode=prefix cacheEff≈0.9`（h50 off turn8 cacheHit=21936；`mlx_metrics` 合并 chat+digest 两条 [MLX] 行 last-wins，精确值须原始 trace 复核）。双臂 digest 同引擎跑 → digest 交错不是 cold 的原因。

根因：同会话复用门 `NativeMLX.swift:2050` `Self.isPrefix` 是**消息级**严格前缀（`messagesMatchForReuse` :3964）。替换把第 N-1 轮 frontier 从 raw **retroactive 重写**成 digest → 边界消息不匹配 → `reuseMiss prefix=false`（:2080）→ 每轮 cold。**内存不连续是结构性的（连续性契约粒度），不是调度时机。**

两个目标（owner）：**延迟**（少 cold prefill）+ **内存**（KV/递归态封顶，治本机 swap 压力）。物化证据已完成（#333 量化 KV round-trip + #335 T4 跨进程 bind）；此后 KV 工作只在「增加可复用前缀量」意义上有价值。**磁盘池永久 OFF**（`RuntimeTuning.prefixPoolEnabled` 默认 OFF；#335 持久快照门控其上 → 产品零开销，纯研究装置）。

## 2. 模型可行性裁定（两模型现取，决定性）

trimmable 是**模型相关**的，不能从单一模型概括。两个本机模型现取核实：

**轴厘清**：两档的轴是**注意力架构**（全注意力 vs GDN 线性递归），**不是 MoE/dense**（FFN 轴，与 KV cache 结构无关）。两个核实模型**都是 MoE**（qwen3_moe / qwen3_5_moe，num_experts 128/256），一可 trim 一不可 ⇒ MoE/dense 与 trimmability 无关。dense 纯注意力同样可 trim，dense GDN 混合同样不可。

| 模型 | model_type | 层 | cache | 可 trim | A（LCP 截断） |
|---|---|---|---|---|---|
| `Ornith-1.5-35B-A3B-MLX-4bit`（本机在用 SelectedModelPath） | qwen3_5_moe | 30 GDN linear_attention + 10 full_attention | MambaCache×30 + 注意力 KV×10 | **false** | **不可行** |
| `mlx-community--Qwen3-Coder-30B-A3B-Instruct-4bit` | qwen3_moe | 48 全注意力（无 layer_types/linear/GDN 字段，use_sliding_window=False） | KVCacheSimple/Quantized×48 | **true** | **可行** |

**GDN 模型铁证**（`.../mlx-swift-lm/Libraries/MLXLLM/Models/Qwen35.swift:1235-1244` `newCache`）：
```swift
if layer.isLinear { return MambaCache() }
// Full-attention layers honor maxKVSize; GDN / linear layers keep
// a fixed recurrent state that cannot be token-windowed.
```
- `MambaCache: ArraysCache: BaseKVCache`，`isTrimmable=false`（KVCache.swift:299，无 override），`trim` 返回 0。
- `canTrimPromptCache = cache.allSatisfy { $0.isTrimmable }`（KVCache.swift:2750）→ 30 层 GDN ⇒ 整模型不可 trim。与 `NativeMLX.swift:3290` 取消路注释「30× GDN 递归层 isTrimmable false」自洽。

**纯注意力模型铁证**（`Qwen3MoE.swift` 零 Mamba/linear/GatedDelta/ArraysCache 引用；`LanguageModel.swift:600-605` 默认 `newCache` 逐层 `makeAttentionKVCache`；`CacheConfiguration.swift:317` 无 sliding window → `KVCacheSimple()`，量化 → `QuantizedKVCache`）：
- `KVCacheSimple.isTrimmable=true`（KVCache.swift:568）、`QuantizedKVCache.isTrimmable=true`（:1484），`trim` = `offset -= min(offset,n)`（O(1) 回退）。
- 48 层全可 trim ⇒ `canTrimPromptCache=true` ⇒ **A 在此模型可行**。

**裁定①（模型 scoped，非普遍撤回）：A（token-LCP 截断到共享前缀、只预填 delta）在 GDN 模型（Ornith）上不可行，在纯注意力模型（Qwen3-Coder）上已核实可行。** `trimPromptCache`（KVCache.swift:2763）/ `ChatSession.record()` 取消路 trim（ChatSession.swift:268-313）机制现成：纯注意力模型直接复用即可拿亚秒 delta；GDN 递归态固定、不能 token-window，无法回退到 LCP。**撤回的是「A 是本机当前 GDN 模型的主杠杆」这一断言，不是 A 本身**——A 是可 trim 模型上已验证的真实杠杆。

**裁定②：append-only 复用两模型都可行且已实证**（OFF 臂 cacheEff≈0.9）——整体携带 cache 向前 append 不需要 trim。复用失败的唯一起因是**替换的 retroactive 重写**，不是模型不支持复用。

**裁定③：可 trim 模型上 A 与形态②压实可复合，且压实更便宜。** 压实不必 clear+全冷重建——可 `trimPromptCache` 回退到稳定前缀（trunk+更早 B 段）只重生压实段。GDN 模型只能 clear+重建（§3）。**产品模型选择因此是杠杆**：要低延迟替换复用，选纯注意力模型（如 Qwen3-Coder）即解锁 A；选 GDN 模型则走 clear+重建压实。归 owner 裁定。

## 3. 决定（可行核心）

**形态②：digest 接地滚动压实 + append-only 复用纪律。**

渲染前缀 = `trunk + B_k（压实段）+ 近期稳定段 + frontier`。
- **B_k 由已结算、来源校验的 digest 压实而来**（不是 raw 综合），supersede **只发生在压实边界**；两次压实之间前缀**严格 append-only**（不重写已提交字节）→ 消息级复用门通过 → 复用生效（目标模型可行，裁定②）。
- **压实事件（模型分档，裁定③）**：
  - **可 trim 模型（Qwen3-Coder 等）**：`trimPromptCache` 回退到稳定前缀（trunk+更早 B 段）→ 只重生压实段，不必全冷。与 A 同一机制复合。
  - **不可 trim GDN 模型（Ornith）**：全量 `clear()`+冷重建更小前缀（唯一释放手段；`evictInterruptedExecution` 已用官方 `clear()`，NativeMLX.swift:3306）。
  - 两档新前缀都更短 ⇒ KV（注意力层）+ 递归态重算（GDN 层，若有）都更小 ⇒ **内存封顶**，代价按 k 轮摊薄。
- **压实调度**读覆盖账本（`chat_turn_ledger` + `turn_digests` / `ISContextLedger`）判定哪些轮已 settled+digested（完成）→ 安全压实进 B_k。完成度权威是账本，不是 brief 自身。
- **触发政策（owner 2026-11-22 细化，非每轮）**：brief 是冷填重建点 ⇒ 压实只在**检查点**发生。检查点间隔由 h100 最小冷填速率（turn1 ~1100 tok/s 清洁档）在**轮次/token**上选定（`DigestPrefixCompaction.boundary` 纯函数：raw 累积字符达 `triggerChars` 或轮数达 `triggerTurns`，先到先触发）；检查点之间边界 B 固定、raw 尾部 append-only ⇒ 消息门复用（OFF 臂 0.9）；检查点处 B 跳变 ⇒ 有界 brief 前缀冷重建一次，按间隔摊薄。**故障/覆盖缺口**走有界 fail-open；**冷 prefill 预计超时**（累积前缀 × h100 速率 > deadline）由字符检查点预算体现。纯函数 ⇒ 确定性 + 跨进程可复现（无 mutable 边界态）。

### KV 释放与「内存指针」（回答 owner）
- GDN 层（30）= **固定递归态**，非逐 token KV，本就定长；「释放已完成部分」对它无意义——要压实只能从新前缀**重算**该态。
- 注意力层（10）= 逐 token KV 随前缀增长，单层可 trim，但**全层 trim 被 GDN 阻断**（裁定①）。
- 故目标模型上**释放 = clear()+重建**，不是 trim 偏移。「内存指针」= **会话 `cachedTokens` 账本 + 压实边界**（哪些 token 已压实可弃），不是 trim offset。LCP/offset 指针仅在可 trim 模型上成立。

### 三平面分离
- **brief/IS = 语义平面**：判断完成度、决定压实内容（渲染配方）。
- **cachedTokens/clear/重建 = KV 物化平面**：物理释放边界。
- brief 不充当 KV 指针图；两平面各司其职，哲学不动。

## 4. 待决设计张力（GDN 模型专属，开放问题，须实测，不空断）

**可 trim 模型（Qwen3-Coder）上此张力由 A 直接化解**：原地重写 frontier 后 `trimPromptCache` 回退到 LCP、只重生 delta，复用照常。下面三形态是**不可 trim GDN 模型（Ornith）**的设计空间——GDN 不可 trim ⇒ **任何对已缓存字节的原地重写都强制 cold**。逐轮把 frontier raw 原地换成 digest 正是这种重写。要在 GDN 模型上同时拿复用+压实，须让压实之间的前缀严格 append-only。候选形态（须 needle + cacheEff/cttft/swap/KV 内存实测择优）：
- **(a) append-only 累积 + 周期压实**：raw 轮与其 digest 都追加保留（不原地删改）→ 复用生效；压实把 raw+digest 对collapse 成 B_k（cold）。代价：压实前缀 ~2× 增长（raw 携带 IS 块，h100 internal 证明块是 ctx 墙驱动）→ 压实须够频。
- **(b) append-only 全文（OFF 臂）+ 稀压实 + IS 检索供事实**：复用已实证（0.9），不做逐轮原地替换；精确事实走 IS 检索块。压实仅在逼近 ctx 墙时触发。
- **(c) 逐轮替换 + 每轮廉价 cold**：接受每轮 cold，但压实封顶前缀使 cold 便宜（小前缀 prefill）。无复用，内存有界。

**owner 细化裁定（2026-11-22）：取触发式稀压实，非逐轮 (c)。** brief 是冷填重建点 ⇒ 每轮压实 = 每轮 cold，浪费；应在轮次/token 检查点触发（按 h100 最小冷填速率选间隔），检查点之间 append-only raw 复用（亚秒 delta），检查点处一次有界冷重建（~2–3s）按间隔摊薄。这是 (a)/(b) 的 append-only 复用 + (c) 的封顶冷重建的**复合**：平均延迟 ≈（间隔内亚秒 × (K−1) + 一次 ~2–3s）/ K ≪ 每轮 ~2–3s。故障/预计超时触发 brief 冷填兜底。实施 = `DigestPrefixCompaction.boundary` 检查点纯函数 + 渲染层 append-only 纪律（keep>0 档）。

### 实测验收杠（owner）+ 量化投影——触发式稀压实是 GDN 的清晰赢面，非 consolation

owner 杠：**压实后每轮冷填只要短于 h100 实测每轮冷填曲线即缓解**。h100 ON 臂原始读数（`runs/h50_20261122/h100_results/summary.json`，只读现取，每轮 mode=cold cacheEff=0）：

| turn | promptTokens | 冷填 promptTime | client_ttft | decode tps | swap |
|---|---|---|---|---|---|
| 1 | 2303 | 2.1s | 5.8 | 47.3 | 1.5G |
| 20 | 5590 | 8.4s | 13.1 | 31.7 | 1.6G |
| 50 | 9458 | 23.8s | 29.5 | 28.6 | 3.8G |
| 100 | 17065 | 30.9s | 35.8 | 29.0 | 2.1G |

冷填随 token 无界增长，且**预填速率随内存压力退化**：turn1 ≈ 2303/2.1 ≈ **1097 tok/s**（清洁）→ turn100 ≈ 17065/30.9 ≈ **552 tok/s**（受压）。

形态②触发式压实封顶前缀（trunk+B_k+近期 digest+检查点间 raw 窗口+frontier）**同时封顶 KV 内存 → 预填速率拉回清洁档 ~1100 tok/s**（双重收益）。投影分两档：**检查点间** append-only 复用，每轮只预填 delta（新 raw 轮 ~600–1000 tok）⇒ **亚秒**；**检查点处**冷重建有界前缀 ~2–3k/1100 ≈ **2–3s**，按间隔 K 摊薄 ⇒ 平均 ≈（亚秒×(K−1)+2–3s）/K。对照现状 2.1→30.9s 每轮全 cold 增长 → 深轮显著优于现状，T100 量级 ~10×。**GDN 上不需要 A/trim 即满足 owner 杠**（append-only 复用裁定②已实证）。brief 判未完成 digest（覆盖账本）→ 完成者压实进 B_k、未完成者保留 raw（B 有界 fail-open），天然复合。

**诚实边界**：~2–3k 前缀、~1100 tok/s 与亚秒 delta 是基于实测曲线的**投影**（turn-1 速率+封顶+append-only 复用假设），非已测。**2026-11-23 实测已修正以下投影（见下节）：检查点 ~2–3k/2–3s → 实测 ~9k/9.9s；亚秒 delta → 实测 ~2.3k tok/2.3s；T100 ~10× → 清洁同轮 2.5× + 灾难避免；检查点间隔 K=8 → 实测 ≈2.13（TRIGGER_CHARS 先触发）。投影撤回，方向（复用+封顶+速率回升）成立。**

### 实测修正（2026-11-23 perf-full-ON 同轮 100 轮验证，`runs/perf_full_on_20261122/`，只读基线 h100 ON）

臂 = 替换 ON + 触发式压实（KEEP=2 / BUDGET_CHARS=1500 / TRIGGER_TURNS=8 / TRIGGER_CHARS=6000）+ 内存池 ON / 磁盘池 OFF；KV fp16 基线（隔离压实杠杆，#333 量化另叠）。100/100 轮 digest=True，零失败。

| 档 | 轮数 | mode / cacheEff | prompt（delta/全量） | promptTime | cttft 均值 | 预填速率 |
|---|---|---|---|---|---|---|
| 检查点间复用 | 51 | prefix / 0.73–0.83 | delta ~2.3k tok | ~2.3s | **7.50s** | 983 tok/s |
| 检查点冷重建 | 49（47 次 B 跳变，间隔 ≈2.13） | cold / 0 | 均值 9048 / **封顶 10667** | 均值 9.90 / max 14.0s | **14.78s** | 934 tok/s |

**清洁同轮对照**（剔除 h100 三次 fail-open 灾难轮 t21/t31/t41）：全 100 轮 2.06×（78/97 胜）；≥20 轮 2.30×（71/78）；≥40 轮 **2.52×（59/60）**；≥60 轮 **2.57×（41/41 全胜）**。检查点轮对 h100 清洁同轮 t≥10 胜 31/42，~t45 后基本全胜。**owner 杠（每轮冷填短于 h100 同轮曲线）深轮达标。**

**最大赢面 = 灾难避免 + 内存封顶**：h100 ON 臂前 41 轮三次 fail-open 渲染全文（t21 69k tok/300.7s、t31 99.5k/596.8s、t41 129.9k/971.7s 客户端超时 FAILED），合计 ~1869s 预填浪费 + 一次失败；perf-full **零灾难**，前缀封顶 10667 不随轮数增长。swap 峰值 1805MB（稳态 1038）vs h100 5641MB。预填速率 934–983 tok/s 回清洁档（h100 t100 退化至 552）——「封顶 KV → 速率回升」双重收益投影**证实**。

**检查点成本根因（投影 ~2–3s 落空）**：检查点渲染 `brief(1..B-keep)+digest(B-keep+1..B)+raw(B+1..frontier)`，B=covered−keep ⇒ **最近 keep=2 个已覆盖轮仍按 raw 渲染**（各携 IS 检索块 ~2k tok）+ 当前轮新 IS 块 ⇒ ~9k tok。压实只折叠 digest 链 t1..B-keep，raw 尾部块不动。TRIGGER_CHARS=6000 在 ~2 轮即触发（先于 TRIGGER_TURNS=8）⇒ 摊薄 K≈2 非 8。

**needle 双轨质量门（冷重启后）——未过**：
- internal（全文无块，62.3k tok）：**28/29**（丢 QC-2027-103，深上下文模型召回 variance；internal 不经过压实，非压实损失）。
- normal（替换+压实+IS 块，7.1k tok）：**7/29 ≪ ≥27/29 杠，FAIL**。
- 机制定案（读注入块 payload + digest 库现取）：① 压实把 96 轮 digest 折成 1500 字**叙事** brief，精确编码退出渲染前缀；② IS 块是**行级词法 echo**（30 items 仅含 4/29 键：旧 needle 答案散行 + 问句 echo + 脚本源码行），补不上精确事实表；③ 模型以**标准默认值幻觉**填空（C50/160/96%/0.32/3%/365）+ 格式似真码（JL-2027-301/GD-5103/ZJ-2027-301/JC-2027-401）+ 相似字段混淆（QC-2027-101↔QC-2027-103）。**伪造来自模型先验，非 digest/brief 伪造**（印证 owner 判断：digest 丢精确细节、不伪造细节；但前缀缺事实时产品级答案仍错）。
- **digest 链本身逐字保留 24/29 键**（库现取；缺 MS-2027-302/PC-2027-556/TS-2027-202/QC-2027-103/RJ-2027-203 = digest 生产阶段损失，先于压实存在，h100 normal 亦丢 2 键）。h100 normal 27/29 主要靠完整 digest 链携键，非块通道。

**修复杠杆（待 owner 裁定，ponytail 排序）**：
1. **键锚定 brief（生产者侧，最小）**：brief 逐字保留 settled digest 的 key:value 行（24 键 ≈500 字， fits BUDGET_CHARS=1500），仅压叙事。渲染/引擎平面不动、模型无关。预期质量地板 ≈ digest 链自身保留率（24/29）+ 块贡献，逼近 h100 normal 27/29。剩余 5 键 = digest 生产损失（D 平面，另件）。
2. **检查点降本**：检查点处把 keep 个已覆盖轮按 **digest**（非 raw）渲染 ⇒ 检查点前缀 ~9k→~5k（pTime ~9.9→~5s）；和/或封顶 IS 块尺寸。与杠杆 1 复合。
3. IS 值感知检索（语义平面，大改，延后）；增大 BUDGET_CHARS（部分、仍叙事有损）；不压 digest 链只压 raw 块（回退链增长，弃）。

**裁定**：性能杠杆真实有效（深轮 2.5× + 灾难避免 + 内存封顶），但**当前叙事 brief 形态过不了质量门**——触发式压实臂在旧键召回上等价于 §7 降级的「纯 brief 质量地板」。产品默认不提升；键锚定 brief 是保住性能赢面同时过门的最小改法。

 ponytail：复用现有消息门 + `trimPromptCache`（可 trim 模型，A）/ `clear()`（GDN 模型，evict 路已证）；新代码仅 LCP 计算（可 trim 档）+ 压实调度 + digest→brief 生产 + append-only 渲染纪律（GDN 档）。**不做 paged/refcount KV 块管理器**（那是跨请求前缀共享轴=多会话吞吐，非单会话深度内存，延后）。

## 5. 质量护栏

digest 逐轮、来源校验、append-only；brief 跨轮综合（丢细节更多、有伪造风险）。h100 normal 臂已丢 PC-2027-556/JK-2027-309（历史与块均不含）。B_k 由**已校验 digest** 压实（非 raw 综合）降一档伪造风险，仍须过 **needle 双轨（internal+normal+块分解）** 才能产品化。IS 检索块是精确事实通道，但覆盖缺口已实测（h50 反馈通道审计），不假设兜底一切。

**2026-11-23 实测护栏结果（perf-full-ON 100 轮）**：normal **7/29 FAIL**（杠 ≥27/29），internal 28/29。叙事 brief 丢精确键 + IS 块行级词法 echo 仅 4/29 键 ⇒ 模型默认值幻觉。**「精确事实走 IS 块」（形态 b 假设）实证不足**——当前词法行级检索不能充当 29 键精确事实表。digest 链逐字保留 24/29 键 ⇒ **键锚定 brief（逐字留 key:value、仅压叙事）是过门最小杠杆**（§4 实测修正）。产品化门前不提升默认。

## 6. 先例（降为可行性注脚，非性能动机）

`prefixDiffLine` 注释「token 级 LCP 待接入 tokenizer」、`toolEchoNormalize`（NativeMLX.swift:2062，2026-10-15 批准）、磁盘池 token 域（`NativeMLXPrefixPool.swift:263-272`）——这些是**连续性契约可以是 token 粒度的起始证据（研究可行性）**，不是性能首选；且其 trim 前提在目标模型不成立（裁定①）。**撤「统一 live-session 与 pool 粒度」目标**（磁盘池永久 OFF）。#335 跨进程可复现 = 研究完整性，T4 已验收，完成态。

## 7. 安全 / 边界

- 三平面不动；IS 语义准入（resolve/reusableAnswer）不改；权威行不动。
- fail-open：压实产物缺失/损坏/账本不连续 → 退回今日渲染（B 有界 fail-open 已实施），绝不渲染错内容。
- 量化 KV 叠加：#333 量化减注意力层 KV 字节，与压实（封顶前缀）正交相乘；kvFingerprint 门不变。
- 产品默认不变：替换旗标 OFF、内存池 ON / 磁盘池 OFF。
- 不做 IS 渲染全量解耦 / 账本移除；C（deadline 调度）/D（生产成本）延后；纯 brief①（每轮重写整段）降为研究臂量质量地板，非产品主干（supersede 每轮 ⇒ 仅 trunk 复用，与「增加前缀量」目标相悖）。

## 8. 验证（实验 1 先跑、实验 2 随后——owner 2026-11-22 裁定）

**已实施（本 PR）**：形态②**触发式**压实 = 纯渲染层、模型无关、**引擎零改动**。三平面解耦：
- 生产者 + 触发政策 `SimiGo/Protocol/DigestPrefixCompaction.swift`：`brief(...)` 纯函数（settled digests → 一条有界 brief，可换模型合成 brief 生产者）；`boundary(rawTurnChars:triggerChars:triggerTurns:)` 纯函数（检查点触发政策，确定性 + 跨进程可复现，无 mutable 边界态）；
- 渲染政策 `HTTPServerChat.digestSubstitutedMessages`：keep>0 档按检查点边界 B 渲染 `brief(1..B-keep)+digest(B-keep+1..B)+raw(B+1..frontier)`；**检查点之间 B 固定、raw 尾部 append-only ⇒ 消息门复用**；检查点处 B 跳变 ⇒ 有界冷重建；B=0（未到检查点）退回原始 append-only raw（OFF 臂形态）。keep=0（默认）= 逐轮完整链，与 B 逐字节一致；账本门 + fail-open 不变；
- 引擎/KV 不动：GDN 检查点间走消息门 append-only 复用、检查点处冷重建更小前缀；可 trim 模型的 token-LCP 复用是另件（A，实验 2）。

旋钮（计算属性读 env，与替换旗标同型，测试可逐例切换；仅 substitution=1 生效）：`SIMIGO_DIGEST_COMPACTION_KEEP`（默认 0=关）、`SIMIGO_DIGEST_COMPACTION_BUDGET_CHARS`（默认 1500）、`SIMIGO_DIGEST_COMPACTION_TRIGGER_TURNS`（默认 8 轮检查点）、`SIMIGO_DIGEST_COMPACTION_TRIGGER_CHARS`（默认 6000 字符检查点，token 代理，先到先触发）。契约测试 16/16（含检查点纯函数稳定/跳变、字符触发、未到检查点 append-only raw、检查点处封顶前缀渲染）。

**实验 1（先跑）：GDN 触发式压实 A/B**——验证 §4 投影（检查点间亚秒复用 + 检查点 ~2–3s 冷重建摊薄）。归研究窗执行（实施窗不装机不重启）：

**结果（2026-11-23，本窗 owner 授权装机跑）：性能杠达标、质量门未过。** 复用 51 轮 cttft 7.50s / 检查点 49 轮 14.78s（封顶 10667 tok）；清洁同轮 ≥40 轮 2.52×、≥60 轮 2.57×；零 fail-open 灾难（h100 三次）；swap 1805 vs 5641MB；预填 934–983 tok/s 回清洁档。needle internal 28/29、normal **7/29 FAIL**。投影修正 + 机制 + 键锚定 brief 杠杆见 §4 实测修正、§5。**产品默认不提升。** 检查点间隔敏感性（TRIGGER_TURNS 4/8/16）与键锚定 brief A/B 待 owner 裁定后续跑。
1. 构建 main+#334 装机（owner），`ab_restart.sh` env：substitution=1 + KEEP=2 + BUDGET_CHARS=1500 + TRIGGER_TURNS=8 + TRIGGER_CHARS=6000（内存池 ON / 磁盘池 OFF 不变）。
2. 复用 h100 回合脚本（fresh session；needle 键换新码防语料污染）；基线 = 既有 h100 ON 臂曲线（同脚本同机，不重跑）。
3. 逐轮记 promptTokens / promptTime / **mode（prefix vs cold）/ cacheEff** / cttft / tps / swap / **KV+递归态内存**。预期：检查点间 mode=prefix、cacheEff>0、亚秒 delta；检查点处 mode=cold、~2–3s；前缀封顶、预填速率回 ~1100 tok/s、swap 不随轮数增长。**关键验证：检查点间消息门是否真过（append-only raw 复用）**。
4. 深轮后冷重启 needle 双轨（internal 全文无块 + normal）+ 事后块分解。先 40 轮 pilot，通过再全 100。质量预期：normal 臂 ≥27/29 基线（精确事实走 IS 块）；internal 臂量化旧键压实损失（诚实 tradeoff，如实报）。
5. 验收杠（owner）：深轮每轮延迟短于 h100 同轮实测（检查点间亚秒、检查点 ~2–3s，平均显著低于现状增长曲线）；needle 不塌。检查点间隔敏感性（TRIGGER_TURNS 4/8/16）可选，延后。

**实验 2（A 杠杆引擎已实施，待 A/B）：可 trim 模型 fork 复用 A/B**——目标模型 Qwen3-Coder-30B-A3B-4bit（本地已备，qwen3_moe 48 全注意力，可 trim）。

**模型前提（现取核实）**：当前产品 ModelPath = Nail-Qwen3.6-35B-A3B-MLX（qwen3_5_moe，text_config 40 层 = 30 linear_attention(GDN) + 10 full_attention，MambaCache×30 ⇒ `canTrimPromptCache=false` ⇒ `maxTrimCount=0`），与 Ornith 同族，**不可 trim**。A 杠杆只在可 trim 模型上产生 trim；在 GDN 上引擎内部 `maxTrimCount=0` 门自动回退 rebuild（不硬编码模型族）。故实验 2 须切到 Qwen3-Coder 跑，GDN 上跑给空结果。产品目标模型是否切换由 A/B 数据裁定（owner）。

**机制（复用依赖现成公共 API，非新造 KV 管理器）**：`ChatSession.fork(history:)`（mlx-swift-lm，SimiGo-patched rev 86e0c63）拷贝暖 KV（COW）+ 替换转录 + `transcriptBuiltCache=false`；下一轮渲染重写 prompt，内部 `PromptCacheReusePolicy` 按 token-LCP 裁定——`RewindToCommonPrefixRule` 计算 `zip(promptTokens,cachedTokens).prefix{==}.count`，`trimCount=cachedTokens.count-LCP`，门 `trimCount<=maxTrimCount && mainCacheIsAligned && 无媒体/mask/state` ⇒ 可 trim 模型 `trimToCommonPrefix` 只预填分叉尾巴；GDN `maxTrimCount=0` ⇒ 回退 rebuild。账本对齐：生成后 `record()` 把 `cachedTokens` 重基为 prompt+已提交生成 token，`processedTokenCount==cachedTokens.count` 成立，fork 保留两者 ⇒ 对齐保持。媒体/无转录态由 fork 自身回退 `.history` 冷路径，行为等价旧冷重建。

**接线（NativeMLX，与渲染层压实解耦）**：reuseMiss else 分支增 `else if RuntimeTuning.trimReuseEnabled && existing && incoming.count>existing.history.count && kvFingerprint 匹配` → `fork(history: incoming.dropLast())`，`managed.history=重写前缀`、`reusedSession=true`、`trimForkedTurn=true` ⇒ delta=[末条]（fork 内部转录=重写前缀，渲染=完整 incoming，无 system 重复，写回 `incoming+[assistant]` 与内部转录同步）。`trimForkedTurn` 跳过 Phase B 消息级 rollforward（引擎 token-LCP/checkpoint 政策已原生对账）。观测：`noteTrimFork()` 计数 + trace；mode 派生增 `trimForkedTurn && 0<cached<total → "rewind"`（路由事实 + 官方读数，非补造上游 mode 字符串；fork 回退 rebuild 时 cached<=0 归 "cold"）。旗标 `SIMIGO_TRIM_REUSE`（计算属性，默认 OFF，逐例可切换）。

**A/B 设计**：同机同脚本同回合，Qwen3-Coder 上 A 臂 `SIMIGO_TRIM_REUSE=1`（fork→trim）vs B 臂 OFF（现行冷重建），叠加替换 ON + KEEP=2 + 触发式压实 + 键锚定 brief。逐轮记 mode（rewind vs cold）/ cacheEff / cachedPromptTokens / promptTime / cttft / tps / swap / KV 内存。验收假设：reuseMiss 轮 A 臂 mode=rewind、cacheEff>0、delta 预填亚秒（brief 稳定前缀越长 LCP 越深）；B 臂 mode=cold。对照实验 1 GDN 基线（复用 cttft 7.50s / 检查点 14.78s）。needle 双轨复验键锚定 brief（internal + normal，杠 ≥27/29）。**引擎改动本 PR 实施（旗标门控默认 OFF，产品行为不变），A/B 归研究窗装机跑。**

**契约级**：检查点触发纯函数（稳定/跳变/字符/禁用）、压实渲染有界/确定性、未到检查点 append-only raw、fail-open（账本缺口 → B/完整链）、keep=0 与 B 逐字节一致——本 PR 测试已覆盖。

## 9. 影响范围（已实施部分）

- `SimiGo/Protocol/DigestPrefixCompaction.swift`（新）：压实生产者 `brief` + 触发政策 `boundary`，均纯函数，与渲染/引擎解耦。
- `SimiGo/Protocol/HTTPServerChat.swift`：`digestSubstitutedMessages` 内触发式压实分档（检查点间 append-only raw 复用 / 检查点处封顶冷重建；承 B 的账本门 + fail-open）。
- `SimiGo/Protocol/DigestPrefixCompaction.swift`：`brief()` 截断时前置「事实锚点（逐字保留）」——`factPattern` 正则从全部 digest 抽编号/牌号/数值+单位，去重保序，锚点有界 + 叙事前缀填充（键锚定 brief，修复叙事 brief 丢精确键）。
- `SimiGo/Lifecycle/RuntimeTuning.swift`：四个压实研究旋钮（KEEP/BUDGET_CHARS/TRIGGER_TURNS/TRIGGER_CHARS）+ `trimReuseEnabled`（SIMIGO_TRIM_REUSE，A 杠杆研究旗标，默认 OFF），均计算属性。
- `SimiGo/Inference/NativeMLX.swift`：reuseMiss 增 trim-fork 分支（`fork(history:)` 接暖 KV 到重写转录，引擎 token-LCP trim）；`trimForkedTurn` 守卫 Phase B rollforward；mode 派生增 "rewind"。**消息级复用门（reuseHit append）维持不变**；trim-fork 仅旗标 ON 启用。
- `SimiGo/Inference/NativeMLXObservation.swift`：`trimFork` 计数 + `noteTrimFork()` + snapshot `trim_fork` 事件。
- `SimiGoTests/DigestPrefixSubstitutionTests.swift`：18/18（+键锚定 brief 保留晚轮事实 + 产品默认替换 ON 守卫；setUp 显式 OFF 基线与产品默认解耦）。EngineIdentityLedgerTests 8/8。
- **产品默认**：替换 **ON**（owner 2026-11-23，env=0 可关）/ 压实 KEEP=0（质量门未过不提升）/ 内存池 ON / 磁盘池永久 OFF / A 杠杆 SIMIGO_TRIM_REUSE 默认 OFF（研究对照）。
- 研究地图：两模型 trimmability 裁定 + 压实形态实测补进 `docs/research/es-is`（研究窗）。
