# SRS-VAL-01 AUTH-REQ-01 Phase 1 Boundary Directive v0.1

> **Status:** BOUNDARY DIRECTIVE V0.1 DELIVERED FOR HUMAN REVIEW
> **Date:** 2026-10-07
> **Directive basis:** Human direction after Run/Implementation Manifest Contract v1.0 acceptance at `eef3d24`
> **Frozen semantic basis:** SRS-VAL-01 Design v0.8 at `1170208`
> **Frozen governance basis:** Authorization Package v0.6 at `047b221`, accepted at `6089f0b`
> **Frozen boundary basis:** Implementation Boundary Audit v0.1 at `cb95c09`
> **Frozen manifest basis:** Run/Implementation Manifest Contract v1.0 at `f69a0e2`
> **Object opened:** `AUTH-REQ-01` pre-authorization boundary design
> **Requested stage set under design:** `{ IMPLEMENTATION }`
> **Implementation / fixture / execution:** NOT AUTHORIZED
> **IS mutation:** NOT AUTHORIZED
> **SimiGo code change:** NOT AUTHORIZED

## 1. Purpose

This directive fixes the shape of the next lawful object before any code is written.

```text
AUTH-REQ-01
Human Authorization Request v0.1
+
IMPLEMENTATION-only Filled Manifest Instance
```

It does not itself grant implementation, fixture preparation, execution, IS
mutation, or SimiGo code change. It defines the immutable authorization object
that must later be separately reviewed and ruled by Human.

## 2. Phase 1 requested stage set

```text
requested_stage_set = {
  IMPLEMENTATION
}
```

Explicitly excluded from AUTH-REQ-01 Phase 1:

```text
FIXTURE_PREPARATION;
EXECUTION;
IS_MUTATION.
```

No Stage Authorization Record may combine this IMPLEMENTATION request with any
other stage. No fixture, execution, or mutation permission may be derived from
an IMPLEMENTATION authorization.

## 3. Target and requested implementation scope

```text
target =
  T-IMPL-01 SRS-VAL Decision Core;

target_module =
  SettledRelationValidationCore;

candidate_source_placement =
  trackD-memory/Sources/SettledRelationValidationCore;

dependency_policy =
  Swift standard library only.

forbidden dependencies =
  MLX/LLM stack;
  CarrierInterface;
  CarrierSQLite;
  RelationCore;
  ExecutionCore;
  SimiGo2Experimental;
  filesystem access;
  network access;
  process execution;
  global mutable state;
  wall-clock/random/environment decision input.
```

The later AUTH-REQ-01 request must exact-bind a finite writable path set. It must
not use an open repository-wide wildcard. Candidate writable scope is limited to:

```text
trackD-memory/Sources/SettledRelationValidationCore/**;
minimal package/target registration changes required only for the new target.
```

Any change outside that scope is out of AUTH-REQ-01 Phase 1.

## 4. Authorization Request must be an immutable object

The Request cannot be prose or a mutable file path. Before Human review, it must
be content-bound as:

```text
authorization_request_identity;
authorization_request_content_address;
authorization_request_canonicalization_method_identity;
requested_stage_set = {
  IMPLEMENTATION
};
requested_scope;
requested_effect_set;
authorized_repository_revision;
authorized_writable_path_set;
target_module =
  SettledRelationValidationCore;
forbidden_path_set;
forbidden_dependency_set;
implementation_effect_set;
validity_boundary;
use_budget;
requester_identity;
request_destination_authority_chain;
request_integrity_binding.
```

Hard rules:

```text
Request A approved by Human must remain Request A.

Changing Request A after approval creates a new Request identity and voids the
prior approval.

A Stage Authorization Record must exact-bind:
  request_identity,
  request_content_address,
  request_integrity_binding,
  approved stage,
  approved scope.

A later reference by name, path, latest pointer, or natural-language summary is
invalid.
```

Failure:

```text
AUTHORIZATION_REQUEST_IDENTITY_DRIFT
AUTHORIZATION_REQUEST_TOCTOU
STAGE_AUTHORIZATION_REQUEST_BINDING_INVALID.
```

## 5. Exact approval chain

```text
Runner Trust Anchor
  → Authorization Authority Root
  → Human Ruling
  → exact approved Authorization Request
  → IMPLEMENTATION-only Stage Authorization Record
  → authorized implementation effect set
```

The Human Ruling must bind the Request identity and content address. The Stage
Authorization Record must bind both the Human Ruling and the exact Request
object. It may authorize only:

```text
IMPLEMENTATION
```

and only within the Request's finite writable/scope boundary.

## 6. Implementation artifact lifecycle

At Authorization Request creation, the result artifact does not exist. Therefore
Phase 1 must not contain:

```text
result_artifact_content_address;
executable artifact identity;
runtime artifact identity;
future/latest artifact placeholder.
```

The authorized IMPLEMENTATION work may produce:

```text
result_artifact_identity;
result_artifact_content_address;
result_artifact_integrity_binding.
```

Only after implementation completion and immutable artifact registration can a
later request exact-bind those artifacts for:

```text
FIXTURE_PREPARATION;
EXECUTION.
```

No Phase 1 authorization may pre-authorize those later stages through a
placeholder, future pointer, latest pointer, or estimated identity.

## 7. Implementation completion gate

At completion, the Implementation record must add:

```text
implementation_completion_record_identity;
implementation_completion_record_content_address;
authorized_request_identity;
authorized_request_content_address;
result_artifact_identity;
result_artifact_content_address;
result_artifact_integrity_binding;
changed_path_set;
forbidden_path_violation_count = 0;
forbidden_dependency_violation_count = 0;
scope_compliance_verdict;
completion_validity_boundary.
```

If implementation exceeds the authorized writable path set, dependency policy,
effect set, validity boundary, or use budget, the result is noncompliant and may
not become the exact artifact for any later stage.

## 8. Required adversarial pre-review

Before Human authorization, AUTH-REQ-01 must be attacked for:

```text
A-R1  Request A approval silently becoming Request B approval.
A-R2  IMPLEMENTATION authorization expanding into fixture/execution/mutation.
A-R3  mutable path, latest pointer, or placeholder used as authority.
A-R4  Human ruling bound to a summary rather than exact Request content.
A-R5  Stage Authorization Record referencing a stale or modified Request.
A-R6  package registration changes affecting unrelated targets.
A-R7  forbidden dependency or infrastructure import entering Decision Core.
A-R8  result artifact identity invented before authorized implementation.
A-R9  completion output escaping the authorized path/effect scope.
```

Each attack must map to a Request field, Stage Authorization Record field,
expected stop outcome, and evidence artifact.

## 9. Decision requested

```text
ACCEPT DIRECTIVE V0.1   open AUTH-REQ-01 Phase 1 design/audit with
                        requested_stage_set = { IMPLEMENTATION } and no code.

REVISE DIRECTIVE V0.1   return with boundary defects.

REJECT DIRECTIVE V0.1   do not proceed.
```

No implementation, fixture preparation, execution, IS mutation, or SimiGo code
change is authorized by this directive.
