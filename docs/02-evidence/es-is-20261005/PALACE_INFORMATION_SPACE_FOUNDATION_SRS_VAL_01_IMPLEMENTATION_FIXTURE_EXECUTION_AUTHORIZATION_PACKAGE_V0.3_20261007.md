# SRS-VAL-01 Implementation / Fixture / Execution / Information-Space Mutation Authorization Package v0.3

> **Status:** PACKAGE V0.3 DELIVERED FOR HUMAN REVIEW — IMPLEMENTATION / FIXTURE / EXECUTION / IS MUTATION NOT AUTHORIZED
> **Date:** 2026-10-07
> **Frozen semantic basis:** SRS-VAL-01 Design v0.8 at `1170208`
> **Review basis:** Human REVISE ruling on Authorization Package v0.2 at `a4446e8`
> **Purpose:** provide a self-contained, auditable authorization and independence boundary for any later implementation, fixture, execution, or Information-Space mutation request.

## 1. Governance status and self-containment

This package is a design and authorization-plan artifact. It does not implement
SRS-VAL, create fixtures, execute an experiment, mutate Information Space, or
change SimiGo code.

```text
SRS-VAL-01 Design v0.8        ACCEPT / FROZEN / IMMUTABLE BASIS
Authorization Package v0.2    REVISE / SUPERSEDED BY V0.3
Authorization Package v0.3    SUBMITTED FOR HUMAN REVIEW
Implementation                NOT AUTHORIZED
Fixture preparation           NOT AUTHORIZED
Execution                     NOT AUTHORIZED
IS mutation                   NOT AUTHORIZED
SimiGo code change            NOT AUTHORIZED
```

v0.3 is self-contained. Authorization Package v0.1 and v0.2 are provenance only.
Only requirements restated in this document are normative. All unenumerated
v0.1/v0.2 provisions are superseded and non-normative.

## 2. Immutable package identity

Every later stage record must bind:

```text
package_identity;
frozen_predicate_design =
  SRS-VAL-01 Design v0.8;
frozen_predicate_basis_commit =
  1170208;
package_design_revision =
  PACKAGE_V0.3;
package_integrity_binding =
  immutable commit/content binding of this package.
```

A mutable package pointer, after-the-fact plan edit, or unspecified revision
cannot authorize a stage.

## 3. Implementation-faithfulness requirements

Any implementation plan must contain a rule-to-code traceability matrix for:

```text
I-14, I-15, I-16;
exact predicate-rule identity/version/integrity;
G-CLASS mandatory classification;
DP-0..DP-4 precedence;
REUSE / BLOCK / RECOMPUTE exclusivity;
structural, provenance, result, dependency, freshness, policy, resolution,
source-relation, and lifecycle checks;
I14_NOT_USED_NO_RECOMPUTE_PATH semantics;
RECOMPUTE semantic envelope;
canonical identity-generation rule binding.
```

For each frozen rule it must name the component, input binding, decision effect,
failure path, observing test, and forbidden alternate behavior. No implementation
may weaken, strengthen, reorder, or reinterpret a frozen rule. No missing
evidence may be interpreted as a pass.

## 4. Human-authentic Stage Authorization Record

No prose authorization is sufficient. Before a stage, the runner requires an
immutable `Stage Authorization Record` plus a matching `Human Ruling Approval`.

### 4.1 Stage Authorization Record fields

```text
authorization_identity;
authorization_kind =
  STAGE_AUTHORIZATION_RECORD;
stage ∈ {
  IMPLEMENTATION,
  FIXTURE_PREPARATION,
  EXECUTION,
  IS_MUTATION
};
package_identity;
package_integrity_binding;
frozen_design_identity;
frozen_design_version =
  SRS-VAL-01 Design v0.8;
frozen_design_commit =
  1170208;
authorization_issuer_identity;
issuer_authority_binding;
human_ruling_identity;
human_ruling_integrity_binding;
approved_record_identity;
approved_record_content_address;
approval_status =
  APPROVED_FOR_NAMED_STAGE_ONLY;
authorized_repository_revision;
authorized_fixture_identities;
authorized_environment_identity;
authorized_effect_or_mutation_set;
authorized_filesystem_scope;
authorized_network_scope;
authorized_execution_run_ids_or_run_budget;
validity_boundary;
authorization_use_count_or_budget;
record_integrity_or_content_address_binding.
```

### 4.2 Human Ruling Approval binding

The linked Human Ruling Approval must contain:

```text
human_ruling_identity;
human_ruling_integrity_binding;
authorization_issuer_identity;
approved_record_identity;
approved_record_content_address;
approved_stage;
approval_status =
  APPROVED_FOR_NAMED_STAGE_ONLY;
approval_validity_boundary;
ruling_to_record_integrity_binding.
```

Hard rules:

```text
The Human Ruling must exact-bind the Stage Authorization Record identity and
content address.

Approval is valid only for the named stage.

A well-formed record with correct integrity but missing, mismatched, expired,
non-Human, or non-approving Human Ruling Approval is invalid.

Failure reason =
  AUTHORIZATION_AUTHENTICITY_INVALID.
```

Record integrity proves immutability. Human Ruling Approval proves authority.

### 4.3 Stage separation

Authorization for one stage never implies another:

```text
IMPLEMENTATION
  ≠ FIXTURE_PREPARATION
  ≠ EXECUTION
  ≠ IS_MUTATION.
```

An `IMPLEMENTATION` record may authorize only its exact named source scope. It
never authorizes fixture creation, execution, IS mutation, or network access.

A `FIXTURE_PREPARATION` record may create only its exact named fixture artifacts.
It never authorizes implementation, execution, IS mutation, or network access.

An `EXECUTION` record may read declared inputs, execute the exact bound artifacts,
and produce declared evidence. Its effect/mutation set must not contain
`INFORMATION_SPACE_MUTATION`.

An `IS_MUTATION` record is a separate authorization object. It must exact-bind
the affected Information-Space identities, mutation operations, result
identities/revisions, source evidence, and rollback or invalidity evidence
requirements.

If an operation requires both execution and IS mutation, it requires both a
valid `EXECUTION` record and a separate valid `IS_MUTATION` record. Neither can
derive the other.

### 4.4 Exact EXECUTION artifact binding

Every `EXECUTION` record must bind, without conditionality:

```text
exact_repository_commit =
  immutable full commit SHA;
exact_implementation_artifact_content_address;
exact_executable_or_runtime_artifact_identity;
runtime_artifact_integrity_binding.
```

Forbidden substitutes:

```text
branch pointer;
working tree;
latest revision;
floating tag;
unpinned container;
conditional result-code field.
```

The runner must revalidate the repository commit and artifact digests immediately
before execution and after execution. Any drift causes:

```text
runner stop;
AUTHORIZATION_TARGET_DRIFT_OR_TOCTOU.
```

Missing, mutable, unpinned, expired, overbroad, cross-stage, out-of-scope, or
authenticity-invalid authorization causes:

```text
runner stop;
AUTHORIZATION_RECORD_MISSING_INVALID_OR_OUT_OF_SCOPE.
```

### 4.5 Run identity control

An execution may run only preregistered run identities. A valid budget without a
matching preregistered run identity causes:

```text
runner stop;
RUN_IDENTITY_NOT_PREREGISTERED.
```

## 5. ES-IND-01 — Execution-State Independence Boundary

The proof object is:

```text
ES1 → declared immutable IS/SRS artifacts and inputs → ES2.
```

ES1 and ES2 must not share process, model/runtime memory, singleton/static
mutable state, agent/conversation memory, in-memory object graph, undeclared
IPC/shared memory, hidden runner cache, runner session carry-over, or transient
ES1 execution state.

### 5.1 Termination default

```text
Default ES1 boundary =
  TERMINATE before ES2 runtime initialization.
```

`QUIESCENT_EXCEPTION` is forbidden unless preregistered as necessary for the
specific proof and accompanied by evidence of all of the following:

```text
no active task;
no pending write or deferred I/O;
no open ES1→ES2 communication channel;
no mutable shared resource;
no outgoing capability;
no background watcher, socket, callback, or service client;
quiescence integrity evidence.
```

A label of “quiescent” without this evidence is invalid.

### 5.2 ES2 input/read provenance closure

For every ES2 proof, the plan must record a declared immutable input closure and
the observed read set:

```text
declared_input_identity;
input_role ∈ {
  DECLARED_IS_SRS_ARTIFACT,
  DECLARED_IMMUTABLE_INPUT
};
content_address_or_immutable_revision;
expected_read_set;
expected_transport_or_channel_identity;
expected_access_mode;
observed_read_set;
observed_transport_or_channel_identity;
undeclared_read_detected;
undeclared_es1_originated_artifact_access_detected;
input_closure_verdict.
```

Required verdict:

```text
observed_read_set == expected_read_set;
observed_channel_set == expected_channel_set;
undeclared_read_detected = false;
undeclared_es1_originated_artifact_access_detected = false;
input_closure_verdict = PASS.
```

This closure applies to filesystem, socket, localhost service, database, local
service, cache, IPC, and any other actual input carrier. A declared IS/SRS
artifact must be content-bound before ES2 starts and must remain unchanged when
revalidated after ES2 stops.

### 5.3 Independence evidence

Each proof must record:

```text
es1_runtime_identity;
es2_runtime_identity;
es1_process_boundary;
es2_process_boundary;
es1_termination_or_approved_exception_evidence;
es2_runtime_initialization_boundary;
shared_state_scan_method_and_result;
declared_input_closure;
shared_state_scan_result;
allowed_shared_artifact_bindings;
forbidden_shared_artifact_bindings;
before/after declared-state hashes;
runner and environment identities.
```

Missing, ambiguous, or failed ES-IND-01 evidence invalidates the affected
REUSE, BLOCK, or RECOMPUTE conclusion.

## 6. REUSE and RECOMPUTE proofs

A REUSE proof must establish that all checks pass, no failure remains, I-15 is
exact and applicable, I-14 is `I14_NOT_USED_NO_RECOMPUTE_PATH`, predicate
classification is not invoked, underlying computation invocation count is zero,
ES2 input closure passes, and only declared reuse/read effects occur.

An eligible RECOMPUTE proof must establish a surviving failure, exact predicate
rule classification, exact immutable I-14 coverage, valid RECOMPUTE semantic
envelope, unchanged canonical identity-rule binding, exact execution artifact
binding, ES2 input closure, and recomputation strictly inside the declared
envelope.

Missing, mutable, unversioned, unstable, expired, out-of-scope, or
integrity-invalid I-14/envelope evidence yields BLOCK, never RECOMPUTE.

## 7. Boundary-case matrix

The package must validate at least:

```text
B-REUSE-01    valid pure REUSE with no failure and no I-14.
B-BLOCK-01    DP-0 boundary inconsistency.
B-BLOCK-02    DP-1 lifecycle HARD_BLOCK despite another eligible failure.
B-BLOCK-03    DP-2 NOT_APPLICABLE or APPLICABILITY_INDETERMINATE.
B-BLOCK-04    surviving failure classified non-eligible.
B-BLOCK-05    classification skipped despite surviving failure.
B-BLOCK-06    predicate-rule binding missing/unstable/invalid.
B-RECOMP-01   eligible failure with exact predicate rule and exact valid I-14.
B-RECOMP-02   eligible failure with missing I-14.
B-RECOMP-03   eligible failure with invalid or overbroad I-14.
B-RECOMP-04   eligible failure with invalid RECOMPUTE envelope.
B-MIXED-01    eligible failure plus DP-1 HARD_BLOCK.
B-BOUNDARY-01 I-16 omits I-15, active I-14, or required predicate binding.
B-BOUNDARY-02 cross-boundary inputs.
B-BOUNDARY-03 later predicate-rule revision offered to a bound invocation.
B-INDEP-01    lawful ES1 termination, immutable IS/SRS handoff, independent ES2.
B-INDEP-02    shared process/runtime cache attempt cannot support an independence
              claim.
B-INDEP-03    ES2 reads an undeclared ES1 filesystem/temp artifact.
B-INDEP-04    ES1/ES2 communicate through localhost/socket/database/service.
B-INDEP-05    declared IS/SRS artifact is replaced or drifts before/during ES2.
B-INDEP-06    quiescence label exists with background task or deferred I/O.
B-INDEP-07    observed ES2 read set includes an undeclared input.
B-AUTH-01     required Stage Authorization Record is absent.
B-AUTH-02     valid record used for a different stage.
B-AUTH-03     authorization scope is overbroad or includes an undeclared effect.
B-AUTH-04     record hash is valid but Human Ruling Approval is absent/mismatched.
B-AUTH-05     executed revision differs from exact authorized revision.
B-AUTH-06     EXECUTION effect set attempts INFORMATION_SPACE_MUTATION.
B-AUTH-07     authorization or bound artifact drifts after validation.
B-AUTH-08     run budget is valid but run identity is not preregistered.
B-AUTH-09     IS mutation occurs without a separate valid IS_MUTATION record.
```

Each case has one auditable pass/stop outcome and no discretionary override.

## 8. Decision requested

```text
ACCEPT PACKAGE V0.3   freeze authorization authenticity, stage/type separation,
                      exact execution binding, ES2 provenance closure, and
                      termination-default independence; no stage is executed
                      until separately authorized.
REVISE PACKAGE V0.3   return with registered defects.
REJECT PACKAGE V0.3   do not proceed.
```

No implementation, fixture preparation, experiment, IS mutation, or SimiGo code
change is authorized by this document.
