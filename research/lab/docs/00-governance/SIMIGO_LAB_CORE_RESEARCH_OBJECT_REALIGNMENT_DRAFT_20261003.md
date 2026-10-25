# SimiGo-Lab Core Research Object Re-alignment — Execution State × Information Space × Continuation

日期：2026-10-03  
状态：**REV.2 / PARTICIPANT PROPOSAL / HUMAN REVIEW REQUIRED**  
性质：研究对象定义图草案。  

本文不重跑、不复审、不改写 R3；不开启 R4；不分配 RQ ID；不授权实验、
实现或存储选型。  

**PALACE 边界修正**：PALACE 不再被排除在核心研究对象之外。它是
Information Space 的候选实体/承载层，必须在概念定义中进入
`Execution State × Information Space × Continuation` 的主轴；但本文
仍不授权 PALACE 实现、迁移、选型或系统集成。

## 0. Human redirection

Human 已指出：Post-R3 Direction Gate 仍从 R3 已有证据出发选择后续线，
这会使研究继续围绕 R3 已经研究过的问题，而不是回到 SimiGo 的核心问题。

Human 进一步修正：此前“暂时不要碰 PALACE”的方向建议是错误的。
SimiGo 的核心不是孤立的 Execution State 研究，而是：

```text
Execution State
      ×
Information Space / PALACE
      ×
Continuation
```

如果把 PALACE 人为隔离到后续阶段，会再次把 Information Space 抽象成
普通实验 fixture，使核心问题退化为条件击穿观察。

本次偏差已另行登记为
`SIMIGO_LAB_RESEARCH_DIRECTION_ACCIDENT_RESEARCH_OBJECT_DRIFT_DRAFT_20261003.md`；
事故类型为 **Research-Object Drift**。

因此本文把上一步方向调整为：

```text
不再先问“如何利用 R3”；
先重新定义核心研究对象。
```

前一个 Post-R3 Direction Gate 草案保留为历史讨论材料，但不再作为
下一步方向选择的输入。

## 1. 核心偏移声明

R3 的实际研究对象被收窄为：

```text
Information Space 变化
      ↓
I / A / C 条件是否被击破
      ↓
differential sensitivity
      ↓
composite interaction
```

这不是 SimiGo 的核心研究对象。

核心研究对象应重新表述为：

```text
Execution State + Information Space 变化
      ↓
原有计算能否继续；
若能继续， continuation 语义如何定义、判定与继承。
```

其中 Information Space 不只是抽象变化符号；在 SimiGo 系统语境中，
PALACE 是其候选实体/承载层，可提供文件、记录、历史、索引、摘要、
session 上下文和变化记录等 continuation-relevant information。

所以：

```text
研究对象 = continuation；
不是 change detection；
不是 condition-status catalog；
也不是 interaction taxonomy。
```

## 2. 研究对象定义图

```text
                 SimiGo
                   │
      ┌────────────┴────────────┐
      │                         │
Execution State          Information Space
      │                         │
execution position          PALACE candidate
execution context           files / records
logical branch              history / index
resources                   summaries / changes
      │                         │
      └────────────┬────────────┘
                   │
             Continuation
                   │
                   ▼

        ES₀ 已在 IS₀ 上计算到 position p
                   │
         Information Space 变化
                   ▼
                IS₀ → IS₁
                   │
                   ▼
  Continuation question:

  resume(ES₀, IS₁, p)
      是否仍可断言为 THIS computation 的合法延续？

  若可断言：
      它继续了什么？
      继承了什么？
      与什么 reference 等价或可区分？

  若不可断言：
      失败语义是什么？
      是 fail-closed、可恢复、需重算，还是语义分支终止？
```

本文不定义 `resume`、reference、等价关系或失败语义；这些是下一步
概念定义的对象。

## 3. 必须区分的三层

### 3.1 Eligibility layer

既有 I/P/A/C 契约关系，以及 R3 中观察的 I/A/C 条件状态，属于候选
资格/可断言性观察层。

```text
I / P / A / C = continuation eligibility 的候选观察面
```

但它们本身不是研究终点。

### 3.2 Continuation layer

资格判定之后，核心问题才出现：

```text
若 eligibility = true，
    execution 是否真的可以继续？
    继续后的状态、位置、输入、产物与责任关系是什么？
```

不能把“条件没坏”直接读成“计算安全延续”。

### 3.3 Correctness / semantics layer

延续是否正确，需要独立定义比较对象。可能的 reference 不得现在选定，
但至少应作为定义项登记：

```text
resume vs recompute-from-prefix
resume vs fresh execution under IS₁
resume vs declared continuation semantics
resume vs lineage/provenance-preserving reference
```

选择哪一个，或如何组合，属于后续 human decision。

## 4. 对 I/A/C 的重新定位

不能继续假定：

```text
I ∧ A ∧ C = 可以 continuation
```

也暂不反向主张它们不必要。

正确位置是：

```text
I/A/C（以及契约中的 P）
      ↓
候选 continuation eligibility 条件
      ↓
需要重新检查它们对 continuation 的角色：
      necessary？
      sufficient？
      only observable proxy？
      only fail-closed guard？
```

因此：

- 条件不成立时，只能得到“当前规则不允许断言合法延续”或
  fail-closed，不能直接推出“任何形式的重启都不可能”；
- 条件成立时，也只是进入 continuation 研究的起点，不是结论。

## 5. Continuation 必须回答的最小概念问题

### Q0 PALACE 在 continuation 中承担什么？

PALACE 不应被当作外部知识库附加物。它应作为 Information Space 的
候选实体进入核心定义，并回答：

```text
哪些 Information Space 历史/结构/索引/状态是 continuation 必需的？
哪些变化必须被记录才能判断 ES 仍可延续？
哪些变化发生后，ES 只能 fail-closed 或重算？
ES 如何得知 Information Space 已变化？
ES 如何引用 PALACE 中的记录而不把 PALACE 变成第二执行引擎？
```

这些问题只进入概念定义；本文不选择 PALACE 的存储结构、API、产品
形态或集成路径。

### Q1 “继续”的对象是什么？

必须区分候选含义，不能混用：

```text
不重算已完成前缀；
不丢失已完成 computation；
保持同一 logical branch；
保持同一 lineage / provenance；
保持 execution position 与 next input；
保持 material/resource state；
从既有位置产生后续状态；
结果与某个 reference 具有待定义关系；
runtime 能恢复；
任务/计算可以接手。
```

这些不是同义词。下一步必须选择或分层组合。

### Q2 “条件约束不变或延续”是什么？

要回答：

```text
条件约束是 continuation 的必要条件、充分条件，
还是只是当前操作化的 guard？
条件成立是否授权继续？
条件破坏是否必须终止？
条件状态是否应输入 continuation correctness 判定？
```

### Q3 “继续计算”的可验证判据是什么？

概念层至少要定义：

```text
被延续的计算是什么；
执行位置是什么；
Information Space 变化模型是什么；
resume 的输入/输出面是什么；
和什么 reference 比较；
等价/合法/失败如何判定。
```

在这些问题定义之前，不应设计实验。

## 6. R3 资产的重新定位

R3 保留为已关闭历史分支和实验资产，但不再定义下一条研究线。

正式定位：

```text
R3 = CLOSED bounded exploratory / boundary characterization branch
```

它产生的是 IS change 与条件观察之间的局部边界证据；它不是 SimiGo
核心 continuation 命题的验证，也不是 PALACE 集成研究。

| R3 资产 | 重新定位 |
| --- | --- |
| R3-2 BROKEN 侧 | 候选 eligibility 条件的可击穿性观察，不是 continuation 不可行证明 |
| R3-3 HOLD 侧 | 候选条件未击穿观察，不是 continuation 安全性证明 |
| IS-X X-08/X-09 | eligibility 判定在复合变化下的组合现象，不是 continuation correctness 结果 |
| I/A/C 词汇 | 候选观察面，不是 continuation 语义本身 |
| fixture / harness / audit 方法 | 只能在新 provenance 与新对象定义后另行评估复用 |

不能因为 R3 门控严格，就把它的研究对象升格为 SimiGo 核心路线。

## 7. 明确不做

```text
不重跑 R3；
不复审 R3；
不改写 R3 结论以挽救其地位；
不做 R4；
不做 interaction expansion；
不因已有投入把 R3 强行变成核心成果；
不选择 semantic oracle；
不实现 resume；
不修改 Execution State Contract；
不分配 RQ ID；
不授权实验。
```

补充：不排除 PALACE 进入核心概念定义，但不实现、不迁移、不选型、
不做系统集成。

## 8. 下一个最小动作

本文通过 human review 后，下一个最小动作是：

```text
起草 Core Continuation Research Object Definition：
  - 一句话研究对象；
  - Information Space / PALACE 在 continuation 中的概念位置；
  - resume/reference/correctness 的概念签名；
  - continuation 的分层含义；
  - eligibility 条件与 continuation correctness 的关系；
  - 明确非主张清单。
```

该步骤仍不进入实验设计。

在任何后续设计冻结前，必须先通过
**Research Object Alignment Gate**，确认计划仍回答核心 continuation
对象，而不是漂移后的条件敏感性代理问题。

## 9. Human decision points

human 需要决定：

```text
1. 是否接受“研究对象 = continuation，而非 change detection”；
2. 是否接受“PALACE 属于 Information Space / 核心研究对象，而不是被隔离的外部附加物”；
3. 是否暂停 Post-R3 Direction Gate 作为方向选择输入；
4. 是否授权起草 Core Continuation Research Object Definition；
5. 是否接受 Research Object Alignment Gate 作为 design freeze 前置；
6. 是否暂缓为后续线分配 RQ ID；
7. 是否继续冻结实验授权。
```

在 human 决定前，状态保持：

```text
Core Research Object Re-alignment = DRAFT / HUMAN REVIEW REQUIRED；
Post-R3 Direction Gate            = SUSPENDED AS ROUTE INPUT；
R3                                = CLOSED historical branch；
R3 claim scope                    = bounded exploratory / boundary
                                    characterization，非核心 continuation
                                    validation；
Research Direction Accident       = DRAFT RECORD /
                                    Research-Object Drift；
Research Object Alignment Gate    = PROPOSED PRE-DESIGN-FREEZE
                                    REQUIREMENT；
successor RQ                      = NOT ASSIGNED；
experiment authorization          = NONE。
```
