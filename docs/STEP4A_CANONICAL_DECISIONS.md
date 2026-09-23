# SimiGo-Lab — STEP④-A Canonical Decisions

**Date:** 2026-09-23
**Status:** ACTIVE / DG-4A-01 RESOLVED / SEMANTIC INSTANTIATION COMPLETE / CONSISTENCY REVIEW PASSED
**Authority:** This file is the canonical decision surface for unresolved STEP④-A semantic choices. Historical audit documents remain evidence and are not re-opened unless a concrete semantic contradiction is identified.

## 1. Governance compression

MCVSD validity is complete:

```
MCVSD_VALIDITY_AUDIT = COMPLETE
MCVSD_RULING         = MCVSD_VALID

MCVSD_VALID_AS_DECLARATION_CONTRACT = TRUE
MCVSD_IS_COMPLETED_VALUE_SEMANTIC_DECLARATION = FALSE
```

No further formal-basis or metadata audit layer is created unless a concrete semantic contradiction requires it.

## 2. Current decision targets

The STEP④-A semantic choices have been explicitly instantiated by the human researcher:

```
SourceStatus     = NEW_DECLARATION
VType            = VECTOR
OutputDiscipline = FINITE_REAL_COORDINATEWISE
Binding_C        = VECTOR_COMPOSITION
```

These values were declared by the human researcher on 2026-09-23. The agent did not select them.

The DG-4A-01 boundary has been resolved separately:

```
DG_4A_01 = RESULT_FORM_DETERMINING
```

## 3. Abstract carriers retained

The following remain abstract carrier positions only:

```
J    = ABSTRACT INDEX CARRIER; MEMBERSHIP/COMPONENT SET UNDECLARED
A    = CARRIER SYMBOL ONLY
W    = CARRIER SYMBOL ONLY
W_D  = CARRIER SYMBOL ONLY
```

No set-theoretic, type-theoretic, product, quotient, image, or cardinality semantics are added by this document.

## 4. Deferred dimensions

```
Order           = DEFERRED
Measurability   = DEFERRED
```

Scalarity, finiteness, nonnegativity, and special-value admissibility are now governed by the declared `OutputDiscipline = FINITE_REAL_COORDINATEWISE`. `Measurability` remains deferred. Positional order is intrinsic to the declared vector structures and is not a separate measurement-order claim.

Infinity semantics remain undeclared:

```
LOSS_INFINITY_PREDEFINED = FALSE
IPR_VALUE                = UNDECLARED
```

The old STEP⑤ `[0,+infinity]` notation does not acquire STEP④ meaning through this document.

## 5. Binding boundary

`Binding_C` has now been instantiated by the human researcher as `VECTOR_COMPOSITION`.

Because `DG_4A_01 = RESULT_FORM_DETERMINING`, this declaration determines the semantic form of the composed result `C`, and the local-to-global relation is derived from that form. It does not rely on runtime representation, observed numerical agreement, cost/loss terminology, STEP⑤ notation, or engineering convention.

## 5.1 Researcher semantic instantiation (2026-09-23)

Declared by the human researcher:

**VType = VECTOR**

```
V_j ∈ ℝ^k,  V_j = (v_{j,1}, ..., v_{j,k})
```

- Expresses: each local value is a homogeneous multi-coordinate object; multi-dimensional structure is preserved.
- Excludes: scalar compression (`SCALAR`), extended-real values, and typed-record semantics at this layer.

**OutputDiscipline = FINITE_REAL_COORDINATEWISE**

```
every coordinate v_{j,i} ∈ ℝ with |v_{j,i}| < ∞
```

- Expresses: admissible values are ordinary finite reals, applied to every coordinate of every `V_j` (the researcher's `V_j ∈ ℝ`, `|V_j| < ∞` is applied coordinate-wise so that it is consistent with `VType = VECTOR`).
- Excludes: `+∞` / `−∞`, `NaN`, missing or undefined coordinates. Sign and nonnegativity are not constrained by this declaration.

**Binding_C = VECTOR_COMPOSITION**

```
C = [V_1, V_2, V_3, ...]  (the composed result C is itself a vector object)
```

- Expresses: under `DG_4A_01 = RESULT_FORM_DETERMINING`, the semantic form of `C` is a vector whose entries are the declared local values; component identity and multiplicity are preserved; the local-to-global relation follows from this form.
- Excludes: additive aggregation (sum, weighted sum, mean/max/min), tuple-as-distinct-contract, record/field semantics, and any aggregation that compresses local values into a single scalar.

## 6. Explicit definition-layer gap resolution

A concrete definition-layer gap was explicitly declared. Its resolution does **not** instantiate any open semantic value.

**DG-4A-01 — Local-value / global-binding semantic boundary**

The MCVSD declaration contract identified `(V_j)` and `Binding_C`, but it did not specify, at the semantic level, the exact role of `Binding_C` relative to an already-typed local value `(V_j)`: specifically, whether `Binding_C` is only a relation among local values, also determines the semantic form of the composed result, or requires both aspects as one contract.

The gap is therefore:

```
V_j semantics
    ↓
[RESOLVED BOUNDARY]
    ↓
Binding_C semantics
    ↓
C semantics
```

This is a **definition gap**, not an experiment request. It does not authorize choosing sum, weighted sum, tuple, vector, record, or any other binding form.

### 6.1 Minimum resolution questions

DG-4A-01 was reduced to three definition questions. They are now answered by the researcher resolution below.

**Q1 — What is the semantic status of the local value before binding?**

`VType` remains the declaration site for the semantic type of each `(V_j)`. `Binding_C` does not replace, repair, or implicitly complete `VType`.

```
V_j
 ↓
[VType]
 ↓
already semantically typed?
```

**Q2 — What is the semantic role of `Binding_C`?**

Among the possible declaration contracts, is `Binding_C`:

- only a relation/operator over already-typed local values;
- a relation/operator that also declares the semantic form of the resulting (C);
- or a single coupled contract that declares both the binding relation and the result semantics?

The human researcher selected `RESULT_FORM_DETERMINING`.

**Q3 — Where does the semantic type of (C) live?**

If (C) has a semantic type distinct from the local (V_j), is that type:

- determined by the declared `Binding_C`;
- declared independently;
- or intentionally left abstract at STEP④-A?

The semantic type of `(C)` is determined by the future concrete `Binding_C` declaration; it remains undeclared until that selection is made.

### 6.2 Boundary test

The minimum test for resolving DG-4A-01 is:

```
Local semantic contract
        ↓
      V_j
        ↓
   Binding_C
        ↓
      C
```

A valid resolution must make the semantic dependency at this interface explicit:

1. (V_j) must have a declared semantic status sufficient for whatever `Binding_C` is declared to act upon;
2. `Binding_C` must have an explicitly declared semantic role;
3. the semantic status of (C) must not be silently inferred from notation, runtime representation, observed values, loss/cost terminology, or engineering convention.

This test does **not** require choosing a particular type, operator, aggregation, or result representation.

### 6.3 Researcher resolution

The human researcher has explicitly adopted `RESULT_FORM_DETERMINING`.

```
DG_4A_01_RESOLUTION = RESULT_FORM_DETERMINING
DECLARATION_SOURCE  = HUMAN_RESEARCHER_EXPLICIT_DECLARATION
RESOLUTION_STATUS   = EFFECTIVE
RESOLUTION_DATE     = 2026-09-23
```

The semantic content is:

```
LOCAL_RELATION_ROLE = DERIVED
RESULT_FORM_ROLE    = PRIMARY_AND_DETERMINING
ROLE_COUPLING       = FORM_DETERMINES_RELATION
C_FORM_STATUS       = DETERMINED_BY_BINDING_C
```

Therefore, `Binding_C` is not a mere relation among local values. Its future explicit selection will determine the semantic form of the composed result `C`; the local-to-global relation follows from that form. No concrete binding form is instantiated by this resolution.

This resolution excludes:

```
RELATION_ONLY
SEPARATE_C_FORM_OUTSIDE_BINDING_C
IMPLICIT_C_FORM
```

It also excludes deriving `C` semantics from runtime representation, serialization or storage format, observed numerical agreement, cost/loss terminology, STEP⑤ notation, or engineering convenience.

Future concrete `Binding_C` candidates are valid only if they:

1. explicitly give the semantic form of `C`;
2. make the local-to-global relation derivable from that form;
3. do not implicitly define `J` membership, ordering, or cardinality;
4. do not give `A`, `W`, or `W_D` shape, numeric semantics, or runtime representation merely through binding.
### Resolution constraint

The gap may be resolved only by an explicit researcher semantic declaration or by a concrete semantic contradiction showing that the present contract is insufficient. No runtime representation, observed numerical agreement, cost/loss terminology, STEP⑤ notation, or engineering convention may resolve it implicitly.

The definition-layer gap is resolved. The semantic instantiation targets are now closed:

```
VType            = VECTOR
OutputDiscipline = FINITE_REAL_COORDINATEWISE
Binding_C        = VECTOR_COMPOSITION
```

The downstream gate is updated:

```
STEP4-B          = UNBLOCKED (NEXT: after Value Discipline)
STEP5            = BLOCKED
EXPERIMENT AUTH  = NONE
```

## 6.4 Downstream consistency review (single required review)

Performed after instantiation, per the allowed action "对新的 semantic instantiation 做一次必要的下游一致性审查". Result: **PASSED — no semantic contradiction found.**

| Check | Result | Notes |
|---|---|---|
| NDAC | NO CONFLICT | NDAC status unchanged |
| SAT_INF_FIN | NO CONFLICT | STEP⑤ target-layer definition untouched |
| Domain partition | NO CONFLICT | Adopted partition stands |
| IPR | NO CONFLICT | `+∞` excluded at the `V_j` layer by OutputDiscipline; envelope-layer `IPR_VALUE` remains UNDECLARED; `LOSS_INFINITY_PREDEFINED = FALSE` stands |
| `A / W / W_D` | NO CONFLICT | Remain carrier symbols only |
| `J` | NO CONFLICT | `J` remains an abstract index carrier; recorded constraint: vector dimension `k` and `C`'s coordinate structure SHALL NOT be silently identified with `J` membership or cardinality; no ordering of `J` is invented by the vector form |
| STEP⑤ boundary | NO CONFLICT | NECT mode remains blocked; no experiment authorization |
| DG-4A-01 validity conditions | SATISFIED | (1) explicit semantic form of `C` given; (2) local-to-global relation derivable from that form; (3) no implicit definition of `J` membership/ordering/cardinality; (4) no shape or numeric semantics added to `A`, `W`, `W_D` |

## 7. Downstream gate

The current decision targets are instantiated and have passed the required review. Therefore:

```
VALUE DISCIPLINE     = OPEN (NEXT ACTION)
STEP4-B RISK         = OPEN (AFTER VALUE DISCIPLINE)
FinLoss              = BLOCKED
RESIDUAL STATUS      = BLOCKED
NECT MODE            = BLOCKED
STEP⑥                = NOT ENTERED
RQ                   = NOT ASSIGNED
EXPERIMENT AUTH      = NONE
```

## 8. Anti-regression rule

Only unresolved semantic choices necessary to instantiate STEP④-A are decision targets.

Formal support, notation, metadata, audit contracts, and downstream requirements SHALL NOT be promoted into new audit layers unless a concrete semantic contradiction is demonstrated.

Historical audit documents under `docs/07-history/` are retained as evidence.
