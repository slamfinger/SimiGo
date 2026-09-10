# SimiGo 审计记录 — StreamTokenFilter / Gate 边界

日期：2026-09-11
分支：`audit-simplify-2026-09-11`

## 1. StreamTokenFilter 当前职责

`StreamTokenFilter` 位于 NativeMLX 与 HTTP streaming callback 之间。

当前有两条路径：

- `disableThinking == true`：直接 sanitize 当前 chunk 后立即回调。
- `disableThinking == false`：自行维护 buffer / pendingText / thinking state，并识别多组 `<think>`、`<thought>`、`<|start_of_think|>` 等标记。

## 2. 结论：P2 cleanup candidate，不列为当前 P1

当 `ModelConfig.disableThinking` 默认开启时，当前快速路径不会因为 `maxPendingCharacters` 形成持续等待；因此它不是此前“长时间不出首 token”的首要证据。

但是，thinking 开启路径是 SimiGo 自建的 presentation parser。它不属于 ChatSession / `streamDetails(to:)` 的官方 generation API，本质上是在 runtime 输出之后重新解释模型文本。

在项目目标“Native MLX + 官方 API，不再造第二套 runtime 规则”下，这一层需要继续证明必要性：

1. 是否只是 UI 标签清理；
2. 是否官方 ChatSession / tokenizer 已经负责 special token；
3. 是否项目协议层真正要求隐藏思维标签；
4. 删除后是否仍能保持现有 OpenAI-compatible streaming 行为。

在上述事实没有确认前，不直接删除，避免把 presentation contract 与 inference contract 混在一起。

## 3. SessionGenerationGate 保留

`SessionGenerationGate` 负责同一 `AgentExecutionKey` 的互斥执行，这一层与官方 `ChatSession` 的非 thread-safe 约束一致。

因此它不是自建 KV runtime，不应与已经删除的 Physical KV / Prefix Cache / Admission ledger 混为一谈。

## 4. RuntimeLifecycleGate 保留

`RuntimeLifecycleGate` 串行化模型 start / stop / resume 等 runtime lifecycle 操作。当前没有证据证明它可以被普通 Swift synchronization 直接删除而不改变 lifecycle semantics，因此本轮保留。

## 5. 下一轮重点

- 修复/收敛 Responses direct SSE；
- 线性化 NativeMLX request task publication；
- 精确验证 ChatSession logical prefix；
- 检查 tools / additionalContext 变化时是否允许继续复用同一 ChatSession；
- 最后再决定是否删除 StreamTokenFilter 的 thinking parser。
