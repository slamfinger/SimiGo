# Controlled Production Pilot v1 PASS

> **Status:** AUTHORIZED CONTROLLED PRODUCTION PILOT V1 — PASS  
> **Date:** 2026-10-09  
> **Base:** `6259ffd9de7a4356d1da2e90dfc4b7db473644e0`  
> **Prerequisite tag:** `production-readiness-v1-pass`  
> **Accepted isolated proof commit:** `6a36c928c50021ec4c754eb4c8006306125bc35b`

## 1. Authorization boundary

This was an isolated controlled production pilot only. It did not authorize
production traffic, public release, canonical PALACE or Information Space
mutation, D-002 rerun/repair, or a claim of full Integrated SimiGo production
proof.

The pilot used a temporary isolated bundle, `/usr/bin/python3`, an isolated
byte-identical copy of the sealed PALACE snapshot, and an explicit versioned
validity policy:

```text
policy schema       = SIMIGO-INFO-VALIDITY-POLICY-V1;
policy version      = controlled-production-pilot-v1;
policy source       = CONTROLLED_PRODUCTION_PILOT_V1;
missing policy      = REJECT;
dependency propagation = ALL_TRANSITIVE;
default validity    = 2030-12-31T23:59:59Z.
```

## 2. Pilot result

```text
startup and initial compute = 9 COMPUTE;
restart and recovery        = 9 REUSE;
REAL-3 invalidation         = REAL-3/REAL-4 COMPUTE, 7 REUSE;
REAL-1 source revision      = REAL-1 COMPUTE, 8 REUSE;
blocked-state observability = BLOCKED state visible;
append-only rollback        = pilot-rollback-good ADVANCED;
stale validity              = BLOCKED_STALE_VALIDITY / no calculator / no settlement / no advance;
missing information         = BLOCKED_MISSING_INFORMATION;
malformed observation time  = bridge rejected / not committed;
corrupt persisted lifecycle = restore rejected;
carrier objects             = all verify.
```

Swift pilot:

```text
ControlledProductionPilotV1E2ETests
Executed 1 test, with 0 failures.
```

## 3. Evidence

```text
docs/02-evidence/controlled-production-pilot-20261009/
  CONTROLLED_PRODUCTION_PILOT_V1_E2E_RECORD.json
  SHA256 = b4fd58a582b097dc1c18bee2ab0150a074fa6878279c5f6112077d9c0c761bf9;

docs/02-evidence/controlled-production-pilot-20261009/
  CONTROLLED_PRODUCTION_PILOT_V1_MANIFEST.json
  SHA256 = bc9f98dc4f1d5de1cd2115d593ea194b7bfc7aac32f24e113548276c22586895.
```

Verifier:

```bash
python3 execution-information-loop/verify_controlled_production_pilot_v1.py
```

Result:

```text
PASS
```

## 4. Boundary

The pilot does not authorize production deployment or claim full Integrated
SimiGo production proof. Any production deployment or broader production claim
requires a separate Human-directed authorization and review.
