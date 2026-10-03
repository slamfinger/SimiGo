# SimiGo-Lab IS-X Attempt #2 Execution Results — Core Confirmation Pair

日期：2026-10-03
状态：**EXECUTED / CONFIRMATION INTERACTION-FOUND（X-08 MASKING 复现）—
AUDIT PASS（14/14）— HUMAN SECOND LAYER PENDING**
授权：human「授权 IS-X Attempt #2 execution」（2026-10-03），范围严格锁定：
A1 验证 R1 修复（X-06 重建）/ A2 验证 R2 包含修复 / A3 X-08/X-09 核心确认
对；不重跑 16 cell、不新增 op、不碰 Design rev.2/P_comp/分类、不加新边界、
R3-4 不自动开启；诚实条款预注册（X-08 若不再 MASKING 如实记录）。
Harness：`isx_confirmation.py` @ `ea55260`（commit+push 先于执行——证据
纪律；设计/预测器/分类零 diff）。

## 1. Campaign setup（§1a lock）

```text
run_uuid            = R33X-A2-20261003T130744Z-70945
run root            = docs/02-evidence/isx-execution/R33X-A2-20261003T130744Z-70945
范围                = 6 cell（X-08/X-09 核心确认对 + SANITY×3 + K-0）
fresh formation     = 密封 R-C1 #4 字节重读；零既往 run 产物读取
t₀ 判定（一次性）    = 全 SATISFIED ⇒ Cons(ES,IS₀)=true ⇒ validity 固定
四重 harness 哈希    = 钉死于 setup 记录
执行瑕疵透明登记     = 首次启动因脚本变量笔误中断于任何 cell 运行之前
                      （零 campaign 工件产生，_faulty 目录清除并登记）；
                      修复 commit 后正式执行
```

## 2. 核心确认对结果

| Cell | 判读 | 条件级分类 | H-X1 验证 |
|---|---|---|---|
| **X-08 (I-Δ2, I-Δ3)** | **MASKING（复现）** | I=MASKING，A/C HOLD-MATCH | **expected=1=actual，resolved=conflict 记录**（预登记解析路径逐项吻合） |
| X-09 (I-Δ3, I-Δ2) | **ADDITIVE（复现）** | I=BROKEN-MATCH/I-NF，A/C HOLD | expected=0=actual |

**顺序依赖结构现象跨战役复现**：同组成（Δ2+Δ3）、异顺序（Δ2→Δ3 vs
Δ3→Δ2）、异联合行为（MASKING vs ADDITIVE）——在独立 formation、独立
run-UUID、独立 t₀ 判定的 fresh campaign 中重复出现。

控制：SANITY-A→A-SUB / SANITY-I→I-MISMATCH / SANITY-C→C-INV 全按预测
BROKEN（三路径活性）；K-0 持有；integrity 全净；t₀ 复算全一致；
instrument_doubt 全 NO；**零 CI 违例（R1 修复在运行中生效）**。

## 3. 修复验证（A1/A2）

```text
A1（R1 对象/效果恒等探针）：
  - 确认 cell 运行中零 CI 违例（Attempt #1 同型组合下曾误报）
  - 独立重建（A-Δ3∘A-Δ2）组合（Attempt #1 cell-06 同型）：修订探针
    零误报——替换效果经迁移存续被正确识别（legal migration ≠ effect
    disappearance 的机械实证）
A2（R2 审计包含）：
  - 分类重算仅施于有效 pair cell；SANITY/K-0/INCONCLUSIVE 一律排除
    出分类统计（Attempt #1 的范围缺陷不再出现）
```

## 4. 判读与审计

```text
campaign_verdict（confirmation-scoped, per design §7 rev.2）
                   = INTERACTION-FOUND
依据               = X-08 MASKING 确认（H-X1 期望验证相等）+ 全控制持有
                     + 零 INCONCLUSIVE（H-2/S-N4 满足）
second_layer_audit = AUDIT PASS（14/14）
透明登记           = 审计 v1 一次 FAIL 系审计表达式布尔优先级缺陷+
                     判读报告缺 interactions 字段（判读脚本省略）——
                     均为审计/判读脚本层缺陷，底层 cell 数据零变更；
                     interactions 字段从 per_cell 旗标机械重建（零判定
                     变更）+ 表达式修正后复跑 ⇒ 14/14；全程透明登记
```

## 5. 解释边界（claim scope，逐字义务）

**允许表述**：
- X-08 MASKING 在独立 fresh campaign 中**复现**，且每次均在预登记
  construction/resolution expectation 与实际解析逐项一致的条件下一致
  出现——**candidate interaction finding 升格为 confirmed（复现级）
  interaction finding，bounded 于当前 fixture/表征/操作对**；
- 顺序依赖联合行为（X-08 MASKING vs X-09 ADDITIVE，同组成异顺序）跨
  战役复现——非「一般非交换性」，只=该操作对在该表征内的稳定结构
  现象；
- 机制读法（bounded）：组合可**遮蔽**单变量击穿——I-condition（按
  Spec 操作化=可评估性）在联合态恢复 SATISFIED 而解析收敛于冲突记录：
  **解析成功 ≠ 谱系正确；机械规则按定义不判语义正确性**——操作化
  边界（RQ3-4 方向）的一手实证。

**禁止表述**：
- 不证 Cons law 推翻/证伪（IS-X 对象=单变量机械预测 vs 联合观测，
  非直接检验 Cons≡I∧A∧C；且 I 的操作化=可评估性）；
- 不证一般 interaction/一般非交换性（单操作对、单 fixture、单表征）；
- 不升格普遍 Cons/条件完备性；RQ3-4 保持开放（「条件被违反但评估器
  无从表示」的形态仍在操作化边界之外）；
- 不开启 continuation/PALACE/IPAC/Route 推论（全程零模型零 Relation
  零 PALACE）。

## 6. Attempt #1 与 Attempt #2 的关系（三层边界维持）

```text
Attempt #1 campaign verdict = INCONCLUSIVE（永久保留——reaudit/复现
                              均不改写历史战役判读）
Attempt #2 confirmation     = INTERACTION-FOUND（confirmation-scoped，
                              独立 campaign 独立判读）
合并读法                    = X-08/X-09 现象在两个独立 campaign（attempt
                              #1 有效 cell 数据 + attempt #2 确认战役）
                              中一致出现——双侧证据（BROKEN 侧 R3-2、
                              HOLD 侧 R3-3、交互侧 IS-X attempt#1+#2）
```

## 7. 下一门（全部归 human；R3-4 不自动开启）

- IS-X Attempt #2 结果的 human second layer；
- **R3-4（Consistency Synthesis）开启决定**——当前证据基础：R3-2
  SUPPORTED（BROKEN 侧）+ R3-3 NO-COUNTEREXAMPLE（HOLD 侧）+ IS-X
  confirmed interaction（交互侧）：in-scope 结构类（单变量定向/单变量
  HOLD/复合）已全部受探针，综合的限定词负担显著低于 R3-3 second layer
  时的评估——是否开启、以何种范围开启归 human；
- 或以有界收官方式关闭 R3（IS-X 交互侧结论作为收官证据之一）。
