# SRS-REAL-CLOSURE-01 — Database-Carrier E8 Path-Map Establishment Request v2.2

> **ARCHIVED** 2026-10-20 · line: E-I 连续计算 · original: docs/00-governance/SRS_REAL_CLOSURE_01_DATABASE_CARRIER_E8_PATH_MAP_ESTABLISHMENT_REQUEST_V2.2_20261008.md
> Evidence status: unchanged (content frozen; moved only)


> **Status:** HUMAN-AUTHORIZED — FRESH E8 PATH MAP ONLY; E8 EXECUTION NOT AUTHORIZED
> **Date:** 2026-10-08
> **Exact Human ruling:** `继续，但只授权建立全新的 E8 path map；不要把 path-map authorization 与 E8 execution 合并。`
> **Predecessor lifecycle closure:** `5ff5d782f2a6f888e98e011462c9513f85d1ddd7`

## 1. Purpose

Establish one fresh, independent E8-reserved evidence path map and validate it
by preflight. This Request authorizes reservation only.

## 2. Authorized scope

```text
create fresh independent E8 path map version 6;
preserve the existing 31 mandatory destinations;
perform unique destination/path inventory;
create and remove preflight root after PASS;
record path-map reservation and preflight result;
stop at Human E8 launch review.
```

## 3. Forbidden scope

```text
E8 campaign execution;
E8 authorization or drafting;
IS mutation;
observer budget consumption;
campaign/IS-mutation/observer budget allocation;
CarrierSQLite semantic/schema/transaction changes;
ES2/ESN semantic changes;
tau/fixture/runner semantic-sequence changes;
decision-boundary changes;
EQ/REJ criteria changes;
E7 evidence reuse or reconstruction;
automatic equivalence;
automatic E8 launch.
```

## 4. Budget

```text
E8 path-map establishment = 1;
E8 campaign budget        = 0 / NOT AUTHORIZED;
E8 IS-mutation budget     = 0 / NOT AUTHORIZED;
E8 observer budget        = 0 / NOT AUTHORIZED.
```

## 5. Required stop

After path-map PASS and fresh preflight PASS, canonical execution stops. E8
launch requires a separate explicit Human authorization.
