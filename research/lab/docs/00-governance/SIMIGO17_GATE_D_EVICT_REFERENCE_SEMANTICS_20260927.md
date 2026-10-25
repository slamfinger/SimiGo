# Gate D — Eviction / Reference Semantics — Contract

**Date**: 2026-09-27 · **Status**: PASSED (reviewer ruling executed:
「evict-by-policy, retain-binding, per-execution rematerialization」—
no binding-count pin, no lease correctness, no LRU-decided Execution/
Binding lifecycle)

---

## D-I  Six invariants

```text
D-I1  Binding is a SEMANTIC reference, never Artifact ownership.
      Binding(P)+Binding(C) → Ref X  ≠  "Artifact X must persist".
      (Otherwise: Execution lives → Binding lives → Artifact pinned
      forever → pool LRU meaningless.)

D-I2  Multiple Execution Bindings do NOT prevent Artifact eviction.

D-I3  BindingCount is NOT a correctness condition for Artifact
      retention. 语义引用（Ref X 载 Binding(P)/Binding(C)——谁在语义上
      绑定）与 物理引用（residentHandle/load task/temporary reader——
      哪些物理操作尚未结束）是两个不同的问题，不得合并。

D-I4  PhysicalUseCount / transient protection (若存在) 只保护正在
      进行的物理操作；它不代表 Execution Binding 数量。
      BindingCount ≠ PhysicalUseCount。

D-I5  v1 introduces NO Lease as a correctness mechanism.（Lease 会引入
      创建者/TTL/renew/crash 过期/clock skew/GC/到期正在
      materialize/多进程续租等复杂度——未来可作为资源优化或跨进程
      协调机制，不进 v1 正确性契约。）

D-I6  After Artifact eviction: Bindings stay active; each Execution
      independently resolves its own state via Runtime Resolution /
      Representation Resolution (Gate C four states, no fifth state).
```

## D-R  Rules

```text
D-R1  Artifact reclamation must not modify, supersede, or detach any
      still-active Binding.
D-R2  If the Artifact is reclaimed, each Execution's Resolution State
      is determined INDEPENDENTLY by its own live materialization and
      Representation availability.
```

## Acceptance matrix (Ref X under Binding(P)+Binding(C))

| Artifact | P live | C live | Parent                     | Child                      |
| -------- | -----: | -----: | -------------------------- | -------------------------- |
| available | yes | yes | ATTACHED_LIVE              | ATTACHED_LIVE              |
| available | yes | no  | ATTACHED_LIVE              | REATTACHABLE               |
| available | no  | yes | REATTACHABLE               | ATTACHED_LIVE              |
| available | no  | no  | REATTACHABLE               | REATTACHABLE               |
| evicted   | yes | yes | ATTACHED_LIVE              | ATTACHED_LIVE              |
| evicted   | yes | no  | ATTACHED_LIVE              | REMATERIALIZATION_REQUIRED |
| evicted   | no  | yes | REMATERIALIZATION_REQUIRED | ATTACHED_LIVE              |
| evicted   | no  | no  | REMATERIALIZATION_REQUIRED | REMATERIALIZATION_REQUIRED |

**The matrix proves: Artifact eviction is a Representation Availability
change — NOT an Execution State change.**

## Pin / Lease positions

```text
Binding → permanent pin                      NO
Binding refcount decides eviction            NO
Artifact eviction → Binding stays active     YES
Per-execution live-materialization judgment  YES
Transient protection during physical reads   allowed (D-I4)
Lease                                        not in correctness contract
Pin as future optimization                   allowed
COW page-level pin                           FORK-3 v1 no
```

**Pin 可以优化，不可以定义正确性。** Even if a future adaptive pin
fails: Ref evicted → Binding still valid → REMATERIALIZATION_REQUIRED —
the system remains semantically correct.

## Four lifetimes, formally separate

```text
Execution lifetime ≠ Binding lifetime ≠ Artifact lifetime ≠
Live materialization lifetime
```

## OPEN — Gate D concurrency boundary (next sub-gate)

Three races to contract before implementation boundary:

```text
1. eviction racing materialize(Ref X)     — who owns artifact
  protection during the read (D-I4 transient handle semantics)
2. last live materialization disappearing — availability flip
  timing and observation point
3. two Executions rematerializing the same Ref concurrently —
  artifact protection AND dedup (single materialization, both bind)
```
