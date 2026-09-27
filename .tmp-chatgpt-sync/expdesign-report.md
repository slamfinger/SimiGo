nodes-out 正式实验设计 DRAFT v0.1 已按你的三预注册要求起草并入库:commit 5c3e82c(RESIDENCY_NODES_OUT_EXPERIMENT_DESIGN_20260922.md,已推送;PASS 前零实现零采数)。

## 三预注册内容

**① 比较什么(granularity 候选集)**:
- 基线(参照)= node-granularity residency(v6 引擎既有节点外化通道,冻结参照行为零改动)
- Candidate A(唯一预注册主候选)= KV resident/externalized 二态(你已批的 candidate comparison model)
- Candidate B/C(block-level 等)本轮不预注册;增补走 Design Revision
- 实验变量唯一 = residency granularity;其余全固定(seed42 双 trace 逐位/B=12/H=8/W=200/generator/C_ext/C_rehy/全部 P3 冻结参照)

**② 什么叫正确(correctness protocol)**:
- correctness invariant = Track B 五元组(Identity/Position/NextInput/Continuation);KV = 被操作对象,两层严禁混同
- 判定 = 每实验组在全部 migration/externalization/rehydration 序列前后,五元组与基线执行逐项等价
- 断言实现 = runner 内置逐操作五元组断言(继承 v6 L2 运行时审计模式)
- violation 处理 = 组内 violation 如实入档(非门失败);基线自身 violation = 实现错误停机

**③ 怎么算成本(cost-channel numerical definitions)**:
- J = C_ext×#ext + C_rehy×#rehy 降级为**兼容披露通道**(与 H-P1/P3 可比,非主判据)
- 新通道 1 migration/re-encoding cost = 恒等映射假设下 0 成本上界 + ±敏感性报告;token-equivalent 折算细则留测量轮(P0.1 Deferred 口径延续)
- 新通道 2 correctness violation/correction = violation 计数如实报告;correction v1 不货币化
- 新通道 3 granularity→byte accounting = 78,246 KiB/node **适用性重验证 = 实验输出之一**(可映射→给映射表;不可映射→报告并停用;按你的裁定不预判"失效")

**主判据说明**:nodes-out 是机制问题非优化问题——本设计不设性能 PASS/FAIL,全部结果 = 机制知识如实入档。

## Exit criteria(预注册)

- E1 correctness:Candidate A 全部 migration 序列五元组逐项等价 → PASS;violation 如实入档不删除
- E2 成本机制知识:correctness PASS 下,兼容 J 差异 + 新通道读数全部如实报告(无性能预设)
- E3 计账单位:适用性判定如实入档
- 全部出口 = 机制知识,交你署名

## 门位

本设计远端 PASS → Experiment runner 实现 UNLOCKED → v6 回归门重跑(P3-A/B/C 冻结逐位)→ 采数 → 机制知识入档 → 审核署名。

请审核 nodes-out 正式实验设计(c3fe842 基线上的 5c3e82c):①granularity 候选集是否完整(仅 Candidate A 是否足够,或需预注册对照变体);②correctness protocol 的"逐项等价 vs 基线"判定是否可操作;③三成本通道数值口径是否需要收紧。PASS 后实现 runner 并执行实验。
