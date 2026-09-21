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

**依赖**：`~/Documents/mlx-swift-lm` fork 实验分支（branch requirement；
远端备份推 `slamfinger/mlx-swift-lm` fork，待建）。
**上游同步**：**mlx-swift-lm #629**(本方 RFC,2026-09-18 提交,open
无回复,2026-09-20 验真登记——见
`EXTERNAL_REVIEW_RECONCILIATION_20260920.md`)+ mlx-lm #1849(提案中)。
F4-D 素材优先对接 #629,补给等 F4 续项出数后一并提交。

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

**状态**：**Track B 闭环收官(2026-09-21)**——Closure 5/5 过 +
**#629 follow-up 技术报告草稿完成**
(`TRACK_B_TECH_REPORT_629_FOLLOWUP_DRAFT_20260921.md`,英文待审定,
发布属对外动作由维护者定夺;F4-D 骨架退役为史料)。
结论(审核批准表述):execution state 可以在执行生命周期内进行共享、
表示迁移与自适应选择,并在表示变化过程中保持 execution identity 与
continuation 不变。完整记录:F1→Closure 十份 + 技术报告 + 外部对照 +
F4-D 骨架(退役)+ 模拟器脚本;代码:vendor 分支
`exp/execution-state-fork`(基于 8f37dbc,永不进 1.7 发布路径)。
**待办**:①报告审定后发布 #629;②Track C(Model-State Residency)
开题——注意与真源报告 §5.3 Track C(Multi-device)命名冲突,新轨
建议命名 Track E 待真源更新定夺;③exp06 M1 本机基线(Track A 开关)。
