# Persistent SRS Representation Manifest Contract v1.8

> **Status:** SUBMITTED FOR HUMAN DESIGN REVIEW — DESIGN ONLY / NO STAGE AUTHORIZED
> **Date:** 2026-10-11
> **Supersedes:** Manifest Contract v1.7 (`REVISE / SUPERSEDED / NEVER FROZEN`)
> **Binds unchanged I0 JSON Schema v1.6 as the candidate schema**
> **Authorization request:** `SIMIGO_PERSISTENT_SRS_REPRESENTATION_AUTHORIZATION_REQUEST_V0.1_20261011.md`
> **Authorization request SHA256:** `4063787b0680da2ccd872ec949c4602295c8bd5d9d6620f7149ff6caa288c791`
> **Human ruling on v1.7:** `REVISE_PERSISTENT_SRS_MANIFEST_CONTRACT_V1.7`
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
  b1ba532b2fb013d3cabea83748b9ca0d54b095fc;

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
  REVISE / SUPERSEDED / NEVER ACCEPTED OR FROZEN;

Persistence Manifest Contract v1.3 =
  REVISE / SUPERSEDED / NEVER ACCEPTED OR FROZEN;

Persistence Manifest Contract v1.4 =
  REVISE / SUPERSEDED / NEVER ACCEPTED OR FROZEN;

Persistence Manifest Contract v1.5 =
  REVISE / SUPERSEDED / NEVER ACCEPTED OR FROZEN;

Persistence Manifest Contract v1.6 =
  REVISE / SUPERSEDED / NEVER ACCEPTED OR FROZEN;

Persistence Manifest Contract v1.7 =
  REVISE / SUPERSEDED BY V1.8 / NEVER ACCEPTED OR FROZEN.
```

## 3. Contract identity

```text
contract_identity =
  SIMIGO_PERSISTENT_SRS_REPRESENTATION_MANIFEST_CONTRACT_V1.8;

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
PERSISTENT_SRS_RECORD_JSON_SCHEMA_V1.6.json
```

Its SHA256 is:

```text
8e373d27afd9c30f8c5e728d03ac71f2c6784f2ba51c2f3195fabd76d6348b41
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
content digests, including expected freshness evidence digests, are exactly
  64 lowercase hexadecimal characters;
UTC timestamp shape is checked by schema pattern, but calendar validity is
  checked by the independent strict UTC parser defined in section 13;
JSON Schema `format` is an annotation and is never trusted as the sole
  calendar-validity assertion;
arrays never imply set semantics unless sorting is explicitly required below.
```

All Decision Core optional binding properties use `NullableBinding`, which permits
exactly `$defs/Binding` or null. `FreshnessRequirement.valid_until_utc` uses
`NullableUTCTimestamp`, which permits exactly `$defs/UTCTimestamp` or null.
`FreshnessRequirement.observed_at_utc` remains non-nullable and uses
`$defs/UTCTimestamp`. Nullable array fields already use `["array", "null"]`. In
every case the property name must still be present; missing property and present
null are different values.

Nullable wrappers must not reference themselves. A wrapper is valid only when its
non-null branch references the corresponding base definition.

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

Identity comparison uses ordered tuples, not concatenated strings. Every string
component is reduced to its exact UTF-8 byte sequence before comparison or
ordering. Swift implementations must compare those UTF-8 byte arrays; they must
not rely on `String ==`, because Swift may treat Unicode canonical-equivalent
strings as equal even when their UTF-8 representations differ.

```text
logical_record_key =
  (identity_utf8: [UInt8], version_utf8: [UInt8]);

record_content_identity =
  (
    identity_utf8: [UInt8],
    version_utf8: [UInt8],
    payload_digest_bytes: [UInt8]
  ).
```

Comparison rules:

```text
compare identity exactly by UTF-8 bytes;
compare version exactly by UTF-8 bytes;
do not concatenate identity and version;
do not use a delimiter;
do not apply Unicode normalization;
do not use case folding;
do not use grapheme or canonical equivalence;
precomposed and decomposed forms are different identities when their UTF-8
  bytes differ.
```

Unordered-collection sorting also compares the UTF-8 bytes of each element's
independent JCS serialization.

If a textual witness is required for diagnostics, it is only:

```text
JCS(["identity", "version"])
JCS(["identity", "version", "payload_digest_hex"])
```

and is not used as the definition of identity.

Within one authorized root, write classification must inspect both the proposed
content-addressed path and all final records for the ordered logical key. The
proposed content-addressed path is:

```text
records/<payload_digest_hex>.psrs
```

If that path exists, the candidate bytes at that path must be classified before
any staging, rename, or overwrite. An untrusted or malformed existing object is
never treated as absent or ignorable.

```text
If the proposed content-addressed path is present:
  execute reader checks R1–R28 on that exact path;
  if any check fails, return that exact failure status;
  extract only the now-verified logical_record_key;
  if its logical key differs from the proposed ordered logical key:
    return RECORD_CONTENT_IDENTITY_MISMATCH;
    do not stage, rename, overwrite, delete, or retry as NEW_RECORD;
  if its logical key equals the proposed key:
    compare the existing I1 bytes with the proposed I1 bytes.
    byte-equivalent I1 -> classify as EXISTING_EQUIVALENT_RECORD;
    different I1 bytes, even with the same payload digest ->
      classify as PERSISTENT_LOGICAL_KEY_CONFLICT;
    this collision terminates immediately: do not scan for a substitute result,
      do not stage, rename, overwrite, delete, retry as NEW_RECORD, or use an
      alternate filename.

Then scan all other final records for the proposed logical_record_key:

If no record has the logical key and the proposed content path is absent:
  classify as NEW_RECORD.

If one existing physical record has the logical key:
  compare its exact I1 bytes and payload digest with the proposed record.
  same bytes/digest -> EXISTING_EQUIVALENT_RECORD;
  different bytes/digest -> PERSISTENT_LOGICAL_KEY_CONFLICT.

If more than one physical record has the logical key:
  classify as PERSISTENT_DUPLICATE_RECORD_STATE and fail closed.

If the proposed content path has a different logical key:
  classify as RECORD_CONTENT_IDENTITY_MISMATCH and fail closed.

If the scan cannot prove completeness or exclusivity:
  classify as PERSISTENT_CONCURRENT_WRITE_INDETERMINATE and fail closed.
```

A content-addressed SHA-256 collision is not retried as `NEW_RECORD`. The exact
target path is authoritative for collision classification; no rename may replace
its bytes.


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
| R6 | Declared total length is not greater than actual file length | `PHYSICAL_LENGTH_MISMATCH` |
| R7 | End magic at the declared final offset is exact | `MAGIC_END_MISMATCH` |
| R8 | Actual file length exactly equals declared total length | `TRAILING_DATA_AFTER_RECORD` |
| R9 | Envelope is exactly 13 ordered fields | `NON_CANONICAL_ENVELOPE` |
| R10 | Envelope schema is exact | `UNKNOWN_ENVELOPE_SCHEMA` |
| R11 | Storage format version is exact | `UNKNOWN_STORAGE_FORMAT_VERSION` |
| R12 | Envelope encoding identity is exact | `ENCODING_IDENTITY_MISMATCH` |
| R13 | Completion state is exactly `COMPLETE` | `COMPLETION_STATE_INVALID` |
| R14 | Envelope logical key UTF-8 tuple equals I0 logical key UTF-8 tuple | `ENVELOPE_LOGICAL_KEY_MISMATCH` |
| R15 | Payload is valid UTF-8 and within limit | `INVALID_JSON_UTF8` / `INTEGER_OVERFLOW_OR_RESOURCE_LIMIT` |
| R16 | Payload parses as one JSON value with valid syntax | `INVALID_JSON_SYNTAX` |
| R17 | JSON depth, duplicate/unknown/missing members, types, and array limits pass | `JSON_DEPTH_LIMIT_EXCEEDED` / `DUPLICATE_JSON_MEMBER` / `UNKNOWN_SCHEMA_OR_FIELD` / `INTEGER_OVERFLOW_OR_RESOURCE_LIMIT` |
| R18 | Payload schema ID and encoding identity are exact | `UNKNOWN_PAYLOAD_SCHEMA` / `ENCODING_IDENTITY_MISMATCH` |
| R19 | Payload validates against the frozen closed JSON Schema | `SCHEMA_VALIDATION_FAILED` |
| R20 | Every UTC timestamp passes the independent strict UTC parser | `INVALID_UTC_TIMESTAMP` |
| R21 | Sort semantic unordered collections, re-serialize with RFC 8785, and require byte equality with original I1 | `NON_CANONICAL_PAYLOAD_BYTES` |
| R22 | Header payload digest equals envelope payload digest | `PAYLOAD_DIGEST_MISMATCH` |
| R23 | Recomputed payload digest equals that payload digest | `PAYLOAD_DIGEST_MISMATCH` |
| R24 | Trailing envelope digest equals recomputed envelope digest | `ENVELOPE_DIGEST_MISMATCH` |
| R25 | Signature domain/signer are exact and Ed25519 signature verifies | `SIGNATURE_VERIFICATION_FAILED` |
| R26 | Envelope producer reference equals I0 | `PRODUCER_AUTHORIZATION_REFERENCE_MISMATCH` |
| R27 | Decision Core commit and SHA256 equal I0 and frozen values | `DECISION_CORE_BINDING_MISMATCH` |
| R28 | Evidence location is authorized | `EVIDENCE_LOCATION_UNAUTHORIZED` |
| R29 | Ordered logical-key uniqueness scan passes | `PERSISTENT_LOGICAL_KEY_CONFLICT` / `RECORD_CONTENT_IDENTITY_MISMATCH` / `PERSISTENT_DUPLICATE_RECORD_STATE` / `PERSISTENT_CONCURRENT_WRITE_INDETERMINATE` |
| R30 | Only after R1–R29 | `COMPLETE_VERIFIED` |

### 13.2 Trailing-data ordering

R6 intentionally checks only that the declared total is not longer than the
actual file, so all declared bytes can be read. R7 checks the end magic at the
declared final offset. R8 then checks for excess bytes. Therefore ordinary
append-after-end reaches:

```text
R8 -> TRAILING_DATA_AFTER_RECORD
```

A short or impossible-to-frame record reaches R6:

```text
R6 -> PHYSICAL_LENGTH_MISMATCH
```

If bytes at the declared end offset have also been corrupted, R7 returns
`MAGIC_END_MISMATCH` before R8.

### 13.3 Canonical byte consistency check

R21 is mandatory and independent of schema validation, digest verification, and
signature verification. The reader must:

```text
take the JSON value parsed from I1;
for each listed unordered collection, if present and non-null, sort elements by
  the UTF-8 bytes of each element's independent RFC 8785 serialization,
  preserving duplicates;
serialize the complete resulting root with RFC 8785;
compare the resulting bytes byte-for-byte with the original I1.
```

If any byte differs, return:

```text
NON_CANONICAL_PAYLOAD_BYTES
```

A semantically equivalent but noncanonical encoding is rejected before digest or
signature checks.

### 13.4 Strict UTC timestamp parser

JSON Schema `format: date-time` is an annotation only. Each UTC string must also
pass an independent parser with:

```text
exact syntax YYYY-MM-DDTHH:MM:SS[.fraction]Z;
year 0001 through 9999;
month 01 through 12;
day valid for the month and Gregorian leap year;
hour 00 through 23;
minute 00 through 59;
second 00 through 59;
one or more fractional digits only when a decimal point is present;
offset exactly Z;
no leap second 60;
no whitespace;
no offset such as +00:00;
no Unicode normalization.
```

Failure returns:

```text
INVALID_UTC_TIMESTAMP
```

### 13.5 Failure status registry

The registry is closed. Synonyms and aliases are forbidden:

```text
TRUNCATED_RECORD;
MAGIC_START_MISMATCH;
UNKNOWN_PHYSICAL_FORMAT_VERSION;
INTEGER_OVERFLOW_OR_RESOURCE_LIMIT;
PHYSICAL_LENGTH_MISMATCH;
MAGIC_END_MISMATCH;
TRAILING_DATA_AFTER_RECORD;
NON_CANONICAL_ENVELOPE;
UNKNOWN_ENVELOPE_SCHEMA;
UNKNOWN_STORAGE_FORMAT_VERSION;
ENCODING_IDENTITY_MISMATCH;
COMPLETION_STATE_INVALID;
ENVELOPE_LOGICAL_KEY_MISMATCH;
INVALID_JSON_UTF8;
INVALID_JSON_SYNTAX;
JSON_DEPTH_LIMIT_EXCEEDED;
DUPLICATE_JSON_MEMBER;
UNKNOWN_SCHEMA_OR_FIELD;
SCHEMA_VALIDATION_FAILED;
UNKNOWN_PAYLOAD_SCHEMA;
INVALID_UTC_TIMESTAMP;
NON_CANONICAL_PAYLOAD_BYTES;
PAYLOAD_DIGEST_MISMATCH;
ENVELOPE_DIGEST_MISMATCH;
SIGNATURE_VERIFICATION_FAILED;
PRODUCER_AUTHORIZATION_REFERENCE_MISMATCH;
DECISION_CORE_BINDING_MISMATCH;
EVIDENCE_LOCATION_UNAUTHORIZED;
PERSISTENT_LOGICAL_KEY_CONFLICT;
RECORD_CONTENT_IDENTITY_MISMATCH;
PERSISTENT_DUPLICATE_RECORD_STATE;
PERSISTENT_CONCURRENT_WRITE_INDETERMINATE;
CANONICAL_PRESENCE_MISMATCH;
CANONICAL_MULTISET_MISMATCH;
RECORD_NOT_FOUND;
PERSISTENCE_VERIFICATION_INDETERMINATE.
```

`VALID_CANONICAL_EQUIVALENCE` is a comparison outcome for a valid reordered
unordered collection, not a failure status.

`COMPLETE_VERIFIED` is the only successful read-verification verdict.
`IDEMPOTENT_COMPLETE` is the only successful write verdict for an already-present
equivalent record; it requires prior `COMPLETE_VERIFIED` and R29.

If a check cannot be executed, return
`PERSISTENCE_VERIFICATION_INDETERMINATE` and BLOCK.

## 14. Write semantics and idempotent branch

The write operation first classifies the ordered logical key and the proposed
content-addressed path. It must never overwrite an existing final record.

```text
W1  acquire authorized exclusive writer lock;
W2  compute the proposed content-addressed path and scan all final records using
      ordered logical_record_key UTF-8 tuples;
W3  inspect an existing proposed content path if present, execute R1–R28 on its
      exact bytes for classification, and classify exactly one of:
      NEW_RECORD;
      EXISTING_EQUIVALENT_RECORD;
      RECORD_CONTENT_IDENTITY_MISMATCH;
      PERSISTENT_LOGICAL_KEY_CONFLICT;
      PERSISTENT_DUPLICATE_RECORD_STATE;
      PERSISTENT_CONCURRENT_WRITE_INDETERMINATE.
```

### 14.1 Existing equivalent record

If W3 returns `EXISTING_EQUIVALENT_RECORD`, the writer must not construct a new
staging file, rename over the existing path, delete the existing path, or create
a second copy. It must:

```text
W4  identify the sole existing physical record;
W5  execute reader checks R1–R28 on that exact existing path;
W6  execute ordered logical-key uniqueness check R29;
W7  derive COMPLETE_VERIFIED only if W5 passes R1–R28 and W6 passes R29;
W8  release the writer lock only after the verdict;
W9  return IDEMPOTENT_COMPLETE only if W7 and W8 pass.
```

No `COMPLETE_VERIFIED` verdict may be produced at W5, before R29 passes. If any
existing-record check fails, return that exact reader failure status and do not
overwrite or repair the record.

`COMPLETE_VERIFIED` is the successful result of read verification. It applies to
bytes checked by R1–R29. `IDEMPOTENT_COMPLETE` is the successful write-operation
outcome for an already-present equivalent record. `IDEMPOTENT_COMPLETE` may be
returned only after the existing record has achieved `COMPLETE_VERIFIED` through
R30 and R29 has passed. It never means that a new file was written, an invalid
record was repaired, or another record may be overwritten.

### 14.2 Content-addressed collision

If W3 returns `RECORD_CONTENT_IDENTITY_MISMATCH`, the writer must stop. It must
not retry as `NEW_RECORD`, stage a candidate, rename over the existing path,
delete it, or use an alternate filename. The exact existing record remains
immutable and the failure status is final for this write attempt.

If W3 returns `PERSISTENT_LOGICAL_KEY_CONFLICT` because the proposed path passed
R1–R28, has the same ordered logical key, but has different I1 bytes under the
same payload digest, the writer must also stop. It must not retry as
`NEW_RECORD`, stage a candidate, rename over the existing path, delete it, or use
an alternate filename. The exact existing record remains immutable and this
logical-key conflict is final for this write attempt.

### 14.3 New record path

Only if W3 returns `NEW_RECORD`, continue:

```text
W7  construct I0–I5 exactly;
W8  frame P0;
W9  write staging file in the same authorized root;
W10 flush staging file;
W11 atomically rename to records/<payload_digest_hex>.psrs;
W12 flush directory where supported;
W13 reopen final path and execute R1–R28;
W14 execute ordered logical-key uniqueness check R29;
W15 derive COMPLETE_VERIFIED only if W13 passes R1–R28 and W14 passes R29;
W16 release lock only after the verdict.
```

Final records are immutable. Staging files are not records. Overwrite is
forbidden. If the target path appears after W3, stop and repeat classification
under the same exclusive lock; never rename over it.

## 15. Persistence failure semantics

| Condition | Exact status |
| --- | --- |
| File shorter than 108 bytes | `TRUNCATED_RECORD` |
| Start magic differs | `MAGIC_START_MISMATCH` |
| Physical version differs | `UNKNOWN_PHYSICAL_FORMAT_VERSION` |
| Length parse/limit/arithmetic fails | `INTEGER_OVERFLOW_OR_RESOURCE_LIMIT` |
| Declared total exceeds actual length | `PHYSICAL_LENGTH_MISMATCH` |
| End magic differs at declared offset | `MAGIC_END_MISMATCH` |
| Actual length exceeds declared total | `TRAILING_DATA_AFTER_RECORD` |
| Envelope field structure differs | `NON_CANONICAL_ENVELOPE` |
| Envelope schema differs | `UNKNOWN_ENVELOPE_SCHEMA` |
| Storage format differs | `UNKNOWN_STORAGE_FORMAT_VERSION` |
| Encoding identity differs | `ENCODING_IDENTITY_MISMATCH` |
| Completion state differs | `COMPLETION_STATE_INVALID` |
| Envelope logical key differs | `ENVELOPE_LOGICAL_KEY_MISMATCH` |
| Payload UTF-8 invalid | `INVALID_JSON_UTF8` |
| Payload JSON syntax invalid | `INVALID_JSON_SYNTAX` |
| JSON depth/member/type/schema violation | `JSON_DEPTH_LIMIT_EXCEEDED` / `DUPLICATE_JSON_MEMBER` / `UNKNOWN_SCHEMA_OR_FIELD` / `SCHEMA_VALIDATION_FAILED` / `INTEGER_OVERFLOW_OR_RESOURCE_LIMIT` |
| Payload schema differs | `UNKNOWN_PAYLOAD_SCHEMA` |
| Expected freshness digest is not Hex64 | `SCHEMA_VALIDATION_FAILED` |
| Payload digest R22/R23 fails | `PAYLOAD_DIGEST_MISMATCH` |
| Envelope digest R24 fails | `ENVELOPE_DIGEST_MISMATCH` |
| Signature/domain/signer fails | `SIGNATURE_VERIFICATION_FAILED` |
| Producer reference differs | `PRODUCER_AUTHORIZATION_REFERENCE_MISMATCH` |
| Decision Core binding differs | `DECISION_CORE_BINDING_MISMATCH` |
| Evidence location differs | `EVIDENCE_LOCATION_UNAUTHORIZED` |
| Same ordered logical key, different content | `PERSISTENT_LOGICAL_KEY_CONFLICT` |
| Different logical key at the proposed content-addressed path, same payload digest | `RECORD_CONTENT_IDENTITY_MISMATCH` |
| Different logical key, same content | `RECORD_CONTENT_IDENTITY_MISMATCH` |
| Multiple records for one logical key | `PERSISTENT_DUPLICATE_RECORD_STATE` |
| NIL becomes explicit empty, or reverse | `CANONICAL_PRESENCE_MISMATCH` |
| Valid unordered reorder | `VALID_CANONICAL_EQUIVALENCE` |
| Duplicate count changes | `CANONICAL_MULTISET_MISMATCH` |
| Lock cannot be proven exclusive | `PERSISTENT_CONCURRENT_WRITE_INDETERMINATE` |
| Any check cannot execute | `PERSISTENCE_VERIFICATION_INDETERMINATE` |

`INTEGER_OVERFLOW` is not a valid alias. The only resource/overflow status is
`INTEGER_OVERFLOW_OR_RESOURCE_LIMIT`.

`IDEMPOTENT_COMPLETE` is not an alias of `COMPLETE_VERIFIED`. It is the write
result for an existing equivalent record after that record independently reached
`COMPLETE_VERIFIED` and logical-key uniqueness R29 passed.

## 16. Manifest record groups

A future filled instance must bind this contract identity and Human-assigned
integrity binding, request and ruling, requested stages, repository revision,
writable/forbidden paths, implementation and runtime digests, JSON Schema digest,
fixture digests, environment, observer and channel universe, evidence root,
writer-lock mechanism, ordered-key scan, content-addressed collision, and idempotent-readback mechanism,
validation matrix, evidence integrity bindings, and stage validity boundaries.

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
valid reorder, duplicate-count change, truncated, short-frame, trailing-byte,
partial, corrupt, unknown physical version, unknown envelope schema, unknown
storage version, unknown payload schema, unknown/extra field, completion mutation,
producer mismatch, core-binding mismatch, unauthorized location,
overflow/resource-limit, invalid JSON syntax, invalid UTC calendar,
concurrent-writer, idempotent existing-record, and content-addressed collision cases.

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
| PR-A13 | Observer data inserted into payload | Normative external schema closed object | `UNKNOWN_SCHEMA_OR_FIELD` | Schema evidence |
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
| PR-A29 | Nullable Binding/UTC omitted or wrong type | Section 5, normative schema | Property must exist; object/string/null distinction enforced | JSON Schema validation evidence |
| PR-A30 | Semantically equivalent noncanonical payload bytes | Sections 6, 13 | `NON_CANONICAL_PAYLOAD_BYTES` | Canonical re-serialization evidence |
| PR-A31 | Invalid calendar date accepted via format annotation | Sections 5, 13 | `INVALID_UTC_TIMESTAMP` | Strict UTC parser evidence |
| PR-A32 | Unicode canonical-equivalent identities merged | Section 7 | UTF-8 byte tuples remain distinct | UTF-8 comparison evidence |
| PR-A33 | Nullable wrapper references itself | Section 5, normative schema | Wrapper non-null branch must reference Binding or UTCTimestamp; recursion fails review | JSON Schema inspection/validation evidence |
| PR-A34 | Write reports success after omitting required reader checks | Sections 13–15 | The applicable write branch must execute every required reader check before success | Write verification and lock evidence |
| PR-A35 | Invalid expected freshness digest accepted as nonempty string | Sections 5–6, normative schema | `FreshnessRequirement.expected_evidence_digest` must be Hex64 | JSON Schema validation evidence |
| PR-A36 | Invalid JSON syntax classified as schema/resource failure | Sections 13, 15 | Unique `INVALID_JSON_SYNTAX` before schema validation | JSON parser evidence |
| PR-A37 | Appended bytes remain unclassified due to exact-length order | Sections 11–13, 15 | Short frame returns `PHYSICAL_LENGTH_MISMATCH`; excess returns `TRAILING_DATA_AFTER_RECORD` | Physical parser evidence |
| PR-A38 | Existing equivalent record overwritten or accepted without verification | Sections 7, 14–16 | Existing path receives R1–R29; no staging/rename/overwrite; then `IDEMPOTENT_COMPLETE` | Root scan, reader, and lock evidence |
| PR-A39 | Idempotent path reports COMPLETE_VERIFIED before R29 | Sections 7, 13–15 | R1–R28 and R29 must both pass before COMPLETE_VERIFIED; then IDEMPOTENT_COMPLETE | Idempotent reader and uniqueness evidence |
| PR-A40 | Content-addressed collision retried as NEW_RECORD or loops | Sections 7, 14–16 | Different logical key stops as RECORD_CONTENT_IDENTITY_MISMATCH with no staging/rename/retry | Collision path, reader, and lock evidence |
| PR-A41 | Same-key, same-digest, different-I1 content-address collision | Sections 7, 14–16 | Immediately stops as PERSISTENT_LOGICAL_KEY_CONFLICT with no staging/rename/overwrite/delete/retry | Collision path, reader, and lock evidence |

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
C12 canonical PALACE and Information Space mutation remain forbidden;
C13 nullable fields preserve missing/null/object distinctions;
C14 canonical payload bytes are re-serialization checked;
C15 UTC validity does not rely on JSON Schema format assertion;
C16 identity strings compare by exact UTF-8 bytes;
C17 nullable wrappers reference their non-null base definitions;
C18 the write success path executes every read check required for its branch;
C19 expected freshness evidence digest is Hex64;
C20 invalid JSON syntax has one closed status;
C21 trailing data is reachable and deterministically classified;
C22 idempotent existing records are verified and never overwritten;
C23 COMPLETE_VERIFIED requires R1–R29 in every branch;
C24 content-addressed collisions are final and non-retriable;
C25 same-key, same-digest, different-I1 collisions are logical-key conflicts.
```

## 21. Decision requested

Human is asked to return exactly one:

```text
ACCEPT_PERSISTENT_SRS_MANIFEST_CONTRACT_V1.8
```

or

```text
REVISE_PERSISTENT_SRS_MANIFEST_CONTRACT_V1.8
```

or

```text
REJECT_PERSISTENT_SRS_MANIFEST_CONTRACT_V1.8
```

Acceptance freezes this design and assigns its integrity binding. It does not
authorize implementation, fixture preparation, execution, marker creation,
evidence-root creation, independent ES₂ consumption, non-recompute attribution,
MLX, V6, PALACE, Information Space, or production operation.
