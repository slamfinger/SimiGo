# SimiGo-Lab — STEP④-A Canonical Decisions

**Date:** 2026-09-23
**Status:** ACTIVE / SEMANTIC INSTANTIATION REQUIRED
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


## 5. Explicit definition-layer gap

A concrete definition-layer gap is now explicitly declared. This does **not** instantiate any open semantic value.

**DG-4A-01 — Local-value / global-binding semantic boundary**

The current MCVSD declaration contract identifies (V_j) and (Binding_C), but it does not yet specify, at the semantic level, the exact role of (Binding_C) relative to an already-typed local value (V_j): specifically, whether (Binding_C) is only a relation among local values, also determines the semantic form of the composed result, or requires both aspects as one contract.

The gap is therefore:

```
V_j semantics
    ↓
[UNRESOLVED BOUNDARY]
    ↓
Binding_C semantics
    ↓
C semantics
```

This is a **definition gap**, not an experiment request. It does not authorize choosing sum, weighted sum, tuple, vector, record, or any other binding form.

### Resolution constraint

The gap may be resolved only by an explicit researcher semantic declaration or by a concrete semantic contradiction showing that the present contract is insufficient. No runtime representation, observed numerical agreement, cost/loss terminology, STEP⑤ notation, or engineering convention may resolve it implicitly.

Until resolved:

```
VType            = UNDECLARED
OutputDiscipline = UNDECLARED
Binding_C        = UNDECLARED
STEP4-B          = BLOCKED
STEP5            = BLOCKED
EXPERIMENT AUTH  = NONE
```

## 6. Downstream gate

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

## 7. Anti-regression rule

Only unresolved semantic choices necessary to instantiate STEP④-A are decision targets.

Formal support, notation, metadata, audit contracts, and downstream requirements SHALL NOT be promoted into new audit layers unless a concrete semantic contradiction is demonstrated.

Historical audit documents under `docs/07-history/` are retained as evidence.
