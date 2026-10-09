# D-002 Replay-Adapter Instrumentation / Redesign Authorization Package v1.4

> **Status:** REVISED FOR HUMAN REVIEW — DESIGN ONLY  
> **Date:** 2026-10-09  
> **Package ID:** `INTEGRATED-ES-PALACE-D002-INSTRUMENTATION-REDESIGN-AUTH-PACKAGE-V1.4`  
> **Supersedes:** v1.3 = REVISE / retained immutable  
> **Canonical base:** `6e631a3d4f7bbfe4dbaa36294a7076373d28b01c`  
> **implementation:** NOT AUTHORIZED  
> **dry materialization:** NOT AUTHORIZED  
> **validation execution:** NOT AUTHORIZED  
> **D-002 rerun / repair-run / new campaign:** NOT AUTHORIZED  
> **D-001 decide() / observer execution:** NOT AUTHORIZED  
> **D-001 handoff:** NOT AUTHORIZED  
> **canonical / PALACE mutation:** NOT AUTHORIZED  
> **evidence overwrite:** FORBIDDEN

## 0. Revision purpose

v1.4 closes four v1.3 contract defects without changing the accepted S0–S12
semantic order:

```text
R1 StageRecord completeness follows entered stages, not all 13 stages;
R2 FailureAnchorCore → FailureCapture → StageRecordCoreFinal → StageRecordFull
   removes circular digest binding;
R3 the complete per-case trace-chain algorithm is restated in this Package;
R4 a universal pre-read path guard applies before every path read in S1–S12.
```

v1.0–v1.3 remain write-once and retained.

## 1. Carried-forward boundaries

```text
D-001 Decision Core   = CLOSED / BOUNDED PASS / READ-ONLY;
D-002                 = FAIL / STOP;
D-002 Postmortem      = COMPLETE / FROZEN;
D-002 rerun           = FORBIDDEN;
repair-run            = FORBIDDEN;
D-001 decide()        = NOT AUTHORIZED;
observer execution    = NOT AUTHORIZED;
D-001 handoff         = NOT AUTHORIZED;
implementation        = NOT AUTHORIZED;
dry materialization   = NOT AUTHORIZED;
validation execution  = NOT AUTHORIZED;
canonical/PALACE mutation = NOT AUTHORIZED;
evidence overwrite    = FORBIDDEN.
```

Accepted v1.3 boundaries retained:

```text
LANE H / LANE F / LANE D separation;
EXPECTED vectors comparator-only;
map_fixtures non-causal;
S2 verify_existing only;
S1 selection field `embedding_metadata.id`;
retained order 1,2,3,4,5,6,7;
unique S8/S9 order;
complete preflight rejection enum.
```

## 2. R1 — entered-stage record completeness

### 2.1 Mandatory scope

A StageRecord is mandatory if and only if the case actually entered that stage.

```text
one entered stage ⇒ exactly one StageRecord;
unentered stage ⇒ no StageRecord;
synthetic PASS/FAIL/SKIPPED records for unentered stages are forbidden.
```

### 2.2 Legal terminal chains

Successful chain:

```text
S0 → S1 → ... → S12
terminal status = PASS at S12;
next_action = STOP_PENDING_SEPARATE_AUTHORIZATION.
```

Early-failure chain:

```text
S0 → ... → S(N) FAIL
N ∈ {0..12};
next_action = CASE_TERMINATED;
S(N+1)..S12 do not exist.
```

A chain ending at its first FAIL is complete and legally valid.

### 2.3 Completeness verification

A validator determines completeness from:

```text
terminal_stage_id;
terminal status;
next_action;
continuous entered-stage sequence;
valid StageRecord and FailureCapture digests.
```

Rules:

```text
if terminal_stage = S12 and status = PASS ⇒ COMPLETE_SUCCESS;
if terminal_stage = S0..S12 and status = FAIL with valid FailureCapture ⇒
   COMPLETE_EARLY_FAILURE;
otherwise ⇒ INCOMPLETE_OR_INVALID_CHAIN.
```

The validator must not require S5–S12 records when S4 failed.

### 2.4 FailureCapture is not a StageRecord

FailureCapture is terminal evidence attached to the failing StageRecord. It does
not consume a later stage sequence and never appears as S13.

## 3. R2 — non-circular failure and StageRecord binding

### 3.1 Object layers

For a failed stage, the immutable build order is:

```text
1 StageAttemptCore;
2 FailureAnchorCore;
3 FailureAnchorDigest;
4 FailureCapture;
5 FailureCaptureDigest;
6 StageRecordCoreFinal;
7 StageRecordDigest;
8 StageRecordFull and chain update.
```

For a successful stage:

```text
1 StageRecordCoreFinal;
2 StageRecordDigest;
3 StageRecordFull and chain update.
```

### 3.2 StageAttemptCore

`StageAttemptCore` is the initial FAIL attempt state. It must contain all semantic
and audit fields except failure capture references:

```text
schema_id = D002-ADAPTER-STAGE-ATTEMPT-CORE-V1;
trace_id;
case_id;
source_embedding_metadata_id;
stage_id;
stage_sequence;
status = FAIL;
started_at_utc;
finished_at_utc;
input_schema_id;
input_object_digests;
output_schema_id;
output_object_digests;
failure_class;
expected_d001_schema_id;
missing_fields[];
extra_fields[];
type_errors[];
value_errors[];
digest_errors[];
cardinality_errors[];
association_errors[];
path_safety_errors[];
stage_profile;
expected_vector_used = false;
d001_executed = false;
observer_executed = false;
semantic_decision_attempted = false.
```

It must not contain:

```text
failure_anchor_digest;
failure_capture_digest;
stage_record_digest;
previous_stage_record_digest;
previous_chain_digest;
trace_chain_digest_after_stage;
trace_chain_digest_after_failure.
```

`stage_attempt_digest = SHA256(canonical StageAttemptCore)`.

### 3.3 FailureAnchorCore

`FailureAnchorCore` is created only after `StageAttemptCore` is complete:

```text
schema_id = D002-FAILURE-ANCHOR-CORE-V1;
stage_attempt_digest;
trace_id;
case_id;
stage_id;
stage_sequence;
failure_class;
source_embedding_metadata_id;
d001_core_sha256_set;
d002_implementation_sha256_set.
```

`failure_anchor_digest = SHA256(canonical FailureAnchorCore)`.

FailureCapture references `failure_anchor_digest`. Because FailureAnchorCore is
already immutable, later addition of `failure_capture_digest` to the final Stage
Record cannot invalidate the anchor.

### 3.4 FailureCapture

`FailureCapture` contains diagnostic evidence and the anchor:

```text
schema_id = D002-ADAPTER-FAILURE-CAPTURE-V2;
failure_anchor_digest;
stage_attempt_digest;
trace_id;
case_id;
stage_id;
stage_sequence;
failure_class;
exception_evidence_state;
exception_pair_id or null;
raw_payload_reference or null;
raw_payload_sha256 or null;
raw_payload_byte_size or null;
normalized_payload_reference or null;
normalized_payload_sha256 or null;
exception_type or null;
exception_message_normalized or null;
exception_message_normalized_sha256 or null;
stack_frame_digests[] or [];
next_action = CASE_TERMINATED;
semantic_decision_attempted = false;
d001_executed = false.
```

`failure_capture_digest = SHA256(canonical FailureCapture)`.

### 3.5 StageRecordCoreFinal

For FAIL, `StageRecordCoreFinal` is created after FailureCapture is sealed:

```text
schema_id = D002-ADAPTER-STAGE-RECORD-CORE-FINAL-V2;
all StageAttemptCore fields;
failure_anchor_digest;
failure_capture_digest;
previous_stage_record_digest or null;
expected_vector_used = false;
d001_executed = false;
observer_executed = false;
semantic_decision_attempted = false;
next_action = CASE_TERMINATED.
```

It excludes chain and self-digest fields:

```text
stage_attempt_digest;
stage_record_digest;
previous_chain_digest;
trace_chain_digest_after_stage;
trace_chain_digest_after_failure.
```

`stage_record_digest = SHA256(canonical StageRecordCoreFinal)`.

For PASS, `StageRecordCoreFinal` has:

```text
status = PASS;
failure_anchor_digest = null;
failure_capture_digest = null;
next_action = ADVANCE or terminal S12 stop;
no failure diagnostics.
```

### 3.6 Independent verification

A verifier must:

```text
1 recompute StageAttemptCore digest;
2 recompute FailureAnchorCore digest and compare FailureCapture.failure_anchor_digest;
3 recompute FailureCapture digest and compare StageRecordCoreFinal.failure_capture_digest;
4 recompute StageRecordCoreFinal digest and compare StageRecordFull.stage_record_digest;
5 verify one-to-one anchor/capture/stage association;
6 verify no duplicate failure capture.
```

Any mismatch is `INVALID_FAILURE_BINDING`.

## 4. R3 — complete trace-chain algorithm

### 4.1 Canonical serialization

Canonical JSON:

```text
UTF-8;
ensure_ascii=false;
sort_keys=true;
separators=(",",":");
no trailing newline;
object keys only; no language-specific types.
```

All SHA-256 output is lowercase 64-hex.

### 4.2 Per-case genesis

Each case has an independent chain.

```text
genesis_message =
  UTF8("D002-ADAPTER-STAGE-CHAIN-V4|GENESIS|" + trace_id + "|" + case_id);
genesis_chain_digest = SHA256(genesis_message).
```

The chain is never shared across cases or traces.

### 4.3 Stage update

For each entered stage:

```text
previous_chain_digest =
  genesis_chain_digest for S0;
  prior trace_chain_digest_after_stage for a prior PASS.
```

A FAIL terminates the case, so no stage follows a failed stage.

`StageRecordCoreFinal` excludes:

```text
stage_attempt_digest;
stage_record_digest;
previous_chain_digest;
trace_chain_digest_after_stage;
trace_chain_digest_after_failure.
```

Compute:

```text
stage_record_digest =
  SHA256(canonical(StageRecordCoreFinal)).

stage_chain_message =
  UTF8(previous_chain_digest_hex)
  || 0x00
  || UTF8(stage_record_digest_hex)
  || 0x00
  || canonical(StageRecordCoreFinal).

trace_chain_digest_after_stage =
  SHA256(stage_chain_message).
```

`StageRecordFull` contains `StageRecordCoreFinal` plus:

```text
stage_record_digest;
previous_chain_digest;
trace_chain_digest_after_stage;
trace_chain_digest_after_failure = null for PASS;
trace_chain_digest_after_failure = actual value for FAIL.
```

### 4.4 FailureCapture chain update

For FAIL only, after `trace_chain_digest_after_stage`:

```text
failure_chain_message =
  UTF8(trace_chain_digest_after_stage_hex)
  || 0x00
  || UTF8(failure_capture_digest_hex)
  || 0x00
  || canonical(FailureCapture).

trace_chain_digest_after_failure =
  SHA256(failure_chain_message).
```

For PASS:

```text
trace_chain_digest_after_failure = null.
```

The terminal chain digest is:

```text
trace_chain_digest_after_failure for early FAIL;
trace_chain_digest_after_stage for PASS at S12.
```

### 4.5 Chain validation

For each entered stage:

```text
1 sequence must be prior sequence + 1;
2 previous_stage_record_digest must equal prior full record digest;
3 previous_chain_digest must equal prior terminal chain digest;
4 stage_record_digest must recompute from StageRecordCoreFinal;
5 trace_chain_digest_after_stage must recompute;
6 FAIL must have valid anchor/capture and after-failure chain;
7 PASS must have null failure fields and null after-failure chain;
8 no duplicate stage_id/sequence;
9 no fork or alternative successor;
10 terminal chain must match declared completion state.
```

Invalid classes:

```text
CHAIN_GENESIS_INVALID;
CHAIN_SEQUENCE_INVALID;
CHAIN_PREDECESSOR_INVALID;
CHAIN_DIGEST_INVALID;
CHAIN_FORK_DETECTED;
CHAIN_DUPLICATE_STAGE;
CHAIN_MISSING_TERMINAL_FAILURE;
CHAIN_MISSING_SUCCESS_TERMINUS;
CHAIN_AFTER_FAIL_CONTINUATION.
```

## 5. R4 — universal pre-read path guard

### 5.1 Scope

The guard applies before every file/stat/open/read of any path used in:

```text
S1–S12,
including D001 candidate paths, fixture objects, manifests, retained inventory,
snapshot bindings, evidence destinations, and correction/reference paths.
```

It applies to fixture paths and non-fixture paths.

### 5.2 Mandatory order

No path content may be read until all pass:

```text
PG-1 lexical path check;
PG-2 approved-root containment;
PG-3 each path component symlink/type check;
PG-4 final target type check;
PG-5 approved-read confirmation;
PG-6 TOCTOU-resistant open;
PG-7 opened-descriptor revalidation;
PG-8 content read and digest verification.
```

### 5.3 PG-1 lexical path check

Before touching the filesystem:

```text
path is nonempty;
path is repository-relative;
path uses "/" only;
path has no "", ".", "..", backslash, drive letter, URI prefix, or NUL;
path has no leading "/".
```

Failure:

```text
PATH_GUARD_LEXICAL_REJECTION;
no stat/open/read.
```

### 5.4 PG-2 containment

Resolve the lexical path against the exact approved root without filesystem
follow:

```text
resolved = approved_root + "/" + relative_path;
resolved must remain inside approved_root;
approved_root must itself be the registered frozen path.
```

Failure:

```text
PATH_GUARD_CONTAINMENT_REJECTION;
no stat/open/read.
```

### 5.5 PG-3/PG-4 symlink and type checks

Check every component and the final target:

```text
no component is a symlink;
final target is a regular file unless the stage explicitly approves a directory;
no device, FIFO, socket, or special file;
no hard-link policy bypass outside the approved root.
```

Failure:

```text
PATH_GUARD_SYMLINK_REJECTION; or
PATH_GUARD_FILE_TYPE_REJECTION.
```

No content read.

### 5.6 PG-5 approved-read confirmation

The stage must have explicitly approved:

```text
root;
relative path class;
purpose;
expected digest when frozen.
```

Failure:

```text
PATH_GUARD_NOT_APPROVED_REJECTION.
```

### 5.7 PG-6 TOCTOU-resistant open

The implementation design must require:

```text
open relative to the approved directory descriptor;
O_NOFOLLOW on the final component;
no path-based reopen after open;
fail if any component changes type or identity during open.
```

Failure:

```text
PATH_GUARD_OPEN_REJECTION.
```

### 5.8 PG-7 opened-descriptor revalidation

After open, verify through the descriptor:

```text
still regular file;
still within approved root policy;
identity/digest matches frozen expectation when bound.
```

Failure:

```text
PATH_GUARD_DESCRIPTOR_REJECTION.
```

### 5.9 PG-8 content digest

Only now may content be read:

```text
compute SHA-256;
compare to frozen digest when present;
reject mismatch without semantic interpretation.
```

Failure:

```text
PATH_GUARD_CONTENT_DIGEST_REJECTION.
```

### 5.10 Failure evidence

Path guard failure creates:

```text
PATH_GUARD_FAILURE_RECORD
```

with:

```text
stage_id;
sequence;
approved_root;
relative_path;
guard_step;
rejection_class;
lexical_normalized_path;
no_content_digest when rejected before read;
next_action = CASE_TERMINATED.
```

It must not continue reading the rejected path to gather more diagnostics.

## 6. Updated stage mapping

| Stage | Path guard scope | Notes |
| --- | --- | --- |
| S0 | governance/manifest paths only | baseline no D001 execution |
| S1 | sealed snapshot and retained fixture metadata | audit selection only |
| S2 | sealed source/snapshot bindings | read-only verify_existing |
| S3 | retained fixture manifests and R-I objects | all guarded |
| S4 | retained fixture representation objects | all guarded |
| S5 | retained auxiliary mapping record | no EXPECTED into causal lane |
| S6 | retained representation and translated candidates | no D001 execution |
| S7 | translated closure candidate | digest materialization |
| S8 | translated non-invocation wrappers | all paths guarded |
| S9 | run manifest/invocation and final I6 | all paths guarded |
| S10 | finalized candidates only | resolved assembly |
| S11 | resolved candidate references | association audit |
| S12 | handoff request preparation record only | no D001 execution |

## 7. D001 code identity carried forward

| File | Content SHA-256 | Git blob ID |
| --- | --- | --- |
| `schemas.py` | `a226522c60bb4352494d01992f09c34f546e56839c19de64440ec40449296216` | `e0c82604e1f58b08a8578329593c92f7a3bf9399` |
| `inventory.py` | `39508edee8826e9728d48ccb4f8a7c430890c7b5349d1424aaf10a756c071a27` | `69508cd64243f01e5e2e4425b98b01340957160e` |
| `reconstruction.py` | `78af949080c48a8ae01e015cded42464c4e970f94470e2c305e825b7b2c95b41` | `a249834d3c48073517dbe321adbc4b8aa20d9bd1` |
| `continuation.py` | `c4af004dbb8993cbaee40b145a95ae41c185e63d34316c574f85c2a3cb98038b` | `adf4428c1968534107bc33b3bc7400a811c4f3ca` |
| `carrier.py` | `b377e8b5a933d5f9e4b3859f1dd0716be6d42df4634429c2378251c45f286e2e` | `1426a231d8eb312659eb8a843f880e2a944243ca` |

## 8. Acceptance criteria

Human review should accept v1.4 only if:

```text
1 records are required only for entered stages and early-failure chains are valid;
2 FailureAnchorCore/FailureCapture/StageRecord binding is non-circular and independently verifiable;
3 the full trace-chain algorithm, genesis, update, failure update, and invalid classes are in this Package;
4 universal path guards precede every path read in S1–S12;
5 accepted v1.3 boundaries remain unchanged;
6 no implementation/execution/campaign/mutation/evidence rewrite is authorized.
```

## 9. Decision requested

Human review must return exactly one ruling:

```text
ACCEPT   freeze v1.4 design only;
REVISE   require a v1.5 design revision;
REJECT   close this instrumentation/redesign pathway.
```

ACCEPT does not authorize implementation, dry materialization, validation,
D001 handoff, observer, campaign, mutation, or equivalence claims.
