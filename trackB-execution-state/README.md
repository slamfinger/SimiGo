# Track B — Execution State Fork（第一优先）

**研究问题**：一个已运行到 128K/256K 的执行状态，能否低成本派生独立、
可验证、可继续执行的 child state（fork），并以 Page 为单位共享与物化
（COW）？——"一次计算，多未来"。

**依据**：F0 探针缺口清单（sequence identity / COW prefix sharing /
惰性物化）+ mlx-lm #980（hybrid 架构 prefix cache 整体失效，Qwen3.5
零缓存收益）+ #1849（paged KV 提案中）。三方收敛：**缺的不是 KV
Cache，是 Execution State 抽象**。

**边界（报告 §5.1 v1.1）**：
- **不研究"Paged KV + COW"存储层本身**——存储层做成可替换设计，
  跟踪 #1849 与 F0 上游草案
  （主仓 `docs/experiments/UPSTREAM_ISSUE_DRAFT_kv_prefix_sharing_cow.md`）
  合流；
- 研究其上一层：COW KV + COW 递归态（GDN）+ 可恢复 execution identity
  + fork/restore/branch 语义 + 单用户策略层。

**依赖**：`~/Documents/mlx-swift-lm` fork 实验分支（branch requirement）。
**远端备份**：`slamfinger/mlx-swift-lm` fork 已建，
`exp/execution-state-fork` 已推（2026-09-21 用户确认"推分支到远端
备份,但不是推上游";与本地 5e39800 同步;**上游 ml-explore 永不推**)。
**上游同步**：**mlx-swift-lm #629**(本方 RFC,2026-09-18 提交,open
无回复,2026-09-20 验真登记——见
`EXTERNAL_REVIEW_RECONCILIATION_20260920.md`)+ mlx-lm #1849(提案中)。
F4-D 素材已整理为技术报告草稿
(`TRACK_B_TECH_REPORT_629_FOLLOWUP_DRAFT_20260921.md`),待审定后由
维护者发布。

**验收（三数 + 一门）**：
1. **Fork Cost**：fork 操作亚秒级（元数据 O(1)）；物理增长 ∝ 分叉后缀
   （分叉后首次写入物化天然 O(后缀)，计入 growth 不计入 fork 延迟）。
   基线 = 磁盘 fork 1.53GB / 1.94s @63.6K；
2. **Restore Depth**：成本随 A→B→C→D 深度平/亚线性。
   基线 = 18.2s @120K（`V17_RUNTIME_MATRIX/README.md:200`）；
3. **Shared Page Ratio**：N 次 fork 后 shared_ratio / physical_growth，
   通过 = 增长与分叉后缀成正比；
4. **正确性门（一票否决）**：fork 态 greedy decode 与同前缀从零
   prefill 逐 token 一致，否则全部速度指标作废。

**止损**：①退化为 O(256K) 全量拷贝；②shared_ratio 不显著高于基线；
③正确性门不过——任一结构性失败，调整方向或关闭本 track。

**架构利好**：qwen3_5_moe 混合布局 COW 友好——长上下文内存集中于
attention KV（append-only，天然分页）；GDN 态 O(1) 尺寸（fork = 固定
memcpy）。"GDN 不可 trim/rewind"在 fork/COW 语境不构成障碍。

**统一正确性不变式(Track B 全程,自 F5 起)**:
**Representation migration must preserve execution identity and
continuation**——迁移不仅要求 KV element-exact,还要求 execution
identity 一致、next-input 状态一致、continuation token 一致、**后续
KV 演化一致**(比 KV equality 严格;F5-1 的 mInput bug 即为其反例证明)。

**状态**：**CLOSED / FROZEN（2026-09-21 终审 PASS/FREEZE；v4 为
Track B 正式终点，无 v4.1）**。终审按 v4 实际提交（acbcb54）三层复审
（语义/可证伪性/结果一致性）全过：G5 discard 语义闭环——父代从
fork 前自身 next-input 继续（discard ≠ adopt），v3 的 "parent state +
childNext" 非法组合消失；parentInputsAgree 被接受为真可证伪条件
（双侧独立产生 + 相等断言，非装饰性 assert）；5/5 由此具有 Closure
意义（⑤ = 完整 discard lifecycle 语义链）。G2 迁移单元契约此前已获
审核正式接受。**冻结范围纪律（钉死）**：*Closure v4 proves lifecycle
semantic correctness under the tested execution position; it does
not prove performance superiority, estimator robustness, or general
residency behavior*——不证性能优越性、不证估计器鲁棒性、不证
Residency 行为（**Residency ≠ Closure**）。表述纪律沿用：discard =
parent remains intact，非 adopt；gate3 只证发生过中途决策；gate4 =
预注册门；regret 仅描述性；τ̂ 热敏感为估计器已知特性。已知边界如实
入档：τ̂ 热敏感、热节流下性能方差、估计器鲁棒性未闭合、Residency
未测。审计链 v1→v4 完整保存为史料（不删错），收敛模型 =
**Execution State = KV + Identity + Position + Next Input +
Continuation Semantics**。**下一步（终审定序；① 已完成）**：① #629 技术报告审定 **完成**——
五项终审全过，**REVIEWED / RELEASE CANDIDATE**（cc7dcb8 + 终审后
唯一措辞微调 "largely removes the steady-state tax"）→ ② 对外发布
follow-up（维护者对外动作，待用户）→ ③ Track B 完整归档 →
④ Residency M1 开题（克制：Resident→Externalized→Rehydrated→
Continue；**首门仅问 ExecutionId(before)==ExecutionId(after)**；其后
M2 状态精确、M3 continuation、M4 rehydration 税；Track 命名待真源
定夺，见真源 §5.3 命名冲突记录）→ ⑤ exp06 M1 并行 → ⑥ Residency
M2–M4 → ⑦ Residency Policy → ⑧ Execution+Residency 双 Policy →
⑨ Future 2.0 架构。终审纪律：不重跑 Closure、不改 4184aa6、不改
v1–v3 史料、不为报告补 benchmark、不把 Residency 提前塞进报告。记录：F1→Closure 十份（+v3/v4 审计
响应增补 + 终审判定）+ 技术报告（REVIEWED / RC）+ 外部对照；代码：
`exp/execution-state-fork` @ acbcb54（本地 + slamfinger fork 同步，
上游永不推）。
