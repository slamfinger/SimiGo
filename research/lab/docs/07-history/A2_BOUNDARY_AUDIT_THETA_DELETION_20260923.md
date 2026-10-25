# A2.0 Boundary Audit — Theta Deletion Test

**Date**: 2026-09-23  
**Status**: EXPLORATORY_AUDIT_REGISTERED / FORMALIZATION_NOT_AUTHORIZED  
**Nature**: reduction audit; no new semantic object, definition, route, implementation, or experiment

## 1. Audit criterion

The boundary test uses dependency, not subjective usefulness:

```text
A concept may remain in the candidate common core only if it remains
meaningful after all model-internal scientific methods are replaced by
an unknown black box 𝔅.
```

Internal mechanisms include transformer layers, attention, RoPE, MoE routing,
KV-cache implementation, sampling, training, search, and model-specific
mechanisms.

## 2. First-pass classification

| Concept | Candidate layer | Dependency result |
| --- | --- | --- |
| `P` | A candidate | Survives as problem/projection/observable-task structure when internals are black-boxed. |
| `δ` | C/B candidate | Current A2.0 does not require restoring historical `δ(I_P)`; decision-generation details are not core. |
| `𝒢_adm(P)` | A candidate | Survives as the externally admissible decision/behavior interface. It must not be expanded into internal rule mechanisms. |
| `Dom(L)` | A candidate | Survives as the question “can this behavior be legally evaluated?” |
| `V` | A candidate | Survives as the set of attainable evaluated behaviors. |
| `R` | A candidate | Survives as the value/evaluation boundary over admissible behavior. |
| `att / Argmin / uniq` | B candidate | Useful diagnostics for a frozen instance, but not required as common-core structure. |
| Rule identity | B/C candidate | May be finer than observational granularity; realized-trajectory equivalence is a separate future question. |
| `C0–C5` | A candidate | Describes the external declaration-to-execution boundary, not model internals. |

These are audit labels, not formal reclassifications.

## 3. Correction to the proposed theta deletion test

The proposed test assumed that `θ` may represent model-internal parameters. In
the registered Architecture 2.0 interface, however:

```text
θ : REGIME_PARAMETER
```

It is the external regime/evaluation-condition carrier, not model weights and
not the internal scientific method. In the concrete instance:

```text
θ0′ ↦ point measure on the deterministic exogenous workload W.
```

Therefore “delete model-internal parameters” is already a no-op with respect to
the current meaning of `θ`.

## 4. Three possible readings of “delete θ”

### Reading A — delete internal model parameters

This does not affect `θ`, because those parameters were never the registered
regime parameter.

### Reading B — delete the external evaluation regime

This breaks the A2.0 loop:

```text
W / μθ disappears
Eθ becomes undefined
Dom(L) loses its evaluation condition
V(P,θ) is undefined
R(P,θ) is undefined
Dom(R), att, Argmin, and uniq lose their registered scope
(P0,θ0′) is no longer a well-formed registered instance
```

So `θ` cannot be deleted wholesale if A2.0 retains evaluation.

### Reading C — freeze θ at one external regime

For a single frozen instance such as `θ0′`, the loop can remain meaningful:

```text
P0
𝒢_adm(P0)
Dom(L)
V(P0,θ0′)
R(P0,θ0′)=5376
att(P0,θ0′)=true
uniq(P0,θ0′)=false
C0–C5 external execution boundary
```

But this freezes the object at one regime and loses regime comparison,
sensitivity, and workload-family semantics.

## 5. Result

The black-box boundary should not delete `θ` wholesale. The better reduction is
to split it:

```text
Core dependency:
  there exists an external evaluation regime.

Possible Layer B:
  a variable regime family / comparable workloads.

Possible Layer C:
  concrete parameterization, measure representation,
  topology, coordinates, and implementation details.
```

Equivalently:

```text
Evaluation regime exists        = core dependency
Regime is a comparable variable = boundary question
Internal model parameters       = already outside the current θ interface
```

## 6. Directional conclusion

The audit supports the larger hypothesis that Architecture 2.0 should stop at
an executable/observable semantic boundary rather than explain model-internal
scientific methods.

However, the first concrete deletion test shows that the common core still needs
some notion of external evaluation regime. A minimal black-box structure would
therefore retain, at most, something like:

```text
observable task/projection
    +
admissible behavior interface
    +
external evaluation regime
    +
cost/evaluation
    +
trajectory/execution boundary
```

This is a candidate reduction direction only. It is not a new formal definition.

## 7. Boundaries

This audit does not redefine `P`, `θ`, `𝒢_adm`, `Dom(L)`, `V`, `R`, `att`,
`Argmin`, or `uniq`. It does not declare `[g]`, behavioral equivalence, a new
common core, `R-INTERNAL-20`, a route selection, R_ORACLE, Δ/gap, FinLoss,
NECT, STEP⑤/STEP⑥, implementation, harness, data collection, profiling,
measurement, or experiment authorization.
