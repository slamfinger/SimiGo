# SRS-VAL-01 Run/Implementation Manifest Contract v1.0

> **Status:** MANIFEST CONTRACT V1.0 DELIVERED FOR HUMAN REVIEW — DESIGN ONLY / NO STAGE AUTHORIZED
> **Date:** 2026-10-07
> **Frozen predicate basis:** SRS-VAL-01 Design v0.8 at `1170208`
> **Frozen governance basis:** Authorization Package v0.6 at `047b221`, accepted at `6089f0b`
> **Frozen implementation boundary:** Implementation Boundary Audit v0.1 at `cb95c09`
> **Review basis:** Human REVISE ruling on Manifest Contract v0.9 at `0a8a693`
> **Purpose:** separate observed read facts from independent semantic-role classification authority.

## 1. Scope and authority

This document is a design-only manifest contract. It is not a filled execution
manifest, authorization request, implementation, fixture, runner, observer, or
Information-Space mutation.

```text
SRS-VAL-01 Design v0.8              ACCEPT / FROZEN / IMMUTABLE BASIS
Authorization Package v0.6          ACCEPT / FROZEN / IMMUTABLE GOVERNANCE BASIS
Implementation Boundary Audit v0.1  ACCEPT / FROZEN / T-IMPL-01 MINIMUM TARGET
Run/Implementation Manifest v1.0    SUBMITTED FOR HUMAN REVIEW
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
  SRS_VAL_01_RUN_IMPLEMENTATION_MANIFEST_CONTRACT_V1.0;

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
  SRS_VAL_01_RUN_IMPLEMENTATION_MANIFEST_CONTRACT_V1.0;
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
semantic-to-expected mapping was frozen before subject start;
expected-to-observed mapping is observer-authoritative and frozen after execution;
observed disposition realization closure is PASS with no undeclared, missing, or
  invented semantic read;
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

### 7.7 M3/M6/M13–M18 — typed semantic-input algebra, disposition realization, phased read mappings, and complete read-instance binding

#### 7.7.1 M14 — classification scope

Classification is not applied to every manifest field. It applies only to an
input capable of affecting at least one of:

```text
predicate result;
authorization validity;
observation validity.
```

Required scope record:

```text
classification_scope_basis_identity;
classification_scope_basis_content_address;
classification_scope_rule =
  CLASSIFY_ONLY_DECISION_OR_EVIDENCE_AUTHORITY_RELEVANT_INPUTS;
classification_scope_verdict.
```

Examples that remain in scope when they can affect those results:

```text
SRS/source-relation value;
dependency/result/policy value;
I-14/I-15/I-16 predicate-bound value;
Predicate Rule semantic value;
representation/language/interpreter semantic value;
Runner Trust Anchor;
Authorization Authority Root;
Stage Authorization Record;
Observer Authorization Record;
Channel Universe/coverage contract;
fidelity verification authority.
```

Pure `NON_DECISION_METADATA` is outside the closure. Examples include:

```text
manifest_instance_identity as a label;
artifact filename or display path;
record creation timestamp used only for bookkeeping;
evidence storage locator where integrity/authority is bound elsewhere;
UI text;
local directory layout.
```

If such metadata can affect predicate result, authorization validity, or
observation validity, it is no longer bookkeeping and must be classified.

Every candidate is recorded as:

```text
candidate_input_identity;
classification_relevance ∈ {
  DECISION_OR_EVIDENCE_AUTHORITY_RELEVANT,
  NON_DECISION_METADATA
};
non_classification_justification, when excluded.
```

No relevant input may be excluded as bookkeeping.

#### 7.7.2 M15 — independent input-category verifier

For every in-scope candidate, category assignment requires external verification.

Required assignment record:

```text
input_category_assignment_record_identity;
input_category_assignment_record_content_address;
input_identity;
assigned_category ∈ {
  SEMANTIC_INPUT,
  GOVERNANCE_AUTHORITY_INPUT,
  OBSERVATION_CONTROL_INPUT
};
category_assignment_basis_content_address;
category_assignment_verifier_identity;
category_assignment_verifier_artifact_identity;
category_assignment_verifier_content_address;
category_assignment_verifier_authority_root;
category_assignment_verifier_authority_chain;
category_assignment_human_ruling_reference;
category_assignment_verification_record_identity;
category_assignment_verification_record_content_address;
category_assignment_source =
  PRE_AUTHORIZED_EXTERNAL_VERIFICATION;
category_assignment_frozen_before_semantic_closure = true;
category_assignment_record_integrity_binding.
```

Required separation:

```text
Category Verifier ≠ T-IMPL-01;
Category Verifier ≠ implementation subject;
Category Verifier ≠ manifest generator;
Category Verifier ≠ fixture builder;
Category Verifier ≠ M9/M10 closure subject;
Category Verifier ≠ expected-read generator;
Category Verifier ≠ Observer;
Category Verifier ≠ fidelity verifier unless independently proven.

The verifier must not share mutable state, writable configuration, writable code,
or writable evidence storage with any separated party.
The verifier authority chain must not depend on the implementation artifact,
semantic closure, expected read set, observed read set, or subject-produced PASS.
```

Failure:

```text
SEMANTIC_CATEGORY_SELF_CERTIFIED
INPUT_CATEGORY_CIRCULAR_AUTHORITY
INPUT_CATEGORY_ASSIGNMENT_DRIFT
INPUT_CATEGORY_VERIFIER_UNAUTHORIZED.
```

#### 7.7.3 M13 — typed semantic-input algebra

Only `SEMANTIC_INPUT` entries enter semantic closure. Governance and observation
inputs have separate control gates.

First build the Semantic Input Universe:

```text
semantic_input_universe_identity;
semantic_input_universe_content_address;
semantic_input_set;
input_disposition ∈ {
  INVOCATION_MATERIALIZED_VALUE,
  EXTERNAL_SEMANTIC_READ,
  NOT_USED_FOR_THIS_INVOCATION
};
partition_disjoint = true;
unpartitioned_semantic_input_count = 0.
```

Then form:

```text
required_materialized_value_set;
required_external_read_set;
required_not_used_set.
```

Hard rule:

```text
SEMANTIC_INPUT_SET
  =
REQUIRED_MATERIALIZED_VALUE_SET
  ∪ REQUIRED_EXTERNAL_READ_SET
  ∪ REQUIRED_NOT_USED_SET;

the three partitions are disjoint;

SEMANTIC_INPUT_SET
  ≠ REQUIRED_EXTERNAL_READ_SET.
```

### 7.7.4 M16 — path-sensitive disposition closure

The implementation closure is not a raw identity-set equality. For every semantic
input in the required universe, compare its required disposition with its actual
invocation disposition.

Required required-disposition record:

```text
required_disposition_mapping_identity;
required_disposition_mapping_content_address;
semantic_input_identity;
required_disposition ∈ {
  INVOCATION_MATERIALIZED_VALUE,
  EXTERNAL_SEMANTIC_READ,
  NOT_USED_FOR_THIS_INVOCATION
};
conditional_not_used_justification, when NOT_USED;
materialized_value_identity, when MATERIALIZED;
materialized_value_digest, when MATERIALIZED;
expected_read_instance_binding_placeholder, when EXTERNAL_READ;
disposition_record_integrity_binding.
```

Required actual-disposition record:

```text
actual_disposition_mapping_identity;
actual_disposition_mapping_content_address;
semantic_input_identity;
actual_disposition ∈ {
  INVOCATION_MATERIALIZED_VALUE,
  EXTERNAL_SEMANTIC_READ,
  NOT_USED_FOR_THIS_INVOCATION
};
actual_materialized_value_identity, when MATERIALIZED;
actual_materialized_value_digest, when MATERIALIZED;
actual_expected_read_instance_identity, when EXTERNAL_READ;
actual_not_used_justification, when NOT_USED;
disposition_record_integrity_binding.
```

Required domain equality:

```text
required_disposition_domain == actual_disposition_domain;
no required semantic input is missing from the actual mapping;
no invented actual semantic input exists;
every semantic input has exactly one required disposition;
every semantic input has exactly one actual disposition.
```

Required path-sensitive equality:

```text
for every semantic input I:
  required_disposition[I] == actual_disposition[I].
```

Disposition-specific rules:

```text
NOT_USED_FOR_THIS_INVOCATION:
  no materialized value is required for this invocation;
  no semantic read instance is required;
  the exact frozen conditional justification must match;
  for inactive I-14, the marker must equal
  I14_NOT_USED_NO_RECOMPUTE_PATH and satisfy its frozen three-state rule.

INVOCATION_MATERIALIZED_VALUE:
  the exact materialized value identity/digest must be present in the closed
  Invocation Record;
  no external semantic read is required solely to obtain this value.

EXTERNAL_SEMANTIC_READ:
  exactly one expected read-instance binding must exist;
  no materialized value may silently replace the required external read.
```

Final disposition verdict:

```text
disposition_domain_verdict = PASS;
path_sensitive_disposition_verdict = PASS;
not_used_disposition_verdict = PASS;
materialized_disposition_verdict = PASS;
external_read_disposition_verdict = PASS;
no_disposition_to_read_set_conflation = true.
```

Failure:

```text
SEMANTIC_DISPOSITION_MISMATCH
NOT_USED_DISPOSITION_INVALID
MATERIALIZED_DISPOSITION_MISSING
EXTERNAL_READ_DISPOSITION_MISSING
DISPOSITION_DOMAIN_MISMATCH.
```

#### 7.7.5 M17 — phased semantic-input to read-instance mapping

Only semantic inputs with disposition `EXTERNAL_SEMANTIC_READ` enter this mapping.
The identity types remain distinct:

```text
semantic_input_identity
  identifies the semantic object;

expected_read_instance_identity
  identifies the pre-authorized read event/binding;

observed_read_instance_identity
  identifies the observer-authoritative executed read event.
```

##### 7.7.5.1 PRE-RUN semantic → expected mapping

Created and frozen before subject start.

```text
pre_run_semantic_to_expected_mapping_identity;
pre_run_semantic_to_expected_mapping_content_address;
semantic_input_identity;
expected_read_instance_identity;
declared_binding_kind ∈ {
  CONTENT_ADDRESS,
  IMMUTABLE_REVISION
};
declared_content_digest_or_resolved_revision_digest;
expected_channel_identity;
expected_access_mode;
expected_read_boundary_contract;
mapping_freeze_boundary;
mapping_freeze_precedes_subject_start = true;
mapping_record_integrity_binding.
```

Hard rules:

```text
The mapping is total over every EXTERNAL_SEMANTIC_READ disposition.
The mapping is one-to-one and non-inventive.
No observed_read_instance_identity may appear in this pre-run record.
No post-run rewrite of semantic→expected identity/content is allowed.
```

##### 7.7.5.2 POST-RUN expected → observed mapping

Produced only by the authorized Observer after execution, inside Observation
Integrity Boundary closure.

```text
post_run_expected_to_observed_mapping_identity;
post_run_expected_to_observed_mapping_content_address;
expected_read_instance_identity;
observed_read_instance_identity;
observed_binding_kind;
read_time_content_digest;
consumed_content_digest;
channel_identity;
access_mode;
read_begin_boundary;
read_end_boundary;
snapshot_or_atomicity_proof;
observer_authorization_identity;
channel_universe_identity;
observer_evidence_class =
  OBSERVER_AUTHORITATIVE_EXECUTION_EVIDENCE;
mapping_freeze_boundary =
  OBSERVATION_INTEGRITY_CLOSURE;
mapping_record_integrity_binding.
```

Hard rules:

```text
The mapping is total over every expected read instance.
The mapping is one-to-one and non-inventive.
No expected_read_instance_identity may be omitted or replaced.
The observer, not the subject or Decision Core, creates this mapping.
The record is immutable after Observation Integrity Boundary closure.
```

##### 7.7.5.3 FINAL composed semantic → expected → observed closure

Created only after both records freeze.

```text
final_semantic_to_observed_read_composition_identity;
final_semantic_to_observed_read_composition_content_address;
semantic_input_identity;
expected_read_instance_identity;
observed_read_instance_identity;
pre_run_mapping_reference;
post_run_mapping_reference;
composition_status =
  IMMUTABLE_AFTER_OBSERVATION_CLOSURE;
composition_integrity_binding.
```

Final mapping rules:

```text
every EXTERNAL_SEMANTIC_READ maps to exactly one expected instance;
every expected instance maps to exactly one observed instance;
every observed instance maps to exactly one expected instance and semantic input;
no missing, invented, duplicate, or drifted mapping exists.
```

Final mapping verdict:

```text
semantic_to_expected_mapping_verdict = PASS;
expected_to_observed_mapping_verdict = PASS;
final_composition_verdict = PASS;
mapping_totality_verdict = PASS;
mapping_one_to_one_verdict = PASS;
mapping_non_inventive_verdict = PASS;
pre_run_mapping_frozen_verdict = PASS;
post_run_observer_authority_verdict = PASS;
post_closure_immutability_verdict = PASS.
```

Failure:

```text
SEMANTIC_TO_EXPECTED_MAPPING_NOT_FROZEN_BEFORE_SUBJECT_START
EXPECTED_TO_OBSERVED_MAPPING_NOT_OBSERVER_AUTHORIZED
FINAL_COMPOSITION_CREATED_BEFORE_OBSERVATION_CLOSURE
SEMANTIC_INPUT_TO_READ_INSTANCE_MAPPING_MISSING
SEMANTIC_INPUT_TO_READ_INSTANCE_MAPPING_NOT_ONE_TO_ONE
EXPECTED_TO_OBSERVED_READ_MAPPING_MISSING
EXPECTED_TO_OBSERVED_READ_MAPPING_NOT_ONE_TO_ONE
READ_INSTANCE_MAPPING_INVENTED
READ_INSTANCE_MAPPING_DRIFTED.
```

#### 7.7.6 M18 — typed disposition realization closure

M16 compares required and declared dispositions. M18 proves actual realization
without conflating identity types or evidence authorities.

##### 7.7.6.1 Typed sets and relations

The three relevant sets have different identity types:

```text
RequiredExternalSemanticInputSet :
  Set<semantic_input_identity>;

ExpectedReadInstanceSet :
  Set<expected_read_instance_identity>;

ObservedReadInstanceSet :
  Set<observed_read_instance_identity>.
```

The two phased mappings are typed relations/functions:

```text
semantic_to_expected :
  semantic_input_identity
    → expected_read_instance_identity;

expected_to_observed :
  expected_read_instance_identity
    → observed_read_instance_identity.
```

They derive from the frozen PRE-RUN and observer-authored POST-RUN records. No
direct set equality is allowed between the three sets.

Required domain/codomain closure:

```text
dom(semantic_to_expected) =
  RequiredExternalSemanticInputSet;

codomain(semantic_to_expected) =
  ExpectedReadInstanceSet;

dom(expected_to_observed) =
  ExpectedReadInstanceSet;

codomain(expected_to_observed) =
  ObservedReadInstanceSet.
```

Required mapping shape:

```text
semantic_to_expected is total;
semantic_to_expected is one-to-one;
semantic_to_expected is non-inventive;

expected_to_observed is total;
expected_to_observed is one-to-one;
expected_to_observed is non-inventive.
```

Required composed relation:

```text
observed_realization :
  semantic_input_identity
    → expected_read_instance_identity
    → observed_read_instance_identity.
```

For every `I ∈ RequiredExternalSemanticInputSet`, exactly one pair:

```text
(semantic_to_expected[I], expected_to_observed[semantic_to_expected[I]])
```

must exist and both identities must resolve to complete read-instance records.

##### 7.7.6.2 Observed-read semantic-role classification

Observer-authoritative read records contain facts about executed reads. They do
not by themselves determine semantic role. Every observer-authoritative read in
the subject's consumable read universe must receive an independent semantic-role
classification.

###### 7.7.6.2.1 Observer fact record

Observer provides only:

```text
observed_read_instance_identity;
read_occurred = true;
raw_channel_identity;
raw_access_mode;
raw_payload_or_content_digest;
read_begin_boundary;
read_end_boundary;
observer_authorization_identity;
observer_evidence_class =
  OBSERVER_AUTHORITATIVE_EXECUTION_EVIDENCE.
```

Observer may not assign any final semantic-role class.

###### 7.7.6.2.2 Independent Classification Verifier

A root-backed, pre-authorized external verifier assigns the semantic role.

Required classification authority record:

```text
observed_read_classification_verifier_identity;
observed_read_classification_verifier_artifact_identity;
observed_read_classification_verifier_content_address;
observed_read_classification_basis_identity;
observed_read_classification_basis_content_address;
observed_read_classification_basis_commit = 1170208;
observed_read_classification_record_identity;
observed_read_classification_record_content_address;
observed_read_classification_authority_chain;
observed_read_classification_human_ruling_reference;
observed_read_classification_source =
  PRE_AUTHORIZED_EXTERNAL_VERIFICATION;
classification_record_frozen_before_realization_closure = true;
classification_record_integrity_binding.
```

The classification verifier must be separate from:

```text
T-IMPL-01;
implementation subject;
manifest generator;
fixture builder;
expected-read generator;
Observer;
M9/M10 closure verifier, unless independently proven;
fidelity verifier, unless independently proven.
```

It must not share mutable state, writable configuration, writable code, or
writable evidence storage with the subject, Observer, or any separated party.

###### 7.7.6.2.3 Classification inputs

The verifier must classify each observed read against all frozen inputs:

```text
semantic_input_universe;
semantic category assignments;
predicate semantic basis;
expected semantic read closure;
rule representation/language/grammar/interpreter semantics;
authorization boundary;
observation boundary/channel universe.
```

###### 7.7.6.2.4 Final semantic-role classes

The Classification Verifier assigns exactly one:

```text
SEMANTIC_REALIZATION_OF_REQUIRED_EXTERNAL_INPUT;
NON_SEMANTIC_MECHANICAL_READ;
FORBIDDEN_UNDECLARED_SEMANTIC_READ.
```

Hard rules:

```text
Observer cannot alone classify a read as NON_SEMANTIC_MECHANICAL_READ.

Observer cannot downgrade a decision-relevant semantic read to mechanical.

NON_SEMANTIC_MECHANICAL_READ is valid only when the independent verifier proves,
from frozen semantic inputs and boundaries, that the read cannot affect predicate
result, authorization validity, or observation validity.

Governance/observation control inputs are not implicitly mechanical merely
because they are not predicate inputs.
```

Failure:

```text
OBSERVED_READ_ROLE_SELF_CERTIFIED
OBSERVED_READ_CLASSIFICATION_VERIFIER_UNAUTHORIZED
OBSERVED_READ_CLASSIFICATION_BASIS_MISSING_OR_DRIFTED
NON_SEMANTIC_CLASSIFICATION_UNVERIFIED
OBSERVED_READ_CLASSIFICATION_RECORD_DRIFTED.
```

##### 7.7.6.3 Disposition-specific realization evidence

For every semantic input `I`, compare:

```text
required_disposition[I];
realized_disposition[I];
realization_evidence_source[I];
realization_evidence_authority_valid_for_disposition[I].
```

Evidence source is disposition-specific:

```text
INVOCATION_MATERIALIZED_VALUE:
  realization_evidence_source[I] =
    CLOSED_INVOCATION_RECORD_REALIZATION_EVIDENCE;

EXTERNAL_SEMANTIC_READ:
  realization_evidence_source[I] =
    OBSERVER_AUTHORITATIVE_READ_EVIDENCE;

NOT_USED_FOR_THIS_INVOCATION:
  realization_evidence_source[I] =
    CLOSED_INVOCATION_RECORD_NEGATIVE_REALIZATION_EVIDENCE
    + OBSERVER_NEGATIVE_READ_CLOSURE_EVIDENCE.
```

Required MATERIALIZED evidence:

```text
exact materialized_value_identity exists in the Invocation Record;
exact materialized_value_digest matches the required value;
the value is materialized inside the closed Invocation Record;
observer-authoritative read evidence is not required solely because the
  disposition is MATERIALIZED;
observer negative read closure confirms no undeclared external semantic read
  realizes I.
```

Required EXTERNAL_READ evidence:

```text
exactly one observed read instance exists for I;
the observed identity is codomain(expected_to_observed);
the observed record is complete and immutable;
read_time_content_digest ==
  consumed_content_digest ==
  declared/resolved content digest;
channel and access mode match the PRE-RUN expectation;
snapshot_or_atomicity_proof verifies;
observer authorization verifies;
channel-universe membership verifies.
```

Required NOT_USED evidence:

```text
no materialized realization exists;
no observer-authoritative semantic read realizing I exists;
closed Invocation Record negative-realization evidence is present;
observer negative read closure is present;
frozen NOT_USED justification is valid;
no undeclared semantic read is reinterpreted as NOT_USED.
```

Required per-input authority verdict:

```text
realized_disposition[I] == required_disposition[I];
realization_evidence_complete[I] = true;
realization_evidence_source_matches_disposition[I] = true;
realization_evidence_authority_valid_for_disposition[I] = true.
```

Do not write or require:

```text
realization_evidence_observer_authoritative[I] = true
```

for MATERIALIZED or NOT_USED as a blanket rule.

##### 7.7.6.4 Final typed realization verdict

Required global verdict:

```text
typed_realization_relation_verdict = PASS;
observed_read_classification_verdict = PASS;
observed_read_semantic_role_authority_verdict = PASS;
materialized_realization_verdict = PASS;
external_read_realization_verdict = PASS;
not_used_realization_verdict = PASS;
negative_read_closure_verdict = PASS;
realization_evidence_authority_verdict = PASS;
no_disposition_to_read_set_conflation = true.
```

Failure:

```text
REQUIRED_EXTERNAL_SEMANTIC_INPUT_NOT_REALIZED
EXPECTED_READ_INSTANCE_MISSING
OBSERVED_READ_INSTANCE_MISSING
SEMANTIC_TO_EXPECTED_DOMAIN_OR_CODOMAIN_MISMATCH
EXPECTED_TO_OBSERVED_DOMAIN_OR_CODOMAIN_MISMATCH
MATERIALIZED_INPUT_SECRETLY_READ
UNDECLARED_SEMANTIC_READ
INVENTED_OR_UNMAPPED_SEMANTIC_READ
NOT_USED_INPUT_WAS_REALIZED
REALIZATION_EVIDENCE_SOURCE_MISMATCH
READ_INSTANCE_EVIDENCE_INCOMPLETE
OBSERVED_READ_SEMANTIC_ROLE_SELF_CERTIFIED.
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
A24 implementation adds a semantic input absent from the required typed closure.
A25 governance/observation authority is read as predicate semantic evidence.
A26 M9/M10 closure verifier is controlled by implementation, expected-read
    generator, observer, or a circular authority chain.
A27 materialized semantic inputs are wrongly counted as external reads.
A28 out-of-scope bookkeeping is promoted to governance or observation input.
A29 category assignment is self-certified by implementation, closure generator, or
    a circular authority chain.
A30 NOT_USED semantic input is treated as a required used input.
A31 raw semantic-input identity set is compared with a read-instance identity set.
A32 expected/observed read mapping is partial, many-to-one, or invented.
A33 pre-run mapping already contains an observed read identity.
A34 undeclared semantic read is hidden by matching declared dispositions only.
A35 mapped read identity does not resolve to a complete observer-authoritative
    read-instance record.
A36 semantic-input, expected-read, and observed-read sets are declared equal
    despite having different identity types.
A37 observer authority is demanded for a MATERIALIZED value while its real
    evidence source is the closed Invocation Record.
A38 Observer falsely classifies a semantically decision-relevant read as
    NON_SEMANTIC_MECHANICAL_READ.
```

Each attack must map to a manifest field, expected stop/pass outcome, observer
source, and evidence artifact.

## 10. Acceptance criteria for this contract

```text
ACCEPT MANIFEST V1.0   freeze the schema and hard constraints; authorize only
                       preparation of a future Human Authorization Request; no
                       code, fixture, run, or mutation.

REVISE MANIFEST V1.0   return with registered defects.

REJECT MANIFEST V1.0   do not proceed.
```

## 11. Decision requested

Accept, revise, or reject this design-only Run/Implementation Manifest contract.

No implementation, fixture preparation, experiment, IS mutation, or SimiGo code
change is authorized by this document.
