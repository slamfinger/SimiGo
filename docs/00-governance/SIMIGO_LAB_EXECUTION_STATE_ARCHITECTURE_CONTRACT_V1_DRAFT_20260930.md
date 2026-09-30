# Execution State Architecture Contract — v1.0 (Synthesis Draft)

日期：2026-09-30  
状态：`CONTRACT v1.0 / REGISTERED / UPSTREAM SEMANTIC REFERENCE`  
Synthesis basis：opening registration `62142ad`（AC-1…AC-4，三大纪律）  
Source state：`62142ad`  
Route authority：`SIMIGO_LAB_EXECUTION_STATE_RESEARCH_ROUTE_REDEFINITION_20260929.md`
——NEXT SYNTHESIS GATE（六问全部在本文收口）

> **本契约是合成，不是重新发明。** 每条语义陈述（§1–§4 标注 [源]）可追溯
> 已登记工件；合成中未发现任何需要偏离登记语义的冲突；全部已知缺口保持
> open（§5），无一被本契约静默解决。登记后本文件成为上游语义参照：代码/
> 登记行为与本文的双向偏离构成 contract-change 信号（§6）。
>
> **Stability ≠ immutability**：修订只能经 contract gate（S2 信号 + S6 面）。

---

## §1 AC-1 Semantic Core — 状态本体（route Q2/Q3 收口）

### §1.1 状态分类总表（D/R/P/O/T）

| 概念 | 分类 | 登记来源 | 契约陈述 |
|---|---|---|---|
| `ExecutionID`（opaque rawValue） | **D** | Phase B §B1；`ExecutionContinuityContract:8` | Execution 身份的唯一权威；backend 不得派生、重定义或合成身份 |
| `ExecutionLineage`（root / parent） | **D** | Phase B §B1；contract:20 | 分支树的语义 linkage；root/parent 是语义元数据，不是替代身份键 |
| `ExecutionPosition`（Int64） | **D** | Phase B §B1/B3；contract:31 | 逻辑时间线的 canonical position；仅由 `continueExecution` 以精确 +1 推进【route Q2 答：canonical source = handle 上的 ExecutionPosition，runtime 独占】 |
| `ExecutionContinuation`（nextInput / continuationID） | **D（现行 Lab 契约）** | Phase B §B2；contract:44 | nextInput 保持 D；transcript-derived 替代**未被假定等价**（open point OP-1） |
| `ExecutionBranchLifecycle`（attached/active/restored/discarded） | **D** | Phase B §B7；contract:59 | Runtime 生命周期；discarded = 终态 tombstone |
| coordinator `handles` | R | Phase B §B3 处置表 | D 的进程内投影 |
| lifecycle records / sequence | O（History） | Phase B §B3 | replay/观测数据；**非最小 D**【route Q3 答：必须 durable 的演化 = snapshot 字段 + tombstone closure；事件史不是必需】 |
| representation history | R + P | Phase B §B3 | restore 加速器，非语义状态 |
| `RepresentationRef` | **P** | Phase B §B4；route Q4 答 | P 层 locator/claim；**不是** Execution semantic state，永不为 handle 字段 |
| binding relation（executionID / ref / boundPositionAtBind / binding state / generation） | separately typed relation | Phase B §B4；route Q5 答 | `ExecutionBindingRegistry` 保持 execution-scoped runtime relation；append 语义属 runtime relation 行为，不得读作 durable event log |
| `runtimeAddress` | R | Phase B §B4 | 永非 durable semantic addressing |
| `boundAt` | O | Phase B §B4 | relation 历史 |
| pool stats / recency | O + T | Phase B §B3 | 策略与观测 |
| in-flight physical use | T | Phase B §B5 | 瞬态保护；驱逐延迟 |
| representation payloads（如 token prefix） | **P** | Phase C §C1 | 对 Runtime opaque；backend 策略自持 |
| 外部 server native cache / slot state | T | Phase C §C1；Round 1 §A2 | server 所有；策略性忽略 |
| `BackendMemoryObservation` | R（观测面） | `RuntimeBackendContract:20` | INV-3 对账输入；解释权在 Runtime；该 R 分类由契约自述的 passive observation 语义推导 |

### §1.2 Semantic Core 三定律

```text
SC-1  语义唯一权威 = ExecutionContinuityCoordinator（经 E1 契约）。
      任何其他类型（backend / adapter / store）不得创建、赋值或改写
      identity / lineage / position / continuation 语义。
      [Phase C §3.2 sovereignty；C-4/C-9 信号]
SC-2  D 的最小持久对象 = Execution Semantic Snapshot：
      id + lineage.root + lineage.parent + position +
      continuation.nextInput + continuation.continuationID + lifecycle；
      recoverable set = snapshots + required lineage tombstones +
      optional separately typed representation binding relations。
      [Phase B §2；登记契约]
SC-3  语义演化仅经四个登记事务窗口（fork：物理 derive 先行；restore：
      物理 restore 先行；discard：物理 release 先行；bind：restore 后
      记录）。窗口之外的物理 I/O 与语义 commit 无因果。
      [coordinator:169-271；Phase B §B6]
```

---

## §2 AC-2 Identity & Continuity — 何时仍是「同一个 Execution State」（route Q1 收口）

### §2.1 核心法则

```text
SAME Execution State ⟺ 以下五元组保持为 Runtime 独占的语义字段，其值只能经登记生命周期转移（create / continue / fork / restore / reattach / discard）演化；
      identity 锚 = ExecutionID；lineage 为其不可变元数据；representation 变化从不直接写这些字段。
      且 representation 侧仅发生已登记的显式结果：
      reattach / rematerializationRequired / recompute / fail-closed

NEW Execution State ⟺ 仅由 create() 或 fork() 以新的 ExecutionID 产生。
```

推论（全部有登记来源）：

```text
IC-1  representation 消失、损坏、换 backend、跨进程——都【不】产生新
      State；只改变 recoverable-set 的显式结果。State S 的 representation
      A 丢失而 B 可用或可重算：S 仍是 S。
      [Phase B §B5 矩阵；Round 1 §A8 闭环]
IC-2  身份跨 backend / 跨格式不变：ExecutionID 不含任何 backend、格式或
      物理语义；backend 差异只能显式降级 representation，不能触及五元组。
      [Phase C §C8；contract target 零模型依赖]
IC-3  discarded = 终态 tombstone：身份保留（reservation）、lineage 可达性
      保留（tombstone closure 为强制条件）；不是 active/restored，不可
      静默复用；collection 须显式 GC 规则且保护存活执行的引用。
      [Phase B §B1/B7；condition 1]
IC-4  重复创建对 active 或 reserved-discarded ID fail closed。
      [Phase B §B1]
IC-5  continuation.nextInput 是 D 的组成部分；transcript-derived recovery
      **不得**假定等价——重新分类前必须通过 bounded equivalence 计划
      （同 execution ID/lineage、同 position、同渲染/分词、同生成身份、
      显式失败路径）。[Phase B §B2；condition 2 —— open point OP-1]
```

### §2.2 判定示例（契约化用户场景）

```text
State S @ position p，representation A 已绑定：
  A 丢失，recompute 可能          → same State S，结果 = recompute
  A 丢失，artifact B 存在且 claim 验证通过 → same State S，结果 = reattach
  A 丢失，无任何 representation   → same State S，结果 =
                                    rematerializationRequired
  对 S 的语义字段做任何改写        → 不是「S 的变化」，是 C-4/C-11 违约
  以新 ID create/fork             → new State（与 S 的关系由 lineage 表达）
```

---

## §3 AC-3 Representation Boundary — 语义结果与一致性（route Q4/Q5/Q6 收口）

### §3.1 关系法则

```text
RB-1  Execution State ──(RepresentationRef / separately typed binding
      relation)──▶ Physical Representation。RepresentationRef 与 binding
      relation 永不进入五元组。【Phase B §B4；route Q4/Q5】
RB-2  binding relation 字段 = executionID（relation key，非新身份权威）/
      representation key·ref（P locator/claim）/ boundPositionAtBind /
      binding state / relation generation；runtimeAddress 恒 R。
      [Phase B §B4]
```

### §3.2 四态结果法则（representation 侧的唯一合法出口）

```text
RB-3  representation available 且 claim/position 验证通过 → reattach
RB-4  namespace / token count / chain hash / position / payload 类型任何
      失配 → loud fail；隔离候选；recompute（禁止静默绑定或静默修复）
RB-5  artifact 缺失 / 不可读 / 无 binding → rematerializationRequired 或
      recompute（语义结果显式化）
RB-6  歧义（同位置多 claim 等）→ fail closed 或显式选择，禁止静默择一
RB-7  logical position 恒为权威：backend bound-position ≠ logical →
      loud fail；stale binding 一律无效；recompute 是永远合法的回退。
      【route Q6 答：logical/physical 一致性边界 = 位置权威在 Runtime，
      物理失配显式化】[Phase B §B5/B6；ResolutionState 四态]
```

### §3.3 能力边界原则

```text
RB-8  Seam 是能力边界，不是强制组件清单：backend 按真实物理所有权接入
      E3（representation 策略）与/或 B1（物化/内存对账）；server-owned
      物理生命周期的 backend 可不行使 B1；client-side 物理状态的 backend
      预期行使 B1。【Round 1 登记；seam stability §S4】
```

---

## §4 AC-4 Backend Independence — 准入标准（standing）

一个 backend 被判定为「实现 SimiGo Backend Independence」当且仅当全部满足：

```text
BI-1  经 E3 实现 representation capability；且当其拥有进程内物理资源时
      经 B1 提供物化/内存对账（RB-8）。
BI-2  不拥有、不写、不派生 Execution 语义（SC-1；C-4 恒否）。
BI-3  表示侧差异只经 RB-3…RB-7 显式结果表达；无静默换语义。
BI-4  在同一 conformance battery 下满足 §2 same-State 判据（语义断言
      零分叉——不得为该 backend 写第二套语义期望）。
BI-5  其 engineering 轮次遵守 M-1…M-5 与 evidence-source-state 纪律；
      证据绑定 commit-hash 级源码状态。
```

**适用域**：Round 1（LLAMAServerExecutionStateAdapter 组合体）是本标准的
第一个判例，不是定义的普遍性证明。未来 backend 的准入各自走 activation
gate；本标准不预证任何未测 backend。

---

## §5 Open points ledger（随契约携带，不关闭）

| OP | 内容 | 登记来源 | 解决路径 |
|---|---|---|---|
| OP-1 | transcript-derived continuation 等价性（nextInput 重分类前置条件） | Phase B §B2 / condition 2 | bounded equivalence 计划 → 独立 review |
| OP-2 | durable ExecutionID allocator / 跨重启 reservation | Phase B gap #2；G-7 | 独立 engineering gate；契约中性 |
| OP-3 | durable store 组合（G-10） | Phase B gap #1；S3 触发点 | 消费 Phase B 边界；激活时轴 d 再检验为第一审计项 |
| OP-4 | contract-level cancellation surface（G-9） | Phase C G-9 | containment 先证；超出来即 contract gate |
| OP-5 | representation content claim 政策（G-6：per-backend claim 已可local；统一 digest 入契约即触发） | Phase B gap #6；condition 3 | per-backend 先行；统一化须 contract gate |
| OP-6 | 工程 gaps G-1/G-2/G-3/G-4/G-5(L-1)/G-8（全部 LOCAL-FIXABLE，S3 地图） | Phase B/C | 各自 engineering gate；禁止顺手修复 |
| OP-7 | PALACE 接口 | 04c608e 并线事实 | 消费前显式 bridging registration |

---

## §6 Drift detection integration（v1.0 登记后生效）

```text
C-13（新增信号） 本契约文本与代码/登记行为的任何双向偏离 = contract-
      change 信号，走独立 contract gate。当前检测机制为程序性：每个 gate
      的 review checklist 对照项；自动化检测归 productization P-2。
S6 standing 面照常适用：battery 复跑绑 hash、S2 十二信号、M-1…M-5、
sovereignty 扫描、inherited-conditions ledger、PALACE 隔离检查。
```

---

## §7 Non-claims

```text
本契约不是：storage / persistence format / API / protocol 规格
本契约不声称：immutability（修订经 contract gate）、universal backend
portability、production readiness、performance 结论
本契约不解决：§5 任一 open point
```

## §8 Evidence hierarchy

```text
登记工件（Phase A/B/C、Round 1、seam stability、route）
    ↓ 逐条引用
本契约 §1–§4（合成，零新增语义）
    ↓ 登记
v1.0 = 上游语义参照（双向 drift 检测生效）
```
