# SimiGo-Lab R2 — IAC ↔ Information Space Consistency Formalization (rev.2)

日期：2026-10-03（rev.2；rev.1 同日）
状态：**REV.2 DELIVERED / HUMAN REVIEW PENDING**
授权：human 显式指令进入 R2（2026-10-03，紧随 HOLD BEFORE R2 裁定）
复审：human R2 review（2026-10-03）= **REVISE REQUIRED**（局部形式化修订，
不需重做 R2，不涉实验、实现、IPAC、P 或 Route）；rev.2 按三处最小修订
+两处结构修正完成，重新提交 R2 review。

## 0. 范围与约束（继承，全程有效）

R2 只处理：

1. I/A/C 与 H1/H2/H3 各自描述什么；
2. 两组概念之间能否建立语义映射 / 一致性关系；
3. Information Space 变化在什么条件下会破坏 I/A/C 所要求的 continuation 条件。

R2 不重新裁定：

- P 的历史含义；
- P 是否第四字段；
- IPAC 是否正确；
- Route A/B/C。

全程禁止：冻结 IPAC、开启 PALACE、修改实现、运行实验、选择 Route。
本文档全部内容为 **candidate formalization**，效力止于「R3 的输入」；
R2 判定（APPROVED / REJECTED / REVISED）归 human。

## 0.1 rev.2 修订记录

| # | rev.1 问题 | rev.2 修订 |
|---|---|---|
| R-1 | 「possible ∧ lawful」把 lawful 内嵌进 H3 映射，使 RQ-R2 的必要性声明循环化（H3 ⇒ Cons 偷偷包含研究对象） | H3 保持纯外部可能性语义，lawful 不内嵌；C↔H3 最多读作「外部 continuation possibility vs 内部 continuation condition」的对应 |
| R-2 | A↔H1 写得近似等价映射，有偷换风险 | 降为依赖/支撑关系：H1=外部信息可获得性，A=内部锚定关系；差异保留为研究对象，不在对应阶段消掉 |
| R-3 | RQ-R2 未显式声明必要性单向性 | 显式写 LawfulContinuation ⇒ Cons 为必要性候选，且 Cons ⇏ LawfulContinuation（非充分） |
| S-1 | Task 2 呈现为 component mapping（I↔H2/A↔H1/C↔H3），易读成两套三元组是同一组东西 | 改为 correspondence relations（I constrains H2 / A depends on H1 / C conditions H3）+ 分层图：外部条件 support/constrain 内部条件 |
| S-2 | Cons 三条件写法易读作 IS 自身属性（IS must contain I/A/C） | 改写为条件保持关系 I-condition ∧ A-condition ∧ C-condition (ES, IS)：IS 变化 → 某内部条件不再成立 → Cons broken |

## 1. Task 1 — 各自描述什么（descriptive separation）

### 1.1 内部 I/A/C（Execution State 内部 continuation skeleton）

引 G-δR Formalization Gate（SIMIGO_LAB_GDELTAR_FORMALIZATION_GATE_20261002.md）
Appendix 原文，仅引用非重裁：

```text
Role(I) = { I-1 模型绑定：restore 拒绝异模型载荷,
            I-2 谱系绑定：不同计算状态可分辨,
            I-3 载荷完整性交叉核对：record↔carrier 失配检出
                〔llama 上被 A 部分补偿——partial subsumption〕 }
Role(A) = { A-1 内容绑定：N 处上下文内容-语义对应
            （同位置异内容状态的可分辨性） }
Role(C) = { C-1 接续许可：未来输入的合法接续关系 }
```

I/A/C 在 R1 封存中的证据地位（引用）：necessity evidence under tested
conditions。P 不入本形式化（范围排除，历史含义已由 R1 封存）。

一句话概括：**I/A/C 作为 R2 工作抽象，描述「延续合法所需的内部语义
条件」**。边界保护：这是 necessity-side 工作抽象——**不得读作 lawful
continuation 的充分条件定义**；充分性是否可建立正是 RQ-R2 要检验的
内容，不是定义（rev.2 R-3 前置）。

### 1.2 外部 H1/H2/H3（Boundary Synthesis accepted model）

引 Boundary Synthesis human 裁定（RESEARCH_STATE.md 2026-10-03 各节）：

- **H1（Information Space）**：当前执行能获得、引用、作用于的
  information domain——回答「哪些信息可用」。数据库/知识库/PALACE 是
  carrier，不等于 Information Space 本身；其边界可随执行、信息获取、
  外部观察和持久化状态变化。
- **H2（Execution State）**：当前 goal-directed execution 的位置、阶段、
  控制状态与可继续点——回答「执行做到哪里」，不是「系统知道什么」。
- **H3（Continuation）**：Goal unchanged + current Execution State
  identifiable + required Information still available → continuation
  **possible**（可能性条件，非保证；资源、权限、版本、外部状态等仍属
  后续独立条件）。

**H3 语义保护（rev.2 R-1）**：H3 保持上述纯外部可能性语义。**H3 不含
lawful**——「lawful」不属于 H3 的语义内容，H3 的任何读法都不得内嵌
合法性；合法性与可能性的关系是 RQ-R2 的研究对象，不由定义拼合。

一句话概括：**H1/H2/H3 描述的是「一次执行在外部世界里处于什么局面」**
——什么信息在域内（H1）、执行在哪（H2）、什么局面下延续可能（H3）。

### 1.3 描述层对照（只对照，不消差异）

| 维度 | 内部 | 外部 | 分界 |
|---|---|---|---|
| 同一性 vs 位置 | I：这是哪个计算状态的延续 | H2：执行现在在哪 | 同一性 ≠ 位置——同一状态可被多次定位，位置可变而身份不变 |
| 绑定 vs 可用 | A：内容被绑定于状态（**内部锚定关系**） | H1：内容在域内可用（**外部可获得性**） | 绑定 ≠ 可用——两者不是同一命题；该差异是研究对象，不在对照阶段消掉（rev.2 R-2） |
| 许可 vs 可能 | C：什么算合法接续（**内部接续条件**） | H3：什么局面下延续可能（**外部可能性**） | 许可 ≠ 可能——H3 不含 lawful；二者关系由 RQ-R2 研究，不由定义拼合（rev.2 R-1） |

## 2. Task 2 — 对应关系 / 一致性（correspondence，NONBINDING）

### 2.1 对应关系（非 component mapping）

rev.2 起，Task 2 不再呈现为「I↔H2 / A↔H1 / C↔H3」的组件映射——该写法
易被读成「两套三元组其实是同一组三个东西」，当前证据不支持此强解释。
改为**对应关系**：

```text
I  ── constrains ─── H2   身份判据为「状态可识别」提供判定内容
A  ── depends on ─── H1   锚定关系依赖外部信息的供给与保持
C  ── conditions ─── H3   接续条件限定合法接续；H3 只给外部可能性
```

抽象分层：

```text
        Information Space
        H1 / H2 / H3        （外部信息条件）
              │
              │  support / constrain
              ↓
        Execution State
        I / A / C           （内部 lawful-continuation 条件）
              │
              ↓
       lawful continuation
```

**研究立场**：R2 的研究对象是两层之间是否存在 consistency relation；
**不是**证明 IAC = H123（同构既无证据支持，也非本 gate 目标）。

### 2.2 候选一致性关系（条件保持形式）

**IAC-Consistency (candidate, 未冻结)**：

```text
Cons(ES, IS) ⟺
    I-condition(ES, IS)   （身份条件保持）
  ∧ A-condition(ES, IS)   （锚定条件保持）
  ∧ C-condition(ES, IS)   （接续条件保持）
```

三个 X-condition 是**条件保持关系**（ES 的内部要求与 IS 当前状态之间的
关系），**不是 IS 自身的属性**：

```text
(a) I-condition：ES 的身份/谱系判据在当前 IS 语境下仍可评估
    （不要求 IS 携带身份，只要求 IS 不使其不可判定）；
(b) A-condition：A-1 所绑定的语义内容仍是 IS 当前边界内的可引用信息
    （可引用 = 存在、可寻址、未被静默替换——替换须可检出）；
(c) C-condition：C-1 接续所依赖的前置语义条件（settled results、
    preconditions）在 IS 中仍成立、未被废弃或取代。
```

读法固定：**IS 变化 → 某个内部条件不再成立 → Cons broken**；
而不是「IS 必须包含/实现 I/A/C」。方向禁令沿用（N-5 精神）：评估
单向——外部变化评估内部判据可满足性，不得反向读作 IS 必须实现 IAC。

### 2.3 诚实边界

- correspondence 的动机是 Continuity Bridge 的 structural correspondence；
  correspondence 是动机非证明；
- 本关系不证明 IPAC 正确、不冻结任何字段、不宣称两组概念同构；
- **A 与 information availability 的差异不消掉**：H1 是外部可获得性、
  A 是内部锚定关系，二者不是同一命题——该差异可能正是 R2 要发现的
  consistency relation 的内容，留作研究对象（rev.2 R-2）；
- **P 相关对应明确声明为范围外**：H2 位置侧与历史 P（P-1 落点/P-2
  边界/P-3 记账）的表面对应不作任何裁定、不作任何推论。

## 3. Task 3 — Information Space 变化何时破坏 I/A/C 所要求的 continuation 条件

破坏的定义：**Cons(ES, IS) 从满足变为不满足**（ES 不变，IS 变化）
= 某个 X-condition 从成立变为不成立。判定对象是「条件是否仍可满足」，
**不是**「输出文本是否变化」（沿用 null ≠ mechanism null 纪律）。
此句为固定判读纪律：禁止滑回「output changed → continuation broken」
——那不是本研究要测的东西。

### 3.1 候选破坏 taxonomy

```text
(a) 类——I-condition 破坏（身份不可判定）：
    IS 变化使 ES 的 lineage 判据无法评估（谱系记录被清除且不可引用）；
    model/版本语境变化使 I-1 不可判定
    （backend boundary 保留：判定责任在 representation 层，IS 变化
    只是使其前提消失）。

(b) 类——A-condition 破坏（锚失效）：
    锚绑定内容被删除 / 移出 IS 当前边界 / 因权限或隐私不可引用；
    内容被替换但锚仍解析（silent substitution：same address,
    different content——PA-2 模式的外部化）。

(c) 类——C-condition 破坏（许可前置失效）：
    接续所依赖的 settled result 被废弃或被新结果取代；
    precondition facts 不再成立；
    出现针对该结果/前提的 invalidation 记录。

跨类——边界重划：
    IS 边界收缩/重定义使多个 X-condition 同时失效（单一动作，
    多成分破坏）。
```

### 3.2 非破坏对照类（防假阳）

- 纯增量变化：新增信息不改变已有内容的可引用性与前提成立性；
- 不触及锚对象、谱系记录、许可前置的变化；
- 可引用性等价迁移（内容搬家但寻址与可检出性保持）。

### 3.3 归因纪律

破坏若发生，须可归因到 (a)/(b)/(c) 之一（或跨类组合）；不可归因的
失败按 INCONCLUSIVE 处理，不得折算为对一致性关系的确认或否证。

## 4. 核心交付 — 可证伪研究问题（RQ-R2 rev.2，必要性单向显式化）

**RQ-R2**：

> 对已形成并可恢复的 Execution State ES 及其 Information Space IS：
> 是否存在一致性关系 Cons(ES, IS)（候选 = §2.2），使得
> (i) **LawfulContinuation(ES, IS) ⇒ Cons(ES, IS)**（必要性候选——
> 且仅此方向）；
> (ii) 保持性 IS 变化（不破坏任何 X-condition）不破坏 lawful
> continuation 的信息侧条件；
> (iii) 破坏性 IS 变化可归因到具体条件（I/A/C-condition 之一），且该
> 归因可在**不重算历史**的前提下判定？

**单向性声明（rev.2 R-3，关键）**：

```text
LawfulContinuation(ES, IS) ⇒ Cons(ES, IS)    〔必要性候选〕
Cons(ES, IS) ⇏ LawfulContinuation(ES, IS)    〔显式非充分〕
```

`Cons = true` **绝不**推出 `LawfulContinuation = true`。R2 不定义
延续的充分条件；充分性是否可建立属后续独立研究。

**循环防护（rev.2 R-1 落点）**：H3 保持纯可能性语义、不含 lawful
（§1.2），因此 (i) 不构成自包含——研究对象（lawful continuation 的
信息侧必要条件）不被定义预先携带。

**可证伪形式**：

- 预测（若候选成立）：存在 IS 变化类 Δ，使 ES 逐字不变、Δ(IS) 后
  lawful continuation 不再可能或不再合法，且失败可归因到 I/A/C-
  condition 之一；
- 证伪路径一（归因失败）：受控 IS 变化导致延续破坏，但破坏无法归因到
  任何条件 ⇒ 候选 Cons 不是正确的刻画，需修订或放弃；
- 证伪路径二（必要性失败）：三个条件全部破坏后 lawful continuation
  仍以可核验方式成立 ⇒ I/A/C 条件相对 IS 不是延续的信息侧必要条件；
- 明确非主张：RQ-R2 不预设 Relation 结构、不预设 PALACE、不涉及 P、
  不测性能、不授权任何实验；实验设计属后续独立 gate（R3 之后）。

## 5. 登记洞察（review 提出，NONBINDING）

human R2 review 指出（登记为 open observation，非结果）：

> I/A/C 与 H1/H2/H3 很可能不是「两套相同的三元字段」，而是「内部语义
> 条件」与「外部信息条件」之间的**对应关系**。若此，R2 无需证明
> IAC = H123；真正值得研究的是二者之间的 consistency relation
> （§2.1 分层图）。这比同构假设更难，但更像真正的理论问题。

该洞察不冻结、不预设结论；其检验方式即 RQ-R2。

## 6. 效力声明

本文档 rev.2 = R2 重新提交稿，状态 REV.2 DELIVERED / HUMAN REVIEW
PENDING。human 判定（APPROVED / REJECTED / REVISED）前，其内容不构成
任何冻结、任何承诺、任何实验授权。R3 仍 blocked by R1–R2，须待 R2
review 通过后另行裁定。

约束保持（review 确认全部维持）：

```text
P              = OUT OF SCOPE
IPAC freeze    = NO
Route          = NO
PALACE         = NO
Implementation = NO
Experiment     = NO
```

## 7. 输入清单

- RESEARCH_STATE.md：「HUMAN RULING CONFIRMED — HOLD BEFORE R2」段
  （R2 前置理解）；Boundary Synthesis H1/H2/H3 ACCEPTED 各节；
  Continuity Bridge 节；R1 Historical Evidence Review 节；human R2
  review 判定（REVISE REQUIRED，2026-10-03，本 rev.2 修订依据）
- SIMIGO_LAB_GDELTAR_FORMALIZATION_GATE_20261002.md（Role taxonomy 原文引用）
- SIMIGO_LAB_HUMAN_RESEARCH_DECISION_IAC_INFORMATION_SPACE_CONSISTENCY_20261003.md
  （R2 定义与 violation question 原始出处）
- SIMIGO_LAB_IPAC_CONTINUITY_BRIDGE_SYNTHESIS_20261003.md（structural
  correspondence 动机与禁止清单）
