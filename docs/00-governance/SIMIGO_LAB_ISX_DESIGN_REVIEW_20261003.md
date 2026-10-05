# SimiGo-Lab IS-X Design — Independent Adversarial Review（human 审查登记）

日期：2026-10-03
状态：**EXECUTED / VERDICT: PASS WITH RECOMMENDATIONS（0 blockers；四项
封口级加固 H-X1..H-X4 RATIFIED 前必须钉死）**
审查人：human（本轮审查由 human 亲自执行，本文档为审查记录登记）。
审查对象：`SIMIGO_LAB_ISX_DESIGN_GATE_20261003.md`（rev.1）。
审查标准：R3-3 对抗审查同规格——攻击「设计自洽但实验无效」漏洞。

## 1. 六锁死点审查表（human 判定）

| 项目 | 判定 | 关键判断 |
|---|---|---|
| ① 组合目录 | ⚠️ 需加固 | 机械抽取原则正确，但 X-08/X-09「遮蔽」语义必须在构造阶段形式化 |
| ② P_comp | ✅ | 结果前冻结、由单变量预测器合成，符合独立性要求 |
| ③ Interaction 分类 | ⚠️ 需加固 | MASKING/EMERGENT-BREAK 清楚，但 SIGNATURE-SHIFT 与 ADDITIVE 边界需机械化 |
| ④ 控制/独立性 | ✅ | R3-N 框架沿用合理；IS-X 增加独立的「组合构造有效性」层 |
| ⑤ 无修补 | ✅ | 禁 outcome-driven patch 尤其重要 |
| ⑥ 出口结构 | ✅ | 不自动开启 R3-4，边界控制正确 |

## 2. 四项强制加固（human 原文要点登记）

**H-X1（最重要）— X-08/X-09 遮蔽不得依赖语义解释**：X-08 测试的是
`P_comp = I BROKEN; actual = I SATISFIED`（MASKING），但必须避免漏洞
——「冲突项导致谱系解析收敛」若依据实际联合结果才被识别，X-08 就成
了结果后定义。**必须在构造阶段锁定**：X-08 conflict target / resolution
order / expected resolution path / expected surviving anchor——全部由
IS-X construction 本身生成。实验后只允许问「实际解析结果 == 预登记
resolution expectation？」，不能反向「看到结果→解释为遮蔽」。X-09 逆序
同理，否则 X-08/X-09 从「交互探针」滑向「结果解释探针」。

**H-X2 — ADDITIVE 必须两层定义**：仅有状态一致不够——若组合结果
I BROKEN/A BROKEN 但签名为 {I-NF, A-SUB}（预测 {I-MISMATCH, A-SUB}），
I-MISMATCH 未出现，这算 SIGNATURE-SHIFT 还是 ADDITIVE 不能留给解释层。
**ADDITIVE ⟺ actual 条件状态 == 预测状态 AND actual 签名集 == P_comp
签名集**；否则「状态正确但签名变化」会被误归 ADDITIVE。

**H-X3 — INVALID-COMPOSITION 与被测系统响应异常的机械边界**：
INVALID-COMPOSITION 只描述**实验构造失败**（组合物无法按预登记构造
规则形成）。组合物成功形成后 evaluator 的任何异常响应**必须进入实验
结果**（真实交互分类），不得经「composition invalid」提前吞掉——后者
可能恰是 EMERGENT-BREAK 或有价值的交互行为。边界：
`COMPOSITION-CONSTRUCTION ERROR → INVALID-COMPOSITION；
constructed IS valid → evaluator runs → unexpected response → actual
interaction classification`。

**H-X4 — 组合层 sanity（构造审计不变量）**：R3-N 三正控只覆盖
evaluator 活性；IS-X 新增风险=**组合构造器本身是否真按预登记形成联合
IS**（否则「本要测 A⊕B 实际构造出 A」会得到看似漂亮的 ADDITIVE）。
增加 per-X-cell 构造审计不变量（非新实验 cell）：op-A present /
op-B present / A construction effect present / B construction effect
present / no undeclared operation present / composition order matches
preregistration。

## 3. 附加审查要求与肯定

- **X-12 结构性理由**：必须明确其覆盖的、X-01..X-11 未覆盖的结构关系
  R，否则是「看起来增加覆盖率、实际不增边界信息」的凑数 cell。
- **X-10/X-11 的 EMERGENT-BREAK 读法确认**：即使出现，也只证明「当前
  单变量机械规则+当前组合结构」无法预测该联合结果——fixture-slice
  bounded，不得升格 Consistency law false（现出口设计未越线，正确）。
- **反滑坡条款肯定**：ADDITIVE=baseline、INTERACTION=deviation from
  independently predicted composition——定义保持不变。
- **分类互斥要求**：优先级固定（ATTRIBUTION-FAILURE → SIGNATURE-SHIFT
  → MASKING/EMERGENT-BREAK → ADDITIVE）或互斥布尔判定式——任意 actual
  result 必须机械地只能落入一个类别。

## 4. 判定与处置（human）

```text
IS-X Design Gate = PASS WITH RECOMMENDATIONS
Blockers         = 0
Mandatory        = H-X1 构造期 resolution lock
                   H-X2 ADDITIVE 双层定义
                   H-X3 INVALID-COMPOSITION 边界
                   H-X4 构造审计不变量
处置             = IS-X Design rev.2 吸收 H-X1..H-X4 → RATIFIED
                   → 独立审查记录封存 → 等待单独 execution authorization
Execution        = NOT AUTHORIZED
R3-4             = LOCKED
```

四项均为**设计封口级加固**而非重做要求——尤其 H-X1/H-X3 不钉死，未来
出现 MASKING/EMERGENT-BREAK 时会留下「预登记交互还是事后解释」的攻击面。
