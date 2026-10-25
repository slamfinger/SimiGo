# PALACE V2 G0 Open-Source Memory Backend Survey — Audit Protocol Draft

日期：2026-10-02  
状态：`DRAFT / FREEZE-PENDING-HUMAN（仅审计设计；无执行授权）`  
Gate：`PALACE_V2_G0_MEMORY_BACKEND_SURVEY（audit only）`  
授权来源：human 确认 + G0 审计纪律指令（2026-10-02）——G0 的作用 =
**防止 PALACE 进入真实工程前被某个现有 Memory 系统的概念模型绑架**；
方法同 Execution State 冻结过程（先观察，再抽象），观察对象从
runtime 换成 **Memory System 的实际工程行为**  
上游锚点：V2 Direction Registration（`0f20268`）  
性质：participant protocol draft——冻结审查通过并获执行授权后方审计

## 0. §0 并发核验（执行前须重跑）

```text
设计登记基线 commit = 0f20268（V2 direction）
执行前重跑 git fetch + 树净核验并记录
```

## 1. 目标（固定）

回答唯一问题：

> **现有开源 Memory System 在真实个人信息工作场景中已经解决了什么？
> 尚未解决什么？**

Non-goals（逐字冻结）：

```text
❌ 证明 MemPalace 正确
❌ 选择「最佳 Memory Database」（不做竞争排名）
❌ 复制 / fork 任何开源项目
❌ 开始设计 PALACE（schema / 对象模型 / 代码）
```

## 2. 审计对象（冻结）

### 2.1 Primary — MemPalace

入选理由（非预设优秀）：与 PALACE V2 场景最接近——

```text
本地文件 → 内容获取 → Memory → Agent 使用
```

重点观察：文件导入模型 / 原始信息保存方式 / 检索机制 / 上下文组织 /
来源追踪能力。

### 2.2 Comparison — Mem0 / Graphiti

| 系统 | 方向 | 重点 |
|---|---|---|
| Mem0 | **Agent → Memory** | memory extraction / memory update / user·session memory / vector·graph combination |
| Graphiti | **Entity → Relation → Memory** | entity / relation / temporal update / graph traversal |

三项目不是竞争排名，而是三个不同方向：

```text
MemPalace：文件 → Memory
Mem0：     Agent → Memory
Graphiti： Entity → Relation → Memory
```

## 3. Capability Matrix（冻结，6 类 17 维）

| 分类 | 维度 |
|---|---|
| **Ingestion** | 文件发现 / 文件格式支持 / 增量更新 / 删除·移动处理 |
| **Content** | 原文保存 / 结构保留 / chunk 策略 |
| **Context** | path 处理 / metadata 处理 / provenance |
| **Retrieval** | keyword search / semantic search / relation expansion |
| **Agent** | MCP·API / model independence |
| **Storage** | backend 结构 |

矩阵判读纪律（human 裁定）：

> **不问「有没有 schema」。问：系统为了完成工作，实际上保存了哪些
> 事实？**

schema 是后来的抽象；本审计记录保存事实本身。

## 4. Memory Path Analysis（新增核心章节）

对每个系统记录一次查询的**实际路径**：

```text
Query → Search Entry → Retrieved Object → Related Object → Final Context
```

三种典型形态（仅记录事实，不评判）：

```text
情况 1  query → embedding similarity → top-k chunks
        ⇒ 纯相似度检索
情况 2  query → document → entity → relation → document → context
        ⇒ 存在拓扑扩展
情况 3  query → previous memory → current state → new memory
        ⇒ 存在时间连续性
```

登记意义：Memory Path 可能成为未来「PALACE Information Topology」的
来源——**但现在只记录事实**（相关假设进 §8 Research Hypothesis
Register，不升级）。

## 5. Database Inspection

不看「用了 SQLite / Chroma / Qdrant」这个层面；看**实际保存什么**：

```text
Database
├── original content?
├── extracted content?
├── embeddings?
├── metadata?
├── source?
├── timestamps?
├── relations?
└── history?
```

核心问题（对应 human 的 L0/L1/L2 信息分层思路；精确分层定义在执行
启动时钉定，本协议不预设）：

> **如果数据库删除，只剩原始文件，能否恢复？**

该问题区分「可从原件重建的衍生层」与「真正被添加的记忆」——
是 G0 与 V1 Lifecycle Storage 未来对话的天然接口。

## 6. Real File Compatibility（强制实测，demo 不算）

多数 Memory 项目展示 txt / markdown / code / web page；本场景是
docx / xlsx / pptx / pdf。执行时至少实测：

```text
Word / Excel / PowerPoint / PDF
``+

**Excel 是关键差异**：它不是文本——包含

```text
Sheet / Cell / Formula / Table / Position
```

若系统把 Excel 压成纯文本流（`A1 项目名称 / B1 秦沈高速 / …`），
重要信息可能已经丢失——该丢失须作为 observation 登记。

## 7. Evidence Grade（继承 SimiGo 纪律）

| 级别 | 定义 | 例 |
|---|---|---|
| **Observation** | 直接看到 | 「MemPalace 使用 SQLite 保存 metadata」 |
| **Inference** | 据观察推断 | 「当前实现可能支持增量更新」 |
| **Open Question** | 尚未验证 | 「path 是否参与 retrieval ranking」 |

禁止：

```text
Observation → 直接升级 → 「PALACE 必须采用 XXX」
```

## 8. Research Hypothesis Register（登记机制 + 首条）

审计中新假设一律入 Register（编号 H-PALACE-G0-nn），状态
UNVERIFIED，附验证方式，**不提前升级**。

首条（human 指定）：

```text
H-PALACE-G0-01
内容     = Memory retrieval may involve traversal over
          information relations rather than pure similarity matching.
状态     = UNVERIFIED
验证方式 = 源码分析 + 查询路径观察（§4 Memory Path Analysis）
```

## 9. 输出工件规格（G0 结论 = 本文批准后的执行产物）

`SIMIGO_LAB_PALACE_V2_G0_MEMORY_BACKEND_AUDIT_RESULT.md`，九节：

```text
1. System overview
2. Capability Matrix
3. Architecture observation
4. Storage observation
5. Retrieval path observation
6. Real document compatibility
7. Reusable components
8. Missing capability against PALACE scenario   ← 最重要
9. Research questions generated                 ← 最重要
```

第 8/9 节决定 PALACE 后面有没有必要研究、研究什么。
输出不是代码、不是 PALACE 设计。

## 10. 审计执行边界

```text
✅ 源码级阅读（clone 公开仓库；结论附源文件路径/commit 引用）
✅ 本地运行实测（§6 四格式 fixture；记录环境与版本）
✅ R0 式证据习惯：观察逐条可溯源（文件/行/运行输出）
❌ 写 PALACE 代码
❌ schema / 对象模型设计
❌ 向任何系统贡献代码或配置真实个人数据
❌ 竞争排名结论
```

G1/G2/G3 = LOCKED（本协议不触碰）。

## 11. Gate Sequence

```text
本协议草案 → human 冻结审查（一次）
           → 执行授权（独立状态转换）
           → 审计执行（MemPalace → Mem0 → Graphiti；逐系统
              交付中间观察，防最后一锅端）
           → G0 结论门（AUDIT_RESULT 九节）→ human 第二层判读
           → 决策：第一实验基座（直接采用 vs 参考实现 + 另选
              substrate）→ G1 解锁申请
```

当前无审计执行授权。
