# Persistent SRS Representation Manifest Contract v1.2

> **Status:** SUBMITTED FOR HUMAN DESIGN REVIEW — DESIGN ONLY / NO STAGE AUTHORIZED
> **Date:** 2026-10-11
> **Supersedes:** Manifest Contract v1.1 (`REVISE / SUPERSEDED / NEVER FROZEN`)
> **Authorization request:** `SIMIGO_PERSISTENT_SRS_REPRESENTATION_AUTHORIZATION_REQUEST_V0.1_20261011.md`
> **Authorization request SHA256:** `4063787b0680da2ccd872ec949c4602295c8bd5d9d6620f7149ff6caa288c791`
> **Human ruling on v1.1:** `REVISE_PERSISTENT_SRS_MANIFEST_CONTRACT_V1.1`
> **Canonical PALACE mutation:** FORBIDDEN
> **Canonical Information Space mutation:** FORBIDDEN
> **MLX execution:** FORBIDDEN
> **V6 rerun:** FORBIDDEN
> **Independent ES₂ consumption:** NOT AUTHORIZED BY THIS CONTRACT
> **Non-recompute attribution:** NOT AUTHORIZED BY THIS CONTRACT

## 1. Scope and authority

This contract defines the exact canonical payload encoding, unique signature
trust-anchor binding, physical frame, separated digest checks, parser resource
limits, logical-key conflict model, envelope cross-validation rules, and
fail-closed persistence semantics for a minimal Persistent SRS Representation.

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
  c5c6a7ebdcfbcaf6019014ef7d42923d8816dea6;

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
  REVISE / SUPERSEDED BY V1.2 / NEVER ACCEPTED OR FROZEN.
```

## 3. Contract identity

```text
contract_identity =
  SIMIGO_PERSISTENT_SRS_REPRESENTATION_MANIFEST_CONTRACT_V1.2;

contract_status_at_issue =
  SUBMITTED_FOR_HUMAN_DESIGN_REVIEW;

contract_integrity_binding =
  immutable Git commit/content binding assigned by Human acceptance;

self_declared_contract_digest = FORBIDDEN.
```

Conditional Manifest Instance v0.1 remains non-executable until rebound and
separately stage-authorized.

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

`I0`–`I5` are integrity-construction layers. `P0` is physical serialization and
placement, not a semantic integrity input.

Dependency graph:

```text
I0 -> I1 -> I2 -> I3 -> I4 -> I5
P0 frames I1, I4, I2, and I5 but is not input to their construction
```

No layer depends on a later integrity layer.

## 5. I0 — closed semantic record values

I0 has a closed field set. `null` means absent/nil. `[]` means an explicit empty
collection. They are never interchangeable.

### 5.1 Root object

```json
{
  "payload_schema_id": "SIMIGO_PERSISTENT_SRS_RECORD_V1",
  "logical_key": {
    "identity": "<string>",
    "version": "<string>"
  },
  "settled_relation_state": "<SRSVALSettledRelationState mapping>",
  "source_relation": "<SRSVALSourceRelation mapping>",
  "dependency_set": "<SRSVALDependencySet mapping>",
  "result": "<SRSVALResult mapping>",
  "provenance": "<SRSVALProvenanceLifecycle mapping>",
  "lifecycle": "<SRSVALProvenanceLifecycle mapping>",
  "freshness": "<SRSVALFreshness mapping>",
  "resolution_policy": "<SRSVALResolutionPolicy mapping>",
  "producer_authorization_reference": "<string>",
  "decision_core_binding": {
    "source_commit": "1d47f3be56dfa8c6bf7619f4566b271ed74aad27",
    "source_sha256": "7fec2ed4d6e6f82fe677a7f098ec98d3e99bf4138420f1dd051570c75cf1c72e"
  },
  "encoding_identity": "PERSISTENT_SRS_CANONICAL_V1"
}
```

Exactly these root members are allowed. No request, observation, execution trace,
timestamp, host path, process ID, or observer evidence is part of I0.

### 5.2 Shared binding object

Maps to `SRSVALBinding`:

```json
{
  "identity": "<string>",
  "version": "<string>",
  "content_digest": "<64 lowercase hexadecimal characters>"
}
```

### 5.3 `settled_relation_state`

Maps to `SRSVALSettledRelationState`:

```json
{
  "binding": "<Binding|null>",
  "settlement_id": "<string>",
  "status": "<DECLARED_SETTLED|CONTESTED|UNRESOLVED_LIFECYCLE_CONFLICT|INVALIDATED>",
  "source_relation_identity": "<string>",
  "result_identity": "<string>",
  "requires_canonical_identity_rule": <true|false>,
  "canonical_identity_rule": "<Binding|null>",
  "provenance_bindings": "<Binding[]|null>"
}
```

### 5.4 `source_relation`

Maps to `SRSVALSourceRelation`:

```json
{
  "binding": "<Binding|null>",
  "semantic_binding": "<Binding|null>",
  "applicability_coverage": "<Binding|null>",
  "invalidation_record": "<Binding|null>",
  "invalidation_status": "<none|superseded|invalidated>",
  "identity_rule": "<Binding|null>",
  "status": "<current|superseded|invalidated>"
}
```

### 5.5 `dependency_set` and dependency element

`dependency_set` maps to `SRSVALDependencySet`:

```json
{
  "boundary": "<Binding|null>",
  "dependencies": "<Dependency[]|null>"
}
```

Dependency maps to `SRSVALDependency`:

```json
{
  "binding": "<Binding|null>",
  "role": "<string>",
  "necessity": "<string>",
  "resolution": "<resolved|unresolved>",
  "status": "<current|superseded|invalidated>"
}
```

### 5.6 `result`

Maps to `SRSVALResult`:

```json
{
  "binding": "<Binding|null>",
  "resolution": "<RESOLVED_WITHOUT_RECOMPUTE|unresolved>",
  "interpretability_evidence": "<Binding|null>",
  "status": "<current|superseded|invalidated>"
}
```

### 5.7 `provenance` and `lifecycle`

Both map to `SRSVALProvenanceLifecycle`:

```json
{
  "bindings": "<Binding[]|null>",
  "lifecycle": "<DECLARED_SETTLED|CONTESTED|UNRESOLVED_LIFECYCLE_CONFLICT|INVALIDATED>",
  "boundary": "<Binding|null>"
}
```

### 5.8 `freshness`

`freshness` maps to `SRSVALFreshness`:

```json
{
  "boundary": "<Binding|null>",
  "requirements": "<FreshnessRequirement[]|null>"
}
```

FreshnessRequirement maps to `SRSVALFreshnessRequirement`:

```json
{
  "identity": "<string>",
  "evidence": "<Binding|null>",
  "expected_evidence_digest": "<string>",
  "status": "<current|FRESHNESS_RECHECK_REQUIRED>",
  "valid_until_utc": "<string|null>",
  "observed_at_utc": "<string>"
}
```

### 5.9 `resolution_policy`

Maps to `SRSVALResolutionPolicy`:

```json
{
  "resolution_rule": "<Binding|null>",
  "policies": "<Binding[]|null>",
  "boundary": "<Binding|null>"
}
```

## 6. I1 — exact canonical payload bytes

`I1` uses a new persistence-specific encoding:

```text
encoding_identity = PERSISTENT_SRS_CANONICAL_V1
```

This is not a claim that `SRSVAL-CANONICAL-TEXT-V4` already defines the new
persistent record. It is a complete mapping from the exact I0 JSON schema to
deterministic bytes using RFC 8785 JSON Canonicalization Scheme (JCS).

Rules:

```text
serialize I0 as UTF-8 JSON using RFC 8785;
UTF-8 only; no byte-order mark;
object members are sorted by JCS;
no whitespace is added;
no duplicate member is accepted by parser or writer;
only string, boolean, array, object, and null exist;
there are no numeric values;
null remains null and remains distinct from [];
[] remains an explicit empty array;
unknown, missing, duplicated, or extra fields fail;
string values are compared and stored exactly; no Unicode normalization;
the resulting bytes are I1.
```

Unordered semantic collections are canonicalized before JCS serialization by
sorting elements by the UTF-8 bytes of each element's independent JCS encoding,
ascending bytewise. This applies to:

```text
settled_relation_state.provenance_bindings;
dependency_set.dependencies;
provenance.bindings;
lifecycle.bindings;
freshness.requirements;
resolution_policy.policies.
```

Sorting preserves duplicates and does not remove or merge members. Therefore
reordering is canonical-equivalent, while duplicate-count change is not.

## 7. I2 — payload digest

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

No implementation may select another Decision Core anchor, a test anchor, a
runtime anchor, a configurable anchor, or an additional key. Domain separation is
mandatory: reuse of this public key for the new persistence domain does not permit
cross-domain signature substitution because the domain is part of signed bytes.

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

The envelope uses `PERSISTENT_SRS_ENVELOPE_CANONICAL_V1`. All integers are
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
| 3 | `logical_key_identity` | UTF-8 | I0 logical key identity |
| 4 | `logical_key_version` | UTF-8 | I0 logical key version |
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
invalid. Field labels and values are compared exactly.

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

## 11. Logical key and content identity

```text
logical_record_key = identity + version;

record_content_identity = identity + version + payload_digest_hex;
```

Within one authorized root:

```text
same key + same payload digest + byte-equivalent I1
  = IDEMPOTENT_COMPLETE;

same key + different payload digest
  = PERSISTENT_LOGICAL_KEY_CONFLICT;

different key + same payload digest
  = RECORD_CONTENT_IDENTITY_MISMATCH.
```

The writer must prove exclusive root mutation and complete logical-key scan
before success. If either cannot be proven:

```text
PERSISTENT_CONCURRENT_WRITE_INDETERMINATE
```

and the operation fails closed.

## 12. P0 — exact physical frame

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

Storage key is authorization and addressing metadata, not semantic identity.

## 13. Parser resource limits and safe parsing

All limits are checked before allocation for the corresponding object.

```text
MAX_PAYLOAD_BYTES = 16777216;
MAX_ENVELOPE_BYTES = 1048576;
MAX_TOTAL_BYTES = 17825900;
MAX_FIELD_LABEL_BYTES = 128;
MAX_JSON_DEPTH = 8;
MAX_ARRAY_COUNT = 1000000;
```

Required parser behavior:

```text
use checked integer arithmetic for every offset and sum;
reject any u64 length greater than the applicable maximum;
reject minimum-length failure before reading segments;
reject declared total length not equal to actual file length;
never allocate an object sized only by an unverified length field;
perform bounded reads only;
reject incomplete reads;
reject trailing data after MAGIC_END;
reject invalid UTF-8;
reject JSON depth greater than 8;
reject duplicate JSON members;
reject unknown JSON members;
reject arrays whose declared count exceeds MAX_ARRAY_COUNT or cannot be read;
reject all integer overflow with INTEGER_OVERFLOW;
fail on first violation without repair or fallback.
```

## 14. Read verification order and separated digest checks

A reader must stop at the first failure.

| Order | Check |
| ---: | --- |
| R1 | File length is at least 108 bytes |
| R2 | Start magic and physical version parse and are exact |
| R3 | Payload and envelope lengths are within section 13 limits using checked arithmetic |
| R4 | Declared total length equals actual file length |
| R5 | End magic appears exactly at final 12 bytes |
| R6 | Envelope parses as exactly 13 fields in exact order |
| R7 | Envelope schema, storage version, encoding identity, and completion state are exact |
| R8 | Envelope logical key exactly equals I0 logical key |
| R9 | Canonical payload parses under section 5–6 with exact fields and limits |
| R10a | Physical `payload_digest_raw` equals envelope `payload_digest_hex` after decoding |
| R10b | `SHA256(SIMIGO_PERSISTENT_SRS_PAYLOAD_DIGEST_V1 + 0x00 + I1)` equals that payload digest |
| R10c | Physical trailing `envelope_digest_raw` equals `SHA256(SIMIGO_PERSISTENT_SRS_ENVELOPE_DIGEST_V1 + 0x00 + I4)` |
| R11 | Signature domain and signer exactly equal section 8; Ed25519 signature verifies |
| R12 | Producer authorization reference in envelope exactly equals I0 |
| R13 | Decision Core commit and SHA256 in envelope exactly equal I0 and frozen values |
| R14 | Evidence location satisfies the separately authorized manifest |
| R15 | Logical-key check required by write/audit operation passes |
| R16 | Only after R1–R15: `COMPLETE_VERIFIED` |

Digest failures are one-to-one:

```text
R10a or R10b fails -> PAYLOAD_DIGEST_MISMATCH;
R10c fails         -> ENVELOPE_DIGEST_MISMATCH;
```

No digest check may be used as a substitute for another.

## 15. Write semantics

```text
W1  acquire authorized exclusive writer lock;
W2  scan authorized root for logical key;
W3  reject conflict or indeterminate scan;
W4  construct I0–I5 exactly;
W5  frame P0;
W6  write staging file in the same authorized root;
W7  flush staging file;
W8  atomically rename to records/<payload_digest_hex>.psrs;
W9  flush directory where supported;
W10 reopen final path and execute R1–R15;
W11 confirm logical-key uniqueness;
W12 release lock only after verdict;
W13 report COMPLETE_VERIFIED only after W10–W11 pass.
```

Final records are immutable. Staging data is not a record. Overwrite is
forbidden.

## 16. Failure semantics

| Condition | Result |
| --- | --- |
| Exit before rename | `RECORD_NOT_FOUND`; staging invalid |
| Rename completed but write verdict absent | Reader independently verifies; no inherited verdict |
| Too short | `TRUNCATED_RECORD` |
| Too long or trailing bytes | `TRAILING_DATA_AFTER_RECORD` |
| Magic/version/frame length invalid | `PHYSICAL_LAYOUT_INVALID` |
| Length overflow or over-limit | `INTEGER_OVERFLOW_OR_RESOURCE_LIMIT` |
| Envelope parse/count/order/field error | `NON_CANONICAL_ENVELOPE` |
| Completion state not exact | `COMPLETION_STATE_INVALID` |
| Payload digest R10a/R10b fails | `PAYLOAD_DIGEST_MISMATCH` |
| Envelope digest R10c fails | `ENVELOPE_DIGEST_MISMATCH` |
| Signature/domain/signer fails | `SIGNATURE_VERIFICATION_FAILED` |
| Logical key mismatch | `LOGICAL_KEY_MISMATCH` |
| Same key different content | `PERSISTENT_LOGICAL_KEY_CONFLICT` |
| NIL and explicit empty differ | `CANONICAL_PRESENCE_MISMATCH` |
| Valid unordered reorder | `VALID_CANONICAL_EQUIVALENCE` |
| Duplicate count changes | `CANONICAL_MULTISET_MISMATCH` |
| Unknown schema/version/field | `UNKNOWN_SCHEMA_OR_FIELD` |
| Decision Core binding differs | `DECISION_CORE_BINDING_MISMATCH` |
| Unauthorized location | `EVIDENCE_LOCATION_UNAUTHORIZED` |
| Lock cannot be proven exclusive | `PERSISTENT_CONCURRENT_WRITE_INDETERMINATE` |
| Any check cannot complete | `PERSISTENCE_VERIFICATION_INDETERMINATE`, BLOCK |

`COMPLETE_VERIFIED` is current-read verification only. It is not durability
proof, ES₂ authorization, non-recompute attribution, or production proof.

## 17. Manifest record groups

A future filled instance must bind this contract identity and Human-assigned
integrity binding, request and ruling, requested stages, repository revision,
writable/forbidden paths, implementation and runtime digests, fixture digests,
environment, observer and channel universe, evidence root, writer-lock mechanism,
logical-key mechanism, validation matrix, evidence integrity bindings, and stage
validity boundaries.

Conditional Manifest Instance v0.1 remains non-executable until rebound and
separately authorized.

### 17.1 IMPLEMENTATION candidate scope

Only these paths may be authorized:

```text
simigo2-experimental/Sources/SimiGo2Experimental/PersistentSRSRepresentation.swift;
simigo2-experimental/Tests/SimiGo2ExperimentalTests/PersistentSRSRepresentationTests.swift;
```

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

### 17.2 FIXTURE_PREPARATION candidate scope

Fixtures must separately bind at least valid, reopen, cross-process, digest
payload mutation, envelope digest mutation, signature/domain/signer mutation,
logical-key mismatch, same-key different-content, NIL-to-empty, valid reorder,
duplicate-count change, truncated, trailing-byte, partial, corrupt, unknown
version, unknown/extra field, completion mutation, producer mismatch, core-binding
mismatch, unauthorized location, overflow/resource-limit, and concurrent-writer
cases.

### 17.3 EXECUTION candidate scope

Execution requires exact artifact, environment, observer, evidence-root,
writer-lock, and budget bindings. Candidate default is one run per separately
authorized fixture. Failed runs consume budget; repair/retry requires a new
Human Authorization Record.

## 18. Observer authority

Observer evidence proves process and filesystem operations. Persistence
verification proves byte validity. Neither replaces the other. Persistence PASS
never authorizes ES₂ and never proves non-recompute.

## 19. Stage separation

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

## 20. Adversarial finding matrix

| ID | Attack | Control | Expected result | Evidence source |
| --- | --- | --- | --- | --- |
| PR-A1 | Digest/signature cycle | Sections 4, 7–10 | Construction invalid | Canonical construction evidence |
| PR-A2 | Envelope digest self-inclusion | Sections 9–10 | Invalid envelope | Envelope parser evidence |
| PR-A3 | Path promoted to identity | Sections 5, 12, 14 | Location authorization only | Path/location evidence |
| PR-A4 | Same logical key, changed bytes | Sections 7, 11, 15–16 | `PERSISTENT_LOGICAL_KEY_CONFLICT` | Root scan + writer evidence |
| PR-A5 | Authorized move treated as identity change | Sections 5, 14 | Same identity; unauthorized location separately blocked | Path + verification evidence |
| PR-A6 | Staging accepted as complete | Sections 15–16 | Staging invalid / `RECORD_NOT_FOUND` | Filesystem evidence |
| PR-A7 | Writer verdict reused cross-process | Sections 15–16 | Reader must verify independently | Reader verification evidence |
| PR-A8 | NIL ↔ explicit empty | Sections 5–6, 16 | `CANONICAL_PRESENCE_MISMATCH` | JSON canonical evidence |
| PR-A9 | Reorder confused with duplicate change | Sections 6, 16 | Reorder valid; count change mismatch | Canonical sorting evidence |
| PR-A10 | Lenient unknown-field removal | Sections 5–6, 9, 13 | Unknown field rejected | Parser evidence |
| PR-A11 | Core binding drift + recomputed I5 | Sections 5, 9, 14 | `DECISION_CORE_BINDING_MISMATCH` | Cross-check evidence |
| PR-A12 | Alternate anchor/domain | Section 8, 14 | `SIGNATURE_VERIFICATION_FAILED` | Fixed-anchor evidence |
| PR-A13 | Observer data inserted into payload | Section 5 closed schema | Unknown field rejected | Payload schema evidence |
| PR-A14 | Persistence PASS treated as ES2 | Sections 1, 19 | STOP; separate authorization | Authorization record |
| PR-A15 | PASS treated as non-recompute proof | Sections 1, 18 | Claim invalid | Authorization record |
| PR-A16 | Evidence root created by stage expansion | Sections 1, 17, 19 | STOP; separate authorization | Marker/root absence record |
| PR-A17 | Ambiguous physical frame | Sections 12–13, 16 | Exact frame failure | Physical parser evidence |
| PR-A18 | Bypass same-key conflict | Sections 7, 11, 15 | Conflict or indeterminate | Root scan + lock evidence |
| PR-A19 | Envelope witness tampering + recomputed I5 | Sections 9, 13–14 | Cross-check/fixed-value failure | Envelope evidence |
| PR-A20 | False completion state | Sections 9, 14, 16 | `COMPLETION_STATE_INVALID` unless R1–R15 pass | Reader evidence |
| PR-A21 | Payload and envelope digest conflation | Sections 7, 10, 14 | R10a/R10b and R10c remain independent | Separated digest evidence |
| PR-A22 | Same semantic values, different custom encoding | Sections 5–6 | Non-JCS/extra mapping rejected | JCS parser evidence |
| PR-A23 | Anchor substitution or domain reuse | Section 8, 14 | Exact anchor/domain only | Anchor/domain evidence |
| PR-A24 | Huge length or arithmetic overflow | Sections 12–13, 16 | `INTEGER_OVERFLOW_OR_RESOURCE_LIMIT` | Bounded parser evidence |

Future manifest review must retain and revalidate this matrix.

## 21. Acceptance criteria

```text
C1  seven layers are exact and acyclic;
C2  payload and envelope digests are independently checked;
C3  canonical payload encoding is complete and implementation-independent;
C4  one unique production anchor and domain are frozen;
C5  logical key and content identity are distinct;
C6  same-key different-content is fail-closed;
C7  physical layout and parser limits are exact;
C8  NIL, empty, ordering, duplicates, and unknown fields are closed;
C9  every persistence failure is deterministic and fail-closed;
C10 no stage is authorized by contract acceptance;
C11 ES2 and non-recompute attribution remain excluded;
C12 canonical PALACE and Information Space mutation remain forbidden.
```

## 22. Decision requested

Human is asked to return exactly one:

```text
ACCEPT_PERSISTENT_SRS_MANIFEST_CONTRACT_V1.2
```

or

```text
REVISE_PERSISTENT_SRS_MANIFEST_CONTRACT_V1.2
```

or

```text
REJECT_PERSISTENT_SRS_MANIFEST_CONTRACT_V1.2
```

Acceptance freezes this design and assigns its integrity binding. It does not
authorize implementation, fixture preparation, execution, marker creation,
evidence-root creation, independent ES₂ consumption, non-recompute attribution,
MLX, V6, PALACE, Information Space, or production operation.
