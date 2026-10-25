# Track E H-P1 Hot Null v2 校准设计(2026-09-22)
**DRAFT v1.0 待审核;按远端裁定(0cc6587 复核)先注册后执行**

> **状态**:DRAFT v1.0,待审核。PASS 前不写校准代码、不跑 permutation。
> 背景:0cc6587 Tier-1 L1 轮 hot 阴性对照触线(S2 −0.1044/S3 −0.2493),
> 触发有效;泄漏审计 PASS(实现层无未来信息泄漏,已正式入档)。裁定:
> 原 hot sentinel 前提"hot trace 访问与拓扑无关 ⇒ 结构信号 ρ≈0"不成立
> ——"生成域独立 ≠ 事件层 null",属 negative-control estimand 定义不足,
> 需本设计修订;非实验失败、非泄漏。tree raw observations
> VALID/PRESERVED、INTERPRETATION LOCKED;L1 出口 LOCKED;L3 LOCKED。

## 1. 固定量(permutation 下不变)

- workload trace = seed 42 原始 hot trace(逐位不变);
- event set = 原 hot workload 自身 LRU ∪ C 去重 (node,t) 集合
  (n=1061,来源 lru 681/C 377/双源 3;逐位不变);
- oracle Y(n,t) = 原 Y(逐位不变);
- 事件时间坐标与事件权重 = 固定(每事件恰好一个观测)。

## 2. 随机量(唯一随机化对象)

**node identity ↔ frozen topology 的标号对应关系**:对 32 个 node
identity 做随机置换;固定拓扑结构(8×4 链/祖先/链成员关系)不变,
仅改变"哪个 node 身份占据哪个拓扑位置"。每次置换后按 §2 定义重算
全部事件的 S1/S2/S3。

## 3. permutation scheme(预注册锁定)

- N_perm = 10,000;
- permutation RNG = Python `random.Random(20260922)`(预注册种子),
  置换算法 = `rng.sample(labels, 32)`(Fisher-Yates);
- 每次置换 c 类:对全部 hot 事件重算 S_c^perm,与固定 Y 做 Spearman
  (平均秩,与 0cc6587 实现一致)→ |ρ_perm,c| 入该类零分布;
- **零分布按类独立**:S1/S2/S3 各自校准,不共用任何常数界。

## 4. Q95 与判定规则(预注册锁定)

- Q95_c = 该类 |ρ_perm,c| 升序排序后的**次序统计量**
  `sorted[ceil(0.95 × N_used) − 1]`(无插值;N_used = 有效抽样数);
- ρ 无定义(秩零方差)的抽样:该次作废、不入零分布,N_used 如实
  记录;若作废超过 1% 在报告中显著披露(预期不发生);
- **hot calibration sentinel(逐类)**:observed |ρ_hot,c| > Q95_c
  → 该类对照异常,全局停机;否则该类通过 calibration sentinel;
- 三类全部通过 = hot 校准通过;任一异常 = 停机,交审核方;
- 观测值 ρ_hot,c = 0cc6587 已采原始读数(S1 +0.0837/S2 −0.1044/
  S3 −0.2493),本轮不重采、不因校准改动。

## 5. 双源 (n,t) 定义修正(远端裁定落档)

信号语义 = **该 workload 统一的 [0,t] 在线历史**(trace 前缀),与
事件来源 policy 无关;窗口计数只依赖 trace 访问序列,故同一 (n,t)
双源事件的两套信号理论上恒等。修正:L1 runner 断言双源事件
S(lru) ≡ S(C) 逐位相等(等价性回归);`lru 先序` 降级为实现层
确定性 fallback(provenance=lru+C 如实记录),不构成信号语义。

## 6. 校准通过后的执行顺序

1. hot sentinel 三类全部通过 → Tier-1 L1 重新进入;
2. 为审计完整性:**完整重跑 Tier-1 runner**(同 revision/同 runner/
   同 provenance),runner 内置回归断言:tree ρ 必须逐位等于
   0cc6587 保存的 raw 值(S1 −0.5218/S2 −0.4767/S3 −0.3418),
   不一致即停机;
3. tree raw 解禁进入逐类 L1 出口归因(§7 逐类署名 + 精度级);
4. L1 PASS ∧ L2 PASS 的类别才进 §4 L3(主方向+敏感方向同跑同报);
5. L3 判读前不产生任何正式研究结论。

## 7. 边界

- 本修订只改 hot 对照 estimand 与双源信号语义表述;信号分类学、
  O1、v6 引擎、P3 冻结全部零改动;
- 本设计 PASS 前不写任何校准代码(先注册后执行,禁 post-hoc);
- 校准 Q95 仅为对照哨兵,不伪装统计检验,不用于 tree 侧任何判定。
