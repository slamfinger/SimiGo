# PALACE V2 G0 中间观察 ① — MemPalace（源码级静态审计）

日期：2026-10-02  
状态：`INTERMEDIATE OBSERVATION #1 / MEMPALACE / STATIC SOURCE AUDIT`  
**FROZEN（human 2026-10-02：MemPalace Observation Set 冻结——不作 PALACE 设计结论）**  
协议：`SIMIGO_LAB_PALACE_V2_G0_MEMORY_BACKEND_AUDIT_PROTOCOL_20261002.md`
（FROZEN / APPROVED，human 2026-10-02）  
审计基线：github.com/MemPalace/mempalace @ `develop` `5ea40d3`
（shallow clone，本地 `.build/mempalace-src/`，不入 Lab git）  
版本：v3.10.0 / MIT / Python 3.9+（另有 Rust crates 并行实现，本轮
以 Python 包为准）  
范围声明：本篇 = 静态源码级审计；§6 真实格式运行时实测 =
下一份中间观察。证据级别逐条标注（Observation / Inference /
Open Question）。

## 1. System overview

```text
[O] 定位     = Local-first AI memory：对话与文件内容 verbatim 存储
              （不摘要、不改写），语义检索取回
[O] 结构隐喻 = wings（人/项目）→ rooms（主题）→ drawers（原文块）
              ——检索可按 wing/room 范围化，非平铺语料
[O] 后端     = 可插拔检索层：默认 ChromaDB；自带 sqlite_exact
              （含 FTS5 + BM25）、pgvector / qdrant / milvus /
              rust_exact；接口 = mempalace/backends/base.py
[O] 接口面   = CLI（mine/search/sweep/dedup/sync/init…）+ MCP
              server（README 称 45 工具；工具数运行时核验 =
              Open Question）
[O] 知识图谱 = 时间性 entity-relation 图（SQLite：entities/triples，
              triples 带 valid_from/valid_to 有效期窗口 + confidence
              + source_closet/source_file/source_drawer_id 溯源列）
[O] 本地优先 = 核心 API-free；embedding 本地 ONNX（minilm ~80MB /
              embeddinggemma-300m ~300MB）或可选 OpenAI-compatible
              endpoint（切换需 rebuild-index，向量空间不同）
```

**Interaction Dependency 标签**（human 补充观察项）：

```text
[O] embedding        = 本地模型或可配置 endpoint——核心检索路径
                       模型可替换（换模型须重建索引）
[O] closet LLM 增强  = OPTIONAL / opt-in（正则 closet 默认由
                       miner 生成；LLM 仅重生成更丰富 closet，
                       Bring-your-own OpenAI-compatible endpoint）
[O] KG 抽取          = triples 带 adapter_name 溯源列；抽取是否
                       依赖特定 LLM = Open Question（待执行链核验）
[I] 推断             = 核心记忆操作 design-level 模型无关；
                       质量层（closet 丰富度、KG 抽取召回）存在
                       模型依赖
```

## 2. Capability Matrix — MemPalace 列

| 分类 | 维度 | 判定 | 级别 |
|---|---|---|---|
| Ingestion | 文件发现 | **有，分模式**：默认 mine 仅文本/代码扩展名（READABLE_EXTENSIONS：txt/md/全主流代码/csv/tex/json/yaml/html…，**不含 Office**）；Office 走独立 `mine --mode extract` | O |
| Ingestion | 文件格式支持 | 文本/代码（默认）+ pdf/docx/pptx/xlsx/epub（MarkItDown）+ rtf（striprtf）——extract 模式 | O |
| Ingestion | 原文保存 | **原始文件不动**（read-time conversion，字节不入库）；库内保存 = 转换后 Markdown 的 verbatim chunk | O |
| Ingestion | 增量更新 | 重 mine + dedup（同 source_file 近重复 drawer 余弦距离阈值清理，保留最长）；**变更内容新旧版本共存语义 = Open Question** | O/OQ |
| Ingestion | 删除/移动处理 | sync.py：gitignore-aware prune——源文件删除/移出/gitignore 后清除对应 drawer | O |
| Content | 原文保存 | drawer = verbatim 转换文本（ Philosophy：不摘要不改写） | O |
| Content | 结构保留 | Office → MarkItDown → **Markdown 表格文本**：Sheet/Cell 坐标/Formula 保留情况 = Open Question（协议 §6 预警的压平风险点） | O/OQ |
| Content | chunk 策略 | CHUNK_SIZE=800 / CHUNK_OVERLAP / MIN_CHUNK_SIZE 可配置 | O |
| Context | path 处理 | source_file 逐 drawer 记录 + SQLite 表达式索引；wing/room/hall 为 metadata 虚拟生成列（locus 索引，1.6GB 级不重写 embedding）——**path 进入记忆并参与范围过滤** | O |
| Context | metadata 处理 | DrawerRecord.metadata 扁平标量约束（RFC 001/002）；嵌套数据入 KG 或 json_string 字段 | O |
| Context | provenance | drawer 级 source_file + chunk_index；KG triple 级 source_drawer_id + source_file + adapter_name | O |
| Retrieval | keyword search | FTS5/BM25（sqlite_exact + chroma 路径均有） | O |
| Retrieval | semantic search | 默认路径（Chroma / sqlite_exact embedding） | O |
| Retrieval | relation expansion | 主检索路径**无** KG 融合（searcher 零引用 knowledge_graph）；KG 为独立 MCP 工具族查询 | O |
| Agent | MCP/API | MCP stdio/http server + CLI + Python API；README 称 45 工具 | O/OQ |
| Agent | model independence | 见 §1 Interaction Dependency | O/I |
| Storage | backend 结构 | 双存储族：向量库（可插拔）+ SQLite KG + closets（正则事实抽取集合） | O |

## 3. Architecture observation

```text
[O] miner-per-content-type：miner.py（项目文本/代码）/
    convo_miner.py（对话导出）/ format_miner.py（Office 二进制，
    --mode extract）——三条摄入管线汇入同一 drawer 管线
[O] 写路径：读时转换 → chunk(800) → drawers（向量库）+
    closets（正则事实，rank 信号）→（可选）KG triples
[O] 读路径：见 §5
[O] 源适配器契约：RFC 002 BaseSourceAdapter（SourceRef local_path/
    uri；DrawerRecord content+source_file+chunk_index+扁平 metadata）——
    第三方源（git/Slack/Cursor…）插件面已定义
[O] 工程成熟度信号：RFC 目录（5 份）/ AGENTS.md / CI windows 专项 /
    benchmark 复现脚本 / 溯源列迁移兼容逻辑
```

## 4. Storage observation（对应协议 §5 + L0/L1/L2 框架）

```text
[O] KG schema：entities(id,name,type,properties) + triples(subject,
    predicate,object,valid_from,valid_to,confidence,source_closet,
    source_file,source_drawer_id,adapter_name)——时间有效期 + 溯源
    在 schema 层存在
[O] 向量库 schema（sqlite_exact 为例）：documents(collection_id,id,
    document,metadata_json,embedding BLOB,dim,created_at,updated_at)
    + docs_fts(FTS5) + wing/room/hall VIRTUAL 生成列 + source_file
    表达式索引
[O] 实际保存的事实（协议 §3 判读纪律）= 转换后文本 chunk + embedding
    + 扁平 metadata（wing/room/source_file 等）+ 正则 closet + 
    KG 三元组；原始二进制不在库内
[O] L0/L1/L2 映射：L0 原始文件 = 用户磁盘上不动（零触碰）；
    L1 机械解析 = MarkItDown/striprtf Markdown（内存中转换）；
    L2 AI 加工 = chunk/embedding/closet/KG triples。
    ⚠️ 命名冲突观察：MemPalace 自带 layers.py = 上下文加载预算
    分层（L0 Identity/L1 Essential/L2 On-Demand/L3 Deep Search），
    与 human 的信息分层框架同名异义——后续行文须加前缀区分
```

**删库恢复问题**（协议 §5 核心问）：

```text
[I] 推断：删除 palace 库后，L1 层可由 L0 确定性重建（MarkItDown
    重跑）；L2 中 embedding/chunk 可重建，但 closet 正则抽取与
    KG triples 的抽取结果是否逐次一致 = Open Question（LLM 参与
    部分 + 实体检测启发式的确定性未验证）
```

## 5. Retrieval path observation（对应协议 §4 + H-PALACE-G0-01）

```text
[O] 主检索路径 = Hybrid：BM25 keyword（FTS5）+ vector semantic
    similarity；「drawer query is the floor — always runs」+
    closet 命中作 rank 提升（信号非闸门）+ date_window 时间窗过滤
    （filed_at 内容日期）+ wing/room metadata 范围过滤
[O] 判读：主路径形态 = 协议 §4 情况 1 的强化版
    （相似度 + 关键词双通道 + 元数据范围化），无拓扑扩展、
    无时间连续性融合
[O] KG 拓扑遍历 = 独立 MCP 工具族（tools_kg），不进入主检索——
    「信息拓扑」能力存在但与检索解耦
[I] H-PALACE-G0-01 首份证据：MemPalace 的检索 = hybrid 相似度
    + 关键词；关系遍历作为独立子系统存在而非检索路径组成。
    假设保持 UNVERIFIED（Mem0/Graphiti 待审计对照）
```

## 6. Real document compatibility（静态判读；运行时实测 = 下一份中间观察）

```text
[O] Office 支持 = 存在但为独立模式（--mode extract），默认 mine 不含
[O] 转换器 = MarkItDown（pdf/docx/pptx/xlsx/epub → Markdown 表格/
    标题文本）——协议 §6 预警的压平风险点在此：xlsx → Markdown 表
    后 Sheet 结构部分保留为表头、Cell 坐标/Formula 大概率丢失
    （MarkItDown 转换语义 = Open Question，须 fixture 实测）
[O] 已知边界（源码自述）：扫描版 PDF 无 OCR = skip、DRM = skip、
    加密 PDF = skip、iCloud 云端占位 = skip
[O] 13 类 fringe case 有显式 SKIP 语义（不崩溃、可报告）
```

## 7. Reusable components（对 PALACE 的可复用面）

```text
[O] 可插拔 backend 接口 + sqlite_exact（FTS5+embedding 单文件方案）
[O] source adapter 契约（RFC 002）与 conformance 套件思路
[O] hybrid 检索管线（BM25+vector+metadata 范围+时间窗）
[O] path→locus 虚拟列索引方案（不重写向量的大库迁移技巧）
[O] temporal KG schema（validity window + 溯源列）
[O] dedup / sync-prune 生命周期维护件
```

## 8. Missing capability against PALACE scenario（决定性节之一）

```text
[O] Office 非默认摄入路径（须显式 --mode extract）
[O] xlsx 结构语义（Sheet/Cell/Formula/Position）在 MarkItDown 转换层
    大概率压平——E1/E5 的精确溯源（Sheet2!B17 级）当前无证据支持
[O] 跨文档比较 / 综合 / 新成果生成 = 不在系统内（Agent 侧任务，
    经 MCP 取上下文）——PALACE V2 的 E3/E4/E7 正是测试 Agent +
    MemPalace 组合
[O] 文件内容 drift 的版本语义（旧值可寻？引用哪一版？）无显式机制
    （E6 预演：dedup 只清近重复，变更语义 = Open Question）
[O] 主检索无 relation traversal（KG 与检索解耦——是否算「缺口」
    留给 G0 结论门，不预判）
```

## 9. Research questions generated（决定性节之二）

```text
RQ-1  MarkItDown xlsx 转换的 Sheet/Cell/Formula 保留边界？（实测）
RQ-2  重 mine 后变更文件的新旧 drawer 共存/覆盖语义？——E6 直接前置
RQ-3  closet/KG 抽取的确定性：同输入两次 mine 产物是否逐字一致？
      （决定删库恢复的可重建性边界）
RQ-4  KG 独立查询 + hybrid 主检索的组合使用形态能否构成
      「拓扑扩展检索」？（对照 Graphiti 后回答）
RQ-5  500–3000 文件 × 秦沈层级在 wings/rooms 结构中的组织成本？
      （wing/room 判定 = 启发式 room_detector_local + entity_detector，
      中文项目资料的表现 = Open Question）
RQ-6  Interaction Dependency：KG 抽取 adapter 的模型依赖边界？
```

---

**中间观察状态**：静态源码级审计完成；运行时实测（§6 四格式 fixture +
RQ-1/RQ-3）为下一份中间观察。Mem0 / Graphiti 依序后续，不并评。
