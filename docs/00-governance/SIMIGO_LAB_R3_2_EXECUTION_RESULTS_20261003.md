# SimiGo-Lab R3-2 Execution Results — Single-change Boundary Study

日期：2026-10-03
状态：**EXECUTED / CAMPAIGN SUPPORTED（fixture-slice bounded）— HUMAN
SECOND LAYER PENDING**
授权：human「授权 R3-2 execution（fixture 实现 + cell 运行）」（2026-10-03）。
设计：R3-2 Design rev.2（RATIFIED）；判定规则：R3-1 Spec rev.2（RATIFIED）。
Harness 源码：`simigo2-experimental/r3-2-harness/` @ `5414061`
（commit+push 先于执行——证据纪律）。

## 1. Campaign setup（§1a lock 执行记录）

```text
run_uuid            = R32-20261003T105711Z-68477
run root            = docs/02-evidence/r3-2-execution/R32-20261003T105711Z-68477
(ES, IS₀) 选择      = 一次性，按预登记准则（formation 材料齐备/真实密封
                      血统/符号名锚引用）；准则执行不依赖任何 t₀ 结果
t₀ 判定             = 一次性，于 setup 阶段（任何 ΔIS 存在之前）
Cons 版本           = R2 rev.2 candidate（Cons ⟺ I∧A∧C conditions）
判定规则            = R3-1 Spec rev.2（RATIFIED）
t₀ 结果             = I/A/C 全 SATISFIED ⇒ Cons(ES,IS₀)=true ⇒
                      cell validity 全战役固定
ES 工件哈希          = 7cd6bfc87b04d66d…
IS₀ canonical 哈希   = def59cc7d300365b…
harness 哈希         = ee4762a2ece33485…（r32_lib.py）
ES 血统             = 真实密封 R-C1 attempt #4 C-B 臂证据运输（S0/S1/
                      任务书字节逐字来自 sealed artifacts；lineage 指向
                      evidence-sha256.txt 全文哈希）
formation           = r32-formation-v1 对 canonical IS₀ 实际执行，基线
                      摘要全部由实际字节计算（无手写基线）
```

## 2. Campaign 结果（14 cell，全部机械判定）

| Cell | 类别 | t₁ I / A / C | 判读 |
|---|---|---|---|
| R32-I-Δ1（IS 侧模型声明变更） | IS-I | **I BROKEN/I-MISMATCH** · A · C | PREDICTION-MATCH |
| R32-I-Δ2（谱系目标删除） | IS-I | **I BROKEN/I-NF** · A · C | PREDICTION-MATCH |
| R32-I-Δ3（谱系目标冲突复制） | IS-I | **I BROKEN/I-AMBIG** · A · C | PREDICTION-MATCH |
| R32-A-Δ1（锚目标删除） | IS-A | I · **A BROKEN/A-NF** · C | PREDICTION-MATCH |
| R32-A-Δ2（锚目标移出边界） | IS-A | I · **A BROKEN/A-NF** · C | PREDICTION-MATCH |
| R32-A-Δ3（同址异容） | IS-A | I · **A BROKEN/A-SUB** · C | PREDICTION-MATCH |
| R32-C-Δ1（前置删除） | IS-C | I · A · **C BROKEN/C-REF-NOT-FOUND** | PREDICTION-MATCH |
| R32-C-Δ2（invalidation 记录） | IS-C | I · A · **C BROKEN/C-INV** | PREDICTION-MATCH |
| R32-C-Δ3（supersession 记录） | IS-C | I · A · **C BROKEN/C-INV** | PREDICTION-MATCH |
| R32-B-Δ1（边界收缩·archive 区） | IS-B | I · A · C 全 SATISFIED | DERIVATION-CONSISTENT |
| R32-B-Δ2（访问拒绝·archive 区） | IS-B | I · A · C 全 SATISFIED | DERIVATION-CONSISTENT |
| R32-K-1a（纯增量） | K-1 | 全 SATISFIED | CONTROL-HOLD |
| R32-K-1b（等价迁移·索引重指向） | K-1 | 全 SATISFIED | CONTROL-HOLD |
| R32-K-0（null control） | K-0 | 全 SATISFIED（与 setup 逐项一致） | CONTROL-HOLD |

完整性：`integrity_all_clean = true`（ES/canonical IS₀ 哈希跨 cell 恒等）；
t₀ 复算一致性：`t0_consistency_all = true`；instrument_doubt 全 NO；
不可归因击穿零；RQ3-4 素材零（本 slice 未触发）。

## 3. 机械判读（Spec §6.2）

```text
campaign_verdict    = SUPPORTED
batch_inconclusive  = false
依据                = 9/9 定向 cell 以预测签名击穿其定向条件且其余条件
                      不动（单变量归因干净）；K-1/K-0 全 CONTROL-HOLD；
                      IS-B cell 与构造时推导一致
```

## 4. 解释边界（claim scope，逐字义务）

**允许表述**：在本 fixture 结构类与单变化战役内，候选条件结构表现出
与 taxonomy 预测一致的行为——**条件满足性对 Information Space 变化
类别呈差分敏感**：身份类变化击穿 I、锚定类变化击穿 A、许可前置类变化
击穿 C，各自携带机械可查签名（含 silent substitution 的 A-SUB 检出）；
未引用/良性/无操作类变化不击穿任何条件；锚的等价迁移（索引重指向、
内容与摘要不变）不破坏锚定。**Cons(ES,IS) 的三条件分解在该 slice 内
对「哪些 IS 变化破坏哪个条件」给出了可归因的差分刻画**——RQ3-1/3-2/
3-3 在本 slice 内的答案为是/是/是。

**禁止表述**：
- 不得写「IPAC/Cons 已证明」「R2 候选关系已证」——本战役检验的是
  taxonomy 预测结构，非 Cons ⟺ I∧A∧C 的充分性（Cons ⇏
  LawfulContinuation 单向性不变）；
- 不得写「适用于产品/所有系统/所有表征」——结论 bounded 于
  purpose-built fixture 结构类（符号名锚引用、单一 ES 实例、文件型
  IS）；内容寻址变体与其它表征的敏感性显式 defer（设计 §2.5）；
- 不得写「Relation/PALACE/产品含义」——全程零模型推理、零 Relation
  carrier、零 PALACE；
- 不得把「定向 cell 全 PREDICTION-MATCH」升格为「预测结构普遍成立」
  ——IS-X 未实例化，RQ3-4（无法归类的 Cons change）在本 slice 零
  触发≠已排除。

## 5. 观察与偏差登记

- 偏差：零（无 deviation、无重试、无重分类；每 cell 构造记录先于
  评估、outcome 仅追加）。
- 观察 O-R1：K-1b（等价迁移）下 A 保持 SATISFIED——印证锚定绑定的是
  「可解析+内容同一」而非具体存储地址；表征敏感性问题（内容寻址下
  A-SUB 结构不可能，Spec §2.4）与该观察同向，留后续边界研究。
- 观察 O-R2：IS-B 整体边界操作（未触及被引用对象）不破坏任何条件——
  IS-B 作为独立现象类在本 slice 未显示超越 I/A/C 的额外一致性成分
  （RQ3-4 方向的否定性素材，bounded，不得升格为「IS-B 永不重要」）。

## 6. 下一门（全部归 human）

- R3-2 结果的 human second layer（本结果的验收/质疑）；
- R3-3（Counterexample / Non-break Study）是否开启：本战役的 non-break
  案例仅覆盖 K-1/B 类；R3-3 的专项反证搜索（ΔIS≠0 而 Cons 不变的更多
  形态、以及不可归因形态的主动寻找）未开始；
- R3-4（Consistency Synthesis）保持 LOCKED；
- IS-X 复合 cell 与内容寻址变体：未实例化，开启归 human。
