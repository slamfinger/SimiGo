# 读数记录：图会不会长（C）与论文锚点重算（D）

日期：2026-11-10；基准 HEAD `29217b0`（产品仓）、生产库 `~/.simigo/simigo.sqlite3` 只读

## C · 图会不会长

**写入者（代码事实，对 29217b0）**：dependency_edges 现有**三个**生产写入者——

| kind | 写入者 | 载体 |
|---|---|---|
| information-demand | `recordNativeSettlementWithIdentityAndAdvancement`（经 settleTurn 的 advancement 计划） | 模型结算 → 检索结算 |
| settlement-consumption | `recordSettlementConsumption`（ESISDatabase.swift:6110 起） | 消费结算 → 被消费结算 |
| **citation** | `recordInformationRetrieval` 提交事务内 `insertCitedSettlementEdgeInTransaction`（:5761，默认 kind="citation"，NOT EXISTS 去重，与源绑定同事务原子落边） | 检索结算 → 被引用的已结算结论 |

P1（2026-11-08）记录的 "citation 边无写入者" **已过时**：写入者已由后续提交补上
（InformationCitationEdgeTests 为其契约测试）。

**生产库活读数（2026-11-10，只读）**：

- 边：information-demand 161 / **citation 21** / settlement-consumption 7，共 189
  （对比 IS 会话 11-09 读数 items 6322 / edges 143 / citation 1）
- items 6738、demands 375、retrieval_settlements 371、settlements 562
- 密度：189 边 / 6738 items ≈ 2.8%——仍稀疏，但三种边都有活跃写入者且在增长
  （约 1 天 +46 边、citation +20）

**回答**：图在长（多写入者、多 kind、跨日增长）；"骨架不是网络"的表述需要更新为
"图在增长、citation 类已接线，密度仍低（~3%）；网络化程度未测"。P1 的"不主张
图会增长成拓扑"仍未关闭——本轮只证增长，不证拓扑化。

## D · 论文 file:line 锚点重算（对 29217b0）

论文附录（PAPER_S6_DRAFT 附录"数字出处对照"）引用的锚点，逐一重算：

| 论文锚点（旧） | 现锚点（29217b0） | 备注 |
|---|---|---|
| `SimiGoESISDatabase.swift:5109-5150`（DERIVED_CONSUMPTION+消费账行） | **文件更名** `ESISDatabase.swift:6110`（`recordSettlementConsumption`；validationStatusOverride :6134） | 类型同步去前缀：`SimiGoESISDatabase`→`ESISDatabase` 等 |
| `SimiGoESISDatabase.swift:4515-4537`（复用 consumerStateID: nil） | `ESISDatabase.swift:5371-5443`（字段 :5371、nil 调用 :5401、`recordInformationReuse` :5414） | |
| `HTTPServerChat.swift:555-600`（复用不写结算） | `:423-431`（[SETTLE_SKIP] wire=chat）、reusableAnswer `:584`、answer_reuse `:664`、复用分支 `:775`/`:1390` | |
| `HTTPServerResponses.swift:1341` | **:1341 未漂移**（同语义行仍在原行） | |
| `HTTPServerMCP.swift:561`（begin reusable_answer 恒 null） | `:665`；**语义未变**——`let reusable: [String: Any] = [:]` 硬编码空 + 注释"不得暴露历史答案"（:656-659） | 语义核实过，不是漂移成可返回答案 |
| `MCPInformationSpaceTests:243` | `:314`（另 :480/:498 三处同断言） | |
| `SimiGoSettlementAuthority.swift:5-12`（throw 即零持久） | **:12 原句在**（"a thrown error means nothing was persisted (fail-closed)"） | 文件未漂 |
| `SimiGoSettlementAuthority.swift:62-66`（payloadDigestMatches） | **:62 未漂移** | |
| `AGENT-ACCESS.md:229-240` | `docs/AGENT-ACCESS.md` §3.3（≈:229-238，"reusable_answer 恒为 null" 生命周期图） | |

**回答**：9 个锚点 8 个语义成立、行号漂移或文件更名；2 个行号未变（Responses:1341、
SettlementAuthority:62）；无一处语义反转。论文修订时按上表机械替换，MCP begin 的
"恒 null"可放心保留原文语义。

## 边界

- C 的增长读数是两时点差（11-09 IS 会话读数 vs 今日），中间无逐时点采样；
- D 只覆盖论文附录列出的 9 个锚点，未重算 §6.2/§6.3 正文提及的其他行号；
- citation 边的方向（检索→结论）按写入者代码与生产库样本目测一致
  （from is-retrieval:* → to UUID），未做全库方向统计。
