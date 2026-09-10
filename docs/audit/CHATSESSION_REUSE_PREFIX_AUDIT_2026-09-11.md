# SimiGo 审计记录 — ChatSession Reuse Prefix Validation

日期：2026-09-11
分支：`audit-simplify-2026-09-11`

## Finding

当前 `NativeMLX.generateUsingChatSession()` 判断已有 `ChatSession` 是否复用，只检查：

```swift
if let existing, incoming.count > existing.history.count {
    managed = existing
    reusedSession = true
}
```

随后直接：

```swift
let delta = Array(incoming.dropFirst(managed.history.count))
```

这里没有验证：

```text
incoming[0..<existing.history.count]
        ==
existing.history
```

## Correctness risk

同一个 `AgentExecutionKey` 下，以下请求都可能进入错误复用路径：

```text
历史 A → 新请求提供“相同数量/更多数量，但前缀已经改变”的 messages
```

例如客户端重发、编辑历史、恢复分支错误、工具结果改变等情况，只要消息数量大于旧 history 数量，SimiGo 就把新输入尾部当成 delta，官方 `ChatSession` 内部却仍保存旧 history/KV 状态。

这样会导致：

```text
logical messages
      ≠
ChatSession history
      ≠
实际 generation prompt / KV prefix
```

这不是官方 MLX ChatSession 的缺陷，而是 SimiGo 自己的 reuse admission 条件过弱。

## Architectural violation

项目当前注释已经声明：Physical KV reuse 应由 NativeMLX / 官方 runtime 根据真实 token prefix 等条件决定；HTTP 层不应根据 messages 猜测 Session。

但当前 NativeMLX 自己通过：

```text
same execution key
+
message count increased
```

决定继续使用旧 `ChatSession`。

因此这仍然是一层 SimiGo 自建的 reuse heuristic。

## Classification

**P1 correctness / state-continuity bug.**

风险高于单纯性能损失，因为错误复用时生成语义可能直接错误。

## Required direction

不要重新实现 token-level KV prefix matching、Physical KV ledger 或第二套 cache。

需要把“是否继续使用既有官方 `ChatSession`”的判定收敛到一个有明确协议语义的条件；至少必须保证逻辑 history 与既有 session history 的前缀关系，否则必须创建新的官方 `ChatSession`。

同时应重新审查：

- `tools` 改变是否允许继续使用现有 session；
- `additionalContext` 改变是否允许继续使用；
- generation parameters 哪些可以安全动态修改；
- Responses `previous_response_id` 链接后进入 ChatSession 时是否仍满足同一 prefix 语义。

本轮仅记录问题，不改复用实现。
