# LOCAL-PRODUCTION-SIGNER-01 — Local Trust Domain B Signing & LAN First-Pairing Conceptual Design v0.4

> **Status:** PENDING HUMAN REVIEW (third formal round). Design only; authorizes
> no implementation, no Build/Test, no fixture, no key generation, no
> frozen-object change.
> **Date:** 2026-10-15
> **Supersedes:** v0.3 (same directory; preserved in place), per
> `LOCAL-PRODUCTION-SIGNER-01-DESIGN-V0.3-REVISE-20261015-01`.
> **Scope of this revision:** ONLY MR-6, MR-7, MR-8, MR-9. No scope expansion;
> no frozen Universe-A change.
> **Grounding note (unchanged):** §6 grounded in the actual frozen encoding
> constants (`SRSEncodingConstants`, blob `f5ea0130…`) and the actual I0 Schema
> v1.6 file (13 required top-level members, three consts), both read in full.
> **Naming rule (unchanged):** all Domain-B identities carry the `LOCALB`
> marker; no bare "production" labeling.

---

## 0. Change logs

### 0.1 v0.3 → v0.4 (second-round formal review items)

| Item | Disposition in v0.4 |
|---|---|
| MR-6 signing input completeness | §6.3.1: canonical byte-level `LOCALB_SIGNING_INPUT_V1` (13-field TLV projection) + per-field exclusion/justification table |
| MR-7 checkpoint continuity | §7.2 rewritten: B1/B2/B3 compare trusted-history relation; re-initialization requires a new lineage |
| MR-8 reader order | §6.4 rewritten as the explicit seven-step order; frame parsing vs payload parsing defined and separated; early schema-id rejection precedes all payload work |
| MR-9 headless semantics | §3.2: strict headless (pre-bound client public key) = default; degraded credential-holder-priority mode = separate, explicitly authorized, never presented as identity verification |

### 0.2 v0.2 → v0.3 (first-round items — all confirmed closed by the second
review except where MR-6..MR-9 reopen deeper layers)

TTL fixed baseline (§3.1); PoP limitation normative (§3.2); rollback branches
(§7.2 — now superseded by MR-7 form); two verification classes (§7.4 —
confirmed fixed); INV-1..4 (§6.5 — INV-3 now superseded by §6.3.1).

### 0.3 v0.1 → v0.2 (unchanged record)

MR-1..MR-5 as registered in the v0.1 REVISE ruling.

## 1. Trust model and naming (unchanged)

Two trust universes (A frozen / B local registry); first trust enters only
through the trusted local channel; `LOCALB` naming; bare "production"
forbidden on Domain-B artifacts.

## 2. Host signing identity (unchanged)

One long-term Ed25519 keypair (`Curve25519.Signing`), Keychain-stored raw
32-byte private key (Secure Enclave = P256 only; OQ-6 PARK). keyID =
lowercase-hex SHA-256 of the raw public key — deterministic one-to-one
fingerprint that NEVER substitutes for public-key verification; unknown
keyID → reject. `SETUP → [load or generate] → [persist + read-back verify] →
OPERATIONAL`; zero fallback; mismatch → `IDENTITY_DEGRADED`.

## 3. Pairing protocol — verifiable state machines

### 3.1 Pairing credential binding tuple and parameters (unchanged from v0.3)

Binds `{ host_instance_id, tls_spki_sha256, srs_key_id, protocol_version
"LPS01-P1", session_nonce }`; credential secret ≥128-bit random;
`FIXED_BASELINE = 5 minutes` frozen in design, not configurable in v1; single
use via atomic registry event; operator-revocable.

### 3.2 Host-side state machine (per pairing attempt; confirmation modes
rewritten per MR-9)

```text
IDLE
 → CREDENTIAL_ISSUED        credential persisted as an Issued event; the
                             operator authorization scope recorded at the
                             local console; in strict-headless mode the
                             credential is additionally PRE-BOUND to an
                             expected client public key fingerprint (see
                             confirmation modes below)
 → PRESENTED                 client presented {credential, client pubkey, PoP
                             signature} over TLS; host verified: credential
                             unexpired AND unconsumed; PoP covers
                             {session_nonce, credential_id, client_pubkey}
                             and verifies; the ACTUAL connection's TLS SPKI
                             equals the bound tls_spki_sha256; in strict
                             headless mode, the presented client pubkey MUST
                             equal the pre-bound key — any other presenter
                             fails HERE
 → OPERATOR_CONFIRM_PENDING  interactive mode only; the interface MUST
                             display: (i) issuance-scope label; (ii) CLIENT
                             PUBLIC KEY FINGERPRINT (first 16 hex of
                             SHA-256(client pubkey)); (iii) session nonce
                             short form; operator cross-checks against the
                             client's own display where possible.
                             LIMITATION, NORMATIVE: proof-of-possession
                             proves key possession ONLY; a forwarded
                             credential may be consumed by a different key
                             holder; operator confirmation authorizes
                             EXACTLY the presented identity and NOTHING
                             about that identity being the expected device.
 → REGISTERED                one atomic registry commit:
                             PAIRING_CREDENTIAL_CONSUMED + CLIENT_REGISTERED
 → terminal: REGISTERED | ABORTED(expired | consumed | revoked | tls_mismatch
                             | pop_invalid | not_prebound_key | declined)

Confirmation modes (MR-9):
  interactive (desktop default)   OPERATOR_CONFIRM_PENDING as above;
  strict headless (DEFAULT for
  headless deployments)          the credential is issued PRE-BOUND to an
                                 expected client public key fingerprint,
                                 which the operator reads from the CLIENT
                                 DEVICE'S OWN DISPLAY at issuance time
                                 (trusted out-of-band identity confirmation);
                                 only the pre-bound key can complete
                                 registration;
  degraded headless ("credential-
  holder-priority registration") opt-in ONLY; requires a separate operator
                                 authorization, recorded as a registry event,
                                 BEFORE first use; guarantees only credential
                                 validity + PoP validity and provides NO
                                 expected-device identity assurance; the
                                 issuance-scope label is displayed and
                                 recorded as an UNVERIFIED intent note,
                                 never as a verified identity.
```

### 3.3 Client-side state machine (unchanged from v0.3)

`DISCOVERED → CONNECTED (TLS; compare ACTUAL TLS SPKI hash and host-presented
keyID against QR/console values; mismatch → ABORT) → PAIRING_SUBMITTED →
PAIRED (stores {host_instance_id, tls_spki_sha256, srs_key_id, permissions})
| ABORTED`; no partial binding stored.

### 3.4 Discovery rule (unchanged)

Leads only; never trust; never a substitute for the QR/console channel.

### 3.5 Threat boundary (one line added)

As in v0.3 (resists passive observation, pairing-time fake host, credential
replay, later rogue keys, silent trust changes; does NOT promise host
compromise, QR forwarding, full relay, compromised clients, guessing;
first-trust conditions A1–A3). The QR-forwarding / full-relay non-guarantees
apply ONLY to interactive and degraded-headless modes; strict headless
removes them for the pre-bound key at the cost of requiring the operator to
read the client's display at issuance.

## 4. Permissions and key-usage boundaries (unchanged)

Client identity key: connection authn + PoP only. LOCALB signing key: signs
SRS records only; never leaves host Keychain. Host TLS key: transport only.
Classes: `P-INFERENCE, P-INFO-READ, P-SRS-WRITE (host-exclusive, structurally
non-grantable), P-ADMIN-PAIRING, P-ADMIN-TRUST`; default-deny; default grant
= {P-INFERENCE, P-INFO-READ}; per-request registry consultation (revocation
effective at next request).

## 5. Identity lifecycles (unchanged)

TLS pin = SPKI hash; renewal (same key) preserves pairings; TLS key
replacement → explicit re-pairing campaign; LOCALB rotation → ceremony,
prior keys retained; LOCALB private-key loss → KEY_LOST declared, public key
retained, historical verification preserved, new signing blocked. No network
event rotates a trust root; TLS validity ≠ SRS signing trust.

## 6. LOCALB record format — issuer and boundary

### 6.1 Grounding facts (unchanged from v0.3)

A-domain envelope value checks in `SRSReader.read` run in order: field `[0]
envelope_schema_id` (else `unknownEnvelopeSchema`), `[1]`, `[5]`, `[12]` —
all before payload parsing (R15+) and signature verification (R25). I0
Schema v1.6: 13 required members, consts on `payload_schema_id` /
`encoding_identity` / `decision_core_binding`.

### 6.2 Decision (unchanged): option (a) — independent LOCALB envelope

Option (b) wrapper remains rejected.

### 6.3 LOCALB envelope fields (v1, frozen at design freeze)

```text
frame: physical framing REUSED unchanged (SIMISRSV1001 / SIMISRSV1END,
       physical version 1, lengths, digests) — trust-neutral;
[0]  envelope_schema_id      = "SIMIGO_PERSISTENT_SRS_LOCALB_ENVELOPE_V1"
[1]  storage_format_version  = "PERSISTENT_SRS_LOCALB_STORAGE_V1"
[2]  logical_key_identity      [3] logical_key_version        (A-parallel)
[4]  payload_digest_hex
[5]  encoding_identity       = "PERSISTENT_SRS_CANONICAL_V1"  // SHARED
[6]  signature_domain        = "SIMIGO_PERSISTENT_SRS_LOCALB_RECORD_SIGNATURE_V1"
[7]  signer_public_key_raw   = LOCALB signer's raw 32-byte public key
[8]  signature_raw           = Ed25519 over LOCALB_SIGNING_INPUT_V1 (§6.3.1)
[9]  producer_authorization_reference = LOCALB operator authorization ref
[10] decision_core_source_commit  = same accepted Decision Core values as A
[11] decision_core_source_sha256    (consistent with payload schema const)
[12] completion_state        = "COMPLETE"
[13] issuer_key_id           = 64-hex keyID of [7]     // B-envelope layer only
[14] issuer_generation       = u32                     // B-envelope layer only
payload: I0 JSON Schema v1.6 VERBATIM, reused unmodified; issuer fields are
ENVELOPE fields — the schema's 13 members and consts are untouched.
```

### 6.3.1 `LOCALB_SIGNING_INPUT_V1` — canonical signed projection (MR-6)

```text
definition:
LOCALB_SIGNING_INPUT_V1 :=
  ASCII("SIMIGO_PERSISTENT_SRS_LOCALB_SIGNING_INPUT_V1") + 0x00 +
  u32_be(field_count = 13) +
  Σ FIELD(label, type, value) in the fixed order below;

FIELD := label_length_u16 + label_ascii_bytes + value_type_u8 +
         value_length_u64 + value_bytes          // all integers big-endian;
// framing family identical to the frozen attempt-evidence FIELD encoding
// (Manifest v2.2 §9); only two value types occur here:
//   0x02 UTF8_STRING, 0x04 BYTE_SEQUENCE.

fixed field order (13):
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
 12 issuer_generation                BYTE_SEQUENCE(4, big-endian u32) ← [14]
 13 canonical_payload                BYTE_SEQUENCE        (exact canonical
                                                          I0 payload bytes)

signature_raw [8] = Ed25519.Sign(local private key, LOCALB_SIGNING_INPUT_V1).

exclusions, each with its stated protection:
 [8]  signature_raw      cannot sign itself; it IS the protection target;
 [4]  payload_digest_hex DERIVED — verification recomputes SHA-256 over the
                         canonical payload (field 13, signed) and compares
                         it to BOTH the frame digest and this field
                         (§6.4 R5); tampering is detected without signing it;
 [13] issuer_key_id      DERIVED — recomputed as SHA-256 of [7] (field 07,
                         signed) and cross-checked against the registry
                         (§6.4 R6);
 frame-level lengths, digests, magics — protected by the byte-level frame
                         structural and digest-recomputation checks
                         (§6.4 R1), which never parse the payload.

completeness statement: every envelope field that affects record identity,
attribution, authorization interpretation, or key-generation semantics is
INSIDE the signed projection; the only unsigned envelope fields are the
signature itself and two derived fields, each detected by independent
byte-level verification. There is no ad-hoc concatenation: the input is a
uniquely reproducible byte-level TLV structure with fixed order, typed
lengths, and a magic prefix.
```

### 6.4 LOCALB Reader verification order (MR-8)

```text
definitions used below:
  frame parsing    = structural slicing of the physical frame (boundaries,
                     lengths, magics) and byte-level digest recomputation
                     over byte ranges; it NEVER interprets payload content;
  payload parsing  = JSON / schema interpretation of the payload bytes.

R1 physical frame structure: boundaries, declared lengths, magics; every
   slice in range; typed failure on any violation (byte-level only);
R2 obtain envelope_schema_id WITHOUT payload parsing — the envelope is a
   contiguous frame region addressable by frame offsets; decode only the
   envelope's first field;
R3 envelope_schema_id check: != LOCALB const → typed rejection HERE. A-domain
   records die at this step; early structural isolation precedes ALL payload
   work (realizable because R2 needs only frame offsets, not payload
   interpretation);
R4 envelope constants and full envelope field structure: storage version,
   encoding identity, completion state, signature domain, field types and
   lengths;
R5 payload checks: payload-digest equality (byte-level recompute vs frame
   digest and vs [4]); strict JSON parse; closed I0 schema validation;
   canonical-byte equality;
R6 trust checks: issuer_key_id [13] recomputed from [7] and looked up in the
   registry (unknown → reject); [7] bytes == registered public key bytes;
   Ed25519 verify of [8] over LOCALB_SIGNING_INPUT_V1 (§6.3.1);
R7 verdict: typed success/failure; any registered key (ACTIVE or RETIRED)
   may verify; only ACTIVE may sign (enforced at signing time).
fail-closed at every step; no third state.
```

### 6.5 Isolation and acceptance invariants (INV-3 updated per MR-6)

```text
INV-1 structural, A side: the A-domain Reader rejects a LOCALB envelope at
     its early envelope-schema check, before payload parsing and signature
     logic (grounded in the frozen check order, §6.1);
INV-2 structural, B side: the LOCALB reader rejects an A envelope at R3, its
     own early schema check — B-side isolation is structural, never realized
     through later signature failure (§6.4 R2–R3);
INV-3 cryptographic domain separation: the LOCALB signature is computed over
     LOCALB_SIGNING_INPUT_V1, which deterministically binds EVERY envelope
     field carrying identity, attribution, authorization, or key-generation
     semantics — including envelope_schema_id, signature_domain,
     logical_key_identity/version, producer_authorization_reference, and
     issuer_generation — plus the canonical payload (§6.3.1); unsigned
     envelope content is limited to the signature itself and two derived
     fields, each protected by independent byte-level verification; the
     signature is therefore not transplantable across schema, domain, or
     metadata interpretations;
INV-4 frozen-schema compatibility boundary: issuer fields [13]/[14] are
     B-envelope-layer only; I0 Schema v1.6's 13 members and consts are
     untouched; no LOCALB mechanism modifies Contract v1.8 or the frozen
     anchor in PersistentSRSRepresentation.swift.
All four must hold simultaneously at design freeze; they are related but not
interchangeable.
```

### 6.6 Rotation ceremony (unchanged)

Explicit operator action at the local console; prior keys RETIRED and
retained; never silent, never network-triggered.

## 7. Trust registry — integrity, backup, recovery

### 7.1 Structure (unchanged)

Append-only hash-chained event log (authority) + derived checkpoint (cache);
one event per trust transition; atomic commit (durable append then
checkpoint rebuild; crash between → log wins).

### 7.2 Load/restore decision — trusted-history relation (rewritten per MR-7)

```text
GUARANTEE STATEMENT (normative): the hash chain proves internal consistency
relative to a trusted position. It never alone proves absence of rollback;
detection depends on a trusted checkpoint that did not roll back with the
data — the operator's offline head record (§7.3). The comparison below is a
TRUSTED-HISTORY RELATION, not head equality: legitimate later writes (new
pairings, revocations, rotations) extend the chain past the checkpoint and
must remain in B3.

B1 rollback or fork — ANY of:
   (a) local head seq < trusted-checkpoint seq;
   (b) same seq, different hash (local vs checkpoint);
   (c) the checkpoint's bound (seq, hash) position cannot be found in the
       local log;
   → refuse to start trust services; enter the explicit recovery flow.
     Re-initialization after B1 REQUIRES a new lineage (new
     host_instance_id; generation restarts at 1) and a freshly recorded
     trusted head; appending a "re-initialized" event onto the possibly
     rolled-back log NEVER clears a B1 condition.

B2 continuity unknown — the trusted checkpoint is missing or unconfirmable,
   or the log is insufficient to verify continuity
   → fail-closed exactly as §7.5; continuity must NOT be claimed as verified;
     resolution = supply a checkpoint, restore a verified backup, or
     explicitly re-initialize (new lineage).

B3 trusted extension — the local log CONTAINS the checkpoint's exact
   (seq, hash) position AND the current head is a verifiable chain extension
   from that position (or equals it)
   → normal operation.
```

### 7.3 Backup and restore (unchanged mechanics, MR-7 semantics)

Export = full log + head (seq, head_hash); head displayed at every export
and recorded offline by the operator (the trusted external checkpoint).
Restore = verify chain → apply §7.2 B1/B2/B3 → explicit operator
confirmation. Restores never create new trust silently.

### 7.4 Permanent-loss semantics — two verification classes (unchanged from
v0.3, confirmed fixed by the second review)

Class-1 cryptographic signature verification (possible whenever the public
key bytes are preserved; establishes signature validity only) vs Class-2
historical trust-state verification (requires registry history or trusted
backup). Permanent loss without backup destroys Class-2; Class-1 remains
possible with preserved keys, but the LOCALB reader's verdict always
requires the registry, so records remain reader-unverified absent a restore.
A Class-1-valid signature NEVER implies current trust; records never restore
registry authority.

### 7.5 Corrupted / missing / unconfirmable registry (unchanged)

No new trust establishment; protected requests fail closed; only
unprotected discovery continues; pending-verification records are never a
trust source.

## 8. Isolation boundary from Universe A (unchanged)

No local key into the frozen anchor or frozen documents; no LOCALB signature
presented as Contract v1.8 production signature; no A record enters the
local registry; no cross-domain trust inference either direction; A-line
resumption stays a separate D2-style governance decision.

## 9. Implementation boundary (unchanged)

New files under a separately authorized writable-path set; frozen module
unmodified; stage separation with separate authorizations; this design
authorizes nothing.

## 10. Non-goals (unchanged)

As v0.3.

## 11. OQ disposition table (notes updated)

```text
OQ-1 registry storage/backup  → RESOLVED §7 (incl. §7.2 trusted-history
                                 relation per MR-7);
OQ-2 credential parameters    → RESOLVED §3.1–3.2 (TTL fixed baseline;
                                 confirmation modes per MR-9);
OQ-3 client key scope         → RESOLVED §4.1;
OQ-4 envelope delta           → RESOLVED §6 incl. §6.3.1 signing input
                                 (MR-6), §6.4 reader order (MR-8),
                                 §6.5 INV-1..4;
OQ-5 permission granularity   → RESOLVED §4.2;
OQ-6 SE/P256 variant          → PARK; Ed25519/Keychain baseline;
OQ-7 discovery                → RESOLVED §3.4 (lead-only); details
                                 implementation-time;
OQ-8 TLS lifecycle            → RESOLVED §5.
```

## 12. Remaining questions (unchanged)

```text
RQ-1  issuance-scope label form (free-form note vs structured descriptor);
RQ-2  checkpoint rebuild cadence — implementation package;
RQ-3  registry event canonicalization for hashing (SRS JCS-style family
      proposed) — frozen in the implementation package.
```
