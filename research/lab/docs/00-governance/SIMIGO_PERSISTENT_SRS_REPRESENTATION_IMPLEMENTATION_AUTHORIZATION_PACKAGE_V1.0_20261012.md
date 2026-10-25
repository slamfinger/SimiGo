# Persistent SRS Representation Implementation Authorization Package v1.0

> **Status:** DELIVERED FOR HUMAN REVIEW — IMPLEMENTATION NOT AUTHORIZED
> **Date:** 2026-10-12
> **Governing Manifest Instance:** v2.2, `ACCEPT / DESIGN BOUND`
> **Governing Contract:** Persistence Manifest Contract v1.8, `ACCEPT / DESIGN FROZEN`
> **Requested stage:** `IMPLEMENTATION` only
> **Implementation status:** NOT AUTHORIZED
> **Fixture preparation:** NOT AUTHORIZED
> **Execution batch:** NOT AUTHORIZED
> **Independent JSON Schema validator run:** NOT AUTHORIZED
> **Canonical PALACE / Information Space mutation:** FORBIDDEN
> **MLX / V6 rerun:** FORBIDDEN
> **Marker / evidence-root creation:** FORBIDDEN

## 1. Purpose and authorization boundary

This package requests a narrow, separately reviewable `IMPLEMENTATION`
authorization for `PersistentSRSRepresentation` and its unit tests.

Approval of this package, if granted, may authorize only the implementation-stage
work in section 8. It must not authorize Fixture Preparation, Execution Batch,
independent validator execution by implication, ES₂ consumption, non-recompute
attribution, canonical PALACE mutation, canonical Information Space mutation, MLX
execution, V6 rerun, or production activity.

Every downstream activity remains a separate Human decision.

## 2. Frozen design and governance bindings

```text
manifest_instance_identity =
  SIMIGO_PERSISTENT_SRS_REPRESENTATION_MANIFEST_INSTANCE_V2.2;

manifest_instance_status =
  ACCEPT / DESIGN BOUND;

manifest_instance_commit =
  8932eea899876543e8e34e42b88bed47e8219969;

manifest_instance_direct_parent_commit =
  9a376dd5c093b17dad390d1c3ee5690cc46b140d;

manifest_instance_sha256 =
  8c0e4954ac07e5e26f8efe81c23f15373f687d7f94afd7a29cdc8b4f8f65588f;

persistence_contract_identity =
  SIMIGO_PERSISTENT_SRS_REPRESENTATION_MANIFEST_CONTRACT_V1.8;

persistence_contract_accepted_commit =
  6ac85f68003afc778aeec5b6fc070f7958be7499;

persistence_contract_git_blob_sha =
  63fc1f6deba0f9f5ca453b543411fb8e371d6613;

persistence_contract_sha256 =
  ba8d7fe609a26bdb88ee90e8af0bcd4778372c0ef552a838e158f7204aed47c0;

accepted_decision_core_source_commit =
  1d47f3be56dfa8c6bf7619f4566b271ed74aad27;

accepted_decision_core_source_sha256 =
  7fec2ed4d6e6f82fe677a7f098ec98d3e99bf4138420f1dd051570c75cf1c72e;
```

## 3. Frozen I0 JSON Schema input

The schema is a read-only test input. It must not be modified, moved, regenerated,
or replaced during implementation.

```text
i0_json_schema_identity =
  PERSISTENT_SRS_RECORD_JSON_SCHEMA_V1.6;

i0_json_schema_path =
  docs/02-evidence/persistent-srs-20261011/PERSISTENT_SRS_RECORD_JSON_SCHEMA_V1.6.json;

i0_json_schema_git_blob_sha =
  0dad25e4886d665d36251ba898cd195c91703ae0;

i0_json_schema_sha256 =
  8e373d27afd9c30f8c5e728d03ac71f2c6784f2ba51c2f3195fabd76d6348b41;

i0_json_schema_status =
  FROZEN / READ-ONLY / NOT AUTHORIZED FOR VALIDATOR EXECUTION.
```

## 4. Exact repository revision

```text
authorized_package_basis_commit =
  8932eea899876543e8e34e42b88bed47e8219969;

authorized_repository_revision =
  8932eea899876543e8e34e42b88bed47e8219969;

repository_revision_binding =
  Implementation must be based on this exact commit or a direct descendant whose
  only intervening commits are the separately committed governance records for
  this package acceptance;
```

The final `IMPLEMENTATION Human Authorization Record` must bind the actual start
commit by full SHA256. It must verify that this commit is `8932...` or a direct
descendant containing only this package's governance changes. No
`REBIND_AT_ISSUE` placeholder is permitted.

## 5. Authorized writable paths

Only these paths may be created or changed:

```text
simigo2-experimental/Sources/SimiGo2Experimental/PersistentSRSRepresentation.swift;
simigo2-experimental/Tests/SimiGo2ExperimentalTests/PersistentSRSRepresentationTests.swift;
```

No other path may be created, deleted, moved, or changed. In particular,
`Package.swift`, `Package.resolved`, the frozen I0 Schema, all governance and
evidence documents, V6 artifacts, PALACE roots, and Information Space roots are
outside the writable set.

## 6. Dependency and effect boundaries

Forbidden dependencies and effects:

```text
MLX;
SQLite;
canonical PALACE storage;
canonical Information Space storage;
network clients or network access;
new external Swift packages;
new executable targets;
new test targets beyond the existing test target;
V6 runner/child/marker/evidence mutation;
filesystem writes outside the Swift build/test sandbox;
process launches other than the authorized build/test command.
```

The implementation must be pure with respect to Decision Core semantics: no
model execution, no persistent state, no hidden global state, and no I/O in the
decision path.

## 7. Required semantic scope

The implementation must bind to and honor Persistence Manifest Contract v1.8:

```text
I0 schema validation;
PERSISTENT_SRS_CANONICAL_V1 encoding rules;
canonical byte re-serialization equality;
base and sealed evidence digest separation;
fixed production Ed25519 anchor/domain binding;
strict UTC parsing;
UTF-8 byte-exact logical-key comparison;
ClassificationDescriptor production/test classifier binding;
logical-key uniqueness;
content-addressed collision classification;
same-key/same-digest/different-I1 collision classification;
append-only attempt/status/closure record semantics;
two-phase candidate qualification and closure commit;
batch budget and attempt-state projection.
```

No new semantic authority may be introduced. No frozen Contract v1.8 or I0 Schema
v1.6 rule may be changed.

## 8. Authorized implementation work

If Human grants the separate `IMPLEMENTATION` authorization record, the authorized
work is limited to:

```text
create or edit PersistentSRSRepresentation.swift;
create or edit PersistentSRSRepresentationTests.swift;
run the exact build command in section 9;
run the exact filtered test command in section 9;
record the resulting evidence in section 10.
```

Code generation, migration, database setup, fixture generation, execution-batch
work, validator execution, and production deployment are not included.

## 9. Exact build and test commands

All commands must run from:

```text
/Users/mr.simi/Documents/SimiGo-Lab/simigo2-experimental
```

Authorized commands:

```text
swift build --product SimiGo2Experimental
swift test --filter PersistentSRSRepresentationTests
```

No unfiltered test invocation, no alternate product, no parallel or retry flags,
and no environment-modifying wrapper is authorized. If either command fails, the
failure consumes the implementation completion attempt and requires a new
scope-bound Human decision; no silent retry is allowed.

## 10. Implementation completion evidence

A later implementation completion review must receive:

```text
actual start commit SHA256;
actual implementation commit SHA256 and direct parent SHA256;
diff bounded to section 5 paths;
source SHA256 for each changed file;
complete build command and exit status;
complete filtered test command and exit status;
build/test output integrity digest;
list of tests executed and their outcomes;
explicit statement that no forbidden path, dependency, or effect was used.
```

The implementation stage may not be marked `COMPLETE` until a separately
authorized JSON Schema validator has run successfully and produced:

```text
validator implementation/version identity;
validator artifact or executable integrity binding;
exact invocation command and working directory;
bound I0 Schema Git blob SHA and SHA256;
validator input/output integrity bindings;
validator exit status;
scope statement proving no additional stage was executed.
```

The validator remains a separate authorization object and is not implicit in
implementation authorization.

## 11. Required negative and positive unit-test coverage

Tests must cover at least:

```text
valid I0 schema encoding and canonical round trip;
JCS canonical byte equality for reordered unordered collections;
NIL versus explicit empty collection distinction;
base digest independence from completion_order_key;
sealed evidence digest binding of core evidence, base digest, and order key;
strict UTC parser acceptance and invalid calendar rejection;
UTF-8 byte-exact logical-key comparison, including Unicode
  canonical-equivalent but byte-distinct identities;
classification descriptor shared production logic;
different logical-key content-addressed collision;
same-key/same-digest/different-I1 collision;
append-only attempt/status/closure behavior;
batch budget and attempt projection rules.
```

Tests must not create persistent files outside the test sandbox and must not
simulate an authorized execution batch.

## 12. Completion criteria

Implementation may be judged complete only when all of the following are true:

```text
Human has separately authorized IMPLEMENTATION;
the actual implementation commit satisfies section 4;
the diff is bounded to section 5;
all forbidden dependency/effect checks pass;
the exact build command passes;
the exact filtered test command passes;
all required unit-test coverage passes;
source and output integrity bindings are recorded;
a separately authorized JSON Schema validator run has passed;
Human implementation-completion review accepts the evidence.
```

Completion does not authorize Fixture Preparation, Execution Batch, independent
ES2 consumption, non-recompute attribution, PALACE or Information Space mutation,
MLX execution, V6 rerun, or production proof.

## 13. Requested Human decision

Human is asked to return exactly one:

```text
AUTHORIZE_IMPLEMENTATION_V1
```

or

```text
REVISE_IMPLEMENTATION_AUTHORIZATION_PACKAGE_V1.0
```

or

```text
REJECT_IMPLEMENTATION_AUTHORIZATION_PACKAGE_V1.0
```

`AUTHORIZE_IMPLEMENTATION_V1` may authorize only section 8 and section 9. Every
downstream activity remains forbidden until separately authorized.
