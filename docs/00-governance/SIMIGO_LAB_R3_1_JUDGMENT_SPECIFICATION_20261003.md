# SimiGo-Lab R3-1 Judgment Specification — Condition Observability Specification

日期：2026-10-03（rev.2；rev.1 同日）
状态：**RATIFIED / FORMAL JUDGMENT RULE**（独立审查 PASS WITH
RECOMMENDATIONS 后，rev.2 机械补入三项收紧条款 H-1/H-2/H-3——零命题
变更；实验进入仍须独立 human 授权）
授权：human「R3-1 = AUTHORIZED FOR SPECIFICATION PRODUCTION ONLY"
（2026-10-03）——授权粒度锁定为规范生产；**不授权**实验、代码、harness、
数据采集、运行、R3-2/R3-3/R3-4。
输入：R3-0 设计（@1c8c463）、R2 rev.2 形式化、R3-1 Gate Review
（NO BLOCKER / READY TO OPEN）及其五项强制内容登记。

**rev.2 修订记录（独立审查 SIMIGO_LAB_R3_1_SPEC_REVIEW_20261003.md
发现，全部为收紧性条款）**：

```text
H-1  §5.4 新增：ΔIS_class 构造时锁定义务（防 post-hoc control）
H-2  §6.1 schema：instrument_doubt 标志 + 仪器疑云签名记录位置显式化
H-3  §3.2 C-DECL：「机械可评估」显式分类判据
```

## 0. 本规范的地位与边界

本文档 = R3-1 的交付物：**判定规范（judgment specification）**——把
R2 rev.2 封存的候选条件转写为可观察、可记录、可判定的操作性规范。

- 本规范**不实现、不运行、不采数**；其中为未来 R3-2 执行登记的仪器化
  要求（§4.3）仅为规范条文，零代码落地。
- 本规范不修改 R2 rev.2 的 Cons 候选定义，只对其三条件给出判定程序。
- 本规范不预设任何 cell 的结果；全部签名类别是**观测类目**，不是预期。
- 规范通过下一次独立审查后，才考虑后续实验授权。

## 1. I-condition 判定规范

### 1.1 判定问题

> ES 的身份/谱系判据，在当前 IS 语境下是否**仍可评估**？
> （判定对象是可评估性，不是身份真值——R2 rev.2 a 子句原文。）

### 1.2 身份判据承载物枚举

按 G-δR Role(I)（引用不重定义），ES 的身份/谱系判据由以下承载物构成，
逐一登记其**所在位置**（ES record 内部 / IS 内容）：

```text
I-EV-1  模型绑定证据（I-1）：ES record 声明的模型身份 +
        （如声明为 IS 依赖）IS 侧模型身份声明
I-EV-2  谱系绑定证据（I-2）：ES record 声明的谱系引用
        （前驱状态/来源记录的引用——可指向 IS 内对象）
I-EV-3  载荷完整性交叉核对证据（I-3）：record↔carrier 对应材料
        （formation 时记录的对应关系声明）
```

### 1.3 评估程序

对每个 I-EV-x，执行其声明式评估规则（formation 时随 state 登记）：

1. 证据完全在 ES record 内部 ⇒ **自足评估**：I 子条件 SATISFIED
   （IS 变化无法触及——这是合法路径，见 1.5 反复杂化条款）。
2. 证据含指向 IS 的引用 ⇒ 解析引用，按 1.4 签名归类。
3. 评估规则本身引用的 IS 结构不存在 ⇒ I-UNSTRUCT。

### 1.4 可观察签名（观测类目）

```text
I-SATISFIED   全部证据可评估且解析无歧义
I-NF          IS 依赖的身份引用解析返回 not-found
I-AMBIG       引用解析到多个冲突候选（provenance conflation，
              Gδ-I 先例）
I-MISMATCH    模型绑定结构比对失败（J-I1/I2 先例：声明身份 vs
              IS 侧声明身份不一致）
I-UNSTRUCT    评估规则所依赖的 IS 结构不存在，评估无法执行
```

I-condition 判定 = 全部 I-EV-x 无 I-NF / I-AMBIG / I-MISMATCH /
I-UNSTRUCT。**禁止语义判断**（模型/评审者对身份是否「合理」的判断
不作输入）。

### 1.5 反复杂化条款（human 指令，逐字义务）

> **不得为了让 I 更「有意义」而人为增加复杂条件。**

- 若所选 ES/IS 表征下身份证据完全自足，则 I-condition ≡ TRUE 对该
  slice 内一切 IS 变化成立——**如实登记为 I-INVARIANT 结果**，不得
  为产生「破坏」而注入 IS 依赖、加设间接引用或改造表征。
- `I(record) ≡ TRUE` 是有效研究结果；其真正的研究问题是该事实对
  `I ∧ A ∧ C` 候选关系意味着什么（进 RQ3-4 / R3-4 综合）。

## 2. A-condition 判定规范

### 2.1 判定问题

> A-1 所绑定的语义内容，是否仍是 IS 当前边界内的可引用信息
> （存在、可寻址、未被静默替换——R2 rev.2 b 子句）？

### 2.2 判定立场（Gate Review spec 决策 #1）

- 引用解析**必须走 ES 自身存储的引用路径**（ES→IS 方向）。
- 观察者可另持只读哈希作**审计**，但**不得作为判定输入**——否则判定
  平凡化，且构成 forbidden channel（观察通道代替状态自身解析能力）。

### 2.3 比较基线（Gate Review spec 决策 #2）

- 「未被静默替换」的判定基线 = **formation 时记录的内容摘要**
  （state 形成时的 provenance 材料）。
- 禁止事后补造基线（no construct-then-claim）。
- 若 ES record 未留 formation 摘要 ⇒ A 记 **A-NOT-EVALUABLE**
  （该 state 的 A 条件不可判定——如实登记，触发 §6.3 出口规则）。

### 2.4 解析语义按引用形式分派

基线随 formation 声明的**引用形式**分派（表征层事实，规范不统一假设定）：

```text
内容寻址引用（address=digest）：解析成功即内容同一，A-SUB 结构上
  不可能——这是表征选择的性质，如实登记（不视为规范缺陷）。
直接地址/符号名引用：解析后比对 formation 摘要，A-SUB 可观测。
```

### 2.5 可观察签名

```text
A-SATISFIED    引用在 IS 边界内解析成功且内容 == formation 摘要
A-NF           引用不解析（目标删除 / 移出当前 IS 边界 / 不可访问）
A-SUB          引用解析成功但内容摘要 ≠ formation 摘要
               （同一地址不同内容——PA-2 外部化；「silent vs 有记录」
               作为描述性标注记录，不影响满足性判定）
A-NOT-EVALUABLE  无 formation 摘要基线，判定不可执行
A-UNRESOLVABLE   引用形式畸形等非 ΔIS 原因导致无法解析
               （仪器疑云路径 → §5.3）
```

A-condition 判定 = A-SATISFIED。**禁止**用模型行为判断锚是否「仍然
有效」。

## 3. C-condition 机械化边界（Gate Review spec 决策 #3）

### 3.1 判定问题

> C-1 接续所依赖的前置语义条件（settled results、preconditions），
> 在 IS 中是否**仍成立**——按机械化边界判定？

### 3.2 机械可查形态（穷尽列举，「仍成立」只按此判定）

```text
C-REF      前置引用解析：settled result / precondition fact 的引用
           found / not-found（R-B1 V-N relation-not-found 先例）
C-INV      invalidation / supersession 记录存在性：IS 中是否存在
           以该 settled result 为目标的废止/取代记录
           （R2 Task 3 c 类「invalidation 记录出现」的可观察化）
C-DECL     formation 时声明的 applicability 条件中**机械可评估者**
           的核对（范围标签/有效期/依赖引用等）。
           机械可评估判据（rev.2 H-3）：声明条件为机械可评估，当且
           仅当存在 formation 声明的确定性评估程序、其输入仅为 IS
           内容、零模型/语义判断参与——三者缺一即归 C-NOT-EVALUABLE
```

C-condition 判定 = 全部前置引用 C-REF found ∧ 无 C-INV 记录 ∧
C-DECL 全部通过。

### 3.3 禁止项与边界

- **模型语义判断禁作判定输入**——「内容是否『真的』还成立」不由模型
  或评审者判断（防输出级观察回流，总判定纪律）。
- 若某 settled result 仅声明**需语义判断的 applicability 条件** ⇒ 该
  state 的 C 记 **C-NOT-EVALUABLE**（如实登记，触发 §6.3）。
- 语义级 C 判定 = 边界修订，走 stop/revise 路径，不在 R3-1 内静默扩展。

## 4. 只读观察义务（Gate Review 强制内容 #4）

### 4.1 观察不变更 IS

- 一切观察（引用解析、摘要比对、记录检索）为只读；
- 观察 IS 全域（或受影响范围）写前/写后哈希比对，任何变更 ⇒ 仪器疑云
  （§5.3）；
- 隔离资源计数核验沿用（204→204 先例）。

### 4.2 通道分离

- 观察通道与 continuation 通道分离；观察基础设施不得成为 continuation
  的依赖（forbidden-channel checks 先例沿用）。

### 4.3 未来 R3-2 执行的仪器化要求（本规范登记，零代码落地）

- 每 cell run-UUID + 独立观测文件（append-only）；
- 单调钟计时（ContinuousClock），墙钟仅辅助；
- 判读脚本与判读输入分离，判读不读旧 observation 作判定输入
  （Replication Audit 原则沿用）。

## 5. Control 漂移条款（Gate Review 强制内容 #5）

### 5.1 Control 家族（三层）

```text
K-0 null-change Control：   (ES,IS₀)→(ES,IS₀)，同流程 ΔIS=0；
                            预期三条件满足性全部不变
K-1 良性变化对照：           纯增量 / 不触及锚·谱系·前置 / 可引用性
                            等价迁移——ΔIS≠0 但预测条件不变
K-2 R3-N 反证方向：          专项搜索 ΔIS≠0 而 Cons 不变的 non-break
                            案例（边界研究义务，非可选）
```

### 5.2 良性对照的双重读法

K-1 出现条件变化 ⇒ 二选一，按证据归入：归因失败（有混淆源）⇒
INCONCLUSIVE；或发现候选条件集之外的依赖（干净归因）⇒ **RQ3-4 素材**
（登记，不改判据）。

### 5.3 漂移处置（预注册）

K-0 出现**任何**条件满足性变化 ⇒ 仪器疑云 ⇒ **该批次全部
INCONCLUSIVE**，不进入判读（仪器审计先例：P5 audit、b3 异常处置）。
A-UNRESOLVABLE / I-UNSTRUCT 等非 ΔIS 原因签名同样走仪器疑云路径。

### 5.4 ΔIS 类别构造时锁定义务（rev.2 H-1）

cell 的 ΔIS_class 在**构造时登记并锁定，先于任何条件评估**；禁止依据
评估结果重分类（例如：IS-I cell 未击穿 I 时，不得事后改判为 K-1 良性
对照）——否则 Control 家族被结果反向定义（hidden post-hoc control）。
类别锁定先于评估，是 per-cell 记录 schema（§6.1）的构造顺序义务。

## 6. 四态出口与失败规则规范化（Gate Review 强制内容 #6）

### 6.1 Per-cell 记录 schema（「可记录」的落实）

每 cell 记录：

```text
{ cell_id, run_uuid, es_id,
  ΔIS_class ∈ {IS-I, IS-A, IS-C, IS-B, IS-X, K-0, K-1}
    〔构造时锁定（§5.4），先于任何条件评估〕,
  I  ∈ {SATISFIED, BROKEN, NOT-EVALUABLE} + 签名类别,
  A  ∈ {SATISFIED, BROKEN, NOT-EVALUABLE} + 签名类别,
  C  ∈ {SATISFIED, BROKEN, NOT-EVALUABLE} + 签名类别,
  instrument_doubt ∈ {NO, YES}
    〔rev.2 H-2：YES = 出现 A-UNRESOLVABLE / I-UNSTRUCT 等 §5.3
      签名；该签名按 NOT-EVALUABLE + 签名类别记录，cell 判定 =
      INCONCLUSIVE〕,
  Cons = I ∧ A ∧ C 的机械合成,
  is_观察前后哈希, 备注（描述性标注，不作判定输入） }
```

NOT-EVALUABLE 不是 BROKEN——它回答的是 R3-1 出口判据问题（该条件对
该 state 可否判定），触发 §6.3。

### 6.2 研究级四态出口（R3-4 综合适用；此处规范化定义）

判读对象 = taxonomy 预测结构（IS-I⇒I-break / IS-A⇒A-break / IS-C⇒
C-break / K-1⇒no-break / K-0 不变），**预测结构 ≠ 预期结果**：

```text
SUPPORTED            定向变化以干净签名归因击穿其定向条件；K-1 全部
                     no-break；K-0 稳定
PARTIALLY SUPPORTED  部分定向映射成立、部分不成立，且失败可干净归因
                     （含交叉敏感性发现：如 IS-C 变化也击穿 A）
NOT SUPPORTED        定向变化系统性不击穿其定向条件（如 I≡A≡C≡TRUE
                     对一切 IS 变化）——一致性边界在本 slice 内不呈
                     IS 依赖性，为实质性有界发现，进 RQ3-4/R3-4；
                     不得为「成功」而改表征或加条件
INCONCLUSIVE         K-0 漂移 / 不可归因击穿 / 仪器疑云 / NOT-EVALUABLE
                     大面积出现致判别力丧失
```

### 6.3 失败规则

- **失败有效性**：任何出口态均为有效结果，不得为使路线成立而修改判据
  （实验宪法条款沿用）。
- **R3-1 自身出口判据**：三条件对所选 state 类别**均可判定**
  （无结构性 NOT-EVALUABLE）⇒ R3-1 达成；存在结构性不可判定 ⇒ R3-1
  FAIL ⇒ 停止 / 修订边界（R3-0 §4.1 原文），不进入 R3-2。
- **I≡TRUE 专项**：I-INVARIANT 结果逐字登记；其含义分析（对候选关系
  意味着什么）属 R3-4 综合，不在规范生产或判读阶段改写 I 的定义。

## 7. Cons 判定程序摘要（单 cell）

```text
对固定 ES 与变化后 IS₁：
  1. 按 §1 评估 I-condition → I 状态 + 签名
  2. 按 §2 评估 A-condition → A 状态 + 签名
  3. 按 §3 评估 C-condition → C 状态 + 签名
  4. Cons(ES, IS₁) = I ∧ A ∧ C（机械合成，含 NOT-EVALUABLE 传播：
     任一 NOT-EVALUABLE ⇒ Cons = NOT-EVALUABLE，该 cell 不参与
     四态统计，进 §6.3 出口判据核算）
  5. 记录 per-cell schema；IS 观察前后哈希核验只读义务
```

## 8. 边界重申

- 本规范生产**仅此为止**：零实验、零代码、零 harness、零数据采集、
  零运行；R3-2 / R3-3 / R3-4 保持 LOCKED。
- 本规范已经独立审查（SIMIGO_LAB_R3_1_SPEC_REVIEW_20261003.md，
  PASS WITH RECOMMENDATIONS / 无 blocker），rev.2 补入三项收紧条款后
  **RATIFIED 为下一阶段正式判定规则**；**实验进入仍须独立 human
  授权**——RATIFIED 不构成任何实验许可。
- P / IPAC 最小性 / IPAC 冻结 / PALACE / MCP / Route A/B/C / 后端适配 /
  产品实现 / 性能 / 模型比较 / 完整恢复系统：全部维持排除。

## 9. 输入清单

- R3-0 设计（SIMIGO_LAB_R3_INFORMATION_SPACE_CONSISTENCY_BOUNDARY_
  DESIGN_20261003.md，GIT SEALED @1c8c463）
- R2 rev.2 形式化（SIMIGO_LAB_R2_IAC_INFORMATION_SPACE_CONSISTENCY_
  FORMALIZATION_20261003.md：三条件候选定义 + 破坏 taxonomy）
- R3-1 Gate Review（SIMIGO_LAB_R3_1_GATE_REVIEW_20261003.md：五项
  强制内容 + 三项 spec 决策）
- G-δR role taxonomy（引用不重定义）；R-B1 / R-C1 #4 / PA-2 / Gδ-I /
  Gδ-A / P7-1 J-I1/I2 / ES-R2 Gate B 历史签名先例（只作类目依据）
