# Tool Governance Contract（P1-3 定义稿）

日期：2026-09-12
状态：**v1 定版（2026-09-12 四项裁决收紧）**——契约定稿，进入实现。本文件只定义契约，不含实现。

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
| `generation_id` | Runtime 内**一次模型生成**的标识 | **v1 定版：恒等于 request_id**；不定义派生规则；一请求多代（`parent_generation_id`）留待 v2 |
| `tool_call_id` | **一次工具调用**的标识（模型输出 id；缺失时 Runtime 生成） | 稳定，贯穿验证→派发→结果全链 |
| `timestamp` | 事件时间 | — |
| `event` | 事件类型（下表） | 封闭枚举 |

**核心组合是 `generation_id + tool_call_id`**：一次生成内的多个工具调用
各自拥有独立 tool_call_id，据此可无损重放整条 agent 链。

## 事件与状态转移

六个 Runtime 事实事件：

```text
REQUESTED
   ↓
VALIDATED
   ↓
 ┌───────────────┐
 │               │
REJECTED      DISPATCHED
（终态）           ↓
            ┌──────┴──────┐
            ↓             ↓
         RESULT         FAILED
       （终态·成功）   （终态·失败）
            ↓
      continuation
```

### 转移规则

1. **每个 `TOOL_REQUESTED` 恰好到达一个终态**
   （REJECTED / RESULT / FAILED 三选一）。不存在无终态的工具调用——
   出现即 Runtime 挂起/泄漏，属可检测违规。
2. **VALIDATED 不可跳过**。模型输出了 tool call ≠ 工具被执行；
   拒绝也必须先经过验证阶段（验证后才有依据给出拒绝 code）。
3. **DISPATCHED 前必须 VALIDATED**；RESULT/FAILED 前必须 DISPATCHED。
4. **取消归属由取消时所处生命周期决定**，实现不得随意选择：
   - 工具**尚未 dispatch** → `TOOL_REJECTED(code=cancelled)`
     （governance rejection）；
   - 工具**已经 dispatch** → `TOOL_FAILED(code=cancelled)`
     （execution failure）。
   不设独立 TOOL_CANCELLED 事件，保持事件集最小。
5. **核心不变量**：`1 REQUESTED → 1 VALIDATED → exactly 1 终态`。
   任何没有终态的 TOOL_REQUESTED 都是 Runtime 可诊断的异常。
6. **工具事件必须幂等可识别**：`(request_id, generation_id, tool_call_id,
   event)` 唯一标识一次事件；`tool_call_id` 是一次模型 tool call 的稳定
   身份——Runtime 不得因事件重放而生成新的 tool call identity
   （为未来 exactly-once dispatch 留出基础；v1 不解决重复执行）。
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

**REJECTED 与 FAILED 的 code 集合互不重叠**：REJECTED 是治理阶段
决定"不允许/不能执行"；FAILED 是已派发后的执行失败。

**TOOL_REJECTED 允许的 reason.code**（治理阶段）：

| code | 语义 |
|---|---|
| `unknown_tool` | 模型调用了未声明的工具（官方 `undeclared_tool` 映射目标） |
| `invalid_arguments` | 参数不符合声明 schema |
| `capability_not_allowed` | 工具已声明，但当前模型/会话不具备调用资格 |
| `policy_denied` | 策略层拒绝（扩展位） |
| `runtime_busy` | Runtime 过载/排队上限拒绝 |
| `cancelled` | dispatch 前被取消（governance rejection） |
| `timeout` | 治理/验证阶段超时 |

**TOOL_FAILED 允许的 reason.code**（执行阶段）：

| code | 语义 |
|---|---|
| `execution_error` | 工具执行器本身失败 |
| `cancelled` | dispatch 后被取消（execution failure） |
| `timeout` | 执行超时 |

语义边界：

- `unknown_tool`：模型调用了未声明的工具（现 rejectedToolCall
  `reason=undeclared_tool` 的映射目标）。
- `invalid_arguments`：参数不符合声明 schema。
- `capability_not_allowed`：工具已声明，但当前模型/会话不具备调用资格。
- `policy_denied`：策略层拒绝（未来扩展位）。
- `timeout`：工具执行超时。
- `cancelled`：生成或会话在工具生命周期内被取消。
- `runtime_busy`：Runtime 过载/排队上限拒绝。
- `execution_error`：**仅属 TOOL_FAILED**——工具执行器本身失败，
  不入 REJECTED code 表；与治理拒绝严格区分。

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
| TOOL_RESULT | `duration_ms`、`result`（`inline` 或 `reference` 形态，语义见下） |
| TOOL_FAILED | `reason{code,message}`、`duration_ms` |

**TOOL_RESULT.result 形态语义**（契约只定两种形态，不定阈值）：

```text
result
├── inline      结果内联于事件
└── reference   结果由引用定位
```

若采用 `reference`，契约规定**语义**：引用必须能唯一定位该 tool result，
且 Runtime 在生命周期内能解析它，或明确报告 `reference unavailable`。
内联阈值、reference backend、存储位置、TTL、序列化格式 → 全部留给实现。

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

## 开放问题 → 已裁决（2026-09-12）

1. `execution_error` → **仅属 TOOL_FAILED**，不入 REJECTED code 表。
2. 取消终态 → 保留 `TOOL_FAILED(code=cancelled)`，不设独立事件；
   归属由生命周期位置决定（见转移规则 4）。
3. `generation_id` → v1 恒等于 request_id，不定义派生规则；
   多代派生留待 v2。
4. TOOL_RESULT payload → 契约只定 inline/reference 语义，
   阈值/后端/序列化留给实现。
