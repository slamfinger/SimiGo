# Persistent SRS Representation Implementation Repair Authorization Package v1.1

> **Status:** REVISED DELIVERY FOR HUMAN REVIEW — REPAIR NOT AUTHORIZED
> **Date:** 2026-10-12
> **Version:** v1.1 (in-place revision of the same document)
> **Supersedes:** v1.0, returned as `REVISE_IMPLEMENTATION_REPAIR_AUTHORIZATION_PACKAGE_V1.0`
> **Revision scope:** authorization-scope consistency across sections 1, 8,
> and 12; R5 check stages aligned to Contract v1.8 section 13.1 (R17 vs R19);
> frozen ClassificationDescriptor field names; explicit invalid-key failure
> status; unmerged W13-W16 semantics; expanded closure state machine with
> bound statuses; table-driven R1 test coverage; repair start-commit binding
> **Basis ruling:** `REVISE_IMPLEMENTATION_COMPLETION_REVIEW`
> **Delivery ruling:** `AUTHORIZE_DRAFT_AND_DELIVER_IMPLEMENTATION_REPAIR_AUTHORIZATION_PACKAGE_V1.0`
> **Bound implementation commit:** `5764396497d115ce8b780dc7190815b849fea924`
> **Bound evidence commit:** `e0b16792dceeb924ef20739b0fac66c636c5e972`
> **Governing frozen rules:** Persistence Manifest Contract v1.8, I0 JSON
> Schema v1.6, Manifest Instance v2.2 — unchanged; no frozen rule may be
> modified to simplify a repair
> **Repair status:** NOT AUTHORIZED

## 1. Purpose and boundary

This package requests a scope-bound `IMPLEMENTATION_REPAIR` authorization for
the six blocking findings R1-R6 returned by the implementation completion
review. If granted, approval may authorize only the repairs of sections 2-7
(R1-R6), limited to the paths of section 8 and the verification sequence of
section 9. It does not authorize Fixture Preparation, Execution Batch,
independent validator execution, ES2 consumption, non-recompute attribution,
canonical PALACE or Information Space mutation, MLX, V6 rerun, or production
activity.

Repair attempts use the independent numbering of section 6 and do not reuse or
alter the historical Attempt 1-8 record of Package v1.1.

## 2. R1 — Sealed field label/type table

Finding: `SRSAttemptEvidence.verify` (V1) only checks that each field's type
number lies in 0x00-0x05; it does not enforce the required type per label, so
type/label mismatches can pass when digests are reconstructed accordingly.

Required exact label/type table:

```text
attempt_id                                    = UTF8_STRING      (0x02) fixed;
matrix_scenario                               = UTF8_STRING      (0x02) fixed;
batch_identity                                = UTF8_STRING      (0x02) fixed;
human_authorization_record                    = UTF8_STRING      (0x02) fixed;
fixture_digest                                = UTF8_STRING      (0x02) fixed;
completed_at_utc                              = UTF8_STRING      (0x02) fixed;
operation_outcome                             = UTF8_STRING      (0x02) fixed;
scenario_verdict                              = UTF8_STRING      (0x02) fixed;
implementation_runtime_environment_bindings   = JSON_STRUCTURE   (0x03) fixed;
observer_authorization_reference              = NULL (0x00) or UTF8_STRING (0x02);
start_stop_evidence                           = JSON_STRUCTURE   (0x03) fixed;
output_and_typed_failure_evidence             = NULL (0x00) or JSON_STRUCTURE (0x03);
base_evidence_digest                          = UTF8_STRING      (0x02) fixed;
completion_order_key                          = COMPLETION_ORDER_KEY_V1 (0x05) fixed;
```

Failure mode: a field carrying a known but wrong type must fail V1 with
`ATTEMPT_CANONICAL_ENCODING_MISMATCH` before any digest reconstruction.

Acceptance standard: the fixed encoding vector still passes V1-V5 unchanged;
known-but-wrong-type records are rejected at V1 with the exact typed status.

Required negative tests: a table-driven test iterating all 14 labels that
asserts every allowed type passes and every non-allowed type fails at V1 with
ATTEMPT_CANONICAL_ENCODING_MISMATCH, explicitly covering the two NULL-optional
fields (observer_authorization_reference, output_and_typed_failure_evidence)
and the two JSON fields
(implementation_runtime_environment_bindings, start_stop_evidence).

Completion evidence: test case names and outcomes for the negative classes,
plus the unchanged fixed-vector result.

## 3. R2 — ClassificationDescriptor and the PR-A41 shared classifier

Finding: the classifier accepts only logical key and payload bytes; the frozen
`ClassificationDescriptor` shape (UTF-8 logical-key tuple, 32-byte payload
digest, exact I1 bytes) is absent, and the collision test passes differing
payload bytes without constructing the controlled same-digest/different-I1
branch.

Required repairs:

```text
descriptor =
  identity_utf8: [UInt8];
  version_utf8:  [UInt8];
  payload_digest_bytes: 32 bytes (production constructor: recomputed SHA-256
    over the exact canonical payload bytes only);
  canonical_payload_i1_bytes: exact I1 bytes;

shared_classifier =
  one pure classification function over descriptors, called by both the
  production W3 path and the controlled test;

production_constructor =
  digest is always recomputed from payload_bytes; no caller-supplied digest;

synthetic_constructor =
  exists only in the test target; may state the same payload digest with
  different I1 bytes solely to exercise the collision branch; the production
  write path must have no reachable entry to it and must not accept a
  caller-supplied digest;

same-key/same-digest/different-I1 =>
  PERSISTENT_LOGICAL_KEY_CONFLICT, final, non-retriable.
```

Failure mode: a production path that could accept a caller-supplied digest, or
a synthetic descriptor reachable from production, violates PR-A41.

Acceptance standard: source/call-graph statement that the production W3 path
and the controlled test invoke the same classification symbol, that the
synthetic constructor is confined to the test target, and that the production
constructor cannot reach synthetic descriptors; no SHA-256 substitution and no
production-visible test flag.

Required negative tests: different-key collision at the content path
(identity mismatch), same-key/same-digest/different-I1 collision via real
descriptors (logical-key conflict), and equivalent-record passthrough.

Completion evidence: test outcomes plus the shared-symbol statement.

## 4. R3 — Signature key precheck before any filesystem side effect

Finding: `SRSWriter.write` accepts a caller-provided signing key without
verifying it against the frozen production anchor, and it creates the
`records/` directory before acquiring the lock; an invalid key can leave a
final record that later fails R25, poisoning the content-addressed path.

Required repairs:

```text
precheck =
  at function entry, before ANY filesystem mutation (including directory
  creation and lock acquisition), derive the caller key's public key and
  require exact equality with the frozen production anchor public key;

invalid_key =>
  immediate failure with status SIGNATURE_VERIFICATION_FAILED (the exact
  Contract v1.8 section 15 status for signer verification failure) and zero
  filesystem side effects;

ordering =
  precheck -> lock -> W2/W3 classification -> (only for NEW_RECORD)
  W7-W12 staging/refresh/rename -> W13-W15 reopen and verify R1-R29.
```

Failure mode: any staging file, directory entry, or final record created when
the key does not match the anchor.

Acceptance standard: an invalid-key write returns SIGNATURE_VERIFICATION_FAILED
and a directory-state snapshot assertion proves the working root is completely
unchanged — no `records/` or `staging/` entry created, modified, or removed.

Required negative tests: invalid-key write with pre-existing and non-existent
root states, asserting zero filesystem side effects.

Completion evidence: test outcomes and the directory-state assertions.

## 5. R4 — Persistence refresh sequence W9-W16

Finding: the writer uses `Data.write(to:)` and `FileManager.moveItem` without
file fsync or directory refresh, so W10 and W12 persistence guarantees are not
demonstrated.

Required sequence:

```text
W9  write staging file (same authorized root);
W10 fsync staging file; failure => remove staging attempt state and return
    PERSISTENCE_VERIFICATION_INDETERMINATE with no final record;
W11 atomic rename to records/<payload_digest_hex>.psrs;
W12 fsync the containing directory where the platform supports it;
    if the directory refresh fails, the persistence state is INDETERMINATE:
    the implementation must not claim the final file is absent, must not
    delete the immutable final record for rollback, and must fail closed;
W13 reopen the final path and execute R1-R28;
W14 execute the ordered logical-key uniqueness check R29;
W15 derive COMPLETE_VERIFIED only if W13 (R1-R28) and W14 (R29) both pass;
W16 release the lock only after the verdict is derived.
```

Each W13-W16 stage keeps its independent contract semantics from section 14.3;
they must not be merged into a single compound check.

Failure mode: claiming success (or absence) without refresh evidence, or
mutating a final record during rollback.

Acceptance standard: the refresh order is auditable in source; refresh failure
yields a typed indeterminate status; a refresh failure never deletes a final
record.

Required negative tests: refresh-failure handling is verified by an
injectable failure point in the test target (no production-visible flag).

Completion evidence: test outcomes and the source-order statement.

## 6. R5 — Closed schema for all nested objects

Finding: `asObj` performs no member whitelisting; nested unknown fields are
only caught indirectly at R21 instead of failing at R19.

Required repairs:

```text
checks are split exactly per Contract v1.8 section 13.1:

R17 structural stage:
  for each nested object class — logical_key, settled_relation_state,
  source_relation, dependency_set, dependency, result, provenance, lifecycle,
  freshness, freshness_requirement, resolution_policy, decision_core_binding,
  binding — decode enforces:
    exact required members — missing => UNKNOWN_SCHEMA_OR_FIELD;
    exact allowed member set — unknown => UNKNOWN_SCHEMA_OR_FIELD;
    JSON depth, duplicate members, and array limits per the existing strict
      parser (JSON_DEPTH_LIMIT_EXCEEDED, DUPLICATE_JSON_MEMBER,
      INTEGER_OVERFLOW_OR_RESOURCE_LIMIT);

R19 schema-validation stage:
  the frozen-schema type, enum, length, pattern, and const checks per class
  fire here with the contract statuses (SCHEMA_VALIDATION_FAILED,
  UNKNOWN_PAYLOAD_SCHEMA, ENCODING_IDENTITY_MISMATCH,
  DECISION_CORE_BINDING_MISMATCH; UTC shape stays a R19 pattern check while
  calendar validity remains R20);

unknown or missing nested members must never survive to R21; but no failure
may be reassigned to R19 merely for convenience — every check fires at its
contract-defined stage and returns its contract-defined status.
```

Failure mode: an unknown nested member surviving to R21.

Acceptance standard: nested unknown and missing members fail at R17 with
`UNKNOWN_SCHEMA_OR_FIELD`; type/enum/pattern violations fail at R19 with the
exact contract status; both are demonstrated per object class.

Required negative tests: at least one unknown-member injection per nested
class asserting the exact R17 status, and at least one type or enum violation
per class asserting the exact R19 status.

Completion evidence: test outcomes for all classes.

## 7. R6 — Evidence-derived eligibility, chain validity, and fixed budget

Finding: the projection ignores `priorEventID` chain validity;
`selectFinalAttempts` lacks candidate eligibility gates; `validateChain` lacks
invalidation projection; the budget cap is caller-adjustable and negative
counts pass.

Required repairs:

```text
eligibility =
  derived only from verified inputs: V1-V5 pass, scenario_verdict PASS,
  latest valid projection EXECUTED_ACTIVE, source batch ACTIVE or COMPLETE,
  binding identity match, and R29 uniqueness evidence present; callers cannot
  declare eligibility with a boolean flag;

projection =
  events form a valid append chain via prior_event_id; a broken chain is
  rejected instead of silently projected;

closure =
  phase 1 derives ELIGIBLE or INELIGIBLE per attempt only from verified
    evidence: the AttemptEvidenceRecord passes V1-V5; the matrix scenario is
    EXECUTION_REQUIRED; scenario_verdict is PASS; the latest valid projection
    is EXECUTED_ACTIVE and not EXCLUDED or FAILED; the source batch is ACTIVE
    or COMPLETE; the Human Authorization Record, fixture digest, implementation
    artifact, runtime artifact, environment identity, and observer
    authorization exactly match the frozen bindings; R29 uniqueness evidence
    exists and passes; and no unresolved authorization, fixture, schema,
    implementation, runtime, environment, observer, or evidence drift exists;
  phase 2 groups eligible attempts by EXECUTION_REQUIRED scenario, sorts each
    group ascending by immutable completion_order_key bytes, selects the last
    element, and registers exactly one candidate per scenario;
    duplicate registration in the set => CLOSURE_DUPLICATE_CANDIDATE;
  phase 2 matrix checks require: exactly one candidate for every
    EXECUTION_REQUIRED scenario with none missing or duplicated;
    implementation-test-required entries have PASS evidence; R29 evidence
    covers the candidate set with no unresolved logical-key, content-identity,
    duplicate-state, or concurrent-writer conflict; no candidate has
    unresolved drift;
  closure versioning: a valid commit's closure_version is exactly the current
    valid head version plus one, and prior_closure_head_version is exactly the
    current head; forks, duplicate versions, skipped versions, and
    out-of-chain commits => CLOSURE_CHAIN_FORK_REJECTED; only ACTIVE or
    INVALIDATED heads may be replaced — an ACTIVE head becomes SUPERSEDED, an
    INVALIDATED head remains INVALIDATED, and the valid replacement commit
    becomes ACTIVE;
  invalidation: an in-chain invalidation targets only the current head, only
    when its trigger affects a FINAL_ATTEMPT role selected by that head or a
    binding/evidence the head relies on, and only with a valid scope-bound
    Human Authorization Record; a non-head target =>
    CLOSURE_INVALIDATION_TARGET_NOT_HEAD and does not affect current closure;
  phase-2 rejection emits a ClosureRejectionRecord and must not emit a
    ClosureCommitRecord or FINAL_ATTEMPT roles; attempts retain their
    projected states; a rejected replacement does not change the head;
  history is immutable: SUPERSEDED and INVALIDATED versions are never
    rewritten back to ACTIVE.

budget =
  fixed valid count range 0...16; negative and oversized counts are rejected;
  the cap is not a caller-tunable parameter.
```

Failure mode: silently projecting from a broken event chain, admitting an
ineligible candidate, or executing a 17th attempt.

Acceptance standard: negative tests prove broken chains, ineligible
candidates, forked chains, non-head invalidations, and negative/oversized
budget counts are each rejected with exact statuses.

Completion evidence: test outcomes for every negative class.

## 8. Authorized repair scope

If Human grants the separate repair authorization record, the authorized work
is limited to:

```text
edit PersistentSRSRepresentation.swift;
edit PersistentSRSRepresentationTests.swift;
run the exact build command in section 9;
run the exact filtered test command in section 9;
record completion evidence per section 10.
```

All other paths remain unwritable. A separate, later request would be required
to revise the Implementation Completion Evidence document.

## 9. Repair attempt model and commands

Repair attempts are numbered `REPAIR_ATTEMPT_1`, `REPAIR_ATTEMPT_2`, ...,
independent of Package v1.1's historical Attempt 1-8. Each attempt authorizes
exactly one sequence:

```text
swift build --product SimiGo2Experimental
swift test --filter PersistentSRSRepresentationTests
```

both from `/Users/mr.simi/Documents/SimiGo-Lab/simigo2-experimental`, with the
test command permitted only after a successful build. Real process exit codes
must be recorded; no pipeline-terminal substitution, no retry, no parallel or
environment-modifying flags.

Failure handling: build failure consumes the repair attempt and stops the
sequence; test failure (compile or case) consumes the attempt and stops; each
failure requires a new scope-bound Human decision bound to fresh source
SHA-256 values.

Repair start binding: the repair Human Authorization Record must bind the
actual start commit by its full git_commit_object_id, the initial
artifact_content_sha256 of both repair paths, and the exact authorized commands
and working directory. If origin/main has advanced beyond the bound commit
before repair starts, the executor must stop and request a re-binding instead
of silently rebasing or re-binding.

## 10. Repair completion evidence requirements

A later repair completion review must receive:

```text
repair basis commits (57643964... and e0b16792...);
repair commit object id and direct parent commit id;
diff bounded to the two repair paths;
artifact content SHA256 for each changed file;
build and filtered test commands, real exit codes, and output integrity
  digests;
the complete test list with per-case outcomes;
negative-test outcomes for R1-R6 as specified above;
explicit statement that no forbidden path, dependency, or effect was used.
```

Log retrievability: the Attempt 8 raw build and test logs are not yet
permanently retrievable from the repository. Their embedding into a revised
completion evidence document (single path, single commit) is listed as a
separate future request requiring its own explicit authorization; no new
evidence root or marker may be created for this purpose.

## 11. Preserved governance state

```text
IMPLEMENTATION ATTEMPT 1-8 = HISTORICAL / PRESERVED;
IMPLEMENTATION SOURCE COMMIT = 5764396497d115ce8b780dc7190815b849fea924;
COMPLETION EVIDENCE COMMIT = e0b16792dceeb924ef20739b0fac66c636c5e972;
IMPLEMENTATION COMPLETE = NOT ESTABLISHED;
R1-R6 = BLOCKING / REPAIR PACKAGE REQUESTED;
INDEPENDENT JSON SCHEMA VALIDATOR = NOT AUTHORIZED / NOT RUN;
FIXTURE_PREPARATION = NOT AUTHORIZED;
EXECUTION_BATCH = NOT AUTHORIZED;
ES2 / NON-RECOMPUTE ATTRIBUTION = NOT AUTHORIZED;
CANONICAL PALACE / INFORMATION SPACE MUTATION = FORBIDDEN;
MLX / V6 / PRODUCTION = NOT AUTHORIZED.
```

## 12. Requested Human decision

Human is asked to return exactly one:

```text
AUTHORIZE_IMPLEMENTATION_REPAIR_V1
```

or

```text
REVISE_IMPLEMENTATION_REPAIR_AUTHORIZATION_PACKAGE_V1.0
```

or

```text
REJECT_IMPLEMENTATION_REPAIR_AUTHORIZATION_PACKAGE_V1.0
```

`AUTHORIZE_IMPLEMENTATION_REPAIR_V1` may authorize only the repairs of
sections 2-7 within the paths of section 8 and the sequence of section 9. The
first authorized verification execution consumes `REPAIR_ATTEMPT_1`.
