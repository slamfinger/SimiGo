# SimiGo-Lab — LOSS-4 Cost Evaluation Interface

**Date:** 2026-09-23  
**Status:** ACTIVE / LOSS-4 DECLARATION COMPLETE  
**Authority:** Human researcher explicit semantic declaration

## 1. Researcher declarations

The following semantic declarations were explicitly made by the human researcher on 2026-09-23:

LOSS-4-C0  COST_INPUT_OBJECT = PAIR_DECISION_OUTPUT_WORKLOAD_INPUT
LOSS-4-C1  DECISION_OUTPUT   = ACTION / DECISION OUTPUT IN A
LOSS-4-C2  WORKLOAD_INPUT    = WORKLOAD OUTCOME IN W
LOSS-4-C3  DOMAIN_RULE       = D_C = A × W
LOSS-4-C4  DECISION_OUTPUT_POSITION = DECISION_OUTPUT IS AN ELEMENT POSITION IN A
LOSS-4-C5  WORKLOAD_INPUT_POSITION  = WORKLOAD_INPUT IS AN OUTCOME ELEMENT IN W; NOT A RANDOM VARIABLE
LOSS-4-C6  PRODUCT_STATUS    = D_C = A × W IS CURRENTLY MFI PLACEHOLDER

These are new semantic commitments at the Loss layer. They are not inferred from historical notation, runtime representation, observed values, engineering convention, STEP⑤ notation, or the previously frozen Value layer.

## 2. Cost input object

The input to C_LOSS is declared as a pair consisting of:

- a decision/action output in A;
- a workload outcome element in W.

Thus the declared input-domain rule is:

D_C = A × W

and the Loss interface may be written:

C_LOSS : D_C → ℝ

For every (a,w) ∈ D_C, C_LOSS(a,w) ∈ ℝ.

## 3. Decision-output position

DECISION_OUTPUT = ACTION / DECISION OUTPUT IN A.

The decision output is an element position in A.

This declaration does not additionally declare a complete mathematical structure for A, nor does it add action-space axioms, ordering, topology, measurability, or other structure.

## 4. Workload-input position

WORKLOAD_INPUT = WORKLOAD OUTCOME IN W.

The workload input is an outcome element in W.

It is explicitly NOT A RANDOM VARIABLE.

No probability-space, random-variable, measurability, distribution, expectation, or stochastic-process semantics are introduced by LOSS-4.

## 5. Product-status boundary

D_C = A × W is currently understood as an MFI placeholder.

This notation records the intended paired input position only. It does not, by itself, declare a global set-theoretic Cartesian-product foundation, type-theoretic product, tuple theory, projections, universal property, total/partial function semantics, or other internal product mathematics.

The unresolved global formal-basis issue remains separate.

## 6. Relation to LOSS-3

LOSS-4 instantiates the input side of the independent C_LOSS object declared in LOSS-3.

Therefore:

- C_LOSS remains independent of C_RBS;
- C_LOSS remains independent of C_COST_j;
- C_LOSS remains independent of C_VALUE;
- COST_DOMAIN = FINITE_REAL remains active;
- INFINITE_COST = NOT PRESENT remains active;
- C_DEFINEDNESS = TOTAL_ON_DECLARED_DOMAIN remains active.

Accordingly, for every declared input (a,w) ∈ D_C:

C_LOSS(a,w) ∈ ℝ

and the evaluation is defined.

## 7. Historical expression boundary

The historical expression C(δ(I_P), W) may now be connected to the Loss interface only at the declared role level as the candidate form:

C_LOSS(δ(I_P), w)

where w is a workload outcome element in W.

This does not yet establish:

- the mathematical type of I_P;
- the mathematical type of δ;
- the semantics of δ(I_P) beyond its declared decision-output role;
- the mathematical semantics of A;
- the mathematical semantics of W;
- the existence of an expectation;
- the definition of R(P;θ);
- the definition of R_oracle(θ);
- the definition of Δ(P;θ);
- FinLoss(P,θ); or
- NECT.

## 8. Current state

- LOSS-3 = CLOSED
- LOSS-4-C0 = ACCEPTED
- LOSS-4-C1 = ACCEPTED
- LOSS-4-C2 = ACCEPTED
- LOSS-4-C3 = ACCEPTED
- LOSS-4-C4 = ACCEPTED
- LOSS-4-C5 = ACCEPTED
- LOSS-4-C6 = ACCEPTED
- C_LOSS INPUT DOMAIN RULE = D_C = A × W
- PRODUCT SEMANTICS = MFI PLACEHOLDER ONLY
- R = BLOCKED
- R_oracle = BLOCKED
- Δ = BLOCKED
- FinLoss = NOT LEGALLY AVAILABLE
- NECT = BLOCKED
- STEP⑥ = NOT ENTERED
- EXPERIMENT AUTH = NONE
- HARNESS AUTH = NONE

## 9. Anti-regression constraint

LOSS-4 does not reopen the Value layer.

In particular:

- VType = VECTOR
- OutputDiscipline = FINITE_REAL_COORDINATEWISE
- Binding_C = VECTOR_COMPOSITION
- VD-01-D = SCALAR FUNCTIONAL / EXCLUDED
- VD-05-F = VALUE-TO-LOSS / DEFERRED

C_LOSS remains a new independent Loss-layer object.