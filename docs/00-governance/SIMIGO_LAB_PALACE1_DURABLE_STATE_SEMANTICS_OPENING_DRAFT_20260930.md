# PALACE-1 Durable State Semantics Opening Draft

日期：2026-09-30  
状态：`DEFERRED / RETAINED AS SEMANTIC HYPOTHESIS SCAFFOLD`  
**降级记录（2026-09-30 第二层判断）**：研究顺序提前——D1–D4 自 Contract
推导而非自物理工程事实；文中全部 CONFIRMED/DEPENDENT 判定降级为
**semantic hypothesis**，不得视为工程事实（尤其「D4 语义答案 CONFIRMED」
与「各场景 SAME = CONFIRMED」——架构契约约束 ≠ 已证明的工程能力）。
后继 = Physical Reality Audit（磁盘实物 → 代码路径 → 删除损失 → 逼出
PALACE 边界）。本文件保留 D1–D4 问题框架与 open points 作 scaffold。  
上游语义参照：Execution State Architecture Contract v1.0（`REGISTERED /
UPSTREAM REFERENCE`，源状态 `da2c8e8`）  
Gate：`PALACE1_DURABLE_STATE_SEMANTICS_OPENING`（definition gate only）  
性质：participant proposal——不实现、不选库、不解决 OP/G

```text
observed code fact ≠ inferred durable semantics ≠ selected implementation
```

## 0. §0 并发核验结果

```text
git fetch / LOCAL = REMOTE      = da2c8e8 ✓
worktree clean                  = 0 项 ✓
da2c8e8 之后并发 commit         = 无 ✓
contract 文件历史               = a1e2e28（synthesis）+ 5ce88d0（登记
                                  strengthening 并入）——此后零变更，
                                  OP-1…OP-7 / G-1…G-10 台账无未登记漂移 ✓
六份文档在位并核验              = NEXT_SESSION_ENTRY / RESEARCH_STATE /
                                  Contract v1.0 / Contract registration /
                                  PALACE-1 Phase B registration（minimal
                                  durable unit audit）/ Seam Stability
                                  registration ✓
Contract v1.0 = UPSTREAM REFERENCE ✓
→ 四项验收条件全部满足，无 STOP 条件
```

## 1. 研究问题（固定）

> 当 Runtime、进程和 Physical Representation 都可能消失时，什么最小语义
> 仍足以使恢复后的对象被称为同一个 Execution State？

本 opening 只做 definition：确定 Contract v1.0 已经决定了什么、既有证据
决定了什么、什么真正 open、什么必须进入下一阶段研究。

## 2. D1 — Durable Minimum（五分类）

对 opening 指定的七项 + 恢复元数据逐项分类：

| 项 | 分类 | 状态 | 依据 |
|---|---|---|---|
| `ExecutionID` | **MUST BE DURABLE** | CONFIRMED（身份锚，IC-3/IC-4） | Phase B §B1；Contract §2。durable allocator 机制 = DEPENDENT（OP-2/G-7）——ID 必须持久 ≠ 分配器已存在 |
| `lineage.root / parent` | **MUST BE DURABLE** | CONFIRMED | Phase B condition 1：tombstone closure 强制，存活子代的 root/parent 至少以 tombstone 可解析 |
| `position` | **MUST BE DURABLE** | CONFIRMED | route Q2：canonical 逻辑位置，Runtime 独占 |
| `continuation.nextInput` | **MUST BE DURABLE（现行契约）** | CONFIRMED as registered；**重分类为 RECONSTRUCTABLE = OPEN（OP-1）** | Phase B §B2：现行契约无 transcript 权威；重分类前置条件 = bounded equivalence 计划 |
| `continuation.continuationID` | **MUST BE DURABLE** | CONFIRMED | Phase B §B2 |
| `lifecycle` | **MUST BE DURABLE** | CONFIRMED | discarded = 终态 tombstone，必须跨进程存在，否则 reservation 失效 |
| transcript | OBSERVATIONAL（现行契约无 durable 地位） | OPEN（其能否成为 continuation 源 = OP-1，不关闭） | Phase B §B2；产品侧 transcript 自述仅为 UI 展示层 |
| recovery metadata 分解： | | | |
| — tombstone / lineage closure data | **MUST BE DURABLE** | CONFIRMED | 同 condition 1；closure 不得依赖非 durable 数据 |
| — binding relations（separately typed） | OPTIONAL DURABLE | CONFIRMED | Phase B recoverable set 的登记可选成分；缺省结果 = rematerializationRequired |
| — representation content claims | PHYSICAL-ONLY | DEPENDENT（OP-5/condition 3） | 仅 reattach 路径需要；per-backend claim 先行 |

**D1 结论**：MUST BE DURABLE 集 = Contract SC-2 七字段 + tombstone closure
data——**零新增语义**。「能从别处推导」不改变 durable 地位（见 D2 原则）。

## 3. D2 — Reconstruction Boundary

三层链与可重建性：

```text
Execution Semantic Snapshot (D)  —— 不可由下层重建：它就是身份锚
        ↓ 恢复时实例化
Runtime Binding (R)              —— 完全可重建（进程内投影，丢失无语义影响）
        ↓ 消费
Physical Representation (P)      —— 可重建（recompute / rematerialization）
```

「能重新生成 ≠ 可以不持久化」的两处具体落点：

```text
(a) nextInput 理论上可由 transcript 推导——OP-1 未决前其 D 地位不变；
    推导可能性不构成降级证据（condition 2 要求 bounded equivalence 计划）。
(b) tombstone closure 理论上可由 lifecycle history 重建——但 history 是
    O 层（非 durable 保证）；closure 若依赖它，保证即失效。closure 必须
    独立持久化。
```

**D2 结论**：可重建集 = R 层全部 + P 屄全部 + 显式降级结果；不可重建集 =
snapshot 本体 + tombstone closure。CONFIRMED。

## 4. D3 — SAME / NEW / OPEN 场景审计

以 Contract §2（identity 锚 = ExecutionID；五字段 Runtime 独占，值仅经
登记生命周期转移演化）为上游法则：

| 场景 | 判定 | 依据 | 状态 |
|---|---|---|---|
| restore（进程内回捕获位） | **SAME** | 登记转移；lifecycle = .restored | CONFIRMED |
| reattach | **SAME** | 登记转移 | CONFIRMED |
| rematerialization | **SAME** | IC-1 / RB-5 | CONFIRMED |
| recompute | **SAME** | IC-1 / RB-7 | CONFIRMED |
| backend replacement | **SAME** | IC-2；Round 1 证据 | CONFIRMED |
| representation loss | **SAME** | IC-1 | CONFIRMED |
| reopen（进程重启，自 durable snapshot 恢复） | **SAME（语义层）** | 身份锚 + 五元组经登记转移语义恢复 | 语义 CONFIRMED；**恢复机制 = OPEN**（恢复必须验证什么：snapshot 完整性 / closure 检查 / reservation replay——下一阶段研究对象） |
| recovery 遇 closure 破损（parent/root tombstone 缺失） | **loud fail** | condition 1 + fail-closed 表；不得主张 same-State | CONFIRMED |
| NEW State | 仅 create / fork 新 ExecutionID | Contract §2 | CONFIRMED |
| transcript-derived recovery（无 nextInput 恢复） | **OPEN** | OP-1；无 bounded equivalence 证据不得分类 | OPEN（不关闭） |

## 5. D4 — Representation Disappearance（极端压测）

```text
Runtime 消失 ✗   Process 消失 ✗   Backend 消失 ✗   Physical Representation 消失 ✗
```

仍然留下、足以识别 State 的 = **durable Execution Semantic Snapshot +
tombstone closure data +（若已持久化的）optional binding relations**。

- **语义答案：CONFIRMED**。Contract SC-2/IC-1 已经定义「State 的存在 =
  snapshot 存在」，与四层无关；`Execution State ≠ Physical Representation`
  在最坏情况下于语义层成立——这正是 Contract 需要经受的压测，通过。
- **存在性答案：DEPENDENT**。当前 Lab 无 durable store（OP-3/G-10），恢复
  机制依赖 OP-2（reservation replay）。存在性的工程化 = 下一阶段研究对象，
  本 opening 不引入任何存储技术方案。

## 6. Re-anchoring ledger（重锚定，不解决）

| 项 | 本 opening 的重锚定点 | 状态 |
|---|---|---|
| OP-1 transcript equivalence | D1 transcript 分类；D3 transcript-recovery 场景 | OPEN |
| OP-2 durable identity allocator | D3 reopen 的 reservation replay 依赖 | DEPENDENT |
| G-7 durable identity reservation | 同 OP-2 | DEPENDENT |
| G-10 / OP-3 durable store | D4 存在性依赖 | DEPENDENT |
| RB-1…RB-8 | 恢复必须尊重的表示结果法则（恢复路径不得绕过四态结果） | CONFIRMED-unchanged |
| IC-1…IC-5 | SAME/NEW 法则来源 | CONFIRMED-unchanged |
| Execution Semantic Snapshot | D1 答案的基础 | CONFIRMED-unchanged |

**发现的依赖（登记，不解决）**：D3 reopen 机制 ← OP-2 + G-10；D1
nextInput 重分类 ← OP-1；D4 实证 ← OP-3。无一被本 opening 关闭。

## 7. Prohibitions（逐字写死）

```text
❌ database selection          ❌ SQLite design
❌ KV schema                   ❌ persistence API
❌ remote service              ❌ storage implementation
❌ artifact format             ❌ second backend
❌ performance benchmark       ❌ productization
❌ 以解释关闭任何 OP/G
```

研究对象是 **Durable State Semantics**，不是 Durable Storage Technology。

## 8. 输出分类（CONFIRMED / OPEN / DEPENDENT / UNKNOWN）

```text
CONFIRMED
  D1 durable minimum 集（snapshot 七字段 + tombstone closure data；
  binding relations optional；claims P 层）
  D2 三层可重建边界（含「可再生 ≠ 可不持久化」两落点）
  D3 场景判定：restore / reattach / rematerialization / recompute /
     backend replacement / representation loss / closure 破损 loud fail /
     NEW 来源——全部 SAME/合法
  D4 语义答案（State 的存在 = snapshot 存在，与四层无关）

OPEN
  OP-1：transcript 能否成为 continuation 源；transcript-recovered 对象
        是否 SAME
  reopen 恢复机制研究问题：合格恢复必须验证什么（完整性 / closure /
        reservation replay 的判据集合）

DEPENDENT
  reopen 机制工程化 ← OP-2 + G-10
  durable reattach ← OP-5 / condition 3
  D4 实证（真实持久化演示）← OP-3 / G-10

UNKNOWN
  七字段 snapshot 在全消失恢复下的【充分性】：Phase B 证明的是必要性与
  边界（它是最小 durable unit），「仅凭 snapshot + closure 即可完成
  same-State 恢复」是 PALACE-1 下一阶段必须检验的核心命题——本 opening
  不预答。
```

## 9. 成功标准对照（human 标准）

```text
✔ Contract v1.0 已决定的：CONFIRMED 集（§8）
✔ 既有证据已决定的：同上（Phase B/C、Round 1、seam stability 引用）
✔ 真正 open 的：OP-1 + reopen 机制问题
✔ 下一阶段必研的：snapshot 充分性检验 + 恢复机制定义（UNKNOWN → 研究）
```

达成——D1–D4 未被强行全答，UNKNOWN 被诚实标出。

## 10. Gate sequence

```text
本草案 →（暂停）human 第二层判断 → external review（六项固定：
Contract fidelity / SAME-State law / durable-reconstructable boundary /
representation independence / OP-G integrity / scope discipline）
→ PASS / ACTIVATION_REQUIRED → registration
→ 下一阶段：durable recovery 语义研究（仍非存储实现）
```
