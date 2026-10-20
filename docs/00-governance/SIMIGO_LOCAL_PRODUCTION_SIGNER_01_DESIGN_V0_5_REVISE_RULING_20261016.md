# LOCAL-PRODUCTION-SIGNER-01 — Design v0.5 Fourth-Round Ruling: REVISE

> **Decision ID:** `LOCAL-PRODUCTION-SIGNER-01-DESIGN-V0.5-REVISE-20261016-01`
> **Type:** Governance registration (fourth formal design review ruling)
> **Date:** 2026-10-16
> **Review basis:** the v0.5 excerpts provided in-session; no claim of
> independent file, source, or implementation verification.
> **Ruling:** `REVISE` — not ACCEPT/FREEZE. Deliver v0.6 handling ONLY MR-12
> and MR-13. v0.1–v0.5 preserved in place; MR-7/8/9 and MR-10 not reopened.

## 1. Re-check summary (registered verbatim in substance)

MR-10 closed (generation/status cross-verification; `[15]` lineage binding;
audit-label disposition). MR-11 core secrecy principles closed; encoding and
failure-state details carried into MR-13.

## 2. New mandatory revisions

```text
MR-12 (blocker) archival verification isolation:
  old-lineage archival verification runs in a separate READ-ONLY historical
  verification context; it never installs old registry material as the
  active trust registry; it cannot pair, rotate, change permissions, or sign;
  results distinguish "historical signature valid" / "trusted in old
  lineage's history" / "trusted in current lineage"; restoring old material
  never modifies the current lineage's host_instance_id, active head, or key
  authorization states; unconfirmable history yields explicit UNVERIFIED,
  never degraded into current trust;
MR-13 (blocker) credential encoding and failure semantics:
  define the canonical byte forms and length bounds of credential_id and
  secret (or use the existing typed length-prefixed encoding rules) —
  identical logical inputs must produce identical digests in all
  implementations, no undefined concatenation; separate credential
  verification from PoP verification into explicit phases — only a
  successfully verified credential secret proceeds to authenticated-holder
  processing, and unknown-id/wrong-secret failures must never consume or
  alter a valid credential; failure semantics distinguished: (credential
  absent / wrong secret / expired / consumed → reject, no re-enable, no
  state change from unauthenticated requests) vs (credential verified but
  PoP or prebound-key failure → reject per an explicitly stated anti-theft
  policy; if termination is chosen it is a security disposition of an
  AUTHENTICATED credential, not a state change triggerable by invalid
  requests) vs (operator decline/revocation/successful consumption →
  irreversible terminal; re-issuance uses a new credential_id).
```

## 3. Governance status

```text
v0.5 = REVISE; v0.6 = next design delivery;
Trust Universe A / Contract v1.8 / frozen anchor = unchanged;
R27 = STOP; REPAIR_ATTEMPT_6 = NOT AUTHORIZED / NOT CONSUMED;
LOCALB implementation, key generation, Build/Test = NOT AUTHORIZED;
accept/freeze at any later round still does not grant implementation
authorization by itself.
```
