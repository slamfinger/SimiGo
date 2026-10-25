# LOCAL-PRODUCTION-SIGNER-01 — Local Production Signing & LAN First-Pairing Conceptual Design v0.1

> **Status:** PENDING HUMAN REVIEW — design only; authorizes no implementation,
> no Build/Test, no fixture, no key generation, and no change to any frozen object
> **Date:** 2026-10-15
> **Commissioning:** `PERSISTENT-SRS-D1-CLOSURE-LPS01-COMMISSIONING-20261015-01` (D-H)
> **Deployment premise:** one SimiGo host used locally, serving a limited set of
> LAN inference clients; no external signing institution exists in this deployment
> (owner attestation 2026-10-15, D-G)
> **Frozen-line relationship:** Trust Universe A (Contract v1.8, I0 Schema v1.6,
> Manifest v2.2, hardcoded anchor) is untouched; R27 remains STOP; this design
> defines Trust Universe B only

---

## 0. Requirement traceability

| Human requirement (2026-10-15 directive) | Section |
|---|---|
| host is the local trust root; identity generated once at first init | §2 |
| private key in macOS Keychain; Ed25519 via existing `Curve25519.Signing` | §2.1–2.2 |
| `keyID` = stable fingerprint bound to identity and key generation | §2.3 |
| local trust registry; restart reads existing identity, never auto-generates | §2.4, §2.5 |
| persist + verify identity BEFORE LAN service enters normal operation; no degradation on init failure | §2.6 |
| first connection triggers pairing, not raw trust; one-time credential with validity + use limit; headless = local-console code; explicit NOT-TOFU rationale | §3 |
| post-pairing registration and automatic authentication | §4 |
| two independent identities: TLS connection identity ≠ SRS signing identity | §5 |
| records carry issuer identity + key generation; Reader verifies via local registry; rotation preserves historical keys; no later-appearing key auto-trusts | §6 |
| strict isolation from frozen Contract v1.8 anchor; new local config, not a replacement | §7 |
| reuse existing SRS encoding/signing infrastructure; no duplicate persistence layer | §6.3, §8 |

## 1. Trust model overview

```text
Trust Universe A (frozen, existing):
  frozen anchor (+fG2YJ+…VMI=) + Contract v1.8 semantics;
  status: R27 STOP / unchanged by this design;

Trust Universe B (local, this design):
  root of trust = the local trust registry on the SimiGo host,
  seeded at first initialization through an explicit, operator-present
  local action (NOT through any network event);
  the registry binds: host signing identities (keyID → pubkey, generation,
  status) and registered client identities (clientID → pubkey, permissions,
  status);
  security goal: identity continuity + verifiable provenance of persisted
  SRS records + automatic operation after one trusted pairing — with no
  external dependency.
```

First trust never enters through the network. It enters through the trusted
local channel (host console / management UI / printed code). This is the
explicit answer to the OWASP TOFU objection: the design is pairing-based,
where the out-of-band channel carries the fingerprints that the network
exchange is later checked against.

## 2. Host signing identity (Area 1)

### 2.1 Generation

- One long-term Ed25519 keypair, generated at first initialization or by an
  explicit re-initialization action; never per-connection, never per-client.
- Algorithm and code path: `Curve25519.Signing.PrivateKey` — the same
  primitive family already used by the accepted Decision Core and
  `PersistentSRSRepresentation` (reuse, no new dependency).
- Generation happens only when the registry reports no identity OR an
  explicit rotation ceremony is performed (§6.4).

### 2.2 Private-key storage

- macOS Keychain, stored as a generic-password item holding the raw 32-byte
  private key representation, access limited to the host service context.
- Honest platform boundary (registered, per Apple documentation): Secure
  Enclave key storage applies to P256 keys, not Curve25519 keys. An Ed25519
  key therefore cannot be claimed Secure-Enclave-resident. The baseline is
  Keychain protection; an alternative P256/Secure-Enclave variant is
  registered as open question OQ-6 (it would depart from the existing
  Ed25519 record-signing infrastructure).

### 2.3 keyID and generations

```text
keyID = lowercase hex SHA-256 of the raw 32-byte public key;
display form = first 8 hex bytes ("ab12cd34…") for humans;
record form = full 64 hex chars;
generation = monotonically increasing integer assigned at initialization /
  rotation time by the registry;
identity tuple = (keyID, generation).
```

### 2.4 Local trust registry

- A local, host-owned registry records: current host signing identity
  (keyID, pubkey, generation, status ACTIVE/RETIRED, created_at, provenance
  = "initialized-at" or "rotated-from:<prior keyID>") and registered client
  identities (§4).
- Registry semantics: append-only for identity history; status flips are
  explicit records, never deletions; losing the registry loses verification
  capability for all Universe-B records (fail-closed, §6.5) — therefore the
  registry write path must be durable (flush-then-publish, the same
  durability discipline already proven on this repository's baseline-store
  pattern) and an operator backup guideline is part of the design.

### 2.5 Restart behavior

- On start: read the existing identity from Keychain + registry; verify the
  Keychain public key matches the registry's ACTIVE entry (byte comparison).
- Never auto-generate a replacement key. If the identity exists but cannot
  be read or does not match the registry, the host enters
  `IDENTITY_DEGRADED`: signing disabled, protected APIs disabled, explicit
  operator error surfaced. No ephemeral key, no test key, no unsigned
  service, ever.

### 2.6 Service state machine (bootstrap ordering)

```text
SETUP → [generate or load identity] → [persist + read-back verify] →
OPERATIONAL (LAN service enters normal work only here)
any failure at any step → stay in SETUP; no signing; no protected APIs;
no fallback path of any kind (fail-closed by design).
```

## 3. One-time pairing protocol (Area 2)

Client lifecycle: `UNPAIRED → PAIRING → REGISTERED → (REVOKED)`.

1. **Discovery.** An unpaired client may discover the service and request
   pairing only. It can read no protected information and call no
   authenticated API.
2. **One-time pairing credential.** The host generates a one-time credential
   (sufficient entropy; short validity window; single-use counter;
   revocable) and displays it ONLY through the trusted local channel:
   - desktop deployment: management UI / QR code;
   - headless deployment: local console one-time code.
   The QR / credential payload carries the host's TWO fingerprints: the
   host TLS certificate fingerprint AND the host signing `keyID` (display
   form). The credential is not a long-lived LAN password.
3. **First verification and approval.** The client connects over TLS and
   presents the one-time credential plus its own client identity public key
   and a proof-of-possession signature (challenge from the host). The
   client independently checks the host TLS fingerprint and signing keyID
   against what the QR/console displayed. Approval is confirmed by the user
   on the trusted local interface (or, for headless, by the act of issuing
   the code to that specific client). The network alone never decides
   trusted identity.
4. **Registration.** On approval the host writes a registration record
   (clientID, client pubkey, permissions, registered_at, status ACTIVE);
   the client stores its server binding (host TLS fingerprint + host
   signing keyID).

## 4. Client registration & automatic authentication (Area 3)

- Subsequent connections authenticate automatically: client proves possession
  of its registered key; host proves TLS identity matching the stored
  fingerprint; no repeated manual pairing.
- Revocation = registry status flip (explicit operator action); revoked
  clients lose access; host-signed records are unaffected.
- Registration records are host-side facts about clients; they never confer
  signing authority (only the host signs; §5).

## 5. Two independent identities (Area, restated as a hard rule)

```text
TLS connection identity: protects LAN transport (host TLS certificate);
SRS signing identity:    attests who signed persisted information (keyID);
separate keys, separate purposes, no key reuse across roles;
TLS handshake success is NEVER evidence of SRS signing trust;
pairing success is NEVER evidence of Universe-A production compliance.
```

## 6. SRS signing, verification, and rotation under Universe B (Area 4)

### 6.1 Record envelope

Universe-B records carry the issuer identity tuple (`keyID`, `generation`)
alongside the signature. The physical framing reuses the existing SRS
encoding infrastructure (canonical payload, envelope, digests) with the
signer field carrying the LOCAL key's public key and the added issuer-tuple
fields; the exact envelope delta is an implementation-time decision under
the future implementation authorization (OQ-4).

### 6.2 Verification rule

```text
verify(record):
  1. look up record.keyID in the local trust registry;
  2. keyID unknown → REJECT (no auto-trust of later-appearing keys,
     including keys that merely appear on the network or on disk);
  3. keyID known → verify Ed25519 signature with the registered pubkey;
  4. retired keys verify their historical records (registry history is
     append-only); a retired key never signs new records;
fail-closed everywhere; no third state between "registry lineage" and
"reject".
```

### 6.3 Infrastructure reuse (no duplicate persistence substrate)

- Signing/verification: existing `SRSVALIssuer` / `SRSSignature` /
  `Curve25519.Signing` code paths and canonical encoding.
- Records: the existing Persistent SRS framing family — the design
  explicitly does NOT introduce a second persistence store, database, or
  carrier; Universe B changes WHO is trusted (registry vs frozen constant),
  not HOW records are encoded or stored.
- The frozen module `PersistentSRSRepresentation.swift` is NOT modified;
  Universe-B implementation lands in new files under a separately authorized
  writable-path set (§8).

### 6.4 Rotation ceremony

- Explicit operator action from the local console: generate next generation
  key → register it (prior key RETIRED, retained) → sign new records with
  the new key. Historical records remain verifiable under retained keys.
  Rotation is never silent and never triggered by a network event.

### 6.5 Registry loss / recovery semantics

- Registry absent or corrupt → all Universe-B verification fails closed
  (records present but unverifiable); recovery = restore registry from
  operator backup and re-verify; there is NO path that re-establishes trust
  from the records themselves (that would be self-attestation).

## 7. Isolation boundary from Trust Universe A (Area 5)

| | Universe A (frozen) | Universe B (local) |
|---|---|---|
| root of trust | hardcoded frozen anchor public key | local trust registry (host) |
| verification | against the frozen constant | against registered local keys |
| status | R27 STOP; unchanged | this design; separately authorized lifecycle |
| records | pre-existing frozen-line objects | new locally signed records |

```text
hard prohibitions (implementation-time and design-time):
  no writing any local public key into the frozen anchor constant or any
    frozen document;
  no universe-B signature presented as Contract v1.8 production signature;
  no universe-A record admitted into the local registry;
  no shared trust inference between the two universes in either direction;
  Universe A resumption (if ever) remains a separate D2-style governance
  decision and is NOT implied by this design.
```

## 8. Implementation boundary (future, separate authorization)

- New files (e.g., local signer identity, registry, pairing service,
  universe-B reader) — NOT the two frozen repair paths of the v2.1 package;
  the future implementation record must define its own
  `authorized_writable_path_set`, build/test plan, and completion evidence,
  following Manifest v2.2-style stage separation (design → implementation →
  validation), each separately authorized.
- This design authorizes nothing; it freezes intent for review.

## 9. Non-goals

External CAs or internet dependencies; multi-host federations; client-side
signing; permission systems beyond a simple operator-managed set; any change
to frozen contracts, PALACE, Information Space, MLX/V6, or the GUI evidence
chain; performance benchmarking.

## 10. Open questions for review

```text
OQ-1  registry storage location and exact durable-write pattern (reuse the
      DCC-1 baseline-store pattern vs simpler append-only file) + backup
      guideline strength (recommend-only vs enforced export reminder);
OQ-2  one-time credential format, entropy, validity window, and use-count
      defaults; QR payload encoding;
OQ-3  client identity key scope (connection auth only vs also encrypting
      client-side state); proof-of-possession challenge details;
OQ-4  exact envelope delta for issuer tuple fields (new fields vs reuse of
      existing signer field + sidecar registry lookup at signing time);
OQ-5  permissions model granularity (single trusted class vs per-client
      capability set) for the first implementation;
OQ-6  Keychain-stored Ed25519 seed (baseline) vs P256/Secure-Enclave
      variant (stronger hardware binding, departs from existing record
      signing infrastructure) — recommendation: Ed25519/Keychain baseline;
OQ-7  service discovery mechanism (e.g., Bonjour) and whether discovery
      announcements may carry the keyID display form (fingerprint yes,
      trust never);
OQ-8  LAN transport assumption: TLS server certificate lifecycle on the
      host (self-signed generated at first init, fingerprint carried in the
      pairing channel).
```
