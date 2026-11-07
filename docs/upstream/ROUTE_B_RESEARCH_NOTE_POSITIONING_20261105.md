# 路线 B · Research Note 对外姿态与定位（2026-11-05）

**Status**: 姿态裁定已采纳（用户 2026-11-05）；本文件为**内部定位材料，不构成对外发送授权**——任何联系行为需届时单独确认，且一次只接触一个对象。
**上游**: `docs/upstream/DEEPSEEK_ES_IS_SEMANTIC_ROUTE_20261105.md`（目标表述已随本裁定更新，见其 §0）
**证据纪律**: `OPEN_SOURCE.md` 边界不变；**谦虚表达不能替代充分证据**（裁定原文）。

---

## 1. 姿态定义：从"架构推介"到"研究发现报告"

| | 旧姿态（放弃） | 新姿态（采纳） |
|---|---|---|
| 名称 | 向开源生态提出 ES/IS 架构 | 向相关技术社区开放 ES/IS 研究，邀请独立审查与复现 |
| 请求 | 接受 / 采纳一套语义架构 | 审查定义、实现、证据；指出反例 |
| 判断权 | 在提案方 | **在审查者** |
| 预设 | 具有新意 / 优越性 | 不预设普遍适用性，不预设任何项目需要采用它 |
| 被拒含义 | 提案失败 | 审查有效结果之一 |

核心要点（裁定）：把判断权交给审查者，而不是要求对方认同结论。最重要的表达是"我们不主张这是一项全新的架构创新，也不主张它优于现有 checkpoint、KV reuse 或 durable execution 机制"。

## 2. 对外定位文本（v0 —— P1–P3 全部齐备前不外发）

### 2.1 中文版（定位段，源自裁定原文）

> **Research Note · 独立技术审查邀请（Independent Technical Review）**
>
> 我们在开发 SimiGo 的过程中，探索了一种执行连续性与信息恢复相分离的研究思路。其核心问题是：**当某项工作已经可靠结算，后续执行能否在不依赖原执行实例及其 KV Cache 的情况下，通过独立保存和验证的信息恢复必要结果，并继续推进？**我们将这一探索暂称为 ES/IS（Execution State / Information Space）。
>
> 目前这仍是一项进行中的研究，而非成熟架构提案。我们希望邀请相关领域的工程师和研究者审查其语义定义、实现机制及实验结果，特别欢迎指出与现有技术的重叠、设计缺陷、不可复现之处，以及不成立的适用场景。
>
> 我们不预设其具有普遍适用性，也不预设任何项目需要采用它。

### 2.2 英文工作译文（发布前需终审）

> **Research Note — An exploratory study of Execution State (ES) and Information Space (IS)**
>
> While developing SimiGo, we explored a research direction that separates execution continuity from information recovery. The core question: **when a unit of work has been reliably settled, can subsequent execution recover the necessary results through independently stored and verified information — without depending on the original execution instance or its KV cache — and continue?** We refer to this exploration as ES/IS.
>
> This is work in progress, not a mature architecture proposal. We invite engineers and researchers in relevant fields to review its semantic definitions, implementation mechanisms, and experimental results. We especially welcome reports of overlap with existing techniques, design flaws, non-reproducibility, and scenarios where it does not hold.
>
> We do not claim general applicability, and we do not presume any project needs to adopt it.

### 2.3 表述纪律（裁定列出的五个优点，发布前逐条自检）

1. 没有自称发明了新架构；
2. 没有贬低已有技术；
3. 说明了研究从哪里产生；
4. 给出了可检验的核心问题；
5. 明确欢迎否定性审查。

## 3. 审查有效性判据（裁定）

| 审查结果 | 性质 |
|---|---|
| 对方认为它没有新意 | 有效审查结果 |
| 对方发现它与已有系统互补 | 有效审查结果 |
| 对方复现成功，认为值得进一步研究 | 有效审查结果 |
| 对方最终不采用 | 同样不意味着研究失败 |

研究成功的标准：**提出一个足够清晰、足够具体、值得同行花时间检验的问题**——不需要证明提出了足以改变行业的架构。

## 4. 分对象邀请矩阵（裁定 §3）

| 对象 | 邀请审查的内容 | 不要求什么 | 现有基础 |
|---|---|---|---|
| **llama.cpp（第一优先）** | sequence fork、KV 生命周期、跨执行续接的工程边界 | 不要求接纳完整 ES/IS | `docs/experiments/UPSTREAM_ISSUE_DRAFT_kv_prefix_sharing_cow.md` + fork 实验记录（与路线 A 共享素材，文档分开） |
| DeepSeek | ES/IS 与模型执行、Agent 连续性的语义关系 | 不要求修改模型服务 | 研究问题邀请（非工程改造请求） |
| GLM / 智谱 | 可靠结算结果与 Agent 执行连续性的适用性 | 不要求集成 SimiGo | 研究问题邀请 |
| vLLM / SGLang（后续） | 结算账本与调度 / KV 管理层的衔接 | 不要求采纳 | 与路线 B 第一落地受众判定一致（路线文档 §2） |

排序纪律（裁定）：**不必一次性同时联系所有人；先选一个最有能力审查当前证据的对象。**第一优先 llama.cpp——工程研究与实验基础最具体。DeepSeek / GLM 收到的是更偏研究问题的邀请，不是工程改造请求。

## 5. 证据前置条件（正式邀请前必须齐备）

| # | 前置 | 现状（2026-11-05 核验） | 缺口 |
|---|---|---|---|
| P1 | 语义说明：ES、IS、Settlement、Continuation 的定义及边界 | B0 术语表 **ACCEPTED**（`B0_ESIS_GLOSSARY_20261105.md`）；B1 最小形式化已交付待复核（`B1_ESIS_MINIMAL_FORMALIZATION_20261105.md`）；冻结契约齐备 | 面向**外部读者**的精简语义说明：只依赖冻结合同，不含 SimiGo 内部结构——与 B5 复刻指南合并推进 |
| P2 | **可复刻实验（硬前置）**：真实模型完成结算 → 释放旧 KV → 经 IS 恢复 → 新 ES 继续执行 | IS 契约引用真机验收读数（`research/agent-runs/simigo-es-is-realmodel-20261026/ACCEPTANCE-20261026-BUILD-97043902.md`）；`research/agent-runs/` 不在当前仓库根目录——这是**仓库可及性事实**，不等于材料已丢失、也不等于实验从未做过（裁定 2026-11-05）。须区分两种状态：「历史材料存在但不在本仓」≠「当前可公开复刻的实验链尚未建立」——P2 针对的是**后者**。用户引述的既有发现：单纯的数据库循环和 Python oracle 不足以证明真实模型续接 | 一条**公开可复刻**的实验链：结算 → 释放 KV → IS 恢复 → 新 ES 续推；附独立复现步骤与预期读数。**关键实验不得晚于研究说明**。方案稿：[P2_EXPERIMENT_PLAN_20261105.md](P2_EXPERIMENT_PLAN_20261105.md)（四阶段证据链；G1 CONDITIONAL PASS，P2-R1–R4 修订后待针对性复核；方案成立 ≠ 实验通过） |
| P3 | 相关工作比较：与 KV reuse、checkpoint、durable execution 的相同点与不同点，承认未证明部分 | 路线文档 §5 四项对照（hypothesis 状态） | 逐系统六问核查（保存什么状态 / 谁拥有恢复与续接决定权 / 是否记录来源、版本和依赖 / 是否支持失效判定 / 是否支持跨执行生命周期恢复 / 哪些能力由系统保证、哪些交给应用层）；核查前不得断言现有系统"不具备"某能力 |

**红线（裁定原文）**：不能让一份漂亮的研究说明先于关键实验。P2 优先级高于一切外发准备。

## 6. 与路线文档的衔接

- 路线 B 目标表述已更新（路线文档 §0 姿态修订块）。
- B4 交付物由"提案 v0"改为 **Research Note v0**（研究定位优先于架构定位；原 working title "A Semantic Architecture for..." 降为内部工作标题）。
- B0/B1 产出直接喂给 P1；B3 六问核查喂给 P3；P2 是新增硬前置。
- B6 渠道盘点受姿态纪律约束：一次一个对象，第一优先 llama.cpp，无授权不发送。

## 7. 纪律声明

- 本文件及全部路线 B 材料仍为**内部材料**；未授权对外发送、公开仓库、联系任何组织。
- 每一次对外接触（无论对象）都需届时单独确认。
- 对外文本发布前必须满足 P1 + P2 + P3 全部齐备；P2 未齐备时，任何"先发说明、后补实验"的做法都违反本姿态。
