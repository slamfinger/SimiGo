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

## 5. Registered retry

Correction-001 S0 stopped because PF-4 compared sorted fixture-root names with
an unsorted constant. This was an implementation self-check ordering defect, not
a fixture defect. The failed PREFLIGHT is retained. Correction-002 is registered
without expanding authority:

```text
manifest_instance_id = 95B0B101-F717-4541-933F-48D750736ABB;
evidence parent =
  docs/02-evidence/integrated-es-palace-d001-validation-v1-correction-002.
```

## 6. Registered S2 readiness retry

Correction-002 S1 passed. Its S2 entry exposed an uncaught missing-pointer
exception before any S2 evidence object was written. This is precisely the
N-MISSING path and must return typed `MISSING_INFORMATION_BLOCK`, not raise.
Correction-003 is registered without expanding authority and retains all prior
evidence.

## 7. Registered terminal-label retry

Correction-003 S2 compared the positive observed label to `typed_decision` while
the pre-registered third vector component is `precedence_reason`. All seven
decisions, identities, and Carrier persistence were otherwise produced. Failed
S2 evidence is retained. Correction-004 is registered without expanding
authority:

```text
manifest_instance_id = 1DACEDBD-6269-42E7-90ED-69276DCAE64B;
evidence parent =
  docs/02-evidence/integrated-es-palace-d001-validation-v1-correction-004.
```
