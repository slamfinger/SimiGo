# Experiment Authorization Package R01 Review Ruling

> **Status:** R01 = **REVISE BEFORE S1**
> **Review date:** 2026-10-06
> **Review authority:** Human independent review
> **Reviewed package basis:** `f42762f`
> **Frozen design:** Probe v0.2 remains ACCEPTED / FROZEN
> **Experiment:** NOT AUTHORIZED
> **S1 fixture preparation:** NOT APPROVED

## 1. Ruling

The Human reviewed the submitted Experiment Authorization Package / Run
Manifest R01 and ruled:

```text
Probe v0.2                    ACCEPTED / FROZEN
Probe Representation Contract ACCEPTED
R01 governance boundary       QUALIFIED
R01 experiment structure      QUALIFIED
R01 evidence design           QUALIFIED
R01 execution packaging       REVISE BEFORE S1
Experiment                    NOT AUTHORIZED
S1                            NOT APPROVED
S3                            NOT AUTHORIZED
```

This is not a Probe redesign. It is a packaging / experimental-control
revision.

## 2. Required R01 revisions

```text
R1  N-B pointer schema:
    preserve two independent NEXT_ACTION records,
    P1a → B1 and P1b → B2.
    Do not introduce a multi-valued target_slot structure.

R2  Reconstruction blinding:
    the fresh reconstruction process must not receive fixture role
    P-POS / N-A / N-B. It receives only an opaque fixture instance ID
    and approved non-semantic addressing inputs. Control-side metadata
    retains the role mapping and expected result.

R3  Deterministic reconstruction entry point:
    the fresh process receives a pre-registered opaque stable session
    locator. It must not scan for the target session or use semantic
    search / embedding / ranking / fixture-generator content.
```

After these revisions, R01 may be resubmitted for a second Human review.
This ruling does not pre-approve S1.

## 3. Continuing prohibitions

```text
experiment execution
implementation work
database creation
fixture preparation
U-A code change
Manifest v1.1 change
UA v1.0 change
Frozen Contract change
MemPalace integration
MCP integration
embedding / semantic-ranking bypass
remote API use
backend selection
```
