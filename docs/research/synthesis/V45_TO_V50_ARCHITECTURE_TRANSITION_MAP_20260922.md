# V4.5 → V5.0 架构转折证据图（2026-09-22）

> 这是历史证据整理，不是重新定义版本历史。目标是回答：SimiGo 为什么从 V4.5 的自有 Runtime 基础走到 V5.0 的 Official Semantics First。

## 1. 转折一：V4.5 建立稳定 Runtime 契约

V4.5 的核心价值不是某个单独优化，而是把以下问题固定为长期安全边界：

- Logical State Isolation
- Physical KV Correctness
- Physical Token Ledger
- Tool Fingerprint Safety
- Lifecycle Convergence
- Cancellation Safety
- Memory Admission Safety
- Observability
- Agent Runtime ≠ Inference Runtime

证据：
- docs/decisions/V4_5_STABLE_FOUNDATION_BASELINE.md
- docs/experiments/EVOLUTION_TRACK.md

研究意义：

> V4.5 解决的是“Runtime 自己必须守住什么”，而不是“Runtime 必须自己实现多少机制”。

## 2. 转折二：审计暴露自研机制与官方语义重叠

2026-09-09 起的审计线曾探索 AdmissionReservationLedger、BatchSequence、PhysicalKVContinuation、CancellationCommitToken 等本地机制。

后续审计发现，其中若干机制正在重新建立与官方 Runtime 相同的权威边界。

证据：
- docs/audit/POST_AUDIT_DELETION_RECORD_2026-09-11.md
- docs/lessons/AUDIT_SIMPLIFY_MIGRATION_LESSONS_2026-09-12.md

关键观察：

> “发现一个运行时问题”不自动意味着“需要新增一个本地状态系统”。

## 3. 转折三：官方 ChatSession 成为 Physical KV 语义权威

简化线切换到官方 mlx-swift-lm ChatSession 后，token ledger、prefix reconciliation、trim/rebuild、cache telemetry 等能力由官方层提供。

SimiGo 保留：
- Logical session continuity
- HTTP/OpenAI protocol mapping
- lifecycle/resource coordination
- observation

SimiGo 不再维护第二套 token-level Physical KV protocol。

证据：
- docs/experiments/OFFICIAL_CAPABILITY_MATRIX.md
- docs/knowledge/findings/FINDING_OFFICIAL_SESSION_OWNS_PHYSICAL_KV.md
- docs/knowledge/principles/PRINCIPLE_OFFICIAL_SEMANTICS_FIRST.md

## 4. 转折四：真实任务证明“边界正确性”比局部机制堆叠更重要

历史问题并非全部来自 Runtime 算法本身：

- OpenAI 字符串化 tool arguments 与官方 Codable 表示不一致，导致 prefix mismatch；
- session 在未完成 prefill 时被取消，可能留下不可安全复用的状态；
- tools:null 在 Foundation / ObjC 边界触发不可由 Swift try? 捕获的异常。

这些问题分别通过边界归一化、session readiness、最小类型守卫解决。

证据：
- docs/lessons/AUDIT_SIMPLIFY_MIGRATION_LESSONS_2026-09-12.md
- docs/lessons/cancel-mid-prefill-poisoned-session-2026-09-17.md
- docs/lessons/incident-app-crash-and-server-hang-2026-09-19.md

研究意义：

> Runtime 稳定性来自正确的责任边界，而不只是更多内部状态。

## 5. 转折五：Execution Fork 实验把“未来能力”与“当前职责”分开

F0 对 Execution Fork 的受控探针表明，当前公开 MLX/MLXLMCommon API 没有 sequence identity / shared-prefix primitive。

因此：
- 真共享 fork 不进入 Core；
- 磁盘 fork 保留为显式分支工作流；
- 不建立 KV Tree / BranchManager / ExecutionState 作为替代权威；
- 上游 capability gap 进入研究轨。

证据：
- docs/experiments/EXECUTION_FORK_F0_PROBE_20260918.md
- docs/experiments/EXECUTION_FORK_F0_PROBE_RESULTS_20260919.md
- docs/decisions/V15_ENDGAME_DECISION_20260919.md
- docs/research/questions/Q_FORK_AND_UPSTREAM_SEMANTICS_20260922.md

## 6. V5.0 的真正收敛

因此 V5.0 不是“V4.5 加更多 Runtime”。

更准确的演化关系是：

```
V4.5
稳定 Runtime 契约
    ↓
审计
发现局部机制与官方语义重叠
    ↓
简化 / 删除
    ↓
官方 ChatSession 成为 Physical KV 语义权威
    ↓
真实任务 + F0 验证剩余边界
    ↓
V5.0 Core Architecture Baseline
```

## 7. 当前仍开放的演进问题

V5.0 没有关闭所有性能问题，而是把它们放到了正确的位置：

- 官方 capability completion：当前可直接接入的官方能力；
- Execution Fork：等待 upstream sequence-sharing capability；
- S1 Batch：实验轨，不得绕过 Core 契约；
- S2 Prefix/Radix Cache：未来能力，不等同于当前 Physical KV authority；
- S3 Continuous Serving：在 S1/S2 证据成熟后再进入。

## 8. 核心历史结论

这条演化线最重要的变化不是代码数量减少，而是：

> **SimiGo 从“自己实现更多 Runtime 机制”转向“证明哪些机制应该由 SimiGo 拥有、哪些应该由上游拥有”。**

这也是 Research / Knowledge Layer 建立后，最值得长期保存的一条架构演化证据链。
