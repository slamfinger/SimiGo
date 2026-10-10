# MLX Backend Identity Repair W1

> **Status:** LOCAL NON-GENERATION VALIDATION PASS / READY FOR MERGE REVIEW
> **Actual MLX smoke:** NOT AUTHORIZED / NOT EXECUTED
> **Date:** 2026-10-10

## Failure being repaired

Actual MLX Smoke V4 was consumed once and closed as
`MLX_SMOKE_FAIL / AUTHORIZED RUN CONSUMED / CLOSED`. Its recorded failure was
`noBoundRepresentation(PRODUCTION-REAL-PALACE)` at `model_execution`.
No model forward pass or generated token was produced.

Source inspection found split ownership of the representation backend:
`ActualMLXSmokeChild` created backend A for `MLXPrefixRecomputeExecutor`,
but `ProductionRuntimeInformationIntegration` was constructed without that
backend and therefore created backend B for its coordinator/runtime bindings.

## Bounded repair

1. Pass the exact same `backend` instance into the Integration initializer.
2. Extend the isolated executor stub so a regression test can observe whether
   the injected backend has the seeded representation at continuation time.
3. Add `testInjectedBackendReceivesSeedAndAdvancedRepresentation`, which
   checks that the seed binding is visible to the executor stub and that the
   final logical position is bound to the returned physical prefix.

No production carrier contract, frozen contract, PALACE snapshot, canonical
Information Space, D-002 artefact, or V4 result/evidence is changed by intent.
The V4 run remains consumed and closed; this repair does not authorize another
actual model call.

## Validation and next gate

The bounded non-generation validation was run locally in
`/Users/mr.simi/Documents/SimiGo-Lab/simigo2-experimental`:

- `ProductionRuntimeFailureBoundaryTests`, including the new backend identity
  test;
  `PASS / 8 tests / 0 failures` at 2026-10-10 23:54:51 local time.
- `swift build --product ActualMLXSmokeChild`;
  `PASS` at 2026-10-10 23:54 local time.

The rebuilt Child binary is bound by:

```text
ActualMLXSmokeChild SHA256 =
  fe234a59d88f825d784e0d5e0e6b4f285c9c589e0779e8440ef00f369e7e00de.
```

A local typo in the regression test's temporary database filename was corrected
before the final recorded run. The final run covered the corrected branch state.

Do not run `testActualMLXSmokeSingleRun`, create a new marker, reset the
consumed marker, or call the model. Any future real MLX attempt needs a separate
manifest/package and explicit Human authorization after this repair passes.

## Preserved boundaries

```text
Actual MLX Smoke V4 = MLX_SMOKE_FAIL / AUTHORIZED RUN CONSUMED / CLOSED
V4 retry / repair-run = FORBIDDEN
Runtime Validation V2 rerun = FORBIDDEN / CLOSED
canonical PALACE / Information Space mutation = FORBIDDEN
D-002 rerun / repair = FORBIDDEN
production deployment / traffic = NOT AUTHORIZED
Integrated SimiGo full production proof = NOT ESTABLISHED
```
