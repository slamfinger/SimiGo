# Persistent SRS Representation Manifest Contract v1.0

> **Status:** SUBMITTED FOR HUMAN DESIGN REVIEW — DESIGN ONLY / NO STAGE AUTHORIZED
> **Date:** 2026-10-11
> **Authorization request:** `SIMIGO_PERSISTENT_SRS_REPRESENTATION_AUTHORIZATION_REQUEST_V0.1_20261011.md`
> **Authorization request SHA256:** `4063787b0680da2ccd872ec949c4602295c8bd5d9d6620f7149ff6caa288c791`
> **Human ruling:** `ACCEPT_REQUEST_FOR_PERSISTENCE_MANIFEST_CONTRACT`
> **Canonical PALACE mutation:** FORBIDDEN
> **Canonical Information Space mutation:** FORBIDDEN
> **MLX execution:** FORBIDDEN
> **V6 rerun:** FORBIDDEN
> **Independent ES₂ consumption:** NOT AUTHORIZED BY THIS CONTRACT
> **Non-recompute attribution:** NOT AUTHORIZED BY THIS CONTRACT

## 1. Scope and authority

This contract defines the review schema, canonical integrity model, physical
storage boundary, and fail-closed persistence semantics for a minimal
Persistent SRS Representation.

It does **not** implement persistence, authorize code changes, authorize fixture
preparation, authorize execution, create evidence, or authorize independent ES₂
consumption or non-recompute attribution.

```text
persistent implementation = NOT AUTHORIZED;
persistent fixture preparation = NOT AUTHORIZED;
persistent execution = NOT AUTHORIZED;
marker creation = FORBIDDEN;
evidence-root creation = FORBIDDEN;
canonical PALACE mutation = FORBIDDEN;
canonical Information Space mutation = FORBIDDEN;
```

Acceptance freezes this design only. Every later stage still requires a separate,
scope-bound Human Authorization Record.

## 2. Frozen provenance and compatibility

```text
request_base_commit =
  4626b7e09fc29b950edd31ae9d9eb79710869085;

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
  RETAINED_AS_FROZEN_PROVENANCE.
```

The existing SRS-VAL Manifest Contract v1.0 cannot be expanded to persistence.
This contract is therefore independent and persistence-specific. It inherits the
canonical semantic discipline of the accepted Decision Core but does not modify
Decision Core or amend the frozen SRS-VAL contract.

## 3. Contract identity

```text
contract_identity =
  SIMIGO_PERSISTENT_SRS_REPRESENTATION_MANIFEST_CONTRACT_V1.0;

contract_status_at_issue =
  SUBMITTED_FOR_HUMAN_DESIGN_REVIEW;

contract_integrity_binding =
  immutable Git commit/content binding assigned by Human acceptance;

self_declared_contract_digest = FORBIDDEN.
```

A future manifest instance must bind this exact identity and the Human-assigned
integrity binding. The conditional Manifest Instance v0.1 is not executable until
that rebinding and separate stage authorization occur.

## 4. Persistent record layers

The persistent object is separated into six layers. No layer may include a later
layer, preventing cyclic digest or signature dependencies.

### 4.1 L0 — semantic record fields

The semantic payload contains only the fields necessary to identify, validate,
and later reuse one Settled Relation State:

```text
schema_id =
  SIMIGO_PERSISTENT_SRS_RECORD_V1;

record_identity:
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

The current ES request, observation record, predicate-rule invocation records,
I-14 invocation record, and runtime execution trace are not semantic payload
fields. They may be supplied later by an independently authorized ES₂ invocation
and cannot be smuggled into persistent identity.

### 4.2 L1 — canonical payload bytes

```text
canonical_payload_data =
  deterministic SRSVAL-CANONICAL-TEXT-V4 encoding of L0;
```

Canonical encoding must preserve all accepted Decision Core rules:

```text
ordered semantic records use fixed field labels and order;
unordered collections sort deterministic encodings;
duplicate elements and duplicate counts remain distinguishable;
NIL and explicit empty collection remain distinct;
no omitted semantic field;
no ambiguous separator-only encoding;
no unknown, extra, or non-canonical field.
```

### 4.3 L2 — payload digest

```text
payload_digest =
  SHA256(
    "SIMIGO_PERSISTENT_SRS_PAYLOAD_DIGEST_V1" + 0x00 +
    canonical_payload_data
  );
```

The payload digest covers only L1. It does not include the signature, envelope
digest, evidence location, read verdict, or any later layer.

### 4.4 L3 — record signature

```text
signature_input =
  "SIMIGO_PERSISTENT_SRS_RECORD_SIGNATURE_V1" + 0x00 +
  schema_id + 0x00 +
  canonical_payload_data + 0x00 +
  signer_public_key;

signature =
  Ed25519 signature over signature_input;

trusted_verifier =
  compile-time production trust anchor only.
```

The signature covers semantic payload bytes and signer identity. It does not
cover the payload digest, envelope digest, evidence location, or read verdict.
The signer may not be selected by the subject at read time.

### 4.5 L4 — canonical envelope

The envelope is deterministic and includes:

```text
envelope_schema_id =
  SIMIGO_PERSISTENT_SRS_ENVELOPE_V1;

record_identity;
encoding_identity;
payload_digest;
signature;
signer_public_key;
signature_domain;
producer_authorization_reference;
decision_core_binding;

storage_format_version =
  PERSISTENT_SRS_STORAGE_V1;

completion_state =
  COMPLETE;
```

The envelope must not include `envelope_digest`, evidence location, read verdict,
process ID, timestamp, host path trust, or any observer evidence as semantic
identity.

### 4.6 L5 — envelope digest

```text
envelope_digest =
  SHA256(
    "SIMIGO_PERSISTENT_SRS_ENVELOPE_DIGEST_V1" + 0x00 +
    canonical_envelope_data_without_envelope_digest_field
  );
```

`envelope_digest` is a storage integrity value outside the bytes it hashes. It
must never be signed as payload and must never be an input to its own digest.

### 4.7 L6 — evidence location

```text
evidence_location =
  authorized evidence root + storage key + filename;
```

Evidence location is physical access metadata. It is not record identity and is
not part of L0 payload identity. A moved copy has the same logical identity if
L1, L2, L3, and L4 remain byte-equivalent.

## 5. Identity versus physical location

```text
record_identity =
  identity + version + payload_digest;
```

Rules:

```text
same record_identity requires byte-equivalent canonical payload;
different canonical payload forbids the same record_identity;
same bytes at different locations have the same record_identity;
physical move does not change record identity;
physical deletion removes access but does not redefine identity;
two records with equal identity but unequal bytes produce
  PERSISTENT_IDENTITY_CONFLICT and fail closed.
```

A manifest may require an exact expected location for authorization purposes.
That requirement is an access-control constraint, not a semantic identity field.
A byte-equivalent copy at an unauthorized location must fail authorization, but
must not be described as a different SRS identity.

## 6. Required read verification order

A reader must verify, in order, and stop at the first failure:

```text
R1  storage format and envelope schema are known;
R2  physical record is complete and non-truncated;
R3  envelope contains no unknown or extra field;
R4  encoding identity is exactly SRSVAL-CANONICAL-TEXT-V4;
R5  payload_digest matches L1;
R6  canonical payload is structurally valid;
R7  record identity equals identity + version + payload_digest;
R8  signer and signature domain are authorized;
R9  Ed25519 signature verifies using the fixed production anchor;
R10 Decision Core binding exactly matches the accepted source commit and SHA256;
R11 semantic record passes all Decision Core structural binding checks;
R12 evidence location satisfies the separately authorized manifest constraint;
R13 final verdict is COMPLETE_VERIFIED only after all prior checks pass.
```

No repair, default substitution, schema coercion, lenient JSON decoding, retry,
or partial acceptance is permitted.

## 7. Write and completion semantics

A writer must use this sequence:

```text
W1  resolve an isolated, manifest-authorized evidence root;
W2  serialize L1;
W3  compute L2, L3, L4, and L5;
W4  write the complete immutable object to a temporary path inside the same
    authorized evidence root;
W5  flush the file;
W6  atomically rename to the final storage key;
W7  flush the containing directory when the platform supports it;
W8  reopen from physical storage and execute all read checks;
W9  emit COMPLETE_VERIFIED only after R1–R13 pass.
```

Rules:

```text
final storage keys are immutable;
overwrite is forbidden;
same identity plus byte-equivalent object may be reported as IDEMPOTENT_COMPLETE;
same identity plus unequal object is PERSISTENT_IDENTITY_CONFLICT;
temporary files are not valid records and must not be promoted by a reader;
the writer may not mark completion in memory before W8/W9.
```

## 8. Persistence failure semantics

Every failure is fail-closed and must be independently observable.

| Condition | Required result |
| --- | --- |
| Writer exits before atomic rename | No final record exists; reader returns `RECORD_NOT_FOUND`. Temporary data remains invalid. |
| Atomic rename completed but process exits before W8 | Physical object may exist, but no write verdict exists. Reader must independently verify. No `COMPLETE_VERIFIED` may be inferred. |
| File is truncated | `TRUNCATED_RECORD`. |
| File is partial or lacks final required fields | `PARTIAL_RECORD`. |
| Bytes are damaged but length is plausible | Digest/signature check fails with `RECORD_CORRUPT`. |
| Payload digest differs | `PAYLOAD_DIGEST_MISMATCH`. |
| Envelope digest differs | `ENVELOPE_DIGEST_MISMATCH`. |
| Signature, signer, or domain differs | `SIGNATURE_VERIFICATION_FAILED`. |
| Identity/version roles swap | `RECORD_IDENTITY_MISMATCH`. |
| NIL becomes explicit empty, or reverse | `CANONICAL_PRESENCE_MISMATCH`. |
| Unordered collection reorders with same members and counts | `VALID_CANONICAL_EQUIVALENCE`. |
| Duplicate count changes | `CANONICAL_MULTISET_MISMATCH`. |
| Unknown schema or storage version | `UNKNOWN_SCHEMA_OR_STORAGE_VERSION`. |
| Unknown or extra field exists | `NON_CANONICAL_RECORD`. |
| Decision Core binding differs | `DECISION_CORE_BINDING_MISMATCH`. |
| Same identity has different bytes | `PERSISTENT_IDENTITY_CONFLICT`. |
| Authorized expected location differs | `EVIDENCE_LOCATION_UNAUTHORIZED`. |
| Any check cannot be completed | `PERSISTENCE_VERIFICATION_INDETERMINATE`, treated as BLOCK. |

`COMPLETE_VERIFIED` means the on-disk bytes passed all checks in the current read
process. It is not proof that a later process will pass, and it is not evidence
of non-recompute.

## 9. Manifest record groups

A future filled instance must bind:

```text
manifest_instance_identity;
this contract identity and Human-assigned integrity binding;
authorization request and Human ruling;
requested_stage_set;
authorized repository revision;
authorized writable path set;
forbidden path and dependency sets;
implementation artifact digest placeholders;
fixture set and immutable fixture digests;
execution artifact and runtime digest bindings;
environment identity;
per-fixture run budgets;
observer authorization and channel universe;
evidence root identity and authorized location;
expected validation matrix;
evidence locations and integrity bindings;
stage validity boundaries.
```

The prior conditional Manifest Instance v0.1 is not executable until it is
rebound to this contract identity and Human-assigned integrity binding.

### 9.1 IMPLEMENTATION stage

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

### 9.2 FIXTURE_PREPARATION stage

Fixtures must be immutable and generated before execution. The future manifest
must separately bind at least:

```text
valid record;
reopen record;
cross-process record;
digest mutation;
signature/signer/domain mutation;
identity/version role swap;
NIL-to-empty mutation;
valid unordered reorder;
duplicate-count mutation;
truncated record;
partial record;
corrupt record;
unknown version;
extra field;
identity conflict;
unauthorized evidence location.
```

### 9.3 EXECUTION stage

Execution requires an exact artifact, environment, observer, and evidence-root
binding. The default candidate budget is one run per separately authorized
fixture, with a maximum of sixteen fixture executions. A failed run consumes that
fixture budget. Repair or retry requires a new scope-bound Human Authorization
Record.

## 10. Observer authority

For any authorized runtime observation:

```text
Observer proves what process and filesystem operations occurred.

The persistence verifier proves whether stored bytes form a valid record.

Observer evidence does not become semantic payload.
Persistence verification does not become observer execution evidence.
A COMPLETE_VERIFIED record does not prove non-recompute.
A cross-process read does not authorize ES₂.
```

Observer, subject, writer, fixture builder, and manifest generator must remain
independent authorities.

## 11. Stage separation

```text
IMPLEMENTATION
  != FIXTURE_PREPARATION
  != EXECUTION
  != independent ES2 consumption
  != non-recompute attribution
  != IS mutation.
```

No stage may be derived from this contract's acceptance, from another stage, or
from the accepted Decision Core. Missing, expired, overbroad, cross-stage, or
drifted authorization stops before that stage.

## 12. Adversarial review requirements

Before Human acceptance, review must attack at least:

```text
PR-A1  digest/signature circular dependency;
PR-A2  envelope digest self-inclusion;
PR-A3  evidence location promoted to semantic identity;
PR-A4  logical identity retained while bytes drift;
PR-A5  physical move treated as identity change without authorization need;
PR-A6  partial temporary file accepted as complete;
PR-A7  writer memory verdict reused as cross-process proof;
PR-A8  NIL converted to explicit empty collection;
PR-A9  unordered reorder confused with duplicate-count change;
PR-A10 unknown field removed by lenient decoding;
PR-A11 Decision Core binding drift;
PR-A12 signer or trust anchor selected by the subject;
PR-A13 observer classification promoted to semantic payload;
PR-A14 persistence PASS treated as ES2 authorization;
PR-A15 persistence PASS treated as non-recompute attribution;
PR-A16 stage authorization expanded through evidence-root creation.
```

Each attack must map to a contract field, expected stop/pass result, observer
source where applicable, and evidence artifact.

## 13. Acceptance criteria

Human may accept this contract only if:

```text
C1  all six integrity layers are explicit and acyclic;
C2  logical identity and physical location are separated;
C3  evidence location is access authorization, not identity;
C4  canonical NIL, empty, ordering, and duplicate semantics are preserved;
C5  every listed persistence failure has a deterministic fail-closed result;
C6  no stage is authorized by contract acceptance;
C7  Decision Core and frozen provenance bindings are exact;
C8  independent ES₂ and non-recompute attribution remain excluded;
C9  canonical PALACE and Information Space mutation remain forbidden.
```

## 14. Decision requested

Human is asked to return exactly one:

```text
ACCEPT_PERSISTENT_SRS_MANIFEST_CONTRACT_V1.0
```

or

```text
REVISE_PERSISTENT_SRS_MANIFEST_CONTRACT_V1.0
```

or

```text
REJECT_PERSISTENT_SRS_MANIFEST_CONTRACT_V1.0
```

Acceptance freezes this design and assigns its integrity binding. It does not
authorize implementation, fixture preparation, execution, marker creation,
evidence-root creation, ES₂ consumption, non-recompute attribution, MLX, V6,
PALACE, Information Space, or production operation.
