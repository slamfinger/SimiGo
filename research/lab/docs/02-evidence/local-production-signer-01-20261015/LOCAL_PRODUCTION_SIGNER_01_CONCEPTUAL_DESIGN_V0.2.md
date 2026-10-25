# LOCAL-PRODUCTION-SIGNER-01 — Local Trust Domain B Signing & LAN First-Pairing Conceptual Design v0.2

> **Status:** PENDING HUMAN REVIEW (second review round) — design only; authorizes
> no implementation, no Build/Test, no fixture, no key generation, no frozen-object
> change
> **Date:** 2026-10-15
> **Supersedes:** v0.1 (same directory), per ruling
> `LOCAL-PRODUCTION-SIGNER-01-DESIGN-V0.1-REVISE-20261015-01`
> **Grounding note (per MR-1):** the record-format decision in §6 is grounded in
> the actual frozen encoding constants (`PersistentSRSRepresentation.swift`
> `SRSEncodingConstants`, blob `f5ea0130…`) and the actual I0 Schema v1.6 file
> (`PERSISTENT_SRS_RECORD_JSON_SCHEMA_V1.6.json`, 13 required top-level members,
> consts on `payload_schema_id` / `encoding_identity` / `decision_core_binding`),
> both read in full for this revision.
> **Naming rule (per ruling §3):** all Domain-B identities carry the `LOCALB`
> marker; no artifact of this design may be labeled bare "production".

---

## 0. Change log v0.1 → v0.2 and traceability

| Ruling item | Closed in |
|---|---|
| MR-1 record issuer + format boundary (OQ-4) | §6 (option (a) chosen, grounded; alternative (b) rejected with reasons) |
| MR-2 pairing state machine (OQ-2/OQ-7) | §3 (state machines, credential binding tuple, replay protection, threat boundary) |
| MR-3 registry integrity/backup/recovery (OQ-1) | §7 |
| MR-4 key usage + permissions (OQ-3/OQ-5) | §4 |
| MR-5 identity lifecycles (OQ-8) | §5 |
| OQ-6 disposition | §11 (PARK per ruling; Ed25519 baseline) |
| Naming constraint | §1.3 |
| keyID precision | §2.3 |

## 1. Trust model and naming

### 1.1 Two trust universes (unchanged)

Universe A: frozen anchor `+fG2YJ+…VMI=` + Contract v1.8 semantics; R27 STOP;
untouched by this design. Universe B: local trust registry on the SimiGo host;
root of trust seeded only by an explicit, operator-present local action.

### 1.2 First-trust principle (unchanged, now mechanized in §3)

Trust never enters through the network. It enters through the trusted local
channel; the network exchange is then CHECKED against what that channel
carried. This is pairing, not raw TOFU.

### 1.3 Naming

```text
work item name        = LOCAL-PRODUCTION-SIGNER-01 (registered, unchanged);
domain-B identity IDs = …LOCALB… (e.g., envelope schema id, signature domain,
                        registry lineage, UI labels);
UI labels             = "Local Trust Domain B signing identity";
forbidden             = any bare "production" label on a Domain-B artifact,
                        and any wording that could be read as Contract v1.8
                        production-signature identity.
```

## 2. Host signing identity (LOCALB signer)

### 2.1–2.2 Generation and storage (unchanged from v0.1)

One long-term Ed25519 keypair via `Curve25519.Signing` (existing dependency),
generated only at first initialization or explicit rotation; private key in a
macOS Keychain generic-password item (raw 32 bytes), host-service access
scope. Honest platform boundary: Secure Enclave key residency applies to
P256, not Curve25519 (OQ-6 = PARK; see §11).

### 2.3 keyID — precise definition (MR-2)

```text
keyID = lowercase-hex( SHA-256( raw 32-byte Ed25519 public key ) );  // 64 hex
display form  = first 8 hex bytes;
registry form = full 64 hex chars;
generation    = u32, monotonically increasing per registry lineage;
identity tuple = (keyID, generation).
```

Two rules make keyID safe:
(a) it IS a deterministic cryptographic fingerprint of the exact public key
(one-to-one with the key bytes); and
(b) it NEVER substitutes for public-key verification: verification always
fetches the full registered public key BY keyID and performs Ed25519
verification with those full bytes. Unknown keyID → reject. keyID is a lookup
handle and display aid, nothing more.

### 2.4–2.6 Registry pointer, restart, service state machine (unchanged from v0.1)

`SETUP → [load or generate identity] → [persist + read-back verify] →
OPERATIONAL`; any failure stays in SETUP, no fallback (no ephemeral key, no
test key, no unsigned service, no degraded-mode signing). Restart reads the
existing identity; mismatch between Keychain key and registry ACTIVE entry →
`IDENTITY_DEGRADED`: signing and protected APIs disabled, explicit operator
error; never auto-regeneration.

## 3. Pairing protocol — verifiable state machines (MR-2)

### 3.1 Pairing credential binding tuple

Every issued credential atomically binds, and is displayed (QR / console code)
together with:

```text
{ host_instance_id   // registry lineage UUID, stable across restarts,
                     // changes only on registry re-initialization (§7.4)
  tls_spki_sha256    // SHA-256 of the host TLS cert's DER SubjectPublicKeyInfo
  srs_key_id         // full 64-hex LOCALB signing keyID
  protocol_version   // "LPS01-P1"
  session_nonce }    // one-time 128-bit random session identifier
plus the credential secret itself (≥128-bit random, never derived from any
of the above).
```

Defaults: validity window ≤ 5 minutes; single consumption; revocable at any
time by the operator. Not a long-lived LAN password.

### 3.2 Host-side state machine (per pairing attempt)

```text
IDLE
 → CREDENTIAL_ISSUED      credential persisted as an Issued event (§7.1);
                           operator authorization scope recorded (who the
                           operator intends to pair; free-form label)
 → PRESENTED               client presented {credential, client pubkey,
                           PoP signature} over TLS; host verified:
                           credential unexpired AND unconsumed;
                           PoP covers {session_nonce, credential_id,
                           client_pubkey} and verifies;
                           the ACTUAL connection's TLS SPKI equals the
                           bound tls_spki_sha256
 → OPERATOR_CONFIRM_PENDING  default mode: explicit confirmation on the
                           trusted local interface. Alternative (headless):
                           the issuance-time operator authorization scope
                           IS the confirmation — but only because the
                           operator created it at the local console; LAN
                           reachability or QR visibility alone NEVER
                           confirms anything
 → REGISTERED              one atomic registry commit containing
                           PAIRING_CREDENTIAL_CONSUMED + CLIENT_REGISTERED
                           (single transaction; a second presentation of the
                           same credential therefore fails at PRESENTED)
 → terminal states: REGISTERED | ABORTED(expired | consumed | revoked |
                           tls_mismatch | pop_invalid | declined)
every transition is a logged, time-stamped event; aborts are terminal for
that credential.
```

### 3.3 Client-side state machine

```text
DISCOVERED → CONNECTED
  (TLS established; client compares the ACTUAL TLS SPKI hash and the
   host-presented keyID against the QR/console values; any mismatch → ABORT)
 → PAIRING_SUBMITTED (credential + client pubkey + PoP)
 → PAIRED   client stores its binding: {host_instance_id, tls_spki_sha256,
            srs_key_id, granted permissions}
 → ABORTED on any failure; no partial binding is stored.
```

### 3.4 Discovery rule (OQ-7)

Discovery (any mechanism) provides LEADS only: name, address, optionally a
display fingerprint for human convenience. It never establishes trust, never
carries anything that substitutes for the QR/console channel, and no client
may auto-trust from reachability. Protocol details (e.g., Bonjour fields) are
implementation-time; the lead-only rule is a design invariant.

### 3.5 Threat boundary (explicit)

```text
RESISTS (under stated assumptions):
  passive LAN observation                 — TLS;
  pairing-time MITM with a fake host      — client compares actual TLS SPKI
        and keyID against the QR; attacker cert/key → mismatch → abort
        (assumes the QR/console channel is genuine: assumption A1);
  credential replay                       — single-use consumption event +
        TTL + session nonce in the PoP;
  later-appearing rogue keys              — registry-or-reject, no third
        state;
  silent trust changes                    — every trust transition is a
        registry event with an operator actor record.

DOES NOT PROMISE (out of scope, stated):
  full host compromise                    — an attacker with host privileges
        (Keychain extraction, malicious host software) owns Universe B by
        definition; mitigation is OS-level, not this design;
  operator forwards the QR/credential     — the out-of-band channel
        requires operator diligence; forwarding risk is inherent to any
        human-carried credential;
  full relay of the pairing exchange      — an attacker holding QR content
        can complete pairing AS ITSELF (it becomes a registered attacker);
        the countermeasure is the operator's issuance-scope label and
        confirmation discipline, not cryptography;
  compromised client devices after        — revocation path exists (§4.3);
        pairing
  guessing attacks                        — ≥128-bit secrets.

FIRST-TRUST CONDITIONS: A1 genuine local console/UI; A2 operator present and
attentive at issuance/confirmation; A3 the client UI faithfully shows what it
verified (client-side compromise out of scope).
```

## 4. Permissions and key-usage boundaries (MR-4)

### 4.1 Key usage separation

```text
client identity key (per client, Ed25519): connection authentication and
  proof-of-possession ONLY; it NEVER carries SRS signing rights — no
  permission value, present or future, grants it in this design version;
LOCALB signing key (host, Ed25519): signs SRS records ONLY; it never leaves
  the host Keychain and is never transferred, wrapped, delegated, or proxied
  to any client as a consequence of registration;
host TLS key: transport ONLY.
No key ever serves two of these roles.
```

### 4.2 Permission classes (minimum working set; names refinable, model not empty)

```text
P-INFERENCE       call inference APIs;
P-INFO-READ       read service status / non-protected information;
P-SRS-WRITE       submit records into persistence — HOST-EXCLUSIVE and
                  structurally non-grantable to clients in v1 (see §4.1);
P-ADMIN-PAIRING   issue/revoke pairing credentials and client registrations;
P-ADMIN-TRUST     key rotation, registry operations, permission changes.
Baseline: default-deny; least privilege; admin plane endpoints separated
from the inference plane; admin operations additionally require the local
console where feasible.
Default grant at pairing = {P-INFERENCE, P-INFO-READ}; any admin class only
by explicit operator action recorded in the registry.
```

### 4.3 Revocation timing

Every protected request authenticates against CURRENT registry state (no
long-lived authority cache; if an implementation later adds a bounded cache,
its TTL is a reviewed parameter, default none). Revocation therefore takes
effect at the client's next protected request; an in-flight request may
complete (bounded by that request's lifetime).

## 5. Identity lifecycles (MR-5)

### 5.1 Stable TLS pin: SPKI, not certificate

Clients pin `tls_spki_sha256` (SHA-256 of the cert's SubjectPublicKeyInfo).
Routine certificate renewal with an UNCHANGED key pair keeps the pin valid —
re-pairing is not forced by expiry or re-issuance.

### 5.2 Lifecycle table

```text
TLS cert renewal (same key pair):
  pairings intact (SPKI unchanged); clients refresh the cert; no trust event;
TLS private key replacement:
  SPKI changes → all existing pairings fail pin check → explicit operator
  re-pairing campaign; a signed pre-published TLS-rotation notice (signed by
  the LOCALB signing key) is an OPTIONAL future mechanism requiring its own
  review — NOT part of v0.2;
LOCALB signing key rotation:
  §6.5 ceremony; registry retains prior keys; historical verification
  preserved; new records carry the new keyID/generation;
LOCALB signing key LOSS (private key unrecoverable):
  registry records KEY_LOST while RETAINING the public key → historical
  records REMAIN verifiable (verification needs only the registered public
  key); NEW signing is blocked until rotation; this is the precise sense in
  which "signature verifiable" and "key currently able to sign" differ;
registry loss / re-initialization: §7.4.
Invariants: no network event ever triggers any trust-root change; TLS
certificate validity (expiry hygiene) is NEVER evidence of SRS signing trust.
```

## 6. LOCALB record format — issuer and boundary (MR-1, primary)

### 6.1 Grounding facts (read from the frozen sources, not assumed)

A-domain envelope value checks in `SRSReader.read` run in this order:
field `[0] envelope_schema_id` (else `unknownEnvelopeSchema`), `[1]` storage
format, `[5]` encoding identity, `[12]` completion state — all BEFORE payload
parsing (R15+) and signature verification (R25). Frozen constants:
`envelopeSchemaID = "SIMIGO_PERSISTENT_SRS_ENVELOPE_V1"`,
`signatureDomain = "SIMIGO_PERSISTENT_SRS_RECORD_SIGNATURE_V1"`, signer =
frozen anchor bytes. I0 Schema v1.6 has 13 required top-level members with
consts on `payload_schema_id`, `encoding_identity`,
`decision_core_binding`.

### 6.2 Decision: option (a) — independent LOCALB envelope configuration

```text
chosen   : a Domain-B-specific envelope with its own schema id, issuer
           fields, signature domain, and storage version;
rejected : option (b) wrapper layer — it would embed an A-shaped envelope
           signed by a non-A key, producing records that LOOK like A-format
           but fail A's R25; that ambiguity, plus double framing, is exactly
           what isolation forbids.
```

### 6.3 LOCALB envelope fields (v1, frozen at design freeze)

```text
frame: physical framing discipline REUSED unchanged (magic SIMISRSV1001 /
SIMISRSV1END, physical version 1, lengths, digests) — the frame is
trust-neutral;
[0]  envelope_schema_id      = "SIMIGO_PERSISTENT_SRS_LOCALB_ENVELOPE_V1"
[1]  storage_format_version  = "PERSISTENT_SRS_LOCALB_STORAGE_V1"
[2]  logical_key_identity    (same semantics as A)
[3]  logical_key_version     (same semantics as A)
[4]  payload_digest_hex
[5]  encoding_identity       = "PERSISTENT_SRS_CANONICAL_V1"   // SHARED:
                              same canonicalizer, deliberately not trust-
                              bearing
[6]  signature_domain        = "SIMIGO_PERSISTENT_SRS_LOCALB_RECORD_SIGNATURE_V1"
[7]  signer_public_key_raw   = LOCALB signer's raw 32-byte public key
[8]  signature_raw           = Ed25519 over (LOCALB domain || canonical payload)
[9]  producer_authorization_reference = LOCALB operator authorization ref
[10] decision_core_source_commit    = same accepted Decision Core values as A
[11] decision_core_source_sha256      (semantic binding; consistent with the
                                       payload schema's const)
[12] completion_state        = "COMPLETE"
[13] issuer_key_id           = 64-hex keyID of [7]
[14] issuer_generation       = u32
payload: I0 JSON Schema v1.6 VERBATIM, reused unmodified as the content
schema (all its consts stand); this design does not touch the schema.
```

### 6.4 Verification rule (LOCALB reader)

```text
1. frame + digest + canonical-byte checks — same discipline as A (truncation,
   framing, digest recomputation, canonical equality);
2. envelope_schema_id == LOCALB const  (A records fail here);
3. signature_domain == LOCALB const; encoding_identity == shared const;
4. issuer_key_id lookup in the LOCAL registry → unknown → REJECT;
5. signer_public_key_raw bytes == registered public key bytes (both must
   match; keyID never substitutes — §2.3);
6. Ed25519 verify over (LOCALB domain || canonical payload);
7. any registered key (ACTIVE or RETIRED) may verify — historical records
   stay verifiable after rotation; only ACTIVE keys may sign (enforced at
   signing time by the host);
fail-closed at every step; statuses are typed; no third state.
```

### 6.5 Isolation proof (bidirectional, structural)

```text
A reader on a LOCALB record: envelope_schema_id mismatch → typed rejection
at the FIRST envelope check, before payload and before any signature logic;
LOCALB reader on an A record: same first-check rejection;
neither universe's verification path can be satisfied by the other's
records; therefore a LOCALB record can never "pass" Contract v1.8
verification, and no A record can acquire LOCALB trust by being read.
Hard rules: Contract v1.8 is not modified to admit local keys; the frozen
anchor constant in PersistentSRSRepresentation.swift stays byte-identical;
B records are never submitted to A-domain paths as evidence of anything.
```

### 6.6 Rotation ceremony (unchanged, restated)

Explicit operator action at the local console: generate next generation key →
register (prior key RETIRED, retained) → sign new records with the new key.
Never silent, never network-triggered.

## 7. Trust registry — integrity, backup, recovery (MR-3)

### 7.1 Structure: append-only hash-chained event log + derived checkpoint

```text
event = { seq(u64), prev_event_hash, event_hash = SHA256(canonical event
         bytes), event_type, actor(operator action id), created_at_utc,
         payload };
event types: IDENTITY_INITIALIZED, KEY_ROTATED, KEY_STATUS_SET(retire/
         revoke, with reason), KEY_LOST_DECLARED, CLIENT_REGISTERED,
         CLIENT_REVOKED, PERMISSIONS_SET, PAIRING_CREDENTIAL_ISSUED /
         CONSUMED / EXPIRED / REVOKED;
the LOG is the authority; a checkpointed current-state file is a cache
rebuilt from the log; every trust transition = exactly one event (atomic
commit = durable event append [write+fsync+publish] followed by checkpoint
rebuild [tmp+rename+dir fsync]; a crash between leaves the log authoritative
— no partial trust state exists).
```

### 7.2 Tamper / truncation / rollback resistance

On every load the full chain is recomputed (hash + seq + type validity);
mismatch → registry UNCONFIRMED (§7.5). Honest boundary: against an attacker
with host privileges who consistently rewrites ALL local state, local
verification cannot resist — that condition is out of scope (§3.5). The
design adds one external anchor: the registry HEAD (seq + head hash) is
displayed at every export and SHOULD be recorded offline by the operator
(paper note); rollback to an older-but-internally-valid chain is detected at
restore by comparing against that offline record.

### 7.3 Backup and restore

Export = full log copy + head (seq, head_hash). Restore = (1) verify the
chain; (2) compare the restored head against the operator's offline record —
an older head is refused unless the operator explicitly accepts a
re-initialization decision; (3) explicit operator confirmation before the
restored registry becomes active. Restores never create new trust silently.

### 7.4 Permanent loss semantics

```text
registry permanently lost →
  fresh re-initialization: new registry lineage (new host_instance_id,
  generation restarts at 1 in the new lineage); all clients re-pair;
  historical LOCALB records: remain on disk but are UNVERIFIED forever
  unless an exported registry (or its key entries) is restored — records
  NEVER restore trust themselves (self-attestation is forbidden);
  distinction enforced: "signature was verifiable" (needed the registered
  public key, now lost) vs "key is currently trusted" (registry state, lost)
  — both fail closed; verification capability returns only via restore.
```

### 7.5 Corrupted / missing / unconfirmable registry

New trust establishment is REFUSED (no new pairing, no rotation, no
permission changes) until the registry is restored or explicitly
re-initialized. Because per-request authentication consults registry state
(§4.3), protected requests fail closed; the service may keep serving only
unprotected discovery. Pending-verification records are never a trust
source.

## 8. Isolation boundary from Universe A (restated with the record-level proof)

The v0.1 prohibitions carry forward unchanged (no local key into the frozen
anchor or frozen documents; no LOCALB signature presented as Contract v1.8
production signature; no A record enters the local registry; no cross-domain
trust inference in either direction; A-line resumption stays a separate
D2-style governance decision). §6.5 adds the structural proof that the
isolation is now enforced by the record format itself.

## 9. Implementation boundary (unchanged)

New files under a separately authorized writable-path set (identity,
registry, pairing service, LOCALB reader/writer); the frozen module is not
modified; stage separation (design → implementation → validation) with
separate authorizations per stage; this design authorizes nothing.

## 10. Non-goals (unchanged)

External CAs / internet dependencies; multi-host federations; client-side
signing; rich permission systems; frozen-object changes; PALACE /
Information Space mutation; performance benchmarking.

## 11. OQ disposition table

```text
OQ-1 registry storage/backup  → RESOLVED §7 (event log + checkpoint; export/
                                restore with anti-rollback; loss semantics);
OQ-2 credential parameters    → RESOLVED §3.1–3.3 (≥128-bit; ≤5 min; single
                                use; nonce-bound PoP; QR payload = binding
                                tuple; consumption atomic);
OQ-3 client key scope         → RESOLVED §4.1 (authn only; no signing rights
                                in any form);
OQ-4 envelope delta           → RESOLVED §6 (option (a); grounded §6.1);
OQ-5 permission granularity   → RESOLVED §4.2 (five-class minimum set,
                                default-deny baseline; names refinable);
OQ-6 SE/P256 variant          → PARK per ruling; Ed25519/Keychain baseline;
OQ-7 discovery                → trust rules RESOLVED §3.4 (lead-only);
                                protocol details deferred to implementation;
OQ-8 TLS lifecycle            → RESOLVED §5 (SPKI pin; renewal/replacement/
                                rotation/loss table).
```

## 12. Remaining questions for this review round (bounded, none blocking design shape)

```text
RQ-1  default credential TTL (5 min proposed) and any auto-expire sweep
      cadence — operator preference;
RQ-2  whether the headless issuance-scope label (§3.2) should be a mandatory
      free-form operator note or a structured client descriptor;
RQ-3  checkpoint rebuild cadence (per-event vs periodic) — implementation
      detail, flagged for the implementation package;
RQ-4  exact canonicalization used for registry event hashing (proposal: the
      same JCS-style canonical ordering family as SRS payloads) — to be
      frozen in the implementation package.
```
