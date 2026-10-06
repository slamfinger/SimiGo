# Physical–Information Reconciliation — v0.1 Design

> **Status:** DESIGN V0.1 DELIVERED FOR HUMAN REVIEW — IMPLEMENTATION / EXPERIMENT NOT AUTHORIZED
> **Date:** 2026-10-06
> **Registered predecessor gap:** R01 closure registered PIR as the next research gap
> **Immediate predecessor result:** ES-CSP-RUN-01 = PASS — CONTINUATION SUFFICIENT / BOUNDED
> **Design purpose:** define physical change, query-time freshness, responsible reconciliation actor, and typed reconciliation boundaries.
> **Scope guard:** design only. No SimiGo code change, no U-A change, no Frozen Contract change, no implementation, no experiment, no user-file mutation, no MCP/remote API.

## 1. Research question

When an Agent receives a query, can SimiGo—within a controlled short window
and through a constrained Reconciliation Sub-Agent—verify the physical objects
relevant to that query and bring Information Space to a prescribed freshness
requirement?

R01 assumed that a lawful closure already existed. PIR begins after that
assumption becomes unsafe because the physical world may have changed.

## 2. Non-goals

This design does not define or authorize:

```text
continuous real-time synchronization;
filesystem watching;
backend selection;
database migration;
MemPalace integration;
MCP integration;
remote API use;
embedding or semantic ranking authority;
business-judgment execution;
automatic modification of user business files;
Execution State expansion;
U-A, Manifest, UA, PB, InformationCore, RelationCore, or Frozen Contract
change.
```

## 3. PIR-D1 — physical change

The first bounded physical domain is local filesystem regular files under one
registered observation root. A physical object is identified by its registered
locator/representation chain, not by mutable path alone.

A physical change is a typed difference between the last lawful registered
physical observation and the current controlled observation.

### 3.1 Initial change classes

```text
PC-CREATE
  a physical regular file exists but has no registered Information/Carrier
  closure for the current query scope.

PC-MODIFY
  the same registered physical object still resolves, but its controlled
  content/metadata check differs from the registered observation according to
  the freshness policy.

PC-DELETE
  the registered locator no longer resolves to a physical regular file.

PC-MOVE / PC-RENAME
  the old locator no longer resolves, but a candidate physical file is found
  by a lawful non-semantic correspondence rule and satisfies the registered
  identity/revision policy.
```

### 3.2 Required distinctions

```text
physical observation ≠ semantic interpretation.
locator change ≠ Information identity change.
representation revision ≠ new semantic meaning.
unresolved locator ≠ proven deletion unless the policy's lawful check says so.
candidate move match ≠ certainty unless the pre-registered correspondence rule
                        accepts it.
```

No new semantic entity is introduced. Physical observations become Information
only through existing formation/provenance semantics, if later authorized.

## 4. PIR-D2 — Information freshness

Freshness is a query-time judgment about whether registered Information still
lawfully represents the relevant physical object.

It is not a background synchronization state.

### 4.1 Freshness policy

A freshness policy must be pre-registered per query scope and must contain:

```text
FP-1  relevant locator / Information scope;
FP-2  maximum accepted age of the last lawful physical observation;
FP-3  required checks:
        existence, locator resolution, controlled metadata, and/or controlled
        content digest;
FP-4  move/rename correspondence rule;
FP-5  conflict policy when observations disagree;
FP-6  result record and provenance requirements.
```

### 4.2 Freshness verdicts

```text
FRESH_WITHIN_WINDOW
  the registered observation satisfies the active policy.

STALE_BEYOND_WINDOW
  the object resolves, but the last observation is outside the accepted window.

PHYSICALLY_CHANGED
  the object resolves and a lawful check establishes a modify-class change.

PHYSICALLY_DELETED
  the lawful check establishes deletion according to policy.

PHYSICALLY_MOVED
  the lawful move/rename rule establishes correspondence.

CREATED_UNREGISTERED
  a relevant physical file exists but is not registered in the query scope.

CONFLICT
  lawful observations disagree and the policy forbids silent selection.

INDETERMINATE
  required evidence is unavailable or the check cannot be completed lawfully.
```

Freshness output must never replace a missing business judgment with a guess.

## 5. PIR-D3 — responsibility

Information Space is passive. It does not watch, decide, reconcile, or run
itself.

Responsibility is layered:

```text
Main Agent / Execution State
  receives the user query;
  determines query scope and freshness policy;
  starts one constrained Reconciliation Sub-Agent;
  consumes the typed reconciliation result.

Reconciliation Sub-Agent
  performs only policy-scoped physical checks;
  records lawful observations;
  emits typed reconciliation output;
  never interprets business intent.

Information Space
  stores registered observations, provenance, revisions, and relations through
  existing lawful semantics;
  never autonomously updates itself.

Physical World
  is checked through bounded lawful observation; it is not modeled as an
  Agent, Information, or Relation semantic entity.
```

The Reconciliation Sub-Agent may be recorded as an actor/provenance subject.
It must not become `AgentInformation`, `AgentRelation`, or an AgentStore.

## 6. PIR-D4 — reconciliation boundaries and typed outputs

### 6.1 Allowed reconciliation actions

```text
check physical existence;
resolve registered locator;
compare policy-required metadata;
compare policy-required content digest;
apply the pre-registered move/rename rule;
emit typed observations;
append provenance-bearing records through existing lawful Information Space
semantics, if separately authorized.
```

### 6.2 Required typed output record

A reconciliation result must contain:

```text
query scope identifier;
freshness policy identifier;
registered Information/Carrier/locator references;
physical observation result;
typed verdict from §4.2;
observation time;
actor/provenance;
checks performed;
checks not performed;
typed failure or conflict reason.
```

### 6.3 Hard boundaries

The Reconciliation Sub-Agent must not:

```text
make business judgments;
decide what the user meant;
choose a business continuation;
modify user business files;
move, rename, delete, or repair user files;
silently overwrite registered Information history;
promote semantic guesses above physical observations;
expand Execution State;
create new semantic primitives;
authorize backend selection or migration;
continue after an unresolved policy conflict.
```

## 7. Reconciliation outcome relation to R01

PIR does not replace R01. It precedes a new R01-like continuation closure:

```text
R01 completed:
  registered closure exists
    → fresh ES reconstruction
    → C1 / C2 continuation determination.

PIR future chain:
  physical change may invalidate closure
    → query-scoped reconciliation
    → typed physical observations
    → new lawful closure
    → fresh ES reconstruction
    → continuation determination.
```

PIR success cannot be claimed merely because files are found. It must show that
Information Space reaches the prescribed freshness state through lawful,
provenance-bearing reconciliation.

## 8. Design-only next review questions

Human review should decide:

```text
D-Q1  Is the first physical domain correctly bounded to local regular files?
D-Q2  Are create / modify / delete / move-rename definitions decidable without
      semantic guessing?
D-Q3  Is query-time freshness sufficiently distinct from continuous sync?
D-Q4  Is the Reconciliation Sub-Agent responsibility boundary strong enough?
D-Q5  Are typed conflict/stale/deleted/moved outputs sufficient for the next
      design revision?
D-Q6  What minimal PIR probe, if any, should be pre-registered after design
      acceptance?
```

No probe is commissioned by this document.

## 9. Decision requested

This document requests Human design review only.

```text
ACCEPT DESIGN      proceed to a separately reviewed minimal probe design,
                   still without implementation
REVISE DESIGN      return with registered defects
REJECT DESIGN      do not proceed to probe design
```

Approval of this design does not authorize implementation, experiment, fixture
creation, user-file access, or SimiGo code change.
