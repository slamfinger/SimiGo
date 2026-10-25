# PALACE V2 G0 中间观察 ④ — Graphiti（源码级静态审计）

日期：2026-10-02  
状态：`INTERMEDIATE OBSERVATION #4 / GRAPHITI / STATIC SOURCE AUDIT`  
审计基线：github.com/getzep/graphiti @ `3c42764`（Zep 开源；shallow
clone，`.build/mempalace-src/graphiti`）  
定位：三系统中唯一以 **Entity → Relation → Memory** 为核心方向的样本；
H-PALACE-G0-01 的判定性对照  
范围声明：静态源码级；未运行（ingest 强制 LLM 提取）

## 1. System overview

```text
[O] 定位     = 「temporal context graphs for AI agents」——时间上下文
              图框架；对比静态 KG：跟踪事实如何随时间变化、维护
              到源数据的 provenance、支持 prescribed + learned
              ontology；增量更新不整图重算（arXiv:2501.13956）
[O] 底座     = 图数据库 driver（Neo4j/FalkorDB/Kuzu/Neptune）+
              embedding + LLM client（默认 OpenAIClient）
[O] 输入模型 = add_episode(name, episode_body: str, source_description,
              reference_time, source: EpisodeType.message|json|text…)——
              episode 为文本体；**无 docx/xlsx/pptx/pdf 处理**
              （文件→文本在调用方，同 Mem0）
```

## 2. Capability Matrix — Graphiti 列

| 分类 | 维度 | 判定 | 级别 |
|---|---|---|---|
| Ingestion | 文件发现/格式 | 无文件面（episode_body 字符串） | O |
| Ingestion | 增量更新 | episode 增量入图；实体/边去重（dedupe_nodes/edges_bulk）；不整图重算 | O |
| Ingestion | 删除/移动处理 | 事实失效语义：invalid_at（非删除） | O |
| Content | 原文保存 | episode 正文存于图数据库（可回查） | O |
| Content | 结构保留 | 无 Office 结构概念（文本入） | O |
| Content | chunk 策略 | episode 为单位（调用方切） | O |
| Context | path 处理 | 无文件路径概念；group_id 分组 | O |
| Context | metadata 处理 | 实体/边 attributes + 顶点/边类型映射（prescribed ontology） | O |
| Context | provenance | **边携带 episodes: list[uuid]**——每条关系可回源到摄入文本 | O |
| Retrieval | keyword search | full-text（图库原生） | O |
| Retrieval | semantic search | cosine（节点+边嵌入） | O |
| Retrieval | relation expansion | **BFS 为一等检索方法**（edge_bfs_search / node_bfs_search；bfs_max_depth；组合配方 full-text+similarity+bfs+cross_encoder） | O |
| Agent | MCP/API | mcp_server + REST server + Python API | O |
| Agent | model independence | 检索侧 embedder/cross-encoder 可插拔；**ingest 侧 LLM 硬依赖**（OpenAIClient 默认；extract/dedupe 走 LLM） | O |
| Storage | backend 结构 | 图库（nodes/edges/episodes/communities 四类对象）+ 嵌入 | O |

## 3. Architecture observation

```text
[O] 双时间轴（bi-temporal）：边 = created_at/expired_at（摄入时间线）
    + valid_at/invalid_at（事实时间线）——事实失效即 invalid_at 标记，
    历史保留不删除
[O] 摄取 = LLM 工程：extract_nodes / extract_edges / dedupe_bulk
    全链 LLM（自定义 prompts 目录 + entity_types pydantic 契约 +
    custom_extraction_instructions）
[O] 检索 = 配方化组合：SearchConfig recipes 将 NodeSearchMethod/
    EdgeSearchMethod（cosine / bm25 / bfs）与 Reranker（rrf / mmr /
    cross_encoder / node_distance / episode_mentions）组合成
    预定义配方（如 combined full-text+similarity+bfs+cross_encoder）
```

## 4. Memory Path Analysis（H-PALACE-G0-01 判定性证据）

```text
[O] Graphiti 组合配方的实际路径：
    query → similarity + full-text（种子节点）→ BFS 拓扑遍历
    （bfs_origin_node_uuids = 种子，bfs_max_depth 控深）
    → 相关边/节点 → cross_encoder/rrf 重排 → context
[O] BFS 语义：从种子节点出发的关系遍历（无种子则空）——
    遍历不是独立旁路，而是组合配方内的检索阶段
```

**H-PALACE-G0-01 判读（Assumption Register 更新）**：

```text
假设原始问句：Memory retrieval 是相似度匹配还是关系遍历？
三样本答案（Observation 级）：
  MemPalace 主路径 = hybrid 相似度（KG 为独立旁路工具）
  Mem0 主路径      = 相似度（OSS core 无图模块）
  Graphiti         = 相似度/全文提供种子 + BFS 关系遍历
                    融合进检索配方（模式 B 实现存在）
假设状态更新     = 全局「纯相似度」不成立；精确事实 = 「关系遍历
                  能力存在，但仅 Graphiti 将其融合进检索配方；
                  另两家为旁路或缺失」——假设由 UNVERIFIED 升格为
                  ANSWERED-DIVERGENT（分系统分歧即发现）
```

## 5. Storage observation（L0/L1/L2 框架）

```text
[O] L0 = 调用方文件（系统外）；episode = 入图的源文本（≈L1 存储化）
[O] L2 = 实体/关系/社区（LLM 建图）——与 episode 共存于同一图库
[O] 删库恢复：episode 文本随库灭；L0 在则可重摄入，但实体/关系
    抽取经 LLM = 非确定性重建（Open Question：同输入两次建图
    产物 diff）——介于 MemPalace（纯函数重建）与 Mem0（记忆即
    本体）之间的第三形态：源文本存储化 + LLM 建图索引
[O] 时间语义：事实按 valid_at/invalid_at 演化且历史可查——
    「旧信息可寻？引用哪一版」在图层面有原生答案（对照 V1
    再激活条件：identity/version 的信息域对应物已在此出现）
```

## 6. Real document compatibility

```text
[O] 同 Mem0：episode_body = 字符串；Office 四格式无处理代码
[I] 推断：Graphiti 在 PALACE 场景的可组合角色 = 关系/时间记忆层；
    文档结构（Sheet/Cell）同样在其边界外
```

## 7. Reusable components

```text
[O] bi-temporal 边模型（valid/invalid + created/expired 四时间戳）
[O] 配方化组合检索框架（method×reranker 正交组合）
[O] BFS 种子遍历实现（图库原生 search_interface + 兜底查询）
[O] episode→边 provenance 链
[O] prescribed + learned ontology 双模（entity_types pydantic 契约）
```

## 8. Missing capability against PALACE scenario

```text
[O] 无文件面（同 Mem0）；episode 文本化 = 结构语义边界外
[O] ingest LLM 硬依赖 + 非确定性重建
[O] 跨文档比较/综合/生成 = 不在系统内（同前两家——
    三系统一致：这些是 Agent 侧任务）
```

## 9. Research questions generated

```text
RQ-G1  BFS 种子质量依赖：相似度首轮失败时拓扑遍历的召回坍缩？
RQ-G2  LLM 建图确定性（同输入两次建图 diff）——与 RQ-3/M0-3 同族
RQ-G3  bi-temporal 查询（as-of 时刻的事实状态）对 E6 场景的覆盖度
RQ-G4  prescribed ontology（entity_types 契约）与 PALACE 未来
       semantic relations 的关系（仅登记，不预答）
```

---

**中间观察状态**：Graphiti 静态审计完成。三系统齐备，可进入 G0
结论门（AUDIT_RESULT 九节：跨系统 Comparison + Gap 收束
RQ-PALACE-01/02/03 + H-PALACE-G0-01 + human 六条工程事实框架，
含第 6 条「查询状态可持久化/可继续」未决空间）。
