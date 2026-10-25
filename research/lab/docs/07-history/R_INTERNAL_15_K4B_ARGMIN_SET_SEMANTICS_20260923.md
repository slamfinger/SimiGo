# R-INTERNAL-15 — K4-B / ARGMIN SET SEMANTICS

**Date**: 2026-09-23  
**Status**: DECLARED  
**Decision**: DEFINE_ARGMIN_SET + ATTAINMENT_EQUIVALENCE

## 1. Precondition

R-INTERNAL-14 / K4-A has already declared:

att : Dom(R) → {true,false}

att(P,θ) ⇔ inf V(P,θ) ∈ V(P,θ)

and Dom_att = {(P,θ) ∈ Dom(R) | att(P,θ)}.

K4-A does not assert attainment anywhere.

## 2. Decision

The researcher explicitly selected K4-B-3 / DEFINE_ARGMIN_SET + ATTAINMENT_EQUIVALENCE.

The argmin set is defined on Dom(R) by:

Argmin(P,θ) = {g ∈ D_opt(P,θ) | L(g;P,θ) = inf V(P,θ)}  ((P,θ) ∈ Dom(R)).

The formal pointwise bridge is registered:

Argmin(P,θ) ≠ ∅ ⇔ att(P,θ)  ((P,θ) ∈ Dom(R)).

Equivalently, the attainment domain is recorded at the set level as:

Dom_att = {(P,θ) ∈ Dom(R) | Argmin(P,θ) ≠ ∅}.

## 3. Semantic interpretation

This gate establishes a set-valued argmin interface. The definition itself carries no existence assertion. Argmin(P,θ) is therefore permitted to be empty at every point unless a later gate establishes otherwise.

The registered equivalence is the formal bridge between the attainment predicate and argmin non-emptiness. It does not add a new existence axiom; it records the exact image-membership correspondence induced by the definitions of V and Argmin.

## 4. Explicit non-declarations

K4-B does not declare:

- Argmin(P,θ) ≠ ∅ at any instance;
- optimizer existence as a separate global assertion;
- uniqueness;
- selector, g*, canonical choice, or tie-breaking;
- replacement of inf by min;
- topology, compactness, continuity, measurability, or finite candidate-domain assumptions;
- θ-level optimization or A(P,θ);
- historical δ(I_P) or a new δ optimization domain;
- R_OBJECT, R_ORACLE, Δ, FinLoss, NECT;
- STEP⑤ / STEP⑥;
- implementation, harness, data collection, profiling, measurement, or experiment authorization.

## 5. Domain choice

Argmin is deliberately defined on Dom(R), not on the larger E10-B context. Outside Dom(R), the current risk/value construction is not legally evaluated as a finite real-valued R; extending the argmin interface there is not authorized by this gate.

## 6. Separation of layers

attainment ≠ argmin set semantics ≠ selector/tie-breaking.

Even where Argmin is nonempty, no choice of one member is defined by K4-B.

## 7. Continuity

docs/SESSION_CONTINUITY.md is synchronized in the same registration commit to include K4-A and K4-B in its current interface and gate lists. It remains a continuity index only; docs/RESEARCH_STATE.md remains the sole semantic authority.