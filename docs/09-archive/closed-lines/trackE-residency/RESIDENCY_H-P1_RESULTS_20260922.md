# Track E H-P1 结果文档:结构信号存在性检验(2026-09-22)
**H-P1:CLOSED / SEALED(远端 68aa374 提交级审计后最终署名)**

> 设计 = `RESIDENCY_H-P1_DESIGN_20260922.md` v0.1.2(PASS/LOCKED);
> Hot Null v2 校准设计 = `RESIDENCY_H-P1_HOT_NULL_V2_DESIGN_20260922.md`
> (PASS/SEALED)。本文档归档全链证据;后续不修改设计、不重跑、不调参。

## 1. 全链门位时间线(全部远端逐提交审计)

| 门 | 提交 | 结果 |
|---|---|---|
| 设计 DRAFT v0.1 | 47aeebc | CONDITIONAL PASS(2 BLOCKER+3 澄清) |
| 设计 v0.1.1 | 4c64c8d | CONDITIONAL PASS(2 BLOCKER+1 补充) |
| 设计 v0.1.2 | 802e150 | **PASS / LOCKED** |
| v6 实现+全冻结回归门 | f1eb28d→4144f72 | L2 空检查 BLOCKER 修复后 **PASS**(exit 0) |
| Tier-1 L1 首轮 | 0cc6587 | hot 触线 → **有效停机**;泄漏审计 PASS(无泄漏) |
| Hot Null v2 设计 | 30a6c16 | PASS / LOCKED(先注册后执行) |
| 校准执行+Tier-1 重跑 | f58fe49 | sentinel 三类全过;**PASS** |
| L1 出口署名 | (远端) | S1/S2/S3 三类 **L1 PASS**(seed-42 Tier-1 experimental-domain fact) |
| L3 采数 | 68aa374 | 哨兵全过;**最终裁定确认** |

## 2. L1 关系检验(Tier-1;存在性线 tree |ρ|≥0.1)

事件集 = 各 workload 自身 lru∪C 去重 (node,t);oracle Y=未来再访问;
信号=O1 在线单形式(S1=pos/S2=A_anc/S3=A_chain self-excluded);
Spearman 平均秩双侧。

| 类 | tree ρ | n | hot ρ(校准后 sentinel) | L1 出口 |
|---|---|---|---|---|
| S1 | −0.5218 | 1752 | +0.0837 ≤ Q95 0.2514 | **PASS** |
| S2 | −0.4767 | 1752 | −0.1044 ≤ Q95 0.2531 | **PASS** |
| S3 | −0.3418 | 1752 | −0.2493 ≤ Q95 0.4105 | **PASS** |

精度级:**seed-42 Tier-1 experimental-domain fact**(Tier-2 seeds 43–47
未执行,不得声称生成域普遍性)。方向描述(审核方核定措辞):在
seed-42、P3 冻结 tree 拓扑及本轮预注册实验域内,S1/S2/S3 与未来缺失
成本均呈负 Spearman 相关;方向与生成器预设方向一致;支持预定义关系
存在,不构成因果机制证明。L1 existence ≠ mechanism attribution。

## 3. hot 阴性对照:从误触线到定量校准(本轮方法论收获)

首轮 hot 对照(固定 |ρ|<0.1)对 S2/S3 触线(−0.1044/−0.2493)→ 触发
有效停机 → 泄漏审计 PASS(实现层无未来信息泄漏:信号纯函数/oracle
隔离/引擎逐位等价/双源排除)→ 裁定:原 sentinel"访问均匀 ⇒ ρ≈0"
推论不成立(生成域独立 ≠ 事件层 null),属对照 estimand 定义不足。
Hot Null v2:固定 trace/事件集/Y/权重,仅置换 node↔topology 标号
(N=10000,seed 20260922),逐类 Q95 次序统计量。结果:S3 零分布
Q95=0.4105,定量解释误触线;三类 observed ≤ Q95 → sentinel 全过,
**SEALED**。

## 4. L3 策略检验(Tier-1;判据主方向 J<J(C)=1085.9)

| 类 | 形态 | tree J | hot J(披露) | L3 | 出口 |
|---|---|---|---|---|---|
| S1 | P_S1(−pos) | **1073.2** < 1085.9 | 1400.3 | **PASS**(裕度 12.7) | **D** |
| S1 | P_S1s(敏感) | 2178.6 | 1517.3 | 未达成(如实报告) | — |
| S2 | P_S2(−A_anc) | 1087.3 | 1424.3 | FAIL(+1.4) | **C** |
| S2 | P_S2s | 2132.1 | 1697.8 | FAIL | — |
| S3 | P_S3(+A_chain) | 1951.6 | 1857.1 | FAIL | **C** |
| S3 | P_S3s | 1264.9 | 1325.6 | FAIL | — |

哨兵(全部形态):确定性重跑逐位一致 + L2 运行时审计 + 一致性下界
dd ≥ |Δrehy|(vs lru)+ violations=0,全过。

## 5. 逐类出口(远端最终署名,68aa374 审计)

- **S1 → 出口 D**:L1∧L2∧L3 全 PASS;结构策略成立的实验性证据
  (seed-42 Tier-1);结构信号 S1+策略形态 P_S1 进 P4 机制清单
  (**候选机制**;12.7 裕度不大,不作普适机制);target 采纳另行立项。
- **S2 → 出口 C**:信号存在且在线可计算,主方向策略未胜 C
  (+1.4);L1 ρ 高不豁免 L3——"有结构信号 ≠ 能形成有效策略";
  未验证机制候选/诊断线索入档。
- **S3 → 出口 C**:L1 关系存在(|ρ|=0.3418)但策略化未兑现;
  "结构信息存在,但当前结构价值函数/控制方式不足以转化为有效驻留
  决策"的诊断样本;不进已验证清单,不删除。

**最关键研究结论**(审核方表述):结构关系 → 在线可计算 → 策略兑现
三个层次被真正拆开并逐级验证;S1 是唯一走完整条链的结构候选。

## 6. 结束与下游

H-P1 **CLOSED / SEALED**(§7:任一逐类出口即结束);不做 Tier-1 重跑、
不改方向、不调参、不加信号、不合并评分、不改 0.1 线、不改 Hot Null v2。
**nodes-out:UNLOCKED;P4:可进入立项门位**。P4 mechanism list input:
S1(D,experimental evidence/candidate mechanism,shape=P_S1);
S2/S3(C,unverified candidate/diagnostic clue)。

## 7. 证据索引

- 设计:`RESIDENCY_H-P1_DESIGN_20260922.md`(v0.1.2)、
  `RESIDENCY_H-P1_HOT_NULL_V2_DESIGN_20260922.md`
- 引擎:`residency_policy_simulator_v6.py`(回归门+结构策略);
  `hp1_tier1_l1.py`(L1);`hp1_hot_null_v2.py`(校准);
  `hp1_tier1_l3.py`(L3)
- 产物:`runs/HP1_V6_REGRESSION_GATE_PROVENANCE_20260922/`、
  `runs/HP1_TIER1_L1_PROVENANCE_20260922/`(含触线 stdout/泄漏审计/
  两份远端裁定入档)、`runs/HP1_HOT_NULL_V2_PROVENANCE_20260922/`、
  `runs/HP1_TIER1_L3_PROVENANCE_20260922/`(含出口裁定入档)
- 提交链:47aeebc→4c64c8d→802e150→f1eb28d→4144f72→0cc6587→
  30a6c16→f58fe49→68aa374
