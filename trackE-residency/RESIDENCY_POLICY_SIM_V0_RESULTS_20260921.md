# Track E(命名待定)Residency Policy Simulator v0 结果(2026-09-21)

> **状态:v0 首跑完成(合成 workload,纯 Python;数字即结果,待审核
> 方终判)。** 代码:`residency_policy_simulator_v0.py`(seed=42,可再生)。
> 设计按开题 v2:决策统一两动作;LRU/Pressure = baseline,Oracle =
> reference bound;`C_rehydrate` = 参数(默认 0.72,扫 0.25–8);
> **C_resident = 0 未建模(P0 prerequisite);SKIP 未建模**——全部
> 数字限定在 boundary-cost 视角。

## 模型

32 节点(大小 1–10 页,合计 159),trace 2000 步,四种 locality
(short/medium/long/very-long = 热集概率/热集大小参数化),预算 =
总量的 20%–100%。四策略:always(永不外化,violation 逐 step 记)/
pressure(≥90% 预算主动外化)/ lru(被动)/ oracle(Belady 式
next-use 预知)。

## 核心结果

**1. 决策空间在全部 24 个 (budget × locality) 组合可观测**:
lru/oracle 成本比 = **1.35–3.05**,无一组合低于 1.10。通用 recency
基线与"预知未来复用"之间存在普遍差距——**residency decision 不是
无关紧要的**。

**2. 差异随预算升高而扩大**:budget 0.20 时比值 1.35–1.56(低预算
全域 thrash,策略趋同);budget 0.80 时 2.47–3.05。**可观测差异区域
= 中高预算 + 任意 locality**;低预算域是"策略无关区"。

**3. locality 影响形态**:short 域绝对成本低(热集小,驻留即可覆盖)
但高预算下比值最高(3.05);long/very-long 域绝对成本最高(全域
复用稀疏)。→ policy 的收益结构依赖 workload,回表 H-P0/H-P1。

**4. C_rehydrate sweep(budget 0.40/medium)**:各策略成本随
C_rehydrate 线性放大(0.25 → 8),oracle 绝对成本始终最低;
sweep 未出现策略排序翻转——**排序稳健,但比值随 C_rehydrate 放大**
即边界成本越贵,聪明的外化越有价值。

## H-P0 / H-P1 初判(描述性,正式判读待 P3)

- v0 已证:**仅 recency(LRU)与完美预知之间存在普遍、可测的差距**
  ——即"未来复用信息"含 decision-relevant 信号,直接杀掉"任何策略
  都一样"的最强无差异假设。
- **但尚未证明**:一个可实现策略能捕获该差距(oracle 用了未来信息);
  也未证明 execution structure(树依赖)在通用信号之外有增量贡献
  (v0 尚无结构化 workload)。H-P1 的正式检验属 P3(new policy 登场
  + 树依赖 workload)。

## v1 失败如实记录(oracle 实现 bug,影响判读方向而非方向性)

首跑 oracle 用**静态"全局最后出现位置"映射**冒充逐步 next-use,导致
oracle 成本普遍**高于** LRU(lru/oracle = 0.07–0.96,物理上不成立
——预知未来的上界不该输给通用基线)。修正 = 标准 Belady 模拟
(逐位置 next-use + 逐节点状态维护);顺带修正 `hash(locality)` 跨
进程不稳定种子 → 稳定序号种子。修正后 oracle 全域 ≤ 诸基线,结论
才可信。**教训:reference bound 的实现 bug 会伪装成"策略无差异"
或"基线更好"——上界必须先通过健全性检查(≤ 一切 baseline)。**

## 诚实性注记

1. C_resident = 0 未建模(P0 prerequisite)——全部结论是
   boundary-cost 视角,不含驻留持有成本;
2. SKIP 未建模(访问外部节点 = 强制 rehydrate);
3. 合成 workload、单 seed、单节点规模;regret 描述性;
4. 无 GPU / 无 SimiGo runtime;live(P4)仅在 P3 显示可实现策略
   差异 > 噪声后。

## 决策

1. **v0 数字入档 → 待审核终判**;
2. **P0 prerequisite 排期**:resident memory cost 计价(否则 policy
   不等式永远缺左边);
3. **P3 方向草案**:new policy = 未来复用概率 × state size 的启发式
   (不含树依赖)先对 LRU;若赢再验树依赖增量(H-P1 强形式);
4. Track E 正式命名待真源定夺。
