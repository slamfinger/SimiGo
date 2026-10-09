# D-002 Replay-Adapter Instrumentation / Redesign Authorization Package v1.2

> **Status:** REVISED FOR HUMAN REVIEW — DESIGN ONLY
> **Date:** 2026-10-09
> **Package ID:** `INTEGRATED-ES-PALACE-D002-INSTRUMENTATION-REDESIGN-AUTH-PACKAGE-V1.2`
> **Supersedes:** v1.1 = REVISE / retained immutable
> **Canonical base:** `5922dc77638cc280577333d819c5cbea2215d29e`
> **implementation:** NOT AUTHORIZED
> **dry materialization:** NOT AUTHORIZED
> **validation execution:** NOT AUTHORIZED
> **D-002 rerun / repair-run / new campaign:** NOT AUTHORIZED
> **D-001 decide() / observer execution:** NOT AUTHORIZED
> **canonical / PALACE mutation:** NOT AUTHORIZED
> **evidence overwrite:** FORBIDDEN

## 0. Revision purpose

v1.2 answers the Human REVISE ruling by closing four contract gaps without
changing code or sealed evidence:

```text
R1 strictly separate historical static audit, active failure capture, and future D001 handoff;
R2 make EXPECTED vectors comparator-only and exclude them from causal input materialization;
R3 make snapshot verification read-only and place snapshot creation/replacement out of scope;
R4 define digest generation versus verification, nested exact-field contracts,
   deterministic trace-chain encoding, and all five D001 code identities.
```

v1.0 and v1.1 remain retained. Neither is rewritten.

## 1. Non-negotiable execution boundary

This Package designs future instrumentation only. It does not authorize:

```text
D-002 execution;
D-002 rerun or repair-run;
new campaign;
D-001 decide() execution;
observer execution;
implementation mutation;
PALACE source/snapshot mutation;
canonical IS mutation;
evidence rewrite.
```

Three lanes are strictly separated:

```text
LANE H — HISTORICAL STATIC AUDIT
  read-only analysis of sealed Attempt-003 evidence and retained source.

LANE F — FUTURE FAILURE CAPTURE
  active terminal evidence emission designed for a separately authorized run.

LANE D — D001 HANDOFF
  future separately authorized execution boundary; never a diagnostic route.
```

No Lane may impersonate another.

## 2. R1 — execution boundary and S13 correction

### 2.1 Historical S13 correction

S13 must not map to `decision_replay.py::replay`. That function invokes D001
`decide()` and is outside this design's authority.

S13 is redefined as:

```text
S13 = HISTORICAL_FALLBACK_STATIC_AUDIT
```

Its only inputs are:

```text
sealed Attempt-003 DECISION_REPLAY_RECORD.json;
retained decision_replay.py source at execution commit `ed3985d6`;
retained D001 continuation.py/reconstruction.py/schemas.py at frozen hashes;
retained D002 fixtures and expected vectors.
```

Its only outputs are:

```text
static control-flow analysis;
sealed fallback record analysis;
source-to-fallback path reconstruction;
missing-instrumentation findings.
```

It must not:

```text
execute replay();
call decide();
construct a new ReplayInventory for execution;
produce a new D001 fallback observation;
claim a newly observed D001 result.
```

### 2.2 Active failure capture is terminal, not a later stage

Every active stage S0–S12 emits a `StageRecord` immediately. If the stage fails,
the same terminal transition emits a `FailureCapture` and stops that case.

```text
stage success → StageRecord(PASS) → next stage only if authorized;
stage failure → StageRecord(FAIL) + FailureCapture → CASE_TERMINATED.
```

FailureCapture is part of the failing stage's terminal transition. It is not S13
and does not permit later stages.

### 2.3 D001 handoff is separate

Future D001 handoff is Lane D and remains outside this design. It requires a new
explicit authorization record and must never be used as an observation mechanism.

## 3. R2 — EXPECTED isolation and causal lane correction

### 3.1 Existing implementation classification

The retained function:

```text
typed_mapping.py::map_fixtures
```

is classified:

```text
NON_CAUSAL_AUXILIARY_MAPPING_RECORD_PATH.
```

Reason:

```text
it reads fixture["expected"]["continuation_class"] while constructing
ESContinuationInput; therefore it must not be represented as the causal path
from PALACE to D001 input.
```

It may remain only as a historical auxiliary record generator. It must not be
used by the future causal materializer.

### 3.2 Required lane separation

```text
CAUSAL MATERIALIZATION LANE
  real PALACE-derived representation
    → retained fixture representation
    → D002-to-D001 wrapper translation
    → digest materialization
    → D001 schema preflight
    → resolved input candidate

COMPARATOR LANE
  frozen EXPECTED vectors
    → independent post-observation comparator only
```

EXPECTED vectors must not enter:

```text
causal mapping;
wrapper translation;
field defaulting;
digest generation;
schema completion;
continuation-class selection;
resolved input assembly;
D001 handoff.
```

The future causal materializer's interface must not accept:

```text
EXPECTED.json;
expected vector objects;
expected decision;
expected continuation_class;
expected precedence_reason.
```

Comparator may read EXPECTED only after observed output exists.

## 4. R3 — snapshot and fixture selection read-only boundary

### 4.1 Snapshot verification only

S2 is limited to:

```text
source_snapshot.py::verify_existing
```

The following are out of scope:

```text
source_snapshot.py::snapshot;
snapshot creation;
temporary snapshot generation;
os.replace onto PALACE_SNAPSHOT.sqlite;
snapshot replacement;
snapshot deletion;
WAL/SHM checkpoint or mutation.
```

The existing sealed snapshot is:

```text
integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite;
SHA256 = 8b3856e2e4e3a1bd87580afc1ab42094e9a952e0985952323e02ae6595ce1444.
```

Future S2 must open it only with:

```text
SQLite URI mode=ro&immutable=1;
PRAGMA query_only=ON;
PRAGMA trusted_schema=OFF.
```

It may run `PRAGMA integrity_check`, count allowed tables, and bind sidecar
state. It must not write, checkpoint, migrate, replace, or regenerate.

If source or snapshot digest drifts, S2 emits FailureCapture and stops.

### 4.2 Fixture selection audit

The historical selector used:

```text
SELECT DISTINCT id
FROM embedding_metadata
ORDER BY id
LIMIT 7.
```

The identifier is the SQLite `embedding_metadata.id` column. The design must not
rename it `internal_id` in the source-selection contract. `internal_id` may exist
only as a downstream representation alias after selection.

S1 audits that retained source IDs remain:

```text
1,2,3,4,5,6,7
```

in that `embedding_metadata.id` order. It must not regenerate fixtures, replace
fixtures, re-query PALACE, or alter ordering.

## 5. R4 — deterministic digest and schema contracts

### 5.1 Canonical serialization

All structured digests use:

```text
UTF-8;
JSON object keys sorted lexicographically;
ensure_ascii=false;
separators comma and colon;
no insignificant whitespace;
no trailing newline.
```

SHA-256 output is lowercase 64-hex.

### 5.2 Digest materialization versus verification

Historical Attempt-003 adapter behavior:

```text
ReplayInventory.read("I1") materialized `closure_digest`
from translated schema_id, closure_id, closure_revision, and members;
D001 reconstruction independently verified that digest by recomputation.
```

Future design must separate:

```text
S6 WrapperTranslation:
  emits TranslatedClosureCandidate WITHOUT `closure_digest`.

S7 Closure Digest Materialization:
  computes and attaches `closure_digest`.

S8 D001 Exact-Field Preflight:
  validates the already-materialized object and recomputes digest independently.
```

S8 must not generate a missing digest. A missing digest at S8 is:

```text
D001_PREFLIGHT_MISSING_FIELD.
```

### 5.3 D001 implemented checks versus adapter ingress checks

The future preflight must record which layer imposed each rule.

#### 5.3.1 I1

D001 implemented checks:

```text
top-level exact fields:
  schema_id,closure_id,closure_revision,members,closure_digest;
schema_id = LAWFUL-INFORMATION-CLOSURE-D001-V1;
closure_digest = SHA256(canonical JSON of
  schema_id,closure_id,closure_revision,members).
```

Adapter ingress additions:

```text
closure_id and closure_revision are nonempty strings;
members is an array with unique nonempty object_id values;
each member has exactly:
  object_id,digest,path,authority;
digest is lowercase 64-hex;
authority is boolean;
path is a safe repository-relative path with no `..`, absolute prefix, backslash,
or symlink component.
```

#### 5.3.2 I3

D001 implemented checks in the positive path:

```text
top-level exact fields:
  schema_id,closure_id,approved_read,settled_record;
schema_id = CARRIER-SNAPSHOT-D001-V1;
approved_read = true;
closure_id matches closure;
REUSE requires settled_record to contain matching
  continuation_output_digest and continuation_identity_digest.
```

Adapter ingress additions:

```text
settled_record is an object;
empty settled_record means CONTINUE;
nonempty REUSE settled_record has exactly:
  source_record_digest,continuation_identity_digest,continuation_output_digest;
all three digests are lowercase 64-hex.
```

#### 5.3.3 I4

D001 implemented checks:

```text
top-level exact fields:
  schema_id,records;
schema_id = PROVENANCE-REVISION-D001-V1;
records contains an entry for every closure member;
each record has revision,status,provenance_digest.
```

Adapter ingress additions:

```text
records is an object, not array;
record keys are unique and exactly match closure member object_id values;
each record has exactly:
  revision,status,provenance_digest;
revision is nonempty;
status = CURRENT | SUPERSEDED;
provenance_digest is lowercase 64-hex.
```

#### 5.3.4 I5

D001 implemented checks:

```text
top-level exact fields:
  schema_id,actions;
schema_id = NEXT-ACTION-D001-V1;
actions is an array;
later semantic precedence uses status, action cardinality, boundary digest,
blocking condition, and carrier state.
```

Adapter ingress additions:

```text
each action object has exactly:
  action_id,target_digest,boundary,boundary_digest,continuation_class;
BLOCKED_LAWFUL_CONTINUATION also has exactly:
  blocking_condition = REGISTERED_BLOCK;
action_id nonempty and unique;
target_digest and boundary_digest lowercase 64-hex;
continuation_class in the D001 enum;
boundary is `D002-PACKAGE-V1.0` for registered cases or `ILLEGAL` for the
N-ILLEGAL retained fixture.
```

#### 5.3.5 I6

D001 implemented checks:

```text
top-level exact fields:
  schema_id,manifest_instance_id,package_id,stage,schema_version,opaque_locator;
schema_id = APPROVED-INVOCATION-D001-V1.
```

Adapter ingress additions:

```text
all six values are nonempty strings;
manifest_instance_id is UUIDv4;
package_id = INTEGRATED-ES-PALACE-D002-IS-CONSUMPTION-AUTH-PACKAGE-V1.0;
stage = D002_CONSUMPTION;
schema_version = D002-CONSUMPTION-MANIFEST-V1;
opaque_locator matches `d002://snapshot/embedding/<positive_integer>`.
```

#### 5.3.6 I8

D001 implemented checks:

```text
top-level exact fields:
  schema_id,input,output;
schema_id = APPROVED-SCHEMAS-D001-V1;
input = ES-CONTINUATION-INPUT-D001-V1;
output = ES-CONTINUATION-OUTPUT-D001-V1.
```

Adapter ingress additions:

```text
all values are nonempty strings;
no extra fields;
input and output differ.
```

#### 5.3.7 I10

D001 implemented checks:

```text
top-level exact fields:
  schema_id,objects;
schema_id = APPROVED-EVIDENCE-DESTINATIONS-D001-V1;
objects is an array.
```

Adapter ingress additions:

```text
objects exactly equals:
  RUN_MANIFEST_INSTANCE.json;
  DECISION_REPLAY_RECORD.json;
  EXPERIMENT_RECORD.json;
  CARRIER_LIFECYCLE_RECORD.json;
  OBSERVER_RECORD.json;
  RECONCILIATION_RECORD.json;
  CLAIM_RECORD.json;
  EVIDENCE_SHA256SUMS;
all entries are unique nonempty `.json` or `SHA256SUMS` names;
order equals the frozen order above.
```

### 5.4 Rejection precedence

Preflight records all defects but selects first fault in this order:

```text
1 missing field;
2 extra field;
3 schema-id mismatch;
4 JSON/type rejection;
5 enum/value rejection;
6 digest rejection;
7 cardinality/association rejection;
8 path-safety rejection.
```

Preflight never repairs, coerces, defaults, or semantically interprets.

## 6. Stage mapping v1.2

| Stage | Purpose | Bound implementation or future design object | Input | Output | PASS | FAIL / termination |
| --- | --- | --- | --- | --- | --- | --- |
| S0 | baseline verification | `campaign.py::git`, `digest_bytes`, `manifest_adapter_closure`; future `BaselineVerifier` | manifest, HEAD, origin/main, baselines | S0 record | clean, canonical, all gates pass | any drift ⇒ FailureCapture → stop |
| S1 | retained source-selection audit | historical `primitive_inventory.py::ordered_records`; future `RetainedSelectionAuditor` | sealed snapshot, retained fixture IDs | selection audit record | IDs remain 1–7 in `embedding_metadata.id` order | drift/regeneration need ⇒ stop |
| S2 | existing snapshot verification | `source_snapshot.py::verify_existing` only | source and snapshot digests, SQLite allowed tables | read-only snapshot record | digests, integrity, logical counts pass | drift, write attempt, integrity failure ⇒ stop |
| S3 | primitive inventory audit | `primitive_inventory.py::load_existing` | retained manifests | R-I inventory record | R-I1..R-I10 resolve and match digests | missing/extra/drift ⇒ stop |
| S4 | fixture representation audit | retained fixture files | closure/provenance/actions/invocation/carrier/schemas/destinations | representation record | all retained objects parse and match digests | malformed/symlink/path escape ⇒ stop |
| S5 | auxiliary mapping record audit | `typed_mapping.py::map_fixtures`, classified non-causal | retained mapping record and EXPECTED | classification record | historical behavior documented | EXPECTED enters causal lane ⇒ stop |
| S6 | causal wrapper translation | future `CausalWrapperTranslator`; historical `ReplayInventory.read` for static comparison | real-source retained representation | translated I1/I3/I4/I5/I6/I8/I10 candidates; closure digest absent | every field has source provenance or explicit MISSING | undeclared semantic fallback ⇒ stop |
| S7 | closure digest materialization | future `ClosureDigestMaterializer` | translated closure candidate without digest | translated closure with digest | deterministic D001 digest generated | malformed payload ⇒ stop |
| S8 | D001 exact-field preflight | future `D001ExactFieldPreflight` | all translated/materialized candidates | preflight record | exact fields, types, digests, cardinality pass | first-fault rejection ⇒ FailureCapture → stop |
| S9 | invocation materialization | future `InvocationMaterializer`; historical I6 path for static comparison | run manifest and retained invocation | D001 I6 candidate | six exact fields materialized without EXPECTED | missing package binding ⇒ stop |
| S10 | resolved input assembly | future `ResolvedInputAssembler` | S6–S9 causal outputs only | resolved `ESContinuationInput` candidate | no unresolved mandatory candidate | unresolved ⇒ stop |
| S11 | pre-decision validation | future `ResolvedInputPreflight` | resolved candidate | validation record | D001 shape/type/digest preflight passes | rejection ⇒ stop |
| S12 | D001 handoff request | future separate `D001HandoffBoundary` | preflight-passed input only | handoff request record | separate Human authorization exists | absent authorization ⇒ NOT_AUTHORIZED stop |
| S13 | historical fallback static audit | sealed evidence plus retained source; not `replay()` | Attempt-003 record and frozen code | historical audit record | static path documented without execution | any execution attempt ⇒ stop |

FailureCapture is not a sequential stage. It is emitted by the failing stage and
closes the case.

## 7. FailureCapture contract

Required fields:

```text
schema_id = D002-ADAPTER-FAILURE-CAPTURE-V2;
trace_id;
case_id;
source_embedding_metadata_id;
failing_stage_id;
stage_sequence;
status = FAIL;
failure_class;
input_binding;
translated_representation_digest;
expected_d001_schema_id;
missing_fields[];
extra_fields[];
type_errors[];
value_errors[];
digest_errors[];
exception_type;
exception_message_raw_sha256;
exception_message_normalized;
exception_message_normalized_sha256;
stack_frame_digests[];
raw_payload_sha256;
raw_payload_byte_size;
raw_payload_reference;
previous_stage_record_digest;
stage_record_digest;
trace_chain_digest_after_failure;
d001_core_sha256_set;
d002_implementation_sha256_set;
next_action = CASE_TERMINATED;
semantic_decision_attempted = false;
d001_executed = false.
```

FailureCapture never invokes D001, repairs input, chooses a semantic decision, or
continues the sequence.

## 8. Deterministic trace-chain encoding

### 8.1 Canonical encoding

For every stage record:

```text
canonical_bytes =
  UTF-8(
    JSON(
      StageRecord,
      ensure_ascii=false,
      sort_keys=true,
      separators=(",",":"),
      no trailing newline
    )
  ).
```

### 8.2 Genesis

```text
genesis_ascii = "D002-ADAPTER-STAGE-CHAIN-V2";
genesis_chain_digest =
  SHA256(UTF-8(genesis_ascii)).
```

### 8.3 Chain update

For each stage:

```text
stage_record_digest = SHA256(canonical_bytes);
chain_input =
  ASCII(previous_chain_digest)
  + 0x00
  + canonical_bytes;
trace_chain_digest_after_stage =
  SHA256(chain_input).
```

For a failed stage:

```text
failure_capture_digest = SHA256(canonical FailureCapture);
failure_chain_input =
  ASCII(trace_chain_digest_after_stage)
  + 0x00
  + canonical FailureCapture;
trace_chain_digest_after_failure =
  SHA256(failure_chain_input).
```

No other serialization is conformant.

## 9. D001 code identity binding

All five D001 files must bind both content SHA-256 and Git blob ID.

| File | Content SHA-256 | Git blob ID |
| --- | --- | --- |
| `schemas.py` | `a226522c60bb4352494d01992f09c34f546e56839c19de64440ec40449296216` | `e0c82604e1f58b08a8578329593c92f7a3bf9399` |
| `inventory.py` | `39508edee8826e9728d48ccb4f8a7c430890c7b5349d1424aaf10a756c071a27` | `69508cd64243f01e5e2e4425b98b01340957160e` |
| `reconstruction.py` | `78af949080c48a8ae01e015cded42464c4e970f94470e2c305e825b7b2c95b41` | `a249834d3c48073517dbe321adbc4b8aa20d9bd1` |
| `continuation.py` | `c4af004dbb8993cbaee40b145a95ae41c185e63d34316c574f85c2a3cb98038b` | `adf4428c1968534107bc33b3bc7400a811c4f3ca` |
| `carrier.py` | `b377e8b5a933d5f9e4b3859f1dd0716be6d42df4634429c2378251c45f286e2e` | `1426a231d8eb312659eb8a843f880e2a944243ca` |

Verification points:

```text
T0 design acceptance;
T1 implementation authorization entry;
T2 instrumentation build entry;
T3 instrumentation build completion;
T4 dry materialization authorization entry;
T5 immediately before D001 handoff authorization request;
T6 after any authorized dry process exits.
```

Each check binds:

```text
verification_point;
HEAD;
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
git_diff_against_frozen_commit=empty.
```

Failure stop:

```text
write CORE_INVARIANCE_FAILURE.json;
do not repair;
do not execute D001;
do not continue;
request separate Human decision.
```

## 10. Acceptance criteria

Human review should accept v1.2 only if:

```text
1 S13 is historical static audit and cannot execute replay()/decide();
2 FailureCapture is terminal and emitted by the failing stage;
3 D001 handoff remains separately authorized;
4 EXPECTED vectors are comparator-only and absent from causal interfaces;
5 existing map_fixtures is classified non-causal auxiliary;
6 S2 is read-only verify_existing and snapshot creation/replacement is out of scope;
7 S1 uses `embedding_metadata.id` and audits retained ordering without regeneration;
8 digest materialization and verification are separate;
9 nested exact-field contracts are explicit;
10 trace-chain serialization, genesis, concatenation, and failure linking are deterministic;
11 all five D001 files bind content SHA-256 and Git blob ID;
12 no implementation/execution/campaign/mutation/evidence rewrite is authorized.
```

## 11. Decision requested

Human review must return exactly one ruling:

```text
ACCEPT   freeze v1.2 design only;
REVISE   require a v1.3 design revision;
REJECT   close this instrumentation/redesign pathway.
```

ACCEPT does not authorize implementation, dry materialization, validation
execution, D001 handoff, observer, campaign, mutation, or equivalence claims.
