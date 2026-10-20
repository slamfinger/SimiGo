# LOCAL-PRODUCTION-SIGNER-01 — Local Trust Domain B Signing & LAN First-Pairing Conceptual Design v0.6

> **Status:** PENDING HUMAN REVIEW (fifth formal round). Design only; authorizes
> no implementation, no Build/Test, no fixture, no key generation, no
> frozen-object change.
> **Date:** 2026-10-16
> **Supersedes:** v0.5 (same directory; preserved in place), per
> `LOCAL-PRODUCTION-SIGNER-01-DESIGN-V0.5-REVISE-20261016-01`.
> **Scope of this revision:** ONLY MR-12 (archival verification isolation) and
> MR-13 (credential encoding and failure semantics). MR-7/8/9 and MR-10 are not
> reopened.

---

## 0. Change logs

### 0.1 v0.5 → v0.6 (fourth-round items)

| Item | Disposition in v0.6 |
|---|---|
| MR-12 archival isolation | new §7.6 Archival Verification Context (read-only, separate from active trust service; typed three-way result vocabulary; hard prohibitions; unconfirmable → ARCHIVAL_UNVERIFIED) |
| MR-13 credential encoding/failures | §3.6 rewritten as C1–C8: canonical typed digest input (fixed-length credential_id 36-byte ASCII UUIDv4, secret 32 raw bytes, length-prefixed framing); presentation phases V/P (§3.2 updated); terminal states reduced to {consumed, revoked, expired} — failed presentations cause NO credential state change (DoS surface removed); anti-theft policy stated |

### 0.2 Earlier rounds (unchanged records)

v0.4→v0.5: MR-10, MR-11, audit-label supplement. v0.3→v0.4: MR-6..MR-9.
v0.2→v0.3: first-round items. v0.1→v0.2: MR-1..MR-5.

## 1. Trust model and naming (unchanged)

## 2. Host signing identity (unchanged)

## 3. Pairing protocol — verifiable state machines

### 3.1 Pairing credential binding tuple and parameters (unchanged from v0.5)

Binds `{ host_instance_id, tls_spki_sha256, srs_key_id, protocol_version
"LPS01-P1", session_nonce }`; secret ≥128-bit random (byte form fixed in
§3.6 C2); `FIXED_BASELINE = 5 minutes` frozen; single use via atomic commit;
operator-revocable.

### 3.2 Host-side state machine (per pairing attempt; presentation phases
updated per MR-13)

```text
IDLE
 → CREDENTIAL_ISSUED        Issued event persisted per §3.6 C2; operator
                             authorization scope recorded; strict-headless
                             pre-binding recorded (expected client pubkey
                             fingerprint read from the client's own display)
 → PRESENTED                 two explicit phases (MR-13):
                             Phase V — CREDENTIAL verification (no state
                             change on failure): credential_id known,
                             unexpired, unconsumed; recomputed digest equals
                             the stored credential_digest (§3.6 C2). Failure
                             (unknown id / wrong secret / expired /
                             consumed) → attempt ABORTED; the credential's
                             state is NOT altered by this request;
                             Phase P — AUTHENTICATED-HOLDER checks (entered
                             only after V succeeds): PoP signature over
                             {session_nonce, credential_id, client_pubkey}
                             verifies; strict-headless prebound key matches
                             (not_prebound_key otherwise); the ACTUAL
                             connection's TLS SPKI equals the bound
                             tls_spki_sha256. Failure → attempt ABORTED;
                             credential state NOT altered (anti-theft
                             policy §3.6 C7);
 → OPERATOR_CONFIRM_PENDING  interactive mode only; mandatory display
                             (issuance-scope label; client public key
                             fingerprint; session nonce short form) and the
                             normative PoP limitation, unchanged from v0.4
 → REGISTERED                ONE atomic registry commit:
                             PAIRING_CREDENTIAL_CONSUMED + CLIENT_REGISTERED
 → terminal (per ATTEMPT): REGISTERED | ABORTED(unknown_credential |
     wrong_secret | expired | already_consumed | revoked | tls_mismatch |
     pop_invalid | not_prebound_key | declined)
   attempt-terminal aborts do NOT by themselves terminate the credential;
   credential-terminal states are exactly {consumed, revoked, expired}
   (§3.6 C6).
```

### 3.3 Client-side state machine; 3.4 Discovery rule; 3.5 Threat boundary
(unchanged from v0.4/v0.5)

### 3.6 Credential persistence, encoding, and failure semantics (MR-13 —
rewritten)

```text
C1 secrecy: the credential secret exists in plaintext ONLY at issuance (host
   memory and the displayed QR/console channel) and in the client's
   possession; it is NEVER written as a bearer secret to the registry, the
   event log, or any diagnostic output; secrets and credential_digest are
   excluded from diagnostic logs;

C2 canonical digest input (typed, length-prefixed, fixed lengths):
   credential_id_bytes = exactly 36 ASCII bytes of the lowercase-hyphenated
                         UUIDv4 string (canonical form; no other form valid);
   secret_bytes        = exactly 32 raw random bytes (≥128-bit entropy by
                         construction; the QR/console DISPLAY may encode them
                         as base64url, but the digest input is the raw bytes);
   credential_digest   = SHA-256(
                           ASCII("LPS01-CRED-V1") + 0x00 +
                           u16_be(len(credential_id_bytes)) + credential_id_bytes +
                           u32_be(len(secret_bytes)) + secret_bytes );
   both lengths are fixed constants; input byte forms are unique; identical
   logical inputs produce identical digests in every implementation; no
   undefined string concatenation occurs anywhere in credential handling;
   the Issued event persists exactly: credential_id, the binding tuple
   (§3.1), validity window, consumption state, and credential_digest;

C3 the digest is verification material — a presented secret allows
   recomputation and comparison; the digest alone cannot complete
   registration (preimage over the 256-bit random secret is infeasible, and
   Phase P additionally requires the client-key proof-of-possession);

C4 atomic consumption: REGISTERED is ONE atomic registry commit consuming
   the credential (PAIRING_CREDENTIAL_CONSUMED) and creating the client
   record (CLIENT_REGISTERED);

C5 (superseded by C6–C8);

C6 credential terminal states are EXACTLY {consumed (successful
   registration), revoked (explicit operator action), expired (time-based)}.
   These are permanent: no processing path re-enables a terminal credential;
   re-issuance always uses a NEW credential_id;

C7 anti-theft policy (explicit choice): presentation failures NEVER alter
   credential state. Unknown credential_id, wrong secret, Phase-P failure
   (invalid PoP, prebound-key mismatch, TLS mismatch), and operator decline
   abort the ATTEMPT only. Rationale: the PoP is an Ed25519 signature over
   challenge material — unforgeable, so retry allowance creates no guessing
   surface; the wrong-secret surface is bounded by the 256-bit random
   secret; the TTL bounds total exposure. Consequently an unauthenticated
   LAN attacker cannot consume, lock, or degrade a valid credential (no
   denial-of-service on legitimate pairing); failure events may be counted
   and logged (credential_id only, no secret material) for operator
   awareness;

C8 presentation phases are ordered and separated (§3.2): Phase V verifies
   the credential secret; ONLY a successful Phase V enters Phase P
   (authenticated-holder processing). Unauthenticated failures (Phase V)
   can never trigger a security disposition of the credential; any future
   credential-terminating security disposition may be applied only to a
   credential that PASSED Phase V, as an explicit operator-recorded action.
```

## 4. Permissions and key-usage boundaries (unchanged)

## 5. Identity lifecycles (unchanged from v0.5)

## 6. LOCALB record format (unchanged from v0.5: envelope fields [0]–[15];
LOCALB_SIGNING_INPUT_V1 with 14 fields incl. issuer_lineage_id; reader
order R1–R7 with R6a–R6g registry cross-verification; INV-1..INV-4;
audit-label §6.3.2; rotation ceremony §6.6)

## 7. Trust registry — integrity, backup, recovery

### 7.1–7.3 (unchanged from v0.5: lineage-scoped key entries; §7.2
trusted-history branches; export/restore mechanics)

### 7.4 Permanent-loss semantics (updated pointer per MR-12)

Two verification classes (Class-1 / Class-2) unchanged; lineage reset
consistency unchanged; archival verification of prior lineages is performed
ONLY through the Archival Verification Context of §7.6 (the v0.5 wording
"restore for archival verification" is superseded by §7.6 — restoration is
never installation as the active registry).

### 7.5 Corrupted / missing / unconfirmable registry (unchanged)

### 7.6 Archival Verification Context — AVC (MR-12 — new)

```text
definition:
  the AVC is a SEPARATE, READ-ONLY historical verification context, opened
  explicitly by an operator action against a specified prior-lineage export
  (event log + recorded head). It reads that export only; it never installs
  old registry material as the active trust registry.

hard prohibitions (context capability boundary):
  the AVC cannot execute client pairing, key rotation, permission changes,
  new record signing, or ANY registry event append; it holds no signing
  keys; loading an AVC never modifies the current lineage's
  host_instance_id, the active registry head, or any current key's
  authorization state.

verification inside the AVC:
  the export's chain is verified with the §7.2 rules RELATIVE TO the
  export's recorded head (the operator's offline record for that export);
  unconfirmable checkpoints or incomplete history yield ARCHIVAL_UNVERIFIED
  for the affected queries — never a trust judgment of any kind.

typed result vocabulary (three distinct judgments, never conflated):
  ARCHIVAL_SIGNATURE_VALID      — Class-1: the record's signature verifies
                                  under a public key present in the export;
  ARCHIVAL_TRUSTED_IN_LINEAGE(L)— Class-2 within lineage L: the record's
                                  (keyID, generation, lineage) matched a
                                  non-REVOKED registry entry in L's verified
                                  history;
  (current-lineage trust)       — produced ONLY by the ACTIVE reader against
                                  the ACTIVE registry; the AVC never issues
                                  it, and no archival result ever converts
                                  into active trust: a prior-lineage record
                                  presented to the ACTIVE reader is still
                                  rejected (ISSUER_UNKNOWN or
                                  ISSUER_LINEAGE_MISMATCH).

operator visibility: AVC results are labeled in all UI/output as archival
  findings about a PRIOR lineage; they grant no standing, no pairing, and no
  permission in the current lineage.
```

## 8. Isolation boundary from Universe A (unchanged)

## 9. Implementation boundary (unchanged)

## 10. Non-goals (unchanged from v0.5)

## 11. OQ disposition table (notes updated)

```text
OQ-1 registry storage/backup  → RESOLVED §7 incl. §7.6 AVC (MR-12);
OQ-2 credential parameters    → RESOLVED §3.1 + §3.6 C1–C8 (canonical
                                 encoding, phases, terminal semantics per
                                 MR-13);
OQ-3 client key scope         → RESOLVED §4.1;
OQ-4 envelope delta           → RESOLVED §6 (unchanged from v0.5);
OQ-5 permission granularity   → RESOLVED §4.2;
OQ-6 SE/P256 variant          → PARK;
OQ-7 discovery                → RESOLVED §3.4;
OQ-8 TLS lifecycle            → RESOLVED §5.
```

## 12. Remaining questions (unchanged)

```text
RQ-1  issuance-scope label form;
RQ-2  checkpoint rebuild cadence — implementation package;
RQ-3  registry event canonicalization for hashing — implementation package.
```
