# Concrete Instance Facts — P0 / θ0′

**Date**: 2026-09-23  
**Status**: REGISTERED  
**Nature**: post-gate computational fact record (no new semantic object)

## 1. Source

Facts derived from the registered Concrete Instantiation gate
(docs/07-history/R_CONCRETE_INSTANTIATION_P0_THETA0_20260923.md, commit a95df3a).
This record adds no semantic object and reopens no chain.

## 2. Registered facts

```
R(P0,θ0′) = 5376

att(P0,θ0′) = true

Argmin(P0,θ0′) ≠ ∅  and  |Argmin(P0,θ0′)| = 4

uniq(P0,θ0′) = false
```

## 3. Derivation chain

(a) The admissible action-sequence space is finite: A^8 with |A^8| = 3^8 = 6561.
Under the deterministic point-mass regime each admissible sequence induces exactly
one trajectory and one per-trajectory cost.

(b) Hence V(P0,θ0′) is finite and non-empty; a finite non-empty subset of R
contains its infimum; therefore inf V ∈ V, and by the K4-A definition
att(P0,θ0′) = true.

(c) By the K4-B bridge, Argmin(P0,θ0′) ≠ ∅.

(d) Exhaustive enumeration of all 6561 sequences (FIFO queue, eviction-under-serve,
horizon settlement) cross-checked by an independent per-round dynamic program over
the resident-session state gives min = 5376.

(e) The minimizer family has the closed form: switch residency to B exactly once at
the k-th B-round, k ∈ {2,4,6,8}, with cost 512 + 1024 + 3×1280 = 5376 independent
of k. Hence exactly |Argmin| = 4, and by the K4-C definition uniq(P0,θ0′) = false.

Representative minimizers (S=serve, R=reject):

```
g1 = (S,S,R,S,R,S,R,S)
g2 = (S,R,S,S,R,S,R,S)
g3 = (S,R,S,R,S,S,R,S)
g4 = (S,R,S,R,S,R,S,S)
```

Non-minimizing benchmarks registered earlier: always-serve-with-evict = 6144;
retain-A/reject-B = 5632. The exact optimum 5376 differs from both.

## 4. Boundaries

This record does not declare a selector, canonical optimizer, or g*; uniq = false
independently blocks canonical selection. R_ORACLE remains NOT_DEFINED; Δ/gap remain
blocked; STEP⑤/STEP⑥ remain NOT ENTERED; no implementation, harness, measurement,
or experiment authorization exists. R-INTERNAL remains IDLE; R_ASSEMBLY remains CLOSED.

## 5. Registration note

An earlier incomplete registration attempt (blob dd2e66e, temp commit 706c605) was
abandoned unreferenced before main was moved; this document is the authoritative
record of the same audited content.
