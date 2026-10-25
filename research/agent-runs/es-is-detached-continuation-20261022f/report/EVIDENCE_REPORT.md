# F round evidence report — Detached Continuation across a real process / Execution-State boundary

* Experiment id: `ES_IS_DETACHED_CONTINUATION_20261022F`
* Run root: `~/SimiGo-Agent-Runs/es-is-detached-continuation-20261022f/`
* Executed: 2026-10-22, model conditions 07:53:22Z – 07:54:58Z
* Machine: Apple-silicon MacBook, macOS, MLX, no model weights copied
* Model: `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit`, snapshot revision
  `6e302ea604ad9ab206367e2c501d1571023e7b6d`
  (tokenizer digest `aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4`)
* Delivered binaries that produced every model condition below
  (`build/delivered-binary-sha256.txt`, re-verified after the last source edit and again after
  the final `swift build` of the closing pass):
  * `SimiGoTaskRun` `322c4855ae634e62fc178c9ff6e0733a1354ea90414f32291bf7fb33d29c3ffc`
  * `SimiGoDetachedDriver` `c6b4c469feaddb31eccdba70586c48f289dab331e2107b4d81f4bdf7bea03af4`
* Machine-readable evidence: `summary.json`
  (sha256 `668179bd22e28f3dff6483e1dfd3d2ecbe142cf477c60a3ed50e79589b2fd656`),
  pack validator `manifests/acceptance.json` → `result: PASS`, `errors: []`
* Code-path audit (who really holds the model context and the cache, entry call sites, ES/IS
  write and read points, key and anchor locations): `report/CODE_PATH_AUDIT.md`
* F-round-only code diffs for all 15 touched files, each pre-F reconstruction hash-checked against
  the pre-F snapshot: `source/f-round-diffs/` (§2.6)

## 1. What was implemented (native, not scripted)

| file | role |
| --- | --- |
| `Sources/SimiGoDetachedDriver/main.swift` (new) | owns the process boundary: creates the two state directories, refuses a non-empty consumer state, runs the U1 producer, `waitUntilExit()`, only then starts the consumer; records PIDs, timestamps, directory manifests, model-call counters and 14 native checks into `lifecycle.json` |
| `Sources/SimiGoTaskRun/main.swift` (new) | one ordinary production `continueTask` per process against a real MLX model; emits per-step evidence JSON; also supports a zero-model `--admission-probe` |
| `Sources/SimiGo2Experimental/ProductionRuntimeInformationIntegration.swift` | per-instance execution identity: static default `executionID` kept, new `taskExecutionID` is what the instance advances, so a consumer can own a DIFFERENT Execution State through the same production entry instead of reattaching the producer's |
| `Sources/SimiGo2Experimental/SettlementProvenanceVerification.swift` | Swift-side detached Ed25519 verification of a dependency settlement against the deployment trust anchor; its evidence record now carries `verified: true` explicitly |
| `scripts/ordinary_task/run_phase_f.py` (new) | fixture preparation, driver invocation, control mutation on copies, evidence aggregation; never builds a model input and never supplies a settled value |
| `Tests/SimiGo2ExperimentalTests/DetachedContinuationEntryTests.swift` (new) | 4 model-free production-entry tests for this round's identity API: per-instance cold Execution State, IS-sourced model input, pre-model refusal, driver refusal on a non-empty consumer state directory |

Recompute semantics in `carrier_loop` were not changed; the consumer reuses the settled U1
through the existing entry path.

## 2. Observed facts

### 2.1 Real process / Execution-State boundary (W-A, W-B — both OBSERVED)

| | W-A | W-B |
| --- | --- | --- |
| producer PID → exit | 81312, 07:53:22.528Z → 07:53:50.659Z, exit 0 | 83780, 07:54:11.710Z → 07:54:37.528Z, exit 0 |
| consumer PID → exit | 82708, 07:53:50.664Z → 07:54:11.642Z, exit 0 | 83931, 07:54:37.530Z → 07:54:58.530Z, exit 0 |
| process-instance id stamped by the runner (independent of ES id and PID) | producer `0dd48cdf-9e50-4dfe-badc-29ad2f607cdc` → consumer `a14fd7ce-f72c-4657-9d4f-9de4f40ec9a1` | producer `11afaf6c-265a-4c7f-8a17-22e6fd144b0f` → consumer `c61da445-af70-40ac-8c9a-f0ecbcd9c8a9` |
| gap producer-exit → consumer-start | 5 ms | 2 ms |
| Execution State ids | `F-WORLD-A-PRODUCER` → `F-WORLD-A-CONSUMER` | `F-WORLD-B-PRODUCER` → `F-WORLD-B-CONSUMER` |
| consumer state dir before start | empty (manifest `{}`) | empty (manifest `{}`) |
| consumer position | created, advanced from 0 → 1 | created, advanced from 0 → 1 |
| U1 settled value | `SECRET=45d378e08713c693` | `SECRET=3875e4ff967ae0f3` |
| U2 settled value | `ANSWER=45d378e08713c693-ade5` | `ANSWER=3875e4ff967ae0f3-418b` |
| U1 settlement object | `b49601d57f230b9d…27f48714` | `df82c8976cf14f24…fea7330d0` |
| U1 signature object | `19227d484d9ea4d5…50696cc7` | `c73e06836e21b16f…ad6043ac` |
| model calls | U1: 1 generate; U2: 1 generate, U1 recomputes 0 | same shape |
| per-item actions the Runtime recorded in the consumer process | `TASK-SOURCE` REUSE, `TASK-U1` REUSE, `TASK-U2` COMPUTE | `TASK-SOURCE` REUSE, `TASK-U1` REUSE, `TASK-U2` COMPUTE |
| model load of the same snapshot in each process (no weights copied) | producer 3.213 s, consumer 2.605 s | producer 2.564 s, consumer 2.568 s |
| whole-process duration | producer 25.970 s, consumer 20.175 s | producer 25.245 s, consumer 20.584 s |
| driver checks | 14 / 14 true | 14 / 14 true |
| runner checks | **19 / 19 true** | **19 / 19 true** |

Each world's U2 template is byte-identical across worlds (`u2_template_sha256` equal in
`summary.json`) and contains no nonce; the value the model had to carry is the first 16 hex
characters of that world's runtime-generated 128-bit nonce, so the two worlds' answers differ
and no single canned answer can serve both. `output_matches_world_settlement` is true in both
worlds: the printed line equals the value bound into that world's own settlement.

The `cost` block of each positive condition (new in the final aggregation pass) is what keeps the
reuse claim honest: the consumer is a second OS process that pays its own model load (2.6 s) and
performs one real 64-token generation for U2 (20 s). What it does not do is recompute U1 — the
Runtime's own action list says REUSE for `TASK-U1`, `computed_item_ids` is `["TASK-U2"]`, and the
snapshot path plus revision is identical between the two processes, so the same existing snapshot
was loaded twice rather than copied or re-materialised.

### 2.2 Negative controls (N1, N2, N3 — all OBSERVED, all refused before any model work)

| condition | refusal stage / reason | tokenize | generate | db before = after | state before = after |
| --- | --- | --- | --- | --- | --- |
| N1 missing settlement | `SETTLEMENT_NOT_ADMITTED` / `MISSING_OR_SUPERSEDED_SETTLEMENT` | 0 | 0 | yes | yes |
| N2 byte-invalid object | `SETTLEMENT_OBJECT_UNREADABLE` / `ObjectByteMismatch: 5431f907e1bdfa64…cd8125b3` | 0 | 0 | yes | yes |
| N3 dependency mismatch | `INPUT_BINDING_DEPENDENCY_NOT_DECLARED` / "placeholder {secret} requires TASK-U1, which the current task item no longer declares" | 0 | 0 | yes | yes |

Each control is a copy of a genuine settled baseline database (`controls/control-base`), mutated
by SQL only; the mutation diff is recorded in `controls/<case>/mutation.json`. N3's recorded
differences are `u2_declared_dependencies` and `u2_item_revision_count` (the item got a new
revision whose dependency list drops TASK-U1), not a cosmetic field.

### 2.3 Isolation audit (N4 — OBSERVED, audit only, no model)

* U2 base template and cold seed contain no nonce in either world.
* Scanning the disallowed surfaces (`u1-state`, `u2-state`, `process-logs`, `logs`,
  evidence files, `lifecycle.json`, `carrier.sqlite`) for the other world's nonce and secret:
  0 violations in both worlds.
* The consumer state directory was empty before the consumer started, in both worlds.
* The only places the world nonce appears are that world's own IS source payload (which the model
  reads as task text) and its evidence files.

### 2.4 Build, tests, guards

* `swift build` (production targets): `Build complete!`, exit 0 —
  `build/swift-build-all.log`, `build/swift-build-products.log`, and re-run after every
  test-side addition as `build/swift-build-after-test-side-additions.log`.
* Narrowest relevant test: `ProductionInputAdmissionTests` — 1 test, 0 failures.
* F-round identity suite `DetachedContinuationEntryTests` — 4 tests, 0 failures
  (`tests/swift-test-detached-entry.log`). Before it was written, nothing in `Tests/` referenced
  the per-instance `taskExecutionID` API at all; that gap is recorded in `tests/README.md`.
* ES-recovery / admission set (`DurableExecutionStateStoreTests`,
  `ExecutionContinuityCoordinatorTests`, `NativeCarrierLifecycleTests`,
  `ProductionInputAdmissionTests`, `ProductionRuntimeFailureBoundaryTests`,
  `ProductionRuntimeInformationIntegrationTests`): 58 tests, 0 failures
  (`tests/swift-test-broad-es-recovery.log`); the same set plus `DetachedContinuationEntryTests`
  is **62 tests, 0 failures** (`tests/swift-test-es-recovery-with-detached-entry.log`). The first
  attempt at this set produced **26 failures**, kept verbatim in
  `tests/swift-test-broad-es-recovery.attempt1.log`; cause and fix in `tests/README.md`.
* Whole package: **415 tests, 0 failures, 5 skipped**
  (`tests/swift-test-full-target.attempt4.log`; attempts 1–3 with 5, 2 and 0 failures kept,
  attempt 3 being the state before this round's new suite).
* Historical artifact guard (`artifact_guard.py verify`): **PASS, 0 issues** — A–E evidence roots
  unchanged.
* Workspace guard (`workspace_guard.py verify`): **PASS**, `head_unchanged: true`,
  `branch_unchanged: true`, `staged_diff_unchanged: true`, 15 changed files, all inside the
  declared allow-list (6 production/script files + 9 test files). Nothing was staged, committed
  or pushed.
* Evidence schema validator: `result: PASS`, `errors: []`, condition ids
  `N1, N2, N3, N4, W-A, W-B` (`manifests/acceptance.json`).
* Final aggregation-only pass (after the test suite and the diff set): the runner's
  `positive_condition` was extended to copy fields that were already present in the two per-process
  records but had been dropped by the aggregator — the Runtime's per-item action list, the
  observed `computed_item_ids` / `reused_item_ids`, the measured model-load and wall-clock cost,
  and two new checks derived from them. No condition was re-executed, no model was loaded, no
  Swift source changed, so both delivered binaries still hash-equal
  `build/delivered-binary-sha256.txt`. Log: `logs/summarize-only.aggregation-refresh.log`;
  `summary.json` now carries **19/19** runner checks for W-A and W-B.

### 2.5 What the code-path audit adds (re-verified in the closing pass)

The ordinary production path this experiment runs forwards through MLX with **no KV cache at all**
(`MLXPrefixRecomputeExecutor.swift:155`, `context.model(running, cache: nil)`, re-feeding the whole
token list each step at `:161-162`); the per-layer `KVCacheSimple` owners exist only on the G3 arm
path (`:431`), which this round does not use. So the thing a detached consumer could inherit is the
persisted **token prefix** (`MLXExecutionStateBackend.prefixes`, `MLXExecutionStateBackend.swift:30`,
plus its durable form in the state directory), not an MLX KV block. The audit and this measurement
are why the release evidence is labelled `PROCESS_ADDRESS_SPACE_DESTROYED_ONLY`: inside a process
there is no cache object to release, and across processes the only observation available is exit.

### 2.6 The actual code difference, isolated to this round (`source/f-round-diffs/`)

The acceptance standard for this task pack is the real code diff, so the first diff set was
checked against it and did not meet it: `git diff` cannot describe untracked files, which left
the native driver, the new test suite, the trust fixture and the runner with **no diff at all**,
and left `source/diff-taskrun.patch` at **0 bytes** while its own README described it as the diff
of `SimiGoTaskRun/main.swift` (that file is untracked too; the empty artifact is disclosed rather
than quietly replaced-in-place-only: it now contains the reconstructed diff, and the 0-byte state
is what `git diff` still produces for it).

`source/f-round-diffs/` closes this. For each of the 15 touched files the pre-F content was
reconstructed from independent earlier-round records (HEAD + the E-round tracked diff, the D-round
worktree diff, the E-round `untracked-current` copies, or the E-round creation hunk) and accepted
**only when its SHA-256 equalled the `before` hash in `manifests/workspace-verify.json`** — the
snapshot taken before any F-round edit. Result: 11 hash-verified F-round-only diffs, 4
full-content diffs for files this round created, 0 files unreconstructed; the reconstructed pre-F
bytes ship in `before/` with a manifest and `SHA256SUMS` (29 entries, all verified), so every
patch is re-derivable. The manifest also re-confirms all 15 worktree files still hash-equal the
guard's `after` values, and no production source was touched to build these diffs, so
`build/delivered-binary-sha256.txt` still matches both delivered binaries exactly.

The single most important line of that diff set is the whole F-round library change, now visible
on its own without earlier rounds' noise: `ProductionRuntimeInformationIntegration` keeps the
static `executionID` as a default and adds a per-instance `taskExecutionID` that every
`runtime.handle` / `settlementCheckpoint` / `create` / `rebind` site now uses — which is what makes
a detached consumer a new Execution State rather than the same logical state reattached under a
new PID.

After these documentation and diff artifacts were added, the two guards and the evidence validator
were run a second time without rebuilding or re-executing anything; their fresh manifests are in
`manifests/closing-diff-pass/` and read `workspace guard PASS (15 changed files, 0 issues,
head/branch/staged unchanged)`, `artifact guard PASS (0 issues)`, `evidence PASS (errors: [])`.
The diff set itself was then regenerated once more from the post-aggregation runner, so
`source/files/`, `source/f-round-diffs/` and `manifests/workspace-verify.json` all describe the
same worktree bytes.

## 3. Inferences (supported, but not directly observed)

1. The consumer's model input for U2 is *materialized from the verified U1 settlement*, because
   the only channel into `next_input_template` is the binding resolver, the consumer state
   directory started empty, the cold seed carries no world value, and `actual_input_sha256`
   matches the template with that world's settled secret substituted.
2. The old execution context is gone as far as the OS is concerned: the producer process exited
   with code 0 and was reaped before the consumer was spawned, so its address space (including any
   MLX/KV allocation) was destroyed by the OS rather than released cooperatively.
3. The refusal path is genuinely pre-model, not merely pre-generation: tokenize counters are 0 as
   well as generation counters, and the database and state digests are unchanged across the
   refusal.
4. Reusing a settled U1 is the ordinary production behavior, not a special-cased branch: the same
   `continueTask` entry serves the producer (which computes U1) and the consumer (which reuses it),
   and the recompute policy in `carrier_loop` was untouched.

## 4. Claim limits — what this evidence does NOT support

* **No observed MLX/KV deallocation.** Release is evidenced only by full process exit plus an
  empty consumer state directory. Nothing in this run measured `MLXPrefixPayload` lifetime,
  cache eviction, or memory high-water marks. §2.5 states the stronger, checked fact: the tested
  path never installs an MLX KV cache, so no KV deallocation could have been observed here even
  with instrumentation.
* **"Signature verified" ≠ "value semantically correct."** Ed25519 verification proves provenance
  against the deployment anchor, not that the model's answer is right. The causal linkage in this
  fixture is proven by per-world nonce divergence, which is a property of the fixture, not a
  general correctness oracle.
* **Copy target was reduced from 32 to 16 hex characters.** A 4-bit 30B model dropped one
  character of a 32-hex transcription in the preserved aborted attempt
  `attempts/aborted-20261022-073805Z` — a real model error, recorded as such. The 128-bit world
  nonce still drives the payload; only the transcribed substring is shorter, so worlds remain
  distinguishable and the template remains nonce-free.
* **U2 output text is not a single line.** The model emitted the answer line and then kept going
  (repeating session text). Settlement takes the first regex match; the contract did not force an
  end-of-turn stop token. Any claim about "clean one-line answers" would be overstated.
* **One generation per condition, no repeats.** These are single observations, not statistics. No
  variance, no seed sweep, no significance claim.
* **Only the tested ordinary entry and this fixture are covered.** No claim about other entries,
  other tasks, other models, or concurrency.
* **No store-wide anti-rollback.** Per the round's scope, the boundary stays at first-tier trust:
  an out-of-band anchor plus admission verification. Rewriting or replacing a whole Information
  Space is not defended here.
* **Consumer holds the signing key by design.** The aborted attempt
  `attempts/aborted-20261022-073059Z` proved that a consumer forbidden from signing cannot settle
  its own U2 (`SIGNING_KEY_MISSING` after a genuine U1 settlement). Anti-forgery therefore rests on
  the anchor and admission verification (N2), and the "did not re-mint a dependency" property is
  proven by object-address equality (`consumer_did_not_remint_u1_object`), not by withholding keys.
* **The new entry tests stop at the model boundary.** `DetachedContinuationEntryTests` uses a
  stub that records the identity, position and input text the production entry hands to the
  model and then throws there, so no settlement is written by those tests. They cover identity,
  cold start, IS-sourced input and pre-model refusal only; every reuse / no-recompute number in
  §2.1 comes from the real-model runs.
* **Harness reads are zero by construction, not by measurement of every possible channel.** The
  runner only reads persisted evidence after the fact; the model inputs were built inside the
  production path.
* **`prefix_replay_tokens = 0` and `old_checkpoint_reads = 0` are structural, not counters of an
  attempted replay.** The consumer process builds a fresh `MLXExecutionStateBackend` over an
  empty state directory, so there is no bound prefix and no checkpoint to read from; the numbers
  record that absence. What the run does measure is the consumer's own created@0 lifecycle record,
  `tokenize_seed_calls = 1` and the empty pre-start state manifest.
* **The nonce-in-argv / nonce-in-environment claim is construction-level.** macOS offers no way to
  re-read a finished child's argv or environment, so `inputs.argv_env_nonce_free` is not an
  observation; `summary.json` now states this in the adjacent
  `inputs.argv_env_nonce_free_scope` field, and the file-level scans
  (`cross_world_nonce_scan_clean`, the N4 audit with `disallowed_surfaces: []` in both worlds) are
  the measured part.

## 5. Preserved failures and non-run items

| item | status | where |
| --- | --- | --- |
| attempt aborted at consumer signing | preserved with cause | `attempts/aborted-20261022-073059Z/` |
| attempt aborted at 32-hex transcription | preserved with cause | `attempts/aborted-20261022-073805Z/` |
| attempt re-executed after the identity-API refactor | preserved with cause; the earlier six-OBSERVED pass is kept verbatim | `attempts/aborted-20261022-075322Z/` |
| zero-model wiring pre-check | **not scientific evidence** — provisional trust root voided, recorded only as harness log | `preflight/README.md`, `preflight/probe-u1.json` |
| broad Swift test-suite breakage found while running the required ES-recovery tests | caused by the pre-existing `required` provenance contract plus a test-environment leak and an incomplete staged deployment bundle; repaired test-side, all three failing logs kept | `tests/README.md`, `tests/*.attempt*.log` |
| production fail-closed check for an incomplete deployment bundle | **prototyped and deliberately reverted** to keep the delivered binary identical to the one that produced the model evidence; reported as an open item instead | `tests/README.md` § "What was deliberately NOT kept" |
| 5 skipped tests in the package | remain unexecuted (G3 supervisor, real-MLX smoke, HF-snapshot diagnostics, authorized palace runtime validations) | `tests/swift-test-full-target.attempt4.log` |
| whole-package test count grew after adding the F-round identity suite | 411 → 415 tests, both states kept | `tests/swift-test-full-target.attempt3.log`, `tests/swift-test-full-target.attempt4.log` |
| no condition marked `BLOCKED_NOT_RUN` | all six scientific conditions executed and were OBSERVED | `summary.json` |
| the round's own diff set did not cover untracked files, and `source/diff-taskrun.patch` was 0 bytes while its README called it a diff | disclosed here, corrected in the closing pass by hash-verified F-round-only diffs; the 0-byte behaviour of `git diff` on untracked files is unchanged and documented | §2.6, `source/f-round-diffs/README.md` |

## 6. Open items for the next round

1. Deployment bundles must carry `settlement_provenance.py`, and the production launch should fail
   closed on a missing imported module instead of returning unparseable empty bridge output.
2. Argument/`argv` surface for the nonce was asserted clean by the runner's own construction; an
   independent `/proc`-style capture is not available on macOS, so that check is weaker than the
   file scans.
3. A release/stop-token-aware contract would remove the trailing model text after `ANSWER=`.
4. Statistical strength: repeat each condition and vary the prompt/decoding to separate causal
   linkage from luck.
