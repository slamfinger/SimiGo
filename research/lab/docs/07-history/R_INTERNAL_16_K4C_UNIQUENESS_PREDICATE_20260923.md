# R-INTERNAL-16 — K4-C / UNIQUENESS PREDICATE

**Date**: 2026-09-23  
**Status**: DECLARED  
**Decision**: UNRESOLVED + UNIQUENESS_PREDICATE

## 1. Precondition

R-INTERNAL-15 / K4-B has already declared:

Argmin(P,θ) = {g ∈ D_opt(P,θ) | L(g;P,θ) = inf V(P,θ)}  ((P,θ) ∈ Dom(R))

Argmin(P,θ) ≠ ∅ ⇔ att(P,θ)

and:

Dom_att = {(P,θ) ∈ Dom(R) | Argmin(P,θ) ≠ ∅}.

K4-B does not assert argmin non-emptiness or uniqueness anywhere.

## 2. Decision

The researcher explicitly selected K4-C-2 / UNRESOLVED + UNIQUENESS_PREDICATE.

The uniqueness predicate is defined on Dom(R) by:

uniq : Dom(R) → {true,false}

uniq(P,θ) ⇔ |Argmin(P,θ)| = 1

and:

Dom_uniq = {(P,θ) ∈ Dom(R) | uniq(P,θ)}.

This is a definitional predicate formation only. No instance is asserted to satisfy it.

## 3. Rejected alternatives

### K4-C-3 — direct uniqueness assertion

Rejected because it would be a bare structural axiom analogous to K4-A-3 / B1. Multiple-optimizer cases remain fully legal under the currently declared abstract framework; no declared structure supports |Argmin(P,θ)| = 1 as a global assertion.

### K4-C-4 — choice-axiom selector

Rejected because a pure selector axiom contributes no canonical content and would function only as a placeholder. It is therefore not registered at this gate.

### K4-C-5 — canonical selector / tie-breaking

Rejected because the language required by a tie-breaking rule has not yet been declared. Any such rule would depend on structure on 𝒢_adm(P) or A (for example an order, topology, or measure), none of which is currently available. Any future sufficient structural condition must open its own independent decision surface.

## 4. Semantic interpretation

K4-C establishes only a truth-valued uniqueness interface:

uniq : Dom(R) → {true,false}

uniq(P,θ) ⇔ |Argmin(P,θ)| = 1

Dom_uniq = {(P,θ) ∈ Dom(R) | uniq(P,θ)}.

It does not assert Dom_uniq ≠ ∅, does not assert uniq is true at any point, and does not produce a selector, canonical optimizer, tie-breaking rule, or computable/reachable g*.

The implication that uniq(P,θ) is false whenever Argmin(P,θ) = ∅ is a direct consequence of the registered definitions, not an additional declaration.

## 5. Forward semantic separation

K4-C preserves the layer separation:

attainment ≠ argmin set semantics ≠ uniqueness predicate ≠ selector/tie-breaking.

In particular, even if uniq(P,θ) is true at some later-established point, no selector is thereby defined by K4-C. Uniqueness and selection remain distinct interfaces.

## 6. Explicit non-declarations

K4-C does not declare:

- Dom_uniq ≠ ∅;
- uniq(P,θ) = true at any particular point;
- optimizer existence as a separate global assertion;
- selector, g*, canonical choice, or tie-breaking;
- replacement of inf by min;
- topology, compactness, continuity, measurability, or finite candidate-domain assumptions;
- θ-level optimization or A(P,θ);
- historical δ(I_P) or a new δ optimization domain;
- R_OBJECT, R_ORACLE, Δ, FinLoss, NECT;
- STEP⑤ / STEP⑥;
- implementation, harness, data collection, profiling, measurement, or experiment authorization.

## 7. Forward-looking continuity note

A future instantiation surface may legitimately declare finiteness of D_opt. If such a structural fact is later authorized, it may materially simplify the relationships among attainment, uniqueness, and selector construction. That observation is recorded only for continuity; it does not authorize the finiteness claim, a selector, or any downstream construction at K4-C.

## 8. Continuity

docs/SESSION_CONTINUITY.md is synchronized in the same registration commit to include R-INTERNAL-16 / K4-C in its gate list, current interfaces, and continuity notes. It remains a continuity index only; docs/RESEARCH_STATE.md remains the sole semantic authority.
