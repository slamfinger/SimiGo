# Database-Carrier / PALACE — PIR RM-001 Implementation & Fixture Preparation Request v2.5

> **Status:** HUMAN-AUTHORIZED — IMPLEMENTATION / FIXTURE PREPARATION ONLY
> **Date:** 2026-10-08
> **Exact Human ruling:** `授权 PIR RM-001 Implementation / Fixture Preparation Request`
> **Predecessor RM-001 package acceptance:** `f777f29...`
> **Predecessor canonical main:** `f6a0e5e17e8d5ce0a130f8a58de0dd824384a2f2`

## 1. Authorized scope

Implement the already-frozen Minimal PIR Probe v0.2 contract and prepare the
RM-001 synthetic fixtures and self-checks for `E-L`, `E-S` and `C-NOCHANGE`.
The stage may bind future evidence destinations and validate fixture legality,
oracle isolation, attribution separation and fail-closed behavior.

## 2. Explicitly forbidden

```text
MINIMAL-PIR-EXP-001 execution;
filesystem reconciliation experiment;
physical observation generation as experiment evidence;
IS mutation;
Probe v0.2 contract change;
RM-001 run-shape, threshold or attribution change;
new semantic entity, CarrierRecord kind, RelationCore rule or Super Store;
whole-space scan in normal application logic;
semantic similarity or model best-guess correlation;
MCP or remote API use;
Database-Carrier campaign work;
E9 authorization;
old campaign evidence reuse;
automatic experiment authorization.
```

## 3. Required completion

```text
implementation present;
E-L / E-S / C-NOCHANGE synthetic fixtures present or reproducibly buildable;
fixture manifests and oracle/control-side ledgers separated from measured input;
deterministic MOVE/RENAME candidate pool validated;
oracle isolation validated;
EV-P01..EV-P18 destination binding present;
pre-experiment legality and self-check PASS;
canonical stop for separate Experiment Launch Review.
```

## 4. Budget

```text
implementation / fixture preparation work cycle = 1;
MINIMAL-PIR-EXP-001 execution budget            = 0 / NOT AUTHORIZED;
IS mutation budget                              = 0 / NOT AUTHORIZED.
```

## 5. Stop

Even if all implementation and fixture self-checks PASS, the state must stop
before experiment. A separate explicit Human authorization is required to launch
`MINIMAL-PIR-EXP-001`.
