# Agent 接入说明（首版支持范围）

> **状态快照（2026-11-05）**：本文按当时主线源码树描述 Agent 接入合同，不代表
> v2.2.4（build 34）候选 DMG 的实际包含范围。build 34 固定候选提交为 `e21d8f7b`，
> 不含后续进入主线的 Qoder collection bridge；候选产物与当前主线的差异见根目录
> [RELEASE.md](../RELEASE.md)。
>
> 自动复用短路（`HTTPServerChat.reusableAnswer`）、MCP 生命周期工具与 GGUF 受管入口
> 已在 v2.2.3 及更早版本的安装包上验收；`/v1/models` 自举声明（#149，§2.1.1）与
> Chat `reasoning_content` 透出（#148，§2.8）是 v2.2.3 之后新增的能力，当时只在
> 隔离根内由测试跑通，安装版运行时取证留给后续发行。
>
> 2026-11-03 的源码变更：产品云端 provider 代理与外部轮次自动捕获路径已删除。信息空间宿主可在不加载模型时提供 `/mcp`。当时的 v2.2.4/build 34 固定本地候选曾验证 App 启动拉起宿主、模型服务接管 API 端口及停止后宿主回落；该候选不是当前 main 的发行产物，相关证据仅适用于候选快照（见根目录 `RELEASE.md`）。
> 本文描述 2026-11-05 主线源码树的接入合同，不表示所有客户端 / wire 已完成安装版 E2E。带自有云端 API 的 Agent 经 MCP 显式调用 SimiGo；SimiGo 不代理其模型请求。

## 1. 什么算「接入」

接入指请求经过 SimiGo 的受管入口，或执行生命周期经过 SimiGo 的 MCP 接口：

| 方式 | 适用对象 | 模型调用发生在 | SimiGo 记录什么 |
| --- | --- | --- | --- |
| A. 本地模型 OpenAI-compatible 入口 | 能自定义 base URL 的本地/自托管 Agent | SimiGo 内部（本地引擎） | 每轮的 ES demand、IS 检索、结算、身份绑定、advancement |
| B. MCP 生命周期 | 继续使用自身云端 API 的 Agent | SimiGo 外部（Agent 自己的云端） | 由 `simigo_es_begin` / `settle` / `fail` 显式写入的结算与失败审计 |

**不构成接入**：Agent 在自己的进程里直接加载模型、完全绕过 SimiGo 的 API 或适配层。
SimiGo 无法仅凭「它用的是本地模型」接管这类执行 —— 这是首版声明的不支持边界，不是待修缺陷。

## 2. 方式 A：本地模型 OpenAI-compatible 入口

### 2.1 端点

- Base URL：`http://127.0.0.1:<APIPort>/v1`（默认 `8000`，设置项 `APIPort`，环境变量 `SIMIGO_PORT`）
- 本地监听默认绑定 `127.0.0.1`；不要在未加 TLS 的情况下暴露到回环之外。

| 路由 | 类别 | 行为 |
| --- | --- | --- |
| `POST /v1/chat/completions`、`/chat/completions` | 受管 | 生成前解析 ES demand → 检索 IS → 命中即 0 调用复用；成功后原子结算 |
| `POST /v1/responses` | 受管 | 同上；另有显式消费（`settlement_consumption`，非流式 opt-in）与受管续跑字段 |
| `POST /v1/completions`、`/completions` | **声明的兼容旁路** | 不做 ES 前置、不做 IS 复用、不写结算；wire 上始终带 `simigo: {"managed": false, "reason": "legacy_text_completions"}` |
| `GET /v1/models`、`GET /v1/models/<id>` | 只读 | 列模型；列表响应顶层带 `simigo` 自举声明（§2.1.1） |

`/v1/completions` 的旁路是声明行为而非遗漏：它的 prompt 是续写文本，不是信息需求。
把 `managed=false` 写进响应体，使这个边界可从外部核验。

### 2.1.1 自举发现：`GET /v1/models` 的 `simigo` 对象（#149）

`GET /v1/models` 仍是标准模型列表；响应顶层另有一个 `simigo` 对象，供 Agent 在第一次
请求前发现「这是 SimiGo、能保留什么、如何声明作用域」。忽略该键的客户端看到的 `data`
与模型对象与之前完全相同。

| 键 | 内容 |
| --- | --- |
| `schema_version` | 自举协议版本（当前 `1`），与数据库 schema 无关 |
| `capabilities` | `es`、`is`（含 `search` 与 `mcp` 路由）、`memory_kv_cache`、`external_api_intake`（云端代理删除后唯一通道是 `mcp_settle`） |
| `request_scopes` | 声明键（`metadata.simigo_request_scope`、`client_metadata.simigo_request_scope`、header `X-SimiGo-Request-Scope`）、内部值（`internal` / `internal_operation` / `internal-op`）、默认 `ordinary`，以及三条 wire 的受管状态 |
| `carrier` | `kv_cache.mode = memory` 与 `disk_persistence`（两个 KV 持久化开关的实时值）；`information_space` 为磁盘对象存储 |
| `runtime_status` | `health`（`ok` / `unavailable`）与 `observed_at`（ISO-8601 观测时间） |

边界：

- **只发现，不授权。** `simigo` 不读取 ES/IS，不返回计数、路径、数据库位置、PID 或
  校准数据；它不是第二套结算或检索权威。
- `runtime_status` 是探针结果快照。`observed_at` 是判断它是否过期的唯一依据；不要把
  上一次读到的 `ok` 当作当前可用性。
- 独立信息空间宿主（§3.1）的 `/v1/models` 也带这个对象；它的 `health` 反映宿主监听器
  自身是否在运行（`ok`），不代表任何模型可用 —— 该宿主的推理路由一律拒绝。
- **不要假设所有 OpenAI 客户端都会请求 `/v1/models`。** 不读模型列表的客户端仍可
  直接调用受管路由，或走 §3 的 MCP；本文档与 MCP 配置是兼容补充，不是唯一的自举渠道。

**前提：受管治理只在本地引擎路径发生。** SimiGo 不再代理外部供应商：云端后端配置、
API Key 与远端转发路径已删除，这些推断路由只由本地引擎（MLX 或 llama.cpp）承接，
始终解析 demand、复用、写结算。带着自有云端 API 的 Agent 不经过这些路由，
应视为未接入，只能走方式 B（见 §3.1 的独立信息空间宿主）。

### 2.2 每轮自动发生什么

调用方不需要额外字段。每次受管请求：

1. 取最后一条 `user` 消息（裁剪空白）作为本轮 query；取不到则本轮不进入治理，直接生成。
2. 按作用域检索 IS 并解析 demand，生成的用户消息与（可选）IS 上下文块一起进入模型。
3. 生成前检查能否复用（见 2.4）；命中则不调用模型。
4. 生成成功后写入一条权威事务：子 ES 状态 + 结算（含 payload 摘要）+ 生产者身份绑定 + advancement。

### 2.3 身份与作用域

作用域决定「同一问题」的判定范围。解析顺序（JSON 字段优先，其次 header）：

- **会话**：`session_id` → `conversation_id` → `client_metadata.session_id` → `metadata.session_id`
  → header `x-simigo-session` → header `x-session-id`
- **Agent**：`agent_id` → header `x-simigo-agent` → header `x-agent-id` → `agent`
  → `metadata.agent_id` → `metadata.agent`
- **Responses 线程**：`thread_id` → `threadId` → `client_metadata.thread_id` → `metadata.thread_id`
  → header `x-codex-turn-metadata`（其内 `thread_id` 字段）

Chat 的作用域 = 显式会话；否则由 `agent_id` + 会话开头的 system/user 消息摘要派生
（`info-<digest>`），同一段对话每轮得到同一作用域。**作用域里不含逐请求 UUID**。

Responses 的作用域 = 显式会话 → `codex-thread:<thread>` → 同样的消息摘要派生。
只给 `previous_response_id` 的 Agent 会解析出父会话，不会每轮换作用域。

> 请求带上稳定的会话标识，才能获得跨轮次的「同一问题」判定。不带标识时，作用域由
> 开头消息决定 —— 只要 Agent 每轮重发相同开头，仍然稳定。

### 2.4 复用的四个条件（全部满足才复用）

1. 该作用域内这个**完全相同的问题**（裁剪空白后逐字相等）已有 `ADVANCED` 的 demand；
2. 回答结算仍然 `valid`；
3. 该 demand 若有检索结算，其 `validity` 也仍为 `valid`（这是捕捉「来源文件已变」的依赖检查）；
4. 记录的生产者 model / tokenizer 与当前引擎 `evaluate(...) == .ok`；缺任一项即拒绝。

任一条件不满足都走正常生成，不做「尽力而为」的近似回答。

> **当前实现审查注记（2026-11-05，尚待实施）**：上述四项是复用应满足的合同条件，
> 但本轮源码静态审查发现，自动答案 shortcut 尚未显式要求历史答案绑定的
> `demand_id` 与本轮 `resolve` 得到的 demand identity 一致。当前信息空间若因新增
> committed chat row、文件或摘要而变化，存在旧答案仍满足历史有效性门槛却被复用的风险。
> 该路径尚无真实机器复现，也未修复；在修复与回归验收前，不应把本节理解为已证明
> 对所有信息空间变化均能拒绝旧答案。跟踪状态见
> [Open Problems #1](knowledge/open-problems/README.md)。

**不复用的已知情况**：Chat 请求带非空 `tools` 时跳过复用短路（工具轮不当作可复用问答）；
这类轮次仍然前置检索并结算。Responses 的复用短路同样跳过工具续轮：请求尾部（最后一条
user 之后）含 `role: tool` 项，或父响应 output 含 `function_call` 项时 `isToolContinuation`
为真，两条 Responses 路径都直接进入生成
（`SimiGo/Protocol/HTTPServerResponses.swift:963`、`:1313`、`:1855`）。

> 原缺陷 **D-1**（Responses 在工具续轮上仍可命中复用，返回不带 `function_call` 的旧文本、
> 截断工具循环）已由上述守卫关闭。原始登记与三选项分析保留在
> `research/agent-runs/simigo-es-is-realmodel-20261026/STAGE1-GAP-MATRIX-20261028.md` §4.8 / §4.16。

### 2.5 线上可核验的标记

| 路径 | 标记 |
| --- | --- |
| Chat 非流式 | 响应体顶层 `simigo: {answer_reuse: true, model_calls: 0, settlement_id, demand_id, source_state_id}` |
| Chat 流式 | 首个 `chat.completion.chunk` 的 `delta.content` 带结算文本，同一 chunk 顶层带上述 `simigo` 块；随后 `finish_reason: "stop"` 与 `data: [DONE]`，不发模型输出 |
| Responses（流式/非流式） | `response.simigo` 同形；流式合成 `response.created → output_item.* → response.completed` |
| Completions | `simigo: {managed: false, reason: "legacy_text_completions"}` |

复用是**读**：不写新结算、不建新的 ES 状态；只追加一条 assistant 会话行和一条
`information_reuse_events` 消费边（`model_calls = 0`）。

### 2.6 诊断开关

| 环境变量 | 默认 | 作用 |
| --- | --- | --- |
| `SIMIGO_IS_ANSWER_REUSE` | 开（`!= "0"`） | 置 `0` 关闭复用短路，用于证明读数来自模型而非 IS |
| `SIMIGO_IS_CONTEXT_FREEZE` | 开（`!= "0"`） | 置 `0` 恢复每轮新鲜注入块（诊断前缀漂移用） |

> 「默认开」与已登记的裁定 R1-A（「默认关闭」）不一致，默认态**尚未裁定**。在裁定前不要
> 按默认关闭撰写对外说明。

### 2.7 鉴权边界

- **明文回环监听**：受管路由不要求 LOCALB 证明（Owner 裁定 2026-10-26）。这是本地工具面，
  响应带 `unprotected-by-LOCALB` 语义。任何非回环暴露都必须走 TLS。
- **TLS 监听**：保留完整 B3 证明链。签名请求**不接受**用 header 选身份（`x-simigo-agent`、
  `x-session-id`、`x-codex-turn-metadata` 等一律拒绝）；身份只能来自签名 JSON 字段。
- **信任前提**：当前按「单机、单人、局域网、生产环境可信」运行；多人多权限所需的是
  SimiGo 侧的认证与写闸，不属于 IS 语义。裁定见
  `docs/decisions/TRUST_BOUNDARY_SINGLE_USER_VS_MULTI_USER_20261112.md`。

### 2.8 `reasoning_content`（#148）

开启 thinking 的 GGUF 模型会在引擎 SSE 里输出 `delta.reasoning_content`。SimiGo 把它
原样转到 Chat 响应的独立字段：

| wire | 形态 |
| --- | --- |
| Chat 非流式 | `choices[0].message.reasoning_content`（仅当模型实际产生非空推理时存在） |
| Chat 流式 | `choices[0].delta.reasoning_content`，与 `delta.content` 按到达顺序交错，互不混用 |

口径：

- 只透出模型自己输出的推理，**不伪造、不把 `content` 复制进来**；模型没给就没有该字段。
- 不进入普通聊天 `content`、不进入 IS 结算、不进入 IS 检索索引、不作为 ES 已完成结果。
- 默认不持久化：推理只在本次响应生命周期内存在，会话账本、结算与检索都只保存答案。
  复用轮没有新的引擎推理，因此重放不带该字段，也不会补造一个。
- 独立长度上限 64 KiB（65,536 字符）。超过后保留前缀并在 `simigo.reasoning` 标记：
  `{"truncated": true, "limit_chars": 65536}`；流式与非流式同形。
- 推理截断不改变答案自己的终止判定：`finish_reason` 与 `simigo.completion=capped`
  仍由引擎的终止原因决定；截断的推理不会被当成完整交付，完整答案也不因此改判。

Responses 与 `/v1/completions` 目前不暴露该字段：Responses 的 reasoning item 合同尚未
纳入；`/v1/completions` 是声明的 legacy 旁路，wire 上没有该字段。

## 3. 方式 B：云端 Agent 经 MCP

### 3.1 传输

- 端点：与 HTTP 入口同一 host:port 的 `POST /mcp`；`GET /mcp` 被拒绝（不发起服务端流）。
- **独立信息空间宿主**：当前候选由 App 启动流程自动拉起一个**不加载模型**的监听器
  （`modelId = simigo-information-space`，占用同一个 API 端口）；模型服务启动时接管该端口，
  停止模型后自动回落到宿主。宿主持有 HTTP listener、`POST /mcp` 与 IS 读路由，不需要先加载
  MLX / llama.cpp，也不需要云端后端配置。其推理路由一律拒绝（`backendNotAvailable`）。
  带着自有云端 API 的 Agent 可直接对接该宿主，不必先加载本地模型。
- 协议：JSON-RPC 2.0，无状态 Streamable-HTTP 子集；单条、批量、通知均可；
  通知返回 `202`。`initialize` 返回 `protocolVersion: "2025-06-18"`，能力只有 `tools`。
- 方法与 HTTP 路由共用同一个 `ESISDatabase` / `InformationLoop`，不存在第二套
  数据库或第二套结算权威。

### 3.2 十个工具

| 工具 | 必填 | 作用 |
| --- | --- | --- |
| `simigo_is_search` | `query` | 解析需求并返回摘要校验过的可引用片段；相同需求复用已结算结果 |
| `simigo_is_status` | — | 载体状态：schema 版本、对象数、索引/依赖条目、完整性计数 |
| `simigo_roots_list` | — | 列出已登记的工作根 |
| `simigo_root_register` | `path` | 登记绝对目录并建索引（只存定位符 + 摘要 + 大小，不复制文件字节） |
| `simigo_is_reconcile` | — | 重新推导已登记根的有效性；根缺失只标记，不清空索引 |
| `simigo_is_settlement` | `settlement_id` | 读回一条结算：payload、`payload_sha256`、有效性、绑定、依赖修订 |
| `simigo_es_begin` | `model`、`tokenizer` | 开始（或恢复）一次执行；不记录任何结果 |
| `simigo_es_settle` | `state_id`、`model`、`tokenizer`、`output` | 提交外部结果，按同一结果合同封装并绑定身份 |
| `simigo_es_fail` | `state_id`、`detail` | 追加式记录失败；**永不产生结算** |
| `simigo_chat_round` | `session_id`、`request_id`、`user`、`assistant`、`turn_index` | 把外部模型写的一轮问答以 external 来源写入会话，并在同一次调用里提升为 `committed`；幂等键是（session, request） |

### 3.2.1 轮次账本（`turn_index`）

MCP 工具由调用方自己决定调不调，协议里没有任何东西能让 SimiGo 知道"这一轮没进来"。`turn_index` 是这个缺口的唯一可验证解：

- 调用方在本会话内对每一轮按 **1、2、3…** 连续编号，随每轮一起传；
- SimiGo 把（session, turn_index）写进 `chat_turn_ledger`，返回 `turn_ledger`
  （`entered` 已进入轮数、`highest` 最大轮号、`missing` 缺失轮号、`continuous`）；
- 跳号即缺口：第 4 轮没调，第 5 轮到达时 `missing=[4]`，菜单栏读数立刻显示
  "轮次 4 进入 / 缺 1（4…）"。

不传 `turn_index` 时工具行为不变（入库照常），但账本无法判断缺口——**"每轮都进入"
只有传了编号才能被检查，否则只能被声称**。重复传同一轮号是幂等的，不会改写已有行。

账本的主键是（session_id, turn_index）。两个 agent 若共用同一个 `session_id`，各自的
第 3 轮会撞在同一个槽位上：账本保留先到者，后到者**不覆盖、也不静默合并**，返回里带
`conflict=<先到者的 request_id>`。看到 `conflict` 说明命名冲突，不是轮次丢失——
给每个 agent 一个前缀（`codex-…` / `qoder-…`）即可。

### 3.3 生命周期接线

```
simigo_es_begin(model, tokenizer, [session_id, query])
  └─ 创建/恢复一个 begun-but-unsettled 的 ES state；永不返回历史答案（`reusable_answer` 恒为 null）
  └─ Agent 调用自己的云端 API 产出 output
simigo_es_settle(state_id, model, tokenizer, output,
                 [session_id, query], [demand_id + retrieval_settlement_id], [dependencies])
  或
simigo_es_fail(state_id, detail, [phase, evidence, model_calls, settlements_written])
```

### 3.4 「MCP 连通 ≠ 结果已记录」

三条判据，全部可从数据库与工具返回核验：

1. 只有 `simigo_es_settle` 会写入**可被当作回答复用**的结算：payload 含顶层 `content`，且在
   给出 `session_id`+`query`（发布一条新的已答 demand）或 `demand_id`+`retrieval_settlement_id`
   （推进该检索 demand）时被置为 `ADVANCED`；两者都不给时结算仍然权威，只是不发布已答
   demand。MCP 面当前不提供答案复用：`reusable_answer` 恒为 null，已答 demand 只会被
   Chat/Responses 的复用门在各自线上消费。`simigo_is_search` 也会写一条结算，但那是**检索结算**
   （id 为 `is-retrieval:<demand_id>`，`validation_status = IS_RETRIEVAL`，payload 是检索结果
   JSON）：demand 停在 `RESOLVED`、不产生 advancement，且复用门控要求载荷含非空顶层
   `content`，所以它只能被引用为 `retrieval_settlement_id`；
2. 只 `begin` 不 `settle` 的执行保持 begun-but-unsettled，不会出现在可复用答案里；
3. `simigo_es_fail` 只落审计，不产生结算，不改变该执行「未结算」的状态。

### 3.5 settle 的前置条件（违反即整体拒绝，不部分写入）

- 该 `state_id` 必须已经 `begin`；未开始的执行不能结算。
- `model` 必须与 begin 时的模型身份一致；换模型必须新开一个 state。
- 一个 state 只结算一次。
- `demand_id` 与 `retrieval_settlement_id` 必须**同时给或同时不给**；给了检索结算，它必须仍为 `valid`。
- `dependencies[].content_address` 必须是载体中**已封存的对象 id**（例如某条先前结算的
  `payload_sha256`）；未封存的地址会让整次 settle 拒绝。
- 结算后的返回报告的是**库里实际提交的**依赖行，不是调用方提交的清单。
- 返回的 `state_id` 是本次结算产生的**子执行状态**，不是入参里 begin 的 `state_id`；
  继续续跑或对结果再次引用时用返回的这个值（入参的那个 state 已结算、不可复用）。

### 3.6 begin 不做答案复用（`reusable_answer` 恒为 null）

`simigo_es_begin` **从不返回历史答案**，即使同一 `session_id`+`query` 已有可复用的已结算
回答：返回值里 `reusable_answer` 恒为 null。begin 只创建（或恢复）一个 begun-but-unsettled
的 ES state；把一个已结算结果变成新 ES 的内容需要一次**显式消费**——来源结算、派生结算与
新 ES 推进三件事一起发生。若 Agent 拿到历史答案提示就直接跳过模型调用而不 settle，该 state
仍是 begun-but-unsettled——把只读提示包装成已完成的 ES 消费正是 begin 不做复用的原因。
当前的显式零模型调用消费走 Responses 的 `settlement_consumption` opt-in；MCP 面未来的
零模型路径也必须以显式消费操作的形式设计，而不是恢复一个无消费语义的提示。

> 历史注记：早期版本的 begin 曾按 session+query 返回过 `reusable_answer` 只读提示（缺陷
> **D-2** 记录了 `simigo_is_search` 不接受 `session_id` 时的复用失配，已随该工具接受
> `session_id`/`request_id`/`session_ids` 而关闭，见
> `SimiGo/Protocol/HTTPServerMCP.swift`）。该只读提示行为已按 2026-11-08 合同裁定移除：
> begin 不暴露历史答案，本节与工具描述以当前代码为准。

## 4. 首版明确不支持 / 未验证

| 项 | 状态 |
| --- | --- |
| Agent 进程内直接加载模型 | 不支持接管（见 §1） |
| 任何外部模型服务作为**上游 provider**（SimiGo 去调用它们，含 Ollama / LM Studio） | 不支持（云端代理已删除；SimiGo 不再向任何外部 provider 发起请求） |
| Anthropic 原生 wire（非 OpenAI-compatible） | 不支持；这类 Agent 走方式 B |
| MCP 工具粒度鉴权 | 未做。`/mcp` 整体属 SRS-write 权限；TLS 监听需完整证明，明文回环免证明 |
| MCP 身份自证 | `model` / `tokenizer` 由调用方自报，SimiGo 无法察觉谎报；它记录的是**声明** |
| 真实第三方 Agent 端到端读取 | 未做（#100）；目前只有测试层与 stand-in 证据 |
| 跨模型复用 | 设计上永不发生（身份不匹配即拒绝）；真实引擎 A→B 换模型的读数未取 |
| 推理内容的持久化与审计 | 不支持；默认只在响应生命周期内处理，未来若需审计须单独授权的保留设计 |

## 5. 最小自检

```bash
BASE=http://127.0.0.1:8000

# A. 受管问答（同一 session 同一问题重复两次，第二次应 0 调用）
curl -s $BASE/v1/chat/completions -H 'content-type: application/json' -d '{
  "model":"local","stream":false,"session_id":"demo-1",
  "messages":[{"role":"user","content":"where is the vault"}]}' | jq '.simigo'

# B. 旁路声明（必须 managed=false）
curl -s $BASE/v1/completions -H 'content-type: application/json' -d '{
  "model":"local","prompt":"SimiGo is"}' | jq '.simigo'

# C. MCP 握手与结算读回（信息空间宿主即可满足，无需本地模型）
curl -s $BASE/mcp -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call",
       "params":{"name":"simigo_is_status","arguments":{}}}' | jq '.result'

# D. 自举发现（旧客户端忽略 simigo；新客户端读它）
curl -s $BASE/v1/models | jq '.simigo'
```

## 6. 本文件的更新触发点

- R1-A 默认态裁定落地后，改 §2.6；
- 真实第三方 Agent 端到端读取完成（#100）后，把具体已验客户端写进 §2/§3；
- 未来若引入非云端的 provider adapter，改 §4 对应行；
- 自举对象的键、`schema_version` 或 `request_scopes` 声明变化时，同步 §2.1.1；
- `reasoning_content` 的字段、上限或结算边界变化时，同步 §2.8；
- 任何路由、身份键、复用门控或 MCP 工具合同的改动，同步改对应小节。
