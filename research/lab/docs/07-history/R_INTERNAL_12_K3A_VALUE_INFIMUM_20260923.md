# R-INTERNAL-12 = K3-A / VALUE_INFIMUM

Date: 2026-09-23

## Declaration

R-INTERNAL-12 = K3-A

Semantic type:

```
VALUE_INFIMUM
```

## Semantic declaration

The abstract optimization operator is concretized as the infimum of the admissible finite value set.

```
V(P,θ)
=
{L(g;P,θ) | g ∈ 𝒢_adm(P), (g,P,θ) ∈ Dom(L)}

OPT(P,θ) = inf V(P,θ)
```

This gate binds the semantic construction of OPT to a value-level infimum. It does not by itself assert that the infimum is finite for every previously established E10-B context.

## Relation to prior gates

R-INTERNAL-9 = E9-B established an abstract scalar optimization operator over the effective optimization domain.

R-INTERNAL-10 = E10-B established that this effective optimization domain is non-empty.

R-INTERNAL-11 = E11-B declared the aggregate output to be finite real-valued, but did not select a concrete construction.

R-INTERNAL-12 now selects `inf` as the concrete construction.

The finiteness/applicability scope of the resulting `R(P,θ)` value remains subject to the subsequent K3-B gate.

## Boundaries

This gate does not declare:

- minimum attainment;
- optimizer existence;
- argmin;
- selector or tie-breaking rule;
- boundedness as an independent global axiom;
- compactness, continuity, measurability, or computability beyond prior declarations;
- any θ-level optimization;
- `A(P,θ)` or another candidate-value set;
- R_OBJECT, R_ORACLE, Δ, FinLoss, NECT;
- STEP⑤/STEP⑥ entry;
- implementation, harness, data collection, profiling, measurement, or experiment authorization.

Historical `δ(I_P)` is not restored and no new δ optimization domain is introduced.
