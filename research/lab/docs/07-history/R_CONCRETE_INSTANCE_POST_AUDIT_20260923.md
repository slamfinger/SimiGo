# Concrete Instance Post-Audit — Definition Closure

**Date**: 2026-09-23  
**Gate**: Concrete Instance Post-Audit  
**Status**: AUDIT REGISTERED / D_OPT REPRESENTATION OPEN  
**Nature**: post-gate audit record; no new R-INTERNAL semantic object

## 1. Scope

This audit reviews the registered concrete instance `(P0,θ0′)` for
definition closure, the effective optimization domain, the value set,
and the value `R(P0,θ0′)=5376`. It does not open R-INTERNAL-20 and does
not change the concrete-instantiation gate.

## 2. Instance closure

The registered instance is precise enough for trajectory-value evaluation:

- `P0 := π0:S→B0` is the projection to the declared visible bundle
  `b=(KV headroom, |resident sessions|, execution phase)`, with
  `I_P0=σ(π0)`.
- `θ0′` is the point measure on the deterministic strict A/B workload
  with `K=8`, `L_A=512`, `D_A=256`, `L_B=1024`, `D_B=128`,
  `B=192 MiB`, and `λ=1280`.
- Actions are `serve`, `defer`, and `reject`; eviction is an execution
  mechanism under `serve`. FIFO handling and terminal settlement are as
  registered.

Two representation details are not fully closed at the abstract
decision-rule level:

1. The factors of `S=S1×⋯×S5` are not individually named. This does not
   block the audited trajectory calculation because decisions and loss
   use the induced visible history and registered runtime accounting,
   but it prevents calling the full raw-state instance definition
   complete.
2. The concrete gate describes rules by visible-history maps
   `a_t=h_t(V_t^g(W))`, while the registered cardinality argument counts
   realized action sequences in `A^8`. No quotient or restriction
   identifying distinct history-rule extensions that agree on the
   single point-mass workload has been registered.

The second point is material to `|Argmin|` and is recorded below.

## 3. Effective domain and value set

By the registered admissibility interface,

```text
D_opt(P0,θ0′)
  = {g∈𝒢_adm(P0) | (g,P0,θ0′)∈Dom(L)}.
```

The always-reject trajectory witnesses non-emptiness. Every served
session fits individually, and eviction-under-serve keeps usage within
`B`; therefore every realized action sequence is feasible under the
registered runtime accounting. The point-mass regime gives a finite
loss for each realized sequence. Hence:

```text
D_opt(P0,θ0′) ≠ ∅
V(P0,θ0′) ≠ ∅
inf V(P0,θ0′) ∈ ℝ
(P0,θ0′) ∈ Dom(R).
```

Under the realized-action-sequence representation, exhaustive
enumeration of all `3^8=6561` sequences gives 19 distinct realized
loss values, with minimum `5376` and maximum `10240`. The registered
global bound `18432` remains valid but is not tight.

## 4. Independent value verification

Two independent calculations were used:

1. exhaustive enumeration over all realized action sequences with FIFO,
   defer/reject queue handling, eviction-under-serve, and horizon
   settlement;
2. forward dynamic programming over `(FIFO queue, resident session)`
   states.

Both give:

```text
R(P0,θ0′)=inf V(P0,θ0′)=5376.
```

The four realized minimizing sequences are:

```text
(S,S,R,S,R,S,R,S)
(S,R,S,S,R,S,R,S)
(S,R,S,R,S,S,R,S)
(S,R,S,R,S,R,S,S)
```

Each has the closed form: switch residency to `B` exactly once at the
`k`-th B-round, `k∈{2,4,6,8}`. Its cost is
`512+1024+3×1280=5376`.

## 5. Argmin scoping

The number `4` is exact for **realized optimal action sequences**. It is
not yet established as the exact cardinality of the abstract rule-level
`Argmin(P0,θ0′)`, because distinct visible-history rule extensions may
agree on the one realized workload but remain distinct as rules.

Consequently, the currently rigorous rule-level statements are:

```text
att(P0,θ0′)=true
uniq(P0,θ0′)=false
|Argmin(P0,θ0′)| ≥ 4
```

with exact rule-level cardinality open until a representation convention
is selected. This scopes, rather than invalidates, the earlier
`|Argmin|=4` fact.

## 6. Boundaries

This audit creates no selector, canonical optimizer, `g*`, tie-breaking
rule, R_ORACLE, Δ/gap, FinLoss, NECT, new δ optimization domain, or
θ-level optimization. R-INTERNAL remains IDLE, R_ASSEMBLY remains
CLOSED, and STEP⑤/STEP⑥ remain NOT ENTERED. No implementation, harness,
data collection, profiling, measurement, or experiment authorization
follows from this record.

## 7. Next decision surface

The open decision is how to define the concrete candidate representation:

1. quotient rules by equality of their realized trajectory under the
   point-mass regime;
2. restrict `𝒢_adm(P0)` to realized visible histories/action sequences;
3. retain the full visible-history rule space and register only the
   lower bound `|Argmin|≥4`.

No option is selected by this audit.
