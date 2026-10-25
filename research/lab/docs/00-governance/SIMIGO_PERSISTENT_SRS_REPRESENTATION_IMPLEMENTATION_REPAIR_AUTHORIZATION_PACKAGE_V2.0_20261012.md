# Persistent SRS Representation Implementation Repair Authorization Package v2.0

> **Status:** DELIVERED FOR HUMAN REVIEW — REPAIR NOT AUTHORIZED
> **Date:** 2026-10-12
> **Basis:** `REVISE_IMPLEMENTATION_COMPLETION_REVIEW` (residual R1–R6)
> **Delivery ruling:** `AUTHORIZE_DRAFT_AND_SUBMIT_IMPLEMENTATION_REPAIR_AUTHORIZATION_PACKAGE_V2.0`
> **Bound commits:** implementation `f1a6b876658e8cd7558b307a78e9da19b367ddc9`;
> evidence `fccd4b694848129d9caa219153689142c336d904`
> **Repair status:** NOT AUTHORIZED

## 1. Scope

Approval would authorize only the repairs of sections 2–8 within the two
repair paths (`PersistentSRSRepresentation.swift`,
`PersistentSRSRepresentationTests.swift`) and the Package v1.4 §9 command
sequence. Repair attempts continue the independent `REPAIR_ATTEMPT_n`
numbering (`REPAIR_ATTEMPT_6` next, only by explicit ruling); each attempt is
consumed by build or test failure; failures require re-binding fresh source
SHA-256 and a new Human decision.

## 2. R1 — real-byte V1 negative tests

Tests must mutate actually encoded sealed bytes and drive
`SRSAttemptEvidence.verify`: a known-but-disallowed type number must fail at
V1 with exactly `ATTEMPT_CANONICAL_ENCODING_MISMATCH`; an unsupported type
number must fail at V1 with exactly `UNSUPPORTED_CANONICAL_VALUE_TYPE`. The
assertions must prove failure occurs at V1, not later, and may not weaken
checks to pass.

## 3. R2 — unforgeable production descriptor

```text
production descriptor fields = immutable, read-only;
production constructor = computes SHA-256 over the exact I1 bytes itself and
  accepts no caller-supplied digest;
no public writable digest or I1 field may exist in the production module;
the synthetic collision branch is validated by the ONE pure classifier shared
  by production W3 and the test;
synthetic descriptor construction lives only in the test target (an internal
  read-only classification protocol in the production module plus a test-only
  synthetic type is an acceptable shape);
the production write path must be unreachable from any synthetic construction.
```

## 4. R3 — zero-side-effect tests and write-order repair

Tests must cover both root states (root absent; root pre-existing) with a
full recursive directory snapshot before/after (paths, object types, file
contents) proving zero side effects. Additionally, an implementation defect is
acknowledged and must be repaired: `SRSWriter.write` still creates `records/`
before acquiring the lock and completing W2/W3 classification. The required
order is: verify signing key → acquire lock → classify → create directories
only for the NEW_RECORD persistence path; the package must state how a lawful
write satisfies lock and directory creation when the root does not yet exist.

## 5. R4 — fail-closed refresh without production fault switches

`try? handle.synchronize()` must be replaced by explicit error handling: a
failed file flush returns `PERSISTENCE_VERIFICATION_INDETERMINATE` and must
not rename the staging file onto the final record. The mutable production
fault switches are removed; production `write` performs real fsync. Testing
injection may only use an internal seam parameter exercised by test callers
(default `nil` = real fsync); a file-flush failure produces no final record;
a directory-flush failure leaves the immutable final record untouched and
reports indeterminate.

## 6. R5 — per-class matrix and R27 end-to-end via real anchor-signed records

Each of the 13 nested object classes requires negative coverage for unknown
members (R17 `UNKNOWN_SCHEMA_OR_FIELD`), structural type violations (R17),
and schema-level enum/length/pattern/const violations (R19
`SCHEMA_VALIDATION_FAILED`), asserting the exact stage and status.

R27 must be validated through the complete Reader path using an existing,
provenance-verifiable production-anchor-signed record: mutate each envelope
binding field separately, recompute the envelope and physical frame digests,
and assert failure at exactly R27 with
`DECISION_CORE_BINDING_MISMATCH`. Random test keys must not impersonate the
production anchor; R25 must not be skipped or simulated; incomplete
end-to-end evidence must not be marked PASS. If no compliant signed record
can be obtained, this package records that fact as a test precondition
requiring a separate Human decision; it must not be declared
cryptographically impossible, and no new fixture may be created without
authorization.

## 7. R6 — evidence-derived eligibility and authorized invalidation

Eligibility and invalidation must derive from verifiable evidence flows:
projection from a validated event chain; batch state from actual batch
records; attempt verification and R29 from their verification result objects;
the Human Authorization Record must be a validated record bound to the
authorization scope and the current head; the invalidation trigger must have
a checkable relation to the head's selected FINAL_ATTEMPT or its bound
evidence; non-head targets return exactly `CLOSURE_INVALIDATION_TARGET_NOT_HEAD`
and do not affect current closure. Boolean self-declaration wrapped in typed
structures is not acceptable.

## 8. Recorded open issue — R14 stage ordering (new finding)

Contract v1.8 §13.1 lists R14 (envelope logical key vs I0 logical key) before
R15, but the implementation performs that comparison after R27 because it
depends on parsing the payload. This is a genuine conflict between the frozen
check order and an implementation dependency. It is NOT covered by this
repair authorization: no frozen rule may be modified and no source reordering
is authorized under this package. An independent Human ruling on the R14
ordering is requested as a separate decision.

## 9. Preserved governance boundaries

```text
REPAIR_ATTEMPT_1–5 = CONSUMED / history immutable;
REPAIR_ATTEMPT_6 = NOT AUTHORIZED (future ruling required);
R1–R6 = RESIDUAL BLOCKERS / new repair authorization requested;
R27 end-to-end = requires a provenance-verifiable production-anchor-signed
  record and complete Reader evidence;
R14 stage ordering = OPEN — separate Human ruling requested;
Contract v1.8 / I0 Schema v1.6 / Manifest Instance v2.2 = FROZEN;
IMPLEMENTATION COMPLETE = NOT ESTABLISHED;
Implementation repair / Build / Test / Independent Validator / Fixture /
  Execution Batch / ES2 / MLX / V6 / Production = NOT AUTHORIZED;
PALACE / Information Space mutation = FORBIDDEN.
```

## 10. Requested Human decision

```text
AUTHORIZE_IMPLEMENTATION_REPAIR_V2
```

or

```text
REVISE_IMPLEMENTATION_REPAIR_AUTHORIZATION_PACKAGE_V2.0
```

or

```text
REJECT_IMPLEMENTATION_REPAIR_AUTHORIZATION_PACKAGE_V2.0
```
