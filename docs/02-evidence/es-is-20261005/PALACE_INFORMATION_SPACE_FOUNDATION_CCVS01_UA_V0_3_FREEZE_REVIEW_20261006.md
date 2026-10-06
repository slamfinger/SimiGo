# CCVS-01 UA v0.3 — Human Freeze Review

> **Status:** REGISTERED / FREEZE GATE OPEN WITH FIVE CONDITIONS
> **Date:** 2026-10-06
> **Object:** UA v0.3 (`PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U1_UNIFIED_ADDENDUM_PROTOCOL_V0.3_20261006.md`)
> after its targeted conformance review (NO BLOCK)
> **Verdict:** design mainline ACCEPTED, no re-architecture; UA v0.3 NOT
> frozen as-is — **five freeze conditions** attached (§3). No UA v0.4 is
> created now; the conditions are incorporated at freeze ruling time.
> **State correction registered (§2):** CCVS-01 Phase C FILE SIDE has been
> executed and is valid; what has not started is Unified U-2. The two gates
> must never be conflated.

---

## Human freeze review message (verbatim)

我重新把当前远端盘面、`cc2912b` 谱系、Phase C 已有实验、UA v0.3 设计和状态账本交叉检查了一遍。结论和前一次相比有一个重要修正：**现在已经不是"准备开始 Phase C"，而是 File 侧 Phase C 已经完成了一轮真实 Baseline A 实验；真正尚未进入的是 Unified Carrier 的 U-2。**

### 1. 当前 Git 盘面已经确认

| 分支                                        | 当前定位                                                                                    |       与 `main` |
| ----------------------------------------- | --------------------------------------------------------------------------------------- | -------------: |
| `main`                                    | `0a23fb0`，正式主线                                                                          |             基准 |
| `integration/path-a-information-place`    | `27bc805`，Unified direction + U-0/U-1 v0.1 的集成备份，也是现有 File-side Phase C 证据的共同祖先         |            +15 |
| `codex/research-recovery-layer-v0.1`      | **`cc2912b`**，包含 v0.2 review → ruling → Evidence Matrix → **UA v0.3 + targeted review** |            +27 |
| `codex/execution-state-research-20260929` | 旧 ES 分支                                                                                 | 比 `main` 落后 14 |
| `research/es-reuse-program-20260930`      | 独立旧研究线，已严重分叉                                                                            |      +9 / -654 |

`cc2912b` 与 `codex/research-recovery-layer-v0.1` 已经完全一致，反向比较也是 `0/0`。所以你说的"本地已提交并推送"在远端侧已经得到回验。

而且我进一步追了 `cc2912b` 的父链：

`27bc805 → ...恢复层 12 个提交... → 9369b99 → 122cece → cc2912b`

所以现在**没有遗漏一个"本地但未推送"的 v0.3 提交**。

并行的 `integration/path-a-information-place` 仍停在 `27bc805`，没有跟着产生新提交。因此目前没有发现并行方偷偷越过 `cc2912b` 再推进的新动作。

---

## 2. 但实验状态比"Human Freeze Gate"复杂得多

这里是当前最容易混淆的地方。

`27bc805` 之前已经存在并被继承的 Phase C File-side工作包括：

* A1 `CarrierSQLite` 已实现
* 真实 Carrier Conformance **10/10 PASS**
* Baseline A：SMALL **5/5 VALID**
* MEDIUM **5/5 VALID**
* B1–B9、B12–B14 已有有效结果
* P8 F1–F9 已执行，G2 = PASS
* 放大系数 B10/B11 曾暴露测量定义问题，之后又有 D-A/D-B/D-C 校准结果
* A1 过程中真实抓到并修复了两个工程缺陷：`sqlite3_finalize` 双重释放、`latestRevision` 非确定排序

也就是说：

> **CCVS-01 Phase B 已冻结，Phase C File-side 已经执行过。**

但是：

> **Unified File + Session 的 U-2 尚未开始。**

因此现在"Human Review / Freeze Gate"指的是 **UA v0.3 的 Unified Carrier Contract 冻结门**，不是整个 CCVS-01 重新停在 Phase C 之前。

这一点我认为应该保留，而且应该在状态文档里写得更锋利，否则下一轮 Agent 很容易把两条门混成一条。

---

# 3. 对 UA v0.3 设计的重新审核

我的判断：

> **总体方向正确，不需要重新设计。**
>
> 但我不建议原样 Freeze；有三个语义精度点值得在冻结前修一下，另外有两个实验已经暴露出来的工程约束必须提升为 U-2 的硬检查项。

### A. `UA-P7` 目前写得稍微过头

现在的表达是：

> Layer ① writes already need no concurrency protocol beyond S1-S6/R1-R6.

这句话容易被读成：

> Information/Relation 参与的复合操作完全不需要额外并发保障。

这是不准确的。

Phase 2 的 immutable + first-write-wins 确实意味着：

**Information 本身不需要"更新冲突"语义。**

但一个 Carrier operation 可能同时涉及：

`Information + Representation + CarrierRecord + mapping + provenance + index`

这时仍然必须依靠 **MA-3 atomicity** 防止半提交。

所以我建议冻结语义改成：

> Layer ① does not require a new semantic concurrency contract; carrier-level operations that span semantic persistence and carrier state remain governed by CC-MA atomicity and consistency requirements.

这就不会把"语义对象不变"误写成"复合事务不需要协调"。

---

### B. `I20 No identity duplication` 必须收窄

现在：

> concurrency never mints a second identity for the same object

这里的"same object"还不够严格。

因为当前语义本来就允许：

* 同一内容在不同来源形成不同 Information；
* 同一 carrier 的不同 representation 有不同 Representation Identity；
* 同一个文件经过某些明确操作产生新 Information 也是合法的。

所以 I20 最好明确成：

> **No unintended duplicate Carrier identity or conflicting duplicate registration for one logical Carrier instance.**

也就是约束：

**同一个 Carrier 被并发操作错误地注册成两个 Carrier。**

而不是约束"相同内容/相同对象概念不能出现两个 InformationID"。

这和现有 Information Identity 规则完全一致。

---

### C. "One unified concurrency model"应该冻结为"一个契约"，不是"一套算法"

v0.3 大方向已经写得比较好：

> internal storage characteristics may differ

我建议再明确一个词：

> **ONE unified concurrency contract / guarantees**

而不是暗示所有操作必须采用同一种物理机制。

例如：

* File revision conflict 可以用 compare-and-swap；
* Session sequence 可以用原子 sequence allocation；
* SQLite transaction 可以承担部分 atomicity；
* index rebuild 可以用 build-version + swap。

这些物理机制可以不同。

统一的是：

**identity / version / provenance / transaction / conflict / recovery / index isolation 的语义保证。**

这个区别很重要，否则 U-2 实现阶段很容易为了"统一"反而造一个过度抽象的 Universal Lock Manager。

---

# 4. 真正值得现在吸收进设计的是 P8 的 F7

这里反而是本轮实验给出的最重要设计反馈之一。

P8 F7：

* authority 本身没有丢；
* FTS 可以 rebuild；
* 但是**原始 searchable text 不在 authority 中**；
* 因此重建只能恢复 identity coverage，不能恢复完整 searchable-content coverage。

而 UA v0.3 的 CC-7 已经写了：

> rebuild-compare = identity coverage **AND searchable-content coverage**

这是正确的，但现在还只是"合同要求"。

我建议把它提升成 U-2 的明确硬门：

> **任何被声明为 derived search index 的系统，都必须在 authority 中保存足以重建该 index 所承诺的 searchable source content；否则只能声明为不完整可重建能力，不得把普通 index rebuild 判定为完整 PASS。**

也就是说：

**A1 现在的 F7 是允许通过的 PB v1.2 File-side baseline 结果；但不能直接成为 Unified U-A 的最终实现模板。**

这是实验结果对设计的真实反哺。

---

# 5. P8 的 F1 也值得把"PASS"的含义写得更清楚

F1 出现：

* revision row 已存在；
* representation row 不存在；
* orphan entity file 存在；
* integrity = `ISSUES`;
* 最终判定仍为 `PASS`。

按照现在协议，这是可以解释的：因为这是**预注册的 crash boundary 结果**，不是 silent corruption。

但从研究记录可读性来看，单写 `PASS` 容易让后来的 Agent 误以为"最终 integrity 必须 CLEAN"。

建议以后使用：

> `PASS (expected detached/orphan state, explicitly detected)`

或者在 verdict schema 中保持 `PASS`，但强制增加：

`ExpectedPostCrashState = DETACHED_OR_ORPHAN_DETECTED`

这样研究证据会更稳。

---

# 6. 还有一个实际的"状态账本问题"

`SESSION_LOG_20261006.md` 现在已经出现明显的历史残留。

例如前面第 14 项还写：

> benchmark protocol authored but not executed

后面第 26–29 项已经明确写：

> Phase C authorized → A1 implemented → Baseline A executed → P8 executed

另外 Key Documents 里还出现：

> `CCVS-01 U-1 addendum protocol v0.2 (CURRENT)`

但真正当前的是 **v0.3**。

这不是语义问题，而是**Research State hygiene 问题**。

我建议下一次提交不要改设计，而是做一次纯状态整顿：

`historical narrative` 保留，
`Current state / Current key documents / Next legal transition` 三处必须唯一、无冲突。

否则下一 Agent 很容易从状态账本而不是最新文件判断门位，然后再次把"Phase C File-side"与"U-2 Unified"混起来。

---

# 7. 现在真正的下一步，我认为已经非常明确

不是去做新的数据库横向比较。

而是：

### **先冻结 UA v0.3，然后进入 U-2。**

U-2 的第一份东西应该是：

**U-A Unified Minimal composition manifest**

它必须在 A1 基础上补齐：

`FILE + SESSION + mapping + provenance + CC-MA`

尤其把目前还缺失的：

* MA-3 atomicity
* MA-4 complete provenance commit
* MA-6 concurrent sequence allocation
* MA-7 operation identity / idempotent retry
* MA-9 concurrent index invalidation/rebuild
* MA-10 snapshot/version consistency

全部写成**可验证机制**，而不是设计口号。

然后才运行第一轮 Unified validation。

而且我建议第一轮不要再开 Git/CAS/PostgreSQL/MinIO 之类的横向大比较。先回答一个更基础的问题：

> **"Unified Carrier 本身，在最小 SQLite + POSIX substrate 上，能否把 File 与 Session 真正放进一个 Carrier contract，并经得住 Multi-Agent Research Day？"**

这一关通过以后，才值得比较更复杂的 carrier topology。

---

## 最终意见

**设计主线：接受。无需重新架构。**

但我会在 Human Freeze 前要求完成这五个精修：

1. `UA-P7` 把"无新的语义并发契约"与"复合操作仍需 atomicity"分开。
2. `I20` 收窄为"无意的 Carrier identity duplication / conflicting registration"。
3. "One unified concurrency model"明确为**统一 contract/guarantees，不是统一物理算法**。
4. 把 P8 F7 暴露的"authority 无法恢复 searchable content"提升为 **U-A 必过的 rebuild completeness gate**。
5. 清理 `SESSION_LOG` 的历史残留状态，保证 Current / Key Documents / Next Transition 单一一致。

**推送方面目前不需要再操作。** 远端 `codex/research-recovery-layer-v0.1` 已经与 `cc2912b` 完全一致；`integration/path-a-information-place` 仍停在 `27bc805`，没有新并行动作；`main` 仍是 `0a23fb0`。现在最合适的是把上述五点作为 **UA v0.3 Freeze Review 意见**，而不是再造一个 v0.4 或偷偷进入 U-2。

---

## Registered consequences

```text
FR-1  UA v0.3 design mainline ACCEPTED. No re-architecture, no
      Canonical Logical Model, no Information/Relation redesign. UA
      v0.3 is NOT frozen as-is: the freeze gate remains OPEN with the
      five conditions below. No UA v0.4 is produced now; the
      conditions are incorporated into the frozen text (UA v1.0) at
      the Human freeze ruling, or per the ruling's instruction.

FR-2  FREEZE CONDITION 1 (UA-P7 rewording): split "no new semantic
      concurrency contract" from "compound operations still need
      coordination". Frozen text: "Layer ① does not require a new
      semantic concurrency contract; carrier-level operations that
      span semantic persistence and carrier state remain governed by
      CC-MA atomicity and consistency requirements." (MA-4 covers the
      compound case: Information + Representation + CarrierRecord +
      mapping + provenance + index.)

FR-3  FREEZE CONDITION 2 (I20 narrowed): "No unintended duplicate
      Carrier identity or conflicting duplicate registration for one
      logical Carrier instance." The bound constrains the same logical
      Carrier being wrongly registered as two Carriers under concurrent
      operation — NOT the legitimate existence of distinct
      InformationIDs formed from the same content, distinct
      Representation Identities per revision, or legitimately new
      Informations from explicit operations. Fully consistent with
      existing Information Identity rules.

FR-4  FREEZE CONDITION 3 (unified concurrency = one CONTRACT, not one
      ALGORITHM): what is unified is the semantic guarantees
      (identity / version / provenance / transaction / conflict /
      recovery / index isolation). Physical mechanisms may differ per
      family and operation (compare-and-swap for file revisions,
      atomic sequence allocation for sessions, SQLite transactions for
      partial atomicity, build-version + swap for index rebuild). This
      explicitly forbids an over-abstracted Universal Lock Manager in
      U-2.

FR-5  FREEZE CONDITION 4 (rebuild completeness gate, from P8 F7):
      promoted to an explicit U-2/U-A hard gate — any system declared
      as a derived search index must hold, IN AUTHORITY, searchable
      source content sufficient to rebuild the index's promised
      coverage; otherwise it may only declare an INCOMPLETE rebuild
      capability and a normal index rebuild must not be judged full
      PASS. A1's F7 remains a valid PB v1.2 File-side baseline result
      and must not become the U-A final implementation template.

FR-6  FREEZE CONDITION 5 (state hygiene): historical narrative in the
      session log is retained; the three canonical sections (Current
      state / Current key documents / Next legal transition) are made
      unique and conflict-free; the Phase-C-executed vs U-2-not-started
      distinction is written sharply. Done in the same commit as this
      registration. (Fixes: v0.2 "(CURRENT)" residue → SUPERSEDED;
      top-block gate sharpening; hygiene note.)

FR-7  P8 F1 verdict semantics: standing recording requirement for all
      FUTURE crash/recovery records — a pre-registered crash-boundary
      PASS should be recorded as
      "PASS (expected detached/orphan state, explicitly detected)" or
      carry ExpectedPostCrashState = DETACHED_OR_ORPHAN_DETECTED in the
      verdict schema. The existing P8 record is NOT retroactively
      modified.

FR-8  Next step AFTER the freeze ruling: U-A Unified Minimal
      composition manifest (FILE + SESSION + mapping + provenance +
      CC-MA on the A1 base), turning MA-3/MA-4/MA-6/MA-7/MA-9/MA-10
      into verifiable mechanisms, then the first Unified validation
      round answering: "Can the Unified Carrier itself, on the minimal
      SQLite + POSIX substrate, truly put File and Session into one
      Carrier contract and withstand Multi-Agent Research Day?" NO
      horizontal carrier-topology comparison in round one.

FR-9  U-2 remains NOT STARTED / NOT AUTHORIZED until the freeze ruling
      and its own separate authorization.
```
