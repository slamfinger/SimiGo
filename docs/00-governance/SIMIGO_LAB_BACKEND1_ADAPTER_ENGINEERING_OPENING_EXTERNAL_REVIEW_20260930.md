# BACKEND-1 Adapter Engineering Opening — External Review

日期：2026-09-30
审查对象：
`docs/00-governance/SIMIGO_LAB_BACKEND1_ADAPTER_ENGINEERING_OPENING_DRAFT_20260930.md`
Draft commit：`25286585a414e715ac9ea8dddbedac2871509fa8`

状态：`EXTERNAL REVIEW COMPLETE`
Verdict：`PASS / ACTIVATION_REQUIRED`

## 1. Review basis

本审查以已登记的 Phase C seam audit 与 Phase B durable-state boundary 为前置事实，不把它们重新审计为本 gate 的研究对象。

已确认的输入边界：

```text
Phase A review          = PASS / REGISTERED
Phase B opening         = PASS / REGISTERED
Phase B boundary audit  = PASS / REGISTERED
Phase C opening         = PASS / REGISTERED
Phase C seam audit      = PASS / REGISTERED
BACKEND-1 adapter eng.  = NOT OPENED
```

Phase C 的最小 seam 输入为 E1 + E3 + B1；Phase C 的 61/61 evidence
只作为 structural evidence，不外推为 adapter production readiness。

## 2. Review result

### R1 — Research question is correctly constrained

PASS.

Draft 的核心问题是“已登记 seam 是否足以承载真实 adapter engineering”，
而不是“如何实现 Llama adapter”。这保持了：

```text
observed code fact
≠ inferred contract
≠ selected implementation
```

也避免把 Phase C 的 seam conclusion 直接转成 implementation authorization。

### R2 — Scope / non-scope boundary

PASS.

Draft 明确禁止：
- 未登记直接实现产品化 adapter；
- storage selection；
- persistence format / API / protocol design；
- artifact portability claim；
- performance claim；
- oversized-specific Execution State semantics。

这与既有 route redefinition 和 Phase C registration 一致。

### R3 — Semantic sovereignty

PASS，且应作为本 gate 的硬性验收条件。

Draft 正确要求 backend-specific identity/cache/artifact state 不得进入
D-level Execution State。若真实 adapter 要求修改 E1/E3/B1 的语义所有权，
必须停止，而不是在 adapter implementation 中静默扩展 contract。

### R4 — Representation boundary

PASS。

Draft 没有把 artifact portability 偷换成 semantic continuity，并保留：
capture / derive / restore / release、stale/foreign payload、rematerialization
与 recompute 等既有边界。

### R5 — Concurrency / cancellation

PASS，但需登记为 engineering-stage mandatory check。

G-2 / G-7 / G-9 仍未关闭。Draft 正确没有把它们假定为已解决，也没有
通过新增 API 预先修复。

### R6 — Default-path non-interference

PASS。

Draft 将默认路径要求限定为结构性检查，并把性能问题留给 RQ3，符合既有
Execution State efficiency principle。

### R7 — Stop conditions

PASS。

Stop conditions 足以阻止以下越界：
- backend 写语义状态；
- backend-specific state 晋升为 D；
- seam 不足却自行修改 contract；
- storage / persistence 扩张；
- performance / production-readiness 外推。

## 3. Required strengthening before registration

以下不是 blocker，但应随 registration 一并固化：

1. **真实 adapter 选择必须保持“验证载荷”性质。**
   本 gate 可以选择一个具体 backend 作为工程验证对象，但不得把该 backend
   的特性写成 Execution State 的一般语义。

2. **G-1 必须保持前置条件。**
   如果 engineering 产生 direct backend entry，不能依赖 coordinator 的
   当前 precondition 来证明 backend 自身 invariant；需要在 targeted evidence
   中明确入口是否存在以及 position guard 如何保持 fail-closed。

3. **L-1/G-5 不得在 adapter implementation 中顺手修复。**
   若 adapter 工程实际触及 PrefixSnapshotStore 的 MLXLMCommon public type，
   应单独记录为 engineering gap；不能把修复隐藏在 adapter commit 中。

4. **Phase B six conditions 继续作为 inherited conditions。**
   尤其 lineage/tombstone closure、representation content claim、
   separately typed binding relation、crash-window classification、
   concurrency / durable identity reservation，不得因 adapter 可运行而视为关闭。

5. **Evidence hierarchy must remain explicit.**
   ```text
   code fact
   → targeted adapter evidence
   → bounded engineering conclusion
   ≠ universal backend portability
   ≠ production readiness
   ≠ performance conclusion
   ```

## 4. Review verdict

```text
Opening Draft = PASS
Activation     = REQUIRED
Engineering    = NOT AUTHORIZED YET
```

本 review 允许进入下一决策点，但不是 repository registration。

只有显式 registration 后，BACKEND-1 adapter engineering 才能开始。

## 5. Registration recommendation

若登记，本 review 建议登记以下 gate state：

```text
BACKEND-1 adapter engineering opening = PASS / REGISTERED
Engineering                         = AUTHORIZED
Storage selection                   = NOT AUTHORIZED
Persistence format/API design       = NOT AUTHORIZED
Performance claim                   = NOT AUTHORIZED
Oversized-specific semantics        = NOT AUTHORIZED
G-1…G-10                            = INHERITED / NOT CLOSED
Phase B six conditions              = INHERITED / NOT CLOSED
```

如果不登记，研究状态应保持：

```text
BACKEND-1 adapter engineering = NOT OPENED
```

本审查本身不改变 gate state。
