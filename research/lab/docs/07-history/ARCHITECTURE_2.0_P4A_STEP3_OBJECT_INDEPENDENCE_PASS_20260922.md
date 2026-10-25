# Architecture 2.0 / P4-A — STEP③ Object Independence: PASS with Frame-Relative Identity

**Date:** 2026-09-22  
**Status:** STEP③ / Object Independence PASS / Parameter Independence remains open

## 1. Attack and adjudication

The first STEP③ attack separated two objections:

1. **A priori / restatement objection:** the Achievable Static Frontier is mathematically implied by the declared frame `(L, D, S, X)` and therefore contains no empirical content.
2. **Redundancy objection:** the frontier is merely a generic Pareto/rate-loss construction and therefore is not a research object.

Both objections fail once the object is separated into three layers.

## 2. Three-layer object identity

### Layer 1 — Instrument / stipulation

`F_AS^(L,D,S)(X)` is a frame-indexed functional definition. This layer is stipulated rather than discovered. Its purpose is to define the measurement instrument.

### Layer 2 — Readout / empirical object

Given architecture X, the actual frontier shape, analytic gap, achievable rate-loss tradeoff, and any phase-transition locations are not implied by the frame. They require analysis and construction against the actual architecture.

### Layer 3 — Regularity / empirical cross-architecture structure

Cross-X commonality, such as stable frontier families, knee alignment, or other structural regularities, is an empirical question and is not entailed by the definition.

Thus the research content resides in Layers 2 and 3, while Layer 1 supplies the instrument.

## 3. Three independence tests

### 3.1 Non-circularity — PASS

The definition does not encode its empirical answer. The frontier may be flat, have no knee, have near-zero analytic gap, or exhibit other unexpected structure. STEP② established only non-degenerate information demand in the decision family; it did not establish any frontier shape.

### 3.2 Non-vacuity — PASS

Admissible changes in X can produce different frontier readouts. The declared derivation strategy family S can also fail on a real architecture, making the achievable frontier empty or otherwise degenerate. Such outcomes are architecture-dependent empirical facts, not consequences of the declaration.

### 3.3 Non-reducibility — PASS

The frontier cannot be obtained from the frame alone once X is instantiated. Actual state-space structure and encoder construction are required. Architecture-specific facts therefore enter the readout in a non-removable way.

## 4. Dependency discovered between gates

STEP② non-degeneracy is not merely a parallel prerequisite. It is the anti-vacuity component of STEP③ object independence.

Without the STEP② semantic-conflict proof, the frontier could survive as a formally defined but decision-degenerate object. Therefore provenance should record the dependency:

`STEP② D-level non-degeneracy → STEP③ object non-vacuity`

This is a gate dependency, not evidence that transfers independently of scope.

## 5. Adjudication

**PASS — but only as a frame-indexed measurement object.**

There is no unqualified “the frontier”. The valid object is an architecture's frontier **relative to a declared `(L, D, S)` frame and its declared robustness family**.

Accordingly, all future RQ/estimand language must preserve the frame index. Unqualified claims of a universal frontier are out of scope.

## 6. Procedural constitutive condition

Frame-relative object independence has a non-reducible procedural condition:

> **Declare first → derive second → measure third.**

The admissible frame family must be frozen before result inspection. If the frame family is narrowed or redesigned after observing outcomes, the claimed framework robustness is no longer an independent test.

Repository provenance therefore has methodological status: the git history establishing declaration-before-measurement is part of the audit trail for object identity. This does not make the repository itself an empirical result; it makes provenance a condition for interpreting the robustness claim.

## 7. Positioning the remaining attacks

- **#2 Parameter independence:** whether L/D/S are constitutive frame coordinates rather than hidden outcome-manipulation knobs.
- **#4 Historical independence:** whether Track B's lifecycle findings are prerequisites rather than the same empirical claim under new terminology.
- **#5 Implementation independence:** whether the instrument is defined at L-level semantics rather than tied to MLX-LM, Runtime, or physical state layout.

**Current status:** Object Independence PASS; Parameter Independence OPEN; no STEP④ transition; no experiment authorization.
