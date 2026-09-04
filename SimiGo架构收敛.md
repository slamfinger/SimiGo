这个工作我建议**不要直接改某一个 Swift 文件**，而是先把 SimiGo 的生命周期模型正式定义下来，然后再按这个模型改代码。

你现在要做的实际上是一次 **Runtime Lifecycle Refactor**。核心目标不是“增加一个 State enum”，而是让：

> **每一个 Request 从创建到释放，都有唯一身份、明确状态、明确 Owner、合法状态迁移、完整 Trace，并且任何异常最终都能收敛到 Release。**

我建议分 **8 个阶段**做。

---

# 1. 先建立统一的 Runtime 对象模型

第一步先把现在代码里的对象关系彻底梳理出来。

目标结构建议固定为：

```text
                    ┌──────────────┐
                    │   Request    │
                    │ requestID    │
                    └──────┬───────┘
                           │ 1
                           ▼
                  ┌──────────────────┐
                  │ GenerationTask   │
                  │ generationID     │
                  └───────┬──────────┘
                          │ 1
                          ▼
                    ┌────────────┐
                    │  Session   │
                    │ sessionID  │
                    └─────┬──────┘
                          │
                 ┌────────┴────────┐
                 ▼                 ▼
             ┌───────┐        ┌────────┐
             │  KV   │        │ Branch │
             └───────┘        └────────┘

GenerationTask
      │
      ▼
   Stream
      │
      ▼
    Agent
      │
      ▼
   Release
```

这里有一个非常重要的原则：

## Agent 不应该拥有底层 Runtime

也就是说不要形成：

```text
Agent
 ├── Session
 ├── KV
 ├── Task
 └── Stream
```

否则 Agent 一退出，就容易产生你最近看到的：

```text
Agent exited
    ↓
但是 Task 还活着
    ↓
KV 还活着
    ↓
Session 还活着
    ↓
SW 指标不下降
```

应该是：

```text
Runtime
 ├── Request
 │    └── GenerationTask
 │          └── Session
 │                └── KV
 │
 └── Agent
       └── observes / drives Request
```

**Agent 是参与者，不是资源 Owner。**

---

# 2. 定义严格的 State Machine

第二步才是 State。

我建议不要每个对象随便定义自己的状态，而是建立一个统一的：

```swift
enum RuntimeState
```

但内部仍然允许各对象有自己的细分状态。

例如 Request：

```text
CREATED
   ↓
QUEUED
   ↓
RUNNING
   ↓
STREAMING
   ↓
COMPLETING
   ↓
COMPLETED
```

异常：

```text
任何状态
   ↓
CANCELLING
   ↓
DRAINING
   ↓
RELEASING
   ↓
RELEASED
```

最终形成：

```text
                ┌───────────┐
                │  CREATED  │
                └─────┬─────┘
                      ▼
                ┌───────────┐
                │  QUEUED   │
                └─────┬─────┘
                      ▼
                ┌───────────┐
                │  RUNNING  │
                └─────┬─────┘
                      ▼
                ┌───────────┐
                │ STREAMING │
                └─────┬─────┘
                      ▼
                ┌────────────┐
                │ COMPLETING │
                └──────┬─────┘
                       ▼
                 ┌──────────┐
                 │COMPLETED │
                 └────┬─────┘
                      │
                      ▼
                 ┌──────────┐
                 │ RELEASED │
                 └──────────┘


任何状态 ──cancel/error/timeout──► CANCELLING
                                      │
                                      ▼
                                   DRAINING
                                      │
                                      ▼
                                   RELEASING
                                      │
                                      ▼
                                   RELEASED
```

关键规则：

> **RELEASED 必须是终态。**

一旦：

```text
RELEASED
```

就绝对不能：

```text
RELEASED → RUNNING
RELEASED → STREAMING
```

---

# 3. 更重要的是：定义“合法迁移表”

这是“可证明”的核心。

不能只是：

```swift
state = .streaming
```

而应该：

```swift
transition(to: .streaming)
```

由 State Machine 判断是否合法。

例如：

| 当前         | 允许                      |
| ---------- | ----------------------- |
| CREATED    | QUEUED                  |
| QUEUED     | RUNNING / CANCELLING    |
| RUNNING    | STREAMING / CANCELLING  |
| STREAMING  | COMPLETING / CANCELLING |
| COMPLETING | COMPLETED / CANCELLING  |
| COMPLETED  | RELEASING               |
| CANCELLING | DRAINING                |
| DRAINING   | RELEASING               |
| RELEASING  | RELEASED                |

其他全部：

```text
INVALID TRANSITION
```

并记录 Trace。

例如：

```text
INVALID_STATE_TRANSITION

request=req-123
generation=gen-456
session=session-789

from=RELEASED
to=STREAMING
```

这样以后再看到奇怪日志，就不是猜。

---

# 4. Request / Task / Session / KV 要建立 Parent-Child Contract

这是第二个非常关键的部分。

例如：

```text
Request
  owns
    GenerationTask
      owns
        SessionHandle
          references
            KV
```

但不是简单的 Swift 引用关系。

需要明确生命周期规则。

例如：

### Request

```text
Request CREATED
    ↓
Task 必须存在
```

### GenerationTask

```text
Task RUNNING
    ↓
Session 必须有效
```

### Session

```text
Session ACTIVE
    ↓
KV 可以存在
```

### KV

```text
KV attached
    ↓
Session 可以使用
```

然后释放必须反过来：

```text
Request
   ↓
Task cancel
   ↓
Stream drain
   ↓
KV detach
   ↓
Session release
   ↓
Task release
   ↓
Request release
```

而不是：

```text
Session.remove()
KV.release()
Task.deregister()
Stream.finish()
```

到处各自释放。

---

# 5. 建立唯一的 Release Coordinator

这一项我认为是**整个改造最重要的代码结构之一**。

现在最容易出现的问题就是：

```text
某个地方 release Task
某个地方 remove Session
某个地方释放 KV
某个地方 stream.finish
某个地方 deregister
```

最终导致：

```text
谁都以为别人释放了
```

所以应该建立：

```swift
RuntimeLifecycleCoordinator
```

或者：

```swift
RuntimeLifecycleManager
```

所有终止路径最终都进入：

```swift
terminate(requestID: reason:)
```

例如：

```text
正常完成
    ┐
cancel
    ├──► terminate()
timeout
    │
client disconnect
    │
agent exit
    │
OOM
    │
generation error
    │
stream error
    ┘
```

然后统一：

```text
terminate
   ↓
mark cancelling
   ↓
stop generation
   ↓
drain stream
   ↓
detach KV
   ↓
release session
   ↓
deregister task
   ↓
release request
   ↓
emit RELEASED
```

这样才能真正解决：

> **Agent 已经退出，但是 SW 指标没有下降**

这种问题。

---

# 6. Stream 必须单独做状态机

你最近出现：

```text
</think>
...
</think>
```

这说明 Stream 层现在很可能同时承担了：

* Token filtering
* Thinking detection
* Finish detection
* Protocol conversion
* Stream closing

这些职责可能交叉。

所以 Stream 应该单独定义：

```text
Stream CREATED
     ↓
OPEN
     ↓
EMITTING
     ↓
FINISHING
     ↓
CLOSED
```

并且：

```text
CLOSED
```

以后任何 token：

```text
emit(token)
```

都必须被拒绝。

例如：

```text
Stream CLOSED
receive token
       ↓
STREAM_AFTER_CLOSE
       ↓
Trace
       ↓
drop
```

这会直接帮助解决重复：

```text
</think>
```

因为：

```text
semantic event
```

只能消费一次。

---

# 7. Agent 要从“生命周期管理者”变成“Lifecycle Observer”

这一点非常重要。

建议 Agent 最终只做：

```text
Agent
 │
 ├── submit Request
 ├── receive Stream
 ├── send tool call
 ├── request cancellation
 └── observe lifecycle
```

而不要做：

```text
Agent
 ├── create Session
 ├── release Session
 ├── release KV
 ├── deregister Task
 ├── close Stream
 └── destroy Request
```

换句话说：

> **Agent 可以请求 Runtime 结束，但是不能自己决定 Runtime 如何释放。**

例如：

```swift
agent.cancel(requestID)
```

而不是：

```swift
agent.session.remove()
agent.task.deregister()
agent.kv.release()
```

这样 Agent 即使：

```text
exit
crash
disconnect
```

Runtime 仍然能够完成：

```text
CANCELLING
 → DRAINING
 → RELEASING
 → RELEASED
```

---

# 8. 最后建立 Lifecycle Trace

你现在已经有：

```text
native_mlx_trace.log
```

这是非常好的基础。

下一步不要只记录：

```text
Inference start
TTFT
Prefill
Decode
```

而要让每一次状态变化都留下统一 Trace。

例如：

```text
[LIFECYCLE]

request=req-001
generation=gen-001
session=session-001

CREATED
   ↓
QUEUED
   ↓
RUNNING
   ↓
PREFILLING
   ↓
KV_ESTABLISHED
   ↓
DECODING
   ↓
STREAMING
   ↓
COMPLETING
   ↓
COMPLETED
   ↓
RELEASING
   ↓
RELEASED
```

每个事件至少带：

```text
timestamp
requestID
generationID
sessionID
streamID
agentID
state
event
reason
memory
KV size
```

例如：

```text
17:25:31.102

LIFECYCLE
event=STATE_TRANSITION

request=req-7F31
generation=gen-A821
session=session-C91A
stream=stream-55E2
agent=agent-03

from=DECODING
to=STREAMING

kvTokens=8192
memory=18.7GB
```

结束时：

```text
17:25:46.821

LIFECYCLE
event=RELEASED

request=req-7F31
generation=gen-A821
session=session-C91A

reason=completed

kvTokens=0
memory=9.4GB
activeTasks=0
activeSessions=0
```

这时候你就可以真正验证：

> **“一个请求结束之后，Runtime 是否真的归零。”**

---

# 9. 再加一个 Runtime Invariant Checker

这一步会让它从“有日志”进入真正的**可证明**阶段。

建立：

```swift
RuntimeInvariantChecker
```

定期或者每次关键状态转换检查：

### Invariant 1

```text
RELEASED request
    ⇒
no active GenerationTask
```

### Invariant 2

```text
RELEASED task
    ⇒
no active Stream
```

### Invariant 3

```text
released Session
    ⇒
no attached KV
```

### Invariant 4

```text
active GenerationTask
    ⇒
valid Session
```

### Invariant 5

```text
stream CLOSED
    ⇒
cannot emit token
```

### Invariant 6

```text
RELEASED
    ⇒
no future state transition
```

### Invariant 7

```text
Agent EXITED
    ≠
Runtime RELEASED
```

这一条尤其重要。

---

# 10. 最后做生命周期测试矩阵

这个阶段不能只测：

> 正常请求能不能生成。

必须测试：

| 场景                | 预期         |
| ----------------- | ---------- |
| 正常完成              | RELEASED   |
| 用户取消              | RELEASED   |
| Agent 退出          | RELEASED   |
| Client 断开         | RELEASED   |
| Stream error      | RELEASED   |
| Model error       | RELEASED   |
| Prefill error     | RELEASED   |
| Decode error      | RELEASED   |
| OOM               | RELEASED   |
| Timeout           | RELEASED   |
| Tool call 中断      | RELEASED   |
| KV reuse 失败       | RELEASED   |
| Session 过期        | RELEASED   |
| 重复 cancel         | 不崩溃        |
| 重复 release        | 不崩溃        |
| stream 重复 close   | 不崩溃        |
| token after close | 丢弃 + Trace |

最终应该得到一个非常简单的原则：

> **无论发生什么，活跃 Runtime 最终都必须收敛到 0 个不可达对象。**

---

# 我建议你实际按照这个顺序改

不要一次把整个项目推翻。

建议分 6 个 Commit：

```text
Commit 1
Lifecycle Model
↓
定义 Request / Task / Session / KV / Stream / Agent
以及 ID 和 Owner 关系
```

```text
Commit 2
State Machine
↓
RuntimeState
StateTransition
合法迁移表
Invalid Transition
```

```text
Commit 3
Lifecycle Coordinator
↓
统一 terminate()
统一 cancel()
统一 release()
```

```text
Commit 4
Stream State Machine
↓
OPEN / EMITTING / FINISHING / CLOSED
解决重复终止和重复 </think>
```

```text
Commit 5
Lifecycle Trace
↓
所有对象状态变化统一写入 Trace
```

```text
Commit 6
Invariant + Stress Test
↓
正常 / cancel / error / disconnect / OOM / agent exit
全部验证最终 RELEASED
```

---

# 最终目标应该长这样

以后我们分析一条 SimiGo 请求，不应该再靠几十行杂乱日志猜。

应该可以直接看到：

```text
┌──────────────────────────────────────────────┐
│ request=req-001                              │
├──────────────────────────────────────────────┤
│ CREATED       17:25:01.002                   │
│ QUEUED        17:25:01.003                   │
│ RUNNING       17:25:01.005                   │
│ PREFILL       17:25:01.012                   │
│ KV_ESTABLISH  17:25:02.102                   │
│ DECODING      17:25:02.103                   │
│ STREAMING     17:25:02.110                   │
│ COMPLETING    17:25:18.231                   │
│ COMPLETED     17:25:18.232                   │
│ RELEASING     17:25:18.233                   │
│ RELEASED      17:25:18.240                   │
├──────────────────────────────────────────────┤
│ Task:    released                            │
│ Session: released                            │
│ Stream:  closed                              │
│ KV:      0 tokens                            │
│ Agent:   detached                            │
│ Memory:  returned                            │
└──────────────────────────────────────────────┘
```

然后如果 Agent 17:25:10 就退出：

```text
Agent EXIT
   ↓
Runtime detects orphaned relationship
   ↓
CANCELLING
   ↓
DRAINING
   ↓
RELEASING
   ↓
RELEASED
```

这时候 **SW 指标一定应该下降**；如果没下降，Invariant Checker 直接报：

```text
RUNTIME INVARIANT VIOLATION

request=req-001

state=RELEASED

but:
activeTask=1
kvTokens=8192
memoryRetained=4.2GB
```

这才是我们要达到的“**严格、可证明、可追踪**”。

---

## 对 SimiGo 来说，我认为第一刀应该从这里下

**不要先改 KV。也不要先改 StreamTokenFilter。**

先建立这 4 个基础件：

```text
RuntimeIdentity
        +
RuntimeState
        +
RuntimeStateMachine
        +
RuntimeLifecycleCoordinator
```

然后让现有的：

```text
NativeMLX
KV Runtime
Session Runtime
Protocol Runtime
StreamTokenFilter
Agent
```

逐步接入它。

这样不会破坏你现在已经做好的 **Physical KV / Prefix Reuse / MLX lazy graph / Memory Runtime**，而是给它们上面增加一层真正的 **Lifecycle Control Plane**。

**这会是 SimiGo 从“工程原型”迈向“可长期运行 Runtime”的关键一次架构收敛。**
