# SimiGo 审计记录 — Streaming / Lifecycle

日期：2026-09-11
分支：`audit-simplify-2026-09-11`

## 1. Responses SSE 仍存在独立发送路径

当前 `HTTPServerResponses.swift` 的 `handleResponsesStreaming` 已正确使用 `text/event-stream`，但事件最终进入：

```swift
context.sendQueue.async { ...
    context.connection.send(...)
}
```

而 Chat / Completions 已改为直接通过 `NWConnection.send` 输出 SSE。

因此三条 OpenAI 流式协议目前不是同一条低延迟发送路径：

- Chat：direct SSE send
- Completions：direct SSE send
- Responses：sendQueue.async → NWConnection.send

这一差异与此前历史上已经验证过的低延迟路径不一致。官方 `mlx-swift-lm 3.31.4` 的 `ChatSession.streamDetails(to:)` 本身确实逐事件产生 `Generation`，所以当前继续出现分钟级首字节/界面延迟时，应优先排查 Responses 的协议发送链，而不是重新实现模型层 streaming。

## 2. Responses SSE 当前没有 `Connection: keep-alive`

当前 Responses streaming response headers 设置了：

- `Content-Type: text/event-stream; charset=utf-8`
- `Cache-Control: no-cache, no-store, must-revalidate`
- `X-Accel-Buffering: no`

但没有像已经修复的 Chat / Completions 路径一样显式设置：

```text
Connection: keep-alive
```

需要统一历史已验证的 SSE framing / connection 行为；本审计不引入 Transfer-Encoding/chunked 等新协议轮子。

## 3. NativeMLX 存在旧的空闲挂起层

`NativeMLX.suspendIfIdle()` 在空闲条件满足后会：

- `modelContainer = nil`
- `sessions.removeAll()`
- `Memory.clearCache()`
- 生命周期切到 `.suspended`

同时 HTTPServer 本身保持运行。

`Service.startHealthCheck()` 对 NativeMLX 使用：

```swift
let _ = await nativeMLX.suspendIfIdle(
    idleTimeout: Self.idleSuspendTimeout
)
```

当前 `idleSuspendTimeout = 120` 秒。

这会人为切断官方 `ChatSession` 的长期对象生命周期，并在后续请求触发重新加载。它不是 MLX 官方 ChatSession/KV 能力的一部分，属于 SimiGo 自建 runtime policy，应作为后续清理候选。

## 4. 不重复构造第二套 KV / Admission 真值

本轮没有恢复任何 Physical KV ledger、projectedMemory、eviction/admission 账本，也没有重新计算 MLX 内部 residency。内存控制继续只使用 MLX 官方 `Memory.memoryLimit` / `Memory.cacheLimit`。

## 下一步

安全修复顺序：

1. Responses 与 Chat / Completions 统一为 direct SSE send，并补齐 `Connection: keep-alive`。
2. 删除 NativeMLX/Service 的 idle-suspend 旧策略，但保留显式 `stop()` 的完整模型释放。
3. 再做一次全仓库死代码/旧 runtime policy 扫描。

本记录刻意不引入新的 streaming buffer、chunked encoder、KV runtime 或 admission algorithm。
