# R-INTERNAL-17 — RO-1 / R_OBJECT_VALUE_FUNCTIONAL

**Date**: 2026-09-23  
**Status**: DECLARED  
**Decision**: RO-1 / VALUE FUNCTIONAL

## 1. Precondition

R-INTERNAL-16 / K4-C has already declared the uniqueness predicate on Dom(R):

uniq : Dom(R) → {true,false}  
uniq(P,θ) ⇔ |Argmin(P,θ)| = 1  
Dom_uniq = {(P,θ) ∈ Dom(R) | uniq(P,θ)}

R_OBJECT was still NOT_DECLARED, while R(P,θ) ∈ ℝ was already established on Dom(R) by K3-B.

## 2. Researcher designation

The researcher explicitly designated:

R-INTERNAL-17 = RO-1

R_OBJECT := R : Dom(R) → ℝ  
R_OBJECT : NOT_DECLARED → DECLARED

This designation is an intent-level design judgment, not a mathematical inference. The registration records the researcher’s stated intent evidence as the decision proxy; final semantic authority remains with the researcher.

## 3. Intent evidence recorded

The designation is supported by the following registered-text evidence:

1. The Phase is Architecture 2.0 / P4 Redefinition, where the object under study is the projection candidate P and R(P,θ) is the value-level evaluation functional for a candidate projection under a regime.
2. R-ASM-B = REGIME_INDEXED_WORKLOAD_DISTRIBUTION_FAMILY establishes a regime-indexed assembly skeleton, making θ comparison part of the declared architecture.
3. STEP④-B / Value Discipline: COMPLETE records the value layer as a completed and independent semantic stage.
4. The repeated explicit blocking of historical δ(I_P) and any new δ optimization domain in K3/K4 provides registered evidence that decision-rule optimization is not the current program-intent surface.

These points are recorded as intent evidence, not as a derivation that logically forces RO-1.

## 4. Declared object semantics

R_OBJECT = R : Dom(R) → ℝ

Under RO-1, the research object is the optimal value functional. Argmin, att, uniq, Dom_att, and Dom_uniq remain fully registered and are not deleted. They are demoted only in semantic role: they are auxiliary objects/interfaces supporting well-definedness, attainment diagnostics, and optimizer diagnostics rather than the primary research object.

This role change does not rewrite or supersede the K4-A/K4-B/K4-C definitions.

## 5. Downstream separation

R_ORACLE remains NOT_DEFINED and is reserved for R-INTERNAL-18. Under RO-1, its future interface may concern value access, but this gate does not define or pre-judge its exact form.

Historical δ(I_P) remains BLOCKED. No new δ optimization domain is introduced.

Δ remains BLOCKED. FinLoss remains NOT LEGALLY AVAILABLE. NECT remains BLOCKED.

STEP⑤ and STEP⑥ remain NOT ENTERED. Implementation, harness, data collection, profiling, measurement, and experiment authorization remain NONE.

No topology, compactness, continuity, measurability, finiteness/cardinality assumption, θ-level optimization, A(P,θ), or approximation/gap object is introduced by this gate.

## 6. Consistency check

RO-1 is compatible with the currently registered interfaces:

- K3-B already establishes that R(P,θ) = inf V(P,θ) ∈ ℝ on Dom(R), so the declared value-functional object is well-formed on its declared domain.
- K4-B and K4-C define Argmin and uniq independently of whether the argmin layer is primary or auxiliary.
- No existing declaration requires the research object to be set-valued.
- Selecting RO-1 does not restore historical δ(I_P) and does not introduce a new δ optimization problem.

## 7. Explicit non-declarations

R-INTERNAL-17 does not declare:

- any change to the definitions of att, Argmin, uniq, Dom_att, or Dom_uniq;
- R_ORACLE;
- Δ, FinLoss, or NECT;
- any selector, tie-breaking, canonical optimizer, or g*;
- topology, compactness, continuity, measurability, finiteness/cardinality assumptions;
- θ-level optimization or A(P,θ);
- historical δ(I_P) or any new δ optimization domain;
- Dom(R) ≠ ∅, Dom_att ≠ ∅, or Dom_uniq ≠ ∅;
- attainment or uniqueness at any particular point;
- min in place of inf;
- implementation, harness, data collection, profiling, measurement, or experiment authorization;
- approximation/gap objects such as a suboptimality gap.

## 8. Assembly transition

R_OBJECT : NOT_DECLARED → DECLARED  
R_OBJECT := R : Dom(R) → ℝ  
R_ASSEMBLY remains OPEN

This gate changes the object-status field only. R_ASSEMBLY is not closed by this declaration.

## 9. Continuity

This history record is registered together with synchronized updates to docs/RESEARCH_STATE.md and docs/SESSION_CONTINUITY.md. The latter remains a continuity index; docs/RESEARCH_STATE.md remains the sole semantic authority.
