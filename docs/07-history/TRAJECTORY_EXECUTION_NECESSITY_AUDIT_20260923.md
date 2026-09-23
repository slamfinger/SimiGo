# Trajectory / Execution Necessity Audit

**Date**: 2026-09-23  
**Status**: AUDIT_REGISTERED / RESULT_CONCRETE_ONLY  
**Nature**: necessity audit over the current value-level core; no new semantic object or definition

## 1. Question

For the current value-level A2.0 core, is trajectory/execution:

```text
PRIMITIVE
DERIVED
CONCRETE-ONLY
```

The audited value-level interface is:

```text
P
θ
𝒢_adm(P) ⊆ {g | g:W→A}
Dom(L)
L(g;P,θ)=Eθ[C_LOSS(g(W),W)]
V(P,θ)={L(g;P,θ)}
R(P,θ)=inf V(P,θ)
```

No execution/trajectory interface is declared as a first-class component of this
value-level core.

## 2. Test A — derivation from the abstract core

From the abstract declarations alone, fix `P`, `θ`, and an admissible `g`. The
following are known:

```text
g(W) ∈ A
C_LOSS:A×W→ℝ
L=Eθ[C_LOSS(g(W),W)]
```

The following are not declared:

```text
initial state S0
transition map T:S×A→S
action-realization semantics
termination condition
observable trajectory carrier τ
time-indexed decomposition of A or C_LOSS
```

Therefore, at the abstract value-core level:

```text
τ cannot be derived from the current declarations.
```

This does not mean trajectory is meaningless. It means that derivation is not
licensed by the current value-level core.

## 3. Test B — concrete-instance derivation

In the registered concrete instance `P0/θ0′`, additional local semantics exist:

```text
P0 gives the projection and visible-information constraint.
θ0′ gives a deterministic exogenous workload W.
A={serve,defer,reject}.
FIFO handling, eviction-under-serve, KV usage, and horizon settlement are declared.
g is realized through visible decision history and per-round actions.
```

With those local declarations, the concrete trajectory can be derived from:

```text
P0 + θ0′ + g
```

including queue state, residency state, KV usage, feasibility, settlement, and
loss.

So the concrete instance supports local derivation, but only because its runtime
semantics were separately declared in the concrete instantiation gate.

## 4. Randomized-behavior pressure test

The current value-level core uses deterministic-looking:

```text
g:W→A
```

It does not register:

```text
g:S→Δ(A)
```

or a random source `ω`, or a trajectory distribution.

Therefore stochastic behavior is not a hidden dependency of the current value
core. If a future interface admits randomized behavior, this audit must reopen:
fixed `P,θ,g` may then induce a distribution over trajectories rather than a
single trajectory, and the meaning of `L` would require a separate stochastic
semantics decision.

## 5. Result

Relative to the current value-level core:

```text
trajectory/execution = CONCRETE-ONLY
```

More precisely:

```text
PRIMITIVE       = NO: no abstract trajectory/execution interface is declared.
DERIVED         = NO at abstract core level: derivation is not licensed by P,θ,g,W,A,C_LOSS alone.
CONCRETE-ONLY   = YES: P0/θ0′ locally declares enough runtime semantics for local derivation.
```

This does not prove that a general execution interface is unnecessary forever. It
proves only that it is not currently necessary for the registered value-level
object.

## 6. Consequence for A2.0

The result supports keeping A2.0, at present, as a value-level theory rather than
immediately expanding it into an execution theory.

It also prevents a premature move:

```text
do not infer “missing execution interface”
    ⇒
define a new primitive E/T/τ.
```

The correct current statement is narrower:

```text
trajectory/execution is locally derived inside the concrete instance,
but is not an abstract-core primitive and is not derivable from the abstract core.
```

## 7. Boundaries

This audit does not define trajectory, execution, state transition, initial
state, termination, behavioral equivalence, `[g]`, stochastic policy semantics,
an execution interface, `R-INTERNAL-20`, a route selection, R_ORACLE, Δ/gap,
FinLoss, NECT, STEP⑤/STEP⑥, implementation, harness, data collection, profiling,
measurement, or experiment authorization.
