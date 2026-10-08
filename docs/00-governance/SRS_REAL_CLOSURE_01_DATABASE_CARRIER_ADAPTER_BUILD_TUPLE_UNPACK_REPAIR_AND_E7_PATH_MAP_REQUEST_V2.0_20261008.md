# SRS-REAL-CLOSURE-01 — Database-Carrier Adapter-Build Tuple-Unpack Repair & Fresh E7 Path Map Request v2.0

> **Status:** HUMAN-AUTHORIZED — PART R6 CORRECTION + FRESH E7 PATH MAP; E7 EXECUTION NOT AUTHORIZED
> **Date:** 2026-10-08
> **Exact Human ruling:** `授权一个新的独立 Request，范围仅限 adapter-build tuple-unpack binding correction + fresh E7 path-map establishment；完成后再次 Human review，再单独决定是否启动 E7。`
> **Predecessor readiness closure:** `db92d31...`
> **Predecessor canonical main:** `cc315fd1c563be2d8992b8361fb8cfd39283ad73`

## 1. Purpose

Close the single readiness blocker by repairing the caller-side adapter-build
tuple-unpack binding, adding a targeted regression/self-check, and establishing
a fresh independently authorized E7 path map. The campaign itself remains
stopped.

## 2. Exact authorized scope

```text
repair adapter-build tuple-unpack binding on the caller side;
preserve build_adapter() tuple[Path, dict] contract;
add targeted tuple-contract regression/self-check;
establish fresh independent E7 evidence path map;
run fresh preflight validating repaired boundary and fresh map;
stop for Human review.
```

## 3. Forbidden scope

```text
E7 campaign execution;
new IS-mutation campaign/observer budget consumption;
CarrierSQLite semantic/schema/transaction changes;
ES2/ESN semantic changes;
tau/fixture/runner semantic-sequence changes;
decision-boundary changes;
EQ/REJ criteria changes;
old E6 evidence reuse for campaign execution;
old budget reuse;
automatic E7 launch;
automatic equivalence establishment.
```

## 4. Budget

```text
adapter-build tuple-unpack repair work cycle = 1;
fresh E7 path-map establishment             = 1;
E7 campaign budget                          = 0 / NOT AUTHORIZED;
E7 IS-mutation budget                       = 0 / NOT AUTHORIZED;
E7 observer budget                          = 0 / NOT AUTHORIZED.
```

## 5. Required stop

After repair PASS, regression/self-check PASS, fresh path-map PASS, and fresh
preflight PASS, canonical execution must stop. E7 can be considered only after
a separate Human review and explicit launch authorization.
