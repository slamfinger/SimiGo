# Agent 接入说明（首版支持范围）

> 状态（2026-10-28）：本文件描述**工作区未提交构建**（v2.2.1 + 阶段 1/2 变更）。
> 公开发布的 v2.2.1（build 30）**不包含**本文所述的自动复用短路、MCP 生命周期工具和
> completions 旁路标记 —— 这三项在 tag `v2.2.1` 上逐项核对均为 0 处。本文不代表已发布版本的能力。

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
| `GET /v1/models`、`GET /v1/models/<id>` | 只读 | 列模型 |

`/v1/completions` 的旁路是声明行为而非遗漏：它的 prompt 是续写文本，不是信息需求。
把 `managed=false` 写进响应体，使这个边界可从外部核验。

**前提：受管治理只在本地引擎路径发生。** 配置了远端后端时，这些推断路由由
`forwardToRemote` 直接转发，不解析 demand、不复用、不写结算 —— 那种模式下的 Agent
应视为未接入，只能走方式 B。

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

**不复用的已知情况**：Chat 请求带非空 `tools` 时跳过复用短路（工具轮不当作可复用问答）；
这类轮次仍然前置检索并结算。Responses 两条路径的复用判定不检查 `tools`。

> 这条不对称已升级为潜在缺陷 **D-1**：Responses 在工具续轮（`function_call_output`）上仍可命中复用，
> 返回不带 `function_call` 的旧文本，工具循环被截断。登记与待裁定选项见
> `research/agent-runs/simigo-es-is-realmodel-20261026/STAGE1-GAP-MATRIX-20261028.md` §4.8。

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

## 3. 方式 B：云端 Agent 经 MCP

### 3.1 传输

- 端点：与 HTTP 入口同一 host:port 的 `POST /mcp`；`GET /mcp` 被拒绝（不发起服务端流）。
- 协议：JSON-RPC 2.0，无状态 Streamable-HTTP 子集；单条、批量、通知均可；
  通知返回 `202`。`initialize` 返回 `protocolVersion: "2025-06-18"`，能力只有 `tools`。
- 方法与 HTTP 路由共用同一个 `SimiGoESISDatabase` / `SimiGoInformationLoop`，不存在第二套
  数据库或第二套结算权威。

### 3.2 九个工具

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

### 3.3 生命周期接线

```
simigo_es_begin(model, tokenizer, [session_id, query])
  └─ reusable_answer 非 null  → 可直接跳过自己的云端调用（只读，不写任何东西）
  └─ reusable_answer 为 null  → 调用自己的云端 API 产出 output
simigo_es_settle(state_id, model, tokenizer, output,
                 [session_id, query], [demand_id + retrieval_settlement_id], [dependencies])
  或
simigo_es_fail(state_id, detail, [phase, evidence, model_calls, settlements_written])
```

### 3.4 「MCP 连通 ≠ 结果已记录」

三条判据，全部可从数据库与工具返回核验：

1. 只有 `simigo_es_settle` 会写入**可被当作回答复用**的结算：payload 含顶层 `content`，且在
   给出 `session_id`+`query`（发布一条新的已答 demand）或 `demand_id`+`retrieval_settlement_id`
   （推进该检索 demand）时被置为 `ADVANCED`；两者都不给时结算仍然权威，但不会被
   `reusable_answer` 找到。`simigo_is_search` 也会写一条结算，但那是**检索结算**
   （id 为 `is-retrieval:<demand_id>`，`validation_status = IS_RETRIEVAL`，payload 是检索结果
   JSON）：demand 停在 `RESOLVED`、不产生 advancement，且复用门控要求载荷含非空顶层
   `content`，所以它只能被引用为 `retrieval_settlement_id`，永远不会变成 `reusable_answer`；
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

### 3.6 `reusable_answer` 是读

`simigo_es_begin` 在同时给出 `session_id` 与 `query` 时，会按 2.4 的同一套门控检查是否已有
可复用的已结算回答。命中时返回 `reusable_answer{text, settlement_id, demand_id, source_state_id, model_calls: 0}`，
且**不写入任何东西**；是否跳过云端调用由 Agent 自己决定。

> 已知缺陷 **D-2**（2026-10-28 核实）：`simigo_is_search` 目前不接受 `session_id`，它写的检索
> demand 不带会话身份；而带 `demand_id` + `retrieval_settlement_id` 的 settle 会跳过会话 demand 的
> 补发。因此「先 search、再带来源 settle、再 begin 复用」这条链路当前**拿不到** `reusable_answer`。
> 暂时可行的替代是：settle 给 `session_id` + `query` 且**不给** demand 引用（可复用，但检索来源
> 只体现在 `dependencies`，不走复用时的检索有效性检查）。修法与裁定见
> `research/agent-runs/simigo-es-is-realmodel-20261026/STAGE1-GAP-MATRIX-20261028.md` §4.11。

## 4. 首版明确不支持 / 未验证

| 项 | 状态 |
| --- | --- |
| Agent 进程内直接加载模型 | 不支持接管（见 §1） |
| Ollama / LM Studio 作为**上游 provider**（SimiGo 去调用它们） | 暂缓（裁定 R2-A：先做真实第三方 Agent 接入） |
| Anthropic 原生 wire（非 OpenAI-compatible） | 不支持；这类 Agent 走方式 B |
| MCP 工具粒度鉴权 | 未做。`/mcp` 整体属 SRS-write 权限；TLS 监听需完整证明，明文回环免证明 |
| MCP 身份自证 | `model` / `tokenizer` 由调用方自报，SimiGo 无法察觉谎报；它记录的是**声明** |
| 真实第三方 Agent 端到端读取 | 未做（#100）；目前只有测试层与 stand-in 证据 |
| 跨模型复用 | 设计上永不发生（身份不匹配即拒绝）；真实引擎 A→B 换模型的读数未取 |

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

# C. MCP 握手与结算读回
curl -s $BASE/mcp -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call",
       "params":{"name":"simigo_is_status","arguments":{}}}' | jq '.result'
```

## 6. 本文件的更新触发点

- R1-A 默认态裁定落地后，改 §2.6；
- 真实第三方 Agent 端到端读取完成（#100）后，把具体已验客户端写进 §2/§3；
- provider adapter（#80）启动后，改 §4 对应行；
- 任何路由、身份键、复用门控或 MCP 工具合同的改动，同步改对应小节。
