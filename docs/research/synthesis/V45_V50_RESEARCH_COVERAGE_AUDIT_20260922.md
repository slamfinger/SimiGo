# V4.5 → V5.0 Research Coverage Audit（2026-09-22）

> 目的：检查 V4.5 的核心架构主张是否已经在 V5.0 Research / Knowledge 层留下可追溯证据。
>
> 本表不是“通过率”，也不是对历史工作的评分。状态仅表示研究链条目前的完整程度。

## 状态定义

- **COVERED**：已有原始证据、Finding/Invariant，并能回到当前架构。
- **PARTIAL**：存在证据，但研究问题、独立通道或知识沉淀尚未完整。
- **OPEN**：历史上提出过，但当前没有足够证据支持升级。
- **SUPERSEDED**：V4.5 的具体实现已被 V5.0 官方语义取代；历史原则保留，但旧实现不再作为当前架构事实。

## Coverage Matrix

| V4.5 主题 | 当前研究承接 | 状态 | 当前证据 | 缺口 |
|---|---|---|---|---|
| Agent Runtime ≠ Inference Runtime | V5.0 Core boundary | COVERED | v4.5 baseline / v5.0 architecture | 无明显研究缺口 |
| Logical State Isolation | Logical/Physical separation | COVERED | V4.5 baseline + invariant | 尚需持续并发回归 |
| Session ≠ Physical KV ownership | Official Semantics First | COVERED | ChatSession capability audit + Finding | 不应恢复第二 KV authority |
| Physical Token Ledger | Official ChatSession ownership | COVERED | capability matrix + audit lessons | 继续跟踪 upstream evolution |
| Tool Fingerprint Safety | Tool protocol / cache compatibility | PARTIAL | v4.5 rules + protocol findings | 需要独立研究问题覆盖长期演化 |
| Tool Parse / Normalize / Commit boundary | Protocol normalization | COVERED | tool protocol evidence + protocol Finding | 继续扩大异常输入矩阵 |
| Cancellation safety | Session readiness | PARTIAL | poisoned-session incident + invariant | readiness 状态仍是最小实现 |
| Lifecycle convergence | Session / task lifecycle audits | PARTIAL | cancellation evidence + Task API audit target | 需要完整 lifecycle evidence map |
| Memory admission / eviction | Official KV ownership + resource boundary | PARTIAL | v4.5 baseline + capability migration | 当前官方语义与本地 resource governance 的边界需继续验证 |
| Long-context pressure | Long-context field observation | PARTIAL | 90K field observation | 需要跨任务/模型重复观察 |
| Observability | cache telemetry / runtime traces | COVERED | official telemetry + runtime evidence | 指标语义继续保持单一来源 |
| Physical KV Reuse | Official token ledger | COVERED | capability matrix + field evidence | 不应回退到自有 KV protocol |
| Controlled Batch / S1 | Evolution Track | OPEN | historical prototype / NO-GO records | 需要新的 capability question，不从旧原型直接进入 Core |
| Execution Fork / shared prefix | F0 research question | COVERED (bounded) | F0 probe + upstream audit | 仅对测试版本成立；等待 upstream capability |
| Continuous Batching / S3 | Evolution Track | OPEN | archived roadmap | 尚无 Core 级证据 |
| Hybrid / Mamba batch semantics | Evolution Track | OPEN | NO-GO rationale | 等 upstream per-sequence state semantics |
| Speculative Decode | Official capability matrix | PARTIAL | official API presence | 需要实机 capability benchmark |
| VLM / multimodal | Official capability matrix | OPEN | API capability inventory | 尚未形成 Core research question |
| Prompt cache save/load | Official capability matrix | OPEN | API audit | 尚未完成实机证据 |
| Guided Generation | Official capability matrix | OPEN | API audit | 尚未完成 integration evidence |

## 1. 当前真正完成的研究闭环

目前最完整的闭环主要有四条：

### A. Official Physical KV Semantics

`V4.5 Physical KV`
→ upstream capability audit
→ ChatSession semantic authority
→ simplification finding
→ Official Semantics First
→ V5.0 boundary

### B. Execution Fork

`Branch/Fork requirement`
→ F0 controlled probe
→ public API capability gap
→ bounded negative result
→ keep fork outside Core

### C. Cancellation / Session readiness

`mid-prefill cancellation`
→ poisoned reusable session
→ real-device regression
→ readiness invariant
→ current minimal eviction guard

### D. Protocol boundary safety

`tools:null / tool representation mismatch`
→ reproduction
→ boundary diagnosis
→ normalization/type guard
→ regression evidence

## 2. 当前最大的研究缺口

不是“还缺很多文档”，而是以下三类：

### Gap 1：V4.5 不变量与 V5.0 不变量的逐项映射

V4.5 有大量历史铁律，V5.0 收敛为较少的核心不变量。

现在已经知道两者发生了架构收敛，但还没有建立逐条映射：

`V4.5 Rule → V5.0 Invariant / Superseded / Evidence`

这是下一阶段最值得做的历史研究工作。

### Gap 2：Official Capability Completion 尚未全部进入 Research

Prompt Cache Save/Load、Guided Generation、Speculative Decode、VLM 等目前主要停留在 capability inventory。

不能因为“官方 API 存在”就把它们写成已经完成的知识。

### Gap 3：Evolution Track 与 Core 的证据边界

S1/S2/S3 已有大量历史设计，但其中一部分来自旧自研 Runtime 时代。

需要明确：

- 哪些仍然是有效研究问题；
- 哪些只是历史实现方案；
- 哪些已经被 V5.0 的 Official Semantics First 否定；
- 哪些需要新的 upstream capability 才能重新打开。

## 3. 研究完整性规则

今后新增 Research Question 时，应至少能回答：

1. 它改变了哪个未知量？
2. 它的主要观察对象是什么？
3. 它有哪些真正独立的证据通道？
4. 什么结果会使当前假设失败？
5. 即使实验失败，是否能得到可复用 Finding？
6. 结果是否改变 Core / Evolution / Upstream Research 的边界？

如果不能回答以上问题，就先作为 Experiment / Investigation，不急于升级为 Research Conclusion。

## 4. 当前结论

V4.5 → V5.0 的主要架构转折已经具有可追溯证据链；但研究体系仍处于“第一轮知识迁移”阶段。

因此当前最合理的状态不是宣称 Research Layer 已完成，而是：

**Core architecture 已稳定；Knowledge layer 已启动；Research coverage 正在建立；Evolution capability 仍需逐项重新验证。**

下一项历史研究任务：

`V4.5 Rule 1–99 → V5.0 12 Core Invariants / Superseded / Open Evidence`

这项工作应保持回溯性质，不改变现有架构，只建立证据索引。
