# Architecture 2.0 P4-A — Static Derivability, Analytic Skeleton, and Decision-Loss Gate

**Date:** 2026-09-22  
**Status:** P4-A STEP① conceptual refinement / no RQ / no experiment authorization

## 1. Purpose

This record consolidates the next refinement after the Analytic Encodability Attack. It sharpens the provenance boundary of encoder construction, records a future architecture-family boundary probe, preserves a hybrid analytic-plus-measured-coefficient hypothesis, and separates object-definition constraints from later evaluation-method constraints.

The central governance rule remains:

> This document refines a candidate research object. It does not open STEP②–⑨, create an RQ, authorize a harness, or authorize data collection.

## 2. Static Derivability as the hard provenance criterion

The strongest operational boundary for Analytic Encodability is:

> An encoder rule is analytically derivable if an agent that has never run the target model can derive the rule from admissible static architecture/computation descriptions alone.

Admissible static sources may include:
- architecture specifications;
- declarative structure and configuration;
- computation semantics;
- dependency/type/shape information;
- implementation source code, when treated only as a static description of computation structure.

The decisive distinction is not “documentation vs source code” but **static reading vs execution observation**.

Allowed:
- read structure → derive encoder rule

Forbidden:
- run → observe behavior → modify/discover encoder rule

The following therefore count as profiling or target-outcome leakage:
- execution traces;
- runtime counters;
- benchmark results;
- measured memory behavior;
- measured migration/materialization behavior;
- resource-decision labels;
- workload traces used to discover predictive fields.

This criterion sharpens the earlier profiling-dependence and decision-leakage attacks without banning architecture-specific knowledge itself.

## 3. Architecture-specific encoder knowledge remains allowed

The gate does **not** require a universal encoder formula.

The admissible form remains:

Architecture X → Encoder_X

What is forbidden is:

Architecture X → run/profile target → Encoder_X

The research question is therefore about **knowledge provenance**, not about eliminating architecture-specific structure.

## 4. Novel-architecture probe as a future discriminating constraint

Hidden architecture-family prior cannot be resolved by inspecting the encoder author's intentions. A future evaluation scope should deliberately include architecture diversity sufficient to expose that prior.

Candidate boundary sampling:
1. a familiar architecture family;
2. a structurally different known family;
3. at least one architecture outside the encoder author's prior experience family, or a purpose-built structural variant designed to be novel to the encoder construction process.

If analytic encoding survives only within familiar families but requires substantial manual modification for novel structures, that is evidence for an applicability boundary (B), not universal cross-architecture validity.

This is a **future STEP②–⑨ design constraint**, not a current experiment authorization. It is especially aligned with the rule:

representative architecture → minimal abstraction → real counterexample → minimal extension

## 5. Analytic skeleton + minimal empirical completion

A useful asymmetry hypothesis is now recorded:

- state-structure fields may often be statically derivable:
  - components;
  - dependency relations;
  - growth patterns;
  - lifetime structure;
  - continuation-relevant structural properties.
- transition/materialization fields may be less statically derivable:
  - migration granularity;
  - reconstruction order;
  - reattach feasibility;
  - implementation/runtime-specific materialization behavior.

This yields a non-binary candidate:

Architecture → analytic structural skeleton → minimal measured coefficients → projection → Runtime decision

If this pattern survives later falsification, Analytic Encodability need not be treated as all-or-nothing. The sharper future question becomes:

> What is the minimum empirical information required to complete an analytically derivable state description?

The cost accounting then remains conceptually separated:

A_analytic + A_measurement → architecture adaptation  
D_decision → repeated runtime decision cost

This is a hypothesis only. No measurement set is currently defined or authorized.

## 6. Definition Layer vs Evaluation-Constraint Layer

STEP① has accumulated substantial material. To avoid circularity, it is now explicitly divided.

### Definition Layer — STEP①

The candidate object contract may contain:
- fixed Runtime-side description language L;
- frozen decoder concept;
- L₀ byte-level direct-dump reference;
- deployment-regime variables such as A:D;
- provenance requirement for analytic encodability.

These define what the candidate object means and what information sources are admissible.

### Evaluation-Constraint Layer — future STEP④–⑨

The following belong to later evaluation design:
- operational two-part cost accounting;
- concrete decoder-in-the-loop protocol;
- operational tests for the six analytic-encodability attack targets;
- novel-architecture sampling protocol;
- concrete rate/distortion estimands;
- measurement budgets and thresholds.

They remain recorded here for provenance, but must be re-filed as explicit design constraints when STEP② and later gates open.

This separation prevents the research object from silently embedding its own experiment protocol.

## 7. Next attack: Decision-Loss Well-Definedness

After information provenance and representation cost, the next conceptual gate is:

> Can Decision Loss D be defined without arbitrary researcher choices, while remaining sufficiently discriminating to distinguish candidate projections?

The dependency is:

Projection → Runtime decision → Decision Loss D

Therefore the candidate value question cannot yet be evaluated until D has a defensible definition.

Two legitimate exits are recorded.

### A. Formal decision model

If D can be defined analytically from task semantics, decision consequences, and admissible assumptions without runtime implementation, continue conceptual definition work.

### B. Harness Authorization Gate

If defining D requires an actual decision process, runtime simulation, or executable harness, do **not** build it implicitly. Stop and open an explicit Harness Authorization Gate under the existing STEP⑤–⑨ governance.

The difficulty of defining D must not silently become permission to implement SimiGo Runtime.

## 8. Current compressed candidate

The surviving P4-A candidate is no longer “prove a universal Execution State object”.

It is closer to:

> 在固定且可审计的 Runtime-side description language 下，研究是否存在一种跨架构、信息来源受约束的 State description，使 Runtime resource decisions 在给定任务与部署 regime 下保持足够决策信息，同时降低跨架构适配与重复决策成本。

Its current conceptual chain is:

Fixed Language → Two-part accounting → Decoder audit → L₀ → Analytic Encodability → Novel-architecture boundary → Decision-Loss Well-Definedness → Rate/Distortion information value

Each arrow remains a candidate gate, not a proven property.

## 9. Governance status

- P4-A STEP①: **WORKING DEFINITION / CONTINUES**
- RQ: **not assigned**
- STEP②–⑨: **not started**
- Runtime implementation: **not authorized**
- Harness construction: **not authorized**
- Data collection: **not authorized**
- Measurement: **not authorized**
- Analytic skeleton + minimal measured coefficients: **hypothesis**
- Novel-architecture probe: **future evaluation constraint**
- Decision-Loss Well-Definedness: **next conceptual attack**

The next legal conceptual action is to attack whether Decision Loss D can be defined cleanly without smuggling in a runtime implementation.
