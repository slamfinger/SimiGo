# R-INTERNAL-1 — P Type Declaration

**Date:** 2026-09-23

## Researcher declaration

R-INTERNAL-1 = P4

## Declared semantics

The projection candidate P is declared at the carrier/type level only:

```text
P : PROJECTION_CANDIDATE
```

This identifies P as a projection candidate without instantiating an internal set-theoretic, functional, or composite structure.

P4 therefore does **not** declare:

- P as a function;
- a concrete domain or codomain for P;
- P as a tuple or other structured object;
- a concrete projection operator;
- a concrete projection-candidate carrier set beyond the type-level declaration;
- any direct relation between P and X, Y, I_P, A, W, or W_D.

## Compatibility with current assembly

Existing declarations remain unchanged:

```text
(P, δ) ↦ g
Γ(P,δ) = g
g : W → A
g ∈ 𝒢_adm(P)
L(g;P,θ) = E_θ[C_LOSS(g(W),W)]
R(P,θ) = OPT_{g ∈ 𝒢_adm(P)} L(g;P,θ)
```

P4 does not require P to have a function structure. The dependence of `𝒢_adm(P)` on P remains valid at the declared type level.

## Non-imported semantics

This declaration does not instantiate δ, θ, the structure of `𝒢_adm(P)`, the domain of L, the legality/existence conditions for `E_θ`, the exact R_OBJECT signature, R_ORACLE, Δ, FinLoss, or NECT.

No implementation, harness, measurement, data collection, profiling, experiment, STEP⑤, or STEP⑥ authorization is created.

## State transition

```text
R-INTERNAL-1 = P4 DECLARED
R_OBJECT     = NOT_DECLARED
R_ASSEMBLY   = OPEN
R_ORACLE     = NOT_DEFINED
Δ            = BLOCKED
FinLoss      = NOT LEGALLY AVAILABLE
NECT         = BLOCKED
STEP⑤       = NOT ENTERED
STEP⑥       = NOT ENTERED
```

## Next unresolved internal interfaces

Under R-ASSEMBLY-10 = M4, resolve remaining internal interfaces in dependency order. P type is now closed at the declared carrier/type level. The next open semantic field should be selected explicitly rather than inferred.
