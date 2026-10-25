# Implementation Planning — FORK-3 Infrastructure — Layer Assignments

**Date**: 2026-09-27 · **Status**: PLANNING_REGISTERED (architecture
layering ruling; no code this gate — first implementation cut defined
at §3)

---

## 1. The three questions, ruled

```text
Q1 PhysicalUseCount  → RepresentationResolver / ArtifactStore 的物理
                       句柄层（PhysicalUseHandle）。不进 Binding
                       （语义引用），不由 Pool 管理语义（驻留策略）。
                       BindingCount / PhysicalUseCount / Pool residency
                       三者继续独立。
Q2 single-flight     → MaterializationCoordinator：Ref → in-flight
                       MaterializationWork。工作本身创建并持有
                       PhysicalUseHandle（C.6：caller 范围 acquire/
                       release 会让 joiner/异步生命周期逃出保护）。
                       生命周期：create work → acquire physical use →
                       load/validate/materialize → publish candidate →
                       release physical use → remove in-flight work。
                       single-flight 成功 ≠ 双方自动 ATTACHED_LIVE——
                       各 Execution 独立走 attachment/commit 边界。
Q3 PrefixSnapshotStore → 保持已通过的 P2 生命周期语义，FORK-3 只增加
                       一个条件：eviction candidate →
                       PhysicalUseCount == 0 ? no → defer /
                       yes → 既有 onEvict 路径。**不修改
                       onEvict → delete artifact 的既有语义**。work
                       complete → release handle → artifact 重新具备
                       eviction eligibility（而非重新 admission、不改
                       Binding、不改 LRU）。
```

## 2. Five-layer boundary (final)

```text
Binding Registry                 ExecutionID → Binding → Ref
RepresentationResolver           available() / resolution
MaterializationCoordinator       Ref-scoped single-flight ·
                                 MaterializationWork · PhysicalUseHandle
ExecutionStatePrefixPool         admission / LRU / eviction candidate /
                                 registration
PrefixSnapshotStore/ArtifactStore artifact read / delete / rescan
```

**Hard constraint**: FORK-3 does not change the passed P2 eviction
persistence loop — it only ADDS the transient physical-use protection
boundary to eviction.

## 3. First implementation cut (sequencing ruling)

```text
第一刀不是改 forkSessionBranch()。

第一刀 = MaterializationCoordinator / PhysicalUseHandle 最小骨架，
tests-first，并发测试先行：

  T-a  materialize(X) × eviction(X)      （保护/延迟语义）
  T-b  materialize(X) × materialize(X)   （single-flight 去重）
  T-c  materialize(X) × restart/rescan   （P2 语义不回归）

这三项通过后，才接 Parent/Child → 同一 Ref X 的 Binding。
FORK-3 实现不把三个尚未验证的问题一次性耦合。
```

## 4. Deferred to later cuts

- Parent/Child Binding wiring (after infrastructure passes)
- forkSessionBranch API plug-in decision (LAST, per the preserved
  ordering)
- usage projection into GenerationUsageReport; disk GC policy;
  upstream sync (mlx-swift-lm main line)
