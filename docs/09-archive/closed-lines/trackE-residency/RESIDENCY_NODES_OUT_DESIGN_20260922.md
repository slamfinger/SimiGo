# Track E nodes-out 正式开题 DRAFT v0.1(2026-09-22)
**DRAFT 待审核;Implementation / 采数 LOCKED(设计 PASS 前零实现零采数)**

> Definition Lock 基线 = `RESIDENCY_NODES_OUT_DEFINITION_RECOVERY_
> 20260922.md`(e5bca86,远端审核 PASS/LOCKED)。本 DRAFT 按远端
> 核定的 10 节结构起草;核心问题措辞按远端建议(不窄化为"性能
> 有没有变好")。

## ① 原始定义(Definition Recovery 考古,e5bca86)

**"nodes-out" 不存在任何历史原始定义。**检索证据:Track B 全部
8 份文档 0 命中;Architecture 2.0 文档 0 次;Policy Opening 0 命中;
M1–M4 仅有 node 粒度 residency 语义、无此术语。唯一历史锚点 = P0.1
Cost Unit Definition(2026-09-21):"nodes-out 挤出计价"为 resident
opportunity cost 三候选之一,提出当日即随三候选整体 **Deferred**,
从未定义、从未实现;后被 H-P1 开题借为串行链占位(原文自标"待决")。
结论:本开题为**首次正式定义**,非历史恢复。

## ② 本轮研究问题

**当 node-granularity externalization pathway 被取消后,residency
粒度、execution-state migration correctness 与边界成本之间的关系
如何变化?**

(不窄化为"移除后性能有没有变好"。本问题在串行链中的位置:
H-P1 答"结构信息能否转化为 residency 控制"→ nodes-out 答
"改变 residency 基本外化粒度后,execution state 是否仍正确、成本
如何重新定义"→ P4 答"哪些结构/状态机制构成核心驻留机制"。)

## ③ nodes-out 移除边界(Definition Lock Q2,F = LOCKED)

**移除 nodes-out = 取消 node-granularity EXTERNALIZE/REHYDRATE
pathway。**

边界纪律:此锁只定义"取消什么",**不预设"取消以后变成什么"**。
residency 二态退化为"非节点粒度"中的"非节点粒度"是**未定义变量**
(远端明确禁止在 Definition Lock 预填答案);alternative residency
granularity(KV-only / block-level / 其他)只能作为正式开题的
**实验变量**,且每个候选须预注册后方可研究。

## ④ execution state 定义(correctness invariant)

两层严格分离:
- **被操作对象**:KV state 的 resident/externalized 状态、KV 访问
  时机、migration/reconstruction 时机、continuation 所依赖的可用
  状态——nodes-out 移除可改变以上全部;
- **correctness invariant**:Track B 五元组(Identity / Position /
  Next Input / Continuation Semantics)必须在 residency/migration
  操作前后保持等价(统一不变式"migration must preserve execution
  identity and continuation"照旧适用)。

禁止偷换:"KV bytes 相同"≠ correctness;correctness 测的是五元组
等价,不是字节相等。parameter residency 与 KV state 正交,不在
nodes-out 操作范围内。

## ⑤ KV / node residency 边界

KV resident / externalized 二态 = **candidate comparison model**
(远端裁定 PASS/CANDIDATE MODEL):可进入正式开题作为待验证比较
模型;身份禁止写成 nodes-out 的定义/历史模型/移除后唯一结果。
其他 alternative granularity(如 block-level)仅在预注册后方可
作为 Candidate B/C 进入比较集。

## ⑥ correctness 定义

对每个实验组(residency granularity 变体):在全部 migration/
rehydration/externalization 操作序列前后,断言五元组
(Identity, Position, Next Input, Continuation Semantics)与参照
执行(未移除 node 外化通道的基线)逐项等价;任何不等价 =
correctness violation,属实验结果如实入档(非门失败,除非连基线
自身都无法保持——那是实现错误,停机查实现)。

## ⑦ cost channels(独立定义;禁止塞进 H-P1 J)

沿用基础设施:C_ext / C_rehy 数值与事件成本语义;J(C_ext×#ext +
C_rehy×#rehy) 仅作为**兼容披露通道**(与 H-P1/P3 可比性),不承担
nodes-out 主判据。新增独立候选通道(全部须在正式实验设计阶段预
注册数值定义后方可采数):
1. state migration / re-encoding cost;
2. correctness violation / correction cost;
3. granularity → byte accounting relationship:P0.1 的
   78,246 KiB/node 是 node-granularity residency model 下的既有
   计账单位,nodes-out 移除后**其适用性必须重新验证**(可能仍可
   映射为 node-equivalent units 作描述性换算,也可能不能——这是
   正式实验要回答的问题之一,非 Definition Lock 预判)。

## ⑧ 与 H-P1 / P3 的继承关系

H-P1(CLOSED/SEALED,edc4dad)输入:mechanism list(S1=D 候选机制
shape=P_S1;S2/S3=C 未验证候选/诊断线索)——nodes-out 链不预判这些
机制在新粒度下的有效性,一切以 P4 立项后的实验为准。P3 冻结零改动
(lru/lfu_aging/belady/V0–V5 冻结参照、C=lfu_aging 参照身份、V0
target 不变);v6 回归门先于 nodes-out 任何实现采数(纪律照旧)。
Hot Null v2 校准结果作为 L1 类工具的方法论资产保留。

## ⑨ 禁止的实验解释

- 禁止把 candidate comparison model 当作 nodes-out 的定义/历史
  事实/唯一后继;
- 禁止用 H-P1 的 L1 ρ 大小预测 nodes-out 任何实验结果;
- 禁止宣称 S1 候选机制在新粒度下仍有效(未经实验);
- 禁止把 78,246 KiB/node 的适用性变化预判为"失效"或"保留";
- 禁止把 L1 existence ≠ mechanism attribution 边界之外做任何
  因果/普适表述;
- 禁止在正式实验设计预注册前引入任何新 granularity 候选。

## ⑩ Exit criteria

nodes-out 链的出口在**正式实验设计**(下一份文档)中逐项预注册;
本开题层的退出条件仅有:
- 本开题审核 PASS → 进入正式实验设计 DRAFT(仍 Implementation/
  采数 LOCKED);
- 本开题审核 FAIL → 按审核意见修订或退回;
- 任何时点发现本开题与冻结约束冲突 → 停机交审核。

## 附:待审核焦点(预列,供审核方)

①核心问题措辞是否达标;②③移除边界 F+"未定义变量"处理是否合格;
④两层分离(被操作对象 vs invariant)是否严格;⑤candidate model
身份表述;⑥correctness 判定(五元组等价 vs 基线对照)是否可操作;
⑦三通道+兼容披露通道的划分;⑧⑨⑩继承/禁止/出口是否完整。
