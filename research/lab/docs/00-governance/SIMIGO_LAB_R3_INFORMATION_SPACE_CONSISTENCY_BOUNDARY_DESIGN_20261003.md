# SimiGo-Lab R3-0 — Information Space Change and Execution-State Consistency Boundary Study — Research Design

日期：2026-10-03
状态：**R3-0 DELIVERED / HUMAN APPROVAL PENDING**
授权来源：human R3 research decision（2026-10-03，紧随 R2 rev.2 APPROVED /
FORMALIZATION SEALED）——R3 研究任务与范围由 human 明确决定；本设计为
R3-0 交付物（**只设计：不实验、不实现**）。

## 0. 定位与授权边界

- R3 的任务（human 裁定要旨）：**不是继续讨论 I/A/C 是什么，而是第一次
  把 R2 的 `Cons(ES, IS)` 变成可观察、可判定、可证伪的研究对象。**
- R3 = "Information Space Change → Execution State Consistency" 研究；
  不直接进入 PALACE、IPAC 或实现。
- **R3 不是 PALACE 实验**：R3 研究「Information Space 的信息变化」这个
  抽象对象，但不因需要改变 Information Space 就选择 PALACE 作为物理
  实现。PALACE 保持 CLOSED。

## 1. 核心研究问题（Primary Question）

> **当 Execution State 固定而 Information Space 发生变化时，哪些变化
> 会使 `Cons(ES,IS)` 从 satisfied 变为 unsatisfied？**

最小研究单元：

```text
IS₀
 │
 │ ΔIS
 ▼
IS₁                ES 固定（不变）

Cons(ES, IS₀) = true
Cons(ES, IS₁) = ?
```

这比直接问「能不能继续」更严格：如果直接观察输出（继续成功/继续失败），
很容易把模型行为、实现缺陷、资源不足、随机性等混进来。R3 首先研究
**条件满足性的变化**，不是输出变化。

## 2. 研究对象与记号

- 研究对象：`Cons(ES, IS)`（R2 rev.2 封存候选定义，引用不修改）：
  `Cons(ES,IS) ⟺ I-condition(ES,IS) ∧ A-condition(ES,IS) ∧
  C-condition(ES,IS)`
- 继承的单向性：`LawfulContinuation(ES,IS) ⇒ Cons(ES,IS)`（必要性候选）；
  `Cons ⇏ LawfulContinuation`（非充分，R2 rev.2 封存）
- 核心对象：`(ES, IS₀) → (ES, IS₁)`（ES 固定）
- 核心观察：`Cons(ES, IS₀) → Cons(ES, IS₁)`
- 核心问题：`ΔIS → Δ(I/A/C conditions)`

## 3. 明确排除（写入 scope，防膨胀）

```text
P                     OUT
IPAC 最小性            OUT
IPAC 冻结              OUT
PALACE 实现             OUT
PALACE MCP             OUT
Route A/B/C            OUT
后端适配                OUT
产品实现                OUT
性能优化                OUT
模型能力比较            OUT
完整恢复系统            OUT
```

## 4. 三个研究层次与阶段门（顺序非常重要）

```text
R3-0  Research Design（本文档；不实验、不实现）
      ↓ human approval
R3-1  Condition Observability
      ↓ gate
R3-2  Single-change Boundary Study
      ↓ gate
R3-3  Counterexample / Non-break Study
      ↓ gate
R3-4  Consistency Synthesis
```

每道 gate 需 human 显式授权放行；R3 一次只授权一段，不一次授权整个 R3。

### 4.1 R3-1：Cons 可判定性（Condition Observability）

研究问题：**是否能够在不依赖最终输出的情况下，对给定 `(ES, IS)` 判断
I/A/C 三类条件是否满足？**

R3-1 不做实验系统实现——先做**判定规范**（judgment specification）：
把三个条件变成可观察命题。

- **I-condition**：不重新定义 I（I-1 model binding / I-2 lineage binding
  / I-3 payload integrity 沿用 G-δR 原文）。研究的是「IS 改变后，原
  Execution State 的 identity conditions 是否仍然成立」。例：
  `IS₀{model=M, lineage=L, payload=P} → IS₁{model=M′, lineage=L,
  payload=P}` ⇒ `I-condition(ES,IS₀)=true`，`I-condition(ES,IS₁)=?`
- **A-condition**：A 是内部 anchoring relation（非 H1 同义词，R2 rev.2
  已定）。研究「IS 中的信息变化是否导致当前 Execution State 无法再被其
  原有信息锚定」。例：`IS₀{required information R exists, R corresponds
  to ES} → IS₁{R removed}` ⇒ `A(ES,IS₀)=true`，`A(ES,IS₁)=?`
- **C-condition**：C 是 continuation condition。研究「IS 的变化是否使
  原 continuation prerequisite 不再成立」。例：`IS₀{settled result R
  valid} → IS₁{R retired / invalidated}` ⇒ `C(ES,IS₀)=true`，
  `C(ES,IS₁)=?`

R3-1 出口判据：I/A/C 三条件能被**独立观察、记录和判定**；做不到就不能
进入 R3-2。

### 4.2 R3-2：Information Space Change Taxonomy（单变量变化边界研究）

先建立「**什么叫 Information Space change**」，不上来就做大量案例。
五类：

```text
ΔIS
│
├── IS-I  Identity change
├── IS-A  Anchor/reference change
├── IS-C  Continuation-prerequisite change
├── IS-B  Boundary/accessibility change
└── IS-X  Cross-condition change
```

前三类对应 R2 的 I/A/C；后两类用于防止过度简化。

- **IS-I（身份变化）**：model identity 改变 / lineage 改变 / payload
  identity·integrity 改变。目标模式：ES 固定，IS₀→IS₁，
  `I: true → false`，A/C 保持。若能稳定观察到该模式 ⇒ 支持
  「Identity-related Information Space changes can invalidate
  I-condition」。
- **IS-A（锚定变化）**：所需信息删除 / 信息范围变化 / 原引用对象消失 /
  原 information-to-state correspondence 不再成立。目标：`I = true`，
  `A: true → false`，C 未主动改变——检验 A 是否真的承担独立的
  continuation anchoring 角色。
- **IS-C（继续条件变化）**：settled result 被撤销 / 前置条件失效 /
  原先允许继续的结果不再有效 / continuation prerequisite 改变。目标：
  `I = true`，`A = true`，`C: true → false`——**把「身份还在」和
  「仍然可以继续」严格分开**。
- **IS-B（边界/可访问性变化）**：信息还存在，但不再属于当前 Information
  Space / 不可访问 / 超出当前语义边界。直接对应既有观点「Information
  Space 是一个信息边界，而不是简单的数据库」：
  ```text
  Information exists
          ≠
  Information belongs to current IS
          ≠
  Information is accessible to ES
  ```
  **R3 不预先宣布它是第四个 primitive，只研究现象**——它可能最终成为
  Information Space 理论中非常重要的独立因素，该判定留给证据与后续
  gate。
- **IS-X（复合变化）**：`ΔI+ΔA / ΔA+ΔC / ΔI+ΔC / ΔI+ΔA+ΔC`。原因：如果
  一开始就用复合变化，出现失败以后根本不知道是谁造成的。顺序严格：
  **单变量变化 → 确认可归因 → 双变量变化 → 交互效应**。

### 4.3 R3-3：最小实验矩阵与反证研究（hypothesis structure）

| Case | ES    | IS 变化         | I | A | C | Cons |
|------|-------|-----------------|---|---|---|------|
| R3-I | fixed | identity        | ↓ | = | = | ↓    |
| R3-A | fixed | anchor/info     | = | ↓ | = | ↓    |
| R3-C | fixed | prerequisite    | = | = | ↓ | ↓    |
| R3-B | fixed | boundary/access | ? | ? | ? | ?    |
| R3-X | fixed | compound        | ? | ? | ? | ?    |

**纪律（固定措辞）**：矩阵中的 `↓` 不是结果预设，而是**待验证预测**；
**矩阵是 hypothesis structure，不是 expected result declaration**。

对照（基本因果结构）：

```text
Control:   (ES, IS₀) → (ES, IS₀)   Cons 应保持不变
Treatment: (ES, IS₀) → (ES, IS₁)   观察 Cons
```

没有 control 就无法证明是 Information Space change 导致 Cons 变化。

**R3-N 反证实验（必做，R3 的边界研究性质所在）**：不只寻找「Information
Space 改变 → Cons 崩溃」，还**必须**寻找「Information Space 改变 →
Cons 仍然成立」。否则很容易得到过强的错误结论 `ΔIS ⇒ ¬Cons`。真正合理
的候选关系：

```text
ΔIS ⇏ ¬Cons
ΔIS →? Δ(I/A/C conditions)   只有特定类型的 IS changes 才可能破坏 Cons
```

这使 R3 从「找几个失败案例」变成真正的边界研究。R3-3 专门搜索两类：

1. `ΔIS ≠ 0` 但 `Cons` 不变（non-break cases）；
2. `ΔIS ≠ 0`、`Cons` 改变，但**无法归因到 I/A/C**（第二种尤其重要——
   直接挑战 R2 候选形式）。

## 5. 总判定纪律（继承 R2 Task 3，提升为 R3 总纪律）

> **R3 的主要判定对象是 condition satisfiability，不是最终输出是否
> 改变。**

因为可能发生：`Cons = false` 但模型碰巧输出同样结果；也可能 `Cons =
true` 但模型因为其他因素输出不同结果。所以：

```text
Output      ↑ 不能直接定义
Cons        │ 由 I/A/C condition satisfiability 判定
最终输出只能作为辅助观察
```

此纪律与 R2 Task 3「判定对象是条件是否仍可满足，而不是输出是否变化」
同源，在 R3 升格为总纪律。

## 6. R3 终局四问（R3-4 才允许回答）

- **RQ3-1**：Information Space 的变化是否能够在 Execution State 固定时
  导致 `Cons(ES,IS)` 改变？
- **RQ3-2**：如果可以，哪些类型的 Information Space change 分别影响
  I、A、C？
- **RQ3-3**：是否存在 Information Space 变化，但 I/A/C 条件仍保持满足
  的情况？
- **RQ3-4**：I/A/C 三类 condition 是否足以描述当前实验范围内观察到的
  consistency boundary，还是存在无法归类的变化？

RQ3-4 尤其重要：如果出现 `IS changed ∧ Cons changed ∧ I = A = C = true`，
那么 R2 的候选形式 `Cons = I ∧ A ∧ C` 直接受挑战——**这才是真正有研究
价值的负结果**。

## 7. PALACE 定位（暂不放进 R3）

```text
                    Information Space
                           │
             ┌─────────────┴─────────────┐
             │                           │
       semantic object              physical carrier
             │                           │
             ▼                           ▼
       Execution State                 PALACE
          / SimiGo
```

R3 先研究左侧（ES ↔ Information Space 语义关系）。等这个关系有了证据
以后，才有资格研究 PALACE 如何成为 Information Space 的物理承载。否则
很容易把 Information Space semantics 和 PALACE database semantics 重新
混在一起。**PALACE = CLOSED 维持不变。**

## 8. 阶段出口与可能结果

R3-4 才允许回答「当前证据是否支持 R2 的 `Cons` 候选定义」。结果必须
允许：

```text
SUPPORTED
PARTIALLY SUPPORTED
NOT SUPPORTED
INCONCLUSIVE
```

**不能预设一定成功**；失败同样是有效结果，不得为使路线成立而修改判据
（实验宪法失败有效性条款精神沿用）。

## 9. 正式登记草案（human 提供的状态草案，逐字登记）

```text
R3
────────────────────────────────
Name:
Information Space Change and
Execution-State Consistency Boundary Study

Primary Question:
当 Execution State 固定而 Information Space
发生变化时，哪些变化会使 Cons(ES,IS)
从 satisfied 变为 unsatisfied？

Secondary Questions:
RQ3-1  I/A/C 是否可独立观察与判定？
RQ3-2  哪些 IS change 分别影响 I/A/C？
RQ3-3  哪些 IS change 不影响 Cons？
RQ3-4  是否存在无法由 I/A/C 解释的 Cons change？

Research Object:
Cons(ES,IS)

Method:
controlled Information Space change
+ fixed Execution State
+ condition-level observation

Primary Judgment:
condition satisfiability

Not:
final output change

Required Controls:
IS unchanged control
single-change attribution
non-break cases
counterexample search

Excluded:
P
IPAC freeze
PALACE
MCP
Route A/B/C
implementation
productization
backend selection

Stages:
R3-0 Design
R3-1 Observability
R3-2 Single-change boundary
R3-3 Counterexample / non-break
R3-4 Consistency synthesis

Possible Outcomes:
SUPPORTED
PARTIALLY SUPPORTED
NOT SUPPORTED
INCONCLUSIVE
```

## 10. R3-0 效力声明

本文档 = R3-0 交付物（研究设计），状态 DELIVERED / HUMAN APPROVAL
PENDING。R3-0 只设计：**零实验、零实现、零 PALACE、零 IPAC 冻结、零
Route 选择**。R3-1 的开启须 human 显式批准本设计；R3-2 / R3-3 / R3-4
各自另过 gate，一次只授权一段。

## 11. 输入清单

- RESEARCH_STATE.md：R2 rev.2 APPROVED / FORMALIZATION SEALED 节；
  Boundary Synthesis H1/H2/H3 ACCEPTED 各节；R1 Historical Evidence
  Review 节
- SIMIGO_LAB_R2_IAC_INFORMATION_SPACE_CONSISTENCY_FORMALIZATION_20261003.md
  rev.2（Cons 候选定义、X-condition 条件保持形式、破坏 taxonomy、RQ-R2
  单向性）
- SIMIGO_LAB_GDELTAR_FORMALIZATION_GATE_20261002.md（I/A/C role taxonomy
  原文，R3-1 引用不重定义）
