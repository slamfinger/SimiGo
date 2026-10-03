# IPAC / Execution State Research Synthesis Gate

Date: 2026-10-03  
Status: `C TRACK SYNTHESIS CLOSED / HUMAN H1…H3 ACCEPTED / CLOSURE APPROVED / NO NEW EXPERIMENT`  
Evidence anchor: `R-C1 #4 = CLOSED / VALID / EVIDENCE PRESERVED`  
Scope: theory synthesis only. No C-Spec, C-Design, C-Impl, Core, PALACE,
Route A, or Route B work is authorized.

## 1. Gate purpose

R-C1 #4 is the first valid bounded experiment in C Track. Before accumulating
more experiments, this gate records what the result does and does not support,
and aligns it with the Execution State / IPAC research question.

## 2. Established evidence boundary

```text
R-C1 #4 = VALID / EVIDENCE PRESERVED

C-A = ES only                 → PARTIAL / X-1 only
C-B = ES + Information        → FULL / X-1…X-5
C-C = ES + Information + Rel  → FULL / X-1…X-5
```

Established bounded observations:

```text
O1 = SUPPORTED / TASK-DOMAIN-BOUNDED
  Runtime state alone did not complete full semantic continuation.
  Persistent Information enabled the preregistered continuation sequence.

O2 = NOT OBSERVED / TASK-DOMAIN-BOUNDED
  Relation did not show additional continuation capability beyond
  independent persistent Information in this single-change task.
```

These results do not establish universal Agent-memory necessity, IPAC,
PALACE necessity, or Relation generality.

## 3. Candidate model

The admissible experimental abstraction is:

```text
Restored Execution State
        +
Resolved Persistent Information
        +
Satisfied Continuation Conditions
        ↓
Continuation
```

Therefore, runtime Execution State is better treated as the lifecycle/control
substrate, while persistent Information forms the semantic substrate required
for continuation beyond task identity.

## 4. IPAC interpretation — OPEN / NONBINDING

A candidate interpretation is that IPAC is not merely four stored fields.
It may describe the relation by which a current Execution State may lawfully
adopt a previously settled computation result persisted outside that state.

Candidate chain:

```text
Past Computation
    ↓
Settled Result
    ↓
Persistent Information / provenance
    ↓
IPAC-style validation
    ↓
Execution State adoption
    ↓
Continuation
```

This is a research hypothesis, not a result of R-C1 #4.

## 5. Three synthesis questions

### Q1 — What must remain inside Execution State?

Evidence supports that C-A retained enough to recover task identity, but not
enough for semantic continuation. A candidate internal minimum includes:

```text
execution identity
lifecycle phase / position
legal carrier references
continuation obligation
```

The complete necessary internal set remains open.

### Q2 — What may live in persistent Information Space?

R-C1 #4 shows that the external side carried information sufficient for
S0, S1, directional change, task rule, and progress recovery. Candidate
external contents include:

```text
settled facts
task charter / continuation rule
identity-addressed observations
provenance
relation structure
```

The necessary and sufficient external set remains open.

### Q3 — When may a state adopt a settled result without recomputation?

A candidate adoption relation requires:

```text
the prior result is addressable;
the prior computation is settled;
the result is provable from persistent Information / provenance;
the result is semantically compatible with the current task;
the current Execution State can reference it without re-deriving it;
continuation conditions are satisfied.
```

This candidate is not yet formalized or experimentally tested.

## 6. Route consequences — DEFERRED

```text
Route A = tests repeatability of the Information dependency.
Route B = tests whether Relation has information-irreducible continuation role.
```

Neither route is selected. Selection should follow, not precede, the synthesis
of the adoption relation.

## 7. Non-goals

```text
No C-Spec amendment
No C-Design amendment
No C-Impl revision
No Core modification
No PALACE implementation or schema
No Route A execution
No Route B execution
No reinterpretation of R-C1 #1…#3 as hypothesis evidence
No universal Agent-memory or Relation-necessity claim
```

## 8. Gate result

```text
B Track              = CLOSED
C Gate               = OPEN / PAUSED FOR SYNTHESIS
C-Spec               = FROZEN
C-Design             = CONFIRMED / NO AMENDMENT
C-Impl               = CLOSED / D-4 REVISION AUDIT PASS
C-Execute            = NOT AUTHORIZED
R-C1 #1…#3           = INVALID INCONCLUSIVE
R-C1 #4              = VALID / EVIDENCE PRESERVED
O1                   = SEALED / SUPPORTED / BOUNDED
O2                   = SEALED / NOT OBSERVED / BOUNDED
IPAC interpretation   = OPEN / NONBINDING
Route A              = DEFERRED
Route B              = DEFERRED
PALACE               = NOT OPEN
```

## 9. Closure review packet — PENDING

`SIMIGO_LAB_IPAC_SYNTHESIS_CLOSURE_REVIEW_20261003.md` now proposes the final
three-layer synthesis model and the only three human review questions:

```text
H1 = Accept distinct but cooperating Execution State / Persistent Information
     layers.
H2 = Accept continuation lawfulness, not mere restoration, as the follow-on
     research question.
H3 = Accept IPAC as an open, nonbinding Result Adoption / Continuation
     Conditions candidate without freezing I/P/A/C definitions.
```

Until H1…H3 are explicitly accepted, neither Route A nor Route B may be
selected and IPAC remains open/nonbinding.

## 10. Human closure ruling — 2026-10-03

Human accepted the proposed closure model:

```text
H1 = ACCEPT
H2 = ACCEPT
H3 = ACCEPT
```

Therefore the synthesis gate is closed:

```text
B Track             = CLOSED
C Gate              = OPEN / SYNTHESIS CLOSED
C-Spec              = FROZEN
C-Design            = CONFIRMED / NO AMENDMENT
C-Impl              = CLOSED / D-4 AUDIT PASS
R-C1 #4             = CLOSED / VALID
O1                  = SEALED / SUPPORTED / BOUNDED
O2                  = SEALED / NOT OBSERVED / BOUNDED
Execution State     = SEMANTIC LAYER ACCEPTED
Persistent Info     = SEMANTIC LAYER ACCEPTED
Continuation model  = ACCEPTED / TASK-DOMAIN-BOUNDED
IPAC                = OPEN / NONBINDING
IPAC minimality     = UNPROVEN
IPAC semantics      = NOT FROZEN
Route A             = DEFERRED
Route B             = DEFERRED
PALACE              = CLOSED
```

This closure defines the current research model. It does not prove IPAC
semantics or authorize Route A/B.
