# SimiGo v2.1.1 — Official Fork, Retention Scope & ZAI Cloud Backend

Date: 2026-10-15  
Build: 11  
Tag: `v2.1.1`  
Platform: Apple Silicon macOS 26.4+  
Asset: `SimiGo-v2.1.1.dmg`

> 2026-10-15 correction: the first published asset was built from a stale
> tree that omitted `ae16763` (replaceable ZAI cloud backend) and `82b57f6`
> (chat-completion cloud route guard). The asset was rebuilt from the
> authoritative tree and re-uploaded; the tag now points at the corrected
> commit.

## Highlights

### Replaceable ZAI cloud backend

The engine can now be swapped to a remote OpenAI-compatible cloud backend
(ZAI) — startup, settings, and both chat-completion routes are guarded, and
model selection carries the backend kind. Local MLX remains the default.

### Live branch fork switches to the official upstream API

`forkSessionBranch` now drives the official `ChatSession.fork()` (upstream
mlx-swift-lm #641, merged 2026-10-07): an in-process copy-on-write fork where
the child shares the parent's evaluated KV/draft cache arrays and copies only
on first write. This retires the v1 disk round-trip (saveCache → GB-scale
file copy → deserialize into a fresh instance).

- Fork is now zero-IO and zero-serialization (v1 paid 0.15s@58k serialization
  each way plus a full checkpoint-file copy).
- The official fork carries the conversation transcript **and** the token
  ledger, so the child is a first-class live session — attribution and reuse
  telemetry apply to it from turn one (v1's disk path produced a raw-cache
  restore whose attribution block was skipped entirely).
- Fork provenance (`forkPoint`) is stamped into the child's checkpoint
  metadata by its first successful turn, and travels with every later save —
  fork lineage is a permanent property of the branch, not a one-time event.
- Overwrite semantics ("选边提升": winner → fork back to main → DELETE the
  rest) are preserved; a stale target checkpoint is removed at fork time so a
  suspend in the fork→first-turn window can never restore pre-fork state.
- Cross-suspend durability is unchanged: the fork's in-memory product is
  marked checkpoint-dirty, so the existing suspend-retry path writes the
  child's durable pair at idle time even before its first turn.

### Retention scope: one-shot requests stop writing durable checkpoints

Sessions minted per HTTP request (`*-request:<uuid>`, e.g. `openai-request:…`
for stateless API clients) never participate in cross-request KV reuse by
design — their durable receipts had no possible future reader. They no longer
write branch checkpoints.

- Measured baseline (2026-10-14): 88 one-shot request checkpoints held
  **54.4 GB — 85% of the 64 GiB store** — reclaimed as dead weight.
- The content-addressed prefix pool is unaffected: shared prefixes exported
  from one-shot requests remain reusable assets for other sessions.

### Checkpoint byte budget 64 → 16 GiB

With one-shot sessions out of the writer set, the retained surface is the
working set of real sessions (baseline: 9 sessions ≈ 9.1 GB). The default
budget shrinks to 16 GiB; `SIMIGO_BRANCH_CHECKPOINT_MAX_BYTES` still
overrides. The first retention pass after upgrade evicts legacy dead weight
LRU-oldest-first down to the new ceiling (active keys protected).

### Vendor pin provenance

`mlx-swift-lm` @ `e520e605` = previous pin `fd5d1b4` + **exactly one commit**
(the official #641 cherry-pick; conflict resolutions limited to composing our
`rebuildAfterFailedRewind` flag with upstream's first-use copy branch, and
keeping our `loadPromptCacheSnapshot(url:materializeArrays:)` signature).
Zero smuggled engine changes; audited `pin..HEAD` before bumping.

## Verification

- Fresh-derivedDataPath Release build: PASS (build 11).
- Dependency resolution audited: checkout at `e520e60`, `fd5d1b4..HEAD`
  contains only the #641 commit.
- `BranchForkTests` updated to the new fork contract (fork point on the
  return value; on-disk meta asserted after the child's first turn).
  Hosted device-test rerun deferred to Xcode per standing policy — the fork
  isolation semantics it guards were pre-sealed by
  `testInMemoryForkCopyOwnership`.
- DMG `hdiutil verify` VALID; embedded app version 2.1.1 (11).
