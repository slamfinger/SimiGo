# Persistent SRS Representation Manifest Instance v2.1

> **Status:** REBOUND TO FROZEN CONTRACT / REVISION CANDIDATE /
> NOT EXECUTABLE / NO STAGE AUTHORIZED
> **Date:** 2026-10-12
> **Supersedes:** Manifest Instance v2.0 (`REVISE / SUPERSEDED / NOT EXECUTED`)
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
  SIMIGO_PERSISTENT_SRS_REPRESENTATION_MANIFEST_INSTANCE_V2.1;

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

persistence_contract_request_base_commit =
  b1ba532b2fb013d3cabea83748b9ca0d54b095fc;

manifest_revision_parent_commit =
  62d128062dcde6021d803989e85c612c7dbc7148;

manifest_revision_source_instance =
  SIMIGO_PERSISTENT_SRS_REPRESENTATION_MANIFEST_INSTANCE_V1.9;

manifest_revision_source_document_sha256 =
  b7fb2ec72778272d1ee0c6bb3333bf3917b153afd5ac28cb36875048cbd665b0;

administrative_revision_reason =
  correct prior_instance_ruling and synchronize manifest_revision_parent_commit
  with the direct Git parent of this revision; no semantic change is authorized
  or made;

source_field_semantics =
  persistence_contract_request_base_commit is the fixed upstream request basis
    for the persistence contract request and is not the parent of this revision;
  manifest_revision_parent_commit is the direct Git parent commit of the current
    Manifest revision;
  manifest_revision_source_instance and source_document_sha256 identify the
    directly superseded Manifest Instance;
  these fields are distinct and must not be substituted for one another;

integrity_binding =
  exact accepted source commit plus SHA256 above;

superseded_instance =
  SIMIGO_PERSISTENT_SRS_REPRESENTATION_MANIFEST_INSTANCE_V2.0;

superseded_instance_status =
  REVISE / SUPERSEDED BY V2.1 / NOT EXECUTED.
```

This instance is bound but not executable. Contract acceptance does not authorize
any stage.

## 2. Authorization provenance

```text
prior_instance_ruling =
  REVISE_PERSISTENT_SRS_MANIFEST_INSTANCE_V1.8;

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

  AttemptEvidenceRecord is immutable once sealed and contains exactly:
    attempt_id;
    matrix scenario;
    batch identity;
    Human Authorization Record;
    fixture digest;
    completed_at_utc;
    operation_outcome;
    scenario_verdict;
    implementation/runtime/environment bindings;
    observer authorization reference;
    start/stop evidence;
    output and typed-failure evidence;
    base_evidence_digest;
    completion_order_key;
    evidence_digest;

  core_evidence_fields are all fields above except base_evidence_digest,
    completion_order_key, and evidence_digest;

  primitive_and_structural_value_encoding =
    all integers used as framing are unsigned big-endian;
    FIELD :=
      label_length_u16 +
      label ASCII bytes +
      value_type_u8 +
      value_length_u64 +
      value_bytes;

    value_type 0x00 = NULL:
      value_length is 0 and value_bytes is empty;
    value_type 0x01 = BOOLEAN:
      value_length is 1; value_bytes is 0x00 or 0x01;
    value_type 0x02 = UTF8_STRING:
      value_bytes is the exact valid UTF-8 encoding with no normalization;
    value_type 0x03 = JSON_STRUCTURE:
      value_bytes is the exact RFC 8785 serialization of an object or array;
    value_type 0x04 = BYTE_SEQUENCE:
      value_bytes is an exact byte string;
    value_type 0x05 = COMPLETION_ORDER_KEY_V1:
      value_bytes is the exact order-key serialization defined below;
    all other value types are invalid;
    numeric JSON values are forbidden in evidence value bytes;
    duplicate field labels, unknown labels, missing labels, reordered labels,
      invalid UTF-8, invalid JSON, trailing bytes, and unsupported types fail;

  core_evidence_fields and fixed order:
    attempt_id;
    matrix_scenario;
    batch_identity;
    human_authorization_record;
    fixture_digest;
    completed_at_utc;
    operation_outcome;
    scenario_verdict;
    implementation_runtime_environment_bindings;
    observer_authorization_reference;
    start_stop_evidence;
    output_and_typed_failure_evidence;

  core_canonical_data =
    ASCII("SIMISRS-ACORE-V1") +
    field_count_u32 (12) +
    exactly 12 FIELD values in the fixed order above;

  base_evidence_digest =
    SHA256(
      ASCII("SIMIGO_PERSISTENT_SRS_ATTEMPT_CORE_V1") + 0x00 +
      core_canonical_data
    );

  completion_order_key_value =
    ASCII("SIMISRS-AKEY-V1") +
    year_u16_be +
    month_u8 +
    day_u8 +
    hour_u8 +
    minute_u8 +
    second_u8 +
    fractional_digit_count_u32_be +
    fractional_decimal_digits_ascii +
    base_evidence_digest_hex_ascii (64 bytes) +
    attempt_id_length_u64_be +
    attempt_id_exact_utf8_bytes;

  fractional digits use exact supplied digits; absence is length zero;
  fractional ordering treats missing digits as trailing zeros;
  no wall-clock re-reading, locale, timezone conversion, Unicode normalization,
    or mutable counter participates in the order key;

  completion_order_key =
    value_type 0x05 plus u64 length plus completion_order_key_value;

  sealed_canonical_data =
    ASCII("SIMISRS-ASEALED-V1") +
    field_count_u32 (14) +
    the 12 core FIELD values in fixed order +
    FIELD("base_evidence_digest", UTF8_STRING, lowercase base digest hex) +
    FIELD("completion_order_key", COMPLETION_ORDER_KEY_V1, order key bytes);

  evidence_digest =
    SHA256(
      ASCII("SIMIGO_PERSISTENT_SRS_ATTEMPT_SEALED_V1") + 0x00 +
      sealed_canonical_data
    );

  no field of a sealed AttemptEvidenceRecord may be rewritten;
  corrections are expressed only by new immutable records;

  fixed_encoding_test_vector =
    This vector freezes framing, JCS, order-key, and digest behavior. It is an
    encoding-consistency vector only and is not a fixture, execution, model run,
    or evidence-root creation.

    fixed inputs:
      attempt_id = "ATTEMPT-0001";
      matrix_scenario = "V-PERSIST-20";
      batch_identity = "EXECUTION_BATCH_01";
      human_authorization_record = "HAR-PERSIST-TEST-001";
      fixture_digest = 64 lowercase hexadecimal zero characters;
      completed_at_utc = "2026-10-11T00:00:00Z";
      operation_outcome = "VALID_CREATE_PASS";
      scenario_verdict = "PASS";
      implementation_runtime_environment_bindings = JCS object:
        {"environment_identity":"TEST-ENV",
         "implementation_artifact_sha256":"<64 zero characters>",
         "runtime_artifact_identity":"TEST-RUNTIME"};
      observer_authorization_reference = null;
      start_stop_evidence = JCS object:
        {"started_at_utc":"2026-10-11T00:00:00Z",
         "stopped_at_utc":"2026-10-11T00:00:01Z"};
      output_and_typed_failure_evidence = null;

    required outputs:
      core_canonical_data_length = 897;
      core_canonical_data_hex =
        53494d495352532d41434f52452d56310000000c000a617474656d70745f696402000000000000000c415454454d50542d30303031000f6d61747269785f7363656e6172696f02000000000000000c562d504552534953542d3230000e62617463685f6964656e74697479020000000000000012455845435554494f4e5f42415443485f3031001a68756d616e5f617574686f72697a6174696f6e5f7265636f72640200000000000000144841522d504552534953542d544553542d303031000e666978747572655f64696765737402000000000000008030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030300010636f6d706c657465645f61745f757463020000000000000014323032362d31302d31315430303a30303a30305a00116f7065726174696f6e5f6f7574636f6d6502000000000000001156414c49445f4352454154455f5041535300107363656e6172696f5f7665726469637402000000000000000450415353002b696d706c656d656e746174696f6e5f72756e74696d655f656e7669726f6e6d656e745f62696e64696e67730300000000000000b27b22656e7669726f6e6d656e745f6964656e74697479223a22544553542d454e56222c22696d706c656d656e746174696f6e5f61727469666163745f736861323536223a2230303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030222c2272756e74696d655f61727469666163745f6964656e74697479223a22544553542d52554e54494d45227d00206f627365727665725f617574686f72697a6174696f6e5f7265666572656e6365000000000000000000001373746172745f73746f705f65766964656e63650300000000000000517b22737461727465645f61745f757463223a22323032362d31302d31315430303a30303a30305a222c2273746f707065645f61745f757463223a22323032362d31302d31315430303a30303a30315a227d00216f75747075745f616e645f74797065645f6661696c7572655f65766964656e6365000000000000000000;
      core_canonical_data_sha256 =
        92ed449b764e791395354cd2708d13e66199df46297182b7508c138c6a2cbe19;
      base_evidence_digest =
        5311214a709efd1ba72823da71238796cb45ecbd93d7ef3ee8f6ca3ef372258f;
      completion_order_key_value_length = 110;
      completion_order_key_value_hex =
        53494d495352532d414b45592d563107ea0a0b0000000000000035333131323134613730396566643162613732383233646137313233383739366362343565636264393364376566336565386636636133656633373232353866000000000000000c415454454d50542d30303031;
      completion_order_key_value_sha256 =
        17a53a9c8c0fee81fbfe38ec9714e2de988af245d1e931c6ef2ea56582bcf6ce;
      sealed_canonical_data_length = 1135;
      sealed_canonical_data_hex =
        53494d495352532d415345414c45442d56310000000e000a617474656d70745f696402000000000000000c415454454d50542d30303031000f6d61747269785f7363656e6172696f02000000000000000c562d504552534953542d3230000e62617463685f6964656e74697479020000000000000012455845435554494f4e5f42415443485f3031001a68756d616e5f617574686f72697a6174696f6e5f7265636f72640200000000000000144841522d504552534953542d544553542d303031000e666978747572655f64696765737402000000000000008030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030300010636f6d706c657465645f61745f757463020000000000000014323032362d31302d31315430303a30303a30305a00116f7065726174696f6e5f6f7574636f6d6502000000000000001156414c49445f4352454154455f5041535300107363656e6172696f5f7665726469637402000000000000000450415353002b696d706c656d656e746174696f6e5f72756e74696d655f656e7669726f6e6d656e745f62696e64696e67730300000000000000b27b22656e7669726f6e6d656e745f6964656e74697479223a22544553542d454e56222c22696d706c656d656e746174696f6e5f61727469666163745f736861323536223a2230303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030222c2272756e74696d655f61727469666163745f6964656e74697479223a22544553542d52554e54494d45227d00206f627365727665725f617574686f72697a6174696f6e5f7265666572656e6365000000000000000000001373746172745f73746f705f65766964656e63650300000000000000517b22737461727465645f61745f757463223a22323032362d31302d31315430303a30303a30305a222c2273746f707065645f61745f757463223a22323032362d31302d31315430303a30303a30315a227d00216f75747075745f616e645f74797065645f6661696c7572655f65766964656e63650000000000000000000014626173655f65766964656e63655f646967657374020000000000000040353331313231346137303965666431626137323832336461373132333837393663623435656362643933643765663365653866366361336566333732323538660014636f6d706c6574696f6e5f6f726465725f6b657905000000000000006e53494d495352532d414b45592d563107ea0a0b0000000000000035333131323134613730396566643162613732383233646137313233383739366362343565636264393364376566336565386636636133656633373232353866000000000000000c415454454d50542d30303031;
      sealed_canonical_data_sha256 =
        6188e6fa6bac44ef85ddac9181818516466116f499768ca2d70b7937780882e1;
      evidence_digest =
        9dc1891f6961852660524e1a23f681745ab05c08272c6391ddc0ef6873e61615;

    implementation still must compare full canonical bytes byte-for-byte; hashes
    are consistency checks and do not replace canonical parsing.

  attempt_evidence_verification_order =
    V1 parse core fields and verify exact magic/count/order/types/no trailing bytes;
    V2 recompute base_evidence_digest and compare to the stored value;
    V3 recompute completion_order_key and compare to the stored bytes;
    V4 reconstruct sealed_canonical_data;
    V5 recompute evidence_digest and compare to the stored value;
    encoding shape mismatch -> ATTEMPT_CANONICAL_ENCODING_MISMATCH;
    unsupported value type -> UNSUPPORTED_CANONICAL_VALUE_TYPE;
    order-key mismatch -> INVALID_COMPLETION_ORDER_KEY;
    digest mismatch -> ATTEMPT_EVIDENCE_DIGEST_MISMATCH;

  completion_order_key is not an input to base_evidence_digest;
  evidence_digest binds core evidence, base digest, and completion_order_key;
  therefore there is no circular dependency;

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
    prior_closure_head_version;
    selected FINAL_ATTEMPT per EXECUTION_REQUIRED scenario;
    non-selected eligible candidates;
    excluded and historical attempts;
    implementation-test results;
    R29 evidence;
    unresolved-drift verdict;
    governing Human Authorization Record;
    closure_evidence_digest;

  no closure event may rewrite an AttemptEvidenceRecord, an AttemptStatusEvent,
    or a prior ClosureCommitRecord;

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
    AttemptEvidenceRecord passes V1–V5 evidence verification;
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
  before emitting a commit, compute the current closure chain head;
  a new commit is valid only if:
    closure_version is exactly current head version plus one;
    prior_closure_head_version is exactly the current head version;
    the current head is ACTIVE or INVALIDATED;
  if the current head is ACTIVE, it becomes SUPERSEDED and the new commit
    becomes ACTIVE;
  if the current head is INVALIDATED, it remains INVALIDATED and the new valid
    replacement commit becomes ACTIVE;
  a commit with any other prior version is a fork and must be rejected with
    CLOSURE_CHAIN_FORK_REJECTED;
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
    head;

closure_chain_model =
  all valid ClosureCommitRecords form one linear chain:
    C1 -> C2 -> C3 -> ... -> current_head;
  C1 has no prior closure head;
  every later Cn must reference exactly Cn-1;
  closure_version must equal n with no gaps;
  forks, duplicate versions, skipped versions, and out-of-chain commits are
    invalid and cannot enter current closure;

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

  an invalidation is in-chain only if target_closure_version equals the current
    head;
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
  an in-chain invalidation applies only to the current head and only when:
    its trigger affects a FINAL_ATTEMPT role selected by that head; or
    its evidence proves drift or invalidity of a binding referenced by that head;
    or
    its evidence proves that R29, implementation-test, closure digest, contract,
      or schema evidence referenced by that head is invalid;
  an invalidation targeting any non-head version is rejected with
    CLOSURE_INVALIDATION_TARGET_NOT_HEAD and does not affect current closure;
  events affecting only non-selected eligible candidates do not invalidate the
    head;
  events affecting only an already superseded or invalidated prior version do
    not make a later active head invalid;
  every matching invalidation requires a scope-bound Human Authorization Record;

closure_state_projection =
  build the unique linear chain C1..Chead;
  C1 is ACTIVE unless invalidated;
  every Cn referenced by Cn+1 becomes SUPERSEDED if it was ACTIVE;
  every Cn referenced by an invalidating replacement remains INVALIDATED if it
    was already INVALIDATED;
  the head is INVALIDATED if an in-chain matching invalidation targets it;
  otherwise the head is ACTIVE;
  prior versions never become ACTIVE after being SUPERSEDED or INVALIDATED;
  current_closure =
    head if head is ACTIVE;
    no current closure if head is INVALIDATED;
  a rejected replacement does not change head state;
  invalidation is not undone by rewriting history; only a later valid replacement
    commit referencing the invalidated head can become current;

matrix_closure_rules =
  EXECUTION matrix closure exists only when current_closure is ACTIVE;
  the ACTIVE ClosureCommitRecord must contain:
    exactly one FINAL_ATTEMPT for every EXECUTION_REQUIRED scenario;
    no unresolved authorization, fixture, schema, implementation, runtime,
      environment, observer, or evidence drift;
    all implementation-test-required PASS evidence;
    valid R29 uniqueness evidence;
    immutable references to every prior closure version and invalidation;

historical_semantics =
  a FAILED attempt remains failed history;
  an EXCLUDED attempt remains excluded history;
  a FINAL_ATTEMPT in Closure vN remains a historical final selection for vN even
    if Closure vN+1 excludes or invalidates it;
  an INVALIDATED Closure vN remains invalid history even after replacement;
  a SUPERSEDED branch fork is not part of the valid chain;
  history does not block closure when the latest valid head has a replacement
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

### 9.1 Attempt evidence encoding failure statuses

The instance-level status set is closed:

```text
ATTEMPT_CANONICAL_ENCODING_MISMATCH;
UNSUPPORTED_CANONICAL_VALUE_TYPE;
INVALID_COMPLETION_ORDER_KEY;
ATTEMPT_EVIDENCE_DIGEST_MISMATCH;
```

No aliases are valid.

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
every execution attempt evidence record is immutable; candidate selection,
  digest derivation, and closure validity use the canonical core/sealed digest
  and linear-head rules in section 9;
all IMPLEMENTATION_TEST_REQUIRED entries must pass and the selected
  the ACTIVE head ClosureCommitRecord FINAL_ATTEMPT roles must cover every
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

## 16. Acceptance addition

```text
C26 attempt canonical bytes, base digest, order key, and sealed digest are fixed
    by section 9 and the fixed encoding vector;
C27 fixed-vector lengths, full byte sequences, and digests must agree;
C28 contract request base and manifest revision parent/source bindings are
    explicitly separated.
```

## 17. Next lawful objects

Human may separately authorize review or execution of:

```text
an independent JSON Schema validator run bound to exact validator/schema inputs;
IMPLEMENTATION under section 7;
FIXTURE_PREPARATION under section 8;
EXECUTION under sections 9–14.
```

Each remains a separate decision. None is authorized by this rebound.
## 18. Decision requested

Human is asked to return exactly one:

```text
ACCEPT_PERSISTENT_SRS_MANIFEST_INSTANCE_V2.1
```

or

```text
REVISE_PERSISTENT_SRS_MANIFEST_INSTANCE_V2.1
```

or

```text
REJECT_PERSISTENT_SRS_MANIFEST_INSTANCE_V2.1
```

Acceptance binds this instance for future separately authorized stages. It does
not authorize implementation, fixture preparation, execution, validator run,
markers, evidence root, ES2 consumption, non-recompute attribution, PALACE,
Information Space, MLX, V6, or production operation.
