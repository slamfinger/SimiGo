# Materialization / Execution-State runtime handoff — 2026-10-14

## Identity

- Handoff ID: `HANDOFF-MATERIALIZATION-RUNTIME-20261014`
- Type: `PROCESS / ENGINEERING HANDOFF`
- Status: `ACTIVE / ENGINEERING PROGRESS RECORDED`
- Branch: `codex/materialization-delete-acquire-race`
- Feature HEAD: `31f50cf1bf3743b3c2804f363831cd854262d59e`
- `main` HEAD: `20c756430a0226b2ee6b844aff1303984b74b163`
- Working tree: clean
- Evidence root:
  `simigo2-experimental/docs/02-evidence/mlx-prefix-cache-probe/20261014-1b8b296e/`

## What changed

### 1. Materialization physical lifecycle

`PrefixSnapshotStore` now has generation-aware publication, deletion, and
reading. Key properties:

- explicit remove is generation-bound;
- pending / executing delete closes admission;
- publication failure restores the old snapshot pair;
- rollback failure writes a durable quarantine tombstone;
- durable quarantine survives restart and blocks rescan/admission;
- loads verify namespace, generation, token chain, and streaming SHA-256.

### 2. Cancellation and physical-boundary uncertainty

`MaterializationCoordinator` waiters are cancellation-responsive without
canceling shared work. Waiter timeout is waiter-local.

For Execution Continuity, a physical advance followed by cancellation or
durable-commit failure now marks `bindingUncertain`. It does not report success
or silently continue with logical / physical mismatch.

### 3. Durable identity

`DurableExecutionIdentityAllocator` provides idempotent operation tokens,
fsynced JSONL appends, process lock, generated or requested IDs, and fail-closed
corruption handling. `create` / `attach` / `fork` reserve IDs before logical
commit when a host injects the allocator.

### 4. Binding registry

`ExecutionBindingRegistry` now appends detached / superseded lifecycle
transitions instead of rewriting relation rows. Resolution uses the latest
event per execution generation.

### 5. Durable Execution State store — G-10 partial

`DurableExecutionStateStore` snapshots semantic handles, lifecycle audit, and
representation payloads. A host injects a payload codec; the store does not
interpret opaque payload semantics.

Coordinator restart restores handles, lifecycle audit, and representation
history. A fresh backend can restore persisted positions and verify their
physical prefix.

Engine bootstrap uses a per-baseline-UUID semantic snapshot. DCC-1 recovery
archives a stale live snapshot and intentionally rebuilds at the committed
baseline, preserving the Tier-1 recovery contract.

### 6. MLX ChatSession runtime wiring

`MLXPrefixCrossSessionCache` installs a verified lookup into
`ChatSession.crossSessionPrefixLookup`. The chain is:

```text
PrefixSnapshotStore
→ MLXPrefixSnapshotLoader
→ ChatSession.crossSessionPrefixLookup
→ fresh ChatSession warm prefill
```

### 7. Real-model system acceptance

Command shape:

```bash
.build/debug/simigo2ctl mlx-prefix-cache-probe MODEL \
  --prefix-tokens 32 --tokens 2 --root TEMP_ROOT
```

Model:
`mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit`,
snapshot `6e302ea604ad9ab206367e2c501d1571023e7b6d`.

Result at implementation HEAD `1b8b296e`:

```text
verdict = PASS
crossSessionHitObserved = true
hookCalls = 1
hookHits = 1
matchedTokenCount = 23
outputsMatch = true
```

Artifacts and hashes are bound in:

`simigo2-experimental/docs/02-evidence/mlx-prefix-cache-probe/20261014-1b8b296e/manifest.json`

## Verification

- Full XCTest at representation-persistence HEAD: `346 executed / 3 skipped / 0 failures`, three runs.
- SIGKILL identity test: failed-fork reservations survive process death.
- SIGKILL quarantine test: rollback tombstone blocks rescan/admission after restart.
- SIGKILL semantic-state test: handles, lifecycle, and representation payloads survive process death.
- Fresh-backend rehydration test: persisted position 0 and 1 restore physical prefixes `[1,2,3]` and `[1,2,3,4,5]`.
- Real-model acceptance: current HEAD PASS as above.

Logs referenced during the session included
`/tmp/representation-rehydrate-full-{1,2,3}.log`; repository evidence is the
durable source.

## Current state

- Feature and remote feature HEAD are aligned at `31f50cf1`.
- Remote `main` is merged at `20c756430`.
- Working tree is clean.
- G-7 has an implementation, not a governance closure.
- G-8 has an implementation, not a governance closure.
- G-5 core-store leakage is isolated behind an MLX adapter, not formally
  declared governance-closed.
- G-10 is substantially implemented for semantic state and representation
  history, but not declared complete.

## Next legal actions

1. Add GUI / long-lived host ownership for the MLX cross-session cache if the
   ChatSession path is promoted beyond CLI acceptance.
2. Add independent long-run / multi-process / chaos acceptance for semantic
   state and representation rehydration.
3. Review and register G-5 / G-8 / G-10 engineering outcomes separately.
4. Keep DCC-1 Tier-1 recovery semantics unchanged unless a new gate approves
   live-position recovery.
5. Preserve the existing real-model acceptance evidence; do not overwrite it
   with later ad-hoc runs.

## Forbidden actions

- Do not claim Materialization or Execution State is production-complete.
- Do not claim power-loss or storage-media durability; tests are process-crash
  evidence only.
- Do not merge Materialization correctness into a universal concurrency claim.
- Do not reopen the consumed Actual MLX Smoke V6 authorization.
- Do not rewrite historical evidence to resolve conflicts.
- Do not let a backend write semantic identity, lineage, position,
  continuation, or lifecycle.
- Do not freeze or declare governance closure without independent review.
