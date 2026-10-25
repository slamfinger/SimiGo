# BACKEND-1 Adapter Engineering Opening Draft

日期：2026-09-30
状态：`DRAFT / EXTERNAL_REVIEW_PENDING`
前置 gate：Phase C seam audit = `PASS / REGISTERED`
基线：`afdf30fc9326fabaa9dab3cbb7e2f605ce782e75`

## 1. Opening purpose

本 gate 不是 Phase C seam audit 的自动延伸，也不是 Llama adapter 实现授权。

唯一研究问题：

> **Phase C 已登记的 E1 + E3 + B1 seam，是否足以承载一个真实 backend adapter 的工程实现，而不把 backend-specific state、representation detail 或 physical lifecycle 重新提升为 Execution Semantic State？**

验证对象是“工程边界是否足够”，不是预先选择 adapter API、协议、存储格式或实现方案。

## 2. Entry facts

Phase C 已登记的最小 seam：

```text
E1  ExecutionContinuityRuntime
    Runtime-owned semantic lifecycle

E3  ExecutionStateBackend
    Backend-owned representation strategy
    opaque ExecutionRepresentationPayload

B1  RuntimeResidencyBackend
    physical materialization / memory accounting boundary
```

已登记证据：
- Phase C targeted structural evidence = 61/61 PASS；
- 三种异构 backend 通过同一 conformance battery；
- semantic layer zero MLX leakage；
- cross-backend semantic continuity 在已测条件内成立；
- representation 侧允许 reattach / rematerializationRequired / recompute 等显式降级。

这些是本 gate 的输入事实，不是 adapter 实现授权。

## 3. Primary audit questions

### A1 — Boundary sufficiency

真实 adapter 所需的最小职责是否能够完全落在 E3/B1，而不要求修改 E1 的语义所有权？

### A2 — Backend-specific state containment

backend-specific state 是否能够保持在 R/P/T 边界内，包括：
- native session / cache；
- backend model identity；
- representation artifact；
- runtime address；
- backend-specific continuation machinery。

任何必须进入 ExecutionStateHandle 的 backend-specific field 都必须被视为 boundary failure，而不是立即修改 contract。

### A3 — Representation lifecycle

capture / derive / restore / release 是否足以覆盖真实 adapter 的 representation 生命周期？

重点检查：
- position ownership；
- stale representation；
- foreign payload；
- lifecycle / discard；
- resource release；
- rematerialization / recompute；
- artifact compatibility 与 semantic continuity 的分离。

### A4 — Capability boundary

backend capability 差异是否可以通过既有显式结果与策略边界表达，而无需把 capability state 写入 D-level Execution State？

### A5 — Cancellation / failure / concurrency

真实 adapter 所需的 cancellation、failure propagation、release ordering、concurrency 是否能够在现有 seam 外围解决？

重点继承 Phase B condition-6 与 Phase C G-2/G-7/G-9；若必须修改 E1/E3/B1，必须停止并重新提出 contract-level gate。

### A6 — Sync / async

真实 backend 的异步物理操作是否可以保持在 seam 外，而语义 commit ordering 仍满足既有因果约束？

不以本 gate 建立性能结论。

### A7 — Default-path non-interference

adapter engineering 是否能够以 backend-specific implementation isolation 的方式进行，而不向稳定 MLX/default path 注入固定 per-token/per-step bookkeeping？

这里只验证结构性边界；性能测量仍属于 RQ3。

### A8 — Semantic continuity

在真实 adapter 工程条件下，backend replacement 是否保持：
```text
id / lineage / position / continuation / lifecycle
```
的 Runtime sovereignty，并把 representation 差异显式化，而不是静默改变 Execution semantics？

## 4. Required engineering-boundary answer

本 gate 最终必须给出三分法：

```text
SUFFICIENT
  现有 E1/E3/B1 可承载 adapter engineering，
  不需要提升 backend-specific state 到 D。

INSUFFICIENT-BUT-LOCAL
  seam 存在局部工程缺口，但缺口可在 R/P/T 层解决，
  不改变 Execution semantic contract。

CONTRACT-BLOCKED
  真实 adapter 必须修改 E1/E3/B1 的语义所有权或 D-level state；
  此时 adapter implementation STOP，不得自行改 contract。
```

上述是分类，不是评分或优劣排序。

## 5. Evidence boundary

允许：
- code-level adapter boundary audit；
- 最小真实 backend integration skeleton 的必要性分析；
- targeted structural tests；
- failure / cancellation / release path validation；
- conformance evidence；
- default-path structural inspection。

在本 gate 明确禁止：
- 未登记前直接实现产品化 Llama adapter；
- storage engine / SQLite / KV / event log / remote service 选型；
- persistence format / API / protocol signature design；
- artifact portability claim；
- performance benchmark 或 latency conclusion；
- oversized-specific Execution State semantics；
- 把 Phase C 的 61/61 structural evidence 外推为 production readiness。

## 6. Inherited conditions and gaps

必须继承：
- Phase B six mandatory conditions；
- Phase C four review-strengthening points；
- G-1 … G-10 全部登记状态。

特别处理：
- G-1 oversized derive position guard：若 adapter engineering 引入 direct backend entry，必须先证明该入口不绕过 position invariant；不得静默依赖 coordinator precondition。
- G-2 coordinator locking；
- G-5/L-1 PrefixSnapshotStore MLX type leakage；
- G-7 durable ExecutionID allocation；
- G-9 cancellation contract surface；
- G-10 durable store。

这些 gaps 在本 opening 中不是关闭项。

## 7. Stop conditions

任一条件成立即 STOP：

1. adapter requires backend write access to ExecutionStateHandle semantics；
2. backend-specific identity / cache / artifact state must enter D-level state；
3. existing E3/B1 contract cannot express representation lifecycle without semantic reinterpretation；
4. cancellation or concurrency requires silent contract change；
5. artifact portability is being used as a substitute for semantic continuity;
6. evidence requires performance or production-readiness extrapolation;
7. implementation scope expands into storage or persistence-format selection.

STOP 后只允许提出新的 contract/architecture gate，不得在本 gate 内自行修复边界。

## 8. Proposed gate sequence

```text
Opening Draft
  ↓
External Review
  ↓
Explicit Registration
  ↓
Engineering
  ↓
Targeted Evidence
  ↓
External Review
  ↓
Registration
```

当前文档只完成 Opening Draft。External Review 尚未视为 registration；本 gate 仍不可进入 Engineering。

## 9. Registration boundary

只有显式登记本 opening review PASS 后，才允许进入 Engineering。

Registration 必须明确：
- 本 gate 的 research question；
- allowed / prohibited scope；
- inherited conditions；
- stop conditions；
- 是否允许进入具体 adapter engineering；
- 若 seam 不足，是否转入独立 contract gate。

在 registration 之前，不修改稳定 seam，不实现 adapter。
