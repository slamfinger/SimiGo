# A2.0 Projection–Evaluation Distinctiveness Attack

**Date**: 2026-09-23  
**Status**: AUDIT_REGISTERED / RESULT_RECOVERABLE  
**Nature**: adversarial distinctiveness audit; no new semantic object, definition, route, implementation, or experiment

## 1. Question

Can a generic optimization schema preserve the current distinction between

```text
P  = projection side
θ  = evaluation-regime side
```

without importing A2.0-specific structure?

The alternatives were:

```text
SEMANTIC_COLLAPSE
RECOVERABLE
STRUCTURAL_DISTINCTIVENESS
```

## 2. Current formal roles

In the value-level core:

```text
P indexes 𝒢_adm(P).
θ indexes the expectation/evaluation regime.
R(P,θ)=inf V(P,θ).
```

Thus the current dependency is two-dimensional:

```text
same P + different θ  ⇒ potentially different evaluation.
different P + same θ  ⇒ potentially different admissible behavior interface.
```

## 3. Elimination attack on `P`

Treat `P` as an ordinary object.

A generic schema may define:

```text
H(P)=𝒢_adm(P)
c(g,P)=L(g;P,θ)
```

without using the word “projection.”

This preserves the formal dependency on `P`. What may be lost is only the external
interpretation that `P` is a projection with direction, domain/codomain, and
information loss.

Those richer properties are not currently load-bearing in the abstract value-level
formulas.

## 4. Elimination attack on `θ`

Treat `θ` as an ordinary object parameter.

A generic schema may define:

```text
μ(θ)
E(μ(θ),c)
R(P,θ)
```

again without calling `θ` an evaluation regime.

The formal dependency remains recoverable. The loss is interpretive, not formal.

## 5. Merge attack

Consider:

```text
(P,θ) ↦ O.
```

There are two cases.

### Destructive opaque merge

If `O` is an opaque object with no retained component structure, then the
distinction between:

```text
same P, different θ
different P, same θ
```

may be lost.

But this is not a neutral generic-schema requirement. It is a deliberately
destructive encoding.

### Product-object merge

A generic schema may instead choose:

```text
O=(P,θ).
```

Then:

```text
proj1(O)=P
proj2(O)=θ
H(O)=𝒢_adm(proj1(O))
μ(O)=regime(proj2(O))
R(O)=inf value under H(O),μ(O)
```

The two-dimensional dependency is preserved. The names `P` and `θ` may disappear,
but their roles can be recovered by the generic object structure.

## 6. Result

```text
SEMANTIC_COLLAPSE             = NOT ESTABLISHED
RECOVERABLE                   = YES at the current formal level
STRUCTURAL_DISTINCTIVENESS    = NOT ESTABLISHED
```

Therefore, the distinction between projection and evaluation regime is currently
recoverable by a generic schema using an ordinary product object.

This does not prove that A2.0 is useless. It does mean that A2.0 has not yet
proved a structural distinction between its value core and a generic optimization
schema at this level.

## 7. Interpretation

The roles of `P` and `θ` are currently:

```text
formally recoverable,
semantically meaningful,
but not yet irreducible structural evidence.
```

Richer projection properties—direction, domain/codomain, information loss, and
information constraint—may eventually produce genuine distinctiveness. In the
current value-level core, however, they are not sufficiently load-bearing to force
that conclusion.

## 8. Boundaries

This audit does not define a projection category, product object, information
structure, behavioral-equivalence relation, execution interface, `[g]`,
`R-INTERNAL-20`, route selection, R_ORACLE, Δ/gap, FinLoss, NECT, STEP⑤/STEP⑥,
implementation, harness, data collection, profiling, measurement, or experiment
authorization.
