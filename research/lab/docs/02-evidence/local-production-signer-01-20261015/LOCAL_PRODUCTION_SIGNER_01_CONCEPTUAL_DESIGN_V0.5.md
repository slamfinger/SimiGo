# LOCAL-PRODUCTION-SIGNER-01 — Local Trust Domain B Signing & LAN First-Pairing Conceptual Design v0.5

> **Status:** PENDING HUMAN REVIEW (fourth formal round). Design only; authorizes
> no implementation, no Build/Test, no fixture, no key generation, no
> frozen-object change.
> **Date:** 2026-10-16
> **Supersedes:** v0.4 (same directory; preserved in place), per
> `LOCAL-PRODUCTION-SIGNER-01-DESIGN-V0.4-REVISE-20261016-01`.
> **Scope of this revision:** ONLY MR-10, MR-11, and the
> producer_authorization_reference semantics supplement. MR-7/MR-8/MR-9 are not
> reopened.
> **Governing principle added by the third-round ruling:** a field being SIGNED
> is not the same as the TRUST FACT the field asserts being VERIFIED — every
> signed trust claim in the envelope is cross-checked against the trusted
> registry, and registry state is never inferred from signed claims.

---

## 0. Change logs

### 0.1 v0.4 → v0.5 (third-round items)

| Item | Disposition in v0.5 |
|---|---|
| MR-10 registry-semantics binding | §6.4 R6a–R6g (typed cross-checks incl. generation, lineage, status); new envelope field `[15] issuer_lineage_id` (§6.3), added to the signing projection (§6.3.1, 14 fields); registry key-entry structure with lineage (§7.1); lineage-reset consistency (§7.4); host-scope decision: host-instance-scoped by default, foreign-key import NOT supported in v1 |
| MR-11 credential persistence | new §3.6 (secret only at issuance/client; Issued event stores credential_id + hashed verifier; atomic consumption; terminal states permanent; diagnostics excluded) |
| producer_authorization_reference | §6.3.2: NON-AUTHORITATIVE AUDIT LABEL (chosen) |

### 0.2 v0.3 → v0.4 (unchanged record)

MR-6 signing input V1; MR-7 trusted-history branches; MR-8 reader order;
MR-9 confirmation modes.

### 0.3 Earlier rounds (unchanged records)

v0.2 → v0.3: TTL baseline; PoP limitation; rollback branches; two verification
classes. v0.1 → v0.2: MR-1..MR-5.

## 1. Trust model and naming (unchanged)

Two trust universes (A frozen / B local registry); first trust enters only
through the trusted local channel; `LOCALB` naming; bare "production"
forbidden on Domain-B artifacts.

## 2. Host signing identity (unchanged)

One long-term Ed25519 keypair (`Curve25519.Signing`), Keychain-stored; keyID =
lowercase-hex SHA-256 of the raw public key (deterministic fingerprint, never a
substitute for public-key verification); `SETUP → persist + read-back verify →
OPERATIONAL`; zero fallback; `IDENTITY_DEGRADED` on mismatch.

## 3. Pairing protocol — verifiable state machines

### 3.1 Pairing credential binding tuple and parameters (unchanged from v0.4)

Binds `{ host_instance_id, tls_spki_sha256, srs_key_id, protocol_version
"LPS01-P1", session_nonce }`; secret ≥128-bit random; `FIXED_BASELINE = 5
minutes` frozen; single use; operator-revocable.

### 3.2 Host-side state machine (unchanged from v0.4, incl. the three
confirmation modes — interactive default / strict headless default for headless
deployments with pre-bound client public key / degraded headless opt-in with
UNVERIFIED intent label; normative PoP limitation; terminal abort set incl.
`not_prebound_key`)

### 3.3 Client-side state machine; 3.4 Discovery rule; 3.5 Threat boundary
(unchanged from v0.4)

### 3.6 Credential persistence and secrecy (MR-11 — new)

```text
C1 the credential secret exists in plaintext ONLY at issuance (host memory
   and the displayed QR/console channel) and in the client's possession; it
   is NEVER written as a bearer secret to the registry, the event log, or
   any diagnostic output;
C2 the Issued event persists exactly: credential_id, the binding tuple
   (§3.1), validity window, consumption state, and
   credential_digest = SHA-256("LPS01-CRED-V1" || credential_id || secret);
   the digest is verification material — a presented secret allows
   recomputation and comparison, but the digest alone cannot complete
   registration (preimage over a ≥128-bit random secret is infeasible, and
   presentation additionally requires the client-key proof-of-possession);
C3 credential secrets and credential_digest are excluded from diagnostic
   logs;
C4 REGISTERED is ONE atomic registry commit consuming the credential
   (PAIRING_CREDENTIAL_CONSUMED) and creating the client record
   (CLIENT_REGISTERED);
C5 credential terminal states (expired, revoked, consumed, failed
   presentation) are PERMANENT: no processing path re-enables an old
   credential; re-issuance always uses a NEW credential_id.
```

## 4. Permissions and key-usage boundaries (unchanged)

Client key: authn + PoP only. LOCALB signing key: SRS records only, never
leaves host Keychain. TLS key: transport only. Classes `P-INFERENCE,
P-INFO-READ, P-SRS-WRITE (host-exclusive), P-ADMIN-PAIRING, P-ADMIN-TRUST`;
default-deny; per-request registry consultation.

## 5. Identity lifecycles (one row added)

TLS pin = SPKI hash (renewal with same key preserves pairings; key replacement
→ explicit re-pairing); LOCALB rotation → ceremony, prior keys retained;
LOCALB private-key loss → KEY_LOST declared, public key retained, historical
verification preserved, new signing blocked; **REVOCATION (suspected
compromise) → registry status REVOKED — verification fails closed INCLUDING
for historical records (§6.4 R6f), and the entry is retained append-only**.
No network event rotates a trust root.

## 6. LOCALB record format — issuer and boundary

### 6.1 Grounding facts (unchanged)

A-domain envelope checks ordered `[0] envelope_schema_id` first, before
payload parsing and signature verification; I0 Schema v1.6: 13 required
members, three consts.

### 6.2 Decision (unchanged): option (a) — independent LOCALB envelope

### 6.3 LOCALB envelope fields (v1, frozen at design freeze; [15] added in
v0.5 per MR-10)

```text
frame: physical framing REUSED unchanged — trust-neutral;
[0]  envelope_schema_id      = "SIMIGO_PERSISTENT_SRS_LOCALB_ENVELOPE_V1"
[1]  storage_format_version  = "PERSISTENT_SRS_LOCALB_STORAGE_V1"
[2]  logical_key_identity      [3] logical_key_version
[4]  payload_digest_hex
[5]  encoding_identity       = "PERSISTENT_SRS_CANONICAL_V1"  // SHARED
[6]  signature_domain        = "SIMIGO_PERSISTENT_SRS_LOCALB_RECORD_SIGNATURE_V1"
[7]  signer_public_key_raw   = LOCALB signer's raw 32-byte public key
[8]  signature_raw           = Ed25519 over LOCALB_SIGNING_INPUT_V1 (§6.3.1)
[9]  producer_authorization_reference (semantics: §6.3.2)
[10] decision_core_source_commit  = same accepted Decision Core values as A
[11] decision_core_source_sha256
[12] completion_state        = "COMPLETE"
[13] issuer_key_id           = 64-hex keyID of [7]
[14] issuer_generation       = u32
[15] issuer_lineage_id       = the host_instance_id (registry lineage UUID) of
                               the signing host — B-envelope layer only; binds
                               the record to the registry lineage whose state
                               interprets it (MR-10)
payload: I0 JSON Schema v1.6 VERBATIM, reused unmodified; [13]/[14]/[15] are
ENVELOPE fields — the schema's 13 members and consts are untouched.
```

### 6.3.1 `LOCALB_SIGNING_INPUT_V1` (updated: 14 fields)

```text
LOCALB_SIGNING_INPUT_V1 :=
  ASCII("SIMIGO_PERSISTENT_SRS_LOCALB_SIGNING_INPUT_V1") + 0x00 +
  u32_be(field_count = 14) +
  Σ FIELD(label, type, value) in the fixed order below;
FIELD := label_length_u16 + label_ascii + value_type_u8 +
         value_length_u64 + value_bytes;   // big-endian; framing family
// identical to the frozen attempt-evidence FIELD encoding; value types used:
// 0x02 UTF8_STRING, 0x04 BYTE_SEQUENCE.

 01 envelope_schema_id               UTF8_STRING          ← [0]
 02 storage_format_version           UTF8_STRING          ← [1]
 03 logical_key_identity             UTF8_STRING          ← [2]
 04 logical_key_version              UTF8_STRING          ← [3]
 05 encoding_identity                UTF8_STRING          ← [5]
 06 signature_domain                 UTF8_STRING          ← [6]
 07 signer_public_key_raw            BYTE_SEQUENCE(32)    ← [7]
 08 producer_authorization_reference UTF8_STRING          ← [9]
 09 decision_core_source_commit      UTF8_STRING          ← [10]
 10 decision_core_source_sha256      UTF8_STRING          ← [11]
 11 completion_state                 UTF8_STRING          ← [12]
 12 issuer_generation                BYTE_SEQUENCE(4, BE) ← [14]
 13 issuer_lineage_id                UTF8_STRING          ← [15]
 14 canonical_payload                BYTE_SEQUENCE        (exact canonical I0
                                                          payload bytes)

signature_raw [8] = Ed25519.Sign(local private key, LOCALB_SIGNING_INPUT_V1).

exclusions (each with its stated protection):
 [8]  signature_raw      cannot sign itself;
 [4]  payload_digest_hex DERIVED — recomputed over field 14 (signed) and
                         compared to the frame digest and [4] (§6.4 R5);
 [13] issuer_key_id      DERIVED — recomputed from [7] (field 07, signed) and
                         registry-checked (§6.4 R6a);
 frame-level lengths/digests/magics — byte-level frame checks (§6.4 R1).
completeness statement: every envelope field affecting record identity,
attribution, authorization interpretation, key-generation semantics, OR
lineage scope is INSIDE the projection; unsigned envelope content is limited
to the signature and two derived fields, each independently verified.
```

### 6.3.2 `producer_authorization_reference` semantics (supplement — chosen)

```text
NON-AUTHORITATIVE AUDIT LABEL:
  the field is signature-protected ATTRIBUTION information — it records which
  LOCALB operator authorization reference the signer associated with the
  record. It MUST NOT be used, alone or together with signature validity, to
  claim that the referenced authorization exists, is valid, or covers any
  operation. Verification of authorization references, if ever required, is a
  separate future capability requiring its own design and authorization; v1
  introduces no second authorization system for it.
```

### 6.4 LOCALB Reader verification order (R6 expanded per MR-10; R1–R5, R7
unchanged from v0.4)

```text
R1 physical frame structure (byte-level only);
R2 obtain envelope_schema_id WITHOUT payload parsing (frame offsets);
R3 schema-id check — non-LOCALB → typed rejection HERE;
R4 envelope constants and full envelope field structure;
R5 payload checks — digest equality (byte-level recompute vs frame digest and
   [4]); strict JSON parse; closed I0 schema validation; canonical-byte
   equality;
R6 trust checks — REGISTRY-SEMANTIC CROSS-VERIFICATION (MR-10):
  R6a recompute issuer_key_id = SHA-256([7]); compare to [13]
      (mismatch → ISSUER_KEYID_MISMATCH);
  R6b registry lookup by [13]; unknown keyID → typed rejection
      (ISSUER_UNKNOWN);
  R6c [7] bytes == the registered public key bytes
      (mismatch → ISSUER_PUBKEY_MISMATCH);
  R6d [14] issuer_generation == the registry entry's recorded generation for
      that keyID (mismatch → ISSUER_GENERATION_MISMATCH);
  R6e [15] issuer_lineage_id == the registry entry's lineage_id AND == the
      current registry lineage (mismatch → ISSUER_LINEAGE_MISMATCH);
  R6f key status from the SAME trusted registry entry:
      ACTIVE, RETIRED, or LOST keys VERIFY (historical records included);
      REVOKED keys NEVER verify (ISSUER_KEY_REVOKED — suspected compromise
      fails closed for history as well);
  R6g Ed25519 verify of [8] over LOCALB_SIGNING_INPUT_V1.
  ACCEPTANCE RULE (normative): a record is accepted ONLY when the signature
  is valid AND every registry cross-check passes. A valid signature never
  substitutes for trusted registry state; registry state is never inferred
  from signed claims.
R7 verdict: typed success/failure; only ACTIVE keys may sign (signing-time
   enforcement).
fail-closed at every step; no third state.
```

### 6.5 Isolation and acceptance invariants (INV-3 text updated)

```text
INV-1 (unchanged) A-side early structural rejection of LOCALB envelopes;
INV-2 (unchanged) B-side early structural rejection of A envelopes (R3),
     never via later signature failure;
INV-3 (updated)  the LOCALB signature is computed over
     LOCALB_SIGNING_INPUT_V1, binding every envelope field with identity,
     attribution, authorization, key-generation, OR LINEAGE semantics — now
     including issuer_lineage_id [15] — plus the canonical payload; unsigned
     content is limited to the signature and two derived fields, each
     independently verified; the signature is not transplantable across
     schema, domain, metadata, or lineage interpretations;
INV-4 (unchanged) frozen-schema compatibility: envelope-layer issuer fields
     only; I0 Schema v1.6 untouched; no modification of Contract v1.8 or the
     frozen anchor.
```

### 6.6 Rotation ceremony (unchanged)

Explicit operator action; prior keys RETIRED and retained; never silent;
never network-triggered.

## 7. Trust registry — integrity, backup, recovery

### 7.1 Structure (key-entry shape added per MR-10)

```text
append-only hash-chained event log (authority) + derived checkpoint (cache);
one event per trust transition; atomic commit discipline unchanged;
registry key entries carry exactly:
  { keyID → raw public key bytes, generation (u32, per-lineage monotonic),
    status (ACTIVE | RETIRED | LOST | REVOKED), lineage_id, created_at,
    provenance ("initialized-at" | "rotated-from:<keyID>" |
                "status-set:<reason>") };
host-instance scope (MR-10 decision): LOCALB records are HOST-INSTANCE-SCOPED
  by default — verification requires the signing key's entry to live in the
  CURRENT registry lineage ([15] + R6e); IMPORT of foreign-lineage keys is
  NOT SUPPORTED in v1 and is an explicit non-goal (any future import would
  require its own design, its own typed verification rules, and separate
  authorization);
REVOKED entries are retained (append-only history) and never verify.
```

### 7.2 Load/restore decision (unchanged from v0.4 — B1 rollback/fork, B2
continuity unknown, B3 trusted extension; re-initialization after B1 requires
a new lineage)

### 7.3 Backup and restore (unchanged)

### 7.4 Permanent-loss semantics (lineage-reset consistency added per MR-10)

```text
two verification classes (unchanged from v0.4: Class-1 cryptographic /
Class-2 trust-state; reader verdict always requires the registry; records
never restore registry authority).
lineage reset (MR-10): a new lineage restarts generation at 1 WITHIN the new
lineage only; [15] + R6e make old-lineage generation values un-interpretable
in a new lineage (their records are rejected by keyID-unknown or
ISSUER_LINEAGE_MISMATCH); the reset rule is therefore consistent with the
host_instance_id change rule of §7.2 B1.
operational consequence (unchanged): new lineage → all clients re-pair; old
records stay reader-unverified unless a backup of the OLD lineage registry
is restored for archival verification purposes (an explicit, logged operator
action that never grants the old keys standing in the new lineage).
```

### 7.5 Corrupted / missing / unconfirmable registry (unchanged)

## 8. Isolation boundary from Universe A (unchanged)

## 9. Implementation boundary (unchanged)

## 10. Non-goals (one line added)

As v0.4, plus: foreign-lineage key import (explicit non-goal in v1, §7.1).

## 11. OQ disposition table (notes updated)

```text
OQ-1 registry storage/backup  → RESOLVED §7 (trusted-history relation §7.2;
                                 lineage-scoped key entries §7.1);
OQ-2 credential parameters    → RESOLVED §3.1 + §3.6 (persistence/secrecy
                                 per MR-11);
OQ-3 client key scope         → RESOLVED §4.1;
OQ-4 envelope delta           → RESOLVED §6 incl. §6.3.1 (14-field signing
                                 input), §6.3.2 (audit-label semantics),
                                 §6.4 R6a–R6g (registry cross-verification),
                                 §6.5 INV-1..4;
OQ-5 permission granularity   → RESOLVED §4.2;
OQ-6 SE/P256 variant          → PARK; Ed25519/Keychain baseline;
OQ-7 discovery                → RESOLVED §3.4; details implementation-time;
OQ-8 TLS lifecycle            → RESOLVED §5 (REVOKED row added).
```

## 12. Remaining questions (unchanged)

```text
RQ-1  issuance-scope label form;
RQ-2  checkpoint rebuild cadence — implementation package;
RQ-3  registry event canonicalization for hashing — implementation package.
```
