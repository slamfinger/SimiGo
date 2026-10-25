# Gate Spec — Phase 2: Relation Boundary Gate（仅 Spec，零实现）

Date: 2026-10-02  
Status: `PHASE 2 OPENED / SPEC REGISTERED / AWAITING HUMAN RULINGS`  
前置：Phase 1 全链 CLOSED（Semantic Surface FROZEN → First
Implementation ACCEPTED → Integration PASS → Backend Independence
PASS → Persistence Semantics PASS，契约 S1–S6 FINALIZED）  
本 Gate 核心问题（human 逐字）：

> **Relation 是否能够作为 Information 之上的独立语义层存在，
> 而不改变 Information 本身？**

节奏不变：Spec → human decision → minimal implementation →
structural audit → runtime evidence → Gate PASS → seal。

## 0. 已冻结的 Relation 语义存量（本 Spec 的边界起点）

Phase 1 C1 裁定已把以下内容置入冻结面（非预埋、待建模）：

```text
Relation
├── subject
├── predicate
├── object
└── provenance
```

服务树观测事实（Phase 0 审计 + 服务树锚点）：
`knowledge_graph.py add_triple(:250)`——triple 含
valid_from/valid_to/confidence/source_drawer_id/source_closet/
source_file；**triple_id 含 `datetime.now()` 盐**（:198）⇒ 服务树
的 Relation identity **非确定性**（同一事实重复落库产生不同 ID，
不幂等）——与 drawer 的确定性 ID 形成对照。此观测为 D2 的
关键决策输入。

## 1. D1 — Relation 的语义对象是什么

| 选项 | 内容 | 依据 |
|---|---|---|
| (a) | 有向二元关系：subject → predicate → object，端点引用 **Information identity**（即 Relation 把已存在的 Information 事实连成结构），自身带 provenance | human 最小结构图（Information A—Relation—Information B）；C1 冻结面四字段 |
| (b) | 自由端点关系（端点为任意语义字符串/实体名，与 Information 实例无关） | 服务树 KG 实际行为（实体名字符串，非 drawer 身份） |

记录者预分析：(a) 与 Phase 1 冻结面及 human 结构图一致；
(b) 是服务树既有能力的写照——**两者可并存但不可混同**：
(a) 是 Core 的 Relation；(b) 属服务树 KG 域，若需要也是后置层。
**待裁**：本 Phase 2 的 Relation 取 (a)、(b) 还是 (a)+(b) 分层。

## 2. D2 — Relation 是否拥有自己的 identity

| 选项 | 内容 | 依据 |
|---|---|---|
| (a) | 拥有 **opaque `RelationID`**（镜像 `InformationID` 模式：identity 是事实、配方是机制、机制侧铸造器、确定性派生自 (subject.id, predicate, object.id [, temporal 起点])） | C4 判词「identity 是事实；recipe 是机制」的 Relation 平移；服务树 datetime 盐**不采纳**（非确定性 = 重复落库不幂等，是机制缺陷非语义要求） |
| (b) | 无独立 identity（关系即事实对，不单独寻址） | ——则 Relation 无法被 store/fetch/单独引用，与「独立语义层」目标相悖 |

记录者预分析：(a)。**待裁**（含：确定性是否要求、temporal
起点是否入 hash 输入）。

## 3. D3 — Relation 是否 immutable

| 选项 | 内容 | 依据 |
|---|---|---|
| (a) | 不可变值语义（镜像 A1）：已形成的 Relation 完整、不可变、不可更新 | 与 A2′ 形成链同构（minter → RelationID → immutable Relation） |
| (b) | 可变（如 valid_to 事后补写） | 服务树 KG 有 valid_to 时段语义；「关系结束」若必须回写同一 Relation 则需可变或另立状态事实 |

记录者预分析：(a) 为主；若需要「关系终止」语义，**不回写**，
而是后置为独立状态事实（保持 A1 同构）。**待裁**（含：temporal
validity 是否进 Phase 2 最小面，还是整体后置）。

## 4. D4 — Relation 是否通过独立 boundary 持久化

| 选项 | 内容 | 依据 |
|---|---|---|
| (a) | 独立 `RelationStore` 边界（镜像 InformationStore：最小操作集 + 独立实现位），与 InformationStore **平行**、互不引用 | 分层干净；backend 可替换性可独立再证 |
| (b) | 复用 InformationStore（把 Relation 塞进 Information 持久化） | 违反 C1（Relation 非 Information 子类型）与已定稿 S1–S6 契约的适用域 |

记录者预分析：(a)。(b) 直接污染已冻结契约。**待裁**（含：
RelationStore 最小操作集是否同样以「实测行为→契约」路径收敛，
即 Phase 1 三 Gate 模式的复刻）。

## 5. D5 — Information 是否完全保持不变

**human 已定向为硬约束（非选项）**：Phase 2 全程

```text
Information.swift / InformationStore.swift / SQLiteStore.swift /
UpperLayer.swift / InMemoryStore.swift diff = 0
```

Relation 层的任何需求都不得触碰以上文件；违反 = FAIL 并重开
裁定。已验收模块是否**新增文件**（如 Relation 类型入
InformationCore vs 独立新模块）见 D7。

## 6. D6 — 两个既有 backend 能否继续透明存在

**human 已定向为硬约束（非选项）**：SQLiteStore / InMemoryStore
零改动、零 Relation 知识继续工作；Relation 的持久化实验不得
寄生其上。若 RelationStore 需要 backend，按 D4(a) 独立引入
（本 Gate 是否实现 persistence 待 D4/D8 裁定）。

## 7. D7 — 模块落位（附加裁定项）

| 选项 | 内容 | 依据 |
|---|---|---|
| (a) | 独立新模块（如 `RelationCore`），仅 `import InformationCore` 引用公共类型 | 镜像 I6/I8 结构证据模式：Relation 层与 Information 层的边界由模块边界物理表达 |
| (b) | 塞入 InformationCore 模块新文件 | 与 C1「Relation 不是 Information 的组成部分」精神相悖（模块即边界声明） |

记录者预分析：(a)。**待裁**。

## 8. Negative Space（Phase 2 全程有效）

Relation 层不得出现：activation、diary、execution state、
checkpoint、ack、Layer0-1、taxonomy、MCP、retrieval/ranking、
Information 字段新增、InformationStore API 新增、filing 入语义、
recipe 入语义、任何「以后方便」预埋。Information 负空间清单
继续全额有效。

## 9. Pass / Fail 条件（适用于本 Gate 后续实现轮）

- **PASS** = D1–D7 全获 human 裁定；实现（若有）零改动受保护
  五文件；负空间审计零声明命中；真实调用链/结构审计按裁定面
  通过；Build 零警告
- **FAIL** = 任何实现需要触碰受保护五文件或引入负空间类型
  ⇒ 停止、登记、重开裁定

## 10. 本 Gate 的推进方式

human 对 D1–D7 逐项裁（或整批裁 + 改动点）→ 裁定封存 →
按裁定最小实现 → 审计与实跑 → Gate 收口。**Spec 阶段零代码。**
