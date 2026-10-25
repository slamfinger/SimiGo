# SimiGo-Lab R3-2 Results Audit — Human Second Layer

> **ARCHIVED** 2026-10-20 · line: 通用治理 / 其他 · original: docs/00-governance/SIMIGO_LAB_R3_2_RESULTS_AUDIT_20261003.md
> Evidence status: unchanged (content frozen; moved only)


日期：2026-10-03
状态：**AUDIT PASS（16/16 机器检查全过）— 结果审查 ≠ R3-3 授权**
授权：human R3-2 second layer 指令（2026-10-03）——审查对象为「结果是否
足以支持当前 SUPPORTED 判读」，非设计重审、非实验重跑。
审计工具：`simigo2-experimental/r3-2-harness/r32_second_layer_audit.py`
（@`51993d8`，commit+push 先于审计运行——证据纪律）。
审计对象 run：`R32-20261003T105711Z-68477`。

## 1. 审计结果（human 八项焦点 → 16 项机器检查）

| human 焦点 | 机器检查 | 结果 |
|---|---|---|
| 证据链闭合（setup→construction→t₀→ΔIS→t₁→integrity 逐 cell 连通） | A1：14/14 cell 的 construction（locked_before_evaluation=true+哈希钉定）→t₀（与 setup 逐项一致）→integrity（ES/IS₀ 哈希不变）全链闭合；A7：append-only 观测中每 cell 五事件完整有序（construction_locked→t0_evaluated→op_applied→t1_evaluated→integrity_verified），单调钟非降，run_uuid 唯一，构造/结果文件物理分离 | **PASS** |
| 签名与预注册预测一一对应（非事后解释） | A2：逐 cell 将 t₁ 实际（state+signature）与 construction.json 内**评估前锁定**的 prediction 一一比对——14/14 一致；构造记录先于评估由文件顺序+观测序列证明 | **PASS** |
| 9 个定向 cell「只击穿目标条件」逐 cell 原始证据 | A3：逐 cell t₁ 原始记录核验——目标条件 BROKEN 且带签名、其余两条件原始 detail 为 SATISFIED（非推断）；9/9 成立（IS-I→I-MISMATCH/I-NF/I-AMBIG；IS-A→A-NF/A-NF/A-SUB；IS-C→C-REF-NOT-FOUND/C-INV/C-INV） | **PASS** |
| IS-B「未触及被引用对象」由操作记录证明 | A4：**从构造时 IS₀ 索引独立重算** region∩referenced——archive/ 区仅含 archived-note（未被引用），与被引用键集 {I-S0,I-S1,anchor:state-diff,lineage-root,runtime-declaration} 交集为空——该证明独立于 t₁ 结果；IS-B cell 的全 SATISFIED 与构造时推导一致（非反推） | **PASS** |
| K-1b 等价迁移是否真保持 binding invariant | A5：对 cell-13 实际树核验——锚符号名解析至 objects/store-v2/R-1.json、in_boundary=true、内容摘要==ES formation 摘要；原路径 objects/R-1.json 已腾空（迁移真实发生，非名义） | **PASS** |
| 14 cell 相互独立（无隐性累积状态） | A6：**frozen-op replay**——对每个 cell，从 canonical IS₀ 新拷贝重放该冻结操作，要求结果树与该 cell 的 IS 树**逐字节一致**——14/14 通过（任何隐性累积/串染都会破坏重放）；另核 K-0 cell 的 IS 树与 canonical IS₀ 哈希恒等 | **PASS** |
| append-only 观测与独立判读无污染 | A7（如上）+ A8：审计独立重算每 cell 判读，与独立判读进程（adjudicate）的 14/14 verdict 一致 | **PASS** |
| SUPPORTED 严格符合 Spec §6.2（不超出预注册判读规则） | A8：按 §6.2 预注册规则重算——batch_inconclusive=false + 9/9 定向 PREDICTION-MATCH + 3/3 对照 CONTROL-HOLD ⇒ SUPPORTED；记录值即 SUPPORTED，无任何加宽表述 | **PASS** |

**审计判定：AUDIT PASS（16/16）。零失败项、零偏差项、零未决项。**

## 2. second layer 确认的实质性结果（human 六点逐项登记）

1. **H-A campaign setup lock 获首次实证执行记录**：(ES,IS₀) 于任何 t₀
   结果前一次性确定、t₀ 一次性判定；无换 IS₀、无重试 setup、无重分类
   路径被触发——反选择偏差约束从设计条款变成有执行记录的既成事实。
2. **差分归因结构干净**：定向变化产生预注册的 I/A/C 签名（非泛化性
   全坏）；K-1/K-0 保持提供必要对照。
3. **H-C 修正产生可观察后果**：I-NF/I-STRUCT 类在「既有结构存在+唯一
   变量改变」条件下作为 I-condition BROKEN 签名被记录（A2 逐 cell
   核验），未被模糊化为 instrument doubt——rev.2 修订非形式性。
4. **「零 instrument doubt」保持限缩读法**：仅说明本 campaign 未触发
   预登记仪器疑云路径；不构成「实验绝对可靠」的一般性结论（human
   原话登记）。
5. **SUPPORTED 严格 slice-bounded**：实际支持的命题=「在本次 fixture、
   ES 结构、符号名锚引用、文件型 Information Space、预注册 ΔIS 类别与
   观察程序下，Cons 条件表现出预测的差分敏感性」；**不**支持
   「Information Space 改变普遍导致 Execution State consistency 改变」。
6. **RQ3-4 未被提前回答**：无「I/A/C BROKEN⇒continuation failure」
   推导；无「Cons 普适定律」宣称。

## 3. 下一步（结果审查 ≠ R3-3 授权）

本审计通过**不自动开启 R3-3**。真正待决的是 human 的更窄问题：

> **R3-2 的 bounded empirical result 是否足以授权进入 R3-3，以及
> R3-3 应验证哪个尚未被当前结果覆盖的边界。**

当前结果未覆盖的边界（R3-3 候选素材，仅登记不预设）：
- 反证方向的非 break 形态远窄于 K-1/B（R3-N 专项搜索未开始）；
- IS-X 复合变化（词汇已封闭：仅已冻结操作组合）未实例化；
- 内容寻址等其它引用表征下的 A 行为（表征敏感性）defer 中；
- 「条件破坏⇒continuation failure」的 R2 候选关系检验不在 R3 范围
  （R3 全程无模型），如需检验属独立 gate。

全部排除清单维持（P/IPAC/PALACE/MCP/Route/后端适配/产品实现/性能/
模型比较/完整恢复系统）；R3-4 保持 LOCKED。
