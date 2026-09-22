# SimiGo-Lab Research Memory Layer

> High-value memory from long-term discussion, especially informal “题外话”, that may influence future SimiGo 2.0 architecture or research direction.
>
> This file is **not** the source of current project state. `RESEARCH_STATE.md` remains authoritative.

## 1. Purpose

Research is not only a sequence of experiments. Important architecture ideas can appear before a formal RQ exists.

This layer preserves only ideas with durable value:

```
题外话 / discussion
        ↓
important insight
        ↓
fork / hypothesis
        ↓
future definition
        ↓
RQ / evidence / architecture knowledge
```

Most conversation is intentionally excluded. A memory item belongs here only if losing it could make a future researcher misunderstand why SimiGo took a particular direction.

## 2. High-value memories

### RM-001 — Research is a branching tree

SimiGo-Lab should be understood as a research tree, not a linear roadmap.

A discussion can create several plausible branches. Some become experiments, some become dead ends, and some remain dormant.

The research tree therefore needs to preserve:
- the parent idea;
- the point of divergence;
- candidate branches;
- why a branch continued or stopped.

Git preserves the implementation/evidence history; this layer preserves the intellectual branching history.

**Status:** CANDIDATE / METHOD INSIGHT

### RM-002 — Model decomposition and sharding are first-class research objects

For a real large model, the unit used by SimiGo does not necessarily have to equal the model's semantic unit.

Potential boundaries include:
- layer/block;
- tensor/tensor slice;
- execution-state-associated object;
- independently resident/migrated object;
- group of objects with tightly coupled access behavior.

The important future question is not “which unit is convenient to instrument?”, but:

> What object has an independently meaningful residency, migration, execution-state, and cost identity?

This may determine how a model should be layered and sharded for SimiGo.

**Status:** CANDIDATE / NOT AN RQ

### RM-003 — Semantic hierarchy may differ from residency hierarchy

A model can have a semantic hierarchy such as:

```
model → layer → block → attention / MLP → tensor
```

SimiGo may need a different operational hierarchy:

```
model
  → residency unit
      → migration unit
          → execution-state unit
```

These two hierarchies may overlap, but they should not be assumed identical.

**Architectural significance:** if true, SimiGo can define its mechanism around runtime behavior rather than hard-coding the upstream model's conceptual decomposition.

**Status:** CANDIDATE / ARCHITECTURE HYPOTHESIS

### RM-004 — Can SimiGo work without upstream semantic dependency?

A particularly important long-horizon question:

> If the current residency / execution-state theory is correct, does SimiGo actually need upstream semantic knowledge?

Distinguish:

```
semantic-assisted
    “this is layer X / attention / MLP / expert”

versus

semantic-dependent
    “the mechanism cannot work without knowing that”
```

The stronger architecture would derive essential information from observable runtime behavior where possible:

```
access
residency
migration
reuse
execution continuity
```

Upstream semantics may remain useful, but they would not be architecturally mandatory.

If this hypothesis survives future validation, it would materially affect portability, model-family coupling, abstraction boundaries, and runtime integration.

**Status:** CANDIDATE / NOT AN RQ

### RM-005 — Access pattern may determine the useful unit

A key principle emerging from the abstract research is:

> useful granularity is determined by access pattern, not by strategy freedom.

The broader architectural hypothesis is that access/co-access behavior may be a more fundamental basis for residency and sharding boundaries than semantic labels.

This is not yet established for a real Swift/MLX runtime.

**Status:** HISTORICAL PRINCIPLE → FUTURE VALIDATION CANDIDATE

### RM-006 — Abstract theory must be separated from runtime embodiment

There is a distinct chain between an abstract mechanism and a real runtime mechanism:

```
abstract mechanism
      ↓
runtime representation
      ↓
runtime-observable state
      ↓
controllable mechanism
      ↓
measurable effect
```

A failure at one transition does not automatically invalidate the previous layer.

This prevents a common research error: treating “we can model it” and “the runtime exposes it in a controllable form” as the same claim.

**Status:** CANDIDATE / FUTURE RESEARCH DIRECTION

### RM-007 — “Unit discovery” precedes implementation choice

Before building a Swift/MLX implementation, the research should establish what the real counterpart of the abstract unit is.

Candidate real units may include:
- layer/block;
- tensor;
- tensor slice;
- allocator/memory region;
- execution-state-associated object;
- dynamically co-accessed group.

The unit should be selected because it has the relevant mechanism semantics, not because it gives the easiest instrumentation.

**Status:** CANDIDATE / PRE-DEFINITION

### RM-008 — Semantic independence is stronger than semantic availability

Upstream semantic information may be available and useful without being architecturally necessary.

The meaningful architectural distinction is:

```
semantic-assisted
        vs.
semantic-dependent
```

This distinction should remain visible in future architecture discussions.

**Status:** CANDIDATE / ARCHITECTURE HYPOTHESIS

### RM-009 — “题外话” can be an architecture-origin event

A casual discussion should normally disappear.

It should enter this memory layer only when it:
- changes a system boundary;
- reveals a hidden variable;
- proposes a fundamentally different decomposition;
- explains a possible dead end;
- creates a durable architecture hypothesis.

Thus this file is intentionally **curated**, not a transcript archive.

**Status:** PROCESS PRINCIPLE

### RM-010 — GitHub as an asynchronous multi-agent research bus

A useful architecture idea emerged from discussion between the local Agent and ChatGPT:

> GitHub can serve as a shared, versioned research dialogue bus between agents, rather than merely as a source-code repository.

The intended separation is:

```
Local Agent
  runtime / filesystem / Swift / MLX / experiments
        ↓
   Git commit / push
        ↓
GitHub research dialogue
        ↓
ChatGPT Agent
  research decomposition / review / boundary challenge
        ↓
   Git commit / push
        ↓
Local Agent
```

The important design principle is **not** to turn GitHub into an unstructured chat transcript. The dialogue should remain provenance-bearing and subordinate to project state:

```
dialogue
   ↓
review / decision
   ↓
explicit registration
   ↓
RESEARCH_STATE / endpoint
```

In particular:

- dialogue must never silently become project state;
- an Agent's proposal must not automatically become an RQ;
- a review must be distinguishable from a registered decision;
- Git history provides provenance, ordering, and recoverability;
- the shared bus can reduce manual copy/paste between local Agent and ChatGPT;
- the two Agents can retain different capability boundaries while collaborating through the same research tree.

Potential future layout:

```
docs/research_bus/
├── INDEX.md
├── inbox/
├── dialogue/
├── decisions/
└── archive/
```

This is an **architecture hypothesis / workflow idea only**. It does not authorize creation of the bus, creation of branches, runtime changes, or any research experiment. A future implementation should be justified independently and should preserve the existing distinction between conversation, decision, and authoritative state.

**Origin:** 2026-09-22 brainstorming between project owner, local Agent, and ChatGPT.

**Status:** CANDIDATE / ARCHITECTURE HYPOTHESIS / NOT AN RQ

### RM-018 — Compute-once / multiple-futures is the conceptual origin of Execution State

The central Architecture 2.0 insight was not simply “make long-context prefill faster”.

The stronger objective was:

> **Compute once, multiple futures.**

An expensive long-context computation should become a reusable, branchable, recoverable state from which multiple continuations can be derived.

This is the conceptual reason Execution State became a research object above raw KV storage. The durable distinction is:

```
one expensive computation
        ↓
reusable execution state
        ↓
fork / branch / continue / restore
        ↓
multiple futures
```

The idea predates the formal Track B evidence chain and should be treated as an architectural origin, not as evidence that the full runtime mechanism exists.

**Provenance:** curated from Architecture 2.0 session reconstruction, 2026-09-22; see `docs/07-history/ARCHITECTURE_2.0_SESSION_KNOWLEDGE_20260922.md`.

**Forbidden inference:** RM-018 does not prove that an equivalent mechanism is exposed by current Swift/MLX runtime APIs.

**Status:** DURABLE ARCHITECTURE ORIGIN / HYPOTHESIS

### RM-019 — Execution State is a semantic layer above raw KV storage

The early 2.0 reasoning deliberately separated:

```
KV bytes / storage representation
        ≠
execution identity + continuation semantics
```

Existing mechanisms such as checkpoint/restore, prefix reuse, and chunked prefill can manipulate state without necessarily exposing a first-class forkable execution identity.

Therefore future research should not use “we can copy or serialize the state” as a substitute for the stronger Execution State question.

**Provenance:** Architecture 2.0 session reconstruction, 2026-09-22.

**Forbidden inference:** this is not a claim that KV storage mechanisms are insufficient for every practical workload; it defines the stronger research abstraction being investigated.

**Status:** DURABLE CONCEPTUAL BOUNDARY

### RM-020 — Deduplicate before inventing

Architecture 2.0 deliberately moved upward in abstraction after comparing candidate work against existing open-source mechanisms.

The durable research rule is:

> Before treating a mechanism as a new SimiGo research contribution, establish whether the relevant lower layer is already solved or supplied upstream.

The intended boundary was approximately:

```
existing KV / attention / distributed primitives
        ↓
reuse rather than duplicate
        ↓
SimiGo research space
Execution State / residency / policy / planner
```

This is a research-efficiency principle, not a claim that upstream mechanisms are complete or optimal.

**Provenance:** Architecture 2.0 session reconstruction, 2026-09-22.

**Status:** DURABLE METHOD INSIGHT

### RM-021 — Architecture decomposition must respect physical resource boundaries

The early “split one large GPU computation into several application tasks” idea was retained as a useful negative lesson.

Creating more application tasks on a saturated single GPU does not by itself create additional hardware execution resources. Consequently, a decomposition proposal must identify the actual resource boundary it exploits:

- kernel-level decomposition → hardware execution / bandwidth question;
- multi-device decomposition → additional device resources;
- application-level splitting on the same saturated device → not automatically a new parallelism mechanism.

**Provenance:** Architecture 2.0 session reconstruction, 2026-09-22.

**Forbidden inference:** this does not prove every application-level decomposition is useless; it rejects the premise that task multiplication alone creates free parallel hardware.

**Status:** DURABLE METHOD / NEGATIVE KNOWLEDGE

### RM-022 — Mechanism existence must precede implementation authority

A recurring Architecture 2.0 correction was that an appealing implementation should not silently become a research commitment.

The intended order is:

```
mechanism hypothesis
        ↓
independence
        ↓
estimand / existence criterion
        ↓
discriminating observation
        ↓
evidence
        ↓
decision
        ↓
implementation authority
```

This is stronger than merely “do experiments before coding”: it protects the research program from turning an unverified architectural hypothesis into an implementation specification.

**Provenance:** Architecture 2.0 methodological evolution, curated 2026-09-22.

**Status:** DURABLE GOVERNANCE / METHOD INSIGHT

### RM-023 — The research object can move upward when lower-layer mechanisms are already available

The 2.0 discussions repeatedly shifted the question upward:

```
storage optimization
      ↓
execution-state semantics
      ↓
residency / observable boundaries
      ↓
runtime mechanism
```

This upward movement is not scope creep by itself. It can be the correct response when lower layers are already available and the unresolved systems question lies at a higher abstraction boundary.

**Provenance:** Architecture 2.0 session reconstruction, 2026-09-22.

**Status:** DURABLE RESEARCH-DIRECTION INSIGHT

## 3. Promotion rule

A memory item does not change project state.

If it later becomes important enough to study:

```
Memory ID
   ↓
Definition document
   ↓
RQ ID
   ↓
Evidence
   ↓
Endpoint / Closure
```

Never silently convert:
- hypothesis → fact;
- discussion → RQ;
- registered prediction → result;
- historical insight → current task.

## 4. Authority boundary

Current research state is determined by:

1. `docs/RESEARCH_STATE.md`
2. endpoint / closure documents
3. experiment ledgers and evidence
4. Git history

This file answers a different question:

> **What important ideas have emerged that may explain or shape the future architecture?**

It may inform future research-question definition, but it cannot open a research branch by itself.

## 5. Future structure

If this layer becomes large, split it into:

```
docs/research_memory/
├── INDEX.md
├── insights/
├── forks/
├── architecture_hypotheses/
└── dead_ends/
```

Stable RM IDs must survive any split so future Agents can reconstruct the intellectual tree.
