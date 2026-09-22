# Track E nodes-out 正式实验设计 DRAFT v0.3(2026-09-22)
**DRAFT 待复审;PASS 前零实现零采数(Implementation / Data LOCKED)**

> 基线:开题 c3fe842(PASS / SEALED AS OPENING BASELINE)+ Definition
> Lock e5bca86。本设计 = 远端核定的下一阶段三预注册:**granularity
> 候选集 + correctness protocol + cost-channel numerical definitions**。
> 核心原则(远端核定):先定义"比较什么、什么叫正确、怎么算成本",
> 最后才允许碰代码。

## 1. 比较什么:granularity 候选集(预注册)

| 角色 | 模型 | 说明 |
|---|---|---|
| 基线(参照) | node-granularity residency | v6 引擎既有节点外化通道(冻结参照行为,零改动) |
| **Candidate A(唯一预注册主候选)** | **KV resident/externalized 二态** | 取消节点粒度选择;全部 KV 状态在同一粒度域管理;远端已批 candidate comparison model |
| Candidate B/C | 不预注册 | block-level 等其他粒度本轮不进;如需增补走 Design Revision |

实验变量唯一 = residency granularity(node 基线 vs Candidate A);
其余全部固定(§4)。

## 2. 什么叫正确:correctness protocol(预注册;v0.2 操作化补锁)

- **correctness invariant = Track B 五元组**(Identity / Position /
  Next Input / Continuation Semantics)——KV 是被操作对象,五元组是
  不变量,两层严禁混同;
- **判定(三层全部锁定,缺一不可)**:
  1. **event-level correctness(对齐基准已锁)**:两种粒度的
     事件序列不同构,不做事件一一对应;对齐锚点 = **decode step
     边界**——Candidate A 每个外化/迁回事件完成时所在的 decode
     step t,取基线执行在同一 step t 的五元组为对齐基准,逐项
     等价(与 step-level 锚点统一,区别仅在采样时机=事件完成
     时刻);
  2. **step-level continuation correctness**:每一个 decode step
     的 continuation 语义(next input 与后续 KV 演化)与基线执行
     逐项等价;
  3. **terminal-state equivalence**:完整 operation sequence 结束
     时,终态五元组与基线执行逐项等价。
  三层比较对象均为基线执行(未移除 node 外化通道);任何一层
  不等价即该组 correctness violation;
- **断言实现**:正式实验 runner 内置逐操作五元组断言(继承 v6
  L2 运行时审计模式:窗口时间界 + 无 oracle 入路径);
- **violation 处理**:组内 violation = 实验结果如实入档(不是门
  失败);基线自身出现 violation = 实现错误,停机查实现。

## 3. 怎么算成本:cost-channel numerical definitions(预注册)

| 通道 | 定义 | 数值口径 |
|---|---|---|
| 兼容披露(非主判据) | J = C_ext×#ext + C_rehy×#rehy | 与 H-P1/P3 可比,仅披露 |
| 新通道 1:migration / re-encoding cost | 粒度变体下每次 state 转换的建模成本 | **方案 A 锁定**:报告 migration/re-encoding event count + bytes moved/read + timing;v1 modeling assumption = identity mapping, 0 modeled conversion cost;**不建立 token-equivalent cost,不做 ±敏感性**;token-equivalent measurement deferred to later measurement round |
| 新通道 2:correctness violation / correction cost | violation 计数如实报告;**v1 correction cost 不货币化**(只报计数与位置) | 与 P0.1 Deferred 一致 |
| 新通道 3:granularity→byte accounting | 78,246 KiB/node 适用性重验证 = **实验输出之一** | 可映射 → 给出 node-equivalent 映射表;不可映射 → 报告"不可映射"并停用该换算;禁止预判 |

**报告纪律(锁定)**:**新通道 1/2/3 全部报告**,不并入任何
既有 J,不相互合并;每通道给出 n(事件数)/读数/口径三要素。

主判据说明:nodes-out 是机制问题非优化问题——本设计**不设性能
PASS/FAIL**;全部结果 = 机制知识如实入档。

## 4. 固定量与变量

- 固定:seed 42 双 trace(hot/tree 逐位同 0cc6587)/ B=12 / H=8 /
  W=200 / generator / C_ext=0.69 / C_rehy=0.72 / 全部 P3 冻结参照;
- 变量:residency granularity(node 基线 vs Candidate A);
- 判读域:tree Tier-1 主域 + hot 披露域;
- 每组运行:确定性重跑逐位一致 + L2 运行时审计(窗口时间界)+
  无 oracle 入路径(继承 v6 模式)。

## 5. Exit criteria(预注册)

- **E1(correctness)**:Candidate A 全部 migration 序列五元组逐项
  等价成立 → correctness PASS;任一 violation → 该组标
  "correctness violation" 如实入档(不删除、不停机,除非基线自身
  violation);
- **E2(成本机制知识)**:correctness PASS 下,兼容披露通道 J 与
  基线差异 + **新通道 1/2/3** 读数全部如实报告——**无性能 PASS/FAIL**,
  结果 = 边界成本机制知识;
- **E3(计账单位)**:78,246 KiB/node 适用性判定(可映射/不可映射)
  如实入档;
- 全部出口 = 机制知识入档,交审核方署名;不预设优劣结论。

## 6. 门位

本设计远端 PASS → Experiment runner 实现 UNLOCKED → v6 回归门重跑
(P3-A/B/C 冻结参照逐位)→ 采数 → 机制知识入档 → 审核署名。
当前:**Implementation / Data Collection LOCKED**。
