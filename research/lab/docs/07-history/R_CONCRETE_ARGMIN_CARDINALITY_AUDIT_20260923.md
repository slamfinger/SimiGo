# Concrete Argmin Cardinality Audit — P0 / θ0′

**Date**: 2026-09-23  
**Gate**: Concrete Argmin Cardinality Audit  
**Status**: REGISTERED  
**Result**: RULE_LEVEL_CARDINALITY_UNDERDETERMINED  
**Nature**: concrete-instance audit; no new R-INTERNAL semantic object

## 1. Question

Under the selected representation
`3 / FULL_VISIBLE_HISTORY_RULE_SPACE`, the audit question is whether the
current point-mass instance uniquely determines:

```text
|Argmin(P0,θ0′)|.
```

The answer is **no**. The current declarations do not determine the exact
rule-level cardinality.

## 2. Fixed loss and realized traces

Let `W0` denote the single deterministic workload in the support of the
point-mass regime `θ0′`. For a visible-history rule `g`, define its realized
decision trace by:

```text
T_g(W0)
  = ((V_t^g(W0), a_t))_{t=1}^8,
where
a_t = h_t(V_t^g(W0)).
```

Because `θ0′` is a point measure, both loss legality and loss value depend only
on this realized trace:

```text
T_g(W0)=T_g′(W0)
⇒
L(g;P0,θ0′)=L(g′;P0,θ0′).
```

For this fixed instance, trajectory feasibility is also evaluated on `W0`.
Hence two rules with the same realized trace have the same admissibility and
the same `D_opt` membership.

## 3. Extension lemma

Suppose `g∈Argmin(P0,θ0′)`, and suppose `v` is a visible-history decision
point not realized by `g` on `W0`. For each action `a∈A`, define `g_{v,a}` to
agree with `g` at every realized visible-history decision point, but assign
action `a` at `v`.

Then every `g_{v,a}` has the same realized trace and the same loss as `g`.
Consequently, if `g_{v,a}` is admissible under the current composite
admission predicate, then:

```text
g_{v,a} ∈ Argmin(P0,θ0′).
```

Thus unconstrained off-trajectory behavior creates distinct rule-level
minimizers without creating distinct realized minimizers.

## 4. Why the exact value is not determined

The four realized optimal action sequences are:

```text
(S,S,R,S,R,S,R,S)
(S,R,S,S,R,S,R,S)
(S,R,S,R,S,S,R,S)
(S,R,S,R,S,R,S,S)
```

They establish four realized minimizers and therefore the rule-level lower
bound:

```text
|Argmin(P0,θ0′)| ≥ 4.
```

However, the number of distinct rule-level minimizers depends on the size and
membership of the visible-history domains on which the maps `h_t` are defined.
The current registration does not explicitly declare:

1. the full universe of visible histories;
2. whether `h_t` must be total on that universe;
3. which unrealized visible histories belong to the admissible-rule domain;
4. any cardinality restriction on admissible extensions.

If each optimal realized trace had only its realized histories in its rule
domain, the trace count would give exactly four. If one admissible off-path
decision point were available per realized minimizer and all three actions
were legal assignments there, the lower bound would become at least
`4×3=12`. More off-path decision points would increase the count, potentially
without a finite bound unless the history universe and admissibility
constraints are declared.

Therefore neither `|Argmin|=4` nor any larger exact finite value follows from
the current instance data alone.

## 5. Registered audit facts

```text
R(P0,θ0′)=5376
att(P0,θ0′)=true
uniq(P0,θ0′)=false
realized optimal action-sequence count=4
|Argmin(P0,θ0′)| ≥ 4
exact |Argmin(P0,θ0′)| = UNDERDETERMINED_BY_CURRENT_DECLARATIONS
```

The distinction is mandatory:

```text
4 realized optimal action sequences
≠
4 rule-level Argmin elements.
```

## 6. Boundaries

This audit does not introduce a realization quotient, a realized-history
restriction, a selector, canonical optimizer, `g*`, or tie-breaking rule. It
does not reopen R-INTERNAL or R_ASSEMBLY, define R_ORACLE, unblock Δ/gap,
FinLoss, or NECT, or enter STEP⑤/STEP⑥. No implementation, harness, data
collection, profiling, measurement, or experiment authorization follows.

## 7. Next concrete decision surface

If an exact rule-level cardinality is wanted, a separate concrete rule-domain
completion is required. It must explicitly define the visible-history universe
and the admissibility constraints for off-trajectory behavior. Until then, the
cardinality remains underdetermined.
