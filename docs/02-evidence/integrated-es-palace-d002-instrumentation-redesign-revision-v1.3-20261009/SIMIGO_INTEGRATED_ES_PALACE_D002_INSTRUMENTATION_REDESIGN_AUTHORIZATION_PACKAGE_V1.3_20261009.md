# D-002 Replay-Adapter Instrumentation / Redesign Authorization Package v1.3

> **Status:** REVISED FOR HUMAN REVIEW — DESIGN ONLY
> **Date:** 2026-10-09
> **Package ID:** `INTEGRATED-ES-PALACE-D002-INSTRUMENTATION-REDESIGN-AUTH-PACKAGE-V1.3`
> **Supersedes:** v1.2 = REVISE / retained immutable
> **Canonical base:** `a89b980011ce37f347a2e89ccbf1af0e2a64c631`
> **implementation:** NOT AUTHORIZED
> **dry materialization:** NOT AUTHORIZED
> **validation execution:** NOT AUTHORIZED
> **D-002 rerun / repair-run / new campaign:** NOT AUTHORIZED
> **D-001 decide() / observer execution:** NOT AUTHORIZED
> **D-001 handoff:** NOT AUTHORIZED
> **canonical / PALACE mutation:** NOT AUTHORIZED
> **evidence overwrite:** FORBIDDEN

## 0. Revision purpose

v1.3 preserves accepted v1.2 boundaries and closes four remaining contract gaps:

```text
R1 unique S8/S9 materialization and validation order;
R2 complete StageRecord schema and chain constraints;
R3 complete RAW_EXCEPTION_PAYLOAD / NORMALIZED_EXCEPTION closure;
R4 complete and unique preflight rejection enum.
```

## 1. Accepted v1.2 boundaries carried forward unchanged

```text
LANE H = historical static audit;
LANE F = future active failure capture;
LANE D = future D001 handoff, separately authorized.

S13 = HISTORICAL_FALLBACK_STATIC_AUDIT;
      never decision_replay.py::replay;
      never D001 decide().

EXPECTED vectors = comparator-only.
map_fixtures = NON_CAUSAL_AUXILIARY_MAPPING_RECORD_PATH.

S2 = source_snapshot.py::verify_existing only.
snapshot creation/replacement/deletion = out of scope.

source selection field = embedding_metadata.id;
retained order = 1,2,3,4,5,6,7;
fixture regeneration = forbidden.

D001 core mutation = forbidden.
```

## 2. R1 — unique stage order and I6 closure

### 2.1 Active case order

The active causal stages are exactly:

```text
S0 BASELINE_VERIFICATION
S1 RETAINED_SOURCE_SELECTION_AUDIT
S2 SEALED_SNAPSHOT_VERIFICATION
S3 PRIMITIVE_INVENTORY_AUDIT
S4 FIXTURE_REPRESENTATION_AUDIT
S5 AUXILIARY_MAPPING_RECORD_AUDIT
S6 NON_INVOCATION_WRAPPER_TRANSLATION
S7 CLOSURE_DIGEST_MATERIALIZATION
S8 NON_INVOCATION_D001_EXACT_FIELD_PREFLIGHT
S9 INVOCATION_MATERIALIZATION_AND_FINAL_PREFLIGHT
S10 RESOLVED_INPUT_ASSEMBLY
S11 RESOLVED_INPUT_ASSOCIATION_AUDIT
S12 D001_HANDOFF_REQUEST_PREPARATION
STOP — pending separate Human authorization
```

S13 is not an active case stage. It is a campaign-level historical static audit
record.

### 2.2 S6 output boundary

S6 translates and finalizes:

```text
I1 closure structure without closure_digest;
I3 carrier candidate;
I4 provenance candidate;
I5 action candidates;
I8 schema-candidate;
I10 evidence-destination candidate.
```

S6 may inspect the retained invocation source but must not emit a final D001 I6
candidate. It emits only:

```text
I6_INTERMEDIATE_SOURCE_VIEW
```

with:

```text
source_invocation_reference;
source_field_presence;
source_value_digests;
manifest_binding_reference.
```

No D001 I6 schema ID is attached at S6.

### 2.3 S8 scope

S8 validates only finalized non-invocation candidates:

```text
I1 after S7 closure digest materialization;
I3;
I4;
I5;
I8;
I10.
```

S8 must reject the case if `I6_INTERMEDIATE_SOURCE_VIEW` is absent, but must not
validate I6 as a final D001 wrapper.

### 2.4 S9 ordered subphases

S9 is one stage with two mandatory ordered subphases:

```text
S9M INVOCATION_MATERIALIZATION
  inputs:
    I6_INTERMEDIATE_SOURCE_VIEW;
    run manifest package_binding/package_id;
    manifest_instance_id;
    schema_version;
  output:
    final D001 I6 candidate.

S9P INVOCATION_FINAL_D001_EXACT_FIELD_PREFLIGHT
  input:
    final D001 I6 candidate only;
  profile:
    D001_EXACT_FIELD_PREFLIGHT_PROFILE_INVOCATION_FINAL;
  result:
    PASS or first-fault rejection.
```

S9 PASS requires both:

```text
S9M = PASS;
S9P = PASS.
```

No second materialization follows S9P.

### 2.5 S10/S11 boundary

S10 assembles the resolved input only from:

```text
final I1;
final I3;
final I4;
final I5;
final I6;
final I8;
final I10.
```

S11 audits associations and completeness. It does not repeat the D001 exact-field
preflight and cannot repair S8/S9 rejections.

## 3. R2 — complete StageRecord schema

### 3.1 Applicability

One StageRecord is mandatory for each case for each active stage S0–S12.

S13 uses a separate `HISTORICAL_FALLBACK_AUDIT_RECORD`; it is not a StageRecord.

`SKIPPED` is not a valid active-stage status. Every S0–S12 stage must be run or
the case fails before that stage.

### 3.2 Canonical record layering

Each StageRecord has three layers:

```text
StageRecordCore      — semantic and audit fields;
StageRecordDigest    — SHA-256 of canonical StageRecordCore;
StageRecordFull      — Core + stage_record_digest + chain fields.
```

`FailureCapture` references `stage_core_digest`, never the later full
`stage_record_digest`, avoiding circular binding.

### 3.3 StageRecordCore

Required for every stage:

| Field | Type / constraint |
| --- | --- |
| `schema_id` | constant `D002-ADAPTER-STAGE-RECORD-V3` |
| `trace_id` | nonempty UUIDv4 |
| `case_id` | one of seven frozen case IDs |
| `source_embedding_metadata_id` | integer 1..7 matching frozen case |
| `stage_id` | `S0`..`S12` |
| `stage_sequence` | integer 0..12, equal to numeric suffix of `stage_id` |
| `status` | `PASS` or `FAIL` |
| `started_at_utc` | RFC 3339 UTC with Z |
| `finished_at_utc` | RFC 3339 UTC with Z, not before start |
| `input_schema_id` | nonempty string or null for S0 |
| `input_object_digests` | object; values lowercase SHA-256 |
| `output_schema_id` | nonempty string or null for terminal S12 |
| `output_object_digests` | object; values lowercase SHA-256 |
| `expected_vector_used` | constant false |
| `d001_executed` | constant false |
| `observer_executed` | constant false |
| `semantic_decision_attempted` | constant false |
| `d001_core_sha256_set` | object of five path-to-SHA256 entries |
| `d002_implementation_sha256_set` | object of audited implementation hashes |
| `stage_profile` | exact profile string from Section 6 |

Required if `status = PASS`:

| Field | Constraint |
| --- | --- |
| `failure_class` | null |
| `failure_capture_digest` | null |
| `next_action` | `ADVANCE`, except S12 = `STOP_PENDING_SEPARATE_AUTHORIZATION` |

Required if `status = FAIL`:

| Field | Constraint |
| --- | --- |
| `failure_class` | nonempty registered class from Section 8 |
| `failure_capture_digest` | lowercase SHA-256 of FailureCapture |
| `next_action` | `CASE_TERMINATED` |

Unknown fields are invalid.

### 3.4 Stage profiles

| Stage | `stage_profile` |
| --- | --- |
| S0 | `BASELINE` |
| S1 | `RETAINED_SELECTION` |
| S2 | `SEALED_SNAPSHOT` |
| S3 | `PRIMITIVE_INVENTORY` |
| S4 | `FIXTURE_REPRESENTATION` |
| S5 | `NON_CAUSAL_AUXILIARY_MAPPING` |
| S6 | `NON_INVOCATION_WRAPPER_TRANSLATION` |
| S7 | `CLOSURE_DIGEST_MATERIALIZATION` |
| S8 | `NON_INVOCATION_D001_EXACT_FIELD_PREFLIGHT` |
| S9 | `INVOCATION_MATERIALIZATION_AND_FINAL_PREFLIGHT` |
| S10 | `RESOLVED_INPUT_ASSEMBLY` |
| S11 | `RESOLVED_INPUT_ASSOCIATION_AUDIT` |
| S12 | `D001_HANDOFF_REQUEST_PREPARATION` |

### 3.5 StageRecordFull

`StageRecordFull` contains all Core fields plus:

| Field | Constraint |
| --- | --- |
| `stage_record_digest` | SHA-256 of canonical StageRecordCore |
| `previous_stage_record_digest` | null for S0; otherwise prior full record digest |
| `previous_chain_digest` | null for S0; otherwise prior `trace_chain_digest_after_stage` |
| `trace_chain_digest_after_stage` | deterministic chain digest from Section 5 |

### 3.6 Sequence and chain rules

```text
one independent chain per case_id;
stage_sequence starts at 0 for S0;
stage_sequence increases by exactly 1;
stage_id suffix must equal stage_sequence;
duplicate or missing sequence is invalid;
S0 previous_stage_record_digest = null;
S0 previous_chain_digest = null;
for N>0, previous links must equal Stage N-1 full record and chain values;
chains are never shared across cases;
chain divergence is terminal INVALID.
```

No chain may include S13.

### 3.7 FailureCapture association

For `status = FAIL`:

```text
1 construct StageRecordCore with status FAIL;
2 compute stage_core_digest = SHA256(canonical StageRecordCore);
3 emit FailureCapture containing stage_core_digest;
4 attach failure_capture_digest to a copied Core;
5 compute full StageRecord digest;
6 update chain after stage and after FailureCapture;
7 terminate case.
```

The pair is valid only if:

```text
FailureCapture.stage_core_digest == SHA256(StageRecordCore);
StageRecord.status = FAIL;
FailureCapture.next_action = CASE_TERMINATED;
both records exist and are write-once.
```

No duplicate FailureCapture is allowed for the same failing StageRecord.

## 4. R3 — exception evidence contracts

### 4.1 Two mandatory object classes

When an adapter exception is thrown, the failing stage must preserve two
independent write-once objects:

```text
RAW_EXCEPTION_PAYLOAD;
NORMALIZED_EXCEPTION.
```

When no exception is thrown, both are absent and FailureCapture records:

```text
exception_evidence_state = NO_EXCEPTION_THROWN.
```

Schema rejection and digest mismatch do not require a synthetic exception.

### 4.2 RAW_EXCEPTION_PAYLOAD

If exact caught diagnostic bytes exist, RAW preserves those exact bytes:

```text
capture_kind = EXACT_CAUGHT_BYTES.
```

If no byte stream exists, RAW is the first-lossless canonical serialization made
at the catch boundary:

```text
capture_kind = CAPTURE_TIME_LOSSLESS_SERIALIZATION;
capture_codec = D002-ADAPTER-EXCEPTION-CAPTURE-V1.
```

RAW must never be a post-audit reconstruction.

RAW metadata:

```text
schema_id = D002-RAW-EXCEPTION-PAYLOAD-V1;
exception_pair_id;
trace_id;
case_id;
stage_id;
stage_sequence;
capture_kind;
raw_byte_size;
raw_sha256;
encoding = UTF-8 | BINARY;
line_ending = LF | CRLF | MIXED | NONE;
exception_class;
caught_at_utc;
unredacted=true.
```

Path rule:

```text
RAW_EXCEPTION_PAYLOAD/<case_id>/<stage_id>/<exception_pair_id>.raw.payload
```

### 4.3 NORMALIZED_EXCEPTION

Normalized is derived only from RAW. It is not a substitute for RAW.

Path rule:

```text
NORMALIZED_EXCEPTION/<case_id>/<stage_id>/<exception_pair_id>.normalized.json
```

Required fields:

```text
schema_id = D002-NORMALIZED-EXCEPTION-V1;
exception_pair_id;
trace_id;
case_id;
stage_id;
stage_sequence;
raw_payload_sha256;
raw_payload_byte_size;
raw_capture_kind;
exception_class;
exception_message_normalized;
exception_message_normalized_sha256;
original_message_byte_size;
original_message_sha256;
stack_frame_digests[];
redaction_pattern_set_id;
redaction_pattern_set_sha256;
redaction_application_order[];
unredacted=false;
semantic_interpretation=null;
semantic_decision=null.
```

### 4.4 Redaction contract

Redaction applies only after RAW is sealed and only to parsed string values. Key
names, array order, object structure, numeric fields, and digest fields are not
rewritten.

Fixed replacement order:

```text
1 absolute repository prefix → `<REPO>`;
2 user home prefix → `<USER>`;
3 each bound secret pattern, in version order → `<REDACTED_SECRET:pattern_index>`;
4 absolute temporary prefix → `<TMP>`.
```

The implementation package must freeze the secret pattern list and bind:

```text
redaction_pattern_set_id;
redaction_pattern_set_sha256;
redaction_algorithm_version = D002-REDACTION-V1.
```

Normalization must preserve:

```text
line endings in RAW;
stack frame order;
digest field values;
exception class;
message structure before redaction.
```

### 4.5 Exception evidence state

FailureCapture must record exactly one:

```text
EXCEPTION_CAPTURED;
NO_EXCEPTION_THROWN;
EXCEPTION_CAPTURE_DEFECT.
```

Rules:

| Situation | State | Result |
| --- | --- | --- |
| exception caught; RAW and NORMALIZED sealed | `EXCEPTION_CAPTURED` | valid FAIL evidence |
| rejection without thrown exception | `NO_EXCEPTION_THROWN` | valid FAIL evidence |
| exception escaped handler or was not captured | `EXCEPTION_CAPTURE_DEFECT` | primary `EVIDENCE_CAPTURE_DEFECT` |
| handler failed while sealing evidence | `EXCEPTION_CAPTURE_DEFECT` | primary `EVIDENCE_CAPTURE_DEFECT` |

This makes missing decisive evidence itself auditable.

### 4.6 Partial-write closure

For each `exception_pair_id`, exactly one state:

```text
RAW_PRESENT + NORMALIZED_PRESENT = EXCEPTION_EVIDENCE_CLOSED;
RAW_PRESENT + NORMALIZED_ABSENT  = PARTIAL_WRITE_RAW_ONLY;
RAW_ABSENT  + NORMALIZED_PRESENT = PARTIAL_WRITE_NORMALIZED_ONLY;
RAW_ABSENT  + NORMALIZED_ABSENT after exception = EXCEPTION_EVIDENCE_MISSING.
```

All partial states are terminal `EVIDENCE_CAPTURE_DEFECT`. They cannot be
repaired by post-audit reconstruction.

## 5. R4 — complete preflight rejection enum

The first-fault precedence is frozen:

```text
1 D001_PREFLIGHT_MISSING_FIELD
2 D001_PREFLIGHT_PATH_SAFETY_REJECTION
3 D001_PREFLIGHT_EXTRA_FIELD
4 D001_PREFLIGHT_SCHEMA_ID_MISMATCH
5 D001_PREFLIGHT_JSON_TYPE_REJECTION
6 D001_PREFLIGHT_ENUM_VALUE_REJECTION
7 D001_PREFLIGHT_VALUE_REJECTION
8 D001_PREFLIGHT_DIGEST_REJECTION
9 D001_PREFLIGHT_CARDINALITY_REJECTION
10 D001_PREFLIGHT_ASSOCIATION_REJECTION
```

No other preflight rejection class is valid.

Each rejection record requires:

```text
rejection_class;
rejection_precedence;
profile;
stage_id;
stage_sequence;
family;
json_path;
expected;
actual;
allowed_secondary_defects[];
next_action = CASE_TERMINATED;
semantic_repair_attempted = false;
d001_executed = false.
```

### 5.1 D001_PREFLIGHT_MISSING_FIELD

```text
trigger: required field or required nested object is absent;
precedence: 1;
secondary: all other independently observed defects;
termination: immediate case termination after FailureCapture.
```

### 5.2 D001_PREFLIGHT_PATH_SAFETY_REJECTION

```text
trigger: path is absolute, uses backslash, contains `..`, escapes fixture root,
        names a symlink, or leaves an approved fixture root;
precedence: 2;
secondary: generic value/type observations;
termination: immediate case termination; no path read.
```

### 5.3 D001_PREFLIGHT_EXTRA_FIELD

```text
trigger: unknown top-level or nested exact-object field;
precedence: 3;
secondary: later value/type defects for the same object;
termination: immediate case termination.
```

### 5.4 D001_PREFLIGHT_SCHEMA_ID_MISMATCH

```text
trigger: wrapper schema_id differs from the required D001 wrapper schema;
precedence: 4;
secondary: nested constraints not evaluated after mismatch;
termination: immediate case termination.
```

### 5.5 D001_PREFLIGHT_JSON_TYPE_REJECTION

```text
trigger: field is not the required JSON type;
precedence: 5;
secondary: constraints dependent on that type;
termination: immediate case termination.
```

### 5.6 D001_PREFLIGHT_ENUM_VALUE_REJECTION

```text
trigger: field exists and is the right type but is outside the frozen enum;
precedence: 6;
secondary: downstream enum-dependent checks;
termination: immediate case termination.
```

### 5.7 D001_PREFLIGHT_VALUE_REJECTION

```text
trigger: nonempty/well-formed value violates a frozen value rule;
precedence: 7;
secondary: dependent cardinality or association checks;
termination: immediate case termination.
```

### 5.8 D001_PREFLIGHT_DIGEST_REJECTION

```text
trigger: digest is malformed or recomputation differs;
precedence: 8;
secondary: downstream identity checks;
termination: immediate case termination.
```

### 5.9 D001_PREFLIGHT_CARDINALITY_REJECTION

```text
trigger: array/object cardinality violates the frozen contract, including
        duplicate action IDs or zero/multiple pointers where one is required;
precedence: 9;
secondary: downstream selection checks;
termination: immediate case termination.
```

### 5.10 D001_PREFLIGHT_ASSOCIATION_REJECTION

```text
trigger: keys, closure members, invocation IDs, or resolved-input references
        fail required association;
precedence: 10;
secondary: later semantic checks;
termination: immediate case termination.
```

No rejection may be renamed, merged, or downgraded.

## 6. Complete active stage order and preflight profile

| Sequence | Stage | Output | Preflight |
| --- | --- | --- | --- |
| 0 | S0 BASELINE_VERIFICATION | S0 record | baseline rules |
| 1 | S1 RETAINED_SOURCE_SELECTION_AUDIT | S1 record | retained-order rules |
| 2 | S2 SEALED_SNAPSHOT_VERIFICATION | S2 record | read-only snapshot rules |
| 3 | S3 PRIMITIVE_INVENTORY_AUDIT | S3 record | R-I inventory rules |
| 4 | S4 FIXTURE_REPRESENTATION_AUDIT | S4 record | retained representation rules |
| 5 | S5 AUXILIARY_MAPPING_RECORD_AUDIT | S5 record | non-causal isolation rules |
| 6 | S6 NON_INVOCATION_WRAPPER_TRANSLATION | S6 record | translation-source rules |
| 7 | S7 CLOSURE_DIGEST_MATERIALIZATION | S7 record | digest materialization rules |
| 8 | S8 NON_INVOCATION_D001_EXACT_FIELD_PREFLIGHT | S8 record | non-invocation D001 preflight |
| 9 | S9 INVOCATION_MATERIALIZATION_AND_FINAL_PREFLIGHT | S9 record | invocation final D001 preflight |
| 10 | S10 RESOLVED_INPUT_ASSEMBLY | S10 record | resolved-input assembly rules |
| 11 | S11 RESOLVED_INPUT_ASSOCIATION_AUDIT | S11 record | association rules |
| 12 | S12 D001_HANDOFF_REQUEST_PREPARATION | S12 record | handoff-request preparation rules |
| — | STOP | no D001 execution | separate Human authorization required |

S13 remains a campaign-level historical static audit, outside this active chain.

## 7. D001 code identity carried forward

| File | Content SHA-256 | Git blob ID |
| --- | --- | --- |
| `schemas.py` | `a226522c60bb4352494d01992f09c34f546e56839c19de64440ec40449296216` | `e0c82604e1f58b08a8578329593c92f7a3bf9399` |
| `inventory.py` | `39508edee8826e9728d48ccb4f8a7c430890c7b5349d1424aaf10a756c071a27` | `69508cd64243f01e5e2e4425b98b01340957160e` |
| `reconstruction.py` | `78af949080c48a8ae01e015cded42464c4e970f94470e2c305e825b7b2c95b41` | `a249834d3c48073517dbe321adbc4b8aa20d9bd1` |
| `continuation.py` | `c4af004dbb8993cbaee40b145a95ae41c185e63d34316c574f85c2a3cb98038b` | `adf4428c1968534107bc33b3bc7400a811c4f3ca` |
| `carrier.py` | `b377e8b5a933d5f9e4b3859f1dd0716be6d42df4634429c2378251c45f286e2e` | `1426a231d8eb312659eb8a843f880e2a944243ca` |

T0–T6 checks remain mandatory.

## 8. Acceptance criteria

Human review should accept v1.3 only if:

```text
1 S8/S9 have one unique materialization/preflight order;
2 StageRecord schema, sequence, chains, and FailureCapture association are closed;
3 RAW/NORMALIZED exception evidence and partial-write defects are closed;
4 path-safety rejection has a unique enum entry and first-fault precedence;
5 accepted v1.2 boundaries remain unchanged;
6 no implementation/execution/campaign/mutation/evidence rewrite is authorized.
```

## 9. Decision requested

Human review must return exactly one ruling:

```text
ACCEPT   freeze v1.3 design only;
REVISE   require a v1.4 design revision;
REJECT   close this instrumentation/redesign pathway.
```

ACCEPT does not authorize implementation, dry materialization, validation,
D001 handoff, observer, campaign, mutation, or equivalence claims.
