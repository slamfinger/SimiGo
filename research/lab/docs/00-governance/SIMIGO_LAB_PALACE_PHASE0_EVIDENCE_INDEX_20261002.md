# Phase 0 §2 证据索引 — 源码级锚点（服务树）

Date: 2026-10-02  
Scope（锁死）: 仅 §2 已登记语义判断的 `file → type/function → behavior`；无新架构探索，无 Swift 设计  
Anchor tree: **`.build/mp-venv312/lib/python3.12/site-packages/mempalace`（3.10.0，126 .py，实际 MCP 服务端）**

## 0. Finding-1：源码树锚定偏差（必须先读）

审计件 §1 声称范围 = 「已安装 mempalace 包全部 48 个 .py 模块」，
对应 `~/Library/Python/3.9/site-packages/mempalace`（`version.py`
= **3.3.3**）。但真实 palace 由 `.mcp.json` 指向的
`.build/mp-venv312/bin/mempalace-mcp` 服务（**3.10.0，126 .py**，
目录结构重组：`searcher/`、`mcp_server/` 子包、`wal.py`、`ids.py`、
`format_miner.py` 等）。

影响判定：

1. `content_date / content_date_source / id_recipe` 等字段在
   3.3.3 树**零写入点**，在 3.10.0 树有完整写入链——审计件这些
   行的源码依据实际来自服务树行为（其 DB 数据事实不受影响，
   且本索引已在服务树补齐锚点）
2. §2 的**语义判定本身**在服务树全部重锚成功，无一条因换树而
   失去依据；无语义反例
3. 审计件「48 模块」范围表述需更正为「服务树 3.10.0（126 .py）
   为权威锚点树；3.3.3 树为历史对照」——本更正不改变任何
   语义归类

## 1. Information 锚点

| §2 判断 | file → type/function → behavior |
---|---|
| drawer.content 逐字存储 | `miner.py` → `_build_drawer_metadata()`(:1697) + `add_drawer()`(:1766) → `collection.upsert(documents=[content])`，content 原文为 document；MCP 路径 `mcp_server/tools_write.py` → `tool_add_drawer()` 同构 |
| provenance：source_file/chunk_index/added_by/filed_at | `miner.py:1740-1748` metadata dict 逐字段写入；`tools_write.py:407-413` base_meta 同构 |
| provenance：source_mtime | `miner.py:1750-1751`（getmtime 缺失时键缺省，非伪造） |
| provenance：line_start/line_end | `miner.py:1752-1755`；Tier 6a 契约见 :1717-1720 docstring |
| temporal：content_date/content_date_source | `miner.py:1756-1757`；推导 = `_extract_content_date_with_source()`(:1667)，分级 filename/frontmatter/body/mtime（:1726-1729），「有日期无来源记 unknown，不回溯推断」 |
| 实现版本：normalize_version | `palace/__init__.py:83` `NORMALIZE_VERSION = 2`；:1747 写入 |
| 实现版本：id_recipe | `ids.py:24` `ID_RECIPE = "v3"`；写入点 `miner.py:1746`、`tools_write.py:415`、`format_miner.py:664` |
| 确定性 ID 方案 | `ids.py` → `make_drawer_id_from_chunk()`（`sha256(f"{source_file}\|{chunk_index}")` 截 24 位，`|` 分隔防拼接碰撞，模块 docstring :1-19 记录缺陷类历史）；MCP 内容寻址路径 `tools_write.py`（wing+room+content 哈希） |
| entities = 派生索引 | `miner.py:1340` `_extract_entities_for_metadata()`（ingest 时计算）+ :1762 条件写入；模块 `entity_detector.py` |
| extract_mode/ingest_mode | `format_miner.py:574-575,660-661`（"extract"/"format"）；`sweeper.py:311`（"sweep"）；读侧判定 `palace/mined.py:21-26` |
| wing/room/hall = 归档分类法（borderline） | `miner.py:1740-1742`（wing/room）+ `detect_hall()`(:1316) 按内容检测 → :1759 `metadata["hall"]`；**纯分类键，不承载出处/时间/内容** |
| KG 三元组 = Information（存储为机制） | `knowledge_graph.py:250` `add_triple()`：valid_from/valid_to/confidence + `source_drawer_id/source_closet/source_file` provenance 回链（docstring 引 RFC 002 §5.5）；区间倒置校验 :283-293 |

## 2. Execution/Continuity 锚点

| §2 判断 | file → type/function → behavior |
|---|---|
| Layer0 = 当前 Execution 身份 | `layers.py:77` `class Layer0` → 读 `~/.mempalace/identity.txt`（:80-91，用户手写纯文本） |
| Layer1 = 可再生的当前上下文呈现 | `layers.py:119` `class Layer1`（Essential Story，模块 docstring :9「Always loaded. Top moments from the palace」——自 palace 派生） |
| diary `agent` 字段 = Continuity | `mcp_server/tools_diary.py:9` `tool_diary_write(agent_name,…)`：agent_name 归一小写入库（#1243）、room 固定 "diary"、wing 缺省 `wing_{agent}`；entry_id = 时间戳+内容哈希 |
| checkpoint ack = 会话终点状态指针 | `mcp_server/tools_diary.py:289` `tool_memories_filed_away()`；注册 `schemas.py:679-682`；hook 联动 `mcp_server/_guards.py:274,290`（`hook_state/last_checkpoint`） |
| closet 指针 = 当前检索路由提示 | `searcher/query.py:100` `_closet_boosts()` docstring：「rank boost, never a gate」；closets 为 pointer lines（:104-106） |

## 3. Index / Mechanism 锚点

| §2 判断 | file → type/function → behavior |
|---|---|
| closet 仅排序信号非门 | `searcher/__init__.py:7` 模块 docstring + `query.py:100-115`（best-per-source boost dict，永不过滤结果集） |
| BM25 重排 | `searcher/ranking.py:141` `_bm25_scores()`；sqlite 词法路径 `searcher/sqlite_bm25.py:64` `_bm25_only_via_sqlite()`、:344 `_merge_bm25_union_candidates()` |
| ChromaDB/HNSW 持久化 | `backends/chroma.py`（PersistentClient；`repair.py:1909` 注释佐证「never imports hnswlib」的规避策略）；可替换后端注册 `backends/registry.py`（pgvector/milvus/qdrant/sqlite_exact 等，pgvector HNSW 索引 `backends/pgvector.py:1009-1017`） |
| WAL 操作审计 | `wal.py:75` `_wal_log()`；写调用例 `tools_write.py:395-404`（add_drawer 记 drawer_id/added_by/content_preview） |
| miner/sweeper = 摄入机制 | `miner.py` `process_file()`（读→chunk→route→batched upsert）；`sweeper.py`；`format_miner.py`（结构化提取） |

## 4. 最终 §2 核验结论（记录者）

1. 服务树重锚 **全部成功**：§2 三分表每行均有 3.10.0 服务树
   的 file/function 级行为锚点；零语义反例
2. 唯一更正 = Finding-1 的范围表述（48→126 模块、锚定树
   更换），不改变任何语义归类
3. borderline 项（wing/room/hall）维持开放，符合 human 裁定
4. **Phase 0 Semantic Surface = FROZEN 的翻转条件已满足**，
   待 human 终确
