# SimiGo-Lab — STEP④-A Canonical Decisions

**Date:** 2026-09-23
**Status:** ACTIVE / DG-4A-01 RESOLVED / SEMANTIC INSTANTIATION REQUIRED
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

Only the following STEP④-A semantic choices are currently open for explicit researcher instantiation:

```
SourceStatus     = NEW_DECLARATION
VType            = UNDECLARED
OutputDiscipline = UNDECLARED
Binding_C        = UNDECLARED
```

The agent SHALL NOT select these values.

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

Scalarity, finiteness, nonnegativity, special-value admissibility, and related output restrictions belong to the eventual `OutputDiscipline` instantiation and are not separately preselected here.

Infinity semantics remain undeclared:

```
LOSS_INFINITY_PREDEFINED = FALSE
IPR_VALUE                = UNDECLARED
```

The old STEP⑤ `[0,+infinity]` notation does not acquire STEP④ meaning through this document.

## 5. Binding boundary

`Binding_C` remains a separate open semantic choice. This document does not select sum, tuple, vector, record, product, or any other aggregation.

Because `DG_4A_01 = RESULT_FORM_DETERMINING`, any future concrete `Binding_C` declaration must determine the semantic form of the composed result `C`. The local-to-global relation is then derived from that semantic form. A future `Binding_C` declaration SHALL NOT rely on runtime representation, observed numerical agreement, cost/loss terminology, STEP⑤ notation, or engineering convention to determine `C` implicitly.

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

The definition-layer gap is resolved. The following semantic instantiation targets remain open:

```
VType            = UNDECLARED
OutputDiscipline = UNDECLARED
Binding_C        = UNDECLARED
```

The downstream gate remains unchanged:

```
STEP4-B          = BLOCKED
STEP5            = BLOCKED
EXPERIMENT AUTH  = NONE
```

## 7. Downstream gate

Until the current decision targets are explicitly instantiated and subsequently reviewed:

```
VALUE DISCIPLINE     = BLOCKED
STEP4-B RISK         = BLOCKED
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
