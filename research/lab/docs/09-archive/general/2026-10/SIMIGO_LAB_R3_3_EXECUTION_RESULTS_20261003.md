# SimiGo-Lab R3-3 Execution Results — R3-N Negative / Counterexample Search

> **ARCHIVED** 2026-10-20 · line: 通用治理 / 其他 · original: docs/00-governance/SIMIGO_LAB_R3_3_EXECUTION_RESULTS_20261003.md
> Evidence status: unchanged (content frozen; moved only)


日期：2026-10-03
状态：**EXECUTED / CAMPAIGN NO-COUNTEREXAMPLE（fixture-slice bounded）—
AUDIT PASS（11/11）— HUMAN SECOND LAYER PENDING**
授权：human「授权 R3-3 execution（R3-N）」（2026-10-03）——fixture 实现+
预注册 14-cell campaign+独立结果审计；RATIFIED 设计零修改；R3-4 LOCKED。
设计：R3-3 Design（R3-N）rev.2（RATIFIED）；判定规则：R3-1 Spec rev.2。
Harness 源码：`simigo2-experimental/r3-2-harness/r3n_*.py` @ `f207931`
（commit+push 先于执行——证据纪律；评估程序零改动，r32_lib 复用）。

## 1. Campaign setup（§1a lock 执行记录）

```text
run_uuid            = R33N-20261003T114301Z-69359
run root            = docs/02-evidence/r3-3-execution/R33N-20261003T114301Z-69359
(ES, IS₀) 选择      = 一次性，按预登记准则（fresh formation——独立性
                      不变量 inv-3；密封 R-C1 #4 字节重新读取，非 R3-2
                      产物——inv-1）
t₀ 判定             = 一次性，setup 阶段；三要素钉死（Cons=R2 rev.2
                      candidate / 规则=Spec rev.2 / 时点=setup）
t₀ 结果             = I/A/C 全 SATISFIED ⇒ Cons(ES,IS₀)=true ⇒
                      cell validity 全战役固定
harness 哈希         = r32_lib ee4762a2ece3…（与 R3-2 完全同源——评估
                      程序零改动）+ r3n_lib 39c939504c11…
```

## 2. Campaign 结果（14 cell，零偏差零重试零重分类）

| Cell | 类别 | t₁ I / A / C | 判读 |
|---|---|---|---|
| R32N-Δ1（未引用对象删除） | R3-N | 全 SATISFIED | HOLD |
| R32N-Δ2（未引用内容改写） | R3-N | 全 SATISFIED | HOLD |
| R32N-Δ3（死索引项） | R3-N | 全 SATISFIED | HOLD |
| R32N-Δ4（被引用键同内容重复候选） | R3-N | 全 SATISFIED | HOLD |
| R32N-Δ5（字段保持扩展） | R3-N | 全 SATISFIED | HOLD |
| R32N-Δ6（前置等价迁移） | R3-N | 全 SATISFIED | HOLD |
| R32N-Δ7（未目标 invalidation） | R3-N | 全 SATISFIED | HOLD |
| R32N-Δ8（scope-tag 增补） | R3-N | 全 SATISFIED | HOLD |
| R32N-Δ9（in_scope 区域增补） | R3-N | 全 SATISFIED | HOLD |
| R32N-Δ10（谱系等价迁移） | R3-N | 全 SATISFIED | HOLD |
| R32N-SANITY-A | SANITY | **A BROKEN/A-SUB**（预测吻合） | SANITY-OK |
| R32N-SANITY-I | SANITY | **I BROKEN/I-MISMATCH**（预测吻合） | SANITY-OK |
| R32N-SANITY-C | SANITY | **C BROKEN/C-INV**（预测吻合） | SANITY-OK |
| R32-K-0 | K-0 | 全 SATISFIED（与 setup 逐项一致） | CONTROL-HOLD |

完整性：`integrity_all_clean=true`；t₀ 复算全一致；instrument_doubt 全
NO；零 INCONCLUSIVE cell；零反例候选。

## 3. 机械判读（设计 §5 rev.2 预注册出口结构）

```text
campaign_verdict    = NO-COUNTEREXAMPLE
依据                = 10/10 反证探针 HOLD + 3/3 正控按预测 BROKEN
                      （I/A/C 三条判定路径活性逐一证实）+ K-0 持有 +
                      零 INCONCLUSIVE cell（H-2 传染规则满足）
second_layer_audit  = AUDIT PASS（11/11：hygiene/链闭合/replay purity
                      14/14/N-probe HOLD 原始证据/逐条件活性/H-3(c) 不
                      适用/H-2 零容忍/出口结构/与判读一致）
```

## 4. 解释边界（claim scope，逐字义务）

**允许表述**：在本 fixture 结构类内，规则条款的十个未测 HOLD 侧——
未引用对象增删改、死索引项、同内容重复候选坍缩、字段域比较、前置与
谱系等价迁移、未目标 invalidation、scope-tag/区域增补——经反证探针
**均未产生条件击穿**；且三条件判定路径经逐条件正控证实活性。**当前
差分敏感性画像（R3-2 的 BROKEN 侧 + R3-3 的 HOLD 侧）在该 slice 内
两侧均获得边界证据。**

**禁止表述**（human 预注册限缩读法，逐字义务）：
- **NO-COUNTEREXAMPLE ≠ Consistency invariant established**——不验证
  条件正确性/最小性/完备性；RQ3-4 保持开放（本 slice 的探针集有限，
  未测 HOLD 侧仍可能存在）；
- 不得写「规则已证明正确」「taxonomy 完备」；
- 不得外推产品/普适/其它表征（bounded 于 fixture 结构类；内容寻址
  变体 defer 不变）；
- 不得开启 continuation/PALACE/IPAC/Route 推论（全程零模型零 Relation
  零 PALACE）。

## 5. 观察

- O-N1：正控三路径的 BROKEN 签名与 R3-2 定向 cell 完全同型（A-SUB/
  I-MISMATCH/C-INV）——同一评估器在两个战役、两次独立 formation 上
  行为一致，评估器稳定性获得跨战役旁证（bounded，不升格）。
- O-N2：Δ4（同内容重复候选）与 Δ6/Δ10（引用组迁移）的 HOLD 证实坍缩
  规则与 referability 规则的 HOLD 侧在该 slice 内成立——与 R3-2 的
  BROKEN 侧（I-Δ3 冲突候选、A-Δ1 删除）合并后，解析规则的两侧均已
  受探针覆盖。

## 6. 下一门（全部归 human）

- R3-3 结果 second layer（本结果的验收/质疑）；
- R3-4（Consistency Synthesis）保持 LOCKED——本结果不自动开启；
- 是否开启 R3-4、或登记新的未覆盖边界（内容寻址表征、IS-X、
  condition→continuation 链接属独立研究问题），归 human 裁定。
