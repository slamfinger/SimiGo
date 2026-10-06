# Minimal PIR Probe Design v0.1 Review Ruling

> **Status:** Minimal PIR Probe Design v0.1 = **CONDITIONAL PASS**
> **Review date:** 2026-10-06
> **Review authority:** Human independent review
> **Reviewed basis:** `c029b89`
> **Required follow-up:** four methodological revisions before Fixture / Run Manifest
> **Implementation:** NOT AUTHORIZED
> **Fixture creation:** NOT AUTHORIZED
> **Experiment:** NOT AUTHORIZED

## 1. Ruling

```text
Research question                     PASS
Paired E-L / E-S design               PASS
Scope / reconciliation separation     PASS
Oracle isolation                      PASS
ICAC vector                           PASS
Change pattern                        PASS
CREATE deferral                       PASS
Negative controls                     PASS
Move / rename protocol                NEEDS REVISION
Scaling attribution                   NEEDS REVISION
Physical-check boundedness            NEEDS REVISION
W_age semantics                       NEEDS REVISION

Minimal PIR Probe Design v0.1         CONDITIONAL PASS
PIR Fixture                           NOT AUTHORIZED
PIR Implementation                    NOT AUTHORIZED
PIR Experiment                        NOT AUTHORIZED
```

No structural rejection or Probe redesign was required.

## 2. Required revisions

```text
MR-1  Rename / redefine W_age as observable observation-age semantics:
      W_obs_age = current reconciliation time - previous lawful physical
      observation time. It must not be described as physical-world change age.

MR-2  Split physical boundedness into non-circular properties:
      physical_check_targets ⊆ declared Physical Scope, and
      unrelated_physical_touches = 0.
      P is the number of candidates actually exposed by the declared Physical
      Scope, not an upper bound mathematically derived from R.

MR-3  Pre-register E-L/E-S scaling attribution:
      N-dependent growth may be attributed only to Scope Resolution / Index /
      declared structural costs. Physical Reconciliation cost may grow with
      P/R but must not show whole-N scan growth.

MR-4  Lock MOVE / RENAME discovery in the future Run Manifest:
      declared candidate pool, allowed file class, identity-correlation rule,
      bounded directory scope, ambiguity handling, and no semantic fallback.
```

## 3. Additional terminology requirement

Run Manifest must distinguish:

```text
physical_observations  policy-scoped checks performed;
physical_changes       typed PC-* differences actually observed.
```

For `C-NOCHANGE`, required outcome is:

```text
physical_observations = R
physical_changes = 0
false_positive_changes = 0
```

## 4. Continuing prohibitions

```text
PIR implementation        NOT AUTHORIZED
PIR fixture creation      NOT AUTHORIZED
PIR experiment            NOT AUTHORIZED
filesystem access trial   NOT AUTHORIZED
SimiGo code change        NOT AUTHORIZED
```
