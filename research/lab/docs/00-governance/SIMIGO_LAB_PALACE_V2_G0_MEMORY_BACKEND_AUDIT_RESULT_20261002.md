# PALACE V2 G0 Memory Backend Survey — AUDIT RESULT

日期：2026-10-02  
状态：`G0 CONCLUSION DRAFT / AWAITING HUMAN SECOND LAYER`  
协议：`SIMIGO_LAB_PALACE_V2_G0_MEMORY_BACKEND_AUDIT_PROTOCOL_20261002.md`
（FROZEN / APPROVED）  
证据基座：中间观察 ①②（MemPalace 静态+运行时，FROZEN）/ ③（Mem0
静态）/ ④（Graphiti 静态）；克隆基线 `5ea40d3` / `abb81c8` / `3c42764`  
结论纪律（human 2026-10-02）：Comparison → Gap；**禁止 Gap → PALACE
schema**；不选「谁最好」；第 6 条（查询状态持久化/继续）保留未决
空间，不回答；不提前改 V2、不定义 Query State schema

## 1. System overview（三方向样本）

```text
① MemPalace（Artifact → Memory）
   本地文件 verbatim 式派生索引（wings/rooms/drawers + hybrid 检索
   + 可选 temporal KG）；核心 API-free；Office 走独立 extract 模式
② Mem0（Agent → Memory）
   对话消息 LLM 蒸馏事实陈述 + 事件式生命周期（ADD/UPDATE/DELETE
   + history 账本）；20+ 向量库适配；LLM 核心硬依赖
③ Graphiti（Relation-centric Memory）
   bi-temporal 上下文图（实体/关系/episode/社区）；LLM 建图；
   配方化组合检索（cosine/bm25/bfs × rrf/mmr/cross_encoder）
```

## 2. Capability Matrix（跨系统；O=Observation / I=Inference / OQ=Open Question）

| 维度 | MemPalace | Mem0 | Graphiti |
|---|---|---|---|
| Ingestion·文件发现 | 分模式（默认文本/代码；Office=extract） | 无 | 无 |
| Ingestion·格式支持 | pdf/docx/pptx/xlsx/epub/rtf（extract） | 不适用（messages） | 不适用（episode 字符串） |
| Ingestion·增量更新 | mtime 跳过 + dedup 后备 | LLM 事件决策 + MD5 去重 | episode 增量入图 + dedupe，不整图重算 |
| Ingestion·删除/移动 | gitignore-aware prune | LLM 语义 DELETE | 事实失效（invalid_at），非删除 |
| Content·原文保存 | L1 转换文本 verbatim（L0 不动） | 无（LLM 改写陈述） | episode 源文本存图 |
| Content·结构保留 | Office→Markdown（压平） | 无结构概念 | 无结构概念 |
| Content·chunk 策略 | 800/overlap 可配置 | 无 chunk（陈述为单位） | episode 为单位 |
| Context·path 处理 | source_file 全链 + locus 索引 | 无 | 无（group_id 分组） |
| Context·metadata | 扁平 17 键实测 | data/hash/lemmatized/时间戳/attributed_to | 实体/边 attributes + 类型契约 |
| Context·provenance | drawer 级 source_file+chunk_index；KG triple 级溯源列 | 记忆→源消息链未见（OQ） | 边携带 episodes[uuid]（源级回链） |
| Retrieval·keyword | BM25（FTS5） | BM25（lemmatized） | full-text（图库原生） |
| Retrieval·semantic | vector 主路径 | vector 主路径 | cosine（节点/边） |
| Retrieval·relation expansion | 无（KG 旁路工具） | 无（OSS core 无图模块，OQ） | **BFS 一等方法（入配方）** |
| Agent·MCP/API | CLI+MCP（45 工具称）+Python API | SDK×2+REST server | MCP+REST+Python API |
| Agent·model independence | 核心可替换（embedding 可换/closet LLM opt-in） | 写路径强制 LLM（provider 无关） | 检索侧可插拔；ingest LLM 硬依赖 |
| Storage·backend | 可插拔（Chroma/sqlite_exact/pgvector/qdrant/milvus/rust） | 20+ 向量库 | 图库（Neo4j/FalkorDB/Kuzu/Neptune） |

## 3. Architecture observation

```text
[O] 三种摄取哲学：
    MemPalace = 确定性转换管线（读时转换→chunk→索引；纯函数倾向）
    Mem0      = LLM 蒸馏管线（消息→事实陈述→事件生命周期）
    Graphiti  = LLM 建图管线（episode→实体/关系→bi-temporal 图）
[O] 三种「事实边界」：
    MemPalace = 原始文件是事实边界（库=可重建派生索引）
    Mem0      = 蒸馏后的事实是边界（原始文件不在系统内）
    Graphiti  = 源文本存储化 + LLM 建图索引（第三形态：
                介于两者之间；但重建经 LLM 非确定性）
```

## 4. Storage observation（L0/L1/L2 框架下）

```text
[O] MemPalace：L0=用户磁盘（不动）；L1=MarkItDown/striprtf 转换
    文本；L2=chunk/embedding/closet/KG——删库可由 L0 重建（实测）
[O] Mem0：L0 缺位；L1 不存在；L2 即本体——库删即记忆灭
[O] Graphiti：L0 缺位；L1=episode 文本存图；L2=LLM 建图——
    库删可重摄入但建图非确定性（OQ）
[I] 推断（bounded）：三者共同点 = L2 全部可弃式或可部分重建，
    「memory 层是否承载不可再生事实」在三系统中均未出现——
    但三者也都未回答「长期使用后 L2 中是否生长出 L0/L1 承载不了
    的语义」（G3 问题，未决）
```

## 5. Retrieval path observation（H-PALACE-G0-01 收束）

```text
[O] MemPalace：query → hybrid（BM25+vector）+ metadata 范围 +
    时间窗 → drawer；KG=独立旁路工具
[O] Mem0：query → scope 过滤 + vector similarity（+BM25 辅助）
    → 记忆陈述
[O] Graphiti：query → 相似度+全文（种子）→ BFS 拓扑遍历
    （max_depth）→ 相关边/节点 → 重排 → context
[O] 三者检索输出均无「跨文档比较/综合/生成」工作流——这些是
    Agent 侧任务
```

**H-PALACE-G0-01 正式收束（human 措辞逐字）**：

> **现有 Memory 系统的检索机制并不统一：MemPalace 与 Mem0 主要采用
> 相似度/全文检索，而 Graphiti 将 BFS 关系遍历直接纳入检索配方。
> 因此「Memory retrieval = pure similarity」不能作为跨系统观察成立。**

假设状态：`ANSWERED-DIVERGENT`（分系统分歧本身即 G0 发现）。

## 6. Real document compatibility

```text
[O] Office 四格式：MemPalace 有条件支持（extract 模式；Sheet 级
    溯源，Cell/Formula/列语义丢失，NaN 噪声入语料——RQ-1 运行时
    实测）；Mem0/Graphiti 零 Office 面
[O] 溯源粒度：docx 段落 / pptx Slide / pdf 页 / xlsx 仅 Sheet
    （MemPalace 实测）；「Markdown line 25 ≠ Sheet2!B17」
[O] CJK PDF = 未获有效观测（fixture 缺陷，OQ-A 两说不成立）
```

## 7. Reusable components（跨系统可复用面）

```text
[O] MemPalace：可插拔 backend 接口、sqlite_exact 单文件方案、
    path→locus 虚拟列索引、hybrid 检索管线、dedup/sync 维护件、
    源适配器契约（RFC 002）
[O] Mem0：LLM 事件式记忆生命周期 + history 账本、20+ 向量库
    factory、多作用域会话过滤
[O] Graphiti：bi-temporal 边模型、配方化组合检索框架、BFS 种子
    遍历、episode→边 provenance 链、prescribed+learned ontology
```

## 8. Missing capability against PALACE scenario（Gap，决定性节）

```text
Gap-A  Office 文件面：三者中仅 MemPalace 有条件覆盖，且 Cell/
       Formula/列语义在转换层丢失（RQ-1）；结构语义（Sheet/Cell/
       Formula/Position）对工作过程理解的必要性 = 未决（
       RQ-PALACE-01）
Gap-B  跨文档比较 / 综合 / 生成：三系统一致缺位（Agent 侧任务）
       ——E3/E4/E7 的组合验证空间
Gap-C  原件与派生信息的长期联系：provenance 粒度不一
       （drawer 级 / 未见 / episode 级）；「原始 artifact 粒度
       provenance 是否必要」= RQ-PALACE-02，未决
Gap-D  查询状态持久化 / continue / fork / restore：
       【OPEN——G0 未决空间，不回答】三系统检索形态均为
       query → retrieve → answer 一次性消费；「一次真实查询
       是否形成值得保存的执行状态」= 留待 G1 真实文件工作暴露
       工程事实后判定（若出现「昨天查到这里→今天从这里继续→
       分叉→可恢复」，则查询状态从题外话变为实验发现）
```

**G0 已知世界 vs PALACE 未验证空间**（human 边界图登记）：

```text
已知（G0 覆盖）        = 保存某种 Memory / 某种 Retrieval /
                        不同索引·图·蒸馏机制
未验证（PALACE 空间）  = 真实 Office 文件工作 / 跨文件比较·综合 /
                        原件与派生信息的长期联系 / 查询过程本身
                        是否值得成为持久状态
```

## 9. Research questions generated（收束台账）

```text
G0 实验链生成：RQ-1…6（MemPalace 静态）/ RQ-7（溯源深度，已答）/
  RQ-M0-1…4 / RQ-G1…4
RQ-PALACE-01 结构语义保持必要性   = 登记未决（G3 前置）
RQ-PALACE-02 原件粒度 provenance  = 登记未决（G3 前置）
RQ-PALACE-03 派生 Memory 是否足够 = 登记未决（G3 前置）
H-PALACE-G0-01                    = ANSWERED-DIVERGENT（收束，见 §5）
OQ-A CJK PDF 复测 / OQ-B 文件变更语义（v1→改 cell→v2→mine）/
  OQ-1 抽取确定性与模型依赖 = 遗留至 G1/E6
E6 参考观察（human 措辞登记）：Graphiti 已出现与 V1 identity/
  version/lineage 问题相邻的工程机制（bi-temporal）；该事实作为
  后续 E6 的参考观察登记，不构成 PALACE 抽象需求
```

## 10. 第一实验基座决策输入（事实陈列，非排名、非决策）

```text
路线 X  以 MemPalace 为第一后端
        依据：唯一有 Office 摄入面 + 唯一经运行时实测 + 文件方向
        同构；代价：xlsx 压平 + 结构语义缺口
路线 Y  以 Graphiti 为第一后端（或关系层）
        依据：唯一融合关系遍历 + bi-temporal 历史保留；代价：
        零文件面 + LLM 建图非确定性 + ingest 成本
路线 Z  MemPalace（文件层）+ Graphiti（关系/时间层）组合
        依据：方向正交互补；代价：两套存储/两套 LLM 依赖的组合
        复杂度未审计
路线 W  参考实现路线（取各系统机制作参考，另选 substrate）
        依据：机制已见清单（§7）；代价：放弃 Buy/Borrow 优先原则
决策归 human（G0 结论门第二层）。
```

## 11. Gate sequence

```text
本 AUDIT_RESULT → human 第二层判读（G0 关闭判定 + 基座决策 +
                G1 解锁裁定）
                → G1 Real Corpus（秦沈 500–3000 文件）设计草案
                → …（V2 gate 序列不变）
本文件不构成：PALACE 设计 / schema / 存储选型 / Gate① 复活
```
