# SimiGo-Lab R3-1 Judgment Specification — Independent Review

日期：2026-10-03
状态：**EXECUTED / VERDICT: PASS WITH RECOMMENDATIONS（无 blocker）**
授权：human「授权进行 R3-1 Judgment Specification（独立审查）」
（2026-10-03）。
评审对象：`SIMIGO_LAB_R3_1_JUDGMENT_SPECIFICATION_20261003.md`（rev.1）。
评审基准：R3-0 设计（@1c8c463）、R2 rev.2 形式化、R3-1 Gate Review 五项
强制内容、human 七项检查指令（2026-10-03）。
边界：本评审通过 ≠ 实验开启；实验进入仍需独立 human 授权。

## 1. Check 1 — Traceability（R3-0 强制约束 → Spec 条款）

逐项核对 R3-0 对 R3-1 的全部要求：

| R3-0 要求 | Spec 对应 | 状态 |
|---|---|---|
| 只做判定规范，不做实验系统实现 | §0 | ✓ |
| I/A/C 各配 IS 变化判定问题（M→M′ / R removed / R retired） | §1.2/1.4、§2.5、§3.2 | ✓ |
| 出口判据=三条件可独立观察、记录、判定 | §6.3（R3-1 自身出口判据）+ §6.1 schema + §7 程序 | ✓ |
| Cons 候选定义引用不修改 | §0 明示 | ✓ |
| 单向性 LawfulContinuation⇒Cons 保持 | Spec 全文无任何 Cons⇒LawfulContinuation 表述（缺省即保持） | ✓ |
| 排除清单维持 | §8 逐字重申 | ✓ |
| Gate Review 五项强制内容 | §1（①）/§2.2+2.3（②）/§3（③）/§4（④）/§5（⑤） | ✓ 全部落位 |
| 总判定纪律（条件满足性非输出变化） | §1.3/§2.5/§3.3/§6.1 多重禁令 | ✓ |

**发现 O-1（观察，非阻塞）**：R3-0 总判定纪律允许「最终输出作为辅助
观察」；Spec 对辅助输出记录保持沉默（既不使用也不禁止）。判定对象
不受影响，但 R3-2 设计门应显式声明：辅助输出遥测可记录、不得进入
判定通道。

**结论：无遗漏。**

## 2. Check 2 — No semantic expansion（重点 C）

- §3.2 C 判定 = C-REF（引用 found/not-found）+ C-INV（invalidation/
  supersession 记录存在性）+ C-DECL（声明式 applicability 中**机械可
  评估者**核对）——三者均为对 IS 内容的确定性检查，零模型判断。
- §3.3 绝对禁令（模型语义判断不作判定输入）+ C-NOT-EVALUABLE 诚实
  出口 + 语义级 C 必须走 stop/revise——无静默扩展通道。

**发现 H-3（加固建议，非阻塞）**：C-DECL 的「机械可评估者」以枚举加
「等」字收尾，分类判据未显式化——存在 R3-2 阶段把语义条件归类为
「机械可评估」的解释空间。应补一条显式判据：**声明条件为机械可评估，
当且仅当存在 formation 声明的确定性评估程序、其输入仅为 IS 内容、
零模型/语义判断参与**。

**结论：未发现语义扩展；一处加固建议。**

## 3. Check 3 — No trivialization（重点 A 引用路径与 I-INVARIANT）

- **A 方向一（防恒真）**：判定立场锁定 ES 自身引用路径 + formation
  基线——A 的满足不是观察者施舍；A-NF（删除/移出边界）与 A-SUB
  （符号名引用下同址异容）均为真实可触发签名。内容寻址下 A-SUB
  结构不可能，但 A-NF 仍可触发——A 在任何引用形式下都非恒真。✓
- **A 方向二（防恒破）**：未人为添加失败模式；A-NOT-EVALUABLE 是
  诚实结构出口而非伪装的 BROKEN。✓
- **I 双向**：I-INVARIANT 条款（§1.5）逐字落实 human 指令——I≡TRUE
  如实登记、禁注入 IS 依赖/加间接引用/改表征；同时 I 的签名全部
  追随 ES 自身 formation 声明的证据结构，无 manufactured references。✓

**结论：双向均无 trivialization。**

## 4. Check 4 — Four-state integrity（NOT-EVALUABLE ≠ BROKEN）

- §6.1 显式声明 NOT-EVALUABLE ≠ BROKEN；§7 NOT-EVALUABLE 传播至
  Cons 且该 cell **不参与四态统计**、改走 §6.3 出口判据核算——
  三态在记录、合成、统计三层都保持区分。✓
- BROKEN 的签名域各条件封闭：I-BROKEN={I-NF, I-AMBIG, I-MISMATCH}；
  A-BROKEN={A-NF, A-SUB}；C-BROKEN={C-REF not-found, C-INV present,
  C-DECL fail}。✓

**发现 H-2（加固建议，非阻塞）**：仪器疑云签名（A-UNRESOLVABLE /
I-UNSTRUCT）的记录位置在 schema 中未显式化——应明确：按
NOT-EVALUABLE + 签名记录，且 cell 级增加 instrument_doubt 标志，
cell 判定按 §5.3 走 INCONCLUSIVE。

**结论：三态区分成立；一处 schema 显式化建议。**

## 5. Check 5 — Attribution / Control（K-0 漂移与 post-hoc 风险）

- §5.3：K-0 出现**任何**条件满足性变化 ⇒ 仪器疑云 ⇒ **该批次全部
  INCONCLUSIVE、不进判读**——漂移处置为预注册硬规则。✓
- K-1 良性对照类目固定（承 R2 Task 3 非破坏类三式），双重读法
  （归因失败⇒INCONCLUSIVE 或干净归因⇒RQ3-4 素材）不改判据。✓

**发现 H-1（加固建议——本次评审最重要的发现，非阻塞但须在规范生效
前补入）**：Spec 未显式规定 **ΔIS 类别的锁定时点**。存在这样的逃逸
路径：某 IS-I cell 未击穿 I ⇒ 事后把它重分类为 K-1 良性 ⇒ Control
家族被结果反向定义（hidden post-hoc control）。应补入：**cell 的
ΔIS_class 在构造时登记并锁定，先于任何条件评估；禁止依据评估结果
重分类**。此条与 human 检查 5 直接对应。

**结论：漂移硬规则在位；一处构造时锁定义务须补。**

## 6. Check 6 — Failure / stopping（停止条件的真实性）

- §6.3：R3-1 FAIL（结构性 NOT-EVALUABLE）⇒ 停止/修订边界，**不进入
  R3-2**——停止条件真实。✓
- 逃逸路径排查：①A-NOT-EVALUABLE 无替代程序可换（§2.3）；②C 语义级
  判定显式禁止静默扩展（§3.3）；③I≡TRUE 禁止加条件改写（§1.5）；
  ④失败有效性条款覆盖全部出口（§6.3）。**未发现「判不出来→修改
  规则→继续」的隐性通道。** ✓

**发现 O-2（观察，非阻塞）**：R3-2 状态选样须披露可判定性前提
（formation 摘要等 formation 时材料的存在性）——样本诚实义务，属
R3-2 设计门内容，非 Spec 缺陷。

**结论：停止条件真实，无逃逸路径。**

## 7. Check 7 — Scope leakage

- R3-2 实验细节：Spec 无 cell 设计、无执行矩阵、无 harness 细节；
  §4.3 仪器化要求仅为条文且全部对应 R3-0/Gate Review 已授权的规范化
  义务。✓
- R3-4 解释问题：I≡TRUE 的含义分析显式推延至 R3-4（§6.3）；四态定义
  属 human 授权的「四态出口及失败规则规范化」范围。✓
- IPAC / PALACE / P / Route A/B/C：§8 全部维持排除；全文无 Relation
  carrier、无 PALACE、无 P 条款。✓

**结论：零泄漏。**

## 8. 特别聚焦 — NOT SUPPORTED 含 I≡A≡C≡TRUE 的逻辑方向

human 点名条款核查（Spec §6.2）：

- 该条款把「定向变化系统性不击穿定向条件（含 I≡A≡C≡TRUE）」定义为
  **NOT SUPPORTED = 实质性有界发现**，并显式禁止「为『成功』而改表征
  或加条件」。✓
- 逻辑方向验证：all-TRUE ⇒ NOT SUPPORTED ⇒ 结果 ⇒ 边界解释（RQ3-4/
  R3-4）——**不是** all-TRUE ⇒ 无发现 ⇒ 修改条件 ⇒ 直到有变化。✓
- 与 INCONCLUSIVE 的分界正确：all-TRUE 是仪器正常下的干净否定，
  不落入 INCONCLUSIVE（后者保留给漂移/不可归因/判别力丧失）。✓

**结论：逻辑方向正确，贯彻「可不断否定、修正、反证，但不得为让研究
继续而改变研究对象」的尺度。**

## 9. 发现汇总

```text
H-1  加固建议（最重要）  ΔIS_class 构造时锁定义务（防 post-hoc control）
H-2  加固建议            仪器疑云签名在 schema 中的显式记录位置
H-3  加固建议            C-DECL「机械可评估」的显式分类判据
O-1  观察                辅助输出遥测的显式定位（归 R3-2 设计门）
O-2  观察                R3-2 状态选样的可判定性前提披露（归 R3-2 设计门）
```

三项 H 均为**收紧性条款**，不改变任何研究命题、判据或研究对象——
按 R2 rev.1→rev.2 先例以最小修订（rev.2）机械补入。

## 10. 判定

```text
Traceability          = PASS（无遗漏）
No semantic expansion = PASS（一处加固）
No trivialization     = PASS（双向无恙）
Four-state integrity  = PASS（一处 schema 显式化）
Attribution/Control   = PASS（一处构造时锁定义务）
Failure/stopping      = PASS（无逃逸路径）
Scope leakage         = PASS（零泄漏）
─────────────────────────────────────────
VERDICT = PASS WITH RECOMMENDATIONS（无 blocker）
处置    = rev.2 机械补入 H-1/H-2/H-3 → Spec 升 rev.2 →
          R3-1 Judgment Spec = RATIFIED（正式判定规则）
```

## 11. 边界声明

- 本评审通过 ≠ 实验开启；**R3-2 的进入须独立的 human 授权**
  （含 R3-2 设计门）。
- RATIFIED 的含义 = Spec 可作为下一阶段的正式判定规则；O-1/O-2 登记
  为 R3-2 设计门输入。
- 全部排除（P / IPAC / PALACE / MCP / Route / 后端适配 / 产品实现 /
  性能 / 模型比较 / 完整恢复系统）维持。
