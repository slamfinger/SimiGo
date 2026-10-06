# SRS-VAL-01 Run/Implementation Manifest Contract v0.4

> **Status:** MANIFEST CONTRACT V0.4 DELIVERED FOR HUMAN REVIEW — DESIGN ONLY / NO STAGE AUTHORIZED
> **Date:** 2026-10-07
> **Frozen predicate basis:** SRS-VAL-01 Design v0.8 at `1170208`
> **Frozen governance basis:** Authorization Package v0.6 at `047b221`, accepted at `6089f0b`
> **Frozen implementation boundary:** Implementation Boundary Audit v0.1 at `cb95c09`
> **Review basis:** Human REVISE ruling on Manifest Contract v0.3 at `cfe1004`
> **Purpose:** close fidelity-verdict authority, executed interpreter identity, and semantic-input completeness before any authorization request.

## 1. Scope and authority

This document is a design-only manifest contract. It is not a filled execution
manifest, authorization request, implementation, fixture, runner, observer, or
Information-Space mutation.

```text
SRS-VAL-01 Design v0.8              ACCEPT / FROZEN / IMMUTABLE BASIS
Authorization Package v0.6          ACCEPT / FROZEN / IMMUTABLE GOVERNANCE BASIS
Implementation Boundary Audit v0.1  ACCEPT / FROZEN / T-IMPL-01 MINIMUM TARGET
Run/Implementation Manifest v0.4    SUBMITTED FOR HUMAN REVIEW
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
  SRS_VAL_01_RUN_IMPLEMENTATION_MANIFEST_CONTRACT_V0.4;

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
  SRS_VAL_01_RUN_IMPLEMENTATION_MANIFEST_CONTRACT_V0.4;
manifest_contract_integrity_binding;
manifest_contract_status =
  ACCEPTED_FROZEN_AT_INSTANCE_CREATION;
authorization_request_reference;
human_ruling_reference;
requested_stage_set;
artifact identities for every requested stage;
environment identity;
observer and channel-universe identities;
evidence locations and integrity bindings;
validity and use budgets.
```

### 3.3 M4 — manifest contract self-version consistency

Hard rule:

```text
future_manifest.contract_identity
  == exact accepted/frozen manifest contract identity;

future_manifest.contract_integrity_binding
  == exact accepted/frozen contract integrity binding.
```

A reference to v0.1, v0.2, latest, current, or any superseded/unaccepted contract
produces:

```text
runner stop;
MANIFEST_CONTRACT_VERSION_MISMATCH.
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
predicate_rule_representation_format_identity;
predicate_rule_representation_format_version;
predicate_rule_representation_format_content_address;
predicate_rule_language_spec_identity;
predicate_rule_language_spec_version;
predicate_rule_language_spec_content_address;
predicate_rule_grammar_binding_identity;
predicate_rule_grammar_binding_content_address;
predicate_rule_interpreter_semantics_identity;
predicate_rule_interpreter_semantics_version;
predicate_rule_interpreter_semantics_content_address;
predicate_rule_interpreter_artifact_identity;
predicate_rule_interpreter_location =
  WITHIN_T_IMPL_01_BOUNDARY;
predicate_rule_semantic_basis_identity;
predicate_rule_semantic_basis_content_address;
predicate_rule_semantic_basis_commit = 1170208;
predicate_rule_normative_binding_identity;
predicate_rule_normative_binding_content_address;
predicate_rule_normative_section_set;
rule_semantics_fidelity_verdict;
semantic_drift_detected = false;
rule_fidelity_verifier_identity;
rule_fidelity_verifier_artifact_identity;
rule_fidelity_verifier_content_address;
rule_fidelity_verifier_semantic_basis_identity;
rule_fidelity_verifier_semantic_basis_content_address;
rule_fidelity_verification_record_identity;
rule_fidelity_verification_record_content_address;
rule_fidelity_verification_authority_chain;
rule_fidelity_verification_human_ruling_reference;
rule_fidelity_verdict_source =
  PRE_AUTHORIZED_EXTERNAL_VERIFICATION;
rule_fidelity_verdict_frozen_before_t_impl_01 = true;
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
bound_predicate_rule_representation_format_identity;
bound_predicate_rule_representation_format_content_address;
bound_predicate_rule_language_spec_identity;
bound_predicate_rule_language_spec_content_address;
bound_predicate_rule_interpreter_semantics_identity;
bound_predicate_rule_interpreter_semantics_content_address;
bound_predicate_rule_interpreter_artifact_identity;
bound_predicate_rule_interpreter_location =
  WITHIN_T_IMPL_01_BOUNDARY;
bound_predicate_rule_semantic_basis_identity;
bound_predicate_rule_semantic_basis_content_address;
bound_predicate_rule_normative_binding_content_address;
rule_semantics_fidelity_verdict;
semantic_drift_detected = false;
authorized_rule_fidelity_verifier_identity;
authorized_rule_fidelity_verifier_artifact_identity;
authorized_rule_fidelity_verifier_content_address;
rule_fidelity_verification_record_identity;
rule_fidelity_verification_record_content_address;
rule_fidelity_verification_record_digest;
rule_fidelity_verdict_source =
  PRE_AUTHORIZED_EXTERNAL_VERIFICATION;
rule_fidelity_verdict_materialized_in_invocation = true;
rule_fidelity_verdict_frozen_before_t_impl_01 = true;
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
PREDICATE_RULE_SEMANTIC_BASIS_MISMATCH.
```

### 4.4 M1 — exact semantic basis gate

The approved rule must bind its classification semantics to the frozen predicate
basis, not merely to an authority decision or natural-language description.

Required semantic-basis identity:

```text
predicate_rule_semantic_basis_identity =
  SRS_VAL_01_DESIGN_V0_8_NORMATIVE_CLASSIFICATION_BASIS;
predicate_rule_semantic_basis_commit =
  1170208;
predicate_rule_semantic_basis_content_address =
  immutable content address of the frozen v0.8 semantic basis extraction;
predicate_rule_normative_binding_content_address =
  immutable content address of the reviewed canonical normative extraction;
predicate_rule_normative_section_set =
  exact enumeration of the v0.8 classification, G-CLASS, DP-precedence,
  non-retroactivity, I-14 conditional, and decision-path sections used by the
  rule.
```

Required fidelity verdict:

```text
rule_content_matches_normative_binding = true;
rule_has_no_extra_classification_semantics = true;
rule_omits_no_required_classification_semantics = true;
semantic_drift_detected = false;
rule_semantics_fidelity_verdict = PASS.
```

The same fidelity closure must include representation, language, and interpreter:

```text
representation_parses_under_bound_grammar = true;
language_spec_content_matches_frozen_v0_8_semantics = true;
interpreter_semantics_matches_language_spec = true;
interpreter_semantics_matches_frozen_v0_8_semantics = true;
interpreter_is_within_t_impl_01_boundary = true;
interpreter_has_no_unauthorized_external_semantics = true;
representation_spec_interpreter_fidelity_verdict = PASS.
```

A Human approval authorizes the rule artifact, but it cannot replace this
content-bound fidelity verdict. Nor may T-IMPL-01, the subject, runner, fixture
builder, or manifest generator issue the verdict.

### 4.5 M7 — fidelity-verdict authority

Every fidelity `PASS` must have an immutable external authority record.

Required verification record:

```text
rule_fidelity_verifier_identity;
rule_fidelity_verifier_artifact_identity;
rule_fidelity_verifier_content_address;
rule_fidelity_verifier_semantic_basis_identity =
  SRS_VAL_01_DESIGN_V0_8_NORMATIVE_CLASSIFICATION_BASIS;
rule_fidelity_verifier_semantic_basis_content_address;
rule_fidelity_verification_record_identity;
rule_fidelity_verification_record_content_address;
rule_fidelity_verification_record_digest;
verified_object_set =
  PREDICATE_RULE + REPRESENTATION + LANGUAGE_SPEC + GRAMMAR +
  INTERPRETER_SEMANTICS;
fidelity_verification_authority_chain;
fidelity_verification_human_ruling_reference;
fidelity_verdict_source =
  PRE_AUTHORIZED_EXTERNAL_VERIFICATION;
verification_record_frozen_before_t_impl_01 = true.
```

Separation rules:

```text
T-IMPL-01 ≠ Predicate Rule Fidelity Verifier.
Predicate Rule Artifact ≠ Fidelity Verifier.
Subject/runner/fixture-builder/manifest-generator ≠ Fidelity Verifier.

The verifier must be root-backed and outside the subject trust boundary.
The verifier must not share mutable state, writable configuration, or evidence
storage with the object it verifies.
The verification record must be immutable and revalidated before Invocation
Record closure.
```

The materialized fidelity verification record is a frozen input to T-IMPL-01.
T-IMPL-01 may consume it, but must not generate, mutate, rederive its authority,
or substitute a runtime self-check.

Failure:

```text
FIDELITY_VERDICT_SELF_CERTIFIED
FIDELITY_VERIFIER_UNAUTHORIZED
FIDELITY_VERIFICATION_RECORD_MISSING_OR_DRIFTED.
```

### 4.6 M2 — materialize the resolved rule value in the Invocation Record

The approved and fidelity-verified rule content must be resolved before closure
and materialized as an immutable value inside the Invocation Record. A pointer,
digest, URI, registry handle, or promise to fetch the rule later is not closure.

Required resolved-rule node:

```text
resolved_predicate_rule_value_identity;
resolved_predicate_rule_value_digest;
resolved_predicate_rule_canonicalization_method_identity;
resolved_predicate_rule_canonicalization_method_content_address;
resolved_predicate_rule_artifact_content_address;
resolved_predicate_rule_content_match = true;
resolved_predicate_rule_semantic_basis_content_address;
resolved_predicate_rule_semantic_basis_match = true;
resolved_predicate_rule_representation_format_match = true;
resolved_predicate_rule_language_spec_match = true;
resolved_predicate_rule_interpreter_semantics_match = true;
resolved_predicate_rule_interpreter_location =
  WITHIN_T_IMPL_01_BOUNDARY;
resolved_predicate_rule_representation_parses_under_bound_grammar = true;
resolved_predicate_rule_language_spec_matches_frozen_v0_8 = true;
resolved_predicate_rule_interpreter_matches_language_spec = true;
rule_is_materialized_in_invocation_value_graph = true;
rule_resolution_occurs_before_invocation_closure = true.
```

Required graph shape:

```text
closed invocation graph
├── SRS semantic values;
├── I-15 values;
├── I-16 closure values;
├── dependency values;
├── active I-14 values or exact not-used marker;
└── resolved Predicate Rule semantic value.
```

Forbidden:

```text
closed graph + rule pointer only;
closed graph + digest resolved by runtime lookup;
closed graph + lazy rule loader;
closed graph + post-closure rule fetch;
canonicalization method selected after resolution.
```

Failure:

```text
PREDICATE_RULE_VALUE_NOT_MATERIALIZED
PREDICATE_RULE_RESOLUTION_AFTER_CLOSURE
PREDICATE_RULE_CANONICALIZATION_UNBOUND.
```

### 4.7 M5 — representation, language-spec, and interpreter closure

The materialized rule has meaning only through a bound representation chain:

```text
Frozen SRS-VAL v0.8 semantics
  → exact language/representation specification
  → exact rule representation/artifact
  → exact Decision Core interpreter semantics
  → classified failure
```

Every arrow must have an immutable identity/content binding.

Required properties:

```text
predicate_rule_representation_format_identity;
predicate_rule_representation_format_version;
predicate_rule_representation_format_content_address;
predicate_rule_language_spec_identity;
predicate_rule_language_spec_version;
predicate_rule_language_spec_content_address;
predicate_rule_grammar_binding_identity;
predicate_rule_grammar_binding_content_address;
predicate_rule_interpreter_semantics_identity;
predicate_rule_interpreter_semantics_version;
predicate_rule_interpreter_semantics_content_address;
predicate_rule_interpreter_artifact_identity;
interpreter_location =
  WITHIN_T_IMPL_01_BOUNDARY.
```

Hard rules:

```text
The representation format cannot be inferred at runtime.
The language specification cannot be selected by the subject, runner, or observer.
The interpreter cannot be a plugin, model, external service, mutable callback,
or undeclared runtime dependency.
Interpreter semantics is part of T-IMPL-01 implementation fidelity.
The interpreter artifact/component is separately content-bound.
If the interpreter is external to the single Decision Core artifact, it must also
appear in expected_semantic_runtime_dependency_set and exact implementation scope.

Forbidden:
interpreter chosen after rule resolution;
two interpreters accepting the same rule content;
representation accepted without bound grammar/spec;
interpreter semantics justified only by tests or Human prose;
semantic dependency reclassified as mechanical to hide the interpreter.
```

Failure:

```text
PREDICATE_RULE_REPRESENTATION_UNBOUND
PREDICATE_RULE_LANGUAGE_SPEC_UNBOUND
PREDICATE_RULE_INTERPRETER_SEMANTICS_UNBOUND
PREDICATE_RULE_INTERPRETER_OUTSIDE_T_IMPL_01
PREDICATE_RULE_INTERPRETER_SEMANTICS_MISMATCH.
```

### 4.8 M8 — executed interpreter component binding

Authorization of an interpreter artifact is insufficient. The exact component
inside the executed Decision Core must be observed and bound.

Required component binding:

```text
decision_core_to_interpreter_component_binding_identity;
authorized_decision_core_artifact_identity;
authorized_interpreter_artifact_identity;
authorized_interpreter_component_path_or_structure_identity;
interpreter_component_role =
  PREDICATE_RULE_INTERPRETER;
interpreter_component_integrity_binding;
authorized_interpreter_semantics_identity;
authorized_language_spec_identity;
authorized_grammar_binding_identity;
bound_predicate_rule_artifact_identity.
```

Required observed/executed binding:

```text
executed_decision_core_artifact_identity;
executed_decision_core_content_address;
executed_interpreter_identity;
executed_interpreter_content_address;
executed_interpreter_component_path_or_structure_identity;
executed_interpreter_component_integrity_binding;
executed_interpreter_semantics_identity;
executed_interpreter_matches_authorized_component = true;
component_binding_observer_identity;
observer_evidence_class =
  OBSERVER_AUTHORITATIVE_EXECUTION_EVIDENCE.
```

Required observed chain:

```text
observed executable
  → exact Decision Core artifact
  → exact interpreter component
  → exact interpreter semantics artifact
  → exact language specification / grammar
  → exact Predicate Rule artifact
  → classified failure.
```

Hard rules:

```text
executed_interpreter_identity ==
  authorized_interpreter_artifact_identity;

executed_interpreter_content_address ==
  authorized interpreter content address;

executed interpreter integrity ==
  authorized component integrity;

the observer, not the subject or Decision Core, supplies the executed-component
identity and integrity evidence.
```

Failure:

```text
EXECUTED_INTERPRETER_COMPONENT_MISMATCH
EXECUTED_INTERPRETER_COMPONENT_UNOBSERVED
DECISION_CORE_TO_INTERPRETER_BINDING_DRIFT.
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

If classification is required, §4.5's resolved Predicate Rule semantic value must
already be present in this graph. The graph may contain its digest as an integrity
binding, but the digest must not be the only representation.

### 6.4 Closure validation

Before returning `closure_verdict = PASS`, validate:

```text
every node is immutable and fully materialized;
every revision binding resolves to its declared digest;
the Predicate Rule semantic value is materialized when classification applies;
resolved Predicate Rule content matches its approved artifact digest;
resolved Predicate Rule semantic basis matches frozen v0.8;
representation, language spec, grammar, and interpreter bindings match;
interpreter is within T-IMPL-01 and has no unauthorized external semantics;
external fidelity verifier, artifact, authority chain, and immutable PASS record
  match;
semantic-input completeness closure is PASS and frozen before the expected read
  set;
canonicalization identity/content is prebound;
no post-closure mutation or re-resolution occurs.
```

### 6.5 Closure failure

Any forbidden node, unresolved reference, mutable node, or post-closure change
produces:

```text
INVOCATION_RECORD_NOT_CLOSED
INVOCATION_RECORD_MUTATED_AFTER_CLOSURE
PREDICATE_RULE_VALUE_NOT_MATERIALIZED.
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

### 7.7 M3/M6/M9 — input, semantic completeness, and pre-registered expected-read closure

Before M6 freezes an expected read set, M9 must prove that the set is complete.

#### 7.7.1 M9 — semantic input completeness closure

The completeness object is produced before the expected read set and independently
of observation.

Required closure record:

```text
semantic_input_closure_record_identity;
semantic_input_closure_record_content_address;
semantic_input_closure_completeness_basis_identity =
  SRS_VAL_01_DESIGN_V0_8_NORMATIVE_CLASSIFICATION_BASIS;
semantic_input_closure_completeness_basis_content_address;
semantic_input_closure_basis_commit = 1170208;
semantic_dependency_to_read_mapping;
semantic_input_closure_verifier_identity;
semantic_input_closure_verifier_artifact_identity;
semantic_input_closure_verifier_content_address;
semantic_input_closure_authority_chain;
semantic_input_closure_human_ruling_reference;
semantic_input_closure_source =
  PRE_AUTHORIZED_INDEPENDENT_CLOSURE_AUDIT;
semantic_input_closure_derived_from_observed_reads = false;
semantic_input_closure_frozen_before_expected_read_set = true.
```

Every semantic binding must be accounted as one of:

```text
INVOCATION_MATERIALIZED_VALUE:
  already materialized inside the closed Invocation Record;

EXTERNAL_SEMANTIC_READ:
  must appear in the expected semantic read set with an exact read-instance
  binding;

NOT_USED_FOR_THIS_INVOCATION:
  allowed only with an exact conditional-state justification, such as an I-14
  not-used marker or classification not invoked.
```

The mapping must account for at least:

```text
SRS/source-relation bindings;
dependency bindings;
result bindings;
resolution and policy bindings;
provenance/lifecycle/freshness bindings;
I-14 when active;
I-15;
I-16 closure evidence;
resolved Predicate Rule artifact/value;
rule representation format;
rule language specification;
rule grammar;
rule interpreter semantics;
canonicalization method;
authority/root evidence required by the invocation.
```

Required completeness verdict:

```text
declared_semantic_inputs ==
  all semantically necessary external inputs for this invocation;
all_semantic_bindings_accounted = true;
unaccounted_semantic_binding_count = 0;
semantic_input_derived_from_observed_reads = false;
semantic_input_closure_verdict = PASS.
```

Failure:

```text
SEMANTIC_INPUT_CLOSURE_INCOMPLETE
SEMANTIC_INPUT_CLOSURE_SELF_AUTHORIZED
SEMANTIC_INPUT_CLOSURE_DERIVED_FROM_OBSERVATION.
```

#### 7.7.2 M6 — pre-registered expected-read freeze

The expected semantic read set is a pre-execution authorization object, not an
output derived from observation. It must be generated only from the M9 closure,
frozen before subject start, and content-bound in the root-backed Human
authorization chain.

Required M6 fields:

```text
expected_read_set_authorization_identity;
expected_read_set_authority_root_chain;
expected_read_set_human_ruling_reference;
expected_read_set_content_address;
expected_read_set_integrity_binding;
expected_read_set_freeze_boundary;
expected_read_set_frozen_before_execution = true;
expected_read_set_generation_source =
  M9_SEMANTIC_INPUT_CLOSURE_RECORD;
semantic_dependency_to_read_mapping_identity;
semantic_input_closure_record_identity;
expected_read_set_derived_from_observed_read_set = false;
expected_read_set_mutation_forbidden_after_freeze = true;
expected_read_set_subject_or_runner_contributions = NONE.
```

If the frozen expected set changes after freeze:

```text
runner stop;
EXPECTED_READ_SET_FROZEN_INPUT_DRIFT.
```

If observed reads were used to create, expand, select, or justify the expected set:

```text
runner stop;
EXPECTED_READ_SET_SELF_AUTHORIZATION.
```

Then the M3 exact closure applies:

```text
invocation_value_graph_identity;
declared_input_binding_kind ∈ {
  CONTENT_ADDRESS,
  IMMUTABLE_REVISION
};
declared_content_digest or immutable revision plus exact
  revision_to_content_digest_binding;
semantic_expected_read_set;
semantic_observed_read_set;
expected_read_instance_binding;
observed_read_instance_binding;
expected_to_observed_read_mapping;
read_instance_binding_verdict;
semantic_read_closure_verdict;
observer_identity.
```

Each expected and observed read-instance binding must contain:

```text
read_instance_identity;
logical_input_identity;
input_role;
declared_binding_kind;
declared_content_digest or resolved revision digest;
read_time_content_digest;
consumed_content_digest;
channel_identity;
access_mode;
snapshot_or_atomicity_proof;
observer_identity;
observer_evidence_class =
  OBSERVER_AUTHORITATIVE_EXECUTION_EVIDENCE.
```

The mapping must be explicit, total, and non-inventive:

```text
every expected semantic read maps to exactly one observed semantic read;
every observed semantic read maps to exactly one expected semantic read;
no expected semantic read is missing;
no observed semantic read is undeclared;
unauthorized duplicates are not silently collapsed;
mapping equality includes logical identity, binding kind, content digest,
channel, access mode, and read-instance proof.
```

Required final verdict:

```text
semantic_expected_read_set
  == semantic_observed_read_set;

for every mapped pair:
  expected_content_digest
    == read_time_content_digest
    == consumed_content_digest;

revision_to_content_digest_binding verifies where applicable;
snapshot_or_atomicity_proof verifies;
read_instance_binding_verdict = PASS;
semantic_read_closure_verdict = PASS;
undeclared_or_missing_read_detected = false;
expected_read_set_freeze_boundary_precedes_subject_start = true;
expected_read_set_content_matches_authorized_freeze = true;
expected_read_set_matches_m9_semantic_input_closure = true;
all_semantic_bindings_accounted = true;
expected_and_observed_production_chains_are_independent = true.
```

Identity-set equality alone is insufficient. If identity sets match but content,
revision digest, instance binding, channel, access mode, or atomicity proof
differs, the gate fails:

```text
SEMANTIC_READ_INSTANCE_MISMATCH
SEMANTIC_READ_CONTENT_MISMATCH
SEMANTIC_READ_CLOSURE_INCOMPLETE.
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
A13 evidence self-certification;
A14 approved predicate rule with drifted semantic basis;
A15 rule represented only by pointer/digest in the Invocation Record;
A16 read identity sets match but consumed read instances/content differ.
A17 manifest instance cites a superseded manifest contract identity.
A18 rule content is valid but interpreted by an unauthorized language/interpreter.
A19 expected read set is derived from observed reads and then declared equal to them.
A20 frozen expected read set drifts after authorization but before subject start.
A21 implementer/manifest generator self-certifies rule/language/interpreter
    fidelity.
A22 approved interpreter differs from the interpreter component actually executed.
A23 expected read set omits a semantically necessary rule/interpreter input and
    then passes because observed reads match the incomplete expectation.
```

Each attack must map to a manifest field, expected stop/pass outcome, observer
source, and evidence artifact.

## 10. Acceptance criteria for this contract

```text
ACCEPT MANIFEST V0.4   freeze the schema and hard constraints; authorize only
                       preparation of a future Human Authorization Request; no
                       code, fixture, run, or mutation.

REVISE MANIFEST V0.4   return with registered defects.

REJECT MANIFEST V0.4   do not proceed.
```

## 11. Decision requested

Accept, revise, or reject this design-only Run/Implementation Manifest contract.

No implementation, fixture preparation, experiment, IS mutation, or SimiGo code
change is authorized by this document.
