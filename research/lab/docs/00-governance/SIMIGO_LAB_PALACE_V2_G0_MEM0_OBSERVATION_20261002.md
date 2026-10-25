# PALACE V2 G0 中间观察 ③ — Mem0（源码级静态审计）

日期：2026-10-02  
状态：`INTERMEDIATE OBSERVATION #3 / MEM0 / STATIC SOURCE AUDIT`  
审计基线：github.com/mem0ai/mem0 @ `abb81c8`（Python SDK v2.2.1；
shallow clone，`.build/mempalace-src/mem0`）  
前置裁定登记（human 2026-10-02）：MemPalace Observation Set FROZEN
（不作 PALACE 设计结论）；RQ-PALACE-01/02/03 登记（G0 输出问题，
非设计）；OQ-B 场景钉定（v1.xlsx → 改 cell → v2.xlsx → mine，观察
并存/覆盖/历史/检索可区分性）；判读方向 = Observation → Comparison
→ Gap，禁止 Gap → PALACE schema  
范围声明：静态源码级；未运行（Mem0 核心写路径强制 LLM——运行时
实测需外部 LLM endpoint，待执行决策）

## 1. System overview

```text
[O] 定位     = 「The Memory Layer for Personalized AI」——Agent/
              对话记忆层；YC 公司；Python + TypeScript 双 SDK；
              Python SDK v2.2.1
[O] 输入模型 = add(messages)——**对话消息**（str 或 role/content
              列表），以 user_id / agent_id / run_id 之一为会话
              作用域；非文件、非目录
[O] 记忆形态 = LLM 提取的事实陈述（JSON {"id","memory","event"}），
              **改写提炼物，非原文**（infer=True 默认；infer=False
              时原样直存 raw memory）
[O] 方向归属 = 三方向中的「Agent → Memory」：把对话蒸馏成事实
              记忆，而非承载原始工件
```

## 2. Capability Matrix — Mem0 列（V2 场景口径）

| 分类 | 维度 | 判定 | 级别 |
|---|---|---|---|
| Ingestion | 文件发现 | **无**（OSS Python 核心零文件发现；docx/xlsx/pptx/pdf 全仓零命中） | O |
| Ingestion | 文件格式支持 | 不适用（输入 = messages 字符串；文件→文本转换完全在调用方） | O |
| Ingestion | 增量更新 | LLM 事件决策（ADD/UPDATE/DELETE）+ MD5 去重 | O |
| Ingestion | 删除/移动处理 | 不适用（无文件概念）；DELETE 为 LLM 决策的语义删除 | O |
| Content | 原文保存 | **无**——记忆 = 改写事实陈述；原消息另存（db.save_messages，session 域）但与记忆记录的关联未在 add 管线出现 | O/OQ |
| Content | 结构保留 | 无（无结构概念） | O |
| Content | chunk 策略 | 无 chunk（每条记忆 = 一条完整事实陈述） | O |
| Context | path 处理 | 无 | O |
| Context | metadata 处理 | 调用方 metadata + data/text_lemmatized/hash/created_at/updated_at/attributed_to | O |
| Context | provenance | **未见记忆→源消息链接**；attributed_to = 归属人；消息历史与记忆分储——溯源链 = Open Question | O/OQ |
| Retrieval | keyword search | BM25 字段（text_lemmatized） | O |
| Retrieval | semantic search | 主路径（vector similarity） | O |
| Retrieval | relation expansion | OSS Python core 无图模块（find 零命中；examples/graph-db-demo 仅为示例）——文档宣称的 graph memory 与 OSS core 缺位 = Open Question | O/OQ |
| Agent | MCP/API | Python/TS SDK + REST server + 集成目录 | O |
| Agent | model independence | provider 无关（LlmFactory 多 provider），**但 LLM 为核心写路径硬依赖** | O |
| Storage | backend 结构 | 20+ 向量库适配（chroma/qdrant/pgvector/faiss/redis/es…）+ SQLite 式 history 表（db.add_history 记录记忆变更） | O |

## 3. Architecture observation

```text
[O] 写管线（infer=True 默认）：messages → LLM 提取提示词
    （generate_additive_extraction_prompt，携带 existing_memories）
    → LLM 返回 JSON 记忆+事件 → 逐条 embed → MD5 去重（批内 +
    既有）→ 批量持久化；LLM 失败 = LLMError 硬失败（不静默）
[O] 记忆生命周期 = LLM 决策：同一次 add 中 LLM 对相关旧记忆给出
    UPDATE/DELETE 事件（add_history 记录变更轨迹）——「记忆演化
    由模型判断」而非文件事实驱动
[O] 初始化即 LLM：Memory.__init__ 中 LlmFactory.create——无 LLM
    配置则核心对象不可用（infer=False 直存路径亦需实例）
```

## 4. Storage observation（L0/L1/L2 框架）

```text
[O] L0（原始文件）= 不在系统内（无文件概念）
[O] L1（机械解析）= 不存在——无确定性转换层
[O] L2（AI 加工）  = 即记忆本体：LLM 提取陈述 + embedding +
    lemmatized + hash + 事件历史
[I] 推断：Mem0 = **Memory-native** 路线的代表——记忆本身就是
    事实存储；与 MemPalace 的 Artifact-centric（文件是事实、
    memory 是派生索引）构成方向两端。删库恢复问题对 Mem0 的
    形态完全不同：库删即记忆灭（原消息表除外）——无从 L0 重建
    的对应物，因为 L0 本来就不在系统边界内
[O] 记忆变更历史 = add_history 保留（旧值/新值/事件/时间）——
    这是对话记忆层的「演化账本」，但对象是改写陈述而非工件
```

## 5. Retrieval path observation

```text
[O] search = scope 过滤（user/agent/run）→ vector similarity
    （+ BM25 lemmatized 辅助）→ 记忆陈述列表
[O] 主路径形态 = 协议 §4 情况 1（相似度检索）；无拓扑扩展、
    无时间连续性融合（expiration_date 仅作可见性过滤）
[I] H-PALACE-G0-01 对照样本第二例：Mem0 主检索同样为相似度
    形态、无关系遍历——两个系统（MemPalace/Mem0）一致指向
    「检索 = 相似度；关系 = 可选旁路子系统」。假设保持
    UNVERIFIED（待 Graphiti——唯一以关系为核心方向的样本）
```

## 6. Real document compatibility（静态判读）

```text
[O] 无文件摄入面：PALACE V2 的四格式（docx/xlsx/pptx/pdf）在
    OSS 核心无任何处理代码——调用方须自行转成文本塞进 messages，
    且经 LLM 蒸馏后原文结构必失
[I] 推断：Mem0 在 PALACE 场景的合理角色不是文档记忆层，而是
    Agent 对话/决策记忆层（与文档层互补的组合位）——该组合假设
    留给 G0 结论门，不预判
```

## 7. Reusable components

```text
[O] 20+ 向量库适配层（factory 模式）
[O] LLM 事件式记忆生命周期（ADD/UPDATE/DELETE + history 账本）
[O] MD5 + 语义双通道去重
[O] 多作用域会话过滤（user/agent/run）
```

## 8. Missing capability against PALACE scenario

```text
[O] 零文件摄入 / 零原文保存 / 零结构概念 / 零 path·provenance 链
[O] 记忆 = LLM 改写物：工程事实的数值/坐标/公式在蒸馏中无任何
    结构性保护（与 MemPalace RQ-1 同类风险，但发生层级更早——
    提取即损失）
[O] 记忆演化 = LLM 语义判断（非文件事实驱动）——可复现性与
    审计性 = Open Question（同输入两次 add 是否产生同一记忆态）
```

## 9. Research questions generated

```text
RQ-M0-1  LLM 蒸馏对工程事实（数值/坐标/公式）的保真边界？（实测）
RQ-M0-2  记忆→源消息的 provenance 链是否存在于检索 payload？
RQ-M0-3  事件决策（UPDATE/DELETE）的确定性：同输入两次 add 的
         记忆态 diff？（Interaction Dependency 的极端样本）
RQ-M0-4  文档宣称的 graph memory 与 OSS core 缺位的落差（版本/
         hosted 分层核实）
```

---

**中间观察状态**：Mem0 静态审计完成。方向对照雏形（Observation 级）：
MemPalace = Artifact→Memory（verbatim 派生索引）；Mem0 =
Agent→Memory（LLM 蒸馏事实）——两端的记忆哲学差异本身就是 G0
Capability Matrix 之外的发现。下一步：Graphiti（Entity→Relation→
Memory，唯一关系核心方向样本）。
