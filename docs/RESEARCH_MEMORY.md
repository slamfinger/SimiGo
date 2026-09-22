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

### RM-024 — Execution State should ideally be semantically light

A long-horizon Architecture 2.0 hypothesis is that the core Execution State mechanism should not require upstream model semantics to function. Semantic metadata may assist optimization, but the mechanism should ideally derive essential control from observable runtime behavior such as access, co-access, residency, migration, reuse, and continuation.

**Provenance:** Architecture 2.0 future-mechanism discussion, curated 2026-09-22.

**Forbidden inference:** semantic-independent runtime control has not been demonstrated in current Swift/MLX.

**Status:** FUTURE ARCHITECTURE HYPOTHESIS / NOT AN RQ

### RM-025 — Operational sharding unit may differ from model semantic unit

Future SimiGo sharding should not assume layer/block/tensor is automatically the correct unit. A candidate unit should have meaningful access, residency, migration, continuation, and cost identity. Unit discovery therefore precedes sharding implementation.

**Provenance:** Architecture 2.0 model-decomposition discussion, curated 2026-09-22.

**Status:** FUTURE ARCHITECTURE HYPOTHESIS / NOT AN RQ

### RM-026 — Physical residency should be separated from logical intelligence state

A long-term mechanism candidate is to let the logical model / Execution State exceed the simultaneously resident physical representation, with execution-aware materialization, migration, eviction, and restoration. The target is not ordinary swap; it is preservation of execution identity and useful capability while minimizing the active physical working set.

**Provenance:** Architecture 2.0 future-mechanism discussion, curated 2026-09-22.

**Forbidden inference:** this does not establish that arbitrary model slices can currently be made non-resident and resumed safely or efficiently.

**Status:** FUTURE ARCHITECTURE HYPOTHESIS / NOT AN RQ

### RM-027 — Execution State can be the bridge between sharding and residency

A stronger future architecture would treat Execution State as the logical object that survives physical movement. Thus load/unload is not sufficient: a unit should remain semantically associated with an ongoing execution while its physical residency changes.

**Provenance:** Architecture 2.0 future-mechanism discussion, curated 2026-09-22.

**Status:** FUTURE ARCHITECTURE HYPOTHESIS / NOT AN RQ

### RM-028 — “Intelligence virtualization” is a candidate long-horizon direction

The combined hypothesis is: logical model / Execution State → operational units → residency manager → physical-memory working set → compute/continue. The aim is to make the logical amount of usable model intelligence potentially exceed the simultaneously resident physical representation, subject to correctness and migration-cost constraints.

This is a conceptual direction, not a named implementation architecture.

**Provenance:** Architecture 2.0 future-mechanism discussion, curated 2026-09-22.

**Status:** FUTURE ARCHITECTURE HYPOTHESIS / NOT AN RQ


### RM-029 — Intelligence is not identical to its physical carrier

A long-horizon abstraction separates:

model semantics ≠ logical executable state ≠ physical resident representation.

Physical memory is a temporary computational carrier, not intelligence itself. This distinction allows future research to ask what must be resident for a given execution frontier rather than treating the entire logical model as permanently resident.

**Provenance:** Architecture 2.0 Long-Horizon Vision, 2026-09-22.
**Forbidden inference:** this does not prove arbitrary model state can be non-resident while preserving execution.
**Status:** DURABLE ARCHITECTURE HYPOTHESIS

### RM-030 — Memory Manager may need to become Execution Manager

A future runtime may need to manage not only bytes and ownership, but execution state, residency, migration, reuse, continuation, and lifecycle.

The conceptual shift is: memory management → execution-aware resource management.

The significance is a possible change in the control boundary, not a requirement to create a class named ExecutionManager.

**Provenance:** Architecture 2.0 Long-Horizon Vision, 2026-09-22.
**Status:** FUTURE ARCHITECTURE HYPOTHESIS / NOT AN RQ

### RM-031 — Residency is a state, not merely an operation

load/unload is too weak as a long-horizon abstraction. An execution unit may be non-resident, materializing, resident, shared/partial, migrating, evicting, or recoverable while retaining logical identity.

Therefore residency may need state-machine semantics rather than isolated memory operations.

**Provenance:** Architecture 2.0 Long-Horizon Vision, 2026-09-22.
**Status:** FUTURE ARCHITECTURE HYPOTHESIS / NOT AN RQ

### RM-032 — Residency should ideally be predictive

A stronger future mechanism is: execution frontier → future access/co-access estimate → working-set prediction → residency planning → materialize/migrate/evict.

The objective is to prepare physical residency for upcoming execution rather than reacting only after memory pressure occurs.

**Forbidden inference:** prediction quality, instrumentation cost, and migration economics remain unvalidated.
**Provenance:** Architecture 2.0 Long-Horizon Vision, 2026-09-22.
**Status:** FUTURE ARCHITECTURE HYPOTHESIS / NOT AN RQ

### RM-033 — Planner may unify Execution State, Residency, and Compute

A long-horizon Architecture 2.0 architecture may place a Planner above three coupled concerns: Execution State, Residency/Memory, and Compute.

The Planner would reason about what execution units are needed, what should be resident, what can be reused/forked, and what computation should occur or be deferred.

**Provenance:** Architecture 2.0 Long-Horizon Vision, 2026-09-22.
**Forbidden inference:** this is not authorization for the current Runtime2 skeleton to implement a Planner.
**Status:** FUTURE ARCHITECTURE HYPOTHESIS / NOT AN RQ

### RM-034 — Runtime Sharding can be behavior-derived

Traditional sharding often starts from deployment-time semantic structure. A future runtime may instead derive operational groups from access/co-access behavior: access graph → co-access groups → operational units → dynamic residency/migration groups.

Thus sharding may be a runtime consequence of execution behavior rather than only a static model-deployment decision.

**Provenance:** Architecture 2.0 Long-Horizon Vision, 2026-09-22.
**Status:** FUTURE ARCHITECTURE HYPOTHESIS / NOT AN RQ

### RM-035 — Execution-State Sharding may be more fundamental than Model Sharding

The object worth independently managing may be a decomposable part of Execution State rather than a model tensor or layer.

Candidate boundaries include continuation, access, residency, migration, sharing/COW, and recomputation dependencies.

This extends the earlier unit-discovery principle from model structure to execution structure.

**Provenance:** Architecture 2.0 Long-Horizon Vision, 2026-09-22.
**Status:** FUTURE ARCHITECTURE HYPOTHESIS / NOT AN RQ

### RM-036 — A computation result can be a reusable execution asset

An expensive computation can be treated as producing an asset with a lifecycle: Create → Reuse → Fork → Continue → Migrate → Materialize → Evict → Restore → Discard.

This reframes execution state from passive cache data into a managed resource whose future value can be preserved or discarded.

**Forbidden inference:** Track B only establishes a bounded tested lifecycle; it does not validate every operation in this long-horizon chain for production runtimes.
**Provenance:** Architecture 2.0 Long-Horizon Vision, 2026-09-22.
**Status:** FUTURE ARCHITECTURE HYPOTHESIS

### RM-037 — Fork is one lifecycle operation, not the final abstraction

The durable abstraction should not terminate at state → fork. A reusable Execution State may need create, continue, fork, share, migrate, materialize, evict, restore, and discard semantics.

The deeper research question is lifecycle preservation of identity, continuation, mobility, and resource manageability.

**Provenance:** Architecture 2.0 Long-Horizon Vision, 2026-09-22.
**Status:** FUTURE ARCHITECTURE HYPOTHESIS / NOT AN RQ

### RM-038 — Optimize for minimum sufficient working set, not minimum memory

The long-horizon target is not simply min(memory), but a working set sufficient for correctness and useful execution while accounting for latency, migration, recomputation, safety, and concurrency costs.

Conceptually: minimum sufficient working set.

This turns residency from a memory-saving trick into an execution-planning problem.

**Provenance:** Architecture 2.0 Long-Horizon Vision, 2026-09-22.
**Status:** FUTURE ARCHITECTURE HYPOTHESIS / NOT AN RQ

### RM-039 — The research object must not be defined by the current upstream API

The absence of a concept from a current MLX/Swift API does not establish that the concept does not exist at the system level.

The intended order remains: theoretical object → runtime-observable boundary → existence criterion → independent observation → implementation path.

This prevents current API boundaries from silently becoming the definition of the research object.

**Provenance:** Architecture 2.0 Long-Horizon Vision and prior source/runtime boundary work, 2026-09-22.
**Status:** DURABLE RESEARCH-METHOD INSIGHT
### RM-040 — Experiments are local tests of higher-level ideas

A concrete experiment should be understood as a bounded observation generated by a higher-level structural idea or research question.

The durable relationship is:

```
idea / structure
      ↓
testable question
      ↓
experiment
      ↓
local evidence
      ↓
update to the parent understanding
```

An experiment result is therefore not identical to the idea it tests, and a failed implementation path does not automatically invalidate the parent conceptual object.

**Provenance:** Architecture 2.0 / SimiGo-Lab methodology discussion, 2026-09-22; formalized in `docs/00-governance/IDEA_TO_EXPERIMENT_CONTINUITY_MODEL_20260922.md`.

**Status:** DURABLE RESEARCH-METHOD INSIGHT

### RM-041 — The archive must preserve the idea–experiment linkage

Remembering experiment names and results is insufficient. Each important experiment should be recoverable as an answer to:

- which durable idea motivated it;
- which bounded question it tested;
- what observation could distinguish the claim;
- what the result changed;
- what the result did not establish.

This linkage is the continuity mechanism between intellectual history and empirical history.

**Provenance:** SimiGo-Lab archive design discussion, 2026-09-22.

**Status:** DURABLE ARCHIVE PRINCIPLE

### RM-042 — Evidence updates ideas locally, not globally

Evidence should update only the structural claim and scope that it actually observes.

The intended relationship is bidirectional:

```
idea → question → experiment → evidence
                         ↓
                 local model update
```

A positive result does not validate every consequence of the parent idea; a negative result does not automatically erase the parent concept. The archive must preserve scope, branch, and forbidden inference.

**Provenance:** SimiGo-Lab methodology discussion, 2026-09-22.

**Status:** DURABLE RESEARCH-METHOD INSIGHT

### RM-043 — Agent continuity depends on the intellectual tree, not only the experiment ledger

A new Agent should be able to reconstruct not merely “what was tested”, but:

```
why it was tested
what idea it belonged to
which branch it represented
what was learned
what remains hypothetical
what is closed
what may legally happen next
```

Therefore `RESEARCH_MEMORY`, governance registers, evidence/decision records, and `RESEARCH_STATE` form a connected memory system rather than independent document collections.

**Provenance:** Multi-Agent memory and archive design discussion, 2026-09-22.

**Status:** DURABLE MULTI-AGENT MEMORY PRINCIPLE

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
