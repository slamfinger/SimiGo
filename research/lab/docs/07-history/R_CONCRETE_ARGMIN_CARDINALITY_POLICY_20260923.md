# Concrete Argmin Cardinality Policy — P0 / θ0′

**Date**: 2026-09-23  
**Gate**: Concrete Argmin Cardinality Policy  
**Status**: REGISTERED  
**Decision**: ACCEPT_UNDERDETERMINATION / NO_RULE_DOMAIN_COMPLETION_NOW  
**Nature**: concrete-instance policy record; no new R-INTERNAL semantic object

## 1. Decision

The researcher accepted the registered underdetermination of the rule-level
argmin cardinality and decided not to introduce a visible-history domain
completion at this time:

```text
Concrete Argmin Cardinality Policy
  = ACCEPT_UNDERDETERMINATION / NO_RULE_DOMAIN_COMPLETION_NOW
```

## 2. Registered concrete facts

The current concrete instance registers only:

```text
R(P0,θ0′) = 5376
att(P0,θ0′) = true
uniq(P0,θ0′) = false
realized optimal action-sequence count = 4
|Argmin(P0,θ0′)| ≥ 4
exact |Argmin(P0,θ0′)|
  = UNDERDETERMINED_BY_CURRENT_DECLARATIONS
```

The value `4` remains exact only for realized optimal action sequences. It is
not registered as the number of rule-level `Argmin` elements.

## 3. Deferred surfaces

No visible-history domain completion is introduced. In particular, the policy
does not declare the full visible-history universe, totality requirements for
`h_t`, membership of unrealized histories in the admissible-rule domain, or
cardinality constraints on off-trajectory behavior.

No realization quotient is introduced. Rules that agree on the realized
trajectory under the point-mass workload remain distinct as rules.

## 4. Boundaries

This policy defines no selector, canonical optimizer, `g*`, or tie-breaking
rule. It does not reopen R-INTERNAL or R_ASSEMBLY, define R_ORACLE, unblock
Δ/gap, FinLoss, or NECT, or enter STEP⑤/STEP⑥. No implementation, harness,
data collection, profiling, measurement, or experiment authorization follows.

## 5. Forward condition

A future exact rule-level cardinality investigation may be opened only if a
concrete consumer requires it. Such an investigation must first complete the
visible-history domain and off-trajectory admissibility declarations. A
realization-identity discussion would remain a separate semantic surface.
