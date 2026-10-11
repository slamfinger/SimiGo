# SRS-VAL-01 Decision Core implementation authorization

> **Status:** AUTHORIZED / DECISION CORE IMPLEMENTATION AND PURE UNIT TESTS ONLY
> **Date:** 2026-10-11
> **Authorization commit correction:** the initial text cited the invalid 42-character
> string `81e099ba5477772678468478366450571733944875`. The valid Git commit is
> `81e099ba8dad4f337e5e86b4d5a02fd47bad33fc`.
> **Baseline commit:** `6e8f4bf67580bc92afddb9f08ee94b3ad402f548`
> **Normative design:** SRS-VAL-01 Design v0.8 (frozen), including inherited v0.7 predicates
> **Execution authority:** Human direction in this session, 2026-10-11

## Authorized scope

The authorized first slice is limited to:

```text
one independent, pure SRS-VAL-01 Decision Core implementation;
pure XCTest coverage of REUSE, BLOCK, and authorized RECOMPUTE paths;
non-generative validation and documentation of the authorized scope.
```

The implementation must preserve the frozen DP-0 through DP-4 precedence,
G-V1 through G-V7 checks, G-CLASS mandatory classification, exact binding
requirements, I-14/I-15/I-16 obligations, typed failures, and mutually exclusive
`REUSE` / `BLOCK` / `RECOMPUTE` outcomes.

## Explicit exclusions

This authorization does not permit:

```text
fixture datasets beyond in-test pure values;
actual MLX execution;
V6 rerun or gate adjustment;
Runtime Validation V2 rerun;
D-002 rerun or repair;
canonical PALACE mutation;
canonical Information Space mutation;
persistent SRS storage;
independent ES2 consumption;
production deployment or traffic.
```

Those require separate review and authorization.
