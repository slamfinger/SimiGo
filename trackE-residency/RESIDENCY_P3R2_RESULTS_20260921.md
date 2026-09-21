# Track E(命名待定)Residency P3 后续轮结果(2026-09-21)

> **状态:P3 后续轮(cost-aware reference + structure-aware policy)
> 首跑完成,待审核方终判。** 代码:`residency_policy_simulator_v2.py`
> (lab 仓;seed=42)。定位:P3 首跑 CONDITIONAL PASS 终判定序的两项
> ①②;NORMS①②③ 延续;objective = v0.1 字典序。

## ① Cost-aware reference:DP 精确最优 vs Belady-greedy(核心结果)

缩减实例(8 节点/预算 3/150 步,**全预建语义,DP 与贪心双方一致调
整并披露**)上以子集 DP 求 `C_ext×#ext + C_rehy×#rehy` 的**精确全局
最小**:

| 实例 | DP 精确最优 | belady_greedy | lfu_aging | lru | tree_lru |
|---|---|---|---|---|---|
| hot8 | 41.6 | **41.6(0.0%)** | +3.4% | +47.4% | +77.9% |
| tree8 | 75.5 | **75.5(0.0%)** | +29.9% | +65.4% | +48.6% |

**发现**:等大小模型下,future-aware Belady-greedy 与精确离线最优
**完全重合(0.0% 差距,两实例)**。这为 P3 首跑的"残差 32–69%"
提供了关键升级依据:**在该成本结构与等大小设定下,Belady reference
即实际可达的 cost-aware 下界**——首跑的描述性残差因此可读作接近
真实 headroom。**限定**:两缩减实例 / 单一 C_ext:C_rehy 比
(0.69:0.72)/ 非证明;cost-aware oracle 的普适性仍列 P0/P3 后续。

## ② Structure-aware policy(H-P1 首次正式检验):阴性结果如实入档

tree_lru(可实现:树邻近期活跃度优先保留,其余按 LRU)对 lru:

- tree 域:+13.3% ~ +16.5%(**更差**);
- hot 域(特异性对照):+7.6% ~ +50.2%(更差,且 hot 域更差——信号
  与 workload 无关地有害)。

**H-P1 判读(首个正式检验)**:naive 结构启发式**未通过**——树邻
活跃度保留信号在此形态下反预测(被保留的"活跃邻"节点挤占了按
recency 应淘汰的冷节点)。**这不等于 H-P1 被杀**:它杀掉的是这一
种 structure signal 形态;H-P1 的其他形态(子树整体外化/召回、
parent→child dependency 预取等)待后续。lru→belady 差距(tree8
65.4%)仍在,可捕获空间存在但需要更好的结构利用设计。

## 大网格(32 节点/2000 步,首触免费语义)

lfu_aging vs lru 与 v1 判读一致:hot 域 −12.5%(0.20)/ −45.1%
(0.40)/ **+7.1%(0.80 翻转)**;tree 域全域 −14.7% ~ −20.1%。
belady_greedy 全格最优。另:H-P1 检验节使用独立再生 trace(同种子
流后段),其 lru 基线与大网格数字略有差异——两个独立样本,结论
形态一致,如实披露。

## 诚实性注记

1. **本工具提交即注册**:simulator v2 首个可运行版本在写入后立即
   暴露两处实现错误(evict_one 缺 step 实参、DP/贪心语义不一致),
   均在运行前/运行中修正并如实记录;首跑即本结果,无数字修订。
2. tree_lru 的 tree-neighbor 评分窗口(W=50)与LFU decay(200)为
   首选参数,未调优;参数敏感性属后续。
3. DP 覆盖性:只驱逐必要数量(正 C_ext 下提前/超额驱逐无益且可达,
   故不需主动驱逐转移——DP 完整性论证一行,详见源码注释)。
4. 合成 workload 单 seed;regret 描述性;C_resident 未入模。

## 决策

1. **P3 后续轮数字入档 → 待审核方终判**;
2. **cost-aware reference 问题闭合(缩减实例级)**:Belady reference
   在等大小设定下与精确最优重合——P3 正式策略比较的 reference 合法
   性成立(限定条件如实);
3. **H-P1 状态更新**:首个 structure-aware 形态被杀;structure
   signal 的正确形态为开放问题(H-P1 保持未验证,含"可能不存在
   可实现形态"的诚实可能);
4. Track E 命名继续待定。
