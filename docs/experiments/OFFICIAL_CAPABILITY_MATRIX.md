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

## P0 —— 建议优先补

### KV Cache Configuration / Quantization

- 官方入口已核实：`public struct KVCacheConfiguration`（`KVCacheConfiguration.swift`），
  Strategy 含 `.affine(AffineKVCacheConfiguration)` 与 `.turboQuant(TurboQuantKVCacheConfiguration)`。
- **接线点**：`GenerateParameters.kvCachePlan()`——KV 配置经由 GenerateParameters 流入
  ChatSession，SimiGo 只需在 `ModelConfig → GenerateParameters` 映射链上增加字段，无需改调用面。
- **必须透传的语义**：cache plan 变更会使官方 token 账本失效（`cachedTokens.removeAll()` → 重建），
  即切换 KV 策略的代价是下一轮全量 prefill——SimiGo 配置面应明示这一点。

### Raw Token Generation

- 官方入口已核实：`generateTokens`（4 个重载）/ `generateTokensTask` / `generateTokenTask` /
  `TokenGeneration` 枚举（Evaluate.swift）。
- 定位：**Runtime/Batch 层的内部能力边界**，不必然暴露为 HTTP API。
  Batch（S1）、Paged KV（S2）、token 级对账、投机解码都比字符串层更贴近 token 层。
- 不意味着现在实现 Token Runtime；只要求能力盘点时承认这条官方路径存在。

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
- 待研究：logits processors、sampling 配置、stop conditions、KV config（见 P0）。
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
P0：KVCacheConfiguration 透传 → Raw Token 能力边界
        ↓
P1：Prompt Cache Save/Load → Guided Generation → 参数补齐
        ↓
P2：Task API 审计 → Speculative 配置透传 → VLM
        ↓
更新本矩阵 → 再评估 Evolution Track S1/S2/S3
```
