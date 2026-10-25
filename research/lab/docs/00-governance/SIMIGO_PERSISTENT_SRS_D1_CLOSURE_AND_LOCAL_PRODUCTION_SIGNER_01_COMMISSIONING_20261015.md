# Persistent SRS — D1 External-Path Closure and LOCAL-PRODUCTION-SIGNER-01 Commissioning

> **Decision ID:** `PERSISTENT-SRS-D1-CLOSURE-LPS01-COMMISSIONING-20261015-01`
> **Type:** Governance registration (D1 branch closure + design-work commissioning)
> **Date:** 2026-10-15
> **Ruling provenance:** Human directive 2026-10-15 — baseline acceptance of
> `PERSISTENT-SRS-R27G0-REPAIR-BOUNDARY-D1-RULING-20261015-01`, deployment-context
> clarification (single local host + limited LAN inference clients), and the
> local-production-signer direction with its stated constraints.
> **Supersedes:** steps D1.1–D1.3 (external custody path) of ruling 20261015-01 §D-E.
> Decisions D-A, D-B, D-C, D-D, D-F of that record are unchanged and remain in force.
> **Status:** REGISTERED. No implementation is authorized by this record.
> Commit/push of this record awaits explicit Human instruction.

---

## 1. Ruled decisions

```text
D-G D1 closure:
  D1_EXTERNAL_CUSTODY_PATH_NOT_APPLICABLE_FOR_DEPLOYMENT
  deployment context = SimiGo host used locally, serving a limited set of
  LAN inference clients; no external signing institution is part of this
  deployment;
  the owner attests that no external custodian or signing service will be
  designated for the frozen anchor (D1.1 has no external answer by design,
  not by omission);
  the External Custody Attestation Request will NOT be sent; it remains a
  historical draft with blank responsible-party fields;
  the R27-G0 scoped negative stands unchanged: absence inside the searched
  scope is NOT upgraded to "external signing capability does not exist", and
  NOT to "the frozen public key should be replaced".

D-H commissioning:
  COMMISSION_LOCAL_PRODUCTION_SIGNER_01_DESIGN
  work item = LOCAL-PRODUCTION-SIGNER-01, design-only;
  scope (five areas, fixed):
    1. host signing identity initialization and persistence;
    2. one-time pairing protocol (first trust via a trusted local channel,
       not raw TOFU);
    3. client registration and automatic post-pairing authentication;
    4. SRS signature verification and key rotation under a local trust
       registry;
    5. isolation boundary between frozen Contract v1.8 and the new local
       production signing configuration;
  deliverable = LOCAL_PRODUCTION_SIGNER_01_CONCEPTUAL_DESIGN_V0.1
    (PENDING HUMAN REVIEW);
  implementation = NOT AUTHORIZED; a separate ruling is required after
    design review, with its own writable-path set; the design must reuse the
    existing SRS encoding/signing infrastructure, must not create a duplicate
    persistence substrate, and must not modify frozen anchors.
```

## 2. Preserved boundaries (restated, unchanged)

```text
Trust Universe A (frozen):
  Contract v1.8 / I0 Schema v1.6 / Manifest Instance v2.2 / hardcoded
  production anchor = untouched; R27 end-to-end remains STOP;
  REPAIR_ATTEMPT_6 = NOT AUTHORIZED / NOT CONSUMED; R14 = OPEN;
  no anchor rewrite, no test-key impersonation, no R27 bypass;
  no pairing success, TLS success, or local-key generation ever counts as
  Universe-A production-signature compliance.

Trust Universe B (new, this work item):
  a local production signing configuration — an independent trust universe;
  locally generated keys never validate pre-existing records;
  pre-existing records never enter the local trust registry;
  later-appearing public keys never acquire trust automatically
  (registry lineage or rejection, no third state).

All other preserved boundaries of ruling 20261015-01 §4 carry forward:
  PALACE / Information Space mutation FORBIDDEN; no Build/Test; no fixture;
  RESEARCH_STATE.md reconciliation pending separate authorization;
  GUI click-through evidence remains engineering-only.
```

## 3. Sequencing

```text
1. design v0.1 delivered (this commissioning + the design document);
2. Human review: ACCEPT/FREEZE (then a separate implementation
   authorization with its own writable paths) / REVISE / PARK;
3. any resumption question for Universe A (frozen line) is untouched by
   this work item and remains under D2-style separate governance if ever
   needed.
```
