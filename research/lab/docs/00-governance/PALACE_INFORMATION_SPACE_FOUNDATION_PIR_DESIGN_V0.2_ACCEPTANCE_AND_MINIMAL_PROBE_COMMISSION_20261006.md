# PIR Design v0.2 Acceptance and Minimal Probe Commission

> **Status:** PIR Design v0.2 + Clarification Addendum = **ACCEPTED**
> **Review date:** 2026-10-06
> **Review authority:** Human independent review
> **Reviewed basis:** `c50978a`
> **Commissioned artifact:** Minimal PIR Probe Design v0.1
> **Implementation:** NOT AUTHORIZED
> **Experiment:** NOT AUTHORIZED
> **Fixture creation:** NOT AUTHORIZED

## 1. Acceptance ruling

```text
Query-Priority Reconciliation        PASS
PIR Design v0.2                      PASS / ACCEPTED
Clarification Addendum               PASS / ACCEPTED

F1 Query Scope                       RESOLVED
F2 Scope/Reconciliation separation   RESOLVED
F3 ICAC cost vector                  RESOLVED
F4 W_age / W_latency                 RESOLVED
F5 request-relative HOT/COLD         RESOLVED

Architecture redesign                NOT REQUIRED
R01 reopening                        NOT WARRANTED
PIR implementation                   NOT AUTHORIZED
PIR experiment                       NOT AUTHORIZED
```

The Human reviewed the five clarifications and confirmed that they removed the
prior ambiguity without damaging Query-Priority architecture.

## 2. Accepted design consequences

```text
Query Scope = Information Scope + Physical Scope.
Scope Resolution and Physical Reconciliation are measured separately.
ICAC is a heterogeneous cost vector, not an unauthorized scalar.
W_age and W_latency are independent.
HOT/COLD is request-relative, not a permanent database tier.
```

The accepted model is:

```text
Query
  → Execution State
  → Information Scope + Physical Scope
  → Candidate Set
  → Physical Reconciliation
  → Fresh Closure
  → Execution
  → New Information
  → Information Space
```

This is query-driven closure formation, not whole-space synchronization.

## 3. Non-blocking probe-design note

`W_age` must later be operationalized as an observable value, for example:

```text
controlled physical observation timestamp
  → query reconciliation timestamp
  → observable observation age
```

Whether file mtime, digest evidence, or controlled event timestamps are
acceptable must be fixed by Minimal PIR Probe Design. This note does not block
acceptance.

## 4. Commission

The next lawful artifact is:

```text
Minimal PIR Probe Design v0.1
```

It must freeze, in design only:

```text
baseline and control structure;
oracle boundary;
physical change planting rules;
measurement points;
W_age observability rule;
W_latency budget rule;
ICAC vector fields;
pass / fail / indeterminate criteria;
failure taxonomy;
and the boundary between scope resolution and physical reconciliation.
```

The initial `10,000 / 20 / 5` shape may guide the design but is not a final run
authorization.

## 5. Continuing prohibitions

```text
PIR implementation            NOT AUTHORIZED
PIR experiment                NOT AUTHORIZED
fixture creation              NOT AUTHORIZED
filesystem access trial       NOT AUTHORIZED
SimiGo code change            NOT AUTHORIZED
U-A / Frozen Contract change  NOT AUTHORIZED
user-file mutation            NOT AUTHORIZED
```
