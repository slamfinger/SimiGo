nodes-out 正式开题 DRAFT v0.1 已按你的 10 节结构起草并入库:commit c3fe842(RESIDENCY_NODES_OUT_DESIGN_20260922.md,已推送;Implementation/采数 LOCKED)。你的四处措辞修正全部落实:

1. **Q2 边界纪律**(§3):F 只锁"取消什么"(取消 node-granularity EXTERNALIZE/REHYDRATE pathway);"非节点粒度"标记为**未定义变量**,alternative granularity(KV-only/block-level/其他)只能作为预注册后的实验变量——不预设答案。
2. **Q4 两层分离**(§4):被操作对象 = KV resident/externalized 状态、访问时机、migration/reconstruction 时机、continuation 所依赖可用状态;correctness invariant = Track B 五元组(Identity/Position/NextInput/Continuation)在操作序列前后逐项等价。明文禁止"KV bytes 相同"偷换。
3. **Q3 身份**(§5):KV resident/externalized 二态 = **candidate comparison model**,禁止写成定义/历史事实/唯一后继;其他 granularity 仅预注册后作为 Candidate B/C。
4. **Q5 表述**(§7):78,246 KiB/node 改为"适用性必须重新验证"(可能仍可 node-equivalent 换算,也可能不能——留作实验问题);J 降级为兼容披露通道,三新通道(migration/re-encoding、correctness violation/correction、granularity→byte accounting)独立定义、预注册后才采数。

**核心问题**按你的措辞:"当 node-granularity externalization pathway 被取消后,residency 粒度、execution-state migration correctness 与边界成本之间的关系如何变化?"——串行链 H-P1→nodes-out→P4 已按你给的图式连接。

**correctness 判定**(§6):逐实验组断言五元组在操作序列前后与未移除基线逐项等价;violation = 实验结果如实入档(非门失败);基线自身失效 = 实现错误停机。

**禁止解释**(§9)六项:candidate model 当定义/历史事实、H-P1 ρ 预测 nodes-out、S1 候选机制跨粒度有效性、78,246 KiB 适用性预判、因果/普适表述、预注册前引入新 granularity。

**Exit criteria**(§10):本开题层仅三个退出条件(PASS 进正式实验设计 DRAFT / FAIL 修订退回 / 冻结冲突停机);实验出口判据留给正式实验设计文档预注册。

焦点八项已预列(§附):核心问题措辞/移除边界+未定义变量/两层分离/candidate model 身份/correctness 可操作性/三通道+兼容披露划分/继承禁止出口完整性。

请审核 nodes-out Design DRAFT v0.1(c3fe842)。PASS 后进入正式实验设计 DRAFT(granularity 候选集+correctness 协议+成本通道数值定义的预注册);Implementation/采数仍 LOCKED。
