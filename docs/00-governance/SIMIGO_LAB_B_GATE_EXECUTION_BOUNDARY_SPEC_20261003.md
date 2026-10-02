# Gate Spec — B：Execution Boundary Definition（B-Spec Definition 阶段件）

Date: 2026-10-03  
Status: `B-SPEC DEFINED / AWAITING HUMAN AUDIT + FREEZE`  
前置：Phase 0 FROZEN / Phase 1 CLOSED（S1–S6, R1–R6）/ Phase 2
CLOSED / SimiGo FORMAL INTEGRATION PASS / T4 CLOSED（强归因，
任务域有界）  
授权范围：仅本件（Boundary Definition）。B-Design / B-Impl /
B-Execute / Core 改动 = 全部未授权。

## 0. 总原则（human 逐字锁定）

> **不要因为现在已经看到了一个很有吸引力的应用场景，就反过来
> 把它预埋进 InformationCore。**

先定义边界，再决定是否需要扩展。本件全部结论 = 边界定义，
非实现设计；任何 Core 扩展须重开冻结裁定并经 human 显式批准。

## 1. 十问定义（human 十问逐题回答，全部锚定已冻结事实）

### Q1 Execution State 能观察什么

```text
E-观察面 =
  (a) 自身执行上下文：formation facts、自有产物、自有动作序列
      （Execution 私有态，留在 Core 之外）
  (b) InformationStore.fetch 可达的全部已存 Information 值
      （S4 边界面）
  (c) RelationStore.fetch 可达的全部已存 Relation 值
      （R4 边界面）
  (d) 声明环境内、其职责所辖实体的当前状态（观察对象本身）
不可观察：Physical Filing 内部（行/WAL/事务）、其他 Execution
  的私有态、声明环境外的一切
```

### Q2 Execution State 能产生什么

```text
E-产生面 =
  (a) 新 Information（formation：内容 + provenance；identity 经
      机制铸造）——包括对外部变化的观察事实
  (b) 新 Relation（已冻结 R 语义：subject/predicate/object/
      provenance）
  (c) Core 之外的私有工作态（文件/内存/执行策略）
不可产生：对已存 Information/Relation 的修改（first-write-wins，
  S3/R3）；taxonomy/activation/diary 语义；Core 内新类型
```

### Q3 Information Space 保存什么

```text
恰为两个已定稿契约面所定义的值：
  Information（identity/content/provenance/temporal）
  Relation（identity/subject/predicate/object/provenance）
除此之外零：无执行态、无会话态、无索引承诺、无策略、无
  未登记语义
```

### Q4 Physical Space 与 Information Space 如何对应

```text
对应关系 = identity 寻址 + first-write-wins（S3）：
  同一 identity 至多一条物理表示；语义值 ↔ 物理表示按 identity
  一一对应
Physical Space（SQLite/WAL/schema 细节）= 可替换 backend 内部
  （Backend Independence Gate 已证可替换），不属于语义
语义层对 Physical 的全部假设 = identity 寻址 + 逐字存取
```

### Q5 Execution provenance 到什么粒度

```text
粒度裁定方向：per-formation，not per-operation
  每次 Information 形成，provenance 记录该次形成的产生事实：
    producedAt / producedBy / source / sourceTime? /
    position? / extractionMode?
操作序列（动作日志、多步过程）= Execution 私有态，不逐动作
  过边界；跨边界的事实以「形成事件」为单位
```

### Q6 External change 如何定义（可观测定义）

```text
对声明环境内实体 E，取两个观察点 t1 < t2 的表示（含摘要）：
  rep(E, t1) ≠ rep(E, t2)
且 t1→t2 之间本 Execution 未经边界形成过与 E 对应的
  Information
⇒ 该差异 = 一次 external change 观察事实，要素 =
  (E, rep(E,t1), rep(E,t2), observer, observedAt)
该观察事实本身 = 候选 Information 形成材料；是否形成 =
  Execution 策略（边界不自动摄取）
「external」判据 = 变化的 formation provenance 不在本
  Execution 的边界写入之内
```

### Q7 before / after 是否属于 Information 变化事实

```text
不是。frozen 语义下 Information 不可变（A1）——「Information
变化」是范畴错误；变化的是外部实体相对已存观察的状态。

边界定义下的正确表达：
  before = 对 E 在 t1 的观察（已存 ⇒ 直接引用；
           未存 ⇒ 先形成 before-state Information）
  after  = 对 E 在 t2 的观察 = 新 Information 形成事件
  二者关系 = Relation（R1–R6 语义内，如 observed-change-of /
           supersedes），subject/object 为两端 Information 的
           identity
⇒ 候选闭环（hash change → before/after → external change →
  「Information update」）在零 Core 修改下即可表达：
  after = 新 Information；change = Relation；无 update 语义
```

### Q8 哪些东西必须留在 Core 之外

```text
动作日志/会话态、观察策略与触发机制、hash 计算与文件监视
实现、retrieval/query/ranking、taxonomy/activation/diary、
palace、WAL/事务内部、MemoryCore（Adaptive Memory Budget）、
ExecutionState contract 语义扩展、通用超级 Store、一切未登记
语义
```

### Q9 最小验证问题（候选研究方向 R-B1 的验证核）

```text
候选 R-B1（登记为候选，非冻结设计）：
  外部实体 E 状态变化 → 执行者观察 before/after → 经边界形成
  after-state Information + change Relation → fresh cold-start
  执行者仅经边界取回，回答「E 自上次观察以来发生了什么」

最小验证问题：
  cold-start executor 能否仅通过 Information boundary 正确回答
  上述问题——且正确性依赖 before/after Information 对（C-N
  空边界对照下不可答）？
验证框架继承 C-E/C-N 归因逻辑（T4 同构）
```

### Q10 哪些问题明确不进入本 Gate

```text
R-B1 的实现与实验、T4 实验逻辑延伸、taxonomy/diary/activation
裁定、palace 重建、SQLite 终局裁定、MemoryCore、B-Design/
B-Impl/B-Execute、修改任何已冻结语义、（b2) 独立包拆分
```

## 2. 候选研究方向登记（R-B1，非冻结）

human 候选环（file → hash change → before/after → external
change → 「Information update」）在本边界定义下的表达：

```text
零 Core 修改：
  before-state = 既有 Information（或新形成）
  after-state  = 新 Information 形成（external change 观察事实）
  change       = Relation（observed-change-of）
无「Information update」语义——immutability + Relation 已足够
```

该候选是否立项 = Boundary Audit + Human Freeze 后的
B-Design 决策。

## 3. Boundary Audit 输入清单（下一阶段）

1. 本件 §1 十问定义逐条审计
2. R-B1 候选与 Q7 表达的完整性/充分性审计
3. 与 SimiGo 既有三 contract（ExecutionState/Continuity/
   RuntimeBackend）的平行性核查（零吸收声明复核）
4. 负空间清单复核

## 4. 推进

```text
B-Spec Definition（本件）→ Boundary Audit（human）→ Human
Freeze → B-Design 是否开启（另行裁定）
```
