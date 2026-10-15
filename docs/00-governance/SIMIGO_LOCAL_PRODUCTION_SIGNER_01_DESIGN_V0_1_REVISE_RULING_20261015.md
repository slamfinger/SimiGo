# LOCAL-PRODUCTION-SIGNER-01 — Design v0.1 Ruling: REVISE

> **Decision ID:** `LOCAL-PRODUCTION-SIGNER-01-DESIGN-V0.1-REVISE-20261015-01`
> **Type:** Governance registration (design review ruling)
> **Date:** 2026-10-15
> **Ruling provenance:** Human review 2026-10-15. Reviewer's access note, registered
> verbatim in substance: the ruling is a substantive initial review based on the
> delivered design **summary**, not a section-by-section acceptance of the v0.1
> file (the reviewer could not access the file from their review environment).
> The v0.2 file should be reviewed directly:
> `docs/02-evidence/local-production-signer-01-20261015/LOCAL_PRODUCTION_SIGNER_01_CONCEPTUAL_DESIGN_V0.2.md`
> **Ruling:** `REVISE` — direction retained; NOT ACCEPT/FREEZE; implementation
> remains NOT AUTHORIZED.

---

## 1. Ruling table

| Item | Ruling |
|---|---|
| Design v0.1 | `REVISE` |
| Core architecture direction | retained (two trust universes; registry-or-reject; fail-closed; no trust from records) |
| OQ-1, OQ-2, OQ-3, OQ-4, OQ-5, OQ-8 | blockers — must be closed in the revision |
| OQ-6 | `PARK` — Ed25519 baseline stands; P256/Secure-Enclave variant is a non-blocking research question (Apple Secure Enclave signing/key agreement is limited to NIST P-256; `Curve25519.Signing`/Ed25519 is not Secure-Enclave-resident) |
| OQ-7 | pairing trust rules must be explicit in the design; discovery-protocol details may be deferred to implementation |
| Implementation authorization | NOT GRANTED |
| Trust Universe A / Contract v1.8 / frozen anchor | FROZEN, unchanged |
| R27 / REPAIR_ATTEMPT_6 | STOP / NOT AUTHORIZED / NOT CONSUMED — unchanged |
| RESEARCH_STATE.md reconciliation | still requires separate authorization |

## 2. Five mandatory revisions (registered as the v0.2 requirement set)

```text
MR-1 (OQ-4, primary blocker)  local signed record issuer + format boundary:
  choose ONE grounded path — (a) independent local record configuration/version
  (B-specific issuer, key identifier, verification rules, format version) or
  (b) independent wrapper layer over unchanged Contract v1.8 records; the
  choice must be grounded in the ACTUAL envelope encoding and I0 schema;
  either way: Contract v1.8 is not modified to admit local keys, and B records
  are never fed into A-domain paths claiming old-contract verification;
MR-2 (OQ-2, OQ-7)            pairing as a verifiable state machine: credential
  binds host identity + TLS identity + SRS signing key identity + protocol
  version + one-time session id; keyID precisely defined (deterministic
  fingerprint, never a substitute for public-key verification); validity,
  unguessability, single consumption, replay protection; client verifies the
  actually-connected TLS identity against out-of-band data; discovery is
  lead-only; explicit host-side authorization before completion; threat
  boundary stated (what is resisted, what is not promised, what physical/
  administrative conditions first trust depends on — QR is out-of-band
  transfer and does not by itself eliminate forwarding/relay risk);
MR-3 (OQ-1)                  registry integrity/backup/recovery semantics:
  tamper/truncate/rollback resistance; atomic add/revoke/retire commits;
  restore rules incl. rollback-to-older-trust detection; permanent-loss
  semantics (re-pairing vs historical verification vs old key material);
  out-of-scope host-compromise conditions; historical signature verifiability
  ≠ current key trustworthiness; records never restore registry authority;
  corrupted/unconfirmable registry refuses NEW trust establishment;
MR-4 (OQ-3, OQ-5)            key usage + permission boundaries: client keys
  never carry SRS production signing rights; signing key never transferred to
  clients; per-operation permission requirements (inference / info read /
  SRS write / pairing management / trust rotation); defaults + revocation
  timing; baseline = default-deny, least privilege, admin plane separated;
MR-5 (OQ-8)                  TLS identity vs record-signing identity
  lifecycles: cert renewal must not break pairings (stable identity
  identifier, not full-cert pinning); behaviors for TLS cert renewal, TLS key
  replacement, SRS key rotation, key loss/recovery; network events never
  silently rotate trust roots; TLS validity never equals SRS signing trust.
```

## 3. Retained rules (not reopened) and the naming constraint

The retained-rule list of the ruling (host-owned local signing; automation
only on already-paired identities; unknown keyID rejected with no third
state; explicit rotation retaining historical verification material; no trust
recovery from records; local public keys never enter the frozen anchor;
`PersistentSRSRepresentation.swift` frozen anchor untouched; no implicit
cross-domain trust inference in either direction) carries into v0.2 verbatim.

Naming constraint: the work-item name `LOCAL-PRODUCTION-SIGNER-01` is kept,
but every identity name in code, record format, and UI must mark it as the
LOCAL Trust Domain B signing identity (v0.2 uses the `LOCALB` marker family),
so "production" is never misread as Contract v1.8 production-signature
identity.

## 4. Next lawful object

Design v0.2 (delivered with this registration) → a new design ruling. Even on
ACCEPT/FREEZE, implementation requires an independent authorization with its
own writable-path set. Nothing in this record authorizes Build/Test, key
generation, fixture creation, frozen-object modification, or
RESEARCH_STATE.md changes.
