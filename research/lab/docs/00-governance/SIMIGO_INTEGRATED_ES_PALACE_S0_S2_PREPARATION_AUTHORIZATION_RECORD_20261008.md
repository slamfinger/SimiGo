# Integrated ES–PALACE S0–S2 Preparation Authorization Record

> **Status:** AUTHORIZED — IMPLEMENTATION / FIXTURE PREPARATION ONLY
> **Date:** 2026-10-08
> **Authorization ID:** `INTEGRATED-ES-PALACE-D001-S0-S2-AUTH-001`
> **Package:** Integrated ES–PALACE Implementation / Fixture Preparation Authorization Package v1.0
> **Manifest Contract:** Integrated ES–PALACE Run Manifest Contract v1.0
> **Canonical base:** `2386e9dcdcaaa186b144f47e8bf65a72eab569b5`

## 1. Human ruling

The Human provided the following exact ruling:

```text
ACCEPT Authorization Package v1.0
ACCEPT Run Manifest Contract v1.0
AUTHORIZE S0-S2 IMPLEMENTATION / FIXTURE PREPARATION ONLY
INTEGRATED EXPERIMENT REMAINS NOT AUTHORIZED
CANONICAL IS MUTATION REMAINS NOT AUTHORIZED
E9 REMAINS NOT AUTHORIZED
EXP-004 REMAINS NOT AUTHORIZED
PIR REMAINS CLOSED
```

The Human also directed entry into `S0–S2 preparation`.

## 2. Bound review objects

```text
Authorization Package v1.0 =
  docs/02-evidence/integrated-es-palace-d001-20261008/
  SIMIGO_INTEGRATED_ES_PALACE_IMPLEMENTATION_FIXTURE_AUTHORIZATION_PACKAGE_V1.0_20261008.md;
  SHA256 = 3ef5967074b2231e9c8c65f093a51464893320f0bf2a74914d35e6f9b6800f43.

Run Manifest Contract v1.0 =
  docs/02-evidence/integrated-es-palace-d001-20261008/
  SIMIGO_INTEGRATED_ES_PALACE_RUN_MANIFEST_CONTRACT_V1.0_20261008.md;
  SHA256 = cea455699055761b7ed14919249c3a1724552c929251a7bb57acc2c82fa07340.
```

## 3. Authorized effect

This Record authorizes only:

```text
S0 PREFLIGHT;
S1 FIXTURE_PREPARATION;
S2 PREPARATION_VALIDATION;
STOP after S2.
```

It creates the required authority to create the exact approved implementation
artifacts, the exact seven approved isolated fixture roots, and the exact nine
write-once evidence objects. It does not authorize an integrated experiment,
observer campaign, canonical IS mutation, semantic broadening, or automatic
follow-on.

## 4. Continuing prohibitions

```text
integrated experiment       = NOT AUTHORIZED;
observer campaign           = NOT AUTHORIZED;
canonical IS mutation       = NOT AUTHORIZED;
E9                          = NOT AUTHORIZED;
EXP-004                     = NOT AUTHORIZED;
PIR                         = CLOSED / VALIDATION DEFERRED;
PALACE equivalence claim    = FORBIDDEN;
integrated SimiGo proof     = FORBIDDEN;
production SimiGo validity  = FORBIDDEN;
LLM autonomy                = FORBIDDEN;
E8 ruling change            = FORBIDDEN;
R01 closure change          = FORBIDDEN;
P1–P7 semantic change       = FORBIDDEN.
```

## 5. Stop rule

After S2 reaches `PASS`, `FAIL`, or `INVALID`, execution must stop and request a
separate Human decision before any integrated experiment.

## 6. Record integrity

This Record is registered by the canonical commit introducing it. Later
modification creates a new content address and does not silently revise this
Human ruling.
