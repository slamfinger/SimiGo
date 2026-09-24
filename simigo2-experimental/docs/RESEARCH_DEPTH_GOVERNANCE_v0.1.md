# SimiGo 2.0 Experimental — Research Depth Governance v0.1

Date: 2026-09-24

## 1. Purpose

SimiGo 2.0 Experimental enters an engineering-research phase in which each experiment may expose a deeper and more specific question.

This document establishes a depth-control mechanism to prevent the research from repeating the A2.0 failure mode: continuously absorbing newly discovered subproblems into the core theory until the research object becomes difficult or impossible to close.

The purpose is not to prevent deeper research. It is to require evidence before increasing research resolution.

## 2. Core Principle

> **Minimum Sufficient Resolution Principle**

Use the lowest observation/research resolution that can explain the current experimental phenomenon and support the current research question.

Only increase resolution when the current resolution produces a repeatedly validated, materially relevant phenomenon that cannot be explained or tested adequately at the current resolution.

A deeper question is not automatically a required next question.

## 3. Three-Gate Depth Check

Every newly discovered question must first pass these checks.

### Gate A — Direct relevance

Does the new question directly affect the current research question?

If it is merely interesting background knowledge, keep it outside the active route.

### Gate B — Continuation necessity

Can the current experiment continue without answering it?

If the current route can proceed without it, treat it as an optional branch rather than a prerequisite.

### Gate C — Evidence of insufficiency

Is there an observed and repeatable phenomenon showing that the current resolution is insufficient?

A conceptual argument alone is not sufficient to increase research resolution.

## 4. Resolution Escalation Rule

The default direction is:

    phenomenon
      ↓
    measurement
      ↓
    repeatability
      ↓
    current resolution sufficient?
      ├── yes → record result / STOP
      └── no → demonstrate insufficiency
                    ↓
                 increase one resolution level
                    ↓
                 re-test

Do not skip directly to a finer-grained object because it appears theoretically more precise.

## 5. Example Resolution Ladder

This ladder is a research aid, not a declaration of the SimiGo architecture:

    R0  Workload / execution context
      ↓
    R1  Parameter or layer-group
      ↓
    R2  Layer
      ↓
    R3  Router
      ↓
    R4  Expert
      ↓
    R5  Token × Expert

The actual stopping level must be determined by evidence.

For example, if group-level intervention is sufficient to establish stable demand/locality and produces a reproducible residency effect, there is no requirement to continue to Layer, Router, Expert, or Token × Expert resolution.

Conversely, if group-level results are repeatedly unstable and the instability is demonstrably tied to finer execution structure, a one-level resolution increase may be justified.

## 6. Stop Is a Valid Result

Stopping at a coarser resolution is not considered an incomplete experiment.

A result of the form:

> "The current resolution is sufficient for the present research question."

is a valid research result.

Likewise:

> "The current resolution is insufficient, and the evidence requires the next resolution."

is a valid escalation result.

Both require evidence.

## 7. Separation from A2.0

A2.0 remains frozen.

This governance rule does not introduce:

- new A2.0 formal definitions;
- new R-INTERNAL nodes;
- probability into A2.0;
- predictive loading into A2.0;
- a new universal SimiGo architecture;
- Expert/Router/Token×Expert as predefined research objects.

The rule belongs to the SimiGo 2.0 Experimental engineering-research process.

## 8. Current Application

Current Layer Demand work should therefore not assume that Representation, Router, Expert, or Token × Expert observation is mandatory.

The immediate experimental question remains bounded by the current measurable resolution.

For the present route:

    workload/input + execution context
        → observable execution/group demand
        → temporal locality
        → predictability
        → residency intervention
        → runtime trade-off

Only if evidence shows that the observable group/layer resolution is insufficient should finer-grained instrumentation be introduced.

## 9. Governance Rule

Before adding a deeper research object, record:

1. the current research question;
2. the current observation resolution;
3. the concrete phenomenon that cannot be explained/tested;
4. why the current resolution is insufficient;
5. the single next resolution being introduced;
6. the stop condition for that deeper experiment.

No automatic theory expansion follows from discovery of a deeper question.

## 10. Guiding Principle

> **Research depth follows evidence, not curiosity.**

Curiosity generates candidate questions.

Evidence determines whether a candidate becomes the next experiment.

The smallest sufficient resolution determines where the experiment stops.
