# SimiGo-Lab Post-R3 Research Direction Gate — Participant Draft

状态：**DRAFT / SUSPENDED AS ROUTE INPUT / SUPERSEDED BY CORE RESEARCH OBJECT REALIGNMENT**

登记时间：2026-10-03  
前置状态：R3 已由
`SIMIGO_LAB_R3_CLOSING_DECLARATION_20261003.md`
正式关闭。  
本文性质：研究转场评审草案。它只把 R3 的有界产出转译为下一阶段可
审视的研究资产，并登记候选方向。  

本文**不**：

- 不重开 R3；
- 不复跑 R3 实验；
- 不为任何候选线分配 RQ ID；
- 不选择下一条研究线；
- 不授权实验、测量、实现、存储选型或模型接入；
- 不把 PALACE / IPAC / P / Route A/B/C 自动并入 R3 后续；
- 不修改 `docs/RESEARCH_STATE.md` 或任何已封存结论。

## 0. Gate 问题

本次 Gate 只回答三个问题：

1. R3 实际改变了我们对 SimiGo Execution State 的什么认识？
2. 哪些问题已经从“研究假设”变成了“有证据支持的边界事实”？
3. 哪些开放边界最值得进入下一阶段的候选研究空间？

判定权保留给 human。本文不输出优先级排序，也不推荐唯一路线。

## 1. 输入锚点

```text
R3 收官声明
docs/00-governance/SIMIGO_LAB_R3_CLOSING_DECLARATION_20261003.md

R3-4 综合门 rev.2
docs/00-governance/SIMIGO_LAB_R3_4_SYNTHESIS_GATE_20261003.md

IS-X Attempt #2 结果
docs/00-governance/SIMIGO_LAB_ISX_ATTEMPT2_RESULTS_20261003.md

权威状态
docs/RESEARCH_STATE.md
```

引用边界：R3 的所有结论都必须继续携带
**fixture-slice bounded** 限定，并遵守收官声明中的限缩读法。

## 2. R3 转译后的 confirmed knowledge

以下均为**有界边界知识**，不是普遍定律。

### 2.1 条件具有差分敏感性

在 R3 的单操作、顺序执行、单 Execution State、文件型 Information
Space、零模型推理切片中，Cons 相关条件对单变量 Execution-State /
Information-Space 变化呈现差分敏感性：

```text
某些定向变化击穿特定条件；
其余条件保持；
控制项持有。
```

可继承读法：后续研究不应把所有条件视为同一敏感度的整体，也不应把
某一条件在单操作下的结果机械外推到其它操作或条件。

### 2.2 HOLD 侧提供了非平凡对照

R3-3 的 HOLD 侧在当前探针范围内观察到零击穿，并有正控活性支持。
这说明 R3-2 的 BROKEN 侧不是“任何变化都会击穿任何条件”的退化结果。

可继承读法：HOLD 侧可以作为下一阶段构造对照的参照，但不能被引用为
不变量已建立。

### 2.3 复合变化暴露出顺序相关联合行为

IS-X 在同组成、异顺序的 X-08 / X-09 操作对上确认：

```text
X-08 = MASKING；
X-09 = ADDITIVE。
```

这支持一个有界判断：在当前 fixture-slice 内，单变量 Execution-State /
Information-Space 变化的敏感性画像，不能在这组复合变化上通过
`P_comp` 机械组合得到。

不可外推读法：

- 这不是普遍非交换性；
- 不是一般 interaction law；
- 不是对所有多操作组合的结论；
- 不涉及模型推理、continuation 成败、并发或时间压力；
- 不把 X-08 / X-09 提升为 Cons 正确性、最小性或完备性证明。

### 2.4 方法论资产

R3 的三层结构已经成为可复用研究模板：

```text
BROKEN side    证明可击穿性；
HOLD side      证明非普遍退化；
interaction    检查复合变化是否超出单变量组合解释。
```

可复用的是方法纪律与判定边界，不是实验细节或具体结论本身。

## 3. R3 后暴露或显式保留的开放边界

以下均来自 R3 收官声明，全部保持
**OPEN BOUNDARY / NOT STARTED / NOT SELECTED**。

| ID | 边界 | 与 R3 的关系 |
| --- | --- | --- |
| UB-1 | content-addressed representation / 表征变体 | R3 未测表征变体下 A 的边界行为 |
| UB-2 | concurrency / 并发 ΔIS | R3 全程结构性未测 |
| UB-3 | temporal dynamics / validity 时窗与时间压力 | R3 中时窗空转，时间压力未测 |
| UB-4 | additional multi-operation pairs | 仅 X-08 / X-09 一组逆序对照 |
| UB-5 | semantic correctness oracle | 冲突记录下谱系语义正确性缺乏独立 oracle |
| UB-6 | 共享盲区 B-1..B-6 | 跨战役一致不等于正确 |
| UB-7 | 检出力边界 | 条件被违反但评估器无法表示的形态不可及 |

这些边界不能因 R3 关闭而被视为已解决或已否定。

## 4. 候选研究空间

本节只登记候选方向，不选择路线。

命名边界：本节的 **Candidate A / B / C** 只是本文为讨论建立的
post-R3 研究问题族标签。它们不等于、不继承、不激活仓库中既有的
**Route A/B/C**；既有 Route A/B/C 仍保持 `NOT SELECTED`。

### Candidate A — R3 开放边界研究

**研究问题族**：表征、并发、时间动态是否改变 R3 观察到的边界行为。

#### A1 Representation boundary

```text
问题       表征变体或 content-addressed representation 是否保持、
           改变或消除 R3 的差分敏感性？
已有证据   UB-1；R3 未测。
未知       表征是否参与条件判定；签名可观察性是否迁移；
           P_comp 问题是否在表征变体下重现。
范围       应保持独立于工程存储选型。
过度主张风险   把当前文件型 IS 结论外推为表征无关结论。
是否值得开     候选；需先独立定义表征边界，不能自动启动。
```

#### A2 Concurrency boundary

```text
问题       并发 ΔIS 是否产生超出顺序复合语义的 Execution State
           一致性边界？
已有证据   UB-2；R3 结构性未测。
未知       并发与 X-08 / X-09 式顺序交互是否同层；冲突形态是否
           能被现有评估器表示；是否需要新的观察面。
范围       不应从 X-08 / X-09 直接推导并发规律。
过度主张风险   把顺序非交换性误读为并发竞争结论。
是否值得开     候选；依赖并发对象与观察面的独立定义。
```

#### A3 Temporal boundary

```text
问题       validity 时窗、延迟可见性或时间压力是否改变条件
           击穿 / 持有行为？
已有证据   UB-3；R3 中时窗空转。
未知       时间是否只是测量变量，还是进入条件本身的构成项。
范围       不应与并发研究合并，除非未来 Gate 明确证明两者共享对象。
过度主张风险   把“时窗空转”解释为“时间不重要”。
是否值得开     候选；需要先证明存在非空时间区分力。
```

### Candidate B — Higher-order composition semantics

**研究问题族**：多操作、顺序、additivity / masking / interaction 的
Execution-State 边界语义。

这是 R3 最直接暴露出来的科学延伸，但本文不据此授权开启。

#### B1 Additional operation pairs

```text
问题       X-08 / X-09 之外的操作对是否呈现 additive、masking、
           其它交互类型，或保持可机械组合？
已有证据   UB-4；仅一组逆序对照。
未知       interaction 是否只属于特定操作语义；
           是否存在稳定的组合分类；
           P_comp 的失败域能否被有限刻画。
范围       首先应限定为 sequential、非并发、零模型推理。
过度主张风险   把一组逆序对照外推为组合代数。
是否值得开     候选；R3 直接暴露，但仍必须先定义操作目录与
               组合分类判据，不因此获得启动优先权。
```

#### B2 Composition semantics formalization

```text
问题       能否定义一个有界的组合语义层，使 additive / masking /
           其它可观察联合行为具有一致的判定与解释？
已有证据   X-08 / X-09 显示同组成异顺序具有不同联合效果。
未知       该层是否应有独立对象，或只是 R3 解释器的重述；
           是否需要最小算子语义；
           是否能不引入 PALACE 或产品语义。
范围       只做形式化/半形式化研究，不做实现。
过度主张风险   用新名词包装 R3 现象，制造虚假理论层。
是否值得开     候选；应先做最小语义 Gate，而不是直接建理论。
```

#### B3 Semantic correctness oracle

```text
问题       在冲突记录形成后，谱系是否语义正确？
已有证据   UB-5；R3 没有语义 oracle。
未知       语义正确性的对象、标准、可观察面与独立裁判机制。
范围       必须与 R3 的签名级一致性判定分开。
过度主张风险   把“签名符合预测”读成“语义正确”。
是否值得开     候选；但依赖独立 oracle 定义，可能是高风险线。
```

### Candidate C — Integrated system / PALACE relation

**研究问题族**：Execution State、Information Space 与 PALACE /
SimiGo 整体系统之间的关系。

#### C1 Post-R3 boundary translation

```text
问题       R3 的哪些有界概念可以被 PALACE / 整体系统研究安全引用，
           哪些不能？
已有证据   R3 收官声明明确排除 PALACE / IPAC / P / Route A/B/C。
未知       R3 边界概念在更大系统语境中的映射是否存在；
           若存在，需要什么新契约。
范围       只做引用边界转译，不做系统设计或实施。
过度主张风险   把 R3 结果直接当系统设计依据。
是否值得开     候选；可考虑作为引用边界前置，但不能自动激活
               PALACE 线。
```

#### C2 Integrated-system research

```text
问题       Execution State 与 PALACE Information Space 的整体系统
           问题应如何定义？
已有证据   现有 PALACE 主线已关闭；R3 也排除该方向。
未知       是否存在必须依赖两者联合才能提出的问题。
范围       必须是新线，不得继承 R3 授权。
过度主张风险   在 R3 刚关闭后立即把系统愿景压回研究主线。
是否值得开     暂不推荐开启；应等待 post-R3 方向裁定后再审视。
```

## 5. 明确不做的事

```text
不为 A/B/C 候选打总分；
不宣称 B 一定优于 A 或 C；
不选择 R4；
不分配 RQ ID；
不创建实验目录；
不修改 R3 harness；
不复用 R3 campaign 作为新证据；
不把 R3 现象重写成产品需求；
不将本文自身登记为研究状态。
```

## 6. 外部审查需要检查的问题

1. 本文是否把 fixture-slice bounded 结论写成了更宽的主张？
2. confirmed knowledge 是否仍保持“有界边界事实”而非普遍规律？
3. 候选方向是否只登记而不暗中选择？
4. B 线是否被过度抬升为 R3 的必然延伸？
5. PALACE 是否被意外重新接入？
6. UB-1..UB-7 是否仍保持 NOT STARTED / NOT SELECTED？
7. 本文是否未授权任何实验、实现或状态迁移？

## 7. Human decision points

在本文通过外部审查后，human 可选择：

```text
1. 接受本文为 Post-R3 Research Direction Gate 的登记输入；
2. 要求修订；
3. 拒绝；
4. 从候选空间中选择一个或多个方向进入独立 opening draft；
5. 暂不选择，维持 R3 CLOSED / no active successor；
6. 将方向登记写入 RESEARCH_STATE.md，或仅保留为 governance 记录。
```

在这些决定之前，SimiGo-Lab 的研究状态仍应保持：

```text
R3 = CLOSED；
Post-R3 Direction Gate = SUSPENDED AS ROUTE INPUT；
successor research line = NOT SELECTED；
RQ successor = NOT ASSIGNED；
experiment authorization = NONE。
```
