# Track E(命名待定)P4 Live Verifier 外部审计记录(2026-09-21)

**对象**:`516ebaf`(`p4_live_policy_verifier.py`,195 行,已推远端)。
**审计结论(外部审核,本仓核验确认)**:**P4-A——模拟层
capacity/miss/eviction invariant probe,有效但弱;P4 live policy
verifier 尚未成立。**

## 四项发现(经本仓逐行核验,全部成立)

1. **DP_opt 为装饰性**:`opt = dp_optimal(...)`(L172)计算并打印,
   但 PASS 判定(`inviolate`)只依赖 `miss_without_evict`——删除整段
   DP,PASS 逻辑不受影响。DP 与 verifier 无因果关系。
2. **`next_use_at` 为伪 Belady**:L113–119 预计算 next-use,但
   L133 实际驱逐 `victim = min(candidates)` = **最低 ID**,与
   next-use 无关。比没写更危险:code review 易误判"已实现 Belady"。
3. **`n != current` 为空转条件**:`evict_one` 仅在
   `node not in resident` 分支内被调用,current 本就不在 resident,
   条件恒真,未测试任何东西。
4. **`miss_without_evict == 0` 近乎重言式**:等大小 + used ≥ budget
   ≥ 1 + current 不占位 ⇒ resident 中必可找到 victim ⇒ 恒 0。
   hot8/tree8 PASS 不构成强验证。

另:结尾 "DP/Belady/**LRU** 结论成立" 中 **LRU 不在脚本内**——
结论超出程序可支持证据,定性为过度声明。

## 审计定位(冻结)

```
516ebaf = P4-A:模拟层 capacity/miss/eviction invariant probe
          —— 有效但弱(miss↔eviction 一对一映射是合法弱不变量,
             但在本模型下近乎重言式)
516ebaf ≠ P4:live policy verifier(尚未成立)
```

## 审计纪律(本轮正式入档,持续有效)

```
Simulation ≠ Source Experiment
Simulation PASS ≠ Source PASS
Invariant Probe PASS ≠ Policy Equivalence PASS
最终裁决 = mlx-swift-lm true-source Swift test;Python 仅为
模型级证据,不得冒充真实 MLX/Swift residency 实验。
```

## 下一轮忠实性清单(审核定立,重写规格 = 本清单)

不得只审"代码有没有 Belady";须审**是否忠实复现 P3R2 数学模型,
并建立 DP → offline policy → live policy 的可验证对应**:

1. next-use 定义正确性;2. tie-break 与 v2 一致(最低 id);
3. prebuilt 语义一致;4. miss/rehydrate 边界一致;5. first-touch
成本口径;6. eviction 与 externalization 同步;7. live cost 与
DP cost 同口径。

## 重写响应(v2,同 commit;待外部复审)

按清单重写为三层验证器,断言对象 = **手算常量 + 跨层等价**,
非自declare PASS:

- 微例(trace [0,1,2,0],budget 2,prebuilt,C 0.69/0.72)手算:
  成本 = 4×0.72 + 1×0.69 = **2.85**;miss = 3;驱逐 = 1 次
  (victim=1)——四层(DP/offline Belady/live Belady/LRU)全部
  对 2.85 断言,驱逐序列确定性断言;
- 缩减实例(hot8/tree8,seed=42):断言 cost_DP ==
  cost_offlineBelady(cost_live == cost_offline,驱逐序列
  offline == live 逐对相等);
- 不变量:每步后 len(resident) ≤ budget(容量);当前节点从不
  出现在驱逐日志(working-set——如实标注:等大小模型下近乎重言,
  variable-size 时须升格);miss↔eviction 一对一(P4-A 弱不变量,
  保留但标注弱)。

**声明范围(收窄)**:本验证器证明 = 缩减实例上 DP/offline/live
三层成本与序列等价 + 手算微例精确吻合(模型级证据)。**不证明**:
P4 live policy verifier 成立;真实 MLX/Swift residency 行为;任何
跨设备/跨模型泛化。P4 proper 仍 LOCKED,最终裁决 = true-source
Swift test。**待外部复审。**

## v3 重写结果(2026-09-21 运行;T2 独立性修复版,待外部复审)

**修复(审计核心缺陷)**:`live` 参数删除,改为**两套互不共享函数
的独立实现**——`offline_belady_batch`(批处理:驱逐时向未来线性扫描
求 next-use,无逐点表)+ `LiveBeladyStream`(流式类:预计算
per-position 表,step() 逐推进);规格共享 = 形式化 SEM-1..5(含
SEM-1 修正:初始 resident=∅、**全体节点初始 ∈ externalized**,
消除"prebuilt 但 resident=∅"歧义;externalized 升格为模型状态,
不变式 resident∪externalized=全体且互斥,property test 逐迹断言)。

| 验证 | 实例 | 结果 |
|---|---|---|
| T3-M1 基础([0,1,2,0]/budget2) | 微例 | 三层 = 2.85,ev=[(2,1)] ✓ |
| T3-M2 tie-break([0,1,2,3]/budget2) | 微例 | 三层 = 4.26,ev=[(2,0),(3,1)] ✓ |
| T3-M3 budget=1 thrash([0,1,0,1]) | 微例 | 三层 = 4.95,ev=[(1,0),(2,1),(3,0)] ✓ |
| T1 cost_DP == offline_batch | hot8 / tree8 | 33.18 ✓ / 74.07 ✓ |
| T2 stream == batch + 驱逐序列逐对相等 | hot8 / tree8 | 22 对 ✓ / 51 对 ✓ |
| Property test(150 随机小迹) | n∈{4,6,8},budget 1–3,len 0–40 | **150/150:DP==batch==stream 且 SEM 不变式成立** |

**事件累积:T3 机制三抓作者错误(跨三个不同子案例)**——
① M1:手算把 step3 命中误计为 miss(4×0.72,正确 3×0.72+0.69=2.85);
② M2:tie-break 期望错(step2 时 0/1 的 next_use 同为 ∞,SEM-4 应逐
最低 id=0,作者误写 1);
③ M3:驱逐序列违反 SEM-3(step1 时 current=1 不可驱逐,唯一候选=0,
作者误写 victim=1)。
三次全部由断言拦截、未产生虚假 PASS;独立重推后修正。**断言机制
连作者也拦,三连实证。**

**独立性的诚实边界**:两实现由同一作者依同一 SEM 规格编写——"实现
独立"指代码路径/数据结构无共享,不指认知独立;交叉验证的证明力 =
规格忠实性的回归保障,非规格本身的正确性证明(规格正确性由 SEM
形式化 + 外部审计把守)。

## v2 重写结果(2026-09-21 运行,待外部复审)

| 验证 | 实例 | 结果 |
|---|---|---|
| T3 手算微例([0,1,2,0]/budget2) | 微例 | DP=offline=live=2.85,misses=3,ev=[(2,1)] ✓ |
| T1 cost_DP == cost_offline | hot8 / tree8 | 33.18==33.18 ✓ / 74.07==74.07 ✓ |
| T2 cost_live==offline 且驱逐序列逐对相等 | hot8 / tree8 | 22 对 ✓ / 51 对 ✓ |
| LRU live 对照(cost-only) | hot8 / tree8 | 45.87 / 113.55 |
| 不变量:working-set / miss@cap↔evict 一对一(弱) | 全部 | True / True |

**事件一:T3 抓住作者手算错误。** T3 首跑 FAIL——作者曾把手算
常量误写为 4×0.72(把 step3 的命中错算为 miss);三层(DP/offline/
live)独立一致给出 2.85,断言拦截并阻止 PASS。独立重推确认 2.85
(3 miss + 1 evict),常量修正后 PASS。**这正是"不可偷换的程序
断言"机制起作用的直接证据——断言连它的作者也拦。**

**披露:绝对值口径差异。** verifier 采用 prebuilt 语义,其 DP
绝对值(hot8 33.18 / tree8 74.07)与 P3R2 的 DP 数字(41.6 / 75.5,
首触免费语义)**不同属口径差异,非矛盾**;T1/T2 等价断言均在
verifier 内部口径成立。两口径的结论形态一致(Belady=DP)。

**事件二:LRU 对照首跑暴露 authoring 失误一次**:重写过程两次
编辑事故(误删 nodes 行/锚点断言失败),均被语法/断言层拦截后
修正,未产生错误输出。
