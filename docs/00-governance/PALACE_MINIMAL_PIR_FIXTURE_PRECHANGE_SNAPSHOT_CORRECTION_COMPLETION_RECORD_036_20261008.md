# PALACE — PIR Fixture Pre-Change Snapshot Correction Completion Record 036

> **Status:** COMPLETE — FIXTURE CORRECTION PASS / TARGETED VALIDATION PASS
> **Date:** 2026-10-08
> **Governing Request v2.7:** `afa3d2e32f4731607ed64a1c10987995c516eecc`
> **Correction commit:** `1536fa6ed9ba3b93fbf60041ebfd4109eb5ce37a`
> **EXP-003:** NOT AUTHORIZED / NOT DRAFTED / NOT EXECUTED

## 1. Correction result

The isolated MOVE false-negative cause is corrected at fixture construction.
The measured registry now preserves both:

```text
pre_change_locator = L_old;
locator = L_new;
stable_object_id = O;
content SHA256 and byte size = unchanged across move.
```

The fixture builder no longer erases the pre-change locator by overwriting
`record.locator` before measured-registry serialization.

## 2. Targeted validation result

```text
pre-change locator preserved = PASS;
pre-change locator absent from post-change archive = PASS;
post-change locator discoverable = PASS;
stable object ID preserved = PASS;
content digest/size preserved across move = PASS;
zero candidates → PHYSICALLY_DELETED = PASS;
one candidate → PHYSICALLY_MOVED = PASS;
many candidates → CONFLICT = PASS;
non-move exact match → FRESH_WITHIN_WINDOW = PASS;
non-move mismatch → PHYSICALLY_CHANGED = PASS.
```

## 3. Boundary result

```text
PIR v0.2 design = UNCHANGED;
RM-001 shapes/thresholds/attribution = UNCHANGED;
reconciler semantic rules = UNCHANGED;
deterministic MOVE/RENAME protocol = UNCHANGED;
oracle semantics = UNCHANGED;
IS = NO MUTATION;
CarrierSQLite/E8 bounded ruling = UNCHANGED;
E7 evidence = NOT REUSED;
EXP-003 = NOT AUTHORIZED.
```

## 4. Bindings

```text
probe SHA256 = 644d166eab251ab7b8681ba6dd163a70105b136f85dfcc9a4007e8a9d17271ae;
experiment runner SHA256 = 58d21a9b55d972f5bd95c7239c8ac276326b29998fed2d9d7d6289dd61239c67;
request commit = afa3d2e32f4731607ed64a1c10987995c516eecc;
correction commit = 1536fa6ed9ba3b93fbf60041ebfd4109eb5ce37a.
```

## 5. Next lawful object

The next lawful object is Human Experiment Launch Review for a future corrected
PIR run. This record does not authorize EXP-003 or any execution.

## 6. Record integrity

```text
record_integrity_binding = registered by the canonical commit introducing this
record; later modification creates a new content address and voids this
completion record.
```
