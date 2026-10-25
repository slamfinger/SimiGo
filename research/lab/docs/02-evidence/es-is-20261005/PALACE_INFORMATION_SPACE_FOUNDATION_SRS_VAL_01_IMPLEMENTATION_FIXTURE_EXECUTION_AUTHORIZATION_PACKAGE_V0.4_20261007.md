# SRS-VAL-01 Implementation / Fixture / Execution / Information-Space Mutation Authorization Package v0.4

> **Status:** PACKAGE V0.4 REVISE — SUPERSEDED BY V0.5 — IMPLEMENTATION / FIXTURE / EXECUTION / IS MUTATION NOT AUTHORIZED
> **Date:** 2026-10-07
> **Frozen semantic basis:** SRS-VAL-01 Design v0.8 at `1170208`
> **Review basis:** Human REVISE ruling on Authorization Package v0.3 at `12678e2`
> **Purpose:** close observation independence, authorization authority, actual runtime/mutation execution, and read-instance immutability before execution freeze.
> **Review ruling:** REVISE; see `docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_IMPLEMENTATION_FIXTURE_EXECUTION_AUTHORIZATION_PACKAGE_V0.4_REVIEW_RULING_20261007.md`.
> **Superseded by:** `docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_IMPLEMENTATION_FIXTURE_EXECUTION_AUTHORIZATION_PACKAGE_V0.5_20261007.md`.

## 1. Governance status and self-containment

This package is an authorization-plan design. It does not implement SRS-VAL,
create fixtures, execute an experiment, mutate Information Space, or change
SimiGo code.

```text
SRS-VAL-01 Design v0.8        ACCEPT / FROZEN / IMMUTABLE BASIS
Authorization Package v0.3    REVISE / SUPERSEDED BY V0.4
Authorization Package v0.4    SUBMITTED FOR HUMAN REVIEW
Implementation                NOT AUTHORIZED
Fixture preparation           NOT AUTHORIZED
Execution                     NOT AUTHORIZED
IS mutation                   NOT AUTHORIZED
SimiGo code change            NOT AUTHORIZED
```

v0.4 is self-contained. Authorization Package v0.1..v0.3 are provenance only.
The normative baseline carried forward consists solely of the requirements
restated or explicitly strengthened here:

```text
four independent stages:
  IMPLEMENTATION,
  FIXTURE_PREPARATION,
  EXECUTION,
  IS_MUTATION;

exact Stage Authorization Record plus Human Ruling Approval;

exact EXECUTION repository/artifact/runtime binding;

ES1 termination default and ES2 provenance closure;

declared IS/SRS and immutable-input-only boundary;

REUSE no-recompute proof;

RECOMPUTE only through exact predicate rule, exact I-14, and exact envelope.
```

All unenumerated v0.1..v0.3 provisions are superseded and non-normative.

## 2. Immutable package identity

Every later record must bind:

```text
package_identity;
frozen_predicate_design =
  SRS-VAL-01 Design v0.8;
frozen_predicate_basis_commit =
  1170208;
package_design_revision =
  PACKAGE_V0.4;
package_integrity_binding =
  immutable commit/content binding of this package.
```

## 3. Authorization Authority Root

Integrity of a record does not prove its authority. Therefore every authorization
chain must begin at an immutable `Authorization Authority Root`.

### 3.1 Root record

```text
authorization_authority_root_identity;
trusted_human_authority_identity;
authority_binding;
authority_scope;
authority_status ∈ {
  ACTIVE,
  REVOKED,
  EXPIRED
};
authority_integrity_binding;
root_governing_human_ruling_reference;
root_content_address.
```

The runner must pin the root identity and integrity binding in its configuration.
A mutable pointer to “current authority” is forbidden. Root rotation requires a
new immutable root and a new Human ruling reference.

### 3.2 Authority chain

```text
Authorization Authority Root
  → Human Ruling
  → authorized issuer
  → Stage Authorization Record
```

The linked Human Ruling must bind:

```text
authorization_authority_root_identity;
trusted_human_authority_identity;
authorization_issuer_identity;
issuer_authority_scope;
issuer_status;
human_ruling_identity;
human_ruling_integrity_binding;
approved_record_identity;
approved_record_content_address;
approved_stage;
approval_status =
  APPROVED_FOR_NAMED_STAGE_ONLY;
approval_validity_boundary;
ruling_to_record_integrity_binding.
```

### 3.3 Validation rules

Before accepting any Stage Authorization Record, validate:

```text
root exists and is ACTIVE;
root digest matches the pinned root;
issuer is named by the root-backed Human Ruling;
issuer scope includes the record stage;
record stage equals approved stage;
record identity/content equals approved identity/content;
ruling digest and issuer binding verify;
validity boundary and use budget are valid.
```

Failure produces:

```text
runner stop;
AUTHORIZATION_TRUST_ROOT_INVALID.
```

A syntactically valid record with a self-declared issuer, unpinned root, revoked
issuer, mismatched scope, or absent root-backed ruling is invalid.

## 4. Stage Authorization Record baseline

The four stages remain independent:

```text
IMPLEMENTATION
  ≠ FIXTURE_PREPARATION
  ≠ EXECUTION
  ≠ IS_MUTATION.
```

Every record must bind package identity, frozen design commit, issuer/root chain,
approved record identity/content, repository revision where applicable, fixture
identities where applicable, environment identity, effect/mutation set, filesystem
scope, network scope, run identity/budget, validity, use budget, and integrity
binding.

`EXECUTION` must bind without conditionality:

```text
exact_repository_commit =
  immutable full commit SHA;
exact_implementation_artifact_content_address;
exact_executable_or_runtime_artifact_identity;
runtime_artifact_integrity_binding.
```

Branches, working trees, latest revisions, floating tags, unpinned containers, and
conditional code fields are invalid.

`IS_MUTATION` is never granted by EXECUTION. If an operation needs both, it
requires both a valid EXECUTION record and a separate valid IS_MUTATION record.

## 5. Observation Integrity Boundary

No claim that something was observed is sufficient. The observation mechanism must
itself be independent, complete, and tamper-resistant.

### 5.1 Observer Integrity Record

For every proof, create an immutable:

```text
observation_integrity_record_identity;
observer_identity;
observer_artifact_content_address;
observer_runtime_artifact_identity;
observer_environment_identity;
observer_execution_boundary;
observer_trust_boundary;
observation_source;
covered_channel_set;
uncovered_channel_set;
observation_start_boundary;
observation_stop_boundary;
observer_to_subject_separation_proof;
observer_tamper_resistance_proof;
observer_artifact_integrity_binding;
completeness_verdict.
```

### 5.2 Independence rules

The observer must be outside the subject trust boundary. ES2, the instrumented
subject runtime, and any component configurable by the subject must not
authoritatively produce observation evidence.

Hard rules:

```text
ES2 cannot authoritatively define its own observed_read_set.

The observer must start before the subject and stop after the subject.

The observer must not share mutable state, writable configuration, writable code,
or writable evidence storage with the subject.

Subject read/write access to observer artifacts or control interfaces is forbidden.

Observer configuration must be prebound and integrity-checked.

Observer artifacts must be revalidated after the run.
```

Failure produces:

```text
OBSERVER_NOT_INDEPENDENT
OBSERVER_ARTIFACT_DRIFT
OBSERVER_TAMPERING_SUSPECTED
OBSERVATION_COVERAGE_INCOMPLETE.
```

### 5.3 Coverage closure

The plan must prove coverage for every channel that can carry a relevant effect:

```text
filesystem reads and writes;
network/socket traffic;
localhost and external service calls;
IPC/shared memory;
process/fork/exec boundaries;
loaded runtime artifacts;
declared IS/SRS reads;
Information-Space mutation effects;
environment/resource access relevant to execution;
state hashes and mutation evidence.
```

`uncovered_channel_set` must be empty unless a channel is impossible in the
prebound environment, and that impossibility must be separately evidenced.

`completeness_verdict` is valid only when coverage is complete, the observer is
independent, and observer artifacts remain unchanged.

### 5.4 Authoritative versus supplementary evidence

Subject self-logs may exist only as supplementary evidence. They never satisfy
`observed_read_set`, `observed_runtime_dependency_set`, or
`observed_mutation_set`. If external observation and subject self-report differ,
the external observation controls and the discrepancy fails the proof.

## 6. Runtime dependency closure

Exact entrypoint binding is insufficient. EXECUTION must close the actual loaded
execution surface.

### 6.1 Authorized dependency set

The EXECUTION record or its immutable attachment must define:

```text
authorized_runtime_dependency_set;
dependency_identity;
dependency_role ∈ {
  executable,
  runtime,
  dynamic_library,
  framework,
  model_file,
  tokenizer,
  configuration,
  plugin,
  runtime_data,
  environment_injected_resource,
  local_service,
  cache_layer
};
dependency_content_address_or_immutable_revision;
dependency_integrity_binding;
dependency_necessity_evidence.
```

Each dependency must be pinned. Floating paths, unpinned containers, mutable
configuration files, latest model/tokenizer references, and implicit cache fills
are forbidden unless represented as exact pinned artifacts.

### 6.2 Observed dependency set

The independent observer must produce:

```text
observed_runtime_dependency_set;
observed_dependency_identity;
observed_dependency_content_address_or_digest;
observed_dependency_source;
load_or_invoke_boundary;
undeclared_dependency_detected;
dependency_closure_verdict.
```

Required verdict:

```text
observed_runtime_dependency_set
  ⊆
authorized_runtime_dependency_set;

undeclared_dependency_detected = false;

dependency_closure_verdict = PASS.
```

Failure produces:

```text
RUNTIME_DEPENDENCY_UNAUTHORIZED
RUNTIME_DEPENDENCY_DRIFT
RUNTIME_DEPENDENCY_CLOSURE_INCOMPLETE.
```

Environment-injected resources and local services are not exempt. If used, they
must be pinned and authorized. If forbidden, their observation must be evidence of
non-use.

## 7. Semantic input and mechanical read separation

Read evidence has two layers.

### 7.1 Semantic input closure

Semantic input is data consumed as part of the predicate or experiment. The
declared semantic input closure remains exact:

```text
observed_semantic_input_read_set
  ==
expected_semantic_input_read_set.
```

### 7.2 Mechanical runtime read closure

Runtime bookkeeping, loader metadata, library lookup, and operating-system internal
reads belong to:

```text
mechanical_runtime_read_set.
```

Mechanical reads do not become semantic inputs, but they must still be covered by
observation and must not bypass the runtime dependency closure. An undeclared
mechanical artifact that can affect execution is a runtime dependency failure, not
a harmless bookkeeping event.

This separation prevents semantic pollution without creating an observation
exemption.

## 8. IS_MUTATION execution closure

A separate IS_MUTATION record must close not only the intended target but also the
executor and observed effect.

### 8.1 Required mutation bindings

```text
authorized_mutation_executor_identity;
authorized_mutation_executor_content_address;
authorized_mutation_runtime_artifact_identity;
authorized_mutation_environment_identity;
authorized_mutation_dependency_set;
exact_affected_information_space_identities;
exact_mutation_operations;
exact_source_evidence_bindings;
expected_result_identity_or_revision;
expected_pre_state_content_address;
expected_post_state_content_address;
expected_mutation_set;
rollback_or_invalidity_evidence_requirement.
```

### 8.2 Observed mutation closure

The independent observer must record:

```text
observed_mutation_executor_identity;
observed_mutation_executor_content_address;
observed_mutation_runtime_artifact_identity;
observed_mutation_dependency_set;
observed_pre_state_content_address;
observed_post_state_content_address;
observed_mutation_set;
mutation_scope_verdict.
```

Required verdict:

```text
observed_mutation_executor_identity ==
  authorized_mutation_executor_identity;

observed_mutation_executor_content_address ==
  authorized_mutation_executor_content_address;

observed_mutation_dependency_set ⊆
  authorized_mutation_dependency_set;

observed_pre_state_content_address ==
  expected_pre_state_content_address;

observed_post_state_content_address ==
  expected_post_state_content_address;

observed_mutation_set ==
  expected_mutation_set;

mutation_scope_verdict = PASS.
```

Failure produces:

```text
MUTATION_EXECUTOR_UNAUTHORIZED
MUTATION_DEPENDENCY_UNAUTHORIZED
MUTATION_STATE_DRIFT
MUTATION_SCOPE_VIOLATION.
```

## 9. Read-instance immutability

Before and after hashes alone do not prove what ES2 consumed. Every declared
semantic input read instance must bind the version actually consumed.

### 9.1 Required read-instance evidence

```text
read_instance_identity;
declared_input_identity;
declared_content_address_or_revision;
read_time_content_digest;
read_instance_snapshot_or_atomicity_proof;
observing_observer_identity;
read_begin_boundary;
read_end_boundary;
consumed_content_matches_declaration.
```

### 9.2 Accepted proof forms

One of the following is required:

```text
IMMUTABLE_SNAPSHOT_PRESEALED
  the input is content-addressed, sealed before ES2 starts, and read-only;

ATOMIC_VERSIONED_READ_HANDLE
  the carrier returns an immutable version and digest for every read;

OBSERVED_MEDIATED_READ
  an independent mediation layer captures the exact content digest at read time.
```

A direct read from a mutable carrier with only before/after equality is invalid.

Failure produces:

```text
READ_INSTANCE_NOT_IMMUTABLE
READ_TIME_CONTENT_MISMATCH.
```

The required result is:

```text
read_time_content_digest ==
  declared_content_address_or_revision_digest;

consumed_content_matches_declaration = true.
```

## 10. Combined execution gate

Before a run, the runner requires all of:

```text
valid Authorization Authority Root chain;
valid Stage Authorization Record for each needed stage;
exact EXECUTION artifact binding where applicable;
exact IS_MUTATION executor binding where applicable;
valid Observer Integrity Record;
declared input closure and read-instance mode;
authorized runtime dependency set.
```

During and after the run, all must remain true:

```text
observer independent and unchanged;
coverage complete;
observed semantic input set exactly declared;
observed runtime dependencies subset authorized;
mutation effects exactly declared where applicable;
read-time content matches declared versions;
no authorization or artifact TOCTOU drift.
```

Any failure stops the run and invalidates the affected decision proof.

## 11. Boundary-case additions

In addition to the prior registered predicate and authorization cases, v0.4
requires at least:

```text
B-OBS-01     observer is subject-controlled or shares writable trust boundary.
B-OBS-02     observer lacks coverage for a relevant channel.
B-OBS-03     observer artifact/configuration changes after prebinding.
B-OBS-04     subject self-report is used as authoritative observed evidence.
B-AUTH-10    valid record hash but no pinned Authorization Authority Root.
B-AUTH-11    issuer is valid-looking but not authorized by the root-backed ruling.
B-RUNTIME-01 unauthorized dynamic library or plugin is loaded.
B-RUNTIME-02 environment-injected model/configuration/cache affects execution.
B-MUT-01     authorized mutation target runs through an unbound executor.
B-MUT-02     observed mutation set contains an extra operation.
B-READ-01    mutable carrier has equal before/after hashes but changes at read
             time.
B-READ-02    read-time digest differs from declared content address.
```

These cases test authorization, execution, and observation closure; they do not
expand the research experiment matrix.

## 12. Decision requested

```text
ACCEPT PACKAGE V0.4   freeze observation integrity, authorization trust root,
                      runtime/mutation execution closure, and read-instance
                      immutability; no stage is executed until separately
                      authorized.
REVISE PACKAGE V0.4   return with registered defects.
REJECT PACKAGE V0.4   do not proceed.
```

No implementation, fixture preparation, experiment, IS mutation, or SimiGo code
change is authorized by this document.
