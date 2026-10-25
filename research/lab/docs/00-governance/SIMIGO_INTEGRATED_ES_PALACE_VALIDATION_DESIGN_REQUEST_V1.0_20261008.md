# SimiGo — Integrated ES–PALACE Validation Design Request v1.0

> **Status:** OPENED — DESIGN / AUTHORIZATION PACKAGE ONLY
> **Date:** 2026-10-08
> **Predecessor:** SimiGo Integrated Foundation Review 001
> **Predecessor canonical main:** `f2f4aff66b75171520123ab7f9ab65a04e0a96d8`
> **Research partition:** D — Integrated SimiGo Execution State + PALACE validation
> **Stage:** DESIGN ONLY

## 1. Requested object

Create a separate:

```text
SimiGo Integrated ES–PALACE Validation Design / Authorization Package
```

It must define the minimal evidence-backed loop:

```text
ES reconstruction
  → PALACE / Information Space context recovery
  → NEXT_ACTION / continuation determination
  → ES continuation
  → bounded carrier persistence
  → next lawful continuation
```

The design request does **not** authorize implementation, fixture creation,
experiment execution, IS mutation, or equivalence claims.

## 2. Design must answer

### 2.1 Responsibility boundary

```text
Execution State
  = continuation semantics / obligations / orchestration;

PALACE Information Space
  = information representation / provenance / context;

Carrier
  = persistence / integrity;

Model
  = inference / semantic interpretation only.
```

### 2.2 Lawful ES consumption of PALACE primitives

The design must specify whether and how ES may lawfully consume
Information-Space primitives to produce the next continuation state without
hidden side channels.

### 2.3 Minimal positive cases

```text
lawful closure
  → reconstruction
  → context recovery
  → NEXT_ACTION determination
  → ES continuation;
already-settled continuation
  → reuse without recompute;
blocked-but-lawful continuation
  → explicit BLOCK state preserved.
```

### 2.4 Minimal negative cases

```text
missing information;
stale information;
ambiguous information;
illegal continuation boundary.
```

These must first become design-level contracts. Fixture creation is not
authorized by this Request.

## 3. Explicit exclusions

```text
PIR reopening;
E9;
CarrierSQLite equivalence reopening;
general Execution State theorem;
PALACE equivalence theorem;
LLM autonomy;
production validation;
performance / concurrency / scale;
new campaign;
implementation / fixture / experiment authorization.
```

## 4. Required stop

The Request ends after delivery of the design / authorization package for Human
review. No integrated campaign is authorized.
