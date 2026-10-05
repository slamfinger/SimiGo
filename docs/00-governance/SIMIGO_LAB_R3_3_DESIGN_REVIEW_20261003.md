# SimiGo-Lab R3-3 Design（R3-N）— Independent Adversarial Review

日期：2026-10-03
状态：**EXECUTED / VERDICT: PASS WITH RECOMMENDATIONS（无 blocker；四项
修订后 RATIFIED）**
授权：human「执行独立对抗审查」（2026-10-03），八项攻击点+假反证防护。
评审对象：`SIMIGO_LAB_R3_3_DESIGN_R3N_20261003.md`（rev.1）。
边界：RATIFIED ≠ execution authorization。

## 1. Check 1 — N-catalog 推导纯度（重点 Δ4/Δ5/Δ6/Δ8/Δ9）

逐 op 验证「预测可仅从规则文本推导，且在 R3-2 outcome 任意取值下不变」：

| op | 规则文本出处 | 结果无关性检验（若 R3-2 outcome 不同，预测是否改变？） |
|---|---|---|
| Δ4 同内容重复候选 | Spec/设计 §5a 坍缩规则：「多候选逐字节相同→收敛为 1；相异→ambiguous」——HOLD 侧由规则文字直接给出；R3-2 只测了相异侧（I-Δ3） | 否——预测独立 |
| Δ5 字段保持扩展 | Spec I-EV-1：比较仅及 `is_reference.field` 声明字段——额外字段不在比较域 | 否 |
| Δ6 前置等价迁移 | Spec C-REF：前置须解析 found ∧ in-boundary——迁移+索引重指向保持二者 | 否（K-1b 仅作「该侧未测」的覆盖证据，预测本身出自 C-REF 规则文字） |
| Δ8 scope-tag 增补 | C-DECL：必需 tag ∈ scope_tags——增补不减除必需项 | 否 |
| Δ9 in_scope 增补 | 边界隶属=要求侧（对象须在界内）；扩界不移除任何对象的隶属 | 否 |

**关键区分（回应 human 焦点 6 的前半）**：目录推导使用了两个输入——
(a) 规则文本；(b) R3-2 的**目录覆盖图**（哪些条款侧已被哪些 op 测过）。
(b) 是结构性知识（catalog 结构），非 outcome 知识；逐 op 检验「预测在
R3-2 outcome 任意反事实下不变」全部成立——**无 outcome 倒推路径**。
Δ1/Δ2/Δ3/Δ7 同法验证通过（判定只依赖引用键/存在性过滤/扫描目标域，
均为规则文字）。

## 2. Check 2 — Null expectation 与操作解耦

每条 N-op 的 HOLD 预测均附独立机械理由（§1 表第三列=规则条款），非
「设计者预期」。预测与评估**代码路径分离**：predict() 从 op 元数据+ES
证据图推导；eval_* 读实际变异后 IS 状态。二者的失效模式互不相同且各有
检出通道：预测错⇒PREDICTION-MISMATCH 通道；评估错⇒SANITY 正控通道
（见 Check 3）与 per-cell t₀ 复算通道。**无循环定义。** ✓

## 3. Check 3 — R32N-SANITY 充分性

**发现 H-1（强制修订）**：rev.1 的 SANITY 仅重实例化 A-Δ3——只证明
**A 评估路径**的 BROKEN 能力。若 I 或 C 评估路径死亡（恒 SATISFIED），
N-cell 中针对 I/C 的真反例将被误读为 HOLD ⇒ 假 NO-COUNTEREXAMPLE。
rev.2 修订：**SANITY 扩展为逐条件三个正控**——SANITY-A（A-Δ3）、
SANITY-I（I-Δ1）、SANITY-C（C-Δ2），三者均须产生预注册 BROKEN 签名；
任一正控 SATISFIED ⇒ 判读器死亡 ⇒ 战役 INCONCLUSIVE+STOP（S-N2 覆盖
全部三路径）。目录变为 **10 反证 + 3 正控 + K-0 = 14 cell**。

## 4. Check 4 — 反例与仪器失败的分界（S-N3 攻击）

**发现 H-2（强制修订）**：rev.1 存在吸收路径——单个 N-cell 因
instrument_doubt 判 INCONCLUSIVE 后，campaign 仍可宣称
NO-COUNTEREXAMPLE（§5①未显式要求零 INCONCLUSIVE），真反例可被洗入
INCONCLUSIVE。rev.2 修订（INCONCLUSIVE 传染规则）：**NO-COUNTEREXAMPLE
当且仅当零 INCONCLUSIVE cell——任何 cell INCONCLUSIVE ⇒ 战役整体
INCONCLUSIVE**（禁 Partial-NO-COUNTEREXAMPLE 读法）。

**发现 H-3（强制修订）**：rev.1 未钉死反例资格与再分类程序，两条误用
路径均存在：①run 中把真反例急分类为仪器故障⇒埋没；②把仪器缺陷计为
COUNTEREXAMPLE-FOUND。rev.2 修订（反例资格三要件）：run 中 N-cell 的
任何 BROKEN **先作为 candidate-counterexample 原样记录（数据）**；
资格判定在闭合后审计作出，须同时满足 (a) 签名可归因至具体条件+机制，
(b) frozen-op replay 复现该击穿（确定性排除瞬态），(c) 审计未能定位
具体仪器机制缺陷——审计定位成功⇒改判 INCONCLUSIVE 并记录（§5⑤ 沿
用）；**cell 排除只允许经预注册 S/I 码，反例 cell 永不排除**。两条
误用路径均被封闭：`意外→doubt→INCONCLUSIVE→继续跑` 被 H-2 传染规则
阻断（INCONCLUSIVE 不能产出 NO-COUNTEREXAMPLE）；`缺陷计入反例` 被
要件(c)阻断。

## 5. Check 5 — 「禁止 campaign 内修补」封闭性

修订后封闭链=目录冻结（§1，seal 时）+预测构造时锁定（§4 沿用）+
null expectation 预注册（§2「不得事后改写」）+判读规则预注册（§5）+
**H-3 补入的排除封闭**（cell 排除仅经预注册 S/I 码）。残余路径排查：
中途改预测规则/判读代码/重跑反例 cell——均属新 implementation/新
campaign，须新授权且原 campaign 记录保全；post-hoc 把反例签名重新
解释为「规则范围外」⇒ 属边界修订门事项，不得在判读层作出。**无
「改规则直到没有反例」通道。** ✓

## 6. Check 6 — R3-2 独立性=实际数据隔离

- inv-1 可代码核验：harness/判读只接受给定 run_dir 参数，无任何 R3-2
  run 路径引用（源码可审）。
- inv-2 由 Check 1 的结果无关性检验承担：逐 op「预测在 R3-2 outcome
  任意取值下不变」成立；目录来源=规则文本+覆盖图（结构知识）。
- inv-3/inv-4 沿用（fresh formation 新 run-UUID；per-cell fresh copy/
  构造记录先行/双哈希/replay purity）。
- 间接选择路径排查：经由 R3-2 outcome、cell 顺序、既有 fixture 状态、
  既有 IS 样本选择 N-cell 的路径——**未发现**（N-op 的对象与机制均由
  规则条款结构决定；SANITY op 选自冻结目录亦为结构知识）。✓

## 7. Check 7 — 出口语义独立性

- rev.1 §2/§0 已含「不升格普遍」；rev.2 补两条**非推导声明**（human
  焦点 7 逐字落实）：**NO-COUNTEREXAMPLE ≠ 证明一致性**——其登记含义
  仅为本 slice 内被测 HOLD 侧条款经受住了反证探针，不验证条件正确性/
  最小性/完备性（RQ3-4 保持开放）；**COUNTEREXAMPLE-FOUND ≠ 普遍反例、
  ≠ 追溯撤销 R3-2**——R3-2 判读关于其自身 cell；反例触发的是 taxonomy
  边界复审门，是否级联由复审门裁定，非自动撤销。两出口都只进边界复审。
  ✓

## 8. Check 8 — 「9+1+1」数量伪完整性

数量本身无意义——逐 op 核对「覆盖一个明确、未覆盖的 HOLD 侧条款」
（§1 表第三列，Check 1 已验）。**HOLD 侧穷举扫描**：

```text
已覆盖：解析坍缩（Δ4）/死项（Δ3）/字段域（Δ5）/前置迁移（Δ6）/
        未引用增删改（Δ1/Δ2/K-1a 先例）/未目标 invalidation（Δ7）/
        scope-tag 增补（Δ8）/扩界（Δ9）/锚迁移（K-1b 先例）
rev.2 补：Δ10 谱系等价迁移——referability 子句在 I-EV-2 上的第三个
        引用组实例（锚=K-1b、前置=Δ6 已覆盖，谱系侧未测）⇒ 目录
        10 反证 cell，referability 子句三引用组全覆盖
结构性不可测（如实登记，非遗漏）：validity-temporal HOLD 侧在战役
        时窗内空转；I-EV-3 payload 完整性对 IS 按构造不敏感（无 IS
        敏感 HOLD 侧可探）
范围外登记（O-1）：两个未测的 BROKEN 侧预测——scope-tag 移除⇒
        C-DECL-FAIL、被引用区域 access-deny⇒A-NF/C-REF-NOT-FOUND——
        属定向家族非反证搜索，登记为未来定向战役的开放预测
```

**结论：无重要 HOLD 侧遗漏；Δ10 补齐 referability 子句。**

## 9. 发现汇总与处置

```text
H-1  强制  SANITY 扩展为逐条件三正控（I/A/C 各一），防假 NO-COUNTEREXAMPLE
H-2  强制  INCONCLUSIVE 传染规则：NO-COUNTEREXAMPLE 当且仅当零
           INCONCLUSIVE cell（封死吸收路径）
H-3  强制  反例资格三要件+再分类程序+排除封闭（封死双向误用）
H-4  收紧  Δ10 谱系等价迁移（referability 子句三引用组全覆盖）
O-1  登记  两个未测 BROKEN 侧预测（范围外，未来定向战役开放预测）
O-2  登记  结构性不可测两侧（validity-temporal 空转/I-EV-3 按构造
           不敏感）——如实登记非遗漏
O-3  登记  非推导声明强化（NO-COUNTEREXAMPLE≠证明一致性/
           COUNTEREXAMPLE-FOUND≠追溯撤销 R3-2）
```

全部为收紧/补全/澄清条款，零命题变更、零研究对象变更。

## 10. 判定

```text
N-catalog 推导纯度      = PASS（逐 op 结果无关性成立）
null expectation 解耦   = PASS
SANITY 充分性           = PASS after H-1
反例/仪器分界           = PASS after H-2/H-3
无修补封闭              = PASS after H-3
R3-2 数据隔离           = PASS（代码可核验+结果无关性成立）
出口语义独立            = PASS after O-3
覆盖完整性              = PASS after H-4（无重要 HOLD 侧遗漏）
────────────────────────────────────────────────
VERDICT = PASS WITH RECOMMENDATIONS（无 blocker）
处置    = rev.2 机械补入 H-1/H-2/H-3/H-4 → R3-3 Design（R3-N）
          = RATIFIED（正式设计）；execution 仍须独立 human 授权
```

## 11. 边界声明

RATIFIED = R3-N 正式设计（反证对象/null expectation/停止条件/独立性
四件锁定）；**execution 须独立 human 授权**；R3-4 LOCKED；全部排除
清单维持。
