# Tool Governance Contract（P1-3 定义稿）

日期：2026-09-12
状态：**定义稿（待审）**——审过事件、状态转移、reason code、关联键与
backend 边界后再进入实现。本文件只定义契约，不含实现。

## 定位与边界

Tool Governance 是 **SimiGo Runtime 层能力**，不属于任何 backend：

```text
                Agent Runtime
                     │
             Tool Governance
                     │
        ┌────────────┴────────────┐
        ↓                         ↓
    NativeMLX                  Llama.cpp
        │                         │
        └────── same contract ────┘
```

- Backend 只负责一件事：**声明"模型产生了什么 tool call"**（原始形态）。
- Tool Governance 负责：这个 tool call **是否允许、是否有效、是否执行、
  执行结果是什么、失败原因是什么**。
- 未来接入 Llama.cpp（或第三个 backend）时，复用同一契约，不重写治理层。

## 关联键（correlation keys）

每个事件携带完整关联键，使一次 Agent loop 可完整回放：

| 键 | 语义 | 稳定性 |
|---|---|---|
| `request_id` | HTTP 请求标识（现有 requestId） | 稳定 |
| `session_id` | 会话标识（execution session） | 稳定 |
| `generation_id` | Runtime 内**一次模型生成**的标识 | 稳定；当前等于 request_id，预留一请求多代演进的演进空间 |
| `tool_call_id` | **一次工具调用**的标识（模型输出 id；缺失时 Runtime 生成） | 稳定，贯穿验证→派发→结果全链 |
| `timestamp` | 事件时间 | — |
| `event` | 事件类型（下表） | 封闭枚举 |

**核心组合是 `generation_id + tool_call_id`**：一次生成内的多个工具调用
各自拥有独立 tool_call_id，据此可无损重放整条 agent 链。

## 事件与状态转移

六个 Runtime 事实事件：

```text
TOOL_REQUESTED
      │
      ▼
TOOL_VALIDATED
      │
 ┌────┴──────────────┐
 ▼                   ▼
TOOL_REJECTED     TOOL_DISPATCHED
（终态）                │
                       ▼
                 TOOL_RESULT（终态·成功）
                       │
                  ┌────┴────┐
                  ▼         ▼
           continuation  TOOL_FAILED（终态·失败）
```

### 转移规则

1. **每个 `TOOL_REQUESTED` 恰好到达一个终态**
   （REJECTED / RESULT / FAILED 三选一）。不存在无终态的工具调用——
   出现即 Runtime 挂起/泄漏，属可检测违规。
2. **VALIDATED 不可跳过**。模型输出了 tool call ≠ 工具被执行；
   拒绝也必须先经过验证阶段（验证后才有依据给出拒绝 code）。
3. **DISPATCHED 前必须 VALIDATED**；RESULT/FAILED 前必须 DISPATCHED。
4. **取消**：任意非终态被取消 → 以 `TOOL_FAILED(reason.code = cancelled)`
   收口（不设独立 TOOL_CANCELLED 事件，保持事件集最小；
   取消原因由 code 表达）。
5. **TOOL_FAILED ≠ model_execution_error**：前者表示"Runtime 正确执行了
   治理，但工具本身执行失败"；后者是模型生成层的失败。两者永不相邻
   混用，LC 分类与工具事件分类相互独立。

## reason 结构与封闭 code 表

`reason` 不做自由文本：

```text
reason
├── code      稳定机器语义（封闭枚举，新增需版本化）
└── message   人类诊断信息（可自由表述，不参与程序判定）
```

| 事件 | 允许的 reason.code |
|---|---|
| TOOL_REJECTED | `unknown_tool` / `invalid_arguments` / `capability_not_allowed` / `policy_denied` |
| TOOL_FAILED | `execution_error`（提案，见开放问题）/ `timeout` / `cancelled` / `runtime_busy` |

语义边界：

- `unknown_tool`：模型调用了未声明的工具（现 rejectedToolCall
  `reason=undeclared_tool` 的映射目标）。
- `invalid_arguments`：参数不符合声明 schema。
- `capability_not_allowed`：工具已声明，但当前模型/会话不具备调用资格。
- `policy_denied`：策略层拒绝（未来扩展位）。
- `timeout`：工具执行超时。
- `cancelled`：生成或会话在工具生命周期内被取消。
- `runtime_busy`：Runtime 过载/排队上限拒绝。
- `execution_error`（提案）：工具执行器本身失败——与治理拒绝严格区分。

## 事件载荷 schema

公共信封（所有事件）：

```text
event, timestamp, request_id, session_id, generation_id, tool_call_id
```

各事件附加字段：

| 事件 | 附加字段 |
|---|---|
| TOOL_REQUESTED | `tool`（名称）、`arguments_raw`（模型原始 JSON 字符串，不修饰） |
| TOOL_VALIDATED | `arguments`（归一化后）、`schema_ref` |
| TOOL_REJECTED | `reason{code,message}` |
| TOOL_DISPATCHED | `executor`、`timeout_policy` |
| TOOL_RESULT | `duration_ms`、`result_ref`（大 payload 引用/截断，不内联） |
| TOOL_FAILED | `reason{code,message}`、`duration_ms` |

## 观测出口（v1）

结构化 trace 行，对齐现有 `[MLX]` / `[LC]` / `[MEM]` 风格：

```text
[TOOL] event=TOOL_REJECTED r=req-x gen=g-x tc=c-1 tool=WebSearch code=unknown_tool
```

HTTP/SSE 层是否透出治理事件 → 非目标（Responses 层的 tool 事件已由
官方事件承担；governance 事件是 Runtime 事实层）。

## 与现有实现的映射

| 现有事实 | 契约事件 |
|---|---|
| ChatSession `.toolCall(let call)` | TOOL_REQUESTED → VALIDATED → DISPATCHED → RESULT |
| ChatSession `.rejectedToolCall(reason=undeclared_tool)` | TOOL_REQUESTED → VALIDATED → REJECTED(`unknown_tool`) |
| `GenerationCompletionInfo` | RESULT 载荷的 duration/usage 来源 |
| LC `RELEASED` | 生命周期关联键的 request_id 来源 |

## 非目标（v1）

- 工具执行器实现、权限/策略引擎、重试策略
- HTTP/SSE 治理事件透出
- 跨请求工具结果缓存

## P1-3 DONE 判据

1. 一次完整 agent loop 的事件序列可从结构化日志**无损回放**；
2. 每个 TOOL_REQUESTED 恰对应一个终态事件（可断言）；
3. reason.code 为封闭枚举，全部拒绝/失败路径携带稳定 code；
4. 契约接口与 backend 解耦（NativeMLX 之外可有第二实现编译通过）。

## 开放问题（待审裁决）

1. `execution_error` 是否入 code 表（工具执行器失败 vs 治理拒绝的区分）。
2. 取消终态：`TOOL_FAILED(code=cancelled)` vs 独立 `TOOL_CANCELLED` 事件
   ——本文选择前者（事件集最小），如需对外语义更明确可改后者。
3. `generation_id` 演进：当前等于 request_id；一请求多代（服务端 agent
   循环内多轮生成）时如何派生子 id。
4. TOOL_RESULT 大 payload 的内联阈值与引用格式。
