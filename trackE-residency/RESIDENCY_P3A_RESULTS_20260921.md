# Track E(命名待定)Residency P3-A 模型验证 + 首轮判别结果(2026-09-21)

> **终审判定(2026-09-21):P3-A——CONDITIONAL PASS;机制框架 PASS、
> 首轮结果 PASS(provisional / implementation-under-test evidence)、
> 正式模型判别 CONDITIONAL PASS。** 两个实现层问题(非设计问题):
> ① **W=200 滑动窗口未实现**(window 从未剪枝,n_i = 全历史计数而非
> 最近 200 步计数)——**必须修复后重跑**的阻断项;② P_pressure 实为
> **raw excess-steps proxy**(ms 校准 NOT YET),文档不得混写为已校准
> ms 通道;③ lfu_aging 实为 **cumulative-frequency LFU variant**
> (decay 定义未执行),或补真 aging 或正名。
>
> **v2 重跑(修复后,本节数字为准;v1 数字降为 provisional)**:
> **cost_aware_greedy(H=8)= 547.3,vs lru −43.8%(hot)/ −18.7%
> (tree)**——外审预判证实:此前"+20.8%/+14.3% 劣于 lru"与"H 强主导"
> 是 **W-bug 伪象**;修复后 H≥8 收敛(H=4=815.2,较 H=8 差 +49.0%,
> 但仍优于 lru −16.2%),"饱和层 +
> id tie-break 病态"假设部分证伪(H≥8 无病态)。H 敏感性仍存在但
> 有界且收敛。**待复现假设的复验结果**:机制观察保留,H 方向修正。
>
> **重跑后判别表(B=12;hot/tree)**:
>
> | 策略 | hot J | vs lru | tree J | vs lru |
> |---|---|---|---|---|
> | lru(baseline) | 973.1 | — | 1422.9 | — |
> | lfu_aging(cumulative-freq + 每200步半衰 aging) | 544.4 | −44.0% | 1085.9 | −23.7% |
> | cost_aware_greedy(H=8,W=200) | 547.3 | **−43.8%** | 1156.4 | **−18.7%** |
> | belady_greedy(reference) | 475.3 | −51.2% | 740.4 | −48.0% |
>
> H sensitivity(hot):H=4 → 815.2(vs lru −16.2%;vs H=8 +49.0%
> 较差)/ H=8 与 H=16 均收敛于
> 547.3——H 影响存在但有界收敛。P_pressure 通道保持 **raw excess-
> steps** 口径(全策略 ≈1990/2000,结构性饱和,与 P0.2 容量内平坦
> 互证;ms 校准 NOT YET)。
>
> **v2 复跑 provenance 闭合(2026-09-21,外审两审计项证据落盘)**:
> 在 301e3f1 代码原样(HEAD 一致、tree clean、simulator sha256
> 5dbc8cc0…、Python 3.14.5)上实际执行全矩阵,产物入档
> `runs/P3A_V2_RERUN_PROVENANCE_20260921/`。**发现并修正一处 stale
> 数字**:上表 tree/lfu_aging 原记 1084.5(−23.8%)为 pre-decay 语义
> 残留——对照实验(仅运行时 patch LFU_DECAY_INTERVAL→∞,即 301e3f1
> 前语义)精确复现 1084.5=rehy 775/ext 763,decay-ON 实际值 =
> **1085.9**(rehy 776/ext 764,恰一对 rehy+ext 之差;−23.7% vs
> lru);hot 上 decay 决策中性(两种语义均 544.4),故 v1→v2 未暴露。
> **其余全部数字(主表 7 格 + H 敏感性 + pressure 全通道)经实跑
> 逐位一致**;排序与结论不翻转(lfu 仍优于 cag,频率信号结论保留)。
> lfu_aging 标签同步澄清:语义 = cumulative-frequency 计数 + 每 200
> 步半衰 aging(驱逐 key=(freq,last_access,id)),标签改写消除
> 与"cumulative-freq variant"旧注记的冲突。H=4 口径修正:vs lru
> −16.2%(优),vs H=8 +49.0%(差);"较差"仅在相对 H=8 时成立。
> P3-A 提升 PASS / UNLOCK 与否,待审核方对本套产物终判。

> **v1 记录(史料,W-bug 数字降为 provisional)**:下文 v1 数字
> (H=8 +20.8%/H=16 −20.7% 等)为全历史计数 bug 下的产物,不可作为
> 冻结公式正式数字引用;"饱和层 + id tie-break 病态"假设已由 v2 重跑
> 部分证伪。 代码:`residency_policy_simulator_v3.py`(lab 仓;seed=42)。
> 冻结规范严格执行:W=200、reuse_score=min(1,n/H)、argmin Score、
> tie 最低 id、H∈{1,4,8,16} 主轮 8、双情景同 trace/seed/策略/预算。

## P3-A 机制验证(PASS)

- 五通道输出(可行性/J_boundary/rehy+ext 计数/超限步/终态驻留)正常;
- 双情景通道(k_c 触发的 P_pressure)正常记录;
- 确定性自检(同配置重跑逐字段一致)PASS;
- NORMS①②③(事件时序/tie-break/working-set)执行无违反。

## 首轮判别数据(B=12 固定基线;hot/tree;H=8 主轮)

| 策略 | hot J | tree J |
|---|---|---|
| lru(baseline) | 973.1 | 1422.9 |
| lfu_aging | 544.4(**−44.0%**) | 1084.5(**−23.8%**) |
| cost_aware_greedy(H=8) | 1176.1(**+20.8%**) | 1627.3(**+14.3%**) |
| belady_greedy(reference) | 475.3 | 740.4 |

### cost_aware_greedy 的 H 敏感性(hot 域)

| H | J | 相对 lru |
|---|---|---|
| 4 | 1348.1 | +41.9% |
| 8 | 1176.1 | +20.8% |
| 16 | 771.4 | **−20.7%** |

## 判读(描述性;正式结论待终判)

1. **频率信号有效且幅度大**:lfu_aging(修复后)对 lru 在双 workload
   均显著优(hot −44.0%,tree −23.8%)——reuse 频率信号的可实现
   证据强化 H-P0 的"pressure + reuse"半边。
2. **cost_aware_greedy(H=8)劣于 lru 是真实的机制级发现**:
   reuse_score = min(1, n/H) 在 H=8 下对热节点(窗口内 ≥8 次)全部
   饱和为 1,饱和层内 argmin 退化为**最低 id 驱逐**——病态行为;
   H=16(饱和尺度放宽)时反超 lru(−20.7%)。**frequency-only
   instantiation 是调参强依赖的,不是稳健的 cost-aware 政策**——
   这是 H-P0 检验的诚实中间结果:实现了"cost-aware framework 的
   第一个最小实例",该实例本身不稳健。
3. **P_pressure 通道结构性饱和(重要设计发现)**:k_c ∈ {9,10,11}
   (< B=12)时全策略 steps_excess ≈ 1990/2000——所有可行策略都
   填满至 B,超限步数只度量 trace 长度,不区分策略;**与 P0.2"容量
   内平坦"互为印证**;真实悬崖是 ms 效应,抽象步数通道不建模
   (ms 校准属 P0.2 曲线/P4 Swift)。该通道在"策略可自愿低于容量"
   的扩展模型中才有区分度。
4. **H-P1 未检验**(structure-aware 不入本轮,按设计)。

## 诚实性注记

1. **v3 首版实现 bug 如实记录**:lfu_aging 漏 freq 递增导致与 lru
   输出完全相同(退化 lru);修复后重跑为本结果。修复前后数字
   均未入档作结论;
2. cost_aware_greedy 的 W/H 参数为设计冻结首选值,未调优;其形态
   (饱和+id tie-break)的病态是本轮发现,非秘密调参对象;
3. 合成 workload 单 seed;regret 描述性;C_resident 未入模;
4. 不反推 Track B / M 链 / P0 系列。

## 决策

1. **P3-A 数字入档 → 待审核方终判**;
2. **后续候选(待审核定夺)**:cost_aware_greedy 形态修正
   (reuse_score 非饱和化,如对数/排名分)→ structure-aware 重设计
   (H-P1)→ nodes-out 评估;
3. Track E 命名继续待 P3 证据。
