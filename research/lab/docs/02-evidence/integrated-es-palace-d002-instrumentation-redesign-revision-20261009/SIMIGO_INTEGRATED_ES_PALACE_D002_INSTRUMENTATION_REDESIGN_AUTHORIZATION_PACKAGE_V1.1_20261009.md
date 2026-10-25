# D-002 Replay-Adapter Instrumentation / Redesign Authorization Package v1.1

> **Status:** REVISED FOR HUMAN REVIEW — DESIGN ONLY
> **Date:** 2026-10-09
> **Package ID:** `INTEGRATED-ES-PALACE-D002-INSTRUMENTATION-REDESIGN-AUTH-PACKAGE-V1.1`
> **Supersedes:** v1.0 = REVISE / retained immutable
> **Canonical base:** `cfa6748bd83c1e99abaf7e9ba58319722d22d4d7`
> **Instrumentation implementation:** NOT AUTHORIZED
> **Adapter redesign implementation:** NOT AUTHORIZED
> **dry materialization / validation:** NOT AUTHORIZED
> **D-002 rerun / new campaign:** NOT AUTHORIZED
> **D-001 decide() / observer execution:** NOT AUTHORIZED
> **canonical / PALACE mutation:** NOT AUTHORIZED
> **evidence overwrite:** FORBIDDEN

## 0. Revision response

v1.0 was ruled `REVISE`. This v1.1 closes the four required gaps without
authorizing implementation or execution:

```text
1 S0–S13 stage-to-code mapping, inputs, outputs, success/failure and termination;
2 exception evidence closure: write-once raw/normalized capture, digest binding,
  correlation identifiers, and redaction rules;
3 D-001 exact-field preflight: fixed schema source, required fields, types,
  rejection rules, and strict isolation from semantic decision authority;
4 D-001 core byte-invariance proof: verification points, failure stop rules,
  and proof that checked code is unmodified.
```

v1.0 remains retained at:

```text
docs/02-evidence/integrated-es-palace-d002-instrumentation-redesign-20261009/
  SIMIGO_INTEGRATED_ES_PALACE_D002_INSTRUMENTATION_REDESIGN_AUTHORIZATION_PACKAGE_V1.0_20261009.md;
SHA256 = 5e9259207f42c3c1a5f5527add22eae17df1d88f4e2eba2ab2cc40de8453bff0.
```

## 1. Non-negotiable result

The design objective is not to make D-002 pass. It is to make a future,
separately authorized study explain the exact failing adapter stage with
write-once evidence.

```text
No D-002 rerun;
no new campaign;
no repair-run;
no D-001 decide() execution;
no observer execution;
no D-001 mutation;
no D-002 implementation mutation;
no PALACE/canonical mutation;
no overwrite of sealed Attempt-001..003 evidence.
```

## 2. Frozen inputs

### 2.1 Postmortem audit

```text
POSTMORTEM_AUDIT_RECORD.md SHA256 =
  c1d525fec465dff765ee0cda266ab655f8d58c3283934b417423346f684afb5d;
FIELD_TRACE_MATRIX.json SHA256 =
  ad25129d12a469641285b382416bdf54076047e5ec82f6a428820ce1550e48c9;
LOSS_CLASSIFICATION.json SHA256 =
  6d612192e45235ae905dff5a586ab0ccbce165f84c37f94f81a360062573f406;
ROOT_CAUSE_HYPOTHESIS.json SHA256 =
  9f6ab53e2260d2736297d3c945464d6bf7ce07a4e972a0a419dad5a30afb61dc;
CORRECTION_PROPOSAL.md SHA256 =
  2ddc41d1e1001d63083625850800cfda16e9d9b990722fed2ebc9d653745669b;
AUDIT_EVIDENCE_SHA256SUMS SHA256 =
  d156b4095825ad8026137361e32aa5cad8e0cc32d8b509576e5d7cd13b058a1f.
```

### 2.2 PALACE and snapshot

```text
PALACE source SHA256 =
  3f790600bfa0ebb0eb7bd4e9f28ac1b6353bd6802d5eeb8f964e7edb8861bf0a;
D-002 snapshot SHA256 =
  8b3856e2e4e3a1bd87580afc1ab42094e9a952e0985952323e02ae6595ce1444.
```

## 3. S0–S13 stage-to-code mapping

“Existing target” is the code that a future implementation package would
instrument. This is a design mapping only; no function is modified or executed.

| Stage | Purpose | Existing observation target | Required input | Required output | PASS condition | FAIL condition / termination |
| --- | --- | --- | --- | --- | --- | --- |
| S0 | baseline verification | `d002/implementation/campaign.py::git`, `digest_bytes`, `manifest_adapter_closure` | run manifest, repository HEAD, baseline digests | `S0_BASELINE_RECORD` | clean worktree; HEAD = origin/main; all baselines match | any mismatch ⇒ write FAIL record; stop before S1 |
| S1 | real-source selection audit | `d002/implementation/primitive_inventory.py::ordered_records` | verified snapshot; ordering rule `ORDER BY internal_id LIMIT 7` | selected internal IDs and ordering proof | exactly seven distinct ordered IDs | missing/duplicate/unstable ordering ⇒ MISSING_SELECTION stop |
| S2 | snapshot binding | `source_snapshot.py::verify_existing` / `snapshot` | source path, snapshot path, SHA-256 pair, SQLite sidecar state | source/snapshot binding record | source and snapshot unchanged; SQLite integrity and logical table counts pass | source drift, sidecar ambiguity, integrity failure ⇒ stop |
| S3 | primitive inventory audit | `primitive_inventory.py::load_existing` | retained fixture manifests; R-I bindings | primitive inventory digest tree | R-I1..R-I10 resolved and digests match | any missing/duplicate/extra binding ⇒ MISSING_INVENTORY stop |
| S4 | fixture representation audit | retained D-002 fixture files; `primitive_inventory.py::write_json` producer binding | closure, provenance, next-action, invocation, carrier, schemas, destinations | fixture representation trace | all seven roots complete and digest-bound | malformed JSON, missing root, path escape ⇒ BAD_FIXTURE stop |
| S5 | typed mapping trace | `typed_mapping.py::map_fixtures` | fixture records; expected vectors | typed mapping stage record | every D002 field has a declared D001 target or explicit MISSING | undeclared semantic fallback ⇒ TRANSLATION_SPEC_GAP stop |
| S6 | wrapper translation trace | `decision_replay.py::ReplayInventory.read` | D002 wrapper records | translated D001 wrapper candidates | every wrapper family I1/I3/I4/I5/I6/I8/I10 translated | unresolved family ⇒ TRANSLATION_LOSS stop |
| S7 | D-001 exact-field preflight | future `AdapterExactFieldPreflight` design; D001 validation rules in `schemas.py::exact_fields`, `require_schema` | translated D001 candidates; fixed D001 schema contract | exact-field preflight record | all required fields/types/enum/digest constraints pass | any preflight rejection ⇒ D001_PREFLIGHT_REJECTED stop before S8 |
| S8 | closure digest materialization | `decision_replay.py::read("I1")`; D001 `schemas.py::digest` | translated closure fields excluding digest | D001 closure digest binding | adapter digest equals independently recomputed D001 digest | mismatch ⇒ CLOSURE_DIGEST_MISMATCH stop |
| S9 | invocation materialization | `decision_replay.py::read("I6")` | run manifest package binding and fixture invocation | D001 invocation candidate | required six fields present and typed | missing/malformed field ⇒ INVOCATION_MATERIALIZATION_FAILED stop |
| S10 | resolved input assembly | translated closure/provenance/actions/invocation candidates | all S6–S9 outputs | resolved `ESContinuationInput` candidate | all D001 mandatory candidates resolved without fallback | any unresolved candidate ⇒ UNRESOLVED_INPUT_ASSEMBLY stop |
| S11 | pre-decision validation | future `AdapterResolvedInputPreflight`; D001 exact-field/type rules | resolved input candidate | validation preflight record | resolved input passes D001 shape/type/digest preflight | any rejection ⇒ RESOLVED_INPUT_REJECTED stop; no semantic repair |
| S12 | D-001 handoff boundary | future separately authorized D001 replay only | resolved and preflight-passed input | D001 handoff receipt | explicit separate Human authorization exists | absent authorization ⇒ NOT_AUTHORIZED stop |
| S13 | unresolved fallback capture | prior `decision_replay.py::replay`; D001 unresolved input encoding | failed candidate and exception evidence | unresolved fallback trace | exact failing stage and exception evidence captured | missing evidence ⇒ EVIDENCE_CAPTURE_DEFECT stop |

Rules:

```text
1 stages are sequential; no skip except designed SKIPPED records;
2 a FAIL record is terminal for that case;
3 no stage may invoke semantic repair;
4 S12 is outside this design's execution authority;
5 S13 may record that D001 would fail closed, but must not execute D001.
```

## 4. Exception evidence closure

### 4.1 Required evidence objects

The future implementation must emit two write-once objects for every caught
adapter exception:

```text
RAW_EXCEPTION_PAYLOAD  — exact original diagnostic bytes or canonical JSON;
NORMALIZED_EXCEPTION   — canonical, redacted, schema-bound record.
```

Both are diagnostic evidence. Neither is semantic decision authority.

### 4.2 Normalized exception record

Required fields:

```text
schema_id                      = "D002-ADAPTER-EXCEPTION-NORMALIZED-V2";
trace_id;
case_id;
source_internal_id;
stage_id;
stage_sequence;
exception_class;
exception_message_raw_sha256;
exception_message_normalized;
exception_message_normalized_sha256;
stack_frame_digests[];
input_object_digests;
expected_d001_schema_id;
expected_required_fields[];
missing_fields[];
extra_fields[];
type_errors[];
value_errors[];
fallback_encoding_observed;
raw_payload_sha256;
raw_payload_byte_size;
raw_payload_evidence_reference;
previous_stage_record_digest;
d001_core_sha256_set;
created_at_utc;
trace_chain_digest.
```

Constraints:

```text
exception_class                 = nonempty string;
digests                         = lowercase 64-hex SHA-256;
missing_fields/extra_fields     = sorted unique strings;
fallback_encoding_observed      = boolean;
semantic_decision_from_exception = forbidden;
trace_chain_digest              = SHA-256(previous chain digest + stage record).
```

### 4.3 Write order

```text
1 serialize raw payload to isolated diagnostic object;
2 compute raw byte SHA-256 and size;
3 normalize and redact;
4 serialize normalized record;
5 append hash-chained `ADAPTER_STAGE_RECORDS.jsonl` record referencing both;
6 append `EXCEPTION_EVIDENCE_SHA256SUMS` only at audit closure.
```

No object may be overwritten. If a collision or existing destination is found,
the stage terminates as `EVIDENCE_WRITE_CONFLICT`.

### 4.4 Correlation identifiers

Every exception record must correlate:

```text
trace_id;
case_id;
source_internal_id;
stage_id;
stage_sequence;
D-001 core hash set;
D-002 implementation hash set;
previous_stage_record_digest.
```

### 4.5 Redaction rules

The normalized record must be produced from the raw payload without semantic
interpretation:

```text
replace absolute repository prefix with <REPO>;
replace user home prefix with <USER>;
replace secret-like tokens matching declared secret patterns with <REDACTED_SECRET>;
preserve exception class, stable message structure, stage identifiers, and digests;
never infer a semantic cause from exception text;
never change the raw payload.
```

The implementation package must publish the exact redaction pattern list and
test vectors before execution.

## 5. D-001 exact-field preflight

### 5.1 Fixed schema source

The preflight must use only these frozen D-001 files as the schema authority:

```text
integrated-es-palace/d001/implementation/schemas.py SHA256 =
  a226522c60bb4352494d01992f09c34f546e56839c19de64440ec40449296216;
integrated-es-palace/d001/implementation/inventory.py SHA256 =
  39508edee8826e9728d48ccb4f8a7c430890c7b5349d1424aaf10a756c071a27;
integrated-es-palace/d001/implementation/reconstruction.py SHA256 =
  78af949080c48a8ae01e015cded42464c4e970f94470e2c305e825b7b2c95b41;
integrated-es-palace/d001/implementation/continuation.py SHA256 =
  c4af004dbb8993cbaee40b145a95ae41c185e63d34316c574f85c2a3cb98038b;
integrated-es-palace/d001/implementation/carrier.py SHA256 =
  b377e8b5a933d5f9e4b3859f1dd0716be6d42df4634429c2378251c45f286e2e.
```

The D002 implementation must not redefine these schema rules.

### 5.2 Required translated wrappers and exact fields

| D001 family | Required schema_id | Required fields besides schema_id | Type constraints |
| --- | --- | --- | --- |
| I1 | `LAWFUL-INFORMATION-CLOSURE-D001-V1` | `closure_id`, `closure_revision`, `members`, `closure_digest` | ids/revision nonempty strings; `members` array; digest lowercase 64-hex; recomputed digest equals stored digest |
| I3 | `CARRIER-SNAPSHOT-D001-V1` | `closure_id`, `approved_read`, `settled_record` | closure id nonempty; approved boolean; settled object; REUSE settled record requires identity/output digests |
| I4 | `PROVENANCE-REVISION-D001-V1` | `records` | object keyed by every closure member; each has nonempty revision, status enum, lowercase digest |
| I5 | `NEXT-ACTION-D001-V1` | `actions` | array; each action has unique id, lowercase target and boundary digest, valid continuation class |
| I6 | `APPROVED-INVOCATION-D001-V1` | `manifest_instance_id`, `package_id`, `stage`, `schema_version`, `opaque_locator` | all nonempty strings; stage enum; locator repository opaque form |
| I8 | `APPROVED-SCHEMAS-D001-V1` | `input`, `output` | exact D001 schema IDs |
| I10 | `APPROVED-EVIDENCE-DESTINATIONS-D001-V1` | `objects` | array matching approved evidence object list |

`PROVENANCE-REVISION-D001-V1` status enum:

```text
CURRENT | SUPERSEDED
```

`continuation_class` enum:

```text
SETTLED_CONTINUATION |
BLOCKED_LAWFUL_CONTINUATION |
BLOCKED_DEFECT |
NON_CONTINUABLE
```

### 5.3 Preflight rejection classes

Rejection must be recorded as one and only one first-fault class:

```text
D001_PREFLIGHT_MISSING_FIELD;
D001_PREFLIGHT_EXTRA_FIELD;
D001_PREFLIGHT_SCHEMA_ID_MISMATCH;
D001_PREFLIGHT_TYPE_REJECTION;
D001_PREFLIGHT_VALUE_REJECTION;
D001_PREFLIGHT_DIGEST_REJECTION;
D001_PREFLIGHT_CARDINALITY_REJECTION.
```

Rules:

```text
preflight is descriptive validation, not semantic repair;
no field may be added, coerced, guessed, or defaulted;
rejection stops adapter materialization before D001 handoff;
all secondary defects may be recorded without changing first fault;
rejection never creates a semantic decision.
```

## 6. D-001 core byte-invariance proof

### 6.1 Frozen code identity set

```text
schemas.py        SHA256 = a226522c60bb4352494d01992f09c34f546e56839c19de64440ec40449296216;
inventory.py      SHA256 = 39508edee8826e9728d48ccb4f8a7c430890c7b5349d1424aaf10a756c071a27;
reconstruction.py SHA256 = 78af949080c48a8ae01e015cded42464c4e970f94470e2c305e825b7b2c95b41;
continuation.py   SHA256 = c4af004dbb8993cbaee40b145a95ae41c185e63d34316c574f85c2a3cb98038b;
carrier.py        SHA256 = b377e8b5a933d5f9e4b3859f1dd0716be6d42df4634429c2378251c45f286e2e.
```

The future implementation record must also bind each Git blob ID and byte size.
At this design review, the Git blob IDs for `schemas.py` and `continuation.py`
are:

```text
schemas.py      = e0c82604e1f58b08a8578329593c92f7a3bf9399;
continuation.py = adf4428c1968534107bc33b3bc7400a811c4f3ca.
```

### 6.2 Verification points

Core invariance must be checked at:

```text
T0 design acceptance;
T1 implementation authorization entry;
T2 instrumentation package build entry;
T3 instrumentation build completion;
T4 dry materialization authorization entry;
T5 immediately before any D001 handoff authorization request;
T6 after any authorized dry process exits.
```

No D001 execution is authorized by this Package.

### 6.3 Required proof fields

Each check must emit:

```text
verification_point;
HEAD commit SHA-256;
HEAD == origin/main;
worktree_clean;
path;
expected_content_sha256;
actual_content_sha256;
expected_git_blob_id;
actual_git_blob_id;
byte_size;
symlink=false;
tracked=true;
git_diff_against_frozen_commit=empty;
result.
```

### 6.4 Failure stop rule

If any check fails:

```text
1 stop all implementation and validation activity;
2 write `CORE_INVARIANCE_FAILURE.json` as a new write-once object;
3 bind expected and actual content hashes, Git blob IDs, HEAD, and path;
4 do not attempt repair;
5 do not enter replay, dry materialization, or campaign;
6 request separate Human decision.
```

`CORE_INVARIANCE_FAILURE` may never be repaired automatically.

## 7. Acceptance criteria for v1.1

Human review should accept this revision only if:

```text
1 every S0–S13 stage has a bound existing target, required I/O, success/failure
  conditions, and terminal stop rule;
2 every adapter exception has mandatory write-once raw and normalized closure,
  digest binding, correlation IDs, and explicit redaction rules;
3 D001 exact-field preflight has fixed schema sources, exact fields, types,
  enums, digest constraints, and rejection classes;
4 D001 core invariance has fixed content hashes, verification points, Git blob
  binding, and fail-closed stop rules;
5 no implementation, execution, campaign, mutation, or evidence rewrite is
  authorized.
```

## 8. Decision requested

Human review must return exactly one ruling:

```text
ACCEPT   freeze v1.1 design only;
REVISE   require a v1.2 design revision;
REJECT   close this instrumentation/redesign pathway.
```

ACCEPT does not authorize implementation, dry materialization, validation,
campaign, D001 execution, observer execution, mutation, or equivalence claims.
