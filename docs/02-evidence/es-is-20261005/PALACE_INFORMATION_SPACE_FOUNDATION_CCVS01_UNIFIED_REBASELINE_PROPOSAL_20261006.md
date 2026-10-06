# CCVS-01 Unified File + Session Information Carrier Rebaseline Proposal

> **Status:** ARCHIVED VERBATIM / ACCEPTED AS DIRECTION BY HUMAN RULING
> **Archive date:** 2026-10-06
> **Provenance:** Proposal text supplied by Human in-session (pasted verbatim,
> preserved byte-for-byte below the archive header). Human instruction
> `按这个设计方向执行。` accepted the proposal's decision point
> (§ "当前建议的 Human decision point") as the CCVS-01 Unified direction.
> The binding registration of that ruling lives in
> `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_UNIFIED_DIRECTION_RULING_20261006.md`.
>
> **Reading rule:** this document is the archived design basis, not a frozen
> protocol. Where the proposal commits to design content (workloads,
> structures, bounds, topologies), that content becomes binding only through
> the U-1 Unified Addendum Protocol after its own Human review ruling.
> Frozen protocol `CCVS-01-PB v1.2` is NOT modified by this proposal or by
> the direction ruling.

---

## Verbatim proposal (Human-supplied, unmodified)

对。基于现在已经完成的 Baseline A + P8，以及 10 月 2 日 MemPalace / G1 / G2 / G3 的实证链，我建议把 CCVS-01 重新整理成一个**统一 File + Session Information Space Carrier** 的验证路线。

关键不是推翻已有实验，而是把已有结果重新放回正确位置：

```text
旧 Baseline A
    = File Information carrier baseline
          ↓
已有 MemPalace / G1-G3
    = Session Information semantics / workload evidence
          ↓
新的统一目标
    = File Information + Session Information
      在同一个 Information Space carrier 中作为一级 workload
```

现有 PB v1.2 不应直接修改；下面应作为一个**新增的 Unified Information Space Addendum / rebaseline proposal**，经 Human ruling 后才进入实现或追加实验。

# CCVS-01 Unified File + Session Information Carrier Rebaseline Proposal

**状态：PROPOSED / HUMAN REVIEW REQUIRED**
**当前阶段：Baseline A + P8 已完成；Candidate B/C/D 尚未启动**
**性质：架构与验证重规划，不修改既有 Frozen PB v1.2，不授权实现**

---

## 1. 重新定义研究对象

CCVS-01 原来的实际重心偏向：

```text
File Information
    ↓
Registry / Locator / Representation / Search
```

现在根据已有 MemPalace 与真实工作实验，应正式改为：

```text
                    Information Space Carrier

             ┌──────────────┴──────────────┐
             │                             │
      File Information              Session Information
             │                             │
   representation/file             conversation/work stream
   revision/locator                event/order
   availability                    findings/judgments
   provenance                      exclusions/negative knowledge
             │                     open questions/next action
             │                             │
             └──────────────┬──────────────┘
                            │
                 unified Identity / Relation /
                 Provenance / Search / History
```

因此：

> **File Information 和 Session Information 是同等级的第一类 carrier workload。**

Session 不是 File 的附属 metadata，也不是 Information Space 上面的“Memory application”。

---

# 2. 已有证据如何直接进入新设计

已有研究已经提供了 Session Information 的实证依据，不再重新定义。

### G0 / MemPalace

已观察：

```text
verbatim content
source/provenance
chunk/event information
BM25 / FTS
semantic search
time filtering
scope filtering
temporal KG
session/conversation mining
```

同时也暴露了几个必须继承到新设计的问题：

```text
XLSX 压平
数字检索噪声
Session / source-file 排序冲突
derived index 污染
wake-up context 污染
```

来源：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_G0_MEMPALACE_OBSERVATION_20261002.md`

`docs/00-governance/SIMIGO_LAB_PALACE_V2_G0_MEMPALACE_RUNTIME_OBSERVATION_20261002.md`

### Real Carrier

真实 MemPalace 载入已经证明：

```text
工作会话
+
真实文件
```

可以同时进入同一空间。

而且：

```text
工作前沿 / 判断依据 / 历史记录
```

具有非常好的检索价值；相反，文件侧存在排序和结构保真问题。

来源：

`docs/00-governance/SIMIGO_LAB_PALACE_REAL_CARRIER_MEMPALACE_V0_INIT_20261002.md`

### G1

证明：

```text
发现 A
   ↓
改变后续探索路径
```

所以 Session Information 不是简单 transcript，而是：

> **information work 的过程状态。**

来源：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_G1_MAIN_PROBE_20261002.md`

### G2

进一步证明：

```text
T-1/T-2 的发现
        ↓
T-3 直接复用
        ↓
零新增读取也能继续工作
```

因此真正有价值的 Session Information 包括：

```text
已经发现什么
比较过什么
哪些数字可能对应
哪些不能对应
哪里冲突
下一步为什么继续查
```

来源：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_G2_EXECUTION_20261002.md`

### G3

已经直接实测：

```text
R1 当前工作位置
R2 已有发现
R3 已排除项
R4 未闭合问题
R5 下一步
```

而 G3-1 又证明：

```text
excluded
≠
safe historical state
```

因为未来新证据可能推翻过去的排除判断，所以还需要：

```text
reason
basis
historical judgment
```

G3-2 则证明：

```text
继续工作
≠
重新审查过去判断
```

两者是两个不同能力。

因此：

```text
Raw
+
Work findings
+
Judgments
+
Negative knowledge
+
Open questions
+
Next action
+
Evidence / provenance
```

都应进入 Session Information workload。

来源：

`docs/00-governance/SIMIGO_LAB_PALACE_V2_G3_RESULT_20261002.md`

`docs/00-governance/SIMIGO_LAB_PALACE_V2_RQG3_1_RESULT_GATE_20261002.md`

`docs/00-governance/SIMIGO_LAB_PALACE_V2_RQG3_2_RESULT_20261002.md`

---

# 3. 新的目标架构：Unified Local Information Space

我建议把第一目标架构定为：

```text
UIS-01
Unified Local Information Space
```

它不是“一个数据库包办一切”，而是一个**最小统一 topology**。

```text
                         SimiGo
                           │
                 semantic data structure
                           │
                ┌──────────▼──────────┐
                │ Information Space   │
                │ semantic boundary   │
                └──────────┬──────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
     Registry           Relation          Session
     + Identity         + History          Stream
        │                  │                  │
        ├──────────┬───────┴──────────┬───────┤
        │          │                  │
     Locator   Provenance         Availability
        │
   Representation
        │
   ┌────┴─────────┐
   │              │
File payload    Session payload
POSIX/object    raw event/text
```

然后统一进入：

```text
        Derived Search Space
          ├── exact / structured
          ├── lexical / FTS
          └── semantic / vector
```

这里最重要的是：

> **Search 是 derived layer，不能成为 authoritative Information source。**

---

# 4. 一级 carrier 不等于物理存储必须相同

这是这次设计最重要的边界。

File 和 Session 是同等级 workload：

```text
File Information
Session Information
       ↑
   same semantic
   Information Space
```

但物理承载可以不同。

### File

```text
Information
   ↓
Representation
   ↓
content-addressed POSIX object
   ↓
Locator
```

### Session

```text
Information
   ↓
Session
   ↓
immutable event sequence
   ↓
raw payload
```

Session 不应该被强迫模拟成：

```text
一个超大的文件
```

同样，File 也不应该因为统一 Information 而被强制塞进 session-event 模型。

统一的是：

```text
Identity
Relation
Provenance
History
Availability
Search
Recovery
```

不是物理字节布局。

---

# 5. 预定型数据结构

这里可以先形成 logical schema，不锁定具体 SQL DDL。

## 5.1 Universal Information

所有 File / Session 信息最终都进入：

```text
Information
    InformationID
    kind
    provenance
    availability
```

其中：

```text
kind = file / session / event / result / derived ...
```

`kind` 是 SimiGo semantic vocabulary；carrier 只保存，不自行解释。

---

## 5.2 Representation

```text
Representation
    RepresentationID
    InformationID
    revision
    representation_kind
    content_reference
    digest
    size
    created_at
```

它继续严格保持：

```text
Information Identity
≠ Representation Identity
≠ Locator
```

这部分直接继承当前 InformationCore / Core Identity audit 的结果。

---

## 5.3 Locator

```text
Locator
    InformationID
    RepresentationID
    physical_locator
    locator_state
    observed_at
```

因此：

```text
MOVE
```

仍然只是：

```text
locator change
```

而不是 Information 改变。

---

## 5.4 Session

Session 是一级 Information workload，而不是 Information 的附属字段：

```text
Session
    SessionID
    root_information
    started_at
    ended_at
    source
    status
```

---

## 5.5 SessionEvent

这是新的关键结构：

```text
SessionEvent
    SessionID
    sequence
    EventID
    payload_reference
    occurred_at
    producer
    provenance
```

核心 invariant：

```text
(SessionID, sequence)
```

必须稳定。

因此：

```text
append #1
append #2
append #3
```

不能因为 summary/reindex/restart 而改变顺序。

---

# 6. Session Information 不只保存聊天原文

根据 G1/G2/G3，建议定义一个 carrier-neutral 的：

```text
Session Information Record
```

它可以承载：

```text
RAW
DISCOVERY
JUDGMENT
EXCLUSION
UNCERTAINTY
OPEN_QUESTION
NEXT_ACTION
EVIDENCE_LINK
RESULT
```

但这里有一个重要边界：

> 这些类型是 SimiGo 的语义结构，carrier 不负责判断一条记录到底是不是“判断”或者“排除”。

carrier 只负责：

```text
保存
定位
检索
关联
恢复
```

SimiGo 负责：

```text
interpret
classify
judge
continue
```

---

# 7. File ↔ Session 必须是一等关系

这是新设计中我认为最重要的新增能力。

例如：

```text
File Information F123
        │
        ├── discussed-in → Session S77
        ├── cited-by → Session S78
        ├── produced-from → Session S80
        ├── decision-source → Session S81
        └── revised-after → Session S85
```

反向也成立：

```text
Session S81
   │
   ├── used File F123
   ├── produced File F124
   ├── questioned File F125
   └── continues Session S76
```

carrier 不理解这些关系的语义，只保证：

```text
typed relation
+
stable endpoint
+
history
```

这与 A4 reduction / InformationCore RelationCore 的研究方向一致。

---

# 8. Search 要重新设计：不能只有 FTS，也不能只有向量

MemPalace 的真实实验已经告诉我们：

```text
semantic search 很有用
```

但是也告诉我们：

```text
semantic retrieval
≠
complete Information retrieval
```

尤其：

```text
313,356
2,881.34
4200
```

这类精确数字，可能被向量/噪声结果淹没。

因此新的 derived search 至少分三层：

```text
L1 Exact / Structured
    exact number
    exact identifier
    source coordinate
    session sequence

L2 Lexical
    BM25 / FTS
    phrase
    token
    filename
    transcript

L3 Semantic
    embedding
    conceptual similarity
```

最终：

```text
Query
 ├── exact
 ├── lexical
 └── semantic
        ↓
candidate set
        ↓
metadata / provenance / scope filtering
        ↓
SimiGo semantic ranking
```

不要让 embedding search 单独成为“Information Space search”。

---

# 9. File Search 的来源粒度也必须升级

MemPalace 的 Excel 实验已经实际暴露：

```text
Sheet 保留
Cell 坐标丢失
Formula 丢失
```

所以新的 File Representation 应该允许：

```text
PDF
    page

PPTX
    slide

DOCX
    paragraph / section

XLSX
    sheet / range / cell / formula
```

注意：

**不一定要把这些全部写成 carrier schema。**

可以是：

```text
RepresentationLocator
```

的结构化 provenance。

例如：

```text
source = file:/...
locator =
    xlsx://workbook/sheet=材料量价/range=B17:E17
```

这样 search 返回的就不是：

```text
“钢筋 4200”
```

而是：

```text
InformationID
RepresentationID
source file
Sheet
range
revision
```

这正好修复 MemPalace 实验暴露的 provenance 深度不足问题。

---

# 10. Session Search 也必须具有 provenance 深度

对应地：

```text
Session search result
```

至少应能返回：

```text
SessionID
EventID
sequence
raw source
record kind
related InformationID
```

而不是只有：

```text
similarity score
snippet
```

否则 G3 的：

```text
“为什么当时这么判断？”
```

无法重新审查。

---

# 11. Raw / Derived 的边界重新确定

这里应该直接吸收 MemPalace 和 P8 两边的经验。

### File

```text
原始文件
    = authoritative representation

extracted text
    = derived

FTS
    = derived

embedding
    = derived

summary
    = derived
```

### Session

```text
raw session event
    = authoritative

event normalization
    = derived

summary
    = derived

embedding
    = derived

KG
    = derived
```

因此：

```text
删除 FTS
→ 可以 rebuild

删除 vector index
→ 可以 rebuild

删除 summary
→ 可以 rebuild

删除 raw session event
→ Information loss

删除 original file representation
→ Representation loss
```

---

# 12. 特别修正当前 A1 的 F7 经验

当前 P8：

```text
F7 = REPAIR
```

并且已经诚实记录：

> 当前 FTS 的 authority 能恢复 identity coverage，但不能完全恢复原始 searchable text。

这对新的统一方案是一个必须修掉的设计点。

新要求：

```text
DerivedSearchIndex
        ↓
必须能够从 authoritative representation
        ↓
deterministically rebuild
```

因此需要一个：

```text
IndexSource
```

概念：

```text
IndexSource
    source_information
    source_representation
    extraction_version
    extraction_reference
```

它可以指向：

```text
原始 File
```

或：

```text
Raw Session Event
```

这样：

```text
drop FTS
    ↓
read authoritative content
    ↓
re-extract
    ↓
rebuild
    ↓
compare
```

才真正成立。

---

# 13. Session workload 应该正式进入 CCVS-01

我建议新增三个 workload 家族。

## S 家族：Session-only

```text
S1 high-frequency append
S2 ordered timeline read
S3 session exact search
S4 session lexical search
S5 session semantic search
S6 historical session retrieval
S7 session index rebuild
S8 session crash/recovery
```

## F 家族：保持现有 File workload

现有：

```text
small object
large file
locator
revision
relation
search
rebuild
crash
```

继续有效，不重做。

## X 家族：Unified Information workload

真正关键。

```text
X1 File → Session retrieval
X2 Session → File retrieval
X3 Cross-session → file history
X4 File revision → session judgment history
X5 File + Session mixed research day
X6 interruption → restart → continue
X7 derived index rebuild across both domains
X8 historical judgment re-audit
```

---

# 14. X5 应成为新的 Binding Workload 候选

我尤其建议把现在的：

```text
WL6 mixed research day
```

重新扩展成：

```text
WL6-U
Unified Research Day
```

示例：

```text
1. 导入新文件
2. 产生 Session
3. 讨论文件内容
4. 发现一个问题
5. 形成判断
6. 排除某个文件
7. 继续查另一个文件
8. 修改原文件
9. Session 再引用新 revision
10. 形成结论
11. 中断
12. restart
13. 继续
14. 查询：
       “为什么当时这么判断？”
15. 查询：
       “这个判断用了哪些文件？”
16. 查询：
       “后来有没有证据推翻它？”
```

这一个 workload 同时覆盖：

```text
File
Session
Relation
Revision
Provenance
Negative knowledge
Search
History
Continuation
Recovery
```

它比单纯 benchmark 一个 SQLite 表的研究价值高得多。

---

# 15. 真实性 workload 直接复用已有两个来源

不用再造一套虚假 corpus。

### File workload

直接复用：

```text
秦沈项目真实文件
+
archive-organizer
```

archive-organizer 可以提供：

```text
scan
change detection
semantic classification
move
rename
remap
journal
incremental organization
```

于是它成为真实 File Information producer。

### Session workload

直接复用：

```text
G1/G2/G3
+
MemPalace Real Carrier
```

这已经包含：

```text
real session
real decisions
real negative knowledge
real pending work
real file references
```

于是：

```text
File workload
+
Session workload
```

都有真实来源。

---

# 16. 候选架构现在应该改成这样

不要直接把 B 定义成“某个数据库”。

### U-A：Unified Minimal

```text
SQLite
  ├── Information Registry
  ├── Session Event Store
  ├── Relation/History
  ├── Locator
  ├── Availability
  └── FTS5

POSIX Entity Store
  ├── large files
  └── large session payloads

Derived Semantic Index
  └── pluggable
```

这是我建议**首先验证**的目标。

原因：

```text
最少组件
+
File / Session 同一 authority
+
最低 seam
```

---

### U-B：Unified Core + MemPalace-derived Retrieval

```text
InformationCore
       │
       ├── File
       ├── Session
       ├── Relation
       └── History
             │
             ▼
        MemPalace
       derived retrieval
```

MemPalace 不再作为 authoritative carrier。

它只承担：

```text
semantic retrieval
session-oriented retrieval
KG-derived retrieval
```

这是一个非常值得测试的 topology。

因为它可以直接回答：

> MemPalace 的强项是否值得作为一个额外 integration seam 保留？

---

### U-C：Unified DB + Dedicated Search

```text
Registry DB
+
Entity/Object Store
+
Session Store
+
Search Engine
+
Vector Engine
```

只有当 U-A/U-B 的真实 workload 明确证明：

```text
search / vector
+
scale
```

超过单体拓扑成本时，才进入。

---

### U-D：MemPalace-centric

只有在重新构造其 authoritative identity / revision / lineage 等机制之后才有资格进入。

不能把：

```text
MemPalace AS-IS
```

直接算完整 Information Space candidate。

这与 10 月 5 日的 `MEMPALACE_ISMCI_ADAPTER_FEASIBILITY_AUDIT` 一致：As-is 不能直接满足当前严格的 carrier obligations；后续 Core Sufficiency Audit 又把问题收窄为“MemPalace native semantic surface 与 InformationCore 的边界”，而不是否定 MemPalace 的 session 价值。

---

# 17. “MemPalace capability parity”应该成为 U-A 的验收参考，而不是 schema 参考

也就是说，不复制：

```text
wing
room
drawer
closet
```

这些具体对象。

而验证 U-A 能否提供同等级行为：

```text
✓ Raw session retention
✓ Incremental session ingestion
✓ Session lexical retrieval
✓ Session semantic retrieval
✓ Session provenance
✓ Cross-session retrieval
✓ File ↔ Session relations
✓ Historical session recall
✓ Work-frontier retrieval
✓ Negative-knowledge recall
✓ Rebuild derived indexes
✓ Resume after restart
```

其中：

```text
MCP
wake-up API
agent UI
```

属于上层 interface，而不是 carrier correctness requirement。

---

# 18. 新增一个非常重要的 correctness requirement

从 G3-1 得到：

```text
过去的排除判断
+
basis
```

必须能被重新发现。

所以加入：

```text
Historical Judgment Review
```

测试。

例如：

```text
旧判断：
“经济运行汇报 = 相邻主题，因此排除”

后来：
0308 内容发生变化

系统必须能够回答：

1. 当初排除是什么？
2. 为什么排除？
3. 依据是什么？
4. 这个依据来自哪个 Information？
5. 后来哪些 Information 发生了变化？
6. 为什么应该重新审查？
```

这是普通数据库 benchmark 完全测不到的，但它是 Information Space 的核心能力。

---

# 19. 新的性能评价不能只看 DB latency

继续保留：

```text
P50
P95
P99
ingest
lookup
search
rebuild
recovery
RSS
disk amplification
```

但 Session + File 统一后新增：

```text
session append throughput
timeline reconstruction
session semantic retrieval
cross-domain retrieval
file→session traversal
session→file traversal
historical judgment lookup
index rebuild equivalence
checkpoint materialization
resume latency
```

更重要的是继续测：

```text
integration seam cost
```

例如：

```text
U-A:
one authority
one transaction domain
one search namespace

U-B:
InformationCore → MemPalace
                    ↑
                 second system
```

不能只报告 MemPalace search 速度。

要测：

```text
ingest
→ canonical store
→ derived index
→ query
→ provenance
→ cross-domain relation
```

整个路径。

---

# 20. 对当前 CCVS-01 的治理处理

这里不要偷偷修改已经冻结的：

```text
CCVS-01-PB v1.2
```

现在建议形成：

```text
CCVS-01
│
├── PB v1.2
│     └── File-side validated baseline
│
└── Unified Information Addendum
      ├── Session workload
      ├── File + Session workload
      ├── Session correctness
      ├── cross-domain retrieval
      └── unified recovery
```

已有：

```text
A File baseline
P8 G2
```

全部保留。

新增 addendum 不需要重新证明：

```text
File create
File move
File large object
...
```

已经通过的 File evidence 可以继承。

新增实验只验证：

```text
Session-specific
+
Unified cross-domain
```

---

# 21. 我建议的新 Phase 顺序

```text
当前
Baseline A File = PASS
P8 = PASS
        │
        ▼
U-0 Session Evidence Consolidation
        │
        ├── G0 / Real Carrier
        ├── G1
        ├── G2
        ├── G3
        └── G3-1 / G3-2
        │
        ▼
Human ruling
        │
        ▼
U-1 Unified Addendum Protocol
        │
        ▼
U-2 A+ Unified implementation
        │
        ▼
Session conformance
        │
        ▼
Session admission
        │
        ▼
Session / Unified benchmark
        │
        ▼
U-B MemPalace-derived topology
        │
        ▼
U-C richer composition only if evidence requires
```

这里 **U-0 本质上主要是证据继承和协议重构，不是重新做实验。**

---

# 22. 最终我建议把“预定型方案”定成这个逻辑

```text
                SimiGo
                  │
          semantic data model
                  │
                  ▼
        ┌─────────────────────┐
        │ Information Space   │
        │                     │
        │ Information         │
        │ Representation      │
        │ Relation            │
        │ Revision            │
        │ Provenance          │
        │ Availability        │
        │ Locator             │
        │ Session             │
        │ SessionEvent        │
        └─────────┬───────────┘
                  │
      ┌───────────┴───────────┐
      │                       │
 File Representation     Session Representation
      │                       │
 POSIX/entity store       event/raw store
      │                       │
      └───────────┬───────────┘
                  │
          authoritative source
                  │
      ┌───────────┴───────────┐
      │                       │
 Exact / Structured       Derived Search
                          ├─ FTS
                          ├─ Semantic
                          └─ Relation expansion
```

这套方案有一个非常重要的性质：

> **它没有把“File Information”当成主数据、“Session Information”当成附加表。**

二者都首先变成：

```text
Information
```

然后各自有自己的：

```text
Representation
```

其中 File 的 Representation 是文件字节，Session 的 Representation 是事件/对话/工作记录。

这才真正符合你现在逐步验证出来的 Information Space 方向。

---

## 当前建议的 Human decision point

现在我不建议继续直接做 Candidate B adapter。

下一步应该只裁定一件事：

```text
是否接受：
CCVS-01 增加
“Unified File + Session Information Carrier”
作为正式验证范围？
```

接受后，**我建议第一候选不是 MemPalace，也不是 PostgreSQL/Qdrant 等复杂组合，而是先把现有 Baseline A 演化成 `U-A Unified Minimal`**：

```text
SQLite Registry
+
Session Event Store
+
POSIX Entity Store
+
Relation/History
+
Locator/Availability
+
FTS5
+
可插拔 Derived Semantic Index
```

然后用：

```text
archive-organizer = File workload
MemPalace/G1-G3 = Session workload
两者交叉 = Unified workload
```

去验证它是否真的能达到 MemPalace 的**Session Information 行为能力**，而不是复制 MemPalace 的实现。

**如果 U-A 能做到，B 就不值得引入；只有 U-A 在真实 Session workload 上失败，才有充分理由把 MemPalace 或独立 Search/Vector 系统引入。**

这条路线与目前“最少成熟基础设施 + 最小 seam + SimiGo 自有语义层”的原则是完全一致的。
