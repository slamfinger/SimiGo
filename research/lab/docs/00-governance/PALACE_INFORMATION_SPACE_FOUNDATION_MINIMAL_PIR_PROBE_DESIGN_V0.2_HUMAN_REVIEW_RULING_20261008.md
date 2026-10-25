# Minimal PIR Probe Design v0.2 Human Review Ruling

> **Status:** Minimal PIR Probe Design v0.2 = **ACCEPT / DESIGN FROZEN**
> **Review date:** 2026-10-08
> **Review authority:** Human independent review
> **Reviewed design basis:** `docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_MINIMAL_PIR_PROBE_DESIGN_V0.2_20261006.md`
> **Design SHA256:** `94667081704f8e27bcd3bbb5cdd1685ee004adf8cf762fa27e24bb3edff23bd1`
> **Implementation:** NOT AUTHORIZED
> **Fixture creation:** NOT AUTHORIZED
> **Experiment:** NOT AUTHORIZED
> **IS mutation:** NOT AUTHORIZED

## 1. Ruling

```text
Minimal PIR Probe v0.1              ACCEPTED / SUPERSEDED BY V0.2;
Minimal PIR Probe v0.2              ACCEPT / DESIGN FROZEN;
MR-1 observable observation age     PASS;
MR-2 non-circular physical boundedness PASS;
MR-3 phase-separated scaling attribution PASS;
MR-4 non-semantic MOVE/RENAME protocol PASS;
Next object                         separate Experiment Authorization Package /
                                    Run Manifest, only if separately authorized;
Implementation                      NOT AUTHORIZED;
Fixture creation                    NOT AUTHORIZED;
Experiment                          NOT AUTHORIZED;
IS mutation                         NOT AUTHORIZED.
```

This restores and completes the paused Human Review of Minimal PIR Probe v0.2.
It does **not** reopen PIR Design Review, authorize implementation or fixtures,
authorize experiment execution, or create an Experiment Authorization Package.

## 2. Review basis

The v0.2 probe inherits accepted PIR Design v0.2 and its Clarification
Addendum:

```text
PIR Design v0.2 SHA256 =
  d409c0d718691520ed558ae92b4c711eb9ad85cb2fc0afb00f2e52459facd5b0;
Clarification Addendum SHA256 =
  310a29a9ab631e04f21e513df7db40c20bfa2a181743a6ed8be1bded95792980;
Minimal PIR Probe v0.1 SHA256 =
  be3e3139941bbdcbcf4178a23186ca5d46f70aedb3ac0a576aebd15a7c73c136.
```

All unamended v0.1 rules remain: paired `E-L` / `E-S`, oracle isolation,
phase-separated ICAC, `W_latency`, typed physical verdicts, Fresh Closure,
failure and indeterminate conditions, evidence requirements, and the prohibition
on implementation / fixture / experiment.

## 3. Required v0.1 revision checks

```text
MR-1  W_obs_age semantics                 PASS;
MR-2  Scope membership + no-global-expansion PASS;
MR-3  phase-separated scaling attribution PASS;
MR-4  deterministic MOVE/RENAME protocol  PASS;
observations versus physical_changes      PASS;
updated PC-6 / PC-9A/B/C / PC-13A/B/C     PASS.
```

The design correctly measures observable observation staleness, not physical
change age. It keeps Physical Reconciliation bounded by declared scope and
`P_materialized`, rather than whole-Information-Space `N`. It pre-registers
scaling attribution and a deterministic, non-semantic MOVE/RENAME correlation
protocol with zero/one/many ambiguity outcomes.

## 4. Four boundary checks

```text
1. Observation ≠ interpretation       PASS;
2. Scope ≠ whole-space synchronization PASS;
3. Freshness ≠ existence              PASS;
4. PIR ≠ Information Space mutation   PASS.
```

The probe may only observe, correlate and issue typed physical verdicts. It may
not perform semantic inference, business judgment, global scans, continuous
sync, semantic ranking, model inference, fixture mutation, IS update, or carrier
mutation. `FRESH_WITHIN_WINDOW`, `STALE_BEYOND_WINDOW`,
`PHYSICALLY_CHANGED`, `PHYSICALLY_DELETED`, `PHYSICALLY_MOVED`, `CONFLICT` and
`INDETERMINATE` remain distinct typed outcomes.

## 5. Authorized next object

If the Human later chooses to continue, the next separate object is an
**Experiment Authorization Package / Run Manifest**. It must mechanically bind:

```text
paired E-L / E-S shape and final numeric windows;
declared Information and Physical Scopes;
P_declared / P_materialized / check-target / observation / change counters;
blinded measured-path inputs;
opaque stable session or fixture locators;
pre-registered MOVE/RENAME candidate pool and correlation rule;
oracle isolation and side-channel denial;
phase-separated ICAC vectors;
PASS / FAIL / INDETERMINATE criteria;
evidence EV-P01..EV-P15.
```

That package review does **not** imply experiment authorization.

## 6. Continuing prohibitions

```text
Probe v0.2 design change;
PIR architecture change;
implementation;
fixture creation;
filesystem access trial;
experiment execution;
IS mutation;
U-A / Manifest / UA / PB / Frozen Contract change;
semantic entity or CarrierRecord growth;
RelationCore extension;
Super Store;
embedding or semantic-ranking authority;
MCP integration;
remote API use;
backend selection;
carrier migration;
E9 or Database-Carrier campaign authorization.
```

## 7. Record integrity

```text
record_integrity_binding = registered by the canonical commit introducing this
ruling; later modification creates a new content address and voids this ruling.
```
