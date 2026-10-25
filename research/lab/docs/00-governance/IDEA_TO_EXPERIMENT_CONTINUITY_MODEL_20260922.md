# Idea → Question → Experiment: Research Continuity Model

> **Purpose:** define the durable conceptual bridge between SimiGo-Lab's intellectual assets and its concrete research work.
>
> This document is a methodology/governance artifact. It does not create an RQ, authorize an experiment, reopen a closed track, or promote an architecture hypothesis to fact.

## 1. Core principle

SimiGo-Lab is not fundamentally an experiment archive.

The physical/runtime world is better represented as a structured system of objects, relations, states, constraints, and transitions. Experiments are observations of selected parts of that structure.

Therefore the primary continuity chain is:

```
Idea / structural hypothesis
        ↓
research question
        ↓
existence / estimand / observation definition
        ↓
experiment design
        ↓
evidence
        ↓
finding
        ↓
decision
        ↓
architecture consequence
        ↓
new or revised idea
```

The experiment is **a local test of a higher-level idea**, not the idea itself.

## 2. Why this bridge is necessary

Without an explicit bridge, a research repository tends to fragment into two disconnected histories:

```
A. intellectual discussion
   → interesting concepts
   → architecture visions
   → forgotten rationale

B. experimental work
   → scripts
   → runs
   → numbers
   → closures
```

The missing object is the **intellectual-to-empirical linkage**:

```
why this experiment exists
        ↓
which idea it tests
        ↓
which specific claim it can distinguish
        ↓
what the result changes
        ↓
what remains unchanged
```

This linkage must survive Agent changes, long pauses, implementation rewrites, and failed branches.

## 3. Three layers

### Layer I — Idea / Structure

This layer contains durable understanding such as:

- conceptual boundaries;
- architecture hypotheses;
- physical/resource constraints;
- candidate objects and relations;
- causal/mechanistic hypotheses;
- negative knowledge;
- unresolved structural questions.

Primary home:

- `docs/RESEARCH_MEMORY.md`
- Architecture 2.0 history/reconstruction documents
- future dedicated idea records when scale requires them.

An idea may exist for a long time without becoming an RQ.

### Layer II — Research Question / Testable Claim

An idea becomes research only when a precise question can be defined.

The conversion should make explicit:

- research object;
- independence;
- estimand;
- observation domain;
- existence criterion;
- insufficiency criterion;
- discriminating power;
- information value versus measurement cost.

Current Gate order remains authoritative:

```
① object
② question
③ independence
④ estimand
⑤ existence
⑥ insufficiency
⑦ discrimination
⑧ information value / cost
⑨ Path / Harness / Experiment
```

The Gate prevents an attractive idea from becoming implementation merely because it sounds plausible.

### Layer III — Empirical Verification

Only after authorization does the chain enter:

```
Design
  ↓
Implementation / collection
  ↓
Evidence
  ↓
Finding
  ↓
Decision
  ↓
Endpoint / Closure
```

Evidence is local and scoped. It does not automatically validate the whole parent idea.

## 4. The bidirectional relationship

The bridge is not one-way.

### Downward

A structural idea generates questions and experiments:

```
Idea
 ↓
What would have to be true?
 ↓
What observation could distinguish it?
 ↓
What is worth measuring?
 ↓
Experiment
```

### Upward

Evidence updates the structural understanding:

```
Evidence
 ↓
What property was actually observed?
 ↓
Which branch is supported / weakened / closed?
 ↓
Does the parent idea survive unchanged?
 ↓
Should the idea be refined, split, or abandoned?
```

Thus:

> **Research is a feedback system between structural hypotheses and local observations.**

## 5. Experiments are local, ideas are global

A single experiment should normally answer a bounded question.

For example:

```
Idea:
Execution State should preserve identity and continuation.

        ↓

RQ:
Can a tested fork representation preserve parent continuation
and child isolation under a defined lifecycle?

        ↓

Experiment:
specific fork / continue / discard trials

        ↓

Evidence:
token-level correctness and lifecycle observations

        ↓

Finding:
bounded tested lifecycle property

        ↓

Decision:
Track B closure / architecture constraint

        ↓

Idea update:
Execution State requires lifecycle semantics beyond raw KV copying.
```

The evidence does **not** establish every future Execution State mechanism.

Conversely, failure of one implementation path does not necessarily falsify the parent conceptual object.

## 6. Branching and pruning

The research tree should preserve both growth and pruning:

```
                 Idea
                  │
       ┌──────────┼──────────┐
       ↓          ↓          ↓
    branch A   branch B   branch C
       │          │          │
     tested     failed     dormant
       │
    refined
       │
    next RQ
```

A closed experiment therefore has two values:

1. empirical evidence about its bounded claim;
2. structural information about which branch should or should not be pursued.

A failed branch is durable negative knowledge when it prevents future Agents from repeating the same conceptual mistake.

## 7. Provenance requirements

Every durable idea that materially influences research should be traceable to:

- its origin or reconstruction source;
- the scope in which it applies;
- its current status;
- supporting evidence, if any;
- what it does **not** prove;
- the legal promotion path if future research is warranted.

Every experiment should be traceable upward to the idea/question it tests.

Every Finding/Decision should be traceable downward to the evidence that supports it.

No link may silently upgrade status.

## 8. Required linkage fields

As the archive evolves, research artifacts should expose these relationships where useful:

```
Idea ID / Memory ID
    ↓
Question / RQ ID
    ↓
Design / Experiment ID
    ↓
Evidence anchor
    ↓
Finding ID
    ↓
Decision ID
    ↓
Architecture consequence
```

Not every idea needs every downstream node.

A durable idea with no RQ is valid.
An RQ with no authorized experiment is valid.
A closed experiment with no architecture consequence is valid.

What is forbidden is inventing a downstream node merely to make the chain look complete.

## 9. Agent recovery rule

A new Agent should not reconstruct SimiGo-Lab by reading only the latest experiments.

Recovery should answer:

1. What are the durable ideas?
2. Which ideas became formal questions?
3. Which questions were actually tested?
4. What did each experiment observe?
5. What was learned locally?
6. Which branches are closed or forbidden?
7. Which ideas remain hypotheses?
8. What is the next legally authorized action?

This is the intended relationship between:

```
RESEARCH_MEMORY
      ↕
Research Questions / Design
      ↕
Evidence / Findings / Decisions
      ↕
RESEARCH_STATE
```

with `RESEARCH_STATE.md` remaining authoritative for current status.

## 10. What this model prevents

This bridge is specifically intended to prevent:

- repeating experiments because their rationale was forgotten;
- losing continuity when an Agent changes;
- treating an experiment result as the whole theory;
- treating a hypothesis as established fact;
- treating implementation convenience as research truth;
- allowing a current API boundary to define the research object;
- reopening closed branches because historical context disappeared;
- creating experiments without knowing what structural claim they test.

## 11. Relationship to existing archive architecture

The existing archive chain remains:

```
Question → Hypothesis → Design → Evidence → Finding → Decision → Architecture → Invariant / Closure
```

This document adds the missing upstream bridge:

```
Durable Idea / Structural Understanding
                 ↓
Question
                 ↓
Hypothesis / Testable Claim
                 ↓
Design → Evidence → Finding → Decision → Architecture
                 ↓
           revised understanding
```

Thus the complete research memory model becomes:

```
                IDEA / STRUCTURE
                       ↕
                    QUESTION
                       ↓
                  TESTABLE CLAIM
                       ↓
                     DESIGN
                       ↓
                  EXPERIMENT
                       ↓
                    EVIDENCE
                       ↓
                    FINDING
                       ↓
                   DECISION
                       ↓
                  ARCHITECTURE
                       ↓
              REVISED IDEA / STRUCTURE
```

This is the intended long-term continuity model for SimiGo-Lab and for collaboration between local Agents and ChatGPT.
