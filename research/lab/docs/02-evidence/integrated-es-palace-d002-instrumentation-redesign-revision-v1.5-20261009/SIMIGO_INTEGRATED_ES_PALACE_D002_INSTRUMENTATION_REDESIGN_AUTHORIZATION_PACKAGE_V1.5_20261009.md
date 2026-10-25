# D-002 Replay-Adapter Instrumentation / Redesign Authorization Package v1.5

> **Status:** REVISED FOR HUMAN REVIEW — DESIGN ONLY  
> **Date:** 2026-10-09  
> **Package ID:** `INTEGRATED-ES-PALACE-D002-INSTRUMENTATION-REDESIGN-AUTH-PACKAGE-V1.5`  
> **Supersedes:** v1.4 = REVISE / retained immutable  
> **Canonical base:** `16d2d2ce3568cd31ec62499fece19f6cd7f32035`  
> **implementation:** NOT AUTHORIZED  
> **dry materialization:** NOT AUTHORIZED  
> **validation execution:** NOT AUTHORIZED  
> **D-002 rerun / repair-run / new campaign:** NOT AUTHORIZED  
> **D-001 decide() / observer execution:** NOT AUTHORIZED  
> **D-001 handoff:** NOT AUTHORIZED  
> **canonical / PALACE mutation:** NOT AUTHORIZED  
> **evidence overwrite:** FORBIDDEN

## 0. Revision purpose

v1.5 preserves accepted v1.4 boundaries and closes four final schema/protocol gaps:

```text
R1 define one common PASS/FAIL StageRecordCore schema;
R2 make previous-record binding uniquely reference StageRecordCore digest;
R3 define component-by-component TOCTOU-resistant path opening and hard-link policy;
R4 define terminal evidence when FailureCapture storage itself fails.
```

v1.0–v1.4 remain write-once and retained.

## 1. Retained boundaries

```text
D-001 Decision Core       = CLOSED / BOUNDED PASS / READ-ONLY;
D-002                     = FAIL / STOP;
D-002 Postmortem          = COMPLETE / FROZEN;
D-002 rerun               = FORBIDDEN;
repair-run                = FORBIDDEN;
D-001 decide()            = NOT AUTHORIZED;
observer execution        = NOT AUTHORIZED;
D-001 handoff             = NOT AUTHORIZED;
implementation            = NOT AUTHORIZED;
dry materialization       = NOT AUTHORIZED;
validation execution      = NOT AUTHORIZED;
canonical/PALACE mutation = NOT AUTHORIZED;
evidence overwrite        = FORBIDDEN.
```

The v1.4 design constraints retained are: entered-stage chain completeness,
non-circular failure binding, comparator-only EXPECTED vectors, read-only sealed
snapshot verification, `embedding_metadata.id` selection, S0–S12 order, complete
preflight rejection enum, and S13 historical-only audit.

This Package does not describe v1.3 as an accepted baseline. It inherits only the
specific v1.3/v1.4 constraints listed above and in Section 8.

## 2. R1 — unified StageRecordCore schema

### 2.1 Object identity

The canonical semantic record is:

```text
schema_id = D002-ADAPTER-STAGE-RECORD-CORE-V5.
```

`StageAttemptCore` from v1.4 remains a FAIL-only precursor object. It is not the
PASS/FAIL canonical record and must not be used for PASS.

### 2.2 Exact field set

A canonical `StageRecordCoreV5` has exactly these fields:

| Field | Presence | Type / constraint |
| --- | --- | --- |
| `schema_id` | required | constant `D002-ADAPTER-STAGE-RECORD-CORE-V5` |
| `trace_id` | required | UUIDv4 |
| `case_id` | required | frozen case ID |
| `source_embedding_metadata_id` | required | integer 1..7 |
| `stage_id` | required | `S0`..`S12` |
| `stage_sequence` | required | integer equal to numeric suffix |
| `status` | required | `PASS` or `FAIL` |
| `started_at_utc` | required | RFC 3339 UTC ending `Z` |
| `finished_at_utc` | required | RFC 3339 UTC ending `Z`, not before start |
| `stage_profile` | required | exact v1.4 profile string |
| `input_schema_id` | required | nonempty string or null |
| `input_object_digests` | required | object; values lowercase SHA-256 |
| `output_schema_id` | required | nonempty string or null for S12 |
| `output_object_digests` | required | object; values lowercase SHA-256 |
| `previous_stage_core_digest` | required | null for S0; otherwise prior Core digest |
| `failure_evidence_state` | required | enum in Section 2.4 |
| `failure_evidence_kind` | conditional | see Section 2.4 |
| `failure_evidence_digest` | conditional | lowercase SHA-256 or null |
| `failure_class` | FAIL only | registered failure class |
| `failure_anchor_digest` | FAIL only | lowercase SHA-256 |
| `failure_capture_digest` | nullable | required iff `failure_evidence_kind = FAILURE_CAPTURE` |
| `termination_witness_digest` | nullable | required iff kind = `TERMINATION_WITNESS` |
| `expected_vector_used` | required | constant false |
| `d001_executed` | required | constant false |
| `observer_executed` | required | constant false |
| `semantic_decision_attempted` | required | constant false |
| `d001_core_sha256_set` | required | five path/digest entries |
| `d002_implementation_sha256_set` | required | implementation identity map |
| `next_action` | required | `ADVANCE`, `CASE_TERMINATED`, or `STOP_PENDING_SEPARATE_AUTHORIZATION` |

Unknown fields are invalid.

### 2.3 Status constraints

PASS requires:

```text
status = PASS;
failure_evidence_state = NOT_APPLICABLE;
failure_evidence_kind = null;
failure_evidence_digest = null;
failure_class = null;
failure_anchor_digest = null;
failure_capture_digest = null;
termination_witness_digest = null;
next_action = ADVANCE for S0..S11;
next_action = STOP_PENDING_SEPARATE_AUTHORIZATION for S12.
```

FAIL requires:

```text
status = FAIL;
next_action = CASE_TERMINATED;
failure_class = registered class.
```

FAIL must use one of:

```text
failure_evidence_kind = FAILURE_CAPTURE
failure_evidence_digest = FailureCapture digest

or

failure_evidence_kind = TERMINATION_WITNESS
failure_evidence_digest = TerminationWitness digest
```

`failure_evidence_state` distinguishes the underlying situation:

```text
NO_EXCEPTION_THROWN;
EXCEPTION_CAPTURED;
EXCEPTION_CAPTURE_PARTIAL_WRITE;
EXCEPTION_CAPTURE_WRITE_FAILURE;
EXCEPTION_CAPTURE_VERIFICATION_FAILURE;
EVIDENCE_CAPTURE_UNVERIFIABLE;
NOT_APPLICABLE.
```

The mapping is frozen in Section 5.

### 2.4 Digest calculation

```text
stage_record_core_digest =
  SHA256(canonical_json(StageRecordCoreV5)).
```

`previous_stage_core_digest` always refers to this Core digest, not to a full
envelope digest.

## 3. R2 — predecessor and full-record binding

### 3.1 Full envelope

After Core digest calculation, the implementation may create:

```text
schema_id = D002-ADAPTER-STAGE-RECORD-FULL-V5;
stage_record_core_digest;
previous_stage_core_digest;
previous_chain_digest;
trace_chain_digest_after_stage;
failure_chain_digest_after_capture or null;
stage_record_full_digest.
```

`stage_record_full_digest` is computed over the canonical Full object with
`stage_record_full_digest` omitted. It is an optional external integrity digest,
not the predecessor pointer.

### 3.2 Predecessor rule

The only valid cross-stage predecessor field is:

```text
previous_stage_core_digest.
```

It must equal the prior stage's `stage_record_core_digest`.

It must never be described or implemented as a Full digest pointer.

### 3.3 Chain update

```text
previous_chain_digest =
  SHA256("D002-ADAPTER-STAGE-CHAIN-V5|GENESIS|" + trace_id + "|" + case_id)
  for S0;

prior `trace_chain_digest_after_capture` for N>0.

stage_chain_message =
  UTF8(previous_chain_digest_hex)
  || 0x00
  || UTF8(stage_record_core_digest_hex)
  || 0x00
  || canonical(StageRecordCoreV5).

trace_chain_digest_after_stage =
  SHA256(stage_chain_message).
```

For FAIL with sealed FailureCapture:

```text
failure_chain_message =
  UTF8(trace_chain_digest_after_stage_hex)
  || 0x00
  || UTF8(failure_capture_digest_hex)
  || 0x00
  || canonical(FailureCapture).

failure_chain_digest_after_capture =
  SHA256(failure_chain_message).
```

For FAIL with only TerminationWitness:

```text
failure_chain_message =
  UTF8(trace_chain_digest_after_stage_hex)
  || 0x00
  || UTF8(termination_witness_digest_hex)
  || 0x00
  || canonical(TerminationWitness).

failure_chain_digest_after_capture =
  SHA256(failure_chain_message).
```

PASS sets:

```text
failure_chain_digest_after_capture = null.
```

## 4. R3 — component-by-component path protocol

### 4.1 Frozen approved-root identity

Before any guarded read, the implementation must bind:

```text
approved_root_path;
root_lstat = {st_dev, st_ino, st_mode, st_nlink, st_uid, st_gid};
root_open_flags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW;
root_identity_source = frozen path-identity manifest.
```

At runtime:

```text
lstat(root_path) must succeed and must not be a symlink;
st_dev and st_ino must equal frozen identity;
open(root_path, root_open_flags) must succeed;
fstat(root_fd) must again equal frozen identity;
root_fd remains open for all descendant opens.
```

### 4.2 Component opening protocol

The relative path is split on `/`. Empty, `.`, `..`, backslash, absolute, and
NUL components are rejected before any open.

For each component:

```text
1 openat(parent_fd, component,
         O_RDONLY | O_NOFOLLOW,
         0 for non-final directories or files;
         O_DIRECTORY | O_NOFOLLOW for an expected directory);
2 fstat(new_fd);
3 verify file type matches the declared component type;
4 verify st_dev and st_ino against the frozen path-identity manifest when bound;
5 verify regular-file st_nlink = 1;
6 retain the descriptor as parent for the next component.
```

No full path is reopened. No component is followed through a symlink. If an
expected identity is absent from the frozen manifest, the descriptor may be
verified for type and then digest-bound, but the case remains
`PATH_IDENTITY_NOT_FROZEN` unless the implementation manifest separately allows
that class.

### 4.3 Final target verification

After final open:

```text
1 fstat descriptor;
2 verify regular file;
3 verify st_nlink = 1;
4 read contents through the descriptor;
5 compute SHA-256;
6 compare frozen digest when bound;
7 parse only after digest verification succeeds.
```

Failure classes:

```text
PATH_GUARD_LEXICAL_REJECTION;
PATH_GUARD_ROOT_IDENTITY_REJECTION;
PATH_GUARD_OPEN_REJECTION;
PATH_GUARD_COMPONENT_SYMLINK_REJECTION;
PATH_GUARD_COMPONENT_TYPE_REJECTION;
PATH_GUARD_COMPONENT_IDENTITY_REJECTION;
PATH_GUARD_HARDLINK_REJECTION;
PATH_GUARD_FINAL_TYPE_REJECTION;
PATH_GUARD_DESCRIPTOR_IDENTITY_REJECTION;
PATH_GUARD_CONTENT_DIGEST_REJECTION.
```

Any rejection occurs before content parsing and terminates the case.

## 5. R4 — FailureCapture write-failure termination protocol

### 5.1 Independent evidence channels

At case start, the future implementation must open two independent write-once
channels:

```text
PRIMARY_EVIDENCE_CHANNEL
  stores RAW / NORMALIZED / FailureAnchor / FailureCapture / StageRecordCore.

INDEPENDENT_TERMINATION_WITNESS_CHANNEL
  stores only minimal TerminationWitness records and must not depend on the
  primary evidence filesystem or directory.
```

Both channel paths and identities are frozen in the implementation manifest. The
witness channel is opened before S0 and remains open until case termination.

### 5.2 Sealed FailureCapture path

If all primary writes and verification succeed:

```text
failure_evidence_kind = FAILURE_CAPTURE;
failure_evidence_digest = SHA256(canonical FailureCapture);
failure_evidence_state = EXCEPTION_CAPTURED or NO_EXCEPTION_THROWN.
```

### 5.3 Primary-write failure protocol

If RAW, NORMALIZED, FailureAnchor, FailureCapture, fsync, or post-write
verification fails, the implementation must:

```text
1 stop primary evidence closure;
2 not reconstruct or fake FailureCapture;
3 write a minimal TerminationWitness through the independent channel;
4 fsync the witness;
5 create StageRecordCoreV5 with:
     failure_evidence_kind = TERMINATION_WITNESS;
     failure_evidence_digest = witness digest;
     failure_evidence_state from Section 5.4;
6 terminate the case.
```

A TerminationWitness contains exactly:

```text
schema_id = D002-TERMINATION-WITNESS-V1;
trace_id;
case_id;
source_embedding_metadata_id;
stage_id;
stage_sequence;
termination_reason =
  RAW_WRITE_FAILURE |
  NORMALIZED_WRITE_FAILURE |
  FAILURE_ANCHOR_WRITE_FAILURE |
  FAILURE_CAPTURE_WRITE_FAILURE |
  PRIMARY_FSYNC_FAILURE |
  PRIMARY_VERIFY_FAILURE |
  PRIMARY_CHANNEL_UNAVAILABLE;
stage_attempt_digest or null;
failure_anchor_digest or null;
last_successful_stage_record_core_digest or null;
raw_payload_sha256 or null;
normalized_payload_sha256 or null;
primary_error_class;
primary_error_message_digest;
occurred_at_utc;
semantic_interpretation = null.
```

### 5.4 Evidence-state mapping

| Situation | `failure_evidence_state` |
| --- | --- |
| rejection; no exception and no diagnostic payload | `NO_EXCEPTION_THROWN` |
| RAW + NORMALIZED + FailureCapture sealed | `EXCEPTION_CAPTURED` |
| RAW sealed; later primary write failed | `EXCEPTION_CAPTURE_PARTIAL_WRITE` |
| primary channel unavailable before evidence write | `EXCEPTION_CAPTURE_WRITE_FAILURE` |
| object written but digest verification failed | `EXCEPTION_CAPTURE_VERIFICATION_FAILURE` |
| required object missing and witness cannot explain closure | `EVIDENCE_CAPTURE_UNVERIFIABLE` |

### 5.5 Closure verifier rule

An independent verifier never reconstructs missing evidence. It accepts a FAIL
chain only if:

```text
failure_evidence_kind = FAILURE_CAPTURE and FailureCapture verifies; or
failure_evidence_kind = TERMINATION_WITNESS and TerminationWitness verifies.
```

Otherwise it returns:

```text
EVIDENCE_CAPTURE_UNVERIFIABLE
```

This makes evidence-capture failure itself a first-class auditable terminal
state.

## 6. Inherited v1.4 constraints

The following v1.4 constraints remain binding:

```text
one entered stage ⇒ one StageRecord;
early FAIL terminates the chain;
unentered stages have no records;
FailureAnchorCore precedes FailureCapture;
EXPECTED vectors never enter causal materialization;
map_fixtures remains non-causal;
S2 verifies existing snapshot only;
snapshot creation/replacement remains out of scope;
S1 uses `embedding_metadata.id`;
retained order remains 1..7;
S13 is historical static audit only.
```

## 7. D001 code identity carried forward

| File | Content SHA-256 | Git blob ID |
| --- | --- | --- |
| `schemas.py` | `a226522c60bb4352494d01992f09c34f546e56839c19de64440ec40449296216` | `e0c82604e1f58b08a8578329593c92f7a3bf9399` |
| `inventory.py` | `39508edee8826e9728d48ccb4f8a7c430890c7b5349d1424aaf10a756c071a27` | `69508cd64243f01e5e2e4425b98b01340957160e` |
| `reconstruction.py` | `78af949080c48a8ae01e015cded42464c4e970f94470e2c305e825b7b2c95b41` | `a249834d3c48073517dbe321adbc4b8aa20d9bd1` |
| `continuation.py` | `c4af004dbb8993cbaee40b145a95ae41c185e63d34316c574f85c2a3cb98038b` | `adf4428c1968534107bc33b3bc7400a811c4f3ca` |
| `carrier.py` | `b377e8b5a933d5f9e4b3859f1dd0716be6d42df4634429c2378251c45f286e2e` | `1426a231d8eb312659eb8a843f880e2a944243ca` |

## 8. Acceptance criteria

Human review should accept v1.5 only if:

```text
1 PASS and FAIL share one exact StageRecordCore schema;
2 predecessor binding uniquely refers to prior Core digest;
3 Full digest is optional and never used as predecessor identity;
4 path opening uses frozen root identity and component descriptors;
5 regular-file hard links are conservatively rejected;
6 primary evidence-write failure produces an independent TerminationWitness;
7 absence of evidence is classified without reconstruction;
8 no implementation/execution/campaign/mutation/evidence rewrite is authorized.
```

## 9. Decision requested

Human review must return exactly one ruling:

```text
ACCEPT   freeze v1.5 design only;
REVISE   require a v1.6 design revision;
REJECT   close this instrumentation/redesign pathway.
```

ACCEPT does not authorize implementation, dry materialization, validation,
D001 handoff, observer, campaign, mutation, or equivalence claims.
