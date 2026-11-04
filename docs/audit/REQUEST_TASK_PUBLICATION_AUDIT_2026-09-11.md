# SimiGo 审计记录 — Request Task Publication / Suspend Race

日期：2026-09-11
分支：`audit-simplify-2026-09-11`

## Finding

当前 `NativeMLX.generate()` 的顺序是：

```swift
let task = Task { ... generation ... }

state.withLock {
    state.activeRequestTasks[requestId] = task
}
```

也就是说，真正的 request task 在加入 `activeRequestTasks` 之前已经被创建并可能开始执行。

而 `stop()` / `suspendIfIdle()` 使用 `activeRequestTasks` 作为 request-lifetime authority。

## Race window

存在以下理论顺序：

```text
T1 generate()
   ↓
创建 Task
   ↓
Task 开始执行 generateUsingChatSession

T2 stop() / suspendIfIdle()
   ↓
观察 activeRequestTasks == empty
   ↓
据此继续 teardown / suspend

T1
   ↓
才把 task 写入 activeRequestTasks
```

因此 `activeRequestTasks` 目前不是“整个 Task 生命周期”的严格发布点。

尤其需要关注：

- `Task` 创建后、State registration 前的 cancellation；
- stop 与 registration 并发；
- suspend 与 registration 并发；
- `generateUsingChatSession()` 在 registration 前是否可能读取并使用 `modelContainer`；
- registration 失败时 Task 是否已经发生过副作用。

## Classification

**P1 concurrency / lifecycle publication race candidate.**

这不是 SSE 发送延迟问题，也不是 MLX 官方 ChatSession 的缺陷；它属于 SimiGo 自己的 request ownership bookkeeping。

## Required proof

需要证明以下不变量：

```text
Task starts
    ⇒ request ownership is already published
```

以及：

```text
stop/suspend observes no active request
    ⇒ no request Task can still enter execution
```

当前代码结构不能直接证明第二条。

## Scope

修复时不要重新引入 KV ledger、Admission、Physical residency bookkeeping。

更安全的方向是重新建立 request Task 的发布线性化点，使 `activeRequestTasks` 覆盖从请求执行开始到结束的完整 ownership 生命周期；具体实现应以不改变 Native MLX `ChatSession` 官方推理路径为前提。

本轮仅记录问题，不改 NativeMLX 并发模型。
