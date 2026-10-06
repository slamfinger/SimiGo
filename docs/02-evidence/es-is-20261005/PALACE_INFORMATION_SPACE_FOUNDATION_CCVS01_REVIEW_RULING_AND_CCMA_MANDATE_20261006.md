# CCVS-01 Review Ruling and CC-MA Mandate

> **Status:** REGISTERED
> **Date:** 2026-10-06
> **Object ruled on:** `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U1_V0_2_CONFORMANCE_REVIEW_20261006.md`
> (final status REVISE, R-1..R-11, zero BLOCK) and UA v0.2
> **Verdict:** B = REVISE — direction and semantic-anchoring conclusions
> ACCEPTED; UA v0.2 NOT frozen; UA v0.3 mandated with R-1..R-11 fixes,
> A-1..A-3 dispositions, and a new mandatory contract surface
> **CC-MA (Multi-Agent Carrier Consistency)**.
> **Precedence note:** the Human issued three messages this round. Message 3
> is the formal operative instruction to the local Agent. Message 1 is the
> concurrency mandate (C1–C10 catalog, design objects, binding design
> scenario, Agent positioning). Message 2 is the Human's own capability-gap
> assessment of the current design ("architecture compatible, capability
> not yet fully covered") and its honest verification boundary. All three
> are archived verbatim below and together constitute the CC-MA design
> basis.

---

## Message 1 — concurrency mandate (verbatim)

对。这样第二条就不能只停留在"建议用独立 worktree"这个工程治理层面。

**两个 Agent 同时读写、持续产生和整理 Information，本身就是未来 Information Space 的高频运行场景，因此必须在 Unified Carrier 的数据库设计阶段就纳入。**

但要注意边界：

> **数据库需要具备多 Agent 并发工作的正确性，不等于把 `Agent` 重新定义成 Information Space 的语义对象。**

数据库设计解决的是 **concurrency / consistency / provenance / conflict**；SimiGo 的既有 Information 语义保持不变。

**Decision: REVISE — Multi-Agent Concurrency 是 Unified Carrier 的数据库设计约束**

### 1. 裁定

本次两个 Agent 同时工作的实际场景确认：

> 多 Agent 同时读取、产生、修改、整理同一 Information Space 的信息，将是未来 SimiGo 的高频工作场景之一。

因此，多 Agent 并行不是后续部署或运维问题，而必须在当前 **Unified Carrier / 数据库设计阶段**作为一等工程约束考虑。

该裁定不改变既有 SimiGo Information Space 语义。

不得增加：

* AgentInformation
* AgentRelation
* Agent-specific Information semantics
* File semantic branch
* Session semantic branch

Agent 是操作主体，不是新的 Information Space 语义对象。

---

### 2. 数据库设计必须支持的基本能力

Unified Carrier 的数据库逻辑与物理设计至少必须能够保证：

#### C1 — Concurrent Read

多个 Agent 可以同时读取同一 Information / Carrier / Representation，而不会互相阻塞到无法工作。

#### C2 — Concurrent Write

多个 Agent 可以同时向同一 Carrier 写入新内容或新版本，不得因为单一全局写锁导致整个 Information Space 串行化。

#### C3 — Lost-Update Prevention

Agent A 读取版本 V1 后工作期间，Agent B 已将同一对象更新为 V2：

Agent A 后续提交时：

```text
MUST detect stale version
MUST NOT silently overwrite V2
```

允许的结果只能是：

```text
accept
merge
rebase/re-read
conflict
retry
```

不能是 blind overwrite。

#### C4 — Atomicity

涉及多个相关对象的更新必须具有明确原子边界。

例如：

```text
new Representation
+ Carrier version
+ provenance
+ relation/reference
```

不能出现"主体已经提交，但 provenance/reference 半提交"的不可解释状态。

#### C5 — Identity Stability

并发修改不能因为：

* file rename
* file move
* representation revision
* session append
* re-index
* summary materialization

而无意改变既有 Information / Carrier identity。

特别禁止：

```text
path change == new Information
event append == new Session identity
index entry == Information identity
```

#### C6 — Session Ordering

Session Carrier 必须保持：

```text
(SessionID, sequence)
```

稳定。

多个 Agent 对同一 Session 并发追加时，必须定义：

* ordering authority
* sequence allocation
* duplicate prevention
* retry/idempotency
* failure recovery

不得依赖客户端时间戳自行推断顺序。

#### C7 — Idempotent Retry

Agent 在网络失败、进程崩溃或提交结果未知后重试，不得产生重复：

* Information
* Representation
* SessionEvent
* Relation
* provenance record

必须存在稳定的 operation/event identity 或等价机制。

#### C8 — Provenance Under Concurrency

每个并发产生的变化都必须能够回答：

```text
who / when / from which version / based on what representation / resulting version
```

该信息属于 provenance / history，不得改变 Information 的既有语义定义。

#### C9 — Derived Index Isolation

多个 Agent 同时更新 authoritative data 时：

```text
authoritative store
        ↓
derived index
```

Index 更新允许滞后，但：

* 不得覆盖 authoritative data；
* 不得成为事实源；
* 必须可从 authority 重建；
* 必须能够识别 stale index；
* 并发 rebuild 不得破坏 authority。

#### C10 — Snapshot / Recovery

一个 Agent 在另一个 Agent 修改期间读取 Information Space 时，应能够获得明确的：

```text
consistent snapshot
或
明确的版本视图
```

不能出现一组关系跨越不同版本而形成"看似合法、实际不存在"的混合状态。

---

### 3. Database design phase 必须增加的设计对象

UA / U-2 design 中必须明确以下概念：

```text
Object Version
Revision / Generation
Operation Identity
Write Intent
Commit / Transaction Boundary
Concurrency Conflict
Idempotency Key
Snapshot / Read Version
Provenance
Index Build Version
```

这些是**数据库运行正确性机制**，不是新的 Information Space semantic objects。

---

### 4. 真实并行场景必须成为 binding design scenario

当前实际场景直接纳入：

```text
Multi-Agent Research Day
```

最小实例：

```text
Agent A:
  create/update research file
  create session records
  derive judgment
  reference file revision

Agent B:
  concurrently read existing lab material
  reorganize / rename / classify file
  update index / summary

Agent A:
  continue from earlier read
  encounter external revision
  attempt write

Database:
  detect version relation
  preserve both authoritative histories
  reject silent overwrite
  maintain identity/provenance
  rebuild derived index if required
```

该场景必须能够验证：

```text
No lost update
No identity duplication
No dangling provenance
No invalid cross-version relation
No session reorder
No duplicate retry
No derived-index corruption
```

---

### 5. File 与 Session 都必须经过同一并发模型

必须避免：

```text
File → normal DB concurrency
Session → special session lock system
```

而应该是：

```text
Unified Carrier concurrency model
             │
       ┌─────┴─────┐
       │           │
      File       Session
```

两者可以有不同的内部存储特性，但：

```text
identity
version
provenance
transaction
conflict
recovery
index invalidation/rebuild
```

必须遵守统一原则。

---

### 6. Agent 的位置

数据库可以记录 actor / producer，例如：

```text
actor_id
actor_type
operation_id
timestamp
```

但这些字段只属于：

```text
provenance / audit / concurrency control
```

不得成为新的 Information semantic layer。

也就是说：

```text
Agent ──operates on──> Carrier
Agent ──produces─────> Representation / Event / Relation
```

而不是：

```text
Agent ──is-a──> Information
```

---

### 7. 与当前 UA v0.2 的关系

U-1 v0.2 不需要因此重做 Information Space 语义。

但应增加一个明确的：

**Multi-Agent Concurrency / Consistency Design Obligation**

并将其纳入后续 U-2 composition manifest 的必检项。

特别是：

* C3 Lost-Update Prevention
* C4 Atomicity
* C6 Session Ordering
* C7 Idempotent Retry
* C8 Provenance
* C9 Derived Index Isolation
* C10 Snapshot / Recovery

不能等到实现后再发现。

---

### 8. 当前不要做的事

当前仍然：

```text
不把 Agent 建成新的 semantic entity
不创建 AgentStore
不创建 FileConcurrencyStore / SessionConcurrencyStore 两套机制
不改变 InformationCore / RelationCore 定义
不修改 PB v1.2
不提前实现 U-2
不进行 backend selection
```

当前任务是把 **Multi-Agent Concurrency** 纳入 Unified Carrier 的数据库设计契约。

**最终判断：**

> File + Session 的统一不仅意味着统一数据语义和 Carrier interface，还必须意味着在高频多 Agent 并发读写下，二者共享同一套 identity / version / transaction / provenance / conflict / recovery / derived-index consistency 模型。

该要求属于 Unified Carrier 的基础设计约束，而不是后续运维增强。

---

## Message 2 — capability-gap assessment (verbatim, operative as design basis)

结论很明确：

**现有设计"可以承载"第二条裁定，但目前"还没有支持到可以保证"的程度。**

也就是说，不需要推翻现有数据库方向；但**多 Agent 并行必须补进现有 Unified Carrier 数据库设计，否则到了 U-2 才处理会太晚。**

我核对到的现有 Carrier 设计已经有这些基础：

* `InformationRegistry`
* `EntityRepresentationStore`
* `LocatorIndex`
* `RelationHistoryStore`
* `SessionInformationStore`
* `DerivedSearchIndex`
* `AvailabilityStore`
* `CarrierIntegrityReporter`

并且已经定义了 `create / move / revise / copy / split / merge / delete / restore / pin / session append / summary / relation / search / rebuild` 等操作；现有 conformance 也已经覆盖了 locator move 保持 Information identity、revision 保持历史 representation、session event 顺序、index rebuild 等。

但是，这些还主要解决：

> **单个 Carrier 的一致性与语义正确性**

而第二条裁定要求的是：

> **多个 Agent 同时对同一个 Information Space 工作时仍然正确。**

### 逐项看

| 第二条要求 | 现有设计 | 判断 |
| --- | --- | --- |
| Concurrent Read | 有 | **基本支持** |
| Concurrent Write | 有 Store/Runtime，但没有并发协议 | **不足** |
| Lost-update prevention | 当前未见 revision compare-and-swap / optimistic concurrency | **缺口** |
| Atomicity | 当前 Runtime 明确"不把跨组件 transaction semantics 做成 universal" | **明显缺口** |
| Identity stability | 已较好，move / revise / pin 已覆盖 | **已有基础** |
| Session ordering | `(SessionID, sequence)` 已有方向 | **部分支持** |
| Idempotent retry | 未见 operation identity / idempotency key | **缺口** |
| Provenance | 已有 relation/history/provenance 方向 | **部分支持** |
| Derived-index isolation | `DerivedSearchIndex` + rebuild 已有 | **较好，但需要并发失效规则** |
| Snapshot consistency | 未见明确 snapshot/read-version contract | **缺口** |
| Multi-agent conflict resolution | 尚无正式 contract | **缺口** |

尤其值得注意的是，现有 `InformationSpaceRuntime` 明确说明：**它不会把跨组件事务语义统一起来，而把这些差异留给未来候选 Carrier 暴露和测量。** 这意味着目前设计有很好的"组件边界"，但还没有形成我们刚才要求的**统一并发一致性模型**。

所以答案不是"数据库设计错了"，而是：

> **现在的设计已经把骨架搭好了，但还缺一个 Multi-Agent Concurrency Contract。**

### 最重要的是，不要另造一个并发数据库层

我不建议变成：

```text
Information DB
+
Agent DB
+
Conflict DB
```

还是同一个 Carrier DB，只增加必要的并发控制字段/机制，例如概念上：

```text
Information
    revision / generation

Representation
    revision

Operation
    operation_id
    actor_id
    base_revision

SessionEvent
    event_id
    sequence

Transaction
    commit boundary

Index
    source revision
    build revision
```

这样 Agent 只是：

> **产生操作的 actor**

而不是 Information Space 的新语义对象。

---

### 对现在的 U-1，我认为应该新增一个非常窄的要求

不是重写 UA v0.2，而是在 **Unified Carrier Contract** 里面增加：

**CC-MA / Multi-Agent Consistency**

至少冻结这五件事：

```text
1. optimistic stale-write detection
2. atomic multi-object update boundary
3. idempotent operation identity
4. consistent read/snapshot semantics
5. derived-index invalidation/rebuild under concurrent writes
```

Session 再额外加：

```text
sequence allocation
append idempotency
```

然后把你今天实际发生的：

> Agent1 正在研究并产生新文件/协议
> Agent2 同时整理 Lab 文件/索引

作为第一个真实 workload。

---

### 还有一个很重要的现实限制

我这次能直接核对到的是**仓库当前可见的 Carrier-neutral 设计文件**。其中 `CarrierSQLite adapter` 的本地最新实现并没有出现在我现在能读取的 GitHub 默认分支内容里，所以我**不能据此声称 SQLite A1 的实际代码已经具备或不具备上述并发机制**。

但从目前已经冻结/交付的 Carrier 设计来看，结论已经足够：

**架构兼容，能力尚未完整覆盖。**

因此，我建议现在不要让 Agent 直接做 U-2，而是让它在现有 UA v0.2 上增加一个很小的 **Multi-Agent Concurrency Design Addendum**，专门把"并发正确性"接入现有 Carrier，而不是另起炉灶。

这一步做完，才真正具备进入数据库实现设计的条件。

---

## Message 3 — formal ruling (verbatim, operative)

我看完这份结果后的判断是：

## 当前裁定：**B = REVISE，接受研究方向，不接受 UA v0.2 冻结**

这次 Agent 的审查做得是对的，而且比继续讨论"要不要统一 File/Session"前进了一步。

更重要的是，它证明了一个事情：

> **Unified Carrier Contract 已经没有发现与既有 SimiGo Information Space 语义冲突。**

所以现在不需要再回头讨论 Information / Relation / Store 的基本语义，更不需要再造 Canonical Logical Model。

### 三个发现尤其关键

**R-1 是必须修。**

"删除 raw session event → Information loss"确实会把 Carrier Record 与 Information 混在一起。

正确边界应是：

```text
CarrierRecord 被删除
        ↓
Carrier 中的原始形成依据/表示可能丢失
        ↓
但已经形成的 Information 不因此自动消失
```

这实际上是在保护 Information 的既有不可变语义。这个不能只当措辞润色。

**R-3 更重要。**

现在已经出现真实情况：

```text
Agent A 产生内容
Agent B 形成/提交 representation
```

因此至少要区分：

```text
Information.Provenance
Carrier-operation / Carrier-production provenance
```

同名但不同层，必须显式消歧。否则未来多 Agent 场景下 provenance 会非常容易串层。

**R-8 也必须修。**

"identity never re-derived from digest"写得太绝对，会和"digest 可以参与 identity formation"混淆。

真正要表达的是：

> **既有 identity 不因 path/name/carrier representation 的变化而重新漂移。**

而不是：

> digest 在 identity formation 中永远不能参与。

这是数据库设计层面很重要的区别。

---

# 但是，我认为这份审查还缺一个新的必审面

就是我们刚刚裁定的：

## **Multi-Agent Concurrency**

你们现在的审查已经把真实场景列进来了：

> Agent A 写研究文件
> Agent B 整理 Lab
> 外部修改后重新读取
> L0 stale index
> provenance 双生产者

很好。

但这些目前只是 **workload / diagnostic examples**。

而我们刚刚已经做出更强的裁定：

> **多 Agent 并行是 Information Space 数据库的高频场景，因此必须在数据库设计阶段成为基础约束。**

所以我认为 UA v0.3 至少应该明确一个：

```text
CC-MA — Multi-Agent Carrier Consistency
```

它不定义新的 Information 语义，只定义 Carrier 层数据库必须保证的行为。

最少应覆盖：

```text
stale-write detection
lost-update prevention
atomicity boundary
operation identity / idempotent retry
concurrent session append ordering
provenance under concurrent writes
snapshot / read-version consistency
derived-index invalidation/rebuild
```

这一点非常重要，因为否则现在这份 Conformance Review 很容易形成：

```text
UA-CC
  ✓ File / Session 同构
  ✓ Identity
  ✓ Locator
  ✓ Representation
  ✓ Provenance
  ✓ Derived index
  ...
```

但到了 U-2 才发现：

> 两个 Agent 同时修改同一个 Carrier，到底谁的结果有效？

那就太晚了。

---

# 所以现在正确的推进顺序是

```text
UA v0.2
   ↓
Conformance Review
   ↓
REVISE
   ↓
UA v0.3
   ├─ R-1..R-11 修正
   ├─ A-1..A-3 明确裁定输入
   └─ CC-MA 多 Agent 并发约束
   ↓
Targeted Conformance Review
   ↓
Human ACCEPT / FREEZE
   ↓
才进入数据库组合设计 / U-2 authorization
```

这里的 **CC-MA 不应该导致重新设计 Information / Relation / Store**。

实际上恰恰相反：

> **Phase 2 已经证明 Information 与 Relation 是独立语义对象、两个 Store 是平行边界，所以并发控制应该建立在这个已有边界上。**

数据库可以解决：

```text
identity
revision
transaction
operation
conflict
provenance
recovery
```

但不能借此重新定义：

```text
Information
Relation
Session
```

---

## 我给本地 Agent 的下一步指令

**Human Ruling — B = REVISE**

接受 UA v0.2 的总体方向与现有语义锚定结论。

不接受 v0.2 冻结。

请在不改变既有 SimiGo Information Space 语义的前提下交付 UA v0.3。

### A. 必须修订

逐项处理 Conformance Review 的：

* R-1 … R-11
* A-1 … A-3

不得擅自把 unresolved ambiguity 转化为 Human decision。

### B. 三项必须特别保持

1. `SessionEvent / CarrierRecord ≠ Information`

删除、失效或重建 Carrier Record 不得自动等价于删除既有 Information。

2. 明确区分：

`Information.Provenance`
与
`Carrier operation / production provenance`

二者不能因同名而混成一个字段或一个语义。

3. 区分：

`identity formation input`
与
`identity stability rule`

digest 可以参与 identity formation，但既有 Information Identity 不得因 path/name/carrier/revision 等变化而漂移。

### C. 新增：CC-MA — Multi-Agent Carrier Consistency

这是数据库设计约束，不是新的 Information Space semantic layer。

必须明确 Unified Carrier 在多个 Agent 并行工作时至少保证：

* stale-write detection
* lost-update prevention
* atomicity boundary
* operation identity / idempotent retry
* concurrent Session append ordering
* concurrent provenance preservation
* snapshot / read-version consistency
* derived-index invalidation / rebuild

使用当前真实场景作为 workload evidence：

`Agent A = actual research writer`
`Agent B = Lab organizer`

但不要把 Agent 建模为新的 Information semantic entity。

### D. 不得做

* 不重写 Information / Relation 定义
* 不建立 Canonical Logical Model
* 不修改 PB v1.2
* 不修改 Frozen Contracts
* 不实现 U-2
* 不选数据库/backend
* 不建立新的数据库
* 不修改历史实验结论
* 不把真实并行场景提升为已经完成的 concurrency validation

### E. 输出

交付：

`PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U1_UNIFIED_ADDENDUM_PROTOCOL_V0.3_20261006.md`

同时保留 v0.2 = SUPERSEDED / review lineage。

完成后进行一次 **Targeted Conformance Review**，只重新验证：

1. R-1..R-11 是否关闭；
2. A-1..A-3 是否获得明确 disposition；
3. CC-MA 是否与既有 Information / Relation semantics 无冲突；
4. File / Session 两个 Carrier family 是否仍保持同构；
5. Identity / Representation / Locator / Record / Provenance boundary 是否仍清楚。

若无 BLOCK，则回到 Human Review / Freeze 门。

U-2 继续 `NOT AUTHORIZED`。

这一步完成后，我认为才真正到了一个很干净的节点：

> **SimiGo 已有 Information Space 语义 → Unified Carrier Contract → File/Session 统一 → 多 Agent 并发成为数据库设计约束 → 再研究怎样复用成熟 OSS 实现。**

这条路线现在已经开始从"理论设计"转向你说的那种**工程实际逼出抽象，再复用已有优秀能力**。

---

## Registered consequences

```text
G-1  UA v0.2 direction and the conformance review's semantic-anchoring
     conclusion are ACCEPTED (no conflicts with frozen semantics; no
     Canonical Logical Model; no return to Information/Relation/Store
     basics).

G-2  UA v0.3 mandated: R-1..R-11 applied; A-1..A-3 given explicit
     dispositions (as decision INPUTS, not self-decided Human rulings;
     A-1/A-3 explicitly deferred/marked, A-2 adopted as a flagged
     carrier-layer default); R-1/R-3/R-8 implemented per ruling B.1-B.3
     (CarrierRecord deletion ≠ Information deletion; Information
     .Provenance vs carrier-operation provenance explicitly distinct;
     identity formation input vs identity stability rule explicitly
     distinct).

G-3  CC-MA added as a new mandatory contract surface: MA-1..MA-10
     incorporating the C1-C10 catalog verbatim; design objects list;
     unified concurrency model across both families (no two-family
     split); Agent positioned as actor only; MA-DS-1 "Multi-Agent
     Research Day" as binding DESIGN scenario (not a completed
     validation); new additive correctness bounds I19-I25 mapped from
     the ruling's seven verifications; CC-MA mechanisms become
     mandatory U-2 composition-manifest check items.

G-4  Honest status inherited from Message 2: current preconstruction =
     component boundaries good, unified concurrency model absent;
     capability gap table carried into CC-MA as design basis; the
     Human's verification boundary (CarrierSQLite local implementation
     not assessed) is recorded; the real parallel scenario remains
     workload evidence, NOT a completed concurrency validation.

G-5  After UA v0.3: Targeted Conformance Review re-verifying exactly
     five points (R-closure, A-dispositions, CC-MA semantic
     compatibility, family isomorphism, identity boundaries). If no
     BLOCK -> Human Review/Freeze gate. U-2 remains NOT AUTHORIZED.

G-6  Standing prohibitions unchanged: no Information/Relation
     redefinition, no Canonical Logical Model, no PB v1.2 change, no
     Frozen Contract change, no U-2, no backend selection, no new
     database, no historical-conclusion modification, no Agent
     semantic entity / AgentStore / two-family concurrency split.
```
