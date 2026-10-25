# Persistent SRS Representation Manifest Contract v1.1

> **Status:** SUBMITTED FOR HUMAN DESIGN REVIEW — DESIGN ONLY / NO STAGE AUTHORIZED
> **Date:** 2026-10-11
> **Supersedes:** Manifest Contract v1.0 (`REVISE / SUPERSEDED / NEVER FROZEN`)
> **Authorization request:** `SIMIGO_PERSISTENT_SRS_REPRESENTATION_AUTHORIZATION_REQUEST_V0.1_20261011.md`
> **Authorization request SHA256:** `4063787b0680da2ccd872ec949c4602295c8bd5d9d6620f7149ff6caa288c791`
> **Human ruling on v1.0:** `REVISE_PERSISTENT_SRS_MANIFEST_CONTRACT_V1.0`
> **Canonical PALACE mutation:** FORBIDDEN
> **Canonical Information Space mutation:** FORBIDDEN
> **MLX execution:** FORBIDDEN
> **V6 rerun:** FORBIDDEN
> **Independent ES₂ consumption:** NOT AUTHORIZED BY THIS CONTRACT
> **Non-recompute attribution:** NOT AUTHORIZED BY THIS CONTRACT

## 1. Scope and authority

This contract defines the exact physical record layout, canonical integrity
layers, logical-key conflict model, envelope cross-validation rules, fail-closed
persistence semantics, and future manifest obligations for a minimal Persistent
SRS Representation.

This document does not implement persistence, authorize code changes, authorize
fixture preparation, authorize execution, create evidence, authorize markers or
an evidence root, authorize independent ES₂ consumption, authorize non-recompute
attribution, or amend any frozen SRS-VAL governance object.

```text
persistent implementation = NOT AUTHORIZED;
persistent fixture preparation = NOT AUTHORIZED;
persistent execution = NOT AUTHORIZED;
marker creation = FORBIDDEN;
evidence-root creation = FORBIDDEN;
canonical PALACE mutation = FORBIDDEN;
canonical Information Space mutation = FORBIDDEN.
```

Acceptance freezes this design only. Every later stage still requires a separate,
scope-bound Human Authorization Record.

## 2. Frozen provenance and compatibility

```text
request_base_commit =
  e6d5f955e7b6ed40b271e5769ccec5160d17fd77;

accepted_decision_core_source_commit =
  1d47f3be56dfa8c6bf7619f4566b271ed74aad27;

accepted_decision_core_source_path =
  simigo2-experimental/Sources/SimiGo2Experimental/SRSVALDecisionCore.swift;

accepted_decision_core_source_sha256 =
  7fec2ed4d6e6f82fe677a7f098ec98d3e99bf4138420f1dd051570c75cf1c72e;

accepted_decision_core_status =
  ACCEPT / INDEPENDENT SOURCE REVIEW CLOSED / NOT PRODUCTION PROOF;

SRS-VAL Design v0.8 commit = 1170208;

Authorization Package v0.6 commit = 047b221;
Authorization Package v0.6 acceptance commit = 6089f0b;

SRS-VAL Manifest Contract v1.0 status =
  ACCEPT / FROZEN / INCOMPATIBLE_FOR_PERSISTENCE_TARGET /
  RETAINED_AS_FROZEN_PROVENANCE;

Persistence Manifest Contract v1.0 status =
  REVISE / SUPERSEDED BY V1.1 / NEVER ACCEPTED OR FROZEN.
```

## 3. Contract identity

```text
contract_identity =
  SIMIGO_PERSISTENT_SRS_REPRESENTATION_MANIFEST_CONTRACT_V1.1;

contract_status_at_issue =
  SUBMITTED_FOR_HUMAN_DESIGN_REVIEW;

contract_integrity_binding =
  immutable Git commit/content binding assigned by Human acceptance;

self_declared_contract_digest = FORBIDDEN.
```

A future manifest instance must bind this exact identity and the Human-assigned
integrity binding. Conditional Manifest Instance v0.1 remains non-executable
until rebound and separately stage-authorized.

## 4. Exact seven-layer model

There are exactly seven named layers:

```text
I0  semantic record values
I1  canonical payload bytes
I2  payload digest
I3  record signature
I4  canonical envelope bytes
I5  envelope digest
P0  physical frame and evidence placement
```

`I0` through `I5` are integrity-construction layers. `P0` is the physical
serialization and placement layer; it is not a semantic integrity input to
`I0`–`I5`.

Dependency graph:

```text
I0 -> I1 -> I2 -> I3 -> I4 -> I5
                    ^ signer material is external authority input
P0 frames I1, I4, I2, and I5 but is not input to their construction
```

No layer may depend on a later integrity layer. In particular, the payload
digest never signs or hashes itself, the signature never includes the envelope
digest, and the envelope digest never includes itself.

## 5. I0 — closed semantic record values

I0 is the only semantic authority. Its field set is closed.

```text
payload_schema_id =
  SIMIGO_PERSISTENT_SRS_RECORD_V1;

logical_record_key:
  identity;
  version;

settled_relation_state;
source_relation;
dependency_set;
result;
provenance;
lifecycle;
freshness;
resolution_policy;

producer_authorization_reference;

decision_core_binding:
  source_commit =
    1d47f3be56dfa8c6bf7619f4566b271ed74aad27;
  source_sha256 =
    7fec2ed4d6e6f82fe677a7f098ec98d3e99bf4138420f1dd051570c75cf1c72e;

encoding_identity =
  SRSVAL-CANONICAL-TEXT-V4;
```

I0 does **not** contain `payload_digest`, signature, envelope digest, storage
location, completion state, process metadata, timestamp, observer evidence, or
request/observation invocation objects. Those later values cannot become
semantic identity.

Canonical payload rules inherit the accepted Decision Core discipline:

```text
ordered semantic records use fixed labels and fixed order;
unordered collections use deterministic, duplicate-preserving encodings;
NIL and explicit empty collection remain distinct;
reordering an unordered collection preserves canonical equivalence;
changing duplicate count changes canonical bytes;
missing, extra, unknown, or non-canonical fields fail closed.
```

## 6. I1 — canonical payload bytes

```text
canonical_payload_data =
  deterministic SRSVAL-CANONICAL-TEXT-V4 encoding of I0;
```

`I1` is the exact byte string hashed and signed. It is embedded directly in the
physical record; it is not stored in a sidecar or selected by a pointer.

## 7. I2 — payload digest and content identity

```text
payload_digest_raw =
  SHA256(
    ASCII("SIMIGO_PERSISTENT_SRS_PAYLOAD_DIGEST_V1") +
    0x00 +
    canonical_payload_data
  );

payload_digest_hex =
  64 lowercase hexadecimal characters of payload_digest_raw;
```

Two identities are distinct:

```text
logical_record_key =
  identity + version;

record_content_identity =
  identity + version + payload_digest_hex;
```

`logical_record_key` names the intended stable SRS slot. `record_content_identity`
names one exact payload. Changing payload bytes changes `payload_digest` and
therefore the content identity, but it does **not** silently change the logical
record key. That separation is mandatory for conflict detection.

## 8. I3 — record signature

```text
signature_domain =
  SIMIGO_PERSISTENT_SRS_RECORD_SIGNATURE_V1;

signature_input =
  ASCII(signature_domain) + 0x00 +
  ASCII(payload_schema_id) + 0x00 +
  canonical_payload_data + 0x00 +
  signer_public_key_raw;

signature =
  Ed25519 signature over signature_input;

signer_public_key_raw =
  32-byte raw Ed25519 public key;

signature_raw =
  64-byte raw Ed25519 signature.
```

The signer must be verified against the compile-time production trust anchor. A
subject-supplied anchor, runtime-selected anchor, or alternate trusted root is
forbidden.

## 9. I4 — canonical envelope bytes

The envelope is a binary canonical object in `PERSISTENT_SRS_ENVELOPE_CANONICAL_V1`
format. It does not embed payload bytes; the physical frame stores `I1` adjacent
to `I4`.

### 9.1 Envelope field encoding

All integers are unsigned big-endian.

```text
FIELD :=
  label_length_u16 +
  label_ascii_bytes +
  value_length_u64 +
  value_bytes;

ENVELOPE :=
  field_count_u32 +
  exactly the 13 FIELD values below, in the exact listed order;
```

No trailing byte, omitted field, repeated field, reordered field, unknown field,
or extra field is valid.

### 9.2 Required envelope fields

| # | Label | Value encoding | Required value / source |
| --- | --- | --- | --- |
| 1 | `envelope_schema_id` | UTF-8 | `SIMIGO_PERSISTENT_SRS_ENVELOPE_V1` |
| 2 | `storage_format_version` | UTF-8 | `PERSISTENT_SRS_STORAGE_V1` |
| 3 | `logical_key_identity` | UTF-8 | Exactly I0 `identity` |
| 4 | `logical_key_version` | UTF-8 | Exactly I0 `version` |
| 5 | `payload_digest_hex` | 64 ASCII lowercase hex | Exactly recomputed I2 |
| 6 | `encoding_identity` | UTF-8 | Exactly I0 `encoding_identity` |
| 7 | `signature_domain` | UTF-8 | Exactly I3 domain |
| 8 | `signer_public_key` | 32 raw bytes | Signer verified against fixed anchor |
| 9 | `signature` | 64 raw bytes | Exactly I3 signature |
| 10 | `producer_authorization_reference` | UTF-8 | Exactly I0 field |
| 11 | `decision_core_source_commit` | UTF-8 | Exactly I0 field and fixed accepted commit |
| 12 | `decision_core_source_sha256` | 64 lowercase ASCII hex | Exactly I0 field and fixed accepted SHA256 |
| 13 | `completion_state` | UTF-8 | Exactly `COMPLETE` |

The envelope is the storage witness for fields also present in I0. I0 remains the
semantic authority; every repeated envelope field must match it byte-for-byte.

## 10. I5 — envelope digest

```text
envelope_digest_raw =
  SHA256(
    ASCII("SIMIGO_PERSISTENT_SRS_ENVELOPE_DIGEST_V1") +
    0x00 +
    canonical_envelope_bytes
  );
```

`canonical_envelope_bytes` is the complete I4 object defined above. It contains
no `envelope_digest` field, so the digest cannot include itself.

## 11. P0 — exact physical frame

The only valid physical storage format is
`PERSISTENT_SRS_PHYSICAL_FRAME_V1`. All integers are unsigned big-endian.

### 11.1 Byte layout

| Offset formula | Size | Field | Required value |
| --- | ---: | --- | --- |
| `0` | 12 | `MAGIC_START` | ASCII `SIMISRSV1001` |
| `12` | 4 | `physical_version_u32` | `1` |
| `16` | 8 | `payload_byte_length_u64` | Exact length of I1 |
| `24` | 8 | `envelope_byte_length_u64` | Exact length of I4 |
| `32` | 32 | `payload_digest_raw` | Exactly I2 raw digest |
| `64` | `payload_byte_length` | `canonical_payload_data` | Exactly I1 |
| `64 + P` | `E` | `canonical_envelope_data` | Exactly I4 |
| `64 + P + E` | 32 | `envelope_digest_raw` | Exactly I5 raw digest |
| `96 + P + E` | 12 | `MAGIC_END` | ASCII `SIMISRSV1END` |

`P = payload_byte_length` and `E = envelope_byte_length`.

### 11.2 Exact total length

```text
total_file_length =
  108 + payload_byte_length + envelope_byte_length;
```

A file shorter or longer than this value is invalid. Zero-length payload or
envelope is invalid. Trailing data after `MAGIC_END` is invalid.

### 11.3 Storage key

Within the authorized root:

```text
records/<payload_digest_hex>.psrs
```

The filename is a content-addressed storage key. It is not the semantic identity.
A file outside the authorized records subtree or with an unauthorized location
fails location authorization even if all integrity checks pass.

## 12. Logical-key uniqueness and conflict rule

An authorized evidence root is a logical-key namespace. Before reporting a
successful write, the writer must determine whether the logical record key
already exists in that root.

```text
same logical_record_key + same payload_digest + byte-equivalent I1
  = IDEMPOTENT_COMPLETE;

same logical_record_key + different payload_digest
  = PERSISTENT_LOGICAL_KEY_CONFLICT;

different logical_record_key + same payload_digest
  = RECORD_CONTENT_IDENTITY_MISMATCH;

any duplicate physical file with unequal bytes
  = PHYSICAL_RECORD_CORRUPT.
```

The final filename is content-addressed, but the content-addressed filename does
not exempt the writer from logical-key conflict detection. A root scan is
mandatory unless a separately frozen equivalent index is authorized.

Writers must serialize root mutation. The future implementation manifest must
bind an exact writer-lock mechanism. If exclusive write access cannot be proven,
the result is:

```text
PERSISTENT_CONCURRENT_WRITE_INDETERMINATE
```

and the operation fails closed. Stale or undeletable locks never revert to silent
success.

## 13. Required read verification order

A reader must stop at the first failure and never repair input.

| Order | Check |
| ---: | --- |
| R1 | File length is at least 108 bytes |
| R2 | `MAGIC_START`, physical version, and length fields parse |
| R3 | Declared total length equals exact physical file length |
| R4 | `MAGIC_END` occurs exactly at the final 12 bytes |
| R5 | Envelope parses as exactly 13 required fields in exact order |
| R6 | Envelope schema and storage format are exact |
| R7 | `completion_state` is exactly `COMPLETE` |
| R8 | `encoding_identity` is exactly `SRSVAL-CANONICAL-TEXT-V4` |
| R9 | Envelope logical key exactly equals I0 logical key |
| R10 | Header digest, envelope digest, recomputed payload digest, and `payload_digest_hex` all agree |
| R11 | Canonical payload is structurally closed and valid |
| R12 | Signature domain and signer are authorized; Ed25519 signature verifies |
| R13 | Producer authorization reference matches I0 |
| R14 | Decision Core commit and SHA256 match I0 and the fixed accepted binding |
| R15 | Evidence location satisfies the separately authorized manifest |
| R16 | Logical-key uniqueness check required by the write/audit operation passes |
| R17 | Only after R1–R16 pass: `COMPLETE_VERIFIED` |

Any inability to complete a check is
`PERSISTENCE_VERIFICATION_INDETERMINATE` and is treated as BLOCK.

## 14. Field authority and cross-validation matrix

| Witness / repeated field | Authoritative source | Required validation |
| --- | --- | --- |
| `identity`, `version` | I0 | Envelope logical key must equal I0 |
| `payload_digest` | Recomputation from I1 | Physical raw digest, envelope hex, and recomputed digest must agree |
| `encoding_identity` | I0 | Envelope field must equal I0 and fixed V4 identity |
| `signature_domain` | I3 construction rule | Envelope value must equal fixed domain |
| `signer_public_key` | Fixed production trust anchor | Envelope key must equal authorized anchor; signature must verify |
| `signature` | I3 signature bytes | Envelope signature must verify against I1 and signer |
| `producer_authorization_reference` | I0 | Envelope field must equal I0 byte-for-byte |
| Decision Core commit and SHA256 | Fixed accepted Decision Core binding | I0 and envelope must equal each other and the frozen values |
| `storage_format_version` | I4 envelope | Must equal `PERSISTENT_SRS_STORAGE_V1`; physical version must equal `1` |
| `completion_state` | I4 envelope | Must equal exactly `COMPLETE`; no other value is valid |
| Segment lengths | Exact physical bytes | Header lengths, actual segments, total length, and end magic must agree |
| Evidence location | Authorized manifest | Content-addressed path and root must satisfy the separate stage authorization |

Envelope-only fields are not protected by the payload signature. Therefore each
envelope-only field has a closed allowed value or a mandatory cross-check. An
attacker who modifies an envelope field and recomputes I5 must still fail R6,
R7, R8, R9, R10, R12, R13, R14, or R15.

## 15. Write and completion semantics

A writer must execute:

```text
W1  acquire the authorized exclusive writer lock;
W2  scan the authorized root for the logical record key;
W3  reject logical-key conflict or indeterminate scan;
W4  construct I0–I5 exactly as defined;
W5  frame P0;
W6  write to a staging file inside the same authorized root;
W7  flush the staging file;
W8  atomically rename to records/<payload_digest_hex>.psrs;
W9  flush the containing directory when supported;
W10 reopen the exact final path and execute R1–R15;
W11 execute logical-key uniqueness confirmation;
W12 release the writer lock only after the verdict;
W13 report COMPLETE_VERIFIED only if W10–W11 pass.
```

Rules:

```text
final records are immutable;
overwrite is forbidden;
staging files are never valid records;
same key and same bytes may be IDEMPOTENT_COMPLETE;
same key and different bytes are PERSISTENT_LOGICAL_KEY_CONFLICT;
writer memory may not substitute for W10;
writer lock release may not turn an unverified write into success.
```

## 16. Persistence failure semantics

| Condition | Required result |
| --- | --- |
| Writer exits before atomic rename | Final record absent; reader returns `RECORD_NOT_FOUND`; staging remains invalid |
| Rename completes but writer exits before verification | Object may exist, but no verdict exists; reader must independently verify |
| File is too short | `TRUNCATED_RECORD` |
| File is longer than exact frame | `TRAILING_DATA_AFTER_RECORD` |
| Magic, version, or frame lengths invalid | `PHYSICAL_LAYOUT_INVALID` |
| Envelope field count/order/label/value invalid | `NON_CANONICAL_ENVELOPE` |
| Completion state is not exactly `COMPLETE` | `COMPLETION_STATE_INVALID` |
| Payload digest differs anywhere | `PAYLOAD_DIGEST_MISMATCH` |
| Envelope digest differs | `ENVELOPE_DIGEST_MISMATCH` |
| Signature, signer, or domain differs | `SIGNATURE_VERIFICATION_FAILED` |
| Logical key differs between I0 and envelope | `LOGICAL_KEY_MISMATCH` |
| Same logical key has different content | `PERSISTENT_LOGICAL_KEY_CONFLICT` |
| NIL becomes explicit empty, or reverse | `CANONICAL_PRESENCE_MISMATCH` |
| Valid unordered collection reorders | `VALID_CANONICAL_EQUIVALENCE` |
| Duplicate count changes | `CANONICAL_MULTISET_MISMATCH` |
| Unknown schema/version/field | `UNKNOWN_SCHEMA_OR_FIELD` |
| Decision Core binding differs | `DECISION_CORE_BINDING_MISMATCH` |
| Evidence location differs | `EVIDENCE_LOCATION_UNAUTHORIZED` |
| Writer lock cannot be proven exclusive | `PERSISTENT_CONCURRENT_WRITE_INDETERMINATE` |
| Any check cannot complete | `PERSISTENCE_VERIFICATION_INDETERMINATE`, BLOCK |

`COMPLETE_VERIFIED` means the checked bytes passed in the current read process.
It is not durable-system proof, not ES₂ authorization, and not proof of
non-recompute.

## 17. Manifest record groups

A future filled instance must bind:

```text
this contract identity and Human-assigned integrity binding;
authorization request and Human ruling;
requested_stage_set;
authorized repository revision;
authorized writable path set;
forbidden path and dependency sets;
implementation artifact digest placeholders;
immutable fixture set and fixture digests;
execution artifact/runtime/environment bindings;
observer authorization and channel universe;
authorized evidence-root identity and exact root binding;
writer-lock mechanism;
logical-key uniqueness mechanism;
expected validation matrix;
evidence locations and integrity bindings;
stage validity boundaries.
```

Conditional Manifest Instance v0.1 is not executable until rebound to this
contract and separately authorized.

### 17.1 IMPLEMENTATION candidate scope

A future implementation authorization may allow only:

```text
simigo2-experimental/Sources/SimiGo2Experimental/PersistentSRSRepresentation.swift;
simigo2-experimental/Tests/SimiGo2ExperimentalTests/PersistentSRSRepresentationTests.swift;
```

Forbidden dependencies remain:

```text
MLX;
SQLite;
canonical PALACE storage;
canonical Information Space storage;
network clients;
new external Swift packages;
V6 runner, child, marker, or evidence mutation.
```

### 17.2 FIXTURE_PREPARATION candidate scope

Future fixtures must be immutable and must separately bind at least:

```text
valid record;
reopen record;
cross-process record;
digest mutation;
signature/signer/domain mutation;
logical-key mismatch;
same-key different-content conflict;
NIL-to-empty mutation;
valid unordered reorder;
duplicate-count mutation;
truncated record;
trailing-byte record;
partial record;
corrupt record;
unknown physical/envelope version;
unknown or extra envelope field;
completion-state mutation;
producer-reference mismatch;
Decision Core binding mismatch;
unauthorized evidence location;
concurrent-writer indeterminate case.
```

### 17.3 EXECUTION candidate scope

Execution requires exact artifact, environment, observer, evidence-root, writer
lock, and budget bindings. The candidate default is one run per separately
authorized fixture. A failed run consumes that fixture budget. Repair or retry
requires a new scope-bound Human Authorization Record.

## 18. Observer authority

```text
Observer proves process and filesystem operations.
Persistence verifier proves whether bytes form a valid record.
Neither authority replaces the other.
Observer classification is never semantic payload.
Persistence COMPLETE_VERIFIED is never observer execution evidence.
Persistence PASS never authorizes ES2.
Persistence PASS never proves non-recompute.
```

Observer, subject, writer, fixture builder, and manifest generator remain
independent authorities.

## 19. Stage separation

```text
IMPLEMENTATION
  != FIXTURE_PREPARATION
  != EXECUTION
  != independent ES2 consumption
  != non-recompute attribution
  != IS mutation.
```

No stage may derive from this contract's acceptance, another stage, or the
accepted Decision Core.

## 20. Adversarial finding matrix

| ID | Attack | Contract control | Expected result | Observer source / evidence artifact |
| --- | --- | --- | --- | --- |
| PR-A1 | Make digest/signature circular | Sections 7–10; I2 excludes I3/I5; I3 excludes I5; I5 excludes itself | Contract-invalid; implementation cannot construct a passing cycle | Not applicable for design; future canonical construction test artifact |
| PR-A2 | Include envelope digest in itself | Section 10 hashes only envelope bytes before digest insertion | Contract-invalid | Envelope parser evidence |
| PR-A3 | Promote path to semantic identity | Sections 5, 11.3, 14 | Path affects authorization only; identity remains I0/I2 | Observer path evidence + location authorization record |
| PR-A4 | Keep logical key while changing bytes | Sections 7, 12, 16 | `PERSISTENT_LOGICAL_KEY_CONFLICT` | Writer scan + execution test evidence |
| PR-A5 | Treat authorized move as identity change | Sections 5, 14 | Same bytes keep identity; unauthorized location separately fails | Observer path evidence + verification record |
| PR-A6 | Accept staging/temp file as complete | Sections 15–16 | `RECORD_NOT_FOUND` / staging invalid | Observer file evidence + reader outcome |
| PR-A7 | Reuse writer memory verdict cross-process | Sections 15–16; reader must R1–R16 | No inherited `COMPLETE_VERIFIED` | Reader verification artifact |
| PR-A8 | NIL becomes explicit empty, or reverse | Sections 5, 16 | `CANONICAL_PRESENCE_MISMATCH` | Canonical parser evidence |
| PR-A9 | Confuse valid reorder with duplicate change | Sections 5, 16 | Reorder = `VALID_CANONICAL_EQUIVALENCE`; count change = `CANONICAL_MULTISET_MISMATCH` | Canonical parser evidence |
| PR-A10 | Remove unknown field by lenient decode | Sections 9, 13, 16 | `NON_CANONICAL_ENVELOPE` | Envelope parser evidence |
| PR-A11 | Alter Decision Core binding and recompute I5 | Sections 5, 9.2, 14 | `DECISION_CORE_BINDING_MISMATCH` | Cross-check evidence |
| PR-A12 | Subject selects alternate signer/anchor | Sections 8, 14 | `SIGNATURE_VERIFICATION_FAILED` | Fixed-anchor verifier evidence |
| PR-A13 | Insert observer classification into payload | Section 5 closed field set | `NON_CANONICAL_RECORD` / semantic parser BLOCK | Payload schema evidence |
| PR-A14 | Treat persistence PASS as ES2 authorization | Sections 1, 19 | STOP; separate authorization required | Authorization boundary record |
| PR-A15 | Treat persistence PASS as non-recompute proof | Sections 1, 18 | Claim invalid; separate attribution required | Authorization boundary record |
| PR-A16 | Expand stage by creating evidence root | Sections 1, 17, 19 | STOP; root requires separate authorization | Marker/root absence record |
| PR-A17 | Exploit ambiguous physical framing | Sections 11, 13, 16 | Exact frame and total length required; `PHYSICAL_LAYOUT_INVALID`, `TRUNCATED_RECORD`, or `TRAILING_DATA_AFTER_RECORD` | Physical parser evidence |
| PR-A18 | Bypass same-key different-content conflict | Sections 7, 12, 15 | Writer scan/lock required; `PERSISTENT_LOGICAL_KEY_CONFLICT` or indeterminate | Root scan and writer-lock evidence |
| PR-A19 | Tamper envelope witness and recompute I5 | Sections 9.2, 13–14 | Matching cross-check or fixed-value check fails | Envelope cross-check evidence |
| PR-A20 | Mark partial or mutated object complete | Sections 9.2, 13, 16 | `COMPLETION_STATE_INVALID` unless all R1–R16 pass | Reader verification artifact |

Every future manifest review must retain and revalidate this matrix.

## 21. Acceptance criteria

Human may accept only if:

```text
C1  the seven-layer model is exact and acyclic;
C2  logical key and content identity are distinct;
C3  same-key different-content behavior is fail-closed;
C4  physical byte layout, lengths, trailer, and storage key are exact;
C5  every envelope witness has an authority and cross-check;
C6  completion state has one valid value;
C7  NIL, empty, ordering, duplicate, and unknown-field rules are closed;
C8  every persistence failure has a deterministic fail-closed result;
C9  no stage is authorized by contract acceptance;
C10  independent ES2 and non-recompute attribution remain excluded;
C11  canonical PALACE and Information Space mutation remain forbidden.
```

## 22. Decision requested

Human is asked to return exactly one:

```text
ACCEPT_PERSISTENT_SRS_MANIFEST_CONTRACT_V1.1
```

or

```text
REVISE_PERSISTENT_SRS_MANIFEST_CONTRACT_V1.1
```

or

```text
REJECT_PERSISTENT_SRS_MANIFEST_CONTRACT_V1.1
```

Acceptance freezes this design and assigns its integrity binding. It does not
authorize implementation, fixture preparation, execution, marker creation,
evidence-root creation, independent ES₂ consumption, non-recompute attribution,
MLX, V6, PALACE, Information Space, or production operation.
