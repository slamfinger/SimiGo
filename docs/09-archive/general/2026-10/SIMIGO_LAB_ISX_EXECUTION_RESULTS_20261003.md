# SimiGo-Lab IS-X Execution Results — Compound ΔIS Interaction Probe

> **ARCHIVED** 2026-10-20 · line: 通用治理 / 其他 · original: docs/00-governance/SIMIGO_LAB_ISX_EXECUTION_RESULTS_20261003.md
> Evidence status: unchanged (content frozen; moved only)


日期：2026-10-03
状态：**EXECUTED / CAMPAIGN INCONCLUSIVE（局部化：单 cell 构造完整性探针
实现缺陷）— AUDIT 9/11（两处 FAIL 均已定位）— HUMAN SECOND LAYER PENDING**
授权：human「授权 IS-X execution」（2026-10-03）；设计 rev.2 零修改；
R3-4 LOCKED 维持。
Harness：`isx_*.py` @ `cce102d`（commit+push 先于执行——证据纪律）。

## 1. Campaign setup（§1a lock）

```text
run_uuid            = R33X-20261003T122818Z-70152
run root            = docs/02-evidence/isx-execution/R33X-20261003T122818Z-70152
t₀ 判定（一次性）    = I/A/C 全 SATISFIED ⇒ Cons(ES,IS₀)=true ⇒
                      validity 全战役固定
harness 哈希         = r32_lib ee4762a2… + r3n_lib 39c93950… +
                      isx_lib（三重钉死于 setup 记录）
formation           = fresh（密封 R-C1 #4 字节重读；零既往 run 产物读取）
```

## 2. Campaign 结果（16 cell）

| Cell | 有序对 | 判读 | 条件级分类 |
|---|---|---|---|
| X-01 (I-Δ2, A-Δ1) | 跨 I×A | **ADDITIVE** | I BROKEN-MATCH/I-NF + A BROKEN-MATCH/A-NF + C HOLD |
| X-02 (I-Δ1, C-Δ2) | 跨 I×C | **ADDITIVE** | I-MISMATCH + C-INV |
| X-03 (A-Δ3, C-Δ2) | 跨 A×C | **ADDITIVE** | A-SUB + C-INV |
| X-04 (I-Δ2, C-Δ1) | 跨 I×C | **ADDITIVE** | I-NF + C-REF-NOT-FOUND |
| X-05 (I-Δ1, I-Δ2) | 同 I | **ADDITIVE** | I-MISMATCH（∈ sig-set{I-MISMATCH,I-NF}） |
| **X-06 (A-Δ3, A-Δ2)** | 同 A | **INCONCLUSIVE（S-X2 CI-2）** | 见 §3 根因定位 |
| X-07 (C-Δ2, C-Δ3) | 同 C | **ADDITIVE** | C-INV |
| **X-08 (I-Δ2, I-Δ3)** | 同 I 序-1 | **MASKING** | P_comp=I BROK{I-NF,I-AMBIG}；actual I SATISFIED；**resolution expectation 验证相等（expected=1/actual=1，resolved=conflict 记录）** |
| X-09 (I-Δ3, I-Δ2) | 同 I 序-2 | **ADDITIVE** | I-NF（∈ sig-set） |
| X-10 (Δ6, Δ10) | HOLD×HOLD | **ADDITIVE** | 全 HOLD |
| X-11 (Δ8, Δ9) | HOLD×HOLD | **ADDITIVE** | 全 HOLD |
| X-12 (B-Δ1, A-Δ2) | 跨类 | **ADDITIVE** | A-NF + 全 I/C HOLD |
| SANITY-A/I/C | 正控 | **SANITY-OK ×3** | A-SUB / I-MISMATCH / C-INV（三路径活性证实） |
| K-0 | 对照 | **CONTROL-HOLD** | 与 setup 逐项一致 |

完整性全净；t₀ 复算全一致；instrument_doubt 全 NO；INVALID-COMPOSITION
零。

## 3. Campaign 判读：INCONCLUSIVE（传染规则）+ 根因定位

```text
campaign_verdict = INCONCLUSIVE
原因             = H-2/S-N4 传染：cell-06 S-X2 构造完整性 CI-2 违例
                   ⇒ 该 cell 判定不可用 ⇒ 战役不得宣称 ALL-ADDITIVE/
                   INTERACTION-FOUND
```

**根因定位（字节级证据，本战役最重要产出之一）**：

- cell-06 组合物**形成正确**：CI-4 replay 恒等通过（组合树 ==
  op_a∘op_b 预登记重放树逐字节）；无 op 错误（composition=OK）；
- **A-Δ3 的替换效果在组合态中存留**：universe/R-1.json（A-Δ2 迁移后
  位置）内容摘要 `5c633798…` ≠ IS₀ R-1 摘要 `03332d18…`——替换字节
  经迁移存续；
- CI-2 失败仅因**效果探针按路径钉死**（断言 objects/R-1.json differs，
  而该路径已被 A-Δ2 合法迁空）——**实现层探针缺陷（路径基 vs 对象
  追踪语义），非真实构造交互**；
- 按 RATIFIED 规则 S-X2：探针失败照记、cell 判 INCONCLUSIVE（其判定
  不可用）；按 S-N4/H-2：战役 INCONCLUSIVE。**未做任何现场修补。**

## 4. 独立审计结果（9/11，两处 FAIL 均已定位）

```text
PASS  hygiene×3 / 链闭合 16/16 / CI-4 replay purity / CI-5 顺序 /
      H-X1 X-08 期望验证（expected=1=actual）/ H-X1 X-09（expected=0
      =actual）/ 出口结构 / 其余
FAIL  CI 重验证——cell-06 同一根因（上述）
FAIL  分类重算一致性——审计脚本自身范围缺陷：对被判 INCONCLUSIVE 的
      cell-06 也重算分类（判读器已在 CI 检查处排除），导致 12/12 比
      对失败——审计实现观察，如实登记
```

## 5. 实质发现（per-cell 数据；因战役 INCONCLUSIVE 不作 campaign 级宣称）

- **F-1（X-08 MASKING candidate）**：两个单独均可击穿 I 的操作组合后，
  I 条件恢复 SATISFIED——解析收敛于冲突记录（预登记期望逐项吻合）。
  机制读法（bounded，待清洁重跑确认）：**组合可以遮蔽击穿**——解析
  成功≠谱系正确，机械规则（可评估性）按定义不判语义正确性；这是
  RQ3-4/操作化边界方向的一手素材。
- **F-2（顺序依赖）**：X-08（Δ2→Δ3）=MASKING vs X-09（Δ3→Δ2）=
  ADDITIVE——同一组成、不同顺序、不同联合行为；预注册有序对使该
  结构现象可见。
- **F-3（构造层交互现象）**：op_b 的重定位使 op_a 的效果位点迁移
  ——CI 探针须按对象追踪而非按路径钉死；该现象本身即「组合可位移
  效果位点」的一手证据（正是 IS-X 研究的构造层交互）。

## 6. 纪律路径（全部归 human；不自动重跑）

按执行约束「需要修改的问题⇒停下进新 review/gate」与 R-C1 工程发现
模式：

```text
① 本 campaign 全量保全为证据（INCONCLUSIVE 非失败）
② harness 探针修订（效果断言对象化：跟随引用迁移而非路径钉死）
   属 implementation revision ⇒ 须独立 review/reaudit
③ 修订通过后，IS-X attempt #2 须**新的显式 execution authorization**
   （本授权已消耗于本次 campaign）
④ R3-4 保持 LOCKED——INCONCLUSIVE 战役不构成综合输入
```

## 7. 解释边界

- 战役判读=INCONCLUSIVE；**禁止**从中宣称 ALL-ADDITIVE 或
  INTERACTION-FOUND（含 X-08 MASKING——其为 per-cell candidate，等
  清洁重跑）；
- 禁止由 F-1 推导「组合语义已明」或任何普遍命题；
- 全部排除清单维持；R3-4 LOCKED。
