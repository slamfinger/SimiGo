# Runtime adapter branch semantics targeted revision

> **Status:** TARGETED REVISION COMPLETE / RUNTIME VALIDATION NOT AUTHORIZED
> **Date:** 2026-10-10

## 1. Ruling consumed

The Human review accepted the Runtime Adapter Integration v1.0 delivery but
withheld runtime-validation authorization because every decision previously
advanced real Execution State. The authorized scope was limited to branch
semantics, targeted regression proof, and a new validation manifest.

## 2. Correction

```text
CONTINUE = real coordinator may advance exactly once and bind the returned
           handle's representation;
REUSE    = read-only settled identity and representation verification;
           no create, continue, reattach, or rebind;
BLOCK    = pure fail-closed result; no execution creation, advance,
           lifecycle record, or representation binding.
```

The adapter now returns an `IntegratedRuntimeApplicationReceipt` recording:

```text
advanced;
execution created;
representation bound;
lifecycle records before/after;
position before/after;
live handle;
bound representation position/prefix.
```

## 3. Targeted regression

```text
test = IntegratedESPalaceRuntimeAdapterBranchTests;
result = PASS / 3 tests / 0 failures.

CONTINUE: position 0 -> 1; created+continued lifecycle delta = 2;
          representation bound and returned-handle consistent.
REUSE: lifecycle delta = 0; position remains 0; no rebind; prior prefix
          and position unchanged.
BLOCK: all four negative decisions return no handle; coordinator lifecycle
          delta = 0; no execution created, advanced, or bound.
```

## 4. Revised binding

```text
revised adapter SHA256 =
  8ffc6f291deea2c5ab2035fc46dd1be73613663f8453dfb8d5a463b4597c1bca;
targeted regression source SHA256 =
  e7a37d66c46ed946c8b1fc426bc10431db15ddf6ee95dffd6bb1846e6480b142;
Runtime Validation Manifest SHA256 =
  7a4adf4a36d06c86fdae2c39182559ef2c17613e572cc684d2891ab9cb3a23d1.
```

The new manifest is a candidate only:

```text
validation_authorized = false;
validation_executed = false;
authorized_runs_if_approved = 1;
terminal states = RUNTIME_VALIDATION_PASS or RUNTIME_VALIDATION_FAIL;
automatic rerun / repair = false.
```

## 5. Boundaries

```text
first VALIDATION_FAIL = retained;
V2 VALIDATION_PASS = CLOSED;
frozen design and P1–P7 = unchanged;
seven-case expected contracts = unchanged;
canonical PALACE / Information Space mutation = FORBIDDEN;
D-002 rerun / repair = FORBIDDEN;
production deployment = NOT AUTHORIZED;
Integrated SimiGo full production proof = NOT ESTABLISHED.
```
