# SimiGo-Lab IS-X Design Gate — Compound ΔIS Interaction Probe (Design Gate Deliverable)

日期：2026-10-03（rev.2；rev.1 同日）
状态：**RATIFIED / 正式设计**（human 亲自对抗审查 PASS WITH
RECOMMENDATIONS 后 rev.2 机械补入四项封口级加固——零命题变更；
**execution 仍须独立 human 授权**）
授权：human「走 α，但只开启 IS-X Design Gate，不开启实验」（2026-10-03）。
上游：R3-2（FORMALLY CLOSED，SUPPORTED/bounded）、R3-3（FORMALLY
CLOSED，NO-COUNTEREXAMPLE/bounded，second layer COMPLETE）、R3-1 Spec
rev.2（判定规则）、R3-0 §4.2（IS-X 原始定义与顺序纪律）。

**rev.2 修订记录（human 对抗审查 SIMIGO_LAB_ISX_DESIGN_REVIEW_20261003.md
判定 PASS WITH RECOMMENDATIONS/0 blockers，四项封口级加固）**：

```text
H-X1  §2a X-08/X-09 构造期 resolution expectation lock（conflict
      target/resolution order/expected resolution path/expected
      surviving anchor 全部由构造期状态追踪机械生成；实验后只允许问
      「实际解析==预登记期望？」，禁结果后解释）
H-X2  §4 ADDITIVE 双层定义（条件状态相等 AND 签名 ∈ P_comp sig-set）
      +分类互斥优先级（ATTRIBUTION-FAILURE → SIGNATURE-SHIFT →
      MASKING/EMERGENT-BREAK → ADDITIVE，任意结果机械落入唯一类）
H-X3  §1a INVALID-COMPOSITION 边界（仅构造失败；组合物成功形成后的
      evaluator 异常响应必须进实验结果，不得提前吞掉）
H-X4  §2a/§5 构造审计不变量（op 呈现/逐 op 效果探针/无未声明操作=
      replay 恒等/顺序匹配——非新实验 cell）
+     §2 X-12 结构性覆盖理由（exclusion-set 组合闭包关系）
```

## 0. 研究问题（human 收窄表述，逐字锁定）

> **当两个已分别具有预登记 HOLD/BROKEN 行为的 IS 变化组合发生时，其
> 联合效应是否仍可由各单变量条件的机械规则独立预测，还是出现新的
> 交互型条件行为？**

**反滑坡条款（预注册）**：同条件双 BROKEN 的朴素叠加（「IS-I 单独坏
+ IS-A 单独坏 ⇒ 联合都坏」）本身不惊奇、不自动回答 RQ3-4。有信息量的
结果是**与单变量预测不一致的联合行为**，或证明在预登记组合规则下联合
行为仍保持可解释。campaign 出口按此设计（§5）。

## 1. 组合语义（预注册）

```text
有序对 (op_a, op_b)：state = op_b(op_a(IS₀-copy))——顺序即语义，
  目录以有序对冻结（顺序依赖本身是可观测结构）。
兼容性：静态核验（本设计 §2 逐对注明）+ 执行期 pre-flight。
INVALID-COMPOSITION 机械边界（rev.2 H-X3）：
  仅当**组合构造失败**——某个冻结 op 在应用中抛错（如移动不存在
  的文件），组合物无法按预登记构造规则形成——才允许记
  INVALID-COMPOSITION。
  组合物**成功形成**后，evaluator 在 t₁ 的任何异常响应**必须进入
  实验结果**（真实交互分类路径），不得经「composition invalid」
  提前吞掉——后者可能恰是 EMERGENT-BREAK 或有价值的交互行为。
  组合态的结构缺失（如 index.json 缺失）按既有 in-cell 规则处理
  （H-C：I-STRUCT-REMOVED = I BROKEN），不属 INVALID-COMPOSITION。
```

## 2. 组合目录（冻结，12 有序对）

生成规则（机械）：从冻结单变量池（R3-2 目录 13 op + R3-N 目录 10 op）
按交互相关分层抽取——跨条件 BROKEN×BROKEN 每条件组合一例、同条件
BROKEN×BROKEN 每族一例、BROKEN×HOLD 遮蔽候选（静态可构造者）、
HOLD×HOLD、跨类一组；静态兼容性逐对核验（不兼容对排除，如
(C-Δ1,Δ6) 双序皆错——删除与移动同文件）。

| # | 有序对 | 逐 op 单变量预测 | 静态兼容性 |
|---|---|---|---|
| X-01 | (I-Δ2, A-Δ1) | I BROK{I-NF}；A BROK{A-NF}；C HOLD | 异键异文件 ✓ |
| X-02 | (I-Δ1, C-Δ2) | I BROK{I-MISMATCH}；C BROK{C-INV}；A HOLD | 异文件 ✓ |
| X-03 | (A-Δ3, C-Δ2) | A BROK{A-SUB}；C BROK{C-INV}；I HOLD | 异文件 ✓ |
| X-04 | (I-Δ2, C-Δ1) | I BROK{I-NF}；C BROK{C-REF-NOT-FOUND}；A HOLD | 异文件 ✓ |
| X-05 | (I-Δ1, I-Δ2) | I BROK{I-MISMATCH ∨ I-NF}；A/C HOLD | 异对象 ✓ |
| X-06 | (A-Δ3, A-Δ2) | A BROK{A-SUB ∨ A-NF}；I/C HOLD | 先改写后移动 ✓ |
| X-07 | (C-Δ2, C-Δ3) | C BROK{C-INV}；I/A HOLD | 同索引追加 ✓ |
| **X-08** | **(I-Δ2, I-Δ3)** | I BROK{I-NF ∨ I-AMBIG}；A/C HOLD | 先删后写冲突项 ✓ **遮蔽候选** |
| X-09 | (I-Δ3, I-Δ2) | I BROK{I-AMBIG ∨ I-NF}；A/C HOLD | 先写冲突后删原项 ✓ |
| X-10 | (Δ6, Δ10) | 全 HOLD | 异对象迁移 ✓ |
| X-11 | (Δ8, Δ9) | 全 HOLD | manifest 异字段 RMW ✓ |
| X-12 | (B-Δ1, A-Δ2) | A BROK{A-NF}；I/C HOLD | manifest 异字段 RMW ✓ |

控制：R32N-SANITY-A/I/C（三正控沿用）+ R32-K-0 ⇒ **16 cell**。
目录在本设计门 seal 时冻结；执行期不得增删改对、不得改序（§4a 沿用）。

## 2a. 构造期 resolution lock 与构造审计不变量（rev.2 H-X1/H-X4）

**X-08/X-09 构造期 resolution expectation（逐对机械生成，先于运行）**：

由冻结 op 的文件/索引效应做构造期状态追踪（construction-level trace
——验证组合机制，非判定预测），逐对锁定：

```text
X-08=(I-Δ2, I-Δ3) 组合态追踪：
  index["lineage-root"] = ["lineage/lineage-root.json",
                           "lineage/lineage-root-conflict.json"]
  文件存在性：orig=ABSENT（Δ2 已删）；conflict=PRESENT（Δ3 已写）
  ⇒ resolution expectation：candidate_count=1；
    resolved_target="lineage/lineage-root-conflict.json"；
    surviving_anchor=conflict 记录；resolution_order=存在性过滤→坍缩
X-09=(I-Δ3, I-Δ2) 组合态追踪：
  index 键 lineage-root=ABSENT（Δ2 pop）；
  文件：orig=ABSENT，conflict=PRESENT（孤儿）
  ⇒ resolution expectation：candidate_count=0；resolved_target=null；
    expected I 签名=I-NF
```

实验后**只允许问**：「实际解析结果 == 预登记 resolution expectation？」
——相等且 P_comp=BROKEN 而 actual=SATISFIED ⇒ MASKING（机械成立）；
不相等 ⇒ 构造/仪器疑云路径。**禁止**「看到实际解析→事后解释为遮蔽」。

**构造审计不变量（每 X-cell，构造记录字段+second layer 复验；非新
实验 cell）**：

```text
CI-1  op_a/op_b 呈现且与预登记一致
CI-2  op_a 效果探针 present（逐 op 冻结效果断言：如 Δ2⇒orig ABSENT）
CI-3  op_b 效果探针 present
CI-4  无未声明操作：组合 IS 树 == (op_a∘op_b) 重放树（逐字节）
CI-5  组合顺序 == 预登记顺序（观测序列核验）
```

**X-12 结构性覆盖理由（human 审查要求）**：X-12=(B-Δ1, A-Δ2) 覆盖的
结构关系 R=**exclusion-set 组合闭包**——两个 op 独立扩张同一 manifest
的 out_of_scope 集（B-Δ1 收 archive/、A-Δ2 收 universe/），检验排除集
组合是否保持各 op 的个体边界效应（锚保持越界+archive 保持越界），
即**边界图不被 last-writer clobber**。该关系未被 X-01..X-11 覆盖
（X-11 的 Δ8/Δ9 只做 scope_tags/in_scope 的加法式 RMW，从不触碰
out_of_scope；其余对均为对象定向操作）——非凑数 cell。

## 3. 联合预测规则 P_comp（结果之前机械确定）

```text
构造时由冻结单变量预测器机械合成（非人工判定）：
  P_comp(X) = BROKEN(sig-set)  若恰一 constituent 单变量预测 X BROKEN
                              （sig-set=该签名）
                           或两者均预测 X BROKEN
                              （sig-set=两签名之并）
             HOLD             若两者均预测 X HOLD
P_comp 随构造记录锁定（先于任何联合评估）——回应 human 锁死项 2。
```

## 4. 交互分类法（预注册，机械分类——rev.2 H-X2 机械化）

条件级判定（逐条件，机械）：

```text
P_comp HOLD  + actual SATISFIED                 → 条件 HOLD-match
P_comp BROK(S) + actual BROKEN + 签名 ∈ S       → 条件 BROKEN-match
P_comp BROK(S) + actual BROKEN + 签名 ∉ S       → SIGNATURE-SHIFT
P_comp BROK(S) + actual SATISFIED               → MASKING
P_comp HOLD  + actual BROKEN（带签名）           → EMERGENT-BREAK
actual BROKEN 无签名                             → ATTRIBUTION-FAILURE
```

**ADDITIVE 双层定义（rev.2 H-X2）**：cell 为 ADDITIVE 当且仅当
**全部三条件状态与 P_comp 状态相等 AND 每条件实际签名 ∈ P_comp
sig-set**——「状态正确但签名变化」归 SIGNATURE-SHIFT，不归 ADDITIVE。

cell 级标签=固定优先级（互斥，任意结果机械落入唯一类）：

```text
1. ATTRIBUTION-FAILURE（任一条件签名-less BROKEN）
2. SIGNATURE-SHIFT（任一条件签名 ∉ sig-set）
3. MASKING / EMERGENT-BREAK（任一条件违反 P_comp 状态方向；
   subtype 逐条件登记于 detail——标签优先级化，信息不丢失）
4. ADDITIVE（全部条件双层匹配）
```

**双条件同时 BROKEN 显式允许**；分类在判读时由预注册规则机械作出——
禁止看到组合结果后才决定「这算不算 interaction」（锁死项 6）；分类
歧义⇒INCONCLUSIVE。

## 5. 控制与独立性沿用（锁死项 5）

- 三正控 R32N-SANITY-A/I/C（逐条件评估路径活性）+ K-0——与 R3-N 完全
  同源，predictions 继承冻结预测器；
- §1a campaign setup lock（fresh formation、一次性 t₀、三要素钉死）；
- inv-1..5 独立性不变量沿用（判读只读本 run 工件；R3-2/R3-3 产物零
  读取作判定输入；目录来源=冻结 op 池结构+静态兼容性，非既往 outcome；
  per-cell fresh copy/构造记录先行/双哈希/replay purity）。

## 6. 无修补封闭与停止条件

- 目录/预测/分类法/出口结构 seal 时冻结；**出现 MASKING/EMERGENT/
  SIGNATURE-SHIFT 不触发任何规则或目录修补**——闭合后进边界复审门
  （human）；
- 停止条件：S-1..S-5、S-N2（正控 SATISFIED=判读器死亡）、S-N3/
  S-N4（INCONCLUSIVE 传染：INTERACTION/ADDITIVE 判读要求零
  INCONCLUSIVE cell）沿用 + **S-X1**：INVALID-COMPOSITION cell 不停
  止（预注册类，逐 cell 登记）；系统性组合失败 ⇒ S-4 + **S-X2**：
  构造审计不变量违例（CI-1..CI-5 任一失败）⇒ 该 cell INCONCLUSIVE
  （构造疑云——组合机制未按预登记形成联合 IS，其判定结果不可用）；
  系统性 CI 违例 ⇒ S-4。

## 7. 出口结构（预注册；任一出口都不自动开启 R3-4）

```text
ALL-ADDITIVE      全部 pair ADDITIVE（双层定义）+ 控制全净 +
                  构造审计不变量全过 + 零 INCONCLUSIVE（S-N4）
                  ⇒ 组合性在该 slice 内成立（bounded）——进 R3-4 综合
                    或有界收官的输入
INTERACTION-FOUND ≥1 MASKING/EMERGENT-BREAK/SIGNATURE-SHIFT
                  ⇒ 交互登记（逐 cell：条件+签名+对+机制+resolution
                    expectation 对照），闭合后进边界复审门
INCONCLUSIVE      传染规则触发（含 CI 违例 cell）
STOP / INVALID    仪器/门控/组合系统性失败
```

## 8. 效力声明

本文档 = IS-X Design Gate 交付物，DELIVERED / INDEPENDENT REVIEW
PENDING。零实验、零代码、零 harness 改动、零采数。执行须独立 human
授权（先独立对抗审查：设计→审查→修订→RATIFIED→执行授权）。R3-4
LOCKED 维持；全部排除清单维持（P/IPAC 冻结/PALACE/MCP/Route/后端
适配/产品实现/性能/模型比较/完整恢复系统）。

## 9. 输入清单

- R3-0 §4.2（IS-X 定义与顺序纪律）；R3-2/R3-3 冻结目录（op 池）；
  R3-1 Spec rev.2（判定程序）；R3-3 second layer 边界结论（α 选定
  依据：IS-X=唯一未覆盖 in-scope 结构类）
