# Track E(命名待定)Residency P3 后续轮结果(2026-09-21)

> **终审判定(2026-09-21):P3 后续轮 simulator v2——CONDITIONAL PASS。**
> 审核方核对 `a4d0d2a`(commit/v2 simulator/结果文档)。理由不是算法
> 错误,而是两个核心问题已获有效证据、但证据边界必须收紧。
>
> **正式状态表(审核冻结)**:v2 code integrity PASS / NORMS① 事件
> 时序 PASS / NORMS② tie-break PASS / NORMS③ working-set PASS /
> DP-simulator 语义对齐 PASS / DP 缩减模型精确性 PASS / **Belady vs
> DP = 0.0%,PASS within tested boundary** / **Cost-aware reference =
> CONDITIONAL CLOSED(当前模型/缩减实例边界内)** / tree_lru 实现
> PASS / tree_lru vs LRU = **NEGATIVE RESULT** / **naive structure
> signal = FALSIFIED** / H-P1 overall = **OPEN / NOT VERIFIED** /
> C_resident PENDING / single-seed OPEN / parameter sensitivity OPEN /
> P4 live **LOCKED / NOT YET**。
>
> **0.0% 的模型级解释(审核给出,比"两实例碰巧重合"更强)**:在
> equal-size / fixed capacity / 非驻留访问必产生 rehydrate / 超容量
> 必驱逐 / 当前节点不可驱逐 / C_ext=0.69:C_rehy=0.72 的模型下,容量
> 满后**每一次非驻留访问都对应一次驱逐**——#ext 与超容量后 miss 数
> 直接对应,#rehy 另含初始建入;total boundary cost 与未来 miss 数
> 紧相关,故 Belady(future-aware)与真 cost-aware optimum 一致。
>
> **限定必须保留**:8 nodes / budget 3 / 150 steps / equal-size /
> prebuilt / single C ratio / 两 workload 实例——不得写成"Belady 是
> 一般意义上的 cost-aware oracle"。
>
> **残差语义升级(审核确认)**:缩减实例中 **LFU→Belady 的残差同时
> 就是 LFU→exact cost-aware optimum 的实测残差**——"接近真实
> headroom"必须加 "**within the tested reduced-model boundary**",
> 不外推到 32 节点大网格。
>
> **H-P1 判读(审核确认)**:阴性结果正式记录 = **naive
> tree-neighbor retention: FALSIFIED / NEGATIVE**;被杀的是该 policy
> family 的第一种具体实现,不是 H-P1 本身。H-P1 树:naive
> tree-neighbor retention ✗ / subtree-level OPEN / dependency-aware
> OPEN / parent-child predictive OPEN / possibly no useful structure
> OPEN。
>
> **措辞纪律(审核收紧⑤)**:"lru→Belady reference 差距仍为 65.4%"
> 保留;后半句改为"**尚不能判断该差距是否能够通过可实现的
> structure-aware policy 捕获**"——三种可能全部开放:A 存在可实现
> structure-aware policy / B 存在信息但无法转化为在线收益 / C 差距
> 主要需要 future knowledge 而非 structure。P3 不提前选 A。
>
> **源码清理(两处非实验性,已落)**:①v2 遗留 stale print
> ("fault 数最优 ≠ total boundary cost 最优")与本轮结果矛盾,改为
> "Belady 与 DP 差距 = 当前缩减实例下的 cost-aware regret;本轮两
> 实例均为 0.0%";②RNG 消耗注记(parent.get fallback 每迭代消耗
> 随机数)以注释形式入档,**不改行为**(改则漂移 seed=42 随机流)。
> 均不重跑。

> **首跑记录(史料)**:v2 数字为容量侧事实;DP 完整性论证、DP/贪心
> 语义对齐披露见下文。 代码:`residency_policy_simulator_v2.py`
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

**发现(审核升级表述)**:等大小模型下,future-aware
Belady-greedy 与精确离线最优完全重合(0.0%,两实例)。**在当前
等大小、全预建、固定容量及给定成本比的缩减实例中,LFU→Belady 的
残差同时也是 LFU→exact cost-aware optimum 的实测残差**——首跑的
"残差 32–69%"升级为缩减模型边界内的实测 headroom
(**within the tested reduced-model boundary**,不外推到 32 节点
大网格)。**限定必须保留**:两缩减实例 / 单一 C_ext:C_rehy 比 /
非证明;cost-aware oracle 的普适性仍列 P0/P3 后续。

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
3. **H-P1 状态更新**:naive tree-neighbor retention 正式记录为
   FALSIFIED;H-P1 保持未验证——三种可能全部开放:A 存在可实现
   structure-aware policy / B 存在信息但无法转化为在线收益 /
   C 差距主要需要 future knowledge 而非 structure;P3 不提前选 A。
   "lru→Belady reference 差距仍为 65.4%"= 可观测差距存在,尚不能
   判断能否经可实现 structure-aware policy 捕获;
4. Track E 命名继续待定。
