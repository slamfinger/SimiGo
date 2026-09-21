# Track E(命名待定)Residency Policy Simulator v0 结果 v2(2026-09-21)

> **状态:v0 等大小重跑完成(合成 workload,纯 Python;待审核方正式
> 终判)。** 代码:`residency_policy_simulator_v0.py`(seed=42,可再生)。
> **v2 修订(审计)**:node size 固定为等大小——可变 size 下
> farthest-next-use 只是启发式,不构成严格 reference bound;size 轴
> 归入 H-P1 sensitivity(后续版本)。口径修正:全部 **24 个非退化**
> (budget < 1.00)组合。

## 模型(v2)

32 节点 × 等大小(size=1,合计 32),trace 2000 步,四种 locality
(short/medium/long/very-long),预算 = 20%–100%。四策略:always
(永不外化,violation 逐 step 记)/ pressure(≥90% 预算主动外化)/
lru(被动)/ **oracle(等大小下 = 标准 Belady,严格 reference
bound;C_ext 占比 ~4%,最优性为惯例近似)**。

## 核心结果(v2 数字)

**1. 决策空间在全部 24 个非退化组合可观测**:lru/oracle =
**1.33–3.05**,无一低于 1.10(budget=1.00 时 oracle 边界成本为 0,
比值无定义,共 28 组合中 24 个非退化)。

**2. 差异随预算升高扩大**:0.20 → 1.33–1.64(低预算全域 thrash,
策略趋同的"策略无关区");0.80 → 2.69–3.05。

**3. C_rehydrate sweep(0.40/medium)**:各策略成本随 C_rehydrate
线性放大(0.25 → 8),无排序翻转;边界成本越贵,外化决策越有价值。

**4. oracle 健全性检查通过**:全域 ≤ 一切 baseline(reference bound
参与结论的前置条件;承 v1 教训,本次作为显式检查项执行)。

## H-P0 / H-P1 状态(按审计降级后的表述)

- v0 已证:**该合成 workload 中,存在可由未来复用信息区分的
  residency decision space;LRU 与 future-aware reference 之间存在
  可测差距**(1.33–3.05)。
- 这证明"未来复用信息**可能**具有 decision-relevant value",**尚
  不足以判定 H-P0**——v0 比较的是 LRU vs future-perfect reference,
  未测试 memory pressure + reuse 的可实现策略;H-P0 的可实现策略
  检验与 H-P1(树依赖增量)的正式判读均留给 P3。

## 诚实性注记

1. C_resident = 0 未建模(P0 prerequisite)——全部结论是
   boundary-cost 视角;
2. SKIP 未建模(访问外部节点 = 强制 rehydrate);
3. 合成 workload、单 seed、等大小节点;regret 描述性;
4. 无 GPU / 无 SimiGo runtime;live(P4)仅在 P3 显示可实现策略
   差异 > 噪声后。

## v1 史料(两次 oracle 修正,均如实保留)

1. **v1-a**:oracle 用静态"全局最后出现位置"冒充逐步 next-use →
   reference bound 普遍低于 LRU(物理不自洽)。修正 = Belady 式
   逐步 next-use + 稳定种子(替换跨进程不定的 `hash()`)。教训:
   **上界实现 bug 会伪装成"策略无差异"或"基线更好",上界须先过
   健全性检查(≤ 一切 baseline)**。
2. **v1-b(本次审计)**:可变 node size(1–10)下 farthest-next-use
   不是严格 Belady(weighted caching 问题),oracle 实为启发式。
   修正 = v0 等大小化(最小变量原则;size 轴属 H-P1,不能既当待验
   信号又当 bound 基础)。教训追加:**reference 的模型假设本身也要
   过检(equal-size?weighted-size?)**。v1-b 数字(1.35–3.05,
   可变 size)已被 v2 等大小数字取代,不作为结论引用。

## 决策

1. **v2 数字入档 → 待审核方正式终判**(审计预评:修后可进入正式
   终判);
2. **P0 = Cost model closure**(C_resident 计价)排期首位;simulator
   本轮定位 = P1(baseline sanity)/ P2(sensitivity)exploratory
   probe;
3. P3:new policy(可实现 future-reuse 启发式)对 LRU;树依赖增量
   (H-P1 强形式)需结构化 workload,其后;
4. Track E 正式命名待真源定夺。
