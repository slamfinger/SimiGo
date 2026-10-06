# SRS-VAL-01 Implementation / Fixture / Execution / Information-Space Mutation Authorization Package v0.6

> **Status:** PACKAGE V0.6 ACCEPT / FROZEN — IMPLEMENTATION / FIXTURE / EXECUTION / IS MUTATION NOT AUTHORIZED
> **Date:** 2026-10-07
> **Frozen semantic basis:** SRS-VAL-01 Design v0.8 at `1170208`
> **Review basis:** Human REVISE ruling on Authorization Package v0.5 at `53dc314`
> **Purpose:** complete the frozen decision-state closure for REUSE, blocked non-recompute, RECOMPUTE authorization, and exact I-14 not-used validity.
> **Review ruling:** ACCEPT / FROZEN; see `docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_IMPLEMENTATION_FIXTURE_EXECUTION_AUTHORIZATION_PACKAGE_V0.6_ACCEPTANCE_20261007.md`.

## 1. Governance status and normative closure

This package is an authorization-plan design. It does not implement SRS-VAL,
create fixtures, execute an experiment, mutate Information Space, or change
SimiGo code.

```text
SRS-VAL-01 Design v0.8        ACCEPT / FROZEN / IMMUTABLE BASIS
Authorization Package v0.5    REVISE / SUPERSEDED BY V0.6
Authorization Package v0.6    ACCEPT / FROZEN
Implementation                NOT AUTHORIZED
Fixture preparation           NOT AUTHORIZED
Execution                     NOT AUTHORIZED
IS mutation                   NOT AUTHORIZED
SimiGo code change            NOT AUTHORIZED
```

v0.6 is self-contained. Authorization Package v0.1..v0.5 are provenance only.
Every normative requirement necessary for implementation, validation,
authorization, observation, and execution is restated in this document. No
requirement is inherited by an open-ended inheritance clause.

## 2. Immutable package identity

Every later record must bind:

```text
package_identity;
frozen_predicate_design =
  SRS-VAL-01 Design v0.8;
frozen_predicate_basis_commit =
  1170208;
package_design_revision =
  PACKAGE_V0.6;
package_integrity_binding =
  immutable commit/content binding of this package.
```

## 3. Frozen SRS-VAL predicate normative baseline

This section restates the frozen predicate requirements that any implementation
plan must preserve without reinterpretation.

### 3.1 Core semantic inputs

The predicate requires exact immutable bindings for the SRS, source relation,
dependencies, result, resolution rule, policy, provenance, lifecycle, freshness,
and current request. In particular:

```text
I-14  governing recompute/reuse authorization;
I-15  exact current reuse request;
I-16  validation observation boundary.
```

`I-14` must bind immutable governing semantic identity, exact immutable version,
immutable content/integrity evidence, source-relation scope, invalidation class,
request class, authorized result outcome, recomputation semantic class,
result-target derivation boundary, and exact canonical relation-identity rule.
It is required only on a RECOMPUTE authorization path. Pure REUSE records:

```text
I14_NOT_USED_NO_RECOMPUTE_PATH.
```

`I-15` is mandatory for every invocation. It is an exact semantic request
binding, not natural language or business intent. Missing, unstable, ambiguous,
or unmatched I-15 yields applicability `INDETERMINATE` and BLOCK.

`I-16` is mandatory for every invocation and must explicitly include boundary
identity, ordering/time evidence, SRS evidence, dependency state, result state,
freshness/policy evidence, lifecycle evidence, consistency evidence, close
boundary, exact I-15 reference, active exact I-14 reference or exact not-used
marker, and exact predicate-rule binding reference or exact not-used marker.

Omitted, ambiguous, unstable, mixed-boundary, or integrity-invalid
decision-critical input produces:

```text
BLOCK / VALIDATION_INPUT_STATE_INCONSISTENT.
```

### 3.2 G-V validation obligations

Every implementation must preserve:

```text
G-V1  SRS declaration integrity:
      addressable settlement identity, DECLARED_SETTLED birth status,
      immutable source-relation binding, exact canonical identity rule when
      applicable, distinct result identity, immutable provenance bindings.

G-V2  source relation:
      exact source identity and semantics, exact applicability coverage,
      lawful handling of invalidation records.

G-V3  dependencies:
      exact revision binding, resolution, integrity, role, necessity, and
      no blocking supersession/invalidation.

G-V4  result:
      exact immutable result identity/revision, resolution without recomputation,
      integrity, interpretability, and no supersession/invalidation.

G-V5  resolution and policy:
      exact immutable rule/version/integrity and exact applicable policy
      versions.

G-V6  provenance and lifecycle:
      immutable/exact evidence for production, declaration, dependency, result,
      and ordering; determinate lifecycle; no CONTESTED,
      UNRESOLVED_LIFECYCLE_CONFLICT, or INVALIDATED reusable state.

G-V7  freshness:
      every freshness requirement has applicable current lawful evidence or a
      typed blocker; FRESHNESS_RECHECK_REQUIRED remains blocking until positively
      cleared by lawful evidence.
```

### 3.3 Failure classification gate

A predicate-rule classification requires an exact immutable registered rule
binding containing identity, exact version, integrity/content address, and
covered failure classes. The bound version alone decides classification. Later
rules never retroactively reinterpret an earlier validation basis.

`G-CLASS` requires every surviving validation failure, unless a higher-precedence
rule already resolves the invocation, to undergo classification before
`BLOCKED_NON_RECOMPUTE_PATH` or `RECOMPUTE`.

`I14_NOT_USED_NO_RECOMPUTE_PATH` means the invocation lawfully established that no
RECOMPUTE authorization path was entered. It never means required classification
was skipped. Its validity is defined by §3.5.

### 3.4 Decision precedence and state completeness

Exactly one primary decision is returned:

```text
DP-0  observation boundary inconsistent/ambiguous/unstable
        → BLOCK;

DP-1  any observation, structural, provenance, result, source-relation,
      resolution, policy, or lifecycle HARD_BLOCK
        → BLOCK;

DP-2  applicability NOT_APPLICABLE or APPLICABILITY_INDETERMINATE
        → BLOCK;

DP-3  every surviving failure is first classified RECOMPUTE_ELIGIBLE by an exact
      immutable predicate-rule binding and exactly covered by valid I-14 and its
      valid semantic envelope
        → RECOMPUTE;

DP-4  no failure remains and all checks pass
        → REUSE.
```

`REUSE`, `BLOCK`, and `RECOMPUTE` are mutually exclusive. Failure alone never
authorizes recomputation. REUSE never requires I-14. Mixed eligible and
hard-block failures yield BLOCK.

### 3.5 Complete decision paths and I-14 not-used validity

The invocation resolves through exactly one completed decision path:

```text
REUSE_PATH
  no validation failure remains; all checks pass;
  I-14 = I14_NOT_USED_NO_RECOMPUTE_PATH.

BLOCKED_NON_RECOMPUTE_PATH
  lawful only when one of the following holds:
    1. a higher-precedence DP-0/DP-1/DP-2 rule already resolves the invocation;
    2. mandatory classification completes for every surviving failure and none
       is RECOMPUTE_ELIGIBLE.
  primary decision = BLOCK;
  I-14 = I14_NOT_USED_NO_RECOMPUTE_PATH.

RECOMPUTE_AUTHORIZATION_PATH
  at least one surviving failure is classified RECOMPUTE_ELIGIBLE by an exact
  immutable predicate-rule binding;
  exact immutable I-14 covers it;
  the RECOMPUTE semantic envelope is valid.
  primary decision = RECOMPUTE or BLOCK according to DP-3 and envelope/I-14
  validity.
```

`I14_NOT_USED_NO_RECOMPUTE_PATH` is valid only in exactly one of these states:

```text
1.  no validation failure remains;

2.  a higher-precedence DP-0/DP-1/DP-2 rule already resolves the invocation;

3.  mandatory classification completes for every surviving failure and none is
    classified RECOMPUTE_ELIGIBLE.
```

The marker is invalid if any surviving failure still requires classification. In
that state:

```text
decision = BLOCK;
reason   = PREDICATE_RULE_CLASSIFICATION_REQUIRED;
I14_NOT_USED_NO_RECOMPUTE_PATH = INVALID.
```

Therefore skipping classification cannot lawfully create a no-recompute path or
avoid the I-14 authorization path.

### 3.6 Implementation faithfulness

The implementation traceability matrix must map every I-14/I-15/I-16 rule,
predicate-rule rule, G-CLASS rule, G-V1..G-V7 rule, DP rule, invariant, typed
failure, decision path, and REUSE/BLOCK/RECOMPUTE boundary to a component, input, effect,
failure path, observing test, and forbidden alternate behavior.

No implementation may weaken, strengthen, reorder, omit, or reinterpret a frozen
rule. No mutable pointer may replace an exact semantic identity/version/content
binding. No missing evidence may be interpreted as a pass.

## 4. Immutable authorization trust chain

### 4.1 Runner Trust Anchor

Authorization begins at an immutable `Runner Trust Anchor`, not a mutable runner
configuration field.

Required anchor record:

```text
runner_trust_anchor_identity;
anchor_kind ∈ {
  IMMUTABLE_RUNNER_BUILD_BINDING,
  EXTERNALLY_PROTECTED_LAUNCH_CONFIGURATION,
  IMMUTABLE_GOVERNANCE_ANCHOR
};
runner_build_identity_or_launch_environment_identity;
trusted_authority_root_identity;
trusted_authority_root_content_address;
trusted_authority_root_integrity_binding;
anchor_integrity_binding;
anchor_governing_human_ruling_reference;
anchor_measurement_or_external_protection_evidence.
```

At least one of the following must hold:

```text
the anchor digest/identity is embedded in the immutable runner build;
the anchor is loaded from externally protected launch configuration whose
integrity and controller are independently measured;
the anchor is supplied by another immutable governance anchor.
```

Forbidden:

```text
mutable runtime configuration selecting the root;
environment variable overriding the anchor;
latest/current pointer;
operator-supplied root path;
unmeasured writable config file.
```

Before use, validate:

```text
runner build/launch identity matches the anchor;
anchor integrity verifies;
anchor is ACTIVE and within validity;
embedded root identity/content equals the anchored root;
anchor has not drifted at launch, pre-run, and post-run.
```

Failure:

```text
runner stop;
RUNNER_TRUST_ANCHOR_INVALID_OR_DRIFTED.
```

### 4.2 Authorization Authority Root

The anchored root record must contain:

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

The complete chain is:

```text
Runner Trust Anchor
  → Authorization Authority Root
  → Human Ruling
  → authorized issuer
  → Stage Authorization Record
  → Observer Authorization Record, when observation is used.
```

Root mismatch, mutable replacement, revoked/expired status, or absence of the
anchored root stops the runner with:

```text
AUTHORIZATION_TRUST_ROOT_INVALID.
```

### 4.3 Human Ruling Approval

The ruling must exact-bind:

```text
runner_trust_anchor_identity;
authorization_authority_root_identity;
trusted_human_authority_identity;
authorization_issuer_identity;
issuer_authority_scope;
issuer_status;
human_ruling_identity;
human_ruling_integrity_binding;
approved_record_identity;
approved_record_content_address;
approved_stage_or_role;
approval_status =
  APPROVED_FOR_NAMED_STAGE_OR_ROLE_ONLY;
approval_validity_boundary;
ruling_to_record_integrity_binding.
```

A correct hash without a root-backed Human approval is invalid.

### 4.4 Stage Authorization Record

Required stages remain independent:

```text
IMPLEMENTATION
  ≠ FIXTURE_PREPARATION
  ≠ EXECUTION
  ≠ IS_MUTATION.
```

Every record binds:

```text
authorization_identity;
authorization_kind =
  STAGE_AUTHORIZATION_RECORD;
stage;
package_identity and integrity;
frozen design identity/version/commit;
runner trust anchor identity;
authority root identity/content;
issuer identity and scope;
human ruling identity/content;
approved record identity/content;
repository revision where applicable;
fixture identities where applicable;
environment identity;
effect/mutation set;
filesystem scope;
network scope;
run IDs/budget;
validity;
use budget;
record integrity/content binding.
```

`IMPLEMENTATION` never authorizes fixture creation, execution, IS mutation, or
network access. `FIXTURE_PREPARATION` never authorizes implementation, execution,
IS mutation, or network access. `EXECUTION` reads declared inputs, executes exact
bound artifacts, and produces declared evidence; its effect set must not contain
`INFORMATION_SPACE_MUTATION`. `IS_MUTATION` is separate and exact.

`EXECUTION` must bind unconditionally:

```text
exact_repository_commit =
  immutable full commit SHA;
exact_implementation_artifact_content_address;
exact_executable_or_runtime_artifact_identity;
runtime_artifact_integrity_binding.
```

Branches, working trees, latest revisions, floating tags, unpinned containers, and
conditional code fields are invalid.

### 4.5 Observer Authorization Record

Observation is an authorized role, not merely an isolated process. Before any
authoritative observation, require an `Observer Authorization Record` in the same
root-backed chain.

It binds:

```text
observer_authorization_identity;
authorization_kind =
  OBSERVER_AUTHORIZATION_RECORD;
observer_identity;
observer_artifact_content_address;
observer_runtime_artifact_identity;
observer_environment_identity;
observer_execution_boundary;
observer_trust_boundary;
authorized_observation_scope;
authorized_observation_sources;
approved_channel_universe_identity;
approved_coverage_contract_identity;
observer_human_ruling_identity;
observer_human_ruling_integrity_binding;
observer_record_integrity_binding;
validity_boundary;
use_budget.
```

The Human Ruling must approve this exact observer artifact, runtime, environment,
scope, channel universe, and coverage contract. An isolated but unauthorized
observer cannot produce authoritative evidence.

## 5. Channel Universe and Environment Closure

Coverage is complete only relative to a preapproved universe of possible relevant
channels.

### 5.1 Channel Universe Contract

Create an immutable:

```text
channel_universe_identity;
environment_identity;
environment_measurement_evidence;
runner_and_runtime_inventory;
required_channel_classes;
declared_channel_classes;
impossible_channel_classes;
unclassified_channel_set;
universe_completeness_method;
universe_integrity_binding;
human_ruling_reference;
human_ruling_integrity_binding.
```

At minimum, evaluate:

```text
filesystem files and directories;
file descriptors and inherited descriptors;
network and socket traffic;
localhost and external services;
IPC and shared memory;
named pipes;
memory-mapped files;
process, fork, exec, and child-process boundaries;
signals;
runtime loading and callbacks;
IS/SRS reads and writes;
Information-Space mutations;
environment variables and injected resources;
device-backed state;
GPU/shared-accelerator state;
credential/helper services;
launch agents or service registrations;
filesystem watchers;
kernel objects relevant to communication;
persistent caches;
clock/entropy sources relevant to evidence;
state hashes and mutation effects.
```

Each channel class must be:

```text
COVERED by an authorized observer and coverage contract;
or IMPOSSIBLE with environment/impossibility evidence.
```

`UNCLASSIFIED` is forbidden. A discovered channel outside the universe does not
pass by omission; it invalidates the universe:

```text
runner stop;
CHANNEL_UNIVERSE_INCOMPLETE_OR_DRIFTED.
```

The universe, observer scope, and coverage contract must be exact-bound by the
same Human authorization. Observer self-definition of the universe is invalid.

## 6. Observation Integrity Boundary

### 6.1 Observer Integrity Record

Every proof requires:

```text
observation_integrity_record_identity;
observer_authorization_identity;
observer_identity;
observer_artifact_content_address;
observer_runtime_artifact_identity;
observer_environment_identity;
observer_execution_boundary;
observer_trust_boundary;
observation_source;
channel_universe_identity;
covered_channel_set;
impossible_channel_set;
uncovered_channel_set;
observation_start_boundary;
observation_stop_boundary;
observer_to_subject_separation_proof;
observer_tamper_resistance_proof;
observer_artifact_integrity_binding;
completeness_verdict.
```

### 6.2 Independence and validity

Hard rules:

```text
ES2 cannot authoritatively define its own observed_read_set.

The observer must start before the subject and stop after the subject.

Observer and subject must not share mutable state, writable configuration,
writable code, writable evidence storage, or control interfaces.

Observer artifact/runtime/configuration must match its authorization.

The observer must cover every COVERED channel and must not write subject-controlled
evidence.

Observer artifacts must revalidate after the run.
```

Failure reasons:

```text
OBSERVER_NOT_AUTHORIZED
OBSERVER_NOT_INDEPENDENT
OBSERVER_ARTIFACT_DRIFT
OBSERVER_TAMPERING_SUSPECTED
OBSERVATION_COVERAGE_INCOMPLETE.
```

Subject self-logs are supplementary only. External observation controls any
discrepancy.

## 7. Runtime dependency closure

Dependencies are classified:

```text
dependency_criticality ∈ {
  SEMANTIC,
  MECHANICAL
}.
```

Semantic dependencies affect predicate semantics, model behavior, result
generation, identity generation, IS semantics, or research conclusions. Examples
include the implementation artifact, relation/model semantics, model files,
tokenizer, plugins that alter behavior, policy/configuration consumed by the
predicate, IS mutation executor, and identity-generation service.

Mechanical dependencies support execution but are not claimed to define research
semantics. Examples may include standard loader/runtime internals, measured base
libraries, logging plumbing, and OS support artifacts.

### 7.1 EXECUTION dependency sets

The record must define:

```text
expected_semantic_runtime_dependency_set;
authorized_mechanical_runtime_dependency_set;
dependency_identity;
dependency_role;
dependency_criticality;
dependency_content_address_or_immutable_revision;
dependency_integrity_binding;
dependency_necessity_evidence.
```

The authorized observer must produce:

```text
observed_semantic_runtime_dependency_set;
observed_mechanical_runtime_dependency_set;
observed_dependency_identity;
observed_content_address_or_digest;
observed_source;
load_or_invoke_boundary;
undeclared_dependency_detected;
dependency_closure_verdict.
```

Required verdict:

```text
observed_semantic_runtime_dependency_set
  ==
expected_semantic_runtime_dependency_set;

observed_mechanical_runtime_dependency_set
  ⊆
authorized_mechanical_runtime_dependency_set;

undeclared_dependency_detected = false;

dependency_closure_verdict = PASS.
```

Any undeclared semantic dependency, semantic substitution, or unauthorized
mechanical dependency fails:

```text
SEMANTIC_RUNTIME_DEPENDENCY_MISMATCH
MECHANICAL_RUNTIME_DEPENDENCY_UNAUTHORIZED
RUNTIME_DEPENDENCY_CLOSURE_INCOMPLETE.
```

### 7.2 Mutation dependency closure

`IS_MUTATION` inherits this closure. Its semantic dependency set must equal the
authorized mutation executor/runtime/IS-semantic set. Its mechanical dependencies
must remain inside the authorized mechanical set.

## 8. IS_MUTATION execution closure

A separate IS_MUTATION record must bind:

```text
authorized_mutation_executor_identity;
authorized_mutation_executor_content_address;
authorized_mutation_runtime_artifact_identity;
authorized_mutation_environment_identity;
expected_semantic_mutation_dependency_set;
authorized_mechanical_mutation_dependency_set;
exact_affected_information_space_identities;
exact_mutation_operations;
exact_source_evidence_bindings;
expected_result_identity_or_revision;
expected_pre_state_content_address;
expected_post_state_content_address;
expected_mutation_set;
rollback_or_invalidity_evidence_requirement.
```

The authorized observer must record the observed executor, runtime, dependencies,
pre-state, post-state, and mutation set. The gate requires:

```text
observer authorization and channel universe PASS;
observed semantic mutation dependencies ==
  expected semantic mutation dependencies;
observed mechanical mutation dependencies ⊆
  authorized mechanical mutation dependencies;
observed executor identity/content ==
  authorized executor identity/content;
observed pre-state ==
  expected pre-state;
observed post-state ==
  expected post-state;
observed mutation set ==
  expected mutation set;
mutation_scope_verdict = PASS.
```

Failures:

```text
MUTATION_EXECUTOR_UNAUTHORIZED
MUTATION_DEPENDENCY_MISMATCH
MUTATION_STATE_DRIFT
MUTATION_SCOPE_VIOLATION.
```

`EXECUTION` authorization never grants mutation.

## 9. Read-instance immutability

For each declared semantic input read, use one binding kind:

```text
declared_input_binding_kind ∈ {
  CONTENT_ADDRESS,
  IMMUTABLE_REVISION
}.
```

If `CONTENT_ADDRESS`:

```text
declared_content_digest;
declared_digest_algorithm;
content_to_digest_binding.
```

If `IMMUTABLE_REVISION`:

```text
declared_immutable_revision;
revision_to_content_digest_binding;
resolved_declared_content_digest;
declared_digest_algorithm.
```

A revision number is never compared as if it were a digest.

Each read instance records:

```text
read_instance_identity;
declared_input_identity;
declared_input_binding_kind;
declared_content_digest or resolved_declared_content_digest;
read_time_content_digest;
read_instance_snapshot_or_atomicity_proof;
observer_authorization_identity;
channel_universe_identity;
read_begin_boundary;
read_end_boundary;
consumed_content_matches_declaration.
```

Accepted proof forms:

```text
IMMUTABLE_SNAPSHOT_PRESEALED;
ATOMIC_VERSIONED_READ_HANDLE;
OBSERVED_MEDIATED_READ.
```

Required result:

```text
read_time_content_digest ==
  declared/resolved declared content digest;

consumed_content_matches_declaration = true;

input binding kind and digest binding verify.
```

Before/after equality alone is invalid. Failures:

```text
READ_INSTANCE_NOT_IMMUTABLE
READ_TIME_CONTENT_MISMATCH
REVISION_TO_DIGEST_BINDING_INVALID.
```

## 10. Combined execution gate

Before execution, require:

```text
valid immutable Runner Trust Anchor;
valid Authorization Authority Root chain;
valid Stage Authorization Record for each stage;
valid Observer Authorization Record and coverage contract;
valid Channel Universe / Environment Closure;
exact EXECUTION artifact bindings where applicable;
exact IS_MUTATION executor binding where applicable;
declared input and read-instance binding plan;
expected semantic and authorized mechanical dependency sets.
```

During and after execution, require:

```text
anchor, authority, observer, package, code, environment, and universe integrity;
observer independence and complete coverage;
no UNCLASSIFIED channel;
semantic dependencies exactly expected;
mechanical dependencies subset authorized;
semantic input reads exactly declared;
read-time content matches declared/resolved digest;
mutation effects exactly declared where applicable;
no authorization, artifact, universe, or state TOCTOU drift.
```

Any failure stops the run and invalidates the affected proof.

## 11. Boundary-case matrix

The implementation/fixture plan must include all of the following cases.

### 11.1 Predicate and validation boundary

```text
B-REUSE-01    valid pure REUSE with no failure and no I-14.
B-BLOCK-01    DP-0 boundary inconsistency.
B-BLOCK-02    DP-1 lifecycle HARD_BLOCK despite another eligible failure.
B-BLOCK-03    DP-2 NOT_APPLICABLE or APPLICABILITY_INDETERMINATE.
B-BLOCK-04    surviving failure classified non-eligible; expected primary
              decision = BLOCK.
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
B-VAL-01      surviving failure plus I14_NOT_USED_NO_RECOMPUTE_PATH plus
              incomplete classification; expected outcome = STOP /
              PREDICATE_RULE_CLASSIFICATION_REQUIRED.
```

### 11.2 Authorization and observation boundary

```text
B-AUTH-01     required Stage Authorization Record absent.
B-AUTH-02     valid record used for a different stage.
B-AUTH-03     authorization scope overbroad or includes undeclared effect.
B-AUTH-04     record hash valid but Human Ruling Approval absent/mismatched.
B-AUTH-05     executed revision differs from exact authorized revision.
B-AUTH-06     EXECUTION effect set attempts INFORMATION_SPACE_MUTATION.
B-AUTH-07     authorization or bound artifact drifts after validation.
B-AUTH-08     run budget valid but run identity not preregistered.
B-AUTH-09     IS mutation occurs without separate valid IS_MUTATION record.
B-AUTH-10     valid record hash but no pinned Runner Trust Anchor.
B-AUTH-11     issuer not authorized by root-backed ruling.
B-AUTH-12     mutable runner configuration replaces the trust anchor.
B-AUTH-13     observer is isolated but lacks Observer Authorization Record.
B-AUTH-14     observer scope or coverage contract differs from Human approval.
B-OBS-01      observer is subject-controlled or shares writable trust boundary.
B-OBS-02      observer lacks coverage for a relevant universe channel.
B-OBS-03      observer artifact/configuration changes after prebinding.
B-OBS-04      subject self-report is used as authoritative observed evidence.
B-OBS-05      channel universe contains an UNCLASSIFIED discovered channel.
B-OBS-06      observer declares completeness without an approved universe.
```

### 11.3 Runtime, mutation, and input boundary

```text
B-RUNTIME-01  unauthorized dynamic library or plugin is loaded.
B-RUNTIME-02  environment-injected model/configuration/cache affects execution.
B-RUNTIME-03  semantic dependency substituted while mechanical allowlist passes.
B-RUNTIME-04  semantic dependency set is a subset rather than exact equality.
B-MUT-01      authorized mutation target runs through an unbound executor.
B-MUT-02      observed mutation set contains an extra operation.
B-MUT-03      mutation observer or channel universe is incomplete.
B-READ-01     mutable carrier has equal before/after hashes but changes at read
              time.
B-READ-02     read-time digest differs from declared content digest.
B-READ-03     immutable revision is compared directly as a digest.
B-READ-04     revision-to-content-digest binding is missing or invalid.
```

Each case has one auditable pass/stop outcome and no discretionary override.

## 12. Decision requested

```text
ACCEPT PACKAGE V0.6   freeze the trust, observation, execution, runtime, and
                      input closures; no stage is executed until separately
                      authorized.
REVISE PACKAGE V0.6   return with registered defects.
REJECT PACKAGE V0.6   do not proceed.
```

No implementation, fixture preparation, experiment, IS mutation, or SimiGo code
change is authorized by this document.
