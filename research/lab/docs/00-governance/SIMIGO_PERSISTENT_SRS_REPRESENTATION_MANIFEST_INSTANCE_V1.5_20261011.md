# Persistent SRS Representation Manifest Instance v1.5

> **Status:** REBOUND TO FROZEN CONTRACT / REVISION CANDIDATE /
> NOT EXECUTABLE / NO STAGE AUTHORIZED
> **Date:** 2026-10-11
> **Supersedes:** Manifest Instance v1.4 (`REVISE / SUPERSEDED / NOT EXECUTED`)
> **Canonical PALACE mutation:** FORBIDDEN
> **Canonical Information Space mutation:** FORBIDDEN
> **MLX execution:** FORBIDDEN
> **V6 rerun:** FORBIDDEN
> **Independent ES₂ consumption:** NOT AUTHORIZED
> **Non-recompute attribution:** NOT AUTHORIZED
> **Marker / evidence-root creation by this document:** FORBIDDEN

## 1. Manifest identity and frozen contract binding

```text
manifest_instance_identity =
  SIMIGO_PERSISTENT_SRS_REPRESENTATION_MANIFEST_INSTANCE_V1.5;

manifest_instance_status =
  REBOUND / DESIGN_FROZEN_CONTRACT_BOUND / REVISION_CANDIDATE /
  NOT_EXECUTABLE / HUMAN_STAGE_AUTHORIZATIONS_REQUIRED;

persistence_manifest_contract_identity =
  SIMIGO_PERSISTENT_SRS_REPRESENTATION_MANIFEST_CONTRACT_V1.8;

persistence_manifest_contract_status =
  ACCEPT / DESIGN FROZEN / NO STAGE AUTHORIZED;

persistence_manifest_contract_accepted_commit =
  6ac85f68003afc778aeec5b6fc070f7958be7499;

persistence_manifest_contract_git_blob_sha =
  63fc1f6deba0f9f5ca453b543411fb8e371d6613;

persistence_manifest_contract_sha256 =
  ba8d7fe609a26bdb88ee90e8af0bcd4778372c0ef552a838e158f7204aed47c0;

request_base_commit =
  e45ea8f46388adcae8fc3f04fab7a8d9024bafff;

integrity_binding =
  exact accepted source commit plus SHA256 above;

superseded_instance =
  SIMIGO_PERSISTENT_SRS_REPRESENTATION_MANIFEST_INSTANCE_V1.4;

superseded_instance_status =
  REVISE / SUPERSEDED BY V1.5 / NOT EXECUTED.
```

This instance is bound but not executable. Contract acceptance does not authorize
any stage.

## 2. Authorization provenance

```text
authorization_request =
  SIMIGO_PERSISTENT_SRS_REPRESENTATION_AUTHORIZATION_REQUEST_V0.1_20261011;

authorization_request_sha256 =
  4063787b0680da2ccd872ec949c4602295c8bd5d9d6620f7149ff6caa288c791;

contract_acceptance_ruling =
  ACCEPT_PERSISTENT_SRS_MANIFEST_CONTRACT_V1.8;

contract_acceptance_record =
  docs/00-governance/SIMIGO_PERSISTENT_SRS_REPRESENTATION_MANIFEST_CONTRACT_V1.8_ACCEPTANCE_20261011.md;

human_stage_ruling_references =
  REQUIRED_SEPARATELY_FOR_EACH_STAGE;
```

Acceptance of the contract authorized only this rebound and design baseline. It
did not authorize implementation, fixtures, execution, markers, evidence root, or
any later research stage.

## 3. SRS-VAL compatibility provenance

```text
srs_val_manifest_contract_identity =
  SRS_VAL_01_RUN_IMPLEMENTATION_MANIFEST_CONTRACT_V1.0;

srs_val_manifest_contract_status =
  ACCEPT / FROZEN / NOT VALID FOR PERSISTENCE_TARGET;

srs_val_manifest_contract_reviewed_basis_commit = f69a0e2;

srs_val_manifest_contract_content_sha256 =
  b9fbc290e096bd94b825bee0e4e8c3c3a4a7efea742cbf9bf755efd75d41055e;

compatibility_verdict =
  INCOMPATIBLE_FOR_PERSISTENCE_TARGET / RETAINED_AS_FROZEN_PROVENANCE.
```

No field here expands SRS-VAL T-IMPL-01.

## 4. Accepted Decision Core and design bindings

```text
accepted_decision_core_source_commit =
  1d47f3be56dfa8c6bf7619f4566b271ed74aad27;

accepted_decision_core_source_path =
  simigo2-experimental/Sources/SimiGo2Experimental/SRSVALDecisionCore.swift;

accepted_decision_core_source_sha256 =
  7fec2ed4d6e6f82fe677a7f098ec98d3e99bf4138420f1dd051570c75cf1c72e;

accepted_decision_core_status =
  ACCEPT / INDEPENDENT SOURCE REVIEW CLOSED / NOT PRODUCTION PROOF;

design_v0_8_commit = 1170208;
design_v0_8_content_sha256 =
  410d280a784cb57bc92992dc3a1f22ed4843bc27bae0a3781141b87d14740801;

authorization_package_v0_6_commit = 047b221;
authorization_package_v0_6_acceptance_commit = 6089f0b;
authorization_package_v0_6_content_sha256 =
  e16ca843999959c7583a1b34199c14ea083e456747a86bbb607c342bc493fe37;
```

## 5. Frozen I0 JSON Schema binding

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
  BOUND / FROZEN WITH CONTRACT V1.8;

independent_json_schema_validator_status =
  NOT RUN / NOT AUTHORIZED.
```

## 6. Requested candidate stage set

```text
requested_candidate_stage_set =
  IMPLEMENTATION,
  FIXTURE_PREPARATION,
  EXECUTION;
```

These are candidate requests only. Each requires a separate Human Authorization
Record. No stage is authorized by this instance, by contract acceptance, by
another stage, or by the accepted Decision Core.

## 7. IMPLEMENTATION stage binding

```text
implementation_authorization_record_identity =
  REQUIRED_BEFORE_IMPLEMENTATION;

authorized_repository_revision =
  REBIND_AT_ISSUE_FROM_FROZEN_CONTRACT_BASE_6AC85F68;

authorized_writable_path_set =
  simigo2-experimental/Sources/SimiGo2Experimental/PersistentSRSRepresentation.swift,
  simigo2-experimental/Tests/SimiGo2ExperimentalTests/PersistentSRSRepresentationTests.swift;

frozen_nonwritable_test_input =
  docs/02-evidence/persistent-srs-20261011/PERSISTENT_SRS_RECORD_JSON_SCHEMA_V1.6.json;

forbidden_path_set =
  integrated-es-palace/**,
  docs/02-evidence/database-carrier-equivalence-campaign-v2.1-e8-reserved-20261008/**,
  canonical PALACE roots,
  canonical Information Space roots,
  all other source and evidence paths;

target_module =
  PersistentSRSRepresentation;

forbidden_dependency_set =
  MLX,
  SQLite,
  canonical PALACE storage,
  canonical Information Space storage,
  network clients,
  new external Swift packages,
  V6 runner/child/marker/evidence mutation;

build_or_artifact_plan =
  swift build --product SimiGo2Experimental,
  swift test --filter PersistentSRSRepresentationTests;

implementation_completion_evidence_requirements =
  build log,
  filtered test log,
  source SHA256 set,
  JSON Schema conformance record from separately authorized validator run,
  implementation_completion_gate =
    implementation source may be written only under a separate implementation
      authorization;
    implementation may not be marked COMPLETE until the separately authorized
      JSON Schema validator run has completed successfully;
    validator authorization is a completion prerequisite and is not included in
      implementation authorization;
  canonical encoding conformance record,
  NIL versus explicit-empty evidence,
  unordered reorder and duplicate-count evidence,
  UTC strict-parser evidence,
  UTF-8 byte identity evidence,
  logical-key conflict evidence,
  different-key content-collision evidence,
  PR-A41 same-key/same-digest/different-I1 branch-control evidence,
  fail-closed verification evidence;

result_artifact_content_address_placeholder =
  REQUIRED_AFTER_SEPARATELY_AUTHORIZED_IMPLEMENTATION.
```

## 8. FIXTURE_PREPARATION stage binding

```text
fixture_authorization_record_identity =
  REQUIRED_BEFORE_FIXTURE_PREPARATION;

fixture_set_identity =
  SIMIGO_PERSISTENT_SRS_REPRESENTATION_FIXTURES_V1;

required_fixture_classes =
  valid record,
  reopen record,
  cross-process record,
  payload digest mutation,
  envelope digest mutation,
  signature/domain/signer mutation,
  identity/version role swap,
  logical-key mismatch,
  same-key different-content conflict,
  PR-A41 same-key/same-digest/different-I1 branch-control descriptor,
  different-key content-addressed collision,
  NIL-to-empty mutation,
  valid unordered reorder,
  duplicate-count mutation,
  truncated record,
  short-frame record,
  trailing-byte record,
  partial record,
  corrupt record,
  unknown physical version,
  unknown envelope schema,
  unknown storage version,
  unknown payload schema,
  unknown/extra field,
  completion-state mutation,
  producer-reference mismatch,
  Decision Core binding mismatch,
  unauthorized evidence location,
  overflow/resource-limit case,
  invalid JSON syntax,
  invalid UTC calendar value,
  concurrent-writer case,
  idempotent existing equivalent record;

fixture_content_addresses =
  REQUIRED_AFTER_SEPARATELY_AUTHORIZED_FIXTURE_GENERATION;

fixture_revision_to_digest_bindings =
  REQUIRED_AFTER_SEPARATELY_AUTHORIZED_FIXTURE_GENERATION;

independence_boundary =
  immutable fixtures generated before execution and outside the subject process;

allowed_artifact_set =
  exactly the frozen immutable fixtures in the separately authorized root;

forbidden_artifact_set =
  V6 evidence,
  canonical PALACE,
  canonical Information Space,
  carrier database reuse,
  any unlisted fixture;

expected_decisions_and_typed_failures =
  exactly those frozen by Persistence Manifest Contract v1.8.
```

## 9. EXECUTION stage binding

```text
execution_batch_authorization_record_identities =
  one REQUIRED record per EXECUTION_BATCH_nn;
  no whole-stage single authorization exists;

exact_repository_commit =
  REQUIRED_AFTER_SEPARATELY_AUTHORIZED_IMPLEMENTATION;

exact_implementation_artifact_content_address =
  REQUIRED_AFTER_SEPARATELY_AUTHORIZED_IMPLEMENTATION;

exact_executable_or_runtime_artifact_identity =
  REQUIRED_AFTER_SEPARATELY_AUTHORIZED_IMPLEMENTATION;

runtime_artifact_integrity_binding =
  REQUIRED_AFTER_SEPARATELY_AUTHORIZED_IMPLEMENTATION;

environment_identity =
  local macOS repository sandbox candidate;
  exact OS/toolchain/process identities must be frozen before EXECUTION;

execution_budget_rules =
  each EXECUTION_BATCH_nn is limited to at most 16 fixture executions;
  the limit is a per-batch cap, not a whole-EXECUTION-stage total;
  every executed attempt counts against the batch budget, including attempts
    whose operation outcome is an expected typed rejection;
  budget is consumed by actual execution and is never refunded on failure,
    cancellation, drift, supersession, or later review;
  each authorized scenario may execute at most once in its assigned batch;
  retry or repair cannot occur in the same batch;
  retry or repair requires a new scope-bound Human Authorization Record, a new
    EXECUTION_BATCH_nn, and a new immutable attempt record;
  additional batches require separate Human Authorization Records;
  no implementation may bypass, reset, refill, pool, defer, or reinterpret the
    batch budget;

immutable_attempt_record_model =
  AttemptEvidenceRecord and governance records are separate;

  AttemptEvidenceRecord is immutable once sealed and contains:
    attempt_id;
    matrix scenario;
    batch identity;
    Human Authorization Record;
    fixture digest;
    completed_at_utc;
    completion_order_key;
    operation_outcome;
    scenario_verdict;
    implementation/runtime/environment bindings;
    observer authorization reference;
    start/stop evidence;
    output and typed-failure evidence;
    evidence_digest;
    prior_event_digest where applicable;

  `completed_at_utc` must pass the strict UTC parser;
  `completion_order_key` is computed only from immutable evidence fields and is
    sealed into the record;
  no field of a sealed AttemptEvidenceRecord may be rewritten;
  a SHA256 evidence digest is sealed at creation;
  corrections are expressed only by new immutable records;

  completion_order_key =
    (
      strict parsed completed_at_utc as the ordered tuple
        (year, month, day, hour, minute, second, fractional_decimal_digits);
      evidence_digest_hex compared as lowercase ASCII;
      attempt_id compared as exact UTF-8 bytes
    );

  fractional ordering compares digits after the decimal point as an infinite
    decimal fraction, with missing digits treated as trailing zeros;
  no wall-clock re-reading, locale, timezone conversion, Unicode normalization,
    or mutable counter participates in the order key;

  AttemptStatusEvent is append-only and contains:
    event_id;
    attempt_id;
    event_type;
    governing Human Authorization Record;
    reason;
    prior_event_id;
    event_evidence_digest;
    writer identity;

  attempt event types are:
    EXECUTED;
    FAILED;
    EXCLUDED_BY_AUTHORIZED_SUPERSESSION;

  ClosureCommitRecord is append-only and contains:
    closure_version;
    prior_closure_version;
    selected FINAL_ATTEMPT per EXECUTION_REQUIRED scenario;
    non-selected eligible candidates;
    excluded and historical attempts;
    implementation-test results;
    R29 evidence;
    unresolved-drift verdict;
    governing Human Authorization Record;
    closure_evidence_digest;

  no closure event may rewrite an AttemptEvidenceRecord or a prior
    ClosureCommitRecord;

batch_state_model =
  batch state is derived from immutable batch lifecycle events;
  ACTIVE:
    entered when its separate Human Authorization Record takes effect;
  COMPLETE:
    entered from ACTIVE when every assigned attempt is executed and its batch
      evidence is sealed;
  SUPERSEDED:
    entered only from ACTIVE or COMPLETE by a scope-bound Human Authorization
      Record;
  FAILED_CLOSED:
    entered only from ACTIVE when unrecoverable authorization, integrity,
      runtime, observer, or evidence failure prevents lawful continuation;
  FAILED_CLOSED is terminal and cannot reopen, resume, become ACTIVE, become
    COMPLETE, or become SUPERSEDED as a batch;

batch_transition_rules =
  no transition may delete or rewrite batch evidence;
  SUPERSEDED records why an ACTIVE or COMPLETE batch left closure;
  FAILED_CLOSED records why lawful continuation stopped;
  a FAILED_CLOSED batch remains FAILED_CLOSED even if attempts inside it are
    later excluded by closure governance;

current_attempt_projection =
  derived only from the latest valid AttemptStatusEvent for each attempt;
  EXECUTED_ACTIVE means latest event is EXECUTED and no later exclusion exists;
  FAILED means latest event is FAILED;
  EXCLUDED means latest event is EXCLUDED_BY_AUTHORIZED_SUPERSESSION;
  there is no SELECTED_FINAL attempt state;

scenario_verdict_rules =
  for expected-rejection scenarios, an exact typed rejection is operationally
    expected and does not make the attempt FAILED;
  scenario_verdict is PASS only if rejection status, controls, and evidence match
    the matrix scenario exactly;
  an attempt is FAILED only when scenario_verdict is FAIL because the operation
    outcome, status, controls, bindings, or evidence do not match the scenario;
  all attempts, including FAILED attempts, remain immutable evidence;

supersession_rules =
  batch-level SUPERSEDED causes an EXCLUDED status event for every unclosed
    attempt in that batch;
  attempt-level EXCLUDED status is also required for affected attempts inside a
    FAILED_CLOSED batch because that batch cannot reopen;
  only a scope-bound Human Authorization Record may authorize an exclusion event;
  exclusion never deletes or rewrites the original attempt or prior event;
  EXCLUDED attempts are removed from the current eligible set but remain
    immutable provenance;
  if implementation, runtime, environment, fixture, schema, observer, or
    authorization bindings drift, every affected prior attempt receives an
    EXCLUDED event and cannot enter the candidate set;

closure_is_two_phase =
  Phase 1 produces a Candidate Eligibility Register without selecting a final
    matrix result;
  Phase 2 selects candidates, checks the Candidate Closure Set, and emits a
    ClosureCommitRecord only if all closure checks pass;
  FINAL_ATTEMPT is a role created by an approved ClosureCommitRecord, never a
    precondition for forming candidates;

phase_1_candidate_qualification =
  for every attempt, independently record ELIGIBLE or INELIGIBLE with reasons;
  eligibility requires all of:
    AttemptEvidenceRecord is sealed and its evidence digest verifies;
    completion_order_key is present and recomputes from immutable evidence;
    completed_at_utc passes the strict UTC parser;
    matrix scenario is EXECUTION_REQUIRED;
    scenario_verdict is PASS;
    latest status projection is EXECUTED_ACTIVE and not EXCLUDED or FAILED;
    source batch is ACTIVE or COMPLETE, not SUPERSEDED or FAILED_CLOSED;
    Human Authorization Record, fixture digest, implementation artifact,
      runtime artifact, environment identity, and observer authorization exactly
      match frozen bindings;
    R29 logical-key/collision uniqueness evidence exists and passes for the
      attempt;
    no unresolved authorization, fixture, schema, implementation, runtime,
      environment, observer, or evidence drift exists;

phase_1_output =
  Candidate Eligibility Register vN;
  all eligible attempt IDs by scenario, with completion_order_key;
  all ineligible attempt IDs with exact reasons;
  R29 evidence references;
  unresolved drift list, which must be empty for candidates;
  multiple eligible attempts for one scenario are normal and do not fail
    candidate qualification;

phase_2_candidate_selection =
  group eligible attempts by EXECUTION_REQUIRED scenario;
  sort each group ascending by immutable completion_order_key;
  select the last element, which is the latest attempt;
  register exactly that selected attempt in the Candidate Closure Set;
  record all non-selected eligible attempts as NOT_SELECTED_ELIGIBLE;
  if the resulting set contains more than one entry for any scenario, return
    CLOSURE_DUPLICATE_CANDIDATE;
  multiple eligible source attempts never trigger that duplicate status; only
    duplicate registration in the set does;
  the selected set is deterministic from immutable evidence alone;
  no FINAL_ATTEMPT exists yet;

phase_2_matrix_checks =
  the Candidate Closure Set must satisfy all of:
    exactly one candidate for every EXECUTION_REQUIRED scenario;
    no candidate scenario is missing or duplicated;
    every implementation-test-required entry has PASS evidence;
    R29 evidence covers the candidate set and has no unresolved logical-key,
      content-identity, duplicate-state, or concurrent-writer conflict;
    no candidate has unresolved authorization, fixture, schema, implementation,
      runtime, environment, observer, or evidence drift;

phase_2_closure_commit =
  if and only if all Phase 2 checks pass, emit one ClosureCommitRecord;
  the commit assigns FINAL_ATTEMPT role to exactly one candidate per
    EXECUTION_REQUIRED scenario;
  the commit lists non-selected eligible candidates, excluded attempts, failed
    attempts, prior closure versions, R29 evidence, and closure digest;
  matrix closure succeeds at the commit;
  only after the commit does a candidate have the derived role FINAL_ATTEMPT;

phase_2_rejection =
  if any Phase 2 check fails, emit a ClosureRejectionRecord with all reasons;
  do not emit ClosureCommitRecord or FINAL_ATTEMPT roles;
  leave EXECUTION incomplete and fail-closed;
  attempts remain EXECUTED_ACTIVE, FAILED, or EXCLUDED exactly as projected;
  a rejected closure attempt does not by itself invalidate an existing active
    closure;

closure_commit_state_model =
  ClosureCommitRecord lifecycle states are:
    ACTIVE;
    SUPERSEDED;
    INVALIDATED;
  ACTIVE:
    assigned to a valid commit that has no matching invalidation record;
  SUPERSEDED:
    assigned to a prior active commit after a later valid commit references it;
  INVALIDATED:
    assigned to a commit after a matching ClosureInvalidationRecord;
  SUPERSEDED and INVALIDATED are terminal for that closure version;

closure_invalidation_record =
  ClosureInvalidationRecord is append-only and contains:
    invalidation_id;
    target_closure_version;
    trigger_class;
    affected FINAL_ATTEMPT roles and attempt_ids;
    affected binding fields and prior/current digests;
    evidence references;
    governing Human Authorization Record;
    prior_event_id;
    invalidation_evidence_digest;

  invalidation_trigger_classes are exactly:
    SELECTED_ATTEMPT_EXCLUDED;
    SELECTED_ATTEMPT_EVIDENCE_INVALID;
    SELECTED_ATTEMPT_AUTHORIZATION_INVALID;
    SELECTED_ATTEMPT_FIXTURE_BINDING_DRIFT;
    SELECTED_ATTEMPT_RUNTIME_OR_ENVIRONMENT_DRIFT;
    SELECTED_ATTEMPT_OBSERVER_AUTHORIZATION_DRIFT;
    R29_UNIQUENESS_EVIDENCE_INVALID;
    IMPLEMENTATION_TEST_EVIDENCE_INVALID;
    FROZEN_CONTRACT_OR_SCHEMA_BINDING_DRIFT;
    CLOSURE_EVIDENCE_DIGEST_INVALID;

closure_invalidation_matching =
  an invalidation applies only to target_closure_version and only when:
    its trigger affects a FINAL_ATTEMPT role selected by that commit; or
    its evidence proves drift or invalidity of a binding referenced by that
      commit; or
    its evidence proves that R29, implementation-test, closure digest, contract,
      or schema evidence referenced by that commit is invalid;
  events affecting only non-selected eligible candidates do not invalidate the
    commit;
  events affecting only an already superseded or invalidated closure do not make
    a later active closure invalid;
  every matching invalidation requires a scope-bound Human Authorization Record;

current_closure_projection =
  process ClosureCommitRecords in closure_version order;
  begin each valid commit ACTIVE;
  prior ACTIVE commit becomes SUPERSEDED when a later valid commit references it;
  a matching ClosureInvalidationRecord makes that target commit INVALIDATED;
  a later valid replacement commit may become ACTIVE even though its prior
    version remains INVALIDATED;
  CLOSURE_REJECTED is not a commit lifecycle event and never changes an existing
    commit state;
  current_closure =
    the latest commit whose projected state is ACTIVE;
  if there is no ACTIVE closure, there is no current matrix closure;
  invalidation is not undone by rewriting history; only a later valid replacement
    closure can become current;

matrix_closure_rules =
  EXECUTION matrix closure exists only when current_closure is ACTIVE;
  the ACTIVE ClosureCommitRecord must contain:
    exactly one FINAL_ATTEMPT for every EXECUTION_REQUIRED scenario;
    no unresolved authorization, fixture, schema, implementation, runtime,
      environment, observer, or evidence drift;
    all implementation-test-required PASS evidence;
    valid R29 uniqueness evidence;
    immutable references to all prior closure versions and invalidations;

historical_semantics =
  a FAILED attempt remains failed history;
  an EXCLUDED attempt remains excluded history;
  a FINAL_ATTEMPT in Closure vN remains a historical final selection for vN even
    if Closure vN+1 excludes or invalidates it;
  an INVALIDATED Closure vN remains invalid history even after replacement;
  history does not block closure when the latest valid closure has a replacement
    FINAL_ATTEMPT;
  no scenario may have more than one FINAL_ATTEMPT in the same current closure.

authorized_effect_set =
  create/read/verify immutable records only inside the authorized evidence root;

filesystem_scope =
  authorized evidence root only;

network_scope =
  DENIED;

validity_boundary =
  frozen Contract v1.8,
  frozen I0 Schema v1.6,
  exact implementation digest,
  exact fixture digest set,
  exact environment digest,
  exact observer authorization,
  and applicable Human Authorization Record must remain unchanged.
```

## 10. Writer lock, scan, collision, and idempotent binding

```text
writer_lock_mechanism =
  exclusive root writer lock;
  lock identity and implementation binding REQUIRED_BEFORE_EXECUTION;

logical_key_scan_mechanism =
  ordered tuple scan over exact UTF-8 identity and version bytes;

content_addressed_collision_mechanism =
  inspect proposed records/<payload_digest_hex>.psrs before staging or rename;
  run R1–R28 on existing bytes for classification;
  different logical key -> RECORD_CONTENT_IDENTITY_MISMATCH;
  same logical key and different I1 ->
    PERSISTENT_LOGICAL_KEY_CONFLICT;

classification_descriptor_contract =
  the shared pure classifier accepts only ClassificationDescriptor values;
  ClassificationDescriptor contains exactly:
    ordered logical key (identity_utf8, version_utf8);
    payload_digest_bytes (32-byte SHA-256 value);
    canonical_payload_i1_bytes (exact I1 bytes);
  a descriptor is a pure classification input, not an assertion that a physical
    record has been read or verified;
  descriptor_origin is audit metadata outside classifier input and must not
    affect classification;

production_descriptor_constructor =
  production W3 constructs a descriptor only after required real validation for
    the proposed existing path has completed, including R1–R28;
  production uses the verified existing record's logical key, stored digest, and
    exact I1 bytes;
  production also constructs the proposed descriptor from its logical key, the
    digest recomputed from proposed I1 with frozen SHA-256, and proposed I1;
  the production constructor is internal to the production module and cannot be
    reached by a test-only synthetic constructor;

test_synthetic_constructor =
  V-PERSIST-21 constructs two synthetic ClassificationDescriptor values through
    a test-only constructor confined to the test target;
  the descriptors intentionally have the same payload_digest_bytes but different
    canonical_payload_i1_bytes;
  this exercises the mathematically anomalous collision classification path
    without claiming that a physical record passed R1–R28 and without changing
    production SHA-256;

shared_classifier_binding =
  production W3 and V-PERSIST-21 must invoke the exact same pure production
    classification function;
  production W3 passes descriptors made by production_descriptor_constructor;
  V-PERSIST-21 passes descriptors made by test_synthetic_constructor;
  classifier output depends only on ClassificationDescriptor values and frozen
    contract rules;
  no digest-function substitution, caller-supplied production digest, protocol
    override, environment selector, alternate algorithm, production-visible test
    flag, or production access to the synthetic constructor is allowed;
  implementation review must prove by source and call graph that:
    production W3 and V-PERSIST-21 invoke the same classification symbol;
    synthetic construction is confined to the test target;
    production W3 cannot reach synthetic descriptors;
  expected PR-A41 result is PERSISTENT_LOGICAL_KEY_CONFLICT with no staging,
    rename, overwrite, delete, alternate filename, or NEW_RECORD retry;

idempotent_readback_mechanism =
  existing equivalent record must independently complete R1–R28 and R29;
  no overwrite, staging, rename, delete, repair, alternate filename, or
  NEW_RECORD retry;

overwrite_policy =
  FORBIDDEN.
```

## 11. Observer and channel universe binding

```text
observer_authorization_record_identity =
  REQUIRED_BEFORE_EXECUTION;

observer_artifact_content_address =
  REQUIRED_BEFORE_EXECUTION;

observer_runtime_artifact_identity =
  REQUIRED_BEFORE_EXECUTION;

observer_environment_identity =
  REQUIRED_BEFORE_EXECUTION;

observer_scope =
  process start/stop,
  opened/created/read files,
  exit status,
  and evidence-root effect observation only;

channel_universe_identity =
  REQUIRED_BEFORE_EXECUTION;

covered_channel_classes =
  local filesystem,
  process lifecycle,
  standard output/error,
  exit status,
  declared temporary files;

impossible_channel_classes =
  network,
  model inference,
  canonical Information Space mutation,
  canonical PALACE mutation;

unclassified_channel_set = empty;

coverage_contract_identity =
  REQUIRED_BEFORE_EXECUTION;

observer_integrity_binding =
  REQUIRED_BEFORE_EXECUTION;

observer_human_ruling_reference =
  REQUIRED_BEFORE_EXECUTION.
```

## 12. Runtime dependency closure

```text
expected_semantic_runtime_dependency_set =
  PersistentSRSRepresentation source artifact,
  accepted Decision Core canonical semantics binding,
  PERSISTENT_SRS_CANONICAL_V1 encoding,
  strict UTC parser,
  fixed production Ed25519 verification anchor,
  logical-key and collision classifier;

authorized_mechanical_runtime_dependency_set =
  Swift runtime,
  local filesystem APIs,
  process runtime,
  SHA256 and signature standard-library dependency;

observed_semantic_runtime_dependency_set =
  REQUIRED_FROM_OBSERVER_AFTER_EXECUTION;

observed_mechanical_runtime_dependency_set =
  REQUIRED_FROM_OBSERVER_AFTER_EXECUTION;

semantic_closure_verdict =
  PASS_ONLY_IF_OBSERVED_EQUALS_EXPECTED_SEMANTIC_SET;

mechanical_closure_verdict =
  PASS_ONLY_IF_OBSERVED_IS_SUBSET_OF_AUTHORIZED_MECHANICAL_SET;

undeclared_dependency_detected =
  MUST_BE_FALSE_FOR_EXECUTION_PASS.
```

## 13. Candidate validation matrix

```text
V-PERSIST-01  valid create in isolated root;
V-PERSIST-02  reopen and verify after writer exit;
V-PERSIST-03  cross-process read/verify without ES1 memory;
V-PERSIST-04  reject payload digest mutation;
V-PERSIST-05  reject envelope digest mutation;
V-PERSIST-06  reject signature/domain/signer mutation;
V-PERSIST-07  reject identity/version role swap;
V-PERSIST-08  reject NIL-to-empty mutation;
V-PERSIST-09  accept valid unordered reorder;
V-PERSIST-10  reject duplicate-count mutation;
V-PERSIST-11  reject truncated, short-frame, trailing-byte, partial, or corrupt record;
V-PERSIST-12  reject unknown physical/envelope/storage/payload version or schema;
V-PERSIST-13  reject unknown or extra fields;
V-PERSIST-14  reject completion-state mutation;
V-PERSIST-15  reject producer-reference or Decision Core-binding mismatch;
V-PERSIST-16  reject logical-key mismatch, duplicate record state, and
              unauthorized location;
V-PERSIST-17  reject invalid JSON syntax and overflow/resource-limit input;
V-PERSIST-18  reject invalid UTC calendar/time values;
V-PERSIST-19  verify idempotent existing equivalent record without overwrite;
V-PERSIST-20  verify binding to accepted Decision Core and canonical encoding;
V-PERSIST-21  exercise the PR-A41 controlled branch descriptor and require
              PERSISTENT_LOGICAL_KEY_CONFLICT with no staging, rename,
              overwrite, delete, alternate filename, or NEW_RECORD retry.
```

Coverage and classifier rules:

```text
V-PERSIST-01 through V-PERSIST-21 constitute complete candidate coverage;
V-PERSIST-21 is an implementation-stage branch-control test using synthetic
  ClassificationDescriptor values, not production digest substitution or a
  persisted SHA-256 collision;
the coverage plan must classify every matrix entry as EXECUTION_REQUIRED or
  IMPLEMENTATION_TEST_REQUIRED before EXECUTION BATCH_01;
every EXECUTION_REQUIRED entry is assigned to exactly one authorized batch;
every execution attempt evidence record is immutable; candidate selection and
  closure validity use the deterministic order-key and closure-projection rules
  in section 9;
all IMPLEMENTATION_TEST_REQUIRED entries must pass and the selected
  the ACTIVE ClosureCommitRecord FINAL_ATTEMPT roles must cover every
  EXECUTION_REQUIRED entry;
a missing, duplicate, unresolved drift, or scenario without exactly one valid
  FINAL_ATTEMPT leaves the matrix incomplete.

PR-A41 production/test classifier binding:
  production W3 and V-PERSIST-21 must call the same pure production
    classification function for the proposed content-addressed path;
  that function accepts verified record descriptors and returns the contract
    status without filesystem mutation;
  the test target may construct synthetic descriptors only through a separate
    test-only constructor/caller;
  the synthetic descriptors may state the same payload digest with different I1
    bytes solely to exercise the impossible SHA-256 collision branch;
  the production write entry point must derive its digest only by recomputing
    frozen SHA-256 over I1 and must not access the test-only constructor or
    accept a caller-supplied digest;
  no digest-function substitution, protocol override, environment selector,
    alternate algorithm, or production-visible test flag is allowed;
  implementation review must prove by source/call graph that:
    production W3 and V-PERSIST-21 invoke the same classification symbol;
    the synthetic descriptor constructor/caller is confined to the test target;
    the production W3 path cannot reach synthetic descriptors.
```

All outcomes are fail-closed unless every required integrity, schema, identity,
encoding, domain, signer, digest, presence, location, lock, and uniqueness check
passes.

## 14. Evidence root and integrity

```text
authorized_evidence_root =
  REQUIRED_BEFORE_SEPARATELY_AUTHORIZED_EXECUTION;
  must be isolated from canonical PALACE, canonical Information Space, V6
  evidence, and all unrelated repository state;

evidence_locations_and_integrity_bindings =
  REQUIRED_AFTER_EACH_SEPARATELY_AUTHORIZED_STAGE;

validity_and_use_budgets =
  section 9 budget plus exact frozen contract, schema, implementation, fixture,
  environment, observer, and authorization bindings.
```

This document creates no evidence root, marker, consumed marker, fixture, or
persistent record.

## 15. Current prohibitions

```text
IMPLEMENTATION = NOT AUTHORIZED;
FIXTURE_PREPARATION = NOT AUTHORIZED;
EXECUTION = NOT AUTHORIZED;
IS_MUTATION = NOT REQUESTED / FORBIDDEN;
marker creation = FORBIDDEN;
consumed marker creation = FORBIDDEN;
evidence-root creation = FORBIDDEN;
canonical PALACE mutation = FORBIDDEN;
canonical Information Space mutation = FORBIDDEN;
MLX execution = FORBIDDEN;
V6 rerun = FORBIDDEN;
production deployment / traffic = NOT AUTHORIZED.
```

## 16. Next lawful objects

Human may separately authorize review or execution of:

```text
an independent JSON Schema validator run bound to exact validator/schema inputs;
IMPLEMENTATION under section 7;
FIXTURE_PREPARATION under section 8;
EXECUTION under sections 9–14.
```

Each remains a separate decision. None is authorized by this rebound.
