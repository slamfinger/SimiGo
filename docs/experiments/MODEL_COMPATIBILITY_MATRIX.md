# 模型兼容性矩阵（Model Compatibility Matrix）

日期：2026-09-11
性质：黑盒兼容性回归资产（P1）。SimiGo 定位为 Runtime Adapter，
不进入 MLX/MLXLMCommon 内部实现层；本矩阵记录官方运行时在不同模型上的
实测行为边界，用于回归对照与上游 issue 素材。

测试环境：SimiGo 18:55 构建（含取消契约修复与 output_text.done 补齐），
mlx-swift-lm `main@238ad74`（Package.resolved 钉定），ctx=131072，
客户端 Codex（Responses 双请求并发 47–80ms 间隔为其标准行为）。

## 实测矩阵（2026-09-11 晚，三模型同构对照）

| 模型 | 架构 | OpenAI | Responses（单请求串行） | Responses（双并发首轮） | Tool Calling | KV/Session Cache | draftN 备注 |
|---|---|---|---|---|---|---|---|
| `peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX` | `qwen3_5_moe`（混合 GatedDeltaNet + 编译段） | ✅ | ✅（20:00，ttft=23.3s，toolCalls=1，cacheEff=1.00） | ❌ 零事件 ≥105s（20:48，draftN=0） | ✅ | ✅ | draftN=2 + 并发 → 硬死锁（sample 实锤 19:44） |
| `peculiar-ragdoll/Tiel-Coder-35B-A3B-MLX-oQ4e` | `qwen3_5_moe`（同族） | ✅ | 未测 | ❌ 零事件 ≥94s（20:56，draftN=2） | 未测 | 未测 | draftN=2 |
| `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit` | `qwen3_moe`（标准） | ✅ | ✅ | ✅ 双双完成（ttft 24.9s/31.1s；首个 tps=1.0 为 GPU 争用） | ✅ tools=24，toolCalls 连续 | ✅ reuse=true，cacheEff 0.99/0.93/0.90 | draftN=2 下并发仍 ✅ |

## 结论

1. **分界变量是模型架构 × 并发生成，不是 Responses 协议能力。**
   Nail 在单请求串行下完整跑通 Responses（20:00 实证）；
   Qwen3-Coder 在 draftN=2 + 并发下同样完整跑通。
   `qwen3_5_moe` 混合架构在并发生成下零输出（`qwen3_moe` 同条件正常）。

2. **draftN 已由现有数据降级**：Nail draftN=0 并发仍卡（20:48），
   Qwen3-Coder draftN=2 并发正常（20:58）——draftN 是放大器，非判别变量。

3. **C→D 零事件区间**（`[GEN] C stream enter` 后无 D/E/F）：发生在
   `streamDetails` 首步。19:44 sample 证明该区间可停留在
   `Qwen35TextModelInner.decodeStep → CompiledDecodeSegmentCache → compile_trace`
   的编译锁上（模型 forward 深处，模板渲染已完成的证据为 Metal kernel JIT 告警刷屏）。

4. **模板已排查**：三模型均有 `chat_template.jinja`；Nail/Tiel 为
   Qwen3.6 推理代复杂模板（29.8KB/458 行，thinking×58/tool_call×36），
   Qwen3-Coder 为标准 Qwen3 模板（6.7KB/131 行）。`jinja=false` 是
   llama.cpp 管道时代遗留参数，NativeMLX 不读取。模板非 C→D 根因。

5. **`rejectedToolCall reason=undeclared_tool tool=WebSearch`**：
   模型生成未声明工具 → Runtime 显式拒绝。工具治理边界有效的实证。

## Session/Prefix Cache 实证（Qwen3-Coder，f57a2b 会话）

| 轮次 | promptTokens | cacheHit | cacheEff | ttft |
|---|---|---|---|---|
| 首轮 | 16,248 | 0 | 0.00 | 33.2s |
| 续轮 | 110 | 16,270 | 0.99 | 0.69s |
| 续轮 | 141 | 16,415 | 0.99 | 0.85s |
| 续轮 | 1,264 | 16,645 | 0.93 | 4.1s |

33.2s → 0.69s：session-aware prefix cache 价值的直接实测。

## 多轮 usage / cache ledger 对齐观测（2026-09-12，Nail 受控三轮）

受控条件：session `usage-obs2`，累积对话（assistant 真实回显），
Nail-Qwen3.6，draftN=0。

| 轮 | usage.input | [MLX] promptTokens | usage.cached | [MLX] cacheHit/cacheTokens | usage.output | total | reuse | ttft |
|---|---:|---:|---:|---:|---:|---:|---|---:|
| T1 | 206 | 206 | 0 | 0 | 89 | 295 | false | 552ms |
| T2 | 19 | 19 | 296 | 296 | 72 | 91 | true | 141ms |
| T3 | 20 | 20 | 388 | 388 | 23 | 43 | true | 141ms |

判定：`usage` 与真实 token ledger 逐轮对齐；`cached_tokens` 直通官方
`info.cachedPromptTokenCount`，无估算。**P1-2 usage projection VERIFIED。**

### 已定性行为（非缺陷，防误报）

- **suspend → resume 后 cached_tokens=0**：`suspend_done` 清空 sessions，
  恢复后首轮全量 prefill 属预期生命周期策略，非 KV cache regression。
- **prefixMismatch 假阳性**：合成测试回显空 assistant 内容导致
  `prefixMismatch index=1 role=assistant` → 假性 reuse=false；
  真实客户端（Codex）回显正确文本后 prefix match、reuse=true。
  测试脚本问题，Runtime 无需修复。

## 遗留未测格

- Tiel：Responses 单请求串行、tool calling、KV reuse（仅测了并发场景）
- Nail：并发 + draftN=0 的完整上限（20:48 于 105s 被配置保存取消，
  死锁 vs 极端变慢未定）——复测时等 ≥5 分钟不取消
- Qwen3-Coder：并发上限（已证可完成，争用时单流 tps 降至 1.0）

## 历史资产

- **S1 批解码实验**（分支 `kv-continuation-impl-2026-09-09`，
  `NativeMLXIntegrationTests.swift` / `BatchDecodeDependencyConformanceTests.swift`）：
  编码了官方 shape 契约——prefill 输入 `[batch, promptLength]`、
  logits `[batch, L, V]`、decode 输入经 `expandedDimensions(axis:1)`
  恢复 `[batch, 1]`；并记录 MLX 后端 B>1/T=1 批解码差异
  （见 memory: mlx-batched-decode-discrepancy）。
  定位：兼容性回归资产。不做产品化。

## 边界纪律

SimiGo 职责：协议、会话生命周期、KV cache 生命周期、工具治理、
能力检测、官方 API 适配、兼容性回归。
MLX/MLXLMCommon 职责：tensor、prefill、decode、KV、编译、推测解码。
不在 SimiGo 内 fork/patch 官方模型 forward 或解码实现。
