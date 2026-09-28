# BETA-RELEASE-SMOKE-1 — Release Suspend/Resume Lifecycle — 2026-09-29

## Verdict

```text
BETA-RELEASE-SMOKE-1 = PASS / AUDIT RECEIPT
BETA-AUDIT-3 = PASS (unchanged)
BETA-STORAGE-1 = PASS (unchanged)
```

## Defect

Release external smoke failed:

```text
LifecycleRaceTests.testGenerateSurvivesSuspendIfIdleHammeringAndResumeRoundtrip
error = notLoaded
```

The same race test passed in Debug, so the failure was not environment noise.

## Root cause

`generate()` released the lifecycle gate after `ensureLoaded()` and only later
registered the generated task in `activeRequestTasks`. During that async gap,
`suspendIfIdle()` saw no active request and could unload the model. Registration
then still succeeded because suspend leaves `isRunning == true`; the queued
generation subsequently observed a nil model container and returned
`notLoaded`.

## Fix

Request ownership now begins at admission, not after model load:

```text
pendingRequestIds insert
  → ensureLoaded / task creation
  → activeRequestTasks registration
  → pendingRequestIds remove
```

`suspendIfIdle()` treats both pending and active requests as busy. Stop clears
both sets. Admission-time failures still produce the existing failed lineage
record.

No per-token/per-step lock, generation-gate redesign, global lifecycle
serializer, Execution State abstraction change, or MLX backend change was
added.

## Regression test

```text
LifecycleRaceTests.testGenerateSurvivesSuspendIfIdleHammeringAndResumeRoundtrip
```

## Evidence

### Targeted race

```text
Debug
  PASS / RACE_WINDOW_HIT / suspendWins=2 / 55.781s

Release
  PASS / RACE_WINDOW_HIT / suspendWins=2 / 58.743s
```

### Full battery

```text
Executed 90 tests, with 8 tests skipped and 0 failures
Duration: 364.029s
```

Regression used temporary 256 GiB storage overrides to preserve the observed
disk baseline; production defaults remain 64 GiB / 16 GiB.

### Release external smoke

```text
BranchFork production API                         PASS 40.584s baseline; PASS in final battery
generation ↔ save/load/delete race battery        3/3 PASS
suspend/resume/generate Release race              PASS / RACE_WINDOW_HIT
PrefixPool daily-path E2E                         2/2 PASS
storage retention regression                      2/2 PASS

Selected Release smoke total
Executed 9 tests, with 0 failures
Duration: 143.352s
```

The Release test harness required `ENABLE_TESTABILITY=YES` and `-DDEBUG` to
compile the existing debug-only suspend timing seam. The production Release
artifact was rebuilt separately without test flags and passed:

```text
Release build  PASS
codesign       PASS
```

## Provenance

```text
base RC      f2794c9768ba534c03ac98520c6d6968cd5a46e2
branch       codex/beta-release-smoke-1
Package.resolved unchanged
mlx-swift    ef5f1b6bb24e27922189316362f3057c64261704
mlx-swift-lm fd5d1b4a8a5ad83e1d78617fecc817fa196a64fc
```
