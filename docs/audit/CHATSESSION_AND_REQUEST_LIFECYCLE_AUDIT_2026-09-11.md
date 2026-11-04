# SimiGo 审计记录 — ChatSession / Request Lifecycle

日期：2026-09-11
分支：`audit-simplify-2026-09-11`

本轮记录保留在审计分支，仅作为下一轮代码修复依据。

## 1. 官方 ChatSession 边界

`mlx-swift-lm 3.31.4` 的 `ChatSession` 是 `final class`，内部私有维护 cache；官方明确说明同一个 session 不是 thread-safe，应由单一 task/thread 使用。

`streamDetails(to:)` 用于向现有 session 追加 structured messages，并由官方内部 cache 管理 KV continuity。官方内部生成循环还会等待底层 generation task 收尾，避免提前停止消费后底层仍继续使用 KV cache。

结论：SimiGo 应维护逻辑 Session→ChatSession 映射，但不应自行构造第二套 token-prefix/KV continuity 判定。

## 2. P1 — ChatSession reuse 仅比较 message count

当前 NativeMLX：

```swift
if let existing, incoming.count > existing.history.count {
    managed = existing
    reusedSession = true
}
```

然后直接：

```swift
let delta = Array(incoming.dropFirst(managed.history.count))
```

没有验证 `incoming` 的前缀是否真的是已有 `history`。

反例：

```text
existing.history = [A, B, C]
incoming        = [X, Y, C, D]
```

因为 `4 > 3`，SimiGo 仍会继续旧 ChatSession，把 `D` 当成 delta。

这属于 **P1 correctness / state-continuity bug**：逻辑 history、实际 prompt 与官方 ChatSession 内部 KV state 可能不一致。

修复方向：至少验证逻辑 history 的 exact prefix；无法证明连续时，宁可新建官方 `ChatSession` 冷启动，不要错误复用。禁止引入自建 token-level KV cache / Physical KV ledger。

同时审查 `tools`、`additionalContext`、生成参数变化对同一 ChatSession continuation 的影响。

## 3. P1 — Request Task publication TOCTOU

当前 `NativeMLX.generate()` 的生命周期是“先创建 Task，再写入 `activeRequestTasks`”。因此理论上存在 task 已经开始运行而 request ledger 尚未可见的窗口。

而 stop/suspend 把 `activeRequestTasks` 当作 request lifetime authority。

需要把 request publication 与 task 可执行性线性化，避免 suspend/stop 在 request 尚未发布时作出错误判断。

不要通过增加另一套 activity ledger 来补洞；应修正现有 State lock 下的 publication 顺序。

## 4. P1 — Responses streaming 缺少 generation-active 标记

Chat / Completions streaming 调用 `context.markGenerationStarted()`，Responses streaming 当前没有。

因此断连路径进入 `closeAndTakeRequestTask(cancelGeneration: true)` 时，`_generationStarted` 可能仍为 false，导致 `cancelGenerationHandler` 不触发。

修复方向：Responses 在进入 generation 前与其它 streaming API 一致地标记 generation active，并保持 defer 清除。

## 5. P1 — Direct SSE 改造误删 lifecycle transitions

Chat / Completions streaming 在 direct SSE 改造时删除了：

```text
CREATED → QUEUED → RUNNING
```

但仍调用统一 `finish()`。

这样 lifecycle ledger 中成功请求可能从 `CREATED` 直接进入 release fallback，而不是：

```text
CREATED → QUEUED → RUNNING → COMPLETING → COMPLETED → RELEASING → RELEASED
```

Direct SSE 与 lifecycle 是正交问题；恢复上述 transitions 不需要恢复 sendQueue。

## 6. P1/P2 — Responses SSE transport 不一致

Responses streaming 仍走：

```text
sendQueue.async → NWConnection.send
```

而 Chat / Completions 已走 direct `NWConnection.send`。

Responses 同时缺 `Connection: keep-alive`。历史已验证的低延迟 SSE 路径要求三者一致，但不要引入新的 chunked encoder 或额外 streaming buffer。

## 7. P2 — idle-suspend 为 SimiGo 自建 runtime policy

NativeMLX 当前 `suspendIfIdle()` 会释放 `modelContainer`、清空 `sessions`、调用 `Memory.clearCache()`；Service 实际使用 120 秒 idle timeout。

这会人为打断官方 ChatSession 生命周期。完成 P1 修复后，应删除这层 idle-suspend；显式 `stop()` 的完整模型释放保留。

## 8. 当前内存原则保持正确

`RuntimeTuning` 已收敛为：

```text
MLX memoryLimit = 22 GiB
MLX cacheLimit  = 4 GiB
Responses store = 64 / 1800s
```

本轮不要重新引入 `projectedMemory`、Admission ledger、Physical KV accounting 或第二套 residency 真值。

## 9. 配置残留候选

`ModelConfig` 仍有 `sleepIdleSeconds`、`isMoE`、`moeMaxSlots` 等字段。当前只认定为 cleanup candidate，必须逐项确认实际引用后再删除。

## 修复优先级

1. exact logical-prefix / ChatSession reuse
2. request task publication linearization
3. Responses generation-active/cancellation
4. streaming lifecycle transitions
5. Responses direct SSE + keep-alive
6. 删除 idle-suspend
7. 最终死代码 / 配置字段清理

本轮不修改运行时代码，仅更新审计依据。