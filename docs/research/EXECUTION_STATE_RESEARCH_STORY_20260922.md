<!-- Publicly curated from SimiGo-Lab. Source: docs/07-history/EXECUTION_STATE_RESEARCH_STORY_20260922.md on exp/simigo2-experimental. Internal recovery/governance material has been excluded. -->

# Execution State Research Story — 2026-09-22

**Status**: RESEARCH MEMORY / RECOVERY MAP  
**Scope**: Architecture 2.0 — Execution State / Track B  
**Purpose**: Compress the experiment-heavy Track B history into a human-readable “why → what → result → idea change” path so that the researcher or a new Agent can recover the intellectual continuity without rereading the full experiment logs.

> This document is a recovery map, not a new finding, decision, experiment, or reopening of Track B.
> The original evidence, findings, decisions, and closure remain authoritative.

---

## 1. The question that started the line

The Execution State line did not begin with “Can we implement KV fork?”

The motivating architectural question was:

> **If expensive long-context computation has already been performed, can its resulting computation state become reusable so that multiple future continuations do not have to repeat the same expensive computation?**

The conceptual progression was:

```
long-context computation is expensive
        ↓
avoid repeating expensive computation
        ↓
Compute Once / Multiple Futures
        ↓
the computed state must be reusable
        ↓
the reusable state must preserve continuation semantics
        ↓
Execution State
```

The central shift was from **cache/storage thinking** toward **reusable executable-state thinking**.

---

## 2. What Track B was actually trying to establish

Track B did **not** attempt to prove all of Architecture 2.0.

Its bounded target was:

> Whether a tested Execution-State lifecycle can preserve identity/continuation semantics across fork, continuation, representation transition, migration/reattach, and discard under the registered scope.

In shorthand:

```
Execution State
    ↓
identity
    ↓
continuation
    ↓
fork
    ↓
child isolation / parent preservation
    ↓
representation transition
    ↓
migration / reattach
    ↓
continue
    ↓
discard
```

The experiments progressively tested this lifecycle rather than five unrelated ideas.

---

## 3. Experiment-by-experiment recovery

### F1 — “Can the state actually fork?”

**Why it was done**

The first risk was that “Execution State” might only be a conceptual name for a collection of tensors/cache data. A real reusable state needed a fork operation with meaningful parent/child semantics.

**What was tested**

- page-split / segment-table representation;
- lazy COW-style fork behavior;
- physical growth associated with private suffix rather than full-depth copying;
- tested GDN reference-fork isolation.

**What it was meant to establish**

> A tested Execution State can support a fork operation without requiring an immediate full-depth copy, while preserving the required tested isolation behavior.

**What it did not establish**

- a universal fork implementation;
- a production API;
- a universal memory model.

**Decision consequence**

Track B continued after the F1 probe; no stop-loss condition was triggered.

---

### F2 — “After fork, can the child really continue correctly?”

**Why this mattered**

A cheap fork is not useful if it changes the computation.

The research therefore moved from representation behavior to **true-model continuation correctness**.

**Key test**

- 16/16 greedy-token agreement against the same-chunking from-scratch control;
- parent attention offsets remained frozen during child execution;
- mixed attention/GDN state remained isolated in the tested setup.

**What it established**

> Under the tested model/configuration, forked Execution State preserved continuation correctness.

This converted “fork as a data-structure trick” into a bounded lifecycle semantic result.

---

### F3 — “Does this survive an actual multi-branch lifecycle?”

**Why it mattered**

A single fork is not enough for the Compute-Once / Multiple-Futures idea.

The question became:

> Can the state be restored and reused across deeper/multiple branches without losing exactness?

**What was tested**

- page-level restore over the tested 16K / 24K / 32K chain;
- COW→COW composition;
- four-way branching;
- private growth behavior;
- model-level decode behavior at the tested workload.

**What it established**

> The tested prototype supported bounded multi-branch / restore lifecycle behavior with continuation correctness preserved over the recorded range.

The important conceptual result was that **Execution State had a lifecycle**, not merely a copy primitive.

---

### F4 — “Must one representation remain fixed forever?”

**Why this mattered**

Once Execution State is treated as a reusable runtime state, representation becomes a lifecycle concern.

A state may be represented in a segmented/shared form when branching is useful, but a continuous representation may later be preferable for steady-state execution.

**What was tested**

- constrained long-depth representation behavior;
- multi-segment performance tax;
- repeated measurements;
- correctness under representation pressure.

**Important feedback**

The tested data showed that multi-segment representation could incur material long-depth performance tax, while correctness remained intact.

This separated two questions:

```
semantic correctness
        ≠
representation performance
```

**Idea consequence**

Representation should not be treated as the identity of Execution State itself.

---

### F5 — “Can representation change without destroying the state?”

This was the next direct test of that separation.

**What was tested**

- Shared/Segmented → Continuous reattach/materialization;
- element equality;
- continuation checks;
- post-transition steady-state behavior;
- migration/materialization cost;
- adaptive transition-policy direction.

**Key result**

The tested reattach path preserved the required state/continuation semantics and restored near-fresh steady-state decode behavior after the one-time materialization cost.

**Idea consequence**

A major durable insight emerged:

> **Representation transition is itself a first-class Execution-State lifecycle operation.**

The state is therefore conceptually above any one physical representation.

---

### F5-3 — “If representation transition has a cost, can runtime make a decision?”

Only after the representation-transition mechanism was established did the research move to policy.

**What was tested**

- online tax estimation;
- remaining-work estimation;
- COW versus reattach choice;
- simulator;
- 12 live trials at 64K@S4;
- observe_k=8.

**What it established**

The tested policy direction could make useful transition choices within the recorded configuration, with low aggregate regret against the stated empirical oracle.

**What it did not establish**

- production policy;
- estimator robustness across models/machines/thermal states/workloads;
- universal break-even thresholds.

This is why the adaptive policy remained explicitly **non-authoritative**.

---

## 4. Closure — what the whole experiment chain finally established

The final closure did not say:

> “Execution State is universally solved.”

It established a bounded lifecycle model:

```
Fork / COW
    ↓
Continue
    ↓
Multi-branch
    ↓
Representation transition
    ↓
Migration / Reattach
    ↓
Continue
    ↓
Discard
```

with the key semantic invariants:

- parent continuation preservation;
- child isolation;
- representation transition semantic preservation;
- tested migration/reattach behavior;
- discard as non-adoption of child state.

Therefore:

**Track B = CLOSED / FROZEN**

within its recorded scope.

---

## 5. What changed in the idea itself

The most important output was not any single benchmark number.

The idea evolved approximately as follows:

```
“save KV/cache”
        ↓
“reuse computed state”
        ↓
“Execution State”
        ↓
“Execution State has identity + continuation”
        ↓
“Execution State is forkable”
        ↓
“Execution State has a lifecycle”
        ↓
“representation is separable from state identity”
        ↓
“representation transition is a lifecycle operation”
        ↓
“execution state can be treated as a reusable execution asset”
```

The last step is a **long-horizon architectural interpretation**, not a newly closed Track B finding. It should remain distinguishable from the frozen experimental scope.

---

## 6. What Track B did NOT answer

The following remain outside the Track B closure:

- general physical residency behavior;
- predictive residency as a general runtime mechanism;
- universal runtime sharding;
- existence of a universal Model Unit / operational unit;
- production-grade adaptive policy;
- universal page/segment granularity;
- all-model/all-workload generalization;
- the complete Architecture 2.0 intellectual graph.

In particular:

> **Track B does not prove that Execution State is the runtime “Model Unit”.**

That is a downstream architectural hypothesis and must not be inferred from the Track B closure.

---

## 7. Where Execution State stands now

A useful recovery classification is:

```
DIRECTLY SUPPORTED BY TRACK B
├── fork / COW lifecycle semantics
├── continuation preservation
├── child isolation
├── multi-branch lifecycle
├── representation transition
├── tested migration / reattach
└── discard semantics

SUPPORTED WITH EXPLICIT SCOPE LIMITS
├── reusable-state interpretation
├── representation/state separation
└── adaptive transition-policy direction

LONG-HORIZON HYPOTHESES
├── Execution State as reusable execution asset
├── Execution State as bridge to residency
├── Execution State as bridge to runtime sharding
└── Execution State → operational/model unit
```

This distinction is essential. A closed Track does not mean every architectural implication generated by the Track is also closed.

---

## 8. How this map should be used

When returning to SimiGo-Lab after a long experiment-heavy period, read this document first.

Then use the original chain only when detail is needed:

```
Research Story
      ↓
Finding Map
      ↓
Decision Register
      ↓
Original Evidence
      ↓
Closure
```

The story answers:

1. **Why did we start this line?**
2. **What was each experiment trying to establish?**
3. **What changed after the experiment?**
4. **What did the final closure actually establish?**
5. **What remains hypothesis rather than result?**

It is deliberately not a replacement for the evidence package.

---

## 9. Research-gate effect

**NONE.**

This document:

- does not reopen Track B;
- does not alter CLOSED / FROZEN status;
- does not register a new RQ;
- does not start STEP⑤;
- does not authorize implementation;
- does not authorize new measurement;
- does not promote Architecture 2.0 hypotheses to established architecture.

Its sole purpose is **research continuity and cognitive-load reduction**.

---

## 10. One-sentence recovery

> **Track B was a progressive attempt to determine whether an already-computed state could become a reusable, forkable, continuable runtime state with a lifecycle independent of any single physical representation; the experiments established a bounded version of that lifecycle, while leaving the larger architectural consequences open.**
