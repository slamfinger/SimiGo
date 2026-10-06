# CCVS-01 U-1 Revision Ruling

> **Status:** REGISTERED
> **Date:** 2026-10-06
> **Scope:** CCVS-01 — ruling on the U-1 Unified Addendum Protocol v0.1
> delivery (`PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U1_UNIFIED_ADDENDUM_PROTOCOL_V0.1_20261006.md`)
> **Verdict:** B = REVISE (direction confirmed; U-0 retained; U-1 revised
> within a narrow structural scope; U-2 remains blocked)
> **Precedence note:** the Human issued two messages in this round. Message 2
> is a self-issued TIGHTENING of message 1 and is the operative form wherever
> the two differ. Both are archived verbatim below. The relation is explicit:
> message 2 replaces message 1's "Canonical Information Space Logical Model
> (redefine InformationCore / RelationCore / Store)" framing with the
> "Unified Carrier Contract over the EXISTING SimiGo Information Space
> semantics" framing.

---

## 1. Message 1 — designated ruling block (verbatim)

The Human designated the following block as the ruling text for this round
("可以直接把下面这段作为本轮对 agent 的裁定"):

**Decision: B = REVISE**

Unified File + Session Carrier 方向继续成立。U-0 Session 证据固化继续保留。U-1 不否定、不返工，但在进入 U-2 implementation 前增加一个受限的结构修订门。

### 1. 新增 Canonical Logical Model

U-1 必须明确 Information Space 的最小逻辑结构：

```text
InformationCore
RelationCore
Store

Carrier
CarrierRecord
Information
Relation
DerivedIndex
```

其中：

* `Information` 是 Information Space 的稳定语义对象；
* `Carrier` 是信息承载方式，至少支持 `FILE` 与 `SESSION`；
* `CarrierRecord` 是 Carrier 内部可定位的记录/片段/事件；
* `Relation` 表达 Information 之间的语义关系；
* `DerivedIndex` 是可删除、可重建的派生结构，不是事实源。

### 2. File / Session 的统一原则

File 与 Session 都是 Carrier，不得分别形成两套 Information 数据模型、两套 Store 或两套独立的核心语义。

SessionEvent 不得直接等同于 Information。

File 中的 section/chunk/extracted representation 与 Session 中的 event/summary event，都应首先属于 CarrierRecord 层，再通过明确的 provenance / semantic mapping 关联到 Information。

### 3. 必须定义的身份关系

U-1 至少明确：

1. Information Identity
2. Carrier Identity
3. CarrierRecord Identity
4. Information ↔ CarrierRecord 映射
5. Information ↔ Information Relation
6. DerivedIndex ↔ source version/fingerprint

并明确各自的生命周期与可变性边界。

### 4. 现有 U-1 内容继续有效

I14–I18、G9–G12、F10–F14、S1–S8、WL6-U 等不撤销。

但这些内容应重新标注为：

> "对 Canonical Logical Model 的 correctness / failure / workload verification"

而不是把 workload protocol 本身当作数据库结构。

### 5. 必须保持的硬约束

* 不新增 FileStore / SessionStore 等平行核心 Store。
* 不让 Session schema 侵入 InformationCore。
* 不让 CarrierRecord 取代 Information。
* 不让 DerivedIndex 成为事实源或身份源。
* 不因本次结构修订重新打开 MemPalace backend selection。
* 不修改 PB v1.2。
* 不进入 U-2 implementation，直到 Canonical Logical Model 完成并通过 Human Review。

### 6. 本轮修订目标

本轮只回答一个问题：

> **在 File 与 Session 统一成为 Carrier 后，Information Space 中什么是"Information"、什么是"Carrier"、什么是"Record"、什么是"Relation"、什么是"Index"，以及它们如何稳定连接。**

完成后再进入 U-2。

(Non-operative reviewer note from message 1, registered for honesty: the
Human reviewed the delivered report and design semantics, not the commits
independently on the remote. Commit for independent verification:
`27bc805` on `integration/path-a-information-place`, pushed to
`slamfinger/SimiGo-Lab`.)

## 2. Message 2 — tightening (verbatim, operative)

现在确实应该把注意力重新拉回 **Information Space 本身的数据库/逻辑结构**，而不是继续讨论 Lab 仓库怎么整理。

从你给出的执行结果看，我的判断是：

**U-0 可以保留；U-1 不建议直接 A = FREEZE，应该 B = REVISE。**

但这个 REVISE 不是否定 Unified File + Session，也不是重新选择 Carrier，更不是重新打开 MemPalace。恰恰相反：**Carrier 方向已经可以继续，下一步应该把"统一载体"下真正不变的数据库语义钉住。**

对。这样一来，刚才我的判断还需要再收紧一层：**不是重新设计 Information Space 的语义模型，而是在 SimiGo 已经定义好的 Information Space 语义之上，解决 Carrier 的统一问题。**

真正的结构应该是：

```text
SimiGo Information Space
        │
        │ 已有、既定的 Information 语义
        ▼
   Information
        │
        │ 通过统一 Carrier 进入/定位/恢复
        ▼
     Carrier
      /   \
   File   Session
```

也就是说，**File 和 Session 的差异应该停留在 Carrier 层，而不能继续向上泄漏。**

### 这件事的关键，其实是"统一到哪一层"

我认为应该明确成下面四层，而不是再创造一套新的数据库语义：

```text
① Information Space Semantic Layer
   SimiGo 已定义
   ─────────────────────────
   Information
   Relation
   semantic state / provenance ...

② Unified Carrier Layer
   ─────────────────────────
   Carrier
     ├─ File Carrier
     └─ Session Carrier

③ Carrier Representation / Record Layer
   ─────────────────────────
   File:
      path / bytes / representation / segment ...

   Session:
      event / sequence / summary / turn ...

④ Derived Access Layer
   ─────────────────────────
   exact lookup
   index
   ranking
   semantic retrieval
```

这里最重要的是：

> **① 不因为 Session 加入而改变。**
>
> **② 才是现在真正需要统一设计的地方。**
>
> **③ 允许 File 和 Session 有物理差异，但必须服从同一个 Carrier Contract。**
>
> **④ 全部属于派生访问能力，不能反过来定义 Information。**

---

## 所以"Unified File + Session"真正要解决的不是 schema 合并

而是：

> **用一个 Carrier 抽象，把不同类型的现实信息来源，以同一种方式提供给 Information Space。**

例如：

```text
Carrier
  identity
  kind
  locator
  representation
  version
  capability
  records
  provenance
```

那么：

```text
File Carrier
  kind = FILE
  locator = filesystem path + fingerprint
  records = file representation units
```

和：

```text
Session Carrier
  kind = SESSION
  locator = session identity
  records = ordered session events
```

它们可以内部不同，但对上层只暴露共同能力：

```text
discover
locate
read
exact-retrieve
enumerate
summarize
reconstruct
```

这样 SimiGo 才真正做到：

**"Information 不关心自己来自文件还是对话。"**

---

# 更重要的一点：Session 不是第二类 Information

这是这次统一里最容易走偏的地方。

不能变成：

```text
File → Information
Session → SessionInformation
```

而应该是：

```text
File Carrier ─────┐
                  ├──→ Information Space
Session Carrier ──┘
```

Session 中的：

```text
event
turn
tool call
summary
checkpoint
```

本质都是**Carrier 内部的可定位内容**。

它们什么时候成为 Information、如何与既有 Information 建立关系，应该仍然由 SimiGo 已有的 Information Space 语义决定，而不是 Session 自己发展一套语义。

---

# 这样也能解释为什么你们现在的 U-0 是有价值的

U-0 那些约束其实都可以看成 **Unified Carrier 的约束**：

* `(SessionID, sequence)` → Carrier 内部稳定 ordering
* `RepresentationLocator` → Carrier 内容定位
* exact 层 → Carrier 能力不能被 ranking 替代
* `IndexSource` → 派生访问结构必须可重建
* wake-up contamination → Carrier 读取不能把派生噪声当事实
* XLSX flattening → Carrier representation 不能丢失原始定位关系

所以 U-0 的方向其实是对的。

真正需要修的是：

> **U-1 不应该继续把重心放在"再定义多少 session workload / fixture / gate"。**

而应该先把这些测试全部挂回：

> **统一 Carrier Contract**

---

# 我会因此把当前结构判断改成

```text
SimiGo
│
├── Information Space Semantic Model   ← 已有，不重做
│
├── Unified Carrier Contract           ← 当前核心工作
│     ├── File Carrier
│     └── Session Carrier
│
├── Representation / Record semantics  ← Carrier内部实现边界
│
└── Derived Access
      ├── Exact
      ├── Index
      └── Semantic
```

其中最值得冻结的是这一条：

> **File 与 Session 是 Carrier 的两个实例族，而不是 Information Space 的两个语义分支。**

---

因此我现在会把本轮裁定更准确地表述成：

**不是"重做 Information Space Logical Model"。**

而是：

**"在既有 SimiGo Information Space 语义不变的前提下，完成 Unified Carrier Contract，使 File Carrier 与 Session Carrier 可以无语义分叉地接入同一个 Information Space。"**

这实际上比我上一条提出的"重新定义 InformationCore / RelationCore / Store"更符合你现在 SimiGo 的研究阶段。后者容易又把已经存在的语义往数据库实现层重新拆一次，反而会产生重复设计。

---

## 3. Registered consequences

```text
R-1  U-0 is RETAINED unchanged (both messages affirm it; message 2
     re-reads its obligations as Unified Carrier constraints — the
     re-anchoring happens in UA v0.2, U-0 itself is not edited).

R-2  UA v0.1 = REVISED, not rejected. The revision produces UA v0.2
     with this scope and no more:
       (a) NEW: Unified Carrier Contract over four layers —
           ① existing SimiGo Information Space semantics (referenced,
           NOT redefined) / ② Unified Carrier Contract (the new
           center) / ③ Carrier Representation/Record layer / ④ Derived
           Access layer;
       (b) the six identity relations from ruling §3 defined inside the
           contract, with lifecycle and mutability boundaries, where
           Information Identity and Information↔Information Relation
           are the EXISTING frozen semantics cited, not re-specified;
       (c) re-anchoring: I14–I18, G9–G12, F10–F14, S1–S8, X1–X8,
           WL6-U, PB-U1..U11 stay valid and are re-labelled as
           correctness/failure/workload verification OF the contract;
           no new workload/fixture/gate definitions;
       (d) corrections to v0.1 required by the tightening:
           the proposed universal `kind` field on Information is
           dropped (existing Information semantics untouched; carrier
           origin lives on the Carrier/Record side);
           "a Session is an Information" (v0.1 L7) is corrected —
           Session content becomes Information only through the
           existing formation semantics, never automatically;
           Session/SessionEvent as separate first-class logical
           objects become Carrier / CarrierRecord instances.

R-3  Frozen principle (the one the Human marked most worth freezing):
     File and Session are two instance families of Carrier, not two
     semantic branches of Information Space. Their differences stop at
     the Carrier layer and must not leak upward.

R-4  Hard constraints carried verbatim from ruling §5 (with the
     message-2 tightening applied): no parallel core Stores
     (FileStore/SessionStore); Session schema must not invade
     InformationCore; CarrierRecord must not replace Information;
     DerivedIndex never a fact or identity source; no MemPalace
     backend reopening; no PB v1.2 modification; no U-2 until this
     revision passes Human Review.

R-5  UA v0.2 returns to AWAITING HUMAN REVIEW. On ACCEPT/FREEZE the
     Human separately decides U-2 authorization. On further REVISE,
     enumerated items only.
```
