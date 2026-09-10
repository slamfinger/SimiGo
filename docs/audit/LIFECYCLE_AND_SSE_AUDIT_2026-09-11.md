# SimiGo 审计记录 — Lifecycle / SSE follow-up

日期：2026-09-11
分支：`audit-simplify-2026-09-11`

## 1. 已确认：Responses streaming 缺 generation-active 标记（P1）

`handleResponsesStreaming` 在解析参数后直接建立 `defer`，但没有像 Chat / Completions streaming 那样先调用 `context.markGenerationStarted()`。

连接断开进入 `ConnectionContext.closeAndTakeRequestTask(cancelGeneration: true)` 时，取消判断依赖 `_generationStarted`。因此 Responses streaming 可能出现：

`client disconnect → request task cancel → cancelGenerationHandler 不触发`

修复原则：与其它 streaming endpoint 保持一致，在 generation 生命周期开始前标记 active，defer 中统一清除。

## 2. 已确认：Chat / Completions streaming 的 lifecycle transition 曾被删掉（P1）

当前 direct SSE 本身不需要 lifecycle transition，但 `finishLifecycle()` 仍然存在。因此必须保持：

`CREATED → QUEUED → RUNNING → COMPLETING → COMPLETED → RELEASING → RELEASED`

不能因为去掉 `sendQueue` 就同时去掉 `transitionToQueued()` / `transitionToRunning()`。

## 3. 已确认：RuntimeLifecycleCoordinator.finish() 有“非法边也写状态”的语义问题（P2）

`finish()` 对每一步先用 `RuntimeTransitionRule.isValid()` 检查，但无论合法与否都会执行 `states[requestID] = step`。

因此出现非法路径时，Trace 会记录 `FORCE_RELEASED`，但内部状态仍会依次写入 `COMPLETING`、`COMPLETED`、`RELEASING`、`RELEASED`。这使 lifecycle ledger 不能再被解释为“全部路径均经过合法 transition”。

现阶段暂不改，因为它明显是原设计的 fail-safe 收敛策略；首先修复正常调用方缺失 transition，之后再决定是否把 `finish()` 收敛为“非法边只强制终止、不伪造中间状态”。

## 4. 已确认：Responses streaming transport 与 Chat / Completions 不一致（P1/P2）

Chat / Completions streaming 当前直接调用 `NWConnection.send(... isComplete:false)`；Responses 仍走：

`sendResponse(close:false) → enqueueSend() → sendQueue.async → NWConnection.send()`

Responses 的首部同时没有显式 `Connection: keep-alive`。

这使三条 streaming endpoint 的 transport contract 不一致，应收敛为历史已验证的 direct SSE 路径，且不能重新引入 generation queue / KV queue。

## 5. 新增重点：HTTP/1.1 streaming body framing 需要实机验证（P1，待定）

当前 Responses 的初始 200 响应：

- `Content-Type: text/event-stream`
- 没有 `Content-Length`
- `close:false`，因此没有 `Connection: close`
- 当前也没有显式 `Transfer-Encoding: chunked`

这意味着 HTTP/1.1 message-body framing 依赖连接持续存在，客户端/URLSession/代理的具体实现可能产生缓冲或等待行为。SSE 的事件分隔符 `\n\n` 并不替代 HTTP message framing。

Chat / Completions 的 direct SSE 目前也采用类似 raw-send 模式，因此不能仅凭代码断言这是唯一根因；需要用实际客户端抓包验证：首个 SSE DATA 是否在 generation callback 后立即到达 socket，以及客户端是否在收到首事件前等待完整 HTTP body。

修复时遵循项目既定约束：优先复用已经验证的 SimiGo direct-SSE 路径，不新造独立 HTTP streaming encoder。

## 6. 已确认：NativeMLX 仍存在自建 idle-suspend（P2）

当前 `suspendIfIdle()` 会在空闲时清除 `modelContainer`、`sessions` 并调用 `Memory.clearCache()`；这不是官方 `ChatSession` 的协议要求。

它会人为打断逻辑 Session → 官方 ChatSession 的连续性，因此应在 P1 生命周期 / SSE 问题收敛后删除；显式 `stop()` 继续负责完整 runtime teardown。

## 7. 已确认：NativeMLX request publication TOCTOU 仍未修复（P1）

当前 `generate()` 仍是：

`Task(...) → state.withLock { activeRequestTasks[requestId] = task }`

Task 在 publication 之前即可开始运行，而 stop/cancel/suspend 将 `activeRequestTasks` 当作 request lifetime 可见性依据。

下一步应在线性化“可执行 task”和“activeRequestTasks 可见”这两个动作；不要增加第二个 request ledger。

## 8. 已确认：ChatSession reuse 的判断仍只比较长度（P1）

当前仍为：

`incoming.count > existing.history.count`

然后直接 `dropFirst(existing.history.count)`。

这无法证明 incoming 是 existing.history 的真实前缀。必须把 reuse 条件收紧为可证明的 logical history continuity；否则创建新的官方 `ChatSession(history:)` 比错误复用安全。

## 9. 官方 API 边界

官方 `mlx-swift-lm` 的 `ChatSession` 明确声明不是 thread-safe；`streamDetails(to:)` 是追加 structured messages 并保持内部 cache continuity 的官方 API。其内部 `streamMap` 以私有 cache 管理 history/KV，并在生成任务结束后完成 cache 更新。

因此 SimiGo 继续禁止重新引入独立 Physical KV ledger、token-prefix cache、Admission memory accounting 或第二套 KV residency 真值。

## 下一轮顺序

1. 修复 Responses `markGenerationStarted()`。
2. 恢复 Chat / Completions streaming 的 lifecycle transitions。
3. 统一 Responses 到 direct SSE，并实测首字节/首事件到达时间。
4. 再处理 request task publication linearization。
5. 收紧 ChatSession logical-prefix reuse。
6. 删除 idle-suspend 与剩余无引用配置。
