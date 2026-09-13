# 现场观察：90K 长上下文 Agent 任务全程（2026-09-13）

- **环境**：SimiGo v1.2（commit `7831331` Release 构建，tag 同步），Nail-Qwen3.6-35B-A3B-MLX / Cyber-Tiel-Coder-35B-A3B-MLX-oQ4e，32GB 工作机（日常并发负载常驻）。
- **对象**：小说续写 agent 任务（会话 `06c88f` / trace key `c5c335/main`），前端 ZCode 类 CLI。
- **时间**：2026-09-13 05:13:15 → 08:06:10（约 2h53m），上下文 465 → 90,925 token。
- **结论**：任务完成 ✅。全部当日修复（取消不提交、阶梯选档、自适应闲置超时、UI 参数兜底、swap 修正）实战零失败；最大成本项确认为 **cacheEff=0.00 全量重预填轮（13/28 轮，46%，约占 wall time 六成）**。

## 1. 任务画像

| 指标 | 值 |
|---|---|
| 请求 / 完成轮 / 客户端放弃 | 34 / 28 / 6 |
| 结束方式 | 最终文本答复 1,820 字节（`rawEv=524 rawB=1,820`，无工具调用）|
| 上下文增长 | 465 → 90,925 token（每轮 +0.4k~66k 不等）|
| 单轮耗时分布 | 17s（暖命中）→ 781s（冷预填幸存）|

全部 6 次客户端放弃均经 `cancelCommitSkip` 干净收敛：history 稳定（无一次毒化）、无级联死亡、**全程零崩溃（Release）**、零重连堆积。

## 2. 阶梯选档实战验证

| 轮次场景 | 档位 | 实测 |
|---|---|---|
| 465 token 首轮 | 2048 | 单前向直出 |
| 16,331 冷预填 | 2048 | **767 tok/s**（512 基线的 4 倍）|
| 43,607（16k 缓存上）| 2048 | 438 tok/s |
| 66,957（跨过 96k 线）| **自动降 512** | 250 tok/s，整轮 385s 存活 ✓ |
| 84,321 重试 | 1024（64-96k 档）| ~200-250 tok/s |

选档按每轮重估自动切换，位置衰减曲线（385→236→167→112→86 tok/s）与阶梯设计一致。

## 3. 核心发现：cacheEff=0.00 全量重预填（P1 级成本项）

28 轮中 13 轮 `cacheEff=0.00`（官方缓存零命中，整段上下文全量重预填），10 轮部分命中，5 轮全命中。13 轮未命中的重复预填 ≈ 任务 wall time 的六成。

**序列**（均有完整 trace）：暖命中健康段 → 71c386 起连续 4 轮零命中（db0573/b40f19 仅 ~60 token delta 也未命中）→ 53d730 自愈（cacheEff 0.99，缓存内容未损）→ 6ce365 又未命中 → f98f48 命中 → ad2d42 起再入未命中段。

- 与 delta 大小、KV 位置、并发均无相关（66k delta 与 60 token delta 都出现过未命中/命中）。
- 未命中轮的重复预填按 ~160-250 tok/s（512 档）进行，成本随上下文线性放大：69k≈330s、76.8k≈475s、89.5k≈677s。
- **上游复现包**：mlx-swift-lm（`238ad74`）ChatSession 官方缓存；trace 关键字 `cacheEff=0.00` + `prefill X/Y` 序列，时间窗 05:19-08:06。qwen3_5_moe 混合架构（GDN + 滑窗全注意力）。

## 4. 次级发现

1. **取消后缓存回滚**：预填中途被取消的轮次，其重试从 0 重新预填（官方会话缓存未保留部分进度；今晚 3/3 例）。例外：03:07 一例曾从 60,705 续跑。同属上游观察；SimiGo 侧行为正确（取消不提交、重试完整重算）。
2. **客户端耐心非硬 600s**：601-635s 被弃与 631/671/781s 存活并存，浮动机制在前端侧。SimiGo 侧对应策略已就位：轮次超时后重试可续（毒化已除）。
3. **新会话第 2 轮 index=0 system 不匹配**：客户端 system 消息内容在第 1→2 轮间变化 → 该轮全量重预填（行为正确：语义变化必须重算）。若客户端每轮注入动态 system 内容则会话永不复用——本任务未受影响（system 稳定），列为客户端侧注意事项。
4. **自适应闲置超时首触发** ✓：任务结束 08:06:10，`suspend_done` 08:17:43（= 最后活动 + 89,450/150+60s ≈ 656s 容忍 + 30s 健康循环粒度），~21GB 释放给日间工作。

## 5. 对 5.1 优先级的影响

1. **缓存稳定性（cacheEff=0.00 根因）** —— 升为第一优先。若 13 轮未命中转化为命中，本任务 wall time 约 -50%；收益大于其他任何单项。
2. 上下文压缩/摘要（本任务 90k 中大块为已归档章节正文）。
3. 上游 two-pack：运行中自适应步长；取消后缓存回滚语义。

## 6. 观测基建状态

本轮全部结论来自已入库的可观测设施：`[MLX] prefill X/Y` 进度行、`rawEv/rawB/emitB`、`reuseMiss` 三判据、`cancelCommitSkip`、xsw_usage swap 遥测。无新增机制需求。

## 7. 附录：cacheEff=0.00 的代码级根因（上游报告基础，2026-09-13 补）

对 `mlx-swift-lm@238ad74` 源码逐行核对，根因链完整闭合：

1. **复用决策**（`PromptCacheReusePolicy.swift`）：规则序 = 协议规则 + `ExtendCachedPrefixRule`（严格扩展→`appendSuffix`）+ `RewindToCommonPrefixRule`（分叉→回卷复用，终局规则）。
2. **回卷门槛**（`RewindToCommonPrefixRule.canRewind`）：要求 `commonPrefix>0 && trimCount>0 && mainCacheIsAligned && draftCacheIsAligned && isTrimmable && 无 media/attentionMask/modelState`。任一不满足 → `.rebuild`（全量重预填，零命中）。
3. **qwen3.5 混合架构命中死穴**：`KVCache.swift:233` 基类 `isTrimmable` 默认 `false`，仅 KVCacheSimple/Quantized/Rotating 等标准 KV 子类覆写 true；GDN（GatedDeltaNet）递归状态层不可回卷 → 会话复合缓存 `isTrimmable=false` → **任何与已缓存 token 前缀的分叉都必然 rebuild**。
4. **分叉来源**：上一轮生成的 token 账本（含响应协议私有 token）与下一轮冷模板重渲染不可能逐 token 复现——assistant 回显/工具结果边界必然分叉。工具结果内容形态决定分叉幅度。
5. **观测-代码对应**：cacheEff=0.99 轮 = 严格扩展（`appendSuffix` 无 isTrimmable 门槛，GDN 状态自然前滚）✓；cacheEff=0.00 轮 = 渲染分叉 → 回卷被拒 → rebuild ✓；60-token delta 也 miss ✓（分叉与 delta 大小无关）；TodoWrite 轮倾向命中（其回显重渲染逐 token 稳定）✓；自愈 = 分叉消失后恢复严格扩展 ✓。与上游 mlx-lm #980（混合架构 prefix reuse 退化）同类，Swift 侧等价现象。

**结论**：SimiGo 侧无缺陷、无可安全本地修复项（回卷 GDN 状态会产生错误输出，引擎拒绝回卷是正确行为）。修复方向在上游：GDN 状态检查点回卷、或 qwen3.5 协议拼接规则（`isToolResultContinuation` 拼接）。SimiGo 侧唯一有效缓解 = 控制会话上下文规模（分叉 rebuild 的代价与上下文线性相关）。

## 8. 附录二：rebuild 触发时点与工具类型的相关性（2026-09-13 补，生产数据）

任务会话 ddc444（16:37-17:26，22 轮）的「上一轮工具 → 下一轮 cacheEff」对齐：

| 上一轮工具 | 下一轮 cacheEff | 样本 |
|---|---|---|
| Bash | 0.93/0.93/0.99/0.85/0.94/0.89/0.96/0.96 | 8/8 命中 |
| AskUserQuestion（3KB 中文）| 0.99 | 1/1 命中 |
| **TodoWrite** | **0.00 / 0.00** | **2/2 全量 rebuild** |

**机制链（代码级）**：`JSONValue.object` 存储为 `[String: JSONValue]` **无序字典**（Value.swift:14）→ 工具调用参数 round-trip（生成 JSON → 解析 → 模板重渲染再编码）**多键对象键序不稳定** → token 前缀在该 assistant 消息处分叉 → GDN 不可回卷 → 全量 rebuild。单键对象（Bash 的 `command`）键序平凡稳定 → 严格扩展命中。

- 与 GDN 根因（§7）复合：分叉不可避免（键序）× 不可回卷（GDN）= rebuild。
- TodoWrite 参数为嵌套多键对象数组（计划列表），命中概率最低；Bash 单键参数最稳。
- 上游修复方向补充：ToolCall arguments 的 round-trip 保序（有序存储或规范化渲染）。
- 排障口诀：**rebuild streak 的起点 = 第一次出现「多键参数工具调用」的轮次**。

## 10. 附录四：真实事件心跳的生产证伪 + 渲染层确定性排序（2026-09-13 深夜补）

**7da320e（makeEvent 真实事件心跳）生产证伪**：16:34 实例（用户自移 16:25 构建入 /Applications，含 makeEvent）运行下，前端照样放弃 4 轮：17:07:52（601s，rawEv=14 rawB=60——解码已有产出仍被弃）、17:18:25（660s，rawEv=0）、17:33:05（676s，rawEv=0）、17:44:08（600s，rawEv=0）。**结论：前端放弃触发既不看字节、也不看协议内事件——只认真实内容产出或任务完成；阈值机制在前端 agent 层，非用户可配置，机制未明（需前端侧日志/源码定位）。** 7da320e 保留（对字节/代理级看门狗仍有效），但对本前端无效。

**渲染层确定性排序（swift-jinja 源码，Value.swift:63）**：`[String: any Sendable]` → Jinja ObjectKey 转换**强制按键字母序排序**（`dict.sorted(by: { $0.key < $1.key })`）。因此：
- L3 重渲染实际是**确定性字母序**，不是「字典随机序」——修正 §8 的表述；
- 由此 **方案 A（保序存储）穿透不了 Jinja 边界**：即便 ToolCall 保序，转换层仍强制字母序；
- 分叉的结构性本质 = **账本（模型自由序生成 token）vs 渲染（确定性字母序）** 的不可调和——任何多键参数的工具调用，其账本尾与重渲染头必分叉；
- 排序 Alphabetical ≠ prefix-preserving：deterministic 不等于 prefix-preserving（外审正确指出）。

**修正后的修复排序**：
1. **qwen3.5 协议拼接规则（方案 C）升为唯一层位正确的上游修复**——它在缓存账本与重渲染之间做协议级拼接（isToolResultContinuation 识别 + 裁剪未提交生成尾 + 拼接工具结果），绕开字母序重渲染对账本的破坏。参考 HarmonyToolRestartRule（87 行）。
2. 方案 A/B（保序/raw 存储）仍值得报告（信息保真），但**单独不解决 cache 分叉**（Jinja 排序层仍在），需与 C 同批或作为 C 的前置。
3. SimiGo 侧维持冻结；观察口径不变。

**任务级缓解（用户已采纳）**：长输出分段生成（小说项目 CLAUDE.md + 全局 ~/.zcode/CLAUDE.md 已落），单轮解码控制在耐心线内。

## 9. 附录三：官方 hit 定义、实现与 qwen35 协议规则缺口（2026-09-13 补，上游 issue 核心）

对 `mlx-swift-lm@238ad74` 三层源码核对：

**hit 定义（PromptCacheReusePolicy.swift）**：本轮全模板渲染 `promptTokens` 对账本 `cachedTokens` **逐 token、按序**比较——
- `ExtendCachedPrefixRule`：严格有序前缀 **且** prompt 严格更长 → `appendSuffix`（只喂后缀）；
- `RewindToCommonPrefixRule`：有序公共前缀 > 0、**缓存严格长于公共前缀（trimCount>0）**、对齐且 isTrimmable → 裁尾后喂余量；
- **数量相同（等长）→ 两规则皆不适用 → rebuild**；数量相同顺序不同 → 公共前缀截断 → 同上。

**实现（ChatSession.swift cache.update）**：`promptTokens = input.text.tokens`（本轮全渲染）、`cachedTokens = conversation.cachedTokens`（账本=渲染+**生成 token**——源码注释明言 "a response protocol may keep generated tokens that a cold template render cannot reproduce, by design"）；判定应用：appendSuffix 只喂 `promptTokens[suffixStart...]`、trim 先 `kvCache.trim` 且对齐校验失败降级 rebuild、rebuild 换新缓存并重置账本。`cacheEfficiency = cached/(cached+prompt)`（Evaluate.swift:2555）——SimiGo 透传一致。

**SimiGo 一致性**：消息级 reuse 门（count/fp/prefix）为粗粒度准入，官方 token 级判定为精确真值——门过、引擎判 rebuild 不是不一致，是两层职责正确分工。

**qwen35 协议规则缺口（上游修复的精确落点）**：`ToolCallFormat.swift:217-231` 的 `promptCacheReuseRules`——gptOSS（HarmonyToolRestartRule）、atem（OnyxToolRestartRule）有协议拼接规则，**`.qwen35` 与其他 9 个格式返回 `[]`**。qwen3.5 的生成 token 账本含 `<tool_call>`/`</tool_call>` 等协议私有 token（冷渲染不可复现），工具结果续跑时无拼接规则 → 落标准规则 → 分叉 × GDN 不可回卷 → rebuild。**上游提案：为 qwen3_5 实现 Qwen35ToolRestartRule**——参考现成 HarmonyToolRestartRule（仅 87 行，解析器 token `<tool_call>`/`</tool_call>` 已存在），纯规则代码可直接单测；随附生产数据集（本文档 + trace）与 issue 链（mlx-lm #980）。

**五层链闭合（2026-09-13 深夜补，全部 file:line 级）**：

```text
L1 协议层  Qwen3.5 官方 chat_template：{% for args_name, args_value in tool_call.arguments|items %}
           → 工具调用以 <parameter=键>值</parameter> 有序参数流重放（顺序承载语义）
L2 存储层  ToolCall.swift:12  arguments: [String: JSONValue]  ← 无序字典，原始生成串解析即弃
L3 重渲染  Chat.swift:161  "arguments": toolCall.function.argumentsObject
           → 消息字典 → Jinja arguments|items 按【字典哈希序】遍历 ≠ 模型生成序
L4 缓存层  渲染 prompt 与账本在工具参数处 token 分叉
           × KVCache.swift:233 GDN 层 isTrimmable=false → rewind 被拒 → .rebuild 全量重预填
L5 观测层  NativeMLX:714-715 官方计数器纯透传 → cacheEff=0.00（SimiGo 零计算，无缺陷）
```

- round-trip 实验（jsonvalue-roundtrip-repro.swift，1139bf1）：`id,content,status,deps` → `id,deps,status,content`，字符串不相等——键序改变决定性证实。
- **自愈机制同理闭合**：rebuild 后账本=哈希序渲染；模型上下文中看到的即哈希序形态 → 后续生成模仿哈希序 → 命中恢复；TodoWrite 内容更新（模型重新自由排序）→ 再次分叉 → miss。Bash 单键参数免疫。
- 上游修复两选项：(a) `ToolCall.Function.arguments` 保序存储（含原始串回退）；(b) Qwen35ToolRestartRule 拼接规则（参考 87 行现成实现）。(b) 改动最小、可单测、不动公共结构。
