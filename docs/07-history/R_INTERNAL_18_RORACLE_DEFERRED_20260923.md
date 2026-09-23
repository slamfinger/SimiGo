# R-INTERNAL-18 — ROr-4 / R_ORACLE_DEFERRED

**Date**: 2026-09-23  
**Status**: DEFERRED  
**Decision**: ROr-4 / DEFER R_ORACLE

## 1. Precondition

R-INTERNAL-17 / RO-1 has declared:

`R_OBJECT = R : Dom(R) → ℝ`

and retained Argmin / att / uniq as auxiliary objects. At the opening of R-INTERNAL-18:

- `R_ORACLE = NOT_DEFINED`
- `Δ = BLOCKED`
- gap/D is not declared
- STEP⑤ = NOT ENTERED

## 2. Researcher designation

The researcher explicitly designated:

`R-INTERNAL-18 = ROr-4`

The decision is to defer R_ORACLE rather than create a zero-content placeholder or prematurely commit to an oracle source/form.

## 3. Consumer analysis

No currently registered problem object consumes an oracle value.

Under RO-1, the registered primary object is R itself. The only plausible downstream role for an oracle in the historical chain is as a reference value entering a comparison/difference object. However:

- Δ remains BLOCKED;
- gap/D is not declared;
- STEP⑤ has not been entered.

Therefore there is currently no registered consumer requiring R_ORACLE.

## 4. Rejected alternatives

### ROr-1

`R_oracle : Dom(R_oracle) → ℝ` would leave both its domain and source unspecified, producing a zero-content placeholder rather than a substantive interface.

### ROr-2

`R_oracle(θ)` would add historical notation and prematurely commit to a regime-indexed form. A substantive θ-only oracle requires a declared P-free admissible class or other legitimate source, neither of which currently exists.

### ROr-3

A sourced theoretical benchmark requires the benchmark source and its domain to be declared first.

### ROr-5

A rule-layer oracle conflicts with the RO-1 value-functional object orientation and would reopen the rule layer without a registered need.

## 5. Declared boundary

R_ORACLE remains NOT_DEFINED.

This gate does not declare an oracle interface. Its output is the deferral boundary and the conditions for a future independent reopening.

Legitimate reopening is available through either of two independent routes:

A. A registered reference-value consumption problem appears, and that comparison surface first demonstrates a legitimate path that does not require reopening blocked Δ.

B. A structural gate declares an oracle source, such as a P-free admissible class or a theoretical benchmark, together with its definition/domain.

## 6. Explicit non-declarations

R-INTERNAL-18 does not introduce:

- gap / D / suboptimality in any form, including definitional placeholders;
- historical δ(I_P) or any new δ optimization domain;
- A(P,θ) or θ-level optimization;
- Δ, FinLoss, or NECT;
- selector, tie-breaking, canonical optimizer, or g*;
- topology, compactness, continuity, measurability, or finiteness/cardinality assumptions;
- implementation, harness, data collection, profiling, measurement, or experiment authorization.

Argmin / att / uniq remain auxiliary under RO-1 and are not altered or deleted.

## 7. State transition

`R_ORACLE = NOT_DEFINED` → remains `NOT_DEFINED`.

R_OBJECT remains `DECLARED (R : Dom(R) → ℝ)`.
R_ASSEMBLY remains OPEN.
Δ remains BLOCKED.
FinLoss remains NOT LEGALLY AVAILABLE.
NECT remains BLOCKED.
STEP⑤ and STEP⑥ remain NOT ENTERED.
EXPERIMENT AUTH = NONE.
HARNESS AUTH = NONE.

## 8. Continuity

This history record is registered together with synchronized updates to `docs/RESEARCH_STATE.md` and `docs/SESSION_CONTINUITY.md`. `docs/RESEARCH_STATE.md` remains the sole semantic authority.
