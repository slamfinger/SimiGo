# SRS-VAL-01 Implementation Boundary Audit v0.1

> **Status:** AUDIT V0.1 DELIVERED FOR HUMAN REVIEW — DESIGN / AUDIT ONLY
> **Date:** 2026-10-07
> **Audit basis:** `6089f0b`
> **Frozen semantic basis:** SRS-VAL-01 Design v0.8 at `1170208`
> **Frozen governance basis:** Authorization Package v0.6 at `047b221`; acceptance registered at `6089f0b`
> **Boundary question:** what is the minimal lawfully authorizable Implementation Target for SRS-VAL-01?
> **Implementation / fixture / experiment:** NOT AUTHORIZED
> **IS mutation:** NOT AUTHORIZED
> **SimiGo code change:** NOT AUTHORIZED

## 1. Audit verdict

```text
Minimal Implementation Target =
  SRS-VAL-01 Decision Core

Definition =
  a pure, side-effect-free semantic predicate module that accepts one exact
  validation invocation record and returns exactly one primary decision plus
  typed evidence/trace;

  SRS-VAL Invocation Record
    → Decision Core
    → REUSE | BLOCK | RECOMPUTE
      + typed failure/evidence trace.

The Decision Core is the only proposed first implementation target.

Carrier, persistence, runner, observer, fixture builder, model/runtime,
execution harness, and IS mutation executor are NOT part of the minimal target.
```

This is an audit recommendation for Human review. It does not authorize
implementation.

## 2. Authority and non-amendment boundary

This audit inherits no permission. It only maps the frozen obligations to a
proposed implementation boundary.

```text
SRS-SEM-01 Design v0.5      ACCEPT / FROZEN / semantic input basis
SRS-VAL-01 Design v0.8      ACCEPT / FROZEN / predicate basis
Authorization Package v0.6  ACCEPT / FROZEN / execution governance basis
Implementation              NOT AUTHORIZED
Fixture preparation         NOT AUTHORIZED
Execution                   NOT AUTHORIZED
IS mutation                 NOT AUTHORIZED
SimiGo code change          NOT AUTHORIZED
```

No statement here may weaken, reinterpret, or amend v0.8 or v0.6.

## 3. Implementation Target — proposed minimal boundary

### 3.1 Target name and placement

Proposed future implementation name:

```text
T-IMPL-01 = SRS-VAL Decision Core

candidate module =
  SettledRelationValidationCore;

candidate source placement =
  trackD-memory/Sources/SettledRelationValidationCore;

candidate dependency policy =
  Swift standard library only;

forbidden dependencies =
  MLX/LLM stack,
  carrier database,
  filesystem access,
  network access,
  process execution,
  global mutable state,
  date/time acquisition,
  random number generation,
  logger as decision authority.
```

The exact path/product and SwiftPM registration must be fixed in the later
Implementation Authorization Request / Run Manifest. This audit does not open or
authorize that change.

### 3.2 Required capabilities inside the Decision Core

```text
C1  Immutable validation invocation record:
    I-1..I-16-style exact bindings, including SRS, source relation,
    dependencies, result, resolution, policy, provenance, lifecycle,
    freshness, I-14, I-15, I-16, and exact predicate-rule binding when
    classification is required.

C2  G-V1..G-V7 evaluation:
    SRS declaration, source relation, dependency, result,
    resolution/policy, provenance/lifecycle, and freshness checks.

C3  I-16 completeness:
    explicit membership of every decision-critical input and typed
    VALIDATION_INPUT_STATE_INCONSISTENT failure on omission/mixed boundary.

C4  Applicability:
    exact comparison of I-15 to the SRS source-relation applicability boundary;
    NOT_APPLICABLE and APPLICABILITY_INDETERMINATE yield BLOCK.

C5  Exact predicate-rule classification:
    only the invocation-bound immutable rule identity/version/integrity may
    classify a surviving failure.

C6  G-CLASS:
    every surviving failure not already resolved by higher precedence must be
    classified before BLOCKED_NON_RECOMPUTE_PATH or RECOMPUTE.

C7  I-14 conditional authorization:
    pure REUSE does not require I-14;
    RECOMPUTE requires exact immutable I-14 plus valid semantic envelope.

C8  Decision state closure:
    REUSE_PATH,
    BLOCKED_NON_RECOMPUTE_PATH,
    RECOMPUTE_AUTHORIZATION_PATH,
    and the three lawful states of I14_NOT_USED_NO_RECOMPUTE_PATH.

C9  DP-0..DP-4 precedence:
    exactly one primary decision: REUSE, BLOCK, or RECOMPUTE.

C10 Typed output:
    primary decision, matched decision path, typed failures, classification
    evidence, binding verification results, and enough data for later
    externally observed execution evidence to be correlated.
```

### 3.3 Explicit non-capabilities

The Decision Core must not:

```text
read or write filesystem;
open network/IPC/database connections;
create, update, delete, or mint Information Space objects;
execute the settled relation or recomputation;
load model/tokenizer/plugin artifacts;
construct fixtures;
observe itself as authoritative evidence;
launch runners or child processes;
trust caller-supplied observation as decision input;
depend on wall-clock, random, locale, environment, or global mutable state;
implicitly authorize another stage.
```

Any one of these would move the work outside T-IMPL-01.

## 4. Existing infrastructure classification

| Existing area | Classification | Reason | First implementation role |
|---|---|---|---|
| `trackD-memory/Sources/InformationCore` | Existing carrier/runtime semantic foundation | Implements frozen immutable Information semantics and provenance primitives, not SRS-VAL decision | Reference/adapter source only; not T-IMPL-01 |
| `trackD-memory/Sources/RelationCore` | Existing relation/carrier foundation | Relation and relation-store semantics predate SRS-VAL and do not decide reuse | Reference/adapter source only; not T-IMPL-01 |
| `trackD-memory/Sources/CarrierInterface` | Carrier/runtime boundary | Abstract carrier/session/observation types are runtime infrastructure, not the frozen predicate | Excluded from T-IMPL-01 |
| `trackD-memory/Sources/CarrierSQLite` | Carrier implementation/storage | Persistence/SQLite is carrier infrastructure | Excluded from T-IMPL-01 |
| `trackD-memory/Sources/ExecutionCore` | ES/relation execution support | Executes/mints relation work; SRS-VAL must not execute work | Excluded from T-IMPL-01 |
| `simigo2-experimental/Sources/SimiGo2Experimental` | App/runtime/experimental stack | MLX/LLM/runtime/experiment concerns are outside the pure predicate | Excluded from T-IMPL-01 |
| Root `Package.swift` | Integration manifest | Any target registration is a code change requiring later authorization | Excluded until Implementation Authorization |

No existing module is already the SRS-VAL Decision Core. Reusing existing types
may occur only through explicitly bound, immutable input adapters defined in the
later manifest.

## 5. Fixture Target boundary

### 5.1 Required fixture families

```text
F-ES1   Source Execution State fixture producing or representing the settled
        relation without supplying live ES1 state to ES2.

F-SRS   Immutable SRS fixture containing exact semantic bindings for source
        relation, dependencies, result, resolution, policy, provenance, and
        lifecycle.

F-DEP   Immutable dependency-state snapshots with content/revision/integrity
        bindings.

F-ES2   Independent ES2 input/request fixture, including exact I-15 and the
        declared IS/SRS artifacts it may read.

F-AUTH  I-14 fixture present only for RECOMPUTE cases; pure REUSE cases record
        I14_NOT_USED_NO_RECOMPUTE_PATH.

F-RULE  Immutable predicate-rule fixture binding exact rule identity, version,
        integrity, and covered failure classes.

F-DEC   Expected primary decision and typed evidence for every case.
```

### 5.2 Allowed fixture content

```text
content-addressed immutable snapshots;
exact immutable revisions with revision-to-digest bindings;
declared IS/SRS artifact snapshots;
declared immutable execution inputs;
expected decision and expected typed failure records;
observer coverage contracts;
declared runtime dependency manifests.
```

### 5.3 Forbidden hidden channels

No fixture may communicate through:

```text
live ES1 process/memory/model context;
agent/conversation memory;
singleton/static/global cache;
undeclared filesystem/temp artifact;
undeclared IPC/shared memory/named pipe;
network/localhost service;
mutable environment variable;
hidden runner cache;
unversioned model/tokenizer/plugin/config;
production Information Space.
```

Fixture equality does not imply Execution-State independence. ES1 termination and
ES2 provenance closure remain mandatory.

## 6. Run/Implementation Manifest field groups

The later manifest must turn the frozen package into concrete, reviewable fields.

### 6.1 Identity and frozen basis

```text
manifest_identity;
audit_basis = IMPLEMENTATION_BOUNDARY_AUDIT_V0.1;
frozen_predicate_design =
  SRS-VAL-01 Design v0.8;
frozen_predicate_basis_commit = 1170208;
frozen_governance_package =
  Authorization Package v0.6;
frozen_governance_basis_commit = 047b221;
authorization_request_reference;
human_ruling_reference.
```

### 6.2 Implementation stage

```text
implementation_stage_record;
authorized_repository_revision;
authorized_writable_path_set;
target_module_identity;
target_module_content_address_after_build;
forbidden_path_set;
forbidden_dependency_set;
implementation_completion_evidence.
```

### 6.3 Fixture stage

```text
fixture_stage_record;
fixture_set_identity;
fixture_content_addresses;
fixture_revision_to_digest_bindings;
fixture_roles;
independence_boundary;
allowed_artifact_set;
forbidden_artifact_set;
fixture_completion_evidence.
```

### 6.4 Execution stage

```text
execution_stage_record;
exact_repository_commit;
exact_implementation_artifact_content_address;
exact_executable_or_runtime_artifact_identity;
runtime_artifact_integrity_binding;
environment_identity;
run_id_or_run_budget;
authorized_effect_set;
filesystem_scope;
network_scope;
validity_boundary.
```

### 6.5 Observer and channel universe

```text
observer_authorization_identity;
observer_artifact_content_address;
observer_runtime_identity;
observer_environment_identity;
observer_scope;
channel_universe_identity;
covered_channel_classes;
impossible_channel_classes;
unclassified_channel_set = empty;
coverage_contract_identity;
observer_start/stop boundaries;
observer_integrity_binding.
```

### 6.6 Runtime dependency closure

```text
expected_semantic_runtime_dependency_set;
authorized_mechanical_runtime_dependency_set;
observed_semantic_runtime_dependency_set;
observed_mechanical_runtime_dependency_set;
semantic_closure_verdict =
  observed semantic set == expected semantic set;
mechanical_closure_verdict =
  observed mechanical set ⊆ authorized mechanical set;
undeclared_dependency_detected = false.
```

### 6.7 Read-instance and evidence

```text
declared_input_binding_kind ∈ {
  CONTENT_ADDRESS,
  IMMUTABLE_REVISION
};
declared_content_digest or revision_to_content_digest_binding;
read_instance_identity;
read_time_content_digest;
snapshot_or_atomicity_proof;
observer_identity;
evidence_artifact_content_addresses;
before/after state hashes.
```

### 6.8 Termination and ES independence

```text
es1_runtime_identity;
es2_runtime_identity;
es1_process_boundary;
es2_process_boundary;
es1_termination_or_approved_exception_evidence;
es2_runtime_initialization_boundary;
shared_state_scan_result;
transient_state_reliance_scan_result;
allowed_shared_artifact_bindings;
forbidden_shared_artifact_bindings.
```

## 7. Stage separation check

```text
IMPLEMENTATION
  may create only the authorized source/path scope.
  ≠ fixture creation, execution, IS mutation, network access.

FIXTURE_PREPARATION
  may create only named immutable fixture artifacts.
  ≠ implementation change, execution, IS mutation, network access.

EXECUTION
  may execute only exact bound artifacts under the declared effect set.
  ≠ implementation change, fixture creation, IS mutation.

IS_MUTATION
  is a separate record/stage with its own executor/runtime/dependency/state/effect
  closure.
  ≠ EXECUTION and never derivable from EXECUTION.
```

Required rule:

```text
No stage authorization may imply, expand, renew, or substitute another stage.
A manifest lacking any required stage record stops before that stage.
```

## 8. Implementation-contract hard points

### 8.1 Mutation evidence structure

The later mutation contract must preserve, at minimum:

```text
mutation_instance_identity;
mutation_operation_identity;
operation_order;
transaction_or_atomicity_boundary;
pre_state_content_address;
post_state_content_address;
observed_execution_trace_identity;
trace_integrity_binding.
```

Equality of an unordered mutation set is not complete mutation equivalence.

### 8.2 Runtime evidence structure

The later runtime contract must keep two disjoint evidence layers:

```text
semantic_dependency_evidence:
  expected/observed semantic dependency identity,
  content/revision digest,
  role,
  necessity,
  exact-equality verdict;

mechanical_dependency_evidence:
  loader/runtime/OS support dependency,
  authorized allowlist membership,
  observed subset verdict,
  non-semantics justification.
```

Mechanical bookkeeping must not be promoted to semantic dependency evidence.

## 9. Adversarial pre-review checklist

Before any Human Authorization Request, the manifest draft must be attacked for:

```text
A1  Fixture answer leakage:
    does any fixture let ES2 obtain the result except declared IS/SRS artifacts?

A2  Observer contamination:
    can the subject alter, disable, scope-limit, or forge observer evidence?

A3  Hidden continuation/side channel:
    can ES1 reach ES2 through process, memory, conversation, cache, descriptor,
    file, IPC, service, signal, watcher, or device state?

A4  Implementation artifact drift:
    can built artifact, runtime, dependency, config, model, tokenizer, plugin,
    or executable differ from the authorized identity?

A5  Semantic dependency pollution:
    can a mechanical dependency change predicate semantics while passing as
    bookkeeping?

A6  Indirect IS mutation:
    can EXECUTION, a plugin, local service, environment resource, or dependency
    mutate Information Space without a separate IS_MUTATION authorization?

A7  Stage bleed:
    can one authorization record expand into another stage?

A8  Decision-state bypass:
    can incomplete classification or a fake not-used marker avoid G-CLASS/I-14?

A9  Read drift:
    can before/after hashes match while the consumed version differs?

A10 Evidence self-certification:
    can the subject or runner produce authoritative evidence outside the
    authorized observer trust chain?
```

Each attack must map to a manifest field, observer source, expected stop/pass
outcome, and evidence artifact.

## 10. Proposed sequencing after Human review of this audit

```text
1. Human reviews and rules on Implementation Boundary Audit v0.1.
2. Prepare Run/Implementation Manifest draft against the accepted target.
3. Perform adversarial pre-review of that manifest.
4. Human opens the Authorization Request.
5. Human separately authorizes only requested stages:
   IMPLEMENTATION / FIXTURE_PREPARATION / EXECUTION / IS_MUTATION.
6. Authorized implementation creates immutable artifact identity.
7. Separate execution authorization is reviewed before any run.
8. Execution occurs only under the frozen governance and observation boundary.
```

## 11. Decision requested

```text
ACCEPT AUDIT V0.1   freeze the proposed minimal Implementation Target boundary
                    and authorize only preparation of a Run/Implementation
                    Manifest draft; still no code, fixture, run, or IS mutation.

REVISE AUDIT V0.1   return with registered boundary defects.

REJECT AUDIT V0.1   do not proceed.
```

No implementation, fixture preparation, execution, IS mutation, or SimiGo code
change is authorized by this document.
