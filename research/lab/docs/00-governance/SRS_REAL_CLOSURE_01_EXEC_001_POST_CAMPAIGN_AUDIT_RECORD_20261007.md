# SRS-REAL-CLOSURE-01 — EXEC-001 Post-Campaign Audit Record

> **Status:** INVALID CAMPAIGN AUDIT CLOSED — AUTHORIZATION CONTRACT DEFECT
> IDENTIFIED
> **Date:** 2026-10-07
> **Scope:** post-campaign evidence audit only. This record does not authorize
> a rerun, corrected Request, fixture repair, IS mutation, observer execution,
> or any core-claim statement.

## 1. Audited object

```text
campaign_run_id = exec-001-edf7d4a;
execution_repository_commit = edf7d4adaac8b43bf6e63b64f177708268cf0428;
authorization_records_commit = c454687e41f7ba2b185353d1beef311551a83f6c;
evidence_commit = 6b511da6fba5e0d9222906df61f3c69e8b8a1c80;
request_commit = 1088a0c27f64fcbd59c207460d9b7576e6797e9e;
request_sha256 = b63c71aa1a0ac978a3e6deeae02a168dac5be9a599d553ccd4ba633f0664671f;
campaign_outcome = INVALID;
stop_code = ENVIRONMENT_CLOSED_UNIVERSE_MISMATCH;
```

## 2. Recomputed root cause

The measured and expected environment identities were recomputed using
Request v0.3's declared rule: remove `probe_identity`, canonicalize the
remaining object with sorted keys and compact separators, then SHA256.

```text
measured_environment_identity =
  ad2abb6809ead5a4d198f35d6f1b8a06624a803c6fc7e161dbb06f1f0838f15a;
expected_environment_identity =
  9048aed245e2f06bcf8682559da2a3c5e38aca67e3cc2c4fbcdbefd9425cc52a;
sole_differing_field = swiftc_version.

expected swiftc_version =
  "swift-driver version: 1.168.6 Apple Swift version 6.4
   (swiftlang-6.4.0.34.1 clang-2100.3.34.1)\nTarget:
   arm64-apple-macosx26.0";
measured swiftc_version =
  "Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)\nTarget:
   arm64-apple-macosx26.0".
```

The probe implementation executes `/usr/bin/swiftc --version`, captures
stdout with `text=True`, applies `.strip()`, and stores that value directly as
`swiftc_version`. The measured value is therefore consistent with the probe
implementation. The frozen expected binding instead used wording associated
with a different Swift driver report. Root cause is therefore:

```text
PRE-AUTHORIZATION ENVIRONMENT-BINDING INCONSISTENCY
```

not runtime environment drift.

## 3. Component classifications

```text
Campaign result = INVALID;
Semantic experiment result = NOT RUN;
Core hypothesis = NOT EVALUATED;
Fixture REVISION 002 = NOT DEFECTIVE / ACCEPTED / FROZEN;
T-IMPL-01 sources = NOT DEFECTIVE / VERIFIED;
Adapter runtime binary = VERIFIED MATCH at
  e88c996b9a64df10dd03f7622ffa8757551baf352908e4d7bf8704295eaffcc7;
Actual measured environment = CONSISTENT WITH PROBE IMPLEMENTATION;
Request v0.3 expected binding = INCONSISTENT WITH ITS OWN PROBE.
```

The INVALID verdict remains binding. The step-0 gate correctly prevented a
campaign whose pre-registered environment binding did not match its own
probe-generated measurement from entering materialization or ES₁.

## 4. Budget effect

```text
execution_campaign_budget = consumed by INVALID exec-001-edf7d4a;
IS_MUTATION budget = unconsumed;
observer_use_budget = unconsumed;
automatic_renewal = forbidden;
c454687 authorization records = consumed/not reusable for another campaign.
```

## 5. Next lawful object

The next lawful object is a Human decision whether to authorize a new
corrected EXECUTION Request. A future minimal correction, if separately
authorized, should preserve the probe implementation and align the expected
`swiftc_version` binding with the output semantics of that probe. This record
does not draft, approve, or authorize that corrected Request.

The old Request v0.3, EXECUTION SAR 001, IS_MUTATION SAR 001, and Observer
Authorization Record 001 cannot be reused for another campaign.

## 6. Continuing boundary

```text
EXECUTION = NOT AUTHORIZED;
IS_MUTATION = NOT AUTHORIZED;
Observer campaign = NOT AUTHORIZED;
fixture repair = NOT AUTHORIZED;
core claim ES1 -> IS(SRS) -> independent ES2 lawful reuse = NOT ESTABLISHED.
```

## 7. Record integrity

```text
record_integrity_binding = registered by the governing commit introducing
this audit record on main; later modification creates a new content address
and voids this audit record.
```
