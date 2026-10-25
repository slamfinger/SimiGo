# PALACE V2 方向登记 — Real-World Information Workspace / G0 Backend Survey

日期：2026-10-02  
状态：`DIRECTION REGISTERED / V2_ACTIVE / G0_AUDIT_NEXT`  
Registration authority：explicit human direction ruling（PALACE 新研究
方案 V2 全文，逐字要点登记；**取代**同日 RIW 方向登记——RIW 工件标记
SUPERSEDED 保留）  
性质：方向与 gate 结构登记——不设计 PALACE schema、不写 PALACE 代码
（G0 为纯审计）

## 1. 核心变化（human 原文）

> **PALACE 不再从「设计一个信息数据库」开始，而从「验证一个成熟
> 开源 Memory System 能否承载真实个人工作信息」开始。**

策略 = **Buy / Borrow before Build**：不在数据库、解析器、向量检索等
已有成熟开源实现的基础设施上花时间。第一候选 **MemPalace**（本地文件
+ Memory + Agent），Mem0（Agent Memory）、Graphiti（时间/关系型
Memory）及其他成熟系统作对照。立场不是「我们认为 MemPalace 很好」，
而是「把 MemPalace 当作实验基座，看它能不能解决真实问题」。

## 2. 研究场景（不是语义定义）

> **一个普通人的长期数字工作空间。**

电脑 / NAS：Word / Excel / PowerPoint / PDF / Markdown / 图片 / 项目
资料 / 历史报告 / 合同 / 技术资料 / 商务资料——多年积累，1,000 至
50,000+ 份。与 GitHub repository 完全不同（代码/版本/commit/branch
已有统一管理层；个人工作资料没有）——**这恰是 PALACE 值得研究的
地方。**

## 3. 正式实验链（V1 链冻结为）

```text
真实文件 → 文件发现 → 异构格式读取 → Memory ingestion
→ 原始信息保留 → 检索 → 多文件联合阅读 → 比较 → 综合
→ 生成新工作成果 → 来源追踪
```

PALACE 由此从「一个记忆数据库」变成**「一个信息工作的执行环境」**。

## 4. 四个研究 Gate（正式冻结）

```text
G0  Open-Source Memory Backend Survey
      → 应该采用什么现成基础设施？
G1  Real Corpus Ingestion
      → 几千份异构真实文件能不能进入统一工作空间？
G2  Cross-Document Work
      → 这个工作空间到底能不能帮助完成真实工作？
G3  Durable Information / Provenance
      → 长期使用以后，哪些信息关系必须持久化？
```

**只有 G2/G3 的工程证据，才有资格产生 PALACE 新抽象。**

## 5. G0 定义（当前 gate）

不写 PALACE 代码；只做开源项目**源码级工程审计**。审计问题清单
（MemPalace 优先）：

```text
如何 ingest Word / Excel / PPT / PDF？
如何保存原文？
文件路径是否进入记忆？
数据库结构是什么？
检索怎么做？
MCP 怎么接？
哪些部分可以直接复用？
哪些地方与我们真实工作场景不匹配？
```

产出 = Capability Matrix（15 项：本地文件导入 / Word / Excel / PPT /
PDF / 保留原文 / 文件路径 / 精确定位 / 全文搜索 / Semantic Search /
多文档比较 / Source Trace / MCP / 本地运行 / 可替换模型——各系统
逐项 ?）。不评「谁最好」，只回答：

> **哪个系统最适合成为 PALACE 的第一实验基座？**

G0 完成后决策：MemPalace 直接作为第一后端，或作为参考实现另选
Memory substrate。

## 6. G1+ 实验链预告（E0–E7，各 gate 开启时再冻结设计）

| # | 实验 | 核心问题 |
|---|---|---|
| G1 | Real-World Corpus-1 | 秦沈目录（项目管理/技术/商务/合同/成本/汇报），**500–3000 文件**起步，不用 synthetic benchmark，不整 NAS 导入 |
| E0 | Corpus Discovery | 系统能否正确理解目录（path/filename/extension/size/mtime）；**path 信息价值不预先规定**（同内容文件在不同路径工作意义不同——实验观察其作用） |
| E1 | Heterogeneous Reading | PDF/Word/Excel/PPT 同一问题能否统一使用（跨格式进入同一信息空间） |
| E2 | Cross-Document Retrieval | 返回文件集合且文件→内容→位置均可回溯 |
| E3 | Cross-Document Comparison | 信息之间关系第一次出现；**不提前定义 Relation，让工程任务逼出** |
| E4 | Synthesis | 旧资料→提取→比较→综合→新成果（比普通 RAG 更值得研究处） |
| E5 | Provenance / Source Trace | 结论→docx §3 / xlsx Sheet2!B17 / pdf p.27 / pptx Slide 8；做不到 ⇒ 登记 **Source Trace Failure**，不马上发明 Provenance Object |
| E6 | Update / Drift | 文件修改后再扫描：知道变了？旧信息可寻？新覆盖旧？历史关系？引用哪一版？——**此时才可能真正重新遇到 identity/version/lineage/snapshot；若真出现，回头激活 Lifecycle Storage 研究** |
| E7 | Real Work Loop | 端到端：实际任务→自找资料→跨文件读取→比较→判断→生成新文档→引用来源→人工检查 |

## 7. Build vs Adopt Gate（防「又一个数据库/知识图谱/embedding」）

```text
成熟开源项目已经解决？
        │ 是 → 采用
        │ 否
        ▼
实际工作中确实存在缺口？
        │ 是 → 研究这个缺口
        └ 否 → 不做
（而不是：我觉得 PALACE 需要 → 设计 → 实现）
```

## 8. SimiGo ↔ PALACE 关系（彻底分开）

```text
                 AI 工作系统
                      │
          ┌───────────┴───────────┐
          ▼                       ▼
    Execution State            Information
         │                       │
       SimiGo                  PALACE
         │                       │
   fork / restore         retrieve / compare
   continuation           synthesize / trace
   resource state          files / knowledge
          └───────────┬───────────┘
                      ▼
                    Agent
```

SimiGo 抽象已冻结 = 底层能力；PALACE 不再研究「Execution State 是
什么」。PALACE 新问题：

> **当 Agent 不再只是聊天，而是在一个人的多年信息空间里持续工作时，
> 需要什么信息能力？**

## 9. V1 处置（不变，重申）

PALACE V1 Lifecycle / Storage research = PARKED。再激活条件 = 真实
工程实验（尤其 E6）暴露「没有 durable identity / lineage / snapshot
就无法解决」。

## 10. 当前起点与停止条件

```text
第一步 = G0（MemPalace 源码级审计；源码级 ≠ 只看 README）
停止条件 = 不提前设计 PALACE schema；G2/G3 证据之前零抽象
```

## 11. Next gate

```text
本方向登记 → G0 审计协议草案（源码级审计设计：系统清单冻结 /
            Capability Matrix 维度冻结 / 审计问题清单冻结 /
            证据格式）→ human 审查 → 执行审计 → G0 结论门
```
