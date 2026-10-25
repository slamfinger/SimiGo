# LOCAL-PRODUCTION-SIGNER-01 — Local Trust Domain B Signing & LAN First-Pairing Conceptual Design v0.3

> **Status:** PENDING HUMAN REVIEW — second formal review round, first round able to
> review full text. Design only; authorizes no implementation, no Build/Test, no
> fixture, no key generation, no frozen-object change.
> **Date:** 2026-10-15
> **Supersedes:** v0.2 (same directory; preserved in place), per the second-round
> review of 2026-10-15 (summary-based review; the reviewer explicitly designated it
> as NOT a formal governance ruling — this v0.3 exists to close the four identified
> items and to provide reviewable full text).
> **Grounding note (MR-1, unchanged):** §6 is grounded in the actual frozen encoding
> constants (`SRSEncodingConstants`, blob `f5ea0130…`) and the actual I0 Schema
> v1.6 file (13 required top-level members, consts on `payload_schema_id` /
> `encoding_identity` / `decision_core_binding`), both read in full.
> **Naming rule:** all Domain-B identities carry the `LOCALB` marker; no artifact of
> this design may be labeled bare "production".

---

## 0. Change logs

### 0.1 v0.2 → v0.3 (second-round review items)

| Review item | Disposition in v0.3 |
|---|---|
| 1. TTL normative-vs-open conflict | §3.1: `FIXED_BASELINE = 5 minutes`, frozen in design, not configurable in v1; former RQ-1 removed |
| 2. PoP ≠ expected-device identity | §3.2: confirmation UI must display client key fingerprint (cross-check when possible); explicit limitation sentence added; §3.5 unchanged |
| 3. Hash chain cannot alone detect whole-state rollback | §7.2–7.3 rewritten to three explicit branches (trusted-checkpoint mismatch / checkpoint missing / chain-proves-consistency-only) |
| 4. "Unverifiable forever" conflates two classes | §7.4 rewritten with the cryptographic-verification vs trust-state-verification distinction |
| OQ-4 acceptance boundary | §6.5 expanded to four explicit invariants; §6.3[8]/§6.4 step 6 updated so the signature input binds schema + domain + canonical content |

### 0.2 v0.1 → v0.2 (first-round REVISE, unchanged record)

MR-1 → §6; MR-2 → §3; MR-3 → §7; MR-4 → §4; MR-5 → §5; OQ-6 PARK; OQ-7 lead-only
invariant + deferred protocol details; naming constraint → §1.3.

## 1. Trust model and naming

### 1.1 Two trust universes (unchanged)

Universe A: frozen anchor `+fG2YJ+…VMI=` + Contract v1.8 semantics; R27 STOP;
untouched. Universe B: local trust registry on the SimiGo host; root of trust
seeded only by an explicit, operator-present local action.

### 1.2 First-trust principle (unchanged)

Trust never enters through the network; it enters through the trusted local
channel, and the network exchange is CHECKED against what that channel carried.

### 1.3 Naming (unchanged)

Work item `LOCAL-PRODUCTION-SIGNER-01` (registered); every Domain-B identity
carries `LOCALB`; UI labels read "Local Trust Domain B signing identity"; bare
"production" labeling forbidden.

## 2. Host signing identity (LOCALB signer)

### 2.1–2.2 Generation and storage (unchanged)

One long-term Ed25519 keypair via `Curve25519.Signing`; generated only at first
initialization or explicit rotation; private key in a macOS Keychain
generic-password item (raw 32 bytes), host-service access scope. Secure Enclave
residency applies to P256, not Curve25519 (OQ-6 = PARK).

### 2.3 keyID — precise definition (unchanged, restated)

```text
keyID = lowercase-hex( SHA-256( raw 32-byte Ed25519 public key ) );
display form = first 8 hex bytes; registry form = full 64 hex;
generation = u32 monotonic per lineage; identity tuple = (keyID, generation).
Rules: (a) keyID IS a deterministic one-to-one fingerprint of the key bytes;
(b) keyID NEVER substitutes for public-key verification — verification always
fetches the full registered public key BY keyID and verifies with those bytes;
unknown keyID → reject.
```

### 2.4–2.6 Registry pointer, restart, service state machine (unchanged)

`SETUP → [load or generate identity] → [persist + read-back verify] →
OPERATIONAL`; failure stays in SETUP, zero fallback. Restart reads the existing
identity; Keychain/registry mismatch → `IDENTITY_DEGRADED`: signing and
protected APIs disabled; never auto-regeneration.

## 3. Pairing protocol — verifiable state machines

### 3.1 Pairing credential binding tuple and parameters

```text
binds: { host_instance_id, tls_spki_sha256, srs_key_id (full 64-hex),
         protocol_version = "LPS01-P1", session_nonce (128-bit, one-time) }
credential secret: ≥128-bit random, independent of all bound values;
validity window: FIXED_BASELINE = 5 minutes — frozen in this design;
  not configurable in v1; changing it requires a design change;
consumption: single use, enforced by an atomic registry event;
revocable at any time by the operator. Not a long-lived LAN password.
```

### 3.2 Host-side state machine (per pairing attempt)

```text
IDLE
 → CREDENTIAL_ISSUED        credential persisted as an Issued event; the
                             operator authorization scope (free-form label of
                             the intended client) recorded at the local console
 → PRESENTED                 client presented {credential, client pubkey, PoP
                             signature} over TLS; host verified: credential
                             unexpired AND unconsumed; PoP covers
                             {session_nonce, credential_id, client_pubkey} and
                             verifies; the ACTUAL connection's TLS SPKI equals
                             the bound tls_spki_sha256
 → OPERATOR_CONFIRM_PENDING  the confirmation interface MUST display:
                             (i)  the issuance-scope label;
                             (ii) the CLIENT PUBLIC KEY FINGERPRINT
                                  (first 16 hex of SHA-256(client pubkey));
                             (iii) the session nonce short form.
                             When the client device can display its own
                             fingerprint (deployment permitting), the operator
                             cross-checks the two displays.
                             LIMITATION, NORMATIVE: proof-of-possession proves
                             key possession ONLY. It never proves that the
                             presenter is the intended device; a forwarded
                             credential may be consumed by a different key
                             holder; operator confirmation authorizes EXACTLY
                             the presented identity and NOTHING about that
                             identity being the expected device.
                             Headless alternative: the issuance-time operator
                             scope IS the confirmation — valid only because it
                             was created at the local console; LAN reachability
                             or QR visibility NEVER confirms anything.
 → REGISTERED                one atomic registry commit:
                             PAIRING_CREDENTIAL_CONSUMED + CLIENT_REGISTERED
 → terminal: REGISTERED | ABORTED(expired | consumed | revoked | tls_mismatch |
                             pop_invalid | declined)
every transition logged and time-stamped; aborts terminal for that credential.
```

### 3.3 Client-side state machine (unchanged)

```text
DISCOVERED → CONNECTED (TLS; client compares the ACTUAL TLS SPKI hash and the
host-presented keyID against the QR/console values; mismatch → ABORT)
 → PAIRING_SUBMITTED (credential + client pubkey + PoP)
 → PAIRED (stores {host_instance_id, tls_spki_sha256, srs_key_id, permissions})
 → ABORTED on any failure; no partial binding stored.
```

### 3.4 Discovery rule (unchanged)

Discovery provides LEADS only (name, address, optional display fingerprint for
human convenience); never trust; never a substitute for the QR/console channel;
no auto-trust from reachability. Protocol details are implementation-time.

### 3.5 Threat boundary (unchanged from v0.2; §3.2 now normatively carries the
PoP limitation for the confirmation step)

Resists (under A1–A3): passive LAN observation (TLS); pairing-time MITM with a
fake host (SPKI + keyID comparison against the genuine QR); credential replay
(single-use + TTL + nonce); later-appearing rogue keys (registry-or-reject);
silent trust changes (all transitions are operator-actor registry events).
Does NOT promise: full host compromise (out of scope by definition); operator
forwarding the QR/credential (inherent to human-carried credentials); full
relay of the pairing exchange by a QR-content holder (it registers AS ITSELF;
countermeasure = operator scope label + fingerprint cross-check discipline,
not cryptography); compromised client devices (revocation path, §4.3);
guessing (≥128-bit).
First-trust conditions: A1 genuine local console/UI; A2 operator present and
attentive; A3 the client UI faithfully shows what it verified.

## 4. Permissions and key-usage boundaries (unchanged from v0.2)

### 4.1 Key usage separation

Client identity key: connection authentication + PoP ONLY; never SRS signing
rights in any form. LOCALB signing key: signs SRS records ONLY; never leaves
host Keychain; never transferred/wrapped/delegated/proxied to clients. Host TLS
key: transport ONLY. No key serves two roles.

### 4.2 Permission classes

```text
P-INFERENCE, P-INFO-READ, P-SRS-WRITE (HOST-EXCLUSIVE, structurally
non-grantable to clients in v1), P-ADMIN-PAIRING, P-ADMIN-TRUST;
default-deny; least privilege; admin plane separated from inference plane;
default grant at pairing = {P-INFERENCE, P-INFO-READ}; admin classes only via
explicit operator action recorded in the registry.
```

### 4.3 Revocation timing

Every protected request authenticates against CURRENT registry state (no
long-lived authority cache; any later bounded cache TTL is a reviewed
parameter, default none). Revocation effective at the next protected request;
in-flight requests may complete.

## 5. Identity lifecycles (unchanged from v0.2)

TLS pin = `tls_spki_sha256` (SPKI hash, not full-cert), so routine renewal with
an unchanged key pair does not break pairings. Table: TLS cert renewal (same
key) → pairings intact; TLS key replacement → SPKI changes → explicit
operator re-pairing campaign (signed pre-published TLS-rotation notice = optional
future mechanism, own review, not in v1); LOCALB rotation → §6.6, prior keys
retained, historical verification preserved; LOCALB private-key LOSS → registry
records KEY_LOST while RETAINING the public key → historical records remain
verifiable, NEW signing blocked until rotation. No network event ever triggers
a trust-root change; TLS certificate validity is never evidence of SRS signing
trust.

## 6. LOCALB record format — issuer and boundary

### 6.1 Grounding facts (unchanged)

A-domain envelope value checks in `SRSReader.read` run in order: field `[0]
envelope_schema_id` (else `unknownEnvelopeSchema`), `[1]` storage format,
`[5]` encoding identity, `[12]` completion state — all BEFORE payload parsing
(R15+) and signature verification (R25). Frozen constants:
`SIMIGO_PERSISTENT_SRS_ENVELOPE_V1`, domain
`SIMIGO_PERSISTENT_SRS_RECORD_SIGNATURE_V1`, signer = frozen anchor bytes.
I0 Schema v1.6: 13 required members, consts on `payload_schema_id` /
`encoding_identity` / `decision_core_binding`.

### 6.2 Decision (unchanged): option (a) — independent LOCALB envelope

Option (b) wrapper remains rejected (A-shaped envelope signed by a non-A key =
looks-like-A-but-fails-R25 ambiguity, plus double framing).

### 6.3 LOCALB envelope fields (v1, frozen at design freeze)

```text
frame: physical framing REUSED unchanged (SIMISRSV1001 / SIMISRSV1END,
       physical version 1, lengths, digests) — trust-neutral;
[0]  envelope_schema_id      = "SIMIGO_PERSISTENT_SRS_LOCALB_ENVELOPE_V1"
[1]  storage_format_version  = "PERSISTENT_SRS_LOCALB_STORAGE_V1"
[2]  logical_key_identity      [3] logical_key_version        (A-parallel)
[4]  payload_digest_hex
[5]  encoding_identity       = "PERSISTENT_SRS_CANONICAL_V1"  // SHARED, non-trust
[6]  signature_domain        = "SIMIGO_PERSISTENT_SRS_LOCALB_RECORD_SIGNATURE_V1"
[7]  signer_public_key_raw   = LOCALB signer's raw 32-byte public key
[8]  signature_raw           = Ed25519 over
                              ( signature_domain_LOCALB
                                || envelope_schema_id_LOCALB
                                || canonical payload bytes )
                              // schema + domain separator + canonicalized
                              // content are ALL bound into the signed input
[9]  producer_authorization_reference = LOCALB operator authorization ref
[10] decision_core_source_commit  = same accepted Decision Core values as A
[11] decision_core_source_sha256    (semantic binding; consistent with the
                                     payload schema's const)
[12] completion_state        = "COMPLETE"
[13] issuer_key_id           = 64-hex keyID of [7]     // B-envelope layer only
[14] issuer_generation       = u32                     // B-envelope layer only
payload: I0 JSON Schema v1.6 VERBATIM, reused unmodified as the content schema
(all its consts stand); the issuer fields are ENVELOPE fields — the schema's
13 top-level members and consts are untouched.
```

### 6.4 Verification rule (LOCALB reader)

```text
1. frame + digest + canonical-byte checks (same discipline as A);
2. envelope_schema_id == LOCALB const   // A records rejected HERE, at the
                                        // reader's own early schema check —
                                        // isolation never depends on later
                                        // signature failure;
3. signature_domain == LOCALB const; encoding_identity == shared const;
   storage_format_version == LOCALB const; completion_state == "COMPLETE";
4. issuer_key_id registry lookup → unknown → REJECT;
5. signer_public_key_raw bytes == registered public key bytes (both must
   match; keyID never substitutes);
6. Ed25519 verify over ( signature_domain_LOCALB
                         || envelope_schema_id_LOCALB
                         || canonical payload bytes );
7. any registered key (ACTIVE or RETIRED) may verify; only ACTIVE may sign
   (enforced at signing time by the host);
fail-closed, typed statuses, no third state.
```

### 6.5 Isolation and acceptance invariants (expanded per second-round review)

```text
INV-1 structural, A side: the A-domain Reader rejects a LOCALB envelope at its
     early envelope-schema check, before payload parsing and before any
     signature logic (grounded in the frozen check order, §6.1);
INV-2 structural, B side: the LOCALB reader rejects an A envelope at its own
     early schema check (§6.4 step 2) — B-side isolation is structural and is
     never realized through later signature failure;
INV-3 cryptographic domain separation: the LOCALB signature input binds the
     LOCALB envelope schema id, the LOCALB signature domain separator, and the
     canonicalized payload bytes (§6.3[8]); a LOCALB signature is therefore not
     transplantable into any other schema or domain interpretation;
INV-4 frozen-schema compatibility boundary: issuer fields [13]/[14] exist only
     in the B envelope layer; I0 Schema v1.6's 13 top-level members and consts
     are untouched, and no LOCALB mechanism modifies Contract v1.8 or the
     frozen anchor in PersistentSRSRepresentation.swift.
These four invariants are related but NOT interchangeable; design freeze
requires all four to hold simultaneously.
```

### 6.6 Rotation ceremony (unchanged)

Explicit operator action at the local console: generate next-generation key →
register (prior key RETIRED, retained) → sign new records with the new key.
Never silent, never network-triggered.

## 7. Trust registry — integrity, backup, recovery

### 7.1 Structure (unchanged)

Append-only hash-chained event log (authority) + derived checkpoint (cache,
rebuilt from log); every trust transition = exactly one event; atomic commit =
durable event append (write+fsync+publish) then checkpoint rebuild
(tmp+rename+dir fsync); crash between → log wins; no partial trust state.
Event types as in v0.2 (IDENTITY_INITIALIZED, KEY_ROTATED, KEY_STATUS_SET,
KEY_LOST_DECLARED, CLIENT_REGISTERED/REVOKED, PERMISSIONS_SET,
PAIRING_CREDENTIAL_ISSUED/CONSUMED/EXPIRED/REVOKED).

### 7.2 Rollback detection — exact guarantee and three branches (rewritten)

```text
GUARANTEE STATEMENT (normative): the hash chain proves INTERNAL CONSISTENCY of
the registry relative to a trusted head. By itself it NEVER proves the absence
of rollback: if registry, checkpoint, and chain are together restored to an
older consistent state, local data alone cannot detect it. Detection depends
on a trusted checkpoint that did NOT roll back with the data — the operator's
offline head record (§7.3).

Branches at load/restore:
B1 trusted external checkpoint AVAILABLE and MISMATCHES the local head
   → refuse to start trust services; enter the explicit recovery flow; an
     operator may accept an older head ONLY as an explicit re-initialization
     decision (logged);
B2 trusted external checkpoint MISSING or UNCONFIRMABLE
   → registry continuity is NOT verified — the system must not claim it is;
     fail-closed exactly as §7.5 (no new trust establishment; protected
     requests refuse) until the operator either supplies a checkpoint,
     restores a verified backup, or explicitly re-initializes;
B3 checkpoint AVAILABLE and MATCHES
   → normal operation; the chain's internal consistency holds relative to
     that head.
```

### 7.3 Backup and restore (updated to the branch semantics)

Export = full log + head (seq, head_hash); the head is displayed at every
export and SHOULD be recorded offline by the operator (paper note — this is
the trusted external checkpoint of §7.2). Restore = verify chain (§7.1) →
apply branch B1/B2/B3 → explicit operator confirmation before activation.
Restores never create new trust silently.

### 7.4 Permanent-loss semantics — two verification classes (rewritten)

```text
Class-1 cryptographic signature verification: checking that a historical
  signature is valid, possible WHENEVER the corresponding PUBLIC KEY bytes
  are available from any preserved source (e.g., an operator export of key
  material). It establishes signature validity ONLY.
Class-2 historical trust-state verification: establishing that the signing
  key belonged to the local trust domain at signing time — requires the
  registry event history or a trusted backup.
On permanent registry loss WITHOUT any backup: Class-2 becomes impossible;
  Class-1 remains POSSIBLE with preserved public keys — the design therefore
  does NOT claim cryptographic impossibility. However, the LOCALB reader's
  verdict ALWAYS requires a registry (fail-closed, §6.4), so absent a restore
  the records remain reader-unverified even where a Class-1 check could
  physically run.
Reverse rule (normative, unchanged): a Class-1-valid signature NEVER implies
  the key is currently trusted; records never restore registry authority
  (self-attestation forbidden).
Operational consequence: re-initialization = new lineage (new
  host_instance_id; generation restarts at 1); all clients re-pair; old
  records stay on disk, reader-unverified unless a backup is restored.
```

### 7.5 Corrupted / missing / unconfirmable registry (unchanged, now the single
fail-closed reference including branch B2)

New trust establishment REFUSED (no pairing, no rotation, no permission
changes) until restore or explicit re-initialization; per-request
authentication consults registry state, so protected requests fail closed;
only unprotected discovery may continue. Pending-verification records are
never a trust source.

## 8. Isolation boundary from Universe A (unchanged)

No local key into the frozen anchor or frozen documents; no LOCALB signature
presented as Contract v1.8 production signature; no A record enters the local
registry; no cross-domain trust inference in either direction; A-line
resumption stays a separate D2-style governance decision. §6.5 carries the
structural and cryptographic proofs.

## 9. Implementation boundary (unchanged)

New files under a separately authorized writable-path set; frozen module
unmodified; stage separation with separate authorizations; this design
authorizes nothing.

## 10. Non-goals (unchanged)

External CAs / internet dependencies; multi-host federations; client-side
signing; rich permission systems; frozen-object changes; PALACE / Information
Space mutation; performance benchmarking.

## 11. OQ disposition table (updated)

```text
OQ-1 registry storage/backup  → RESOLVED §7 (event log + checkpoint; export/
                                restore; §7.2 three rollback branches; §7.4
                                two verification classes);
OQ-2 credential parameters    → RESOLVED §3.1 (≥128-bit; FIXED_BASELINE
                                TTL = 5 min frozen in design; single use;
                                nonce-bound PoP; QR payload = binding tuple);
OQ-3 client key scope         → RESOLVED §4.1 (authn only; no signing rights);
OQ-4 envelope delta           → RESOLVED §6 + acceptance invariants §6.5
                                INV-1..INV-4;
OQ-5 permission granularity   → RESOLVED §4.2;
OQ-6 SE/P256 variant          → PARK (per rulings); Ed25519/Keychain baseline;
OQ-7 discovery                → trust rules RESOLVED §3.4 (lead-only);
                                protocol details implementation-time;
OQ-8 TLS lifecycle            → RESOLVED §5 (SPKI pin; lifecycle table).
```

## 12. Remaining questions (renumbered after TTL resolution)

```text
RQ-1  issuance-scope label form (free-form note vs structured descriptor);
RQ-2  checkpoint rebuild cadence (per-event vs periodic) — implementation
      package;
RQ-3  registry event canonicalization for hashing (proposal: the SRS
      JCS-style canonical ordering family) — frozen in the implementation
      package.
```
