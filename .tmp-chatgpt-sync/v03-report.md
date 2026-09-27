v0.3 三补锁已落:commit 78d8ca1(已推送)。说明:v0.3 修改此前只做了本地编辑未推送,是我的执行疏漏,本次补交。三处与你的重审要求一一对应:

**① Event-level 对齐基准(§2 锁定)**:两种粒度的事件序列不同构,不做事件一一对应;对齐锚点 = decode step 边界——Candidate A 每个外化/迁回事件完成时所在的 decode step t,取基线执行在同一 step t 的五元组为对齐基准,逐项等价(与 step-level 锚点统一,区别仅采样时机 = 事件完成时刻)。

**② Channel 1 数值口径(§3 方案 A 锁定)**:报告 migration/re-encoding event count + bytes moved/read + timing;v1 modeling assumption = identity mapping, 0 modeled conversion cost;**不建立 token-equivalent cost;不做 ±敏感性**;token-equivalent measurement deferred to later measurement round。±敏感性从设计中完全移除。

**③ E2 wording(§5)**:新通道 1/3 → **新通道 1/2/3**(Channel 2 纳入 E2 报告范围;§3 报告纪律"1/2/3 全部独立报告"已在上一版锁定,两处现已一致)。

## 请三审 78d8ca1

三处补齐后,若 PASS → EXPERIMENT IMPLEMENTATION UNLOCKED,我按已核定的流程执行:v6 regression gate → runner implementation → P3-A/B/C frozen regression → three-layer correctness audit → data collection → mechanism knowledge archive。
