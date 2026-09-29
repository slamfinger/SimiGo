# BETA-STORAGE-1 — Physical Representation Retention — 2026-09-29

## Gate

```text
BETA-AUDIT-3 lifecycle consistency: PASS (unchanged)
BETA-STORAGE-1 storage retention:   PASS / AUDIT RECEIPT
Beta release tag:                   still not created
UI cleanup surface:                 intentionally deferred
```

The issue is unbounded retention of physical representations—not the existence
of large, owned Execution State artifacts.

## Baseline observation

```text
~/.simigo/branch-checkpoints   120.06 GiB
~/.simigo/prefix-pool           33.72 GiB
~/.cache/huggingface           OUT OF SCOPE
```

## Ownership / retention policy

### Branch checkpoints

A durable branch checkpoint is a paired receipt:

```text
<execution-key>.safetensors
<execution-key>.meta.json
```

Ownership rules:

1. A parseable, complete pair is owned by its `storageKey`.
2. Keys currently registered as active sessions are always retained.
3. A missing counterpart or unusable sidecar is an orphan and is removed.
4. `deleteSessionBranch` remains the explicit owner-release path.
5. After the physical-byte ceiling is exceeded, the oldest valid non-active
   receipt is released first.

Default ceiling:

```text
64 GiB
SIMIGO_BRANCH_CHECKPOINT_MAX_BYTES overrides it.
```

### Prefix pool

The pool now enforces both budgets with shared LRU ordering:

```text
logical message-element budget: 200,000
physical-byte budget:            16 GiB
```

Overrides:

```text
SIMIGO_PREFIX_POOL=0
SIMIGO_PREFIX_POOL_MAX_BYTES=<bytes>
```

An artifact's physical size includes its `.safetensors` and JSON sidecar. When
either budget is exceeded, LRU eviction deletes the persisted artifact through
the existing Gate-D physical-use registry.

### Test boundary

Checkpoint tests now remove their isolated temporary stores with `defer`.
Runtime-level checkpoints continue to use the production retention policy.

## Implementation

```text
SimiGo fix branch       codex/beta-storage-1
SimiGo2Experimental     codex/beta-storage-1
backend primitive commit 669467d2165752d492f0795169799bb5cedbaf79
```

No UI was added.

## Regression receipts

### SimiGo full battery

```text
Executed 90 tests, with 8 tests skipped and 0 failures
Duration: 422.224s
```

Storage regression:

```text
testBranchCheckpointByteBudgetKeepsActiveAndDropsOldestOrphan PASS
testPrefixPoolPhysicalByteBudgetEvictsLRU                    PASS
```

BETA-AUDIT-3 race battery remained green:

```text
testGenerationGateBlocksSaveUntilGenerationCompletes        PASS
testGenerationGateBlocksLoadCommitUntilGenerationCompletes  PASS
testGenerationGateBlocksDeleteLifecycleUntilGenerationCompletes PASS
```

### Backend primitive selected battery

```text
ExecutionStatePrefixPoolTests       10/10 PASS
PrefixPoolSessionLifecycleTests      4/4 PASS
PrefixSnapshotStoreTests             7/7 PASS
Total                               21/21 PASS
```

## Dependency provenance

```text
SimiGo Package.resolved SHA256
4072b69845ca1684b363cf7ea965f696e19979a100eb015ab891a500cba94f3c

SimiGo2Experimental Package.resolved: unchanged versus branch base
mlx-swift:    ef5f1b6bb24e27922189316362f3057c64261704
mlx-swift-lm: fd5d1b4a8a5ad83e1d78617fecc817fa196a64fc
```

## Release receipt caveat

Regression runs used a temporary 256 GiB override so the audit did not destroy
the observed baseline. The default policy takes effect on the next production
runtime start without overrides: branch checkpoints converge to 64 GiB and the
prefix pool converges to 16 GiB as new exports occur.

## Delta receipt (2026-09-29, post-audit)

`b37d88f` perf(retention) — committed after this audit's registration — adds a
pre-budget gate to `BranchCheckpointRetention.enforce`: paired bytes are summed
via `fileSizeKey` and the metadata decode section is skipped entirely while the
total is at or under the byte budget. The eviction trigger remains strictly
`retainedBytes > byteBudget`, so the under-budget early return is
outcome-equivalent by construction. Accepted trade-off: pairs whose meta
exists but fails to decode are no longer cleaned while under budget (deferred
to the first over-budget sweep; the load path fails loudly on bad sidecars).
Behavior equivalence is locked by `StorageRetentionTests` (+3 differential
probes: garbage-meta pairs survive under budget and are removed over budget;
exact-budget boundary takes the pre-budget exit) and by the full-suite gate
(111 executed / 0 failures @5fa3d38). This receipt covers the delta; the
audit body above describes the pre-gate mechanism it measured.
