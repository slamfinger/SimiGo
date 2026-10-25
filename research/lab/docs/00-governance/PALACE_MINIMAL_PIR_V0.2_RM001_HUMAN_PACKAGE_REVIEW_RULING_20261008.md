# Minimal PIR Probe v0.2 RM-001 Human Package Review Ruling

> **Status:** RM-001 = **ACCEPT PACKAGE**
> **Review date:** 2026-10-08
> **Review authority:** Human independent review
> **Reviewed package basis:** `docs/00-governance/PALACE_MINIMAL_PIR_V0.2_EXPERIMENT_AUTHORIZATION_PACKAGE_RUN_MANIFEST_RM001_20261008.md`
> **Package SHA256:** `4df7ba8f764fc44ef5a087c83e7075a60fe4fd5cafc7fd4c9d77f0c18d71bfc0`
> **Frozen design SHA256:** `94667081704f8e27bcd3bbb5cdd1685ee004adf8cf762fa27e24bb3edff23bd1`

## 1. Ruling

```text
Package / Run Manifest RM-001       ACCEPT PACKAGE;
E-L / E-S / C-NOCHANGE run shapes   APPROVED FOR PACKAGE BOUNDARY ONLY;
W_obs_age                           60,000 ms / accepted as package constraint;
W_latency                           5,000 ms / accepted as package constraint;
oracle isolation                    PASS;
phase-separated attribution         PASS;
EV-P01..EV-P18 closure coverage     PASS;
Implementation                      NOT AUTHORIZED;
Fixture creation                    NOT AUTHORIZED;
Experiment execution                NOT AUTHORIZED;
IS mutation                         NOT AUTHORIZED;
E9                                  NOT AUTHORIZED.
```

This ruling accepts RM-001 as a reviewable experimental contract only. It does
not authorize implementation, fixture creation, experiment execution, IS
mutation, budget consumption, E9, or any equivalence broadening.

## 2. Check 1 — run-shape legality

```text
E-L        = N=10,000, R=20, M=5;
E-S        = N=20, R=20, M=5;
C-NOCHANGE = paired R=20, M=0.
```

The three shapes are legally distinct:

```text
E-L tests the large registered-space case;
E-S controls the same R/M pattern in a small registered space;
C-NOCHANGE verifies complete scoped observation with zero changes.
```

The package pre-registers that `N`-dependent growth may be attributed only to
Scope Resolution / Index, Candidate Retrieval or declared structural registry
overhead. It explicitly forbids attributing such growth to Physical
Reconciliation. These shapes therefore test bounded reconciliation and phase
attribution; they do not establish a PIR performance or complexity theorem.

## 3. Check 2 — oracle legality

The package requires oracle isolation:

```text
the oracle may know planted truth for later evaluation;
the measured path must not receive the planted-change ledger,
ground-truth relevant set, expected verdicts, oracle output,
fixture role, control-side cost target, or agent notes.
```

Required evidence includes `EV-P04 sealed oracle ledger` and
`EV-P15 side-channel denial record`. Fail-closed triggers include oracle or
side-channel input entering the measured path. Oracle legality is therefore
PASS.

## 4. Check 3 — evidence closure

`EV-P01..EV-P18` covers the full lifecycle rather than only final verdicts:

```text
preparation:
  EV-P01 fixture manifests/checksums;
  EV-P02 query/freshness policy;
  EV-P03 blinded measured-path input;
  EV-P04 sealed oracle ledger;

observation and reconciliation:
  EV-P05 phase-separated ICAC;
  EV-P06 Information Scope resolution;
  EV-P07 Physical Scope resolution;
  EV-P08 physical reconciliation observations;
  EV-P09 W_obs_age;
  EV-P10 W_latency;
  EV-P16 raw object-touch audit;
  EV-P17 MOVE/RENAME correlation;

closure and evaluation:
  EV-P11 Fresh Closure;
  EV-P12 evaluation join;
  EV-P13 false positives / false negatives;
  EV-P14 paired E-L / E-S comparison;
  EV-P15 side-channel denial;
  EV-P18 observations-versus-changes counts.
```

Evidence closure coverage is PASS. The absent `campaign_stderr` concept from a
different evidence family is not relevant here; PIR failure capture remains
covered by raw audit logs, evaluation records and fail-closed triggers.

## 5. Check 4 — attribution

The package requires separate measurement and disclosure for:

```text
Scope Resolution / Index;
Candidate Retrieval;
Physical Scope assembly;
Physical Reconciliation;
IS Update;
Fresh Closure Reconstruction;
N, R and M effects;
unrelated physical touches.
```

It forbids merging heterogeneous ICAC units into a scalar and forbids
attributing N-dependent growth to Physical Reconciliation when
`P_materialized`, check targets and unrelated touches remain bounded. Therefore
information-scope cost, physical-reconciliation cost and unrelated work remain
separable.

## 6. Accepted package constraints

```text
W_obs_age  = 60,000 ms;
W_latency  = 5,000 ms;
E-L        = N=10,000, R=20, M=5;
E-S        = N=20, R=20, M=5;
C-NOCHANGE = paired R=20, M=0;
typed verdicts =
  FRESH_WITHIN_WINDOW,
  STALE_BEYOND_WINDOW,
  PHYSICALLY_CHANGED,
  PHYSICALLY_DELETED,
  PHYSICALLY_MOVED,
  CONFLICT,
  INDETERMINATE;
MOVE/RENAME = deterministic content SHA256 + byte size + stable opaque ID,
              exactly one candidate for MOVED/RENAMED,
              zero for DELETED,
              multiple for CONFLICT.
```

## 7. Authorization boundary

```text
RM-001 PACKAGE                ACCEPTED;
Implementation                NOT AUTHORIZED;
Fixture creation              NOT AUTHORIZED;
MINIMAL-PIR-EXP-001 execution NOT AUTHORIZED;
IS mutation                   NOT AUTHORIZED;
E9                            NOT AUTHORIZED;
automatic staged promotion    FORBIDDEN.
```

The next lawful object is an explicit Human decision whether to authorize a
separate implementation/fixture preparation stage. Even if that stage is later
authorized, execution of `MINIMAL-PIR-EXP-001` requires another explicit Human
authorization.

## 8. Record integrity

```text
record_integrity_binding = registered by the canonical commit introducing this
ruling; later modification creates a new content address and voids this package
acceptance.
```
