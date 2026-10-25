# D-002 Replay-Adapter Instrumentation / Redesign Authorization Package v1.6

> **Status:** REVISED FOR HUMAN REVIEW — LIMIT-OF-SCOPE DESIGN CORRECTION  
> **Date:** 2026-10-09  
> **Package ID:** `INTEGRATED-ES-PALACE-D002-INSTRUMENTATION-REDESIGN-AUTH-PACKAGE-V1.6`  
> **Supersedes:** v1.5 = REVISE / retained immutable  
> **Canonical base:** `8ac4c0a5f50aeb1e564e0bc7b28bca986fee4ac4`  
> **implementation:** NOT AUTHORIZED  
> **dry materialization:** NOT AUTHORIZED  
> **validation execution:** NOT AUTHORIZED  
> **D-002 rerun / repair-run / new campaign:** NOT AUTHORIZED  
> **D-001 decide() / observer execution:** NOT AUTHORIZED  
> **D-001 handoff:** NOT AUTHORIZED  
> **canonical / PALACE mutation:** NOT AUTHORIZED  
> **evidence overwrite:** FORBIDDEN

## 0. Limit-of-scope revision

v1.6 corrects only three contradictions in v1.5:

```text
R1 PASS-chain predecessor ambiguity;
R2 TerminationWitness-only closure when primary evidence is unavailable;
R3 PATH_IDENTITY_NOT_FROZEN classification.
```

No new observation layer, digest layer, security mechanism, stage, or general
schema is introduced. v1.0–v1.5 remain write-once and retained.

## 1. Retained v1.5 boundaries

```text
D-001 Decision Core       = CLOSED / BOUNDED PASS / READ-ONLY;
D-002                     = FAIL / STOP;
D-002 Postmortem          = COMPLETE / FROZEN;
implementation            = NOT AUTHORIZED;
dry materialization       = NOT AUTHORIZED;
validation execution      = NOT AUTHORIZED;
D-002 rerun/repair-run    = FORBIDDEN;
new campaign              = NOT AUTHORIZED;
D-001 decide()            = NOT AUTHORIZED;
observer execution        = NOT AUTHORIZED;
D-001 handoff             = NOT AUTHORIZED;
canonical/PALACE mutation = NOT AUTHORIZED;
evidence overwrite        = FORBIDDEN.
```

Also retained:

```text
entered-stage StageRecord completeness;
FailureAnchorCore before FailureCapture;
comparator-only EXPECTED vectors;
read-only sealed snapshot verification;
S1 selection by embedding_metadata.id;
S0–S12 order;
component-descriptor path opening.
```

## 2. R1 — PASS chain predecessor corrected

### 2.1 Rule

For every stage after S0:

```text
previous_chain_digest =
  prior trace_chain_digest_after_stage.
```

This rule has no exception. Only a PASS stage can have a successor because every
FAIL immediately terminates the case.

### 2.2 PASS predecessor

For `stage_sequence = N > 0`:

```text
previous_chain_digest =
  Stage N-1.trace_chain_digest_after_stage.
```

Example:

```text
S0 PASS trace_chain_digest_after_stage = C0;
S1 previous_chain_digest = C0.
```

### 2.3 FAIL terminal predecessor

For a FAIL at stage N:

```text
previous_chain_digest =
  Stage N-1.trace_chain_digest_after_stage.

trace_chain_digest_after_stage =
  computed normally for the failed stage.

failure_chain_digest_after_capture =
  computed from FailureCapture or TerminationWitness.

terminal_chain_digest =
  trace_chain_digest_after_failure.
```

No successor follows a FAIL. No later stage may cite
`trace_chain_digest_after_failure`.

### 2.4 Valid chain patterns

```text
COMPLETE_SUCCESS:
  S0 PASS → S1 PASS → ... → S12 PASS
  every N>0 uses prior after_stage chain;
  terminal chain = S12 after_stage.

COMPLETE_EARLY_FAILURE:
  S0 PASS → ... → S(N) FAIL
  S(N) uses prior after_stage chain for stage update;
  S(N) computes after_capture chain;
  terminal chain = S(N) after_capture chain;
  no S(N+1)..S12 records.

INVALID:
  PASS after FAIL;
  successor citing after_capture chain;
  missing terminal FAIL capture/witness;
  forked or duplicated chain.
```

## 3. R2 — TerminationWitness-only closure

### 3.1 Two legal FAIL closures

A FAIL case must close in exactly one mode:

```text
MODE A PRIMARY_FAILURE_CAPTURE_CLOSED
  Primary channel successfully stores FailureCapture;
  StageRecordCoreV5 exists in primary channel;
  StageRecordCore.failure_evidence_kind = FAILURE_CAPTURE;
  StageRecordCore.failure_capture_digest = valid FailureCapture digest;
  terminal chain = failure_chain_digest_after_capture.

MODE B WITNESS_ONLY_TERMINATION_CLOSED
  Primary channel is unavailable or fails before/during closure;
  no complete StageRecordCore is required in primary;
  Independent TerminationWitness is the terminal object;
  primary chain is explicitly marked INCOMPLETE_PRIMARY_CHAIN;
  terminal chain = witness terminal chain.
```

MODE B does not fabricate, reconstruct, or relocate a StageRecordCore.

### 3.2 Witness-only trigger

Enter MODE B when any of:

```text
PRIMARY_CHANNEL_UNAVAILABLE;
PRIMARY_WRITE_FAILURE;
PRIMARY_FSYNC_FAILURE;
PRIMARY_VERIFY_FAILURE;
FAILURE_ANCHOR_WRITE_FAILURE;
FAILURE_CAPTURE_WRITE_FAILURE;
STAGE_RECORD_CORE_WRITE_FAILURE.
```

### 3.3 WITNESS_ONLY_TERMINATION object

The independent witness object has exactly:

```text
schema_id = D002-WITNESS-ONLY-TERMINATION-V2;
trace_id;
case_id;
source_embedding_metadata_id;
stage_id;
stage_sequence;
prior_stage_core_digest or null;
prior_chain_digest or null;
stage_attempt_digest or null;
failure_anchor_digest or null;
failure_class;
failure_evidence_state;
termination_trigger;
primary_channel_state =
  AVAILABLE | UNAVAILABLE | WRITE_FAILED | FSYNC_FAILED | VERIFY_FAILED |
  PARTIAL_WRITE | UNVERIFIABLE;
primary_stage_record_state =
  ABSENT | PARTIAL | PRESENT_UNTRUSTED;
raw_payload_sha256 or null;
raw_payload_byte_size or null;
normalized_payload_sha256 or null;
failure_capture_digest or null;
witness_created_at_utc;
witness_digest;
semantic_interpretation = null;
semantic_decision = null;
d001_executed = false;
observer_executed = false;
next_action = CASE_TERMINATED.
```

Constraints:

```text
witness_digest = SHA256(canonical witness object with witness_digest omitted);
failure_anchor_digest may be null only when its write failed or was unreachable;
if StageRecordCore exists but cannot be verified, its digest may be recorded only
as `PRESENT_UNTRUSTED` metadata and must not become predecessor authority;
all digest fields are lowercase 64-hex or null;
semantic interpretation and decision remain null.
```

### 3.4 Independent verifier rule

The verifier accepts MODE B only if:

```text
1 the witness object exists and digest-verifies;
2 termination_trigger is one of the frozen MODE B triggers;
3 primary_stage_record_state is recorded;
4 no complete primary StageRecordCore is treated as authoritative unless its
   digest independently verifies and the witness marks PRESENT_UNTRUSTED;
5 no post-hoc reconstruction is used.
```

Result:

```text
WITNESS_ONLY_TERMINATION_CLOSED
```

If the expected witness object is absent, malformed, digest-invalid, or the
frozen witness channel cannot prove its prior reservation, the verifier returns:

```text
EVIDENCE_CAPTURE_UNVERIFIABLE.
```

It must not reconstruct a complete chain.

### 3.5 Primary-chain status

MODE B records:

```text
primary_chain_status = INCOMPLETE_PRIMARY_CHAIN;
primary_chain_recovery = FORBIDDEN_WITHOUT_NEW_AUTHORIZATION.
```

This is a valid terminal outcome. It does not become a complete D002 chain and
does not support any broader claim.

## 4. R3 — PATH_IDENTITY_NOT_FROZEN closure

### 4.1 Classification

`PATH_IDENTITY_NOT_FROZEN` is a formal path-guard rejection, not an allowed
audit-only state.

```text
failure_class = PATH_GUARD_REJECTION;
path_guard_rejection_class = PATH_GUARD_IDENTITY_NOT_FROZEN_REJECTION.
```

### 4.2 Trigger

Reject when a required component identity is absent from the frozen path-identity
manifest, ambiguous, or does not bind both `st_dev` and `st_ino`.

Conservative rule: implementation manifests may not mark unfrozen component
identity as allowed.

### 4.3 Precedence

Within path-guard checks:

```text
1 lexical rejection;
2 containment rejection;
3 component symlink rejection;
4 component type rejection;
5 identity-not-frozen rejection;
6 component identity mismatch rejection;
7 not-approved rejection;
8 open rejection;
9 descriptor identity rejection;
10 hard-link rejection;
11 content-digest rejection.
```

### 4.4 Failure record

```text
failure_class = PATH_GUARD_REJECTION;
path_guard_rejection_class = PATH_GUARD_IDENTITY_NOT_FROZEN_REJECTION;
stage_id;
stage_sequence;
approved_root;
relative_path;
component_index;
component_name;
expected_identity = ABSENT;
actual_lstat_identity;
no_content_digest = true;
next_action = CASE_TERMINATED.
```

No path content is read after this rejection.

## 5. Updated chain table

| Prior stage | Current stage | `previous_chain_digest` | Terminal behavior |
| --- | --- | --- | --- |
| S0..S11 PASS | next S stage | prior `trace_chain_digest_after_stage` | continue |
| any stage | same-stage FAIL | prior `trace_chain_digest_after_stage` for stage update | terminal `after_capture` chain |
| — | witness-only MODE B | prior stage Core/chain recorded if available | witness terminal chain; primary incomplete |

No FAIL successor is valid.

## 6. Acceptance criteria

Human review should accept v1.6 only if:

```text
1 PASS successors cite prior after_stage chain;
2 FAIL never has a successor and terminal chain uses after_capture;
3 witness-only termination is independently verifiable without primary;
4 primary incomplete chain is retained as incomplete, not reconstructed;
5 unfrozen component identity is a formal path-guard rejection;
6 no scope expansion or implementation/execution authorization exists.
```

## 7. Decision requested

Human review must return exactly one ruling:

```text
ACCEPT   freeze v1.6 design only;
REVISE   require a v1.7 limit-of-scope correction;
REJECT   close this instrumentation/redesign pathway.
```

ACCEPT does not authorize implementation, dry materialization, validation,
D001 handoff, observer, campaign, mutation, or equivalence claims.
