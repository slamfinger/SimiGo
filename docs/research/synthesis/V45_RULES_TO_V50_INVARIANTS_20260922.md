# V4.5 Rule 1–99 → V5.0 Evidence Mapping（2026-09-22）

> 历史映射审计。目的不是重新评价 V4.5，而是判断 99 条铁律在 V5.0 中的命运：仍为核心、语义保留但实现权威迁移、已被具体实现取代，或尚无足够证据。
>
> **禁止把“有对应文字”误认为“有独立证据”。** 本表优先依据现有 V5.0 白皮书、Capability Matrix、Research/Knowledge 层和历史实验。

## 状态说明

- **COVERED**：当前架构仍明确成立，并已有相应证据/契约。
- **PARTIAL**：原则仍有价值，但证据、研究问题或跨场景验证不完整。
- **SUPERSEDED**：历史语义可能保留，但 V4.5 的具体实现/所有权已经被 V5.0 或官方能力取代。
- **OPEN**：仍属于未来 Execution/Evolution 研究，不能直接当作当前 Core 事实。

## 全量映射

| Rule | V4.5 主张 | V5.0 状态 | 依据 / 缺口 |
|---:|---|---|---|
| 1 | Evolution discipline | **OPEN / SUPERSEDED** | 稳定基线思想仍成立；V5.0 已改为 Core + Evolution，而非继续维护 v4.5 implementation. |
| 2 | Inference Runtime ≠ Agent Runtime | **COVERED** | V5.0 I1 |
| 3 | HTTPServer is Protocol Gateway | **COVERED** | V5.0 Protocol boundary |
| 4 | Agent/Session/Branch/Request identity | **COVERED** | V5.0 I3 + Context model |
| 5 | Session identity ≠ KV isolation | **COVERED** | V5.0 I4; official ChatSession finding |
| 6 | Logical isolation / physical sharing | **COVERED** | V5.0 I3/I4 |
| 7 | Namespace vs token exact match | **COVERED** | V5.0 I4/I6 |
| 8 | Model + ToolFP + Prefix + Residency reuse gate | **SUPERSEDED** | 旧自研 Revision/Residency authority 不再由 SimiGo 持有；semantic compatibility remains V5.0 I4/I6. |
| 9 | Physical Token Ledger | **SUPERSEDED** | 语义保留，但 ledger ownership 已转给 official ChatSession. |
| 10 | Token ↔ KV synchronized mapping | **SUPERSEDED** | 仍是语义约束；具体 token ledger 事实来源转为官方. |
| 11 | Trim syncs KV + Ledger | **SUPERSEDED** | 由 official PromptCacheReusePolicy/ChatSession 负责. |
| 12 | Delta prefill starts at commonLen | **SUPERSEDED** | 历史执行策略；不再作为 SimiGo 自有 KV protocol. |
| 13 | Exact match must not full-prefill | **SUPERSEDED** | 语义由官方 cache reuse policy 承担；当前不保留本地实现权威. |
| 14 | Commit actual generated tokens | **SUPERSEDED** | 物理提交语义保留；官方 session owns token/cache accounting. |
| 15 | Revision is compute result, not Session ownership | **COVERED** | V5.0 Physical KV definition. |
| 16 | Tool Fingerprint only KV semantic compatibility | **PARTIAL** | 原则仍成立；长期 ToolFP research coverage 尚未单独注册. |
| 17 | Tool Call is model output; SimiGo does not execute | **COVERED** | V5.0 I1 + Tool boundary. |
| 18 | {} is valid zero-arg Tool Call | **COVERED** | Protocol finding / V5.0 boundary. |
| 19 | Malformed history fail-fast | **COVERED** | Protocol boundary finding. |
| 20 | Degeneration belongs Logical Branch | **PARTIAL** | V5.0 state separation supports it; dedicated current evidence is limited. |
| 21 | Partial dispatch keeps attemptedSignatures | **PARTIAL** | Historical tool protocol evidence; not yet promoted to standalone research question. |
| 22 | Cancel-before-dispatch cannot fake transition | **PARTIAL** | Covered by cancellation lessons, but not standalone RQ. |
| 23 | Client disconnect enters cancellation | **PARTIAL** | Lifecycle evidence exists; complete protocol-to-lifecycle coverage remains open. |
| 24 | Cancellation cannot commit incomplete KV | **COVERED** | Cancellation/session evidence + V5.0 I10. |
| 25 | Same Logical Branch serial | **COVERED** | SessionGenerationGate contract + V5.0 state separation. |
| 26 | Runtime lifecycle globally serial | **COVERED** | RuntimeLifecycleGate evidence. |
| 27 | Stop closes admission/cancels/drains/releases | **PARTIAL** | Historical invariant; current official resource ownership means mapping is implementation-sensitive. |
| 28 | Do not clear active ownership directly | **PARTIAL** | Historical lifecycle/resource lesson; no current standalone RQ. |
| 29 | Bounded cache + Predictive Admission before prefill | **SUPERSEDED** | V5.0 moved Physical KV/resource authority toward official memory governance; predictive ledger is not current Core fact. |
| 30 | Streaming parser cannot control KV/lifecycle | **COVERED** | V5.0 state separation. |
| 31 | Responses state ≠ Physical KV | **COVERED** | V5.0 Protocol/Physical KV boundary. |
| 32 | previous_response_id ≠ KV key | **COVERED** | V5.0 Protocol/Physical KV boundary. |
| 33 | KV reuse is not KPI | **COVERED** | V5.0 performance principle. |
| 34 | KV optimization cannot break protocol/lifecycle/tool correctness | **COVERED** | V5.0 I12 + evidence discipline. |
| 35 | Runtime modification requires benchmark | **COVERED** | V5.0 evidence discipline. |
| 36 | No benchmark/audit/stress, no stable core | **COVERED** | V5.0 I12. |
| 37 | One major variable at a time | **PARTIAL** | Experiment discipline; not a Core invariant. |
| 38 | Multi-Agent KV reuse is optimization, not Agent Runtime | **COVERED** | V5.0 boundary. |
| 39 | LAN node is service capability, not orchestration | **COVERED** | V5.0 boundary. |
| 40 | Protocol compatibility cannot pollute lifecycle | **COVERED** | V5.0 canonical request + lifecycle. |
| 41 | Session uniqueness must not force cold prefill | **COVERED** | V5.0 physical reuse model. |
| 42 | Global Physical KV is compute reuse layer, not conversation state | **COVERED** | V5.0 Physical KV definition. |
| 43 | Shared KV requires model/tool/token semantic consistency | **COVERED** | V5.0 I6. |
| 44 | Branch serialization ≠ global model serialization | **PARTIAL** | Still architectural intent; future execution concurrency needs continued evidence. |
| 45 | Eviction releases residency without deleting logical ledger | **SUPERSEDED** | Lossless semantic principle retained, but current Physical KV ledger ownership is official. |
| 46 | Finished/cancelled request cannot re-enter runnable set | **PARTIAL** | Lifecycle principle covered; current evidence not separately mapped. |
| 47 | No duplicate decode participation in one scheduling epoch | **OPEN** | Old scheduler invariant; S1/S3 capability is currently open. |
| 48 | Scheduler balances throughput/fairness/latency | **OPEN** | Historical optimization criterion; no current Core scheduler evidence. |
| 49 | Prefill chunking protects decode progress | **OPEN** | Execution optimization, not current Core. |
| 50 | Batch is local execution capability | **OPEN** | Evolution Track; no current stable batch evidence. |
| 51 | Scheduler owns Execution, not Agent/Session state | **COVERED** | V5.0 scheduler boundary. |
| 52 | Resource scope orthogonal to semantic reuse | **COVERED** | V5.0 resource/physical separation. |
| 53 | KV selection and resource budget are independent | **COVERED** | V5.0 Physical KV / Resource separation. |
| 54 | Contention root cause must be instrumented | **PARTIAL** | Observability principle exists; future contention research remains. |
| 55 | Scheduler optimization requires E2E/stability proof | **OPEN** | Scheduler itself is not current Core capability. |
| 56 | longContextThreshold drives stronger eviction | **SUPERSEDED** | Specific threshold/strategy is tuning/history, not V5.0 invariant. |
| 57 | Long context does not change semantic reuse | **COVERED** | V5.0 Physical KV definition/resource separation. |
| 58 | Internal KV budget model | **SUPERSEDED** | Old local admission model retired; current resource semantics defer more to official MLX memory governance. |
| 59 | Revision count ≠ memory budget | **COVERED** | V5.0 resource separation. |
| 60 | Long-context pressure ≠ multi-agent contention | **PARTIAL** | Long-context finding exists; cross-factor study remains open. |
| 61 | Swap is diagnostic, not KV size | **COVERED** | V5.0 resource model. |
| 62 | End-of-request resource cleanup must be observed | **COVERED** | Lifecycle/observability evidence. |
| 63 | Long-context thresholds need benchmark backing | **PARTIAL** | Single 90K observation is insufficient for generalization. |
| 64 | clearCache is auxiliary, not lifecycle control | **SUPERSEDED** | Historical implementation rule; lifecycle ownership changed. |
| 65 | Structured Tool Call primary, raw fallback secondary | **SUPERSEDED** | Current official parser/rejectedToolCall path removed old raw parser; principle survives only where fallback is needed. |
| 66 | Raw parser state is generation-local | **SUPERSEDED** | Old parser removed; state-separation principle remains. |
| 67 | Raw tool parser incremental state machine | **SUPERSEDED** | Old fallback implementation removed after upstream coverage. |
| 68 | Tool body cannot leak to ordinary text | **SUPERSEDED** | Historical raw-parser invariant; official structured path now primary. |
| 69 | Structured/raw tool dedup | **SUPERSEDED** | Old dual-path mechanism removed; no current parallel raw/structured authority. |
| 70 | Parser failure ≠ plain text | **COVERED** | Official rejectedToolCall + boundary normalization. |
| 71 | Raw parse failure blocks KV commit | **SUPERSEDED** | Old raw parser-specific rule; current upstream rejection semantics replace local parser. |
| 72 | raw detected + no forwarded + KV commit forbidden | **SUPERSEDED** | Specific old raw-path state combination; no longer a current Core state. |
| 73 | Malformed/incomplete raw call fail-fast | **COVERED** | Protocol correctness principle remains; current implementation relies on official rejection semantics. |
| 74 | {} valid; missing arguments not inferred | **COVERED** | Protocol boundary finding. |
| 75 | Tool validity necessary for KV commit | **PARTIAL** | Semantic safety remains, but current official session owns physical commit semantics. |
| 76 | Parser cannot own KV/gate/scheduler/executor | **COVERED** | V5.0 state/boundary separation. |
| 77 | Parser transient state cannot become Logical State | **COVERED** | V5.0 state separation. |
| 78 | Raw parser flush order | **SUPERSEDED** | Old implementation detail removed. |
| 79 | Unclosed raw call at EOS is protocol failure | **SUPERSEDED** | Raw parser removed; official rejection path is current authority. |
| 80 | Tool observability distinguishes protocol outcomes | **PARTIAL** | Historical observability contract; current telemetry coverage needs audit. |
| 81 | Parse failure cannot emit normal completion | **COVERED** | Official rejection semantics + protocol boundary. |
| 82 | Tool correctness > permissive continuity | **COVERED** | Protocol fail-fast principle. |
| 83 | Revision count only history bound | **SUPERSEDED** | No current local Revision authority; concept remains as historical lesson. |
| 84 | Revision count is not memory optimization | **COVERED** | V5.0 resource separation. |
| 85 | Local admission budget components | **SUPERSEDED** | Old local admission model retired. |
| 86 | RSS/VM/Swap separate from internal KV ledger | **COVERED** | V5.0 resource model. |
| 87 | RSS cannot directly infer KV size | **COVERED** | V5.0 resource model. |
| 88 | Eviction must be lossless | **PARTIAL** | Semantic principle retained; current official ownership requires continued evidence. |
| 89 | Long-context eviction does not alter match rules | **COVERED** | V5.0 physical/resource separation. |
| 90 | Revision count and resource budget orthogonal | **COVERED** | V5.0 resource separation. |
| 91 | Lifecycle transitions validated by table | **COVERED** | Lifecycle finding/evidence. |
| 92 | RELEASED is terminal | **COVERED** | Lifecycle implementation + evidence. |
| 93 | All termination paths converge in finish() | **COVERED** | Lifecycle implementation + evidence. |
| 94 | Lifecycle ledger does not own resources | **COVERED** | V5.0 Lifecycle boundary. |
| 95 | Ledger cannot report RELEASED before real task cleanup | **COVERED** | Lifecycle lesson/evidence. |
| 96 | Lifecycle state must be bounded | **COVERED** | Lifecycle implementation. |
| 97 | Lifecycle trace must be structured | **COVERED** | Observability architecture. |
| 98 | Do not add parallel state machine when equivalent protection exists | **COVERED** | Simplification finding / Official Semantics First. |
| 99 | RUNNING→COMPLETING reviewed transition edge | **SUPERSEDED** | Version-specific lifecycle transition detail; not a V5.0 Core invariant. |

## 主要结果

### 1. V4.5 并没有“99 条全部继续有效”

这次映射最重要的发现，是 V5.0 并不是把 99 条铁律原封不动搬到新架构。

大量条目可以分成三类：

1. **架构语义继续成立**：如 Agent/Inference 边界、逻辑隔离、物理复用、状态分离、取消安全、生命周期收敛。
2. **语义继续成立，但实现权威迁移**：尤其是 Physical KV / Token Ledger / Trim / Exact Match / Resource 相关条目。官方 ChatSession 成为事实来源后，SimiGo 不再拥有第二套物理状态权威。
3. **历史实现细节被淘汰**：如 Raw Tool Parser 的大量具体状态机规则、Revision Pool、Predictive Admission 的部分实现、旧 Scheduler/Batched Decode 细节。

### 2. 最重要的架构迁移

可以压缩成：

`V4.5 Rule`
→ `问题被真实工程暴露`
→ `实验 / 审计`
→ `发现上游已有更高权威语义`
→ `删除本地重复实现`
→ `V5.0 Core Invariant`

因此，“删除代码”不是知识损失。

相反，部分 V4.5 规则已经完成了：

**实现 → 证据 → 抽象 → 上游语义迁移**

### 3. 当前最需要重新研究的区域

本次映射暴露四个真正的 Open/Partial 集群：

#### A. Execution Scheduler / Batch

Rules 44, 47–50, 54–55 仍有大量历史设计，但当前 S1/S2/S3 并没有足够的新证据进入 Core。

结论：**不要从旧 Batch 原型直接恢复 Scheduler 权威。**

#### B. Long-Context Resource Governance

Rules 60、63 等已有实机证据，但目前仍不足以把单次 90K 观察升级成普遍规律。

下一步应该是跨任务 / 跨模型 / 固定硬件条件下的重复观察，而不是增加新的 admission abstraction。

#### C. Tool Protocol

Rules 65–82 中相当一部分属于已经删除的 Raw Tool Parser 时代。

这些条目不应继续制造“旧 Parser 的幽灵状态”。

真正需要保留的是更高层原则：

`protocol correctness → safe normalization → no malformed semantic state`

#### D. Lifecycle

Rules 91–99 是目前历史证据最完整的一组，但仍应把“实现状态机”与“生命周期必须收敛”区分开。

长期 Core 是 **termination convergence**，不是某一个具体 enum / transition table。

## 4. 与 V5.0 十二条 Core Invariants 的关系

当前可以看到一个明显收敛：

| V5.0 Core | 主要吸收的 V4.5 规则 |
|---|---|
| I1 Inference boundary | 2, 17, 38, 39 |
| I2 Official semantics first | 8–16（尤其 9–13）及 65–79 的部分迁移 |
| I3 Logical isolation | 4–7, 20, 25, 44 |
| I4 Physical reuse | 5–8, 41–43 |
| I5 Token fact | 9–14 |
| I6 Semantic compatibility | 8, 16, 43 |
| I7 State separation | 20, 30, 31, 32, 51, 76, 77 |
| I8 Resource boundary | 29, 52–63, 83–90（实现细节大量被 supersede） |
| I9 Lossless eviction | 45, 88 |
| I10 Cancellation safety | 22–24, 46, 62 |
| I11 Lifecycle convergence | 26–28, 91–99 |
| I12 Evidence before Core | 1, 33–37, 54–55, 63 |

> 该表是“语义吸收关系”，不是证明每一条旧规则都有独立实验支持。

## 5. 研究系统的下一步

到这里，V4.5 → V5.0 已经完成了第一轮**历史证据考古**。

下一阶段不宜继续增加历史映射表，而应该对四个仍开放的区域分别建立真正的 Research Question：

1. Execution Scheduler / Batch capability
2. Long-context resource repeatability
3. Tool protocol evolution under upstream changes
4. Lifecycle readiness beyond current eviction guard

每个问题都必须先定义：

`Unknown → Observation Object → Independent Channels → Falsification → Evidence → Finding`

而不是先设计代码。

## 6. 最终判断

当前 V5.0 的稳定性并不是来自“保留了 V4.5 的 99 条铁律”。

更准确的描述是：

> **V4.5 的 99 条规则经过真实工程、实验、审计和上游能力验证后，被压缩成更少的、实现无关的 Core Invariants；无法继续证明为 Core 的内容被降级为历史、实验或开放问题。**

这正是 Research / Knowledge Layer 建立后的第一项真正产出。
