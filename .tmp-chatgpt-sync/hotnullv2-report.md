按你的裁定,H-P1 Hot Null v2 Calibration Design 已注册:commit 30a6c16(新设计文档 RESIDENCY_H-P1_HOT_NULL_V2_DESIGN_20260922.md + 你的裁定全文入档,已推送)。先注册后执行,PASS 前零校准代码。裁定三项全部落档:泄漏审计 PASS 入档;hot 触线重分类为对照 estimand 定义不足;双源 lru 先序降级为确定性 fallback。

## 设计锁定的预注册内容

**固定量**:seed 42 原始 hot trace 逐位不变;event set = hot 自身 LRU∪C 去重 (node,t)(n=1061);Y 逐位不变;事件时间坐标与权重固定。

**唯一随机量**:node identity ↔ frozen topology 标号对应关系(32 个 node identity 置换;拓扑结构不变)。

**permutation scheme**:N_perm = 10,000;RNG = Python random.Random(20260922)(预注册种子);置换算法 = rng.sample(labels, 32)(Fisher-Yates);每次置换重算全部事件 S_c^perm,与固定 Y 做 Spearman(平均秩,与 0cc6587 实现一致)。

**Q95 与判定**:Q95_c = 该类 |ρ_perm| 升序次序统计量 sorted[ceil(0.95×N_used)−1](无插值);ρ 无定义(秩零方差)抽样作废、N_used 如实记录,作废超 1% 显著披露;逐类 calibration sentinel:observed |ρ_hot,c| > Q95_c → 对照异常全局停机;否则该类通过;三类独立校准,无共用常数。观测值直接用 0cc6587 原始读数(S1 +0.0837/S2 −0.1044/S3 −0.2493),不重采。

**双源定义修正(§5)**:信号语义 = workload 统一 [0,t] 在线历史(policy 无关);runner 断言双源事件 S(lru) ≡ S(C) 逐位相等;lru 先序降级为实现层确定性 fallback。

**校准通过后的执行顺序(§6)**:hot sentinel 三类全过 → 完整重跑 Tier-1 runner(内置回归断言:tree ρ 必须逐位等于 raw 保存值 S1 −0.5218/S2 −0.4767/S3 −0.3418,不一致即停机)→ tree 解禁逐类出口归因 → 过门类进 L3。

## 请审核

请审 Hot Null v2 设计(30a6c16):①permutation scheme 是否有未声明自由度;②Q95 次序统计量(无插值)+ 严格大于判定是否可接受;③零方差抽样作废规则的边界;④校准通过后重跑 Tier-1 的回归断言设计是否充分。PASS 后我将实现校准脚本并执行 hot calibration。
