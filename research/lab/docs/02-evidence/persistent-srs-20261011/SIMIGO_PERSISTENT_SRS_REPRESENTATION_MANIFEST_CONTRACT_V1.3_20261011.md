# Persistent SRS Representation Manifest Contract v1.3

> **Status:** SUBMITTED FOR HUMAN DESIGN REVIEW — DESIGN ONLY / NO STAGE AUTHORIZED
> **Date:** 2026-10-11
> **Supersedes:** Manifest Contract v1.2 (`REVISE / SUPERSEDED / NEVER FROZEN`)
> **Authorization request:** `SIMIGO_PERSISTENT_SRS_REPRESENTATION_AUTHORIZATION_REQUEST_V0.1_20261011.md`
> **Authorization request SHA256:** `4063787b0680da2ccd872ec949c4602295c8bd5d9d6620f7149ff6caa288c791`
> **Human ruling on v1.2:** `REVISE_PERSISTENT_SRS_MANIFEST_CONTRACT_V1.2`
> **Canonical PALACE mutation:** FORBIDDEN
> **Canonical Information Space mutation:** FORBIDDEN
> **MLX execution:** FORBIDDEN
> **V6 rerun:** FORBIDDEN
> **Independent ES₂ consumption:** NOT AUTHORIZED BY THIS CONTRACT
> **Non-recompute attribution:** NOT AUTHORIZED BY THIS CONTRACT

## 1. Scope and authority

This contract defines the exact I0 JSON value schema, canonical payload bytes,
unique signature trust anchor, physical frame, separated digest checks, ordered
identity comparison, parser resource limits, envelope cross-validation, logical
key conflicts, and fail-closed persistence semantics for a minimal Persistent SRS
Representation.

It does not implement persistence, authorize code changes, authorize fixture
preparation, authorize execution, create evidence, authorize markers or an
evidence root, authorize independent ES₂ consumption, authorize non-recompute
attribution, or amend frozen SRS-VAL governance.

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
  ed891ca8a203664695a976caeff108ac334f1784;

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

Persistence Manifest Contract v1.0 =
  REVISE / SUPERSEDED / NEVER ACCEPTED OR FROZEN;

Persistence Manifest Contract v1.1 =
  REVISE / SUPERSEDED / NEVER ACCEPTED OR FROZEN;

Persistence Manifest Contract v1.2 =
  REVISE / SUPERSEDED BY V1.3 / NEVER ACCEPTED OR FROZEN.
```

## 3. Contract identity

```text
contract_identity =
  SIMIGO_PERSISTENT_SRS_REPRESENTATION_MANIFEST_CONTRACT_V1.3;

contract_status_at_issue =
  SUBMITTED_FOR_HUMAN_DESIGN_REVIEW;

contract_integrity_binding =
  immutable Git commit/content binding assigned by Human acceptance;

self_declared_contract_digest = FORBIDDEN.
```

Conditional Manifest Instance v0.1 remains non-executable until rebound and
separately stage-authorized.

## 4. Exact seven-layer model

```text
I0  semantic record values
I1  canonical payload bytes
I2  payload digest
I3  record signature
I4  canonical envelope bytes
I5  envelope digest
P0  physical frame and evidence placement
```

`I0`–`I5` are integrity-construction layers. `P0` is physical serialization and
placement, not a semantic integrity input.

Dependency graph:

```text
I0 -> I1 -> I2 -> I3 -> I4 -> I5
P0 frames I1, I4, I2, and I5 but is not input to their construction
```

No layer depends on a later integrity layer.

## 5. Normative I0 JSON Schema

The complete, closed type definition is externalized in:

```text
PERSISTENT_SRS_RECORD_JSON_SCHEMA_V1.3.json
```

Its SHA256 is:

```text
9e425322ccc6af085cbcc64c86242bd5d1f519f648cc05d6a15e0a98a761d545
```

The schema is normative and uses JSON Schema Draft 2020-12. It is metadata for
validation; it is not serialized as part of I0.

Rules:

```text
I0 must validate against that exact schema;
all objects use additionalProperties=false;
all listed members are required;
unknown and missing members fail;
null means Swift/JSON nil;
[] means an explicit empty collection;
null and [] are never interchangeable;
schema `$defs` are type definitions, not I0 properties;
schema `$id`, `$schema`, `title`, and `description` are not I0 data;
strings are exact UTF-8 values without Unicode normalization;
content digests are exactly 64 lowercase hexadecimal characters;
UTC timestamps use RFC 3339 date-time ending in Z;
arrays never imply set semantics unless sorting is explicitly required below.
```

The schema maps to accepted Decision Core value types as named in each `$defs`
description. This mapping does not authorize modifying Decision Core.

## 6. I1 — exact canonical payload bytes

```text
encoding_identity = PERSISTENT_SRS_CANONICAL_V1
```

`I1` is the RFC 8785 JCS serialization of the I0 object after the following
canonicalization step:

```text
For each unordered semantic collection, sort elements ascending by the UTF-8
bytes of each element's independent JCS serialization:
  settled_relation_state.provenance_bindings;
  dependency_set.dependencies;
  provenance.bindings;
  lifecycle.bindings;
  freshness.requirements;
  resolution_policy.policies.
Sorting preserves duplicates. Then serialize the complete root object with JCS.
```

Required JCS rules:

```text
UTF-8 only and no byte-order mark;
object members sorted as required by RFC 8785;
no whitespace beyond exact JCS escaping;
no numeric values;
no Unicode normalization;
exact string escaping per RFC 8785;
null remains null;
[] remains an explicit empty array;
unknown, missing, or duplicate members fail.
```

Two I0 values that differ only in the order of an unordered collection produce
the same `I1`. Two values with different members, duplicate counts, field types,
field values, or presence states produce different `I1`.

## 7. Logical key and content identity

Identity comparison uses ordered tuples, not concatenated strings.

```text
logical_record_key =
  (identity: String, version: String);

record_content_identity =
  (identity: String, version: String, payload_digest_hex: Hex64).
```

Comparison rules:

```text
compare identity exactly by Unicode scalar/UTF-8 content;
compare version exactly by Unicode scalar/UTF-8 content;
do not concatenate identity and version;
do not use a delimiter;
do not apply Unicode normalization;
do not compare case-folded values.
```

If a textual witness is required for diagnostics, it is only:

```text
JCS(["identity", "version"])
JCS(["identity", "version", "payload_digest_hex"])
```

and is not used as the definition of identity.

Within one authorized root:

```text
same logical_record_key + same payload_digest + byte-equivalent I1
  = IDEMPOTENT_COMPLETE;

same logical_record_key + different payload_digest
  = PERSISTENT_LOGICAL_KEY_CONFLICT;

different logical_record_key + same payload_digest
  = RECORD_CONTENT_IDENTITY_MISMATCH.
```

The writer must prove exclusive root mutation and complete logical-key scan
before success. If either cannot be proven:

```text
PERSISTENT_CONCURRENT_WRITE_INDETERMINATE
```

and the operation fails closed.

## 8. Unique production signature trust anchor

The only authorized anchor is the accepted Decision Core production
record-integrity anchor:

```text
anchor_id =
  SRSVAL_PRODUCTION_RECORD_INTEGRITY_ANCHOR_V1;

decision_core_symbol =
  SRSVALTrustAnchor.recordIntegrityIssuer;

signer_public_key_base64 =
  +fG2YJ+YnW1RtsX8bCbukUERvSlIq4fvP7cZcs6+VMI=;

signer_public_key_raw_length = 32;

signer_public_key_raw_sha256 =
  8c7c011f4f1458fad4b26b0d6a12b3f37bbab5b6a10eaef46530efb0c475c4c4;

persistent_signature_domain =
  SIMIGO_PERSISTENT_SRS_RECORD_SIGNATURE_V1.
```

No other Decision Core anchor, test anchor, runtime anchor, configurable anchor,
or additional key is valid.

```text
signature_input =
  ASCII(persistent_signature_domain) + 0x00 +
  ASCII("SIMIGO_PERSISTENT_SRS_RECORD_V1") + 0x00 +
  canonical_payload_data + 0x00 +
  signer_public_key_raw;

signature =
  Ed25519 signature over signature_input.
```

## 9. I4 — canonical envelope bytes

Envelope format is `PERSISTENT_SRS_ENVELOPE_CANONICAL_V1`. All integers are
unsigned big-endian.

```text
FIELD :=
  label_length_u16 +
  label_ascii_bytes +
  value_length_u64 +
  value_bytes;

ENVELOPE :=
  field_count_u32 +
  exactly 13 FIELD values in exact order;
```

| # | Label | Value encoding | Required value / source |
| --- | --- | --- | --- |
| 1 | `envelope_schema_id` | UTF-8 | `SIMIGO_PERSISTENT_SRS_ENVELOPE_V1` |
| 2 | `storage_format_version` | UTF-8 | `PERSISTENT_SRS_STORAGE_V1` |
| 3 | `logical_key_identity` | UTF-8 | I0 `logical_key.identity` |
| 4 | `logical_key_version` | UTF-8 | I0 `logical_key.version` |
| 5 | `payload_digest_hex` | 64 ASCII lowercase hex | Recomputed I2 |
| 6 | `encoding_identity` | UTF-8 | `PERSISTENT_SRS_CANONICAL_V1` |
| 7 | `signature_domain` | UTF-8 | Section 8 domain |
| 8 | `signer_public_key` | 32 raw bytes | Section 8 anchor |
| 9 | `signature` | 64 raw bytes | Section 8 signature |
| 10 | `producer_authorization_reference` | UTF-8 | I0 field |
| 11 | `decision_core_source_commit` | UTF-8 | I0 field |
| 12 | `decision_core_source_sha256` | 64 lowercase hex | I0 field |
| 13 | `completion_state` | UTF-8 | `COMPLETE` |

Unknown, missing, duplicated, reordered, truncated, or extra envelope fields are
invalid.

## 10. I5 — envelope digest

```text
envelope_digest_raw =
  SHA256(
    ASCII("SIMIGO_PERSISTENT_SRS_ENVELOPE_DIGEST_V1") +
    0x00 +
    canonical_envelope_bytes
  );
```

The envelope contains no envelope-digest field, so I5 cannot include itself.

## 11. P0 — exact physical frame

Physical format is `PERSISTENT_SRS_PHYSICAL_FRAME_V1`. All integers are unsigned
big-endian.

| Offset formula | Size | Field | Required value |
| --- | ---: | --- | --- |
| `0` | 12 | `MAGIC_START` | ASCII `SIMISRSV1001` |
| `12` | 4 | `physical_version_u32` | `1` |
| `16` | 8 | `payload_byte_length_u64` | Exact I1 length |
| `24` | 8 | `envelope_byte_length_u64` | Exact I4 length |
| `32` | 32 | `payload_digest_raw` | Exactly I2 |
| `64` | `P` | `canonical_payload_data` | Exactly I1 |
| `64 + P` | `E` | `canonical_envelope_data` | Exactly I4 |
| `64 + P + E` | 32 | `envelope_digest_raw` | Exactly I5 |
| `96 + P + E` | 12 | `MAGIC_END` | ASCII `SIMISRSV1END` |

```text
total_file_length = 108 + P + E;
storage_key = records/<payload_digest_hex>.psrs;
```

Storage key is authorization/address metadata, not semantic identity.

## 12. Parser limits and checked parsing

```text
MAX_PAYLOAD_BYTES = 16777216;
MAX_ENVELOPE_BYTES = 1048576;
MAX_TOTAL_BYTES = 17825900;
MAX_FIELD_LABEL_BYTES = 128;
MAX_JSON_DEPTH = 8;
MAX_ARRAY_COUNT = 1000000;
MAX_STRING_BYTES = 1048576;
```

Parsing requirements:

```text
use checked integer arithmetic for every offset, length, and sum;
validate minimum file length before segment access;
validate all maximum limits before allocation;
never allocate based solely on an unverified length;
perform bounded reads;
reject incomplete reads;
reject trailing data after MAGIC_END;
reject invalid UTF-8;
reject JSON depth over 8;
reject duplicate JSON members;
reject unknown and missing JSON members;
reject over-limit strings and arrays;
fail on first violation without repair or fallback.
```

## 13. Read verification order and failure status registry

The reader stops at the first failed check and returns that exact status. Only
statuses in this registry are valid; aliases are forbidden.

### 13.1 Read checks

| Order | Check | Failure status |
| ---: | --- | --- |
| R1 | File length is at least 108 bytes | `TRUNCATED_RECORD` |
| R2 | Start magic is exact | `MAGIC_START_MISMATCH` |
| R3 | Physical version is exactly `1` | `UNKNOWN_PHYSICAL_FORMAT_VERSION` |
| R4 | Length parse and checked arithmetic succeed | `INTEGER_OVERFLOW_OR_RESOURCE_LIMIT` |
| R5 | Payload/envelope lengths are within limits | `INTEGER_OVERFLOW_OR_RESOURCE_LIMIT` |
| R6 | `108 + P + E` equals actual file length | `PHYSICAL_LENGTH_MISMATCH` |
| R7 | End magic is exact and has no trailing bytes | `MAGIC_END_MISMATCH` / `TRAILING_DATA_AFTER_RECORD` |
| R8 | Envelope is exactly 13 ordered fields | `NON_CANONICAL_ENVELOPE` |
| R9 | Envelope schema is exact | `UNKNOWN_ENVELOPE_SCHEMA` |
| R10 | Storage format version is exact | `UNKNOWN_STORAGE_FORMAT_VERSION` |
| R11 | Envelope encoding identity is exact | `ENCODING_IDENTITY_MISMATCH` |
| R12 | Completion state is exactly `COMPLETE` | `COMPLETION_STATE_INVALID` |
| R13 | Envelope logical key equals I0 ordered logical key | `ENVELOPE_LOGICAL_KEY_MISMATCH` |
| R14 | Payload is valid UTF-8 and within limit | `INVALID_JSON_UTF8` / `INTEGER_OVERFLOW_OR_RESOURCE_LIMIT` |
| R15 | Payload JSON depth, duplicate/unknown/missing members, types, and limits pass | `JSON_DEPTH_LIMIT_EXCEEDED` / `DUPLICATE_JSON_MEMBER` / `UNKNOWN_SCHEMA_OR_FIELD` / `INTEGER_OVERFLOW_OR_RESOURCE_LIMIT` |
| R16 | Payload schema ID is exact | `UNKNOWN_PAYLOAD_SCHEMA` |
| R17 | Header payload digest equals envelope payload digest | `PAYLOAD_DIGEST_MISMATCH` |
| R18 | Recomputed payload digest equals that payload digest | `PAYLOAD_DIGEST_MISMATCH` |
| R19 | Trailing envelope digest equals recomputed envelope digest | `ENVELOPE_DIGEST_MISMATCH` |
| R20 | Signature domain/signer are exact and signature verifies | `SIGNATURE_VERIFICATION_FAILED` |
| R21 | Envelope producer reference equals I0 | `PRODUCER_AUTHORIZATION_REFERENCE_MISMATCH` |
| R22 | Decision Core commit and SHA256 equal I0 and frozen values | `DECISION_CORE_BINDING_MISMATCH` |
| R23 | Evidence location is authorized | `EVIDENCE_LOCATION_UNAUTHORIZED` |
| R24 | Logical-key uniqueness check passes | `PERSISTENT_LOGICAL_KEY_CONFLICT` / `RECORD_CONTENT_IDENTITY_MISMATCH` / `PERSISTENT_CONCURRENT_WRITE_INDETERMINATE` |
| R25 | Only after R1–R24 | `COMPLETE_VERIFIED` |

If a check cannot be executed, return
`PERSISTENCE_VERIFICATION_INDETERMINATE` and BLOCK.

## 14. Write semantics

```text
W1  acquire authorized exclusive writer lock;
W2  scan authorized root using ordered logical_record_key tuples;
W3  reject conflict, content mismatch, or indeterminate scan;
W4  construct I0–I5 exactly;
W5  frame P0;
W6  write staging file in the same authorized root;
W7  flush staging file;
W8  atomically rename to records/<payload_digest_hex>.psrs;
W9  flush directory where supported;
W10 reopen final path and execute R1–R23;
W11 confirm ordered logical-key uniqueness;
W12 release lock only after verdict;
W13 report COMPLETE_VERIFIED only after W10–W11 pass.
```

Final records are immutable. Staging files are not records. Overwrite is
forbidden.

## 15. Persistence failure semantics

| Condition | Exact status |
| --- | --- |
| File shorter than 108 bytes | `TRUNCATED_RECORD` |
| Start magic differs | `MAGIC_START_MISMATCH` |
| Physical version differs | `UNKNOWN_PHYSICAL_FORMAT_VERSION` |
| Length parse/limit/arithmetic fails | `INTEGER_OVERFLOW_OR_RESOURCE_LIMIT` |
| Declared length differs from actual | `PHYSICAL_LENGTH_MISMATCH` |
| End magic differs | `MAGIC_END_MISMATCH` |
| Bytes exist after end magic | `TRAILING_DATA_AFTER_RECORD` |
| Envelope field structure differs | `NON_CANONICAL_ENVELOPE` |
| Envelope schema differs | `UNKNOWN_ENVELOPE_SCHEMA` |
| Storage format differs | `UNKNOWN_STORAGE_FORMAT_VERSION` |
| Encoding identity differs | `ENCODING_IDENTITY_MISMATCH` |
| Completion state differs | `COMPLETION_STATE_INVALID` |
| Envelope logical key differs | `ENVELOPE_LOGICAL_KEY_MISMATCH` |
| Payload UTF-8 invalid | `INVALID_JSON_UTF8` |
| JSON depth/member/type/schema violation | `JSON_DEPTH_LIMIT_EXCEEDED` / `DUPLICATE_JSON_MEMBER` / `UNKNOWN_SCHEMA_OR_FIELD` / `INTEGER_OVERFLOW_OR_RESOURCE_LIMIT` |
| Payload schema differs | `UNKNOWN_PAYLOAD_SCHEMA` |
| Payload digest check fails | `PAYLOAD_DIGEST_MISMATCH` |
| Envelope digest check fails | `ENVELOPE_DIGEST_MISMATCH` |
| Signature/domain/signer fails | `SIGNATURE_VERIFICATION_FAILED` |
| Producer reference differs | `PRODUCER_AUTHORIZATION_REFERENCE_MISMATCH` |
| Decision Core binding differs | `DECISION_CORE_BINDING_MISMATCH` |
| Evidence location differs | `EVIDENCE_LOCATION_UNAUTHORIZED` |
| Same ordered logical key, different content | `PERSISTENT_LOGICAL_KEY_CONFLICT` |
| Different logical key, same content | `RECORD_CONTENT_IDENTITY_MISMATCH` |
| NIL becomes explicit empty, or reverse | `CANONICAL_PRESENCE_MISMATCH` |
| Valid unordered reorder | `VALID_CANONICAL_EQUIVALENCE` |
| Duplicate count changes | `CANONICAL_MULTISET_MISMATCH` |
| Lock cannot be proven exclusive | `PERSISTENT_CONCURRENT_WRITE_INDETERMINATE` |
| Any check cannot execute | `PERSISTENCE_VERIFICATION_INDETERMINATE` |

`INTEGER_OVERFLOW` is not a valid alias. The only resource/overflow status is
`INTEGER_OVERFLOW_OR_RESOURCE_LIMIT`.

`COMPLETE_VERIFIED` is current-read verification only. It is not durability
proof, ES₂ authorization, non-recompute attribution, or production proof.

## 16. Manifest record groups

A future filled instance must bind this contract identity and Human-assigned
integrity binding, request and ruling, requested stages, repository revision,
writable/forbidden paths, implementation and runtime digests, JSON Schema digest,
fixture digests, environment, observer and channel universe, evidence root,
writer-lock mechanism, ordered-key scan mechanism, validation matrix, evidence
integrity bindings, and stage validity boundaries.

Conditional Manifest Instance v0.1 remains non-executable until rebound and
separately authorized.

### 16.1 IMPLEMENTATION candidate scope

Only these paths may be authorized:

```text
simigo2-experimental/Sources/SimiGo2Experimental/PersistentSRSRepresentation.swift;
simigo2-experimental/Tests/SimiGo2ExperimentalTests/PersistentSRSRepresentationTests.swift;
```

The JSON Schema artifact is a frozen test/verification input, not a writable
implementation target.

Forbidden dependencies:

```text
MLX;
SQLite;
canonical PALACE storage;
canonical Information Space storage;
network clients;
new external Swift packages;
V6 runner, child, marker, or evidence mutation.
```

### 16.2 FIXTURE_PREPARATION candidate scope

Future fixtures must separately bind at least valid, reopen, cross-process,
payload digest mutation, envelope digest mutation, signature/domain/signer
mutation, logical-key tuple mismatch, same-key different-content, NIL-to-empty,
valid reorder, duplicate-count change, truncated, trailing-byte, partial, corrupt,
unknown physical version, unknown envelope schema, unknown storage version,
unknown payload schema, unknown/extra field, completion mutation, producer
mismatch, core-binding mismatch, unauthorized location, overflow/resource-limit,
and concurrent-writer cases.

### 16.3 EXECUTION candidate scope

Execution requires exact artifact, environment, observer, evidence-root,
writer-lock, schema digest, and budget bindings. Candidate default is one run per
separately authorized fixture. Failed runs consume budget; repair/retry requires
a new Human Authorization Record.

## 17. Observer authority

Observer evidence proves process and filesystem operations. Persistence
verification proves byte validity. Neither replaces the other. Persistence PASS
never authorizes ES₂ and never proves non-recompute.

## 18. Stage separation

```text
IMPLEMENTATION
  != FIXTURE_PREPARATION
  != EXECUTION
  != independent ES2 consumption
  != non-recompute attribution
  != IS mutation.
```

No stage may derive from contract acceptance, another stage, or the accepted
Decision Core.

## 19. Adversarial finding matrix

| ID | Attack | Control | Expected result | Evidence source |
| --- | --- | --- | --- | --- |
| PR-A1 | Digest/signature cycle | Sections 4, 7–10 | Invalid construction | Canonical construction evidence |
| PR-A2 | Envelope digest self-inclusion | Section 10 | Invalid envelope | Envelope parser evidence |
| PR-A3 | Path promoted to identity | Sections 5, 11, 13 | Location authorization only | Path/location evidence |
| PR-A4 | Same logical tuple, changed bytes | Sections 7, 15–16 | `PERSISTENT_LOGICAL_KEY_CONFLICT` | Root scan + writer evidence |
| PR-A5 | Authorized move treated as identity change | Sections 5, 13 | Same identity; unauthorized location separately blocked | Path + verification evidence |
| PR-A6 | Staging accepted as complete | Sections 15–16 | Staging invalid / `RECORD_NOT_FOUND` | Filesystem evidence |
| PR-A7 | Writer verdict reused cross-process | Sections 15–16 | Reader verifies independently | Reader verification evidence |
| PR-A8 | NIL ↔ explicit empty | Sections 5–6, 15 | `CANONICAL_PRESENCE_MISMATCH` | JSON canonical evidence |
| PR-A9 | Reorder confused with duplicate change | Sections 6, 15 | Reorder valid; count change mismatch | Canonical sorting evidence |
| PR-A10 | Lenient unknown-field removal | Sections 5, 13, 15 | `UNKNOWN_SCHEMA_OR_FIELD` | Schema/parser evidence |
| PR-A11 | Core binding drift + recomputed I5 | Sections 5, 9, 13 | `DECISION_CORE_BINDING_MISMATCH` | Cross-check evidence |
| PR-A12 | Alternate anchor/domain | Sections 8, 13 | `SIGNATURE_VERIFICATION_FAILED` | Fixed-anchor evidence |
| PR-A13 | Observer data inserted into payload | Appendix schema closed object | `UNKNOWN_SCHEMA_OR_FIELD` | Schema evidence |
| PR-A14 | Persistence PASS treated as ES2 | Sections 1, 18 | STOP; separate authorization | Authorization record |
| PR-A15 | PASS treated as non-recompute proof | Sections 1, 17 | Claim invalid | Authorization record |
| PR-A16 | Evidence root created by stage expansion | Sections 1, 16, 18 | STOP; separate authorization | Marker/root absence record |
| PR-A17 | Ambiguous physical framing | Sections 11, 13, 15 | Exact frame failure | Physical parser evidence |
| PR-A18 | Bypass same-key conflict | Sections 7, 15 | Conflict or indeterminate | Root scan + lock evidence |
| PR-A19 | Envelope witness tampering + recomputed I5 | Sections 9, 13–15 | Cross-check/fixed-value failure | Envelope evidence |
| PR-A20 | False completion state | Sections 9, 13, 15 | `COMPLETION_STATE_INVALID` | Reader evidence |
| PR-A21 | Payload/envelope digest conflation | Sections 7, 10, 13 | Independent R17–R19 failures | Separated digest evidence |
| PR-A22 | Same values, different custom encoding | Sections 5–6 | Non-JCS/extra mapping rejected | JCS parser evidence |
| PR-A23 | Anchor substitution/domain reuse | Sections 8, 13 | Exact anchor/domain only | Anchor/domain evidence |
| PR-A24 | Huge length/overflow | Sections 11–13, 15 | `INTEGER_OVERFLOW_OR_RESOURCE_LIMIT` | Bounded parser evidence |
| PR-A25 | Placeholder/object type confusion | Section 5 normative schema | Schema validation fails | JSON Schema validation evidence |
| PR-A26 | String concatenation collapses logical keys | Section 7 | Ordered-tuple comparison required | Key comparison evidence |
| PR-A27 | Failure alias or ambiguous status | Sections 13, 15 | Only registry status accepted | Failure registry evidence |
| PR-A28 | Version failures conflated | Sections 11, 13, 15 | Physical/envelope/storage/payload failures are distinct | Version parser evidence |

Future manifest review must retain and revalidate this matrix.

## 20. Acceptance criteria

```text
C1  seven layers are exact and acyclic;
C2  I0 has a closed formal JSON Schema with no placeholder ambiguity;
C3  payload and envelope digests are independently checked;
C4  failure statuses form one closed registry with no aliases;
C5  logical key and content identity are ordered tuples;
C6  unique production anchor and domain are frozen;
C7  same-key different-content is fail-closed;
C8  physical layout and parser limits are exact;
C9  NIL, empty, ordering, duplicates, and unknown fields are closed;
C10 no stage is authorized by contract acceptance;
C11 ES2 and non-recompute attribution remain excluded;
C12 canonical PALACE and Information Space mutation remain forbidden.
```

## 21. Decision requested

Human is asked to return exactly one:

```text
ACCEPT_PERSISTENT_SRS_MANIFEST_CONTRACT_V1.3
```

or

```text
REVISE_PERSISTENT_SRS_MANIFEST_CONTRACT_V1.3
```

or

```text
REJECT_PERSISTENT_SRS_MANIFEST_CONTRACT_V1.3
```

Acceptance freezes this design and assigns its integrity binding. It does not
authorize implementation, fixture preparation, execution, marker creation,
evidence-root creation, independent ES₂ consumption, non-recompute attribution,
MLX, V6, PALACE, Information Space, or production operation.
