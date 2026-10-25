# Swift build and test evidence (F round)

| file | content |
| --- | --- |
| `swift-test-narrow-admission.log` | narrowest relevant test: `ProductionInputAdmissionTests` (production input-admission gate) — 1 test, 0 failures |
| `swift-test-detached-entry.log` | the F-round identity suite `DetachedContinuationEntryTests` — **4 tests, 0 failures** |
| `swift-test-es-recovery-with-detached-entry.log` | the ES-recovery/admission set plus the new suite — **62 tests, 0 failures** |
| `swift-test-broad-es-recovery.attempt1.log` | first attempt at the ES-recovery/admission set — **26 failures kept verbatim** |
| `swift-test-broad-es-recovery.log` | same set after the test-side fix — 58 tests, 0 failures |
| `swift-test-full-target.attempt1.log` | whole package, first full run — 411 tests, 5 failures |
| `swift-test-full-target.attempt2.log` | after the bundle/staging fix — 411 tests, 2 failures |
| `swift-test-full-target.attempt3.log` | final state of the repaired pre-existing suites — 411 tests, 0 failures, 5 skipped |
| `swift-test-full-target.attempt4.log` | whole package after adding `DetachedContinuationEntryTests` — **415 tests, 0 failures, 5 skipped** |
| `../build/swift-build-all.log`, `../build/swift-build-products.log` | `swift build` of the production targets |

## What attempt1 showed

`DurableExecutionStateStoreTests` (8) and `ExecutionContinuityCoordinatorTests` (15)
passed. `NativeCarrierLifecycleTests` (2 of 10 failed),
`ProductionRuntimeFailureBoundaryTests` (10 assertion failures over 8 tests) and
`ProductionRuntimeInformationIntegrationTests` (14 of 16 failed) did not. Every failure
happened inside the production bridge before the behaviour under test was reached:

* 22 lines: `No such file or directory: …/simigo-admission-<UUID>/trust-forged-u1-settlement/trust-anchor.json`
* 2 lines: `TRUST_ANCHOR_MISSING: SIMIGO_SETTLEMENT_TRUST_ANCHOR`
* 3 lines: `XCTAssert` mismatches whose observed value was the same bridge error, e.g.
  `("modelExecutorUnavailable") is not equal to ("bridgeFailed(command: "execute", exitCode: 1, message: "TRUST_ANCHOR_MISSING…"))`

The full run (attempt1) then exposed two more pre-existing gaps:

* `IntegratedSimigoProofE2ETests`, `ControlledProductionPilotV1E2ETests`:
  `TRUST_ANCHOR_MISSING`, i.e. the same missing deployment trust root.
* `ProductionReadinessDeploymentPreparationTests` (3 cases):
  `Error Domain=NSCocoaErrorDomain Code=3840 "Unable to parse empty data."` — the staged
  deployment bundle copied `carrier_loop.py`, `real_palace_loop.py`, `db_is.py` but **not**
  `settlement_provenance.py`, which the E-round contract made a required bridge import. The
  bundled bridge died on `ImportError` and emitted no JSON at all.

None of these were introduced by the F round. Isolation proof for cause 1: running
`swift test --filter ProductionRuntimeInformationIntegrationTests` alone — with no other suite
able to touch the process environment — still produced 14 failures, all `TRUST_ANCHOR_MISSING`.

## What was changed (all test-side)

* `Tests/SimiGo2ExperimentalTests/SettlementTrustFixture.swift` (new) — provisions one fresh
  Ed25519 key pair per test process into a temporary directory **outside every Information
  Space database**, writes the two documents in the schemas the Python producer and the Swift
  verifier load, and exports `SIMIGO_SETTLEMENT_TRUST_ANCHOR` /
  `SIMIGO_SETTLEMENT_SIGNING_KEY`. It re-exports on every call, so a suite that overwrote the
  variable is re-pointed at the next `setUp`. It signs and verifies nothing itself.
* `NativeCarrierLifecycleTests`, `ProductionRuntimeFailureBoundaryTests`,
  `ProductionRuntimeInformationIntegrationTests`, `IntegratedSimigoProofE2ETests`,
  `ControlledProductionPilotV1E2ETests`, `ProductionReadinessDeploymentPreparationTests` —
  `setUpWithError` installs the fixture.
* `ProductionInputAdmissionTests` — clears its per-case fixture anchor export in `defer`,
  closing the leak that produced the dangling-path variant.
* `ProductionReadinessDeploymentPreparationTests`, `ControlledProductionPilotV1E2ETests` —
  the staged deployment bundle now carries `settlement_provenance.py`.

## The coverage gap the F round itself had to close

The task pack requires pure Swift production-entry tests for the new identity and cold start.
Before this round's last suite, `grep -rn taskExecutionID Tests/` returned nothing: the
per-instance identity API that lets a consumer own a DIFFERENT Execution State through the same
entry had **no test at all**, and neither of the two executables `Package.swift` added for this
round was exercised by the test target. `Tests/SimiGo2ExperimentalTests/DetachedContinuationEntryTests.swift`
(new, 4 tests, model-free) closes it:

* `testPerInstanceIdentityCreatesItsOwnColdStateFromInformationSpaceInput` — two
  `ProductionRuntimeInformationIntegration` instances with different `executionID` on one
  Information Space and two fresh state directories. The stub records the state the entry hands
  to the model: each run gets **its own identity at position 0**, each tokenizer call receives
  the admitted `inputText` **including the settled `TASK-U1` value**, and neither instance's
  durable state carries the other identity.
* `testPerInstanceIdentityStillRefusesBeforeTheModelWhenSettlementIsMissing` — under a
  per-instance identity the entry still refuses
  (`SETTLEMENT_NOT_ADMITTED`, `TASK-U1`) with 0 tokenizations and 0 model calls, and leaves both
  the database bytes and the state directory untouched.
* `testOrdinaryExecutableEntryAdmitsAndRefusesWithoutAnyModelWork` — spawns the built
  `SimiGoTaskRun --admission-probe` under an explicit `--execution-id` and checks the record:
  `ADMITTED` for a valid settlement / `ADMISSION_REFUSED` for a missing one, echo of the identity
  it was given, `model_loaded: false`, all counters 0, `database_unchanged: true`.
* `testDetachedDriverRefusesNonEmptyConsumerStateDirectory` — spawns the built
  `SimiGoDetachedDriver` with a pre-populated `u2-state` and asserts it exits 1 with
  `refusing to reuse state` **before** writing any lifecycle record or a `process-logs` directory.

These tests stop the run at the model boundary on purpose (the stub throws there), so they prove
identity, cold start, IS-sourced input and pre-model refusal; the settled-value *reuse* counts and
the no-recompute property of a completed run come from the real-model conditions W-A/W-B.

## What was deliberately NOT kept

While diagnosing the bundle gap, a production-side change was prototyped: validate in
`runBridge` that the modules the bridge imports exist in the bundle, so an incomplete
deployment fails closed with the missing path instead of returning unparseable empty output.
It was **reverted**: it is outside the F round's single core (detached continuation), and any
production edit would drift the delivered binary away from the one that produced the model
evidence. `Sources/SimiGo2Experimental/ProductionRuntimeInformationIntegration.swift` is
byte-identical to `../source/files/Sources__SimiGo2Experimental__ProductionRuntimeInformationIntegration.swift`,
and after all of this (including the final `swift build` logged in
`../build/swift-build-after-test-side-additions.log`)
`.build/debug/SimiGoTaskRun` is still `322c4855ae634e62fc178c9ff6e0733a1354ea90414f32291bf7fb33d29c3ffc`
and `.build/debug/SimiGoDetachedDriver` is still
`c6b4c469feaddb31eccdba70586c48f289dab331e2107b4d81f4bdf7bea03af4` — the hashes recorded in
`../build/delivered-binary-sha256.txt` for the run that produced the model evidence. The
un-fixed gap is reported as an open item instead.

## Scope of the claim

A green test run proves the tested entry points behave as asserted under a correctly
provisioned deployment. It does not prove semantic correctness of any settled model value, and
the 5 skipped tests remain unexecuted.
