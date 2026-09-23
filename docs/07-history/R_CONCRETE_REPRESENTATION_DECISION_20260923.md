# Concrete Representation Decision — P0 / θ0′

**Date**: 2026-09-23  
**Gate**: Concrete Representation Decision  
**Status**: REGISTERED  
**Decision**: 3 / FULL_VISIBLE_HISTORY_RULE_SPACE  
**Nature**: instance representation convention; no new R-INTERNAL semantic object

## 1. Decision

For the concrete instance `(P0,θ0′)`, the rule-level representation remains
the full visible-history rule space:

```text
𝒢_adm(P0)
  ↓
D_opt(P0,θ0′)
  ↓
V(P0,θ0′)
  ↓
R(P0,θ0′)
```

No realization quotient is introduced. No realized-history restriction is
imposed on `𝒢_adm(P0)` or `D_opt(P0,θ0′)`.

## 2. Semantic effect

The existing rule-level interfaces remain unchanged:

```text
Argmin(P0,θ0′)
  = {g∈D_opt(P0,θ0′) | L(g;P0,θ0′)=inf V(P0,θ0′)}

att(P0,θ0′) ⇔ Argmin(P0,θ0′)≠∅

uniq(P0,θ0′) ⇔ |Argmin(P0,θ0′)|=1
```

The four optimal realized action sequences continue to be exact only at the
realized-trajectory layer. Under the selected full rule-space representation,
they imply only:

```text
|Argmin(P0,θ0′)| ≥ 4.
```

The exact rule-level cardinality remains:

```text
exact |Argmin(P0,θ0′)| = OPEN.
```

## 3. Rejected or deferred alternatives

### Realization quotient

Declined for now. Identifying rules that have the same realized trajectory on
the point-mass workload is an object-identity change. It would require a formal
equivalence relation, quotient space, well-definedness of loss on classes, and
a separate account of uniqueness at equivalence-class level.

### Realized-history restriction

Declined for now. Restricting `𝒢_adm(P0)` to realized visible histories or
action sequences changes the instance optimization domain. Its conclusions may
not be silently identified with the current rule-level `R(P0,θ0′)`.

## 4. Continuity boundaries

This decision does not define a selector, canonical optimizer, `g*`, or
tie-breaking rule. It does not reopen R-INTERNAL or R_ASSEMBLY, does not define
R_ORACLE, does not unblock Δ/gap, FinLoss, or NECT, and does not enter
STEP⑤/STEP⑥. No implementation, harness, data collection, profiling,
measurement, or experiment authorization follows.

## 5. Next concrete surface

The next instance-level surface is to determine whether the full
visible-history rule representation, together with the current declarations,
determines the exact cardinality of `Argmin(P0,θ0′)`, or formally shows that
the point-mass instance underdetermines that cardinality because rule behavior
on unrealized visible histories is not constrained by the loss.

No new R-INTERNAL gate is opened by this decision.
