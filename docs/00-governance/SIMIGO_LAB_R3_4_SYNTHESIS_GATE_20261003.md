# SimiGo-Lab R3-4 Synthesis Gate — Bounded Synthesis and Boundary Adjudication

日期：2026-10-03（rev.2；rev.1 同日）
状态：**REV.2 / HUMAN REVIEW VERDICT REGISTERED / 收官依据**
（human review 判定 = SUPPORTED / BOUNDED / PASS WITH REVISIONS——措辞
边界修订，非重实验、非推翻综合门；rev.2 应用四处修订后作为 R3 收官
依据；收官声明本身另行待 human 指令）

**rev.2 修订记录（human review，全部为措辞边界收紧——防止从「有界证据」
滑向「普遍命题」）**：

```text
R3-4-R1  改变点 1 限定为「单变量预测合成非封闭」——P_comp 对该复合
         操作实例的合成预测不封闭（当前 fixture/representation/
         operation pair 下无法由两个单变量结果机械推出联合结果），
         非 Cons 本身或条件系统的一般代数性质
R3-4-R2  改变点 2 收紧为「本测试组合中联合效应表现出顺序敏感性；
         本 slice 内不能将复合变化建模为无序操作集合」——一组逆序
         对照不足以推出所有复合变化效应均为序列函数的一般命题
R3-4-R3  「任何涉及复合变化的边界刻画必须携带顺序参数」收紧为「对
         已表现出顺序敏感性的复合变化，后续边界刻画必须保留操作
         顺序信息；当前证据不足以证明所有复合变化均具有该要求」
R3-4-R4  「A/C 未见交互」固定为正式边界语言：「在当前已测试的 A/C
         组合中未观察到 interaction；不能据此排除 A/C interaction」
R3-4-R5  R2 候选定义支持表述固定为「作为当前 fixture、representation、
         operation catalog 与 observation procedure 下的操作化刻画，
         获得 bounded empirical support；R3-2/R3-3/IS-X 未发现当前
         探针范围内的反例」——「无反例」永远带探针域
```
（本门=有界综合+边界裁定；收官结论不在本门，待 human review 后另行）
授权：human「开启 R3-4」（2026-10-03），任务定性（human 预定）：R3-4
不是「证明 R3 成功」，而是真正的 **bounded synthesis / boundary
adjudication gate**；问题收窄（human 逐字）：**「在当前 fixture、
representation 和既有 observation procedure 下，R3-2、R3-3 与 IS-X
是否足以支持一个关于 differential sensitivity profile 的有界综合结论；
IS-X 所发现的 interaction 是否改变此前对 Cons 条件边界的解释。」**

## 0. 综合范围（human 可/不可清单，逐字锁定）

```text
可综合：
  当前 fixture 中的 differential sensitivity profile
  当前表示边界下的 interaction evidence
  当前操作化条件的边界
不可综合（逐条排除，本门全程遵守）：
  Cons 的普遍定律
  I ∧ A ∧ C 的充分/必要性
  condition correctness / minimality / completeness
  一般 interaction law
  一般非交换性
  continuation implication
  PALACE / IPAC / Route
```

## 1. 证据清单（三侧，各自状态/证据级/边界）

| 侧 | 战役 | 状态 | 证据级 | 边界 |
|---|---|---|---|---|
| BROKEN 侧 | R3-2（14 cell） | SUPPORTED / fixture-slice bounded / second layer AUDIT PASS 16/16 / FORMALLY CLOSED | 9/9 定向变化以预注册签名击穿定向条件、其余条件不动；控制全持有 | instance-level；符号名锚引用；单 ES；文件型 IS；零模型 |
| HOLD 侧 | R3-3（14 cell） | NO-COUNTEREXAMPLE / bounded / second layer COMPLETE / FORMALLY CLOSED | 10/10 未测 HOLD 侧实例零击穿；三正控逐条件活性证实；零 INCONCLUSIVE | 探针=规则误实现最可能破的侧面；检出力=操作化边界；共享盲区 B-1..B-6 登记 |
| 交互侧 | IS-X Attempt #1（16 cell）+ Attempt #2（6 cell 确认） | #1 INCONCLUSIVE（永久保留）；#2 CONFIRMATION INTERACTION-FOUND；second layer PASS WITH BOUNDED CONFIRMATION | 11/12 pair ADDITIVE（#1）+ **X-08 CONFIRMED MASKING / X-09 CONFIRMED ADDITIVE（#2 复现）**；修复链完整（defect→R1/R2→reaudit 9/9→fresh→zero CI→audit 14/14） | 单操作对；#1 与 #2 分立不合并（禁 22-cell 合并读法）；交互结论 bounded 于 fixture/表征/操作对 |

## 2. 综合一 — Differential Sensitivity Profile（有界）

在当前 fixture 结构类、共享表征边界（符号名锚引用/文件型 IS/字节摘要
绑定）与预注册观察程序下，Execution State 条件满足性对 Information
Space 变化的**差分敏感性画像**呈三区结构：

```text
区 1（单变量定向侧，R3-2）：
  身份类变化 → I 击穿（I-MISMATCH / I-NF / I-AMBIG）
  锚定类变化 → A 击穿（A-NF / A-SUB）
  许可类变化 → C 击穿（C-REF-NOT-FOUND / C-INV）
  ——定向、带机械签名、互不溢出（9/9）

区 2（单变量 HOLD 侧，R3-3）：
  未引用对象增删改 / 死索引 / 同内容重复候选坍缩 / 字段保持扩展 /
  前置与谱系等价迁移 / 未目标 invalidation / scope-tag·区域增补
  → 全部零击穿（10/10）

区 3（复合变化侧，IS-X）：
  多数组合 ADDITIVE（单变量预测机械可合成——含朴素双 BROKEN 叠加，
  反滑坡条款经受实证）
  但存在已确认的例外：X-08 MASKING（两个单独足以击穿 I 的操作在
  Δ2→Δ3 顺序下联合使 I 恢复 SATISFIED，解析收敛于冲突记录，H-X1
  预登记期望逐项吻合）+ X-09 逆序 ADDITIVE（I-NF）——
  联合行为**顺序敏感**且**不能由冻结单变量机械组合规则 P_comp
  独立预测**
```

**逐条件 profile**（rev.2 R3-4-R4 措辞固定）：

| 条件 | 定向击穿（R3-2） | HOLD 侧（R3-3） | 交互行为（IS-X） |
|---|---|---|---|
| I | I-MISMATCH / I-NF / I-AMBIG | 谱系迁移/同内容重复候选/字段扩展均不击穿 | **可被组合遮蔽**（X-08）；逆序不遮蔽（X-09） |
| A | A-NF / A-SUB | 等价迁移不击穿（绑定=可解析+内容同一，非存储地址） | **在当前已测试的 A/C 组合中未观察到 interaction；不能据此排除 A/C interaction** |
| C | C-REF-NOT-FOUND / C-INV | 未目标 invalidation/增补类不击穿 | **在当前已测试的 A/C 组合中未观察到 interaction；不能据此排除 A/C interaction** |

## 3. 综合二 — Boundary Adjudication：IS-X interaction 是否改变此前对 Cons 条件边界的解释

**判定：是——在三个具体且已登记的点上改变；在两个根本点上不改变。**
（rev.2：改变点 1/2 措辞按 R3-4-R1/R2/R3 收紧）

**改变点 1（单变量预测合成非封闭）**：此前的画像（R3-2/R3-3 后）隐含
「单变量敏感性刻画即边界」。IS-X 证明的是：**单变量预测规则 P_comp
对该复合操作实例的合成预测不封闭**——在当前 fixture / representation /
operation pair 下，P_comp 无法由两个单变量结果机械推出联合结果
（X-08 P_comp≠actual）；顺序是边界画像的一部分。差分敏感性画像以三区
结构表述，单变量两区在本 slice 内不再充分。**本发现不构成对 Cons 本身
或条件系统的一般代数性质的陈述。**

**改变点 2（顺序敏感性进入画像）**：已测试的操作组合（X-08/X-09 同操
作逆序对）的联合效应对执行顺序敏感（X-08 MASKING vs X-09 ADDITIVE，
复现级）——因此**在本 slice 内不能将复合变化建模为无序操作集合**。当
前仅有一组逆序对照，不足以推出「所有 IS 复合变化的效应均为序列函数而
非集合函数」的一般命题。**对已表现出顺序敏感性的复合变化，后续边界刻
画必须保留操作顺序信息；当前证据不足以证明所有复合变化均具有该要求。**

**改变点 3（操作化边界具体化）**：X-08 使「解析成功 ≠ 谱系正确」从
抽象限定变为**有一手实例的操作化边界**——I-condition（按 Spec=身份可
评估性）在联合态恢复 SATISFIED 而解析收敛于冲突记录：机械条件满足性
不追踪语义层面的身份损伤。条件满足性是 evidence-condition 概念，不是
semantic-correctness 保证。

**不改变点 1（条件级观察词汇保持有效）**：MASKING 本身是**条件级现
象**（I 从「 constituent 单独可破」变为「联合 SATISFIED」，由 I/A/C
词汇完整表达）——交互没有产生任何超出条件词汇的不可归类现象。R2 候
选形式未被 RQ3-4 形态反例挑战（「IS changed ∧ Cons changed ∧ I=A=C
=true」未出现；X-08 中 Cons 全程保持 true）。

**不改变点 2（判定纪律不变）**：「判定对象=条件可满足性而非输出变
化」「实例级探针非条款级验证」「检出力=操作化边界」等全部既有纪律对
交互侧同样适用；交互发现不豁免任何限缩读法。

## 4. R3 终局四问（R3-0 §6，逐条终答）

```text
RQ3-1  IS 变化能否在 ES 固定时改变 Cons(ES,IS)？
       = 能（R3-2 定向击穿 9/9；IS-X 交互侧在条件级观察）。
RQ3-2  哪些 IS change 分别影响 I/A/C？
       = 单变量层：定向映射逐一确认（区 1）；复合层：多数 ADDITIVE，
         但存在顺序依赖的 MASKING（区 3）——联合效应不由 P_comp 独立
         预测。
RQ3-3  哪些 IS change 不影响 Cons？
       = 区 2 全部（10/10）+ 区 3 的 ADDITIVE 多数（含 X-09）。
RQ3-4  是否存在无法由 I/A/C 解释的 Cons change？
       = 本 slice 内未观察到——X-08 交互完整落在 I/A/C 条件词汇内
         （MASKING=条件级现象）；R2 候选形式未受「IS changed ∧ Cons
         changed ∧ I=A=C=true」形态反例挑战。附注册边界：检出力=
         操作化边界，「条件被违反但评估器无从表示」的形态不可及。
```

## 5. 判定（预注册四态出口）

**主判定（human 收窄问题）= SUPPORTED（bounded）**：三侧证据（各自
独立审计通过、交互侧复现级确认）**足以支持**一个关于 differential
sensitivity profile 的有界综合结论（§2 三区画像+逐条件 profile）；且
IS-X interaction **确实改变**此前对 Cons 条件边界的解释（§3 三个改变
点），改变方式已逐项登记。

**对 R2 Cons 候选定义的关系（R3-0 §8 框架映射；rev.2 R3-4-R5 措辞固
定）**：候选形式（Cons ⟺ I∧A∧C，机械操作化）**作为当前 fixture、
representation、operation catalog 与 observation procedure 下的操作化
刻画，获得 bounded empirical support；R3-2/R3-3/IS-X 未发现当前探针
范围内的反例**——定向/HOLD/交互三侧一致。两项注册边界使其不得升格：
①操作化边界（满足性≠语义正确性，X-08 具体化）；②单变量预测合成非封
闭（P_comp，含顺序敏感性）。**禁止**读作正确性/最小性/完备性证明；
「无反例」永远带探针域；IPAC 保持 OPEN/NONBINDING 不变。

## 6. 非主张清单（§0 不可综合清单的判定侧落实）

本综合**不主张**：Cons 普遍定律；I∧A∧C 充分/必要；condition
correctness/minimality/completeness；一般 interaction law；一般非交换
性；continuation implication（条件破坏⇒延续失败未测，R3 无模型）；
PALACE/IPAC/Route 含义；产品/普适/其它表征外推（内容寻址变体 defer）。

## 7. 对后续的关系

- 本 gate 交付 = 综合与边界裁定；**收官结论另行**——待 human review
  本综合后，由 human 决定以何种形式收官（R3 正式关闭声明+开放边界登
  记：内容寻址表征/并发/时间动态/多操作对/语义正确性 oracle 均为登记
  在案的未测边界）；
- X-08 的语义层追问（冲突记录下的「谱系正确性」）需要独立 semantic
  correctness oracle——属未来独立研究问题，非 R3 范围；
- R3 全程零模型、零 Relation carrier、零 PALACE——此边界使全部结论
  bounded 于信息空间机械层，不外推。

## 8. 输入清单

- R3-2 结果+second layer（FORMALLY CLOSED）；R3-3 结果+second layer
  （FORMALLY CLOSED，含三区结构前身与共享盲区 B-1..B-6）；IS-X 设计
  rev.2/Attempt #1/#2 结果/second layer（PASS WITH BOUNDED
  CONFIRMATION）；R3-1 Spec rev.2（操作化定义）；R2 rev.2（候选定义，
  引用不修改）；R3-0（终局四问与四态出口框架）
