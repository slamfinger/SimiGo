# Persistent SRS Representation Manifest Instance v1.0

> **Status:** REBOUND TO FROZEN CONTRACT / NOT EXECUTABLE /
> NO STAGE AUTHORIZED
> **Date:** 2026-10-11
> **Supersedes:** Conditional Manifest Instance v0.1 for governance binding only
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
  SIMIGO_PERSISTENT_SRS_REPRESENTATION_MANIFEST_INSTANCE_V1.0;

manifest_instance_status =
  REBOUND / DESIGN_FROZEN_CONTRACT_BOUND / NOT_EXECUTABLE /
  HUMAN_STAGE_AUTHORIZATIONS_REQUIRED;

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

integrity_binding =
  exact accepted source commit plus SHA256 above;

superseded_conditional_instance =
  SIMIGO_PERSISTENT_SRS_REPRESENTATION_MANIFEST_INSTANCE_V0.1.
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
  canonical encoding conformance record,
  NIL versus explicit-empty evidence,
  unordered reorder and duplicate-count evidence,
  UTC strict-parser evidence,
  UTF-8 byte identity evidence,
  logical-key conflict and content-collision evidence,
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
execution_authorization_record_identity =
  REQUIRED_BEFORE_EXECUTION;

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

run_id_or_run_budget =
  one execution per separately authorized fixture;
  maximum sixteen fixture executions;
  failed execution consumes that fixture budget;
  repair/retry requires a new scope-bound Human Authorization Record;

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
V-PERSIST-16  reject logical-key mismatch, same-key different-content conflict,
              different-key content collision, duplicate record state, and
              unauthorized location;
V-PERSIST-17  reject invalid JSON syntax and overflow/resource-limit input;
V-PERSIST-18  reject invalid UTC calendar/time values;
V-PERSIST-19  verify idempotent existing equivalent record without overwrite;
V-PERSIST-20  verify binding to accepted Decision Core and canonical encoding.
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
