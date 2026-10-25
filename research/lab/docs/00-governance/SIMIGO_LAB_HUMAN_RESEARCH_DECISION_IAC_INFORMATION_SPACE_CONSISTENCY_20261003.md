# Human Research Decision — IAC ↔ Information Space Consistency

Date: 2026-10-03  
Status: `HUMAN DECISION APPROVED / R0 APPROVED / IAC ↔ INFORMATION SPACE CONSISTENCY ADOPTED`  
Prior state: `ROUTE SELECTION PAUSED / S1…S4 DEFERRED`  
Evidence anchors:
- `R-C1 #4 = CLOSED / VALID / EVIDENCE PRESERVED`
- `O1 = SEALED / SUPPORTED / TASK-DOMAIN-BOUNDED`
- `O2 = SEALED / NOT OBSERVED / TASK-DOMAIN-BOUNDED`
- `IPAC continuity bridge = OPEN / NONBINDING`

## 1. Decision question

Human must decide whether to adopt this as the next primary research question:

```text
Does a consistency relation exist between the internal Execution State
I/A/C continuation skeleton and the external Information Space boundary,
such that changes to the Information Space can preserve or violate the
conditions required for lawful continuation?
```

This decision does **not** authorize implementation, experiment, PALACE,
IPAC freezing, or Route A/B/C selection.

## 2. Why this is now upstream of Route A/B

R-C1 #4 established:

```text
C-A  State only               → partial / X-1 only
C-B  State + Information      → full / X-1…X-5
C-C  State + Info + Relation  → full / X-1…X-5
```

But it did not explain the deeper question:

```text
Why does persistent Information restore lawful continuation,
and what happens if the Information Space later violates the semantic
conditions that continuation depends on?
```

Therefore choosing Route A or B now would be premature.

## 3. Proposed sequence if approved

### R0 — Human Research Decision

Decide only:

```text
Adopt “IAC ↔ Information Space semantic consistency”
as the next primary research question.
```

### R1 — Historical evidence review

Reopen prior IPAC / IAC decisions as evidence, not as new experiments.

Critical audit question:

```text
When the earlier study said “P may be carried or compensated by A”,
did that mean:

1. P is a redundant field;
2. P’s semantics can be represented by A’s structure; or
3. P’s continuation role can be satisfied by A under defined conditions?
```

The answer changes what the old evidence can support.

### R2 — Internal / external consistency formalization

Formulate a falsifiable research question without freezing IPAC:

```text
Internal:
  I + A + C
      ↓
  Execution State continuation semantics

External:
  Information Space
      ↓
  information conditions required by that semantics

Violation question:
  If Information Space changes violate the semantic conditions required by
  I/A/C, does the original Execution State still belong to the same
  continuation?
```

### R3 — Route decision after consistency framing

Only after R0–R2 review:

```text
Route A: Information complexity / scope change
Route B: Relation’s independent role
Route C: Information Space boundary breaking or preserving I/A/C consistency
```

No route is selected by this packet. Route C is only a possible future label.

## 4. Non-goals

```text
No C-Spec amendment
No C-Design amendment
No C-Impl revision
No Core modification
No PALACE implementation or schema
No Route A/B/C execution
No IPAC field freezing
No claim that IPAC is proven
No universal Agent-memory claim
```

## 5. Decision format

```text
R0 = APPROVED / REJECTED / REVISED
R1 = APPROVED / REJECTED / REVISED
R2 = APPROVED / REJECTED / REVISED
R3 = APPROVED / DEFERRED / NOT READY
```

If R0–R2 are approved, the next gate is formal research design. If not, C Track
remains paused.


## 6. Human decision approval — 2026-10-03

Human explicitly approved the decision packet in chat:

```text
批准
```

Approval time:

```text
2026-10-03T14:33:24+0800
```

Approved decision:

```text
R0 = APPROVED
Primary research question = ADOPTED
Question = IAC ↔ Information Space semantic consistency
```

This approval authorizes only the research question adoption. It does not
authorize implementation, experiment, PALACE, IPAC freezing, or Route A/B/C
selection.

Current status:

```text
R0 = APPROVED
R1 = PENDING EXPLICIT HUMAN INSTRUCTION
R2 = PENDING EXPLICIT HUMAN INSTRUCTION
R3 = NOT READY / REQUIRES R1–R2 COMPLETION
C Gate = OPEN / HUMAN RESEARCH DECISION APPROVED
Implementation = NOT STARTED
Experiment = NOT AUTHORIZED
PALACE = CLOSED
Route A/B/C = NOT SELECTED
```
