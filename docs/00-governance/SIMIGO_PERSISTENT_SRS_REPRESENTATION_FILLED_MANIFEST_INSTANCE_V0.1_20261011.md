# Persistent SRS Representation Filled Manifest Instance v0.1

> **Status:** CONDITIONAL DRAFT / SUBMITTED WITH HUMAN AUTHORIZATION REQUEST V0.1 /
> NOT EXECUTABLE
> **Date:** 2026-10-11
> **Human Authorization Request:** `SIMIGO_PERSISTENT_SRS_REPRESENTATION_AUTHORIZATION_REQUEST_V0.1_20261011.md`
> **Authorization request SHA256:** `4063787b0680da2ccd872ec949c4602295c8bd5d9d6620f7149ff6caa288c791`
> **Canonical PALACE mutation:** FORBIDDEN
> **Canonical Information Space mutation:** FORBIDDEN
> **MLX execution:** FORBIDDEN
> **V6 rerun:** FORBIDDEN
> **Independent ES₂ consumption:** NOT REQUESTED
> **Non-recompute attribution:** NOT REQUESTED

## 1. Manifest identity and governing contract

```text
manifest_instance_identity =
  SIMIGO_PERSISTENT_SRS_REPRESENTATION_MANIFEST_INSTANCE_V0.1;

manifest_instance_status =
  CONDITIONAL_DRAFT / HUMAN_REVIEW_REQUIRED / NO_STAGE_AUTHORIZED;

persistence_manifest_contract_identity =
  SIMIGO_PERSISTENT_SRS_REPRESENTATION_MANIFEST_CONTRACT_V1.0;

persistence_manifest_contract_status =
  PROPOSED / NOT YET DELIVERED / NOT ACCEPTED / NOT FROZEN;

persistence_manifest_contract_integrity_binding =
  TO_BE_FROZEN_BEFORE_ANY_STAGE_AUTHORIZATION;

authorization_request_reference =
  SIMIGO_PERSISTENT_SRS_REPRESENTATION_AUTHORIZATION_REQUEST_V0.1_20261011;

human_ruling_reference =
  REQUIRED_BEFORE_CONTRACT_FREEZE;
```

This is a filled conditional draft, not an executable instance. It becomes valid
only if Human first accepts the authorization request, then separately accepts
and freezes a persistence-specific manifest contract.

## 2. Compatibility binding to SRS-VAL Manifest Contract v1.0

```text
srs_val_manifest_contract_identity =
  SRS_VAL_01_RUN_IMPLEMENTATION_MANIFEST_CONTRACT_V1.0;

srs_val_manifest_contract_status =
  ACCEPT / FROZEN / NOT VALID FOR PERSISTENCE TARGET;

srs_val_manifest_contract_reviewed_basis_commit = f69a0e2;

srs_val_manifest_contract_content_sha256 =
  b9fbc290e096bd94b825bee0e4e8c3c3a4a7efea742cbf9bf755efd75d41055e;

compatibility_verdict =
  INCOMPATIBLE_FOR_PERSISTENCE_TARGET / RETAINED_AS_FROZEN_PROVENANCE;

reason =
  Contract v1.0 freezes T-IMPL-01 to SRS-VAL Decision Core and explicitly
  excludes persistence, SQLite, runner, observer, fixture builder, model/runtime
  stack, execution harness, and IS mutation executor.
```

No field in this instance claims that persistence is an authorized expansion of
T-IMPL-01.

## 3. Frozen provenance and accepted implementation binding

```text
request_base_commit =
  553cc8c58ead7f88d139d39627fca920f2eadc22;

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

## 4. Requested stage set

```text
requested_stage_set =
  IMPLEMENTATION,
  FIXTURE_PREPARATION,
  EXECUTION;
```

Each stage requires a separate Human Authorization Record. No stage may be
derived from acceptance of this request, from another stage, or from the
accepted Decision Core.

## 5. IMPLEMENTATION stage candidate binding

```text
implementation_authorization_record_identity =
  REQUIRED_BEFORE_IMPLEMENTATION;

authorized_repository_revision =
  TO_BE_REBOUND_AT_ISSUE_FROM_REQUEST_BASE_553CC8C5;

authorized_writable_path_set =
  simigo2-experimental/Sources/SimiGo2Experimental/PersistentSRSRepresentation.swift,
  simigo2-experimental/Tests/SimiGo2ExperimentalTests/PersistentSRSRepresentationTests.swift;

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
  existing V6 runner/child evidence;

build_or_artifact_plan =
  swift build --product SimiGo2Experimental,
  swift test --filter PersistentSRSRepresentationTests;

implementation_completion_evidence_requirements =
  build log,
  filtered test log,
  source SHA256 set,
  canonical encoding conformance record,
  NIL versus empty-list regression evidence,
  unordered collection regression evidence,
  fail-closed verification evidence;

result_artifact_content_address_placeholder =
  REQUIRED_AFTER_IMPLEMENTATION;
```

## 6. FIXTURE_PREPARATION stage candidate binding

```text
fixture_authorization_record_identity =
  REQUIRED_BEFORE_FIXTURE_PREPARATION;

fixture_set_identity =
  SIMIGO_PERSISTENT_SRS_REPRESENTATION_FIXTURES_V1;

fixture_roles:
  F-PERSIST-VALID     = one canonical valid SRS record;
  F-PERSIST-REOPEN    = same record after writer exit;
  F-PERSIST-CROSSPROC = separate-process read/verify input;
  F-PERSIST-DIGEST    = digest-mutated record;
  F-PERSIST-SIGNATURE = signature/signer/domain-mutated record;
  F-PERSIST-ROLE      = identity/version field-role-swapped record;
  F-PERSIST-NIL       = NIL-to-empty collection mutation record;
  F-PERSIST-REORDER   = valid unordered collection reorder record;
  F-PERSIST-TRUNCATED = partial/truncated record;
  F-PERSIST-VERSION   = unknown schema/version record;
  F-PERSIST-EXTRA     = extra-field record;

fixture_content_addresses =
  REQUIRED_AFTER_FROZEN_FIXTURE_GENERATION;

fixture_revision_to_digest_bindings =
  REQUIRED_AFTER_FROZEN_FIXTURE_GENERATION;

independence_boundary =
  fixtures generated before execution and outside the subject process;

allowed_artifact_set =
  exactly the immutable fixtures above in an isolated evidence root;

forbidden_artifact_set =
  V6 evidence,
  canonical PALACE,
  canonical Information Space,
  carrier database reuse,
  any unlisted fixture;

expected_decisions_and_typed_failures =
  frozen by the separate persistence-specific contract before fixture creation.
```

## 7. EXECUTION stage candidate binding

```text
execution_authorization_record_identity =
  REQUIRED_BEFORE_EXECUTION;

exact_repository_commit =
  TO_BE_REBOUND_AFTER_IMPLEMENTATION_ACCEPTANCE;

exact_implementation_artifact_content_address =
  REQUIRED_AFTER_IMPLEMENTATION;

exact_executable_or_runtime_artifact_identity =
  REQUIRED_AFTER_IMPLEMENTATION;

runtime_artifact_integrity_binding =
  REQUIRED_AFTER_IMPLEMENTATION;

environment_identity =
  local macOS repository sandbox;
  exact OS/toolchain/process identities must be frozen before EXECUTION;

run_id_or_run_budget =
  one execution per separately authorized fixture;
  maximum ten executions for V-PERSIST-01 through V-PERSIST-10;
  failed execution consumes that fixture budget;
  repair/retry requires a new scope-bound Human Authorization Record;

authorized_effect_set =
  create/read/verify immutable records only inside the authorized evidence root;

filesystem_scope =
  authorized evidence root only;

network_scope =
  DENIED;

validity_boundary =
  exact frozen contract, implementation digest, fixture digest set, environment
  digest, and Human Authorization Record must remain unchanged.
```

## 8. Observer and channel universe candidate binding

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
  process start/stop, opened files, created files, read files, exit status,
  and evidence-root effect observation only;

channel_universe_identity =
  TO_BE_FROZEN_WITH_PERSISTENCE_CONTRACT;

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

## 9. Runtime dependency closure

```text
expected_semantic_runtime_dependency_set =
  PersistentSRSRepresentation source artifact,
  accepted SRSVALDecisionCore canonical semantics binding,
  declared persistence schema/canonical encoder,
  declared integrity verifier;

authorized_mechanical_runtime_dependency_set =
  Swift runtime,
  local filesystem APIs,
  process runtime,
  hashing/signature standard library dependency;

observed_semantic_runtime_dependency_set =
  REQUIRED_FROM_OBSERVER_AFTER_EXECUTION;

observed_mechanical_runtime_dependency_set =
  REQUIRED_FROM_OBSERVER_AFTER_EXECUTION;

semantic_closure_verdict =
  PASS_ONLY_IF_EQUAL_TO_EXPECTED_SEMANTIC_SET;

mechanical_closure_verdict =
  PASS_ONLY_IF_OBSERVED_SUBSET_OF_AUTHORIZED_MECHANICAL_SET;

undeclared_dependency_detected =
  MUST_BE_FALSE_FOR_EXECUTION_PASS.
```

## 10. Candidate validation matrix

```text
V-PERSIST-01  valid create in isolated root;
V-PERSIST-02  reopen and verify after writer exit;
V-PERSIST-03  cross-process read/verify without ES1 memory;
V-PERSIST-04  reject digest mutation;
V-PERSIST-05  reject signature/domain/signer mutation;
V-PERSIST-06  reject identity/version field-role swap;
V-PERSIST-07  reject NIL-to-empty collection mutation;
V-PERSIST-08  accept reordered unordered collections;
V-PERSIST-09  reject truncated/unknown-version/extra-field record;
V-PERSIST-10  verify binding to accepted Decision Core and canonical encoding.
```

All candidate outcomes are fail-closed unless every required integrity, schema,
identity, encoding, domain, signer, digest, and presence check passes.

## 11. Evidence and integrity

```text
evidence_root =
  TO_BE_FROZEN_IN_PERSISTENCE_CONTRACT;
  must be isolated from canonical PALACE, canonical Information Space, and V6
  evidence;

evidence_locations_and_integrity_bindings =
  REQUIRED_AFTER_EACH_SEPARATELY_AUTHORIZED_STAGE;

validity_and_use_budgets =
  section 7 run budget plus exact frozen artifact bindings;
```

No evidence root, fixture, marker, consumed marker, or record is created by this
document.

## 12. Current prohibitions

```text
IMPLEMENTATION = NOT AUTHORIZED;
FIXTURE_PREPARATION = NOT AUTHORIZED;
EXECUTION = NOT AUTHORIZED;
IS_MUTATION = NOT REQUESTED / FORBIDDEN;
marker creation = FORBIDDEN;
evidence-root creation = FORBIDDEN;
canonical PALACE mutation = FORBIDDEN;
canonical Information Space mutation = FORBIDDEN;
MLX execution = FORBIDDEN;
V6 rerun = FORBIDDEN;
production deployment / traffic = FORBIDDEN.
```

## 13. Decision requested

Human should first rule on Authorization Request v0.1. If accepted, the next and
only lawful artifact is a separate persistence-specific Manifest Contract for
review. This instance must then be rebound to the frozen contract identity and
integrity before any stage authorization.
