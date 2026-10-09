# Bounded Production SimiGo Runtime Integration PASS

> **Status:** BOUNDED PRODUCTION RUNTIME INTEGRATION PASS / DEPLOYMENT NOT
> AUTHORIZED  
> **Date:** 2026-10-09  
> **Accepted isolated-loop base:** `bb09a55ef980ac4af3f1605ccf8de928abf6cc23`

## 1. Authorization

```text
isolated real-source closed loop      = ACCEPT;
bounded production runtime integration = AUTHORIZED;
production deployment                  = NOT AUTHORIZED;
Integrated SimiGo proof                = NOT ESTABLISHED;
canonical PALACE / IS mutation          = FORBIDDEN / NOT PERFORMED;
D-002 rerun or repair-run               = FORBIDDEN / NOT PERFORMED.
```

## 2. Integrated boundary

The real SimiGo `ExecutionContinuityCoordinator` remains the lifecycle
authority. `MLXExecutionStateBackend` and `MLXPrefixPayload` own the bounded
opaque representation. The accepted Python `RealPalaceSource` and D002
append-only carrier remain the Information Space path; they are exposed through
a JSON bridge and are not reimplemented.

The test uses the sealed D002 PALACE snapshot read-only, materializes one
collection/segment/seven-record structural closure into an isolated carrier, and
drives continuation with the real coordinator.

## 3. Verified behavior

```text
phase 1  initial real-source compute      = 9 COMPUTE / 0 REUSE;
phase 2  runtime restart + reattach       = 0 COMPUTE / 9 REUSE;
phase 3  explicit REAL-3 invalidation     = REAL-3/REAL-4 COMPUTE, 7 REUSE;
phase 4  isolated REAL-1 source revision  = REAL-1 COMPUTE, 8 REUSE;
invalid validity                         = BLOCKED_VALIDITY_FAILURE;
invalid demand advances Execution State  = false;
vector/full-text/model/cloud access       = false;
canonical PALACE mutation                = false;
canonical Information Space mutation      = false.
```

Swift test:

```text
ProductionRuntimeInformationIntegrationTests
Executed 2 tests, with 0 failures.
```

## 4. Evidence

```text
docs/02-evidence/production-runtime-integration-20261009/
  PRODUCTION_RUNTIME_INTEGRATION_E2E_RECORD.json
  SHA256 = b3291a23e24b93b27827954f8468557b2da15de4dce8562ee5603c6629ff6941;

docs/02-evidence/production-runtime-integration-20261009/
  PRODUCTION_RUNTIME_INTEGRATION_MANIFEST_V1.json
  SHA256 = 64fc9d1c1c5ef8f4264a1f3a2230d7f738c8b8b27e425a02d5bada01c003fc9f.
```

One-command verification:

```bash
python3 execution-information-loop/verify_production_runtime_integration.py
```

## 5. Boundary

This proves the authorized bounded runtime integration only. It does not prove
production deployment, PALACE equivalence, PALACE-supplied validity policy,
automatic background source discovery, or Integrated SimiGo.

## 6. V2 revision — stale-validity fail-closed gate

Review identified a production-path gap: an expired source validity window was
being recomputed and then settled without refreshed validity authorization. The
bounded bridge now preflights every required source before executing the
calculator or carrier settlement.

```text
source valid until = 2020-01-01T00:00:00Z;
evaluated at       = 2026-10-09T00:00:00Z;
verdict            = BLOCKED_STALE_VALIDITY;
blocked items      = 9;
calculator calls   = 0;
new settlements    = 0;
ES advancement     = false.
```

V2 evidence:

```text
docs/02-evidence/production-runtime-integration-20261009/
  PRODUCTION_RUNTIME_INTEGRATION_E2E_RECORD_V2.json
  SHA256 = 678e56fd883ba2f8a0fa95d4e6a090965d3b188f2a1811d52cc2f61c07acec89;

docs/02-evidence/production-runtime-integration-20261009/
  PRODUCTION_RUNTIME_INTEGRATION_MANIFEST_V2.json
  SHA256 = 973abbb02d2a30cae40f475f306f3c1944045cb382a51e9b5556632ed6b63d65.
```

The V1 evidence is retained unchanged. The verifier is bound by the current
review commit instead of embedding its own hash in the manifest.

## 7. V3 revision — undefined validity policy fail-closed

V2 covered expired windows, but a required source with no validity policy was
still allowed to enter the accepted carrier execution path. V3 closes that gap
before calculator execution.

```text
validity policy = undefined;
verdict         = BLOCKED_VALIDITY_POLICY_MISSING;
blocked items   = 9;
calculator      = not executed;
settlement      = not created;
ES advancement  = false.
```

V3 also retains expired and malformed gates:

```text
expired  = BLOCKED_STALE_VALIDITY;
malformed = BLOCKED_INVALID_VALIDITY.
```

V3 evidence:

```text
docs/02-evidence/production-runtime-integration-20261009/
  PRODUCTION_RUNTIME_INTEGRATION_E2E_RECORD_V3.json
  SHA256 = 033c61d48d25079ec135f617fb7fc4149282d0bc8eea7554955a7d502fb3ffa1;

docs/02-evidence/production-runtime-integration-20261009/
  PRODUCTION_RUNTIME_INTEGRATION_MANIFEST_V3.json
  SHA256 = 4b2a61f5b911891104a53ef3a8ede8da0ae388feb2e81f55aeaa1509abb331ac.
```

Swift regression:

```text
ProductionRuntimeInformationIntegrationTests
Executed 3 tests, with 0 failures.
```

## 8. V3 REV1 revision — duplicate-free stale set and verifier binding

Human review identified two V3 issues: residual stale-item append logic could
duplicate or falsely broaden the stale set, and the production verifier did not
independently bind the primary E2E evidence digest or V3 review commit.

V3 REV1 fixes both without rerunning the integration design:

```text
stale validity failure item IDs =
  REAL-COLLECTION, REAL-SEGMENT,
  REAL-1..REAL-7;
duplicate IDs                   = 0;
Swift tests                     = 3 PASS / 0 FAIL;
primary evidence SHA256         = d87a3b021fa68037daac493df2749f337c74ec662698026e1d89a96e09918bb8;
manifest SHA256                 = 83b5f1c9915e2f718da19068ffe692da6b262c33541e9875ee6278a52db2910b;
review anchor                   = annotated tag targeting the V3 REV1 review commit.
```

The verifier now checks primary evidence digest/result, exact stale item set,
manifest implementation hashes, sealed snapshot digest, Swift tests, worktree
cleanliness, and a non-circular annotated V3 REV1 review tag targeting HEAD.

V3 REV1 evidence:

```text
docs/02-evidence/production-runtime-integration-20261009/
  PRODUCTION_RUNTIME_INTEGRATION_E2E_RECORD_V3_REV1.json;

docs/02-evidence/production-runtime-integration-20261009/
  PRODUCTION_RUNTIME_INTEGRATION_MANIFEST_V3_REV1.json.
```

## 9. V3 REV2 revision — persisted lifecycle restore fail-closed

Human review found that a corrupted or unknown persisted `lifecycle` was being
converted to `.active` by `?? .active` and could therefore reattach as a live
execution. V3 REV2 removes that fail-open path.

```text
allowed recovery lifecycles = active, restored, attached;
unknown lifecycle           = REJECTED;
discarded lifecycle         = REJECTED;
default to active           = removed;
corrupt archive advancement = false;
new settlement              = false.
```

The Swift recovery archive is validated before attachment. The regression test
also compares the post-rejection audit against the pre-recovery baseline:

```text
Execution State dependency count = unchanged;
settlement dependency count      = unchanged;
current settlement states        = unchanged.
```

V3 REV2 evidence:

```text
docs/02-evidence/production-runtime-integration-20261009/
  PRODUCTION_RUNTIME_INTEGRATION_E2E_RECORD_V3_REV2.json
  SHA256 = a7319f871d08e964901fd7adaaed1969f5412de3e7c28ecf3e3fc5db00103c2b;

docs/02-evidence/production-runtime-integration-20261009/
  PRODUCTION_RUNTIME_INTEGRATION_MANIFEST_V3_REV2.json
  SHA256 = 222da75fc57cdbdf209d1fef83125e7b9448fbdd6e372d7ce3becade89201563.
```

Swift regression:

```text
ProductionRuntimeInformationIntegrationTests
Executed 4 tests, with 0 failures.
```
