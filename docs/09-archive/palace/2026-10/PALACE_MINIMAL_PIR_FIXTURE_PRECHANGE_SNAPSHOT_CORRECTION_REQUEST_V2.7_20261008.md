# PALACE — Minimal PIR Fixture / Measured-Registry Pre-Change Snapshot Correction & Targeted Validation Request v2.7

> **ARCHIVED** 2026-10-20 · line: PALACE / Integrated ES · original: docs/00-governance/PALACE_MINIMAL_PIR_FIXTURE_PRECHANGE_SNAPSHOT_CORRECTION_REQUEST_V2.7_20261008.md
> Evidence status: unchanged (content frozen; moved only)


> **Status:** HUMAN-AUTHORIZED — FIXTURE / MEASURED-REGISTRY CORRECTION AND TARGETED VALIDATION ONLY
> **Date:** 2026-10-08
> **Exact Human ruling:** `授权一次独立的 fixture/measured-registry pre-change snapshot correction + targeted validation，然后重新进入 launch review。`
> **Predecessor audit:** EXP-002 Human Evidence Audit Record 035
> **Predecessor canonical main:** `e462cf22df9f0ff130ec6deac017b7ab26b53f80`

## 1. Purpose

Preserve the pre-change locator provenance required to adjudicate deterministic
MOVE/RENAME, while keeping the post-change destination discoverable. This Request
corrects the isolated fixture/measured-registry snapshot defect only.

## 2. Authorized scope

```text
repair fixture builder / measured-registry construction;
preserve pre-change locator snapshot for planted MOVE;
retain post-change locator as the discoverable destination;
retain stable opaque object ID, content SHA256 and byte size;
add targeted regression for pre-change state → post-change state;
validate zero / one / many MOVE-candidate ambiguity policy remains intact;
revalidate EV-P01..EV-P18 fixture destination bindings;
stop for Human Experiment Launch Review.
```

Required acceptance invariant:

```text
pre-change:
  old_locator = L_old;
  object_id = O;

post-change:
  new_locator = L_new;
  object_id = O;

measured registry:
  L_old preserved;
  L_new discoverable;
  O stable;
  digest/size unchanged across move.
```

## 3. Forbidden scope

```text
PIR v0.2 design change;
RM-001 run shape, W_obs_age, W_latency or attribution change;
reconciler semantic rules change;
deterministic MOVE/RENAME protocol change;
oracle semantics change;
IS mutation;
CarrierSQLite change;
E8 bounded equivalence change;
E7 evidence reuse;
EXP-003 authorization/drafting/execution;
new campaign/observation budget;
PC-CREATE addition;
automatic experiment launch.
```

## 4. Required stop

After correction and targeted validation PASS, canonical state stops for separate
Human Experiment Launch Review. This Request does not authorize EXP-003 or any
execution.
