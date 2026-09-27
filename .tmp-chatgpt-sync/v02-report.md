nodes-out 正式实验设计 v0.2 补锁已落:commit 06f7140(纯文档,已推送;Implementation/Data 继续 LOCKED)。你要求的三点全部落档:

**① correctness protocol 操作化(§2 三层全部锁定)**:
1. event-level correctness:每一次 migration/externalization/rehydration 事件前后,五元组逐项等价;
2. step-level continuation correctness:每一个 decode step 的 continuation 语义(next input 与后续 KV 演化)与基线执行逐项等价;
3. terminal-state equivalence:完整 operation sequence 结束时,终态五元组与基线执行逐项等价。
三层比较对象均为基线执行(未移除 node 外化通道);任何一层不等价 = 该组 correctness violation;runner 内置逐操作断言(继承 v6 L2 模式)。

**② cost channels 数值口径补锁(§3 表格更新+报告纪律)**:
- 新通道 1/2/3 全部独立报告,不并入任何既有 J,不相互合并;每通道给出 n(事件数)/读数/口径三要素;
- Channel 2 correction cost **v1 不货币化**(只报计数与位置)——按你的裁定落死;
- Channel 1 保持"恒等映射 0 成本上界 + ±敏感性"的 v1 口径,P0.1 Deferred 延续;
- Channel 3 = 78,246 KiB/node 适用性重验证 = 实验输出之一(不预判)。

**③ granularity**:维持 PASS 不变(唯一预注册主候选 = Candidate A KV 二态;B/C 增补走 Design Revision)。

## 门位

v0.2 复审 PASS → EXPERIMENT IMPLEMENTATION UNLOCKED → v6 regression gate → runner implementation → P3-A/B/C frozen regression → correctness audit → 采数 → mechanism knowledge archive。

请复审 v0.2(06f7140)。PASS 后我实现 runner 并按 §2 三层 correctness + §3 通道口径执行实验。
