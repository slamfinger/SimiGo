# Execution Fork F5-1 结果:Reattach 最小原型(2026-09-20 深夜)

**性质**:2.0 Track B 受约束工程化验证——**表示形态迁移
(Representation Transition)第一步**(承外部审核定序:F5-1 → F5-2 →
F5-3 → 阶段收束;#629/Instruments/exp06 全部后置于 F5)。
**代码**:`Tests/MLXLMTests/ExecutionStateForkF5Reattach.swift`(1 测试
通过,488s;reattach = state 赋值惰性视图 + eval 物化,单次 O(depth)
拷贝;GDN 层不动)。

## F5-1 三项验收:**全部通过**

设置:64K @4 段(同 F4-E 方法:warm-up 后测、P/被测侧交替、深度锁步;
P = 解冻续写补至全深的 fresh 1 段对照)。

| 验收项 | 要求 | 实测 | 判定 |
|---|---|---|---|
| 正确性 | merge 前后逐元素一致 | 首个 attention 层 **逐元素相等 ✓** | ✅ |
| 正确性(续跑) | 合并后逐 token 门 | **48/48 ✓**(对 P 同流对照) | ✅ |
| 性能 | 合并后稳态 ≤1.05× fresh | **1.006×**(1.010/1.002 两 rep) | ✅ |
| 成本 | 完整 merge latency + copy 字节 | **85.2 ms,10 层,逻辑 KV 1.25GiB 单次拷贝** | ✅ 记录在案 |

过程数据:
- 合并前税(同场复测):**1.219×**(与 F4-E 的 1.256× 同量级,复证);
- 合并后首 token 158.6ms(含 capacity==offset 触发的一次 step-256
  增长拼接——KVCacheSimple 常态行为,一次性,不入稳态);
- 合并后 active 22.9GiB(叶 COW 段表引用释放)。

## 实测 break-even(取代设计期假设)

```
reattach 85.2 ms(一次性)
÷ 合并前税 16.7 ms/token(P 76.1 vs 叶 92.8)
= **≈ 5.1 token 回本**
```

设计期假设是 10–15 token;实测 **≈5 token**,优于假设。含首 token
增长拼接的总回本 < 8 token。**表述纪律:此为 64K@4 段单点实测,
深度/段数轴的 break-even 矩阵由 F5-2 给出。**

## 首轮 harness bug(如实记录)

首轮 token 门失败,根因 = 合并侧输入 token 未与叶侧同步(mInput
未初始化为 lInput,首步喂错 token 流即脱同步)——**非 merge 缺陷**
(该轮 element-exact 与稳态 1.048× 已有效)。修复一行后全绿。教训:
多执行流对照实验中,**每个执行流的 next-input 状态是 execution
state 的一部分**,换表示/换对象时必须随迁——这本身就是 F0 说的
"execution identity"问题在实验层的再现。

## 决策

1. **F5-1 通过:表示形态迁移成立**——Shared/Segmented(共享/多段)
   → Continuous(连续)的主动切换把 1.22–1.26× 长深度税消到 1.006×,
   一次性成本 85.2ms@64K,实测 ~5 token 回本。
2. **F5-2(下一步)**:break-even 矩阵(18K/32K/64K/128K × 深度 ×
   段数;COW decode / reattach 时间 / reattach 后 decode / cumulative
   latency / fresh baseline 五列)——注意 128K 需评估本机 32GB 内存
   上限(权重 20 + KV 2.6×2)。
3. **F5-3(其后)**:自动 transition policy(预计 decode 长度 × 当前
   多段税 > reattach 成本 → reattach)。
4. **阶段收束提醒(审核预排)**:F5 全过后暂停扩实验,做 Track B
   阶段成果收束(完整模型:fork/COW/多级/restore/rollback/promotion/
   解冻/discard-reuse/性能税/reattach/transition)→ 架构 2.0 设计
   输入。研究问题的升级:从"能不能做 Branching Execution State"到
   **"执行状态应在 Shared/Segmented/Continuous 三种表示间如何迁移"**。
5. 边界重申:全部代码仅在 `exp/execution-state-fork`。
