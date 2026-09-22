# SimiGo-Lab Research Memory Layer

> Purpose: preserve high-value research insights, architectural hypotheses, forks, and long-horizon questions that emerge during discussion before they become formal research questions or conclusions.
>
> This document is not an authority for current research state. RESEARCH_STATE.md remains authoritative for state, RQ status, gates, and legal next actions.

## 1. Why this layer exists

Long-term research does not grow as a linear sequence of experiments. Important architectural directions can emerge in informal discussion, including “题外话”, then later become research questions, design constraints, or architecture principles.

The memory layer preserves the origin and evolution of those ideas without prematurely promoting them to facts.

Core lifecycle:

discussion / 题外话
        ↓
insight
        ↓
fork / candidate direction
        ↓
research definition
        ↓
registered RQ
        ↓
evidence
        ↓
architecture knowledge

Most ideas should terminate before reaching an RQ. Termination is a valid research outcome.

## 2. Memory types

### 2.1 Insight

A useful observation or conceptual connection that may matter later.

Status:
- HISTORICAL
- CANDIDATE
- PROMOTED
- SUPERSEDED

An insight is not a conclusion merely because it is recorded here.

### 2.2 Fork

A point where one research line produced multiple plausible directions.

A fork records:
- parent question/context;
- trigger;
- candidate branches;
- why each branch was considered;
- later disposition.

A branch may become an RQ, remain dormant, or become a dead end.

### 2.3 Architecture hypothesis

A hypothesis about how SimiGo 2.0 could be structured.

Examples include:
- model decomposition / layering;
- model sharding and residency boundaries;
- whether useful residency units can be defined from access patterns rather than upstream semantic labels;
- whether a mechanism can operate without depending on upstream semantic information;
- whether the current architecture theory remains valid when translated from the abstract model into a real runtime.

These are hypotheses until independently defined and evidenced.

### 2.4 Dead end

A direction that was investigated or considered and later rejected, closed, or rendered unnecessary.

Dead ends are retained because they explain why later architecture does not follow an apparently obvious route.

## 3. Initial high-value memory candidates

### RM-001 — Research itself is a branching system

The SimiGo-Lab research process should be understood as a tree rather than a linear roadmap.

Execution-state fork/branch semantics provide a useful conceptual analogy: a research discussion can fork into multiple possible futures, while only some branches become formal research.

Implication:
- Git commits preserve evidence and implementation history.
- The research-memory layer preserves the intellectual branching history.
- Closed/dead branches should remain discoverable rather than silently disappearing.

Status: CANDIDATE / ARCHITECTURE-METHOD INSIGHT

### RM-002 — Model decomposition and sharding are themselves research objects

A future SimiGo 2.0 investigation may need to ask how a large model is divided into meaningful residency / migration / execution units.

Candidate dimensions include:
- layer/block-level decomposition;
- tensor or tensor-slice decomposition;
- groups of objects sharing an access pattern;
- units induced by runtime residency rather than by upstream model semantics;
- sharding boundaries and their effect on migration/cost.

This is deliberately not a proposed implementation.

The research question must first establish what constitutes an independently meaningful unit in the target runtime.

Status: CANDIDATE / NOT AN RQ

### RM-003 — Can the architecture operate without upstream semantic dependency?

A long-horizon architectural hypothesis:

If the current residency / execution-state theory is correct, can the mechanism derive the information it needs from observable execution/access behavior rather than requiring semantic knowledge supplied by the upstream model/runtime?

Potential distinction:

Upstream semantic dependency
    ↓
“this object is layer X / attention / MLP / expert ...”

versus

Runtime-observable dependency
    ↓
“this unit was accessed / resident / migrated / reused ...”

The important question is not whether upstream semantics are useful. They may be.

The question is whether they are architecturally necessary.

If the mechanism can remain effective without upstream semantic labels, that would materially affect:
- portability;
- coupling between model/runtime and residency system;
- support for different model families;
- abstraction boundaries;
- feasibility of independent runtime integration.

This is a hypothesis only. No conclusion is registered.

Status: CANDIDATE / NOT AN RQ

### RM-004 — Access pattern may be a more fundamental boundary than semantic identity

Existing research established an important methodological principle in the current abstract model:

useful granularity is determined by access pattern, not by strategy freedom.

This memory item records the broader architectural possibility that the same principle may define model decomposition and sharding boundaries in a real runtime.

It must not be treated as a proven real-runtime result.

Status: HISTORICAL PRINCIPLE → FUTURE VALIDATION CANDIDATE

### RM-005 — Abstract theory versus runtime embodiment

The current abstract research has established mechanisms in a controlled model. A separate future question is whether those mechanisms have observable counterparts in real Swift/MLX execution.

This creates an explicit distinction:

abstract mechanism
      ↓
runtime representation
      ↓
runtime-observable state
      ↓
controllable mechanism
      ↓
measurable effect

Failure at any transition is informative and does not automatically invalidate the upstream abstract result.

Status: CANDIDATE / FUTURE RESEARCH DIRECTION

## 4. Promotion rules

A memory item may be promoted only when the appropriate research gate is opened.

Promotion must preserve provenance:

Memory ID
   ↓
Definition document
   ↓
RQ ID
   ↓
experiment / evidence
   ↓
endpoint / closure

Never silently convert:
- hypothesis → fact;
- registered prediction → result;
- discussion → RQ;
- historical insight → current task.

## 5. Relationship to current research state

Current state remains governed exclusively by:

1. docs/RESEARCH_STATE.md
2. current endpoint / closure documents
3. experiment ledgers and evidence
4. git history

This memory layer may suggest future questions, but it cannot open a research branch by itself.

Current gate remains the Definition / Opening gate described by RESEARCH_STATE.md.

## 6. Future extension

When the volume grows, split this file into:

docs/research_memory/
├── INDEX.md
├── insights/
├── forks/
├── architecture_hypotheses/
└── dead_ends/

The index should preserve stable IDs and links so that an Agent can reconstruct not only where the project is, but also which intellectual branches produced that state.
