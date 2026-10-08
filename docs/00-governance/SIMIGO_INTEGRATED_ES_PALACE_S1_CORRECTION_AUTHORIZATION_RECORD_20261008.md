# Integrated ES–PALACE S1 Correction Authorization Record

> **Status:** AUTHORIZED — S0–S2 PREPARATION CORRECTION ONLY
> **Date:** 2026-10-08
> **Correction ID:** `INTEGRATED-ES-PALACE-D001-S1-CORRECTION-001`
> **Predecessor authorization:** `INTEGRATED-ES-PALACE-D001-S0-S2-AUTH-001`

## 1. Failed attempt retained

S1 attempt `1865893F-D177-4603-8FE2-A2CFD7D4D08E` produced:

```text
IMPLEMENTATION_SELF_CHECK = FAIL;
FIXTURE_PREPARATION       = FAIL;
failing gate              = SC-2 static import allowlist;
carrier / fixture semantics = not implicated;
integrated experiment     = not executed.
```

The failed evidence and generated fixtures remain immutable in:

```text
docs/02-evidence/integrated-es-palace-d001-validation-v1/
integrated-es-palace/d001/fixtures/
```

No failed evidence object was overwritten.

## 2. Authorized correction

The active S0–S2 preparation authorization permits correction of this
implementation self-check defect. This Record registers the required new
manifest instance and evidence parent:

```text
manifest_instance_id = 5C8F8D7E-37F9-45A1-9123-54DDA83FEE8D;
evidence parent =
  docs/02-evidence/integrated-es-palace-d001-validation-v1-correction-001.
```

The correction may rerun S0, validate the already-generated seven fixture
roots, and run S2. It may not alter P1–P7, integrated experiment boundaries,
canonical IS, E8, R01, PIR, E9, or EXP-004 authority.

## 3. Continuing prohibitions

```text
integrated experiment       = NOT AUTHORIZED;
observer campaign           = NOT AUTHORIZED;
canonical IS mutation       = NOT AUTHORIZED;
E9                          = NOT AUTHORIZED;
EXP-004                     = NOT AUTHORIZED;
PIR                         = CLOSED / VALIDATION DEFERRED;
equivalence broadening      = FORBIDDEN.
```

## 4. Integrity

This correction is registered by the canonical commit introducing it. The
failed S1 evidence is not rewritten.
