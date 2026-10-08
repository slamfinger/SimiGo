# SimiGo Integrated ES–PALACE Implementation / Fixture Preparation Request v1.0

> **Status:** OPENED — IMPLEMENTATION / FIXTURE PREPARATION PACKAGE ONLY
> **Date:** 2026-10-08
> **Request ID:** `INTEGRATED-ES-PALACE-IMPLEMENTATION-FIXTURE-PREPARATION-REQUEST-V1.0`
> **Research partition:** D — Integrated SimiGo Execution State + PALACE validation
> **Predecessor canonical main:** `88a34c2b3d0f97613926fa075c0a0f3aa0c5a106`
> **Governing frozen design:** Integrated ES–PALACE Validation Design Package 001 Revision v1.1 = ACCEPT / DESIGN FROZEN
> **Frozen revision basis:** `bae6999d632038d19fd9c4b35a71a9a7edb19a69`

## 1. Authorized object

This Request authorizes only the creation of a separate, Human-reviewable:

```text
Integrated ES–PALACE Implementation / Fixture Preparation
Authorization Package + Run Manifest
```

The package must mechanically bind the frozen P1–P7 contracts to an
implementable and fixture-preparable boundary. It must not silently enlarge the
design, authorize execution, or consume campaign budget.

Creation of actual implementation artifacts, fixture state, experiment
harness execution or evidence-producing runs remains unauthorized until that
package is accepted through a separate explicit Human decision.

## 2. Frozen design inheritance

The future package must inherit exactly:

```text
P1  Primitive Inventory;
P2  PALACE → ES Typed Mapping;
P3  Continuation Identity Contract;
P4  Side-Channel Denial Matrix;
P5  Negative Decision Precedence;
P6  Carrier Lifecycle Contract;
P7  Integrated-vs-Predecessor Boundary.
```

It must preserve:

```text
Lawful Information Closure
  → PALACE / Information Space primitive inventory
  → typed ES reconstruction input
  → continuation identity / NEXT_ACTION
  → REUSE / BLOCK / bounded continuation
  → Carrier persistence
  → next lawful continuation.
```

The following non-composition boundary remains binding:

```text
E8 = bounded CarrierSQLite carrier equivalence evidence;
R01 = bounded continuation-sufficiency evidence;
D  = NEW integrated semantic-closure object;
E8 + R01 ≠ integrated SimiGo proof.
```

## 3. Required package contents

The package must define:

```text
1. exact implementation scope and allowed artifacts;
2. exact fixture-preparation scope and allowed fixture roots;
3. primitive inventory bindings for P1;
4. typed PALACE → ES schemas and authority boundaries for P2;
5. canonical continuation-identity tuple and digest rule for P3;
6. side-channel denial checks for P4;
7. deterministic negative precedence and typed outputs for P5;
8. Carrier persistence / success / failure lifecycle checks for P6;
9. evidence destinations, write-once and closure rules;
10. fresh experiment-entry preflight;
11. PASS / FAIL / INVALID criteria;
12. stop rules and explicit non-authorization of experiment execution.
```

## 4. Required fixture / contract matrix

The package must pre-register at least:

```text
P-LAWFUL      lawful closure → reconstruction → continuation;
P-SETTLED     settled continuation → REUSE without recompute;
P-BLOCKED     blocked-but-lawful → explicit BLOCK preserved;

N-MISSING     MISSING_INFORMATION_BLOCK;
N-STALE       STALE_INFORMATION_BLOCK;
N-AMBIGUOUS   AMBIGUOUS_INFORMATION_BLOCK;
N-ILLEGAL     ILLEGAL_CONTINUATION_BLOCK.
```

Each case must bind:

```text
trigger;
typed decision;
identity / digest binding;
precedence reason;
closure artifact;
no fallback guess.
```

Synthetic fixture initialization may be planned only inside isolated,
explicitly bound fixture roots. Canonical IS mutation is forbidden.

## 5. Required validation boundaries

The package must require implementation self-checks proving:

```text
1. primitive inventory is mechanically complete;
2. PALACE → ES mapping is typed and authority-separated;
3. continuation identity is deterministic and digest-bound;
4. forbidden side channels are absent or denied;
5. negative precedence is deterministic;
6. Carrier does not make semantic decisions;
7. implementation does not treat E8 + R01 as integrated proof.
```

It must also distinguish:

```text
implementation / fixture preparation validation
      from
integrated experiment execution.
```

## 6. Explicit prohibitions

This Request does not authorize:

```text
implementation artifact creation;
fixture creation or mutation;
experiment execution;
canonical IS mutation;
PIR reopening;
E9 or Database-Carrier campaign work;
EXP-004;
CarrierSQLite semantic change;
E8 formal ruling change;
R01 closure change;
P1–P7 semantic change;
PALACE equivalence claim;
general Execution State theorem;
integrated SimiGo proof;
production SimiGo validity;
LLM autonomy;
experiment budget consumption;
observer campaign budget consumption;
automatic Run Manifest approval.
```

## 7. Stop condition

This Request ends after delivery of the Implementation / Fixture Preparation
Authorization Package + Run Manifest for Human review.

The lawful sequence remains:

```text
Request opened
  ↓
package + manifest delivered
  ↓
Human review
  ↓
ACCEPT / REVISE / REJECT
  ↓
if ACCEPT, separately authorize implementation / fixture preparation
  ↓
validation
  ↓
separate experiment authorization decision
```

## 8. Preserved state

```text
E8 bounded CarrierSQLite equivalence = ESTABLISHED / BOUNDED;
R01 continuation sufficiency         = PASS / BOUNDED;
PIR                                  = CLOSED / VALIDATION DEFERRED;
PALACE equivalence                   = NOT ESTABLISHED;
Integrated SimiGo proof              = NOT ESTABLISHED.
```

## 9. Record integrity

```text
record_integrity_binding = registered by the canonical commit introducing this
Request; later modification creates a new content address and voids this
Request opening.
```
