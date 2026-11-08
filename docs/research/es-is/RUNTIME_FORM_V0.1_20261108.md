# 运行时形态：可安装 App，启动即信息空间宿主

时间：2026-11-08　对象：Release 2.2.4 (build 35)

## 结论

发行物是一个可双击安装的 App，不是源码包。App 启动后先起一个**不加载模型**的信息空间宿主
（`modelId = simigo-information-space`），占同一 API 端口，提供 `POST /mcp` 与 IS 读路由；
模型服务只有显式启动才接管端口，停止后回落宿主。

## 读数（本机 Release 构建）

| 检查 | 读数 |
| --- | --- |
| 启动即宿主 | `GET /v1/models` → `data=[simigo-information-space]`；`capabilities.is.mcp` 在位 |
| 用户根重复采样 | 2/4/8/14 s 均宿主，未见自动加载模型 |
| MCP 面 | `tools/list` = 9 个工具 |
| 检索 | `simigo_is_search` 返回带摘要校验的片段，命中 `upstream/P2_CONFIG_RECORD_20261105.md:418` |
| 载体状态 | schema 23、objects 1409、index 1942、dependency 87839、corrupt 0、dangling 0 |
| 安装包 | `hdiutil verify` VALID；包内 2.2.4；Apple Development 重签 |

## 边界

- 模型启停是菜单栏动作：没有 HTTP 启停路由，也没有 URL scheme，因此“装好就能被外部 Agent
  加载模型”目前不成立；外部 Agent 能直接用的是 MCP 面与 IS 检索面。
- 首启向导未完成时宿主不启动；安装器清标记后重开，向导完成后的激活事件补起宿主。
- 宿主与模型切换有约 1 秒端口交接窗口。

## 对研究的意义

宿主形态让“信息空间”先于模型成立：Agent 自带云端 API 时也能接入（方式 B，只写结算与审计），
模型只是可选的计算载体。这是 §3 的 carrier 论证在发行物上的对应物——不是“先有模型再挂记忆”，
而是“先有可持续的结算与检索面，模型按需接入”。

## Codex 侧接入（2026-11-08 实测）

`codex mcp add simigo --url http://127.0.0.1:8000/mcp` 写入 `~/.codex/config.toml`
（streamable_http，enabled）。经 Codex 自己的 MCP 客户端跑了两轮：

| 轮次 | 写入 IS 的结果 |
| --- | --- |
| `simigo_is_status` | 只读，不产生 demand/结算 |
| `simigo_is_search` | 新增 demand（`RESOLVED`）+ 检索结算 `is-retrieval:<demand_id>` |
| `simigo_es_begin` → `simigo_es_settle` | 新执行状态 → 内容结算（`validity=valid`）+ demand 置 `ADVANCED` |

计数对照：demands 250 → 252、settlements 380 → 382（1 检索 + 1 内容）。
只读工具不落轮次，是“不制造第二权威”的既定边界，不是缺口。

注意：`approval_policy=never` 下 Codex 会拒绝对 MCP 工具的任何调用；需要该会话允许审批，
或对该服务器显式放开（`mcp_servers.simigo.default_tools_approval_mode="approve"`）。

## 会话正文进 IS：两条链（2026-11-08 补）

改前实测：本机 `chat_messages` 里没有本轮 Codex 对话；`simigo_es_settle` 只落结算，
不落会话正文。因此“问过什么、答了什么”在 IS 里查不到。

补了两条：

1. **显式一轮**：新 MCP 工具 `simigo_chat_round(session_id, request_id, user, assistant)`，
   走已有外部轮次合同（`recordExternalTurn` → `recordExternalResponse` →
   `verifyExternalTurn`），写入即 `committed`、可检索；重复调用幂等（第二次
   `rows_promoted=0`、返回同一批 message_id）。
2. **自动全量**：把 `~/.codex/sessions` 注册为 IS 根（`iscli register`，29 MB / 63 文件，
   51 条内容结算、12 个超大或二进制跳过）。此后 rollout JSONL 的问答两轨都按文件进入
   索引，`is_search` 可直接命中。

读数：写入后 `is_search("你检查一下我这句话进入is数据库了吗")` 命中
`chat:codex-01a1b5b1/610`；`is_search("监控自动回落 MCP服务器轮次进入is数据库")` 命中
`work-00000000a93a6ce4/2026/11/08/rollout-*.jsonl` 两处。工具面 9 → 10。

## 图标语义与多格式采集（2026-11-08 二次修订）

菜单栏图标只表达一件事：谁在占这个端口。

| 状态 | 图标 |
| --- | --- |
| IS 宿主在跑（默认，MCP / 检索可用，无模型） | `bolt` 灰色描边 |
| 本地模型在跑（宿主回落，MCP 由模型监听器接管） | `bolt.fill` 实心绿 |
| 模型在跑但内存压力 warn / critical | 实心橙 / 实心红 |

采集侧此前只有 Qoder 桥接线，`AIStudioSource` / `DeepSeekSource` /
`FlatMessageExportSource` 三个适配器在包里没有任何调用方（死代码）。现改为
`MultiFormatCollection`：按文档结构识别（`recognizes`），不认扩展名，写外部轮次合同。

实测样本 `/Users/mr.simi/Desktop/大模型会话记录`：扫描 386 文件、识别 76、
轮次 2640、入库 2640（可检索 2416）、失败 0；格式分布 aistudio 1453 / deepseek 1169 /
flat-export 18。`is_search` 已命中 `chat:aistudio:…/1645` 等导入轮次。
