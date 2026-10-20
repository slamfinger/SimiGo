# LOCAL-PRODUCTION-SIGNER-01 — Local Trust Domain B Signing & LAN First-Pairing Conceptual Design v0.7

> **Status:** PENDING HUMAN REVIEW (sixth formal round). Design only; authorizes
> no implementation, no Build/Test, no fixture, no key generation, no
> frozen-object change.
> **Date:** 2026-10-16
> **Supersedes:** v0.6 (same directory; preserved in place), per
> `LOCAL-PRODUCTION-SIGNER-01-DESIGN-V0.6-REVISE-20261016-01`.
> **Scope of this revision:** ONLY MR-14 (credential plaintext lifecycle),
> MR-15 (archival result semantics vs revocation), MR-16 (bounded failure
> telemetry), MR-17 (fingerprint display vs machine binding). MR-12 stays
> closed; MR-13's architecture is unchanged.

---

## 0. Change logs

### 0.1 v0.6 → v0.7 (fifth-round items)

| Item | Disposition in v0.7 |
|---|---|
| MR-14 plaintext lifecycle | §3.6 C1 rewritten as persistence-vs-runtime boundary |
| MR-15 archival semantics | §7.6 result vocabulary reworked into three non-conflatable layers; `ARCHIVAL_TRUSTED_IN_LINEAGE` superseded by `ARCHIVAL_REGISTRATION_MATCH(L, status)` with an explicit no-signing-time-claim scope statement |
| MR-16 bounded telemetry | §3.6 C9 added |
| MR-17 fingerprint rules | §3.2 fingerprint display rules added (display_abbrev / human_verification_form 32-hex / full-value machine bindings) |

### 0.2 Earlier rounds (unchanged records)

v0.5→v0.6: MR-12, MR-13. v0.4→v0.5: MR-10, MR-11, supplement. v0.3→v0.4:
MR-6..MR-9. v0.2→v0.3: first-round items. v0.1→v0.2: MR-1..MR-5.

## 1. Trust model and naming (unchanged)

## 2. Host signing identity (unchanged)

## 3. Pairing protocol — verifiable state machines

### 3.1 Pairing credential binding tuple and parameters (unchanged from v0.6)

### 3.2 Host-side state machine (fingerprint display rules added per MR-17;
phases unchanged from v0.6)

```text
fingerprint display rules (MR-17):
  display_abbrev          = first 16 hex of SHA-256(client public key) —
                            a reading aid ONLY; never a machine binding and
                            never the sole basis of human first-trust;
  human_verification_form = first 32 hex (128-bit prefix) of the same
                            fingerprint — the form used in interactive
                            cross-checks and in strict-headless pre-binding
                            confirmation; rationale: targeted impersonation
                            requires finding a key whose fingerprint prefix
                            equals the displayed value (preimage ≈ 2^128);
                            the 16-hex abbrev would offer only ≈ 2^64;
  machine bindings        = the FULL client public key (or the FULL 64-hex
                            fingerprint) is the pre-bound object stored at
                            issuance (strict headless) and the value compared
                            at PRESENTED; short forms never participate in
                            machine comparison.

state machine (unchanged from v0.6 except the display rules above):
IDLE → CREDENTIAL_ISSUED (strict-headless pre-binds the FULL client public
key, read from the client's own display in human_verification_form) →
PRESENTED (Phase V credential verification — no state change on failure;
Phase P authenticated-holder checks — PoP, prebound full-key comparison,
TLS SPKI match) → OPERATOR_CONFIRM_PENDING (interactive only; displays the
issuance-scope label, the human_verification_form fingerprint, and the
session nonce short form; normative PoP limitation applies) → REGISTERED
(one atomic commit: PAIRING_CREDENTIAL_CONSUMED + CLIENT_REGISTERED) |
ABORTED(unknown_credential | wrong_secret | expired | already_consumed |
revoked | tls_mismatch | pop_invalid | not_prebound_key | declined).
Attempt-terminal aborts do not terminate the credential; credential
terminal states are exactly {consumed, revoked, expired} (§3.6 C6).
```

### 3.3 Client-side state machine; 3.4 Discovery rule; 3.5 Threat boundary
(unchanged; §3.5 non-promises now also carry the MR-16 resource-exhaustion
boundary by reference to C9)

### 3.6 Credential persistence, encoding, and failure semantics (C1
rewritten per MR-14; C9 added per MR-16; C2–C8 unchanged from v0.6)

```text
C1 plaintext lifecycle — persistence vs runtime boundary (MR-14):
   the credential secret may exist in memory ONLY (i) at issuance (host
   memory and the displayed QR/console channel), (ii) in the client's
   possession, and (iii) TRANSIENTLY during a Phase-V verification
   (submission transport and host-side digest recomputation);
   it is NEVER persisted: not in the registry, not in the authoritative
   event log, not in persistent diagnostic storage; request bodies, QR
   originals, and error contexts containing the secret are never recorded;
   runtime retention after verification is minimized — best-effort early
   clearing, with the specific memory-clearing mechanism designated an
   implementation requirement, not a design claim;
   credential_digest and the credential secret remain distinct concepts:
   the digest's persistability never makes it a substitute or
   representation of the secret.

C2 canonical digest input — unchanged from v0.6 (36-byte ASCII UUIDv4
   credential_id; 32 raw secret bytes; typed length-prefixed SHA-256 input);
C3 digest properties — unchanged;
C4 atomic consumption — unchanged;
C5 — superseded by C6–C8;
C6 terminal states exactly {consumed, revoked, expired} — unchanged;
C7 anti-theft policy: presentation failures never alter credential state —
   unchanged (telemetry sentence now governed by C9);
C8 ordered V/P phases; unauthenticated failures never trigger security
   dispositions — unchanged;

C9 failure telemetry is bounded and non-authoritative (MR-16):
   presentation failures are NEVER appended to the authoritative event log
   (the trust chain records only Issued/Consumed/Expired/Revoked,
   registration, rotation, and status events); failure telemetry lives in
   bounded, non-authoritative storage (fixed-size counters or ring buffers)
   and may be dropped with no trust effect; rate limiting may be used to
   protect host resources, but no unauthenticated failure may change any
   credential state (C6–C8 unchanged);
   honest boundary: the design does NOT promise resistance to bandwidth
   exhaustion or full resource-exhaustion attacks against the host; the
   guaranteed scope is exactly that such attacks cannot consume, lock, or
   degrade a valid credential's STATE.
```

## 4. Permissions and key-usage boundaries (unchanged)

## 5. Identity lifecycles (unchanged)

## 6. LOCALB record format (unchanged from v0.5/v0.6: envelope [0]–[15];
LOCALB_SIGNING_INPUT_V1 14 fields; reader R1–R7 with R6a–R6g; INV-1..INV-4;
audit-label §6.3.2; rotation ceremony)

## 7. Trust registry — integrity, backup, recovery

### 7.1–7.5 (unchanged from v0.6)

### 7.6 Archival Verification Context — AVC (result vocabulary reworked per
MR-15; context definition and hard prohibitions unchanged from v0.6)

```text
definition and hard prohibitions: unchanged from v0.6 — the AVC is a
separate, read-only historical verification context opened explicitly by an
operator against a specified prior-lineage export (log + recorded head);
it never installs old material as the active registry; it cannot pair,
rotate, change permissions, sign, or append events; it holds no signing
keys; loading it never modifies the current lineage's host_instance_id,
active head, or key authorization states; unconfirmable history yields
ARCHIVAL_UNVERIFIED.

typed result vocabulary — three non-conflatable layers (MR-15):

  LAYER 1 — cryptographic check:
    ARCHIVAL_SIGNATURE_VALID | ARCHIVAL_SIGNATURE_INVALID
    pure computation against a public key present in the export; says
    NOTHING about trust;

  LAYER 2 — historical registration fact:
    ARCHIVAL_REGISTRATION_MATCH(L, status)
    the record's (keyID, generation, lineage) matches the VERIFIED
    registration history of lineage L; `status` reports the entry's
    recorded status in that history (ACTIVE | RETIRED | LOST | REVOKED,
    as of the export);
    scope statement (normative): v1 defines NO trusted signing-time or
    equivalent ordering evidence — timestamps inside the signed payload are
    SIGNER CLAIMS, not evidence — therefore this verdict states ONLY
    "consistent with the verified lineage registration history" and MUST
    NOT be read as independent proof of the key's status at the actual
    signing time;

  LAYER 3 — acceptance verdict:
    produced ONLY by the ACTIVE reader against the ACTIVE registry; the AVC
    never issues acceptance; a REVOKED key may legitimately receive
    LAYER-1 VALID together with LAYER-2 (status = REVOKED), and every
    presentation of that combination MUST carry the explicit annotation
    "signature cryptographically valid; key revoked in lineage history;
    NOT ACCEPTABLE" — never anything readable as current trust or as
    permission to accept the record;

  consistency rule: the status vocabulary and the REVOKED-never-accepts
  rule are IDENTICAL in the active reader and the AVC (active R6f;
  archival layer-2 status); the only difference between the two contexts
  is WHICH registry — active or exported — supplies the facts.

naming note: the v0.6 name ARCHIVAL_TRUSTED_IN_LINEAGE(L) is SUPERSEDED by
ARCHIVAL_REGISTRATION_MATCH(L, status) to eliminate the "trusted at signing
time" reading; ARCHIVAL_SIGNATURE_VALID is retained with its layer-1 scope.
```

## 8. Isolation boundary from Universe A (unchanged)

## 9. Implementation boundary (unchanged)

## 10. Non-goals (one line added)

As v0.6, plus: resistance to bandwidth-level or full resource-exhaustion
attacks (out of scope; credential-state immunity is the guaranteed extent).

## 11. OQ disposition table (notes updated)

```text
OQ-1 registry storage/backup  → RESOLVED §7 incl. §7.6 layered AVC results;
OQ-2 credential parameters    → RESOLVED §3.1 + §3.6 C1–C9 (lifecycle
                                 boundary MR-14; telemetry bound MR-16);
OQ-3 client key scope         → RESOLVED §4.1;
OQ-4 envelope delta           → RESOLVED §6;
OQ-5 permission granularity   → RESOLVED §4.2;
OQ-6 SE/P256 variant          → PARK;
OQ-7 discovery                → RESOLVED §3.4;
OQ-8 TLS lifecycle            → RESOLVED §5.
```

## 12. Remaining questions (one added)

```text
RQ-1  issuance-scope label form;
RQ-2  checkpoint rebuild cadence — implementation package;
RQ-3  registry event canonicalization for hashing — implementation package;
RQ-4  the 128-bit human_verification_form length is a design-chosen
      threshold (preimage ≈ 2^128); if the reviewer prefers full 64-hex
      human comparison in strict mode, that is a display-policy change only.
```
