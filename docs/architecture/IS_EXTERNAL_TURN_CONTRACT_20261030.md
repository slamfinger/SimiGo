# IS 外部轮次数据契约（2026-10-30）

**性质**：数据契约 + 检索资格规则，描述当前实现（不是能力规划）。
**权威实现**：`Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoESISDatabase.swift`、
`SimiGo/Protocol/HTTPServerRemoteIS.swift`、`SimiGo/Protocol/HTTPServer.swift`。
**边界**：本文只记录产品代码与测试层已经成立的事实。真机验收读数另见
`research/agent-runs/simigo-es-is-realmodel-20261026/ACCEPTANCE-20261026-BUILD-97043902.md`
（测试层读数不写入该文件）；W4、Agent 分类取证等未关闭项见 §8。

## 1. 三个状态是三个问题

外部 API 的信息可以从外部进来，也可以只保留不消费。把「入库」「结算」「可检索」
当同一个开关是此前 Codex 污染事件的根因之一，因此三者分开定义：

| 状态 | 含义 | 载体 |
| --- | --- | --- |
| 已记录 recorded | 文本与来源已落库，任何检索都不会选中它 | `chat_messages.turn_state='recorded'` |
| 已结算·已验证 committed | 该请求两行（用户/回答）都到齐，且回答被判定完整 | `turn_state='committed'` + `verified_at` |
| 可检索 retrievable | 在 committed 之上，还要通过消费方的范围/来源/依赖检查 | `chatIndexRows(sessionIDs:)` 等只读 committed |

已记录不等于可检索：`chatIndexRows` 只 SELECT `turn_state='committed'`
（`SimiGoESISDatabase.swift:3069` 起，条件在 `:3076`）。在途文本可以被记录，
但不会因为「已经在数据库里」就成为另一个并发请求的已结算知识。

## 2. Schema（迁移 v16，`simigo-external-turn-provenance-v16`）

`chat_messages` 新增列，全部追加、不重写历史行：

| 列 | 类型 | 语义 |
| --- | --- | --- |
| `source_kind` | TEXT NOT NULL DEFAULT `'local'` | `local` / `external` |
| `source_provider` | TEXT NULL | 上游识别名（当前为 `openai-compatible`） |
| `request_id` | TEXT NULL | 生产方请求身份，同一请求的用户/回答两行共享 |
| `verified_at` | TEXT NULL | 结算发生时刻 |

旧行默认 `source_kind='local'`，原有 `turn_state` 保持不变；v16 不做回填、
不做语义改写。新增索引 `idx_chat_messages_request`、`idx_chat_messages_source`。

`turn_state` 取值：`pending` / `recorded` / `committed` / `internal`。
`internal` 是「保留但不参与结算」的终态（见 §3.3）。

## 3. 写入与结算规则

### 3.1 外部 API 转发（`forwardToRemote`）

对 `POST /v1/chat/completions`、`/chat/completions`、`/v1/completions`、
`/completions`、`/v1/responses`（仅当 `remoteBackend != nil` 时走转发）：

1. **转发前** `beginExternalTurn`：从请求体抽取用户文本，写用户行
   `turn_state='recorded'`。写库失败不影响客户端请求。
2. 上游返回后 `finishExternalTurn`：抽取回答文本；只有
   `completed == true` 且文本非空才调用 `verifyExternalTurn`。
3. `verifyExternalTurn` 要求该 `(session_id, request_id, source_kind='external')`
   的用户行与回答行都存在，然后把 `turn_state='recorded'` 的两行改为
   `committed` 并写 `verified_at`；只更新 `recorded` 行，重复调用幂等。

「完整」的判据按 wire 区分：

| wire | 非流式 | 流式 |
| --- | --- | --- |
| chat / completions | `finish_reason != "length"` | 收到 `[DONE]`；`length` 结尾不结算 |
| responses | `status` 缺省或 `"completed"` | `response.completed`；`incomplete/failed/error` 不结算 |

HTTP 状态不在 2xx 时不结算。流式捕获上限 8 MiB，超限则不结算（用户行保持
`recorded`）。

### 3.2 未结算的三种留痕

`[REMOTE_IS]` trace 逐条说明发生了什么，便于回放：

- `recorded=user request=… session=…`
- `recorded=answer_absent …`（回答侧没有可结算文本）
- `recorded=answer_unverified …`（回答文本有，但被判不完整）
- `verified=1|0 …`（`1` 表示该请求的两行已提交）
- `record_failed=open_db|user|answer …`（写库失败，不影响转发）

### 3.3 内部记账（`internalOperation`）

客户端声明为内部操作的轮次，用户/回答行都以 `turn_state='internal'` 落库：
文本保留可审计，`verifyExternalTurn` 对它返回 0 行变更，永远不会成为可检索知识。
声明通道是 `metadata.simigo_request_scope` / `client_metadata.simigo_request_scope`
或 `X-SimiGo-Request-Scope: internal`，只认客户端显式声明，不从 wire、会话或内容推断。
测试：`testInternalOperationIsKeptButNeverPromoted`（数据层）、
`testInternalDeclaredForwardedTurnIsKeptButNeverPromoted`（真实 HTTP 转发路径）。

### 3.4 本地重试不收养外部行

`lastUserMessage` 只取 `source_kind='local'` 的最近用户行。外部行属于另一个生产方
的请求身份，本地轮次的 retry 复用不得采纳或提升它。
测试：`testLocalRetryNeverAdoptsExternalRow`。

## 4. 并发不变量

- 结算键是 `(session_id, request_id, source_kind='external')`，不是「最近一行」：
  一个请求的在途文本不可能被另一个请求的结算顺手提升。
- `verifyExternalTurn` 要求两侧都在，单边在途（只有用户行）不会提交。
- 测试：`testVerifyingOneRequestNeverPromotesAnotherInFlightTurn`、
  `testVerificationRequiresBothSides`。

## 5. 检索资格

`committed` 只是「这一行自己的事实」。某次请求能否消费它，还要看该请求的范围：
`chatIndexRows(sessionIDs:)` 按会话取 committed 行，`SimiGoInformationLoop.resolve`
在其上做查询匹配。内部记账行（`internal`）与在途行（`recorded`）在数据层就被排除。

## 6. 端到端链路（产品代码，非测试替身）

`SimiGoTests/RemoteISForwardingTests.swift` 用真实 `HTTPServer` + 真实
`forwardToRemote` + loopback 桩上游，验证：

1. 非流式完整回答 → 两行 `committed`、`source_kind='external'`、共享 `request_id`、
   `verified_at` 非空，且 `SimiGoInformationLoop.resolve` 命中这两个 message id；
2. 流式 `[DONE]` → 同样提交；
3. `finish_reason='length'` → 两行 `recorded`、`verified_at` 为空、检索为空；
4. 请求头 `X-SimiGo-Request-Scope: internal` → 两行 `internal`、`verified_at` 为空、
   正文仍可审计读出、检索为空（内部记账保留但不获得检索资格）。

测试只在注入 `SIMIGO_HOME`/`SIMIGO_CACHE_ROOT`/`SIMIGO_STATE_GRAPH_STORE` 时运行，
否则 `XCTSkip`，因此普通 `xcodebuild test` 不会写真实 `~/.simigo`。

## 7. 未覆盖面（当前实现的已知空洞）

- `GET /v1/models` 不产生轮次，不捕获。
- 只有工具调用、没有文本的响应：回答侧没有可结算文本，用户行保持 `recorded`。
- 捕获上限 8 MiB 之外的流式响应不结算（用户行仍 `recorded`）。
- 外部轮次与 ES/KV 复用契约（结算消费边）尚未接线：本契约只覆盖 IS 留存与检索资格。
- `chatIndexRows` 仍为模块内 API；应用层只能经 `SimiGoInformationLoop` 观察可检索性。

## 8. 未关闭项

- 真机 + 真实模型的读数尚未取得：本文的结论是代码与隔离测试层结论，
  不能替代安装版验收。
- Agent 分类取证（用户对话 / 后台 rollout / 工具调用 / 内部记账分别的
  发送、落库、检索行为）为路线 01。其中「请求实际发送了什么」已在 §9
  取到客户端侧证据；「服务端收到什么 / IS 存了什么 / 注入了什么」仍需安
  装版窗口（见 §9 末）。
- W4 预算门与 #138 样本污染是独立问题，本文不涉及、也不因本文改动而关闭。

## 9. 客户端请求通道实证（2026-10-30，路线 01 第一步）

用本机回环 stub（`build/a30/capture/stub.py` / `stub_tool.py`）+ 隔离
`CODEX_HOME`（`build/a30/codex_home_capture`）让**真实 Codex 客户端**
`/Applications/Codex.app/Contents/Resources/codex`（0.133.0）直接发请求，
记录原始头部与请求体到 `build/a30/capture/requests*.jsonl`。不经过模型、
不经过安装版、不写真实 `~/.codex` 与 `~/.simigo`。

**实际发出的通道（两次捕获完全一致）**

| 通道 | 值 |
| --- | --- |
| `POST` 路径 | `/v1/responses`（`wire_api = "responses"`，`stream: true`） |
| 头部 `originator` | `codex_exec`（二进制内另有 `codex_cli_rs` / `codex-tui` / `codex_vscode`，并受 `CODEX_INTERNAL_ORIGINATOR_OVERRIDE` 覆盖） |
| 头部 `user-agent` | `codex_exec/0.133.0 (Mac OS 27.0.1; arm64) …` |
| 头部 `session-id` / `thread-id` | 会话 UUID |
| 头部 `x-client-request-id` | 同会话 UUID |
| 头部 `x-codex-window-id`、`x-codex-beta-features` | 存在（值不含身份语义） |
| 头部 `x-codex-turn-metadata` | JSON：`session_id`、`thread_id`、**`thread_source`**、`turn_id`、`sandbox`、`turn_started_at_unix_ms` |
| 体 `client_metadata` | `{"x-codex-installation-id": …}` |
| 体 `prompt_cache_key` | 会话 UUID |
| 体 `store` | `false` |

**没有的东西**：核心二进制与 `app.asar` 里都**不存在**
`simigo_request_scope` / `x-simigo` / `request_scope`（grep 计数 0）。
即 Codex Desktop 当前版本**不会**作 §3.3 意义上的 internal 声明；任何
「把 Codex 后台轮判为内部记账」都不能依赖客户端声明，只能来自服务端可
观测通道（`originator`、`x-codex-turn-metadata.thread_source`、UA）或
带外登记。

**已取到的三类（可回放）**

1. 用户对话轮：1 次 `POST`，`input` 为 3 条 message，`thread_source=user`
   （`build/a30/capture/requests.jsonl`）。
2. 工具轮：同一 `turn_id` 连续 2 次 `POST`；第 2 次 `input` 里追加
   `function_call` + `function_call_output`（工具输出原样回到 wire），
   `thread_source` 仍为 `user`（`requests_tool.jsonl`）。
3. Review 子代理轮：`codex review --uncommitted`，1 次 `POST`，
   **`thread_source=subagent`**，且 `x-codex-turn-metadata` 多出 `workspaces`
   （含 `latest_git_commit_hash`、`has_change…`）（`requests_review.jsonl`）。

**`thread_source` 的取值词汇（同一二进制）**

- app-server 协议侧 `SessionSource = { "custom": … } | { "subAgent": … } |
  { "internal": … } | { "subagent": … }`；子代理细分为 `subAgentReview` /
  `subAgentCompact` / `subAgentThreadSpawn` / `subAgentOther`。
- wire 实测值：`user`、`subagent`。
- 含义：**客户端自带的来源分类里就存在 `internal`**。因此「内部记账」这类
  轮次可以由 `thread_source` 直接区分，不需要 SimiGo 自造声明头；但该值
  在真实后台轮上的出现仍需安装版窗口取证（§8）。

**尚未取得**：后台 rollout / 内部记账两类在真实客户端上的 `thread_source`
取值（需触发 Codex 自身的后台轮），以及服务端收到什么、IS 存了什么、检索
注入了什么（需装 a30 包 + 手动起服务 + `SIMIGO_TRACE_CLIENT_HEADERS=1`）。
`build/a30/candidate_identity.json` 为对应安装包身份。
- W4 预算门与 #138 样本污染是独立问题，本文不涉及、也不因本文改动而关闭。

## 10. 服务端第一份真机读数：并发 2 + 取消 + 提交（2026-10-30 03:50–03:56）

安装 a30（exe `0ff340bc…`）、菜单栏起服务后，出现一次真实客户端窗口。原始证据在
`build/a30/evidence/live-20261030-0350/`（日志快照 + 只读库快照 + README）。
该窗口**未开** `SIMIGO_TRACE_CLIENT_HEADERS`，故只有服务端侧，没有客户端请求头。

| 问题 | 读数 |
| --- | --- |
| 服务端收到什么 | 两条 `POST /v1/responses`、`stream=true`、`agent=default`、scope 分别是 `01a18936-c772…` / `-c678…`；`promptTokens` 9,571 / 13,620 |
| IS 存了什么 | id 244（c772，3,616 B）与 245（c678，6 B）两条 `user`、`turn_state=pending`、`source_kind=local`、`source_provider`/`request_id` 为 NULL，正文在 `is_objects` |
| 检索注入了什么 | `[IS] contextInject` 两条按 scope 分开：`c772 index=2 bytes=5012`、`c678 index=3 bytes=589`，均 `replay=0`；各落一条 `is-retrieval` 结算 |
| 在途是否污染他人 | 否。c772 于 03:51:01 `peerClosed` → `CANCEL` → `cancelCommitSkip` → `poisonedSessionEvict`，从未 `committed`/结算；c678 独立完成 |
| 结算 | 只有跑完的那条：245/246 转 `committed`（03:56:06），答案结算 `18EA8656…` `VALID`/`valid` |
| 可检索（下一轮） | **未观测**：本窗口没有同 scope 的后续轮，`replay=1` 未出现 |
| W4 | `skip_record reason=model_warmup` 仍在，样本未记录；与本表其它行无关 |

两条新事实（需裁定，不在本文范围内自行关闭）：

1. **取消的本地轮没有终止态**：id 244 至今仍为 `pending`。fail-closed 成立
   （普通检索只读 `committed`），但行状态不再反映「该请求已死」。
2. **本地路径不写 `request_id` / `source_provider`**，而外部转发路径
   （`recordExternalTurn`）会写。路线 02 要求的「请求身份」目前只在外部路径成立。

## 11. 三方真实客户端窗口：Codex / ZCode / Qoder（2026-10-30 13:45–14:01）

证据：`build/a32/three-agent-live-20261030/`（两段 trace + 只读行导出 + 结算导出 + 哈希）。
安装版 PID 63514、`:8000`；05:14 suspend → 13:46:04 冷加载 5.7 s。owner 在三个客户端各发一条「你好」。

### 11.1 首快照（13:53:41）

| 问题 | 读数 |
| --- | --- |
| 服务端收到 | 5 条 user 行、4 个 scope：Codex `01a18b57-ec36…`（「你好」+ rollout 分析）、`01a18b57-ede4…`（标题生成）、`session_756b…`（chat.completions，5 条消息，30,501 tok）、`info-beec0a…`（无身份 chat.completions，2 条消息，26,437 tok，6+ 次重试） |
| IS 存了 | 全部 `turn_state=pending`、`source_kind=local`、`agent=default`、无 `request_id` |
| 检索注入 | 三条「你好」共享同一 685 B 块（`replay=1`）；Codex 标题生成 5,012 B、rollout 分析 4,652 B |
| 结算 | 时点 0 条 answer settlement；Qoder 家族 60 s 取消（13:46:58 / 13:48:01 / 13:49:28 / 13:53:29） |
| W4 | `gate=withdrawn … action=admit`，无 503 |

### 11.2 复快照（13:54–13:56）：两家完成并结算，结论更正

首快照的「0 条 committed」只是时点事实，后续读数如下（`chat-rows-258-266.csv`、
`settlements-window-2.csv`、`trace-segment-2.log`）：

| 行 / 结算 | 事实 |
| --- | --- |
| 263 + `53A24744-…` | ZCode assistant「你好！有什么可以帮你的吗？」`committed`；valid / VALID / state `chat-197fe008` |
| 264 + `D2450577-…` | Codex ec36 assistant `committed`；valid / VALID；user 261「你好」随之 committed |
| 265 + `0831BE71-…` | Codex ec36 rollout 分析回答（224 tok）`committed`；valid / VALID；user 262 随之 committed |
| 258 | Qoder 仍 `pending`（13:54:55、13:55:52 `peerClosed`/`DETACH`） |
| 260 | Codex 标题生成仍 `pending`（13:54:35 `generation_contended` 分离） |

- **ZCode 没有 60 s 看门狗**：`r=cc65fc`（30,501 tok，`s=sessio`）13:46:07 起，13:54:12 prefill
  30501/30501，`ttft=434214 ms`、`stop=complete`、genTokens=8，13:54:15 completed。预算门同样
  先 `reject_estimated estMs=159173` 再 `action=admit`。→ 60 s 只属于 `s=openai` 家族。
- **Qoder 的前缀复用成立但无人接收**：13:47:01 `memPoolCapture tokens=24408` 伴
  `cancelPrefixUnproven captured=24408`；13:55:41 同一 26,437 tok 重试在已断连请求上
  `memPoolHit matchedTokens=24408`；13:55:52 `generation_contended` 分离 → `cancelCommitSkip`
  → `memPoolCaptureRefused (rows 26439 ≠ ledger 0)`；13:55:53 下一重试 `sessionAdopt own=transfer`。
  → 客户端已放弃，258 无 committed。
- **Codex 标题生成走的是失败分离路径**（不是客户端取消）：`memPoolCaptureRefused rows 9567 ≠ ledger 0`。
  其 demand `733c15b3…` 已 `RESOLVED` 并落 `is-retrieval` 结算，但 turn 仍 `pending`：
  **检索结算 ≠ 轮次结算**，两者在库里是分离的。

复快照计数：`settlements` 276（+3：2 条 answer + 1 条 is-retrieval 复用）、`retrieval_settlements` 177、
`information_reuse_events` 1（无新增）。

新增三条事实（需裁定，不在本文范围内自行关闭）：

1. **后台轮与用户轮同权已实证**：rollout 分析（262→265）按普通轮 `committed` 并签发 VALID 结算，
   与用户轮（261→264）无差别；客户端不声明 `simigo_request_scope`（#139），服务端不读
   `thread_source` → 检索资格当前只由 `turn_state` 一道门决定。
2. **检索结果跨会话共享**：「你好」的两条 demand（`19be…` Qoder、`3633…` 后续复用）均无需新候选即可
   `RESOLVED`；demand id = SHA256(query + keywords + 候选集摘要 + stale)、不含 session
   （`SimiGoInformationLoop.swift:231-251`）。`chatSessionIDs` 只过滤 chat 行。
3. **完成时长与客户端看门狗决定结局**：ZCode 434 s 完成（无看门狗）、Qoder >100 s 冷 prefill 被
   60 s 取消、Codex 后台轮被 `generation_contended` 分离——三家同窗口的命运差异来自协议/调度，
   不来自 IS 资格。

### 11.3 Qoder 最终结算（14:01:01）：15 分 03 秒后，靠前缀池命中完成

证据：`build/a33/qoder-settled-20261030/`（14:00:09–14:02:55 trace 段 + 行/链导出 + 哈希）。

| 项 | 读数 |
| --- | --- |
| user 行 | 258 `committed`（13:45:58，6 B「你好」） |
| assistant 行 | 269 `committed`（14:01:01，42 B「你好！有什么我可以帮你的吗？」） |
| 答案结算 | `27A4CD73-C5BB-4055-8F4C-6802F13DE42D`，`VALID`/`valid`，14:01:01.910 |
| 检索结算 | demand `20bd247e…` → `is-retrieval:20bd247e…`，14:01:01.818 |
| 墙钟 | 13:45:58 → 14:01:01，**15 分 03 秒** |

- 首轮与多次 60 s 取消均未产出（§11.1）；结算发生在最后一次重试：
  14:00:43 `DETACH stop=1 … generation_contended` → 14:00:49 `memPoolHit matchedTokens=24408/26437`
  → 14:01:01 `mode=cross-session cacheHitTokens=24408 cacheEff=0.92 promptTokens=2029 ttft=12409ms
  genTokens=8 stop=complete` → `RELEASED r=f196a0 s=openai reason=completed`。
  → #136 内存前缀池把该轮从「26,437 tok 冷 prefill」压到 2,029 tok，第一次让 `s=openai` 家族在
  看门狗内完成并结算；§11.2「Qoder 无人接收」应限定为 13:56 时点。
- 14:01:01.822 / 14:01:07.548 两条后台标题/建议请求（scope `info-268f68b3…`、`info-b209bd…`）
  分别复用 `A36A7F4F…` / `2DB5CC75…`（`model_calls=0`），来源结算生成于 2026-10-29；
  本次各新增一条 `committed` assistant 行（268 `{"title":"打招呼"}`、270 `NO_SUGGESTION`）。
  **未裁定**：同 query 跨天/跨 scope 复用标题与建议答案、以及重复后台行进入可检索集是否合格
  （关联 #124/#125/#126）。

### 11.4 可检索资格：当前实现只由 `turn_state` 一道门决定

`chatIndexRows`（`SimiGoESISDatabase.swift:3069-3077`）的 SQL 只有
`WHERE c.turn_state='committed'`，不带 role、`source_kind`、前台/后台或 Agent 条件；
`sessionIDs` 参数只做 scope 过滤。demand id 不含 session（§11.2 第 2 条），
所以命中还可跨 Agent 复用。

| 轮次类别 | 入库行 | 结算 | 可检索 |
| --- | --- | --- | --- |
| 用户对话（259/263、261/264、258/269） | 是 | VALID | **是**（committed） |
| 后台 rollout 分析（262/265） | 是 | VALID | **是**（与用户轮同权） |
| 后台标题生成（260） | 是（pending） | 无轮次结算 | **否**（pending） |
| 工具调用中间轮 | 不落库（P2，a31） | 不签发 | 不适用 |
| 后台标题/建议复用（268/270） | 是 | 复用既有 VALID | **是**（committed） |

即当前三态映射为：已记录 = 行存在（含 pending）、已结算 = `settlements` 行、
可检索 = `turn_state='committed'`。**持久化资格与检索资格的分离尚未实现**——
这正是路线 02 要补的合同，不是本窗口的既有行为。

**未覆盖面**：ZCode/Qoder 各自的 scope 归因为推断（前者带显式会话名与 5 条消息，后者无身份、
26.4k 脚手架与既往 Qoder 读数接近）；确认需一次 `SIMIGO_TRACE_CLIENT_HEADERS=1` 窗口。
复快照时（13:56）Qoder 258 与标题生成 260 均无 committed；258 已于 14:01:01 结算（§11.3），
260 仍 `pending`（与 §10 第 1 条同源）。
