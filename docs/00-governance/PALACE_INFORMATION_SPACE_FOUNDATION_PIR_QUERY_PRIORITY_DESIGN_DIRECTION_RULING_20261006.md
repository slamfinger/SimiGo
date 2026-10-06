# PIR Query-Priority Design Direction Ruling

> **Status:** Human design direction ACCEPTED; PIR Design v0.2 DELIVERED FOR REVIEW
> **Date:** 2026-10-06
> **Review authority:** Human
> **Design basis:** PIR Design v0.1
> **Implementation:** NOT AUTHORIZED
> **Experiment:** NOT AUTHORIZED
> **SimiGo code change:** NOT AUTHORIZED

## 1. Direction

The Human accepted the following as a PIR design principle:

```text
Query-Priority Reconciliation:
SimiGo does not require Information Space to remain continuously synchronized
with the entire physical world. When an Agent requests information, SimiGo
first resolves the current Query Scope and prioritizes verification/update of
the physical objects in that scope that affect the current Information Closure.
Unrelated or lower-priority Information may defer reconciliation.
```

This is not continuous synchronization and does not require the entire
Information Space to reach the same freshness at the same time.

## 2. Accepted architecture principle

```text
Query
  → Scope
  → Candidate Index
  → Relevant Objects
  → Physical Check
  → Fresh Closure
```

Index and Summary are prioritization/narrowing layers. They reduce the cost
of Physical Reconciliation. They do not replace physical evidence, make
business judgments, or authorize semantic guessing.

Logical priority layers:

```text
HOT / QUERY PATH
  Index, Summary, Identity/Revision, scope-relevant Relations,
  Physical Reconciliation, and Query-Scoped Closure.

COLD / BACKGROUND
  unrelated, stale, historical, pending, or low-priority Information.
```

These are logical freshness/priority layers, not a new backend, store, schema,
or consistency protocol.

## 3. Metric direction

The Human registered **Information Closure Acquisition Cost (ICAC)** as the
next research metric direction:

```text
ICAC =
    Scope Resolution Cost
  + Candidate Retrieval Cost
  + Physical Reconciliation Cost
  + IS Update Cost
  + Closure Reconstruction Cost
```

The key question is whether required acquisition cost depends primarily on
Query Scope rather than total Information Space size.

## 4. Future minimal experiment shape — NOT COMMISSIONED

A possible first bounded experiment could use:

```text
10,000 Information objects;
20 objects in the current Query Scope;
5 physical changes among those relevant objects;
fixed freshness window;
query-priority reconciliation only.
```

This shape is design-direction only. No fixture, dataset, harness, database,
implementation, or run is authorized.

## 5. Current boundary

```text
PIR implementation        NOT AUTHORIZED
PIR experiment            NOT AUTHORIZED
SimiGo code change        NOT AUTHORIZED
U-A / Frozen Contract     UNCHANGED
Probe v0.3 / R01 rerun    NOT WARRANTED
Next artifact             Human review of PIR Design v0.2
```
