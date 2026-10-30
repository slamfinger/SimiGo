# Stage 1 缺口矩阵（换 Agent → 进入 ES/IS 管控）

日期：2026-10-28
基线：HEAD `b08525116b878dbf`（工作区未提交）；产品代码只读审计，未修改任何文件。
方法：路由表、请求处理、ES/IS 写入面的直接代码取证；不引用历史结论作为新证据。

## 0. 摘要

- 第三方 Agent 今天**可以**用 OpenAI 兼容形状直连 SimiGo 本地 API：入站入口存在，且本地明文监听器对所有受保护路由免 LOCALB 证明。
- 「自动治理」的最后一层（IS 命中就不调模型）**不存在**，而且不是接线级工作量：产品生成路径从不声明结算复用契约，检索侧的复用键又被既有裁定判定为不可充当消费键。
  - **（2026-10-28 复核撤回）** 该结论只成立于 Stage B 合同那一本账。Chat 非流式路径另有一套已实现的零模型调用短路（默认开，未提交，已有真机读数）。见 §4.3。
- 「模型身份进合同」**已经实现**：HTTP 生成路径把模型身份一路写入结算身份。

## 1. 事实（代码级）

### 1.1 入站统一入口（Agent → SimiGo）

| 事实 | 位置 |
|---|---|
| 接受 OpenAI 形状：`POST /v1/chat/completions`、`/chat/completions`、`/v1/completions`、`/completions`、`/v1/responses` | `SimiGo/Protocol/HTTPServer.swift:1252-1257` |
| 上列全部登记为 `.protected(permission: .inference)` | 同上 |
| 本地**明文**监听器对受保护路由免证明直接放行（"local developer/tool surface"，Owner ruling 2026-10-26）；TLS 监听器保留完整 B3 证明门 | `HTTPServer.swift:2112-2133` |
| 请求中 `model` 字段**不做任何校验**（未找到未知模型的拒绝分支），任意模型名都会进入本地生成 | 全仓检索无 `model_not_found` / `unknown model` |
| 身份解析：`agent_id`、`x-simigo-agent`、`x-agent-id`、`agent`、`metadata.agent_id` | `HTTPServer.swift:2590-2642` |
| 无显式会话身份时铸造 `"<ns>-request:<uuid>"`（`openai` / `responses` 两个家族） | `HTTPServer.swift:2650-2655`、`:2757-2760`、`HTTPServerResponses.swift:2360-2364` |
| 受保护路由上，身份选择**头**被拒绝，只能走签名 JSON 字段；明文监听器不经过该校验 | `HTTPServer.swift:1282-1314`、`:2126-2128` |

结论：Agent 侧只需 `base_url=http://127.0.0.1:<port>/v1` + 任意 `Bearer`，即可进入 ES/IS 受管生成路径。

### 1.2 出站 provider adapter（SimiGo → Ollama / LM Studio）

| 事实 | 位置 |
|---|---|
| `UpstreamProvider` = `openai / ollama / lmstudio`，含 `modelsPath`（`/v1/models` vs `/api/tags`）与 `defaultPort`（443 / 11434 / 1234） | `SimiGo/App/CloudBackend.swift:34-63` |
| `CloudBackendConfiguration` 已有 `provider` 字段（默认 `.openai`）与 provider-aware `modelsProbeURL()` | `CloudBackend.swift:71-81`、`:148-157` |
| `modelsProbeURL()` **零调用点** | 全仓检索仅见声明 |
| 生产构造点不传 provider，恒为 `.openai` | `SimiGo/System/Service.swift:652-654` |
| provider 无持久化键（`AppKey` 只有 `cloudBaseURL` / `cloudModel`） | `SimiGo/App/Config.swift:10-11` |
| 无 provider 选择 UI | `Service.swift:537-542`、`Settings.swift:325` |
| 三条路径共用 OpenAI 请求体，故 chat 路径本身无需按 provider 分支 | `CloudBackend.swift:26-33`（代码内注释） |

结论：provider adapter **逻辑已写、未接线**；当前是「死配置」。本机未安装 Ollama / LM Studio（`which ollama` 空、端口 11434/1234 无监听），本轮无法做端到端验证。

> **提交状态限定（2026-10-28 复核）**：本节全部行描述的是**工作区**（`CloudBackend.swift` 未提交改动）。`git show HEAD:SimiGo/App/CloudBackend.swift | grep -c UpstreamProvider` = 0 ⇒ 已安装的 v2.2.1 里没有 provider 概念，`Service.swift` 在 HEAD 上也不含 `provider`。

### 1.3 自动治理（ES 前置 + IS 命中短路）

| 事实 | 位置 |
|---|---|
| 零模型调用消费**已实现**，但仅 `/v1/responses`，且必须由调用方给出显式 typed payload：`source_settlement_id` + contract + query + extract | `SimiGo/Protocol/SettlementConsumptionEntry.swift:4-45`（契约注释）、`:143` |
| 该 payload 缺省时 Responses 路径逐字节不变；出现但不可用则拒绝，不回退 | 同上 `:26-29` |
| `declareSettlementReuseContract` **仅被测试与 b7 临时工具调用，产品生成路径无调用方** | `SimiGoESISDatabase.swift:3204`；调用点仅 `SimiGoTests/ResponsesSettlementConsumptionHTTPTests.swift:117`、`Packages/.../SimiGoSettlementConsumptionTests.swift:70,265,532` |
| 检索侧复用键**不可**充当消费键（既有裁定）：`executeInformationDemand` 写的是检索结算，不是 `settlements`；其 canonical 可复用，判据不可 | `ACCEPTANCE-20261026-BUILD-97043902.md:1190` |

结论：今天不存在「进入生成前先查 IS，命中就不调模型」的自动路径；且要建立它，必须先决定**每个已结算轮次向外发布什么 demand**。这不是接线，是语义。

> **范围限制（2026-10-28 复核）**：本节三行只覆盖 `settlement_reuse_contracts` 这张表与 Responses 的显式 opt-in。它**不**覆盖 Chat 路径上独立实现的复用短路——检索时只按 `declareSettlementReuseContract` 找调用点，漏掉了按行为实现的第二条路。更正见 §4.3。

### 1.4 模型身份进合同（换模型不假定可互换）

| 事实 | 位置 |
|---|---|
| HTTP chat 路径把生产者身份带入结算：`modelIdentity: producer?.modelIdentity ?? modelId` | `SimiGo/Protocol/HTTPServerChat.swift:151`、`:205` |
| ES 结算写入走带身份的接口 `recordNativeSettlementWithIdentity` | `SimiGo/App/ExecutionStateGraph.swift:479`、`:564` |
| Responses 路径同样携带 `turn.modelIdentity` | `HTTPServerResponses.swift:1008`、`:1025` |
| 云端后端记录 `"remote:" + modelId` | `SimiGo/Inference/RemoteOpenAIRuntime.swift:47-48` |
| 本地 MLX 记录 canonical 模型身份 | `NativeMLX.swift:444`、`:2675` |

结论：模型身份已在结算侧留痕，「不同模型结果可直接互换」的假设在产品里没有依据。

## 2. 结论

1. Stage 1-A 的**入站一半已完成**；剩下的一半（provider adapter）逻辑已存在，缺持久化与调用点，且本机无对应服务可验证。
2. Stage 1-B 的「自动 IS 命中短路」**未实现**，前置条件是「结算时发布可匹配 demand」的语义决定，不能靠接线补齐。
   - **（2026-10-28 复核撤回）** 该结论对 Chat 非流式路径不成立：短路已实现、默认开、已有真机读数（§3.31 T2）。它走的是 `information_demands` + `information_advancements` 这本账，不是 `settlement_reuse_contracts`。见 §4.3。
3. Stage 1-C 的「身份进合同」已完成；剩「Agent 可替换」的**验收**（换 Agent 后同一 ES/IS 仍成立）尚未有跨 Agent 的真实读数。

## 3. 假设

- 明文 loopback 免证明是**有意**的产品面（代码注释引 Owner ruling），本轮按既定事实处理，不改动其安全边界。
- 主流 Agent（Ollama、LM Studio 客户端、OpenAI SDK 系）均可配置 OpenAI 兼容 base URL，因此**入站不需要非 OpenAI 形状的适配器**；该判断未用真实第三方 Agent 验证。

## 4. 待裁定

| # | 决策 | 选项 | 推荐 | 影响面 |
|---|---|---|---|---|
| R1 | 自动短路的 demand 发布判据 | A 结算时发布 canonical demand（规范化 userText + scope），仅 exact-repeat 命中即复用，默认关闭、任何不确定回落生成；B 保持现状，只把显式消费合同从 Responses 补到 Chat；C 仅在同一会话谱系内自动复用，跨 Agent 不共享 | A（可证伪、最弱主张） | 命中即零模型调用，属行为变更；须有开关与拒绝理由可观测 |
| R2 | provider adapter 优先级 | A 暂缓，先做「真实第三方 Agent 接入」端到端与文档；B 现在补持久化 + 设置项，等你安装 Ollama/LM Studio 后验证 | A | 本机不可验证，先做会再次产生死配置 |

## 4.1 业主裁定（2026-10-28）

- **R1 = A**：结算时发布 canonical demand（规范化 userText + scope），仅 exact-repeat 命中即复用；默认关闭；任何不确定回落生成。
- **R2 = A**：provider adapter 暂缓；先做真实第三方 Agent 接入的端到端验收。

## 4.2 A 的实施约束（实现前必须先解决）

R1-A 的「demand 基」与既有消费合同的基**不是同一种东西**，不能直接复用：

| 约束 | 位置 |
|---|---|
| 声明时的 canonical 由 `canonicalDemandInput` 计算，基 = `query + 该根全部 file_contents 摘要`，**与对话/问句无关** | `SimiGoESISDatabase.swift:2216-2253` |
| `rootIDs` 传空数组或不传，SQL 都会取**全部**索引文件；无法用现有 API 表达「与文件无关的基」 | 同上 `:2221-2225` |
| 同一结算的声明是终态：改任何一项（含 query/roots/digest）都抛 `contractMismatch`，不允许改写 | `:3256-3271` |
| 数据模型明写「可复用是已结算单元的**已声明属性**，绝不从文本相似度推断」 | `:3181-3183` |

因此 R1-A 不是接线，需要一项**契约级扩展**：
1. 新增一种 demand 基（例如 `basis = "user-text"`），canonical = 规范化 userText + scope，与文件索引解耦；
2. `settlement_reuse_contracts` 增加基类型字段（或新表）⇒ **DB 迁移**（现有最高为 v11 一族的版本化迁移）；
3. 新增「按 canonical 反查有效结算」的读取面，并在读侧**重查**结算有效性与身份绑定（不得只信声明时的快照）；
4. 请求路径钩子：开关开启时先反查，命中走既有零模型调用消费；未命中或任何不确定 → 回落生成；
5. 端到端读数须证明「命中轮模型调用数 = 0」，不能只证明代码路径被走过。

以上 1–3 属已评审组件（阶段 B 消费合同）的改动，需要独立设计与评审，不适合在未验证的情况下顺手改。

## 4.3 更正（2026-10-28 复核）：§1.3 结论句、§2 结论 2、§4.2 的实施结论撤回

### 4.3.1 失误定性：仪器/口径缺陷

§1.3 只按**符号**检索（`declareSettlementReuseContract` 的调用点），没有按**行为**检索（「模型动作之前的短路返回」）。Chat 路径另写了一套短路，不经 Stage B 合同表，于是被整段漏掉。这是检索面的缺陷，不是产品缺陷，也不是「读数与判据不一致」。本轮补检的符号面：`answeredDemand`、`isAnswerReuseEnabled`、`[IS_REUSE]`、`information_advancements`。

### 4.3.2 补检到的事实（均为工作区代码，HEAD 不含）

| # | 事实 | 位置 |
|---|---|---|
| 1 | Chat **非流式**路径在模型动作前有短路返回块；条件是 `tools` 为空（工具轮永不复用） | `SimiGo/Protocol/HTTPServerChat.swift:815-820` |
| 2 | 判决函数 `reusableAnswer`：开关；上一轮在本 scope 内应答过同一问句；应答结算 `validity=valid`；检索结算 `validity=valid`（依赖检查）；生产者身份判据 `evaluate(...) == .ok`；正文非空 | 同上 `:248-270` |
| 3 | 复用是**读**：不写结算、不建 ES 行，只追加一条 assistant chat 行 + `[IS_REUSE] … model_calls=0` | 同上 `:272-283` |
| 4 | 复用键 =（information scope，尾部 user 文本）。文本只做 `trimmingCharacters`，无 Unicode 归一/大小写折叠 ⇒ 属 **exact-repeat** | 同上 `:91`、`:116` |
| 5 | scope = `sessionID ?? resolveExplicitSession(...) ?? informationScope(agentId:messages:)`；后者 = agentId + 首条 system 或首条 user 原文的 SHA-256 前缀 | 同上 `:99-101`、`:287-299` |
| 6 | demand 行与 advancement 行由上一轮 `settleInformationTurn → loop.settleTurn` 在结算时写入；读取只认 `state='ADVANCED'` | 同上 `:193-210`；`SimiGoESISDatabase.swift:2709-2731` |
| 7 | 默认开启：`SIMIGO_IS_ANSWER_REUSE != "0"` | 同上 `:225-227` |
| 8 | 该实现**不在 HEAD（v2.2.1/已安装）**：`git show HEAD:…HTTPServerChat.swift \| grep -c reusableAnswer` = 0；该文件工作区 +168/−20 | 本轮实测 |
| 9 | 已有真机读数：§3.31 T2 `0.23s`、`[IS_REUSE] … model_calls=0`、两条 `chat_messages` 共享同一 `content_object_id`、发生在零持久化 KV 默认配置下 | `ACCEPTANCE-20261026-BUILD-97043902.md:1964`、`:2008`、`:2024`；`COMMIT-SCOPE-INVENTORY-20261028.md:48-52` |
| 10 | 测试层覆盖为零（全仓无测试引用 `answeredDemand` / `isAnswerReuseEnabled`） | `COMMIT-SCOPE-INVENTORY-20261028.md:52` |

### 4.3.3 修正后的判定

- **Stage 1-B「IS 命中短路」不是未实现**：Chat 非流式路径已实现、默认开、有单窗口单问句真机正例。未提交（HEAD 无）、测试层零覆盖、流式与 Responses 自动路径无。
- **R1-A 的语义在产品里已经存在**，只是名字不同：结算时发布的是 `information_demands(query, session_id)` + `information_advancements`，而不是 `settlement_reuse_contracts` 的 canonical digest。
- **§4.2 的「R1-A 不是接线，需要契约级扩展」撤回。** §4.2 表格里的四条约束仍然为真，但它们只约束 Stage B 那本账，不适用于 R1-A。

### 4.3.4 R1-A 剩余工作（修正后，按建议顺序）

| # | 事项 | 性质 | 阻塞 |
|---|---|---|---|
| A | **默认态冲突**：裁定 R1-A 写「默认关闭」，代码是默认开（`!= "0"` 才开） | 需裁定 | 未裁定前不改默认，避免「悄悄改产品默认」 |
| B | **复用没有记为消费边**：只写 chat 行 + 日志，无 `settlement_consumptions` 行、无消费者 ES、无派生结算 ⇒ `model_calls=0` 只是日志文本，不是表里的数据 | 实现缺口 | 无 |
| C | 覆盖面：流式与 `/v1/responses` 自动路径无短路（Responses 只有显式 opt-in 合同） | 实现缺口 | 无 |
| D | 测试层零覆盖（正例/失效/身份不匹配/scope 隔离） | 验证缺口 | 无 |
| E | 语义边界须落档：trim-only 归一；scope 由首轮原文派生，首轮变化即不复用（fail-open 到生成，符合「任何不确定回落生成」）；跨 Agent 共享仅在 agentId 与首轮原文都相同时成立 | 文档 | 无 |

建议顺序 **B + D → C → A**：先把「命中」变成表里的可核验事实并加上测试，再扩覆盖面，最后处理默认态。

### 4.3.5 实施状态（2026-10-28，工作区，未提交）

按 §4.3.4 的建议顺序执行，B、D 完成，C 部分完成，E 在此落档；A 不动。

**B（消费边）— 已完成。** 新增 v14 迁移与附加表 `information_reuse_events`：

| 列 | 含义 |
|---|---|
| `reuse_id` | 行标识 |
| `source_settlement_id` / `source_state_id` | 被复用的权威结算与其 ES |
| `demand_id` | 内容寻址的需求 id；`UNIQUE` ⇒ 同一需求只留一条消费边，重复记录返回既有行 |
| `session_id` | 消费发生的 scope |
| `consumer_state_id` | 可空，且恒为空：**复用是读取，不产生消费者 ES 状态** |
| `canonical_digest` | `sha256("sessionID\|query")`，把精确查找键密封进行 |
| `model_calls` | `INTEGER NOT NULL CHECK(model_calls=0)`：零模型调用是列约束，不是日志文本 |
| `reused_at` | 写入时刻（UTC） |

`recordInformationReuse(...)` 拒绝空 `demand_id` / 空 `source_settlement_id`，并在源结算 `validity != "valid"` 时抛 `InformationReuseError.sourceNotValid`。**没有复用既有的 `settlement_consumptions`**：那张表的 `state_id NOT NULL` 会逼出一个人造 ES 状态，等于把一次读取伪装成一次执行，故用附加表而不是伪造状态。源结算不被改写、不被消费，仍是该段文本唯一的权威记录。

**D（测试）— 已完成。** 门控从 app 层下沉到包内 `SimiGoInformationLoop.reusableAnswer(sessionID:query:identity:)`，四条规则 + 载荷非空全部 fail-closed（任一不满足返回 `nil`，即「去生成」而非「尽力复用」）；app 层只保留诊断关闭开关与环境映射，后续 MCP 等入口共用同一套规则。新增 `SimiGoInformationReuseTests`（5 例：同 scope 正例且不新增结算、未结算不可服、失效链不可服、身份不匹配不可服、异 scope/大小写标点不同不可服）与 `SimiGoESISDatabaseTests` 的 3 例（零调用行、按 demand 幂等、非法源拒绝）。schema 头 13→14，四处固定断言（Carrier 两处、Database 首部一组、Snapshot 一处）同步更新后 `swift test` 40/40 通过（Carrier 17 + Database 15 + Snapshot 3 + Reuse 5，另有 0 例的 Experimental 套件）。

**C（覆盖面）— 部分完成。** `/v1/chat/completions` 的**非流式与流式**现在共用同一门控；两者都放在 `fork_from_branch` 处理**之后**，避免复用把一个显式的分支请求静默吞掉。流式输出按真实流的线形给出：一个 `delta.content` chunk（附 `simigo.answer_reuse/model_calls/settlement_id/demand_id/source_state_id`）、一个 `finish_reason=stop` 的 chunk、`data: [DONE]` 后关闭；复用行在流被接受之后才写，写头失败不会留下「没人看见的复用」记录。

未完成：**`/v1/responses` 的自动路径仍无短路**（流式与非流式都只有显式 opt-in 合同）。Responses 流式需要合成 `response.created` / `output_item.*` / `response.completed` 整套事件，风险与工作量都高于 Chat 侧，本轮不做。

**C 的验证边界（须如实计入）**：流式复用只做了增量 Debug 构建的类型检查与链接（`build/u3-check`，产物时间戳 09:06:12 > 源文件 09:05:57），**没有端到端跑过**。按 Owner「不要扩大测试套件」的指示，本轮未新增 app 级 HTTP 测试；因此「流式复用在线形上真的能被 OpenAI 兼容客户端消费」目前是**未取证**的，不得作为已验收结论引用。

**E（语义边界）— 落档于此。**

- 归一化只有 **trim**：仅去掉尾部用户文本两端空白；大小写、标点不同视为不同问题（测试断言 `Where is the exit?` 不复用 `where is the exit`）。这是有意的保守：宁可生成，不可错配。
- scope 推导为 `sessionID ?? 显式会话 ?? informationScope(agentId: 首条 system/user 原文)`；**首轮原文一变，scope 就变**，同一问题不会被跨会话复用（fail-open 到生成，符合「任何不确定回落生成」）。
- 跨 Agent 共享只在 **agentId 与首轮原文都相同**（或双方提供同一显式会话）时成立；换 Agent 默认不复用，这与「不假定不同模型的结果可互换」一致。
- 复用写一条 chat 行 + 一条消费边，**不写结算、不写 ES 状态**；依赖失效会沿 `transitiveDependents` 级联：源检索结算失效 ⇒ 其答案结算同样失效 ⇒ 再次提问回落生成（测试显式断言了这一级联，而不是假装规则 3 能独立隔离）。

**A（默认态）— 仍未裁定，代码未改。**（`SIMIGO_IS_ANSWER_REUSE != "0"` 即默认开。）

### 4.3.6 1-C 附带发现的缺陷与修复（2026-10-28，工作区）

复核「不同模型的结果不能假定可互换」时发现一处真实漏洞，已修：

- **缺陷**：`recordNativeSettlementWithIdentityAndAdvancement` 调 `insertIdentityBindingRows` 是**无条件**写入，而 app 在拿不到 producer 时曾兜底成 `"unspecified"`。于是两个**不同**但都未被识别的模型各自写出 `digest("unspecified")`，`evaluate` 只比摘要 ⇒ 判定 `.ok` ⇒ 后一个模型可以继承前一个模型的已结算文本。这正是产品路线里「不能直接假定它们的结果可以互换」的违例。
- **修复**：`SimiGoSettlementIdentityBinding.Identity` 增加 `absent`（空串）与 `isSpecified`，并明确「无身份 = 没有声明，不是通配」；`evaluate` / `evaluateConsumer` 增加 `SETTLEMENT_BINDING_CONSUMER_ABSENT` 拒绝码，并把 `recorded == digest("")` 一律当作缺失；app 兜底从 `"unspecified"` 改为 `.absent`。
- **判据收紧方向**：读取侧统一 fail-closed ⇒ 未识别生产者的结算**既不可被复用、也不可被受管续跑消费**。
- **未做（有意）**：写入侧仍为「无身份」写一行空摘要绑定。要让记录本身也不出现这种伪声明，需改 `insertIdentityBindingRows`，会牵动既有 DB 断言，本轮不动；读取侧已不承认它。
- **测试**：新增 `testAbsentProducerIdentityIsNeverServable`（`.absent` 对 `.absent` 也必须拒绝，并直接断言绑定层拒绝码）；`swift test` 全量 **200/200** 通过；app 侧增量 Debug 构建退出码 0（唯一 `error:` 行是既有的 CoreSimulator 版本噪声）。

### 4.4 阶段 2 起点：MCP 生命周期接线（2026-10-28，工作区，未提交）

#### 4.4.1 只读审计：原来的 MCP 面是「只读的」

`HTTPServerMCP.swift` 原有 6 个工具：`simigo_is_search`、`simigo_is_status`、`simigo_roots_list`、`simigo_root_register`、`simigo_is_reconcile`、`simigo_is_settlement`。对照业主列出的五项生命周期能力：

| 能力 | 审计时状态 |
|---|---|
| 开始一次执行（ES） | 无 |
| 读取已结算结果 | 有（`is_search` / `is_settlement`） |
| 提交满足合同的结算 | 无 |
| 声明来源与依赖 | 无（只能间接通过 root 注册与 reconcile） |
| 记录失败 | 无 |

`MCPInformationSpaceTests.testSettlementSummaryIsReadableAndCitableOverMCP` 的结构正是业主指出的那个缺口：它**先用包内 `SimiGoInformationLoop` 写结算**，再经 MCP 读回。也就是说旧测试证明的是「读得回」，而不是「经工具调用被记录下来」。所以「MCP 连接成功 ≠ 结果已被记录」在代码层面一直是**未接线**，不是接线了但没测。

#### 4.4.2 已实现的三个工具（同一套原生操作，没有第二本账）

- **`simigo_es_begin`**（必填 `model` / `tokenizer`）：为模型跑在 SimiGo 之外的 Agent 建或恢复 ES。新建行 `lifecycle=active`，**不写任何结果**；对已结算的 state 拒绝复用（防止把已封闭的执行当新执行），对不同 model 的已有 state 拒绝（换引擎是新执行，不是同一执行换身份）。可选 `query` + `session_id` 时返回 `reusable_answer`——这是对已结算答案的**只读**检查，不写 `information_reuse_events`，`model_calls=0` 只是本次读取的事实，不冒充结算。
- **`simigo_es_settle`**：经 `SimiGoSettlementAuthority.authorize` + `SimiGoInformationLoop.settleTurn` 落权威结算 ⇒ 结果合同校验、payload 摘要封印、producer model/tokenizer 绑定、advancement、摘要，全部走原生事务。要求先 `begin`（未 begin 拒绝）、model 必须与 begin 一致、同一 state 只结算一次、`demand_id` 与 `retrieval_settlement_id` 必须成对且后者必须 `valid`（否则拒绝引用失效来源）。`dependencies` 逐条写成 `settlement:<id> -> <dep>` 修订，**与结算在同一个事务里**提交（`recordNativeSettlementWithIdentityAndAdvancement` 的 `declaredDependencies`）：`content_address` 必须是已封存对象 id（`is_dependency_entries` 的 `is_objects` 外键就是权威），未封存地址在结算前以 `invalidArguments` 拒绝整次 settle，不会出现「结算成功但声明的来源被静默丢弃」；回包 `dependencies` 从库内读回，不是回声输入。
- **`simigo_es_fail`**：写 append-only 失败审计 `c-failure-audit:<execution_id>`，**永不生成结算**；重复 execution_id 返回 `duplicate_execution_id` 而不是覆盖。回包带 `settlement_id`（空串），让调用方一眼看出「这条执行没有结果」。

包侧只补了两个只读入口（`executionStateModelIdentity`、`executionStateParentID`），用于 settle 时核对身份与保住父边；没有新增表、没有新增迁移。

#### 4.4.3 证据（2026-10-28 10:05，隔离根一次性跑绿）

**仪器**：`xcodebuild build-for-testing`（Debug，`-derivedDataPath build/u3-check`，退出码 0）→ `tools/make_isolated_xctestrun.py` 把三个根目录重定向到 `/tmp/simigo-mcp-test-20261028/iso`（`other_differences: []`，`run.xctestrun` sha256 `bd942038…`）→ `test-without-building` 点名 `SimiGoTests/MCPInformationSpaceTests`：**9/9 通过（0.101s），`XCODEBUILD_RC=0`**；跑前跑后安装实例均未检出（`INSTALLED_APP_BEFORE=` / `INSTALLED_APP_AFTER=`）。包侧 `SimiGoRuntime` 合同套件 `swift test` **200/200 通过**（同一份改动，0 failures）。

- **已证明**（工具调用真的落行，不是「MCP 能连通」）：
  - 结算行、producer model/tokenizer 绑定、摘要、依赖均可从 `simigo_is_settlement` 读回；`begin` 时 `settlements` 计数为 0。
  - 精确重复经 MCP 短路：同 session 同 query 的 `begin` 回 `reusable_answer`（`text: "the exit is north"`、`model_calls: 0`、`source_state_id` 指向第一次执行）；本轮实测 `demand_published=7194230E…`、`demand_error=` 空。
  - 依赖必须引用已封存对象：第二轮以第一条结算的 `payload_sha256` 作为 `content_address` 声明依赖后，`is_dependency_entries` 计数为 1，回包与回执都读得回；改报 `"abc"` 则在结算前被拒，`settlements` 计数不变，随后同一 state 仍能正常结算（拒绝没有吞掉这次执行）。
  - 未 begin / 跨模型 / 二次结算三类仍被拒且不落行；失败审计落盘且不产生结算。
- **未证明**：① 尚无真实第三方 Agent（Claude Desktop / Cursor 等）经 MCP 真调一轮再查库的端到端读数；② `model` / `tokenizer` 由调用方自报，没有探针校验真实性，这套绑定防的是「不同引擎互不继承」，不是「调用方谎报身份」；③ 失败不改 ES `lifecycle`（无结算即无结果，审计是权威记录）；④ 未做 MCP 权限/鉴权分级，任何能访问 `/mcp` 的客户端都能写结算。
- **取证过程**：本小节上一版在任何一次绿跑之前就写了「已证明」，属于超前写入，现已按上述读数重写。中途还证伪过一次「复用已通」的判断——当时隔离根里跑的是 09:31 的旧测试 bundle，`reusable_answer` 恒为 null；换成同源新构建后才得到本节读数。

### 4.5 实施状态续（2026-10-28 第二窗，工作区，未提交）

本节只记录**测试层**读数，不写入验收文档；产品代码同上，仍未提交、未触碰安装实例。

**C（覆盖面）— 已完成。** `/v1/responses` 自动路径（流式 + 非流式）现在与 Chat 共用同一门控：

| 事实 | 位置 |
|---|---|
| 非流式在生成前查 `reusableAnswer(for:)`，命中则由 `makeCompletedResponse` 合成完整 completed 体 | `SimiGo/Protocol/HTTPServerResponses.swift`（`handleResponsesNonStreaming`） |
| 流式命中时经 `ResponsesStreamState` 合成 `response.created` → `output_item.*` → `response.completed` 整套事件，不发 `response.failed` | 同上（`handleResponsesStreaming`） |
| 杀手开关在共享判定里：`isAnswerReuseEnabled` 由 Chat 与 Responses 共用，仍是 `SIMIGO_IS_ANSWER_REUSE != "0"` | `HTTPServerChat.swift:224`、`:239` |
| 显式请求合同优先：`settlement_consumption` / 受管续跑存在时自动复用不介入 | Responses 两条路径的 `consumptionNote == nil` 判定 |
| 复用只读：不写结算、不建 ES 行；写一条 `information_reuse_events` 消费边与一条 assistant chat 行 | 本文件 §4.3.5 B 项 |

**`/v1/completions` 的边界（新裁定，工作区）。** 该路由的 prompt 是续写文本而不是 IS demand，故不做 ES 前置、不做 IS 复用、不写结算——这是**声明的兼容旁路**，不是遗漏。wire 上非流式体与流式终止 chunk 都带 `simigo: {"managed": false, "reason": "legacy_text_completions"}`，使边界可从外部核验。

**跨引擎（1-C 产品级）— 已有测试。** 同一 session 同一问句，在第二个 tokenizer 内容不同的引擎身份下重新生成、不复用，且响应无 `simigo` 块（`testDifferentProducerIdentityIsNotReused`）。注意：两个 stand-in 的 model 指纹相同（repo/revision/root 均为空），拒绝发生在 tokenizer 绑定不匹配——这与生产行为一致（`evaluate` 先比 model 再比 tokenizer，任一不匹配即拒绝）。

**Chat 流式复用线上消费 — 已取证（2026-10-28 10:28，新增套件）。** `ChatAnswerReuseHTTPTests` 经真实签名 HTTP 入口 `POST /v1/chat/completions (stream: true)` 覆盖：首轮生成（模型调用计数 +1，SSE 带生成文本与 `[DONE]`，无 `simigo` 块）；同 session 同问句第二轮**不调用模型**（计数不变），SSE 在内容 chunk 上带 `simigo: {answer_reuse: true, model_calls: 0, settlement_id, demand_id, source_state_id}`，随后 `finish_reason=stop` 与 `data: [DONE]`，文本等于已结算答案；`currentChatStateID` 与 `readSettlementReceipts().count` 均不变（复用是读）；`information_reuse_events` 落行且 `modelCalls=0`；换一个问句则恢复正常生成（计数 +1、无 `simigo` 块）。唯一被替换的组件是生成器（计数器），其余全部走真实产品派发。

**证据（2026-10-28 10:27–10:29，隔离根，同一构建）**：`build-for-testing`（Debug，`build/u3-check`，`-enableCodeCoverage NO`）退出码 0；`tools/make_isolated_xctestrun.py` 重定向三根（`other_differences: []`，`run.xctestrun` sha256 `bd942038…`）；`test-without-building` 点名两套（本构建只新增测试文件，产品代码与上一窗相同）：

| 套件 | 读数 |
|---|---|
| `ChatAnswerReuseHTTPTests` | 1/1 通过（0.907s）：流式精确重复不调模型，SSE 带 `answer_reuse/model_calls=0` 与结算文本，ES/结算计数不变，消费边落行 |
| `ResponsesAnswerReuseHTTPTests` | 3/3 通过（2.996s）：精确重复 0 调用、流式重复 0 调用、跨引擎重新生成 |
| `MCPInformationSpaceTests` | 9/9 通过（上一窗同源构建） |
| `ResponsesSettlementConsumptionHTTPTests` | 10/10 通过（上一窗同源构建，显式消费仍优先） |
| `CompletionsBoundaryHTTPTests` | 2/2 通过（流式与非流式都声明 `managed=false` 且结算计数不变） |

跑前跑后安装实例均未检出（`INSTALLED_BEFORE=` / `INSTALLED_AFTER=` 皆空）。

**仍缺（1-B/1-C 收口条件）**：A 项默认态裁定未下，代码未改；安装版 + 真实模型的复用与换模型读数未取（需手动起服务）。测试层四条自动路径（Chat 非流式/流式、Responses 非流式/流式）均已覆盖，不再有未取证的线上形态。

### 4.6 「首版支持哪些接入方式」已落档（2026-10-28，工作区，未提交）

按目标要求「首版要明确支持哪些接入方式」，在 [`docs/AGENT-ACCESS.md`](../../../docs/AGENT-ACCESS.md) 写成接入说明，
并在 `research/README.md` 导航表加了一行指针。写的过程中逐条回源码核对，补到三条此前未登记的事实：

| 事实 | 位置 | 含义 |
|---|---|---|
| 受管治理只在本地引擎路径发生；配置远端后端时推断路由走 `forwardToRemote`，不解析 demand、不复用、不写结算 | `HTTPServer.swift:2434` 起 | 「SimiGo 作云端代理」模式下的 Agent 不算接入，只能走方式 B |
| Chat 两条路径的复用短路要求 `tools` 为空 | `HTTPServerChat.swift:415`、`:904` | 工具轮不复用，但仍前置检索并结算 |
| Responses 两条路径的复用判定**不检查** `tools` | `HTTPServerResponses.swift:1250`、`:1683` | 与 Chat 不对称，登记为已知差异（是否有意未裁定） |

文档里同时写明了版本边界：在 tag `v2.2.1` 上核对 `simigo_es_begin`、`isAnswerReuseEnabled`、
`unmanagedCompletionsBlock` 均为 0 处 —— 已发布安装版没有本文所述的复用短路与 MCP 生命周期工具。
文档也写明默认态仍待 R1-A 裁定、真实第三方 Agent 端到端（#100）未做。

### 4.7 Release 配置编译复验（2026-10-28，只编译，不安装、不启动）

按 owner「先专注 Release 构建复验」的要求，对未提交工作区（HEAD `b0852511`）做了一次 Release 编译复验：

| 项 | 读数 |
|---|---|
| 命令 | `xcodebuild -project SimiGo.xcodeproj -scheme SimiGo -configuration Release -derivedDataPath build/u5-release-20261028 CODE_SIGNING_ALLOWED=NO build` |
| 结果 | `XCODEBUILD_RC=0`，`** BUILD SUCCEEDED **`；日志中唯一含 `error:` 的行是 CoreSimulator 版本告警，非编译错误 |
| 产物 | `build/u5-release-20261028/Build/Products/Release/SimiGo.app`，二进制 108,691,128 B，sha256 `b9e952a1c22ced95a9b0882b93ba432437f6a6f45503701655b6b2952043dc16`，版本 2.2.1 (build 31) |
| 能力符号 | `simigo_es_begin`、`simigo_es_settle`、`reusable_answer`、`SIMIGO_IS_ANSWER_REUSE`、`SIMIGO_IS_CONTEXT_FREEZE`、`legacy_text_completions`、`information_reuse_events`×5 均在 |
| 安装实例 | 前后均无 `Applications/SimiGo.app` 进程；其二进制未变（sha256 `c5e248ac766215ec926765e82e1057147c404e76907021d4f7d8fe8b53f40828`） |

一条在核查中确认的**取证陷阱**，后续读二进制必须记住：Release 优化会把 ≤15 字节的短字面量实体化进指令流，
`strings` / 字节子串会搜不到。`simigo_es_fail`（14 B）、`audit_persisted`（15 B）、`failure_class`（13 B）因此均搜不到，
但同一工具条目的长描述（含 `begun-but-unsettled`）与 `evidence values must be strings` 都在。用最小复现确认：
`swiftc -O` 下 14 字节的工具名与返回键同样从 `.o` 中消失，而 16 字节的 `simigo_is_status` 保留。
故符号存在性只能用「长度 ≥16 的字面量 + 同条目长描述」交叉判断，不能据短串缺失断定工具缺失。

### 4.8 潜在缺陷 D-1：Responses 复用短路可截断工具循环（2026-10-28，链路已核实，只登记不改码）

**状态**：待 owner 裁定；未改产品代码（属语义变更，需授权）；未新增测试（owner 指示不扩测试套件）。

**机制链（逐环核实）**：

| # | 环节 | 位置 |
|---|---|---|
| 1 | Responses 作用域跨工具轮稳定：显式会话 → `codex-thread:<thread>` → 消息摘要 | `SimiGo/Protocol/HTTPServerResponses.swift:961-974` |
| 2 | 「同一问题」判据只取最后一条 `role=="user"` 消息；工具循环里追加的 `function_call_output` 不改变它 | `HTTPServerResponses.swift:950-954`，`:1240-1244` / `:1672-1676` 的 `queryOverride` |
| 3 | 生成结束后无条件结算：任意非空 assistant 文本都走 `settleTurn(..., summaryQuery: turn.query)`，把该问题记为已回答 | `HTTPServerResponses.swift:980-1030`（结算调用 `:1019-1029`）；调用点 `:1328`（非流式）、`:1793`（流式） |
| 4 | 下一轮带 tools 回传同一问题时，复用闸门先于一切生成逻辑命中：非流式 `:1250-1251`（唯一守卫是 `consumptionNote == nil`），流式 `:1683`；两者都不检查 tools | `HTTPServerResponses.swift:1250`、`:1683` |
| 5 | `reusableAnswer(for:)` 内部也没有 tools 判定 | `HTTPServerChat.swift:239-248` |
| 6 | 命中后以 `buildResponsesOutput(content: reuse.text, calls: [])` 直接完成，不调用模型、不产生 `function_call` | `HTTPServerResponses.swift:1253` |

**触发场景**：模型「先说一句、再 function_call」是 Agents 的常见形态。同一作用域内（含 `previous_response_id` 续跑）再次提出同一问题时，
第二轮拿到的是那句前导文本 + `calls: []`，工具永远不会被执行；而这一轮仍以 `answer_reuse / model_calls: 0` 正常完成，
并在 IS 追加一条 reuse 边，外观与成功生成一致。前导文本本身被结算为一次回答并不算错（它确实是对该问题的有效文本），
问题在于第 4 环拿它当作了「包含工具执行」的那一轮的终点。

**Chat 侧对照**：`:415` 与 `:905` 都要求 `(tools ?? []).isEmpty`，故 Chat 不会发生该短路。
`docs/AGENT-ACCESS.md:78-79` 已如实记下这条不对称，但当时按「已知情况」描述、未评估后果，现升级为潜在缺陷。

**测试覆盖**：`SimiGoTests/ResponsesAnswerReuseHTTPTests.swift` 没有 tools 用例（全文唯一 `tools` 出现在 `:67` 的隔离根注释）。

**零模型复现路径**：包内测试在隔离根预置「同 scope、同 query、`ADVANCED` 的 demand + valid 结算 + 与当前引擎一致的生产者身份」，
再发一个带 `tools`、且消息含 `function_call_output` 的 Responses 请求，断言响应是否带 `answer_reuse` 与 `calls: []`。本轮未执行。

**待裁定选项**：

- **(i) 定向跳过（推荐）**：请求含 `function_call_output`，或父响应 output 含 `function_call` 时跳过复用。
  不影响「全新重复提问」的零调用复用，只排除工具续轮。可实现性已核：`parsed.currentInputMessages` 是 `[JSONValue]`
  （`HTTPServerResponses.swift:424`），按 `type == "function_call_output"` 扫描即可，无需改解析器或 DB。
- **(ii) 对齐 Chat**：请求带非空 `tools` 即不复用。语义最保守，但几乎关闭所有 Responses Agent（默认带工具）的复用。
- **(iii) 接受现状并写入契约**：明确「Responses 工具轮不保证复用安全」，由接入方自行规避。

**旁证（已核实，不构成第二处缺陷）**：`consumptionNote` 只出现在非流式路径（设置 `:1148-1170`、闸门 `:1250`、回写 `:1356-1359`），
因为流式路径对显式消费直接以 `consumptionUnsupportedOnStream` 类型化拒绝（`:1536-1540`），根本到不了闸门。这一不对称是良性的。

**可达性（2026-10-28 补核）**：两条前置分支都挡不住 D-1——

- 显式消费：非流式在闸门前处理（`:1149-1170`，命中即返回，`recompute` 置 `consumptionNote` 使闸门不触发）；流式直接拒绝。二者都不会进入被截断的复用。
- C-scope 受管续跑：`:1181` 起的 `managedContinuationStep` 分支在普通管线之前返回，不经过复用闸门。
- **普通 `previous_response_id` 续跑（请求不带 C-scope 字段）仍走完整管线**：`continuationGate`（`:1224`）→ `prepareInformationTurn` → 闸门（`:1251`）。
  此时 `currentInputMessages` 通常只有 `function_call_output`、没有 user 消息，`queryOverride` 回退到 `canonicalMessages` 的最后一条 user，
  即原问题 Q；作用域由父会话解析，跨轮不变。流式同构（`:1651` → `:1683`）。**故续跑形态也可达。**

### 4.9 待 owner 决策（截至 2026-10-28 的收口清单）

| # | 决策 | 当前事实 | 推荐 | 悬置的后果 |
|---|---|---|---|---|
| D1 | `SIMIGO_IS_ANSWER_REUSE` 默认态 | 代码默认开（`!= "0"`），与 R1-A「默认关闭」冲突（`docs/AGENT-ACCESS.md` §2.6 已标注） | 按 R1-A 改为默认关、`=1` 显式开启，并同步改写对外说明 | 阶段 1-B 无法收口，对外文档无法定稿 |
| D2 | 删除 2 份孤儿草稿 | 两文件在整仓无任何引用，共 13.5 KB；证据与哈希见 `LAB-DOC-CLEANUP-PLAN-20261028.md` §4.C | 批准删除（Git 可恢复） | 阶段 3 停在「待批」，其余候选已改判保留 |
| D3 | 安装版真实模型读数 | 服务须手动启动；安装实例至今未触碰 | 授权一轮干净窗口 | 1-B 复用读数、1-C 跨模型 A→B、#100 第三方 Agent 端到端均无真机证据 |
| D4 | 阶段 4 提交 / 推送 / 安装 | 工作区未提交、远端 `main` 未变、无新标签 | 待 1–3 收口后按既定顺序执行 | 无法发版，README/Release 不能收敛 |
| D5 | D-1 修法 | 三选项见 §4.8 | 选项 (i) 定向跳过（请求含 `function_call_output` 时不复用）；施工规格与测试见 §4.14.2 | Responses 工具续轮仍可能被旧前导文本短路 |
| D6 | D-2 修法 | 三选项见 §4.11 | 选项 (i)：`simigo_is_search` 接受 `session_id` 并传给 `Demand`；施工规格、测试与随附文档校正见 §4.14.1 | 云端 Agent 的检索联动结算无法复用，「检索→结算→复用」闭环不成立 |

### 4.10 阶段 2 硬化：MCP 生命周期文档逐条对照实现（2026-10-28）

对 `docs/AGENT-ACCESS.md` §3.4/§3.5 与实现逐条核对：三条判据与六条 settle 前置条件全部成立；
发现并修正一处**文档精度**问题，未改产品代码：

- §3.4 原第 1 条「只有 settle 会写权威结算」在措辞上过宽：`simigo_is_search` 经
  `SimiGoInformationLoop.resolve` 调 `recordInformationRetrieval`（`SimiGoESISDatabase.swift:3031`）
  会写一条**检索结算** `is-retrieval:<demand_id>`（`validation_status = IS_RETRIEVAL`），
  并把 demand upsert 为 `RESOLVED`；它从不调用 `insertInformationAdvancementRows`。
- 复用侧有两道**独立**闸口把检索结算挡在 `reusable_answer` 之外：`answeredDemand` 只取
  `state='ADVANCED'`（`:2771-2797`，检索后停在 `RESOLVED`）；`reusableAnswer` 要求结算 payload
  顶层 `content` 非空（`SimiGoInformationLoop.swift:330-359`），检索载荷是 StoredResult JSON，
  没有该字段。故**不构成第二处缺陷**；文档已改为两类结算的区分表述。
- `simigo_es_settle` 返回的 `state_id` 是本次结算产生的**子状态**（`HTTPServerMCP.swift:669`，
  `turn.childStateID`），与入参里 begin 的 state 不同；已补进 §3.5。
- 另核实：settle 既不给 `session_id`+`query`、也不给 `demand_id`+`retrieval_settlement_id` 时，
  结算仍是权威结算，但**不会**出现在 `reusable_answer` 里——补发 demand 只在 `:648-661`
  走 `recordAnsweredDemand`（发布新 demand，`SimiGoESISDatabase.swift:2827-2857`，state 直接为
  `ADVANCED`）。该条件已写入 §3.4 判据 1。
- 仍未验证（归 #100）：真实第三方 Agent 端到端、`model`/`tokenizer` 由调用方自报不可核、
  `/mcp` 鉴权粒度（整体 SRS-write，无工具级授权）。

### 4.11 潜在缺陷 D-2：MCP「带来源结算」与「回答复用」互斥（2026-10-28，链路已核实，只登记不改码）

状态：待 owner 裁定；未改产品代码；未新增测试。与 D-1 独立。

`docs/AGENT-ACCESS.md` §3.3 推荐的完整生命周期是
`simigo_is_search → simigo_es_settle(demand_id + retrieval_settlement_id) → 以后 simigo_es_begin 返回 reusable_answer`。
逐行核对后，**第三步拿不到复用**：带来源结算会把答案写进一条**无会话身份**的 demand，而复用按会话精确匹配。

| # | 环节 | 证据 |
|---|---|---|
| 1 | `simigo_is_search` 的入参 schema 只有 `session_ids`（被检索的 chat 会话），没有 `session_id` | `HTTPServerMCP.swift:186`、`:190` |
| 2 | 该 handler 构造 `Demand` 时不传 `sessionID`，默认 `nil` | `HTTPServerMCP.swift:340-345`；`SimiGoInformationLoop.swift:35-47` |
| 3 | 检索写入时 `information_demands.session_id` 因此为 NULL | `SimiGoInformationLoop.swift:256-262`；`SimiGoESISDatabase.swift:3005`、`:3090-3115` |
| 4 | 复用按 `d.session_id=? AND d.query=? AND d.state='ADVANCED'` 精确匹配 | `SimiGoESISDatabase.swift:2771-2797`；`SimiGoInformationLoop.swift:330-359` |
| 5 | 带 `demand_id`+`retrieval_settlement_id` 的 settle 会写 advancement（`settleTurn` 内），`turn.advancementID` 非空 | `SimiGoInformationLoop.swift:431-486`（`:457`） |
| 6 | 因 `advancementID` 非空，会话 demand 的补发分支被跳过 | `HTTPServerMCP.swift:646-661` |

- **触发**：`is_search(Q)` → `settle(state, [session_id, query], [demand_id, retrieval_settlement_id])` →
  `begin(new_state, session_id, Q)` → `reusable_answer` 为 null；而结算本身 valid、可被
  `simigo_is_settlement` 读回。
- **两条路径互斥**：不带 `demand_id`/`retrieval_settlement_id` 的 settle 会由
  `recordAnsweredDemand` 发布会话 demand（`SimiGoESISDatabase.swift:2827-2857`，state 直接
  `ADVANCED`），复用可用，但检索来源不进入 advancement 的检索有效性检查；带了检索引用，
  来源绑定正确，却无法复用。
- **测试层未覆盖**：`SimiGoTests/MCPInformationSpaceTests.swift:351-413` 是唯一复用用例，
  其 settle（`:360-367`）**不带**任何 demand 引用，恰好走的是能复用的那条分支。
  （该套件 2026-10-28 已在隔离窗口 9/9 跑通，见 §4.12；跑通不改变本条结论——带来源的 settle 仍无测试。）
- **修法选项**：
  - **(i) 推荐**：`simigo_is_search` 增加可选 `session_id` 并传给 `Demand.sessionID`（schema + 一行）。
    无需 DB 迁移；检索 demand 带会话后，advancement 与复用按同一 demand 命中，检索有效性检查也保留。
  - (ii) settle 时无条件补发会话 demand：会让 `answeredDemand` 取到最新 advancement 的
    `retrievalSettlementID = NULL`，复用闸门因此跳过检索有效性检查 —— 以安全换可用，不推荐。
  - (iii) 保持现状并把「来源与复用互斥」写进对外文档 —— 与阶段 2 的产品目标直接冲突。
- 影响面：云端 Agent 的「检索→结算→复用」闭环，属阶段 2 的核心卖点，不是边角。
- 同一过度声明也存在于 `simigo_es_begin` 的 tool description（`HTTPServerMCP.swift:245-247`
  「the settled answer already held for that question is returned as `reusable_answer`」）
  **以及 `docs/AGENT-ACCESS.md` §3.4 第 1 条**（[`:155-157`](file:///Users/mr.simi/Documents/SimiGo/docs/AGENT-ACCESS.md#L155)：
  称给出 `demand_id`+`retrieval_settlement_id` 即「被置为 `ADVANCED`…被 `reusable_answer` 找到」，
  与同文件 §3.6 的 D-2 注自相矛盾）；修 D-2 时一并校正，避免 wire 层与文档继续承诺未实现的行为。
  本轮未改该文档（`docs/` 属发布面，改动随 D6 裁定一起做）。

### 4.12 阶段 2 测试层读数：MCPInformationSpaceTests 9/9 通过 + runner 挂起根因（2026-10-28，测试层，不改产品代码）

状态：**已取得读数**；位置是隔离窗口下的测试层，按既有规矩**不写入 ACCEPTANCE 文件**，
也不作为发布级验收。产品代码、测试源码、构建产物与安装实例均未改动。

#### 4.12.1 先卡住的不是代码：runner 在 dyld 里挂起

两次窗口都是 `** TEST EXECUTE FAILED **` + `The test runner hung before establishing connection.`，
零条 `Test Case`，约 333 s 被判超时（与 ACCEPTANCE §3.20/§3.21 同族）。本轮把根因取到了：

| 证据 | 内容 |
|---|---|
| `sample` 宿主（pid 2327，`/private/tmp/.../SimiGo.app/Contents/MacOS/SimiGo`） | 主线程停在 `dyld4::prepare → loadDependents → forEachRPath → mapFileReadOnly → dyld4::open`；物理驻留 **256 KB**，一个库都没映射——冻在动态链接，不在应用代码 |
| 直接启动同一二进制（同一副本） | 1 s 内加载 **1264** 条 dyld 库记录并打出 `SimiGo bootstrap: issueCount=0 models=20 …`，常驻正常 |
| `DYLD_PRINT_LIBRARIES` 直启日志 | `grep -c Documents/SimiGo/build` = **69**：全部包框架都是从 `~/Documents/.../PackageFrameworks` 加载的 |
| `otool -l` | 主可执行与 `SimiGo.debug.dylib` 都带绝对 `LC_RPATH /Users/.../build/u3-check/Build/Products/Debug/PackageFrameworks`；从 `Contents/Frameworks` 加载的计数 = **0** |

判定：Xcode 生成的绝对 rpath 让 dyld 在**解析包框架时**必须 `open()` `~/Documents` 下的路径；
由 `testmanagerd` 拉起的宿主没有该目录的 TCC 授权，`open()` 在连接测试之前就卡住。
直接启动之所以能过，是启动上下文不同（同一字节的二进制），不是代码差异。这也解释了为什么
把 app 复制到 `/tmp` 仍会挂——**复制没有改掉二进制里的绝对 rpath**。

**可复现的修法（纯 harness，不动二进制、不重签）**：让测试根自包含在 `/tmp`——
复制 `Debug/SimiGo.app`、`Debug/PackageFrameworks` 与 base xctestrun 到同一 `Products` 树，
用 `tools/make_isolated_xctestrun.py` 在其旁生成隔离 xctestrun。xctestrun 里本就有
`DYLD_FRAMEWORK_PATH=__TESTROOT__/Debug:__TESTROOT__/Debug/PackageFrameworks:…`，
该目录一旦存在，dyld 全在 `/tmp` 命中，一个 `~/Documents` 路径都不再打开。

#### 4.12.2 读数

```
xcodebuild test-without-building \
  -xctestrun /tmp/simigo-mcp-test-20261028b/Products/iso-d.xctestrun \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:SimiGoTests/MCPInformationSpaceTests
```

- `Executed 9 tests, with 0 failures (0 unexpected) in 0.104 (0.106) seconds`；窗口墙钟约 17 s（11:15:15→11:15:32）。
- 9 个用例全绿：`testInitializeToolsListAndNotificationShape`、`testRootRegisterIsIndexOnlyAndSearchResolvesIt`、
  `testUnknownToolAndMissingSettlementFailClosed`、`testSettlementSummaryIsReadableAndCitableOverMCP`、
  `testBeginSettleRecordsAuthoritativeSettlement`、`testSettleWithoutBeginAndWrongModelFailClosed`、
  `testBeginReportsSettledAnswerAcrossEngines`、`testFailureIsAuditedAndNeverBecomesASettlement`、
  `testInformationScopeGroupsByConversationOpening`。
- 复用读数（套件自打）：
  `[MCP-REUSE] demand_published=EF11A090-… advancement= reusable={"text":"the exit is north","model_calls":0,"source_state_id":"D7A1CFF1-…","settlement_id":"5F041979-…"}`。
  `advancement` 为空、`demand_published` 非空，正是 §4.11 第 5–6 行「无检索引用的 settle 才走补发分支」的实例；
  该用例对另一模型、另一会话均返回 null，且 `settlements=1`、`information_reuse_events=0`。
- 结算/依赖/回执读数字段完整（`[MCP-SETTLE]`、`[MCP-SETTLE-DEP]`、`[MCP-SETTLE-RECEIPT]`）：
  `validity=valid`、`dependencies` 引用上游结算、`bindings` 含 `producer.model_identity` 与 `producer.tokenizer_identity`。
- 身份：仓库 HEAD `b0852511`，工作区 55 项（本轮开始前即如此）；测试产物来自 `build/u3-check`（测试二进制 mtime 11:02）。
- 隔离：`/tmp/simigo-mcp-test-20261028d/{home,cache,state-graph}`；隔离 xctestrun sha256 `0a0a6a57…`，
  `other_differences: []`。套件把 `simigo.sqlite3`(+wal/shm)、`logs/`、`manifests/` 全写在该根内；
  真实 `~/.simigo` 最新文件仍是 01:52，11:14 之后 **0** 个文件被改。

#### 4.12.3 能证明什么、不能证明什么

- **能**：MCP 生命周期工具在进程内端到端接线可用——begin/settle/fail、模型身份不符拒结、
  未 begin 拒结、未知工具与缺失结算 fail-closed、根注册+检索、结算摘要可引用、信息作用域分组，
  以及「settle 后 begin 返回 `reusable_answer` 且 `model_calls=0`」。
- **不能**：不带来源的 settle 分支 ≠ 带来源分支。§4.11 的 D-2 仍**未取到经验证据**——
  套件里唯一复用用例不带 `demand_id`/`retrieval_settlement_id`，检索联动路径没有被执行。
  同理未覆盖：跨进程、真实第三方 Agent、真实模型。
  要把 D-2 从「链路已核实」升级为「已复现」，需要新增一个带来源结算的复用用例；
  在 owner 裁定 D6 之前不做（不扩测试套件）。

#### 4.12.4 对 #30 的补录

本节把 ACCEPTANCE §3.20 第 2 项「`test runner hung before establishing connection` 的复现条件」
补上了：**Xcode 生成的绝对 `LC_RPATH` 指向 `~/Documents`**（首次启动 / 隔离根 / 端口复用都不是必要条件）。
§3.22 用「一窗一选择子」绕开过，但真正的自变量是宿主在 dyld 阶段能否在本机 TCC 允许的路径内解析全部框架。
§4.13 在 Release 宿主上再次用同一修法跑通（Release 宿主的 rpath 只有相对路径，但仍需 PackageFrameworks 与重签）。

### 4.13 Release 构建上的同一套 MCP 生命周期读数：9/9 通过（2026-10-28，测试层，不改产品代码）

本节回答「Debug 9/9 是否只是 Debug 特性」：同一套 `MCPInformationSpaceTests` 在 **Release 优化构建**上
逐个通过，且复用分支仍打印 `model_calls=0`。

**构建身份**

| 项 | 值 |
| --- | --- |
| 源码 | HEAD `b08525116b878dbfbee737005b0006130206cbd3`；工作树 55 项未提交；`git diff \| shasum -a 256` = `6bdcb43b1a056f9d1efcc0a0558804275bb63779d250265df4f53c2f83ad62e7` |
| 动作 | `xcodebuild -project SimiGo.xcodeproj -scheme SimiGo -configuration Release -derivedDataPath build/rel90 ENABLE_TESTABILITY=YES -enableCodeCoverage NO build-for-testing` → `BFT_RC=0` |
| 产物 | `build/rel90/Build/Products/Release/SimiGo.app`；测试包 mtime 11:22、4,868,960 B（05:20 的 4,600,368 B 旧包已被取代） |
| 宿主 sha256 | `e2bb6ef2e22a1cbf12884e4cf805436fd6954fe60b10090adbcf8e1ea537f1a8`（adhoc 深签后） |
| 测试包 sha256 | `4fc7b537d4e278f204ad7d713831d758aca31ef9d027ccd45717ada83c5afddc` |

**测试根与隔离**

- 自包含根：`/tmp/simigo-relmcp-20261028/Products/{Release/SimiGo.app, Release/PackageFrameworks(16), base2.xctestrun}`；
  深签带 `get-task-allow` + `disable-library-validation` + testmanagerd mach-lookup，`codesign --verify --deep --strict` = OK。
- 隔离 xctestrun `mcp-release2.xctestrun` sha256 `56f59a014d6215729a160792790b22cf407f44e91771785fcbbb70f05460cb75`，
  `other_differences: []`，三根注入 `/tmp/simigo-relmcp-20261028/iso2/{home,cache,state-graph/...}`。
- 全部写盘落在 `iso2/`（`simigo.sqlite3` + WAL/SHM、`logs/native_mlx_trace.log`、`manifests/`、`sources/`）；
  真实 `~/.simigo` 自 11:22 起 **0** 个文件变化；窗口内 `pgrep -fl "MacOS/SimiGo"` 为空。

**读数**

```
Executed 9 tests, with 0 failures (0 unexpected) in 0.095 (0.098) seconds
** TEST EXECUTE SUCCEEDED **        # RUN_RC=0，窗口 11:22:25 → 11:22:35
[MCP-REUSE] demand_published=73AA35C1-48F3-4C9D-A068-1DDDD666C307 demand_error= advancement=
            reusable=[..."model_calls": 0, "settlement_id": "AF59AAA6-C2DD-41BF-A296-9E0988A1D4C2"]
[MCP-SETTLE] [... "validity": "valid", "summary_recorded": true, "demand_id": "59715B27-…"]
```

逐个通过：`testBeginSettleRecordsAuthoritativeSettlement`、`testSettleWithoutBeginAndWrongModelFailClosed`、
`testBeginReportsSettledAnswerAcrossEngines`、`testFailureIsAuditedAndNeverBecomesASettlement`、
`testInformationScopeGroupsByConversationOpening`、`testInitializeToolsListAndNotificationShape`、
`testRootRegisterIsIndexOnlyAndSearchResolvesIt`、`testSettlementSummaryIsReadableAndCitableOverMCP`、
`testUnknownToolAndMissingSettlementFailClosed`。

**口径限定（写死）**

1. 这是 `ENABLE_TESTABILITY=YES` 的 **Release 测试产物**（保留内部符号、嵌入 16 个 SwiftPM framework），
   **≠ 可发布 DMG 的字节**，不得当发布候选引用；
2. 只证明 MCP 生命周期接线在 Release 优化下仍成立；**不**证明 D-2 的带来源复用分支——
   唯一复用用例仍不带 `demand_id`/`retrieval_settlement_id`，§4.11 结论不变；
3. 同日 11:20 的 Release 5/5 是 05:20 旧测试包（早于 10:04 的测试源），由本节替代，不单独引用；
4. 本节不改变 D1–D6 任何待裁定项。
5. 工艺：Release 宿主**不需要** `Contents/Frameworks/libXCTestBundleInject.dylib` 也能注入（Debug 与 Release 两次窗口均无该文件）；
   必要条件是①自包含 `/tmp` 根（app + `PackageFrameworks` + xctestrun 同级）②adhoc 重签带 `disable-library-validation`。

### 4.13.1 同一 Release 宿主上的回答复用 HTTP 套件：4/4 通过（2026-10-28，测试层，不改产品代码）

阶段 1-B 的 Release 侧补充读数：在 §4.13 的同一自包含 Release 测试根上运行**既有**两条回答复用
HTTP 套件（未新增测试、未重编译）。

- 构建：沿用 §4.13 的可测性 Release 产物（宿主 `e2bb6ef2…`、测试包 `4fc7b537…`）。
- 命令：`xcodebuild test-without-building -xctestrun /tmp/simigo-relmcp-20261028/Products/reuse3.xctestrun
  -destination 'platform=macOS,arch=arm64'
  -only-testing:SimiGoTests/ResponsesAnswerReuseHTTPTests
  -only-testing:SimiGoTests/ChatAnswerReuseHTTPTests -resultBundlePath /tmp/simigo-relmcp-20261028/result3.xcresult`
- 隔离：`reuse3.xctestrun` sha256 `eb902ff8296a4ba0a4a8c363a7d453a5895eacb549bf930ecdd4e49e2d622d67`
  （源 `base2.xctestrun` `5d99cbaf…`），`other_differences: []`，三根注入
  `/tmp/simigo-relmcp-20261028/iso3/{home,cache,state-graph/...}`；隔离记录生成于 11:25:26。

**读数**

```
Executed 4 tests, with 0 failures (0 unexpected) in 3.842 (3.845) seconds
** TEST EXECUTE SUCCEEDED **        # RUN_RC=0，窗口 11:25:27 → 11:25:31
```

逐个通过：

- `ChatAnswerReuseHTTPTests.testStreamingExactRepeatIsServedWithoutModelCall`（0.910 s）
- `ResponsesAnswerReuseHTTPTests.testDifferentProducerIdentityIsNotReused`（1.304 s）
- `ResponsesAnswerReuseHTTPTests.testExactRepeatIsServedWithoutModelCall`（0.842 s）
- `ResponsesAnswerReuseHTTPTests.testStreamingRepeatIsServedWithoutModelCall`（0.787 s）

写盘全部落 `iso3/`（`simigo.sqlite3` + WAL/SHM、`logs/native_mlx_trace.log`、`sources/` 等）；
服务器日志 `监听 127.0.0.1:59374`（chat）/`59372`（responses）均带隔离根；真实 `~/.simigo`
自 11:25:00 起 **0** 个文件变化；窗口后 `pgrep -fl "MacOS/SimiGo"` 为空。

**口径限定**

1. 四条用例都不是带 `tools` 的请求，**不覆盖 D-1**（Responses 复用短路截断工具循环仍只在代码层核实，§4.8 结论不变）；
2. 仍是 `ENABLE_TESTABILITY=YES` 的 Release 测试产物，**≠ 可发布 DMG 的字节**；
3. 不改变 D1–D6 任何待裁定项。

### 4.13.2 同一 Release 宿主上的 ES/IS 核心合同套件：8 套件 51/51（2026-10-28，测试层，不改产品代码）

补足「Release 优化构建下，阶段 1–2 所依赖的 ES/IS 权威合同是否与 Debug 一致」。仍用 §4.13 的可测性
Release 产物，**未重编译、未新增测试**，只跑仓库既有套件。

- 命令：`xcodebuild test-without-building -xctestrun /tmp/simigo-relmcp-20261028/Products/core4.xctestrun
  -destination 'platform=macOS,arch=arm64' -only-testing:SimiGoTests/{ExecutionStateGraphSettlementContract,
  ExecutionStateGraphAdmission, ExecutionLineage, ContinuationAdmissionSettlementBinding,
  ResponsesContinuationSettlementContract, ResponsesSettlementConsumptionHTTP, ManagedContinuationAdapter,
  ToolGovernance}Tests -resultBundlePath /tmp/simigo-relmcp-20261028/result4.xcresult`
- 隔离：`core4.xctestrun` sha256 `d484450bd0722950d8bdac96b19d441e9fb52d36ffd509a4d0057bfbed3b9486`
  （源 `base2.xctestrun` `5d99cbaf…`），`other_differences: []`，三根注入
  `/tmp/simigo-relmcp-20261028/iso4/{home,cache,state-graph/...}`。

**读数**

```
Executed 51 tests, with 0 failures (0 unexpected) in 7.387 (7.403) seconds
** TEST EXECUTE SUCCEEDED **        # RUN_RC=0，窗口 11:28:30 → 11:28:38；跳过 0 条
```

| 套件 | 用例 | 耗时 |
| --- | --- | --- |
| `ContinuationAdmissionSettlementBindingTests` | 3 | 0.021 s |
| `ExecutionLineageTests` | 5 | 0.004 s |
| `ExecutionStateGraphAdmissionTests` | 3 | 0.021 s |
| `ExecutionStateGraphSettlementContractTests` | 3 | 0.015 s |
| `ManagedContinuationAdapterTests` | 7 | 0.114 s |
| `ResponsesContinuationSettlementContractTests` | 10 | 0.300 s |
| `ResponsesSettlementConsumptionHTTPTests` | 10 | 6.905 s（真起 HTTP 服务） |
| `ToolGovernanceTests` | 10 | 0.007 s |

写盘全部落 `iso4/`；真实 `~/.simigo` 自 11:28:25 起 **0** 个文件变化；窗口后无 SimiGo 进程。
八套件均无 `XCTSkip`（0 skipped），说明其前提（隔离三根）已由 xctestrun 满足。

**口径限定**

1. 全部为**无真实模型**的合同/HTTP/DB 层用例；不覆盖真实权重、KV-free 矩阵与跨模型读数；
2. 仍是 `ENABLE_TESTABILITY=YES` 的 Release 测试产物，**≠ 可发布 DMG**；
3. 与 D-1/D-2 无关（不含 `tools` 复用与检索联动结算），不改变 D1–D6。

### 4.14 D-1 / D-2 实施规格（2026-10-28，待裁定；未改任何产品代码）

为把 §4.8 / §4.11 的「选项 (i)」变成可立即施工的补丁，本节把两处改动的确切位置、形状、测试与风险固定下来。
**本节不含已实施改动**；D5/D6 裁定前不动代码。

#### 4.14.1 D-2：`simigo_is_search` 接受 `session_id`

现状（逐行核实）：

- schema 只有被检索会话数组 `session_ids`（`HTTPServerMCP.swift:186`）；
- handler 构造 `SimiGoInformationLoop.ResolveInput` 时未传 `sessionID`（`:340-345`）；
- 该类型的 `init` **已支持** `sessionID: String? = nil`（`Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoInformationLoop.swift:35-47`），
  所以修法不需要新增类型或迁移。

**补丁形状（两处，均为增量）**

```swift
// HTTPServerMCP.swift, simigo_is_search inputSchema（:182-189）
"session_id": ["type": "string"],          // 新增：本次检索所属会话（可选）

// HTTPServerMCP.swift, resolve 调用（:340-345）
let resolution = try loop.resolve(.init(
    query: query,
    sessionID: optionalString(arguments, "session_id"),   // 新增
    rootIDs: arguments["root_ids"] as? [String] ?? [],
    includeChat: (arguments["include_chat"] as? Bool) ?? true,
    chatSessionIDs: arguments["session_ids"] as? [String] ?? [],
    limit: (arguments["limit"] as? Int) ?? 40))
```

`optionalString(_:_:)` 已在本文件使用（settle 分支 `:649`），无需新助手。

**为什么够用**：检索 demand 因此带上会话身份；随后 `simigo_es_settle(demand_id + retrieval_settlement_id)`
推进的正是这条 demand（state → `ADVANCED`），而 `answeredDemand(sessionID:query:)` 按
`(session_id, query, state='ADVANCED')` 精确命中；复用闸门要求的「结算载荷含顶层 `content`」
由 settle 的答案载荷满足，检索有效性检查也保留（advancement 的 `retrievalSettlementID` 非空）。
**无需 DB 迁移**；新字段是可选的，旧调用方行为不变。

**测试（随补丁一起，仅 2 条，不扩面）**

1. 正例：`is_search(query:Q, session_id:S)` → `settle(带 demand_id + retrieval_settlement_id + content)` →
   `begin(new_state, session_id:S, query:Q)` 断言 `reusable_answer != nil` 且 `model_calls == 0`；
2. 负例：同链路但 `begin` 用 `session_id:T`，断言无 `reusable_answer`。

落在 `MCPInformationSpaceTests` 内（复用其隔离根与既有断言风格），不新建套件。

**随补丁一并校正的对外文字（D6 范围）**

- `docs/AGENT-ACCESS.md` §3.3 生命周期示例补 `session_id`；§3.4 第 1 条与 §3.6 的 D-2 注合并为同一事实；
- `simigo_es_begin` tool description（`HTTPServerMCP.swift:245-247`）删除「只要结算过就能被复用」的隐含承诺，
  改为「同一会话 + 同一 query 的已结算回答」；
- `simigo_is_search` 的 `session_id` 在 description 里写明「仅影响该检索 demand 的会话归属，不参与检索过滤」。

**风险**：`session_id` 与 `session_ids` 名字接近，需在 description 中区分（前者是归属，后者是被检索集合）；
调用方若把 `session_ids` 误传成 `session_id` 不会报错但会失去检索范围——负例 2 覆盖语义，不覆盖拼写。

#### 4.14.2 D-1：Responses 工具续轮不得被复用短路

现状：非流式闸门 `HTTPServerResponses.swift:1250`、流式闸门 `:1683`；唯一守卫分别是
`consumptionNote == nil` 与无守卫；`reusableAnswer(for:)`（`HTTPServerChat.swift:239-248`）内无 tools 判定。

**判据**（对 §4.8 选项 (i) 的精确化，不改变选项本身）：
「本轮是工具续轮」当且仅当 **最后一条 user 消息之后**出现 `function_call_output`，或父响应 output
含 `function_call`。只看会话历史里是否出现过工具输出会误伤带历史的全量请求（会把整个会话的复用全关掉），
所以按「最后一条 user 之后」切分，而不是「请求含 `function_call_output`」的全量扫描。

```swift
/// 工具续轮必须以本轮的 function_call 结束，不能被上一轮的前导文本短路。
static func isToolContinuation(_ parsed: ResponsesParsedRequest) -> Bool {
    let items = parsed.currentInputMessages
    let lastUser = items.lastIndex { $0.object?["role"]?.string == "user" }
    let tail = lastUser.map { items[($0 + 1)...] } ?? items[...]
    if tail.contains(where: { $0.object?["type"]?.string == "function_call_output" }) {
        return true
    }
    return (parsed.parent?.output ?? []).contains { ($0["type"] as? String) == "function_call" }
}
```

**改动点（三处）**

1. 新增上面的静态助手（与 `lastUserText` 同在 `HTTPServerResponses` 的响应辅助区，`:950` 附近）；
2. 非流式闸门改为 `if consumptionNote == nil, !Self.isToolContinuation(parsed), let turn = information.turn, ...`（`:1250-1251`）；
3. 流式闸门改为 `if !Self.isToolContinuation(parsed), let turn = information.turn, ...`（`:1683`）。

不改结算、不改 `reusableAnswer`、不改 Chat 路径（Chat 已有 `tools.isEmpty` 守卫，`:415`、`:905`）。

**测试（仅 1 条）**：在 `ResponsesAnswerReuseHTTPTests` 预置同 scope、同 query 的已结算回答，
再发一个「最后一条 user 之后带 `function_call_output`」的请求，断言响应**不带** `answer_reuse`、
且照常进入生成（可用既有的零模型 fake 引擎断言收到了模型调用）；不新增套件、不引入真实权重。

**行为影响**：只排除工具续轮；「全新重复提问」的零调用复用不变（§4.13.1 的 4/4 用例覆盖该路径）。
显式消费与 C-scope 受管续跑在闸门前分支，已核实不受影响（§4.8 可达性补核）。

**风险**：极少数客户端在工具输出之后再追加一条 user 消息——此时不会被判为工具续轮，复用仍可能命中；
这与「最后一条 user 是新的提问」的语义一致，属可接受边界，拟写入契约而不加判定。

### 4.15 阶段 4 发布草案索引（2026-10-28，草案；未改 README/docs、未提交、未发布）

新建同目录 `STAGE4-RELEASE-DRAFT-20261028.md`，内容：公开面事实校正、五项对外必答的「可写句 / 禁止句」、
README 六个区块的替换草案（R-1…R-6，按行号）、下一版 GitHub Release 正文模板、
C1–C16 声明→证据 checklist、D1–D6 与本草案的映射。

关键校正：公开 Release **已是 v2.2.1**（2026-10-27T13:49:03Z，build 30，DMG `SimiGo-v2.2.1-30-f6a4decf.dmg`）；
真正过期的是 README——下载区仍指 `v2.1.0`（`:24`、`:29`、`:34`、`:49`），状态表仍写 `v2.1.0 (build 10)`（`:201`），
§11 文档表未列 `docs/AGENT-ACCESS.md`。工作区为 `2.2.1` / build `31`（55 个未提交路径），下一版必须进位。

发布阻塞项（草案内编号）：C8 = D-2/D6、C9 = D1、C10 = D-1/D5、C13 = D3；C14–C16 为不可写项
（第三方 Agent 真实接入、provider adapter、批处理）。本索引不含已实施改动。

### 4.16 D-1 / D-2 补丁与三条测试落地读数（2026-10-28，受限实施）

**授权范围**：D1 = GO（保持默认开启，不改默认态）、D5 = GO（§4.14.2 D-1 最小补丁）、D6 = GO
（§4.14.1 D-2 最小补丁，不做数据库迁移）。**未授权**：提交、进位、构建 DMG、安装、发布；
`README.md` 与 `docs/AGENT-ACCESS.md` 本轮**未改**（发布面，随 D4）。

**D-2 补丁**（`SimiGo/Protocol/HTTPServerMCP.swift`，两处 + 两段描述）

- `simigo_is_search` inputSchema 增加可选 `session_id`（与被检索集合 `session_ids` 并列）；
  description 写明「`session_id` 只定归属、`session_ids` 选被检索会话」；
- `loop.resolve(.init(...))` 传入 `sessionID: optionalString(arguments, "session_id")`
  （该 `init` 本就接受此参数，无新类型、无迁移）；
- `simigo_es_begin` description 收窄为「同一会话 + 同一问题 + 相同生产者身份」。

**D-1 补丁**（`SimiGo/Protocol/HTTPServerResponses.swift`，一个助手 + 两个闸门）

- 新增 `Self.isToolContinuation(parsed)`：取最后一条 `user` 之后的尾段，含工具输出判为续轮；
  父响应 output 含 `function_call` 亦判为续轮；
- 非流式闸门（`consumptionNote == nil` 处）与流式闸门均加 `!Self.isToolContinuation(parsed)`。
- **与 §4.14.2 的差异（行为不变）**：规格按原始输入项 `type == "function_call_output"` 判定，但
  `parsed.currentInputMessages` 是**chat 形态**（解析时已把该 item 转成 `role: "tool"`），
  故判据改用 `role == "tool"`；「最后一条 user 之后」的切分与父响应判据未变。

**新增测试（3 条，未新建套件）**

1. `MCPInformationSpaceTests.testSourcedSettleIsReusableInItsSearchSession`：
   `is_search(session_id=S)` → `settle(demand_id + retrieval_settlement_id)` → `begin(S, Q)`
   得到 `reusable_answer`、`model_calls=0`；并断言 `information_demands.session_id=S`（既有 schema）、
   重开同一 DB 仍能 `answeredDemand` 命中（无迁移的兼容性验证）。
2. `MCPInformationSpaceTests.testSourcedSettleIsNotReusableFromAnotherSession`：同链路换 `S'` → 不复用。
3. `ResponsesAnswerReuseHTTPTests.testToolContinuationIsNotServedFromSettledAnswer`：
   已结算正文后追加 `function_call_output` 的同 query 请求 → 生成计数 +1、响应无 `simigo` 块。

**构建与隔离**

- Debug `build-for-testing`（`build/u3-check`，`-enableCodeCoverage NO`）：`BFT_RC=0`。
- 自包含测试根 `/tmp/simigo-d1d2-20261028/Products/{Debug/SimiGo.app, Debug/PackageFrameworks,
  base.xctestrun, run1.xctestrun}`；隔离 xctestrun sha256
  `8d4e4cc32bebbe242b5dab6285dea2abb67c3adc382d6b12a50cf7378b694783`
  （源 `c5f53628…50d3`），`other_differences: []`，三根注入 `iso1/{home,cache,state-graph}`。
  布局修正记录：xctestrun 必须位于 `Products/` 层（`__TESTROOT__` 相对其所在目录解析），
  放在 `Products/Debug` 会解析成 `Debug/Debug/SimiGo.app` 而报 Missing test product。

**读数**

```
Executed 15 tests, with 0 failures (0 unexpected) in 7.715 (7.719) seconds   # RUN_RC=0
```

| 新用例 | 耗时 |
| --- | --- |
| `testSourcedSettleIsReusableInItsSearchSession` | 0.018 s |
| `testSourcedSettleIsNotReusableFromAnotherSession` | 0.019 s |
| `testToolContinuationIsNotServedFromSettledAnswer` | 4.626 s |

既有用例无回归：`MCPInformationSpaceTests` 11/11（含原 9 条）、`ResponsesAnswerReuseHTTPTests` 4/4。
写盘全落 `iso1/`；真实 `~/.simigo` 自 13:18 起 **0** 个文件变化；窗口后无 SimiGo 进程。

**差异检查（按授权要求）**

- `HTTPServerChat.swift`（复用默认态 `!= "0"`）mtime 09:08，未触碰；
- `SimiGoESISDatabase.swift` mtime 10:03，未触碰：**无 schema 变更、无迁移**；
- `README.md`、`docs/` 未改；工作区脏路径数 56（与本轮前一致，未新增文件）；
- 改动仅限：`HTTPServerMCP.swift`、`HTTPServerResponses.swift`、
  `MCPInformationSpaceTests.swift`、`ResponsesAnswerReuseHTTPTests.swift`（后者为未跟踪新文件）。

**口径限定**

1. 全部为 Debug + 无真实模型的测试层读数，**≠ 安装版验收**（C13 仍待 D3）；
2. D-1 只覆盖「用户文本后追加工具输出」这一形态；真实第三方 Agent 的完整工具循环未跑（#100）；
3. C8/C10 可改为「已修复并有测试」，但在 D3 安装版复验前不得写成「已发布/已验收」。

## 5. 本轮未做（及原因）

- **未改任何产品代码**：provider 改造在本机无法验证（无 Ollama / LM Studio）；自动短路的语义裁定已获（§4.1 R1=A），但复核发现短路已存在（§4.3），剩余工作见 §4.3.4，本轮不做顺手改动。
- **未新增测试**：Owner 指示「专注于 Release 构建复验与内存预算边界，而不是继续扩大测试套件」，且 §4.3.4 的 A 项（默认态）尚未裁定。
- **未触碰**安装实例、未提交、未打标签、未推送；工作区仍保持未提交状态。

> 注（2026-10-28 后续）：以上第 1、2 条描述的是**本文件写成的那一轮**。同日晚些时候按 §4.3.4 顺序推进了 B/D/C（见 §4.3.5），其中包含产品代码改动与包内测试；§4.3.5 起为现行状态。

### 4.17 阻断 2 取证与闭环：`:549` 红灯定性为「测量对象错位」，改判后 15/15（2026-10-28 22:39–22:58，测试层，未改产品代码）

owner 裁定（余项三分 · 一.2）要求：复核该失败的原始断言和运行日志，确认是产品行为错误、测试契约错误，还是已证实的环境问题，再依结论修正并重跑；不能只因为它是「已知红灯」就视为已接受。以下是按该要求做的取证、定性与重跑。

**原始断言**（`SimiGoTests/ResponsesContinuationHTTPIntegrationTests.swift:549`，测类 `testAdmissionWithoutSettleStaysOnTheClientBranch`）：

```swift
XCTAssertEqual(try totalExecutionStates(), statesBefore,
               "admission alone must not create an ES row")
```

其中 `totalExecutionStates()` = `count("execution_states")`——**全表计数**（`:241`）。

**原始运行日志**（两处独立窗口、同点同文）：`rc-t1-20261028/run-rc-continuation.log:126`（20:54）与本轮 `is549-20261028/run-549.log`（22:39，单测 + 全新隔离库）均为 `("2") is not equal to ("1") - admission alone must not create an ES row`。

**直接归属取证**（本轮新增；跑完单测后只读 dump 该隔离库，`execution-states.txt`）：

| state_id | parent_id | next_input |
|---|---|---|
| `S-0001` | NULL | `HTTP-ADMITONLY-7103`（锚点，`stageSettledAnchor` 造的） |
| `chat-acaa513d-066d-41f9-9636-d0f38478b78d` | NULL | `plain answer, no contract`（本轮生成的答案） |

`chat_execution_links`：`info-b7cbdc67a07480f6d883bdfdaa84da43 → chat-acaa513d-…`。**多出的那一行不是锚点的子 ES**，而是这一轮已完成答案自己的信息线根行。产品写入链（逐跳，全部为已提交代码）：
`SimiGo/Protocol/HTTPServerResponses.swift:1049-1059`（`settleTurn(stateID: "chat-<uuid>", …)`）→ `Packages/…/SimiGoInformationLoop.swift:460-470`（`childState: .init(id: stateID, parentID: parentStateID, …)`）→ `Packages/…/SimiGoESISDatabase.swift:1485-1491`（`insertExecutionStateRow`）。父 id 取自 `currentChatStateID(sessionID:)`（`SimiGoESISDatabase.swift:3655`，读 `chat_execution_links`），与续跑用的 `previous_es_state_id` 是**两条不同血缘**。

**提交归属时间线**：该断言写于 `c97f016d`（2026-10-25 13:33）；造成它的写入路径进仓于 `c68b64ba`（2026-10-27 20:59，`feat(protocol): run managed continuations as P1 -> gate -> P2`），**晚两天**。`git diff` 既没碰这条断言，也没碰这行产品代码（`stateID: "chat-` 在 HEAD 的 `HTTPServerResponses.swift:1022` 已存在）。⇒ 与未提交的 T-1 工作无关；也与 Debug/Release 配置无关（同一读数和这条红灯在两类构建窗口逐项复现）。

**定性结论：测试契约（测量对象）错位。** 不是产品行为错误，也不是已证实的环境问题。判据要保护的是「admission-only 续跑不得为续跑捏造子 ES」——它的直接判据全部通过（`o.settlement==0`、`o.generateBranch=="main"`、`o.forkTargets.isEmpty`，都在 `:549` 之前），而全表计数把**另一个功能**（每个完成轮自结算一条无父 `chat-*` 信息线根行 + 对应答案结算）的合法写入误读成被拒的续跑写入。与 owner 已裁过的 `settlement_bindings` 行类口径同族。

**修正**（按既有裁定「修测量对象，不动产品接线」；`SimiGoTests/ResponsesContinuationHTTPIntegrationTests.swift` 单文件）：新增 `executionStatesByParent()`（直读隔离库的 `state_id → parent_id`）与 `rowsIsolatedSQLite(_:columns:)`；把那条全表计数换成三条逐条留证据的归属判据——新行中**无一行以锚点为父**、新行**恰好 1 条**、且该行为**无父 `chat-*` 根**。未删除任何断言，未放松 T-1 完整性判据，失败信息里带新行本身。

**重跑读数**（全新隔离库，三份 `iso-record*.json` 均 `other_differences: []`）：

| 测类 | 读数 | 说明 |
|---|---|---|
| `ResponsesContinuationHTTPIntegrationTests` | **15/15，0 unexpected**（15.276 s） | 原 14/15；`:549` 改判后通过 |
| 受管族 5 测类（8+7+10+11+10） | **46/46** | 与 RC-T1 同构成 |
| `GenerationCompletionHTTPTests` | **7/7** | T-1 覆盖路径的测层对照 |

后两行在同一候选的同一次运行里合计 53/53（`run-rest.log`）。

**身份**（`is549-20261028/dual-hash-identity.txt`、`source-identity.txt`）：产品去签名内容哈希 `019269936accf3ec703a97cb0b159befd326f657cd398a396b17a82b9ebafbfd`（21703984 B）与 T-1 运行候选**逐字节相同**，`LC_UUID` 恒等 `869D9013-55E5-3819-9BA7-DB6CECEBAEF3`；签名后文件哈希本轮为 `72e1b086585b8987b1ad4492f40d36161044a795c8dd3f13db7aa576fadd0464`（上一轮 `eccb2d7d022e1b35c14d3819a4d85d7752a333b2f2bdeef2788ad927f3cfdad5`）——按双哈希口径记，**不**写成「签名后哈希一致」。测包 `d67a7763…`（前 `6b6c3a32…`）。HEAD 仍 `b0852511…`（未提交），`git diff` 摘要由 `3c9c6604…` 变为 `2b8ef9e1f23f550aa6fd7630b7677308763bc0cdc9bcdf27101da2cf1a61b6ab`；重记录的 22 个文件中 20 个逐字节相同，两个变动文件都在 `SimiGoTests/` 下。版本读为 2.2.1 / build 31，**未进位**。

**遗留裁定项（两条，不自行决定）**

> 状态更新（2026-10-29）：两条均已被 owner 裁定并已落地——第 1 条 = 裁定 ③-A（接受，边界见 §4.18），
> 第 2 条 = 裁定 ③-B（同批修正，已实施并重跑 15/15 + 53/53，见 §4.18 与 `is3b-20261029/`）。本节正文不再待裁。


1. 本轮把「每个完成轮都会写一条自己的 ES 根行 + 一条答案结算」当作既定产品语义接受。若 owner 认为受管 admission-only 轮不该落这条行，那是**产品侧**改动，需另行授权，本节的测类改判要随之回退。
2. 同一测类另有 3 处仍用全表计数表达「must add no child ES row」——`:671/:697`（拒绝步）、`:831/:864`（422 契约拒绝）、`:877/:918`（500 写失败回滚）。它们**当前通过**，但绿灯来自这些路径根本不调用 `settleResponsesInformationTurn`（另一功能恰好没写），不是测量对象正确。是否同批改为归属判据请 owner 定；本轮按「不扩范围」未动。

**未执行**：安装版复现、真实模型窗口、流式 / Chat Completions / Text Completions / 取消路径回归（属余项二.5）；未提交、未推送、未打包、未安装。


### 4.18 四项裁定落地：① 历史不重写 · ② 两个非研究文件 · ③-A 完成轮 ES 根行语义 · ③-B 三处全表计数（2026-10-29 00:00–00:40）

owner 2026-10-29 裁定原文四项，逐条按裁定的边界执行。授权明确**不含提交、推送、打标签、发布**；本轮四项动作里没有任何一项 Git 写操作、打包发布或安装。

#### 4.18.1 ① Release hygiene：接受既有公开历史，不做历史重写

裁定边界（照抄要点）：**不重写历史**，保留既有公开提交、tag 与冻结原始证据，不改变其历史身份；**不把既有暴露误称为已脱敏**——本裁定接受这一历史风险，不代表这些信息不敏感；**未来发行物另行把关**，将进入未来 RC 或发行包的证据使用对外脱敏副本与必要的来源/校验信息，不直接改写冻结原件，且当前公开分支的文件不能仅因增加脱敏副本就被视为已经干净；**若后续发现有效凭据、私钥或其他实质性秘密，必须单独升级为安全事件**，按实际泄露对象决定撤销、轮换与针对性清理，本裁定不覆盖这种情况。

量化现状（`hygiene2-20261029/hit-population.txt`，两个检查器实跑）：

| 检查器 | 结果 |
|---|---|
| `tools/release_artifact_audit.py` | `PY_RC=1`，1947 条 FAIL，检查 9330 个跟踪文件；非 research 的 FAIL 只剩 1 个文件 |
| `git grep -I -l -E '/Users/\|mr\.simi\|YPXU8M53F9\|slamfinger@163\.com'` | 1940 个文件命中 = `research/` 下 **1939** + 非 research **1** |

那 1 个非 research 命中就是 ② 里**不授权修改**的 LOCALB 测试文件。`tools/make_release_dmg.sh` 现在两个检查器下都不再命中（`NONE (clean)`）。

**本项状态：不能写「阻断 1 已解除」。** 已解除的是「窄改范围内该改的部分」；「对外脱敏副本 + 来源/校验信息」机制仍未建（任务 #111 保持 in_progress），1939 个 research 命中按裁定原样保留、只接受不掩饰。

#### 4.18.2 ② 两个非研究文件

**a. `Packages/LOCALBCore/Tests/LOCALBCoreTests/LOCALBTransportIdentityStoreTests.swift` — 未修改（不授权）。** 该文件 `:369-370` 的 `SIMIGO_HOME=/Users/example/iso-root` 是合成测试路径，不是本机路径的泄露；按裁定保留该输入，避免仅为消除 grep 命中而削弱路径脱敏覆盖。它因此仍是唯一的非 research 命中——这是裁定的**预期结果**，不是遗漏。

**b. `tools/make_release_dmg.sh` — 有条件授权的窄改，已执行并验毕**（`hygiene2-20261029/`，全文 `narrow-change.diff`）。只换掉人工拼接 `/Users/` + 用户名那一处：

```applescript
- set userName to short user name of (system info)
- … rm -f /Users/" & userName & "/.simigo/manifests/first-run-done.json" with administrator privileges
+ set markerPath to (POSIX path of (path to home folder)) & ".simigo/manifests/first-run-done.json"
+ … rm -f " & quoted form of markerPath with administrator privileges
```

等价性按裁定要求**先测后改**（`equivalence-probe.txt`，都是实测）：

1. 把两版各自的 marker 语句用 `return` 替掉提权执行、只构造命令串：两串**只有一个 token 不同**——目标路径由裸写变成 `quoted form of` 包起（`EQUAL_AFTER_STRIPPING_QUOTES=YES`）。去引号后逐字符相同；加引号是收紧（该路径可含空格，旧写法不转义）。
2. 两种写法在**同一用户会话、提权之前**求值：`path to home folder` → `/Users/mr.simi/`，`short user name of (system info)` → `mr.simi`；解析出的完整标记路径两版均为 `/Users/mr.simi/.simigo/manifests/first-run-done.json`。
3. 产品侧读的是同一个文件：`SimiGo/App/FirstRunWizard.swift:16` → `SimiGoPaths.manifests`，主目录权威是 `FileManager.default.homeDirectoryForCurrentUser`（`SimiGoPaths.swift:22`、`:56`）。新写法与该权威同源，故安装器与产品不会分叉。

「适用的打包冒烟」= 跑真脚本、不跑安装器（`dmg-smoke.sh`、`dmg-smoke-final.txt`）：HEAD 版与工作副本各跑一遍，参数指向惰性假 bundle（`Contents/MacOS/SimiGo` 是 `/usr/bin/true` 副本、全程未执行），`OUT` 由脚本自身 dirname 推出所以 DMG 落在 `/tmp` 沙箱内、**仓库根未被写入**，`/Applications` 只以 stage 内符号链接出现，`安装SimiGo.app` 只编译不双击。两版读数同为：`SCRIPT_RC=0`、DMG `hdiutil verify` VALID、stage 三项布局一致、`osacompile` 成功、编译产物 `codesign --verify` 满足 DR；`osadecompile` 出的那两行正是各自的 marker 写法。判据不含 DMG 字节（体积/时间戳/压缩随内容变）。

**自我更正（留档不删）**：第一轮改完 `dmg-smoke-round1-unfixed-comment.txt`（脚本 `b8e1ab60…`）打包冒烟已全绿，但 `git grep` 仍命中第 37 行——命中来自**我新写的注释里那句「不人工拼接 /Users/ 与用户名」**，是文字不是行为。改为「不拼接固定的家目录前缀与用户名」后命中消失；最终以脚本 `1ed1594aea81414ceac9d9042195e087ed6a28644d2087fdb7c8b00fc9837858` 重跑整套冒烟并重取读数（HEAD 版 `7d098e9ad622c3c9a7cdd8cee1da57a911c139ec0c73fe41a3d6ad07f207979a`）。

#### 4.18.3 ③-A：每个完成轮拥有独立 ES 根行 —— 接受，边界照裁定

接受 §4.17 的取证：一个**已完成并结算**的普通轮次创建自己的无父 `chat-*` ES 根行（`parent=NULL`）+ IS 关联 + 答案结算，这不是锚点子行；单看 `execution_states` 全局计数无法证明 admission 创建了子行。边界（照抄要点）：**真正只完成 admission、没有完成生成与结算的路径，不得借用上述普通完成轮次语义自动取得创建子行或结算记录的许可**；测试按各路径的实际生命周期判定。⇒ §4.17 的 `:549` 改判维持，其「完成轮恰好多一行无父 `chat-*`」的正断言即本裁定的直接体现。

#### 4.18.4 ③-B：其余三组全表计数同批修正 —— 已实施，读数 15/15 + 53/53

范围严格限定 `:671/:697`、`:831/:864`、`:877/:918`（改前工作树实际行号 `:689/:715`、`:849/:882`、`:895/:936`）。每处改为按具体锚点与 `parent` 关系判定，三条并列（详见 `is3b-20261029/INDEX.md`）：① 新行中无一行以锚点为父 ② `informationLineageRows()` 不变（不得借完成轮次语义写根行）③ `added == []`（任一行系都不得新增）。第 ③ 条正是裁定「对产品语义确实要求不得产生任何新行的路径，另行检查该路径不应产生的根行及结算记录」的落实；三条原有的结算行数、`answer/retrieval/unattributed` 绑定分类与图投影断言全部保留，未删断言、未放宽预期、未扩展到其他测类、未动产品端 admission/settlement/ES-IS 写入接线。四处站点全改完后 `totalExecutionStates()`（全表计数读取）已无引用，随之删除。

**一处必要的自我修正**：`chat-` 前缀**不是**行系判据。归属对照里出现 `chat-2a738087…` 的 `parent_id = es-bfb260c1…`——续跑结算把信息会话 `linkChatSession(stateID: 子 ES)`（`SimiGo/Protocol/HTTPServerResponses.swift:1036`）后，下一完成轮的 `chat-*` 答案行就挂在该子 ES 下。于是把 `informationLineageRows()` 从 `state_id LIKE 'chat-%'` 收紧为 `… AND parent_id IS NULL`（与 ③-A 措辞一致），并**重建候选、重跑两组门禁**，使汇报读数出自修正后的仪器。收紧不放松任何判据：三处站点另有 `added == []`，任何新行无论前缀与父都会红。

**非空证**（裁定要求「确认新断言测试的是行为本身，而不是当前实现碰巧经过的分支」）：同一对读取器在三个正例窗口分别观测到锚点的 `es-<uuid>` 子行 + 其结算、完成轮的无父 `chat-*` 根行 + 其答案结算、以及检索结算；而拒绝路径跑完后表里只剩预置锚点 `S-0001` 一行。`testNativeContractRejectionIs422AndWritesNothing` 的 `added == []` 是对**有数据的表**做的测量（`per-test-attribution.txt`、`execution-states-attr.txt`、`class-run-row-classes.txt`）。

**读数与身份**（双哈希口径；`is3b-20261029/dual-hash-identity.txt`、`run-classA.log`、`run-familyB.log`）：

| 组 | 结果 |
|---|---|
| A 改写类 `ResponsesContinuationHTTPIntegrationTests` | **15/15**，0 failures |
| B 受管回归族 + 完成度线协议套件（6 类同窗） | **53/53**（8+7+10+11+10+7） |

产品去签名内容哈希 `019269936accf3ec703a97cb0b159befd326f657cd398a396b17a82b9ebafbfd`（21703984 B）与 T-1、`:549` 两轮**内容一致**，`LC_UUID` 恒等 `869D9013-55E5-3819-9BA7-DB6CECEBAEF3`——本轮只动一个测试文件，这是预期结果；签名后文件哈希本轮为 `083a8a667876b61b8cabb606ead140c9b8e0a3eb6aa7747bb3461d3e526ca97d`（`:549` 轮 `72e1b086585b8987b1ad4492f40d36161044a795c8dd3f13db7aa576fadd0464`），**每轮重签必变，不写成「签名后哈希一致」**。测包 final `662cdad0c18163ac256d6424da93746a60e5afecf2204e0a9c22f9a6a53246ce`。HEAD 仍 `b0852511…`，版本仍 `2.2.1 / build 31` 未进位。该候选是 `build-for-testing` 产物，**≠ 可发布 DMG**，不能替代发布包与安装版身份验收。

#### 4.18.5 执行边界与当前发布状态（照裁定复述，不自行扩展）

本轮裁定不改变现有 Git 状态，也不授权发布操作；冻结原始证据与整体验收账本保持不变。①②③-A③-B 完成后，须再按**实际 diff、回归结果与最终发行物清单**重新判断发布阻断——**目前不能据此宣告 v2.2.0rc1 或后续版本已具备发布资格**。T-1 身份口径不再开新讨论。

仍开着的余项：阻断 3（下一版实际源码集与候选身份冻结，含把 `GenerationCompletionRealModelE2ETests.swift` 纳入可复现验证范围）、二.4（用最终 DMG 而非测试包验证）、二.5（对外承诺的 API 路径回归：流式 Responses、Chat Completions、Text Completions、取消，以及真实预填期间断连/超时后同会话重试的 `cachedPromptTokens`/`cacheEff`/模型调用行为）、二.6（README 下载指引仍指 v2.1.0）、① 的对外脱敏副本机制（机制本身见 §4.19；真实发行清单与打包/CI 接线仍未建）。

**未执行**：提交、推送、打标签、发布、安装、提权；未生成可发布 DMG；未跑真实模型窗口（③-B 判据不依赖真实权重驻留）；未改产品代码，未改 `tools/` 其他文件，未改 LOCALB 测试。真实 `~/.simigo` 本轮只读（`manifests/` 仅 `bootstrap-report.json`、`engine-recipes.json`，`first-run-done.json` 不存在，也没有删除动作）。

### 4.19 对外脱敏副本机制：最小闭环已建成并演示（2026-10-29 00:40–01:10）

对应 §4.18.5 余项「① 的对外脱敏副本机制」。落地两件新工具 + 16 条负向测试，全程只读仓库、只写 `/tmp`；未提交、未推送、未打包、未发布、未安装；未改产品码、未改 T-1 身份口径、未改 admission/settlement 接线、未改冻结证据，`tools/open_source_audit.sh` 与 CI 均未动。完整材料：`hygiene-mechanism-20261029/`（`INDEX.md` 为入口）。

#### 4.19.1 两个测量对象，不得混用

| | 原树审计（既有，未改） | 交付物闸门（本轮新增） |
|---|---|---|
| 工具 | `tools/open_source_audit.sh`、`tools/release_artifact_audit.py` | `tools/release_sanitize.py` |
| 对象 | 全部**已跟踪**文件，含全部 `research/` | 仅**显式输入清单**列出的文件 |
| 用途 | 枚举现存暴露，作待办清单 | 判定某一次发行物能否出门（exit 1 fail closed） |
| 本轮读数 | `PY_RC=1`，1947 FAIL / 9330 文件；`git grep` 1941 文件（research 1939 + 非 research 2） | 真实证据演示通过；负例全部拒绝 |

裁定 ① 的两条禁令在这里各落一半：原件保留、不改写（原树审计照旧红，不掩饰）；不因 `research/` 在库里就自动打包，也不靠忽略 `research/` 让任何一侧变绿（闸门只认清单）。

#### 4.19.2 五步闭环

1. **输入清单**：`build --inputs` 要求 `manifest_version=1`、`sources` 非空、每项恰好 `{path, output}`；路径必须相对且无 `..`；source 必须存在且位于 `--root` 内；**从不扫描目录**。
2. **独立副本**：只写 `--out`；源以只读方式读取（前后 SHA-256 逐字节相同）；规则只作用在副本；输出目录非空即拒绝；任一步失败即回滚本次已写文件，不留半成品。
3. **来源/校验清单**：`provenance.json` 记 `rules_version` 与每源 `source / source_sha256 / source_bytes / output / output_sha256 / output_bytes / rules_applied`；**不记录被脱敏的原值**。
4. **交付目录闸门**：规则版本一致、声明输出存在、哈希＋字节一致、4 类禁词、残留 home/temp 绝对路径、交付目录内未声明文件——逐条 fail closed。
5. **负向测试**：16 条（`unit-tests.log`，0.11 s），含关键一条「敏感原始字节 + 清单哈希一并改写为匹配」仍被拒（闸门查内容，不只查哈希）。

规则集 `sanitize-2026-10-29.1`：`home_paths` → `temp_paths` → 4 个禁词（`forbidden_0..3`），顺序固定、幂等。禁词**直接 import** 审计的 `FORBIDDEN`，两边规则不会漂移；本工具用字符串拼接构造 home 正则，自身不携带所脱敏的字面量，因此两个新工具在审计同一套谓词下 `hits=0`，无需把自己排除。

#### 4.19.3 真实冻结证据上的读数（`hygiene-mechanism-20261029/mech-demo.log`）

| 源（只读） | 原始命中 | 副本命中 | 字节 |
|---|---|---|---|
| `STAGE1-GAP-MATRIX-20261028.md` | 14 | 0 | 89831 → 89811 |
| `ACCEPTANCE-20261026-BUILD-97043902.md` | 62 | 0 | 266062 → 265852 |

源文件 build 前后 `sha256` / 字节数不变（`d004094b…` / 89831、`94efe635…` / 266062）⇒ 冻结原件未被触碰。闸门 `PASS`，副本哈希 `8457a6d6…`（89811 B）与 `abe0884…`（265852 B）写入清单。负例：原始字节放回并把清单改成匹配 → `forbidden_0 x9 / forbidden_1 x4 / forbidden_2 x1 / home_paths x6`，RC=1；多一个 `notes.md` → 唯一 FAIL 为 `undeclared file`，RC=1。

**一处收紧**：闸门最初会把命中的字面量与完整绝对路径打印出来，等于把泄漏值再写进 CI 日志与失败转录。现改为只报规则 id、次数与首个字节偏移（如 `forbidden_0 x9 first@45585`），检测能力不变；本节的审计摘要把同样处理（`artifact-audit-summary.txt`），因此新增材料自身 `hits=0`。

#### 4.19.4 没做完、也不能宣称的部分

- **hygiene 未整体完成**：原树审计仍 `PY_RC=1`（1947/9330）。本轮只是把「未来发行物怎么出门」的机制建起来。
- **这不是发行清单**：`inputs.json` 只演示 2 个文件。下一版发行物到底含哪些文件、清单谁维护、如何接进打包与 CI，均未定、未做。
- **只覆盖 UTF-8 文本**：二进制证据（Office/PDF/图片容器）一律拒绝而非猜测处理，需要各自可证的流程。
- 脱敏是文本替换，不保证语义完整，也不替代「内容本身该不该公开」的判断。
- 新增工具目前**未被 git 跟踪**，因而不在原树审计的枚举范围内；它们自身的干净性是逐文件扫描 `hits=0` 记录的。
- 发布资格不变：不提交、不推送、不打标签、不发布、不安装；整体发布阻断仍然成立。

### 4.20 owner 复核（2026-10-29）：③-B 局部完成 · 机制演示通过 · 三项接入前确认

owner 复核结论（依据归档记录，未独立读取本机文件）：③-B 的三条路径区分成立、可转为**局部完成**，不再扩大产品接线；脱敏机制**本地演示通过**，但「实际发行清单与构建／CI 集成」「源码集与候选身份冻结」「最终 DMG 与剩余回归」均未完成，整体 hygiene 未通过、发布授权未取得。下一步顺序：**二.5（API 路径回归 + 真实模型取消—重试）→ 二.6 与下一版源文件集合 → 阻断 3 冻结候选身份 → 机制接入实际发行流程 → 二.4 最终 DMG 验收**。owner 同时明确：把工具纳入 Git 跟踪是为了让发布机械可复现、可审阅，**不等于授权提交／推送／打标签／发布**。

#### 4.20.1 三项「接入前必须确认」的当前回答

**① 路径约束是物理约束，不是字符串约束 —— 已确认，并补了 3 条负向测试（19/19）。**

- 源侧：`build` 对 `root / path` 先 `resolve()`（跟随符号链接）再 `relative_to(root)`。实测：manifest 写 `inside/link-to-outside.md`、链接指向 root 之外 → `SanitizeError: source path escapes its root`，输出目录未生成任何文件。
- 输出侧：`out / output` 同样 `resolve()` 后与 `--out` 比较，故 `sub/escaped.md`（`sub` 是指向外部目录的链接）被判越界（新增 `test_output_containment_is_physical_not_lexical` 直接把守卫钉在物理比较上；`build` 另有「输出目录必须为空」作为第一道）。
- 交付侧：`gate` 本轮新增显式拒绝——声明输出若为符号链接 → `declared output is a symlink`；目录扫描中发现任何符号链接 → `symlink in deliverable directory`（新增 `test_gate_fails_on_a_symlinked_output`，链接目标内容干净且哈希与清单一致也照样拒绝）。
- **一处自我更正留档**：新测试的第一版把「外部目标」建在了 `--root` 内部，测试因此按预期不触发拒绝而失败——这恰好证明断言测的是物理逃逸，不是名字里有没有 `..`；把目标移到独立临时目录后通过。

**② 清单与来源记录必须绑定到确定的候选 —— 未完成，属接入步骤，不假装已做。**

`provenance.json` 目前只证明「副本 ↔ 清单 ↔ 源文件」的内部一致性（内容没被换、规则版本没变），**不是独立的来源真实性证明**。接入时必须把以下一起写进候选身份并互相绑定：冻结源码集身份、输入清单身份（清单文件本身的哈希）、工具与规则版本（含两个工具文件的哈希）、产物清单。这些都要等阻断 3 的候选冻结才有对象可绑。

**③ 文本机制不替代二进制产物验收 —— 维持，不扩输入范围。**

工具继续**拒绝**非 UTF-8 源（「无法证明可脱敏」）。DMG、签名后的 app、其他二进制容器走各自的打包与产物验收路径；不通过扩大或绕过文本工具的输入范围来制造「统一门禁」的假象。

#### 4.20.2 两个测量对象的结论继续分开

原树审计 2026-10-29 复跑仍 `PY_RC=1`（1947 FAIL / 9330 跟踪文件）：这与裁定 ①「保留冻结历史证据、不重写历史」一致，**需要继续留存与解释**，不是待消除的噪声。未来能否发布由**确定的候选文件集合 + 该交付物的门禁结果**判定，既不能只看原树扫描，也不能只看两个演示文件的 PASS。

#### 4.20.3 执行边界

未提交、未推送、未打标签、未发布、未安装；未改产品码、T-1 身份口径、admission／settlement 接线与冻结证据；`tools/open_source_audit.sh` 与 CI 未动。两个新工具仍**未被 git 跟踪**；按 owner 裁定，纳入跟踪是接入步骤的一部分，且不构成提交／发布授权。
