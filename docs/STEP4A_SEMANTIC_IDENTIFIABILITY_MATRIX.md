# SimiGo-Lab — STEP④-A Semantic Identifiability Matrix

**Date:** 2026-09-23
**Status:** DECISION SUPPORT ONLY / NO SEMANTIC INSTANTIATION
**Scope:** STEP④-A semantic analysis only

> This document is a decision-support artifact. It does not instantiate `VType`, `OutputDiscipline`, or `Binding_C`, and it does not authorize experiment, implementation, measurement, or STEP⑤ entry.

## 1. Governance boundary

Current canonical semantic state remains:

```
SourceStatus     = NEW_DECLARATION
VType            = UNDECLARED
OutputDiscipline = UNDECLARED
Binding_C        = UNDECLARED

J   = ABSTRACT INDEX CARRIER
A   = CARRIER SYMBOL ONLY
W   = CARRIER SYMBOL ONLY
W_D = CARRIER SYMBOL ONLY

Order         = DEFERRED
Measurability = DEFERRED
```

The canonical state is defined by `docs/RESEARCH_STATE.md` and `docs/STEP4A_CANONICAL_DECISIONS.md`. This document does not supersede either file.

Explicitly:

```
VType selection              = NOT PERFORMED
OutputDiscipline selection   = NOT PERFORMED
Binding_C selection          = NOT PERFORMED
Experiment authorization     = NONE
Implementation authorization = NONE
Measurement authorization    = NONE
STEP4-B                      = BLOCKED
STEP5                       = BLOCKED
```

## 2. Purpose

The purpose is to distinguish three questions that must not be conflated:

1. **Semantic distinction:** Are two candidate declarations formally different?
2. **Observational distinguishability:** Can some currently admissible observation produce different consequences under those candidates?
3. **Semantic declaration:** Has the human researcher explicitly adopted one candidate as the research semantics?

Only (1) is purely definitional. (2) concerns potential empirical constraint. (3) remains a researcher declaration.

A candidate can therefore be:

- formally distinct but observationally equivalent under the current observation frame;
- empirically constrainable without being uniquely identifiable;
- compatible with all current evidence without thereby becoming the declared semantics.

## 3. Working identifiability relation

For candidate semantics (S_1,S_2) and an observation frame (O):

```
Potentially distinguishable
    iff
there exists an admissible observation condition x
such that O(S1, x) != O(S2, x)
```

Conversely, if under the current observation frame:

```
for all admissible x:
    O(S1, x) = O(S2, x)
```

then (S_1) and (S_2) are observationally equivalent under that frame.

This does **not** mean the semantics are formally identical. It means the current observation layer cannot distinguish them.

No experiment is authorized by this definition.

## 4. VType candidate matrix

| Candidate | Semantic commitment | Structure retained | What it rules out / constrains | Potential observable distinction | If no distinction |
|---|---|---|---|---|---|
| Scalar | (V_j) is a single scalar value | One value with scalar semantics | Requires any relevant phenomenon to be representable without semantically distinct coordinates | Architecture case where independent, non-compressible dimensions are required | Scalar and richer types may remain observationally equivalent under current observation |
| Vector | (V_j) is a vector with declared coordinates | Multiple homogeneous dimensions | Requires coordinate semantics and eventually comparison/aggregation rules | Architecture case where multiple homogeneous dimensions are jointly necessary and cannot be collapsed without semantic loss | Vector may be observationally equivalent to a scalar projection |
| Typed record | (V_j) is a structured record with named/typed fields | Heterogeneous field semantics | Prevents treating semantically different fields as anonymous coordinates | Architecture case where field identity/type is necessary to preserve meaning | Record may collapse observationally to a scalar/vector projection |
| Other structure | A separately defined value object | Structure specific to the phenomenon | Requires its own semantic contract | Any architecture counterexample targeting simpler candidates | Remains an undeclared alternative until explicitly instantiated |


### VType boundary audit

For STEP④-A purposes, `VType` denotes the **semantic value type of (V_j)**. It must not be inferred from:

- the number of numerical fields observed;
- a scalar projection of a richer object;
- serialization or storage format;
- runtime data structures;
- tensor/array representation.

Accordingly:

```
semantic value type
    !=
representation format
    !=
runtime data structure
```

The candidate list is therefore a decision-support partition, not an assertion that every listed representation is a distinct ontology.

### OutputDiscipline boundary audit

The candidate space currently contains several kinds of admissibility considerations. This is intentional as a provisional decision-support frame, but it must not silently expand into additional canonical decision targets.

`OutputDiscipline` concerns admissibility restrictions on (V_j). It does not, by itself, instantiate:

```
Order
Measurability
Binding_C
Observation frame
Runtime representation
```

Whether missingness/partiality belongs inside the eventual OutputDiscipline declaration remains UNDECLARED.

### Binding_C orthogonality audit

The current Binding_C candidate list contains both aggregation-style relations (for example, sum or max) and composition/result-form possibilities (for example, tuple or record).

This is recorded as a **potential internal orthogonality issue**, not as a new decision axis.

```
aggregation relation
        ?
composition / result form
```

No automatic split into separate semantic variables is authorized. Such a split would itself require explicit researcher instantiation.

### Observation-frame boundary audit

The symbol (O) in the identifiability relation denotes only an **abstract observation frame used to define potential observational distinguishability**.

```
O = abstract discrimination frame
O != declared experimental observable
O != authorized measurement protocol
```

Therefore the existence of (O) in this matrix does not authorize experiment, data collection, profiling, or measurement.

### VType discipline

Observation of multiple numbers does not establish vector semantics.

Observation of a scalar output does not establish scalar ontology.

A type candidate can be empirically constrained by architecture counterexamples, but the experiment cannot itself perform the formal declaration.

## 5. OutputDiscipline candidate matrix

| Candidate | Semantic commitment | Admissible-value consequence | What it excludes / constrains | Potential observable distinction | Declaration requirement |
|---|---|---|---|---|---|
| Finite real | Outputs must be finite real values | Excludes infinities and non-finite special values | Any interpretation requiring infinity or non-finite output | Observation of a genuinely semantically required non-finite case can challenge the candidate | Researcher must state that such cases are inadmissible |
| Nonnegative finite real | Outputs are finite and nonnegative | Excludes negative and non-finite values | Requires nonnegativity to have semantic justification | A genuinely negative semantic value can challenge the candidate | Nonnegativity cannot be imported from convenience |
| Extended real | Output domain admits explicitly declared infinite values | May admit (+infty) and/or (-infty) according to declaration | Excludes interpreting infinity as merely undefined unless separately stated | A boundary case requiring an infinite value can constrain alternatives | Meaning and propagation of infinity must be explicit |
| Componentwise discipline | Different components/fields may have distinct admissibility rules | Discipline follows declared component semantics | Rejects an implicit single global rule | Architecture cases where components have irreducibly different domains | Component domains and rules must be explicit |
| Missing/partial-admitting | Missing/undefined states may be admissible outputs | Distinguishes missing/undefined from ordinary values | Excludes treating every non-value as measurement failure or outside-domain without declaration | Architecture cases with semantically meaningful absence/undefinedness | Meaning of missingness and its downstream behavior must be explicit |

### OutputDiscipline boundary

Observed occurrence and semantic admissibility are different propositions:

```
Observed case exists
    !=
case is a valid V_j
```

In particular:

```
LOSS_INFINITY_PREDEFINED = FALSE
IPR_VALUE                = UNDECLARED
```

remains unchanged. Historical STEP⑤ notation does not instantiate STEP④ output semantics.

## 6. Binding_C candidate matrix

| Candidate | Semantic commitment | Structure retained | What it rules out / constrains | Potential observable distinction | Declaration requirement |
|---|---|---|---|---|---|
| Sum | Overall value is additive composition of local values | Additive contribution | Non-additive interaction as the defining relation | Interaction/nonlinearity that cannot be represented by addition | Common additive space and meaning of addition must be explicit |
| Weighted sum | Local values contribute through declared weights | Weighted additive contribution | Unweighted contribution and arbitrary weights | Stable architecture behavior requiring nontrivial weighting | Weight source, units, and semantic basis must be explicit |
| Mean / max / min | Overall output is determined by a specific aggregation rule | Selected summary relation | Component-preserving interpretations | Cases where different aggregators yield different semantic predictions | Order and aggregation semantics must be declared |
| Tuple | Overall output preserves multiple local values as ordered components | Component identity and multiplicity | Forced scalar compression | Cases where component identity/order matters | Ordering and membership semantics must be explicit |
| Vector composition | Overall output is a homogeneous multi-coordinate object | Multiple coordinates | Heterogeneous field semantics | Cases where coordinates are jointly interpreted as one homogeneous object | Dimension semantics must be explicit |
| Record composition | Overall output preserves named heterogeneous components | Field identity and types | Anonymous coordinate treatment | Cases where field identity/type changes interpretation | Field schema and field-level discipline must be explicit |
| Other binding | A separately defined local-to-global relation | Relation-specific structure | Any default aggregation assumption | Architecture counterexample specific to competing bindings | Full relation must be explicitly defined |

### Binding_C boundary

Numerical agreement does not establish binding semantics.

For example:

```
V1 = 3
V2 = 5
C = 8
```

is compatible with additive composition, but does not by itself establish:

```
Binding_C = sum
```

Likewise, preservation of multiple values does not by itself establish tuple, vector, or record semantics.

## 7. Cross-semantic interaction matrix

The three decisions are independent semantic axes.

| Combination issue | Constraint |
|---|---|
| VType × OutputDiscipline | A type does not automatically determine finiteness, nonnegativity, infinity, missingness, order, or measurability |
| VType × Binding_C | Scalar local values do not imply additive binding; vector local values do not imply concatenation or vector binding |
| OutputDiscipline × Binding_C | A local admissibility rule does not automatically determine how admissible values compose globally |
| Binding_C × J | Binding must not silently define membership, ordering, cardinality, or component identity of abstract (J) |
| VType × J | Vector dimensions must not be silently identified with (J)-members |
| All × A/W/W_D | Carrier symbols acquire no shape, numeric semantics, or runtime representation merely from a candidate semantic choice |

## 8. Discrimination burden

For every candidate pair, a legitimate discrimination claim must identify:

```
Candidate A
Candidate B
    ↓
semantic difference
    ↓
observable consequence that differs
    ↓
admissible observation condition
    ↓
possible falsification / constraint
```

The following are insufficient:

- numerical convenience;
- agreement on one observed dataset;
- existence of a scalar projection;
- engineering intuition;
- natural-language use of “cost” or “loss”;
- downstream notation;
- runtime representation;
- STEP⑤ notation;
- oracle or Risk terminology.

## 9. Non-identifiability is a valid result

If all admissible observations under the current observation frame satisfy:

```
O(S1,x) = O(S2,x)
```

then the correct result is:

```
OBSERVATIONAL EQUIVALENCE UNDER CURRENT FRAME
```

not:

```
SELECT THE MORE CONVENIENT SEMANTIC
```

Such a result does not complete semantic instantiation. It establishes only that current observations cannot distinguish the candidates.

## 10. Relation to current gates

This document does not enter STEP⑤.

The current order remains:

```
STEP④-A semantic instantiation
        ↓
necessary downstream consistency review
        ↓
Value Discipline / STEP④-B
        ↓
STEP⑤ and later gates only when separately satisfied
```

Semantic identifiability analysis is therefore decision support inside the current STEP④-A boundary.

## 11. Prohibited regressions

This document must not be used to:

- select a preferred VType;
- select a preferred OutputDiscipline;
- select Binding_C;
- infer (V_j) from cost/loss/Risk/oracle terminology;
- infer infinity semantics from STEP⑤;
- assign membership or type semantics to (J);
- give A/W/W_D runtime or tensor semantics;
- authorize a semantic discrimination experiment;
- authorize runtime implementation or a research harness;
- authorize data collection, profiling, or measurement;
- register RQ-P4-01 automatically;
- reopen closed/sealed historical research lines.

## 12. Decision status

```
SEMANTIC IDENTIFIABILITY ANALYSIS = DEFINED AS DECISION-SUPPORT FRAME
VType                        = UNDECLARED
OutputDiscipline             = UNDECLARED
Binding_C                    = UNDECLARED

EXPERIMENT AUTH              = NONE
IMPLEMENTATION AUTH         = NONE
MEASUREMENT AUTH             = NONE
STEP4-B                      = BLOCKED
STEP5                        = BLOCKED
```

The next legitimate researcher action remains explicit semantic instantiation, or an explicit determination that additional definition-level analysis is required. This document itself does not make that choice.
