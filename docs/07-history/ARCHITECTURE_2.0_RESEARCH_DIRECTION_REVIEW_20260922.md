# Architecture 2.0 Research Direction Review — 2026-09-22

> **Purpose:** 在 Execution State intellectual closure 完成后，重新审视 Architecture 2.0 中哪些长期思想值得继续形成独立研究问题。
>
> **Governance status:** 本文是方向复盘 / provenance review，不是 Research Track、Research Question、Experiment、Finding、Decision 或 implementation authorization。
>
> **Research-gate effect:** NONE。本文不启动 STEP⑤，不注册新的 RQ，不改变任何 CLOSED / SEALED / FROZEN 状态。

## 1. 当前锚点

Execution State 已完成独立的 Intellectual Closure Review。

Track B 在其限定 scope 内已经形成闭环：

`fork → continue → branch → representation transition / reattach → continue → discard`

因此当前真正需要回答的不是：

> “Track B 之后还能不能继续做 Execution State 实验？”

而是：

> **Execution State 的闭环究竟留下了哪些可以独立生长的 Architecture 2.0 思想？哪些只是架构推演？哪些已经具备形成独立研究问题的结构？**

本复盘不把“下游思想”视为 Track B 的自动结论。

## 2. 复盘方法

对每个候选思想只检查以下关系：

`Idea → Origin → What Track B changed → What remains unknown → Candidate research object → Current status`

其中：

- **Origin**：该思想从哪里产生；
- **Track B changed**：Track B 实际改变了什么认知；
- **Remaining unknown**：当前仍不知道什么；
- **Candidate research object**：如果未来研究，究竟要研究什么对象；
- **Current status**：Memory hypothesis / definition candidate / candidate RQ 等；
- **Forbidden inference**：明确禁止从已有结果越级推出什么。

本复盘不对候选方向进行“最好/最差”排序，也不替人决定下一研究问题。

## 3. 已经确认的上游基础

### 3.1 Execution State 不再只是“保存 KV”

历史思想从：

`save KV/cache`

逐步收敛为：

`reusable computed state → Execution State → identity + continuation → forkable lifecycle-bearing state`

Track B 又进一步确认：

- lifecycle operations 可以组合；
- representation 与 state identity 可以分离；
- representation transition 可以作为 lifecycle operation；
- discard 可以保持 parent continuation；
- tested scope 内存在 bounded execution-state lifecycle。

这些内容已经进入 Track B closure，不应重新作为下一研究问题的起点。

### 3.2 但 Execution State closure 没有自动证明下游架构

尤其没有自动证明：

- universal runtime Model Unit；
- universal residency object；
- universal sharding unit；
- planner object；
- predictive residency；
- production adaptive policy；
- complete Architecture 2.0。

因此下一阶段必须重新定义研究对象，而不能沿历史链直接“顺推实验”。

## 4. Architecture 2.0 候选思想 provenance map

| Idea | Origin / durable memory | Track B 实际改变了什么 | 仍未知 | 独立研究对象是否已成形 | 当前状态 |
|---|---|---|---|---|---|
| 智能 ≠ 模型文件 ≠ 物理表示 | RM-029 / Long-Horizon Vision | Execution State 提供了逻辑执行状态与物理表示可分离的具体实例 | 哪些逻辑能力可以在何种非驻留表示下继续执行 | 尚未具体化 | DURABLE ARCHITECTURE HYPOTHESIS |
| Memory Manager → Execution Manager | RM-030 | Execution State lifecycle 暗示管理边界可能高于 bytes | 是否存在可独立观察、管理、决策的 execution-aware resource boundary | 尚未具体化 | FUTURE ARCHITECTURE HYPOTHESIS |
| Residency 是状态 | RM-031 / P3 lineage | 历史研究已把 residency 从 load/unload 扩展到更丰富状态语义 | 哪些 residency state 在真实 runtime 中具有独立机制身份 | 部分成形，但对象边界仍需定义 | DEFINITION CANDIDATE |
| Residency 预测性 | RM-032 | P3 等历史工作提供相关背景，但未验证完整预测机制 | access prediction、prediction error、migration cost、instrumentation cost 与收益关系 | 可能形成独立问题，但尚未定义 estimand | FUTURE RESEARCH CANDIDATE |
| Planner 统一 Execution State / Residency / Compute | RM-033 | Execution State 与 Residency 已显示存在耦合的 lifecycle / cost 问题 | 是否存在需要统一决策边界的 runtime mechanism | 尚未具体化 | ARCHITECTURE HYPOTHESIS |
| Runtime Sharding | RM-034 | unit-discovery 思想得到方法论支持 | runtime 是否会产生可独立管理的行为边界，以及这些边界能否成为 sharding group | 候选对象存在，但尚未完成定义 | FUTURE RESEARCH CANDIDATE |
| Execution-State Sharding | RM-035 | Track B 证明不同 state component 可拥有不同 fork / representation semantics | 是否存在可独立管理且可跨 representation 生命周期保持的 state partition | 候选对象较清晰，但尚未形成 RQ | FUTURE RESEARCH CANDIDATE |
| 计算结果 = reusable execution asset | RM-036 | Track B 在 bounded scope 内验证了部分 asset lifecycle | 完整 lifecycle 的哪些操作在真实 runtime 中具有独立语义与经济价值 | 候选对象存在，但范围很大 | ARCHITECTURE HYPOTHESIS |
| Fork 是生命周期操作之一 | RM-037 | 已被 Track B closure 实际吸收 | 更完整 lifecycle 的 runtime boundary 是否可独立观察 | 已被上游 closure 部分消化 | DURABLE ARCHITECTURE HYPOTHESIS |
| Minimum Sufficient Working Set | RM-038 | lifecycle / residency / migration 成本使“最小内存”目标显得过窄 | 如何定义 sufficient、working set、cost function 与约束 | 概念清楚但 estimand 未定义 | FUTURE RESEARCH CANDIDATE |
| 研究对象不由上游 API 定义 | RM-039 | Source/Runtime Definition 已将 theoretical object 与 observable boundary 分开 | 能否从 runtime observation 独立建立 object existence | 已经进入当前 Definition chain | CURRENT DEFINITION METHOD |
| Semantic-light Runtime | RM-024 / RM-039 | component-specific semantics 与 runtime boundary 的分离得到方法论支持 | 在不依赖 upstream semantic labels 时，哪些 runtime properties 仍可独立观察 | 候选对象存在 | FUTURE RESEARCH CANDIDATE |

## 5. 当前最重要的分界

### 5.1 已经不是下一步研究对象的内容

以下内容不应因为 Architecture 2.0 复盘而重新打开：

- Track B lifecycle；
- Track B fork / continue / reattach / discard 的既有 closure；
- Track E；
- 已 sealed 的 P3 / H-P1；
- 已关闭的 nodes-out；
- 任何历史实验的重新执行。

它们属于已完成或冻结的知识资产。

### 5.2 尚不能直接成为实验的内容

以下思想虽然具有研究价值，但目前仍缺少完整的：

`Object → Question → Independence → Estimand → Existence Criterion → ...`

因此不能直接跳到 implementation / harness / experiment：

- predictive residency；
- runtime sharding；
- execution-state sharding；
- minimum sufficient working set；
- semantic-light operational unit；
- planner；
- execution-aware resource management。

### 5.3 当前 Definition chain 真正触及的核心

当前 Source/Runtime definition work 正在处理的其实是一个更基础的问题：

> **如果某种“runtime operational unit / Model Unit”在系统层面存在，它是否能够在预注册的模型、workload、observation domain 内，通过独立可观察的 runtime boundary structure 被识别？**

STEP④ 已经只定义了 estimand：

`B(M,W,O)`

以及候选 boundary descriptor：

`S(b)=<A_b,R_b,C_b,I_b>`

其中 A/R/C/I 是描述维度，不是 existence criterion。

因此目前不能把：

`B(M,W,O) → Model Unit exists`

当成已成立关系。

## 6. 为什么现在值得停下来做方向复盘

如果现在直接进入 STEP⑤，很容易发生一种结构性错误：

`Architecture 2.0 idea → choose one interpretation → existence criterion → experiment`

这样会把“长期思想”偷偷压缩成一个未经比较的具体研究对象。

更稳妥的顺序是：

`Execution State closure`
↓
`Architecture 2.0 direction review`
↓
`identify candidate independent objects`
↓
`only then choose/define a research question`
↓
`STEP⑤ for that specific object`

这里的“review”不是拖延，而是防止把上一条研究线的惯性当成下一条研究线的研究对象。

## 7. 当前候选方向的成熟度判断

为了避免“思想很多 = RQ 很多”的误判，可以把当前资产分成四类。

### A. 已成为 durable method / boundary

- RM-039：研究对象不能由当前 upstream API 定义；
- RM-040～043：思想—实验—证据—决策—架构的连续性与 Agent memory 原则。

这些不是下一实验对象，而是研究治理基础。

### B. 已被 Track B 部分验证，但不需要立即重开

- Execution State lifecycle；
- fork / continue / representation transition / discard；
- representation 与 state identity 的分离；
- execution asset 的 bounded lifecycle interpretation。

它们作为上游基础继续存在，不应重新做同一问题。

### C. 已形成较明确的未来研究对象候选，但尚未成为 RQ

- runtime operational unit / Model Unit existence；
- execution-state sharding；
- runtime behavior-derived operational grouping；
- predictive residency；
- minimum sufficient working set。

这些方向各自仍需要独立回答“对象是什么、为什么独立、estimand 是什么”。

### D. 目前更像上层架构组织方式，而非独立研究对象

- Memory Manager → Execution Manager；
- Planner；
- 完整 execution-asset management architecture；
- Architecture 2.0 overall architecture。

这些可以继续作为上层假设保存，但不能因为图景完整就直接成为实验对象。

## 8. 当前不应做的选择

本复盘明确不作以下选择：

1. 不宣布“Model Unit”就是下一研究对象；
2. 不宣布“Execution-State Sharding”就是下一研究对象；
3. 不宣布“Predictive Residency”就是下一研究对象；
4. 不把 Minimum Sufficient Working Set 当作已经定义的 optimization target；
5. 不把 Planner 当作必须实现的 runtime component；
6. 不把 Architecture 2.0 长期图景当作既定架构；
7. 不因为 STEP④ 已 PASS 就自动启动 STEP⑤；
8. 不因为历史主线曾经从 Execution State 走向 Residency，就认为未来必须沿同一路线继续。

## 9. 下一合法动作

当前最合适的动作不是实验，而是：

> **从上述候选方向中逐一检查“独立研究对象是否已经形成”，并在必要时为某一个候选对象重新建立 Definition / Opening。**

对于当前 Source/Runtime 线，仍保留：

- STEP④ PASS；
- STEP⑤ UNSTARTED；
- RQ ID 未分配；
- 无 implementation / measurement authorization。

如果后续决定继续这条线，下一份正式研究文档应先回答：

> **Model Unit / runtime operational unit 到底是一个怎样的独立研究对象，而不是它应该由什么 API 或代码对象来实现。**

如果复盘后发现另一个 Architecture 2.0 idea 更适合作为独立研究对象，则应另开其自己的 Definition / Opening，不得借用当前 STEP④ 的 estimand 或 gate。

## 10. Governance conclusion

本复盘的结论不是“下一步做 X”。

结论是：

> **Execution State 已经完成自己的 intellectual closure；现在应先把它产生的 Architecture 2.0 下游思想重新分层，确认哪些只是长期架构假设、哪些已经形成独立研究对象、哪些仍需 Definition，之后再决定是否进入 STEP⑤。**

因此本文件完成后：

- Track B：仍 CLOSED / FROZEN；
- Track E：仍 CLOSED / SEALED；
- P3 / H-P1 / nodes-out：状态不变；
- P4：仍 NOT STARTED；
- RQ-F-01：仍 NOT DEFINED；
- 当前 STEP④：仍 PASS；
- 当前 STEP⑤：仍 UNSTARTED；
- 不产生实验授权；
- 不产生实现授权；
- 不产生新的 RQ ID。

**Research-gate effect: NONE.**

---

## 11. Recovery sentence

新 Agent 恢复到本阶段时，应能够从本文直接得到：

> “Execution State 已完成闭环；现在不是继续做 Track B，而是重新审视 Architecture 2.0 哪些思想已经长成独立研究对象。STEP④ 虽已 PASS，但 STEP⑤ 尚未启动；任何候选方向都必须先经过自己的对象—问题—独立性—estimand 定义，而不能从 Architecture 2.0 图景或历史实验直接跳到实现与测量。”
