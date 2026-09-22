# Execution State — Future Mechanism Candidates

**Date:** 2026-09-22  
**Nature:** durable future-architecture memory / candidate mechanism map  
**Authority:** hypothesis only; does not open an RQ, authorize implementation, or change current research state  
**Scope:** SimiGo-Lab / SimiGo 2.0

> This document records long-horizon mechanisms from Architecture 2.0 discussion that should not be lost when the original conversation is gone. They remain candidate mechanisms rather than implementation requirements.

## 1. The broader future question

The long-term Execution State problem may extend beyond whether an already-computed state can be forked, continued, restored, and shared.

> **Can the runtime make large-model intelligence operationally resident, movable, and reusable without requiring the whole model or whole semantic hierarchy to be simultaneously resident in physical memory?**

Conceptually: large model / context → operational units → only currently required state enters physical memory → other state remains represented and recoverable → migration + reuse + continuation → coherent Execution State.

## 2. Candidate A — Execution State without upstream semantic dependency

Future hypothesis: the essential Execution State mechanism should, where possible, operate without depending on upstream model semantics.

Distinguish semantic-assisted (upstream tells us layer/block/attention/MLP/expert) from semantic-dependent (the mechanism cannot function without those labels).

The stronger target would derive essential runtime information from access, co-access, residency, migration, reuse, execution continuity, and cost. Upstream semantics may remain optional hints.

If validated, this could reduce coupling to a model family, upstream repository, semantic naming scheme, or fixed layer hierarchy.

Not established: no current evidence proves a production Swift/MLX Execution State mechanism can operate with zero upstream semantic dependency.

## 3. Candidate B — Model sharding as operational decomposition

The model's semantic hierarchy and the runtime's useful management hierarchy may differ.

Semantic hierarchy: model → layer → block → attention / MLP → tensor.

Possible operational hierarchy: model → residency unit → migration unit → execution-state unit.

The candidate mechanism is therefore not simply “shard by layer”. It is to discover a unit with independently meaningful access, residency, migration, continuation, and cost identity, then use that unit as the basis for runtime sharding.

Candidate units include layer/block, tensor, tensor slice, state-associated object, memory region, or dynamically co-accessed group.

## 4. Candidate C — Layering that follows access rather than semantics

A deeper sharding mechanism could derive dynamic or semi-static grouping from runtime access/co-access behavior:

access / co-access → grouping → residency boundary → migration boundary → Execution State boundary.

Semantic layers describe what the model means; operational layers describe what the runtime needs to move and keep resident. Whether these can be safely separated is unproven.

## 5. Candidate D — Minimize intelligence resident in physical memory

A particularly important long-horizon idea is to stop treating “the model” as something that must exist in physical memory as one continuously resident object.

> **Only the intelligence required by the current execution frontier should need to be physically resident at a given time.**

This is stronger than ordinary memory optimization. The target is to preserve useful computation and model capability while reducing the simultaneously resident physical working set.

Possible mechanisms include demand-driven materialization, residency windows, access-driven prefetch, eviction with recoverability, shared historical state, model-slice migration, and execution-state-aware working-set management.

These are candidates, not selected techniques.

## 6. Candidate E — Execution State bridges sharding and residency

The candidates become more coherent if Execution State is the object that survives movement.

Model decomposition → operational units → residency/migration → Execution State → continuation identity.

Key hypothesis:

> A unit should not merely be loadable/unloadable; it should remain meaningful to an ongoing execution state while its physical residency changes.

This suggests a distinction between logical state identity and current physical residency. A logically active state may be resident, shared, migrated, materialized, temporarily non-resident, or restored.

Whether the target runtime can expose and control this distinction is open.

## 7. Candidate F — Intelligence virtualization

The broader direction can be viewed as a possible execution-aware intelligence virtualization layer:

Logical Model / Execution State → operational units → residency manager → physical-memory working set → compute / continue.

> **The logical amount of model intelligence available to the execution could exceed the simultaneously resident physical representation, provided identity, correctness, and migration cost remain controlled.**

This is not equivalent to ordinary OS swap or virtual memory. The desired mechanism would be execution-aware and would understand continuity and movement cost.

## 8. Critical future dependency chain

Execution State existence → runtime-observable boundary → operational unit discovery → semantic-independence test → residency/migration control → model sharding → working-set minimization → large logical model over smaller physical residency.

The order matters. A future Agent must not jump directly from “we want less memory” to a sharding implementation. Runtime object and unit semantics need to be established first.

## 9. What must not be assumed

These candidates do not establish that layer-level or tensor-level sharding is correct, that access clustering is stable, that semantic-independent control is possible, that non-resident state can resume without semantic loss, that migration overhead is acceptable, that physical memory can be reduced without extra compute/latency, that a particular MLX/Swift API exposes the required control, or that “intelligence virtualization” is the final architecture.

## 10. Relation to current research state

This document is memory and architecture-hypothesis only. It does not register RQ-F-01, start STEP ⑤, authorize Swift/MLX implementation or data collection, reopen Track B/E, or promote Architecture 2.0 into production architecture.

The authoritative state remains `docs/RESEARCH_STATE.md`.

## 11. Why this must survive in durable memory

If these ideas disappear with the original conversation, a future Agent may incorrectly reduce the long-term goal to “implement COW KV”.

The broader direction is: COW / forkable Execution State → runtime-independent operational unit → semantic-light or semantic-independent control → model sharding/layering → minimum necessary physical residency → large logical intelligence on constrained physical memory.

The individual mechanisms remain hypotheses; the intellectual direction should remain recoverable.