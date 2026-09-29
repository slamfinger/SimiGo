# PALACE-1 Phase B Opening Draft — Minimal Durable Unit

日期：2026-09-30  
状态：`PARTICIPANT_DRAFT / PHASE_B_NOT_OPEN / AWAITING_PHASE_A_REGISTRATION`  
前置：Phase A review = `PASS / REGISTRATION_REQUIRED`  
性质：proposal only；不是 registration，不是 Phase B activation

本文只准备 registration 后可立即评审的 Phase B opening。它不改变 Phase B 的
closed 状态，不选择 SQLite / KV / event log / remote，不实现 Palace database，
不实现 Llama adapter。

## 1. Proposed research question

> 在 Phase A 边界内，一个 Execution 的最小 durable semantic unit 是什么，才能在
> 进程退出、runtime binding 失效或 Physical Representation 不可用后恢复 execution
> semantics，而不把 Runtime Binding、Backend State 或 Physical Representation
> 错误提升为 Durable Semantic State？

The deliverable is an architecture contract question, not a storage schema.

## 2. Inputs inherited from Phase A

Inferred minimum D candidate:

```text
ExecutionStateHandle
├── id
├── lineage.root
├── lineage.parent
├── position
├── continuation.nextInput
├── continuation.continuationID
└── lifecycle
```

Mandatory review conditions:

1. durable identity allocation / tombstone policy;
2. continuation versus transcript equivalence;
3. representation content claim / validation policy;
4. durable binding relation separate from Execution State;
5. crash-consistency recovery semantics;
6. discarded-binding semantic guard.

## 3. Proposed subquestions

### B1 — Identity

What is the durable uniqueness rule for `ExecutionID`?

Must answer:

- can a discarded ID be reused;
- when may a tombstone be collected;
- what happens after restart on duplicate ID;
- whether lineage root/parent is part of identity or recoverable metadata.

### B2 — Continuation source

Is `continuation.nextInput` durable state, transcript-derived state, or a caller-
supplied delta?

If transcript becomes canonical, Phase B must prove semantic equivalence to the
current `ExecutionContinuation`; it must not silently reclassify `nextInput`.

### B3 — Evolution representation

Does semantic recovery require the full lifecycle event history, or only the latest
valid semantic snapshot plus selected lineage facts?

Must separate:

```text
minimum recovery state
≠ replay / observability history
≠ physical representation history
```

### B4 — Binding relation

If recovery needs to reattach a representation, what durable relation record is
required?

Must keep separate:

```text
ExecutionStateHandle          = D candidate
ExecutionRepresentationRef    = P locator / claim
Execution → Ref relation      = separate durable relation, only if needed
runtimeAddress / generation   = R or relation metadata
```

### B5 — Physical availability

For each recovered execution, what are the valid outcomes when its referenced
representation is:

```text
available and valid
available but invalid
missing
in flight / locked
corrupt
```

Each outcome must map to `reattach`, `recompute`, `unbound`, or explicit fail-closed.

### B6 — Crash consistency

What are the recovery rules for:

```text
D record written without relation
relation written without D record
representation written without claim
claim written without representation
tombstone written without physical release
physical release without tombstone
```

The draft deliberately does not define a transaction protocol or storage format.

### B7 — Discarded state

What does `discarded` mean across restart?

Must define whether it is:

```text
terminal tombstone
recoverable lifecycle state
 garbage-collectable identity reservation
 observability-only history
```

## 4. Explicit non-goals

```text
❌ storage technology selection
❌ Palace database schema
❌ persistence file format
❌ Llama adapter
❌ oversized special semantics
❌ performance benchmark
❌ full lineage history as minimum D
❌ promotion of KV / checkpoint / sidecar into Execution State
```

## 5. Acceptance criteria

Phase B may close its first audit only if it produces:

1. a named minimal durable unit at contract level;
2. a field-by-field `D / R / P / O / T` disposition;
3. an explicit identity and tombstone rule;
4. an explicit continuation-source decision or a bounded equivalence test plan;
5. a separate binding/relation decision;
6. a representation availability / corruption recovery matrix;
7. crash-window recovery semantics without storage selection;
8. a fail-closed test plan for every semantic mismatch.

## 6. Gate sequence

```text
Phase A review PASS
      ↓
explicit human/repository registration   ← current gate
      ↓
Phase B opening registration
      ↓
Phase B code-level audit
      ↓
external review
      ↓
explicit registration
```

Until the current gate is registered, this draft remains only a participant proposal.
