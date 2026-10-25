# P4-A Post-LOSS-5 Dependency Review

**Date:** 2026-09-23  
**Status:** CONCEPTUAL DEPENDENCY REVIEW / NO NEW SEMANTIC SELECTION / NO RQ REGISTRATION / NO EXPERIMENT AUTHORIZATION

## 1. Purpose

This review asks a narrower question after LOSS-5 resolution:

> Which parts of the historical P4-A proposition remain independently supported by the currently declared semantic objects, and which parts require the absent R layer?

This is a dependency review. It does not reopen STEP④-A / STEP④-B, does not select an R object, and does not redefine the historical estimand.

## 2. Current declared semantic chain

```
V_j ∈ ℝ^k
  ↓
C = [V_1,V_2,...]
  ↓
C_LOSS : D_C → ℝ
  ↓
D_C = A × W
```

The chain stops here.

Current declarations do not provide:

```
C_LOSS
  ↓
R(P;θ)
  ↓
R_oracle(θ)
  ↓
Δ(P;θ)
  ↓
FinLoss(P,θ)
```

LOSS-5 explicitly resolved R_OBJECT_SCHEMA = A, meaning no Risk / aggregate evaluation object is currently defined.

## 3. Dependency classification

### 3.1 Objects independently supported by current declarations

| Object / relation | Current status | Dependency |
|---|---|---|
| V_j | CURRENT / DECLARED | STEP④-A Value semantics |
| C = [V_1,V_2,...] | CURRENT / DECLARED | Binding_C = VECTOR_COMPOSITION |
| C_LOSS : D_C → ℝ | CURRENT / DECLARED | LOSS-3 + LOSS-4 |
| D_C = A × W | CURRENT / MFI PLACEHOLDER | LOSS-4 |
| finite-real pointwise cost evaluation | CURRENT / DECLARED | LOSS-3 |

These objects do not require an aggregate Risk / expectation object.

### 3.2 Objects not independently supported

| Object | Current status | Missing dependency |
|---|---|---|
| R(P;θ) | NOT_DEFINED_BY_CURRENT_FRAMEWORK | aggregate/evaluation object |
| R_oracle(θ) | NOT_DEFINED_BY_CURRENT_FRAMEWORK | oracle aggregate/reference object |
| Δ(P;θ) | BLOCKED | R, R_oracle and common subtraction semantics |
| FinLoss(P;θ) | NOT LEGALLY AVAILABLE | Δ and membership in the declared loss domain |
| D_X(P;θ) as historical decision-loss functional | NOT CURRENTLY INSTANTIATED | decision-loss functional above pointwise C_LOSS |
| historical F_AS,X target as an operational loss frontier | CONDITIONAL / HISTORICAL | decision-loss functional |

The last row is important: the historical STEP④ PASS established a candidate estimand frame, but the later Loss-layer audit shows that its decision-loss coordinate is not currently instantiated.

## 4. No retroactive invalidation of STEP④-A / STEP④-B

This review does not reopen the already declared:

```
VType            = VECTOR
OutputDiscipline = FINITE_REAL_COORDINATEWISE
Binding_C        = VECTOR_COMPOSITION
Value Discipline = COMPLETE
```

Nor does it declare the historical STEP④ PASS invalid.

The correct distinction is:

```
STEP④ semantic/value declarations
        = current and closed

historical STEP④ estimand frame
        = retained as historical/conditional formulation

current operational decision-loss object
        = not instantiated
```

Thus the issue is downstream dependency, not a contradiction in the Value layer.

## 5. What remains of P4-A without R

After removing the currently unavailable R layer, P4-A still contains a potentially meaningful lower-level structure:

```
architecture / computation
        ↓
Execution-State description
        ↓
semantic Value representation
        ↓
pointwise decision/workload cost interface C_LOSS
```

This establishes a cost-evaluation interface, but not yet a scalar decision criterion over strategies, workloads, regimes, or frontiers.

Therefore the following propositions cannot currently be evaluated as formal claims:

- one representation has lower decision loss than another;
- a projection preserves decision loss within a tolerance;
- a representation is on an achievable loss frontier;
- an oracle gap is finite;
- a nontrivial frontier exists under the historical STEP⑤ criterion.

## 6. What does not follow

The absence of R does not imply that P4-A is false.

Nor does it imply that C_LOSS is insufficient.

It only establishes:

```
C_LOSS alone does not instantiate the historical aggregate decision-loss layer.
```

Likewise, it does not justify silently replacing the missing layer with a sum, expectation, average, worst case, supremum, probability-weighted risk, empirical mean, or any other aggregate.

Any such replacement would be a new researcher semantic declaration.

## 7. Critical boundary discovered by the review

The current dependency boundary is:

```
                    CURRENT
                       │
V_j → C_VALUE → C_LOSS ├──── STOP
                       │
                    NO R OBJECT
                       │
                  HISTORICAL
                       │
             R → R_oracle → Δ
                       │
                  FinLoss
                       │
                    NECT
```

Therefore the unresolved question is no longer:

> Which formula should define FinLoss?

It is earlier:

> Is an aggregate decision-evaluation object above pointwise C_LOSS actually required by the research proposition?

That question has not been answered by the current framework.

## 8. Consequence for the P4-A proposition

Two logically distinct continuation directions exist, but neither is selected here.

### Direction A — Pointwise-cost research

P4-A could be reformulated so that its research claim terminates at a pointwise cost interface or another object that does not require an aggregate R layer.

This would be a new research formulation, not a silent continuation of historical STEP④/⑤.

### Direction B — Aggregate decision-loss research

If the intended P4-A claim genuinely requires comparing strategies over workloads/regimes, then an explicit object above C_LOSS is required.

That would require a fresh researcher declaration of the relevant object schema and its semantics.

No such declaration is made here.

## 9. Governance result

```
STEP④-A VALUE SEMANTICS     = CLOSED
STEP④-B VALUE DISCIPLINE    = COMPLETE
LOSS-3                       = CLOSED
LOSS-4                       = CLOSED
LOSS-5                       = RESOLVED AT CURRENT LEVEL
R_OBJECT                     = NOT_DECLARED
CURRENT LOSS CEILING         = C_LOSS
HISTORICAL R / Δ / FinLoss   = RETAINED, NOT INSTANTIATED
NECT                         = BLOCKED
STEP⑥                        = NOT ENTERED
RQ REGISTRATION              = NONE
EXPERIMENT AUTHORIZATION     = NONE
HARNESS AUTHORIZATION        = NONE
```

## 10. Review conclusion

The post-LOSS-5 review does not produce a new mathematical object.

It establishes only the dependency fact that:

> **The currently declared pointwise finite-real cost object C_LOSS is not, by itself, an aggregate decision-loss functional and therefore cannot instantiate the historical P4-A R → R_oracle → Δ → FinLoss chain.**

The next researcher decision, if continuation is desired, is therefore a proposition-level choice:

```
Does P4-A require an object above C_LOSS?
```

No answer is selected by this document.