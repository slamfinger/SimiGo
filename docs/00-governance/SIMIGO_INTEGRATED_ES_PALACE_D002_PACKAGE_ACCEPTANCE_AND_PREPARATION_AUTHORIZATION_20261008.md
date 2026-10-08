# D-002 Authorization Package v1.0 Acceptance and Preparation Authorization

> **Status:** ACCEPT / PREPARATION AUTHORIZED
> **Date:** 2026-10-08
> **Authorization ID:** `INTEGRATED-ES-PALACE-D002-PREP-AUTH-001`
> **Canonical base:** `38fb3276ee9722b1f93290758c79975e36a27656`
> **Manifest instance:** `45E2228A-8095-48F0-803E-4E25AF03C4B3`

## 1. Human ruling

The Human returned:

```text
D-002 Authorization Package v1.0 = ACCEPT
```

The Human separately added one binding preparation gate:

```text
SQLite snapshot must prove transaction consistency, not merely equality of the
single-file byte digest.
```

The snapshot gate must bind:

```text
source byte digest unchanged;
snapshot byte digest bound;
SQLite integrity check PASS;
snapshot independently readable;
WAL/SHM/transaction consistency explicitly represented.
```

## 2. Authorized stage

Only the following preparation stage is authorized:

```text
D-002 implementation preparation;
D-002 source snapshot preparation;
D-002 fixture preparation;
preparation validation;
STOP before experiment.
```

The preparation may create the exact implementation artifacts proposed by
Package v1.0, one isolated SQLite snapshot, and seven snapshot-derived fixture
cases. It may not run D-002 experiment or observer campaign.

## 3. Continuing prohibitions

```text
D-002 experiment                   = NOT AUTHORIZED;
D-002 observer campaign execution  = NOT AUTHORIZED;
canonical IS mutation              = NOT AUTHORIZED;
PALACE source mutation             = NOT AUTHORIZED;
semantic search                    = FORBIDDEN;
embedding/vector traversal         = FORBIDDEN;
cloud/model causal participation   = FORBIDDEN;
E9                                 = NOT AUTHORIZED;
EXP-004                            = NOT AUTHORIZED;
PIR reopening                      = NOT AUTHORIZED;
PALACE equivalence claim           = FORBIDDEN;
integrated SimiGo proof            = FORBIDDEN.
```

## 4. Required stop

Preparation must stop after validation. A separate Human decision is required
before any experiment or observer campaign.

## 5. Record integrity

This acceptance is registered by the canonical commit introducing it. Later
modification creates a new content address and does not silently revise the
Human ruling.
