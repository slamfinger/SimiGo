# SimiGo-Lab — LOSS-3 Cost Declarations

**Date:** 2026-09-23  
**Status:** ACTIVE / LOSS-3 DECLARATION COMPLETE  
**Authority:** Human researcher explicit semantic declaration

## 1. Researcher declarations

The following four semantic declarations were explicitly made by the human researcher on 2026-09-23:

LOSS-3-C0  C_LOSS_OBJECT = NEW_INDEPENDENT_C_LOSS
LOSS-3-C1  COST_DOMAIN   = FINITE_REAL
LOSS-3-C2  INFINITE_COST = NOT_PRESENT
LOSS-3-C3  C_DEFINEDNESS = TOTAL_ON_DECLARED_DOMAIN

These are new semantic commitments at the Loss layer. They are not inferred from historical notation, runtime representation, observed values, engineering convention, STEP⑤ notation, or the previously frozen Value layer.

## 2. Independent Loss object

`C_LOSS` is a new independent cost/loss object.

It SHALL NOT be silently identified with any historically reused `C` symbol, including:

- `C_RBS`
- `C_COST_j`
- `C_VALUE`

Current semantic identities remain undeclared:

- `C_RBS ↔ C_COST_j` = UNDECLARED
- `C_COST_j ↔ C_VALUE` = UNDECLARED
- `C_RBS ↔ C_VALUE` = UNDECLARED

The declaration `C_LOSS_OBJECT = NEW_INDEPENDENT_C_LOSS` does not establish any of these identities.

## 3. Cost domain

`C_LOSS` has finite-real output:

`COST_DOMAIN = FINITE_REAL`

For every input in its declared domain, `C_LOSS(x) ∈ ℝ` and the output is finite.

No extended-real cost value is introduced by this declaration.

## 4. Infinite-cost semantics

`INFINITE_COST = NOT_PRESENT`

Therefore `+∞` and `−∞` are not legitimate output values of `C_LOSS`.

This declaration does not by itself determine how any historical `+∞` notation elsewhere in the research corpus should be interpreted. In particular, `LOSS_INFINITY_PREDEFINED = FALSE` remains unchanged for unrelated historical layers.

## 5. Definedness

`C_DEFINEDNESS = TOTAL_ON_DECLARED_DOMAIN`

For every input belonging to the declared domain of `C_LOSS`, the cost evaluation is defined and returns a finite real.

This is a totality declaration relative to the declared domain. It does not yet specify the domain itself, nor does it define the semantic type of `δ`, `I_P`, or `W`.

## 6. Boundary preserved

These declarations resolve the Cost Codomain Gate only.

They do not yet derive `R(P;θ)`, `R_oracle(θ)`, `Δ(P;θ)`, `FinLoss(P,θ)`, or NECT.

In particular, finite-real output of `C_LOSS` does not by itself establish existence or finiteness of an expectation, an infimum, an oracle baseline, or a residual.

The next required gate remains `LOSS-4 = Cost Evaluation Interface`, with the remaining questions:

1. what object `δ(I_P)` denotes;
2. what the declared input domain of `C_LOSS` is;
3. whether `(δ(I_P),W)` lies in that domain;
4. whether the totality declaration therefore applies to the historical evaluation expression.

## 7. Current state

- LOSS-3-C0 = ACCEPTED
- LOSS-3-C1 = ACCEPTED
- LOSS-3-C2 = ACCEPTED
- LOSS-3-C3 = ACCEPTED
- C_LOSS = NEW INDEPENDENT OBJECT
- COST DOMAIN = FINITE_REAL
- INFINITE COST = NOT PRESENT
- DEFINEDNESS = TOTAL ON DECLARED DOMAIN
- R = BLOCKED
- R_oracle = BLOCKED
- Δ = BLOCKED
- FinLoss = NOT LEGALLY AVAILABLE
- NECT = BLOCKED
- STEP⑥ = NOT ENTERED
- EXPERIMENT AUTH = NONE
- HARNESS AUTH = NONE

## 8. Anti-regression constraint

No Value-layer semantic decision is reopened by LOSS-3.

- `VType = VECTOR`
- `OutputDiscipline = FINITE_REAL_COORDINATEWISE`
- `Binding_C = VECTOR_COMPOSITION`
- `VD-01-D = SCALAR FUNCTIONAL / EXCLUDED`
- `VD-05-F = VALUE-TO-LOSS / DEFERRED`

`C_LOSS` is therefore an independent Loss-layer object rather than a scalarization or reinterpretation of `C_VALUE`.