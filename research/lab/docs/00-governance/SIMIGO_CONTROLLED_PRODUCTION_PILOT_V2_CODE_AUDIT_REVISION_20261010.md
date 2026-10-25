# Controlled Production Pilot v2 — Code-Audit Revision

> **Status:** BOUNDED PILOT REVISION COMPLETE — local verification PASS.  
> **Date:** 2026-10-10  
> **Prior accepted pilot:** `4ecb8bfefeedebba9172ab8630d691af895d4db8`  
> **Base:** `6259ffd9de7a4356d1da2e90dfc4b7db473644e0`  
> **Production deployment:** NOT AUTHORIZED / NOT PERFORMED.

## 1. Revision scope

This revision answers the code-level pilot audit only. It does not reopen
D-001/D-002, mutate canonical PALACE or canonical Information Space, rerun a
D-002 campaign, authorize production traffic, or claim full Integrated SimiGo
production proof.

## 2. Closed findings

```text
settlement + durable ES intent   = one carrier transaction;
runtime application intent       = PENDING_SWIFT recorded in ES object;
transitive validity preflight    = complete dependency closure before compute;
missing validity                 = BLOCKED_MISSING_VALIDITY;
stale/malformed validity         = BLOCKED_* before calculator/settlement;
blocked continuation             = real BLOCKED ES appended with prior state;
validity policy identity         = required version/source; bound to settlement;
source revision policy retention = prior policy is retained;
Swift launch fallback            = removed; system Python is explicit;
stale and malformed side effects = covered by executable pilot test;
verifier evidence binding        = primary evidence SHA256 checked;
verifier dependency set          = carrier and readiness dependencies included.
```

The prior Python bridge no longer creates a second post-settlement ES record.
`CarrierInformationLoop.execute_demand()` records the durable ES transition in
the same SQLite transaction as settlements; blocked results roll back partial
writes and append a separate BLOCKED state with the prior lawful state.

## 3. Verification

```text
python compile                    = PASS;
carrier selftest                  = PASS / 17 checks;
ControlledProductionPilotV1E2ETests = PASS / 1 test / 0 failures;
ProductionRuntimeInformationIntegrationTests = PASS / 4 tests / 0 failures;
ProductionReadinessDeploymentPreparationTests = PASS / 4 tests / 0 failures;
pilot verifier                    = PASS
```

## 4. Evidence

```text
docs/02-evidence/controlled-production-pilot-20261009/
  CONTROLLED_PRODUCTION_PILOT_V2_E2E_RECORD.json
  SHA256 = 055d6445696aaab8513eb1971e922b534fdf5b9178bba7d23d273b540e5f0726;

docs/02-evidence/controlled-production-pilot-20261009/
  CONTROLLED_PRODUCTION_PILOT_V2_MANIFEST.json
  SHA256 = 0a30143a564f845c4bad24764cdc60718c70dd258c1745568ecce9f5dfb077b3.
```

## 5. Boundary

The result is an isolated controlled pilot revision PASS only. It does not
establish production deployment readiness, PALACE equivalence, full Integrated
SimiGo production proof, or authority to deploy. These require separate
Human-directed review.
