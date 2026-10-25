# Execution Fork F5-3 Step 1 结果:Adaptive Policy Simulator(2026-09-21)

**性质**:2.0 Track B 表示形态迁移第三步的**第一步(policy simulator,
审核三步法)**——在纯数据层验证策略逻辑,runtime / 预测误差 / 模型
行为分离(后者属 Step 2/3)。
**代码**:`f5_3_policy_simulator.py`(本仓,python3 stdlib,可复跑:
`python3 f5_3_policy_simulator.py --trials 2000 --seed 42`)。
**成本模型全部来自实测**:C_fresh(D)=49.1ms+0.412μs/token×D(两点
标定:F3-E7 @4.2K 与 F5-1 @64K);τ 按 (F5-2, F4-E) 两轮观测区间
均匀采样(**跨 run 波动直接建模为环境随机性**);merge 用 F5-2 实测;
首 token 惩罚 ≈ merge(F5-1 实测 158.6−76.1≈82ms)。

## 策略与设置

- **四策略**:always-COW / always-reattach(立即迁移,含首 token
  惩罚)/ **adaptive** / **oracle**(hindsight,知完整 continuation,
  实验参考非运行策略);
- **adaptive**:前 4 步观察估 τ̂(噪声 12%/√k);此后**每步滚动重估**,
  E[T_rem] = min(已生成长度 n, budget);决策
  `E[T_rem] × τ̂ × C_fresh > 2×merge ⇒ reattach`;
- 分支长度混合分布(审核要求):short(2–8)/ mid(16–32)/
  long(64–128)/ xlong(256–512)各 25%;9 配置 × 2,000 trials × 3 budget。

## v1→v2 的结构性修正(simulator 的直接产出)

v1 用固定 budget=256 作 E[T_rem]:总体 -21.6% 但 **short 分支系统性
过度迁移**(reattach 75–100% vs oracle 0–57%,regret 最高 +41%)——
正是审核预言的"continuation 假设过长则 adaptive 看起来聪明实则滥迁"。
v2 改滚动估计 E[rem]=n:**short 分支 reattach 率降至 2–6%(贴 oracle),
浅税格 ≤两极端 94–98%**。

## 结果(v2)

**总平均(全配置 × 全 bucket × 全 budget)**:

| 策略 | 平均延迟 | 相对 |
|---|---|---|
| always-COW | 10,812 ms | 基线 |
| always-reattach | 8,375 ms | -22.5% |
| **adaptive** | **8,493 ms** | **-21.4% vs COW;+1.4% vs always** |
| oracle | 8,367 ms | 下界 |

- **regret vs oracle = +1.5%**,且 **budget 不敏感**(64/256/512 全档
  1.014–1.015)——策略对预算假设稳健;
- 行为正确性:**短分支保持 COW**(浅税格 reatt 2–6%)、**长分支主动
  迁移**(long/xlong reatt 73–100%)——"adaptive"名副其实;
- bucket 级:short regret 0.5–29%(64K@S2 的 29% 出现在 τ=1.785 极端
  税下——该格 oracle 自己 86% 迁移,adaptive 57% 追随是正确行为);
  mid 的 4–12% = 滚动观察期的固有代价(约 5–15 步付税后越过阈值),
  绝对量 50–240ms;
- **验收判定(审核标准"不系统性输给两极端")**:**通过**——adaptive
  全局大幅优于 always-COW(-21.4%),微逊 always-reattach(+1.4%,
  代价=观察期,远小于两极端间 29% 的差距),无任何 bucket 同时输给
  两极端。

## 决策

1. **F5-3 Step 1 通过**:策略结构成立,运行时参数已定(observe_k=4、
   τ̂ 噪声界、E[rem]=n 滚动、budget 上界不敏感)。
2. **Step 2/3(下一会话)**:live 四策略真机对照(同 continuation 四
   路重放)+ 在线税估计接入 runtime(标定 C_fresh 线 + 滑窗 τ̂);
   验收沿用本步判定标准。
3. 其后按审核预排:**Track B 阶段收束**(三问:共享 execution state
   能否安全存在 / 性能成本能否消除 / 系统能否自主选择表示——前两问
   已有实验支持,第三问待 Step 2/3 闭环)。
4. 边界:本步为实测参数上的策略模拟,非真机测量;绝对延迟数值是
   模型推算,相对关系(策略排序、regret 结构)才是结论。
