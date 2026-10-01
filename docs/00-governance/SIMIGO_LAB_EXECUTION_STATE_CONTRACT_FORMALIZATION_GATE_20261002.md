# Execution State Contract Formalization Gate — 2026-10-02

日期：2026-10-02
状态：`CONTRACT GATE OPENED / DRAFT DELIVERED / ACCEPTANCE AWAITING
HUMAN`
任务令：human 2026-10-02（不立即升格两层模型为正式 Contract；先开
一道很窄的 Contract Gate 做契约化审查；只做一个文档，九节结构；
之后停在验收门——不实现代码、不改产品仓、不跑模型）
定位：从「研究抽象」进入「工程契约」阶段的标准转换审查。目标不是
证明理论，而是回答：**当前已获实验支持并经 G-δR 形式化的语义，哪些
可以进入 SimiGo 正式 Contract；哪些必须保留为 research-level
interpretation。**

证据基线（本契约的全部实验依据）：P7-1 bounded cross-backend
support（98dbed7）→ G-δ necessity/carrier-dependent compensation
（659ebf8）→ Closure Revision ACCEPTED（69a8866）→ G-δR
FORMALIZATION_SUFFICIENT + 附录 A/B/C（3ecb22f）。

---

## 1. Contract scope（契约范围）

**冻结四类内容**：

```text
Execution State Contract
│
├── 1. Semantic relations          I / P / A / C（含 Role 分解，
│                                    G-δR 附录 A）
├── 2. Required invariants         identity / position / anchor /
│                                    continuation（INV-XB 族）
├── 3. Lifecycle obligations       fork / restore / continue /
│                                    discard / release
└── 4. Representation boundary     backend-native representation
                                     声明面 = Σ_R / C_R / Inv_R /
                                     Rules_R
```

**明确排除（不得写入 Contract）**：

- 「I/P/A/C 已被证明是数学最小集」（minimality 未证明，且已
  representation-aware 化）；
- 任何具体 backend 的 representation 实例（MLX/llama 的字段布局）；
- ρ_L* / ρ_M* 的实现细节（它们是已注册表示声明的**内容示例**，
  非契约条款）；
- 「KV cache 就是/不是 Execution State」类 backend-specific 判断；
- 性能指标（D8 边界继承）。

**与前序在案契约的关系**：Execution State Architecture Contract
v1.0（20260930，UPSTREAM REFERENCE）为本契约的**前驱参照**——其
semantic core/lifecycle 章节与本契约 Semantic Contract 相容；其
representation boundary 章节由本契约的两层定义（G-δR）精化。冲突
时以本契约（证据后置版）为准，v1.0 保留为历史参照。

## 2. Semantic Contract（语义契约——SimiGo 长期稳定的部分）

```text
Execution State 必须保持四条语义关系：
  I  Identity      ——状态属于哪个模型/哪个执行谱系（Role: I-1/I-2）
  P  Position      ——计算进度与续算落点（Role: P-1/P-2/P-3）
  A  Anchor        ——状态位置上的内容-语义对应（Role: A-1）
  C  Continuation  ——未来输入的合法接续关系（Role: C-1）

以及预注册 continuation invariant（INV-XB 族，P7-0 §4）：
  INV-I / INV-P / INV-A / INV-C
```

义务表述为**语义保持义务**，不指涉任何字段：任何声称持有
Execution State 的组件，必须使其状态记录/载体满足四关系语义，且
经 lifecycle 操作后 INV-XB 可断言。语义成员资格判据（G-δR §1.4）
为修正机制：关系成员资格可经 closure revision gate 修订，本契约
版本号随之递增。

## 3. Representation Contract（表示契约——backend 的声明义务）

任何 backend R 声称承载 Execution State，必须**声明**：

```text
Σ_R     record schema（状态记录字段集）
C_R     carrier（物理载体及其语义——载体是什么、不是什么）
Inv_R   representation invariant（良构 record 上恒立的确定性事实）
Rules_R 推导规则封闭集（实验前枚举冻结；含显式缺席规则）
```

并满足：

> **representation 可以变化，但不得改变 semantic contract 所要求的
> continuation invariant。**

声明变更 = 新表示声明（§8 版本规则），不自动继承旧声明的合格性。

## 4. Invariant obligations（不变量义务）

- INV-I：restore 后 identity 可断言且与 checkpoint 一致；模型/谱系
  绑定可核验。
- INV-P：restore 后落点与所录计算进度一致；进度失配可检测
  （检测机制允许 representation-dependent——见 §6）。
- INV-A：内容-语义对应可核验（锚定可比较且 functional）。
- INV-C：未来输出可断言为 THIS state 的延续（continuation
  provenance 可构造）。
- 验证义务：每个表示声明的合格性须由**预注册合格性电池**（P7-1
  C1–C4 / G-δ 电池结构）在声明时运行并留存 R0 工件。

## 5. Lifecycle obligations（生命周期义务）

| 操作 | 语义义务（INV-XB 跨操作保持） |
|---|---|
| **fork** | 分叉点两侧 closure 完整保持：anchor(child@fork) == anchor(parent@fork)；parent 非污染（child 分叉后 parent 状态与续算不变） |
| **restore** | I/P/A 可再断言（identity 核验、落点一致、锚可比较）；C 可再接续（恢复后可续算且 provenance 可构造） |
| **continue** | 严格前缀延接语义（Δ 接续于所录进度点）；延续 provenance 可断言（区别于同文本新计算） |
| **discard** | 废止后无 ghost continuation：状态不可再被合法续算，discard 原子性（逻辑废止与物理释放的顺序义务） |
| **release** | 释放后绑定清空、无跨状态残留；失败可恢复可重试（产品线 discard/release 原子性修复为义务来源） |

义务为语义级：实现方式（字段/机制）由各 Representation Contract
自行声明。

## 6. Representation-dependent derivability（G-δR 最重要的产出条款）

**P 条款（显式非要求项）**：

```text
Semantic Contract 要求：P 的语义必须被正确保持
  （落点可断言、进度失配可检测、记账可用）。

Contract 不要求：P 在每种 representation 中作为独立字段存在。

Representation 层：P may be explicit OR P may be derivable
  ——可 derivable 的前提=推导规则已注册于该声明的 Rules_R
    （例：full-prefix 锚表示中，A 的注册比对规则覆盖 P-2）；
  ——未注册推导规则而实际依赖推导 ⇒ 违反表示声明义务。
```

**一般化条款（(relation, representation) 属性）**：上述模式适用
于全部四关系——任一关系 X 在表示 R 中可显式或可推导，条件相同：
(a) 规则注册于 Rules_R；(b) 声明附 Required_R 评估（哪些功能
Required / Compensated，附证据级）；(c) 载体检视与全量重算排除
（继承 G-δR §2）。 necessity evidence 的表示范围随声明登记。

## 7. Explicit non-claims（非主张清单）

- 不主张 {I,P,A,C} 数学最小（未证明，且已 representation-aware 化）；
- 不主张 backend-independent（bounded claim 边界保持：两 backend
  ≠ 所有）；
- 不主张 universal/general Execution State theory；
- 不定义 ES「形而上是什么」（D7 继承：契约管语义保持义务，不管
  本体）；
- 不含性能主张；
- 本契约的实验依据限定于已登记证据链（P4/P5-1/P7-1/G-δ 及其在案
  原跑），「未复制」标注义务随引用传递。

## 8. Compatibility / versioning rules（兼容与版本规则）

- **版本**：ES Contract 版本号独立演进（本稿 = ES Contract draft
  1.0，待验收）；Representation Declaration 独立版本化（R 声明
  v.something）。
- **变更规则**：
  - Semantic Contract 变更 = closure-revision 级事件（须 human
    gate + 证据）；
  - Representation Declaration 变更 = 重新声明 + 合格性电池重跑；
  - 新 backend/新模型格式 = 新 Representation Declaration，零
    Semantic Contract 变更（这正是两层设计的目的）。
- **前驱兼容**：Architecture Contract v1.0 = 前驱参照（§1）；P6
  冻结概念边界 = Semantic 层定义来源；G-δR 两层定义 = 形式基础；
  PALACE 边界与 Security invariant 轨道不在本契约内（各自独立
  gate）。

## 9. Contract acceptance gate（验收门）

- **验收判定归 human**：本 Gate 通过 ⇒ 进入「Abstraction Freeze →
  SimiGo v2.0 Contract」讨论；不通过 ⇒ 修订本稿再审。
- 验收后的合格性义务：任何 backend 声明合格性前，须按 §4 运行
  预注册合格性电池并留存 R0 工件（P7-1/G-δ 即首两个实例）。
- 本 Gate 自身不触发任何实现、产品仓变更或实验。

---

**停在此处。** 零代码、零产品仓变更、零模型调用。

---

## 10. GATE RULING（human，2026-10-02）：CONTRACT ACCEPTED — FORMALIZATION SUFFICIENT

draft 1.0（2c6df83）通过本 Gate，进入下一阶段 **Abstraction Freeze →
SimiGo v2.0 Contract** 讨论。批准要点登记：

1. Semantic/Representation 两层正确分离——不会把 MLX/llama 实现细节
   错误提升为理论本体；
2. **P 条款必须保留**：「P 的语义必须被保持，但不要求在每一种
   representation 中作为独立字段存在」——`explicit OR derivable`
   是正确的 Contract-level abstraction；
3. Lifecycle 进入契约——Execution State 从「几个关系的集合」变成
   可操作的生命周期语义；
4. 非主张清单保持原样（防实现过程反向膨胀）；
5. 版本规则正确——「MLX upstream 改变/backend/model format/binary
   改变后 ES 抽象是否仍成立」这一问题被正式纳入架构。

**边界冻结**：Contract accepted ≠ SimiGo v2.0 Contract 已发布。研究
链：…→ Execution State Contract ★ACCEPTED → Abstraction Freeze →
SimiGo v2.0 Contract ← CURRENT NEXT GATE。研究形式化可接受；尚不称
「已完成的 v2.0 产品契约」。
