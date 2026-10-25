# Execution Fork F5-3 Step 2/3 结果:真机四策略 + 估计器验证(2026-09-21)

**性质**:2.0 Track B 表示迁移第三步的真机闭环(承审核收紧验收:
Step 2 policy 与 Step 3 estimator 分开出指标;Decision Regret 为主
指标;oracle 用实测下界)。**代码**:
`Tests/MLXLMTests/ExecutionStateForkF5Live.swift`(1 测试通过,841s;
64K@S4,12 试次 = 4 bucket × 3;C_fresh 由 P 侧一次标定,无 twin 依赖;
同 continuation 三路重放)。

## Step 2:真机四策略——**通过**

oracle = min(COW 实测, Reattach 实测)(两纯策略的实测下界,免假设)。

| bucket | COW | always-R | **adaptive** | oracle | 平均 regret | AD 迁移(oracle 择迁) |
|---|---|---|---|---|---|---|
| short(2–8) | 616 | 281 | **260** | 255 | +1.7% | 0/3(1) |
| mid(16–32) | 1,941 | 1,608 | 1,724 | 1,608 | +7.5% | 3/3(3) |
| long(64–128) | 11,007 | 9,122 | 9,329 | 9,122 | +2.3% | 3/3(3) |
| xlong(256–512) | 38,396 | 31,477 | **31,541** | 31,477 | **+0.1%** | 3/3(3) |
| **总** | **12,990** | **10,622** | **10,714** | **10,616** | **+0.9%** | — |

- **AD vs COW −17.5%,vs always-R +0.9%,regret +0.9%**;
- **xlong #3 出现 regret −1.0%(AD 优于两纯策略)**:oracle=min(A,R)
  是纯策略下界而非 AD 下界——中途切换(前 5 步 COW + 早期迁移)
  可以同时赢过两个极端,这是 adaptive 价值的直接证明;
- 行为正确:短分支不迁(0/3)、中长分支 4–5 步即决策;
- **token 门 36/36(12 试次 × 3 路重放全一致)**——execution identity
  跨三种表示(COW/merged/中途切换)保持 continuation 不变;
- 遥测完整入 log(决策步 / τ̂ vs τ / E[rem] vs rem / merge 实测
  71–84ms / 各路总延迟)。
- **表述纪律:12 试次、单配置(64K@S4)、单机(M5 Air);regret 数字
  限此范围,普适性由 closure 实验与跨配置复测回答。**

## Step 3:估计器 k 扫描——**k=4 被推翻,默认改 k=8**

后验分析(用 COW 路前 k 步实测延迟;不额外跑):

| observe_k | \|τ̂−τ\|/τ 平均 | 事后决策与 oracle 择优一致 |
|---|---|---|
| k=2 | 51.7% | 3/12 |
| k=4 | 22.0% | 4/12 |
| **k=8** | **8.1%** | **9/12** |

- τ̂ 系统性高估(+0.06–0.09)来源 = 首步视图物化 cache-miss;
  k=8 稀释首步异常后误差降至 8.1%,决策一致率 75%;
- **observe_k 默认值 4 → 8**(审核"不让 k 变神奇常数"的直接产出:
  用数据选默认,而非拍定);
- 观察:k=4 的高估方向偏保守(偏早迁),mid regret 7.5% 主要由观察期
  与早迁共同贡献;k=8 预计改善 mid 桶(closure 实验复验)。

## 决策

1. **F5-3 Step 2/3 通过**——simulator 的策略逻辑在真实模型执行中
   成立:运行时能基于在线估计自主做出正确迁移决策,regret +0.9%,
   且存在优于两极端的操作点。
2. 运行时参数定稿:observe_k=8、滑窗 τ̂、E[rem]=min(n, budget)、
   merge 成本口径 2×merge(实测 71–84ms@64K)。
3. **下一步 = Track B closure experiment**(审核预排):全生命周期
   串联(fork → COW → tax 出现 → 在线估计 → adaptive 决策 →
   reattach → continuous → 同 identity 同 continuation),一次实验
   证明完整命题;过则 Track B 核心架构命题闭环,再开 Track C
   (Model-State Residency,同构:表示税↔传输税、reattach↔prefetch、
   discard↔evict、adaptive representation↔adaptive residency)。
4. 边界重申:全部代码仅在 `exp/execution-state-fork`。
