# ADR：digest 接地滚动压实（形态②）+ 前缀复用——目标模型可行性裁定（2026-11-22）

**状态：提案（owner 2026-11-22 认可形态②方向；引擎改动待实施裁定）。**
本 ADR 经目标模型现取核实后**重写**：原「token 级 LCP 截断复用（A）」主杠杆判断**已撤回**——目标模型不可 trim（见 §2）。可行核心改为**形态②滚动压实 + append-only 复用纪律**。
驱动证据：`ES-IS-research` Spike A #4（063C118B）h100/h50 双臂 trace；根因注记 35ADB7F2；owner 裁定（形态②、磁盘池永久 OFF、物化证据已完成）。

## 1. 问题（实证）

替换 ON 臂**每轮全 cold**：h100 100/100 轮 `mode=cold cacheHit=0 cacheEff=0.0`；T100 cttft 35.8s 中 cold prefill 30.9s（87%）。OFF 全文臂 `mode=prefix cacheEff≈0.9`（h50 off turn8 cacheHit=21936；`mlx_metrics` 合并 chat+digest 两条 [MLX] 行 last-wins，精确值须原始 trace 复核）。双臂 digest 同引擎跑 → digest 交错不是 cold 的原因。

根因：同会话复用门 `NativeMLX.swift:2050` `Self.isPrefix` 是**消息级**严格前缀（`messagesMatchForReuse` :3964）。替换把第 N-1 轮 frontier 从 raw **retroactive 重写**成 digest → 边界消息不匹配 → `reuseMiss prefix=false`（:2080）→ 每轮 cold。**内存不连续是结构性的（连续性契约粒度），不是调度时机。**

两个目标（owner）：**延迟**（少 cold prefill）+ **内存**（KV/递归态封顶，治本机 swap 压力）。物化证据已完成（#333 量化 KV round-trip + #335 T4 跨进程 bind）；此后 KV 工作只在「增加可复用前缀量」意义上有价值。**磁盘池永久 OFF**（`RuntimeTuning.prefixPoolEnabled` 默认 OFF；#335 持久快照门控其上 → 产品零开销，纯研究装置）。

## 2. 目标模型可行性裁定（现取，决定性）

目标 MLX 模型 = `ornith-ai--Ornith-1.5-35B-A3B-MLX-4bit`（`SelectedModelPath` 现取），`model_type=qwen3_5_moe`，text 40 层 `layer_types` = **30× linear_attention（GDN）+ 10× full_attention**（`full_attention_interval=4`、`linear_conv_kernel_dim=4`、`mamba_ssm_dtype`）。

代码铁证（`.../mlx-swift-lm/Libraries/MLXLLM/Models/Qwen35.swift:1235-1244` `newCache`）：
```swift
if layer.isLinear { return MambaCache() }
// Full-attention layers honor maxKVSize; GDN / linear layers keep
// a fixed recurrent state that cannot be token-windowed.
```
- `MambaCache: ArraysCache: BaseKVCache`，`isTrimmable=false`（KVCache.swift:299，MambaCache 无 override）；`trim` 返回 0。
- `canTrimPromptCache = cache.allSatisfy { $0.isTrimmable }`（KVCache.swift:2750）→ 30 层 GDN 不可 trim ⇒ **整模型不可 trim**。
- 与 `NativeMLX.swift:3290` 取消路注释自证一致：「生产模型（30× GDN 递归层）上 isTrimmable 为 false」。

**裁定①：原 A（token-LCP 截断到共享前缀、只预填 delta）在目标模型上不可行。** `trimPromptCache`（KVCache.swift:2763）/ `ChatSession.record()` 取消路 trim（ChatSession.swift:268-313）机制存在且对纯注意力模型有效，但 GDN 递归态是**固定状态、不能 token-window**，无法回退到 LCP。token-LCP 截断降级为**仅适用于可 trim 的纯注意力模型的条件优化**，不是目标模型路径。

**裁定②：append-only 复用在目标模型上可行且已实证**（OFF 臂 cacheEff≈0.9）——整体携带 cache（递归态+注意力 KV）向前 append 不需要 trim。复用失败的唯一起因是**替换的 retroactive 重写**，不是模型不支持复用。

## 3. 决定（可行核心）

**形态②：digest 接地滚动压实 + append-only 复用纪律。**

渲染前缀 = `trunk + B_k（压实段）+ 近期稳定段 + frontier`。
- **B_k 由已结算、来源校验的 digest 压实而来**（不是 raw 综合），supersede **只发生在压实边界**；两次压实之间前缀**严格 append-only**（不重写已提交字节）→ 消息级复用门通过 → 复用生效（目标模型可行，裁定②）。
- **压实事件 = 全量 clear()+冷重建更小前缀**（目标模型不可 trim，唯一释放手段；`evictInterruptedExecution` 已用官方 `clear()`，NativeMLX.swift:3306）。新前缀更短 ⇒ KV（10 注意力层）+ 递归态重算（30 GDN 层）都更小 ⇒ **内存封顶**。代价按 k 轮摊薄。
- **压实调度**读覆盖账本（`chat_turn_ledger` + `turn_digests` / `ISContextLedger`）判定哪些轮已 settled+digested（完成）→ 安全压实进 B_k。完成度权威是账本，不是 brief 自身。

### KV 释放与「内存指针」（回答 owner）
- GDN 层（30）= **固定递归态**，非逐 token KV，本就定长；「释放已完成部分」对它无意义——要压实只能从新前缀**重算**该态。
- 注意力层（10）= 逐 token KV 随前缀增长，单层可 trim，但**全层 trim 被 GDN 阻断**（裁定①）。
- 故目标模型上**释放 = clear()+重建**，不是 trim 偏移。「内存指针」= **会话 `cachedTokens` 账本 + 压实边界**（哪些 token 已压实可弃），不是 trim offset。LCP/offset 指针仅在可 trim 模型上成立。

### 三平面分离
- **brief/IS = 语义平面**：判断完成度、决定压实内容（渲染配方）。
- **cachedTokens/clear/重建 = KV 物化平面**：物理释放边界。
- brief 不充当 KV 指针图；两平面各司其职，哲学不动。

## 4. 待决设计张力（开放问题，须实测，不空断）

目标模型不可 trim ⇒ **任何对已缓存字节的原地重写都强制 cold**。逐轮把 frontier raw 原地换成 digest 正是这种重写。要在目标模型上同时拿复用+压实，须让压实之间的前缀严格 append-only。候选形态（须 needle + cacheEff/cttft/swap/KV 内存实测择优）：
- **(a) append-only 累积 + 周期压实**：raw 轮与其 digest 都追加保留（不原地删改）→ 复用生效；压实把 raw+digest 对collapse 成 B_k（cold）。代价：压实前缀 ~2× 增长（raw 携带 IS 块，h100 internal 证明块是 ctx 墙驱动）→ 压实须够频。
- **(b) append-only 全文（OFF 臂）+ 稀压实 + IS 检索供事实**：复用已实证（0.9），不做逐轮原地替换；精确事实走 IS 检索块。压实仅在逼近 ctx 墙时触发。
- **(c) 逐轮替换 + 每轮廉价 cold**：接受每轮 cold，但压实封顶前缀使 cold 便宜（小前缀 prefill）。无复用，内存有界。

 ponytail：先复用现有消息门 + `clear()`（evict 路已证），新代码仅压实调度 + digest→brief 生产 + append-only 渲染纪律。**不做 trim 工程（目标模型用不上）、不做 paged/refcount KV 块管理器**（那是跨请求前缀共享轴=多会话吞吐，非单会话深度内存，延后）。

## 5. 质量护栏

digest 逐轮、来源校验、append-only；brief 跨轮综合（丢细节更多、有伪造风险）。h100 normal 臂已丢 PC-2027-556/JK-2027-309（历史与块均不含）。B_k 由**已校验 digest** 压实（非 raw 综合）降一档伪造风险，仍须过 **needle 双轨（internal+normal+块分解）** 才能产品化。IS 检索块是精确事实通道，但覆盖缺口已实测（h50 反馈通道审计），不假设兜底一切。

## 6. 先例（降为可行性注脚，非性能动机）

`prefixDiffLine` 注释「token 级 LCP 待接入 tokenizer」、`toolEchoNormalize`（NativeMLX.swift:2062，2026-10-15 批准）、磁盘池 token 域（`NativeMLXPrefixPool.swift:263-272`）——这些是**连续性契约可以是 token 粒度的起始证据（研究可行性）**，不是性能首选；且其 trim 前提在目标模型不成立（裁定①）。**撤「统一 live-session 与 pool 粒度」目标**（磁盘池永久 OFF）。#335 跨进程可复现 = 研究完整性，T4 已验收，完成态。

## 7. 安全 / 边界

- 三平面不动；IS 语义准入（resolve/reusableAnswer）不改；权威行不动。
- fail-open：压实产物缺失/损坏/账本不连续 → 退回今日渲染（B 有界 fail-open 已实施），绝不渲染错内容。
- 量化 KV 叠加：#333 量化减注意力层 KV 字节，与压实（封顶前缀）正交相乘；kvFingerprint 门不变。
- 产品默认不变：替换旗标 OFF、内存池 ON / 磁盘池 OFF。
- 不做 IS 渲染全量解耦 / 账本移除；C（deadline 调度）/D（生产成本）延后；纯 brief①（每轮重写整段）降为研究臂量质量地板，非产品主干（supersede 每轮 ⇒ 仅 trunk 复用，与「增加前缀量」目标相悖）。

## 8. 验证（实施时）

- 契约级：压实调度账本门、B_k digest 接地、append-only 渲染纪律（压实间无原地重写）、fail-open。
- 真机 A/B（研究模式）：§4 三候选形态对照，量 cacheEff / cttft / swap / **KV+递归态内存** / needle 双轨。
- 模型覆盖：可 trim 纯注意力模型上验证 token-LCP 条件优化（裁定①的另一半）；目标 GDN 模型上验证 clear+重建压实。

## 9. 影响范围

- `SimiGo/Protocol/HTTPServerChat.swift`：append-only 渲染纪律 + 压实边界（承 B 的 `digestSubstitutedMessages`）。
- 压实调度器 + digest→brief 生产（新件，digest 接地）。
- `SimiGo/Inference/NativeMLX.swift`：复用门维持消息级（目标模型 append-only 即过）；clear+重建走 evict 既有路；token-LCP 档位仅可 trim 模型条件启用。
- 研究地图：目标模型 trimmability 裁定 + 压实形态实测补进 `docs/research/es-is`。
