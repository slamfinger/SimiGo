# Track E(命名待定)Residency P3 结果(2026-09-21)

> **状态:P3 前置探针 + simulator v1 首跑完成,待审核方终判。**
> 代码:`ResidencyP3DepthFootprint.swift` + `residency_policy_simulator_v1.py`
> (exp 分支 / lab 仓)。定位:P0.1 PASS(v0.1 Policy Objective
> Definition)解锁;两条实现规范注记已实现(事件计数时序 + tie-break
> 最低 id)。P3 结论以实验为准,不预设 H-P0/H-P1。

## 前置探针:resident footprint depth sweep(P0 审计④闭合)

对 P@depth(4K/16K/64K)驻留链 nbytes 精计:

| depth | attention 分配 | GDN 槽 | GDN 占比 | attention 占比 |
|---|---|---|---|---|
| 4096 | 81,920 KiB | 62,880 KiB | 43.4% | 56.6% |
| 16384 | 327,680 KiB | 62,880 KiB | 16.1% | 83.9% |
| 65536 | 1,310,720 KiB | 62,880 KiB | 4.6% | 95.4% |

- attention 分配**精确线性**(depth × 20 KiB;本组深度 256 对齐故
  padding 0%);GDN 三深度一致(61.4 MiB 固定)——**P0 审计④的结构
  推断升级为本配置实测**;
- **交叉点 ≈ 3,100 行**:浅节点 GDN 底价主导,深节点 attention 主导
  ——state-size 信号有了可操作的形态(深度 ↔ 成本结构)。

## simulator v1(字典序 objective;NORMS 已实现)

事件时序(touch → REHYDRATE → 容量检查 → 逐个 EXTERNALIZE,同步
多事件逐一计数)+ tie-break 最低 id(P0.1 终判两条注记闭合)。
等大小 32 节点,trace 2000,seed 42;双 workload:hot(热集,H-P0 域)
/ tree(8 树×4 节点,0.7 概率沿树边行走,H-P1 setup);策略:lru
(baseline)/ **lfu_aging(NEW,可实现:计数 + 每 200 步减半 aging)**/
oracle(Belady reference);C_ext=0.69,C_rehy=0.72。

### H-P0 域(hot):可实现 reuse 信号 vs 纯 recency

lfu_aging 相对 lru:**中压力大幅优(0.40 预算 −45.1%),低压力翻转
(0.80 预算 +7.1%)**。

### H-P1 setup(tree):LFU 优势全域稳定

lfu_aging 相对 lru:**−13.7% ~ −25.2%,全部预算域一致**;且 lfu→
oracle 残差 **32–69%** 未被频率信号捕获。

## H-P0 / H-P1 初判(描述性;正式判读仍以 P3 全部实验为准)

1. **H-P0 获得首个可实现策略证据(部分域)**:仅用 recency 不是
   上限——频率信号在 hot 域中高预算区显著优于 LRU;但低压力区
   (0.80)LFU 反而更差:**reuse 信号的收益是预算依赖的,不是无条件的**
   ——这本身就是"residency decision 依赖 workload 结构"的第一个
   判读性证据。
2. **H-P1 候选空间已量化(未检验)**:lfu→oracle 残差 32–69%,且
   tree 域 LFU 优势全域稳定而 hot 域翻转——两域行为形态不同,提示
   结构信息(父子相关访问)有频率之外的增量。**正式 H-P1 检验需要
   structure-aware policy**(下一轮),本 v1 只建立空间。
3. 前置 sweep 给 policy 的输入:state-size 信号 = 深度代理(浅=
   GDN 底价 43% 主导,深=attention 95% 主导),同一节点在不同深度
   的驻留成本结构不同。

## 诚实性注记

1. 合成 workload、单 seed;LFU-aging 参数(decay=200)未调优——
   新 policy 形态本身是 P3 的探索对象,非调优目标;+7.1% 翻转不构成
   "LFU 不适用"结论(参数与域依赖如实标注);
2. C_resident 未入模(P0 capacity 视角,字典序第一层 = 硬约束);
3. SKIP 未建模;单机内存语义;不反推 Track B / M 链 / simulator v0;
4. H-P0/H-P1 判读为描述性, regret 不是胜负分。

## 决策

1. **P3 首跑数字入档 → 待审核方终判**;
2. P3 后续候选(待审核定夺):structure-aware policy(树依赖信号,
   H-P1 正式检验)→ depth-aware signal(前置 sweep 的 GDN/attention
   占比)→ nodes-out 计价评估;
3. Track E 命名继续待 P3 证据。
