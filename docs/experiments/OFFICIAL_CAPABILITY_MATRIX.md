# 官方 MLX 能力覆盖矩阵（Official Capability Matrix）

日期：2026-09-12
核对基准：mlx-swift-lm `main@238ad74`（当前 Package.resolved 钉定 commit），全部 API 名以该 commit 源码为准。

## 定位

下一阶段的正确方向不是增强自研 Runtime 机制，而是 **Official Capability Completion**：
把官方已经存在、且符合 SimiGo 定位（Inference Runtime）的能力逐步透传/映射出来。
这是能力面扩展，不违反 Core Freeze——所有条目都走官方 API，不建立第二套 token/cache/协议事实。

纪律：每个能力落地前走演进纪律（最小原型 → 实机 benchmark → 审计 → 稳定 DMG），
一次一个变量；本矩阵属于 experiments 层，随条目落地持续更新。

## 已接入 Core（✅）

| 能力 | 官方 API | SimiGo 状态 |
|---|---|---|
| Model loading | `LLMModelFactory.loadContainer` | Core |
| ChatSession / conversation / streaming | `ChatSession.streamDetails(to:)` | Core |
| Tool Calling | `Generation.toolCall` → `ParsedToolCall` | Core |
| rejectedToolCall | `Generation.rejectedToolCall`（留痕+忽略） | Core |
| Prompt cache reuse（token 账本） | `PromptCacheReusePolicy`（appendSuffix / trimToCommonPrefix / rebuild） | Core |
| Cache telemetry | `cacheStatus()` + `GenerateCompletionInfo.cacheEfficiency/cachedPromptTokenCount` | Core |
| KV Cache Configuration / Quantization | `GenerateParameters.kvCache` ← `ModelConfig.kvCache`（P0-A，`02587d1`；SDK 兼容修正 `f89e4bc`） | **Core** |

## P0 —— 已完成（P0-A CLOSED，2026-09-12）

### KV Cache Configuration / Quantization ✅（`02587d1`，SDK 兼容修正 `f89e4bc`）

- 官方入口：`public struct KVCacheConfiguration`（Strategy：fullPrecision / affine / turboQuant /
  varianceNormalized；Capacity：maxTokens + preservedPrefixTokens；CompatibilityPolicy）。
- **接线点**：`GenerateParameters.kvCache`——SimiGo 侧 `ModelConfig.kvCache: KVCacheSettings?`
  （策略名与官方预设一一对应：affine4 / affine8 / turboQuality / turboBalanced / turboMemory）
  经 `NativeMLX.makeKVCacheConfiguration` 映射后注入；`maxKVSize: nil` 保证不触发
  legacy 冲突守卫（`hasLegacyKVCacheOverrides == false`）。
- **已透传的语义**：cache plan 变更使官方 token 账本失效（`cachedTokens.removeAll()`），
  下一轮全量 prefill——配置切换的代价，不是 cache regression。
- `compatibility: .allowPartial`：混合注意力模型（Mamba 层不支持量化）受支持层生效、其余原样。
- 非法 strategy fail-fast（`RuntError.generationFailed`），不静默忽略。
- 契约测试 8 项（`KVCacheSettingsTests`）：预设映射 / capacity 默认 / fail-fast / Codable 往返。
- `f89e4bc` 说明：`deletingLastPathComponent` 属性形式是**本地 SDK 编译兼容性修正**——
  Foundation API 表达形式不属于 Runtime contract；当前以本地实际编译 SDK 为准，
  不记录为"与上游方向相反、需要重新同步"。

## P0-B —— Raw Token Generation：能力边界审计结论（2026-09-12）

官方入口已核实（Evaluate.swift）：`generateTokens` 4 个重载 +
`generateTokensTask` / `generateTokenTask`，统一返回 `AsyncStream<TokenGeneration>`
（`.token(Int)` / `.info(GenerateCompletionInfo)`——与解码路径共用同一 info 类型）。

**边界事实**：

```text
Raw 路径入参：LMInput（已 token 化）+ [KVCache]（裸 cache 数组）+ ModelContext/Container
             + 可选 wiredMemoryTicket
ChatSession 路径 = Raw 路径 + conversation/模板渲染/token 账本/telemetry 的官方封装
```

**冻结的边界声明**：

1. Raw Token API 属于**未来 Execution Plane 内部能力**（S1 Batch、Paged KV、token 级对账），
   不用于 HTTP 请求路径——用它做请求生成等于绕过 ChatSession 账本，
   重新制造已被消除的"第二套事实来源"。
2. 当前不写 Token Runtime、不改 ChatSession 主路径；
   本节仅确立能力边界与官方入口清单，供未来 S1/S2 设计时引用。
3. 值得留意的官方细节：raw 路径暴露 `wiredMemoryTicket` 参数——
   与本机已观测的 wired-memory 页出现象相关，未来资源治理设计时可引用。

## P1

### Prompt Cache Save / Load

- 已核实：保存 = `ChatSession.saveCache(to:)`；加载 = 自由函数 `loadPromptCache(url:)` /
  `loadPromptCacheSnapshot(url:)`（KVCache.swift）+ 接受预构建 cache 的 `ChatSession` init。
- 官方兼容策略（plan / layer kind 校验，账本失效→重建）由 ChatSession 自带，**SimiGo 不建第二套 cache ledger**。
- 适用场景：超长 System Prompt、Coding Agent 固定前缀、固定 Tool Schema、LAN 多 Agent 共享预热。
- 注意与现有 warm reuse 的关系：进程内复用走 token 账本（已闭环），跨进程/跨启动持久化才是本能力。

### Guided Generation（JSON Schema / EBNF）

- 官方产品已核实：`MLXGuidedGeneration`（Package.swift products）。
- 对 Agent 场景价值：结构化输出由 grammar 保证，而不是靠模型自觉 + 事后修复。
- 属 Model/Protocol Capability，不是 Agent Logic。

### Generation Parameters 补齐

- 已映射：maxTokens/temperature/topP/topK/minP/repetitionPenalty/presencePenalty。
- 待研究：logits processors、sampling 配置、stop conditions（KV config 已落地，见 P0-A）。
- 纪律：先建立「SimiGo API → 官方参数」一一映射表，能映射才开放，不批量堆参数。

## P2

- **Generation Task API 对齐**：官方 `generateTask`/`generateTokensTask` 带 early-stop +
  deterministic cleanup 语义。SimiGo 现有 `activeRequestTasks` + cancelGeneration 是正确的；
  值得审计一次「SimiGo Task × MLX Task × Stream lifecycle × Cancellation」的重复状态，
  **只审计，不重构**。
- **诊断面透传**：`cacheStatus()` 已用；`ModelContainer` 侧同款诊断可继续暴露。
- **Speculative Decode**（对早期矩阵的事实修正）：`SpeculativeDecodingConfig` 已内置于
  钉定版本的 ChatSession（draftModel / numDraftTokens / memoryPolicy / loadDraftModel 延迟加载），
  非等官方状态。门控条件 = 模型具备 MTP 头 + 实机 benchmark；配置面可低成本透传。
- **VLM / Multimodal**：`UserInput` 已含 images/videos/audios；产品 `MLXVLM` 存在。
  属 Protocol/Model Plane 扩展，不触及 Runtime Core；HTTP 层需要多模态消息编码设计。

## Future / 明确排除

- **Embeddings**（`MLXEmbedders`）：KV/Generation/Session 语义与 LLM 完全不同，
  未来作为独立 Model Capability（如 `/v1/embeddings`）加入，不混入当前 Core。
- **LoRA / Fine-tuning**：官方有（238ad74 头提交即 LoRA 相关），但 SimiGo 定位是
  Inference Runtime——**明确排除在当前 Core 之外**（借鉴但不照搬的实际应用）。
- **Batch / Continuous Batch**：维持 Evolution Track S1/S3 的 NO-GO 与实验纪律，
  不属于"官方能力补齐"的 P0。
- **Advanced Prefix/Radix Cache**：S2，SGLang 参考；当前官方 token 账本已覆盖进程内复用。

## 建议顺序

```text
当前 v5.0 Core（已验证）
        ↓
Official Capability Audit（本文）
        ↓
P0-A：KVCacheConfiguration 透传 ✅（02587d1）
P0-B：Raw Token 能力边界审计 ✅（本文，冻结边界声明）
        ↓
P1：Prompt Cache Save/Load → Guided Generation → 参数补齐
        ↓
P2：Task API 审计 → Speculative 配置透传 → VLM
        ↓
更新本矩阵 → 再评估 Evolution Track S1/S2/S3
```
