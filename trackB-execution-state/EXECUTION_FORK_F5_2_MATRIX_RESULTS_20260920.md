# Execution Fork F5-2 结果:Performance-tax Break-even 矩阵(2026-09-20)

**性质**:2.0 Track B 表示形态迁移第二步(承外部审核定序与 F5-1)。
**代码**:`Tests/MLXLMTests/ExecutionStateForkF5Matrix.swift`(1 测试
通过,2,363s;方法继承 F4-E/F5-1:warm-up 后测、交替、锁步、3 reps)。
**验收规则(F5-1 新规,全程生效)**:每格过两道门——①State
Representation Transition(逐元素一致)②Execution Continuation
(迁移后同一 identity 的 continuation 一致 + mInput 同步系统断言)。
**九格门全 ✓。**

## Tier A 正常矩阵(全过)

| 配置(actual) | pre税 | merge | post税 | **perf-tax BE 稳态** | BE 含首token |
|---|---|---|---|---|---|
| 18K@S2 (18,432) | 1.068× | 16ms | 0.999× | 5.3 tok | 23.7 tok |
| 18K@S4 (18,432) | 1.219× | 44ms | 0.975× | 4.2 tok | 11.1 tok |
| 18K@S8 (16,384) | 0.992× | 24ms | 1.015× | inf(无可避免税) | inf |
| 32K@S2 (32,768) | 1.250× | 35ms | 0.978× | 2.5 tok | 8.0 tok |
| 32K@S4 (32,768) | 1.045× | 39ms | 0.953× | 13.9 tok | 40.9 tok |
| 32K@S8 (32,768) | 1.130× | 43ms | 0.958× | 5.4 tok | 14.9 tok |
| 64K@S2 (65,536) | **1.785×** | 75ms | 1.042× | **1.6 tok** | 4.8 tok |
| 64K@S4 (65,536) | 1.429× | 65ms | 1.125× | 2.7 tok | 7.2 tok |
| 64K@S8 (65,536) | 1.600× | 105ms | 1.003× | 3.1 tok | 7.6 tok |

- perf-tax BE 定义(审核命名):reattach 一次性成本 ÷ **可避免的
  多段表示额外税**(非总 token latency);含首 token 口径单列。
- merge 成本 ∝ 深度(16→105ms),随段数略升。

## Tier B(128K 极限档):按纪律记 N/A

峰值估算(权重 20.1GiB + P 全深 KV + 叶私有 + 合并瞬时):
S4 = 27.0GiB、S8 = 27.3GiB,**超 25.5GiB 安全线与 24GiB MLX 限额**。
**未抬限额硬挤,两格记 N/A**(换更大内存机器后补测;峰值估算公式
与决策规则已固化在代码里)。

## 三个问题的回答(审核 A/B/C)

- **A 深度阈值**:64K 行收益显著且确定(税 1.43–1.79×,BE 1.6–3.1
  token);32K 中等且方差大;≤18K 边际(16K@S8 无税)。一阶结论:
  **深度是税的主导变量**。
- **B 段数阈值**:同深度内段数效应**弱于**深度效应且非单调
  (S2 常比 S4 更差——与 F4-E 段数轴观察一致);无独立阈值必要。
- **C 组合与最重要的意外发现:pre 税跨 run 方差大**(同配置 ±0.1–0.5:
  18K@S4 本轮 1.219 vs F4-E 1.089;32K@S4 1.045 vs 1.137;64K@S4
  post 税本轮 1.125 vs F5-1 的 1.006)。**⇒ 静态阈值表不可靠,
  F5-3 策略必须用在线估计**:
  `E[remaining_tokens] × tax_online > reattach_cost → reattach`,
  其中 tax_online = 滑动窗口实测(COW 侧 ms/token 对近期 fresh 参考
  或对预算模型的偏差),而非查表。

## 决策

1. **F5-2 通过**:reattach 在 18–64K × 2–8 段全矩阵把税收敛到
   0.95–1.13×(8/9 格 ≤1.05),perf-tax BE 稳态中位 ~4 token,
   两道验收门九格全绿。
2. **F5-3(下一步)**:自动 transition policy 原型——确定性成本模型
   + **在线税估计**(本矩阵的直接推论);验收 = 策略驱动的 reattach
   在模拟负载(随机分支长度)下,总延迟优于 always-COW 与
   always-reattach 两个极端。
3. 其后按审核预排:**Track B 阶段收束**(完整表示迁移模型 → 架构
   2.0 设计输入)。#629 补给等收束文档;exp06 M1 维持后置。
4. 边界重申:全部代码仅在 `exp/execution-state-fork`;Tier B 的 N/A
   是纪律执行结果,不是数据缺失。
