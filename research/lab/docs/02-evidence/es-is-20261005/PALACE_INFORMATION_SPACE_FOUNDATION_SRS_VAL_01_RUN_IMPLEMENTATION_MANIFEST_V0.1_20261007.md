# SRS-VAL-01 Run/Implementation Manifest Contract v0.1

> **Status:** MANIFEST CONTRACT V0.1 REVISE — SUPERSEDED BY V0.2 — DESIGN ONLY / NO STAGE AUTHORIZED
> **Date:** 2026-10-07
> **Frozen predicate basis:** SRS-VAL-01 Design v0.8 at `1170208`
> **Frozen governance basis:** Authorization Package v0.6 at `047b221`, accepted at `6089f0b`
> **Frozen implementation boundary:** Implementation Boundary Audit v0.1 at `cb95c09`
> **Purpose:** convert the frozen T-IMPL-01 boundary and Authorization Package v0.6 obligations into a reviewable stage-separated manifest contract.
> **Review ruling:** REVISE; see `docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_RUN_IMPLEMENTATION_MANIFEST_V0.1_REVIEW_RULING_20261007.md`.
> **Superseded by:** `docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_RUN_IMPLEMENTATION_MANIFEST_V0.2_20261007.md`.

## 1. Scope and authority

This document is a design-only manifest contract. It is not a filled execution
manifest, authorization request, implementation, fixture, runner, observer, or
Information-Space mutation.

```text
SRS-VAL-01 Design v0.8              ACCEPT / FROZEN / IMMUTABLE BASIS
Authorization Package v0.6          ACCEPT / FROZEN / IMMUTABLE GOVERNANCE BASIS
Implementation Boundary Audit v0.1  ACCEPT / FROZEN / T-IMPL-01 MINIMUM TARGET
Run/Implementation Manifest v0.1    SUBMITTED FOR HUMAN REVIEW
Implementation                      NOT AUTHORIZED
Fixture preparation                 NOT AUTHORIZED
Execution                           NOT AUTHORIZED
IS mutation                         NOT AUTHORIZED
SimiGo code change                  NOT AUTHORIZED
```

Acceptance of this contract would freeze only the manifest schema and review
obligations. Each later stage still requires an explicit, scope-bound Human
Authorization Record.

## 2. Frozen implementation target

The only authorized future implementation boundary is:

```text
T-IMPL-01 = SRS-VAL Decision Core

input:
  closed immutable validation invocation value graph;

output:
  exactly one primary decision
    REUSE | BLOCK | RECOMPUTE;
  deterministic semantic derivation trace;
  typed failures and binding verdicts.
```

T-IMPL-01 excludes carrier, SQLite, persistence, runner, observer, fixture
builder, model/runtime stack, execution harness, and IS mutation executor.

No manifest field may expand T-IMPL-01 into those targets.

## 3. Manifest identity and lifecycle

This contract distinguishes the reviewable schema from a later filled manifest.

### 3.1 Contract identity

```text
manifest_contract_identity =
  SRS_VAL_01_RUN_IMPLEMENTATION_MANIFEST_CONTRACT_V0.1;

frozen_predicate_design =
  SRS-VAL-01 Design v0.8;
frozen_predicate_basis_commit = 1170208;

frozen_governance_package =
  Authorization Package v0.6;
frozen_governance_basis_commit = 047b221;

frozen_implementation_boundary =
  Implementation Boundary Audit v0.1;
frozen_boundary_basis_commit = cb95c09;

manifest_contract_integrity_binding =
  immutable commit/content binding of this document.
```

### 3.2 Future manifest instance

A future filled manifest must bind:

```text
manifest_instance_identity;
manifest_contract_identity =
  SRS_VAL_01_RUN_IMPLEMENTATION_MANIFEST_CONTRACT_V0.1;
authorization_request_reference;
human_ruling_reference;
requested_stage_set;
artifact identities for every requested stage;
environment identity;
observer and channel-universe identities;
evidence locations and integrity bindings;
validity and use budgets.
```

No instance may be created or executed until the Human authorization request is
separately approved.

## 4. Hard constraint H1 — predicate rule artifact independence

The Decision Core and Registered Predicate Rule Artifact are separate immutable
objects.

### 4.1 Required rule artifact record

```text
predicate_rule_artifact_identity;
predicate_rule_identity;
predicate_rule_version;
predicate_rule_content_address;
predicate_rule_integrity_binding;
covered_failure_classes;
rule_semantic_boundary;
rule_registration_authority_identity;
rule_authority_root_chain;
rule_human_ruling_reference;
rule_validity_boundary;
rule_artifact_integrity_binding.
```

### 4.2 Decision Core binding record

The invocation must carry a resolved immutable binding:

```text
decision_core_artifact_identity;
decision_core_content_address;
bound_predicate_rule_artifact_identity;
bound_predicate_rule_identity;
bound_predicate_rule_version;
bound_predicate_rule_content_address;
bound_rule_integrity_binding;
covered_failure_classes;
rule_binding_verification_verdict.
```

### 4.3 Anti-self-registration rules

Forbidden:

```text
Decision Core generating its own rule identity;
Decision Core declaring itself to be the rule artifact;
runtime creation or replacement of the rule artifact;
mutable registry lookup as semantic authority;
rule name, label, or local path as semantic binding;
Decision Core choosing a latest/current rule;
rule and Decision Core sharing one unpinned artifact.
```

Required proof:

```text
rule artifact and Decision Core artifact identities differ;
both artifacts have independent content bindings;
the rule registration descends from the frozen authority chain;
the invocation binding equals the approved rule artifact;
the Decision Core only interprets the bound rule.
```

Failure:

```text
PREDICATE_RULE_SELF_REGISTRATION_OR_BINDING_INVALID
```

## 5. Hard constraint H2 — derivation trace is not observation evidence

There are two non-interchangeable evidence classes.

### 5.1 Decision Core derivation trace

Decision Core may produce:

```text
trace_identity;
trace_class =
  DETERMINISTIC_SEMANTIC_DERIVATION_TRACE;
input_value_graph_digest;
decision_core_artifact_identity;
bound_rule_artifact_binding;
evaluated_gv_rules;
matched_dp_rule;
failure_classifications;
i14_applicability;
i14_not_used_marker_state;
final_decision_path;
final_primary_decision;
typed_failure_records;
trace_integrity_binding.
```

This proves semantic derivation from the closed input. It does not prove that an
external execution observed the subject faithfully.

### 5.2 Observer-authoritative execution evidence

Authoritative execution evidence must come from:

```text
Subject
  → Independent Observer
  → Observation Integrity Boundary
```

and must be labeled:

```text
evidence_class =
  OBSERVER_AUTHORITATIVE_EXECUTION_EVIDENCE.
```

Required observer evidence classes remain separate:

```text
process/runtime evidence;
filesystem/network/IPC/channel evidence;
loaded runtime dependency evidence;
read-instance evidence;
termination/evidence boundary evidence;
mutation evidence where separately authorized.
```

### 5.3 Prohibition

```text
Decision Core derivation trace
  ≠ observer-authoritative execution evidence.

Subject self-report
  ≠ observer-authoritative evidence.

A valid derivation trace cannot certify its own execution, runtime isolation,
input capture, observation completeness, or absence of side channels.
```

Any manifest field that uses derivation output as observation proof is invalid.

## 6. Hard constraint H3 — closed immutable Invocation Record

The entire T-IMPL-01 input must be a closed immutable value graph.

### 6.1 Required record properties

```text
invocation_record_identity;
invocation_record_content_address;
invocation_value_graph_digest;
deep_immutable_value_graph = true;
all_external_references_resolved = true;
all_revision_to_digest_bindings_verified = true;
no_unresolved_pointer = true;
closure_verdict = PASS.
```

Every node must be an immutable value or a resolved immutable content/revision
binding. Nested collections must be immutable and deterministic.

### 6.2 Forbidden node classes

The graph must not contain:

```text
lazy resolver;
file handle;
database handle;
socket or connection;
actor reference;
closure or callback;
environment lookup;
clock lookup;
random source;
global registry;
mutable reference;
unresolved latest/current pointer;
agent/conversation memory reference;
subject-controlled evidence producer.
```

### 6.3 I-14 and predicate-rule conditional nodes

The graph includes:

```text
exact I-15 binding;
I-16 boundary closure;
active exact I-14 binding or exact I14_NOT_USED_NO_RECOMPUTE_PATH marker;
exact predicate-rule artifact binding or exact not-used marker,
  according to the frozen G-CLASS state.
```

The I-14 not-used marker remains valid only in the three frozen states:

```text
1. no validation failure remains;
2. higher-precedence DP-0/DP-1/DP-2 already resolves;
3. mandatory classification completes for every surviving failure and none is
   RECOMPUTE_ELIGIBLE.
```

### 6.4 Closure failure

Any forbidden node, unresolved reference, mutable node, or post-closure change
produces:

```text
INVOCATION_RECORD_NOT_CLOSED
INVOCATION_RECORD_MUTATED_AFTER_CLOSURE.
```

A non-closed record may not enter T-IMPL-01.

## 7. Manifest record groups

A future filled manifest must include these groups. Empty sets are valid only
when explicitly justified and authorized.

### 7.1 Common identity

```text
manifest_instance_identity;
manifest_contract_identity;
frozen design/governance/boundary basis;
authorization_request_reference;
human_ruling_reference;
requested_stage_set;
validity_boundary.
```

### 7.2 IMPLEMENTATION stage

```text
implementation_authorization_record_identity;
authorized_repository_revision;
authorized_writable_path_set;
target_module = SettledRelationValidationCore;
forbidden_path_set;
forbidden_dependency_set;
build_or_artifact_plan;
implementation_completion_evidence_requirements;
result_artifact_content_address_placeholder.
```

### 7.3 FIXTURE_PREPARATION stage

```text
fixture_authorization_record_identity;
fixture_set_identity;
fixture_roles:
  F-ES1, F-SRS, F-DEP, F-ES2, F-AUTH, F-RULE, F-DEC;
fixture content addresses;
fixture revision-to-digest bindings;
independence boundary;
allowed artifact set;
forbidden artifact set;
expected decisions and typed failures.
```

### 7.4 EXECUTION stage

```text
execution_authorization_record_identity;
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

### 7.5 Observer and channel universe

```text
observer_authorization_record_identity;
observer_artifact_content_address;
observer_runtime_artifact_identity;
observer_environment_identity;
observer_scope;
channel_universe_identity;
covered_channel_classes;
impossible_channel_classes;
unclassified_channel_set = empty;
coverage_contract_identity;
observer_start/stop boundaries;
observer_integrity_binding;
observer_human_ruling_reference.
```

### 7.6 Runtime dependency closure

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

### 7.7 Input and read instance

```text
invocation_value_graph_identity;
declared_input_binding_kind ∈ {
  CONTENT_ADDRESS,
  IMMUTABLE_REVISION
};
declared_content_digest or immutable revision plus exact
  revision_to_content_digest_binding;
expected_read_set;
observed_read_set;
read_instance_identity;
read_time_content_digest;
snapshot_or_atomicity_proof;
observer_identity.
```

### 7.8 Evidence separation

```text
decision_core_derivation_trace_identity;
derivation_trace_class =
  DETERMINISTIC_SEMANTIC_DERIVATION_TRACE;
observer_evidence_record_identities;
observer_evidence_class =
  OBSERVER_AUTHORITATIVE_EXECUTION_EVIDENCE;
evidence_artifact_content_addresses;
evidence_integrity_bindings.
```

### 7.9 Termination and ES independence

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

### 7.10 IS_MUTATION stage, only if separately requested

```text
is_mutation_authorization_record_identity;
mutation_executor_identity;
mutation_executor_content_address;
mutation_runtime_artifact_identity;
mutation_environment_identity;
affected_information_space_identities;
mutation_operation_identities;
ordered_mutation_trace;
operation_order;
transaction_or_atomicity_boundary;
pre_state_content_address;
post_state_content_address;
observed_execution_trace_identity;
rollback_or_invalidity_evidence_requirement.
```

Unordered mutation-set equality is not complete mutation equivalence. A valid
mutation record must preserve operation identity, order, atomicity boundary, and
observer trace.

## 8. Stage separation gate

```text
IMPLEMENTATION
  ≠ FIXTURE_PREPARATION
  ≠ EXECUTION
  ≠ IS_MUTATION.
```

Required rules:

```text
IMPLEMENTATION may alter only its exact source/path scope.
FIXTURE_PREPARATION may create only named immutable fixtures.
EXECUTION may run only exact bound artifacts under its declared effect set.
IS_MUTATION requires a separate record and can never derive from EXECUTION.

A missing, invalid, expired, overbroad, cross-stage, or drifted record stops
before that stage.
```

## 9. Required adversarial manifest review

Before any Human Authorization Request, reviewers must attack:

```text
A1  rule self-registration or rule/Decision-Core artifact conflation;
A2  derivation trace used as observer evidence;
A3  non-closed or mutable Invocation Record;
A4  fixture answer leakage;
A5  observer subject contamination;
A6  hidden continuation/side channel;
A7  implementation/runtime artifact drift;
A8  semantic dependency hidden as mechanical dependency;
A9  EXECUTION indirectly obtaining IS mutation;
A10 stage authorization expansion;
A11 incomplete classification or fake I-14 not-used marker;
A12 read-time content drift;
A13 evidence self-certification.
```

Each attack must map to a manifest field, expected stop/pass outcome, observer
source, and evidence artifact.

## 10. Acceptance criteria for this contract

```text
ACCEPT MANIFEST V0.1   freeze the schema and hard constraints; authorize only
                       preparation of a future Human Authorization Request; no
                       code, fixture, run, or mutation.

REVISE MANIFEST V0.1   return with registered defects.

REJECT MANIFEST V0.1   do not proceed.
```

## 11. Decision requested

Accept, revise, or reject this design-only Run/Implementation Manifest contract.

No implementation, fixture preparation, experiment, IS mutation, or SimiGo code
change is authorized by this document.
