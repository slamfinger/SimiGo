# Route Selection Review — A/B Discrimination Gate

Date: 2026-10-03  
Status: `ROUTE SELECTION REVIEW PACKET READY / SELECTED ROUTE = NONE`  
Prior anchor: `R-C1 #4 = CLOSED / VALID / EVIDENCE PRESERVED`  
Prior discrimination review:
`SIMIGO_LAB_ROUTE_A_B_EXPERIMENTAL_DISCRIMINATION_REVIEW_20261003.md`

## 1. Scope

This packet prepares, but does not execute, the route-selection ruling.

```text
No implementation is authorized.
No experimental design is opened.
No Route A/B execution is authorized.
No PALACE work is opened.
```

## 2. Candidate routes

```text
Route A = INFORMATION-COMPLEXITY PROBE
Route B = RELATION-DISCRIMINATION PROBE
```

## 3. Rulings required before selection

### S1 — Primary unknown

Does the reviewer confirm that the highest-priority unknown is:

```text
Does a Relation-dependent continuation condition exist that cannot be
expressed by Persistent Information alone?
```

### S2 — Route A necessity

Does the reviewer confirm that Route A should remain deferred until the
primary Relation question is resolved, because Route A does not directly test
that competing explanation?

### S3 — Route B design feasibility precondition

Does the reviewer confirm that Route B may enter design only if a later
design can construct:

```text
Same Information
        │
   ┌────┴────┐
   ▼         ▼
 C-B         C-C
 I only    I + Relation
```

with auditable:

```text
Information equivalence
isolated Relation difference
identical continuation criterion
```

If this cannot be constructed and audited, Route B remains deferred.

### S4 — Design Gate authorization

If S1–S3 pass, does the reviewer authorize only:

```text
Route B = SELECTED FOR EXPERIMENTAL DESIGN
```

This is not:

```text
Route B implementation authorization
Route B execution authorization
PALACE authorization
```

## 4. Candidate consequence if S1–S4 pass

Route B has two informative primary outcomes:

```text
C-B FAIL / C-C PASS
  supports a bounded Relation-dependent continuation observation.

C-B PASS / C-C PASS
  preserves O2 = NOT OBSERVED and weakens the current Relation-necessity
  hypothesis within this task domain.
```

Both outcomes are research-informative only if Information-equivalence audit
passes.

## 5. Required Route B Design Gate topics if selected

```text
B1  Target continuation question
B2  Same-Information construction
B3  Relation-only controlled variable
B4  C-B / C-C state construction
B5  Information-equivalence audit
B6  Relation endpoint/direction invariant
B7  Forbidden fallback
B8  Lifecycle protocol
B9  Physical overwrite protocol
B10 Evaluator X-1…X-5
B11 PASS / FAIL / INCONCLUSIVE matrix
B12 Stop conditions
B13 Evidence layout
B14 Claim boundary
```

B2 / B3 / B5 are the critical controls.

## 6. Current route status

```text
Route A = DEFERRED / INFORMATION-COMPLEXITY PROBE
Route B = DEFERRED / RELATION-DISCRIMINATION PROBE
Selected route = NONE
Route B design = NOT OPEN
Route B implementation = NOT STARTED
Route B execution = NOT AUTHORIZED
PALACE = CLOSED
```

## 7. Human ruling addendum — DEFER / SUPERSEDE

Human ruled:

```text
S1 = DEFER
S2 = DEFER
S3 = DEFER
S4 = NOT APPROVED
```

Reason: Route B selection was upstream of an unresolved question—why a settled
result may be directly adopted. Route Selection is therefore paused and
superseded by:

```text
SIMIGO_LAB_IPAC_MINIMAL_SEMANTICS_GATE_20261003.md
```

Route A/B remain deferred. This is not a route failure and does not reopen
implementation.

## 8. Addendum — routes remain deferred after boundary refinement

A later boundary synthesis reframed the upstream question from:

```text
Information-only vs Information + Relation
```

to:

```text
Execution State / Information Space boundary and coupling
```

Therefore Route A and Route B remain deferred under their revised
descriptions:

```text
Route A = INFORMATION-COMPLEXITY PROBE
Route B = RELATION-DISCRIMINATION PROBE
```

Neither route is selected.

## 8. Human addendum — S1…S4 deferred / superseded by research decision

Human ruled:

```text
S1 = DEFER
S2 = DEFER
S3 = DEFER
S4 = NOT APPROVED
```

Reason: selecting Information vs Relation was upstream of an unresolved question:

```text
Why may a settled result be directly adopted?
```

Route Selection is therefore paused and superseded by:

```text
SIMIGO_LAB_HUMAN_RESEARCH_DECISION_IAC_INFORMATION_SPACE_CONSISTENCY_20261003.md
```

Route A/B remain deferred. This is not a route failure and does not reopen
implementation.
