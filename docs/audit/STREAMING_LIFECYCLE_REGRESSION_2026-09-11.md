# SimiGo 审计记录 — Streaming Lifecycle Regression

日期：2026-09-11
分支：`audit-simplify-2026-09-11`

## 1. Finding

直接 SSE 低延迟改造后，Chat / Completions 的 streaming path 保留了：

```swift
await context.registerLifecycle()
```

但删除了：

```swift
try await context.transitionToQueued()
try await context.transitionToRunning()
```

Responses streaming 当前同样只注册 lifecycle，也没有在 generation 前完成上述状态迁移。

## 2. Actual consequence

`RuntimeLifecycleCoordinator.finish(success: true, ...)` 的正常成功路径假定当前状态已经进入：

```text
QUEUED → RUNNING
        ↓
COMPLETING → COMPLETED → RELEASING → RELEASED
```

而当前 direct-SSE streaming path 的状态仍可能是：

```text
CREATED
   ↓
finish(success: true)
```

此时：

```swift
RuntimeTransitionRule.isValid(from: .created, to: .completing)
```

不成立，`finish()` 会记录 `FORCE_RELEASED`，然后继续把状态字段推进到后续终态。

这意味着 lifecycle trace 不再反映真实的 streaming execution phase。

## 3. Why this matters

这不是 HTTP 输出延迟问题，也不会自动说明模型生成失败；它是 direct SSE 改造过程中把原有 lifecycle 状态语义误删后的回归。

同时，`ConnectionContext.markGenerationStarted()` 仍然被 Chat / Completions streaming 使用，因此 lifecycle 与 generation cancellation 已经出现不一致：

```text
generation cancellation authority = active
lifecycle execution phase = CREATED
```

Responses streaming 更进一步：当前没有调用 `markGenerationStarted()`，所以连接断开时 `terminate(cancelGeneration: true)` 可能无法把本次 generation 标记为需要取消。

## 4. Required correction boundary

低延迟 SSE 不需要恢复 `sendQueue`。

正确修复应当保持：

```text
SSE headers  → direct NWConnection.send
SSE chunks   → direct NWConnection.send
[DONE]       → direct NWConnection.send
```

同时恢复最小 lifecycle / cancellation bookkeeping：

```text
markGenerationStarted()
registerLifecycle()
transitionToQueued()
transitionToRunning()
generateHandler(...)
finishLifecycle(...)
markGenerationFinished()
```

这些状态操作不应重新包住 SSE payload，也不应重新引入发送队列。

## 5. Classification

- **P1 correctness regression:** Responses streaming 未 `markGenerationStarted()`，断连取消可能丢失。
- **P1 observability/state regression:** Chat / Completions / Responses streaming 删除正常 lifecycle transitions，成功请求可能产生 `FORCE_RELEASED`，生命周期账本失真。
- **Performance impact:** 未发现需要恢复 sendQueue 的理由。

## 6. Decision

不要通过删除整个 lifecycle 文件来掩盖这一问题；先修复 streaming path 的最小状态语义，再继续判断 RuntimeLifecycle 是否还有独立价值。

本轮没有恢复任何自建 KV、Admission、Physical residency 或 chunked transport。
